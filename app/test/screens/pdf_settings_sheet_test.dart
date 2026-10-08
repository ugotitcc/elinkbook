import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_page_turn_animation.dart';
import 'package:elinkbook/reader/pdf_page_turn_mode.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/screens/pdf_settings_sheet.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

import '../support/full_book_reader_prefs.dart';

void main() {
  testWidgets('三個分頁標籤皆存在', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(find.byKey(const Key('pdf_settings_tab_display')), findsOneWidget);
    expect(find.byKey(const Key('pdf_settings_tab_filters')), findsOneWidget);
    expect(find.byKey(const Key('pdf_settings_tab_crop')), findsOneWidget);
  });

  testWidgets('點擊 Fit Width 選項後，onChanged 帶入 pdfFitMode=fitWidth', (
    tester,
  ) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => notified = prefs,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_fit_mode_fit_width')));
    await tester.pump();

    expect(notified?.pdfFitMode, PdfFitMode.fitWidth);
  });

  testWidgets('點擊真實比例 1:1 選項後，onChanged 帶入 pdfFitMode=actualSize', (
    tester,
  ) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => notified = prefs,
    );

    await tester.tap(
      find.byKey(const Key('pdf_settings_fit_mode_actual_size')),
    );
    await tester.pump();

    expect(notified?.pdfFitMode, PdfFitMode.actualSize);
  });

  testWidgets('點擊 Page-fit 選項後，onChanged 帶入 pdfFitMode=pageFit', (
    tester,
  ) async {
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

  testWidgets('prefs.pdfFitMode 為 null 時（未持久化過），不因為初始 build 就觸發 onChanged', (
    tester,
  ) async {
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
          .widget<Slider>(find.byKey(const Key('pdf_settings_contrast_slider')))
          .value,
      30,
    );
    expect(
      tester
          .widget<Slider>(
            find.byKey(const Key('pdf_settings_brightness_slider')),
          )
          .value,
      -20,
    );
  });

  testWidgets('prefs.pdfContrast／pdfBrightness 為 null 時，滑桿顯示預設值 0', (
    tester,
  ) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Slider>(find.byKey(const Key('pdf_settings_contrast_slider')))
          .value,
      0,
    );
    expect(
      tester
          .widget<Slider>(
            find.byKey(const Key('pdf_settings_brightness_slider')),
          )
          .value,
      0,
    );
  });

  testWidgets('拖動對比度滑桿後，onChanged 帶入新的 pdfContrast，其餘 PDF 欄位不變', (
    tester,
  ) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfContrast: 0, pdfBrightness: 15),
      (prefs) => notified = prefs,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pdf_settings_contrast_increment')));
    await tester.pump();

    expect(notified?.pdfContrast, greaterThan(0));
    expect(notified?.pdfBrightness, 15);
  });

  testWidgets('拖動亮度滑桿後，onChanged 帶入新的 pdfBrightness', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => notified = prefs,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('pdf_settings_brightness_decrement')),
    );
    await tester.pump();

    expect(notified?.pdfBrightness, lessThan(0));
  });

  testWidgets('濾鏡分頁存在加粗強度滑桿，初始值反映 prefs（0..1 換算為 0..100 顯示）', (tester) async {
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
            find.byKey(const Key('pdf_settings_bold_strength_slider')),
          )
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
            find.byKey(const Key('pdf_settings_bold_strength_slider')),
          )
          .value,
      0,
    );
  });

  testWidgets('拖動加粗強度滑桿後，onChanged 帶入新的 pdfBoldStrength（0..1），其餘 PDF 欄位不變', (
    tester,
  ) async {
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

    // 視覺還原（VISUAL_ANALYSIS.md）後濾鏡分頁改為可捲動（見
    // pdf_settings_sheet.dart _buildFiltersTab），「加粗強度」列可能落在
    // 可視範圍外，先捲動確保可點擊。
    await tester.ensureVisible(
      find.byKey(const Key('pdf_settings_bold_strength_increment')),
    );
    await tester.tap(
      find.byKey(const Key('pdf_settings_bold_strength_increment')),
    );
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

    expect(
      find.byKey(const Key('pdf_settings_crop_mode_none')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('pdf_settings_crop_mode_auto')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('pdf_settings_crop_mode_manual')),
      findsOneWidget,
    );
  });

  testWidgets('點擊手動選區按鈕後，觸發 onRequestManualCrop（不直接改變 pdfCropMode）', (
    tester,
  ) async {
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
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => notified = prefs,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_auto')));
    await tester.pump();

    expect(notified?.pdfCropMode, PdfCropMode.autoDetect);
  });

  testWidgets('已持久化 pdfCropRect 時，調整其他分頁的滑桿不會清空 pdfCropRect（關鍵回歸檢查）', (
    tester,
  ) async {
    BookReaderPrefs? notified;
    const existingCropRect = PdfCropRect(
      left: 0.02,
      top: 0.03,
      right: 0.98,
      bottom: 0.97,
    );
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

    expect(
      find.byKey(const Key('pdf_settings_dual_page_mode_auto')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('pdf_settings_dual_page_mode_always')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('pdf_settings_dual_page_mode_never')),
      findsOneWidget,
    );
  });

  testWidgets('點擊永遠雙頁選項後，onChanged 帶入 dualPageMode=always', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => notified = prefs,
    );

    await tester.tap(
      find.byKey(const Key('pdf_settings_dual_page_mode_always')),
    );
    await tester.pump();

    expect(notified?.dualPageMode, DualPageMode.always);
  });

  testWidgets('點擊永遠單頁選項後，onChanged 帶入 dualPageMode=never', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(dualPageMode: DualPageMode.always),
      (prefs) => notified = prefs,
    );

    await tester.tap(
      find.byKey(const Key('pdf_settings_dual_page_mode_never')),
    );
    await tester.pump();

    expect(notified?.dualPageMode, DualPageMode.never);
  });

  testWidgets('prefs.dualPageMode 為 null 時（未持久化過），不因為初始 build 就觸發 onChanged', (
    tester,
  ) async {
    var callCount = 0;
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) => callCount++);

    expect(callCount, 0);
  });

  testWidgets('已持久化 dualPageMode 時，調整濾鏡分頁不會清空 dualPageMode（回歸檢查）', (
    tester,
  ) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(dualPageMode: DualPageMode.always, pdfContrast: 0),
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

    expect(
      find.byKey(const Key('pdf_settings_dual_page_cover_alone')),
      findsOneWidget,
    );
  });

  testWidgets('封面獨立開關初始值反映 prefs（未持久化時預設開啟）', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('pdf_settings_dual_page_cover_alone')),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('關閉封面獨立開關後，onChanged 帶入 dualPageCoverAlone=false', (
    tester,
  ) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => notified = prefs,
    );

    // 翻頁模式群組新增後顯示分頁變高，開關被擠出可視區，先捲動到可見（epic-56 Issue 2）。
    await tester.dragUntilVisible(
      find.byKey(const Key('pdf_settings_dual_page_cover_alone')),
      find.byKey(const Key('pdf_settings_display_scroll')),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('pdf_settings_dual_page_cover_alone')),
    );
    await tester.pump();

    expect(notified?.dualPageCoverAlone, isFalse);
  });

  testWidgets('已持久化 dualPageCoverAlone=false 時，調整雙頁模式不會清空該欄位（回歸檢查）', (
    tester,
  ) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(dualPageCoverAlone: false),
      (prefs) => notified = prefs,
    );

    await tester.tap(
      find.byKey(const Key('pdf_settings_dual_page_mode_always')),
    );
    await tester.pump();

    expect(notified?.dualPageMode, DualPageMode.always);
    expect(notified?.dualPageCoverAlone, isFalse); // 關鍵斷言：未被清空
  });

  testWidgets('顯示分頁新增控制項後仍可正常渲染，不觸發 RenderFlex overflow（審查修正）', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('顯示分頁新增頁面方向兩個選項按鈕', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(
      find.byKey(const Key('pdf_settings_dual_page_direction_ltr')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('pdf_settings_dual_page_direction_rtl')),
      findsOneWidget,
    );
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
      find.byKey(const Key('pdf_settings_dual_page_direction_ltr')),
    );
    await tester.tap(
      find.byKey(const Key('pdf_settings_dual_page_direction_ltr')),
    );
    await tester.pump();

    expect(notified?.dualPageDirection, DualPageDirection.ltr);
  });

  testWidgets('點擊右到左選項後，onChanged 帶入 dualPageDirection=rtl（未持久化時預設即為 rtl）', (
    tester,
  ) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => notified = prefs,
    );

    // 方向選項在顯示分頁底部，需先捲動才能點擊
    await tester.ensureVisible(
      find.byKey(const Key('pdf_settings_dual_page_direction_rtl')),
    );
    await tester.tap(
      find.byKey(const Key('pdf_settings_dual_page_direction_rtl')),
    );
    await tester.pump();

    expect(notified?.dualPageDirection, DualPageDirection.rtl);
  });

  testWidgets('已持久化 dualPageDirection=ltr 時，調整封面獨立開關不會清空該欄位（回歸檢查）', (
    tester,
  ) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(dualPageDirection: DualPageDirection.ltr),
      (prefs) => notified = prefs,
    );

    // 封面獨立開關在顯示分頁中間偏下，需先捲動才能點擊
    await tester.ensureVisible(
      find.byKey(const Key('pdf_settings_dual_page_cover_alone')),
    );
    await tester.tap(
      find.byKey(const Key('pdf_settings_dual_page_cover_alone')),
    );
    await tester.pump();

    expect(notified?.dualPageCoverAlone, isFalse);
    expect(notified?.dualPageDirection, DualPageDirection.ltr); // 關鍵斷言：未被清空
  });

  testWidgets('頁尾開關初始值反映 prefs（未持久化時預設開啟）', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('pdf_settings_show_footer')),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('已持久化 showFooter=false 時，頁尾開關初始值反映為關閉', (tester) async {
    await _pumpSheet(tester, const BookReaderPrefs(showFooter: false), (_) {});

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('pdf_settings_show_footer')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('關閉頁尾開關後，onChanged 帶入 showFooter=false', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => notified = prefs,
    );

    await tester.ensureVisible(
      find.byKey(const Key('pdf_settings_show_footer')),
    );
    await tester.tap(find.byKey(const Key('pdf_settings_show_footer')));
    await tester.pump();

    expect(notified?.showFooter, isFalse);
  });

  testWidgets('已持久化 fullscreen=true 時，全螢幕模式開關初始值反映為開啟', (tester) async {
    await _pumpSheet(tester, const BookReaderPrefs(fullscreen: true), (_) {});

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('pdf_settings_fullscreen')),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('開啟全螢幕模式開關後，onChanged 帶入 fullscreen=true', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => notified = prefs,
    );

    await tester.ensureVisible(
      find.byKey(const Key('pdf_settings_fullscreen')),
    );
    await tester.tap(find.byKey(const Key('pdf_settings_fullscreen')));
    await tester.pump();

    expect(notified?.fullscreen, isTrue);
  });

  testWidgets('已持久化 showFooter=false 時，調整雙頁模式不會清空該欄位（回歸檢查）', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(showFooter: false),
      (prefs) => notified = prefs,
    );

    await tester.tap(
      find.byKey(const Key('pdf_settings_dual_page_mode_always')),
    );
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

  testWidgets('翻頁模式：未覆寫（null）時顯示為逐頁，且不顯示「換頁動畫」選項', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});
    expect(find.byKey(const Key('pdf_settings_page_turn_mode_paginated')),
        findsOneWidget);
    expect(find.byKey(const Key('pdf_settings_page_turn_mode_scroll')),
        findsOneWidget);
    expect(find.byKey(const Key('pdf_settings_page_turn_animation_slide')),
        findsNothing);
    expect(find.byKey(const Key('pdf_settings_page_turn_animation_none')),
        findsNothing);
  });
  testWidgets('點擊「連續捲動」後，onChanged 帶入 pdfPageTurnMode=scroll 且「換頁動畫」選項出現',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (p) => notified = p);
    await tester
        .tap(find.byKey(const Key('pdf_settings_page_turn_mode_scroll')));
    await tester.pump();
    expect(notified?.pdfPageTurnMode, PdfPageTurnMode.scroll);
    await tester.dragUntilVisible(
      find.byKey(const Key('pdf_settings_page_turn_animation_slide')),
      find.byKey(const Key('pdf_settings_display_scroll')),
      const Offset(0, -100),
    );
    expect(find.byKey(const Key('pdf_settings_page_turn_animation_slide')),
        findsOneWidget);
  });
  testWidgets('點擊「逐頁」後，onChanged 帶入 pdfPageTurnMode=paginated 且「換頁動畫」選項隱藏',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.scroll),
      (p) => notified = p,
    );
    await tester
        .tap(find.byKey(const Key('pdf_settings_page_turn_mode_paginated')));
    await tester.pump();
    expect(notified?.pdfPageTurnMode, PdfPageTurnMode.paginated);
    expect(find.byKey(const Key('pdf_settings_page_turn_animation_slide')),
        findsNothing);
  });
  testWidgets('隱藏不清除：換頁動畫＝無，切到逐頁再切回連續捲動後，動畫值仍為無並隨 onChanged 帶出',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(
        pdfPageTurnMode: PdfPageTurnMode.scroll,
        pdfPageTurnAnimation: PdfPageTurnAnimation.none,
      ),
      (p) => notified = p,
    );
    await tester
        .tap(find.byKey(const Key('pdf_settings_page_turn_mode_paginated')));
    await tester.pump();
    expect(notified?.pdfPageTurnAnimation, PdfPageTurnAnimation.none,
        reason: '隱藏時動畫值仍須帶回，不可清成 null 或 slide');
    await tester
        .tap(find.byKey(const Key('pdf_settings_page_turn_mode_scroll')));
    await tester.pump();
    await tester
        .tap(find.byKey(const Key('pdf_settings_dual_page_mode_always')));
    await tester.pump();
    expect(notified?.pdfPageTurnMode, PdfPageTurnMode.scroll);
    expect(notified?.pdfPageTurnAnimation, PdfPageTurnAnimation.none,
        reason: '切回連續捲動後使用者先前的動畫選擇必須還在');
  });
  testWidgets('已持久化 pdfPageTurnMode＝scroll 時，調整濾鏡分頁不會清空翻頁模式（回歸檢查）',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.scroll),
      (p) => notified = p,
    );
    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_contrast_increment')));
    await tester.pump();
    expect(notified?.pdfPageTurnMode, PdfPageTurnMode.scroll,
        reason: '關鍵斷言：未被清空');
  });
  testWidgets('英文介面下翻頁模式小標題正確以英文渲染', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {},
        locale: const Locale('en'));
    expect(find.text('Page-turn mode'), findsOneWidget);
  });
  testWidgets('換頁動畫兩個選項皆存在', (tester) async {
    await _pumpSheet(tester, const BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.scroll), (_) {});

    // 捲動到換頁動畫選項可見（需要更多捲動量）
    await tester.dragUntilVisible(
      find.byKey(const Key('pdf_settings_page_turn_animation_slide')),
      find.byKey(const Key('pdf_settings_display_scroll')),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('pdf_settings_page_turn_animation_slide')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('pdf_settings_page_turn_animation_none')),
      findsOneWidget,
    );
  });

  testWidgets('點擊「無」選項後，onChanged 帶入 pdfPageTurnAnimation=none', (
    tester,
  ) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.scroll),
      (prefs) => notified = prefs,
    );

    // 捲動到換頁動畫選項可見
    await tester.dragUntilVisible(
      find.byKey(const Key('pdf_settings_page_turn_animation_none')),
      find.byKey(const Key('pdf_settings_display_scroll')),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('pdf_settings_page_turn_animation_none')),
    );
    await tester.pump();

    expect(notified?.pdfPageTurnAnimation, PdfPageTurnAnimation.none);
  });

  testWidgets('點擊「滑動」選項後，onChanged 帶入 pdfPageTurnAnimation=slide', (
    tester,
  ) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.scroll, pdfPageTurnAnimation: PdfPageTurnAnimation.none),
      (prefs) => notified = prefs,
    );

    // 捲動到換頁動畫選項可見
    await tester.dragUntilVisible(
      find.byKey(const Key('pdf_settings_page_turn_animation_slide')),
      find.byKey(const Key('pdf_settings_display_scroll')),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('pdf_settings_page_turn_animation_slide')),
    );
    await tester.pump();

    expect(notified?.pdfPageTurnAnimation, PdfPageTurnAnimation.slide);
  });

  testWidgets(
    '已持久化 pdfPageTurnAnimation 時，調整濾鏡分頁不會清空 pdfPageTurnAnimation（回歸檢查）',
    (tester) async {
      BookReaderPrefs? notified;
      await _pumpSheet(
        tester,
        const BookReaderPrefs(pdfPageTurnAnimation: PdfPageTurnAnimation.none),
        (prefs) => notified = prefs,
      );

      await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('pdf_settings_contrast_increment')),
      );
      await tester.pump();

      expect(
        notified?.pdfPageTurnAnimation,
        PdfPageTurnAnimation.none,
      ); // 關鍵斷言：未被清空
    },
  );

  testWidgets('isEinkMode: true 時，濾鏡分頁 3 個數值列皆改為 EBStepper，不存在任何 '
      'Slider，且頂列不重複顯示數值文字（比照 review-plan-issue-2.md C1 對 '
      'ReaderSettingsSheet._buildSliderRow 已建立的先例——EBStepper 內部已顯示'
      '一次，頂列不應再顯示第二次），點擊 + 觸發 onChanged'
      '（epic-39-layout-settings-redesign Issue 5）', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfContrast: 20),
      (prefs) => notified = prefs,
      isEinkMode: true,
    );
    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    for (final keyPrefix in [
      'pdf_settings_contrast',
      'pdf_settings_brightness',
      'pdf_settings_bold_strength',
    ]) {
      expect(
        find.byKey(Key('${keyPrefix}_value')),
        findsOneWidget,
        reason: '$keyPrefix 應改為 EBStepper（僅 EBStepper 具備 _value Key）',
      );
    }
    expect(
      find.byType(Slider),
      findsNothing,
      reason: '濾鏡分頁在 E-Ink 模式下不應存在任何 Slider',
    );
    expect(
      find.text('20'),
      findsOneWidget,
      reason: '對比度數值只應在 EBStepper 內顯示一次，頂列不應重複顯示',
    );
    // 審查修正 M3（review-plan-issue-5.md）：一併確認 _decrement 按鈕存在，
    // 不只驗證 +（EBStepper 本身的 +/- 邊界行為已在 Issue 1 完整測試，這裡
    // 只需確認整合層兩顆按鈕都確實被渲染出來）。
    expect(
      find.byKey(const Key('pdf_settings_contrast_decrement')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_contrast_increment')));
    await tester.pump();

    expect(notified, isNotNull);
    expect(notified!.pdfContrast, greaterThan(20));
  });

  testWidgets('isEinkMode: false（預設）時，濾鏡分頁維持既有 Slider 且頂列保留數值文字'
      '（一般主題 Slider 不具備數值回饋能力，比照 review-plan-issue-2.md C1 '
      '先例，既有行為零回歸）（epic-39-layout-settings-redesign Issue 5）', (tester) async {
    await _pumpSheet(tester, const BookReaderPrefs(pdfContrast: 20), (_) {});
    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('pdf_settings_contrast_slider')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('pdf_settings_contrast_value')), findsNothing);
    expect(find.text('20'), findsOneWidget, reason: '一般主題下頂列應保留數值文字');
  });

  testWidgets('PdfSettingsSheet 在 E-Ink 模式下選中項目呈現高對比底色', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildEinkThemeData(),
        home: Scaffold(
          body: PdfSettingsSheet(
            prefs: const BookReaderPrefs(pdfFitMode: PdfFitMode.fitWidth),
            onChanged: (_) {},
            onRequestManualCrop: () {},
            isEinkMode: true,
          ),
        ),
      ),
    );

    // 【審查修正 Important】key 直接掛在帶 BoxDecoration 的 Container 上
    // （見 Task 1 ReaderOptionTile 實作），不再用
    // find.descendant(...).first 這種依賴子樹結構的脆弱寫法。
    expect(
      find.byKey(const Key('pdf_settings_fit_mode_fit_width')),
      findsOneWidget,
    );
    final container = tester.widget<Container>(
      find.byKey(const Key('pdf_settings_fit_mode_fit_width')),
    );
    expect((container.decoration as BoxDecoration).color, Colors.black);
  });

  testWidgets('Fit 模式群組改用 EBOptionChipGroup 後，3 個選項皆顯示 spec.md 選項標籤'
      '對照表定義的短標籤（epic-39-layout-settings-redesign Issue 5）', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    for (final item in [
      ('page_fit', '整頁'),
      ('fit_width', '頁寬'),
      ('actual_size', '原比'),
    ]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('pdf_settings_fit_mode_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'pdf_settings_fit_mode_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets('雙頁模式群組改用 EBOptionChipGroup 後，3 個選項皆顯示短標籤'
      '（epic-39-layout-settings-redesign Issue 5）', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    for (final item in [('auto', '自動'), ('always', '雙頁'), ('never', '單頁')]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('pdf_settings_dual_page_mode_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'pdf_settings_dual_page_mode_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets('頁面方向群組改用 EBOptionChipGroup 後，2 個選項皆顯示短標籤'
      '（epic-39-layout-settings-redesign Issue 5）', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    for (final item in [('ltr', '左翻'), ('rtl', '右翻')]) {
      final (suffix, label) = item;
      await tester.ensureVisible(
        find.byKey(Key('pdf_settings_dual_page_direction_$suffix')),
      );
      expect(
        find.descendant(
          of: find.byKey(Key('pdf_settings_dual_page_direction_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'pdf_settings_dual_page_direction_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets('換頁動畫群組改用 EBOptionChipGroup 後，2 個選項皆顯示短標籤'
      '（epic-39-layout-settings-redesign Issue 5）', (tester) async {
    await _pumpSheet(tester, const BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.scroll), (_) {});

    for (final item in [('slide', '滑動'), ('none', '無')]) {
      final (suffix, label) = item;
      await tester.dragUntilVisible(
        find.byKey(Key('pdf_settings_page_turn_animation_$suffix')),
        find.byKey(const Key('pdf_settings_display_scroll')),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(Key('pdf_settings_page_turn_animation_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'pdf_settings_page_turn_animation_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets('裁切模式群組改用 EBOptionChipGroup 後，「不裁」「智慧」「手動」三個選項'
      '皆顯示短標籤（epic-39-layout-settings-redesign Issue 5）', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();

    for (final item in [('none', '不裁'), ('auto', '智慧'), ('manual', '手動')]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('pdf_settings_crop_mode_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'pdf_settings_crop_mode_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets('裁切模式群組選中態機制正確運作：一般選項相符時顯示選中樣式，'
      '「手動選區」動作型項目無論 groupValue 為何皆恆為未選中樣式'
      '（審查修正 I1，review-plan-issue-5.md：補上正反對照斷言，避免僅斷言'
      '未選中態時，若選取機制整體失效〔例如 groupValue 傳遞錯誤導致全部'
      '晶片皆渲染為未選中〕仍會誤判通過；審查修正 I4，review-issues.md／'
      'I1，review-spec.md：EBOptionChipItem.onTap 項目由 forceUnselected '
      '保證，取代舊 bool sentinel 寫法後行為零回歸）'
      '（epic-39-layout-settings-redesign Issue 5）', (tester) async {
    // 情境一：groupValue 為一般選項（autoDetect），驗證選中態機制正常
    // 運作，「手動選區」在此一般情境下也維持未選中（基準對照）。
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfCropMode: PdfCropMode.autoDetect),
      (_) {},
    );
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();

    final context = tester.element(
      find.byKey(const Key('pdf_settings_crop_mode_auto')),
    );
    final colorScheme = Theme.of(context).colorScheme;

    final autoContainer = tester.widget<Container>(
      find.byKey(const Key('pdf_settings_crop_mode_auto')),
    );
    expect(
      (autoContainer.decoration as BoxDecoration).color,
      colorScheme.primary,
      reason:
          '選中態項目背景色應為 primary（視覺還原，見'
          ' docs/research/uiux/VISUAL_ANALYSIS.md），證明選取機制正常運作',
    );

    final manualContainerCase1 = tester.widget<Container>(
      find.byKey(const Key('pdf_settings_crop_mode_manual')),
    );
    expect(
      (manualContainerCase1.decoration as BoxDecoration).color,
      colorScheme.surface,
      reason: '手動選區項目在一般情境下應維持未選中樣式',
    );

    // 情境二（epic-60 改變設計）：groupValue 等於 PdfCropMode.manual
    // （使用者先前已完成一次手動裁切、_cropMode 已持久化為 manual）時，
    // 「手動選區」項目要反白，讓使用者看得出目前是手動模式；其餘兩個
    // 一般選項維持未選中。原設計（恆未選中）導致三個按鈕全不反白。
    //
    // 先清空畫面再重建：同型別 widget 連續 pump 會重用舊 State，
    // `_cropMode` 只在 initState 讀取，會停在情境一的 autoDetect。舊版情境二
    // 因為「手動」恆未選中，即使實際沒測到 manual 也照樣通過（epic-60 發現）。
    await tester.pumpWidget(const SizedBox());
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfCropMode: PdfCropMode.manual),
      (_) {},
    );
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();

    Color? colorOf(String suffix) => (tester
            .widget<Container>(find.byKey(Key('pdf_settings_crop_mode_$suffix')))
            .decoration as BoxDecoration)
        .color;

    expect(colorOf('manual'), colorScheme.primary,
        reason: '目前模式為手動時，「手動」應顯示選中樣式（epic-60）');
    expect(colorOf('none'), colorScheme.surface);
    expect(colorOf('auto'), colorScheme.surface);
  });

  testWidgets('目前為手動裁切時點「不裁」：反白從「手動」移到「不裁」，'
      '且 onChanged 帶入 pdfCropMode=none、保留原 pdfCropRect（epic-60 審查 M-2）',
      (tester) async {
    BookReaderPrefs? notified;
    const rect = PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9);
    await _pumpSheet(
      tester,
      const BookReaderPrefs(
        pdfCropMode: PdfCropMode.manual,
        pdfCropRect: rect,
      ),
      (prefs) => notified = prefs,
    );
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();

    final primary = Theme.of(
      tester.element(find.byKey(const Key('pdf_settings_crop_mode_none'))),
    ).colorScheme.primary;
    Color? colorOf(String suffix) => (tester
            .widget<Container>(find.byKey(Key('pdf_settings_crop_mode_$suffix')))
            .decoration as BoxDecoration)
        .color;

    expect(colorOf('manual'), primary, reason: '起始：手動反白');

    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_none')));
    await tester.pumpAndSettle();

    expect(colorOf('none'), primary, reason: '反白移到「不裁」');
    expect(colorOf('manual'), isNot(primary), reason: '「手動」不再反白');
    expect(notified?.pdfCropMode, PdfCropMode.none);
    expect(notified?.pdfCropRect, rect, reason: '裁切範圍保留，之後切回手動不必重畫');
  });

  testWidgets('E-Ink 主題下，目前為手動裁切時「手動」呈現黑底、其他兩顆白底'
      '（epic-60 審查 M-3）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildEinkThemeData(),
        home: Scaffold(
          body: PdfSettingsSheet(
            prefs: const BookReaderPrefs(pdfCropMode: PdfCropMode.manual),
            onChanged: (_) {},
            onRequestManualCrop: () {},
            isEinkMode: true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();

    Color? colorOf(String suffix) => (tester
            .widget<Container>(find.byKey(Key('pdf_settings_crop_mode_$suffix')))
            .decoration as BoxDecoration)
        .color;

    expect(colorOf('manual'), Colors.black);
    expect(colorOf('none'), Colors.white);
    expect(colorOf('auto'), Colors.white);
  });

  testWidgets('目前已是手動裁切時，再點「手動」仍觸發 onRequestManualCrop（可重新框選），'
      '且不呼叫 onChanged（epic-60）', (tester) async {
    var requestCount = 0;
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfCropMode: PdfCropMode.manual),
      (prefs) => notified = prefs,
      onRequestManualCrop: () => requestCount++,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_manual')));
    await tester.pump();

    expect(requestCount, 1);
    expect(notified, isNull);
  });

  testWidgets('英文介面下分頁籤/Fit 模式/裁切模式文字正確以英文渲染', (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(),
      (_) {},
      locale: const Locale('en'),
    );

    expect(find.text('Display'), findsOneWidget);
    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('Crop'), findsOneWidget);
  });

  group('全欄位保留守衛（Issue 10）：種子 33 欄位，操作一個控制項後只有該欄位改變', () {
    Future<BookReaderPrefs?> tapAndCapture(
      WidgetTester tester,
      String keyName,
    ) async {
      BookReaderPrefs? notified;
      await _pumpSheet(
        tester,
        fullBookReaderPrefsSeed,
        (prefs) => notified = prefs,
      );
      await tester.ensureVisible(find.byKey(Key(keyName)));
      await tester.tap(find.byKey(Key(keyName)));
      await tester.pump();
      return notified;
    }

    testWidgets('切換全螢幕 → 只有 fullscreen 改變', (tester) async {
      final notified = await tapAndCapture(tester, 'pdf_settings_fullscreen');
      expect(notified, isNotNull);
      expect(notified!.fullscreen, isFalse);
      expectPrefsPreserved(notified, fullBookReaderPrefsSeed,
          except: {'fullscreen'});
    });

    testWidgets('切換頁尾顯示 → 只有 show_footer 改變', (tester) async {
      final notified = await tapAndCapture(tester, 'pdf_settings_show_footer');
      expect(notified, isNotNull);
      expect(notified!.showFooter, isFalse);
      expectPrefsPreserved(notified, fullBookReaderPrefsSeed,
          except: {'show_footer'});
    });

    testWidgets('切換封面獨立 → 只有 dual_page_cover_alone 改變', (tester) async {
      final notified =
          await tapAndCapture(tester, 'pdf_settings_dual_page_cover_alone');
      expect(notified, isNotNull);
      expect(notified!.dualPageCoverAlone, isTrue);
      expectPrefsPreserved(notified, fullBookReaderPrefsSeed,
          except: {'dual_page_cover_alone'});
    });
  });
}

Future<void> _pumpSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged, {
  VoidCallback onRequestManualCrop = _noopVoid,
  bool isEinkMode = false,
  Locale locale = const Locale('zh', 'TW'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PdfSettingsSheet(
          prefs: prefs,
          onChanged: onChanged,
          onRequestManualCrop: onRequestManualCrop,
          isEinkMode: isEinkMode,
        ),
      ),
    ),
  );
}

void _noopVoid() {}

Future<void> _pumpModalSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged, {
  VoidCallback onRequestManualCrop = _noopVoid,
  bool isEinkMode = false,
  Locale locale = const Locale('zh', 'TW'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
                isEinkMode: isEinkMode,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
