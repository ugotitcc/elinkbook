// app/test/search/content_indexing_scheduler_test.dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/reader_activity_tracker.dart';
import 'package:elinkbook/search/content_indexer.dart';
import 'package:elinkbook/search/content_indexing_scheduler.dart';

/// 測試用假索引器：由測試逐一 `add()` segment 到 [_controller]，讓測試能
/// 精確控制「排程器在處理到哪個章節時，外部條件（App 背景化/開閱讀畫面）
/// 發生變化」，不需要真正的 PDF/WebView I/O。
class _FakeContentIndexer implements ContentIndexer {
  final _controller = StreamController<IndexedSegment>();
  int? lastResumeFromChapter;

  /// 【審查修正】`lastResumeFromChapter` 預設值本來就是 null，若
  /// `resumeFromChapter` 傳入剛好也是 null，單看 `lastResumeFromChapter`
  /// 無法區分「indexBook() 從未被呼叫」與「indexBook(resumeFromChapter:
  /// null) 確實被呼叫過」——用獨立布林旗標明確記錄「是否真的被呼叫過」，
  /// 避免測試在排程器根本沒有分派時也誤判通過。
  bool wasCalled = false;

  /// 【I-3 測試用】記錄最後一次 indexBook() 收到的 [Book]——同一個假索引器
  /// 實例可能先後服務多本同格式的書，單看 `wasCalled` 無法分辨「被呼叫過」
  /// 與「被呼叫時傳入的是哪一本書」，佇列排序測試需要後者才能斷言正確性。
  Book? lastBook;

  void addSegment(IndexedSegment segment) => _controller.add(segment);
  Future<void> finish() => _controller.close();

  @override
  Stream<IndexedSegment> indexBook(Book book, {int? resumeFromChapter}) {
    wasCalled = true;
    lastBook = book;
    lastResumeFromChapter = resumeFromChapter;
    return _controller.stream;
  }
}

Book _book(String id, {BookFileFormat format = BookFileFormat.epub}) {
  return Book(
    id: id,
    title: '測試書 $id',
    format: format,
    filePath: '/books/$id',
    source: BookSource.local,
    createTime: DateTime(2026, 1, 1),
    lastReadTime: DateTime(2026, 1, 1),
  );
}

void main() {
  late SqliteLibraryRepository repository;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    db = repository.database;
  });

  tearDown(() async {
    // 等待排程器可能仍在進行的 DB 寫入完成，避免 database_closed 競態
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await repository.close();
  });

  Future<void> insertPendingBook(Book book, {int? lastChapterIndex}) async {
    await repository.insertBook(book);
    await db.insert('content_index_status', {
      'book_id': book.id,
      'status': 'pending',
      'last_chapter_index': lastChapterIndex,
      'updated_at': 1000,
    });
  }

  Future<Map<String, Object?>> statusOf(String bookId) async {
    final rows = await db.query('content_index_status',
        where: 'book_id = ?', whereArgs: [bookId]);
    return rows.single;
  }

  group('ContentIndexingScheduler', () {
    test('App 前台且無閱讀畫面開啟時，處理完一本書後狀態轉為 done', () async {
      final tracker = ReaderActivityTracker();
      final pdfIndexer = _FakeContentIndexer();
      final foliateIndexer = _FakeContentIndexer();
      final book = _book('book-1');
      await insertPendingBook(book);

      final scheduler = ContentIndexingScheduler(
        database: db,
        activityTracker: tracker,
        pdfIndexer: pdfIndexer,
        foliateIndexer: foliateIndexer,
      );
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      foliateIndexer.addSegment(const IndexedSegment(
          chapterIndex: 0, locator: 'epubcfi(/6/2)', rawText: '第一段'));
      foliateIndexer.addSegment(const IndexedSegment(
          chapterIndex: 0, locator: 'epubcfi(/6/4)', rawText: '第二段'));
      await foliateIndexer.finish();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final status = await statusOf('book-1');
      expect(status['status'], 'done');

      final indexRows = await db.query('book_content_index',
          where: 'book_id = ?', whereArgs: ['book-1']);
      expect(indexRows, hasLength(2));
      expect(indexRows.map((r) => r['token_text']), everyElement(isNotEmpty));

      final ftsRows = await db.rawQuery(
          "SELECT rowid FROM book_content_fts WHERE book_content_fts MATCH '第 一'");
      expect(ftsRows, isNotEmpty, reason: '寫入應觸發 Issue 0 的 FTS5 同步 trigger');
    });

    test('PDF 格式書籍分派給 pdfIndexer，非 PDF 分派給 foliateIndexer', () async {
      final tracker = ReaderActivityTracker();
      final pdfIndexer = _FakeContentIndexer();
      final foliateIndexer = _FakeContentIndexer();
      await insertPendingBook(_book('pdf-book', format: BookFileFormat.pdf));

      final scheduler = ContentIndexingScheduler(
        database: db,
        activityTracker: tracker,
        pdfIndexer: pdfIndexer,
        foliateIndexer: foliateIndexer,
      );
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(pdfIndexer.wasCalled, isTrue,
          reason: 'PDF 格式書籍應分派給 pdfIndexer');
      expect(foliateIndexer.wasCalled, isFalse,
          reason: 'PDF 格式書籍不應分派給 foliateIndexer');
      await pdfIndexer.finish();
    });

    test('開啟閱讀畫面（ReaderActivityTracker）時，正在處理的書籍於下個章節邊界暫停，記錄游標',
        () async {
      final tracker = ReaderActivityTracker();
      final indexer = _FakeContentIndexer();
      await insertPendingBook(_book('book-2'));

      final scheduler = ContentIndexingScheduler(
        database: db,
        activityTracker: tracker,
        pdfIndexer: _FakeContentIndexer(),
        foliateIndexer: indexer,
      );
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // 完成第 0 章。
      indexer.addSegment(const IndexedSegment(
          chapterIndex: 0, locator: 'epubcfi(/6/2)', rawText: '第一章內容'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      // 開始送出第 1 章第一筆，觸發章節邊界檢查（此時尚未呼叫
      // markReaderOpened，應正常繼續處理進入第 1 章）。
      indexer.addSegment(const IndexedSegment(
          chapterIndex: 1, locator: 'epubcfi(/6/4)', rawText: '第二章第一段'));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // 使用者開啟閱讀畫面——排程器應在下一個章節邊界暫停。
      tracker.markReaderOpened();
      indexer.addSegment(const IndexedSegment(
          chapterIndex: 2, locator: 'epubcfi(/6/6)', rawText: '第三章第一段'));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final status = await statusOf('book-2');
      expect(status['status'], 'indexing',
          reason: '尚未處理完全書，應維持 indexing（非 done）');
      expect(status['last_chapter_index'], 1,
          reason: '第 1 章已完整寫入，游標應停在 1（第 2 章的資料被捨棄，未寫入）');

      final indexRows = await db.query('book_content_index',
          where: 'book_id = ?', whereArgs: ['book-2']);
      expect(indexRows.map((r) => r['chapter_index']).toSet(), {0, 1},
          reason: '第 2 章（chapterIndex=2）尚未完整走完章節邊界，不應寫入');
    });

    test('App 背景化後、回到前台時，從續跑游標繼續處理', () async {
      final tracker = ReaderActivityTracker();
      final firstRunIndexer = _FakeContentIndexer();
      await insertPendingBook(_book('book-3'), lastChapterIndex: 4);

      final scheduler = ContentIndexingScheduler(
        database: db,
        activityTracker: tracker,
        pdfIndexer: _FakeContentIndexer(),
        foliateIndexer: firstRunIndexer,
      );
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(firstRunIndexer.lastResumeFromChapter, 5,
          reason: '既有游標為 4（已完成），應從第 5 章開始續跑');
      await firstRunIndexer.finish();
    });

    test('App 背景化時，不會開始處理新的 pending 書籍', () async {
      final tracker = ReaderActivityTracker();
      final indexer = _FakeContentIndexer();
      await insertPendingBook(_book('book-4'));

      final scheduler = ContentIndexingScheduler(
        database: db,
        activityTracker: tracker,
        pdfIndexer: _FakeContentIndexer(),
        foliateIndexer: indexer,
      );
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final status = await statusOf('book-4');
      expect(status['status'], 'pending', reason: 'App 背景化時排程器不應開始處理');
    });

    test('【I-3】indexing 狀態書籍優先於 pending 書籍被選中，不因剛暫停而被擠到佇列尾端',
        () async {
      final tracker = ReaderActivityTracker();
      // book-a／book-b 皆為 epub 格式，共用同一個 foliateIndexer 實例
      // （見下方建構子），故只需要一個假索引器，用 lastBook.id 判斷究竟
      // 是哪一本書被選中（見 _FakeContentIndexer.lastBook 註解）。
      final indexerA = _FakeContentIndexer();
      // 書 A：早先已開始處理、中途暫停過（updated_at 較新，模擬剛暫停）。
      await insertPendingBook(_book('book-a'), lastChapterIndex: 1);
      await db.update('content_index_status', {'status': 'indexing', 'updated_at': 9999},
          where: 'book_id = ?', whereArgs: ['book-a']);
      // 書 B：全新匯入、從未處理過（insertPendingBook 預設 updated_at:
      // 1000，比書 A 剛被設定的 9999 舊）。
      await insertPendingBook(_book('book-b'));

      final scheduler = ContentIndexingScheduler(
        database: db,
        activityTracker: tracker,
        pdfIndexer: _FakeContentIndexer(),
        // book-a／book-b 皆為 epub 格式（_book() 預設值），共用同一個
        // foliateIndexer 實例——用 lastBook.id 而非 wasCalled 判斷究竟是
        // 哪一本書被選中，見 _FakeContentIndexer.lastBook 註解。
        foliateIndexer: indexerA,
      );
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(indexerA.wasCalled, isTrue);
      expect(indexerA.lastBook?.id, 'book-a',
          reason: 'updated_at 較新但 status=indexing 的書 A 應優先於 status=pending 的書 B 被選中');
      await indexerA.finish();
    });

    test('【I-4】requestProcessing() 可在排程器閒置時喚醒處理新插入的 pending 列', () async {
      final tracker = ReaderActivityTracker();
      final indexer = _FakeContentIndexer();

      final scheduler = ContentIndexingScheduler(
        database: db,
        activityTracker: tracker,
        pdfIndexer: _FakeContentIndexer(),
        foliateIndexer: indexer,
      );
      // 排程器啟動當下佇列是空的，_runLoop() 應立即結束、回到閒置狀態。
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(indexer.wasCalled, isFalse);

      // 模擬 Issue 2／3 批次插入一筆新的 pending 列後主動呼叫
      // requestProcessing()（App 生命週期與 ReaderActivityTracker 皆未
      // 變動，若沒有這個公開方法，排程器沒有任何訊號會知道有新工作）。
      await insertPendingBook(_book('book-5'));
      scheduler.requestProcessing();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(indexer.wasCalled, isTrue);
      await indexer.finish();
    });

    test('【M-2】dispose() 後，正在處理的書於下個章節邊界暫停（不會變成 done），也不會開始下一本書',
        () async {
      final tracker = ReaderActivityTracker();
      final indexer = _FakeContentIndexer();
      await insertPendingBook(_book('book-6'));
      await insertPendingBook(_book('book-7'));

      final scheduler = ContentIndexingScheduler(
        database: db,
        activityTracker: tracker,
        pdfIndexer: _FakeContentIndexer(),
        foliateIndexer: indexer,
      );
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(indexer.wasCalled, isTrue, reason: 'book-6 應已開始處理');

      // 完成第 0 章。
      indexer.addSegment(const IndexedSegment(
          chapterIndex: 0, locator: 'epubcfi(/6/2)', rawText: '第一段'));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      scheduler.dispose();
      // dispose() 後模擬 App 生命週期事件仍可能因既有訂閱殘留而觸發一次
      // （例如 removeObserver 之前已排入佇列的事件），驗證 _disposed 旗標
      // 確實阻擋繼續處理，而不是僅僅移除了 observer——handleAppLifecycleStateChanged()
      // 是測試可直接呼叫的公開方法，不經過真正的 WidgetsBindingObserver。
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      // 送出第 1 章第一筆，觸發章節邊界檢查——此時應偵測到 dispose() 已
      // 發生而暫停，不繼續處理，book-6 應停在「已完成第 0 章」狀態。
      indexer.addSegment(const IndexedSegment(
          chapterIndex: 1, locator: 'epubcfi(/6/4)', rawText: '第二段'));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final status6 = await statusOf('book-6');
      expect(status6['status'], 'indexing',
          reason: 'book-6 應在 dispose() 後的章節邊界暫停，不應變成 done');
      expect(status6['last_chapter_index'], 0);
      final status7 = await statusOf('book-7');
      expect(status7['status'], 'pending',
          reason: 'dispose() 後不應開始處理 book-7');
    });

    test(
        '處理中若 content_index_status 列被外部刪除（模擬「啟用全文檢索」開關關閉），'
        '中止處理並清除已寫入的殘留索引列（review-plan-issue-3.md C-1）', () async {
      final tracker = ReaderActivityTracker();
      final pdfIndexer = _FakeContentIndexer();
      final foliateIndexer = _FakeContentIndexer();
      final book = _book('book-1');
      await insertPendingBook(book);

      final scheduler = ContentIndexingScheduler(
        database: db,
        activityTracker: tracker,
        pdfIndexer: pdfIndexer,
        foliateIndexer: foliateIndexer,
      );
      scheduler.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // 章節 0 →章節 1 的邊界會觸發一次 flush，此時 content_index_status
      // 列仍存在，章節 0 應正常寫入 book_content_index。
      foliateIndexer.addSegment(const IndexedSegment(
          chapterIndex: 0, locator: 'epubcfi(/6/2)', rawText: '第一章'));
      foliateIndexer.addSegment(const IndexedSegment(
          chapterIndex: 1, locator: 'epubcfi(/6/4)', rawText: '第二章'));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final flushedRows = await db.query('book_content_index',
          where: 'book_id = ?', whereArgs: ['book-1']);
      expect(flushedRows, hasLength(1), reason: '章節 0 應已正常 flush');

      // 模擬「啟用全文檢索」開關關閉：外部直接刪除該書的
      // content_index_status 列（比照
      // SqliteFullTextSearchSettingsRepository._clearIndexData() 的實際
      // 行為，見 plans/plan-issue-3.md Task 2）。
      await db.delete('content_index_status',
          where: 'book_id = ?', whereArgs: ['book-1']);

      // 章節 1 →章節 2 的邊界應偵測到列已消失，中止處理，不再 flush 章節 1，
      // 且清除章節 0 先前已寫入的殘留列（不留下孤兒索引）。
      foliateIndexer.addSegment(const IndexedSegment(
          chapterIndex: 2, locator: 'epubcfi(/6/6)', rawText: '第三章'));
      await foliateIndexer.finish();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final indexRowsAfter = await db.query('book_content_index',
          where: 'book_id = ?', whereArgs: ['book-1']);
      expect(indexRowsAfter, isEmpty,
          reason: '分類關閉後應清除已寫入的殘留列，不留下孤兒索引');
    });
  });
}
