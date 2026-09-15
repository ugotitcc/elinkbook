import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
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
import 'package:elinkbook/screens/notes_bottom_sheet.dart';
import 'package:elinkbook/screens/reader_screen.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pumpUntilNotesButtonEnabled(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final finder = find.byKey(const Key('reader_notes_button'));
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 【真機人工驗證清單，本測試無法自動涵蓋】
  // Flutter integration_test 對 PlatformView（AndroidView）內部原生
  // Foliate WebView 的觸控選字手勢與畫面繪製視覺結果不可靠，
  // 故下列項目須另外以真實裝置人工驗證：
  //   1. 原生長按選字手勢觸發 selectionchange，浮動工具列正確顯示。
  //   2. 點擊螢光筆/底線後 Overlayer 繪製樣式正確，純備註淡灰底樣式正常。
  //   3. 點擊既有劃線/備註觸發 show-annotation 事件並開啟編輯/刪除對話框。
  //   4. 直排與橫排切換後，既有劃線位置精確跟隨文字重繪。
  //   5. 簡繁轉換模式切換時，「非等長詞彙」（如「内存」→「記憶體」、
  //      「公共汽車」→「公車」）的劃線/書籤精確字元位置——本檔案下方
  //      新增的測試只涵蓋元素層級 CFI 的例外保護網，未涵蓋字元 offset
  //      映射的精確度，需另外準備已知內容的 fixture 並用真機或
  //      Puppeteer（app/tool/foliate_touch_harness/ 既有依賴，本次
  //      環境未安裝 node_modules 無法當場產生已驗證 CFI）驗證。

  testWidgets('Foliate 流式 EPUB：預先寫入 CFI 劃線＋備註，NotesBottomSheet 正確顯示並可互動',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
    final bookmarksRepository = BookmarksRepository(libraryRepository.database);
    final highlightsRepository = HighlightsRepository(libraryRepository.database);
    final notesRepository = NotesRepository(libraryRepository.database);

    final samplePath = await _stageAssetAsFile(
      'test/fixtures/sample_multi_chapter.epub',
      'foliate_highlights_notes.epub',
    );
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_foliate_highlights_epub',
      title: 'Foliate 劃線測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    const highlightId = 'h_foliate_1';
    await highlightsRepository.insert(const Highlight(
      id: highlightId,
      bookId: 'b_foliate_highlights_epub',
      style: HighlightStyle.highlighterYellow,
      epubLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
      progression: 0.1,
    ));
    const pureNoteId = 'n_foliate_1';
    await notesRepository.insert(const Note(
      id: 'n_foliate_2',
      bookId: 'b_foliate_highlights_epub',
      text: 'Foliate 依附備註',
      epubLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
      progression: 0.1,
      highlightId: highlightId,
    ));
    await notesRepository.insert(const Note(
      id: pureNoteId,
      bookId: 'b_foliate_highlights_epub',
      text: 'Foliate 純備註',
      epubLocatorJson: '{"cfi":"epubcfi(/6/6)","index":1,"fraction":0.3}',
      progression: 0.3,
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_foliate_highlights_epub',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
          isFixedLayout: false,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilNotesButtonEnabled(tester);

    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notes_sheet_annotation_list')), findsOneWidget);
    expect(find.text('Foliate 依附備註'), findsOneWidget);
    expect(find.text('Foliate 純備註'), findsOneWidget);

    await tester.tap(find.text('Foliate 依附備註'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesBottomSheet), findsNothing);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('notes_sheet_annotation_edit_$pureNoteId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('note_edit_dialog_field')), '已編輯 Foliate 純備註');
    await tester.tap(find.byKey(const Key('note_edit_dialog_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('已編輯 Foliate 純備註'), findsOneWidget);
    expect(find.text('Foliate 純備註'), findsNothing);

    final notesAfterEdit = await notesRepository.listByBook('b_foliate_highlights_epub');
    expect(notesAfterEdit.firstWhere((n) => n.id == pureNoteId).text, '已編輯 Foliate 純備註');
  });

  // 審查修正 I-3：本測試使用的既有 fixture（sample_multi_chapter.epub）
  // 與下方插入的劃線 CFI（epubcfi(/6/4)）皆為元素層級／純占位繁體文字，
  // 未包含任何 TWPhrases 非等長詞彙（如「内存」→「記憶體」），也未落在
  // 任何文字節點的字元 offset 上——`isTextNode()` 守衛下，
  // `adjustOffsetForCfi()` 對這個 CFI 完全不會被觸發。本測試只驗證「切換
  // 簡繁模式時，既有標記不會導致例外/畫面崩潰」這個回歸保護網，**不**
  // 驗證非等長詞彙情境下的精確字元位置——那需要一個內容已知、且能被
  // 獨立驗證（例如透過真機或 Puppeteer 產生的真實 CFI）的 fixture，本次
  // 修訂未能在本環境下取得可執行的瀏覽器/Puppeteer 環境驗證出正確字串，
  // 為避免寫入未經驗證、可能誤導的 CFI 常數，改為在下方「真機人工驗證
  // 清單」新增對應項目，如實反映目前的驗證缺口。
  testWidgets(
      'Foliate 流式 EPUB：簡繁轉換模式切換後，既有標記不拋出例外（回歸保護網，epic-42-text-conversion Issue 2）',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
    final highlightsRepository = HighlightsRepository(libraryRepository.database);

    final samplePath = await _stageAssetAsFile(
      'test/fixtures/sample_multi_chapter.epub',
      'foliate_text_conversion_cfi.epub',
    );
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_text_conversion_cfi',
      title: '簡繁轉換 CFI 穩定性測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    const highlightId = 'h_text_conversion_1';
    await highlightsRepository.insert(const Highlight(
      id: highlightId,
      bookId: 'b_text_conversion_cfi',
      style: HighlightStyle.highlighterYellow,
      epubLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
      progression: 0.1,
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_text_conversion_cfi',
          prefsManager: prefsManager,
          highlightsRepository: highlightsRepository,
          isFixedLayout: false,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilNotesButtonEnabled(tester);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    // 開啟版面設定 Bottom Sheet（reader_chrome_layout_button 為既有 Key，
    // 見 app/lib/screens/reader_chrome_bottom_bar.dart），切換到「呈現」
    // 分頁，點選「轉換為繁體」（Key 由 epic-42-text-conversion Issue 1
    // 既有交付，見 plan-issue-1.md Task 7）。
    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, '呈現'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('reader_settings_text_conversion_traditional')),
    );
    await tester.pumpAndSettle();

    // 切換後 WebView 沒有拋出例外，既有劃線仍可透過 NotesBottomSheet
    // 正常顯示——回歸保護網（元素層級 CFI，不涵蓋非等長詞彙字元位置，
    // 見上方測試名稱前的說明）。
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notes_sheet_annotation_list')), findsOneWidget);
  });
}
