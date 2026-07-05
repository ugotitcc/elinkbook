# Issue 11：匯入流程新增處理中狀態回饋 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `LibraryScreen` 的匯入流程（單檔/多檔選取、資料夾匯入）新增「處理中」狀態的視覺回饋——顯示覆蓋層 + 進度指示 + 「匯入中...」文字，並停用其他匯入觸發點——避免使用者在匯入大檔案（例如 100MB 以上的漫畫類 EPUB）時，因為畫面在處理期間完全無變化而誤以為 App 當機。

**Architecture:** 純 Flutter/Dart UI 層變更，新增一個 `bool _isImporting` 狀態欄位，包住既有的 `_pickAndImportFiles()`/`_pickAndImportFolder()` 呼叫；`build()` 在 `_isImporting` 為真時於書架內容上疊加一層覆蓋層。不涉及原生程式碼、不新增 MethodChannel、不修改 `LibraryRepository`/`BookImportService` 介面本身。

**Tech Stack:** Flutter/Dart（`flutter_test` widget test）、既有的 `LibraryScreen`/`BookImportService` 型別（Issue 4/5/8）。

## Global Constraints

- 觸發匯入（單檔/多檔選取按鈕、資料夾匯入按鈕）後，在 `importService.importFiles()`/`importFolder()` 等待期間，畫面須顯示明確的「匯入中...」提示（覆蓋層 + `CircularProgressIndicator`）。
- 處理中狀態須同時停用其他匯入觸發點——App Bar 的「匯入書籍」選單按鈕（`library_import_button`，整個選單，因為它底下兩個選項皆為匯入動作）與空清單狀態的「匯入書籍」按鈕（`library_empty_import_button`）——避免使用者重複點擊觸發並行的多次匯入。
- 匯入完成（不論成功或拋出例外）後，處理中狀態必須解除，畫面恢復一般可互動狀態；既有的「匯入失敗時靜默吞掉例外」行為維持不變——本工單只新增處理中期間的視覺回饋與觸發點停用，不改動任何錯誤處理邏輯。
- 本工單範圍僅止於匯入流程的處理中回饋，不改動排序、檢視模式切換、設定入口、或 Issue 10 的長按多選/批次移動分類等其他既有互動。
- 不得新增/修改任何 MethodChannel、不得修改 `LibraryRepository`/`BookImportService` 介面本身。
- 所有 UI 文字與程式碼註解維持正體中文。
- 套件名稱為 `elinkbook`；所有測試 import 使用 `package:elinkbook/...`。
- Widget test 中若畫面上會出現 `CircularProgressIndicator`（無 `value`，即不確定進度）這類持續動畫元件，一律使用固定次數/時長的 `tester.pump(Duration(...))`，**不得使用 `tester.pumpAndSettle()`**——持續動畫會不斷排程新影格，導致 `pumpAndSettle()` 逾時拋出例外。

---

### Task 1：`LibraryScreen` 匯入處理中狀態回饋

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/test/support/fake_book_import_service.dart`
- Modify: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: 既有的 `BookImportService.importFiles(List<String> uris, {String? folderName})` / `importFolder(String folderUri, {bool autoGroupByFolderName})`（Issue 4/8，簽章不變）。
- Produces: 無新公開介面——`LibraryScreen` 對外建構參數不變。本工單只新增內部狀態與其對應的 Key，供本檔案的 widget test 觀察：`Key('library_importing_overlay')`（匯入中覆蓋層）。`FakeBookImportService` 新增一個可選的 `pendingCompleter` 欄位（測試用途），供 widget test 控制匯入「尚未完成」的時間點。

此任務改動集中在 `library_screen.dart`（狀態欄位 + 三個既有方法 + 一個新增方法）與其對應的測試基礎設施，因為所有變更都圍繞同一個 `_isImporting` 狀態欄位，拆成多個獨立任務沒有實質意義。

- [ ] **Step 1: 擴充 `FakeBookImportService`，支援可控制完成時機的假匯入**

打開 `app/test/support/fake_book_import_service.dart`，將整個檔案內容換成：

```dart
import 'dart:async';

import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/models/book.dart';

/// 供 widget test 使用的 [BookImportService] 假實作。預設立即回傳空清單；
/// 若設定 [pendingCompleter]，`importFiles`/`importFolder` 改為等待該
/// completer 完成才回傳（或拋出例外，取決於呼叫 `complete`/`completeError`），
/// 讓測試能控制「匯入尚未完成」的時間點（見 Issue 11：匯入處理中狀態回饋）。
class FakeBookImportService implements BookImportService {
  Completer<List<Book>>? pendingCompleter;

  @override
  Future<List<Book>> importFiles(
    List<String> uris, {
    String? folderName,
  }) {
    final completer = pendingCompleter;
    if (completer != null) return completer.future;
    return Future.value(const []);
  }

  @override
  Future<List<Book>> importFolder(
    String folderUri, {
    bool autoGroupByFolderName = true,
  }) {
    final completer = pendingCompleter;
    if (completer != null) return completer.future;
    return Future.value(const []);
  }
}
```

- [ ] **Step 2: 寫失敗的測試——三個新的處理中狀態測試**

打開 `app/test/screens/library_screen_test.dart`。在檔案開頭現有的 import 區塊最上方新增：

```dart
import 'dart:async';

```

（放在檔案第一行 `import 'package:flutter/material.dart';` 之前。）

接著在 `void main() { ... }` 的最後一個 `testWidgets(...)`（`點擊「選擇資料夾」...`）之後、檔案結尾的 `}` 之前，新增以下 3 個測試：

```dart
  testWidgets('觸發資料夾匯入後，匯入完成前畫面顯示處理中狀態，其他匯入觸發點停用',
      (tester) async {
    const folderPickerChannel = MethodChannel('elinkbook/folder_picker');
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(folderPickerChannel, null);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(folderPickerChannel, (call) async {
      if (call.method == 'pickFolder') {
        return 'content://example/tree/folder';
      }
      return null;
    });

    final importService = FakeBookImportService();
    final completer = Completer<List<Book>>();
    importService.pendingCompleter = completer;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: importService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_import_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_import_folder_option')));
    await tester.pumpAndSettle();

    expect(find.text('匯入資料夾'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_import_folder_confirm')));
    // 此時 importFolder() 已開始執行但尚未完成（completer 尚未 complete）。
    // 畫面上會出現持續動畫的 CircularProgressIndicator，不可用
    // pumpAndSettle()（會因動畫持續排程新影格而逾時），改用固定次數的
    // pump() 讓對話框關閉、_pickAndImportFolder 恢復執行到
    // setState(_isImporting = true) 為止。
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('library_importing_overlay')), findsOneWidget);
    expect(find.text('匯入中...'), findsOneWidget);

    final importButton = tester.widget<PopupMenuButton<void>>(
      find.byKey(const Key('library_import_button')),
    );
    expect(importButton.enabled, isFalse);

    completer.complete(const []);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_importing_overlay')), findsNothing);
  });

  testWidgets('觸發單檔/多檔匯入後，匯入完成前畫面顯示處理中狀態，完成後恢復正常',
      (tester) async {
    const filePickerChannel =
        MethodChannel('miguelruivo.flutter.plugins.filepicker');
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePickerChannel, null);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, (call) async {
      if (call.method == 'custom') {
        return [
          {
            'name': 'book.epub',
            'path': '/tmp/book.epub',
            'size': 100,
            'bytes': null,
            'identifier': 'content://example/book.epub',
          },
        ];
      }
      return null;
    });

    final importService = FakeBookImportService();
    final completer = Completer<List<Book>>();
    importService.pendingCompleter = completer;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: importService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 此時書架為空清單狀態，「library_empty_import_button」是可觸及的匯入
    // 入口，用來一併驗證「其他匯入觸發點」在處理中也會被停用。
    expect(find.byKey(const Key('library_empty_import_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_import_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_import_files_option')));
    // FilePicker.pickFiles() 透過模擬的原生 MethodChannel 立即回傳一筆結果，
    // 接著 importFiles() 進入 pending 狀態（completer 尚未 complete）。同樣
    // 不可用 pumpAndSettle()，改用固定時長的 pump()。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('library_importing_overlay')), findsOneWidget);
    expect(find.text('匯入中...'), findsOneWidget);

    final emptyImportButton = tester.widget<ElevatedButton>(
      find.byKey(const Key('library_empty_import_button')),
    );
    expect(emptyImportButton.onPressed, isNull);

    completer.complete(const []);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_importing_overlay')), findsNothing);
  });

  testWidgets('匯入過程拋出例外時，處理中狀態仍正確解除，畫面恢復正常', (tester) async {
    const folderPickerChannel = MethodChannel('elinkbook/folder_picker');
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(folderPickerChannel, null);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(folderPickerChannel, (call) async {
      if (call.method == 'pickFolder') {
        return 'content://example/tree/folder';
      }
      return null;
    });

    final importService = FakeBookImportService();
    final completer = Completer<List<Book>>();
    importService.pendingCompleter = completer;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: importService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_import_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_import_folder_option')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_import_folder_confirm')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('library_importing_overlay')), findsOneWidget);

    completer.completeError(Exception('模擬匯入失敗'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_importing_overlay')), findsNothing);
  });
```

- [ ] **Step 3: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/library_screen_test.dart`
Expected: FAIL——新增的 3 項測試因找不到 `Key('library_importing_overlay')`、`PopupMenuButton.enabled` 恆為 `true`、或 `ElevatedButton.onPressed` 非 `null` 而失敗。

- [ ] **Step 4: 實作——新增 `_isImporting` 狀態欄位**

打開 `app/lib/screens/library_screen.dart`。在 `_LibraryScreenState` 類別現有的欄位宣告區塊（第 37-45 行，`Set<String>? _selectedBookIds;` 之後）新增一個欄位：

```dart
  bool _isImporting = false;
```

- [ ] **Step 5: 實作——`_pickAndImportFiles()` 加上處理中狀態**

把現有的 `_pickAndImportFiles()` 方法（原第 104-120 行）整段換成：

```dart
  Future<void> _pickAndImportFiles() async {
    try {
      final picked = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['epub', 'pdf', 'txt'],
      );
      if (picked == null || picked.files.isEmpty) return;
      final uris =
          picked.files.map((f) => f.identifier).whereType<String>().toList();
      if (uris.isEmpty) return;
      setState(() => _isImporting = true);
      await widget.importService.importFiles(uris);
      await _loadBooks();
    } catch (_) {
      // 匯入失敗時靜默吞掉，避免異常傳播破壞 widget 樹或留下不一致狀態
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }
```

- [ ] **Step 6: 實作——`_pickAndImportFolder()` 加上處理中狀態**

把現有的 `_pickAndImportFolder()` 方法（原第 122-141 行）整段換成：

```dart
  Future<void> _pickAndImportFolder() async {
    try {
      final folderUri =
          await _folderPickerChannel.invokeMethod<String>('pickFolder');
      if (folderUri == null) return;
      // pickFolder 對應真實系統資料夾選擇器，使用者操作時間可能很長；
      // 確認畫面在這段等待期間沒有被 pop/dispose，才能安全使用 context。
      if (!mounted) return;
      final autoGroup = await _confirmAutoGroupByFolderName();
      if (autoGroup == null) return;
      setState(() => _isImporting = true);
      await widget.importService.importFolder(
        folderUri,
        autoGroupByFolderName: autoGroup,
      );
      await _loadGroups();
      await _loadBooks();
    } catch (_) {
      // 匯入失敗時靜默吞掉，避免異常傳播破壞 widget 樹或留下不一致狀態
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }
```

- [ ] **Step 7: 實作——`build()` 疊加處理中覆蓋層**

把現有的 `build()` 方法（原第 276-304 行）整段換成：

```dart
  @override
  Widget build(BuildContext context) {
    final books = _books;
    return PopScope(
      canPop: !_inSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _inSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: _inSelectionMode
            ? _buildSelectionAppBar()
            : _buildNormalAppBar(books),
        body: books == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  Column(
                    children: [
                      _buildGroupTabs(),
                      Expanded(
                        child: books.isEmpty
                            ? _buildEmptyState()
                            : _buildBookList(books),
                      ),
                    ],
                  ),
                  if (_isImporting) _buildImportingOverlay(),
                ],
              ),
      ),
    );
  }

  Widget _buildImportingOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        key: const Key('library_importing_overlay'),
        color: Colors.black38,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('匯入中...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 8: 實作——`_buildNormalAppBar()` 停用匯入選單按鈕**

在 `_buildNormalAppBar(List<Book>? books)` 方法（原第 306-366 行）內，找到 `PopupMenuButton<void>`（`key: const Key('library_import_button')`）這一塊，新增 `enabled` 參數。把：

```dart
        PopupMenuButton<void>(
          key: const Key('library_import_button'),
          icon: const Icon(Icons.add),
          tooltip: '匯入書籍',
          itemBuilder: (context) => [
```

換成：

```dart
        PopupMenuButton<void>(
          key: const Key('library_import_button'),
          icon: const Icon(Icons.add),
          tooltip: '匯入書籍',
          enabled: !_isImporting,
          itemBuilder: (context) => [
```

（其餘 `itemBuilder` 內容與方法其他部分不變。）

- [ ] **Step 9: 實作——`_buildEmptyState()` 停用匯入按鈕**

把現有的 `_buildEmptyState()` 方法（原第 434-449 行）整段換成：

```dart
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('尚未匯入書籍'),
          const SizedBox(height: 12),
          ElevatedButton(
            key: const Key('library_empty_import_button'),
            onPressed: _isImporting ? null : _pickAndImportFiles,
            child: const Text('匯入書籍'),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 10: 執行測試確認通過**

Run: `cd app && flutter test test/screens/library_screen_test.dart`
Expected: PASS，全部測試（既有 + 新增 3 項）皆通過

- [ ] **Step 11: 執行完整測試套件與靜態分析**

Run: `cd app && flutter test`
Expected: PASS，全數通過，無既有測試被本次變更破壞

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 12: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/support/fake_book_import_service.dart app/test/screens/library_screen_test.dart
git commit -m "feat: add importing-in-progress overlay to LibraryScreen"
```

---

## 手動驗證（合併前，需真實裝置）

Task 1 為純 Dart widget test 可驗證，不需要真實裝置即可完成 TDD 循環。但依 Issue 11 驗收標準，合併前仍建議在真實 Android 裝置上手動走一遍：

1. 匯入一個 100MB 以上的大檔案（例如漫畫類 EPUB）。
2. 確認處理期間畫面明確顯示覆蓋層 + 進度指示 + 「匯入中...」文字，App Bar 的匯入按鈕在此期間無法點擊。
3. 確認處理完成後，覆蓋層消失，該書籍連同封面正確出現在書架上。
4. 若書架原本為空，重複步驟 1-3，確認空清單狀態下的「匯入書籍」按鈕同樣在處理中被停用。
