#!/usr/bin/env python3
import os
import sys
import subprocess
import shutil

TEST_DIR = "/tmp/lossless_verifier_tests"
PROJECT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
HARNESS_BIN = "/tmp/test_video_verifier_bin"

def run_cmd(cmd, check=True):
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if check and res.returncode != 0:
        print(f"Command failed (code {res.returncode}): {' '.join(cmd)}")
        print("STDOUT:", res.stdout)
        print("STDERR:", res.stderr)
        sys.exit(res.returncode)
    return res

def setup():
    if os.path.exists(TEST_DIR):
        shutil.rmtree(TEST_DIR)
    os.makedirs(TEST_DIR, exist_ok=True)

    print("==> 編譯 test_video_verifier 測試主程式...")
    swift_files = [
        os.path.join(PROJECT_DIR, "src/L10n.swift"),
        os.path.join(PROJECT_DIR, "src/Engine/Types.swift"),
        os.path.join(PROJECT_DIR, "src/Engine/Limitations.swift"),
        os.path.join(PROJECT_DIR, "src/Engine/FFmpegRunner.swift"),
        os.path.join(PROJECT_DIR, "src/Engine/VideoLosslessVerifier.swift"),
        os.path.join(PROJECT_DIR, "tests/test_video_verifier.swift"),
    ]
    compile_cmd = ["swiftc", "-target", "arm64-apple-macos14.0", "-O"] + swift_files + ["-o", HARNESS_BIN]
    run_cmd(compile_cmd)
    print("✓ 編譯完成。")

def test_10bit_low_bit():
    print("\n--- [專項測試 1] 10 位元低位元精度測試 (Y=512 vs Y=513) ---")
    file_512 = os.path.join(TEST_DIR, "frame_512.yuv")
    file_513 = os.path.join(TEST_DIR, "frame_513.yuv")
    
    # 320x240 yuv422p10le: Y=320*240 (153600B), U=160*240 (76800B), V=160*240 (76800B)
    with open(file_512, "wb") as f:
        f.write((512).to_bytes(2, "little") * (320 * 240))
        f.write((512).to_bytes(2, "little") * (160 * 240))
        f.write((512).to_bytes(2, "little") * (160 * 240))

    with open(file_513, "wb") as f:
        f.write((513).to_bytes(2, "little") * (320 * 240))
        f.write((512).to_bytes(2, "little") * (160 * 240))
        f.write((512).to_bytes(2, "little") * (160 * 240))

    mkv_512 = os.path.join(TEST_DIR, "clip_512.mkv")
    mkv_513 = os.path.join(TEST_DIR, "clip_513.mkv")

    run_cmd(["ffmpeg", "-v", "quiet", "-y", "-f", "rawvideo", "-pix_fmt", "yuv422p10le", "-s", "320x240", "-i", file_512, "-c:v", "ffv1", mkv_512])
    run_cmd(["ffmpeg", "-v", "quiet", "-y", "-f", "rawvideo", "-pix_fmt", "yuv422p10le", "-s", "320x240", "-i", file_513, "-c:v", "ffv1", mkv_513])

    res = run_cmd([HARNESS_BIN, "low_bit_precision", mkv_512, mkv_513])
    print(res.stdout.strip())

def test_post_20_frame():
    print("\n--- [專項測試 2] 第 20 幀後資料變異測試 (25 幀中前 20 幀相同，後 5 幀突變) ---")
    file_512 = os.path.join(TEST_DIR, "frame_512.yuv")
    file_513 = os.path.join(TEST_DIR, "frame_513.yuv")

    with open(file_512, "rb") as f:
        d512 = f.read()
    with open(file_513, "rb") as f:
        d513 = f.read()

    vid_a = os.path.join(TEST_DIR, "vid_a.yuv")
    vid_b = os.path.join(TEST_DIR, "vid_b.yuv")

    with open(vid_a, "wb") as f:
        for _ in range(25):
            f.write(d512)

    with open(vid_b, "wb") as f:
        for _ in range(20):
            f.write(d512)
        for _ in range(5):
            f.write(d513)

    mkv_a = os.path.join(TEST_DIR, "vid_a.mkv")
    mkv_b = os.path.join(TEST_DIR, "vid_b.mkv")

    run_cmd(["ffmpeg", "-v", "quiet", "-y", "-f", "rawvideo", "-pix_fmt", "yuv422p10le", "-s", "320x240", "-r", "25", "-i", vid_a, "-c:v", "ffv1", mkv_a])
    run_cmd(["ffmpeg", "-v", "quiet", "-y", "-f", "rawvideo", "-pix_fmt", "yuv422p10le", "-s", "320x240", "-r", "25", "-i", vid_b, "-c:v", "ffv1", mkv_b])

    res = run_cmd([HARNESS_BIN, "post_20_frame_variation", mkv_a, mkv_b])
    print(res.stdout.strip())

def test_audio_multitrack():
    print("\n--- [專項測試 3] 多軌音訊逐軌 PCM 比對測試 (含雙音軌 FLAC/PCM) ---")
    in_mov = os.path.join(TEST_DIR, "multi_audio_src.mov")
    out_mkv = os.path.join(TEST_DIR, "multi_audio_out.mkv")

    # 產生具備 2 條音軌之 Blackmagic 規範來源 (v210 10-bit 4:2:2, Track 0: 48kHz PCM 24-bit, Track 1: 44.1kHz PCM 24-bit)
    run_cmd([
        "ffmpeg", "-v", "quiet", "-y",
        "-f", "lavfi", "-i", "testsrc=duration=1:size=320x240:rate=25",
        "-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=48000:duration=1",
        "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100:duration=1",
        "-map", "0:v", "-map", "1:a", "-map", "2:a",
        "-c:v", "v210",
        "-c:a", "pcm_s24le",
        in_mov
    ])

    # 轉檔為 MKV FFV1 + FLAC (保留所有音軌)
    run_cmd([
        "ffmpeg", "-v", "quiet", "-y",
        "-i", in_mov,
        "-map", "0:v", "-map", "0:a:0", "-map", "0:a:1",
        "-c:v", "ffv1", "-level", "3", "-g", "1",
        "-c:a", "flac",
        out_mkv
    ])

    res = run_cmd([HARNESS_BIN, "audio_multitrack", in_mov, out_mkv])
    print(res.stdout.strip())

def test_sync_and_metadata():
    print("\n--- [專項測試 4] 影音同步與容器中繼資料獨立報告測試 ---")
    src_tc = os.path.join(TEST_DIR, "src_timecode.mov")
    dst_mkv = os.path.join(TEST_DIR, "dst_timecode.mkv")

    # 產生帶有 timecode 與 metadata 之 Blackmagic 規範來源
    run_cmd([
        "ffmpeg", "-v", "quiet", "-y",
        "-f", "lavfi", "-i", "testsrc=duration=1:size=320x240:rate=25",
        "-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=48000:duration=1",
        "-map", "0:v", "-map", "1:a",
        "-c:v", "v210",
        "-c:a", "pcm_s24le",
        "-timecode", "01:23:45:12",
        "-metadata", "title=OriginalMaster",
        "-metadata", "comment=VerifiedCleanClip",
        src_tc
    ])

    # 轉碼為 MKV (容器中繼資料標籤變更，但像素與 PCM 100% 精準無損)
    run_cmd([
        "ffmpeg", "-v", "quiet", "-y",
        "-i", src_tc,
        "-map", "0:v", "-map", "0:a",
        "-c:v", "ffv1", "-level", "3", "-g", "1",
        "-c:a", "flac",
        "-metadata", "title=LosslessArchive",
        dst_mkv
    ])

    res = run_cmd([HARNESS_BIN, "sync_and_metadata", src_tc, dst_mkv])
    print(res.stdout.strip())

def teardown():
    print("\n==> 清理測試資源...")
    if os.path.exists(TEST_DIR):
        shutil.rmtree(TEST_DIR)
    if os.path.exists(HARNESS_BIN):
        os.remove(HARNESS_BIN)
    print("✓ 清理完成。")

if __name__ == "__main__":
    setup()
    try:
        test_10bit_low_bit()
        test_post_20_frame()
        test_audio_multitrack()
        test_sync_and_metadata()
        print("\n========================================================")
        print("🎉 視訊無損驗證器專項回歸測試 (4大專項) 100% 通過！")
        print("========================================================")
    finally:
        teardown()
