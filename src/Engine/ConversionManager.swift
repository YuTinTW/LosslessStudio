import Foundation
import Combine
import AppKit

public class ConversionManager: ObservableObject {
    public static let shared = ConversionManager()

    // MARK: - Published State

    @Published public var tasks: [ConversionTaskItem] = []
    @Published public var outputDirectory: URL
    @Published public var isProcessing: Bool = false
    @Published public var isCancelled: Bool = false
    @Published public var currentProcessingIndex: Int = 0
    @Published public var globalLogs: [String] = []
    @Published public var batchReport: BatchReport?

    // MARK: - Default Presets (音訊/圖片/視訊快速切換)
    @Published public var defaultAudioPreset: String = "flac"
    @Published public var defaultImagePreset: String = "png"
    @Published public var defaultVideoPreset: String = "mp4_remux"

    // MARK: - Concurrency Config

    /// 視訊轉碼最大並行數（FFmpeg 子行程，限制 CPU/記憶體）
    public var maxVideoWorkers: Int = 2
    /// 圖片轉換最大並行數（ImageIO，輕量可較高）
    public var maxImageWorkers: Int = 4

    // MARK: - Private & Locks

    let tasksLock = NSRecursiveLock()
    private let activeProcessesLock = NSLock()
    private var activeProcesses: [UUID: Process] = [:]

    // BLK-2 防護：原子化保留輸出路徑與鎖定，防止並行轉檔時同名檔覆蓋
    private let outputUrlLock = NSLock()
    private var reservedOutputPaths = Set<String>()

    // H-2 防護：有上限的 Probe 佇列（避免瞬間千檔匯入觸發數百個子程序）
    private lazy var probeOpQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.losslessstudio.probe"
        q.maxConcurrentOperationCount = 6
        q.qualityOfService = .utility
        return q
    }()

    private lazy var videoOpQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.losslessstudio.video"
        q.maxConcurrentOperationCount = maxVideoWorkers
        q.qualityOfService = .userInitiated
        return q
    }()

    private lazy var imageOpQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.losslessstudio.image"
        q.maxConcurrentOperationCount = maxImageWorkers
        q.qualityOfService = .userInitiated
        return q
    }()

    private lazy var audioOpQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.losslessstudio.audio"
        q.maxConcurrentOperationCount = 4
        q.qualityOfService = .userInitiated
        return q
    }()

    private var logThrottleTimer: Timer?
    private var pendingLogBuffer: [String] = []
    private let logLock = NSLock()

    public init() {
        let defaultOut = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: "/tmp")
        self.outputDirectory = defaultOut
    }

    // MARK: - Process Tracking & Cancellation

    func registerActiveProcess(taskId: UUID, process: Process) {
        activeProcessesLock.lock()
        activeProcesses[taskId] = process
        activeProcessesLock.unlock()
    }

    func unregisterActiveProcess(taskId: UUID) {
        activeProcessesLock.lock()
        activeProcesses.removeValue(forKey: taskId)
        activeProcessesLock.unlock()
    }

    // MARK: - Logging（節流更新，日誌環形上限 2000 行防止記憶體膨脹）

    public func log(_ msg: String) {
        logLock.lock()
        let timestamp = ISO8601DateFormatter().string(from: Date())
        pendingLogBuffer.append("[\(timestamp)] \(msg)")
        logLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.logThrottleTimer == nil {
                self.logThrottleTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    self.logLock.lock()
                    let batch = self.pendingLogBuffer
                    self.pendingLogBuffer.removeAll()
                    self.logLock.unlock()

                    self.globalLogs.append(contentsOf: batch)
                    if self.globalLogs.count > 2000 {
                        self.globalLogs.removeFirst(self.globalLogs.count - 2000)
                    }
                    batch.forEach { print($0) }
                    self.logThrottleTimer = nil
                }
            }
        }
    }

    // MARK: - Add Files / Folders (H-3 防護：執行中完全拒絕修改佇列)

    public func addFiles(urls: [URL]) {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        guard !isProcessing else {
            log("⚠ 批次轉檔進行中，禁止加入新檔案以保護佇列安全")
            return
        }
        let items = urls.map { url -> ConversionTaskItem in
            var item = ConversionTaskItem(url: url)
            applyDefaultPreset(to: &item)
            return item
        }
        DispatchQueue.main.async {
            self.tasks.append(contentsOf: items)
        }
        scheduleProbe(for: items)
    }

    public func addFolder(rootUrl: URL) {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        guard !isProcessing else {
            log("⚠ 批次轉檔進行中，禁止加入資料夾")
            return
        }
        guard let enumerator = FileManager.default.enumerator(
            at: rootUrl,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var items: [ConversionTaskItem] = []
        let supportedExts = Set([
            "mp4","mkv","mov","webm","avi","m4v","flv","ts","mts","m2ts","wmv","vob","3gp","ogv","mpg","mpeg",
            "png","jpg","jpeg","tiff","tif","bmp","webp","heic","heif","gif","psd","icns","dng","cr2","nef","arw",
            "wav","flac","aiff","aif","alac","m4a","mp3","aac","ogg","opus","wma","ac3","eac3","dts","m4r","caf","amr","ape","wv"
        ])
        let resolvedRoot = rootUrl.resolvingSymlinksInPath()
        for case let fileUrl as URL in enumerator {
            let ext = fileUrl.pathExtension.lowercased()
            guard supportedExts.contains(ext) else { continue }
            let resolvedFile = fileUrl.resolvingSymlinksInPath()
            let rootPath = resolvedRoot.path
            let filePath = resolvedFile.path
            let relative: String
            if filePath.hasPrefix(rootPath) {
                relative = String(filePath.dropFirst(rootPath.count)).drop(while: { $0 == "/" }).description
            } else {
                relative = fileUrl.lastPathComponent
            }
            var item = ConversionTaskItem(
                url: fileUrl,
                relativeInputPath: relative
            )
            applyDefaultPreset(to: &item)
            item.status = .inspecting
            items.append(item)
        }
        log("資料夾匯入：\(rootUrl.lastPathComponent) 找到 \(items.count) 個支援檔案")
        DispatchQueue.main.async {
            self.tasks.append(contentsOf: items)
        }
        scheduleProbe(for: items)
    }

    public func applyDefaultPreset(to item: inout ConversionTaskItem) {
        let kind = item.mediaKind
        switch kind {
        case .audio:
            item.applyPreset(id: defaultAudioPreset)
        case .image:
            item.applyPreset(id: defaultImagePreset)
        case .video:
            item.applyPreset(id: defaultVideoPreset)
        }
    }

    public func applyDefaultPresetsToPendingTasks() {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        for i in 0..<tasks.count {
            if case .pending = tasks[i].status {
                applyDefaultPreset(to: &tasks[i])
            }
        }
    }

    // H-2 防護：使用 OperationQueue 限制 Probe 最大並行數為 6
    private func scheduleProbe(for items: [ConversionTaskItem]) {
        for item in items {
            let id = item.id
            let op = BlockOperation { [weak self] in
                guard let self else { return }
                let inspection = try? FFmpegRunner.shared.probe(fileUrl: item.inputUrl)
                DispatchQueue.main.async {
                    self.tasksLock.lock()
                    defer { self.tasksLock.unlock() }
                    guard let idx = self.tasks.firstIndex(where: { $0.id == id }) else { return }
                    self.tasks[idx].inspection = inspection
                    self.tasks[idx].comparison?.inputInspection = inspection
                    if case .inspecting = self.tasks[idx].status {
                        self.tasks[idx].status = .pending
                    }
                    // 若探測後發現為純音訊（無視訊軌），自動確保目標格式為音訊專屬
                    if let insp = inspection, !insp.isImage, insp.videoCodec == nil, insp.audioCodec != nil {
                        if self.tasks[idx].category == .remux || self.tasks[idx].category == .videoLossless {
                            self.tasks[idx].applyPreset(id: self.defaultAudioPreset)
                        }
                    }
                }
            }
            probeOpQueue.addOperation(op)
        }
    }

    // MARK: - Batch Control

    public func clearTasks() {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        guard !isProcessing else { return }
        tasks.removeAll()
        outputUrlLock.lock()
        reservedOutputPaths.removeAll()
        outputUrlLock.unlock()
    }

    public func removeTask(id: UUID) {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        guard !isProcessing else { return }
        tasks.removeAll(where: { $0.id == id })
    }

    /// 取消執行中的批次：終止所有活動中的子行程並取消排程
    public func cancelBatch() {
        isCancelled = true
        videoOpQueue.cancelAllOperations()
        imageOpQueue.cancelAllOperations()
        audioOpQueue.cancelAllOperations()
        probeOpQueue.cancelAllOperations()

        // 終止所有子程序
        activeProcessesLock.lock()
        for (_, p) in activeProcesses {
            p.terminate()
        }
        activeProcesses.removeAll()
        activeProcessesLock.unlock()

        // R-4 修復：將尚未完成的所有任務標記為 cancelled，避免停滯在 pending 導致報告計數錯誤
        tasksLock.lock()
        for i in tasks.indices {
            switch tasks[i].status {
            case .pending, .processing, .inspecting:
                tasks[i].status = .cancelled
                tasks[i].comparison?.verificationStatus = .cannotVerify
                tasks[i].comparison?.verificationNote = "批次已被使用者手動取消"
            default:
                break
            }
        }
        tasksLock.unlock()

        log("已送出批次取消請求，終止進行中子行程並取消佇列。")
    }

    /// 重試失敗或被拒絕的任務
    public func retryFailed() {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        guard !isProcessing else { return }
        let failedIndices = tasks.indices.filter {
            switch tasks[$0].status {
            case .failed, .rejected, .cancelled: return true
            default: return false
            }
        }
        for idx in failedIndices {
            tasks[idx].status = .pending
            tasks[idx].comparison?.verificationStatus = .unverified
            tasks[idx].comparison?.verificationNote = "重試中"
        }

        if !failedIndices.isEmpty {
            log("重試 \(failedIndices.count) 個未完成任務")
            startBatch()
        }
    }

    // MARK: - Start Batch (BLK-1, H-1 防護)

    public func startBatch() {
        tasksLock.lock()
        guard !isProcessing else {
            tasksLock.unlock()
            return
        }
        isProcessing = true
        isCancelled = false
        batchReport = nil

        videoOpQueue.maxConcurrentOperationCount = maxVideoWorkers
        imageOpQueue.maxConcurrentOperationCount = maxImageWorkers

        let pendingIndices = tasks.indices.filter {
            if case .pending = tasks[$0].status { return true }
            return false
        }
        // H-1 防護：僅鎖定當前批次的 Task ID 集合，絕不與先前的批次重複計數
        let currentBatchTaskIds = Set(pendingIndices.map { tasks[$0].id })
        tasksLock.unlock()

        var report = BatchReport()
        report.batchId = UUID()
        report.startDate = Date()
        report.outputDirectory = outputDirectory.path
        report.total = pendingIndices.count

        log("開始批次無損轉檔：本次排程 \(pendingIndices.count) 項任務（視訊並行: \(maxVideoWorkers)，圖片並行: \(maxImageWorkers)）")

        let group = DispatchGroup()

        for idx in pendingIndices {
            guard !isCancelled else { break }
            group.enter()
            let isImage = tasks[idx].category == .imageLossless
            let op = ConversionOperation(manager: self, taskIndex: idx)
            // BLK-1 核心修復：將 group.leave() 掛在 Operation.completionBlock 上！
            // Operation 被 cancelAllOperations 取消時，其 main() 不會執行，但 completionBlock 保證觸發！
            op.completionBlock = {
                group.leave()
            }

            if isImage {
                imageOpQueue.addOperation(op)
            } else if tasks[idx].category == .audioLossless || tasks[idx].category == .audioLossy {
                audioOpQueue.addOperation(op)
            } else {
                videoOpQueue.addOperation(op)
            }
        }

        // 等候本批次結束
        DispatchQueue.global(qos: .utility).async { [weak self] in
            group.wait()
            guard let self else { return }

            DispatchQueue.main.async {
                self.tasksLock.lock()
                defer { self.tasksLock.unlock() }

                report.endDate = Date()
                let batchTasks = self.tasks.filter { currentBatchTaskIds.contains($0.id) }
                report.succeeded = batchTasks.filter { if case .completed = $0.status { return true }; return false }.count
                report.failed    = batchTasks.filter { if case .failed    = $0.status { return true }; return false }.count
                report.rejected  = batchTasks.filter { if case .rejected  = $0.status { return true }; return false }.count
                report.cancelled = batchTasks.filter { if case .cancelled = $0.status { return true }; return false }.count

                for t in batchTasks {
                    let note = t.comparison?.verificationNote ?? t.status.displayText
                    report.taskDetails.append((name: t.inputUrl.lastPathComponent, status: t.status.displayText, note: note))
                }

                self.writeBatchReport(report)
                self.isProcessing = false
                self.batchReport = report
                self.log(report.summary)
            }
        }
    }

    // MARK: - Safe Output URL (BLK-2 核心修復：原子化加鎖與預約機制)

    public func generateSafeOutputUrl(inputUrl: URL, targetExt: String, relativePath: String?) -> URL {
        outputUrlLock.lock()
        defer { outputUrlLock.unlock() }

        let cleanExt = targetExt.replacingOccurrences(of: ".", with: "").lowercased()
        let baseName = inputUrl.deletingPathExtension().lastPathComponent

        let relativeDir: String
        if let rel = relativePath {
            let relUrl = URL(fileURLWithPath: rel)
            relativeDir = relUrl.deletingLastPathComponent().relativePath
        } else {
            relativeDir = ""
        }

        let targetDir = relativeDir.isEmpty || relativeDir == "."
            ? outputDirectory
            : outputDirectory.appendingPathComponent(relativeDir)

        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        var candidate = targetDir.appendingPathComponent("\(baseName)_lossless.\(cleanExt)")
        var counter = 1
        while FFmpegRunner.isSameFile(url1: inputUrl, url2: candidate)
            || FileManager.default.fileExists(atPath: candidate.path)
            || reservedOutputPaths.contains(candidate.path) {
            candidate = targetDir.appendingPathComponent("\(baseName)_lossless_\(counter).\(cleanExt)")
            counter += 1
        }
        // 立即記錄保留，防止併發中的其他工作搶佔同名
        reservedOutputPaths.insert(candidate.path)
        return candidate
    }

    // H-1 防護：檔名加入高精度毫秒與 UUID 避免同秒覆蓋
    private func writeBatchReport(_ report: BatchReport) {
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        let reportUrl = outputDirectory.appendingPathComponent("LosslessStudio_BatchReport_\(ms)_\(report.batchId.uuidString.prefix(6)).txt")
        try? report.summary.write(to: reportUrl, atomically: true, encoding: .utf8)
        log("批次報告已輸出：\(reportUrl.path)")
    }

    // MARK: - Export Verification Report

    public func exportVerificationReport() -> URL? {
        tasksLock.lock()
        defer { tasksLock.unlock() }

        var lines: [String] = []
        lines.append("================================================================================")
        lines.append("LosslessStudio 前後編碼對照與完整無損驗證報告")
        lines.append("產出時間：\(ISO8601DateFormatter().string(from: Date()))")
        lines.append("總任務數：\(tasks.count)")
        lines.append("================================================================================\n")

        for (i, t) in tasks.enumerated() {
            lines.append("--- [任務 \(i + 1)] \(t.inputUrl.lastPathComponent) ---")
            lines.append("模式：\(t.category.rawValue)")
            lines.append("狀態：\(t.status.displayText)")
            if let cmd = t.executionCommand {
                lines.append("執行指令參數：\(cmd)")
            }
            if let cmp = t.comparison {
                lines.append("來源規格 (真實探測)：")
                if let inp = cmp.inputInspection {
                    lines.append("  容器: \(inp.formatName), 串流數: \(inp.streams.count)")
                    for s in inp.streams {
                        lines.append("    [Stream #\(s.index) \(s.codecType)] 編碼: \(s.codecName ?? "未知"), Profile: \(s.profile ?? "無"), 像素格式: \(s.pixelFormat ?? "無"), 解析度: \(s.resolution ?? "無"), 幀率: \(s.frameRate ?? "未知"), 取樣率: \(s.sampleRate != nil ? "\(s.sampleRate!)Hz" : "無"), 聲道: \(s.channels != nil ? "\(s.channels!)" : "無")")
                    }
                } else {
                    lines.append("  尚未探測")
                }
                lines.append("輸出規格 (產物真實再探測，絕不捏造)：")
                if let out = cmp.outputInspection {
                    lines.append("  容器: \(out.formatName), 串流數: \(out.streams.count)")
                    for s in out.streams {
                        lines.append("    [Stream #\(s.index) \(s.codecType)] 編碼: \(s.codecName ?? "未知"), Profile: \(s.profile ?? "無"), 像素格式: \(s.pixelFormat ?? "無"), 解析度: \(s.resolution ?? "無"), 幀率: \(s.frameRate ?? "未知"), 取樣率: \(s.sampleRate != nil ? "\(s.sampleRate!)Hz" : "無"), 聲道: \(s.channels != nil ? "\(s.channels!)" : "無")")
                    }
                } else {
                    lines.append("  尚未產出 (規劃中)")
                }
                lines.append("無損比對狀態：\(cmp.verificationStatus.rawValue)")
                lines.append("驗證詳細說明：\(cmp.verificationNote)")
                if let ih = cmp.inputHash, let oh = cmp.outputHash {
                    lines.append("  來源 Hash: \(ih)")
                    lines.append("  輸出 Hash: \(oh)")
                }
            }
            if let err = t.lastStderr, !err.isEmpty {
                lines.append("執行 Stderr：\n\(err)")
            }
            lines.append("\n")
        }

        let fullText = lines.joined(separator: "\n")
        let saveUrl = outputDirectory.appendingPathComponent("LosslessStudio_VerificationReport_\(Int(Date().timeIntervalSince1970 * 1000)).txt")
        do {
            try fullText.write(to: saveUrl, atomically: true, encoding: .utf8)
            log("編碼驗證對照報告已匯出：\(saveUrl.path)")
            return saveUrl
        } catch {
            log("匯出報告失敗：\(error.localizedDescription)")
            return nil
        }
    }

    private func defaultCategory(for url: URL) -> ConversionCategory {
        let ext = url.pathExtension.lowercased()
        if ["png","jpg","jpeg","tiff","tif","bmp","webp","heic"].contains(ext) {
            return .imageLossless
        }
        if ["wav","flac","aiff","aif"].contains(ext) {
            return .audioLossless
        }
        if ["mp3","aac","ogg","opus","wma"].contains(ext) {
            return .audioLossy
        }
        return .remux
    }

    private func defaultContainer(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ["png","jpg","jpeg","tiff","tif","bmp","webp","heic"].contains(ext) {
            return ext == "png" ? "tiff" : "png"
        }
        if ["wav","flac","aiff","aif"].contains(ext) {
            return ext == "wav" ? "flac" : "wav"
        }
        if ["mp3","aac","ogg","opus","wma"].contains(ext) {
            return ext == "mp3" ? "m4a" : "mp3"
        }
        return ext == "mkv" ? "mp4" : "mkv"
    }
}

// MARK: - ConversionOperation

final class ConversionOperation: Operation, @unchecked Sendable {
    private weak var manager: ConversionManager?
    private let taskIndex: Int

    init(manager: ConversionManager, taskIndex: Int) {
        self.manager = manager
        self.taskIndex = taskIndex
        super.init()
    }

    override func main() {
        guard let mgr = manager else { return }
        guard !isCancelled && !mgr.isCancelled else {
            DispatchQueue.main.async {
                mgr.tasksLock.lock()
                defer { mgr.tasksLock.unlock() }
                mgr.tasks[self.taskIndex].status = .cancelled
                mgr.tasks[self.taskIndex].comparison?.verificationStatus = .cannotVerify
                mgr.tasks[self.taskIndex].comparison?.verificationNote = "批次已被取消"
            }
            return
        }

        let item = mgr.tasks[taskIndex]
        let taskId = item.id

        DispatchQueue.main.async {
            mgr.tasks[self.taskIndex].status = .processing(progress: 0.05, speed: "計算中", eta: "預估中")
            mgr.currentProcessingIndex = self.taskIndex
        }

        let start = Date()
        mgr.log("處理中 [\(taskIndex + 1)/\(mgr.tasks.count)]: \(item.inputUrl.lastPathComponent)")

        var finalOutputUrl: URL?

        do {
            let outputUrl = mgr.generateSafeOutputUrl(
                inputUrl: item.inputUrl,
                targetExt: item.outputContainer,
                relativePath: item.relativeInputPath
            )
            finalOutputUrl = outputUrl

            var executionCmd = ""

            switch item.category {
            case .remux:
                // M1 防護：如果 inspection 為 nil，強制即時 probe，絕不跳過檢查
                let insp: MediaInspectionResult
                if let existing = item.inspection {
                    insp = existing
                } else {
                    insp = try FFmpegRunner.shared.probe(fileUrl: item.inputUrl)
                    DispatchQueue.main.async { mgr.tasks[self.taskIndex].inspection = insp }
                }

                let check = LosslessLimitations.canRemux(
                    videoCodec: insp.videoCodec,
                    audioCodec: insp.audioCodec,
                    targetContainer: item.outputContainer
                )
                if !check.allowed {
                    DispatchQueue.main.async {
                        mgr.tasks[self.taskIndex].status = .rejected(reason: check.reason)
                        mgr.tasks[self.taskIndex].comparison?.verificationStatus = .cannotVerify
                        mgr.tasks[self.taskIndex].comparison?.verificationNote = "拒絕直通: \(check.reason)"
                    }
                    mgr.log("拒絕直通: \(check.reason)")
                    return
                }

                executionCmd = "ffmpeg -nostdin -y -i \"\(item.inputUrl.path)\" -c copy -map 0 -map_metadata 0 \"\(outputUrl.path)\""
                try FFmpegRunner.shared.executeRemux(
                    inputUrl: item.inputUrl,
                    outputUrl: outputUrl,
                    processObserver: { [weak mgr] p in
                        mgr?.registerActiveProcess(taskId: taskId, process: p)
                    },
                    onProgress: { [weak mgr] p, sp, et in
                        DispatchQueue.main.async {
                            mgr?.tasks[self.taskIndex].status = .processing(progress: p, speed: sp, eta: et)
                        }
                    }
                )

            case .videoLossless:
                let ext = outputUrl.pathExtension.lowercased()
                if ext == "mov" {
                    executionCmd = "ffmpeg -nostdin -y -i \"\(item.inputUrl.path)\" -map 0 -c:v prores_ks -profile:v 5 -vendor apl0 -bits_per_mb 8000 -c:a pcm_s24le \"\(outputUrl.path)\""
                } else if ext == "mkv" {
                    executionCmd = "ffmpeg -nostdin -y -i \"\(item.inputUrl.path)\" -map 0 -c:v ffv1 -level 3 -g 1 -c:a flac \"\(outputUrl.path)\""
                } else {
                    executionCmd = "ffmpeg -nostdin -y -i \"\(item.inputUrl.path)\" -map 0 -c:v libx264 -crf 0 -preset medium -c:a alac \"\(outputUrl.path)\""
                }

                try FFmpegRunner.shared.executeLosslessTranscode(
                    inputUrl: item.inputUrl,
                    outputUrl: outputUrl,
                    processObserver: { [weak mgr] p in
                        mgr?.registerActiveProcess(taskId: taskId, process: p)
                    },
                    onProgress: { [weak mgr] p, sp, et in
                        DispatchQueue.main.async {
                            mgr?.tasks[self.taskIndex].status = .processing(progress: p, speed: sp, eta: et)
                        }
                    }
                )

            case .imageLossless:
                executionCmd = "ImageLosslessEngine.convertImageLossless"
                try ImageLosslessEngine.shared.convertImageLossless(inputUrl: item.inputUrl, outputUrl: outputUrl)

            case .imageLossy:
                let q = (item.currentPresetId == "jpg_80" || item.currentPresetId == "webp_85") ? 0.80 : 0.95
                executionCmd = "ImageLosslessEngine.convertImageLossy(quality: \(q))"
                try ImageLosslessEngine.shared.convertImageLossy(inputUrl: item.inputUrl, outputUrl: outputUrl, quality: q)

            case .audioLossless:
                let outExt = outputUrl.pathExtension.lowercased()
                executionCmd = "ffmpeg -nostdin -y -i \"\(item.inputUrl.path)\" -vn -sn (audioLossless: .\(outExt)) \"\(outputUrl.path)\""
                try FFmpegRunner.shared.executeAudioLossless(
                    inputUrl: item.inputUrl,
                    outputUrl: outputUrl,
                    targetBitDepth: item.audioBitDepth,
                    targetSampleRate: item.audioSampleRate,
                    processObserver: { [weak mgr] p in
                        mgr?.registerActiveProcess(taskId: taskId, process: p)
                    },
                    onProgress: { [weak mgr] p, sp, et in
                        DispatchQueue.main.async {
                            mgr?.tasks[self.taskIndex].status = .processing(progress: p, speed: sp, eta: et)
                        }
                    }
                )

            case .audioLossy:
                let outExt = outputUrl.pathExtension.lowercased()
                let br = item.audioBitrate ?? "320k"
                executionCmd = "ffmpeg -nostdin -y -i \"\(item.inputUrl.path)\" -vn -sn (audioLossy: .\(outExt) @ \(br)) \"\(outputUrl.path)\""
                try FFmpegRunner.shared.executeAudioLossy(
                    inputUrl: item.inputUrl,
                    outputUrl: outputUrl,
                    bitrate: br,
                    targetSampleRate: item.audioSampleRate,
                    targetBitDepth: item.audioBitDepth,
                    processObserver: { [weak mgr] p in
                        mgr?.registerActiveProcess(taskId: taskId, process: p)
                    },
                    onProgress: { [weak mgr] p, sp, et in
                        DispatchQueue.main.async {
                            mgr?.tasks[self.taskIndex].status = .processing(progress: p, speed: sp, eta: et)
                        }
                    }
                )
            }

            mgr.unregisterActiveProcess(taskId: taskId)

            // ── 轉檔完成後：重新真實探測產物並執行無損比對驗證 ──
            var comparison = mgr.tasks[self.taskIndex].comparison ?? EncodingComparison(inputUrl: item.inputUrl, category: item.category)
            comparison.outputUrl = outputUrl
            comparison.executionArgs = [executionCmd]

            let outInspection = try? FFmpegRunner.shared.probe(fileUrl: outputUrl)
            comparison.outputInspection = outInspection

            // 執行客觀比對驗證 (R-1, R-2 嚴格修復)
            switch item.category {
            case .remux:
                let verify = FFmpegRunner.shared.verifyRemux(inputUrl: item.inputUrl, outputUrl: outputUrl)
                comparison.inputHash = verify.inputVideoHash ?? verify.inputAudioHash
                comparison.outputHash = verify.outputVideoHash ?? verify.outputAudioHash

                if verify.allMatched {
                    comparison.verificationStatus = .passed
                    comparison.verificationNote = "串流直通封裝驗證通過：\(verify.note)"
                } else {
                    let hasMismatch = (verify.videoHashMatch == false && verify.inputVideoHash != nil && verify.outputVideoHash != nil) ||
                                      (verify.audioHashMatch == false && verify.inputAudioHash != nil && verify.outputAudioHash != nil)
                    if hasMismatch {
                        comparison.verificationStatus = .mismatch
                        comparison.verificationNote = "位元流比對失敗（不吻合）：\(verify.note)"
                    } else {
                        comparison.verificationStatus = .cannotVerify
                        comparison.verificationNote = "未能完整提取所有串流之位元流 MD5 進行校驗：\(verify.note)"
                    }
                }

            case .videoLossless:
                let outExt = outputUrl.pathExtension.lowercased()
                if outExt == "mov" {
                    comparison.verificationStatus = .visualLossless
                    comparison.verificationNote = "視覺級極限近似無損 (ProRes 4444 XQ 12-bit，非數學像素無損)，含微量量化誤差。"
                } else {
                    let inPixelMd5 = FFmpegRunner.shared.computeRawVideoMd5(fileUrl: item.inputUrl, maxFrames: 20)
                    let outPixelMd5 = FFmpegRunner.shared.computeRawVideoMd5(fileUrl: outputUrl, maxFrames: 20)
                    comparison.inputHash = inPixelMd5
                    comparison.outputHash = outPixelMd5

                    if let ip = inPixelMd5, let op = outPixelMd5 {
                        if ip == op {
                            comparison.verificationStatus = .passed
                            comparison.verificationNote = "解碼前 20 幀 RGB 像素 MD5 (\(ip)) 完全一致，數學級無損。"
                        } else {
                            comparison.verificationStatus = .mismatch
                            comparison.verificationNote = "解碼點陣像素 MD5 不吻合（來源: \(ip) vs 產物: \(op)），檢測到數據差異。"
                        }
                    } else {
                        comparison.verificationStatus = .cannotVerify
                        comparison.verificationNote = "未能提取解碼像素進行 MD5 校驗。"
                    }
                }

            case .imageLossless:
                let inPix = ImageLosslessEngine.shared.computePixelMd5(fileUrl: item.inputUrl)
                let outPix = ImageLosslessEngine.shared.computePixelMd5(fileUrl: outputUrl)
                comparison.inputHash = inPix
                comparison.outputHash = outPix

                if let ip = inPix, let op = outPix {
                    if ip == op {
                        comparison.verificationStatus = .passed
                        comparison.verificationNote = "點陣 RGBA 像素 1:1 完全一致（MD5: \(ip)）。"
                    } else {
                        comparison.verificationStatus = .mismatch
                        comparison.verificationNote = "點陣 RGBA 像素比對不一致（來源: \(ip) vs 產物: \(op)），檢測到圖像差異！"
                    }
                } else {
                    comparison.verificationStatus = .cannotVerify
                    comparison.verificationNote = "未能提取點陣像素雜湊進行校驗。"
                }

            case .imageLossy:
                comparison.verificationStatus = .lossyConversion
                comparison.verificationNote = "有損圖片壓縮格式（JPEG/WebP 高效），採用視覺量化演算法，不進行像素比對。"

            case .audioLossless:
                let inInsp = try? FFmpegRunner.shared.probe(fileUrl: item.inputUrl)
                let depth = item.audioBitDepth ?? inInsp?.streams.first(where: { $0.codecType == "audio" })?.bitDepth ?? 16
                let pcmCodec = (depth >= 24) ? "pcm_s24le" : "pcm_s16le"
                let inPcm = FFmpegRunner.shared.computeAudioPcmMd5(fileUrl: item.inputUrl, pcmCodec: pcmCodec)
                let outPcm = FFmpegRunner.shared.computeAudioPcmMd5(fileUrl: outputUrl, pcmCodec: pcmCodec)
                comparison.inputHash = inPcm
                comparison.outputHash = outPcm

                if let ip = inPcm, let op = outPcm {
                    if ip == op {
                        comparison.verificationStatus = .passed
                        comparison.verificationNote = "解碼 PCM 音訊取樣完全一致（MD5: \(ip)），100% 數學無損互轉。"
                    } else {
                        comparison.verificationStatus = .mismatch
                        comparison.verificationNote = "解碼 PCM 音訊取樣雜湊不一致（來源: \(ip) vs 產物: \(op)），檢測到波形差異！"
                    }
                } else {
                    comparison.verificationStatus = .cannotVerify
                    comparison.verificationNote = "未能提取 PCM 音訊雜湊進行校驗。"
                }

            case .audioLossy:
                let br = item.audioBitrate ?? "320k"
                let sr = item.audioSampleRate != nil ? "\(item.audioSampleRate!)Hz" : "保留來源取樣率"
                comparison.verificationStatus = .lossyConversion
                comparison.verificationNote = "有損音訊轉換／降轉模式（碼率: \(br), 取樣率: \(sr)），採用心理聲學量化，不進行位元比對。"
            }

            let duration = Date().timeIntervalSince(start)
            DispatchQueue.main.async {
                mgr.tasks[self.taskIndex].status = .completed(outputUrl: outputUrl, duration: duration)
                mgr.tasks[self.taskIndex].outputInspection = outInspection
                mgr.tasks[self.taskIndex].comparison = comparison
                mgr.tasks[self.taskIndex].executionCommand = executionCmd
            }
            mgr.log("完成: \(outputUrl.lastPathComponent) (耗時 \(String(format: "%.2f", duration))s) [\(comparison.verificationStatus.rawValue)]")

        } catch {
            mgr.unregisterActiveProcess(taskId: taskId)
            if let out = finalOutputUrl {
                try? FileManager.default.removeItem(at: out)
            }
            DispatchQueue.main.async {
                mgr.tasks[self.taskIndex].status = .failed(error: error.localizedDescription)
                mgr.tasks[self.taskIndex].comparison?.verificationStatus = .cannotVerify
                mgr.tasks[self.taskIndex].comparison?.verificationNote = "失敗: \(error.localizedDescription)"
                mgr.tasks[self.taskIndex].lastStderr = error.localizedDescription
            }
            mgr.log("失敗: \(item.inputUrl.lastPathComponent) — \(error.localizedDescription)")
        }
    }
}
