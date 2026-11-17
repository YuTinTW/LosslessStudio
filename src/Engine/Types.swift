import Foundation

public enum ConversionCategory: String, CaseIterable, Identifiable, Codable {
    case remux = "保留原編碼：串流直通 (Stream Copy)"
    case videoLossless = "視訊無損重新編碼：編碼會改變 (Lossless Re-encode)"
    case imageLossless = "圖片無損像素轉換 (Lossless Image)"
    case imageLossy = "圖片有損壓縮格式 (Lossy Image / WebP / JPEG)"
    case audioLossless = "無損音訊互轉 (Lossless Audio)"
    case audioLossy = "有損／相容性降轉模式 (Lossy Audio / Downsampling)"
    case document = "PDF 頁面點陣化與文件轉換 (PDF to Image)"

    public var id: String { rawValue }

    public var isBitstreamCopy: Bool {
        self == .remux
    }

    public var description: String {
        switch self {
        case .remux:
            return "嚴格串流直通（-c copy），絕不進行二次解碼與重新編碼。100% 保留原始視訊/音訊壓縮位元流，零品質量化損失，嚴禁自動 fallback 重編碼。"
        case .videoLossless:
            return "重新解碼並使用數學無損壓縮算法（如 FFV1、x264 8-bit CRF 0）封裝。解碼 RGB/YUV 像素點陣完全精確一致。若為 ProRes 4444 XQ 則為視覺級極限近似無損（12-bit，非數學 1:1 精確一致）。"
        case .imageLossless:
            return "外部 ImageMagick 轉換 PNG、TIFF、BMP、WebP；交付前比對16-bit RGBA取樣、尺寸、位深與來源中繼資料。無法保留則拒絕，不支援動畫、多頁或未驗證格式。"
        case .imageLossy:
            return "通用有損圖片格式壓縮（JPEG, WebP 有損模式），提供自訂高品質壓縮參數，標註有損壓縮狀態。"
        case .audioLossless:
            return "典藏級無損音訊互轉（WAV PCM 16/24/32-bit、FLAC、ALAC、AIFF、CAF）。解碼 PCM 取樣點對點 1:1 雜湊校驗，保證 100% 數學無損。"
        case .audioLossy:
            return "有損與高相容性降轉模式（MP3、AAC、OGG、OPUS、AC3）。支援自訂位元率 (320k/256k/192k/128k) 與取樣率/位深降轉，誠實標示有損降轉狀態，絕不虛假宣稱無損。"
        case .document:
            return "macOS 原生 PDFKit 點陣化渲染引擎（PDF 文件頁面依序渲染為 PNG、JPEG、TIFF、BMP、WebP 高解析圖片；圖片點陣化封裝為 PDF）。明確標註渲染點陣化，不支援 Office 專利文件。"
        }
    }
}

public enum VerificationStatus: String, Codable {
    case unverified = "未驗證"
    case verifying = "驗證中..."
    case passed = "通過 (數學無損/位元流吻合)"
    case visualLossless = "通過 (視覺近似無損，非位元精確)"
    case lossyConversion = "有損轉換 (不進行位元比對)"
    case mismatch = "不一致 (檢測到資料差異)"
    case cannotVerify = "無法驗證 (容器或格式不支援位元比對)"
    case failed = "轉檔失敗"
    case disqualified = "未符無損 (已產出檔案，標示不合格原因)"

    public var badgeColorName: String {
        switch self {
        case .unverified: return "secondary"
        case .verifying: return "orange"
        case .passed: return "green"
        case .visualLossless: return "blue"
        case .lossyConversion, .disqualified: return "orange"
        case .mismatch, .failed: return "red"
        case .cannotVerify: return "gray"
        }
    }
}

public enum TaskStatus: Equatable, Codable {
    case pending
    case inspecting
    case processing(progress: Double, speed: String?, eta: String?)
    case completed(outputUrl: URL, duration: TimeInterval)
    case rejected(reason: String)
    case failed(error: String)
    case cancelled

    public var displayText: String {
        switch self {
        case .pending:
            return "等待中"
        case .inspecting:
            return "探測中..."
        case .processing(let p, let speed, let eta):
            if let sp = speed, let et = eta, sp != "不適用" && et != "不適用" {
                return String(format: "轉檔中 %.0f%% (速度: %@, 預估剩餘: %@)", p * 100, sp, et)
            } else {
                return String(format: "轉檔中 (%.0f%%)", p * 100)
            }
        case .completed:
            return "轉檔完成 (待驗證)"
        case .rejected(let r):
            return "已拒絕: \(r)"
        case .failed(let e):
            return "失敗: \(e)"
        case .cancelled:
            return "已取消"
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .completed, .rejected, .failed, .cancelled: return true
        default: return false
        }
    }
}

public struct StreamInfo: Codable, Equatable, Identifiable {
    public var id: Int { index }
    public let index: Int
    public let codecType: String // "video", "audio", "subtitle"
    public let codecName: String?
    public let profile: String?
    public let pixelFormat: String?
    public let resolution: String?
    public let frameRate: String?
    public let bitDepth: Int?
    public let sampleRate: Int?
    public let channels: Int?
    public let channelLayout: String?
    public let title: String?
    public let language: String?

    public init(
        index: Int,
        codecType: String,
        codecName: String?,
        profile: String? = nil,
        pixelFormat: String? = nil,
        resolution: String? = nil,
        frameRate: String? = nil,
        bitDepth: Int? = nil,
        sampleRate: Int? = nil,
        channels: Int? = nil,
        channelLayout: String? = nil,
        title: String? = nil,
        language: String? = nil
    ) {
        self.index = index
        self.codecType = codecType
        self.codecName = codecName
        self.profile = profile
        self.pixelFormat = pixelFormat
        self.resolution = resolution
        self.frameRate = frameRate
        self.bitDepth = bitDepth
        self.sampleRate = sampleRate
        self.channels = channels
        self.channelLayout = channelLayout
        self.title = title
        self.language = language
    }
}

public struct MediaInspectionResult: Codable, Equatable {
    public let filePath: String
    public let fileSize: Int64
    public let formatName: String
    public let duration: Double?
    public let videoCodec: String?
    public let videoProfile: String?
    public let videoPixelFormat: String?
    public let videoResolution: String?
    public let videoFrameRate: String?
    public let audioCodec: String?
    public let audioChannels: Int?
    public let audioSampleRate: Int?
    public let isImage: Bool

    // 逐軌串流清單
    public let streams: [StreamInfo]

    // 圖片/文件專用屬性 (ImageIO / PDFKit 探測)
    public let imageBitsPerComponent: Int?
    public let imageColorSpace: String?
    public let imageHasAlpha: Bool?
    public let pageCount: Int?

    public init(
        filePath: String,
        fileSize: Int64,
        formatName: String,
        duration: Double?,
        videoCodec: String?,
        videoProfile: String? = nil,
        videoPixelFormat: String?,
        videoResolution: String?,
        videoFrameRate: String? = nil,
        audioCodec: String?,
        audioChannels: Int?,
        audioSampleRate: Int?,
        isImage: Bool,
        streams: [StreamInfo] = [],
        imageBitsPerComponent: Int? = nil,
        imageColorSpace: String? = nil,
        imageHasAlpha: Bool? = nil,
        pageCount: Int? = nil
    ) {
        self.filePath = filePath
        self.fileSize = fileSize
        self.formatName = formatName
        self.duration = duration
        self.videoCodec = videoCodec
        self.videoProfile = videoProfile
        self.videoPixelFormat = videoPixelFormat
        self.videoResolution = videoResolution
        self.videoFrameRate = videoFrameRate
        self.audioCodec = audioCodec
        self.audioChannels = audioChannels
        self.audioSampleRate = audioSampleRate
        self.isImage = isImage
        self.streams = streams
        self.imageBitsPerComponent = imageBitsPerComponent
        self.imageColorSpace = imageColorSpace
        self.imageHasAlpha = imageHasAlpha
        self.pageCount = pageCount
    }
}

/// 前後編碼對照與比對驗證紀錄
public struct EncodingComparison: Identifiable, Codable {
    public var id: UUID = UUID()
    public var inputUrl: URL
    public var outputUrl: URL?
    public var category: ConversionCategory
    public var executionArgs: [String] = []

    // 來源真實探測
    public var inputInspection: MediaInspectionResult?
    // 輸出真實探測（未完成前為 nil，不可臆測）
    public var outputInspection: MediaInspectionResult?

    // 驗證比對數值
    public var inputHash: String?
    public var outputHash: String?
    public var verificationStatus: VerificationStatus = .unverified
    public var verificationNote: String = "尚未執行驗證 (規劃中)"
    public var qualificationReasons: [String] = []
}

public struct ConversionTaskItem: Identifiable {
    public let id: UUID
    public let inputUrl: URL
    public var relativeInputPath: String?
    public var outputContainer: String
    public var category: ConversionCategory
    public var status: TaskStatus
    public var inspection: MediaInspectionResult?
    public var outputInspection: MediaInspectionResult?
    public var comparison: EncodingComparison?
    public var logMessages: [String]
    public var executionCommand: String?
    public var lastStderr: String?

    // 產物清單 (支援多頁 PDF 等多產物任務)
    public var outputUrls: [URL] = []

    // 音訊進階設定 (有損降轉與無損位深/取樣率設定)
    public var audioBitrate: String? = "320k"
    public var audioSampleRate: Int? = nil
    public var audioBitDepth: Int? = nil

    // PDF 專用進階設定 (多頁點陣化與解析度)
    public var pdfDPI: Double = 150.0
    public var pdfPageCount: Int? = nil

    public init(
        url: URL,
        category: ConversionCategory = .remux,
        outputContainer: String = "mkv",
        relativeInputPath: String? = nil,
        audioBitrate: String? = "320k",
        audioSampleRate: Int? = nil,
        audioBitDepth: Int? = nil
    ) {
        self.id = UUID()
        self.inputUrl = url
        self.outputContainer = outputContainer
        self.category = category
        self.status = .pending
        self.logMessages = []
        self.relativeInputPath = relativeInputPath
        self.audioBitrate = audioBitrate
        self.audioSampleRate = audioSampleRate
        self.audioBitDepth = audioBitDepth
        self.comparison = EncodingComparison(inputUrl: url, category: category)
    }

    public var mediaKind: MediaKind {
        if let insp = inspection {
            if insp.isImage { return .image }
            if insp.videoCodec == nil && insp.audioCodec != nil { return .audio }
            if insp.videoCodec != nil { return .video }
        }
        let ext = inputUrl.pathExtension.lowercased()
        if ["png","jpg","jpeg","tiff","tif","bmp","webp","heic","heif","gif","psd","icns","dng","cr2","nef","arw"].contains(ext) {
            return .image
        }
        if ["wav","flac","aiff","aif","alac","m4a","mp3","aac","ogg","opus","wma","ac3","eac3","dts","m4r","caf","amr","ape","wv"].contains(ext) {
            return .audio
        }
        if ["pdf","docx","doc","xlsx","xls","pptx","ppt","pages","numbers","key","txt","rtf","rtfd","csv","tsv","html","htm","md","markdown"].contains(ext) {
            return .document
        }
        return .video
    }

    public var currentPresetId: String {
        let kind = self.mediaKind
        switch kind {
        case .audio:
            if category == .audioLossless {
                if outputContainer == "wav" {
                    if audioBitDepth == 32 { return "wav_32" }
                    if audioBitDepth == 24 { return "wav_24" }
                    return "wav_16"
                }
                if outputContainer == "m4a" { return "alac" }
                if outputContainer == "caf" { return "caf" }
                return outputContainer // flac, aiff
            } else if category == .audioLossy {
                if outputContainer == "mp3" {
                    if audioBitrate == "256k" { return "mp3_256" }
                    if audioBitrate == "192k" { return "mp3_192" }
                    if audioBitrate == "128k" { return "mp3_128" }
                    return "mp3_320"
                }
                if outputContainer == "m4a" { return "aac" }
                if outputContainer == "ac3" { return "ac3" }
                return outputContainer // ogg, opus
            }
            return "flac"

        case .image:
            if category == .imageLossy {
                if outputContainer == "jpg" || outputContainer == "jpeg" {
                    return "jpg_95"
                }
                return "webp_85"
            }
            if outputContainer == "pdf" { return "pdf" }
            return outputContainer // png, tiff, webp, bmp

        case .video:
            if category == .audioLossy {
                if outputContainer == "mp3" { return "extract_mp3" }
                return "extract_aac"
            } else if category == .audioLossless {
                if outputContainer == "wav" { return "extract_wav" }
                return "extract_flac"
            } else if category == .videoLossless {
                if outputContainer == "mov" { return "prores" }
                if outputContainer == "mp4" { return "mp4_lossless" }
                return "ffv1"
            }
            return "\(outputContainer)_remux"

        case .document:
            if outputContainer == "png" { return "pdf_to_png" }
            if outputContainer == "jpg" || outputContainer == "jpeg" { return "pdf_to_jpg" }
            if outputContainer == "tiff" || outputContainer == "tif" { return "pdf_to_tiff" }
            if outputContainer == "webp" { return "pdf_to_webp" }
            if outputContainer == "bmp" { return "pdf_to_bmp" }
            if outputContainer == "pdf" { return "img_to_pdf" }
            return outputContainer // pdf, png, etc.
        }
    }

    public mutating func applyPreset(id: String) {
        let kind = self.mediaKind
        let options = MediaPresets.presets(for: kind)
        guard let opt = options.first(where: { $0.id == id }) else { return }
        self.category = opt.category
        self.outputContainer = opt.container
        if let br = opt.audioBitrate {
            self.audioBitrate = br
        }
        if let bd = opt.audioBitDepth {
            self.audioBitDepth = bd
        }
    }
}

public enum MediaKind: String, Codable {
    case audio = "音訊"
    case image = "圖片"
    case video = "視訊"
    case document = "文件"
}

public struct TargetPresetOption: Identifiable, Hashable {
    public let id: String
    public let displayName: String
    public let group: String
    public let category: ConversionCategory
    public let container: String
    public let audioBitrate: String?
    public let audioBitDepth: Int?
    public let isLossless: Bool

    public init(
        id: String,
        displayName: String,
        group: String,
        category: ConversionCategory,
        container: String,
        audioBitrate: String? = nil,
        audioBitDepth: Int? = nil,
        isLossless: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.group = group
        self.category = category
        self.container = container
        self.audioBitrate = audioBitrate
        self.audioBitDepth = audioBitDepth
        self.isLossless = isLossless
    }
}

public struct MediaPresets {
    public static let audioPresets: [TargetPresetOption] = [
        TargetPresetOption(id: "wav_32", displayName: "WAV (32-bit Float)", group: "無損音訊", category: .audioLossless, container: "wav", audioBitDepth: 32, isLossless: true),
        TargetPresetOption(id: "wav_24", displayName: "WAV (24-bit PCM)", group: "無損音訊", category: .audioLossless, container: "wav", audioBitDepth: 24, isLossless: true),
        TargetPresetOption(id: "wav_16", displayName: "WAV (16-bit PCM)", group: "無損音訊", category: .audioLossless, container: "wav", audioBitDepth: 16, isLossless: true),
        TargetPresetOption(id: "flac", displayName: "FLAC (無損壓縮)", group: "無損音訊", category: .audioLossless, container: "flac", isLossless: true),
        TargetPresetOption(id: "alac", displayName: "ALAC (.m4a Mac推薦無損)", group: "無損音訊", category: .audioLossless, container: "m4a", isLossless: true),
        TargetPresetOption(id: "aiff", displayName: "AIFF (無損 PCM)", group: "無損音訊", category: .audioLossless, container: "aiff", isLossless: true),
        TargetPresetOption(id: "caf", displayName: "CAF (CoreAudio無損)", group: "無損音訊", category: .audioLossless, container: "caf", isLossless: true),
        TargetPresetOption(id: "mp3_320", displayName: "MP3 (320k 最佳)", group: "常用降轉", category: .audioLossy, container: "mp3", audioBitrate: "320k", isLossless: false),
        TargetPresetOption(id: "mp3_256", displayName: "MP3 (256k 高音質)", group: "常用降轉", category: .audioLossy, container: "mp3", audioBitrate: "256k", isLossless: false),
        TargetPresetOption(id: "mp3_192", displayName: "MP3 (192k 標準)", group: "常用降轉", category: .audioLossy, container: "mp3", audioBitrate: "192k", isLossless: false),
        TargetPresetOption(id: "mp3_128", displayName: "MP3 (128k 輕量)", group: "常用降轉", category: .audioLossy, container: "mp3", audioBitrate: "128k", isLossless: false),
        TargetPresetOption(id: "aac", displayName: "AAC (.m4a 256k)", group: "常用降轉", category: .audioLossy, container: "m4a", audioBitrate: "256k", isLossless: false),
        TargetPresetOption(id: "ogg", displayName: "OGG (Vorbis 256k)", group: "常用降轉", category: .audioLossy, container: "ogg", audioBitrate: "256k", isLossless: false),
        TargetPresetOption(id: "opus", displayName: "OPUS (160k 高音質)", group: "常用降轉", category: .audioLossy, container: "opus", audioBitrate: "160k", isLossless: false),
        TargetPresetOption(id: "ac3", displayName: "AC3 (640k 環繞/立體聲)", group: "常用降轉", category: .audioLossy, container: "ac3", audioBitrate: "640k", isLossless: false),
    ]

    public static let imagePresets: [TargetPresetOption] = [
        TargetPresetOption(id: "png", displayName: "PNG (點陣無損)", group: "點陣無損", category: .imageLossless, container: "png", isLossless: true),
        TargetPresetOption(id: "tiff", displayName: "TIFF (16/8-bit 無損)", group: "點陣無損", category: .imageLossless, container: "tiff", isLossless: true),
        TargetPresetOption(id: "webp", displayName: "WebP (VP8L 無損)", group: "點陣無損", category: .imageLossless, container: "webp", isLossless: true),
        TargetPresetOption(id: "bmp", displayName: "BMP (點陣位圖)", group: "點陣無損", category: .imageLossless, container: "bmp", isLossless: true),
        TargetPresetOption(id: "pdf", displayName: "PDF 文件 (1:1 像素原生點陣封裝)", group: "文件輸出", category: .imageLossless, container: "pdf", isLossless: true),
        TargetPresetOption(id: "jpg_95", displayName: "JPEG (高品質 95%)", group: "通用壓縮", category: .imageLossy, container: "jpg", isLossless: false),
        TargetPresetOption(id: "jpg_80", displayName: "JPEG (標準 80%)", group: "通用壓縮", category: .imageLossy, container: "jpg", isLossless: false),
        TargetPresetOption(id: "webp_85", displayName: "WebP (高效 85%)", group: "通用壓縮", category: .imageLossy, container: "webp", isLossless: false),
    ]

    public static let videoPresets: [TargetPresetOption] = [
        TargetPresetOption(id: "mp4_remux", displayName: "MP4 (串流直通)", group: "容器直通", category: .remux, container: "mp4", isLossless: true),
        TargetPresetOption(id: "mkv_remux", displayName: "MKV (串流直通)", group: "容器直通", category: .remux, container: "mkv", isLossless: true),
        TargetPresetOption(id: "mov_remux", displayName: "MOV (QuickTime 直通)", group: "容器直通", category: .remux, container: "mov", isLossless: true),
        TargetPresetOption(id: "webm_remux", displayName: "WebM (開源 Web 直通)", group: "容器直通", category: .remux, container: "webm", isLossless: true),
        TargetPresetOption(id: "avi_remux", displayName: "AVI (直通)", group: "容器直通", category: .remux, container: "avi", isLossless: true),
        TargetPresetOption(id: "ts_remux", displayName: "TS (串流直通)", group: "容器直通", category: .remux, container: "ts", isLossless: true),
        TargetPresetOption(id: "mxf_remux", displayName: "MXF (廣播級直通)", group: "容器直通", category: .remux, container: "mxf", isLossless: true),
        TargetPresetOption(id: "ffv1", displayName: "MKV (FFV1 典藏無損)", group: "無損重編碼", category: .videoLossless, container: "mkv", isLossless: true),
        TargetPresetOption(id: "prores", displayName: "MOV (ProRes 4444 XQ)", group: "無損重編碼", category: .videoLossless, container: "mov", isLossless: true),
        TargetPresetOption(id: "mp4_lossless", displayName: "MP4 (x264 數學無損)", group: "無損重編碼", category: .videoLossless, container: "mp4", isLossless: true),
        TargetPresetOption(id: "mp4_compatible", displayName: "MP4 (相容輸出 / 自動轉 8-bit)", group: "通用視訊", category: .videoLossless, container: "mp4", isLossless: false),
        TargetPresetOption(id: "mxf_broadcast", displayName: "MXF (廣播級相容輸出)", group: "通用視訊", category: .videoLossless, container: "mxf", isLossless: false),
        TargetPresetOption(id: "extract_mp3", displayName: "提取音訊: MP3 (320k)", group: "提取純音訊", category: .audioLossy, container: "mp3", audioBitrate: "320k", isLossless: false),
        TargetPresetOption(id: "extract_wav", displayName: "提取音訊: WAV (24-bit 無損)", group: "提取純音訊", category: .audioLossless, container: "wav", audioBitDepth: 24, isLossless: true),
        TargetPresetOption(id: "extract_flac", displayName: "提取音訊: FLAC (無損)", group: "提取純音訊", category: .audioLossless, container: "flac", isLossless: true),
        TargetPresetOption(id: "extract_aac", displayName: "提取音訊: AAC (.m4a 256k)", group: "提取純音訊", category: .audioLossy, container: "m4a", audioBitrate: "256k", isLossless: false),
    ]

    public static let documentPresets: [TargetPresetOption] = [
        TargetPresetOption(id: "pdf_to_png", displayName: "PDF 轉 PNG (多頁渲染 / 保留透明度)", group: "PDF 轉圖片", category: .document, container: "png", isLossless: false),
        TargetPresetOption(id: "pdf_to_jpg", displayName: "PDF 轉 JPEG (高品質 / 自動填白底)", group: "PDF 轉圖片", category: .document, container: "jpg", isLossless: false),
        TargetPresetOption(id: "pdf_to_tiff", displayName: "PDF 轉 TIFF (高解析印刷 / 保留透明度)", group: "PDF 轉圖片", category: .document, container: "tiff", isLossless: false),
        TargetPresetOption(id: "pdf_to_webp", displayName: "PDF 轉 WebP (現代網頁圖檔)", group: "PDF 轉圖片", category: .document, container: "webp", isLossless: false),
        TargetPresetOption(id: "pdf_to_bmp", displayName: "PDF 轉 BMP (標準點陣圖)", group: "PDF 轉圖片", category: .document, container: "bmp", isLossless: false),
        TargetPresetOption(id: "img_to_pdf", displayName: "圖片轉 PDF (原生點陣封裝)", group: "圖片轉文件", category: .document, container: "pdf", isLossless: false),
    ]

    public static func presets(for kind: MediaKind) -> [TargetPresetOption] {
        switch kind {
        case .audio: return audioPresets
        case .image: return imagePresets
        case .video: return videoPresets
        case .document: return documentPresets
        }
    }
}

/// 批次執行結果報告
public struct BatchReport {
    public var batchId: UUID = UUID()
    public var total: Int = 0
    public var succeeded: Int = 0
    public var failed: Int = 0
    public var rejected: Int = 0
    public var cancelled: Int = 0
    public var totalDuration: TimeInterval = 0
    public var startDate: Date = Date()
    public var endDate: Date?
    public var outputDirectory: String = ""
    public var taskDetails: [(name: String, status: String, note: String)] = []

    public var summary: String {
        let elapsed = endDate.map { $0.timeIntervalSince(startDate) } ?? 0
        var lines: [String] = []
        lines.append("=== LosslessStudio 批次報告 (ID: \(batchId.uuidString.prefix(8))) ===")
        lines.append("開始時間：\(ISO8601DateFormatter().string(from: startDate))")
        lines.append("結束時間：\(endDate.map { ISO8601DateFormatter().string(from: $0) } ?? "-")")
        lines.append("輸出目錄：\(outputDirectory)")
        lines.append("本次任務數：\(total)")
        lines.append("✓ 成功：\(succeeded)")
        lines.append("✗ 失敗：\(failed)")
        lines.append("⊘ 拒絕：\(rejected)")
        lines.append("⊗ 取消：\(cancelled)")
        lines.append("總耗時：\(String(format: "%.2f", elapsed))s")
        if !taskDetails.isEmpty {
            lines.append("\n任務明細：")
            for t in taskDetails.prefix(50) {
                lines.append("  [\(t.status)] \(t.name) — \(t.note)")
            }
            if taskDetails.count > 50 {
                lines.append("  ... 還有 \(taskDetails.count - 50) 項")
            }
        }
        return lines.joined(separator: "\n")
    }
}
