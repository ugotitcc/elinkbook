import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('尚未儲存過主題時，loadTheme 回傳預設值 light', () async {
    final prefs = AppThemePreferences();
    expect(await prefs.loadTheme(), AppTheme.light);
  });

  test('saveTheme 寫入後，loadTheme 讀回相同的值', () async {
    final prefs = AppThemePreferences();
    await prefs.saveTheme(AppTheme.sepia);
    expect(await prefs.loadTheme(), AppTheme.sepia);
  });

  test('尚未儲存過 E-Ink 開關時，loadEinkMode 回傳預設值 false', () async {
    final prefs = AppThemePreferences();
    expect(await prefs.loadEinkMode(), false);
  });

  test('saveEinkMode 寫入後，loadEinkMode 讀回相同的值', () async {
    final prefs = AppThemePreferences();
    await prefs.saveEinkMode(true);
    expect(await prefs.loadEinkMode(), true);
  });

  test('已儲存的主題字串無法對應到任何列舉值時，loadTheme 安全回退為預設值', () async {
    SharedPreferences.setMockInitialValues({
      'app_theme': 'not_a_real_enum_value',
    });
    final prefs = AppThemePreferences();
    expect(await prefs.loadTheme(), AppTheme.light);
  });
}
