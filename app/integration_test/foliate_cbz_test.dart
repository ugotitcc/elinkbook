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

      // RTL 模式下，ZoneAction.previousPage（熱區語意上的「上一頁」，對應
      // 3×3 熱區左側格）應讓 fixed-layout.js 的 renderer.prev()（讀取
      // this.rtl=true）呼叫 #goRight()——實際效果是往書本「邏輯上的下一頁」
      // 前進（日漫翻頁習慣：從封面往後翻是往左滑）。開書當下（無既有閱讀
      // 記錄）一律定位於第一個 section／spread（index 0，見
      // fixed-layout.js #index 初始值 -1、view.init({}) 走預設導覽路徑），
      // 而 index 0 是全書最前端，若 book.dir 覆寫未生效（誤退回 LTR 語意），
      // previousPage 會讓 renderer.prev() 呼叫 #goLeft()、最終落到
      // goToSpread(this.#index - 1, ...)（即 goToSpread(-1, ...)），該函式
      // 對越界 index 直接提早 return、不觸發任何 relocate 事件，位置維持
      // 在 index 0 不動；只有 book.dir 覆寫確實生效、renderer.prev() 正確
      // 委派為 #goRight() 時，位置才會前進到 index 1。因此「index 是否從
      // 0 變動」本身即是方向正確性的明確訊號（非僅驗證 book.dir 覆寫值
      // 傳遞，而是斷言使用者觸發熱區動作後的實際翻頁結果——issues.md
      // Issue 3「單元測試要求」明文要求；reviews/review-issue-3.md
      // Important #2 審查修正）。
      ReaderScreen.triggerZoneAction(readerKey, ZoneAction.previousPage);
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
        reason: 'RTL 模式下「上一頁」熱區應讓位置從開書時的 index 0 前進，'
            '而非停留原地——若停留在 0，代表 book.dir 覆寫未生效、'
            '仍以 LTR 語意處理（見上方註解的完整因果鏈說明）',
      );
    },
  );
}
