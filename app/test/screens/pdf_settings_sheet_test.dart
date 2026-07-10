import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/screens/pdf_settings_sheet.dart';

void main() {
  testWidgets('三個分頁標籤皆存在', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(find.byKey(const Key('pdf_settings_tab_display')), findsOneWidget);
    expect(find.byKey(const Key('pdf_settings_tab_filters')), findsOneWidget);
    expect(find.byKey(const Key('pdf_settings_tab_crop')), findsOneWidget);
  });

  testWidgets('點擊 Fit Width 選項後，onChanged 帶入 pdfFitMode=fitWidth', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => notified = prefs);

    await tester.tap(find.byKey(const Key('pdf_settings_fit_mode_fit_width')));
    await tester.pump();

    expect(notified?.pdfFitMode, PdfFitMode.fitWidth);
  });

  testWidgets('點擊真實比例 1:1 選項後，onChanged 帶入 pdfFitMode=actualSize',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => notified = prefs);

    await tester.tap(find.byKey(const Key('pdf_settings_fit_mode_actual_size')));
    await tester.pump();

    expect(notified?.pdfFitMode, PdfFitMode.actualSize);
  });

  testWidgets('點擊 Page-fit 選項後，onChanged 帶入 pdfFitMode=pageFit', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfFitMode: PdfFitMode.fitWidth),
      (prefs) => notified = prefs,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_fit_mode_page_fit')));
    await tester.pump();

    expect(notified?.pdfFitMode, PdfFitMode.pageFit);
  });

  testWidgets('prefs.pdfFitMode 為 null 時（未持久化過），不因為初始 build 就觸發 onChanged',
      (tester) async {
    var callCount = 0;
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) => callCount++);

    expect(callCount, 0);
  });
}

Future<void> _pumpSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PdfSettingsSheet(
        prefs: prefs,
        onChanged: onChanged,
      ),
    ),
  ));
}
