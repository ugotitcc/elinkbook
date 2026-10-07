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
  // 最小縮放只會比 pdfrx 原本更寬鬆、不會更嚴格：取 pdfrx 原本的最小縮放與
  // 「目前單元的 Fit 基準」兩者較小者。使用者在連續捲動時可縮得比 Fit Width／
  // 真實比例小，但絕不會出現「最小縮放比目前縮放還大」而在雙指縮放時彈跳。
  PdfViewerLayoutMetrics legacyMetrics(
    Size view,
    int? pageNumber, {
    PdfPageLayout? layout,
  }) {
    final legacy = PdfViewerSizeDelegateLegacy(
      maxScale: kPdfFitMaxZoom,
      minScale: 0.1,
      useAlternativeFitScaleAsMinScale: true,
      onePassRenderingScaleThreshold: 200 / 72,
      calculateInitialZoom: null,
    );
    return _metrics(legacy, view: view, pageNumber: pageNumber, layout: layout);
  }

  group('最小縮放＝min(pdfrx 原本的最小縮放, 目前單元的 Fit 基準)', () {
    test('Page-fit：基準 400/816 與 pdfrx 原本的相同', () {
      expect(_metrics(_delegate(PdfFitMode.pageFit)).minScale,
          closeTo(400 / 816, 1e-9));
    });

    test('Fit Width：基準 400/616 比 pdfrx 原本的大，最小縮放維持 pdfrx 原本的', () {
      final minScale = _metrics(_delegate(PdfFitMode.fitWidth)).minScale;
      expect(minScale, legacyMetrics(const Size(400, 400), 1).minScale);
      expect(minScale, lessThan(400 / 616));
    });

    test('真實比例：基準 1.0 比 pdfrx 原本的大，最小縮放維持 pdfrx 原本的', () {
      final minScale = _metrics(_delegate(PdfFitMode.actualSize)).minScale;
      expect(minScale, legacyMetrics(const Size(400, 400), 1).minScale);
      expect(minScale, lessThan(1.0));
    });

    test('雙頁 spread 單元：基準（整個 spread）比 pdfrx 原本以單頁算的小，採用較小的基準', () {
      final spreadLayout = PdfPageLayout(
        pageLayouts: [
          const Rect.fromLTWH(8, 8, 600, 800),
          const Rect.fromLTWH(616, 8, 600, 800),
        ],
        documentSize: const Size(1224, 816),
      );
      Rect spreadOf(PdfPageLayout l, int pageNumber) =>
          l.pageLayouts[0].expandToInclude(l.pageLayouts[1]);
      final delegate = PdfFitSizeDelegateProvider(
        fitMode: PdfFitMode.pageFit,
        unitRectOf: spreadOf,
        pageMargin: 8,
      ).create();
      const view = Size(400, 800);

      final actual = _metrics(delegate, view: view, layout: spreadLayout);
      final legacyMin =
          legacyMetrics(view, 1, layout: spreadLayout).minScale;
      // 合併矩形 1208x800，含邊距 1224x816：min(400/1224, 800/816)
      expect(actual.minScale, closeTo(400 / 1224, 1e-9));
      expect(actual.minScale, lessThan(legacyMin));
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

    test('可視尺寸為 0：退回 pdfrx 原本的指標，不丟例外', () {
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

  group('嚴格最小縮放（逐頁模式，epic-56 Issue 4）', () {
    PdfViewerSizeDelegate strict(PdfFitMode mode) => PdfFitSizeDelegateProvider(
          fitMode: mode,
          unitRectOf: _unitRectOf,
          pageMargin: 8,
          strictMinScale: true,
        ).create();

    test('最小縮放＝單元基準本身：Fit Width 為 400/616', () {
      expect(_metrics(strict(PdfFitMode.fitWidth)).minScale,
          closeTo(400 / 616, 1e-9));
    });

    test('Page-fit 與真實比例同理', () {
      expect(_metrics(strict(PdfFitMode.pageFit)).minScale,
          closeTo(400 / 816, 1e-9));
      expect(_metrics(strict(PdfFitMode.actualSize)).minScale, 1.0);
    });

    test('比非嚴格模式更嚴格：非嚴格取 min(pdfrx 最小縮放, 基準)，嚴格不會比它小', () {
      final loose = _metrics(_delegate(PdfFitMode.fitWidth)).minScale;
      final tight = _metrics(strict(PdfFitMode.fitWidth)).minScale;
      expect(tight, greaterThanOrEqualTo(loose));
      expect(tight, closeTo(400 / 616, 1e-9));
    });

    test('可視尺寸為 0：退回 pdfrx 原本的指標，不丟例外', () {
      expect(
        () => _metrics(strict(PdfFitMode.fitWidth), view: Size.zero),
        returnsNormally,
      );
    });

    test('provider 相等性包含 strictMinScale', () {
      final a = PdfFitSizeDelegateProvider(
          fitMode: PdfFitMode.pageFit,
          unitRectOf: _unitRectOf,
          pageMargin: 8,
          strictMinScale: true);
      final b = PdfFitSizeDelegateProvider(
          fitMode: PdfFitMode.pageFit,
          unitRectOf: _unitRectOf,
          pageMargin: 8);
      final c = PdfFitSizeDelegateProvider(
          fitMode: PdfFitMode.pageFit,
          unitRectOf: _unitRectOf,
          pageMargin: 8,
          strictMinScale: true);
      expect(a, isNot(b));
      expect(a, c);
      expect(a.hashCode, c.hashCode);
    });
  });

  group('裁切後小版面恆滿足 minScale<=maxScale（epic-54 Issue 18）', () {
    // 智慧裁切後的版面：頁面只剩 20x20（裁切框內），400x400 視窗下 Fit 基準
    // 遠超 kPdfFitMaxZoom；TCL 14 真機實測 pdfrx 原生 minScale=8.0407 >
    // maxScale=8.0，透傳即觸發 InteractiveViewer 斷言崩潰。
    final tinyLayout = PdfPageLayout(
      pageLayouts: const [Rect.fromLTWH(8, 8, 20, 20)],
      documentSize: const Size(36, 36),
    );
    PdfViewerSizeDelegate strictTiny(PdfFitMode mode) =>
        PdfFitSizeDelegateProvider(
          fitMode: mode,
          unitRectOf: _unitRectOf,
          pageMargin: 8,
          strictMinScale: true,
        ).create();

    // 說明：有效頁路徑的 zoom 已被 _zoomFor 以 kPdfFitMaxZoom 箝位（zoom <=
    // maxScale），所以前後兩案（嚴格模式有效頁、非嚴格模式）是「不變式」守衛，
    // 本身拿掉 _clampedMetrics 仍會通過；真正咬住箝位的是中間「pivot 頁無效時
    // 透傳」案例（智慧重開崩潰路徑，已用拿掉箝位的突變驗證確認會紅）。
    test('嚴格模式有效頁：minScale<=maxScale（不變式）', () {
      final m =
          _metrics(strictTiny(PdfFitMode.pageFit), layout: tinyLayout);
      expect(m.minScale, lessThanOrEqualTo(m.maxScale));
    });

    test('pivot 頁無效時透傳亦須滿足 minScale<=maxScale（智慧重開崩潰路徑）', () {
      final m = _metrics(strictTiny(PdfFitMode.pageFit),
          layout: tinyLayout, pageNumber: null);
      expect(m.minScale, lessThanOrEqualTo(m.maxScale));
    });

    test('非嚴格模式小版面同理（不變式）', () {
      final m = _metrics(_delegate(PdfFitMode.pageFit), layout: tinyLayout);
      expect(m.minScale, lessThanOrEqualTo(m.maxScale));
    });
  });
}
