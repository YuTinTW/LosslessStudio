import os
import pathlib
import struct
import subprocess
import sys
import tempfile

_proj_root = pathlib.Path(__file__).resolve().parent.parent
default_app = str(_proj_root / "build" / "LosslessStudio")
default_magick = "/Applications/LosslessStudio.app/Contents/ImageMagick/bin/magick"

app = sys.argv[1] if len(sys.argv) > 1 else default_app
magick = sys.argv[2] if len(sys.argv) > 2 else default_magick

app = str(pathlib.Path(app).resolve())
app_args = [app, "-AppleLanguages", "(zh-Hant)"]
magick = str(pathlib.Path(magick).resolve())

magick_dir = pathlib.Path(magick).resolve().parent.parent
coders_dir = magick_dir / "lib" / "ImageMagick" / "modules-Q16HDRI" / "coders"
env = os.environ.copy()
if coders_dir.exists():
    env["MAGICK_CODER_MODULE_PATH"] = str(coders_dir)
    env["MAGICK_CONFIGURE_PATH"] = str(magick_dir / "etc" / "ImageMagick-7")

print(f"=== LosslessStudio 審核項專項回歸測試 ===")
print(f"  Binary: {app}")
print(f"  Magick: {magick}")

with tempfile.TemporaryDirectory(prefix="lossless-reg-") as tmp:
    root = pathlib.Path(tmp)

    # -------------------------------------------------------------
    # 測試 1: 帶真實 8BIM (Photoshop 3.0 APP13) 的 JPEG 轉 PNG
    # -------------------------------------------------------------
    print("\n--- [專項 1] 帶 8BIM (Photoshop APP13) 的 JPEG 轉 PNG ---")
    base_png = root / "base.png"
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "lavfi", "-i", "color=c=purple:size=64x64:duration=1", "-frames:v", "1", str(base_png)], check=True)
    base_jpg = root / "base.jpg"
    subprocess.run([magick, str(base_png), str(base_jpg)], check=True, env=env)

    # 注入真實 8BIM 區塊
    bim_block = b"Photoshop 3.0\x008BIM\x04\x04\x00\x00\x00\x00\x00?\x1c\x01Z\x00\x03\x1b%G\x1c\x02\x00\x00\x02\x00\x02\x1c\x02?\x00\x06172626\x1c\x02>\x00\x0820220607\x1c\x027\x00\x0820220607\x1c\x02<\x00\x06172626\x008BIM\x04%\x00\x00\x00\x00\x00\x10XZ\xe9\x9a\x89\x8f\xc2\xac\x15\xe8\xd4{\xb9\xd9E*"
    app13 = b"\xff\xed" + struct.pack(">H", len(bim_block) + 2) + bim_block
    jpg_bytes = base_jpg.read_bytes()
    jpg_8bim = root / "sample_8bim.jpg"
    jpg_8bim.write_bytes(jpg_bytes[:2] + app13 + jpg_bytes[2:])

    out_png = root / "output_8bim.png"
    p1 = subprocess.run([*app_args, "--cli", "--mode", "image", "--input", str(jpg_8bim), "--output", str(out_png)], capture_output=True, text=True, env=env)
    assert p1.returncode == 0, f"轉檔失敗: {p1.stderr}"
    assert out_png.exists(), "產物 PNG 不存在"

    bim_in = subprocess.run([magick, str(jpg_8bim), "8bim:-"], capture_output=True, env=env).stdout
    bim_out = subprocess.run([magick, str(out_png), "8bim:-"], capture_output=True, env=env).stdout
    assert bim_in == bim_out and len(bim_in) > 0, f"8BIM 遺失或不符: in={len(bim_in)} vs out={len(bim_out)}"

    pix_in = subprocess.run([magick, str(jpg_8bim), "-depth", "16", "-endian", "MSB", "rgba:-"], capture_output=True, env=env).stdout
    pix_out = subprocess.run([magick, str(out_png), "-depth", "16", "-endian", "MSB", "rgba:-"], capture_output=True, env=env).stdout
    assert pix_in == pix_out, "像素解碼不符"
    print("✓ 通過：帶 8BIM JPEG 轉 PNG 成功產出，8BIM 完整保留，16-bit RGBA 像素 1:1 完全一致。")

    # -------------------------------------------------------------
    # 測試 2: 帶 8BIM 的 JPEG 轉 BMP（目標格式不支援中繼資料）
    # -------------------------------------------------------------
    print("\n--- [專項 2] 帶 8BIM JPEG 轉 BMP（中繼資料受限但產物完整交付）---")
    out_bmp = root / "output_8bim.bmp"
    p2 = subprocess.run([*app_args, "--cli", "--mode", "image", "--input", str(jpg_8bim), "--output", str(out_bmp)], capture_output=True, text=True, env=env)
    assert p2.returncode == 0, f"轉檔失敗: {p2.stderr}"
    assert out_bmp.exists(), "產物 BMP 不存在"
    assert "未符無損" in p2.stdout and "8bim" in p2.stdout, f"未明確標示 8bim 警語: {p2.stdout}"
    print("✓ 通過：BMP 正常交付（大小: {} bytes），終端明確提示未符無損並列出 8bim 遺失。".format(out_bmp.stat().st_size))

    # -------------------------------------------------------------
    # 測試 3: 圖片轉 PDF 客觀宣稱降級（標註已完成・有警告，不假標通過）
    # -------------------------------------------------------------
    print("\n--- [專項 3] 圖片轉 PDF 客觀宣稱降級（標註未符無損，不假標通過）---")
    out_pdf = root / "output.pdf"
    p3 = subprocess.run([*app_args, "--cli", "--mode", "image", "--input", str(base_png), "--output", str(out_pdf)], capture_output=True, text=True, env=env)
    assert p3.returncode == 0, f"圖片轉 PDF 失敗: {p3.stderr}"
    assert out_pdf.exists(), "PDF 產物不存在"
    assert "PDF 容器格式限制" in p3.stdout or "無法保留照片原始 EXIF" in p3.stdout or "未符無損" in p3.stdout, f"PDF 輸出未標明客觀限制: {p3.stdout}"
    assert "無損轉換完成 (無損)" not in p3.stdout, f"PDF 輸出不應假標無損完成: {p3.stdout}"
    print("✓ 通過：PDF 正常產出，輸出資訊誠實標明「PDF 容器格式限制：無法保留照片原始 EXIF 中繼資料與色彩描述檔」。")

    # -------------------------------------------------------------
    # 測試 4: 有損轉換原因整合（不被通用有損說明掩蓋）
    # -------------------------------------------------------------
    print("\n--- [專項 4] 有損圖片轉換具體原因與 Alpha 平坦化警語保留 ---")
    alpha_png = root / "alpha.png"
    raw_rgba = bytes([255, 0, 0, 128] * (32 * 32))
    raw_file = root / "raw.rgba"
    raw_file.write_bytes(raw_rgba)
    subprocess.run([magick, "-size", "32x32", "-depth", "8", f"rgba:{raw_file}", str(alpha_png)], env=env, check=True)

    out_jpg_mode_image = root / "lossy_mode_image.jpg"
    p4 = subprocess.run([*app_args, "--cli", "--mode", "image", "--input", str(alpha_png), "--output", str(out_jpg_mode_image)], capture_output=True, text=True, env=env)
    assert p4.returncode == 0, f"轉檔失敗: {p4.stderr}"
    assert out_jpg_mode_image.exists(), "產物 JPG 不存在"
    assert "Alpha 透明通道" in p4.stdout and "有損壓縮" in p4.stdout, f"未保留 Alpha 平坦化或有損警語: {p4.stdout}"

    out_jpg_mode_lossy = root / "lossy_mode_lossy.jpg"
    p4_lossy = subprocess.run([*app_args, "--cli", "--mode", "image-lossy", "--input", str(alpha_png), "--output", str(out_jpg_mode_lossy)], capture_output=True, text=True, env=env)
    assert p4_lossy.returncode == 0, f"image-lossy 模式轉檔失敗: {p4_lossy.stderr}"
    assert out_jpg_mode_lossy.exists(), "image-lossy 產物 JPG 不存在"
    assert "Alpha 透明通道" in p4_lossy.stdout, f"image-lossy 未保留 Alpha 平坦化警語: {p4_lossy.stdout}"
    print("✓ 通過：有損 JPEG 轉換輸出正常，--mode image 與 --mode image-lossy 皆正確整合 Alpha 平坦化與量化損失警告。")

print("\n🎉 4 大審核回歸專項全部通過！")
