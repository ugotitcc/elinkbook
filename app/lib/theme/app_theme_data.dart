import 'package:flutter/material.dart';
import 'app_theme.dart';

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
  const background = Color(0xFFF8F8FA);
  const surface = Color(0xFFFFFFFF);
  const onSurface = Color(0xFF1A1A2E);
  const border = Color(0xFFE0E0E5);
  const primary = Color(0xFF8B5CF6);

  final colorScheme = ColorScheme.light(
    primary: primary,
    surface: surface,
    onSurface: onSurface,
    outline: border,
  );

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: background,
    cardColor: surface,
    dividerColor: border,
    useMaterial3: true,
  );
}

ThemeData _buildDarkTheme() {
  const background = Color(0xFF121214);
  const surface = Color(0xFF1E1E22);
  const onSurface = Color(0xFFE8E8EC);
  const border = Color(0xFF2A2A30);
  const primary = Color(0xFFBB86FC);

  final colorScheme = ColorScheme.dark(
    primary: primary,
    surface: surface,
    onSurface: onSurface,
    outline: border,
  );

  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: background,
    cardColor: surface,
    dividerColor: border,
    useMaterial3: true,
  );
}

ThemeData _buildSepiaTheme() {
  const background = Color(0xFFF4ECD8);
  const surface = Color(0xFFFAF3E3);
  const onSurface = Color(0xFF5B4636);
  const border = Color(0xFFE6DCBF);
  const primary = Color(0xFFB45309);

  final colorScheme = ColorScheme.light(
    primary: primary,
    surface: surface,
    onSurface: onSurface,
    outline: border,
  );

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: background,
    cardColor: surface,
    dividerColor: border,
    useMaterial3: true,
  );
}

ThemeData _buildEinkTheme() {
  final colorScheme = ColorScheme.light(
    primary: Colors.black,
    onPrimary: Colors.white,
    secondary: Colors.black,
    onSecondary: Colors.white,
    surface: Colors.white,
    onSurface: Colors.black,
    error: Colors.black,
    onError: Colors.white,
    outline: Colors.black,
  );

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.white,
    cardColor: Colors.white,
    dividerColor: Colors.black,
    useMaterial3: true,
    // 停用點擊水波紋效果與高亮，以避免電子紙裝置上產生嚴重殘影與刷新閃爍
    splashFactory: NoSplash.splashFactory,
    hoverColor: Colors.transparent,
    highlightColor: Colors.transparent,
  );
}
