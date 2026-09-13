import 'page_turn_mode.dart';
import 'screen_orientation_setting.dart';

/// 「閱讀預設值」畫面（`ReadingDefaultsScreen`，FR-36/37/38/42）對應的 7 個
/// 欄位，從 `GlobalReaderPrefs` 拆出（2026-09-13，見
/// `docs/superpowers/plans/2026-09-13-split-global-reader-prefs.md`）。UI
/// 畫面與本類別現在是同一件事——見 `CONTEXT.md`「閱讀預設值」詞條
/// 2026-09-13 修訂。全部欄位皆 non-nullable，全域層本身沒有更上層的預設
/// 可回退。
class ReadingDefaults {
  final PageTurnMode pageTurnMode;
  final ScreenOrientationSetting screenOrientation;

  /// 音量鍵翻頁總開關（FR-36），預設 `true`（沿用既有行為）。無單書覆寫層。
  final bool volumeKeyEnabled;

  /// 全螢幕模式全域預設值（FR-42），預設 `false`。與單書層
  /// `BookReaderPrefs.fullscreen` 為雙層解析關係
  /// （`book.fullscreen ?? global.reading.fullscreen`）。
  final bool fullscreen;

  /// 啟動時開啟最後閱讀的那本書，預設 `true`。
  final bool openLastBookOnLaunch;

  /// 「顯示頁首／頁尾」全域預設值，預設 `false`。與單書層
  /// `BookReaderPrefs.showHeader`/`showFooter` 為雙層解析關係。
  final bool showHeader;
  final bool showFooter;

  const ReadingDefaults({
    this.pageTurnMode = PageTurnMode.paginated,
    this.screenOrientation = ScreenOrientationSetting.auto,
    this.volumeKeyEnabled = true,
    this.fullscreen = false,
    this.openLastBookOnLaunch = true,
    this.showHeader = false,
    this.showFooter = false,
  });

  const ReadingDefaults.initial() : this();

  ReadingDefaults copyWith({
    PageTurnMode? pageTurnMode,
    ScreenOrientationSetting? screenOrientation,
    bool? volumeKeyEnabled,
    bool? fullscreen,
    bool? openLastBookOnLaunch,
    bool? showHeader,
    bool? showFooter,
  }) {
    return ReadingDefaults(
      pageTurnMode: pageTurnMode ?? this.pageTurnMode,
      screenOrientation: screenOrientation ?? this.screenOrientation,
      volumeKeyEnabled: volumeKeyEnabled ?? this.volumeKeyEnabled,
      fullscreen: fullscreen ?? this.fullscreen,
      openLastBookOnLaunch: openLastBookOnLaunch ?? this.openLastBookOnLaunch,
      showHeader: showHeader ?? this.showHeader,
      showFooter: showFooter ?? this.showFooter,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReadingDefaults &&
      other.pageTurnMode == pageTurnMode &&
      other.screenOrientation == screenOrientation &&
      other.volumeKeyEnabled == volumeKeyEnabled &&
      other.fullscreen == fullscreen &&
      other.openLastBookOnLaunch == openLastBookOnLaunch &&
      other.showHeader == showHeader &&
      other.showFooter == showFooter;

  @override
  int get hashCode => Object.hash(
        pageTurnMode,
        screenOrientation,
        volumeKeyEnabled,
        fullscreen,
        openLastBookOnLaunch,
        showHeader,
        showFooter,
      );
}
