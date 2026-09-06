import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/book_action_sheet.dart';

Book _book() {
  return Book(
    id: '1',
    title: '書名',
    format: BookFileFormat.epub,
    filePath: 'content://example/1.epub',
    source: BookSource.local,
    createTime: DateTime(2026, 1, 1),
    lastReadTime: DateTime(2026, 1, 1),
  );
}

Future<void> _openSheet(
  WidgetTester tester, {
  bool showRemoveCache = true,
  bool showLayoutOverride = true,
  VoidCallback? onShowDetails,
  VoidCallback? onMove,
  VoidCallback? onLayoutOverride,
  VoidCallback? onRemoveCache,
  VoidCallback? onDelete,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (context) => BookActionSheet(
              book: _book(),
              showRemoveCache: showRemoveCache,
              showLayoutOverride: showLayoutOverride,
              onShowDetails: onShowDetails ?? () {},
              onMove: onMove ?? () {},
              onLayoutOverride: onLayoutOverride ?? () {},
              onRemoveCache: onRemoveCache,
              onDelete: onDelete ?? () {},
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('showRemoveCache: false 時「移除快取」選項不存在', (tester) async {
    await _openSheet(tester, showRemoveCache: false);
    expect(find.byKey(const Key('book_action_remove_cache')), findsNothing);
  });

  testWidgets('showLayoutOverride: false 時「版面覆寫」選項不存在', (tester) async {
    await _openSheet(tester, showLayoutOverride: false);
    expect(find.byKey(const Key('book_action_layout_override')), findsNothing);
  });

  testWidgets('showRemoveCache／showLayoutOverride 皆為 true 時五個選項全部存在', (
    tester,
  ) async {
    await _openSheet(tester);
    expect(find.byKey(const Key('book_action_details')), findsOneWidget);
    expect(find.byKey(const Key('book_action_move')), findsOneWidget);
    expect(find.byKey(const Key('book_action_layout_override')), findsOneWidget);
    expect(find.byKey(const Key('book_action_remove_cache')), findsOneWidget);
    expect(find.byKey(const Key('book_action_delete')), findsOneWidget);
  });

  testWidgets('點擊「詳細資料」關閉 Sheet 並呼叫 onShowDetails', (tester) async {
    var called = 0;
    await _openSheet(tester, onShowDetails: () => called++);
    await tester.tap(find.byKey(const Key('book_action_details')));
    await tester.pumpAndSettle();
    expect(called, 1);
    expect(find.byKey(const Key('book_action_details')), findsNothing);
  });

  testWidgets('點擊「移動」關閉 Sheet 並呼叫 onMove', (tester) async {
    var called = 0;
    await _openSheet(tester, onMove: () => called++);
    await tester.tap(find.byKey(const Key('book_action_move')));
    await tester.pumpAndSettle();
    expect(called, 1);
  });

  testWidgets('點擊「版面覆寫」關閉 Sheet 並呼叫 onLayoutOverride', (tester) async {
    var called = 0;
    await _openSheet(tester, onLayoutOverride: () => called++);
    await tester.tap(find.byKey(const Key('book_action_layout_override')));
    await tester.pumpAndSettle();
    expect(called, 1);
  });

  testWidgets('點擊「移除快取」關閉 Sheet 並呼叫 onRemoveCache', (tester) async {
    var called = 0;
    await _openSheet(tester, onRemoveCache: () => called++);
    await tester.tap(find.byKey(const Key('book_action_remove_cache')));
    await tester.pumpAndSettle();
    expect(called, 1);
  });

  testWidgets('點擊「刪除」關閉 Sheet 並呼叫 onDelete', (tester) async {
    var called = 0;
    await _openSheet(tester, onDelete: () => called++);
    await tester.tap(find.byKey(const Key('book_action_delete')));
    await tester.pumpAndSettle();
    expect(called, 1);
  });
}
