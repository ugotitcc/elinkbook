import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
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

  group('computeSpreadLayout', () {
    List<Size> pages(int n) => List.filled(n, const Size(100, 200));

    test('LTR、封面獨立、5 頁：頁面矩形置中且 spread 內兩頁緊貼', () {
      final layout = computeSpreadLayout(
        pageSizes: pages(5),
        margin: 8,
        coverAlone: true,
        direction: DualPageDirection.ltr,
      );

      expect(layout.spreads, [
        [0],
        [1, 2],
        [3, 4],
      ]);
      // 封面（單頁 spread）在該列內置中：x = margin + (contentW - W) / 2
      // = 8 + (200 - 100) / 2 = 58。
      expect(layout.pageRects[0], const Rect.fromLTWH(58, 8, 100, 200));
      // 第一個雙頁 spread：LTR 時文件順序在前者（page 1）在左。
      expect(layout.pageRects[1], const Rect.fromLTWH(8, 216, 100, 200));
      expect(layout.pageRects[2], const Rect.fromLTWH(108, 216, 100, 200));
      // 兩頁緊貼：右頁 left == 左頁 right。
      expect(layout.pageRects[1].right, layout.pageRects[2].left);
    });

    test('RTL、封面獨立、5 頁：spread 內左右鏡像', () {
      final layout = computeSpreadLayout(
        pageSizes: pages(5),
        margin: 8,
        coverAlone: true,
        direction: DualPageDirection.rtl,
      );

      // RTL：文件順序在後者（page 2）在左，page 1 在右——與已刪除的舊
      // Kotlin pairIndices(anchor:1, RTL) == (2, 1) 定義一致。
      expect(layout.pageRects[2], const Rect.fromLTWH(8, 216, 100, 200));
      expect(layout.pageRects[1], const Rect.fromLTWH(108, 216, 100, 200));
    });

    test('spreadRects 寬度全部一致，等於文件內容寬度（翻頁縮放不跳動）', () {
      final layout = computeSpreadLayout(
        pageSizes: pages(5),
        margin: 8,
        coverAlone: true,
        direction: DualPageDirection.ltr,
      );
      final contentWidth = layout.documentSize.width - 8 * 2;
      for (final rect in layout.spreadRects) {
        expect(rect.width, contentWidth,
            reason: '封面單頁 spread 也必須與雙頁 spread 同寬，翻頁時頁面'
                '視覺大小才不會跳動');
      }
    });

    test('spreadRects 垂直依序遞增、彼此不重疊，且與 documentSize 一致', () {
      final layout = computeSpreadLayout(
        pageSizes: pages(6),
        margin: 8,
        coverAlone: true,
        direction: DualPageDirection.ltr,
      );
      for (var i = 0; i < layout.spreadRects.length - 1; i++) {
        expect(
          layout.spreadRects[i].bottom + 8,
          layout.spreadRects[i + 1].top,
        );
      }
      expect(
        layout.documentSize.height,
        layout.spreadRects.last.bottom + 8,
      );
    });

    test('單頁 spread（封面）的頁面在該列內水平置中', () {
      final layout = computeSpreadLayout(
        pageSizes: pages(5),
        margin: 8,
        coverAlone: true,
        direction: DualPageDirection.ltr,
      );
      expect(
        layout.pageRects[0].center.dx,
        layout.spreadRects[0].center.dx,
      );
    });

    test('pageRects 逐頁可查、尺寸等於原始頁面尺寸（Issue 4 相容性契約）', () {
      final layout = computeSpreadLayout(
        pageSizes: pages(5),
        margin: 8,
        coverAlone: true,
        direction: DualPageDirection.ltr,
      );
      expect(layout.pageRects.length, 5);
      for (final rect in layout.pageRects) {
        expect(rect.size, const Size(100, 200));
      }
      // pageRects 是「單一頁面」邊界，spreadRects 是合併後的跨頁邊界，
      // 兩者不應相等——這是 Issue 4 換算劃線選取矩形時的關鍵區分。
      expect(layout.pageRects[1], isNot(layout.spreadRects[1]));
    });

    test('0 頁與 1 頁的邊界不擲例外', () {
      final empty = computeSpreadLayout(
        pageSizes: const [],
        margin: 8,
        coverAlone: true,
        direction: DualPageDirection.ltr,
      );
      expect(empty.pageRects, isEmpty);
      expect(empty.spreadRects, isEmpty);
      expect(empty.spreads, isEmpty);
      expect(empty.documentSize, const Size(16, 8));

      final single = computeSpreadLayout(
        pageSizes: pages(1),
        margin: 8,
        coverAlone: true,
        direction: DualPageDirection.ltr,
      );
      expect(single.spreads, [
        [0],
      ]);
      expect(single.pageRects.length, 1);
    });
  });

  group('PdfSpreadLayout 導航查詢', () {
    // 5 頁、封面獨立：spreads == [[0],[1,2],[3,4]]，pageToSpread ==
    // [0,1,1,2,2]。
    PdfSpreadLayout layout5CoverAlone() => computeSpreadLayout(
          pageSizes: List.filled(5, const Size(100, 200)),
          margin: 8,
          coverAlone: true,
          direction: DualPageDirection.ltr,
        );

    // 6 頁、封面不獨立：spreads == [[0,1],[2,3],[4,5]]。
    PdfSpreadLayout layout6NoCover() => computeSpreadLayout(
          pageSizes: List.filled(6, const Size(100, 200)),
          margin: 8,
          coverAlone: false,
          direction: DualPageDirection.ltr,
        );

    test('spreadIndexOf／anchorPageOf 往返一致', () {
      final layout = layout5CoverAlone();
      expect(layout.spreadIndexOf(0), 0);
      expect(layout.spreadIndexOf(1), 1);
      expect(layout.spreadIndexOf(2), 1); // 與 page 1 同一 spread。
      expect(layout.spreadIndexOf(3), 2);
      expect(layout.spreadIndexOf(4), 2);
      expect(layout.anchorPageOf(0), 0);
      expect(layout.anchorPageOf(1), 1);
      expect(layout.anchorPageOf(2), 3);
    });

    test('封面獨立時 nextSpreadAnchor 的步進與邊界', () {
      final layout = layout5CoverAlone();
      expect(layout.nextSpreadAnchor(0), 1); // 封面 → 步進 1。
      expect(layout.nextSpreadAnchor(1), 3); // spread [1,2] → [3,4]，步進 2。
      expect(layout.nextSpreadAnchor(2), 3); // 從右頁(2)出發也對。
      expect(layout.nextSpreadAnchor(3), isNull); // 已在最後一個 spread。
      expect(layout.nextSpreadAnchor(4), isNull);
    });

    test('封面獨立時 previousSpreadAnchor 的步進與邊界', () {
      final layout = layout5CoverAlone();
      expect(layout.previousSpreadAnchor(1), 0);
      expect(layout.previousSpreadAnchor(2), 0);
      expect(layout.previousSpreadAnchor(3), 1);
      expect(layout.previousSpreadAnchor(0), isNull); // 已在封面。
    });

    test('封面不獨立時步進恆為 2', () {
      final layout = layout6NoCover();
      expect(layout.nextSpreadAnchor(0), 2);
      expect(layout.nextSpreadAnchor(2), 4);
      expect(layout.nextSpreadAnchor(4), isNull);
      expect(layout.previousSpreadAnchor(4), 2);
      expect(layout.previousSpreadAnchor(2), 0);
      expect(layout.previousSpreadAnchor(0), isNull);
    });

    test('spreadIndexOf 對超界 pageIndex 安全 clamp，不擲例外', () {
      final layout = layout5CoverAlone();
      expect(() => layout.spreadIndexOf(-1), returnsNormally);
      expect(() => layout.spreadIndexOf(999), returnsNormally);
      expect(layout.spreadIndexOf(-1), layout.spreadIndexOf(0));
      expect(layout.spreadIndexOf(999), layout.spreadIndexOf(4));
    });
  });
}
