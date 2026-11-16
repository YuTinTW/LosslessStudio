import SwiftUI
import AppKit
import PDFKit

public struct EncodingMonitorView: View {
    @ObservedObject var manager = ConversionManager.shared
    @State private var selectedTaskId: UUID?
    @State private var filterStatus: String = "全部"
    @State private var exportedReportUrl: URL?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                            .font(.title2)
                            .foregroundColor(Color(red: 0.91, green: 0.51, blue: 0.23))
                        Text("編碼即時監控與前後規格對照")
                            .font(.title2.bold())
                            .foregroundColor(.primary)
                    }
                    Text("逐檔即時比對來源與輸出之真實探測資訊，嚴格驗證串流直通 (-c copy) 與數學無損一致性，絕不偷偷改變編碼")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    if let url = manager.exportVerificationReport() {
                        exportedReportUrl = url
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }) {
                    Label("匯出驗證報告", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.91, green: 0.51, blue: 0.23))
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(Divider(), alignment: .bottom)

            // Split View: Task List on Left, Detailed Comparison on Right
            HSplitView {
                // Left Column: Tasks Queue
                VStack(spacing: 0) {
                    HStack {
                        Text("工作佇列 (\(manager.tasks.count))")
                            .font(.headline)
                        Spacer()
                        Picker("", selection: $filterStatus) {
                            Text("全部").tag("全部")
                            Text("已完成").tag("已完成")
                            Text("未通過/失敗").tag("未通過/失敗")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .overlay(Divider(), alignment: .bottom)

                    List(selection: $selectedTaskId) {
                        ForEach(filteredTasks) { task in
                            TaskRowView(task: task)
                                .tag(task.id)
                        }
                    }
                    .listStyle(.inset)
                }
                .frame(minWidth: 320, maxWidth: 450)

                // Right Column: Side-by-Side Detailed Comparison
                VStack(spacing: 0) {
                    if let selectedTask = manager.tasks.first(where: { $0.id == selectedTaskId }) {
                        DetailedComparisonCard(task: selectedTask)
                    } else if let firstTask = manager.tasks.first {
                        DetailedComparisonCard(task: firstTask)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("尚無轉檔任務")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("加入檔案或資料夾後，即可在此即時監控輸入與輸出之編碼參數對照")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 500)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var filteredTasks: [ConversionTaskItem] {
        switch filterStatus {
        case "已完成":
            return manager.tasks.filter { if case .completed = $0.status { return true }; return false }
        case "未通過/失敗":
            return manager.tasks.filter {
                switch $0.status {
                case .failed, .rejected: return true
                default:
                    if let cmp = $0.comparison, cmp.verificationStatus == .mismatch || cmp.verificationStatus == .disqualified || cmp.verificationStatus == .failed { return true }
                    return false
                }
            }
        default:
            return manager.tasks
        }
    }
}

// MARK: - Task Row View

struct TaskRowView: View {
    let task: ConversionTaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(task.inputUrl.lastPathComponent)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                statusBadge
            }

            HStack {
                Text(task.category.isBitstreamCopy ? "串流直通" : (task.category == .document ? "排版渲染" : "重編碼"))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(task.category.isBitstreamCopy ? Color.green.opacity(0.15) : (task.category == .document ? Color.indigo.opacity(0.15) : Color.orange.opacity(0.15)))
                    .foregroundColor(task.category.isBitstreamCopy ? .green : (task.category == .document ? .indigo : .orange))
                    .cornerRadius(4)

                Spacer()

                if let cmp = task.comparison {
                    Text(cmp.verificationStatus.rawValue)
                        .font(.caption2)
                        .foregroundColor(verificationColor(cmp.verificationStatus))
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch task.status {
        case .pending:
            Text("等待").font(.caption2).foregroundColor(.secondary)
        case .inspecting:
            Text("探測中").font(.caption2).foregroundColor(.blue)
        case .processing(let p, _, _):
            Text("\(Int(p * 100))%").font(.caption2).foregroundColor(.orange)
        case .completed:
            if let cmp = task.comparison, cmp.verificationStatus == .disqualified {
                Text("完成(警告)").font(.caption2.bold()).foregroundColor(.orange)
            } else if let cmp = task.comparison, cmp.verificationStatus == .cannotVerify {
                Text("完成(未比對)").font(.caption2.bold()).foregroundColor(.secondary)
            } else {
                Text("完成").font(.caption2).foregroundColor(.green)
            }
        case .rejected:
            Text("拒絕").font(.caption2).foregroundColor(.red)
        case .failed:
            Text("失敗").font(.caption2).foregroundColor(.red)
        case .cancelled:
            Text("取消").font(.caption2).foregroundColor(.secondary)
        }
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
}

// MARK: - Detailed Comparison Card

struct DetailedComparisonCard: View {
    let task: ConversionTaskItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Task Overview Banner
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(task.inputUrl.lastPathComponent)
                            .font(.title3.bold())
                        Spacer()
                        if let v = task.comparison?.verificationStatus {
                            verificationBadge(v)
                        }
                    }

                    HStack(spacing: 12) {
                        Label(task.category == .document ? "排版渲染輸出 (非數學無損)" : task.category.rawValue, systemImage: task.category.isBitstreamCopy ? "arrow.right.arrow.left" : (task.category == .document ? "doc.on.doc" : "gearshape.2"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let duration = taskDuration {
                            Label("耗時 \(String(format: "%.2f", duration))s", systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Side-by-Side Comparison Grid
                Text("實際輸入與輸出規格並排對照 (真實 Probe 資料)")
                    .font(.headline)
                    .foregroundColor(.primary)

                HStack(alignment: .top, spacing: 16) {
                    // Left Column: Input
                    SpecificationColumn(
                        title: "來源檔案 (Input)",
                        subtitle: task.inputUrl.path,
                        inspection: task.comparison?.inputInspection,
                        accentColor: .blue
                    )

                    // Right Column: Output
                    SpecificationColumn(
                        title: "輸出產物 (Output)",
                        subtitle: task.outputUrls.count > 1 ? "\(task.outputUrls.first?.path ?? "") 等共 \(task.outputUrls.count) 頁" : (task.comparison?.outputUrl?.path ?? "尚未完成產出"),
                        inspection: task.comparison?.outputInspection,
                        accentColor: .green,
                        outputUrls: task.outputUrls
                    )
                }

                // Verification Result Box
                if let cmp = task.comparison {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: cmp.verificationStatus == .passed ? "checkmark.seal.fill" : (cmp.verificationStatus == .disqualified ? "exclamationmark.triangle.fill" : "info.circle.fill"))
                                .foregroundColor(verificationColor(cmp.verificationStatus))
                            Text("無損一致性驗證結果：\(cmp.verificationStatus.rawValue)")
                                .font(.headline)
                        }
                        Text(cmp.verificationNote)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if !cmp.qualificationReasons.isEmpty {
                            Divider()
                            Text("未符無損之具體原因與差異細節：")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                            ForEach(cmp.qualificationReasons, id: \.self) { reason in
                                Text("• \(reason)")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }

                        if let ih = cmp.inputHash, let oh = cmp.outputHash {
                            Divider()
                            HStack {
                                Text("來源位元/像素 Hash:")
                                    .font(.caption.bold())
                                Text(ih)
                                    .font(.caption.monospaced())
                            }
                            HStack {
                                Text("輸出位元/像素 Hash:")
                                    .font(.caption.bold())
                                Text(oh)
                                    .font(.caption.monospaced())
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(verificationColor(cmp.verificationStatus).opacity(0.4), lineWidth: 1)
                    )
                    .cornerRadius(8)
                }

                // Execution Command & Log
                if let cmd = task.executionCommand {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("底層執行參數 (透明可查)")
                                .font(.headline)
                            Spacer()
                            Button("複製指令") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(cmd, forType: .string)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }

                        Text(cmd)
                            .font(.system(.caption, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.85))
                            .foregroundColor(.green)
                            .cornerRadius(6)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var taskDuration: TimeInterval? {
        if case .completed(_, let d) = task.status { return d }
        return nil
    }

    @ViewBuilder
    private func verificationBadge(_ status: VerificationStatus) -> some View {
        Text(status.rawValue)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(badgeBackgroundColor(status))
            .foregroundColor(badgeForegroundColor(status))
            .cornerRadius(6)
    }

    private func badgeBackgroundColor(_ status: VerificationStatus) -> Color {
        switch status {
        case .passed: return Color.green.opacity(0.15)
        case .visualLossless: return Color.blue.opacity(0.15)
        case .lossyConversion, .disqualified: return Color.orange.opacity(0.15)
        case .mismatch, .failed: return Color.red.opacity(0.15)
        case .verifying: return Color.orange.opacity(0.15)
        case .cannotVerify, .unverified: return Color.gray.opacity(0.15)
        }
    }

    private func badgeForegroundColor(_ status: VerificationStatus) -> Color {
        switch status {
        case .passed: return .green
        case .visualLossless: return .blue
        case .lossyConversion, .disqualified: return .orange
        case .mismatch, .failed: return .red
        case .verifying: return .orange
        case .cannotVerify, .unverified: return .secondary
        }
    }

    private func verificationColor(_ v: VerificationStatus) -> Color {
        badgeForegroundColor(v)
    }
}

// MARK: - Specification Column

struct SpecificationColumn: View {
    let title: String
    let subtitle: String
    let inspection: MediaInspectionResult?
    let accentColor: Color
    var outputUrls: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(accentColor).frame(width: 8, height: 8)
                Text(title).font(.headline)
            }
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Divider()

            if subtitle.lowercased().hasSuffix(".pdf") {
                // PDF 文件專用規格展示
                let url = URL(fileURLWithPath: subtitle)
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                let doc = PDFKit.PDFDocument(url: url)
                let pageCount = doc?.pageCount ?? 0
                let firstPageBox = doc?.page(at: 0)?.bounds(for: .mediaBox)

                specRow(label: "格式類型", value: "PDF 文件")
                specRow(label: "檔案大小", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                specRow(label: "文件頁數", value: "\(pageCount) 頁")
                if let box = firstPageBox {
                    specRow(label: "單頁尺寸 (點)", value: "\(Int(box.width)) × \(Int(box.height)) pt")
                }
                specRow(label: "渲染模式", value: "逐頁點陣化排版渲染（非數學無損）")
            } else if let insp = inspection {
                if insp.isImage {
                    // 圖片專用規格檢視（不套用影片專用欄位）
                    specRow(label: "圖片格式", value: insp.formatName.uppercased())
                    specRow(label: "檔案大小", value: ByteCountFormatter.string(fromByteCount: insp.fileSize, countStyle: .file))
                    specRow(label: "尺寸解析度", value: insp.videoResolution ?? "無")
                    specRow(label: "通道位深 (bpc)", value: insp.imageBitsPerComponent != nil ? "\(insp.imageBitsPerComponent!) bit/通道" : "未知")
                    specRow(label: "色彩空間 (ICC)", value: insp.imageColorSpace ?? "sRGB (標準)")
                    specRow(label: "Alpha 透明通道", value: insp.imageHasAlpha == true ? "有 (RGBA)" : "無")
                } else {
                    // 影音規格與多軌清單
                    specRow(label: "封裝容器", value: insp.formatName.uppercased())
                    specRow(label: "檔案大小", value: ByteCountFormatter.string(fromByteCount: insp.fileSize, countStyle: .file))
                    if let dur = insp.duration {
                        specRow(label: "總時長", value: String(format: "%.2f 秒", dur))
                    } else {
                        specRow(label: "總時長", value: "未知")
                    }
                    
                    Divider()
                    Text("逐軌串流清單 (共 \(insp.streams.count) 軌)").font(.caption.bold())
                    
                    if insp.streams.isEmpty {
                        Text("無探測到之媒體軌道").font(.caption2).foregroundColor(.secondary)
                    } else {
                        ForEach(insp.streams) { s in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("#\(s.index) [\(s.codecType.uppercased())]").font(.caption2.bold()).foregroundColor(.blue)
                                    Spacer()
                                    Text(s.codecName ?? "未知編碼").font(.caption2.monospaced()).bold()
                                }
                                if s.codecType == "video" {
                                    HStack {
                                        Text("格式/深度: \(s.pixelFormat ?? "未知") (\(s.bitDepth != nil ? "\(s.bitDepth!)bit" : "未知"))").font(.caption2).foregroundColor(.secondary)
                                        Spacer()
                                        Text("尺寸: \(s.resolution ?? "未知") @ \(s.frameRate ?? "未知")fps").font(.caption2).foregroundColor(.secondary)
                                    }
                                } else if s.codecType == "audio" {
                                    HStack {
                                        Text("聲道: \(s.channels != nil ? "\(s.channels!) 聲道 (\(s.channelLayout ?? "立體聲"))" : "未知")").font(.caption2).foregroundColor(.secondary)
                                        Spacer()
                                        Text("取樣: \(s.sampleRate != nil ? "\(s.sampleRate!) Hz" : "未知")").font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                if let lang = s.language, !lang.isEmpty {
                                    Text("語言: \(lang)").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            .padding(6)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(4)
                        }
                    }
                }
            } else {
                Text("尚未探測規格資訊 (規劃中)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            }

            if outputUrls.count > 1 {
                Divider()
                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.down.right.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("逐頁產出檔案列表 (共 \(outputUrls.count) 頁，無冗餘副本)").font(.caption.bold())
                }
                ForEach(outputUrls, id: \.self) { u in
                    HStack {
                        Image(systemName: "photo.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text(u.lastPathComponent)
                            .font(.caption2.monospaced())
                        Spacer()
                        if let sz = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int64) {
                            Text(ByteCountFormatter.string(fromByteCount: sz, countStyle: .file))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(3)
                    .background(Color.secondary.opacity(0.04))
                    .cornerRadius(4)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func specRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .bold()
        }
    }
}
