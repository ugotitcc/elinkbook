import 'package:shared_preferences/shared_preferences.dart';

import 'page_turn_mode.dart';
import 'screen_orientation_setting.dart';

/// 翻頁模式／螢幕方向的全域預設值（FR-37／FR-38）。目前無對應設定 UI——
/// `epic-14-system-settings` 尚未開發，本 epic 僅實作「單書覆寫值 `??`
/// 全域預設值」的資料層，初始值沿用現有行為（不改變既有使用者體驗）；
/// `epic-14` 上線後只需在同一組 key 上補設定畫面。直接使用
/// `shared_preferences` 官方支援的測試方式驅動測試，比照
/// `LibraryPreferences`（見 docs/epics/epic-1-library/spec.md）。
class GlobalReaderDefaults {
  static const _pageTurnModeKey = 'global_reader_page_turn_mode';
  static const _screenOrientationKey = 'global_reader_screen_orientation';

  Future<PageTurnMode> loadPageTurnMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pageTurnModeKey);
    if (raw == null) return PageTurnMode.paginated;
    try {
      return PageTurnMode.values.byName(raw);
    } catch (_) {
      // 儲存的字串無法對應到任何列舉值時（例如未來改了列舉名稱、或裝置上
      // 的資料被污染），byName 會拋出 ArgumentError；安全回退為預設值。
      return PageTurnMode.paginated;
    }
  }

  Future<void> savePageTurnMode(PageTurnMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pageTurnModeKey, mode.name);
  }

  Future<ScreenOrientationSetting> loadScreenOrientation() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_screenOrientationKey);
    if (raw == null) return ScreenOrientationSetting.auto;
    try {
      return ScreenOrientationSetting.values.byName(raw);
    } catch (_) {
      return ScreenOrientationSetting.auto;
    }
  }

  Future<void> saveScreenOrientation(ScreenOrientationSetting setting) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_screenOrientationKey, setting.name);
  }
}
