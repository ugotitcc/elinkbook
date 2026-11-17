import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pump_until_pdf_ready.dart';

/// Issue 45：裁切編輯期間（`cropEditModeActive == true`）暫時顯示未裁切完整頁面，
/// 不改動 `pdfCropMode` / `pdfCropRect`，也不觸發重複自動偵測或丟棄加粗疊圖。
void main() {
  setUp(() => pdfrxInitialize());

  const nonUniformCrop = PdfCropRect(
    left: 0.0,
    top: 0.2,
    right: 1.0,
    bottom: 0.8,
  );

  Future<GlobalKey<State<PdfReaderView>>> pumpPdf(
    WidgetTester tester, {
    GlobalKey<State<PdfReaderView>>? key,
    PdfCropMode pdfCropMode = PdfCropMode.none,
    PdfCropRect? pdfCropRect,
    PdfFitMode? pdfFitMode,
    bool cropEditModeActive = false,
    double pdfBoldStrength = 0.0,
    ValueChanged<PdfCropRect>? onCropRectComputed,
    VoidCallback? onReady,
    bool waitUntilReady = true,
  }) async {
    final viewKey = key ?? GlobalKey<State<PdfReaderView>>();
    var rendered = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          key: viewKey,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          pdfCropMode: pdfCropMode,
          pdfCropRect: pdfCropRect,
          pdfFitMode: pdfFitMode,
          cropEditModeActive: cropEditModeActive,
          pdfBoldStrength: pdfBoldStrength,
          onCropRectComputed: onCropRectComputed,
          onPageRendered: () {
            rendered++;
            onReady?.call();
          },
          onError: (_) {},
        ),
      ),
    );
    if (waitUntilReady) {
      await pumpUntilPdfReady(tester, condition: () => rendered != 0);
      await tester.pump();
    }
    return viewKey;
  }

  void setupLandscapeViewport(WidgetTester tester) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1224, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  double firstPageAspectRatio(GlobalKey<State<PdfReaderView>> key) {
    final rects = PdfReaderView.visiblePageRects(key);
    expect(rects, isNotEmpty);
    final r = rects.first.rectInViewer;
    return r.width / r.height;
  }

  double firstPageWidth(GlobalKey<State<PdfReaderView>> key) {
    final rects = PdfReaderView.visiblePageRects(key);
    expect(rects, isNotEmpty);
    return rects.first.rectInViewer.width;
  }

  testWidgets(
    '已有手動裁切，cropEditModeActive 為 true 時，可見頁面長寬比等於未裁切的頁面',
    (tester) async {
      setupLandscapeViewport(tester);
      final key = GlobalKey<State<PdfReaderView>>();

      await pumpPdf(
        tester,
        key: key,
        pdfCropMode: PdfCropMode.none,
      );
      final aspectFull = firstPageAspectRatio(key);

      await pumpPdf(
        tester,
        key: key,
        pdfCropMode: PdfCropMode.manual,
        pdfCropRect: nonUniformCrop,
        cropEditModeActive: false,
        waitUntilReady: false,
      );
      await pumpUntilPdfReady(
        tester,
        condition: () =>
            (firstPageAspectRatio(key) - aspectFull).abs() > 1e-3,
      );
      final aspectCropped = firstPageAspectRatio(key);
      expect(aspectCropped, isNot(closeTo(aspectFull, 1e-3)));

      await pumpPdf(
        tester,
        key: key,
        pdfCropMode: PdfCropMode.manual,
        pdfCropRect: nonUniformCrop,
        cropEditModeActive: true,
        waitUntilReady: false,
      );
      await pumpUntilPdfReady(
        tester,
        condition: () =>
            (firstPageAspectRatio(key) - aspectFull).abs() < 1e-3,
      );
      expect(firstPageAspectRatio(key), closeTo(aspectFull, 1e-3));
    },
  );

  testWidgets(
    'cropEditModeActive 切回 false 後，恢復為裁切後的頁面寬度',
    (tester) async {
      setupLandscapeViewport(tester);
      final key = GlobalKey<State<PdfReaderView>>();

      await pumpPdf(
        tester,
        key: key,
        pdfCropMode: PdfCropMode.manual,
        pdfCropRect: nonUniformCrop,
        pdfFitMode: PdfFitMode.pageFit,
        cropEditModeActive: false,
      );
      final croppedWidth = firstPageWidth(key);

      await pumpPdf(
        tester,
        key: key,
        pdfCropMode: PdfCropMode.manual,
        pdfCropRect: nonUniformCrop,
        pdfFitMode: PdfFitMode.pageFit,
        cropEditModeActive: true,
        waitUntilReady: false,
      );
      await pumpUntilPdfReady(
        tester,
        condition: () => (firstPageWidth(key) - croppedWidth).abs() > 1.0,
      );
      expect(firstPageWidth(key), isNot(closeTo(croppedWidth, 1.0)));

      await pumpPdf(
        tester,
        key: key,
        pdfCropMode: PdfCropMode.manual,
        pdfCropRect: nonUniformCrop,
        pdfFitMode: PdfFitMode.pageFit,
        cropEditModeActive: false,
        waitUntilReady: false,
      );
      await pumpUntilPdfReady(
        tester,
        condition: () => (firstPageWidth(key) - croppedWidth).abs() < 1.0,
      );
      expect(firstPageWidth(key), closeTo(croppedWidth, 1.0));
    },
  );

  testWidgets(
    'autoDetect 且矩形已快取，cropEditModeActive 為 true 時不呼叫 onCropRectComputed',
    (tester) async {
      setupLandscapeViewport(tester);
      final key = GlobalKey<State<PdfReaderView>>();
      var computedCount = 0;

      await pumpPdf(
        tester,
        key: key,
        pdfCropMode: PdfCropMode.autoDetect,
        pdfCropRect: nonUniformCrop,
        cropEditModeActive: false,
        onCropRectComputed: (_) => computedCount++,
      );
      final aspectCropped = firstPageAspectRatio(key);

      await pumpPdf(
        tester,
        key: key,
        pdfCropMode: PdfCropMode.autoDetect,
        pdfCropRect: nonUniformCrop,
        cropEditModeActive: true,
        onCropRectComputed: (_) => computedCount++,
        waitUntilReady: false,
      );
      await pumpUntilPdfReady(
        tester,
        condition: () =>
            (firstPageAspectRatio(key) - aspectCropped).abs() > 1e-3,
      );
      // 額外跑幾輪讓 pageOverlaysBuilder / _maybeDetectCropRect 有機會執行
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(computedCount, 0);
    },
  );

  testWidgets(
    '已有裁切且加粗強度大於 0，切換 cropEditModeActive 後疊圖仍會產生，不被丟棄',
    (tester) async {
      setupLandscapeViewport(tester);
      final key = GlobalKey<State<PdfReaderView>>();

      await pumpPdf(
        tester,
        key: key,
        pdfCropMode: PdfCropMode.manual,
        pdfCropRect: nonUniformCrop,
        cropEditModeActive: false,
        pdfBoldStrength: 1.0,
      );
      await pumpUntilPdfReady(
        tester,
        condition: () => find.byType(RawImage).evaluate().isNotEmpty,
        maxIterations: 120,
        delayBetweenPumps: const Duration(milliseconds: 50),
      );
      await tester.pump();
      final croppedOverlay =
          tester.widget<RawImage>(find.byType(RawImage).first).image!;
      final croppedOverlayAspect =
          croppedOverlay.width / croppedOverlay.height;

      await pumpPdf(
        tester,
        key: key,
        pdfCropMode: PdfCropMode.manual,
        pdfCropRect: nonUniformCrop,
        cropEditModeActive: true,
        pdfBoldStrength: 1.0,
        waitUntilReady: false,
      );
      await pumpUntilPdfReady(
        tester,
        condition: () {
          final images = find.byType(RawImage).evaluate();
          if (images.isEmpty) return false;
          final img = (images.first.widget as RawImage).image;
          if (img == null) return false;
          final aspect = img.width / img.height;
          return (aspect - croppedOverlayAspect).abs() > 0.1;
        },
        maxIterations: 120,
        delayBetweenPumps: const Duration(milliseconds: 50),
      );
      await tester.pump();
      final fullOverlay =
          tester.widget<RawImage>(find.byType(RawImage).first).image!;
      expect(
        fullOverlay.width / fullOverlay.height,
        isNot(closeTo(croppedOverlayAspect, 0.1)),
      );
      expect(
        fullOverlay.width / fullOverlay.height,
        closeTo(firstPageAspectRatio(key), 0.05),
      );
    },
  );
}
