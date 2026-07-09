import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

void main() {
  group('resolveThemeData', () {
    test('isEinkMode 為 false 時，light/dark/sepia 回傳不同的 ThemeData', () {
      final light = resolveThemeData(theme: AppTheme.light, isEinkMode: false);
      final dark = resolveThemeData(theme: AppTheme.dark, isEinkMode: false);
      final sepia = resolveThemeData(theme: AppTheme.sepia, isEinkMode: false);

      // 三組主題的 scaffoldBackgroundColor 皆不同
      expect(light.scaffoldBackgroundColor, isNot(dark.scaffoldBackgroundColor));
      expect(light.scaffoldBackgroundColor, isNot(sepia.scaffoldBackgroundColor));
      expect(dark.scaffoldBackgroundColor, isNot(sepia.scaffoldBackgroundColor));
    });

    test('isEinkMode 為 true 時，不論 theme 為何皆回傳相同的高對比 ThemeData', () {
      final einkLight =
          resolveThemeData(theme: AppTheme.light, isEinkMode: true);
      final einkDark =
          resolveThemeData(theme: AppTheme.dark, isEinkMode: true);
      final einkSepia =
          resolveThemeData(theme: AppTheme.sepia, isEinkMode: true);

      expect(einkLight.scaffoldBackgroundColor,
          einkDark.scaffoldBackgroundColor);
      expect(einkLight.scaffoldBackgroundColor,
          einkSepia.scaffoldBackgroundColor);
    });

    test('E-Ink 高對比 ThemeData 使用純白背景與純黑文字', () {
      final eink = resolveThemeData(theme: AppTheme.light, isEinkMode: true);
      expect(eink.scaffoldBackgroundColor, Colors.white);
      expect(eink.colorScheme.onSurface, Colors.black);
    });
  });

  group('buildThemeData', () {
    test('light 主題使用淺色背景', () {
      final theme = buildThemeData(AppTheme.light);
      expect(theme.brightness, Brightness.light);
    });

    test('dark 主題使用深色背景', () {
      final theme = buildThemeData(AppTheme.dark);
      expect(theme.brightness, Brightness.dark);
    });

    test('sepia 主題使用淺色背景（羊皮紙色）', () {
      final theme = buildThemeData(AppTheme.sepia);
      expect(theme.brightness, Brightness.light);
      // 羊皮紙色通常不是純白
      expect(theme.scaffoldBackgroundColor, isNot(Colors.white));
    });
  });
}
