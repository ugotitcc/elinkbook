import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/book_update_models.dart';
import 'package:elinkbook/library/models/book.dart';
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
  late Directory tempDir;
  late Directory stagingDir;
  late BookImportServiceImpl service;

  setUp(() async {
    repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    tempDir = Directory.systemTemp.createTempSync('staging_test_');
    stagingDir = Directory(p.join(tempDir.path, 'update_staging'))..createSync();
    service = BookImportServiceImpl(
      repository: repository,
      updateStagingDirectory: stagingDir,
    );
  });

  tearDown(() async {
    await repository.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  BookUpdateCandidate createCandidate({String? stagedPath}) {
    return BookUpdateCandidate(
      sourceUri: 'content://downloads/test.epub',
      displayName: 'test.epub',
      format: BookFileFormat.epub,
      confidence: UpdateConfidence.high,
      candidateBooks: [
        Book(
          id: 'b1',
          title: '舊書',
          format: BookFileFormat.epub,
          filePath: '/path/1',
          source: BookSource.local,
          groupName: BookGroup.uncategorized,
          createTime: DateTime.fromMillisecondsSinceEpoch(1000),
          lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      ],
      stagedPath: stagedPath,
    );
  }

  group('BookImportService.discardUpdateCandidate', () {
    test('刪除 candidate.stagedPath 指向的暫存檔', () async {
      final stagedFile = File(p.join(stagingDir.path, 'temp-123.epub'))
        ..writeAsStringSync('staged-data');
      expect(stagedFile.existsSync(), isTrue);

      final candidate = createCandidate(stagedPath: stagedFile.path);
      await service.discardUpdateCandidate(candidate);

      expect(stagedFile.existsSync(), isFalse);
    });

    test('candidate.stagedPath 為 null 時靜默成功，不拋出例外', () async {
      final candidate = createCandidate(stagedPath: null);
      await expectLater(service.discardUpdateCandidate(candidate), completes);
    });

    test('candidate.stagedPath 檔案已不存在時靜默成功', () async {
      final nonExistent = p.join(stagingDir.path, 'already-gone.epub');
      final candidate = createCandidate(stagedPath: nonExistent);
      await expectLater(service.discardUpdateCandidate(candidate), completes);
    });
  });

  group('BookImportService update staging', () {
    test('執行 detectBookUpdate 命中更新候選時，回傳的 candidate.stagedPath 不為 null 且檔案真實存在於 updateStagingDirectory', () async {
      final oldBookFile = File(p.join(tempDir.path, 'old_note.md'))
        ..writeAsStringSync('---\ntitle: 隨筆\nauthor: 筆者\n---\n舊版內容');
      final existingBook = Book(
        id: 'existing-id-1',
        title: '隨筆',
        author: '筆者',
        format: BookFileFormat.md,
        filePath: oldBookFile.path,
        source: BookSource.local,
        groupName: BookGroup.uncategorized,
        contentFingerprint: 'fake-old-hash',
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      );
      await repository.insertBook(existingBook);

      final newBookFile = File(p.join(tempDir.path, 'new_note.md'))
        ..writeAsStringSync('---\ntitle: 隨筆\nauthor: 筆者\n---\n新版更新內容');

      final result = await service.detectBookUpdate(newBookFile.path);

      expect(result, isA<DetectedUpdate>());
      final update = result as DetectedUpdate;
      expect(update.candidate.stagedPath, isNotNull);
      final stagedFile = File(update.candidate.stagedPath!);
      expect(stagedFile.existsSync(), isTrue);
      expect(p.dirname(stagedFile.path), equals(stagingDir.path));
      expect(stagedFile.readAsStringSync(), contains('新版更新內容'));
    });
  });
}
