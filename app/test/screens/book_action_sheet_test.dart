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

/// 建立包含 BookActionSheet 的 MaterialApp widget。
Widget _buildApp({
  bool showRemoveCache = true,
  bool showLayoutOverride = true,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          builder: (context) => BookActionSheet(
            book: _book(),
            showRemoveCache: showRemoveCache,
            showLayoutOverride: showLayoutOverride,
          ),
        ),
        child: const Text('open'),
      ),
    ),
  );
}

/// 建立會回傳 BookAction 結果的 MaterialApp widget。
Widget _buildResultApp({
  required ValueNotifier<BookAction?> resultNotifier,
  bool showRemoveCache = true,
  bool showLayoutOverride = true,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          resultNotifier.value = await showModalBottomSheet<BookAction>(
            context: context,
            builder: (context) => BookActionSheet(
              book: _book(),
              showRemoveCache: showRemoveCache,
              showLayoutOverride: showLayoutOverride,
            ),
          );
        },
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  testWidgets('showRemoveCache: false 時「移除快取」選項不存在', (tester) async {
    await tester.pumpWidget(_buildApp(showRemoveCache: false));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book_action_remove_cache')), findsNothing);
  });

  testWidgets('showLayoutOverride: false 時「版面覆寫」選項不存在', (tester) async {
    await tester.pumpWidget(_buildApp(showLayoutOverride: false));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book_action_layout_override')), findsNothing);
  });

  testWidgets('showRemoveCache／showLayoutOverride 皆為 true 時五個選項全部存在', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book_action_details')), findsOneWidget);
    expect(find.byKey(const Key('book_action_move')), findsOneWidget);
    expect(find.byKey(const Key('book_action_layout_override')), findsOneWidget);
    expect(find.byKey(const Key('book_action_remove_cache')), findsOneWidget);
    expect(find.byKey(const Key('book_action_delete')), findsOneWidget);
  });

  // 以下「回傳值」測試：`showModalBottomSheet` 的 Future 只有在 Sheet 被
  // 關閉後才會 resolve，因此不能用 `_buildApp` + 先 pump 再 tap 的分離
  // 模式——`result` 會在 Sheet 關閉前就被 capture 為 null。改為在單一
  // testWidgets 內用 ValueNotifier 跨時間捕獲結果。

  testWidgets('點擊「詳細資料」回傳 BookAction.showDetails 並關閉 Sheet', (tester) async {
    final resultNotifier = ValueNotifier<BookAction?>(null);
    await tester.pumpWidget(_buildResultApp(resultNotifier: resultNotifier));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_details')));
    await tester.pumpAndSettle();
    expect(resultNotifier.value, BookAction.showDetails);
    expect(find.byKey(const Key('book_action_details')), findsNothing);
  });

  testWidgets('點擊「移動」回傳 BookAction.move 並關閉 Sheet', (tester) async {
    final resultNotifier = ValueNotifier<BookAction?>(null);
    await tester.pumpWidget(_buildResultApp(resultNotifier: resultNotifier));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_move')));
    await tester.pumpAndSettle();
    expect(resultNotifier.value, BookAction.move);
  });

  testWidgets('點擊「版面覆寫」回傳 BookAction.layoutOverride 並關閉 Sheet', (tester) async {
    final resultNotifier = ValueNotifier<BookAction?>(null);
    await tester.pumpWidget(_buildResultApp(resultNotifier: resultNotifier));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_layout_override')));
    await tester.pumpAndSettle();
    expect(resultNotifier.value, BookAction.layoutOverride);
  });

  testWidgets('點擊「移除快取」回傳 BookAction.removeCache 並關閉 Sheet', (tester) async {
    final resultNotifier = ValueNotifier<BookAction?>(null);
    await tester.pumpWidget(_buildResultApp(resultNotifier: resultNotifier));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_remove_cache')));
    await tester.pumpAndSettle();
    expect(resultNotifier.value, BookAction.removeCache);
  });

  testWidgets('點擊「刪除」回傳 BookAction.delete 並關閉 Sheet', (tester) async {
    final resultNotifier = ValueNotifier<BookAction?>(null);
    await tester.pumpWidget(_buildResultApp(resultNotifier: resultNotifier));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_delete')));
    await tester.pumpAndSettle();
    expect(resultNotifier.value, BookAction.delete);
  });
}
