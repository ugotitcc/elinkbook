import 'package:flutter/foundation.dart';

import '../l10n/app_locale.dart';
import '../theme/app_theme.dart';

/// 外觀依賴組（ADR 0037）：主題、E-Ink 修飾子與介面語言，加上三個變更 callback。
///
/// 與其他三組不同：它是**快照**，不是 `main()` 建一次的服務。可變狀態的擁有者是
/// `_ElinkBookAppState`，每次 `build()` 依目前 State 組出新的快照往下傳；畫面只讀值、
/// 呼叫 callback，不持有狀態。三個 callback 為 non-null——正式環境與測試都恆有處理者。
/// `currentLocaleOverride == null` 代表跟隨系統（比照 `AppLocalePreferences` 的 nullable 語意）。
@immutable
class AppearanceDependencies {
  final AppTheme currentTheme;
  final bool isEinkMode;
  final AppLocale? currentLocaleOverride;
  final ValueChanged<AppTheme> onThemeChanged;
  final ValueChanged<bool> onEinkModeChanged;
  final ValueChanged<AppLocale?> onLocaleChanged;

  const AppearanceDependencies({
    required this.currentTheme,
    required this.isEinkMode,
    required this.currentLocaleOverride,
    required this.onThemeChanged,
    required this.onEinkModeChanged,
    required this.onLocaleChanged,
  });
}
