import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';
import 'package:elinkbook/cloud_import/onedrive_oauth_client.dart';
import 'package:elinkbook/screens/settings_screen.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_client.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import '../support/fake_cloud_account_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_custom_fonts_repository.dart';

const _appInfoChannel = MethodChannel('elinkbook/app_info');

void main() {
  late FlutterSecureStoragePlatform originalPlatform;

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
    SharedPreferences.setMockInitialValues({});
    originalPlatform = FlutterSecureStoragePlatform.instance;
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appInfoChannel, null);
    FlutterSecureStoragePlatform.instance = originalPlatform;
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
    expect(
        find.byKey(const Key('settings_reading_defaults_button')),
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
    // 【審查修正 Important：見補件審查】新增 E-Ink 開關（Issue 5 Task 1）
    // 把畫面內容撐高，「關於」項目在預設 800x600 測試視窗下會被擠出可視
    // 範圍，tap() 打不到——放大測試視窗，比照本檔案 ensureVisible() 對
    // ListView 內 ListTile 無效時的既有替代慣例（見
    // reader_settings_sheet_test.dart）。
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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

  testWidgets('點擊「閱讀預設值」導航至 ReadingDefaultsScreen', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(prefsManager: FakeReaderPrefsManager()),
    ));

    await tester
        .tap(find.byKey(const Key('settings_reading_defaults_button')));
    await tester.pumpAndSettle();

    expect(find.text('閱讀預設值'), findsOneWidget);
  });

  testWidgets('SettingsScreen 顯示「同步」入口，點擊導航至 SyncSettingsScreen',
      (tester) async {
    final accountRepository = SyncAccountRepository();
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        prefsManager: FakeReaderPrefsManager(),
        syncAccountRepository: accountRepository,
        syncClient: SyncClient(accountRepository: accountRepository),
      ),
    ));

    expect(find.byKey(const Key('settings_sync_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_sync_button')));
    await tester.pumpAndSettle();

    expect(find.text('同步'), findsOneWidget);
  });

  testWidgets('SettingsScreen 顯示「已連結的雲端匯入帳戶」入口，點擊導航至 CloudAccountSettingsScreen',
      (tester) async {
    final cloudAccountRepository = FakeCloudAccountRepository();
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        prefsManager: FakeReaderPrefsManager(),
        cloudAccountRepository: cloudAccountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: cloudAccountRepository),
        oneDriveOAuthClient:
            OneDriveOAuthClient(accountRepository: cloudAccountRepository),
      ),
    ));

    expect(
      find.byKey(const Key('settings_cloud_account_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('settings_cloud_account_button')));
    await tester.pumpAndSettle();

    expect(find.text('已連結的雲端匯入帳戶'), findsOneWidget);
  });

  testWidgets(
      '點擊「閱讀器 Console Log」導航至 ReaderConsoleLogScreen（epic-18-reader-device-qa '
      'Issue 33）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(prefsManager: FakeReaderPrefsManager()),
    ));

    expect(
        find.byKey(const Key('settings_reader_console_log_button')),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_reader_console_log_button')));
    await tester.pumpAndSettle();

    expect(find.text('閱讀器 Console Log'), findsOneWidget);
  });

  testWidgets('SettingsScreen 顯示 Console Log 開關，初始值反映已儲存的 consoleLogEnabled',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        prefsManager: FakeReaderPrefsManager(
          globalPrefs:
              const GlobalReaderPrefs.initial().copyWith(consoleLogEnabled: true),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byKey(const Key('settings_console_log_switch')), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('settings_console_log_switch')))
          .value,
      isTrue,
    );
  });

  testWidgets('Console Log 開關預設關閉（尚未儲存過設定時）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(prefsManager: FakeReaderPrefsManager()),
    ));
    await tester.pump();

    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('settings_console_log_switch')))
          .value,
      isFalse,
    );
  });

  testWidgets('切換 Console Log 開關後，onChanged 觸發 saveGlobalPrefs 持久化新值',
      (tester) async {
    final prefsManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(prefsManager: prefsManager),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const Key('settings_console_log_switch')));
    await tester.pump();

    expect(prefsManager.savedGlobalPrefsCalls, hasLength(1));
    expect(prefsManager.savedGlobalPrefsCalls.single.consoleLogEnabled, isTrue);
    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('settings_console_log_switch')))
          .value,
      isTrue,
    );
  });

  testWidgets('SettingsScreen 顯示 E-Ink 模式開關，點擊切換觸發 onEinkModeChanged', (tester) async {
    bool? receivedEink;
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        prefsManager: FakeReaderPrefsManager(),
        currentTheme: AppTheme.light,
        isEinkMode: false,
        onEinkModeChanged: (val) => receivedEink = val,
      ),
    ));

    expect(find.byKey(const Key('settings_eink_mode_switch')), findsOneWidget);
    expect(find.text('E-Ink 高對比模式'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_eink_mode_switch')));
    await tester.pumpAndSettle();

    expect(receivedEink, isTrue);
  });
}
