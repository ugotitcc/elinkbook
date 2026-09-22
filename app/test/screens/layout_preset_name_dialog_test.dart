import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/screens/layout_preset_name_dialog.dart';

void main() {
  Future<String?> pumpAndOpen(
    WidgetTester tester, {
    Locale locale = const Locale('zh', 'TW'),
    String initialText = '',
  }) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showLayoutPresetNameDialog(
              context,
              initialText: initialText,
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('顯示標題、輸入名稱後點擊儲存回傳 trim 後的名稱', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showLayoutPresetNameDialog(context);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('為預設集命名'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('layout_preset_name_dialog_field')),
      '  我的預設集  ',
    );
    await tester.tap(find.byKey(const Key('layout_preset_name_dialog_confirm')));
    await tester.pumpAndSettle();

    // trim 的字元層邏輯本身另有 validateLayoutPresetName() 的純函式單元
    // 測試覆蓋，這裡驗證的是對話框把該邏輯的結果原樣回傳給呼叫端。
    expect(result, '我的預設集');
    expect(find.byKey(const Key('layout_preset_name_dialog_field')), findsNothing);
  });

  testWidgets('輸入空白字串後點擊儲存顯示驗證錯誤，不關閉對話框', (tester) async {
    await pumpAndOpen(tester);

    await tester.enterText(
      find.byKey(const Key('layout_preset_name_dialog_field')),
      '   ',
    );
    await tester.tap(find.byKey(const Key('layout_preset_name_dialog_confirm')));
    await tester.pump();

    expect(find.text('名稱不可為空'), findsOneWidget);
    expect(find.byKey(const Key('layout_preset_name_dialog_field')), findsOneWidget);
  });

  testWidgets('點擊取消回傳 null', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showLayoutPresetNameDialog(context);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('英文介面下標題／驗證錯誤／按鈕文字正確顯示', (tester) async {
    await pumpAndOpen(tester, locale: const Locale('en'));
    expect(find.text('Name the Preset'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('layout_preset_name_dialog_field')),
      '   ',
    );
    await tester.tap(find.byKey(const Key('layout_preset_name_dialog_confirm')));
    await tester.pump();

    expect(find.text('Name cannot be empty'), findsOneWidget);
  });
}
