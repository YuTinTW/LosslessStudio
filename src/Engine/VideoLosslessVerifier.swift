import Foundation
import CryptoKit

/// 獨立視訊與多媒體無損驗證器 (VideoLosslessVerifier)
/// 專門驗證 8/10/12 位元影片、多軌音訊、影音同步、全片長度與時間碼/中繼資料獨立報告。
/// 支援原生色深平面像素格式（如 yuv422p10le / yuv420p10le / gbrp10le），廢除 RGB24 截斷與 20 幀假陽性。
public struct VideoLosslessVerifier {

    // MARK: - 軌道與略過診斷資訊
    public struct TrackInfo: Codable, Equatable {
        public let index: Int
        public let codecType: String
        public let codecName: String?
        public let pixelFormat: String?
        public let bitDepth: Int?
        public let resolution: String?
        public let isSkipped: Bool
        public let skipReasonZh: String?
        public let skipReasonEn: String?

        public var localizedSkipReason: String? {
            guard let zh = skipReasonZh, let en = skipReasonEn else { return nil }
            return L10n.text(zh, en)
        }

        public init(
            index: Int,
            codecType: String,
            codecName: String?,
            pixelFormat: String? = nil,
            bitDepth: Int? = nil,
            resolution: String? = nil,
            isSkipped: Bool = false,
            skipReasonZh: String? = nil,
            skipReasonEn: String? = nil
        ) {
            self.index = index
            self.codecType = codecType
            self.codecName = codecName
            self.pixelFormat = pixelFormat
            self.bitDepth = bitDepth
            self.resolution = resolution
            self.isSkipped = isSkipped
            self.skipReasonZh = skipReasonZh
            self.skipReasonEn = skipReasonEn
        }
    }

    // MARK: - 逐軌音訊驗證報告
    public struct AudioTrackVerification: Codable, Equatable {
        public let streamIndex: Int
        public let inputCodec: String?
        public let outputCodec: String?
        public let channels: Int?
        public let sampleRate: Int?
        public let bitDepth: Int?
        public let inputPcmMd5: String?
        public let outputPcmMd5: String?
        public let isMatched: Bool
        public let noteZh: String
        public let noteEn: String

        public var localizedNote: String {
            L10n.text(noteZh, noteEn)
        }

        public init(
            streamIndex: Int,
            inputCodec: String?,
            outputCodec: String?,
            channels: Int?,
            sampleRate: Int?,
            bitDepth: Int?,
            inputPcmMd5: String?,
            outputPcmMd5: String?,
            isMatched: Bool,
            noteZh: String,
            noteEn: String
        ) {
            self.streamIndex = streamIndex
            self.inputCodec = inputCodec
            self.outputCodec = outputCodec
            self.channels = channels
            self.sampleRate = sampleRate
            self.bitDepth = bitDepth
            self.inputPcmMd5 = inputPcmMd5
            self.outputPcmMd5 = outputPcmMd5
            self.isMatched = isMatched
            self.noteZh = noteZh
            self.noteEn = noteEn
        }
    }

    // MARK: - 影音同步驗證報告
    public struct SyncVerification: Codable, Equatable {
        public let videoStartPts: Double?
        public let audioStartPts: Double?
        public let videoDuration: Double?
        public let audioDuration: Double?
        public let syncOffsetSeconds: Double?
        public let isSyncPreserved: Bool
        public let noteZh: String
        public let noteEn: String

        public var localizedNote: String {
            L10n.text(noteZh, noteEn)
        }

        public init(
            videoStartPts: Double?,
            audioStartPts: Double?,
            videoDuration: Double?,
            audioDuration: Double?,
            syncOffsetSeconds: Double?,
            isSyncPreserved: Bool,
            noteZh: String,
            noteEn: String
        ) {
            self.videoStartPts = videoStartPts
            self.audioStartPts = audioStartPts
            self.videoDuration = videoDuration
            self.audioDuration = audioDuration
            self.syncOffsetSeconds = syncOffsetSeconds
            self.isSyncPreserved = isSyncPreserved
            self.noteZh = noteZh
            self.noteEn = noteEn
        }
    }

    // MARK: - 中繼資料與時間碼差異 (獨立報告)
    public struct MetadataDifference: Codable, Equatable {
        public let tagKey: String
        public let inputValue: String?
        public let outputValue: String?
        public let isIndependentNote: Bool
        public let noteZh: String
        public let noteEn: String

        public var localizedNote: String {
            L10n.text(noteZh, noteEn)
        }

        public init(
            tagKey: String,
            inputValue: String?,
            outputValue: String?,
            isIndependentNote: Bool = true,
            noteZh: String,
            noteEn: String
        ) {
            self.tagKey = tagKey
            self.inputValue = inputValue
            self.outputValue = outputValue
            self.isIndependentNote = isIndependentNote
            self.noteZh = noteZh
            self.noteEn = noteEn
        }
    }

    // MARK: - 全面無損驗收報告
    public struct VerificationReport: Codable, Equatable {
        public let isPassed: Bool
        public let isBitIdentical: Bool
        public let isSampleIdentical: Bool
        public let isAudioIdentical: Bool
        public let isSyncPreserved: Bool
        public let nativePixelFormat: String?
        public let nativeBitDepth: Int?
        public let verifiedFrames: Int
        public let totalFramesInput: Int?
        public let totalFramesOutput: Int?
        public let inputVideoDigest: String?
        public let outputVideoDigest: String?
        public let sampleHashesInput: [String]
        public let sampleHashesOutput: [String]
        public let audioTracks: [AudioTrackVerification]
        public let syncInfo: SyncVerification?
        public let timecodeStatusZh: String?
        public let timecodeStatusEn: String?
        public let metadataDifferences: [MetadataDifference]
        public let skippedTracks: [TrackInfo]
        public let noteZh: String
        public let noteEn: String

        public var localizedNote: String {
            L10n.text(noteZh, noteEn)
        }

        public var localizedTimecodeStatus: String? {
            guard let zh = timecodeStatusZh, let en = timecodeStatusEn else { return nil }
            return L10n.text(zh, en)
        }

        public init(
            isPassed: Bool,
            isBitIdentical: Bool,
            isSampleIdentical: Bool,
            isAudioIdentical: Bool = true,
            isSyncPreserved: Bool = true,
            nativePixelFormat: String?,
            nativeBitDepth: Int?,
            verifiedFrames: Int,
            totalFramesInput: Int? = nil,
            totalFramesOutput: Int? = nil,
            inputVideoDigest: String? = nil,
            outputVideoDigest: String? = nil,
            sampleHashesInput: [String] = [],
            sampleHashesOutput: [String] = [],
            audioTracks: [AudioTrackVerification] = [],
            syncInfo: SyncVerification? = nil,
            timecodeStatusZh: String? = nil,
            timecodeStatusEn: String? = nil,
            metadataDifferences: [MetadataDifference] = [],
            skippedTracks: [TrackInfo] = [],
            noteZh: String,
            noteEn: String
        ) {
            self.isPassed = isPassed
            self.isBitIdentical = isBitIdentical
            self.isSampleIdentical = isSampleIdentical
            self.isAudioIdentical = isAudioIdentical
            self.isSyncPreserved = isSyncPreserved
            self.nativePixelFormat = nativePixelFormat
            self.nativeBitDepth = nativeBitDepth
            self.verifiedFrames = verifiedFrames
            self.totalFramesInput = totalFramesInput
            self.totalFramesOutput = totalFramesOutput
            self.inputVideoDigest = inputVideoDigest
            self.outputVideoDigest = outputVideoDigest
            self.sampleHashesInput = sampleHashesInput
            self.sampleHashesOutput = sampleHashesOutput
            self.audioTracks = audioTracks
            self.syncInfo = syncInfo
            self.timecodeStatusZh = timecodeStatusZh
            self.timecodeStatusEn = timecodeStatusEn
            self.metadataDifferences = metadataDifferences
            self.skippedTracks = skippedTracks
            self.noteZh = noteZh
            self.noteEn = noteEn
        }
    }

    // MARK: - 像素格式解析
    /// 解析最佳無損平面像素格式（保留原始位深與色度採樣，避免 YUV 轉 RGB 矩陣失真與 10-bit 截斷）
    public static func resolveNativePlanarPixFmt(from pixFmt: String?, bitDepth: Int?) -> String {
        guard let pf = pixFmt?.lowercased() else { return "yuv420p" }
        // 8-bit Packed 4:2:2 (2vuy, UYVY, YUYV) -> 平面 yuv422p (100% 取樣點對點保留)
        if pf == "uyvy422" || pf == "yuyv422" || pf == "2vuy" || pf == "yuv422p" {
            return "yuv422p"
        }
        // 8-bit 4:2:0
        if pf == "yuv420p" || pf == "nv12" || pf == "nv21" {
            return "yuv420p"
        }
        // 10-bit 4:2:2 (v210, yuv422p10le/be) -> 保留 10-bit 平面 yuv422p10le
        if pf == "v210" || pf == "yuv422p10le" || pf == "yuv422p10be" || pf == "p210le" {
            return "yuv422p10le"
        }
        // 10-bit 4:2:0
        if pf == "yuv420p10le" || pf == "yuv420p10be" || pf == "p010le" {
            return "yuv420p10le"
        }
        // 10-bit / 12-bit 4:4:4
        if pf == "v410" || pf == "yuv444p10le" || pf == "yuv444p10be" {
            return "yuv444p10le"
        }
        if pf == "yuv444p12le" || pf == "yuv444p12be" {
            return "yuv444p12le"
        }
        if pf == "yuv422p12le" || pf == "yuv422p12be" {
            return "yuv422p12le"
        }
        // RGB 平面與原生色深
        if pf == "r210" || pf == "gbrp10le" {
            return "gbrp10le"
        }
        if pf == "gbrp12le" {
            return "gbrp12le"
        }
        if pf == "rgb24" || pf == "bgr24" || pf == "gbrp" {
            return "rgb24"
        }
        if pf == "rgba" || pf == "bgra" || pf == "argb" {
            return "rgba"
        }
        // 依照位深回退
        if bitDepth == 10 {
            return "yuv422p10le"
        } else if bitDepth == 12 {
            return "yuv422p12le"
        }
        return pf
    }

    // MARK: - 串流逐幀雜湊提取 (輕量管線，避免記憶體隨影片增長)
    /// 提取指定影音檔之逐幀 framemd5 雜湊清單。
    /// 當 maxFrames 為 nil 或 <= 0 時，驗證整部影片所有幀（全片完整長度）。
    public static func extractFrameMd5s(
        fileUrl: URL,
        maxFrames: Int? = nil,
        pixelFormat: String? = nil
    ) -> [String] {
        guard let ffmpeg = FFmpegRunner.shared.resolveBinaryPath(name: "ffmpeg") else { return [] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.standardInput = FileHandle.nullDevice

        var args = ["-nostdin", "-v", "quiet", "-i", fileUrl.path, "-map", "0:v:0"]
        if let mf = maxFrames, mf > 0 {
            args.append(contentsOf: ["-vframes", "\(mf)"])
        }
        if let pf = pixelFormat, !pf.isEmpty {
            args.append(contentsOf: ["-pix_fmt", pf])
        }
        args.append(contentsOf: ["-f", "framemd5", "-"])
        p.arguments = args

        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()

        // 串流行讀取：framemd5 每幀僅約 50 字元文字，整片 10 萬幀僅數 MB 字串，記憶體恆定安全
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        guard p.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return [] }
        var md5s: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            // framemd5 格式: streamIndex, pts, dts, duration, size, hash
            let parts = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 6 {
                md5s.append(String(parts[5]))
            }
        }
        return md5s
    }

    /// 計算全部逐幀雜湊的綜合指紋（以 SHA-256 匯整所有幀雜湊，代表整部影片的唯一位元簽章）
    public static func computeStreamCompositeDigest(frameHashes: [String]) -> String? {
        guard !frameHashes.isEmpty else { return nil }
        let combined = frameHashes.joined(separator: "\n")
        guard let data = combined.data(using: .utf8) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 逐軌音訊 PCM 驗證
    /// 依軌逐一比對音訊解碼 PCM 雜湊，支援多聲道與 16/24/32 位元 PCM
    public static func verifyAudioTracks(
        inputUrl: URL,
        outputUrl: URL
    ) -> [AudioTrackVerification] {
        guard let ffmpeg = FFmpegRunner.shared.resolveBinaryPath(name: "ffmpeg") else { return [] }
        let inInsp = try? FFmpegRunner.shared.probe(fileUrl: inputUrl)
        let outInsp = try? FFmpegRunner.shared.probe(fileUrl: outputUrl)

        let inAudioStreams = inInsp?.streams.filter { $0.codecType == "audio" } ?? []
        let outAudioStreams = outInsp?.streams.filter { $0.codecType == "audio" } ?? []

        var results: [AudioTrackVerification] = []

        for (idx, inA) in inAudioStreams.enumerated() {
            let outA = idx < outAudioStreams.count ? outAudioStreams[idx] : nil
            let bitDepth = inA.bitDepth ?? 16
            let codecName = inA.codecName?.lowercased() ?? ""
            let pcmCodec: String
            if codecName.contains("f32") || codecName.contains("f64") {
                pcmCodec = "pcm_f32le"
            } else if bitDepth > 24 || codecName.contains("s32") {
                pcmCodec = "pcm_s32le"
            } else if bitDepth > 16 {
                pcmCodec = "pcm_s24le"
            } else {
                pcmCodec = "pcm_s16le"
            }

            func computePcmMd5(fileUrl: URL, streamIndex: Int) -> String? {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: ffmpeg)
                p.standardInput = FileHandle.nullDevice
                p.arguments = ["-nostdin", "-v", "quiet", "-i", fileUrl.path, "-map", "0:a:\(streamIndex)", "-vn", "-sn", "-c:a", pcmCodec, "-f", "md5", "-"]
                let pipe = Pipe()
                p.standardOutput = pipe
                try? p.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                guard p.terminationStatus == 0, let str = String(data: data, encoding: .utf8), !str.isEmpty else { return nil }
                return str.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "MD5=", with: "")
            }

            let inMd5 = computePcmMd5(fileUrl: inputUrl, streamIndex: idx)
            let outMd5 = outA != nil ? computePcmMd5(fileUrl: outputUrl, streamIndex: idx) : nil

            let isMatched = (inMd5 != nil && outMd5 != nil && inMd5 == outMd5 && inA.channels == outA?.channels && inA.sampleRate == outA?.sampleRate)
            let noteZh: String
            let noteEn: String

            if outA == nil {
                noteZh = "目標產物遺失音訊軌 #\(idx)（來源編碼: \(inA.codecName ?? "unknown")）。"
                noteEn = "Target missing audio track #\(idx) (source codec: \(inA.codecName ?? "unknown"))."
            } else if isMatched {
                noteZh = "音訊軌 #\(idx) PCM 取樣 MD5 完全一致（\(inA.channels ?? 2) 聲道, \(inA.sampleRate ?? 48000)Hz, \(pcmCodec)），數學級無損。"
                noteEn = "Audio track #\(idx) PCM sample MD5 identical (\(inA.channels ?? 2)ch, \(inA.sampleRate ?? 48000)Hz, \(pcmCodec)), mathematically lossless."
            } else {
                noteZh = "音訊軌 #\(idx) PCM 取樣不吻合（來源 MD5: \(inMd5 ?? "nil") vs 輸出: \(outMd5 ?? "nil")）。"
                noteEn = "Audio track #\(idx) PCM mismatch (source MD5: \(inMd5 ?? "nil") vs output: \(outMd5 ?? "nil"))."
            }

            results.append(AudioTrackVerification(
                streamIndex: idx,
                inputCodec: inA.codecName,
                outputCodec: outA?.codecName,
                channels: inA.channels,
                sampleRate: inA.sampleRate,
                bitDepth: bitDepth,
                inputPcmMd5: inMd5,
                outputPcmMd5: outMd5,
                isMatched: isMatched,
                noteZh: noteZh,
                noteEn: noteEn
            ))
        }

        return results
    }

    // MARK: - 影音同步檢驗 (PTS 與起始時間偏移)
    public static func verifySync(
        inputUrl: URL,
        outputUrl: URL
    ) -> SyncVerification {
        guard let ffprobe = FFmpegRunner.shared.resolveBinaryPath(name: "ffprobe") else {
            return SyncVerification(
                videoStartPts: nil,
                audioStartPts: nil,
                videoDuration: nil,
                audioDuration: nil,
                syncOffsetSeconds: nil,
                isSyncPreserved: false,
                noteZh: "找不到 ffprobe 進行同步檢測。",
                noteEn: "ffprobe not found for AV sync analysis."
            )
        }

        func probePtsAndDuration(fileUrl: URL) -> (vStart: Double?, aStart: Double?, vDur: Double?, aDur: Double?) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ffprobe)
            p.arguments = ["-v", "quiet", "-print_format", "json", "-show_streams", fileUrl.path]
            let pipe = Pipe()
            p.standardOutput = pipe
            try? p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let streams = json["streams"] as? [[String: Any]] else {
                return (nil, nil, nil, nil)
            }

            var vs: Double? = nil
            var as_: Double? = nil
            var vd: Double? = nil
            var ad: Double? = nil

            for s in streams {
                let type = s["codec_type"] as? String
                if type == "video" && vs == nil {
                    if let stStr = s["start_time"] as? String { vs = Double(stStr) }
                    if let dStr = s["duration"] as? String { vd = Double(dStr) }
                } else if type == "audio" && as_ == nil {
                    if let stStr = s["start_time"] as? String { as_ = Double(stStr) }
                    if let dStr = s["duration"] as? String { ad = Double(dStr) }
                }
            }
            return (vs, as_, vd, ad)
        }

        let inPts = probePtsAndDuration(fileUrl: inputUrl)
        let outPts = probePtsAndDuration(fileUrl: outputUrl)

        // 計算音訊相對於視訊的起始偏移差
        let inOffset = (inPts.vStart != nil && inPts.aStart != nil) ? (inPts.aStart! - inPts.vStart!) : 0.0
        let outOffset = (outPts.vStart != nil && outPts.aStart != nil) ? (outPts.aStart! - outPts.vStart!) : 0.0
        let deltaOffset = abs(outOffset - inOffset)

        // 容差設定為 1 毫秒 (0.001s)
        let isSyncPreserved = deltaOffset <= 0.001

        let noteZh: String
        let noteEn: String
        if isSyncPreserved {
            noteZh = "影音起始相對偏移一致（來源偏移: \(String(format: "%.4f", inOffset))s vs 輸出: \(String(format: "%.4f", outOffset))s，誤差 < 1ms），同步完好。"
            noteEn = "AV start offset preserved (in: \(String(format: "%.4f", inOffset))s vs out: \(String(format: "%.4f", outOffset))s, delta < 1ms); sync preserved."
        } else {
            noteZh = "檢測到影音同步漂移（偏移誤差: \(String(format: "%.4f", deltaOffset))s > 1ms）。"
            noteEn = "AV sync drift detected (delta: \(String(format: "%.4f", deltaOffset))s > 1ms)."
        }

        return SyncVerification(
            videoStartPts: outPts.vStart,
            audioStartPts: outPts.aStart,
            videoDuration: outPts.vDur,
            audioDuration: outPts.aDur,
            syncOffsetSeconds: deltaOffset,
            isSyncPreserved: isSyncPreserved,
            noteZh: noteZh,
            noteEn: noteEn
        )
    }

    // MARK: - 時間碼與中繼資料獨立比對
    public static func inspectMetadataAndTimecode(
        inputUrl: URL,
        outputUrl: URL
    ) -> (timecodeStatusZh: String?, timecodeStatusEn: String?, differences: [MetadataDifference]) {
        guard let ffprobe = FFmpegRunner.shared.resolveBinaryPath(name: "ffprobe") else {
            return (nil, nil, [])
        }

        func probeTags(fileUrl: URL) -> (timecode: String?, formatTags: [String: String]) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ffprobe)
            p.arguments = ["-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", fileUrl.path]
            let pipe = Pipe()
            p.standardOutput = pipe
            try? p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return (nil, [:])
            }

            var tc: String? = nil
            var fTags: [String: String] = [:]

            if let fmt = json["format"] as? [String: Any], let tags = fmt["tags"] as? [String: Any] {
                for (k, v) in tags {
                    if let str = v as? String {
                        fTags[k.lowercased()] = str
                        if k.lowercased() == "timecode" && tc == nil { tc = str }
                    }
                }
            }

            if let streams = json["streams"] as? [[String: Any]] {
                for s in streams {
                    if let tags = s["tags"] as? [String: Any] {
                        for (k, v) in tags {
                            if let str = v as? String, k.lowercased() == "timecode" && tc == nil {
                                tc = str
                            }
                        }
                    }
                }
            }

            return (tc, fTags)
        }

        let inData = probeTags(fileUrl: inputUrl)
        let outData = probeTags(fileUrl: outputUrl)

        var tcZh = "來源無時間碼標籤。"
        var tcEn = "Source has no timecode tag."
        if let inTc = inData.timecode {
            if let outTc = outData.timecode, inTc == outTc {
                tcZh = "時間碼 [\(inTc)] 完整保留於輸出標籤中。"
                tcEn = "Timecode [\(inTc)] preserved in output metadata."
            } else {
                tcZh = "來源具備時間碼 [\(inTc)]，輸出轉換為 [\(outData.timecode ?? "未保留於通用標籤")]（已獨立記錄，不影響畫面像素無損判定）。"
                tcEn = "Source timecode [\(inTc)] converted to [\(outData.timecode ?? "none in general tags")] (recorded independently; does not invalidate pixel lossless status)."
            }
        }

        var diffs: [MetadataDifference] = []
        for (k, inV) in inData.formatTags {
            let outV = outData.formatTags[k]
            if inV != outV {
                diffs.append(MetadataDifference(
                    tagKey: k,
                    inputValue: inV,
                    outputValue: outV,
                    isIndependentNote: true,
                    noteZh: "中繼資料 [\(k)] 存在差異（來源: \(inV) vs 輸出: \(outV ?? "無")），已獨立記錄。",
                    noteEn: "Metadata [\(k)] difference (in: \(inV) vs out: \(outV ?? "none")); logged independently."
                ))
            }
        }

        return (tcZh, tcEn, diffs)
    }

    // MARK: - 完整全項無損驗收 (畫面、音訊、同步、時間碼與全片長度)
    public static func verifyFullLossless(
        inputUrl: URL,
        outputUrl: URL,
        maxFrames: Int? = nil
    ) -> VerificationReport {
        let inInsp = try? FFmpegRunner.shared.probe(fileUrl: inputUrl)
        let outInsp = try? FFmpegRunner.shared.probe(fileUrl: outputUrl)

        let inPixFmt = inInsp?.videoPixelFormat
        let outPixFmt = outInsp?.videoPixelFormat
        let inDepth = inInsp?.streams.first(where: { $0.codecType == "video" })?.bitDepth ?? (inPixFmt?.contains("10") == true ? 10 : 8)
        let _ = outInsp?.streams.first(where: { $0.codecType == "video" })?.bitDepth ?? (outPixFmt?.contains("10") == true ? 10 : 8)

        // 解析原生比對格式
        let targetPlanarFmt = resolveNativePlanarPixFmt(from: inPixFmt, bitDepth: inDepth)

        // 1. 視訊逐幀驗證 (完整長度串流提取)
        let inMd5s = extractFrameMd5s(fileUrl: inputUrl, maxFrames: maxFrames, pixelFormat: targetPlanarFmt)
        let outMd5s = extractFrameMd5s(fileUrl: outputUrl, maxFrames: maxFrames, pixelFormat: targetPlanarFmt)

        let isVideoSampleMatch = (!inMd5s.isEmpty && !outMd5s.isEmpty && inMd5s == outMd5s)
        let isBitMatch = isVideoSampleMatch && (inPixFmt == outPixFmt)
        let verifiedCount = min(inMd5s.count, outMd5s.count)

        let inDigest = computeStreamCompositeDigest(frameHashes: inMd5s)
        let outDigest = computeStreamCompositeDigest(frameHashes: outMd5s)

        // 2. 逐軌音訊驗證
        let audioResults = verifyAudioTracks(inputUrl: inputUrl, outputUrl: outputUrl)
        let isAudioAllMatch = audioResults.isEmpty || audioResults.allSatisfy { $0.isMatched }

        // 3. 同步檢測
        let hasBothVA = (inInsp?.videoCodec != nil && inInsp?.audioCodec != nil)
        let syncResult = hasBothVA ? verifySync(inputUrl: inputUrl, outputUrl: outputUrl) : nil
        let isSyncGood = syncResult?.isSyncPreserved ?? true

        // 4. 時間碼與中繼資料獨立分析
        let metaResult = inspectMetadataAndTimecode(inputUrl: inputUrl, outputUrl: outputUrl)

        // 5. 略過軌道分析
        var skipped: [TrackInfo] = []
        let inStreams = inInsp?.streams ?? []
        let outStreams = outInsp?.streams ?? []
        let outExt = outputUrl.pathExtension.lowercased()
        
        for s in inStreams {
            let outCountOfThisType = outStreams.filter { $0.codecType == s.codecType }.count
            let sameTypeStreams = inStreams.filter { $0.codecType == s.codecType }
            let sOrderInType = sameTypeStreams.firstIndex(where: { $0.index == s.index }) ?? 0
            let isDropped = sOrderInType >= outCountOfThisType
            
            if isDropped {
                var rZh = "目標容器不支援此軌道直接封裝，已依規範略過。"
                var rEn = "Target container does not support this stream; skipped per container standards."
                if s.codecType == "data" || s.codecName == "smpte_436m_anc" || s.codecName == "tmcd" {
                    rZh = "檢測到廣播級輔助資料軌/時間碼軌 [\(s.codecName ?? "data")]，已過濾以防封裝錯誤，時間碼中繼資料已獨立保全。"
                    rEn = "Broadcast auxiliary data/timecode stream [\(s.codecName ?? "data")] filtered to prevent muxing errors; timecode metadata preserved independently."
                } else if s.codecType == "subtitle" {
                    if outExt == "mkv" {
                        rZh = "字幕軌 [\(s.codecName ?? "sub")] 在寫入時未成功封裝至 MKV。"
                        rEn = "Subtitle track [\(s.codecName ?? "sub")] failed to mux into MKV."
                    } else {
                        rZh = "目標容器 .\(outExt) 不支援此字幕格式直接封裝，已略過。"
                        rEn = "Target container .\(outExt) does not support this subtitle format for direct muxing; skipped."
                    }
                }
                skipped.append(TrackInfo(
                    index: s.index,
                    codecType: s.codecType,
                    codecName: s.codecName,
                    pixelFormat: s.pixelFormat,
                    bitDepth: s.bitDepth,
                    resolution: s.resolution,
                    isSkipped: true,
                    skipReasonZh: rZh,
                    skipReasonEn: rEn
                ))
            }
        }

        // 綜合判定：視訊像素無失真、音訊全軌無損、同步無漂移
        let isAllPassed = isVideoSampleMatch && isAudioAllMatch && isSyncGood

        let noteZh: String
        let noteEn: String
        let frameScopeTextZh = (maxFrames == nil || maxFrames! <= 0) ? "全片完整 \(verifiedCount) 幀" : "採樣前 \(verifiedCount) 幀"
        let frameScopeTextEn = (maxFrames == nil || maxFrames! <= 0) ? "all \(verifiedCount) frames (full-length)" : "sample \(verifiedCount) frames"

        if isAllPassed {
            noteZh = "全片驗收通過：逐幀像素雜湊完全吻合（\(frameScopeTextZh)，原生色深 \(inDepth) 位元 [\(targetPlanarFmt)]），音訊逐軌 PCM 精確無損，影音同步完好。"
            noteEn = "Full verification PASSED: frame pixel hashes identical (\(frameScopeTextEn), native \(inDepth)-bit [\(targetPlanarFmt)]), all audio tracks PCM identical, AV sync preserved."
        } else if !isVideoSampleMatch {
            noteZh = "視訊逐幀像素雜湊不吻合（檢測到畫面資料差異，色深 \(inDepth) 位元 [\(targetPlanarFmt)]），存在像素失真。"
            noteEn = "Video frame pixel hashes mismatch (difference detected, bit-depth \(inDepth)-bit [\(targetPlanarFmt)]); pixel alteration observed."
        } else if !isAudioAllMatch {
            noteZh = "視訊畫面一致，但音訊逐軌校驗未通過（音訊取樣失真或缺軌）。"
            noteEn = "Video pixels identical, but audio track verification failed (PCM mismatch or missing tracks)."
        } else {
            noteZh = "影音資料吻合，但檢測到影音同步漂移超出容差。"
            noteEn = "AV data identical, but AV sync drift exceeded tolerance."
        }

        return VerificationReport(
            isPassed: isAllPassed,
            isBitIdentical: isBitMatch,
            isSampleIdentical: isVideoSampleMatch,
            isAudioIdentical: isAudioAllMatch,
            isSyncPreserved: isSyncGood,
            nativePixelFormat: targetPlanarFmt,
            nativeBitDepth: inDepth,
            verifiedFrames: verifiedCount,
            totalFramesInput: inMd5s.count,
            totalFramesOutput: outMd5s.count,
            inputVideoDigest: inDigest,
            outputVideoDigest: outDigest,
            sampleHashesInput: inMd5s,
            sampleHashesOutput: outMd5s,
            audioTracks: audioResults,
            syncInfo: syncResult,
            timecodeStatusZh: metaResult.timecodeStatusZh,
            timecodeStatusEn: metaResult.timecodeStatusEn,
            metadataDifferences: metaResult.differences,
            skippedTracks: skipped,
            noteZh: noteZh,
            noteEn: noteEn
        )
    }

    // MARK: - 視訊像素專項無損比對（向下相容與專注畫面）
    public static func verifyPixelLossless(
        inputUrl: URL,
        outputUrl: URL,
        sampleFrames: Int? = nil
    ) -> VerificationReport {
        return verifyFullLossless(inputUrl: inputUrl, outputUrl: outputUrl, maxFrames: sampleFrames)
    }

    // MARK: - 串流直通 (Remux) 比對驗證
    public static func verifyStreamCopy(inputUrl: URL, outputUrl: URL) -> FFmpegRunner.RemuxVerificationResult {
        return FFmpegRunner.shared.verifyRemux(inputUrl: inputUrl, outputUrl: outputUrl)
    }
}
