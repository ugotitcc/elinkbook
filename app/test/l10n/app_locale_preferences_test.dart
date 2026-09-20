import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/l10n/app_locale.dart';
import 'package:elinkbook/l10n/app_locale_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('尚未儲存過語言覆寫時，loadLocaleOverride 回傳 null（跟隨系統）', () async {
    final prefs = AppLocalePreferences();
    expect(await prefs.loadLocaleOverride(), isNull);
  });

  test('saveLocaleOverride 寫入後，loadLocaleOverride 讀回相同的值', () async {
    final prefs = AppLocalePreferences();
    await prefs.saveLocaleOverride(AppLocale.en);
    expect(await prefs.loadLocaleOverride(), AppLocale.en);
  });

  test('saveLocaleOverride(null) 清除既有覆寫，之後回到跟隨系統', () async {
    final prefs = AppLocalePreferences();
    await prefs.saveLocaleOverride(AppLocale.zhCN);
    expect(await prefs.loadLocaleOverride(), AppLocale.zhCN);

    await prefs.saveLocaleOverride(null);
    expect(await prefs.loadLocaleOverride(), isNull);
  });

  test('已儲存的字串無法對應到任何列舉值時，loadLocaleOverride 安全回退為 null', () async {
    SharedPreferences.setMockInitialValues({
      'app_locale': 'not_a_real_enum_value',
    });
    final prefs = AppLocalePreferences();
    expect(await prefs.loadLocaleOverride(), isNull);
  });

  test('三個 AppLocale 成員皆能正確 round-trip', () async {
    final prefs = AppLocalePreferences();
    for (final locale in AppLocale.values) {
      await prefs.saveLocaleOverride(locale);
      expect(await prefs.loadLocaleOverride(), locale);
    }
  });
}
