import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/layout_preset.dart';
import 'package:elinkbook/screens/layout_preset_dialogs.dart';

import '../support/pump_localized_widget.dart';

LayoutPreset _preset(int id, String name) => LayoutPreset(
      id: id,
      name: name,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 2),
      prefs: BookReaderPrefs.empty,
    );

void main() {
  // 測試用「畫面」：用一個變數控制 contextProvider 回傳值，模擬畫面卸載。
  late BuildContext? currentContext;
  late DialogLayoutPresetPrompts prompts;

  Future<void> pumpHost(WidgetTester tester) async {
    await pumpLocalizedWidget(
      tester,
      Scaffold(
        body: Builder(builder: (context) {
          currentContext = context;
          return const SizedBox();
        }),
      ),
    );
    prompts = DialogLayoutPresetPrompts(contextProvider: () => currentContext);
  }

  group('畫面已卸載（contextProvider 回傳 null）', () {
    testWidgets('五個方法都回傳取消，且沒有顯示任何對話框', (tester) async {
      await pumpHost(tester);
      currentContext = null;

      expect(await prompts.askName(), isNull);
      expect(await prompts.pickOverwriteTarget([_preset(1, 'A')]), isNull);
      expect(await prompts.confirmOverwrite('A'), isFalse);
      expect(await prompts.confirmApplyToOthers(2), isFalse);
      expect(await prompts.confirmDelete('A'), isFalse);

      await tester.pump();
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('對話框開著的期間畫面被卸載：關閉後仍回傳取消', (tester) async {
      await pumpHost(tester);
      final liveContext = currentContext;

      final future = prompts.confirmDelete('A');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('layout_preset_delete_confirm')), findsOneWidget);

      // 對話框開著時畫面被卸載，之後使用者按了「確認」
      currentContext = null;
      await tester.tap(find.byKey(const Key('layout_preset_delete_confirm')));
      await tester.pumpAndSettle();

      expect(await future, isFalse);
      expect(liveContext, isNotNull);
    });
  });

  group('畫面仍在', () {
    testWidgets('confirmOverwrite：確認回傳 true，取消回傳 false', (tester) async {
      await pumpHost(tester);

      var future = prompts.confirmOverwrite('A');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('layout_preset_overwrite_confirm')));
      await tester.pumpAndSettle();
      expect(await future, isTrue);

      future = prompts.confirmOverwrite('A');
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await future, isFalse);
    });

    testWidgets('confirmApplyToOthers：確認回傳 true，取消回傳 false', (tester) async {
      await pumpHost(tester);

      var future = prompts.confirmApplyToOthers(3);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('layout_preset_apply_confirm')));
      await tester.pumpAndSettle();
      expect(await future, isTrue);

      future = prompts.confirmApplyToOthers(3);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await future, isFalse);
    });

    testWidgets('confirmDelete：確認回傳 true，取消回傳 false', (tester) async {
      await pumpHost(tester);

      var future = prompts.confirmDelete('A');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('layout_preset_delete_confirm')));
      await tester.pumpAndSettle();
      expect(await future, isTrue);

      future = prompts.confirmDelete('A');
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await future, isFalse);
    });

    testWidgets('pickOverwriteTarget：點選項目回傳該預設集，取消回傳 null', (tester) async {
      await pumpHost(tester);
      final presets = [_preset(1, '甲'), _preset(2, '乙'), _preset(3, '丙')];

      var future = prompts.pickOverwriteTarget(presets);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('layout_preset_overwrite_option_2')));
      await tester.pumpAndSettle();
      expect((await future)?.name, '乙');

      future = prompts.pickOverwriteTarget(presets);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('layout_preset_overwrite_cancel')));
      await tester.pumpAndSettle();
      expect(await future, isNull);
    });

    testWidgets('askName：輸入名稱並確認回傳名稱', (tester) async {
      await pumpHost(tester);

      final future = prompts.askName();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('layout_preset_name_dialog_field')),
        '夜讀直排',
      );
      await tester.tap(find.byKey(const Key('layout_preset_name_dialog_confirm')));
      await tester.pumpAndSettle();

      expect(await future, '夜讀直排');
    });
  });
}
