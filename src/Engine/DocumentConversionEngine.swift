import Foundation
import AppKit
import CoreText
import UniformTypeIdentifiers

public class DocumentConversionEngine {
    public static let shared = DocumentConversionEngine()

    public init() {}

    /// 執行文件格式轉換
    public func convertDocument(inputUrl: URL, outputUrl: URL) throws {
        // 嚴格來源保護 (檢查路徑與 inode)
        if FFmpegRunner.isSameFile(url1: inputUrl, url2: outputUrl) {
            throw NSError(
                domain: "DocumentConversionEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "嚴格安全保護：目標檔案與來源為相同檔案 (inode/路徑重疊)，禁止覆寫原檔！"]
            )
        }

        let inExt = inputUrl.pathExtension.lowercased()
        let outExt = outputUrl.pathExtension.lowercased()

        switch outExt {
        case "pdf":
            try exportToPDF(inputUrl: inputUrl, outputUrl: outputUrl, inExt: inExt)
        case "txt":
            try exportToPlainText(inputUrl: inputUrl, outputUrl: outputUrl, inExt: inExt)
        case "rtf":
            try exportToRTF(inputUrl: inputUrl, outputUrl: outputUrl, inExt: inExt)
        case "csv":
            try exportToCSV(inputUrl: inputUrl, outputUrl: outputUrl, inExt: inExt)
        default:
            throw NSError(
                domain: "DocumentConversionEngine",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "不支援的文件輸出格式: .\(outExt)，支援: .pdf, .txt, .rtf, .csv"]
            )
        }
    }

    // MARK: - Export to PDF

    private func exportToPDF(inputUrl: URL, outputUrl: URL, inExt: String) throws {
        // 1. 微軟 Word (.docx, .doc): 原廠高保真渲染 (Word -> Pages -> CoreText 備援)
        if ["docx", "doc"].contains(inExt) {
            if tryExportWordWithAppleScript(inputUrl: inputUrl, outputUrl: outputUrl) {
                return
            }
            if tryExportPagesWithAppleScript(inputUrl: inputUrl, outputUrl: outputUrl) {
                return
            }
            let attrString = try loadAttributedString(from: inputUrl, inExt: inExt)
            try renderAttributedStringToPDF(attr: attrString, outputUrl: outputUrl)
            return
        }

        // 2. 微軟 Excel (.xlsx, .xls): 原廠試算表渲染 (Excel -> Numbers -> Python 表格備援)
        if ["xlsx", "xls"].contains(inExt) {
            if tryExportExcelWithAppleScript(inputUrl: inputUrl, outputUrl: outputUrl) {
                return
            }
            if tryExportNumbersWithAppleScript(inputUrl: inputUrl, outputUrl: outputUrl) {
                return
            }
            try convertSpreadsheetToPDF(inputUrl: inputUrl, outputUrl: outputUrl)
            return
        }

        // 3. 微軟 PowerPoint (.pptx, .ppt): (PowerPoint -> Keynote)
        if ["pptx", "ppt"].contains(inExt) {
            if tryExportPowerPointWithAppleScript(inputUrl: inputUrl, outputUrl: outputUrl) {
                return
            }
            if tryExportKeynoteWithAppleScript(inputUrl: inputUrl, outputUrl: outputUrl) {
                return
            }
        }

        // 4. Apple iWork 原生格式 (.pages, .numbers, .key)
        if ["pages", "numbers", "key"].contains(inExt) {
            if tryExportWithAppleScript(inputUrl: inputUrl, outputUrl: outputUrl, inExt: inExt) {
                return
            }
        }

        // 5. 分隔符號表格 (.csv, .tsv)
        if ["csv", "tsv"].contains(inExt) {
            try convertDelimitedToPDF(inputUrl: inputUrl, outputUrl: outputUrl, isTsv: inExt == "tsv")
            return
        }

        // 6. RTF, HTML, TXT, Markdown 原生 CoreText 向量高解析排版轉 PDF (正向坐標)
        let attrString = try loadAttributedString(from: inputUrl, inExt: inExt)
        try renderAttributedStringToPDF(attr: attrString, outputUrl: outputUrl)
    }

    // MARK: - Export to Text / RTF / CSV

    private func exportToPlainText(inputUrl: URL, outputUrl: URL, inExt: String) throws {
        if ["xlsx", "xls", "csv", "tsv"].contains(inExt) {
            let tempTsv = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".tsv")
            defer { try? FileManager.default.removeItem(at: tempTsv) }
            try runSpreadsheetHelper(inputUrl: inputUrl, outputUrl: tempTsv, format: "tsv")
            let data = try Data(contentsOf: tempTsv)
            try data.write(to: outputUrl)
            return
        }

        let attrString = try loadAttributedString(from: inputUrl, inExt: inExt)
        guard let data = attrString.string.data(using: .utf8) else {
            throw NSError(domain: "DocumentConversionEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "無法編碼文字為 UTF-8"])
        }
        try data.write(to: outputUrl)
    }

    private func exportToRTF(inputUrl: URL, outputUrl: URL, inExt: String) throws {
        let attrString: NSAttributedString
        if ["xlsx", "xls", "csv", "tsv"].contains(inExt) {
            let tempHtml = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".html")
            defer { try? FileManager.default.removeItem(at: tempHtml) }
            try runSpreadsheetHelper(inputUrl: inputUrl, outputUrl: tempHtml, format: "html")
            attrString = try loadAttributedString(from: tempHtml, inExt: "html")
        } else {
            attrString = try loadAttributedString(from: inputUrl, inExt: inExt)
        }

        let rtfData = try attrString.data(
            from: NSRange(location: 0, length: attrString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        try rtfData.write(to: outputUrl)
    }

    private func exportToCSV(inputUrl: URL, outputUrl: URL, inExt: String) throws {
        if ["xlsx", "xls", "tsv", "csv"].contains(inExt) {
            try runSpreadsheetHelper(inputUrl: inputUrl, outputUrl: outputUrl, format: "csv")
        } else {
            throw NSError(
                domain: "DocumentConversionEngine",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "僅試算表或表格文件支援匯出為 CSV 格式"]
            )
        }
    }

    // MARK: - Spreadsheet & Tabular Processing

    private func convertSpreadsheetToPDF(inputUrl: URL, outputUrl: URL) throws {
        let tempHtml = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".html")
        defer { try? FileManager.default.removeItem(at: tempHtml) }

        try runSpreadsheetHelper(inputUrl: inputUrl, outputUrl: tempHtml, format: "html")
        let attr = try loadAttributedString(from: tempHtml, inExt: "html")
        try renderAttributedStringToPDF(attr: attr, outputUrl: outputUrl)
    }

    private func convertDelimitedToPDF(inputUrl: URL, outputUrl: URL, isTsv: Bool) throws {
        let tempHtml = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".html")
        defer { try? FileManager.default.removeItem(at: tempHtml) }

        try runSpreadsheetHelper(inputUrl: inputUrl, outputUrl: tempHtml, format: "html")
        let attr = try loadAttributedString(from: tempHtml, inExt: "html")
        try renderAttributedStringToPDF(attr: attr, outputUrl: outputUrl)
    }

    private func runSpreadsheetHelper(inputUrl: URL, outputUrl: URL, format: String) throws {
        let scriptPath = findScriptPath(name: "convert_spreadsheet.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            scriptPath,
            "--input", inputUrl.path,
            "--output", outputUrl.path,
            "--format", format
        ]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errStr = String(data: errData, encoding: .utf8) ?? "未知錯誤"
            throw NSError(
                domain: "DocumentConversionEngine",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "試算表解析轉換失敗: \(errStr.trimmingCharacters(in: .whitespacesAndNewlines))"]
            )
        }
    }

    // MARK: - CoreText Vector PDF Rendering (Correct Upright Coordinates)

    private func renderAttributedStringToPDF(attr: NSAttributedString, outputUrl: URL) throws {
        // 標準 A4 規格 (72 DPI: 595.2 x 841.8 pt)
        let pageWidth: CGFloat = 595.2
        let pageHeight: CGFloat = 841.8
        let margin: CGFloat = 45.0
        let contentRect = CGRect(x: margin, y: margin, width: pageWidth - margin * 2, height: pageHeight - margin * 2)

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let consumer = CGDataConsumer(url: outputUrl as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "DocumentConversionEngine", code: 10, userInfo: [NSLocalizedDescriptionKey: "無法建立 PDF 繪圖 Context"])
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attr as CFAttributedString)
        var textIndex = 0
        let totalLength = attr.length

        while textIndex < totalLength {
            context.beginPage(mediaBox: &mediaBox)
            let path = CGMutablePath()
            path.addRect(contentRect)

            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: textIndex, length: 0), path, nil)
            let frameRange = CTFrameGetVisibleStringRange(frame)
            if frameRange.length == 0 {
                context.endPage()
                break
            }

            // 正向坐標繪製：CGPDFContext 原生 (0,0) 位於左下角且 Y 朝上，CoreText 直接繪製即為正向文字
            // 絕不可做 translateBy(0, pageHeight) + scaleBy(1, -1)，否則會導致文字 180 度上下倒置！
            context.saveGState()
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
            context.restoreGState()

            context.endPage()
            textIndex += frameRange.length
        }

        context.closePDF()
    }

    // MARK: - Document Loading

    private func loadAttributedString(from url: URL, inExt: String) throws -> NSAttributedString {
        switch inExt {
        case "docx":
            return try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                documentAttributes: nil
            )
        case "doc":
            return try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.docFormat],
                documentAttributes: nil
            )
        case "rtf":
            return try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        case "rtfd":
            return try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.rtfd],
                documentAttributes: nil
            )
        case "html", "htm":
            let data = try Data(contentsOf: url)
            return try NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )
        case "md", "markdown":
            let raw = try String(contentsOf: url, encoding: .utf8)
            let styledHtml = markdownToHtml(raw)
            if let data = styledHtml.data(using: .utf8) {
                return (try? NSAttributedString(
                    data: data,
                    options: [
                        .documentType: NSAttributedString.DocumentType.html,
                        .characterEncoding: String.Encoding.utf8.rawValue
                    ],
                    documentAttributes: nil
                )) ?? NSAttributedString(string: raw)
            }
            return NSAttributedString(string: raw)
        default:
            let raw = try String(contentsOf: url, encoding: .utf8)
            let font = NSFont.systemFont(ofSize: 11)
            return NSAttributedString(string: raw, attributes: [.font: font, .foregroundColor: NSColor.textColor])
        }
    }

    private func markdownToHtml(_ md: String) -> String {
        var html = "<!DOCTYPE html><html><head><meta charset='utf-8'><style>"
        html += "body { font-family: -apple-system, sans-serif; margin: 30px; font-size: 13px; line-height: 1.6; color: #222; }"
        html += "h1, h2, h3 { color: #d35400; }"
        html += "pre, code { font-family: Menlo, monospace; background: #f4f4f4; padding: 2px 4px; border-radius: 3px; font-size: 12px; }"
        html += "blockquote { border-left: 3px solid #d35400; margin: 0; padding-left: 10px; color: #666; }"
        html += "</style></head><body>"

        let lines = md.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("# ") {
                html += "<h1>\(line.dropFirst(2))</h1>"
            } else if line.hasPrefix("## ") {
                html += "<h2>\(line.dropFirst(3))</h2>"
            } else if line.hasPrefix("### ") {
                html += "<h3>\(line.dropFirst(4))</h3>"
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                html += "<br/>"
            } else {
                html += "<p>\(line)</p>"
            }
        }
        html += "</body></html>"
        return html
    }

    // MARK: - Native Office & iWork AppleScript Automation

    /// 使用 Microsoft Word 原廠渲染匯出為 PDF (最高保真，完整保留相片、字型、邊距與表格)
    private func tryExportWordWithAppleScript(inputUrl: URL, outputUrl: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: "/Applications/Microsoft Word.app") else {
            return false
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let wordTmpDir = "\(home)/Library/Containers/com.microsoft.Word/Data/tmp"
        try? FileManager.default.createDirectory(atPath: wordTmpDir, withIntermediateDirectories: true)
        let tempPdfPath = "\(wordTmpDir)/lossless_word_\(UUID().uuidString).pdf"
        defer { try? FileManager.default.removeItem(atPath: tempPdfPath) }

        let script = """
        with timeout of 30 seconds
            tell application "Microsoft Word"
                open POSIX file "\(inputUrl.path)"
                set doc to active document
                save as doc file name "\(tempPdfPath)" file format format PDF
                close doc saving no
            end tell
        end timeout
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: tempPdfPath) {
            try? FileManager.default.removeItem(at: outputUrl)
            do {
                try FileManager.default.copyItem(atPath: tempPdfPath, toPath: outputUrl.path)
                return true
            } catch {
                return false
            }
        }
        return false
    }

    /// 使用 Apple Pages 原廠引擎匯出為 PDF (支援 docx, doc, pages，保真度極高)
    private func tryExportPagesWithAppleScript(inputUrl: URL, outputUrl: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: "/Applications/Pages.app") else {
            return false
        }

        let script = """
        with timeout of 30 seconds
            tell application "Pages"
                set doc to open POSIX file "\(inputUrl.path)"
                export doc to POSIX file "\(outputUrl.path)" as PDF
                close doc saving no
            end tell
        end timeout
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()

        return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputUrl.path)
    }

    /// 使用 Microsoft Excel 原廠渲染匯出為 PDF
    private func tryExportExcelWithAppleScript(inputUrl: URL, outputUrl: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: "/Applications/Microsoft Excel.app") else {
            return false
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let excelTmpDir = "\(home)/Library/Containers/com.microsoft.Excel/Data/tmp"
        try? FileManager.default.createDirectory(atPath: excelTmpDir, withIntermediateDirectories: true)
        let tempPdfPath = "\(excelTmpDir)/lossless_excel_\(UUID().uuidString).pdf"
        defer { try? FileManager.default.removeItem(atPath: tempPdfPath) }

        let script = """
        with timeout of 30 seconds
            tell application "Microsoft Excel"
                open POSIX file "\(inputUrl.path)"
                set wb to active workbook
                save workbook as wb filename "\(tempPdfPath)" file format PDF file format
                close wb saving no
            end tell
        end timeout
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: tempPdfPath) {
            try? FileManager.default.removeItem(at: outputUrl)
            do {
                try FileManager.default.copyItem(atPath: tempPdfPath, toPath: outputUrl.path)
                return true
            } catch {
                return false
            }
        }
        return false
    }

    /// 使用 Apple Numbers 原廠匯出為 PDF
    private func tryExportNumbersWithAppleScript(inputUrl: URL, outputUrl: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: "/Applications/Numbers.app") else {
            return false
        }

        let script = """
        with timeout of 30 seconds
            tell application "Numbers"
                set doc to open POSIX file "\(inputUrl.path)"
                export doc to POSIX file "\(outputUrl.path)" as PDF
                close doc saving no
            end tell
        end timeout
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()

        return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputUrl.path)
    }

    /// 使用 Microsoft PowerPoint 原廠匯出為 PDF
    private func tryExportPowerPointWithAppleScript(inputUrl: URL, outputUrl: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: "/Applications/Microsoft PowerPoint.app") else {
            return false
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let pptTmpDir = "\(home)/Library/Containers/com.microsoft.Powerpoint/Data/tmp"
        try? FileManager.default.createDirectory(atPath: pptTmpDir, withIntermediateDirectories: true)
        let tempPdfPath = "\(pptTmpDir)/lossless_ppt_\(UUID().uuidString).pdf"
        defer { try? FileManager.default.removeItem(atPath: tempPdfPath) }

        let script = """
        with timeout of 30 seconds
            tell application "Microsoft PowerPoint"
                open POSIX file "\(inputUrl.path)"
                set doc to active presentation
                save doc in POSIX file "\(tempPdfPath)" as save as PDF
                close doc saving no
            end tell
        end timeout
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: tempPdfPath) {
            try? FileManager.default.removeItem(at: outputUrl)
            do {
                try FileManager.default.copyItem(atPath: tempPdfPath, toPath: outputUrl.path)
                return true
            } catch {
                return false
            }
        }
        return false
    }

    /// 使用 Apple Keynote 原廠匯出為 PDF
    private func tryExportKeynoteWithAppleScript(inputUrl: URL, outputUrl: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: "/Applications/Keynote.app") else {
            return false
        }

        let script = """
        with timeout of 30 seconds
            tell application "Keynote"
                set doc to open POSIX file "\(inputUrl.path)"
                export doc to POSIX file "\(outputUrl.path)" as PDF
                close doc saving no
            end tell
        end timeout
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()

        return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputUrl.path)
    }

    /// 通用 iWork 匯出
    private func tryExportWithAppleScript(inputUrl: URL, outputUrl: URL, inExt: String) -> Bool {
        let appName = (inExt == "pages") ? "Pages" : (inExt == "numbers" ? "Numbers" : "Keynote")
        guard FileManager.default.fileExists(atPath: "/Applications/\(appName).app") else {
            return false
        }

        let script = """
        with timeout of 30 seconds
            tell application "\(appName)"
                set doc to open POSIX file "\(inputUrl.path)"
                export doc to POSIX file "\(outputUrl.path)" as PDF
                close doc saving no
            end tell
        end timeout
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputUrl.path)
    }

    private func findScriptPath(name: String) -> String {
        var candidates: [String] = []
        if let resPath = Bundle.main.resourcePath {
            candidates.append(resPath + "/" + name)
        }
        if let arg0 = CommandLine.arguments.first {
            let exeUrl = URL(fileURLWithPath: arg0)
            let base = exeUrl.deletingLastPathComponent().deletingLastPathComponent()
            candidates.append(base.appendingPathComponent("Resources/\(name)").path)
            candidates.append(base.appendingPathComponent("scripts/\(name)").path)
        }
        let fileUrl = URL(fileURLWithPath: #file)
        let repoRoot = fileUrl.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(repoRoot.appendingPathComponent("scripts/\(name)").path)

        for c in candidates where !c.isEmpty && FileManager.default.fileExists(atPath: c) {
            return c
        }
        return candidates.last ?? name
    }
}
