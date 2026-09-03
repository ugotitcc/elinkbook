import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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

  testWidgets('點擊設定圖示導航至 SettingsScreen，返回後回到 LibraryScreen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('書架'), findsOneWidget);

    // 使用 tooltip 來明確指定要點擊 AppBar 的設定按鈕（而非「管理分類」chip 的圖示）
    await tester.tap(find.byTooltip('設定'));
    await tester.pumpAndSettle();

    expect(find.text('設定'), findsOneWidget);

    // 點擊 AppBar 的返回按鈕以代替 tester.pageBack()，增加測試強健度
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('書架'), findsOneWidget);
  });
}
