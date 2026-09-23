import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:elinkbook/theme/elink_tokens.dart';

/// 比較兩個顏色的 RGB 分量是否相同，忽略 alpha（用於驗證某個顏色是否
/// 「來源於」另一個顏色，即使中間套用了不同透明度）。
bool _sameRgb(Color a, Color b) => a.r == b.r && a.g == b.g && a.b == b.b;

void main() {
  group('resolveThemeData', () {
    test('isEinkMode 為 false 時，light/dark/sepia 回傳不同的 ThemeData', () {
      final light = resolveThemeData(theme: AppTheme.light, isEinkMode: false);
      final dark = resolveThemeData(theme: AppTheme.dark, isEinkMode: false);
      final sepia = resolveThemeData(theme: AppTheme.sepia, isEinkMode: false);

      // 三組主題的 scaffoldBackgroundColor 皆不同
      expect(
        light.scaffoldBackgroundColor,
        isNot(dark.scaffoldBackgroundColor),
      );
      expect(
        light.scaffoldBackgroundColor,
        isNot(sepia.scaffoldBackgroundColor),
      );
      expect(
        dark.scaffoldBackgroundColor,
        isNot(sepia.scaffoldBackgroundColor),
      );
    });

    test('isEinkMode 為 true 時，不論 theme 為何皆回傳相同的高對比 ThemeData', () {
      final einkLight = resolveThemeData(
        theme: AppTheme.light,
        isEinkMode: true,
      );
      final einkDark = resolveThemeData(theme: AppTheme.dark, isEinkMode: true);
      final einkSepia = resolveThemeData(
        theme: AppTheme.sepia,
        isEinkMode: true,
      );

      expect(
        einkLight.scaffoldBackgroundColor,
        einkDark.scaffoldBackgroundColor,
      );
      expect(
        einkLight.scaffoldBackgroundColor,
        einkSepia.scaffoldBackgroundColor,
      );
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

    test('light 主題 ColorScheme 全角色對齊 DESIGN.md §1.1（不留 M3 baseline）', () {
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

    test('移除 cardColor／dividerColor 顯式設定後，ThemeData 這兩個 M2 遺留'
        '欄位本身的 M3 預設解析值仍符合預期（cardColor 退回'
        ' colorScheme.surface，dividerColor 退回 colorScheme.outline，皆與'
        '移除前手動設定的值相同）——**注意**：這兩個欄位只是 ThemeData 上的'
        '獨立屬性，不代表 Card()／Divider() widget 實際渲染會讀取它們（M3'
        '下兩個 widget 各自直接吃 colorScheme 的其他角色，見下一則'
        ' testWidgets），這裡只保護「還有其他呼叫端直接讀'
        ' Theme.of(context).dividerColor」這種用法（例如'
        ' nav_zone_settings_screen.dart，屬 Issue 5 範圍）不會被本工單影響。', () {
      final theme = buildThemeData(AppTheme.light);
      expect(theme.cardColor, theme.colorScheme.surface);
      expect(theme.dividerColor, theme.colorScheme.outline);
    });

    testWidgets('移除 cardColor／dividerColor 顯式設定後，Card()／Divider() widget'
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
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
        find.descendant(of: find.byType(Card), matching: find.byType(Material)),
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

    test('dark 主題 ColorScheme 全角色對齊 DESIGN.md §1.1（不留 M3 baseline，'
        'outline／surfaceContainerHighest 採用 DESIGN.md 值，不維持真機實測'
        '調校值——可辨識度風險改由 SwitchThemeData 承接，見 Issue 2 Task 5）', () {
      final theme = buildThemeData(AppTheme.dark);
      final scheme = theme.colorScheme;

      expect(scheme.primary, const Color(0xFF38BDF8));
      expect(scheme.onPrimary, const Color(0xFF141416));
      expect(scheme.primaryContainer, const Color(0xFF182836));
      expect(scheme.onPrimaryContainer, const Color(0xFF38BDF8));
      expect(scheme.surface, const Color(0xFF1D1D22));
      expect(scheme.onSurface, const Color(0xFFF2EFE6));
      expect(scheme.onSurfaceVariant, const Color(0xFFB5B2A8));
      expect(scheme.outline, const Color(0xFF2C2C34));
      expect(scheme.surfaceContainerHighest, const Color(0xFF19191D));
      expect(scheme.error, const Color(0xFFF87171));
      expect(theme.scaffoldBackgroundColor, const Color(0xFF141416));
    });

    test('dark 主題的 dividerColor 與 outline 保持同一色值（本檔案既有設計：'
        '單一色票同時代表 outline 與分隔線語意）', () {
      final theme = buildThemeData(AppTheme.dark);
      expect(theme.dividerColor, theme.colorScheme.outline);
    });

    test('sepia 主題 ColorScheme 全角色對齊 DESIGN.md §1.1（不留 M3 baseline）', () {
      final theme = buildThemeData(AppTheme.sepia);
      final scheme = theme.colorScheme;

      expect(scheme.primary, const Color(0xFFB8362D));
      expect(scheme.onPrimary, const Color(0xFFFFFFFF));
      expect(scheme.primaryContainer, const Color(0xFFFAECEA));
      expect(scheme.onPrimaryContainer, const Color(0xFFB8362D));
      expect(scheme.surface, const Color(0xFFFAF3E3));
      expect(scheme.onSurface, const Color(0xFF1F2022));
      expect(scheme.onSurfaceVariant, const Color(0xFF535457));
      expect(scheme.outline, const Color(0xFFE6DFCB));
      expect(scheme.surfaceContainerHighest, const Color(0xFFF0EBD9));
      expect(scheme.error, const Color(0xFFDC2626));
      expect(theme.scaffoldBackgroundColor, const Color(0xFFFCFAF2));
    });

    test('eink 主題 ColorScheme 全角色對齊 DESIGN.md §1.1（純黑白，不留'
        ' secondary／onSecondary，且 inverseSurface／onInverseSurface 亦不留'
        ' M3 baseline 預設值；後兩者為 epic-39-layout-settings-redesign Issue 4'
        ' 新增斷言——Issue 4 是全專案第一個實際讀取這兩個角色的功能，此前未被'
        ' 任何測試涵蓋）', () {
      final theme = buildEinkThemeData();
      final scheme = theme.colorScheme;

      expect(scheme.primary, const Color(0xFF000000));
      expect(scheme.onPrimary, const Color(0xFFFFFFFF));
      expect(scheme.primaryContainer, const Color(0xFFFFFFFF));
      expect(scheme.onPrimaryContainer, const Color(0xFF000000));
      expect(scheme.surface, const Color(0xFFFFFFFF));
      expect(scheme.onSurface, const Color(0xFF000000));
      expect(scheme.onSurfaceVariant, const Color(0xFF000000));
      expect(scheme.outline, const Color(0xFF000000));
      expect(scheme.surfaceContainerHighest, const Color(0xFFFFFFFF));
      expect(scheme.error, const Color(0xFF000000));
      expect(scheme.inverseSurface, const Color(0xFF000000));
      expect(scheme.onInverseSurface, const Color(0xFFFFFFFF));
      expect(theme.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
    });

    test('四套主題的 switchTheme 三插槽於 OFF 狀態皆解析自 colorScheme.onSurface'
        '（電子紙可辨識度補強，取代不再可靠的 outline／surfaceContainerHighest'
        ' 對比手法，見 spec.md「電子紙可辨識度補強機制」）', () {
      for (final theme in AppTheme.values) {
        final themeData = buildThemeData(theme);
        final onSurface = themeData.colorScheme.onSurface;
        final switchTheme = themeData.switchTheme;

        final thumb = switchTheme.thumbColor?.resolve(<WidgetState>{});
        final track = switchTheme.trackColor?.resolve(<WidgetState>{});
        final trackOutline = switchTheme.trackOutlineColor?.resolve(
          <WidgetState>{},
        );

        expect(thumb, isNotNull, reason: '$theme thumbColor 未設定');
        expect(track, isNotNull, reason: '$theme trackColor 未設定');
        expect(trackOutline, isNotNull, reason: '$theme trackOutlineColor 未設定');
        expect(
          _sameRgb(thumb!, onSurface),
          true,
          reason: '$theme thumbColor (OFF) 應來源於 onSurface',
        );
        expect(
          _sameRgb(track!, onSurface),
          true,
          reason: '$theme trackColor (OFF) 應來源於 onSurface',
        );
        expect(
          _sameRgb(trackOutline!, onSurface),
          true,
          reason: '$theme trackOutlineColor (OFF) 應來源於 onSurface',
        );
      }
    });

    test('四套主題的 switchTheme 三插槽於 ON 狀態皆解析自 colorScheme.primary／onPrimary'
        '（視覺還原，對齊 Reference 截圖「開＝主色填滿」，見'
        ' docs/research/uiux/VISUAL_ANALYSIS.md），且與 OFF 狀態可互相區分', () {
      for (final theme in AppTheme.values) {
        final themeData = buildThemeData(theme);
        final colorScheme = themeData.colorScheme;
        final switchTheme = themeData.switchTheme;

        final track = switchTheme.trackColor?.resolve(<WidgetState>{});
        const onState = <WidgetState>{WidgetState.selected};
        final thumbOn = switchTheme.thumbColor?.resolve(onState);
        final trackOn = switchTheme.trackColor?.resolve(onState);
        final trackOutlineOn = switchTheme.trackOutlineColor?.resolve(onState);

        expect(thumbOn, isNotNull, reason: '$theme thumbColor (selected) 未設定');
        expect(trackOn, isNotNull, reason: '$theme trackColor (selected) 未設定');
        expect(
          trackOutlineOn,
          isNotNull,
          reason: '$theme trackOutlineColor (selected) 未設定',
        );
        expect(
          _sameRgb(thumbOn!, colorScheme.onPrimary),
          true,
          reason: '$theme thumbColor (selected) 應來源於 onPrimary',
        );
        expect(
          _sameRgb(trackOn!, colorScheme.primary),
          true,
          reason: '$theme trackColor (selected) 應來源於 primary',
        );
        expect(
          _sameRgb(trackOutlineOn!, colorScheme.primary),
          true,
          reason: '$theme trackOutlineColor (selected) 應來源於 primary',
        );
        // ON/OFF 兩態的 track 必須可互相區分——OFF 為低透明度、ON 為滿不
        // 透明，即使 primary 與 onSurface 剛好同色（例如 E-Ink 皆為純黑）
        // 也仍可靠由透明度區分，不依賴 RGB 是否不同。
        expect(
          trackOn.a,
          isNot(track!.a),
          reason: '$theme trackColor 的 ON/OFF 狀態應可互相區分',
        );
      }
    });

    test('E-Ink 主題的 switchTheme 三插槽於 OFF 狀態皆解析自 colorScheme.onSurface', () {
      final themeData = buildEinkThemeData();
      final onSurface = themeData.colorScheme.onSurface;
      final switchTheme = themeData.switchTheme;

      final thumb = switchTheme.thumbColor?.resolve(<WidgetState>{});
      final track = switchTheme.trackColor?.resolve(<WidgetState>{});
      final trackOutline = switchTheme.trackOutlineColor?.resolve(
        <WidgetState>{},
      );

      expect(thumb, isNotNull);
      expect(track, isNotNull);
      expect(trackOutline, isNotNull);
      expect(_sameRgb(thumb!, onSurface), true);
      expect(_sameRgb(track!, onSurface), true);
      expect(_sameRgb(trackOutline!, onSurface), true);
    });

    test('E-Ink 主題的 switchTheme ON 狀態呈現「黑底白點」（primary＝純黑、'
        'onPrimary＝純白，見 _buildEinkTheme()），對比度高於原本方案，'
        '不削弱電子紙可辨識度', () {
      final themeData = buildEinkThemeData();
      final colorScheme = themeData.colorScheme;
      final switchTheme = themeData.switchTheme;

      final track = switchTheme.trackColor?.resolve(<WidgetState>{});
      const onState = <WidgetState>{WidgetState.selected};
      final thumbOn = switchTheme.thumbColor?.resolve(onState);
      final trackOn = switchTheme.trackColor?.resolve(onState);
      final trackOutlineOn = switchTheme.trackOutlineColor?.resolve(onState);

      expect(thumbOn, isNotNull);
      expect(trackOn, isNotNull);
      expect(trackOutlineOn, isNotNull);
      expect(_sameRgb(thumbOn!, colorScheme.onPrimary), true);
      expect(_sameRgb(trackOn!, colorScheme.primary), true);
      expect(_sameRgb(trackOutlineOn!, colorScheme.primary), true);
      expect(colorScheme.primary, const Color(0xFF000000));
      expect(colorScheme.onPrimary, const Color(0xFFFFFFFF));
      // ON/OFF 兩態的 track 必須可互相區分——primary 與 onSurface 在 E-Ink
      // 皆為純黑，RGB 相同，靠透明度（OFF 低透明度／ON 滿不透明）區分。
      expect(trackOn.a, isNot(track!.a));
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

    test('dark 主題（isEinkMode: false）組裝出正確的 ElinkTokens 值', () {
      final theme = resolveThemeData(theme: AppTheme.dark, isEinkMode: false);
      final tokens = theme.extension<ElinkTokens>();

      expect(tokens, isNotNull);
      expect(tokens!.highlightYellow, const Color(0xFF854D0E));
      expect(tokens.highlightGreen, const Color(0xFF166534));
      expect(tokens.highlightBlue, const Color(0xFF1E40AF));
      expect(tokens.underlineColor, const Color(0xFF38BDF8));
      expect(tokens.progressTrack, const Color(0xFF2C2C34));
      expect(tokens.coverPlaceholder, const Color(0xFF1D1D22));
      expect(tokens.badgeScrim, const Color(0xFF7A7872));
      expect(tokens.ttsActiveHighlight, const Color(0xFF182836));
      expect(tokens.isEink, false);
      expect(tokens.reducedMotion, false);
      expect(tokens.discretePaging, false);
    });

    test('sepia 主題（isEinkMode: false）組裝出正確的 ElinkTokens 值', () {
      final theme = resolveThemeData(theme: AppTheme.sepia, isEinkMode: false);
      final tokens = theme.extension<ElinkTokens>();

      expect(tokens, isNotNull);
      expect(tokens!.highlightYellow, const Color(0xFFFEF3C7));
      expect(tokens.highlightGreen, const Color(0xFFEDF5F0));
      expect(tokens.highlightBlue, const Color(0xFFEDF2F7));
      expect(tokens.underlineColor, const Color(0xFFB8362D));
      expect(tokens.progressTrack, const Color(0xFFE6DFCB));
      expect(tokens.coverPlaceholder, const Color(0xFFF0EBD9));
      expect(tokens.badgeScrim, const Color(0xFF848588));
      expect(tokens.ttsActiveHighlight, const Color(0xFFFAECEA));
      expect(tokens.isEink, false);
      expect(tokens.reducedMotion, false);
      expect(tokens.discretePaging, false);
    });

    test('E-Ink 模式（isEinkMode: true，不論 theme 為何）組裝出正確的'
        ' ElinkTokens 值', () {
      final theme = resolveThemeData(theme: AppTheme.dark, isEinkMode: true);
      final tokens = theme.extension<ElinkTokens>();

      expect(tokens, isNotNull);
      expect(tokens!.highlightYellow, const Color(0xFF000000));
      expect(tokens.highlightGreen, const Color(0xFF000000));
      expect(tokens.highlightBlue, const Color(0xFF000000));
      expect(tokens.underlineColor, const Color(0xFF000000));
      expect(tokens.progressTrack, const Color(0xFF000000));
      expect(tokens.coverPlaceholder, const Color(0xFFFFFFFF));
      expect(tokens.badgeScrim, const Color(0xFF000000));
      expect(tokens.ttsActiveHighlight, const Color(0xFF000000));
      expect(tokens.isEink, true);
      expect(tokens.reducedMotion, true);
      expect(tokens.discretePaging, true);
    });
  });
}
