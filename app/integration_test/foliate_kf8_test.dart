import 'dart:async';
import 'dart:io';
import '../test/support/fake_reader_feature_dependencies.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/reader_screen.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// 持續 pump，直到載入指示器消失或逾時（比照既有
/// `reading_position_test.dart` 的既有斷言方式）。
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FoliateReaderView 直接開啟真實 AZW3 檔案，成功渲染無錯誤', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.azw3', 'foliate_sample.azw3');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateReaderView(
          filePath: samplePath,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 15));
    await tester.pumpAndSettle();

    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');
  });

  testWidgets(
    '透過 BookImportService 匯入 AZW3 並經 ReaderScreen 開啟，成功渲染無錯誤'
    '（epic-11 Issue 2 程式碼審查 I1 迴歸測試——原版本繞過匯入管線與 ReaderScreen 分派邏輯，'
    '未能覆蓋 C1/C2 實際發生的路徑）',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final libraryRepository =
          await SqliteLibraryRepository.open(inMemoryDatabasePath);
      addTearDown(() => libraryRepository.close());
      final prefsManager = ReaderPrefsManagerImpl(
        BookReaderPrefsRepository(libraryRepository.database),
        ReadingPositionRepository(libraryRepository.database),
      );
      final importService = BookImportServiceImpl(repository: libraryRepository);

      final samplePath = await _stageAssetAsFile(
          'test/fixtures/sample.azw3', 'foliate_kf8_import_integration.azw3');
      addTearDown(() async {
        final file = File(samplePath);
        if (await file.exists()) await file.delete();
      });

      // 真正走匯入管線（本機路徑，`content://` scheme 的隨機存取限制已由
      // 純 Dart 單元測試涵蓋，見 kf8_metadata_test.dart「content:// URI
      // 支援」群組），驗證 book_import_service_impl.dart 寫入的
      // Book.isFixedLayout 能讓 ReaderScreen 正確分派、不卡在載入畫面
      // （C2 迴歸驗證）。
      final result = await importService.importFiles(
        [samplePath],
        displayNames: ['sample.azw3'],
      );
      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.single;
      expect(book.title, contains('Time Machine'));

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(filePath: book.filePath, bookId: book.id, dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager, libraryRepository: libraryRepository)),
        ),
      );
      await _pumpUntilLoaded(tester);

      expect(find.byKey(const Key('reader_error_text')), findsNothing);
    },
  );
}
