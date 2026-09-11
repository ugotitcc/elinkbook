// app/test/search/full_text_search_settings_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/search/full_text_search_settings_repository.dart';

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
  late int requestProcessingCallCount;
  late SqliteFullTextSearchSettingsRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    db = libraryRepository.database;
    requestProcessingCallCount = 0;
    repository = SqliteFullTextSearchSettingsRepository(
      database: db,
      requestProcessing: () => requestProcessingCallCount++,
    );
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  Future<Map<String, Object?>?> statusOf(String bookId) async {
    final rows = await db.query('content_index_status',
        where: 'book_id = ?', whereArgs: [bookId]);
    return rows.isEmpty ? null : rows.single;
  }

  group('epic-10-search Issue 3：FullTextSearchSettingsRepository', () {
    test('isEnabled 兩個分類初始值皆為 false', () async {
      expect(await repository.isEnabled(ContentIndexCategory.pdf), isFalse);
      expect(
          await repository.isEnabled(ContentIndexCategory.foliate), isFalse);
    });

    test('setEnabled(pdf, true) 後 isEnabled(pdf) 為 true，foliate 不受影響',
        () async {
      await repository.setEnabled(ContentIndexCategory.pdf, true);

      expect(await repository.isEnabled(ContentIndexCategory.pdf), isTrue);
      expect(
          await repository.isEnabled(ContentIndexCategory.foliate), isFalse);
    });

    test('setEnabled(pdf, true) 只回填「pdf 格式且已下載」且尚無資料列的書籍',
        () async {
      await libraryRepository
          .insertBook(_book('pdf-1', format: BookFileFormat.pdf));
      await libraryRepository.insertBook(_book('epub-1'));
      await libraryRepository.insertBook(_book(
        'pdf-not-downloaded',
        format: BookFileFormat.pdf,
        isDownloaded: false,
      ));

      await repository.setEnabled(ContentIndexCategory.pdf, true);

      final pdfStatus = await statusOf('pdf-1');
      expect(pdfStatus, isNotNull);
      expect(pdfStatus!['status'], 'pending');
      expect(await statusOf('epub-1'), isNull);
      expect(await statusOf('pdf-not-downloaded'), isNull);
    });

    test(
        'setEnabled(foliate, true) 回填多種格式（epub/txt/azw3/md）並排除 pdf'
        '（review-plan-issue-3.md M-3）', () async {
      await libraryRepository.insertBook(_book('epub-1'));
      await libraryRepository
          .insertBook(_book('txt-1', format: BookFileFormat.txt));
      await libraryRepository
          .insertBook(_book('azw3-1', format: BookFileFormat.azw3));
      await libraryRepository
          .insertBook(_book('md-1', format: BookFileFormat.md));
      await libraryRepository
          .insertBook(_book('pdf-1', format: BookFileFormat.pdf));

      await repository.setEnabled(ContentIndexCategory.foliate, true);

      for (final id in ['epub-1', 'txt-1', 'azw3-1', 'md-1']) {
        final status = await statusOf(id);
        expect(status, isNotNull, reason: '$id 應被回填為 pending');
        expect(status!['status'], 'pending');
      }
      expect(await statusOf('pdf-1'), isNull);
    });

    test(
        'setEnabled(foliate, true) 把既有未追蹤的 cbz 書籍標記為 unsupported，'
        '不進入 pending 佇列（review-plan-issue-3.md I-2）', () async {
      await libraryRepository
          .insertBook(_book('cbz-1', format: BookFileFormat.cbz));

      await repository.setEnabled(ContentIndexCategory.foliate, true);

      final status = await statusOf('cbz-1');
      expect(status, isNotNull);
      expect(status!['status'], 'unsupported');
    });

    test('setEnabled(category, true) 不覆蓋已存在的 content_index_status 列',
        () async {
      await libraryRepository
          .insertBook(_book('pdf-done', format: BookFileFormat.pdf));
      await db.insert('content_index_status', {
        'book_id': 'pdf-done',
        'status': 'done',
        'updated_at': 1000,
      });

      await repository.setEnabled(ContentIndexCategory.pdf, true);

      final status = await statusOf('pdf-done');
      expect(status!['status'], 'done');
    });

    test('setEnabled(category, true) 呼叫 requestProcessing 喚醒排程器', () async {
      await libraryRepository
          .insertBook(_book('pdf-1', format: BookFileFormat.pdf));

      await repository.setEnabled(ContentIndexCategory.pdf, true);

      expect(requestProcessingCallCount, 1);
    });

    test('setEnabled(category, false) 不呼叫 requestProcessing', () async {
      await repository.setEnabled(ContentIndexCategory.pdf, false);

      expect(requestProcessingCallCount, 0);
    });

    test('setEnabled(pdf, false) 清除 pdf 格式索引資料，不影響 foliate 格式既有索引',
        () async {
      await libraryRepository
          .insertBook(_book('pdf-1', format: BookFileFormat.pdf));
      await libraryRepository.insertBook(_book('epub-1'));
      await db.insert('content_index_status',
          {'book_id': 'pdf-1', 'status': 'done', 'updated_at': 1000});
      await db.insert('content_index_status',
          {'book_id': 'epub-1', 'status': 'done', 'updated_at': 1000});
      await db.insert('book_content_index', {
        'id': 'seg-pdf-1',
        'book_id': 'pdf-1',
        'chapter_index': 0,
        'locator': '{"page":0}',
        'raw_text': 'PDF 內容',
        'token_text': 'PDF 內容',
        'created_at': 1000,
      });
      await db.insert('book_content_index', {
        'id': 'seg-epub-1',
        'book_id': 'epub-1',
        'chapter_index': 0,
        'locator': 'epubcfi(/6/2)',
        'raw_text': 'EPUB 內容',
        'token_text': 'EPUB 內容',
        'created_at': 1000,
      });

      await repository.setEnabled(ContentIndexCategory.pdf, false);

      expect(await statusOf('pdf-1'), isNull);
      expect(await statusOf('epub-1'), isNotNull);
      final pdfIndexRows = await db.query('book_content_index',
          where: 'book_id = ?', whereArgs: ['pdf-1']);
      expect(pdfIndexRows, isEmpty);
      final epubIndexRows = await db.query('book_content_index',
          where: 'book_id = ?', whereArgs: ['epub-1']);
      expect(epubIndexRows, hasLength(1));
      final ftsRows = await db.rawQuery(
          "SELECT rowid FROM book_content_fts WHERE book_content_fts MATCH 'PDF'");
      expect(ftsRows, isEmpty, reason: 'FTS5 trigger 應同步清空已刪除的 pdf 索引列');
    });

    test(
        'setEnabled(foliate, false) 清除 foliate 格式索引資料，不影響 pdf 格式既有索引'
        '（review-plan-issue-3.md M-3）', () async {
      await libraryRepository.insertBook(_book('epub-1'));
      await libraryRepository
          .insertBook(_book('pdf-1', format: BookFileFormat.pdf));
      await db.insert('content_index_status',
          {'book_id': 'epub-1', 'status': 'done', 'updated_at': 1000});
      await db.insert('content_index_status',
          {'book_id': 'pdf-1', 'status': 'done', 'updated_at': 1000});
      await db.insert('book_content_index', {
        'id': 'seg-epub-1',
        'book_id': 'epub-1',
        'chapter_index': 0,
        'locator': 'epubcfi(/6/2)',
        'raw_text': 'EPUB 內容',
        'token_text': 'EPUB 內容',
        'created_at': 1000,
      });

      await repository.setEnabled(ContentIndexCategory.foliate, false);

      expect(await statusOf('epub-1'), isNull);
      expect(await statusOf('pdf-1'), isNotNull);
    });

    test(
        'rebuildIndex(category) 清除既有索引後重新回填 pending 並喚醒排程器',
        () async {
      await libraryRepository
          .insertBook(_book('pdf-1', format: BookFileFormat.pdf));
      await db.insert('content_index_status',
          {'book_id': 'pdf-1', 'status': 'done', 'updated_at': 1000});
      await db.insert('book_content_index', {
        'id': 'seg-pdf-1',
        'book_id': 'pdf-1',
        'chapter_index': 0,
        'locator': '{"page":0}',
        'raw_text': '舊內容',
        'token_text': '舊內容',
        'created_at': 1000,
      });

      await repository.rebuildIndex(ContentIndexCategory.pdf);

      final status = await statusOf('pdf-1');
      expect(status, isNotNull);
      expect(status!['status'], 'pending');
      final indexRows = await db.query('book_content_index',
          where: 'book_id = ?', whereArgs: ['pdf-1']);
      expect(indexRows, isEmpty, reason: '重建索引應先清除舊的索引明細');
      expect(requestProcessingCallCount, 1);
    });
  });
}
