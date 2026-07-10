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

  testWidgets('濾鏡分頁存在對比度／亮度滑桿，初始值反映 prefs', (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfContrast: 30, pdfBrightness: -20),
      (_) {},
    );

    // 切到濾鏡分頁
    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('pdf_settings_contrast_slider')))
          .value,
      30,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('pdf_settings_brightness_slider')))
          .value,
      -20,
    );
  });

  testWidgets('prefs.pdfContrast／pdfBrightness 為 null 時，滑桿顯示預設值 0',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('pdf_settings_contrast_slider')))
          .value,
      0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('pdf_settings_brightness_slider')))
          .value,
      0,
    );
  });

  testWidgets('拖動對比度滑桿後，onChanged 帶入新的 pdfContrast，其餘 PDF 欄位不變',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfContrast: 0, pdfBrightness: 15),
      (prefs) => notified = prefs,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('pdf_settings_contrast_increment')));
    await tester.pump();

    expect(notified?.pdfContrast, greaterThan(0));
    expect(notified?.pdfBrightness, 15);
  });

  testWidgets('拖動亮度滑桿後，onChanged 帶入新的 pdfBrightness', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => notified = prefs);

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('pdf_settings_brightness_decrement')));
    await tester.pump();

    expect(notified?.pdfBrightness, lessThan(0));
  });

  testWidgets('濾鏡分頁存在加粗強度滑桿，初始值反映 prefs（0..1 換算為 0..100 顯示）',
      (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfBoldStrength: 0.6),
      (_) {},
    );

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('pdf_settings_bold_strength_slider')))
          .value,
      60,
    );
  });

  testWidgets('prefs.pdfBoldStrength 為 null 時，滑桿顯示預設值 0', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('pdf_settings_bold_strength_slider')))
          .value,
      0,
    );
  });

  testWidgets('拖動加粗強度滑桿後，onChanged 帶入新的 pdfBoldStrength（0..1），其餘 PDF 欄位不變',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(
        pdfFitMode: PdfFitMode.fitWidth,
        pdfContrast: 10,
        pdfBrightness: -5,
        pdfBoldStrength: 0,
      ),
      (prefs) => notified = prefs,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('pdf_settings_bold_strength_increment')));
    await tester.pump();

    expect(notified?.pdfBoldStrength, greaterThan(0));
    // 關鍵回歸檢查：加粗滑桿變動不應清空其他已追蹤的 PDF 欄位。
    expect(notified?.pdfFitMode, PdfFitMode.fitWidth);
    expect(notified?.pdfContrast, 10);
    expect(notified?.pdfBrightness, -5);
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
