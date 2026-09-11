// app/test/search/search_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/search/cjk_tokenizer.dart';
import 'package:elinkbook/search/search_repository.dart';

Book _book(
  String id, {
  String title = '測試書',
  String? author,
  DateTime? lastReadTime,
}) {
  return Book(
    id: id,
    title: title,
    author: author,
    format: BookFileFormat.epub,
    filePath: '/books/$id',
    source: BookSource.local,
    createTime: DateTime(2026, 1, 1),
    lastReadTime: lastReadTime ?? DateTime(2026, 1, 1),
  );
}

void main() {
  late SqliteLibraryRepository repository;
  late SqliteSearchRepository searchRepository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    searchRepository = SqliteSearchRepository(database: repository.database);
  });

  tearDown(() async {
    await repository.close();
  });

  Future<void> insertContentRow(
    String bookId,
    String rawText, {
    int chapterIndex = 0,
    String locator = 'epubcfi(/6/2)',
  }) async {
    await repository.database.insert('book_content_index', {
      'id': const Uuid().v4(),
      'book_id': bookId,
      'chapter_index': chapterIndex,
      'locator': locator,
      'raw_text': rawText,
      'token_text': tokenizeForIndex(rawText),
      'created_at': 1000,
    });
  }

  group('searchTitleAuthor', () {
    test('空字串（或僅空白）回傳空陣列，不下 SQL 查詢', () async {
      final results = await searchRepository.searchTitleAuthor('   ');
      expect(results, isEmpty);
    });

    test('比對書名或作者（不分大小寫），依 lastReadTime 新到舊排序', () async {
      await repository.insertBook(
        _book('b1', title: '龍族', lastReadTime: DateTime(2026, 1, 1)),
      );
      await repository.insertBook(
        _book(
          'b2',
          title: 'Dune',
          author: 'Frank Herbert',
          lastReadTime: DateTime(2026, 3, 1),
        ),
      );
      await repository.insertBook(
        _book(
          'b3',
          title: '三體',
          author: '劉慈欣',
          lastReadTime: DateTime(2026, 2, 1),
        ),
      );

      final byTitle = await searchRepository.searchTitleAuthor('dune');
      expect(byTitle.map((b) => b.id).toList(), ['b2']);

      final byAuthor = await searchRepository.searchTitleAuthor('劉慈欣');
      expect(byAuthor.map((b) => b.id).toList(), ['b3']);
    });

    test('查詢字串含 % 或 _ 時視為一般字元比對，不當作 LIKE 萬用字元（review-plan-issue-4.md M-3）',
        () async {
      await repository.insertBook(_book('b1', title: '完全不相關的書名'));
      await repository.insertBook(_book('b2', title: '100%達成'));

      final results = await searchRepository.searchTitleAuthor('100%');

      expect(results.map((b) => b.id).toList(), ['b2']);
    });
  });

  group('searchContent', () {
    test('空字串（token 化後為空）回傳空陣列，不下 MATCH 查詢', () async {
      final results = await searchRepository.searchContent('   ');
      expect(results, isEmpty);
    });

    test('依 book_id 分組，每本書最多回傳 perBookLimit 筆，未命中的書不出現在結果中', () async {
      await repository.insertBook(_book('b1', title: '書一'));
      await repository.insertBook(_book('b2', title: '書二'));
      await insertContentRow('b1', '第一段落含關鍵詞測試');
      await insertContentRow('b1', '第二段落也含關鍵詞測試');
      await insertContentRow('b1', '第三段落一樣含關鍵詞測試');
      await insertContentRow('b1', '第四段落又出現關鍵詞測試');
      await insertContentRow('b2', '完全不相關的內容');

      final results = await searchRepository.searchContent(
        '關鍵詞測試',
        perBookLimit: 3,
      );

      expect(results, hasLength(1));
      expect(results.single.book.id, 'b1');
      expect(results.single.matches, hasLength(3));
    });

    test('顯示片段回傳原始文字（未逐字加空白，token_text 只用於索引比對）', () async {
      await repository.insertBook(_book('b1'));
      await insertContentRow('b1', '這是一句包含搜尋關鍵字的句子');

      final results = await searchRepository.searchContent('搜尋關鍵字');

      expect(results.single.matches.single.snippet, '這是一句包含搜尋關鍵字的句子');
      expect(results.single.matches.single.locator, 'epubcfi(/6/2)');
    });

    test('查無命中時回傳空陣列', () async {
      await repository.insertBook(_book('b1'));
      await insertContentRow('b1', '完全不相關的內容');

      final results = await searchRepository.searchContent('不存在的詞彙');

      expect(results, isEmpty);
    });

    test(
        '長文本（超過 80 rune）時，顯示片段以關鍵字為中心截斷，前後皆有內容時兩端皆加上刪節號'
        '（reviews/review-issue-4.md Minor 3，補齊 I-4 修正的測試覆蓋）', () async {
      await repository.insertBook(_book('b1'));
      const keyword = '關鍵詞彙';
      // 前綴 40 字 + 關鍵字 4 字 + 後綴 66 字 = 110 字，確保視窗（寬度 80，
      // 關鍵字前保留 20 字）前後都還有被截斷掉的內容，兩端都應出現刪節號
      // （見 search_repository.dart _truncate() 的視窗計算）。
      final prefix = List.filled(40, '填').join();
      final suffix = List.filled(66, '填').join();
      final rawText = '$prefix$keyword$suffix';
      expect(rawText.length, 110);
      await insertContentRow('b1', rawText);

      final results = await searchRepository.searchContent(keyword);

      final snippet = results.single.matches.single.snippet;
      expect(
        snippet,
        contains(keyword),
        reason: '截斷視窗必須包含使用者輸入的關鍵字，不可截斷到看不見搜尋詞（I-4 原始問題）',
      );
      expect(snippet, startsWith('…'), reason: '關鍵字前方仍有被截斷的內容，應加上刪節號');
      expect(snippet, endsWith('…'), reason: '關鍵字後方仍有被截斷的內容，應加上刪節號');
      expect(
        snippet.length,
        82,
        reason: '視窗寬度固定 80 個字元，前後各加一個刪節號，總長 82',
      );
    });
  });
}
