import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:elinkbook/screens/library_group_management_dialog.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

import '../support/fake_library_repository.dart';
import '../support/pump_localized_widget.dart';

void main() {
  testWidgets(
      '分類數量多且鍵盤開啟（新增分類名稱欄位取得焦點）時，'
      '管理分類對話框底部不應溢位', (tester) async {
    final repository = FakeLibraryRepository();
    // 比照使用者回報畫面：畫面中已有數個具名分類（含「未分類」共 5+ 個）。
    for (final name in ['有意義', '測試', '四書聖訓', '心理勵志', '小說']) {
      await repository.upsertGroup(name);
    }
    final groups = await repository.listGroups();

    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => LibraryGroupManagementDialog(
                  repository: repository,
                  initialGroups: groups,
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

    // 點擊「新增分類名稱」欄位取得焦點，模擬使用者實際操作時觸發系統鍵盤
    // 彈出；widget test 環境沒有真正的系統鍵盤，改用
    // tester.testTextInput.show() 讓 Flutter 認為鍵盤已顯示，並手動調整
    // MediaQuery.viewInsets.bottom 模擬鍵盤佔用的螢幕高度（比照真機常見的
    // 注音鍵盤高度比例，約佔螢幕下半部）。
    await tester.tap(find.byKey(const Key('library_group_add_field')));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: '分類數量多＋鍵盤開啟時，AlertDialog 內容（分類清單＋新增欄位）'
            '不應該讓 RenderFlex 溢位（真機回報：BOTTOM OVERFLOWED BY 21 PIXELS）');
  });

  testWidgets('重新命名為已存在的分類名稱時，錯誤訊息文字色為 colorScheme.error',
      (tester) async {
    final repository = FakeLibraryRepository();
    await repository.upsertGroup('A');
    await repository.upsertGroup('B');
    final groups = await repository.listGroups();
    final theme = resolveThemeData(theme: AppTheme.light, isEinkMode: false);

    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => LibraryGroupManagementDialog(
                  repository: repository,
                  initialGroups: groups,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      theme: AppTheme.light,
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_rename_button_A')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('library_group_rename_field')), 'B');
    await tester.tap(find.byKey(const Key('library_group_rename_confirm')));
    await tester.pumpAndSettle();

    final errorText = tester.widget<Text>(find.text('分類「B」已存在，請使用其他名稱'));
    expect(errorText.style?.color, theme.colorScheme.error);
  });

  testWidgets('英文介面下，重新命名撞名顯示英文固定訊息（不含伺服器原始診斷文字）',
      (tester) async {
    final repository = FakeLibraryRepository();
    await repository.upsertGroup('A');
    await repository.upsertGroup('B');
    final groups = await repository.listGroups();

    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => LibraryGroupManagementDialog(
                  repository: repository,
                  initialGroups: groups,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      locale: const Locale('en'),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_rename_button_A')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('library_group_rename_field')), 'B');
    await tester.tap(find.byKey(const Key('library_group_rename_confirm')));
    await tester.pumpAndSettle();

    expect(
      find.text('"B" already exists. Please use a different name.'),
      findsOneWidget,
    );
  });

  testWidgets('「新增」按鈕須位於「關閉」按鈕右側（最右邊）', (tester) async {
    final repository = FakeLibraryRepository();
    await repository.upsertGroup('A');
    final groups = await repository.listGroups();

    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => LibraryGroupManagementDialog(
                  repository: repository,
                  initialGroups: groups,
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

    final addButtonX = tester
        .getTopLeft(find.byKey(const Key('library_group_add_button')))
        .dx;
    final closeButtonX = tester
        .getTopLeft(find.byKey(const Key('library_group_close_button')))
        .dx;

    expect(addButtonX, greaterThan(closeButtonX),
        reason: '「新增」應排在「關閉」右側，即畫面最右邊');
  });

  testWidgets(
      '新增分類時輸入三語言任一保留字，前端攔截、不呼叫 repository.upsertGroup()、顯示錯誤訊息',
      (tester) async {
    final repository = FakeLibraryRepository();
    final groups = await repository.listGroups();

    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => LibraryGroupManagementDialog(
                  repository: repository,
                  initialGroups: groups,
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

    for (final reserved in ['未分類', '未分类', 'Uncategorized']) {
      await tester.enterText(
        find.byKey(const Key('library_group_add_field')),
        reserved,
      );
      await tester.tap(find.byKey(const Key('library_group_add_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('「$reserved」是系統保留的分類名稱，請使用其他名稱'),
        findsOneWidget,
        reason: '「$reserved」應被前端攔截並顯示錯誤',
      );
    }

    expect(repository.upsertGroupCalls, isEmpty);
  });

  testWidgets(
      '重新命名分類時輸入保留字，前端攔截、不呼叫 repository.renameGroup()、顯示錯誤訊息',
      (tester) async {
    final repository = FakeLibraryRepository();
    await repository.upsertGroup('奇幻');
    final groups = await repository.listGroups();

    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => LibraryGroupManagementDialog(
                  repository: repository,
                  initialGroups: groups,
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

    await tester.tap(find.byKey(const Key('library_group_rename_button_奇幻')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('library_group_rename_field')),
      '未分类',
    );
    await tester.tap(find.byKey(const Key('library_group_rename_confirm')));
    await tester.pumpAndSettle();

    expect(
      find.text('「未分类」是系統保留的分類名稱，請使用其他名稱'),
      findsOneWidget,
    );
    expect(repository.renameGroupCalls, isEmpty);
  });

  testWidgets('分類清單中「未分類」依目前介面語言正確轉譯，使用者自訂分類原樣顯示',
      (tester) async {
    final repository = FakeLibraryRepository();
    await repository.upsertGroup('Fantasy');
    final groups = await repository.listGroups();

    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => LibraryGroupManagementDialog(
                  repository: repository,
                  initialGroups: groups,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      locale: const Locale('zh', 'CN'),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('未分类'), findsOneWidget);
    expect(find.text('Fantasy'), findsOneWidget);
    expect(find.text('未分類'), findsNothing, reason: '不應顯示未轉譯的正體中文原字面值');
  });

  testWidgets('刪除分類確認訊息中的目的地分類名稱依目前介面語言正確轉譯', (tester) async {
    final repository = FakeLibraryRepository();
    await repository.upsertGroup('奇幻');
    final groups = await repository.listGroups();

    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => LibraryGroupManagementDialog(
                  repository: repository,
                  initialGroups: groups,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      locale: const Locale('en'),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_delete_button_奇幻')));
    await tester.pumpAndSettle();

    expect(
      find.text('Delete category "奇幻"? Books in this category will be '
          'moved to "Uncategorized".'),
      findsOneWidget,
    );
  });
}
