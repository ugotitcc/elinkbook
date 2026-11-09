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
import 'package:elinkbook/reader/bookmarks_repository.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/highlights_repository.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/notes_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import '../test/support/fake_reader_feature_dependencies.dart';
import '../test/support/pump_localized_widget.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pumpUntilNotesButtonEnabled(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final finder = find.byKey(const Key('reader_chrome_annotations_button'));
    if (finder.evaluate().isNotEmpty &&
        tester.widget<IconButton>(finder).onPressed != null) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：筆記按鈕未轉為可點擊狀態');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 解析頁尾進度文字 `當前頁/總頁數`；格式不符回傳 null。
({int current, int total})? _parseProgress(String? text) {
  final m = RegExp(r'^(\d+)/(\d+)$').firstMatch(text ?? '');
  if (m == null) return null;
  return (current: int.parse(m.group(1)!), total: int.parse(m.group(2)!));
}

/// 等到頁尾顯示「總頁數 > 0」的有效進度（排除初始 `0/0`），回傳當前頁碼。
Future<int> _pumpUntilProgressReady(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (true) {
    final finder = find.byKey(const Key('reader_footer_progress_text'));
    if (finder.evaluate().isNotEmpty) {
      final p = _parseProgress(tester.widget<Text>(finder).data);
      if (p != null && p.total > 0) return p.current;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：頁尾進度未出現總頁數 > 0 的有效值');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 等到當前頁碼嚴格大於 [oldPage]（證明下一頁熱區確實讓閱讀位置前進）。
Future<void> _pumpUntilPageAdvanced(WidgetTester tester, int oldPage) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final finder = find.byKey(const Key('reader_footer_progress_text'));
    if (finder.evaluate().isNotEmpty) {
      final p = _parseProgress(tester.widget<Text>(finder).data);
      if (p != null && p.current > oldPage) return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：頁碼未超過 $oldPage（點擊下一頁熱區沒有讓位置前進）');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TXT 格式：匯入後經 ReaderScreen 開啟，支援點擊熱區翻頁且筆記面板能顯示預先寫入之劃線備註',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await libraryRepository.close();
    });

    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
    final bookmarksRepository = BookmarksRepository(libraryRepository.database);
    final highlightsRepository = HighlightsRepository(libraryRepository.database);
    final notesRepository = NotesRepository(libraryRepository.database);
    final importService = BookImportServiceImpl(repository: libraryRepository);

    final samplePath = await _stageAssetAsFile(
      'test/fixtures/sample_utf8_chapters.txt',
      'windows_smoke_txt_sample.txt',
    );
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final importResult = await importService.importFiles(
      [samplePath],
      displayNames: ['sample_utf8_chapters.txt'],
    );
    expect(importResult.importedBooks, hasLength(1));
    final book = importResult.importedBooks.single;

    const highlightId = 'h_smoke_txt_1';
    await highlightsRepository.insert(Highlight(
      id: highlightId,
      bookId: book.id,
      style: HighlightStyle.highlighterYellow,
      epubLocatorJson: '{"cfi":"epubcfi(/6/2)","index":0,"fraction":0.1}',
      progression: 0.1,
    ));
    await notesRepository.insert(Note(
      id: 'n_smoke_txt_1',
      bookId: book.id,
      text: 'TXT 格式冒煙測試筆記',
      epubLocatorJson: '{"cfi":"epubcfi(/6/2)","index":0,"fraction":0.1}',
      progression: 0.1,
      highlightId: highlightId,
    ));

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: book.filePath,
        bookId: book.id,
        isFixedLayout: book.isFixedLayout,
        dependencies: fakeReaderFeatureDependencies(
          prefsManager: prefsManager,
          libraryRepository: libraryRepository,
          bookmarksRepository: bookmarksRepository,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    // 驗證翻頁
    final initialPage = await _pumpUntilProgressReady(tester);
    await tester.tap(find.byKey(const Key('nav_zone_2')));
    await _pumpUntilPageAdvanced(tester, initialPage);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    // 驗證劃線與筆記面板
    await _pumpUntilNotesButtonEnabled(tester);
    await tester.tap(find.byKey(const Key('reader_chrome_annotations_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notes_sheet_annotation_list')), findsOneWidget);
    expect(find.text('TXT 格式冒煙測試筆記'), findsOneWidget);
  });

  testWidgets('MD 格式：匯入後經 ReaderScreen 開啟，支援點擊熱區翻頁且筆記面板能顯示預先寫入之劃線備註',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await libraryRepository.close();
    });

    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
    final bookmarksRepository = BookmarksRepository(libraryRepository.database);
    final highlightsRepository = HighlightsRepository(libraryRepository.database);
    final notesRepository = NotesRepository(libraryRepository.database);
    final importService = BookImportServiceImpl(repository: libraryRepository);

    final samplePath = await _stageAssetAsFile(
      'test/fixtures/sample.md',
      'windows_smoke_md_sample.md',
    );
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final importResult = await importService.importFiles(
      [samplePath],
      displayNames: ['sample.md'],
    );
    expect(importResult.importedBooks, hasLength(1));
    final book = importResult.importedBooks.single;

    const highlightId = 'h_smoke_md_1';
    await highlightsRepository.insert(Highlight(
      id: highlightId,
      bookId: book.id,
      style: HighlightStyle.highlighterYellow,
      epubLocatorJson: '{"cfi":"epubcfi(/6/2)","index":0,"fraction":0.1}',
      progression: 0.1,
    ));
    await notesRepository.insert(Note(
      id: 'n_smoke_md_1',
      bookId: book.id,
      text: 'MD 格式冒煙測試筆記',
      epubLocatorJson: '{"cfi":"epubcfi(/6/2)","index":0,"fraction":0.1}',
      progression: 0.1,
      highlightId: highlightId,
    ));

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: book.filePath,
        bookId: book.id,
        isFixedLayout: book.isFixedLayout,
        dependencies: fakeReaderFeatureDependencies(
          prefsManager: prefsManager,
          libraryRepository: libraryRepository,
          bookmarksRepository: bookmarksRepository,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    // 驗證翻頁
    final initialPage = await _pumpUntilProgressReady(tester);
    await tester.tap(find.byKey(const Key('nav_zone_2')));
    await _pumpUntilPageAdvanced(tester, initialPage);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    // 驗證劃線與筆記面板
    await _pumpUntilNotesButtonEnabled(tester);
    await tester.tap(find.byKey(const Key('reader_chrome_annotations_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notes_sheet_annotation_list')), findsOneWidget);
    expect(find.text('MD 格式冒煙測試筆記'), findsOneWidget);
  });

  testWidgets('AZW3 格式：匯入後經 ReaderScreen 開啟，支援點擊熱區翻頁且筆記面板能顯示預先寫入之劃線備註',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await libraryRepository.close();
    });

    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
    final bookmarksRepository = BookmarksRepository(libraryRepository.database);
    final highlightsRepository = HighlightsRepository(libraryRepository.database);
    final notesRepository = NotesRepository(libraryRepository.database);
    final importService = BookImportServiceImpl(repository: libraryRepository);

    final samplePath = await _stageAssetAsFile(
      'test/fixtures/sample.azw3',
      'windows_smoke_azw3_sample.azw3',
    );
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final importResult = await importService.importFiles(
      [samplePath],
      displayNames: ['sample.azw3'],
    );
    expect(importResult.importedBooks, hasLength(1));
    final book = importResult.importedBooks.single;

    const highlightId = 'h_smoke_azw3_1';
    await highlightsRepository.insert(Highlight(
      id: highlightId,
      bookId: book.id,
      style: HighlightStyle.highlighterYellow,
      epubLocatorJson: '{"cfi":"epubcfi(/6/2)","index":0,"fraction":0.1}',
      progression: 0.1,
    ));
    await notesRepository.insert(Note(
      id: 'n_smoke_azw3_1',
      bookId: book.id,
      text: 'AZW3 格式冒煙測試筆記',
      epubLocatorJson: '{"cfi":"epubcfi(/6/2)","index":0,"fraction":0.1}',
      progression: 0.1,
      highlightId: highlightId,
    ));

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: book.filePath,
        bookId: book.id,
        isFixedLayout: book.isFixedLayout,
        dependencies: fakeReaderFeatureDependencies(
          prefsManager: prefsManager,
          libraryRepository: libraryRepository,
          bookmarksRepository: bookmarksRepository,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    // 驗證翻頁
    final initialPage = await _pumpUntilProgressReady(tester);
    await tester.tap(find.byKey(const Key('nav_zone_2')));
    await _pumpUntilPageAdvanced(tester, initialPage);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    // 驗證劃線與筆記面板
    await _pumpUntilNotesButtonEnabled(tester);
    await tester.tap(find.byKey(const Key('reader_chrome_annotations_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notes_sheet_annotation_list')), findsOneWidget);
    expect(find.text('AZW3 格式冒煙測試筆記'), findsOneWidget);
  });
}
