import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/reading_defaults.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';

void main() {
  test('ReadingDefaults.initial() 回傳與現行硬編碼預設一致的值', () {
    const prefs = ReadingDefaults.initial();
    expect(prefs.pageTurnMode, PageTurnMode.paginated);
    expect(prefs.screenOrientation, ScreenOrientationSetting.auto);
    expect(prefs.volumeKeyEnabled, isTrue);
    expect(prefs.fullscreen, isFalse);
    expect(prefs.openLastBookOnLaunch, isTrue);
    expect(prefs.showHeader, isFalse);
    expect(prefs.showFooter, isFalse);
  });

  test('copyWith 只更新指定欄位，其餘欄位保留原值', () {
    const original = ReadingDefaults.initial();
    final updated = original.copyWith(pageTurnMode: PageTurnMode.scroll);
    expect(updated.pageTurnMode, PageTurnMode.scroll);
    expect(updated.screenOrientation, original.screenOrientation);
    expect(updated.volumeKeyEnabled, original.volumeKeyEnabled);
    expect(updated.fullscreen, original.fullscreen);
    expect(updated.openLastBookOnLaunch, original.openLastBookOnLaunch);
    expect(updated.showHeader, original.showHeader);
    expect(updated.showFooter, original.showFooter);
  });

  test('copyWith 可個別更新 volumeKeyEnabled／fullscreen／openLastBookOnLaunch', () {
    const original = ReadingDefaults.initial();
    final updated = original.copyWith(
      volumeKeyEnabled: false,
      fullscreen: true,
      openLastBookOnLaunch: false,
    );
    expect(updated.volumeKeyEnabled, isFalse);
    expect(updated.fullscreen, isTrue);
    expect(updated.openLastBookOnLaunch, isFalse);
    expect(updated.pageTurnMode, original.pageTurnMode);
  });

  test('copyWith 可個別更新 showHeader／showFooter', () {
    const original = ReadingDefaults.initial();
    final updated = original.copyWith(showHeader: true, showFooter: true);
    expect(updated.showHeader, isTrue);
    expect(updated.showFooter, isTrue);
    expect(updated.fullscreen, original.fullscreen);
  });

  test('七個欄位值皆相同的 ReadingDefaults 視為相等', () {
    const a = ReadingDefaults(
      pageTurnMode: PageTurnMode.scroll,
      screenOrientation: ScreenOrientationSetting.lock90,
      volumeKeyEnabled: false,
      fullscreen: true,
      openLastBookOnLaunch: false,
      showHeader: true,
      showFooter: true,
    );
    const b = ReadingDefaults(
      pageTurnMode: PageTurnMode.scroll,
      screenOrientation: ScreenOrientationSetting.lock90,
      volumeKeyEnabled: false,
      fullscreen: true,
      openLastBookOnLaunch: false,
      showHeader: true,
      showFooter: true,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('任一欄位不同時視為不相等', () {
    const a = ReadingDefaults.initial();
    expect(a == a.copyWith(pageTurnMode: PageTurnMode.scroll), isFalse);
    expect(
        a == a.copyWith(screenOrientation: ScreenOrientationSetting.lock90),
        isFalse);
    expect(a == a.copyWith(volumeKeyEnabled: false), isFalse);
    expect(a == a.copyWith(fullscreen: true), isFalse);
    expect(a == a.copyWith(openLastBookOnLaunch: false), isFalse);
    expect(a == a.copyWith(showHeader: true), isFalse);
    expect(a == a.copyWith(showFooter: true), isFalse);
  });
}
