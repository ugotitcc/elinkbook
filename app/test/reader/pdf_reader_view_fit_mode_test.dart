import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pump_until_pdf_ready.dart';

const _viewSize = Size(400, 400);
const _margin = 8.0;

/// 用 400x400 的固定可視範圍，讓 Page-fit（高度受限）與 Fit Width 的值不同。
Widget _app(PdfReaderView child, {Size size = _viewSize}) => MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: child,
        ),
      ),
    );

PdfReaderView _view({
  required void Function() onRendered,
  PdfFitMode? fit,
  String file = 'test/fixtures/sample.pdf',
  DualPageMode dualMode = DualPageMode.never,
  bool coverAlone = true,
  PdfCropMode cropMode = PdfCropMode.none,
  PdfCropRect? cropRect,
  Key? key,
}) =>
    PdfReaderView(
      key: key ?? const ValueKey('fit_view'),
      filePath: file,
      onPageRendered: onRendered,
      onError: (_) {},
      pdfFitMode: fit,
      dualPageMode: dualMode,
      dualPageCoverAlone: coverAlone,
      pdfCropMode: cropMode,
      pdfCropRect: cropRect,
    );

PdfViewerController _controllerOf(WidgetTester tester) =>
    tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;

Future<Size> _pageSize(WidgetTester tester, String path, int index) async {
  final size = await tester.runAsync(() async {
    final doc = await PdfDocument.openFile(path);
    final page = doc.pages[index];
    final s = Size(page.width, page.height);
    await doc.dispose();
    return s;
  });
  return size!;
}

Future<PdfViewerController> _open(
  WidgetTester tester, {
  PdfFitMode? fit,
  String file = 'test/fixtures/sample.pdf',
  DualPageMode dualMode = DualPageMode.never,
  bool coverAlone = true,
  PdfCropMode cropMode = PdfCropMode.none,
  PdfCropRect? cropRect,
  Size size = _viewSize,
  Key? key,
}) async {
  var rendered = 0;
  await tester.pumpWidget(_app(_view(
    onRendered: () => rendered++,
    fit: fit,
    file: file,
    dualMode: dualMode,
    coverAlone: coverAlone,
    cropMode: cropMode,
    cropRect: cropRect,
    key: key,
  ), size: size));
  await pumpUntilPdfReady(tester, condition: () => rendered != 0);
  // 初始縮放在版面初始化後才套用，再多等幾輪讓它落定。
  await pumpUntilPdfReady(tester, maxIterations: 5);
  return _controllerOf(tester);
}

void main() {
  setUp(() => pdfrxInitialize());

  testWidgets('不傳 pdfFitMode：沿用 pdfrx 預設（初始縮放＝coverScale），零回歸（Review Focus 5）',
      (tester) async {
    final c = await _open(tester);
    expect(c.currentZoom, closeTo(c.coverScale, 0.001));
  });

  testWidgets('Page-fit：整頁（含頁邊距）完整放進可視範圍，最小縮放同值', (tester) async {
    final page = await _pageSize(tester, 'test/fixtures/sample.pdf', 0);
    final expected = _minOf(_viewSize.width / (page.width + _margin * 2),
        _viewSize.height / (page.height + _margin * 2));
    final c = await _open(tester, fit: PdfFitMode.pageFit);
    expect(c.currentZoom, closeTo(expected, 0.001));
    expect(c.minScale, closeTo(expected, 0.001));
  });

  testWidgets('Fit Width：頁寬（含頁邊距）滿版，且與 Page-fit 的值不同', (tester) async {
    final page = await _pageSize(tester, 'test/fixtures/sample.pdf', 0);
    final fitWidth = _viewSize.width / (page.width + _margin * 2);
    final pageFit = _minOf(fitWidth,
        _viewSize.height / (page.height + _margin * 2));
    // 前提：這份 fixture 在 400x400 下兩種模式要有鑑別力。
    expect(fitWidth - pageFit, greaterThan(0.01));

    final c = await _open(tester, fit: PdfFitMode.fitWidth);
    expect(c.currentZoom, closeTo(fitWidth, 0.001));
    // 最小縮放只會比 pdfrx 原本更寬鬆：不大於基準（見 delegate 說明）。
    expect(c.minScale, lessThanOrEqualTo(fitWidth + 0.001));
  });

  testWidgets('真實比例：縮放 1.0，最小縮放不大於 1.0', (tester) async {
    final c = await _open(tester, fit: PdfFitMode.actualSize);
    expect(c.currentZoom, closeTo(1.0, 0.001));
    expect(c.minScale, lessThanOrEqualTo(1.0 + 0.001));
  });

  testWidgets('雙頁模式：以 spread 合併矩形（含邊距）算基準（Review Focus 4）', (tester) async {
    final c = await _open(
      tester,
      fit: PdfFitMode.pageFit,
      file: 'test/fixtures/sample_dual_page.pdf',
      dualMode: DualPageMode.always,
      coverAlone: false,
    );
    final spread = c.layout.pageLayouts[0].expandToInclude(c.layout.pageLayouts[1]);
    final inflated = spread.inflate(_margin);
    final expected = _minOf(
        _viewSize.width / inflated.width, _viewSize.height / inflated.height);
    expect(c.currentZoom, closeTo(expected, 0.001));
    // 合併矩形比單頁寬：基準必須比「只看第一頁」的 Page-fit 小。
    final single = c.layout.pageLayouts[0].inflate(_margin);
    final singleFit = _minOf(
        _viewSize.width / single.width, _viewSize.height / single.height);
    expect(c.currentZoom, lessThan(singleFit));
  });

  testWidgets('手動裁切：以裁切後的頁面矩形（含邊距）算基準（Review Focus 4）', (tester) async {
    final c = await _open(
      tester,
      fit: PdfFitMode.pageFit,
      cropMode: PdfCropMode.manual,
      cropRect:
          const PdfCropRect(left: 0.25, top: 0.1, right: 0.75, bottom: 0.9),
    );
    final cropped = c.layout.pageLayouts[0].inflate(_margin);
    final expected = _minOf(
        _viewSize.width / cropped.width, _viewSize.height / cropped.height);
    expect(c.currentZoom, closeTo(expected, 0.001));
  });

  testWidgets('執行期由 Page-fit 切到 Fit Width：縮放改為 Fit Width 的基準', (tester) async {
    final page = await _pageSize(tester, 'test/fixtures/sample.pdf', 0);
    final fitWidth = _viewSize.width / (page.width + _margin * 2);

    var rendered = 0;
    await tester.pumpWidget(_app(_view(
        onRendered: () => rendered++, fit: PdfFitMode.pageFit)));
    await pumpUntilPdfReady(tester, condition: () => rendered != 0);
    await pumpUntilPdfReady(tester, maxIterations: 5);
    final c = _controllerOf(tester);
    // 前提：切換前確實不同。這依賴 sample.pdf（約 612x792）在 400x400 下
    // Page-fit 受高度限制（≈0.495）、Fit Width 受寬度限制（≈0.637）；更換
    // fixture 時需重新確認兩者仍有鑑別力。
    expect(c.currentZoom, lessThan(fitWidth - 0.01));

    await tester.pumpWidget(_app(_view(
        onRendered: () => rendered++, fit: PdfFitMode.fitWidth)));
    await pumpUntilPdfReady(
      tester,
      condition: () => (c.currentZoom - fitWidth).abs() < 0.001,
    );
    expect(c.currentZoom, closeTo(fitWidth, 0.001));
    expect(c.minScale, lessThanOrEqualTo(fitWidth + 0.001));
  });

  testWidgets('使用者手動放大後切換 Fit 模式：縮放回到新模式的基準（Review Focus 3）',
      (tester) async {
    final page = await _pageSize(tester, 'test/fixtures/sample.pdf', 0);
    final pageFit = _minOf(_viewSize.width / (page.width + _margin * 2),
        _viewSize.height / (page.height + _margin * 2));

    var rendered = 0;
    await tester.pumpWidget(_app(_view(
        onRendered: () => rendered++, fit: PdfFitMode.fitWidth)));
    await pumpUntilPdfReady(tester, condition: () => rendered != 0);
    await pumpUntilPdfReady(tester, maxIterations: 5);
    final c = _controllerOf(tester);

    // 使用者手動放大到 3 倍。
    await c.setZoom(Offset.zero, 3.0, duration: Duration.zero);
    await tester.pump();
    expect(c.currentZoom, closeTo(3.0, 0.001));

    await tester.pumpWidget(_app(_view(
        onRendered: () => rendered++, fit: PdfFitMode.pageFit)));
    await pumpUntilPdfReady(
      tester,
      condition: () => (c.currentZoom - pageFit).abs() < 0.001,
    );
    expect(c.currentZoom, closeTo(pageFit, 0.001));
  });

  group('導覽（跳頁／翻頁）後維持 Fit 模式的縮放（程式審查 I-1、I-2）', () {
    testWidgets('單頁・真實比例：下一頁後縮放仍是 1.0，不被縮成頁寬', (tester) async {
      final key = GlobalKey<State<PdfReaderView>>();
      final c = await _open(
        tester,
        fit: PdfFitMode.actualSize,
        file: 'test/fixtures/sample_multi_page.pdf',
        key: key,
      );
      expect(c.currentZoom, closeTo(1.0, 0.001));

      PdfReaderView.nextPage(key);
      await pumpUntilPdfReady(tester, condition: () => c.pageNumber == 2);
      await pumpUntilPdfReady(tester, maxIterations: 5);

      expect(c.pageNumber, 2);
      expect(c.currentZoom, closeTo(1.0, 0.001));
    });

    testWidgets('單頁・Page-fit：下一頁後仍整頁放進螢幕（行為不變的守衛）', (tester) async {
      final page = await _pageSize(tester, 'test/fixtures/sample_multi_page.pdf', 1);
      final expected = _minOf(_viewSize.width / (page.width + _margin * 2),
          _viewSize.height / (page.height + _margin * 2));
      final key = GlobalKey<State<PdfReaderView>>();
      final c = await _open(
        tester,
        fit: PdfFitMode.pageFit,
        file: 'test/fixtures/sample_multi_page.pdf',
        key: key,
      );

      PdfReaderView.nextPage(key);
      await pumpUntilPdfReady(tester, condition: () => c.pageNumber == 2);
      await pumpUntilPdfReady(tester, maxIterations: 5);

      expect(c.pageNumber, 2);
      expect(c.currentZoom, closeTo(expected, 0.001));
    });

    testWidgets('單頁・Fit Width：跳到指定頁後縮放仍是 Fit Width 基準', (tester) async {
      final page = await _pageSize(tester, 'test/fixtures/sample_multi_page.pdf', 3);
      final expected = _viewSize.width / (page.width + _margin * 2);
      final key = GlobalKey<State<PdfReaderView>>();
      final c = await _open(
        tester,
        fit: PdfFitMode.fitWidth,
        file: 'test/fixtures/sample_multi_page.pdf',
        key: key,
      );

      PdfReaderView.jumpToPage(key, 3);
      await pumpUntilPdfReady(tester, condition: () => c.pageNumber == 4);
      await pumpUntilPdfReady(tester, maxIterations: 5);

      expect(c.pageNumber, 4);
      expect(c.currentZoom, closeTo(expected, 0.001));
    });

    testWidgets('雙頁・Fit Width：下一個 spread 後縮放是該 spread 的 Fit Width 基準，不是整個 spread 放進螢幕',
        (tester) async {
      // 800x240：spread 比可視範圍寬又矮，Fit Width（受寬度限制）與 Page-fit
      // （受高度限制）的值明顯不同，才有鑑別力。
      const size = Size(800, 240);
      final key = GlobalKey<State<PdfReaderView>>();
      final c = await _open(
        tester,
        fit: PdfFitMode.fitWidth,
        file: 'test/fixtures/sample_dual_page.pdf',
        dualMode: DualPageMode.always,
        coverAlone: false,
        size: size,
        key: key,
      );

      // 第二個 spread ＝ 第 3、4 頁（index 2、3）。
      final spread2 = c.layout.pageLayouts[2].expandToInclude(c.layout.pageLayouts[3]);
      final inflated = spread2.inflate(_margin);
      final fitWidth = size.width / inflated.width;
      final pageFit = _minOf(fitWidth, size.height / inflated.height);
      expect(fitWidth - pageFit, greaterThan(0.05)); // 前提：兩者有鑑別力

      PdfReaderView.nextPage(key);
      await pumpUntilPdfReady(tester, condition: () => c.pageNumber == 3);
      await pumpUntilPdfReady(tester, maxIterations: 5);

      expect(c.pageNumber, 3); // spread 錨點頁（1-indexed）
      expect(c.currentZoom, closeTo(fitWidth, 0.001));
    });
  });
}

double _minOf(double a, double b) => a < b ? a : b;
