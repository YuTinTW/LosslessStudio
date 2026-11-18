import Foundation
import CryptoKit
import Darwin
import CoreGraphics
import ImageIO
import PDFKit

/// External ImageMagick adapter. No ImageIO conversion or fallback.
public class ImageLosslessEngine {
    public static let shared = ImageLosslessEngine()
    private let executable: URL?
    private let timeoutSeconds: TimeInterval
    public init() {
        timeoutSeconds = 65
        let candidates = [ProcessInfo.processInfo.environment["MAGICK_EXECUTABLE"],
                          Bundle.main.bundleURL.appendingPathComponent("Contents/ImageMagick/bin/magick").path,
                          Bundle.main.resourceURL?.appendingPathComponent("ImageMagick/bin/magick").path,
                          Bundle.main.resourceURL?.appendingPathComponent("magick").path,
                          "/opt/homebrew/bin/magick", "/usr/local/bin/magick"].compactMap { $0 }
        executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }
    init(executable: URL?, timeoutSeconds: TimeInterval = 65) { self.executable = executable; self.timeoutSeconds = timeoutSeconds }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "ImageLosslessEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private let coders = ["png":"png", "tif":"tiff", "tiff":"tiff", "bmp":"bmp", "jpg":"jpeg", "jpeg":"jpeg", "webp":"webp", "pdf":"pdf"]
    private func imagePath(_ url: URL) throws -> String {
        guard let coder = coders[url.pathExtension.lowercased()] else { throw failure(L10n.text("此外部圖片引擎目前僅開放已測試的 PNG、TIFF、BMP、JPEG、WebP 與 PDF；其他格式尚未驗證。", "This image engine supports PNG, TIFF, BMP, JPEG, WebP, and PDF. Other formats have not been verified.")) }
        return coder + ":" + url.path
    }
    private func run(_ arguments: [String], directory: URL, cancelled: () -> Bool) throws -> Data {
        guard let executable = executable else { throw failure(L10n.text("缺少 ImageMagick 圖片引擎；未使用系統內建轉碼。", "The ImageMagick image engine is missing. Conversion requires ImageMagick.")) }
        if cancelled() { throw CancellationError() }
        let stdout = directory.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: stdout.path, contents: nil) else { throw failure(L10n.text("無法建立圖片引擎暫存檔。", "Could not create a temporary file for the image engine.")) }
        defer { try? FileManager.default.removeItem(at: stdout) }
        let handle = try FileHandle(forWritingTo: stdout)
        defer { try? handle.close() }
        let limits = ["-limit","thread","2","-limit","memory","128MiB","-limit","map","256MiB","-limit","disk","512MiB","-limit","width","16384","-limit","height","16384","-limit","time","60"]
        let process = Process(); process.executableURL = executable
        process.arguments = arguments.first == "identify" ? ["identify"] + limits + arguments.dropFirst() : limits + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["MAGICK_TEMPORARY_PATH"] = directory.path
        let engineRoot = executable.deletingLastPathComponent().deletingLastPathComponent()
        let modules = engineRoot.appendingPathComponent("lib/ImageMagick/modules-Q16HDRI/coders")
        if FileManager.default.fileExists(atPath: modules.path) {
            environment["MAGICK_HOME"] = engineRoot.path
            environment["MAGICK_CODER_MODULE_PATH"] = modules.path
            environment["MAGICK_CONFIGURE_PATH"] = engineRoot.appendingPathComponent("etc/ImageMagick-7").path
        }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle; process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning {
            if cancelled() || Date() >= deadline {
                process.terminate()
                let stop = Date().addingTimeInterval(1)
                while process.isRunning && Date() < stop { Thread.sleep(forTimeInterval: 0.02) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                if cancelled() { throw CancellationError() }
                throw failure(L10n.text("圖片引擎處理逾時。", "The image engine timed out."))
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        process.waitUntilExit()
        if cancelled() { throw CancellationError() }
        guard process.terminationStatus == 0 else { throw failure(L10n.text("ImageMagick 無法完成處理；格式、檔案或資源限制不符。", "ImageMagick could not process the image. Check the format, file, and resource limits.")) }
        return try Data(contentsOf: stdout)
    }
    private struct Info {
        let width: Int; let height: Int; let depth: Int; let orientation: String; let profiles: [String]; let format: String
    }
    private func info(_ url: URL, directory: URL, cancelled: () -> Bool) throws -> Info {
        let data = try run(["identify","-format","%w|%h|%z|%[colorspace]|%[orientation]|%[profiles]|%m\\n", try imagePath(url)], directory: directory, cancelled: cancelled)
        let rows = String(decoding:data,as:UTF8.self).split(separator:"\n")
        guard rows.count == 1 else { throw failure(L10n.text("動畫或多頁圖片尚未支援，已拒絕以免遺失影格。", "Animated or multipage images are unsupported. Conversion stopped to preserve all frames.")) }
        let f = rows[0].split(separator:"|",omittingEmptySubsequences:false).map(String.init)
        guard f.count == 7, let w = Int(f[0]), let h = Int(f[1]), let d = Int(f[2]), w > 0, h > 0, w <= 16384, h <= 16384, w*h <= 16_000_000, d <= 16,
              ["sRGB","RGB","Gray"].contains(f[3]) else { throw failure(L10n.text("圖片尺寸、色彩空間或位深超出已驗證範圍。", "The image dimensions, color space, or bit depth are outside the verified range.")) }
        return Info(width:w,height:h,depth:d,orientation: f[4] == "Undefined" ? "TopLeft" : f[4],profiles:f[5].split(separator:",").map(String.init),format:f[6].lowercased())
    }
    private func pixels(_ url: URL, directory: URL, cancelled: () -> Bool) throws -> Data {
        try run([try imagePath(url),"-depth","16","-endian","MSB","rgba:-"],directory:directory,cancelled:cancelled)
    }
    @discardableResult
    public func convertImageLossless(inputUrl: URL, outputUrl: URL, isCancelled: @escaping () -> Bool = { false }) throws -> [String] {
        try convert(inputUrl:inputUrl,outputUrl:outputUrl,quality:nil,cancelled:isCancelled)
    }
    @discardableResult
    public func convertImageLossy(inputUrl: URL, outputUrl: URL, quality: Double = 0.9, isCancelled: @escaping () -> Bool = { false }) throws -> [String] {
        try convert(inputUrl:inputUrl,outputUrl:outputUrl,quality:quality,cancelled:isCancelled)
    }
    private func convert(inputUrl: URL, outputUrl: URL, quality: Double?, cancelled: () -> Bool) throws -> [String] {
        if FFmpegRunner.isSameFile(url1:inputUrl,url2:outputUrl) { throw failure(L10n.text("來源與輸出為同一檔案，禁止覆寫。", "The source and output refer to the same file. Choose a different output.")) }
        let ext = outputUrl.pathExtension.lowercased()
        if ext == "pdf" {
            try exportImageToPDF(inputUrl: inputUrl, outputUrl: outputUrl, cancelled: cancelled)
            return [L10n.text("PDF 容器格式限制：無法保留照片原始 EXIF 中繼資料與色彩描述檔 (維持 1:1 像素尺寸)", "PDF keeps the original pixel dimensions but cannot preserve the image's EXIF metadata or color profile.")]
        }
        guard ["png","tif","tiff","bmp","webp","jpg","jpeg"].contains(ext) else { throw failure(L10n.text("不支援此圖片輸出格式：.\(ext)", "Unsupported image output format .\(ext).")) }
        let directory = outputUrl.deletingLastPathComponent().appendingPathComponent(".lossless-image-" + UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer { try? FileManager.default.removeItem(at:directory) }
        
        let source = try info(inputUrl,directory:directory,cancelled:cancelled)
        var reasons: [String] = []

        if quality == nil && ["jpg","jpeg"].contains(ext) {
            reasons.append(L10n.text("JPEG 本質為有損壓縮格式，產出檔案具有量化損失", "JPEG compression introduces quantization loss."))
        }

        var effectiveDepth = source.depth
        if source.depth > 8 && ["bmp","webp","jpg","jpeg"].contains(ext) {
            effectiveDepth = 8
            reasons.append(L10n.text("來源為 \(source.depth)-bit 高位深，目標格式（\(ext)）僅支援 8-bit（已降位深轉換）", "The source is \(source.depth)-bit. The \(ext) output is limited to 8-bit."))
        }

        var hasAlpha = false
        if ["jpg","jpeg"].contains(ext) {
            let raw = try pixels(inputUrl,directory:directory,cancelled:cancelled)
            for i in stride(from:6,to:raw.count,by:8) where raw[i] != 255 || raw[i+1] != 255 {
                hasAlpha = true
                break
            }
            if hasAlpha {
                reasons.append(L10n.text("JPEG 格式不支援 Alpha 透明通道（透明度已平坦化為白色背景）", "JPEG does not support alpha transparency. Transparent areas were flattened onto white."))
            }
        }

        let result = directory.appendingPathComponent("result." + ext)
        var args: [String] = []
        if ["jpg","jpeg"].contains(ext) && hasAlpha {
            args += [try imagePath(inputUrl), "-background", "white", "-flatten"]
        } else {
            args += [try imagePath(inputUrl)]
        }
        args += ["-depth", String(effectiveDepth)]
        if ext == "webp" {
            args += ["-define","webp:lossless=\(quality == nil ? "true" : "false")","-define","webp:exact=true"]
        }
        if ext == "png" {
            args += ["-define","png:include-chunk=all","-define","png:bit-depth=\(effectiveDepth)"]
        }
        let effQ = quality ?? (["jpg","jpeg"].contains(ext) ? 0.95 : nil)
        if let q = effQ {
            args += ["-quality", String(Int(max(0,min(1,q))*100))]
        }
        args += [try imagePath(result)]
        _ = try run(args,directory:directory,cancelled:cancelled)

        guard FileManager.default.fileExists(atPath: result.path) else { throw failure(L10n.text("ImageMagick 未能產出有效檔案。", "ImageMagick did not create a valid output file.")) }
        let output = try info(result,directory:directory,cancelled:cancelled)
        guard output.format == coders[ext], source.width == output.width, source.height == output.height else {
            throw failure(L10n.text("輸出尺寸或格式不一致，轉檔失敗。", "The output dimensions or format differed from the requested values."))
        }
        if output.depth < source.depth && effectiveDepth == source.depth {
            reasons.append(L10n.text("目標產物位深降低（來源 \(source.depth)-bit，產物 \(output.depth)-bit）", "The output bit depth decreased from \(source.depth)-bit to \(output.depth)-bit."))
        }

        for profile in source.profiles {
            if !output.profiles.contains(profile) {
                reasons.append(L10n.text("目標格式無法保留來源中繼資料（\(profile)）", "The output format could not preserve the source metadata (\(profile))."))
            } else {
                do {
                    let a = try run([try imagePath(inputUrl),profile+":-"],directory:directory,cancelled:cancelled)
                    let b = try run([try imagePath(result),profile+":-"],directory:directory,cancelled:cancelled)
                    if a != b {
                        reasons.append(L10n.text("來源中繼資料有變更（\(profile)）", "The source metadata changed (\(profile))."))
                    }
                } catch {
                    if cancelled() { throw CancellationError() }
                    reasons.append(L10n.text("中繼資料校驗工具執行受限（\(profile)）: \(error.localizedDescription)", "Metadata verification could not complete (\(profile)). \(error.localizedDescription)"))
                }
            }
        }

        if quality == nil && !["jpg","jpeg"].contains(ext) {
            do {
                let a = try pixels(inputUrl,directory:directory,cancelled:cancelled)
                let b = try pixels(result,directory:directory,cancelled:cancelled)
                if a != b {
                    reasons.append(L10n.text("16-bit RGBA 點陣像素比對不一致（檢測到色空間或點陣微幅差異）", "The 16-bit RGBA pixel comparison found differences in the color space or pixel values."))
                }
            } catch {
                if cancelled() { throw CancellationError() }
                reasons.append(L10n.text("像素校驗工具提取點陣受限: \(error.localizedDescription)", "Pixel verification could not extract the raster data. \(error.localizedDescription)"))
            }
        }

        if cancelled() { throw CancellationError() }
        do {
            try FileManager.default.linkItem(at:result,to:outputUrl)
        } catch {
            guard !FileManager.default.fileExists(atPath: outputUrl.path) else { throw error }
            try FileManager.default.moveItem(at: result, to: outputUrl)
        }
        return reasons
    }

    private func exportImageToPDF(inputUrl: URL, outputUrl: URL, cancelled: () -> Bool) throws {
        if cancelled() { throw CancellationError() }
        let directory = outputUrl.deletingLastPathComponent().appendingPathComponent(".lossless-pdf-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try info(inputUrl, directory: directory, cancelled: cancelled)
        if cancelled() { throw CancellationError() }

        guard let sourceRef = CGImageSourceCreateWithURL(inputUrl as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(sourceRef, 0, nil) else {
            throw failure(L10n.text("無法讀取或解碼來源圖片點陣資料。", "Could not read or decode the source image pixels."))
        }

        let w = CGFloat(source.width)
        let h = CGFloat(source.height)
        var mediaBox = CGRect(x: 0, y: 0, width: w, height: h)

        let stagingPdf = directory.appendingPathComponent("result.pdf")
        guard let consumer = CGDataConsumer(url: stagingPdf as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw failure(L10n.text("無法建立 PDF 繪圖環境。", "Could not create the PDF drawing context."))
        }

        if cancelled() { throw CancellationError() }
        context.beginPage(mediaBox: &mediaBox)
        context.draw(cgImage, in: mediaBox)
        context.endPage()
        context.closePDF()

        if cancelled() { throw CancellationError() }
        guard FileManager.default.fileExists(atPath: stagingPdf.path),
              let doc = PDFDocument(url: stagingPdf), doc.pageCount > 0 else {
            throw failure(L10n.text("圖片轉 PDF 產物無效。", "The image-to-PDF output is invalid."))
        }

        do {
            try FileManager.default.linkItem(at: stagingPdf, to: outputUrl)
        } catch {
            guard !FileManager.default.fileExists(atPath: outputUrl.path) else { throw error }
            try FileManager.default.moveItem(at: stagingPdf, to: outputUrl)
        }
    }
    public func computePixelMd5(fileUrl: URL) -> String? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
            defer { try? FileManager.default.removeItem(at:directory) }
            _ = try info(fileUrl,directory:directory,cancelled:{false})
            let data = try pixels(fileUrl,directory:directory,cancelled:{false})
            return Insecure.MD5.hash(data:data).map { String(format:"%02x",$0) }.joined()
        } catch { return nil }
    }
}
