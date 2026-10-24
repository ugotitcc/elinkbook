# Issue 25：本書書籤 module 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** 把「目前位置有沒有書籤」的 3 份實作與 2 份切換邏輯，收成一個 `BookmarkController`（持有書籤清單，提供 `load()`、`at(位置)`、`toggle(position:, l10n:)`）。純重構，唯一刻意的行為變化是：流式 EPUB 開書就載入書籤（修正星號開書時可能為空）。

**Architecture：** 新增 `app/lib/reader/bookmark_controller.dart`（頂層純函式 `isSameBookmarkPosition`、類別 `BookmarkController`）。`ReaderScreen` 以 `late final BookmarkController _bookmarks` 持有，不通知，呼叫後自己 `setState`。`NotesBottomSheet` 自建一個同類別實例，建構參數不動。`bookmark_toggle.dart` 併入後刪除。

**Tech Stack：** Flutter／Dart、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立 `spec.md`，設計依據是 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 25 設計決策」（決策 1～12）；詞彙見 `CONTEXT.md`「本書書籤」。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **純重構**（決策 1）：除決策 7 的載入時機外，呼叫順序、`mounted` 檢查、fire-and-forget 逐字保留。
- **存在性判斷直查 repository**（決策 5，Epic 26 競態修復）：`toggle` 不看記憶體清單；`at()` 才看清單（給星號圖示用）。
- **預設名稱由呼叫端的 `BookmarkPositionContext` 決定**（決策 6）：FAB 傳不帶 `chapterTitle` 的 context，面板傳帶 `chapterTitle` 的 context。兩者名稱不同是現狀，不要統一。
- **不碰 `BuildContext`**（決策 2）：`l10n` 由呼叫端在 `await` 前取好。
- **範圍外**：不改 `NotesBottomSheet` 建構參數與其重新命名／刪除／全刪流程；不改 `Bookmark`、`BookmarkPositionContext`、`BookmarksRepository`；不動 `ReaderScreen.togglePdfBookmark` 這個測試 seam 的簽章。
- **測試原則（replace, don't layer）**：`bookmark_toggle_test` 改名為 `bookmark_controller_test`，舊檔刪除。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（`run_in_background`，不要同時跑第二個）。
- **每個 Task／commit 結束都必須可編譯、`flutter analyze` 乾淨、被觸及的測試全綠**。
- **提交前**：`flutter analyze` 必須 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Windows 環境**：多數原始檔是 CRLF，Edit 的定位字串不要含換行；`python` 編輯以 `newline=''` 開檔。
- **Commit**：不加 `Co-Authored-By`。每個 Task 一個 commit。
- **不要提交** `app/android/gradle.properties`（使用者擱置的未提交變動）。
- **計畫與實作同分支同 PR**，不另開文件分支。

## Review Focus

最可能咬到使用者的情況（依可能性排序）：

1. **切換後星號沒更新，或書籤重複新增。** `toggle` 必須先直查 repository 再改，改完自己重載清單。→ Task 1 測「清單是舊的、資料庫已有書籤時，`toggle` 仍刪除而非重複新增」。
2. **流式 EPUB 開書後星號仍為空**（本張要修的缺陷）。→ Task 2 先寫紅燈測試。
3. **PDF 星號退步。** PDF 原本借 `_pdfTocLoaded` 在開書時載入；改成 `initState` 載入後，不可漏載或重複載。→ 既有 PDF 書籤案例（`reader_screen_test.dart` 約 9303、9351）必須維持綠。
4. **面板書籤分頁行為改變。** 面板改用自己的 `BookmarkController`，切換、重新命名、刪除、全刪後清單與按鈕狀態要和現在一致。→ `notes_bottom_sheet_test.dart` 全檔必須綠。
5. **FAB 與面板的預設名稱被誤統一。** → Task 3 保留兩個既有名稱斷言。
6. **關閉面板後星號過期。** 重載範圍從「FXL／PDF」擴大為所有格式。

## 待計畫審查確認（計畫撰寫時發現，設計討論未涵蓋）

- **邊界情況**：`NotesBottomSheet._toggleBookmark` 在 `currentPosition` 兩組欄位都是 null（位置尚未回報）時，會新增一筆沒有任何定位資訊的書籤。`ReaderScreen` 兩條路徑已有 null 守衛，只有面板會中。
  - 本計畫預設：**逐字保留**（純重構，面板照舊新增），不在 module 內加守衛。
  - 若審查者要求修正，另開 Issue 或併入本張的決策 7，需使用者決定。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/bookmark_controller.dart` | 新增 | `isSameBookmarkPosition`、`BookmarkController` |
| `app/lib/reader/bookmark_toggle.dart` | 刪除 | 併入 controller |
| `app/lib/screens/reader_screen.dart` | 修改 | 用 `_bookmarks`；刪 `_fxlBookmarks`、`_loadFxlBookmarks`、兩個 `…AtCurrentPosition`；`initState` 載入；面板關閉後重載擴大 |
| `app/lib/screens/notes_bottom_sheet.dart` | 修改 | 自建 `BookmarkController`；刪 `_matchesCurrentPosition`、自寫切換 |
| `app/test/reader/bookmark_controller_test.dart` | 新增（由 `bookmark_toggle_test.dart` 改名） | 純函式、`load`、`at`、`toggle` |
| `app/test/screens/reader_screen_test.dart` | 修改 | 新增「流式 EPUB 開書後星號正確」案例 |
| `CONTEXT.md` | 已完成 | 「本書書籤」詞條（設計定案時已加） |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 開發記錄、狀態 |

## Interface 草案（以實際編譯與既有型別為準）

```dart
/// 兩個位置是否相同：pdfPageIndex 有值比頁碼，否則比 epubLocatorJson 字串。
/// 兩者皆 null 時回傳 false。
bool isSameBookmarkPosition(Bookmark bookmark, BookmarkPositionContext position);

/// 本書書籤 module：不通知，呼叫端自己 setState。不碰 BuildContext。
class BookmarkController {
  BookmarkController({required BookmarksRepository repository, required String bookId});

  List<Bookmark> get bookmarks;

  /// 重新讀取清單。失敗只 debugPrint，清單保持舊值。
  /// 由 State 的 mounted 檢查與 setState 由呼叫端負責（回傳 Future 供呼叫端 await）。
  Future<void> load();

  /// 此位置的書籤（看記憶體清單，供星號圖示用）；沒有回傳 null。
  Bookmark? at(BookmarkPositionContext position);

  /// 直查 repository：有就刪、沒有就新增（名稱 = Bookmark.defaultName(position, l10n)）；
  /// 做完自己 load()。
  Future<void> toggle({required BookmarkPositionContext position, required AppLocalizations l10n});
}
```

> `toggle` 新增的 `Bookmark` 欄位逐字沿用現狀：`epubLocatorJson`、`progression`、`pdfPageIndex` 取自 `position`（ReaderScreen 的 EPUB 路徑只帶前兩者、PDF 路徑只帶 `pdfPageIndex`，面板三者皆從 context 取，結果相同）。

---

### Task 0：建立分支與提交設計文件

- [ ] **Step 1：** 分支 `epic-54/issue-25-bookmark`（已從含 PR #363 的 `main` 建立）。
- [ ] **Step 2：** 提交 `CONTEXT.md`、`epic.md`、`issues.md`、本計畫（純文件，一個 commit）。

### Task 1：`BookmarkController` 與測試

**Files：** 新增 `bookmark_controller.dart`、`test/reader/bookmark_controller_test.dart`（由 `bookmark_toggle_test.dart` 以 `git mv` 改名後改寫）；暫不刪 `bookmark_toggle.dart`（Task 2 刪）。

- [ ] **Step 1：** `git mv test/reader/bookmark_toggle_test.dart test/reader/bookmark_controller_test.dart`；三個既有案例改為對 `BookmarkController.toggle` 的斷言（無書籤→新增；已有→刪除；多筆只刪命中的那筆），位置改用 `BookmarkPositionContext`。
- [ ] **Step 2（紅）：** 新增案例：
  - `isSameBookmarkPosition`：PDF 同頁／不同頁；EPUB 同字串／不同字串；兩者皆 null 回 false；`pdfPageIndex` 有值時忽略 `epubLocatorJson`。
  - `load()`：載入後 `bookmarks` 為 repository 內容；repository 丟例外時清單保持舊值且不丟出。
  - `at()`：命中回書籤、未命中回 null；只看記憶體清單（未 `load` 時回 null）。
  - `toggle()`：記憶體清單是舊的（未 `load`）、資料庫已有該位置書籤 → 仍刪除，不重複新增（Review Focus 1）；toggle 後 `bookmarks` 已是最新；新增的名稱 = `Bookmark.defaultName(position, l10n)`；新增的書籤欄位三者取自 position。
- [ ] **Step 3（綠）：** 實作 `bookmark_controller.dart`。
- [ ] **Step 4：** `flutter analyze`；跑 `test/reader/bookmark_controller_test.dart`、`bookmark_test.dart`；commit。

### Task 2：`ReaderScreen` 遷移與載入時機修正（唯一行為變化）

**Files：** `reader_screen.dart`、`bookmark_toggle.dart`（刪除）、`test/screens/reader_screen_test.dart`。

- [ ] **Step 1（紅）：** 在 `reader_screen_test.dart` 書籤案例區（約 3312–3450，比照 3362 的 FXL 切換案例搭建）新增：
  - 流式 EPUB：repository 預先放一筆與當前定位相同的書籤，開書並收到位置回報後，**不點任何按鈕**，書籤按鈕圖示應為「已加入」。現行程式應失敗。
  - 流式 EPUB：開面板新增書籤後關閉，FAB 圖示應為「已加入」（Q8 擴大重載）。現行程式應失敗。
- [ ] **Step 2（綠，一個 commit）：**
  - 新增 `late final BookmarkController _bookmarks = BookmarkController(repository: widget.dependencies.bookmarksRepository, bookId: widget.bookId)`；`initState` 內 `_bookmarks.load().then((_) { if (mounted) setState(() {}); })`（放在 `_loadLayoutPresets()` 之後）。
  - 刪 `_fxlBookmarks`、`_loadFxlBookmarks`、`_bookmarkAtCurrentPosition`、`_pdfBookmarkAtCurrentPosition`。
  - 星號圖示（約 2255、2673）改用 `_bookmarks.at(...)`：EPUB 傳 `BookmarkPositionContext(epubLocatorJson: _epubPositionInfo?.locatorJson)`，PDF 傳 `BookmarkPositionContext(pdfPageIndex: _pdfPageInfo?.pageIndex)`；位置為 null 時行為與現狀相同（回 null）。
  - `_toggleBookmark`／`_togglePdfBookmark` 改呼叫 `_bookmarks.toggle(...)`，之後 `if (mounted) setState(() {})`；`l10n` 在 `await` 前取得；保留 `positionInfo == null`／`pageIndex == null` 的 return 守衛。FAB 的 context 不帶 `chapterTitle`（決策 6）。
  - `_handlePageRendered` 內 PDF 區塊移除 `_loadFxlBookmarks()` 呼叫與相關註解；`_pdfTocLoaded` 只留給目錄。
  - 面板關閉後：`_loadFxlBookmarks()` 改為 `_bookmarks.load().then(...setState)`，**移除 `_isFixedLayout || format == BookFormat.pdf` 條件**。
  - 刪 `import '../reader/bookmark_toggle.dart'`；`git rm app/lib/reader/bookmark_toggle.dart`。
- [ ] **Step 3：** 驗證：`flutter analyze`；跑 `reader_screen_test.dart` 全檔（含書籤 3076–3460、PDF 約 9303／9351）、`reader_chrome_bottom_bar_test.dart`、`bookmark_controller_test.dart`；Step 1 兩個新案例轉綠；commit。

### Task 3：`NotesBottomSheet` 遷移

**Files：** `notes_bottom_sheet.dart`。

- [ ] **Step 1：** `_NotesBottomSheetState` 新增 `late final BookmarkController _bookmarkController`（`initState` 建立，`repository: widget.bookmarksRepository`、`bookId: widget.bookId`）；`_bookmarks` 改讀 `_bookmarkController.bookmarks`；`_loadBookmarks` 改為 `_bookmarkController.load()` 後 `setState`（重新命名／刪除／全刪流程仍呼叫 `_loadBookmarks`，其內部資料操作不動）。
- [ ] **Step 2：** 刪 `_matchesCurrentPosition` 與 `_bookmarkAtCurrentPosition`，改 `_bookmarkController.at(widget.currentPosition)`；`_toggleBookmark` 改為 `await _bookmarkController.toggle(position: widget.currentPosition, l10n: l10n)` 後 `setState`，`l10n` 在 `await` 前取得。面板傳帶 `chapterTitle` 的 `currentPosition`（現狀），名稱不變。
- [ ] **Step 3：** `flutter analyze`；跑 `test/screens/notes_bottom_sheet_test.dart` 全檔、`reader_screen_test.dart` 書籤相關案例；commit。

### Task 4：收尾

- [ ] **Step 1（設計定案時已完成）：** `CONTEXT.md` 新增「本書書籤」。
- [ ] **Step 2：** `epic.md` 開發記錄；`issues.md` Issue 25 狀態；`docs/epics.md` 對應列同步。
- [ ] **Step 3：** 驗收：`grep -rn "_fxlBookmarks\|_loadFxlBookmarks\|_pdfBookmarkAtCurrentPosition\|_matchesCurrentPosition\|bookmark_toggle" app/lib app/test` 應為 0（含註解；有註解提到舊名稱須同步改字）。
- [ ] **Step 4：** `flutter analyze`；`node tool/check_l10n_hardcoded_strings.js`；`node tool/check_integration_keys.js`；完整 `flutter test`（`run_in_background`，只跑一個）。
- [ ] **Step 5：** WAVE 真機抽驗（流式 EPUB、FXL、PDF 各一本）：已有書籤的書開啟時星號正確；FAB 新增／移除；面板新增／移除後關閉，FAB 星號同步；面板重新命名／刪除／全刪；PDF 書籤跳轉。
- [ ] **Step 6：** 程式審查（報告存 `reviews/review-code-issue-25.md`，不進版控）；開 PR。
