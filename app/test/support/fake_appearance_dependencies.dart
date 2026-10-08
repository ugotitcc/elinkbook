import 'package:flutter/foundation.dart';
import 'package:elinkbook/l10n/app_locale.dart';
import 'package:elinkbook/screens/appearance_dependencies.dart';
import 'package:elinkbook/theme/app_theme.dart';

/// 預設淺色、非 E-Ink、跟隨系統、callback 為 no-op 的外觀快照（ADR 0037）。
AppearanceDependencies fakeAppearanceDependencies({
  AppTheme currentTheme = AppTheme.light,
  bool isEinkMode = false,
  AppLocale? currentLocaleOverride,
  ValueChanged<AppTheme>? onThemeChanged,
  ValueChanged<bool>? onEinkModeChanged,
  ValueChanged<AppLocale?>? onLocaleChanged,
}) {
  return AppearanceDependencies(
    currentTheme: currentTheme,
    isEinkMode: isEinkMode,
    currentLocaleOverride: currentLocaleOverride,
    onThemeChanged: onThemeChanged ?? (_) {},
    onEinkModeChanged: onEinkModeChanged ?? (_) {},
    onLocaleChanged: onLocaleChanged ?? (_) {},
  );
}
