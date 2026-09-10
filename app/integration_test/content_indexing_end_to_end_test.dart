// app/integration_test/content_indexing_end_to_end_test.dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/reader_activity_tracker.dart';
import 'package:elinkbook/search/content_indexing_scheduler.dart';
import 'package:elinkbook/search/foliate_content_indexer.dart';
import 'package:elinkbook/search/pdf_content_indexer.dart';
import 'package:pdfrx/pdfrx.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _waitUntilStatus(
  Database db,
  String bookId,
  String expectedStatus, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final rows = await db.query('content_index_status',
        where: 'book_id = ?', whereArgs: [bookId]);
    final status = rows.isNotEmpty ? rows.single['status'] as String? : null;
    if (status == expectedStatus) return;
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：$bookId 狀態仍是 $status，預期 $expectedStatus');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'PDF 與 EPUB fixture 各自從 pending 背景索引完成轉為 done，且 book_content_fts 可查到已知內容',
      (tester) async {
    await pdfrxFlutterInitialize();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => repository.close());
    final db = repository.database;

    final pdfPath =
        await _stageAssetAsFile('test/fixtures/sample_multi_page.pdf', 'e2e.pdf');
    final epubPath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub', 'e2e.epub');
    addTearDown(() async {
      for (final path in [pdfPath, epubPath]) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    });

    final pdfBook = Book(
      id: 'e2e-pdf-book',
      title: '端到端測試 PDF',
      format: BookFileFormat.pdf,
      filePath: pdfPath,
      source: BookSource.local,
      createTime: DateTime(2026, 1, 1),
      lastReadTime: DateTime(2026, 1, 1),
    );
    final epubBook = Book(
      id: 'e2e-epub-book',
      title: '端到端測試 EPUB',
      format: BookFileFormat.epub,
      filePath: epubPath,
      source: BookSource.local,
      createTime: DateTime(2026, 1, 1),
      lastReadTime: DateTime(2026, 1, 1),
    );

    await repository.insertBook(pdfBook);
    await repository.insertBook(epubBook);
    for (final bookId in [pdfBook.id, epubBook.id]) {
      await db.insert('content_index_status', {
        'book_id': bookId,
        'status': 'pending',
        'last_chapter_index': null,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    }

    final tracker = ReaderActivityTracker();
    final scheduler = ContentIndexingScheduler(
      database: db,
      activityTracker: tracker,
      pdfIndexer: const PdfContentIndexer(),
      foliateIndexer: const FoliateContentIndexer(),
    );
    addTearDown(() => scheduler.dispose());
    scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    await _waitUntilStatus(db, pdfBook.id, 'done');
    await _waitUntilStatus(db, epubBook.id, 'done');

    // PDF：已知內容含 "Page" 字樣（見 pdf_reader_view_search_test.dart）。
    final pdfMatches = await db.rawQuery(
      'SELECT bci.locator, bci.raw_text FROM book_content_fts '
      'JOIN book_content_index bci ON bci.rowid = book_content_fts.rowid '
      "WHERE bci.book_id = ? AND book_content_fts MATCH 'Page'",
      [pdfBook.id],
    );
    expect(pdfMatches, isNotEmpty);
    final pdfLocator = pdfMatches.first['locator'] as String;
    expect(pdfLocator, contains('"page"'));

    // EPUB：已知內容含中文「第一章」（tokenizeForQuery 需求逐字空白分隔，
    // 這裡直接用已知已經過 tokenizeForIndex() 轉換的形式查詢，等效於
    // SearchRepository.searchContent() 未來會做的轉換，Issue 1 尚未交付
    // 該 repository，故此處直接組出 MATCH 用字串）。
    final epubMatches = await db.rawQuery(
      'SELECT bci.locator, bci.raw_text FROM book_content_fts '
      'JOIN book_content_index bci ON bci.rowid = book_content_fts.rowid '
      "WHERE bci.book_id = ? AND book_content_fts MATCH '\"第 一 章\"'",
      [epubBook.id],
    );
    expect(epubMatches, isNotEmpty);
    final epubLocator = epubMatches.first['locator'] as String;
    expect(epubLocator, startsWith('epubcfi('));
  });
}
