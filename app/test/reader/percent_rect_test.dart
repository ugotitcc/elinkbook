import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/percent_rect.dart';

void main() {
  test('四個欄位值完全相同的 PercentRect 視為相等', () {
    const a = PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4);
    const b = PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('任一欄位不同時視為不相等', () {
    const a = PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4);
    const b = PercentRect(left: 0.15, top: 0.2, right: 0.3, bottom: 0.4);
    expect(a, isNot(b));
  });

  test('toJson／fromJson round-trip 保留所有欄位', () {
    const rect = PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4);
    final restored = PercentRect.fromJson(rect.toJson());
    expect(restored, rect);
  });

  group('overlaps', () {
    test('兩個矩形有重疊區域時回傳 true', () {
      const a = PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.5);
      const b = PercentRect(left: 0.3, top: 0.3, right: 0.7, bottom: 0.7);
      expect(a.overlaps(b), isTrue);
      expect(b.overlaps(a), isTrue);
    });

    test('兩個矩形完全不重疊時回傳 false', () {
      const a = PercentRect(left: 0.1, top: 0.1, right: 0.2, bottom: 0.2);
      const b = PercentRect(left: 0.8, top: 0.8, right: 0.9, bottom: 0.9);
      expect(a.overlaps(b), isFalse);
    });

    test('兩個矩形僅邊緣相接（不重疊面積）時回傳 false', () {
      const a = PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.5);
      const b = PercentRect(left: 0.5, top: 0.1, right: 0.9, bottom: 0.5);
      expect(a.overlaps(b), isFalse);
    });
  });
}

