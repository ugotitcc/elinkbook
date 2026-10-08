import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/main.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_preferences.dart';
import 'package:elinkbook/screens/settings_scaffold.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/pump_localized_widget.dart';
import '../support/fake_reader_feature_dependencies.dart';
import '../support/fake_sync_dependencies.dart';

void main() {
  late SqliteLibraryRepository sqliteRepo;
  late ReaderPrefsManager prefsManager;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    sqliteRepo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    prefsManager = FakeReaderPrefsManager();
  });

  tearDown(() async {
    await sqliteRepo.close();
  });

  testWidgets('MaterialApp 設定 themeAnimationDuration 為 Duration.zero'
      '（DESIGN.md §18 零動畫轉場：切換主題／E-Ink 不應有交叉淡出動畫，'
      '避免電子紙殘影）', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ElinkBookApp(
        readerFeatures: fakeReaderFeatureDependencies(
          libraryRepository: FakeLibraryRepository(),
          bookImportService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
        sync: fakeSyncDependencies(),
      ),
    );
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeAnimationDuration, Duration.zero);
  });

  testWidgets('ElinkBookApp 依 AppThemePreferences 套用正確主題 (非 E-Ink 模式)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'app_theme': 'dark',
      'app_eink_mode': false,
    });

    final prefs = AppThemePreferences();
    final theme = await prefs.loadTheme();
    final eink = await prefs.loadEinkMode();

    await tester.pumpWidget(
      ElinkBookApp(
        initialTheme: theme,
        initialEinkMode: eink,
        readerFeatures: fakeReaderFeatureDependencies(
          libraryRepository: FakeLibraryRepository(),
          bookImportService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
        sync: fakeSyncDependencies(),
      ),
    );
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme?.brightness, Brightness.dark);
  });

  testWidgets('ElinkBookApp 依 AppThemePreferences 套用正確主題 (E-Ink 高對比模式)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'app_theme': 'dark',
      'app_eink_mode': true,
    });

    final prefs = AppThemePreferences();
    final theme = await prefs.loadTheme();
    final eink = await prefs.loadEinkMode();

    await tester.pumpWidget(
      ElinkBookApp(
        initialTheme: theme,
        initialEinkMode: eink,
        readerFeatures: fakeReaderFeatureDependencies(
          libraryRepository: FakeLibraryRepository(),
          bookImportService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
        sync: fakeSyncDependencies(),
      ),
    );
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    // E-Ink 高對比模式下，不論原本主題為何，背景皆為純白
    expect(materialApp.theme?.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
    // brightness 為 light（高對比黑白用 light scheme）
    expect(materialApp.theme?.brightness, Brightness.light);
  });

  testWidgets(
    'SettingsScreen「佈景」主題切換按鈕點擊更新 preferences（原位於 LibraryScreen AppBar，'
    '因 epic-18 工具列溢位修復搬移至此）',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      AppTheme? receivedTheme;

      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(
          currentTheme: AppTheme.light,
          isEinkMode: false,
          onThemeChanged: (theme) => receivedTheme = theme,
          readerFeatures: fakeReaderFeatureDependencies(
            prefsManager: prefsManager,
          ),
          sync: fakeSyncDependencies(),
        ),
      );
      await tester.pumpAndSettle();

      // 點擊 dark 主題圓點
      await tester.tap(find.byKey(const Key('settings_theme_dot_dark')));
      await tester.pumpAndSettle();

      expect(receivedTheme, AppTheme.dark);
    },
  );

  testWidgets(
    'SettingsScreen E-Ink 切換開關點擊更新 preferences（原位於 LibraryScreen AppBar，'
    '因 epic-36 AppBar 收斂搬移至此）',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      bool? receivedEinkMode;

      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(
          currentTheme: AppTheme.light,
          isEinkMode: false,
          onEinkModeChanged: (enabled) => receivedEinkMode = enabled,
          readerFeatures: fakeReaderFeatureDependencies(
            prefsManager: prefsManager,
          ),
          sync: fakeSyncDependencies(),
        ),
      );
      await tester.pumpAndSettle();

      // 點擊 E-Ink 開關
      await tester.tap(find.byKey(const Key('settings_eink_mode_switch')));
      await tester.pumpAndSettle();

      expect(receivedEinkMode, true);
    },
  );
}
