import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/highlights_repository.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/notes_repository.dart';

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
  late HighlightsRepository highlightsRepository;
  late NotesRepository notesRepository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    highlightsRepository = HighlightsRepository(libraryRepository.database);
    notesRepository = NotesRepository(libraryRepository.database);
    await libraryRepository.insertBook(_testBook('b1'));
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  test('insert 回傳自動指派的 rowid，listByBook 讀回相同資料', () async {
    final id = await notesRepository.insert(const Note(bookId: 'b1', text: 'A', progression: 0.1));
    expect(id, greaterThan(0));

    final list = await notesRepository.listByBook('b1');
    expect(list.single.text, 'A');
  });

  test('listByBook 依 progression 由小到大排序', () async {
    await notesRepository.insert(const Note(bookId: 'b1', text: 'B', progression: 0.8));
    await notesRepository.insert(const Note(bookId: 'b1', text: 'A', progression: 0.1));

    final list = await notesRepository.listByBook('b1');
    expect(list.map((n) => n.text).toList(), ['A', 'B']);
  });

  test('updateText 更新指定備註的文字，其餘欄位不受影響', () async {
    final id = await notesRepository
        .insert(const Note(bookId: 'b1', text: '舊文字', progression: 0.2, highlightId: null));
    await notesRepository.updateText(id, '新文字');

    final list = await notesRepository.listByBook('b1');
    expect(list.single.text, '新文字');
    expect(list.single.progression, 0.2);
  });

  test('delete 移除指定單筆備註，其餘不受影響', () async {
    final id1 = await notesRepository.insert(const Note(bookId: 'b1', text: 'A', progression: 0.1));
    final id2 = await notesRepository.insert(const Note(bookId: 'b1', text: 'B', progression: 0.5));
    await notesRepository.delete(id1);

    final list = await notesRepository.listByBook('b1');
    expect(list, hasLength(1));
    expect(list.single.id, id2);
  });

  test('deleteAllForBook 只清空指定書籍的備註，其他書籍不受影響', () async {
    await libraryRepository.insertBook(_testBook('b2'));
    await notesRepository.insert(const Note(bookId: 'b1', text: 'A', progression: 0.1));
    await notesRepository.insert(const Note(bookId: 'b2', text: 'B', progression: 0.1));

    await notesRepository.deleteAllForBook('b1');

    expect(await notesRepository.listByBook('b1'), isEmpty);
    expect(await notesRepository.listByBook('b2'), hasLength(1));
  });

  test(
      'FK 退化行為（spec.md 決策 #13／資料模型關聯）：刪除劃線後，依附的'
      '備註 highlight_id 自動變 null，備註內容本身不受影響', () async {
    final highlightId = await highlightsRepository.insert(
      const Highlight(bookId: 'b1', style: HighlightStyle.underline, progression: 0.3),
    );
    final noteId = await notesRepository.insert(
      Note(bookId: 'b1', text: '依附備註', progression: 0.3, highlightId: highlightId),
    );

    await highlightsRepository.delete(highlightId);

    final notes = await notesRepository.listByBook('b1');
    final degraded = notes.singleWhere((n) => n.id == noteId);
    expect(degraded.highlightId, isNull);
    expect(degraded.text, '依附備註');
  });

  test(
      'FK 退化行為（批次版本）：deleteAllForBook 清空劃線後，所有依附備註'
      '皆退化為純備註，備註本身不被刪除', () async {
    final h1 = await highlightsRepository
        .insert(const Highlight(bookId: 'b1', style: HighlightStyle.underline, progression: 0.1));
    final h2 = await highlightsRepository
        .insert(const Highlight(bookId: 'b1', style: HighlightStyle.underline, progression: 0.2));
    await notesRepository.insert(Note(bookId: 'b1', text: 'N1', progression: 0.1, highlightId: h1));
    await notesRepository.insert(Note(bookId: 'b1', text: 'N2', progression: 0.2, highlightId: h2));

    await highlightsRepository.deleteAllForBook('b1');

    final notes = await notesRepository.listByBook('b1');
    expect(notes, hasLength(2));
    expect(notes.every((n) => n.highlightId == null), isTrue);
  });
}
