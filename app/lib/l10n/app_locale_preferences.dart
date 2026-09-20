import 'package:shared_preferences/shared_preferences.dart';

import 'app_locale.dart';

/// 介面語言偏好的持久化（FR-49，`docs/adr/0033-interface-locale-device-local-not-synced.md`：
/// 裝置本地儲存，不跨裝置同步）。比照 `AppThemePreferences` 既有模式，直接
/// 使用 `shared_preferences` 官方支援的測試方式驅動測試。
class AppLocalePreferences {
  static const _localeKey = 'app_locale'; // 值域：'zhTW' / 'zhCN' / 'en'（AppLocale enum 成員名稱，非 BCP-47 格式）；鍵不存在＝跟隨系統

  /// 回傳 `null` 代表「跟隨系統」。
  Future<AppLocale?> loadLocaleOverride() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localeKey);
    if (raw == null) return null;
    try {
      return AppLocale.values.byName(raw);
    } catch (_) {
      // 儲存的字串無法對應到任何列舉值時（例如未來改了列舉名稱、或裝置上
      // 的資料被污染），byName 會拋出 ArgumentError；安全回退為跟隨系統。
      return null;
    }
  }

  /// 傳入 `null` 清除既有覆寫（回到跟隨系統）。
  Future<void> saveLocaleOverride(AppLocale? locale) async {
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_localeKey);
    } else {
      await prefs.setString(_localeKey, locale.name);
    }
  }
}
