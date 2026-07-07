import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/writing_mode.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqliteLibraryRepository libraryRepository;
  late BookReaderPrefsRepository repository;

  setUp(() async {
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    repository = BookReaderPrefsRepository(libraryRepository.database);
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

  test('尚未儲存過偏好設定時，load 回傳 BookReaderPrefs.empty', () async {
    final prefs = await repository.load('b1');
    expect(prefs, BookReaderPrefs.empty);
  });

  test('save 寫入後，load 讀回相同的值', () async {
    const prefs = BookReaderPrefs(
      fontFamily: AppFont.sourceHanSerif,
      fontSize: 20,
      writingModeOverride: WritingMode.vertical,
    );

    await repository.save('b1', prefs);

    expect(await repository.load('b1'), prefs);
  });

  test('save 覆寫既有偏好設定（同一本書再次呼叫 save）', () async {
    await repository.save('b1', const BookReaderPrefs(fontSize: 18));
    await repository.save('b1', const BookReaderPrefs(fontSize: 22));

    final prefs = await repository.load('b1');
    expect(prefs.fontSize, 22);
  });

  test('刪除書籍後，對應的偏好設定列因 ON DELETE CASCADE 一併消失', () async {
    await repository.save('b1', const BookReaderPrefs(fontSize: 18));

    await libraryRepository.deleteBook('b1');

    expect(await repository.load('b1'), BookReaderPrefs.empty);
  });

  test('當 save 寫入的數值在 SQLite 存成整數時，load 仍能安全轉換為 double 而不崩潰',
      () async {
    const prefs = BookReaderPrefs(
      fontSize: 18.0, // 無小數部分，SQLite 可能存成 INTEGER
      lineHeight: 1.0, // 同上
    );

    await repository.save('b1', prefs);

    // 若 BookReaderPrefs.fromMap 直接用 `as double?` 而非
    // `(... as num?)?.toDouble()`，此處會拋出 type cast 例外崩潰。
    final loaded = await repository.load('b1');
    expect(loaded.fontSize, 18.0);
    expect(loaded.lineHeight, 1.0);
  });
}
