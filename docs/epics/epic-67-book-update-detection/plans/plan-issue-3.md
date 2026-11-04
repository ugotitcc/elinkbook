# Issue 3：手動入口與強制重新連結 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** (1) 書籍動作選單新增「用新檔案更新此書」：使用者選檔、只檢查格式相同、確認後以 `replaceBook` 取代；(2) 閱讀器的「重新選取檔案」遇到「格式相同但內容與記錄不符」時，不再直接拒絕，而是詢問「強制重新連結」，確認後只更新檔案路徑（不改指紋）。兩條路徑成功後都要清掉被換掉的書封面圖片快取。

**Architecture:** 兩條路徑都不新增服務。手動更新直接呼叫 Issue 1 的 `BookImportService.replaceBook`（不帶 `candidate`），流程收在新的 `screens/support/manual_book_update_flow.dart`，`LibraryScreen` 只負責接線與重新載入書架。強制重新連結在 `relinkBook` 新增 `force` 具名參數；沿用既有 `BookRelinkFailure(contentMismatch)` 當作「待呼叫端確認」的訊號，`OpenBookFlow.relink` 新增選用的 `confirmForce` 回呼，由 `ReaderScreen` 以對話框回答後帶 `force: true` 再呼叫一次。

**Tech Stack:** Flutter／Dart、`ChangeNotifier`、ARB 在地化（`flutter gen-l10n`）、`flutter_test`、`sqflite_common_ffi`（服務測試）。

**Spec:** `docs/epics/epic-67-book-update-detection/spec.md`（「各入口的互動」手動更新、「重新連結的相容」）；工單見同目錄 `issues.md` Issue 3；Issue 1 介面見 `plans/plan-issue-1.md`；Issue 2 見 `plans/plan-issue-2.md`；ADR 0040。

**分支建議：** `epic-67/issue-3-manual-update-force-relink`（從最新 `main` 切出）。

## 已查證事實（2026-11-04 讀程式所得）

| # | 事實 | 對設計的影響 |
|---|---|---|
| F1 | `relinkBook`（`book_import_service_impl.dart:274`）順序：讀書 → 僅 EPUB／PDF／AZW3 可重新連結（`_relinkableFormats`）→ 格式相同 → 新 URI 不是別本書的來源 → 算指紋（EPUB 先取 OPF identifier、其餘 SHA-256）→ 與記錄比對，不符回 `contentMismatch` → 持久化授權／落地複本 → `updateBook(filePath, 指紋沿用)` | 強制路徑只需略過第 5 步的比對；格式、重複來源、持久化與寫入完全沿用。第 6 步在比對之後，所以「先回 `contentMismatch`、等使用者確認、再帶 `force` 重呼叫」不會在確認前消耗任何持久化授權 |
| F2 | 重新連結的唯一畫面入口是閱讀器：`ReaderScreen._handleRelinkPressed` → `OpenBookFlow.relink(pick)`（`open_book_flow.dart:219`）。`OpenBookRelink` typedef 是 `Future<BookRelinkResult> Function(String uri, String? displayName)`；`contentMismatch` 目前走 `readerStorageRelinkContentMismatch` SnackBar | 書架沒有重新連結入口，「強制重新連結」的對話框只加在閱讀器。`OpenBookRelink` typedef 加 `force` 後，`reader_screen_test.dart`、`open_book_flow_test.dart` 的假 `relinkBook` 簽章要同步 |
| F3 | `replaceBook(bookId, newUri, {displayName, candidate, sourceRefs})` 的 `candidate` 可為 null：`source = candidate?.stagedPath ?? newUri`（`book_import_service_impl.dart:445`）；內部已檢查格式相同（不符回 `formatMismatch`）、允許所有格式、永不拋例外、同一本書序列化 | 手動更新不需要候選與暫存。但服務在格式不符時才回報——要「確認前」就擋掉格式不符，必須在 UI 端先做同一個判斷 |
| F4 | 服務內部格式判斷是私有的 `_detectImportFormat(uri, displayName)`（displayName 優先、URI 退路，`book_import_service_impl.dart:1017`）；公開的 `detectBookFileFormat(String)` 只吃單一字串。`app/lib/screens/` 目前沒有任何檔案 import `book_import_service_impl.dart`（審查 M-2） | 抽出公開的 `detectImportFileFormat(uri, displayName)`，服務與手動更新流程共用，避免兩邊判斷不一致。為維持畫面層只依賴抽象的分層，新增薄檔 `app/lib/library/book_file_format_detection.dart`，僅 `export 'book_import_service_impl.dart' show detectImportFileFormat;`，畫面層只 import 這個薄檔（不從 `book_import_service.dart` re-export：實作檔已 import 介面檔，會形成循環） |
| F5 | `SingleBookFilePicker`／`pickSingleBookFileViaFilePicker`（`book_import_picker_helper.dart:230`）可注入；`ReaderScreen` 以 `widget.pickSingleBookFile ?? pickSingleBookFileViaFilePicker` 使用。`allowedExtensions` 傳 `BookFileFormat` 名稱即可（`epub/pdf/azw3/txt/cbz/md` 與 `detectBookFileFormat` 的副檔名一一對應） | `LibraryScreen` 比照加可注入的 `pickSingleBookFile` |
| F6 | 動作選單：`BookAction` 列舉（`book_action_sheet.dart:10`）＋ `BookActionSheet`（`showRemoveCache`、`showLayoutOverride` 控制可見性）＋ `LibraryScreen._openBookActionSheet` 的 `switch`。`ReaderFeatureDependencies.bookImportService` 已可從 `LibraryScreen.dependencies` 取得 | 新增 `BookAction.updateBook`、`showUpdateBook`；不需新的依賴 |
| F7 | `Book.isDownloaded == false`（Calibre 僅有詮釋資料、尚未下載）的書沒有本機檔案 | 這類書不顯示「用新檔案更新此書」（取代會把它變成沒有 Calibre 下載關聯的本機檔，語意不明；使用者應先下載） |
| F8 | 取代成功後封面檔可能被改寫或移除（`BookReplaceSuccess.updatedBook.coverPath` 可為 null）；`BookCover` 用 `Image.file`，圖片快取以路徑為鍵。`evictCoverImageCache(String)`（`book_update_resolver.dart`）已存在且吞例外 | 手動更新成功時對「舊 `book.coverPath`」與「`updatedBook.coverPath`」各 evict 一次（非 null、去重）。強制重新連結不改封面，不需 evict——工單的 evict 要求只適用取代 |
| F9 | 可重用字串：`bookUpdateReplaceNotice`（偏移提示）、`bookUpdateResultReplacedOnlyMessage(1)`、`bookUpdateFailedMessage(1)`、`cancel`；可重用函式 `showBookUpdateResultSnackBarWith(messenger, l10n, BookUpdateApplyResult)` | 手動更新的成功／失敗提示不新增字串，直接以 `BookUpdateApplyResult(replaced: 1)`／`(failed: 1)` 呈現 |
| F10 | `fake_book_import_service.dart` 的 `relinkBook` 與 `RelinkCallRecord` 只記錄 `bookId/newUri/displayName`；`replaceBook` 已有 `replaceResultsByBookId`、`replaceCalls`、`lastReplaceDisplayName` | 假服務補記 `force`；其餘不動 |

## 已確認決策（本計畫自行定案，待人類審閱）

- **D1：以既有 `BookRelinkFailure(contentMismatch)` 當作「待確認」結果，不新增密封子類別。** 工單的「回傳可由呼叫端繼續確認的結果」＝此結果本身；呼叫端確認後再以 `force: true` 重呼叫。優點：`BookRelinkResult` 的所有既有 `switch` 不受影響。代價：確認後會再讀一次檔案（`force` 時若原書有指紋則略過指紋計算，所以不會再整檔雜湊一次）。
- **D2：`relinkBook(..., {String? displayName, bool force = false})`。** `force: true` 只略過「指紋不符」這一關；`book == null`／格式不可重新連結／格式不符／已在書庫（別本書的來源）／持久化失敗仍照常回對應失敗。成功時 `contentFingerprint` 維持原值（原值為 null 才補寫，此時仍須計算指紋）。
- **D3：`OpenBookFlow.relink(pick, {Future<bool> Function()? confirmForce})`。** 收到 `contentMismatch` 且有 `confirmForce` 時呼叫之：回 `true` → 以 `force: true` 再呼叫 `relinkBook`；回 `false` → `OpenBookRelinkCancelled`（不顯示 SnackBar）。沒有 `confirmForce` 時維持現狀（回 `OpenBookRelinkFailed(contentMismatch)`），既有測試與 SnackBar 文案不變。確認期間狀態維持 `OpenBookRelinking`（按鈕停用）。
- **D4：手動更新僅對 `isDownloaded` 的書顯示，所有格式皆可。** 格式限定與原書相同；格式判斷與服務共用 `detectImportFileFormat`（F4），不符時在確認前以 SnackBar 拒絕，不呼叫 `replaceBook`。
- **D5：手動更新的確認對話框一定出現**（spec：「通過即進入取代確認」），內容含新檔名、書名與偏移提示（沿用 `bookUpdateReplaceNotice`）；不做身份比對、不列候選。
- **D6：由確認對話框承載等待（審查 I-3）。** 使用者按「更新」時對話框**不關閉**：內部設為更新中（「取消」「更新」皆停用、不可用返回鍵或點外面關閉、顯示 `bookUpdateApplying`「處理中…」），在對話框內 `await replaceBook`，完成後才以 `BookReplaceResult` pop。如此取代期間書架被模態擋住，不會有開書、刪除、移動與取代並行的競態，也有等待回饋，不需要另做全域遮罩。
- **D8：兩個新對話框都遵守 E-Ink 零動畫規範（審查 M-1）。** `showForceRelinkDialog(context, {bool isEinkMode = false})`、`runManualBookUpdate(..., {bool isEinkMode = false})`，`showDialog` 一律帶 `animationStyle: isEinkMode ? AnimationStyle.noAnimation : null`（比照 `book_update_summary_dialog.dart`）；`ReaderScreen` 傳 `widget.isEinkMode`，`LibraryScreen` 傳 `widget.appearance.isEinkMode`。
- **D7：新增字串（四份 ARB 同步）：** `bookActionUpdateBook`（選單項目，兼作確認對話框標題）＝「用新檔案更新此書」、`bookManualUpdateConfirmMessage(title, fileName)`、`bookManualUpdateConfirmButton`＝「更新」、`bookManualUpdateFormatMismatch`＝「選取的檔案格式與此書不同，無法更新」、`readerForceRelinkTitle`＝「強制重新連結？」、`readerForceRelinkMessage`、`readerForceRelinkConfirm`＝「強制重新連結」。

## Global Constraints

- 所有註解、文件、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文。
- 畫面字串走 `AppLocalizations`，四份 ARB（`app_zh_TW`／`app_zh`／`app_zh_CN`／`app_en`）同步，並 `flutter gen-l10n` 重產；不得硬編碼中文。
- Flutter 3.41.9：不得使用此版本沒有的 API。
- 手動更新與強制重新連結都只檢查「格式相同」，不做書名／作者／識別碼比對（spec 使用者故事 20、21、49）。
- 強制重新連結「只更新檔案路徑，不改指紋」；此規則對所有書通用，不新增資料庫欄位、不記錄哪本書被取代過（spec「重新連結的相容」）。
- 既有重新連結的成功與其他失敗分支（`formatMismatch`、`alreadyInLibrary`、`failed`）行為不回歸；無 `confirmForce` 時 `contentMismatch` 的 SnackBar 文案不變。
- 取代成功後須 evict 舊／新封面的 `FileImage` 快取（ADR 0040、F8）。
- 提交前：`flutter analyze` 必須 "No issues found!"；`node tool/check_l10n_hardcoded_strings.js`；`node tool/check_integration_keys.js`（皆在 `app/` 下）。
- 測試範圍：每個 Task 只跑觸及的測試檔；完整 `flutter test --no-pub` 只在最後一個 Task 執行一次。指令工作目錄為 `app/`；測試與 analyze 後 `git checkout pubspec.lock windows/flutter` 還原工具雜訊。

## Review Focus

1. **強制重新連結不得繞過其他檢查**（Task 1）：`force: true` 時格式不符仍回 `formatMismatch`、新 URI 是別本書的來源仍回 `alreadyInLibrary`、不可重新連結的格式（TXT／MD／CBZ）仍回 `failed`，且任何失敗都不改記錄。
2. **確認前不留副作用**（Task 1、2）：`contentMismatch` 回傳時資料庫與檔案系統完全不動；使用者在對話框按取消時只呼叫過一次 `relinkBook`（`force: false`），沒有任何 `force: true` 呼叫。
3. **強制成功後指紋不變、閱讀進度與註記不動**（Task 1）：只換 `filePath`；`id`／進度／分類欄位與呼叫前相同。
4. **手動更新選錯格式或無法辨識副檔名**（Task 3）：不彈確認、不呼叫 `replaceBook`、顯示格式不符 SnackBar；選檔取消則完全靜默。
5. **取代失敗時書不動**（Task 3）：`BookReplaceFailure`（含各原因）顯示「更新失敗，書籍沒有任何變動」；失敗時不 evict 封面、不重新載入書架以外的任何東西。
8. **取代進行中書架不可操作**（Task 3；審查 I-3）：對話框在 `replaceBook` 完成前不關閉，期間兩顆按鈕停用、返回鍵與點外面無效，避免開書／刪除／移動與取代並行。
6. **非同步空窗的畫面卸載**（Task 2、3）：選檔或對話框期間畫面被卸載，不得再使用已失效的 `BuildContext`、不得拋例外；SnackBar 用事先取得的 `ScaffoldMessengerState`。
7. **選單可見性**（Task 3）：`isDownloaded == false` 的書沒有「用新檔案更新此書」；其餘所有格式都有。

---

### Task 1：服務——`relinkBook` 的 `force` 與共用格式判斷

**Files:**
- Modify: `app/lib/library/book_import_service.dart`（介面 `relinkBook` 加 `force`、`BookRelinkFailureReason.contentMismatch` 文件註解補「呼叫端可確認後以 `force` 重試」）
- Modify: `app/lib/library/book_import_service_impl.dart`（`relinkBook`；新增頂層 `detectImportFileFormat`，`_detectImportFormat` 改委派）
- Create: `app/lib/library/book_file_format_detection.dart`（薄 re-export，見 F4）
- Modify: `app/test/support/fake_book_import_service.dart`（`RelinkCallRecord`／`relinkBook` 補 `force`）
- Modify: `app/test/wifi_transfer/wifi_transfer_service_test.dart:39`（私有 `_ThrowingImportService.relinkBook` 簽章同步為 `{String? displayName, bool force = false}`，否則介面擴充後整個測試檔編譯失敗；審查 I-1）
- Test: `app/test/library/book_import_service_test.dart`（既有 relink 測試群組旁新增 `force` 案例）

**Interfaces:**
- Consumes: Issue 1／epic-15 既有 `relinkBook`、`computeBookContentFingerprint`、`_persistPermissionOrLandCopy`。
- Produces:
  - `Future<BookRelinkResult> relinkBook(String bookId, String newUri, {String? displayName, bool force = false})`（`BookImportService` 與實作、假服務同簽章）。
  - 頂層 `BookFileFormat? detectImportFileFormat(String uri, String? displayName)`（定義於 `book_import_service_impl.dart`，與 `detectBookFileFormat` 並列；displayName 優先，無法辨識時退回 URI；畫面層改由 `library/book_file_format_detection.dart` 取得）。
  - 假服務 `RelinkCallRecord.force`（`bool`）。

- [ ] **Step 1: 寫失敗測試**（`book_import_service_test.dart`，沿用該檔既有 relink 測試的 fixture 與建構方式，測試名稱用中文）
  - `relinkBook force：內容不符時 force:false 回 contentMismatch 且記錄完全不動`
  - `relinkBook force：內容不符時 force:true 成功，filePath 更新、contentFingerprint 與 id／閱讀進度不變`（斷言 `BookRelinkSuccess.updatedBook.contentFingerprint == 原指紋`，並從 repository 重新讀書驗證）
  - `relinkBook force：格式不符時即使 force:true 仍回 formatMismatch`
  - `relinkBook force：新 URI 是別本書的來源時即使 force:true 仍回 alreadyInLibrary`
  - `relinkBook force：TXT／MD／CBZ 即使 force:true 仍回 failed`
  - `relinkBook force：原書沒有指紋時 force:true 仍補寫新檔指紋`
  - `relinkBook force：內容相符時 force:true 與 force:false 結果相同`
  - `detectImportFileFormat：displayName 優先、URI 退路、兩者皆無法辨識回 null`

- [ ] **Step 2: 執行確認失敗**
  Run（`app/`）：`flutter test test/library/book_import_service_test.dart --no-pub`
  Expected: 編譯失敗或新案例 FAIL（`force` 參數／`detectImportFileFormat` 未定義）。

- [ ] **Step 3: 實作**
  - `book_import_service_impl.dart`：新增頂層 `detectImportFileFormat`（內容即現有 `_detectImportFormat` 的運算式），`_detectImportFormat` 改為呼叫它。
  - `relinkBook` 簽章加 `bool force = false`。第 5 步比對改為：原書有指紋且 `force == true` 時**略過指紋計算與比對**（第 4 步的計算移到需要時才做）；原書沒有指紋時（不論 `force`）照舊計算並補寫。第 1～3、6、7 步與例外處理不動。
  - 新增 `book_file_format_detection.dart`（一行 `export`）。
  - 介面、假服務與 `wifi_transfer_service_test.dart` 的 `_ThrowingImportService` 同步簽章；假服務把 `force` 記進 `RelinkCallRecord`。介面文件註解寫明：`contentMismatch` 是「呼叫端可詢問使用者後以 `force: true` 重試」的訊號。

- [ ] **Step 4: 執行確認通過**
  Run: `flutter test test/library/book_import_service_test.dart --no-pub`
  Expected: PASS，既有 relink 案例不回歸。

- [ ] **Step 5: Commit**
  ```bash
  git add app/lib/library app/test/support/fake_book_import_service.dart app/test/library/book_import_service_test.dart app/test/wifi_transfer/wifi_transfer_service_test.dart
  git commit -m "feat(library): relinkBook 支援 force 強制重新連結並抽出共用格式判斷（epic-67 Issue 3）"
  ```

---

### Task 2：閱讀器——強制重新連結的確認流程

**Files:**
- Create: `app/lib/screens/widgets/force_relink_dialog.dart`
- Modify: `app/lib/reader/open_book_flow.dart`（`OpenBookRelink` typedef、`relink` 的 `confirmForce`）
- Modify: `app/lib/screens/reader_screen.dart:492`（`relinkBook:` 接線帶 `force`）、`:1529` `_handleRelinkPressed`（傳入 `confirmForce`）
- Modify: `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`，重產 `app_localizations*.dart`
- Test: `app/test/reader/open_book_flow_test.dart`、`app/test/screens/reader_screen_test.dart`、Create `app/test/screens/widgets/force_relink_dialog_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `relinkBook(..., force:)`。
- Produces:
  - `typedef OpenBookRelink = Future<BookRelinkResult> Function(String uri, String? displayName, {bool force})`。
  - `Future<OpenBookRelinkOutcome> OpenBookFlow.relink(Future<OpenBookPickedFile?> Function() pick, {Future<bool> Function()? confirmForce})`，語意見 D3。
  - `Future<bool> showForceRelinkDialog(BuildContext context, {bool isEinkMode = false})`（D8）：回 `true` 表確認；取消、點外面關閉、返回鍵一律回 `false`。Key：`force_relink_dialog`（AlertDialog）、`force_relink_cancel`、`force_relink_confirm`。

- [ ] **Step 1: 新增 ARB 字串（四份同步）並重產**
  `readerForceRelinkTitle`／`readerForceRelinkMessage`／`readerForceRelinkConfirm`（含 `@` 描述）。繁中文案：標題「強制重新連結？」；內文「選取的檔案與原書內容不一致，可能不是同一本書。若這是同一本書的新版本，可強制重新連結：只會更換檔案位置，閱讀進度與註記位置不會調整，可能因內容不同而偏移。」；按鈕「強制重新連結」。
  Run: `flutter gen-l10n`

- [ ] **Step 2: 寫失敗測試**
  - `force_relink_dialog_test.dart`：`按確認回 true`、`按取消回 false`、`點對話框外面關閉回 false`（以 `showDialog` 包裝在 `MaterialApp` 並帶 `AppLocalizations` delegates／locale）。
  - `open_book_flow_test.dart`：
    - `contentMismatch 且 confirmForce 回 true：以 force:true 再呼叫一次並重新開書（OpenBookRelinkReopened）`（斷言 `relinkBook` 被呼叫兩次，第二次 `force == true`）
    - `contentMismatch 且 confirmForce 回 false：回 OpenBookRelinkCancelled、只呼叫一次 relinkBook（force:false）、狀態回到 OpenBookFailed`
    - `contentMismatch 但沒有 confirmForce：維持 OpenBookRelinkFailed(contentMismatch)`（回歸）
    - `formatMismatch／alreadyInLibrary／failed 不觸發 confirmForce`
    - `confirmForce 拋例外視為 failed，不拋出`
    - `confirmForce 等待期間 flow 被 dispose：不再呼叫第二次 relinkBook`
  - `reader_screen_test.dart`：
    - `重新選取檔案遇 contentMismatch：出現強制重新連結對話框；按取消不顯示 SnackBar 且錯誤視圖仍在`
    - `按確認後以 force:true 重新連結並重新開書`（斷言假服務 `relinkCalls` 兩筆，第二筆 `force == true`）
  - 既有測試中假 `relinkBook` 的簽章依 typedef 補 `{bool force = false}`。
  - **既有測試調整（審查 I-2）：** `reader_screen_test.dart:13279` 附近以 Map 迴圈驗證四種失敗原因 SnackBar 的測試，把 `BookRelinkFailureReason.contentMismatch` 條目移出迴圈（改由上面兩個新的專屬測試覆蓋，因為現在會先彈對話框而不是 SnackBar）；其餘三個原因維持原迴圈。

- [ ] **Step 3: 執行確認失敗**
  Run: `flutter test test/reader/open_book_flow_test.dart test/screens/reader_screen_test.dart test/screens/widgets/force_relink_dialog_test.dart --no-pub`
  Expected: FAIL／編譯失敗。

- [ ] **Step 4: 實作**
  - `force_relink_dialog.dart`：`AlertDialog`（標題、內文、`l10n.cancel` 與 `readerForceRelinkConfirm` 兩個 `TextButton`），`showDialog<bool>` 結果以 `== true` 轉成 `bool`。
  - `OpenBookFlow.relink`：第一次 `relinkBook(uri, name)` 結果為 `BookRelinkFailure(contentMismatch)` 且 `confirmForce != null` 時，先檢查 `_disposed`，再 `await confirmForce()`；`true` 且仍未 dispose → `relinkBook(uri, name, force: true)` 並照原邏輯轉成 outcome；`false` → `OpenBookRelinkCancelled`。整段包在既有 try/catch 內，維持「保證不拋例外」。
  - `reader_screen.dart`：`relinkBook:` 轉呼叫 `importService.relinkBook(bookId, uri, displayName: name, force: force)`；`_handleRelinkPressed` 傳 `confirmForce: () async => mounted && await showForceRelinkDialog(context, isEinkMode: widget.isEinkMode)`（已卸載時回 `false`）。`force_relink_dialog.dart` 的 `showDialog` 帶 `animationStyle: isEinkMode ? AnimationStyle.noAnimation : null`（D8）。

- [ ] **Step 5: 執行確認通過**
  Run: 同 Step 3 指令
  Expected: PASS。

- [ ] **Step 6: 靜態檢查**
  Run: `flutter analyze` → "No issues found!"；`node tool/check_l10n_hardcoded_strings.js`；`node tool/check_integration_keys.js`。

- [ ] **Step 7: Commit**
  ```bash
  git add app/lib/screens/widgets/force_relink_dialog.dart app/lib/reader/open_book_flow.dart app/lib/screens/reader_screen.dart app/lib/l10n app/test/reader/open_book_flow_test.dart app/test/screens/reader_screen_test.dart app/test/screens/widgets/force_relink_dialog_test.dart
  git commit -m "feat(reader): 重新選取檔案內容不符時詢問強制重新連結（epic-67 Issue 3）"
  ```

---

### Task 3：書架——「用新檔案更新此書」

**Files:**
- Create: `app/lib/screens/support/manual_book_update_flow.dart`
- Modify: `app/lib/screens/book_action_sheet.dart`（`BookAction.updateBook`、`showUpdateBook`、選項 Key `book_action_update_book`）
- Modify: `app/lib/screens/library_screen.dart`（建構子 `pickSingleBookFile`、`_openBookActionSheet` 傳 `showUpdateBook: book.isDownloaded` 並處理 `BookAction.updateBook`）
- Modify: 四份 ARB 與重產的 `app_localizations*.dart`
- Test: Create `app/test/screens/support/manual_book_update_flow_test.dart`；Modify `app/test/screens/book_action_sheet_test.dart`、`app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `detectImportFileFormat`；`BookImportService.replaceBook`；`showBookUpdateResultSnackBarWith`、`BookUpdateApplyResult`、`evictCoverImageCache`、`SingleBookFilePicker`、`pickSingleBookFileViaFilePicker`。
- Produces:
  - `enum ManualBookUpdateOutcome { cancelled, formatMismatch, replaced, failed }`
  - `Future<ManualBookUpdateOutcome> runManualBookUpdate(BuildContext context, {required Book book, required BookImportService importService, required SingleBookFilePicker pickFile, bool isEinkMode = false, void Function(String coverPath) onCoverChanged = evictCoverImageCache})`
    - 流程：`pickFile([book.format.name])`（null → `cancelled`）→ `detectImportFileFormat(uri, displayName) != book.format` → 顯示 `bookManualUpdateFormatMismatch` SnackBar、回 `formatMismatch` → 確認對話框（`showDialog<BookReplaceResult>`，`barrierDismissible: false`、`animationStyle` 依 `isEinkMode`；內部為 `StatefulWidget`，按「更新」後進入更新中狀態並在對話框內 `await replaceBook(book.id, uri, displayName: displayName)`，完成後以結果 pop；`replaceBook` 拋例外視為 `BookReplaceFailure(writeFailed)`；按「取消」pop `null` → `cancelled`；更新中以 `PopScope(canPop: false)` 擋返回鍵，D6）→ 結果：成功 → evict 舊 `book.coverPath` 與 `updatedBook.coverPath`（非 null、去重、單筆失敗不影響）、`showBookUpdateResultSnackBarWith(replaced: 1)`、回 `replaced`；失敗或拋例外 → `failed: 1` 的 SnackBar、回 `failed`。永不拋例外；每個 `await` 之後檢查 `context.mounted`，SnackBar 用進入時就取得的 `ScaffoldMessengerState`／`AppLocalizations`。
  - 對話框 Key：`book_manual_update_dialog`、`book_manual_update_notice`（偏移提示）、`book_manual_update_cancel`、`book_manual_update_confirm`、`book_manual_update_applying`（更新中文字，沿用 `bookUpdateApplying`）。
  - `BookActionSheet({..., bool showUpdateBook = true})`；`BookAction.updateBook` 排在 `move`／`layoutOverride` 之後、`removeCache` 之前。

- [ ] **Step 1: 新增 ARB 字串（四份同步）並重產**
  `bookActionUpdateBook`、`bookManualUpdateConfirmMessage`（placeholders：`title`、`fileName`，String）、`bookManualUpdateConfirmButton`、`bookManualUpdateFormatMismatch`（含 `@` 描述）。繁中文案：「用新檔案更新此書」／「將以「{fileName}」取代「{title}」的檔案內容。閱讀進度、分類與版面偏好會保留。」／「更新」／「選取的檔案格式與此書不同，無法更新」。簡中與英文同步翻譯（簡中詞彙用大陸慣用語，不得混入繁體字）。
  Run: `flutter gen-l10n`

- [ ] **Step 2: 寫失敗測試**
  - `manual_book_update_flow_test.dart`（假服務＋假選檔器＋最小 `MaterialApp`／`Scaffold`，帶 l10n delegates）：
    - `取消選檔：回 cancelled、沒有 SnackBar、未呼叫 replaceBook`
    - `格式不符（EPUB 書選到 .pdf）：回 formatMismatch、出現格式不符 SnackBar、不彈確認、未呼叫 replaceBook`
    - `副檔名無法辨識（無 displayName 的不透明 URI）視為格式不符`
    - `displayName 優先於 URI 判斷格式`（URI 無副檔名、displayName 為 .epub → 通過）
    - `確認對話框內含新檔名與書名與偏移提示；按取消回 cancelled、未呼叫 replaceBook`
    - `確認後成功：replaceBook 以 (book.id, uri, displayName) 呼叫且 candidate 為 null；回 replaced；顯示「已更新 1 本」；對舊封面與新封面各 evict 一次（相同路徑只一次；新封面為 null 只 evict 舊的）`
    - `不比對書名作者識別碼：新檔書名與原書完全不同仍成功`（假服務回傳的 `updatedBook` 標題不同即可）
    - `取代失敗（各 BookReplaceFailureReason）：回 failed、顯示更新失敗 SnackBar、未 evict`
    - `replaceBook 拋例外：同失敗處理，不拋出`
    - `對話框開啟期間 context 卸載：不拋例外`
    - `更新中（replaceBook 以 Completer 擱置）：對話框仍在、取消與更新按鈕皆停用、顯示處理中文字、返回鍵無法關閉；Completer 完成後對話框才關閉`（審查 I-3）
    - `E-Ink 模式（isEinkMode:true）：對話框無過場動畫`（比照 `book_update_summary_dialog_test.dart` 既有做法）
  - `book_action_sheet_test.dart`：`showUpdateBook 為 true 時顯示 book_action_update_book 且點擊回傳 BookAction.updateBook`、`為 false 時不顯示`。
  - `library_screen_test.dart`：`已下載的書 ⋮ 選單有「用新檔案更新此書」`、`未下載（isDownloaded:false）的書沒有`、`點選後經注入的選檔器選同格式檔並確認 → 假服務收到 replaceBook 且書架重新載入`、`EPUB／PDF／AZW3／TXT／MD／CBZ 皆顯示該項目`（以參數化建書驗證）。

- [ ] **Step 3: 執行確認失敗**
  Run: `flutter test test/screens/support/manual_book_update_flow_test.dart test/screens/book_action_sheet_test.dart test/screens/library_screen_test.dart --no-pub`
  Expected: FAIL／編譯失敗。

- [ ] **Step 4: 實作**
  - `manual_book_update_flow.dart`：依 Interfaces 的流程；封面 evict 用 `<String>{?oldCover, ?newCover}` 去重後逐一 `try { onCoverChanged(path) } catch (_) {}`。
  - `manual_book_update_flow.dart` 與 `library_screen.dart` 取得格式判斷一律 import `library/book_file_format_detection.dart`，不得 import `book_import_service_impl.dart`（F4）。
  - `book_action_sheet.dart`：新增列舉值、`showUpdateBook` 與 `ListTile`（`Icons.file_upload_outlined`）。
  - `library_screen.dart`：建構子加 `final SingleBookFilePicker? pickSingleBookFile`（預設退回 `pickSingleBookFileViaFilePicker`）；`_openBookActionSheet` 的 `switch` 新增 `BookAction.updateBook`：呼叫 `runManualBookUpdate(context, book: book, importService: widget.dependencies.bookImportService, pickFile: ..., isEinkMode: widget.appearance.isEinkMode)`，結果為 `replaced` 且 `mounted` 時 `await _bookListController.loadBooks()`。

- [ ] **Step 5: 執行確認通過**
  Run: 同 Step 3 指令
  Expected: PASS，既有書架與動作選單案例不回歸。

- [ ] **Step 6: 靜態檢查**
  Run: `flutter analyze` → "No issues found!"；`node tool/check_l10n_hardcoded_strings.js`；`node tool/check_integration_keys.js`。

- [ ] **Step 7: Commit**
  ```bash
  git add app/lib/screens app/lib/l10n app/test/screens
  git commit -m "feat(library): 書籍動作選單新增「用新檔案更新此書」（epic-67 Issue 3）"
  ```

---

### Task 4：文件同步、完整測試與真機驗證清單

**Files:**
- Modify: `docs/epics/epic-67-book-update-detection/epic.md`（新增「Issue 3 計畫與實作」段落：D1～D7、已知限制、真機驗證「尚未執行」）
- Modify: `docs/epics/epic-67-book-update-detection/issues.md`（Issue 3 列與 Status 改為實作完成待 PR）
- Modify: 本計畫檔（勾選完成的步驟）

- [ ] **Step 1: 完整測試與靜態檢查**
  Run（`app/`）：`flutter test --no-pub`；`flutter analyze`；`node tool/check_l10n_hardcoded_strings.js`；`node tool/check_integration_keys.js`；然後 `git checkout pubspec.lock windows/flutter`。
  Expected: 全部通過、analyze "No issues found!"。

- [ ] **Step 2: 更新 epic.md 與 issues.md**
  記錄決策、已知限制（見「不在範圍」）與真機驗證項目；真機驗證一律標「尚未執行，由人類另行處理」，不自行勾選。

- [ ] **Step 3: 真機／模擬器手動驗證項目（由人類執行，結果補記於 epic.md）**
  1. 書架 ⋮ → 「用新檔案更新此書」：選同格式的修訂檔 → 確認 → 書名／封面更新、閱讀進度與書籤仍在、書架封面立即換新（驗證 FileImage 快取 evict）。
  2. 同上但選不同格式檔 → 提示格式不符、書不變。
  3. 對已被取代過的 PDF／AZW3 書，使其開書失敗（例如撤銷檔案授權）後在閱讀器按「重新選取檔案」選原檔 → 出現強制重新連結對話框 → 確認後成功重新開書；選取消則維持錯誤畫面。
  4. 閱讀器重新選取檔案選到不同格式 → 仍直接拒絕（不出現強制對話框）。
  5. E-Ink 裝置：確認對話框顯示正常、無多餘過場殘影。

- [ ] **Step 4: Commit**
  ```bash
  git add docs/epics/epic-67-book-update-detection
  git commit -m "docs(epic-67): Issue 3 實作記錄與工單更新"
  ```

---

## 不在範圍

- 書架端的重新連結入口（目前重新連結只存在於閱讀器開書失敗畫面）。
- 手動更新的全域遮罩／進度百分比（D6 僅以對話框內的「處理中…」承載等待）；批次手動更新（一次選多本）。
- 強制重新連結後的閱讀位置／註記降級——屬 Issue 5 的閱讀器降級機制（已合併 PR #383），本 Issue 不重複處理。
- 強制重新連結不更新指紋：之後若使用者仍想讓指紋跟上新檔，需走「用新檔案更新此書」（取代同樣保留舊指紋，這是 Issue 1 已記錄的決定）。
- Calibre 尚未下載（`isDownloaded == false`）的書不提供手動更新（F7）。

## 需要人類確認

1. D1「沿用 `contentMismatch` 當待確認訊號、確認後以 `force: true` 重呼叫」是否符合工單「回傳可由呼叫端繼續確認的結果」？替代方案是新增 `BookRelinkNeedsConfirmation` 密封子類別（較顯式，但所有既有 `switch` 都要補分支）。
2. D4：未下載的 Calibre 書不顯示該選單項目是否接受？
3. 強制重新連結對話框文案（D7）與「更新」確認按鈕文案是否需要調整。

（原第 3 點「手動更新是否不顯示遮罩」已依審查 I-3 改為 D6：由確認對話框承載等待。）

## 自我審查

- **Spec 覆蓋：** 手動入口（Task 3）、僅格式檢查不比身份（Task 3 測試）、取代確認含偏移提示（Task 3 `book_manual_update_notice`）、格式不符明確拒絕（Task 3）；強制重新連結的內容不符回待確認／確認後只改路徑不改指紋／格式不符仍拒絕／其他分支不回歸（Task 1、2）；封面快取 evict（Task 3，F8 說明強制路徑不需要）；四語系（Task 2、3 Step 1）；工單列的畫面測試——選單項目對適用格式存在、強制對話框取消與確認（Task 2、3）。
- **型別一致：** `relinkBook(..., {displayName, force})`、`OpenBookRelink` typedef 的 `{bool force}`、`confirmForce`、`detectImportFileFormat`、`ManualBookUpdateOutcome`、`runManualBookUpdate`、`showUpdateBook`、`showForceRelinkDialog`、`isEinkMode`、`detectImportFileFormat`（經 `book_file_format_detection.dart`）在各 Task 的 Interfaces 與步驟中名稱一致。
- **比例：** 4 個 Task，約 3 個程式 Task 加 1 個文件／驗證 Task；程式區塊僅留簽章、測試名稱與關鍵斷言。
