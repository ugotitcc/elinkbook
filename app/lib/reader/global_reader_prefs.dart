import 'package:flutter/foundation.dart';

import 'nav_zone_mode.dart';
import 'page_turn_mode.dart';
import 'screen_orientation_setting.dart';
import 'zone_action.dart';

/// 跨書生效的全域預設閱讀偏好。
///
/// 七個欄位皆 non-nullable——與 [BookReaderPrefs] 的「全欄位 nullable、
/// null=未覆寫」語意刻意不同：全域層本身沒有更上層的預設可回退，任何時候
/// 都必須有一個明確生效值。
class GlobalReaderPrefs {
  final PageTurnMode pageTurnMode;
  final ScreenOrientationSetting screenOrientation;

  /// 熱區映射模式，預設 [NavZoneMode.rightFlip]（design.md「新增的
  /// GlobalReaderPrefs 欄位」）。
  final NavZoneMode navZoneMode;

  /// 長度固定 9。僅 [navZoneMode] 為 [NavZoneMode.custom] 時內容才生效
  /// （其餘模式由 [resolveZoneActions] 查表算出，忽略本欄位）；仍持續
  /// 保留是為了使用者切回自訂模式時能還原上次編輯結果。
  final List<ZoneAction> navZoneCustomActions;

  /// 是否顯示熱區輔助線，預設 `false`。
  final bool showNavZoneDebugOverlay;

  /// 音量鍵翻頁總開關（FR-36，epic-14-system-settings Issue 4），預設
  /// `true`（沿用既有行為，不影響升級前的使用者體驗）。無單書覆寫層——
  /// `ReaderPrefsManagerImpl.resolve()` 直接透傳本欄位。
  final bool volumeKeyEnabled;

  /// 全螢幕模式全域預設值（FR-42，epic-14-system-settings Issue 4），
  /// 預設 `false`。與既有單書層 `BookReaderPrefs.fullscreen` 為雙層解析
  /// 關係（`book.fullscreen ?? global.fullscreen`），涵蓋 EPUB 流式／
  /// FXL／PDF 三種格式（design.md 決策 6）。
  final bool fullscreen;

  /// 啟動時開啟最後一本書（epic-18-reader-device-qa Issue 29），預設
  /// `true`。開啟時，App 啟動當下若圖書庫內有任何書籍，直接導向最後
  /// 閱讀（`Book.lastReadTime` 最新）的那一本，取代顯示書架。
  final bool openLastBookOnLaunch;

  const GlobalReaderPrefs({
    required this.pageTurnMode,
    required this.screenOrientation,
    required this.navZoneMode,
    required this.navZoneCustomActions,
    required this.showNavZoneDebugOverlay,
    this.volumeKeyEnabled = true,
    this.fullscreen = false,
    this.openLastBookOnLaunch = true,
  });

  /// 初始值，與現行 GlobalReaderDefaults 的既有硬編碼預設一致，
  /// 不改變任何現有使用者體驗。
  const GlobalReaderPrefs.initial()
      : pageTurnMode = PageTurnMode.paginated,
        screenOrientation = ScreenOrientationSetting.auto,
        navZoneMode = NavZoneMode.rightFlip,
        navZoneCustomActions = rightFlipZoneTemplate,
        showNavZoneDebugOverlay = false,
        volumeKeyEnabled = true,
        fullscreen = false,
        openLastBookOnLaunch = true;

  GlobalReaderPrefs copyWith({
    PageTurnMode? pageTurnMode,
    ScreenOrientationSetting? screenOrientation,
    NavZoneMode? navZoneMode,
    List<ZoneAction>? navZoneCustomActions,
    bool? showNavZoneDebugOverlay,
    bool? volumeKeyEnabled,
    bool? fullscreen,
    bool? openLastBookOnLaunch,
  }) {
    return GlobalReaderPrefs(
      pageTurnMode: pageTurnMode ?? this.pageTurnMode,
      screenOrientation: screenOrientation ?? this.screenOrientation,
      navZoneMode: navZoneMode ?? this.navZoneMode,
      navZoneCustomActions: navZoneCustomActions ?? this.navZoneCustomActions,
      showNavZoneDebugOverlay:
          showNavZoneDebugOverlay ?? this.showNavZoneDebugOverlay,
      volumeKeyEnabled: volumeKeyEnabled ?? this.volumeKeyEnabled,
      fullscreen: fullscreen ?? this.fullscreen,
      openLastBookOnLaunch: openLastBookOnLaunch ?? this.openLastBookOnLaunch,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlobalReaderPrefs &&
      other.pageTurnMode == pageTurnMode &&
      other.screenOrientation == screenOrientation &&
      other.navZoneMode == navZoneMode &&
      listEquals(other.navZoneCustomActions, navZoneCustomActions) &&
      other.showNavZoneDebugOverlay == showNavZoneDebugOverlay &&
      other.volumeKeyEnabled == volumeKeyEnabled &&
      other.fullscreen == fullscreen &&
      other.openLastBookOnLaunch == openLastBookOnLaunch;

  @override
  int get hashCode => Object.hash(
        pageTurnMode,
        screenOrientation,
        navZoneMode,
        Object.hashAll(navZoneCustomActions),
        showNavZoneDebugOverlay,
        volumeKeyEnabled,
        fullscreen,
        openLastBookOnLaunch,
      );
}
