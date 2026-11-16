import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import CryptoKit

public class ImageLosslessEngine {
    public static let shared = ImageLosslessEngine()

    public init() {}

    public func convertImageLossless(inputUrl: URL, outputUrl: URL) throws {
        // 嚴格來源保護 (檢查路徑與 inode)
        if FFmpegRunner.isSameFile(url1: inputUrl, url2: outputUrl) {
            throw NSError(domain: "ImageLosslessEngine", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "嚴格安全保護：目標檔案與來源為相同檔案 (inode/路徑重疊)，禁止覆寫原檔！"])
        }

        let outExt = outputUrl.pathExtension.lowercased()
        if outExt == "jpg" || outExt == "jpeg" {
            throw NSError(domain: "ImageLosslessEngine", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "JPEG 格式屬於有損壓縮（離散餘弦轉換量化損失），無法進行無損輸出。為維護資料無損原則，本工具拒絕輸出為 JPEG。建議改選 PNG 或 TIFF。"])
        }

        guard let source = CGImageSourceCreateWithURL(inputUrl as CFURL, nil) else {
            throw NSError(domain: "ImageLosslessEngine", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "無法解析來源圖片檔案"])
        }

        // H5 防護：檢查多幀/多頁面（防止動畫 GIF、多頁 TIFF 靜默遺失後續影格）
        let frameCount = CGImageSourceGetCount(source)
        if frameCount > 1 {
            throw NSError(domain: "ImageLosslessEngine", code: 9,
                          userInfo: [NSLocalizedDescriptionKey: "來源圖片包含多影格/多頁面 (\(frameCount) 幀，如動畫 GIF/APNG 或多頁 TIFF)，單圖轉換會導致其他影格遺失！為維護資料完整無損，拒絕丟失影格之轉換。"])
        }

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "ImageLosslessEngine", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "無法讀取來源圖片點陣資料"])
        }

        // H5 防護：16-bit 高位深檢查
        let bpc = image.bitsPerComponent
        if outExt == "webp" && bpc > 8 {
            throw NSError(domain: "ImageLosslessEngine", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "來源圖片為高位深 (\(bpc)-bit/通道)，WebP 無損規範 (VP8L) 上限為 8-bit/通道，轉換會造成位深降階失真！為維護絕對無損，請選用 16-bit PNG 或 TIFF。"])
        }

        // 取得來源完整 Metadata（EXIF, IPTC, GPS, TIFFImageDescription 等）
        let sourceProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]

        let targetUTType: CFString
        switch outExt {
        case "png":
            targetUTType = UTType.png.identifier as CFString
        case "tiff", "tif":
            targetUTType = UTType.tiff.identifier as CFString
        case "bmp":
            targetUTType = UTType.bmp.identifier as CFString
        case "webp":
            if #available(macOS 11.0, *) {
                targetUTType = UTType.webP.identifier as CFString
            } else {
                targetUTType = "org.webmproject.webp" as CFString
            }
        default:
            throw NSError(domain: "ImageLosslessEngine", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "不支援的圖片輸出格式: .\(outExt)，僅支援無損格式 PNG, TIFF, BMP, WebP"])
        }

        guard let destination = CGImageDestinationCreateWithURL(outputUrl as CFURL, targetUTType, 1, nil) else {
            if outExt == "webp" {
                try convertWithFFmpegWebPLossless(inputUrl: inputUrl, outputUrl: outputUrl)
                return
            }
            throw NSError(domain: "ImageLosslessEngine", code: 6,
                          userInfo: [NSLocalizedDescriptionKey: "系統 ImageIO 無法建立目標格式 [\(targetUTType)] 之寫入器"])
        }

        // ── Metadata 移轉 ──────────────────────────────────────────────────────
        // 傳遞 sourceProps 作為目標屬性，讓 ImageIO 盡可能保留 EXIF/IPTC/GPS/ICC。
        // 誠實技術揭露：
        //  - PNG 原生 tEXt 規範僅為 Latin-1；非 ASCII 字元（如繁體中文）可能在
        //    格式互轉時被截斷或轉為 EXIF UserComment。
        //  - 非所有私有自訂 tag 均能 100% 跨格式映射，不宣稱未經證明的完整保留。
        // ───────────────────────────────────────────────────────────────────────
        CGImageDestinationAddImage(destination, image, sourceProps as CFDictionary)

        if !CGImageDestinationFinalize(destination) {
            throw NSError(domain: "ImageLosslessEngine", code: 7,
                          userInfo: [NSLocalizedDescriptionKey: "圖片寫入與 Metadata 轉存失敗"])
        }
    }

    private func convertWithFFmpegWebPLossless(inputUrl: URL, outputUrl: URL) throws {
        guard let ffmpeg = FFmpegRunner.shared.resolveBinaryPath(name: "ffmpeg") else {
            throw NSError(domain: "ImageLosslessEngine", code: 8,
                          userInfo: [NSLocalizedDescriptionKey: "系統 ImageIO 不支援 WebP 寫入，且本機未安裝 FFmpeg。請安裝具備 libwebp 編碼器之 FFmpeg 或改選 PNG/TIFF。"])
        }

        // H4 防護：檢查 FFmpeg 是否真正具備 webp 編碼器
        let checkProcess = Process()
        checkProcess.executableURL = URL(fileURLWithPath: ffmpeg)
        checkProcess.arguments = ["-encoders"]
        let checkPipe = Pipe()
        checkProcess.standardOutput = checkPipe
        try? checkProcess.run()
        let checkData = checkPipe.fileHandleForReading.readDataToEndOfFile()
        checkProcess.waitUntilExit()
        let encodersList = String(data: checkData, encoding: .utf8) ?? ""
        if !encodersList.contains("libwebp") && !encodersList.contains("webp") {
            throw NSError(domain: "ImageLosslessEngine", code: 8,
                          userInfo: [NSLocalizedDescriptionKey: "系統 ImageIO 無法直接寫入 WebP，且本機 FFmpeg 編譯組態不含 libwebp 編碼器。無法無損產出 WebP，建議改選 PNG 或 TIFF。"])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.standardInput = FileHandle.nullDevice
        process.arguments = [
            "-nostdin", "-nostats", "-loglevel", "warning", "-y",
            "-i", inputUrl.path,
            "-c:v", "libwebp",
            "-lossless", "1",
            "-map_metadata", "0",
            outputUrl.path
        ]

        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        let errData = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errStr = String(data: errData, encoding: .utf8) ?? "未知錯誤"
            throw NSError(domain: "ImageLosslessEngine", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "WebP 無損轉檔失敗: \(errStr.suffix(300))"])
        }
    }

    // MARK: - Pixel Verification
    public func computePixelMd5(fileUrl: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(fileUrl as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let dataProvider = image.dataProvider,
              let data = dataProvider.data as Data? else {
            return nil
        }
        return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
