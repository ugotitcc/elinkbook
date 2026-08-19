import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show sqrt;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/layout_preset_repository.dart';
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
import '../support/fake_opds_client.dart';
import '../support/fake_remote_server_repository.dart';
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_remote_thumbnail_cache.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/screens/remote_server_list_screen.dart';
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
import '../support/fake_custom_fonts_repository.dart';
import 'package:elinkbook/screens/settings_screen.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_client.dart';
import 'package:elinkbook/reader/bookmark.dart';

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
    // epic-18-reader-device-qa Issue 29：openLastBookOnLaunch 預設 true，
    // 會讓頂層 LibraryScreen 啟動當下自動導向最後閱讀的書籍——這個共用
    // fixture 供本檔案絕大多數測試使用，這些測試的斷言目標是書架本身的
    // 行為，並非這個自動開書的新功能，故在這裡明確關閉，避免每個既有測試
    // 都被意外導覽到 ReaderScreen 而斷言失敗。Issue 29 自己的測試（見
    // 「openLastBookOnLaunch=...」系列）各自建立獨立的 FakeReaderPrefsManager
    // 明確開啟，不受這裡影響。
    prefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial()
          .copyWith(openLastBookOnLaunch: false),
    );
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
      '窄邏輯寬度裝置（比照 AiPaper Reader C 等 E-Ink 裝置實測會觸發溢位的寬度區間）下，'
      '書架 AppBar 工具列不再 RenderFlex overflow（epic-18：3 顆主題圓點移至 SettingsScreen 後）',
      (tester) async {
    // 修復前：11 個固定寬度 actions 項目在寬度 360 時已確認溢位 29px（見
    // reviews/bugfix-repro-appbar-overflow.md）；修復後移除 3 顆主題圓點 +
    // 間隔（僅存 7 項），在同一寬度下應不再溢位。
    tester.view.physicalSize = const Size(360, 1648);
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

    expect(tester.takeException(), isNull);
    // 主題圓點已搬離書架 AppBar，不應再出現於此。
    expect(find.byKey(const Key('library_theme_dot_light')), findsNothing);
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
    // 使用 .unknown 格式讓 ReaderScreen 命中「不支援格式」分支（純 Dart 安全路徑，
    // 不觸發 AndroidView），確保 pumpAndSettle 能順利完成。重點是驗證
    // Navigator.pop() 後 _openBook 的 .then() 回呼會呼叫 _loadBooks()，
    // 與實際閱讀器渲染無關。
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      filePath: 'content://example/1.unknown',
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
      format: BookFileFormat.epub,
      filePath: 'content://example/1.unknown',
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
      filePath: 'content://example/1.unknown',
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

    // 用 .unknown 檔名讓 ReaderScreen 命中「不支援格式」分支（純 Dart 安全路徑，
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
      '新分類拼貼格正確出現且未消失',
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
          // 分類名稱本身不影響拼貼格順序（epic-18-reader-device-qa
          // Issue 31 修正後改依 _sortBy 排序）；這裡只是一個任意的新分類
          // 名稱，用來驗證資料夾匯入建立的新分類拼貼格確實會出現、不會
          // 消失。
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

    // epic-18-reader-device-qa Issue 31 修正後，_buildGroupTiles() 不再
    // 區分「_groups 已註冊」與「孤兒」分類——所有分類統一來自同一份依
    // _sortBy 排序的 books 走訪順序，故不需要 _loadGroups() 是否有被
    // 呼叫也不會讓「一般叢書」的拼貼格消失或錯放；這裡改為單純驗證新
    // 建立的分類拼貼格確實存在（未消失）。「奇幻」排在「一般叢書」之前
    // 是因為前者的 lastReadTime 是既有 fixture 的真實值（`_testBook()`
    // 預設值＝建立當下），後者是透過資料夾匯入剛建立、從未被打開過的
    // 新書——依 Issue 29 修正後的語意，剛匯入未讀的書不該被誤判為
    // 「最後閱讀」而排到已有真實閱讀紀錄的書之前（`lastReadTime` 為
    // 「尚未讀過」的 epoch 0 哨兵值，排序模式「最後閱讀」下必然排在最
    // 後），並非依名稱排序。
    final tileTitles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .where((title) => title == '奇幻' || title == '一般叢書')
        .toList();
    expect(tileTitles, ['奇幻', '一般叢書']);
  });

  testWidgets(
      '分類拼貼格彼此的相對順序跟隨目前選定的排序模式（最後閱讀），'
      '而非固定依分類名稱排序（epic-18-reader-device-qa Issue 31）',
      (tester) async {
    // 刻意讓「名稱字母序」與「最後閱讀時間序」互相矛盾：'一般叢書'
    // 名稱字母序排最前（一 U+4E00 < 奇 U+5947 < 武 U+6B66），但依
    // lastReadTime 應排最後——若拼貼格順序錯誤地仍依名稱排序（舊 bug
    // 行為），這裡會斷言失敗。
    final generalBook = _testBook(
      id: 'g1',
      title: '叢書A',
      groupName: '一般叢書',
      lastReadTime: DateTime(2026, 1, 1),
    );
    final fantasyBook = _testBook(
      id: 'f1',
      title: '奇幻A',
      groupName: '奇幻',
      lastReadTime: DateTime(2026, 6, 1),
    );
    final wuxiaBook = _testBook(
      id: 'w1',
      title: '武俠A',
      groupName: '武俠',
      lastReadTime: DateTime(2026, 3, 1),
    );
    final repository = FakeLibraryRepository(
      initialBooks: [generalBook, fantasyBook, wuxiaBook],
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

    // 切到列表檢視，方便用 ListTile.title 比對拼貼格彼此的相對順序
    // （格狀檢視的 _GroupGridTile 是 InkWell，不是 ListTile，比照既有
    // 「新分類拼貼格排在「未分類」之前」測試的既有寫法）。
    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    final tileTitles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .where((title) => title == '奇幻' || title == '一般叢書' || title == '武俠')
        .toList();
    expect(tileTitles, ['奇幻', '武俠', '一般叢書'],
        reason: 'LibraryScreen 預設排序模式為「最後閱讀」，拼貼格順序應依各分類'
            '最近一次被閱讀的書籍（lastReadTime 最新）排列，而非分類名稱字母序');
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

  // epic-29-cloud-import Issue 3：Google Drive 匯入選單測試
  testWidgets('googleDriveStorageClient 為 null 時「從 Google Drive 匯入」選項停用', (tester) async {
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

    await tester.tap(find.byKey(const Key('library_import_button')));
    await tester.pumpAndSettle();

    final option = tester.widget<PopupMenuItem<void>>(
      find.byKey(const Key('library_import_google_drive_option')),
    );
    expect(option.enabled, false);
  });

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
      id: 'h_lib_1',
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

    final notesButton = find.byKey(const Key('reader_pdf_notes_button'));
    expect(tester.widget<IconButton>(notesButton).onPressed, isNotNull);

    // epic-24 Issue 8：PDF 不再使用 AppBar，筆記按鈕改為 FAB，與
    // PdfReaderView 同層疊放於 Stack；此情境下 PdfReaderView 尚未完成
    // 真實非同步渲染時本身版面大小為 0，導致 tester.tap() 座標命中失敗
    // ——直接呼叫 onPressed callback 繞過此問題（比照
    // reader_screen_test.dart:633 既有先例）。
    tester.widget<IconButton>(notesButton).onPressed!();
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
      id: 'h_lib_2',
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

    // epic-24 Issue 8：PDF 不再使用 AppBar，筆記按鈕改為 FAB，與
    // PdfReaderView 同層疊放於 Stack；此情境下 PdfReaderView 尚未完成
    // 真實非同步渲染時本身版面大小為 0，導致 tester.tap() 座標命中失敗
    // ——直接呼叫 onPressed callback 繞過此問題（比照
    // reader_screen_test.dart:633 既有先例）。
    tester
        .widget<IconButton>(find.byKey(const Key('reader_pdf_notes_button')))
        .onPressed!();
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

  testWidgets(
      '分類拼貼格依目前排序模式（最後閱讀）排序；「未分類」不使用拼貼格顯示，不計入排序',
      (tester) async {
    // epic-18-reader-device-qa Issue 31 修正前，拼貼格順序固定依分類名稱
    // A-Z（不受 _sortBy 影響）；修正後改依 _sortBy 排序，這裡明確指定
    // 不同的 lastReadTime（而非依賴巧合的建立順序時間差），確保斷言不依賴
    // 名稱字母序與時間序恰好一致的巧合。
    final bookSci = _testBook(
      id: '1',
      title: '科幻書',
      groupName: '科幻',
      lastReadTime: DateTime(2026, 1, 1),
    );
    final bookFan = _testBook(
      id: '2',
      title: '奇幻書',
      groupName: '奇幻',
      lastReadTime: DateTime(2026, 6, 1),
    );
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
    // 不含數量），用它的 title 文字順序驗證排序——LibraryScreen 預設排序
    // 模式為「最後閱讀」，奇幻書 lastReadTime 較新，故「奇幻」拼貼格排在
    // 「科幻」之前。只有 2 個拼貼格——「未分類」不使用拼貼格顯示，
    // bookNone 純粹以個別書籍項目呈現在拼貼格之後。
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

  testWidgets(
      '分類拼貼格（格狀檢視）封面預覽區塊填滿可用高度，下方不留空白'
      '（診斷修正：原本用 GridView.count 預設正方形儲存格，2×2 網格自身高度'
      '只略等於寬度，遠小於拼貼格 childAspectRatio: 0.62 分配到的較高可用'
      '空間，NeverScrollableScrollPhysics 又不會撐滿，導致封面下方留下大片'
      '空白；改用 Column/Row 手排 Expanded 後應精確填滿）', (tester) async {
    final books = List.generate(
      4,
      (i) => _testBook(id: '$i', title: '書$i', groupName: '奇幻'),
    );
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

    final tileFinder = find.byKey(const Key('group_tile_奇幻'));
    expect(tileFinder, findsOneWidget);

    // 結構性驗證：不再使用 GridView 手排 2×2（改用 Expanded 手排），確保
    // 修法本身確實生效，不是巧合的尺寸吻合。
    expect(
      find.descendant(of: tileFinder, matching: find.byType(GridView)),
      findsNothing,
    );

    // 尺寸驗證：4 本書皆無 coverPath，_BookCover 各自以 ColoredBox 佔位
    // （內含置中的小圖示，圖示本身不會撐滿儲存格，故量測 ColoredBox 本身
    // 的邊界而非圖示）；取最下面那一列（第 3/4 格）佔位色塊的底部，應緊
    // 接分類名稱文字的頂部（僅隔明講的 SizedBox(height: 4) 一點點間距），
    // 而非留下大片空白。
    final coverBoxFinder = find.descendant(
      of: tileFinder,
      matching: find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == Colors.grey.shade300,
      ),
    );
    final coverBoxCount = tester.widgetList(coverBoxFinder).length;
    expect(coverBoxCount, 4);
    final bottomRowBottomY = List.generate(
      coverBoxCount,
      (i) => tester.getBottomLeft(coverBoxFinder.at(i)).dy,
    ).reduce((a, b) => a > b ? a : b);

    final labelFinder = find.descendant(
      of: tileFinder,
      matching: find.text('奇幻 (4)'),
    );
    final labelTopY = tester.getTopLeft(labelFinder).dy;

    expect(labelTopY - bottomRowBottomY, lessThan(10),
        reason: '封面預覽區塊與分類名稱之間不應留下大片空白（僅預期的 4px 間距）');
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

  testWidgets('LibraryScreen 貫穿 customFontsRepository 至 SettingsScreen',
      (tester) async {
    final customFontsRepository = FakeCustomFontsRepository();
    await tester.pumpWidget(MaterialApp(
      home: LibraryScreen(
        repository: FakeLibraryRepository(initialBooks: const []),
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
        customFontsRepository: customFontsRepository,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();

    final settingsScreen =
        tester.widget<SettingsScreen>(find.byType(SettingsScreen));
    expect(settingsScreen.customFontsRepository, customFontsRepository);
  });

  testWidgets(
      'LibraryScreen 點開一本書後，ReaderScreen 收到的 customFontsRepository 正確貫穿（自訂字型無法在單書閱讀字型選單出現的診斷回歸測試）',
      (tester) async {
    // 使用 .txt 格式讓 ReaderScreen 命中「不支援格式」分支（純 Dart 安全
    // 路徑，不觸發 AndroidView），比照本檔案既有的貫穿驗證測試手法——本
    // 測試只關心建構參數是否正確貫穿，與實際閱讀器渲染無關。
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      filePath: 'content://example/1.txt',
    );
    final customFontsRepository = FakeCustomFontsRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          customFontsRepository: customFontsRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.customFontsRepository, same(customFontsRepository),
        reason: 'LibraryScreen._openBook() 未把 customFontsRepository 貫穿給 '
            'ReaderScreen，導致 ReaderScreen._loadCustomFonts() 早期 return，'
            '_customFonts 永遠是空清單，自訂字型永遠不會出現在 '
            'ReaderSettingsSheet 的單書字型選單中');
  });

  testWidgets(
      'LibraryScreen 點開一本書後，ReaderScreen 收到的 layoutPresetRepository／bookReaderPrefsRepository 正確貫穿',
      (tester) async {
    final layoutPresetRepository =
        LayoutPresetRepository(libraryRepository.database);
    final bookReaderPrefsRepository =
        BookReaderPrefsRepository(libraryRepository.database);

    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      filePath: 'content://example/1.txt',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          layoutPresetRepository: layoutPresetRepository,
          bookReaderPrefsRepository: bookReaderPrefsRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.layoutPresetRepository, same(layoutPresetRepository),
        reason: 'LibraryScreen._openBook() 未把 layoutPresetRepository 貫穿給 '
            'ReaderScreen，版面設定預設集功能將完全無法使用。');
    expect(readerScreen.bookReaderPrefsRepository, same(bookReaderPrefsRepository),
        reason: 'LibraryScreen._openBook() 未把 bookReaderPrefsRepository 貫穿給 '
            'ReaderScreen，書籍設定複製與批次套用功能將完全無法使用。');
  });

  testWidgets(
      'LibraryScreen 點開一本書後，ReaderScreen 收到的 syncCheckpointTrigger 正確貫穿',
      (tester) async {
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      filePath: 'content://example/1.txt',
    );
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      isLoggedIn: () async => false,
      runCheckpoint: () async {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          syncCheckpointTrigger: syncCheckpointTrigger,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.syncCheckpointTrigger, same(syncCheckpointTrigger),
        reason: 'LibraryScreen._openBook() 未把 syncCheckpointTrigger 貫穿給 '
            'ReaderScreen，離開閱讀畫面時就不會觸發書籍切換 checkpoint');
  });

  testWidgets(
      'LibraryScreen 透過分類篩選路徑（_openGroupFilteredView）開書後，'
      'ReaderScreen 收到的 syncCheckpointTrigger 與外層一致'
      '（epic-8-sync Issue 10）', (tester) async {
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      groupName: '奇幻',
      filePath: 'content://example/1.txt',
    );
    final syncAccountRepository = SyncAccountRepository();
    final syncClient = SyncClient(accountRepository: syncAccountRepository);
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      isLoggedIn: () async => false,
      runCheckpoint: () async {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          syncAccountRepository: syncAccountRepository,
          syncClient: syncClient,
          syncCheckpointTrigger: syncCheckpointTrigger,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    final filteredScreenFinder = _filteredLibraryScreenFinder('奇幻');
    final filteredScreen = tester.widget<LibraryScreen>(filteredScreenFinder);
    expect(filteredScreen.syncAccountRepository, same(syncAccountRepository),
        reason: '_openGroupFilteredView() 未把 syncAccountRepository 貫穿給下一層 '
            'LibraryScreen');
    expect(filteredScreen.syncClient, same(syncClient),
        reason: '_openGroupFilteredView() 未把 syncClient 貫穿給下一層 LibraryScreen');
    expect(filteredScreen.syncCheckpointTrigger, same(syncCheckpointTrigger),
        reason: '_openGroupFilteredView() 未把 syncCheckpointTrigger 貫穿給下一層 '
            'LibraryScreen');

    await tester.tap(find.descendant(
      of: filteredScreenFinder,
      matching: find.byKey(const Key('book_item_1')),
    ));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.syncCheckpointTrigger, same(syncCheckpointTrigger),
        reason: '透過分類篩選路徑開書，ReaderScreen 收到的 syncCheckpointTrigger 應與'
            '外層一致，離開閱讀畫面／閱讀中 5 分鐘計時器兩種來源才會正確觸發 '
            'checkpoint');
  });

  testWidgets(
      'openLastBookOnLaunch=true 且圖書庫有書籍時，App 啟動後自動導向最後閱讀的書籍'
      '（epic-18-reader-device-qa Issue 29）', (tester) async {
    final older = _testBook(
      id: 'older',
      title: '較早閱讀的書',
      filePath: 'content://example/older.txt',
      lastReadTime: DateTime(2026, 1, 1),
    );
    final newer = _testBook(
      id: 'newer',
      title: '最近閱讀的書',
      filePath: 'content://example/newer.txt',
      lastReadTime: DateTime(2026, 6, 1),
    );
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial()
          .copyWith(openLastBookOnLaunch: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [older, newer]),
          importService: FakeBookImportService(),
          prefsManager: fakeManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.bookId, 'newer',
        reason: 'openLastBookOnLaunch 應自動導向 lastReadTime 最新的那一本，'
            '而非清單第一筆或任意一筆');
  });

  testWidgets(
      'openLastBookOnLaunch=false 時，App 啟動後停留在書架，不自動開書'
      '（epic-18-reader-device-qa Issue 29）', (tester) async {
    final book = _testBook(
      id: 'b1',
      title: '測試書',
      filePath: 'content://example/b1.txt',
    );
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial()
          .copyWith(openLastBookOnLaunch: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: fakeManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReaderScreen), findsNothing);
    expect(find.byKey(const Key('book_item_b1')), findsOneWidget);
  });

  testWidgets(
      'openLastBookOnLaunch=true 但圖書庫沒有任何書籍時，不嘗試開書也不拋出例外'
      '（epic-18-reader-device-qa Issue 29）', (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial()
          .copyWith(openLastBookOnLaunch: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: const []),
          importService: FakeBookImportService(),
          prefsManager: fakeManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReaderScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '透過分類篩選路徑（groupFilter 非 null）進入的 LibraryScreen 不會自動開書，'
      '即使 openLastBookOnLaunch=true（epic-18-reader-device-qa Issue 29）',
      (tester) async {
    final book = _testBook(
      id: 'b1',
      title: '奇幻書',
      groupName: '奇幻',
      filePath: 'content://example/b1.txt',
    );
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial()
          .copyWith(openLastBookOnLaunch: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: fakeManager,
          groupFilter: '奇幻',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReaderScreen), findsNothing,
        reason: '只有頂層書架（groupFilter == null）啟動當下才應該觸發自動開書，'
            '分類篩選路徑本身不應該重複觸發');
  });

  testWidgets(
      '橫屏（4 欄）下 3 個分類拼貼格＋第 4 欄由第一本書籍格頂上時，兩者文字'
      '標籤起始 Y 座標對齊（epic-18-reader-device-qa Issue 42，真機使用'
      '回報：書架橫屏下封面未對齊——直式 3 欄時 3 個分類恰好填滿一列、'
      '書籍從下一列開始，不會同列；橫屏 4 欄時 3 個分類只填滿前 3 欄，'
      '第 4 欄由第一本書籍格頂上，才會與分類拼貼格同列。根因是'
      '_BookGridTile 有 2 行文字說明（書名＋進度），_GroupGridTile 只有'
      '1 行〔分類名稱＋本數〕，兩者封面 Expanded 吃到的剩餘高度因此不同，'
      '導致同列的封面底部邊界錯開。程式碼審查修正：原測試只建立 1 個分類'
      '〔任何欄數下皆會同列，未精確重現橫屏限定的觸發條件〕，改為 3 個'
      '不同分類＋橫屏 4 欄，具體驗證「第 4 欄由書籍格頂上」這個情境）',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final books = [
      _testBook(id: 'g0', title: '奇幻書', groupName: '奇幻'),
      _testBook(id: 'g1', title: '科幻書', groupName: '科幻'),
      _testBook(id: 'g2', title: '歷史書', groupName: '歷史'),
      _testBook(id: 'b0', title: '第一本個別書'),
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

    final groupTileFinder = find.byKey(const Key('group_tile_奇幻'));
    final bookTileFinder = find.byKey(const Key('book_item_b0'));
    expect(groupTileFinder, findsOneWidget);
    expect(bookTileFinder, findsOneWidget);

    // 前提：兩者確實同列（外層總高度相同、頂端 Y 座標相同，這是
    // GridView 在橫屏 4 欄、3 個分類拼貼格＋書籍格緊接在第 4 欄的既有
    // 佈局保證，這裡順便驗證前提沒有跑掉）。
    expect(
      tester.getTopLeft(groupTileFinder).dy,
      tester.getTopLeft(bookTileFinder).dy,
    );
    expect(
      tester.getSize(groupTileFinder).height,
      tester.getSize(bookTileFinder).height,
    );

    final groupLabelTop = tester
        .getTopLeft(find.descendant(
          of: groupTileFinder,
          matching: find.text('奇幻 (1)'),
        ))
        .dy;
    final bookTitleTop = tester
        .getTopLeft(find.descendant(
          of: bookTileFinder,
          matching: find.text('第一本個別書'),
        ))
        .dy;

    expect(bookTitleTop, groupLabelTop,
        reason: '同列的分類拼貼格與書籍格，文字標籤起始高度應對齊，'
            '封面區塊底部邊界才不會錯開');
  });

  testWidgets(
      '系統字級放大時，分類拼貼格與書籍格的文字說明區高度隨字級同比例'
      '縮放，不會觸發 RenderFlex 溢位（程式碼審查修正，'
      'tmp/epic-18/review-issue-42-44.md Important #1：修法前文字說明區'
      '是自然高度，字級放大時 Column 會自然讓出空間；修法後鎖進固定像素'
      '高度的 SizedBox，若沒有隨 textScaler 同比例縮放，字級放大會讓'
      '_BookGridTile 的 2 行文字被截斷、觸發溢位）', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final books = [
      _testBook(id: 'g0', title: '奇幻書', groupName: '奇幻'),
      _testBook(id: 'b0', title: '第一本個別書，書名故意寫長一點測試換行'),
    ];
    final repository = FakeLibraryRepository(initialBooks: books);

    await tester.pumpWidget(
      MediaQuery(
        // 模擬系統字級放大 1.5 倍（Android「顯示大小」設定常見選項）。
        data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: MaterialApp(
          home: LibraryScreen(
            repository: repository,
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 字級放大情境下，只要沒有 RenderFlex 溢位例外，就代表固定高度容器
    // 有隨 textScaler 同比例放大、確實讓出足夠空間。
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('group_tile_奇幻')), findsOneWidget);
    expect(find.byKey(const Key('book_item_b0')), findsOneWidget);
  });

  testWidgets(
      '系統字級縮放曲線為非線性時（真機常見情境——Android 系統字級調大後，'
      '「非線性字級縮放」會讓縮放比例依輸入數值大小而不同），分類拼貼格與'
      '書籍格的文字說明區仍不會觸發 RenderFlex 溢位（/diagnose 第七輪，'
      'Air Reader C 真機回報：手動調大系統字級後，即使已套用 Issue 42 的'
      '固定高度隨 textScaler 縮放修法，仍會溢位。根因是舊寫法把「書名+'
      '進度」的合計常數〔34.0〕整體丟進 textScaler.scale()，而 Flutter '
      '真正的 Text 元件是對書名〔12〕與進度〔10〕各自的字級分別呼叫 '
      'scale()。兩者只有在縮放曲線為線性時才恆等；`flutter_test` 套件的 '
      'TestPlatformDispatcher.scaleFontSize 寫死是線性乘法，測不出這個'
      '落差，必須像既有測試一樣改用 MediaQuery 直接提供非線性的自訂 '
      'TextScaler 才能重現）', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final books = [
      _testBook(id: 'g0', title: '奇幻書', groupName: '奇幻'),
      _testBook(id: 'b0', title: '第一本個別書，書名故意寫長一點測試換行'),
    ];
    final repository = FakeLibraryRepository(initialBooks: books);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: _NonLinearTextScaler(1.5)),
        child: MaterialApp(
          home: LibraryScreen(
            repository: repository,
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('group_tile_奇幻')), findsOneWidget);
    expect(find.byKey(const Key('book_item_b0')), findsOneWidget);
  });

  group('遠端書庫進入點', () {
    testWidgets('未提供 remoteServerRepository/opdsClient 時，AppBar 不顯示遠端書庫按鈕', (tester) async {
      final repository = FakeLibraryRepository();
      final importService = FakeBookImportService();
      await tester.pumpWidget(MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: importService,
          prefsManager: FakeReaderPrefsManager(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('library_remote_library_button')), findsNothing);
    });

    testWidgets('提供 remoteServerRepository/opdsClient 時，AppBar 顯示遠端書庫按鈕，點擊後導向 RemoteServerListScreen',
        (tester) async {
      final repository = FakeLibraryRepository();
      final importService = FakeBookImportService();
      await tester.pumpWidget(MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: importService,
          prefsManager: FakeReaderPrefsManager(),
          remoteServerRepository: FakeRemoteServerRepository(),
          createOpdsClient: () => FakeOpdsClient(),
          computeFingerprint: (path, format) async => 'test-fingerprint',
          thumbnailCache: FakeRemoteThumbnailCache(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('library_remote_library_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('library_remote_library_button')));
      await tester.pumpAndSettle();

      expect(find.byType(RemoteServerListScreen), findsOneWidget);
    });

    testWidgets('從遠端書庫返回書架時，重新載入書籍清單，顯示新下載的書籍'
        '（review-issue-5-code.md Important #2）', (tester) async {
      // 比照「從閱讀器返回書架時，重新載入書籍清單」既有測試的手法：
      // widget test 無法真正走完整下載/匯入流程，改為在使用者停留於
      // RemoteServerListScreen 期間，直接對 repository 寫入模擬「下載
      // 完成後已匯入新書」的結果，驗證 Navigator.push().then() 的
      // _loadBooks() 回呼確實有被觸發。
      final repository = FakeLibraryRepository();
      final importService = FakeBookImportService();
      await tester.pumpWidget(MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: importService,
          prefsManager: FakeReaderPrefsManager(),
          remoteServerRepository: FakeRemoteServerRepository(),
          createOpdsClient: () => FakeOpdsClient(),
          computeFingerprint: (path, format) async => 'test-fingerprint',
          thumbnailCache: FakeRemoteThumbnailCache(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('遠端下載的書'), findsNothing);

      await tester.tap(find.byKey(const Key('library_remote_library_button')));
      await tester.pumpAndSettle();

      expect(find.byType(RemoteServerListScreen), findsOneWidget);

      await repository.insertBook(_testBook(
        id: 'remote-1',
        title: '遠端下載的書',
        author: '某作者',
      ));

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('遠端下載的書'), findsOneWidget,
          reason: '返回書架後應重新載入書籍清單，顯示遠端下載期間新匯入的書籍，'
              '而非停留在舊快照');
    });
  });

  testWidgets('選取 Calibre 來源已下載書籍後點擊「移除本機快取」，刪除實體檔案、isDownloaded 變 false，劃線/書籤/進度不受影響',
      (tester) async {
    // 〔比照 library_screen.dart _deleteSelectedBooks() 既有註解說明〕
    // widget test 的 fake zone 無法完成真實 I/O 的 Future，一律使用
    // *Sync() 系列同步呼叫，不需要 tester.runAsync()。
    final tempDir = Directory.systemTemp.createTempSync('library_remove_cache_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final bookFile = File('${tempDir.path}/remote_book.epub')..writeAsStringSync('dummy');

    final book = Book(
      id: 'b1',
      title: '遠端書',
      format: BookFileFormat.epub,
      filePath: bookFile.path,
      source: BookSource.calibreOpds,
      remoteServerId: 'srv1',
      remoteBookId: 'remote-1',
      remoteDownloadUrl: 'http://example.com/download/1.epub',
      isDownloaded: true,
      epubLocator: 'locator-json',
      progress: 0.5,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(2000),
    );
    final repository = FakeLibraryRepository(initialBooks: [book]);
    final bookmarksRepository = FakeBookmarksRepository();
    await bookmarksRepository.insert(
      const Bookmark(id: 'bm1', bookId: 'b1', name: '第一章'),
    );

    await tester.pumpWidget(MaterialApp(
      home: LibraryScreen(
        repository: repository,
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(
          globalPrefs: const GlobalReaderPrefs.initial()
              .copyWith(openLastBookOnLaunch: false),
        ),
        bookmarksRepository: bookmarksRepository,
      ),
    ));
    await tester.pumpAndSettle();

    // 長按（_onBookLongPress → _enterSelectionMode）已經把這本書放進
    // _selectedBookIds（見 library_screen.dart:295-297），不需要再多點一次
    // ——選取模式下再點一次同一本書會呼叫 _toggleBookSelection() 把它
    // 取消選取，反而導致 count == 0、下方按鈕被停用。
    await tester.longPress(find.byKey(const Key('book_item_b1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_remove_local_cache_button')));
    await tester.pumpAndSettle();

    final updated = (await repository.listBooks()).single;
    expect(updated.isDownloaded, isFalse);
    expect(updated.filePath, bookFile.path);
    expect(bookFile.existsSync(), isFalse);
    expect(updated.epubLocator, 'locator-json');
    expect(updated.progress, 0.5);
    expect(await bookmarksRepository.listByBook('b1'), hasLength(1));
  });

  testWidgets('選取非 Calibre 來源（本機匯入）書籍時，點擊「移除本機快取」不影響該書', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('library_remove_cache_local_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final bookFile = File('${tempDir.path}/local_book.epub')..writeAsStringSync('dummy');

    final book = Book(
      id: 'b2',
      title: '本機書',
      format: BookFileFormat.epub,
      filePath: bookFile.path,
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(2000),
    );
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(MaterialApp(
      home: LibraryScreen(
        repository: repository,
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(
          globalPrefs: const GlobalReaderPrefs.initial()
              .copyWith(openLastBookOnLaunch: false),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_b2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_remove_local_cache_button')));
    await tester.pumpAndSettle();

    final unchanged = (await repository.listBooks()).single;
    expect(unchanged.isDownloaded, isTrue);
    expect(bookFile.existsSync(), isTrue);
  });

  group('Issue 4：待下載書籍重新下載', () {
    late Directory tempRoot;
    late PathProviderPlatform originalPathProvider;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('library_redownload_test');
      originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = FakePathProviderPlatform(tempRoot.path);
    });

    tearDown(() {
      PathProviderPlatform.instance = originalPathProvider;
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    final server = RemoteServerProfile(
      id: 'srv1',
      name: '家用 NAS',
      baseUrl: 'http://192.168.1.100:8080/opds',
      type: RemoteServerType.opds,
      allowInsecure: false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    Book pendingBook() => Book(
          id: 'b1',
          title: '待下載的書',
          format: BookFileFormat.epub,
          filePath: '/no/longer/exists.epub',
          source: BookSource.calibreOpds,
          remoteServerId: 'srv1',
          remoteBookId: 'remote-1',
          remoteDownloadUrl: 'http://192.168.1.100:8080/opds/download/1.epub',
          isDownloaded: false,
          createTime: DateTime.fromMillisecondsSinceEpoch(1000),
          lastReadTime: DateTime.fromMillisecondsSinceEpoch(2000),
        );

    testWidgets('點擊待下載書籍先跳出確認對話框，取消則不觸發下載', (tester) async {
      final repository = FakeLibraryRepository(initialBooks: [pendingBook()]);
      final opdsClient = FakeOpdsClient();
      await tester.pumpWidget(MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
          remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
          createOpdsClient: () => opdsClient,
          isMobileDataConnection: () async => false,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_b1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('library_redownload_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('library_redownload_cancel_button')));
      await tester.pumpAndSettle();

      expect(opdsClient.downloadBookCalls, isEmpty);
    });

    testWidgets('偵測到行動數據連線時，確認對話框額外顯示流量提示文字', (tester) async {
      final repository = FakeLibraryRepository(initialBooks: [pendingBook()]);
      await tester.pumpWidget(MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
          remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
          createOpdsClient: () => FakeOpdsClient(),
          isMobileDataConnection: () async => true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_b1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('行動數據'), findsOneWidget);
    });

    testWidgets('確認後成功重新下載，更新 filePath/isDownloaded，不建立新的 Book 記錄', (tester) async {
      final repository = FakeLibraryRepository(initialBooks: [pendingBook()]);
      final opdsClient = FakeOpdsClient();
      await tester.pumpWidget(MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
          remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
          createOpdsClient: () => opdsClient,
          isMobileDataConnection: () async => false,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_b1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library_redownload_confirm_button')));
      await tester.pump();

      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      final books = await repository.listBooks();
      expect(books, hasLength(1));
      expect(books.single.id, 'b1');
      expect(books.single.isDownloaded, isTrue);
      expect(books.single.filePath, isNot('/no/longer/exists.epub'));
      expect(File(books.single.filePath).existsSync(), isTrue);
      expect(opdsClient.downloadBookCalls, ['http://192.168.1.100:8080/opds/download/1.epub']);
    });

    testWidgets('下載失敗時顯示錯誤訊息，書籍狀態不變', (tester) async {
      final repository = FakeLibraryRepository(initialBooks: [pendingBook()]);
      final opdsClient = FakeOpdsClient(downloadError: StateError('模擬下載失敗'));
      await tester.pumpWidget(MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(),
          remoteServerRepository: FakeRemoteServerRepository(initialServers: [server]),
          createOpdsClient: () => opdsClient,
          isMobileDataConnection: () async => false,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_b1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library_redownload_confirm_button')));
      await tester.pump();

      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('重新下載失敗，請稍後再試'), findsOneWidget);
      final books = await repository.listBooks();
      expect(books.single.isDownloaded, isFalse);
      expect(books.single.filePath, '/no/longer/exists.epub');
    });
  });
}

/// 刻意「非線性」的測試用 TextScaler：對較大的輸入值套用較低的有效縮放
/// 比例，模擬真實 Android「非線性字級縮放」曲線（避免超大字級把版面撐爆，
/// 對數值較大的輸入相對縮放得較保守）。`textScaleFactor == 1.0` 時
/// `scale(x) == x`（與線性/未縮放行為一致，不影響其他既有測試的既有假設），
/// `textScaleFactor > 1.0` 時，`scale(A) + scale(B)` 恆大於 `scale(A + B)`
/// （任何嚴格凹函式皆有此「拆開分別縮放，總和比整體一起縮放更大」的性質）
/// ——足以證明「把兩行文字字級合計成單一常數再縮放」與「兩行文字字級各自
/// 縮放再相加」在非線性曲線下不是同一件事。
class _NonLinearTextScaler extends TextScaler {
  const _NonLinearTextScaler(this.textScaleFactor);

  @override
  final double textScaleFactor;

  @override
  double scale(double fontSize) {
    if (textScaleFactor == 1.0) return fontSize;
    return fontSize + (textScaleFactor - 1.0) * 6.0 * sqrt(fontSize);
  }

  @override
  bool operator ==(Object other) =>
      other is _NonLinearTextScaler && other.textScaleFactor == textScaleFactor;

  @override
  int get hashCode => textScaleFactor.hashCode;
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
  DateTime? lastReadTime,
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
    lastReadTime: lastReadTime ?? now,
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
