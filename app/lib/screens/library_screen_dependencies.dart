import 'package:flutter/foundation.dart';

import '../l10n/app_locale.dart';
import '../theme/app_theme.dart';

/// 收斂主題／顯示控制相關欄位（epic-26-architecture-hardening Issue 7）。
/// `currentTheme`/`isEinkMode` 沿用 `LibraryScreen` 原欄位現行預設值
/// （`AppTheme.light`/`false`），維持不傳入時的既有行為。
@immutable
class LibraryThemeDependencies {
  final AppTheme currentTheme;
  final bool isEinkMode;
  final ValueChanged<AppTheme>? onThemeChanged;
  final ValueChanged<bool>? onEinkModeChanged;

  const LibraryThemeDependencies({
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.onEinkModeChanged,
  });
}

/// 收斂介面語言相關欄位（epic-45-interface-i18n Issue 1，`spec.md` §4）。
/// `currentLocaleOverride == null` 代表跟隨系統（比照 `AppLocalePreferences`
/// 既有 nullable 儲存語意，見 `app/lib/l10n/app_locale_preferences.dart`）。
@immutable
class LibraryLocaleDependencies {
  final AppLocale? currentLocaleOverride;
  final ValueChanged<AppLocale?>? onLocaleChanged;

  const LibraryLocaleDependencies({
    this.currentLocaleOverride,
    this.onLocaleChanged,
  });
}
