import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_selection_info.dart';
import 'package:elinkbook/reader/percent_rect.dart';

void main() {
  test('兩個欄位值完全相同的 PdfSelectionInfo 視為相等', () {
    const a = PdfSelectionInfo(
      pageIndex: 3,
      rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
      widgetRect: PercentRect(left: 0.15, top: 0.25, right: 0.35, bottom: 0.45),
    );
    const b = PdfSelectionInfo(
      pageIndex: 3,
      rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
      widgetRect: PercentRect(left: 0.15, top: 0.25, right: 0.35, bottom: 0.45),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('widgetRect 不同時，兩個 PdfSelectionInfo 不視為相等（letterbox 定位修正回歸防護）', () {
    const a = PdfSelectionInfo(
      pageIndex: 3,
      rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
      widgetRect: PercentRect(left: 0.15, top: 0.25, right: 0.35, bottom: 0.45),
    );
    const b = PdfSelectionInfo(
      pageIndex: 3,
      rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
      widgetRect: PercentRect(left: 0.5, top: 0.5, right: 0.6, bottom: 0.6),
    );
    expect(a == b, isFalse);
  });
}
