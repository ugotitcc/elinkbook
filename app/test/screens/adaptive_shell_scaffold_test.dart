import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/reader/reader_prefs_manager.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/adaptive_shell_scaffold.dart';
import 'package:elinkbook/screens/library_screen.dart';
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/screens/settings_scaffold.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_custom_fonts_repository.dart';
import '../support/fake_tts_provider.dart';

void main() {
  late ReaderPrefsManager prefsManager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefsManager = FakeReaderPrefsManager();
  });

  Widget buildApp() {
    return MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: AdaptiveShellScaffold(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
      ),
    );
  }

  testWidgets('三個目的地圖示切換後 IndexedStack.index 正確且畫面對應正確', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);

    await tester.tap(find.byKey(const Key('library_source_button')));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);
    expect(find.text('來源'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sources_settings_button')));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 2);
    expect(find.text('設定'), findsOneWidget);
  });

  testWidgets('切換目的地不重建 LibraryScreen 的 State（狀態保留）', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    final stateBefore = tester.state(find.byType(LibraryScreen));

    await tester.tap(find.byKey(const Key('library_source_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sources_library_button')));
    await tester.pumpAndSettle();

    final stateAfter = tester.state(find.byType(LibraryScreen));
    expect(identical(stateBefore, stateAfter), isTrue);
  });

  testWidgets('切回書架分頁時觸發 refreshSignal，書架重新載入資料', (tester) async {
    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: AdaptiveShellScaffold(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 新增一本書到 repository 記憶體資料，模擬「來源」畫面完成匯入
    await repository.insertBook(
      Book(
        id: 'new_book',
        title: '後補書',
        format: BookFileFormat.epub,
        filePath: 'content://example/new_book.epub',
        source: BookSource.local,
        createTime: DateTime.now(),
        lastReadTime: DateTime.now(),
      ),
    );

    await tester.tap(find.byKey(const Key('library_source_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sources_library_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_new_book')), findsOneWidget);
  });

  testWidgets('非書架分頁時系統返回鍵優先切回書架', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_source_button')));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
  });

  testWidgets('SettingsScreen 收到 customFontsRepository/onEinkModeChanged 轉送（取代原 library_screen_test.dart 的 2 則測試）', (tester) async {
    final customFontsRepository = FakeCustomFontsRepository();
    bool? toggledValue;
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: AdaptiveShellScaffold(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            customFontsRepository: customFontsRepository,
          ),
          themeDependencies: LibraryThemeDependencies(
            onEinkModeChanged: (val) => toggledValue = val,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();

    final settingsScreen =
        tester.widget<SettingsScaffold>(find.byType(SettingsScaffold));
    expect(settingsScreen.customFontsRepository, customFontsRepository);
    expect(settingsScreen.onEinkModeChanged, isNotNull);

    await tester.tap(find.byKey(const Key('settings_eink_mode_switch')));
    await tester.pumpAndSettle();

    expect(toggledValue, isTrue);
  });

  testWidgets('上層 themeDependencies 更新後，已切換過去的 SettingsScreen 收到最新 isEinkMode（審查報告 C-1 回歸測試：子畫面不得在 initState 快取）', (tester) async {
    Widget buildWithEink(bool isEinkMode) {
      return MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: isEinkMode),
        home: AdaptiveShellScaffold(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          themeDependencies: LibraryThemeDependencies(isEinkMode: isEinkMode),
        ),
      );
    }

    await tester.pumpWidget(buildWithEink(false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();

    var settingsScreen =
        tester.widget<SettingsScaffold>(find.byType(SettingsScaffold));
    expect(settingsScreen.isEinkMode, isFalse);

    // 重新 pumpWidget 同一個 AdaptiveShellScaffold（同一個 widget tree
    // 位置），但 themeDependencies.isEinkMode 已改變——模擬使用者在別處
    // 切換 E-Ink 模式後，main.dart 的 setState() 觸發整棵 widget tree
    // 帶著新的 themeDependencies 重新 build()。
    await tester.pumpWidget(buildWithEink(true));
    await tester.pumpAndSettle();

    settingsScreen = tester.widget<SettingsScaffold>(find.byType(SettingsScaffold));
    expect(
      settingsScreen.isEinkMode,
      isTrue,
      reason: '若 AdaptiveShellScaffold 把子畫面快取在 initState()，這裡會維持 false，'
          '因為快取的 SettingsScreen 建構當下的 isEinkMode 已經是舊值',
    );
  });

  testWidgets('在設定分頁點擊「書架」圖示切回書架分頁', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 2);

    await tester.tap(find.byKey(const Key('settings_library_button')));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
  });

  testWidgets('在設定分頁點擊「來源」圖示切到來源分頁', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 2);

    await tester.tap(find.byKey(const Key('settings_source_button')));
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);
  });

  testWidgets('SettingsScaffold 收到 readerFeatureRepositories.ttsProvider 轉送', (tester) async {
    final ttsProvider = FakeTtsProvider();
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: AdaptiveShellScaffold(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories:
              LibraryReaderFeatureRepositories(ttsProvider: ttsProvider),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_settings_button')));
    await tester.pumpAndSettle();

    final settingsScaffold =
        tester.widget<SettingsScaffold>(find.byType(SettingsScaffold));
    expect(settingsScaffold.ttsProvider, ttsProvider);
  });
}
