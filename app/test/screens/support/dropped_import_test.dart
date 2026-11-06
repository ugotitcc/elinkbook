import 'dart:io';

import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/book_update_models.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/support/dropped_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/fake_book_import_service.dart';

Book _testBook(String id) {
  final now = DateTime(2026, 1, 1);
  return Book(
    id: id,
    title: '書 $id',
    format: BookFileFormat.epub,
    filePath: 'C:/books/$id.epub',
    source: BookSource.local,
    createTime: now,
    lastReadTime: now,
  );
}

BookUpdateCandidate _testCandidate(String id) {
  return BookUpdateCandidate(
    sourceUri: 'C:/books/$id.epub',
    displayName: '$id.epub',
    format: BookFileFormat.epub,
    confidence: UpdateConfidence.high,
    candidateBooks: [_testBook(id)],
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dropped_import_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('classifyDroppedPaths：混合路徑正確分成 files／folders，重複路徑去重，不存在路徑歸入 files，順序不變', () {
    final file1 = File(p.join(tempDir.path, 'a.epub'))..writeAsBytesSync([1]);
    final dir1 = Directory(p.join(tempDir.path, 'folder1'))..createSync();
    final file2 = File(p.join(tempDir.path, 'b.pdf'))..writeAsBytesSync([2]);
    final dir2 = Directory(p.join(tempDir.path, 'folder2'))..createSync();
    final missingPath = p.join(tempDir.path, 'missing.epub');

    final classified = classifyDroppedPaths([
      file1.path,
      dir1.path,
      file1.path,
      missingPath,
      dir2.path,
      dir1.path,
      file2.path,
    ]);

    expect(classified.files, [file1.path, missingPath, file2.path]);
    expect(classified.folders, [dir1.path, dir2.path]);
  });

  test('只有檔案：不呼叫 confirmAutoGroup，importFiles 收到全部檔案與對應的 basename 作為 displayNames（含中文與空白）', () async {
    final file1 = File(p.join(tempDir.path, '我的 書.epub'))..writeAsBytesSync([1]);
    final file2 = File(p.join(tempDir.path, 'second.pdf'))..writeAsBytesSync([2]);
    final service = FakeBookImportService()
      ..importFilesResult = ImportResult(importedBooks: [_testBook('1')]);
    var confirmCalls = 0;

    final result = await importDroppedPaths(
      service,
      [file1.path, file2.path],
      confirmAutoGroup: () async {
        confirmCalls++;
        return true;
      },
    );

    expect(confirmCalls, 0);
    expect(service.lastImportCall, isNotNull);
    expect(service.lastImportCall!.uris, [file1.path, file2.path]);
    expect(service.lastImportCall!.displayNames, ['我的 書.epub', 'second.pdf']);
    expect(result, isNotNull);
    expect(result!.importedBooks, hasLength(1));
  });

  test('只有資料夾：呼叫 confirmAutoGroup 一次，importFolder 帶入確認框的選擇', () async {
    final dir1 = Directory(p.join(tempDir.path, '書櫃'))..createSync();
    final service = FakeBookImportService()
      ..importFolderResult = ImportResult(importedBooks: [_testBook('f1')]);
    var confirmCalls = 0;

    final result = await importDroppedPaths(
      service,
      [dir1.path],
      confirmAutoGroup: () async {
        confirmCalls++;
        return false;
      },
    );

    expect(confirmCalls, 1);
    expect(service.importFolderCalls, [dir1.path]);
    expect(service.lastAutoGroupByFolderName, isFalse);
    expect(result, isNotNull);
    expect(result!.importedBooks.map((b) => b.id), ['f1']);
  });

  test('多個資料夾：confirmAutoGroup 只呼叫一次，兩個資料夾都以同一個選擇匯入', () async {
    final dir1 = Directory(p.join(tempDir.path, '資料夾甲'))..createSync();
    final dir2 = Directory(p.join(tempDir.path, '資料夾乙'))..createSync();
    final service = FakeBookImportService();
    var confirmCalls = 0;

    final result = await importDroppedPaths(
      service,
      [dir1.path, dir2.path],
      confirmAutoGroup: () async {
        confirmCalls++;
        return true;
      },
    );

    expect(confirmCalls, 1);
    expect(service.importFolderCalls, [dir1.path, dir2.path]);
    expect(service.lastAutoGroupByFolderName, isTrue);
    expect(result, isNotNull);
  });

  test('混合：檔案與資料夾都匯入，結果合併（importedBooks、updateCandidates 串接，略過計數相加）', () async {
    final file1 = File(p.join(tempDir.path, 'a.epub'))..writeAsBytesSync([1]);
    final dir1 = Directory(p.join(tempDir.path, 'folder1'))..createSync();
    final service = FakeBookImportService()
      ..importFilesResult = ImportResult(
        importedBooks: [_testBook('file_book')],
        skippedDuplicateCount: 1,
        skippedUnsupportedCount: 2,
        updateCandidates: [_testCandidate('cand_file')],
      )
      ..importFolderResult = ImportResult(
        importedBooks: [_testBook('folder_book')],
        skippedDuplicateCount: 3,
        skippedUnsupportedCount: 4,
        updateCandidates: [_testCandidate('cand_folder')],
      );

    final result = await importDroppedPaths(
      service,
      [file1.path, dir1.path],
      confirmAutoGroup: () async => true,
    );

    expect(result, isNotNull);
    expect(result!.importedBooks.map((b) => b.id), ['file_book', 'folder_book']);
    expect(result.skippedDuplicateCount, 4);
    expect(result.skippedUnsupportedCount, 6);
    expect(result.updateCandidates.map((c) => c.displayName), [
      'cand_file.epub',
      'cand_folder.epub',
    ]);
    expect(result.failure, isNull);
  });

  test('confirmAutoGroup 回 null：回傳 null，importFiles 與 importFolder 都沒被呼叫', () async {
    final file1 = File(p.join(tempDir.path, 'a.epub'))..writeAsBytesSync([1]);
    final dir1 = Directory(p.join(tempDir.path, 'folder1'))..createSync();
    final service = FakeBookImportService();

    final result = await importDroppedPaths(
      service,
      [file1.path, dir1.path],
      confirmAutoGroup: () async => null,
    );

    expect(result, isNull);
    expect(service.lastImportCall, isNull);
    expect(service.importFolderCalls, isEmpty);
  });

  test('failure 規則：沒有檔案且所有資料夾都 failure 時帶 failure；有檔案或任一資料夾成功則 failure 為 null', () async {
    final file1 = File(p.join(tempDir.path, 'a.epub'))..writeAsBytesSync([1]);
    final dir1 = Directory(p.join(tempDir.path, 'folder1'))..createSync();
    final dir2 = Directory(p.join(tempDir.path, 'folder2'))..createSync();

    // 1. 沒有檔案且所有資料夾都失敗
    final allFailService = FakeBookImportService()
      ..importFolderResult = const ImportResult(
        failure: ImportFailure.folderListingFailed,
      );
    final allFailResult = await importDroppedPaths(
      allFailService,
      [dir1.path, dir2.path],
      confirmAutoGroup: () async => true,
    );
    expect(allFailResult!.failure, ImportFailure.folderListingFailed);

    // 2. 沒有檔案，但其中一個資料夾成功
    final partialFolderService = FakeBookImportService()
      ..importFolderResultsByUri[dir1.path] = const ImportResult(
        failure: ImportFailure.folderListingFailed,
      )
      ..importFolderResultsByUri[dir2.path] = ImportResult(
        importedBooks: [_testBook('ok')],
      );
    final partialFolderResult = await importDroppedPaths(
      partialFolderService,
      [dir1.path, dir2.path],
      confirmAutoGroup: () async => true,
    );
    expect(partialFolderResult!.failure, isNull);
    expect(partialFolderResult.importedBooks, hasLength(1));

    // 3. 有檔案且資料夾失敗
    final fileAndFailFolderService = FakeBookImportService()
      ..importFilesResult = ImportResult(importedBooks: [_testBook('file_ok')])
      ..importFolderResult = const ImportResult(
        failure: ImportFailure.folderListingFailed,
      );
    final fileAndFailFolderResult = await importDroppedPaths(
      fileAndFailFolderService,
      [file1.path, dir1.path],
      confirmAutoGroup: () async => true,
    );
    expect(fileAndFailFolderResult!.failure, isNull);
    expect(fileAndFailFolderResult.importedBooks, hasLength(1));
  });

  test('paths 為空：回傳 null 且不呼叫任何匯入', () async {
    final service = FakeBookImportService();
    var confirmCalls = 0;

    final result = await importDroppedPaths(
      service,
      const [],
      confirmAutoGroup: () async {
        confirmCalls++;
        return true;
      },
    );

    expect(result, isNull);
    expect(confirmCalls, 0);
    expect(service.lastImportCall, isNull);
    expect(service.importFolderCalls, isEmpty);
  });
}
