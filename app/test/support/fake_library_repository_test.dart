import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';

import 'fake_library_repository.dart';

void main() {
  group('FakeLibraryRepository.findByRemoteBookId', () {
    test('命中：回傳對應書籍', () async {
      final repo = FakeLibraryRepository();
      await repo.insertBook(Book(
        id: 'book1',
        title: '雲端書',
        format: BookFileFormat.epub,
        filePath: '/books/book1.epub',
        source: BookSource.calibreOpds,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
        remoteServerId: 'srv1',
        remoteBookId: 'remote-book-1',
      ));

      final found = await repo.findByRemoteBookId('srv1', 'remote-book-1');
      expect(found?.id, 'book1');
    });

    test('未命中：不同站點或不同 remoteBookId 皆回傳 null', () async {
      final repo = FakeLibraryRepository();
      await repo.insertBook(Book(
        id: 'book1',
        title: '雲端書',
        format: BookFileFormat.epub,
        filePath: '/books/book1.epub',
        source: BookSource.calibreOpds,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
        remoteServerId: 'srv1',
        remoteBookId: 'remote-book-1',
      ));

      expect(await repo.findByRemoteBookId('srv2', 'remote-book-1'), isNull);
      expect(await repo.findByRemoteBookId('srv1', 'other-book'), isNull);
    });
  });

  group('FakeLibraryRepository.findByContentFingerprint', () {
    test('命中：回傳對應書籍', () async {
      final repo = FakeLibraryRepository();
      await repo.insertBook(Book(
        id: 'book1',
        title: '本機書',
        format: BookFileFormat.epub,
        filePath: '/books/book1.epub',
        source: BookSource.local,
        contentFingerprint: 'fingerprint-abc',
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      final found = await repo.findByContentFingerprint('fingerprint-abc');
      expect(found?.id, 'book1');
    });

    test('未命中：回傳 null', () async {
      final repo = FakeLibraryRepository();
      expect(await repo.findByContentFingerprint('does-not-exist'), isNull);
    });
  });

  group('FakeLibraryRepository.findByCloudFileId', () {
    test('命中：回傳對應書籍', () async {
      final repo = FakeLibraryRepository();
      await repo.insertBook(Book(
        id: 'book1',
        title: '雲端匯入的書',
        format: BookFileFormat.epub,
        filePath: '/books/book1.epub',
        source: BookSource.googleDrive,
        cloudFileId: 'gdrive-file-1',
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      final found =
          await repo.findByCloudFileId(BookSource.googleDrive, 'gdrive-file-1');
      expect(found?.id, 'book1');
    });

    test('未命中：不同 provider 或不同 cloudFileId 皆回傳 null', () async {
      final repo = FakeLibraryRepository();
      await repo.insertBook(Book(
        id: 'book1',
        title: '雲端匯入的書',
        format: BookFileFormat.epub,
        filePath: '/books/book1.epub',
        source: BookSource.googleDrive,
        cloudFileId: 'gdrive-file-1',
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      expect(
        await repo.findByCloudFileId(BookSource.oneDrive, 'gdrive-file-1'),
        isNull,
      );
      expect(
        await repo.findByCloudFileId(BookSource.googleDrive, 'other-file'),
        isNull,
      );
    });
  });

  group('FakeLibraryRepository.findBookById', () {
    test('命中：回傳對應書籍', () async {
      final repo = FakeLibraryRepository();
      await repo.insertBook(Book(
        id: 'book1',
        title: '本機書',
        format: BookFileFormat.epub,
        filePath: '/books/book1.epub',
        source: BookSource.local,
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      final found = await repo.findBookById('book1');
      expect(found?.id, 'book1');
      expect(found?.title, '本機書');
    });

    test('未命中：回傳 null', () async {
      final repo = FakeLibraryRepository();
      expect(await repo.findBookById('does-not-exist'), isNull);
    });
  });

  group('FakeLibraryRepository._withGroupName 保留所有新欄位', () {
    test('renameGroup 後，書籍的 remoteServerId 與 contentFingerprint 等欄位皆保留', () async {
      final repo = FakeLibraryRepository();
      await repo.upsertGroup('自訂分類');
      await repo.insertBook(Book(
        id: 'book1',
        title: '雲端書',
        format: BookFileFormat.epub,
        filePath: '/books/book1.epub',
        source: BookSource.calibreOpds,
        groupName: '自訂分類',
        epubLocator: '{"href":"/c1.xhtml"}',
        pdfPageIndex: null,
        isFixedLayout: false,
        contentFingerprint: 'fp-123',
        positionUpdatedAt: 2000,
        positionSyncedServerUpdatedAt: '2026-08-17T00:00:00Z',
        remoteServerId: 'srv1',
        remoteBookId: 'rb-1',
        remoteDownloadUrl: 'http://example.com/1.epub',
        isDownloaded: false,
        cloudFileId: 'gdrive-file-1',
        createTime: DateTime.fromMillisecondsSinceEpoch(1000),
        lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      await repo.renameGroup('自訂分類', '新分類');

      final books = await repo.listBooks();
      final book = books.single;
      expect(book.groupName, '新分類');
      expect(book.epubLocator, '{"href":"/c1.xhtml"}');
      expect(book.isFixedLayout, false);
      expect(book.contentFingerprint, 'fp-123');
      expect(book.positionUpdatedAt, 2000);
      expect(book.positionSyncedServerUpdatedAt, '2026-08-17T00:00:00Z');
      expect(book.remoteServerId, 'srv1');
      expect(book.remoteBookId, 'rb-1');
      expect(book.remoteDownloadUrl, 'http://example.com/1.epub');
      expect(book.isDownloaded, false);
      expect(book.cloudFileId, 'gdrive-file-1');
    });
  });
}
