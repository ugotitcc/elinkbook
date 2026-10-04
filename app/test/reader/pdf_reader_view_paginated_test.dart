import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_page_turn_animation.dart';
import 'package:elinkbook/reader/pdf_page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  int activity = 0;

  /// 在 onPageRendered 當下執行的動作（模擬 ReaderScreen 開書後立刻帶高亮）。
  VoidCallback? onRenderedHook;

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
    bool reportActivity = true,
  }) =>
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: PdfReaderView(
          key: key,
          filePath: file,
          onPageRendered: () {
            rendered++;
            onRenderedHook?.call();
          },
          onError: (_) {},
          onPageChanged: (PdfPageInfo info) => pages.add(info.pageIndex),
          onReadingActivity: reportActivity ? () => activity++ : null,
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

  group('瞬間換頁導覽（規則 3／4 Page-fit 子集、規則 6）', () {
    testWidgets('nextPage／previousPage：瞬間換到相鄰單元（預設滑動動畫也不播放）', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app()); // animation 預設為 slide
      expect(_visiblePages(c), [1]);

      PdfReaderView.nextPage(h.key);
      // 刻意不 pump：Duration.zero 的 goToPosition 同步完成，沒有任何動畫幀。
      expect(_visiblePages(c), [2]);

      PdfReaderView.previousPage(h.key);
      expect(_visiblePages(c), [1]);
    });

    testWidgets('第一個單元往前、最後一個單元往後：無動作（Review Focus 5）', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app());

      PdfReaderView.previousPage(h.key);
      expect(_visiblePages(c), [1]);

      for (var i = 0; i < 6; i++) {
        PdfReaderView.nextPage(h.key); // 5 頁文件：第 5 次之後已在最後一頁
      }
      expect(_visiblePages(c), [5]);
    });

    testWidgets('單頁文件：下一頁與上一頁都無動作、不拋例外', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app(file: 'test/fixtures/sample.pdf'));
      PdfReaderView.nextPage(h.key);
      PdfReaderView.previousPage(h.key);
      expect(_visiblePages(c), [1]);
    });

    testWidgets('3×3 熱區的下一頁／上一頁動作：瞬間換頁', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final actions = List<ZoneAction>.filled(9, ZoneAction.none);
      actions[2] = ZoneAction.nextPage;
      actions[0] = ZoneAction.previousPage;
      void onZone(ZoneAction a) {
        if (a == ZoneAction.nextPage) PdfReaderView.nextPage(h.key);
        if (a == ZoneAction.previousPage) PdfReaderView.previousPage(h.key);
      }

      final c = await h.open(
          tester, h.app(navZoneActions: actions, onZoneAction: onZone));
      await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_2')));
      await tester.pump();
      expect(_visiblePages(c), [2]);

      await tester.tap(find.byKey(const Key('pdf_reader_nav_zone_0')));
      await tester.pump();
      expect(_visiblePages(c), [1]);
      // 等待 PdfViewer 內部 DoubleTapGestureRecognizer 的定時器過期。
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('雙頁模式：下一頁換到下一個 spread，頁碼回報錨點頁', (tester) async {
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
      PdfReaderView.nextPage(h.key);
      expect(_visiblePages(c), [3, 4]);
      await pumpUntilPdfReady(tester,
          condition: () => h.pages.isNotEmpty && h.pages.last == 2,
          maxIterations: 10);
      expect(h.pages.last, 2);
    });

    testWidgets('頁碼回報：單頁逐頁換頁後為新頁碼（index）', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      await h.open(tester, h.app());
      PdfReaderView.nextPage(h.key);
      await pumpUntilPdfReady(tester,
          condition: () => h.pages.isNotEmpty && h.pages.last == 1,
          maxIterations: 10);
      expect(h.pages.last, 1);
    });

    testWidgets('jumpToPage：落在目標單元頂端、基準縮放，不繼承先前的偏移與縮放', (tester) async {
      _setSurface(tester, const Size(400, 400));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      final base = 400 / (612 + _margin * 2);

      PdfReaderView.jumpToPage(h.key, 2);
      expect(_visiblePages(c), [3]);
      final top3 = c.layout.pageLayouts[2].top - _margin;
      expect(c.visibleRect.top, closeTo(top3, 1e-3));
      expect(c.currentZoom, closeTo(base, 1e-3));

      // 放大並在頁內往下平移後再次絕對跳轉：回到新單元頂端與基準縮放。
      await c.setZoom(c.centerPosition, 2.0, duration: Duration.zero);
      await c.goToPosition(
        documentOffset: Offset(0, top3 + 300),
        zoom: 2.0,
        duration: Duration.zero,
      );
      PdfReaderView.jumpToPage(h.key, 3);
      expect(_visiblePages(c), [4]);
      expect(c.visibleRect.top,
          closeTo(c.layout.pageLayouts[3].top - _margin, 1e-3));
      expect(c.currentZoom, closeTo(base, 1e-3));
    });
  });

  group('視窗尺寸改變與模式切換（Review Focus 2、3）', () {
    testWidgets('旋轉／視窗尺寸改變：停在同一單元，縮放重算為新基準', (tester) async {
      _setSurface(tester, const Size(400, 400));
      final h = _Harness();
      final c = await h.open(tester, h.app());
      PdfReaderView.jumpToPage(h.key, 2);
      expect(_visiblePages(c), [3]);

      tester.view.physicalSize = const Size(300, 900);
      await pumpUntilPdfReady(tester, maxIterations: 8);

      expect(_visiblePages(c), [3]);
      final base = 300 / (612 + _margin * 2); // 寬度受限
      expect(c.currentZoom, closeTo(base, 1e-3));
      final box = c.layout.pageLayouts[2].inflate(_margin);
      expect(c.visibleRect.center.dy, closeTo(box.center.dy, 0.5));
    });

    testWidgets('逐頁→連續捲動→逐頁：停在原本那一頁', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app());
      PdfReaderView.jumpToPage(h.key, 2);
      expect(_visiblePages(c), [3]);

      await tester.pumpWidget(h.app(turnMode: PdfPageTurnMode.scroll));
      await pumpUntilPdfReady(tester, maxIterations: 8);
      expect(c.pageNumber, 3);

      await tester.pumpWidget(h.app());
      await pumpUntilPdfReady(tester, maxIterations: 8);
      expect(_visiblePages(c), [3]);
    });

    testWidgets('逐頁下切換 Fit 模式：縮放改為新模式的基準', (tester) async {
      _setSurface(tester, const Size(400, 400));
      final h = _Harness();
      final c = await h.open(tester, h.app());
      expect(c.currentZoom, closeTo(400 / (792 + _margin * 2), 1e-3));

      await tester.pumpWidget(h.app(fit: PdfFitMode.fitWidth));
      final fitWidth = 400 / (612 + _margin * 2);
      await pumpUntilPdfReady(tester,
          condition: () => (c.currentZoom - fitWidth).abs() < 1e-3,
          maxIterations: 10);
      expect(c.currentZoom, closeTo(fitWidth, 1e-3));
      expect(_visiblePages(c), [1]);
    });

    testWidgets('逐頁下切換雙頁模式：仍停在原頁所屬的 spread', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(
          tester, h.app(file: 'test/fixtures/sample_dual_page.pdf'));
      PdfReaderView.jumpToPage(h.key, 3);
      expect(_visiblePages(c), [4]);

      await tester.pumpWidget(h.app(
        file: 'test/fixtures/sample_dual_page.pdf',
        dualMode: DualPageMode.always,
      ));
      await pumpUntilPdfReady(tester, maxIterations: 8);
      expect(_visiblePages(c), [3, 4]);
    });
  });

  group('雙頁＋封面獨立：翻頁縮放不跳動（C-1）', () {
    testWidgets('封面翻到內頁 spread：縮放基準相同', (tester) async {
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
      final coverZoom = c.currentZoom;
      PdfReaderView.nextPage(h.key);
      expect(_visiblePages(c), [2, 3]);
      expect(c.currentZoom, closeTo(coverZoom, 1e-6));
    });
  });

  group('審查修復（最終審查 I-1、I-2）', () {
    testWidgets('只有高度改變（例如軟鍵盤）：保留頁內位置與縮放，不重設到頂端（I-1）',
        (tester) async {
      _setSurface(tester, const Size(400, 400));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      PdfReaderView.jumpToPage(h.key, 2);
      final unitTop = c.layout.pageLayouts[2].top - _margin;
      await c.goToPosition(
        documentOffset: Offset(0, unitTop + 150),
        zoom: c.currentZoom,
        duration: Duration.zero,
      );
      expect(c.visibleRect.top, closeTo(unitTop + 150, 1e-3));

      tester.view.physicalSize = const Size(400, 350);
      await pumpUntilPdfReady(tester, maxIterations: 8);

      expect(_visiblePages(c), [3]);
      expect(c.visibleRect.top, closeTo(unitTop + 150, 1e-2));
      expect(c.currentZoom, closeTo(400 / (612 + _margin * 2), 1e-3));
    });

    testWidgets('實體鍵 PageDown／PageUp／End／Home：以單元為單位瞬間換頁（I-2）', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app());
      await tester.tap(find.byType(PdfViewer));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      expect(_visiblePages(c), [2]);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      expect(_visiblePages(c), [1]);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      expect(_visiblePages(c), [5]);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      expect(_visiblePages(c), [1]);
    });
  });

  group('長頁相對步進：先頁內逐屏、到底才換頁；往回對稱並落在上一單元底端（規則 3、4）', () {
    // Fit Width、視窗 400x200、頁 612x792：基準 400/628，單元方框高 808，
    // 縮放後內容高 808 * 基準，最大捲動量＝808 * 基準 − 200，步距＝200 * 0.9 = 180。
    final base = 400 / (612 + _margin * 2);
    final maxScroll = 808 * base - 200;

    double offsetPx(PdfViewerController c, int unitIndex) {
      final unitTop = c.layout.pageLayouts[unitIndex].top - _margin;
      return (c.visibleRect.top - unitTop) * c.currentZoom;
    }

    testWidgets('下一頁：0 → 180 → 最大捲動量 → 換到第 2 頁頂端', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      expect(offsetPx(c, 0), closeTo(0, 1e-3));

      PdfReaderView.nextPage(h.key);
      expect(_visiblePages(c), [1]);
      expect(offsetPx(c, 0), closeTo(180, 1e-3));

      PdfReaderView.nextPage(h.key);
      expect(_visiblePages(c), [1]);
      expect(offsetPx(c, 0), closeTo(maxScroll, 1e-3));

      PdfReaderView.nextPage(h.key);
      expect(_visiblePages(c), [2]);
      expect(offsetPx(c, 1), closeTo(0, 1e-3));
      expect(c.currentZoom, closeTo(base, 1e-6));
    });

    testWidgets('上一頁：從第 2 頁頂端回到第 1 頁底端，再逐屏往上退，到頂端後第一頁無動作（Review Focus 1）',
        (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      PdfReaderView.jumpToPage(h.key, 1); // 絕對跳轉：第 2 頁頂端
      expect(offsetPx(c, 1), closeTo(0, 1e-3));

      PdfReaderView.previousPage(h.key);
      expect(_visiblePages(c), [1]);
      expect(offsetPx(c, 0), closeTo(maxScroll, 1e-3)); // 落在底端

      PdfReaderView.previousPage(h.key);
      expect(offsetPx(c, 0), closeTo(maxScroll - 180, 1e-3));

      PdfReaderView.previousPage(h.key);
      expect(offsetPx(c, 0), closeTo(0, 1e-3)); // 下限 0

      PdfReaderView.previousPage(h.key); // 第一個單元頂端再往前：無動作
      expect(_visiblePages(c), [1]);
      expect(offsetPx(c, 0), closeTo(0, 1e-3));
    });

    testWidgets('最後一頁到底後再按下一頁：無動作', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      PdfReaderView.jumpToPage(h.key, 4);
      PdfReaderView.nextPage(h.key); // 0 → 180
      PdfReaderView.nextPage(h.key); // → 最大捲動量
      PdfReaderView.nextPage(h.key); // 已到底、沒有下一頁
      expect(_visiblePages(c), [5]);
      expect(offsetPx(c, 4), closeTo(maxScroll, 1e-3));
    });

    testWidgets('絕對跳轉仍落在頂端，不繼承底端位置（規則 4：落底端只適用相對步進）', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      PdfReaderView.jumpToPage(h.key, 1);
      PdfReaderView.previousPage(h.key); // 落在第 1 頁底端
      PdfReaderView.jumpToPage(h.key, 0);
      expect(offsetPx(c, 0), closeTo(0, 1e-3));
    });

    testWidgets('Page-fit 單元沒有溢出：仍是整頁換頁（Issue 4 行為不變，Review Focus 3）', (tester) async {
      _setSurface(tester, const Size(300, 900));
      final h = _Harness();
      final c = await h.open(tester, h.app());
      PdfReaderView.nextPage(h.key);
      expect(_visiblePages(c), [2]);
      PdfReaderView.previousPage(h.key);
      expect(_visiblePages(c), [1]);
    });

    testWidgets('放大後單元縱向溢出：步距以目前縮放換算，仍先頁內步進（Review Focus 3）', (tester) async {
      _setSurface(tester, const Size(400, 400));
      final h = _Harness();
      final c = await h.open(tester, h.app()); // Page-fit：整頁入鏡、沒有溢出
      await c.setZoom(c.centerPosition, 2.0, duration: Duration.zero);
      final unitTop = c.layout.pageLayouts[0].top - _margin;
      await c.goToPosition(
        documentOffset: Offset(c.visibleRect.left, unitTop),
        zoom: 2.0,
        duration: Duration.zero,
      );
      expect(offsetPx(c, 0), closeTo(0, 1e-3));

      PdfReaderView.nextPage(h.key);
      expect(_visiblePages(c), [1]);
      expect(offsetPx(c, 0), closeTo(360, 1e-3)); // 400 * 0.9
      expect(c.currentZoom, closeTo(2.0, 1e-6));
    });

    testWidgets('實體鍵 PageDown 與音量鍵共用同一套步進：長頁上先頁內捲動', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      await tester.tap(find.byType(PdfViewer));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      expect(_visiblePages(c), [1]);
      expect(offsetPx(c, 0), closeTo(180, 1e-3));
    });
  });

  group('帶高亮的跳轉：視窗自動帶到看得到高亮的位置（規則 7，Review Focus 4）', () {
    /// 高亮矩形（百分比）換成文件座標，與 PdfReaderView 的換算一致。
    Rect docRect(PdfViewerController c, int pageIndex, PercentRect p) {
      final page = c.layout.pageLayouts[pageIndex];
      return Rect.fromLTRB(
        page.left + p.left * page.width,
        page.top + p.top * page.height,
        page.left + p.right * page.width,
        page.top + p.bottom * page.height,
      );
    }

    void expectVisible(PdfViewerController c, Rect hl) {
      final v = c.visibleRect;
      expect(v.top, lessThanOrEqualTo(hl.top + 1e-3));
      expect(v.bottom, greaterThanOrEqualTo(hl.bottom - 1e-3));
    }

    testWidgets('jumpToPageAtRect：高亮在頁面下半部 → 視窗帶到看得到高亮', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      const rect = PercentRect(left: 0.1, top: 0.8, right: 0.5, bottom: 0.85);

      PdfReaderView.jumpToPageAtRect(h.key, 2, rect);
      expect(_visiblePages(c), [3]);
      expectVisible(c, docRect(c, 2, rect));
    });

    testWidgets('jumpToPageAtRect：高亮在頁面上半部、頂端已可見 → 維持頂端', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      const rect = PercentRect(left: 0.1, top: 0.05, right: 0.5, bottom: 0.08);

      PdfReaderView.jumpToPageAtRect(h.key, 2, rect);
      expect(c.visibleRect.top,
          closeTo(c.layout.pageLayouts[2].top - _margin, 1e-3));
    });

    testWidgets('showTemporaryHighlight（開書與就地跳轉路徑）：同樣自動帶到高亮', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      const rect = PercentRect(left: 0.1, top: 0.9, right: 0.5, bottom: 0.95);

      PdfReaderView.jumpToPage(h.key, 1); // applyTo(shouldNavigate: true) 先跳頁
      PdfReaderView.showTemporaryHighlight(h.key, 1, rect);
      await tester.pump();
      expect(_visiblePages(c), [2]);
      expectVisible(c, docRect(c, 1, rect));
      expect(find.byKey(const Key('pdf_reader_jump_highlight_1')), findsOneWidget);
    });

    testWidgets('開書當下（onPageRendered 內）呼叫 showTemporaryHighlight：視窗仍帶到高亮（M-2）',
        (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      const rect = PercentRect(left: 0.1, top: 0.9, right: 0.5, bottom: 0.95);
      h.onRenderedHook =
          () => PdfReaderView.showTemporaryHighlight(h.key, 0, rect);
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));

      expect(_visiblePages(c), [1]);
      expectVisible(c, docRect(c, 0, rect));
    });

    testWidgets('showTemporaryHighlight 的目標頁不是目前單元：先換到該單元再定位', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      const rect = PercentRect(left: 0.1, top: 0.9, right: 0.5, bottom: 0.95);

      PdfReaderView.showTemporaryHighlight(h.key, 3, rect); // 目前在第 1 頁
      await tester.pump();
      expect(_visiblePages(c), [4]);
      expectVisible(c, docRect(c, 3, rect));
    });

    testWidgets('高亮比可視高度還高：上緣貼齊可視上緣', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      // 可視文件高度 = 200 / 基準 ≈ 314；高亮高 0.6 * 792 ≈ 475 → 比可視高度高。
      const rect = PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.8);

      PdfReaderView.jumpToPageAtRect(h.key, 1, rect);
      expect(c.visibleRect.top,
          closeTo(docRect(c, 1, rect).top, 1e-2));
    });

    testWidgets('裁切模式：以裁切後的頁面座標換算高亮', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(
        tester,
        h.app(
          fit: PdfFitMode.fitWidth,
          cropMode: PdfCropMode.manual,
          cropRect:
              const PdfCropRect(left: 0.0, top: 0.0, right: 1.0, bottom: 0.5),
        ),
      );
      // 原頁面座標 top 0.4～0.45 落在裁切範圍（上半）內；裁切後的相對位置為 0.8～0.9。
      const rect = PercentRect(left: 0.1, top: 0.4, right: 0.5, bottom: 0.45);
      const relative = PercentRect(left: 0.1, top: 0.8, right: 0.5, bottom: 0.9);

      PdfReaderView.jumpToPageAtRect(h.key, 1, rect);
      expectVisible(c, docRect(c, 1, relative));
    });

    testWidgets('裁切模式：高亮完全落在裁切範圍外：不調整位置、不拋例外', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(
        tester,
        h.app(
          fit: PdfFitMode.fitWidth,
          cropMode: PdfCropMode.manual,
          cropRect:
              const PdfCropRect(left: 0.0, top: 0.0, right: 1.0, bottom: 0.5),
        ),
      );
      const outside = PercentRect(left: 0.1, top: 0.8, right: 0.5, bottom: 0.9);
      PdfReaderView.jumpToPageAtRect(h.key, 1, outside);
      expect(_visiblePages(c), [2]);
      expect(c.visibleRect.top,
          closeTo(c.layout.pageLayouts[1].top - _margin, 1e-3));
    });

    testWidgets('雙頁 spread 內的第二頁：以該頁在 spread 內的位置換算', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      final c = await h.open(
        tester,
        h.app(
          file: 'test/fixtures/sample_dual_page.pdf',
          fit: PdfFitMode.fitWidth,
          dualMode: DualPageMode.always,
        ),
      );
      const rect = PercentRect(left: 0.1, top: 0.9, right: 0.5, bottom: 0.95);
      PdfReaderView.jumpToPageAtRect(h.key, 1, rect); // 第 2 頁屬於 spread [1, 2]
      expectVisible(c, docRect(c, 1, rect));
    });

    testWidgets('連續捲動：jumpToPageAtRect 退化為 jumpToPage，跳到目標頁且不拋例外（不套用逐頁高亮規則）', (tester) async {
      _setSurface(tester, const Size(400, 400));
      final h = _Harness();
      await h.open(tester, h.app(turnMode: PdfPageTurnMode.scroll));
      PdfReaderView.jumpToPageAtRect(
        h.key,
        2,
        const PercentRect(left: 0.1, top: 0.8, right: 0.5, bottom: 0.85),
      );
      // 連續捲動走原本的 jumpToPage（含換頁動畫），等頁碼落定後確認確實跳到第 3 頁。
      final c = h.controller(tester);
      await pumpUntilPdfReady(tester,
          condition: () => c.pageNumber == 3, maxIterations: 10);
      expect(c.pageNumber, 3);
    });
  });

  group('頁內垂直拖曳回報閱讀活動（規則 9，Review Focus 5）', () {
    Future<void> drag(
      WidgetTester tester,
      List<Offset> moves, {
      Offset? start,
    }) async {
      final g = await tester.startGesture(
          start ?? tester.getCenter(find.byType(PdfViewer)));
      for (final m in moves) {
        await g.moveBy(m);
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('逐頁：垂直拖曳 60 像素 → 回報至少一次', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      await drag(tester, [const Offset(0, -60)]);
      expect(h.activity, greaterThanOrEqualTo(1));
    });

    testWidgets('同一手勢分兩段各 12 像素：累積 24 → 回報一次', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      await drag(tester, [const Offset(0, -12), const Offset(0, -12)]);
      expect(h.activity, 1);
    });

    testWidgets('未達 20 像素不回報；兩次各 10 像素的分開手勢不累積（換手勢歸零）', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      await drag(tester, [const Offset(0, -10)]);
      await drag(tester, [const Offset(0, -10)]);
      expect(h.activity, 0);
    });

    testWidgets('水平拖曳不回報', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      await drag(tester, [const Offset(-80, 0)]);
      expect(h.activity, 0);
    });

    testWidgets('兩指同時按下（縮放）不回報', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      final center = tester.getCenter(find.byType(PdfViewer));
      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(40, 0));
      await g1.moveBy(const Offset(0, -60));
      await g2.moveBy(const Offset(0, -60));
      await g1.up();
      await g2.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(h.activity, 0);
    });

    testWidgets('Page-fit 單元沒有縱向溢出（視窗不會動）：垂直拖曳不回報（M-3）', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      await h.open(tester, h.app(fit: PdfFitMode.pageFit));
      await drag(tester, [const Offset(0, -60)]);
      expect(h.activity, 0);
    });

    testWidgets('兩指縮放後抬起一指：縮放前的餘數不接續累積（M-4）', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      await h.open(tester, h.app(fit: PdfFitMode.fitWidth));
      final center = tester.getCenter(find.byType(PdfViewer));
      final g1 = await tester.startGesture(center);
      await g1.moveBy(const Offset(0, -12)); // 累積 12，未達 20
      final g2 = await tester.startGesture(center + const Offset(40, 0));
      await g2.up(); // 回到單指
      await g1.moveBy(const Offset(0, -12)); // 若餘數保留會累積成 24 而回報
      await g1.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(h.activity, 0);
    });

    testWidgets('連續捲動模式不由 PdfReaderView 回報（由頁碼變化與既有路徑處理）', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      await h.open(
          tester, h.app(turnMode: PdfPageTurnMode.scroll, fit: PdfFitMode.fitWidth));
      await drag(tester, [const Offset(0, -60)]);
      expect(h.activity, 0);
    });

    testWidgets('未傳 onReadingActivity（既有呼叫端）：拖曳不拋例外', (tester) async {
      _setSurface(tester, const Size(400, 200));
      final h = _Harness();
      await h.open(tester, h.app(fit: PdfFitMode.fitWidth, reportActivity: false));
      await drag(tester, [const Offset(0, -60)]);
      expect(h.activity, 0);
    });
  });
}
