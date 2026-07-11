import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';

void main() {
  test('GlobalReaderPrefs.initial() 回傳與現行硬編碼預設一致的值（paginated/auto）', () {
    const prefs = GlobalReaderPrefs.initial();
    expect(prefs.pageTurnMode, PageTurnMode.paginated);
    expect(prefs.screenOrientation, ScreenOrientationSetting.auto);
  });

  test('copyWith 只更新指定欄位，其餘欄位保留原值', () {
    const original = GlobalReaderPrefs(
      pageTurnMode: PageTurnMode.paginated,
      screenOrientation: ScreenOrientationSetting.auto,
    );
    final updated = original.copyWith(pageTurnMode: PageTurnMode.scroll);
    expect(updated.pageTurnMode, PageTurnMode.scroll);
    expect(updated.screenOrientation, ScreenOrientationSetting.auto);
  });

  test('兩個欄位值相同的 GlobalReaderPrefs 視為相等', () {
    const a = GlobalReaderPrefs(
      pageTurnMode: PageTurnMode.scroll,
      screenOrientation: ScreenOrientationSetting.lock90,
    );
    const b = GlobalReaderPrefs(
      pageTurnMode: PageTurnMode.scroll,
      screenOrientation: ScreenOrientationSetting.lock90,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
