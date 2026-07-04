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
}
