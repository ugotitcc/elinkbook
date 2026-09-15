import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';

void main() {
  test('TextConversionMode 有三個值：original／toTraditional／toSimplified',
      () {
    expect(TextConversionMode.values, hasLength(3));
    expect(TextConversionMode.values, contains(TextConversionMode.original));
    expect(
        TextConversionMode.values, contains(TextConversionMode.toTraditional));
    expect(
        TextConversionMode.values, contains(TextConversionMode.toSimplified));
  });

  test('enum 名稱字串穩定（供 SharedPreferences／SQLite 序列化）', () {
    expect(TextConversionMode.original.name, 'original');
    expect(TextConversionMode.toTraditional.name, 'toTraditional');
    expect(TextConversionMode.toSimplified.name, 'toSimplified');
  });
}
