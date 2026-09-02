import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:elinkbook/theme/elink_tokens.dart';

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

    test('light 主題 ColorScheme 全角色對齊 DESIGN.md §1.1（不留 M3 baseline）',
        () {
      final theme = buildThemeData(AppTheme.light);
      final scheme = theme.colorScheme;

      expect(scheme.primary, const Color(0xFF0284C7));
      expect(scheme.onPrimary, const Color(0xFFFFFFFF));
      expect(scheme.primaryContainer, const Color(0xFFE0F2FE));
      expect(scheme.onPrimaryContainer, const Color(0xFF0284C7));
      expect(scheme.surface, const Color(0xFFFFFFFF));
      expect(scheme.onSurface, const Color(0xFF0F172A));
      expect(scheme.onSurfaceVariant, const Color(0xFF334155));
      expect(scheme.outline, const Color(0xFFCBDFE9));
      expect(scheme.surfaceContainerHighest, const Color(0xFFE6F1FA));
      expect(scheme.error, const Color(0xFFEF4444));
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF0F6FC));
    });

    test(
        '移除 cardColor／dividerColor 顯式設定後，ThemeData 這兩個 M2 遺留'
        '欄位本身的 M3 預設解析值仍符合預期（cardColor 退回'
        ' colorScheme.surface，dividerColor 退回 colorScheme.outline，皆與'
        '移除前手動設定的值相同）——**注意**：這兩個欄位只是 ThemeData 上的'
        '獨立屬性，不代表 Card()／Divider() widget 實際渲染會讀取它們（M3'
        '下兩個 widget 各自直接吃 colorScheme 的其他角色，見下一則'
        ' testWidgets），這裡只保護「還有其他呼叫端直接讀'
        ' Theme.of(context).dividerColor」這種用法（例如'
        ' nav_zone_settings_screen.dart，屬 Issue 5 範圍）不會被本工單影響。',
        () {
      final theme = buildThemeData(AppTheme.light);
      expect(theme.cardColor, theme.colorScheme.surface);
      expect(theme.dividerColor, theme.colorScheme.outline);
    });

    testWidgets(
        '移除 cardColor／dividerColor 顯式設定後，Card()／Divider() widget'
        '實際渲染出的顏色符合 M3 預設角色（Card 走'
        ' colorScheme.surfaceContainerLow，Divider 走'
        ' colorScheme.outlineVariant——這兩個角色從頭到尾都不吃'
        ' cardColor／dividerColor，跟本工單是否移除這兩個欄位無關；這則'
        '測試單純鎖定／記錄這個容易被誤解的 M3 實際渲染事實，不是本 Task'
        ' diff 要驗證失敗轉通過的對象，見 Step 2 說明。'
        ' surfaceContainerLow／outlineVariant 本身不在 DESIGN.md §1.1 本次'
        '要對齊的角色清單內，若之後要讓 Card／Divider 視覺對齊設計系統色'
        '票，需另開工單評估，不在本 Issue 2 範圍）', (tester) async {
      final theme = buildThemeData(AppTheme.light);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Column(
              children: [
                Card(child: SizedBox(width: 10, height: 10)),
                Divider(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cardMaterial = tester.widget<Material>(
        find.descendant(
          of: find.byType(Card),
          matching: find.byType(Material),
        ),
      );
      expect(cardMaterial.color, theme.colorScheme.surfaceContainerLow);

      final dividerContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(Divider),
          matching: find.byType(Container),
        ),
      );
      final dividerDecoration = dividerContainer.decoration! as BoxDecoration;
      expect(
        dividerDecoration.border!.bottom.color,
        theme.colorScheme.outlineVariant,
      );
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

  group('resolveThemeData 組裝的 ElinkTokens', () {
    test('light 主題（isEinkMode: false）組裝出正確的 ElinkTokens 值', () {
      final theme = resolveThemeData(theme: AppTheme.light, isEinkMode: false);
      final tokens = theme.extension<ElinkTokens>();

      expect(tokens, isNotNull);
      expect(tokens!.highlightYellow, const Color(0xFFFEF08A));
      expect(tokens.highlightGreen, const Color(0xFFBBF7D0));
      expect(tokens.highlightBlue, const Color(0xFFBFDBFE));
      expect(tokens.underlineColor, const Color(0xFF0284C7));
      expect(tokens.progressTrack, const Color(0xFFCBDFE9));
      expect(tokens.coverPlaceholder, const Color(0xFFE6F1FA));
      expect(tokens.badgeScrim, const Color(0xFF94A3B8));
      expect(tokens.ttsActiveHighlight, const Color(0xFFE0F2FE));
      expect(tokens.isEink, false);
      expect(tokens.reducedMotion, false);
      expect(tokens.discretePaging, false);
    });
  });
}
