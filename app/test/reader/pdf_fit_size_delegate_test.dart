import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_fit_size_delegate.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

// 單頁 600x800，pdfrx 版面座標含 8 的頁邊距位移。
final _layout = PdfPageLayout(
  pageLayouts: [const Rect.fromLTWH(8, 8, 600, 800)],
  documentSize: const Size(616, 816),
);

Rect _unitRectOf(PdfPageLayout layout, int pageNumber) =>
    layout.pageLayouts[pageNumber - 1];

PdfViewerSizeDelegate _delegate(PdfFitMode mode) => PdfFitSizeDelegateProvider(
      fitMode: mode,
      unitRectOf: _unitRectOf,
      pageMargin: 8,
    ).create();

PdfViewerLayoutMetrics _metrics(
  PdfViewerSizeDelegate delegate, {
  Size view = const Size(400, 400),
  PdfPageLayout? layout,
  int? pageNumber = 1,
}) =>
    delegate.calculateMetrics(
      viewSize: view,
      layout: layout ?? _layout,
      pageNumber: pageNumber,
      pageMargin: 8,
      boundaryMargin: null,
    );

void main() {
  group('最小縮放＝該 Fit 模式的基準（不可縮到基準以下）', () {
    test('Page-fit：min(400/616, 400/816)', () {
      expect(_metrics(_delegate(PdfFitMode.pageFit)).minScale,
          closeTo(400 / 816, 1e-9));
    });

    test('Fit Width：400/616', () {
      expect(_metrics(_delegate(PdfFitMode.fitWidth)).minScale,
          closeTo(400 / 616, 1e-9));
    });

    test('真實比例：1.0', () {
      expect(_metrics(_delegate(PdfFitMode.actualSize)).minScale, 1.0);
    });

    test('基準超過 pdfrx 上限時夾在上限', () {
      final tiny = PdfPageLayout(
        pageLayouts: [const Rect.fromLTWH(8, 8, 10, 10)],
        documentSize: const Size(26, 26),
      );
      expect(
        _metrics(_delegate(PdfFitMode.fitWidth), layout: tiny).minScale,
        kPdfFitMaxZoom,
      );
    });

    test('只改最小縮放，其餘指標沿用 pdfrx 原本的計算', () {
      final legacy = PdfViewerSizeDelegateLegacy(
        maxScale: kPdfFitMaxZoom,
        minScale: 0.1,
        useAlternativeFitScaleAsMinScale: true,
        onePassRenderingScaleThreshold: 200 / 72,
        calculateInitialZoom: null,
      );
      final expected = _metrics(legacy);
      final actual = _metrics(_delegate(PdfFitMode.fitWidth));
      expect(actual.maxScale, expected.maxScale);
      expect(actual.coverScale, expected.coverScale);
      expect(actual.alternativeFitScale, expected.alternativeFitScale);
    });
  });

  group('不可用的輸入退回 pdfrx 原本的指標（Review Focus 1）', () {
    PdfViewerLayoutMetrics legacyMetrics(Size view, int? pageNumber) {
      final legacy = PdfViewerSizeDelegateLegacy(
        maxScale: kPdfFitMaxZoom,
        minScale: 0.1,
        useAlternativeFitScaleAsMinScale: true,
        onePassRenderingScaleThreshold: 200 / 72,
        calculateInitialZoom: null,
      );
      return _metrics(legacy, view: view, pageNumber: pageNumber);
    }

    test('可視尺寸為 0：沿用 pdfrx 的最小縮放，不是 0 或無限大', () {
      final actual = _metrics(_delegate(PdfFitMode.fitWidth), view: Size.zero);
      expect(actual.minScale, legacyMetrics(Size.zero, 1).minScale);
    });

    test('沒有 pivot 頁（pageNumber 為 null）：沿用 pdfrx', () {
      final actual =
          _metrics(_delegate(PdfFitMode.pageFit), pageNumber: null);
      expect(actual.minScale, legacyMetrics(const Size(400, 400), null).minScale);
    });
  });

  group('provider 相等性（pdfrx 靠它判斷要不要重建 delegate）', () {
    test('欄位相同則相等、雜湊相同', () {
      final a = PdfFitSizeDelegateProvider(
          fitMode: PdfFitMode.pageFit, unitRectOf: _unitRectOf, pageMargin: 8);
      final b = PdfFitSizeDelegateProvider(
          fitMode: PdfFitMode.pageFit, unitRectOf: _unitRectOf, pageMargin: 8);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('Fit 模式不同則不相等', () {
      final a = PdfFitSizeDelegateProvider(
          fitMode: PdfFitMode.pageFit, unitRectOf: _unitRectOf, pageMargin: 8);
      final b = PdfFitSizeDelegateProvider(
          fitMode: PdfFitMode.fitWidth, unitRectOf: _unitRectOf, pageMargin: 8);
      expect(a, isNot(b));
    });
  });
}
