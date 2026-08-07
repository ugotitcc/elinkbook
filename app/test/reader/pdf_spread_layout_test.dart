import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_spread_layout.dart';

void main() {
  group('isDualPageEnabled', () {
    test('auto 模式：橫向啟用、直向關閉', () {
      expect(
        isDualPageEnabled(mode: DualPageMode.auto, isLandscape: true),
        isTrue,
      );
      expect(
        isDualPageEnabled(mode: DualPageMode.auto, isLandscape: false),
        isFalse,
      );
    });

    test('always 模式：不論方向恆為啟用', () {
      expect(
        isDualPageEnabled(mode: DualPageMode.always, isLandscape: true),
        isTrue,
      );
      expect(
        isDualPageEnabled(mode: DualPageMode.always, isLandscape: false),
        isTrue,
      );
    });

    test('never 模式：不論方向恆為停用', () {
      expect(
        isDualPageEnabled(mode: DualPageMode.never, isLandscape: true),
        isFalse,
      );
      expect(
        isDualPageEnabled(mode: DualPageMode.never, isLandscape: false),
        isFalse,
      );
    });
  });

  group('buildSpreads', () {
    test('封面獨立時 5 頁配對為 [0][1,2][3,4]（收尾雙頁）', () {
      final spreads = buildSpreads(totalPages: 5, coverAlone: true);
      expect(spreads, [
        [0],
        [1, 2],
        [3, 4],
      ]);
    });

    test('封面獨立時 6 頁配對為 [0][1,2][3,4][5]（收尾單頁）', () {
      final spreads = buildSpreads(totalPages: 6, coverAlone: true);
      expect(spreads, [
        [0],
        [1, 2],
        [3, 4],
        [5],
      ]);
    });

    test('封面不獨立時 5 頁配對為 [0,1][2,3][4]', () {
      final spreads = buildSpreads(totalPages: 5, coverAlone: false);
      expect(spreads, [
        [0, 1],
        [2, 3],
        [4],
      ]);
    });

    test('封面不獨立時 6 頁配對為 [0,1][2,3][4,5]', () {
      final spreads = buildSpreads(totalPages: 6, coverAlone: false);
      expect(spreads, [
        [0, 1],
        [2, 3],
        [4, 5],
      ]);
    });

    test('1 頁與 0 頁的邊界不擲例外', () {
      expect(buildSpreads(totalPages: 1, coverAlone: true), [
        [0],
      ]);
      expect(buildSpreads(totalPages: 1, coverAlone: false), [
        [0],
      ]);
      expect(buildSpreads(totalPages: 0, coverAlone: true), <List<int>>[]);
    });
  });
}
