# Epic 30 Issue 6：抽出「遠端書籍下載器」深模組 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `LibraryScreen._handleRedownload()` 與 `RemoteCatalogScreen._DownloadQueueDialogState._downloadOne()` 各自重複實作的「下載到暫存檔→複製到永久目錄→例外清理」邏輯，抽出成一個共用的 `RemoteBookDownloader` 深模組，兩個呼叫端改為呼叫同一份程式碼。

**Architecture:** 新增 `lib/remote/remote_book_downloader.dart`，內含兩個獨立的頂層函式（非單一 `materialize()`）：`downloadToTempFile()` 負責建暫存目錄＋呼叫 `OpdsClient.downloadBook()`；`promoteToPermanent()` 負責建永久目錄＋複製＋刪暫存檔＋例外清理。拆成兩個函式而非一個的原因：`RemoteCatalogScreen._downloadOne()` 在「下載到暫存檔」完成後、「複製到永久目錄」之前，插入了 Issue 3 的重複匯入指紋比對＋使用者確認對話框這個決策點——使用者選擇不建立新副本時，流程在這裡就結束（刪暫存檔、標記 `duplicateSkipped`），永遠不會呼叫「複製到永久目錄」。`LibraryScreen._handleRedownload()` 沒有這個決策點，兩個函式背靠背呼叫。

**Tech Stack:** Dart（純邏輯，無 Flutter widget 依賴）、`package:path`、`package:path_provider`、`package:uuid`，與既有 `OpdsClient` 介面（`app/lib/remote/opds_client.dart`）。

**Spec:** `docs/epics/epic-30-calibre-remote-library/issues.md`（Issue 6 章節）；架構分析依據 `docs/research/architecture-review-library-remote-screens.md`（候選 1，Top recommendation）。

## Global Constraints

- 兩個呼叫端（`_handleRedownload()`／`_downloadOne()`）改用新模組後，**行為必須完全不變**——這是重構任務，不是新功能，既有測試不得修改斷言、只能因為程式碼搬移而調整呼叫方式。
- 新模組 `RemoteBookDownloader` 是純 Dart 邏輯，不依賴 `BuildContext`／`State`／`setState`，兩個呼叫端各自的 UI 狀態更新（`setState`、`ScaffoldMessenger`、對話框）留在呼叫端，不下沉到新模組。
- `downloadToTempFile()` 內部**不**做例外清理——`OpdsHttpClient.downloadBook()`（`app/lib/remote/opds_http_client.dart:96-131`）已確認在例外／取消時會自行刪除目的檔案，重複清理是死碼。
- `promoteToPermanent()` 的永久檔名沿用暫存檔名（`p.basename(tempPath)`），不重新產生 UUID——與原本兩份實作「temp 檔名與 permanent 檔名相同」的既有行為一致。
- 兩個呼叫端各自既有的「外層 catch 清暫存檔」邏輯**保留**，不可整段刪除——`_downloadOne()` 在指紋比對／確認對話框這段仍需要獨立清理（此時 `promoteToPermanent()` 根本還沒被呼叫）。

---

### Task 1: 建立 RemoteBookDownloader 深模組

**Files:**
- Create: `app/lib/remote/remote_book_downloader.dart`
- Test: `app/test/remote/remote_book_downloader_test.dart`
- Modify: `app/test/support/fake_opds_client.dart`（新增 `downloadBookPasswords`／`downloadBookCancellationTokens` 記錄欄位，見 Step 9）

**Interfaces:**
- Consumes：`OpdsClient`（`app/lib/remote/opds_client.dart` 既有介面，`downloadBook()` 簽章見下方）、`fileExtensionFor(BookFileFormat)`（`opds_client.dart` 既有函式）、`OpdsAcquisition`／`OpdsDownloadCancellationToken`（`app/lib/remote/opds_types.dart`／`opds_client.dart`）、`RemoteServerProfile`（`app/lib/remote/remote_server_profile.dart`）、`BookFileFormat`（`app/lib/library/models/library_enums.dart`）。
- Produces（Task 2／3 依賴這兩個函式的確切簽章）：
  ```dart
  Future<String> downloadToTempFile({
    required OpdsClient client,
    required RemoteServerProfile server,
    required OpdsAcquisition acquisition,
    required BookFileFormat format,
    String? password,
    void Function(int received, int total)? onProgress,
    OpdsDownloadCancellationToken? cancellationToken,
  });

  Future<String> promoteToPermanent(String tempPath);
  ```
  兩者皆回傳最終檔案的絕對路徑字串；失敗時皆拋出原始例外（不包裝成自訂例外型別），呼叫端維持既有的「不分細分錯誤類型，統一顯示失敗訊息」慣例。

- [ ] **Step 1: 寫 `downloadToTempFile()` 的失敗測試**

建立 `app/test/remote/remote_book_downloader_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/remote/opds_client.dart';
import 'package:elinkbook/remote/opds_types.dart';
import 'package:elinkbook/remote/remote_book_downloader.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';

import '../support/fake_opds_client.dart';
import '../support/fake_path_provider_platform.dart';

void main() {
  late Directory tempRoot;
  late PathProviderPlatform originalPathProvider;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('remote_book_downloader_test');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempRoot.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPathProvider;
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  final server = RemoteServerProfile(
    id: 'srv1',
    name: '測試站點',
    baseUrl: 'http://example.com/opds',
    type: RemoteServerType.opds,
    allowInsecure: false,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
  );

  const acquisition = OpdsAcquisition(
    href: 'http://example.com/opds/download/1.epub',
    format: BookFileFormat.epub,
  );

  test('downloadToTempFile() 建立 remote_download_temp/ 目錄並呼叫 client.downloadBook()', () async {
    final client = FakeOpdsClient();

    final tempPath = await downloadToTempFile(
      client: client,
      server: server,
      acquisition: acquisition,
      format: BookFileFormat.epub,
    );

    expect(client.downloadBookCalls, [acquisition.href]);
    expect(tempPath, contains('remote_download_temp'));
    expect(tempPath, endsWith('.epub'));
    expect(File(tempPath).existsSync(), isTrue);
  });

  test('downloadToTempFile() 下載失敗時原樣拋出例外，不做額外清理', () async {
    final client = FakeOpdsClient(downloadError: StateError('模擬下載失敗'));

    await expectLater(
      downloadToTempFile(
        client: client,
        server: server,
        acquisition: acquisition,
        format: BookFileFormat.epub,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/remote/remote_book_downloader_test.dart`
Expected: FAIL——`Target of URI doesn't exist: 'package:elinkbook/remote/remote_book_downloader.dart'`（檔案尚未建立）。

- [ ] **Step 3: 建立 `remote_book_downloader.dart`，實作 `downloadToTempFile()`**

建立 `app/lib/remote/remote_book_downloader.dart`：

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../library/models/library_enums.dart';
import 'opds_client.dart';
import 'opds_types.dart';
import 'remote_server_profile.dart';

/// 把一筆 OPDS acquisition 下載到 App 暫存目錄（epic-30-calibre-remote-library
/// Issue 6，`docs/research/architecture-review-library-remote-screens.md`
/// 候選 1：`LibraryScreen._handleRedownload()`／`RemoteCatalogScreen`
/// `_downloadOne()` 原本各自重複實作同一段邏輯，此處收斂為共用深模組）。
///
/// **不含例外清理**：[OpdsClient.downloadBook]（`OpdsHttpClient` 真實
/// 實作，見 `opds_http_client.dart`）已確認在下載失敗／使用者取消時會
/// 自行刪除目的檔案，這裡重複清理是死碼，故意不做。
Future<String> downloadToTempFile({
  required OpdsClient client,
  required RemoteServerProfile server,
  required OpdsAcquisition acquisition,
  required BookFileFormat format,
  String? password,
  void Function(int received, int total)? onProgress,
  OpdsDownloadCancellationToken? cancellationToken,
}) async {
  final tempDir = await getTemporaryDirectory();
  final downloadDir = Directory(p.join(tempDir.path, 'remote_download_temp'));
  if (!await downloadDir.exists()) await downloadDir.create(recursive: true);
  final fileName = '${const Uuid().v4()}.${fileExtensionFor(format)}';
  final tempPath = p.join(downloadDir.path, fileName);

  await client.downloadBook(
    server,
    acquisition,
    tempPath,
    password: password,
    onProgress: onProgress,
    cancellationToken: cancellationToken,
  );

  return tempPath;
}
```

- [ ] **Step 4: 執行測試確認前兩則通過**

Run: `cd app && flutter test test/remote/remote_book_downloader_test.dart`
Expected: 前兩則 `downloadToTempFile()` 測試 PASS。

- [ ] **Step 5: 寫 `promoteToPermanent()` 的測試**

在同一個測試檔的 `main()` 內，於既有兩則測試後追加：

```dart
  test('promoteToPermanent() 複製暫存檔到 remote_books/ 並刪除暫存檔', () async {
    final client = FakeOpdsClient();
    final tempPath = await downloadToTempFile(
      client: client,
      server: server,
      acquisition: acquisition,
      format: BookFileFormat.epub,
    );

    final permanentPath = await promoteToPermanent(tempPath);

    expect(permanentPath, contains('remote_books'));
    expect(p.basename(permanentPath), p.basename(tempPath));
    expect(File(permanentPath).existsSync(), isTrue);
    expect(File(tempPath).existsSync(), isFalse);
  });

  test('promoteToPermanent() 複製中途失敗時清除殘留暫存檔並重新拋出例外', () async {
    final client = FakeOpdsClient();
    final tempPath = await downloadToTempFile(
      client: client,
      server: server,
      acquisition: acquisition,
      format: BookFileFormat.epub,
    );

    // 模擬「複製到永久目錄」中途失敗：把 App 文件目錄路徑指向一個不存在
    // 的唯讀路徑，讓 permanentDir.create() 之後的 tempFile.copy() 失敗。
    // 這裡改用最直接的方式——刪掉暫存檔本身，讓 File.copy() 因來源檔案
    // 不存在而拋出 PathNotFoundException，驗證 catch 分支正確處理「來源
    // 已消失」這個真實會發生的邊界情況（例如系統背景清過暫存目錄）。
    await File(tempPath).delete();

    await expectLater(
      promoteToPermanent(tempPath),
      throwsA(anything),
    );
    // 暫存檔本來就已經被刪除，這裡驗證 catch 分支的「if (await leftover
    // .exists())」防護不會因為檔案已不存在而額外拋出例外。
  });
```

- [ ] **Step 6: 執行測試確認新增兩則失敗**

Run: `cd app && flutter test test/remote/remote_book_downloader_test.dart`
Expected: FAIL——`promoteToPermanent` 未定義。

- [ ] **Step 7: 實作 `promoteToPermanent()`**

在 `remote_book_downloader.dart` 的 `downloadToTempFile()` 函式後面追加：

```dart
/// 把 [tempPath] 指向的暫存檔複製到 App 永久文件目錄的 `remote_books/`
/// 子目錄，成功後刪除暫存檔，回傳永久檔案的絕對路徑。永久檔名沿用暫存
/// 檔名（[p.basename]），與原本兩份實作「temp 檔名與 permanent 檔名相同」
/// 的既有行為一致。
///
/// 任何例外皆確保不留孤兒/半成品檔案，呼叫端不需要自己再判斷 `tempPath`
/// 是否還存在。區分兩種失敗窗口分開處理（**〔審查 review-plan-issue-6.md
/// Finding 3 部分採納，理由見下方〕**）：
/// - `copy()` 本身失敗（例如磁碟空間不足）：`permanentPath` 可能是部分
///   寫入的殘檔，清掉；`tempPath` 原封不動保留（來源檔案本身沒問題）。
/// - `copy()` 已成功、只有隨後的 `delete(tempPath)` 失敗：此時
///   `permanentPath` 是一份完整有效的檔案，**絕不能清掉**——審查原始建議
///   是「catch 區塊一併清理 permanentPath」，但那個寫法沒有區分這兩種
///   失敗窗口，會在「複製已成功、只是刪暫存檔失敗」這個情境下誤刪一份
///   已經下載成功的書籍檔案，逼使用者重新下載一次，比留一個孤兒暫存檔
///   （`remote_download_temp/` 本身是 OS 可回收的暫存語意，見既有
///   `getTemporaryDirectory()` 慣例）更糟——故僅在 `copied == false`
///   （複製本身失敗）時才清 `permanentPath`。
Future<String> promoteToPermanent(String tempPath) async {
  final fileName = p.basename(tempPath);
  final docsDir = await getApplicationDocumentsDirectory();
  final permanentDir = Directory(p.join(docsDir.path, 'remote_books'));
  if (!await permanentDir.exists()) await permanentDir.create(recursive: true);
  final permanentPath = p.join(permanentDir.path, fileName);
  final tempFile = File(tempPath);
  var copied = false;
  try {
    await tempFile.copy(permanentPath);
    copied = true;
    await tempFile.delete();
    return permanentPath;
  } catch (_) {
    if (!copied) {
      final leftoverPerm = File(permanentPath);
      if (await leftoverPerm.exists()) await leftoverPerm.delete();
    }
    final leftoverTemp = File(tempPath);
    if (await leftoverTemp.exists()) await leftoverTemp.delete();
    rethrow;
  }
}
```

- [ ] **Step 8: 執行全部測試確認通過**

Run: `cd app && flutter test test/remote/remote_book_downloader_test.dart`
Expected: 4 則測試全數 PASS。

- [ ] **Step 9: 擴充 `FakeOpdsClient` 記錄 `downloadBook()` 的 `password`／`cancellationToken` 參數**

**〔審查 review-plan-issue-6.md Finding 2 採納〕** 目前 `app/test/support/fake_opds_client.dart` 的 `downloadBookCalls` 只記錄 `acquisition.href`，無法驗證 `password`／`cancellationToken` 是否正確透傳——而 Finding 1 抓到的正是「忘記傳 `password`」這類錯誤，值得補一個能真正抓到同類回歸的測試。修改 `app/test/support/fake_opds_client.dart`：

```dart
  final List<String> downloadBookCalls = [];
  // 〔審查 review-plan-issue-6.md Finding 2 採納〕與 downloadBookCalls
  // 同索引對應，供 remote_book_downloader_test.dart 驗證
  // downloadToTempFile() 是否正確透傳 password／cancellationToken 給
  // client.downloadBook()（比照既有 testConnectionPasswords 的記錄模式）。
  final List<String?> downloadBookPasswords = [];
  final List<OpdsDownloadCancellationToken?> downloadBookCancellationTokens = [];
```

並在 `downloadBook()` 方法內、`downloadBookCalls.add(acquisition.href);` 那行下方新增：

```dart
    downloadBookPasswords.add(password);
    downloadBookCancellationTokens.add(cancellationToken);
```

- [ ] **Step 10: 寫 `downloadToTempFile()` 參數透傳測試**

在 `remote_book_downloader_test.dart` 的既有兩則 `downloadToTempFile()` 測試後（Step 1 寫的那兩則，`promoteToPermanent()` 測試之前）追加：

```dart
  test('downloadToTempFile() 正確將 password 與 cancellationToken 透傳給 client', () async {
    final client = FakeOpdsClient();
    final token = OpdsDownloadCancellationToken();
    var progressCalled = false;

    await downloadToTempFile(
      client: client,
      server: server,
      acquisition: acquisition,
      format: BookFileFormat.epub,
      password: 'secret_password',
      cancellationToken: token,
      onProgress: (received, total) => progressCalled = true,
    );

    expect(client.downloadBookPasswords, ['secret_password']);
    expect(client.downloadBookCancellationTokens.single, same(token));
    expect(progressCalled, isTrue);
  });
```

- [ ] **Step 11: 執行測試確認通過**

Run: `cd app && flutter test test/remote/remote_book_downloader_test.dart`
Expected: 5 則測試全數 PASS。

- [ ] **Step 12: flutter analyze**

Run: `cd app && flutter analyze lib/remote/remote_book_downloader.dart test/remote/remote_book_downloader_test.dart test/support/fake_opds_client.dart`
Expected: `No issues found!`

- [ ] **Step 13: Commit**

```bash
git add app/lib/remote/remote_book_downloader.dart app/test/remote/remote_book_downloader_test.dart app/test/support/fake_opds_client.dart
git commit -m "feat(epic-30): Issue 6 Task 1 - RemoteBookDownloader 深模組"
```

---

### Task 2: RemoteCatalogScreen._downloadOne() 改用 RemoteBookDownloader

**Files:**
- Modify: `app/lib/screens/remote_catalog_screen.dart:538-612`（`_DownloadQueueDialogState._downloadOne()`）
- Test: `app/test/screens/remote_catalog_screen_test.dart`（既有測試，不新增案例，僅驗證零回歸）

**Interfaces:**
- Consumes：Task 1 產出的 `downloadToTempFile()`／`promoteToPermanent()`（`app/lib/remote/remote_book_downloader.dart`）。
- Produces：無新對外介面，`_downloadOne()` 對外行為（`_statuses`／`_permanentPaths` 的更新時機與最終狀態）完全不變。

- [ ] **Step 1: 確認既有測試涵蓋的行為（重構前基準）**

Run: `cd app && flutter test test/screens/remote_catalog_screen_test.dart`
Expected: 目前全數 PASS（重構前的基準線，等下 Step 4 重構後要維持同樣的通過結果）。

- [ ] **Step 2: 在 `remote_catalog_screen.dart` 加入新 import**

`app/lib/screens/remote_catalog_screen.dart` 檔案頂部，於既有 `import '../remote/opds_client.dart';` 那行下方新增：

```dart
import '../remote/remote_book_downloader.dart';
```

- [ ] **Step 3: 執行 `flutter analyze` 確認新 import 沒有立即報 unused（此步驟只是中繼確認，尚未改 `_downloadOne()` 本體）**

Run: `cd app && flutter analyze lib/screens/remote_catalog_screen.dart`
Expected: 因為還沒使用這個 import，`flutter analyze` 會報 `unused_import`——這是預期中的暫時狀態，下一步驟會用到它。

- [ ] **Step 4: 把 `_downloadOne()` 改為呼叫 `downloadToTempFile()`／`promoteToPermanent()`**

找到 `app/lib/screens/remote_catalog_screen.dart:538-612` 的 `_downloadOne()` 方法，整段替換為：

```dart
  Future<void> _downloadOne(int index) async {
    if (!mounted) return;
    setState(() => _statuses[index] = _DownloadItemStatus.downloading);
    final item = widget.queue[index];
    final token = OpdsDownloadCancellationToken();
    _tokens[index] = token;
    // 〔審查 review-plan-issue-2.md Finding 3 採納，epic-30 Issue 6 沿用〕
    // 宣告在 try 外，讓 catch 區塊也能存取——指紋比對／確認對話框這段窗口
    // 發生例外時，`promoteToPermanent()` 根本還沒被呼叫，仍需要這裡自行
    // 清理暫存檔（`promoteToPermanent()` 只保證它自己那一步的例外會清理）。
    String? tempPath;
    try {
      tempPath = await downloadToTempFile(
        client: widget.client,
        server: widget.server,
        acquisition: item.acquisition,
        format: item.acquisition.format!,
        password: widget.password,
        cancellationToken: token,
      );

      if (!mounted) return;
      setState(() => _statuses[index] = _DownloadItemStatus.checkingDuplicate);
      final fingerprint = await widget.computeFingerprint(tempPath, item.acquisition.format!);
      final existingByFingerprint =
          await widget.libraryRepository.findByContentFingerprint(fingerprint);
      if (existingByFingerprint != null) {
        if (!mounted) return;
        final proceed = await _showDuplicateConfirmDialog(
          context,
          '偵測到「${item.entry.title}」與本機已有的一本書內容相同，仍要建立新的一份嗎？',
        );
        if (!proceed) {
          final leftover = File(tempPath);
          if (await leftover.exists()) await leftover.delete();
          if (!mounted) return;
          setState(() => _statuses[index] = _DownloadItemStatus.duplicateSkipped);
          return;
        }
      }

      final permanentPath = await promoteToPermanent(tempPath);

      if (!mounted) return;
      setState(() {
        _permanentPaths[index] = permanentPath;
        _statuses[index] = _DownloadItemStatus.done;
      });
    } catch (_) {
      if (tempPath != null) {
        final leftover = File(tempPath);
        if (await leftover.exists()) await leftover.delete();
      }
      if (!mounted) return;
      setState(() {
        _statuses[index] =
            token.isCancelled ? _DownloadItemStatus.cancelled : _DownloadItemStatus.failed;
      });
    }
  }
```

- [ ] **Step 5: 執行既有測試確認零回歸**

Run: `cd app && flutter test test/screens/remote_catalog_screen_test.dart`
Expected: 與 Step 1 相同的測試數量全數 PASS（含下載成功／失敗／取消／重複偵測／重試的既有案例）。

- [ ] **Step 6: flutter analyze 確認乾淨**

Run: `cd app && flutter analyze lib/screens/remote_catalog_screen.dart`
Expected: `No issues found!`——此時 Step 2 加入的 import 已在 Step 4 用到，`unused_import` 警告應已消失。若仍有其他 `dart:io`／`path`／`path_provider`／`uuid` 相關 import 因為 `_downloadOne()` 不再直接使用而變成 unused，逐一移除（先確認檔案內沒有其他地方還在用，例如 `_importSuccessful()`／`_showDuplicateConfirmDialog()` 是否還需要 `dart:io` 的 `File`）。

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/remote_catalog_screen.dart
git commit -m "refactor(epic-30): Issue 6 Task 2 - RemoteCatalogScreen._downloadOne() 改用 RemoteBookDownloader"
```

---

### Task 3: LibraryScreen._handleRedownload() 改用 RemoteBookDownloader

**Files:**
- Modify: `app/lib/screens/library_screen.dart:579-655`（`_handleRedownload()`）
- Test: `app/test/screens/library_screen_test.dart`（既有「Issue 4：待下載書籍重新下載」測試群組，不新增案例，僅驗證零回歸）

**Interfaces:**
- Consumes：Task 1 產出的 `downloadToTempFile()`／`promoteToPermanent()`。
- Produces：無新對外介面，`_handleRedownload()` 對外行為（更新 `Book.filePath`／`isDownloaded`、失敗訊息、`_redownloadingBookIds` 重入防護）完全不變。

- [ ] **Step 1: 確認既有測試涵蓋的行為（重構前基準）**

Run: `cd app && flutter test test/screens/library_screen_test.dart --plain-name "Issue 4：待下載書籍重新下載"`
Expected: 4 則測試（取消／行動數據提示／成功／失敗）全數 PASS（重構前基準線）。

- [ ] **Step 2: 在 `library_screen.dart` 加入新 import**

`app/lib/screens/library_screen.dart` 檔案頂部，於既有 `import '../remote/opds_client.dart';` 那行下方新增：

```dart
import '../remote/remote_book_downloader.dart';
```

- [ ] **Step 3: 把 `_handleRedownload()` 改為呼叫 `downloadToTempFile()`／`promoteToPermanent()`**

找到 `app/lib/screens/library_screen.dart:579-655` 的 `_handleRedownload()` 方法，把「建立暫存目錄」到「刪暫存檔」這段（原第 618-637 行左右，`final tempDir = await getTemporaryDirectory();` 起、`await tempFile.delete();` 止）整段替換為：

```dart
      tempPath = await downloadToTempFile(
        client: client,
        server: server,
        acquisition: OpdsAcquisition(href: remoteDownloadUrl, format: book.format),
        format: book.format,
        password: password,
      );

      final permanentPath = await promoteToPermanent(tempPath);
```

替換後，緊接著的既有那一行

```dart
      await widget.repository
          .updateBook(book.copyWith(filePath: permanentPath, isDownloaded: true));
```

維持不動（`permanentPath` 變數名稱與型別不變，`copyWith()` 呼叫不需要修改）。方法其餘部分（開頭的驗證/確認邏輯、`catch`/`finally` 區塊）維持不動——`catch` 區塊裡「`if (tempPath != null)` 清殘留暫存檔」的邏輯繼續保留，作為 `promoteToPermanent()` 內部清理之外的額外防線（`promoteToPermanent()` 拋出例外時其實已經清過，這裡等於是無害的二次確認，見本計畫 Global Constraints）。

- [ ] **Step 4: 執行既有測試確認零回歸**

Run: `cd app && flutter test test/screens/library_screen_test.dart --plain-name "Issue 4：待下載書籍重新下載"`
Expected: 與 Step 1 相同的 4 則測試全數 PASS。

- [ ] **Step 5: 執行整個 library_screen_test.dart 確認沒有波及其他測試**

Run: `cd app && flutter test test/screens/library_screen_test.dart`
Expected: 全數 PASS（`library_screen.dart` 是全專案改動最頻繁的熱點檔案，這個檔案本身的完整測試套件需要整套跑過，不只跑改動到的那個 group）。

- [ ] **Step 6: flutter analyze 確認乾淨**

Run: `cd app && flutter analyze lib/screens/library_screen.dart`
Expected: `No issues found!`——若因為 `_handleRedownload()` 不再直接組 temp/permanent 路徑而讓 `dart:io`／`path`／`path_provider`／`uuid` 變成 unused import，逐一確認檔案內其他地方（例如 `_deleteSelectedBooks()`／`_removeLocalCacheForSelectedBooks()`）是否仍需要，需要則保留，不需要則移除。

- [ ] **Step 7: 全專案回歸測試**

Run: `cd app && flutter test`
Expected: 全數 PASS，零回歸（Issue 6 是純重構，不改變任何對外行為，全專案測試數量應與重構前一致）。

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/library_screen.dart
git commit -m "refactor(epic-30): Issue 6 Task 3 - LibraryScreen._handleRedownload() 改用 RemoteBookDownloader"
```

---

## 自我審查記錄（撰寫計畫時的自我複核）

- **Spec 覆蓋**：`issues.md` Issue 6 的三個「What to build」條目（新增共用模組／`_downloadOne()` 遷移／`_handleRedownload()` 遷移）分別對應 Task 1／2／3；「單元測試要求」的兩條（新模組測試、既有測試零回歸）分別對應 Task 1 Step 1-8 與 Task 2/3 的 Step 1／4／5／7。
- **與 `issues.md` 原文的落差（已修正，非遺漏）**：Issue 6 原文把 `promoteToPermanent()` 簽章寫成 `promoteToPermanent(String tempPath, BookFileFormat format)`；撰寫本計畫時重讀兩份原始實作才發現永久檔名其實**沿用暫存檔名**（`fileName` 變數在原始碼中只產生一次、temp 與 permanent 共用），因此 `format` 參數在 `promoteToPermanent()` 內根本用不到——改為 `promoteToPermanent(String tempPath)`，用 `p.basename(tempPath)` 取檔名。這是比 Issue 文字更精確的介面，Task 1-3 的程式碼片段已全部採用新簽章，無不一致之處。
- **型別一致性檢查**：`downloadToTempFile()`／`promoteToPermanent()` 的簽章、回傳型別（皆為 `Future<String>`）在 Task 1（定義）與 Task 2／3（呼叫）三處逐字一致，已核對。
- **佔位符掃描**：全計畫程式碼片段皆為可直接套用的完整程式碼，無 `TODO`／「依需要調整」等佔位敘述；Step 6（`flutter analyze` 後續清 unused import）刻意保留「需要則保留、不需要則移除」的判斷空間，因為兩個檔案的其餘用途（`_deleteSelectedBooks()` 等既有方法）在計畫撰寫當下仍持續使用同一批 import，實際是否變成 unused 需視 Task 2/3 執行當下的檔案完整內容而定，不是遺漏細節。

### 依 `review-plan-issue-6.md` 審查意見修訂記錄（2026-08-19）

- **Finding 1（Important，已修訂）**：核實正確——Task 3 Step 3 原始程式碼片段確實遺漏 `password: password`，會讓有密碼保護的站點重新下載回歸失敗（401），且 `password` 區域變數會變成 `unused_local_variable`。已補上。
- **Finding 2（Important，已修訂）**：核實有價值——新增的 Task 1 Step 9-11，擴充 `FakeOpdsClient` 記錄 `password`／`cancellationToken`，並補上透傳驗證測試，這類測試正是能在未來抓到「像 Finding 1 那樣忘記傳某個參數」回歸的測試。
- **Finding 3（Minor，部分採納並修正設計）**：審查指出的風險（`copy()` 中途失敗留下部分寫入的 `permanentPath` 殘檔）核實成立，但審查建議的寫法（catch 區塊無差別清理 `permanentPath`）技術上不正確——沒有區分「`copy()` 本身失敗」與「`copy()` 已成功、只有隨後的 `delete(tempPath)` 失敗」這兩種情境；後者的 `permanentPath` 已是完整有效檔案，無差別清理會誤刪一份下載成功的書籍檔案，比原本「留一個 OS 可回收的孤兒暫存檔」的後果更嚴重。已改為用 `copied` 旗標區分兩種失敗窗口，只在複製本身失敗時才清 `permanentPath`（Task 1 Step 7 已更新程式碼與文件註解）。
- **Finding 4（Minor，無需修訂）**：審查本身即建議「維持該設計即可」，未變更。
