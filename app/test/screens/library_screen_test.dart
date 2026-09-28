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
import 'package:elinkbook/reader/text_conversion_mode.dart';
import 'package:elinkbook/reader/layout_preset_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager.dart';
import 'package:elinkbook/screens/library_paging.dart';
import 'package:elinkbook/screens/library_screen.dart';
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/screens/library_search_screen.dart';

import '../support/fake_full_text_search_settings_repository.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/widgets/book_cover.dart';


import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/pump_localized_widget.dart';
import '../support/fake_search_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_opds_client.dart';
import '../support/fake_remote_server_repository.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import '../support/fake_highlights_repository.dart';
import '../support/fake_notes_repository.dart';
import '../support/fake_tts_provider.dart';
import 'package:elinkbook/reader/tts_audio_handler.dart';
import '../support/fake_tts_audio_focus_source.dart';
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
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/screens/book_action_sheet.dart';
import 'package:elinkbook/screens/widgets/eb_sheet_shell.dart';
import '../support/fake_book_reader_prefs_repository.dart';

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
    libraryRepository = await SqliteLibraryRepository.open(
      inMemoryDatabasePath,
    );
    // epic-18-reader-device-qa Issue 29：openLastBookOnLaunch 預設 true，
    // 會讓頂層 LibraryScreen 啟動當下自動導向最後閱讀的書籍——這個共用
    // fixture 供本檔案絕大多數測試使用，這些測試的斷言目標是書架本身的
    // 行為，並非這個自動開書的新功能，故在這裡明確關閉，避免每個既有測試
    // 都被意外導覽到 ReaderScreen 而斷言失敗。Issue 29 自己的測試（見
    // 「openLastBookOnLaunch=...」系列）各自建立獨立的 FakeReaderPrefsManager
    // 明確開啟，不受這裡影響。
    prefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(openLastBookOnLaunch: false),
      ),
    );
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  testWidgets('圖書庫為空時顯示「尚未匯入書籍」提示與匯入按鈕', (tester) async {
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    expect(find.text('書架'), findsOneWidget);
    expect(find.text('尚未匯入書籍'), findsOneWidget);
    expect(
      find.byKey(const Key('library_empty_import_button')),
      findsOneWidget,
    );
  });

  testWidgets('圖書庫載入資料失敗時，畫面降級顯示空清單狀態而非永遠卡在載入中', (tester) async {
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(throwOnListBooks: true),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    expect(find.text('尚未匯入書籍'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('有書籍時，書架 grid 呈現正確渲染書籍項目（標題、進度固定 0%）', (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢', author: '曹雪芹');
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_grid_view')), findsOneWidget);
    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    final bookItemFinder = find.byKey(const Key('book_item_1'));
    // Issue 9：該書無 coverPath，BookCover 退回 CoverPlaceholder，其內建的
    // 書名縮略文字跟 _BookGridTile 本身的標題 caption 各自顯示一次「紅樓
    // 夢」，兩者皆是核准設計、非回歸，預期恰好 2 個匹配；限定在
    // book_item_1 範圍內查找，避免繼續閱讀列（Issue 3）額外渲染的同名
    // 文字被誤計入（`review-plan-issue-3.md` I-1）。
    expect(
      find.descendant(of: bookItemFinder, matching: find.text('紅樓夢')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: bookItemFinder, matching: find.text('0%')),
      findsOneWidget,
    );
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
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    final delegate =
        tester
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
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    final delegate =
        tester
                .widget<GridView>(find.byKey(const Key('library_grid_view')))
                .gridDelegate
            as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 4);
  });

  group('書架搜尋（2026-09-08 /grill-with-docs 使用者需求，比照 '
      'prototype/elinkbook_theme_prototype.html 常駐搜尋列設計）', () {
    // 2026-09-28 使用者需求：取代原「AppBar 下方常駐搜尋列」——搜尋列改收
    // 在標題列的 🔍 按鈕，點了才在標題列展開，不佔書架內容區高度（讓
    // Mobiscribe Wave 排得下兩列封面）。
    testWidgets('搜尋列預設收合在標題列 🔍 按鈕，點了在標題列展開，點 ✕ 清空並收合',
        (tester) async {
      final book = _testBook(id: '1', title: '紅樓夢');
      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: FakeLibraryRepository(initialBooks: [book]),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
    );
      await tester.pumpAndSettle();

      final field = find.byKey(const Key('library_search_field'));
      final toggle = find.byKey(const Key('library_search_toggle_button'));
      expect(field, findsNothing);
      expect(
        find.descendant(of: find.byType(AppBar), matching: toggle),
        findsOneWidget,
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(AppBar), matching: field),
        findsOneWidget,
      );

      await tester.enterText(field, '紅');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library_search_close_button')));
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      expect(toggle, findsOneWidget);
      // 收合時一併清空關鍵字，書架恢復完整清單。
      expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    });

    testWidgets('輸入搜尋字串後，僅顯示書名或作者符合的書籍（不分大小寫），且不再顯示分類拼貼格',
        (tester) async {
      final books = [
        _testBook(id: '1', title: '紅樓夢', author: '曹雪芹', groupName: '古典文學'),
        _testBook(id: '2', title: 'Dune', author: 'Frank Herbert', groupName: '科幻'),
        _testBook(id: '3', title: '三國演義', author: '羅貫中', groupName: '古典文學'),
      ];
      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: FakeLibraryRepository(initialBooks: books),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
    );
      await tester.pumpAndSettle();

      // 搜尋前：分類拼貼格存在。
      expect(find.byKey(const Key('group_tile_古典文學')), findsOneWidget);
      expect(find.byKey(const Key('group_tile_科幻')), findsOneWidget);

      await _openLibrarySearchField(tester);

      await tester.enterText(
        find.byKey(const Key('library_search_field')),
        'dune',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('group_tile_古典文學')), findsNothing,
          reason: '搜尋中應改為扁平清單，不再顯示分類拼貼格。');
      expect(find.byKey(const Key('group_tile_科幻')), findsNothing);
      expect(find.byKey(const Key('book_item_2')), findsOneWidget);
      expect(find.byKey(const Key('book_item_1')), findsNothing);
      expect(find.byKey(const Key('book_item_3')), findsNothing);
    });

    testWidgets('清空搜尋字串後，恢復原本的分類拼貼格與書籍清單瀏覽畫面', (tester) async {
      final books = [
        _testBook(id: '1', title: '紅樓夢', groupName: '古典文學'),
        _testBook(id: '2', title: 'Dune', groupName: '科幻'),
      ];
      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: FakeLibraryRepository(initialBooks: books),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
    );
      await tester.pumpAndSettle();

      await _openLibrarySearchField(tester);

      await tester.enterText(
        find.byKey(const Key('library_search_field')),
        'dune',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('group_tile_古典文學')), findsNothing);

      await _openLibrarySearchField(tester);

      await tester.enterText(find.byKey(const Key('library_search_field')), '');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('group_tile_古典文學')), findsOneWidget);
      expect(find.byKey(const Key('group_tile_科幻')), findsOneWidget);
    });

    testWidgets('已鑽入某分類時輸入搜尋字串，仍搜尋全書庫（忽略目前分類瀏覽狀態）',
        (tester) async {
      final books = [
        _testBook(id: '1', title: '紅樓夢', groupName: '古典文學'),
        _testBook(id: '2', title: 'Dune', groupName: '科幻'),
      ];
      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: FakeLibraryRepository(initialBooks: books),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
    );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('group_tile_古典文學')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('book_item_2')), findsNothing,
          reason: '尚未搜尋前，鑽入「古典文學」分類看不到「科幻」分類的書籍。');

      await _openLibrarySearchField(tester);

      await tester.enterText(
        find.byKey(const Key('library_search_field')),
        'dune',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('book_item_2')), findsOneWidget,
          reason: '搜尋範圍應忽略目前分類瀏覽狀態，仍能找到「科幻」分類的 Dune。');
    });

    testWidgets('未輸入文字時不顯示清除按鈕，輸入文字後才顯示', (tester) async {
      final book = _testBook(id: '1', title: '紅樓夢');
      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: FakeLibraryRepository(initialBooks: [book]),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
    );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('library_search_clear_button')), findsNothing);

      await _openLibrarySearchField(tester);

      await tester.enterText(find.byKey(const Key('library_search_field')), '紅');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('library_search_clear_button')), findsOneWidget);
    });

    testWidgets('點擊清除按鈕後，清空搜尋框並恢復原本的分類拼貼格與書籍清單瀏覽畫面', (tester) async {
      final books = [
        _testBook(id: '1', title: '紅樓夢', groupName: '古典文學'),
        _testBook(id: '2', title: 'Dune', groupName: '科幻'),
      ];
      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: FakeLibraryRepository(initialBooks: books),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
    );
      await tester.pumpAndSettle();

      await _openLibrarySearchField(tester);

      await tester.enterText(find.byKey(const Key('library_search_field')), 'dune');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('group_tile_古典文學')), findsNothing);

      await tester.tap(find.byKey(const Key('library_search_clear_button')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byKey(const Key('library_search_field'))).controller!.text,
        isEmpty,
      );
      expect(find.byKey(const Key('library_search_clear_button')), findsNothing);
      expect(find.byKey(const Key('group_tile_古典文學')), findsOneWidget);
      expect(find.byKey(const Key('group_tile_科幻')), findsOneWidget);
    });
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
      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: FakeLibraryRepository(initialBooks: [book]),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
    );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // 主題圓點已搬離書架 AppBar，不應再出現於此。
      expect(find.byKey(const Key('library_theme_dot_light')), findsNothing);
    },
  );

  testWidgets('裝置旋轉（MediaQuery 從直立變橫放）後，書架封面欄數即時從 3 變為 4，不需要重新導航或重建整個畫面', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final book = _testBook(id: '1', title: '紅樓夢');
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
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
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    final delegate =
        tester
                .widget<GridView>(find.byKey(const Key('library_grid_view')))
                .gridDelegate
            as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisSpacing, 8);
    // 2026-09-28：列間距 12 → 4（讓 Mobiscribe Wave 排得下兩列封面）。
    expect(delegate.mainAxisSpacing, 4);
  });

  testWidgets('從閱讀器返回書架時，重新載入書籍清單，避免後續操作以過期資料覆寫最新進度', (tester) async {
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

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('book_item_1')),
        matching: find.text('0%'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    // widget test 環境無法真正渲染原生 PlatformView 觸發 ReaderScreen 的
    // 位置寫入路徑，這裡直接呼叫 repository.updateBook 模擬「ReaderScreen
    // 已透過 ReadingPositionRepository 把最新進度寫入資料庫」這個結果
    // （見 Critical 2 審查意見的觸發情境）。
    await repository.updateBook(
      Book(
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
      ),
    );

    // 返回書架（點擊 ReaderChromeTopBar 的返回鍵）。改用明確的 Key 尋找，
    // 不再用 tester.pageBack()——後者靠比對 Material 預設 BackButton 的
    // 英文 tooltip「Back」／CupertinoNavigationBarBackButton 型別辨識，
    // 我們的自訂按鈕 tooltip 是中文「返回」，比對不到
    // （epic-38-reader-chrome-tts-redesign Issue 1，Scaffold.appBar 已
    // 改為恆為 null，返回鍵完全由 ReaderChromeTopBar 承載）。
    await tester.tap(find.byKey(const Key('reader_chrome_back_button')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('book_item_1')),
        matching: find.text('50%'),
      ),
      findsOneWidget,
      reason:
          '返回書架後應重新載入書籍清單，顯示閱讀器寫入的最新進度，'
          '而非停留在舊快照的 0%',
    );
  });

  testWidgets('全域簡繁轉換為繁體時，書架格狀視圖書名依轉換模式呈現（epic-42-text-conversion Issue 3）',
      (tester) async {
    final book = _testBook(id: '1', title: '国电脑');
    final localPrefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(
          openLastBookOnLaunch: false,
          textConversion: TextConversionMode.toTraditional,
        ),
      ),
    );
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: localPrefsManager,
        ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('book_item_1')),
        matching: find.text('國電腦'),
      ),
      findsNWidgets(2),
      reason: 'CoverPlaceholder 書名縮略與卡片下方標題文字各顯示一次，比照既有測試慣例',
    );
    expect(find.text('国电脑'), findsNothing);
  });

  testWidgets('全域簡繁轉換為繁體時，書架列表視圖書名／作者依轉換模式呈現（epic-42-text-conversion Issue 3）',
      (tester) async {
    final book = _testBook(id: '1', title: '国电脑', author: '电脑作者');
    final localPrefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(
          openLastBookOnLaunch: false,
          textConversion: TextConversionMode.toTraditional,
        ),
      ),
    );
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: localPrefsManager,
        ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_view_toggle_option')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('book_item_1')),
        matching: find.text('國電腦'),
      ),
      findsNWidgets(2),
      reason: 'CoverPlaceholder 書名縮略與列標題文字各顯示一次，比照既有測試慣例',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('book_item_1')),
        matching: find.text('電腦作者'),
      ),
      findsOneWidget,
      reason: '作者僅顯示於列表副標題，CoverPlaceholder 不含作者欄位',
    );
  });

  testWidgets('全域簡繁轉換為繁體時，繼續閱讀列書名依轉換模式呈現（epic-42-text-conversion Issue 3）',
      (tester) async {
    final book = _testBook(
      id: '1',
      title: '国电脑',
      lastReadTime: DateTime(2026, 1, 1),
    );
    final localPrefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(
          openLastBookOnLaunch: false,
          textConversion: TextConversionMode.toTraditional,
        ),
      ),
    );
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: localPrefsManager,
        ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('library_continue_reading_row')),
        matching: find.text('國電腦'),
      ),
      findsOneWidget,
      reason: '2026-09-28 繼續閱讀列縮圖縮成 30x42 後，BookCover 佔位圖太小、'
          '依其既有門檻不顯示書名縮略，只剩 _ContinueReadingRow 標題文字一處',
    );
  });

  testWidgets('全域簡繁轉換為繁體時，書籍詳細資料對話框書名／作者依轉換模式呈現（epic-42-text-conversion Issue 3）',
      (tester) async {
    final book = _testBook(id: '1', title: '国电脑', author: '电脑作者');
    final localPrefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(
          openLastBookOnLaunch: false,
          textConversion: TextConversionMode.toTraditional,
        ),
      ),
    );
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: localPrefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('詳細資料'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('book_details_dialog')),
        matching: find.text('國電腦'),
      ),
      findsOneWidget,
    );
    expect(find.text('作者：電腦作者'), findsOneWidget);
  });

  testWidgets('外部刷新訊號觸發時，重新載入全域簡繁轉換預設值（epic-42-text-conversion Issue 3）',
      (tester) async {
    final book = _testBook(id: '1', title: '国电脑');
    final localPrefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(openLastBookOnLaunch: false),
      ),
    );
    final refreshSignal = ChangeNotifier();
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: localPrefsManager,
          refreshSignal: refreshSignal,
        ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('book_item_1')),
        matching: find.text('国电脑'),
      ),
      findsNWidgets(2),
      reason: 'CoverPlaceholder 縮略與卡片標題各顯示一次，比照既有測試慣例（轉換前）',
    );

    localPrefsManager.globalPrefs = localPrefsManager.globalPrefs.copyWith(
      reading: const ReadingDefaults(
        openLastBookOnLaunch: false,
        textConversion: TextConversionMode.toTraditional,
      ),
    );
    refreshSignal.notifyListeners();
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('book_item_1')),
        matching: find.text('國電腦'),
      ),
      findsNWidgets(2),
      reason: 'CoverPlaceholder 縮略與卡片標題各顯示一次，比照既有測試慣例（轉換後）',
    );
  });

  testWidgets('全域簡繁轉換為繁體時，單書動作選單頂部標題依轉換模式呈現（epic-42-text-conversion Issue 3，審查修正 I-1）',
      (tester) async {
    final book = _testBook(id: '1', title: '国电脑');
    final localPrefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(
          openLastBookOnLaunch: false,
          textConversion: TextConversionMode.toTraditional,
        ),
      ),
    );
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: localPrefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();

    expect(find.text('國電腦'), findsWidgets,
        reason: '書架卡片（CoverPlaceholder 縮略＋標題）與動作選單頂部標題皆顯示已轉換文字');
    expect(find.text('国电脑'), findsNothing);
  });

  testWidgets('切換檢視模式按鈕後，書架從 grid 切換為列表呈現', (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢', author: '曹雪芹');
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_grid_view')), findsOneWidget);
    expect(find.byKey(const Key('library_list_view')), findsNothing);

    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_view_toggle_option')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_grid_view')), findsNothing);
    expect(find.byKey(const Key('library_list_view')), findsOneWidget);
    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
  });

  testWidgets('切換檢視模式後，重新建立 LibraryScreen 仍維持上次選擇（模擬 App 重啟）', (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢', author: '曹雪芹');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_grid_view')), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_view_toggle_option')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_list_view')), findsOneWidget);

    // 模擬 App 重啟：SharedPreferences.setMockInitialValues 的模擬儲存體會
    // 延續到同一個測試行程內建立的新 LibraryScreen 實例，等同於重啟後讀到
    // 上次寫入的值。
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          key: const Key('library_screen_after_restart'),
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
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

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [bookB, bookA]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_view_toggle_option')));
    await tester.pumpAndSettle();

    // 兩本書皆為預設「未分類」——「未分類」不使用拼貼格顯示（見【診斷
    // 修正】），故書架上沒有拼貼格 ListTile，只有書籍本身的 ListTile。
    var titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .toList();
    expect(titles, ['B書', 'A書']);

    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_option_title')));
    await tester.pumpAndSettle();

    titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .toList();
    expect(titles, ['A書', 'B書']);
  });

  testWidgets('排序方式選擇會持久化，重新建立 LibraryScreen 後仍維持上次選擇', (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢', author: '曹雪芹');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_option_author')));
    await tester.pumpAndSettle();

    // 模擬 App 重啟
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          key: const Key('library_screen_after_restart'),
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('library_sort_option_author')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
  });

  testWidgets('點擊分類拼貼格後只顯示該分類書籍；返回書架後僅顯示未分類書籍與分類拼貼格（已分類書籍不重複列出）', (
    tester,
  ) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB = _testBook(
      id: '2',
      title: 'B書',
      groupName: BookGroup.uncategorized,
    );
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    // 【審查修正】bookA 已歸類到「奇幻」，頂層書架不應重複列出，只透過
    // 「奇幻」拼貼格顯示；bookB 是「未分類」，仍照舊直接列在書籍清單中。
    expect(find.byKey(const Key('book_item_1')), findsNothing);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsNothing);

    await tester.tap(find.byKey(const Key('library_back_from_group_button')));
    await tester.pumpAndSettle();

    expect(find.text('書架'), findsOneWidget);
    expect(find.byKey(const Key('book_item_1')), findsNothing);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);
  });

  testWidgets(
    '分類拼貼格內，有封面圖片的書籍格與無封面佔位符格渲染高度一致'
    '（根因見本計劃 Task 2「Discovery 發現」：_GroupGridTile 內部 Row'
    ' 預設寬鬆 cross-axis 約束，已於規劃階段以 widget test 重現）',
    (tester) async {
      final tempDir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('group_tile_height_test'),
      ))!;
      addTearDown(() => tester.runAsync(() => tempDir.delete(recursive: true)));
      final coverFile = File('${tempDir.path}/cover.png');
      await tester.runAsync(() => coverFile.writeAsBytes(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
              '42YAAAAASUVORK5CYII=',
            ),
          ));

      final bookWithCover = _testBook(
        id: '1',
        title: '有封面的書',
        groupName: '測試分類',
        coverPath: coverFile.path,
      );
      final bookWithoutCover = _testBook(
        id: '2',
        title: '沒有封面的書',
        groupName: '測試分類',
      );
      final repository = FakeLibraryRepository(
        initialBooks: [bookWithCover, bookWithoutCover],
      );

      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: repository,
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
    );
      await tester.pumpAndSettle();

      final groupTileFinder = find.byKey(const Key('group_tile_測試分類'));
      expect(groupTileFinder, findsOneWidget);

      final cellsFinder =
          find.descendant(of: groupTileFinder, matching: find.byType(BookCover));
      expect(cellsFinder, findsNWidgets(2));
      final firstSize = tester.getSize(cellsFinder.at(0));
      final secondSize = tester.getSize(cellsFinder.at(1));
      expect(firstSize.height, secondSize.height);
    },
  );

  testWidgets('管理分類對話框：新增分類後，因無書籍歸屬，書架不會顯示該分類的拼貼格', (tester) async {
    final repository = FakeLibraryRepository();
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
        repository: repository,
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_manage_groups_option')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('library_group_add_field')),
      '奇幻',
    );
    await tester.tap(find.byKey(const Key('library_group_add_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_group_manage_item_奇幻')),
      findsOneWidget,
    );

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();

    // 新分類目前沒有任何書籍歸屬，_buildGroupTiles() 只保留非空分類，故
    // 書架上不會出現「奇幻」拼貼格（design.md 決策：拼貼格只代表非空分類）。
    expect(find.byKey(const Key('group_tile_奇幻')), findsNothing);
  });

  testWidgets('管理分類對話框：刪除分類前彈出確認對話框，確認後該分類下書籍改顯示於書架頂層的「未分類」書籍清單中', (
    tester,
  ) async {
    final book = _testBook(id: '1', title: '奇幻小說', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
        repository: repository,
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
      ),
    );
    await tester.pumpAndSettle();

    // 刪除前書籍已歸類到「奇幻」，只透過拼貼格顯示，頂層書籍清單看不到它。
    expect(find.byKey(const Key('book_item_1')), findsNothing);

    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_manage_groups_option')));
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

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
        repository: repository,
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_manage_groups_option')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_delete_button_奇幻')));
    await tester.pumpAndSettle();

    expect(find.text('刪除分類'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_group_manage_item_奇幻')),
      findsOneWidget,
    );

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('group_tile_奇幻')), findsOneWidget);
    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
  });

  testWidgets('管理分類對話框：嘗試刪除「未分類」時操作被禁止（找不到刪除/重新命名按鈕）', (tester) async {
    final repository = FakeLibraryRepository();
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
        repository: repository,
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_manage_groups_option')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('library_group_delete_button_${BookGroup.uncategorized}')),
      findsNothing,
    );
    expect(
      find.byKey(Key('library_group_rename_button_${BookGroup.uncategorized}')),
      findsNothing,
    );
  });

  testWidgets('管理分類對話框：重新命名分類後，拼貼格顯示新名稱', (tester) async {
    final book = _testBook(id: '1', title: '奇幻小說', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
        repository: repository,
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_manage_groups_option')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_rename_button_奇幻')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('library_group_rename_field')),
      '科幻',
    );
    await tester.tap(find.byKey(const Key('library_group_rename_confirm')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_group_manage_item_科幻')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('library_group_manage_item_奇幻')), findsNothing);

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('group_tile_科幻')), findsOneWidget);
    expect(find.byKey(const Key('group_tile_奇幻')), findsNothing);
  });

  testWidgets('長按書籍卡片後進入選取模式，且該卡片顯示為已選取狀態', (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢');
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
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
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [bookA, bookB]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
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

  testWidgets('選取模式下點擊「✕ 取消」後恢復一般瀏覽狀態，且卡片點擊恢復導覽進閱讀器', (tester) async {
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      filePath: 'content://example/1.unknown',
    );
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library_selection_app_bar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_selection_cancel_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_selection_app_bar')), findsNothing);
    expect(find.byKey(const Key('library_sort_view_button')), findsOneWidget);
    expect(find.byKey(const Key('book_selection_indicator_1')), findsNothing);

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    // 用 .unknown 檔名讓 ReaderScreen 命中「不支援格式」分支（純 Dart 安全路徑，
    // 不觸發 AndroidView；見 reader_screen_test.dart 既有模式），只用來證明
    // 「導覽確實發生」，不驗證實際閱讀渲染。2026-09-12 起 TopBar 標題一律為空
    // 字串，不再顯示書名，故僅驗證 ReaderScreen 已推入且顯示不支援提示。
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.text('不支援的檔案格式'), findsOneWidget);
  });

  testWidgets('選取模式下觸發系統返回鍵時退出選取模式，而非真的離開畫面', (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢');
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
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

  testWidgets('選取多本書後點擊「移動到分類」，選擇目的分類後所有已勾選書籍的分類皆更新', (tester) async {
    final bookA = _testBook(
      id: '1',
      title: 'A書',
      groupName: BookGroup.uncategorized,
    );
    final bookB = _testBook(
      id: '2',
      title: 'B書',
      groupName: BookGroup.uncategorized,
    );
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);
    await repository.upsertGroup('奇幻');

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
        repository: repository,
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
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

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);
  });

  testWidgets('選取多本 EPUB 書籍後點擊「強制 FXL」，所有已選取書籍的 isFixedLayout 皆變為 true', (
    tester,
  ) async {
    final bookA = _testBook(id: '1', title: 'A漫畫');
    final bookB = _testBook(id: '2', title: 'B漫畫');
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
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

    expect(
      find.byKey(const Key('library_selection_app_bar')),
      findsNothing,
      reason: '執行後應立即退出選取模式（比照移動到分類既有行為）',
    );

    final updated = await repository.listBooks();
    expect(updated.firstWhere((b) => b.id == '1').isFixedLayout, isTrue);
    expect(updated.firstWhere((b) => b.id == '2').isFixedLayout, isTrue);
  });

  testWidgets('選取集合混雜 EPUB 與 PDF 時，點擊「強制 FXL」只影響 EPUB、PDF 不受影響也不拋錯', (
    tester,
  ) async {
    final epubBook = _testBook(id: '1', title: 'A漫畫');
    final pdfBook = _testBook(
      id: '2',
      title: 'B文件',
      format: BookFileFormat.pdf,
      filePath: 'content://example/2.pdf',
    );
    final repository = FakeLibraryRepository(initialBooks: [epubBook, pdfBook]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
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
    expect(
      updated.firstWhere((b) => b.id == '2').isFixedLayout,
      isNull,
      reason: 'PDF 不具備 isFixedLayout 語意，應完全不受影響',
    );
  });

  testWidgets('選取集合全為非 EPUB 時，「強制 FXL」按鈕仍然顯示（不隱藏/不因格式停用）', (tester) async {
    final pdfBook = _testBook(
      id: '1',
      title: 'A文件',
      format: BookFileFormat.pdf,
      filePath: 'content://example/1.pdf',
    );
    final repository = FakeLibraryRepository(initialBooks: [pdfBook]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_force_fxl_button')), findsOneWidget);

    final button = tester.widget<IconButton>(
      find.byKey(const Key('library_force_fxl_button')),
    );
    expect(
      button.onPressed,
      isNotNull,
      reason: 'count > 0 時按鈕應可點擊，不因選取內容全為非 EPUB 而停用',
    );
  });

  testWidgets('選取多本 EPUB 書籍後點擊「恢復自動判斷」，對每本已選取書籍呼叫 detectAndCacheEpubLayout', (
    tester,
  ) async {
    final bookA = _testBook(id: '1', title: 'A漫畫', isFixedLayout: true);
    final bookB = _testBook(id: '2', title: 'B漫畫', isFixedLayout: true);
    final repository = FakeLibraryRepository(
      initialBooks: [bookA, bookB],
      detectedIsFixedLayout: false,
    );

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_item_2')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_restore_auto_layout_button')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_selection_app_bar')), findsNothing);
    expect(repository.detectAndCacheEpubLayoutCalls, containsAll(['1', '2']));
    final updated = await repository.listBooks();
    expect(updated.firstWhere((b) => b.id == '1').isFixedLayout, isFalse);
    expect(updated.firstWhere((b) => b.id == '2').isFixedLayout, isFalse);
  });

  testWidgets('選取集合混雜 EPUB 與 TXT 時，點擊「恢復自動判斷」只影響 EPUB、TXT 不受影響也不拋錯', (
    tester,
  ) async {
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

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_item_2')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_restore_auto_layout_button')),
    );
    await tester.pumpAndSettle();

    expect(repository.detectAndCacheEpubLayoutCalls, ['1']);
  });

  testWidgets('選取集合全為非 EPUB 時，「恢復自動判斷」按鈕仍然顯示（不隱藏/不因格式停用）', (tester) async {
    final txtBook = _testBook(
      id: '1',
      title: 'A文字書',
      format: BookFileFormat.txt,
      filePath: 'content://example/1.txt',
    );
    final repository = FakeLibraryRepository(initialBooks: [txtBook]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
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

  testWidgets('書架（grid）與列表兩種檢視皆能觸發長按進入選取模式並完成批次移動', (tester) async {
    final bookA = _testBook(
      id: '1',
      title: 'A書',
      groupName: BookGroup.uncategorized,
    );
    final bookB = _testBook(
      id: '2',
      title: 'B書',
      groupName: BookGroup.uncategorized,
    );
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);
    await repository.upsertGroup('奇幻');

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
        repository: repository,
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_view_toggle_option')));
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

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);
  });

  testWidgets('點擊分類拼貼格為原地狀態切換；下鑽後不顯示拼貼格區塊與管理分類選單項目', (
    tester,
  ) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB = _testBook(
      id: '2',
      title: 'B書',
      groupName: BookGroup.uncategorized,
    );
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    // AppBar 標題顯示分類名稱，不是「書架」。
    expect(find.text('奇幻'), findsOneWidget);

    // 原地下鑽後畫面樹上只有一個 LibraryScreen——不再顯示拼貼格區塊。
    expect(find.byKey(const Key('group_tile_奇幻')), findsNothing);

    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library_manage_groups_option')), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsNothing);
  });

  testWidgets('在分類篩選畫面把書移到其他分類後點擊返回按鈕回到書架，頂層拼貼格即時反映最新狀態', (
    tester,
  ) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB = _testBook(id: '2', title: 'B書', groupName: '科幻');
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
        repository: repository,
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('奇幻 (1 本)'), findsOneWidget);
    expect(find.text('科幻 (1 本)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_move_to_group_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_move_to_group_option_科幻')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_back_from_group_button')));
    await tester.pumpAndSettle();

    // bookA 已被移出「奇幻」——「奇幻」拼貼格應消失（剩 0 本），「科幻」
    // 拼貼格應顯示 2 本。
    expect(find.byKey(const Key('group_tile_奇幻')), findsNothing);
    expect(find.text('科幻 (2 本)'), findsOneWidget);
  });

  testWidgets('分類拼貼格彼此的相對順序跟隨目前選定的排序模式（最後閱讀），'
      '而非固定依分類名稱排序（epic-18-reader-device-qa Issue 31）', (tester) async {
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

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    // 切到列表檢視，方便用 ListTile.title 比對拼貼格彼此的相對順序
    // （格狀檢視的 _GroupGridTile 是 InkWell，不是 ListTile，比照既有
    // 「新分類拼貼格排在「未分類」之前」測試的既有寫法）。
    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_view_toggle_option')));
    await tester.pumpAndSettle();

    final tileTitles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .where((title) => title == '奇幻' || title == '一般叢書' || title == '武俠')
        .toList();
    expect(
      tileTitles,
      ['奇幻', '武俠', '一般叢書'],
      reason:
          'LibraryScreen 預設排序模式為「最後閱讀」，拼貼格順序應依各分類'
          '最近一次被閱讀的書籍（lastReadTime 最新）排列，而非分類名稱字母序',
    );
  });

  testWidgets('選取模式下 AppBar 顯示刪除按鈕，取消刪除確認對話框不會呼叫 deleteBook', (tester) async {
    final book = _testBook(id: '1', title: '測試書');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_delete_books_button')),
      findsOneWidget,
    );

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

  testWidgets('選取多本書後點擊刪除並確認，每個已選取 id 各被呼叫一次 deleteBook，書籍從列表消失', (
    tester,
  ) async {
    final bookA = _testBook(id: '1', title: 'A書');
    final bookB = _testBook(id: '2', title: 'B書');
    final bookC = _testBook(id: '3', title: 'C書');
    final repository = FakeLibraryRepository(
      initialBooks: [bookA, bookB, bookC],
    );

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
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
      await coverFile.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
          '42YAAAAASUVORK5CYII=',
        ),
      );
    });

    final book = _testBook(
      id: '1',
      title: '測試書',
      filePath: bookFile.path,
      coverPath: coverFile.path,
    );
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
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

  testWidgets('書籍 filePath 為外部 content:// 參照時，刪除書籍不會嘗試刪除原始檔案也不拋例外', (
    tester,
  ) async {
    final book = _testBook(
      id: '1',
      title: '測試書',
      filePath: 'content://com.android.externalstorage.documents/document/1234',
    );
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
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

      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: FakeLibraryRepository(initialBooks: [book]),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
            readerFeatureRepositories: LibraryReaderFeatureRepositories(
              highlightsRepository: highlightsRepository,
              notesRepository: notesRepository,
            ),
          ),
    );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_1')));
      await tester.pumpAndSettle();

      final readerScreen = tester.widget<ReaderScreen>(
        find.byType(ReaderScreen),
      );
      expect(
        readerScreen.highlightsRepository,
        same(highlightsRepository),
        reason:
            'LibraryScreen._openBook() 修正前，highlightsRepository 從未'
            '貫穿給 ReaderScreen，一律為 null（見 issues.md Issue 6 背景）',
      );
      expect(readerScreen.notesRepository, same(notesRepository));
    },
  );

  testWidgets(
    'LibraryScreen 點開一本書後，ReaderScreen 收到的 ttsProvider 正確貫穿（Issue 9 缺口修正）',
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
      final ttsProvider = FakeTtsProvider();

      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: FakeLibraryRepository(initialBooks: [book]),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
            readerFeatureRepositories: LibraryReaderFeatureRepositories(
              ttsProvider: ttsProvider,
            ),
          ),
    );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_1')));
      await tester.pumpAndSettle();

      final readerScreen = tester.widget<ReaderScreen>(
        find.byType(ReaderScreen),
      );
      expect(
        readerScreen.ttsProvider,
        same(ttsProvider),
        reason:
            'LibraryScreen._openBook() 修正前，ttsProvider 從未貫穿給 '
            'ReaderScreen，一律為 null（見 issues.md Issue 9 背景）',
      );
    },
  );

  testWidgets('LibraryScreen 點開一本書後，ReaderScreen 收到的 ttsAudioHandler／'
      'ttsAudioFocusSource 正確貫穿（epic-34-tts-readalong Issue 7）', (
    tester,
  ) async {
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      filePath: 'content://example/1.txt',
    );
    final ttsAudioHandler = TtsAudioHandler();
    final ttsAudioFocusSource = FakeTtsAudioFocusSource();

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            ttsAudioHandler: ttsAudioHandler,
            ttsAudioFocusSource: ttsAudioFocusSource,
          ),
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.ttsAudioHandler, same(ttsAudioHandler));
    expect(readerScreen.ttsAudioFocusSource, same(ttsAudioFocusSource));
  });

  testWidgets(
      'LibraryScreen 點開一本書後，ReaderScreen 收到的 searchRepository／'
      'isFullTextSearchAvailable 正確貫穿（epic-10-search Issue 8）', (
    tester,
  ) async {
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      filePath: 'content://example/1.txt',
    );
    final searchRepository = FakeSearchRepository();

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            searchRepository: searchRepository,
            isFullTextSearchAvailable: false,
          ),
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.searchRepository, same(searchRepository));
    expect(readerScreen.isFullTextSearchAvailable, isFalse);
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

      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: repository,
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
    );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_1')));
      await tester.pumpAndSettle();

      final readerScreen = tester.widget<ReaderScreen>(
        find.byType(ReaderScreen),
      );
      expect(readerScreen.isFixedLayout, isFalse);
      expect(readerScreen.libraryRepository, same(repository));
    },
  );

  testWidgets('透過 LibraryScreen 開啟已有劃線/備註資料的 PDF 書籍後，'
      '「劃線與備註」分頁正確顯示既有資料而非空狀態（Issue 6 缺口修正）', (tester) async {
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
    await highlightsRepository.insert(
      const Highlight(
        id: 'h_lib_1',
        bookId: '1',
        style: HighlightStyle.highlighterYellow,
        pdfPageIndex: 0,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
      ),
    );

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
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

    final notesButton = find.byKey(const Key('reader_chrome_annotations_button'));
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

    expect(
      find.byKey(const Key('notes_sheet_annotation_list')),
      findsOneWidget,
      reason:
          '修正前 highlightsRepository／notesRepository 永遠為 null，'
          '此分頁只會顯示空狀態佔位符（見 issues.md Issue 6 背景）',
    );
    expect(
      find.byKey(const Key('notes_sheet_annotations_placeholder')),
      findsNothing,
    );
  });

  testWidgets('透過 LibraryScreen 開書的正式流程匯出 Markdown 後，內容包含該書實際的劃線/備註'
      '（Issue 6 缺口修正，回歸 Issue 5 審查發現的「永遠空狀態」問題）', (tester) async {
    // 【根因說明，比照 notes_bottom_sheet_test.dart 既有先例】真實
    // Directory.createTemp／File I/O 需要真正的作業系統事件迴圈，
    // AutomatedTestWidgetsFlutterBinding 的 fake Zone 無法完成，連
    // tester.tap() 本身也必須整個放進 tester.runAsync() 才能讓
    // _exportMarkdown() 從第一行就綁定真實 Zone。
    final tempDir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp(
        'library_screen_markdown_export_test',
      ),
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
    await highlightsRepository.insert(
      const Highlight(
        id: 'h_lib_2',
        bookId: '1',
        style: HighlightStyle.highlighterYellow,
        pdfPageIndex: 0,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
      ),
    );

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
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
        .widget<IconButton>(
          find.byKey(const Key('reader_chrome_annotations_button')),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('notes_sheet_export_markdown')));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (fakeShare.lastParams == null &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();

    expect(fakeShare.lastParams, isNotNull);
    final files = fakeShare.lastParams!.files;
    expect(files, hasLength(1));
    final exportedFile = File(files!.single.path);
    final content = await tester.runAsync(() => exportedFile.readAsString());
    expect(
      content,
      contains('### 📌 螢光筆（黃）（位置：第 1 頁）'),
      reason:
          '修正前 LibraryScreen 從未貫穿 highlightsRepository／'
          'notesRepository，匯出內容的劃線/備註段落永遠固定顯示'
          '「尚未加入任何劃線或備註」（見 issues.md Issue 6 背景）',
    );
    expect(content, isNot(contains('*(尚未加入任何劃線或備註)*')));
  });

  // ── Task 2: 補齊分類拼貼格排序/兜底桶/空格佔位/選取模式互動測試 ──

  testWidgets('分類拼貼格依目前排序模式（最後閱讀）排序；「未分類」不使用拼貼格顯示，不計入排序', (tester) async {
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
    final repository = FakeLibraryRepository(
      initialBooks: [bookSci, bookFan, bookNone],
    );

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_view_toggle_option')));
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
    expect(
      find.byKey(Key('group_tile_${BookGroup.uncategorized}')),
      findsNothing,
    );
    expect(find.byKey(const Key('book_item_3')), findsOneWidget);
  });

  testWidgets('【診斷修正】「未分類」不使用拼貼格顯示，其書籍純以個別書籍項目呈現', (tester) async {
    final bookFan = _testBook(id: '1', title: '奇幻書', groupName: '奇幻');
    final bookNone = _testBook(id: '2', title: '未分類書');
    final repository = FakeLibraryRepository(initialBooks: [bookFan, bookNone]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
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

  testWidgets('_groups 快照落後於 _books 時，孤兒 groupName 仍會被兜底桶收留，不會讓書籍消失', (
    tester,
  ) async {
    final book = _testBook(id: '1', title: '懸疑小說', groupName: '懸疑');
    final repository = FakeLibraryRepository(initialBooks: [book]);
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
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
    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_option_title')));
    await tester.pumpAndSettle();

    // '科幻' 不在 _groups 快照中（快照仍是建構時的 {未分類, 懸疑}），書籍
    // 仍應被兜底桶收留、出現在某個拼貼格，而不是從書架上「消失」。
    expect(find.byKey(const Key('group_tile_科幻')), findsOneWidget);
    expect(find.text('科幻 (1 本)'), findsOneWidget);
  });

  testWidgets('分類拼貼格的封面預覽只取該分類前 4 本書，且保留目前排序結果的順序', (tester) async {
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

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    expect(find.text('奇幻 (5 本)'), findsOneWidget);

    final tileFinder = find.byKey(const Key('group_tile_奇幻'));
    expect(
      find.descendant(
        of: tileFinder,
        matching: find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.menu_book,
        ),
      ),
      findsNWidgets(4),
    );
    expect(
      find.descendant(
        of: tileFinder,
        matching: find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.article,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('分類拼貼格（格狀檢視）封面預覽區塊填滿可用高度，下方不留空白'
      '（診斷修正：原本用 GridView.count 預設正方形儲存格，2×2 網格自身高度'
      '只略等於寬度，遠小於拼貼格 childAspectRatio: 0.62 分配到的較高可用'
      '空間，NeverScrollableScrollPhysics 又不會撐滿，導致封面下方留下大片'
      '空白；改用 Column/Row 手排 Expanded 後應精確填滿）', (tester) async {
    final books = List.generate(
      4,
      (i) => _testBook(id: '$i', title: '書$i', groupName: '奇幻'),
    );
    final repository = FakeLibraryRepository(initialBooks: books);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
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

    // 尺寸驗證：4 本書皆無 coverPath，BookCover 各自以 CoverPlaceholder 佔位
    // （Issue 9：內含置中的圖示/書名縮略，圖示與文字本身不會撐滿儲存格，
    // 故量測 CoverPlaceholder 本身的邊界而非圖示）；取最下面那一列（第 3/4
    // 格）佔位元件的底部，應緊接分類名稱文字的頂部（僅隔明講的
    // SizedBox(height: 4) 一點點間距），而非留下大片空白。
    final coverBoxFinder = find.descendant(
      of: tileFinder,
      matching: find.byType(CoverPlaceholder),
    );
    final coverBoxCount = tester.widgetList(coverBoxFinder).length;
    expect(coverBoxCount, 4);
    final bottomRowBottomY = List.generate(
      coverBoxCount,
      (i) => tester.getBottomLeft(coverBoxFinder.at(i)).dy,
    ).reduce((a, b) => a > b ? a : b);

    final labelFinder = find.descendant(
      of: tileFinder,
      matching: find.text('奇幻 (4 本)'),
    );
    final labelTopY = tester.getTopLeft(labelFinder).dy;

    expect(
      labelTopY - bottomRowBottomY,
      lessThan(10),
      reason: '封面預覽區塊與分類名稱之間不應留下大片空白（僅預期的 4px 間距）',
    );
  });

  testWidgets('分類拼貼格（格狀檢視）不足 4 本時以中性色塊佔位，名稱與本數正確顯示', (tester) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB = _testBook(id: '2', title: 'B書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    final tileFinder = find.byKey(const Key('group_tile_奇幻'));
    expect(tileFinder, findsOneWidget);
    expect(find.text('奇幻 (2 本)'), findsOneWidget);

    // Issue 9：2 本書皆無 coverPath，BookCover 各自退回 CoverPlaceholder
    // （依格式圖示＋書名），拼貼格本身「不足 4 本」的 2 個空格佔位
    // （_groupTilePreviewCell 的 fallback 分支）也改用 CoverPlaceholder
    // （固定 Icons.book、不傳 title）——A/B 兩類共用同一顆元件、視覺統一，
    // 改用「格式圖示（menu_book，2 個真書）＋固定圖示（Icons.book，2 個
    // 空格）」精確區分來源，取代舊版靠 ColoredBox 色階區分的做法。
    expect(
      find.descendant(of: tileFinder, matching: find.byIcon(Icons.menu_book)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: tileFinder, matching: find.byIcon(Icons.book)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: tileFinder, matching: find.byType(CoverPlaceholder)),
      findsNWidgets(4),
    );
    expect(
      find.descendant(of: tileFinder, matching: find.byType(BookCover)),
      findsNWidgets(2),
    );
  });

  testWidgets('分類拼貼格（列表檢視）不足 4 本時以中性色塊佔位', (tester) async {
    final book = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_view_toggle_option')));
    await tester.pumpAndSettle();

    final tileFinder = find.byKey(const Key('group_tile_奇幻'));
    expect(tileFinder, findsOneWidget);
    expect(find.text('奇幻'), findsOneWidget);
    expect(find.text('1 本'), findsOneWidget);
    // Issue 9：同上（格狀檢視版本）理由：1 本書無 coverPath 退回
    // CoverPlaceholder（依格式圖示＋書名），3 個「不足 4 本」空格也改用
    // CoverPlaceholder（固定 Icons.book、不傳 title），改用「格式圖示
    // （menu_book，1 個真書）＋固定圖示（Icons.book，3 個空格）」精確區分
    // 來源，取代舊版靠 ColoredBox 色階區分的做法。
    expect(
      find.descendant(of: tileFinder, matching: find.byIcon(Icons.menu_book)),
      findsNWidgets(1),
    );
    expect(
      find.descendant(of: tileFinder, matching: find.byIcon(Icons.book)),
      findsNWidgets(3),
    );
    expect(
      find.descendant(of: tileFinder, matching: find.byType(CoverPlaceholder)),
      findsNWidgets(4),
    );
    expect(
      find.descendant(of: tileFinder, matching: find.byType(BookCover)),
      findsNWidgets(1),
    );
  });

  testWidgets('長按進入選取模式後，分類拼貼格的 onTap 停用，點擊不觸發導覽也不影響選取狀態', (tester) async {
    // bookA 維持「未分類」，確保它仍會出現在頂層書架的書籍清單中可供長按
    // （已歸類的書籍不再重複顯示於頂層，見「已分類的書不重複列出」規則）；
    // bookB 歸入「奇幻」，用來確保有一個分類拼貼格可以點擊測試。
    final bookA = _testBook(
      id: '1',
      title: 'A書',
      groupName: BookGroup.uncategorized,
    );
    final bookB = _testBook(id: '2', title: 'B書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
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

  testWidgets('點擊分類拼貼格為原地狀態切換，不產生新的 Navigator 路由（C-2 核心回歸測試）', (
    tester,
  ) async {
    final book = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigatorState.canPop(), isFalse);

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    expect(
      navigatorState.canPop(),
      isFalse,
      reason: '原地下鑽不應該推入新的 Navigator 路由（舊行為必須明確斷言「不會再發生」）',
    );
    expect(
      find.byType(LibraryScreen),
      findsOneWidget,
      reason: '畫面樹上永遠只有一個 LibraryScreen 實例',
    );
  });

  testWidgets('下鑽分類後 AppBar leading 顯示返回按鈕、title 顯示分類名稱；點擊返回按鈕回到頂層書架', (
    tester,
  ) async {
    final book = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_back_from_group_button')), findsNothing);

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_back_from_group_button')), findsOneWidget);
    expect(find.text('奇幻'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_back_from_group_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_back_from_group_button')), findsNothing);
    expect(find.text('書架'), findsOneWidget);
  });

  testWidgets('頂層書架多選模式下系統返回鍵先解除多選，不退出畫面（PopScope 合併邏輯）', (
    tester,
  ) async {
    final book = _testBook(id: '1', title: 'A書');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library_selection_app_bar')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_selection_app_bar')), findsNothing,
      reason: '系統返回鍵應優先解除多選模式，而非直接關閉畫面',
    );
    expect(find.byType(LibraryScreen), findsOneWidget);
  });

  testWidgets('下鑽分類內多選模式下系統返回鍵先解除多選，不誤切回頂層（PopScope 合併邏輯）', (
    tester,
  ) async {
    final book = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();
    expect(find.text('奇幻'), findsOneWidget);

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library_selection_app_bar')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_selection_app_bar')), findsNothing,
      reason: '應先解除多選模式',
    );
    expect(
      find.text('奇幻'), findsOneWidget,
      reason: '解除多選後應仍停留在下鑽的分類畫面，不應該同一次系統返回鍵就直接跳回頂層書架',
    );
    expect(find.byKey(const Key('library_back_from_group_button')), findsOneWidget);
  });

  testWidgets('下鑽分類（非多選模式）下系統返回鍵切回頂層書架（PopScope 合併邏輯）', (
    tester,
  ) async {
    final book = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();
    expect(find.text('奇幻'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('書架'), findsOneWidget);
    expect(find.byKey(const Key('library_back_from_group_button')), findsNothing);
  });

  testWidgets('_buildBookList 合併分類格與書籍的 index 空間，分類格恆排在書籍之前', (tester) async {
    final bookA = _testBook(id: '1', title: 'A書', groupName: '奇幻');
    final bookB = _testBook(
      id: '2',
      title: 'B書',
      groupName: BookGroup.uncategorized,
    );
    final repository = FakeLibraryRepository(initialBooks: [bookA, bookB]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_view_toggle_option')));
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

      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: FakeLibraryRepository(initialBooks: [book]),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
            readerFeatureRepositories: LibraryReaderFeatureRepositories(
              customFontsRepository: customFontsRepository,
            ),
          ),
    );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_1')));
      await tester.pumpAndSettle();

      final readerScreen = tester.widget<ReaderScreen>(
        find.byType(ReaderScreen),
      );
      expect(
        readerScreen.customFontsRepository,
        same(customFontsRepository),
        reason:
            'LibraryScreen._openBook() 未把 customFontsRepository 貫穿給 '
            'ReaderScreen，導致 ReaderScreen._loadCustomFonts() 早期 return，'
            '_customFonts 永遠是空清單，自訂字型永遠不會出現在 '
            'ReaderSettingsSheet 的單書字型選單中',
      );
    },
  );

  testWidgets(
    'LibraryScreen 點開一本書後，ReaderScreen 收到的 layoutPresetRepository／bookReaderPrefsRepository 正確貫穿',
    (tester) async {
      final layoutPresetRepository = LayoutPresetRepository(
        libraryRepository.database,
      );
      final bookReaderPrefsRepository = BookReaderPrefsRepository(
        libraryRepository.database,
      );

      final book = _testBook(
        id: '1',
        title: '紅樓夢',
        author: '曹雪芹',
        filePath: 'content://example/1.txt',
      );

      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: FakeLibraryRepository(initialBooks: [book]),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
            readerFeatureRepositories: LibraryReaderFeatureRepositories(
              layoutPresetRepository: layoutPresetRepository,
              bookReaderPrefsRepository: bookReaderPrefsRepository,
            ),
          ),
    );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_1')));
      await tester.pumpAndSettle();

      final readerScreen = tester.widget<ReaderScreen>(
        find.byType(ReaderScreen),
      );
      expect(
        readerScreen.layoutPresetRepository,
        same(layoutPresetRepository),
        reason:
            'LibraryScreen._openBook() 未把 layoutPresetRepository 貫穿給 '
            'ReaderScreen，版面設定預設集功能將完全無法使用。',
      );
      expect(
        readerScreen.bookReaderPrefsRepository,
        same(bookReaderPrefsRepository),
        reason:
            'LibraryScreen._openBook() 未把 bookReaderPrefsRepository 貫穿給 '
            'ReaderScreen，書籍設定複製與批次套用功能將完全無法使用。',
      );
    },
  );

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

      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: FakeLibraryRepository(initialBooks: [book]),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
            syncDependencies: LibrarySyncDependencies(
              syncCheckpointTrigger: syncCheckpointTrigger,
            ),
          ),
    );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_1')));
      await tester.pumpAndSettle();

      final readerScreen = tester.widget<ReaderScreen>(
        find.byType(ReaderScreen),
      );
      expect(
        readerScreen.syncCheckpointTrigger,
        same(syncCheckpointTrigger),
        reason:
            'LibraryScreen._openBook() 未把 syncCheckpointTrigger 貫穿給 '
            'ReaderScreen，離開閱讀畫面時就不會觸發書籍切換 checkpoint',
      );
    },
  );

  testWidgets('openLastBookOnLaunch=true 且圖書庫有書籍時，App 啟動後自動導向最後閱讀的書籍'
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
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(openLastBookOnLaunch: true),
      ),
    );

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [older, newer]),
          importService: FakeBookImportService(),
          prefsManager: fakeManager,
        ),
    );
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(
      readerScreen.bookId,
      'newer',
      reason:
          'openLastBookOnLaunch 應自動導向 lastReadTime 最新的那一本，'
          '而非清單第一筆或任意一筆',
    );
  });

  testWidgets('openLastBookOnLaunch=false 時，App 啟動後停留在書架，不自動開書'
      '（epic-18-reader-device-qa Issue 29）', (tester) async {
    final book = _testBook(
      id: 'b1',
      title: '測試書',
      filePath: 'content://example/b1.txt',
    );
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(openLastBookOnLaunch: false),
      ),
    );

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: fakeManager,
        ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReaderScreen), findsNothing);
    expect(find.byKey(const Key('book_item_b1')), findsOneWidget);
  });

  testWidgets('openLastBookOnLaunch=true 但圖書庫沒有任何書籍時，不嘗試開書也不拋出例外'
      '（epic-18-reader-device-qa Issue 29）', (tester) async {
    final fakeManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(openLastBookOnLaunch: true),
      ),
    );

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: const []),
          importService: FakeBookImportService(),
          prefsManager: fakeManager,
        ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReaderScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('橫屏（4 欄）下 3 個分類拼貼格＋第 4 欄由第一本書籍格頂上時，兩者文字'
      '標籤起始 Y 座標對齊（epic-18-reader-device-qa Issue 42，真機使用'
      '回報：書架橫屏下封面未對齊——直式 3 欄時 3 個分類恰好填滿一列、'
      '書籍從下一列開始，不會同列；橫屏 4 欄時 3 個分類只填滿前 3 欄，'
      '第 4 欄由第一本書籍格頂上，才會與分類拼貼格同列。根因是'
      '_BookGridTile 有 2 行文字說明（書名＋進度），_GroupGridTile 只有'
      '1 行〔分類名稱＋本數〕，兩者封面 Expanded 吃到的剩餘高度因此不同，'
      '導致同列的封面底部邊界錯開。程式碼審查修正：原測試只建立 1 個分類'
      '〔任何欄數下皆會同列，未精確重現橫屏限定的觸發條件〕，改為 3 個'
      '不同分類＋橫屏 4 欄，具體驗證「第 4 欄由書籍格頂上」這個情境）', (tester) async {
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

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
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
        .getTopLeft(
          find.descendant(of: groupTileFinder, matching: find.text('奇幻 (1 本)')),
        )
        .dy;
    // Issue 9：BookCover 無封面圖時改用 CoverPlaceholder，其內建書名縮略
    // 跟 _BookGridTile 本身的標題 caption 顯示同一段文字，find.descendant
    // 對「第一本個別書」現在會命中 2 個 Text——這裡要量測的是書籍格「本身
    // caption」的 Y 座標（用來跟分類拼貼格標籤對齊），CoverPlaceholder
    // 內建迷你標題的 Y 座標不是量測對象，用 Element 的
    // findAncestorWidgetOfExactType 排除掉屬於 CoverPlaceholder 子樹的那個。
    final bookTitleCandidates = find
        .descendant(of: bookTileFinder, matching: find.text('第一本個別書'))
        .evaluate()
        .where(
          (element) =>
              element.findAncestorWidgetOfExactType<CoverPlaceholder>() ==
              null,
        );
    expect(
      bookTitleCandidates.length,
      1,
      reason: '書籍格本身的標題 caption 應該只有一個（不含 CoverPlaceholder 內建的迷你標題）',
    );
    final bookTitleTop =
        (bookTitleCandidates.single.renderObject as RenderBox)
            .localToGlobal(Offset.zero)
            .dy;

    expect(
      bookTitleTop,
      groupLabelTop,
      reason:
          '同列的分類拼貼格與書籍格，文字標籤起始高度應對齊，'
          '封面區塊底部邊界才不會錯開',
    );
  });

  testWidgets('系統字級放大時，分類拼貼格與書籍格的文字說明區高度隨字級同比例'
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

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: repository,
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
      mediaQueryData: MediaQueryData(textScaler: TextScaler.linear(1.5)),
    );
    await tester.pumpAndSettle();

    // 字級放大情境下，只要沒有 RenderFlex 溢位例外，就代表固定高度容器
    // 有隨 textScaler 同比例放大、確實讓出足夠空間。
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('group_tile_奇幻')), findsOneWidget);
    expect(find.byKey(const Key('book_item_b0')), findsOneWidget);
  });

  testWidgets('系統字級縮放曲線為非線性時（真機常見情境——Android 系統字級調大後，'
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

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: repository,
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
      mediaQueryData: const MediaQueryData(textScaler: _NonLinearTextScaler(1.5)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('group_tile_奇幻')), findsOneWidget);
    expect(find.byKey(const Key('book_item_b0')), findsOneWidget);
  });

  testWidgets(
    '選取 Calibre 來源已下載書籍後點擊「移除本機快取」，刪除實體檔案、isDownloaded 變 false，劃線/書籤/進度不受影響',
    (tester) async {
      // 〔比照 library_screen.dart _deleteSelectedBooks() 既有註解說明〕
      // widget test 的 fake zone 無法完成真實 I/O 的 Future，一律使用
      // *Sync() 系列同步呼叫，不需要 tester.runAsync()。
      final tempDir = Directory.systemTemp.createTempSync(
        'library_remove_cache_test',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final bookFile = File('${tempDir.path}/remote_book.epub')
        ..writeAsStringSync('dummy');

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

      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: repository,
            importService: FakeBookImportService(),
            prefsManager: FakeReaderPrefsManager(
              globalPrefs: const GlobalReaderPrefs.initial().copyWith(
                reading: const ReadingDefaults(openLastBookOnLaunch: false),
              ),
            ),
            readerFeatureRepositories: LibraryReaderFeatureRepositories(
              bookmarksRepository: bookmarksRepository,
            ),
          ),
    );
      await tester.pumpAndSettle();

      // 長按（_onBookLongPress → _enterSelectionMode）已經把這本書放進
      // _selectedBookIds（見 library_screen.dart:295-297），不需要再多點一次
      // ——選取模式下再點一次同一本書會呼叫 _toggleBookSelection() 把它
      // 取消選取，反而導致 count == 0、下方按鈕被停用。
      await tester.longPress(find.byKey(const Key('book_item_b1')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('library_remove_local_cache_button')),
      );
      await tester.pumpAndSettle();

      final updated = (await repository.listBooks()).single;
      expect(updated.isDownloaded, isFalse);
      expect(updated.filePath, bookFile.path);
      expect(bookFile.existsSync(), isFalse);
      expect(updated.epubLocator, 'locator-json');
      expect(updated.progress, 0.5);
      expect(await bookmarksRepository.listByBook('b1'), hasLength(1));
    },
  );

  testWidgets('選取非 Calibre 來源（本機匯入）書籍時，點擊「移除本機快取」不影響該書', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync(
      'library_remove_cache_local_test',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final bookFile = File('${tempDir.path}/local_book.epub')
      ..writeAsStringSync('dummy');

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

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(
            globalPrefs: const GlobalReaderPrefs.initial().copyWith(
              reading: const ReadingDefaults(openLastBookOnLaunch: false),
            ),
          ),
        ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_b2')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_remove_local_cache_button')),
    );
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
      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: repository,
            importService: FakeBookImportService(),
            prefsManager: FakeReaderPrefsManager(),
            remoteLibraryDependencies: LibraryRemoteLibraryDependencies(
              remoteServerRepository: FakeRemoteServerRepository(
                initialServers: [server],
              ),
              createOpdsClient: () => opdsClient,
            ),
            isMobileDataConnection: () async => false,
          ),
    );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_b1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('library_redownload_dialog')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('library_redownload_cancel_button')),
      );
      await tester.pumpAndSettle();

      expect(opdsClient.downloadBookCalls, isEmpty);
    });

    testWidgets('偵測到行動數據連線時，確認對話框額外顯示流量提示文字', (tester) async {
      final repository = FakeLibraryRepository(initialBooks: [pendingBook()]);
      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: repository,
            importService: FakeBookImportService(),
            prefsManager: FakeReaderPrefsManager(),
            remoteLibraryDependencies: LibraryRemoteLibraryDependencies(
              remoteServerRepository: FakeRemoteServerRepository(
                initialServers: [server],
              ),
              createOpdsClient: () => FakeOpdsClient(),
            ),
            isMobileDataConnection: () async => true,
          ),
    );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_b1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('行動數據'), findsOneWidget);
    });

    testWidgets('確認後成功重新下載，更新 filePath/isDownloaded，不建立新的 Book 記錄', (
      tester,
    ) async {
      final repository = FakeLibraryRepository(initialBooks: [pendingBook()]);
      final opdsClient = FakeOpdsClient();
      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: repository,
            importService: FakeBookImportService(),
            prefsManager: FakeReaderPrefsManager(),
            remoteLibraryDependencies: LibraryRemoteLibraryDependencies(
              remoteServerRepository: FakeRemoteServerRepository(
                initialServers: [server],
              ),
              createOpdsClient: () => opdsClient,
            ),
            isMobileDataConnection: () async => false,
          ),
    );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_b1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('library_redownload_confirm_button')),
      );
      await tester.pump();

      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      final books = await repository.listBooks();
      expect(books, hasLength(1));
      expect(books.single.id, 'b1');
      expect(books.single.isDownloaded, isTrue);
      expect(books.single.filePath, isNot('/no/longer/exists.epub'));
      expect(File(books.single.filePath).existsSync(), isTrue);
      expect(opdsClient.downloadBookCalls, [
        'http://192.168.1.100:8080/opds/download/1.epub',
      ]);
    });

    testWidgets(
        '重新下載完成後呼叫 fullTextSearchSettingsRepository.handleBookAvailable'
        '（epic-10-search Issue 2）', (tester) async {
      final repository = FakeLibraryRepository(initialBooks: [pendingBook()]);
      final opdsClient = FakeOpdsClient();
      final fullTextSearchSettingsRepository =
          FakeFullTextSearchSettingsRepository();
      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: repository,
            importService: FakeBookImportService(),
            prefsManager: FakeReaderPrefsManager(),
            remoteLibraryDependencies: LibraryRemoteLibraryDependencies(
              remoteServerRepository: FakeRemoteServerRepository(
                initialServers: [server],
              ),
              createOpdsClient: () => opdsClient,
            ),
            readerFeatureRepositories: LibraryReaderFeatureRepositories(
              fullTextSearchSettingsRepository:
                  fullTextSearchSettingsRepository,
            ),
            isMobileDataConnection: () async => false,
          ),
    );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_b1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('library_redownload_confirm_button')),
      );
      await tester.pump();

      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(
        fullTextSearchSettingsRepository.handleBookAvailableCalls,
        hasLength(1),
      );
      final calledWith =
          fullTextSearchSettingsRepository.handleBookAvailableCalls.single;
      expect(calledWith.id, 'b1');
      expect(calledWith.isDownloaded, isTrue);
    });

    testWidgets('下載失敗時顯示錯誤訊息，書籍狀態不變', (tester) async {
      final repository = FakeLibraryRepository(initialBooks: [pendingBook()]);
      final opdsClient = FakeOpdsClient(downloadError: StateError('模擬下載失敗'));
      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: repository,
            importService: FakeBookImportService(),
            prefsManager: FakeReaderPrefsManager(),
            remoteLibraryDependencies: LibraryRemoteLibraryDependencies(
              remoteServerRepository: FakeRemoteServerRepository(
                initialServers: [server],
              ),
              createOpdsClient: () => opdsClient,
            ),
            isMobileDataConnection: () async => false,
          ),
    );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_b1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('library_redownload_confirm_button')),
      );
      await tester.pump();

      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('重新下載失敗，請稍後再試'), findsOneWidget);
      final books = await repository.listBooks();
      expect(books.single.isDownloaded, isFalse);
      expect(books.single.filePath, '/no/longer/exists.epub');
    });
  });

  testWidgets('LibraryScreen 點擊排序按鈕，彈出選單中當前選中的排序項目顯示 Checkmark 圖示', (
    tester,
  ) async {
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();

    // 預設排序為最近閱讀（lastRead）
    final lastReadItemFinder = find.byKey(
      const Key('library_sort_option_lastRead'),
    );
    expect(lastReadItemFinder, findsOneWidget);

    // 驗證該項目包含 check 圖示
    expect(
      find.descendant(
        of: lastReadItemFinder,
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'LibraryScreen 點開一本書後，ReaderScreen 收到的 isEinkMode 與 themeDependencies.isEinkMode 一致',
    (tester) async {
      final book = _testBook(
        id: '1',
        title: '紅樓夢',
        author: '曹雪芹',
        filePath: 'content://example/1.txt',
      );

      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: FakeLibraryRepository(initialBooks: [book]),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
            themeDependencies: LibraryThemeDependencies(isEinkMode: true),
          ),
    );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_item_1')));
      await tester.pumpAndSettle();

      final readerScreen = tester.widget<ReaderScreen>(
        find.byType(ReaderScreen),
      );
      expect(
        readerScreen.isEinkMode,
        isTrue,
        reason:
            'LibraryScreen._openBook() 未把 themeDependencies.isEinkMode '
            '貫穿給 ReaderScreen，導致朗讀高亮在 E-Ink 模式下仍使用一般的'
            '半透明色，在低對比度螢幕上難以辨識。',
      );
    },
  );

  testWidgets('空書架點擊「匯入書籍」呼叫 onNavigateToSource callback（issues.md Issue 1 明訂，審查報告 I-1）', (tester) async {
    var sourceTapped = 0;
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          onNavigateToSource: () => sourceTapped++,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_empty_import_button')));
    await tester.pumpAndSettle();

    expect(sourceTapped, 1);
  });

  testWidgets('點擊 AppBar「來源」圖示呼叫 onNavigateToSource callback（審查報告 M-3）', (tester) async {
    var sourceTapped = 0;
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: const []),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          onNavigateToSource: () => sourceTapped++,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_source_button')));
    await tester.pumpAndSettle();

    expect(sourceTapped, 1);
  });

  testWidgets('直向與橫向的每頁項目數依可用空間動態計算，橫向欄數多於直向', (tester) async {
    final books = List.generate(20, (i) => _testBook(id: '$i', title: '書$i'));

    tester.view.physicalSize = const Size(800, 1200); // portrait
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: books),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    final portraitPageSize = _measuredPageSize(tester);
    expect(portraitPageSize, greaterThanOrEqualTo(3), reason: '直向至少要能完整顯示 1 行（3 欄）');
    expect(portraitPageSize % 3, 0, reason: '直向 3 欄，pageSize 必為 3 的倍數（整數列，不可半截列）');
    expect(
      find.text('1 / ${libraryPageCount(20, portraitPageSize)}'),
      findsOneWidget,
    );

    tester.view.physicalSize = const Size(1200, 800); // landscape
    await tester.pumpAndSettle();

    final landscapePageSize = _measuredPageSize(tester);
    expect(landscapePageSize, greaterThanOrEqualTo(4), reason: '橫向至少要能完整顯示 1 行（4 欄）');
    expect(landscapePageSize % 4, 0, reason: '橫向 4 欄，pageSize 必為 4 的倍數（整數列，不可半截列）');
  });

  testWidgets('點擊 PagingBar 下一頁/上一頁切換書架顯示的書籍', (tester) async {
    final books = List.generate(20, (i) => _testBook(id: '$i', title: '書$i'));

    tester.view.physicalSize = const Size(800, 1200); // portrait
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: books),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    final pageSize = _measuredPageSize(tester);
    final pageCount = libraryPageCount(20, pageSize);
    expect(find.byKey(const Key('book_item_0')), findsOneWidget);
    expect(
      find.byKey(Key('book_item_$pageSize')),
      findsNothing,
      reason: '第一頁不該出現下一頁才有的項目',
    );
    expect(find.text('1 / $pageCount'), findsOneWidget);

    await tester.tap(find.byKey(const Key('paging_bar_next_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_0')), findsNothing);
    expect(
      find.byKey(Key('book_item_$pageSize')),
      findsOneWidget,
      reason: '第二頁第一項全域 index 應等於 pageSize',
    );
    expect(find.text('2 / $pageCount'), findsOneWidget);

    await tester.tap(find.byKey(const Key('paging_bar_previous_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_0')), findsOneWidget);
    expect(find.text('1 / $pageCount'), findsOneWidget);
  });

  testWidgets('旋轉螢幕時目前頁碼依新每頁容量正確換算，不跳到看不懂的地方', (tester) async {
    final books = List.generate(60, (i) => _testBook(id: '$i', title: '書$i'));

    tester.view.physicalSize = const Size(800, 1200); // portrait
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: books),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    final portraitPageSize = _measuredPageSize(tester);

    await tester.tap(find.byKey(const Key('paging_bar_next_button')));
    await tester.pumpAndSettle();

    // 走到第 2 頁（0-based page=1），第一項全域 index = portraitPageSize。
    expect(find.byKey(Key('book_item_$portraitPageSize')), findsOneWidget);

    tester.view.physicalSize = const Size(1200, 800); // landscape
    await tester.pumpAndSettle();

    final landscapePageSize = _measuredPageSize(tester);
    final expectedPage = libraryRecalculatePage(
      oldPage: 1,
      oldPageSize: portraitPageSize,
      newPageSize: landscapePageSize,
    );
    final expectedPageCount = libraryPageCount(60, landscapePageSize);
    expect(find.text('${expectedPage + 1} / $expectedPageCount'), findsOneWidget);
    expect(
      find.byKey(Key('book_item_${expectedPage * landscapePageSize}')),
      findsOneWidget,
      reason: '換算後頁面第一項全域 index 應等於 expectedPage * landscapePageSize',
    );
  });

  testWidgets('切換排序條件後頁碼重置為第一頁', (tester) async {
    final books = List.generate(20, (i) => _testBook(id: '$i', title: '書$i'));

    tester.view.physicalSize = const Size(800, 1200); // portrait
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: books),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    final pageSize = _measuredPageSize(tester);
    final pageCount = libraryPageCount(20, pageSize);

    await tester.tap(find.byKey(const Key('paging_bar_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('2 / $pageCount'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_option_title')));
    await tester.pumpAndSettle();

    expect(find.text('1 / $pageCount'), findsOneWidget);
  });

  testWidgets('進入/離開分類下鑽時頁碼重置為第一頁', (tester) async {
    final groupBooks = List.generate(
      20,
      (i) => _testBook(id: 'g$i', title: '分類書$i', groupName: '奇幻'),
    );

    tester.view.physicalSize = const Size(800, 1200); // portrait
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: groupBooks),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    final pageSize = _measuredPageSize(tester);
    final pageCount = libraryPageCount(20, pageSize);
    expect(find.text('1 / $pageCount'), findsOneWidget);

    await tester.tap(find.byKey(const Key('paging_bar_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('2 / $pageCount'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_back_from_group_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    expect(
      find.text('1 / $pageCount'),
      findsOneWidget,
      reason: '再次下鑽同一分類時頁碼應已重置，不殘留上次離開時的頁碼',
    );
  });

  testWidgets('同一直向裝置在較矮／較高兩種高度下，書架每頁列數確實跟著變動（矮裝置少於高裝置）', (
    tester,
  ) async {
    final books = List.generate(60, (i) => _testBook(id: '$i', title: '書$i'));

    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    tester.view.physicalSize = const Size(400, 600); // 較矮（直向：width < height）
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: books),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();
    final shortPageSize = _measuredPageSize(tester);
    expect(shortPageSize % 3, 0, reason: '直向 3 欄，pageSize 必為 3 的倍數（整數列）');

    tester.view.physicalSize = const Size(400, 1400); // 較高，同一裝置寬度不變
    await tester.pumpAndSettle();
    final tallPageSize = _measuredPageSize(tester);
    expect(tallPageSize % 3, 0, reason: '直向 3 欄，pageSize 必為 3 的倍數（整數列）');

    expect(
      tallPageSize,
      greaterThan(shortPageSize),
      reason:
          '較高裝置可用高度較多，應能顯示比較矮裝置更多列；若動態計算退化回寫死'
          '1 行，兩者會相等，測試須能抓到這種回歸',
    );
  });

  testWidgets(
    'List View 每頁列數依 ListTile 列高獨立計算，窄高裝置下不再沿用 Grid 幾何 '
    '算出的過大 pageSize（epic-36 Issue 7 追加修正——I-1：修正前兩種檢視共用同一組 '
    'pageSize，List 這一頁可能因 NeverScrollableScrollPhysics 而裁切掉部分書籍）',
    (tester) async {
      final books = List.generate(60, (i) => _testBook(id: '$i', title: '書$i'));

      // 窄寬度＋充裕高度：Grid cell 因寬度窄而變矮，同一段可用高度下能塞進
      // 很多列 Grid cell，若 List 誤用這組 pageSize，需要的 ListTile 總高度
      // 會遠超過實際可用高度（見下方斷言）。
      tester.view.physicalSize = const Size(320, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: FakeLibraryRepository(initialBooks: books),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
    );
      await tester.pumpAndSettle();
      final gridPageSize = _measuredPageSize(tester);

      await tester.tap(find.byKey(const Key('library_sort_view_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library_sort_view_toggle_option')));
      await tester.pumpAndSettle();
      final listPageSize = _measuredPageSize(tester);

      expect(
        listPageSize,
        lessThan(gridPageSize),
        reason:
            '此裝置尺寸下 ListTile（約 72dp/列）遠矮於 Grid cell，若 List 仍沿用 '
            'Grid 算出的 pageSize（修正前的行為），兩者會相等；獨立計算後 List '
            '應該塞進更多列，pageSize 理應更大——這裡刻意反過來斷言「更小」是為了'
            '先鎖住「沒有繼續沿用同一組數字」這個修正意圖，實際數值大小關係見下一則'
            '斷言（bottom 不溢出）',
      );

      // 核心回歸斷言：頁面上實際渲染的最後一個項目，其下緣不能超出
      // library_list_view 容器的下緣——這是「該頁項目被靜默裁切、看得到頁碼
      // 卻看不到/點不到書」這個 Bug 的直接幾何徵狀，不依賴任何特定像素常數。
      final lastItemKey = Key('book_item_${listPageSize - 1}');
      expect(find.byKey(lastItemKey), findsOneWidget);
      final containerBottom = tester
          .getBottomRight(find.byKey(const Key('library_list_view')))
          .dy;
      final lastItemBottom = tester.getBottomRight(find.byKey(lastItemKey)).dy;
      expect(
        lastItemBottom,
        lessThanOrEqualTo(containerBottom + 0.5),
        reason: '最後一項若超出容器下緣，代表這一頁有項目被靜默裁切、無法捲動看見',
      );
    },
  );

  testWidgets('書庫全空時不渲染繼續閱讀列', (tester) async {
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_continue_reading_row')), findsNothing);
  });

  testWidgets('有書籍但全部 lastReadTime 為 epoch 0（從未閱讀）時不渲染繼續閱讀列', (
    tester,
  ) async {
    final bookA = _testBook(
      id: '1',
      title: 'A書',
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
    );
    final bookB = _testBook(
      id: '2',
      title: 'B書',
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
    );

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [bookA, bookB]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_continue_reading_row')), findsNothing);
  });

  testWidgets('至少一本書 lastReadTime > 0 時渲染繼續閱讀列，顯示最近閱讀那本並可點擊繼續閱讀', (
    tester,
  ) async {
    final older = _testBook(
      id: 'older',
      title: '較早閱讀的書',
      lastReadTime: DateTime(2026, 1, 1),
      filePath: 'content://example/older.txt',
    );
    final newer = _testBook(
      id: 'newer',
      title: '最近閱讀的書',
      lastReadTime: DateTime(2026, 6, 1),
      filePath: 'content://example/newer.txt',
    );
    final neverRead = _testBook(
      id: 'never',
      title: '沒讀過的書',
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
    );

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository:
              FakeLibraryRepository(initialBooks: [older, newer, neverRead]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_continue_reading_row')), findsOneWidget);
    // 2026-09-28 繼續閱讀列縮圖縮成 30x42 後，無 coverPath 時的
    // CoverPlaceholder 太小、依其既有門檻不顯示書名縮略（原本 Issue 9 預期
    // 縮略＋標題共 2 個匹配），只剩 _ContinueReadingRow 標題文字一處。
    expect(
      find.descendant(
        of: find.byKey(const Key('library_continue_reading_row')),
        matching: find.text('最近閱讀的書'),
      ),
      findsOneWidget,
      reason: '應顯示 lastReadTime 最新的那一本，而不是任何一本有讀過的書',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('library_continue_reading_row')),
        matching: find.text('較早閱讀的書'),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('library_continue_reading_row')));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderScreen), findsOneWidget);
  });

  testWidgets('下鑽檢視分類時不渲染繼續閱讀列', (tester) async {
    final book = _testBook(
      id: '1',
      title: 'A書',
      groupName: '奇幻',
      lastReadTime: DateTime(2026, 1, 1),
    );

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library_continue_reading_row')), findsOneWidget);

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_continue_reading_row')),
      findsNothing,
      reason: '繼續閱讀列是頂層書架的常駐列，下鑽檢視分類時不應出現',
    );
  });

  // 2026-09-28 使用者需求（Mobiscribe Wave 要排兩列封面）：繼續閱讀列
  // 壓矮——進度 % 併到「繼續閱讀」字眼後面，從三行字變兩行；書架每列之間
  // 的間隙縮小。
  testWidgets('繼續閱讀列：進度併在「繼續閱讀」後面，整列高度不超過 56',
      (tester) async {
    final book = _testBook(
      id: 'recent',
      title: '最近閱讀的書',
      lastReadTime: DateTime(2026, 9, 1),
    ).copyWith(progress: 0.45);
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(const Key('library_continue_reading_row'));
    expect(
      find.descendant(of: row, matching: find.text('繼續閱讀 · 45%')),
      findsOneWidget,
    );
    expect(tester.getSize(row).height, lessThanOrEqualTo(56));
  });

  testWidgets('書架格狀檢視每列之間的間隙為 4', (tester) async {
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(
              initialBooks: [_testBook(id: '1', title: '紅樓夢')]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    final grid =
        tester.widget<GridView>(find.byKey(const Key('library_grid_view')));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.mainAxisSpacing, 4);
    // 2026-09-28：寬高比 0.62 → 0.64，每格略矮，配合搜尋列收進標題列湊出兩列。
    expect(delegate.childAspectRatio, 0.64);
  });

  testWidgets('多選模式進行中，繼續閱讀列不可點擊（review-plan-issue-3.md M-3：避免無勾選指示反饋卻誤觸切換選取狀態）', (
    tester,
  ) async {
    final mostRecent = _testBook(
      id: 'recent',
      title: '最近閱讀的書',
      lastReadTime: DateTime(2026, 6, 1),
    );
    final other = _testBook(
      id: 'other',
      title: '另一本書',
      lastReadTime: DateTime(2026, 1, 1),
    );

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [mostRecent, other]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library_continue_reading_row')), findsOneWidget);

    await tester.longPress(find.byKey(const Key('book_item_other')));
    await tester.pumpAndSettle();
    expect(find.text('已選取 1 本'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('library_continue_reading_row')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(
      find.text('已選取 1 本'),
      findsOneWidget,
      reason: '點擊繼續閱讀列不應該把 mostRecent 加進選取集合，選取數量應維持不變',
    );
    expect(find.byType(ReaderScreen), findsNothing);
  });

  testWidgets('點擊 book_action_menu 後 BookActionSheet／EBSheetShell 出現在畫面上', (
    tester,
  ) async {
    final book = _testBook(id: '1', title: '書A');
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();

    expect(find.byType(EBSheetShell), findsOneWidget);
    expect(find.byType(BookActionSheet), findsOneWidget);
  });

  testWidgets('多選模式進行中時 book_action_menu 不顯示（與長按多選互斥）', (tester) async {
    final book = _testBook(id: '1', title: '書A');
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_action_menu_1')), findsNothing);
  });

  testWidgets('詳細資料：book.isDownloaded == false 時顯示「尚未下載」，不查詢檔案', (
    tester,
  ) async {
    final book = _testBook(id: '1', title: '書A', isDownloaded: false);
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_action_details')));
    await tester.pumpAndSettle();

    // 【review-plan-issue-4.md I-4】`尚未下載` 嵌入在 `Text('檔案大小：尚未下載')`
    // 中，用 `find.textContaining` 匹配子字串而非精确比对整个 Text data。
    expect(find.textContaining('尚未下載'), findsOneWidget);
  });

  testWidgets('詳細資料：content:// URI 或讀取失敗時顯示「未知大小」，不崩潰', (tester) async {
    final book = _testBook(id: '1', title: '書A', isDownloaded: true);
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_action_details')));
    await tester.pumpAndSettle();

    expect(find.textContaining('未知大小'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('詳細資料：已下載且為本機真實檔案時顯示格式化後的檔案大小', (tester) async {
    final tempFile = File(
      '${Directory.systemTemp.path}/book_details_test_'
      '${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    // 【I-4】`writeAsBytes` 是原生 I/O，在 testWidgets 的 fake-async 環境下
    // 若不包在 `runAsync` 裡，Future 永遠不會完成導致測試掛死。
    await tester.runAsync(() => tempFile.writeAsBytes(List.filled(2048, 0)));
    addTearDown(() async {
      await tester.runAsync(() async {
        if (await tempFile.exists()) await tempFile.delete();
      });
    });

    final book = _testBook(
      id: '1',
      title: '書A',
      filePath: tempFile.path,
      isDownloaded: true,
    );
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_action_details')));
    await tester.pumpAndSettle();

    expect(find.textContaining('2.0 KB'), findsOneWidget);
  });

  testWidgets('詳細資料：lastReadTime 為 epoch 0 時顯示「尚未閱讀」，而非誤導性的 1970 年日期', (
    tester,
  ) async {
    final book = _testBook(
      id: '1',
      title: '書A',
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
    );
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_action_details')));
    await tester.pumpAndSettle();

    expect(find.textContaining('尚未閱讀'), findsOneWidget);
  });

  testWidgets(
    '清單檢視模式下 book_action_menu 圖示存在，點擊後 BookActionSheet 出現'
    '（review-plan-issue-4.md I-3：Step 3c 修改 _BookListTile 的 trailing '
    '結構為 Row，先前測試只覆蓋了格狀模式，補上清單模式的整合測試）',
    (tester) async {
      final book = _testBook(id: '1', title: '書A');
      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: FakeLibraryRepository(initialBooks: [book]),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
    );
      await tester.pumpAndSettle();

      // 切換為清單檢視（既有既有慣例：見本檔案「library_sort_view_button」
      // /「library_sort_view_toggle_option」的既有測試）。
      await tester.tap(find.byKey(const Key('library_sort_view_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library_sort_view_toggle_option')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('library_list_view')), findsOneWidget);

      expect(find.byKey(const Key('book_action_menu_1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('book_action_menu_1')));
      await tester.pumpAndSettle();

      expect(find.byType(EBSheetShell), findsOneWidget);
      expect(find.byType(BookActionSheet), findsOneWidget);
    },
  );

  // ─── Task 4：onMove / onRemoveCache / onDelete 單書版本 ──────────

  testWidgets('點擊「移動」選擇分類後，該書 groupName 更新，其他書籍不受影響', (tester) async {
    final book = _testBook(id: '1', title: '書A');
    final groupSeed = _testBook(id: '2', title: '書B', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book, groupSeed]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
        repository: repository,
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_action_move')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_move_to_group_option_奇幻')));
    await tester.pumpAndSettle();

    final updated = await repository.listBooks();
    expect(updated.firstWhere((b) => b.id == '1').groupName, '奇幻');
    expect(
      updated.firstWhere((b) => b.id == '2').groupName,
      '奇幻',
      reason: '既有書籍不應受影響',
    );
  });

  testWidgets('點擊「移除快取」確認後，該書 isDownloaded 變 false，本機檔案被刪除', (tester) async {
    final tempFile = File(
      '${Directory.systemTemp.path}/remove_cache_test_'
      '${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    await tester.runAsync(() => tempFile.writeAsBytes([1, 2, 3]));
    addTearDown(() async {
      await tester.runAsync(() async {
        if (await tempFile.exists()) await tempFile.delete();
      });
    });

    final book = _testBook(
      id: '1',
      title: '書A',
      filePath: tempFile.path,
      source: BookSource.calibreOpds,
      isDownloaded: true,
    );
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book_action_remove_cache')), findsOneWidget);
    await tester.tap(find.byKey(const Key('book_action_remove_cache')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('book_action_remove_cache_confirm_button')),
    );
    await tester.pumpAndSettle();

    final updated = await repository.listBooks();
    expect(updated.firstWhere((b) => b.id == '1').isDownloaded, isFalse);
    expect(
      await tester.runAsync(() => tempFile.exists()),
      isFalse,
      reason: '本機快取檔案應被刪除',
    );
  });

  testWidgets(
    '點擊「刪除」確認後，該書從畫面上消失；若恰為 _mostRecentBook，繼續閱讀列同步消失'
    '（plan-issue-4.md「計劃範圍澄清」第 3 點：驗證 loadBooks() 既有機制已自動'
    '涵蓋重新計算，無需額外程式碼）',
    (tester) async {
      final book = _testBook(id: '1', title: '書A', lastReadTime: DateTime(2026, 6, 1));
      final repository = FakeLibraryRepository(initialBooks: [book]);

      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: repository,
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
    );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('library_continue_reading_row')), findsOneWidget);

      await tester.tap(find.byKey(const Key('book_action_menu_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book_action_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library_delete_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('book_item_1')), findsNothing);
      expect(
        find.byKey(const Key('library_continue_reading_row')),
        findsNothing,
        reason: '被刪除的書恰為 _mostRecentBook，繼續閱讀列不應殘留無效書籍參照',
      );
    },
  );

  // ─── Task 5：_LayoutOverrideDialog ─────────────────────────────

  testWidgets('bookReaderPrefsRepository 未提供時，「版面覆寫」選項不顯示', (tester) async {
    final book = _testBook(id: '1', title: '書A');
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_action_layout_override')), findsNothing);
  });

  testWidgets(
    '版面覆寫：儲存後只有 writingModeOverride/pageTurnModeOverride 改變，其他既有欄位'
    '原樣保留，選「使用預設」能真的清成 null（plan-issue-4.md「計劃範圍澄清」'
    '第 2 點核心回歸測試：不可誤用 copyWith()）',
    (tester) async {
      final book = _testBook(id: '1', title: '書A');
      final repository = FakeLibraryRepository(initialBooks: [book]);
      // 【review-plan-issue-4.md C-2】不可用 BookReaderPrefsRepository(
      // libraryRepository.database)：`libraryRepository` 是本檔案 setUp()
      // 另外開立的 SqliteLibraryRepository，其 SQLite books 表裡沒有 id
      // == '1' 這筆書籍（book 只放進了上面的記憶體 FakeLibraryRepository），
      // book_reader_prefs.book_id 是 REFERENCES books(id) 的外鍵，直接
      // save() 會立即拋出 FOREIGN KEY constraint failed。改用純記憶體的
      // FakeBookReaderPrefsRepository，徹底繞開這個約束、測試也更快更純粹。
      final bookReaderPrefsRepository = FakeBookReaderPrefsRepository();
      await bookReaderPrefsRepository.save(
        '1',
        const BookReaderPrefs(
          fontSize: 1.5,
          marginTop: 24,
          writingModeOverride: WritingMode.horizontal,
        ),
      );

      await pumpLocalizedWidget(
      tester,
      LibraryScreen(
            repository: repository,
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
            readerFeatureRepositories: LibraryReaderFeatureRepositories(
              bookReaderPrefsRepository: bookReaderPrefsRepository,
            ),
          ),
    );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_action_menu_1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('book_action_layout_override')), findsOneWidget);
      await tester.tap(find.byKey(const Key('book_action_layout_override')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('layout_override_writing_mode_default')));
      await tester.tap(find.byKey(const Key('layout_override_page_turn_mode_scroll')));
      await tester.tap(find.byKey(const Key('layout_override_save_button')));
      await tester.pumpAndSettle();

      final saved = await bookReaderPrefsRepository.load('1');
      expect(saved.fontSize, 1.5, reason: '既有 fontSize 不應被清空');
      expect(saved.marginTop, 24, reason: '既有 marginTop 不應被清空');
      expect(
        saved.writingModeOverride,
        isNull,
        reason:
            '選「使用預設」須真的清成 null，若誤用 copyWith() 的 ?? 語意則仍會殘留'
            '原本的 horizontal',
      );
      expect(saved.pageTurnModeOverride, PageTurnMode.scroll);
    },
  );

  testWidgets(
      '點擊「搜尋書本內容」入口，帶同一組關鍵字導航至 LibrarySearchScreen（epic-10-search Issue 4）',
      (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢', author: '曹雪芹');
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            searchRepository: FakeSearchRepository(),
          ),
        ),
    );
    await tester.pumpAndSettle();

    await _openLibrarySearchField(tester);

    await tester.enterText(
      find.byKey(const Key('library_search_field')),
      '紅樓',
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_content_search_entry_button')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LibrarySearchScreen), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
              find.byKey(const Key('library_search_screen_field')))
          .controller!
          .text,
      '紅樓',
    );
  });

  // 2026-09-28 使用者需求：「搜尋書本內容」點了是跳到另一個畫面，不需要在
  // 書架內容區佔一整列。改成標題列上的圖示按鈕、放在排序按鈕左邊，讓書架
  // 多出一列的高度（Mobiscribe Wave 可以排兩列封面）。
  testWidgets('「搜尋書本內容」入口在書架標題列、排序按鈕左邊，不再佔書架內容區',
      (tester) async {
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(
              initialBooks: [_testBook(id: '1', title: '紅樓夢')]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            searchRepository: FakeSearchRepository(),
          ),
        ),
    );
    await tester.pumpAndSettle();

    final entry = find.byKey(const Key('library_content_search_entry_button'));
    expect(
      find.descendant(of: find.byType(AppBar), matching: entry),
      findsOneWidget,
    );
    final sortButton = find.byKey(const Key('library_sort_view_button'));
    expect(tester.getCenter(entry).dx, lessThan(tester.getCenter(sortButton).dx));
    expect(
      tester.getCenter(entry).dy,
      moreOrLessEquals(tester.getCenter(sortButton).dy),
    );
  });

  testWidgets('searchRepository 為 null 時，「搜尋書本內容」入口停用（點擊無反應）',
      (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢');
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('library_content_search_entry_button')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LibrarySearchScreen), findsNothing);
  });

  testWidgets('多選模式下，「搜尋書本內容」入口停用（審查修正 M-2）', (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢');
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            searchRepository: FakeSearchRepository(),
          ),
        ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    // 2026-09-28：入口移到一般標題列，多選模式換成選取工具列，入口直接不出現。
    expect(
      find.byKey(const Key('library_content_search_entry_button')),
      findsNothing,
    );
  });

  testWidgets(
      'readerFeatureRepositories 參考改變時 didUpdateWidget 重新賦值 _batchActions 不拋例外'
      '（回歸保護：`late final` 誤用曾在 Epic 45 觸發 LateInitializationError，見 '
      'docs/epics/epic-45-interface-i18n/reviews/review-issue-1.md I-1）',
      (tester) async {
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
        readerFeatureRepositories: LibraryReaderFeatureRepositories(),
      ),
    );
    await tester.pumpAndSettle();

    // 重新 pumpWidget 同一個 LibraryScreen（同一個 widget tree 位置，State
    // 因此被重用、didUpdateWidget() 會被呼叫），但 readerFeatureRepositories
    // 改傳一個「欄位值相同但非同一物件參考」的新實例（刻意不用 const，避免
    // Dart 對相同引數的 const 建構式做規範化、折疊成同一個實例而測不出這個
    // 回歸）——LibraryReaderFeatureRepositories 未覆寫 ==（見本檔案上方既有
    // 註解「沒有覆寫 ==（預設參考相等）」），因此這裡必定觸發
    // LibraryScreen.didUpdateWidget() 的 _batchActions 重新賦值分支。修復前
    // （`late final`）這裡會拋出 LateInitializationError；修復後（`late`）
    // 應正常通過。
    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
        readerFeatureRepositories: LibraryReaderFeatureRepositories(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  group('三語言渲染驗證（epic-45-interface-i18n Issue 3）', () {
    testWidgets('英文介面下 AppBar／空狀態／選取模式文字正確以英文渲染', (tester) async {
      await pumpLocalizedWidget(
        tester,
        LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
        locale: const Locale('en'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Library'), findsOneWidget);
      expect(find.text('No books imported yet'), findsOneWidget);
      expect(find.text('Import Books'), findsOneWidget);
    });

    testWidgets('英文介面下選取模式 AppBar 標題依 ICU plural 正確處理單複數', (tester) async {
      final books = [
        _testBook(id: '1', title: 'Book A'),
        _testBook(id: '2', title: 'Book B'),
      ];
      await pumpLocalizedWidget(
        tester,
        LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: books),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
        locale: const Locale('en'),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const Key('book_item_1')));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.byKey(const Key('book_item_2')));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('簡體中文介面下分類拼貼格數量與刪除確認訊息正確以簡體渲染', (tester) async {
      final book = _testBook(id: '1', title: '測試書', groupName: '奇幻');
      await pumpLocalizedWidget(
        tester,
        LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
        locale: const Locale('zh', 'CN'),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('1 本'), findsOneWidget);

      await tester.tap(find.byKey(const Key('group_tile_奇幻')));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('book_item_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library_delete_books_button')));
      await tester.pumpAndSettle();

      expect(find.text('删除书籍'), findsOneWidget);
      expect(find.textContaining('将删除已选取的 1 本书籍'), findsOneWidget);
    });

    testWidgets('英文介面下書籍詳細資料對話框日期依 en 地區慣例格式化（非手動 y/m/d 拼接）',
        (tester) async {
      final book = _testBook(
        id: '1',
        title: 'Test Book',
        lastReadTime: DateTime(2026, 3, 15),
      );
      await pumpLocalizedWidget(
        tester,
        LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
        locale: const Locale('en'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_action_menu_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book_action_details')));
      await tester.pumpAndSettle();

      // DateFormat.yMd('en') 輸出格式為 "3/15/2026"（月/日/年），與手動拼接
      // 的 "2026/3/15"（年/月/日）不同，藉此驗證確實改用 DateFormat 而非
      // 殘留手動字串拼接。
      expect(find.textContaining('3/15/2026'), findsOneWidget);
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

/// 量測目前畫面樹上 `library_grid_view`／`library_list_view` 實際渲染了
/// 幾個書籍項目（`book_item_*` key）——用來在動態列數計算後，量到「當下
/// 裝置尺寸／字級底下真正算出的 pageSize」，取代寫死的舊「3/4」假設常數
/// （epic-36 Issue 7：pageSize 現在依實際可用高度動態計算，測試不能再
/// 預先假設固定列數）。呼叫時機：itemCount 必須大於等於這個裝置理論上
/// 可能算出的最大 pageSize（本檔案相關測試皆準備至少 20 本書），確保第
/// 一頁一定被塞滿、量到的數字就是真正的 pageSize，而非因為書不夠多被
/// itemCount 截斷的結果。
int _measuredPageSize(WidgetTester tester) {
  final finder = find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith('book_item_');
  });
  return finder.evaluate().length;
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
  BookSource source = BookSource.local,
  bool isDownloaded = true,
}) {
  // 預設時間戳改為依 id 內數字反向換算的確定性公式（不再用
  // `DateTime.now()`）：Issue 3 新增的分頁測試以
  // `List.generate(N, (i) => _testBook(id: '$i', ...))` 依序快速建立多本
  // 書籍，若沿用真實時鐘，同一迴圈中的呼叫可能落在同一毫秒或得到與
  // 迴圈方向不一致的遞增順序，讓預設「最後閱讀」排序下 book_item 的頁面
  // 分佈變得不穩定。id 內數字越大，此處换算出的預設 lastReadTime/
  // createTime 越舊，確保 book_item_0 排序在前；id 不含數字（例如
  // 'older'/'newer'）則退回同一個固定時間戳，測試需要區分先後時必須
  // 明確傳入 lastReadTime（`review-issue-3.md` Important #1）。
  final numericId = int.tryParse(id.replaceAll(RegExp(r'[^0-9]'), ''));
  final defaultTime = numericId != null
      ? DateTime.fromMillisecondsSinceEpoch(1700000000000 - numericId * 1000)
      : DateTime.fromMillisecondsSinceEpoch(1700000000000);
  return Book(
    id: id,
    title: title,
    author: author,
    format: format,
    filePath: filePath ?? 'content://example/$id.epub',
    source: source,
    coverPath: coverPath,
    groupName: groupName,
    isFixedLayout: isFixedLayout,
    isDownloaded: isDownloaded,
    createTime: defaultTime,
    lastReadTime: lastReadTime ?? defaultTime,
  );
}

/// 2026-09-28：書架搜尋列改收在標題列 🔍 按鈕，輸入前要先展開。已展開時
/// 不再點（再點會變成 ✕ 收合）。
Future<void> _openLibrarySearchField(WidgetTester tester) async {
  if (find.byKey(const Key('library_search_field')).evaluate().isNotEmpty) {
    return;
  }
  await tester.tap(find.byKey(const Key('library_search_toggle_button')));
  await tester.pumpAndSettle();
}
