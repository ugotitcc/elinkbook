import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/book_update_models.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';

void main() {
  group('normalizeBookKey', () {
    test('去除首尾空白與轉小寫', () {
      expect(normalizeBookKey('  Hello '), 'hello');
    });

    test('全形英數轉半形並轉小寫', () {
      expect(normalizeBookKey('ＡＢＣ１２３'), 'abc123');
    });

    test('全形空白轉半形空白', () {
      expect(normalizeBookKey('紅　樓夢'), '紅 樓夢');
    });

    test('空字串、純空白與 null 皆回傳 null', () {
      expect(normalizeBookKey(''), isNull);
      expect(normalizeBookKey('   '), isNull);
      expect(normalizeBookKey('　　'), isNull);
      expect(normalizeBookKey(null), isNull);
    });

    test('中文標點符號不被改變', () {
      expect(normalizeBookKey('紅樓夢，上冊'), '紅樓夢，上冊');
    });
  });

  group('BookUpdateCandidate', () {
    test('copyWith(stagedPath: ...) 只修改 stagedPath', () {
      final dummyBook = Book(
        id: 'book-1',
        title: '舊書',
        format: BookFileFormat.epub,
        filePath: '/path/1',
        source: BookSource.local,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final candidate = BookUpdateCandidate(
        sourceUri: 'content://test/book.epub',
        displayName: 'book.epub',
        format: BookFileFormat.epub,
        confidence: UpdateConfidence.high,
        candidateBooks: [dummyBook],
        unreadableCandidateBookIds: const {},
        stagedPath: null,
      );

      final updated = candidate.copyWith(stagedPath: '/staged/temp.epub');

      expect(updated.sourceUri, candidate.sourceUri);
      expect(updated.displayName, candidate.displayName);
      expect(updated.format, candidate.format);
      expect(updated.confidence, candidate.confidence);
      expect(updated.candidateBooks, candidate.candidateBooks);
      expect(updated.unreadableCandidateBookIds, candidate.unreadableCandidateBookIds);
      expect(updated.stagedPath, '/staged/temp.epub');
    });
  });

  group('BookDetectionResult & BookReplaceResult 型別層次', () {
    test('BookDetectionResult sealed class 各子型別可用', () {
      const BookDetectionResult r1 = DetectedNewBook();
      const BookDetectionResult r2 = DetectedUnsupported();
      expect(r1, isA<DetectedNewBook>());
      expect(r2, isA<DetectedUnsupported>());
    });

    test('BookReplaceResult sealed class 各子型別可用', () {
      const BookReplaceResult failure = BookReplaceFailure(
        BookReplaceFailureReason.formatMismatch,
      );
      expect(failure, isA<BookReplaceFailure>());
      expect(
        (failure as BookReplaceFailure).reason,
        BookReplaceFailureReason.formatMismatch,
      );
    });

    test('BookSourceRefs 可攜帶各來源欄位', () {
      const refs = BookSourceRefs(
        source: BookSource.googleDrive,
        cloudFileId: 'drive-123',
        remoteServerId: 'server-1',
        remoteBookId: 'remote-42',
        remoteDownloadUrl: 'https://example.com/dl',
      );
      expect(refs.source, BookSource.googleDrive);
      expect(refs.cloudFileId, 'drive-123');
      expect(refs.remoteServerId, 'server-1');
      expect(refs.remoteBookId, 'remote-42');
      expect(refs.remoteDownloadUrl, 'https://example.com/dl');
    });
  });
}
