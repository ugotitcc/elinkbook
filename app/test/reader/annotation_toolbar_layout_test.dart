import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/annotation_toolbar_layout.dart';
import 'package:elinkbook/reader/percent_rect.dart';

void main() {
  group('annotationToolbarTop', () {
    test('選取範圍上方空間足夠時貼在選取範圍上方', () {
      const rect = PercentRect(left: 0.1, top: 0.5, right: 0.5, bottom: 0.6);

      final top = annotationToolbarTop(
        anchorRect: rect,
        size: const Size(400, 800),
      );

      // 0.5 * 800 - 104（工具列高度）- 8（間距）= 288
      expect(top, 288);
    });

    test('選取範圍上方空間不足時改貼在選取範圍下方', () {
      const rect = PercentRect(left: 0.1, top: 0.05, right: 0.5, bottom: 0.1);

      final top = annotationToolbarTop(
        anchorRect: rect,
        size: const Size(400, 800),
      );

      // 上方為 0.05 * 800 - 112 = -72，不足；下方為 0.1 * 800 + 8 = 88。
      expect(top, 88);
    });

    test('貼在下方仍超出畫面底部時 clamp 到畫面內', () {
      const rect = PercentRect(left: 0.1, top: 0.0, right: 0.5, bottom: 0.95);

      final top = annotationToolbarTop(
        anchorRect: rect,
        size: const Size(400, 800),
      );

      // 下方為 0.95 * 800 + 8 = 768，clamp 到 800 - 104 = 696。
      expect(top, 696);
    });

    test('上方空間剛好等於 0 時仍貼在上方（邊界值）', () {
      const rect = PercentRect(left: 0.1, top: 0.14, right: 0.5, bottom: 0.2);

      final top = annotationToolbarTop(
        anchorRect: rect,
        size: const Size(400, 800),
      );

      // 0.14 * 800 - 104 - 8 = 0（浮點誤差內）；若改成嚴格大於 0 會落到下方 168。
      expect(top, closeTo(0, 1e-9));
    });

    test('畫面高度小於工具列高度時貼齊上緣，不拋例外', () {
      const rect = PercentRect(left: 0.1, top: 0.05, right: 0.5, bottom: 0.1);

      final top = annotationToolbarTop(
        anchorRect: rect,
        size: const Size(400, 90),
      );

      // 下方為 0.1 * 90 + 8 = 17，但上界 90 - 104 為負，退化為 0。
      expect(top, 0);
    });
  });

  group('annotationToolbarLeft', () {
    test('選取範圍在畫面左側時依比例定位', () {
      const rect = PercentRect(left: 0.1, top: 0.5, right: 0.5, bottom: 0.6);

      final left = annotationToolbarLeft(
        anchorRect: rect,
        size: const Size(400, 800),
      );

      expect(left, 40);
    });

    test('選取範圍靠近畫面右緣時 clamp 到畫面寬度扣掉工具列寬度', () {
      const rect = PercentRect(left: 0.9, top: 0.5, right: 0.95, bottom: 0.6);

      final left = annotationToolbarLeft(
        anchorRect: rect,
        size: const Size(400, 800),
      );

      // 0.9 * 400 = 360，clamp 到 400 - 256 = 144。
      expect(left, 144);
    });

    test('畫面寬度小於工具列寬度時貼齊左緣，不拋例外', () {
      const rect = PercentRect(left: 0.9, top: 0.5, right: 0.95, bottom: 0.6);

      final left = annotationToolbarLeft(
        anchorRect: rect,
        size: const Size(200, 800),
      );

      // 0.9 * 200 = 180，但上界 200 - 256 為負，退化為 0。
      expect(left, 0);
    });
  });
}
