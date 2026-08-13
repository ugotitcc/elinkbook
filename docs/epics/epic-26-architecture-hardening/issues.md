# Epic 26 — 架構深化機會：工單清單 (Issues)

依 `docs/research/architecture-review-test-suite-epub-pdf.md`（2026-08-11，`/improve-codebase-architecture` 流程產出，7 個候選深化機會）逐項評估後立案。目前只有候選 1 經 `/diagnose` 確認為現存 bug並拆為 Issue 1；其餘候選（2/3/6 同類但影響較小、4/5/7 需要先決策或範圍較大）尚未拆案，視後續優先順序決定是否納入本 Epic。

---

## Issue 1：流式 EPUB 書籤 toggle 快取未載入時，第一次點擊誤判無書籤而重複新增

**Status:** `ready-for-agent`——根因已由 `/diagnose` 確認（原始碼交叉核對＋widget test 重現），修法方向明確（比照 PDF 端已修過的版本），無需進一步 Discovery/Architecting，可直接進入 `/plan-issue`。

**依賴：** 無

**來源：** `docs/research/architecture-review-test-suite-epub-pdf.md` 候選 1（強度 Strong，「現存 bug，非假設性風險」）。診斷過程與重現測試詳見 `reviews/bugfix-repro.md`。

**背景／症狀：** 使用者重新開啟一本先前已在目前位置加過書籤的**流式（reflowable）EPUB**，在本次閱讀 session 尚未打開過筆記面板（NotesBottomSheet）的情況下，第一次點擊浮動書籤 toggle 按鈕（星星圖示），預期應是「刪除既有書籤」，實際卻是「新增一筆重複書籤」——同一位置最終出現 2 筆書籤記錄。

**根因（已用原始碼交叉核對＋widget test 重現確認，非臆測）：**

`_toggleBookmark()`（`app/lib/screens/reader_screen.dart:736`）用 `_bookmarkAtCurrentPosition` getter（`:714`）判斷目前頁是否已有書籤，該 getter 只讀記憶體快取 `_fxlBookmarks`（初始值 `[]`），不查 repository。EPUB 開書流程中沒有任何一處會在使用者**第一次點擊書籤按鈕之前**把既有書籤預先載入這個快取：

- `_loadFxlBookmarks()`（`:680`）只在以下時機被呼叫：`_toggleBookmark()`／`_togglePdfBookmark()` 自己執行完 insert/delete **之後**（`:755`、`:786`，用來刷新 UI，不影響本次判斷）；Notes 面板關閉時（`:1002`），但條件是 `_isFixedLayout || format == BookFormat.pdf`——**純流式（非 FXL）EPUB 被排除在外**；PDF 開書流程（`:1040`，`epic-24-pdf-engine-rebuild` Issue 8 補上的預先載入），**EPUB 沒有對應呼叫**。
- 對照 PDF 端：`_togglePdfBookmark()`（`:762-787`）明確不依賴 `_fxlBookmarks`，改為直接 `await repository.listByBook(widget.bookId)` 查詢，程式碼註解記載這正是為了「避免快取尚未載入時導致重複新增」（`epic-24-pdf-engine-rebuild` 該工單已修過的同一類 bug）。EPUB 端的 `_toggleBookmark()` 從未收到這個修復。

**驗證（已用 widget test 重現，見 `reviews/bugfix-repro.md`）**：預先在 `FakeBookmarksRepository` 塞入一筆與即將回報的 `locatorJson` 完全相同的書籤，模擬「重開已加過書籤的書」，不開 Notes 面板、直接點擊書籤 toggle 按鈕一次——結果 repository 從 1 筆變成 2 筆（應為 0 筆，因為預期行為是刪除既有書籤），確認重現。

**Solution（比照架構檢視報告候選 1 的建議方向）：** 抽出一個共用 module（`bool Function(Bookmark) matches` / `Bookmark Function() build` 參數化「查 repository → 比對 → insert/delete → reload」），`_toggleBookmark()`／`_togglePdfBookmark()` 皆改用此 module、直接查 repository 而非依賴 `_fxlBookmarks` 快取判斷存在性；EPUB 傳入 `epubLocatorJson` 比對邏輯、PDF 傳入 `pdfPageIndex` 比對邏輯。`_fxlBookmarks` 快取本身可繼續保留供 UI 顯示用（星星圖示狀態、Notes 面板書籤分頁），只是不再用它做 toggle 當下的存在性判斷。

**單元測試要求：**
- 把 `reviews/bugfix-repro.md` 的重現測試轉為永久回歸測試（流式 EPUB，開書後未開過 Notes 面板、目前位置已有書籤，第一次點擊 toggle 應刪除該書籤、repository 剩 0 筆、圖示變回 `star_border`）。
- 既有測試（`reader_screen_test.dart` line 3681 起「點擊浮動書籤 toggle 按鈕可新增/移除目前頁書籤」、PDF 對應測試）須繼續全數通過，確認重構未破壞既有行為。
- 確認 EPUB／PDF 兩邊呼叫共用 module 後，其中一邊修過的競態測試對另一邊同樣有效（可比照候選 1 文件的「刪除測試」精神：把其中一份 adapter 實作刪掉、改呼叫共用 module，行為不變）。

**驗收標準：** 流式 EPUB 重開已加過書籤的書、未開過 Notes 面板時，第一次點擊書籤按鈕正確判斷為「刪除」而非「新增」；EPUB／PDF 書籤 toggle 邏輯收斂為同一個共用 module；`flutter analyze` 乾淨、`flutter test` 全數通過。
