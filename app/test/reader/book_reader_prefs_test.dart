import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
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
}
