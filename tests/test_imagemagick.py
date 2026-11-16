"""Synthetic external image tests. Usage: python3 tests/test_imagemagick.py BINARY MAGICK"""
import hashlib
import os
import pathlib
import struct
import subprocess
import sys
import tempfile

binary, magick = map(str, map(pathlib.Path, sys.argv[1:3]))
magick_dir = pathlib.Path(magick).resolve().parent.parent
coders_dir = magick_dir / "lib" / "ImageMagick" / "modules-Q16HDRI" / "coders"
env = os.environ.copy()
if coders_dir.exists():
    env["MAGICK_CODER_MODULE_PATH"] = str(coders_dir)
    env["MAGICK_CONFIGURE_PATH"] = str(magick_dir / "etc" / "ImageMagick-7")

count = 0
with tempfile.TemporaryDirectory(prefix='lossless-image-tests-') as folder:
    root = pathlib.Path(folder)
    def command(*args):
        return subprocess.run([magick, *map(str, args)], env=env, check=True, capture_output=True).stdout
    def convert(src, out, mode='image', succeeds=True):
        global count
        before = src.read_bytes()
        p = subprocess.run([binary, '--cli', '--input', str(src), '--output', str(out), '--mode', mode], env=env, capture_output=True)
        assert (p.returncode == 0) == succeeds, p.stdout.decode(errors='replace')
        assert src.read_bytes() == before
        if not succeeds:
            assert not out.exists()
        count += 1
    for depth in (8, 16):
        for channels in ('rgb', 'rgba'):
            vals = []
            for y in range(9):
                for x in range(13):
                    vals.extend(((x*3911+y*217)%65536, (x*719+y*8123)%65536, (x*1009+y*413)%65536))
                    if channels == 'rgba': vals.append((x*541+y*7001)%65536)
            raw = root/'source.raw'
            raw.write_bytes(bytes(v//257 for v in vals) if depth == 8 else struct.pack('>'+'H'*len(vals), *vals))
            src = root/f'{channels}{depth}.png'
            command('-size', '13x9', '-depth', depth, '-endian', 'MSB', f'{channels}:{raw}', src)
            samples = command(src, '-depth', 16, '-endian', 'MSB', 'rgba:-')
            for ext in ('png', 'tiff', 'bmp', 'webp'):
                out = root/f'{channels}{depth}-out.{ext}'
                convert(src, out, succeeds=True)
                if depth == 8 or ext in ('png', 'tiff'):
                    assert command(out, '-depth', 16, '-endian', 'MSB', 'rgba:-') == samples
            for ext in ('jpg', 'webp'):
                convert(src, root/f'lossy-{channels}{depth}.{ext}', mode='image-lossy', succeeds=True)
    profile = pathlib.Path('/System/Library/ColorSync/Profiles/AdobeRGB1998.icc')
    if profile.exists():
        src = root/'metadata.jpg'
        command(root/'rgb8.png', '-profile', profile, src)
        exif = b'Exif\0\0'+b'II'+struct.pack('<HIH',42,8,1)+struct.pack('<HHI',274,3,1)+struct.pack('<H',6)+b'\0\0'+b'\0\0\0\0'
        jpeg = src.read_bytes()
        src.write_bytes(jpeg[:2]+b'\xff\xe1'+struct.pack('>H',len(exif)+2)+exif+jpeg[2:])
        for ext in ('png', 'webp', 'tiff', 'bmp'):
            out = root/f'metadata-out.{ext}'
            convert(src, out, succeeds=True)
            if ext in ('png', 'webp'):
                assert command('identify', '-format', '%[EXIF:Orientation]', out) == b'6'
                for kind in ('icc', 'exif'):
                    assert command(src, kind+':-') == command(out, kind+':-')
    # 8BIM (Photoshop 3.0 APP13) regression test
    bim_block = b"Photoshop 3.0\x008BIM\x04\x04\x00\x00\x00\x00\x00?\x1c\x01Z\x00\x03\x1b%G\x1c\x02\x00\x00\x02\x00\x02\x1c\x02?\x00\x06172626\x1c\x02>\x00\x0820220607\x1c\x027\x00\x0820220607\x1c\x02<\x00\x06172626\x008BIM\x04%\x00\x00\x00\x00\x00\x10XZ\xe9\x9a\x89\x8f\xc2\xac\x15\xe8\xd4{\xb9\xd9E*"
    app13 = b"\xff\xed" + struct.pack(">H", len(bim_block) + 2) + bim_block
    bim_base_jpg = root/'base_bim.jpg'
    command(root/'rgb8.png', bim_base_jpg)
    base_bytes = bim_base_jpg.read_bytes()
    bim_src = root/'with_8bim.jpg'
    bim_src.write_bytes(base_bytes[:2] + app13 + base_bytes[2:])
    bim_png = root/'with_8bim_out.png'
    convert(bim_src, bim_png, succeeds=True)
    assert command(bim_src, '8bim:-') == command(bim_png, '8bim:-')
    assert command(bim_src, 'iptc:-') == command(bim_png, 'iptc:-')
    assert command(bim_src, '-depth', 16, '-endian', 'MSB', 'rgba:-') == command(bim_png, '-depth', 16, '-endian', 'MSB', 'rgba:-')
    convert(bim_src, root/'with_8bim_out.bmp', succeeds=True)
    convert(bim_src, root/'with_8bim_out.webp', succeeds=True)
    multi = root/'multi.tiff'
    command(root/'rgb8.png', root/'rgb8.png', multi)
    convert(multi, root/'multi.png', succeeds=False)
    corrupt = root/'bad.png'; corrupt.write_bytes(b'not an image')
    convert(corrupt, root/'bad-out.png', succeeds=False)
    # A pre-existing destination is never overwritten.
    src = root/'rgb8.png'; out = root/'existing.png'; out.write_bytes(b'preserve me')
    p = subprocess.run([binary, '--cli', '--input', str(src), '--output', str(out), '--mode', 'image'], capture_output=True)
    assert p.returncode != 0 and out.read_bytes() == b'preserve me'; count += 1
    assert not list(root.glob('.lossless-image-*'))
print(f'PASS {count} conversions/rejections; normalized samples, sources, collision and cleanup checked')
