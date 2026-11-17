import Foundation
import CryptoKit
import ImageIO
import CoreGraphics

public class FFmpegRunner {
    public static let shared = FFmpegRunner()
    
    public var customFFmpegPath: String?
    public var customFFprobePath: String?
    
    public init() {}
    
    public func resolveBinaryPath(name: String) -> String? {
        if name == "ffmpeg", let p = customFFmpegPath, FileManager.default.isExecutableFile(atPath: p) { return p }
        if name == "ffprobe", let p = customFFprobePath, FileManager.default.isExecutableFile(atPath: p) { return p }
        
        let bundlePath = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name)").path
        if FileManager.default.isExecutableFile(atPath: bundlePath) { return bundlePath }
        
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    
    // MARK: - Safe Inode Check
    public static func isSameFile(url1: URL, url2: URL) -> Bool {
        if url1.standardizedFileURL == url2.standardizedFileURL { return true }
        let fm = FileManager.default
        let path1 = url1.resolvingSymlinksInPath().path
        let path2 = url2.resolvingSymlinksInPath().path
        if path1 == path2 { return true }
        if let attr1 = try? fm.attributesOfItem(atPath: path1),
           let attr2 = try? fm.attributesOfItem(atPath: path2),
           let ino1 = attr1[.systemFileNumber] as? NSNumber,
           let ino2 = attr2[.systemFileNumber] as? NSNumber,
           let dev1 = attr1[.systemNumber] as? NSNumber,
           let dev2 = attr2[.systemNumber] as? NSNumber,
           ino1 == ino2 && dev1 == dev2 {
            return true
        }
        return false
    }
    
    // MARK: - Probe (逐軌完整讀取，非僅首軌)
    public func probe(fileUrl: URL) throws -> MediaInspectionResult {
        let ext = fileUrl.pathExtension.lowercased()
        let isKnownImageExt = ["png", "jpg", "jpeg", "tiff", "tif", "bmp", "webp", "heic"].contains(ext)
        
        // 若為純圖片，先以 ImageIO 取得色彩與深度，再以 ffprobe 補足容器資訊
        var imageBpc: Int?
        var imageColorSpace: String?
        var imageHasAlpha: Bool?
        
        if isKnownImageExt, let source = CGImageSourceCreateWithURL(fileUrl as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            imageBpc = image.bitsPerComponent
            imageColorSpace = image.colorSpace?.name as String? ?? "sRGB"
            imageHasAlpha = (image.alphaInfo != .none && image.alphaInfo != .noneSkipLast && image.alphaInfo != .noneSkipFirst)
        }
        
        guard let ffprobe = resolveBinaryPath(name: "ffprobe") else {
            let attr = try? FileManager.default.attributesOfItem(atPath: fileUrl.path)
            let size = (attr?[.size] as? Int64) ?? 0
            return MediaInspectionResult(
                filePath: fileUrl.path,
                fileSize: size,
                formatName: ext,
                duration: nil,
                videoCodec: nil,
                videoPixelFormat: nil,
                videoResolution: nil,
                audioCodec: nil,
                audioChannels: nil,
                audioSampleRate: nil,
                isImage: isKnownImageExt,
                streams: [],
                imageBitsPerComponent: imageBpc,
                imageColorSpace: imageColorSpace,
                imageHasAlpha: imageHasAlpha
            )
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobe)
        process.arguments = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            fileUrl.path
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        // H6 防護：先讀取 pipe 再 waitUntilExit，防止超過 64KB 管線緩衝時死鎖
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let attr = try? FileManager.default.attributesOfItem(atPath: fileUrl.path)
            let size = (attr?[.size] as? Int64) ?? 0
            return MediaInspectionResult(
                filePath: fileUrl.path,
                fileSize: size,
                formatName: ext,
                duration: nil,
                videoCodec: nil,
                videoPixelFormat: nil,
                videoResolution: nil,
                audioCodec: nil,
                audioChannels: nil,
                audioSampleRate: nil,
                isImage: isKnownImageExt,
                streams: [],
                imageBitsPerComponent: imageBpc,
                imageColorSpace: imageColorSpace,
                imageHasAlpha: imageHasAlpha
            )
        }
        
        let format = json["format"] as? [String: Any]
        let rawStreams = json["streams"] as? [[String: Any]] ?? []
        
        var streamInfos: [StreamInfo] = []
        var primaryVCodec: String?
        var primaryVProfile: String?
        var primaryVPixFmt: String?
        var primaryVRes: String?
        var primaryVFrameRate: String?
        var primaryACodec: String?
        var primaryAChan: Int?
        var primaryARate: Int?
        var isImage = isKnownImageExt
        
        for (idx, s) in rawStreams.enumerated() {
            let codecType = (s["codec_type"] as? String) ?? "unknown"
            let codecName = s["codec_name"] as? String
            let profile = s["profile"] as? String
            let pixFmt = s["pix_fmt"] as? String
            let tags = s["tags"] as? [String: Any]
            let title = tags?["title"] as? String
            let lang = tags?["language"] as? String
            
            var res: String?
            if let w = s["width"] as? Int, let h = s["height"] as? Int {
                res = "\(w)x\(h)"
            }
            
            var fr: String?
            if let rfr = s["r_frame_rate"] as? String, rfr != "0/0" {
                fr = rfr
            } else if let afr = s["avg_frame_rate"] as? String, afr != "0/0" {
                fr = afr
            }
            
            var bitDepth: Int?
            if let bStr = s["bits_per_raw_sample"] as? String, let b = Int(bStr) {
                bitDepth = b
            } else if let pf = pixFmt {
                if pf.contains("10le") || pf.contains("10be") || pf.contains("p10") { bitDepth = 10 }
                else if pf.contains("12le") || pf.contains("12be") || pf.contains("p12") { bitDepth = 12 }
                else if pf.contains("16le") || pf.contains("16be") || pf.contains("p16") { bitDepth = 16 }
                else if pf.contains("8") || pf.contains("420p") || pf.contains("rgb24") { bitDepth = 8 }
            }
            
            var chan: Int?
            var sRate: Int?
            var chLayout: String?
            if codecType == "audio" {
                chan = s["channels"] as? Int
                chLayout = s["channel_layout"] as? String
                if let srStr = s["sample_rate"] as? String {
                    sRate = Int(srStr)
                }
            }
            
            let info = StreamInfo(
                index: s["index"] as? Int ?? idx,
                codecType: codecType,
                codecName: codecName,
                profile: profile,
                pixelFormat: pixFmt,
                resolution: res,
                frameRate: fr,
                bitDepth: bitDepth,
                sampleRate: sRate,
                channels: chan,
                channelLayout: chLayout,
                title: title,
                language: lang
            )
            streamInfos.append(info)
            
            if codecType == "video" && primaryVCodec == nil {
                primaryVCodec = codecName
                primaryVProfile = profile
                primaryVPixFmt = pixFmt
                primaryVRes = res
                primaryVFrameRate = fr
                if ["png", "mjpeg", "bmp", "tiff", "webp"].contains(codecName?.lowercased() ?? "") && (format?["duration"] == nil || (Double(format?["duration"] as? String ?? "0") ?? 0) <= 0.04) {
                    isImage = true
                }
            } else if codecType == "audio" && primaryACodec == nil {
                primaryACodec = codecName
                primaryAChan = chan
                primaryARate = sRate
            }
        }
        
        let durStr = format?["duration"] as? String
        let dur = durStr != nil ? Double(durStr!) : nil
        let sizeStr = format?["size"] as? String
        let size = sizeStr != nil ? Int64(sizeStr!) : 0
        let fmtName = format?["format_name"] as? String ?? ext
        
        return MediaInspectionResult(
            filePath: fileUrl.path,
            fileSize: size ?? 0,
            formatName: fmtName,
            duration: dur,
            videoCodec: primaryVCodec,
            videoProfile: primaryVProfile,
            videoPixelFormat: primaryVPixFmt,
            videoResolution: primaryVRes,
            videoFrameRate: primaryVFrameRate,
            audioCodec: primaryACodec,
            audioChannels: primaryAChan,
            audioSampleRate: primaryARate,
            isImage: isImage,
            streams: streamInfos,
            imageBitsPerComponent: imageBpc,
            imageColorSpace: imageColorSpace,
            imageHasAlpha: imageHasAlpha
        )
    }
    
    // MARK: - Remux (串流直通)
    public func executeRemux(
        inputUrl: URL,
        outputUrl: URL,
        customAudioCodec: String? = nil,
        customAudioBitrate: String? = nil,
        processObserver: ((Process) -> Void)? = nil,
        onProgress: ((Double, String?, String?) -> Void)? = nil
    ) throws {
        guard let ffmpeg = resolveBinaryPath(name: "ffmpeg") else {
            throw NSError(domain: "FFmpegRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: "找不到 ffmpeg 執行檔"])
        }
        
        if FFmpegRunner.isSameFile(url1: inputUrl, url2: outputUrl) {
            throw NSError(domain: "FFmpegRunner", code: 3, userInfo: [NSLocalizedDescriptionKey: "嚴格安全保護：目標檔案與來源為相同檔案 (inode/路徑重疊)，禁止覆寫原檔！"])
        }
        
        let insp = try? probe(fileUrl: inputUrl)
        let totalDurationUs = (insp?.duration ?? 0) * 1_000_000.0
        
        var args = [
            "-nostdin",
            "-nostats",
            "-loglevel", "warning",
            "-progress", "pipe:1",
            "-y",
            "-i", inputUrl.path
        ]
        
        if let audioCodec = customAudioCodec {
            args.append(contentsOf: ["-c:v", "copy", "-c:a", audioCodec])
            if let br = customAudioBitrate {
                args.append(contentsOf: ["-b:a", br])
            }
        } else {
            args.append(contentsOf: ["-c", "copy"])
        }
        
        args.append(contentsOf: [
            "-map", "0:v?",
            "-map", "0:a?",
            "-dn",
            "-map_metadata", "0",
            outputUrl.path
        ])
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.standardInput = FileHandle.nullDevice
        process.arguments = args
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        processObserver?(process)
        
        var currentProgress: Double = 0.05
        var currentSpeed: String = "計算中..."
        var currentEta: String = "計算中..."
        
        var buffer = ""
        let outHandle = outPipe.fileHandleForReading
        outHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            buffer += text
            while let nlRange = buffer.range(of: "\n") {
                let line = String(buffer[..<nlRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                buffer.removeSubrange(...nlRange.lowerBound)
                
                if line.hasPrefix("out_time_us=") {
                    let valStr = String(line.dropFirst("out_time_us=".count))
                    if let us = Double(valStr), totalDurationUs > 0 {
                        currentProgress = min(0.99, max(0.01, us / totalDurationUs))
                    }
                } else if line.hasPrefix("speed=") {
                    let sStr = String(line.dropFirst("speed=".count)).trimmingCharacters(in: .whitespaces)
                    currentSpeed = (sStr.isEmpty || sStr == "N/A") ? "未知" : sStr
                    if let spd = Double(currentSpeed.replacingOccurrences(of: "x", with: "")), spd > 0, totalDurationUs > 0 {
                        let remSec = max(0, (totalDurationUs - (currentProgress * totalDurationUs)) / (spd * 1_000_000.0))
                        currentEta = String(format: "%.1f秒", remSec)
                    } else {
                        currentEta = totalDurationUs > 0 ? "計算中..." : "不適用"
                    }
                    onProgress?(currentProgress, currentSpeed, currentEta)
                } else if line == "progress=end" {
                    currentProgress = 1.0
                    onProgress?(1.0, currentSpeed, "0秒")
                }
            }
        }
        
        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        outHandle.readabilityHandler = nil
        
        if process.terminationStatus != 0 {
            try? FileManager.default.removeItem(at: outputUrl)
            let errString = String(data: errData, encoding: .utf8) ?? "未知 FFmpeg 錯誤"
            throw NSError(domain: "FFmpegRunner", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "封裝直通失敗 (\(process.terminationStatus)): \(errString.suffix(400))"
            ])
        }
        onProgress?(1.0, currentSpeed.isEmpty ? "直通完成" : currentSpeed, "0秒")
    }
    
    // MARK: - Lossless Transcode
    public func executeLosslessTranscode(
        inputUrl: URL,
        outputUrl: URL,
        compatibleMode: Bool = false,
        processObserver: ((Process) -> Void)? = nil,
        onProgress: ((Double, String?, String?) -> Void)? = nil
    ) throws {
        guard let ffmpeg = resolveBinaryPath(name: "ffmpeg") else {
            throw NSError(domain: "FFmpegRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: "找不到 ffmpeg 執行檔"])
        }
        
        if FFmpegRunner.isSameFile(url1: inputUrl, url2: outputUrl) {
            throw NSError(domain: "FFmpegRunner", code: 3, userInfo: [NSLocalizedDescriptionKey: "嚴格安全保護：目標檔案與來源為相同檔案 (inode/路徑重疊)，禁止覆寫原檔！"])
        }
        
        let ext = outputUrl.pathExtension.lowercased()
        let insp = try? probe(fileUrl: inputUrl)
        let pixFmt = insp?.videoPixelFormat?.lowercased() ?? ""
        let totalDurationUs = (insp?.duration ?? 0) * 1_000_000.0
        
        var vArgs: [String] = []
        var aArgs: [String] = []
        
        if compatibleMode {
            // 通用相容模式：強制轉為容器標準編碼與音訊，適配所有設備與高位深/特殊色度來源
            if ext == "webm" {
                vArgs = ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "30"]
                aArgs = ["-c:a", "libopus", "-b:a", "192k"]
            } else if ext == "mxf" {
                vArgs = ["-c:v", "mpeg2video", "-s", "720x576", "-r", "25", "-qscale:v", "2"]
                aArgs = ["-c:a", "pcm_s16le", "-ar", "48000"]
            } else if ext == "avi" {
                vArgs = ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-preset", "medium"]
                aArgs = ["-c:a", "mp3", "-b:a", "320k"]
            } else {
                vArgs = ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-preset", "medium"]
                aArgs = ["-c:a", "aac", "-b:a", "256k"]
            }
        } else if ext == "mkv" {
            // Matroska + FFV1 真正的數學無損保存格式
            vArgs = ["-c:v", "ffv1", "-level", "3", "-g", "1"]
            aArgs = ["-c:a", "flac"]
        } else if ext == "mov" {
            // Apple QuickTime + ProRes 4444 XQ
            // 視覺級極限近似無損 (12-bit，非數學 1:1 一致)
            vArgs = ["-c:v", "prores_ks", "-profile:v", "5", "-vendor", "apl0", "-bits_per_mb", "8000"]
            aArgs = ["-c:a", "pcm_s24le"]
        } else if ext == "webm" {
            vArgs = ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "30"]
            aArgs = ["-c:a", "libopus", "-b:a", "192k"]
        } else if ext == "avi" {
            vArgs = ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-preset", "medium"]
            aArgs = ["-c:a", "mp3", "-b:a", "320k"]
        } else if ext == "ts" {
            vArgs = ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-preset", "medium"]
            aArgs = ["-c:a", "aac", "-b:a", "256k"]
        } else if ext == "mxf" {
            vArgs = ["-c:v", "mpeg2video", "-s", "720x576", "-r", "25", "-qscale:v", "2"]
            aArgs = ["-c:a", "pcm_s16le", "-ar", "48000"]
        } else {
            // MP4 (libx264 CRF 0): 嚴格檢查來源位深與色度取樣
            if !pixFmt.isEmpty && pixFmt != "yuv420p" {
                throw NSError(domain: "FFmpegRunner", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "來源像素格式為 [\(pixFmt)]（高位深/色度非 4:2:0），MP4 (libx264) 會靜默降階造成資料損失！請改選【MP4 通用相容】或【MKV FFV1 典藏無損】！"
                ])
            }
            vArgs = ["-c:v", "libx264", "-crf", "0", "-preset", "medium"]
            aArgs = ["-c:a", "alac"]
        }
        
        var args = ["-nostdin", "-nostats", "-loglevel", "warning", "-progress", "pipe:1", "-y", "-i", inputUrl.path]
        args.append(contentsOf: ["-map", "0:v?", "-map", "0:a?", "-dn"])
        args.append(contentsOf: vArgs)
        args.append(contentsOf: aArgs)
        args.append(contentsOf: ["-map_metadata", "0", outputUrl.path])
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.standardInput = FileHandle.nullDevice
        process.arguments = args
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        processObserver?(process)
        
        var currentProgress: Double = 0.05
        var currentSpeed: String = "計算中..."
        var currentEta: String = "計算中..."
        
        var buffer = ""
        let outHandle = outPipe.fileHandleForReading
        outHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            buffer += text
            while let nlRange = buffer.range(of: "\n") {
                let line = String(buffer[..<nlRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                buffer.removeSubrange(...nlRange.lowerBound)
                
                if line.hasPrefix("out_time_us=") {
                    let valStr = String(line.dropFirst("out_time_us=".count))
                    if let us = Double(valStr), totalDurationUs > 0 {
                        currentProgress = min(0.99, max(0.01, us / totalDurationUs))
                    }
                } else if line.hasPrefix("speed=") {
                    let sStr = String(line.dropFirst("speed=".count)).trimmingCharacters(in: .whitespaces)
                    currentSpeed = (sStr.isEmpty || sStr == "N/A") ? "未知" : sStr
                    if let spd = Double(currentSpeed.replacingOccurrences(of: "x", with: "")), spd > 0, totalDurationUs > 0 {
                        let remSec = max(0, (totalDurationUs - (currentProgress * totalDurationUs)) / (spd * 1_000_000.0))
                        currentEta = String(format: "%.1f秒", remSec)
                    } else {
                        currentEta = totalDurationUs > 0 ? "計算中..." : "不適用"
                    }
                    onProgress?(currentProgress, currentSpeed, currentEta)
                } else if line == "progress=end" {
                    currentProgress = 1.0
                    onProgress?(1.0, currentSpeed, "0秒")
                }
            }
        }
        
        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        outHandle.readabilityHandler = nil
        
        if process.terminationStatus != 0 {
            try? FileManager.default.removeItem(at: outputUrl)
            let errString = String(data: errData, encoding: .utf8) ?? "未知 FFmpeg 錯誤"
            throw NSError(domain: "FFmpegRunner", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "像素無損轉碼失敗: \(errString.suffix(400))"
            ])
        }
        onProgress?(1.0, currentSpeed.isEmpty ? "轉碼完成" : currentSpeed, "0秒")
    }

    // MARK: - Lossless Audio Conversion
    public func executeAudioLossless(
        inputUrl: URL,
        outputUrl: URL,
        targetBitDepth: Int? = nil,
        targetSampleRate: Int? = nil,
        processObserver: ((Process) -> Void)? = nil,
        onProgress: ((Double, String?, String?) -> Void)? = nil
    ) throws {
        guard let ffmpeg = resolveBinaryPath(name: "ffmpeg") else {
            throw NSError(domain: "FFmpegRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: "找不到 ffmpeg 執行檔"])
        }
        if FFmpegRunner.isSameFile(url1: inputUrl, url2: outputUrl) {
            throw NSError(domain: "FFmpegRunner", code: 3, userInfo: [NSLocalizedDescriptionKey: "嚴格安全保護：目標檔案與來源為相同檔案 (inode/路徑重疊)，禁止覆寫原檔！"])
        }

        let outExt = outputUrl.pathExtension.lowercased()
        let insp = try? probe(fileUrl: inputUrl)
        let totalDurationUs = (insp?.duration ?? 0) * 1_000_000.0

        var aArgs: [String] = []
        switch outExt {
        case "wav":
            let depth = targetBitDepth ?? insp?.streams.first(where: { $0.codecType == "audio" })?.bitDepth ?? 16
            if depth >= 32 {
                aArgs = ["-c:a", "pcm_s32le"]
            } else if depth >= 24 {
                aArgs = ["-c:a", "pcm_s24le"]
            } else {
                aArgs = ["-c:a", "pcm_s16le"]
            }
        case "flac":
            aArgs = ["-c:a", "flac"]
            if let depth = targetBitDepth {
                if depth >= 24 {
                    aArgs.append(contentsOf: ["-sample_fmt", "s32"])
                } else {
                    aArgs.append(contentsOf: ["-sample_fmt", "s16"])
                }
            }
        case "m4a":
            aArgs = ["-c:a", "alac"]
        case "aiff", "aif":
            let depth = targetBitDepth ?? insp?.streams.first(where: { $0.codecType == "audio" })?.bitDepth ?? 16
            if depth >= 24 {
                aArgs = ["-c:a", "pcm_s24be"]
            } else {
                aArgs = ["-c:a", "pcm_s16be"]
            }
        case "caf":
            let depth = targetBitDepth ?? insp?.streams.first(where: { $0.codecType == "audio" })?.bitDepth ?? 16
            if depth >= 24 {
                aArgs = ["-c:a", "pcm_s24le"]
            } else {
                aArgs = ["-c:a", "pcm_s16le"]
            }
        default:
            throw NSError(domain: "FFmpegRunner", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "不支援的無損音訊目標格式: .\(outExt)（支援 .wav, .flac, .m4a [alac], .aiff, .caf）"
            ])
        }

        if let sr = targetSampleRate, sr > 0 {
            aArgs.append(contentsOf: ["-ar", "\(sr)"])
        }

        var args = ["-nostdin", "-nostats", "-loglevel", "warning", "-progress", "pipe:1", "-y", "-i", inputUrl.path]
        args.append(contentsOf: ["-vn", "-sn", "-dn"])
        args.append(contentsOf: aArgs)
        args.append(contentsOf: ["-map_metadata", "0", outputUrl.path])

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.standardInput = FileHandle.nullDevice
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        processObserver?(process)

        var currentProgress: Double = 0.05
        var currentSpeed: String = "計算中..."
        var currentEta: String = "計算中..."

        var buffer = ""
        let outHandle = outPipe.fileHandleForReading
        outHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            buffer += text
            while let nlRange = buffer.range(of: "\n") {
                let line = String(buffer[..<nlRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                buffer.removeSubrange(...nlRange.lowerBound)

                if line.hasPrefix("out_time_us=") {
                    let valStr = String(line.dropFirst("out_time_us=".count))
                    if let us = Double(valStr), totalDurationUs > 0 {
                        currentProgress = min(0.99, max(0.01, us / totalDurationUs))
                    }
                } else if line.hasPrefix("speed=") {
                    let sStr = String(line.dropFirst("speed=".count)).trimmingCharacters(in: .whitespaces)
                    currentSpeed = (sStr.isEmpty || sStr == "N/A") ? "未知" : sStr
                    if let spd = Double(currentSpeed.replacingOccurrences(of: "x", with: "")), spd > 0, totalDurationUs > 0 {
                        let remSec = max(0, (totalDurationUs - (currentProgress * totalDurationUs)) / (spd * 1_000_000.0))
                        currentEta = String(format: "%.1f秒", remSec)
                    } else {
                        currentEta = totalDurationUs > 0 ? "計算中..." : "不適用"
                    }
                    onProgress?(currentProgress, currentSpeed, currentEta)
                } else if line == "progress=end" {
                    currentProgress = 1.0
                    onProgress?(1.0, currentSpeed, "0秒")
                }
            }
        }

        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        outHandle.readabilityHandler = nil

        if process.terminationStatus != 0 {
            try? FileManager.default.removeItem(at: outputUrl)
            let errString = String(data: errData, encoding: .utf8) ?? "未知 FFmpeg 錯誤"
            throw NSError(domain: "FFmpegRunner", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "無損音訊轉換失敗: \(errString.suffix(400))"
            ])
        }
        onProgress?(1.0, currentSpeed.isEmpty ? "完成" : currentSpeed, "0秒")
    }

    // MARK: - Lossy Audio / Downsampling Conversion
    public func executeAudioLossy(
        inputUrl: URL,
        outputUrl: URL,
        bitrate: String = "320k",
        targetSampleRate: Int? = nil,
        targetBitDepth: Int? = nil,
        processObserver: ((Process) -> Void)? = nil,
        onProgress: ((Double, String?, String?) -> Void)? = nil
    ) throws {
        guard let ffmpeg = resolveBinaryPath(name: "ffmpeg") else {
            throw NSError(domain: "FFmpegRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: "找不到 ffmpeg 執行檔"])
        }
        if FFmpegRunner.isSameFile(url1: inputUrl, url2: outputUrl) {
            throw NSError(domain: "FFmpegRunner", code: 3, userInfo: [NSLocalizedDescriptionKey: "嚴格安全保護：目標檔案與來源為相同檔案 (inode/路徑重疊)，禁止覆寫原檔！"])
        }

        let outExt = outputUrl.pathExtension.lowercased()
        let insp = try? probe(fileUrl: inputUrl)
        let inChannels = insp?.streams.first(where: { $0.codecType == "audio" })?.channels ?? 2
        let totalDurationUs = (insp?.duration ?? 0) * 1_000_000.0

        var effectiveBitrate = bitrate
        var aArgs: [String] = []
        switch outExt {
        case "mp3":
            aArgs = ["-c:a", "libmp3lame", "-b:a", effectiveBitrate]
        case "m4a", "aac":
            aArgs = ["-c:a", "aac", "-b:a", effectiveBitrate]
        case "ogg":
            // 原生 vorbis 編碼器為實驗性質，需 -strict -2；且原生 vorbis 僅支援立體聲 (2 聲道)，非 2 聲道需自適應重採樣為 2 聲道
            aArgs = ["-c:a", "vorbis", "-strict", "-2", "-b:a", effectiveBitrate]
            if inChannels != 2 {
                aArgs.append(contentsOf: ["-ac", "2"])
            }
        case "opus":
            // libopus 每聲道上限為 256kbps，單聲道 (mono) 上限為 256k，超過需自適應鉗制
            if inChannels == 1 {
                if let kbps = Int(effectiveBitrate.lowercased().replacingOccurrences(of: "k", with: "")), kbps > 256 {
                    effectiveBitrate = "256k"
                } else if effectiveBitrate == "320k" {
                    effectiveBitrate = "256k"
                }
            }
            aArgs = ["-c:a", "libopus", "-b:a", effectiveBitrate]
        case "ac3":
            aArgs = ["-c:a", "ac3", "-b:a", effectiveBitrate]
        default:
            aArgs = ["-c:a", "libmp3lame", "-b:a", effectiveBitrate]
        }

        if let sr = targetSampleRate, sr > 0 {
            if outExt == "opus" {
                if [8000, 12000, 16000, 24000, 48000].contains(sr) {
                    aArgs.append(contentsOf: ["-ar", "\(sr)"])
                } else {
                    aArgs.append(contentsOf: ["-ar", "48000"])
                }
            } else {
                aArgs.append(contentsOf: ["-ar", "\(sr)"])
            }
        }

        var args = ["-nostdin", "-nostats", "-loglevel", "warning", "-progress", "pipe:1", "-y", "-i", inputUrl.path]
        args.append(contentsOf: ["-vn", "-sn", "-dn"])
        args.append(contentsOf: aArgs)
        args.append(contentsOf: ["-map_metadata", "0", outputUrl.path])

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.standardInput = FileHandle.nullDevice
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        processObserver?(process)

        var currentProgress: Double = 0.05
        var currentSpeed: String = "計算中..."
        var currentEta: String = "計算中..."

        var buffer = ""
        let outHandle = outPipe.fileHandleForReading
        outHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            buffer += text
            while let nlRange = buffer.range(of: "\n") {
                let line = String(buffer[..<nlRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                buffer.removeSubrange(...nlRange.lowerBound)

                if line.hasPrefix("out_time_us=") {
                    let valStr = String(line.dropFirst("out_time_us=".count))
                    if let us = Double(valStr), totalDurationUs > 0 {
                        currentProgress = min(0.99, max(0.01, us / totalDurationUs))
                    }
                } else if line.hasPrefix("speed=") {
                    let sStr = String(line.dropFirst("speed=".count)).trimmingCharacters(in: .whitespaces)
                    currentSpeed = (sStr.isEmpty || sStr == "N/A") ? "未知" : sStr
                    if let spd = Double(currentSpeed.replacingOccurrences(of: "x", with: "")), spd > 0, totalDurationUs > 0 {
                        let remSec = max(0, (totalDurationUs - (currentProgress * totalDurationUs)) / (spd * 1_000_000.0))
                        currentEta = String(format: "%.1f秒", remSec)
                    } else {
                        currentEta = totalDurationUs > 0 ? "計算中..." : "不適用"
                    }
                    onProgress?(currentProgress, currentSpeed, currentEta)
                } else if line == "progress=end" {
                    currentProgress = 1.0
                    onProgress?(1.0, currentSpeed, "0秒")
                }
            }
        }

        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        outHandle.readabilityHandler = nil

        if process.terminationStatus != 0 {
            try? FileManager.default.removeItem(at: outputUrl)
            let errString = String(data: errData, encoding: .utf8) ?? "未知 FFmpeg 錯誤"
            throw NSError(domain: "FFmpegRunner", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "有損音訊降轉失敗: \(errString.suffix(400))"
            ])
        }
        onProgress?(1.0, currentSpeed.isEmpty ? "完成" : currentSpeed, "0秒")
    }

    // MARK: - Verification Helpers
    public struct RemuxVerificationResult {
        public var hasVideo: Bool
        public var hasAudio: Bool
        public var videoHashMatch: Bool?
        public var audioHashMatch: Bool?
        public var inputVideoHash: String?
        public var outputVideoHash: String?
        public var inputAudioHash: String?
        public var outputAudioHash: String?
        public var allMatched: Bool
        public var note: String
    }
    
    public func verifyRemux(inputUrl: URL, outputUrl: URL) -> RemuxVerificationResult {
        let inInsp = try? probe(fileUrl: inputUrl)
        let hasVideo = inInsp?.streams.contains(where: { $0.codecType == "video" }) ?? false
        let hasAudio = inInsp?.streams.contains(where: { $0.codecType == "audio" }) ?? false
        
        var inV: String? = nil
        var outV: String? = nil
        var vMatch: Bool? = nil
        
        if hasVideo {
            inV = computeBitstreamMd5(fileUrl: inputUrl, streamSpecifier: "0:v:0")
            outV = computeBitstreamMd5(fileUrl: outputUrl, streamSpecifier: "0:v:0")
            if let iv = inV, let ov = outV {
                vMatch = (iv == ov)
            } else {
                vMatch = false
            }
        }
        
        var inA: String? = nil
        var outA: String? = nil
        var aMatch: Bool? = nil
        
        if hasAudio {
            inA = computeBitstreamMd5(fileUrl: inputUrl, streamSpecifier: "0:a:0")
            outA = computeBitstreamMd5(fileUrl: outputUrl, streamSpecifier: "0:a:0")
            if let ia = inA, let oa = outA {
                aMatch = (ia == oa)
            } else {
                aMatch = false
            }
        }
        
        var allOk = true
        var notes: [String] = []
        
        if hasVideo {
            if vMatch == true {
                notes.append("視訊串流 MD5 吻合 (\(inV!))")
            } else if inV != nil && outV != nil {
                allOk = false
                notes.append("視訊串流 MD5 不一致 (來源: \(inV!) vs 產物: \(outV!))")
            } else {
                allOk = false
                notes.append("視訊位元流提取失敗")
            }
        }
        
        if hasAudio {
            if aMatch == true {
                notes.append("音訊串流 MD5 吻合 (\(inA!))")
            } else if inA != nil && outA != nil {
                allOk = false
                notes.append("音訊串流 MD5 不一致 (來源: \(inA!) vs 產物: \(outA!))")
            } else {
                allOk = false
                notes.append("音訊位元流提取失敗")
            }
        }
        
        if !hasVideo && !hasAudio {
            allOk = false
            notes.append("未偵測到任何影音串流可驗證")
        }
        
        return RemuxVerificationResult(
            hasVideo: hasVideo,
            hasAudio: hasAudio,
            videoHashMatch: vMatch,
            audioHashMatch: aMatch,
            inputVideoHash: inV,
            outputVideoHash: outV,
            inputAudioHash: inA,
            outputAudioHash: outA,
            allMatched: allOk,
            note: notes.joined(separator: "；")
        )
    }

    public func computeBitstreamMd5(fileUrl: URL, streamSpecifier: String? = nil) -> String? {
        guard let ffmpeg = resolveBinaryPath(name: "ffmpeg") else { return nil }
        let specifier: String
        if let s = streamSpecifier {
            specifier = s
        } else {
            if let insp = try? probe(fileUrl: fileUrl) {
                if insp.streams.contains(where: { $0.codecType == "video" }) {
                    specifier = "0:v:0"
                } else if insp.streams.contains(where: { $0.codecType == "audio" }) {
                    specifier = "0:a:0"
                } else {
                    return nil
                }
            } else {
                specifier = "0:v:0"
            }
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.standardInput = FileHandle.nullDevice
        p.arguments = ["-nostdin", "-v", "quiet", "-i", fileUrl.path, "-map", specifier, "-c", "copy", "-f", "md5", "-"]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0, let str = String(data: data, encoding: .utf8), !str.isEmpty else { return nil }
        return str.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "MD5=", with: "")
    }
    
    public func computeFramemd5(fileUrl: URL, maxFrames: Int = 30) -> String? {
        guard let ffmpeg = resolveBinaryPath(name: "ffmpeg") else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.standardInput = FileHandle.nullDevice
        p.arguments = ["-nostdin", "-v", "quiet", "-i", fileUrl.path, "-vframes", "\(maxFrames)", "-f", "framemd5", "-"]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0, let str = String(data: data, encoding: .utf8) else { return nil }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public func computeRawVideoMd5(fileUrl: URL, maxFrames: Int = 30) -> String? {
        guard let ffmpeg = resolveBinaryPath(name: "ffmpeg") else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.standardInput = FileHandle.nullDevice
        p.arguments = ["-nostdin", "-v", "quiet", "-i", fileUrl.path, "-vframes", "\(maxFrames)", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public func computeAudioPcmMd5(fileUrl: URL, pcmCodec: String = "pcm_s16le") -> String? {
        guard let ffmpeg = resolveBinaryPath(name: "ffmpeg") else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.standardInput = FileHandle.nullDevice
        p.arguments = ["-nostdin", "-v", "quiet", "-i", fileUrl.path, "-vn", "-sn", "-c:a", pcmCodec, "-f", "md5", "-"]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0, let str = String(data: data, encoding: .utf8), !str.isEmpty else { return nil }
        return str.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "MD5=", with: "")
    }
}
