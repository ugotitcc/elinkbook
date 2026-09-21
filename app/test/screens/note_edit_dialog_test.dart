import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/note_edit_dialog.dart';
import 'package:elinkbook/l10n/app_localizations.dart';

void main() {
  testWidgets('輸入文字後按儲存，回傳已 trim 的文字', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showNoteTextDialog(context, title: '新增備註');
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('新增備註'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('note_edit_dialog_field')), '  這段很重要  ');
    await tester.tap(find.byKey(const Key('note_edit_dialog_confirm')));
    await tester.pumpAndSettle();

    expect(result, '這段很重要');
  });

  testWidgets('文字為空白時按儲存，回傳 null（視同取消）', (tester) async {
    String? result = 'not-set-yet';
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showNoteTextDialog(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('note_edit_dialog_field')), '   ');
    await tester.tap(find.byKey(const Key('note_edit_dialog_confirm')));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('帶入 initialText 時，輸入框預先顯示該文字', (tester) async {
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showNoteTextDialog(context, initialText: '既有備註'),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byKey(const Key('note_edit_dialog_field')));
    expect(field.controller?.text, '既有備註');
  });

  testWidgets('按取消，回傳 null 且不拋出例外（含退場動畫期間）', (tester) async {
    String? result = 'not-set-yet';
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showNoteTextDialog(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    // 刻意用逐格 pump（而非 pumpAndSettle）跨過退場轉場動畫的中間幾個
    // frame，驗證此時 TextField 底下的 controller 尚未被過早 dispose
    // 而拋出「used after being disposed」例外（見 Global Constraints
    // 之前 NotesBottomSheet._renameController 已修過的同類問題）。
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('英文介面下取消/儲存按鈕正確以英文渲染', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showNoteTextDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });
}
