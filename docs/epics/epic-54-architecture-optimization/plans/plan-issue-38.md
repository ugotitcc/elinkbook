# Issue 38 實作計畫：重新下載書籍收成一個 module

> **給執行者**：必須使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行。步驟用 `- [ ]` 追蹤，完成一步就改成 `- [x]`。

**目標**：把 `LibraryScreen._handleRedownload` 的「查伺服器、讀密碼、建 client、下載、升格、更新書、標索引」收成一個純 Dart module，畫面只留對話框、提示、重載。

**架構**：頂層函式 `redownloadBook(...)` 放 `app/lib/remote/remote_book_redownload.dart`，回傳列舉 `RedownloadOutcome`，不丟例外、不含 l10n 文字。依賴由參數傳入。

**技術**：Flutter 3.47.9／Dart 3.13.7；測試用既有假物件（`FakeOpdsClient`、`FakeRemoteServerRepository`、`FakeLibraryRepository`、`FakeFullTextSearchSettingsRepository`、`FakePathProviderPlatform`）。

**設計來源**：`epic.md`「Issue 38 設計決策」。本計畫只列施工步驟。

## Global Constraints

- 程式碼須在 Flutter 3.47.9 編譯，`flutter analyze` 必須顯示 `No issues found!`。
- 不新增任何使用者可見字串；三則 SnackBar 沿用既有 `libraryRemoteDisabledMessage`、`libraryRemoteServerNotFoundMessage`、`libraryRedownloadFailedMessage`。
- 不改 `remote_book_downloader.dart`、`RemoteDownloadJob`、`DownloadQueueController`。
- 提交不加 `Co-Authored-By`。註解與文件用正體中文。
- 測試範圍：只跑受影響的測試檔；完整 `flutter test` 只在最後一個 Task 跑一次。

## Review Focus

1. 離開畫面後下載完成：書庫仍須被更新（module 為純 Dart、不接收 `BuildContext`，由型別本身保證；行為由 Task 1 測試 1 釘住）。
2. 缺遠端資訊的書：必須在確認對話框**之前**就顯示提示（現況行為），不能變成先問再說不行。→ Task 2。
3. 索引標記丟例外：不得讓「檔案已下載成功」變成失敗。→ Task 1 測試 4。
4. 下載失敗：書的 `filePath`／`isDownloaded` 必須原樣。→ Task 1 測試 5。
5. 同一本書連點兩次：第二次須被忽略。→ Task 2（守衛留在畫面，沿用既有行為）。

## 現況（2026-11-15 讀碼確認）

- `library_screen.dart` `_handleRedownload`（約 509～612 行）：先檢查 `remoteServerId`／`remoteDownloadUrl`（缺則 SnackBar 後 return，**在對話框之前**）→ 重複點擊守衛 → `isMobileDataConnection` → 確認對話框 → 下載流程（本計畫要搬走的部分）。
- 下載與升格已共用 `downloadToTempFile`／`promoteToPermanent`（`remote/remote_book_downloader.dart`），兩者失敗時各自清暫存檔。
- 既有 widget 測試：`library_screen_test.dart` 的 `group('Issue 4：待下載書籍重新下載')`，6 個測試：取消、行動數據提示、成功、索引標記、失敗、缺網址。

## 目標 interface（`app/lib/remote/remote_book_redownload.dart`）

```dart
enum RedownloadOutcome { succeeded, notRemoteBook, serverNotFound, failed }

/// 這本書是否具備重新下載所需的遠端資訊（remoteServerId 與 remoteDownloadUrl 皆非 null）。
/// 畫面在跳確認對話框之前用它判斷，維持「缺資訊就立刻提示」的現況行為。
bool isRedownloadable(Book book);

Future<RedownloadOutcome> redownloadBook({
  required Book book,
  required RemoteServerRepository remoteServerRepository,
  required LibraryRepository libraryRepository,
  required FullTextSearchSettingsRepository fullTextSearchSettingsRepository,
  required OpdsClient Function() createOpdsClient,
});
```

行為：`!isRedownloadable` → `notRemoteBook`（不呼叫 `createOpdsClient`）；找不到伺服器 → `serverNotFound`；下載、升格、`updateBook` 任一步丟例外 → `failed`；`handleBookAvailable` 丟例外 → 吞掉，仍回 `succeeded`；其餘 `succeeded`。

---

## Task 1：module 與單元測試（TDD）

**Files:**
- Create: `app/lib/remote/remote_book_redownload.dart`
- Create: `app/test/remote/remote_book_redownload_test.dart`
- Modify: `app/test/support/fake_full_text_search_settings_repository.dart`（加錯誤注入）

**Interfaces:**
- Produces：上方「目標 interface」。
- Consumes：`downloadToTempFile`、`promoteToPermanent`（`remote_book_downloader.dart`）、`OpdsAcquisition(href:, format:)`。

- [x] **Step 1：假物件加錯誤注入。** 在 `FakeFullTextSearchSettingsRepository` 加 `Object? handleBookAvailableError;`（建構子具名參數，預設 `null`）；`handleBookAvailable` 先記錄呼叫，再於 `handleBookAvailableError != null` 時 `throw`。
- [x] **Step 2：寫失敗測試。** 測試檔比照 `remote_book_downloader_test.dart` 的 `setUp`（`FakePathProviderPlatform` 指向暫存目錄）。伺服器 `srv1`、待下載書 `pendingBook()` 比照 `library_screen_test.dart` 同名輔助。測試名稱與斷言：
  1. `成功：回傳 succeeded，更新 filePath 為 remote_books 下的檔案且 isDownloaded 為 true，書庫仍只有 1 本`
  2. `成功：把伺服器密碼傳給 client.downloadBook`（`downloadBookPasswords` 等於 `['secret']`；以 `addServer(server, password: 'secret')` 建立）
  3. `成功：呼叫 handleBookAvailable，參數是更新後的書`（`handleBookAvailableCalls.single.isDownloaded` 為 true）
  4. `handleBookAvailable 丟例外：仍回 succeeded，書已更新`
  5. `下載失敗：回傳 failed，書的 filePath／isDownloaded 不變`（`FakeOpdsClient(downloadError: Exception('boom'))`）
  6. `缺 remoteDownloadUrl：回傳 notRemoteBook，且不呼叫 createOpdsClient`（用計數的 `createOpdsClient` lambda；伺服器清單放入 `srv1`）
  7. `缺 remoteServerId、但有 remoteDownloadUrl：回傳 notRemoteBook（不是 serverNotFound），且不呼叫 createOpdsClient`（伺服器清單放入 `srv1`；若實作漏掉前置檢查，會誤回 `serverNotFound`，此測試即失敗）
  8. `remoteServerId 指向不存在的站點：回傳 serverNotFound`
  9. `isRedownloadable：remoteServerId 或 remoteDownloadUrl 任一為 null 時為 false，皆非 null 時為 true`
- [x] **Step 3：執行確認失敗。** `cd app && flutter test test/remote/remote_book_redownload_test.dart`；預期：編譯失敗（找不到 `redownloadBook`）。
- [x] **Step 4：實作 `redownloadBook` 與 `isRedownloadable`。** 流程依序為：`if (!isRedownloadable(book)) return RedownloadOutcome.notRemoteBook`（最前面，須在任何 I/O 之前短路）→ 其後照 `_handleRedownload` 現有順序（`listServers` 迴圈找 id → `loadPassword` → `createOpdsClient()` → `downloadToTempFile` → `promoteToPermanent` → `book.copyWith(filePath:, isDownloaded: true)` → `libraryRepository.updateBook` → `try { handleBookAvailable } catch (_) {}`）。外層 `try/catch (_)` 回 `failed`。**不**保留 `tempPath` 清理（死碼，見設計決策 5）。`handleBookAvailable` 的 `catch` 上方註解寫明「刻意靜默：索引為衍生資料，可由重建索引補」。
- [x] **Step 5：執行確認通過。** 同 Step 3 指令；預期：9 個測試全過。
- [x] **Step 6：`cd app && flutter analyze` 乾淨後提交。** `git add app/lib/remote/remote_book_redownload.dart app/test/remote/remote_book_redownload_test.dart app/test/support/fake_full_text_search_settings_repository.dart`；訊息 `feat(remote): 重新下載書籍收成 redownloadBook module（epic-54 Issue 38 Task 1）`。

## Task 2：畫面改用 module，更新 widget 測試

**Files:**
- Modify: `app/lib/screens/library_screen.dart`（`_handleRedownload`，約 509～612 行；刪除隨之無用的 import）
- Modify: `app/test/screens/library_screen_test.dart`（`group('Issue 4：待下載書籍重新下載')`）

**Interfaces:**
- Consumes：Task 1 的 `isRedownloadable`、`redownloadBook`、`RedownloadOutcome`。
- Produces：無新公開介面；`LibraryScreen` 對外行為不變。

- [x] **Step 1：確認現況測試全過。** `cd app && flutter test test/screens/library_screen_test.dart --plain-name "Issue 4"`；預期：6 個全過（改動前基線）。
- [x] **Step 2：改寫 `_handleRedownload`。** 順序維持：`!isRedownloadable(book)` → SnackBar `libraryRemoteDisabledMessage` 後 return（**在對話框之前**）→ `_redownloadingBookIds` 守衛 → `isMobileDataConnection` → `mounted` → `_confirmRedownload` → `_redownloadingBookIds.add` → `try { outcome = await redownloadBook(...) } finally { remove }` → `if (!mounted) return` → 依 `outcome` 對應：`succeeded` → `await _bookListController.loadBooks()`；`serverNotFound` → `libraryRemoteServerNotFoundMessage`；`failed` → `libraryRedownloadFailedMessage`；`notRemoteBook` → `libraryRemoteDisabledMessage`。依賴取自 `widget.sources.remoteServerRepository`、`widget.sources.createOpdsClient`、`widget.dependencies.libraryRepository`、`widget.dependencies.fullTextSearchSettingsRepository`。
- [x] **Step 3：刪除無用 import。** 以 `flutter analyze` 的 `unused_import` 為準（`dart:io` 因 `_calculateFileSize`〔約 1808 行〕仍用 `File(book.filePath)`，**須保留**；預期無用的是 `remote_book_downloader.dart`、`opds_types.dart`、`remote_server_profile.dart`，其餘仍在用的不動）。
- [x] **Step 4：刪除被 module 測試接手的 widget 測試。** 刪「確認後成功重新下載…」與「重新下載完成後呼叫 handleBookAvailable」兩個；**保留**「取消」「行動數據提示」「下載失敗時顯示錯誤訊息」，以及「書本缺 remoteDownloadUrl…」（它是 `notRemoteBook` 到 SnackBar 的唯一對應測試，且釘住「對話框之前」的順序，見 Review Focus 2；與設計決策 7 的差異，**已於 `reviews/review-plan-issue-38.md` M-1 審查批准保留**：module 單元測試只證明回傳 `notRemoteBook`，保護不了日後有人把確認對話框移到前置判斷之前）。
- [x] **Step 5：執行確認通過。** `cd app && flutter test test/screens/library_screen_test.dart test/remote/remote_book_redownload_test.dart`；預期：全過。
- [x] **Step 6：`flutter analyze` 乾淨後提交。** 訊息 `refactor(library): 重新下載改用 redownloadBook，刪除死碼暫存檔清理（epic-54 Issue 38 Task 2）`。

## Task 3：整體驗證與文件

**Files:**
- Modify: `docs/epics/epic-54-architecture-optimization/epic.md`（追加 Issue 38 實作與驗證紀錄）
- Modify: `docs/epics/epic-54-architecture-optimization/issues.md`（Issue 38 狀態）

- [x] **Step 1：兩個靜態守衛。** `cd app && node tool/check_l10n_hardcoded_strings.js` 與 `node tool/check_integration_keys.js`（Windows 用 pnpm 內建 Node，見記憶）；預期：兩者 PASS。
- [x] **Step 2：完整測試。** `cd app && flutter test`；預期：0 失敗（基線 5263 通過、2 略過，數量因刪 2 個 widget 測試、加 9 個單元測試而變動）。
- [x] **Step 3：寫入 `epic.md`。** 記實作內容、與設計決策的差異（新增 `isRedownloadable`；保留「缺網址」widget 測試，理由取自 `review-plan-issue-38.md` M-1：它是 UI 順序守衛，module 測試無法取代）、驗證結果，以及**未驗證**：未在真機對真實 OPDS 伺服器實測重新下載。
- [x] **Step 4：`issues.md` 的 Issue 38 狀態改為「已完成待合併」。** 提交並 push，開 PR。
