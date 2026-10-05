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
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/notes_bottom_sheet.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import '../test/support/fake_reader_feature_dependencies.dart';

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

Future<void> _pumpUntilFxlBookmarkToggleEnabled(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final finder = find.byKey(const Key('reader_fixed_layout_bookmark_toggle_button'));
    if (finder.evaluate().isNotEmpty &&
        tester.widget<IconButton>(finder).onPressed != null) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：懸浮書籤按鈕未轉為可點擊狀態');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'FXL：懸浮書籤 toggle 新增、Bottom Sheet 清單查看/重新命名/跳轉、劃線與備註分頁維持空狀態的端到端流程',
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
    final bookmarksRepository = BookmarksRepository(libraryRepository.database);

    final samplePath = await _stageAssetAsFile(
      'test/fixtures/sample_fixed_layout.epub',
      'fxl_bookmarks.epub',
    );
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_fxl_bookmarks',
      title: 'FXL 書籤測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(filePath: samplePath, bookId: 'b_fxl_bookmarks', dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager, bookmarksRepository: bookmarksRepository)),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilFxlBookmarkToggleEnabled(tester);

    // 懸浮書籤 toggle：新增目前頁書籤。
    await tester.tap(find.byKey(const Key('reader_fixed_layout_bookmark_toggle_button')));
    await tester.pumpAndSettle();

    // 懸浮筆記按鈕：開啟 Bottom Sheet 確認書籤已持久化寫入資料庫。
    await tester.tap(find.byKey(const Key('reader_fixed_layout_notes_button')));
    await tester.pumpAndSettle();
    expect(find.byType(NotesBottomSheet), findsOneWidget);

    final bookmarks = await bookmarksRepository.listByBook('b_fxl_bookmarks');
    expect(bookmarks, hasLength(1));
    final bookmarkId = bookmarks.single.id;

    // 重新命名。
    await tester.tap(find.byKey(Key('notes_sheet_bookmark_rename_$bookmarkId')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('notes_sheet_rename_field')),
      '我的書籤',
    );
    await tester.tap(find.byKey(const Key('notes_sheet_rename_confirm')));
    await tester.pumpAndSettle();
    expect(find.text('我的書籤'), findsOneWidget);

    // 「✏️ 劃線與備註」分頁：FXL 不支援，維持空狀態且無批次刪除按鈕。
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notes_sheet_annotations_placeholder')), findsOneWidget);
    expect(find.byKey(const Key('notes_sheet_delete_all_highlights')), findsNothing);

    // 切回書籤分頁，點選跳轉：Bottom Sheet 關閉、懸浮控制項收合。
    await tester.tap(find.byKey(const Key('notes_sheet_tab_bookmarks')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    expect(find.byType(NotesBottomSheet), findsNothing);
    expect(find.byKey(const Key('reader_fixed_layout_back_button')), findsNothing);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
}
