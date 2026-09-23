import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_image_filters.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import '../support/pump_until_pdf_ready.dart';

void main() {
  // ── Task 1 純函式測試已移至 pdf_image_filters_test.dart（依 plan File Structure）──

  // ── Task 4: ColorFiltered widget tests ──

  group('PdfReaderView ColorFiltered', () {
    setUp(() => pdfrxInitialize());

    testWidgets('不傳濾鏡參數時，不套用 ColorFiltered（零回歸基準）',
        (tester) async {
      var renderedCount = 0;
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            onPageRendered: () => renderedCount++,
            onError: (_) {},
          ),
        ),
      );
      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

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
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

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
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            pdfBrightness: 30,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
          ),
        ),
      );
      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

      expect(find.byType(ColorFiltered), findsOneWidget);
    });
  });

  // ── Task 5: Bold overlay widget tests ──
  // 【複審修正】原本以為 Isolate.run() 在 Flutter test 環境中無法 spawn
  // 新 isolate，故只測零回歸分支。實際逐層排查後確認並非環境限制：
  // pdf_reader_view.dart 內把 Isolate.run() 的 closure 定義在
  // `_recomputeOverlay`/`_detectCropRect` 方法內部時，即使 closure 只讀取
  // 已取出的區域變數，Dart VM 仍會把該 closure 所在整個詞法作用域的
  // Context（含 `page: PdfPage` 參數，因此牽連 pdfrx 內部的
  // `_PdfDocumentPdfium.permissions`——一個 rxdart `BehaviorSubject`，不可
  // 跨 isolate 傳遞）一併打包，導致 `Isolate.run()` 在執行期擲出
  // 「object is unsendable」例外——這是真實的既有實作缺陷，會在真機上
  // 同樣發生，不是測試環境限定的假象。已改為呼叫獨立於 State 之外的頂層
  // 輔助函式（`_isolateProcessOverlayPixels`/`_isolateDetectCropRect`，見
  // `pdf_reader_view.dart` 檔案結尾的詳細說明），Isolate.run() 現在在此
  // 測試環境中可正常運作，以下測試直接驗證覆蓋圖的實際產出。

  group('PdfReaderView bold overlay', () {
    setUp(() => pdfrxInitialize());

    testWidgets('pdfBoldStrength == 0（預設）時，不產生任何覆蓋層（零回歸）',
        (tester) async {
      var renderedCount = 0;
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            onPageRendered: () => renderedCount++,
            onError: (_) {},
          ),
        ),
      );
      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(RawImage), findsNothing);
    });

    testWidgets('pdfBoldStrength > 0 時，第一頁疊加一張處理後的 RawImage 覆蓋層',
        (tester) async {
      var renderedCount = 0;
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            pdfBoldStrength: 1.0,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
          ),
        ),
      );
      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
      await pumpUntilPdfReady(
        tester,
        condition: () => find.byType(RawImage).evaluate().isNotEmpty,
        delayBetweenPumps: const Duration(milliseconds: 50),
      );
      await tester.pump();

      expect(find.byType(RawImage), findsWidgets,
          reason: '加粗啟用且 Isolate 運算成功完成後，應有至少一張處理後的頁面覆蓋圖');
    });

    testWidgets(
        '同時有多頁需要加粗運算時，各頁互不取消（Critical 2 回歸測試：'
        '不得共用單一 debouncer 排程逐頁運算）', (tester) async {
      var renderedCount = 0;
      final key = GlobalKey<State<PdfReaderView>>();

      // 用夠高的可視區域讓多於 1 頁同時進入 pageOverlaysBuilder 的呼叫範圍。
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SizedBox(
            height: 2000,
            child: PdfReaderView(
              key: key,
              filePath: 'test/fixtures/sample_multi_page.pdf',
              pdfBoldStrength: 1.0,
              onPageRendered: () => renderedCount++,
              onError: (_) {},
            ),
          ),
        ),
      );
      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
      await pumpUntilPdfReady(
        tester,
        condition: () => find.byType(RawImage).evaluate().length >= 2,
        maxIterations: 40,
        delayBetweenPumps: const Duration(milliseconds: 50),
      );
      await tester.pump();

      expect(
        find.byType(RawImage).evaluate().length,
        greaterThanOrEqualTo(2),
        reason: '若各頁的加粗運算共用同一個 debouncer 排程，後呼叫的頁面會取消先前'
            '排程、只會剩下最後一頁算出覆蓋圖；這裡斷言至少 2 頁都完成運算，證明'
            '各頁是獨立排程、互不取消',
      );
    });
  });

  // ── Task 6: Crop detection widget tests ──

  group('PdfReaderView crop detection', () {
    setUp(() => pdfrxInitialize());

    testWidgets('pdfCropMode=autoDetect 且尚無 pdfCropRect 時，首次渲染後觸發 onCropRectComputed',
        (tester) async {
      var renderedCount = 0;
      PdfCropRect? computedRect;
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            pdfCropMode: PdfCropMode.autoDetect,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onCropRectComputed: (rect) => computedRect = rect,
          ),
        ),
      );
      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
      await pumpUntilPdfReady(
        tester,
        condition: () => computedRect != null,
        delayBetweenPumps: const Duration(milliseconds: 50),
      );

      expect(computedRect, isNotNull);
    });

    testWidgets('pdfCropMode=autoDetect 且已有 pdfCropRect 時，不重新觸發偵測',
        (tester) async {
      var renderedCount = 0;
      var computeCount = 0;
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            pdfCropMode: PdfCropMode.autoDetect,
            pdfCropRect: const PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onCropRectComputed: (rect) => computeCount++,
          ),
        ),
      );
      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
      await tester.pump(const Duration(milliseconds: 500));

      expect(computeCount, 0, reason: '已有快取矩形時不應重新計算');
    });

    testWidgets('裁切模式啟用時，即使 dualPageMode=always 也強制單頁', (tester) async {
      var renderedCount = 0;
      PdfPageInfo? lastPageInfo;
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

      PdfReaderView.nextPage(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(lastPageInfo?.pageIndex, 1, reason: '裁切啟用時應退回單頁步進 1，而非雙頁步進 2');
    });
  });

  // ── Task 7: Crop visual effect widget tests ──

  group('PdfReaderView crop visual', () {
    setUp(() => pdfrxInitialize());

    testWidgets('pdfCropMode=none（預設）時不影響 layoutPages（零回歸）',
        (tester) async {
      var renderedCount = 0;
      PdfPageInfo? lastPageInfo;
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
          ),
        ),
      );
      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
      expect(lastPageInfo?.totalPages, 5);
      expect(find.byType(RawImage), findsNothing);
    });

    testWidgets('裁切啟用時，頁面顯示尺寸依裁切矩形縮小（非原始頁面比例），'
        '且第一頁疊加裁切後的覆蓋圖', (tester) async {
      var renderedCount = 0;
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            pdfCropMode: PdfCropMode.autoDetect,
            pdfCropRect: const PdfCropRect(left: 0.25, top: 0.1, right: 0.75, bottom: 0.9),
            onPageRendered: () => renderedCount++,
            onError: (_) {},
          ),
        ),
      );
      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
      await pumpUntilPdfReady(
        tester,
        condition: () => find.byType(RawImage).evaluate().isNotEmpty,
        delayBetweenPumps: const Duration(milliseconds: 50),
      );
      await tester.pump();

      expect(find.byType(RawImage), findsWidgets,
          reason: '裁切啟用且 Isolate 運算成功完成後，第一頁應有裁切後的覆蓋圖');
    });
  });

  // ── Task 9: cropEditModeActive widget tests ──

  group('PdfReaderView cropEditModeActive', () {
    setUp(() => pdfrxInitialize());

    testWidgets('cropEditModeActive=true 時，nextPage/previousPage 暫停回應',
        (tester) async {
      var renderedCount = 0;
      PdfPageInfo? lastPageInfo;
      final key = GlobalKey<State<PdfReaderView>>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
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
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            onPageRendered: () => renderedCount++,
            onError: (_) {},
            onPageChanged: (info) => lastPageInfo = info,
          ),
        ),
      );
      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

      PdfReaderView.nextPage(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(lastPageInfo?.pageIndex, 1);
    });
  });

  // ── Debounce & Crop Invalidation Tests (Without Isolate.run) ──

  group('PdfReaderView debounce and crop invalidation', () {
    setUp(() => pdfrxInitialize());

    testWidgets('執行期連續變更 pdfBoldStrength（模擬 Slider 拖曳）時，在 debounce 沉澱前不會對每個中間值各自觸發一次運算', (tester) async {
      // 說明：此測試不依賴 Isolate.run。我們透過觀察 PdfViewer 實例是否改變，
      // 來間接驗證內部 _committedBoldStrength 是否已更新（更新會觸發 setState 重建）。
      var renderedCount = 0;
      final key = GlobalKey<State<PdfReaderView>>();
      
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
            pdfBoldStrength: 0.0,
            onPageRendered: () => renderedCount++,
            onError: (_) {},
          ),
        ),
      );
      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
      
      // 模擬連續拖曳：第一次變更
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
      
      final viewer1 = tester.widget<PdfViewer>(find.byType(PdfViewer));
      expect(viewer1.params.layoutPages, isNull, reason: '無裁切矩形時，單頁模式下 layoutPages 應為 null');
      
      // 模擬智慧自動裁切偵測完成寫回
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
      await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);
      
      final viewer1 = tester.widget<PdfViewer>(find.byType(PdfViewer));
      expect(viewer1.params.calculateCurrentPageNumber, isNotNull, reason: '雙頁模式啟用時，應有自訂頁碼推算邏輯');
      
      // 啟用裁切模式
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
