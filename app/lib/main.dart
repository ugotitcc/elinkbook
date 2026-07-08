import 'package:flutter/material.dart';

import 'library/book_import_service.dart';
import 'library/book_import_service_impl.dart';
import 'library/library_repository.dart';
import 'library/sqlite_library_repository.dart';
import 'reader/book_reader_prefs_repository.dart';
import 'screens/library_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dbPath = await defaultLibraryDatabasePath();
  final repository = await SqliteLibraryRepository.open(dbPath);
  final importService = BookImportServiceImpl(repository: repository);
  // BookReaderPrefsRepository 必須與 repository 共用同一個 Database 連線
  // （book_reader_prefs 的外鍵約束要求，見 epic-3-fonts-layout Issue 1 spec.md）。
  // 在這裡（repository 尚未收窄為 LibraryRepository 介面前）取用
  // SqliteLibraryRepository 具象型別才有的 .database getter（見
  // docs/adr/0007-reader-screen-book-id-contract.md）。
  final prefsRepository = BookReaderPrefsRepository(repository.database);
  runApp(
    ElinkBookApp(
      repository: repository,
      importService: importService,
      prefsRepository: prefsRepository,
    ),
  );
}

/// elinkBook App 根元件。
class ElinkBookApp extends StatelessWidget {
  final LibraryRepository repository;
  final BookImportService importService;
  final BookReaderPrefsRepository prefsRepository;

  const ElinkBookApp({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'elinkBook',
      home: LibraryScreen(
        repository: repository,
        importService: importService,
        prefsRepository: prefsRepository,
      ),
    );
  }
}
