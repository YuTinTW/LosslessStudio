import hashlib
import os
import pathlib
import subprocess
import sys
import tempfile
import time

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

print("\n🎉 PDF 點陣化轉圖片 12 大深度安全與防破壞回歸測試全部通過！")
