import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmark_position_context.dart';
import 'package:elinkbook/reader/annotation_list_item.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/screens/notes_bottom_sheet.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import '../support/fake_bookmarks_repository.dart';
import '../support/fake_highlights_repository.dart';
import '../support/fake_notes_repository.dart';
import '../support/fake_path_provider_platform.dart';
import '../support/fake_share_platform.dart';

Future<void> _pumpSheet(
  WidgetTester tester, {
  required FakeBookmarksRepository repository,
  String bookId = 'b1',
  String bookTitle = '測試書籍',
  String? bookAuthor,
  double bookProgress = 0.0,
  BookmarkPositionContext currentPosition = const BookmarkPositionContext(),
  ValueChanged<Bookmark>? onBookmarkSelected,
  FakeHighlightsRepository? highlightsRepository,
  FakeNotesRepository? notesRepository,
  ValueChanged<AnnotationListItem>? onAnnotationSelected,
  VoidCallback? onAnnotationsChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: Scaffold(
        body: NotesBottomSheet(
          bookId: bookId,
          bookTitle: bookTitle,
          bookAuthor: bookAuthor,
          bookProgress: bookProgress,
          bookmarksRepository: repository,
          currentPosition: currentPosition,
          onBookmarkSelected: onBookmarkSelected ?? (_) {},
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
          onAnnotationSelected: onAnnotationSelected,
          onAnnotationsChanged: onAnnotationsChanged,
        ),
      ),
    ),
  );
  await tester.pump(); // 讓 initState 觸發的 _loadBookmarks() 非同步結果套用
}

void main() {
  testWidgets('開啟後顯示兩個分頁籤，預設在書籤分頁', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(tester, repository: repository);

    expect(find.byKey(const Key('notes_sheet_tab_bookmarks')), findsOneWidget);
    expect(
      find.byKey(const Key('notes_sheet_tab_annotations')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('notes_sheet_bookmark_list')), findsOneWidget);
  });

  testWidgets('切至「劃線與備註」分頁顯示空狀態佔位符', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(tester, repository: repository);

    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('notes_sheet_annotations_placeholder')),
      findsOneWidget,
    );
  });

  testWidgets('書籤分頁正確依位置順序顯示清單', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository.insert(
      const Bookmark(id: 'bm1', bookId: 'b1', name: 'C', progression: 0.8),
    );
    await repository.insert(
      const Bookmark(id: 'bm2', bookId: 'b1', name: 'A', progression: 0.1),
    );
    await _pumpSheet(tester, repository: repository);

    final listFinder = find.byKey(const Key('notes_sheet_bookmark_list'));
    final listTiles = tester.widgetList<ListTile>(
      find.descendant(of: listFinder, matching: find.byType(ListTile)),
    );
    final titles = listTiles.map((t) => (t.title as Text).data).toList();
    expect(titles, ['A', 'C']);
  });

  testWidgets('點選書籤項目觸發 onBookmarkSelected', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository.insert(
      const Bookmark(id: 'bm3', bookId: 'b1', name: '第一章', progression: 0.1),
    );
    Bookmark? selected;
    await _pumpSheet(
      tester,
      repository: repository,
      onBookmarkSelected: (b) => selected = b,
    );

    await tester.tap(find.text('第一章'));
    await tester.pump();

    expect(selected?.name, '第一章');
  });

  testWidgets('尚未有書籤時，toggle 按鈕顯示「加入此頁書籤」', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(
      tester,
      repository: repository,
      currentPosition: const BookmarkPositionContext(pdfPageIndex: 4),
    );

    expect(find.text('加入此頁書籤'), findsOneWidget);
  });

  testWidgets('點擊 toggle 按鈕後新增書籤，清單即時反映', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(
      tester,
      repository: repository,
      currentPosition: const BookmarkPositionContext(pdfPageIndex: 4),
    );

    await tester.tap(find.byKey(const Key('notes_sheet_bookmark_toggle')));
    await tester.pump();

    expect(find.text('第 5 頁'), findsOneWidget);
    expect(find.text('已加入此頁書籤'), findsOneWidget);
  });

  testWidgets('已有書籤時再次點擊 toggle 按鈕，移除該筆書籤', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository.insert(
      const Bookmark(id: 'bm4', bookId: 'b1', name: '第 5 頁', pdfPageIndex: 4),
    );
    await _pumpSheet(
      tester,
      repository: repository,
      currentPosition: const BookmarkPositionContext(pdfPageIndex: 4),
    );

    expect(find.text('已加入此頁書籤'), findsOneWidget);
    await tester.tap(find.byKey(const Key('notes_sheet_bookmark_toggle')));
    await tester.pump();

    expect(find.text('第 5 頁'), findsNothing);
    expect(find.text('加入此頁書籤'), findsOneWidget);
  });

  testWidgets('EPUB 情境下 toggle 依 epubLocatorJson 精確比對', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository.insert(
      const Bookmark(
        id: 'bm5',
        bookId: 'b1',
        name: '別處',
        epubLocatorJson: '{"href":"/other.xhtml"}',
      ),
    );
    await _pumpSheet(
      tester,
      repository: repository,
      currentPosition: const BookmarkPositionContext(
        epubLocatorJson: '{"href":"/c1.xhtml"}',
        progression: 0.1,
      ),
    );

    expect(
      find.text('加入此頁書籤'),
      findsOneWidget,
      reason: '不同 locatorJson 不應視為同一位置',
    );
  });

  testWidgets('重新命名書籤後清單顯示新名稱', (tester) async {
    final repository = FakeBookmarksRepository();
    const id = 'bm6';
    await repository.insert(
      const Bookmark(id: id, bookId: 'b1', name: '舊名稱', progression: 0.1),
    );
    await _pumpSheet(tester, repository: repository);

    await tester.tap(find.byKey(Key('notes_sheet_bookmark_rename_$id')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('notes_sheet_rename_field')),
      '新名稱',
    );
    await tester.tap(find.byKey(const Key('notes_sheet_rename_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('新名稱'), findsOneWidget);
    expect(find.text('舊名稱'), findsNothing);
  });

  testWidgets('單筆刪除書籤後清單即時消失，不需確認', (tester) async {
    final repository = FakeBookmarksRepository();
    const id = 'bm7';
    await repository.insert(
      const Bookmark(id: id, bookId: 'b1', name: '待刪除', progression: 0.1),
    );
    await _pumpSheet(tester, repository: repository);

    await tester.tap(find.byKey(Key('notes_sheet_bookmark_delete_$id')));
    await tester.pump();

    expect(find.text('待刪除'), findsNothing);
  });

  testWidgets('批次刪除按鈕在無書籤時停用', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(tester, repository: repository);

    final button = tester.widget<IconButton>(
      find.byKey(const Key('notes_sheet_delete_all_bookmarks')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('批次刪除顯示確認對話框，取消不刪除', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository.insert(
      const Bookmark(id: 'bm8', bookId: 'b1', name: 'A', progression: 0.1),
    );
    await repository.insert(
      const Bookmark(id: 'bm9', bookId: 'b1', name: 'B', progression: 0.5),
    );
    await _pumpSheet(tester, repository: repository);

    await tester.tap(find.byKey(const Key('notes_sheet_delete_all_bookmarks')));
    await tester.pumpAndSettle();
    expect(find.textContaining('共 2 筆'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('批次刪除確認後清單清空', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository.insert(
      const Bookmark(id: 'bm10', bookId: 'b1', name: 'A', progression: 0.1),
    );
    await repository.insert(
      const Bookmark(id: 'bm11', bookId: 'b1', name: 'B', progression: 0.5),
    );
    await _pumpSheet(tester, repository: repository);

    await tester.tap(find.byKey(const Key('notes_sheet_delete_all_bookmarks')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('notes_sheet_delete_all_bookmarks_confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsNothing);
  });

  testWidgets(
    '未提供 highlightsRepository／notesRepository 時，維持 Issue 1 既有空狀態佔位符',
    (tester) async {
      final repository = FakeBookmarksRepository();
      await _pumpSheet(tester, repository: repository);

      await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('notes_sheet_annotations_placeholder')),
        findsOneWidget,
      );
    },
  );

  testWidgets('提供兩個 repository 後，「劃線與備註」分頁依位置排序顯示合併清單', (tester) async {
    final repository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    const highlightId = 'h7';
    await highlightsRepository.insert(
      const Highlight(
        id: highlightId,
        bookId: 'b1',
        style: HighlightStyle.highlighterPink,
        progression: 0.2,
      ),
    );
    await notesRepository.insert(
      Note(
        id: 'n2',
        bookId: 'b1',
        text: '依附備註',
        progression: 0.2,
        highlightId: highlightId,
      ),
    );
    await notesRepository.insert(
      const Note(id: 'n3', bookId: 'b1', text: '純備註', progression: 0.5),
    );

    await _pumpSheet(
      tester,
      repository: repository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
    );
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('notes_sheet_annotation_list')),
      findsOneWidget,
    );
    expect(find.text('螢光筆（粉）'), findsOneWidget);
    expect(find.text('依附備註'), findsOneWidget);
    expect(find.text('純備註'), findsOneWidget);
  });

  testWidgets('點選合併項目觸發 onAnnotationSelected', (tester) async {
    final repository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    await highlightsRepository.insert(
      const Highlight(
        id: 'h1',
        bookId: 'b1',
        style: HighlightStyle.underline,
        progression: 0.1,
      ),
    );
    AnnotationListItem? selected;

    await _pumpSheet(
      tester,
      repository: repository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
      onAnnotationSelected: (item) => selected = item,
    );
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('底線'));

    expect(selected?.highlight?.style, HighlightStyle.underline);
  });

  testWidgets('編輯備註文字後清單即時反映，且觸發 onAnnotationsChanged', (tester) async {
    final repository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    const noteId = 'n4';
    await notesRepository.insert(
      const Note(id: noteId, bookId: 'b1', text: '舊文字', progression: 0.1),
    );
    var changedCount = 0;

    await _pumpSheet(
      tester,
      repository: repository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
      onAnnotationsChanged: () => changedCount++,
    );
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('notes_sheet_annotation_edit_$noteId')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('note_edit_dialog_field')),
      '新文字',
    );
    await tester.tap(find.byKey(const Key('note_edit_dialog_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('新文字'), findsOneWidget);
    expect(changedCount, greaterThan(0));
  });

  testWidgets('單筆刪除合併項目時，劃線與備註一併刪除', (tester) async {
    final repository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    const highlightId = 'h2';
    await highlightsRepository.insert(
      const Highlight(
        id: highlightId,
        bookId: 'b1',
        style: HighlightStyle.underline,
        progression: 0.1,
      ),
    );
    await notesRepository.insert(
      Note(
        id: 'n6',
        bookId: 'b1',
        text: '依附備註',
        progression: 0.1,
        highlightId: highlightId,
      ),
    );

    await _pumpSheet(
      tester,
      repository: repository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
    );
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    final itemKey = 'h${highlightId}_nn6';
    await tester.tap(find.byKey(Key('notes_sheet_annotation_delete_$itemKey')));
    await tester.pumpAndSettle();

    expect(await highlightsRepository.listByBook('b1'), isEmpty);
    expect(await notesRepository.listByBook('b1'), isEmpty);
    expect(
      find.byKey(const Key('notes_sheet_annotations_placeholder')),
      findsOneWidget,
    );
  });

  testWidgets('批次刪除所有劃線：確認對話框顯示正確筆數，確認後劃線清單清空', (tester) async {
    final repository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    await highlightsRepository.insert(
      const Highlight(
        id: 'h3',
        bookId: 'b1',
        style: HighlightStyle.underline,
        progression: 0.1,
      ),
    );
    await highlightsRepository.insert(
      const Highlight(
        id: 'h4',
        bookId: 'b1',
        style: HighlightStyle.underline,
        progression: 0.2,
      ),
    );

    await _pumpSheet(
      tester,
      repository: repository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
    );
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('notes_sheet_delete_all_highlights')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('2'), findsWidgets);

    await tester.tap(
      find.byKey(const Key('notes_sheet_delete_all_highlights_confirm')),
    );
    await tester.pumpAndSettle();

    expect(await highlightsRepository.listByBook('b1'), isEmpty);
    expect(
      find.byKey(const Key('notes_sheet_annotations_placeholder')),
      findsOneWidget,
    );
  });

  testWidgets('已退化的純備註（highlightId 已為 null，模擬真實資料庫 FK ON DELETE SET NULL '
      'cascade 之後的狀態——真正的 cascade 行為本身由 Task 4 對真實 SQLite 的 '
      'notes_repository_test.dart 驗證，本測試不重複模擬那段邏輯，Fake 之間也刻意'
      '不互相協調）：批次刪除所有劃線後，這筆早已獨立存在的純備註不受影響，仍正確'
      '顯示在清單中', (tester) async {
    final repository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    await highlightsRepository.insert(
      const Highlight(
        id: 'h5',
        bookId: 'b1',
        style: HighlightStyle.underline,
        progression: 0.1,
      ),
    );
    // 直接建構「已退化」狀態（highlightId: null），而非先建立一筆連結中的
    // 備註再期待 Fake 自動模擬 cascade——兩個 Fake 刻意保持互不協調（見
    // Global Constraints／FakeNotesRepository 既有 KDoc），避免在測試替身
    // 裡重新實作一份可能與真實資料庫語意逐漸失準的 FK cascade 邏輯。
    await notesRepository.insert(
      const Note(
        id: 'n5',
        bookId: 'b1',
        text: '已退化的純備註',
        progression: 0.3,
        highlightId: null,
      ),
    );

    await _pumpSheet(
      tester,
      repository: repository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
    );
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('notes_sheet_delete_all_highlights')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('notes_sheet_delete_all_highlights_confirm')),
    );
    await tester.pumpAndSettle();

    expect(await highlightsRepository.listByBook('b1'), isEmpty);
    expect(find.text('已退化的純備註'), findsOneWidget);
    expect(
      find.byKey(const Key('notes_sheet_annotations_placeholder')),
      findsNothing,
    );
  });

  testWidgets('批次刪除所有備註：取消不刪除，確認後備註消失、劃線不受影響', (tester) async {
    final repository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    await highlightsRepository.insert(
      const Highlight(
        id: 'h6',
        bookId: 'b1',
        style: HighlightStyle.underline,
        progression: 0.1,
      ),
    );
    await notesRepository.insert(
      const Note(id: 'n1', bookId: 'b1', text: '純備註', progression: 0.5),
    );

    await _pumpSheet(
      tester,
      repository: repository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
    );
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notes_sheet_delete_all_notes')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await notesRepository.listByBook('b1'), hasLength(1));

    await tester.tap(find.byKey(const Key('notes_sheet_delete_all_notes')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('notes_sheet_delete_all_notes_confirm')),
    );
    await tester.pumpAndSettle();

    expect(await notesRepository.listByBook('b1'), isEmpty);
    expect(await highlightsRepository.listByBook('b1'), hasLength(1));
  });

  testWidgets('顯示「導出為 Markdown」按鈕', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(tester, repository: repository);

    expect(
      find.byKey(const Key('notes_sheet_export_markdown')),
      findsOneWidget,
    );
  });

  testWidgets('點擊導出為 Markdown 按鈕後，正確寫入暫存檔案並呼叫 SharePlatform.share', (
    tester,
  ) async {
    // 【根因說明，取代原本被簡化掉的失敗版本，見 task-2-report.md「Known
    // Issues」】`flutter test` 使用的 `AutomatedTestWidgetsFlutterBinding` 以
    // `FakeAsync` 接管整個測試的 Timer／microtask 排程，僅由 `pump()` 手動
    // 推進；真實 `dart:io` 檔案系統操作（`Directory.createTemp`／
    // `File.writeAsString`／`File.exists` 等）需要真正的作業系統事件迴圈才能
    // 完成。Dart async 函式的 Zone 是在「函式開始執行的當下」就固定，往後每個
    // await 續作都沿用同一個 Zone——因此不能像等待平台方法通道那樣，先
    // `tap()`／`pump()` 讓 `_exportMarkdown()` 在（fake）ambient zone 起跑，
    // 事後才補一個 `tester.runAsync(() => Future.delayed(...))`：那樣真實 I/O
    // 早已在 fake zone 裡卡死，事後的 runAsync 救不回來（實測會直接卡滿框架
    // 預設 10 分鐘逾時，正是原本這個測試被簡化掉的直接原因）。正確做法是連
    // `tester.tap()` 本身也一併放進 `tester.runAsync()` 的 callback 裡，讓
    // `_exportMarkdown()`（含其中真正的檔案寫入與分享呼叫）整個從一開始就在
    // runAsync 提供的真實 Zone 下執行；fake 平台替身（`PathProviderPlatform.
    // instance`／`SharePlatform.instance`）本身沒有問題——兩者皆為即時讀取
    // 的 getter，替換後立即生效（見 `path_provider`／
    // `share_plus_platform_interface` 套件原始碼），問題純粹出在 Zone 時機。
    final tempDir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('markdown_export_test'),
    ))!;
    addTearDown(() => tester.runAsync(() => tempDir.delete(recursive: true)));

    final originalPathProvider = PathProviderPlatform.instance;
    final originalSharePlatform = SharePlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    final fakeShare = FakeSharePlatform();
    SharePlatform.instance = fakeShare;
    addTearDown(() {
      PathProviderPlatform.instance = originalPathProvider;
      SharePlatform.instance = originalSharePlatform;
    });

    final repository = FakeBookmarksRepository();
    await repository.insert(
      const Bookmark(id: 'bm12', bookId: 'b1', name: '第一章', progression: 0.1),
    );

    await _pumpSheet(
      tester,
      repository: repository,
      bookTitle: '測試書籍',
      bookAuthor: '測試作者',
      bookProgress: 0.42,
    );

    // `tap()` 本身也在 runAsync callback 內執行，讓 onPressed 觸發的
    // `_exportMarkdown()` 從第一行就綁定 runAsync 的真實 Zone（見上方
    // 根因說明）；隨後改為輪詢等待 `fakeShare.lastParams` 被賦值，而非固定
    // 延遲——固定延遲（例如原本的 100ms）在系統負載較高、真實磁碟 I/O 較慢
    // 時會造成間歇性失敗（實測：連續執行會偶發 `fakeShare.lastParams` 仍為
    // null），輪詢＋逾時上限才能同時兼顧「不誤判失敗」與「真的卡住時仍會
    // 逾時而非無限等待」。
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('notes_sheet_export_markdown')));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (fakeShare.lastParams == null &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();

    expect(fakeShare.lastParams, isNotNull);
    final files = fakeShare.lastParams!.files;
    expect(files, hasLength(1));
    final exportedFile = File(files!.single.path);
    final exists = await tester.runAsync(() => exportedFile.exists());
    expect(exists, isTrue);
    final content = await tester.runAsync(() => exportedFile.readAsString());
    expect(content, contains('# 閱讀筆記：《測試書籍》'));
    expect(content, contains('**作者**：測試作者'));
    expect(content, contains('**閱讀進度**：42%'));
    expect(content, contains('*   第一章'));
  });

  testWidgets('點擊右上角 X 取消按鈕後，Bottom Sheet 關閉（Navigator.pop 生效）', (
    tester,
  ) async {
    await _pumpModalSheet(tester, repository: FakeBookmarksRepository());

    expect(find.byType(NotesBottomSheet), findsOneWidget);

    await tester.tap(find.byKey(const Key('notes_sheet_close_button')));
    await tester.pumpAndSettle();

    expect(find.byType(NotesBottomSheet), findsNothing);
  });
}

Future<void> _pumpModalSheet(
  WidgetTester tester, {
  required FakeBookmarksRepository repository,
  String bookId = 'b1',
  String bookTitle = '測試書籍',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => NotesBottomSheet(
                bookId: bookId,
                bookTitle: bookTitle,
                bookAuthor: null,
                bookProgress: 0.0,
                bookmarksRepository: repository,
                currentPosition: const BookmarkPositionContext(),
                onBookmarkSelected: (_) {},
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
