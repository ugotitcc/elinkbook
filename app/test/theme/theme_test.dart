import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/main.dart';
import 'package:elinkbook/theme/app_theme_preferences.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';

void main() {
  late SqliteLibraryRepository sqliteRepo;
  late BookReaderPrefsRepository prefsRepository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    sqliteRepo = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    prefsRepository = BookReaderPrefsRepository(sqliteRepo.database);
  });

  tearDown(() async {
    await sqliteRepo.close();
  });

  testWidgets('ElinkBookApp 依 AppThemePreferences 套用正確主題 (非 E-Ink 模式)',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_theme': 'dark',
      'app_eink_mode': false,
    });

    final prefs = AppThemePreferences();
    final theme = await prefs.loadTheme();
    final eink = await prefs.loadEinkMode();

    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsRepository: prefsRepository,
        initialTheme: theme,
        initialEinkMode: eink,
      ),
    );
    await tester.pumpAndSettle();

    final materialApp =
        tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme?.brightness, Brightness.dark);
  });

  testWidgets('ElinkBookApp 依 AppThemePreferences 套用正確主題 (E-Ink 高對比模式)',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_theme': 'dark',
      'app_eink_mode': true,
    });

    final prefs = AppThemePreferences();
    final theme = await prefs.loadTheme();
    final eink = await prefs.loadEinkMode();

    await tester.pumpWidget(
      ElinkBookApp(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsRepository: prefsRepository,
        initialTheme: theme,
        initialEinkMode: eink,
      ),
    );
    await tester.pumpAndSettle();

    final materialApp =
        tester.widget<MaterialApp>(find.byType(MaterialApp));
    // E-Ink 高對比模式下，不論原本主題為何，背景皆為純白
    expect(materialApp.theme?.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
    // brightness 為 light（高對比黑白用 light scheme）
    expect(materialApp.theme?.brightness, Brightness.light);
  });
}
