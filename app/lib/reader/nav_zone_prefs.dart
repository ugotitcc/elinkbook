import 'package:flutter/foundation.dart';

import 'nav_zone_mode.dart';
import 'zone_action.dart';

/// 導航熱區偏好（epic-7-interaction／FR-24），從 `GlobalReaderPrefs` 拆出
/// （2026-09-13，見 `docs/superpowers/plans/2026-09-13-split-global-reader-prefs.md`）。
/// 三個欄位皆 non-nullable，全域層本身沒有更上層的預設可回退。
class NavZonePrefs {
  /// 熱區映射模式，預設 [NavZoneMode.rightFlip]。
  final NavZoneMode navZoneMode;

  /// 長度固定 9。僅 [navZoneMode] 為 [NavZoneMode.custom] 時內容才生效
  /// （其餘模式由 `resolveZoneActions` 查表算出，忽略本欄位）；仍持續保留
  /// 是為了使用者切回自訂模式時能還原上次編輯結果。
  final List<ZoneAction> navZoneCustomActions;

  /// 是否顯示熱區輔助線，預設 `false`。
  final bool showNavZoneDebugOverlay;

  const NavZonePrefs({
    this.navZoneMode = NavZoneMode.rightFlip,
    this.navZoneCustomActions = rightFlipZoneTemplate,
    this.showNavZoneDebugOverlay = false,
  });

  /// 初始值，與現行硬編碼預設一致，不改變任何現有使用者體驗。
  const NavZonePrefs.initial() : this();

  NavZonePrefs copyWith({
    NavZoneMode? navZoneMode,
    List<ZoneAction>? navZoneCustomActions,
    bool? showNavZoneDebugOverlay,
  }) {
    return NavZonePrefs(
      navZoneMode: navZoneMode ?? this.navZoneMode,
      navZoneCustomActions: navZoneCustomActions ?? this.navZoneCustomActions,
      showNavZoneDebugOverlay:
          showNavZoneDebugOverlay ?? this.showNavZoneDebugOverlay,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NavZonePrefs &&
      other.navZoneMode == navZoneMode &&
      listEquals(other.navZoneCustomActions, navZoneCustomActions) &&
      other.showNavZoneDebugOverlay == showNavZoneDebugOverlay;

  @override
  int get hashCode => Object.hash(
        navZoneMode,
        Object.hashAll(navZoneCustomActions),
        showNavZoneDebugOverlay,
      );
}
