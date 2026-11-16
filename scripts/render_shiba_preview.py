#!/usr/bin/env python3
import os
from PIL import Image, ImageDraw

# 24x24 Pixel Palette
PALETTE = {
    '.': (0, 0, 0, 0),             # Transparent
    'O': (235, 120, 42, 255),      # Warm Shiba Orange #EB782A
    'D': (184, 80, 20, 255),       # Deep Orange Shadow #B85014
    'W': (255, 248, 238, 255),     # Cream White #FFF8EE (Muzzle, eyebrows, chest)
    'L': (244, 226, 204, 255),     # Warm Soft Cream #F4E2CC (Transition)
    'P': (248, 172, 164, 255),     # Soft Blush Pink #F8ACA4 (Inner ear, blush)
    'K': (44, 34, 30, 255),        # Charcoal Dark #2C221E (Eyes, nose, outlines)
    'T': (232, 92, 105, 255),      # Tongue Pink #E85C69
    'Y': (255, 210, 50, 255),      # Gold Star Sparkle #FFD232
    'B': (95, 175, 235, 255),      # Sky Blue Sweatdrop #5FAFEB
    'S': (220, 210, 195, 255),     # Ground shadow #DCD2C3
}

# 24x24 Grids

# ----------------- IDLE (待機坐姿・麻糬眉點・立體三角耳・捲尾呼吸搖晃) -----------------
IDLE_0 = [
    "........................",
    "....DD............DD....",
    "...DOOD..........DOOD...",
    "...DOOPD........DOOPD...",
    "...DOOPD........DOOPD...",
    "..DOOOPDD......DDOOOPD..",
    "..DOOOOOODDDDDDOOOOOOD..",
    ".DOOOOOOOOOOOOOOOOOOOOD.",
    ".DOOWWOOOOOOOOOOOOWWOOD.", # 清楚可愛的麻糬眉點 (W W)
    ".DOOWWOOOKOOOOOKOOWWOOD.", # 圓黑眼睛 (K) 襯托白眉
    "DOOOOOOOKKOOKKOOOOOOOOOD", # 眼睛與輪廓
    "DOOOWWWWOOOOOOOOWWWWOOOD", # 飽滿白頰 (Urajiro)
    "DOOWWWWWWWWWWWWWWWWWWOOD", # 奶油口鼻區
    "DOOWWWWWWWKKWWWWWWWWWOOD", # 可愛小黑鼻 (KK)
    ".DOWWWWWWKTTKWWWWWWWWOD.", # 咪咪笑嘴 (KTTK)
    ".DOOWWWWWWWWWWWWWWWWOOD.", # 下巴弧線
    "..DOOOOOOOWWWWOOOOOOD...", # 豐滿頸部
    "..DOOOOOOWWWWWWOOOOD..DD", # 胸口白毛，右側捲尾 (DD/OO)
    ".DOOOOOOOWWWWWWOOOOD.DOO",
    ".DOOOWWOOWWWWWWOOWOODDOO", # 短萌雙前爪 (W W)
    ".DOOWWWWOOWWWWOOWWWODDOO",
    "..DWWWWD.DWWWWD.DWWWDDO.",
    "...DDDD...DDDD...DDD.D..", # 爪底陰影
    "........................"
]

IDLE_1 = [
    "........................",
    "....DD............DD....",
    "...DOOD..........DOOD...",
    "...DOOPD........DOOPD...",
    "...DOOPD........DOOPD...",
    "..DOOOPDD......DDOOOPD..",
    "..DOOOOOODDDDDDOOOOOOD..",
    ".DOOOOOOOOOOOOOOOOOOOOD.",
    ".DOOWWOOOOOOOOOOOOWWOOD.", # 麻糬眉點
    ".DOOWWOOOKOOOOOKOOWWOOD.", # 圓黑眼睛
    "DOOOOOOOKKOOKKOOOOOOOOOD",
    "DOOOWWWWOOOOOOOOWWWWOOOD", # 白頰
    "DOOWWWWWWWWWWWWWWWWWWOOD",
    "DOOWWWWWWWKKWWWWWWWWWOOD", # 小黑鼻
    ".DOWWWWWWKTTKWWWWWWWWOD.", # 微笑嘴
    ".DOOWWWWWWWWWWWWWWWWOOD.",
    "..DOOOOOOOWWWWOOOOOOD.DD", # 捲尾擺動換位
    "..DOOOOOOWWWWWWOOOOD.DOO",
    ".DOOOOOOOWWWWWWOOOODDOOD",
    ".DOOOWWOOWWWWWWOOWOODDO.",
    ".DOOWWWWOOWWWWOOWWWODD..",
    "..DWWWWD.DWWWWD.DWWWD...",
    "...DDDD...DDDD...DDD....",
    "........................"
]

# ----------------- CONVERTING (奔跑轉檔・側身飛躍・飄逸捲尾・元氣張嘴) -----------------
CONV_0 = [
    "........................",
    "........DD..............",
    ".......DOOD.......DD....",
    "......DOOPD......DOOD...",
    ".....DOOOPDDDDDDDOOPD...",
    "....DOOOOOOOOOOOOOOPD...",
    "...DOOOOOOOOOOOOOOOOD...",
    "..DOOWWOOOOOOOOOOOOD....", # 眉點
    "..DOOWWOOKOOOOOOOOOD....", # 專注眼神
    ".DOOOOOOKKOOOOOOOOD.DDD.",
    ".DOOWWWWOOOOOOOOOODDOOOD", # 側面捲尾高高捲起
    "DOOWWWWWWWWWWOOOOODDOOOD",
    "DOOWWWWWKKWWWWWWWOODDOOD", # 鼻尖
    ".DOWWWWWWWKTTKWWWWOOODD.", # 吐舌喘氣
    "..DOOWWWWWWWWWWWWOOOD...",
    "...DOOOOOOWWWWWWOOOOD...",
    "....DOOOOOOOOOOOOOOD....",
    ".....DOOOOOOOOOOOOOD....",
    "......DOOWWWOOOWWWO.....", # 四肢奔跑跨步
    "......DOWWWOD.DOWWWOD...",
    ".......DWWWD...DWWWD....",
    "........DDD.....DDD.....",
    "........................",
    "........................"
]

CONV_1 = [
    "........................",
    "........DD..............",
    ".......DOOD.......DD....",
    "......DOOPD......DOOD...",
    ".....DOOOPDDDDDDDOOPD...",
    "....DOOOOOOOOOOOOOOPD...",
    "...DOOOOOOOOOOOOOOOOD.DD",
    "..DOOWWOOOOOOOOOOOOD.DOO", # 眉點
    "..DOOWWOOKOOOOOOOOODDOOD", # 眼神
    ".DOOOOOOKKOOOOOOOOODDOOD", # 捲尾跳動
    ".DOOWWWWOOOOOOOOOOODDOOD",
    "DOOWWWWWWWWWWOOOOOODDD..",
    "DOOWWWWWKKWWWWWWWOOOD...",
    ".DOWWWWWWWKTTKWWWWOOD...",
    "..DOOWWWWWWWWWWWWOOOD...",
    "...DOOOOOOWWWWWWOOOOD...",
    "....DOOOOOOOOOOOOOOD....",
    ".....DOOOOOOOOOOOOOD....",
    ".......DOWWWODDOWWWOD...", # 懸空小跑步
    "........DWWWDD.DWWWD....",
    ".........DDD....DDD.....",
    "........................",
    "........................",
    "........................"
]

# ----------------- COMPLETED (開心大勝・笑瞇瞇笑臉・歡呼舉爪・金色星星) -----------------
COMP_0 = [
    "...YY...................",
    "..YYYY..................",
    "...YY...DD............DD",
    ".......DOOD..........DOO",
    "......DOOPD........DOOPD",
    ".....DOOOPDD......DDOOOP",
    "....DOOOOOODDDDDDOOOOOOD",
    "...DOOOOOOOOOOOOOOOOOOOD",
    "..DOOWWOOOOOOOOOOOOWWOOD", # 眉點
    "..DOOWW..KK....KK..WWOOD", # 開心笑眼瞇瞇 (^ ^)
    ".DOOOOO..KK....KK.OOOOOD",
    "DOOOWWWWOOOOOOOOWWWWOOOD", # 飽滿白頰
    "DOOWWWWWWWWWWWWWWWWWWOOD",
    "DOOWWWWWWWKKWWWWWWWWWOOD", # 黑鼻
    ".DOWWWWWKTTTTKWWWWWWWOD.", # 開懷大笑大舌頭
    ".DOOWWWWKTTTTKWWWWWWWOOD",
    "..DOOOOOOWWWWOOOOOOOOD..",
    ".DOOWWWOOWWWWOOOWWWOD...", # 兩隻短手開心舉起！
    ".DOWWWWOODWWWD.DOWWWOD..",
    "..DWWWWD..DDD...DWWWD...",
    "...DDDD..........DDDD...",
    "........................",
    "........................",
    "........................"
]

COMP_1 = [
    "...................YY...",
    "..................YYYY..",
    "...YY...DD.........YY.DD",
    "..YYYY.DOOD..........DOO",
    "...YY.DOOPD........DOOPD",
    ".....DOOOPDD......DDOOOP",
    "....DOOOOOODDDDDDOOOOOOD",
    "...DOOOOOOOOOOOOOOOOOOOD",
    "..DOOWWOOOOOOOOOOOOWWOOD", # 眉點
    "..DOOWW..KK....KK..WWOOD", # 笑眼
    ".DOOOOO..KK....KK.OOOOOD",
    "DOOOWWWWOOOOOOOOWWWWOOOD",
    "DOOWWWWWWWWWWWWWWWWWWOOD",
    "DOOWWWWWWWKKWWWWWWWWWOOD",
    ".DOWWWWWKTTTTKWWWWWWWOD.", # 大笑
    ".DOOWWWWKTTTTKWWWWWWWOOD",
    "..DOOOOOOWWWWOOOOOOOOD.D", # 捲尾也開心搖動
    ".DOOWWWOOWWWWOOOWWWOD.DO",
    ".DOWWWWOODWWWD.DOWWWODDO",
    "..DWWWWD..DDD...DWWWDDO.",
    "...DDDD..........DDDD...",
    "........................",
    "........................",
    "........................"
]

# ----------------- FAILED (垂耳飛機耳・困惑流汗・委屈眼神) -----------------
FAIL_0 = [
    "........................",
    "........................",
    "........................",
    "..DDDD............DDDD..", # 垂耳/飛機耳
    ".DOOOOD..........DOOOOD.",
    ".DOOPPDDDDDDDDDDDDOOPPD.",
    ".DOOOOOOOOOOOOOOOOOOOOD.",
    ".DOOWWOOOOOOOOOOOOWWOOD.", # 眉點
    ".DOOWW.KK......KK.WWOOD.", # 委屈八字眼 (困惑)
    "DOOOOO.KK......KK.OOOOOD",
    "DOOOWWWWOOOOOOOOWWWWOOOD",
    "DOOWWWWWWWWWWWWWWWWWWOOD",
    "DOOWWWWWWWKKWWWWWWWWWOOD", # 黑鼻
    ".DOWWWWWWWKKWWWWWWWWWOD.", # 抿嘴扁嘴
    ".DOOWWWWWWWWWWWWWWWWOOD.",
    "..DOOOOOOOWWWWOOOOOOD...",
    "..DOOOOOOWWWWWWOOOOD..BB", # 藍色大汗滴 (BB)
    ".DOOOOOOOWWWWWWOOOOD.BBB",
    ".DOOOWWOOWWWWWWOOWOODBBB",
    ".DOOWWWWOOWWWWOOWWWOD.BB",
    "..DWWWWD.DWWWWD.DWWWD...",
    "...DDDD...DDDD...DDD....",
    "........................",
    "........................"
]

FAIL_1 = [
    "........................",
    "........................",
    "........................",
    "..DDDD............DDDD..", # 垂耳
    ".DOOOOD..........DOOOOD.",
    ".DOOPPDDDDDDDDDDDDOOPPD.",
    ".DOOOOOOOOOOOOOOOOOOOOD.",
    ".DOOWWOOOOOOOOOOOOWWOOD.", # 眉點
    ".DOOWW.KK......KK.WWOOD.", # 委屈八字眼
    "DOOOOO.KK......KK.OOOOOD",
    "DOOOWWWWOOOOOOOOWWWWOOOD",
    "DOOWWWWWWWWWWWWWWWWWWOOD",
    "DOOWWWWWWWKKWWWWWWWWWOOD",
    ".DOWWWWWWWKKWWWWWWWWWOD.",
    ".DOOWWWWWWWWWWWWWWWWOOD.",
    "..DOOOOOOOWWWWOOOOOOD...",
    "..DOOOOOOWWWWWWOOOOD....",
    ".DOOOOOOOWWWWWWOOOOD..BB", # 汗滴滴落
    ".DOOOWWOOWWWWWWOOWOODBBB",
    ".DOOWWWWOOWWWWOOWWWOD.BB",
    "..DWWWWD.DWWWWD.DWWWD...",
    "...DDDD...DDDD...DDD....",
    "........................",
    "........................"
]

def render_grid_to_image(grid, scale=12):
    height = len(grid)
    width = len(grid[0])
    img = Image.new('RGBA', (width * scale, height * scale), (250, 248, 245, 255)) # Cream White Background #FAF8F5
    draw = ImageDraw.Draw(img)
    
    for r, row in enumerate(grid):
        for c, char in enumerate(row):
            rgba = PALETTE.get(char, (0, 0, 0, 0))
            if rgba[3] > 0:
                draw.rectangle([
                    c * scale, r * scale,
                    (c + 1) * scale - 1, (r + 1) * scale - 1
                ], fill=rgba)
    return img

def main():
    from pathlib import Path
    project_root = Path(__file__).resolve().parent.parent
    out_dir = str(project_root / "previews")
    os.makedirs(out_dir, exist_ok=True)
    
    states = [
        ("idle_0", IDLE_0),
        ("idle_1", IDLE_1),
        ("converting_0", CONV_0),
        ("converting_1", CONV_1),
        ("completed_0", COMP_0),
        ("completed_1", COMP_1),
        ("failed_0", FAIL_0),
        ("failed_1", FAIL_1)
    ]
    
    rendered = {}
    for name, grid in states:
        img = render_grid_to_image(grid, scale=10) # 240x240 px
        path = os.path.join(out_dir, f"shiba_{name}.png")
        img.save(path)
        rendered[name] = img
        print(f"Rendered: {path}")
        
    # 組合一張 4 態橫向預覽總覽圖
    sheet = Image.new('RGBA', (240 * 4 + 50, 240 + 70), (250, 248, 245, 255))
    draw = ImageDraw.Draw(sheet)
    
    label_states = [
        ("待機 (Idle)", rendered["idle_0"], 10),
        ("轉檔中 (Converting)", rendered["converting_0"], 260),
        ("成功完成 (Completed)", rendered["completed_0"], 510),
        ("失敗困惑 (Failed)", rendered["failed_0"], 760)
    ]
    
    for label, img, x in label_states:
        sheet.paste(img, (x, 50), img)
        draw.text((x + 40, 20), label, fill=(60, 50, 45, 255))
        
    overview_path = os.path.join(out_dir, "shiba_states_overview.png")
    sheet.save(overview_path)
    print(f"Overview saved: {overview_path}")

if __name__ == "__main__":
    main()
