import Foundation
import CoreGraphics

let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }

let fakeEncoder = root.appendingPathComponent("magick")
try "#!/bin/sh\nexit 1\n".write(to: fakeEncoder, atomically: true, encoding: .utf8)
try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeEncoder.path)
setenv("MAGICK_EXECUTABLE", fakeEncoder.path, 1)
let engine = PDFConversionEngine()
let source = root.appendingPathComponent("source.pdf")
let output = root.appendingPathComponent("output.png")
let english = CommandLine.arguments.contains("(en)")

func checkFailure(_ expected: String, outputUrl: URL = output, format: String = "png") throws {
    do {
        _ = try engine.convertPDFToImages(inputUrl: source, outputUrl: outputUrl, targetFormat: format)
        fatalError("Accepted invalid PDF job")
    } catch {
        assert(error.localizedDescription.contains(expected), error.localizedDescription)
        assert(!fm.fileExists(atPath: output.path))
    }
}

try checkFailure(english ? "does not exist" : "不存在")
try Data().write(to: source)
try checkFailure(english ? "empty (0 bytes)" : "空檔案")
try checkFailure(english ? "refer to the same file" : "相同檔案", outputUrl: source)

var page = CGRect(x: 0, y: 0, width: 100, height: 100)
let pdf = CGContext(source as CFURL, mediaBox: &page, nil)!
pdf.beginPDFPage(nil)
pdf.endPDFPage()
pdf.closePDF()
let before = try Data(contentsOf: source)
try checkFailure(english ? "Unsupported PDF output format" : "不支援的 PDF 輸出圖片格式", format: "invalid")
try checkFailure(english ? "failed to encode" : "編碼失敗")
let after = try Data(contentsOf: source)
assert(after == before)
let entries = try fm.contentsOfDirectory(atPath: root.path).sorted()
assert(entries == ["magick", "source.pdf"])
print("PASS PDF validation, localized messages, source preservation, and cleanup")
