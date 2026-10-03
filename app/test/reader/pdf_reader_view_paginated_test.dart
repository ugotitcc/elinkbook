import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_page_turn_animation.dart';
import 'package:elinkbook/reader/pdf_page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pump_until_pdf_ready.dart';

const _margin = 8.0;

/// 把測試視窗設成 [size]（邏輯像素，devicePixelRatio 固定 1），PdfReaderView 直接
/// 填滿整個視窗，所以可視尺寸就是 [size]。
void _setSurface(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 與 pdfrx 繪製規則一致的外部證據：與目前可視矩形有面積相交的頁面（1-based）。
List<int> _visiblePages(PdfViewerController c) {
  final visible = c.visibleRect;
  final rects = c.layout.pageLayouts;
  return [
    for (var i = 0; i < rects.length; i++)
      if (!rects[i].intersect(visible).isEmpty) i + 1,
  ];
}

class _Harness {
  final key = GlobalKey<State<PdfReaderView>>();
  int rendered = 0;
  final pages = <int>[];

  Widget app({
    String file = 'test/fixtures/sample_multi_page.pdf',
    PdfPageTurnMode turnMode = PdfPageTurnMode.paginated,
    PdfFitMode? fit = PdfFitMode.pageFit,
    PdfPageTurnAnimation animation = PdfPageTurnAnimation.slide,
    DualPageMode dualMode = DualPageMode.never,
    bool coverAlone = false,
    PdfCropMode cropMode = PdfCropMode.none,
    PdfCropRect? cropRect,
    int? initialPageIndex,
    List<ZoneAction>? navZoneActions,
    void Function(ZoneAction)? onZoneAction,
  }) =>
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          key: key,
          filePath: file,
          onPageRendered: () => rendered++,
          onError: (_) {},
          onPageChanged: (PdfPageInfo info) => pages.add(info.pageIndex),
          initialPageIndex: initialPageIndex,
          pdfPageTurnMode: turnMode,
          pdfFitMode: fit,
          pdfPageTurnAnimation: animation,
          dualPageMode: dualMode,
          dualPageCoverAlone: coverAlone,
          pdfCropMode: cropMode,
          pdfCropRect: cropRect,
          navZoneActions: navZoneActions ??
              List<ZoneAction>.filled(9, ZoneAction.none),
          onZoneAction: onZoneAction,
        ),
      );

  Future<void> waitReady(WidgetTester tester) async {
    await pumpUntilPdfReady(tester, condition: () => rendered != 0);
    // 初始定位在 onViewerReady 之後才落定，再多等幾輪。
    await pumpUntilPdfReady(tester, maxIterations: 5);
  }

  Future<PdfViewerController> open(WidgetTester tester, Widget app) async {
    await tester.pumpWidget(app);
    await waitReady(tester);
    return controller(tester);
  }

  PdfViewerController controller(WidgetTester tester) =>
      tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
}

void main() {
  setUp(() => pdfrxInitialize());

  group('幾何隔離：逐頁下鄰頁不進入可視矩形（Review Focus 1）', () {
    testWidgets('Page-fit＋窄長視窗 300x900：只有第 1 頁相交；連續捲動同條件會露出鄰頁（對照）',
        (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app());
      expect(_visiblePages(c), [1]);

      final scroll = _Harness();
      final cs = await scroll.open(
          tester, scroll.app(turnMode: PdfPageTurnMode.scroll));
      expect(_visiblePages(cs).length, greaterThan(1),
          reason: '對照組：連續捲動下鄰頁會從留白處露出，否則本測試對間距沒有鑑別力');
    });

    testWidgets('Page-fit＋窄長視窗：目前單元在縱向置中', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app());
      final box = c.layout.pageLayouts[0].inflate(_margin);
      expect(c.visibleRect.center.dy, closeTo(box.center.dy, 0.5));
      expect(c.currentZoom, closeTo(300 / (612 + _margin * 2), 1e-3));
    });

    testWidgets('Fit Width、縱向有留白（300x400 小頁放進 400x1000）：只有第 1 頁相交', (tester) async {
      _setSurface(tester, const Size(400, 1000));
      final h = _Harness();
      final c = await h.open(
        tester,
        h.app(file: 'test/fixtures/sample_dual_page.pdf', fit: PdfFitMode.fitWidth),
      );
      expect(_visiblePages(c), [1]);
      expect(c.currentZoom, closeTo(400 / (300 + _margin * 2), 1e-3));
    });

    testWidgets('Fit Width、縱向溢出（612x792 放進 400x400）：只有第 1 頁相交，頁寬滿版', (tester) async {
      _setSurface(tester, const Size(400, 400));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      expect(_visiblePages(c), [1]);
      expect(c.currentZoom, closeTo(400 / (612 + _margin * 2), 1e-3));
      // 縱向溢出時從頁頂開始。
      expect(c.visibleRect.top, closeTo(c.layout.pageLayouts[0].top - _margin, 1e-3));
    });

    testWidgets('雙頁＋封面獨立（預設）：封面單頁 spread 的縮放基準取 spread 內容寬（C-1）',
        (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(
        tester,
        h.app(
          file: 'test/fixtures/sample_dual_page.pdf',
          dualMode: DualPageMode.always,
          coverAlone: true,
        ),
      );
      expect(_visiblePages(c), [1]); // 封面單獨一頁
      // 基準以 spread 內容寬（兩頁 600 + 邊距 16）計，不是封面單頁寬。
      expect(c.currentZoom, closeTo(300 / (600 + _margin * 2), 1e-3));
    });

    testWidgets('雙頁模式：整個 spread（第 1、2 頁）一起可見，鄰近 spread 不可見', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(
        tester,
        h.app(
          file: 'test/fixtures/sample_dual_page.pdf',
          dualMode: DualPageMode.always,
        ),
      );
      expect(_visiblePages(c), [1, 2]);
    });

    testWidgets('手動裁切：只有第 1 頁相交', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(
        tester,
        h.app(
          cropMode: PdfCropMode.manual,
          cropRect:
              const PdfCropRect(left: 0.25, top: 0.1, right: 0.75, bottom: 0.9),
        ),
      );
      expect(_visiblePages(c), [1]);
    });

    testWidgets('快取外擴保留 pdfrx 預設 1.0（Issue 3 結論，不得改動）', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      await h.open(tester, h.app());
      final params = tester.widget<PdfViewer>(find.byType(PdfViewer)).params;
      expect(params.verticalCacheExtent, 1.0);
      expect(params.horizontalCacheExtent, 1.0);
    });
  });

  group('平移與縮放鎖定在目前單元（Review Focus 4）', () {
    testWidgets('縮放不可低於基準，可在基準之上放大且仍只與目前單元相交', (tester) async {
      _setSurface(tester, const Size(400, 400));
      final h = _Harness();
      final c = await h.open(tester, h.app());
      final base = 400 / (792 + _margin * 2); // Page-fit：高度受限

      await c.setZoom(c.centerPosition, 0.1, duration: Duration.zero);
      expect(c.currentZoom, closeTo(base, 1e-3));

      await c.setZoom(c.centerPosition, 2.0, duration: Duration.zero);
      expect(c.currentZoom, closeTo(2.0, 1e-3));
      expect(_visiblePages(c), [1]);
    });

    testWidgets('goToPosition 到遠處的文件座標：可視矩形仍鎖在目前單元內', (tester) async {
      _setSurface(tester, const Size(400, 400));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      final unit0 = c.layout.pageLayouts[0].inflate(_margin);

      await c.goToPosition(
        documentOffset: Offset(0, c.layout.pageLayouts[4].bottom + 3000),
        duration: Duration.zero,
      );
      expect(_visiblePages(c), [1]);
      expect(c.visibleRect.bottom, lessThanOrEqualTo(unit0.bottom + 1e-3));
      expect(c.visibleRect.top, greaterThanOrEqualTo(unit0.top - 1e-3));
    });
  });

  group('頁碼與初始定位（規則 10）', () {
    testWidgets('以 initialPageIndex 開書：落在該頁單元，頁碼回報該頁', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app(initialPageIndex: 3));
      expect(_visiblePages(c), [4]);
      expect(h.pages.last, 3);
    });

    testWidgets('雙頁模式：頁碼回報 spread 錨點頁', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      await h.open(
        tester,
        h.app(
          file: 'test/fixtures/sample_dual_page.pdf',
          dualMode: DualPageMode.always,
          initialPageIndex: 3, // 第 4 頁屬於 [2, 3] 這組 spread，錨點為第 3 頁（index 2）
        ),
      );
      expect(h.pages.last, 2);
    });

    testWidgets('單頁文件（1 頁）開啟不崩，只與第 1 頁相交（Review Focus 5）', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app(file: 'test/fixtures/sample.pdf'));
      expect(_visiblePages(c), [1]);
    });
  });
}