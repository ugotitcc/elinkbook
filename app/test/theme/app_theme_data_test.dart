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
        '區分，對比嚴重不足；後續真機電子紙硬體實測發現一般顯示器上「足夠」'
        '的對比在電子紙上仍不可辨識，outline 值進一步調亮為 #86868F，感知亮度差'
        '約 0.41，留更多安全邊際）', () {
      final theme = buildThemeData(AppTheme.dark);
      final outline = theme.colorScheme.outline;
      final surface = theme.colorScheme.surface;

      double perceivedLuminance(Color c) =>
          0.299 * c.r + 0.587 * c.g + 0.114 * c.b;

      final luminanceDiff =
          (perceivedLuminance(outline) - perceivedLuminance(surface)).abs();

      // 舊色值（#2A2A30 對 #1E1E22）的亮度差約 0.048，明顯不足；新色值
      // 須顯著超過這個數字，門檻取 0.15（新色值 #86868F 實測約 0.41，留有
      // 餘裕）。
      expect(luminanceDiff, greaterThan(0.15));
    });

    test(
        'dark 主題的 dividerColor 與 outline 保持同一色值（本檔案既有設計：'
        '單一色票同時代表 outline 與分隔線語意）', () {
      final theme = buildThemeData(AppTheme.dark);
      expect(theme.dividerColor, theme.colorScheme.outline);
    });

    test(
        'dark 主題的 surfaceContainerHighest 色與 surface 色有足夠感知亮度'
        '差，Switch 等元件關閉狀態的軌道底色在深色背景下清楚可辨識'
        '（epic-22-reader-theme-integration Issue 4 真機電子紙硬體對比'
        '追加修正：原本未客製 surfaceContainerHighest，隱性等於 surface，'
        '導致關閉狀態軌道與背景完全同色，僅靠一條細外框線撐可視度，這種'
        '手法在電子紙抖動渲染下結構性地不可靠，真機拍照確認關閉狀態'
        '完全消失）', () {
      final theme = buildThemeData(AppTheme.dark);
      final trackFill = theme.colorScheme.surfaceContainerHighest;
      final surface = theme.colorScheme.surface;

      double perceivedLuminance(Color c) =>
          0.299 * c.r + 0.587 * c.g + 0.114 * c.b;

      final luminanceDiff =
          (perceivedLuminance(trackFill) - perceivedLuminance(surface)).abs();

      // 未客製時 surfaceContainerHighest 隱性等於 surface，亮度差為 0，
      // 完全不可辨識；新色值 #3C3C44 對 surface #1E1E22 實測約 0.119，
      // 門檻取 0.10，讓關閉狀態的 Switch 本身就是一塊與背景明顯不同的
      // 實心色塊，不必再完全依賴細外框線才能被看見。
      expect(luminanceDiff, greaterThan(0.10));
    });
  });
}
