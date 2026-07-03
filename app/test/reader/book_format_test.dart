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
}
