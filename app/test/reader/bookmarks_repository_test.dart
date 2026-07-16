import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmarks_repository.dart';

Book _testBook(String id) {
  return Book(
    id: id,
    title: '測試書',
    format: BookFileFormat.epub,
    filePath: 'content://example/$id',
    source: BookSource.local,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

void main() {
  late SqliteLibraryRepository libraryRepository;
  late BookmarksRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    repository = BookmarksRepository(libraryRepository.database);
    await libraryRepository.insertBook(_testBook('b1'));
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  test('insert 回傳自動指派的 rowid，listByBook 讀回相同資料', () async {
    final id = await repository.insert(const Bookmark(
      bookId: 'b1',
      name: '第一章',
      epubLocatorJson: '{"href":"/c1.xhtml"}',
      progression: 0.1,
    ));
    expect(id, greaterThan(0));

    final list = await repository.listByBook('b1');
    expect(list, hasLength(1));
    expect(list.single.id, id);
    expect(list.single.name, '第一章');
  });

  test('listByBook 依 EPUB progression 由小到大排序', () async {
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'C', progression: 0.8));
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'A', progression: 0.1));
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'B', progression: 0.5));

    final list = await repository.listByBook('b1');
    expect(list.map((b) => b.name).toList(), ['A', 'B', 'C']);
  });

  test('listByBook 依 PDF 頁索引由小到大排序', () async {
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'C', pdfPageIndex: 20));
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'A', pdfPageIndex: 2));
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'B', pdfPageIndex: 10));

    final list = await repository.listByBook('b1');
    expect(list.map((b) => b.name).toList(), ['A', 'B', 'C']);
  });

  test('listByBook 只回傳指定 book_id 的書籤', () async {
    await libraryRepository.insertBook(_testBook('b2'));
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'X', progression: 0.1));
    await repository
        .insert(const Bookmark(bookId: 'b2', name: 'Y', pdfPageIndex: 0));

    final list = await repository.listByBook('b1');
    expect(list, hasLength(1));
    expect(list.single.name, 'X');
  });

  test('rename 更新指定書籤的名稱，其餘欄位不受影響', () async {
    final id = await repository.insert(const Bookmark(
      bookId: 'b1',
      name: '舊名稱',
      pdfPageIndex: 5,
    ));
    await repository.rename(id, '新名稱');

    final list = await repository.listByBook('b1');
    expect(list.single.name, '新名稱');
    expect(list.single.pdfPageIndex, 5);
  });

  test('delete 移除指定單筆書籤，其餘不受影響', () async {
    final id1 = await repository
        .insert(const Bookmark(bookId: 'b1', name: 'A', progression: 0.1));
    final id2 = await repository
        .insert(const Bookmark(bookId: 'b1', name: 'B', progression: 0.5));
    await repository.delete(id1);

    final list = await repository.listByBook('b1');
    expect(list, hasLength(1));
    expect(list.single.id, id2);
  });

  test('deleteAllForBook 只清空指定書籍的書籤，其他書籍不受影響', () async {
    await libraryRepository.insertBook(_testBook('b2'));
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'X', progression: 0.1));
    await repository
        .insert(const Bookmark(bookId: 'b2', name: 'Y', pdfPageIndex: 0));

    await repository.deleteAllForBook('b1');

    expect(await repository.listByBook('b1'), isEmpty);
    expect(await repository.listByBook('b2'), hasLength(1));
  });
}
