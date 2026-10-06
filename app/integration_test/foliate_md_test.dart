import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import '../test/support/fake_reader_feature_dependencies.dart';
import '../test/support/pump_localized_widget.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑
/// （比照 foliate_kf8_test.dart／foliate_cbz_test.dart／foliate_txt_test.dart
/// 既有 helper）。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// 持續 pump，直到載入指示器消失或逾時（比照既有斷言方式）。
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '透過 BookImportService 匯入 MD（含 Frontmatter／巢狀標題／程式碼區塊／'
    '表格）並經 ReaderScreen 開啟，成功渲染無錯誤，Frontmatter 標題正確寫入、'
    '目錄正確產生',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
      addTearDown(() => libraryRepository.close());
      final prefsManager = ReaderPrefsManagerImpl(
        BookReaderPrefsRepository(libraryRepository.database),
        ReadingPositionRepository(libraryRepository.database),
      );
      final importService = BookImportServiceImpl(repository: libraryRepository);

      final samplePath =
          await _stageAssetAsFile('test/fixtures/sample.md', 'foliate_md_integration.md');
      addTearDown(() async {
        final file = File(samplePath);
        if (await file.exists()) await file.delete();
      });

      final result = await importService.importFiles([samplePath], displayNames: ['sample.md']);
      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.single;
      expect(book.title, '真機測試筆記');
      expect(book.isFixedLayout, isFalse);

      final readerKey = GlobalKey<State<ReaderScreen>>();
      await pumpLocalizedWidget(
        tester,
        ReaderScreen(
          key: readerKey,
          filePath: book.filePath,
          bookId: book.id,
          isFixedLayout: book.isFixedLayout,
          dependencies: fakeReaderFeatureDependencies(
            prefsManager: prefsManager,
            libraryRepository: libraryRepository,
          ),
        ),
      );
      await _pumpUntilLoaded(tester);

      expect(find.byKey(const Key('reader_error_text')), findsNothing);

      final toc = await ReaderScreen.loadTableOfContentsForTest(readerKey);
      expect(toc.map((e) => e.title), ['第一章 起源', '第二章 結局']);
    },
  );
}
