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
  // WebView 的觸控事件模擬並不可靠（既有慣例：本專案其餘涉及原生手勢的
  // 功能，如 PDF 長按框選、FXL 三欄熱區，也都未嘗試以 tester.longPress/
  // drag 模擬 WebView 內部選字），故下列項目須另外以真實裝置人工驗證，
  // 不在本檔案自動化範圍：
  //   1. 原生長按+拖曳選字手勢確實觸發 onSelectionChanged、浮動工具列
  //      正確定位於選取範圍上方。
  //   2. 點擊螢光筆三色/底線按鈕，Decorator 疊加的視覺樣式與資料庫寫入
  //      一致；純備註淡灰底視覺可辨識。
  //   3. 點擊既有標記觸發 onAnnotationActivated、編輯/刪除 Dialog 正確
  //      開啟。
  //   4. 直排/橫排切換後，既有劃線視覺仍正確跟隨文字位置（design.md
  //      已知風險，底線樣式尤其需要確認）。
  // 本檔案改為驗證「repository 驅動」的部分：預先透過 Repository 寫入
  // 劃線/備註資料（模擬手勢建立後的最終資料狀態），驗證 NotesBottomSheet
  // 清單顯示、跳轉、編輯、刪除的端到端流程（比照 notes_bookmark_test.dart
  // 既有結構，書籤跳轉本身的原生渲染結果同樣無法在 widget test 層級斷言）。

  testWidgets('EPUB：預先寫入劃線＋依附備註，NotesBottomSheet 正確顯示合併清單並可跳轉/刪除',
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
      'epub_highlights_notes.epub',
    );
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_highlights_epub',
      title: '劃線測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    const highlightId = 'h_epub_1';
    await highlightsRepository.insert(const Highlight(
      id: highlightId,
      bookId: 'b_highlights_epub',
      style: HighlightStyle.highlighterYellow,
      epubLocatorJson: '{"href":"/OEBPS/chapter1.xhtml"}',
      progression: 0.05,
    ));
    const pureNoteId = 'n_epub_1';
    await notesRepository.insert(const Note(
      id: 'n_epub_2',
      bookId: 'b_highlights_epub',
      text: '這段很重要',
      epubLocatorJson: '{"href":"/OEBPS/chapter1.xhtml"}',
      progression: 0.05,
      highlightId: highlightId,
    ));
    await notesRepository.insert(const Note(
      id: pureNoteId,
      bookId: 'b_highlights_epub',
      text: '純備註內容',
      epubLocatorJson: '{"href":"/OEBPS/chapter2.xhtml"}',
      progression: 0.3,
    ));

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: 'b_highlights_epub',
        dependencies: fakeReaderFeatureDependencies(
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
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
    expect(find.text('這段很重要'), findsOneWidget);
    expect(find.text('純備註內容'), findsOneWidget);

    // 點選合併項目後 Bottom Sheet 應關閉（跳轉本身的原生渲染結果無法在
    // widget test 層級斷言，比照既有書籤測試的既定限制）。
    await tester.tap(find.text('這段很重要'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesBottomSheet), findsNothing);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    // 重新開啟，驗證編輯純備註（另一筆，非上面已跳轉刪除的合併項目）文字
    // 持久化生效：Dialog 儲存後清單即時反映新文字，且直接重新查詢
    // repository 確認資料庫確實已更新（不只是 widget tree 上的暫存狀態）。
    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('notes_sheet_annotation_edit_$pureNoteId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('note_edit_dialog_field')), '已編輯的純備註');
    await tester.tap(find.byKey(const Key('note_edit_dialog_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('已編輯的純備註'), findsOneWidget);
    expect(find.text('純備註內容'), findsNothing);
    final notesAfterEdit = await notesRepository.listByBook('b_highlights_epub');
    expect(notesAfterEdit.firstWhere((n) => n.id == pureNoteId).text, '已編輯的純備註');

    // 關閉 Bottom Sheet，重新開啟驗證單筆刪除（劃線+備註一併消失）持久化生效。
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('notes_sheet_annotation_delete_h${highlightId}_n1')));
    await tester.pumpAndSettle();

    expect(await highlightsRepository.listByBook('b_highlights_epub'), isEmpty);
    expect(find.text('這段很重要'), findsNothing);
    // 上一段編輯備註流程已把這筆純備註的文字改為「已編輯的純備註」，
    // 此處延續驗證單筆刪除只影響被刪除的合併項目，不影響這筆仍保留的
    // 純備註。
    expect(find.text('已編輯的純備註'), findsOneWidget);
  });
}
