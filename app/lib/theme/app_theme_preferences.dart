import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

/// 全域主題與 E-Ink 高對比開關的持久化（FR-31）。直接使用
/// `shared_preferences` 官方支援的測試方式驅動測試，比照
/// `LibraryPreferences`（見 docs/epics/epic-1-library/spec.md）。
class AppThemePreferences {
  static const _themeKey = 'app_theme';
  static const _einkModeKey = 'app_eink_mode';

  Future<AppTheme> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_themeKey);
    if (raw == null) return AppTheme.light;
    try {
      return AppTheme.values.byName(raw);
    } catch (_) {
      // 儲存的字串無法對應到任何列舉值時（例如未來改了列舉名稱、或裝置上
      // 的資料被污染），byName 會拋出 ArgumentError；安全回退為預設值。
      return AppTheme.light;
    }
  }

  Future<void> saveTheme(AppTheme theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, theme.name);
  }

  Future<bool> loadEinkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_einkModeKey) ?? false;
  }

  Future<void> saveEinkMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_einkModeKey, enabled);
  }
}
