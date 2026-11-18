import SwiftUI
import AppKit

public struct LimitationsView: View {
    @State private var selectedTab: Int = 0
    @State private var copiedNotice: Bool = false
    
    public init() {}
    
    private var guideText: String {
        let resourceName = L10n.text("USER_GUIDE", "USER_GUIDE_EN")
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        if let url = Bundle.main.url(forResource: "USER_GUIDE", withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        if let resourceUrl = Bundle.main.resourceURL?.appendingPathComponent("\(resourceName).md"),
           let content = try? String(contentsOf: resourceUrl, encoding: .utf8) {
            return content
        }
        if let resourceUrl = Bundle.main.resourceURL?.appendingPathComponent("USER_GUIDE.md"),
           let content = try? String(contentsOf: resourceUrl, encoding: .utf8) {
            return content
        }
        return L10n.text("手冊已內建於應用程式中。", "User guide is embedded in the application.")
    }
    
    private func openGuideInExternalApp() {
        let resourceName = L10n.text("USER_GUIDE", "USER_GUIDE_EN")
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "md") {
            NSWorkspace.shared.open(url)
            return
        }
        if let url = Bundle.main.url(forResource: "USER_GUIDE", withExtension: "md") {
            NSWorkspace.shared.open(url)
            return
        }
        if let resourceUrl = Bundle.main.resourceURL?.appendingPathComponent("USER_GUIDE.md") {
            NSWorkspace.shared.open(resourceUrl)
        }
    }
    
    private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(guideText, forType: .string)
        copiedNotice = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            copiedNotice = false
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 頂部導覽列
            HStack {
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 26))
                    .foregroundColor(Color(red: 0.91, green: 0.51, blue: 0.23)) // 暖橘
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("LosslessStudio 功能說明與使用手冊", "LosslessStudio Manual & Documentation"))
                        .font(.title3).bold()
                    Text(L10n.text("深入了解無損原則、批次處理、效能調校與格式矩陣", "Learn about lossless principles, batch processing, performance tuning, and formats"))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                
                Picker("", selection: $selectedTab) {
                    Text(L10n.text("📖 功能操作手冊", "📖 User Guide")).tag(0)
                    Text(L10n.text("🛡️ 技術原則與相容矩陣", "🛡️ Technical Matrix")).tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.secondary.opacity(0.08))
            
            Divider()
            
            if selectedTab == 0 {
                userGuideTab
            } else {
                technicalMatrixTab
            }
        }
        .frame(minWidth: 680, minHeight: 520)
    }
    
    // MARK: - Tab 0: 使用手冊
    private var userGuideTab: some View {
        VStack(spacing: 0) {
            // 快捷動作列
            HStack(spacing: 12) {
                Text(L10n.text("📌 支援點對點無損、直通、多線程並行與安全防護", "📌 Supports bit-exact lossless, stream copy, multithreading, and source protection"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                
                if copiedNotice {
                    Text(L10n.text("✓ 已複製全文至剪貼簿", "✓ Copied to clipboard"))
                        .font(.caption).bold()
                        .foregroundColor(.green)
                }
                
                Button(action: copyToClipboard) {
                    Label(L10n.text("複製全文", "Copy All"), systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                
                Button(action: openGuideInExternalApp) {
                    Label(L10n.text("在系統中開啟 .md", "Open .md"), systemImage: "arrow.up.forward.app")
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.04))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(summarySections, id: \.title) { sec in
                        guideSection(icon: sec.icon, title: sec.title, color: sec.color, content: sec.items)
                    }
                }
                .padding(20)
            }
        }
    }
    
    private struct GuideSectionData {
        let icon: String
        let title: String
        let color: Color
        let items: [(String, String)]
    }

    private var summarySections: [GuideSectionData] {
        if L10n.text("zh", "en") == "en" {
            return [
                GuideSectionData(
                    icon: "shield.checkerboard",
                    title: "1. Core Philosophy & Three Key Principles",
                    color: .blue,
                    items: [
                        ("Never Overwrite Source", "Underlying inode matching and atomic reservation ensure source files are never corrupted. Incremental suffixes are added if same folder."),
                        ("Honest Technical Disclosure", "Clearly separates Stream Copy, Mathematical Lossless, Visually Lossless, and Lossy. Rejects fake lossless claims."),
                        ("Zero Dependency Bundle", "Embedded Apple Silicon optimized FFmpeg/ImageMagick; no external tools or Homebrew required.")
                    ]
                ),
                GuideSectionData(
                    icon: "pawprint.fill",
                    title: "2. Visuals & Shiba Inu Pixel Animations",
                    color: Color(red: 0.91, green: 0.51, blue: 0.23),
                    items: [
                        ("Idle State", "Shiba sits and wags tail, waiting for file imports."),
                        ("Converting State", "Shiba runs diligently, indicating background conversion queue is active."),
                        ("Completed State", "Shiba wags tail happily and jumps to celebrate."),
                        ("Failed State", "Shiba tilts head in confusion, prompting you to inspect logs.")
                    ]
                ),
                GuideSectionData(
                    icon: "slider.horizontal.3",
                    title: "3. Five Core Conversion Modes",
                    color: .purple,
                    items: [
                        ("Stream Copy (Remux / -c copy)", "Changes container packaging (e.g. MKV to MP4) without decoding or re-encoding. Millisecond execution, zero quality loss."),
                        ("Mathematical Lossless (FFV1 MKV)", "Mathematical frame-by-frame archival lossless; decoded pixel hashes (framemd5) match 100%. Supports 10/12-bit high depth."),
                        ("Visually Lossless (ProRes 4444 XQ)", "Apple professional post-production 12-bit format. Ultra-smooth timeline editing; honestly classified as visually lossless."),
                        ("Audio Lossless & Compatibility", "FLAC / WAV / ALAC / AIFF 1:1 bit-exact verification; also offers MP3 / AAC / OGG / OPUS compatibility modes."),
                        ("Image Lossless & Image-to-PDF", "PNG / TIFF / WebP lossless conversion preserving ICC & EXIF. Image to PDF uses 1:1 pixel rasterization packaging."),
                        ("PDF to Image (Multi-page Rasterization)", "PDF to PNG / JPEG renders pages sequentially without dropping any pages (_p1, _p2 suffixes). Explicitly tagged as rasterization, not fake lossless.")
                    ]
                ),
                GuideSectionData(
                    icon: "cpu",
                    title: "4. Advanced Settings (Concurrency Tuning)",
                    color: .green,
                    items: [
                        ("Video Workers (Default 2, Range 1-8)", "Controls concurrent video tasks. Video transcoding is CPU/GPU intensive; 2 guarantees smooth macOS responsiveness."),
                        ("Image Workers (Default 4, Range 1-16)", "Controls concurrent image tasks. Images are lightweight and can process concurrently with higher counts."),
                        ("Hardware Tuning Guide", "M1-M3 recommend 2/4; M-Pro recommend 2-4/8; M-Max/Ultra can scale to 4-6/16 for extreme batch speed.")
                    ]
                ),
                GuideSectionData(
                    icon: "gauge.with.dots.needle.bottom.50percent",
                    title: "5. Real-Time Monitor & Safe Batch Mirroring",
                    color: .teal,
                    items: [
                        ("Dual Probe Track-by-Track", "Monitoring window displays input vs output video/audio tracks, profile, pix_fmt, and color space."),
                        ("Folder Tree Mirroring", "Drag entire directory structures; automatically mirrors nested subfolders with 6-worker probe throttling."),
                        ("One-Click Graceful Cancel", "Cancel anytime to immediately terminate background FFmpeg subprocesses and release temp files cleanly.")
                    ]
                )
            ]
        }
        return [
            GuideSectionData(
                icon: "shield.checkerboard",
                title: "1. 核心理念與三大原則",
                color: .blue,
                items: [
                    ("嚴格禁止覆寫原檔", "具備底層 Inode 識別與原子路徑預約，輸出與來源同目錄時自動添加編號，絕不損壞原檔。"),
                    ("誠實技術揭露", "分開標示「直通」、「數學無損」、「視覺接近無損」與「有損」，拒絕虛假無損宣稱。"),
                    ("零依賴自包含", "內嵌 Apple Silicon 優化之 FFmpeg/ImageMagick，無需安裝任何外部指令或套件。")
                ]
            ),
            GuideSectionData(
                icon: "pawprint.fill",
                title: "2. 介面視覺與點陣柴犬動態",
                color: Color(red: 0.91, green: 0.51, blue: 0.23),
                items: [
                    ("閒置狀態 (Idle)", "柴犬坐著晃尾巴，等待匯入檔案。"),
                    ("轉檔狀態 (Converting)", "柴犬認真奔跑，代表背景佇列運算中。"),
                    ("完成狀態 (Completed)", "柴犬開心搖尾並跳躍慶祝。"),
                    ("失敗狀態 (Failed)", "柴犬垂耳困惑搖頭，提示檢查日誌診斷。")
                ]
            ),
            GuideSectionData(
                icon: "slider.horizontal.3",
                title: "3. 五大核心處理模式詳解",
                color: .purple,
                items: [
                    ("封裝直通 (Remux / -c copy)", "更換容器包裝（如 MKV 轉 MP4），不解碼不重編碼，毫秒級完成且零畫質損失。"),
                    ("像素級數學無損 (FFV1 MKV)", "數學級逐幀無損典藏，解碼像素雜湊 100% framemd5 一致，支援 10/12-bit 高色深。"),
                    ("視覺接近無損 (ProRes 4444 XQ)", "Apple 專業後期調色 12-bit 規格，時間軸極致流暢，誠實定位為視覺無損。"),
                    ("音訊無損與相容性轉換", "FLAC / WAV / ALAC / AIFF 1:1 位元一致比對；另提供 MP3/AAC/OGG/OPUS 相容性模式。"),
                    ("圖片無損與圖片轉 PDF", "PNG / TIFF / WebP 無損互轉，保留 ICC 與 EXIF；圖片轉 PDF 採 1:1 像素點陣封裝（點陣包裝，非向量化，不保證零損失）。"),
                    ("PDF 轉圖片（多頁逐頁渲染）", "PDF 轉 PNG / JPEG 採逐頁渲染點陣輸出，多頁不遺漏（檔名附加 _p1, _p2 等序號）；提供標準與高解析度 (DPI) 渲染選項。此轉換本質為排版點陣化渲染，非原圖抽取或數學無損，系統明確標示無法驗證品質，避免虛假無損宣稱。")
                ]
            ),
            GuideSectionData(
                icon: "cpu",
                title: "4. 進階處理設定（並行效能調節）",
                color: .green,
                items: [
                    ("視訊並行 (預設 2, 範圍 1~8)", "控制同時轉碼的影片數量。影片極耗 CPU/GPU，設為 2 能保證流暢轉檔且 Mac 不卡頓。"),
                    ("圖片並行 (預設 4, 範圍 1~16)", "控制同時處理的圖片數量。圖片為原生輕量運算，可設定較高數值在短時間跑完。"),
                    ("硬體調校建議", "M1~M3 建議 2/4；M-Pro 建議 2~4/8；M-Max/Ultra 可調至 4~6/16 極速批次。")
                ]
            ),
            GuideSectionData(
                icon: "gauge.with.dots.needle.bottom.50percent",
                title: "5. 即時監控與萬檔批次鏡像",
                color: .teal,
                items: [
                    ("雙向 Probe 逐軌比對", "監控視窗清晰呈現輸入與輸出的視訊軌、音訊軌、Profile、pix_fmt 與色彩空間。"),
                    ("萬檔資料夾鏡像匯入", "支援拖曳整個目錄樹，自動鏡像維持原有子資料夾層級，內建 6-Worker Probe 節流。"),
                    ("一鍵優雅取消", "隨時點擊取消，立即中斷背景 FFmpeg 子行程並釋放暫存，安全乾淨退出。")
                ]
            )
        ]
    }
    
    private func guideSection(icon: String, title: String, color: Color, content: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(content, id: \.0) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0)
                            .font(.subheadline).bold()
                            .foregroundColor(.primary)
                        Text(item.1)
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    if item.0 != content.last?.0 {
                        Divider().padding(.vertical, 2)
                    }
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Tab 1: 技術矩陣
    private var technicalMatrixTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading) {
                        Text(L10n.text("無損原則與技術限制聲明", "Lossless Principles & Technical Disclaimers"))
                            .font(.title3).bold()
                        Text(L10n.text("誠實工程揭露：不誇大、不宣稱任意格式均可無損互轉", "Honest engineering disclosure: no false claims of universal lossless conversion"))
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // 注意事項清單
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("重要限制與警語", "Important Disclaimers & Limitations"))
                        .font(.headline)
                    ForEach(localizedDisclaimers, id: \.self) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.orange)
                            Text(item)
                                .font(.callout)
                        }
                    }
                }
                
                // 容器支援矩陣
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("容器直通相容矩陣 (Container Support Matrix)", "Container Support Matrix (Stream Copy)"))
                        .font(.headline)
                    
                    VStack(spacing: 6) {
                        ForEach(LosslessLimitations.containerSupportMatrix, id: \.container) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(row.name).bold()
                                    Spacer()
                                    Text(L10n.text("容器: .\(row.container)", "Container: .\(row.container)")).font(.caption).foregroundColor(.secondary)
                                }
                                Text(L10n.text("支援視訊: \(row.supportedVideo.joined(separator: ", "))", "Supported Video: \(row.supportedVideo.joined(separator: ", "))"))
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                Text(L10n.text("支援音訊: \(row.supportedAudio.joined(separator: ", "))", "Supported Audio: \(row.supportedAudio.joined(separator: ", "))"))
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                Text(L10n.text("備註: \(row.notes)", "Notes: \(localizedNotes(for: row.container, defaultNotes: row.notes))"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color.secondary.opacity(0.06))
                            .cornerRadius(6)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var localizedDisclaimers: [String] {
        if L10n.text("zh", "en") == "en" {
            return [
                "【External Image Engine】Embedded portable ImageMagick currently supports PNG/TIFF/BMP/JPEG/WebP and image-to-PDF; HEIC, RAW, and other formats are unverified. Animations/multi-page files that cannot be fully preserved are rejected rather than saved as incomplete single pages. If format constraints prevent preserving metadata or bit depth, the file is produced normally and clearly flagged with disqualified reasons and evidence.",
                "【Image to PDF Support】Supports directly packaging PNG, JPEG, WebP, TIFF, BMP into standard PDF documents using 1:1 pixel rasterization (preserves original image dimensions and pixels, zero lossy recompression, non-text/vector). Pure lightweight self-contained architecture, does not bundle heavy Office converter suites, does not support Word/Excel/PPT.",
                "【Not All Conversions Can Be Lossless】There is no technology in the industry where arbitrary format conversions are lossless. If the source is lossy (e.g. JPEG, low-bitrate MP3), converting to a lossless container only preserves the current decoded state, and cannot restore lost information.",
                "【Stream Copy & Smart Compatibility】Stream copy prioritizes preserving original audio/video bitstreams with zero quality loss. If the target container supports video but not audio (e.g. MP4 with uncompressed PCM), the system automatically uses Video Stream Copy + High-Quality Compatible Audio Transcode (e.g. 320k AAC) and notes it honestly; if neither is compatible, it guides compatible transcoding or rejects invalid packaging.",
                "【Pixel Lossless (Lossless Transcode) Limits】True mathematical pixel lossless re-encoding (e.g. FFV1, x264 8-bit CRF 0) is CPU-intensive, and output size is typically several times larger than lossy source. For high bit-depth (10-bit/12-bit) or 4:2:2/4:4:4 chroma, choose MKV (FFV1) to avoid silent downsampling in MP4.",
                "【ProRes 4444 XQ Visually Lossless Positioning】Apple officially positions ProRes as visually lossless (up to 12-bit, not mathematical bit-exact). Due to color space conversion and DCT quantization, decoded framemd5 differs from source; it is not archival mathematical lossless.",
                "【Metadata Preservation Differences】Different containers support different metadata specifications (e.g. tag differences between MKV and MP4, or EXIF support in specific image formats). This tool preserves all portable metadata whenever possible, but proprietary private tags or non-ASCII characters cannot be guaranteed 100% across containers.",
                "【Ad-hoc Code Signing & Gatekeeper Note】This distribution uses local Ad-hoc code signing (not commercially notarized by Apple Developer). If Gatekeeper prompts unverified developer on another Mac, go to 'System Settings > Privacy & Security' and click 'Open Anyway', or run `xattr -d com.apple.quarantine LosslessStudio.app` in Terminal."
            ]
        }
        return LosslessLimitations.disclaimers
    }

    private func localizedNotes(for container: String, defaultNotes: String) -> String {
        guard L10n.text("zh", "en") == "en" else { return defaultNotes }
        switch container {
        case "mkv": return "Highest compatibility, full support for FFV1 mathematical lossless and multi-audio/subtitles."
        case "mp4": return "Widely compatible with mobile devices. If audio is uncompressed PCM, automatically converted to high-quality AAC to preserve video bitstream."
        case "mov": return "Best compatibility with Apple ecosystem, supports ProRes 4444 XQ (visually lossless) and uncompressed PCM audio."
        case "webm": return "Open-source web standard container, restricted to open-source video/audio codecs."
        case "avi": return "Legacy Windows multimedia container."
        case "ts": return "Broadcast and streaming transport stream container."
        case "mxf": return "Professional broadcast container, supports 48kHz PCM audio and broadcast video codecs."
        default: return defaultNotes
        }
    }
}
