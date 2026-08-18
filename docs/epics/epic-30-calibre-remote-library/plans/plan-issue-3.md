# Epic 30 Issue 3：雙層重複匯入偵測 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `RemoteCatalogScreen` 的目錄瀏覽／下載流程中掛入雙層重複匯入偵測——選檔前置檢查（`findByRemoteBookId`）與下載後指紋比對（`findByContentFingerprint`）——命中時提示使用者是否仍要建立新副本，不強制阻擋。

**Architecture:** 兩個查詢方法（`findByRemoteBookId`/`findByContentFingerprint`）已在 Issue 0 完成並測試（`LibraryRepository`/`SqliteLibraryRepository`/`FakeLibraryRepository` 三件套）。本 Issue 純粹是把既有的查詢能力接進 `RemoteCatalogScreen` 的兩個既有時機點：Layer 1 在 `_toggleSelection()`（使用者勾選書目當下）；Layer 2 在 `_DownloadQueueDialog._downloadOne()`（下載完成寫入暫存檔之後、複製到永久位置之前）。指紋計算透過新的可注入函式型別 `ComputeRemoteFingerprint` 完成，**不**在 widget 內直接呼叫 `computeBookContentFingerprint()`——該函式對非 `content://` 路徑內部使用 `Isolate.run()`，這與 `testWidgets()` 的假時間測試環境不相容（epic-30 Issue 2 `reviews/review-issue-2.md` 已確認此組合會卡死至 10 分鐘逾時，且 `tester.runAsync()` 無法解決），比照 Issue 2 解決 `OpdsClient` 生命週期問題的 `createOpdsClient` 工廠函式注入先例，用同樣手法把這個依賴變成可替換的注入參數。

**Tech Stack:** Flutter widget（`StatefulWidget`/`showDialog`）、既有 `LibraryRepository` 查詢介面、`FakeLibraryRepository`（`test/support/`）。不涉及 schema 變更、不需要新的第三方套件。

**Spec:** `docs/epics/epic-30-calibre-remote-library/spec.md`（「重複匯入偵測（雙層檢查，比照 `epic-29` 機制）」小節）、`docs/epics/epic-30-calibre-remote-library/issues.md`（「Issue 3：雙層重複匯入偵測」）。

## Global Constraints

- 兩層檢查皆為**精確比對**，不做書名/作者模糊比對（`spec.md` 已定案，理由見 `CONTEXT.md`「書籍內容指紋」已知覆蓋率落差）。
- 同一本書若先前用不同格式下載過，因 `remoteBookId` 為書本層級，仍視為重複並提示——不為「格式不同」開特例。
- **本 Issue 範圍排除**：同一批次（同一次「下載已選取」）內兩個不同書目彼此互為重複的偵測——`_importSuccessful()` 只在整個佇列跑完後才一次呼叫 `importFiles()` 寫入資料庫，批次進行中前面已下載成功的項目尚未真正落地到 `LibraryRepository`，Layer 2 的 `findByContentFingerprint()` 查不到「同批次但排在前面」的項目。這是刻意界定的範圍外情境（機率低、需要額外的批次內追蹤狀態才能解決，YAGNI），不是遺漏。
- **本 Issue 範圍排除**：Layer 2 對 EPUB 格式的指紋計算**不**額外呼叫原生 `extractMetadata` 取得 OPF identifier（不比照 `book_import_service_impl.dart` 既有匯入流程的精確做法），直接使用整個暫存檔案的 SHA-256（`computeBookContentFingerprint()` 不傳 `epubIdentifier` 時的預設行為）。已知限制：若 Calibre 伺服器對外提供的 EPUB 位元組與使用者當初直接匯入的原始檔案不完全相同（即使 OPF identifier 相同），此路徑會漏抓為不同書籍——與既有《書籍內容指紋》文件已承認的跨來源覆蓋率落差性質相同，此為 2026-08-18 與使用者確認後的決策，非後續才發現的疏漏。

---

## Task 1：選檔前置重複偵測（Layer 1）＋ `LibraryRepository` 貫穿三層

**Files:**
- Modify: `app/lib/screens/remote_catalog_screen.dart:1-56, 130-152`
- Modify: `app/lib/screens/remote_server_list_screen.dart`
- Modify: `app/lib/screens/library_screen.dart:676-692`
- Test: `app/test/screens/remote_catalog_screen_test.dart`
- Test: `app/test/screens/remote_server_list_screen_test.dart`

**Interfaces:**
- Consumes：`LibraryRepository.findByRemoteBookId(String serverId, String remoteBookId) → Future<Book?>`（`app/lib/library/library_repository.dart:44`，Issue 0 已完成，`SqliteLibraryRepository`／`FakeLibraryRepository` 皆已實作）。
- Produces：`RemoteCatalogScreen` 新增 `required LibraryRepository libraryRepository` 建構參數；`RemoteServerListScreen` 同名新增 `required LibraryRepository libraryRepository` 建構參數並貫穿到 `RemoteCatalogScreen`。後續 Task 2 會沿用這條貫穿路徑。

- [ ] **Step 1: 於 `remote_catalog_screen_test.dart` 新增書目 fixture 與 3 項 Layer 1 測試（預期編譯失敗）**

在 `app/test/screens/remote_catalog_screen_test.dart` 檔案開頭新增 import：

```dart
import 'package:elinkbook/library/models/book.dart';

import '../support/fake_library_repository.dart';
```

在 `entry1`/`entry2` 宣告之後新增書目 fixture 函式與測試專用常數：

```dart
Book _fakeBookMatchingRemote({
  required String id,
  required String remoteServerId,
  required String remoteBookId,
}) {
  return Book(
    id: id,
    title: '已匯入的書',
    format: BookFileFormat.epub,
    filePath: '/books/$id.epub',
    source: BookSource.calibreOpds,
    remoteServerId: remoteServerId,
    remoteBookId: remoteBookId,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

Book _fakeBookWithFingerprint(String id, String fingerprint) {
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

修改 `pumpScreen` helper，新增 `libraryRepository` 參數（預設空的 `FakeLibraryRepository()`）：

```dart
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeOpdsClient opdsClient,
    FakeRemoteServerRepository? repository,
    FakeLibraryRepository? libraryRepository,
    String? feedUrl,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteCatalogScreen(
        server: server,
        repository: repository ?? FakeRemoteServerRepository(),
        libraryRepository: libraryRepository ?? FakeLibraryRepository(),
        createOpdsClient: () => opdsClient,
        importService: FakeBookImportService(),
        feedUrl: feedUrl,
      ),
    ));
    await tester.pumpAndSettle();
  }
```

在 `group('下載與匯入')` **之前**（與既有的分類下鑽／勾選測試同一層級）新增：

```dart
  group('選檔前置重複偵測（Layer 1）', () {
    testWidgets('勾選已存在 remoteServerId/remoteBookId 的書目時彈出重複提示，選擇取消則不勾選', (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      final libraryRepository = FakeLibraryRepository(initialBooks: [
        _fakeBookMatchingRemote(id: 'local-1', remoteServerId: 'srv1', remoteBookId: 'book-1'),
      ]);
      await pumpScreen(tester, opdsClient: opdsClient, libraryRepository: libraryRepository);

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote_catalog_duplicate_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('remote_catalog_duplicate_dialog_cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-1')), findsNothing);
    });

    testWidgets('勾選已存在的書目時彈出重複提示，選擇仍要建立則正常勾選', (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      final libraryRepository = FakeLibraryRepository(initialBooks: [
        _fakeBookMatchingRemote(id: 'local-1', remoteServerId: 'srv1', remoteBookId: 'book-1'),
      ]);
      await pumpScreen(tester, opdsClient: opdsClient, libraryRepository: libraryRepository);

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remote_catalog_duplicate_dialog_confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-1')), findsOneWidget);
    });

    testWidgets('勾選沒有重複紀錄的書目時不彈出提示，直接勾選', (tester) async {
      final opdsClient = FakeOpdsClient(feeds: {
        server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
      });
      await pumpScreen(tester, opdsClient: opdsClient);

      await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote_catalog_duplicate_dialog')), findsNothing);
      expect(find.byKey(const Key('remote_catalog_checkbox_checked_book-1')), findsOneWidget);
    });
  });
```

既有測試「點擊書目可勾選/取消勾選，僅有支援格式的書目可勾選」需要小幅調整——Step 3 會把 `_toggleSelection` 從同步 `void` 改成 `async`（新增一次 `findByRemoteBookId()` 的 await 之後才 `setState()`），單一 `await tester.pump()` 可能來不及讓 microtask 完全落地、導致間歇性 flaky。把這個測試裡三處 `await tester.pump();`（緊接在 `tester.tap()` 之後的那三處）改為 `await tester.pumpAndSettle();`，斷言本身不變。其餘既有測試維持不變，它們此刻已改用未帶 `libraryRepository` 的 `pumpScreen`（會使用預設的空 `FakeLibraryRepository()`，等同 Layer 1 永遠不命中），行為不受影響。

在 `group('下載與匯入')` 內部，逐一在每個直接呼叫 `tester.pumpWidget(MaterialApp(home: RemoteCatalogScreen(...)))`（而非透過 `pumpScreen` helper）的既有測試中，於 `repository: FakeRemoteServerRepository(),` 這一行之後新增一行 `libraryRepository: FakeLibraryRepository(),`——這個群組內共有 7 處這樣的建構呼叫（「勾選單本書下載」「多格式選擇」「多選批次下載」「下載失敗」「下載取消」「引數驗證」，以及尚未新增的 Layer 2 測試，見 Task 2）。

- [ ] **Step 2: 執行測試確認編譯失敗**

Run: `flutter test test/screens/remote_catalog_screen_test.dart`
Expected: FAIL——編譯錯誤，`RemoteCatalogScreen` 建構子沒有 `libraryRepository` 具名參數。這是預期中的失敗（比照 Issue 2 Task 1 `createOpdsClient` 工廠函式重構同樣手法：新增必要建構參數會讓整個檔案先編譯失敗，Step 3 補上生產程式碼後才會一起變綠）。

- [ ] **Step 3: 修改 `RemoteCatalogScreen`，新增 `libraryRepository` 參數與 Layer 1 檢查邏輯**

修改 `app/lib/screens/remote_catalog_screen.dart` 開頭 import 區塊，新增：

```dart
import '../library/library_repository.dart';
```

修改 `RemoteCatalogScreen` 類別（第 30-55 行）：

```dart
class RemoteCatalogScreen extends StatefulWidget {
  final RemoteServerProfile server;
  final RemoteServerRepository repository;
  final LibraryRepository libraryRepository;
  final OpdsClient Function() createOpdsClient;
  final BookImportService importService;

  /// `null` 代表載入 [server.baseUrl]（站點根目錄）；非 `null` 時載入指定
  /// 的分類/分頁 Feed（點擊 [OpdsNavigationLink] 下鑽時使用）。
  final String? feedUrl;

  /// AppBar 標題，`null` 時使用 [server.name]（根目錄畫面）。
  final String? title;

  const RemoteCatalogScreen({
    super.key,
    required this.server,
    required this.repository,
    required this.libraryRepository,
    required this.createOpdsClient,
    required this.importService,
    this.feedUrl,
    this.title,
  });

  @override
  State<RemoteCatalogScreen> createState() => _RemoteCatalogScreenState();
}
```

修改 `_openSubsection`（第 130-141 行），新增 `libraryRepository` 貫穿：

```dart
  void _openSubsection(OpdsNavigationLink link) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => RemoteCatalogScreen(
        server: widget.server,
        repository: widget.repository,
        libraryRepository: widget.libraryRepository,
        createOpdsClient: widget.createOpdsClient,
        importService: widget.importService,
        feedUrl: link.href,
        title: link.title,
      ),
    ));
  }
```

修改 `_toggleSelection`（第 143-152 行），改為 `async` 並加入 Layer 1 前置檢查：

```dart
  Future<void> _toggleSelection(OpdsEntry entry) async {
    if (!_isSelectable(entry)) return;
    if (_selectedRemoteBookIds.contains(entry.remoteBookId)) {
      setState(() => _selectedRemoteBookIds.remove(entry.remoteBookId));
      return;
    }
    final existing =
        await widget.libraryRepository.findByRemoteBookId(widget.server.id, entry.remoteBookId);
    if (existing != null) {
      if (!mounted) return;
      final proceed = await _showDuplicateConfirmDialog(
        context,
        '「${entry.title}」之前匯入過了，仍要建立新的一份嗎？',
      );
      if (!proceed) return;
    }
    if (!mounted) return;
    setState(() => _selectedRemoteBookIds.add(entry.remoteBookId));
  }
```

在檔案最下方（`_DownloadQueueDialogState` 類別結尾之後，檔案最末）新增共用的重複確認彈窗函式（Task 2 的 Layer 2 也會共用這個函式）：

```dart
/// 重複匯入確認彈窗（epic-30-calibre-remote-library Issue 3，spec.md
/// 「重複匯入偵測」）：選檔前置（Layer 1）與下載後指紋比對（Layer 2）
/// 兩層檢查共用同一個確認 UI，只有提示文字不同——精確比對命中不代表
/// 強制阻擋，使用者可選擇仍要建立新副本。
Future<bool> _showDuplicateConfirmDialog(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('remote_catalog_duplicate_dialog'),
      title: const Text('重複的書籍'),
      content: Text(message),
      actions: [
        TextButton(
          key: const Key('remote_catalog_duplicate_dialog_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('remote_catalog_duplicate_dialog_confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('仍要建立'),
        ),
      ],
    ),
  );
  return result ?? false;
}
```

- [ ] **Step 4: 執行測試確認 Layer 1 測試通過**

Run: `flutter test test/screens/remote_catalog_screen_test.dart`
Expected: FAIL——這次改為執行期失敗：`RemoteServerListScreen`／`library_screen.dart` 尚未更新（見下方 Step 5-6），但本檔案（`remote_catalog_screen_test.dart`）本身應已全數通過，因為它只直接建構 `RemoteCatalogScreen`，不經過 `RemoteServerListScreen`。

- [ ] **Step 5: 貫穿 `RemoteServerListScreen`**

修改 `app/lib/screens/remote_server_list_screen.dart` 開頭 import 區塊，新增：

```dart
import '../library/library_repository.dart';
```

修改 `RemoteServerListScreen` 類別欄位與建構子：

```dart
class RemoteServerListScreen extends StatefulWidget {
  final RemoteServerRepository repository;
  final LibraryRepository libraryRepository;
  final OpdsClient Function() createOpdsClient;
  final BookImportService importService;

  const RemoteServerListScreen({
    super.key,
    required this.repository,
    required this.libraryRepository,
    required this.createOpdsClient,
    required this.importService,
  });
```

修改 `_openCatalog`：

```dart
  void _openCatalog(RemoteServerProfile profile) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => RemoteCatalogScreen(
        server: profile,
        repository: widget.repository,
        libraryRepository: widget.libraryRepository,
        createOpdsClient: widget.createOpdsClient,
        importService: widget.importService,
      ),
    ));
  }
```

修改 `app/test/screens/remote_server_list_screen_test.dart` 的 `pumpScreen` helper，新增 import：

```dart
import '../support/fake_library_repository.dart';
```

並修改建構呼叫：

```dart
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeRemoteServerRepository repository,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteServerListScreen(
        repository: repository,
        libraryRepository: FakeLibraryRepository(),
        createOpdsClient: () => FakeOpdsClient(),
        importService: FakeBookImportService(),
      ),
    ));
    await tester.pumpAndSettle();
  }
```

- [ ] **Step 6: 貫穿 `LibraryScreen`**

修改 `app/lib/screens/library_screen.dart` 第 684-689 行，新增一行：

```dart
                  builder: (context) => RemoteServerListScreen(
                    repository: widget.remoteServerRepository!,
                    libraryRepository: widget.repository,
                    createOpdsClient: widget.createOpdsClient!,
                    importService: widget.importService,
                  ),
```

（`widget.repository` 即 `LibraryScreen` 既有的 `LibraryRepository` 欄位，非新增；`LibraryScreen` 本身不需要新增任何建構參數。）

- [ ] **Step 7: 執行全專案測試確認零回歸**

Run: `flutter analyze && flutter test`
Expected: `flutter analyze` 乾淨；`flutter test` 全數通過，零回歸。

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/remote_catalog_screen.dart app/lib/screens/remote_server_list_screen.dart app/lib/screens/library_screen.dart app/test/screens/remote_catalog_screen_test.dart app/test/screens/remote_server_list_screen_test.dart
git commit -m "feat(epic-30): Issue 3 Task 1 - 選檔前置重複偵測（Layer 1）"
```

---

## Task 2：下載後指紋比對（Layer 2）＋ `ComputeRemoteFingerprint` 注入 seam

**Files:**
- Modify: `app/lib/library/book_content_fingerprint.dart`
- Modify: `app/lib/screens/remote_catalog_screen.dart`
- Modify: `app/lib/screens/remote_server_list_screen.dart`
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/main.dart`
- Create: `app/test/support/fake_fingerprint_computer.dart`
- Test: `app/test/screens/remote_catalog_screen_test.dart`
- Test: `app/test/screens/remote_server_list_screen_test.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 貫穿完成的 `libraryRepository` 參數鏈（`RemoteCatalogScreen`/`RemoteServerListScreen`）；`LibraryRepository.findByContentFingerprint(String fingerprint) → Future<Book?>`（Issue 0 已完成）；`computeBookContentFingerprint(String filePath, BookFileFormat format, {String? epubIdentifier}) → Future<String>`（`app/lib/library/book_content_fingerprint.dart:33`，既有函式不變動）。
- Produces：新型別 `typedef ComputeRemoteFingerprint = Future<String> Function(String filePath, BookFileFormat format)`（定義於 `book_content_fingerprint.dart`）；`RemoteCatalogScreen`/`RemoteServerListScreen`/`LibraryScreen` 新增 `computeFingerprint` 建構參數（前兩者 `required`，`LibraryScreen` 為 `ComputeRemoteFingerprint?` 可選，比照 `createOpdsClient` 既有可選模式）；`main.dart` 提供生產環境預設值。

- [ ] **Step 1: 新增 `ComputeRemoteFingerprint` 型別與 `FakeFingerprintComputer` 測試替身**

修改 `app/lib/library/book_content_fingerprint.dart`，在 `computeBookContentFingerprint` 函式宣告**之前**新增：

```dart
/// 內容指紋計算函式型別（epic-30-calibre-remote-library Issue 3，
/// spec.md「重複匯入偵測」第二層檢查）：`RemoteCatalogScreen` 的下載佇列
/// 透過這個型別注入 [computeBookContentFingerprint]，而不直接呼叫該
/// 函式——該函式對非 `content://` 路徑內部使用 `Isolate.run()`，這與
/// `testWidgets()` 的假時間測試環境不相容（epic-30 Issue 2
/// `reviews/review-issue-2.md` 已確認此組合會卡死至 10 分鐘逾時，
/// `tester.runAsync()` 亦無法解決），widget test 需要能替換成不觸碰
/// Isolate 的假函式，比照 `OpdsClient Function() createOpdsClient`
/// 既有的工廠函式注入先例。
typedef ComputeRemoteFingerprint = Future<String> Function(
  String filePath,
  BookFileFormat format,
);
```

新增檔案 `app/test/support/fake_fingerprint_computer.dart`：

```dart
import 'package:elinkbook/library/book_content_fingerprint.dart';
import 'package:elinkbook/library/models/library_enums.dart';

/// 供 widget test 使用的 [ComputeRemoteFingerprint] 假實作，避免測試環境
/// 觸碰真實 `computeBookContentFingerprint()` 的 `Isolate.run()`（見
/// `book_content_fingerprint.dart` 對 [ComputeRemoteFingerprint] 的文件
/// 說明）。預設每次呼叫回傳固定值 [nextFingerprint]（預設
/// `'fake-fingerprint'`），測試可依情境覆寫來模擬「這個下載內容與本機某
/// 本書指紋相同」。[calls] 記錄每次呼叫的 `filePath`，供測試驗證呼叫
/// 時機（例如「只在下載成功後、複製到永久位置之前呼叫」）。
class FakeFingerprintComputer {
  String nextFingerprint = 'fake-fingerprint';
  final List<String> calls = [];

  Future<String> call(String filePath, BookFileFormat format) async {
    calls.add(filePath);
    return nextFingerprint;
  }
}
```

- [ ] **Step 2: 於 `remote_catalog_screen_test.dart` 新增 Layer 2 測試（預期編譯失敗）**

在 `app/test/screens/remote_catalog_screen_test.dart` 開頭新增 import：

```dart
import '../support/fake_fingerprint_computer.dart';
```

修改 `pumpScreen` helper，新增 `computeFingerprint` 參數：

```dart
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeOpdsClient opdsClient,
    FakeRemoteServerRepository? repository,
    FakeLibraryRepository? libraryRepository,
    FakeFingerprintComputer? fingerprintComputer,
    String? feedUrl,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteCatalogScreen(
        server: server,
        repository: repository ?? FakeRemoteServerRepository(),
        libraryRepository: libraryRepository ?? FakeLibraryRepository(),
        computeFingerprint: (fingerprintComputer ?? FakeFingerprintComputer()).call,
        createOpdsClient: () => opdsClient,
        importService: FakeBookImportService(),
        feedUrl: feedUrl,
      ),
    ));
    await tester.pumpAndSettle();
  }
```

在 `group('下載與匯入')` 內，於 7 處既有的直接 `RemoteCatalogScreen(...)` 建構呼叫中，各自新增一行 `computeFingerprint: (path, format) async => 'unused-fingerprint',`（緊接在 Task 1 新增的 `libraryRepository: FakeLibraryRepository(),` 之後）。

在 `group('下載與匯入')` 內新增一個新的子群組（緊接在既有測試之後）：

```dart
    group('下載後指紋比對（Layer 2）', () {
      testWidgets('下載後偵測到與本機書籍內容指紋相同時彈出提示，選擇不建立新副本則刪除暫存檔並標記為略過',
          (tester) async {
        final opdsClient = FakeOpdsClient(feeds: {
          server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
        });
        final libraryRepository = FakeLibraryRepository(initialBooks: [
          _fakeBookWithFingerprint('local-1', 'dup-fingerprint'),
        ]);
        final fingerprintComputer = FakeFingerprintComputer()..nextFingerprint = 'dup-fingerprint';
        final importService = FakeBookImportService();
        await tester.pumpWidget(MaterialApp(
          home: RemoteCatalogScreen(
            server: server,
            repository: FakeRemoteServerRepository(),
            libraryRepository: libraryRepository,
            computeFingerprint: fingerprintComputer.call,
            createOpdsClient: () => opdsClient,
            importService: importService,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
        await tester.pump();

        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
          if (find.byKey(const Key('remote_catalog_duplicate_dialog')).evaluate().isNotEmpty) break;
        }

        expect(find.byKey(const Key('remote_catalog_duplicate_dialog')), findsOneWidget);
        await tester.tap(find.byKey(const Key('remote_catalog_duplicate_dialog_cancel')));
        await tester.pumpAndSettle();

        expect(find.text('重複已略過（未匯入）'), findsOneWidget);
        expect(importService.lastImportCall, isNull);
        expect(
          Directory(p.join(tempRoot.path, 'remote_download_temp')).listSync(),
          isEmpty,
        );
      });

      testWidgets('下載後偵測到重複時選擇仍要建立新副本，正常完成匯入', (tester) async {
        final opdsClient = FakeOpdsClient(feeds: {
          server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
        });
        final libraryRepository = FakeLibraryRepository(initialBooks: [
          _fakeBookWithFingerprint('local-1', 'dup-fingerprint'),
        ]);
        final fingerprintComputer = FakeFingerprintComputer()..nextFingerprint = 'dup-fingerprint';
        final importService = FakeBookImportService();
        await tester.pumpWidget(MaterialApp(
          home: RemoteCatalogScreen(
            server: server,
            repository: FakeRemoteServerRepository(),
            libraryRepository: libraryRepository,
            computeFingerprint: fingerprintComputer.call,
            createOpdsClient: () => opdsClient,
            importService: importService,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
        await tester.pump();

        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
          if (find.byKey(const Key('remote_catalog_duplicate_dialog')).evaluate().isNotEmpty) break;
        }

        await tester.tap(find.byKey(const Key('remote_catalog_duplicate_dialog_confirm')));
        await tester.pump();

        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(find.text('完成'), findsWidgets);
        expect(importService.lastImportCall, isNotNull);
      });

      testWidgets('下載後未偵測到重複時不彈出提示，直接完成', (tester) async {
        final opdsClient = FakeOpdsClient(feeds: {
          server.baseUrl: const OpdsFeed(title: '根目錄', entries: [entry1]),
        });
        final importService = FakeBookImportService();
        await tester.pumpWidget(MaterialApp(
          home: RemoteCatalogScreen(
            server: server,
            repository: FakeRemoteServerRepository(),
            libraryRepository: FakeLibraryRepository(),
            computeFingerprint: FakeFingerprintComputer().call,
            createOpdsClient: () => opdsClient,
            importService: importService,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
        await tester.pump();

        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('remote_catalog_duplicate_dialog')), findsNothing);
        expect(find.text('完成'), findsWidgets);
        expect(importService.lastImportCall, isNotNull);
      });
    });
```

在檔案開頭新增 `path` 套件 import（供上方 `p.join()` 使用）：

```dart
import 'package:path/path.dart' as p;
```

- [ ] **Step 3: 執行測試確認編譯失敗**

Run: `flutter test test/screens/remote_catalog_screen_test.dart`
Expected: FAIL——編譯錯誤，`RemoteCatalogScreen` 建構子沒有 `computeFingerprint` 具名參數。

- [ ] **Step 4: 修改 `RemoteCatalogScreen`／`_DownloadQueueDialog`，新增 `computeFingerprint` 參數與 Layer 2 檢查邏輯**

修改 `app/lib/screens/remote_catalog_screen.dart` 開頭 import，新增：

```dart
import '../library/book_content_fingerprint.dart';
```

修改 `RemoteCatalogScreen` 類別欄位與建構子（延續 Task 1 的版本，新增一行欄位＋一行建構參數）：

```dart
class RemoteCatalogScreen extends StatefulWidget {
  final RemoteServerProfile server;
  final RemoteServerRepository repository;
  final LibraryRepository libraryRepository;
  final ComputeRemoteFingerprint computeFingerprint;
  final OpdsClient Function() createOpdsClient;
  final BookImportService importService;

  final String? feedUrl;
  final String? title;

  const RemoteCatalogScreen({
    super.key,
    required this.server,
    required this.repository,
    required this.libraryRepository,
    required this.computeFingerprint,
    required this.createOpdsClient,
    required this.importService,
    this.feedUrl,
    this.title,
  });

  @override
  State<RemoteCatalogScreen> createState() => _RemoteCatalogScreenState();
}
```

修改 `_openSubsection`，貫穿 `computeFingerprint`：

```dart
  void _openSubsection(OpdsNavigationLink link) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => RemoteCatalogScreen(
        server: widget.server,
        repository: widget.repository,
        libraryRepository: widget.libraryRepository,
        computeFingerprint: widget.computeFingerprint,
        createOpdsClient: widget.createOpdsClient,
        importService: widget.importService,
        feedUrl: link.href,
        title: link.title,
      ),
    ));
  }
```

修改 `_startDownload()` 建構 `_DownloadQueueDialog` 處，新增兩個具名參數：

```dart
      builder: (context) => _DownloadQueueDialog(
        queue: queue,
        client: _client,
        server: widget.server,
        password: _password,
        importService: widget.importService,
        libraryRepository: widget.libraryRepository,
        computeFingerprint: widget.computeFingerprint,
      ),
```

修改 `_DownloadItemStatus` enum，新增兩個值：

```dart
enum _DownloadItemStatus { pending, downloading, checkingDuplicate, done, duplicateSkipped, failed, cancelled }
```

修改 `_DownloadQueueDialog` 類別欄位與建構子：

```dart
class _DownloadQueueDialog extends StatefulWidget {
  final List<_DownloadQueueItem> queue;
  final OpdsClient client;
  final RemoteServerProfile server;
  final String? password;
  final BookImportService importService;
  final LibraryRepository libraryRepository;
  final ComputeRemoteFingerprint computeFingerprint;

  const _DownloadQueueDialog({
    required this.queue,
    required this.client,
    required this.server,
    required this.password,
    required this.importService,
    required this.libraryRepository,
    required this.computeFingerprint,
  });

  @override
  State<_DownloadQueueDialog> createState() => _DownloadQueueDialogState();
}
```

修改 `_downloadOne(int index)`：在 `await widget.client.downloadBook(...)` 呼叫**之後**、`final docsDir = await getApplicationDocumentsDirectory();` **之前**插入 Layer 2 檢查（其餘程式碼不變）：

```dart
      await widget.client.downloadBook(
        widget.server,
        item.acquisition,
        tempPath,
        password: widget.password,
        cancellationToken: token,
      );

      if (!mounted) return;
      setState(() => _statuses[index] = _DownloadItemStatus.checkingDuplicate);
      final fingerprint = await widget.computeFingerprint(tempPath, item.acquisition.format!);
      final existingByFingerprint = await widget.libraryRepository.findByContentFingerprint(fingerprint);
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

      final docsDir = await getApplicationDocumentsDirectory();
```

修改 `_statusLabel()`，新增兩個 case：

```dart
  String _statusLabel(_DownloadItemStatus status) {
    switch (status) {
      case _DownloadItemStatus.pending:
        return '等待中';
      case _DownloadItemStatus.downloading:
        return '下載中';
      case _DownloadItemStatus.checkingDuplicate:
        return '比對重複中';
      case _DownloadItemStatus.done:
        return '完成';
      case _DownloadItemStatus.duplicateSkipped:
        return '重複已略過（未匯入）';
      case _DownloadItemStatus.failed:
        return '失敗';
      case _DownloadItemStatus.cancelled:
        return '已取消';
    }
  }
```

`canRetry` 判斷式（`status == _DownloadItemStatus.failed || status == _DownloadItemStatus.cancelled`）維持不變——`duplicateSkipped` 是終態，刻意不提供重試按鈕（使用者已在彈窗中明確做出選擇，YAGNI）。`trailing` 的取消按鈕判斷式（`status == _DownloadItemStatus.downloading`）也維持不變——`checkingDuplicate` 狀態沒有可取消的操作（指紋計算是本機運算，非網路下載）。

- [ ] **Step 5: 執行測試確認 `remote_catalog_screen_test.dart` 通過**

Run: `flutter test test/screens/remote_catalog_screen_test.dart`
Expected: PASS，全部測試（Task 1 新增的 3 項＋既有測試＋本 Task 新增的 3 項）通過。

- [ ] **Step 6: 貫穿 `RemoteServerListScreen`／`LibraryScreen`／`main.dart`**

修改 `app/lib/screens/remote_server_list_screen.dart` 開頭 import，新增：

```dart
import '../library/book_content_fingerprint.dart';
```

修改 `RemoteServerListScreen` 類別欄位與建構子：

```dart
class RemoteServerListScreen extends StatefulWidget {
  final RemoteServerRepository repository;
  final LibraryRepository libraryRepository;
  final ComputeRemoteFingerprint computeFingerprint;
  final OpdsClient Function() createOpdsClient;
  final BookImportService importService;

  const RemoteServerListScreen({
    super.key,
    required this.repository,
    required this.libraryRepository,
    required this.computeFingerprint,
    required this.createOpdsClient,
    required this.importService,
  });
```

修改 `_openCatalog`：

```dart
  void _openCatalog(RemoteServerProfile profile) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => RemoteCatalogScreen(
        server: profile,
        repository: widget.repository,
        libraryRepository: widget.libraryRepository,
        computeFingerprint: widget.computeFingerprint,
        createOpdsClient: widget.createOpdsClient,
        importService: widget.importService,
      ),
    ));
  }
```

修改 `app/test/screens/remote_server_list_screen_test.dart`，新增 import：

```dart
import '../support/fake_fingerprint_computer.dart';
```

修改 `pumpScreen` helper：

```dart
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeRemoteServerRepository repository,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteServerListScreen(
        repository: repository,
        libraryRepository: FakeLibraryRepository(),
        computeFingerprint: FakeFingerprintComputer().call,
        createOpdsClient: () => FakeOpdsClient(),
        importService: FakeBookImportService(),
      ),
    ));
    await tester.pumpAndSettle();
  }
```

修改 `app/lib/screens/library_screen.dart` 開頭 import，新增：

```dart
import '../library/book_content_fingerprint.dart';
```

修改 `LibraryScreen` 類別，新增欄位與建構參數（緊接在既有 `createOpdsClient` 之後）：

```dart
  final OpdsClient Function()? createOpdsClient;
  final ComputeRemoteFingerprint? computeFingerprint;
```

```dart
    this.createOpdsClient,
    this.computeFingerprint,
```

修改第 676-692 行的遠端書庫入口按鈕，條件與建構呼叫皆新增 `computeFingerprint`：

```dart
        if (widget.remoteServerRepository != null &&
            widget.createOpdsClient != null &&
            widget.computeFingerprint != null)
          IconButton(
            key: const Key('library_remote_library_button'),
            icon: const Icon(Icons.cloud_outlined),
            tooltip: '遠端書庫',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => RemoteServerListScreen(
                    repository: widget.remoteServerRepository!,
                    libraryRepository: widget.repository,
                    computeFingerprint: widget.computeFingerprint!,
                    createOpdsClient: widget.createOpdsClient!,
                    importService: widget.importService,
                  ),
                ),
              );
            },
          ),
```

修改 `app/test/screens/library_screen_test.dart` 第 3165-3173 行附近，既有測試「顯示遠端書庫入口按鈕」（`remoteServerRepository`/`createOpdsClient` 皆已設定的那個測試）新增一行：

```dart
        home: LibraryScreen(
          repository: repository,
          importService: importService,
          prefsManager: FakeReaderPrefsManager(),
          remoteServerRepository: FakeRemoteServerRepository(),
          createOpdsClient: () => FakeOpdsClient(),
          computeFingerprint: (path, format) async => 'test-fingerprint',
        ),
```

（因為新增條件會讓這個既有的按鈕可見性測試在沒有 `computeFingerprint` 時失敗——按鈕不會顯示。）

修改 `app/lib/main.dart`：確認開頭已 import `library/book_content_fingerprint.dart`（若尚未 import，新增），並在 `ElinkBookApp` 類別欄位與建構子（第 123-163 行附近，緊接在 `createOpdsClient` 之後）新增：

```dart
  final OpdsClient Function()? createOpdsClient;
  final ComputeRemoteFingerprint? computeFingerprint;
```

```dart
    this.createOpdsClient,
    this.computeFingerprint,
```

在 `_ElinkBookAppState.build()` 中建構 `LibraryScreen` 處，找到既有的這兩行（不動）：

```dart
        remoteServerRepository: widget.remoteServerRepository,
        createOpdsClient: widget.createOpdsClient,
```

在其後新增一行：

```dart
        remoteServerRepository: widget.remoteServerRepository,
        createOpdsClient: widget.createOpdsClient,
        computeFingerprint: widget.computeFingerprint,
```

在 `main()` 函式建構 `ElinkBookApp(...)` 處（第 97-118 行附近），於 `createOpdsClient: () => OpdsHttpClient(),` 之後新增：

```dart
      createOpdsClient: () => OpdsHttpClient(),
      computeFingerprint: (path, format) => computeBookContentFingerprint(path, format),
```

- [ ] **Step 7: 執行全專案測試確認零回歸**

Run: `flutter analyze && flutter test`
Expected: `flutter analyze` 乾淨；`flutter test` 全數通過，零回歸。

- [ ] **Step 8: Commit**

```bash
git add app/lib/library/book_content_fingerprint.dart app/lib/screens/remote_catalog_screen.dart app/lib/screens/remote_server_list_screen.dart app/lib/screens/library_screen.dart app/lib/main.dart app/test/support/fake_fingerprint_computer.dart app/test/screens/remote_catalog_screen_test.dart app/test/screens/remote_server_list_screen_test.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-30): Issue 3 Task 2 - 下載後指紋比對（Layer 2）"
```

---

## Self-Review（撰寫計畫時的自我檢查）

**Spec 涵蓋度**：`spec.md`「重複匯入偵測」4 個條列點——(1) 選檔前置檢查→Task 1；(2) 下載後指紋比對→Task 2；(3) 不同格式仍判定重複→`remoteBookId` 為書本層級天然滿足，不需要額外程式碼（Layer 1 檢查的是 `entry.remoteBookId`，與 acquisition 格式無關）；(4) 精確比對不做模糊比對→兩層皆直接用既有 `findByRemoteBookId`/`findByContentFingerprint` 的精確查詢，未新增任何模糊比對邏輯。`issues.md` Issue 3 的單元測試要求（前置命中／指紋命中／取消清暫存檔／仍要匯入完成／不同格式仍判定重複）除「不同格式仍判定重複」外皆有對應測試；「不同格式仍判定重複」不需要獨立測試案例——Layer 1 測試已證明比對邏輯只看 `remoteBookId`，與格式無關，重複寫一個換格式的測試不會增加驗證力（YAGNI）。

**型別一致性**：`ComputeRemoteFingerprint` 型別在 Task 2 Step 1 定義後，Task 2 Step 4／6 的所有使用處（`RemoteCatalogScreen`／`_DownloadQueueDialog`／`RemoteServerListScreen`／`LibraryScreen`／`main.dart`）簽章一致皆為 `Future<String> Function(String, BookFileFormat)`。`libraryRepository` 欄位命名在 Task 1 全部三個檔案一致。

**佔位符掃描**：全文無 TBD／implement later／"add appropriate error handling" 等字樣；所有程式碼步驟皆附完整可執行程式碼。
