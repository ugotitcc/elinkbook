import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager.dart';
import 'package:elinkbook/screens/library_screen.dart';
import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import '../support/fake_highlights_repository.dart';
import '../support/fake_notes_repository.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import '../support/fake_bookmarks_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import '../support/fake_path_provider_platform.dart';
import '../support/fake_share_platform.dart';

void main() {
  late SqliteLibraryRepository libraryRepository;
  late ReaderPrefsManager prefsManager;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 全螢幕模式頻道（epic-19 Issue 1）：ReaderScreen.dispose() 會無條件
    // 呼叫 elinkbook/fullscreen setEnabled(false)，需要全域 mock 避免
    // MissingPluginException。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/fullscreen'),
      (_) async => null,
    );
  });

  setUp(() async {
    // LibraryScreen.initState() 現在會呼叫 SharedPreferences.getInstance()，
    // 純 Dart widget test 環境沒有真正的原生實作，須用官方支援的測試替身。
    SharedPreferences.setMockInitialValues({});
    // LibraryScreen 自 Issue 3 起需要 ReaderPrefsManager（見
    // docs/adr/0007-reader-screen-book-id-contract.md）。這裡的測試情境
    // 本身不涉及版面偏好設定的讀寫，只需要滿足建構參數即可。
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    prefsManager = FakeReaderPrefsManager();
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  testWidgets('圖書庫為空時顯示「尚未匯入書籍」提示與匯入按鈕', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('書架'), findsOneWidget);
    expect(find.text('尚未匯入書籍'), findsOneWidget);
    expect(
      find.byKey(const Key('library_empty_import_button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('library_import_button')), findsOneWidget);
  });

  testWidgets('圖書庫載入資料失敗時，畫面降級顯示空清單狀態而非永遠卡在載入中', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(throwOnListBooks: true),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('尚未匯入書籍'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('有書籍時，書架 grid 呈現正確渲染書籍項目（標題、進度固定 0%）',
      (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢', author: '曹雪芹');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_grid_view')), findsOneWidget);
    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.text('紅樓夢'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('直立（高 > 寬）時，書架封面格數為 3 欄', (tester) async {
    // 800×1200：寬 < 高，MediaQuery.orientation 判定為 portrait。
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final book = _testBook(id: '1', title: '紅樓夢');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final delegate = tester
            .widget<GridView>(find.byKey(const Key('library_grid_view')))
            .gridDelegate
        as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);
  });

  testWidgets('橫放（寬 > 高）時，書架封面格數為 4 欄', (tester) async {
    // 1200×800：寬 > 高，MediaQuery.orientation 判定為 landscape。
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final book = _testBook(id: '1', title: '紅樓夢');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final delegate = tester
            .widget<GridView>(find.byKey(const Key('library_grid_view')))
            .gridDelegate
        as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 4);
  });

  testWidgets(
      '裝置旋轉（MediaQuery 從直立變橫放）後，書架封面欄數即時從 3 變為 4，不需要重新導航或重建整個畫面',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final book = _testBook(id: '1', title: '紅樓夢');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    SliverGridDelegateWithFixedCrossAxisCount currentDelegate() =>
        tester
                .widget<GridView>(find.byKey(const Key('library_grid_view')))
                .gridDelegate
            as SliverGridDelegateWithFixedCrossAxisCount;

    expect(currentDelegate().crossAxisCount, 3);

    // 同一個 pumpWidget 之後直接改變 view 尺寸並重新 pump，模擬裝置旋轉，
    // 不重新導航、不重建 LibraryScreen（比照既有 reader_screen_test.dart
    // 對 tester.view.physicalSize 的既有使用模式）。
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();

    expect(currentDelegate().crossAxisCount, 4);
  });

  testWidgets('書架封面格狀檢視含欄格間距，避免封面互相緊貼', (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final delegate = tester
            .widget<GridView>(find.byKey(const Key('library_grid_view')))
            .gridDelegate
        as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisSpacing, 8);
    expect(delegate.mainAxisSpacing, 12);
  });

  testWidgets('從閱讀器返回書架時，重新載入書籍清單，避免後續操作以過期資料覆寫最新進度',
      (tester) async {
    // 使用 .txt 格式讓 ReaderScreen 命中「不支援格式」分支（純 Dart 安全路徑，
    // 不觸發 AndroidView），確保 pumpAndSettle 能順利完成。重點是驗證
    // Navigator.pop() 後 _openBook 的 .then() 回呼會呼叫 _loadBooks()，
    // 與實際閱讀器渲染無關。
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      filePath: 'content://example/1.txt',
    );
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0%'), findsOneWidget);

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    // widget test 環境無法真正渲染原生 PlatformView 觸發 ReaderScreen 的
    // 位置寫入路徑，這裡直接呼叫 repository.updateBook 模擬「ReaderScreen
    // 已透過 ReadingPositionRepository 把最新進度寫入資料庫」這個結果
    // （見 Critical 2 審查意見的觸發情境）。
    await repository.updateBook(Book(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      format: BookFileFormat.txt,
      filePath: 'content://example/1.txt',
      source: BookSource.local,
      progress: 0.5,
      groupName: BookGroup.uncategorized,
      createTime: book.createTime,
      lastReadTime: book.lastReadTime,
    ));

    // 返回書架（點擊 ReaderScreen AppBar 的預設返回鍵，等同
    // Navigator.pop()）。
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('50%'), findsOneWidget,
        reason: '返回書架後應重新載入書籍清單，顯示閱讀器寫入的最新進度，'
            '而非停留在舊快照的 0%');
  });

  testWidgets('切換檢視模式按鈕後，書架從 grid 切換為列表呈現', (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢', author: '曹雪芹');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_grid_view')), findsOneWidget);
    expect(find.byKey(const Key('library_list_view')), findsNothing);

    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_grid_view')), findsNothing);
    expect(find.byKey(const Key('library_list_view')), findsOneWidget);
    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
  });

  testWidgets('切換檢視模式後，重新建立 LibraryScreen 仍維持上次選擇（模擬 App 重啟）',
      (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢', author: '曹雪芹');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_grid_view')), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_list_view')), findsOneWidget);

    // 模擬 App 重啟：SharedPreferences.setMockInitialValues 的模擬儲存體會
    // 延續到同一個測試行程內建立的新 LibraryScreen 實例，等同於重啟後讀到
    // 上次寫入的值。
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          key: const Key('library_screen_after_restart'),
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_list_view')), findsOneWidget);
    expect(find.byKey(const Key('library_grid_view')), findsNothing);
  });

  testWidgets('選擇「書名」排序後，書架清單依書名字母順序重新排列', (tester) async {
    final now = DateTime.now();
    final bookB = Book(
      id: '1',
      title: 'B書',
      author: null,
      format: BookFileFormat.epub,
      filePath: 'content://example/1.epub',
      source: BookSource.local,
      createTime: now,
      lastReadTime: now.add(const Duration(minutes: 1)),
    );
    final bookA = Book(
      id: '2',
      title: 'A書',
      author: null,
      format: BookFileFormat.epub,
      filePath: 'content://example/2.epub',
      source: BookSource.local,
      createTime: now,
      lastReadTime: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [bookB, bookA]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    // 兩本書皆為預設「未分類」——「未分類」不使用拼貼格顯示（見【診斷
    // 修正】），故書架上沒有拼貼格 ListTile，只有書籍本身的 ListTile。
    var titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .toList();
    expect(titles, ['B書', 'A書']);

    await tester.tap(find.byKey(const Key('library_sort_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_option_title')));
    await tester.pumpAndSettle();

    titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .toList();
    expect(titles, ['A書', 'B書']);
  });

  testWidgets('排序方式選擇會持久化，重新建立 LibraryScreen 後仍維持上次選擇',
      (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢', author: '曹雪芹');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_sort_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_option_author')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('排序：作者'), findsOneWidget);

    // 模擬 App 重啟
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          key: const Key('library_screen_after_restart'),
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('排序：作者'), findsOneWidget);
  });

  testWidgets(
      '點擊分類拼貼格後只顯示該分類書籍；返回書架後僅顯示未分類書籍與分類拼貼格（已分類書籍不重複列出）',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB =
        _testBook(id: '2', title: 'B書', groupName: BookGroup.uncategorized);
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 【審查修正】bookA 已歸類到「奇幻」，頂層書架不應重複列出，只透過
    // 「奇幻」拼貼格顯示；bookB 是「未分類」，仍照舊直接列在書籍清單中。
    expect(find.byKey(const Key('book_item_1')), findsNothing);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    final filteredScreenFinder = _filteredLibraryScreenFinder('奇幻');
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_1')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_2')),
      ),
      findsNothing,
    );

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    await navigatorState.maybePop();
    await tester.pumpAndSettle();

    expect(find.text('書架'), findsOneWidget);
    expect(find.byKey(const Key('book_item_1')), findsNothing);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);
  });

  testWidgets('管理分類對話框：新增分類後，因無書籍歸屬，書架不會顯示該分類的拼貼格',
      (tester) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_manage_groups_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('library_group_add_field')),
      '奇幻',
    );
    await tester.tap(find.byKey(const Key('library_group_add_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_group_manage_item_奇幻')), findsOneWidget);

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();

    // 新分類目前沒有任何書籍歸屬，_buildGroupTiles() 只保留非空分類，故
    // 書架上不會出現「奇幻」拼貼格（design.md 決策：拼貼格只代表非空分類）。
    expect(find.byKey(const Key('group_tile_奇幻')), findsNothing);
  });

  testWidgets(
      '管理分類對話框：刪除分類前彈出確認對話框，確認後該分類下書籍改顯示於書架頂層的「未分類」書籍清單中',
      (tester) async {
    final book = _testBook(id: '1', title: '奇幻小說', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 刪除前書籍已歸類到「奇幻」，只透過拼貼格顯示，頂層書籍清單看不到它。
    expect(find.byKey(const Key('book_item_1')), findsNothing);

    await tester.tap(find.byKey(const Key('library_manage_groups_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_delete_button_奇幻')));
    await tester.pumpAndSettle();

    expect(find.text('刪除分類'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_group_delete_confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('group_tile_奇幻')), findsNothing);

    // 刪除分類後書籍改列為「未分類」——「未分類」不使用拼貼格顯示，書籍
    // 直接以個別項目呈現在頂層書籍清單中，不需要再點擊任何拼貼格導覽。
    expect(
      find.byKey(Key('group_tile_${BookGroup.uncategorized}')),
      findsNothing,
    );
    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
  });

  testWidgets('管理分類對話框：刪除確認對話框按下取消，分類與所屬書籍皆不受影響', (tester) async {
    final book = _testBook(id: '1', title: '奇幻小說', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_manage_groups_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_delete_button_奇幻')));
    await tester.pumpAndSettle();

    expect(find.text('刪除分類'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_group_manage_item_奇幻')), findsOneWidget);

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('group_tile_奇幻')), findsOneWidget);
    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    final filteredScreenFinder = _filteredLibraryScreenFinder('奇幻');
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_1')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('管理分類對話框：嘗試刪除「未分類」時操作被禁止（找不到刪除/重新命名按鈕）',
      (tester) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_manage_groups_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        Key('library_group_delete_button_${BookGroup.uncategorized}'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        Key('library_group_rename_button_${BookGroup.uncategorized}'),
      ),
      findsNothing,
    );
  });

  testWidgets('管理分類對話框：重新命名分類後，拼貼格顯示新名稱', (tester) async {
    final book = _testBook(id: '1', title: '奇幻小說', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_manage_groups_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_rename_button_奇幻')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('library_group_rename_field')),
      '科幻',
    );
    await tester.tap(find.byKey(const Key('library_group_rename_confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_group_manage_item_科幻')), findsOneWidget);
    expect(find.byKey(const Key('library_group_manage_item_奇幻')), findsNothing);

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('group_tile_科幻')), findsOneWidget);
    expect(find.byKey(const Key('group_tile_奇幻')), findsNothing);
  });

  testWidgets('點擊「選擇資料夾」，確認自動分類開關後，匯入資料夾內書籍並依資料夾名稱建立分類',
      (tester) async {
    const folderPickerChannel = MethodChannel('elinkbook/folder_picker');
    const metadataChannel = MethodChannel('elinkbook/book_metadata');
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(folderPickerChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(metadataChannel, null);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(folderPickerChannel, (call) async {
      if (call.method == 'pickFolder') {
        return 'content://example/tree/folder';
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(metadataChannel, (call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'listFolderContents') {
        return {
          'folderName': '歷史小說',
          'fileUris': ['content://example/tree/folder/document/book1.epub'],
        };
      }
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: BookImportServiceImpl(repository: repository),
          prefsManager: prefsManager,
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
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('group_tile_歷史小說')), findsOneWidget);
  });

  testWidgets('長按書籍卡片後進入選取模式，且該卡片顯示為已選取狀態', (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_selection_app_bar')), findsOneWidget);
    expect(find.text('已選取 1 本'), findsOneWidget);

    final icon = tester.widget<Icon>(
      find.byKey(const Key('book_selection_indicator_1')),
    );
    expect(icon.icon, Icons.check_circle);
  });

  testWidgets('選取模式下點擊其他卡片可加選/取消選；點擊卡片不再導覽進閱讀器', (tester) async {
    final bookA = _testBook(id: '1', title: 'A書');
    final bookB = _testBook(id: '2', title: 'B書');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [bookA, bookB]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    expect(find.text('已選取 1 本'), findsOneWidget);

    await tester.tap(find.byKey(const Key('book_item_2')));
    await tester.pumpAndSettle();
    expect(find.text('已選取 2 本'), findsOneWidget);

    await tester.tap(find.byKey(const Key('book_item_2')));
    await tester.pumpAndSettle();
    expect(find.text('已選取 1 本'), findsOneWidget);
  });

  testWidgets('選取模式下點擊「✕ 取消」後恢復一般瀏覽狀態，且卡片點擊恢復導覽進閱讀器',
      (tester) async {
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      filePath: 'content://example/1.txt',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library_selection_app_bar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_selection_cancel_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_selection_app_bar')), findsNothing);
    expect(find.byKey(const Key('library_sort_button')), findsOneWidget);
    expect(find.byKey(const Key('book_selection_indicator_1')), findsNothing);

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    // 用 .txt 檔名讓 ReaderScreen 命中「不支援格式」分支（純 Dart 安全路徑，
    // 不觸發 AndroidView；見 reader_screen_test.dart 既有模式），只用來證明
    // 「導覽確實發生」，不驗證實際閱讀渲染。
    expect(find.text('閱讀器'), findsOneWidget);
    expect(find.text('不支援的檔案格式'), findsOneWidget);
  });

  testWidgets('選取模式下觸發系統返回鍵時退出選取模式，而非真的離開畫面', (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library_selection_app_bar')), findsOneWidget);

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    await navigatorState.maybePop();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_selection_app_bar')), findsNothing);
    expect(find.text('書架'), findsOneWidget);
  });

  testWidgets('選取多本書後點擊「移動到分類」，選擇目的分類後所有已勾選書籍的分類皆更新',
      (tester) async {
    final bookA =
        _testBook(id: '1', title: 'A書', groupName: BookGroup.uncategorized);
    final bookB =
        _testBook(id: '2', title: 'B書', groupName: BookGroup.uncategorized);
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);
    await repository.upsertGroup('奇幻');

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_item_2')));
    await tester.pumpAndSettle();
    expect(find.text('已選取 2 本'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_move_to_group_button')));
    await tester.pumpAndSettle();
    expect(find.text('移動到分類'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_move_to_group_option_奇幻')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_selection_app_bar')), findsNothing);

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    final filteredScreenFinder = _filteredLibraryScreenFinder('奇幻');
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_1')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_2')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('選取多本 EPUB 書籍後點擊「強制 FXL」，所有已選取書籍的 isFixedLayout 皆變為 true',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A漫畫');
    final bookB = _testBook(id: '2', title: 'B漫畫');
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_item_2')));
    await tester.pumpAndSettle();
    expect(find.text('已選取 2 本'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_force_fxl_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_selection_app_bar')), findsNothing,
        reason: '執行後應立即退出選取模式（比照移動到分類既有行為）');

    final updated = await repository.listBooks();
    expect(updated.firstWhere((b) => b.id == '1').isFixedLayout, isTrue);
    expect(updated.firstWhere((b) => b.id == '2').isFixedLayout, isTrue);
  });

  testWidgets(
      '選取集合混雜 EPUB 與 PDF 時，點擊「強制 FXL」只影響 EPUB、PDF 不受影響也不拋錯',
      (tester) async {
    final epubBook = _testBook(id: '1', title: 'A漫畫');
    final pdfBook = _testBook(
      id: '2',
      title: 'B文件',
      format: BookFileFormat.pdf,
      filePath: 'content://example/2.pdf',
    );
    final repository =
        FakeLibraryRepository(initialBooks: [epubBook, pdfBook]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_item_2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_force_fxl_button')));
    await tester.pumpAndSettle();

    final updated = await repository.listBooks();
    expect(updated.firstWhere((b) => b.id == '1').isFixedLayout, isTrue);
    expect(updated.firstWhere((b) => b.id == '2').isFixedLayout, isNull,
        reason: 'PDF 不具備 isFixedLayout 語意，應完全不受影響');
  });

  testWidgets('選取集合全為非 EPUB 時，「強制 FXL」按鈕仍然顯示（不隱藏/不因格式停用）',
      (tester) async {
    final pdfBook = _testBook(
      id: '1',
      title: 'A文件',
      format: BookFileFormat.pdf,
      filePath: 'content://example/1.pdf',
    );
    final repository = FakeLibraryRepository(initialBooks: [pdfBook]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_force_fxl_button')), findsOneWidget);

    final button = tester.widget<IconButton>(
      find.byKey(const Key('library_force_fxl_button')),
    );
    expect(button.onPressed, isNotNull,
        reason: 'count > 0 時按鈕應可點擊，不因選取內容全為非 EPUB 而停用');
  });

  testWidgets(
      '選取多本 EPUB 書籍後點擊「恢復自動判斷」，對每本已選取書籍呼叫 detectAndCacheEpubLayout',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A漫畫', isFixedLayout: true);
    final bookB = _testBook(id: '2', title: 'B漫畫', isFixedLayout: true);
    final repository = FakeLibraryRepository(
      initialBooks: [bookA, bookB],
      detectedIsFixedLayout: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_item_2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_restore_auto_layout_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_selection_app_bar')), findsNothing);
    expect(
      repository.detectAndCacheEpubLayoutCalls,
      containsAll(['1', '2']),
    );
    final updated = await repository.listBooks();
    expect(updated.firstWhere((b) => b.id == '1').isFixedLayout, isFalse);
    expect(updated.firstWhere((b) => b.id == '2').isFixedLayout, isFalse);
  });

  testWidgets(
      '選取集合混雜 EPUB 與 TXT 時，點擊「恢復自動判斷」只影響 EPUB、TXT 不受影響也不拋錯',
      (tester) async {
    final epubBook = _testBook(id: '1', title: 'A漫畫', isFixedLayout: true);
    final txtBook = _testBook(
      id: '2',
      title: 'B文字書',
      format: BookFileFormat.txt,
      filePath: 'content://example/2.txt',
    );
    final repository = FakeLibraryRepository(
      initialBooks: [epubBook, txtBook],
      detectedIsFixedLayout: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_item_2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_restore_auto_layout_button')));
    await tester.pumpAndSettle();

    expect(repository.detectAndCacheEpubLayoutCalls, ['1']);
  });

  testWidgets('選取集合全為非 EPUB 時，「恢復自動判斷」按鈕仍然顯示（不隱藏/不因格式停用）',
      (tester) async {
    final txtBook = _testBook(
      id: '1',
      title: 'A文字書',
      format: BookFileFormat.txt,
      filePath: 'content://example/1.txt',
    );
    final repository = FakeLibraryRepository(initialBooks: [txtBook]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final button = tester.widget<IconButton>(
      find.byKey(const Key('library_restore_auto_layout_button')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('書架（grid）與列表兩種檢視皆能觸發長按進入選取模式並完成批次移動',
      (tester) async {
    final bookA =
        _testBook(id: '1', title: 'A書', groupName: BookGroup.uncategorized);
    final bookB =
        _testBook(id: '2', title: 'B書', groupName: BookGroup.uncategorized);
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);
    await repository.upsertGroup('奇幻');

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library_list_view')), findsOneWidget);

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final checkbox = tester.widget<Checkbox>(
      find.byKey(const Key('book_selection_indicator_1')),
    );
    expect(checkbox.value, isTrue);

    await tester.tap(find.byKey(const Key('book_item_2')));
    await tester.pumpAndSettle();
    expect(find.text('已選取 2 本'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_move_to_group_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_move_to_group_option_奇幻')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    final filteredScreenFinder = _filteredLibraryScreenFinder('奇幻');
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_1')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_2')),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      '點擊分類拼貼格會推入新的 LibraryScreen 並以該分類篩選；篩選畫面不顯示拼貼格區塊與管理分類按鈕',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB =
        _testBook(id: '2', title: 'B書', groupName: BookGroup.uncategorized);
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    final filteredScreenFinder = _filteredLibraryScreenFinder('奇幻');
    expect(filteredScreenFinder, findsOneWidget);

    // AppBar 標題顯示分類名稱，不是「書架」（此文字在整棵樹中唯一——背景
    // 畫面的拼貼格文字是「奇幻 (1)」而非單獨的「奇幻」，不會誤判）。
    expect(find.text('奇幻'), findsOneWidget);

    // 篩選畫面本身不顯示拼貼格區塊、不顯示「管理分類」按鈕（用 descendant
    // 限定搜尋範圍在篩選畫面內，避免誤判到背景仍掛載的頂層畫面自己的拼貼
    // 格／管理分類按鈕——MaterialPageRoute 預設 maintainState: true，背景
    // 畫面推入新畫面後仍留在 widget 樹中）。
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('group_tile_奇幻')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('library_manage_groups_button')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_1')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_2')),
      ),
      findsNothing,
    );
  });

  testWidgets(
      '從分類篩選畫面把書移到其他分類後返回書架，頂層拼貼格與書籍清單即時反映最新狀態',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB = _testBook(id: '2', title: 'B書', groupName: '科幻');
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('奇幻 (1)'), findsOneWidget);
    expect(find.text('科幻 (1)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    final filteredScreenFinder = _filteredLibraryScreenFinder('奇幻');
    await tester.longPress(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_1')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_move_to_group_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_move_to_group_option_科幻')));
    await tester.pumpAndSettle();

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    await navigatorState.maybePop();
    await tester.pumpAndSettle();

    // bookA 已被移出「奇幻」——「奇幻」拼貼格應消失（剩 0 本，
    // _buildGroupTiles 只保留非空分類），「科幻」拼貼格應顯示 2 本。若
    // _openGroupFilteredView 沒有在返回時呼叫 _loadBooks()，這裡會錯誤地
    // 仍顯示「奇幻 (1)」／「科幻 (1)」的舊快照。
    expect(find.byKey(const Key('group_tile_奇幻')), findsNothing);
    expect(find.text('科幻 (2)'), findsOneWidget);
  });

  testWidgets(
      '【審查修正】從分類篩選畫面內用「選擇資料夾＋自動分類」建立新分類後返回書架，'
      '新分類拼貼格排在「未分類」之前，而非落入孤兒兜底桶排到最後',
      (tester) async {
    const folderPickerChannel = MethodChannel('elinkbook/folder_picker');
    const metadataChannel = MethodChannel('elinkbook/book_metadata');
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(folderPickerChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(metadataChannel, null);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(folderPickerChannel, (call) async {
      if (call.method == 'pickFolder') {
        return 'content://example/tree/folder';
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(metadataChannel, (call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'listFolderContents') {
        return {
          // 刻意選用 name ASC 排序上會落在「奇幻」之前的名稱（一 U+4E00 <
          // 奇 U+5947），讓「正確載入 vs. 落入孤兒兜底桶」兩種情境的拼貼格
          // 順序真的不同，用來偵測 _loadGroups() 是否有確實被呼叫（「未
          // 分類」不使用拼貼格顯示後，不能再用它當排序參考基準點）。
          'folderName': '一般叢書',
          'fileUris': ['content://example/tree/folder/document/book1.epub'],
        };
      }
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    final book = _testBook(id: '1', title: '奇幻小說', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: BookImportServiceImpl(repository: repository),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    // 篩選畫面內的「匯入書籍」入口沒有比照「管理分類」用 groupFilter ==
    // null 隱藏，故仍可在此觸發「選擇資料夾＋自動分類」，建立一個頂層
    // _groups 快照原本不知道的新分類。
    final filteredScreenFinder = _filteredLibraryScreenFinder('奇幻');
    await tester.tap(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('library_import_button')),
      ),
    );
    await tester.pumpAndSettle();
    // PopupMenuButton 的選單項目透過 Overlay 路由渲染，不是觸發它的
    // LibraryScreen 的 descendant，故這裡不能比照上面用 find.descendant
    // 限定範圍——但這個選單同一時間只會有一份，不會有背景/前景重複的問
    // 題，直接用未限定範圍的 find.byKey 即可（比照既有「點擊「選擇資料
    // 夾」...」測試的既有寫法）。
    await tester.tap(find.byKey(const Key('library_import_folder_option')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_import_folder_confirm')));
    await tester.pumpAndSettle();

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    await navigatorState.maybePop();
    await tester.pumpAndSettle();

    // Navigator.pop 會把被彈出的篩選畫面從 widget 樹移除（跟 push 不同，
    // 不會留下背景重複實例），故此時切到列表檢視只會影響剩下的頂層畫面，
    // library_view_mode_toggle 這個 key 在樹中唯一。切到列表檢視是為了用
    // _GroupListTile 的 ListTile.title（純分類名稱，不含數量）方便比對順
    // 序——格狀檢視的 _GroupGridTile 是 InkWell，不是 ListTile。
    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    // 若 _openGroupFilteredView() 的 .then() 沒有一併呼叫 _loadGroups()，
    // 「一般叢書」不在頂層 _groups 快照中，會被 _buildGroupTiles() 的孤兒
    // 兜底桶排到所有「正常註冊」分類（此處只有「奇幻」）之後；正確行為
    // 是「一般叢書」依 name ASC 排序排在「奇幻」之前（一 U+4E00 < 奇
    // U+5947），而非孤兒兜底桶把它排到「奇幻」之後。
    final tileTitles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .where((title) => title == '奇幻' || title == '一般叢書')
        .toList();
    expect(tileTitles, ['一般叢書', '奇幻']);
  });

  testWidgets('選取模式下 AppBar 顯示刪除按鈕，取消刪除確認對話框不會呼叫 deleteBook',
      (tester) async {
    final book = _testBook(id: '1', title: '測試書');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_delete_books_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_delete_books_button')));
    await tester.pumpAndSettle();

    expect(find.text('刪除書籍'), findsOneWidget);
    expect(
      find.text('將刪除已選取的 1 本書籍，並一併刪除其書籤、劃線與備註，此操作無法復原。確定要刪除嗎？'),
      findsOneWidget,
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(repository.deleteBookCalls, isEmpty);
    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
  });

  testWidgets('選取多本書後點擊刪除並確認，每個已選取 id 各被呼叫一次 deleteBook，書籍從列表消失',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A書');
    final bookB = _testBook(id: '2', title: 'B書');
    final bookC = _testBook(id: '3', title: 'C書');
    final repository =
        FakeLibraryRepository(initialBooks: [bookA, bookB, bookC]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_item_2')));
    await tester.pumpAndSettle();
    expect(find.text('已選取 2 本'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_delete_books_button')));
    await tester.pumpAndSettle();
    expect(
      find.text('將刪除已選取的 2 本書籍，並一併刪除其書籤、劃線與備註，此操作無法復原。確定要刪除嗎？'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('library_delete_confirm_button')));
    await tester.pumpAndSettle();

    expect(repository.deleteBookCalls, unorderedEquals(['1', '2']));
    expect(find.byKey(const Key('library_selection_app_bar')), findsNothing);
    expect(find.byKey(const Key('book_item_1')), findsNothing);
    expect(find.byKey(const Key('book_item_2')), findsNothing);
    expect(find.byKey(const Key('book_item_3')), findsOneWidget);
  });

  testWidgets('確認刪除後，書籍檔案與封面檔案（本機複本）從裝置上被刪除', (tester) async {
    // 【根因說明，比照既有 Markdown 匯出測試先例】真實 Directory.createTemp／
    // File I/O 需要真正的作業系統事件迴圈，AutomatedTestWidgetsFlutterBinding
    // 的 fake Zone 無法完成，須用 tester.runAsync() 包住真實 I/O。
    final tempDir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('library_screen_delete_book_test'),
    ))!;
    addTearDown(() => tester.runAsync(() => tempDir.delete(recursive: true)));

    final bookFile = File('${tempDir.path}/book.epub');
    final coverFile = File('${tempDir.path}/cover.png');
    await tester.runAsync(() async {
      await bookFile.writeAsBytes([0]);
      // 最小合法 1x1 PNG（可被 Image.file 成功解碼），避免 _BookCover 在
      // pumpAndSettle() 階段因無效圖片內容觸發 FlutterError.reportError
      // 而讓測試失敗（bookFile 的內容不受此限——filePath 從未被當成圖片
      // 解碼，只有 coverPath 會經過 Image.file）。
      await coverFile.writeAsBytes(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
        '42YAAAAASUVORK5CYII=',
      ));
    });

    final book = _testBook(
      id: '1',
      title: '測試書',
      filePath: bookFile.path,
      coverPath: coverFile.path,
    );
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_delete_books_button')));
    await tester.pumpAndSettle();

    // 確認刪除的 tap 在框架 zone 內執行，讓 Navigator.pop 觸發的 microtask
    // 正常 flush。_deleteSelectedBooks 使用 deleteSync()（同步系統呼叫），不
    // 需 runAsync 即可在 fake zone 內完成。
    await tester.tap(find.byKey(const Key('library_delete_confirm_button')));
    await tester.pumpAndSettle();

    expect(repository.deleteBookCalls, ['1']);
    expect(bookFile.existsSync(), isFalse);
    expect(coverFile.existsSync(), isFalse);
    expect(find.byKey(const Key('book_item_1')), findsNothing);
  });

  testWidgets('書籍 filePath 為外部 content:// 參照時，刪除書籍不會嘗試刪除原始檔案也不拋例外',
      (tester) async {
    final book = _testBook(
      id: '1',
      title: '測試書',
      filePath: 'content://com.android.externalstorage.documents/document/1234',
    );
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_delete_books_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_delete_confirm_button')));
    await tester.pumpAndSettle();

    expect(repository.deleteBookCalls, ['1']);
    expect(find.byKey(const Key('book_item_1')), findsNothing);
  });

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
    final completer = Completer<ImportResult>();
    importService.pendingCompleter = completer;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: importService,
          prefsManager: prefsManager,
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

    completer.complete(const ImportResult(importedBooks: []));
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
    final completer = Completer<ImportResult>();
    importService.pendingCompleter = completer;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: importService,
          prefsManager: prefsManager,
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

    completer.complete(const ImportResult(importedBooks: []));
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
    final completer = Completer<ImportResult>();
    importService.pendingCompleter = completer;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: importService,
          prefsManager: prefsManager,
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

  testWidgets('【診斷修正】匯入完成後有檔案因來源 URI 重複被跳過時，顯示提示告知使用者',
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
    final completer = Completer<ImportResult>();
    importService.pendingCompleter = completer;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: importService,
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_empty_import_button')));
    await tester.pump(const Duration(milliseconds: 300));

    completer.complete(
      const ImportResult(importedBooks: [], skippedDuplicateCount: 2),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 本已存在，已跳過'), findsOneWidget);
  });

  testWidgets('匯入完成且無重複時，顯示已匯入本數的成功提示（Issue 2：匯入成功缺乏正面回饋）',
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
    final completer = Completer<ImportResult>();
    importService.pendingCompleter = completer;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: importService,
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_empty_import_button')));
    await tester.pump(const Duration(milliseconds: 300));

    completer.complete(
      ImportResult(importedBooks: [_testBook(id: '1', title: '書一')]),
    );
    await tester.pumpAndSettle();

    expect(find.text('已匯入 1 本書'), findsOneWidget);
  });

  testWidgets('匯入完成且同時有重複被跳過時，合併成單一提示（Issue 2：匯入成功缺乏正面回饋）',
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
    final completer = Completer<ImportResult>();
    importService.pendingCompleter = completer;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: importService,
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_empty_import_button')));
    await tester.pump(const Duration(milliseconds: 300));

    completer.complete(
      ImportResult(
        importedBooks: [_testBook(id: '1', title: '書一')],
        skippedDuplicateCount: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已匯入 1 本，2 本已存在，已跳過'), findsOneWidget);
    expect(find.text('2 本已存在，已跳過'), findsNothing);
  });

  testWidgets(
      'LibraryScreen 點開一本書後，ReaderScreen 收到的 highlightsRepository／notesRepository 正確貫穿（Issue 6 缺口修正）',
      (tester) async {
    // 使用 .txt 格式讓 ReaderScreen 命中「不支援格式」分支（純 Dart 安全
    // 路徑，不觸發 AndroidView，比照既有「從閱讀器返回書架」測試的既有
    // 做法）——本測試只關心建構參數是否正確貫穿，與實際閱讀器渲染無關。
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      filePath: 'content://example/1.txt',
    );
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.highlightsRepository, same(highlightsRepository),
        reason: 'LibraryScreen._openBook() 修正前，highlightsRepository 從未'
            '貫穿給 ReaderScreen，一律為 null（見 issues.md Issue 6 背景）');
    expect(readerScreen.notesRepository, same(notesRepository));
  });

  testWidgets(
      'LibraryScreen 點開一本書後，ReaderScreen 收到的 isFixedLayout／libraryRepository 正確貫穿（epic-17-epub-render-migration Issue 3）',
      (tester) async {
    // 使用 .txt 格式讓 ReaderScreen 命中「不支援格式」分支（純 Dart 安全
    // 路徑，不觸發 AndroidView），比照本檔案既有的貫穿驗證測試手法——本
    // 測試只關心建構參數是否正確貫穿，與實際閱讀器渲染無關。
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      filePath: 'content://example/1.txt',
      isFixedLayout: false,
    );
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.isFixedLayout, isFalse);
    expect(readerScreen.libraryRepository, same(repository));
  });

  testWidgets(
      '透過 LibraryScreen 開啟已有劃線/備註資料的 PDF 書籍後，'
      '「劃線與備註」分頁正確顯示既有資料而非空狀態（Issue 6 缺口修正）',
      (tester) async {
    final book = Book(
      id: '1',
      title: '測試 PDF',
      author: '測試作者',
      format: BookFileFormat.pdf,
      filePath: 'test/fixtures/sample.pdf',
      source: BookSource.local,
      groupName: BookGroup.uncategorized,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    );
    final bookmarksRepository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    await highlightsRepository.insert(const Highlight(
      bookId: '1',
      style: HighlightStyle.highlighterYellow,
      pdfPageIndex: 0,
      pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // PDF 的「📚 筆記」按鈕須等 onPageRendered 觸發後才可點擊（既有防呆
    // 邏輯，見 reader_screen_test.dart 既有先例）；app/test/ 環境下原生
    // _channel 恆為 null，改為直接呼叫 PdfReaderView 的公開回呼模擬。
    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageRendered();
    await tester.pump();

    final notesButton = find.byKey(const Key('reader_notes_button'));
    expect(tester.widget<IconButton>(notesButton).onPressed, isNotNull);

    await tester.tap(notesButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notes_sheet_annotation_list')), findsOneWidget,
        reason: '修正前 highlightsRepository／notesRepository 永遠為 null，'
            '此分頁只會顯示空狀態佔位符（見 issues.md Issue 6 背景）');
    expect(
      find.byKey(const Key('notes_sheet_annotations_placeholder')),
      findsNothing,
    );
  });

  testWidgets(
      '透過 LibraryScreen 開書的正式流程匯出 Markdown 後，內容包含該書實際的劃線/備註'
      '（Issue 6 缺口修正，回歸 Issue 5 審查發現的「永遠空狀態」問題）',
      (tester) async {
    // 【根因說明，比照 notes_bottom_sheet_test.dart 既有先例】真實
    // Directory.createTemp／File I/O 需要真正的作業系統事件迴圈，
    // AutomatedTestWidgetsFlutterBinding 的 fake Zone 無法完成，連
    // tester.tap() 本身也必須整個放進 tester.runAsync() 才能讓
    // _exportMarkdown() 從第一行就綁定真實 Zone。
    final tempDir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('library_screen_markdown_export_test'),
    ))!;
    addTearDown(() => tester.runAsync(() => tempDir.delete(recursive: true)));

    final originalPathProvider = PathProviderPlatform.instance;
    final originalSharePlatform = SharePlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    final fakeShare = FakeSharePlatform();
    SharePlatform.instance = fakeShare;

    // 【審查修正，見 review-plan-issue-6.md Spec (b)】runAsync 下若
    // PdfReaderView（AndroidView）觸發版面重新佈局，會透過
    // SystemChannels.platform_views 呼叫真實 'create' 方法通道；未註冊
    // handler 時會拋出 MissingPluginException 而非單純掛起，導致測試崩潰
    // ——僅在 runAsync 的真實 Zone 下才會發生（比照
    // epub_reader_view_test.dart／pdf_reader_view_test.dart 既有先例，
    // 於 addTearDown 還原，範圍不擴及本檔案其他測試）。
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter/platform_views'),
      (message) async => 1,
    );

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_1'),
      (message) async => null,
    );

    addTearDown(() {
      PathProviderPlatform.instance = originalPathProvider;
      SharePlatform.instance = originalSharePlatform;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter/platform_views'),
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_1'),
        null,
      );
    });

    final book = Book(
      id: '1',
      title: '測試 PDF',
      author: '測試作者',
      format: BookFileFormat.pdf,
      filePath: 'test/fixtures/sample.pdf',
      source: BookSource.local,
      groupName: BookGroup.uncategorized,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    );
    final bookmarksRepository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    await highlightsRepository.insert(const Highlight(
      bookId: '1',
      style: HighlightStyle.highlighterYellow,
      pdfPageIndex: 0,
      pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageRendered();
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('notes_sheet_export_markdown')));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (fakeShare.lastParams == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();

    expect(fakeShare.lastParams, isNotNull);
    final files = fakeShare.lastParams!.files;
    expect(files, hasLength(1));
    final exportedFile = File(files!.single.path);
    final content = await tester.runAsync(() => exportedFile.readAsString());
    expect(content, contains('### 📌 螢光筆（黃）（位置：第 1 頁）'),
        reason: '修正前 LibraryScreen 從未貫穿 highlightsRepository／'
            'notesRepository，匯出內容的劃線/備註段落永遠固定顯示'
            '「尚未加入任何劃線或備註」（見 issues.md Issue 6 背景）');
    expect(content, isNot(contains('*(尚未加入任何劃線或備註)*')));
  });

  // ── Task 2: 補齊分類拼貼格排序/兜底桶/空格佔位/選取模式互動測試 ──

  testWidgets('分類拼貼格依名稱 A-Z 排序；「未分類」不使用拼貼格顯示，不計入排序',
      (tester) async {
    final bookSci = _testBook(id: '1', title: '科幻書', groupName: '科幻');
    final bookFan = _testBook(id: '2', title: '奇幻書', groupName: '奇幻');
    final bookNone = _testBook(id: '3', title: '未分類書');
    final repository =
        FakeLibraryRepository(initialBooks: [bookSci, bookFan, bookNone]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    // 列表檢視下拼貼格是 ListTile（_GroupListTile.title 只顯示分類名稱，
    // 不含數量），用它的 title 文字順序驗證排序（name ASC：奇幻 < 科幻，
    // 依 Dart String 預設 UTF-16 碼點比較）。只有 2 個拼貼格——「未分類」
    // 不使用拼貼格顯示，bookNone 純粹以個別書籍項目呈現在拼貼格之後。
    final tileTitles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .take(2)
        .map((tile) => (tile.title as Text).data)
        .toList();
    expect(tileTitles, ['奇幻', '科幻']);
    expect(find.byKey(Key('group_tile_${BookGroup.uncategorized}')),
        findsNothing);
    expect(find.byKey(const Key('book_item_3')), findsOneWidget);
  });

  testWidgets('【診斷修正】「未分類」不使用拼貼格顯示，其書籍純以個別書籍項目呈現',
      (tester) async {
    final bookFan = _testBook(id: '1', title: '奇幻書', groupName: '奇幻');
    final bookNone = _testBook(id: '2', title: '未分類書');
    final repository =
        FakeLibraryRepository(initialBooks: [bookFan, bookNone]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 具名分類（奇幻）仍照舊顯示拼貼格；「未分類」不應該有拼貼格，只有
    // 具名分類才用 2×2 拼貼呈現，「未分類」的書籍純粹以個別書籍項目顯示
    // （已由前一輪診斷修正確保會列在頂層書籍清單中）。
    expect(find.byKey(const Key('group_tile_奇幻')), findsOneWidget);
    expect(
      find.byKey(Key('group_tile_${BookGroup.uncategorized}')),
      findsNothing,
    );
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);
  });

  testWidgets('_groups 快照落後於 _books 時，孤兒 groupName 仍會被兜底桶收留，不會讓書籍消失',
      (tester) async {
    final book = _testBook(id: '1', title: '懸疑小說', groupName: '懸疑');
    final repository = FakeLibraryRepository(initialBooks: [book]);
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 直接繞過 UI 呼叫 repository.updateBook()，模擬「_groups 快照落後於
    // _books」的情境（例如另一裝置端已新增分類，但本機 _groups 尚未重新
    // 整理）——FakeLibraryRepository.updateBook() 不會同步更新 _groups
    // （比照 SqliteLibraryRepository 的既有分工，_groups 是獨立載入的快
    // 照，見 _loadGroups()）。
    await repository.updateBook(book.copyWith(groupName: '科幻'));
    // 觸發 _loadBooks()（不觸發 _loadGroups()）：_changeSortBy() 只重讀
    // _books，不重讀 _groups，正好模擬「_groups 落後」情境。
    await tester.tap(find.byKey(const Key('library_sort_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_option_title')));
    await tester.pumpAndSettle();

    // '科幻' 不在 _groups 快照中（快照仍是建構時的 {未分類, 懸疑}），書籍
    // 仍應被兜底桶收留、出現在某個拼貼格，而不是從書架上「消失」。
    expect(find.byKey(const Key('group_tile_科幻')), findsOneWidget);
    expect(find.text('科幻 (1)'), findsOneWidget);
  });

  testWidgets('分類拼貼格的封面預覽只取該分類前 4 本書，且保留目前排序結果的順序',
      (tester) async {
    final now = DateTime.now();
    final books = [
      for (var i = 0; i < 4; i++)
        Book(
          id: '${i + 1}',
          title: '奇幻書${i + 1}',
          author: null,
          format: BookFileFormat.epub,
          filePath: 'content://example/${i + 1}.epub',
          source: BookSource.local,
          groupName: '奇幻',
          createTime: now,
          lastReadTime: now.subtract(Duration(minutes: i)),
        ),
      // 第 5 本書刻意用不同格式（txt → Icons.article）且 lastReadTime 最
      // 舊（預設「最後閱讀」排序下排最後），用來驗證 previewBooks.take(4)
      // 確實把它排除在封面預覽之外——若截取邏輯錯誤（例如順序顛倒），這
      // 裡會多出一個 Icons.article。
      Book(
        id: '5',
        title: '奇幻書5',
        author: null,
        format: BookFileFormat.txt,
        filePath: 'content://example/5.txt',
        source: BookSource.local,
        groupName: '奇幻',
        createTime: now,
        lastReadTime: now.subtract(const Duration(minutes: 10)),
      ),
    ];
    final repository = FakeLibraryRepository(initialBooks: books);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('奇幻 (5)'), findsOneWidget);

    final tileFinder = find.byKey(const Key('group_tile_奇幻'));
    expect(
      find.descendant(
        of: tileFinder,
        matching:
            find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.menu_book),
      ),
      findsNWidgets(4),
    );
    expect(
      find.descendant(
        of: tileFinder,
        matching:
            find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.article),
      ),
      findsNothing,
    );
  });

  testWidgets('分類拼貼格（格狀檢視）不足 4 本時以中性色塊佔位，名稱與本數正確顯示',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB = _testBook(id: '2', title: 'B書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tileFinder = find.byKey(const Key('group_tile_奇幻'));
    expect(tileFinder, findsOneWidget);
    expect(find.text('奇幻 (2)'), findsOneWidget);

    // 2 本書皆無 coverPath，_BookCover 各自退回格式圖示佔位（Icon），故拼
    // 貼格內應有 2 個 Icon（書封佔位）＋ 2 個中性灰色塊（拼貼格本身「不
    // 足 4 本」的空格佔位，色階 grey.shade200，與 _BookCover 內部佔位的
    // shade300 不同，可用色階區分兩者，不需要存取 private widget 型別）。
    expect(
      find.descendant(of: tileFinder, matching: find.byType(Icon)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: tileFinder,
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == Colors.grey.shade200,
        ),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('分類拼貼格（列表檢視）不足 4 本時以中性色塊佔位', (tester) async {
    final book = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    final tileFinder = find.byKey(const Key('group_tile_奇幻'));
    expect(tileFinder, findsOneWidget);
    expect(find.text('奇幻'), findsOneWidget);
    expect(find.text('1 本'), findsOneWidget);
    expect(
      find.descendant(of: tileFinder, matching: find.byType(Icon)),
      findsNWidgets(1),
    );
    expect(
      find.descendant(
        of: tileFinder,
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == Colors.grey.shade200,
        ),
      ),
      findsNWidgets(3),
    );
  });

  testWidgets('長按進入選取模式後，分類拼貼格的 onTap 停用，點擊不觸發導覽也不影響選取狀態',
      (tester) async {
    // bookA 維持「未分類」，確保它仍會出現在頂層書架的書籍清單中可供長按
    // （已歸類的書籍不再重複顯示於頂層，見「已分類的書不重複列出」規則）；
    // bookB 歸入「奇幻」，用來確保有一個分類拼貼格可以點擊測試。
    final bookA = _testBook(id: '1', title: 'A書', groupName: BookGroup.uncategorized);
    final bookB = _testBook(id: '2', title: 'B書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    expect(find.text('已選取 1 本'), findsOneWidget);

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    // 選取狀態不受影響、沒有觸發 Navigator.push（沒有跳轉離開，選取列仍
    // 顯示在同一個畫面上）。
    expect(find.text('已選取 1 本'), findsOneWidget);
    expect(find.byKey(const Key('library_selection_app_bar')), findsOneWidget);
  });

  testWidgets('_buildBookList 合併分類格與書籍的 index 空間，分類格恆排在書籍之前',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB =
        _testBook(id: '2', title: 'B書', groupName: BookGroup.uncategorized);
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    // bookA 已歸類到「奇幻」→ 1 個拼貼格（ListTile），頂層書架不重複列出
    // （只透過拼貼格顯示）；bookB 是「未分類」→「未分類」不使用拼貼格
    // 顯示，純粹以個別書籍項目列在書籍清單中（也是 ListTile，見
    // _BookListTile）。驗證拼貼格恆排最前面：第 1 個 ListTile 的 title
    // 應為分類名稱，之後才是「未分類」書籍本身。
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .toList();
    expect(titles, ['奇幻', 'B書']);
  });
}

Book _testBook({
  required String id,
  required String title,
  String? author,
  String groupName = BookGroup.uncategorized,
  String? filePath,
  String? coverPath,
  bool? isFixedLayout,
  BookFileFormat format = BookFileFormat.epub,
}) {
  final now = DateTime.now();
  return Book(
    id: id,
    title: title,
    author: author,
    format: format,
    filePath: filePath ?? 'content://example/$id.epub',
    source: BookSource.local,
    coverPath: coverPath,
    groupName: groupName,
    isFixedLayout: isFixedLayout,
    createTime: now,
    lastReadTime: now,
  );
}

/// 找出目前 widget 樹中 `groupFilter` 等於 [groupName] 的那個 LibraryScreen
/// 實例（即 _openGroupFilteredView 推入的篩選畫面）。MaterialPageRoute
/// 預設 `maintainState: true`，背景畫面（groupFilter == null 的頂層畫面）
/// 推入新畫面後仍留在 widget 樹中，兩個 LibraryScreen 實例的書籍/拼貼格
/// key 會同時存在——後續斷言一律搭配 find.descendant(of: 這個 finder, ...)
/// 限定搜尋範圍在篩選畫面本身，避免誤判到背景畫面的同名 widget。
Finder _filteredLibraryScreenFinder(String groupName) => find.byWidgetPredicate(
      (widget) => widget is LibraryScreen && widget.groupFilter == groupName,
    );
