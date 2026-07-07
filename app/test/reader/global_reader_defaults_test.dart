import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/reader/global_reader_defaults.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('尚未儲存過翻頁模式全域預設時，loadPageTurnMode 回傳預設值 paginated',
      () async {
    final defaults = GlobalReaderDefaults();
    expect(await defaults.loadPageTurnMode(), PageTurnMode.paginated);
  });

  test('savePageTurnMode 寫入後，loadPageTurnMode 讀回相同的值', () async {
    final defaults = GlobalReaderDefaults();
    await defaults.savePageTurnMode(PageTurnMode.scroll);
    expect(await defaults.loadPageTurnMode(), PageTurnMode.scroll);
  });

  test('尚未儲存過螢幕方向全域預設時，loadScreenOrientation 回傳預設值 auto',
      () async {
    final defaults = GlobalReaderDefaults();
    expect(
        await defaults.loadScreenOrientation(), ScreenOrientationSetting.auto);
  });

  test('saveScreenOrientation 寫入後，loadScreenOrientation 讀回相同的值',
      () async {
    final defaults = GlobalReaderDefaults();
    await defaults.saveScreenOrientation(ScreenOrientationSetting.lock90);
    expect(await defaults.loadScreenOrientation(),
        ScreenOrientationSetting.lock90);
  });

  test('已儲存的翻頁模式字串無法對應到任何列舉值時，loadPageTurnMode 安全回退為預設值',
      () async {
    SharedPreferences.setMockInitialValues({
      'global_reader_page_turn_mode': 'not_a_real_enum_value',
    });
    final defaults = GlobalReaderDefaults();
    expect(await defaults.loadPageTurnMode(), PageTurnMode.paginated);
  });

  test('已儲存的螢幕方向字串無法對應到任何列舉值時，loadScreenOrientation 安全回退為預設值',
      () async {
    SharedPreferences.setMockInitialValues({
      'global_reader_screen_orientation': 'not_a_real_enum_value',
    });
    final defaults = GlobalReaderDefaults();
    expect(
        await defaults.loadScreenOrientation(), ScreenOrientationSetting.auto);
  });
}
