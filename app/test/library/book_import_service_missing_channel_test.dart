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
import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/models/book_group.dart';
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

  test('ImportResult 預設 skippedUnsupportedCount 為 0', () {
    expect(const ImportResult().skippedUnsupportedCount, 0);
  });

  test('importFiles：不可辨識格式略過並計入 skippedUnsupportedCount，不計入 skippedDuplicateCount',
      () async {
    final epubPath = p.join(tempDir.path, 'a.epub');
    await File('test/fixtures/sample.epub').copy(epubPath);
    final jpgPath = p.join(tempDir.path, 'cover.jpg');
    await File(jpgPath).writeAsBytes([1, 2, 3]);
    final zipPath = p.join(tempDir.path, 'notes.zip');
    await File(zipPath).writeAsBytes([4, 5, 6]);

    final result = await service.importFiles([epubPath, jpgPath, zipPath]);

    expect(result.importedBooks, hasLength(1));
    expect(result.skippedUnsupportedCount, 2);
    expect(result.skippedDuplicateCount, 0);
  });

  test('本機資料夾：只匯入第一層，子資料夾內的書不匯入，書歸入以資料夾名命名的分類',
      () async {
    final folderDir = Directory(p.join(tempDir.path, '書庫'))..createSync();
    await File('test/fixtures/sample.epub')
        .copy(p.join(folderDir.path, '甲.epub'));
    await File(p.join(folderDir.path, 'desktop.ini')).writeAsBytes([1, 2, 3]);
    final subDir = Directory(p.join(folderDir.path, 'sub'))..createSync();
    await File('test/fixtures/sample.epub')
        .copy(p.join(subDir.path, '乙.epub'));

    final result = await service.importFolder(folderDir.path);

    expect(result.failure, isNull);
    expect(result.importedBooks, hasLength(1));
    expect(result.importedBooks.single.title, '甲');
    expect(result.importedBooks.single.groupName, '書庫');
    expect(result.skippedUnsupportedCount, 1);
  });

  test('本機資料夾：autoGroupByFolderName 為 false 時書歸入未分類', () async {
    final folderDir = Directory(p.join(tempDir.path, '書庫'))..createSync();
    await File('test/fixtures/sample.epub')
        .copy(p.join(folderDir.path, '甲.epub'));

    final result = await service.importFolder(
      folderDir.path,
      autoGroupByFolderName: false,
    );

    expect(result.failure, isNull);
    expect(result.importedBooks, hasLength(1));
    expect(result.importedBooks.single.groupName, BookGroup.uncategorized);
  });

  test('本機資料夾：不存在的路徑回傳 folderListingFailed', () async {
    final result = await service.importFolder(
      p.join(tempDir.path, '不存在的資料夾'),
    );

    expect(result.failure, ImportFailure.folderListingFailed);
    expect(result.importedBooks, isEmpty);
  });
}
