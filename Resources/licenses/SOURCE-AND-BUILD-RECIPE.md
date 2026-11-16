# LosslessStudio 第三方依賴原始碼與構建規範 (Source & Build Recipe)

本文件依據 GNU General Public License (GPLv2 / GPLv3) 及相關開源授權規範，詳載 LosslessStudio 所內嵌之 FFmpeg、ImageMagick 及所有第三方動態庫之版本、原始碼取得來源、構建配置參數與重現指引。

---

## 1. FFmpeg 8.1.2 (GPLv2 / GPLv3 / LGPLv2.1 / LGPLv3)

- **版本**: `ffmpeg version 8.1.2`
- **授權全文**: 包含 GPLv2 (`FFmpeg-COPYING.GPLv2.txt`)、GPLv3 (`FFmpeg-COPYING.GPLv3.txt`)、LGPLv2.1 (`FFmpeg-COPYING.LGPLv2.1.txt`) 及 LGPLv3 (`FFmpeg-COPYING.LGPLv3.txt`)
- **官方原始碼發布位址**: `https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz`
- **原始碼雜湊 (SHA256)**: `464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c`
- **編譯器**: Apple clang version 21.0.0 (clang-2100.0.123.102)
- **實體構建配置參數 (Exact Configuration)**:
  ```bash
  ./configure \
    --prefix=/opt/homebrew/Cellar/ffmpeg/8.1.2 \
    --enable-shared \
    --enable-pthreads \
    --enable-version3 \
    --cc=clang \
    --host-cflags= \
    --host-ldflags='-Wl,-ld_classic' \
    --enable-gpl \
    --enable-libsvtav1 \
    --enable-libopus \
    --enable-libx264 \
    --enable-libmp3lame \
    --enable-libdav1d \
    --enable-libvmaf \
    --enable-libvpx \
    --enable-libx265 \
    --enable-opencl \
    --enable-openssl \
    --disable-htmlpages \
    --disable-podpages \
    --disable-txtpages \
    --disable-sdl2
  ```
- **核心函式庫版本**:
  - `libavutil`: 60.26.102
  - `libavcodec`: 62.28.102
  - `libavformat`: 62.12.102
  - `libavdevice`: 62.3.102
  - `libavfilter`: 11.14.102
  - `libswscale`: 9.5.102
  - `libswresample`: 6.3.102

---

## 2. ImageMagick 7.1.2-26 (ImageMagick License / Apache 2.0 相容)

- **版本**: `ImageMagick 7.1.2-26 Q16-HDRI aarch64 702175ac4:20260621`
- **官方原始碼發布位址**: `https://github.com/ImageMagick/ImageMagick/releases/download/7.1.2-26/ImageMagick-7.1.2-26.7z`
- **原始碼雜湊 (SHA256)**: `87aceeed7448836ba33bdfc9ae8a5a415ff68be54848d56b858fc92c01198539`
- **特徵旗標**: Cipher DPC HDRI Modules
- **內建代理 (Delegates)**: `bzlib freetype heic jng jpeg lcms ltdl lzma png tiff webp xml zlib zstd`

---

## 3. 內嵌第三方動態程式庫完整清單與授權對照表 (依實際 otool 依賴)

| 函式庫名稱 | 版本 | 授權條款 | 官方原始碼取得來源 |
| :--- | :--- | :--- | :--- |
| **x264** | r3222 (commit b35605a) | GPL v2+ | `https://code.videolan.org/videolan/x264.git` |
| **x265** | 4.2 | GPL v2+ | `https://bitbucket.org/multicoreware/x265_git/downloads/x265_4.2.tar.gz` |
| **dav1d** | 1.5.3 | BSD 2-Clause | `https://code.videolan.org/videolan/dav1d/-/archive/1.5.3/dav1d-1.5.3.tar.bz2` |
| **libopus** | 1.6.1 | BSD 3-Clause | `https://ftp.osuosl.org/pub/xiph/releases/opus/opus-1.6.1.tar.gz` |
| **libvpx** | 1.16.0 | BSD 3-Clause | `https://github.com/webmproject/libvpx/archive/refs/tags/v1.16.0.tar.gz` |
| **lame** | 3.100 | LGPL v2.0 | `https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz` |
| **openssl** | 3.6.3 | Apache 2.0 | `https://github.com/openssl/openssl/releases/download/openssl-3.6.3/openssl-3.6.3.tar.gz` |
| **libvmaf** | 3.2.0 | BSD 2-Clause | `https://github.com/Netflix/vmaf/archive/refs/tags/v3.2.0.tar.gz` |
| **svt-av1** | 4.1.0 | BSD 2-Clause | `https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v4.1.0/SVT-AV1-v4.1.0.tar.bz2` |
| **freetype** | 2.14.3 | FTL / GPLv2 | `https://downloads.sourceforge.net/project/freetype/freetype2/2.14.3/freetype-2.14.3.tar.xz` |
| **libpng** | 1.6.58 | libpng License | `https://downloads.sourceforge.net/project/libpng/libpng16/1.6.58/libpng-1.6.58.tar.xz` |
| **jpeg-turbo** | 3.2.0 | IJG / BSD-3 | `https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.2.0/libjpeg-turbo-3.2.0.tar.gz` |
| **little-cms2** | 2.19.1 | MIT License | `https://downloads.sourceforge.net/project/lcms/lcms/2.19.1/lcms2-2.19.1.tar.gz` |
| **libtool** | 2.5.4 | GPLv2+ / LGPLv2.1+ | `https://ftpmirror.gnu.org/gnu/libtool/libtool-2.5.4.tar.xz` |
| **xz** | 5.8.4 | 0BSD / GPLv2 / LGPLv2.1 | `https://github.com/tukaani-project/xz/releases/download/v5.8.4/xz-5.8.4.tar.gz` |
| **libtiff** | 4.7.2 | libtiff (BSD-like) | `https://download.osgeo.org/libtiff/tiff-4.7.2.tar.gz` |
| **webp** | 1.6.0 | BSD 3-Clause | `https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz` |
| **zstd** | 1.5.7_1 | BSD 3-Clause / GPLv2 | `https://github.com/facebook/zstd/archive/refs/tags/v1.5.7.tar.gz` |

---

## 4. 本機重現與原始碼封裝說明

1. **授權條文存檔**：本發行包附帶之所有第三方授權全文存檔於 `Resources/licenses/`（或 DMG 根目錄之 `licenses/`）。
2. **本地原始碼封裝與公式記錄**：
   - 專案根目錄下設有 `sources/`，其中 `sources/archives/` 存放主要原始碼封裝檔，`sources/receipts/` 存放 Homebrew 原廠安裝收據與 SPDX SBOM，`sources/formulas/` 存放官方公式。完整雜湊清單參見 `sources/MANIFEST.txt`。
3. **可重現性分析與客觀限制**：
   - 使用上述原始碼、公式與配置參數，在 macOS arm64 環境下編譯，可產出功能完全一致且相容之二進位檔。
   - 由於 macOS Mach-O 執行檔與動態函式庫在編譯連接時包含隨機產生的 `LC_UUID` 與編譯時間戳頭部，不同時間或環境下編譯產出之二進位檔 SHA256 雜湊值客觀上不會 100% 相同，特此說明。
