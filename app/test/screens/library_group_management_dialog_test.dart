import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:elinkbook/screens/library_group_management_dialog.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

import '../support/fake_library_repository.dart';

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

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
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

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
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
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_rename_button_A')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('library_group_rename_field')), 'B');
    await tester.tap(find.byKey(const Key('library_group_rename_confirm')));
    await tester.pumpAndSettle();

    final errorText = tester.widget<Text>(find.text('分類「B」已存在'));
    expect(errorText.style?.color, theme.colorScheme.error);
  });

  testWidgets('「新增」按鈕須位於「關閉」按鈕右側（最右邊）', (tester) async {
    final repository = FakeLibraryRepository();
    await repository.upsertGroup('A');
    final groups = await repository.listGroups();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
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
}
