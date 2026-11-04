# Issue 4：下載佇列「待確認更新」Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 雲端（Google Drive／OneDrive）與 Calibre 背景下載完成後，若新檔是書庫中某本書的更新版，該項目進入新狀態「待確認更新」（佇列繼續處理下一筆、不彈對話框）；使用者之後在下載面板點開項目選取代／並存／跳過；暫存檔在每條離開路徑與下次啟動時都會被清掉。同時補上 Issue 1 合併後雲端／Calibre／WiFi 三處「忽略更新候選」造成的檔案靜默遺失。

**Architecture:** 控制器維持來源無關：`QueuedDownloadJob` 新增 `detectUpdate`／`settleUpdate` 兩個能力，由 `CloudDownloadJob`／`RemoteDownloadJob` 各自持有匯入服務與來源參數實作。`DownloadQueueController` 在下載完成後、既有指紋重複比對之前先呼叫 `detectUpdate`；回傳候選則轉入「待確認更新」並釋放佇列。取代／並存的實際呼叫收斂到新的 `settleBookUpdate`（Issue 2 的 `applyBookUpdateChoices` 改為委派給它，兩個入口共用同一份邏輯）。面板重用 Issue 2 的 `BookUpdateSummaryDialog`（加一個「由呼叫端提供套用函式、取消時不丟棄」的選項）。暫存沿用 Issue 1 服務的 `update_staging/` 目錄，啟動時整個清掃。

**Tech Stack:** Flutter／Dart、`ChangeNotifier`、ARB 在地化（`flutter gen-l10n`）、`flutter_test`。

**Spec:** `docs/epics/epic-67-book-update-detection/spec.md`（「各入口的互動」「背景下載佇列」）；工單見同目錄 `issues.md` Issue 4；Issue 1 介面見 `plans/plan-issue-1.md`；Issue 2 見 `plans/plan-issue-2.md`；ADR 0040。

**分支建議：** `epic-67/issue-4-download-queue-pending-update`（從最新 `main` 切出）。

## 已查證事實（2026-11-04 讀程式所得）

| # | 事實 | 對設計的影響 |
|---|---|---|
| F1 | 控制器現行流程（`download_queue_controller.dart` `_downloadOne`）：`download` → `computeFingerprint` → `hasDuplicate`（`findByContentFingerprint`）→ 若重複則 `onDuplicateConfirm` 對話框 → `promote` → `import` | `detectUpdate` 必須插在 `computeFingerprint` **之前**：EPUB 的指紋是 OPF 識別碼，識別碼相同、內容不同的修訂檔會先被 `hasDuplicate` 命中而進入「已存在」對話框，永遠到不了更新版判定（spec「Problem Statement」第二點） |
| F2 | `BookImportService.detectBookUpdate(uri, displayName:)` 公開版本內部會把更新版新檔複製到服務的 `update_staging/`（`_stageNewFile`），回傳的候選 `stagedPath` 已填入；複製失敗時 `stagedPath == null` | `detectUpdate` 在 `stagedPath == null` 時回傳 `null`（退回既有匯入流程，不遺失下載）；候選成立後原下載暫存檔即可刪除，等同 spec 要求的「立即移到 App 私有專屬暫存目錄」 |
| F3 | 雲端暫存檔名 `<uuid>.<ext>`（`downloadCloudFileToTempFile`），OPDS 同（`downloadToTempFile`）；`CloudFileEntry.name` 有副檔名，`OpdsEntry.title` 沒有 | 偵測／並存的 `displayName`：雲端用 `entry.name`；Calibre 用 `'${entry.title}.${fileExtensionFor(acquisition.format!)}'`，否則並存的書名退路會是 uuid |
| F4 | `CloudDownloadJob.import`／`RemoteDownloadJob.import` 呼叫 `importFiles` 後**丟掉回傳值**（`cloud_download_job.dart:79`、`remote_download_job.dart:88`） | Issue 1 合併後若 `importFiles` 內部判成更新版，該檔既未匯入、暫存也殘留且項目仍顯示「完成」。本 Issue 在兩個 `import` 補上「殘留候選一律當新書匯入」保底 |
| F5 | WiFi：`wifi_transfer_service.dart:135` 遇到 `importedBooks.isEmpty` 回 `failed` 並刪除落地檔；更新版現在會走到這裡（spec 要求 WiFi「維持現狀：指紋相同跳過、其餘當新書」） | Issue 1 造成 WiFi 行為回歸：更新版上傳被判失敗＋服務暫存殘留。Task 6 以「殘留候選當新書匯入」恢復現狀 |
| F6 | `replaceBook`／`importCandidateAsNewBook` 接受 `BookSourceRefs`（雲端 `cloudFileId`、遠端 `remoteServerId`／`remoteBookId`／`remoteDownloadUrl`、`source`）；`importCandidateAsNewBook` 另有 `folderName` | `settleUpdate` 把來源參數帶進去；雲端並存沿用 `folderName` |
| F7 | `update_staging` 目錄名只寫死在 `book_import_service_impl.dart` 的 `_resolveUpdateStagingDirectory`（`<getApplicationDocumentsDirectory()>/update_staging`），服務沒有清掃 API；啟動流程在 `main.dart`（`DownloadQueueController` 於約 387 行建構） | 抽出共用常數與清掃函式，`main.dart` 啟動時呼叫；不動 `BookImportService` 介面（避免所有假實作連動） |
| F8 | Issue 2 已有 `BookUpdateSummaryDialog`（`showBookUpdateSummaryDialog(context, importService:, candidates:, isEinkMode:)`，取消／返回＝全部跳過並丟棄）、`applyBookUpdateChoices`、`handleImportUpdateCandidates`（含 SnackBar 組合邏輯）、`evictCoverImageCache` | 面板重用對話框；SnackBar 組合邏輯抽成可重用函式；封面快取失效以控制器的 `onCoverChanged` 回呼橋接（控制器不依賴 widget／painting） |
| F9 | `QueuedDownloadJob` 的實作者：`CloudDownloadJob`、`RemoteDownloadJob`、`test/downloads/download_queue_controller_test.dart` 的 `FakeQueuedDownloadJob`、`test/screens/widgets/download_queue_panel_test.dart` 的 `_FakeQueuedDownloadJob` | 介面新增方法後這四處都要補（`implements`，不會自動繼承預設實作） |

## 已確認決策（本計畫自行定案，待人類審閱）

- **D1：偵測先於指紋比對。** 見 F1。偵測結果為新書／重複／不支援／偵測失敗／`stagedPath == null` 一律回 `null`，走既有流程（重複仍走既有 `onDuplicateConfirm`，「整檔雜湊相同的重複沿用既有行為」）。
- **D2：新狀態 `DownloadItemStatus.awaitingUpdateConfirmation`**，項目新增 `BookUpdateCandidate? updateCandidate`。進入此狀態即離開 `_runLoop` 的處理（佇列立即處理下一筆）。
- **D3：結算語意。** 控制器 `resolveUpdate(id, choice)`：取代／並存成功 → `done`；失敗 → `failed`（可「重試」＝重新下載，暫存已由結算邏輯丟棄）；**跳過 → 項目從面板移除**（暫存已刪）。同一項目結算中重複呼叫、或狀態不是「待確認更新」時直接回 `failed` 計數、不重複呼叫服務。
- **D4：面板上的對話框「取消」不丟棄。** 使用者只是看看、稍後再決定時，項目與暫存必須保留；只有明確選「跳過」、完成取代／並存、或從面板「移除」才刪暫存。因此對話框新增 `discardOnCancel`（預設 true，Issue 2 行為不變）。
- **D5：「移除」待確認項目＝跳過。** `dismiss(id)` 對待確認項目會先結算為跳過（刪暫存）再移除；`dismiss` 回傳型別由 `void` 改 `Future<void>`（既有呼叫端不受影響）。
- **D6：暫存目錄沿用服務的 `update_staging/`**，不另建下載專屬目錄（spec 要求的「App 私有、免儲存權限、重啟前不被系統回收」均已滿足）。啟動時整個目錄清空。
- **D7：兩個 `import` 的保底與 WiFi 保底一律「當新書匯入」**，不是丟棄：寧可多一本重複書，也不讓使用者的檔案無聲消失（維持 Issue 1 之前的行為）。

## Global Constraints

- 所有註解、文件、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文。
- 畫面字串走 `AppLocalizations`，四份 ARB（`app_zh_TW`／`app_zh`／`app_zh_CN`／`app_en`）同步，並 `flutter gen-l10n` 重產；不得硬編碼中文。
- Flutter 3.41.9：不得使用此版本沒有的 API。
- `DownloadQueueController` 不得 import 任何 `screens/`、`BookImportService`、widget／painting 套件；控制器維持「來源無關、可離線單元測試」。
- 選檔階段既有「已在書庫，仍要下載？」提示（`CloudBrowserScreen`／`RemoteCatalogScreen`）行為不變。
- 重複（整檔相同）沿用既有行為；本 Issue 不改 WiFi 去重邏輯，只恢復「其餘當新書」。
- 待確認清單不跨重啟持久化。
- 提交前：`flutter analyze` 必須 "No issues found!"；`node tool/check_l10n_hardcoded_strings.js`；`node tool/check_integration_keys.js`（皆在 `app/` 下）。
- 測試範圍：每個 Task 只跑觸及的測試檔；完整 `flutter test --no-pub` 只在最後一個 Task 執行一次。指令工作目錄為 `app/`；測試與 analyze 後 `git checkout pubspec.lock windows/flutter` 還原工具雜訊。

## Review Focus

1. **待確認項目不阻塞佇列**（Task 2）：一筆進入待確認後，其後的項目照常下載完成；待確認期間再 `enqueueJobs` 也不受影響。
2. **每條離開路徑都刪暫存**（Task 2、3、4）：跳過、取代完成、並存完成、結算失敗、從面板移除、啟動清掃；唯獨面板對話框「取消」**不**刪（D4）。
3. **結算重入與競態**（Task 2）：同一項目連按兩次、結算途中 `dismiss`、非待確認狀態呼叫 `resolveUpdate`，服務都不得被重複呼叫、不得拋例外。
4. **偵測失敗不丟下載**（Task 2、3）：`detectUpdate` 拋例外或 `stagedPath == null` → 走既有匯入流程，檔案不遺失。
5. **EPUB 識別碼相同的修訂檔不再被「已存在」對話框吞掉**（Task 2）：以假工作驗證偵測先於 `computeFingerprint`／`onDuplicateConfirm`，且真正重複的檔案仍走原對話框。
6. **WiFi 與兩個 `import` 的保底**（Task 3、6）：殘留更新候選當新書匯入，結果計入已匯入、服務暫存被清掉。
7. **啟動清掃安全**（Task 4）：目錄不存在、為空、含子目錄、無權限刪除時都不拋例外、不阻擋啟動。
8. **保底並存後不留孤立檔**（Task 3、6；審查 I-2）：`importCandidateAsNewBook` 會把服務暫存檔再複製成 `imported_books/<新 id>.<ext>`，原本的落地檔（WiFi 的 `landedPath`、雲端／Calibre 的 `permanentPath`）因此不再被任何書引用，必須刪除。
9. **面板對話框的非預期關閉不得丟棄或崩潰**（Task 5；審查 I-1）：`showDialog` 回傳 null 且 `discardOnCancel == false` 時，不得呼叫套用函式，也不得對 null 的 `importService` 解參考。

---

### Task 1：共用結算邏輯 `settleBookUpdate`（並讓 Issue 2 的套用邏輯委派給它）

**Files:**
- Create: `app/lib/library/book_update_settle.dart`
- Create: `app/test/library/book_update_settle_test.dart`
- Modify: `app/lib/screens/support/book_update_resolver.dart`

**Interfaces（Produces）：**

```dart
// 自 book_update_resolver.dart 搬入（resolver 以 `export` 重新匯出，Issue 2 既有 import 與測試不必改）
sealed class BookUpdateChoice { const BookUpdateChoice(); }
final class ReplaceChoice extends BookUpdateChoice { final String bookId; const ReplaceChoice(this.bookId); /* 保留既有 ==/hashCode */ }
final class CoexistChoice extends BookUpdateChoice { const CoexistChoice(); }
final class SkipChoice extends BookUpdateChoice { const SkipChoice(); }

enum BookUpdateSettleOutcome { replaced, coexisted, skipped, failed }

class BookUpdateSettleResult {
  final BookUpdateSettleOutcome outcome;
  /// 取代成功時，舊書與新書封面路徑（非 null、去重）；供 UI 層 evict 圖片快取。
  final Set<String> changedCoverPaths;
  const BookUpdateSettleResult(this.outcome, {this.changedCoverPaths = const {}});
}

/// 對單一更新候選套用決定；永不拋例外。語意同 Issue 2 的 applyBookUpdateChoices 單筆：
/// Skip → discardUpdateCandidate；Replace → replaceBook(..., candidate:, sourceRefs:)，失敗或拋例外補 discard；
/// Coexist → importCandidateAsNewBook(candidate, folderName:, sourceRefs:)，null 或拋例外 → failed（服務已自行丟棄）。
Future<BookUpdateSettleResult> settleBookUpdate(
  BookImportService service,
  BookUpdateCandidate candidate,
  BookUpdateChoice choice, {
  BookSourceRefs? sourceRefs,
  String? folderName,
});
```

`applyBookUpdateChoices` 保持簽章與回傳不變，內部逐筆委派 `settleBookUpdate`、依 `outcome` 累計計數、對 `changedCoverPaths` 呼叫 `onCoverChanged`。

- [x] **Step 1：寫失敗測試**（`book_update_settle_test.dart`，用 `FakeBookImportService`）：
  - `跳過`：outcome `skipped`，`discardedCandidates` 含該候選。
  - `取代成功`：`replaceCalls` 的 bookId 正確、`replaceBook` 收到的 `sourceRefs`／`candidate` 與傳入相同（需把 fake 的 `replaceBook` 記錄 `sourceRefs`：擴充 `replaceCalls` 的紀錄型別或另加 `lastReplaceSourceRefs`）；outcome `replaced`；`changedCoverPaths` 為舊書與新書封面（相同只留一個，null 略過）。
  - `取代失敗`／`replaceThrows`：outcome `failed`、候選被丟棄、`changedCoverPaths` 為空。
  - `並存成功`：`importCandidateCalls` 含該候選，且 `folderName`、`sourceRefs` 被轉傳（fake 記錄）；`並存失敗`（回 null／拋例外）→ `failed`。
- [x] **Step 2：確認失敗** `flutter test --no-pub test/library/book_update_settle_test.dart`
- [x] **Step 3：實作** 新檔；修改 resolver 為 re-export＋委派。
- [x] **Step 4：確認通過**，並重跑 Issue 2 的 `test/screens/support/book_update_resolver_test.dart`、`test/screens/widgets/book_update_summary_dialog_test.dart`（護欄：行為不變）。
- [x] **Step 5：`flutter analyze`**；提交 `refactor(library): 抽出更新版結算邏輯 settleBookUpdate（epic-67 Issue 4 Task 1）`。

---

### Task 2：`QueuedDownloadJob` 介面與控制器「待確認更新」狀態機

**Files:**
- Modify: `app/lib/downloads/download_queue_controller.dart`
- Modify: `app/test/downloads/download_queue_controller_test.dart`（`FakeQueuedDownloadJob` 補新方法並新增案例）
- Modify: `app/test/screens/widgets/download_queue_panel_test.dart`（僅 `_FakeQueuedDownloadJob` 補新方法，讓它編譯）

**Interfaces：**
- Consumes：Task 1 的 `BookUpdateChoice`／`BookUpdateSettleResult`／`BookUpdateSettleOutcome`；`BookUpdateCandidate`（`library/book_update_models.dart`）。
- Produces：

```dart
enum DownloadItemStatus { /* 既有七個 */, awaitingUpdateConfirmation }

class DownloadQueueItem {
  /* 既有欄位 */
  BookUpdateCandidate? updateCandidate; // 僅 awaitingUpdateConfirmation 時非 null
}

abstract class QueuedDownloadJob {
  /* 既有成員 */
  /// 對剛下載完成的暫存檔偵測更新版。回傳 null＝不是更新版（新書／重複／不支援／偵測失敗／暫存複製失敗）。
  /// 回傳非 null 時，候選的 stagedPath 必為非 null，且呼叫端可安全刪除原暫存檔。
  Future<BookUpdateCandidate?> detectUpdate(String tempPath);

  /// 依使用者選擇結算候選（含來源參數）；永不拋例外。
  Future<BookUpdateSettleResult> settleUpdate(BookUpdateCandidate candidate, BookUpdateChoice choice);
}

class DownloadQueueController extends ChangeNotifier {
  DownloadQueueController({
    required this.onDuplicateConfirm,
    this.onCoverChanged,           // void Function(String coverPath)?，取代成功時對每個 changedCoverPaths 呼叫
  });

  /// 結算「待確認更新」項目；非該狀態、或同一項目正在結算中 → 回傳 failed 且不呼叫 job。
  /// 內部以 `final Set<String> _resolvingIds` 管理結算中的項目：進入前若已在集合內直接回
  /// `BookUpdateSettleResult(BookUpdateSettleOutcome.failed)`；通過檢查後立即加入，
  /// 以 try/finally 保證結束時移除（審查 I-4）。
  Future<BookUpdateSettleResult> resolveUpdate(String id, BookUpdateChoice choice);

  /// 既有 dismiss 改為 Future<void>；待確認項目先結算為 SkipChoice（刪暫存）再移除。
  /// 項目正在結算中（在 `_resolvingIds` 內）時不動作直接返回，避免結算與移除並行（審查 I-4）。
  Future<void> dismiss(String id);
}
```

**`_downloadOne` 新流程：** `download` 成功後 → 狀態設 `checkingDuplicate` → `detectUpdate(tempPath)`（拋例外視為 null）→ 非 null：刪原暫存檔、`item.updateCandidate = candidate`、狀態 `awaitingUpdateConfirmation`、`notifyListeners()`、`return`（迴圈繼續下一筆）；null：維持既有 `computeFingerprint` → `hasDuplicate` → … 流程完全不變。`resolveUpdate` 成功後對每個 `changedCoverPaths` 以 `onCoverChanged?.call(path)` 通知（回呼為 null 時安全略過，審查 M-2）；結果為 replaced／coexisted → `done`，`progress = 1.0`、清 `updateCandidate`；`skipped` → 移除項目；`failed` → `failed`、清 `updateCandidate`。`retry(id)` 對 `awaitingUpdateConfirmation` 項目不動作。

- [x] **Step 1：補假工作與寫失敗測試**（`FakeQueuedDownloadJob` 加 `detectResult`（`BookUpdateCandidate?`）、`detectThrows`、`settleResult`、`settleCalls`（候選＋選擇）、`detectCalls` 與 `computeFingerprintCalls` 的相對順序紀錄）：
  - `更新版進入待確認且佇列繼續`（Review Focus 1）：兩筆工作，第一筆 `detectResult` 非 null → 第一筆狀態 `awaitingUpdateConfirmation`、`updateCandidate` 非 null、其 `import`／`promote` 呼叫數為 0；第二筆照常 `done`。
  - `待確認期間再 enqueue 不受影響`：待確認後 `enqueueJobs` 新工作 → 正常完成。
  - `原暫存檔被刪`：以真實暫存檔路徑驗證 `detectResult` 非 null 後原檔不存在。
  - `偵測先於指紋與重複對話框`（Review Focus 5）：`detectResult` 非 null 且 `hasDuplicateResult: true` → `onDuplicateConfirm` 從未被呼叫、`computeFingerprintCalls == 0`；`detectResult` 為 null 且 `hasDuplicateResult: true` → 仍呼叫 `onDuplicateConfirm`（既有行為迴歸）。
  - `偵測拋例外走既有流程`（Review Focus 4）：`detectThrows` → 項目最終 `done`、`importCalls == 1`。
  - `resolveUpdate 取代／並存成功`：狀態 `done`、`settleCalls` 帶正確選擇；`settleResult` 的 `changedCoverPaths` 每一個都傳給 `onCoverChanged`。
  - `resolveUpdate 跳過`：項目從 `items` 消失、`settleCalls` 含 `SkipChoice`。
  - `resolveUpdate 失敗`：項目 `failed`、`updateCandidate == null`；其後 `retry` 重新下載並可成功。
  - `重入與錯誤狀態`（Review Focus 3）：對 `done`／`downloading` 項目呼叫 `resolveUpdate` → 回 `failed`、`settleCalls` 為空；對待確認項目同時呼叫兩次（第一次的 `settleUpdate` 以 Completer 擋住）→ `settleCalls` 只有一次、第二次回 `failed`；結算途中呼叫 `dismiss` → 項目仍在、`settleCalls` 不增加；結算完成後 `_resolvingIds` 已清空（可再對其他項目結算）。
  - `未提供 onCoverChanged`（審查 M-2）：建構子不傳回呼叫時，取代成功不拋例外。
  - `dismiss 待確認項目`：`settleCalls` 含 `SkipChoice`、項目消失；`dismiss` 一般項目行為不變（既有測試保持通過）。
  - `retry 對待確認項目無動作`：`downloadCalls` 不增加。
- [x] **Step 2：確認失敗** `flutter test --no-pub test/downloads/download_queue_controller_test.dart`
- [x] **Step 3：實作** 介面、狀態、控制器流程；`download_queue_panel_test.dart` 的假工作補預設實作（`detectUpdate` 回 null、`settleUpdate` 回 `skipped`）。
- [x] **Step 4：確認通過**，並重跑 `test/screens/widgets/download_queue_panel_test.dart`（此時面板尚未改，須仍通過；面板內對新狀態的 `switch` 在 Task 5 補，但為了編譯通過，本 Task 先讓三個 `switch` 對新狀態回傳暫時值——狀態圖示 `Icons.update`、標籤先用既有 `downloadQueueStatusPending`，Task 5 改正式字串）。
- [x] **Step 5：`flutter analyze`**；提交 `feat(downloads): 下載佇列新增「待確認更新」狀態與結算（epic-67 Issue 4 Task 2）`。

---

### Task 3：`CloudDownloadJob`／`RemoteDownloadJob` 實作偵測、結算與殘留候選保底

**Files:**
- Modify: `app/lib/cloud_import/cloud_download_job.dart`、`app/lib/remote/remote_download_job.dart`
- Modify: `app/test/cloud_import/cloud_download_job_test.dart`
- Create: `app/test/remote/remote_download_job_test.dart`

**Interfaces：**
- Consumes：Task 1 `settleBookUpdate`；Task 2 的介面。
- 行為（兩個 job 皆然）：
  - `detectUpdate(tempPath)`：呼叫 `importService.detectBookUpdate(tempPath, displayName: …)`（displayName 見 F3）；結果為 `DetectedUpdate` 且 `candidate.stagedPath != null` → 回傳候選；其餘或拋例外 → `null`。若結果是 `DetectedUpdate` 但 `stagedPath == null` → 回 `null`。
  - `settleUpdate(candidate, choice)`：`settleBookUpdate(importService, candidate, choice, sourceRefs: …, folderName: …)`。雲端：`BookSourceRefs(source: source, cloudFileId: entry.id)`、`folderName: folderName`；Calibre：`BookSourceRefs(source: BookSource.calibreOpds, remoteServerId: server.id, remoteBookId: entry.remoteBookId, remoteDownloadUrl: acquisition.href)`。
  - `import(permanentPath)`（保底，F4／D7）：保留現行 `importFiles` 參數；取得結果後，對 `result.updateCandidates` 每一筆呼叫 `importCandidateAsNewBook`（雲端帶 `folderName` 與同樣的 `sourceRefs`；Calibre 帶 `sourceRefs`）。只要 `result.updateCandidates` 非空（單檔批次，代表該檔沒有被匯入為書），不論並存成功與否，都要刪除 `permanentPath`：並存的新書使用的是服務從暫存檔重新複製的 `imported_books/<新 id>.<ext>`，`permanentPath` 已無人引用（審查 I-2）。刪除失敗吞掉。

- [x] **Step 1：寫失敗測試**（以 `FakeBookImportService`；`detectResult`、`importFilesResult`、`importCandidateResult`、`replaceResultsByBookId` 控制）：
  - `detectUpdate`：`DetectedUpdate` 且有 `stagedPath` → 回候選，且 `detectBookUpdate` 收到的 `displayName`：雲端為 `entry.name`、Calibre 為 `'<title>.epub'`；`DetectedNewBook`／`DetectedDuplicate`／`DetectedUnsupported` → `null`；`DetectedUpdate` 但 `stagedPath == null` → `null`；服務拋例外 → `null`。
  - `settleUpdate 取代`（雲端）：`replaceBook` 收到 `sourceRefs.cloudFileId == entry.id` 且 `source == job.source`；（Calibre）收到 `remoteServerId`／`remoteBookId`／`remoteDownloadUrl` 與 `source == calibreOpds`。
  - `settleUpdate 並存`：`importCandidateAsNewBook` 收到同樣 `sourceRefs`；雲端另收到 `folderName`。
  - `settleUpdate 跳過`：候選被丟棄。
  - `import 保底`（Review Focus 6、8）：以真實暫存檔作為 `permanentPath`，`importFilesResult` 含 1 筆殘留候選 → `importCandidateCalls` 含該候選且帶來源參數，**`permanentPath` 檔案已被刪除**（並存失敗時同樣被刪）；`importFilesResult` 無候選 → `importCandidateCalls` 為空、`permanentPath` **不被刪**、行為與先前完全相同（既有測試保持通過）。
- [x] **Step 2：確認失敗 → Step 3：實作 → Step 4：確認通過**，並重跑 Task 2 的測試檔、`test/screens/cloud_browser_screen_test.dart`、`test/screens/remote_catalog_screen_test.dart`（選檔階段重複提示迴歸）。
- [x] **Step 5：`flutter analyze`**；提交 `feat(downloads): 雲端與 Calibre 下載工作支援更新版偵測與結算（epic-67 Issue 4 Task 3）`。

---

### Task 4：啟動清掃與 `main.dart` 接線

**Files:**
- Create: `app/lib/library/update_staging.dart`
- Create: `app/test/library/update_staging_test.dart`
- Modify: `app/lib/library/book_import_service_impl.dart`（`_resolveUpdateStagingDirectory` 改用共用常數）
- Modify: `app/lib/main.dart`

**Interfaces（Produces）：**

```dart
/// 更新暫存目錄名稱（位於應用程式文件目錄下）。
const String kUpdateStagingFolderName = 'update_staging';

/// 清空 [documentsDirectory]/update_staging 底下所有內容（檔案與子目錄），保留目錄本身或不建立皆可。
/// 目錄不存在視為成功；任何刪除失敗皆吞掉，永不拋例外、不阻擋啟動。
Future<void> sweepUpdateStaging(Directory documentsDirectory);
```

`main.dart`：在建立 `BookImportServiceImpl`／`DownloadQueueController` 之前（任何匯入發生之前）`await sweepUpdateStaging(await getApplicationDocumentsDirectory())`（以 try/catch 包住）；`DownloadQueueController` 建構時傳 `onCoverChanged: evictCoverImageCache`（自 `screens/support/book_update_resolver.dart` 匯入）。

- [x] **Step 1：寫失敗測試**（`update_staging_test.dart`，真實暫存目錄）：
  - `清掃`：目錄含 3 個檔案與 1 個含檔案的子目錄 → 呼叫後目錄內為空。
  - `目錄不存在`：不拋例外。
  - `空目錄`：不拋例外。
  - `刪除失敗不拋例外`（Review Focus 7）：以 Windows 不可刪的情境難以穩定重現時，改測「路徑存在但是一般檔案而非目錄」→ 不拋例外、該檔案不被刪（只處理目錄）。
  - `常數`：`kUpdateStagingFolderName == 'update_staging'`，且 `BookImportServiceImpl` 在未指定 `updateStagingDirectory` 時使用同一名稱（以 `path_provider` 假實作或檢查常數引用，擇一能穩定驗證者）。
- [x] **Step 2：確認失敗 → Step 3：實作與接線 → Step 4：確認通過**，並重跑 `test/library/book_import_service_update_staging_test.dart`、`test/elinkbook_app_wiring_test.dart`。
- [x] **Step 5：`flutter analyze`**；提交 `feat(library): 啟動時清掃更新暫存目錄（epic-67 Issue 4 Task 4）`。

---

### Task 5：下載面板處理待確認更新（對話框擴充、字串、SnackBar 重用）

**Files:**
- Modify: `app/lib/screens/widgets/book_update_summary_dialog.dart`
- Modify: `app/lib/screens/support/book_import_picker_helper.dart`（抽出 `showBookUpdateResultSnackBar`）
- Modify: `app/lib/screens/widgets/download_queue_panel.dart`
- Modify: `app/lib/screens/sources_home_screen.dart`（建構 `DownloadQueuePanel` 時傳 `isEinkMode`）
- Modify: `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`，並 `flutter gen-l10n`
- Modify: `app/test/screens/widgets/book_update_summary_dialog_test.dart`、`app/test/screens/support/book_import_picker_helper_test.dart`、`app/test/screens/widgets/download_queue_panel_test.dart`

**Interfaces：**
- `showBookUpdateSummaryDialog` 變更（向下相容）：`importService` 改為可為 null（`BookImportService?`）；新增 `BookUpdateDecisionApplier? applier`（`typedef BookUpdateDecisionApplier = Future<BookUpdateApplyResult> Function(List<BookUpdateDecision>)`）與 `bool discardOnCancel = true`；斷言 `importService != null || applier != null`。有 `applier` 時套用走 `applier`；`discardOnCancel == false` 時取消／返回**不呼叫**任何套用或丟棄，直接關閉並回傳 `BookUpdateApplyResult()`（全 0）。其餘（Issue 2 路徑）行為與測試不變。

**`showDialog` 回傳 null 的保底（審查 I-1）：** `result != null` 直接回傳；否則先判 `!discardOnCancel` → 回傳 `const BookUpdateApplyResult()`（不套用、不丟棄，也不碰可能為 null 的 `importService`）；再判 `applier != null` → `applier(全 SkipChoice 決定)`；最後才是 `applyBookUpdateChoices(importService!, 全 SkipChoice 決定)`（Issue 2 既有保底）。
- `showBookUpdateResultSnackBar(BuildContext context, BookUpdateApplyResult result)`：由 `handleImportUpdateCandidates` 內現有 SnackBar 組合邏輯抽出（規則不變：三個成功鍵＋失敗鍵＋`bookUpdateResultWithFailedMessage`，全 0 或僅跳過不顯示），`handleImportUpdateCandidates` 改為呼叫它。
- `DownloadQueuePanel({required controller, bool isEinkMode = false})`。
- 新增 ARB 鍵（四份同步）：`downloadQueueStatusAwaitingUpdate`＝「待確認更新」、`downloadQueueUpdateReviewButton`＝「處理」（含 `@` 描述）。

**面板行為：** `inProgress` 判定維持只涵蓋 `pending`／`downloading`／`checkingDuplicate`，新狀態走非進行中分支（顯示圖示與標籤，不畫進度條；審查 M-1）。`_trailingAction` 簽章改為 `_trailingAction(BuildContext context, AppLocalizations l10n)`（點「處理」需 context 開對話框），待確認狀態以 `Row(mainAxisSize: MainAxisSize.min, children: [處理, 移除])` 建構，避免擠壓左側名稱（審查 I-3）。待確認項目的狀態圖示 `Icons.update`、標籤 `downloadQueueStatusAwaitingUpdate`（取代 Task 2 的暫時值）；尾端動作為「處理」按鈕（Key `sources_download_queue_update_review_<id>`）與既有「移除」按鈕（Key `sources_download_queue_dismiss_<id>`，呼叫 `controller.dismiss`）。點「處理」→ `showBookUpdateSummaryDialog(candidates: [item.updateCandidate!], applier: …, discardOnCancel: false, isEinkMode: isEinkMode)`；`applier` 呼叫 `controller.resolveUpdate(item.id, decision.choice)` 並把 outcome 對映成單筆 `BookUpdateApplyResult`；對話框關閉後（`context.mounted`）呼叫 `showBookUpdateResultSnackBar`。項目已不是待確認狀態時（例如對話框開啟期間被移除）`resolveUpdate` 回 `failed`，SnackBar 顯示失敗訊息。

- [x] **Step 1：新增 ARB 字串**至四份檔案並 `flutter gen-l10n`；跑 `flutter test --no-pub test/l10n/arb_consistency_test.dart test/l10n/app_localizations_generated_test.dart`。
- [x] **Step 2：寫失敗測試**
  - 對話框（`book_update_summary_dialog_test.dart`）：`有 applier`——套用時 `applier` 收到正確的決定清單、`importService` 為 null 也可運作；`discardOnCancel: false`——按取消／系統返回後對話框關閉、`discardedCandidates` 為空、`applier` 未被呼叫、回傳全 0；預設 `discardOnCancel`——既有「取消丟棄」測試全數保持通過。
  - SnackBar 抽出（`book_import_picker_helper_test.dart`）：既有 `handleImportUpdateCandidates` 全部案例保持通過；另加直接呼叫 `showBookUpdateResultSnackBar` 的案例（取代／並存／混合／部分失敗／全為跳過不顯示）。
  - 對話框（補）：`discardOnCancel: false` 且僅傳 `applier`（`importService` 為 null）時，模擬 `showDialog` 回 null（以 `Navigator.pop(context)` 直接關閉）→ 不拋例外、`applier` 未被呼叫、回傳全 0（審查 I-1）。
  - 面板（`download_queue_panel_test.dart`，用真實 `DownloadQueueController`＋可控假工作）：
    - `待確認項目顯示`：出現「待確認更新」標籤、`update_review` 與 `dismiss` 按鈕；`sources_download_queue_progress_<id>` 不存在；窄螢幕（寬 320）長名稱下無 overflow 例外。
    - `點處理開啟對話框`：出現 `book_update_apply`；按套用（預設取代）→ 假工作 `settleCalls` 含 `ReplaceChoice`、項目變「完成」、出現「已更新 1 本」SnackBar。
    - `選跳過`：項目從清單消失、`settleCalls` 含 `SkipChoice`。
    - `對話框取消不丟棄`（D4、Review Focus 2）：按取消後項目仍在、`settleCalls` 為空、可再次點「處理」。
    - `移除`：點 dismiss → 假工作收到 `SkipChoice`、項目消失。
    - `取代失敗`：`settleResult` 為 failed → 項目變「失敗」並出現失敗 SnackBar。
- [x] **Step 3：確認失敗 → Step 4：實作 → Step 5：確認通過**，並重跑 Issue 2 的 `test/screens/sources_home_screen_test.dart` 與 Task 2 的控制器測試。
- [ ] **Step 6：`flutter analyze`**；`node tool/check_l10n_hardcoded_strings.js`；`node tool/check_integration_keys.js`；提交 `feat(downloads): 下載面板處理待確認更新（epic-67 Issue 4 Task 5）`。

---

### Task 6：WiFi 傳輸維持「其餘當新書」

**Files:**
- Modify: `app/lib/wifi_transfer/wifi_transfer_service.dart`（約 135 行 `importFiles` 之後）
- Modify: `app/test/wifi_transfer/wifi_transfer_service_test.dart`

**行為：** `importFiles` 回傳後，對 `result.updateCandidates` 每一筆呼叫 `importCandidateAsNewBook`（D7）；成功者視同已匯入。判定 `imported` 改為 `result.importedBooks.isNotEmpty || 至少一筆並存成功`；其餘維持（`isEmpty` → 失敗並刪落地檔）。**只要 `result.updateCandidates` 非空，無論並存成功與否都要 `safeDelete(landedPath)`**：並存的新書使用服務重新複製出的私有檔，WiFi 落地檔已無人引用（審查 I-2）。指紋相同的去重邏輯不動。

- [ ] **Step 1：寫失敗測試**（假匯入服務回傳含 1 筆更新候選、`importedBooks` 為空）：
  - `更新版上傳當新書匯入`：`importCandidateAsNewBook` 被呼叫、`UploadResult.outcome == imported`、**落地檔已被刪除**（`deleteFile` 假實作收到 `landedPath`）。
  - `並存失敗`：`importCandidateResult` 為 null → outcome `failed`、落地檔被刪。
  - `一般新書匯入`：`updateCandidates` 為空時落地檔**不被刪**（書本身引用它）。
  - `一般新書與重複`：既有案例全數通過。
- [ ] **Step 2：確認失敗 → Step 3：實作 → Step 4：確認通過**。
- [ ] **Step 5：`flutter analyze`**；提交 `fix(wifi): 更新版上傳維持當新書匯入，不被 Issue 1 的偵測吞掉（epic-67 Issue 4 Task 6）`。

---

### Task 7：完整驗證與文件同步

**Files:**
- Modify: `docs/epics/epic-67-book-update-detection/epic.md`、`issues.md`

- [ ] **Step 1：** `flutter analyze` 乾淨；兩支 node 檢查腳本通過。
- [ ] **Step 2：** 完整 `flutter test --no-pub` 全綠（本計畫唯一一次全套）；之後 `git checkout pubspec.lock windows/flutter`。
- [ ] **Step 3：真機／模擬器手動驗證**（由人類執行並把結果補記於 `epic.md`；執行者不得自行勾選）：
  1. 書庫預置一本 EPUB，從 Google Drive（或 OneDrive）下載同識別碼、內容不同的新版 → 項目顯示「待確認更新」，佇列中其他項目繼續下載；點「處理」選取代 → 書名／封面更新、閱讀進度與書籤仍在、`cloudFileId` 已補寫。
  2. 同上改用 Calibre 書庫，選並存 → 新書帶 `remoteServerId`／`remoteBookId`。
  3. 待確認狀態下 force-stop 重啟 App → 面板項目消失，`<documents>/update_staging/` 為空。
  4. 整檔相同的檔案仍出現原「已存在，仍要匯入？」對話框。
  5. WiFi 傳輸上傳一份更新版 EPUB → 成為新書（不再顯示失敗）。
- [ ] **Step 4：文件同步：** `epic.md` 新增「Issue 4 計畫與實作」段，記錄 D1～D7、F4／F5（Issue 1 副作用與保底）、手動驗證結果（未執行則明寫「尚未執行」）；`issues.md` Issue 4 補計畫連結與狀態。`docs/epics.md` 備註與 PR 欄**合併後**才改。
- [ ] **Step 5：提交** `docs(epic-67): Issue 4 實作記錄`。

---

## 不在本 Issue 範圍（避免誤做）

- 手動入口與強制重新連結（Issue 3）。
- 選檔階段「已在書庫，仍要下載？」提示的任何改動（維持原樣，只做迴歸）。
- 待確認清單的跨重啟持久化。
- WiFi 的更新版真正支援（取代／並存清單）；本 Issue 僅恢復「其餘當新書」。
- 整檔相同重複的處理流程調整。
- 服務端 `BookImportService` 介面變更。

## 需要人類確認（審閱本計畫時請回覆）

（計畫審查對以下四題的意見均為「維持原案」，人類已於 2026-11-04 確認「照審查建議」：1 直接移除、2 取消不丟棄、3 在本 Issue 修 WiFi、4 沿用 `update_staging/`。）

1. **D3「跳過＝項目從面板消失」：** 使用者按跳過後，項目直接移除而不留「已略過」紀錄，是否接受？（替代：新增一個終態「已跳過更新」並保留到手動移除。）
2. **D4：** 面板對話框「取消」不丟棄、項目留在原處，是否符合預期？
3. **Task 6（WiFi）：** spec 把 WiFi 列為「不納入」，但 Issue 1 合併後 WiFi 更新版上傳會被判失敗並殘留暫存，這是回歸。是否同意在本 Issue 以最小修補恢復現狀，或另開工單？
4. **D6：** 沿用服務的 `update_staging/` 而非另建下載專屬目錄，是否同意？
