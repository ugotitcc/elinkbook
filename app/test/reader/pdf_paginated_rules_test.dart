import 'dart:ui';

import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_paginated_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const view = Size(400, 800);

  group('fitBaseScale：縮放基準（規則 1）', () {
    test('Page-fit：寬高各自的比例取較小者（寬度受限）', () {
      // 1000x500 放進 400x800：寬 0.4、高 1.6 → 0.4
      expect(
        fitBaseScale(mode: PdfFitMode.pageFit, contentSize: const Size(1000, 500), viewSize: view),
        closeTo(0.4, 1e-9),
      );
    });

    test('Page-fit：高度受限', () {
      // 400x2000 放進 400x800：寬 1.0、高 0.4 → 0.4
      expect(
        fitBaseScale(mode: PdfFitMode.pageFit, contentSize: const Size(400, 2000), viewSize: view),
        closeTo(0.4, 1e-9),
      );
    });

    test('Page-fit：寬高比例相同時兩者一致', () {
      expect(
        fitBaseScale(mode: PdfFitMode.pageFit, contentSize: const Size(500, 1000), viewSize: view),
        closeTo(0.8, 1e-9),
      );
    });

    test('Fit Width：可視寬度除以內容寬度，與高度無關', () {
      expect(
        fitBaseScale(mode: PdfFitMode.fitWidth, contentSize: const Size(500, 1000), viewSize: view),
        closeTo(0.8, 1e-9),
      );
      expect(
        fitBaseScale(mode: PdfFitMode.fitWidth, contentSize: const Size(500, 100000), viewSize: view),
        closeTo(0.8, 1e-9),
      );
    });

    test('Fit Width：內容比可視寬度窄時會放大', () {
      expect(
        fitBaseScale(mode: PdfFitMode.fitWidth, contentSize: const Size(200, 100), viewSize: view),
        closeTo(2.0, 1e-9),
      );
    });

    test('真實比例：恆為 1.0，不論內容與可視尺寸', () {
      expect(
        fitBaseScale(mode: PdfFitMode.actualSize, contentSize: const Size(1000, 3000), viewSize: view),
        1.0,
      );
      expect(
        fitBaseScale(mode: PdfFitMode.actualSize, contentSize: const Size(10, 10), viewSize: view),
        1.0,
      );
    });
  });

  group('maxVerticalScroll：頁內最大捲動量（規則 2）', () {
    test('縮放後內容比可視高度高：回傳差值', () {
      // 500x2000 縮放 0.8 → 高 1600，可視 800 → 800
      expect(
        maxVerticalScroll(contentSize: const Size(500, 2000), scale: 0.8, viewSize: view),
        closeTo(800, 1e-9),
      );
    });

    test('剛好等高：0', () {
      expect(
        maxVerticalScroll(contentSize: const Size(500, 1000), scale: 0.8, viewSize: view),
        closeTo(0, 1e-9),
      );
    });

    test('比可視高度矮：0，不為負', () {
      expect(
        maxVerticalScroll(contentSize: const Size(500, 500), scale: 0.8, viewSize: view),
        0,
      );
    });
  });

  group('fitOrigin：內容對齊起點（規則 1）', () {
    test('兩個維度都比可視範圍小：置中', () {
      expect(
        fitOrigin(
          contentSize: const Size(200, 100),
          scale: 1.0,
          viewSize: view,
          direction: DualPageDirection.ltr,
        ),
        const Offset(100, 350),
      );
    });

    test('Fit Width 縱向溢出：橫向剛好滿版，縱向從頁頂開始', () {
      expect(
        fitOrigin(
          contentSize: const Size(500, 3000),
          scale: 0.8,
          viewSize: view,
          direction: DualPageDirection.ltr,
        ),
        const Offset(0, 0),
      );
    });

    test('真實比例橫向溢出：左到右靠左（起點 0）', () {
      expect(
        fitOrigin(
          contentSize: const Size(1000, 3000),
          scale: 1.0,
          viewSize: view,
          direction: DualPageDirection.ltr,
        ),
        const Offset(0, 0),
      );
    });

    test('真實比例橫向溢出：右到左靠右（右緣對齊可視右緣）', () {
      expect(
        fitOrigin(
          contentSize: const Size(1000, 3000),
          scale: 1.0,
          viewSize: view,
          direction: DualPageDirection.rtl,
        ),
        const Offset(-600, 0),
      );
    });
  });

  group('fitZoomForUnit：單元＋頁邊距＋可視尺寸 → 夾住上限的縮放值', () {
    test('內容尺寸含頁邊距（各邊加 margin）', () {
      // 單元 600x800 加 8 邊距 → 616x816；Page-fit 放進 400x400：min(400/616, 400/816)
      final zoom = fitZoomForUnit(
        mode: PdfFitMode.pageFit,
        unitRect: const Rect.fromLTWH(8, 8, 600, 800),
        pageMargin: 8,
        viewSize: const Size(400, 400),
        maxZoom: 8,
      );
      expect(zoom, closeTo(400 / 816, 1e-9));
    });

    test('Fit Width 用含邊距的寬度', () {
      final zoom = fitZoomForUnit(
        mode: PdfFitMode.fitWidth,
        unitRect: const Rect.fromLTWH(8, 8, 600, 800),
        pageMargin: 8,
        viewSize: const Size(400, 400),
        maxZoom: 8,
      );
      expect(zoom, closeTo(400 / 616, 1e-9));
    });

    test('超過上限時夾在上限', () {
      final zoom = fitZoomForUnit(
        mode: PdfFitMode.fitWidth,
        unitRect: const Rect.fromLTWH(8, 8, 10, 10),
        pageMargin: 8,
        viewSize: const Size(400, 400),
        maxZoom: 8,
      );
      expect(zoom, 8);
    });

    test('可視尺寸為 0（版面尚未量測）：回傳 null', () {
      expect(
        fitZoomForUnit(
          mode: PdfFitMode.pageFit,
          unitRect: const Rect.fromLTWH(8, 8, 600, 800),
          pageMargin: 8,
          viewSize: Size.zero,
          maxZoom: 8,
        ),
        isNull,
      );
    });

    test('內容尺寸為 0：回傳 null，不是無限大', () {
      expect(
        fitZoomForUnit(
          mode: PdfFitMode.fitWidth,
          unitRect: Rect.zero,
          pageMargin: 0,
          viewSize: const Size(400, 400),
          maxZoom: 8,
        ),
        isNull,
      );
    });

    test('真實比例固定 1.0（仍受上限夾住）', () {
      expect(
        fitZoomForUnit(
          mode: PdfFitMode.actualSize,
          unitRect: const Rect.fromLTWH(8, 8, 600, 800),
          pageMargin: 8,
          viewSize: const Size(400, 400),
          maxZoom: 8,
        ),
        1.0,
      );
    });
  });

  group('stackPageRects：單頁堆疊版面（與 pdfrx 預設版面一致）', () {
    test('頁面水平置中、由 margin 起依頁高加 margin 累加', () {
      final r = stackPageRects(
        pageSizes: const [Size(595, 842), Size(300, 400)],
        margin: 8,
      );
      expect(r.rects[0], const Rect.fromLTWH(8, 8, 595, 842));
      expect(r.rects[1], const Rect.fromLTWH(155.5, 858, 300, 400));
      expect(r.documentSize, const Size(611, 1266));
    });
  });

  group('isolatePaginatedUnits：逐頁幾何隔離（間距公式）', () {
    // 兩頁 A4 595x842，margin 8：內容方框（含邊距）611x858，第 1 頁方框 0～858。
    final stacked = stackPageRects(
      pageSizes: const [Size(595, 842), Size(595, 842)],
      margin: 8,
    );

    PaginatedLayout isolate({
      required Size view,
      PdfFitMode mode = PdfFitMode.pageFit,
      List<Rect>? rects,
      List<int>? pageToUnit,
      List<Rect>? baseUnits,
      Size? doc,
      double maxZoom = 8,
    }) =>
        isolatePaginatedUnits(
          pageRects: rects ?? stacked.rects,
          pageToUnit: pageToUnit ?? const [0, 1],
          baseUnitRects: baseUnits,
          documentSize: doc ?? stacked.documentSize,
          margin: 8,
          mode: mode,
          viewSize: view,
          maxZoom: maxZoom,
        );

    double boxGap(PaginatedLayout l, int a, int b) =>
        l.unitRects[b].inflate(8).top - l.unitRects[a].inflate(8).bottom;

    test('窄長視窗 300x900、Page-fit：基準 300/611，超出量 487.5，間距 537.5', () {
      final l = isolate(view: const Size(300, 900));
      expect(boxGap(l, 0, 1), closeTo(537.5, 1e-6));
      // 第 1 單元不動；第 2 頁整體下移 545.5（1403.5 - 858）。
      expect(l.pageRects[0], const Rect.fromLTWH(8, 8, 595, 842));
      expect(l.pageRects[1].top, closeTo(1403.5, 1e-6));
      expect(l.pageRects[1].left, 8);
      expect(l.unitRects[1].top, closeTo(1403.5, 1e-6));
      expect(l.documentSize.width, 611);
      expect(l.documentSize.height, closeTo(2253.5, 1e-6));
      expect(l.unitAnchorPages, [0, 1]);
      expect(l.pageToUnit, [0, 1]);
      expect(l.unitCount, 2);
    });

    test('Fit Width 在同一視窗下基準相同，間距相同', () {
      final l = isolate(view: const Size(300, 900), mode: PdfFitMode.fitWidth);
      expect(boxGap(l, 0, 1), closeTo(537.5, 1e-6));
    });

    test('高度受限（300x300、Page-fit）：超出量 0，間距只剩 50', () {
      final l = isolate(view: const Size(300, 300));
      expect(boxGap(l, 0, 1), closeTo(50, 1e-6));
      expect(l.pageRects[1].top, closeTo(916, 1e-6)); // 858 + 58
      expect(l.documentSize.height, closeTo(1766, 1e-6)); // 908 + 858
    });

    test('真實比例（基準 1.0）：超出量 (900 - 858) / 2 = 21，間距 71', () {
      final l = isolate(view: const Size(300, 900), mode: PdfFitMode.actualSize);
      expect(boxGap(l, 0, 1), closeTo(71, 1e-6));
      expect(l.pageRects[1].top, closeTo(937, 1e-6));
      expect(l.documentSize.height, closeTo(1787, 1e-6));
    });

    test('間距取兩側超出量較大者，與單元順序無關（Review Focus 1）', () {
      // 小頁 100x100（超出量 116）與 A4（超出量 487.5），視窗 300x900、Page-fit。
      for (final sizes in [
        const [Size(100, 100), Size(595, 842)],
        const [Size(595, 842), Size(100, 100)],
      ]) {
        final s = stackPageRects(pageSizes: sizes, margin: 8);
        final l = isolate(
          view: const Size(300, 900),
          rects: s.rects,
          doc: s.documentSize,
        );
        expect(boxGap(l, 0, 1), closeTo(537.5, 1e-6));
      }
    });

    test('spread 單元：頁面相對位置不變、整個單元一起移動，錨點為單元第一頁', () {
      // 兩個 spread，各 2 頁 300x400，頁間距 8。
      const rects = [
        Rect.fromLTWH(8, 8, 300, 400),
        Rect.fromLTWH(316, 8, 300, 400),
        Rect.fromLTWH(8, 416, 300, 400),
        Rect.fromLTWH(316, 416, 300, 400),
      ];
      final l = isolate(
        view: const Size(300, 900),
        rects: rects,
        pageToUnit: const [0, 0, 1, 1],
        doc: const Size(624, 824),
      );
      // 單元內容方框 624x416，基準 300/624，超出量 (1872 - 416) / 2 = 728，間距 778。
      expect(l.unitRects[0], const Rect.fromLTWH(8, 8, 608, 400));
      expect(boxGap(l, 0, 1), closeTo(778, 1e-6));
      expect(l.pageRects[0], rects[0]);
      expect(l.pageRects[1], rects[1]);
      expect(l.pageRects[2].top, closeTo(1202, 1e-6));
      expect(l.pageRects[3].top, closeTo(1202, 1e-6));
      expect(l.pageRects[3].left, 316);
      expect(l.unitAnchorPages, [0, 2]);
      expect(l.documentSize.height, closeTo(1610, 1e-6));
    });

    test('單頁 spread（封面獨立）：單元矩形取傳入的 baseUnitRects，與雙頁 spread 同寬、基準一致（C-1）', () {
      // 內容寬 600：封面（第 0 頁）在 spread 內水平置中，內頁兩頁並排。
      const rects = [
        Rect.fromLTWH(158, 8, 300, 400),
        Rect.fromLTWH(8, 416, 300, 400),
        Rect.fromLTWH(308, 416, 300, 400),
      ];
      const baseUnits = [
        Rect.fromLTWH(8, 8, 600, 400),
        Rect.fromLTWH(8, 416, 600, 400),
      ];
      final l = isolate(
        view: const Size(300, 900),
        rects: rects,
        pageToUnit: const [0, 1, 1],
        baseUnits: baseUnits,
        doc: const Size(616, 824),
      );
      // 兩個單元方框都是 616x416：基準同為 300/616，超出量 (1848 - 416) / 2 = 716，間距 766。
      expect(l.unitRects[0].width, 600);
      expect(l.unitRects[1].width, 600);
      expect(boxGap(l, 0, 1), closeTo(766, 1e-6));
      // 封面頁維持置中（x 不變），內頁整體下移 774（1190 - 416）。
      expect(l.pageRects[0], rects[0]);
      expect(l.pageRects[1].top, closeTo(1190, 1e-6));
      expect(l.pageRects[2].top, closeTo(1190, 1e-6));
      expect(l.unitAnchorPages, [0, 1]);
    });

    test('視窗尺寸為無限大（無界限制）：不移動任何頁面，不拋例外（M-3）', () {
      final l = isolate(view: const Size(double.infinity, double.infinity));
      expect(l.pageRects, stacked.rects);
    });

    test('基準被 maxZoom 夾住時，以夾住後的縮放算超出量', () {
      // 10x10 小頁、Fit Width、視窗 400x400：方框 26x26，基準 15.38 夾成 8，
      // 超出量 (400/8 - 26) / 2 = 12，間距 62。
      final s = stackPageRects(
        pageSizes: const [Size(10, 10), Size(10, 10)],
        margin: 8,
      );
      final l = isolate(
        view: const Size(400, 400),
        mode: PdfFitMode.fitWidth,
        rects: s.rects,
        doc: s.documentSize,
      );
      expect(boxGap(l, 0, 1), closeTo(62, 1e-6));
    });

    test('視窗尺寸為 0（尚未量測）：不移動任何頁面，單元矩形仍為頁面聯集（Review Focus 5）', () {
      final l = isolate(view: Size.zero);
      expect(l.pageRects, stacked.rects);
      expect(l.documentSize, stacked.documentSize);
      expect(l.unitRects, stacked.rects);
    });

    test('單頁文件：不拋例外，單元只有一個', () {
      final s = stackPageRects(pageSizes: const [Size(595, 842)], margin: 8);
      final l = isolate(
        view: const Size(300, 900),
        rects: s.rects,
        pageToUnit: const [0],
        doc: s.documentSize,
      );
      expect(l.unitCount, 1);
      expect(l.pageRects, s.rects);
    });
  });

  group('clampPagedViewport：把縮放與平移鎖在單元內（規則 1、2、6）', () {
    const view = Size(400, 800);
    // 單元方框 500x2000，Fit Width 基準 0.8：可視 500x1000，橫向剛好等寬。
    const content = Rect.fromLTWH(0, 0, 500, 2000);

    PagedViewport clamp({
      Rect unit = content,
      double base = 0.8,
      double zoom = 0.8,
      Offset? cand,
      DualPageDirection dir = DualPageDirection.ltr,
    }) =>
        clampPagedViewport(
          unitContent: unit,
          viewSize: view,
          baseZoom: base,
          maxZoom: 8,
          zoom: zoom,
          candidateTopLeft: cand,
          direction: dir,
        );

    test('縱向溢出：候選位置在範圍內則保留', () {
      final v = clamp(cand: const Offset(0, 300));
      expect(v.zoom, closeTo(0.8, 1e-9));
      expect(v.topLeft.dx, closeTo(0, 1e-9));
      expect(v.topLeft.dy, closeTo(300, 1e-9));
    });

    test('縱向溢出：超出範圍時夾在 0 與（單元高 - 可視高）', () {
      expect(clamp(cand: const Offset(0, 5000)).topLeft.dy, closeTo(1000, 1e-9));
      expect(clamp(cand: const Offset(0, -50)).topLeft.dy, closeTo(0, 1e-9));
    });

    test('沒有候選位置（跳轉）：縱向落在頂端', () {
      expect(clamp().topLeft.dy, closeTo(0, 1e-9));
    });

    test('候選位置為 NaN 或無限大：視同沒有候選位置，不污染結果（M-2）', () {
      final v = clamp(cand: const Offset(double.nan, double.infinity));
      expect(v.topLeft.dx.isFinite, isTrue);
      expect(v.topLeft.dy, closeTo(0, 1e-9));
    });

    test('縮放低於基準被拉回基準（Review Focus 4）', () {
      expect(clamp(zoom: 0.1).zoom, closeTo(0.8, 1e-9));
    });

    test('縮放超過上限被夾在 maxZoom', () {
      final v = clamp(zoom: 20, cand: const Offset(100, 100));
      expect(v.zoom, 8);
      // 可視 50x100，橫向範圍 0～450，縱向 0～1900。
      expect(v.topLeft, const Offset(100, 100));
    });

    test('放大後橫向溢出：候選位置夾在單元左右緣內', () {
      final v = clamp(zoom: 8, cand: const Offset(9999, 0));
      expect(v.topLeft.dx, closeTo(450, 1e-9));
    });

    test('兩個維度都比可視範圍小：置中（可視左上角為負）', () {
      // 內容 200x100，視窗 400x800，Page-fit 基準 2，可視 200x400。
      final v = clampPagedViewport(
        unitContent: const Rect.fromLTWH(0, 0, 200, 100),
        viewSize: view,
        baseZoom: 2,
        maxZoom: 8,
        zoom: 2,
        candidateTopLeft: const Offset(77, 77),
        direction: DualPageDirection.ltr,
      );
      expect(v.topLeft.dx, closeTo(0, 1e-9));
      expect(v.topLeft.dy, closeTo(-150, 1e-9));
    });

    test('單元不在文件原點：置中與頂端都以單元方框為準', () {
      final v = clamp(unit: const Rect.fromLTWH(100, 5000, 500, 2000));
      expect(v.topLeft.dx, closeTo(100, 1e-9));
      expect(v.topLeft.dy, closeTo(5000, 1e-9));
      expect(
        clamp(unit: const Rect.fromLTWH(100, 5000, 500, 2000), cand: const Offset(0, 99999))
            .topLeft
            .dy,
        closeTo(6000, 1e-9),
      );
    });

    test('真實比例橫向溢出：沒有候選位置時依方向決定起始側（左到右靠左、右到左靠右）', () {
      const wide = Rect.fromLTWH(0, 0, 1000, 3000);
      final ltr = clamp(unit: wide, base: 1, zoom: 1);
      final rtl = clamp(unit: wide, base: 1, zoom: 1, dir: DualPageDirection.rtl);
      expect(ltr.topLeft.dx, closeTo(0, 1e-9));
      expect(rtl.topLeft.dx, closeTo(600, 1e-9));
      expect(rtl.topLeft.dy, closeTo(0, 1e-9));
    });

    test('真實比例橫向溢出：有候選位置時夾在 0～（單元寬 - 可視寬）', () {
      const wide = Rect.fromLTWH(0, 0, 1000, 3000);
      expect(clamp(unit: wide, base: 1, zoom: 1, cand: const Offset(300, 0)).topLeft.dx,
          closeTo(300, 1e-9));
      expect(clamp(unit: wide, base: 1, zoom: 1, cand: const Offset(900, 0)).topLeft.dx,
          closeTo(600, 1e-9));
      expect(clamp(unit: wide, base: 1, zoom: 1, cand: const Offset(-5, 0)).topLeft.dx,
          closeTo(0, 1e-9));
    });
  });

  group('pagedAdjacentUnit：相對步進（規則 3、4 的 Page-fit 子集）', () {
    test('中間單元：往前／往後各移一個單元', () {
      expect(pagedAdjacentUnit(currentUnit: 2, unitCount: 5, forward: true), 3);
      expect(pagedAdjacentUnit(currentUnit: 2, unitCount: 5, forward: false), 1);
    });

    test('最後一個單元往後、第一個單元往前：無動作（Review Focus 5）', () {
      expect(pagedAdjacentUnit(currentUnit: 4, unitCount: 5, forward: true), isNull);
      expect(pagedAdjacentUnit(currentUnit: 0, unitCount: 5, forward: false), isNull);
    });

    test('只有一個單元或沒有單元：兩個方向都無動作', () {
      expect(pagedAdjacentUnit(currentUnit: 0, unitCount: 1, forward: true), isNull);
      expect(pagedAdjacentUnit(currentUnit: 0, unitCount: 1, forward: false), isNull);
      expect(pagedAdjacentUnit(currentUnit: 0, unitCount: 0, forward: true), isNull);
    });
  });
}
