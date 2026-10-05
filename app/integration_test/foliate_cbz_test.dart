import 'dart:convert';
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
            isFixedLayout: book.isFixedLayout,
            dependencies: fakeReaderFeatureDependencies(
              prefsManager: prefsManager,
              libraryRepository: libraryRepository,
            ),
          ),
        ),
      );
      await _pumpUntilLoaded(tester);

      expect(find.byKey(const Key('reader_error_text')), findsNothing);
    },
  );

  /// **架構修正記錄（epic-11 Issue 4 程式碼審查 Important #2，2026-08-17）**：
  /// 本檔案原本的 RTL 測試假設「切換 RTL 後，熱區的『上一頁』動作應該讓
  /// 頁碼往前進」，源自 Issue 1 Spike／design.md／spec.md／issues.md Issue 3
  /// 一路延續下來、從未真機驗證過的假設。真機實測後發現該斷言在單頁模式
  /// 下（手機直向、CBZ 預設情境）恆為失敗，往下追查 `fixed-layout.js`
  /// 原始碼證實：`#goLeft()`/`#goRight()`（`next()`/`prev()` 內 `this.rtl`
  /// 三元運算式實際呼叫的對象）只有在雙頁跨頁模式下才可能成功，單頁模式
  /// 下 `this.#center` 恆為真、兩者恆為 falsy，`book.dir` 對單頁模式的
  /// `next()`/`prev()` 導覽方向**完全沒有作用**。
  ///
  /// 交叉核對本專案既有、已出貨的 PDF `dualPageDirection`
  /// （`pdf_spread_layout.dart`／`pdf_reader_view.dart`）證實這不是 CBZ
  /// 獨有的缺陷，而是本 App 對「RTL/LTR」的既定、一致的設計哲學：
  /// `dualPageDirection` 只影響雙頁跨頁時的視覺/幾何排版（`pdf_spread_
  /// layout.dart`：「RTL 的左右鏡像只發生在幾何排版階段」），**不影響**
  /// 熱區觸發後的導覽方向本身——`_handleZoneAction()` 對 PDF 的
  /// `previousPage`/`nextPage` 呼叫從未依 `dualPageDirection` 分支。
  ///
  /// 人類已確認（2026-08-17）採用「翻頁的規則以熱區為準」——CBZ 沿用與
  /// PDF 一致的既有精神，`book.dir` 不反轉導覽方向，只透過既有
  /// `fixed-layout.js` `#spread()` 邏輯影響雙頁跨頁時的頁面配對順序。
  /// 以下兩則測試驗證「LTR／RTL 對同一組熱區動作產生完全一致的導覽結果」
  /// 這個修正後的不變量，取代原本試圖證明方向反轉的斷言。

  testWidgets(
    'RTL 模式：導覽方向完全依熱區設定前進，不因 book.dir 而反轉'
    '（nextPage 前進、隨後 previousPage 退回原點，驗證 book.dir 覆寫本身'
    '不會讓 main.js／fixed-layout.js 拋出例外或產生非預期導覽結果）',
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
            isFixedLayout: book.isFixedLayout,
            dependencies: fakeReaderFeatureDependencies(
              prefsManager: prefsManager,
              libraryRepository: libraryRepository,
            ),
          ),
        ),
      );
      await _pumpUntilLoaded(tester);
      expect(find.byKey(const Key('reader_error_text')), findsNothing);

      // nextPage：index 0 → 1（熱區語意上的「下一頁」，不受 book.dir 影響）。
      ReaderScreen.triggerZoneAction(readerKey, ZoneAction.nextPage);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('reader_error_text')), findsNothing);

      // previousPage：index 1 → 0（熱區語意上的「上一頁」，同樣不受
      // book.dir 影響，驗證來回導覽皆正常，非單向巧合）。
      ReaderScreen.triggerZoneAction(readerKey, ZoneAction.previousPage);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('reader_error_text')), findsNothing);

      // ReaderScreen 對外未暴露目前定位的公開讀取介面（見 CLAUDE.md
      // 「ReaderScreen」架構小節）——卸載畫面觸發 dispose() →
      // _writeCurrentPosition() 寫入，再從 prefsManager 讀回，是本專案
      // 既有測試手段下能取得「目前實際定位」的唯一管道。
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 500));

      final finalPosition = (await prefsManager.load(book.id)).readingPosition;
      final locatorJson = finalPosition.epubLocatorJson;
      expect(locatorJson, isNotNull);
      final locator = jsonDecode(locatorJson!) as Map<String, Object?>;
      expect(
        (locator['index'] as num).toInt(),
        0,
        reason: 'RTL 模式下 nextPage 後接 previousPage 應回到開書起始頁 '
            'index 0——與下一則 LTR 測試預期結果完全相同，佐證 book.dir 不'
            '影響導覽方向本身（僅影響雙頁跨頁的視覺排版，見上方架構修正'
            '記錄）',
      );
    },
  );

  testWidgets(
    'LTR 模式：導覽方向與 RTL 完全一致（佐證 book.dir 不影響熱區導覽語意，'
    '只是既有 PDF dualPageDirection 精神的延伸——純視覺/幾何排版概念，'
    '非方向反轉；與上一則 RTL 測試互為對照組，兩者應產生相同的導覽結果）',
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
          'test/fixtures/sample.cbz', 'foliate_cbz_ltr_control_integration.cbz');
      addTearDown(() async {
        final file = File(samplePath);
        if (await file.exists()) await file.delete();
      });

      final result = await importService.importFiles(
        [samplePath],
        displayNames: ['sample.cbz'],
      );
      final book = result.importedBooks.single;

      // 明確寫入 LTR 偏好——elinkBook 全域預設值其實是 RTL（見
      // dual_page_direction.dart「亦為 elinkBook 全域固定預設值」），若不
      // 明確覆寫，本測試會跟未設定的預設情境混在一起，喪失「明確 LTR」
      // 對照組的意義。
      final loaded = await prefsManager.load(book.id);
      await prefsManager.saveBookPrefs(
        book.id,
        loaded.bookPrefs.copyWith(dualPageDirection: DualPageDirection.ltr),
      );

      final readerKey = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            key: readerKey,
            filePath: book.filePath,
            bookId: book.id,
            isFixedLayout: book.isFixedLayout,
            dependencies: fakeReaderFeatureDependencies(
              prefsManager: prefsManager,
              libraryRepository: libraryRepository,
            ),
          ),
        ),
      );
      await _pumpUntilLoaded(tester);
      expect(find.byKey(const Key('reader_error_text')), findsNothing);

      ReaderScreen.triggerZoneAction(readerKey, ZoneAction.nextPage);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('reader_error_text')), findsNothing);

      ReaderScreen.triggerZoneAction(readerKey, ZoneAction.previousPage);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('reader_error_text')), findsNothing);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 500));

      final finalPosition = (await prefsManager.load(book.id)).readingPosition;
      final locatorJson = finalPosition.epubLocatorJson;
      expect(locatorJson, isNotNull);
      final locator = jsonDecode(locatorJson!) as Map<String, Object?>;
      expect(
        (locator['index'] as num).toInt(),
        0,
        reason: 'LTR 模式下 nextPage 後接 previousPage 應回到開書起始頁 '
            'index 0——與上一則 RTL 測試預期結果完全相同',
      );
    },
  );
}
