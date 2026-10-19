// app/test/dictionary/csv_rows_test.dart
import 'package:elinkbook/dictionary/importers/csv_rows.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('基本多列多欄', () {
    expect(parseCsvRows('a,b\nc,d'), [
      ['a', 'b'],
      ['c', 'd'],
    ]);
  });

  test('引號內的逗號與換行不分割', () {
    expect(parseCsvRows('a,"b,c"\n"d\ne",f'), [
      ['a', 'b,c'],
      ['d\ne', 'f'],
    ]);
  });

  test('"" 跳脫成單一引號', () {
    expect(parseCsvRows('"say ""hi""",x'), [
      ['say "hi"', 'x'],
    ]);
  });

  test('CRLF 與結尾空列', () {
    expect(parseCsvRows('a,b\r\nc,d\r\n'), [
      ['a', 'b'],
      ['c', 'd'],
    ]);
  });

  test('空字串回傳空清單', () {
    expect(parseCsvRows(''), isEmpty);
  });

  test('空欄位保留為空字串', () {
    expect(parseCsvRows('a,,c'), [
      ['a', '', 'c'],
    ]);
  });
}
