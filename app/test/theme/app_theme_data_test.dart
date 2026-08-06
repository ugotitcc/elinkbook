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

    test(
        'dark 主題的 outline 色與 surface 色有足夠感知亮度差，Switch 等元件'
        '關閉狀態外框在深色背景下清楚可辨識（epic-22-reader-theme-'
        'integration Issue 4：原色值 #2A2A30 與 surface #1E1E22 幾乎無法'
        '區分，對比嚴重不足）', () {
      final theme = buildThemeData(AppTheme.dark);
      final outline = theme.colorScheme.outline;
      final surface = theme.colorScheme.surface;

      double perceivedLuminance(Color c) =>
          0.299 * c.r + 0.587 * c.g + 0.114 * c.b;

      final luminanceDiff =
          (perceivedLuminance(outline) - perceivedLuminance(surface)).abs();

      // 舊色值（#2A2A30 對 #1E1E22）的亮度差約 0.048，明顯不足；新色值
      // 須顯著超過這個數字，門檻取 0.15（新色值實測約 0.246，留有餘裕）。
      expect(luminanceDiff, greaterThan(0.15));
    });

    test(
        'dark 主題的 dividerColor 與 outline 保持同一色值（本檔案既有設計：'
        '單一色票同時代表 outline 與分隔線語意）', () {
      final theme = buildThemeData(AppTheme.dark);
      expect(theme.dividerColor, theme.colorScheme.outline);
    });
  });
}
