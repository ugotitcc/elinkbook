# 🗺️ 專案 Epic 狀態看板

> 每個 Epic 只列一列精簡摘要；完整開發歷程（Discovery／Architecting／逐 Issue 記錄／審查修訂）改記錄於各 Epic 自己目錄下的 `epic.md`（🟢 已歸檔者在 `docs/archive/<日期>-<簡稱>/epic.md`，🟡 開發中者在 `docs/epics/<epic-name>/epic.md`；⚪ 未開始者尚無目錄，備註直接寫在本表）。

**單機閱讀優先波次的原始排序決議**（2026-07-14 `/grill-with-docs`，理由記於 `docs/prd.md` FR-19 段落）：`epic-5` → `epic-7` → `epic-14` → `epic-6` → `epic-8`；實際完成順序有一次偏離——`epic-6-annotations` 提前於 `epic-7`／`epic-14` 之前完成（既成事實，已合併回 `main`，不可逆）。

## 摘要

| 順位 | Epic | 狀態 | 備註 |
|---|---|---|---|
| 1 | `epic-0-skeleton` 技術骨架 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 2 | `epic-1-library` 圖書庫基礎 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 3 | `epic-2-vertical-core` 排版切換與直排核心 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 4 | `epic-3-fonts-layout` 字型與版面設定 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 5 | `epic-4-pdf-enhance` PDF 專業增強 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 6 | `epic-16-dual-page` 橫向雙頁顯示 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 7 | `epic-5-toc-pagination` 目錄與頁碼 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 8 | `epic-6-annotations` 註記與知識管理 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 9 | `epic-7-interaction` 互動控制 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 10 | `epic-17-epub-render-migration` EPUB 渲染引擎遷移評估 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 11 | `epic-8-sync` 雲端同步 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 12 | `epic-14-system-settings` 系統設定 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 13 | `epic-9-stats` 閱讀統計 | ⚪ 未開始 (Backlog) | 開發排期順延至 `epic-14-system-settings` 之後 |
| 14 | `epic-10-search` 全文檢索 | 🟡 開發中 (Active) | Issue 0-8 全部完成（Issue 8 PR #238 已合併）；全部工單結案，待人類決定歸檔時機 |
| 15 | `epic-40-bundled-sqlite` 自帶編譯進 FTS5 的 SQLite（取代系統內建版本） | 🟡 開發中 (Active) | Issue 0 程式碼已完成並合併（PR #236）；真機重新驗證（`9491G`／`Hera_Vis_WIFI`）為收尾步驟，待人類執行後歸檔 |
| 16 | `epic-11-multi-format-reader` 多格式閱讀擴充（KF8/CBZ/TXT/MD） | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 17 | `epic-12-social` 社群分享 | ⚪ 未開始 (Backlog) | P3，最低優先 |
| 18 | `epic-13-ios` iOS 移植 | ⚪ 未開始 (Backlog) | 待 Android 版本（epic-0/2/3/4/5）穩定後啟動 |
| 19 | `epic-15-storage-permission` 傳統儲存權限機制 | ⚪ 未開始 (Backlog) | 目前依賴 SAF 逐次選取授權，部分裝置重新選取子資料夾體驗不佳，待評估補強執行期權限方案 |
| 20 | `epic-4-pdf-enhance` （技術債）加粗濾鏡裝置矩陣複驗 | ⚪ 未開始 (Backlog) | 待取得 API 24-30 裝置後複驗加粗濾鏡效能與穩定性（已知殘留風險） |
| 21 | `epic-21-pdf-import-cover-fix` PDF 匯入封面產生管線卡住修復（技術債） | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 22 | `epic-18-reader-device-qa` 真機 UI 精修（版面設定/工具列/書架/直排邊距） | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 23 | `epic-19-shelf-reading-enhance` 書架與閱讀體驗強化（全螢幕模式/刪除書籍/分類拼貼） | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 24 | `epic-22-reader-theme-integration` 閱讀主題真正接上書本內容（深色/羊皮紙前景背景色） | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 25 | `epic-20-fxl-foliate-migration` FXL 渲染引擎遷移評估（foliate-js Phase 2） | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 26 | `epic-24-pdf-engine-rebuild` PDF 渲染引擎重建（遷移至 pdfrx/PDFium） | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 27 | `epic-25-annotation-interaction-qa` 劃線/備註真機互動精修 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 28 | `epic-26-architecture-hardening` 架構深化機會（測試套件效率／EPUB-PDF 底層架構） | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 29 | `epic-27-reader-device-compat` 裝置相容性強化（開書逾時／載入中點擊防護／高對比視覺強化） | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 30 | `epic-28-reader-settings-enhancements` 閱讀器設定強化（字距／Console Log 開關／版面設定預設集） | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 31 | `epic-29-cloud-import` 雲端服務匯入書籍（Google Drive／OneDrive） | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 32 | `epic-30-calibre-remote-library` Calibre 遠端書架整合 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 33 | `epic-31-touch-intent-unification` 觸控意圖判讀統一 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 34 | `epic-32-foliate-js-paginator-sync` foliate-js paginator.js 上游同步 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 35 | `epic-33-foliate-js-vendor-sync` foliate-js vendored 檔案持續同步 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 36 | `epic-34-tts-readalong` 語音朗讀（TTS）與同步高亮（Read-along） | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 37 | `epic-35-design-system-tokens` 設計系統 Token 落地（ElinkTokens：三主題＋E-Ink 修飾子） | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 38 | `epic-36-adaptive-shelf-navigation` 三目的地導覽／書架下鑽強化／設定四分區 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 39 | `epic-37-test-suite-flakiness` 全套測試套件既有不穩定性追蹤 | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 40 | `epic-38-reader-chrome-tts-redesign` 閱讀器 Chrome／TTS 重構（`DESIGN.md` §19 階段二） | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 41 | `epic-39-layout-settings-redesign` 版面設定三畫面主題化＋E-Ink 步進器（`DESIGN.md` §18.3 補實作） | 🟢 已歸檔 (Archived) | 已完成，已歸檔 |
| 42 | `epic-41-search-architecture-hardening` 全文檢索模組架構深化機會（epic-10-search 開發後盤點） | 🟡 開發中 (Active) | Issue 1（PR #240）／Issue 2（PR #241）已完成並合併；Issue 3-5 待實作、Issue 6 `needs-info` 暫緩，皆已 `/grilling` 敲定細節 |

**狀態燈號定義**：
- ⚪ **未開始 (Backlog)**：已被規劃但尚未啟動。無實際目錄。
- 🟡 **開發中 (Active)**：目前正在進行設計探索或程式碼編寫。目錄存放於 `docs/epics/`。
- 🟢 **已歸檔 (Archived)**：實作完成、測試通過且併入主線。目錄已移至 `docs/archive/`。
