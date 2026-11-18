# LosslessStudio (無損多媒體處理工作室)

[English user guide](Resources/USER_GUIDE.en.md) · [English installation guide](Resources/INSTALLATION_GUIDE.en.txt)

macOS 原生高效、安全且嚴格遵守無損原則的影音與圖片批次轉檔工作室。

---

## 🌟 核心理念與技術原則

1. **原檔安全防護（Never Overwrite Source）**：嚴格禁止覆寫來源檔案。支援跨路徑同 Inode 辨識（防止硬連結或符號連結繞過），若輸出與來源指向相同檔案，系統於引擎層立即阻斷；併發輸出時採用執行緒安全的原子檔名預約註冊表（`reservedOutputPaths`），徹底杜絕覆蓋風險。
2. **誠實技術揭露（No Fake Lossless）**：業界不存在「任何格式隨意互轉皆無損」的技術。本工具清楚分開呈現三種不同層次的無損，並主動拒絕偽稱無損的操作：
   * **封裝直通 (Remux / Stream Copy, `-c copy`)**：不經解碼與重編碼，僅變換容器包裝（如 MP4 轉 MKV）。保留 100% 原始編碼位元流，零畫質損失，毫秒級完成。若目標容器不相容來源編碼（如 WebM 封裝 H.264），直接拒絕並提示原因。
   * **像素級數學無損轉碼 (Lossless Transcode - FFV1)**：使用數學無損演算法（如 FFV1 視訊 + FLAC 音訊），保證解碼後的每一格像素與取樣點與來源 100% framemd5 一致。
   * **視覺接近無損 (Visual Lossless - Apple ProRes 4444 XQ)**：ProRes 為 Apple 針對高動態範圍後期調色打造的 12-bit 高品質編碼，本質為視覺無損（Near-Lossless），因 DCT 轉換微幅捨入，解碼像素雜湊不可保證 100% 位元一致，系統誠實標註為視覺無損而非數學無損。
   * **x264 限制說明**：x264 CRF 0 僅限 8-bit YUV 4:2:0 來源達到無損。若來源為 10-bit 或 4:2:2/4:4:4，系統主動阻斷降採樣操作，引導改用 FFV1 MKV 典藏模式。
   * **圖片無損轉換 (Lossless Image)**：基於 Apple 原生 ImageIO 與 CoreGraphics，支援 PNG、TIFF、Lossless WebP、BMP 相互轉換，完整保留 EXIF、GPS、IPTC 與 ICC 色彩設定檔。對於 JPEG 等本質有損格式，直接拒絕並清楚說明原因；同時攔截多影格動圖與 16-bit 降轉 WebP 操作。
   * **無損音訊互轉 (Lossless Audio)**：支援廣播級未壓縮 WAV (PCM 16/24/32-bit)、FLAC、Apple Lossless (ALAC / .m4a)、AIFF (.aiff/.aif) 彼此無損互轉。解碼 PCM 音訊採樣點對點 1:1 MD5 比對，保證 100% 數學無損。
   * **有損／相容性降轉模式 (Lossy Audio / Downsampling Mode)**：支援 MP3 (libmp3lame 320k/256k/192k/128k)、AAC (.m4a/.aac)、OGG (.ogg, vorbis)、OPUS (.opus, libopus)，並支援取樣率降轉 (例如 96k/48k -> 44.1k)。界面與驗證狀態誠實標示為「有損轉換 (不進行位元比對)」，絕不虛偽宣稱無損。
3. **完全自包含可散布引擎（Self-Contained Bundle）**：
   - App Bundle 內嵌 Apple Silicon 原生 `ffmpeg` 與 `ffprobe`（位於 `Contents/Resources/`），並以 `bundle_dependencies.py` 自動遞迴打包 17 個非系統動態函式庫至 `Contents/Frameworks/`（約 36MB）。
   - 所有外部載入路徑均以 `install_name_tool` 重寫為 `@rpath/`，經隔離環境（`env -i`，無 Homebrew PATH 與 DYLD）實測驗證，完全零外部依賴，無需使用者安裝 Homebrew。

---

## 🎨 日系日式柴犬像素動態與溫潤配色（Argon 協作生成）

主介面採用「日式奶油白（`#FAF8F5`）與暖橘（`#E8823A`）」溫潤低飽和配色，並整合透過 macOS GUI 調用 **4 Argon** 生成的純 SwiftUI 點陣柴犬動態組件（`ShibaPixelView.swift`）：
* **4 種運作狀態**：閒置晃尾 (`idle`)、處理中跑步 (`converting`)、成功搖尾開心跳躍 (`completed`)、失敗垂耳困惑搖頭 (`failed`)。
* **無障礙支援**：偵測系統 `accessibilityReduceMotion`，開啟時自動轉為靜態像素構圖。

---

## 🔍 即時編碼監控與串流對比面板（Encoding Monitor Window）

提供獨立的專業編碼監控視窗（`EncodingMonitorView`）：
1. **輸入 vs 輸出雙向 Probe 對比**：逐軌分析（視訊軌、音訊軌、字幕軌），呈現編碼格式、Profile、像素格式（pix_fmt）、解析度、色彩空間、色深、聲道數與取樣率。
2. **直通 vs 重編碼清晰標籤**：明確區分 Stream Copy 與 Re-encode。
3. **5 級驗證狀態徽章**：
   * `✓ 位元流完全吻合 (Stream Copy)`
   * `✓ 像素級數學無損 (FFV1 / 點陣 1:1)`
   * `ℹ 視覺接近無損 (Apple ProRes 4444 XQ)`
   * `⚠ 偵測到降採樣或色深損失 (已主動阻斷)`
   * `✗ 拒絕執行 (有損格式 / 不相容)`
4. **真實進度監控**：解析 `ffmpeg -progress`，即時呈現真實轉碼進度、處理速度（x倍速）與 ETA，資料不足時顯示「未知/不適用」。
5. **完整執行日誌與報告導出**：展示實際執行之命令列（含安全防護參數），支援一鍵複製 stderr 診斷訊息與導出 JSON 檢驗報告。

---

## 📁 專案目錄結構

```text
LosslessStudio/
├── src/
│   ├── main.swift                   # App 入口點（支援 GUI 啟動與 CLI 批次/無頭測試）
│   ├── Engine/
│   │   ├── Types.swift              # 串流分析模型、編碼對比、5 級驗證狀態列舉
│   │   ├── Limitations.swift        # 容器相容性矩陣、技術限制與防護警語
│   │   ├── FFmpegRunner.swift       # FFmpeg 封裝直通/轉碼、-progress 解析、Inode 比對與 MD5 驗證
│   │   ├── ImageLosslessEngine.swift# 原生 Apple ImageIO 圖片無損轉換引擎與像素比對
│   │   └── ConversionManager.swift  # 異步並行佇列（影音/圖片獨立限制）、原子路徑預約、批次鏡像目錄
│   └── UI/
│       ├── ContentView.swift        # 日系暖橘主介面、批次檔案清單、柴犬動態與監控視窗觸發
│       ├── ShibaPixelView.swift     # Argon 生成之純 SwiftUI 點陣柴犬 4 態動畫
│       ├── EncodingMonitorView.swift# 專業即時編碼監控、串流對比與驗證視窗
│       └── LimitationsView.swift    # 技術限制與容器矩陣獨立說明面板
├── Resources/
│   ├── Info.plist                   # macOS 應用程式屬性清單
│   ├── AppIcon.icns                 # macOS 專屬向量繪製圖示
│   ├── LICENSE-FFMPEG.txt           # FFmpeg GPL v2+/LGPL 授權與源碼指引
│   └── 使用說明與安裝指南.txt        # 散布版安裝指南與 Gatekeeper 授權說明
├── scripts/
│   ├── make_icon.py                 # 自動化產生高解析度 AppIcon.icns 腳本
│   ├── build.sh                     # Swift 原生快速編譯腳本
│   ├── bundle_dependencies.py       # 遞迴打包動態函式庫與重寫 @rpath 腳本
│   └── package.sh                   # 打包 .app、Frameworks 嵌入、Ad-hoc 簽章、DMG 與 Zip
├── tests/
│   └── run_tests.sh                 # 包含 9 大自動化測試與 1,000 檔壓力測試腳本
├── dist/
│   ├── LosslessStudio-macOS.zip     # 獨立發行 Zip 壓縮檔 (16MB)
│   └── LosslessStudio.dmg           # 獨立發行 DMG 磁碟映像檔 (17MB)
├── ACCEPTANCE_REPORT.md             # 完整驗收與審查整改報告
└── README.md
```

---

## 🚀 安裝與發行產物（可供外部下載）

* **發行安裝檔**：
  * **DMG 磁碟映像檔**：[LosslessStudio.dmg](https://github.com/YuTinTW/LosslessStudio/releases/latest/download/LosslessStudio.dmg) (**約 21 MB**，內含 Applications 拖曳捷徑、完整內建 Frameworks、授權與安裝說明)
  * **Zip 壓縮檔**：[LosslessStudio-macOS.zip](https://github.com/YuTinTW/LosslessStudio/releases/latest/download/LosslessStudio-macOS.zip) (**約 20 MB**)
* **配套第三方原始碼**：[LosslessStudio-sources.zip](https://github.com/YuTinTW/LosslessStudio/releases/latest/download/LosslessStudio-sources.zip)（約 148 MiB）。
* **全部版本與發行說明**：[GitHub Releases](https://github.com/YuTinTW/LosslessStudio/releases)。
* **本機安裝應用程式**：`/Applications/LosslessStudio.app` 及 `~/Applications/LosslessStudio.app`

### 本機候選包

執行 `./scripts/package.sh`，通過簽章、映像檔完整性與隱私稽核後，專案的 `reports/blackmagic-localization/candidate.*` 會包含 App、DMG 與 ZIP。打包流程只寫入專案內的候選目錄。

### 系統需求與未測宣告
- **硬體架構**：Apple Silicon (arm64, M1 / M2 / M3 / M4)。
- **最低作業系統需求**：macOS 26 (Tahoe) 或更新版本（因內嵌之 FFmpeg、ImageMagick 與其相依動態函式庫最低二進位建置版本為 macOS 26.0；支援 macOS 14/15 舊版本之依賴真重建方案已列為後續排程）。
- **實證範圍與未測宣告**：本建置已於本機隔離環境（`env -i`，無 Homebrew PATH 與 DYLD）實測驗證通過；尚未於未配置任何開發工具之第三方全新乾淨實體機器上進行跨機實測，特此明示。

> **Gatekeeper 提示**：
> 本軟體使用 macOS Ad-hoc 安全本機簽章，不繞過 Gatekeeper。若 macOS 彈出「無法開啟，因為無法驗證開發者」提示，可依標準方式開啟：
> 1. 至「系統設定」>「隱私權與安全性」點擊「仍要打開」。
> 2. 或在終端機執行：`xattr -cr /Applications/LosslessStudio.app`。
