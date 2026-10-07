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
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_frame_overlay.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/screens/fxl_settings_sheet.dart';
import 'package:elinkbook/screens/pdf_settings_sheet.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/screens/reader_settings_sheet.dart';
import '../test/support/fake_reader_feature_dependencies.dart';
import '../test/support/pump_localized_widget.dart';

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
  final finder = find.byKey(const Key('reader_chrome_layout_button'));
  if (finder.evaluate().isEmpty) return false;
  return tester.widget<IconButton>(finder).onPressed != null;
}

/// PDF 與 FXL 的「版面」按鈕（epic-38 Issue 1：統一走底部工具列的
/// `reader_chrome_layout_button`，`onPressed` 於 `_openBookFlow.isRendered`
/// 前恆為 null，見 reader_screen.dart 對應的 `onLayoutTap` 區塊）。
bool _pdfSettingsButtonReady(WidgetTester tester) {
  final finder = find.byKey(const Key('reader_chrome_layout_button'));
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
      ReadingPositionRepository(libraryRepository.database),
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

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: 'b1',
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
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

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: 'b1',
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
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

  testWidgets('開啟定樣式範例 EPUB，⚙️版面按鈕存在且點開後是 FxlSettingsSheet（非 ReaderSettingsSheet）',
      (tester) async {
    // epic-54 Issue 18（使用者決定 2026-10-07）：Epic 38 起三格式版面按鈕
    // 統一顯示、僅回呼分派不同，舊斷言「最終不顯示」與設計直接矛盾，改為
    // 驗存在且正確（見 reviews/triage-issue-18.md §(4-a)）。
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_fixed_layout.epub', 'sample_toggle_fixed.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: 'b1',
        isFixedLayout: true,
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    await _pumpUntil(
      tester,
      () =>
          _loadingIndicatorGone() &&
          find
              .byKey(const Key('reader_chrome_layout_button'))
              .evaluate()
              .isNotEmpty,
      timeout: const Duration(seconds: 10),
    );

    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pumpAndSettle();

    expect(find.byType(FxlSettingsSheet), findsOneWidget,
        reason: 'FXL 書籍的版面按鈕應開啟 FxlSettingsSheet');
    expect(find.byType(ReaderSettingsSheet), findsNothing,
        reason: 'FXL 書籍不應誤開流式書籍的 ReaderSettingsSheet');
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

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: 'b_settings_1',
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    await _pumpUntil(
      tester,
      () => _layoutSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
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

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: bookId,
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    await _pumpUntil(
      tester,
      () => _layoutSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
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
    await pumpLocalizedWidget(tester, const SizedBox.shrink());
    await tester.pumpAndSettle();

    final reloadedPrefs = (await prefsManager.load(bookId)).bookPrefs;
    expect(reloadedPrefs.fontSize, 1.0625,
        reason: '初始值為 null（顯示原型預設 16），點擊一次 + 按鈕後應存成倍率 1.0625 (17/16)');

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: bookId,
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
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

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: 'b_writing_mode_override',
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    await _pumpUntil(
      tester,
      () => _layoutSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pumpAndSettle();

    // 排版方向覆寫列在「呈現」分頁（IndexedStack 非 TabBarView，切分頁無動畫）。
    await tester.tap(find.byKey(const Key('reader_settings_tab_presentation')));
    await tester.pumpAndSettle();

    final verticalButton = find.byKey(const Key('reader_settings_writing_mode_vertical'));
    final sheetScrollable = find.descendant(
      of: find.byKey(const Key('reader_settings_tab_presentation_list')),
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

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: 'b_page_turn_mode_override',
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    await _pumpUntil(
      tester,
      () => _layoutSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pumpAndSettle();

    // 翻頁模式覆寫列在「呈現」分頁。
    await tester.tap(find.byKey(const Key('reader_settings_tab_presentation')));
    await tester.pumpAndSettle();

    final scrollButton = find.byKey(const Key('reader_settings_page_turn_mode_scroll'));
    final sheetScrollable = find.descendant(
      of: find.byKey(const Key('reader_settings_tab_presentation_list')),
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

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: 'b_orientation_default',
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
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

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: bookId,
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
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

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: bookId,
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
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
    await pumpLocalizedWidget(tester, const SizedBox.shrink());
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

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: bookId,
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    await _pumpUntil(
      tester,
      () => _pdfSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
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

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: bookId,
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    await _pumpUntil(
      tester,
      () => _pdfSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pumpAndSettle();

    for (final keySuffix in ['fit_width', 'actual_size', 'page_fit']) {
      await tester.tap(find.byKey(Key('pdf_settings_fit_mode_$keySuffix')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('reader_error_text')), findsNothing,
          reason: '切換至 $keySuffix 後畫面應持續渲染成功，不應觸發 onError');
    }
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

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: bookId,
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    await _pumpUntil(
      tester,
      () => _pdfSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
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

  testWidgets('PDF 調整加粗強度後畫面持續渲染成功、無 onError', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_bold.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_bold';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: bookId,
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    await _pumpUntil(
      tester,
      () => _pdfSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
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

  testWidgets('PDF 切換至智慧自動裁切，畫面持續渲染成功、無 onError', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_crop.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_crop';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: bookId,
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    await _pumpUntil(
      tester,
      () => _pdfSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
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

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: bookId,
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    await _pumpUntil(
      tester,
      () => _pdfSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_auto')));
    await tester.pump(const Duration(seconds: 1));

    final firstRect = (await prefsManager.load(bookId)).bookPrefs.pdfCropRect;
    expect(firstRect, isNotNull, reason: '智慧自動裁切應已計算出矩形並持久化');

    // 關閉重開，確認 initialPreferences 帶入已持久化的 cropRect，原生端
    // 不會因為是全新 PlatformView 實例就重新偵測一次。
    await pumpLocalizedWidget(tester, const SizedBox.shrink());
    await tester.pump();

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: bookId,
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
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

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: bookId,
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    await _pumpUntil(
      tester,
      () => _pdfSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
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

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: bookId,
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    await _pumpUntil(
      tester,
      () => _pdfSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pump(const Duration(seconds: 1));

    // epic-54 Issue 18（使用者決定 2026-10-07）：現行框選是整面手勢層
    //（`pdf_crop_frame_gesture_layer`）拖畫＋置中確認鈕
    //（`pdf_crop_frame_confirm`，無框時停用），已無「四角控制點」與右下角
    // 確認鈕（舊原生 CropOverlayView 概念，見
    // reviews/triage-issue-18.md §(4-c)）。此處在手勢層上拖出 0.5×0.5 的框
    //（任一邊須 ≥0.05 才有效），再按 Key 點確認。
    expect(find.byKey(const Key('pdf_crop_frame_gesture_layer')),
        findsOneWidget);
    final gestureBox =
        tester.getRect(find.byKey(const Key('pdf_crop_frame_gesture_layer')));
    final dragStart = Offset(
      gestureBox.left + gestureBox.width * 0.25,
      gestureBox.top + gestureBox.height * 0.3,
    );
    final dragGesture = await tester.startGesture(dragStart);
    await tester.pump(const Duration(milliseconds: 50));
    await dragGesture.moveBy(Offset(
      gestureBox.width * 0.5,
      gestureBox.height * 0.5,
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await dragGesture.up();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byKey(const Key('pdf_crop_frame_confirm')));
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    // 現行 UX（epic-58）：確認後直接套用並回到閱讀畫面，不再重開
    // PdfSettingsSheet（舊原生流程的行為；新流程見 onConfirm 實作）。
    expect(find.byType(PdfCropFrameOverlay), findsNothing,
        reason: '確認框選後應退出裁切互動模式');
    expect(find.byType(PdfSettingsSheet), findsNothing,
        reason: '現行確認後不重開 PdfSettingsSheet，直接套用回到閱讀畫面');

    final saved = (await prefsManager.load(bookId)).bookPrefs;
    expect(saved.pdfCropMode, PdfCropMode.manual);
    expect(saved.pdfCropRect, isNotNull);
  });

  testWidgets(
      'PDF 手動裁切重新進入互動模式並再次確認（manual→manual），第二次確認'
      '寫入新的矩形值且持續正確持久化', (tester) async {
    // epic-54 Issue 18（使用者決定 2026-10-07）：現行框選是手勢層拖畫
    //（控制點概念已由 epic-58 取代），兩次畫出不同的框並確認，第二次的矩形
    // 應與第一次不同——比原「已知限制」版（只能斷言相等）更強，真正驗到
    // manual→manual 重新確認有確實寫入（見
    // reviews/triage-issue-18.md §(4-c)）。
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_crop_manual_readjust.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_crop_manual_readjust';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: bookId,
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );

    await _pumpUntil(
      tester,
      () => _pdfSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pump(const Duration(seconds: 2));

    // 第一次框選：在手勢層上拖出第一個框並按 Key 確認（none → manual）。
    // 小工具：依比例在手勢層上拖畫出框。
    Future<void> drawBox(double l, double t, double r, double b) async {
      final box =
          tester.getRect(find.byKey(const Key('pdf_crop_frame_gesture_layer')));
      final gesture = await tester.startGesture(
        Offset(box.left + box.width * l, box.top + box.height * t),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(Offset(
        box.width * (r - l),
        box.height * (b - t),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.byKey(const Key('pdf_crop_frame_gesture_layer')),
        findsOneWidget);
    await drawBox(0.2, 0.25, 0.65, 0.7);
    await tester.tap(find.byKey(const Key('pdf_crop_frame_confirm')));
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byType(PdfCropFrameOverlay), findsNothing,
        reason: '第一次確認框選後應退出裁切互動模式');

    final firstSaved = (await prefsManager.load(bookId)).bookPrefs;
    expect(firstSaved.pdfCropMode, PdfCropMode.manual);
    final firstRect = firstSaved.pdfCropRect;
    expect(firstRect, isNotNull);

    // 重新進入手動裁切互動模式——這是本測試要驗證的核心情境：cropMode
    // 在這次重新調整前後全程維持 manual。現行機制下 onConfirm 直接經
    // _handlePrefsChanged 寫入 prefs（見 ReaderScreen 的 onConfirm 實作），
    // 不依賴 cropMode 變動，因此第二次確認必須寫入新的矩形值。
    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(PdfSettingsSheet), findsNothing,
        reason: '第二次點擊手動選區後應再次關閉 PdfSettingsSheet、進入裁切互動模式');
    expect(find.byKey(const Key('pdf_crop_frame_gesture_layer')),
        findsOneWidget);

    // 第二次畫出明顯不同的框並確認。
    await drawBox(0.35, 0.4, 0.85, 0.9);
    await tester.tap(find.byKey(const Key('pdf_crop_frame_confirm')));
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byType(PdfCropFrameOverlay), findsNothing,
        reason: '第二次確認框選後應退出裁切互動模式');

    final secondSaved = (await prefsManager.load(bookId)).bookPrefs;
    expect(secondSaved.pdfCropMode, PdfCropMode.manual);
    final secondRect = secondSaved.pdfCropRect;
    expect(secondRect, isNotNull);
    // 兩次畫出不同的框，第二次的矩形必須與第一次不同——證明 manual→manual
    // 重新確認確實寫入新值（比舊版「只能斷言相等」更強）。
    expect(secondRect, isNot(equals(firstRect)),
        reason: '第二次確認應寫入新畫的框選矩形，而非沿用第一次的值');
  });

}
