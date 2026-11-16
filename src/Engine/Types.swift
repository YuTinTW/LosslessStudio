import Foundation

public enum ConversionCategory: String, CaseIterable, Identifiable, Codable {
    case remux = "保留原編碼：串流直通 (Stream Copy)"
    case videoLossless = "視訊無損重新編碼：編碼會改變 (Lossless Re-encode)"
    case imageLossless = "圖片無損像素轉換 (Lossless Image)"
    case audioLossless = "無損音訊互轉 (Lossless Audio)"
    case audioLossy = "有損／相容性降轉模式 (Lossy Audio / Downsampling)"

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
            return "原生 ImageIO 進行點陣點對點無損映射（PNG, TIFF, BMP），像素 100% 吻合。非 ASCII (中文) metadata 依容器特性盡力保留，已知技術限制誠實揭露。"
        case .audioLossless:
            return "典藏級無損音訊互轉（WAV PCM 16/24/32-bit、FLAC、ALAC、AIFF）。解碼 PCM 取樣點對點 1:1 雜湊校驗，保證 100% 數學無損。"
        case .audioLossy:
            return "有損與高相容性降轉模式（MP3、AAC、OGG、OPUS）。支援自訂位元率 (320k/256k/192k/128k) 與取樣率/位深降轉，誠實標示有損降轉狀態，絕不虛假宣稱無損。"
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

    public var badgeColorName: String {
        switch self {
        case .unverified: return "secondary"
        case .verifying: return "orange"
        case .passed: return "green"
        case .visualLossless: return "blue"
        case .lossyConversion: return "orange"
        case .mismatch: return "red"
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

    // 圖片專用屬性 (ImageIO 探測)
    public let imageBitsPerComponent: Int?
    public let imageColorSpace: String?
    public let imageHasAlpha: Bool?

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
        imageHasAlpha: Bool? = nil
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

    // 音訊進階設定 (有損降轉與無損位深/取樣率設定)
    public var audioBitrate: String? = "320k"
    public var audioSampleRate: Int? = nil
    public var audioBitDepth: Int? = nil

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
