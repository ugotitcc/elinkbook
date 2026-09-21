import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/main.dart';
import 'package:elinkbook/l10n/app_locale.dart';
import 'package:elinkbook/l10n/app_locale_preferences.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/screens/adaptive_shell_scaffold.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_reader_prefs_manager.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('不傳 initialLocaleOverride／localePreferences 時仍可正常建構（既有相容性）',
      (tester) async {
    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('MaterialApp 正確接上 localizationsDelegates／supportedLocales',
      (tester) async {
    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
      ),
    );
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      materialApp.localizationsDelegates,
      containsAll(AppLocalizations.localizationsDelegates),
    );
    expect(
      materialApp.supportedLocales,
      containsAll(AppLocalizations.supportedLocales),
    );
  });

  testWidgets('initialLocaleOverride 非 null 時，MaterialApp.locale 直接採用該語言',
      (tester) async {
    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
        initialLocaleOverride: AppLocale.en,
      ),
    );
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.locale, const Locale('en'));
  });

  testWidgets('initialLocaleOverride 為 null 時，MaterialApp.locale 亦為 null（交給 localeListResolutionCallback 動態解析）',
      (tester) async {
    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
      ),
    );
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.locale, isNull);
  });

  testWidgets(
      'localeListResolutionCallback 正確接線至 resolveMaterialAppLocale（/receiving-code-review I-1 修正）',
      (tester) async {
    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
      ),
    );
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final callback = materialApp.localeListResolutionCallback;
    expect(callback, isNotNull);

    // 直接呼叫 MaterialApp 實際持有的那個 callback 實例——若 main.dart
    // 誤接了別的函式或簽章寫錯，這裡會直接暴露，而不只是驗證
    // resolveMaterialAppLocale() 本身正確（Task 2 已覆蓋純函式邏輯，這裡
    // 驗證的是「main.dart 真的把它接上去了」這條接線本身）。
    final resolved = callback!(
      const [Locale('fr', 'FR'), Locale('en', 'US')],
      AppLocalizations.supportedLocales,
    );
    expect(resolved, const Locale('en'));
  });

  testWidgets(
      'AppLocalizations.of(context) 在 Widget 樹內可正常取得而不拋例外（/receiving-code-review I-1 修正）',
      (tester) async {
    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
      ),
    );
    await tester.pumpAndSettle();

    final scaffoldContext =
        tester.element(find.byType(AdaptiveShellScaffold));
    expect(AppLocalizations.of(scaffoldContext), isNotNull);
  });

  testWidgets(
      '選取語言後，MaterialApp.locale 立即反映新語言，且 AppLocalePreferences.saveLocaleOverride 持久化新值',
      (tester) async {
    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_language_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_language_option_zh_cn')));
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.locale, const Locale('zh', 'CN'));

    final saved = await AppLocalePreferences().loadLocaleOverride();
    expect(saved, AppLocale.zhCN);
  });

  testWidgets('選取「跟隨系統」後，MaterialApp.locale 變回 null（不再手動覆寫）',
      (tester) async {
    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
        initialLocaleOverride: AppLocale.en,
      ),
    );
    await tester.pumpAndSettle();

    final before = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(before.locale, const Locale('en'));

    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_language_button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('settings_language_option_follow_system')),
    );
    await tester.pumpAndSettle();

    final after = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(after.locale, isNull);

    final saved = await AppLocalePreferences().loadLocaleOverride();
    expect(saved, isNull);
  });
}
