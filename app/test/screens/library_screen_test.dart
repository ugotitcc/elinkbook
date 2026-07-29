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

    // 兩本書皆為預設「未分類」，書架會多顯示 1 個「未分類」拼貼格
    // ListTile，恆排在書籍之前（見 _buildBookList 合併 index 空間的規則）
    // ——用 .skip(1) 跳過它，只比較書籍本身的順序。
    var titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .skip(1)
        .map((tile) => (tile.title as Text).data)
        .toList();
    expect(titles, ['B書', 'A書']);

    await tester.tap(find.byKey(const Key('library_sort_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_option_title')));
    await tester.pumpAndSettle();

    titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .skip(1)
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

  testWidgets('點擊分類拼貼格後只顯示該分類書籍；返回後恢復書架顯示全部書籍',
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

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
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
    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
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
      '管理分類對話框：刪除分類前彈出確認對話框，確認後該分類下書籍改顯示於「未分類」拼貼格',
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

    await tester.tap(find.byKey(Key('group_tile_${BookGroup.uncategorized}')));
    await tester.pumpAndSettle();

    final filteredScreenFinder =
        _filteredLibraryScreenFinder(BookGroup.uncategorized);
    expect(
      find.descendant(
        of: filteredScreenFinder,
        matching: find.byKey(const Key('book_item_1')),
      ),
      findsOneWidget,
    );
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
    final completer = Completer<List<Book>>();
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
}

Book _testBook({
  required String id,
  required String title,
  String? author,
  String groupName = BookGroup.uncategorized,
  String? filePath,
  String? coverPath,
  bool? isFixedLayout,
}) {
  final now = DateTime.now();
  return Book(
    id: id,
    title: title,
    author: author,
    format: BookFileFormat.epub,
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
