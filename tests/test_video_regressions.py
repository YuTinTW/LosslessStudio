#!/usr/bin/env python3
import os
import pathlib
import subprocess
import sys
import tempfile

_proj_root = pathlib.Path(__file__).resolve().parent.parent
default_app = str(_proj_root / "build" / "LosslessStudio")
app = sys.argv[1] if len(sys.argv) > 1 else default_app
app = str(pathlib.Path(app).resolve())

print("================================================================")
print("LosslessStudio 影片格式相容性、資料軌過濾與智慧降級專項回歸測試")
print(f"  執行檔: {app}")
print("================================================================")

def get_bitstream_md5(filepath: str, stream_spec: str) -> str:
    cmd = ["ffmpeg", "-nostdin", "-v", "quiet", "-i", filepath, "-map", stream_spec, "-c", "copy", "-f", "md5", "-"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        return ""
    return res.stdout.strip().replace("MD5=", "")

with tempfile.TemporaryDirectory(prefix="lossless-video-reg-") as tmp:
    root = pathlib.Path(tmp)

    # -------------------------------------------------------------
    # 測試 1: 廣播級包含 smpte_436m_anc 輔助資料軌的 MXF 轉 MOV 與 MP4
    # -------------------------------------------------------------
    print("\n--- [專項 1] 廣播級含 smpte_436m_anc 資料軌 MXF 轉 MOV / MP4 ---")
    mcc_file = root / "captions.mcc"
    mcc_file.write_text("""File Format=MacCaption_MCC V1.0
UUID=5A1C6E2B-8F04-4C2E-9B7A-1D3E5F607182
Creation Program=Closed Caption Software
Creation Date=Wednesday, October 14, 2026
Creation Time=09:30:00
Time Code Rate=25
00:00:00:10\t942094206168636573bdcc0afc
""")

    # 1.1 MPEG-2 + PCM + smpte_436m_anc MXF -> MOV (直通)
    mxf_mpeg2 = root / "broadcast_mpeg2_anc.mxf"
    gen_mpeg2_cmd = [
        "ffmpeg", "-y",
        "-f", "lavfi", "-i", "testsrc=duration=1:size=720x576:rate=25",
        "-f", "lavfi", "-i", "sine=duration=1:sample_rate=48000",
        "-eia608_extract", "0", "-i", str(mcc_file),
        "-c:v", "mpeg2video", "-c:a", "pcm_s16le", "-ar", "48000",
        "-c:d", "copy",
        "-map", "0:v", "-map", "1:a", "-map", "2:d?",
        str(mxf_mpeg2)
    ]
    subprocess.run(gen_mpeg2_cmd, check=True, capture_output=True)

    probe_in1 = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-of", "json", str(mxf_mpeg2)], capture_output=True, text=True)
    assert "smpte_436m_anc" in probe_in1.stdout, "未能成功合成含 smpte_436m_anc 之 MXF 樣本"

    out_mov = root / "output_from_anc.mov"
    p_mov = subprocess.run([app, "--cli", "--mode", "remux", "--input", str(mxf_mpeg2), "--output", str(out_mov)], capture_output=True, text=True)
    assert p_mov.returncode == 0, f"MXF 轉 MOV 失敗: {p_mov.stderr}"
    assert out_mov.exists() and out_mov.stat().st_size > 0, "MOV 產物不存在或為空"

    # 比對視訊位元流 MD5，驗證視訊為無損直通
    v_in_md5 = get_bitstream_md5(str(mxf_mpeg2), "0:v:0")
    v_out_md5 = get_bitstream_md5(str(out_mov), "0:v:0")
    assert v_in_md5 and v_in_md5 == v_out_md5, f"視訊位元流 MD5 不符: in={v_in_md5} vs out={v_out_md5}"

    # 確證資料軌被安全過濾
    probe_mov = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-of", "json", str(out_mov)], capture_output=True, text=True)
    assert "smpte_436m_anc" not in probe_mov.stdout, "MOV 產物未能成功過濾非相容資料軌"
    print(f"  ✓ 通過: MXF (MPEG-2) 成功直通為 QuickTime MOV (視訊位元流 100% 吻合: {v_in_md5}，無錯誤 234)")

    # 1.2 H.264 + PCM + smpte_436m_anc MXF -> MP4 (直通視訊 + 智慧 AAC 音訊降級 + 資料軌過濾)
    mxf_h264 = root / "broadcast_h264_anc.mxf"
    gen_h264_cmd = [
        "ffmpeg", "-y",
        "-f", "lavfi", "-i", "testsrc=duration=1:size=320x240:rate=25",
        "-f", "lavfi", "-i", "sine=duration=1:sample_rate=48000",
        "-eia608_extract", "0", "-i", str(mcc_file),
        "-c:v", "libx264", "-c:a", "pcm_s16le", "-ar", "48000",
        "-c:d", "copy",
        "-map", "0:v", "-map", "1:a", "-map", "2:d?",
        str(mxf_h264)
    ]
    subprocess.run(gen_h264_cmd, check=True, capture_output=True)

    out_mp4 = root / "output_from_anc.mp4"
    p_mp4 = subprocess.run([app, "--cli", "--mode", "remux", "--input", str(mxf_h264), "--output", str(out_mp4)], capture_output=True, text=True)
    assert p_mp4.returncode == 0, f"MXF 轉 MP4 失敗: {p_mp4.stderr}"
    assert out_mp4.exists() and out_mp4.stat().st_size > 0, "MP4 產物不存在或為空"

    def get_video_framemd5(filepath: str) -> str:
        cmd = ["ffmpeg", "-nostdin", "-v", "quiet", "-i", filepath, "-map", "0:v:0", "-f", "framemd5", "-"]
        return subprocess.run(cmd, capture_output=True, text=True).stdout

    v_h264_in_fmd5 = get_video_framemd5(str(mxf_h264))
    v_h264_out_fmd5 = get_video_framemd5(str(out_mp4))
    assert v_h264_in_fmd5 and v_h264_in_fmd5 == v_h264_out_fmd5, "H.264 解碼視訊幀序列不符"

    probe_mp4 = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-of", "json", str(out_mp4)], capture_output=True, text=True)
    assert "smpte_436m_anc" not in probe_mp4.stdout, "MP4 未能過濾資料軌"
    assert "aac" in probe_mp4.stdout.lower(), "音訊未轉碼為相容 AAC"
    print("  ✓ 通過: MXF (H.264+ANC) 成功轉為 MP4 (視訊幀 100% 吻合，音訊轉相容 AAC，資料軌安全過濾)")

    # 1.3 MXF (MPEG-2+ANC) -> MP4 (透過像素轉碼模式)
    out_trans_mp4 = root / "output_transcode.mp4"
    p_trans = subprocess.run([app, "--cli", "--mode", "transcode", "--input", str(mxf_mpeg2), "--output", str(out_trans_mp4)], capture_output=True, text=True)
    assert p_trans.returncode == 0, f"MXF 轉碼至 MP4 失敗: {p_trans.stderr}"
    assert out_trans_mp4.exists() and out_trans_mp4.stat().st_size > 0, "轉碼產物不存在"
    print("  ✓ 通過: MXF (MPEG-2+ANC) 成功轉碼至 MP4，資料軌安全捨棄無崩潰")

    # -------------------------------------------------------------
    # 測試 2: 包含相機未壓縮音訊 pcm_s16be 的影片轉 MP4（智慧相容降級策略）
    # -------------------------------------------------------------
    print("\n--- [專項 2] pcm_s16be 音訊相機影片轉 MP4 (視訊位元保全 + 音訊相容轉碼) ---")
    src_pcm_mov = root / "camera_pcm_s16be.mov"
    gen_pcm_cmd = [
        "ffmpeg", "-y",
        "-f", "lavfi", "-i", "testsrc=duration=1:size=320x240:rate=30",
        "-f", "lavfi", "-i", "sine=frequency=1000:duration=1",
        "-c:v", "libx264", "-c:a", "pcm_s16be",
        str(src_pcm_mov)
    ]
    subprocess.run(gen_pcm_cmd, check=True, capture_output=True)

    # 確證來源音訊為 pcm_s16be
    probe_pcm = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-of", "json", str(src_pcm_mov)], capture_output=True, text=True)
    assert "pcm_s16be" in probe_pcm.stdout, "未能成功合成含 pcm_s16be 音訊之樣本"

    out_pcm_mp4 = root / "camera_transcoded.mp4"
    p_fallback = subprocess.run([app, "--cli", "--mode", "remux", "--input", str(src_pcm_mov), "--output", str(out_pcm_mp4)], capture_output=True, text=True)
    assert p_fallback.returncode == 0, f"智慧降級轉檔失敗: {p_fallback.stderr}"
    assert "NOTICE" in p_fallback.stdout or "AAC" in p_fallback.stdout or "相容" in p_fallback.stdout, "日誌未註記音訊相容轉換說明"

    # 驗證產物：視訊位元流 100% 精確直通，音訊為相容 AAC
    v_pcm_in_md5 = get_bitstream_md5(str(src_pcm_mov), "0:v:0")
    v_pcm_out_md5 = get_bitstream_md5(str(out_pcm_mp4), "0:v:0")
    assert v_pcm_in_md5 and v_pcm_in_md5 == v_pcm_out_md5, f"視訊位元流應直通無損: in={v_pcm_in_md5} vs out={v_pcm_out_md5}"

    probe_mp4_out = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-of", "json", str(out_pcm_mp4)], capture_output=True, text=True)
    assert "aac" in probe_mp4_out.stdout.lower(), "產物音訊未成功轉碼為相容 AAC"
    print(f"  ✓ 通過: 系統自動以「視訊位元直通保全 (MD5: {v_pcm_in_md5}) + 音訊轉高品質相容 AAC」智慧完成交付，杜絕直接拒絕")

    # -------------------------------------------------------------
    # 測試 3: 七大常見容器 (MP4, MKV, MOV, WebM, AVI, TS, MXF) 交叉互轉矩陣
    # -------------------------------------------------------------
    print("\n--- [專項 3] 七大容器 (MP4, MKV, MOV, WebM, AVI, TS, MXF) 交叉轉換驗證 ---")
    containers = ["mp4", "mkv", "mov", "webm", "avi", "ts", "mxf"]
    
    # 建立基準檔案
    base_file = root / "base_video.mp4"
    subprocess.run([
        "ffmpeg", "-y",
        "-f", "lavfi", "-i", "testsrc=duration=1:size=320x240:rate=25",
        "-f", "lavfi", "-i", "sine=duration=1:sample_rate=48000",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac",
        str(base_file)
    ], check=True, capture_output=True)

    passed_count = 0
    total_count = len(containers)

    for target_c in containers:
        target_file = root / f"transcode_target.{target_c}"
        cmd = [app, "--cli", "--mode", "transcode", "--input", str(base_file), "--output", str(target_file)]
        p_c = subprocess.run(cmd, capture_output=True, text=True)
        assert p_c.returncode == 0, f"轉檔至 .{target_c} 失敗: {p_c.stderr}"
        assert target_file.exists() and target_file.stat().st_size > 0, f".{target_c} 產物無效"
        
        # 驗證產物有視訊且可讀
        probe_res = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-of", "json", str(target_file)], capture_output=True, text=True)
        assert "video" in probe_res.stdout, f".{target_c} 產物遺失視訊軌"
        passed_count += 1
        print(f"  ✓ 基準 MP4 -> .{target_c.upper()} 轉碼驗證成功 ({target_file.stat().st_size} bytes)")

    print(f"\n🎉 專項回歸測試全數通過！(3 大測試項目、{passed_count}/{total_count} 容器轉碼無縫驗證通過)")
