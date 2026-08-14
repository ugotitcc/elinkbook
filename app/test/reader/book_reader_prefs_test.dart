import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/column_mode.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_page_turn_animation.dart';
import 'package:elinkbook/reader/writing_mode.dart';

void main() {
  test('BookReaderPrefs.empty 所有欄位皆為 null', () {
    const prefs = BookReaderPrefs.empty;
    expect(prefs.fontFamily, isNull);
    expect(prefs.fontSize, isNull);
    expect(prefs.fontWeight, isNull);
    expect(prefs.lineHeight, isNull);
    expect(prefs.paragraphSpacing, isNull);
    expect(prefs.pageMargins, isNull);
    expect(prefs.textAlign, isNull);
    expect(prefs.publisherStyles, isNull);
    expect(prefs.writingModeOverride, isNull);
    expect(prefs.pageTurnModeOverride, isNull);
    expect(prefs.screenOrientationOverride, isNull);
    expect(prefs.pdfFitMode, isNull);
    expect(prefs.pdfContrast, isNull);
    expect(prefs.pdfBrightness, isNull);
    expect(prefs.pdfBoldStrength, isNull);
    expect(prefs.pdfCropMode, isNull);
    expect(prefs.pdfCropRect, isNull);
    expect(prefs.dualPageMode, isNull);
    expect(prefs.dualPageCoverAlone, isNull);
    expect(prefs.dualPageDirection, isNull);
    expect(prefs.marginTop, isNull);
    expect(prefs.marginBottom, isNull);
    expect(prefs.marginLeft, isNull);
    expect(prefs.marginRight, isNull);
    expect(prefs.letterSpacing, isNull);
    expect(prefs.pdfPageTurnAnimation, isNull);
  });

  test('兩個欄位值完全相同的 BookReaderPrefs 視為相等', () {
    const a = BookReaderPrefs(
      fontFamily: 'SourceHanSansTC',
      fontSize: 18,
      writingModeOverride: WritingMode.vertical,
    );
    const b = BookReaderPrefs(
      fontFamily: 'SourceHanSansTC',
      fontSize: 18,
      writingModeOverride: WritingMode.vertical,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('任一欄位值不同時視為不相等', () {
    const a = BookReaderPrefs(fontSize: 18);
    const b = BookReaderPrefs(fontSize: 20);
    expect(a, isNot(b));
  });

  test('PDF 欄位值完全相同的 BookReaderPrefs 視為相等', () {
    const a = BookReaderPrefs(
      pdfFitMode: PdfFitMode.fitWidth,
      pdfContrast: 20,
      pdfBrightness: -10,
      pdfBoldStrength: 0.5,
      pdfCropMode: PdfCropMode.manual,
      pdfCropRect: PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
    );
    const b = BookReaderPrefs(
      pdfFitMode: PdfFitMode.fitWidth,
      pdfContrast: 20,
      pdfBrightness: -10,
      pdfBoldStrength: 0.5,
      pdfCropMode: PdfCropMode.manual,
      pdfCropRect: PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('PDF 欄位任一不同時視為不相等', () {
    const a = BookReaderPrefs(pdfContrast: 20);
    const b = BookReaderPrefs(pdfContrast: 30);
    expect(a, isNot(b));
  });

  test('toMap／fromMap round-trip 保留所有欄位（含 book_id）', () {
    const prefs = BookReaderPrefs(
      fontFamily: 'TaiwanPearl',
      fontSize: 18.5,
      fontWeight: 1.75,
      lineHeight: 1.6,
      paragraphSpacing: 12,
      pageMargins: 20,
      textAlign: EpubTextAlign.justify,
      publisherStyles: false,
      writingModeOverride: WritingMode.horizontal,
      pageTurnModeOverride: PageTurnMode.scroll,
      screenOrientationOverride: ScreenOrientationSetting.lock90,
    );

    final map = prefs.toMap('book-1');
    expect(map['book_id'], 'book-1');
    expect(map['font_family'], 'TaiwanPearl');
    expect(map['publisher_styles'], 0);
    expect(map['writing_mode_override'], 'horizontal');

    final restored = BookReaderPrefs.fromMap(map);
    expect(restored, prefs);
  });

  test('toMap／fromMap round-trip 正確處理全部欄位皆為 null', () {
    const prefs = BookReaderPrefs.empty;
    final map = prefs.toMap('book-2');
    final restored = BookReaderPrefs.fromMap(map);
    expect(restored, prefs);
  });

  test('PDF 欄位的 toMap／fromMap round-trip 保留所有欄位', () {
    const prefs = BookReaderPrefs(
      pdfFitMode: PdfFitMode.actualSize,
      pdfContrast: 15.5,
      pdfBrightness: -5.5,
      pdfBoldStrength: 0.75,
      pdfCropMode: PdfCropMode.autoDetect,
      pdfCropRect: PdfCropRect(left: 0.02, top: 0.03, right: 0.98, bottom: 0.97),
    );

    final map = prefs.toMap('book-3');
    expect(map['pdf_fit_mode'], 'actualSize');
    expect(map['pdf_contrast'], 15.5);
    expect(map['pdf_brightness'], -5.5);
    expect(map['pdf_bold_strength'], 0.75);
    expect(map['pdf_crop_mode'], 'autoDetect');
    expect(map['pdf_crop_rect'], isA<String>());

    final restored = BookReaderPrefs.fromMap(map);
    expect(restored, prefs);
  });

  test('EPUB 讀取時 PDF 欄位恆為 null，反之 PDF 讀取時 EPUB 欄位恆為 null', () {
    const epubOnly = BookReaderPrefs(fontSize: 18, pdfContrast: null);
    final epubMap = epubOnly.toMap('book-4');
    expect(epubMap['pdf_fit_mode'], isNull);
    expect(epubMap['pdf_contrast'], isNull);
    expect(epubMap['pdf_crop_rect'], isNull);

    const pdfOnly = BookReaderPrefs(pdfContrast: 10, fontSize: null);
    final pdfMap = pdfOnly.toMap('book-5');
    expect(pdfMap['font_family'], isNull);
    expect(pdfMap['font_size'], isNull);
    expect(pdfMap['writing_mode_override'], isNull);
  });

  test('copyWith 只更新指定欄位，其餘欄位保留原值', () {
    const original = BookReaderPrefs(
      fontSize: 18,
      pdfFitMode: PdfFitMode.fitWidth,
      pdfContrast: 10,
      pdfCropMode: PdfCropMode.autoDetect,
    );

    final updated = original.copyWith(
      pdfCropRect:
          const PdfCropRect(left: 0.05, top: 0.05, right: 0.95, bottom: 0.95),
    );

    expect(updated.fontSize, 18);
    expect(updated.pdfFitMode, PdfFitMode.fitWidth);
    expect(updated.pdfContrast, 10);
    expect(updated.pdfCropMode, PdfCropMode.autoDetect);
    expect(
      updated.pdfCropRect,
      const PdfCropRect(left: 0.05, top: 0.05, right: 0.95, bottom: 0.95),
    );
  });

  test('copyWith 不傳任何參數時，回傳與原本欄位值完全相同（但非同一個 identity）的物件',
      () {
    const original = BookReaderPrefs(fontSize: 18, pdfContrast: -20);
    final copy = original.copyWith();

    expect(copy, original);
    expect(identical(copy, original), isFalse);
  });

  test('雙頁欄位值完全相同的 BookReaderPrefs 視為相等', () {
    const a = BookReaderPrefs(
      dualPageMode: DualPageMode.always,
      dualPageCoverAlone: false,
      dualPageDirection: DualPageDirection.rtl,
    );
    const b = BookReaderPrefs(
      dualPageMode: DualPageMode.always,
      dualPageCoverAlone: false,
      dualPageDirection: DualPageDirection.rtl,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('雙頁欄位任一不同時視為不相等', () {
    const a = BookReaderPrefs(dualPageMode: DualPageMode.always);
    const b = BookReaderPrefs(dualPageMode: DualPageMode.never);
    expect(a, isNot(b));
  });

  test('雙頁欄位的 toMap／fromMap round-trip 保留所有欄位', () {
    const prefs = BookReaderPrefs(
      dualPageMode: DualPageMode.never,
      dualPageCoverAlone: false,
      dualPageDirection: DualPageDirection.rtl,
    );

    final map = prefs.toMap('book-6');
    expect(map['dual_page_mode'], 'never');
    expect(map['dual_page_cover_alone'], 0);
    expect(map['dual_page_direction'], 'rtl');

    final restored = BookReaderPrefs.fromMap(map);
    expect(restored, prefs);
  });

  test('dualPageCoverAlone 為 true／false／null 皆正確 round-trip（避免布林值 0/1 轉換錯誤）',
      () {
    const withTrue = BookReaderPrefs(dualPageCoverAlone: true);
    final trueMap = withTrue.toMap('book-7');
    expect(trueMap['dual_page_cover_alone'], 1);
    expect(BookReaderPrefs.fromMap(trueMap).dualPageCoverAlone, isTrue);

    const withFalse = BookReaderPrefs(dualPageCoverAlone: false);
    final falseMap = withFalse.toMap('book-8');
    expect(falseMap['dual_page_cover_alone'], 0);
    expect(BookReaderPrefs.fromMap(falseMap).dualPageCoverAlone, isFalse);

    const withNull = BookReaderPrefs.empty;
    final nullMap = withNull.toMap('book-9');
    expect(nullMap['dual_page_cover_alone'], isNull);
    expect(BookReaderPrefs.fromMap(nullMap).dualPageCoverAlone, isNull);
  });

  test('換頁動畫欄位值完全相同的 BookReaderPrefs 視為相等', () {
    const a = BookReaderPrefs(pdfPageTurnAnimation: PdfPageTurnAnimation.none);
    const b = BookReaderPrefs(pdfPageTurnAnimation: PdfPageTurnAnimation.none);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('換頁動畫欄位不同時視為不相等', () {
    const a = BookReaderPrefs(pdfPageTurnAnimation: PdfPageTurnAnimation.slide);
    const b = BookReaderPrefs(pdfPageTurnAnimation: PdfPageTurnAnimation.none);
    expect(a, isNot(b));
  });

  test('換頁動畫欄位的 toMap／fromMap round-trip 保留欄位值，null 亦正確 round-trip',
      () {
    const withNone =
        BookReaderPrefs(pdfPageTurnAnimation: PdfPageTurnAnimation.none);
    final noneMap = withNone.toMap('book-anim-1');
    expect(noneMap['pdf_page_turn_animation'], 'none');
    expect(BookReaderPrefs.fromMap(noneMap), withNone);

    const withNull = BookReaderPrefs.empty;
    final nullMap = withNull.toMap('book-anim-2');
    expect(nullMap['pdf_page_turn_animation'], isNull);
    expect(BookReaderPrefs.fromMap(nullMap).pdfPageTurnAnimation, isNull);
  });

  test('頁首/頁尾欄位 BookReaderPrefs.empty 為 null（未覆寫，交由 ResolvedPreferences 決定預設值 true）',
      () {
    const prefs = BookReaderPrefs.empty;
    expect(prefs.showHeader, isNull);
    expect(prefs.showFooter, isNull);
  });

  test('頁首/頁尾欄位值完全相同的 BookReaderPrefs 視為相等', () {
    const a = BookReaderPrefs(showHeader: false, showFooter: true);
    const b = BookReaderPrefs(showHeader: false, showFooter: true);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('頁首/頁尾欄位任一不同時視為不相等', () {
    const a = BookReaderPrefs(showHeader: true);
    const b = BookReaderPrefs(showHeader: false);
    expect(a, isNot(b));
  });

  test('showHeader／showFooter 為 true／false／null 皆正確 toMap／fromMap round-trip（避免布林值 0/1 轉換錯誤）',
      () {
    const withTrue = BookReaderPrefs(showHeader: true, showFooter: true);
    final trueMap = withTrue.toMap('book-10');
    expect(trueMap['show_header'], 1);
    expect(trueMap['show_footer'], 1);
    expect(BookReaderPrefs.fromMap(trueMap).showHeader, isTrue);
    expect(BookReaderPrefs.fromMap(trueMap).showFooter, isTrue);

    const withFalse = BookReaderPrefs(showHeader: false, showFooter: false);
    final falseMap = withFalse.toMap('book-11');
    expect(falseMap['show_header'], 0);
    expect(falseMap['show_footer'], 0);
    expect(BookReaderPrefs.fromMap(falseMap).showHeader, isFalse);
    expect(BookReaderPrefs.fromMap(falseMap).showFooter, isFalse);

    const withNull = BookReaderPrefs.empty;
    final nullMap = withNull.toMap('book-12');
    expect(nullMap['show_header'], isNull);
    expect(nullMap['show_footer'], isNull);
    expect(BookReaderPrefs.fromMap(nullMap).showHeader, isNull);
    expect(BookReaderPrefs.fromMap(nullMap).showFooter, isNull);
  });

  test('copyWith 更新 showHeader／showFooter 時，其餘欄位保留原值', () {
    const original =
        BookReaderPrefs(fontSize: 18, showHeader: true, showFooter: true);
    final updated = original.copyWith(showFooter: false);

    expect(updated.fontSize, 18);
    expect(updated.showHeader, isTrue);
    expect(updated.showFooter, isFalse);
  });

  test('columnMode 與 columnSize 預設為 null（未覆寫）', () {
    const prefs = BookReaderPrefs.empty;
    expect(prefs.columnMode, isNull);
    expect(prefs.columnSize, isNull);
  });

  test('columnMode 與 columnSize 相同的 BookReaderPrefs 視為相等', () {
    const a = BookReaderPrefs(columnMode: ColumnMode.single, columnSize: 800);
    const b = BookReaderPrefs(columnMode: ColumnMode.single, columnSize: 800);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('columnMode 與 columnSize 不同時視為不相等', () {
    const a = BookReaderPrefs(columnMode: ColumnMode.single);
    const b = BookReaderPrefs(columnMode: ColumnMode.double);
    expect(a, isNot(b));
  });

  test('toMap 與 fromMap 正確轉換 columnMode 與 columnSize', () {
    const prefs = BookReaderPrefs(columnMode: ColumnMode.double, columnSize: 600);
    final map = prefs.toMap('b1');
    expect(map['column_mode'], 'double');
    expect(map['column_size'], 600.0);

    final restored = BookReaderPrefs.fromMap(map);
    expect(restored.columnMode, ColumnMode.double);
    expect(restored.columnSize, 600.0);
  });

  test('columnMode/columnSize 為 null 時 toMap 正確產生 null 值', () {
    const prefs = BookReaderPrefs.empty;
    final map = prefs.toMap('b2');
    expect(map['column_mode'], isNull);
    expect(map['column_size'], isNull);

    final restored = BookReaderPrefs.fromMap(map);
    expect(restored.columnMode, isNull);
    expect(restored.columnSize, isNull);
  });

  test('copyWith 正確更新 columnMode 與 columnSize', () {
    const original = BookReaderPrefs(fontSize: 18);
    final updated = original.copyWith(columnMode: ColumnMode.single, columnSize: 900);
    expect(updated.fontSize, 18);
    expect(updated.columnMode, ColumnMode.single);
    expect(updated.columnSize, 900.0);
  });

  test('邊距 4 個獨立欄位的 toMap／fromMap round-trip 保留所有欄位', () {
    const prefs = BookReaderPrefs(
      marginTop: 72,
      marginBottom: 20,
      marginLeft: 30,
      marginRight: 30,
    );

    final map = prefs.toMap('book-margin-1');
    expect(map['margin_top'], 72);
    expect(map['margin_bottom'], 20);
    expect(map['margin_left'], 30);
    expect(map['margin_right'], 30);

    final restored = BookReaderPrefs.fromMap(map);
    expect(restored, prefs);
  });

  test('邊距 4 個欄位任一不同時視為不相等', () {
    const a = BookReaderPrefs(marginTop: 64);
    const b = BookReaderPrefs(marginTop: 72);
    expect(a, isNot(b));
  });

  test('全螢幕模式欄位 BookReaderPrefs.empty 為 null（未覆寫，交由 ResolvedPreferences 決定預設值 false）',
      () {
    const prefs = BookReaderPrefs.empty;
    expect(prefs.fullscreen, isNull);
  });

  test('全螢幕模式欄位值完全相同的 BookReaderPrefs 視為相等', () {
    const a = BookReaderPrefs(fullscreen: true);
    const b = BookReaderPrefs(fullscreen: true);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('全螢幕模式欄位值不同時視為不相等', () {
    const a = BookReaderPrefs(fullscreen: true);
    const b = BookReaderPrefs(fullscreen: false);
    expect(a, isNot(b));
  });

  test('fullscreen 為 true／false／null 皆正確 toMap／fromMap round-trip（避免布林值 0/1 轉換錯誤）',
      () {
    const withTrue = BookReaderPrefs(fullscreen: true);
    final trueMap = withTrue.toMap('book-fs-1');
    expect(trueMap['fullscreen'], 1);
    expect(BookReaderPrefs.fromMap(trueMap).fullscreen, isTrue);

    const withFalse = BookReaderPrefs(fullscreen: false);
    final falseMap = withFalse.toMap('book-fs-2');
    expect(falseMap['fullscreen'], 0);
    expect(BookReaderPrefs.fromMap(falseMap).fullscreen, isFalse);

    const withNull = BookReaderPrefs.empty;
    final nullMap = withNull.toMap('book-fs-3');
    expect(nullMap['fullscreen'], isNull);
    expect(BookReaderPrefs.fromMap(nullMap).fullscreen, isNull);
  });

  test('copyWith 更新 fullscreen 時，其餘欄位保留原值', () {
    const original = BookReaderPrefs(fontSize: 18, fullscreen: false);
    final updated = original.copyWith(fullscreen: true);

    expect(updated.fontSize, 18);
    expect(updated.fullscreen, isTrue);
  });

  test('letterSpacing 為具體數值／null 皆正確 toMap／fromMap round-trip', () {
    const withValue = BookReaderPrefs(letterSpacing: 0.15);
    final valueMap = withValue.toMap('book1');
    expect(valueMap['letter_spacing'], 0.15);
    expect(BookReaderPrefs.fromMap(valueMap).letterSpacing, 0.15);

    const withNull = BookReaderPrefs();
    final nullMap = withNull.toMap('book1');
    expect(nullMap['letter_spacing'], isNull);
    expect(BookReaderPrefs.fromMap(nullMap).letterSpacing, isNull);
  });

  test('fromMap 餵入 int 型別的 letter_spacing（模擬 SQLite/JSON 對整數值的型別行為）不拋例外，正確轉為 double',
      () {
    final prefs = BookReaderPrefs.fromMap({'letter_spacing': 0});
    expect(prefs.letterSpacing, 0.0);
    expect(prefs.letterSpacing, isA<double>());
  });

  test('copyWith 更新 letterSpacing 時，其餘欄位保留原值', () {
    const original = BookReaderPrefs(fontSize: 18, letterSpacing: 0.1);
    final updated = original.copyWith(letterSpacing: 0.2);

    expect(updated.fontSize, 18);
    expect(updated.letterSpacing, 0.2);
  });

  test('copyWith 更新 pdfPageTurnAnimation 時，其餘欄位保留原值', () {
    const original = BookReaderPrefs(
      pdfContrast: 10,
      pdfPageTurnAnimation: PdfPageTurnAnimation.slide,
    );
    final updated =
        original.copyWith(pdfPageTurnAnimation: PdfPageTurnAnimation.none);

    expect(updated.pdfContrast, 10);
    expect(updated.pdfPageTurnAnimation, PdfPageTurnAnimation.none);
  });

  group('enumByNameOrNull', () {
    test('找不到對應名稱時回傳 null，不拋出例外', () {
      expect(enumByNameOrNull(EpubTextAlign.values, 'not_a_real_value'), isNull);
    });

    test('name 為 null 時回傳 null', () {
      expect(enumByNameOrNull(EpubTextAlign.values, null), isNull);
    });

    test('找得到時正確回傳對應列舉值', () {
      expect(enumByNameOrNull(EpubTextAlign.values, 'center'), EpubTextAlign.center);
    });
  });

  test('fromMap 對未知的列舉名稱字串安全降級為 null，不拋出例外（epic-28 Issue 3 反序列化容錯，服務 SQLite 與 JSON 兩條路徑）',
      () {
    final map = BookReaderPrefs.empty.toMap('book-1')
      ..['text_align'] = 'not_a_real_enum_value'
      ..['writing_mode_override'] = 'not_a_real_enum_value'
      ..['page_turn_mode_override'] = 'not_a_real_enum_value'
      ..['screen_orientation_override'] = 'not_a_real_enum_value'
      ..['pdf_fit_mode'] = 'not_a_real_enum_value'
      ..['pdf_crop_mode'] = 'not_a_real_enum_value'
      ..['dual_page_mode'] = 'not_a_real_enum_value'
      ..['dual_page_direction'] = 'not_a_real_enum_value'
      ..['column_mode'] = 'not_a_real_enum_value';

    final restored = BookReaderPrefs.fromMap(map);

    expect(restored.textAlign, isNull);
    expect(restored.writingModeOverride, isNull);
    expect(restored.pageTurnModeOverride, isNull);
    expect(restored.screenOrientationOverride, isNull);
    expect(restored.pdfFitMode, isNull);
    expect(restored.pdfCropMode, isNull);
    expect(restored.dualPageMode, isNull);
    expect(restored.dualPageDirection, isNull);
    expect(restored.columnMode, isNull);
  });
}
