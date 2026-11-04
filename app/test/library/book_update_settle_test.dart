import 'package:elinkbook/library/book_update_models.dart';
import 'package:elinkbook/library/book_update_settle.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_book_import_service.dart';

Book _makeBook({
  required String id,
  required String title,
  String? coverPath,
  String? filePath,
}) {
  return Book(
    id: id,
    title: title,
    format: BookFileFormat.epub,
    filePath: filePath ?? '/data/books/$id.epub',
    source: BookSource.local,
    coverPath: coverPath,
    createTime: DateTime(2026, 1, 1),
    lastReadTime: DateTime(2026, 1, 1),
  );
}

BookUpdateCandidate _makeCandidate({
  String sourceUri = 'file:///data/new.epub',
  String? displayName,
  String? stagedPath = '/data/staging/staged.epub',
  List<Book>? candidateBooks,
}) {
  return BookUpdateCandidate(
    sourceUri: sourceUri,
    format: BookFileFormat.epub,
    displayName: displayName,
    stagedPath: stagedPath,
    confidence: UpdateConfidence.high,
    candidateBooks: candidateBooks ?? [_makeBook(id: 'b1', title: '舊書')],
  );
}

void main() {
  group('settleBookUpdate 單筆結算邏輯', () {
    late FakeBookImportService service;

    setUp(() {
      service = FakeBookImportService();
    });

    test('跳過：outcome 為 skipped，且 discardedCandidates 含該候選', () async {
      final candidate = _makeCandidate();

      final result = await settleBookUpdate(
        service,
        candidate,
        const SkipChoice(),
      );

      expect(result.outcome, BookUpdateSettleOutcome.skipped);
      expect(result.changedCoverPaths, isEmpty);
      expect(service.discardedCandidates, contains(candidate));
      expect(service.replaceCalls, isEmpty);
      expect(service.importCandidateCalls, isEmpty);
    });

    test('取代成功：replaceCalls 帶正確 bookId，sourceRefs 與 candidate 正確轉傳，回傳舊新封面去重', () async {
      final oldBook = _makeBook(id: 'b1', title: '舊書', coverPath: '/covers/old.png');
      final updatedBook = _makeBook(id: 'b1', title: '新書', coverPath: '/covers/new.png');
      final candidate = _makeCandidate(
        sourceUri: 'file:///new.epub',
        displayName: '新版小說.epub',
        candidateBooks: [oldBook],
      );

      service.replaceResultsByBookId['b1'] = BookReplaceSuccess(updatedBook);

      const sourceRefs = BookSourceRefs(
        source: BookSource.googleDrive,
        cloudFileId: 'cloud-123',
      );

      final result = await settleBookUpdate(
        service,
        candidate,
        const ReplaceChoice('b1'),
        sourceRefs: sourceRefs,
      );

      expect(result.outcome, BookUpdateSettleOutcome.replaced);
      expect(service.replaceCalls, [('b1', 'file:///new.epub')]);
      expect(service.lastReplaceDisplayName, '新版小說.epub');
      expect(service.lastReplaceCandidate, candidate);
      expect(service.lastReplaceSourceRefs, sourceRefs);
      expect(result.changedCoverPaths, {'/covers/old.png', '/covers/new.png'});
      // 成功時服務端自行處理暫存，不額外呼叫 discard
      expect(service.discardedCandidates, isEmpty);
    });

    test('取代成功（新舊封面相同或為 null）：changedCoverPaths 正確去重與忽略 null', () async {
      final oldBook = _makeBook(id: 'b1', title: '舊書', coverPath: '/covers/same.png');
      final updatedBook = _makeBook(id: 'b1', title: '新書', coverPath: '/covers/same.png');
      final candidate = _makeCandidate(candidateBooks: [oldBook]);

      service.replaceResultsByBookId['b1'] = BookReplaceSuccess(updatedBook);

      final result = await settleBookUpdate(
        service,
        candidate,
        const ReplaceChoice('b1'),
      );

      expect(result.outcome, BookUpdateSettleOutcome.replaced);
      expect(result.changedCoverPaths, {'/covers/same.png'});
    });

    test('取代失敗：outcome 為 failed，候選被丟棄，changedCoverPaths 為空', () async {
      final candidate = _makeCandidate();
      service.replaceResultsByBookId['b1'] =
          const BookReplaceFailure(BookReplaceFailureReason.writeFailed);

      final result = await settleBookUpdate(
        service,
        candidate,
        const ReplaceChoice('b1'),
      );

      expect(result.outcome, BookUpdateSettleOutcome.failed);
      expect(result.changedCoverPaths, isEmpty);
      expect(service.discardedCandidates, contains(candidate));
    });

    test('取代拋出例外：outcome 為 failed，候選被丟棄，永不對外拋出例外', () async {
      final candidate = _makeCandidate();
      service.replaceThrows = Exception('IO Error');

      final result = await settleBookUpdate(
        service,
        candidate,
        const ReplaceChoice('b1'),
      );

      expect(result.outcome, BookUpdateSettleOutcome.failed);
      expect(result.changedCoverPaths, isEmpty);
      expect(service.discardedCandidates, contains(candidate));
    });

    test('並存成功：outcome 為 coexisted，folderName 與 sourceRefs 正確轉傳', () async {
      final candidate = _makeCandidate();
      final newBook = _makeBook(id: 'b2', title: '並存書');
      service.importCandidateResult = newBook;

      const sourceRefs = BookSourceRefs(
        source: BookSource.calibreOpds,
        remoteServerId: 'srv-1',
        remoteBookId: 'rb-2',
      );

      final result = await settleBookUpdate(
        service,
        candidate,
        const CoexistChoice(),
        folderName: '小說',
        sourceRefs: sourceRefs,
      );

      expect(result.outcome, BookUpdateSettleOutcome.coexisted);
      expect(result.changedCoverPaths, isEmpty);
      expect(service.importCandidateCalls, [candidate]);
      expect(service.lastImportCandidateFolderName, '小說');
      expect(service.lastImportCandidateSourceRefs, sourceRefs);
    });

    test('並存失敗（回傳 null）：outcome 為 failed', () async {
      final candidate = _makeCandidate();
      service.importCandidateResult = null;

      final result = await settleBookUpdate(
        service,
        candidate,
        const CoexistChoice(),
      );

      expect(result.outcome, BookUpdateSettleOutcome.failed);
      expect(result.changedCoverPaths, isEmpty);
    });

    test('並存拋出例外：outcome 為 failed，永不對外拋出例外', () async {
      final candidate = _makeCandidate();
      service.importCandidateThrows = Exception('Import failed');

      final result = await settleBookUpdate(
        service,
        candidate,
        const CoexistChoice(),
      );

      expect(result.outcome, BookUpdateSettleOutcome.failed);
      expect(result.changedCoverPaths, isEmpty);
    });
  });
}
