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
/// （比照 foliate_kf8_test.dart／foliate_cbz_test.dart 既有 helper）。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// 持續 pump，直到載入指示器消失或逾時（比照既有 foliate_kf8_test.dart／
/// foliate_cbz_test.dart 既有斷言方式）。
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<
    ({
      SqliteLibraryRepository repository,
      ReaderPrefsManagerImpl prefsManager,
      BookImportServiceImpl importService,
    })> _setUpServices() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
  final prefsManager = ReaderPrefsManagerImpl(
    BookReaderPrefsRepository(repository.database),
    ReadingPositionRepository(repository.database),
  );
  return (
    repository: repository,
    prefsManager: prefsManager,
    importService: BookImportServiceImpl(repository: repository),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '透過 BookImportService 匯入 Big5 編碼 TXT 並經 ReaderScreen 開啟，'
    '成功渲染無錯誤（驗證編碼偵測＋EPUB 合成的完整真機端到端流程）',
    (tester) async {
      final services = await _setUpServices();
      addTearDown(() => services.repository.close());

      final samplePath =
          await _stageAssetAsFile('test/fixtures/sample_big5.txt', 'foliate_txt_big5_integration.txt');
      addTearDown(() async {
        final file = File(samplePath);
        if (await file.exists()) await file.delete();
      });

      final result = await services.importService.importFiles(
        [samplePath],
        displayNames: ['sample_big5.txt'],
      );
      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.single;
      expect(book.isFixedLayout, isFalse);

      await pumpLocalizedWidget(
        tester,
        ReaderScreen(
          filePath: book.filePath,
          bookId: book.id,
          isFixedLayout: book.isFixedLayout,
          dependencies: fakeReaderFeatureDependencies(
            prefsManager: services.prefsManager,
            libraryRepository: services.repository,
          ),
        ),
      );
      await _pumpUntilLoaded(tester);

      expect(find.byKey(const Key('reader_error_text')), findsNothing);
    },
  );

  testWidgets(
    '透過 BookImportService 匯入 UTF-8 編碼、含章節標題的 TXT 並經 ReaderScreen 開啟，'
    '成功渲染無錯誤，目錄正確產生',
    (tester) async {
      final services = await _setUpServices();
      addTearDown(() => services.repository.close());

      final samplePath = await _stageAssetAsFile(
          'test/fixtures/sample_utf8_chapters.txt', 'foliate_txt_utf8_integration.txt');
      addTearDown(() async {
        final file = File(samplePath);
        if (await file.exists()) await file.delete();
      });

      final result = await services.importService.importFiles(
        [samplePath],
        displayNames: ['sample_utf8_chapters.txt'],
      );
      final book = result.importedBooks.single;

      final readerKey = GlobalKey<State<ReaderScreen>>();
      await pumpLocalizedWidget(
        tester,
        ReaderScreen(
          key: readerKey,
          filePath: book.filePath,
          bookId: book.id,
          isFixedLayout: book.isFixedLayout,
          dependencies: fakeReaderFeatureDependencies(
            prefsManager: services.prefsManager,
            libraryRepository: services.repository,
          ),
        ),
      );
      await _pumpUntilLoaded(tester);

      expect(find.byKey(const Key('reader_error_text')), findsNothing);

      final toc = await ReaderScreen.loadTableOfContentsForTest(readerKey);
      expect(toc.map((e) => e.title), ['第一章 起源', '第二章 冒險', '第三章 結局']);
    },
  );

  testWidgets(
    '大型 TXT（約 6MB，無規範章節標記）匯入與開書流暢，不因超大 DOM section 崩潰',
    (tester) async {
      final services = await _setUpServices();
      addTearDown(() => services.repository.close());

      // 產生約 6MB、無章節標記的合成內容（每行約 60 bytes，約 100000 行），
      // 驗證 chunkByByteSize() 的分塊防護在真機端到端流程中確實生效
      // （比照既有 foliate_epub_reader_view_test.dart
      // _buildLargeSyntheticEpub() 大型檔案測試模式，運行期產生、不提交
      // 進版控）。
      final tempDir = await getTemporaryDirectory();
      final largeFile = File('${tempDir.path}/foliate_txt_large_integration.txt');
      final sink = largeFile.openWrite();
      for (var i = 0; i < 100000; i++) {
        sink.writeln('第 $i 行內容，用於測試大型 TXT 檔案的分塊防護機制是否正常運作。');
      }
      await sink.close();
      addTearDown(() async {
        if (await largeFile.exists()) await largeFile.delete();
      });

      final result = await services.importService.importFiles(
        [largeFile.path],
        displayNames: ['large_novel.txt'],
      );
      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.single;

      await pumpLocalizedWidget(
        tester,
        ReaderScreen(
          filePath: book.filePath,
          bookId: book.id,
          isFixedLayout: book.isFixedLayout,
          dependencies: fakeReaderFeatureDependencies(
            prefsManager: services.prefsManager,
            libraryRepository: services.repository,
          ),
        ),
      );
      await _pumpUntilLoaded(tester);

      expect(find.byKey(const Key('reader_error_text')), findsNothing);
    },
  );
}
