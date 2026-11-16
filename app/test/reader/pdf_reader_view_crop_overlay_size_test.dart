import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pump_until_pdf_ready.dart';

/// 回歸測試：手動裁切後頁面放大倍率超過覆蓋圖點陣圖解析度（pageRenderScale 2～3 倍）時，
/// 覆蓋圖必須撐滿整個頁面矩形；否則只佔左上一角，露出底層被壓扁的整頁而看起來「頁面重疊」。
void main() {
  setUp(() => pdfrxInitialize());

  testWidgets('手動裁切＋放大倍率高於覆蓋圖解析度：覆蓋圖撐滿頁面矩形', (tester) async {
    // 寬 1224、dpr 1：裁切後頁寬 306，Fit Width 縮放約 3.8 倍，高於覆蓋圖的 2 倍解析度。
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1224, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var rendered = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => rendered++,
          onError: (_) {},
          pdfPageTurnMode: PdfPageTurnMode.paginated,
          pdfFitMode: PdfFitMode.fitWidth,
          pdfCropMode: PdfCropMode.manual,
          pdfCropRect:
              const PdfCropRect(left: 0.25, top: 0.1, right: 0.75, bottom: 0.9),
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => rendered != 0);
    await pumpUntilPdfReady(
      tester,
      condition: () => find.byType(RawImage).evaluate().isNotEmpty,
      maxIterations: 120,
      delayBetweenPumps: const Duration(milliseconds: 50),
    );
    await tester.pump();

    final controller =
        tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    final pageRect = controller.layout.pageLayouts[0];
    final zoom = controller.currentZoom;
    final overlaySize = tester.getSize(find.byType(RawImage).first);

    expect(zoom, greaterThan(3.0), reason: '前提：放大倍率需高於覆蓋圖解析度');
    expect(overlaySize.width, closeTo(pageRect.width * zoom, 1.0));
    expect(overlaySize.height, closeTo(pageRect.height * zoom, 1.0));
  });
}
