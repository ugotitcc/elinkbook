import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/screens/reader_screen.dart';

// 依 spec.md「測試決策」：ReaderScreen 分派到 EpubReaderView/PdfReaderView
// 後，實際渲染內容存在於原生 PlatformView 之中，一般 flutter test（無真實
// 裝置/模擬器）無法觀察其渲染結果，因此 EPUB/PDF 兩個分支的「確實渲染出
// 內容」驗證改由 integration_test/reader_screen_test.dart 在真實裝置上
// 執行；此處只保留 flutter test 就能可靠驗證的部分：「不支援格式」分支，
// 以及橫直排切換按鈕、換頁模式切換按鈕在 onLayoutResolved 觸發前的初始
// 狀態（按鈕本身的顯示/隱藏、停用狀態不依賴原生回呼，可離線驗證）。
void main() {
  // ReaderScreen 自 Issue 3 起需要 BookReaderPrefsRepository（見
  // docs/adr/0007-reader-screen-book-id-contract.md）。這裡用
  // sqflite_common_ffi 的記憶體資料庫建構一個真實但空的實例——測試情境
  // 本身不涉及版面偏好設定的讀寫，只需要滿足建構參數即可，比照
  // BookReaderPrefsRepository 既有測試慣例（不 mock 資料層）。
  late SqliteLibraryRepository libraryRepository;
  late BookReaderPrefsRepository prefsRepository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    prefsRepository = BookReaderPrefsRepository(libraryRepository.database);
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  testWidgets('不支援格式顯示明確錯誤訊息', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.txt',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    expect(find.text('閱讀器'), findsOneWidget);
    expect(find.text('不支援的檔案格式'), findsOneWidget);
  });

  testWidgets('EPUB 格式顯示橫直排切換按鈕，初始為停用狀態', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    final finder = find.byKey(const Key('reader_writing_mode_toggle'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason: '尚未收到 onLayoutResolved，_writingMode 仍為 null，按鈕應為停用狀態',
    );
  });

  testWidgets('EPUB 格式顯示換頁模式切換按鈕，初始為停用狀態且提示切換為捲動',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    final finder = find.byKey(const Key('reader_page_turn_mode_toggle'));
    expect(finder, findsOneWidget);
    final button = tester.widget<IconButton>(finder);
    expect(
      button.onPressed,
      isNull,
      reason: '尚未收到 onLayoutResolved，應與橫直排切換按鈕共用同一個停用條件',
    );
    expect(
      button.tooltip,
      '切換為捲動模式',
      reason: '_pageTurnMode 初始值為 PageTurnMode.paginated，按鈕應顯示切換目標（捲動模式）',
    );
  });

  testWidgets('PDF 格式不顯示橫直排切換按鈕與換頁模式切換按鈕', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    expect(find.byKey(const Key('reader_writing_mode_toggle')), findsNothing);
    expect(find.byKey(const Key('reader_page_turn_mode_toggle')), findsNothing);
  });
}
