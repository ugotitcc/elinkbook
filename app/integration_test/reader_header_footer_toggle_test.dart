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
import 'package:elinkbook/reader/book_reader_prefs.dart';
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

/// Epic 5 Issue 5：頁首/頁尾顯示切換——真機整合測試。
///
/// 純 flutter test 環境下 EpubReaderView._channel 恆為 null（AndroidView
/// 未真正建立），無法觸發 onPageRendered/onLayoutResolved 等原生回呼，
/// 因此「書籍載入完成後 AppBar 標題正確替換」及「頁尾受 showFooter 控制」
/// 等需要原生渲染引擎參與的端到端行為，必須在此檔案以真機驗證。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'EPUB reflowable 預設（未持久化）開書後，AppBar 標題顯示章節名稱元件'
      '（reader_appbar_chapter_title），頁尾正常顯示',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
    addTearDown(() => libraryRepository.close());

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'reader_header_toggle_epub.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    // 必須先插入書籍，否則 prefs 寫入會因 FOREIGN KEY 約束失敗
    await libraryRepository.insertBook(Book(
      id: 'b_header_toggle_integration',
      title: '預設測試書',
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
          bookId: 'b_header_toggle_integration',
          prefsManager: prefsManager,
        ),
      ),
    );

    // 等待原生 PlatformView 載入完成（loading indicator 消失）。
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 原生端完成渲染後，Dart 端需要一次額外 pump 以處理回呼佇列（如
    // onLayoutResolved、onCharacterCountReady 等 microtask）。
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    // 預設 showHeader=true → AppBar 標題應為可點擊的章節標題元件。
    expect(find.byKey(const Key('reader_appbar_chapter_title')), findsOneWidget,
        reason: '預設 showHeader=true 時 AppBar 標題應顯示 reader_appbar_chapter_title');
    expect(find.byKey(const Key('reader_appbar_static_title')), findsNothing,
        reason: '預設 showHeader=true 時不應出現靜態「閱讀器」文字');
    // 預設 showFooter=true → 頁尾正常顯示。
    expect(find.byKey(const Key('reader_footer')), findsOneWidget,
        reason: '預設 showFooter=true 時頁尾應顯示');
  });

  testWidgets(
      '已持久化 showHeader=false 開 EPUB 書後，AppBar 標題維持靜態「閱讀器」文字'
      '（reader_appbar_static_title），頁尾仍正常顯示',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
    addTearDown(() => libraryRepository.close());

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'reader_header_off_integration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    // 必須先插入書籍，否則 prefs 寫入會因 FOREIGN KEY 約束失敗
    await libraryRepository.insertBook(Book(
      id: 'b_header_off_integration',
      title: '頁首關閉測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    // 預先寫入 showHeader=false 的單書偏好。
    await prefsManager.saveBookPrefs(
      'b_header_off_integration',
      const BookReaderPrefs(showHeader: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_header_off_integration',
          prefsManager: prefsManager,
        ),
      ),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    // showHeader=false → 標題維持靜態「閱讀器」文字。
    expect(find.byKey(const Key('reader_appbar_static_title')), findsOneWidget,
        reason: 'showHeader=false 時 AppBar 標題應為 reader_appbar_static_title');
    expect(find.text('閱讀器'), findsOneWidget,
        reason: 'showHeader=false 時 AppBar 標題文字為「閱讀器」');
    expect(find.byKey(const Key('reader_appbar_chapter_title')), findsNothing,
        reason: 'showHeader=false 時不應出現 reader_appbar_chapter_title');
    // showFooter 預設為 true（未持久化 showFooter），頁尾應正常顯示。
    expect(find.byKey(const Key('reader_footer')), findsOneWidget,
        reason: 'showFooter 預設 true 時頁尾應顯示');
  });

  testWidgets(
      '已持久化 showFooter=false 開 EPUB 書後，頁尾不顯示，'
      'AppBar 標題仍正常顯示章節名稱元件',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
    addTearDown(() => libraryRepository.close());

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'reader_footer_off_integration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    // 必須先插入書籍，否則 prefs 寫入會因 FOREIGN KEY 約束失敗
    await libraryRepository.insertBook(Book(
      id: 'b_footer_off_integration',
      title: '頁尾關閉測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await prefsManager.saveBookPrefs(
      'b_footer_off_integration',
      const BookReaderPrefs(showFooter: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_footer_off_integration',
          prefsManager: prefsManager,
        ),
      ),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    // showFooter=false → 頁尾不顯示。
    expect(find.byKey(const Key('reader_footer')), findsNothing,
        reason: 'showFooter=false 時頁尾不應顯示');
    // showHeader 預設為 true（未持久化），AppBar 標題應為章節名稱元件。
    expect(find.byKey(const Key('reader_appbar_chapter_title')), findsOneWidget,
        reason: 'showHeader 預設 true 時 AppBar 標題應為 reader_appbar_chapter_title');
  });

  testWidgets(
      '已持久化 showFooter=false 開 PDF 書後，頁尾不顯示',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
    addTearDown(() => libraryRepository.close());

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'reader_pdf_footer_off_integration.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    // 必須先插入書籍，否則 prefs 寫入會因 FOREIGN KEY 約束失敗
    await libraryRepository.insertBook(Book(
      id: 'b_pdf_footer_off_integration',
      title: 'PDF 頁尾關閉測試書',
      format: BookFileFormat.pdf,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await prefsManager.saveBookPrefs(
      'b_pdf_footer_off_integration',
      const BookReaderPrefs(showFooter: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_pdf_footer_off_integration',
          prefsManager: prefsManager,
        ),
      ),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    // showFooter=false → 頁尾不顯示。
    expect(find.byKey(const Key('reader_footer')), findsNothing,
        reason: 'showFooter=false 時 PDF 頁尾不應顯示');
    // PDF 的 AppBar 標題恆為靜態「閱讀器」文字（頁首概念僅限 EPUB）。
    expect(find.byKey(const Key('reader_appbar_static_title')), findsOneWidget,
        reason: 'PDF 的 AppBar 標題恆為 reader_appbar_static_title');
  });
}
