import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/nav_zone_mode.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/zone_action.dart';

void main() {
  test(
      'GlobalReaderPrefs.initial() 回傳與現行硬編碼預設一致的值（paginated/auto/rightFlip）',
      () {
    const prefs = GlobalReaderPrefs.initial();
    expect(prefs.pageTurnMode, PageTurnMode.paginated);
    expect(prefs.screenOrientation, ScreenOrientationSetting.auto);
    expect(prefs.navZoneMode, NavZoneMode.rightFlip);
    expect(prefs.navZoneCustomActions, rightFlipZoneTemplate);
    expect(prefs.showNavZoneDebugOverlay, isFalse);
  });

  test('copyWith 只更新指定欄位，其餘欄位保留原值', () {
    const original = GlobalReaderPrefs(
      pageTurnMode: PageTurnMode.paginated,
      screenOrientation: ScreenOrientationSetting.auto,
      navZoneMode: NavZoneMode.rightFlip,
      navZoneCustomActions: rightFlipZoneTemplate,
      showNavZoneDebugOverlay: false,
    );
    final updated = original.copyWith(pageTurnMode: PageTurnMode.scroll);
    expect(updated.pageTurnMode, PageTurnMode.scroll);
    expect(updated.screenOrientation, ScreenOrientationSetting.auto);
    expect(updated.navZoneMode, NavZoneMode.rightFlip);
    expect(updated.navZoneCustomActions, rightFlipZoneTemplate);
    expect(updated.showNavZoneDebugOverlay, isFalse);
  });

  test('copyWith 可個別更新熱區三欄位', () {
    const original = GlobalReaderPrefs.initial();
    const customActions = [
      ZoneAction.menu, ZoneAction.none, ZoneAction.none,
      ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
    ];
    final updated = original.copyWith(
      navZoneMode: NavZoneMode.custom,
      navZoneCustomActions: customActions,
      showNavZoneDebugOverlay: true,
    );
    expect(updated.navZoneMode, NavZoneMode.custom);
    expect(updated.navZoneCustomActions, customActions);
    expect(updated.showNavZoneDebugOverlay, isTrue);
    expect(updated.pageTurnMode, original.pageTurnMode);
  });

  test('五個欄位值皆相同的 GlobalReaderPrefs 視為相等', () {
    const a = GlobalReaderPrefs(
      pageTurnMode: PageTurnMode.scroll,
      screenOrientation: ScreenOrientationSetting.lock90,
      navZoneMode: NavZoneMode.oneHand,
      navZoneCustomActions: rightFlipZoneTemplate,
      showNavZoneDebugOverlay: true,
    );
    const b = GlobalReaderPrefs(
      pageTurnMode: PageTurnMode.scroll,
      screenOrientation: ScreenOrientationSetting.lock90,
      navZoneMode: NavZoneMode.oneHand,
      navZoneCustomActions: rightFlipZoneTemplate,
      showNavZoneDebugOverlay: true,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('navZoneCustomActions 內容不同時視為不相等', () {
    const a = GlobalReaderPrefs(
      pageTurnMode: PageTurnMode.paginated,
      screenOrientation: ScreenOrientationSetting.auto,
      navZoneMode: NavZoneMode.custom,
      navZoneCustomActions: [
        ZoneAction.menu, ZoneAction.none, ZoneAction.none,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ],
      showNavZoneDebugOverlay: false,
    );
    const b = GlobalReaderPrefs(
      pageTurnMode: PageTurnMode.paginated,
      screenOrientation: ScreenOrientationSetting.auto,
      navZoneMode: NavZoneMode.custom,
      navZoneCustomActions: [
        ZoneAction.none, ZoneAction.none, ZoneAction.menu,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
        ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ],
      showNavZoneDebugOverlay: false,
    );
    expect(a == b, isFalse);
  });

  test('GlobalReaderPrefs.initial() 的 volumeKeyEnabled 預設 true、fullscreen 預設 false',
      () {
    const prefs = GlobalReaderPrefs.initial();
    expect(prefs.volumeKeyEnabled, isTrue);
    expect(prefs.fullscreen, isFalse);
  });

  test('copyWith 可個別更新 volumeKeyEnabled／fullscreen，不影響其餘欄位', () {
    const original = GlobalReaderPrefs.initial();
    final updated =
        original.copyWith(volumeKeyEnabled: false, fullscreen: true);
    expect(updated.volumeKeyEnabled, isFalse);
    expect(updated.fullscreen, isTrue);
    expect(updated.pageTurnMode, original.pageTurnMode);
    expect(updated.navZoneMode, original.navZoneMode);
  });

  test('volumeKeyEnabled 或 fullscreen 不同時視為不相等', () {
    const a = GlobalReaderPrefs.initial();
    final b = a.copyWith(volumeKeyEnabled: false);
    expect(a == b, isFalse);
    final c = a.copyWith(fullscreen: true);
    expect(a == c, isFalse);
  });

  test('GlobalReaderPrefs.initial() 的 openLastBookOnLaunch 預設 true', () {
    const prefs = GlobalReaderPrefs.initial();
    expect(prefs.openLastBookOnLaunch, isTrue);
  });

  test('copyWith 可更新 openLastBookOnLaunch，不影響其餘欄位', () {
    const original = GlobalReaderPrefs.initial();
    final updated = original.copyWith(openLastBookOnLaunch: false);
    expect(updated.openLastBookOnLaunch, isFalse);
    expect(updated.pageTurnMode, original.pageTurnMode);
    expect(updated.volumeKeyEnabled, original.volumeKeyEnabled);
  });

  test('openLastBookOnLaunch 不同時視為不相等', () {
    const a = GlobalReaderPrefs.initial();
    final b = a.copyWith(openLastBookOnLaunch: false);
    expect(a == b, isFalse);
  });
}
