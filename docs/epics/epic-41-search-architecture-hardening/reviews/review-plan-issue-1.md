# Epic 41 Issue 1 實作計畫審查與複審報告 (Implementation Plan Review & Re-review Report)

**審查對象：**
- [`docs/epics/epic-41-search-architecture-hardening/plans/plan-issue-1.md`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-41-search-architecture-hardening/plans/plan-issue-1.md)

**關聯規格與架構文件：**
- [`docs/epics/epic-41-search-architecture-hardening/epic.md`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-41-search-architecture-hardening/epic.md)（Epic 看板）
- [`docs/epics/epic-41-search-architecture-hardening/issues.md`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-41-search-architecture-hardening/issues.md)（Issue 1 規格段落）
- [`docs/epics/epic-41-search-architecture-hardening/reviews/review-epic-and-issues.md`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-41-search-architecture-hardening/reviews/review-epic-and-issues.md)（前置架構審查意見，特別是 I-3）

**診斷基準程式碼：**
- [`app/lib/screens/reader_screen.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/screens/reader_screen.dart)（`ReaderScreen` 20+ 欄位建構子簽章）
- [`app/lib/screens/library_screen.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/screens/library_screen.dart)（呼叫點 1：`_openBook()`）
- [`app/lib/screens/library_search_screen.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/screens/library_search_screen.dart)（呼叫點 2：`_openBook()`）
- [`app/lib/screens/book_search_screen.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/lib/screens/book_search_screen.dart)（呼叫點 3：`_handleSnippetTap()`）
- [`app/test/screens/library_screen_test.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/test/screens/library_screen_test.dart)（既有開書回歸測試）
- [`app/test/screens/library_search_screen_test.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/test/screens/library_search_screen_test.dart)（既有全庫搜尋開書回歸測試）
- [`app/test/screens/book_search_screen_test.dart`](file:///C:/Users/fycdc/AI/elinkBook/app/test/screens/book_search_screen_test.dart)（既有單書搜尋推入回歸測試）

**審查專家：** 系統架構師 & 測試工程審查員  
**初審日期：** 2026-09-14  
**初審結論：** 🟢 Ready to implement with fixes（1 Important / 3 Minor）  
**複審日期：** 2026-09-14  
**複審結論：** **🟢 Approved（全數問題皆已妥善修訂或合理釐清，無新引入缺陷，核准進入實作階段）**

---

## 摘要統計 (Findings Summary)

| 嚴重度層級 (Severity) | 初審數量 | 複審狀態 | 說明 |
|---|:---:|:---:|---|
| **Critical（阻斷性缺陷）** | **0** | **全數解決 (0 殘留)** | 無阻斷性缺陷（任務切分清晰、呼叫點行號與程式碼比對 100% 精確、TDD 流程完整）。 |
| **Important（重要測試與防禦漏洞）** | **1** | **全數解決 (0 殘留)** | **I-1**: Task 1 Step 1 單元測試補齊 `features` 全部 12 個欄位的非空實例賦值與 `expect(..., same(...))` 斷言，消除了 `null == null` 的虛假綠燈缺陷（**ADDRESSED**）。 |
| **Minor（次要優化與細節校正）** | **3** | **全數解決 (0 殘留)** | **M-1**: 模組檔名維持 `reader_screen_route.dart`，語意可接受且無執行期影響（**REBUTTED & ACCEPTED**）。<br>**M-2**: Task 4 Step 7 工單完成狀態格式已修訂為 `**Status:** completed（...）` 統一慣例（**ADDRESSED**）。<br>**M-3**: Commit 訊息範本 metadata 符合專案追蹤要求，合理維持（**REBUTTED & ACCEPTED**）。 |
| **總計 (Total)** | **4** | **4 項已處理 (0 殘留)** | **實作計畫完備，無阻斷性與重要缺陷，核准啟動工單實作** |

---

## 1. 總結評估 (Executive Summary)

[`docs/epics/epic-41-search-architecture-hardening/plans/plan-issue-1.md`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-41-search-architecture-hardening/plans/plan-issue-1.md) 在初審後進行了迅速且高規格的修訂：

1. **單元測試防禦強度達到 100% (I-1)**：
   - Task 1 Step 1 測試程式碼中，針對 `LibraryReaderFeatureRepositories` 轉送至 `ReaderScreen` 的全部 12 個欄位（`bookmarksRepository`、`highlightsRepository`、`notesRepository`、`customFontsRepository`、`layoutPresetRepository`、`bookReaderPrefsRepository`、`ttsProvider`、`ttsAudioHandler`、`ttsAudioFocusSource`、`readerActivityTracker`、`searchRepository`、`isFullTextSearchAvailable`），作者精準引入了 `test/support/` 既有的假物件；
   - 針對缺少現成 Fake 的 `LayoutPresetRepository`，敏銳且正確地遵循既有測試慣例（`test/reader/layout_preset_repository_test.dart`），在 `setUpAll`/`setUp` 初始化 in-memory SQLite 資料庫並傳入 `dbRepository.database`；
   - 斷言區塊對上述 12 個欄位皆以 `expect(screen.xxx, same(xxx))` 逐一核對物件記憶體參照，徹底杜絕了先前「9 個欄位皆為 null 導致漏傳也能 pass」的漏洞，真正達成了「100% 欄位對帳」。
2. **工單狀態格式與專案對齊 (M-2)**：
   - Task 4 Step 7 的工單完成狀態修訂為標準的 `**Status:** completed（plans/plan-issue-1.md 4 個 Task 全數完成……）`，符合 `epic-10`、`epic-40` 看板解析規範。
3. **其餘細節合理採納或維持 (M-1, M-3)**：
   - 檔名 `reader_screen_route.dart` 與 Commit attribution 格式依全專案歷史慣例維持，經核對無任何相容性問題。

---

## 2. 初審發現與修訂建議 (Original Findings & Recommendations)

### Critical（阻斷性缺陷）

*(無阻斷性缺陷)*

---

### Important（重要測試與防禦漏洞）

> [!WARNING]
> **I-1. Task 1 Step 1 欄位對帳單元測試遺漏 9 個 Repository 欄位的非空比對，削弱防禦力**
>
> - **位置**：`plan-issue-1.md:77-119`（初審版本）
> - **分析**：測試中 `features` 僅賦值 3 個欄位，其餘 9 個（`highlightsRepository`、`notesRepository`、`customFontsRepository`、`layoutPresetRepository`、`bookReaderPrefsRepository`、`ttsProvider`、`ttsAudioHandler`、`ttsAudioFocusSource`、`searchRepository`）皆預設為 `null` 且未作斷言，無法防範工廠函式漏接。
> - **建議**：利用 `test/support/` 假物件或真實 in-memory 實例填滿 12 個欄位，逐一執行 `expect(screen.xxx, same(xxx))`。

---

### Minor（次要優化與細節校正）

> [!NOTE]
> **M-1. 模組檔名 `reader_screen_route.dart` 與內部純 Widget 工廠函式命名之語意落差**
> - **建議**：更名為 `reader_screen_builder.dart`，或維持原檔名。

---

> [!NOTE]
> **M-2. Task 4 Step 7 工單完成狀態標記應遵循 `Status: completed（...）` 專案慣例**
> - **建議**：改為 `**Status:** completed（...）` 格式。

---

> [!NOTE]
> **M-3. Commit 訊息範本硬編碼外部 session URL 標籤**
> - **建議**：實作 commit 時評估是否清理或維持。

---

## 3. 複審逐項查驗結果 (Re-review Verification)

| 項目 | 審查意見要求 | 計畫修訂實作核對 | 複審判決 |
|---|---|---|:---:|
| **I-1** | 補齊單元測試 12 個欄位的非空賦值與斷言 | [`plan-issue-1.md:87-181`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-41-search-architecture-hardening/plans/plan-issue-1.md#L87-L181)（Task 1 Step 1）：引入 in-memory `SqliteLibraryRepository` 建構 `LayoutPresetRepository`，其餘 11 個欄位全數給定非空實例；斷言區塊對 12 個欄位皆使用 `expect(..., same(...))` 逐一斷言參照相等，欄位對帳完全覆蓋。 | **✅ ADDRESSED** |
| **M-1** | 檔名與工廠函式命名語意微調 | [`plan-issue-1.md:32, 163`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-41-search-architecture-hardening/plans/plan-issue-1.md#L32)：維持 `reader_screen_route.dart`。考量檔案路徑清晰且不影響任何執行期語意，合理維持。 | **🟢 REBUTTED & ACCEPTED** |
| **M-2** | 工單完成狀態格式遵循專案慣例 | [`plan-issue-1.md:691-698`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-41-search-architecture-hardening/plans/plan-issue-1.md#L691-L698)（Task 4 Step 7）：已修訂為 `**Status:** completed（plans/plan-issue-1.md 4 個 Task 全數完成……）`，完全貼齊全專案 issue tracker 規範。 | **✅ ADDRESSED** |
| **M-3** | Commit 訊息範本 metadata 處理 | [`plan-issue-1.md:21-25`](file:///C:/Users/fycdc/AI/elinkBook/docs/epics/epic-41-search-architecture-hardening/plans/plan-issue-1.md#L21-L25)：經核對專案歷史 commit 紀錄，格式統一，維持現狀合理。 | **🟢 REBUTTED & ACCEPTED** |

---

### 新引入改動安全性審查 (New Breakage Inspection)

- **測試設定健全度**：
  - Step 1 加入了 `setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });`，這是使用 in-memory SQLite 時的標準起手式，能確保純 Dart 單元測試環境下 `SqliteLibraryRepository.open(inMemoryDatabasePath)` 穩定執行，無原生依賴問題。
  - `setUp` 開啟資料庫與 `tearDown` 關閉資料庫配對完整，無連線洩漏風險。
- **無任何多餘或衝突的相依性**：
  - 引入的 Fake 物件（如 `FakeBookmarksRepository`、`FakeCustomFontsRepository` 等）皆已於現有程式碼庫驗證存在且簽章相符，未引入任何不存在的符號。

---

## 4. 結論與下一步 (Final Verdict & Next Steps)

本實作計畫經本次修訂後，測試案例防禦力完備（100% 欄位對帳鎖定），呼叫端改動面清晰受控，TDD 步驟無任何模糊空間。

- [x] **複審結論：🟢 Approved（核准通過，計畫完備，無殘留阻斷缺陷）**
- **下一步**：請使用 `/superpowers:subagent-driven-development` 或 `/superpowers:executing-plans` 依計畫循序執行 Task 1 至 Task 4 之實作與驗收。
