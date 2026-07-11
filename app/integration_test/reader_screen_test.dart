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
import 'package:elinkbook/reader/reader_prefs_manager.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/screens/pdf_settings_sheet.dart';
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

Book _book(String id, {BookFileFormat format = BookFileFormat.epub}) => Book(
      id: id,
      title: '書名',
      format: format,
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
  late ReaderPrefsManager prefsManager;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
    );
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
          prefsManager: prefsManager,
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
          prefsManager: prefsManager,
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
          prefsManager: prefsManager,
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
          prefsManager: prefsManager,
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
          prefsManager: prefsManager,
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

    final reloadedPrefs = (await prefsManager.load(bookId)).bookPrefs;
    expect(reloadedPrefs.fontSize, 1.0625,
        reason: '初始值為 null（顯示原型預設 16），點擊一次 + 按鈕後應存成倍率 1.0625 (17/16)');

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
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
          prefsManager: prefsManager,
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
          prefsManager: prefsManager,
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
          prefsManager: prefsManager,
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
    await prefsManager.saveBookPrefs(
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
          prefsManager: prefsManager,
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
    await prefsManager.saveBookPrefs(
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
          prefsManager: prefsManager,
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

  testWidgets('PDF 點擊「⚙️版面」按鈕開啟 PdfSettingsSheet（非 ReaderSettingsSheet）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_settings_open.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_settings_open';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
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

    expect(find.byType(PdfSettingsSheet), findsOneWidget);
    expect(find.byType(ReaderSettingsSheet), findsNothing);
  });

  testWidgets('PDF 切換三種 Fit 模式，畫面持續渲染成功、無 onError', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_fit_mode.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_fit_mode';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
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

    for (final keySuffix in ['fit_width', 'actual_size', 'page_fit']) {
      await tester.tap(find.byKey(Key('pdf_settings_fit_mode_$keySuffix')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('reader_error_text')), findsNothing,
          reason: '切換至 $keySuffix 後畫面應持續渲染成功，不應觸發 onError');
    }
  });

  testWidgets('調整 PDF Fit 模式後關閉重開該書，設定被正確記住', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_fit_mode_persist.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_fit_mode_persist';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
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
    await tester.tap(find.byKey(const Key('pdf_settings_fit_mode_actual_size')));
    await tester.pump();
    // 給非同步的 BookReaderPrefsRepository.save() 足夠時間完成寫入。
    await tester.pump(const Duration(milliseconds: 500));

    final saved = (await prefsManager.load(bookId)).bookPrefs;
    expect(saved.pdfFitMode, PdfFitMode.actualSize);

    // 關閉重開，確認 initialPreferences 機制真正生效（不只是 UI 顯示）。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.fitMode, PdfFitMode.actualSize);
  });

  testWidgets('PDF 調整對比度／亮度後畫面持續渲染成功、無 onError', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_filters.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_filters';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
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
    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    for (final keySuffix in ['contrast_increment', 'brightness_decrement']) {
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(Key('pdf_settings_$keySuffix')));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('reader_error_text')), findsNothing,
          reason: '調整 $keySuffix 後畫面應持續渲染成功，不應觸發 onError');
    }
  });

  testWidgets('調整 PDF 對比度／亮度後關閉重開該書，設定被正確記住', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_filters_persist.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_filters_persist';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
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
    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_contrast_increment')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final saved = (await prefsManager.load(bookId)).bookPrefs;
    expect(saved.pdfContrast, 5); // 預設 0，點一次 +5

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.contrast, 5);
  });

  testWidgets('PDF 調整加粗強度後畫面持續渲染成功、無 onError', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_bold.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_bold';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
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
    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('pdf_settings_bold_strength_increment')));
    // boldStrength 變動觸發完整重新渲染，比 contrast/brightness 更重，給予
    // 較長的 settle 時間。
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '調整加粗強度後畫面應持續渲染成功，不應觸發 onError');
  });

  testWidgets('調整 PDF 加粗強度後關閉重開該書，設定被正確記住', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_bold_persist.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_bold_persist';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
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
    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('pdf_settings_bold_strength_increment')));
    await tester.pump(const Duration(seconds: 1));

    final saved = (await prefsManager.load(bookId)).bookPrefs;
    expect(saved.pdfBoldStrength, closeTo(0.1, 0.001)); // 預設 0，點一次 +10（UI）換算 +0.1

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.boldStrength, closeTo(0.1, 0.001));
  });

  testWidgets('PDF 切換至智慧自動裁切，畫面持續渲染成功、無 onError', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_crop.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_crop';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
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
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_auto')));
    // 首次切到 autoDetect 會觸發偵測＋完整重新渲染，給予較長的 settle
    // 時間。
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '切換至智慧自動裁切後畫面應持續渲染成功，不應觸發 onError');
  });

  testWidgets('智慧自動裁切計算後關閉重開該書，pdf_crop_rect 不重新計算（值一致）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_crop_persist.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_crop_persist';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
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
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_auto')));
    await tester.pump(const Duration(seconds: 1));

    final firstRect = (await prefsManager.load(bookId)).bookPrefs.pdfCropRect;
    expect(firstRect, isNotNull, reason: '智慧自動裁切應已計算出矩形並持久化');

    // 關閉重開，確認 initialPreferences 帶入已持久化的 cropRect，原生端
    // 不會因為是全新 PlatformView 實例就重新偵測一次。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );
    await tester.pump(const Duration(seconds: 1));

    final secondRect = (await prefsManager.load(bookId)).bookPrefs.pdfCropRect;
    expect(secondRect, firstRect,
        reason: '重開書後 pdf_crop_rect 應與第一次計算的值完全一致，代表沒有重新計算');
  });

  testWidgets('PDF 進入手動裁切互動模式後，翻頁手勢暫停回應（不觸發頁面錯誤或意外離開裁切模式）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_crop_manual_pause.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_crop_manual_pause';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
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
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(PdfSettingsSheet), findsNothing,
        reason: '點擊手動選區後應關閉 PdfSettingsSheet、進入裁切互動模式');

    // 進入裁切互動模式期間，對 PdfReaderView 區域做水平拖曳手勢（正常
    // 閱讀模式下會觸發翻頁），確認不會出現錯誤畫面，也不會意外重新開啟
    // PdfSettingsSheet（那只在確認框選、onCropRectSelected 觸發後才會
    // 發生）——用來間接驗證翻頁手勢在裁切互動模式下確實被暫停，沒有讓
    // 原生端 nextPage()/previousPage() 觸發非預期的重新渲染或狀態改變。
    await tester.drag(find.byType(PdfReaderView), const Offset(-200, 0));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byType(PdfSettingsSheet), findsNothing,
        reason: '拖曳手勢不應觸發任何確認流程，裁切互動模式應維持進行中');
  });

  testWidgets('PDF 手動裁切拖拉四角控制點確認後，pdf_crop_mode/pdf_crop_rect 正確寫入且畫面套用新裁切結果',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_crop_manual_confirm.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_crop_manual_confirm';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
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
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pump(const Duration(seconds: 1));

    // 拖拉右下角控制點：從 PdfReaderView 區域內、預設初始裁切框（四周
    // 10% 邊距，見 PdfReaderView.kt 的 enterCropEditMode()）的右下角附近
    // 往左上方拖曳一段距離，縮小裁切框範圍。實際手勢座標依真機畫面尺寸
    // 計算——若 tester.drag()/tester.timedDrag() 對疊加於 AndroidView 之
    // 上的原生 CropOverlayView 無法正確傳遞觸控事件，改用
    // `adb shell input touchscreen swipe`（座標依 `adb shell wm size`
    // 查得的真機解析度換算），並在報告中誠實記錄實際採用的方式。
    final pdfViewBox = tester.getRect(find.byType(PdfReaderView));
    final approxBottomRightHandle = Offset(
      pdfViewBox.left + pdfViewBox.width * 0.9,
      pdfViewBox.top + pdfViewBox.height * 0.9,
    );
    final dragGesture = await tester.startGesture(approxBottomRightHandle);
    await tester.pump(const Duration(milliseconds: 50));
    await dragGesture.moveBy(const Offset(-80, -80));
    await tester.pump(const Duration(milliseconds: 50));
    await dragGesture.up();
    await tester.pump(const Duration(seconds: 1));

    // 點擊確認按鈕：CropOverlayView 把它畫在固定右下角（見
    // CONFIRM_BUTTON_MARGIN_DP/CONFIRM_BUTTON_RADIUS_DP 常數），螢幕座標
    // 需依裝置 density 換算，實測時直接對 PdfReaderView 區域右下角附近
    // 嘗試點擊即可命中（確認按鈕的視覺半徑遠大於一般手指誤差）。
    final approxConfirmButton = Offset(
      pdfViewBox.right - 40,
      pdfViewBox.bottom - 40,
    );
    await tester.tapAt(approxConfirmButton);
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byType(PdfSettingsSheet), findsOneWidget,
        reason: '確認框選後應重新開啟 PdfSettingsSheet 顯示套用結果');

    final saved = (await prefsManager.load(bookId)).bookPrefs;
    expect(saved.pdfCropMode, PdfCropMode.manual);
    expect(saved.pdfCropRect, isNotNull);
  });

  testWidgets(
      'PDF 手動裁切重新進入互動模式並再次確認（manual→manual）流程不出錯，且'
      '第二次確認結果持續正確持久化（回歸測試：原生端 cropRect 欄位過去只在'
      'cropMode 變動時才更新，manual→manual 的重新確認不會觸發此更新，見'
      'PdfReaderView.kt enterCropEditMode() 的修復。'
      '已知限制：本測試在此真機／Flutter 版本組合下，`tester.startGesture`'
      '／`dragFrom`／原始 PointerEvent 注入／adb 觸控注入皆無法讓'
      'CropOverlayView 的控制點產生位移（詳細診斷見'
      'task-6-fix-report.md），因此本測試無法驗證「兩次確認的矩形數值不同」，'
      '只驗證 manual→manual 重新確認路徑本身不出錯、且結果持續正確持久化——'
      '這仍是既有測試套件未涵蓋的新情境，既有的單輪手動裁切測試從未重新'
      '進入過裁切互動模式）', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_crop_manual_readjust.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_crop_manual_readjust';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
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
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pump(const Duration(seconds: 2));

    final pdfViewBox = tester.getRect(find.byType(PdfReaderView));
    final approxConfirmButton = Offset(
      pdfViewBox.right - 40,
      pdfViewBox.bottom - 40,
    );

    // 第一次框選：none → manual 的首次確認（本身不是本測試鎖定驗證的
    // bug 情境，cropMode 有變動，既有 didUpdateWidget 機制本來就會正確
    // 更新原生端狀態；此處只是必要的前置步驟，讓 cropMode 進入 manual，
    // 為下方「manual → manual 重新確認」鋪路）。
    await tester.tapAt(approxConfirmButton);
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byType(PdfSettingsSheet), findsOneWidget,
        reason: '第一次確認框選後應重新開啟 PdfSettingsSheet');

    final firstSaved = (await prefsManager.load(bookId)).bookPrefs;
    expect(firstSaved.pdfCropMode, PdfCropMode.manual);
    final firstRect = firstSaved.pdfCropRect;
    expect(firstRect, isNotNull);

    // 重新進入手動裁切互動模式——這是本測試要驗證的核心情境：cropMode
    // 在這次重新調整前後全程維持 manual、不曾變動，因此不會像
    // none/autoDetect → manual 的首次框選那樣，透過
    // PdfReaderView.dart 的 didUpdateWidget 偵測到 cropMode 變化、間接送出
    // setPdfPreferences 更新原生端 cropRect 欄位（見
    // reader_screen.dart _handleCropRectSelected／PdfReaderView.dart
    // didUpdateWidget）。修復前，這種情境下原生端 cropRect 欄位完全不會
    // 被更新；修復後，enterCropEditMode() 的 onConfirm 回呼本身會直接
    // 更新原生端狀態。
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(PdfSettingsSheet), findsNothing,
        reason: '第二次點擊手動選區後應再次關閉 PdfSettingsSheet、進入裁切互動模式');

    await tester.tapAt(approxConfirmButton);
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byType(PdfSettingsSheet), findsOneWidget,
        reason: '第二次確認框選後應再次重新開啟 PdfSettingsSheet');

    final secondSaved = (await prefsManager.load(bookId)).bookPrefs;
    expect(secondSaved.pdfCropMode, PdfCropMode.manual);
    final secondRect = secondSaved.pdfCropRect;
    expect(secondRect, isNotNull);
    // 因本測試無法驅動 CropOverlayView 的控制點產生實際位移（見上方測試
    // 名稱中的已知限制說明），第二次確認的矩形數值預期與第一次相同——
    // 這裡仍斷言其「與第一次確認一致」，確保 manual→manual 重新確認路徑
    // 至少不會意外把資料改壞（例如被清空、變成不同分頁的殘留值等）。
    // 修復本身的即時渲染效果（原生端 cropRect 是否確實同步更新），已改用
    // task-6-fix-report.md 記錄的原生端暫時性 Log.i 診斷輸出交叉核對，
    // 詳見報告書「已知限制與替代驗證方式」章節。
    expect(secondRect, equals(firstRect));
  });

  testWidgets(
      'PDF 依序調整 Fit 模式/對比度/亮度/加粗/裁切模式後關閉重開，全部欄位皆正確記住並套用（組合持久化收尾驗證）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_e2e_combo.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_e2e_combo';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
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

    // 顯示分頁：Fit 模式改為 Fit Width。
    await tester.tap(find.byKey(const Key('pdf_settings_fit_mode_fit_width')));
    await tester.pump(const Duration(milliseconds: 500));

    // 濾鏡分頁：對比度／亮度／加粗強度皆各按一次「+」微調鈕，確保三個欄位
    // 都偏離預設值 0，才能有效驗證彼此不會互相清空。
    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_contrast_increment')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('pdf_settings_brightness_increment')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('pdf_settings_bold_strength_increment')));
    await tester.pump(const Duration(milliseconds: 300));

    // 裁切分頁：切到智慧自動（不使用手動選區——依 Global Constraints，本
    // issue 不重複驗證 Issue 6 的觸控互動邏輯）。
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_auto')));
    await tester.pump(const Duration(seconds: 1));

    // 關閉設定，記錄目前畫面上 PdfReaderView 的完整生效值，作為「調整完成
    // 當下」的基準，稍後與「重開書後」比對。
    await tester.tap(find.byKey(const Key('pdf_settings_tab_display')));
    await tester.pumpAndSettle();

    final beforeClose = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(beforeClose.fitMode, PdfFitMode.fitWidth);
    expect(beforeClose.contrast, greaterThan(0));
    expect(beforeClose.brightness, greaterThan(0));
    expect(beforeClose.boldStrength, greaterThan(0));
    expect(beforeClose.cropMode, PdfCropMode.autoDetect);

    // 從資料庫直接讀出持久化結果（不透過畫面重建，排除「畫面剛好還沒
    // rebuild」這種偽陽性）。
    final saved = (await prefsManager.load(bookId)).bookPrefs;
    expect(saved.pdfFitMode, PdfFitMode.fitWidth);
    expect(saved.pdfContrast, greaterThan(0));
    expect(saved.pdfBrightness, greaterThan(0));
    expect(saved.pdfBoldStrength, greaterThan(0));
    expect(saved.pdfCropMode, PdfCropMode.autoDetect);
    expect(saved.pdfCropRect, isNotNull,
        reason: '智慧自動裁切應已計算出矩形並隨其餘欄位一併持久化');

    // 關閉重開，驗證 initialPreferences 在「多欄位同時非 null」的情境下
    // 依然完整無遺漏地送出——這是本任務要補上的、Issue 2-6 各自單欄位
    // 測試從未涵蓋過的組合情境。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );
    await tester.pump(const Duration(seconds: 1));

    final afterReopen = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(afterReopen.fitMode, beforeClose.fitMode,
        reason: '重開書後 fitMode 應與關閉前一致');
    expect(afterReopen.contrast, beforeClose.contrast,
        reason: '重開書後 contrast 應與關閉前一致');
    expect(afterReopen.brightness, beforeClose.brightness,
        reason: '重開書後 brightness 應與關閉前一致');
    expect(afterReopen.boldStrength, beforeClose.boldStrength,
        reason: '重開書後 boldStrength 應與關閉前一致');
    expect(afterReopen.cropMode, beforeClose.cropMode,
        reason: '重開書後 cropMode 應與關閉前一致');
    expect(afterReopen.cropRect, beforeClose.cropRect,
        reason: '重開書後 cropRect 應與關閉前一致，且不因重開書而重新計算'
            '（見 Issue 5 決策 #3：全書統一比例，不逐頁重算、不重開書重算）');

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
}
