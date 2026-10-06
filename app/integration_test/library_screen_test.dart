import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/library_screen.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import '../test/support/fake_reader_feature_dependencies.dart';
import '../test/support/pump_localized_widget.dart';

const _metadataChannel = MethodChannel('elinkbook/book_metadata');

/// 持續 pump，直到 [condition] 成立或逾時。與 Issue 4/5 既有 integration_test
/// 採用相同手法：ReaderScreen 對外只有 filePath 一個建構參數，
/// onPageRendered/onError 為內部實作細節，用 Key 觀察渲染狀態是否轉換。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  Duration step = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時（$timeout）：條件未成立');
    }
    await tester.pump(step);
  }
}

bool _loadingIndicatorGone() =>
    find.byKey(const Key('reader_loading_indicator')).evaluate().isEmpty;

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File(p.join(tempDir.path, fileName));
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '從書架點擊一本透過 BookImportService 匯入的真實書籍項目，導航至 ReaderScreen 且內容成功渲染',
    (tester) async {
      final tempDir = await getTemporaryDirectory();
      final uniqueSuffix = DateTime.now().microsecondsSinceEpoch;
      final dbPath = p.join(
        tempDir.path,
        'library_screen_test_$uniqueSuffix.db',
      );
      final coversDir = Directory(
        p.join(tempDir.path, 'library_screen_test_covers_$uniqueSuffix'),
      );
      await coversDir.create(recursive: true);
      final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub',
        'library_screen_test_sample.epub',
      );

      final repository = await SqliteLibraryRepository.open(dbPath);
      final importService = BookImportServiceImpl(
        repository: repository,
        coversDirectory: coversDir,
      );

      addTearDown(() async {
        await repository.close();
        final dbFile = File(dbPath);
        if (await dbFile.exists()) await dbFile.delete();
        if (await coversDir.exists()) await coversDir.delete(recursive: true);
        final sampleFile = File(samplePath);
        if (await sampleFile.exists()) await sampleFile.delete();
      });

      // 模擬真實匯入流程：createTestContentUri 透過 FileProvider 模擬 SAF 授權
      // 回傳的 content:// URI（與 Issue 4 的 content_uri_acceptance_test.dart
      // 相同手法），BookImportServiceImpl.importFiles() 內部會自行呼叫
      // takePersistableUriPermission，不需在測試中另外呼叫。
      final contentUri = await _metadataChannel.invokeMethod<String>(
        'createTestContentUri',
        {'path': samplePath},
      );
      expect(contentUri, isNotNull);
      expect(
        contentUri!.startsWith('content://'),
        isTrue,
        reason: '必須是真正的 content:// URI，而非 file://',
      );

      final importResult = await importService.importFiles([contentUri]);
      final imported = importResult.importedBooks;
      expect(imported, hasLength(1));
      final importedBook = imported.single;

      await pumpLocalizedWidget(
        tester,
        LibraryScreen(
          repository: repository,
          importService: importService,
          // Issue 11 起進入閱讀器需要完整的閱讀器功能依賴（單元測試同樣傳這個）
          readerFeatureRepositories: completeLegacyReaderFeatures(
            bookImportService: importService,
          ),
          syncDependencies: completeLegacySyncDependencies(),
          prefsManager: ReaderPrefsManagerImpl(
            BookReaderPrefsRepository(repository.database),
            ReadingPositionRepository(repository.database),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('book_item_${importedBook.id}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('閱讀器'), findsOneWidget);

      // 先確認載入指示器真的存在，才能保證下面「等它消失」是有意義的等待，
      // 而不是 Key 被改名/移除後，condition 從一開始就成立、測試沒等待就
      // silently 通過（與 reader_screen_test.dart 採用相同手法）。
      expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

      // 10 秒逾時：Readium 需非同步解析 EPUB 套件結構並啟動 WebView 導覽器，
      // 與 Issue 4/5 其餘 integration_test 採用相同的逾時時間。
      await _pumpUntil(
        tester,
        _loadingIndicatorGone,
        timeout: const Duration(seconds: 10),
      );

      expect(
        find.byKey(const Key('reader_error_text')),
        findsNothing,
        reason: '應觸發 onPageRendered（載入指示器消失且無錯誤訊息），但畫面顯示了錯誤',
      );
    },
  );

  testWidgets('真實匯入一本流式 EPUB 後點開，由 FoliateReaderView 成功渲染出內容', (tester) async {
    final tempDir = await getTemporaryDirectory();
    final uniqueSuffix = DateTime.now().microsecondsSinceEpoch;
    final dbPath = p.join(
      tempDir.path,
      'library_screen_foliate_test_$uniqueSuffix.db',
    );
    final coversDir = Directory(
      p.join(tempDir.path, 'library_screen_foliate_test_covers_$uniqueSuffix'),
    );
    await coversDir.create(recursive: true);
    final samplePath = await _stageAssetAsFile(
      'test/fixtures/sample.epub',
      'library_screen_foliate_test_sample.epub',
    );

    final repository = await SqliteLibraryRepository.open(dbPath);
    final importService = BookImportServiceImpl(
      repository: repository,
      coversDirectory: coversDir,
    );

    addTearDown(() async {
      await repository.close();
      final dbFile = File(dbPath);
      if (await dbFile.exists()) await dbFile.delete();
      if (await coversDir.exists()) await coversDir.delete(recursive: true);
      final sampleFile = File(samplePath);
      if (await sampleFile.exists()) await sampleFile.delete();
    });

    final contentUri = await _metadataChannel.invokeMethod<String>(
      'createTestContentUri',
      {'path': samplePath},
    );
    final importResult = await importService.importFiles([contentUri!]);
    final imported = importResult.importedBooks;
    expect(imported, hasLength(1));
    final importedBook = imported.single;
    // sample.epub 是流式（reflowable）素材，Issue 2 的 extractMetadata 應
    // 已判斷 isFixedLayout 為 false——先核實這個前提，若不成立代表測試素材
    // 或 Issue 2 判斷邏輯有問題，而非本 Issue 的分派邏輯有問題。
    expect(
      importedBook.isFixedLayout,
      isFalse,
      reason: 'sample.epub 應為流式素材，isFixedLayout 應由 Issue 2 判斷為 false',
    );

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
        repository: repository,
        importService: importService,
        // Issue 11 起進入閱讀器需要完整的閱讀器功能依賴（單元測試同樣傳這個）
        readerFeatureRepositories: completeLegacyReaderFeatures(
          bookImportService: importService,
        ),
        syncDependencies: completeLegacySyncDependencies(),
        prefsManager: ReaderPrefsManagerImpl(
          BookReaderPrefsRepository(repository.database),
          ReadingPositionRepository(repository.database),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('book_item_${importedBook.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );

    expect(
      find.byKey(const Key('reader_error_text')),
      findsNothing,
      reason: '應觸發 onPageRendered，但畫面顯示了錯誤',
    );
    expect(
      find.byType(FoliateReaderView),
      findsOneWidget,
      reason: '流式 EPUB 應由 FoliateReaderView 渲染',
    );
  });

  testWidgets(
    '真實匯入一本 FXL（固定版面）EPUB 後點開，同樣由 FoliateReaderView 成功渲染出內容'
    '（Epic 20 Issue 2 起 FXL 與流式皆統一走 FoliateReaderView，不再分派到已刪除的 EpubReaderView）',
    (tester) async {
      final tempDir = await getTemporaryDirectory();
      final uniqueSuffix = DateTime.now().microsecondsSinceEpoch;
      final dbPath = p.join(
        tempDir.path,
        'library_screen_fxl_test_$uniqueSuffix.db',
      );
      final coversDir = Directory(
        p.join(tempDir.path, 'library_screen_fxl_test_covers_$uniqueSuffix'),
      );
      await coversDir.create(recursive: true);
      final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_fixed_layout.epub',
        'library_screen_fxl_test_sample.epub',
      );

      final repository = await SqliteLibraryRepository.open(dbPath);
      final importService = BookImportServiceImpl(
        repository: repository,
        coversDirectory: coversDir,
      );

      addTearDown(() async {
        await repository.close();
        final dbFile = File(dbPath);
        if (await dbFile.exists()) await dbFile.delete();
        if (await coversDir.exists()) await coversDir.delete(recursive: true);
        final sampleFile = File(samplePath);
        if (await sampleFile.exists()) await sampleFile.delete();
      });

      final contentUri = await _metadataChannel.invokeMethod<String>(
        'createTestContentUri',
        {'path': samplePath},
      );
      final importResult = await importService.importFiles([contentUri!]);
      final imported = importResult.importedBooks;
      expect(imported, hasLength(1));
      final importedBook = imported.single;
      expect(
        importedBook.isFixedLayout,
        isTrue,
        reason: 'sample_fixed_layout.epub 應為 FXL 素材，isFixedLayout 應為 true',
      );

      await pumpLocalizedWidget(
        tester,
        LibraryScreen(
          repository: repository,
          importService: importService,
          // Issue 11 起進入閱讀器需要完整的閱讀器功能依賴（單元測試同樣傳這個）
          readerFeatureRepositories: completeLegacyReaderFeatures(
            bookImportService: importService,
          ),
          syncDependencies: completeLegacySyncDependencies(),
          prefsManager: ReaderPrefsManagerImpl(
            BookReaderPrefsRepository(repository.database),
            ReadingPositionRepository(repository.database),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('book_item_${importedBook.id}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await _pumpUntil(
        tester,
        _loadingIndicatorGone,
        timeout: const Duration(seconds: 10),
      );

      expect(find.byKey(const Key('reader_error_text')), findsNothing);
      expect(
        find.byType(FoliateReaderView),
        findsOneWidget,
        reason: 'FXL 書籍自 Epic 20 Issue 2 起同樣由 FoliateReaderView 渲染',
      );
    },
  );
}
