import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/cloud_import/cloud_download_job.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/book_update_models.dart';
import 'package:elinkbook/library/book_update_settle.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_fingerprint_computer.dart';
import '../support/fake_library_repository.dart';

Book _makeTestBook(String id) => Book(
      id: id,
      title: '目標書',
      format: BookFileFormat.epub,
      filePath: '/data/target.epub',
      source: BookSource.local,
      createTime: DateTime(2026, 1, 1),
      lastReadTime: DateTime(2026, 1, 1),
    );

BookUpdateCandidate _makeCandidate({String? stagedPath = '/staged/path.epub'}) {
  return BookUpdateCandidate(
    sourceUri: 'file:///tmp/incoming.epub',
    displayName: 'a.epub',
    format: BookFileFormat.epub,
    stagedPath: stagedPath,
    confidence: UpdateConfidence.high,
    candidateBooks: [_makeTestBook('existing-1')],
  );
}

void main() {
  CloudDownloadJob makeJob({
    FakeBookImportService? importService,
    String? folderName,
    BookSource source = BookSource.googleDrive,
    String fileId = 'file-1',
    String fileName = 'a.epub',
  }) =>
      CloudDownloadJob(
        entry: CloudFileEntry(
          id: fileId,
          name: fileName,
          isFolder: false,
          format: BookFileFormat.epub,
        ),
        client: FakeCloudStorageClient(),
        importService: importService ?? FakeBookImportService(),
        libraryRepository: FakeLibraryRepository(),
        computeFingerprintFn: FakeFingerprintComputer().call,
        source: source,
        folderName: folderName,
      );

  test('isAuthFailure 只對 CloudAuthRequiredException 為真', () {
    final job = makeJob();

    expect(job.isAuthFailure(CloudAuthRequiredException()), isTrue);
    expect(job.isAuthFailure(Exception('HTTP 500')), isFalse);
    expect(job.isAuthFailure(StateError('x')), isFalse);
  });

  group('detectUpdate', () {
    test('DetectedUpdate 且有 stagedPath 回傳候選，傳入 entry.name', () async {
      final importService = FakeBookImportService();
      final candidate = _makeCandidate(stagedPath: '/staged/incoming.epub');
      importService.detectResult = DetectedUpdate(candidate);

      final job = makeJob(importService: importService, fileName: 'my_novel.epub');
      final result = await job.detectUpdate('/tmp/download.epub');

      expect(result, candidate);
      expect(importService.lastDetectUri, '/tmp/download.epub');
      expect(importService.lastDetectDisplayName, 'my_novel.epub');
    });

    test('DetectedNewBook、DetectedDuplicate、DetectedUnsupported 回傳 null', () async {
      final importService = FakeBookImportService();
      final job = makeJob(importService: importService);

      importService.detectResult = const DetectedNewBook();
      expect(await job.detectUpdate('/tmp/1'), isNull);

      importService.detectResult = DetectedDuplicate(_makeTestBook('existing-1'));
      expect(await job.detectUpdate('/tmp/2'), isNull);

      importService.detectResult = const DetectedUnsupported();
      expect(await job.detectUpdate('/tmp/3'), isNull);
    });

    test('DetectedUpdate 但 stagedPath 為 null 回傳 null', () async {
      final importService = FakeBookImportService();
      final candidate = _makeCandidate(stagedPath: null);
      importService.detectResult = DetectedUpdate(candidate);

      final job = makeJob(importService: importService);
      expect(await job.detectUpdate('/tmp/1'), isNull);
    });

    test('服務拋例外回傳 null', () async {
      final importService = FakeBookImportService();
      importService.detectThrows = Exception('IO error');

      final job = makeJob(importService: importService);
      expect(await job.detectUpdate('/tmp/1'), isNull);
    });
  });

  group('settleUpdate', () {
    test('取代：帶入正確來源參數', () async {
      final importService = FakeBookImportService();
      importService.replaceResultsByBookId['existing-1'] = BookReplaceSuccess(
        _makeTestBook('existing-1'),
      );
      final job = makeJob(
        importService: importService,
        source: BookSource.oneDrive,
        fileId: 'onedrive-file-123',
      );
      final candidate = _makeCandidate();

      final result = await job.settleUpdate(candidate, const ReplaceChoice('existing-1'));

      expect(result.outcome, BookUpdateSettleOutcome.replaced);
      expect(importService.lastReplaceSourceRefs?.source, BookSource.oneDrive);
      expect(importService.lastReplaceSourceRefs?.cloudFileId, 'onedrive-file-123');
    });

    test('並存：帶入來源參數與 folderName', () async {
      final importService = FakeBookImportService();
      importService.importCandidateResult = _makeTestBook('new-id');
      final job = makeJob(
        importService: importService,
        source: BookSource.googleDrive,
        fileId: 'gdrive-file-456',
        folderName: 'My Folder',
      );
      final candidate = _makeCandidate();

      final result = await job.settleUpdate(candidate, const CoexistChoice());

      expect(result.outcome, BookUpdateSettleOutcome.coexisted);
      expect(importService.lastImportCandidateSourceRefs?.source, BookSource.googleDrive);
      expect(importService.lastImportCandidateSourceRefs?.cloudFileId, 'gdrive-file-456');
      expect(importService.lastImportCandidateFolderName, 'My Folder');
    });

    test('跳過：丟棄候選', () async {
      final importService = FakeBookImportService();
      final job = makeJob(importService: importService);
      final candidate = _makeCandidate();

      final result = await job.settleUpdate(candidate, const SkipChoice());

      expect(result.outcome, BookUpdateSettleOutcome.skipped);
      expect(importService.discardedCandidates, contains(candidate));
    });
  });

  group('import 保底（Review Focus 6、8）', () {
    test('殘留候選被當作新書匯入且 permanentPath 檔案被刪除', () async {
      final tempDir = await Directory.systemTemp.createTemp('cloud_import_test_');
      final tempFile = File('${tempDir.path}/permanent.epub');
      await tempFile.writeAsString('content');

      final importService = FakeBookImportService();
      final candidate = _makeCandidate();
      importService.importFilesResult = ImportResult(
        importedBooks: [],
        updateCandidates: [candidate],
      );
      importService.importCandidateResult = _makeTestBook('new-id');

      final job = makeJob(
        importService: importService,
        source: BookSource.googleDrive,
        fileId: 'gdrive-file-789',
        folderName: 'Sci-Fi',
      );

      await job.import(tempFile.path);

      expect(importService.importCandidateCalls, contains(candidate));
      expect(importService.lastImportCandidateFolderName, 'Sci-Fi');
      expect(importService.lastImportCandidateSourceRefs?.source, BookSource.googleDrive);
      expect(importService.lastImportCandidateSourceRefs?.cloudFileId, 'gdrive-file-789');
      expect(await tempFile.exists(), isFalse);

      await tempDir.delete(recursive: true);
    });

    test('殘留候選並存全部失敗：permanentPath 被刪且 import 拋例外，讓項目標為 failed（審查 I-1）', () async {
      final tempDir = await Directory.systemTemp.createTemp('cloud_import_test_');
      final tempFile = File('${tempDir.path}/permanent.epub');
      await tempFile.writeAsString('content');

      final importService = FakeBookImportService();
      final candidate = _makeCandidate();
      importService.importFilesResult = ImportResult(
        importedBooks: [],
        updateCandidates: [candidate],
      );
      importService.importCandidateThrows = Exception('disk full');

      final job = makeJob(importService: importService);

      await expectLater(job.import(tempFile.path), throwsA(isA<StateError>()));

      expect(await tempFile.exists(), isFalse);

      await tempDir.delete(recursive: true);
    });

    test('殘留候選並存回傳 null 時同樣拋例外（審查 I-1）', () async {
      final tempDir = await Directory.systemTemp.createTemp('cloud_import_test_');
      final tempFile = File('${tempDir.path}/permanent.epub');
      await tempFile.writeAsString('content');

      final importService = FakeBookImportService();
      importService.importFilesResult = ImportResult(
        importedBooks: [],
        updateCandidates: [_makeCandidate()],
      );
      importService.importCandidateResult = null;

      final job = makeJob(importService: importService);

      await expectLater(job.import(tempFile.path), throwsA(isA<StateError>()));
      expect(await tempFile.exists(), isFalse);

      await tempDir.delete(recursive: true);
    });

    test('多筆殘留候選只要有一筆並存成功就不拋例外', () async {
      final tempDir = await Directory.systemTemp.createTemp('cloud_import_test_');
      final tempFile = File('${tempDir.path}/permanent.epub');
      await tempFile.writeAsString('content');

      final importService = FakeBookImportService();
      importService.importFilesResult = ImportResult(
        importedBooks: [],
        updateCandidates: [_makeCandidate(), _makeCandidate()],
      );
      importService.importCandidateResult = _makeTestBook('new-id');

      final job = makeJob(importService: importService);

      await job.import(tempFile.path);
      expect(await tempFile.exists(), isFalse);

      await tempDir.delete(recursive: true);
    });

    test('無殘留候選時，不呼叫 importCandidateAsNewBook 且 permanentPath 不被刪', () async {
      final tempDir = await Directory.systemTemp.createTemp('cloud_import_test_');
      final tempFile = File('${tempDir.path}/permanent.epub');
      await tempFile.writeAsString('content');

      final importService = FakeBookImportService();
      importService.importFilesResult = ImportResult(
        importedBooks: [
          _makeTestBook('book-1'),
        ],
        updateCandidates: [],
      );

      final job = makeJob(importService: importService);

      await job.import(tempFile.path);

      expect(importService.importCandidateCalls, isEmpty);
      expect(await tempFile.exists(), isTrue);

      await tempDir.delete(recursive: true);
    });
  });
}
