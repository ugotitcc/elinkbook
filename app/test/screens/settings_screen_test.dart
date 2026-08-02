import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:elinkbook/screens/settings_screen.dart';
import 'package:elinkbook/theme/app_theme.dart';
import '../support/fake_reader_prefs_manager.dart';
import 'package:elinkbook/reader/custom_fonts_repository.dart';
import '../support/fake_custom_fonts_repository.dart';

const _appInfoChannel = MethodChannel('elinkbook/app_info');

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'elinkBook',
      packageName: 'cc.ugotit.elinkbook',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appInfoChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appInfoChannel, null);
  });

  testWidgets('SettingsScreen 顯示設定標題與「佈景」「關於」「導航熱區」入口', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(prefsManager: FakeReaderPrefsManager()),
    ));

    expect(find.text('設定'), findsOneWidget);
    expect(find.text('佈景'), findsOneWidget);
    expect(find.byKey(const Key('settings_theme_dot_light')), findsOneWidget);
    expect(find.byKey(const Key('settings_theme_dot_dark')), findsOneWidget);
    expect(find.byKey(const Key('settings_theme_dot_sepia')), findsOneWidget);
    expect(find.byKey(const Key('settings_about_button')), findsOneWidget);
    expect(find.byKey(const Key('settings_nav_zone_button')), findsOneWidget);
    expect(
        find.byKey(const Key('settings_font_management_button')),
        findsOneWidget);
  });

  testWidgets('SettingsScreen 點擊主題圓點觸發 onThemeChanged（Issue：AppBar 工具列溢位修復）',
      (tester) async {
    AppTheme? receivedTheme;
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        prefsManager: FakeReaderPrefsManager(),
        currentTheme: AppTheme.light,
        onThemeChanged: (theme) => receivedTheme = theme,
      ),
    ));

    await tester.tap(find.byKey(const Key('settings_theme_dot_sepia')));
    await tester.pumpAndSettle();

    expect(receivedTheme, AppTheme.sepia);
  });

  testWidgets('SettingsScreen E-Ink 模式下主題圓點停用點擊', (tester) async {
    AppTheme? receivedTheme;
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        prefsManager: FakeReaderPrefsManager(),
        currentTheme: AppTheme.light,
        isEinkMode: true,
        onThemeChanged: (theme) => receivedTheme = theme,
      ),
    ));

    await tester.tap(find.byKey(const Key('settings_theme_dot_dark')));
    await tester.pumpAndSettle();

    expect(receivedTheme, isNull);
  });

  testWidgets('點擊「關於」導航至 AboutScreen，可返回 SettingsScreen', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(prefsManager: FakeReaderPrefsManager()),
    ));

    await tester.tap(find.byKey(const Key('settings_about_button')));
    await tester.pumpAndSettle();

    expect(find.text('關於'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('設定'), findsOneWidget);
  });

  testWidgets('點擊「導航熱區」導航至 NavZoneSettingsScreen', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(prefsManager: FakeReaderPrefsManager()),
    ));

    await tester.tap(find.byKey(const Key('settings_nav_zone_button')));
    await tester.pumpAndSettle();

    expect(find.text('導航熱區'), findsOneWidget);
  });

  testWidgets('點擊「字型管理」導航至 FontManagementScreen', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        prefsManager: FakeReaderPrefsManager(),
        customFontsRepository: FakeCustomFontsRepository(),
      ),
    ));

    await tester.tap(find.byKey(const Key('settings_font_management_button')));
    await tester.pumpAndSettle();

    expect(find.text('字型管理'), findsOneWidget);
  });
}
