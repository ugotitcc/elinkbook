// metadata channel 不存在時的匯入降級測試（epic-66 Issue 1 Task 8）。
//
// Windows 沒有 `elinkbook/book_metadata` 原生端，任何 `invokeMethod` 都會
// 丟 `MissingPluginException`（`flutter test` 未註冊 handler 的環境同樣
// 會丟），匯入必須與既有 `PlatformException` 降級一樣：標題退回檔名、
// 無封面、不丟例外、不中斷整批匯入。
//
// 刻意不註冊 `elinkbook/book_metadata` 的 mock handler，模擬通道不存在。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqliteLibraryRepository repository;
  late Directory coversDir;
  late Directory importedBooksDir;
  late Directory tempDir;
  late BookImportServiceImpl service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    coversDir = Directory.systemTemp.createTempSync('book_import_missing_covers');
    importedBooksDir =
        Directory.systemTemp.createTempSync('book_import_missing_imported');
    tempDir = Directory.systemTemp.createTempSync('book_import_missing_src');
    service = BookImportServiceImpl(
      repository: repository,
      coversDirectory: coversDir,
      importedBooksDirectory: importedBooksDir,
    );
  });

  tearDown(() async {
    await repository.close();
    for (final dir in [coversDir, importedBooksDir, tempDir]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  test('匯入 EPUB：metadata channel 不存在時，標題退回檔名、不丟例外', () async {
    final source = File('test/fixtures/sample.epub');
    final epubPath = p.join(tempDir.path, '我的最愛.epub');
    await source.copy(epubPath);

    final result = await service.importFiles([epubPath]);

    expect(result.failure, isNull);
    expect(result.importedBooks, hasLength(1),
        reason: 'MissingPluginException 不可中斷匯入');
    final book = result.importedBooks.single;
    expect(book.title, '我的最愛', reason: '標題退回檔名（去副檔名）');
    expect(book.format, BookFileFormat.epub);
    expect(book.coverPath, isNull, reason: '沒有封面可取');
    expect(book.filePath, epubPath, reason: '本機路徑不落地複本、原樣存入');
  });
}
