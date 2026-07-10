# 🗺️ 專案 Epic 狀態看板

| Epic 代號 & 名稱 | 當前狀態 | 實際存放路徑 | 關聯 PRD 需求章節 | 備註 |
|---|---|---|---|---|
| `epic-0-skeleton` 技術骨架 | 🟢 已歸檔 (Archived) | `docs/archive/2026-07-04-epic-0-skeleton/` | 無對應 FR，技術地基 | Issue 1–6 全數已合併 `main`（PR #1–#5、#7）；epic 端到端目標（Flutter + Android + EPUB(Readium) + PDF）已達成並歸檔 |
| `epic-1-library` 圖書庫基礎 | 🟢 已歸檔 (Archived) | `docs/archive/2026-07-06-epic-1-library/` | FR-01, 02, 03, 26, 27, 28, 29, 33, 34 | Issue 1-11 全數已完成並合併回 `main`（Issue 10：PR #16；Issue 11：PR #17）；epic 目標已達成並歸檔。FR-33/34（書籍分類群組、匯入自動分類）為 2026-07-04 PRD 修訂新增，見 `docs/archive/2026-07-06-epic-1-library/issues.md` |
| `epic-2-vertical-core` 排版切換與直排核心 | 🟢 已歸檔 (Archived) | `docs/archive/2026-07-07-epic-2-vertical-core/` | FR-05, 06, 32 | Issue 1-5 全數已完成並合併回 `main`（PR #18、#19、#22、#23、#24）；epic 目標已達成並歸檔 |
| `epic-3-fonts-layout` 字型與版面設定 | 🟢 已歸檔 (Archived) | `docs/archive/2026-07-10-epic-3-fonts-layout/` | FR-09, 10, 31 | Issue 1-10 全數已完成（Issue 1: PR #25; Issue 2: PR #26; Issue 3: PR #27; Issue 4: PR #28; Issue 5: PR #29；Issue 6 真機驗證發現的 Issue 7/8/9〔字重無效／底部裁切／PDF 無法換頁〕與追加的 Issue 10〔漫畫奇偶頁縮放不一致〕皆已修復並經真機確認）；epic 目標已達成並歸檔。FR-09 已拆分：自訂字型上傳/管理/刪除移至 `epic-14-system-settings`（FR-35）；FR-10 新增螢幕方向/翻頁模式與 `epic-14-system-settings`（FR-37/38）之全域/單書雙層覆寫邏輯；FR-42（固定版面全螢幕顯示開關，本 epic 收尾時追加分流）比照同一模式歸入 `epic-14-system-settings` |
| `epic-4-pdf-enhance` PDF 專業增強 | ⚪ 未開始 (Backlog) | N/A | FR-11 | |
| `epic-16-dual-page` 橫向雙頁顯示 | ⚪ 未開始 (Backlog) | N/A | FR-41 | `/grill-with-docs` 2026-07-10 分流新增：裝置橫向時，漫畫（EPUB 固定版面）與 PDF 同時並排顯示兩頁、頁面間不留空白。橫跨 epic-3（EPUB FXL 排版）與本 epic（PDF），決議獨立成一個 Epic、待 epic-4-pdf-enhance 之後啟動 |
| `epic-5-toc-pagination` 目錄與頁碼 | ⚪ 未開始 (Backlog) | N/A | FR-07, 08, 12, 22, 23, 40 | FR-40（頁首/頁尾顯示切換）為 2026-07-04 PRD 修訂新增 |
| `epic-6-annotations` 註記與知識管理 | ⚪ 未開始 (Backlog) | N/A | FR-13, 14, 15, 16, 25 | |
| `epic-7-interaction` 互動控制 | ⚪ 未開始 (Backlog) | N/A | FR-18, 24 | FR-18/FR-24 內容已擴充（音量鍵固定翻頁方向、單手模式左右熱區可獨立設定）；FR-18 音量鍵總開關已移至 `epic-14-system-settings`（FR-36） |
| `epic-8-sync` 雲端同步 | ⚪ 未開始 (Backlog) | N/A | FR-19, 20, 30 | |
| `epic-14-system-settings` 系統設定 | ⚪ 未開始 (Backlog) | N/A | FR-35, 36, 37, 38, 39, 42 | **開發順序提前至 epic-8 之後、epic-9 之前**（代號維持 `epic-14` 不變，僅調整開發排期，避免牽動已有文件中對代號的既有引用）。橫跨字型 (epic-3)、互動 (epic-7)、同步 (epic-8) 之全域設定畫面，FR-37/38 與 epic-3 之 FR-10、FR-36 與 epic-7 之 FR-18 為全域/單書雙層覆寫關係。FR-42（固定版面全螢幕顯示開關，`/grill-with-docs` 2026-07-10 追加）比照同一模式：全域預設＋單書覆寫 |
| `epic-9-stats` 閱讀統計 | ⚪ 未開始 (Backlog) | N/A | FR-17 | 開發排期順延至 `epic-14-system-settings` 之後 |
| `epic-10-search` 全文檢索 | ⚪ 未開始 (Backlog) | N/A | FR-04 | 獨立於圖書庫之外的子系統（SQLite FTS5） |
| `epic-11-txt-engine` TXT 直排引擎 | ⚪ 未開始 (Backlog) | N/A | 無直接對應 FR | 自訂輕量排版引擎，後續評估 Rust/C++ 共用核心 |
| `epic-12-social` 社群分享 | ⚪ 未開始 (Backlog) | N/A | FR-21 | P3，最低優先 |
| `epic-13-ios` iOS 移植 | ⚪ 未開始 (Backlog) | N/A | 無直接對應 FR | 待 Android 版本（epic-0/2/3/4/5）穩定後啟動 |
| `epic-15-storage-permission` 傳統儲存權限機制 | ⚪ 未開始 (Backlog) | N/A | 無直接對應 FR，補強 FR-01/FR-33/34 匯入流程 | 目前檔案/資料夾匯入完全依賴 SAF（Storage Access Framework）逐次選取授權，`AndroidManifest.xml` 未宣告任何儲存權限，故「設定 → 應用程式 → elinkBook」看不到可切換的權限項目；部分裝置在 App 重新安裝、或系統選擇器書籤被清除後，選擇器會落回無法選取的儲存根目錄（Android 11+ 限制），使用者需重新在選擇器內手動導覽至子資料夾才能恢復。2026-07-10 真機測試時發現並記錄，待評估是否新增傳統執行期儲存權限（例如 `MANAGE_EXTERNAL_STORAGE` 或 `READ_MEDIA_*`）作為輔助/退路方案，改善此體驗 |

**狀態燈號定義**：
- ⚪ **未開始 (Backlog)**：已被規劃但尚未啟動。無實際目錄。
- 🟡 **開發中 (Active)**：目前正在進行設計探索或程式碼編寫。目錄存放於 `docs/epics/`。
- 🟢 **已歸檔 (Archived)**：實作完成、測試通過且併入主線。目錄已移至 `docs/archive/`。
