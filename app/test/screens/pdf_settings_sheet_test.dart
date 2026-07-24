import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
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

  testWidgets('裁切分頁存在不裁切／智慧自動／手動選區三個選項', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pdf_settings_crop_mode_none')), findsOneWidget);
    expect(
        find.byKey(const Key('pdf_settings_crop_mode_auto')), findsOneWidget);
    expect(
        find.byKey(const Key('pdf_settings_crop_mode_manual')), findsOneWidget);
  });

  testWidgets('點擊手動選區按鈕後，觸發 onRequestManualCrop（不直接改變 pdfCropMode）',
      (tester) async {
    var requestCount = 0;
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => notified = prefs,
      onRequestManualCrop: () => requestCount++,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pump();

    expect(requestCount, 1);
    // 手動選區的實際框選結果由 ReaderScreen 端的裁切互動模式流程另外
    // 提供（見 spec.md「ReaderScreen 內部行為異動」），本分頁點擊「手動
    // 選區」本身不直接呼叫 onChanged／改變 pdfCropMode。
    expect(notified, isNull);
  });

  testWidgets('點擊智慧自動選項後，onChanged 帶入 pdfCropMode=autoDetect', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => notified = prefs);

    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_auto')));
    await tester.pump();

    expect(notified?.pdfCropMode, PdfCropMode.autoDetect);
  });

  testWidgets(
      '已持久化 pdfCropRect 時，調整其他分頁的滑桿不會清空 pdfCropRect（關鍵回歸檢查）',
      (tester) async {
    BookReaderPrefs? notified;
    const existingCropRect =
        PdfCropRect(left: 0.02, top: 0.03, right: 0.98, bottom: 0.97);
    await _pumpSheet(
      tester,
      const BookReaderPrefs(
        pdfCropMode: PdfCropMode.autoDetect,
        pdfCropRect: existingCropRect,
        pdfContrast: 0,
      ),
      (prefs) => notified = prefs,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_contrast_increment')));
    await tester.pump();

    expect(notified?.pdfContrast, greaterThan(0));
    expect(notified?.pdfCropMode, PdfCropMode.autoDetect);
    expect(notified?.pdfCropRect, existingCropRect); // 關鍵斷言：未被清空
  });

  testWidgets('顯示分頁新增雙頁模式三個選項按鈕', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(find.byKey(const Key('pdf_settings_dual_page_mode_auto')),
        findsOneWidget);
    expect(find.byKey(const Key('pdf_settings_dual_page_mode_always')),
        findsOneWidget);
    expect(find.byKey(const Key('pdf_settings_dual_page_mode_never')),
        findsOneWidget);
  });

  testWidgets('點擊永遠雙頁選項後，onChanged 帶入 dualPageMode=always',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => notified = prefs);

    await tester.tap(find.byKey(const Key('pdf_settings_dual_page_mode_always')));
    await tester.pump();

    expect(notified?.dualPageMode, DualPageMode.always);
  });

  testWidgets('點擊永遠單頁選項後，onChanged 帶入 dualPageMode=never',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(dualPageMode: DualPageMode.always),
      (prefs) => notified = prefs,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_dual_page_mode_never')));
    await tester.pump();

    expect(notified?.dualPageMode, DualPageMode.never);
  });

  testWidgets('prefs.dualPageMode 為 null 時（未持久化過），不因為初始 build 就觸發 onChanged',
      (tester) async {
    var callCount = 0;
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) => callCount++);

    expect(callCount, 0);
  });

  testWidgets(
      '已持久化 dualPageMode 時，調整濾鏡分頁不會清空 dualPageMode（回歸檢查）',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(
        dualPageMode: DualPageMode.always,
        pdfContrast: 0,
      ),
      (prefs) => notified = prefs,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_contrast_increment')));
    await tester.pump();

    expect(notified?.pdfContrast, greaterThan(0));
    expect(notified?.dualPageMode, DualPageMode.always); // 關鍵斷言：未被清空
  });

  testWidgets('顯示分頁新增封面獨立開關', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(find.byKey(const Key('pdf_settings_dual_page_cover_alone')),
        findsOneWidget);
  });

  testWidgets('封面獨立開關初始值反映 prefs（未持久化時預設開啟）', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('pdf_settings_dual_page_cover_alone')))
          .value,
      isTrue,
    );
  });

  testWidgets('關閉封面獨立開關後，onChanged 帶入 dualPageCoverAlone=false',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => notified = prefs);

    await tester
        .tap(find.byKey(const Key('pdf_settings_dual_page_cover_alone')));
    await tester.pump();

    expect(notified?.dualPageCoverAlone, isFalse);
  });

  testWidgets(
      '已持久化 dualPageCoverAlone=false 時，調整雙頁模式不會清空該欄位（回歸檢查）',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(dualPageCoverAlone: false),
      (prefs) => notified = prefs,
    );

    await tester
        .tap(find.byKey(const Key('pdf_settings_dual_page_mode_always')));
    await tester.pump();

    expect(notified?.dualPageMode, DualPageMode.always);
    expect(notified?.dualPageCoverAlone, isFalse); // 關鍵斷言：未被清空
  });

  testWidgets(
      '顯示分頁新增控制項後仍可正常渲染，不觸發 RenderFlex overflow（審查修正）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('顯示分頁新增頁面方向兩個選項按鈕', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(find.byKey(const Key('pdf_settings_dual_page_direction_ltr')),
        findsOneWidget);
    expect(find.byKey(const Key('pdf_settings_dual_page_direction_rtl')),
        findsOneWidget);
  });

  testWidgets('點擊左到右選項後，onChanged 帶入 dualPageDirection=ltr', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(dualPageDirection: DualPageDirection.rtl),
      (prefs) => notified = prefs,
    );

    // 方向選項在顯示分頁底部，需先捲動才能點擊
    await tester.ensureVisible(
        find.byKey(const Key('pdf_settings_dual_page_direction_ltr')));
    await tester.tap(find.byKey(const Key('pdf_settings_dual_page_direction_ltr')));
    await tester.pump();

    expect(notified?.dualPageDirection, DualPageDirection.ltr);
  });

  testWidgets(
      '點擊右到左選項後，onChanged 帶入 dualPageDirection=rtl（未持久化時預設即為 rtl）',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => notified = prefs);

    // 方向選項在顯示分頁底部，需先捲動才能點擊
    await tester.ensureVisible(
        find.byKey(const Key('pdf_settings_dual_page_direction_rtl')));
    await tester.tap(find.byKey(const Key('pdf_settings_dual_page_direction_rtl')));
    await tester.pump();

    expect(notified?.dualPageDirection, DualPageDirection.rtl);
  });

  testWidgets(
      '已持久化 dualPageDirection=ltr 時，調整封面獨立開關不會清空該欄位（回歸檢查）',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(dualPageDirection: DualPageDirection.ltr),
      (prefs) => notified = prefs,
    );

    // 封面獨立開關在顯示分頁中間偏下，需先捲動才能點擊
    await tester.ensureVisible(
        find.byKey(const Key('pdf_settings_dual_page_cover_alone')));
    await tester
        .tap(find.byKey(const Key('pdf_settings_dual_page_cover_alone')));
    await tester.pump();

    expect(notified?.dualPageCoverAlone, isFalse);
    expect(notified?.dualPageDirection,
        DualPageDirection.ltr); // 關鍵斷言：未被清空
  });

  testWidgets('頁尾開關初始值反映 prefs（未持久化時預設開啟）', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('pdf_settings_show_footer')))
          .value,
      isTrue,
    );
  });

  testWidgets('已持久化 showFooter=false 時，頁尾開關初始值反映為關閉', (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(showFooter: false),
      (_) {},
    );

    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('pdf_settings_show_footer')))
          .value,
      isFalse,
    );
  });

  testWidgets('關閉頁尾開關後，onChanged 帶入 showFooter=false', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => notified = prefs);

    await tester.ensureVisible(
        find.byKey(const Key('pdf_settings_show_footer')));
    await tester.tap(find.byKey(const Key('pdf_settings_show_footer')));
    await tester.pump();

    expect(notified?.showFooter, isFalse);
  });

  testWidgets('已持久化 showFooter=false 時，調整雙頁模式不會清空該欄位（回歸檢查）',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(showFooter: false),
      (prefs) => notified = prefs,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_dual_page_mode_always')));
    await tester.pump();

    expect(notified?.dualPageMode, DualPageMode.always);
    expect(notified?.showFooter, isFalse, reason: '關鍵斷言：未被清空');
  });

  testWidgets('點擊關閉按鈕後，Bottom Sheet 關閉（Navigator.pop 生效）', (tester) async {
    await _pumpModalSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(find.byType(PdfSettingsSheet), findsOneWidget);

    await tester.tap(find.byKey(const Key('pdf_settings_close_button')));
    await tester.pumpAndSettle();

    expect(find.byType(PdfSettingsSheet), findsNothing);
  });
}

Future<void> _pumpSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged, {
  VoidCallback onRequestManualCrop = _noopVoid,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PdfSettingsSheet(
        prefs: prefs,
        onChanged: onChanged,
        onRequestManualCrop: onRequestManualCrop,
      ),
    ),
  ));
}

void _noopVoid() {}

Future<void> _pumpModalSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged, {
  VoidCallback onRequestManualCrop = _noopVoid,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            enableDrag: false,
            builder: (_) => PdfSettingsSheet(
              prefs: prefs,
              onChanged: onChanged,
              onRequestManualCrop: onRequestManualCrop,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
