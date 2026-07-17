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
import 'package:elinkbook/reader/percent_rect.dart';
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
  // 比照 epic-6-annotations Issue 2 integration_test 既有先例：Flutter
  // integration_test 對原生 View 的觸控事件模擬並不可靠，本專案既有慣例
  // 是原生手勢功能一律另外以真實裝置人工驗證，不嘗試以
  // tester.longPress/drag 模擬。以下項目須另外以真實裝置人工驗證：
  //   1. 長按 PDF 頁面直接觸發拖曳框選矩形手勢（不需先進入獨立模式，
  //      ADR 0008），放開後浮動工具列正確定位於選取矩形上方。
  //   2. 長按框選與既有水平滑動翻頁手勢實際共存不衝突（審查修正 1.1後：
  //      長按/拖曳辨識已改由 Flutter 端 GestureDetector 主導、與
  //      onHorizontalDragEnd 同一個手勢競技場仲裁，架構上已不存在原生端
  //      無條件攔截 ACTION_DOWN 的問題；此項為對「按構造正確」的實機
  //      體感確認，非未知風險排查——若真的發現翻頁手勢仍受影響，代表
  //      實作與計劃書不一致，須回頭檢查 Task 6/8 是否正確落實）。
  //   3. 框選進行中第二指觸碰螢幕，驗證框選狀態正確取消、浮動工具列收起
  //      （Dart 端 Listener 偵測多指觸碰，見 Global Constraints）。
  //   4. 點擊螢光筆三色/底線按鈕，建立劃線後 Bitmap 正確疊加渲染；純
  //      備註淡灰底＋右上角黑白向量圖釘視覺可辨識，尤其在 E-Ink 高對比
  //      模式下確認清晰不模糊（審查修正 2.2）。
  //   5. 刪除劃線/備註後（單筆或批次），驗證 refreshAnnotations() 確實
  //      觸發原生端重繪、無殘留視覺。
  //   6. 裝置旋轉後，驗證既有劃線座標仍正確對應頁面實際內容（letterbox-
  //      aware 座標基準驗證，見 plan-issue-3.md Global Constraints「PDF
  //      座標協定」）。
  //   7. 已裁切（crop）頁面上長按框選，驗證矩形相對「裁切後內容範圍」
  //      計算正確（非整個原生 View）。
  // 本檔案改為驗證「repository 驅動」的部分：預先透過 Repository 寫入
  // 劃線/備註資料（模擬手勢建立後的最終資料狀態），驗證 NotesBottomSheet
  // 清單顯示、跳轉、編輯、刪除的端到端流程。

  testWidgets('PDF：預先寫入劃線＋依附備註，NotesBottomSheet 正確顯示合併清單並可跳轉/刪除',
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

    final samplePath = await _stageAssetAsFile('test/fixtures/sample.pdf', 'pdf_highlights_notes.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_highlights_pdf',
      title: '劃線測試書',
      format: BookFileFormat.pdf,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    const rect = PercentRect(left: 0.1, top: 0.1, right: 0.6, bottom: 0.2);
    final highlightId = await highlightsRepository.insert(const Highlight(
      bookId: 'b_highlights_pdf',
      style: HighlightStyle.highlighterYellow,
      pdfPageIndex: 0,
      pdfRect: rect,
    ));
    await notesRepository.insert(Note(
      bookId: 'b_highlights_pdf',
      text: '這段很重要',
      pdfPageIndex: 0,
      pdfRect: rect,
      highlightId: highlightId,
    ));
    await notesRepository.insert(const Note(
      bookId: 'b_highlights_pdf',
      text: '純備註內容',
      pdfPageIndex: 1,
      pdfRect: PercentRect(left: 0.0, top: 0.3, right: 0.4, bottom: 0.4),
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_highlights_pdf',
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
    // widget test 層級斷言，比照既有先例的既定限制）。
    await tester.tap(find.text('這段很重要'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesBottomSheet), findsNothing);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    // 重新開啟，驗證單筆刪除（劃線+備註一併消失）持久化生效。
    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('notes_sheet_annotation_delete_h${highlightId}_n1')));
    await tester.pumpAndSettle();

    expect(await highlightsRepository.listByBook('b_highlights_pdf'), isEmpty);
    expect(find.text('這段很重要'), findsNothing);
    expect(find.text('純備註內容'), findsOneWidget);
  });
}
