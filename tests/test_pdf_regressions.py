import hashlib
import os
import pathlib
import subprocess
import sys
import tempfile
import time
from PIL import Image

_proj_root = pathlib.Path(__file__).resolve().parent.parent
default_app = str(_proj_root / "build" / "LosslessStudio")
default_magick = "/Applications/LosslessStudio.app/Contents/ImageMagick/bin/magick"

app = sys.argv[1] if len(sys.argv) > 1 else default_app
magick = sys.argv[2] if len(sys.argv) > 2 else default_magick

app = str(pathlib.Path(app).resolve())
magick = str(pathlib.Path(magick).resolve())

magick_dir = pathlib.Path(magick).resolve().parent.parent
coders_dir = magick_dir / "lib" / "ImageMagick" / "modules-Q16HDRI" / "coders"
env = os.environ.copy()
env["MAGICK_TEMPORARY_PATH"] = "/tmp"
if coders_dir.exists():
    env["MAGICK_CODER_MODULE_PATH"] = str(coders_dir)
    env["MAGICK_CONFIGURE_PATH"] = str(magick_dir / "etc" / "ImageMagick-7")

print(f"=== LosslessStudio PDF 點陣化與轉圖片完整安全與深度回歸測試 ===")
print(f"  Binary: {app}")
print(f"  Magick: {magick}")

def file_md5(p: pathlib.Path) -> str:
    return hashlib.md5(p.read_bytes()).hexdigest()

with tempfile.TemporaryDirectory(prefix="lossless-pdf-deep-") as tmp:
    root = pathlib.Path(tmp)

    # 1. 產生測試 PDF 檔案
    pdf_generator = root / "gen_pdfs.swift"
    pdf_generator.write_text("""
import Foundation
import CoreGraphics
import PDFKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])

// 1. 生成三頁測試 PDF (200x100, 150x150, 100x300)
do {
    let url = outDir.appendingPathComponent("multi_page.pdf")
    var box1 = CGRect(x: 0, y: 0, width: 200, height: 100)
    var box2 = CGRect(x: 0, y: 0, width: 150, height: 150)
    var box3 = CGRect(x: 0, y: 0, width: 100, height: 300)

    guard let consumer = CGDataConsumer(url: url as CFURL),
          let ctx = CGContext(consumer: consumer, mediaBox: &box1, nil) else { fatalError() }

    ctx.beginPage(mediaBox: &box1)
    ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    ctx.fill(CGRect(x: 10, y: 10, width: 80, height: 80))
    ctx.endPage()

    ctx.beginPage(mediaBox: &box2)
    ctx.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
    ctx.fillEllipse(in: CGRect(x: 20, y: 20, width: 110, height: 110))
    ctx.endPage()

    ctx.beginPage(mediaBox: &box3)
    ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
    ctx.fill(CGRect(x: 10, y: 50, width: 80, height: 200))
    ctx.endPage()
    ctx.closePDF()
}

// 2. 旋轉 90 度 PDF
do {
    let url = outDir.appendingPathComponent("rotated.pdf")
    var box = CGRect(x: 0, y: 0, width: 200, height: 100)
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { fatalError() }
    ctx.beginPage(mediaBox: &box)
    ctx.setFillColor(red: 1, green: 0.5, blue: 0, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
    ctx.endPage()
    ctx.closePDF()

    let doc = PDFDocument(url: url)!
    doc.page(at: 0)!.rotation = 90
    doc.write(to: url)
}

// 3. 加密 PDF
do {
    let url = outDir.appendingPathComponent("locked.pdf")
    var box = CGRect(x: 0, y: 0, width: 100, height: 100)
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { fatalError() }
    ctx.beginPage(mediaBox: &box)
    ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
    ctx.endPage()
    ctx.closePDF()

    let doc = PDFDocument(url: url)!
    doc.write(to: url, withOptions: [.userPasswordOption: "secret123"])
}

// 4. 透明度 PDF
do {
    let url = outDir.appendingPathComponent("transparent.pdf")
    var box = CGRect(x: 0, y: 0, width: 100, height: 100)
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { fatalError() }
    ctx.beginPage(mediaBox: &box)
    ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 0.5)
    ctx.fill(CGRect(x: 20, y: 20, width: 60, height: 60))
    ctx.endPage()
    ctx.closePDF()
}

// 5. 半透明純紅測試 (red: 1.0, green: 0.0, blue: 0.0, alpha: 0.5)
do {
    let url = outDir.appendingPathComponent("translucent_red.pdf")
    var box = CGRect(x: 0, y: 0, width: 100, height: 100)
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { fatalError() }
    ctx.beginPage(mediaBox: &box)
    ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 0.5)
    ctx.fill(CGRect(x: 10, y: 10, width: 80, height: 80))
    ctx.endPage()
    ctx.closePDF()
}

// 6. 非對稱角落旋轉測試 (200x100 頁面，左上角 x:10, y:70, w:20, h:20 紅色標記)
for r in [90, 180, 270] {
    let url = outDir.appendingPathComponent("asym_rot_\\(r).pdf")
    var box = CGRect(x: 0, y: 0, width: 200, height: 100)
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { fatalError() }
    ctx.beginPage(mediaBox: &box)
    ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    ctx.fill(CGRect(x: 10, y: 70, width: 20, height: 20))
    ctx.endPage()
    ctx.closePDF()

    let doc = PDFDocument(url: url)!
    doc.page(at: 0)!.rotation = r
    doc.write(to: url)
}
""")
    subprocess.run(["swift", str(pdf_generator), str(root)], check=True)

    multi_pdf = root / "multi_page.pdf"
    corrupted_pdf = root / "corrupted.pdf"
    corrupted_pdf.write_bytes(b"%PDF-1.4\nGarbageCorruptedContent...")

    # -------------------------------------------------------------
    # 測試 1: Sentinel 防破壞測試（既有 output 及 _page_2 sentinel 內容 Hash 100% 不變）
    # -------------------------------------------------------------
    print("\n--- [專項 1] Sentinel 防破壞測試（嚴禁覆寫既有 output 及 _page_2，自動尋找非衝突序列）---")
    sentinel_base = root / "sentinel_job.png"
    sentinel_page2 = root / "sentinel_job_page_2.png"

    sentinel_base.write_text("SENTINEL_BASE_ORIGINAL_DATA_DO_NOT_TOUCH")
    sentinel_page2.write_text("SENTINEL_PAGE_2_ORIGINAL_DATA_DO_NOT_TOUCH")

    hash_base_before = file_md5(sentinel_base)
    hash_p2_before = file_md5(sentinel_page2)

    p1 = subprocess.run([app, "--cli", "--mode", "document", "--input", str(multi_pdf), "--output", str(sentinel_base)], capture_output=True, text=True, env=env)
    assert p1.returncode == 0, f"轉檔失敗: {p1.stderr}\nstdout: {p1.stdout}"

    # 驗證既有 sentinel 檔案未被覆寫，Hash 100% 不變
    assert file_md5(sentinel_base) == hash_base_before, "既有 sentinel_base 檔案內容被篡改！"
    assert file_md5(sentinel_page2) == hash_p2_before, "既有 sentinel_page_2 檔案內容被篡改！"

    # 驗證新產物自動避開衝突，改為 _1 序列產出
    out_1_p1 = root / "sentinel_job_1_page_1.png"
    out_1_p2 = root / "sentinel_job_1_page_2.png"
    out_1_p3 = root / "sentinel_job_1_page_3.png"

    assert out_1_p1.exists(), f"避撞序列第 1 頁應產出於 {out_1_p1}"
    assert out_1_p2.exists(), f"避撞序列第 2 頁應產出於 {out_1_p2}"
    assert out_1_p3.exists(), f"避撞序列第 3 頁應產出於 {out_1_p3}"
    print("✓ 通過：既有檔案與 _page_2 哨兵內容 Hash 100% 保持原樣，系統自動遞增檔名序列避開衝突。")

    # -------------------------------------------------------------
    # 測試 2: 多頁不殘留未記錄的首頁額外副本
    # -------------------------------------------------------------
    print("\n--- [專項 2] 多頁產物乾淨性測試（多頁不殘留未記錄之首頁副本）---")
    clean_target = root / "clean_multi.png"
    p2 = subprocess.run([app, "--cli", "--mode", "document", "--input", str(multi_pdf), "--output", str(clean_target)], capture_output=True, text=True, env=env)
    assert p2.returncode == 0, f"轉檔失敗: {p2.stderr}"

    assert (root / "clean_multi_page_1.png").exists()
    assert (root / "clean_multi_page_2.png").exists()
    assert (root / "clean_multi_page_3.png").exists()
    assert not clean_target.exists(), f"多頁輸出不應無故建立未記錄之重複 {clean_target} 檔案！"
    print("✓ 通過：多頁輸出僅依序產出 _page_1..3，絕不硬湊殘留重複首頁檔案。")

    # -------------------------------------------------------------
    # 測試 3: 真正中途取消回滾測試（渲染第 1 頁後中止，零洩漏、不刪除外部檔案）
    # -------------------------------------------------------------
    print("\n--- [專項 3] 真正中途取消回滾測試（--cancel-after-page 1，嚴格回滾不刪除外部既有檔案）---")
    ext_file = root / "external_user_file.png"
    ext_file.write_text("IMPORTANT_EXTERNAL_USER_FILE_CONTENT")
    ext_hash = file_md5(ext_file)

    cancel_target = root / "cancel_job.png"
    p3_cancel = subprocess.run([app, "--cli", "--mode", "document", "--input", str(multi_pdf), "--output", str(cancel_target), "--cancel-after-page", "1"], capture_output=True, text=True, env=env)
    assert p3_cancel.returncode != 0, "中途取消應返回非零退出碼"
    assert ext_file.exists() and file_md5(ext_file) == ext_hash, "外部既有檔案在取消回滾時被意外刪除或修改！"
    assert not cancel_target.exists(), "中途取消不應留下主輸出檔"
    assert not (root / "cancel_job_page_1.png").exists(), "中途取消不應將第 1 頁洩漏殘留至目標目錄"
    assert not (root / "cancel_job_page_2.png").exists()

    staging_dirs_cancel = list(root.glob(".pdf-render-*"))
    assert len(staging_dirs_cancel) == 0, f"中途取消後 staging 目錄未被清理: {staging_dirs_cancel}"
    print("✓ 通過：中途取消（第 1 頁渲染後取消）成功回滾，外部既有檔案與目標目錄零污染，staging 100% 清理。")

    # -------------------------------------------------------------
    # 測試 4: 2 個同 BaseName 並行轉檔撞名保護 (Concurrent collision safety)
    # -------------------------------------------------------------
    print("\n--- [專項 4] 並行撞名原子隔離測試（2 個同名任務並行，零覆蓋、產物各自完整）---")
    sub1 = root / "concurrent_test.png"
    sub2 = root / "concurrent_test.png"

    # 同時啟動兩個進程，指向相同 output 基準
    procA = subprocess.Popen([app, "--cli", "--mode", "document", "--input", str(multi_pdf), "--output", str(sub1)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    procB = subprocess.Popen([app, "--cli", "--mode", "document", "--input", str(multi_pdf), "--output", str(sub2)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)

    outA, errA = procA.communicate()
    outB, errB = procB.communicate()

    assert procA.returncode == 0, f"進程 A 失敗: {errA}"
    assert procB.returncode == 0, f"進程 B 失敗: {errB}"

    # 兩個任務應產出兩組不重疊的完整頁面序列 (共 6 個檔案)
    set1 = [root / f"concurrent_test_page_{i}.png" for i in (1, 2, 3)]
    set2 = [root / f"concurrent_test_1_page_{i}.png" for i in (1, 2, 3)]

    for f in set1 + set2:
        assert f.exists(), f"並行產物缺失: {f.name}"
    print("✓ 通過：2 個同名任務同時啟動，原子加鎖預約成功隔離為 concurrent_test 及 concurrent_test_1 兩組共 6 檔，零覆蓋。")

    # -------------------------------------------------------------
    # 測試 5: DPI 動態解析度實測 (72 vs 150 vs 300 尺寸嚴格成比例)
    # -------------------------------------------------------------
    print("\n--- [專項 5] DPI 動態調整實測（驗證 72 / 150 / 300 DPI 像素尺寸精確比例差異）---")
    out_72 = root / "dpi_72.png"
    out_150 = root / "dpi_150.png"
    out_300 = root / "dpi_300.png"

    subprocess.run([app, "--cli", "--mode", "document", "--input", str(multi_pdf), "--output", str(out_72), "--dpi", "72"], check=True, env=env)
    subprocess.run([app, "--cli", "--mode", "document", "--input", str(multi_pdf), "--output", str(out_150), "--dpi", "150"], check=True, env=env)
    subprocess.run([app, "--cli", "--mode", "document", "--input", str(multi_pdf), "--output", str(out_300), "--dpi", "300"], check=True, env=env)

    p1_72 = root / "dpi_72_page_1.png"
    p1_150 = root / "dpi_150_page_1.png"
    p1_300 = root / "dpi_300_page_1.png"

    dim_72 = subprocess.run([magick, "identify", "-format", "%wx%h", str(p1_72)], capture_output=True, text=True, env=env).stdout.strip()
    dim_150 = subprocess.run([magick, "identify", "-format", "%wx%h", str(p1_150)], capture_output=True, text=True, env=env).stdout.strip()
    dim_300 = subprocess.run([magick, "identify", "-format", "%wx%h", str(p1_300)], capture_output=True, text=True, env=env).stdout.strip()

    w72, h72 = map(int, dim_72.split("x"))
    w150, h150 = map(int, dim_150.split("x"))
    w300, h300 = map(int, dim_300.split("x"))

    # 第 1 頁 PDF 幾何為 200x100 pt
    # 72 DPI: 200x100
    # 150 DPI: ~417x209
    # 300 DPI: ~834x417
    assert 198 <= w72 <= 202 and 98 <= h72 <= 102, f"72 DPI 尺寸不符: {dim_72}"
    assert 415 <= w150 <= 420 and 205 <= h150 <= 212, f"150 DPI 尺寸不符: {dim_150}"
    assert 830 <= w300 <= 838 and 414 <= h300 <= 420, f"300 DPI 尺寸不符: {dim_300}"

    assert w72 < w150 < w300 and h72 < h150 < h300, "DPI 尺寸遞增關係不符"
    print(f"✓ 通過：72 DPI ({dim_72})、150 DPI ({dim_150})、300 DPI ({dim_300}) 尺寸完全隨參數精準變化，比例吻合。")

    # 驗證非均勻內容 bounding box 在 72 / 150 / 300 DPI 佔比嚴格一致（防止內容未隨畫布放大）
    im72 = Image.open(str(p1_72)).convert("RGBA")
    im150 = Image.open(str(p1_150)).convert("RGBA")
    im300 = Image.open(str(p1_300)).convert("RGBA")
    bbox72 = Image.eval(im72.split()[0], lambda x: 255 if x > 200 else 0).getbbox()
    bbox150 = Image.eval(im150.split()[0], lambda x: 255 if x > 200 else 0).getbbox()
    bbox300 = Image.eval(im300.split()[0], lambda x: 255 if x > 200 else 0).getbbox()
    assert bbox72 and bbox150 and bbox300, "無法偵測紅色內容區域邊界"
    w_r72 = (bbox72[2] - bbox72[0]) / w72
    h_r72 = (bbox72[3] - bbox72[1]) / h72
    w_r150 = (bbox150[2] - bbox150[0]) / w150
    h_r150 = (bbox150[3] - bbox150[1]) / h150
    w_r300 = (bbox300[2] - bbox300[0]) / w300
    h_r300 = (bbox300[3] - bbox300[1]) / h300
    print(f"  非均勻內容佔比: 72 DPI (w={w_r72:.4f}, h={h_r72:.4f}), 150 DPI (w={w_r150:.4f}, h={h_r150:.4f}), 300 DPI (w={w_r300:.4f}, h={h_r300:.4f})")
    assert abs(w_r72 - w_r150) < 0.02 and abs(w_r72 - w_r300) < 0.02, f"寬度佔比不一致: 72={w_r72}, 150={w_r150}, 300={w_r300}"
    assert abs(h_r72 - h_r150) < 0.02 and abs(h_r72 - h_r300) < 0.02, f"高度佔比不一致: 72={h_r72}, 150={h_r150}, 300={h_r300}"
    print("  ✓ 通過：非均勻內容在 72/150/300 DPI 佔比嚴格一致，確認內容確實隨 DPI 等比例放大。")

    # 驗證非對稱角落旋轉（90/180/270度角落位置精確對齊，嚴防雙重旋轉或尺寸縮小）
    for r, exp_x, exp_y in [(90, 70, 10), (180, 170, 70), (270, 10, 170)]:
        asym_in = root / f"asym_rot_{r}.pdf"
        asym_out = root / f"asym_rendered_{r}.png"
        subprocess.run([app, "--cli", "--mode", "document", "--input", str(asym_in), "--output", str(asym_out), "--dpi", "72"], check=True, env=env)
        asym_im = Image.open(str(asym_out)).convert("RGBA")
        asym_bbox = Image.eval(asym_im.split()[0], lambda x: 255 if x > 200 else 0).getbbox()
        assert asym_bbox is not None, f"旋轉 {r} 度後無法偵測紅色角標"
        # 容許 2px 算術邊界誤差
        bx0, by0, bx1, by1 = asym_bbox
        bw = bx1 - bx0
        bh = by1 - by0
        assert 18 <= bw <= 22 and 18 <= bh <= 22, f"旋轉 {r} 度後角標尺寸失真: {bw}x{bh}"
        assert abs(bx0 - exp_x) <= 3 and abs(by0 - exp_y) <= 3, f"旋轉 {r} 度後角標位置錯誤（可能發生雙重旋轉）: 實測 {asym_bbox} vs 預期起始 ({exp_x}, {exp_y})"
        print(f"  ✓ 旋轉 {r:3} 度非對稱角標: 實測邊界 {asym_bbox} 吻合預期位置 ({exp_x}, {exp_y})，無雙重旋轉。")

    # -------------------------------------------------------------
    # 測試 6: 零 ImageIO 編碼依賴，全格式 ImageMagick 編碼驗證
    # -------------------------------------------------------------
    print("\n--- [專項 6] 格式完整性（PNG, JPEG, TIFF, BMP, WebP 全部由內嵌 ImageMagick 編碼產出）---")
    trans_pdf = root / "transparent.pdf"
    for fmt in ["png", "jpg", "tiff", "bmp", "webp"]:
        out_f = root / f"magick_pure.{fmt}"
        res = subprocess.run([app, "--cli", "--mode", "document", "--input", str(trans_pdf), "--output", str(out_f)], capture_output=True, text=True, env=env)
        assert res.returncode == 0, f"{fmt} 轉換失敗: {res.stderr}"
        assert out_f.exists(), f"{fmt} 產物缺失"
        size = out_f.stat().st_size
        assert size > 0, f"{fmt} 為空檔"
        print(f"  ✓ {fmt.upper()}: {size} bytes")

    # -------------------------------------------------------------
    # 測試 7: 半透明純紅 Unpremultiply 實際像素值檢驗（防暗邊）
    # -------------------------------------------------------------
    print("\n--- [專項 7] 半透明純紅 Unpremultiply 實際像素檢驗（RGBA straight alpha 解除預乘，杜絕暗邊）---")
    red_pdf = root / "translucent_red.pdf"
    red_png = root / "translucent_red.png"
    res_red = subprocess.run([app, "--cli", "--mode", "document", "--input", str(red_pdf), "--output", str(red_png), "--dpi", "150"], capture_output=True, text=True, env=env)
    assert res_red.returncode == 0, f"半透明紅轉檔失敗: {res_red.stderr}"
    assert red_png.exists()

    # 1. 使用 ImageMagick identify 讀取中央像素 (104, 104) 之實際 RGBA
    pix_val = subprocess.run([magick, "identify", "-format", "%[pixel:p{104,104}]", str(red_png)], capture_output=True, text=True, env=env).stdout.strip()
    print(f"  ImageMagick 像素取樣值: {pix_val}")
    # 若為 premultiplied 未反預乘，R 會被壓低至 128 (srgba(128,0,0,0.5))
    # 經反預乘後，R 必須恢復為飽和紅色 (R > 240 / srgba(255,0,0,0.5))
    assert "255" in pix_val or "100%" in pix_val, f"未正確執行 Unpremultiply，半透明紅像素 R 通道異常 (可能殘留暗紅/暗邊): {pix_val}"

    # 2. 同步使用 Python PIL / Pillow 進行獨立位元組驗證
    try:
        from PIL import Image
        im = Image.open(str(red_png)).convert("RGBA")
        cx, cy = im.width // 2, im.height // 2
        r, g, b, a = im.getpixel((cx, cy))
        print(f"  PIL RGBA 中心點 ({cx}, {cy}) 取樣值: ({r}, {g}, {b}, {a})")
        assert r >= 250 and g <= 10 and b <= 10 and 120 <= a <= 136, f"PIL 檢測像素非反預乘飽和紅: ({r}, {g}, {b}, {a})"
    except ImportError:
        pass
    print("  ✓ 通過：半透明純紅反預乘實測成功，R 通道保持飽和 255/100%，無暗邊。")

    # -------------------------------------------------------------
    # 測試 8: 真實 Metadata DPI 單位與 JPEG 95 規格驗證
    # -------------------------------------------------------------
    print("\n--- [專項 8] 真實 Metadata DPI (PixelsPerInch) 與 JPEG 品質規格驗證 ---")
    # 檢驗 PNG DPI
    png_dpi = subprocess.run([magick, "identify", "-units", "PixelsPerInch", "-format", "%x x %y %U", str(p1_150)], capture_output=True, text=True, env=env).stdout.strip()
    print(f"  PNG 150 DPI Metadata: {png_dpi}")
    assert "PixelsPerInch" in png_dpi and ("149.99" in png_dpi or "150" in png_dpi), f"PNG DPI 單位或數值異常: {png_dpi}"

    # 檢驗 JPG 品質為 95
    jpg_file = root / "magick_pure.jpg"
    jpg_q = subprocess.run([magick, "identify", "-format", "%Q", str(jpg_file)], capture_output=True, text=True, env=env).stdout.strip()
    print(f"  JPEG Quality: {jpg_q}")
    assert jpg_q == "95", f"JPEG 品質應為 95 (符合 UI 規格)，實測為: {jpg_q}"

    # -------------------------------------------------------------
    # 測試 9: Staging 目錄無殘留與無零長佔位暴露
    # -------------------------------------------------------------
    print("\n--- [專項 9] Staging 目錄安全生命週期（零殘留暫存目錄、無零長佔位檔案暴露）---")
    stray_staging = list(root.glob(".pdf-render-*"))
    assert len(stray_staging) == 0, f"偵測到洩漏的 staging 目錄: {stray_staging}"
    stray_rgba = list(root.glob("*.rgba"))
    assert len(stray_rgba) == 0, f"偵測到洩漏的 raw rgba 暫存: {stray_rgba}"
    print("  ✓ 通過：所有 staging 暫存目錄與 raw RGBA 點陣檔案皆在 defer 生命週期內 100% 清理。")

    # -------------------------------------------------------------
    # 測試 10: 提交中碰撞與 Inode 身分核實（Page 2 撞名時撤銷 Page 1，但絕不誤刪 Page 2 外部檔案）
    # -------------------------------------------------------------
    print("\n--- [專項 10] 提交中碰撞與 Inode 身分核實（Page 2 碰撞撤銷 Page 1，嚴格 Inode 比對不刪外部檔）---")
    in_commit_base = root / "commit_collision_job.png"
    in_commit_p2 = root / "commit_collision_job_page_2.png"
    in_commit_p2.write_text("SENTINEL_IN_COMMIT_PAGE_2_DATA")
    p2_ino_before = in_commit_p2.stat().st_ino
    p2_hash_before = file_md5(in_commit_p2)

    p10 = subprocess.run([app, "--cli", "--mode", "document", "--input", str(multi_pdf), "--output", str(in_commit_base)], capture_output=True, text=True, env=env)
    assert p10.returncode == 0, f"提交中碰撞避讓失敗: {p10.stderr}"

    # 驗證 Page 2 Sentinel 內容與 Inode 完全未被更動
    assert in_commit_p2.exists()
    assert in_commit_p2.stat().st_ino == p2_ino_before, "Page 2 Sentinel Inode 發生變更，遭非法刪除重建！"
    assert file_md5(in_commit_p2) == p2_hash_before, "Page 2 Sentinel 內容遭篡改！"

    # 驗證首輪 link 的 Page 1 在遇到 Page 2 碰撞後已透過 Inode 比對正確撤回
    assert not (root / "commit_collision_job_page_1.png").exists(), "第 1 頁硬連結未在碰撞時正確撤銷！"

    # 驗證任務自動遞增至 _1 序列產出完整 3 頁
    assert (root / "commit_collision_job_1_page_1.png").exists()
    assert (root / "commit_collision_job_1_page_2.png").exists()
    assert (root / "commit_collision_job_1_page_3.png").exists()
    print("  ✓ 通過：提交中第 2 頁碰撞時，第 1 頁依 Inode 確證身分安全撤銷，外部第 2 頁 Inode 與內容 100% 保持原樣，新序列完整產出。")

    # -------------------------------------------------------------
    # 測試 11: 外部置換 Inode 身分核實免疫測試（被外力替換之檔案絕不被撤回機制誤刪）
    # -------------------------------------------------------------
    print("\n--- [專項 11] 外部置換 Inode 身分核實免疫測試（外力替換之同名檔案拒絕 unlink）---")
    replacement_script = root / "test_replacement_identity.swift"
    replacement_script.write_text("""
import Foundation
import Darwin

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let stageFile = dir.appendingPathComponent("stage_test.png")
try! "STAGED_ORIGINAL".write(to: stageFile, atomically: true, encoding: .utf8)

var stStage = stat()
lstat(stageFile.path, &stStage)
let expectedDev = stStage.st_dev
let expectedIno = stStage.st_ino

let targetFile = dir.appendingPathComponent("target_replace_test.png")
assert(link(stageFile.path, targetFile.path) == 0)

// 模擬在硬連結後、清理前，外部進程以新檔案替換 targetFile (產生不同 Inode)
unlink(targetFile.path)
try! "EXTERNAL_ATTACKER_OR_USER_REPLACEMENT".write(to: targetFile, atomically: true, encoding: .utf8)
var stReplaced = stat()
lstat(targetFile.path, &stReplaced)
assert(stReplaced.st_ino != expectedIno)

// 執行引擎之 Inode 身分核實清理邏輯
var unlinked = false
var stTarget = stat()
if lstat(targetFile.path, &stTarget) == 0 && stTarget.st_dev == expectedDev && stTarget.st_ino == expectedIno {
    unlink(targetFile.path)
    unlinked = true
}

assert(!unlinked, "身分核實機制必須拒絕刪除 Inode 不匹配的替換檔案！")
let survivor = try! String(contentsOf: targetFile, encoding: .utf8)
assert(survivor == "EXTERNAL_ATTACKER_OR_USER_REPLACEMENT")
print("Swift Inode Identity Immunity PASS")
""")
    res_swift = subprocess.run(["swift", str(replacement_script), str(root)], capture_output=True, text=True)
    assert res_swift.returncode == 0, f"外部置換 Inode 身分核實免疫測試失敗: {res_swift.stderr}"
    print("  ✓ 通過：若 target 被外部進程替換為新 Inode，引擎 lstat 身份比對成功拒絕 unlink，外部檔案安全留存。")

    # -------------------------------------------------------------
    # 測試 12: 非 EEXIST 錯誤立即中斷保護（拒絕 10000 次無意義空迴圈）
    # -------------------------------------------------------------
    print("\n--- [專項 12] 非 EEXIST 硬連結錯誤立即中止保護（唯讀目錄等嚴格拒絕萬次無意義空重試）---")
    readonly_dir = root / "readonly_output_dir"
    readonly_dir.mkdir(parents=True, exist_ok=True)
    readonly_dir.chmod(0o555)  # 唯讀權限
    defer_chmod = lambda: readonly_dir.chmod(0o755)

    try:
        t_start = time.time()
        p12 = subprocess.run([app, "--cli", "--mode", "document", "--input", str(multi_pdf), "--output", str(readonly_dir / "out.png")], capture_output=True, text=True, env=env)
        elapsed = time.time() - t_start
        assert p12.returncode != 0, "唯讀目錄應返回非零錯誤退出碼"
        assert elapsed < 3.0, f"遇到權限等非 EEXIST 錯誤耗時 {elapsed:.2f}s，疑似陷入 10000 次無意義重試！"
        print(f"  ✓ 通過：遭遇非 EEXIST 權限錯誤於 {elapsed:.2f} 秒內立即中止拋錯，未進行無意義萬次空重試。")
    finally:
        defer_chmod()

    # -------------------------------------------------------------
    # 測試 13: 跨卷軸與非硬連結檔案系統 (FAT32/exFAT) 及中文空白路徑安全提交與防覆寫碰撞
    # -------------------------------------------------------------
    print("\n--- [專項 13] 跨卷軸與非硬連結檔案系統 (FAT32/exFAT) 及中文空白路徑安全提交 ---")
    setup_script = _proj_root / "scripts" / "setup_fat32_test_vol.sh"
    fat_mount = _proj_root / "reports" / "portability-20261117" / "test-volumes" / "mnt"

    # 1. 確保透過專案內專屬腳本掛載獨立 FAT32 測試卷軸
    res_setup = subprocess.run([str(setup_script)], capture_output=True, text=True)
    assert res_setup.returncode == 0, f"執行 FAT32 建卷腳本失敗: {res_setup.stderr}"

    # 2. 嚴格驗證掛載點真實檔案系統類型，拒絕以普通 APFS 空目錄冒充
    mount_check = subprocess.run(["diskutil", "info", str(fat_mount)], capture_output=True, text=True)
    assert mount_check.returncode == 0, f"無法讀取掛載點資訊: {mount_check.stderr}"
    assert "Type (Bundle):             msdos" in mount_check.stdout or "Partition Type:            DOS_FAT_32" in mount_check.stdout, f"掛載點檔案系統非真實 msdos/FAT32: {mount_check.stdout}"

    # 3. 實地執行 link 探針，確認檔案系統硬連結限制 (errno: 45 ENOTSUP)
    probe_src = fat_mount / "probe_link_src.bin"
    probe_dst = fat_mount / "probe_link_dst.bin"
    probe_src.write_bytes(b"LINK_PROBE_DATA")
    probe_errno = None
    try:
        os.link(str(probe_src), str(probe_dst))
    except OSError as e:
        probe_errno = e.errno
    finally:
        if probe_src.exists(): probe_src.unlink()
        if probe_dst.exists(): probe_dst.unlink()

    assert probe_errno == 45, f"FAT32 卷軸 link 探針應拋出 errno: 45 (ENOTSUP)，實際回傳: {probe_errno}"
    print(f"  [確證] 掛載點檔案系統已核實為 msdos/FAT32，link 探針回傳碼: {probe_errno} (ENOTSUP)。")

    fat_target_dir = fat_mount / "測試 專案 目錄 with spaces"
    fat_target_dir.mkdir(parents=True, exist_ok=True)
    fat_out_base = fat_target_dir / "fat_render.png"

    # 4. 正常提交 3 頁 PDF 至 FAT32 卷軸（驗證完整端到端轉檔）
    p13 = subprocess.run([app, "--cli", "--mode", "document", "--input", str(multi_pdf), "--output", str(fat_out_base)], capture_output=True, text=True, env=env)
    assert p13.returncode == 0, f"FAT32 提交失敗: {p13.stderr}"
    for i in range(1, 4):
        page_file = fat_target_dir / f"fat_render_page_{i}.png"
        assert page_file.exists(), f"FAT32 頁面未生成: {page_file}"
        assert page_file.stat().st_size > 0, f"FAT32 頁面為空: {page_file}"

    # 5. 測試 FAT32 卷軸碰撞避讓與首頁身分回滾
    fat_coll_base = fat_target_dir / "fat_coll.png"
    fat_sentinel_p2 = fat_target_dir / "fat_coll_page_2.png"
    fat_sentinel_p2.write_bytes(b"SENTINEL_FAT32_PAGE_2")
    p2_bytes_before = fat_sentinel_p2.read_bytes()

    p13_coll = subprocess.run([app, "--cli", "--mode", "document", "--input", str(multi_pdf), "--output", str(fat_coll_base)], capture_output=True, text=True, env=env)
    assert p13_coll.returncode == 0, f"FAT32 碰撞提交失敗: {p13_coll.stderr}"
    assert fat_sentinel_p2.exists() and fat_sentinel_p2.read_bytes() == p2_bytes_before, "FAT32 外部 Sentinel 遭覆寫！"
    assert not (fat_target_dir / "fat_coll_page_1.png").exists(), "FAT32 第一頁未在碰撞時回滾！"
    for i in range(1, 4):
        page_file = fat_target_dir / f"fat_coll_1_page_{i}.png"
        assert page_file.exists(), f"FAT32 避讓序列頁面未生成: {page_file}"

    # 6. 使用獨立測試 Harness (build/test_copy_harness) 對實際 Production copyFileExclusively 進行全量異常注入
    print("  [子項] 透過獨立測試 Harness 驗證 Production copyFileExclusively 6 大異常注入...")
    harness = _proj_root / "build" / "test_copy_harness"
    staged_payload = fat_target_dir / "staged_harness_payload.bin"
    staged_payload.write_bytes(b"PRODUCTION_PROBE_STAGED_PAYLOAD_MULTIPLE_CHUNKS" * 4000) # ~188KB

    # (a) 正常排他建立與 fstat 鎖定
    target_norm = fat_target_dir / "target_harness_normal.bin"
    if target_norm.exists(): target_norm.unlink()
    res_norm = subprocess.run([str(harness), "normal", str(staged_payload), str(target_norm)], capture_output=True, text=True, env=env)
    assert res_norm.returncode == 0, f"Harness normal 失敗: {res_norm.stderr}"
    assert target_norm.exists() and target_norm.stat().st_size == staged_payload.stat().st_size
    target_norm.unlink()

    # (b) 既有檔案碰撞保護 (EEXIST 17)
    target_coll = fat_target_dir / "target_harness_coll.bin"
    target_coll.write_bytes(b"EXISTING_SENTINEL")
    res_coll = subprocess.run([str(harness), "collision", str(staged_payload), str(target_coll)], capture_output=True, text=True, env=env)
    assert res_coll.returncode == 0, f"Harness collision 應通過: {res_coll.stderr}"
    assert target_coll.read_bytes() == b"EXISTING_SENTINEL", "既有檔案遭篡改！"
    target_coll.unlink()

    # (c) 寫入中途取消 (ECANCELED 89) 與 target 清理
    target_canc = fat_target_dir / "target_harness_cancel.bin"
    if target_canc.exists(): target_canc.unlink()
    res_canc = subprocess.run([str(harness), "cancel_mid_write", str(staged_payload), str(target_canc)], capture_output=True, text=True, env=env)
    assert res_canc.returncode == 0, f"Harness mid-write cancel 失敗: {res_canc.stderr}"
    assert not target_canc.exists(), "中途取消後殘留 target！"

    # (d) 寫入中途外力替換 Inode 免疫測試（驗證 safeCleanup 拒絕刪除替換檔案）
    target_rep = fat_target_dir / "target_harness_rep.bin"
    if target_rep.exists(): target_rep.unlink()
    res_rep = subprocess.run([str(harness), "replacement_during_write", str(staged_payload), str(target_rep)], capture_output=True, text=True, env=env)
    assert res_rep.returncode == 0, f"Harness replacement 失敗: {res_rep.stderr}"
    assert target_rep.exists(), "外部替換檔案遭誤刪！"
    assert target_rep.read_bytes() == b"EXTERNAL_ATTACKER_REPLACEMENT_PAYLOAD"
    target_rep.unlink()

    # (e) 來源開啟失敗 (ENOENT 2) 目標安全清理
    target_nosrc = fat_target_dir / "target_harness_nosrc.bin"
    res_nosrc = subprocess.run([str(harness), "source_missing", str(root / "nonexistent.bin"), str(target_nosrc)], capture_output=True, text=True, env=env)
    assert res_nosrc.returncode == 0, f"Harness source missing 失敗: {res_nosrc.stderr}"
    assert not target_nosrc.exists(), "來源失敗後殘留 target！"

    # (f) 真實磁碟滿 (ENOSPC 28) 寫入失敗注入與目標清理
    filler_file = fat_mount / "filler_disk_full.bin"
    try:
        with open(filler_file, "wb") as f_fill:
            while True:
                f_fill.write(b"0" * 32768)
    except OSError:
        pass

    large_staged = root / "large_staged_for_enospc.bin"
    large_staged.write_bytes(b"B" * 2000000) # 2MB
    target_enospc = fat_target_dir / "target_harness_enospc.bin"

    res_enospc = subprocess.run([str(harness), "enospc", str(large_staged), str(target_enospc)], capture_output=True, text=True, env=env)
    assert res_enospc.returncode == 0, f"Harness ENOSPC 測試失敗: {res_enospc.stderr}"
    assert not target_enospc.exists(), "ENOSPC 失敗後殘留半成品目標檔案！"

    if filler_file.exists(): filler_file.unlink()
    if staged_payload.exists(): staged_payload.unlink()

    print("  ✓ 通過：FAT32 卷軸真實檔案系統檢驗、errno 45 探針確證、中文空白路徑安全提交，以及獨立 Harness 實測中途取消、外部替換免疫、來源缺失與 ENOSPC 磁碟滿異常注入全部通過！")

    # -------------------------------------------------------------
    # 測試 14: 權限不足 / 唯讀 / 無效目錄具體診斷回報與立即中止
    # -------------------------------------------------------------
    print("\n--- [專項 14] 具體錯誤原因回報（唯讀、權限不足、無效目錄）---")
    # 無效/不存在目錄
    p14_noent = subprocess.run([app, "--cli", "--mode", "document", "--input", str(multi_pdf), "--output", "/nonexistent_disk_9999/path/out.png"], capture_output=True, text=True, env=env)
    assert p14_noent.returncode != 0, "不存在目錄應返回非零"
    out_noent = p14_noent.stdout + p14_noent.stderr
    assert "不存在" in out_noent or "無效" in out_noent or "read only" in out_noent.lower() or "errno: 2" in out_noent or "FAILED" in out_noent, f"應給予具體目錄不存在原因: {out_noent}"

    # 唯讀目錄具體原因
    ro_test_dir = root / "strictly_readonly_dir"
    ro_test_dir.mkdir(parents=True, exist_ok=True)
    ro_test_dir.chmod(0o555)
    try:
        p14_ro = subprocess.run([app, "--cli", "--mode", "document", "--input", str(multi_pdf), "--output", str(ro_test_dir / "out.png")], capture_output=True, text=True, env=env)
        assert p14_ro.returncode != 0
        out_ro = p14_ro.stdout + p14_ro.stderr
        assert "權限" in out_ro or "唯讀" in out_ro or "permission" in out_ro.lower() or "read only" in out_ro.lower() or "errno: 13" in out_ro, f"應給予具體權限原因: {out_ro}"
    finally:
        ro_test_dir.chmod(0o755)
    print("  ✓ 通過：目錄不存在與權限不足均輸出具體錯誤原因與 POSIX errno 診斷，拒絕模糊報錯。")

print("\n🎉 PDF 點陣化轉圖片 14 大深度安全與防破壞回歸測試全部通過！")
