import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager.dart';
import 'package:elinkbook/screens/library_screen.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

import 'support/fake_book_import_service.dart';
import 'support/fake_library_repository.dart';
import 'support/fake_reader_prefs_manager.dart';

void main() {
  late SqliteLibraryRepository libraryRepository;
  late ReaderPrefsManager prefsManager;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    prefsManager = FakeReaderPrefsManager();
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  testWidgets(
    '點擊設定圖示呼叫 onNavigateToSettings callback（epic-36 三目的地導覽取代 '
    'Navigator.push，見 reviews/review-issues.md I-1）',
    (tester) async {
      var settingsRequested = 0;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: LibraryScreen(
            repository: FakeLibraryRepository(),
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
            onNavigateToSettings: () => settingsRequested++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('書架'), findsOneWidget);

      await tester.tap(find.byKey(const Key('library_settings_button')));
      await tester.pumpAndSettle();

      expect(settingsRequested, 1);
      // 三目的地導覽下設定畫面由 AdaptiveShellScaffold 的 IndexedStack
      // 承接，不再是 Navigator.push 推入的新路由——這裡只驗證 LibraryScreen
      // 端呼叫了 callback，跨分頁 IndexedStack 切換與參數轉送行為由
      // adaptive_shell_scaffold_test.dart（Task 5）驗證。
      expect(find.text('書架'), findsOneWidget);
    },
  );
}
