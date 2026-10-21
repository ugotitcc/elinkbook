// app/test/screens/dictionary_online_consent_dialog_test.dart
import 'package:elinkbook/screens/dictionary_online_consent_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_localized_widget.dart';

/// 按鈕開啟對話框，回傳其結果的 Future；呼叫端自行 `pump`。
Future<Future<bool>> _openDialog(
  WidgetTester tester, {
  bool isEinkMode = false,
}) async {
  late Future<bool> result;
  await pumpLocalizedWidget(
    tester,
    Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => result = showDictionaryOnlineConsentDialog(
          context,
          isEinkMode: isEinkMode,
        ),
        child: const Text('open'),
      ),
    ),
    isEinkMode: isEinkMode,
  );
  await tester.tap(find.text('open'));
  return result;
}

void main() {
  testWidgets('顯示四項說明', (tester) async {
    await _openDialog(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('www.moedict.tw'), findsOneWidget);
    expect(find.textContaining('書名、前後文、位置、裝置識別'), findsOneWidget);
    expect(find.textContaining('隨時'), findsOneWidget);
    expect(
      find.byKey(const Key('dictionary_online_consent_dialog')),
      findsOneWidget,
    );
  });

  testWidgets('同意回 true', (tester) async {
    final result = await _openDialog(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dictionary_online_consent_agree')));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    expect(find.byKey(const Key('dictionary_online_consent_dialog')), findsNothing);
  });

  testWidgets('取消回 false', (tester) async {
    final result = await _openDialog(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dictionary_online_consent_cancel')));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
  });

  testWidgets('點對話框外回 false', (tester) async {
    final result = await _openDialog(tester);
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
  });

  testWidgets('E-Ink 模式不使用動畫', (tester) async {
    await _openDialog(tester, isEinkMode: true);
    await tester.pump();

    expect(
      find.byKey(const Key('dictionary_online_consent_dialog')),
      findsOneWidget,
    );
    expect(tester.hasRunningAnimations, isFalse);
  });
}
