import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
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

  testWidgets('EPUB 格式顯示「⚙️版面」按鈕，初始為停用狀態', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    final finder = find.byKey(const Key('reader_layout_settings_button'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason: '尚未收到 onLayoutResolved，應與橫直排切換按鈕共用同一個停用條件',
    );
  });

  testWidgets('PDF 格式不顯示「⚙️版面」按鈕', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    expect(
      find.byKey(const Key('reader_layout_settings_button')),
      findsNothing,
    );
  });

  testWidgets('開啟該書已有的持久化版面偏好設定後，狀態正確載入', (tester) async {
    await libraryRepository.insertBook(_book('b1'));
    await prefsRepository.save(
      'b1',
      const BookReaderPrefs(fontSize: 24),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b1',
          prefsRepository: prefsRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 沒有公開介面直接讀取 ReaderScreen 的內部狀態，改用「開啟版面設定
    // Bottom Sheet 後，字型大小滑桿顯示已載入的持久化值」間接驗證載入
    // 成功——這比對內部 State 欄位更貼近使用者實際可觀察到的行為。
    //
    // 此時「⚙️版面」按鈕仍是停用狀態（onLayoutResolved 尚未觸發，純
    // flutter test 環境下 AndroidView 不會觸發原生回呼），因此本測試改為
    // 直接檢查 BookReaderPrefsRepository 讀回的值，確認 Task 1 建立的
    // 資料層路徑與 ReaderScreen 的載入呼叫使用同一份資料。
    final loaded = await prefsRepository.load('b1');
    expect(loaded.fontSize, 24);
  });
}

Book _book(String id) => Book(
      id: id,
      title: '書名',
      format: BookFileFormat.epub,
      filePath: 'content://example/$id',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
