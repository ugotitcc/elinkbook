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
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/screens/toc_bottom_sheet.dart';
import '../test/support/fake_reader_feature_dependencies.dart';
import '../test/support/pump_localized_widget.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pumpUntilFooterVisible(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (find.byKey(const Key('reader_footer')).evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：頁尾未出現（全書字元數計算未完成）');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 審查修正：目錄按鈕的啟用條件除了書本開啟外，另需背景目錄抓取
/// （`EpubReaderView.loadTableOfContents`）完成（見 `_tocLoaded`），與頁尾
/// 出現與否（字元數背景計算完成）是兩條獨立的非同步路徑，不保證何者先
/// 完成——不能假設頁尾出現時目錄一定也已抓取完畢，需明確等待按鈕本身轉為
/// 可點擊，而非緊接著 `_pumpUntilFooterVisible` 就直接點擊。
Future<void> _pumpUntilTocButtonEnabled(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final finder = find.byKey(const Key('reader_chrome_toc_button'));
    if (finder.evaluate().isNotEmpty &&
        tester.widget<IconButton>(finder).onPressed != null) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：目錄按鈕未轉為可點擊狀態（背景目錄抓取未完成）');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpUntilProgressChanged(WidgetTester tester, String oldProgressText) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final textFinder = find.byKey(const Key('reader_footer_progress_text'));
    if (textFinder.evaluate().isNotEmpty) {
      final currentText = tester.widget<Text>(textFinder).data ?? '';
      if (currentText != oldProgressText) {
        return; // 進度已變更，跳出
      }
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：頁尾進度文字未改變，仍為 $oldProgressText');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('EPUB 目錄樹狀清單正確渲染巢狀結構，點選項目後畫面確實跳轉至正確章節',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub', 'epub_toc_integration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_epub_toc',
      title: 'EPUB 目錄測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: 'b_epub_toc',
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilFooterVisible(tester);

    final initialProgressText =
        (tester.widget<Text>(find.byKey(const Key('reader_footer_progress_text'))))
                .data ??
            '';

    // 開啟目錄，驗證頂層 3 章皆顯示。
    // epic-54 Issue 19 修復後：目前章節改以 spine index 判定，開書在第一章時
    // 第二章必須預設收合（保護「開書預設收合」，本測試曾於 Issue 18 為繞過
    // 已知缺陷而放寬，現已改回）。
    await _pumpUntilTocButtonEnabled(tester);
    await tester.tap(find.byKey(const Key('reader_chrome_toc_button')));
    await tester.pumpAndSettle();

    expect(find.byType(TocBottomSheet), findsOneWidget);
    expect(find.text('第一章：起始'), findsOneWidget);
    expect(find.text('第二章：發展'), findsOneWidget);
    expect(find.text('第三章：結局'), findsOneWidget);

    // 展開第二章，驗證巢狀子項出現。
    // 注意：展開按鈕的 Key 由 TocBottomSheet 內部產生，實際 Key 字串
    // 取決於 Readium 序列化的 locatorJson 內容。此處改用「找到「第二章：
    // 發展」文字所在的 ListTile，再找同一列的 IconButton」策略，避免
    // Key 字串不匹配導致測試失敗。
    final chapter2Row = find.text('第二章：發展');
    expect(chapter2Row, findsOneWidget);
    final expandButton = find.descendant(
      of: find.ancestor(
        of: chapter2Row,
        matching: find.byType(ListTile),
      ),
      matching: find.byType(IconButton),
    );
    expect(expandButton, findsOneWidget);
    // 開書預設只展開目前章節（第一章）；第二章的子節此時不得出現。
    expect(find.text('第一節'), findsNothing, reason: '開書在第一章，第二章應預設收合');
    expect(find.text('第二節'), findsNothing);
    await tester.tap(expandButton);
    await tester.pump();
    expect(find.text('第一節'), findsOneWidget);
    expect(find.text('第二節'), findsOneWidget);

    // 點選「第三章：結局」，驗證目錄自動關閉、頁尾進度確實反映跳轉結果。
    // FR-08「200ms 內完成跳轉」的時限本身，因 Bottom Sheet 關閉動畫
    // （Material 預設約 250-300ms）與原生跳轉耗時混在同一段
    // pumpAndSettle() 內、無法乾淨拆分自動化量測，已於真機以人工肉眼／
    // 碼表確認跳轉本身（非含 UI 轉場動畫）在觀感上是瞬間完成，此處改以
    // 內容正確性斷言（進度確實改變）驗證跳轉發生。
    await tester.tap(find.text('第三章：結局'));
    await tester.pumpAndSettle();

    expect(find.byType(TocBottomSheet), findsNothing, reason: '點選後應自動關閉目錄');

    // 等待 Native 跳轉並回報最新 progress 到 Dart 端使進度文字改變
    await _pumpUntilProgressChanged(tester, initialProgressText);
    final finalProgressText =
        (tester.widget<Text>(find.byKey(const Key('reader_footer_progress_text'))))
                .data ??
            '';
    expect(finalProgressText, isNot(initialProgressText),
        reason: '跳轉到第三章後頁尾進度應與開書時的起始位置不同');
    // 跳到第三章後再開目錄：目前章節應為第三章，第二章子節不得展開
    // （驗證判定不只在開書當下正確，epic-54 Issue 19）。
    await _pumpUntilTocButtonEnabled(tester);
    await tester.tap(find.byKey(const Key('reader_chrome_toc_button')));
    await tester.pumpAndSettle();
    expect(find.byType(TocBottomSheet), findsOneWidget);
    expect(find.text('第一節'), findsNothing, reason: '跳到第三章後第二章應維持收合');
    expect(find.text('第二節'), findsNothing);
    // 第三章應被標示為目前章節（TocBottomSheet 以 ListTile.selected 表示）。
    final ch3Tile =
        tester.widget<ListTile>(find.widgetWithText(ListTile, '第三章：結局'));
    expect(ch3Tile.selected, isTrue, reason: '跳轉後第三章應標示為目前章節');

    // 測試自行清理：關閉目錄，避免懸置的 Modal 影響 teardown 或後續案例。
    await tester.tap(find.byKey(const Key('toc_bottom_sheet_close_button')));
    await tester.pumpAndSettle();
    expect(find.byType(TocBottomSheet), findsNothing, reason: '目錄驗證完成後應正常關閉');
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });

  testWidgets('單一 spine 內多個目錄錨點：開書與跳轉後「目前章節」皆由 DOM 判定，精確到小節（epic-54 Issue 20）',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_single_spine_multi_anchor.epub',
        'epub_toc_single_spine.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_epub_toc_single_spine',
      title: 'EPUB 單檔多錨點目錄測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: 'b_epub_toc_single_spine',
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilFooterVisible(tester);

    Future<void> openToc() async {
      await _pumpUntilTocButtonEnabled(tester);
      await tester.tap(find.byKey(const Key('reader_chrome_toc_button')));
      await tester.pumpAndSettle();
      expect(find.byType(TocBottomSheet), findsOneWidget);
    }

    bool selected(String title) =>
        tester.widget<ListTile>(find.widgetWithText(ListTile, title)).selected;

    Future<void> closeToc() async {
      await tester.tap(find.byKey(const Key('toc_bottom_sheet_close_button')));
      await tester.pumpAndSettle();
    }

    String progressText() =>
        tester
            .widget<Text>(find.byKey(const Key('reader_footer_progress_text')))
            .data ??
        '';

    // 1) 開書位於第一節（頁面含 h1 與 s1 錨點，s2/s3 在後面）：
    //    不得因全書 progression 偏高而選到第二、三節。
    await openToc();
    expect(selected('第一節'), isTrue, reason: '開書位於第一節');
    expect(selected('第二節'), isFalse);
    expect(selected('第三節'), isFalse);
    final progressAtOpen = progressText();

    // 2) 跳到第三節。
    await tester.tap(find.widgetWithText(ListTile, '第三節'));
    await tester.pumpAndSettle();
    await _pumpUntilProgressChanged(tester, progressAtOpen);
    await openToc();
    expect(selected('第三節'), isTrue, reason: '跳到第三節後應標示第三節');
    expect(selected('第一節'), isFalse);
    expect(selected('第二節'), isFalse);
    final progressAtS3 = progressText();

    // 3) 回頭跳到第二節（往回跳，驗證不是只會往後）。
    await tester.tap(find.widgetWithText(ListTile, '第二節'));
    await tester.pumpAndSettle();
    await _pumpUntilProgressChanged(tester, progressAtS3);
    await openToc();
    expect(selected('第二節'), isTrue, reason: '往回跳到第二節後應標示第二節');
    expect(selected('第一節'), isFalse);
    expect(selected('第三節'), isFalse);

    await closeToc();
    expect(find.byType(TocBottomSheet), findsNothing);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
}
