import 'dart:async';

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

void main() {
  late SqliteLibraryRepository libraryRepository;
  late ReaderPrefsManager prefsManager;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
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

    // 切到列表模式，讓每本書對應到一個 ListTile，方便直接比對 widget 樹順序
    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    // 預設「最後閱讀」排序（新到舊）：lastReadTime 較晚的 B書應排在前面。直接
    // 比對 widget 樹中 ListTile 的資料順序，不依賴渲染座標（dy）比較，避免
    // 測試受螢幕尺寸、字型渲染或版面間距等排版細節變動影響而變得脆弱。
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

  testWidgets('點擊分類 tab 後，畫面只顯示該群組的書籍；點擊「全部」顯示所有書籍',
      (tester) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB = _testBook(id: '2', title: 'B書', groupName: BookGroup.uncategorized);
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

    await tester.tap(find.byKey(const Key('library_group_tab_奇幻')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsNothing);

    await tester.tap(find.byKey(const Key('library_group_tab_all')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);
  });

  testWidgets('管理分類對話框：新增分類後，新分類出現在 tab 列', (tester) async {
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

    await tester.tap(find.byKey(const Key('library_group_manage_button')));
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

    expect(find.byKey(const Key('library_group_tab_奇幻')), findsOneWidget);
  });

  testWidgets('管理分類對話框：刪除分類前彈出確認對話框，確認後該分類下書籍改顯示於「未分類」篩選',
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

    await tester.tap(find.byKey(const Key('library_group_manage_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_delete_button_奇幻')));
    await tester.pumpAndSettle();

    expect(find.text('刪除分類'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_group_delete_confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_group_tab_奇幻')), findsNothing);

    await tester.tap(
      find.byKey(Key('library_group_tab_${BookGroup.uncategorized}')),
    );
    await tester.pumpAndSettle();

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

    await tester.tap(find.byKey(const Key('library_group_manage_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_delete_button_奇幻')));
    await tester.pumpAndSettle();

    expect(find.text('刪除分類'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_group_manage_item_奇幻')), findsOneWidget);

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_group_tab_奇幻')), findsOneWidget);
    await tester.tap(find.byKey(const Key('library_group_tab_奇幻')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
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

    await tester.tap(find.byKey(const Key('library_group_manage_button')));
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

  testWidgets('管理分類對話框：重新命名分類後，tab 列顯示新名稱', (tester) async {
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

    await tester.tap(find.byKey(const Key('library_group_manage_button')));
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

    expect(find.byKey(const Key('library_group_tab_科幻')), findsOneWidget);
  });

  testWidgets('刪除目前篩選中的分類後，畫面自動退回「全部」篩選（不留在已不存在的分類）',
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

    await tester.tap(find.byKey(const Key('library_group_tab_奇幻')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_manage_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_delete_button_奇幻')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_group_delete_confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();

    // 該書已改列「未分類」；篩選應已自動退回「全部」，故仍可見
    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
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

    expect(find.byKey(const Key('library_group_tab_歷史小說')), findsOneWidget);
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

    await tester.tap(find.byKey(const Key('library_group_tab_奇幻')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);
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

    await tester.tap(find.byKey(const Key('library_group_tab_奇幻')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);
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
}

Book _testBook({
  required String id,
  required String title,
  String? author,
  String groupName = BookGroup.uncategorized,
  String? filePath,
}) {
  final now = DateTime.now();
  return Book(
    id: id,
    title: title,
    author: author,
    format: BookFileFormat.epub,
    filePath: filePath ?? 'content://example/$id.epub',
    source: BookSource.local,
    groupName: groupName,
    createTime: now,
    lastReadTime: now,
  );
}
