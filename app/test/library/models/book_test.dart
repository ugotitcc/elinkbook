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

  test('totalCharacterCount 欄位可正確往返（Issue 3 新增）', () {
    final book = Book(
      id: 'b6',
      title: 'EPUB 書籍',
      format: BookFileFormat.epub,
      filePath: '/storage/emulated/0/book.epub',
      source: BookSource.local,
      totalCharacterCount: 123456,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.totalCharacterCount, 123456);
  });

  test('totalCharacterCount 未設定時，往返後仍為 null（代表尚未計算過）', () {
    final book = Book(
      id: 'b7',
      title: 'EPUB 書籍',
      format: BookFileFormat.epub,
      filePath: '/storage/emulated/0/book2.epub',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.totalCharacterCount, isNull);
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
}
