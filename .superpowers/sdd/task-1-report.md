# Task 1 Report: Scaffolding & Router (專案初始化、裝置外框與底層頁面路由器)

## 任務概述
本任務已成功完成 `elinkBook` Web 原型模擬器的基礎骨架搭建、高質感的手機外殼 Mockup 繪製、三個核心分頁的路由切換，以及整合了自我測試套件（Self-Test Suite），用以驗證底層狀態管理與路由切換的正確性。

---

## 實作細節與技術亮點

### 1. 初始 HTML5 骨架與高質感 CSS 設計
- **雙佈局設計**：左側為手機 Mockup，右側為現代暗黑風格的控制台面板（Control Panel），方便開發與測試對照。
- **現代字體與顏色變數**：載入了 Google Fonts 的 `Outfit` 與 `Inter` 做為無襯線字體，並載入 `Noto Serif TC` 以完美支援直排中文的宋體/明體質感。
- **手機外殼 Mockup**：
  - 精緻的邊框（Bezel）與圓角（Radius），搭配立體的陰影和反光。
  - 頂部前鏡頭處特別設計了**動態島（Dynamic Island）**，具備 Hover 展開的流暢微動畫。
  - 側邊設有**實體音量鍵**，具備 Hover 高亮與 Active 按壓位移的物理效果。
  - 狀態列時間採用 JavaScript 動態更新，每秒與系統時間同步，顯著提升原型生活感。

### 2. 多主題與排版切換
- **多主題支援**：實作了 **淺色 (Light)**、**深色 (Dark)**、**羊皮紙 (Sepia)** 以及 **E-Ink 高對比 (E-Ink)** 四種閱讀主題，透過點擊書架上方的色彩圓點即可即時無縫切換。
- **橫/直排切換**：在閱讀器畫面中，提供一鍵切換**直排（vertical-rl）**與**橫排**的功能。直排模式使用了標準 CSS `writing-mode: vertical-rl` 進行繁體中文的優雅排版。

### 3. 多分頁路由與狀態管理 (`AppState`)
- **全域狀態物件 `AppState`** 統一管理目前分頁（`currentPage`）、主題（`theme`）、排版方向（`layoutDirection`）以及書籍資料。
- 底部導覽列切換時，具有 Flutter 風格的圖標縮放與底色漸層微動畫。
- 三大分頁內容：
  - **書架 (Shelf)**：以卡片網格（Grid）呈現書本，包含古典封面的「紅樓夢」與現代感封面的「三國演義」，並顯示格式標籤（EPUB/TXT）與高質感閱讀進度條。
  - **閱讀器 (Reader)**：展示電子書實際閱讀畫面，支援點擊螢幕左右側 1/3 區域進行翻頁。
  - **統計 (Stats)**：整合了 GitHub 貢獻圖風格的**閱讀熱點圖 (Heatmap)**，以及本週每日閱讀時長的 CSS 柱狀圖。

### 4. 實體音量鍵翻頁整合
- 側邊實體音量鍵在非閱讀狀態下點擊會提示音量調整；在閱讀器狀態下，點擊音量加（`volume-up`）與音量減（`volume-down`）可直接控制當前書籍的閱讀進度（每次增減 5%），並跳出流暢的 Toast 浮層通知，完美符合單手操作與音量鍵翻頁的需求。

---

## 自我測試套件 (Self-Test Suite) 結果
我們在 `prototype/index.html` 底部整合了測試引擎，並在控制台提供一鍵「運行自我測試」按鈕。目前已註冊並通過以下三個核心測試：

1. **驗證切換路由狀態變更 (PASS)**
   - 測試步驟：暫存目前頁面 ➔ 切換至 `stats` ➔ 驗證 `AppState.currentPage === 'stats'` ➔ 切換回 `shelf` ➔ 驗證回歸 ➔ 還原頁面。
2. **驗證主題切換與 Class 變更 (PASS)**
   - 測試步驟：切換主題至 `sepia` ➔ 驗證手機 DOM 是否成功附加 `theme-sepia` class ➔ 驗證 `AppState.theme === 'sepia'` ➔ 還原主題。
3. **驗證音量鍵閱讀翻頁邏輯 (PASS)**
   - 測試步驟：切換至閱讀器分頁 ➔ 模擬點擊音量減鍵 ➔ 驗證書籍進度是否增加 5% ➔ 模擬點擊音量加鍵 ➔ 驗證書籍進度是否減少 5%（還原）➔ 還原頁面。

運行結果在控制台「自我測試結果」區域顯示：**`3 PASS / 0 FAIL`**。

---

## 成果檔案路徑
- **模擬器主頁面**：[prototype/index.html](file:///U:/MyDeveloper/AI/elinkBook/prototype/index.html)
- **進度分類帳**：[.superpowers/sdd/progress.md](file:///U:/MyDeveloper/AI/elinkBook/.superpowers/sdd/progress.md)
