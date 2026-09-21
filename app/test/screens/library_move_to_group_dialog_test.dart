import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/screens/library_move_to_group_dialog.dart';

import '../support/pump_localized_widget.dart';

void main() {
  testWidgets('顯示所有分類選項，點擊後以該分類名稱關閉對話框', (tester) async {
    String? result = 'unset';
    await pumpLocalizedWidget(
      tester,
      Builder(
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
    await pumpLocalizedWidget(
      tester,
      Builder(
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
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_move_to_group_cancel')));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets(
      '「未分類」選項依目前介面語言正確轉譯，使用者自訂分類原樣顯示，標題亦正確轉譯，'
      '且點擊已轉譯選項回傳的仍是底層 Sentinel 原始字面值'
      '（/receiving-code-review M-2 修正：補齊 pop 回傳值斷言，鎖死「表現層轉譯不影響'
      '底層資料庫值」這條核心契約，不能只驗證畫面顯示文字）',
      (tester) async {
    String? result = 'unset';
    await pumpLocalizedWidget(
      tester,
      Builder(
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
      locale: const Locale('en'),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Move to Category'), findsOneWidget);
    expect(find.text('Uncategorized'), findsOneWidget);
    expect(find.text('奇幻'), findsOneWidget);
    expect(find.text('未分類'), findsNothing, reason: '不應顯示未轉譯的正體中文原字面值');

    await tester.tap(find.text('Uncategorized'));
    await tester.pumpAndSettle();

    expect(
      result,
      BookGroup.uncategorized,
      reason: '英文介面下點擊已轉譯為 "Uncategorized" 的選項，pop 回傳的仍須是資料庫主鍵原始字面值'
          '「未分類」，不可是顯示用的英文字串',
    );
  });
}
