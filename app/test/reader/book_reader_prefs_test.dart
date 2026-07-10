import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
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
  });

  test('兩個欄位值完全相同的 BookReaderPrefs 視為相等', () {
    const a = BookReaderPrefs(
      fontFamily: AppFont.sourceHanSans,
      fontSize: 18,
      writingModeOverride: WritingMode.vertical,
    );
    const b = BookReaderPrefs(
      fontFamily: AppFont.sourceHanSans,
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
      fontFamily: AppFont.taiwanPearl,
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
    expect(map['font_family'], 'taiwanPearl');
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
}
