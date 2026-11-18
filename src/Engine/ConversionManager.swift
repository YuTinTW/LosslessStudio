import Foundation
import Combine
import AppKit
import PDFKit

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

    // MARK: - Default Presets (音訊/圖片/視訊/文件快速切換)
    @Published public var defaultAudioPreset: String = "flac"
    @Published public var defaultImagePreset: String = "png"
    @Published public var defaultVideoPreset: String = "mp4_remux"
    @Published public var defaultDocumentPreset: String = "pdf_to_png"

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
            log(L10n.text(L10n.text("⚠ 批次轉檔進行中，禁止加入新檔案以保護佇列安全", "⚠ Wait for the current batch to finish before adding files."), "⚠ Wait for the current batch to finish before adding files."))
            return
        }
        let officeExts = Set(["docx","doc","xlsx","xls","pptx","ppt","pages","numbers","key"])
        let items = urls.map { url -> ConversionTaskItem in
            var item = ConversionTaskItem(url: url)
            if officeExts.contains(url.pathExtension.lowercased()) {
                item.status = .rejected(reason: L10n.text(L10n.text("本軟體為純輕量自包含架構，不支援 Office 文件 (.docx, .xlsx 等)；如需轉檔 PDF 請使用「圖片轉 PDF」功能。", "Office documents such as .docx and .xlsx are unsupported. Use Image to PDF to convert supported images."), "Office documents such as .docx and .xlsx are unsupported. Use Image to PDF to convert supported images."))
            } else {
                applyDefaultPreset(to: &item)
            }
            return item
        }
        DispatchQueue.main.async {
            self.tasks.append(contentsOf: items)
        }
        scheduleProbe(for: items.filter {
            if case .rejected = $0.status { return false }
            return true
        })
    }

    public func addFolder(rootUrl: URL) {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        guard !isProcessing else {
            log(L10n.text(L10n.text("⚠ 批次轉檔進行中，禁止加入資料夾", "⚠ Wait for the current batch to finish before adding folders."), "⚠ Wait for the current batch to finish before adding folders."))
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
            "wav","flac","aiff","aif","alac","m4a","mp3","aac","ogg","opus","wma","ac3","eac3","dts","m4r","caf","amr","ape","wv",
            "pdf"
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
        log(L10n.text(L10n.text("資料夾匯入：\(rootUrl.lastPathComponent) 找到 \(items.count) 個支援檔案", "Found \(items.count) supported files in \(rootUrl.lastPathComponent)."), "Found \(items.count) supported files in \(rootUrl.lastPathComponent)."))
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
        case .document:
            item.applyPreset(id: defaultDocumentPreset)
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
                var pdfPages: Int? = nil
                if item.inputUrl.pathExtension.lowercased() == "pdf" {
                    if let doc = PDFDocument(url: item.inputUrl) {
                        pdfPages = doc.pageCount
                    }
                }
                DispatchQueue.main.async {
                    self.tasksLock.lock()
                    defer { self.tasksLock.unlock() }
                    guard let idx = self.tasks.firstIndex(where: { $0.id == id }) else { return }
                    if let count = pdfPages {
                        self.tasks[idx].pdfPageCount = count
                    }
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
                tasks[i].comparison?.verificationStatus = .unverified
                tasks[i].comparison?.verificationNote = L10n.text(L10n.text("批次已被使用者手動取消", "The user canceled the batch."), "The user canceled the batch.")
            default:
                break
            }
        }
        tasksLock.unlock()

        log(L10n.text(L10n.text("已送出批次取消請求，終止進行中子行程並取消佇列。", "Batch cancellation requested. Active processes and queued jobs are being stopped."), "Batch cancellation requested. Active processes and queued jobs are being stopped."))
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
            tasks[idx].comparison?.verificationNote = L10n.text(L10n.text("重試中", "Retrying"), "Retrying")
        }

        if !failedIndices.isEmpty {
            log(L10n.text(L10n.text("重試 \(failedIndices.count) 個未完成任務", "Retrying \(failedIndices.count) unfinished jobs."), "Retrying \(failedIndices.count) unfinished jobs."))
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

        log(L10n.text(L10n.text("開始批次無損轉檔：本次排程 \(pendingIndices.count) 項任務（視訊並行: \(maxVideoWorkers)，圖片並行: \(maxImageWorkers)）", "Starting \(pendingIndices.count) jobs (up to \(maxVideoWorkers) video and \(maxImageWorkers) image jobs at a time)."), "Starting \(pendingIndices.count) jobs (up to \(maxVideoWorkers) video and \(maxImageWorkers) image jobs at a time)."))

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
        log(L10n.text(L10n.text("批次報告已輸出：\(reportUrl.path)", "Batch report saved to \(reportUrl.path)."), "Batch report saved to \(reportUrl.path)."))
    }

    // MARK: - Export Verification Report

    public func exportVerificationReport() -> URL? {
        tasksLock.lock()
        defer { tasksLock.unlock() }

        var lines: [String] = []
        lines.append("================================================================================")
        lines.append(L10n.text(L10n.text("LosslessStudio 前後編碼對照與完整無損驗證報告", "LosslessStudio encoding comparison and verification report"), "LosslessStudio encoding comparison and verification report"))
        lines.append(L10n.text(L10n.text("產出時間：\(ISO8601DateFormatter().string(from: Date()))", "Generated \(ISO8601DateFormatter().string(from: Date()))"), "Generated \(ISO8601DateFormatter().string(from: Date()))"))
        lines.append(L10n.text(L10n.text("總任務數：\(tasks.count)", "Total jobs: \(tasks.count)"), "Total jobs: \(tasks.count)"))
        lines.append("================================================================================\n")

        for (i, t) in tasks.enumerated() {
            lines.append(L10n.text(L10n.text("--- [任務 \(i + 1)] \(t.inputUrl.lastPathComponent) ---", "--- [Job \(i + 1)] \(t.inputUrl.lastPathComponent) ---"), "--- [Job \(i + 1)] \(t.inputUrl.lastPathComponent) ---"))
            lines.append(L10n.text("模式：\(t.category.displayName)", "Mode: \(t.category.displayName)"))
            lines.append(L10n.text(L10n.text("狀態：\(t.status.displayText)", "Status: \(t.status.displayText)"), "Status: \(t.status.displayText)"))
            if let cmd = t.executionCommand {
                lines.append(L10n.text(L10n.text("執行指令參數：\(cmd)", "Command arguments: \(cmd)"), "Command arguments: \(cmd)"))
            }
            if let cmp = t.comparison {
                lines.append(L10n.text(L10n.text("來源規格 (真實探測)：", "Source stream information:"), "Source stream information:"))
                if let inp = cmp.inputInspection {
                    lines.append(L10n.text(L10n.text("  容器: \(inp.formatName), 串流數: \(inp.streams.count)", "  Container: \(inp.formatName), streams: \(inp.streams.count)"), "  Container: \(inp.formatName), streams: \(inp.streams.count)"))
                    for s in inp.streams {
                        lines.append(L10n.text(L10n.text("    [Stream #\(s.index) \(s.codecType)] 編碼: \(s.codecName ?? "未知"), Profile: \(s.profile ?? "無"), 像素格式: \(s.pixelFormat ?? "無"), 解析度: \(s.resolution ?? "無"), 幀率: \(s.frameRate ?? "未知"), 取樣率: \(s.sampleRate != nil ? "\(s.sampleRate!)Hz" : "無"), 聲道: \(s.channels != nil ? "\(s.channels!)" : "無")", "    [Stream #\(s.index) \(s.codecType)] Codec: \(s.codecName ?? "Unknown"), profile: \(s.profile ?? "N/A"), pixel format: \(s.pixelFormat ?? "N/A"), resolution: \(s.resolution ?? "N/A"), frame rate: \(s.frameRate ?? "Unknown"), sample rate: \(s.sampleRate != nil ? "\(s.sampleRate!)Hz" : "N/A"), channels: \(s.channels != nil ? "\(s.channels!)" : "N/A")"), "    [Stream #\(s.index) \(s.codecType)] Codec: \(s.codecName ?? "Unknown"), profile: \(s.profile ?? "N/A"), pixel format: \(s.pixelFormat ?? "N/A"), resolution: \(s.resolution ?? "N/A"), frame rate: \(s.frameRate ?? "Unknown"), sample rate: \(s.sampleRate != nil ? "\(s.sampleRate!)Hz" : "N/A"), channels: \(s.channels != nil ? "\(s.channels!)" : "N/A")"))
                    }
                } else {
                    lines.append(L10n.text(L10n.text("  尚未探測", "  Source stream information unavailable"), "  Source stream information unavailable"))
                }
                lines.append(L10n.text(L10n.text("輸出規格 (產物真實再探測，絕不捏造)：", "Output stream information:"), "Output stream information:"))
                if let out = cmp.outputInspection {
                    lines.append(L10n.text(L10n.text("  容器: \(out.formatName), 串流數: \(out.streams.count)", "  Container: \(out.formatName), streams: \(out.streams.count)"), "  Container: \(out.formatName), streams: \(out.streams.count)"))
                    for s in out.streams {
                        lines.append(L10n.text(L10n.text("    [Stream #\(s.index) \(s.codecType)] 編碼: \(s.codecName ?? "未知"), Profile: \(s.profile ?? "無"), 像素格式: \(s.pixelFormat ?? "無"), 解析度: \(s.resolution ?? "無"), 幀率: \(s.frameRate ?? "未知"), 取樣率: \(s.sampleRate != nil ? "\(s.sampleRate!)Hz" : "無"), 聲道: \(s.channels != nil ? "\(s.channels!)" : "無")", "    [Stream #\(s.index) \(s.codecType)] Codec: \(s.codecName ?? "Unknown"), profile: \(s.profile ?? "N/A"), pixel format: \(s.pixelFormat ?? "N/A"), resolution: \(s.resolution ?? "N/A"), frame rate: \(s.frameRate ?? "Unknown"), sample rate: \(s.sampleRate != nil ? "\(s.sampleRate!)Hz" : "N/A"), channels: \(s.channels != nil ? "\(s.channels!)" : "N/A")"), "    [Stream #\(s.index) \(s.codecType)] Codec: \(s.codecName ?? "Unknown"), profile: \(s.profile ?? "N/A"), pixel format: \(s.pixelFormat ?? "N/A"), resolution: \(s.resolution ?? "N/A"), frame rate: \(s.frameRate ?? "Unknown"), sample rate: \(s.sampleRate != nil ? "\(s.sampleRate!)Hz" : "N/A"), channels: \(s.channels != nil ? "\(s.channels!)" : "N/A")"))
                    }
                } else {
                    lines.append(L10n.text(L10n.text("  尚未產出 (規劃中)", "  Output stream information unavailable"), "  Output stream information unavailable"))
                }
                lines.append(L10n.text("無損比對狀態：\(cmp.verificationStatus.displayText)", "Verification status: \(cmp.verificationStatus.displayText)"))
                lines.append(L10n.text(L10n.text("驗證詳細說明：\(cmp.verificationNote)", "Verification details: \(cmp.verificationNote)"), "Verification details: \(cmp.verificationNote)"))
                if let ih = cmp.inputHash, let oh = cmp.outputHash {
                    lines.append(L10n.text(L10n.text("  來源 Hash: \(ih)", "  Source hash: \(ih)"), "  Source hash: \(ih)"))
                    lines.append(L10n.text(L10n.text("  輸出 Hash: \(oh)", "  Output hash: \(oh)"), "  Output hash: \(oh)"))
                }
            }
            if let err = t.lastStderr, !err.isEmpty {
                lines.append(L10n.text(L10n.text("執行 Stderr：\n\(err)", "Process diagnostics:\n\(err)"), "Process diagnostics:\n\(err)"))
            }
            lines.append("\n")
        }

        let fullText = lines.joined(separator: "\n")
        let saveUrl = outputDirectory.appendingPathComponent("LosslessStudio_VerificationReport_\(Int(Date().timeIntervalSince1970 * 1000)).txt")
        do {
            try fullText.write(to: saveUrl, atomically: true, encoding: .utf8)
            log(L10n.text(L10n.text("編碼驗證對照報告已匯出：\(saveUrl.path)", "Verification report exported to \(saveUrl.path)."), "Verification report exported to \(saveUrl.path)."))
            return saveUrl
        } catch {
            log(L10n.text(L10n.text("匯出報告失敗：\(error.localizedDescription)", "Could not export the report. \(error.localizedDescription)"), "Could not export the report. \(error.localizedDescription)"))
            return nil
        }
    }

    private func defaultCategory(for url: URL) -> ConversionCategory {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            return .document
        }
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
        if ext == "pdf" {
            return "png"
        }
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
                mgr.tasks[self.taskIndex].comparison?.verificationStatus = .unverified
                mgr.tasks[self.taskIndex].comparison?.verificationNote = L10n.text(L10n.text("批次已被取消", "The batch was canceled."), "The batch was canceled.")
            }
            return
        }

        let item = mgr.tasks[taskIndex]
        let taskId = item.id

        DispatchQueue.main.async {
            mgr.tasks[self.taskIndex].status = .processing(progress: 0.05, speed: L10n.text(L10n.text("計算中", "Calculating"), "Calculating"), eta: L10n.text(L10n.text("預估中", "Estimating"), "Estimating"))
            mgr.currentProcessingIndex = self.taskIndex
        }

        let start = Date()
        mgr.log(L10n.text(L10n.text("處理中 [\(taskIndex + 1)/\(mgr.tasks.count)]: \(item.inputUrl.lastPathComponent)", "Processing [\(taskIndex + 1)/\(mgr.tasks.count)]: \(item.inputUrl.lastPathComponent)"), "Processing [\(taskIndex + 1)/\(mgr.tasks.count)]: \(item.inputUrl.lastPathComponent)"))

        var finalOutputUrl: URL?

        do {
            let outputUrl = mgr.generateSafeOutputUrl(
                inputUrl: item.inputUrl,
                targetExt: item.outputContainer,
                relativePath: item.relativeInputPath
            )
            finalOutputUrl = outputUrl

            var executionCmd = ""
            var taskOutputUrls: [URL] = []
            var comparison = mgr.tasks[self.taskIndex].comparison ?? EncodingComparison(inputUrl: item.inputUrl, category: item.category)

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
                if check.allowed {
                    executionCmd = "ffmpeg -nostdin -y -i \"\(item.inputUrl.path)\" -c copy -map 0:v? -map 0:a? -dn -map_metadata 0 \"\(outputUrl.path)\""
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
                } else if check.canCopyVideo && check.needsAudioTranscode {
                    let audioCodec = check.fallbackAudioCodec ?? "aac"
                    let audioBitrate = check.fallbackAudioBitrate ?? "320k"
                    executionCmd = "ffmpeg -nostdin -y -i \"\(item.inputUrl.path)\" -c:v copy -c:a \(audioCodec) -b:a \(audioBitrate) -map 0:v? -map 0:a? -dn -map_metadata 0 \"\(outputUrl.path)\""
                    try FFmpegRunner.shared.executeRemux(
                        inputUrl: item.inputUrl,
                        outputUrl: outputUrl,
                        customAudioCodec: audioCodec,
                        customAudioBitrate: audioBitrate,
                        processObserver: { [weak mgr] p in
                            mgr?.registerActiveProcess(taskId: taskId, process: p)
                        },
                        onProgress: { [weak mgr] p, sp, et in
                            DispatchQueue.main.async {
                                mgr?.tasks[self.taskIndex].status = .processing(progress: p, speed: sp, eta: et)
                            }
                        }
                    )
                    comparison.verificationStatus = .disqualified
                    let note = L10n.text(
                        "視訊位元直通保全，音訊因 \(item.outputContainer.uppercased()) 容器規範自動轉為高品質 \(audioCodec.uppercased())",
                        "Video bitstream preserved; audio converted to high-quality \(audioCodec.uppercased()) per \(item.outputContainer.uppercased()) standard"
                    )
                    comparison.verificationNote = note
                    comparison.qualificationReasons = [note]
                } else {
                    let target = item.outputContainer.lowercased()
                    executionCmd = "ffmpeg -nostdin -y -i \"\(item.inputUrl.path)\" -map 0:v? -map 0:a? -dn (相容轉碼至 .\(target)) \"\(outputUrl.path)\""
                    try FFmpegRunner.shared.executeLosslessTranscode(
                        inputUrl: item.inputUrl,
                        outputUrl: outputUrl,
                        compatibleMode: true,
                        processObserver: { [weak mgr] p in mgr?.registerActiveProcess(taskId: taskId, process: p) },
                        onProgress: { [weak mgr] p, sp, et in
                            DispatchQueue.main.async { mgr?.tasks[self.taskIndex].status = .processing(progress: p, speed: sp, eta: et) }
                        }
                    )
                    comparison.verificationStatus = .disqualified
                    let reason = L10n.text(
                        "未符無損直通: 目標容器 .\(target) 不支援目前視訊編碼 [\(insp.videoCodec ?? "未知")] 直通，已採用相容轉碼產出檔案",
                        "Remux disqualified: target container .\(target) does not support [\(insp.videoCodec ?? "unknown")] remux; fallback transcode used"
                    )
                    comparison.verificationNote = reason
                    comparison.qualificationReasons = [reason]
                }

            case .videoLossless:
                let isCompatible = (item.currentPresetId == "mp4_compatible")
                let ext = outputUrl.pathExtension.lowercased()
                if isCompatible {
                    executionCmd = "ffmpeg -nostdin -y -i \"\(item.inputUrl.path)\" -map 0:v? -map 0:a? -dn -c:v libx264 -pix_fmt yuv420p -crf 18 -preset medium -c:a aac -b:a 256k \"\(outputUrl.path)\""
                } else if ext == "mov" {
                    executionCmd = "ffmpeg -nostdin -y -i \"\(item.inputUrl.path)\" -map 0:v? -map 0:a? -dn -c:v prores_ks -profile:v 5 -vendor apl0 -bits_per_mb 8000 -c:a pcm_s24le \"\(outputUrl.path)\""
                } else if ext == "mkv" {
                    executionCmd = "ffmpeg -nostdin -y -i \"\(item.inputUrl.path)\" -map 0:v? -map 0:a? -dn -c:v ffv1 -level 3 -g 1 -c:a flac \"\(outputUrl.path)\""
                } else if ext == "webm" {
                    executionCmd = "ffmpeg -nostdin -y -i \"\(item.inputUrl.path)\" -map 0:v? -map 0:a? -dn -c:v libvpx-vp9 -b:v 0 -crf 30 -c:a libopus \"\(outputUrl.path)\""
                } else if ext == "mxf" {
                    executionCmd = "ffmpeg -nostdin -y -i \"\(item.inputUrl.path)\" -map 0:v? -map 0:a? -dn -c:v mpeg2video -qscale:v 2 -ar 48000 -c:a pcm_s16le \"\(outputUrl.path)\""
                } else if ext == "avi" {
                    executionCmd = "ffmpeg -nostdin -y -i \"\(item.inputUrl.path)\" -map 0:v? -map 0:a? -dn -c:v libx264 -crf 18 -c:a mp3 \"\(outputUrl.path)\""
                } else {
                    executionCmd = "ffmpeg -nostdin -y -i \"\(item.inputUrl.path)\" -map 0:v? -map 0:a? -dn -c:v libx264 -crf 0 -preset medium -c:a alac \"\(outputUrl.path)\""
                }

                try FFmpegRunner.shared.executeLosslessTranscode(
                    inputUrl: item.inputUrl,
                    outputUrl: outputUrl,
                    compatibleMode: isCompatible,
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
                let warnings = try ImageLosslessEngine.shared.convertImageLossless(inputUrl: item.inputUrl, outputUrl: outputUrl, isCancelled: { self.isCancelled || mgr.isCancelled })
                if !warnings.isEmpty {
                    comparison.verificationStatus = .disqualified
                    comparison.verificationNote = L10n.text(L10n.text("未符無損: ", "Lossless criteria not met: "), "Lossless criteria not met: ") + warnings.joined(separator: L10n.text("；", " / "))
                    comparison.qualificationReasons = warnings
                }

            case .imageLossy:
                let q = (item.currentPresetId == "jpg_80" || item.currentPresetId == "webp_85") ? 0.80 : 0.95
                executionCmd = "ImageLosslessEngine.convertImageLossy(quality: \(q))"
                let warnings = try ImageLosslessEngine.shared.convertImageLossy(inputUrl: item.inputUrl, outputUrl: outputUrl, quality: q, isCancelled: { self.isCancelled || mgr.isCancelled })
                comparison.verificationStatus = .lossyConversion
                let detail = warnings.isEmpty ? L10n.text(L10n.text("依品質參數 \(Int(q * 100))% 輸出，不進行無損比對", "Encoded at \(Int(q * 100))% quality without a lossless comparison."), "Encoded at \(Int(q * 100))% quality without a lossless comparison.") : warnings.joined(separator: L10n.text("；", " / "))
                comparison.verificationNote = L10n.text(L10n.text("圖片有損壓縮完成: \(detail)", "Lossy image compression completed. \(detail)"), "Lossy image compression completed. \(detail)")
                comparison.qualificationReasons = warnings

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

            case .document:
                let inExt = item.inputUrl.pathExtension.lowercased()
                let outExt = outputUrl.pathExtension.lowercased()
                if ["png","jpg","jpeg","tiff","tif","bmp","webp"].contains(inExt) && outExt == "pdf" {
                    executionCmd = "ImageLosslessEngine.exportImageToPDF"
                    let warnings = try ImageLosslessEngine.shared.convertImageLossless(inputUrl: item.inputUrl, outputUrl: outputUrl, isCancelled: { self.isCancelled || mgr.isCancelled })
                    comparison.verificationStatus = .disqualified
                    let defaultReason = L10n.text(L10n.text("PDF 容器格式限制：無法保留照片原始 EXIF 中繼資料與色彩描述檔 (維持 1:1 像素尺寸)", "PDF keeps the original pixel dimensions but cannot preserve the image's EXIF metadata or color profile."), "PDF keeps the original pixel dimensions but cannot preserve the image's EXIF metadata or color profile.")
                    let reasons = warnings.isEmpty ? [defaultReason] : warnings
                    comparison.verificationNote = L10n.text(L10n.text("已完成交付（未符無損）: ", "Output created with lossless limitations: "), "Output created with lossless limitations: ") + reasons.joined(separator: L10n.text("；", " / "))
                    comparison.qualificationReasons = reasons
                } else if inExt == "pdf" && ["png","jpg","jpeg","tiff","tif","bmp","webp"].contains(outExt) {
                    executionCmd = "PDFConversionEngine.convertPDFToImages"
                    let dpi: Double = item.pdfDPI
                    let (outputUrls, warnings) = try PDFConversionEngine.shared.convertPDFToImages(
                        inputUrl: item.inputUrl,
                        outputUrl: outputUrl,
                        targetFormat: outExt,
                        dpi: dpi,
                        isCancelled: { self.isCancelled || mgr.isCancelled }
                    )
                    taskOutputUrls = outputUrls
                    comparison.verificationStatus = .cannotVerify
                    let note = L10n.text(L10n.text("PDF 文件點陣化渲染完成（共 \(outputUrls.count) 頁，解析度 \(Int(dpi)) DPI）：", "Rendered \(outputUrls.count) PDF pages at \(Int(dpi)) DPI: "), "Rendered \(outputUrls.count) PDF pages at \(Int(dpi)) DPI: ") + warnings.joined(separator: L10n.text("；", " / "))
                    comparison.verificationNote = note
                    comparison.qualificationReasons = warnings
                } else {
                    throw NSError(domain: "ConversionManager", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.text(L10n.text("本軟體為純輕量自包含架構，不支援 Office 文件 (.docx, .xlsx 等)；如需轉檔 PDF 請使用「圖片轉 PDF」或「PDF 轉圖片」功能。", "Office documents such as .docx and .xlsx are unsupported. Use Image to PDF or PDF to Images."), "Office documents such as .docx and .xlsx are unsupported. Use Image to PDF or PDF to Images.")])
                }
            }

            mgr.unregisterActiveProcess(taskId: taskId)

            let actualFinalUrl = taskOutputUrls.first ?? outputUrl

            // ── 轉檔完成後：重新真實探測產物並執行無損比對驗證 ──
            comparison.outputUrl = actualFinalUrl
            comparison.executionArgs = [executionCmd]

            let outInspection = try? FFmpegRunner.shared.probe(fileUrl: actualFinalUrl)
            comparison.outputInspection = outInspection

            // 執行客觀比對驗證 (R-1, R-2 嚴格修復)
            switch item.category {
            case .remux:
                if comparison.verificationStatus == .disqualified {
                    break
                }
                let verify = FFmpegRunner.shared.verifyRemux(inputUrl: item.inputUrl, outputUrl: outputUrl)
                comparison.inputHash = verify.inputVideoHash ?? verify.inputAudioHash
                comparison.outputHash = verify.outputVideoHash ?? verify.outputAudioHash

                if verify.allMatched {
                    comparison.verificationStatus = .passed
                    comparison.verificationNote = L10n.text("串流直通封裝驗證通過：\(verify.note)", "Stream copy remux verified: \(verify.note)")
                } else {
                    let hasMismatch = (verify.videoHashMatch == false && verify.inputVideoHash != nil && verify.outputVideoHash != nil) ||
                                      (verify.audioHashMatch == false && verify.inputAudioHash != nil && verify.outputAudioHash != nil)
                    if hasMismatch {
                        comparison.verificationStatus = .mismatch
                        comparison.verificationNote = L10n.text("位元流比對失敗（不吻合）：\(verify.note)", "Bitstream verification failed (mismatch): \(verify.note)")
                    } else {
                        comparison.verificationStatus = .cannotVerify
                        comparison.verificationNote = L10n.text("未能完整提取所有串流之位元流 MD5 進行校驗：\(verify.note)", "Failed to extract complete bitstream MD5: \(verify.note)")
                    }
                }

                // 檢查是否有被略過軌道並記錄警告
                if let insp = item.inspection {
                    let outInsp = try? FFmpegRunner.shared.probe(fileUrl: outputUrl)
                    let outStreams = outInsp?.streams ?? []
                    let outExt = outputUrl.pathExtension.lowercased()
                    for s in insp.streams {
                        let outCount = outStreams.filter { $0.codecType == s.codecType }.count
                        let sameTypeStreams = insp.streams.filter { $0.codecType == s.codecType }
                        let sOrderInType = sameTypeStreams.firstIndex(where: { $0.index == s.index }) ?? 0
                        if sOrderInType >= outCount {
                            if s.codecType == "data" || s.codecName == "smpte_436m_anc" || s.codecName == "tmcd" {
                                let w = L10n.text(
                                    "檢測到廣播級輔助資料軌/時間碼 [\(s.codecName ?? "data")]，已過濾以確保容器相容性，時間碼中繼資料已保全。",
                                    "Auxiliary data/timecode [\(s.codecName ?? "data")] filtered for container compatibility; metadata timecode preserved."
                                )
                                if !comparison.qualificationReasons.contains(w) {
                                    comparison.qualificationReasons.append(w)
                                }
                            } else if s.codecType == "subtitle" {
                                if outExt == "mkv" {
                                    let w = L10n.text(
                                        "來源字幕軌 [\(s.codecName ?? "sub")] 未能封裝至 MKV。",
                                        "Source subtitle track [\(s.codecName ?? "sub")] could not be muxed into MKV."
                                    )
                                    if !comparison.qualificationReasons.contains(w) {
                                        comparison.qualificationReasons.append(w)
                                    }
                                } else {
                                    let w = L10n.text(
                                        "目標容器 .\(item.outputContainer) 不支援此字幕格式直接封裝，已略過。",
                                        "Target container .\(item.outputContainer) does not support direct subtitle remux; skipped."
                                    )
                                    if !comparison.qualificationReasons.contains(w) {
                                        comparison.qualificationReasons.append(w)
                                    }
                                }
                            }
                        }
                    }
                }

            case .videoLossless:
                let isCompatible = (item.currentPresetId == "mp4_compatible")
                let outExt = outputUrl.pathExtension.lowercased()
                if isCompatible {
                    comparison.verificationStatus = .lossyConversion
                    comparison.verificationNote = L10n.text("通用相容 MP4 轉換模式（8-bit H.264 / AAC 256k），已適配色彩採樣以確保相容所有播放設備。", "Universal compatible MP4 mode (8-bit H.264 / AAC 256k), colorspace adapted for playback compatibility.")
                } else if outExt == "mov" {
                    comparison.verificationStatus = .visualLossless
                    comparison.verificationNote = L10n.text("視覺級極限近似無損 (ProRes 4444 XQ 12-bit，非數學像素無損)，含微量量化誤差。", "Visual near-lossless mode (ProRes 4444 XQ 12-bit, not mathematical bit-exact), minor quantization drift present.")
                } else if outExt == "webm" || outExt == "mxf" || outExt == "avi" || outExt == "ts" {
                    comparison.verificationStatus = .lossyConversion
                    comparison.verificationNote = L10n.text("通用相容視訊轉換模式 (\(outExt.uppercased()))，產出標準相容多媒體檔案。", "Compatible video transcode mode (\(outExt.uppercased())), generated standard media file.")
                } else {
                    let report = VideoLosslessVerifier.verifyFullLossless(inputUrl: item.inputUrl, outputUrl: outputUrl, maxFrames: nil)
                    comparison.inputHash = report.sampleHashesInput.first
                    comparison.outputHash = report.sampleHashesOutput.first

                    if report.isPassed {
                        comparison.verificationStatus = .passed
                        comparison.verificationNote = report.localizedNote
                    } else if report.verifiedFrames > 0 {
                        comparison.verificationStatus = .mismatch
                        comparison.verificationNote = report.localizedNote
                    } else {
                        comparison.verificationStatus = .cannotVerify
                        comparison.verificationNote = report.localizedNote
                    }

                    // 記錄被略過軌道之診斷警告
                    for track in report.skippedTracks {
                        if let reason = track.localizedSkipReason {
                            comparison.qualificationReasons.append(reason)
                        }
                    }
                }

            case .imageLossless:
                let outExt = outputUrl.pathExtension.lowercased()
                if outExt == "pdf" {
                    comparison.verificationStatus = .disqualified
                    comparison.verificationNote = L10n.text(L10n.text("已完成交付（未符無損）：PDF 容器格式限制：無法保留照片原始 EXIF 中繼資料與色彩描述檔 (維持 1:1 像素尺寸)。", "PDF created at the original pixel dimensions. The image's EXIF metadata and color profile could not be preserved."), "PDF created at the original pixel dimensions. The image's EXIF metadata and color profile could not be preserved.")
                    comparison.qualificationReasons = [L10n.text(L10n.text("PDF 容器格式限制：無法保留照片原始 EXIF 中繼資料與色彩描述檔 (維持 1:1 像素尺寸)", "PDF keeps the original pixel dimensions but cannot preserve the image's EXIF metadata or color profile."), "PDF keeps the original pixel dimensions but cannot preserve the image's EXIF metadata or color profile.")]
                } else {
                    let inPix = ImageLosslessEngine.shared.computePixelMd5(fileUrl: item.inputUrl)
                    let outPix = ImageLosslessEngine.shared.computePixelMd5(fileUrl: outputUrl)
                    comparison.inputHash = inPix
                    comparison.outputHash = outPix

                    if comparison.verificationStatus == .disqualified {
                        if let ip = inPix, let op = outPix {
                            if ip == op {
                                comparison.verificationNote = L10n.text(L10n.text("未符無損（像素 1:1 一致，中繼資料/格式受限）: ", "Pixel values match. Metadata or format limits prevented a fully lossless result: "), "Pixel values match. Metadata or format limits prevented a fully lossless result: ") + comparison.qualificationReasons.joined(separator: L10n.text("；", " / "))
                            } else {
                                if !comparison.qualificationReasons.contains(where: { $0.localizedCaseInsensitiveContains(L10n.text("像素", "pixel")) }) {
                                    comparison.qualificationReasons.append(L10n.text(L10n.text("點陣 RGBA 像素比對不一致（來源: \(ip) vs 產物: \(op)）", "RGBA pixels differ (source hash \(ip), output hash \(op))."), "RGBA pixels differ (source hash \(ip), output hash \(op))."))
                                }
                                comparison.verificationNote = L10n.text(L10n.text("未符無損: ", "Lossless criteria not met: "), "Lossless criteria not met: ") + comparison.qualificationReasons.joined(separator: L10n.text("；", " / "))
                            }
                        }
                    } else if let ip = inPix, let op = outPix {
                        if ip == op {
                            comparison.verificationStatus = .passed
                            comparison.verificationNote = L10n.text(L10n.text("點陣 RGBA 像素 1:1 完全一致（MD5: \(ip)）。", "RGBA pixels match exactly (MD5 \(ip))."), "RGBA pixels match exactly (MD5 \(ip)).")
                        } else {
                            comparison.verificationStatus = .disqualified
                            let diffNote = L10n.text(L10n.text("點陣 RGBA 像素比對不一致（來源: \(ip) vs 產物: \(op)）", "RGBA pixels differ (source hash \(ip), output hash \(op))."), "RGBA pixels differ (source hash \(ip), output hash \(op)).")
                            comparison.qualificationReasons.append(diffNote)
                            comparison.verificationNote = L10n.text(L10n.text("未符無損: ", "Lossless criteria not met: "), "Lossless criteria not met: ") + comparison.qualificationReasons.joined(separator: L10n.text("；", " / "))
                        }
                    } else {
                        comparison.verificationStatus = .cannotVerify
                        comparison.verificationNote = L10n.text(L10n.text("未能提取點陣像素雜湊進行校驗。", "Could not extract a pixel hash for verification."), "Could not extract a pixel hash for verification.")
                    }
                }

            case .imageLossy:
                comparison.verificationStatus = .lossyConversion
                let base = L10n.text(L10n.text("有損圖片壓縮格式（採用視覺量化演算法，不進行像素比對）", "Lossy image compression uses quantization. No pixel comparison was performed."), "Lossy image compression uses quantization. No pixel comparison was performed.")
                if !comparison.qualificationReasons.isEmpty {
                    comparison.verificationNote = L10n.text(L10n.text("\(base)；具體警語: ", "\(base) Warnings: "), "\(base) Warnings: ") + comparison.qualificationReasons.joined(separator: L10n.text("；", " / "))
                } else if comparison.verificationNote.isEmpty {
                    comparison.verificationNote = base
                }

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
                        comparison.verificationNote = L10n.text(L10n.text("解碼 PCM 音訊取樣完全一致（MD5: \(ip)），100% 數學無損互轉。", "The decoded PCM audio samples match in the comparison (MD5 \(ip))."), "The decoded PCM audio samples match in the comparison (MD5 \(ip)).")
                    } else {
                        comparison.verificationStatus = .mismatch
                        comparison.verificationNote = L10n.text(L10n.text("解碼 PCM 音訊取樣雜湊不一致（來源: \(ip) vs 產物: \(op)），檢測到波形差異！", "The decoded PCM audio samples differ (source hash \(ip), output hash \(op))."), "The decoded PCM audio samples differ (source hash \(ip), output hash \(op)).")
                    }
                } else {
                    comparison.verificationStatus = .cannotVerify
                    comparison.verificationNote = L10n.text(L10n.text("未能提取 PCM 音訊雜湊進行校驗。", "Could not extract a PCM audio hash for verification."), "Could not extract a PCM audio hash for verification.")
                }

            case .audioLossy:
                let br = item.audioBitrate ?? "320k"
                let sr = item.audioSampleRate != nil ? "\(item.audioSampleRate!)Hz" : L10n.text(L10n.text("保留來源取樣率", "Source sample rate"), "Source sample rate")
                comparison.verificationStatus = .lossyConversion
                comparison.verificationNote = L10n.text(L10n.text("有損音訊轉換／降轉模式（碼率: \(br), 取樣率: \(sr)），採用心理聲學量化，不進行位元比對。", "Lossy audio conversion (bitrate \(br), sample rate \(sr)). No bit comparison was performed."), "Lossy audio conversion (bitrate \(br), sample rate \(sr)). No bit comparison was performed.")

            case .document:
                let outExt = outputUrl.pathExtension.lowercased()
                if outExt == "pdf" {
                    comparison.verificationStatus = .disqualified
                    comparison.verificationNote = L10n.text(L10n.text("已完成交付（未符無損）：PDF 容器格式限制：無法保留照片原始 EXIF 中繼資料與色彩描述檔 (維持 1:1 像素尺寸)。", "PDF created at the original pixel dimensions. The image's EXIF metadata and color profile could not be preserved."), "PDF created at the original pixel dimensions. The image's EXIF metadata and color profile could not be preserved.")
                    comparison.qualificationReasons = [L10n.text(L10n.text("PDF 容器格式限制：無法保留照片原始 EXIF 中繼資料與色彩描述檔 (維持 1:1 像素尺寸)", "PDF keeps the original pixel dimensions but cannot preserve the image's EXIF metadata or color profile."), "PDF keeps the original pixel dimensions but cannot preserve the image's EXIF metadata or color profile.")]
                } else {
                    comparison.verificationStatus = .cannotVerify
                    let base = L10n.text(L10n.text("PDF 文件點陣化渲染產物已交付（像素為重新取樣產生非原圖無損抽取，不進行位元比對）", "PDF images were rendered at the selected resolution. No bit comparison was performed."), "PDF images were rendered at the selected resolution. No bit comparison was performed.")
                    if comparison.verificationNote.isEmpty {
                        if !comparison.qualificationReasons.isEmpty {
                            comparison.verificationNote = L10n.text(L10n.text("\(base)；警語: ", "\(base) Warnings: "), "\(base) Warnings: ") + comparison.qualificationReasons.joined(separator: L10n.text("；", " / "))
                        } else {
                            comparison.verificationNote = base
                        }
                    }
                }
            }

            let duration = Date().timeIntervalSince(start)
            DispatchQueue.main.async {
                mgr.tasks[self.taskIndex].outputUrls = taskOutputUrls.isEmpty ? [actualFinalUrl] : taskOutputUrls
                mgr.tasks[self.taskIndex].status = .completed(outputUrl: actualFinalUrl, duration: duration)
                mgr.tasks[self.taskIndex].outputInspection = outInspection
                mgr.tasks[self.taskIndex].comparison = comparison
                mgr.tasks[self.taskIndex].executionCommand = executionCmd
            }
            mgr.log(L10n.text("完成: \(actualFinalUrl.lastPathComponent) (耗時 \(String(format: "%.2f", duration))s) [\(comparison.verificationStatus.displayText)]", "Completed \(actualFinalUrl.lastPathComponent) in \(String(format: "%.2f", duration))s [\(comparison.verificationStatus.displayText)]"))

        } catch {
            mgr.unregisterActiveProcess(taskId: taskId)
            if ![ConversionCategory.document, .imageLossless, .imageLossy].contains(item.category), let out = finalOutputUrl {
                try? FileManager.default.removeItem(at: out)
            }
            DispatchQueue.main.async {
                if error is CancellationError || self.isCancelled || mgr.isCancelled {
                    mgr.tasks[self.taskIndex].status = .cancelled
                    mgr.tasks[self.taskIndex].comparison?.verificationStatus = .unverified
                    mgr.tasks[self.taskIndex].comparison?.verificationNote = L10n.text(L10n.text("批次已取消", "The batch was canceled."), "The batch was canceled.")
                    return
                }
                mgr.tasks[self.taskIndex].status = .failed(error: error.localizedDescription)
                mgr.tasks[self.taskIndex].comparison?.verificationStatus = .failed
                mgr.tasks[self.taskIndex].comparison?.verificationNote = L10n.text(L10n.text("失敗: \(error.localizedDescription)", "Conversion failed. \(error.localizedDescription)"), "Conversion failed. \(error.localizedDescription)")
                mgr.tasks[self.taskIndex].lastStderr = error.localizedDescription
            }
            mgr.log(L10n.text(L10n.text("失敗: \(item.inputUrl.lastPathComponent) — \(error.localizedDescription)", "Could not convert \(item.inputUrl.lastPathComponent). \(error.localizedDescription)"), "Could not convert \(item.inputUrl.lastPathComponent). \(error.localizedDescription)"))
        }
    }
}
