import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_locale.dart';
import 'package:elinkbook/theme/app_theme.dart';

import 'fake_appearance_dependencies.dart';

void main() {
  test('fakeAppearanceDependencies 預設為淺色、非 E-Ink、跟隨系統，callback 為 no-op 且 non-null', () {
    final deps = fakeAppearanceDependencies();
    expect(deps.currentTheme, AppTheme.light);
    expect(deps.isEinkMode, isFalse);
    expect(deps.currentLocaleOverride, isNull);
    deps.onThemeChanged(AppTheme.dark);
    deps.onEinkModeChanged(true);
    deps.onLocaleChanged(null);
  });

  test('fakeAppearanceDependencies 具名覆寫原樣帶入', () {
    AppTheme? changed;
    final deps = fakeAppearanceDependencies(
      currentTheme: AppTheme.sepia,
      isEinkMode: true,
      currentLocaleOverride: AppLocale.en,
      onThemeChanged: (t) => changed = t,
    );
    deps.onThemeChanged(AppTheme.dark);
    expect(deps.currentTheme, AppTheme.sepia);
    expect(deps.isEinkMode, isTrue);
    expect(deps.currentLocaleOverride, AppLocale.en);
    expect(changed, AppTheme.dark);
  });
}
