import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_image_filters.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';

void main() {
  // ── Task 1 純函式測試已移至 pdf_image_filters_test.dart（依 plan File Structure）──

  // ── Task 4: ColorFiltered widget tests ──

  group('PdfReaderView ColorFiltered', () {
    setUp(() => pdfrxInitialize());

    Future<void> waitRendered(WidgetTester tester, int Function() rendered) {
      return tester.runAsync(() async {
        for (var i = 0; i < 30 && rendered() == 0; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
    }

    testWidgets('不傳濾鏡參數時，不套用 ColorFiltered（零回歸基準）',
        (tester) async {
      var renderedCount = 0;
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            onPageRendered: () => renderedCount++,
            onError: (_) {},
          ),
        ),
      );
      await waitRendered(tester, () => renderedCount);

      final colorFiltered = tester.widgetList<ColorFiltered>(
        find.byType(ColorFiltered),
      );
      expect(colorFiltered, isEmpty,
          reason: 'contrast/brightness 皆為預設值 0 時不應包 ColorFiltered');
    });

    testWidgets('pdfContrast/pdfBrightness 非零時，套用對應矩陣的 ColorFiltered',
        (tester) async {
      var renderedCount = 0;
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            pdfContrast: 50,
            pdfBrightness: -20,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
          ),
        ),
      );
      await waitRendered(tester, () => renderedCount);

      final colorFiltered = tester.widget<ColorFiltered>(find.byType(ColorFiltered));
      final filter = colorFiltered.colorFilter;
      final expectedMatrix =
          contrastBrightnessColorMatrix(contrast: 50, brightness: -20);
      expect(filter, ColorFilter.matrix(expectedMatrix));
    });

    testWidgets('contrast=0 但 brightness 非零時仍套用 ColorFiltered', (tester) async {
      var renderedCount = 0;
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            pdfBrightness: 30,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
          ),
        ),
      );
      await waitRendered(tester, () => renderedCount);

      expect(find.byType(ColorFiltered), findsOneWidget);
    });
  });

  // ── Task 5: Bold overlay widget tests ──
  // 注意：Isolate.run 在 Flutter test 環境中無法 spawn 新 isolate，
  // 因此覆蓋圖的 Isolate 運算在此環境下會失敗。這裡只驗證「不加粗時
  // 不產出覆蓋圖」的零回歸行為，加粗覆蓋圖的實際像素處理留给真機
  // 整合測試驗證。

  group('PdfReaderView bold overlay', () {
    setUp(() => pdfrxInitialize());

    Future<void> waitRendered(WidgetTester tester, int Function() rendered) {
      return tester.runAsync(() async {
        for (var i = 0; i < 30 && rendered() == 0; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
    }

    testWidgets('pdfBoldStrength == 0（預設）時，不產生任何覆蓋層（零回歸）',
        (tester) async {
      var renderedCount = 0;
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            onPageRendered: () => renderedCount++,
            onError: (_) {},
          ),
        ),
      );
      await waitRendered(tester, () => renderedCount);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(RawImage), findsNothing);
    });
  });

  // ── Task 6: Crop detection widget tests ──
  // 注意：onCropRectComputed 與覆蓋圖運算都依賴 Isolate.run，在 Flutter
  // test 環境中無法 spawn 新 isolate。這裡只驗證「裁切+雙頁互斥」的版面
  // 行為（不需要 Isolate），其餘留給真機整合測試。

  group('PdfReaderView crop detection', () {
    setUp(() => pdfrxInitialize());

    Future<void> waitRendered(WidgetTester tester, int Function() rendered) {
      return tester.runAsync(() async {
        for (var i = 0; i < 30 && rendered() == 0; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
    }

    testWidgets('裁切模式啟用時，即使 dualPageMode=always 也強制單頁', (tester) async {
      var renderedCount = 0;
      PdfPageInfo? lastPageInfo;
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            dualPageMode: DualPageMode.always,
            pdfCropMode: PdfCropMode.autoDetect,
            pdfCropRect: const PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
          ),
        ),
      );
      await waitRendered(tester, () => renderedCount);

      PdfReaderView.nextPage(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(lastPageInfo?.pageIndex, 1, reason: '裁切啟用時應退回單頁步進 1，而非雙頁步進 2');
    });
  });

  // ── Task 7: Crop visual effect widget tests ──
  // 注意：覆蓋圖運算依賴 Isolate.run，在 Flutter test 環境中無法 spawn
  // 新 isolate。這裡只驗證「不裁切時不影響版面」的零回歸行為。

  group('PdfReaderView crop visual', () {
    setUp(() => pdfrxInitialize());

    Future<void> waitRendered(WidgetTester tester, int Function() rendered) {
      return tester.runAsync(() async {
        for (var i = 0; i < 30 && rendered() == 0; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
    }

    testWidgets('pdfCropMode=none（預設）時不影響 layoutPages（零回歸）',
        (tester) async {
      var renderedCount = 0;
      PdfPageInfo? lastPageInfo;
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
          ),
        ),
      );
      await waitRendered(tester, () => renderedCount);
      expect(lastPageInfo?.totalPages, 5);
      expect(find.byType(RawImage), findsNothing);
    });
  });

  // ── Task 9: cropEditModeActive widget tests ──

  group('PdfReaderView cropEditModeActive', () {
    setUp(() => pdfrxInitialize());

    Future<void> waitRendered(WidgetTester tester, int Function() rendered) {
      return tester.runAsync(() async {
        for (var i = 0; i < 30 && rendered() == 0; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
    }

    testWidgets('cropEditModeActive=true 時，nextPage/previousPage 暫停回應',
        (tester) async {
      var renderedCount = 0;
      PdfPageInfo? lastPageInfo;
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            cropEditModeActive: true,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
          ),
        ),
      );
      await waitRendered(tester, () => renderedCount);
      expect(lastPageInfo?.pageIndex, 0);

      PdfReaderView.nextPage(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(lastPageInfo?.pageIndex, 0, reason: '裁切編輯模式下翻頁應無效');

      PdfReaderView.jumpToPage(key, 3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(lastPageInfo?.pageIndex, 0, reason: '裁切編輯模式下跳頁應無效');
    });

    testWidgets('cropEditModeActive=false（預設）時翻頁行為不變（零回歸）',
        (tester) async {
      var renderedCount = 0;
      PdfPageInfo? lastPageInfo;
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
          ),
        ),
      );
      await waitRendered(tester, () => renderedCount);

      PdfReaderView.nextPage(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(lastPageInfo?.pageIndex, 1);
    });
  });

  // ── Debounce & Crop Invalidation Tests (Without Isolate.run) ──

  group('PdfReaderView debounce and crop invalidation', () {
    setUp(() => pdfrxInitialize());

    Future<void> waitRendered(WidgetTester tester, int Function() rendered) {
      return tester.runAsync(() async {
        for (var i = 0; i < 30 && rendered() == 0; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
    }

    testWidgets('執行期連續變更 pdfBoldStrength（模擬 Slider 拖曳）時，在 debounce 沉澱前不會對每個中間值各自觸發一次運算', (tester) async {
      // 說明：此測試不依賴 Isolate.run。我們透過觀察 PdfViewer 實例是否改變，
      // 來間接驗證內部 _committedBoldStrength 是否已更新（更新會觸發 setState 重建）。
      var renderedCount = 0;
      final key = GlobalKey<State<PdfReaderView>>();
      
      await tester.pumpWidget(
        MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            pdfBoldStrength: 0.0,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
          ),
        ),
      );
      await waitRendered(tester, () => renderedCount);
      
      // 模擬連續拖曳：第一次變更
      await tester.pumpWidget(
        MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            pdfBoldStrength: 0.1,
            onPageRendered: () {},
            onError: (_) {},
          ),
        ),
      );
      
      // 模擬連續拖曳：100ms 後第二次變更
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(
        MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            pdfBoldStrength: 0.2,
            onPageRendered: () {},
            onError: (_) {},
          ),
        ),
      );
      final viewer2 = tester.widget<PdfViewer>(find.byType(PdfViewer));
      
      // 100ms 後檢查
      await tester.pump(const Duration(milliseconds: 100));
      final viewer3 = tester.widget<PdfViewer>(find.byType(PdfViewer));
      
      // 在 debounce 沉澱前，內部不會觸發 setState 重建，因此 PdfViewer 實例相同
      expect(identical(viewer2, viewer3), isTrue, reason: 'debounce 尚未沉澱，不應觸發內部 setState 重建');
      
      // 等待 debounce 沉澱 (300ms)
      await tester.pump(const Duration(milliseconds: 350));
      final viewer4 = tester.widget<PdfViewer>(find.byType(PdfViewer));
      
      // debounce 沉澱後，內部觸發 setState 重建，產生新的 PdfViewer 實例
      expect(identical(viewer3, viewer4), isFalse, reason: 'debounce 沉澱後，應觸發內部 setState 重建');
    });

    testWidgets('執行期切換 pdfCropRect 時，版面尺寸立即反映新裁切矩形（間接驗證 invalidate）', (tester) async {
      // 說明：此測試不依賴 Isolate.run。我們透過觀察 PdfViewerParams.layoutPages 是否改變，
      // 來間接驗證 didUpdateWidget 是否正確處理了裁切矩形的變更並觸發了版面重算。
      var renderedCount = 0;
      final key = GlobalKey<State<PdfReaderView>>();
      
      await tester.pumpWidget(
        MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            pdfCropMode: PdfCropMode.autoDetect,
            pdfCropRect: null,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
          ),
        ),
      );
      await waitRendered(tester, () => renderedCount);
      
      final viewer1 = tester.widget<PdfViewer>(find.byType(PdfViewer));
      expect(viewer1.params.layoutPages, isNull, reason: '無裁切矩形時，單頁模式下 layoutPages 應為 null');
      
      // 模擬智慧自動裁切偵測完成寫回
      await tester.pumpWidget(
        MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            pdfCropMode: PdfCropMode.autoDetect,
            pdfCropRect: const PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
            onPageRendered: () {},
            onError: (_) {},
          ),
        ),
      );
      
      final viewer2 = tester.widget<PdfViewer>(find.byType(PdfViewer));
      expect(viewer2.params.layoutPages, isNotNull, reason: '有裁切矩形時，應套用 _layoutCroppedPages');
    });

    testWidgets('裁切模式與雙頁模式互斥：裁切啟用時，強制停用雙頁版面計算', (tester) async {
      // 說明：此測試不依賴 Isolate.run。我們透過觀察 PdfViewerParams.calculateCurrentPageNumber，
      // 來間接驗證當裁切啟用時，雙頁模式的頁碼推算邏輯是否被正確停用。
      var renderedCount = 0;
      final key = GlobalKey<State<PdfReaderView>>();
      
      await tester.pumpWidget(
        MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            dualPageMode: DualPageMode.always,
            pdfCropMode: PdfCropMode.none,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
          ),
        ),
      );
      await waitRendered(tester, () => renderedCount);
      
      final viewer1 = tester.widget<PdfViewer>(find.byType(PdfViewer));
      expect(viewer1.params.calculateCurrentPageNumber, isNotNull, reason: '雙頁模式啟用時，應有自訂頁碼推算邏輯');
      
      // 啟用裁切模式
      await tester.pumpWidget(
        MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            dualPageMode: DualPageMode.always,
            pdfCropMode: PdfCropMode.autoDetect,
            pdfCropRect: const PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
            onPageRendered: () {},
            onError: (_) {},
          ),
        ),
      );
      
      final viewer2 = tester.widget<PdfViewer>(find.byType(PdfViewer));
      expect(viewer2.params.calculateCurrentPageNumber, isNull, reason: '裁切啟用時，應強制停用雙頁模式的頁碼推算邏輯');
    });
  });
}
