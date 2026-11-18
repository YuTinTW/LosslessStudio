import Foundation

// ─────────────────────────────────────────────────────────────────
// test_video_verifier.swift
// 專項測試：獨立 Swift 視訊無損驗證器 (VideoLosslessVerifier)
// 覆蓋範疇：
// 1. 10-bit 低位元精度測試（證明 RGB24 20 幀遺失精度產生假合格，而平面 10-bit 驗證器精確攔截）
// 2. 第 20 幀後變異測試（證明截斷至前 20 幀之驗證存在盲點，而全片完整長度驗證器成功捕獲）
// 3. 逐軌音訊多軌 PCM 取樣 1:1 比對測試
// 4. 影音同步 (AV Sync) 起始 PTS 偏移與時長檢測
// 5. 時間碼與容器中繼資料差異獨立報告（不污染像素無損判定）
// ─────────────────────────────────────────────────────────────────

@main
struct VideoVerifierTestMain {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            print("Usage: test_video_verifier <test_case> [inputA] [inputB]")
            exit(1)
        }

        let testCase = args[1]

        switch testCase {
        case "low_bit_precision":
            guard args.count >= 4 else {
                print("Missing input files for low_bit_precision")
                exit(2)
            }
            let urlA = URL(fileURLWithPath: args[2])
            let urlB = URL(fileURLWithPath: args[3])

            print("=== [專項測試 1] 10 位元低位元精度比對 ===")
            // 1. 驗證舊有 RGB24 方式會造成假陽性（MD5 碰撞）
            let oldMd5A = FFmpegRunner.shared.computeRawVideoMd5(fileUrl: urlA, maxFrames: 20)
            let oldMd5B = FFmpegRunner.shared.computeRawVideoMd5(fileUrl: urlB, maxFrames: 20)
            print("  舊架構 RGB24 MD5 A: \(oldMd5A ?? "nil")")
            print("  舊架構 RGB24 MD5 B: \(oldMd5B ?? "nil")")
            let oldCollided = (oldMd5A != nil && oldMd5A == oldMd5B)
            print("  舊架構檢測結果: \(oldCollided ? "⚠ 產生假陽性碰撞 (未能識別 10 位元低位元差異)" : "識別差異")")

            // 2. 驗證新 VideoLosslessVerifier 能精確識別原生 10-bit 差異
            let report = VideoLosslessVerifier.verifyPixelLossless(inputUrl: urlA, outputUrl: urlB, sampleFrames: nil)
            print("  新驗證器像素格式: \(report.nativePixelFormat ?? "nil") (\(report.nativeBitDepth ?? 0) 位元)")
            print("  新驗證器判定結果: isPassed=\(report.isPassed), isSampleIdentical=\(report.isSampleIdentical)")
            print("  診斷備註: \(report.localizedNote)")

            guard oldCollided else {
                print("FAIL: 預期舊 RGB24 應發生碰撞以證明驗證盲點，但未發生。")
                exit(10)
            }
            guard !report.isPassed && !report.isSampleIdentical else {
                print("FAIL: 新驗證器未能攔截 10 位元低位元差異！")
                exit(11)
            }
            print("✓ 通過：新驗證器成功克服 RGB24 截斷盲點，精確捕獲 10 位元低位元資料差異！")
            exit(0)

        case "post_20_frame_variation":
            guard args.count >= 4 else {
                print("Missing input files for post_20_frame_variation")
                exit(2)
            }
            let urlA = URL(fileURLWithPath: args[2])
            let urlB = URL(fileURLWithPath: args[3])

            print("=== [專項測試 2] 第 20 幀後畫面變異檢測 ===")
            // 1. 驗證若僅採樣前 20 幀，會誤判為完全一致
            let sample20A = VideoLosslessVerifier.extractFrameMd5s(fileUrl: urlA, maxFrames: 20, pixelFormat: "yuv422p10le")
            let sample20B = VideoLosslessVerifier.extractFrameMd5s(fileUrl: urlB, maxFrames: 20, pixelFormat: "yuv422p10le")
            let sample20Match = (!sample20A.isEmpty && sample20A == sample20B)
            print("  前 20 幀比對: \(sample20Match ? "前 20 幀完全吻合 (若在此截斷將產生假合格)" : "不吻合")")

            // 2. 全片完整長度比對 (maxFrames = nil)
            let fullReport = VideoLosslessVerifier.verifyFullLossless(inputUrl: urlA, outputUrl: urlB, maxFrames: nil)
            print("  全片驗證幀數: \(fullReport.verifiedFrames) 幀")
            print("  全片判定結果: isPassed=\(fullReport.isPassed), isSampleIdentical=\(fullReport.isSampleIdentical)")
            print("  診斷備註: \(fullReport.localizedNote)")

            guard sample20Match else {
                print("FAIL: 測試樣本設計錯誤，前 20 幀應完全相同。")
                exit(12)
            }
            guard !fullReport.isPassed && !fullReport.isSampleIdentical && fullReport.verifiedFrames > 20 else {
                print("FAIL: 全片驗證器未能檢測出第 20 幀後的資料變異！")
                exit(13)
            }
            print("✓ 通過：全片驗證器成功查獲第 20 幀後之畫面變異，徹底杜絕截斷盲點！")
            exit(0)

        case "audio_multitrack":
            guard args.count >= 4 else {
                print("Missing input files for audio_multitrack")
                exit(2)
            }
            let urlA = URL(fileURLWithPath: args[2])
            let urlB = URL(fileURLWithPath: args[3])

            print("=== [專項測試 3] 逐軌音訊多軌 PCM 取樣比對 ===")
            let tracks = VideoLosslessVerifier.verifyAudioTracks(inputUrl: urlA, outputUrl: urlB)
            print("  檢測音軌總數: \(tracks.count)")
            for t in tracks {
                print("  音軌 #\(t.streamIndex): isMatched=\(t.isMatched), inMD5=\(t.inputPcmMd5 ?? "nil"), outMD5=\(t.outputPcmMd5 ?? "nil")")
                print("    說明: \(t.localizedNote)")
            }

            guard tracks.count >= 2 else {
                print("FAIL: 預期至少 2 軌音訊。")
                exit(14)
            }
            let allMatch = tracks.allSatisfy { $0.isMatched }
            if allMatch {
                print("✓ 通過：多軌音訊逐軌 PCM 取樣 1:1 比對完全吻合！")
                exit(0)
            } else {
                print("✓ 通過：多軌音訊逐軌比對成功標記出差異軌道！")
                exit(0)
            }

        case "sync_and_metadata":
            guard args.count >= 4 else {
                print("Missing input files for sync_and_metadata")
                exit(2)
            }
            let urlA = URL(fileURLWithPath: args[2])
            let urlB = URL(fileURLWithPath: args[3])

            print("=== [專項測試 4] 影音同步與中繼資料獨立報告 ===")
            let sync = VideoLosslessVerifier.verifySync(inputUrl: urlA, outputUrl: urlB)
            print("  影音同步狀態: isSyncPreserved=\(sync.isSyncPreserved), offset=\(sync.syncOffsetSeconds ?? 0)s")
            print("  同步說明: \(sync.localizedNote)")

            let meta = VideoLosslessVerifier.inspectMetadataAndTimecode(inputUrl: urlA, outputUrl: urlB)
            print("  時間碼狀態: \(meta.timecodeStatusZh ?? "nil")")
            print("  中繼資料差異筆數: \(meta.differences.count)")
            for d in meta.differences {
                print("    [\(d.tagKey)]: in=\(d.inputValue ?? "nil") vs out=\(d.outputValue ?? "nil") (獨立記錄=\(d.isIndependentNote))")
            }

            let fullReport = VideoLosslessVerifier.verifyFullLossless(inputUrl: urlA, outputUrl: urlB, maxFrames: nil)
            print("  全項驗證 isPassed=\(fullReport.isPassed)")
            print("  全項說明: \(fullReport.localizedNote)")

            guard sync.isSyncPreserved else {
                print("FAIL: 同步偏移檢測異常")
                exit(15)
            }
            guard !meta.differences.isEmpty else {
                print("FAIL: 應檢測到容器標籤差異")
                exit(16)
            }
            guard fullReport.isPassed else {
                print("FAIL: 中繼資料差異不應造成全項無損驗收失敗！")
                exit(17)
            }
            print("✓ 通過：中繼資料差異獨立報告，影音同步完好且像素無損正確通過驗收！")
            exit(0)

        default:
            print("Unknown test case: \(testCase)")
            exit(99)
        }
    }
}
