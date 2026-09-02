import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'elink_tokens.dart';

/// 參考 prototype/index.html 的 CSS 變數定義，為每種主題建立對應的
/// [ThemeData]。色彩值取自 prototype 的設計（見
/// docs/epics/epic-3-fonts-layout/issues.md Issue 5）。

/// 根據 [theme] 回傳對應的 [ThemeData]，不考慮 E-Ink 高對比模式。
ThemeData buildThemeData(AppTheme theme) {
  switch (theme) {
    case AppTheme.light:
      return _buildLightTheme();
    case AppTheme.dark:
      return _buildDarkTheme();
    case AppTheme.sepia:
      return _buildSepiaTheme();
  }
}

/// 回傳 E-Ink 高對比模式專用的固定黑白 [ThemeData]。
ThemeData buildEinkThemeData() => _buildEinkTheme();

/// 解析最終生效 of [ThemeData]：[isEinkMode] 為 true 時一律套用 E-Ink
/// 高對比主題，不論 [theme] 為何；為 false 時依 [theme] 套用對應主題。
ThemeData resolveThemeData({
  required AppTheme theme,
  required bool isEinkMode,
}) {
  if (isEinkMode) return buildEinkThemeData();
  return buildThemeData(theme);
}

// ──────────────────────────────────────────────────────────
// 私有建構方法
// ──────────────────────────────────────────────────────────

ThemeData _buildLightTheme() {
  const primary = Color(0xFF0284C7);
  const onPrimary = Color(0xFFFFFFFF);
  const primaryContainer = Color(0xFFE0F2FE);
  const onPrimaryContainer = Color(0xFF0284C7);
  const surface = Color(0xFFFFFFFF);
  const onSurface = Color(0xFF0F172A);
  const onSurfaceVariant = Color(0xFF334155);
  const outline = Color(0xFFCBDFE9);
  const scaffoldBackground = Color(0xFFF0F6FC);
  const surfaceContainerHighest = Color(0xFFE6F1FA);
  const error = Color(0xFFEF4444);

  final colorScheme = ColorScheme.light(
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    surfaceContainerHighest: surfaceContainerHighest,
    error: error,
  );

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackground,
    useMaterial3: true,
    extensions: const [
      ElinkTokens(
        highlightYellow: Color(0xFFFEF08A),
        highlightGreen: Color(0xFFBBF7D0),
        highlightBlue: Color(0xFFBFDBFE),
        underlineColor: Color(0xFF0284C7),
        progressTrack: Color(0xFFCBDFE9),
        coverPlaceholder: Color(0xFFE6F1FA),
        badgeScrim: Color(0xFF94A3B8),
        ttsActiveHighlight: Color(0xFFE0F2FE),
        isEink: false,
        reducedMotion: false,
        discretePaging: false,
      ),
    ],
  );
}

ThemeData _buildDarkTheme() {
  const primary = Color(0xFF38BDF8);
  const onPrimary = Color(0xFF141416);
  const primaryContainer = Color(0xFF182836);
  const onPrimaryContainer = Color(0xFF38BDF8);
  const surface = Color(0xFF1D1D22);
  const onSurface = Color(0xFFF2EFE6);
  const onSurfaceVariant = Color(0xFFB5B2A8);
  // 【epic-35-design-system-tokens Issue 2】改採 DESIGN.md §1.1 色表值，
  // 不再維持先前真機電子紙實測調亮值（outline #86868F／
  // surfaceContainerHighest #3C3C44，見 spec.md「Dark 主題色值衝突決議」）
  // ——選擇配色系統一致性優先。這兩個角色跟 surface 的感知亮度差因此大幅
  // 縮小，Switch 等元件不再靠這兩個角色的顏色對比撐可辨識度，改由
  // _buildSwitchTheme() 的 onSurface 邊框補強機制承接（見下方 switchTheme
  // 賦值處，Issue 2 Task 5 加上）。
  const outline = Color(0xFF2C2C34);
  const scaffoldBackground = Color(0xFF141416);
  const surfaceContainerHighest = Color(0xFF19191D);
  const error = Color(0xFFF87171);

  final colorScheme = ColorScheme.dark(
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    surfaceContainerHighest: surfaceContainerHighest,
    error: error,
  );

  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackground,
    useMaterial3: true,
    extensions: const [
      ElinkTokens(
        highlightYellow: Color(0xFF854D0E),
        highlightGreen: Color(0xFF166534),
        highlightBlue: Color(0xFF1E40AF),
        underlineColor: Color(0xFF38BDF8),
        progressTrack: Color(0xFF2C2C34),
        coverPlaceholder: Color(0xFF1D1D22),
        badgeScrim: Color(0xFF7A7872),
        ttsActiveHighlight: Color(0xFF182836),
        isEink: false,
        reducedMotion: false,
        discretePaging: false,
      ),
    ],
  );
}

ThemeData _buildSepiaTheme() {
  const primary = Color(0xFFB8362D);
  const onPrimary = Color(0xFFFFFFFF);
  const primaryContainer = Color(0xFFFAECEA);
  const onPrimaryContainer = Color(0xFFB8362D);
  const surface = Color(0xFFFAF3E3);
  const onSurface = Color(0xFF1F2022);
  const onSurfaceVariant = Color(0xFF535457);
  const outline = Color(0xFFE6DFCB);
  const scaffoldBackground = Color(0xFFFCFAF2);
  const surfaceContainerHighest = Color(0xFFF0EBD9);
  const error = Color(0xFFDC2626);

  final colorScheme = ColorScheme.light(
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    surfaceContainerHighest: surfaceContainerHighest,
    error: error,
  );

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackground,
    useMaterial3: true,
    extensions: const [
      ElinkTokens(
        highlightYellow: Color(0xFFFEF3C7),
        highlightGreen: Color(0xFFEDF5F0),
        highlightBlue: Color(0xFFEDF2F7),
        underlineColor: Color(0xFFB8362D),
        progressTrack: Color(0xFFE6DFCB),
        coverPlaceholder: Color(0xFFF0EBD9),
        badgeScrim: Color(0xFF848588),
        ttsActiveHighlight: Color(0xFFFAECEA),
        isEink: false,
        reducedMotion: false,
        discretePaging: false,
      ),
    ],
  );
}

ThemeData _buildEinkTheme() {
  const primary = Color(0xFF000000);
  const primaryContainer = Color(0xFFFFFFFF);
  const onPrimaryContainer = Color(0xFF000000);
  const surface = Color(0xFFFFFFFF);
  const onSurface = Color(0xFF000000);
  const onSurfaceVariant = Color(0xFF000000);
  const outline = Color(0xFF000000);
  const surfaceContainerHighest = Color(0xFFFFFFFF);
  const error = Color(0xFF000000);

  final colorScheme = ColorScheme.light(
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    surfaceContainerHighest: surfaceContainerHighest,
    error: error,
    onError: Colors.white,
  );

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.white,
    useMaterial3: true,
    // 停用點擊水波紋效果與高亮，以避免電子紙裝置上產生嚴重殘影與刷新閃爍
    splashFactory: NoSplash.splashFactory,
    hoverColor: Colors.transparent,
    highlightColor: Colors.transparent,
    extensions: const [
      ElinkTokens(
        // highlightYellow／highlightGreen／highlightBlue／ttsActiveHighlight：
        // DESIGN.md §1.2 標註「無背景（改用下劃線／外框／點虛線）」、未給
        // 明確 hex 值——E-Ink 純黑白色盤下取黑色（描邊/底線用色），實際
        // 「不畫底色改畫線條」的渲染邏輯屬其他 Issue 範圍，這裡只決定色票值。
        highlightYellow: Color(0xFF000000),
        highlightGreen: Color(0xFF000000),
        highlightBlue: Color(0xFF000000),
        underlineColor: Color(0xFF000000),
        progressTrack: Color(0xFF000000),
        coverPlaceholder: Color(0xFFFFFFFF),
        badgeScrim: Color(0xFF000000),
        ttsActiveHighlight: Color(0xFF000000),
        isEink: true,
        reducedMotion: true,
        discretePaging: true,
      ),
    ],
  );
}
