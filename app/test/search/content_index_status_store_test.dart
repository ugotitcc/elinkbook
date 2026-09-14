// app/test/search/content_index_status_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/search/content_index_status_store.dart';

Book _book(
  String id, {
  BookFileFormat format = BookFileFormat.epub,
  bool isDownloaded = true,
}) {
  return Book(
    id: id,
    title: '測試書 $id',
    format: format,
    filePath: '/books/$id',
    source: BookSource.local,
    createTime: DateTime(2026, 1, 1),
    lastReadTime: DateTime(2026, 1, 1),
    isDownloaded: isDownloaded,
  );
}

void main() {
  late SqliteLibraryRepository libraryRepository;
  late Database db;
  late ContentIndexStatusStore store;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    db = libraryRepository.database;
    store = ContentIndexStatusStore(db);
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  Future<Map<String, Object?>?> statusOf(String bookId) async {
    final rows = await db.query('content_index_status',
        where: 'book_id = ?', whereArgs: [bookId]);
    return rows.isEmpty ? null : rows.single;
  }

  Future<List<Map<String, Object?>>> contentRowsOf(String bookId) async {
    return db.query('book_content_index',
        where: 'book_id = ?', whereArgs: [bookId]);
  }

  Future<void> insertContentRow(String bookId, int chapterIndex) async {
    await db.insert('book_content_index', {
      'id': '$bookId-$chapterIndex',
      'book_id': bookId,
      'chapter_index': chapterIndex,
      'locator': 'epubcfi(/6/4!/4/$chapterIndex)',
      'raw_text': '第 $chapterIndex 章內容',
      'token_text': '第 $chapterIndex 章 內 容',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  group('markPending', () {
    test('尚無資料列時插入 pending', () async {
      await libraryRepository.insertBook(_book('b1'));

      await store.markPending('b1');

      final status = await statusOf('b1');
      expect(status, isNotNull);
      expect(status!['status'], 'pending');
    });

    test('已有資料列時不覆蓋既有 status（ConflictAlgorithm.ignore）', () async {
      await libraryRepository.insertBook(_book('b1'));
      await store.markPending('b1');
      await store.markDone('b1');

      await store.markPending('b1');

      final status = await statusOf('b1');
      expect(status!['status'], 'done');
    });
  });

  group('markIndexing', () {
    test('轉態為 indexing，不動 last_chapter_index', () async {
      await libraryRepository.insertBook(_book('b1'));
      await db.insert('content_index_status', {
        'book_id': 'b1',
        'status': 'pending',
        'last_chapter_index': 3,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await store.markIndexing('b1');

      final status = await statusOf('b1');
      expect(status!['status'], 'indexing');
      expect(status['last_chapter_index'], 3);
    });
  });

  group('updateProgress', () {
    test('更新 last_chapter_index，不改變 status', () async {
      await libraryRepository.insertBook(_book('b1'));
      await store.markPending('b1');
      await store.markIndexing('b1');

      await store.updateProgress('b1', 5);

      final status = await statusOf('b1');
      expect(status!['status'], 'indexing');
      expect(status['last_chapter_index'], 5);
    });
  });

  group('markDone', () {
    test('轉態為 done', () async {
      await libraryRepository.insertBook(_book('b1'));
      await store.markPending('b1');

      await store.markDone('b1');

      expect((await statusOf('b1'))!['status'], 'done');
    });
  });

  group('markError', () {
    test('轉態為 error 並記錄 error_message', () async {
      await libraryRepository.insertBook(_book('b1'));
      await store.markPending('b1');

      await store.markError('b1', error: 'boom');

      final status = await statusOf('b1');
      expect(status!['status'], 'error');
      expect(status['error_message'], 'boom');
    });
  });

  group('markUnsupported', () {
    test('尚無資料列時插入 unsupported', () async {
      await libraryRepository
          .insertBook(_book('b1', format: BookFileFormat.cbz));

      await store.markUnsupported('b1');

      expect((await statusOf('b1'))!['status'], 'unsupported');
    });

    test('已有資料列時不覆蓋', () async {
      await libraryRepository
          .insertBook(_book('b1', format: BookFileFormat.cbz));
      await store.markPending('b1');

      await store.markUnsupported('b1');

      expect((await statusOf('b1'))!['status'], 'pending');
    });
  });

  group('isTracked', () {
    test('資料列存在時回傳 true，不存在時回傳 false', () async {
      await libraryRepository.insertBook(_book('b1'));
      await libraryRepository.insertBook(_book('b2'));
      await store.markPending('b1');

      expect(await store.isTracked('b1'), isTrue);
      expect(await store.isTracked('b2'), isFalse);
    });
  });

  group('deleteForBook', () {
    test('同一交易內刪除 book_content_index 與 content_index_status 兩張表',
        () async {
      await libraryRepository.insertBook(_book('b1'));
      await store.markPending('b1');
      await insertContentRow('b1', 0);
      await insertContentRow('b1', 1);

      await store.deleteForBook('b1');

      expect(await statusOf('b1'), isNull);
      expect(await contentRowsOf('b1'), isEmpty);
    });

    test('兩張表皆已無資料列時呼叫仍安全（冪等，不拋例外）', () async {
      await libraryRepository.insertBook(_book('b1'));

      await store.deleteForBook('b1');

      expect(await statusOf('b1'), isNull);
    });
  });

  group('backfillPending', () {
    test('只回填「格式符合分類且已下載」且尚無資料列的書籍', () async {
      await libraryRepository
          .insertBook(_book('pdf-1', format: BookFileFormat.pdf));
      await libraryRepository.insertBook(_book('epub-1'));
      await libraryRepository.insertBook(_book(
        'pdf-not-downloaded',
        format: BookFileFormat.pdf,
        isDownloaded: false,
      ));

      await store.backfillPending(ContentIndexCategory.pdf);

      expect((await statusOf('pdf-1'))!['status'], 'pending');
      expect(await statusOf('epub-1'), isNull);
      expect(await statusOf('pdf-not-downloaded'), isNull);
    });

    test('foliate 分類額外把已下載的 cbz 書籍標記為 unsupported', () async {
      await libraryRepository.insertBook(_book('epub-1'));
      await libraryRepository
          .insertBook(_book('cbz-1', format: BookFileFormat.cbz));

      await store.backfillPending(ContentIndexCategory.foliate);

      expect((await statusOf('epub-1'))!['status'], 'pending');
      expect((await statusOf('cbz-1'))!['status'], 'unsupported');
    });

    test('已有資料列的書籍一律跳過，不覆蓋既有 status', () async {
      await libraryRepository.insertBook(_book('epub-1'));
      await store.markPending('epub-1');
      await store.markDone('epub-1');

      await store.backfillPending(ContentIndexCategory.foliate);

      expect((await statusOf('epub-1'))!['status'], 'done');
    });
  });

  group('clearByCategory', () {
    test('pdf 分類：刪除該分類格式書籍的索引資料，不影響另一分類', () async {
      await libraryRepository
          .insertBook(_book('pdf-1', format: BookFileFormat.pdf));
      await libraryRepository.insertBook(_book('epub-1'));
      await store.markPending('pdf-1');
      await store.markPending('epub-1');
      await insertContentRow('pdf-1', 0);
      await insertContentRow('epub-1', 0);

      await store.clearByCategory(ContentIndexCategory.pdf);

      expect(await statusOf('pdf-1'), isNull);
      expect(await contentRowsOf('pdf-1'), isEmpty);
      expect((await statusOf('epub-1'))!['status'], 'pending');
      expect(await contentRowsOf('epub-1'), isNotEmpty);
    });

    test('foliate 分類：刪除該分類格式書籍的索引資料，不影響 pdf 分類與 cbz',
        () async {
      await libraryRepository
          .insertBook(_book('pdf-1', format: BookFileFormat.pdf));
      await libraryRepository.insertBook(_book('epub-1'));
      await libraryRepository
          .insertBook(_book('cbz-1', format: BookFileFormat.cbz));
      await store.markPending('pdf-1');
      await store.markPending('epub-1');
      await store.markUnsupported('cbz-1');
      await insertContentRow('pdf-1', 0);
      await insertContentRow('epub-1', 0);

      await store.clearByCategory(ContentIndexCategory.foliate);

      expect(await statusOf('epub-1'), isNull);
      expect(await contentRowsOf('epub-1'), isEmpty);
      expect((await statusOf('pdf-1'))!['status'], 'pending');
      expect(await contentRowsOf('pdf-1'), isNotEmpty);
      // 【審查修正 I-2】驗證 `format != 'pdf' AND format != 'cbz'` 篩選
      // 確實排除 CBZ——foliate 分類的清除不該波及 CBZ 既有的 unsupported 列。
      expect((await statusOf('cbz-1'))!['status'], 'unsupported');
    });
  });
}
