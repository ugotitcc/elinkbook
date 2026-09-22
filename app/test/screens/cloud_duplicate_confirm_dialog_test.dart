import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/screens/cloud_duplicate_confirm_dialog.dart';

void main() {
  Future<bool?> pumpAndOpen(
    WidgetTester tester, {
    Locale locale = const Locale('zh', 'TW'),
    String message = '測試訊息',
  }) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showCloudDuplicateConfirmDialog(context, message);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('顯示標題與傳入訊息，點擊「仍要建立」回傳 true', (tester) async {
    await pumpAndOpen(tester, message: '「紅樓夢」之前匯入過了，仍要建立新的一份嗎？');
    expect(find.text('重複的書籍'), findsOneWidget);
    expect(find.text('「紅樓夢」之前匯入過了，仍要建立新的一份嗎？'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cloud_duplicate_dialog_confirm')));
    await tester.pumpAndSettle();
  });

  testWidgets('點擊取消回傳 false', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showCloudDuplicateConfirmDialog(context, '測試訊息');
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cloud_duplicate_dialog_cancel')));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('英文介面下標題與按鈕文字正確顯示', (tester) async {
    await pumpAndOpen(tester, locale: const Locale('en'), message: 'Test message');
    expect(find.text('Duplicate Book'), findsOneWidget);
    expect(find.text('Test message'), findsOneWidget);
    expect(find.text('Create Anyway'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });
}
