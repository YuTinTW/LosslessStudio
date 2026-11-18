import SwiftUI
import AppKit
import PDFKit

public struct EncodingMonitorView: View {
    @ObservedObject var manager = ConversionManager.shared
    @State private var selectedTaskId: UUID?
    @State private var filterStatusIndex: Int = 0
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
                        Text(L10n.text("編碼即時監控與前後規格對照", "Encoding Monitor & Specification Comparison"))
                            .font(.title2.bold())
                            .foregroundColor(.primary)
                    }
                    Text(L10n.text("逐檔即時比對來源與輸出之真實探測資訊，嚴格驗證串流直通 (-c copy) 與數學無損一致性，絕不偷偷改變編碼", "Real-time probe comparison of source and output files; strictly verifies stream copy (-c copy) and mathematical lossless integrity without stealth re-encoding"))
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
                    Label(L10n.text("匯出驗證報告", "Export Report"), systemImage: "square.and.arrow.up")
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
                        Text(L10n.text("工作佇列 (\(manager.tasks.count))", "Tasks Queue (\(manager.tasks.count))"))
                            .font(.headline)
                        Spacer()
                        Picker("", selection: $filterStatusIndex) {
                            Text(L10n.text("全部", "All")).tag(0)
                            Text(L10n.text("已完成", "Completed")).tag(1)
                            Text(L10n.text("未通過/失敗", "Failed / Warnings")).tag(2)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
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
                            Text(L10n.text("尚無轉檔任務", "No Conversion Tasks"))
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(L10n.text("加入檔案或資料夾後，即可在此即時監控輸入與輸出之編碼參數對照", "Import files or folders to monitor real-time codec and parameter comparisons"))
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
        .frame(minWidth: 920, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var filteredTasks: [ConversionTaskItem] {
        switch filterStatusIndex {
        case 1:
            return manager.tasks.filter { if case .completed = $0.status { return true }; return false }
        case 2:
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
                Text(task.category.isBitstreamCopy ? L10n.text("串流直通", "Stream Copy") : (task.category == .document ? L10n.text("排版渲染", "Page Raster") : L10n.text("重編碼", "Re-encode")))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(task.category.isBitstreamCopy ? Color.green.opacity(0.15) : (task.category == .document ? Color.indigo.opacity(0.15) : Color.orange.opacity(0.15)))
                    .foregroundColor(task.category.isBitstreamCopy ? .green : (task.category == .document ? .indigo : .orange))
                    .cornerRadius(4)

                Spacer()

                if let cmp = task.comparison {
                    Text(cmp.verificationStatus.displayText)
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
            Text(L10n.text("等待", "Pending")).font(.caption2).foregroundColor(.secondary)
        case .inspecting:
            Text(L10n.text("探測中", "Inspecting")).font(.caption2).foregroundColor(.blue)
        case .processing(let p, _, _):
            Text("\(Int(p * 100))%").font(.caption2).foregroundColor(.orange)
        case .completed:
            if let cmp = task.comparison, cmp.verificationStatus == .disqualified {
                Text(L10n.text("完成(警告)", "Done (Warn)")).font(.caption2.bold()).foregroundColor(.orange)
            } else if let cmp = task.comparison, cmp.verificationStatus == .cannotVerify {
                Text(L10n.text("完成(未比對)", "Done (Unchecked)")).font(.caption2.bold()).foregroundColor(.secondary)
            } else {
                Text(L10n.text("完成", "Done")).font(.caption2).foregroundColor(.green)
            }
        case .rejected:
            Text(L10n.text("拒絕", "Rejected")).font(.caption2).foregroundColor(.red)
        case .failed:
            Text(L10n.text("失敗", "Failed")).font(.caption2).foregroundColor(.red)
        case .cancelled:
            Text(L10n.text("取消", "Cancelled")).font(.caption2).foregroundColor(.secondary)
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
                        Label(task.category == .document ? L10n.text("排版渲染輸出 (非數學無損)", "Page Rasterization (Non-lossless)") : task.category.displayName, systemImage: task.category.isBitstreamCopy ? "arrow.right.arrow.left" : (task.category == .document ? "doc.on.doc" : "gearshape.2"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let duration = taskDuration {
                            Label(L10n.text("耗時 \(String(format: "%.2f", duration))s", "Elapsed: \(String(format: "%.2f", duration))s"), systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Side-by-Side Comparison Grid
                Text(L10n.text("實際輸入與輸出規格並排對照 (真實 Probe 資料)", "Side-by-Side Input & Output Specifications (Real Probe Data)"))
                    .font(.headline)
                    .foregroundColor(.primary)

                HStack(alignment: .top, spacing: 16) {
                    // Left Column: Input
                    SpecificationColumn(
                        title: L10n.text("來源檔案 (Input)", "Source File (Input)"),
                        subtitle: task.inputUrl.path,
                        inspection: task.comparison?.inputInspection,
                        accentColor: .blue
                    )

                    // Right Column: Output
                    SpecificationColumn(
                        title: L10n.text("輸出產物 (Output)", "Output Artifact (Output)"),
                        subtitle: task.outputUrls.count > 1 ? L10n.text("\(task.outputUrls.first?.path ?? "") 等共 \(task.outputUrls.count) 頁", "\(task.outputUrls.first?.path ?? "") and \(task.outputUrls.count) pages total") : (task.comparison?.outputUrl?.path ?? L10n.text("尚未完成產出", "Output pending completion")),
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
                            Text(L10n.text("無損一致性驗證結果：\(cmp.verificationStatus.displayText)", "Lossless Verification Result: \(cmp.verificationStatus.displayText)"))
                                .font(.headline)
                        }
                        Text(cmp.verificationNote)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if !cmp.qualificationReasons.isEmpty {
                            Divider()
                            Text(L10n.text("未符無損之具體原因與差異細節：", "Disqualified Reasons & Discrepancy Details:"))
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
                                Text(L10n.text("來源位元/像素 Hash:", "Source Bit/Pixel Hash:"))
                                    .font(.caption.bold())
                                Text(ih)
                                    .font(.caption.monospaced())
                            }
                            HStack {
                                Text(L10n.text("輸出位元/像素 Hash:", "Output Bit/Pixel Hash:"))
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
                            Text(L10n.text("底層執行參數 (透明可查)", "Underlying Execution Parameters (Auditable)"))
                                .font(.headline)
                            Spacer()
                            Button(L10n.text("複製指令", "Copy Command")) {
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
        Text(status.displayText)
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

                specRow(label: L10n.text("格式類型", "Format"), value: L10n.text("PDF 文件", "PDF Document"))
                specRow(label: L10n.text("檔案大小", "File Size"), value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                specRow(label: L10n.text("文件頁數", "Page Count"), value: L10n.text("\(pageCount) 頁", "\(pageCount) pages"))
                if let box = firstPageBox {
                    specRow(label: L10n.text("單頁尺寸 (點)", "Page Size (pt)"), value: "\(Int(box.width)) × \(Int(box.height)) pt")
                }
                specRow(label: L10n.text("渲染模式", "Render Mode"), value: L10n.text("逐頁點陣化排版渲染（非數學無損）", "Page-by-page Rasterization (Non-lossless)"))
            } else if let insp = inspection {
                if insp.isImage {
                    // 圖片專用規格檢視（不套用影片專用欄位）
                    specRow(label: L10n.text("圖片格式", "Image Format"), value: insp.formatName.uppercased())
                    specRow(label: L10n.text("檔案大小", "File Size"), value: ByteCountFormatter.string(fromByteCount: insp.fileSize, countStyle: .file))
                    specRow(label: L10n.text("尺寸解析度", "Resolution"), value: insp.videoResolution ?? L10n.text("無", "None"))
                    specRow(label: L10n.text("通道位深 (bpc)", "Bit Depth (bpc)"), value: insp.imageBitsPerComponent != nil ? L10n.text("\(insp.imageBitsPerComponent!) bit/通道", "\(insp.imageBitsPerComponent!) bpc") : L10n.text("未知", "Unknown"))
                    specRow(label: L10n.text("色彩空間 (ICC)", "Color Space (ICC)"), value: insp.imageColorSpace ?? L10n.text("sRGB (標準)", "sRGB (Standard)"))
                    specRow(label: L10n.text("Alpha 透明通道", "Alpha Channel"), value: insp.imageHasAlpha == true ? L10n.text("有 (RGBA)", "Yes (RGBA)") : L10n.text("無", "No"))
                } else {
                    // 影音規格與多軌清單
                    specRow(label: L10n.text("封裝容器", "Container"), value: insp.formatName.uppercased())
                    specRow(label: L10n.text("檔案大小", "File Size"), value: ByteCountFormatter.string(fromByteCount: insp.fileSize, countStyle: .file))
                    if let dur = insp.duration {
                        specRow(label: L10n.text("總時長", "Duration"), value: String(format: L10n.text("%.2f 秒", "%.2f s"), dur))
                    } else {
                        specRow(label: L10n.text("總時長", "Duration"), value: L10n.text("未知", "Unknown"))
                    }
                    
                    Divider()
                    Text(L10n.text("逐軌串流清單 (共 \(insp.streams.count) 軌)", "Track Streams (\(insp.streams.count) tracks)")).font(.caption.bold())
                    
                    if insp.streams.isEmpty {
                        Text(L10n.text("無探測到之媒體軌道", "No Media Tracks Detected")).font(.caption2).foregroundColor(.secondary)
                    } else {
                        ForEach(insp.streams) { s in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("#\(s.index) [\(s.codecType.uppercased())]").font(.caption2.bold()).foregroundColor(.blue)
                                    Spacer()
                                    Text(s.codecName ?? L10n.text("未知編碼", "Unknown Codec")).font(.caption2.monospaced()).bold()
                                }
                                if s.codecType == "video" {
                                    HStack {
                                        Text(L10n.text("格式/深度: \(s.pixelFormat ?? "未知") (\(s.bitDepth != nil ? "\(s.bitDepth!)bit" : "未知"))", "Format/Depth: \(s.pixelFormat ?? "Unknown") (\(s.bitDepth != nil ? "\(s.bitDepth!)bit" : "Unknown"))")).font(.caption2).foregroundColor(.secondary)
                                        Spacer()
                                        Text(L10n.text("尺寸: \(s.resolution ?? "未知") @ \(s.frameRate ?? "未知")fps", "Size: \(s.resolution ?? "Unknown") @ \(s.frameRate ?? "Unknown")fps")).font(.caption2).foregroundColor(.secondary)
                                    }
                                } else if s.codecType == "audio" {
                                    HStack {
                                        Text(L10n.text("聲道: \(s.channels != nil ? "\(s.channels!) 聲道 (\(s.channelLayout ?? "立體聲"))" : "未知")", "Channels: \(s.channels != nil ? "\(s.channels!) ch (\(s.channelLayout ?? "Stereo"))" : "Unknown")")).font(.caption2).foregroundColor(.secondary)
                                        Spacer()
                                        Text(L10n.text("取樣: \(s.sampleRate != nil ? "\(s.sampleRate!) Hz" : "未知")", "Sample: \(s.sampleRate != nil ? "\(s.sampleRate!) Hz" : "Unknown")")).font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                if let lang = s.language, !lang.isEmpty {
                                    Text(L10n.text("語言: \(lang)", "Language: \(lang)")).font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            .padding(6)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(4)
                        }
                    }
                }
            } else {
                Text(L10n.text("尚未探測規格資訊 (規劃中)", "Specification inspection pending (scheduled)"))
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
                    Text(L10n.text("逐頁產出檔案列表 (共 \(outputUrls.count) 頁，無冗餘副本)", "Page Output Files List (\(outputUrls.count) pages, no duplicate first page)")).font(.caption.bold())
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
