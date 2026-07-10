import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';

void main() {
  test('建構後四個欄位正確保留', () {
    const rect = PdfCropRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8);
    expect(rect.left, 0.1);
    expect(rect.top, 0.2);
    expect(rect.right, 0.9);
    expect(rect.bottom, 0.8);
  });

  test('四個欄位值完全相同的 PdfCropRect 視為相等', () {
    const a = PdfCropRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8);
    const b = PdfCropRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('任一欄位值不同時視為不相等', () {
    const a = PdfCropRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8);
    const b = PdfCropRect(left: 0.15, top: 0.2, right: 0.9, bottom: 0.8);
    expect(a, isNot(b));
  });

  test('toJson／fromJson round-trip 保留所有欄位', () {
    const rect = PdfCropRect(left: 0.05, top: 0.1, right: 0.95, bottom: 0.9);

    final json = rect.toJson();
    final restored = PdfCropRect.fromJson(json);

    expect(restored, rect);
  });

  test('toJson 產出的字串包含四個座標鍵值', () {
    const rect = PdfCropRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8);
    final json = rect.toJson();
    expect(json, contains('"left":0.1'));
    expect(json, contains('"top":0.2'));
    expect(json, contains('"right":0.9'));
    expect(json, contains('"bottom":0.8'));
  });
}
