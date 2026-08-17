import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_format.dart';

void main() {
  test('.epub 副檔名判定為 EPUB 格式', () {
    expect(detectBookFormat('book.epub'), BookFormat.epub);
  });

  test('.pdf 副檔名判定為 PDF 格式', () {
    expect(detectBookFormat('book.pdf'), BookFormat.pdf);
  });

  test('不支援的副檔名回傳 unknown', () {
    expect(detectBookFormat('book.xyz'), BookFormat.unknown);
  });

  test('無副檔名的路徑回傳 unknown', () {
    expect(detectBookFormat('book'), BookFormat.unknown);
  });

  test('空字串路徑回傳 unknown（不拋出例外）', () {
    expect(detectBookFormat(''), BookFormat.unknown);
  });

  test('大寫副檔名不分大小寫皆能判定成功', () {
    expect(detectBookFormat('book.EPUB'), BookFormat.epub);
    expect(detectBookFormat('book.PDF'), BookFormat.pdf);
  });

  test('.azw3 副檔名回傳 BookFormat.azw3', () {
    expect(detectBookFormat('book.azw3'), BookFormat.azw3);
    expect(detectBookFormat('BOOK.AZW3'), BookFormat.azw3);
  });

  test('detectBookFormat 對 .cbz 副檔名回傳 BookFormat.cbz', () {
    expect(detectBookFormat('comic.cbz'), BookFormat.cbz);
    expect(detectBookFormat('COMIC.CBZ'), BookFormat.cbz);
  });

  test('detectBookFormat 對 .txt 副檔名回傳 BookFormat.txt', () {
    expect(detectBookFormat('novel.txt'), BookFormat.txt);
    expect(detectBookFormat('NOVEL.TXT'), BookFormat.txt);
  });

  test('detectBookFormat 對 .md 副檔名回傳 BookFormat.md', () {
    expect(detectBookFormat('notes.md'), BookFormat.md);
    expect(detectBookFormat('NOTES.MD'), BookFormat.md);
  });

  group('isFoliateFormat', () {
    test('epub／azw3 回傳 true', () {
      expect(isFoliateFormat(BookFormat.epub), isTrue);
      expect(isFoliateFormat(BookFormat.azw3), isTrue);
    });

    test('cbz 回傳 true', () {
      expect(isFoliateFormat(BookFormat.cbz), isTrue);
    });

    test('txt 回傳 true', () {
      expect(isFoliateFormat(BookFormat.txt), isTrue);
    });

    test('isFoliateFormat 對 md 回傳 true', () {
      expect(isFoliateFormat(BookFormat.md), isTrue);
    });

    test('pdf／unknown 回傳 false', () {
      expect(isFoliateFormat(BookFormat.pdf), isFalse);
      expect(isFoliateFormat(BookFormat.unknown), isFalse);
    });
  });
}
