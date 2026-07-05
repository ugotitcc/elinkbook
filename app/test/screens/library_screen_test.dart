import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/screens/library_screen.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';

void main() {
  setUp(() {
    // LibraryScreen.initState() 現在會呼叫 SharedPreferences.getInstance()，
    // 純 Dart widget test 環境沒有真正的原生實作，須用官方支援的測試替身。
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('圖書庫為空時顯示「尚未匯入書籍」提示與匯入按鈕', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('書架'), findsOneWidget);
    expect(find.text('尚未匯入書籍'), findsOneWidget);
    expect(
      find.byKey(const Key('library_empty_import_button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('library_import_button')), findsOneWidget);
  });

  testWidgets('圖書庫載入資料失敗時，畫面降級顯示空清單狀態而非永遠卡在載入中', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(throwOnListBooks: true),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('尚未匯入書籍'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('有書籍時，書架 grid 呈現正確渲染書籍項目（標題、進度固定 0%）',
      (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢', author: '曹雪芹');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_grid_view')), findsOneWidget);
    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.text('紅樓夢'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('切換檢視模式按鈕後，書架從 grid 切換為列表呈現', (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢', author: '曹雪芹');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_grid_view')), findsOneWidget);
    expect(find.byKey(const Key('library_list_view')), findsNothing);

    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_grid_view')), findsNothing);
    expect(find.byKey(const Key('library_list_view')), findsOneWidget);
    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
  });

  testWidgets('切換檢視模式後，重新建立 LibraryScreen 仍維持上次選擇（模擬 App 重啟）',
      (tester) async {
    final book = _testBook(id: '1', title: '紅樓夢', author: '曹雪芹');
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_grid_view')), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_view_mode_toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_list_view')), findsOneWidget);

    // 模擬 App 重啟：SharedPreferences.setMockInitialValues 的模擬儲存體會
    // 延續到同一個測試行程內建立的新 LibraryScreen 實例，等同於重啟後讀到
    // 上次寫入的值。
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          key: const Key('library_screen_after_restart'),
          repository: repository,
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_list_view')), findsOneWidget);
    expect(find.byKey(const Key('library_grid_view')), findsNothing);
  });
}

Book _testBook({required String id, required String title, String? author}) {
  final now = DateTime.now();
  return Book(
    id: id,
    title: title,
    author: author,
    format: BookFileFormat.epub,
    filePath: 'content://example/$id.epub',
    source: BookSource.local,
    createTime: now,
    lastReadTime: now,
  );
}
