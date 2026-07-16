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
import 'package:elinkbook/reader/epub_character_count_repository.dart';
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

/// 持續 pump，直到頁尾（reader_footer）出現或逾時——全書字元數背景計算
/// 完成前頁尾不會顯示（見 Task 7），需要額外等待，與「載入指示器消失」是
/// 兩個獨立的時間點（見 spec.md「執行緒與快取」：開書當下畫面已可互動，
/// 計算結果延後才顯示）。
Future<void> _pumpUntilFooterVisible(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (find.byKey(const Key('reader_footer')).evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：頁尾未出現（全書字元數計算未完成）');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('EPUB 開書後畫面立即可互動（不卡頓），背景計算完成後頁尾顯示估算頁碼；第二次開啟同一本書直接讀取快取',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
      EpubCharacterCountRepository(libraryRepository.database),
    );

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_long_vertical.epub', 'epub_pagination_integration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    // 【審查修正】EpubCharacterCountRepository.save() 是 partial UPDATE，
    // 若 books 表尚無對應書籍列，UPDATE 影響 0 列、靜默無效果——背景計算
    // 完成回報 onCharacterCountReady 時若書籍尚未存在於資料庫，快取會
    // 悄悄遺失。真機測試須先插入書籍列，比照 reading_position_test.dart
    // 既有先例。
    await libraryRepository.insertBook(Book(
      id: 'b_epub_pagination',
      title: 'EPUB 分頁估算測試書 1',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    // 第一次開書：驗證載入指示器很快消失（開書當下即可互動，不等背景計算）。
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

    // 背景計算完成後頁尾才出現，驗證估算總頁數為正整數。
    await _pumpUntilFooterVisible(tester);
    final progressTextFinder = find.byKey(const Key('reader_footer_progress_text'));
    expect(progressTextFinder, findsOneWidget);
    final progressText =
        (tester.widget<Text>(progressTextFinder)).data ?? '';
    expect(progressText, matches(RegExp(r'第 \d+/\d+ 頁')),
        reason: '頁尾應顯示「第 N/M 頁」格式的估算頁碼');

    // 離開畫面，驗證 totalCharacterCount 已快取進資料庫。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle(); // 給非同步的 saveTotalCharacterCount 寫入時間
    final cached = await EpubCharacterCountRepository(libraryRepository.database)
        .load('b_epub_pagination');
    expect(cached, isNotNull, reason: '離開後全書字元數應已快取至資料庫');

    // 第二次開啟同一本書：頁尾應能較快出現（直接讀取快取，不重新計算），
    // 沿用較短的逾時視窗做粗略驗證。
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
    expect(find.byKey(const Key('reader_footer')), findsOneWidget,
        reason: '有快取值時頁尾應與載入指示器消失同時出現，不需再等待背景計算');
  });

  testWidgets('EPUB 頁尾輸入框跳頁後，畫面確實跳轉到目標頁附近', (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
      EpubCharacterCountRepository(libraryRepository.database),
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
    await _pumpUntilFooterVisible(tester);

    final totalPagesText =
        (tester.widget<Text>(find.byKey(const Key('reader_footer_progress_text')))).data ?? '';
    final match = RegExp(r'第 \d+/(\d+) 頁').firstMatch(totalPagesText);
    expect(match, isNotNull);
    final totalPages = int.parse(match!.group(1)!);
    final targetPage = (totalPages / 2).ceil().clamp(1, totalPages);

    await tester.enterText(
        find.byKey(const Key('reader_footer_jump_input')), '$targetPage');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 【審查修正】ReaderFooter 實際輸出格式為「進度 xx% ｜ 第 N/M 頁」，
    // 計畫原文的 find.text('第 N/M 頁') 精確比對缺少百分比前綴，一律找不到
    // 對應 widget 而斷言失敗；改為讀取 reader_footer_progress_text 的文字
    // 內容再用 contains 判斷，同時保留原本「頁尾應更新為目標頁」的驗證
    // 意圖。
    final progressTextFinder = find.byKey(const Key('reader_footer_progress_text'));
    expect(progressTextFinder, findsOneWidget);
    final progressText = (tester.widget<Text>(progressTextFinder)).data ?? '';
    expect(progressText, contains('第 $targetPage/$totalPages 頁'),
        reason: '輸入框跳頁後頁尾應更新為目標頁');
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
}
