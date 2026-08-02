# Bug 修復診斷：自訂字型匯入後無法在單書閱讀字型選單中出現

> `/diagnose` 產出，2026-08-02。

## 症狀

使用者回報：透過「設定 → 字型管理」上傳自訂字型後，開啟一本書、進入「版面設定」（`ReaderSettingsSheet`）的「單書閱讀字型」下拉選單，看不到剛上傳的自訂字型，只有內建 5 款字型可選。

## Phase 1-2：feedback loop 與重現

追蹤資料流：`FontManagementScreen`（上傳）→ `CustomFontsRepository.listAll()`（查詢）→ `ReaderScreen._loadCustomFonts()`（載入）→ `_customFonts` → `ReaderSettingsSheet.customFonts`（合併進下拉選單）。逐段檢查：

- `ReaderSettingsSheet._buildFontFamilyDropdown()`（`reader_settings_sheet.dart:419-454`）合併邏輯正確：`...widget.customFonts.map(...)` 無條件併入下拉選單項目，無過濾/篩選 bug。
- `CustomFontsRepository.listAll()`（`custom_fonts_repository.dart:13-16`）為單純 `_db.query('custom_fonts', ...)`，與 `main.dart` 建構、`FontManagementScreen` 共用同一個 `Database` 連線——若字型能在「字型管理」畫面清單中看到，`listAll()` 必定能正確查到。
- `ReaderScreen._loadCustomFonts()`（`reader_screen.dart:634-649`）：`final repository = widget.customFontsRepository; if (repository == null) return;`——**只要 `customFontsRepository` 是 `null`，`_customFonts` 永遠停留在初始值 `[]`**。

`grep -rn "ReaderScreen(" app/lib` 顯示全專案只有 2 處：`reader_screen.dart`（自身定義）與 `library_screen.dart:419`（唯一的建構呼叫點）。檢視 `LibraryScreen._openBook()`（`library_screen.dart:415-431`，使用者點擊書架封面開書的唯一入口）：其 `ReaderScreen(...)` 建構參數列出 `filePath`／`bookId`／`prefsManager`／`bookmarksRepository`／`highlightsRepository`／`notesRepository`／`bookTitle`／`bookAuthor`／`bookProgress`／`isFixedLayout`／`libraryRepository`，**唯獨缺少 `customFontsRepository`**。

寫下可重現的 widget test（比照本檔案既有的「Issue 6 缺口修正」測試手法——用 `.txt` 格式書籍讓 `ReaderScreen` 命中安全的「不支援格式」分支，不觸發 `AndroidView`，只驗證建構參數貫穿）：

```dart
testWidgets('LibraryScreen 點開一本書後，ReaderScreen 收到的 customFontsRepository 正確貫穿', ...)
```

執行結果：`Expected: same instance as <FakeCustomFontsRepository>`／`Actual: <null>`——100% 可重現，非時序/隨機性問題。

## Phase 3：假設排除

| # | 假設 | 結論 |
|---|---|---|
| 1 | `LibraryScreen._openBook()` 沒有把 `customFontsRepository` 貫穿給 `ReaderScreen` | **確認為根因**（見上，靜態程式碼事實，非執行期行為） |
| 2 | `CustomFontsRepository.listAll()` 查詢邏輯有誤 | 排除——純粹的 `_db.query()`，與「字型管理」畫面共用同一連線 |
| 3 | `ReaderSettingsSheet` 下拉選單合併/過濾邏輯有誤 | 排除——`...widget.customFonts.map(...)` 無條件合併 |
| 4 | Issue 3 修正過的非同步載入競態重新出現 | 排除——該競態只影響開書當下 `FoliateEpubReaderView` 的 CSS 注入時機，使用者手動點開設定面板時 `_loadCustomFonts()` 早已完成（或早已因 `repository == null` 直接跳過），與本症狀無關 |

## Phase 5：修復與回歸測試

**根因**：`LibraryScreen._openBook()`（唯一的開書入口）從未把 `customFontsRepository` 傳給 `ReaderScreen`，導致 `_loadCustomFonts()` 早期 `return`、`_customFonts` 永遠是空清單。

這與先前已修復過的「Issue 6 缺口」（`highlightsRepository`／`notesRepository` 曾經同樣沒有貫穿）是同一類問題——`epic-14` Issue 2 的計畫審查當時有特別注意到 `LibraryScreen._openGroupFilteredView()`（分類篩選畫面的遞迴 `LibraryScreen(...)` 自我建構點）容易漏傳並補上測試，但沒有涵蓋到 `_openBook()` 本身（唯一真正建構 `ReaderScreen` 的地方），因此這個真正的漏洞從 Issue 2 合併以來一直未被發現。

**修復**：`library_screen.dart:415-432` 的 `ReaderScreen(...)` 建構式補上 `customFontsRepository: widget.customFontsRepository,`。

**回歸測試**：`test/screens/library_screen_test.dart`「LibraryScreen 點開一本書後，ReaderScreen 收到的 customFontsRepository 正確貫穿」，正確的測試接縫（真實開書路徑，非只測 `_openGroupFilteredView` 的轉發）。

## Phase 6：驗證與現況

- [x] 原始重現不再發生（回歸測試由 FAIL 轉為 PASS）
- [x] 回歸測試通過，接縫正確（比照既有 Issue 6 缺口修正的驗證手法）
- [x] 無臨時除錯插樁需要清理
- [x] `flutter analyze`：No issues found!
- [x] `flutter test`：771/771 全數通過（含新增的 1 個回歸測試，原 770 個既有測試無 Regression）

## Post-mortem：什麼可以預防這個 bug？

這是同一個架構脆弱點第二次造成漏洞（第一次是 Issue 6 的 `highlightsRepository`／`notesRepository`）：`LibraryScreen._openBook()` 是唯一的開書入口，但每次 `ReaderScreen` 新增一個可選建構參數（新的 repository/service），都必須手動記得同步在這裡補上一行，且目前沒有任何機制強制檢查「`LibraryScreen` 持有的每個 repository 欄位都有貫穿給 `ReaderScreen`」。這是純手動紀律在把關，容易在功能擴充時遺漏——建議在下一次遇到類似擴充時，考慮改用一個集中的「ReaderScreen 依賴集合」物件（例如把 `bookmarksRepository`／`highlightsRepository`／`notesRepository`／`customFontsRepository`／`libraryRepository` 打包成一個 value object），從 `LibraryScreen` 整包往下傳、`ReaderScreen` 整包接收，讓新增一個 repository 時只需要改一個地方（該物件的定義），不再是「新增 repository → 記得同步修改 N 個分散的建構呼叫點」。是否要投入這個重構留待後續評估，非本次緊急修復範圍。
