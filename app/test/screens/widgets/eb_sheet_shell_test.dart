import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/widgets/eb_sheet_shell.dart';

/// 捕捉 Navigator 實際推入的 Route，供斷言 `ModalBottomSheetRoute` 的
/// `transitionDuration` 是否真的依 `isEinkMode` 走到 `AnimationStyle.
/// noAnimation`——`showModalBottomSheet()` 沒有回傳值可以直接檢查，這是
/// Flutter 官方支援的既有觀察手法（`NavigatorObserver.didPush`）。
class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushedRoute = route;
  }
}

Future<void> _pumpAndOpen(
  WidgetTester tester, {
  bool isEinkMode = false,
  NavigatorObserver? observer,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: observer == null ? [] : [observer],
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => EBSheetShell.show<void>(
            context,
            title: '標題',
            isEinkMode: isEinkMode,
            builder: (context) => const Text('內容'),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
}

void main() {
  testWidgets('拖曳把手存在', (tester) async {
    await _pumpAndOpen(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('eb_sheet_shell_drag_handle')), findsOneWidget);
  });

  testWidgets('右上角關閉按鈕能關閉 Sheet', (tester) async {
    await _pumpAndOpen(tester);
    await tester.pumpAndSettle();
    expect(find.text('內容'), findsOneWidget);

    await tester.tap(find.byKey(const Key('eb_sheet_shell_close_button')));
    await tester.pumpAndSettle();

    expect(find.text('內容'), findsNothing);
  });

  testWidgets('isEinkMode: true 時彈出動畫時長為 Duration.zero', (tester) async {
    final observer = _RecordingNavigatorObserver();
    await _pumpAndOpen(tester, isEinkMode: true, observer: observer);
    await tester.pump();

    final route = observer.lastPushedRoute;
    expect(route, isA<ModalBottomSheetRoute>());
    expect((route as ModalBottomSheetRoute).transitionDuration, Duration.zero);

    await tester.pumpAndSettle();
  });

  testWidgets('isEinkMode: false（預設）時彈出動畫時長非 Duration.zero', (tester) async {
    final observer = _RecordingNavigatorObserver();
    await _pumpAndOpen(tester, observer: observer);
    await tester.pump();

    final route = observer.lastPushedRoute;
    expect(route, isA<ModalBottomSheetRoute>());
    expect(
      (route as ModalBottomSheetRoute).transitionDuration,
      isNot(Duration.zero),
    );

    await tester.pumpAndSettle();
  });
}
