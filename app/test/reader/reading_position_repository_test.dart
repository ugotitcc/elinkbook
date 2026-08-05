import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/reading_position.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqliteLibraryRepository libraryRepository;
  late ReadingPositionRepository repository;

  setUp(() async {
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    repository = ReadingPositionRepository(libraryRepository.database);
    await libraryRepository.insertBook(Book(
      id: 'b1',
      title: '書名',
      format: BookFileFormat.epub,
      filePath: 'content://example/b1',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    ));
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  test('尚未儲存過位置時，load 回傳預設值（皆為 null／progress=0）', () async {
    final position = await repository.load('b1');
    expect(position, const ReadingPosition());
  });

  test('save 寫入 EPUB 定位後，load 讀回相同的值', () async {
    const position = ReadingPosition(
      epubLocatorJson:
          '{"href":"/chap1.xhtml","locations":{"totalProgression":0.3}}',
      progress: 0.3,
    );

    await repository.save('b1', position);

    expect(await repository.load('b1'), position);
  });

  test('save 寫入 PDF 頁索引後，load 讀回相同的值', () async {
    const position = ReadingPosition(pdfPageIndex: 4, progress: 0.67);

    await repository.save('b1', position);

    expect(await repository.load('b1'), position);
  });

  test('save 覆寫既有位置（同一本書再次呼叫 save）', () async {
    await repository.save(
        'b1', const ReadingPosition(pdfPageIndex: 1, progress: 0.1));
    await repository.save(
        'b1', const ReadingPosition(pdfPageIndex: 5, progress: 0.5));

    final position = await repository.load('b1');
    expect(position.pdfPageIndex, 5);
    expect(position.progress, 0.5);
  });

  test('save 不影響書籍的其餘欄位（partial update，非整列覆寫）', () async {
    await repository.save(
        'b1', const ReadingPosition(pdfPageIndex: 2, progress: 0.2));

    final books = await libraryRepository.listBooks();
    expect(books.single.title, '書名'); // 未被覆寫成任何預設值
  });

  test('對應書籍列不存在時，save 靜默無效果、不拋出例外', () async {
    await expectLater(
      repository.save('不存在的書', const ReadingPosition(pdfPageIndex: 1)),
      completes,
    );
  });

  test('save 寫入後，position_updated_at 被設為目前時間戳記（epic-8-sync Issue 5）', () async {
    final before = DateTime.now().millisecondsSinceEpoch;

    await repository.save('b1', const ReadingPosition(pdfPageIndex: 3, progress: 0.3));

    final after = DateTime.now().millisecondsSinceEpoch;
    final rows = await libraryRepository.database
        .query('books', where: 'id = ?', whereArgs: ['b1']);
    final updatedAt = rows.single['position_updated_at'] as int;
    expect(updatedAt, greaterThanOrEqualTo(before));
    expect(updatedAt, lessThanOrEqualTo(after));
  });

  test(
      'save 寫入後，lastReadTime 被更新為目前時間戳記（epic-18-reader-device-qa '
      'Issue 29：真正的「最後閱讀時間」應在使用者實際閱讀、位置有異動時更新，'
      '而非只在匯入當下寫一次）', () async {
    final before = DateTime.now().millisecondsSinceEpoch;

    await repository.save(
        'b1', const ReadingPosition(pdfPageIndex: 3, progress: 0.3));

    final after = DateTime.now().millisecondsSinceEpoch;
    final books = await libraryRepository.listBooks();
    final lastReadTime = books.single.lastReadTime.millisecondsSinceEpoch;
    expect(lastReadTime, greaterThanOrEqualTo(before));
    expect(lastReadTime, lessThanOrEqualTo(after));
  });

  test('save 兩次呼叫，第二次的 position_updated_at 不早於第一次', () async {
    await repository.save('b1', const ReadingPosition(pdfPageIndex: 1, progress: 0.1));
    final firstRows = await libraryRepository.database
        .query('books', where: 'id = ?', whereArgs: ['b1']);
    final firstUpdatedAt = firstRows.single['position_updated_at'] as int;

    await repository.save('b1', const ReadingPosition(pdfPageIndex: 2, progress: 0.2));
    final secondRows = await libraryRepository.database
        .query('books', where: 'id = ?', whereArgs: ['b1']);
    final secondUpdatedAt = secondRows.single['position_updated_at'] as int;

    expect(secondUpdatedAt, greaterThanOrEqualTo(firstUpdatedAt));
  });
}
