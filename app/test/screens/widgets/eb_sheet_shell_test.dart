import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/screens/widgets/eb_sheet_shell.dart';

import '../../support/pump_localized_widget.dart';

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
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
  testWidgets('AppLocalizations 存在時，關閉按鈕 tooltip 依三語言正確在地化',
      (tester) async {
    for (final entry in {
      const Locale('zh', 'TW'): '關閉',
      const Locale('zh', 'CN'): '关闭',
      const Locale('en'): 'Close',
    }.entries) {
      await pumpLocalizedWidget(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => EBSheetShell.show<void>(
              context,
              title: '標題',
              builder: (context) => const Text('內容'),
            ),
            child: const Text('open'),
          ),
        ),
        locale: entry.key,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final iconButton = tester.widget<IconButton>(
        find.byKey(const Key('eb_sheet_shell_close_button')),
      );
      expect(iconButton.tooltip, entry.value);

      // （/receiving-code-review M-2 修正）額外驗證三語言下關閉按鈕本身
      // 仍可正常點擊關閉，不只是 tooltip 文字正確。
      await tester.tap(find.byKey(const Key('eb_sheet_shell_close_button')));
      await tester.pumpAndSettle();
      expect(find.text('內容'), findsNothing);
    }
  });

  testWidgets('AppLocalizations 不存在（裸 MaterialApp）時，tooltip 回退既有中文字面值',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => EBSheetShell.show<void>(
              context,
              title: '標題',
              builder: (context) => const Text('內容'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final iconButton = tester.widget<IconButton>(
      find.byKey(const Key('eb_sheet_shell_close_button')),
    );
    expect(iconButton.tooltip, '關閉');
  });

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

  testWidgets('isEinkMode: true 時最外層有 eb_sheet_shell_eink_border 外框（上左右 2px、無陰影）',
      (tester) async {
    const outlineColor = Color(0xFF79747E);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          colorScheme: const ColorScheme.light(outline: outlineColor),
        ),
        home: const Scaffold(
          body: EBSheetShell(
            title: '標題',
            isEinkMode: true,
            child: Text('內容'),
          ),
        ),
      ),
    );

    final finder = find.byKey(const Key('eb_sheet_shell_eink_border'));
    expect(finder, findsOneWidget);

    final decoratedBox = tester.widget<DecoratedBox>(finder);
    expect(decoratedBox.decoration, isA<BoxDecoration>());
    final decoration = decoratedBox.decoration as BoxDecoration;
    expect(decoration.boxShadow, isNull);
    expect(decoration.border, isA<Border>());
    final border = decoration.border as Border;

    expect(border.top.width, 2.0);
    expect(border.top.color, outlineColor);
    expect(border.left.width, 2.0);
    expect(border.left.color, outlineColor);
    expect(border.right.width, 2.0);
    expect(border.right.color, outlineColor);
    expect(border.bottom.width, 0.0);
  });

  testWidgets('isEinkMode: false 時沒有 eb_sheet_shell_eink_border 外框元件',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: EBSheetShell(
            title: '標題',
            isEinkMode: false,
            child: Text('內容'),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('eb_sheet_shell_eink_border')), findsNothing);
  });

  testWidgets('EBSheetShell.show 在 isEinkMode: true 時 BottomSheet 為直角且無陰影',
      (tester) async {
    await _pumpAndOpen(tester, isEinkMode: true);
    await tester.pumpAndSettle();

    final bottomSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(bottomSheet.elevation, 0);
    expect(bottomSheet.shape, isA<RoundedRectangleBorder>());
    final shape = bottomSheet.shape as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.zero);
  });

  testWidgets('EBSheetShell.show 在 isEinkMode: false 時 BottomSheet 沿用主題預設',
      (tester) async {
    await _pumpAndOpen(tester, isEinkMode: false);
    await tester.pumpAndSettle();

    final bottomSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(bottomSheet.elevation, isNot(0));
    final shape = bottomSheet.shape;
    if (shape is RoundedRectangleBorder) {
      expect(shape.borderRadius, isNot(BorderRadius.zero));
    }
  });

  testWidgets('標題、把手、關閉鍵仍在，ConstrainedBox 最大高度仍為螢幕 85%', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: EBSheetShell(
            title: '測試標題',
            isEinkMode: true,
            child: Text('內容'),
          ),
        ),
      ),
    );

    expect(find.text('測試標題'), findsOneWidget);
    expect(find.byKey(const Key('eb_sheet_shell_drag_handle')), findsOneWidget);
    expect(find.byKey(const Key('eb_sheet_shell_close_button')), findsOneWidget);

    final screenHeight = tester.getSize(find.byType(MaterialApp)).height;
    final constrainedBox = tester.widget<ConstrainedBox>(
      find
          .descendant(
            of: find.byType(EBSheetShell),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    expect(constrainedBox.constraints.maxHeight, screenHeight * 0.85);
  });
}
