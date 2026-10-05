import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import '../test/support/fake_reader_feature_dependencies.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 2));
}

/// 等待畫面上出現包含 [textFragment] 的文字，用於換頁後頁尾文字經由原生
/// method channel 非同步回報更新（`onPageChanged`）才會出現，真機上的
/// round-trip 耗時不固定，比照 [_pumpUntilLoaded] 既有的等待迴圈寫法，
/// 而非賭一個固定秒數的 `tester.pump(Duration(seconds: 1))`（既有慣例見
/// `integration_test/pdf_dual_page_test.dart`／`reader_screen_test.dart`
/// 換頁後一律呼叫 `tester.pumpAndSettle()`）。
Future<void> _pumpUntilTextFound(WidgetTester tester, String textFragment) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (find.textContaining(textFragment).evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：畫面上未出現包含「$textFragment」的文字');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Epic 7 Issue 4：PDF 熱區導覽 + 沉浸模式——真機整合測試。
///
/// 【真機人工驗證清單，本測試無法自動涵蓋】
/// 比照 epic-6-annotations Issue 2/3 integration_test 既有先例：Flutter
/// integration_test 對原生 View 的觸控事件模擬並不可靠，本專案既有慣例是
/// 原生手勢功能一律另外以真實裝置人工驗證，不嘗試以 tester.tap 模擬手指
/// 點在特定螢幕座標上。以下項目須另外以真實裝置人工驗證：
///   1. 依序點擊畫面上 9 個實體區域（左上/上/右上/左/中/右/左下/下/右下），
///      逐一確認對應到 navZoneActions 陣列中正確的格子（例如預設
///      rightFlip 模板：左欄＝上一頁、中欄＝選單、右欄＝下一頁）。
///   2. 開啟「顯示熱區輔助線」後，畫面上應能看到 9 格邊框與動作文字標籤，
///      且標籤文字與實際點擊行為一致。
///   3. 熱區點擊（單擊）與既有長按拖曳劃線框選手勢實際共存不衝突：短促
///      點擊觸發熱區動作、按住不放並拖曳觸發劃線框選，兩者不互相誤觸發
///      （ADR 0008 已標記的未收斂風險，本 issue 須收斂）。
///   4. 旋轉裝置後，9 格熱區的點擊位置隨畫面重新排版正確對應（不會維持
///      舊的座標網格）。
/// 本檔案自動化的部分改為驗證「分派邏輯」：透過 `ReaderScreen.
/// triggerZoneAction` 直接觸發，確認在真機原生渲染下（`PdfReaderView`
/// 已收到 `initialPreferences`、`_channel` 非 null）翻頁與沉浸模式切換
/// 真的生效——這條路徑不涉及座標模擬，純粹驗證 Dart 分派邏輯 → 原生
/// method channel → 真機渲染結果，是 integration_test 可靠涵蓋的範圍。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('triggerZoneAction(menu) 真機切換沉浸模式（AppBar／頁尾顯示/隱藏）',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );

    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'pdf_nav_zone_menu.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_nav_zone_menu',
      title: '熱區沉浸模式測試書',
      format: BookFileFormat.pdf,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    final key = GlobalKey<State<ReaderScreen>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(key: key, filePath: samplePath, bookId: 'b_nav_zone_menu', dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager)),
      ),
    );
    await _pumpUntilLoaded(tester);

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);

    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump();

    expect(find.byType(AppBar), findsNothing);

    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('triggerZoneAction(nextPage/previousPage) 真機正確換頁，且不影響沉浸模式',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );

    // 注意：改用 sample_dual_page.pdf（共 6 頁，比照
    // pdf_dual_page_test.dart 既有先例）而非單頁的 sample.pdf——換頁測試
    // 需要至少 2 頁才能驗證 nextPage() 真的把頁碼從 1 推進到 2。
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_dual_page.pdf', 'pdf_nav_zone_pageturn.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_nav_zone_pageturn',
      title: '熱區換頁測試書',
      format: BookFileFormat.pdf,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    final key = GlobalKey<State<ReaderScreen>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(key: key, filePath: samplePath, bookId: 'b_nav_zone_pageturn', dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager)),
      ),
    );
    await _pumpUntilLoaded(tester);

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(find.byKey(const Key('reader_footer')), findsOneWidget);
    expect(find.textContaining('第 1/'), findsOneWidget, reason: '初始應在第 1 頁');

    ReaderScreen.triggerZoneAction(key, ZoneAction.nextPage);
    await _pumpUntilTextFound(tester, '第 2/');

    expect(find.textContaining('第 2/'), findsOneWidget, reason: '呼叫 nextPage 後應換到第 2 頁');
    expect(find.byType(AppBar), findsOneWidget, reason: '換頁不應影響沉浸模式（design.md 決策 #14）');

    ReaderScreen.triggerZoneAction(key, ZoneAction.previousPage);
    await _pumpUntilTextFound(tester, '第 1/');

    expect(find.textContaining('第 1/'), findsOneWidget, reason: '呼叫 previousPage 後應換回第 1 頁');
    expect(find.byType(AppBar), findsOneWidget);
  });
}
