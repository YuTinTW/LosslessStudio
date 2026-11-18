import Foundation
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
let src = root.appendingPathComponent("source.png")
try Data("synthetic".utf8).write(to:src)
let out = root.appendingPathComponent("output.png")
func rejected(_ engine: ImageLosslessEngine, cancelled: @escaping () -> Bool = {false}) throws -> Error {
    do { try engine.convertImageLossless(inputUrl:src,outputUrl:out,isCancelled:cancelled); fatalError("unexpected success") }
    catch { assert(!fm.fileExists(atPath:out.path)); return error }
}
let missing = try rejected(ImageLosslessEngine(executable:nil))
assert(missing.localizedDescription.contains("ImageMagick")); print("PASS missing engine; no fallback/output")
let fake = root.appendingPathComponent("fake")
try "#!/bin/sh\nexec /bin/sleep 20\n".write(to:fake,atomically:true,encoding:.utf8)
try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:fake.path)
let start = Date()
let timeout = try rejected(ImageLosslessEngine(executable:fake,timeoutSeconds:0.2))
let timeoutMessage = CommandLine.arguments.contains("(en)") ? "timed out" : "逾時"
assert(timeout.localizedDescription.contains(timeoutMessage) && Date().timeIntervalSince(start)<4)
print("PASS timeout termination")
var polls = 0
let cancelled = try rejected(ImageLosslessEngine(executable:fake),cancelled:{polls += 1; return polls>4})
assert(cancelled is CancellationError); print("PASS running cancellation")
assert(try! Data(contentsOf:src) == Data("synthetic".utf8))
let remaining = try fm.contentsOfDirectory(atPath:root.path)
assert(!remaining.contains(where:{$0.hasPrefix(".lossless-image-")})); print("PASS source preserved and staging cleaned")
