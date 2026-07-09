import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/screens/reader_settings_sheet.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。原生
/// 渲染引擎（Readium／PdfRenderer）都需要真實的裝置檔案系統路徑，不能直接
/// 讀取 Flutter asset。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// 持續 pump，直到 [condition] 成立或逾時。`ReaderScreen` 對外只有 filePath
/// 一個建構參數（見 spec.md 的 seam 定義），onPageRendered/onError 是內部
/// 實作細節，因此本檔案用 Key 觀察渲染狀態是否轉換，而非直接掛 callback。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  Duration step = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時（$timeout）：條件未成立');
    }
    await tester.pump(step);
  }
}

bool _loadingIndicatorGone() =>
    find.byKey(const Key('reader_loading_indicator')).evaluate().isEmpty;

/// 判斷「⚙️版面」按鈕是否已就緒（存在且可點擊）。`onLayoutResolved` 觸發前
/// `_autoDetectedWritingMode` 為 null，此時按鈕的 `onPressed` 亦為 null
/// （見 reader_screen.dart 的 `_buildAppBarActions`），因此以此作為「自動
/// 偵測已完成」的觀察點——取代 Issue 4 移除的 `reader_writing_mode_toggle`
/// 讀取信號。
bool _layoutSettingsButtonReady(WidgetTester tester) {
  final finder = find.byKey(const Key('reader_layout_settings_button'));
  if (finder.evaluate().isEmpty) return false;
  return tester.widget<IconButton>(finder).onPressed != null;
}

Book _book(String id) => Book(
      id: id,
      title: '書名',
      format: BookFileFormat.epub,
      filePath: 'content://example/$id',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ReaderScreen 自 Issue 3 起需要 BookReaderPrefsRepository（見
  // docs/adr/0007-reader-screen-book-id-contract.md）。真實裝置上用記憶體
  // 資料庫即可，這些既有測試情境本身不驗證版面偏好設定的持久化行為
  // （持久化驗證見既有的 Bottom Sheet 互動測試）。
  late SqliteLibraryRepository libraryRepository;
  late BookReaderPrefsRepository prefsRepository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    prefsRepository = BookReaderPrefsRepository(libraryRepository.database);
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  testWidgets('ReaderScreen 開啟範例 EPUB 檔案，渲染出非空白內容', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.epub', 'sample.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '應觸發 onPageRendered（載入指示器消失且無錯誤訊息），'
            '但畫面顯示了錯誤');
  });

  testWidgets('ReaderScreen 開啟範例 PDF 檔案，渲染出非空白內容', (tester) async {
    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'sample.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 5),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '應觸發 onPageRendered（載入指示器消失且無錯誤訊息），'
            '但畫面顯示了錯誤');
  });

  testWidgets('開啟定樣式範例 EPUB，⚙️版面按鈕最終不顯示', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_fixed_layout.epub', 'sample_toggle_fixed.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () =>
          _loadingIndicatorGone() &&
          find
              .byKey(const Key('reader_layout_settings_button'))
              .evaluate()
              .isEmpty,
      timeout: const Duration(seconds: 10),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });

  testWidgets('開啟版面設定 Bottom Sheet，調整字型大小後畫面持續渲染成功、無 onError',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_settings_font_size.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    await libraryRepository.insertBook(_book('b_settings_1'));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_settings_1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => _layoutSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('reader_settings_font_size_increment')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '調整字型大小後畫面應持續渲染成功，不應觸發 onError');
  });

  testWidgets('調整版面設定後關閉重開該書，設定被正確記住（驗證 initialPreferences 生效）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_settings_persist.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_settings_persist';
    await libraryRepository.insertBook(_book(bookId));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsRepository: prefsRepository,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => _layoutSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('reader_settings_font_size_increment')));
    await tester.pump();
    // 給非同步的 BookReaderPrefsRepository.save() 足夠時間完成寫入，避免
    // 下方關閉重開的讀取搶在寫入完成前發生（widget test 環境下兩者共用
    // 同一個 event loop，不需要真的等很久，但仍需保守給一個緩衝）。
    await tester.pump(const Duration(milliseconds: 500));

    // 關閉目前畫面，模擬使用者離開閱讀器（觸發 EpubReaderView.dispose()
    // 釋放原生資源），再重新開啟同一本書。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    final reloadedPrefs = await prefsRepository.load(bookId);
    expect(reloadedPrefs.fontSize, 1.0625,
        reason: '初始值為 null（顯示原型預設 16），點擊一次 + 按鈕後應存成倍率 1.0625 (17/16)');

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsRepository: prefsRepository,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '帶著已持久化的 fontSize=17 重新開書，應正常渲染、不觸發 onError'
            '（驗證 EpubReaderView 的 initialPreferences 機制在真實裝置上正確運作）');
  });

  testWidgets('點擊排版方向覆寫圖示「強制直排」後，畫面持續渲染成功、無 onError',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_writing_mode_override.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    await libraryRepository.insertBook(_book('b_writing_mode_override'));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_writing_mode_override',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => _layoutSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();

    final verticalButton = find.byKey(const Key('reader_settings_writing_mode_vertical'));
    final sheetScrollable = find.descendant(
      of: find.byType(ReaderSettingsSheet),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(verticalButton, 50.0, scrollable: sheetScrollable);
    await tester.drag(sheetScrollable, const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(verticalButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '點擊「強制直排」覆寫圖示後畫面應持續渲染成功，不應觸發 onError');
  });

  testWidgets('點擊翻頁模式覆寫圖示「滾動翻頁」後，畫面持續渲染成功、無 onError',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_page_turn_mode_override.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    await libraryRepository.insertBook(_book('b_page_turn_mode_override'));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_page_turn_mode_override',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => _layoutSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();

    final scrollButton = find.byKey(const Key('reader_settings_page_turn_mode_scroll'));
    final sheetScrollable = find.descendant(
      of: find.byType(ReaderSettingsSheet),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(scrollButton, 50.0, scrollable: sheetScrollable);
    await tester.drag(sheetScrollable, const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(scrollButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '點擊「滾動翻頁」覆寫圖示後畫面應持續渲染成功，不應觸發 onError');
  });

  testWidgets(
      '未覆寫螢幕方向時，進入 ReaderScreen 後依全域預設值呼叫 '
      'SystemChrome.setPreferredOrientations（auto→空列表）', (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_orientation_default.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_orientation_default',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () =>
          calls.any((c) => c.method == 'SystemChrome.setPreferredOrientations'),
      timeout: const Duration(seconds: 10),
    );

    final call = calls.firstWhere(
      (c) => c.method == 'SystemChrome.setPreferredOrientations',
    );
    expect(call.arguments, isEmpty,
        reason: 'ScreenOrientationSetting.auto（未覆寫時的全域預設值）'
            '應對應空列表（允許全部方向）');
  });

  testWidgets(
      'screenOrientationOverride=lock90 時，SystemChrome.setPreferredOrientations '
      '帶入 landscapeLeft', (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    const bookId = 'b_orientation_lock90';
    await libraryRepository.insertBook(_book(bookId));
    await prefsRepository.save(
      bookId,
      const BookReaderPrefs(
        screenOrientationOverride: ScreenOrientationSetting.lock90,
      ),
    );

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_orientation_lock90.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsRepository: prefsRepository,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () =>
          calls.any((c) => c.method == 'SystemChrome.setPreferredOrientations'),
      timeout: const Duration(seconds: 10),
    );

    final call = calls.firstWhere(
      (c) => c.method == 'SystemChrome.setPreferredOrientations',
    );
    expect(call.arguments, ['DeviceOrientation.landscapeLeft']);
  });

  testWidgets('離開 ReaderScreen 後，SystemChrome.setPreferredOrientations([]) 被呼叫還原',
      (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    const bookId = 'b_orientation_dispose';
    await libraryRepository.insertBook(_book(bookId));
    await prefsRepository.save(
      bookId,
      const BookReaderPrefs(
        screenOrientationOverride: ScreenOrientationSetting.lock0,
      ),
    );

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'sample_orientation_dispose.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsRepository: prefsRepository,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () =>
          calls.any((c) => c.method == 'SystemChrome.setPreferredOrientations'),
      timeout: const Duration(seconds: 10),
    );
    calls.clear();

    // 離開畫面（觸發 ReaderScreen.dispose()），比照既有「關閉重開該書」
    // 測試模擬使用者離開閱讀器的既有手法。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    expect(
      calls.any((c) =>
          c.method == 'SystemChrome.setPreferredOrientations' &&
          (c.arguments as List).isEmpty),
      isTrue,
      reason: 'dispose() 應呼叫 SystemChrome.setPreferredOrientations([]) '
          '還原系統預設，不論進入時鎖定了哪個角度',
    );
  });
}
