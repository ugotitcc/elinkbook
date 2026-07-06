import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/writing_mode.dart';

void main() {
  test('EpubLayoutInfo 建構後可讀取欄位', () {
    const info =
        EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.vertical);
    expect(info.isFixedLayout, isFalse);
    expect(info.writingMode, WritingMode.vertical);
  });

  test('EpubLayoutInfo 欄位皆相同時相等', () {
    const a =
        EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal);
    const b =
        EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal);
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });

  test('EpubLayoutInfo 欄位不同時不相等', () {
    const a =
        EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.vertical);
    const b =
        EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.vertical);
    expect(a, isNot(equals(b)));
  });
}
