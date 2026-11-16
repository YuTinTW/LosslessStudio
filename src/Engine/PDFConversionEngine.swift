import Darwin
import Foundation
import CoreGraphics
import PDFKit

public class PDFConversionEngine {
    public static let shared = PDFConversionEngine()

    private let magickExecutable: URL?

    // 全域路徑預約鎖與集合，防止進程內部多執行緒並行撞名
    private static let pathReservationLock = NSLock()
    private static var globallyReservedPaths = Set<String>()

    public init() {
        let candidates = [
            ProcessInfo.processInfo.environment["MAGICK_EXECUTABLE"],
            Bundle.main.bundleURL.appendingPathComponent("Contents/ImageMagick/bin/magick").path,
            Bundle.main.resourceURL?.appendingPathComponent("ImageMagick/bin/magick").path,
            Bundle.main.resourceURL?.appendingPathComponent("magick").path,
            "/Applications/LosslessStudio.app/Contents/ImageMagick/bin/magick",
            "/opt/homebrew/bin/magick",
            "/usr/local/bin/magick"
        ].compactMap { $0 }
        magickExecutable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    private func failure(_ message: String, code: Int = 1) -> NSError {
        NSError(domain: "PDFConversionEngine", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// 執行 PDF 頁面點陣化渲染轉圖片
    /// - Parameters:
    ///   - inputUrl: 來源 PDF 檔案 URL
    ///   - outputUrl: 目標輸出路徑基準（單頁時作為基準檔名；多頁時作為基準目錄與基底名稱）
    ///   - targetFormat: 目標圖片格式（png, jpg, jpeg, tiff, tif, bmp, webp）
    ///   - dpi: 渲染解析度（DPI，如 72, 150, 300）
    ///   - isCancelled: 取消檢查閉包
    /// - Returns: (生成的圖片 URL 列表, 資格與規格警語列表)
    public func convertPDFToImages(
        inputUrl: URL,
        outputUrl: URL,
        targetFormat: String,
        dpi: Double = 150.0,
        isCancelled: @escaping () -> Bool = { false }
    ) throws -> (outputUrls: [URL], warnings: [String]) {
        if isCancelled() { throw CancellationError() }

        guard let executable = magickExecutable else {
            throw failure("缺少內嵌 ImageMagick 圖片編碼引擎；嚴禁使用系統內建轉碼工具。")
        }

        // 1. 安全檢查：來源與輸出不可為同一檔案（防覆寫同檔與相同 inode）
        if FFmpegRunner.isSameFile(url1: inputUrl, url2: outputUrl) {
            throw failure("嚴格安全保護：目標輸出路徑與來源 PDF 為相同檔案 (inode/路徑重疊)，禁止覆寫原檔！")
        }

        guard FileManager.default.fileExists(atPath: inputUrl.path) else {
            throw failure("來源 PDF 檔案不存在: \(inputUrl.path)")
        }

        let attr = try? FileManager.default.attributesOfItem(atPath: inputUrl.path)
        let fileSize = attr?[.size] as? UInt64 ?? 0
        guard fileSize > 0 else {
            throw failure("來源 PDF 檔案為空檔案 (0 bytes)")
        }

        // 2. 載入並驗證 PDF 文件
        guard let doc = PDFDocument(url: inputUrl) else {
            throw failure("無法載入或解析 PDF 檔案（檔案可能已損毀、格式不相容或非有效 PDF）")
        }

        if doc.isLocked {
            throw failure("PDF 檔案已加密或受密碼鎖定保護，無法讀取頁面內容進行點陣化渲染")
        }

        let pageCount = doc.pageCount
        guard pageCount > 0 else {
            throw failure("PDF 檔案無任何有效頁面 (pageCount = 0)")
        }

        if pageCount > 5000 {
            throw failure("PDF 頁數 (\(pageCount) 頁) 超出安全處理上限 (5000 頁)")
        }

        let cleanExt = targetFormat.replacingOccurrences(of: ".", with: "").lowercased()
        let normalizedExt = (cleanExt == "jpeg") ? "jpg" : (cleanExt == "tif" ? "tiff" : cleanExt)
        guard ["png", "jpg", "tiff", "bmp", "webp"].contains(normalizedExt) else {
            throw failure("不支援的 PDF 輸出圖片格式: .\(cleanExt)。支援格式: png, jpg, tiff, bmp, webp")
        }

        let parentDir = outputUrl.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let initialBaseName = outputUrl.deletingPathExtension().lastPathComponent

        // 建立全任務專屬 staging 暫存目錄（defer 保證退出時必定清理）
        let stagingDir = parentDir.appendingPathComponent(".pdf-render-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer {
            try? FileManager.default.removeItem(at: stagingDir)
        }

        let effectiveDpi = max(dpi, 36.0)
        var warnings: [String] = [
            "PDF 點陣化渲染：像素為頁面繪圖指令重新取樣產生，非原圖無損抽取",
            "點陣化渲染受限於指定解析度 (\(Int(effectiveDpi)) DPI) 與顏色空間轉換，未進行雙向位元精確無損比對"
        ]

        if normalizedExt == "jpg" {
            warnings.append("JPEG 格式不支援透明度，已自動填充白色背景 (Flattened to white background)")
        }

        // 3. 逐頁渲染為原始 RGBA（並進行 Unpremultiply 反預乘處理）編碼至 staging
        var stagedUrls: [URL] = []
        var committedRecords: [(url: URL, dev: dev_t, ino: ino_t)] = []
        var finalUrls: [URL] = []

        do {
            for pageIndex in 0..<pageCount {
                if isCancelled() { throw CancellationError() }

                guard let page = doc.page(at: pageIndex) else {
                    throw failure("無法讀取 PDF 第 \(pageIndex + 1) 頁內容")
                }

                // 計算頁面邊界與旋轉
                var box = page.bounds(for: .cropBox)
                if box.width <= 0 || box.height <= 0 {
                    box = page.bounds(for: .mediaBox)
                }
                guard box.width > 0 && box.height > 0 else {
                    throw failure("PDF 第 \(pageIndex + 1) 頁尺寸無效 (\(box.width)x\(box.height))")
                }

                let rot = (page.rotation % 360 + 360) % 360
                let isRotated = (rot == 90 || rot == 270)
                let widthPts = isRotated ? box.height : box.width
                let heightPts = isRotated ? box.width : box.height

                let scale = CGFloat(effectiveDpi / 72.0)
                let pixelWidth = Int(ceil(widthPts * scale))
                let pixelHeight = Int(ceil(heightPts * scale))

                guard pixelWidth > 0 && pixelHeight > 0 else {
                    throw failure("PDF 第 \(pageIndex + 1) 頁計算像素尺寸異常: \(pixelWidth)x\(pixelHeight)")
                }

                if pixelWidth > 32768 || pixelHeight > 32768 {
                    throw failure("PDF 第 \(pageIndex + 1) 頁像素尺寸 (\(pixelWidth)x\(pixelHeight)) 超出單圖上限 32768px")
                }

                // 準備繪圖記憶體 Context (RGBA 8-bit premultipliedLast)
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                guard let bitmapCtx = CGContext(
                    data: nil,
                    width: pixelWidth,
                    height: pixelHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: pixelWidth * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else {
                    throw failure("無法建立繪圖記憶體 Context (\(pixelWidth)x\(pixelHeight))")
                }

                let targetRect = CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))

                // 透過 CGPDFPage 精準渲染
                guard let pageRef = page.pageRef else {
                    throw failure("無法取得 PDF 第 \(pageIndex + 1) 頁核心 CGPDFPage 引用")
                }

                let extraRotate = Int32((rot - Int(pageRef.rotationAngle) + 360) % 360)
                let transform = pageRef.getDrawingTransform(
                    .cropBox,
                    rect: targetRect,
                    rotate: extraRotate,
                    preserveAspectRatio: true
                )
                bitmapCtx.concatenate(transform)
                bitmapCtx.drawPDFPage(pageRef)

                // 提取原始 RGBA 點陣資料並進行反預乘（Unpremultiply Alpha），寫入暫存檔
                guard let data = bitmapCtx.data else {
                    throw failure("無法取得第 \(pageIndex + 1) 頁渲染點陣記憶體指標")
                }

                let byteCount = pixelWidth * pixelHeight * 4
                var rawData = Data(count: byteCount)
                rawData.withUnsafeMutableBytes { (destPtr: UnsafeMutableRawBufferPointer) in
                    let src = data.bindMemory(to: UInt8.self, capacity: byteCount)
                    let dst = destPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    for i in stride(from: 0, to: byteCount, by: 4) {
                        let a = Int(src[i + 3])
                        if a == 0 {
                            dst[i] = 0
                            dst[i + 1] = 0
                            dst[i + 2] = 0
                            dst[i + 3] = 0
                        } else if a == 255 {
                            dst[i] = src[i]
                            dst[i + 1] = src[i + 1]
                            dst[i + 2] = src[i + 2]
                            dst[i + 3] = 255
                        } else {
                            // 反預乘：c = round(c_p * 255 / a)，防止半透明邊緣被直通讀取造成暗邊
                            let r = min(255, (Int(src[i]) * 255 + a / 2) / a)
                            let g = min(255, (Int(src[i + 1]) * 255 + a / 2) / a)
                            let b = min(255, (Int(src[i + 2]) * 255 + a / 2) / a)
                            dst[i] = UInt8(r)
                            dst[i + 1] = UInt8(g)
                            dst[i + 2] = UInt8(b)
                            dst[i + 3] = UInt8(a)
                        }
                    }
                }

                let rawFile = stagingDir.appendingPathComponent("raw_page_\(pageIndex + 1).rgba")
                try rawData.write(to: rawFile)
                defer { try? FileManager.default.removeItem(at: rawFile) }

                let stagedImage = stagingDir.appendingPathComponent("stage_page_\(pageIndex + 1).\(normalizedExt)")

                // 使用內附 ImageMagick 將原始 RGBA 點陣編碼為最終格式
                try encodeWithMagick(
                    executable: executable,
                    rawFile: rawFile,
                    width: pixelWidth,
                    height: pixelHeight,
                    format: normalizedExt,
                    dpi: effectiveDpi,
                    stagingDir: stagingDir,
                    outputFile: stagedImage,
                    isCancelled: isCancelled
                )

                stagedUrls.append(stagedImage)
            }

            if isCancelled() { throw CancellationError() }

            // 4. 取得所有 staging 頁面原始檔案之 (st_dev, st_ino) 實體身分
            var stagedIdentities: [(dev: dev_t, ino: ino_t)] = []
            for staged in stagedUrls {
                var st = stat()
                guard lstat(staged.path, &st) == 0 else {
                    throw failure("無法讀取暫存檔案 \(staged.lastPathComponent) 之屬性")
                }
                stagedIdentities.append((dev: st.st_dev, ino: st.st_ino))
            }

            // 5. 全部頁面於 staging 完成後，進行跨進程原子無覆寫提交 (POSIX link)
            Self.pathReservationLock.lock()
            defer {
                for record in committedRecords {
                    Self.globallyReservedPaths.remove(record.url.path)
                }
                Self.pathReservationLock.unlock()
            }

            var counter = 0
            while true {
                if isCancelled() { throw CancellationError() }

                let candidateBase = (counter == 0) ? initialBaseName : "\(initialBaseName)_\(counter)"
                var candidateUrls: [URL] = []
                if pageCount == 1 {
                    candidateUrls.append(parentDir.appendingPathComponent("\(candidateBase).\(normalizedExt)"))
                } else {
                    for p in 1...pageCount {
                        candidateUrls.append(parentDir.appendingPathComponent("\(candidateBase)_page_\(p).\(normalizedExt)"))
                    }
                }

                // 檢查進程內預約集合與同檔保護
                var inMemoryCollision = false
                for url in candidateUrls {
                    if FFmpegRunner.isSameFile(url1: inputUrl, url2: url) || Self.globallyReservedPaths.contains(url.path) {
                        inMemoryCollision = true
                        break
                    }
                }
                if inMemoryCollision {
                    counter += 1
                    if counter > 10000 { throw failure("無法為 PDF 輸出尋找未碰撞的可用檔名序列") }
                    continue
                }

                // 嘗試將所有 staging 頁面以原子方式 link 到候選路徑（link 遇目標已存在保證失敗 EEXIST，絕不覆寫）
                var linkedThisRound: [(url: URL, dev: dev_t, ino: ino_t)] = []
                var collisionDetected = false

                for (idx, staged) in stagedUrls.enumerated() {
                    let target = candidateUrls[idx]
                    let expected = stagedIdentities[idx]
                    if link(staged.path, target.path) == 0 {
                        linkedThisRound.append((url: target, dev: expected.dev, ino: expected.ino))
                    } else {
                        let err = errno
                        if err == EEXIST {
                            collisionDetected = true
                            break
                        } else {
                            // 非 EEXIST 錯誤（如唯讀目錄、權限不足或磁碟空間滿等），立即中止，嚴禁空跑萬次重試！
                            for item in linkedThisRound {
                                var st = stat()
                                if lstat(item.url.path, &st) == 0 && st.st_dev == item.dev && st.st_ino == item.ino {
                                    unlink(item.url.path)
                                }
                            }
                            throw failure("提交產物建立硬連結失敗: \(target.path) (errno: \(err))")
                        }
                    }
                }

                if collisionDetected {
                    // 清理本輪已建立之 link（嚴格以 lstat 比對原始 staging 之 st_dev/ino 身分，絕不可誤刪外部替換檔）
                    for item in linkedThisRound {
                        var st = stat()
                        if lstat(item.url.path, &st) == 0 && st.st_dev == item.dev && st.st_ino == item.ino {
                            unlink(item.url.path)
                        }
                    }
                    counter += 1
                    if counter > 10000 {
                        throw failure("無法為 PDF 輸出尋找未碰撞的可用檔名序列")
                    }
                    continue
                }

                // 成功提交所有頁面！直接採用本輪成功 link 記錄之確證身分（不事後 lstat target 避免外力置換競態）
                committedRecords = linkedThisRound
                for item in committedRecords {
                    Self.globallyReservedPaths.insert(item.url.path)
                }
                finalUrls = candidateUrls
                break
            }

            // 清理 staging 檔案
            for staged in stagedUrls {
                unlink(staged.path)
            }

        } catch {
            // 異常回滾：僅清理本任務已提交之檔案，並嚴格以 lstat 核實 (st_dev, st_ino) 吻合才 unlink，嚴禁碰觸外部替換檔案
            for record in committedRecords {
                var st = stat()
                if lstat(record.url.path, &st) == 0 {
                    if st.st_dev == record.dev && st.st_ino == record.ino {
                        unlink(record.url.path)
                    }
                }
            }
            throw error
        }

        return (finalUrls, warnings)
    }

    // MARK: - ImageMagick Encoding (Zero ImageIO Dependency)

    private func encodeWithMagick(
        executable: URL,
        rawFile: URL,
        width: Int,
        height: Int,
        format: String,
        dpi: Double,
        stagingDir: URL,
        outputFile: URL,
        isCancelled: @escaping () -> Bool
    ) throws {
        if isCancelled() { throw CancellationError() }

        let p = Process()
        p.executableURL = executable

        let dpiStr = "\(Int(round(dpi)))"

        var args: [String] = [
            "-limit", "thread", "2",
            "-limit", "memory", "256MiB",
            "-limit", "time", "60",
            "-size", "\(width)x\(height)",
            "-depth", "8",
            "-units", "PixelsPerInch",
            "-density", dpiStr,
            "rgba:\(rawFile.path)"
        ]

        switch format {
        case "jpg":
            args.append(contentsOf: [
                "-background", "white",
                "-flatten",
                "-quality", "95",
                "-units", "PixelsPerInch",
                "-density", dpiStr,
                "jpeg:\(outputFile.path)"
            ])
        case "png":
            args.append(contentsOf: [
                "-units", "PixelsPerInch",
                "-density", dpiStr,
                "png:\(outputFile.path)"
            ])
        case "tiff":
            args.append(contentsOf: [
                "-units", "PixelsPerInch",
                "-density", dpiStr,
                "tiff:\(outputFile.path)"
            ])
        case "bmp":
            args.append(contentsOf: [
                "-units", "PixelsPerInch",
                "-density", dpiStr,
                "bmp:\(outputFile.path)"
            ])
        case "webp":
            args.append(contentsOf: [
                "-quality", "95",
                "-units", "PixelsPerInch",
                "-density", dpiStr,
                "webp:\(outputFile.path)"
            ])
        default:
            throw failure("不支援的編碼格式: \(format)")
        }

        p.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["MAGICK_TEMPORARY_PATH"] = stagingDir.path
        let engineRoot = executable.deletingLastPathComponent().deletingLastPathComponent()
        let coderModules = engineRoot.appendingPathComponent("lib/ImageMagick/modules-Q16HDRI/coders")
        if FileManager.default.fileExists(atPath: coderModules.path) {
            env["MAGICK_CODER_MODULE_PATH"] = coderModules.path
            env["MAGICK_CONFIGURE_PATH"] = engineRoot.appendingPathComponent("etc/ImageMagick-7").path
        }
        p.environment = env

        try p.run()

        let deadline = Date().addingTimeInterval(65.0)
        while p.isRunning {
            if isCancelled() || Date() > deadline {
                p.terminate()
                usleep(100_000)
                if p.isRunning {
                    kill(p.processIdentifier, SIGKILL)
                }
                p.waitUntilExit()
                if isCancelled() {
                    throw CancellationError()
                } else {
                    throw failure("ImageMagick \(format) 編碼逾時 (超過 65 秒)")
                }
            }
            usleep(20_000)
        }
        p.waitUntilExit()

        if p.terminationStatus != 0 || !FileManager.default.fileExists(atPath: outputFile.path) {
            throw failure("ImageMagick \(format) 編碼失敗 (Exit code: \(p.terminationStatus))")
        }
    }
}
