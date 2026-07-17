import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/epub_selection_info.dart';
import 'package:elinkbook/reader/percent_rect.dart';

void main() {
  test('兩個欄位值完全相同的 EpubSelectionInfo 視為相等', () {
    const a = EpubSelectionInfo(
      locatorJson: '{"href":"/c1.xhtml"}',
      progression: 0.2,
      rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
    );
    const b = EpubSelectionInfo(
      locatorJson: '{"href":"/c1.xhtml"}',
      progression: 0.2,
      rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
