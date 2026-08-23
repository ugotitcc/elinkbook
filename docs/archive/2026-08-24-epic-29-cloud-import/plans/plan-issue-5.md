# Epic 29 Issue 5：雲端匯入重複偵測（雙層檢查）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（建議）或 superpowers:executing-plans 逐一 Task 執行本計劃。步驟使用核取方塊（`- [ ]`）語法追蹤進度。

**Goal:** 為 Epic 29（Google Drive／OneDrive 雲端匯入）加入雙層重複匯入偵測——選檔前置檢查（比對 `cloudFileId`）與下載後指紋比對（比對 `content_fingerprint`）——兩層皆為精確比對，命中時提示使用者但不強制阻擋。

**Architecture:** 完整比照 `epic-30-calibre-remote-library` Issue 3 已審查合併、已在生產環境驗證過的 `RemoteCatalogScreen` 雙層重複偵測設計，只替換識別鍵與呼叫端型別（`remoteBookId` → `cloudFileId`、`OpdsEntry` → `CloudFileEntry`）。Layer 1（選檔前置）掛在 `CloudBrowserScreen._toggleSelection()`；Layer 2（下載後指紋比對）掛在 `CloudDownloadQueueDialog._downloadOne()`，插在既有「下載到暫存檔」與「搬移至永久位置」兩步之間。兩層共用同一個確認對話框 helper。`LibraryRepository.findByCloudFileId()`／`findByContentFingerprint()` 已由 Epic 29 Issue 0 建好，本計劃是這兩個方法的第一個消費端。

**Tech Stack:** Flutter widget test（`flutter_test`），既有 `FakeCloudStorageClient`／`FakeBookImportService`／`FakeLibraryRepository`／`FakeFingerprintComputer` 測試替身（後者定義於 `book_content_fingerprint.dart` 的 `ComputeRemoteFingerprint` typedef 之下，provider 無關、可直接沿用，不需要新型別）。

**Spec:** `docs/epics/epic-29-cloud-import/spec.md`「重複匯入偵測」章節；本計劃直接沿用的既有實作參考為 `app/lib/screens/remote_catalog_screen.dart`（`_toggleSelection`／`_DownloadQueueDialogState._downloadOne`／`_showDuplicateConfirmDialog`，`epic-30` Issue 3）。

## Global Constraints

- 兩層檢查皆為**精確比對**，不做書名/作者模糊比對（`spec.md`「重複匯入偵測」定案）。
- 命中時提示使用者「之前匯入過了，仍要建立新的一份嗎？」，使用者可選擇仍要匯入，**不被強制阻擋**。
- Layer 1 命中且使用者選擇取消：該檔案**不進入下載佇列**（不下載，不消耗流量）。
- Layer 2 命中且使用者選擇取消：**立即刪除暫存檔**，不搬移至永久位置，不呼叫 `importFiles()`。
- 所有新增的使用者可見文字與程式碼註解一律使用正體中文（zh-TW），不得使用簡體中文（`CLAUDE.md` 全域規範）。
- 每個 Task 完成後須 `flutter analyze` 乾淨（"No issues found!"）且 `flutter test` 全數通過、零回歸。

---

### Task 1：`CloudBrowserScreen` Layer 1——選檔前置重複偵測 + 共用確認對話框

**Files:**
- Modify: `app/lib/screens/cloud_download_queue_dialog.dart`（新增共用確認對話框 helper 函式；下一個 Task 也會用到）
- Modify: `app/lib/screens/cloud_browser_screen.dart`（`_toggleSelection()` 改為非同步、掛入 Layer 1 檢查）
- Modify: `app/test/support/fake_library_repository.dart`（新增 `throwOnFindByCloudFileId`）
- Test: `app/test/screens/cloud_browser_screen_test.dart`

**Interfaces：**
- Consumes：`LibraryRepository.findByCloudFileId(BookSource provider, String cloudFileId) → Future<Book?>`（Epic 29 Issue 0 已建好，`CloudBrowserScreen` 既有 `widget.libraryRepository`／`widget.source` 欄位可直接取得所需引數）。
- Produces：`showCloudDuplicateConfirmDialog(BuildContext context, String message) → Future<bool>`（新增的公開頂層函式，定義於 `cloud_download_queue_dialog.dart`，供本 Task 的 `CloudBrowserScreen`（Layer 1）與 Task 2 的 `CloudDownloadQueueDialog`（Layer 2）共用；`cloud_browser_screen.dart` 已經 `import 'cloud_download_queue_dialog.dart';`，不需新增 import）。

- [ ] **Step 1：`FakeLibraryRepository` 新增 `throwOnFindByCloudFileId`**

在 `app/test/support/fake_library_repository.dart` 找到：

```dart
  bool throwOnFindByRemoteBookId = false;
```

改為（新增對等的 `throwOnFindByCloudFileId`，供本 Task 的 Layer 1 錯誤處理測試使用）：

```dart
  bool throwOnFindByRemoteBookId = false;

  /// 供測試模擬 [findByCloudFileId] 拋出例外，驗證呼叫端的錯誤處理（比照
  /// 上方 [throwOnFindByRemoteBookId] 既有慣例，epic-29-cloud-import
  /// Issue 5）。
  bool throwOnFindByCloudFileId = false;
```

找到：

```dart
  @override
  Future<Book?> findByCloudFileId(BookSource provider, String cloudFileId) async {
    for (final book in _books) {
      if (book.source == provider && book.cloudFileId == cloudFileId) {
        return book;
      }
    }
    return null;
  }
```

改為：

```dart
  @override
  Future<Book?> findByCloudFileId(BookSource provider, String cloudFileId) async {
    if (throwOnFindByCloudFileId) {
      throw Exception('模擬 findByCloudFileId 查詢失敗');
    }
    for (final book in _books) {
      if (book.source == provider && book.cloudFileId == cloudFileId) {
        return book;
      }
    }
    return null;
  }
```

- [ ] **Step 2：寫入失敗的 Layer 1 測試（4 個情境）**

在 `app/test/screens/cloud_browser_screen_test.dart` 頂部，`import '../support/fake_path_provider_platform.dart';` 之後新增：

```dart
import 'package:elinkbook/library/models/book.dart';

import '../support/fake_library_repository.dart';
```

（`fake_library_repository.dart` 已存在於既有 import 清單中，不要重複新增這一行；只新增 `package:elinkbook/library/models/book.dart` 這一行。）

在 `pumpScreen` helper 定義之前新增一個本機測試 fixture 建構函式：

```dart
  Book fakeBookWithCloudFileId(String id, BookSource source, String cloudFileId) {
    return Book(
      id: id,
      title: '已匯入的書',
      format: BookFileFormat.epub,
      filePath: '/books/$id.epub',
      source: source,
      cloudFileId: cloudFileId,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
  }
```

在檔案最後一個既有 `testWidgets` 區塊之後、`}` 收尾之前，新增：

```dart

  group('選檔前置重複偵測（Layer 1）', () {
    testWidgets('勾選已存在 cloudFileId 的檔案時彈出重複提示，選擇取消則不勾選', (tester) async {
      final client = FakeCloudStorageClient(folderContents: {
        null: const CloudFolderListing(entries: [fileEntryNoThumbnail]),
      });
      final libraryRepository = FakeLibraryRepository(initialBooks: [
        fakeBookWithCloudFileId('local-1', BookSource.googleDrive, 'file-1'),
      ]);
      await pumpScreen(tester, client: client, libraryRepository: libraryRepository);

      await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cloud_duplicate_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cloud_duplicate_dialog_cancel')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('google_drive_browser_checkbox_checked_file-1')),
        findsNothing,
      );
    });

    testWidgets('勾選已存在 cloudFileId 的檔案時彈出重複提示，選擇仍要建立則正常勾選', (tester) async {
      final client = FakeCloudStorageClient(folderContents: {
        null: const CloudFolderListing(entries: [fileEntryNoThumbnail]),
      });
      final libraryRepository = FakeLibraryRepository(initialBooks: [
        fakeBookWithCloudFileId('local-1', BookSource.googleDrive, 'file-1'),
      ]);
      await pumpScreen(tester, client: client, libraryRepository: libraryRepository);

      await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cloud_duplicate_dialog_confirm')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('google_drive_browser_checkbox_checked_file-1')),
        findsOneWidget,
      );
    });

    testWidgets('勾選沒有重複紀錄的檔案時不彈出提示，直接勾選', (tester) async {
      final client = FakeCloudStorageClient(folderContents: {
        null: const CloudFolderListing(entries: [fileEntryNoThumbnail]),
      });
      await pumpScreen(tester, client: client);

      await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cloud_duplicate_dialog')), findsNothing);
      expect(
        find.byKey(const Key('google_drive_browser_checkbox_checked_file-1')),
        findsOneWidget,
      );
    });

    testWidgets('findByCloudFileId 拋出例外時，視同沒有偵測到重複，直接勾選不中斷', (tester) async {
      final client = FakeCloudStorageClient(folderContents: {
        null: const CloudFolderListing(entries: [fileEntryNoThumbnail]),
      });
      final libraryRepository = FakeLibraryRepository()..throwOnFindByCloudFileId = true;
      await pumpScreen(tester, client: client, libraryRepository: libraryRepository);

      await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cloud_duplicate_dialog')), findsNothing);
      expect(
        find.byKey(const Key('google_drive_browser_checkbox_checked_file-1')),
        findsOneWidget,
      );
    });
  });
```

- [ ] **Step 3：執行測試確認失敗**

執行：`flutter test test/screens/cloud_browser_screen_test.dart --plain-name "選檔前置重複偵測"`
預期：4 個新測試皆 FAIL（`cloud_duplicate_dialog` 相關 Key 尚不存在，畫面點擊後直接勾選，無重複偵測邏輯）。

- [ ] **Step 4：`cloud_download_queue_dialog.dart` 新增共用確認對話框**

在 `app/lib/screens/cloud_download_queue_dialog.dart` 找到檔案最後一行（`class _CloudDownloadQueueDialogState` 的收尾 `}`）：

```dart
      actions: [
        TextButton(
          key: const Key('cloud_download_queue_done_button'),
          onPressed: _allSettled ? () => Navigator.of(context).pop() : null,
          child: const Text('完成'),
        ),
      ],
    );
  }
}
```

改為（在該 `}` 之後新增頂層函式）：

```dart
      actions: [
        TextButton(
          key: const Key('cloud_download_queue_done_button'),
          onPressed: _allSettled ? () => Navigator.of(context).pop() : null,
          child: const Text('完成'),
        ),
      ],
    );
  }
}

/// 重複匯入確認彈窗（epic-29-cloud-import Issue 5，完整比照
/// `remote_catalog_screen.dart` 的 `_showDuplicateConfirmDialog` 既有
/// 設計）：選檔前置（Layer 1，[CloudBrowserScreen]）與下載後指紋比對
/// （Layer 2，本檔案的 [CloudDownloadQueueDialog]）兩層檢查共用同一個
/// 確認 UI，只有提示文字不同——精確比對命中不代表強制阻擋，使用者可選擇
/// 仍要建立新副本。刻意宣告為公開（非私有）頂層函式而非私有於單一檔案，
/// 因為 Layer 1 與 Layer 2 分屬 `cloud_browser_screen.dart`／
/// `cloud_download_queue_dialog.dart` 兩個不同檔案（不像 epic-30 兩層都在
/// 同一個檔案內，可以用私有函式）。
Future<bool> showCloudDuplicateConfirmDialog(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('cloud_duplicate_dialog'),
      title: const Text('重複的書籍'),
      content: Text(message),
      actions: [
        TextButton(
          key: const Key('cloud_duplicate_dialog_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('cloud_duplicate_dialog_confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('仍要建立'),
        ),
      ],
    ),
  );
  return result ?? false;
}
```

- [ ] **Step 5：`CloudBrowserScreen._toggleSelection()` 掛入 Layer 1 檢查**

在 `app/lib/screens/cloud_browser_screen.dart` 找到：

```dart
  final Map<String, Future<Uint8List>> _pendingThumbnailFetches = {};

  @override
  void initState() {
```

改為（新增重入防護欄位）：

```dart
  final Map<String, Future<Uint8List>> _pendingThumbnailFetches = {};

  /// 【Epic 29 Issue 5，比照 `remote_catalog_screen.dart` 的
  /// `_pendingDuplicateChecks` 既有先例】快速連續點擊同一個尚未勾選的
  /// 檔案時，避免兩次 `findByCloudFileId()` 查詢並行、各自可能彈出一次
  /// 重複提示——查詢期間先記錄該 entry id，重入的點擊直接忽略。
  final Set<String> _pendingDuplicateChecks = {};

  @override
  void initState() {
```

找到：

```dart
  void _toggleSelection(CloudFileEntry entry) {
    setState(() {
      if (_selectedIds.contains(entry.id)) {
        _selectedIds.remove(entry.id);
      } else {
        _selectedIds.add(entry.id);
      }
    });
  }
```

改為：

```dart
  Future<void> _toggleSelection(CloudFileEntry entry) async {
    if (_selectedIds.contains(entry.id)) {
      setState(() => _selectedIds.remove(entry.id));
      return;
    }
    if (_pendingDuplicateChecks.contains(entry.id)) return;
    _pendingDuplicateChecks.add(entry.id);
    var hasDuplicate = false;
    try {
      hasDuplicate =
          await widget.libraryRepository.findByCloudFileId(widget.source, entry.id) != null;
    } catch (_) {
      hasDuplicate = false;
    } finally {
      _pendingDuplicateChecks.remove(entry.id);
    }
    if (hasDuplicate) {
      if (!mounted) return;
      final proceed = await showCloudDuplicateConfirmDialog(
        context,
        '「${entry.name}」之前匯入過了，仍要建立新的一份嗎？',
      );
      if (!proceed) return;
    }
    if (!mounted) return;
    setState(() => _selectedIds.add(entry.id));
  }
```

- [ ] **Step 6：修正兩個既有測試因 `_toggleSelection` 改為非同步而不再可靠的 `pump()` 時序**

`_toggleSelection()` 從同步改為非同步後，「勾選」這個分支（原本已勾選、點擊取消勾選的分支則仍在第一個 `await` 之前同步執行 `setState`，不受影響）在 `setState(() => _selectedIds.add(...))` 之前多了一次
`await widget.libraryRepository.findByCloudFileId(...)` 的非同步間隔，單一 `await tester.pump()` 不保證能推進到這次 `setState`——完整比照 `remote_catalog_screen_test.dart` 對等的「勾選沒有重複紀錄的書目時不彈出提示，直接勾選」測試已改用 `pumpAndSettle()` 的既有先例，本步驟把本檔案兩個「點擊尚未勾選的檔案」情境的 `pump()` 改為 `pumpAndSettle()`。

在 `app/test/screens/cloud_browser_screen_test.dart` 找到（縮圖 in-flight Future 記憶化迴歸測試）：

```dart
    // 縮圖仍在載入中（completer 尚未完成）時，勾選另一個檔案觸發父層
    // setState 重建整個 GridView，包含尚未載入完成的縮圖項目。
    await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-1')));
    await tester.pump();
```

改為：

```dart
    // 縮圖仍在載入中（completer 尚未完成）時，勾選另一個檔案觸發父層
    // setState 重建整個 GridView，包含尚未載入完成的縮圖項目。
    //
    // 【Epic 29 Issue 5】file-1 的勾選現在會先經過一次
    // `findByCloudFileId()` 非同步查詢才 setState，改用 pumpAndSettle()
    // 確保這次 setState 真的發生，測試才真的驗證到「勾選觸發父層重建」
    // 這個前提，而不是因為 setState 還沒發生而偶然通過。
    await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-1')));
    await tester.pumpAndSettle();
```

找到（「點擊檔案項目切換勾選狀態」測試的第一次點擊，勾選分支）：

```dart
    await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-1')));
    await tester.pump();

    expect(
      find.byKey(const Key('google_drive_browser_checkbox_checked_file-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-1')));
    await tester.pump();

    expect(
      find.byKey(const Key('google_drive_browser_checkbox_checked_file-1')),
      findsNothing,
    );
```

改為（第二次點擊是取消勾選分支，`setState` 仍在第一個 `await` 之前同步執行，維持 `pump()` 即可；只有第一次點擊的勾選分支需要改為 `pumpAndSettle()`）：

```dart
    await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('google_drive_browser_checkbox_checked_file-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-1')));
    await tester.pump();

    expect(
      find.byKey(const Key('google_drive_browser_checkbox_checked_file-1')),
      findsNothing,
    );
```

- [ ] **Step 7：執行測試確認通過**

執行：`flutter test test/screens/cloud_browser_screen_test.dart`
預期：全數 PASS（含新增的 4 個 Layer 1 測試，以及既有測試零回歸——`_toggleSelection` 呼叫端 `onTap: () => _toggleSelection(entry)` 語法不變，改回傳 `Future<void>` 不影響 `InkWell.onTap` 的 `void Function()` 簽章）。

- [ ] **Step 8：Commit**

```bash
git add app/lib/screens/cloud_download_queue_dialog.dart app/lib/screens/cloud_browser_screen.dart app/test/support/fake_library_repository.dart app/test/screens/cloud_browser_screen_test.dart
git commit -m "feat(epic-29): Issue 5——CloudBrowserScreen 選檔前置重複偵測（Layer 1）"
```

---

### Task 2：`CloudDownloadQueueDialog` Layer 2——下載後指紋比對

**Files:**
- Modify: `app/lib/screens/cloud_download_queue_dialog.dart`
- Test: `app/test/screens/cloud_download_queue_dialog_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `showCloudDuplicateConfirmDialog(BuildContext, String) → Future<bool>`；`LibraryRepository.findByContentFingerprint(String fingerprint) → Future<Book?>`（Issue 0 已建好）；既有的 `ComputeRemoteFingerprint` typedef（`Future<String> Function(String filePath, BookFileFormat format)`，定義於 `app/lib/library/book_content_fingerprint.dart`，provider 無關，直接沿用不新增型別）。
- Produces：`CloudDownloadQueueDialog` 新增兩個必填建構參數 `libraryRepository: LibraryRepository`、`computeFingerprint: ComputeRemoteFingerprint`，供 Task 3 的 `CloudBrowserScreen` 貫穿注入。

- [ ] **Step 1：寫入失敗的 Layer 2 測試（3 個情境）**

在 `app/test/screens/cloud_download_queue_dialog_test.dart` 找到 import 區塊：

```dart
import '../support/fake_book_import_service.dart';
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_path_provider_platform.dart';
```

改為：

```dart
import '../support/fake_book_import_service.dart';
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_fingerprint_computer.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_path_provider_platform.dart';
```

找到：

```dart
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/cloud_download_queue_dialog.dart';
```

改為：

```dart
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/cloud_download_queue_dialog.dart';
```

找到 `pumpDialog` helper：

```dart
  Future<void> pumpDialog(
    WidgetTester tester, {
    required FakeCloudStorageClient client,
    required FakeBookImportService importService,
    List<CloudFileEntry> entries = const [entry1],
    String? folderName,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (context) => CloudDownloadQueueDialog(
                entries: entries,
                client: client,
                importService: importService,
                source: BookSource.googleDrive,
                folderName: folderName,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
  }
```

改為（新增兩個可選參數，未提供時分別退回空的 `FakeLibraryRepository`／預設 `FakeFingerprintComputer`——既有 3 個測試呼叫端不需要任何修改，`findByContentFingerprint` 對空 repository 永遠回傳 `null`，行為與新增前完全一致）：

```dart
  Future<void> pumpDialog(
    WidgetTester tester, {
    required FakeCloudStorageClient client,
    required FakeBookImportService importService,
    FakeLibraryRepository? libraryRepository,
    FakeFingerprintComputer? fingerprintComputer,
    List<CloudFileEntry> entries = const [entry1],
    String? folderName,
  }) async {
    final fingerprint = fingerprintComputer ?? FakeFingerprintComputer();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (context) => CloudDownloadQueueDialog(
                entries: entries,
                client: client,
                importService: importService,
                libraryRepository: libraryRepository ?? FakeLibraryRepository(),
                computeFingerprint: fingerprint.call,
                source: BookSource.googleDrive,
                folderName: folderName,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
  }
```

在 `entry1` 定義之後新增本機測試 fixture 建構函式：

```dart
  Book fakeBookWithFingerprint(String id, String fingerprint) {
    return Book(
      id: id,
      title: '本機已有的書',
      format: BookFileFormat.epub,
      filePath: '/books/$id.epub',
      source: BookSource.local,
      contentFingerprint: fingerprint,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
  }
```

在檔案最後一個既有 `testWidgets`（「下載中點擊取消後顯示已取消狀態，暫存檔不殘留」）之後、`}` 收尾之前，新增：

```dart

  group('下載後指紋比對（Layer 2）', () {
    testWidgets('下載後偵測到與本機書籍內容指紋相同時彈出提示，選擇不建立新副本則刪除暫存檔並標記為略過',
        (tester) async {
      final client = FakeCloudStorageClient(downloadContents: {
        'file-1': [1, 2, 3],
      });
      final importService = FakeBookImportService();
      final libraryRepository = FakeLibraryRepository(initialBooks: [
        fakeBookWithFingerprint('local-1', 'dup-fingerprint'),
      ]);
      final fingerprintComputer = FakeFingerprintComputer()..nextFingerprint = 'dup-fingerprint';
      await pumpDialog(
        tester,
        client: client,
        importService: importService,
        libraryRepository: libraryRepository,
        fingerprintComputer: fingerprintComputer,
      );

      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        if (find.byKey(const Key('cloud_duplicate_dialog')).evaluate().isNotEmpty) break;
      }

      expect(find.byKey(const Key('cloud_duplicate_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cloud_duplicate_dialog_cancel')));
      await settleDownload(tester);

      expect(find.text('重複已略過（未匯入）'), findsOneWidget);
      expect(importService.lastImportCall, isNull);
      final tempDownloadDir = Directory('${tempRoot.path}/cloud_import_download_temp');
      expect(
        tempDownloadDir.existsSync() ? tempDownloadDir.listSync() : const [],
        isEmpty,
      );
    });

    testWidgets('下載後偵測到重複時選擇仍要建立新副本，正常完成匯入', (tester) async {
      final client = FakeCloudStorageClient(downloadContents: {
        'file-1': [1, 2, 3],
      });
      final importService = FakeBookImportService();
      final libraryRepository = FakeLibraryRepository(initialBooks: [
        fakeBookWithFingerprint('local-1', 'dup-fingerprint'),
      ]);
      final fingerprintComputer = FakeFingerprintComputer()..nextFingerprint = 'dup-fingerprint';
      await pumpDialog(
        tester,
        client: client,
        importService: importService,
        libraryRepository: libraryRepository,
        fingerprintComputer: fingerprintComputer,
      );

      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        if (find.byKey(const Key('cloud_duplicate_dialog')).evaluate().isNotEmpty) break;
      }

      await tester.tap(find.byKey(const Key('cloud_duplicate_dialog_confirm')));
      await settleDownload(tester);

      final listTile =
          tester.widget<ListTile>(find.byKey(const Key('cloud_download_queue_item_file-1')));
      expect((listTile.subtitle as Text).data, '完成');
      expect(importService.lastImportCall, isNotNull);
    });

    testWidgets('下載後未偵測到重複時不彈出提示，直接完成', (tester) async {
      final client = FakeCloudStorageClient(downloadContents: {
        'file-1': [1, 2, 3],
      });
      final importService = FakeBookImportService();
      final fingerprintComputer = FakeFingerprintComputer();
      await pumpDialog(
        tester,
        client: client,
        importService: importService,
        fingerprintComputer: fingerprintComputer,
      );

      await settleDownload(tester);

      expect(find.byKey(const Key('cloud_duplicate_dialog')), findsNothing);
      final listTile =
          tester.widget<ListTile>(find.byKey(const Key('cloud_download_queue_item_file-1')));
      expect((listTile.subtitle as Text).data, '完成');
      expect(importService.lastImportCall, isNotNull);
      // 驗證指紋計算確實在下載成功之後才被呼叫恰好一次，且傳入的是下載
      // 完成的暫存檔路徑（比照 review-issue-3.md 對 remote_catalog 版本的
      // 既有斷言慣例）。
      expect(fingerprintComputer.calls, hasLength(1));
      expect(fingerprintComputer.calls.single, isNotEmpty);
    });
  });
```

- [ ] **Step 2：執行測試確認失敗**

執行：`flutter test test/screens/cloud_download_queue_dialog_test.dart`
預期：編譯失敗（`CloudDownloadQueueDialog` 沒有 `libraryRepository`/`computeFingerprint` 具名參數）。

- [ ] **Step 3：`CloudDownloadQueueDialog` 新增建構參數與 Layer 2 邏輯**

在 `app/lib/screens/cloud_download_queue_dialog.dart` 找到：

```dart
import 'package:flutter/material.dart';

import '../cloud_import/cloud_book_downloader.dart';
import '../cloud_import/cloud_storage_client.dart';
import '../library/book_import_service.dart';
import '../library/models/library_enums.dart';

enum CloudDownloadItemStatus { pending, downloading, done, failed, cancelled }
```

改為：

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../cloud_import/cloud_book_downloader.dart';
import '../cloud_import/cloud_storage_client.dart';
import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/library_enums.dart';

enum CloudDownloadItemStatus {
  pending,
  downloading,
  checkingDuplicate,
  done,
  duplicateSkipped,
  failed,
  cancelled,
}
```

找到：

```dart
class CloudDownloadQueueDialog extends StatefulWidget {
  final List<CloudFileEntry> entries;
  final CloudStorageClient client;
  final BookImportService importService;
  final BookSource source;
  final String? folderName;

  const CloudDownloadQueueDialog({
    super.key,
    required this.entries,
    required this.client,
    required this.importService,
    required this.source,
    this.folderName,
  });
```

改為：

```dart
class CloudDownloadQueueDialog extends StatefulWidget {
  final List<CloudFileEntry> entries;
  final CloudStorageClient client;
  final BookImportService importService;

  /// 【Epic 29 Issue 5，Layer 2：下載後指紋比對】下載完成、搬移至永久
  /// 位置之前，用來查詢是否已存在內容指紋相同的本機書籍。
  final LibraryRepository libraryRepository;

  /// 【Epic 29 Issue 5，Layer 2】計算暫存檔內容指紋的函式，與
  /// `RemoteCatalogScreen`／`main.dart` 共用同一個 `ComputeRemoteFingerprint`
  /// typedef（provider 無關）。真機組裝時傳入
  /// `computeBookContentFingerprint`；widget test 環境必須改注入
  /// `FakeFingerprintComputer`（真實函式內部對本機路徑用 `Isolate.run()`
  /// 計算 SHA-256，在 `testWidgets()` 的 fake-time 測試環境下會死鎖，見
  /// `book_content_fingerprint.dart` 文件說明）。
  final ComputeRemoteFingerprint computeFingerprint;

  final BookSource source;
  final String? folderName;

  const CloudDownloadQueueDialog({
    super.key,
    required this.entries,
    required this.client,
    required this.importService,
    required this.libraryRepository,
    required this.computeFingerprint,
    required this.source,
    this.folderName,
  });
```

找到：

```dart
  Future<void> _downloadOne(int index) async {
    if (!mounted) return;
    setState(() => _statuses[index] = CloudDownloadItemStatus.downloading);
    final entry = widget.entries[index];
    final token = CloudDownloadCancellationToken();
    _tokens[index] = token;
    try {
      final tempPath = await downloadCloudFileToTempFile(
        client: widget.client,
        entry: entry,
        cancellationToken: token,
      );
      final permanentPath = await promoteCloudFileToPermanent(tempPath);
      if (!mounted) return;
      setState(() {
        _permanentPaths[index] = permanentPath;
        _statuses[index] = CloudDownloadItemStatus.done;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statuses[index] = token.isCancelled
            ? CloudDownloadItemStatus.cancelled
            : CloudDownloadItemStatus.failed;
      });
    }
  }
```

改為（`tempPath` 提升到 `try` 外層的區域變數，讓 `catch` 區塊在「指紋比對／彈窗期間發生例外」這個 `promoteCloudFileToPermanent()` 自身清理保證涵蓋不到的窗口，也能正確刪除暫存檔——完整比照 `remote_catalog_screen.dart._downloadOne` 既有設計）：

```dart
  Future<void> _downloadOne(int index) async {
    if (!mounted) return;
    setState(() => _statuses[index] = CloudDownloadItemStatus.downloading);
    final entry = widget.entries[index];
    final token = CloudDownloadCancellationToken();
    _tokens[index] = token;
    String? tempPath;
    try {
      tempPath = await downloadCloudFileToTempFile(
        client: widget.client,
        entry: entry,
        cancellationToken: token,
      );

      if (!mounted) return;
      setState(() => _statuses[index] = CloudDownloadItemStatus.checkingDuplicate);
      // entry.format 在此保證非 null：能被使用者勾選、進而進入下載佇列的
      // 檔案，其 format 必然已通過 detectCloudFileFormat() 驗證——偵測不到
      // 支援格式的項目在 listFolder() 就已被過濾掉，不會出現在 _entries
      // 內（比照 remote_catalog_screen.dart._downloadOne 的
      // `item.acquisition.format!` 既有做法）。
      final fingerprint = await widget.computeFingerprint(tempPath, entry.format!);
      final existingByFingerprint =
          await widget.libraryRepository.findByContentFingerprint(fingerprint);
      if (existingByFingerprint != null) {
        if (!mounted) return;
        final proceed = await showCloudDuplicateConfirmDialog(
          context,
          '偵測到「${entry.name}」與本機已有的一本書內容相同，仍要建立新的一份嗎？',
        );
        if (!proceed) {
          final leftover = File(tempPath);
          if (await leftover.exists()) await leftover.delete();
          if (!mounted) return;
          setState(() => _statuses[index] = CloudDownloadItemStatus.duplicateSkipped);
          return;
        }
      }

      final permanentPath = await promoteCloudFileToPermanent(tempPath);
      if (!mounted) return;
      setState(() {
        _permanentPaths[index] = permanentPath;
        _statuses[index] = CloudDownloadItemStatus.done;
      });
    } catch (_) {
      if (tempPath != null) {
        final leftover = File(tempPath);
        if (await leftover.exists()) await leftover.delete();
      }
      if (!mounted) return;
      setState(() {
        _statuses[index] = token.isCancelled
            ? CloudDownloadItemStatus.cancelled
            : CloudDownloadItemStatus.failed;
      });
    }
  }
```

找到：

```dart
  String _statusLabel(CloudDownloadItemStatus status) {
    switch (status) {
      case CloudDownloadItemStatus.pending:
        return '等待中';
      case CloudDownloadItemStatus.downloading:
        return '下載中';
      case CloudDownloadItemStatus.done:
        return '完成';
      case CloudDownloadItemStatus.failed:
        return '失敗';
      case CloudDownloadItemStatus.cancelled:
        return '已取消';
    }
  }
```

改為：

```dart
  String _statusLabel(CloudDownloadItemStatus status) {
    switch (status) {
      case CloudDownloadItemStatus.pending:
        return '等待中';
      case CloudDownloadItemStatus.downloading:
        return '下載中';
      case CloudDownloadItemStatus.checkingDuplicate:
        return '比對重複中';
      case CloudDownloadItemStatus.done:
        return '完成';
      case CloudDownloadItemStatus.duplicateSkipped:
        return '重複已略過（未匯入）';
      case CloudDownloadItemStatus.failed:
        return '失敗';
      case CloudDownloadItemStatus.cancelled:
        return '已取消';
    }
  }
```

- [ ] **Step 4：執行測試確認通過**

執行：`flutter test test/screens/cloud_download_queue_dialog_test.dart`
預期：全數 PASS（含新增的 3 個 Layer 2 測試，既有 3 個測試零回歸——`pumpDialog` 新增的兩個參數皆為可選，未傳入時退回空 `FakeLibraryRepository`，`findByContentFingerprint` 永遠回傳 `null`，行為與新增前一致）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/cloud_download_queue_dialog.dart app/test/screens/cloud_download_queue_dialog_test.dart
git commit -m "feat(epic-29): Issue 5——CloudDownloadQueueDialog 下載後指紋比對（Layer 2）"
```

---

### Task 3：貫穿注入 `computeFingerprint`——`CloudBrowserScreen` 必填化 + `library_screen.dart` 兩呼叫點與選單門檻 + 自我遞迴導航點轉發

**Files:**
- Modify: `app/lib/screens/cloud_browser_screen.dart`
- Modify: `app/lib/screens/library_screen.dart`
- Test: `app/test/screens/cloud_browser_screen_test.dart`
- Modify: `app/test/screens/library_screen_test.dart`

**Interfaces：**
- Consumes：Task 2 的 `CloudDownloadQueueDialog({..., required libraryRepository, required computeFingerprint})`；`LibraryScreen` 既有的 `final ComputeRemoteFingerprint? computeFingerprint;` 欄位（`library_screen.dart:68`，Epic 30 已建置，本 Task 是第一個把它接到 Google Drive／OneDrive 匯入路徑的消費端）。
- Produces：`CloudBrowserScreen` 新增必填建構參數 `computeFingerprint: ComputeRemoteFingerprint`。

- [ ] **Step 1：`CloudBrowserScreen` 新增必填 `computeFingerprint` 欄位並貫穿給 `CloudDownloadQueueDialog`**

在 `app/lib/screens/cloud_browser_screen.dart` 找到：

```dart
import '../cloud_import/cloud_storage_client.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/book_group.dart';
import '../library/models/library_enums.dart';
import 'cloud_download_queue_dialog.dart';
```

改為：

```dart
import '../cloud_import/cloud_storage_client.dart';
import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/book_group.dart';
import '../library/models/library_enums.dart';
import 'cloud_download_queue_dialog.dart';
```

找到：

```dart
  final BookSource source;

  /// `null` 代表瀏覽雲端硬碟根目錄；非 `null` 時瀏覽指定資料夾（點擊
  /// [CloudFileEntry.isFolder] 為 `true` 的項目下鑽時使用）。
  final String? folderId;
```

改為：

```dart
  final BookSource source;

  /// 【Epic 29 Issue 5】貫穿轉發給 [CloudDownloadQueueDialog] 做 Layer 2
  /// 下載後指紋比對；本畫面自己的 Layer 1（選檔前置）只需要
  /// [libraryRepository]，不需要指紋計算，故不在這裡使用。
  final ComputeRemoteFingerprint computeFingerprint;

  /// `null` 代表瀏覽雲端硬碟根目錄；非 `null` 時瀏覽指定資料夾（點擊
  /// [CloudFileEntry.isFolder] 為 `true` 的項目下鑽時使用）。
  final String? folderId;
```

找到：

```dart
  const CloudBrowserScreen({
    super.key,
    required this.client,
    required this.libraryRepository,
    required this.importService,
    required this.source,
    this.folderId,
    this.title,
  });
```

改為：

```dart
  const CloudBrowserScreen({
    super.key,
    required this.client,
    required this.libraryRepository,
    required this.importService,
    required this.source,
    required this.computeFingerprint,
    this.folderId,
    this.title,
  });
```

找到 `_openSubfolder()`：

```dart
  void _openSubfolder(CloudFileEntry entry) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => CloudBrowserScreen(
        client: widget.client,
        libraryRepository: widget.libraryRepository,
        importService: widget.importService,
        source: widget.source,
        folderId: entry.id,
        title: entry.name,
      ),
    ));
  }
```

改為（一併轉發 `computeFingerprint`，否則下鑽進資料夾後會遺失，等同重現 Issue 4 review-plan-issue-4.md Critical #1 那類「重新命名/新增必填欄位時漏轉發遞迴自我導航點」的同一種錯誤模式）：

```dart
  void _openSubfolder(CloudFileEntry entry) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => CloudBrowserScreen(
        client: widget.client,
        libraryRepository: widget.libraryRepository,
        importService: widget.importService,
        source: widget.source,
        computeFingerprint: widget.computeFingerprint,
        folderId: entry.id,
        title: entry.name,
      ),
    ));
  }
```

找到 `_startDownload()`：

```dart
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CloudDownloadQueueDialog(
        entries: selected,
        client: widget.client,
        importService: widget.importService,
        source: widget.source,
        folderName: folderName,
      ),
    );
```

改為：

```dart
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CloudDownloadQueueDialog(
        entries: selected,
        client: widget.client,
        importService: widget.importService,
        libraryRepository: widget.libraryRepository,
        computeFingerprint: widget.computeFingerprint,
        source: widget.source,
        folderName: folderName,
      ),
    );
```

- [ ] **Step 2：更新 `cloud_browser_screen_test.dart` 的 `pumpScreen` helper**

在 `app/test/screens/cloud_browser_screen_test.dart` 頂部 import 區塊新增：

```dart
import '../support/fake_fingerprint_computer.dart';
```

找到：

```dart
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeCloudStorageClient client,
    FakeLibraryRepository? libraryRepository,
    FakeBookImportService? importService,
    String? folderId,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: CloudBrowserScreen(
        client: client,
        libraryRepository: libraryRepository ?? FakeLibraryRepository(),
        importService: importService ?? FakeBookImportService(),
        source: BookSource.googleDrive,
        folderId: folderId,
      ),
    ));
    await tester.pumpAndSettle();
  }
```

改為（新增可選的 `fingerprintComputer` 參數，未提供時退回預設 `FakeFingerprintComputer()`——既有全部呼叫端不需要修改）：

```dart
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeCloudStorageClient client,
    FakeLibraryRepository? libraryRepository,
    FakeBookImportService? importService,
    FakeFingerprintComputer? fingerprintComputer,
    String? folderId,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: CloudBrowserScreen(
        client: client,
        libraryRepository: libraryRepository ?? FakeLibraryRepository(),
        importService: importService ?? FakeBookImportService(),
        source: BookSource.googleDrive,
        computeFingerprint: (fingerprintComputer ?? FakeFingerprintComputer()).call,
        folderId: folderId,
      ),
    ));
    await tester.pumpAndSettle();
  }
```

- [ ] **Step 3：執行測試確認通過**

執行：`flutter test test/screens/cloud_browser_screen_test.dart`
預期：全數 PASS（含 Task 1 新增的 4 個 Layer 1 測試）。

- [ ] **Step 4：`library_screen.dart` 兩個呼叫點貫穿 `computeFingerprint` + 選單門檻**

在 `app/lib/screens/library_screen.dart` 找到：

```dart
  void _openGoogleDriveBrowser(CloudStorageClient client) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (context) => CloudBrowserScreen(
            client: client,
            libraryRepository: widget.repository,
            importService: widget.importService,
            source: BookSource.googleDrive,
          ),
        ))
        .then((_) {
```

改為：

```dart
  void _openGoogleDriveBrowser(CloudStorageClient client) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (context) => CloudBrowserScreen(
            client: client,
            libraryRepository: widget.repository,
            importService: widget.importService,
            source: BookSource.googleDrive,
            computeFingerprint: widget.computeFingerprint!,
          ),
        ))
        .then((_) {
```

找到：

```dart
  void _openOneDriveBrowser(CloudStorageClient client) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (context) => CloudBrowserScreen(
            client: client,
            libraryRepository: widget.repository,
            importService: widget.importService,
            source: BookSource.oneDrive,
            title: 'OneDrive',
          ),
        ))
        .then((_) {
```

改為：

```dart
  void _openOneDriveBrowser(CloudStorageClient client) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (context) => CloudBrowserScreen(
            client: client,
            libraryRepository: widget.repository,
            importService: widget.importService,
            source: BookSource.oneDrive,
            computeFingerprint: widget.computeFingerprint!,
            title: 'OneDrive',
          ),
        ))
        .then((_) {
```

找到「匯入」選單的兩個雲端匯入項目：

```dart
            PopupMenuItem<void>(
              key: const Key('library_import_google_drive_option'),
              enabled: widget.googleDriveStorageClient != null,
              onTap: widget.googleDriveStorageClient == null
                  ? null
                  : () => _openGoogleDriveBrowser(widget.googleDriveStorageClient!),
              child: const Text('從 Google Drive 匯入'),
            ),
            PopupMenuItem<void>(
              key: const Key('library_import_onedrive_option'),
              enabled: widget.oneDriveStorageClient != null,
              onTap: widget.oneDriveStorageClient == null
                  ? null
                  : () => _openOneDriveBrowser(widget.oneDriveStorageClient!),
              child: const Text('從 OneDrive 匯入'),
            ),
```

改為（`computeFingerprint` 成為 `CloudBrowserScreen` 必填欄位後，兩個選單項目也必須一併門檻於 `widget.computeFingerprint != null`，否則 `widget.computeFingerprint!` 在該值為 `null` 時會直接丟出 `TypeError`——比照既有「遠端書庫」按鈕 `widget.remoteServerRepository != null && ... && widget.computeFingerprint != null` 的既定門檻慣例）：

```dart
            PopupMenuItem<void>(
              key: const Key('library_import_google_drive_option'),
              enabled: widget.googleDriveStorageClient != null &&
                  widget.computeFingerprint != null,
              onTap: (widget.googleDriveStorageClient == null ||
                      widget.computeFingerprint == null)
                  ? null
                  : () => _openGoogleDriveBrowser(widget.googleDriveStorageClient!),
              child: const Text('從 Google Drive 匯入'),
            ),
            PopupMenuItem<void>(
              key: const Key('library_import_onedrive_option'),
              enabled: widget.oneDriveStorageClient != null &&
                  widget.computeFingerprint != null,
              onTap: (widget.oneDriveStorageClient == null ||
                      widget.computeFingerprint == null)
                  ? null
                  : () => _openOneDriveBrowser(widget.oneDriveStorageClient!),
              child: const Text('從 OneDrive 匯入'),
            ),
```

- [ ] **Step 5：修正 `library_screen_test.dart` 兩則既有測試因新增選單門檻而不再通過**

【審查 review-plan-issue-5.md Critical #1 採納】Step 4 的門檻變更，讓「從 Google Drive／OneDrive 匯入」兩個選單項目多了 `widget.computeFingerprint != null` 這個條件；但 `library_screen_test.dart` 既有兩則導航測試建構 `LibraryScreen` 時並未傳入 `computeFingerprint`，套用 Step 4 後這兩個選單項目會被誤判為停用，`tester.tap()` 點擊後不會觸發導航，既有斷言會直接失敗。

在 `app/test/screens/library_screen_test.dart` 找到 import 區塊：

```dart
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_remote_thumbnail_cache.dart';
```

改為：

```dart
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_fingerprint_computer.dart';
import '../support/fake_remote_thumbnail_cache.dart';
```

找到：

```dart
  testWidgets('提供 googleDriveStorageClient 時點擊「從 Google Drive 匯入」導航至 GoogleDriveBrowserScreen',
      (tester) async {
    final client = FakeCloudStorageClient();
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          googleDriveStorageClient: client,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_import_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_import_google_drive_option')));
    await tester.pumpAndSettle();

    expect(find.text('Google Drive'), findsOneWidget);
  });
```

改為：

```dart
  testWidgets('提供 googleDriveStorageClient 時點擊「從 Google Drive 匯入」導航至 GoogleDriveBrowserScreen',
      (tester) async {
    final client = FakeCloudStorageClient();
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          googleDriveStorageClient: client,
          computeFingerprint: FakeFingerprintComputer().call,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_import_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_import_google_drive_option')));
    await tester.pumpAndSettle();

    expect(find.text('Google Drive'), findsOneWidget);
  });
```

找到：

```dart
  testWidgets('提供 oneDriveStorageClient 時點擊「從 OneDrive 匯入」導航至 CloudBrowserScreen',
      (tester) async {
    final client = FakeCloudStorageClient();
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          oneDriveStorageClient: client,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('library_import_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_import_onedrive_option')));
    await tester.pumpAndSettle();

    expect(find.text('OneDrive'), findsOneWidget);
  });
```

改為：

```dart
  testWidgets('提供 oneDriveStorageClient 時點擊「從 OneDrive 匯入」導航至 CloudBrowserScreen',
      (tester) async {
    final client = FakeCloudStorageClient();
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          oneDriveStorageClient: client,
          computeFingerprint: FakeFingerprintComputer().call,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('library_import_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_import_onedrive_option')));
    await tester.pumpAndSettle();

    expect(find.text('OneDrive'), findsOneWidget);
  });
```

**注意**：既有的「`googleDriveStorageClient`／`oneDriveStorageClient` 為 `null` 時選項停用」兩則測試（第 2033–2046 行、第 2071–2089 行）本來就未提供 `computeFingerprint`，維持現狀即可——`enabled` 判斷式是 `&&`（兩個條件皆需成立才啟用），這兩則測試驗證的正是「storage client 為 null」單一條件已經足以讓選項停用，不需要額外新增「`computeFingerprint` 為 null 時選項停用」的斷言（審查報告 Minor 建議的第 3 點，兩個既有測試已經涵蓋等價情境，不重複新增）。

- [ ] **Step 6：`_openGroupFilteredView()` 自我遞迴導航點轉發 `computeFingerprint`**

在 `app/lib/screens/library_screen.dart` 找到：

```dart
              // 【審查修正 review-issue-3.md Important #1】先前遺漏這個
              // 欄位，導致從分類篩選路徑進入的 LibraryScreen 內「從
              // Google Drive 匯入」選單項目永遠停用（比照上方三個雲端
              // 帳號相關欄位的既有貫穿慣例）。
              googleDriveStorageClient: widget.googleDriveStorageClient,
              oneDriveStorageClient: widget.oneDriveStorageClient,
              currentTheme: widget.currentTheme,
```

改為（一併轉發 `computeFingerprint`——不然 Issue 5 新增的 `widget.computeFingerprint != null` 選單門檻，會讓分類篩選路徑內「從 Google Drive／OneDrive 匯入」兩個選項一起被誤停用，等同重現 review-issue-3.md Important #1 同一種「自我遞迴導航點漏轉發新依賴」錯誤模式；本次**只**補上 `computeFingerprint`——`remoteServerRepository`／`createOpdsClient`／`thumbnailCache` 這三個「遠端書庫」相關欄位在這個遞迴點本來就未轉發，是 Epic 30 遺留、與本 Issue 無關的既有缺口，不在本計劃範圍內一併修正，留待後續處理）：

```dart
              // 【審查修正 review-issue-3.md Important #1】先前遺漏這個
              // 欄位，導致從分類篩選路徑進入的 LibraryScreen 內「從
              // Google Drive 匯入」選單項目永遠停用（比照上方三個雲端
              // 帳號相關欄位的既有貫穿慣例）。
              googleDriveStorageClient: widget.googleDriveStorageClient,
              oneDriveStorageClient: widget.oneDriveStorageClient,
              // 【Epic 29 Issue 5】Issue 5 新增的「從 Google Drive／
              // OneDrive 匯入」選單門檻改為同時檢查
              // `widget.computeFingerprint != null`，這裡若不轉發，分類
              // 篩選路徑內兩個雲端匯入選項會一起被誤停用（同一種錯誤模式
              // 見上方 googleDriveStorageClient 的審查修正註解）。
              computeFingerprint: widget.computeFingerprint,
              currentTheme: widget.currentTheme,
```

- [ ] **Step 7：執行完整測試套件與靜態分析確認零回歸**

執行：`flutter analyze`
預期："No issues found!"

執行：`flutter test`
預期：全數 PASS。

- [ ] **Step 8：Commit**

```bash
git add app/lib/screens/cloud_browser_screen.dart app/lib/screens/library_screen.dart app/test/screens/cloud_browser_screen_test.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-29): Issue 5——貫穿注入 computeFingerprint 至雲端匯入選單與分類篩選路徑"
```
