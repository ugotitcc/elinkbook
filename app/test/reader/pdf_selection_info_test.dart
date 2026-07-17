import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_selection_info.dart';
import 'package:elinkbook/reader/percent_rect.dart';

void main() {
  test('兩個欄位值完全相同的 PdfSelectionInfo 視為相等', () {
    const a = PdfSelectionInfo(
      pageIndex: 3,
      rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
    );
    const b = PdfSelectionInfo(
      pageIndex: 3,
      rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
