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

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// 持續 pump，直到載入指示器消失或逾時，比照
/// integration_test/reading_position_test.dart 的既有 helper。
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

/// 持續 pump，直到浮動進度文字（reader_foliate_progress_text）出現或逾時——
/// foliate-js 完成首次 relocate 回報前不會顯示，與「載入指示器消失」是兩個
/// 獨立的時間點。這個小型文字（`_buildFoliateProgressText()`）與含跳頁
/// 輸入框的完整 `ReaderFooter`（`Key('reader_footer')`）不同——後者只在
/// 點擊 `reader_foliate_progress_button` 開啟 Bottom Sheet 後才存在，見
/// `reader_screen.dart` 的 `_openFoliateProgressSheet()`。
Future<void> _pumpUntilProgressVisible(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (find.byKey(const Key('reader_foliate_progress_text')).evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：浮動進度文字未出現');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('EPUB 開書後浮動進度文字顯示正確格式（epic-26 Issue 5：不再依賴全書字元數快取）',
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
        'test/fixtures/sample_long_vertical.epub', 'epub_pagination_integration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_epub_pagination',
      title: 'EPUB 分頁估算測試書 1',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_epub_pagination',
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    await _pumpUntilProgressVisible(tester);
    final progressTextFinder = find.byKey(const Key('reader_foliate_progress_text'));
    final progressText = (tester.widget<Text>(progressTextFinder)).data ?? '';
    expect(progressText, matches(RegExp(r'^\d+/\d+$')),
        reason: '浮動進度文字應顯示「currentPage/totalPages」格式');
  });

  testWidgets('點擊浮動進度按鈕開啟頁尾 Bottom Sheet，輸入框跳頁後畫面確實跳轉到目標頁附近',
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
        'test/fixtures/sample.epub', 'epub_pagination_jump_integration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    // 【審查修正】同上，先插入書籍列。
    await libraryRepository.insertBook(Book(
      id: 'b_epub_pagination_jump',
      title: 'EPUB 分頁估算測試書 2',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_epub_pagination_jump',
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilProgressVisible(tester);

    // 【審查修正】含跳頁輸入框的 ReaderFooter 只存在於 Bottom Sheet 內，
    // 開書後不會自動出現，須先點擊浮動按鈕開啟。
    await tester.tap(find.byKey(const Key('reader_foliate_progress_button')));
    await tester.pumpAndSettle();

    final footerProgressTextFinder =
        find.byKey(const Key('reader_footer_progress_text'));
    expect(footerProgressTextFinder, findsOneWidget);
    final totalPagesText =
        (tester.widget<Text>(footerProgressTextFinder)).data ?? '';
    final match = RegExp(r'^\d+/(\d+)$').firstMatch(totalPagesText);
    expect(match, isNotNull);
    final totalPages = int.parse(match!.group(1)!);
    final targetPage = (totalPages / 2).ceil().clamp(1, totalPages);

    await tester.enterText(
        find.byKey(const Key('reader_footer_jump_input')), '$targetPage');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final progressText =
        (tester.widget<Text>(footerProgressTextFinder)).data ?? '';
    expect(progressText, contains('$targetPage/$totalPages'),
        reason: '輸入框跳頁後 Bottom Sheet 內的頁尾應更新為目標頁');
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
}
