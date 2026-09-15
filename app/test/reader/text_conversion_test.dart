import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/text_conversion.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';

void main() {
  group('convertText', () {
    test('original 模式原樣回傳', () {
      expect(convertText('国电脑', TextConversionMode.original), '国电脑');
    });

    test('toTraditional 轉換已知簡體字元', () {
      expect(convertText('国', TextConversionMode.toTraditional), '國');
      expect(convertText('电脑', TextConversionMode.toTraditional), '電腦');
    });

    test('toSimplified 轉換已知繁體字元', () {
      expect(convertText('國', TextConversionMode.toSimplified), '国');
      expect(convertText('電腦', TextConversionMode.toSimplified), '电脑');
    });

    test('多對一併字取首個候選字（真實 OpenCC 資料：「后」「干」案例）', () {
      // STCharacters.txt：后 -> 後 后（取「後」）；干 -> 幹 乾 干 榦（取「幹」）。
      expect(convertText('后', TextConversionMode.toTraditional), '後');
      expect(convertText('干', TextConversionMode.toTraditional), '幹');
    });

    test('查找表找不到的字元維持原樣', () {
      expect(
        convertText('ABC123', TextConversionMode.toTraditional),
        'ABC123',
      );
    });

    test('轉換不改變 UTF-16 長度與 code point 數量（ΔL=0，ADR 0030 核心不變量，審查修正 C-1）', () {
      const input = '国电脑后干发里';
      final converted =
          convertText(input, TextConversionMode.toTraditional);
      expect(converted.length, input.length,
          reason: 'UTF-16 code unit 長度不可改變（epubcfi.js Range offset 計算基準）');
      expect(converted.runes.length, input.runes.length,
          reason: 'Unicode code point 數量不可改變');
    });

    test('空字串原樣回傳（審查修正 I-1）', () {
      expect(convertText('', TextConversionMode.toTraditional), '');
      expect(convertText('', TextConversionMode.original), '');
    });

    test('英數/標點/中文混排字串只轉換中文部分（審查修正 I-1）', () {
      expect(
        convertText('Hello 电脑, 世界！123', TextConversionMode.toTraditional),
        'Hello 電腦, 世界！123',
      );
    });

    test('含代理對字元（輔助平面／emoji）的字串不拋例外、原樣保留（審查修正 I-1）', () {
      // '😀'（U+1F600）與 '𠗣'（U+205E3）皆需代理對編碼，兩者都不在查找表
      // 中（查找表已在生成階段排除 BMP↔輔助平面配對，見 Task 3），
      // convertText 走訪 runes 時須正確處理、不拋例外、原樣保留。
      const input = '国😀𠗣电';
      final converted = convertText(input, TextConversionMode.toTraditional);
      expect(converted, '國😀𠗣電');
      expect(converted.length, input.length);
    });
  });
}
