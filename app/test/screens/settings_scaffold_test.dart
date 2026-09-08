import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';
import 'package:elinkbook/cloud_import/onedrive_oauth_client.dart';
import 'package:elinkbook/screens/settings_scaffold.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_client.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
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
    // 四分區重排後「關於」分區被推到較下方，需放大視窗
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
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
      home: SettingsScaffold(
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
      home: SettingsScaffold(
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
      home: SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
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
      home: SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
    ));

    await tester.tap(find.byKey(const Key('settings_nav_zone_button')));
    await tester.pumpAndSettle();

    expect(find.text('導航熱區'), findsOneWidget);
  });

  testWidgets('點擊「字型管理」導航至 FontManagementScreen', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(
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
      home: SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
    ));

    await tester
        .tap(find.byKey(const Key('settings_reading_defaults_button')));
    await tester.pumpAndSettle();

    expect(find.text('閱讀預設值'), findsOneWidget);
  });

  testWidgets('SettingsScreen 顯示「同步」入口，點擊導航至 SyncSettingsScreen',
      (tester) async {
    // 四分區重排後「同步與帳號」分區被推到較下方，需放大視窗
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final accountRepository = SyncAccountRepository();
    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(
        prefsManager: FakeReaderPrefsManager(),
        syncAccountRepository: accountRepository,
        syncClient: SyncClient(accountRepository: accountRepository),
        onManualSync: () async => true,
        loadLastSyncedAt: () async => null,
      ),
    ));

    expect(find.byKey(const Key('settings_sync_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_sync_button')));
    await tester.pumpAndSettle();

    expect(find.text('同步'), findsOneWidget);
  });

  testWidgets('SettingsScreen 顯示「已連結的雲端匯入帳戶」入口，點擊導航至 CloudAccountSettingsScreen',
      (tester) async {
    // 四分區重排後「同步與帳號」分區被推到較下方，需放大視窗
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final cloudAccountRepository = FakeCloudAccountRepository();
    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(
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
    // 四分區重排後「關於」分區被推到較下方，需放大視窗
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
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
    // 四分區重排後 Console Log 開關被推到較下方，需放大視窗
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(
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
    // 四分區重排後 Console Log 開關被推到較下方，需放大視窗
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
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
    // 四分區重排後 Console Log 開關被推到較下方，需放大視窗
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final prefsManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(prefsManager: prefsManager),
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
      home: SettingsScaffold(
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
  testWidgets(
      'SettingsScreen 主題預覽圓點改讀 resolveThemeData() 的實際色值（不再維持寫死近似值）',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(
        prefsManager: FakeReaderPrefsManager(),
        currentTheme: AppTheme.dark,
      ),
    ));

    final lightPreview =
        resolveThemeData(theme: AppTheme.light, isEinkMode: false);
    final darkPreview =
        resolveThemeData(theme: AppTheme.dark, isEinkMode: false);
    final sepiaPreview =
        resolveThemeData(theme: AppTheme.sepia, isEinkMode: false);

    BoxDecoration decorationFor(String key) => tester
        .widget<Container>(find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(Container),
        ))
        .decoration as BoxDecoration;

    final light = decorationFor('settings_theme_dot_light');
    final dark = decorationFor('settings_theme_dot_dark');
    final sepia = decorationFor('settings_theme_dot_sepia');

    expect(light.color, lightPreview.scaffoldBackgroundColor);
    expect(dark.color, darkPreview.scaffoldBackgroundColor);
    expect(sepia.color, sepiaPreview.scaffoldBackgroundColor);

    // currentTheme 為 dark：dark 圓點是選取狀態，邊框讀取 dark 主題自己的
    // primary；light／sepia 未選取，邊框讀取各自主題自己的 outline
    // （取代原本寫死的 Colors.grey）。
    expect(
        (dark.border as Border).top.color, darkPreview.colorScheme.primary);
    expect(
        (light.border as Border).top.color, lightPreview.colorScheme.outline);
    expect(
        (sepia.border as Border).top.color, sepiaPreview.colorScheme.outline);
  });
  testWidgets(
      'SettingsScreen E-Ink 開啟時，主題預覽圓點呈現虛線邊框，不再降低透明度，'
      '且依目前選擇的主題呈現粗細差異（DESIGN.md §17.2／§7.2）',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(
        prefsManager: FakeReaderPrefsManager(),
        currentTheme: AppTheme.light,
        isEinkMode: true,
      ),
    ));

    // 不再有 Opacity 包裹圓點（原本的降低透明度手法已移除）。
    expect(
      find.descendant(
        of: find.byKey(const Key('settings_theme_dot_light')),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );

    // 鎖定狀態下 Container 不再設定 border（虛線改由疊加的 CustomPaint
    // 繪製）。
    final decoration = tester
        .widget<Container>(find.descendant(
          of: find.byKey(const Key('settings_theme_dot_light')),
          matching: find.byType(Container),
        ))
        .decoration as BoxDecoration;
    expect(decoration.border, isNull);

    CustomPaint customPaintFor(String key) => tester.widget<CustomPaint>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(CustomPaint),
          ),
        );

    // currentTheme 為 light：light 圓點是「目前選擇」，虛線用粗線
    // （3dp）；dark／sepia 未選擇，虛線用細線（1.5dp）——沿用 DESIGN.md
    // §7.2 既有定義的「Border Width 1.5dp -> 3dp」數值，讓鎖定狀態下仍能
    // 分辨原本選的是哪個主題。`_LockedDotBorderPainter` 是本檔案私有類
    // 別，測試檔無法用型別直接存取，改以 dynamic 讀取其公開欄位
    // strokeWidth。
    // ignore: avoid_dynamic_calls
    expect(
        (customPaintFor('settings_theme_dot_light').painter as dynamic)
            .strokeWidth,
        3.0);
    // ignore: avoid_dynamic_calls
    expect(
        (customPaintFor('settings_theme_dot_dark').painter as dynamic)
            .strokeWidth,
        1.5);

    // 提示文字「這裡選的是關閉 E-Ink 後要恢復的主題」顯示。
    expect(find.byKey(const Key('settings_theme_locked_hint')), findsOneWidget);
  });

  testWidgets(
      'SettingsScreen 主題預覽圓點在 E-Ink 開啟時，Semantics 標籤讀出鎖定狀態與目前選擇的主題',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(
        prefsManager: FakeReaderPrefsManager(),
        currentTheme: AppTheme.sepia,
        isEinkMode: true,
      ),
    ));

    final semantics = tester
        .getSemantics(find.byKey(const Key('settings_theme_dot_light')));
    expect(semantics.label, contains('已鎖定'));
    expect(semantics.label, contains('羊皮紙'));

    handle.dispose();
  });

  testWidgets(
      'SettingsScreen 主題預覽圓點在「未鎖定」狀態下仍保有可啟動的 Semantics tap 動作'
      '（回歸保護：Semantics 不得整包排除子樹語意，見 reviews/review-plan-issue-3.md Critical 1）',
      (tester) async {
    final handle = tester.ensureSemantics();
    AppTheme? receivedTheme;
    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(
        prefsManager: FakeReaderPrefsManager(),
        currentTheme: AppTheme.light,
        isEinkMode: false,
        onThemeChanged: (theme) => receivedTheme = theme,
      ),
    ));

    final semantics = tester
        .getSemantics(find.byKey(const Key('settings_theme_dot_sepia')));
    // SemanticsNode 本身沒有 hasAction()，要透過 getSemanticsData() 取得
    // SemanticsData 才有這個方法（已核對 Flutter SDK
    // src/semantics/semantics.dart 原始碼確認）。
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue);

    await tester.tap(find.byKey(const Key('settings_theme_dot_sepia')));
    await tester.pumpAndSettle();
    expect(receivedTheme, AppTheme.sepia);

    handle.dispose();
  });

  testWidgets('SettingsScreen E-Ink 關閉時，不顯示鎖定提示文字，圓點維持一般邊框', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(
        prefsManager: FakeReaderPrefsManager(),
        currentTheme: AppTheme.light,
        isEinkMode: false,
      ),
    ));

    expect(find.byKey(const Key('settings_theme_locked_hint')), findsNothing);

    final decoration = tester
        .widget<Container>(find.descendant(
          of: find.byKey(const Key('settings_theme_dot_light')),
          matching: find.byType(Container),
        ))
        .decoration as BoxDecoration;
    expect(decoration.border, isNotNull);
  });

  testWidgets('四個區塊標題依序為外觀／閱讀／同步與帳號／關於', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
    ));
    await tester.pumpAndSettle();

    // 取所有 Text widget 的 data，只保留四個分區標題（各有至少一個
    // EBSectionHeader 會產生對應文字），並檢查出現順序。
    final allTexts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();

    // 找出四個分區標題在 allTexts 中首次出現的位置
    final expected = ['外觀', '閱讀', '同步與帳號', '關於'];
    final indices = expected.map((h) => allTexts.indexOf(h)).toList();

    // 每個標題都必須存在
    for (var i = 0; i < expected.length; i++) {
      expect(indices[i], isNonNegative,
          reason: '找不到分區標題「${expected[i]}」');
    }
    // 順序必須遞增
    for (var i = 1; i < indices.length; i++) {
      expect(indices[i], greaterThan(indices[i - 1]),
          reason: '「${expected[i]}」應在「${expected[i - 1]}」之後出現');
    }
  });

  testWidgets('AppBar 顯示「書架」「來源」圖示，點擊分別呼叫對應 callback', (tester) async {
    var libraryTapped = 0;
    var sourceTapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(
        prefsManager: FakeReaderPrefsManager(),
        onNavigateToLibrary: () => libraryTapped++,
        onNavigateToSource: () => sourceTapped++,
      ),
    ));

    expect(find.byKey(const Key('settings_library_button')), findsOneWidget);
    expect(find.byKey(const Key('settings_source_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_library_button')));
    await tester.pumpAndSettle();
    expect(libraryTapped, 1);
    expect(sourceTapped, 0);

    await tester.tap(find.byKey(const Key('settings_source_button')));
    await tester.pumpAndSettle();
    expect(sourceTapped, 1);
  });

  testWidgets('未接上 onNavigateToLibrary／onNavigateToSource 時，圖示仍存在但不崩潰', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
    ));

    expect(find.byKey(const Key('settings_library_button')), findsOneWidget);
    expect(find.byKey(const Key('settings_source_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_library_button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('點擊「朗讀語音與語速」導航至 TtsDefaultsScreen', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
    ));

    await tester.tap(find.byKey(const Key('settings_tts_defaults_button')));
    await tester.pumpAndSettle();

    expect(find.text('朗讀語音與語速'), findsOneWidget);
  });
}
