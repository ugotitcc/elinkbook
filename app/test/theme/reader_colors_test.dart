import 'dart:ui';
import 'package:elinkbook/theme/reader_colors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseHexColor', () {
    test('標準大寫 6 位十六進制色碼解析成功', () {
      expect(parseHexColor('#FFFFFF'), equals(const Color(0xFFFFFFFF)));
      expect(parseHexColor('#000000'), equals(const Color(0xFF000000)));
      expect(parseHexColor('#123456'), equals(const Color(0xFF123456)));
    });

    test('小寫 6 位十六進制色碼可正常解析', () {
      expect(parseHexColor('#ff8800'), equals(const Color(0xFFFF8800)));
      expect(parseHexColor('#abcdef'), equals(const Color(0xFFABCDEF)));
    });

    test('無效色碼格式一律回傳 null', () {
      expect(parseHexColor('FFFFFF'), isNull, reason: '缺少 # 前綴');
      expect(parseHexColor('#FFF'), isNull, reason: '3 位簡寫不支援');
      expect(parseHexColor('#GGGGGG'), isNull, reason: '非合法十六進制字元');
      expect(parseHexColor(''), isNull, reason: '空字串');
      expect(parseHexColor('#FFFFFFF'), isNull, reason: '7 位長度不符');
      expect(parseHexColor('#12345'), isNull, reason: '5 位長度不符');
      expect(parseHexColor(' #FFFFFF'), isNull, reason: '帶有空白');
      expect(parseHexColor('#FFFFFF '), isNull, reason: '尾端空白');
    });
  });

  group('formatHexColor', () {
    test('格式化為大寫 #RRGGBB 格式且補前導零', () {
      expect(formatHexColor(const Color(0xFF0A0B0C)), equals('#0A0B0C'));
      expect(formatHexColor(const Color(0xFFFFFFFF)), equals('#FFFFFF'));
      expect(formatHexColor(const Color(0xFF000000)), equals('#000000'));
      expect(formatHexColor(const Color(0xFF00FF00)), equals('#00FF00'));
    });
  });

  group('contrastRatio', () {
    test('白底黑字對比度約為 21:1', () {
      final ratio = contrastRatio(const Color(0xFFFFFFFF), const Color(0xFF000000));
      expect(ratio, closeTo(21.0, 0.1));
    });

    test('相同顏色對比度為 1:1', () {
      final ratio = contrastRatio(const Color(0xFFFFFFFF), const Color(0xFFFFFFFF));
      expect(ratio, closeTo(1.0, 0.001));
    });

    test('參數順序對調結果相同（交換律）', () {
      const c1 = Color(0xFF336699);
      const c2 = Color(0xFFEEDDCC);
      expect(contrastRatio(c1, c2), equals(contrastRatio(c2, c1)));
    });
  });

  group('ReaderColors', () {
    test('empty 預設 background 與 text 為 null', () {
      expect(ReaderColors.empty.background, isNull);
      expect(ReaderColors.empty.text, isNull);
    });

    test('withBackground 與 withText 支援賦值與傳 null 清除', () {
      const initial = ReaderColors(
        background: Color(0xFFFFFFFF),
        text: Color(0xFF000000),
      );

      final clearedBg = initial.withBackground(null);
      expect(clearedBg.background, isNull);
      expect(clearedBg.text, equals(const Color(0xFF000000)));

      final clearedText = initial.withText(null);
      expect(clearedText.background, equals(const Color(0xFFFFFFFF)));
      expect(clearedText.text, isNull);

      final updatedBg = initial.withBackground(const Color(0xFFF0F6FC));
      expect(updatedBg.background, equals(const Color(0xFFF0F6FC)));
      expect(updatedBg.text, equals(const Color(0xFF000000)));
    });

    test('相等性 == 與 hashCode 依欄位值比較', () {
      const a = ReaderColors(
        background: Color(0xFFFFFFFF),
        text: Color(0xFF000000),
      );
      const b = ReaderColors(
        background: Color(0xFFFFFFFF),
        text: Color(0xFF000000),
      );
      const c = ReaderColors(
        background: Color(0xFFFFFFFF),
        text: null,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
