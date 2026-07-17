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
}
