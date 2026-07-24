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
import 'package:elinkbook/reader/epub_character_count_repository.dart';
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

  testWidgets('Foliate 流式 EPUB：預先寫入 CFI 劃線＋備註，NotesBottomSheet 正確顯示並可互動',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
      EpubCharacterCountRepository(libraryRepository.database),
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

    final highlightId = await highlightsRepository.insert(const Highlight(
      bookId: 'b_foliate_highlights_epub',
      style: HighlightStyle.highlighterYellow,
      epubLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
      progression: 0.1,
    ));
    await notesRepository.insert(Note(
      bookId: 'b_foliate_highlights_epub',
      text: 'Foliate 依附備註',
      epubLocatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
      progression: 0.1,
      highlightId: highlightId,
    ));
    final pureNoteId = await notesRepository.insert(const Note(
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
}
