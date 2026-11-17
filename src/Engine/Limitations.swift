import Foundation

public struct LosslessLimitations {
    public static let disclaimers: [String] = [
        "【外部圖片引擎】內嵌可攜 ImageMagick，目前開放 PNG/TIFF/BMP/JPEG/WebP 及圖片轉 PDF；HEIC、RAW及其他格式未驗證。動畫/多頁若無法完整保全時拒絕以單頁冒充。若因格式限制無法保全中繼資料或位深，系統將正常產出檔案並明確標註未符無損原因與證據，不虛假宣稱無損。",
        "【圖片轉 PDF 支援】支援將 PNG、JPEG、WebP、TIFF、BMP 等圖片直接以原生 1:1 像素點陣封裝為標準 PDF 文件（保持原始圖片尺寸與點陣資料，無二次有損壓縮，非文字/向量繪圖）。本軟體為純輕量自包含架構，不內建龐大 Office 轉檔套件，不支援 Word/Excel/PPT 等辦公文件。",
        "【非所有轉換皆可無損】業界並不存在『任何格式間隨意互轉皆無損』的技術。若來源為有損格式（如 JPEG、低碼率 MP3），轉為無損容器僅能保留現有解碼後狀態，無法憑空還原拍攝或錄音時已損失的原始資訊。",
        "【封裝直通 (Stream Copy) 與智慧相容性】直通優先維持原始音視訊位元流，零品質量化損失。若目標容器支援該視訊但音訊不相容（如 MP4 不支援未壓縮 PCM），系統自動採用「視訊無損直通 + 高品質音訊相容轉碼（如 320k AAC）」完成交付並誠實註記，絕不產生損壞檔案；若音視訊皆不相容則引導相容轉碼或拒絕非標準封裝。",
        "【像素無損 (Lossless Transcode) 限制】真正的像素無損重編碼（如 FFV1、x264 8-bit CRF 0）會耗費大量 CPU 算力，且產出的檔案體積通常是來源有損檔案的數倍至十幾倍。高位深（10-bit/12-bit）或 4:2:2/4:4:4 色度來源請務必選用 MKV (FFV1)，避免使用 MP4 造成靜默降階失真。",
        "【ProRes 4444 XQ 視覺無損定位】Apple 官方定位 ProRes 為視覺級極限近似無損（最高 12-bit，非數學位元 1:1 精確一致）。因色空間轉換與 DCT 量化，解碼 framemd5 與原始不同，不屬於典藏級數學無損模式。",
        "【Metadata 保留差異】不同容器支援的 Metadata 規範不同（例如 MKV 與 MP4 的標籤結構差異，或 EXIF 在特定圖片格式中的支援度）。本工具盡可能保留所有可移植之 Metadata，但特定專有私有標籤或非 ASCII 字元在不同容器間無法保證 100% 映射，不宣稱未經證明的完整保留。",
        "【Ad-hoc 簽章與 Gatekeeper 提示】本發行檔採用本機 Ad-hoc 簽章（未包含 Apple Developer 商業公證）。其他 Mac 首次開啟若遇 Gatekeeper 提示損毀或未驗證開發者，請至『系統設定 > 隱私權與安全性』點選『仍要打開』，或於終端機執行 `xattr -d com.apple.quarantine LosslessStudio.app`。"
    ]
    
    public static let containerSupportMatrix: [(container: String, name: String, supportedVideo: [String], supportedAudio: [String], notes: String)] = [
        ("mkv", "Matroska (.mkv)", ["h264", "hevc", "vp8", "vp9", "av1", "prores", "ffv1", "mpeg4", "mjpeg", "mpeg2video", "dnxhd"], ["aac", "ac3", "eac3", "flac", "alac", "opus", "vorbis", "pcm_s16le", "pcm_s24le", "pcm_s16be", "pcm_s24be", "pcm_s32le", "pcm_s32be", "mp3"], "相容性最高，完整支援 FFV1 數學無損與多音軌/字幕。"),
        ("mp4", "MPEG-4 Part 14 (.mp4)", ["h264", "hevc", "av1", "vp9", "mpeg4"], ["aac", "alac", "ac3", "eac3", "mp3", "opus"], "廣泛相容行動設備。若音訊為未壓縮 PCM (如 pcm_s16be)，系統自動以高品質 AAC 相容轉碼交付，保全視訊位元直通。"),
        ("mov", "Apple QuickTime (.mov)", ["prores", "h264", "hevc", "mjpeg", "dnxhd", "mpeg2video"], ["pcm_s16le", "pcm_s24le", "pcm_s16be", "pcm_s24be", "pcm_s32le", "pcm_s32be", "alac", "aac", "mp3", "ac3", "eac3", "flac"], "Apple 生態相容性最佳，支援 ProRes 4444 XQ（視覺近似無損）與 PCM 未壓縮音訊。"),
        ("webm", "WebM (.webm)", ["vp8", "vp9", "av1"], ["opus", "vorbis"], "開源 Web 標準容器，音視訊限定開源編碼。"),
        ("avi", "Audio Video Interleave (.avi)", ["mjpeg", "mpeg4", "h264"], ["pcm_s16le", "mp3", "ac3"], "舊版 Windows 多媒體容器。"),
        ("ts", "MPEG Transport Stream (.ts)", ["h264", "hevc", "mpeg2video"], ["aac", "ac3", "mp3"], "廣播與串流傳輸串流容器。"),
        ("mxf", "Material eXchange Format (.mxf)", ["mpeg2video", "h264", "hevc", "prores", "dnxhd"], ["pcm_s16le", "pcm_s24le", "pcm_s16be", "pcm_s24be", "aac"], "專業廣播級影音容器，支援 48kHz PCM 音訊與廣播級視訊編碼。")
    ]
    
    public static let imageFormatMatrix: [(format: String, isTrulyLossless: Bool, notes: String)] = [
        ("PNG", true, "完全點陣無損壓縮，支援 Alpha 透明通道，中繼資料須逐檔核對。"),
        ("TIFF", true, "完全點陣無損，支援 8-bit / 16-bit / 32-bit 深度，色彩空間與中繼資料須逐檔核對。"),
        ("WebP (Lossless)", true, "使用 WebP 無損模式 (VP8L)，僅支援 8-bit 深度，且需 ImageMagick 具備 WebP 寫入能力。"),
        ("BMP", true, "未壓縮點陣位圖無損，不支援複雜 EXIF 資訊，檔案體積極大。"),
        ("PDF (Image to PDF)", true, "原生 1:1 像素點陣封裝，保持原始像素尺寸，不進行有損二度壓縮，支援 PNG/JPEG/TIFF/WebP/BMP 轉 PDF。"),
        ("JPEG / JPG", false, "本質為有損壓縮。轉至 JPEG 必定經歷 DCT 離散餘弦轉換與量化，無法達到數學無損；透明來源將平坦化為白色背景，系統產出檔案並標示未符無損原因。")
    ]
    
    public static let audioFormatMatrix: [(format: String, isLossless: Bool, supportedBitDepths: String, notes: String)] = [
        ("WAV (.wav)", true, "16-bit / 24-bit / 32-bit float PCM", "標準廣播級未壓縮 PCM，相容性最高，可達 100% 數學無損。"),
        ("FLAC (.flac)", true, "16-bit / 24-bit PCM", "開源自由無損音訊壓縮，壓縮比約 50%-60%，解碼 PCM 點對點一致。"),
        ("ALAC (.m4a)", true, "16-bit / 24-bit PCM", "Apple Lossless Audio Codec，相容 Apple 裝置與 iTunes/Music.app。"),
        ("AIFF (.aiff/.aif)", true, "16-bit / 24-bit / 32-bit PCM (Big-Endian)", "Apple 專業未壓縮音訊標準，常用於 Logic Pro 與專業音樂製作。"),
        ("MP3 (.mp3)", false, "16-bit (感知量化)", "本質為有損壓縮 (libmp3lame)，支援 320k/256k/192k/128k。不可宣稱位元無損。"),
        ("AAC (.m4a/.aac)", false, "16-bit (MDCT 量化)", "現代高效率有損壓縮 (aac)，廣泛用於串流與行動裝置。不可宣稱位元無損。"),
        ("OGG (.ogg)", false, "16-bit (Vorbis)", "開源有損音訊格式 (vorbis)，啟用實驗模式 (-strict -2) 並自適應標準化為 2 聲道，相容各類遊戲與 Web 播放。"),
        ("OPUS (.opus)", false, "48kHz 原生取樣 (libopus)", "新世代低延遲高音質有損音訊編碼，單聲道最高 256k、雙聲道最高 512k，自適應鉗制單聲道碼率上限。")
    ]

    public struct RemuxCheckResult {
        public let allowed: Bool
        public let canCopyVideo: Bool
        public let canCopyAudio: Bool
        public let needsAudioTranscode: Bool
        public let fallbackAudioCodec: String?
        public let fallbackAudioBitrate: String?
        public let reason: String

        public init(
            allowed: Bool,
            canCopyVideo: Bool,
            canCopyAudio: Bool,
            needsAudioTranscode: Bool,
            fallbackAudioCodec: String?,
            fallbackAudioBitrate: String?,
            reason: String
        ) {
            self.allowed = allowed
            self.canCopyVideo = canCopyVideo
            self.canCopyAudio = canCopyAudio
            self.needsAudioTranscode = needsAudioTranscode
            self.fallbackAudioCodec = fallbackAudioCodec
            self.fallbackAudioBitrate = fallbackAudioBitrate
            self.reason = reason
        }
    }
    
    /// 檢查特定編碼是否可直通至特定容器，或需智慧相容降級
    public static func canRemux(videoCodec: String?, audioCodec: String?, targetContainer: String) -> RemuxCheckResult {
        let target = targetContainer.lowercased().replacingOccurrences(of: ".", with: "")
        guard let entry = containerSupportMatrix.first(where: { $0.container == target }) else {
            return RemuxCheckResult(
                allowed: false,
                canCopyVideo: false,
                canCopyAudio: false,
                needsAudioTranscode: false,
                fallbackAudioCodec: nil,
                fallbackAudioBitrate: nil,
                reason: "不支援的目標容器格式: .\(target)"
            )
        }
        
        var canCopyVideo = true
        if let vc = videoCodec?.lowercased() {
            canCopyVideo = entry.supportedVideo.contains { vc.contains($0) }
        }
        
        var canCopyAudio = true
        if let ac = audioCodec?.lowercased() {
            canCopyAudio = entry.supportedAudio.contains { ac.contains($0) }
        }
        
        if canCopyVideo && canCopyAudio {
            return RemuxCheckResult(
                allowed: true,
                canCopyVideo: true,
                canCopyAudio: true,
                needsAudioTranscode: false,
                fallbackAudioCodec: nil,
                fallbackAudioBitrate: nil,
                reason: "相容直通封裝。"
            )
        }

        if canCopyVideo && !canCopyAudio {
            var fallbackCodec = "aac"
            var fallbackBitrate: String? = "320k"
            switch target {
            case "mp4", "mov", "ts":
                fallbackCodec = "aac"
                fallbackBitrate = "320k"
            case "webm":
                fallbackCodec = "libopus"
                fallbackBitrate = "192k"
            case "avi":
                fallbackCodec = "mp3"
                fallbackBitrate = "320k"
            case "mxf":
                fallbackCodec = "pcm_s16le"
                fallbackBitrate = nil
            default:
                fallbackCodec = "aac"
                fallbackBitrate = "320k"
            }
            let acStr = audioCodec ?? "未知"
            return RemuxCheckResult(
                allowed: false,
                canCopyVideo: true,
                canCopyAudio: false,
                needsAudioTranscode: true,
                fallbackAudioCodec: fallbackCodec,
                fallbackAudioBitrate: fallbackBitrate,
                reason: "目標容器 .\(target) 不支援目前音訊編碼 [\(acStr)] 的直接封裝。可智慧採用視訊直通+音訊相容轉碼 (\(fallbackCodec.uppercased()))。"
            )
        }
        
        let vcStr = videoCodec ?? "未知"
        return RemuxCheckResult(
            allowed: false,
            canCopyVideo: false,
            canCopyAudio: canCopyAudio,
            needsAudioTranscode: false,
            fallbackAudioCodec: nil,
            fallbackAudioBitrate: nil,
            reason: "目標容器 .\(target) 不支援目前視訊編碼 [\(vcStr)] 的直接封裝，直通將導致播放失敗。建議改選 .mkv 或使用像素無損轉碼。"
        )
    }
}
