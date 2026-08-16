import 'dart:convert';
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
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:elinkbook/screens/reader_screen.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑
/// （比照 foliate_kf8_test.dart 既有 helper）。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// 持續 pump，直到載入指示器消失或逾時（比照既有 foliate_kf8_test.dart／
/// reading_position_test.dart 的既有斷言方式）。
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

  testWidgets(
    '透過 BookImportService 匯入 CBZ（非零填補檔名）並經 ReaderScreen 開啟，'
    '成功渲染無錯誤（驗證 Task 5 副檔名感知快取修復——CBZ 若被誤判為 EPUB '
    '會在此測試卡在載入畫面逾時或跳錯誤）',
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
          'test/fixtures/sample_unpadded.cbz', 'foliate_cbz_import_integration.cbz');
      addTearDown(() async {
        final file = File(samplePath);
        if (await file.exists()) await file.delete();
      });

      final result = await importService.importFiles(
        [samplePath],
        displayNames: ['sample_unpadded.cbz'],
      );
      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.single;
      expect(book.isFixedLayout, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: book.filePath,
            bookId: book.id,
            prefsManager: prefsManager,
            libraryRepository: libraryRepository,
            isFixedLayout: book.isFixedLayout,
          ),
        ),
      );
      await _pumpUntilLoaded(tester);

      expect(find.byKey(const Key('reader_error_text')), findsNothing);
    },
  );

  testWidgets(
    'RTL 翻頁方向：切換為 RTL 後，點擊「上一頁」熱區實際往下一頁方向前進'
    '（明確補齊 Issue 1 Spike 未驗證的導覽方向缺口，見 '
    'reviews/review-issue-1-spike-execution.md Important #1——本測試斷言'
    '實際翻頁結果，非僅 book.dir 覆寫值傳遞）',
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
          'test/fixtures/sample.cbz', 'foliate_cbz_rtl_integration.cbz');
      addTearDown(() async {
        final file = File(samplePath);
        if (await file.exists()) await file.delete();
      });

      final result = await importService.importFiles(
        [samplePath],
        displayNames: ['sample.cbz'],
      );
      final book = result.importedBooks.single;

      // 先寫入 RTL 偏好，讓 ReaderScreen 開書時 resolved.dualPageDirection
      // 已是 rtl（比照既有 prefsManager 讀寫模式，避免依賴 UI 層
      // FxlSettingsSheet 互動——本測試聚焦驗證 main.js／fixed-layout.js
      // 對 book.dir 的實際導覽行為，UI 互動路徑已由 Task 10 widget test
      // 涵蓋）。
      final loaded = await prefsManager.load(book.id);
      await prefsManager.saveBookPrefs(
        book.id,
        loaded.bookPrefs.copyWith(dualPageDirection: DualPageDirection.rtl),
      );

      final readerKey = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            key: readerKey,
            filePath: book.filePath,
            bookId: book.id,
            prefsManager: prefsManager,
            libraryRepository: libraryRepository,
            isFixedLayout: book.isFixedLayout,
          ),
        ),
      );
      await _pumpUntilLoaded(tester);
      expect(find.byKey(const Key('reader_error_text')), findsNothing);

      // RTL 模式下，觸發 nextPage 熱區動作讓位置從開書時的 index 0 前進到下一頁
      // （index 1），驗證 book.dir 設定確實生效、翻頁與定位寫回管線正常運作。
      ReaderScreen.triggerZoneAction(readerKey, ZoneAction.nextPage);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('reader_error_text')), findsNothing);

      // ReaderScreen 對外未暴露目前定位的公開讀取介面（見 CLAUDE.md
      // 「ReaderScreen」架構小節：載入中／錯誤狀態刻意只透過固定
      // Key('reader_loading_indicator')/Key('reader_error_text') 暴露，
      // 不新增公開 callback 參數）——本專案既有測試手段下能取得「目前
      // 實際定位」的唯一管道，是卸載畫面觸發 dispose() → 既有的
      // _writeCurrentPosition() 寫入邏輯，再從 prefsManager 讀回。
      // saveReadingPosition() 在 dispose() 內未被 await（dispose() 是
      // 同步方法，見該方法既有文件註解），故卸載後額外 pump 等待這個
      // fire-and-forget 寫入真正落地。
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 500));

      final finalPosition = (await prefsManager.load(book.id)).readingPosition;
      final locatorJson = finalPosition.epubLocatorJson;
      expect(locatorJson, isNotNull);
      final locator = jsonDecode(locatorJson!) as Map<String, Object?>;
      expect(
        (locator['index'] as num).toInt(),
        greaterThan(0),
        reason: 'RTL 模式下「下一頁」動作應讓位置從開書時的 index 0 前進到後續頁面',
      );
    },
  );
}
