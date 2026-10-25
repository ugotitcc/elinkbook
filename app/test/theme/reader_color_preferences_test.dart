import 'dart:ui';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/reader_color_preferences.dart';
import 'package:elinkbook/theme/reader_colors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReaderColorPreferences', () {
    late ReaderColorPreferences preferences;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      preferences = const ReaderColorPreferences();
    });

    test('未曾存過任何值時，load 回傳 ReaderColors.empty', () async {
      final colors = await preferences.load(AppTheme.light);
      expect(colors, equals(ReaderColors.empty));
      expect(colors.background, isNull);
      expect(colors.text, isNull);
    });

    test('儲存自訂背景與文字色後可正確讀回相同值', () async {
      const saved = ReaderColors(
        background: Color(0xFF112233),
        text: Color(0xFFAABBCC),
      );
      await preferences.save(AppTheme.light, saved);

      final loaded = await preferences.load(AppTheme.light);
      expect(loaded, equals(saved));
    });

    test('只儲存背景色時，文字色維持 null，反之亦然', () async {
      const bgOnly = ReaderColors(background: Color(0xFFFFFFFF), text: null);
      await preferences.save(AppTheme.light, bgOnly);

      final loadedBg = await preferences.load(AppTheme.light);
      expect(loadedBg.background, equals(const Color(0xFFFFFFFF)));
      expect(loadedBg.text, isNull);

      const textOnly = ReaderColors(background: null, text: Color(0xFF000000));
      await preferences.save(AppTheme.dark, textOnly);

      final loadedText = await preferences.load(AppTheme.dark);
      expect(loadedText.background, isNull);
      expect(loadedText.text, equals(const Color(0xFF000000)));
    });

    test('三種佈景（淺色、深色、羊皮紙）設定彼此獨立互不干擾', () async {
      await preferences.save(
        AppTheme.light,
        const ReaderColors(background: Color(0xFFFFFFFF), text: Color(0xFF111111)),
      );
      await preferences.save(
        AppTheme.dark,
        const ReaderColors(background: Color(0xFF000000), text: Color(0xFFEEEEEE)),
      );
      await preferences.save(
        AppTheme.sepia,
        const ReaderColors(background: Color(0xFFFBF0D9), text: Color(0xFF5F4B32)),
      );

      final light = await preferences.load(AppTheme.light);
      final dark = await preferences.load(AppTheme.dark);
      final sepia = await preferences.load(AppTheme.sepia);

      expect(light.background, equals(const Color(0xFFFFFFFF)));
      expect(dark.background, equals(const Color(0xFF000000)));
      expect(sepia.background, equals(const Color(0xFFFBF0D9)));
    });

    test('設為 null 或 ReaderColors.empty 時對應 key 會被確實 remove', () async {
      await preferences.save(
        AppTheme.light,
        const ReaderColors(background: Color(0xFFFFFFFF), text: Color(0xFF000000)),
      );
      final sp = await SharedPreferences.getInstance();
      expect(sp.containsKey('reader_color_light_background'), isTrue);
      expect(sp.containsKey('reader_color_light_text'), isTrue);

      // 清除背景色，保留文字色
      await preferences.save(
        AppTheme.light,
        const ReaderColors(background: null, text: Color(0xFF000000)),
      );
      expect(sp.containsKey('reader_color_light_background'), isFalse);
      expect(sp.containsKey('reader_color_light_text'), isTrue);

      // 儲存 empty，兩者皆 remove
      await preferences.save(AppTheme.light, ReaderColors.empty);
      expect(sp.containsKey('reader_color_light_background'), isFalse);
      expect(sp.containsKey('reader_color_light_text'), isFalse);
    });

    test('預先塞入無效色碼格式時安全回退為 null、不崩潰', () async {
      SharedPreferences.setMockInitialValues({
        'reader_color_light_background': 'invalid-hex',
        'reader_color_light_text': '#123', // 非 6 位
      });

      final colors = await preferences.load(AppTheme.light);
      expect(colors.background, isNull);
      expect(colors.text, isNull);
    });
  });
}
