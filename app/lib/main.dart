import 'package:flutter/material.dart';

import 'library/book_import_service.dart';
import 'library/book_import_service_impl.dart';
import 'library/library_repository.dart';
import 'library/sqlite_library_repository.dart';
import 'screens/library_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dbPath = await defaultLibraryDatabasePath();
  final repository = await SqliteLibraryRepository.open(dbPath);
  final importService = BookImportServiceImpl(repository: repository);
  runApp(
    ElinkBookApp(repository: repository, importService: importService),
  );
}

/// elinkBook App 根元件。
class ElinkBookApp extends StatelessWidget {
  final LibraryRepository repository;
  final BookImportService importService;

  const ElinkBookApp({
    super.key,
    required this.repository,
    required this.importService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'elinkBook',
      home: LibraryScreen(repository: repository, importService: importService),
    );
  }
}
