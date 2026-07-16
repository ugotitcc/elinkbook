import 'package:flutter/material.dart';

import 'library/book_import_service.dart';
import 'library/book_import_service_impl.dart';
import 'library/library_repository.dart';
import 'library/sqlite_library_repository.dart';
import 'reader/book_reader_prefs_repository.dart';
import 'reader/epub_character_count_repository.dart';
import 'reader/reader_prefs_manager.dart';
import 'reader/reader_prefs_manager_impl.dart';
import 'reader/reading_position_repository.dart';
import 'screens/library_screen.dart';
import 'theme/app_theme.dart';
import 'theme/app_theme_data.dart';
import 'theme/app_theme_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themePreferences = AppThemePreferences();
  final initialTheme = await themePreferences.loadTheme();
  final initialEinkMode = await themePreferences.loadEinkMode();

  final dbPath = await defaultLibraryDatabasePath();
  final repository = await SqliteLibraryRepository.open(dbPath);
  final importService = BookImportServiceImpl(repository: repository);
  // BookReaderPrefsRepository 必須與 repository 共用同一個 Database 連線
  // （book_reader_prefs 的外鍵約束要求，見 epic-3-fonts-layout Issue 1 spec.md）。
  // 在這裡（repository 尚未收窄為 LibraryRepository 介面前）取用
  // SqliteLibraryRepository 具象型別才有的 .database getter（見
  // docs/adr/0007-reader-screen-book-id-contract.md）。
  final prefsRepository = BookReaderPrefsRepository(repository.database);
  final prefsManager = ReaderPrefsManagerImpl(
    prefsRepository,
    ReadingPositionRepository(repository.database),
    EpubCharacterCountRepository(repository.database),
  );
  runApp(
    ElinkBookApp(
      repository: repository,
      importService: importService,
      prefsManager: prefsManager,
      initialTheme: initialTheme,
      initialEinkMode: initialEinkMode,
      themePreferences: themePreferences,
    ),
  );
}

/// elinkBook App 根元件。啟動時接受從 main 傳入之 [initialTheme] 與
/// [initialEinkMode]（解決開機閃白屏與狀態競爭問題，見 review 意見）。
class ElinkBookApp extends StatefulWidget {
  final LibraryRepository repository;
  final BookImportService importService;
  final ReaderPrefsManager prefsManager;
  final AppThemePreferences themePreferences;
  final AppTheme initialTheme;
  final bool initialEinkMode;

  ElinkBookApp({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsManager,
    this.initialTheme = AppTheme.light,
    this.initialEinkMode = false,
    AppThemePreferences? themePreferences,
  }) : themePreferences = themePreferences ?? AppThemePreferences();

  @override
  State<ElinkBookApp> createState() => _ElinkBookAppState();
}

class _ElinkBookAppState extends State<ElinkBookApp> {
  late AppTheme _theme;
  late bool _isEinkMode;

  @override
  void initState() {
    super.initState();
    _theme = widget.initialTheme;
    _isEinkMode = widget.initialEinkMode;
  }

  void _handleThemeChanged(AppTheme theme) {
    setState(() => _theme = theme);
    widget.themePreferences.saveTheme(theme);
  }

  void _handleEinkModeChanged(bool enabled) {
    setState(() => _isEinkMode = enabled);
    widget.themePreferences.saveEinkMode(enabled);
  }

  @override
  Widget build(BuildContext context) {
    final themeData = resolveThemeData(
      theme: _theme,
      isEinkMode: _isEinkMode,
    );
    return MaterialApp(
      title: 'elinkBook',
      theme: themeData,
      home: LibraryScreen(
        repository: widget.repository,
        importService: widget.importService,
        prefsManager: widget.prefsManager,
        currentTheme: _theme,
        isEinkMode: _isEinkMode,
        onThemeChanged: _handleThemeChanged,
        onEinkModeChanged: _handleEinkModeChanged,
      ),
    );
  }
}
