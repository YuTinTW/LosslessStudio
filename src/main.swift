import SwiftUI
import AppKit

// ─────────────────────────────────────────────────────────────────
// CLI 無頭批次模式
//   --cli           啟用 CLI 模式
//   --mode          remux | transcode | image
//   --input <file>  單檔輸入
//   --output <file> 單檔輸出
//   --folder <dir>  資料夾遞迴匯入（與 --mode、--output-dir 搭配）
//   --output-dir <dir> 資料夾匯入的輸出根目錄（預設 /tmp/lossless_out）
//   --workers-video N  視訊並行數（預設 2）
//   --workers-image N  圖片並行數（預設 4）
//   --retry-failed  重試上次失敗（此 CLI 模式：重跑尚存的失敗任務）
// ─────────────────────────────────────────────────────────────────

func runCLIMode() -> Int32 {
    let args = CommandLine.arguments
    print("=== LosslessStudio CLI Engine Mode ===")

    // ── 資料夾批次模式 ──────────────────────────────────────────
    if let folderIdx = args.firstIndex(of: "--folder"), folderIdx + 1 < args.count {
        return runFolderBatchCLI(args: args, folderIdx: folderIdx)
    }

    // ── 單檔模式（原有 API，向下相容） ──────────────────────────
    guard let modeIdx  = args.firstIndex(of: "--mode"),  modeIdx  + 1 < args.count,
          let inputIdx = args.firstIndex(of: "--input"), inputIdx + 1 < args.count,
          let outIdx   = args.firstIndex(of: "--output"), outIdx  + 1 < args.count else {
        print("Usage: LosslessStudio --cli --mode [remux|transcode|image|audio-lossless|audio-lossy] --input <file> --output <file>")
        print("       LosslessStudio --cli --folder <dir> --mode [remux|transcode|image|audio-lossless|audio-lossy] --output-dir <dir>")
        return 1
    }

    let mode      = args[modeIdx + 1]
    let inputUrl  = URL(fileURLWithPath: args[inputIdx + 1])
    let outputUrl = URL(fileURLWithPath: args[outIdx + 1])
    var dpi: Double = 150.0
    if let dpiIdx = args.firstIndex(of: "--dpi"), dpiIdx + 1 < args.count {
        dpi = Double(args[dpiIdx + 1]) ?? 150.0
    }

    print("Mode: \(mode)")
    print("Input: \(inputUrl.path)")
    print("Output: \(outputUrl.path)")

    do {
        if FFmpegRunner.isSameFile(url1: inputUrl, url2: outputUrl) {
            print("ERROR: 禁止覆寫來源檔案 (同路徑或相同 inode)！")
            return 2
        }

        switch mode {
        case "remux":
            let insp = try FFmpegRunner.shared.probe(fileUrl: inputUrl)
            print("Inspected: Video=\(insp.videoCodec ?? "none"), Audio=\(insp.audioCodec ?? "none")")
            let check = LosslessLimitations.canRemux(
                videoCodec: insp.videoCodec,
                audioCodec: insp.audioCodec,
                targetContainer: outputUrl.pathExtension
            )
            if !check.allowed {
                if check.canCopyVideo && check.needsAudioTranscode {
                    let audioCodec = check.fallbackAudioCodec ?? "aac"
                    let audioBitrate = check.fallbackAudioBitrate ?? "320k"
                    print("NOTICE: 視訊位元直通保全，音訊因 \(outputUrl.pathExtension.uppercased()) 容器規範自動轉為高品質相容編碼 (\(audioCodec))")
                    try FFmpegRunner.shared.executeRemux(
                        inputUrl: inputUrl,
                        outputUrl: outputUrl,
                        customAudioCodec: audioCodec,
                        customAudioBitrate: audioBitrate
                    )
                    print("SUCCESS: 視訊無損直通與相容音訊轉碼完成")
                } else {
                    print("REJECTED: \(check.reason)"); return 10
                }
            } else {
                try FFmpegRunner.shared.executeRemux(inputUrl: inputUrl, outputUrl: outputUrl)
                print("SUCCESS: 封裝直通完成 (無損)")
            }

        case "transcode":
            try FFmpegRunner.shared.executeLosslessTranscode(inputUrl: inputUrl, outputUrl: outputUrl)
            print("SUCCESS: 像素無損轉碼完成 (無損)")

        case "image":
            let warnings = try ImageLosslessEngine.shared.convertImageLossless(inputUrl: inputUrl, outputUrl: outputUrl)
            if warnings.isEmpty {
                print("SUCCESS: 圖片無損轉換完成 (無損)")
            } else {
                print("SUCCESS: 圖片轉換完成 (未符無損: \(warnings.joined(separator: "; ")))")
            }

        case "image-lossy":
            let warnings = try ImageLosslessEngine.shared.convertImageLossy(inputUrl: inputUrl, outputUrl: outputUrl)
            if warnings.isEmpty {
                print("SUCCESS: 圖片有損壓縮完成（不宣稱像素無損）")
            } else {
                print("SUCCESS: 圖片有損壓縮完成（未符無損: \(warnings.joined(separator: "; "))）")
            }

        case "audio-lossless":
            let insp = try? FFmpegRunner.shared.probe(fileUrl: inputUrl)
            let depth = insp?.streams.first(where: { $0.codecType == "audio" })?.bitDepth ?? 16
            let pcmCodec = (depth >= 24) ? "pcm_s24le" : "pcm_s16le"
            try FFmpegRunner.shared.executeAudioLossless(inputUrl: inputUrl, outputUrl: outputUrl)
            let inPcm = FFmpegRunner.shared.computeAudioPcmMd5(fileUrl: inputUrl, pcmCodec: pcmCodec)
            let outPcm = FFmpegRunner.shared.computeAudioPcmMd5(fileUrl: outputUrl, pcmCodec: pcmCodec)
            if let ip = inPcm, let op = outPcm, ip == op {
                print("SUCCESS: 音訊無損轉換完成 (PCM MD5: \(ip))")
            } else {
                print("SUCCESS: 音訊轉換完成 (PCM MD5: 來源 \(inPcm ?? "-") vs 產物 \(outPcm ?? "-"))")
            }

        case "audio-lossy":
            var br = "320k"
            if let brIdx = args.firstIndex(of: "--bitrate"), brIdx + 1 < args.count {
                br = args[brIdx + 1]
            }
            var ar: Int? = nil
            if let arIdx = args.firstIndex(of: "--ar"), arIdx + 1 < args.count {
                ar = Int(args[arIdx + 1])
            }
            try FFmpegRunner.shared.executeAudioLossy(inputUrl: inputUrl, outputUrl: outputUrl, bitrate: br, targetSampleRate: ar)
            print("SUCCESS: 音訊有損／降轉完成 (碼率: \(br), 不進行位元比對)")

        case "document":
            let inExt = inputUrl.pathExtension.lowercased()
            let outExt = outputUrl.pathExtension.lowercased()
            if ["png","jpg","jpeg","tiff","tif","bmp","webp"].contains(inExt) && outExt == "pdf" {
                _ = try ImageLosslessEngine.shared.convertImageLossless(inputUrl: inputUrl, outputUrl: outputUrl)
                print("SUCCESS: 圖片轉 PDF 原生封裝完成 (1:1 像素點陣封裝)")
            } else if inExt == "pdf" && ["png","jpg","jpeg","tiff","tif","bmp","webp"].contains(outExt) {
                var cancelAfterPage = -1
                if let cancelIdx = args.firstIndex(of: "--cancel-after-page"), cancelIdx + 1 < args.count {
                    cancelAfterPage = Int(args[cancelIdx + 1]) ?? -1
                }
                var renderedPages = 0
                let (pages, warnings) = try PDFConversionEngine.shared.convertPDFToImages(
                    inputUrl: inputUrl,
                    outputUrl: outputUrl,
                    targetFormat: outExt,
                    dpi: dpi,
                    isCancelled: {
                        if cancelAfterPage > 0 {
                            renderedPages += 1
                            if renderedPages > cancelAfterPage {
                                return true
                            }
                        }
                        return false
                    }
                )
                let note = warnings.isEmpty ? "" : " (注意: \(warnings.joined(separator: "; ")))"
                print("SUCCESS: PDF 轉圖片點陣化渲染完成 (共 \(pages.count) 頁，解析度: \(Int(dpi)) DPI)\(note)")
            } else if ["docx","doc","xlsx","xls","pptx","ppt","pages","numbers","key"].contains(inExt) {
                print("REJECTED: 本軟體為純輕量自包含架構，不支援 Office 文件 (.docx, .xlsx 等)；如需轉檔 PDF 請使用「圖片轉 PDF」功能。")
                return 11
            } else {
                print("REJECTED: 不支援的文件轉檔組合 (來源: .\(inExt) -> 目標: .\(outExt))。支援: 圖片轉 PDF 或 PDF 轉圖片。")
                return 12
            }

        default:
            print("ERROR: 未知模式: \(mode)")
            return 3
        }
        return 0
    } catch {
        print("FAILED: \(error.localizedDescription)")
        return 4
    }
}

/// 資料夾批次 CLI：遞迴走訪，保留相對路徑，有限並行，逐檔報告，單檔失敗不阻斷
func runFolderBatchCLI(args: [String], folderIdx: Int) -> Int32 {
    let folderPath = args[folderIdx + 1]
    let rootUrl    = URL(fileURLWithPath: folderPath)

    // 預設模式
    let mode: String
    if let modeIdx = args.firstIndex(of: "--mode"), modeIdx + 1 < args.count {
        mode = args[modeIdx + 1]
    } else {
        mode = "image"
    }

    // 輸出根目錄
    let outDirPath: String
    if let odIdx = args.firstIndex(of: "--output-dir"), odIdx + 1 < args.count {
        outDirPath = args[odIdx + 1]
    } else {
        outDirPath = "/tmp/lossless_out"
    }
    let outRootUrl = URL(fileURLWithPath: outDirPath)
    try? FileManager.default.createDirectory(at: outRootUrl, withIntermediateDirectories: true)

    // 並行數
    let videoWorkers: Int
    let imageWorkers: Int
    if let vwIdx = args.firstIndex(of: "--workers-video"), vwIdx + 1 < args.count {
        videoWorkers = Int(args[vwIdx + 1]) ?? 2
    } else { videoWorkers = 2 }
    if let iwIdx = args.firstIndex(of: "--workers-image"), iwIdx + 1 < args.count {
        imageWorkers = Int(args[iwIdx + 1]) ?? 4
    } else { imageWorkers = 4 }

    // 目標副檔名
    let targetExt: String
    switch mode {
    case "remux":         targetExt = "mkv"
    case "transcode":     targetExt = "mkv"
    case "image":         targetExt = "tiff"
    case "audio-lossless": targetExt = "flac"
    case "audio-lossy":    targetExt = "mp3"
    case "document":       targetExt = "pdf"
    default:              targetExt = "mkv"
    }

    // 支援格式
    let supportedExts = Set([
        "mp4","mkv","mov","webm","avi","m4v","flv","ts","mts","m2ts","wmv","vob","3gp","ogv","mpg","mpeg",
        "png","jpg","jpeg","tiff","tif","bmp","webp","heic","heif","gif","psd","icns","dng","cr2","nef","arw",
        "wav","flac","aiff","aif","alac","m4a","mp3","aac","ogg","opus","wma","ac3","eac3","dts","m4r","caf","amr","ape","wv",
        "docx","doc","xlsx","xls","pptx","ppt","pages","numbers","key","txt","rtf","rtfd","csv","tsv","html","htm","md","markdown"
    ])

    guard let enumerator = FileManager.default.enumerator(
        at: rootUrl,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        print("ERROR: 無法走訪目錄 \(folderPath)"); return 5
    }

    var files: [(url: URL, relative: String)] = []
    // 解析 symlink（macOS /tmp → /private/tmp），確保路徑長度計算正確
    let resolvedRoot = rootUrl.resolvingSymlinksInPath()
    for case let fileUrl as URL in enumerator {
        guard supportedExts.contains(fileUrl.pathExtension.lowercased()) else { continue }
        let resolvedFile = fileUrl.resolvingSymlinksInPath()
        let rootPath = resolvedRoot.path
        let filePath = resolvedFile.path
        let relative: String
        if filePath.hasPrefix(rootPath) {
            relative = String(filePath.dropFirst(rootPath.count)).drop(while: { $0 == "/" }).description
        } else {
            relative = fileUrl.lastPathComponent
        }
        files.append((fileUrl, relative))
    }

    let total = files.count
    print("資料夾: \(folderPath)")
    print("模式: \(mode)  目標格式: .\(targetExt)")
    print("輸出根目錄: \(outDirPath)")
    print("視訊並行: \(videoWorkers)  圖片並行: \(imageWorkers)")
    print("共找到 \(total) 個支援格式檔案")
    print("────────────────────────────")

    var batchDpi: Double = 150.0
    if let dpiIdx = args.firstIndex(of: "--dpi"), dpiIdx + 1 < args.count {
        batchDpi = Double(args[dpiIdx + 1]) ?? 150.0
    }

    let lock      = NSLock()
    let outputUrlLock = NSLock()
    var reservedOutputPaths = Set<String>()
    let isFlat    = args.contains("--flat")
    var succeeded = 0
    var failed    = 0
    var rejected  = 0
    let startTime = Date()

    // 有限並行 OperationQueue
    let opQueue = OperationQueue()
    opQueue.maxConcurrentOperationCount = (mode == "image") ? imageWorkers : videoWorkers
    opQueue.name = "com.losslessstudio.cli.batch"

    for (fileUrl, relative) in files {
        let op = BlockOperation {
            // 安全輸出路徑（支援子目錄鏡像與 --flat 單層平鋪）
            let targetDir: URL
            if isFlat {
                targetDir = outRootUrl
            } else {
                let relUrl     = URL(fileURLWithPath: relative)
                let relDir     = relUrl.deletingLastPathComponent().relativePath
                targetDir  = relDir == "." ? outRootUrl : outRootUrl.appendingPathComponent(relDir)
            }
            try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

            let baseName   = fileUrl.deletingPathExtension().lastPathComponent
            
            // BLK-2 原子預約機制：避免多線程同時挑中同檔名
            outputUrlLock.lock()
            var candidate  = targetDir.appendingPathComponent("\(baseName)_lossless.\(targetExt)")
            var counter    = 1
            while FileManager.default.fileExists(atPath: candidate.path)
                || FFmpegRunner.isSameFile(url1: candidate, url2: fileUrl)
                || reservedOutputPaths.contains(candidate.path) {
                candidate = targetDir.appendingPathComponent("\(baseName)_lossless_\(counter).\(targetExt)")
                counter += 1
            }
            reservedOutputPaths.insert(candidate.path)
            outputUrlLock.unlock()

            var msg = ""
            do {
                switch mode {
                case "remux":
                    let insp  = try FFmpegRunner.shared.probe(fileUrl: fileUrl)
                    let check = LosslessLimitations.canRemux(
                        videoCodec: insp.videoCodec,
                        audioCodec: insp.audioCodec,
                        targetContainer: targetExt
                    )
                    if !check.allowed {
                        if check.canCopyVideo && check.needsAudioTranscode {
                            let audioCodec = check.fallbackAudioCodec ?? "aac"
                            let audioBitrate = check.fallbackAudioBitrate ?? "320k"
                            try FFmpegRunner.shared.executeRemux(
                                inputUrl: fileUrl,
                                outputUrl: candidate,
                                customAudioCodec: audioCodec,
                                customAudioBitrate: audioBitrate
                            )
                        } else {
                            lock.lock(); rejected += 1; lock.unlock()
                            msg = check.reason
                            print("⊘ REJECTED  \(relative) — \(check.reason)")
                            return
                        }
                    } else {
                        try FFmpegRunner.shared.executeRemux(inputUrl: fileUrl, outputUrl: candidate)
                    }
                case "transcode":
                    try FFmpegRunner.shared.executeLosslessTranscode(inputUrl: fileUrl, outputUrl: candidate)
                case "image":
                    try ImageLosslessEngine.shared.convertImageLossless(inputUrl: fileUrl, outputUrl: candidate)
                case "audio-lossless":
                    try FFmpegRunner.shared.executeAudioLossless(inputUrl: fileUrl, outputUrl: candidate)
                case "audio-lossy":
                    try FFmpegRunner.shared.executeAudioLossy(inputUrl: fileUrl, outputUrl: candidate, bitrate: "320k")
                case "document":
                    let inExt = fileUrl.pathExtension.lowercased()
                    let outExt = candidate.pathExtension.lowercased()
                    if ["png","jpg","jpeg","tiff","tif","bmp","webp"].contains(inExt) && outExt == "pdf" {
                        try ImageLosslessEngine.shared.convertImageLossless(inputUrl: fileUrl, outputUrl: candidate)
                    } else if inExt == "pdf" && ["png","jpg","jpeg","tiff","tif","bmp","webp"].contains(outExt) {
                        _ = try PDFConversionEngine.shared.convertPDFToImages(inputUrl: fileUrl, outputUrl: candidate, targetFormat: outExt, dpi: batchDpi)
                    } else {
                        throw NSError(domain: "LosslessStudio", code: 11, userInfo: [NSLocalizedDescriptionKey: "本軟體為純輕量自包含架構，不支援 Office 文件轉檔。"])
                    }
                default: break
                }
                lock.lock(); succeeded += 1; lock.unlock()
                print("✓ OK  \(relative) → \(candidate.lastPathComponent)")
            } catch {
                lock.lock(); failed += 1; lock.unlock()
                msg = error.localizedDescription
                print("✗ FAIL  \(relative) — \(msg)")
            }
        }
        opQueue.addOperation(op)
    }

    opQueue.waitUntilAllOperationsAreFinished()

    let elapsed = Date().timeIntervalSince(startTime)
    let report  = """
    ════════════════════════════════════
    LosslessStudio 批次報告
    ════════════════════════════════════
    輸出目錄 : \(outDirPath)
    總任務數 : \(total)
    ✓ 成功   : \(succeeded)
    ✗ 失敗   : \(failed)
    ⊘ 拒絕   : \(rejected)
    總耗時   : \(String(format: "%.1f", elapsed))s
    ════════════════════════════════════
    """
    print(report)

    // 寫出報告檔
    let reportPath = outRootUrl.appendingPathComponent("LosslessStudio_BatchReport.txt")
    try? report.write(to: reportPath, atomically: true, encoding: .utf8)
    print("報告已儲存：\(reportPath.path)")

    return failed > 0 ? Int32(failed) : 0
}

// ─────────────────────────────────────────────────────────────────
// App 入口：CLI / GUI 分流
// ─────────────────────────────────────────────────────────────────
if CommandLine.arguments.contains("--cli") {
    let code = runCLIMode()
    exit(code)
} else {
    _ = NSApplication.shared
    let app  = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()

        let contentView = ContentView()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "LosslessStudio - 專業無損影音與圖片批次工作站"
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Standard macOS Menu Bar & Apple Shortcuts
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. App 選單 (LosslessStudio)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "LosslessStudio")

        let aboutItem = NSMenuItem(
            title: "關於 LosslessStudio",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(aboutItem)
        appMenu.addItem(NSMenuItem.separator())

        let hideItem = NSMenuItem(
            title: "隱藏 LosslessStudio",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(
            title: "隱藏其他",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)

        let unhideAllItem = NSMenuItem(
            title: "顯示全部",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(unhideAllItem)
        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "結束 LosslessStudio",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. 檔案選單 (File)
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "檔案")

        let openItem = NSMenuItem(
            title: "加入檔案...",
            action: #selector(menuOpenFiles(_:)),
            keyEquivalent: "o"
        )
        fileMenu.addItem(openItem)

        let importFolderItem = NSMenuItem(
            title: "匯入資料夾...",
            action: #selector(menuImportFolder(_:)),
            keyEquivalent: "O"
        )
        importFolderItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(importFolderItem)
        fileMenu.addItem(NSMenuItem.separator())

        let startBatchItem = NSMenuItem(
            title: "開始轉檔",
            action: #selector(menuStartBatch(_:)),
            keyEquivalent: "r"
        )
        fileMenu.addItem(startBatchItem)

        let clearItem = NSMenuItem(
            title: "清空清單",
            action: #selector(menuClearTasks(_:)),
            keyEquivalent: "k"
        )
        fileMenu.addItem(clearItem)
        fileMenu.addItem(NSMenuItem.separator())

        let closeItem = NSMenuItem(
            title: "關閉視窗",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        fileMenu.addItem(closeItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // 3. 編輯選單 (Edit) - 啟用系統剪貼簿與文字全域快捷鍵
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "編輯")

        let undoItem = NSMenuItem(
            title: "復原",
            action: #selector(UndoManager.undo),
            keyEquivalent: "z"
        )
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(
            title: "重作",
            action: #selector(UndoManager.redo),
            keyEquivalent: "Z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())

        let cutItem = NSMenuItem(
            title: "剪下",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(cutItem)

        let copyItem = NSMenuItem(
            title: "複製",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(copyItem)

        let pasteItem = NSMenuItem(
            title: "貼上",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(pasteItem)

        let selectAllItem = NSMenuItem(
            title: "全選",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editMenu.addItem(selectAllItem)
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 4. 視窗選單 (Window)
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "視窗")

        let minimizeItem = NSMenuItem(
            title: "最小化",
            action: #selector(NSWindow.miniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(minimizeItem)

        let zoomItem = NSMenuItem(
            title: "縮放",
            action: #selector(NSWindow.zoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(zoomItem)

        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Menu Actions & Shortcuts

    @objc func menuOpenFiles(_ sender: Any?) {
        DispatchQueue.main.async {
            guard !ConversionManager.shared.isProcessing else { return }
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            if panel.runModal() == .OK {
                ConversionManager.shared.addFiles(urls: panel.urls)
            }
        }
    }

    @objc func menuImportFolder(_ sender: Any?) {
        DispatchQueue.main.async {
            guard !ConversionManager.shared.isProcessing else { return }
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            if panel.runModal() == .OK, let url = panel.url {
                ConversionManager.shared.addFolder(rootUrl: url)
            }
        }
    }

    @objc func menuStartBatch(_ sender: Any?) {
        DispatchQueue.main.async {
            if !ConversionManager.shared.tasks.isEmpty && !ConversionManager.shared.isProcessing {
                ConversionManager.shared.startBatch()
            }
        }
    }

    @objc func menuClearTasks(_ sender: Any?) {
        DispatchQueue.main.async {
            if !ConversionManager.shared.tasks.isEmpty && !ConversionManager.shared.isProcessing {
                ConversionManager.shared.clearTasks()
            }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(menuStartBatch(_:)) {
            return !ConversionManager.shared.tasks.isEmpty && !ConversionManager.shared.isProcessing
        }
        if menuItem.action == #selector(menuClearTasks(_:)) {
            return !ConversionManager.shared.tasks.isEmpty && !ConversionManager.shared.isProcessing
        }
        if menuItem.action == #selector(menuOpenFiles(_:)) || menuItem.action == #selector(menuImportFolder(_:)) {
            return !ConversionManager.shared.isProcessing
        }
        return true
    }
}
