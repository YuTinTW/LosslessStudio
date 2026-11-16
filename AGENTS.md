# LosslessStudio 專案協作與檔案所有權規範 (AGENTS.md)

本文件定義多助手協同開發 LosslessStudio 專案時之職責分工、檔案所有權與防衝突準則。

---

## 👥 角色與職責分工

### 1. 程式開發員 (agent-247d2490-f1d4-462f-adb8-8cc76ea2f6e4)
- **職責**：核心轉檔與批次引擎實作、無損演算法校驗、錯誤修復、全域自動化測試、動態庫自包含打包（DMG/ZIP）與程式碼簽章。
- **獨佔管理路徑**：
  - `src/Engine/` 全部檔案（`Types.swift`, `FFmpegRunner.swift`, `ImageLosslessEngine.swift`, `ConversionManager.swift`, `Limitations.swift`）
  - `src/main.swift`（CLI 與 App 啟動入口）
  - `scripts/`（`build.sh`, `package.sh`, `bundle_dependencies.py`, `make_icon.py`）
  - `tests/`（`run_tests.sh` 及其測試套件）
  - `dist/`（正式發行產物 DMG 與 ZIP）

### 2. 介面與動畫開發員 (agent-78ea3951-cc74-42a8-a278-9784e793aef1)
- **職責**：柴犬像素藝術重塑、4 態點陣動畫繪製（待機/轉檔/完成/失敗）、SwiftUI 渲染組件精修、UI 預覽產出與使用者偏好對齊。
- **獨佔管理路徑**：
  - `src/UI/ShibaPixelView.swift`（柴犬動畫組件）
- **共同協商修改路徑**：
  - `src/UI/ContentView.swift`（主視窗配置與柴犬組件嵌入介面）
  - `src/UI/LimitationsView.swift`（限制說明彈窗）
  - `src/UI/EncodingMonitorView.swift`（編碼監控面板）

---

## 🔒 檔案修改與併發安全規範

1. **先在獨立工作區預覽**：UI 與動畫修改需先於助手自身工作區驗證效果與產生預覽圖，確認滿意後再同步至共享專案目錄，嚴禁直接覆蓋未經確認之已下載產物。
2. **GUI 佔用宣告**：若需使用 `computer_use` 控制桌面應用程式（如調用外部模型或查看畫面），須先於協作訊息中確認目前無其他助手正在操作。
3. **打包與發行單一入口**：所有正式發行檔（`dist/LosslessStudio.dmg`）均由「程式開發員」在完整通過 9 大測試與動態函式庫載入路徑校驗後統一建置，避免版本割裂。
