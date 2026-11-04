import 'dart:io';

import 'package:elinkbook/library/book_update_models.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/support/book_update_resolver.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_book_import_service.dart';

class _TestImageStreamCompleter extends ImageStreamCompleter {}

Book _makeBook({
  required String id,
  String title = '測試書',
  String? coverPath,
}) {
  return Book(
    id: id,
    title: title,
    format: BookFileFormat.epub,
    source: BookSource.local,
    filePath: '/test/path/$id.epub',
    coverPath: coverPath,
    createTime: DateTime(2026, 1, 1),
    lastReadTime: DateTime(2026, 1, 1),
  );
}

BookUpdateCandidate _makeCandidate({
  String sourceUri = 'file:///test/new.epub',
  String? displayName = 'new.epub',
  BookFileFormat format = BookFileFormat.epub,
  UpdateConfidence confidence = UpdateConfidence.high,
  List<Book>? candidateBooks,
  String? stagedPath = '/test/staging/staged.epub',
}) {
  return BookUpdateCandidate(
    sourceUri: sourceUri,
    displayName: displayName,
    format: format,
    confidence: confidence,
    candidateBooks: candidateBooks ?? [_makeBook(id: 'b1', coverPath: '/covers/b1.png')],
    stagedPath: stagedPath,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('applyBookUpdateChoices', () {
    late FakeBookImportService service;
    late List<String> evictedCovers;

    setUp(() {
      service = FakeBookImportService();
      evictedCovers = [];
    });

    test('跳過：丟棄暫存檔、計數 skipped++、不觸碰其他操作', () async {
      final candidate = _makeCandidate();
      final decisions = [
        BookUpdateDecision(candidate, const SkipChoice()),
      ];

      final result = await applyBookUpdateChoices(
        service,
        decisions,
        onCoverChanged: evictedCovers.add,
      );

      expect(result.skipped, 1);
      expect(result.replaced, 0);
      expect(result.coexisted, 0);
      expect(result.failed, 0);
      expect(service.discardedCandidates, [candidate]);
      expect(service.replaceCalls, isEmpty);
      expect(service.importCandidateCalls, isEmpty);
      expect(evictedCovers, isEmpty);
    });

    test('取代成功：呼叫 replaceBook、evict 舊新封面（去重）、成功分支不重複丟棄', () async {
      final oldBook = _makeBook(id: 'b1', coverPath: '/covers/b1.png');
      final updatedBook = _makeBook(id: 'b1', coverPath: '/covers/b1.png');
      final candidate = _makeCandidate(candidateBooks: [oldBook]);
      service.replaceResultsByBookId['b1'] = BookReplaceSuccess(updatedBook);

      final decisions = [
        BookUpdateDecision(candidate, const ReplaceChoice('b1')),
      ];

      final result = await applyBookUpdateChoices(
        service,
        decisions,
        onCoverChanged: evictedCovers.add,
      );

      expect(result.replaced, 1);
      expect(result.failed, 0);
      expect(service.replaceCalls, [('b1', candidate.sourceUri)]);
      // 新舊 coverPath 相同，去重後只呼叫一次
      expect(evictedCovers, ['/covers/b1.png']);
      expect(service.discardedCandidates, isEmpty);
    });

    test('取代成功且新舊封面路徑不同：兩者皆被 evict', () async {
      final oldBook = _makeBook(id: 'b1', coverPath: '/covers/old.png');
      final updatedBook = _makeBook(id: 'b1', coverPath: '/covers/new.png');
      final candidate = _makeCandidate(candidateBooks: [oldBook]);
      service.replaceResultsByBookId['b1'] = BookReplaceSuccess(updatedBook);

      final decisions = [
        BookUpdateDecision(candidate, const ReplaceChoice('b1')),
      ];

      final result = await applyBookUpdateChoices(
        service,
        decisions,
        onCoverChanged: evictedCovers.add,
      );

      expect(result.replaced, 1);
      expect(evictedCovers, ['/covers/old.png', '/covers/new.png']);
    });

    test('取代失敗（回傳失敗或丟例外）：補丟棄暫存檔、計數 failed++、不 evict 封面', () async {
      final candidate1 = _makeCandidate(sourceUri: 'file:///c1.epub');
      service.replaceResultsByBookId['b1'] =
          const BookReplaceFailure(BookReplaceFailureReason.newFileParseFailed);

      final result1 = await applyBookUpdateChoices(
        service,
        [BookUpdateDecision(candidate1, const ReplaceChoice('b1'))],
        onCoverChanged: evictedCovers.add,
      );

      expect(result1.failed, 1);
      expect(result1.replaced, 0);
      expect(service.discardedCandidates, [candidate1]);
      expect(evictedCovers, isEmpty);

      // 測試丟出例外情境
      service.discardedCandidates.clear();
      service.replaceThrows = Exception('磁碟寫入崩潰');
      final candidate2 = _makeCandidate(sourceUri: 'file:///c2.epub');

      final result2 = await applyBookUpdateChoices(
        service,
        [BookUpdateDecision(candidate2, const ReplaceChoice('b1'))],
        onCoverChanged: evictedCovers.add,
      );

      expect(result2.failed, 1);
      expect(service.discardedCandidates, [candidate2]);
      expect(evictedCovers, isEmpty);
    });

    test('並存：成功時 coexisted++、失敗時 failed++', () async {
      final candidate1 = _makeCandidate(sourceUri: 'file:///new1.epub');
      service.importCandidateResult = _makeBook(id: 'new_book');

      final result1 = await applyBookUpdateChoices(
        service,
        [BookUpdateDecision(candidate1, const CoexistChoice())],
        onCoverChanged: evictedCovers.add,
      );

      expect(result1.coexisted, 1);
      expect(result1.failed, 0);
      expect(service.importCandidateCalls, [candidate1]);

      // 回傳 null 視為失敗
      service.importCandidateCalls.clear();
      service.importCandidateResult = null;
      final candidate2 = _makeCandidate(sourceUri: 'file:///new2.epub');

      final result2 = await applyBookUpdateChoices(
        service,
        [BookUpdateDecision(candidate2, const CoexistChoice())],
        onCoverChanged: evictedCovers.add,
      );

      expect(result2.failed, 1);
      expect(result2.coexisted, 0);
    });

    test('單筆失敗不中斷其他列：逐筆循序套用', () async {
      final c1 = _makeCandidate(sourceUri: 'file:///c1.epub');
      final c2 = _makeCandidate(sourceUri: 'file:///c2.epub');
      final c3 = _makeCandidate(sourceUri: 'file:///c3.epub');

      service.replaceResultsByBookId['b1'] =
          const BookReplaceFailure(BookReplaceFailureReason.writeFailed);
      service.importCandidateResult = _makeBook(id: 'b3');

      final decisions = [
        BookUpdateDecision(c1, const ReplaceChoice('b1')),
        BookUpdateDecision(c2, const SkipChoice()),
        BookUpdateDecision(c3, const CoexistChoice()),
      ];

      final result = await applyBookUpdateChoices(
        service,
        decisions,
        onCoverChanged: evictedCovers.add,
      );

      expect(result.failed, 1);
      expect(result.skipped, 1);
      expect(result.coexisted, 1);
      expect(result.replaced, 0);
    });

    test('多候選取代指定書：精確對應目標書籍之 bookId 與封面', () async {
      final b1 = _makeBook(id: 'b1', title: '版本一', coverPath: '/covers/b1.png');
      final b2 = _makeBook(id: 'b2', title: '版本二', coverPath: '/covers/b2.png');
      final updatedB2 = _makeBook(id: 'b2', title: '版本二新版', coverPath: '/covers/b2.png');
      final candidate = _makeCandidate(candidateBooks: [b1, b2]);
      service.replaceResultsByBookId['b2'] = BookReplaceSuccess(updatedB2);

      final decisions = [
        BookUpdateDecision(candidate, const ReplaceChoice('b2')),
      ];

      final result = await applyBookUpdateChoices(
        service,
        decisions,
        onCoverChanged: evictedCovers.add,
      );

      expect(result.replaced, 1);
      expect(service.replaceCalls, [('b2', candidate.sourceUri)]);
      expect(evictedCovers, ['/covers/b2.png']);
    });
  });

  group('evictCoverImageCache', () {
    test('evictCoverImageCache 呼叫後使 ImageCache 移除該項目', () {
      final testPath = '${Directory.systemTemp.path}/test_cover.png';
      final provider = FileImage(File(testPath));

      PaintingBinding.instance.imageCache.putIfAbsent(
        provider,
        () => _TestImageStreamCompleter(),
      );
      expect(PaintingBinding.instance.imageCache.containsKey(provider), isTrue);

      evictCoverImageCache(testPath);
      expect(PaintingBinding.instance.imageCache.containsKey(provider), isFalse);
    });
  });
}
