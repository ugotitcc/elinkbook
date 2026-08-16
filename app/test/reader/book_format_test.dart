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
    expect(detectBookFormat('book.txt'), BookFormat.unknown);
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

  group('isFoliateFormat', () {
    test('epub／azw3 回傳 true', () {
      expect(isFoliateFormat(BookFormat.epub), isTrue);
      expect(isFoliateFormat(BookFormat.azw3), isTrue);
    });

    test('pdf／unknown 回傳 false', () {
      expect(isFoliateFormat(BookFormat.pdf), isFalse);
      expect(isFoliateFormat(BookFormat.unknown), isFalse);
    });
  });
}
