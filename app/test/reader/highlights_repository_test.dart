import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/highlights_repository.dart';

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
  late HighlightsRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    repository = HighlightsRepository(libraryRepository.database);
    await libraryRepository.insertBook(_testBook('b1'));
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  test('insert 寫入後 listByBook 讀回相同資料', () async {
    await repository.insert(const Highlight(
      id: 'h1',
      bookId: 'b1',
      style: HighlightStyle.highlighterYellow,
      epubLocatorJson: '{"href":"/c1.xhtml"}',
      progression: 0.1,
    ));

    final list = await repository.listByBook('b1');
    expect(list, hasLength(1));
    expect(list.single.id, 'h1');
    expect(list.single.style, HighlightStyle.highlighterYellow);
  });

  test('listByBook 依 progression 由小到大排序', () async {
    await repository.insert(
        const Highlight(id: 'h2', bookId: 'b1', style: HighlightStyle.underline, progression: 0.8));
    await repository.insert(
        const Highlight(id: 'h3', bookId: 'b1', style: HighlightStyle.underline, progression: 0.1));

    final list = await repository.listByBook('b1');
    expect(list.map((h) => h.progression).toList(), [0.1, 0.8]);
  });

  test('listByBook 只回傳指定 book_id 的劃線', () async {
    await libraryRepository.insertBook(_testBook('b2'));
    await repository.insert(
        const Highlight(id: 'h4', bookId: 'b1', style: HighlightStyle.underline, progression: 0.1));
    await repository.insert(
        const Highlight(id: 'h5', bookId: 'b2', style: HighlightStyle.underline, progression: 0.1));

    final list = await repository.listByBook('b1');
    expect(list, hasLength(1));
  });

  test('delete 移除指定單筆劃線，其餘不受影響', () async {
    await repository.insert(
        const Highlight(id: 'h6', bookId: 'b1', style: HighlightStyle.underline, progression: 0.1));
    await repository.insert(
        const Highlight(id: 'h7', bookId: 'b1', style: HighlightStyle.underline, progression: 0.5));
    await repository.delete('h6');

    final list = await repository.listByBook('b1');
    expect(list, hasLength(1));
    expect(list.single.id, 'h7');
  });

  test('deleteAllForBook 只清空指定書籍的劃線，其他書籍不受影響', () async {
    await libraryRepository.insertBook(_testBook('b2'));
    await repository.insert(
        const Highlight(id: 'h8', bookId: 'b1', style: HighlightStyle.underline, progression: 0.1));
    await repository.insert(
        const Highlight(id: 'h9', bookId: 'b2', style: HighlightStyle.underline, progression: 0.1));

    await repository.deleteAllForBook('b1');

    expect(await repository.listByBook('b1'), isEmpty);
    expect(await repository.listByBook('b2'), hasLength(1));
  });

  test('listByBook 對 PDF 劃線依 pdf_page_index 由小到大排序', () async {
    await repository.insert(const Highlight(
        id: 'h10', bookId: 'b1', style: HighlightStyle.underline, pdfPageIndex: 5));
    await repository.insert(const Highlight(
        id: 'h11', bookId: 'b1', style: HighlightStyle.underline, pdfPageIndex: 1));

    final list = await repository.listByBook('b1');
    expect(list.map((h) => h.pdfPageIndex).toList(), [1, 5]);
  });
}
