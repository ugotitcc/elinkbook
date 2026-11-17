import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pump_until_pdf_ready.dart';

/// Issue 44：手動裁切需要知道「頁面現在在畫面的哪個矩形」，才能把裁切框的
/// 畫面比例換算成頁面比例。座標單位為邏輯像素（相對 PdfReaderView 自己）。
void main() {
  setUp(() => pdfrxInitialize());

  Future<GlobalKey<State<PdfReaderView>>> pumpReader(
    WidgetTester tester, {
    bool waitUntilReady = true,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1224, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final key = GlobalKey<State<PdfReaderView>>();
    var rendered = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => rendered++,
          onError: (_) {},
        ),
      ),
    );
    if (waitUntilReady) {
      await pumpUntilPdfReady(tester, condition: () => rendered != 0);
      await tester.pump();
    }
    return key;
  }

  testWidgets('尚未就緒：回傳空清單，不擲例外', (tester) async {
    final key = await pumpReader(tester, waitUntilReady: false);
    expect(PdfReaderView.visiblePageRects(key), isEmpty);
    // 讓文件開完，避免測試結束時還有非同步工作
    await pumpUntilPdfReady(tester, condition: () => false, maxIterations: 20);
  });

  testWidgets('就緒後：第一頁在畫面內、寬高比與頁面一致、水平置中', (tester) async {
    final key = await pumpReader(tester);

    final rects = PdfReaderView.visiblePageRects(key);
    expect(rects, isNotEmpty);
    expect(rects.first.pageIndex, 0);

    final controller =
        tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    final pageLayout = controller.layout.pageLayouts[0];
    final r = rects.first.rectInViewer;

    // 寬高比與頁面一致（縮放是等比）
    expect(r.width / r.height, closeTo(pageLayout.width / pageLayout.height, 1e-3));
    // 與畫面有交集，且水平置中於 1224 寬的畫面
    expect(r.overlaps(const Rect.fromLTWH(0, 0, 1224, 900)), isTrue);
    expect((r.left + r.right) / 2, closeTo(612, 2.0));
    // 縮放倍率換算：矩形寬 = 文件座標寬 × 目前縮放
    expect(r.width, closeTo(pageLayout.width * controller.currentZoom, 0.5));
  });

  testWidgets('只回傳與畫面有交集的頁面', (tester) async {
    final key = await pumpReader(tester);
    const viewport = Rect.fromLTWH(0, 0, 1224, 900);
    for (final entry in PdfReaderView.visiblePageRects(key)) {
      expect(entry.rectInViewer.overlaps(viewport), isTrue,
          reason: '第 ${entry.pageIndex} 頁不在畫面內，不應回傳');
    }
  });
}
