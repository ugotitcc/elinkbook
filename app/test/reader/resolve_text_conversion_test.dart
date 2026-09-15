import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/reading_defaults.dart';
import 'package:elinkbook/reader/resolve_text_conversion.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';

void main() {
  group('resolveTextConversion', () {
    test('book.textConversionOverride 非 null 時優先於 global.textConversion', () {
      const book =
          BookReaderPrefs(textConversionOverride: TextConversionMode.toSimplified);
      const global = ReadingDefaults(textConversion: TextConversionMode.toTraditional);
      expect(resolveTextConversion(book, global), TextConversionMode.toSimplified);
    });

    test('book.textConversionOverride 為 null 時回退 global.textConversion', () {
      const book = BookReaderPrefs.empty;
      const global = ReadingDefaults(textConversion: TextConversionMode.toTraditional);
      expect(resolveTextConversion(book, global), TextConversionMode.toTraditional);
    });

    test('兩者皆未設定時回傳 original（硬編碼預設值一致）', () {
      const book = BookReaderPrefs.empty;
      const global = ReadingDefaults.initial();
      expect(resolveTextConversion(book, global), TextConversionMode.original);
    });
  });
}
