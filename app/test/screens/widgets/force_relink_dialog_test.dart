import 'package:elinkbook/screens/widgets/force_relink_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_localized_widget.dart';

class _Host extends StatelessWidget {
  const _Host({
    required this.onResult,
    this.isEinkMode = false,
  });

  final void Function(bool) onResult;
  final bool isEinkMode;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const Key('open'),
            onPressed: () async {
              final r = await showForceRelinkDialog(
                context,
                isEinkMode: isEinkMode,
              );
              onResult(r);
            },
            child: const Text('open'),
          ),
        ),
      );
}

void main() {
  testWidgets('按確認回 true', (tester) async {
    bool? result;
    await pumpLocalizedWidget(
      tester,
      _Host(onResult: (r) => result = r),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('force_relink_dialog')), findsOneWidget);
    expect(find.byKey(const Key('force_relink_cancel')), findsOneWidget);
    expect(find.byKey(const Key('force_relink_confirm')), findsOneWidget);

    await tester.tap(find.byKey(const Key('force_relink_confirm')));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.byKey(const Key('force_relink_dialog')), findsNothing);
  });

  testWidgets('按取消回 false', (tester) async {
    bool? result;
    await pumpLocalizedWidget(
      tester,
      _Host(onResult: (r) => result = r),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('force_relink_cancel')));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.byKey(const Key('force_relink_dialog')), findsNothing);
  });

  testWidgets('點對話框外面關閉回 false', (tester) async {
    bool? result;
    await pumpLocalizedWidget(
      tester,
      _Host(onResult: (r) => result = r),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    // 點擊對話框外側 barrier
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.byKey(const Key('force_relink_dialog')), findsNothing);
  });
  testWidgets('isEinkMode 為 true 時正常顯示與關閉（無動畫）', (tester) async {
    bool? result;
    await pumpLocalizedWidget(
      tester,
      _Host(
        isEinkMode: true,
        onResult: (r) => result = r,
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('force_relink_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('force_relink_confirm')));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });
}
