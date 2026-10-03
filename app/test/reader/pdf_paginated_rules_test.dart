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
}
