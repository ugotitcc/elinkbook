// app/test/reader/pdf_reader_view_jump_highlight_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import '../support/pump_until_pdf_ready.dart';

void main() {
  setUp(() => pdfrxInitialize());

  testWidgets('showTemporaryHighlight 後畫面渲染出對應頁碼的暫態高亮 widget', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfReaderView.showTemporaryHighlight(
      key,
      0,
      const PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('pdf_reader_jump_highlight_0')),
      findsOneWidget,
    );
  });

  testWidgets('clearTemporaryHighlight 後高亮 widget 從畫面消失', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfReaderView.showTemporaryHighlight(
      key,
      0,
      const PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('pdf_reader_jump_highlight_0')),
      findsOneWidget,
    );

    PdfReaderView.clearTemporaryHighlight(key);
    await tester.pump();
    expect(find.byKey(const Key('pdf_reader_jump_highlight_0')), findsNothing);
  });

  testWidgets('高亮只在對應的 pageIndex 顯示，其他頁不受影響', (tester) async {
    var renderedCount = 0;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
      ),
    );
    await pumpUntilPdfReady(tester, condition: () => renderedCount != 0);

    PdfReaderView.showTemporaryHighlight(
      key,
      1,
      const PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
    );
    await tester.pump();

    expect(find.byKey(const Key('pdf_reader_jump_highlight_0')), findsNothing);
  });

  testWidgets(
      'State 尚未掛載時，showTemporaryHighlight／clearTemporaryHighlight 皆靜默忽略',
      (tester) async {
    final orphanKey = GlobalKey<State<PdfReaderView>>();
    expect(
      () => PdfReaderView.showTemporaryHighlight(
        orphanKey,
        0,
        const PercentRect(left: 0, top: 0, right: 1, bottom: 1),
      ),
      returnsNormally,
    );
    expect(
      () => PdfReaderView.clearTemporaryHighlight(orphanKey),
      returnsNormally,
    );
  });
}
