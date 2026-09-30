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
import 'package:elinkbook/l10n/app_locale.dart';
import 'package:elinkbook/screens/settings_scaffold.dart';
import 'package:elinkbook/sync/sync_checkpoint_result.dart';
import 'package:elinkbook/screens/widgets/eb_section_header.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_client.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/search/full_text_search_settings_repository.dart';
import '../support/fake_cloud_account_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/pump_localized_widget.dart';
import '../support/fake_custom_fonts_repository.dart';
import '../support/fake_downloadable_font_store.dart';
import '../support/fake_full_text_search_settings_repository.dart';

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
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      {},
    );
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

    await pumpLocalizedWidget(tester, SettingsScaffold(prefsManager: FakeReaderPrefsManager()));

    expect(find.text('設定'), findsOneWidget);
    expect(find.text('佈景'), findsOneWidget);
    expect(find.byKey(const Key('settings_theme_dot_light')), findsOneWidget);
    expect(find.byKey(const Key('settings_theme_dot_dark')), findsOneWidget);
    expect(find.byKey(const Key('settings_theme_dot_sepia')), findsOneWidget);
    expect(find.byKey(const Key('settings_about_button')), findsOneWidget);
    expect(find.byKey(const Key('settings_nav_zone_button')), findsOneWidget);
    expect(
      find.byKey(const Key('settings_font_management_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('settings_reading_defaults_button')),
      findsOneWidget,
    );
  });

  testWidgets('SettingsScreen 點擊主題圓點觸發 onThemeChanged（Issue：AppBar 工具列溢位修復）', (
    tester,
  ) async {
    AppTheme? receivedTheme;
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          currentTheme: AppTheme.light,
          onThemeChanged: (theme) => receivedTheme = theme,
        ),
    );

    await tester.tap(find.byKey(const Key('settings_theme_dot_sepia')));
    await tester.pumpAndSettle();

    expect(receivedTheme, AppTheme.sepia);
  });

  testWidgets('SettingsScreen E-Ink 模式下主題圓點停用點擊', (tester) async {
    AppTheme? receivedTheme;
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          currentTheme: AppTheme.light,
          isEinkMode: true,
          onThemeChanged: (theme) => receivedTheme = theme,
        ),
    );

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
    // epic-45 Issue 1 新增「語言」卡片後需再加大高度，原 1000 已不足
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpLocalizedWidget(tester, SettingsScaffold(prefsManager: FakeReaderPrefsManager()));

    await tester.tap(find.byKey(const Key('settings_about_button')));
    await tester.pumpAndSettle();

    expect(find.text('關於'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('設定'), findsOneWidget);
  });

  testWidgets('點擊「導航熱區」導航至 NavZoneSettingsScreen', (tester) async {
    await pumpLocalizedWidget(tester, SettingsScaffold(prefsManager: FakeReaderPrefsManager()));

    await tester.tap(find.byKey(const Key('settings_nav_zone_button')));
    await tester.pumpAndSettle();

    expect(find.text('導航熱區'), findsOneWidget);
  });

  testWidgets('點擊「字型管理」導航至 FontManagementScreen', (tester) async {
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          customFontsRepository: FakeCustomFontsRepository(),
        ),
    );

    await tester.tap(find.byKey(const Key('settings_font_management_button')));
    await tester.pumpAndSettle();

    expect(find.text('字型管理'), findsOneWidget);
  });

  testWidgets('點擊「閱讀預設值」導航至 ReadingDefaultsScreen', (tester) async {
    await pumpLocalizedWidget(tester, SettingsScaffold(prefsManager: FakeReaderPrefsManager()));

    await tester.tap(find.byKey(const Key('settings_reading_defaults_button')));
    await tester.pumpAndSettle();

    expect(find.text('閱讀預設值'), findsOneWidget);
  });

  testWidgets('SettingsScreen 顯示「同步」入口，點擊導航至 SyncSettingsScreen', (
    tester,
  ) async {
    // 四分區重排後「同步與帳號」分區被推到較下方，需放大視窗
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final accountRepository = SyncAccountRepository();
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          syncAccountRepository: accountRepository,
          syncClient: SyncClient(accountRepository: accountRepository),
          onManualSync: () async => SyncCheckpointResult.synced,
          loadLastSyncedAt: () async => null,
        ),
    );

    expect(find.byKey(const Key('settings_sync_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_sync_button')));
    await tester.pumpAndSettle();

    expect(find.text('同步'), findsOneWidget);
  });

  testWidgets(
    'SettingsScreen 顯示「已連結的雲端匯入帳戶」入口，點擊導航至 CloudAccountSettingsScreen',
    (tester) async {
      // 四分區重排後「同步與帳號」分區被推到較下方，需放大視窗
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final cloudAccountRepository = FakeCloudAccountRepository();
      await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            cloudAccountRepository: cloudAccountRepository,
            googleDriveOAuthClient: GoogleDriveOAuthClient(
              accountRepository: cloudAccountRepository,
            ),
            oneDriveOAuthClient: OneDriveOAuthClient(
              accountRepository: cloudAccountRepository,
            ),
          ),
    );

      expect(
        find.byKey(const Key('settings_cloud_account_button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('settings_cloud_account_button')));
      await tester.pumpAndSettle();

      expect(find.text('已連結的雲端匯入帳戶'), findsOneWidget);
    },
  );

  testWidgets(
    '點擊「閱讀器 Console Log」導航至 ReaderConsoleLogScreen（epic-18-reader-device-qa '
    'Issue 33）',
    (tester) async {
      // 四分區重排後「關於」分區被推到較下方，需放大視窗
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await pumpLocalizedWidget(tester, SettingsScaffold(prefsManager: FakeReaderPrefsManager()));

      expect(
        find.byKey(const Key('settings_reader_console_log_button')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('settings_reader_console_log_button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('閱讀器 Console Log'), findsOneWidget);
    },
  );

  testWidgets('SettingsScreen 顯示 Console Log 開關，初始值反映已儲存的 consoleLogEnabled', (
    tester,
  ) async {
    // 四分區重排後 Console Log 開關被推到較下方，需放大視窗
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(
            globalPrefs: const GlobalReaderPrefs.initial().copyWith(
              consoleLogEnabled: true,
            ),
          ),
        ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('settings_console_log_switch')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('settings_console_log_switch')),
          )
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

    await pumpLocalizedWidget(tester, SettingsScaffold(prefsManager: FakeReaderPrefsManager()));
    await tester.pump();

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('settings_console_log_switch')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('切換 Console Log 開關後，onChanged 觸發 saveGlobalPrefs 持久化新值', (
    tester,
  ) async {
    // 四分區重排後 Console Log 開關被推到較下方，需放大視窗
    // epic-45 Issue 1 新增「語言」卡片後需再加大高度，原 1200 已不足
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final prefsManager = FakeReaderPrefsManager();
    await pumpLocalizedWidget(tester, SettingsScaffold(prefsManager: prefsManager));
    await tester.pump();

    await tester.tap(find.byKey(const Key('settings_console_log_switch')));
    await tester.pump();

    expect(prefsManager.savedGlobalPrefsCalls, hasLength(1));
    expect(prefsManager.savedGlobalPrefsCalls.single.consoleLogEnabled, isTrue);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('settings_console_log_switch')),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('SettingsScreen 顯示 E-Ink 模式開關，點擊切換觸發 onEinkModeChanged', (
    tester,
  ) async {
    bool? receivedEink;
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          currentTheme: AppTheme.light,
          isEinkMode: false,
          onEinkModeChanged: (val) => receivedEink = val,
        ),
    );

    expect(find.byKey(const Key('settings_eink_mode_switch')), findsOneWidget);
    expect(find.text('E-Ink 高對比模式'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_eink_mode_switch')));
    await tester.pumpAndSettle();

    expect(receivedEink, isTrue);
  });
  testWidgets('SettingsScreen 主題預覽圓點改讀 resolveThemeData() 的實際色值（不再維持寫死近似值）', (
    tester,
  ) async {
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          currentTheme: AppTheme.dark,
        ),
    );

    final lightPreview = resolveThemeData(
      theme: AppTheme.light,
      isEinkMode: false,
    );
    final darkPreview = resolveThemeData(
      theme: AppTheme.dark,
      isEinkMode: false,
    );
    final sepiaPreview = resolveThemeData(
      theme: AppTheme.sepia,
      isEinkMode: false,
    );

    BoxDecoration decorationFor(String key) =>
        tester
                .widget<Container>(
                  find.descendant(
                    of: find.byKey(Key(key)),
                    matching: find.byType(Container),
                  ),
                )
                .decoration
            as BoxDecoration;

    final light = decorationFor('settings_theme_dot_light');
    final dark = decorationFor('settings_theme_dot_dark');
    final sepia = decorationFor('settings_theme_dot_sepia');

    expect(light.color, lightPreview.scaffoldBackgroundColor);
    expect(dark.color, darkPreview.scaffoldBackgroundColor);
    expect(sepia.color, sepiaPreview.scaffoldBackgroundColor);

    // currentTheme 為 dark：dark 圓點是選取狀態，邊框讀取 dark 主題自己的
    // primary；light／sepia 未選取，邊框讀取各自主題自己的 outline
    // （取代原本寫死的 Colors.grey）。
    expect((dark.border as Border).top.color, darkPreview.colorScheme.primary);
    expect(
      (light.border as Border).top.color,
      lightPreview.colorScheme.outline,
    );
    expect(
      (sepia.border as Border).top.color,
      sepiaPreview.colorScheme.outline,
    );
  });
  testWidgets('SettingsScreen E-Ink 開啟時，主題預覽圓點呈現虛線邊框，不再降低透明度，'
      '且依目前選擇的主題呈現粗細差異（DESIGN.md §17.2／§7.2）', (tester) async {
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          currentTheme: AppTheme.light,
          isEinkMode: true,
        ),
    );

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
    final decoration =
        tester
                .widget<Container>(
                  find.descendant(
                    of: find.byKey(const Key('settings_theme_dot_light')),
                    matching: find.byType(Container),
                  ),
                )
                .decoration
            as BoxDecoration;
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
      3.0,
    );
    // ignore: avoid_dynamic_calls
    expect(
      (customPaintFor('settings_theme_dot_dark').painter as dynamic)
          .strokeWidth,
      1.5,
    );

    // 提示文字「這裡選的是關閉 E-Ink 後要恢復的主題」顯示。
    expect(find.byKey(const Key('settings_theme_locked_hint')), findsOneWidget);
  });

  testWidgets('SettingsScreen 主題預覽圓點在 E-Ink 開啟時，Semantics 標籤讀出鎖定狀態與目前選擇的主題', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          currentTheme: AppTheme.sepia,
          isEinkMode: true,
        ),
    );

    final semantics = tester.getSemantics(
      find.byKey(const Key('settings_theme_dot_light')),
    );
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
      await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            currentTheme: AppTheme.light,
            isEinkMode: false,
            onThemeChanged: (theme) => receivedTheme = theme,
          ),
    );

      final semantics = tester.getSemantics(
        find.byKey(const Key('settings_theme_dot_sepia')),
      );
      // SemanticsNode 本身沒有 hasAction()，要透過 getSemanticsData() 取得
      // SemanticsData 才有這個方法（已核對 Flutter SDK
      // src/semantics/semantics.dart 原始碼確認）。
      expect(
        semantics.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tester.tap(find.byKey(const Key('settings_theme_dot_sepia')));
      await tester.pumpAndSettle();
      expect(receivedTheme, AppTheme.sepia);

      handle.dispose();
    },
  );

  testWidgets('SettingsScreen E-Ink 關閉時，不顯示鎖定提示文字，圓點維持一般邊框', (tester) async {
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          currentTheme: AppTheme.light,
          isEinkMode: false,
        ),
    );

    expect(find.byKey(const Key('settings_theme_locked_hint')), findsNothing);

    final decoration =
        tester
                .widget<Container>(
                  find.descendant(
                    of: find.byKey(const Key('settings_theme_dot_light')),
                    matching: find.byType(Container),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(decoration.border, isNotNull);
  });

  testWidgets('四個區塊標題依序為外觀／閱讀／同步與帳號／關於', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpLocalizedWidget(tester, SettingsScaffold(prefsManager: FakeReaderPrefsManager()));
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
      expect(indices[i], isNonNegative, reason: '找不到分區標題「${expected[i]}」');
    }
    // 順序必須遞增
    for (var i = 1; i < indices.length; i++) {
      expect(
        indices[i],
        greaterThan(indices[i - 1]),
        reason: '「${expected[i]}」應在「${expected[i - 1]}」之後出現',
      );
    }
  });

  testWidgets('視覺還原（docs/research/uiux/VISUAL_ANALYSIS.md）：每個設定項目改以獨立卡片'
      '（Card）呈現，分區之間不再靠 Divider 分隔——改由 EBSectionHeader 自身的'
      '頂部留白區隔，畫面上完全不出現 Divider', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpLocalizedWidget(tester, SettingsScaffold(prefsManager: FakeReaderPrefsManager()));
    await tester.pumpAndSettle();

    expect(find.byType(Divider), findsNothing, reason: '不應再出現分隔線');

    final listView = tester.widget<ListView>(find.byType(ListView));
    final children =
        (listView.childrenDelegate as SliverChildListDelegate).children;
    final headerIndices = <int>[
      for (var i = 0; i < children.length; i++)
        if (children[i] is EBSectionHeader) i,
    ];
    expect(headerIndices.length, 4, reason: '應有外觀／閱讀／同步與帳號／關於四個分區標題');
    expect(headerIndices.first, 0, reason: '第一個分區標題「外觀」前不應有任何元素');

    // 每個已知的設定項目 Key，皆應能往上找到一個 Card 祖先（證明改用卡片
    // 樣式而非裸 ListTile）。
    const itemKeys = [
      'settings_font_management_button',
      'settings_reading_defaults_button',
      'settings_nav_zone_button',
      'settings_tts_defaults_button',
      'settings_sync_button',
      'settings_cloud_account_button',
      'settings_about_button',
      'settings_reader_console_log_button',
    ];
    for (final key in itemKeys) {
      expect(
        find.ancestor(of: find.byKey(Key(key)), matching: find.byType(Card)),
        findsOneWidget,
        reason: '$key 應包裹在一張 Card 內',
      );
    }
  });

  testWidgets('AppBar 顯示「書架」「來源」圖示，點擊分別呼叫對應 callback', (tester) async {
    var libraryTapped = 0;
    var sourceTapped = 0;
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          onNavigateToLibrary: () => libraryTapped++,
          onNavigateToSource: () => sourceTapped++,
        ),
    );

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

  testWidgets('未接上 onNavigateToLibrary／onNavigateToSource 時，圖示仍存在但不崩潰', (
    tester,
  ) async {
    await pumpLocalizedWidget(tester, SettingsScaffold(prefsManager: FakeReaderPrefsManager()));

    expect(find.byKey(const Key('settings_library_button')), findsOneWidget);
    expect(find.byKey(const Key('settings_source_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_library_button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('點擊「朗讀語音與語速」導航至 TtsDefaultsScreen', (tester) async {
    await pumpLocalizedWidget(tester, SettingsScaffold(prefsManager: FakeReaderPrefsManager()));

    await tester.tap(find.byKey(const Key('settings_tts_defaults_button')));
    await tester.pumpAndSettle();

    expect(find.text('朗讀語音與語速'), findsOneWidget);
  });

  group('epic-10-search Issue 3：全文檢索設定開關', () {
    testWidgets('開關初始值反映 repository.isEnabled()', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = FakeFullTextSearchSettingsRepository(
        initialEnabled: {ContentIndexCategory.pdf: true},
      );
      await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository: repository,
          ),
    );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Switch>(
                find.byKey(const Key('settings_full_text_search_pdf_switch')))
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<Switch>(find.byKey(
                const Key('settings_full_text_search_foliate_switch')))
            .value,
        isFalse,
      );
    });

    testWidgets('開啟開關前彈出確認對話框，取消不呼叫 setEnabled', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = FakeFullTextSearchSettingsRepository();
      await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository: repository,
          ),
    );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('settings_full_text_search_pdf_switch')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('full_text_search_enable_confirm_dialog')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(
          const Key('full_text_search_enable_confirm_dialog_cancel')));
      await tester.pumpAndSettle();

      expect(repository.setEnabledCalls, isEmpty);
      expect(
        tester
            .widget<Switch>(
                find.byKey(const Key('settings_full_text_search_pdf_switch')))
            .value,
        isFalse,
      );
    });

    testWidgets('開啟開關確認後呼叫 setEnabled(true) 並更新畫面狀態', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = FakeFullTextSearchSettingsRepository();
      await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository: repository,
          ),
    );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('settings_full_text_search_pdf_switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(
          const Key('full_text_search_enable_confirm_dialog_confirm')));
      await tester.pumpAndSettle();

      expect(repository.setEnabledCalls, [(ContentIndexCategory.pdf, true)]);
      expect(
        tester
            .widget<Switch>(
                find.byKey(const Key('settings_full_text_search_pdf_switch')))
            .value,
        isTrue,
      );
    });

    testWidgets('關閉開關不彈出確認對話框，直接呼叫 setEnabled(false)', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = FakeFullTextSearchSettingsRepository(
        initialEnabled: {ContentIndexCategory.pdf: true},
      );
      await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository: repository,
          ),
    );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('settings_full_text_search_pdf_switch')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('full_text_search_enable_confirm_dialog')),
        findsNothing,
      );
      expect(repository.setEnabledCalls, [(ContentIndexCategory.pdf, false)]);
    });

    testWidgets(
        '重建索引按鈕：開關開啟時可用，點擊後呼叫 rebuildIndex（review-plan-issue-3.md I-1）',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = FakeFullTextSearchSettingsRepository(
        initialEnabled: {ContentIndexCategory.pdf: true},
      );
      await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository: repository,
          ),
    );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(
          const Key('settings_full_text_search_pdf_rebuild_button')));
      await tester.pumpAndSettle();

      expect(repository.rebuildIndexCalls, [ContentIndexCategory.pdf]);
    });

    testWidgets('重建索引按鈕：開關關閉時停用', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository:
                FakeFullTextSearchSettingsRepository(),
          ),
    );
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(find.byKey(
          const Key('settings_full_text_search_pdf_rebuild_button')));
      expect(button.onPressed, isNull);
    });

    testWidgets('isFullTextSearchAvailable 為 false 時顯示不支援提示、不顯示開關',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository:
                FakeFullTextSearchSettingsRepository(),
            isFullTextSearchAvailable: false,
          ),
    );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('settings_full_text_search_unavailable_hint')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings_full_text_search_pdf_switch')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('settings_full_text_search_foliate_switch')),
        findsNothing,
      );
    });

    testWidgets(
        'didUpdateWidget 時重新載入全文檢索開關狀態（review-plan-issue-3.md M-1）',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = FakeFullTextSearchSettingsRepository();
      await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository: repository,
          ),
    );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Switch>(
                find.byKey(const Key('settings_full_text_search_pdf_switch')))
            .value,
        isFalse,
      );

      // 模擬另一個入口（Issue 4 的全庫搜尋畫面）呼叫 setEnabled 之後，本
      // 畫面因為 IndexedStack 切換分頁而重新 build（同一個 State，重新
      // 傳入等價的 widget 設定）。
      await repository.setEnabled(ContentIndexCategory.pdf, true);
      await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
            prefsManager: FakeReaderPrefsManager(),
            fullTextSearchSettingsRepository: repository,
          ),
    );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Switch>(
                find.byKey(const Key('settings_full_text_search_pdf_switch')))
            .value,
        isTrue,
      );
    });
  });

  group('epic-45-interface-i18n Issue 1：語言選擇 UI', () {
    testWidgets('顯示「語言」入口，currentLocaleOverride 非 null 時 subtitle 顯示該語言名稱',
        (tester) async {
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          currentLocaleOverride: AppLocale.zhCN,
        ),
      );

      expect(find.byKey(const Key('settings_language_button')), findsOneWidget);
      expect(find.text('語言'), findsOneWidget);
      // epic-48：語言名稱一律以該語言本身的寫法顯示（endonym），不隨介面語系翻譯。
      expect(find.text('简体中文'), findsOneWidget);
    });

    testWidgets(
        'currentLocaleOverride 為 null（跟隨系統）時，subtitle 動態標註目前系統實際生效語言',
        (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);

      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
      );

      expect(find.text('跟隨系統（English）'), findsOneWidget);
    });

    testWidgets('英文介面下語言選項仍顯示「正體中文」「简体中文」「English」（epic-48）',
        (tester) async {
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          currentLocaleOverride: AppLocale.zhTW,
        ),
        locale: const Locale('en'),
      );

      // 設定頁「Language」列的副標題
      expect(find.text('正體中文'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings_language_button')));
      await tester.pumpAndSettle();

      Finder optionText(String key, String text) => find.descendant(
            of: find.byKey(Key(key)),
            matching: find.text(text),
          );
      expect(optionText('settings_language_option_zh_tw', '正體中文'), findsOneWidget);
      expect(optionText('settings_language_option_zh_cn', '简体中文'), findsOneWidget);
      expect(optionText('settings_language_option_en', 'English'), findsOneWidget);
      expect(find.text('Traditional Chinese'), findsNothing);
      expect(find.text('Simplified Chinese'), findsNothing);
    });

    testWidgets('點擊「語言」開啟選擇器，4 個選項存在，目前選中項目正確反映 currentLocaleOverride',
        (tester) async {
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          currentLocaleOverride: AppLocale.en,
        ),
      );

      await tester.tap(find.byKey(const Key('settings_language_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('settings_language_option_follow_system')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings_language_option_zh_tw')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings_language_option_zh_cn')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settings_language_option_en')), findsOneWidget);

      // 【/receiving-code-review I-1 修正】`RadioListTile.groupValue`／
      // `onChanged` 已於本專案改用 `RadioGroup<T>` 祖先包裹（見
      // reading_defaults_screen.dart／commit 5fa3f5bb），選中狀態改斷言
      // 外層 `RadioGroup` 的 `groupValue`，而非逐一讀取個別 tile（個別
      // tile 已不再持有這個值）。
      final group = tester.widget<RadioGroup<AppLocale?>>(
        find.byType(RadioGroup<AppLocale?>),
      );
      expect(group.groupValue, AppLocale.en);
    });

    testWidgets(
        'currentLocaleOverride 為 null 時，開啟選擇器「跟隨系統」呈現選中狀態（/receiving-code-review I-3 修正）',
        (tester) async {
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
      );

      await tester.tap(find.byKey(const Key('settings_language_button')));
      await tester.pumpAndSettle();

      final group = tester.widget<RadioGroup<AppLocale?>>(
        find.byType(RadioGroup<AppLocale?>),
      );
      expect(group.groupValue, isNull);
    });

    testWidgets('選取「正體中文」選項，onLocaleChanged 收到 AppLocale.zhTW 且 Sheet 關閉',
        (tester) async {
      AppLocale? received;
      var receivedCalled = false;
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          currentLocaleOverride: AppLocale.en,
          onLocaleChanged: (locale) {
            receivedCalled = true;
            received = locale;
          },
        ),
      );

      await tester.tap(find.byKey(const Key('settings_language_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_language_option_zh_tw')));
      await tester.pumpAndSettle();

      expect(receivedCalled, isTrue);
      expect(received, AppLocale.zhTW);
      expect(
        find.byKey(const Key('settings_language_option_zh_tw')),
        findsNothing,
        reason: 'Sheet 應已關閉',
      );
    });

    testWidgets('選取「跟隨系統」選項，onLocaleChanged 收到 null', (tester) async {
      AppLocale? received = AppLocale.en;
      var receivedCalled = false;
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          currentLocaleOverride: AppLocale.en,
          onLocaleChanged: (locale) {
            receivedCalled = true;
            received = locale;
          },
        ),
      );

      await tester.tap(find.byKey(const Key('settings_language_button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('settings_language_option_follow_system')),
      );
      await tester.pumpAndSettle();

      expect(receivedCalled, isTrue);
      expect(received, isNull);
    });

    testWidgets(
        '選取「簡體中文」與「English」選項，onLocaleChanged 分別收到對應列舉值（/receiving-code-review I-3 修正：原測試僅覆蓋正體中文／跟隨系統兩個選項）',
        (tester) async {
      AppLocale? received;
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(
          prefsManager: FakeReaderPrefsManager(),
          onLocaleChanged: (locale) => received = locale,
        ),
      );

      await tester.tap(find.byKey(const Key('settings_language_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_language_option_zh_cn')));
      await tester.pumpAndSettle();
      expect(received, AppLocale.zhCN);

      await tester.tap(find.byKey(const Key('settings_language_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_language_option_en')));
      await tester.pumpAndSettle();
      expect(received, AppLocale.en);
    });

    testWidgets('未接上 onLocaleChanged 時，選取選項不崩潰', (tester) async {
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
      );

      await tester.tap(find.byKey(const Key('settings_language_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_language_option_en')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('英文介面下設定畫面主要項目正確以英文渲染', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
      locale: const Locale('en'),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('E-Ink high contrast mode'), findsOneWidget);
    expect(find.text('Font Management'), findsOneWidget);
    expect(find.text('Reading'), findsOneWidget);
    expect(find.text('Reading Defaults'), findsOneWidget);
    expect(find.text('Navigation Zones'), findsOneWidget);
    expect(find.text('Read-Aloud Voice & Speed'), findsOneWidget);
    expect(find.text('Sync & Accounts'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);
    expect(find.text('Linked Cloud Import Accounts'), findsOneWidget);
    expect(find.text('About'), findsNWidgets(2));
    expect(find.text('Reader Console Log'), findsOneWidget);
    expect(find.text('Console Log Interception'), findsOneWidget);
  });

  testWidgets('E-Ink 模式下佈景色點的無障礙標籤正確帶出鎖定提示文字（英文）',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
        prefsManager: FakeReaderPrefsManager(),
        isEinkMode: true,
        currentTheme: AppTheme.dark,
      ),
      locale: const Locale('en'),
    );

    final semantics = tester.getSemantics(
      find.byKey(const Key('settings_theme_dot_light')),
    );
    expect(semantics.label, contains('locked'));
    expect(semantics.label, contains('Dark'));

    handle.dispose();
  });

  testWidgets('字型管理入口把 downloadableFontStore 傳給字型管理畫面（epic-49）', (tester) async {
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
        prefsManager: FakeReaderPrefsManager(),
        customFontsRepository: FakeCustomFontsRepository(),
        downloadableFontStore: FakeDownloadableFontStore(),
      ),
    );

    final entry = find.byKey(const Key('settings_font_management_button'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('font_management_download_sourceHanSans')), findsOneWidget);
  });
}

