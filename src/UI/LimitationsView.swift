import SwiftUI
import AppKit

public struct LimitationsView: View {
    @State private var selectedTab: Int = 0
    @State private var copiedNotice: Bool = false
    
    public init() {}
    
    private var guideText: String {
        // 由 App Bundle 載入內建手冊
        if let url = Bundle.main.url(forResource: "USER_GUIDE", withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        if let resourceUrl = Bundle.main.resourceURL?.appendingPathComponent("USER_GUIDE.md"),
           let content = try? String(contentsOf: resourceUrl, encoding: .utf8) {
            return content
        }
        return "手冊已內建於應用程式中。"
    }
    
    private func openGuideInExternalApp() {
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
                    Text("LosslessStudio 功能說明與使用手冊")
                        .font(.title3).bold()
                    Text("深入了解無損原則、批次處理、效能調校與格式矩陣")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                
                Picker("", selection: $selectedTab) {
                    Text("📖 功能操作手冊").tag(0)
                    Text("🛡️ 技術原則與相容矩陣").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
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
        .frame(minWidth: 640, minHeight: 520)
    }
    
    // MARK: - Tab 0: 使用手冊
    private var userGuideTab: some View {
        VStack(spacing: 0) {
            // 快捷動作列
            HStack(spacing: 12) {
                Text("📌 支援點對點無損、直通、多線程並行與安全防護")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                
                if copiedNotice {
                    Text("✓ 已複製全文至剪貼簿")
                        .font(.caption).bold()
                        .foregroundColor(.green)
                }
                
                Button(action: copyToClipboard) {
                    Label("複製全文", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                
                Button(action: openGuideInExternalApp) {
                    Label("在系統中開啟 .md", systemImage: "arrow.up.forward.app")
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.04))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 1. 核心理念
                    guideSection(
                        icon: "shield.checkerboard",
                        title: "1. 核心理念與三大原則",
                        color: .blue,
                        content: [
                            ("嚴格禁止覆寫原檔", "具備底層 Inode 識別與原子路徑預約，輸出與來源同目錄時自動添加編號，絕不損壞原檔。"),
                            ("誠實技術揭露", "分開標示「直通」、「數學無損」、「視覺接近無損」與「有損」，拒絕虛假無損宣稱。"),
                            ("零依賴自包含", "內嵌 Apple Silicon 優化之 FFmpeg/ImageMagick，無需安裝任何外部指令或套件。")
                        ]
                    )
                    
                    // 2. 柴犬動畫與視覺
                    guideSection(
                        icon: "pawprint.fill",
                        title: "2. 介面視覺與點陣柴犬動態",
                        color: Color(red: 0.91, green: 0.51, blue: 0.23),
                        content: [
                            ("閒置狀態 (Idle)", "柴犬坐著晃尾巴，等待匯入檔案。"),
                            ("轉檔狀態 (Converting)", "柴犬認真奔跑，代表背景佇列運算中。"),
                            ("完成狀態 (Completed)", "柴犬開心搖尾並跳躍慶祝。"),
                            ("失敗狀態 (Failed)", "柴犬垂耳困惑搖頭，提示檢查日誌診斷。")
                        ]
                    )
                    
                    // 3. 五大核心處理模式
                    guideSection(
                        icon: "slider.horizontal.3",
                        title: "3. 五大核心處理模式詳解",
                        color: .purple,
                        content: [
                            ("封裝直通 (Remux / -c copy)", "更換容器包裝（如 MKV 轉 MP4），不解碼不重編碼，毫秒級完成且零畫質損失。"),
                            ("像素級數學無損 (FFV1 MKV)", "數學級逐幀無損典藏，解碼像素雜湊 100% framemd5 一致，支援 10/12-bit 高色深。"),
                            ("視覺接近無損 (ProRes 4444 XQ)", "Apple 專業後期調色 12-bit 規格，時間軸極致流暢，誠實定位為視覺無損。"),
                            ("音訊無損與相容性轉換", "FLAC / WAV / ALAC / AIFF 1:1 位元一致比對；另提供 MP3/AAC/OGG/OPUS 相容性模式。"),
                            ("圖片無損與圖片轉 PDF", "PNG / TIFF / WebP 無損互轉，保留 ICC 與 EXIF；圖片轉 PDF 採 1:1 像素點陣封裝（點陣包裝，非向量化，不保證零損失）。"),
                            ("PDF 轉圖片（多頁逐頁渲染）", "PDF 轉 PNG / JPEG 採逐頁渲染點陣輸出，多頁不遺漏（檔名附加 _p1, _p2 等序號）；提供標準與高解析度 (DPI) 渲染選項。此轉換本質為排版點陣化渲染，非原圖抽取或數學無損，系統明確標示無法驗證品質，避免虛假無損宣稱。")
                        ]
                    )
                    
                    // 4. 進階效能調節
                    guideSection(
                        icon: "cpu",
                        title: "4. 進階處理設定（並行效能調節）",
                        color: .green,
                        content: [
                            ("視訊並行 (預設 2, 範圍 1~8)", "控制同時轉碼的影片數量。影片極耗 CPU/GPU，設為 2 能保證流暢轉檔且 Mac 不卡頓。"),
                            ("圖片並行 (預設 4, 範圍 1~16)", "控制同時處理的圖片數量。圖片為原生輕量運算，可設定較高數值在短時間跑完。"),
                            ("硬體調校建議", "M1~M3 建議 2/4；M-Pro 建議 2~4/8；M-Max/Ultra 可調至 4~6/16 極速批次。")
                        ]
                    )
                    
                    // 5. 即時監控與批次安全
                    guideSection(
                        icon: "gauge.with.dots.needle.bottom.50percent",
                        title: "5. 即時監控與萬檔批次鏡像",
                        color: .teal,
                        content: [
                            ("雙向 Probe 逐軌比對", "監控視窗清晰呈現輸入與輸出的視訊軌、音訊軌、Profile、pix_fmt 與色彩空間。"),
                            ("萬檔資料夾鏡像匯入", "支援拖曳整個目錄樹，自動鏡像維持原有子資料夾層級，內建 6-Worker Probe 節流。"),
                            ("一鍵優雅取消", "隨時點擊取消，立即中斷背景 FFmpeg 子行程並釋放暫存，安全乾淨退出。")
                        ]
                    )
                }
                .padding(20)
            }
        }
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
                        Text("無損原則與技術限制聲明")
                            .font(.title3).bold()
                        Text("誠實工程揭露：不誇大、不宣稱任意格式均可無損互轉")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // 注意事項清單
                VStack(alignment: .leading, spacing: 8) {
                    Text("重要限制與警語")
                        .font(.headline)
                    ForEach(LosslessLimitations.disclaimers, id: \.self) { item in
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
                    Text("容器直通相容矩陣 (Container Support Matrix)")
                        .font(.headline)
                    
                    VStack(spacing: 6) {
                        ForEach(LosslessLimitations.containerSupportMatrix, id: \.container) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(row.name).bold()
                                    Spacer()
                                    Text("容器: .\(row.container)").font(.caption).foregroundColor(.secondary)
                                }
                                Text("支援視訊: \(row.supportedVideo.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                Text("支援音訊: \(row.supportedAudio.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                Text("備註: \(row.notes)")
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
}
