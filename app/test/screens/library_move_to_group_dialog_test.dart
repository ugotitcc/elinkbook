import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/screens/library_move_to_group_dialog.dart';

void main() {
  testWidgets('顯示所有分類選項，點擊後以該分類名稱關閉對話框', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDialog<String>(
                context: context,
                builder: (_) => const LibraryMoveToGroupDialog(
                  groups: [BookGroup('未分類'), BookGroup('奇幻')],
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('移動到分類'), findsOneWidget);
    expect(
      find.byKey(const Key('library_move_to_group_option_未分類')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('library_move_to_group_option_奇幻')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('library_move_to_group_option_奇幻')));
    await tester.pumpAndSettle();

    expect(result, '奇幻');
  });

  testWidgets('點擊取消後，對話框關閉且不回傳任何分類', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDialog<String>(
                context: context,
                builder: (_) => const LibraryMoveToGroupDialog(
                  groups: [BookGroup('未分類')],
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_move_to_group_cancel')));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
