#!/usr/bin/env python3
import os
import subprocess
from PIL import Image, ImageDraw, ImageFont

def create_icon():
    size = 1024
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # macOS style squircle background with modern deep blue/cyan gradient
    # Simulate rounded rectangle
    margin = 80
    r = 220
    # Gradient background
    base = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    base_draw = ImageDraw.Draw(base)
    
    for y in range(margin, size - margin):
        ratio = (y - margin) / float(size - 2 * margin)
        # Gradient from deep royal blue (28, 55, 140) to cyan violet (45, 140, 220)
        r_c = int(24 + ratio * 30)
        g_c = int(50 + ratio * 90)
        b_c = int(140 + ratio * 95)
        base_draw.line([(margin, y), (size - margin, y)], fill=(r_c, g_c, b_c, 255))
        
    mask = Image.new('L', (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([margin, margin, size - margin, size - margin], radius=r, fill=255)
    
    img.paste(base, (0, 0), mask)
    
    # Draw geometric lossless badge in the center
    # Outer ring
    center = size // 2
    draw.ellipse([center - 240, center - 240, center + 240, center + 240], outline=(255, 255, 255, 200), width=18)
    
    # Diamond / Prism representing lossless fidelity
    poly = [
        (center, center - 160),
        (center + 160, center),
        (center, center + 160),
        (center - 160, center)
    ]
    draw.polygon(poly, fill=(255, 255, 255, 240))
    
    # Inner infinity / copy symbol
    draw.ellipse([center - 80, center - 50, center, center + 50], outline=(28, 70, 160, 255), width=16)
    draw.ellipse([center, center - 50, center + 80, center + 50], outline=(28, 70, 160, 255), width=16)
    
    # Save iconset
    iconset_dir = "/tmp/LosslessStudio.iconset"
    os.makedirs(iconset_dir, exist_ok=True)
    
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    for s in sizes:
        resized = img.resize((s, s), Image.Resampling.LANCZOS)
        if s <= 512:
            resized.save(f"{iconset_dir}/icon_{s}x{s}.png")
        if s >= 32:
            half = s // 2
            resized.save(f"{iconset_dir}/icon_{half}x{half}@2x.png")
            
    # Run iconutil
    from pathlib import Path
    project_root = Path(__file__).resolve().parent.parent
    out_icns = str(project_root / "Resources" / "AppIcon.icns")
    os.makedirs(os.path.dirname(out_icns), exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", out_icns], check=True)
    print("AppIcon.icns generated at:", out_icns)

if __name__ == "__main__":
    create_icon()
