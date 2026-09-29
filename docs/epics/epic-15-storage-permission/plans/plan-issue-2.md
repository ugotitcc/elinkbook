# Epic 15 Issue 2：在閱讀器錯誤畫面重新選取檔案，書籍原地重新連結並繼續閱讀 — 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 存取權限失效或找不到檔案時，使用者在閱讀器錯誤畫面按「重新選取檔案」、選到同一本書後，書籍記錄原地換成新路徑（`id`、閱讀位置、劃線、書籤全保留），並在同一個畫面重新開書。

**Architecture:**
- `BookImportService` 新增 `relinkBook(bookId, newUri, {displayName})`，回傳 sealed class `BookRelinkResult`。實作採「先驗證，後持久化」：格式、重複、內容指紋全部通過後，才持久化授權或落地複本，最後 `updateBook` 原地更新。
- 格式判斷、持久化授權／落地複本兩段邏輯，從 `_importSingleFile` 抽成私有 helper，匯入與重新連結共用同一份實作。
- `ReaderScreen` 錯誤視圖在探測結果為 `permissionRevoked`／`fileNotFound`、且有匯入服務時顯示外框按鈕；選檔器以可注入的 `SingleBookFilePicker` 提供。成功後在同一次 `setState` 內換路徑、回到載入中、重啟 30 秒逾時；閱讀視圖因錯誤視圖已把它移出樹，會以新路徑重新建立（維持原本的 GlobalKey）。

**Tech Stack:** Flutter／Dart 3（sealed class、record、pattern matching）、`file_picker`、`sqflite_common_ffi`（服務層測試）、`flutter_test`、`flutter gen-l10n`（ARB）。

**Spec:** [`../spec.md`](../spec.md)（「閱讀器錯誤視圖」「Re-link 服務」「介面文案與在地化」三段）、[`../issues.md`](../issues.md) Issue 2

## Global Constraints

- 型別名稱與簽章逐字照 spec：

  ```dart
  sealed class BookRelinkResult { const BookRelinkResult(); }
  final class BookRelinkSuccess extends BookRelinkResult { final Book updatedBook; const BookRelinkSuccess(this.updatedBook); }
  enum BookRelinkFailureReason { formatMismatch, contentMismatch, alreadyInLibrary, failed }
  final class BookRelinkFailure extends BookRelinkResult { final BookRelinkFailureReason reason; const BookRelinkFailure(this.reason); }
  Future<BookRelinkResult> relinkBook(String bookId, String newUri, {String? displayName});

  typedef SingleBookFilePicker =
      Future<({String uri, String? displayName})?> Function(List<String> allowedExtensions);
  ```

- Re-link 處理順序固定為 spec 的 7 步（讀最新記錄 → 格式 → 重複 → 指紋 → 比對 → 持久化／落地 → `updateBook`）。前 5 步任何一步失敗，都**不呼叫** `takePersistableUriPermission`、**不呼叫** `copyContentUriToFile`、**不寫**資料庫。
- EPUB 指紋必須先對新 URI 呼叫 `extractMetadata` 取 OPF identifier，再傳給 `computeBookContentFingerprint(..., epubIdentifier:)`；取不到才退回 SHA-256。
- 重複檢查只擋「**其他**書籍（id 不同）的 `filePath` 等於新 URI」；等於原書自己的 `filePath` 不擋。
- 格式判斷、持久化授權、落地複本三段規則與第一次匯入共用同一份實作，不可複製貼上另寫一份。
- `updateBook` 只改 `filePath`，以及原書沒有指紋時補寫的 `contentFingerprint`；其餘欄位（`id`、書名、作者、封面、分類、閱讀位置、同步欄位）全部沿用 `findBookById` 讀到的最新記錄。
- `FakeBookImportService`（`test/support/`）與 `_ThrowingImportService`（`test/wifi_transfer/wifi_transfer_service_test.dart`）必須同步實作 `relinkBook`，否則有二十多個測試檔會編譯失敗。
- 閱讀視圖**維持原本的 GlobalKey**，不加 `ValueKey`、不外包 `KeyedSubtree`。
- 按鈕顯示條件：`_probeResult` 是 `permissionRevoked` 或 `fileNotFound`，**而且** `widget.bookImportService != null`。
- 按鈕 Key：`Key('reader_storage_relink_button')`；處理中的進度指示器 Key：`Key('reader_storage_relink_progress')`。按鈕用 `OutlinedButton`（E-Ink 高對比模式下要有明確外框）。
- 選擇器取消時：不顯示任何 SnackBar、不呼叫 `relinkBook`、錯誤視圖維持原樣、按鈕恢復可用。
- 顯示 SnackBar 或重新開書前，都要先確認 `mounted`；按鈕狀態在 `finally` 區段恢復。
- 在地化：新增 `readerStorageRelinkButton`、`readerStorageRelinkFormatMismatch`、`readerStorageRelinkContentMismatch`、`readerStorageRelinkAlreadyInLibrary`、`readerStorageRelinkFailed` 五個 key。四份 ARB 都要補：
  - `app_zh_TW.arb`：範本，含 `@key` 說明。
  - `app_zh.arb`：中文退路，內容同正體中文。
  - `app_zh_CN.arb`、`app_en.arb`。

  改完執行 `flutter gen-l10n`，生成的 `app_localizations*.dart` 已納入版控，要一起提交。
- 移除 Issue 0 留下的 `// ignore: prefer_final_fields` 與上一行說明註解（`reader_screen.dart` 約第 373–374 行），`flutter analyze` 仍須乾淨。
- 程式碼註解使用正體中文，並標註 `epic-15-storage-permission Issue 2`。
- 每個 Task 只跑觸及的測試檔；最後一個 Task 跑一次完整 `flutter test`。`flutter analyze` 必須是 `No issues found!`。
- 所有指令都在 `app/` 目錄下執行（除非另外註明）。

## Review Focus

spec 沒有明講、但使用者最可能碰到的五種情況，依發生機率排序：

1. **快速連點「重新選取檔案」**：大檔案算 SHA-256 要數秒，使用者以為沒反應會再點。第二次點擊不可再開選擇器、也不可平行發動第二次 Re-link。由 Task 2 的「連點兩次只開一次選擇器」測試釘住。
2. **重新連結成功，但新檔案一樣打不開**（例如選到同一個仍然沒有授權的 URI，或檔案本身毀損）：閱讀器必須再走一次「探測 → 錯誤視圖 → 按鈕」，不可卡在上一輪的 `_isProbingAccess`／`_probeResult` 殘留狀態。由 Task 2 的「重新開書後再次失敗會重新探測」測試釘住。
3. **Re-link 處理中離開閱讀器**：`relinkBook` 回來時 State 已 dispose，不可 `setState` 或顯示 SnackBar 拋例外。由 Task 2 的「處理中離開不拋例外」測試釘住。
4. **選擇器或服務拋出例外**（`FilePicker` 在部分 SAF Provider 會丟 `PlatformException`；服務內部也可能有未預期錯誤）：按鈕不可永遠停在停用狀態。預設選擇器把例外當成取消；`ReaderScreen` 把 `relinkBook` 的例外當成 `failed` 顯示 SnackBar。由 Task 2 的「relinkBook 拋出例外」測試釘住。
5. **對 TXT／MD／CBZ 書籍呼叫 `relinkBook`**：這些書的 `filePath` 是匯入時合成／重建的落地檔，若被換成原始檔 URI，閱讀器會把原始 TXT 當 EPUB 開，整本書壞掉。依 spec「受影響範圍」，只有 EPUB／PDF／AZW3 可能維持 `content://`，其餘格式一律回傳 `failed`、不碰任何原生呼叫。由 Task 1 的「TXT 書籍回傳 failed」測試釘住。

## 計畫審查修訂（2026-09-28，`reviews/review-plan-issue-2.md`，0 Critical／0 Important／4 Minor）

- **M-1 採納**：`_handleRelinkPressed` 顯示 SnackBar 前先 `hideCurrentSnackBar()`，連續選錯檔案時新結果立即取代舊提示。
- **M-2 不採納**：審查建議在 `_reopenWithFilePath` 內再重設 `_isProbingAccess = false`。這個旗標只在 `_probeAccessAndShowError` 期間為 true，而且在切到錯誤視圖之前就已經還原；重新開書只能從錯誤視圖的按鈕觸發，所以進入 `_reopenWithFilePath` 時它必定是 false。多寫這一行反而會讓讀者誤以為它可能還是 true。「重新開書後再次失敗會重新探測」測試（Review Focus 2）已經證明第二輪探測能正常觸發。
- **M-3 不採納**：審查建議選擇器在 `identifier` 為 null 時改用 `file.path`。在 Android 上，`file_picker` 的 `path` 指向它複製到 App 快取目錄的暫存檔，系統清快取後就會消失。寫進 `Book.filePath` 的話，這本書很快又會打不開，正好違背本功能的目的。此外，專案既有的兩個選擇器（`pickAndImportFiles`、字型管理的上傳）都只用 `identifier`、會把 null 過濾掉，桌面版也不在目前範圍內。維持原寫法：`identifier` 為 null 時視為取消。
- **M-4 採納**：`_pickAndRelink` 在選擇器回傳後先檢查 `mounted`，使用者選檔期間離開閱讀器時不發動 `relinkBook`，避免白做整檔 SHA-256 與持久化授權。Task 2 新增「選檔期間離開閱讀器」測試把這個行為固定住（流程測試 13 → 14 個）。

**使用者決定（2026-09-28）**：
- 保留 `relinkBook` 的格式限制（只接受 EPUB／PDF／AZW3，見 Review Focus 5）。issues.md 的 7 個步驟沒有列出這道檢查，但它符合 spec「受影響範圍」。
- 保留 `_reopenWithFilePath` 內「EPUB 版面偵測尚未完成時重新觸發」這段防禦。依 issues.md 的要求實作；目前的流程走不到這條路徑，所以不另外寫專屬測試。

## 程式審查修訂（2026-09-29，`reviews/review-issue-2.md`，0 Critical／0 Important／4 Minor）

使用者決定 4 項都依建議處理：

- **M-1 修正**：Re-link 成功時先 `hideCurrentSnackBar()`，避免先選錯、再選對之後，重新開書的畫面還掛著上一次的失敗提示。新增 widget test「先選錯再選對：重新開書時收掉上一次的失敗提示」。已確認拿掉修正時這個測試會失敗。
- **M-2 修正**：「選擇器取消」和四種失敗原因的 widget test，原本斷言「repository 記錄不變」，但注入的假匯入服務不碰資料庫，這些斷言永遠會通過。已刪除，改成註明真正的保證在 `book_import_service_test.dart` 的 `relinkBook` 失敗案例；失敗案例的測試名稱從「記錄不變」改成「不重新開書」。這是本計畫 Task 2 Step 3 本身的問題。
- **M-3 修正（方案 a）**：EPUB 的主指紋是用 OPF identifier 算出、卻和原書指紋不符時，再用整檔 SHA-256 比對一次。這樣可以處理「匯入當下沒取得 identifier、資料庫存的是 SHA-256」的情況。原本的指紋保留、不改寫。反過來的情況（資料庫存 identifier、這次讀不到）無法補救，仍回傳 `contentMismatch`，記成已知限制。`_computeRelinkFingerprint` 改寫成 `_readEpubIdentifier`，第 4 步直接呼叫 `computeBookContentFingerprint`。新增兩個服務測試：退回 SHA-256 成功、identifier 與 SHA-256 都不同時仍然拒絕。
- **M-4 記為已知限制**：第 7 步 `updateBook` 失敗時，第 6 步已經持久化的授權和落地複本不會回收。原生端沒有釋放授權的方法；複本檔名固定為 `<bookId>.<格式>`，重試時會直接覆寫。已在程式碼第 7 步加註說明。
- **順帶修正**：實作時 `relinkBook` 插在 `_existingFilePaths` 的說明註解和函式本體中間，導致那段說明變成掛在 `_relinkableFormats` 上。已經把說明搬回 `_existingFilePaths` 前面。

驗證：`book_import_service_test`、`reader_screen_test`、`wifi_transfer_service_test`、`reader_screen_route_test` 共 `+390: All tests passed!`（原 387 個，加上 M-3 兩個、M-1 一個）；`flutter analyze` 顯示 `No issues found!`；l10n 稽核兩項都 PASS。

---

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/library/book_import_service.dart` | Modify | `BookRelinkResult` 系列型別、介面新增 `relinkBook` |
| `app/lib/library/book_import_service_impl.dart` | Modify | `relinkBook` 實作；抽出 `_detectImportFormat`、`_persistPermissionOrLandCopy` 兩個共用 helper |
| `app/test/library/book_import_service_test.dart` | Modify | Re-link 服務單元測試 |
| `app/test/support/fake_book_import_service.dart` | Modify | 可設定回傳值、記錄引數的 `relinkBook` |
| `app/test/wifi_transfer/wifi_transfer_service_test.dart` | Modify | `_ThrowingImportService` 補 `relinkBook` |
| `app/lib/screens/support/book_import_picker_helper.dart` | Modify | `SingleBookFilePicker` typedef、預設實作 `pickSingleBookFileViaFilePicker` |
| `app/lib/screens/reader_screen.dart` | Modify | `pickSingleBookFile` 參數、`_isRelinking`、按鈕、重新連結流程、重新開書復位、移除 lint 豁免 |
| `app/test/screens/reader_screen_test.dart` | Modify | 按鈕顯示條件、M-1／M-2 補測、Re-link 流程的 widget test |
| `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb` | Modify | 五個新 key |
| `app/lib/l10n/app_localizations*.dart` | Regenerate | `flutter gen-l10n` 產物 |

---

### Task 0：建立工作分支（worktree）

- [x] **Step 1：建立 worktree**

在儲存庫根目錄執行：

```bash
git worktree add .worktrees/epic-15-issue-2 -b epic-15/issue-2 main
```

之後所有 Task 都在 `.worktrees/epic-15-issue-2` 內進行（指令在其下的 `app/` 目錄執行）。

---

### Task 1：`BookImportService.relinkBook`（服務層＋測試替身）

**Files:**
- Modify: `app/lib/library/book_import_service.dart`（`ImportResult` 之後新增型別；抽象類別末端新增方法）
- Modify: `app/lib/library/book_import_service_impl.dart`（`_importSingleFile` 第 228–268 行改呼叫 helper；`_existingFilePaths` 之後新增 `relinkBook` 與 helper）
- Modify: `app/test/support/fake_book_import_service.dart`
- Modify: `app/test/wifi_transfer/wifi_transfer_service_test.dart`（`_ThrowingImportService`）
- Test: `app/test/library/book_import_service_test.dart`

**Interfaces:**
- Consumes: 既有 `LibraryRepository.findBookById`／`listBooks`／`updateBook`、`computeBookContentFingerprint`、`kBookMetadataChannel` 的 `extractMetadata`／`computeSha256`／`takePersistableUriPermission`／`copyContentUriToFile`。
- Produces（Task 2 使用）：
  - `BookRelinkResult`、`BookRelinkSuccess(Book updatedBook)`、`BookRelinkFailure(BookRelinkFailureReason reason)`、`BookRelinkFailureReason { formatMismatch, contentMismatch, alreadyInLibrary, failed }`，皆位於 `package:elinkbook/library/book_import_service.dart`。
  - `BookImportService.relinkBook(String bookId, String newUri, {String? displayName})`。
  - `FakeBookImportService`：
    - `BookRelinkResult relinkResult`（預設 `BookRelinkFailure(failed)`）
    - `Completer<BookRelinkResult>? relinkCompleter`（設定時改等它）
    - `Object? relinkError`（設定時回傳 `Future.error`）
    - `List<RelinkCallRecord> relinkCalls`，`RelinkCallRecord` 有 `bookId`、`newUri`、`displayName` 三個欄位。

- [x] **Step 1：新增型別與介面方法，讓測試替身先能編譯**

`book_import_service.dart`：在 `ImportResult` 類別之後新增：

```dart
/// epic-15-storage-permission Issue 2：[BookImportService.relinkBook] 的結果。
/// 用 sealed class 而非純列舉：成功時呼叫端需要知道最終生效的檔案路徑
/// （可能是落地複本的本機路徑，不一定是選取的 URI），必須帶出更新後的
/// [Book]。
sealed class BookRelinkResult {
  const BookRelinkResult();
}

/// 重新連結成功；[updatedBook] 是已寫入資料庫的最新記錄。
final class BookRelinkSuccess extends BookRelinkResult {
  final Book updatedBook;
  const BookRelinkSuccess(this.updatedBook);
}

/// 重新連結失敗的原因（使用者可見文字由呼叫端在地化）。
enum BookRelinkFailureReason {
  /// 選取的檔案格式與原書不同。
  formatMismatch,

  /// 內容指紋不同：選到的不是同一本書。
  contentMismatch,

  /// 選取的檔案已經是書庫中另一本書的來源。
  alreadyInLibrary,

  /// 讀取或寫入失敗，也包含找不到該 id 的書籍記錄、不支援重新連結的格式。
  failed,
}

/// 重新連結失敗；原本的書籍記錄完全不動。
final class BookRelinkFailure extends BookRelinkResult {
  final BookRelinkFailureReason reason;
  const BookRelinkFailure(this.reason);
}
```

`abstract class BookImportService` 的 `importFolder` 宣告之後新增：

```dart
  /// epic-15-storage-permission Issue 2：把書籍 [bookId] 的檔案位置原地換成
  /// 使用者重新選取的 [newUri]（[displayName] 為選擇器提供的真實檔名，
  /// 供 URI 不含副檔名時判斷格式）。先驗證格式、重複、內容指紋，全部通過
  /// 後才持久化授權或落地複本，最後以 `updateBook` 原地更新——`id`、
  /// 閱讀位置、劃線、書籤全部保留。任何驗證失敗都不修改記錄、不持久化
  /// 授權、不留下檔案。處理順序見 epic-15 spec.md「Re-link 服務」。
  Future<BookRelinkResult> relinkBook(
    String bookId,
    String newUri, {
    String? displayName,
  });
```

`test/support/fake_book_import_service.dart`：在 `ImportCallRecord` 類別之後新增：

```dart
/// 記錄一次 [BookImportService.relinkBook] 的呼叫參數
/// （epic-15-storage-permission Issue 2）。
class RelinkCallRecord {
  final String bookId;
  final String newUri;
  final String? displayName;

  const RelinkCallRecord({
    required this.bookId,
    required this.newUri,
    this.displayName,
  });
}
```

在 `FakeBookImportService` 類別內（`importFolder` 之後）新增：

```dart
  /// epic-15-storage-permission Issue 2：[relinkBook] 的回傳值，預設為
  /// `failed`。測試可改成 [BookRelinkSuccess] 或其他失敗原因。
  BookRelinkResult relinkResult =
      const BookRelinkFailure(BookRelinkFailureReason.failed);

  /// 設定時 [relinkBook] 改為等待此 completer，讓測試控制「處理中」的時間點。
  Completer<BookRelinkResult>? relinkCompleter;

  /// 設定時 [relinkBook] 回傳 `Future.error(relinkError)`，模擬服務拋出例外。
  Object? relinkError;

  /// 每次 [relinkBook] 的呼叫參數，依呼叫順序排列。
  final List<RelinkCallRecord> relinkCalls = [];

  @override
  Future<BookRelinkResult> relinkBook(
    String bookId,
    String newUri, {
    String? displayName,
  }) {
    relinkCalls.add(RelinkCallRecord(
      bookId: bookId,
      newUri: newUri,
      displayName: displayName,
    ));
    final error = relinkError;
    if (error != null) return Future.error(error);
    final completer = relinkCompleter;
    if (completer != null) return completer.future;
    return Future.value(relinkResult);
  }
```

`test/wifi_transfer/wifi_transfer_service_test.dart` 的 `_ThrowingImportService`，在 `importFolder` 之後新增：

```dart
  // epic-15-storage-permission Issue 2：介面新增方法，本測試不使用。
  @override
  Future<BookRelinkResult> relinkBook(
    String bookId,
    String newUri, {
    String? displayName,
  }) =>
      Future.value(const BookRelinkFailure(BookRelinkFailureReason.failed));
```

（該檔已 import `package:elinkbook/library/book_import_service.dart`，不必另外補；若沒有，補上。）

`book_import_service_impl.dart` 先放一個會讓測試失敗的最小實作，確保全專案可編譯：在 `_existingFilePaths` 之前新增：

```dart
  @override
  Future<BookRelinkResult> relinkBook(
    String bookId,
    String newUri, {
    String? displayName,
  }) async =>
      const BookRelinkFailure(BookRelinkFailureReason.failed);
```

Run: `flutter analyze`
Expected: `No issues found!`（確認所有實作都已補上方法）

- [x] **Step 2：寫失敗的測試**

`book_import_service_test.dart` 頂端 import 區補上（已存在的不重複加）：

```dart
import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:path/path.dart' as p;
```

在 `main()` 內、最後一個 `group` 之後新增：

```dart
  group('relinkBook（epic-15-storage-permission Issue 2）', () {
    const oldPdfUri = 'content://example/old/book.pdf';
    const newPdfUri = 'content://example/new/book.pdf';
    const oldEpubUri = 'content://example/old/book.epub';
    const newEpubUri = 'content://example/new/book.epub';

    late List<MethodCall> calls;

    /// 模擬原生端：extractMetadata 回傳 [epubIdentifier]、computeSha256 回傳
    /// [sha256]（null 模擬計算失敗）、持久化授權依 [failPermission] 成功或失敗、
    /// 落地複本依 [failCopy] 成功或失敗。所有呼叫記錄在 [calls]。
    void mockRelinkChannel({
      String? epubIdentifier,
      String? sha256 = 'sha-same',
      bool failPermission = false,
      bool failCopy = false,
    }) {
      calls = [];
      mockChannel((call) async {
        calls.add(call);
        switch (call.method) {
          case 'extractMetadata':
            return {'title': '新選取的檔案', 'identifier': epubIdentifier};
          case 'computeSha256':
            return sha256;
          case 'takePersistableUriPermission':
            if (failPermission) {
              throw PlatformException(code: 'permission_failed');
            }
            return null;
          case 'copyContentUriToFile':
            if (failCopy) throw PlatformException(code: 'copy_failed');
            return null;
        }
        return null;
      });
    }

    bool wasCalled(String method) => calls.any((c) => c.method == method);

    Future<Book> seedBook({
      String id = 'b1',
      BookFileFormat format = BookFileFormat.pdf,
      String filePath = oldPdfUri,
      String? contentFingerprint = 'sha-same',
    }) {
      final time = DateTime.fromMillisecondsSinceEpoch(1000);
      return repository.insertBook(Book(
        id: id,
        title: '原書 $id',
        author: '原作者',
        format: format,
        filePath: filePath,
        source: BookSource.local,
        coverPath: '/covers/$id.png',
        contentFingerprint: contentFingerprint,
        createTime: time,
        lastReadTime: time,
      ));
    }

    /// 驗證前 5 步失敗時的共同保證：沒有持久化授權、沒有落地複本、
    /// 記錄的 filePath 維持原值。
    Future<void> expectUntouched(String bookId, String originalPath) async {
      expect(wasCalled('takePersistableUriPermission'), isFalse);
      expect(wasCalled('copyContentUriToFile'), isFalse);
      expect(importedBooksDir.listSync(), isEmpty);
      expect((await repository.findBookById(bookId))!.filePath, originalPath);
    }

    test('PDF 指紋相同：持久化新 URI 授權後原地更新 filePath，id 不變', () async {
      await seedBook();
      mockRelinkChannel();

      final result = await service.relinkBook('b1', newPdfUri,
          displayName: 'book.pdf');

      expect(result, isA<BookRelinkSuccess>());
      final updated = (result as BookRelinkSuccess).updatedBook;
      expect(updated.id, 'b1');
      expect(updated.filePath, newPdfUri);
      expect((await repository.findBookById('b1'))!.filePath, newPdfUri);
      final permissionCall =
          calls.singleWhere((c) => c.method == 'takePersistableUriPermission');
      expect((permissionCall.arguments as Map)['uri'], newPdfUri);
    });

    test('EPUB 以 extractMetadata 取得的 OPF identifier 比對，與資料庫中的 '
        'identifier 相同時判定為同一本書（回歸：不可改算 SHA-256）', () async {
      await seedBook(
        format: BookFileFormat.epub,
        filePath: oldEpubUri,
        contentFingerprint: 'urn:uuid:same-book',
      );
      mockRelinkChannel(
          epubIdentifier: 'urn:uuid:same-book', sha256: 'sha-would-mismatch');

      final result = await service.relinkBook('b1', newEpubUri);

      expect(result, isA<BookRelinkSuccess>());
      expect(wasCalled('computeSha256'), isFalse);
      final metadataCall =
          calls.singleWhere((c) => c.method == 'extractMetadata');
      expect((metadataCall.arguments as Map)['uri'], newEpubUri);
    });

    test('選取的 URI 等於原書自己的 filePath（撤銷後重新授權同一個檔案）時，'
        '不判定為 alreadyInLibrary，正常完成', () async {
      await seedBook();
      mockRelinkChannel();

      final result = await service.relinkBook('b1', oldPdfUri);

      expect(result, isA<BookRelinkSuccess>());
      expect((result as BookRelinkSuccess).updatedBook.filePath, oldPdfUri);
      expect(wasCalled('takePersistableUriPermission'), isTrue);
    });

    test('格式不同回傳 formatMismatch，不持久化、不落地、不改記錄', () async {
      await seedBook(format: BookFileFormat.epub, filePath: oldEpubUri);
      mockRelinkChannel();

      final result = await service.relinkBook('b1', newPdfUri);

      expect((result as BookRelinkFailure).reason,
          BookRelinkFailureReason.formatMismatch);
      await expectUntouched('b1', oldEpubUri);
    });

    test('新 URI 已是另一本書的來源時回傳 alreadyInLibrary，不持久化、不落地、'
        '不改記錄', () async {
      await seedBook();
      await seedBook(id: 'b2', filePath: newPdfUri);
      mockRelinkChannel();

      final result = await service.relinkBook('b1', newPdfUri);

      expect((result as BookRelinkFailure).reason,
          BookRelinkFailureReason.alreadyInLibrary);
      await expectUntouched('b1', oldPdfUri);
    });

    test('內容指紋不同回傳 contentMismatch，不持久化、不落地、不改記錄', () async {
      await seedBook(contentFingerprint: 'sha-original');
      mockRelinkChannel(sha256: 'sha-another-book');

      final result = await service.relinkBook('b1', newPdfUri);

      expect((result as BookRelinkFailure).reason,
          BookRelinkFailureReason.contentMismatch);
      await expectUntouched('b1', oldPdfUri);
    });

    test('找不到書籍 id 時回傳 failed', () async {
      mockRelinkChannel();

      final result = await service.relinkBook('no-such-book', newPdfUri);

      expect((result as BookRelinkFailure).reason,
          BookRelinkFailureReason.failed);
      expect(calls, isEmpty);
    });

    test('指紋計算失敗（computeSha256 回傳 null）時回傳 failed，不持久化、'
        '不落地、不改記錄', () async {
      await seedBook();
      mockRelinkChannel(sha256: null);

      final result = await service.relinkBook('b1', newPdfUri);

      expect((result as BookRelinkFailure).reason,
          BookRelinkFailureReason.failed);
      await expectUntouched('b1', oldPdfUri);
    });

    test('TXT 書籍（filePath 是匯入時合成的落地檔）不支援重新連結，回傳 failed '
        '且不呼叫任何原生方法', () async {
      final localTxt = p.join(importedBooksDir.path, 'synth.txt');
      await seedBook(format: BookFileFormat.txt, filePath: localTxt);
      mockRelinkChannel();

      final result = await service.relinkBook(
          'b1', 'content://example/new/book.txt');

      expect((result as BookRelinkFailure).reason,
          BookRelinkFailureReason.failed);
      expect(calls, isEmpty);
      expect((await repository.findBookById('b1'))!.filePath, localTxt);
    });

    test('原書沒有指紋時略過比對，並把新算出的指紋寫回', () async {
      await seedBook(contentFingerprint: null);
      mockRelinkChannel(sha256: 'sha-new');

      final result = await service.relinkBook('b1', newPdfUri);

      expect(result, isA<BookRelinkSuccess>());
      expect((await repository.findBookById('b1'))!.contentFingerprint,
          'sha-new');
    });

    test('驗證通過後持久化授權失敗：改存落地複本，回傳帶本機路徑的成功結果',
        () async {
      await seedBook();
      mockRelinkChannel(failPermission: true);

      final result = await service.relinkBook('b1', newPdfUri);

      final expectedPath = p.join(importedBooksDir.path, 'b1.pdf');
      expect((result as BookRelinkSuccess).updatedBook.filePath, expectedPath);
      expect((await repository.findBookById('b1'))!.filePath, expectedPath);
      final copyCall = calls.singleWhere((c) => c.method == 'copyContentUriToFile');
      expect((copyCall.arguments as Map)['uri'], newPdfUri);
      expect((copyCall.arguments as Map)['destinationPath'], expectedPath);
    });

    test('URI 不含副檔名（媒體庫不透明 ID）時以 displayName 判斷格式，並改存'
        '落地複本', () async {
      await seedBook();
      mockRelinkChannel();
      const opaqueUri =
          'content://com.android.providers.media.documents/document/document%3A42';

      final result = await service.relinkBook('b1', opaqueUri,
          displayName: '原書.pdf');

      expect((result as BookRelinkSuccess).updatedBook.filePath,
          p.join(importedBooksDir.path, 'b1.pdf'));
      expect(wasCalled('copyContentUriToFile'), isTrue);
    });

    test('持久化授權與落地複本都失敗時回傳 failed，記錄不變', () async {
      await seedBook();
      mockRelinkChannel(failPermission: true, failCopy: true);

      final result = await service.relinkBook('b1', newPdfUri);

      expect((result as BookRelinkFailure).reason,
          BookRelinkFailureReason.failed);
      expect((await repository.findBookById('b1'))!.filePath, oldPdfUri);
    });

    test('以 findBookById 的最新記錄為基礎：閱讀位置、書名、封面、作者全部保留',
        () async {
      final seeded = await seedBook();
      // 模擬匯入之後使用者讀過這本書，閱讀位置寫回資料庫。
      await repository.updateBook(
          seeded.copyWith(progress: 0.42, pdfPageIndex: 17));
      mockRelinkChannel();

      await service.relinkBook('b1', newPdfUri);

      final stored = (await repository.findBookById('b1'))!;
      expect(stored.filePath, newPdfUri);
      expect(stored.progress, 0.42);
      expect(stored.pdfPageIndex, 17);
      expect(stored.title, '原書 b1');
      expect(stored.author, '原作者');
      expect(stored.coverPath, '/covers/b1.png');
    });
  });
```

- [x] **Step 3：執行測試，確認失敗**

Run: `flutter test test/library/book_import_service_test.dart --plain-name "relinkBook"`
Expected: FAIL。所有預期 `BookRelinkSuccess` 的案例失敗（實際是 `BookRelinkFailure`）；`formatMismatch`／`alreadyInLibrary`／`contentMismatch` 三個案例的 `reason` 斷言失敗（實際是 `failed`）。「找不到書籍 id」「TXT 書籍」「指紋計算失敗」「兩者都失敗」這幾個預期 `failed` 的案例，在最小實作下就會通過，這是預期中的正向對照。

- [x] **Step 4：實作**

`book_import_service_impl.dart`：

**4a. 抽出兩個共用 helper。** 在 `_copyToLocalStorage` 之前新增：

```dart
  /// 判斷匯入／重新連結檔案的格式：優先用呼叫端提供的真實檔名，URI 當退路。
  /// 部分文件提供者（例如媒體庫文件提供者 com.android.providers.media.documents，
  /// 使用者透過系統選擇器的「最近」／媒體索引視圖選檔時常見）回傳的 URI
  /// 只帶不透明數字文件 ID（例如 .../document/document%3A1000001716），
  /// 完全不含檔名／副檔名——只看 URI 判斷格式在這種情況下必定回傳 null
  /// （真機驗證發現的實際症狀：選檔正確返回、匯入沒有拋出任何例外，但
  /// 書架永遠是空的）。資料夾匯入（importFolder）目前仍只有 URI 可用
  /// （DocumentFile 的 uri 路徑對 externalstorage 這類本機提供者通常仍
  /// 保留可辨識檔名），沒有另外提供 displayName 時退回只看 URI。
  /// epic-15-storage-permission Issue 2 起由 [relinkBook] 共用。
  BookFileFormat? _detectImportFormat(String uri, String? displayName) =>
      (displayName != null ? detectBookFileFormat(displayName) : null) ??
          detectBookFileFormat(uri);

  /// 對 `content://` URI 持久化讀取授權，回傳最終要寫進 `Book.filePath` 的
  /// 路徑；非 `content://` 輸入原樣回傳。
  ///
  /// 只對 content:// scheme 持久化權限（file_picker 在 Android 上一定回傳
  /// content:// URI；此判斷主要防禦測試/除錯情境誤傳純路徑）。部分文件
  /// 提供者（例如媒體庫文件提供者 com.android.providers.media.documents，
  /// 相對於標準的外部儲存文件提供者）在某些裝置/Android 版本上不保證核發
  /// 可持久化授權，`takePersistableUriPermission` 會拋出 PlatformException；
  /// 此時不能直接放棄（先前版本的行為——真機驗證發現這會讓匯入功能在部分
  /// 裝置上整個無法使用），改為退而求其次：把檔案內容複製一份到 App 私有
  /// 儲存空間，改用這份本機複本的真實檔案路徑，不再依賴來源 content:// URI
  /// 在下次啟動後是否還能讀取——複製也失敗才回傳 null。
  ///
  /// 即使權限持久化成功，若來源 URI 本身不含可辨識副檔名（例如媒體庫文件
  /// 提供者的不透明數字 ID），ReaderScreen 開啟時仍是依 filePath 的副檔名
  /// 判斷格式（detectBookFormat，與匯入時的格式判斷各自獨立運作）——
  /// filePath 若維持原始 URI，開啟時會判定為不支援的格式。因此只要 URI
  /// 本身沒有可辨識副檔名，就一律複製一份到本機、以正確副檔名命名，讓
  /// 匯入與開啟兩處的格式判斷全程一致。
  ///
  /// epic-15-storage-permission Issue 2 起由 [relinkBook] 共用，確保重新
  /// 連結與第一次匯入的行為一致。
  Future<String?> _persistPermissionOrLandCopy(
    String uri,
    String id,
    BookFileFormat format,
  ) async {
    if (!uri.startsWith('content://')) return uri;
    var permissionGranted = true;
    try {
      await kBookMetadataChannel.invokeMethod<void>(
        'takePersistableUriPermission',
        {'uri': uri},
      );
    } on PlatformException {
      permissionGranted = false;
    }
    if (!permissionGranted || detectBookFileFormat(uri) == null) {
      return _copyToLocalStorage(uri, id, format);
    }
    return uri;
  }
```

**4b. `_importSingleFile` 改呼叫 helper。** 把第 218–231 行（`// 優先用呼叫端提供的真實檔名` 那段註解到 `if (format == null) return null;`）改成：

```dart
    final format = _detectImportFormat(uri, displayName);
    if (format == null) return null;
```

把第 235–268 行（`// 只對 content:// scheme 持久化權限` 那段註解到 `if (takePermission && ...) { ... }` 區塊結尾）改成：

```dart
    // 持久化授權／落地複本規則見 _persistPermissionOrLandCopy。資料夾批次
    // 匯入（importFolder）的子檔案 URI 共用資料夾層級已取得的權限，呼叫時
    // 傳入 takePermission: false 跳過這一步。
    var resolvedUri = uri;
    if (takePermission) {
      final persisted = await _persistPermissionOrLandCopy(uri, id, format);
      if (persisted == null) return null;
      resolvedUri = persisted;
    }
```

中間的 `final id = ...;` 那一行保持不動。

**4c. 實作 `relinkBook`。** 把 Step 1 的最小實作整段替換為：

```dart
  /// epic-15-storage-permission Issue 2：可能維持 `content://` 的格式。
  /// TXT／MD 匯入時已合成 EPUB 並落地、CBZ 匯入時已重建並落地，
  /// `filePath` 指向落地檔；若換成原始檔 URI，閱讀器會把原始檔當合成結果
  /// 開啟，整本書壞掉（spec.md「受影響範圍」）。
  static const _relinkableFormats = {
    BookFileFormat.epub,
    BookFileFormat.pdf,
    BookFileFormat.azw3,
  };

  @override
  Future<BookRelinkResult> relinkBook(
    String bookId,
    String newUri, {
    String? displayName,
  }) async {
    try {
      // 1. 讀取最新記錄：由服務自行讀取而非由呼叫端傳入 Book 快照，避免
      //    updateBook 整列覆寫時把閱讀位置等欄位蓋回舊值。
      final book = await _repository.findBookById(bookId);
      if (book == null || !_relinkableFormats.contains(book.format)) {
        return const BookRelinkFailure(BookRelinkFailureReason.failed);
      }

      // 2. 格式必須與原書相同（規則與第一次匯入共用）。
      final format = _detectImportFormat(newUri, displayName);
      if (format != book.format) {
        return const BookRelinkFailure(BookRelinkFailureReason.formatMismatch);
      }

      // 3. 新 URI 不可是另一本書的來源；等於原書自己的 filePath 則放行
      //    （撤銷授權後重新選取同一個檔案，是本功能的主要情境）。
      final books = await _repository.listBooks();
      if (books.any((b) => b.id != book.id && b.filePath == newUri)) {
        return const BookRelinkFailure(
            BookRelinkFailureReason.alreadyInLibrary);
      }

      // 4. 利用選擇器核發的暫時讀取授權計算指紋——此時尚未持久化授權，
      //    選錯檔案不會白白消耗系統的持久化授權配額。
      final fingerprint = await _computeRelinkFingerprint(newUri, format!);

      // 5. 比對指紋；原書沒有指紋時略過，稍後補寫。
      final originalFingerprint = book.contentFingerprint;
      if (originalFingerprint != null && originalFingerprint != fingerprint) {
        return const BookRelinkFailure(
            BookRelinkFailureReason.contentMismatch);
      }

      // 6. 確認是同一本書後才持久化授權或落地複本（規則與第一次匯入共用）。
      final resolvedPath =
          await _persistPermissionOrLandCopy(newUri, book.id, format);
      if (resolvedPath == null) {
        return const BookRelinkFailure(BookRelinkFailureReason.failed);
      }

      // 7. 原地更新：只改 filePath 與補寫的指紋，其餘欄位沿用最新記錄。
      final updated = book.copyWith(
        filePath: resolvedPath,
        contentFingerprint: originalFingerprint ?? fingerprint,
      );
      await _repository.updateBook(updated);
      return BookRelinkSuccess(updated);
    } catch (_) {
      // 指紋計算失敗（computeSha256 回傳 null 會拋出 StateError）、資料庫
      // 讀寫失敗等，一律視為 failed：本方法保證不拋出例外，呼叫端只需
      // 依結果顯示對應 SnackBar。
      return const BookRelinkFailure(BookRelinkFailureReason.failed);
    }
  }

  /// epic-15-storage-permission Issue 2：計算重新選取檔案的內容指紋，算法
  /// 必須與第一次匯入完全一致——EPUB 先以 `extractMetadata` 取 OPF
  /// identifier（取不到才退回 SHA-256），其餘格式直接取 SHA-256。若跳過
  /// `extractMetadata`，EPUB 會算出 SHA-256，和資料庫裡存的 identifier
  /// 永遠對不上，所有 EPUB 都會被誤判為不同的書。
  Future<String> _computeRelinkFingerprint(
    String uri,
    BookFileFormat format,
  ) async {
    String? epubIdentifier;
    if (format == BookFileFormat.epub) {
      try {
        final metadata =
            await kBookMetadataChannel.invokeMapMethod<String, Object?>(
          'extractMetadata',
          {'uri': uri, 'format': format.name},
        );
        epubIdentifier = metadata?['identifier'] as String?;
      } on PlatformException {
        // 比照匯入：詮釋資料提取失敗時退回整檔 SHA-256。
      }
    }
    return computeBookContentFingerprint(
      uri,
      format,
      epubIdentifier: epubIdentifier,
    );
  }
```

說明：`format!` 安全，因為 `format != book.format` 已經排除了 null（`book.format` 非 null）。若 analyzer 提示多餘的 `!`，改成直接用 `format`。

- [x] **Step 5：執行測試，確認通過**

Run: `flutter test test/library/book_import_service_test.dart`
Expected: All tests passed，包含新增的 14 個 `relinkBook` 案例與所有既有匯入案例（證明抽出 helper 沒有改變匯入行為）。

Run: `flutter test test/wifi_transfer/wifi_transfer_service_test.dart`
Expected: All tests passed。

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add lib/library/book_import_service.dart lib/library/book_import_service_impl.dart test/library/book_import_service_test.dart test/support/fake_book_import_service.dart test/wifi_transfer/wifi_transfer_service_test.dart
git commit -m "feat(library): BookImportService 新增 relinkBook 原地重新連結書籍（epic-15 Issue 2）"
```

---

### Task 2：閱讀器錯誤視圖的「重新選取檔案」與重新開書（含在地化）

**Files:**
- Modify: `app/lib/screens/support/book_import_picker_helper.dart`（檔案末端新增）
- Modify: `app/lib/screens/reader_screen.dart`：
  - import 區
  - `ReaderScreen` 建構參數（`bookImportService` 之後）
  - State 欄位區（`_activeFilePath` 附近，約第 373–384 行）
  - `_handleOpenBookTimeout` 之後新增重新連結方法（約第 2003 行）
  - `_buildBody` 錯誤分支（約第 2896 行）
- Modify: `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`
- Regenerate: `app/lib/l10n/app_localizations*.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：
  - Task 1 的 `BookRelinkResult`／`BookRelinkSuccess`／`BookRelinkFailure`／`BookRelinkFailureReason`、`BookImportService.relinkBook`、`FakeBookImportService.relinkResult`／`relinkCompleter`／`relinkError`／`relinkCalls`。
  - Issue 1 的 `_probeResult`、`_isProbingAccess`、`probeStorageAccess`。
  - Issue 0 的 `_activeFilePath`、`widget.bookImportService`。
- Produces：
  - `typedef SingleBookFilePicker` 與 `pickSingleBookFileViaFilePicker`（`lib/screens/support/book_import_picker_helper.dart`）。
  - `ReaderScreen.pickSingleBookFile`（`SingleBookFilePicker?`，null 時走預設實作）。
  - l10n getter：`readerStorageRelinkButton`、`readerStorageRelinkFormatMismatch`、`readerStorageRelinkContentMismatch`、`readerStorageRelinkAlreadyInLibrary`、`readerStorageRelinkFailed`。

- [x] **Step 1：新增 ARB key 並產生程式碼**

四份 ARB 都在 `"readerStorageFileNotFoundMessage"` 之後插入（範本檔在它的 `"@readerStorageFileNotFoundMessage": {...}` 區塊之後）。

`app_zh_TW.arb`：

```json
  "readerStorageRelinkButton": "重新選取檔案",
  "@readerStorageRelinkButton": {
    "description": "epic-15 Issue 2：存取權限失效或找不到檔案時，錯誤畫面上重新選取書籍檔案的按鈕"
  },
  "readerStorageRelinkFormatMismatch": "選取的檔案格式與原書不同",
  "@readerStorageRelinkFormatMismatch": {
    "description": "epic-15 Issue 2：重新選取的檔案格式與原書不同（例如原書 EPUB 卻選了 PDF）時的 SnackBar"
  },
  "readerStorageRelinkContentMismatch": "選取的檔案與原書內容不同，請選取同一本書",
  "@readerStorageRelinkContentMismatch": {
    "description": "epic-15 Issue 2：重新選取的檔案內容指紋與原書不同（選到另一本書）時的 SnackBar"
  },
  "readerStorageRelinkAlreadyInLibrary": "這個檔案已經是書庫中的另一本書",
  "@readerStorageRelinkAlreadyInLibrary": {
    "description": "epic-15 Issue 2：重新選取的檔案已是書庫中另一本書的來源時的 SnackBar"
  },
  "readerStorageRelinkFailed": "重新連結失敗，請再試一次",
  "@readerStorageRelinkFailed": {
    "description": "epic-15 Issue 2：重新連結因讀取或寫入失敗等其他原因失敗時的 SnackBar"
  },
```

`app_zh.arb`（內容同正體中文，不含 `@key`）：

```json
  "readerStorageRelinkButton": "重新選取檔案",
  "readerStorageRelinkFormatMismatch": "選取的檔案格式與原書不同",
  "readerStorageRelinkContentMismatch": "選取的檔案與原書內容不同，請選取同一本書",
  "readerStorageRelinkAlreadyInLibrary": "這個檔案已經是書庫中的另一本書",
  "readerStorageRelinkFailed": "重新連結失敗，請再試一次",
```

`app_zh_CN.arb`：

```json
  "readerStorageRelinkButton": "重新选择文件",
  "readerStorageRelinkFormatMismatch": "选择的文件格式与原书不同",
  "readerStorageRelinkContentMismatch": "选择的文件与原书内容不同，请选择同一本书",
  "readerStorageRelinkAlreadyInLibrary": "这个文件已经是书库中的另一本书",
  "readerStorageRelinkFailed": "重新链接失败，请再试一次",
```

`app_en.arb`：

```json
  "readerStorageRelinkButton": "Select file again",
  "readerStorageRelinkFormatMismatch": "The selected file's format doesn't match the original book.",
  "readerStorageRelinkContentMismatch": "The selected file isn't the same book. Please select the original book's file.",
  "readerStorageRelinkAlreadyInLibrary": "This file is already another book in your library.",
  "readerStorageRelinkFailed": "Couldn't relink the file. Please try again.",
```

Run: `flutter gen-l10n`
Expected: 沒有錯誤輸出；`git status` 看得到 `lib/l10n/app_localizations.dart`、`app_localizations_zh.dart`、`app_localizations_en.dart` 被修改。

- [x] **Step 2：新增選擇器 typedef 與預設實作**

`lib/screens/support/book_import_picker_helper.dart` 檔案末端新增：

```dart
/// epic-15-storage-permission Issue 2：單檔選擇器。[allowedExtensions] 依
/// 原書格式傳入（例如 EPUB 傳 `['epub']`）；使用者取消時回傳 `null`。包成
/// 可注入的函式型別，讓 `ReaderScreen` 的 widget test 不必觸碰平台實作。
typedef SingleBookFilePicker = Future<({String uri, String? displayName})?>
    Function(List<String> allowedExtensions);

/// [SingleBookFilePicker] 的預設實作：`FilePicker` 單選。`uri` 是
/// `PlatformFile.identifier`（Android 上為 `content://` URI），`displayName`
/// 是真實檔名，供 URI 不含副檔名時判斷格式。選擇器拋出例外時比照
/// [pickAndImportFiles] 既有行為視為取消，回傳 `null`。
Future<({String uri, String? displayName})?> pickSingleBookFileViaFilePicker(
  List<String> allowedExtensions,
) async {
  try {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    final file = picked?.files.firstOrNull;
    final uri = file?.identifier;
    if (file == null || uri == null) return null;
    return (uri: uri, displayName: file.name);
  } catch (_) {
    return null;
  }
}
```

- [x] **Step 3：寫失敗的測試**

`reader_screen_test.dart` import 區補上（已存在的不重複加）：

```dart
import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/library_repository.dart'
    show kBookMetadataChannel;
import 'package:elinkbook/screens/support/book_import_picker_helper.dart';
```

**3a. 擴充 Issue 1 的 `_pumpContentUriReader`**：新增三個選用參數，並傳給 `ReaderScreen`（既有呼叫端不受影響）。把它的參數列與 `home:` 改成：

```dart
Future<int Function()> _pumpContentUriReader(
  WidgetTester tester, {
  required FakeReaderPrefsManager prefsManager,
  required Future<StorageAccessProbeResult> Function(String uri) probe,
  String filePath = 'content://com.example.provider/book.epub',
  // epic-15-storage-permission Issue 2
  String bookId = 'b_probe',
  BookImportService? bookImportService,
  SingleBookFilePicker? pickSingleBookFile,
}) async {
```

```dart
      home: ReaderScreen(
        filePath: filePath,
        bookId: bookId,
        prefsManager: prefsManager,
        isFixedLayout: false,
        bookImportService: bookImportService,
        pickSingleBookFile: pickSingleBookFile,
      ),
```

**3b. 在 `_pumpContentUriReader` 之後新增 Issue 2 的測試輔助函式：**

```dart
/// epic-15-storage-permission Issue 2：反覆 pump 直到 [condition] 成立或達到
/// 上限。閱讀器載入中有無限動畫，不能用 pumpAndSettle。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 50,
}) async {
  for (var i = 0; i < maxPumps && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// epic-15-storage-permission Issue 2：暫時覆寫 [cacheBookForServing]，依序
/// 記錄收到的路徑。[failPaths] 內的路徑回傳 null（模擬開書失敗，
/// FoliateReaderView 會呼叫 onError）；[hangPaths] 內的路徑永不完成（模擬
/// 開書卡住）；其餘回傳假快取路徑。測試結束時還原全檔 setUpAll 的覆寫。
List<String> _overrideCacheBookForServing({
  Set<String> failPaths = const {},
  Set<String> hangPaths = const {},
}) {
  final calls = <String>[];
  final original = cacheBookForServing;
  cacheBookForServing = (filePath, instanceId) {
    calls.add(filePath);
    if (failPaths.contains(filePath)) return Future.value(null);
    if (hangPaths.contains(filePath)) return Completer<String?>().future;
    return Future.value('/fake/cache/dir/current.epub');
  };
  addTearDown(() => cacheBookForServing = original);
  return calls;
}

/// epic-15-storage-permission Issue 2：假的單檔選擇器，記錄每次收到的
/// allowedExtensions。[pending] 非 null 時等它完成，否則立即回傳 [result]
/// （null 代表使用者取消）。
class _FakeSingleBookFilePicker {
  _FakeSingleBookFilePicker(this.result);

  final ({String uri, String? displayName})? result;
  Completer<({String uri, String? displayName})?>? pending;
  final List<List<String>> calls = [];

  Future<({String uri, String? displayName})?> call(
      List<String> allowedExtensions) {
    calls.add(allowedExtensions);
    return pending?.future ?? Future.value(result);
  }
}

/// epic-15-storage-permission Issue 2：Re-link widget test 用的書籍記錄。
Book _relinkTestBook({
  String id = 'b_probe',
  BookFileFormat format = BookFileFormat.epub,
  required String filePath,
  String? contentFingerprint,
}) {
  return Book(
    id: id,
    title: '重新連結測試書',
    format: format,
    filePath: filePath,
    source: BookSource.local,
    contentFingerprint: contentFingerprint,
    createTime: DateTime.fromMillisecondsSinceEpoch(0),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
  );
}
```

**3c. 在 `main()` 內、Issue 1 的 `group('開書失敗的存取探測…')` 之後新增：**

```dart
  group('重新選取檔案（epic-15-storage-permission Issue 2）', () {
    const relinkButton = Key('reader_storage_relink_button');
    const relinkProgress = Key('reader_storage_relink_progress');
    const oldUri = 'content://com.example.provider/book.epub';
    const newUri = 'content://com.example.provider/moved/book.epub';

    /// 觸發一次開書失敗並等到錯誤視圖出現（以 onError seam 觸發，
    /// 與 Issue 1 測試相同）。
    Future<void> failAndShowError(WidgetTester tester) async {
      tester
          .widget<FoliateReaderView>(find.byType(FoliateReaderView))
          .onError('boom');
      await _pumpUntil(tester,
          () => find.byKey(const Key('reader_error_text')).evaluate().isNotEmpty);
    }

    String errorText(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const Key('reader_error_text')))
        .data!;

    // ── 按鈕顯示條件 ──

    for (final result in [
      StorageAccessProbeResult.permissionRevoked,
      StorageAccessProbeResult.fileNotFound,
    ]) {
      testWidgets('$result 且有匯入服務：顯示有外框的重新選取按鈕', (tester) async {
        await _pumpContentUriReader(tester,
            prefsManager: prefsManager,
            probe: (_) async => result,
            bookImportService: FakeBookImportService());
        await failAndShowError(tester);

        expect(find.byKey(relinkButton), findsOneWidget);
        expect(tester.widget(find.byKey(relinkButton)), isA<OutlinedButton>());
        expect(
          find.descendant(
              of: find.byKey(relinkButton), matching: find.text('重新選取檔案')),
          findsOneWidget,
        );
      });
    }

    for (final result in [
      StorageAccessProbeResult.readable,
      StorageAccessProbeResult.unknownError,
    ]) {
      testWidgets('$result：不顯示重新選取按鈕', (tester) async {
        await _pumpContentUriReader(tester,
            prefsManager: prefsManager,
            probe: (_) async => result,
            bookImportService: FakeBookImportService());
        await failAndShowError(tester);

        expect(find.byKey(relinkButton), findsNothing);
      });
    }

    testWidgets('沒有匯入服務時只顯示分類說明，不顯示按鈕', (tester) async {
      await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => StorageAccessProbeResult.permissionRevoked);
      await failAndShowError(tester);

      expect(errorText(tester), 'App 對這個檔案的存取權限已失效，請重新選取檔案。');
      expect(find.byKey(relinkButton), findsNothing);
    });

    testWidgets('補 Issue 1 審查 M-1：cacheBookForServing 回傳 null → '
        'FoliateReaderView onError → 探測一次並顯示說明與按鈕', (tester) async {
      _overrideCacheBookForServing(failPaths: {oldUri});
      final probeCalls = await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => StorageAccessProbeResult.permissionRevoked,
          bookImportService: FakeBookImportService());
      await _pumpUntil(
          tester, () => find.byKey(relinkButton).evaluate().isNotEmpty);

      expect(probeCalls(), 1);
      expect(errorText(tester), 'App 對這個檔案的存取權限已失效，請重新選取檔案。');
      expect(find.byKey(relinkButton), findsOneWidget);
    });

    testWidgets('補 Issue 1 審查 M-2：content:// PDF 開書失敗同樣探測並顯示按鈕',
        (tester) async {
      // PdfReaderView 以 readContentUriAll 取得暫存檔；回傳 null 會拋出
      // StateError → onError。
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const resourceChannel = MethodChannel('elinkbook/reader_resources_cache');
      messenger.setMockMethodCallHandler(resourceChannel, (call) async => null);
      addTearDown(
          () => messenger.setMockMethodCallHandler(resourceChannel, null));

      final probeCalls = await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          filePath: 'content://com.example.provider/book.pdf',
          probe: (_) async => StorageAccessProbeResult.permissionRevoked,
          bookImportService: FakeBookImportService());
      await _pumpUntil(
          tester, () => find.byKey(relinkButton).evaluate().isNotEmpty);

      expect(probeCalls(), 1);
      expect(find.byKey(relinkButton), findsOneWidget);
    });

    // ── 重新連結流程 ──

    testWidgets('選取成功：記錄原地更新、id 不變，回到載入中並以新路徑重新開書'
        '（真實 BookImportServiceImpl＋記憶體 repository）', (tester) async {
      final cacheCalls = _overrideCacheBookForServing(failPaths: {oldUri});
      final repository = FakeLibraryRepository(initialBooks: [
        _relinkTestBook(filePath: oldUri, contentFingerprint: 'urn:uuid:same'),
      ]);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(kBookMetadataChannel, (call) async {
        if (call.method == 'extractMetadata') {
          return {'identifier': 'urn:uuid:same'};
        }
        return null; // takePersistableUriPermission 成功
      });
      addTearDown(
          () => messenger.setMockMethodCallHandler(kBookMetadataChannel, null));
      final picker =
          _FakeSingleBookFilePicker((uri: newUri, displayName: 'book.epub'));

      await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => StorageAccessProbeResult.permissionRevoked,
          bookImportService: BookImportServiceImpl(repository: repository),
          pickSingleBookFile: picker.call);
      await _pumpUntil(
          tester, () => find.byKey(relinkButton).evaluate().isNotEmpty);

      await tester.tap(find.byKey(relinkButton));
      await _pumpUntil(tester, () => cacheCalls.length == 2);

      expect(picker.calls, [
        ['epub']
      ]);
      final stored = await repository.findBookById('b_probe');
      expect(stored!.filePath, newUri);
      expect(stored.id, 'b_probe');
      // 閱讀視圖重新建立：快取函式以新路徑再被呼叫一次（不需要 ValueKey）。
      expect(cacheCalls, [oldUri, newUri]);
      expect(find.byKey(const Key('reader_error_text')), findsNothing);
      expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);
    });

    testWidgets('Re-link 回傳落地複本路徑時，重新開書使用該本機路徑', (tester) async {
      const localCopy = '/data/user/0/app/imported_books/b_probe.epub';
      final cacheCalls = _overrideCacheBookForServing(failPaths: {oldUri});
      final service = FakeBookImportService()
        ..relinkResult = BookRelinkSuccess(
            _relinkTestBook(filePath: localCopy));

      await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => StorageAccessProbeResult.fileNotFound,
          bookImportService: service,
          pickSingleBookFile: _FakeSingleBookFilePicker(
              (uri: newUri, displayName: 'book.epub')).call);
      await _pumpUntil(
          tester, () => find.byKey(relinkButton).evaluate().isNotEmpty);

      await tester.tap(find.byKey(relinkButton));
      await _pumpUntil(tester, () => cacheCalls.length == 2);

      expect(service.relinkCalls.single.bookId, 'b_probe');
      expect(service.relinkCalls.single.newUri, newUri);
      expect(service.relinkCalls.single.displayName, 'book.epub');
      expect(cacheCalls.last, localCopy);
    });

    testWidgets('重新開書後再次卡住時，30 秒開書逾時仍會觸發', (tester) async {
      _overrideCacheBookForServing(failPaths: {oldUri}, hangPaths: {newUri});
      final service = FakeBookImportService()
        ..relinkResult = BookRelinkSuccess(_relinkTestBook(filePath: newUri));

      await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => StorageAccessProbeResult.permissionRevoked,
          bookImportService: service,
          pickSingleBookFile: _FakeSingleBookFilePicker(
              (uri: newUri, displayName: 'book.epub')).call);
      await _pumpUntil(
          tester, () => find.byKey(relinkButton).evaluate().isNotEmpty);
      await tester.tap(find.byKey(relinkButton));
      await tester.pump();
      await tester.pump();

      await tester.pump(const Duration(seconds: 29));
      expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(errorText(tester), '開書逾時，可能是系統 WebView 版本過舊或檔案異常');
      expect(find.byKey(relinkButton), findsNothing);
    });

    testWidgets('重新開書後再次失敗：重新探測一次並再次顯示按鈕（Review Focus 2）',
        (tester) async {
      _overrideCacheBookForServing(failPaths: {oldUri, newUri});
      final service = FakeBookImportService()
        ..relinkResult = BookRelinkSuccess(_relinkTestBook(filePath: newUri));

      final probeCalls = await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => StorageAccessProbeResult.permissionRevoked,
          bookImportService: service,
          pickSingleBookFile: _FakeSingleBookFilePicker(
              (uri: newUri, displayName: 'book.epub')).call);
      await _pumpUntil(
          tester, () => find.byKey(relinkButton).evaluate().isNotEmpty);
      await tester.tap(find.byKey(relinkButton));
      await _pumpUntil(tester, () => probeCalls() == 2);
      await _pumpUntil(
          tester, () => find.byKey(relinkButton).evaluate().isNotEmpty);

      expect(probeCalls(), 2);
      expect(find.byKey(relinkButton), findsOneWidget);
    });

    testWidgets('處理中按鈕停用並顯示進度，結束後恢復', (tester) async {
      final service = FakeBookImportService()
        ..relinkCompleter = Completer<BookRelinkResult>();
      await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => StorageAccessProbeResult.permissionRevoked,
          bookImportService: service,
          pickSingleBookFile: _FakeSingleBookFilePicker(
              (uri: newUri, displayName: 'book.epub')).call);
      await failAndShowError(tester);

      await tester.tap(find.byKey(relinkButton));
      await tester.pump();

      expect(
          tester.widget<OutlinedButton>(find.byKey(relinkButton)).onPressed,
          isNull);
      expect(find.byKey(relinkProgress), findsOneWidget);

      service.relinkCompleter!
          .complete(const BookRelinkFailure(BookRelinkFailureReason.failed));
      await tester.pump();
      await tester.pump();

      expect(
          tester.widget<OutlinedButton>(find.byKey(relinkButton)).onPressed,
          isNotNull);
      expect(find.byKey(relinkProgress), findsNothing);
    });

    testWidgets('快速連點兩次只開一次選擇器（Review Focus 1）', (tester) async {
      final picker =
          _FakeSingleBookFilePicker((uri: newUri, displayName: 'book.epub'))
            ..pending = Completer();
      await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => StorageAccessProbeResult.permissionRevoked,
          bookImportService: FakeBookImportService(),
          pickSingleBookFile: picker.call);
      await failAndShowError(tester);

      await tester.tap(find.byKey(relinkButton));
      await tester.pump();
      await tester.tap(find.byKey(relinkButton), warnIfMissed: false);
      await tester.pump();

      expect(picker.calls, hasLength(1));
    });

    testWidgets('選擇器取消：不顯示 SnackBar、不呼叫 relinkBook、按鈕恢復可用、'
        '錯誤視圖維持原樣', (tester) async {
      final repository = FakeLibraryRepository(
          initialBooks: [_relinkTestBook(filePath: oldUri)]);
      final service = FakeBookImportService();
      await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => StorageAccessProbeResult.fileNotFound,
          bookImportService: service,
          pickSingleBookFile: _FakeSingleBookFilePicker(null).call);
      await failAndShowError(tester);

      await tester.tap(find.byKey(relinkButton));
      await tester.pump();
      await tester.pump();

      expect(service.relinkCalls, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(
          tester.widget<OutlinedButton>(find.byKey(relinkButton)).onPressed,
          isNotNull);
      expect(errorText(tester),
          '找不到原始檔案，可能已被移動、改名或刪除。請先確認檔案仍在裝置中，再重新選取。');
      expect((await repository.findBookById('b_probe'))!.filePath, oldUri);
    });

    for (final entry in {
      BookRelinkFailureReason.formatMismatch: '選取的檔案格式與原書不同',
      BookRelinkFailureReason.contentMismatch: '選取的檔案與原書內容不同，請選取同一本書',
      BookRelinkFailureReason.alreadyInLibrary: '這個檔案已經是書庫中的另一本書',
      BookRelinkFailureReason.failed: '重新連結失敗，請再試一次',
    }.entries) {
      testWidgets('${entry.key}：錯誤視圖維持原樣並顯示對應 SnackBar，記錄不變',
          (tester) async {
        final repository = FakeLibraryRepository(
            initialBooks: [_relinkTestBook(filePath: oldUri)]);
        final cacheCalls = _overrideCacheBookForServing();
        final service = FakeBookImportService()
          ..relinkResult = BookRelinkFailure(entry.key);
        await _pumpContentUriReader(tester,
            prefsManager: prefsManager,
            probe: (_) async => StorageAccessProbeResult.permissionRevoked,
            bookImportService: service,
            pickSingleBookFile: _FakeSingleBookFilePicker(
                (uri: newUri, displayName: 'book.epub')).call);
        await failAndShowError(tester);
        final cacheCallsBefore = cacheCalls.length;

        await tester.tap(find.byKey(relinkButton));
        await tester.pump();
        await tester.pump();

        expect(find.text(entry.value), findsOneWidget);
        expect(errorText(tester), 'App 對這個檔案的存取權限已失效，請重新選取檔案。');
        expect(find.byKey(relinkButton), findsOneWidget);
        expect(cacheCalls.length, cacheCallsBefore, reason: '失敗時不可重新開書');
        expect((await repository.findBookById('b_probe'))!.filePath, oldUri);
      });
    }

    testWidgets('relinkBook 拋出例外：視為 failed，顯示 SnackBar 且按鈕恢復可用'
        '（Review Focus 4）', (tester) async {
      final service = FakeBookImportService()..relinkError = StateError('爆掉');
      await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => StorageAccessProbeResult.permissionRevoked,
          bookImportService: service,
          pickSingleBookFile: _FakeSingleBookFilePicker(
              (uri: newUri, displayName: 'book.epub')).call);
      await failAndShowError(tester);

      await tester.tap(find.byKey(relinkButton));
      await tester.pump();
      await tester.pump();

      expect(find.text('重新連結失敗，請再試一次'), findsOneWidget);
      expect(
          tester.widget<OutlinedButton>(find.byKey(relinkButton)).onPressed,
          isNotNull);
    });

    testWidgets('Re-link 處理中離開閱讀器，結果回來後不拋例外（Review Focus 3）',
        (tester) async {
      final service = FakeBookImportService()
        ..relinkCompleter = Completer<BookRelinkResult>();
      await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => StorageAccessProbeResult.permissionRevoked,
          bookImportService: service,
          pickSingleBookFile: _FakeSingleBookFilePicker(
              (uri: newUri, displayName: 'book.epub')).call);
      await failAndShowError(tester);
      await tester.tap(find.byKey(relinkButton));
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      service.relinkCompleter!
          .complete(BookRelinkSuccess(_relinkTestBook(filePath: newUri)));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('選檔期間離開閱讀器：選擇器回傳後不呼叫 relinkBook、不拋例外'
        '（計畫審查 M-4）', (tester) async {
      final service = FakeBookImportService();
      final picker =
          _FakeSingleBookFilePicker((uri: newUri, displayName: 'book.epub'))
            ..pending = Completer();
      await _pumpContentUriReader(tester,
          prefsManager: prefsManager,
          probe: (_) async => StorageAccessProbeResult.permissionRevoked,
          bookImportService: service,
          pickSingleBookFile: picker.call);
      await failAndShowError(tester);
      await tester.tap(find.byKey(relinkButton));
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      picker.pending!.complete((uri: newUri, displayName: 'book.epub'));
      await tester.pump();

      expect(service.relinkCalls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
```

- [x] **Step 4：執行測試，確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "重新選取檔案"`
Expected: 編譯錯誤，`No named parameter with the name 'pickSingleBookFile'`。

- [x] **Step 5：實作**

**5a. import。** `reader_screen.dart` 在 `import 'note_edit_dialog.dart';` 之前新增：

```dart
import 'support/book_import_picker_helper.dart'
    show SingleBookFilePicker, pickSingleBookFileViaFilePicker;
```

（`BookRelinkResult` 等型別來自既有的 `import '../library/book_import_service.dart';`。）

**5b. 建構參數。** 在 `final BookImportService? bookImportService;` 之後新增：

```dart
  /// epic-15-storage-permission Issue 2：「重新選取檔案」使用的單檔選擇器；
  /// `null` 時使用 [pickSingleBookFileViaFilePicker]。供 widget test 注入，
  /// 不必觸碰平台實作。
  final SingleBookFilePicker? pickSingleBookFile;
```

建構子參數列在 `this.bookImportService,` 之後新增 `this.pickSingleBookFile,`。

**5c. State 欄位。** 刪除 `_activeFilePath` 上方這兩行（Issue 0 的暫時性 lint 豁免）：

```dart
  // Issue 2 會在 Re-link 成功時重新賦值，本 Issue 暫無寫入點，故保留非 final。
  // ignore: prefer_final_fields
```

在 `bool _isProbingAccess = false;` 之後新增：

```dart
  /// epic-15-storage-permission Issue 2：「重新選取檔案」處理中（從按下按鈕
  /// 到 relinkBook 回傳為止）。期間按鈕停用並顯示進度，避免大檔案計算
  /// 指紋時使用者重複開啟選擇器或平行發動多次 Re-link。
  bool _isRelinking = false;
```

**5d. 重新連結流程。** 在 `_handleOpenBookTimeout` 方法之後新增：

```dart
  /// epic-15-storage-permission Issue 2：「重新選取檔案」按鈕的處理函式。
  /// 取消選檔時什麼都不做（不顯示 SnackBar）；成功時原地重新開書；失敗時
  /// 以 SnackBar 說明原因，錯誤視圖維持原樣可再試一次。
  Future<void> _handleRelinkPressed() async {
    if (_isRelinking) return;
    setState(() => _isRelinking = true);
    final BookRelinkResult? result;
    try {
      result = await _pickAndRelink();
    } finally {
      if (mounted) setState(() => _isRelinking = false);
    }
    if (!mounted || result == null) return;
    switch (result) {
      case BookRelinkSuccess(:final updatedBook):
        _reopenWithFilePath(updatedBook.filePath);
      case BookRelinkFailure(:final reason):
        final l10n = AppLocalizations.of(context)!;
        final message = switch (reason) {
          BookRelinkFailureReason.formatMismatch =>
            l10n.readerStorageRelinkFormatMismatch,
          BookRelinkFailureReason.contentMismatch =>
            l10n.readerStorageRelinkContentMismatch,
          BookRelinkFailureReason.alreadyInLibrary =>
            l10n.readerStorageRelinkAlreadyInLibrary,
          BookRelinkFailureReason.failed => l10n.readerStorageRelinkFailed,
        };
        // 先收掉上一則：連續選錯檔案時，新結果不必排在前一則（預設 4 秒）
        // 之後才出現，否則使用者會以為第二次嘗試沒有反應（計畫審查 M-1）。
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// 開啟單檔選擇器（副檔名限定為原書格式）並呼叫 relinkBook。使用者取消
  /// 時回傳 null。保證不拋出例外：選擇器或服務的任何例外都視為 failed，
  /// 否則按鈕狀態雖會在 finally 恢復，使用者卻得不到任何回饋。
  Future<BookRelinkResult?> _pickAndRelink() async {
    final importService = widget.bookImportService;
    if (importService == null) return null;
    try {
      final picker = widget.pickSingleBookFile ?? pickSingleBookFileViaFilePicker;
      // 只有 EPUB／PDF／AZW3 會走到這裡，BookFormat 名稱即副檔名。
      final picked = await picker([detectBookFormat(_activeFilePath).name]);
      // 選檔期間使用者可能已離開閱讀器：不再發動 relinkBook，避免白做
      // 整檔 SHA-256 與持久化授權（計畫審查 M-4）。
      if (!mounted || picked == null) return null;
      return await importService.relinkBook(
        widget.bookId,
        picked.uri,
        displayName: picked.displayName,
      );
    } catch (_) {
      return const BookRelinkFailure(BookRelinkFailureReason.failed);
    }
  }

  /// epic-15-storage-permission Issue 2：Re-link 成功後以 [filePath] 在同一個
  /// 畫面重新開書（spec.md「重新開書的復位清單」）。閱讀視圖維持原本的
  /// GlobalKey：錯誤視圖已把它整個移出樹，回到載入中時一定會建立新實例，
  /// 以新路徑重新走一次快取與開書流程。偏好設定、閱讀位置、字型以
  /// bookId 載入，Re-link 不改 bookId，不需要重跑。
  void _reopenWithFilePath(String filePath) {
    setState(() {
      _activeFilePath = filePath;
      _state = _RenderState.loading;
      _errorMessage = null;
      _probeResult = null;
      _openBookTimeoutTimer?.cancel();
      _openBookTimeoutTimer = Timer(
        const Duration(seconds: 30),
        _handleOpenBookTimeout,
      );
    });
    // EPUB 版面偵測若在失敗前尚未完成（仍是 null），以新路徑重新觸發一次，
    // 否則 _buildBody 的 gating 條件會讓閱讀視圖永遠停在等待。
    if (_dispatchedIsFixedLayout == null &&
        detectBookFormat(filePath) == BookFormat.epub) {
      _resolveEpubEngineDispatch();
    }
  }
```

**5e. 錯誤視圖加按鈕。** `_buildBody` 錯誤分支中，把 Issue 1 的：

```dart
          Center(
            // epic-15-storage-permission Issue 1：新的分類說明是多行長文字
            // （英文約 140 字元），加上水平間距並置中，避免貼齊螢幕兩側
            // （審查 M-1）。
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                // 依存取探測結果分流。
                switch (_probeResult) {
                  StorageAccessProbeResult.permissionRevoked =>
                    l10n.readerStoragePermissionRevokedMessage,
                  StorageAccessProbeResult.fileNotFound =>
                    l10n.readerStorageFileNotFoundMessage,
                  _ => _errorMessage ?? l10n.readerFailedToLoadBookMessage,
                },
                key: const Key('reader_error_text'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
```

改成：

```dart
          Center(
            // epic-15-storage-permission Issue 1：新的分類說明是多行長文字
            // （英文約 140 字元），加上水平間距並置中，避免貼齊螢幕兩側
            // （審查 M-1）。
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    // 依存取探測結果分流。
                    switch (_probeResult) {
                      StorageAccessProbeResult.permissionRevoked =>
                        l10n.readerStoragePermissionRevokedMessage,
                      StorageAccessProbeResult.fileNotFound =>
                        l10n.readerStorageFileNotFoundMessage,
                      _ => _errorMessage ?? l10n.readerFailedToLoadBookMessage,
                    },
                    key: const Key('reader_error_text'),
                    textAlign: TextAlign.center,
                  ),
                  // epic-15-storage-permission Issue 2：權限失效／找不到檔案
                  // 且有匯入服務時才提供重新選取。用 OutlinedButton：E-Ink
                  // 高對比模式只有黑白兩色，純填色或純文字按鈕的輪廓容易和
                  // 背景融在一起。
                  if (widget.bookImportService != null &&
                      (_probeResult ==
                              StorageAccessProbeResult.permissionRevoked ||
                          _probeResult ==
                              StorageAccessProbeResult.fileNotFound)) ...[
                    const SizedBox(height: 24),
                    OutlinedButton(
                      key: const Key('reader_storage_relink_button'),
                      onPressed: _isRelinking ? null : _handleRelinkPressed,
                      child: _isRelinking
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                key: Key('reader_storage_relink_progress'),
                                strokeWidth: 2,
                              ),
                            )
                          : Text(l10n.readerStorageRelinkButton),
                    ),
                  ],
                ],
              ),
            ),
          ),
```

- [x] **Step 6：執行測試，確認通過**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "重新選取檔案"`
Expected: 21 個測試全部通過（顯示條件 5 個、M-1／M-2 各 1 個、流程 14 個）。

Run: `flutter test test/screens/reader_screen_test.dart test/screens/reader_screen_route_test.dart`
Expected: All tests passed。Issue 1 的「開書失敗的存取探測」group（錯誤文字外包一層 `Column` 不影響 `Key('reader_error_text')` 的查找）與其他既有案例都不受影響。

Run: `flutter analyze`
Expected: `No issues found!`（確認移除 `// ignore: prefer_final_fields` 後沒有新警告）。

Run: `node tool/check_l10n_hardcoded_strings.js`
Expected: 沒有新增違規。

- [x] **Step 7：Commit**

```bash
git add lib/screens/reader_screen.dart lib/screens/support/book_import_picker_helper.dart test/screens/reader_screen_test.dart lib/l10n/
git commit -m "feat(reader): 錯誤畫面重新選取檔案並原地重新開書（epic-15 Issue 2）"
```

---

### Task 3：真機驗證（需要真人操作）

**Files:** 無程式改動；結果記錄在 `docs/epics/epic-15-storage-permission/epic.md`。

這個 Task 需要實體 Android 裝置，以及用檔案管理員手動操作。執行者若是 agent，完成 Step 1 後就停下來，把 Step 2～5 交給人類操作，並回報在哪裡等待。

> **2026-09-29 更正**：原本的步驟要求「在系統設定清除 App 的檔案存取授權，或以 adb 撤銷授權」，但這個前提是錯的。App 讀書靠的是 SAF 持久化 URI 授權（使用者在系統選檔器選資料夾或檔案時核發），不是安裝時要求的權限：它不會出現在系統設定的權限頁面，在沒有 root 的裝置上也沒有撤銷手段。所以改用「搬移原始檔案」觸發 `fileNotFound`。這條路和 `permissionRevoked` 顯示的是同一個按鈕、後面走同一條重新連結流程，差別只在錯誤說明文字，而錯誤說明的分流已由 widget test 驗證。

- [x] **Step 1：安裝 debug 版**

Run: `flutter devices`，確認裝置 ID 後執行 `flutter run -d <device-id>`。

- [x] **Step 2：準備書籍並搬走原始檔案（人類）**

- 以「匯入資料夾」匯入一本 EPUB（例如放在 `Download/TEST/`），讀到中間某頁，加一條劃線、一個書籤，返回書架。
- 用檔案管理員把這本 EPUB **搬移**到另一個資料夾（例如 `Download/`），不要刪除。
- 開書，確認出現「找不到原始檔案…」說明與「重新選取檔案」按鈕。

- [x] **Step 3：選錯檔案（人類）**

按下按鈕，改選另一本 EPUB。預期：SnackBar 顯示「選取的檔案與原書內容不同，請選取同一本書」，錯誤畫面維持原樣。

- [x] **Step 4：選對檔案、返回書架、重開 App（人類）**

- 再按一次按鈕，到新位置選原本那本。預期：直接開書，停在原本讀到的位置，劃線、書籤都還在。
- 返回書架。預期：這本書仍在原分類，封面、書名不變。
- 關掉 App 再重開，開同一本書。預期：可以正常開啟，代表新授權已持久化。

- [x] **Step 5：記錄結果**

在 `epic.md` 新增「Issue 2 真機驗證」段落，記錄實際執行的情境與結果。任何一項不符預期，如實記錄並回報，不要逕自修改範圍外的程式碼。

---

### Task 4：完整測試與進度文件

- [x] **Step 1：完整測試**

Run: `flutter test`
Expected: All tests passed。若有失敗，先單獨重跑該檔案，確認是不是本 Issue 造成的；和本 Issue 無關的失敗要如實記錄在 `epic.md`，不要為了讓它通過而修改範圍外的程式碼。

Run: `flutter analyze`
Expected: `No issues found!`

Run: `node tool/check_l10n_hardcoded_strings.js`
Expected: 通過。

- [x] **Step 2：更新進度文件**

- `docs/epics/epic-15-storage-permission/issues.md`：Issue 2 的 `**Status:** ready-for-agent` 改為 `**Status:** completed`。
- `docs/epics/epic-15-storage-permission/epic.md`：在「目前狀態」之前新增「Issue 2 完成記錄」，內容包含 commit 清單、完整 `flutter test` 結果與執行時的 commit、真機驗證摘要（未執行就如實寫「待補」）。把「目前狀態」改為反映 Issue 2 完成、待 PR 合併。
- `docs/epics.md`：epic-15 備註改為 `Issue 2 已完成`。

```bash
git add ../docs/epics/epic-15-storage-permission/issues.md ../docs/epics/epic-15-storage-permission/epic.md ../docs/epics.md
git commit -m "docs(epic-15): 記錄 Issue 2 完成"
```
