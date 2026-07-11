import 'page_turn_mode.dart';
import 'screen_orientation_setting.dart';

/// 跨書生效的全域預設閱讀偏好。
///
/// 兩個欄位皆 non-nullable——與 [BookReaderPrefs] 的「全欄位 nullable、
/// null=未覆寫」語意刻意不同：全域層本身沒有更上層的預設可回退，任何時候
/// 都必須有一個明確生效值。
class GlobalReaderPrefs {
  final PageTurnMode pageTurnMode;
  final ScreenOrientationSetting screenOrientation;

  const GlobalReaderPrefs({
    required this.pageTurnMode,
    required this.screenOrientation,
  });

  /// 初始值，與現行 GlobalReaderDefaults 的既有硬編碼預設一致，
  /// 不改變任何現有使用者體驗。
  const GlobalReaderPrefs.initial()
      : pageTurnMode = PageTurnMode.paginated,
        screenOrientation = ScreenOrientationSetting.auto;

  GlobalReaderPrefs copyWith({
    PageTurnMode? pageTurnMode,
    ScreenOrientationSetting? screenOrientation,
  }) {
    return GlobalReaderPrefs(
      pageTurnMode: pageTurnMode ?? this.pageTurnMode,
      screenOrientation: screenOrientation ?? this.screenOrientation,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlobalReaderPrefs &&
      other.pageTurnMode == pageTurnMode &&
      other.screenOrientation == screenOrientation;

  @override
  int get hashCode => Object.hash(pageTurnMode, screenOrientation);
}
