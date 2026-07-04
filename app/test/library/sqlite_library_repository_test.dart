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
}
