# Epic 28 Issue 3 — 版面設定預設集＋書籍設定複製 實作計畫審查報告

本報告針對 [`docs/epics/epic-28-reader-settings-enhancements/plans/plan-issue-3.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-28-reader-settings-enhancements/plans/plan-issue-3.md) 進行深度技術架構與實作計畫審查，評估其是否符合需求規格（`design.md`、`spec.md`、`issues.md`）、專案既有架構原則、資料防護規範與 TDD 開發標準。

---

## 1. 優點與亮點 (Strengths)

* **TDD 流程切分嚴謹且具高可執行性**：
  計畫規劃為 11 個自洽、可獨立測試與提交的垂直切片 Task。每個 Task 皆明確包含「編寫失敗測試 → 驗證預期失敗 → 編寫實作碼 → 驗證通過 → 分析與零回歸檢查 → 獨立 commit 指令」，細節具體且清晰。
* **反序列化容錯設計（Task 1）兼顧多路徑**：
  `enumByNameOrNull` 頂層輔助函式取代了既有容易拋出 `ArgumentError` 的 `values.byName()`，同時服務了既有 SQLite `book_reader_prefs` 讀取路徑與新引入的 `prefs_json` JSON 路徑，大幅提升面對未知/過期列舉值時的系統穩健性（安全降級為 `null` 未覆寫）。
* **欄位污染防護機制完善（Task 2）**：
  明確定義 `BookReaderPrefs.reflowableEpubFields()`，在另存預設集與跨書複製時強制將非流式 EPUB 的 10 個欄位（`pageMargins`、6 個 `pdf*`、3 個 `dualPage*`）過濾為 `null`，不依賴「流式 EPUB 欄位必定為 null」的脆弱假設，有效防範歷史資料或人工版面覆蓋殘留的污染。
* **儲存格式設計前瞻且可維護性高（Task 4 & 5）**：
  `layout_preset` 資料表採用 `prefs_json` 儲存過濾後的偏好設定，避免未來 `BookReaderPrefs` 每新增排版欄位就必須雙重維護 SQLite migration，大幅降低未來維護成本；且 `replace` 時嚴格鎖定 `id` 與 `created_at` 不變、僅更新 `updated_at`，並在查詢時固定以 `id ASC` 排序，防止 UI 卡片順序在更新時跳動。
* **批次寫入與資料庫層級過濾效能優化（Task 6 & 7）**：
  - `BookReaderPrefsRepository.saveMultiple()` 採用單一 `Database.transaction()` 包裹，避免批次套用到多本書籍時產生多次獨立交易導致 UI 卡頓。
  - `LibraryRepository.listReflowableEpubBooks()` 直接下 SQL 條件（`filePath LIKE '%.epub' AND (is_fixed_layout IS NULL OR is_fixed_layout != 1)`）過濾書籍，取代記憶體過濾，效能優異。
* **UI 與業務邏輯責任邊界清晰（Task 8 & 9 & 10）**：
  `ReaderSettingsSheet` 與 `LayoutPresetBookPickerScreen` 保持為純展示型元件（Pure Presentational Widgets），所有資料庫 I/O、命名/覆蓋/確認對話框均集中於 `ReaderScreen` 協調處理，元件間耦合度低且利於單元/Widget 測試。
* **規格小疏漏主動補完**：
  計畫敏銳辨識出 `spec.md` 遺漏了「刪除預設集」的 callback，主動依據產品源頭需求（`design.md`「管理介面（新增/命名/刪除）」）補足第 5 個 callback `onDeletePreset`，體現了高度的審查洞察力。
* **端到端貫穿與編譯驗證（Task 11）**：
  計畫在最後一個 Task 將依賴完整貫穿至 `main.dart` 與 `LibraryScreen`，並包含真實 `flutter build apk --debug` 步驟，確保進入點組裝無誤。

---

## 2. 問題與疑慮 (Issues)

### Critical (必須修正)
* 無。

### Important (應該修正)
* 無。

### Minor (建議優化 / 注意事項)

#### 1. SQLite Migration 版本號動態核對
* **說明**：計畫中已明確在 Task 4 提醒「實作前務必以 `grep -n "version:" app/lib/library/sqlite_library_repository.dart` 確認目前 `main` 的實際版本號現值」。鑑於目前 `main` 與平行工單可能升級至 `version: 20`，實作時依當下現值遞增即可。

#### 2. 單本書籍與多本書籍套用確認邏輯
* **說明**：計畫在 Task 10 `_handleApplyPreset` 與 `_handleApplyFromBook` 中明確說明：判斷是否跳出確認對話框是以「是否為『套用到其他書籍』流程」為依據，而非單純依據 `targetBookIds.length > 1`（即使使用者在其他書籍選擇器中僅勾選 1 本書，仍屬跨書覆蓋操作，需跳出確認）。此業務邏輯設計精確符合 UX 規範。

---

## 3. 評估結論 (Assessment)

* **是否已準備好開始實作 (Ready to implement)？**：**準備好開始實作 (Ready to implement)**。
* **評估理由**：實作計畫架構完備、職責邊界分明、TDD 步驟詳盡，充分考量了欄位污染防護、反序列化容錯、批次寫入效能與 SQLite migration 相容性，無任何阻擋實作之架構缺陷。
