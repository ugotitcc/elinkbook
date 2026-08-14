import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import '../support/pump_until_pdf_ready.dart';

void main() {
  setUp(() => pdfrxInitialize());

  testWidgets('renderThumbnail 回傳非 null 影像，寬度符合 maxWidth，高度依頁面比例換算',
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
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final image = await tester.runAsync(
      () => PdfReaderView.renderThumbnail(key, 0, maxWidth: 120),
    );

    expect(image, isNotNull);
    // sample_multi_page.pdf 頁面尺寸為 612×792（US Letter，見 fixture
    // MediaBox，Issue 5/6 已驗證），比例換算高度 = 792 / 612 * 120 ≈
    // 155.29，容許 1px 誤差（int 四捨五入）。
    expect(image!.width, 120);
    expect(image.height, closeTo(792 / 612 * 120, 1));
    image.dispose();
  });

  testWidgets('pageIndex 超出範圍時回傳 null，不拋出例外', (tester) async {
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
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final image = await tester.runAsync(
      () => PdfReaderView.renderThumbnail(key, 999, maxWidth: 120),
    );

    expect(image, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('State 尚未掛載時回傳 null', (tester) async {
    final orphanKey = GlobalKey<State<PdfReaderView>>();

    final image = await PdfReaderView.renderThumbnail(orphanKey, 0, maxWidth: 120);

    expect(image, isNull);
  });

  testWidgets('不同 pageIndex 各自產生獨立的影像，互不影響', (tester) async {
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
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    final image0 = await tester.runAsync(
      () => PdfReaderView.renderThumbnail(key, 0, maxWidth: 80),
    );
    final image4 = await tester.runAsync(
      () => PdfReaderView.renderThumbnail(key, 4, maxWidth: 80),
    );

    expect(image0, isNotNull);
    expect(image4, isNotNull);
    expect(image0!.width, 80);
    expect(image4!.width, 80);
    image0.dispose();
    image4.dispose();
  });
}
