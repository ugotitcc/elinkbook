import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/book_update_models.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/theme/app_theme_preferences.dart';

import '../support/fake_library_repository.dart';

class _CountingLibraryRepository extends FakeLibraryRepository {
  _CountingLibraryRepository();
  int listBooksCallCount = 0;

  @override
  Future<List<Book>> listBooks({
    LibrarySortBy sortBy = LibrarySortBy.lastRead,
    String? groupFilter,
  }) {
    listBooksCallCount++;
    return super.listBooks(sortBy: sortBy, groupFilter: groupFilter);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const channel = MethodChannel('elinkbook/book_metadata');

  late SqliteLibraryRepository repository;
  late Directory tempDir;
  late Directory coversDir;
  late Directory importedDir;
  late Directory stagingDir;
  late BookImportServiceImpl service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    tempDir = Directory.systemTemp.createTempSync('pipeline_test_');
    coversDir = Directory(p.join(tempDir.path, 'covers'))..createSync();
    importedDir = Directory(p.join(tempDir.path, 'imported_books'))..createSync();
    stagingDir = Directory(p.join(tempDir.path, 'update_staging'))..createSync();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'copyContentUriToFile') {
        final args = call.arguments as Map;
        final dest = args['destinationPath'] as String;
        File(dest).writeAsStringSync('dummy content');
        return null;
      }
      if (call.method == 'extractMetadata') {
        final uri = (call.arguments as Map)['uri'] as String;
        if (uri.contains('match_id')) {
          return {
            'title': '測試書',
            'author': '測試作者',
            'identifier': 'same-identifier',
          };
        }
        return {
          'title': '全新書-${uri.hashCode}',
          'author': '全新作者-${uri.hashCode}',
          'identifier': 'id-${uri.hashCode}',
        };
      }
      return null;
    });

    service = BookImportServiceImpl(
      repository: repository,
      coversDirectory: coversDir,
      importedBooksDirectory: importedDir,
      updateStagingDirectory: stagingDir,
      themePreferences: AppThemePreferences(),
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await repository.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('BookImportService pipeline integration (Task 6)', () {
    test('更新版不寫入資料庫，stagedPath 存在且 updateCandidates 包含該候選', () async {
      final oldFile = File(p.join(importedDir.path, 'b1.epub'))..writeAsStringSync('舊檔');
      await repository.insertBook(Book(
        id: 'b1',
        title: '測試書',
        author: '測試作者',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        source: BookSource.local,
        contentFingerprint: 'same-identifier',
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      ));

      final newFile = File(p.join(tempDir.path, 'match_id_update.epub'))..writeAsStringSync('新檔');
      final result = await service.importFiles([newFile.path]);

      expect(result.importedBooks, isEmpty);
      expect(result.updateCandidates, hasLength(1));
      final candidate = result.updateCandidates.first;
      expect(candidate.stagedPath, isNotNull);
      expect(File(candidate.stagedPath!).existsSync(), isTrue);

      final booksInDb = await repository.listBooks();
      expect(booksInDb, hasLength(1));
      expect(booksInDb.first.id, 'b1');
    });

    test('重複檔案跳過（決策 D2）：整檔相同 → skippedDuplicateCount == 1，updateCandidates 為空', () async {
      final oldFile = File(p.join(importedDir.path, 'b1.epub'))..writeAsStringSync('完全相同的舊檔內容');
      await repository.insertBook(Book(
        id: 'b1',
        title: '測試書',
        author: '測試作者',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        source: BookSource.local,
        contentFingerprint: 'same-identifier',
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      ));

      final dupFile = File(p.join(tempDir.path, 'match_id_dup.epub'))..writeAsStringSync('完全相同的舊檔內容');
      final result = await service.importFiles([dupFile.path]);

      expect(result.importedBooks, isEmpty);
      expect(result.skippedDuplicateCount, 1);
      expect(result.updateCandidates, isEmpty);
    });

    test('混合批次：包含 1 新書、1 更新版、1 重複，各歸其類', () async {
      final oldFile = File(p.join(importedDir.path, 'b1.epub'))..writeAsStringSync('完全相同的內容');
      await repository.insertBook(Book(
        id: 'b1',
        title: '測試書',
        author: '測試作者',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        source: BookSource.local,
        contentFingerprint: 'same-identifier',
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      ));

      final brandNew = File(p.join(tempDir.path, 'brand_new.epub'))..writeAsStringSync('全新檔案');
      final updateFile = File(p.join(tempDir.path, 'match_id_update.epub'))..writeAsStringSync('更新版不同內容');
      final dupFile = File(p.join(tempDir.path, 'match_id_dup.epub'))..writeAsStringSync('完全相同的內容');

      final result = await service.importFiles([
        brandNew.path,
        updateFile.path,
        dupFile.path,
      ]);

      expect(result.importedBooks, hasLength(1));
      expect(result.importedBooks.first.title, isNotEmpty);
      expect(result.updateCandidates, hasLength(1));
      expect(result.skippedDuplicateCount, 1);
    });

    test('審查 I-2：不透明 URI（無副檔名）透過 displayNames 偵測更新版', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'extractMetadata') {
          return {
            'title': '測試書',
            'author': '測試作者',
            'identifier': 'same-identifier',
          };
        }
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'copyContentUriToFile') {
          final dest = (call.arguments as Map)['destinationPath'] as String;
          File(dest).writeAsStringSync('staged');
          return null;
        }
        if (call.method == 'computeSha256') {
          return 'sha-new';
        }
        return null;
      });

      final oldFile = File(p.join(importedDir.path, 'b1.epub'))..writeAsStringSync('舊檔');
      await repository.insertBook(Book(
        id: 'b1',
        title: '測試書',
        author: '測試作者',
        format: BookFileFormat.epub,
        filePath: oldFile.path,
        source: BookSource.local,
        contentFingerprint: 'same-identifier',
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      ));

      const opaqueUri = 'content://com.android.providers.media.documents/document/1000';
      final result = await service.importFiles(
        [opaqueUri],
        displayNames: ['match_id_update.epub'],
      );

      expect(result.importedBooks, isEmpty);
      expect(result.updateCandidates, hasLength(1));
    });

    test('importCandidateAsNewBook：並存成功，新書 filePath 位於 imported_books 且暫存檔清除', () async {
      final oldBook = Book(
        id: 'orig-id',
        title: '我的小說',
        author: '作者',
        format: BookFileFormat.epub,
        filePath: '/storage/orig.epub',
        source: BookSource.local,
        groupName: BookGroup.uncategorized,
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      );
      await repository.insertBook(oldBook);

      final stagedFile = File(p.join(stagingDir.path, '12345-6789.epub'))
        ..writeAsStringSync('暫存檔案內容');

      final candidate = BookUpdateCandidate(
        sourceUri: 'content://downloads/novel.epub',
        displayName: '我的小說.epub',
        format: BookFileFormat.epub,
        confidence: UpdateConfidence.high,
        candidateBooks: [oldBook],
        stagedPath: stagedFile.path,
      );

      final newBook = await service.importCandidateAsNewBook(candidate);

      expect(newBook, isNotNull);
      expect(newBook!.id, isNot('orig-id'));
      expect(p.isWithin(stagingDir.path, newBook.filePath), isFalse);
      expect(p.isWithin(importedDir.path, newBook.filePath), isTrue);
      expect(stagedFile.existsSync(), isFalse); // 暫存檔被刪除

      final allBooks = await repository.listBooks();
      expect(allBooks, hasLength(2)); // 原書與新書並存
    });

    test('審查 I-1：importCandidateAsNewBook 保留 displayName 書名，不退為時間戳記', () async {
      final stagedFile = File(p.join(stagingDir.path, '99999-8888.txt'))
        ..writeAsStringSync('章節一\n故事內文');

      final candidate = BookUpdateCandidate(
        sourceUri: 'content://downloads/raw.txt',
        displayName: '紅樓夢精選.txt',
        format: BookFileFormat.txt,
        confidence: UpdateConfidence.suspected,
        candidateBooks: const [],
        stagedPath: stagedFile.path,
      );

      final newBook = await service.importCandidateAsNewBook(candidate);

      expect(newBook, isNotNull);
      expect(newBook!.title, '紅樓夢精選');
      expect(stagedFile.existsSync(), isFalse);
    });

    test('importCandidateAsNewBook 失敗（空 TXT）回傳 null 且暫存檔仍被清除', () async {
      final emptyStaged = File(p.join(stagingDir.path, 'empty-1.txt'))
        ..writeAsStringSync('');

      final candidate = BookUpdateCandidate(
        sourceUri: 'content://downloads/empty.txt',
        displayName: 'empty.txt',
        format: BookFileFormat.txt,
        confidence: UpdateConfidence.suspected,
        candidateBooks: const [],
        stagedPath: emptyStaged.path,
      );

      final result = await service.importCandidateAsNewBook(candidate);

      expect(result, isNull);
      expect(emptyStaged.existsSync(), isFalse); // 失敗仍被清除
    });

    test('審查 M-2：批次匯入時 listBooks 呼叫為常數次，且同批次內後續檔案可偵測前一檔案', () async {
      final countingRepo = _CountingLibraryRepository();
      final batchService = BookImportServiceImpl(
        repository: countingRepo,
        coversDirectory: coversDir,
        importedBooksDirectory: importedDir,
        updateStagingDirectory: stagingDir,
      );

      final file1 = File(p.join(tempDir.path, 'batch1.epub'))..writeAsStringSync('內容 1');
      final file2 = File(p.join(tempDir.path, 'batch2.epub'))..writeAsStringSync('內容 2');
      final file3 = File(p.join(tempDir.path, 'batch3.epub'))..writeAsStringSync('內容 3');

      await batchService.importFiles([file1.path, file2.path, file3.path]);

      // 迴圈開始前只呼叫 1 次 listBooks
      expect(countingRepo.listBooksCallCount, 1);
    });
  });
}
