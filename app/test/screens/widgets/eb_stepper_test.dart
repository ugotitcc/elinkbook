import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/screens/widgets/eb_stepper.dart';

void main() {
  Widget buildStepper({
    double value = 16,
    double min = 12,
    double max = 80,
    double step = 1,
    String displayValue = '16',
    ValueChanged<double>? onChanged,
  }) {
    return MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: EBStepper(
          keyPrefix: 'test_stepper',
          value: value,
          min: min,
          max: max,
          step: step,
          displayValue: displayValue,
          onChanged: onChanged ?? (_) {},
        ),
      ),
    );
  }

  testWidgets('顯示 displayValue 文字', (tester) async {
    await tester.pumpWidget(buildStepper(displayValue: '42'));

    expect(find.text('42'), findsOneWidget);
    expect(find.byKey(const Key('test_stepper_value')), findsOneWidget);
  });

  testWidgets('點擊 + 觸發 onChanged 並帶入 value + step', (tester) async {
    double? received;
    await tester.pumpWidget(
      buildStepper(value: 16, step: 1, onChanged: (v) => received = v),
    );

    await tester.tap(find.byKey(const Key('test_stepper_increment')));

    expect(received, 17);
  });

  testWidgets('點擊 - 觸發 onChanged 並帶入 value - step', (tester) async {
    double? received;
    await tester.pumpWidget(
      buildStepper(value: 16, step: 1, onChanged: (v) => received = v),
    );

    await tester.tap(find.byKey(const Key('test_stepper_decrement')));

    expect(received, 15);
  });

  testWidgets('value - step < min 時，減少按鈕停用', (tester) async {
    await tester.pumpWidget(buildStepper(value: 12, min: 12, step: 1));

    final button = tester.widget<IconButton>(
      find.byKey(const Key('test_stepper_decrement')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('value + step > max 時，增加按鈕停用', (tester) async {
    await tester.pumpWidget(buildStepper(value: 80, max: 80, step: 1));

    final button = tester.widget<IconButton>(
      find.byKey(const Key('test_stepper_increment')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('未觸及邊界時，減少/增加按鈕皆為可點擊狀態', (tester) async {
    await tester.pumpWidget(buildStepper(value: 16, min: 12, max: 80, step: 1));

    final decrement = tester.widget<IconButton>(
      find.byKey(const Key('test_stepper_decrement')),
    );
    final increment = tester.widget<IconButton>(
      find.byKey(const Key('test_stepper_increment')),
    );
    expect(decrement.onPressed, isNotNull);
    expect(increment.onPressed, isNotNull);
  });

  testWidgets('widget tree 內不存在任何 Slider', (tester) async {
    await tester.pumpWidget(buildStepper());

    expect(find.byType(Slider), findsNothing);
  });
}
