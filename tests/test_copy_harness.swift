import Foundation
import Darwin

// ─────────────────────────────────────────────────────────────────
// test_copy_harness.swift
// 專門測試 Production PDFConversionEngine.copyFileExclusively 輔助函式
// 包含中途取消、外部替換身分免疫、ENOSPC 磁碟滿、EEXIST 碰撞防覆寫與來源開啟失敗
// ─────────────────────────────────────────────────────────────────

@main
struct CopyHarnessMain {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            fputs("Usage: test_copy_harness <test_name> [args...]\n", stderr)
            exit(1)
        }

        let testName = args[1]

        switch testName {
        case "normal":
            guard args.count >= 4 else { exit(2) }
            let staged = URL(fileURLWithPath: args[2])
            let target = URL(fileURLWithPath: args[3])
            let (dev, ino, err) = PDFConversionEngine.copyFileExclusively(from: staged, to: target)
            if let e = err {
                print("ERROR: \(e)")
                exit(10)
            } else {
                print("SUCCESS dev=\(dev) ino=\(ino)")
                exit(0)
            }

        case "collision":
            guard args.count >= 4 else { exit(2) }
            let staged = URL(fileURLWithPath: args[2])
            let target = URL(fileURLWithPath: args[3])
            let (_, _, err) = PDFConversionEngine.copyFileExclusively(from: staged, to: target)
            if let e = err {
                print("ERROR: \(e)")
                exit(e == EEXIST ? 0 : 11)
            } else {
                print("UNEXPECTED_SUCCESS")
                exit(12)
            }

        case "cancel_mid_write":
            guard args.count >= 4 else { exit(2) }
            let staged = URL(fileURLWithPath: args[2])
            let target = URL(fileURLWithPath: args[3])
            var writeCallCount = 0
            let (_, _, err) = PDFConversionEngine.copyFileExclusively(
                from: staged,
                to: target,
                isCancelled: {
                    writeCallCount += 1
                    // 第一次檢查允許通過（進入寫入），第 4 次在第一個區塊寫入後觸發取消
                    if writeCallCount >= 4 {
                        return true
                    }
                    return false
                }
            )
            guard let e = err, e == ECANCELED else {
                fputs("Expected ECANCELED (89), got \(String(describing: err))\n", stderr)
                exit(13)
            }
            // 驗證目標檔案已遭 safeCleanup 徹底清除
            if FileManager.default.fileExists(atPath: target.path) {
                fputs("Target file still exists after mid-write cancellation!\n", stderr)
                exit(14)
            }
            print("CANCEL_MID_WRITE_PASS")
            exit(0)

        case "replacement_during_write":
            guard args.count >= 4 else { exit(2) }
            let staged = URL(fileURLWithPath: args[2])
            let target = URL(fileURLWithPath: args[3])
            var writeCallCount = 0
            let (_, _, err) = PDFConversionEngine.copyFileExclusively(
                from: staged,
                to: target,
                isCancelled: {
                    writeCallCount += 1
                    if writeCallCount >= 4 {
                        // 在寫入中途、targetFd 仍開啟時，模擬外力進程強行 unlink target 並置換為新檔案
                        unlink(target.path)
                        try? "EXTERNAL_ATTACKER_REPLACEMENT_PAYLOAD".write(to: target, atomically: false, encoding: .utf8)
                        // 接著觸發中途失敗取消，促使 safeCleanup 執行核實清理
                        return true
                    }
                    return false
                }
            )
            guard let e = err, e == ECANCELED else {
                fputs("Expected ECANCELED (89), got \(String(describing: err))\n", stderr)
                exit(15)
            }
            // 關鍵核實：safeCleanup 應比對 Inode 發現目標已遭替換，絕對不可刪除該替換檔案！
            guard FileManager.default.fileExists(atPath: target.path) else {
                fputs("FATAL: External replaced file was incorrectly deleted by safeCleanup!\n", stderr)
                exit(16)
            }
            let survivor = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
            guard survivor == "EXTERNAL_ATTACKER_REPLACEMENT_PAYLOAD" else {
                fputs("FATAL: Replaced file content corrupted: \(survivor)\n", stderr)
                exit(17)
            }
            print("REPLACEMENT_IMMUNITY_PASS")
            exit(0)

        case "source_missing":
            guard args.count >= 4 else { exit(2) }
            let staged = URL(fileURLWithPath: args[2])
            let target = URL(fileURLWithPath: args[3])
            let (_, _, err) = PDFConversionEngine.copyFileExclusively(from: staged, to: target)
            guard let e = err, e == ENOENT else {
                fputs("Expected ENOENT (2), got \(String(describing: err))\n", stderr)
                exit(18)
            }
            if FileManager.default.fileExists(atPath: target.path) {
                fputs("Target still exists after source open failure!\n", stderr)
                exit(19)
            }
            print("SOURCE_MISSING_PASS")
            exit(0)

        case "enospc":
            guard args.count >= 4 else { exit(2) }
            let staged = URL(fileURLWithPath: args[2])
            let target = URL(fileURLWithPath: args[3])
            if FileManager.default.fileExists(atPath: target.path) {
                try? FileManager.default.removeItem(at: target)
            }
            let (_, _, err) = PDFConversionEngine.copyFileExclusively(from: staged, to: target)
            guard let e = err, e == ENOSPC else {
                fputs("Expected ENOSPC (28), got \(String(describing: err))\n", stderr)
                exit(20)
            }
            if FileManager.default.fileExists(atPath: target.path) {
                fputs("Target still exists after ENOSPC failure!\n", stderr)
                exit(21)
            }
            print("ENOSPC_PASS")
            exit(0)

        default:
            fputs("Unknown test name: \(testName)\n", stderr)
            exit(99)
        }
    }
}
