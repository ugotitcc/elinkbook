import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';

void main() {
  test('Book toMap/fromMap 往返後所有欄位值不變', () {
    final book = Book(
      id: 'b1',
      title: '測試書名',
      author: '測試作者',
      format: BookFileFormat.epub,
      filePath: 'content://com.example/book.epub',
      source: BookSource.local,
      coverPath: '/data/covers/b1.png',
      progress: 42.5,
      groupName: '經典名著',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.id, book.id);
    expect(restored.title, book.title);
    expect(restored.author, book.author);
    expect(restored.format, book.format);
    expect(restored.filePath, book.filePath);
    expect(restored.source, book.source);
    expect(restored.coverPath, book.coverPath);
    expect(restored.progress, book.progress);
    expect(restored.groupName, book.groupName);
    expect(restored.createTime, book.createTime);
    expect(restored.lastReadTime, book.lastReadTime);
  });

  test('author/coverPath 為 null、其餘欄位使用預設值時往返仍正確', () {
    final book = Book(
      id: 'b2',
      title: 'PDF 書籍',
      format: BookFileFormat.pdf,
      filePath: '/storage/emulated/0/book.pdf',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.author, isNull);
    expect(restored.coverPath, isNull);
    expect(restored.progress, 0);
    expect(restored.groupName, '未分類');
  });

  test('TXT 格式與雲端來源列舉值可正確往返', () {
    final book = Book(
      id: 'b3',
      title: 'TXT 書籍',
      format: BookFileFormat.txt,
      filePath: '/storage/emulated/0/book.txt',
      source: BookSource.googleDrive,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.format, BookFileFormat.txt);
    expect(restored.source, BookSource.googleDrive);
  });

  test('copyWith(groupName: ...) 只改變 groupName，其餘欄位保持不變', () {
    final book = Book(
      id: 'b4',
      title: '測試書名',
      author: '測試作者',
      format: BookFileFormat.epub,
      filePath: 'content://com.example/book.epub',
      source: BookSource.local,
      coverPath: '/data/covers/b4.png',
      progress: 30,
      groupName: '舊分類',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    final moved = book.copyWith(groupName: '新分類');

    expect(moved.groupName, '新分類');
    expect(moved.id, book.id);
    expect(moved.title, book.title);
    expect(moved.author, book.author);
    expect(moved.format, book.format);
    expect(moved.filePath, book.filePath);
    expect(moved.source, book.source);
    expect(moved.coverPath, book.coverPath);
    expect(moved.progress, book.progress);
    expect(moved.createTime, book.createTime);
    expect(moved.lastReadTime, book.lastReadTime);
  });

  test('copyWith() 不傳入參數時，回傳與原本欄位值相同的新物件', () {
    final book = Book(
      id: 'b5',
      title: '測試書名',
      format: BookFileFormat.pdf,
      filePath: '/storage/emulated/0/book.pdf',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final copy = book.copyWith();

    expect(copy.groupName, book.groupName);
    expect(copy.id, book.id);
    expect(copy.title, book.title);
  });

  test('isFixedLayout 欄位可正確往返（epic-17-epub-render-migration Issue 2）',
      () {
    final fxlBook = Book(
      id: 'b8',
      title: 'FXL 漫畫',
      format: BookFileFormat.epub,
      filePath: '/storage/emulated/0/comic.epub',
      source: BookSource.local,
      isFixedLayout: true,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final reflowableBook = Book(
      id: 'b9',
      title: '流式小說',
      format: BookFileFormat.epub,
      filePath: '/storage/emulated/0/novel.epub',
      source: BookSource.local,
      isFixedLayout: false,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    expect(Book.fromMap(fxlBook.toMap()).isFixedLayout, isTrue);
    expect(Book.fromMap(reflowableBook.toMap()).isFixedLayout, isFalse);
  });

  test('isFixedLayout 未設定時，往返後仍為 null（代表尚未判斷過，或格式不適用）',
      () {
    final book = Book(
      id: 'b10',
      title: 'PDF 書籍',
      format: BookFileFormat.pdf,
      filePath: '/storage/emulated/0/report.pdf',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.isFixedLayout, isNull);
  });

  test('copyWith(isFixedLayout: ...) 只改變 isFixedLayout，其餘欄位保持不變',
      () {
    final book = Book(
      id: 'b11',
      title: '流式小說',
      format: BookFileFormat.epub,
      filePath: '/storage/emulated/0/novel.epub',
      source: BookSource.local,
      groupName: '小說',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    final detected = book.copyWith(isFixedLayout: false);

    expect(detected.isFixedLayout, isFalse);
    expect(detected.id, book.id);
    expect(detected.title, book.title);
    expect(detected.groupName, book.groupName);
    expect(detected.createTime, book.createTime);
    expect(detected.lastReadTime, book.lastReadTime);
  });

  test('operator== 與 hashCode：欄位值完全相同視為相等，isFixedLayout 不同則不相等',
      () {
    Book build({bool? isFixedLayout}) => Book(
          id: 'b12',
          title: '書名',
          format: BookFileFormat.epub,
          filePath: '/storage/emulated/0/book.epub',
          source: BookSource.local,
          isFixedLayout: isFixedLayout,
          createTime: DateTime.fromMillisecondsSinceEpoch(1000),
          lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
        );

    final a = build(isFixedLayout: true);
    final b = build(isFixedLayout: true);
    final c = build(isFixedLayout: false);
    final d = build();

    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
    expect(a, isNot(equals(c)));
    expect(a, isNot(equals(d)));
  });

  test('contentFingerprint 欄位可正確往返（epic-8-sync Issue 3）', () {
    final book = Book(
      id: 'b13',
      title: '書名',
      format: BookFileFormat.epub,
      filePath: 'content://com.example/book.epub',
      source: BookSource.local,
      contentFingerprint: 'urn:uuid:00000000-0000-0000-0000-000000000001',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.contentFingerprint,
        'urn:uuid:00000000-0000-0000-0000-000000000001');
  });

  test('contentFingerprint 未設定時，往返後仍為 null（代表尚未計算過指紋）', () {
    final book = Book(
      id: 'b14',
      title: '書名',
      format: BookFileFormat.pdf,
      filePath: '/storage/emulated/0/book.pdf',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.contentFingerprint, isNull);
  });

  test('positionUpdatedAt／positionSyncedServerUpdatedAt 欄位可正確往返（epic-8-sync Issue 5）',
      () {
    final book = Book(
      id: 'b15',
      title: '書名',
      format: BookFileFormat.epub,
      filePath: 'content://com.example/book.epub',
      source: BookSource.local,
      positionUpdatedAt: 1735689600000,
      positionSyncedServerUpdatedAt: '2026-08-04 12:00:00.000Z',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.positionUpdatedAt, 1735689600000);
    expect(restored.positionSyncedServerUpdatedAt, '2026-08-04 12:00:00.000Z');
  });

  test('positionUpdatedAt／positionSyncedServerUpdatedAt 未設定時，往返後仍為 null（代表尚未同步過閱讀位置）',
      () {
    final book = Book(
      id: 'b16',
      title: '書名',
      format: BookFileFormat.pdf,
      filePath: '/storage/emulated/0/book.pdf',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.positionUpdatedAt, isNull);
    expect(restored.positionSyncedServerUpdatedAt, isNull);
  });

  test('copyWith 保留 contentFingerprint／positionUpdatedAt／positionSyncedServerUpdatedAt（epic-8-sync 最終審查修正）',
      () {
    final book = Book(
      id: 'b17',
      title: '書名',
      format: BookFileFormat.epub,
      filePath: 'content://com.example/book.epub',
      source: BookSource.local,
      contentFingerprint: 'fp-17',
      positionUpdatedAt: 1735689600000,
      positionSyncedServerUpdatedAt: '2026-08-04 12:00:00.000Z',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final copied = book.copyWith(groupName: '新分類');

    expect(copied.contentFingerprint, 'fp-17');
    expect(copied.positionUpdatedAt, 1735689600000);
    expect(copied.positionSyncedServerUpdatedAt, '2026-08-04 12:00:00.000Z');
    expect(copied.groupName, '新分類');
  });

  test('copyWith(isDownloaded: false) 只改變 isDownloaded，filePath 等其餘欄位保持不變', () {
    final book = Book(
      id: 'b18',
      title: '書名',
      format: BookFileFormat.epub,
      filePath: '/storage/remote_books/b18.epub',
      source: BookSource.calibreOpds,
      remoteServerId: 'srv1',
      remoteBookId: 'remote-18',
      remoteDownloadUrl: 'http://example.com/download/18.epub',
      isDownloaded: true,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final removed = book.copyWith(isDownloaded: false);

    expect(removed.isDownloaded, isFalse);
    expect(removed.filePath, '/storage/remote_books/b18.epub');
    expect(removed.remoteServerId, 'srv1');
    expect(removed.remoteBookId, 'remote-18');
    expect(removed.remoteDownloadUrl, 'http://example.com/download/18.epub');
  });

  test('copyWith(filePath: ..., isDownloaded: true) 同時更新兩個欄位，remoteDownloadUrl 等其餘欄位保持不變',
      () {
    final book = Book(
      id: 'b19',
      title: '書名',
      format: BookFileFormat.epub,
      filePath: '/storage/remote_books/b19.epub',
      source: BookSource.calibreOpds,
      remoteServerId: 'srv1',
      remoteBookId: 'remote-19',
      remoteDownloadUrl: 'http://example.com/download/19.epub',
      isDownloaded: false,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final redownloaded = book.copyWith(
      filePath: '/storage/remote_books/b19-new.epub',
      isDownloaded: true,
    );

    expect(redownloaded.filePath, '/storage/remote_books/b19-new.epub');
    expect(redownloaded.isDownloaded, isTrue);
    expect(redownloaded.remoteDownloadUrl, 'http://example.com/download/19.epub');
    expect(redownloaded.remoteServerId, 'srv1');
  });

  test('cloudFileId 欄位可正確往返（epic-29-cloud-import Issue 0）', () {
    final book = Book(
      id: 'b20',
      title: '雲端匯入的書',
      format: BookFileFormat.epub,
      filePath: '/storage/imported_books/b20.epub',
      source: BookSource.googleDrive,
      cloudFileId: 'gdrive-file-abc123',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.cloudFileId, 'gdrive-file-abc123');
  });

  test('cloudFileId 未設定時，往返後仍為 null（代表非雲端匯入）', () {
    final book = Book(
      id: 'b21',
      title: '本機書',
      format: BookFileFormat.pdf,
      filePath: '/storage/emulated/0/book.pdf',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.cloudFileId, isNull);
  });

  test(
      'copyWith() 覆寫全部新開放的具名參數（epic-26-architecture-hardening '
      'Issue 9），值正確套用，未覆寫的既有具名參數維持原值', () {
    final original = Book(
      id: 'b23',
      title: '原書名',
      author: '原作者',
      format: BookFileFormat.pdf,
      filePath: '/storage/original.pdf',
      source: BookSource.local,
      coverPath: '/storage/original_cover.png',
      progress: 0.1,
      epubLocator: 'original-locator',
      pdfPageIndex: 3,
      isFixedLayout: false,
      contentFingerprint: 'fp-original',
      positionUpdatedAt: 1000,
      positionSyncedServerUpdatedAt: '2026-01-01 00:00:00.000Z',
      remoteServerId: 'srv-original',
      remoteBookId: 'remote-original',
      remoteDownloadUrl: 'http://example.com/original.pdf',
      isDownloaded: true,
      cloudFileId: 'cloud-original',
      groupName: '原分類',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    final updated = original.copyWith(
      title: '新書名',
      author: '新作者',
      format: BookFileFormat.epub,
      source: BookSource.googleDrive,
      coverPath: '/storage/new_cover.png',
      progress: 0.9,
      epubLocator: 'new-locator',
      pdfPageIndex: 7,
      contentFingerprint: 'fp-new',
      positionUpdatedAt: 5000,
      positionSyncedServerUpdatedAt: '2026-08-21 00:00:00.000Z',
      remoteServerId: 'srv-new',
      remoteBookId: 'remote-new',
      remoteDownloadUrl: 'http://example.com/new.pdf',
      cloudFileId: 'cloud-new',
      createTime: DateTime.fromMillisecondsSinceEpoch(9000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(9999),
    );

    expect(updated.id, 'b23', reason: 'id 不開放為具名參數，不可能改變');
    expect(updated.title, '新書名');
    expect(updated.author, '新作者');
    expect(updated.format, BookFileFormat.epub);
    expect(updated.source, BookSource.googleDrive);
    expect(updated.coverPath, '/storage/new_cover.png');
    expect(updated.progress, 0.9);
    expect(updated.epubLocator, 'new-locator');
    expect(updated.pdfPageIndex, 7);
    expect(updated.contentFingerprint, 'fp-new');
    expect(updated.positionUpdatedAt, 5000);
    expect(updated.positionSyncedServerUpdatedAt, '2026-08-21 00:00:00.000Z');
    expect(updated.remoteServerId, 'srv-new');
    expect(updated.remoteBookId, 'remote-new');
    expect(updated.remoteDownloadUrl, 'http://example.com/new.pdf');
    expect(updated.cloudFileId, 'cloud-new');
    expect(updated.createTime, DateTime.fromMillisecondsSinceEpoch(9000));
    expect(updated.lastReadTime, DateTime.fromMillisecondsSinceEpoch(9999));

    // 既有 4 個具名參數本次未傳入，維持原值——證明新開放的 17 個參數不影響
    // 既有行為。
    expect(updated.filePath, '/storage/original.pdf');
    expect(updated.isFixedLayout, isFalse);
    expect(updated.isDownloaded, isTrue);
    expect(updated.groupName, '原分類');
  });

  test(
      'copyWith() 不傳入 cloudFileId 時維持原值（epic-26-architecture-hardening '
      'Issue 9 已開放為具名參數，沿用既有「不傳入即維持原值」慣例，不可被'
      '靜默清空）', () {
    final book = Book(
      id: 'b22',
      title: '雲端匯入的書',
      format: BookFileFormat.epub,
      filePath: '/storage/imported_books/b22.epub',
      source: BookSource.oneDrive,
      cloudFileId: 'onedrive-file-xyz789',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final copied = book.copyWith(groupName: '新分類');

    expect(copied.cloudFileId, 'onedrive-file-xyz789');
    expect(copied.groupName, '新分類');
  });
}
