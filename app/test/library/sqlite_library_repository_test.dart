import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';

Book _book(
  String id, {
  String title = '書名',
  String? author,
  BookFileFormat format = BookFileFormat.epub,
  double progress = 0,
  String groupName = '未分類',
  int createTime = 1000,
  int lastReadTime = 1000,
}) {
  return Book(
    id: id,
    title: title,
    author: author,
    format: format,
    filePath: 'content://example/$id',
    source: BookSource.local,
    progress: progress,
    groupName: groupName,
    createTime: DateTime.fromMillisecondsSinceEpoch(createTime),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(lastReadTime),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqliteLibraryRepository repository;

  setUp(() async {
    repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
  });

  tearDown(() async {
    await repository.close();
  });

  test('insertBook 後可用 listBooks 取回', () async {
    await repository.insertBook(_book('b1', title: '紅樓夢'));

    final books = await repository.listBooks();

    expect(books, hasLength(1));
    expect(books.single.title, '紅樓夢');
  });

  test('updateBook 更新既有書籍的欄位', () async {
    await repository.insertBook(_book('b1', title: '舊書名'));

    await repository.updateBook(_book('b1', title: '新書名'));

    final books = await repository.listBooks();
    expect(books.single.title, '新書名');
  });

  test('deleteBook 移除指定書籍', () async {
    await repository.insertBook(_book('b1'));
    await repository.insertBook(_book('b2'));

    await repository.deleteBook('b1');

    final books = await repository.listBooks();
    expect(books.map((b) => b.id), ['b2']);
  });

  group('listBooks 排序', () {
    setUp(() async {
      await repository.insertBook(_book(
        'b1',
        title: '西遊記',
        author: '吳承恩',
        createTime: 3000,
        lastReadTime: 1000,
      ));
      await repository.insertBook(_book(
        'b2',
        title: '三國演義',
        author: '羅貫中',
        createTime: 1000,
        lastReadTime: 3000,
      ));
      await repository.insertBook(_book(
        'b3',
        title: '水滸傳',
        author: '施耐庵',
        createTime: 2000,
        lastReadTime: 2000,
      ));
    });

    test('lastRead：最近閱讀優先', () async {
      final books = await repository.listBooks(sortBy: LibrarySortBy.lastRead);
      expect(books.map((b) => b.id).toList(), ['b2', 'b3', 'b1']);
    });

    test('createTime：最近建立優先', () async {
      final books =
          await repository.listBooks(sortBy: LibrarySortBy.createTime);
      expect(books.map((b) => b.id).toList(), ['b1', 'b3', 'b2']);
    });

    test('author：依作者排序', () async {
      final books = await repository.listBooks(sortBy: LibrarySortBy.author);
      expect(books.map((b) => b.author).toList(), ['吳承恩', '施耐庵', '羅貫中']);
    });

    test('title：依書名排序', () async {
      final books = await repository.listBooks(sortBy: LibrarySortBy.title);
      expect(books.map((b) => b.title).toList(), ['三國演義', '水滸傳', '西遊記']);
    });
  });

  test('listBooks 依 groupFilter 篩選', () async {
    await repository.insertBook(_book('b1', groupName: '經典名著'));
    await repository.insertBook(_book('b2', groupName: '古典奇幻'));

    final books = await repository.listBooks(groupFilter: '經典名著');

    expect(books.map((b) => b.id).toList(), ['b1']);
  });

  test('listBooks 不指定 groupFilter 時回傳全部', () async {
    await repository.insertBook(_book('b1', groupName: '經典名著'));
    await repository.insertBook(_book('b2', groupName: '古典奇幻'));

    final books = await repository.listBooks();

    expect(books, hasLength(2));
  });
}
