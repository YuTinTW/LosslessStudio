import Foundation
import CoreGraphics
class FFmpegRunner {
 static func isSameFile(url1: URL, url2: URL) -> Bool { url1.standardizedFileURL == url2.standardizedFileURL }
}
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
let src = root.appendingPathComponent("input.docx")
try Data("test".utf8).write(to: src)
let fixture = root.appendingPathComponent("fixture.pdf")
var box = CGRect(x:0,y:0,width:100,height:100)
let ctx = CGContext(fixture as CFURL, mediaBox:&box,nil)!
ctx.beginPDFPage(nil); ctx.endPDFPage(); ctx.closePDF()
let fake = root.appendingPathComponent("fake")
func script(_ text: String) throws {
 try text.write(to:fake,atomically:true,encoding:.utf8)
 try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:fake.path)
}
try script("#!/bin/sh\nfor arg in \"$@\"; do if [ \"$prev\" = '--outdir' ]; then dest=\"$arg\"; fi; prev=\"$arg\"; done\ncp \"${0%/*}/fixture.pdf\" \"$dest/input.pdf\"\n")
let engine = DocumentConversionEngine(libreOfficeExecutable:fake,timeoutSeconds:3)
let out = root.appendingPathComponent("out.pdf")
try engine.convertDocument(inputUrl:src,outputUrl:out)
assert(fm.fileExists(atPath:out.path)); print("PASS mock valid PDF publication")
let original = try Data(contentsOf:out)
do { try engine.convertDocument(inputUrl:src,outputUrl:out); fatalError("overwrote") } catch {}
let after = try Data(contentsOf:out); assert(after == original); print("PASS existing output preserved")
try script("#!/bin/sh\nexit 0\n")
do { try engine.convertDocument(inputUrl:src,outputUrl:root.appendingPathComponent("bad.pdf")); fatalError("accepted invalid PDF") } catch {}
print("PASS zero-exit missing PDF rejected")
try script("#!/bin/sh\nexec /bin/sleep 20\n")
let timeoutEngine = DocumentConversionEngine(libreOfficeExecutable:fake,timeoutSeconds:0.2)
let start = Date()
do { try timeoutEngine.convertDocument(inputUrl:src,outputUrl:root.appendingPathComponent("timeout.pdf")); fatalError("no timeout") } catch {}
assert(Date().timeIntervalSince(start)<4); print("PASS process timeout")
var polls = 0
do { try engine.convertDocument(inputUrl:src,outputUrl:root.appendingPathComponent("cancel.pdf"),isCancelled:{ polls += 1; return polls > 4 }); fatalError("no cancel") } catch is CancellationError { print("PASS running process cancellation") }
let remaining = try fm.contentsOfDirectory(atPath:root.path); assert(!remaining.contains(where:{$0.hasPrefix(".losslessstudio-")})); print("PASS temporary cleanup")
