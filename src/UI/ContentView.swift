import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct ContentView: View {
    @ObservedObject var manager = ConversionManager.shared
    @State private var showingLimitations = false
    @State private var showingLogs = false
    @State private var showingReport = false
    @State private var showingMonitor = false

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
            taskListOrEmpty
            Divider()
            bottomBar
            if showingLogs { logPanel }
            if let report = manager.batchReport, showingReport { reportPanel(report) }
        }
        .frame(minWidth: 920, minHeight: 620)
        .background(creamWhite)
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
        if manager.isProcessing { return .converting }
        let hasFailed = manager.tasks.contains {
            switch $0.status {
            case .failed, .rejected: return true
            default:
                if let cmp = $0.comparison, cmp.verificationStatus == .mismatch { return true }
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
            ShibaPixelView(state: shibaCurrentState, pixelSize: 4.5)
                .frame(width: 72, height: 72)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.8))
                        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("LosslessStudio")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(softCharcoal)
                    Text("柴犬像素無損工作站")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(warmOrange.opacity(0.15))
                        .foregroundColor(warmOrange)
                        .cornerRadius(6)
                }
                Text("串流直通 (-c copy) · 數學無損編碼 · 前後編碼對照監控 · 千檔目錄結構保留")
                    .font(.caption)
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
                    Label("技術限制說明", systemImage: "info.circle")
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
        HStack(spacing: 10) {
            Text("輸出目錄:")
                .font(.callout).bold()
                .foregroundColor(softCharcoal)
            Text(manager.outputDirectory.path)
                .font(.caption).foregroundColor(.secondary)
                .lineLimit(1).truncationMode(.middle)
                .padding(4)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(4)
            Button("變更...") { selectOutputFolder() }
                .buttonStyle(.borderless)
                .font(.callout)

            Spacer()

            // 並行度控制
            HStack(spacing: 6) {
                Text("視訊並行:").font(.caption2).foregroundColor(.secondary)
                Stepper("\(manager.maxVideoWorkers)", value: $manager.maxVideoWorkers, in: 1...8)
                    .frame(width: 80).font(.caption2)
                Text("圖片並行:").font(.caption2).foregroundColor(.secondary)
                Stepper("\(manager.maxImageWorkers)", value: $manager.maxImageWorkers, in: 1...16)
                    .frame(width: 80).font(.caption2)
            }

            Divider().frame(height: 20)

            Button(action: selectFiles) {
                Label("加入檔案...", systemImage: "plus.circle")
            }
            .disabled(manager.isProcessing)

            Button(action: selectFolder) {
                Label("匯入資料夾...", systemImage: "folder.badge.plus")
            }
            .disabled(manager.isProcessing)

            Button(action: { manager.clearTasks() }) {
                Label("清空", systemImage: "trash")
            }
            .disabled(manager.tasks.isEmpty || manager.isProcessing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Task List
    private var taskListOrEmpty: some View {
        Group {
            if manager.tasks.isEmpty {
                VStack(spacing: 16) {
                    ShibaPixelView(state: .idle, pixelSize: 6)
                        .frame(width: 96, height: 96)
                    Text("拖放影音或圖片檔案 / 資料夾至此處")
                        .font(.headline)
                        .foregroundColor(softCharcoal)
                    Text("支援遞迴匯入資料夾，將自動鏡像保留相對目錄結構，防止同名衝突與覆寫")
                        .font(.caption)
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
    }

    private func taskRow(_ task: ConversionTaskItem, index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconForCategory(task.category))
                .foregroundColor(task.category.isBitstreamCopy ? .blue : warmOrange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(task.inputUrl.lastPathComponent)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)

                    if let rel = task.relativeInputPath, !rel.isEmpty, rel != task.inputUrl.lastPathComponent {
                        Text(rel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    if let insp = task.inspection {
                        Text(insp.isImage ? "圖片: \(insp.videoResolution ?? "未知")" : "視訊: \(insp.videoCodec ?? "未知") | 音訊: \(insp.audioCodec ?? "未知")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("探測規格中...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let cmp = task.comparison, cmp.verificationStatus != .unverified {
                        Text(cmp.verificationStatus.rawValue)
                            .font(.caption2.bold())
                            .foregroundColor(verificationColor(cmp.verificationStatus))
                    }
                }
            }

            Spacer()

            // 模式選擇
            Picker("", selection: Binding(
                get: { manager.tasks[index].category },
                set: { newCat in
                    manager.tasks[index].category = newCat
                    let allowed = allowedContainers(for: newCat)
                    if !allowed.contains(manager.tasks[index].outputContainer) {
                        manager.tasks[index].outputContainer = allowed.first ?? "mkv"
                    }
                }
            )) {
                ForEach(ConversionCategory.allCases) { cat in
                    Text(categoryShortLabel(cat)).tag(cat)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
            .disabled(manager.isProcessing)

            // 目標格式
            Picker("", selection: Binding(
                get: { manager.tasks[index].outputContainer },
                set: { manager.tasks[index].outputContainer = $0 }
            )) {
                ForEach(allowedContainers(for: task.category), id: \.self) { c in
                    Text(".\(c)").tag(c)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 75)
            .disabled(manager.isProcessing)

            if task.category == .audioLossy {
                Picker("", selection: Binding(
                    get: { manager.tasks[index].audioBitrate ?? "320k" },
                    set: { manager.tasks[index].audioBitrate = $0 }
                )) {
                    Text("320k").tag("320k")
                    Text("256k").tag("256k")
                    Text("192k").tag("192k")
                    Text("128k").tag("128k")
                }
                .pickerStyle(.menu)
                .frame(width: 75)
                .disabled(manager.isProcessing)
            }

            // 狀態欄
            statusView(task.status)
                .frame(width: 140, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private func categoryShortLabel(_ cat: ConversionCategory) -> String {
        switch cat {
        case .remux: return "串流直通"
        case .videoLossless: return "無損視訊"
        case .imageLossless: return "無損圖片"
        case .audioLossless: return "無損音訊"
        case .audioLossy: return "有損降轉"
        }
    }

    private func verificationColor(_ v: VerificationStatus) -> Color {
        switch v {
        case .passed: return .green
        case .visualLossless: return .blue
        case .lossyConversion: return .orange
        case .mismatch: return .red
        case .verifying: return .orange
        case .cannotVerify, .unverified: return .secondary
        }
    }

    @ViewBuilder
    private func statusView(_ status: TaskStatus) -> some View {
        switch status {
        case .pending:
            Text("等待中").font(.caption).foregroundColor(.secondary)
        case .inspecting:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("探測中").font(.caption).foregroundColor(.secondary)
            }
        case .processing(let p, _, _):
            VStack(alignment: .trailing, spacing: 2) {
                ProgressView(value: p).controlSize(.small)
                Text(String(format: "%.0f%%", p * 100)).font(.caption2)
            }
        case .completed:
            Label("完成", systemImage: "checkmark.circle.fill")
                .font(.caption.bold())
                .foregroundColor(.green)
        case .rejected(let reason):
            Label("拒絕", systemImage: "xmark.circle")
                .font(.caption)
                .foregroundColor(.red)
                .help(reason)
        case .failed(let err):
            Label("失敗", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(.red)
                .help(err)
        case .cancelled:
            Text("已取消").font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - Bottom Bar
    private var bottomBar: some View {
        HStack {
            Button(action: { showingLogs.toggle() }) {
                Label(showingLogs ? "隱藏日誌" : "顯示日誌 (\(manager.globalLogs.count))", systemImage: "text.alignleft")
            }
            .buttonStyle(.borderless)

            if manager.batchReport != nil {
                Button(action: { showingReport.toggle() }) {
                    Label("批次摘要報告", systemImage: "chart.bar.doc.horizontal")
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            // 統計摘要
            let total = manager.tasks.count
            let done = manager.tasks.filter { if case .completed = $0.status { return true }; return false }.count
            let fail = manager.tasks.filter { if case .failed = $0.status { return true }; return false }.count
            Text("共 \(total) 項 | 成功: \(done) | 失敗: \(fail)")
                .font(.caption)
                .foregroundColor(.secondary)

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
                    Label("開始無損轉檔", systemImage: "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(warmOrange)
            .disabled(manager.tasks.isEmpty || manager.isProcessing)
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
                .buttonStyle(.borderless).font(.caption2)
                Button("清空") { manager.globalLogs.removeAll() }
                    .buttonStyle(.borderless).font(.caption2)
            }
            .padding(.horizontal, 12).padding(.top, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(manager.globalLogs.indices, id: \.self) { i in
                        Text(manager.globalLogs[i])
                            .font(.system(size: 11, design: .monospaced))
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
                Button("關閉") { showingReport = false }.buttonStyle(.borderless).font(.caption2)
            }
            .padding(.horizontal, 12).padding(.top, 6)
            Text(r.summary)
                .font(.system(size: 11, design: .monospaced))
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
        }
        .background(Color.secondary.opacity(0.05))
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

    private func iconForCategory(_ cat: ConversionCategory) -> String {
        switch cat {
        case .remux: return "arrow.right.arrow.left.square.fill"
        case .videoLossless: return "film.fill"
        case .imageLossless: return "photo.fill"
        case .audioLossless: return "waveform"
        case .audioLossy: return "waveform.badge.minus"
        }
    }

    private func allowedContainers(for cat: ConversionCategory) -> [String] {
        switch cat {
        case .remux:
            return ["mkv", "mp4", "mov", "webm"]
        case .videoLossless:
            return ["mkv", "mov", "mp4"]
        case .imageLossless:
            return ["tiff", "png", "bmp", "webp"]
        case .audioLossless:
            return ["flac", "wav", "m4a", "aiff"]
        case .audioLossy:
            return ["mp3", "m4a", "ogg", "opus"]
        }
    }
}
