import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PDFKit

public struct ContentView: View {
    @ObservedObject var manager = ConversionManager.shared
    @State private var showingLimitations = false
    @State private var showingLogs = false
    @State private var showingReport = false
    @State private var showingMonitor = false
    @State private var isDropTargeted = false

    public init() {}

    private let warmOrange = Color(red: 0.91, green: 0.51, blue: 0.23)
    private let creamWhite = Color(red: 0.98, green: 0.97, blue: 0.95)
    private let softCharcoal = Color(red: 0.23, green: 0.21, blue: 0.20)

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            toolBar
            Divider()
            if !manager.tasks.isEmpty {
                DisclosureGroup("輸出格式") {
                    ScrollView { presetBar }.frame(maxHeight: 160)
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }
            Divider()
            taskListOrEmpty
            Divider()
            bottomBar
            if showingLogs { logPanel }
            if let report = manager.batchReport, showingReport { reportPanel(report) }
        }
        .font(.system(size: 16))
        .controlSize(.large)
        .frame(minWidth: 960, minHeight: 640)
        .background(creamWhite)
        .preferredColorScheme(.light)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .sheet(isPresented: $showingMonitor) {
            VStack(spacing: 0) {
                EncodingMonitorView()
                HStack {
                    Spacer()
                    Button("關閉監控視窗") { showingMonitor = false }
                        .keyboardShortcut(.cancelAction)
                        .padding(12)
                }
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }

    // MARK: - Animated Shiba State
    private var shibaCurrentState: ShibaAnimationState {
        if isDropTargeted { return .converting }
        if manager.isProcessing { return .converting }
        let hasFailed = manager.tasks.contains {
            switch $0.status {
            case .failed, .rejected: return true
            default:
                if let cmp = $0.comparison, cmp.verificationStatus == .mismatch || cmp.verificationStatus == .failed { return true }
                return false
            }
        }
        if hasFailed { return .failed }
        let hasCompleted = manager.tasks.contains {
            if case .completed = $0.status { return true }
            return false
        }
        if hasCompleted && !manager.isProcessing { return .completed }
        return .idle
    }

    // MARK: - Header
    private var headerBar: some View {
        HStack(spacing: 16) {
            // Original Pixel Shiba Sprite
            ShibaPixelView(state: shibaCurrentState, pixelSize: 2.5)
                .frame(width: 48, height: 48)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.8))
                        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("LosslessStudio")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(softCharcoal)
                    Text("檔案轉換")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(warmOrange.opacity(0.15))
                        .foregroundColor(warmOrange)
                        .cornerRadius(6)
                }
                Text("匯入檔案 → 選擇格式 → 開始轉檔")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button(action: { showingMonitor.toggle() }) {
                    Label("編碼對照監控", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }
                .buttonStyle(.borderedProminent)
                .tint(warmOrange)

                Button(action: { showingLimitations.toggle() }) {
                    Label("使用手冊與功能說明", systemImage: "book.pages")
                }
                .buttonStyle(.bordered)
            }
            .sheet(isPresented: $showingLimitations) {
                VStack {
                    LimitationsView()
                    Button("關閉") { showingLimitations = false }.padding(.bottom, 12)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.6))
    }

    // MARK: - Tool Bar
    private var toolBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
            Text("輸出目錄:")
                .font(.callout).bold()
                .foregroundColor(softCharcoal)
                .fixedSize()
            Text(manager.outputDirectory.path)
                .font(.system(size: 16)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(4)
            Button("變更...") { selectOutputFolder() }
                .buttonStyle(.borderless)
                .font(.callout)
                .fixedSize()

            }
            HStack(spacing: 12) {
            Button(action: selectFiles) {
                Label("匯入檔案…", systemImage: "plus.circle.fill")
            }
            .disabled(manager.isProcessing)
            .fixedSize()

            Button(action: selectFolder) {
                Label("匯入資料夾...", systemImage: "folder.badge.plus")
            }
            .disabled(manager.isProcessing)
            .fixedSize()

            Button(action: { manager.clearTasks() }) {
                Label("清空", systemImage: "trash")
            }
            .disabled(manager.tasks.isEmpty || manager.isProcessing)
            .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Preset Quick Switcher Bar
    private var presetBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(warmOrange)
                Text("批次預設格式:")
                    .font(.caption.bold())
                    .foregroundColor(softCharcoal)
            }

            if manager.tasks.contains(where: { $0.mediaKind == .audio }) {
            // 音訊預設選單
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .foregroundColor(warmOrange)
                    .font(.system(size: 16))
                Text("音訊:").font(.system(size: 16)).foregroundColor(.secondary)
                Menu {
                    ForEach(MediaPresets.audioPresets) { opt in
                        Button(action: {
                            manager.defaultAudioPreset = opt.id
                            manager.applyDefaultPresetsToPendingTasks()
                        }) {
                            HStack {
                                Text(opt.displayName)
                                if manager.defaultAudioPreset == opt.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Text(currentPresetLabel(for: .audio, id: manager.defaultAudioPreset))
                        .font(.system(size: 16))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .menuStyle(.borderlessButton)
                .frame(minWidth: 120, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.8))
            .cornerRadius(5)
            }

            if manager.tasks.contains(where: { $0.mediaKind == .image }) {
            // 圖片預設選單
            HStack(spacing: 4) {
                Image(systemName: "photo")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
                Text("圖片:").font(.system(size: 16)).foregroundColor(.secondary)
                Menu {
                    ForEach(MediaPresets.imagePresets) { opt in
                        Button(action: {
                            manager.defaultImagePreset = opt.id
                            manager.applyDefaultPresetsToPendingTasks()
                        }) {
                            HStack {
                                Text(opt.displayName)
                                if manager.defaultImagePreset == opt.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Text(currentPresetLabel(for: .image, id: manager.defaultImagePreset))
                        .font(.system(size: 16))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .menuStyle(.borderlessButton)
                .frame(minWidth: 105, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.8))
            .cornerRadius(5)
            }

            if manager.tasks.contains(where: { $0.mediaKind == .video }) {
            // 視訊預設選單
            HStack(spacing: 4) {
                Image(systemName: "film")
                    .foregroundColor(.blue)
                    .font(.system(size: 16))
                Text("視訊:").font(.system(size: 16)).foregroundColor(.secondary)
                Menu {
                    ForEach(MediaPresets.videoPresets) { opt in
                        Button(action: {
                            manager.defaultVideoPreset = opt.id
                            manager.applyDefaultPresetsToPendingTasks()
                        }) {
                            HStack {
                                Text(opt.displayName)
                                if manager.defaultVideoPreset == opt.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Text(currentPresetLabel(for: .video, id: manager.defaultVideoPreset))
                        .font(.system(size: 16))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .menuStyle(.borderlessButton)
                .frame(minWidth: 120, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.8))
            .cornerRadius(5)
            }

            if manager.tasks.contains(where: { $0.mediaKind == .document }) {
            // PDF 文件預設選單
            HStack(spacing: 4) {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.indigo)
                    .font(.system(size: 16))
                Text("PDF轉圖片:").font(.system(size: 16)).foregroundColor(.secondary)
                Menu {
                    ForEach(MediaPresets.documentPresets) { opt in
                        Button(action: {
                            manager.defaultDocumentPreset = opt.id
                            manager.applyDefaultPresetsToPendingTasks()
                        }) {
                            HStack {
                                Text(opt.displayName)
                                if manager.defaultDocumentPreset == opt.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Text(currentPresetLabel(for: .document, id: manager.defaultDocumentPreset))
                        .font(.system(size: 16))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .menuStyle(.borderlessButton)
                .frame(minWidth: 140, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.8))
            .cornerRadius(5)
            }




            Button(action: { manager.applyDefaultPresetsToPendingTasks() }) {
                Label("套用至未開始項目", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            .disabled(manager.tasks.isEmpty || manager.isProcessing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
    }

    // MARK: - Task List
    private var taskListOrEmpty: some View {
        Group {
            if manager.tasks.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(warmOrange)
                    Text(isDropTargeted ? "放開滑鼠以立即匯入檔案！" : "拖放影音、圖片或 PDF 文件 / 資料夾至此處")
                        .font(.headline)
                        .foregroundColor(isDropTargeted ? warmOrange : softCharcoal)
                    Text("支援 WAV/FLAC/MP3/MP4/MKV/PNG/TIFF/PDF 等格式，自動遞迴保留目錄結構")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        Button("加入多個檔案...") { selectFiles() }
                        Button("匯入整個資料夾...") { selectFolder() }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(manager.tasks.indices, id: \.self) { i in
                        taskRow(manager.tasks[i], index: i)
                    }
                }
                .listStyle(.inset)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isDropTargeted ? warmOrange : Color.clear, style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
                .background(isDropTargeted ? warmOrange.opacity(0.06) : Color.clear)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        )
    }

    private func taskRow(_ task: ConversionTaskItem, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 媒體類型專屬圖示
            mediaKindIcon(task.mediaKind)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(task.inputUrl.lastPathComponent)
                        .font(.system(.body, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)

                    if let rel = task.relativeInputPath, !rel.isEmpty, rel != task.inputUrl.lastPathComponent {
                        Text(rel)
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    if let insp = task.inspection {
                        Text(formatInspectionInfo(insp, for: task))
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    } else if task.inputUrl.pathExtension.lowercased() == "pdf" || task.mediaKind == .document {
                        Text(pdfFileInfo(for: task))
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    } else {
                        Text(inspectionPlaceholder(for: task.status))
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }

                    if let cmp = task.comparison, cmp.verificationStatus != .unverified {
                        Text(cmp.verificationStatus.rawValue)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(verificationColor(cmp.verificationStatus))
                    }
                }

                if task.mediaKind == .document || task.inputUrl.pathExtension.lowercased() == "pdf" {
                    let pageCount = task.pdfPageCount ?? PDFDocument(url: task.inputUrl)?.pageCount ?? 1
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.indigo)
                        Text(pageCount > 1 ? "多頁文件：逐頁排版渲染輸出為獨立圖檔（檔名自動附加 _page_1, _page_2...），共 \(pageCount) 頁完整輸出不遺漏" : "單頁文件：逐頁排版渲染輸出為獨立圖檔（若多頁將自動附加 _page_1, _page_2...）")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                }

                if task.outputUrls.count > 1 {
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.down.right.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.indigo)
                        Text("已成功逐頁產出 \(task.outputUrls.count) 個獨立圖檔 (無冗餘首頁副本): \(task.outputUrls.map { $0.lastPathComponent }.joined(separator: ", "))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.indigo)
                    }
                    .padding(.top, 2)
                }

                if let cmp = task.comparison, cmp.verificationStatus == .disqualified || !cmp.qualificationReasons.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        let noteClean = cmp.verificationNote.hasPrefix("未符無損: ") ? String(cmp.verificationNote.dropFirst(6)) : cmp.verificationNote
                        Text("未符無損原因: \(noteClean)")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(cmp.qualificationReasons, id: \.self) { reason in
                            Text("• \(reason)")
                                .font(.system(size: 14))
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if case .failed(let err) = task.status {
                    Text("失敗原因: \(err)")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if case .rejected(let reason) = task.status {
                    Text("拒絕原因: \(reason)")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {

            // 類別標籤徽章 (無損 / 直通 / 有損)
            categoryBadge(task)

            // 直覺單一目標格式選單 (依媒體類型自動分組)
            targetPresetPicker(task, index: index)

            // PDF 渲染解析度 (DPI) 調整
            if task.mediaKind == .document || task.inputUrl.pathExtension.lowercased() == "pdf" {
                Picker("", selection: Binding(
                    get: { manager.tasks[index].pdfDPI },
                    set: { manager.tasks[index].pdfDPI = $0 }
                )) {
                    Text("72 DPI").tag(72.0)
                    Text("150 DPI").tag(150.0)
                    Text("300 DPI").tag(300.0)
                    Text("600 DPI").tag(600.0)
                }
                .pickerStyle(.menu)
                .frame(width: 105)
                .disabled(manager.isProcessing)
                .help("設定 PDF 頁面點陣化渲染解析度 (DPI)")
            }

            // 有損音訊位元率細調
            if task.category == .audioLossy {
                Picker("", selection: Binding(
                    get: { manager.tasks[index].audioBitrate ?? "320k" },
                    set: { manager.tasks[index].audioBitrate = $0 }
                )) {
                    Text("320k").tag("320k")
                    Text("256k").tag("256k")
                    Text("192k").tag("192k")
                    Text("160k").tag("160k")
                    Text("128k").tag("128k")
                }
                .pickerStyle(.menu)
                .frame(width: 72)
                .disabled(manager.isProcessing)
            }

            Spacer()
            // 狀態欄
            statusView(for: task)
                .frame(width: 140, alignment: .trailing)

            // 移除單一任務按鈕
            if !manager.isProcessing {
                Button(action: { manager.removeTask(id: task.id) }) {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("移除此任務")
            }
        }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.7))
        .cornerRadius(12)
    }

    private func mediaKindIcon(_ kind: MediaKind) -> some View {
        switch kind {
        case .audio:
            return Image(systemName: "waveform")
                .foregroundColor(warmOrange)
        case .image:
            return Image(systemName: "photo.fill")
                .foregroundColor(.green)
        case .video:
            return Image(systemName: "film.fill")
                .foregroundColor(.blue)
        case .document:
            return Image(systemName: "doc.text.fill")
                .foregroundColor(.indigo)
        }
    }

    private func categoryBadge(_ task: ConversionTaskItem) -> some View {
        let text: String
        let color: Color
        if task.inputUrl.pathExtension.lowercased() == "pdf" || task.category == .document {
            text = "排版渲染"
            color = .indigo
        } else if task.category == .remux {
            text = "串流直通"
            color = .blue
        } else if task.category == .audioLossless || task.category == .videoLossless || task.category == .imageLossless {
            text = "無損"
            color = .green
        } else {
            text = "有損降轉"
            color = .orange
        }
        return Text(text)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .cornerRadius(4)
    }

    private func targetPresetPicker(_ task: ConversionTaskItem, index: Int) -> some View {
        let presets = MediaPresets.presets(for: task.mediaKind)
        let groups = Array(NSOrderedSet(array: presets.map { $0.group })).compactMap { $0 as? String }

        return Menu {
            ForEach(groups, id: \.self) { g in
                Section(header: Text(g)) {
                    ForEach(presets.filter { $0.group == g }) { opt in
                        Button(action: {
                            manager.tasks[index].applyPreset(id: opt.id)
                        }) {
                            HStack {
                                Text(opt.displayName)
                                if manager.tasks[index].currentPresetId == opt.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentPresetLabel(for: task.mediaKind, id: task.currentPresetId))
                    .font(.system(size: 16))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        }
        .frame(width: 185)
        .disabled(manager.isProcessing)
    }

    private func inspectionPlaceholder(for status: TaskStatus) -> String {
        switch status {
        case .pending: return "等待探測規格"
        case .inspecting: return "探測規格中…"
        case .processing: return "處理中 · 未取得規格"
        case .failed, .rejected, .cancelled, .completed: return "未取得規格"
        }
    }

    private func formatInspectionInfo(_ insp: MediaInspectionResult, for task: ConversionTaskItem) -> String {
        switch task.mediaKind {
        case .audio:
            var parts: [String] = []
            if let codec = insp.audioCodec, !codec.isEmpty {
                parts.append(codec)
            } else {
                parts.append("音訊軌")
            }
            if let ch = insp.audioChannels {
                parts.append(ch == 1 ? "單聲道" : (ch == 2 ? "立體聲" : "\(ch) 聲道"))
            }
            if let sr = insp.audioSampleRate {
                parts.append("\(sr) Hz")
            }
            if let stream = insp.streams.first(where: { $0.codecType == "audio" }), let bd = stream.bitDepth, bd > 0 {
                parts.append("\(bd)-bit")
            }
            return "音訊: " + parts.joined(separator: " · ")

        case .image:
            var parts: [String] = []
            if let res = insp.videoResolution, !res.isEmpty {
                parts.append(res)
            }
            if let cs = insp.imageColorSpace, !cs.isEmpty {
                parts.append(cs)
            }
            if let bpc = insp.imageBitsPerComponent {
                parts.append("\(bpc)-bit/色")
            }
            return "圖片: " + (parts.isEmpty ? "規格已探測" : parts.joined(separator: " · "))

        case .video:
            var vParts: [String] = []
            if let vCodec = insp.videoCodec {
                vParts.append(vCodec)
            }
            if let res = insp.videoResolution {
                vParts.append(res)
            }
            if let fps = insp.videoFrameRate {
                vParts.append("\(fps) fps")
            }
            let vText = vParts.isEmpty ? "視訊: 串流" : "視訊: " + vParts.joined(separator: " · ")

            if let aCodec = insp.audioCodec {
                var aParts = [aCodec]
                if let ch = insp.audioChannels {
                    aParts.append(ch == 1 ? "單聲道" : (ch == 2 ? "立體聲" : "\(ch)ch"))
                }
                if let sr = insp.audioSampleRate {
                    aParts.append("\(sr)Hz")
                }
                return "\(vText) | 音訊: " + aParts.joined(separator: " · ")
            } else {
                return vText
            }

        case .document:
            return pdfFileInfo(for: task)
        }
    }

    private func pdfFileInfo(for task: ConversionTaskItem) -> String {
        let extLower = task.inputUrl.pathExtension.lowercased()
        let size = (try? FileManager.default.attributesOfItem(atPath: task.inputUrl.path)[.size] as? Int64) ?? 0
        let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        if extLower == "pdf" {
            let pageCount = task.pdfPageCount ?? PDFDocument(url: task.inputUrl)?.pageCount ?? 1
            let dpi = Int(task.pdfDPI)
            return "PDF 文件 · \(pageCount) 頁 · \(sizeStr) · 渲染解析度: \(dpi) DPI"
        }
        return "文件: \(extLower.uppercased()) · \(sizeStr)"
    }

    private func currentPresetLabel(for kind: MediaKind, id: String) -> String {
        if kind == .document {
            switch id.lowercased() {
            case "png", "pdf_to_png": return "PNG (多頁渲染)"
            case "jpg", "jpeg", "pdf_to_jpg": return "JPEG (95%)"
            case "tiff", "tif", "pdf_to_tiff": return "TIFF (未壓縮)"
            case "webp", "pdf_to_webp": return "WebP (高效圖檔)"
            case "bmp", "pdf_to_bmp": return "BMP (位圖)"
            case "pdf", "img_to_pdf": return "圖片轉 PDF"
            default: return "\(id.uppercased()) 圖片"
            }
        }
        if let opt = MediaPresets.presets(for: kind).first(where: { $0.id == id }) {
            return opt.displayName
        }
        return id
    }

    private func verificationColor(_ v: VerificationStatus) -> Color {
        switch v {
        case .passed: return .green
        case .visualLossless: return .blue
        case .lossyConversion, .disqualified: return .orange
        case .mismatch, .failed: return .red
        case .verifying: return .orange
        case .cannotVerify, .unverified: return .secondary
        }
    }

    @ViewBuilder
    private func statusView(for task: ConversionTaskItem) -> some View {
        switch task.status {
        case .pending:
            Text("等待中").font(.system(size: 16)).foregroundColor(.secondary)
        case .inspecting:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("探測中").font(.system(size: 16)).foregroundColor(.secondary)
            }
        case .processing(let p, _, _):
            VStack(alignment: .trailing, spacing: 2) {
                ProgressView(value: p).controlSize(.small)
                Text(String(format: "%.0f%%", p * 100)).font(.system(size: 16))
            }
        case .completed:
            if let cmp = task.comparison, cmp.verificationStatus == .disqualified {
                Label("已完成・有警告", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.orange)
                    .help(cmp.verificationNote)
            } else if let cmp = task.comparison, cmp.verificationStatus == .cannotVerify {
                Label("已完成・無法驗證", systemImage: "questionmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
                    .help(cmp.verificationNote)
            } else {
                Label("完成", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundColor(.green)
            }
        case .rejected(let reason):
            Label("拒絕", systemImage: "xmark.circle")
                .font(.system(size: 16))
                .foregroundColor(.red)
                .help(reason)
        case .failed(let err):
            Label("失敗", systemImage: "exclamationmark.triangle")
                .font(.system(size: 16))
                .foregroundColor(.red)
                .help(err)
        case .cancelled:
            Text("已取消").font(.system(size: 16)).foregroundColor(.secondary)
        }
    }

    // MARK: - Bottom Bar
    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { showingLogs.toggle() }) {
                Label(showingLogs ? "隱藏日誌" : "顯示日誌 (\(manager.globalLogs.count))", systemImage: "text.alignleft")
            }
            .buttonStyle(.borderless)
            .fixedSize()

            if manager.batchReport != nil {
                Button(action: { showingReport.toggle() }) {
                    Label("批次摘要報告", systemImage: "chart.bar.doc.horizontal")
                }
                .buttonStyle(.borderless)
                .fixedSize()
            }



            DisclosureGroup("進階處理設定") {
            // 並行度控制 (乾淨緊湊、標籤隱藏、絕不折行擠壓)
            HStack(spacing: 6) {
                Text("視訊並行: \(manager.maxVideoWorkers)").font(.system(size: 16)).foregroundColor(.secondary).fixedSize()
                Stepper("", value: $manager.maxVideoWorkers, in: 1...8)
                    .labelsHidden()
                    .controlSize(.mini)
                Text("圖片並行: \(manager.maxImageWorkers)").font(.system(size: 16)).foregroundColor(.secondary).fixedSize()
                Stepper("", value: $manager.maxImageWorkers, in: 1...16)
                    .labelsHidden()
                    .controlSize(.mini)
            }

            }



            HStack(spacing: 16) {
            // 統計摘要
            let total = manager.tasks.count
            let done = manager.tasks.filter { if case .completed = $0.status { return true }; return false }.count
            let warned = manager.tasks.filter {
                if case .completed = $0.status, let cmp = $0.comparison, cmp.verificationStatus == .disqualified { return true }
                return false
            }.count
            let fail = manager.tasks.filter {
                switch $0.status {
                case .failed, .rejected: return true
                default: return false
                }
            }.count
            let summaryText = warned > 0
                ? "共 \(total) 項 | 成功: \(done) (有警告: \(warned)) | 失敗: \(fail)"
                : "共 \(total) 項 | 成功: \(done) | 失敗: \(fail)"
            Text(summaryText)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .fixedSize()

            Spacer()
            // 取消按鈕
            if manager.isProcessing {
                Button("取消批次", role: .destructive) {
                    manager.cancelBatch()
                }
                .buttonStyle(.bordered)
            }

            // 重試按鈕
            if fail > 0 && !manager.isProcessing {
                Button(action: { manager.retryFailed() }) {
                    Label("重試失敗項目 (\(fail))", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            // 開始批次
            Button(action: { manager.startBatch() }) {
                if manager.isProcessing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("處理中...")
                    }
                } else {
                    Label("開始轉檔", systemImage: "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(warmOrange)
            .disabled(manager.tasks.isEmpty || manager.isProcessing)
        }
            }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Logs Panel
    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("即時執行日誌").font(.caption.bold())
                Spacer()
                Button("複製日誌") {
                    let full = manager.globalLogs.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(full, forType: .string)
                }
                .buttonStyle(.borderless).font(.system(size: 16))
                Button("清空") { manager.globalLogs.removeAll() }
                    .buttonStyle(.borderless).font(.system(size: 16))
            }
            .padding(.horizontal, 12).padding(.top, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(manager.globalLogs.indices, id: \.self) { i in
                        Text(manager.globalLogs[i])
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
            .frame(height: 120)
        }
        .background(Color.black.opacity(0.04))
    }

    // MARK: - Report Panel
    private func reportPanel(_ r: BatchReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("批次報告摘要").font(.caption.bold())
                Spacer()
                Button("關閉") { showingReport = false }.buttonStyle(.borderless).font(.system(size: 16))
            }
            .padding(.horizontal, 12).padding(.top, 6)
            Text(r.summary)
                .font(.system(size: 14, design: .monospaced))
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
        }
        .background(Color.secondary.opacity(0.05))
    }

    // MARK: - Drag and Drop Handling
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !manager.isProcessing else { return false }
        let group = DispatchGroup()
        var loadedUrls: [URL] = []
        let lock = NSLock()

        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let u = url {
                        lock.lock()
                        loadedUrls.append(u)
                        lock.unlock()
                    }
                    group.leave()
                }
            } else {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let url = item as? URL {
                        lock.lock()
                        loadedUrls.append(url)
                        lock.unlock()
                    } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        lock.lock()
                        loadedUrls.append(url)
                        lock.unlock()
                    } else if let str = item as? String, let url = URL(string: str) {
                        lock.lock()
                        loadedUrls.append(url)
                        lock.unlock()
                    }
                }
            }
        }

        group.notify(queue: .main) {
            guard !loadedUrls.isEmpty else { return }
            var regularFiles: [URL] = []
            for url in loadedUrls {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    self.manager.addFolder(rootUrl: url)
                } else {
                    regularFiles.append(url)
                }
            }
            if !regularFiles.isEmpty {
                self.manager.addFiles(urls: regularFiles)
            }
        }
        return true
    }

    // MARK: - Actions & Helpers
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            manager.addFiles(urls: panel.urls)
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            manager.addFolder(rootUrl: url)
        }
    }

    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            manager.outputDirectory = url
        }
    }
}
