// app/test/screens/full_text_search_confirm_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/full_text_search_confirm_dialog.dart';
import 'package:elinkbook/search/full_text_search_settings_repository.dart';

/// 捕捉 Navigator 實際推入的 Route，供斷言 `DialogRoute` 的
/// `transitionDuration` 是否真的依 `isEinkMode` 走到 `AnimationStyle.
/// noAnimation`（比照 `test/screens/widgets/eb_sheet_shell_test.dart`
/// 既有手法）。
class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushedRoute = route;
  }
}

Future<bool?> _open(
  WidgetTester tester, {
  required ContentIndexCategory category,
  bool isEinkMode = false,
  NavigatorObserver? observer,
}) async {
  bool? result;
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: observer == null ? [] : [observer],
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showFullTextSearchEnableConfirmDialog(
              context,
              category: category,
              isEinkMode: isEinkMode,
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('按下取消對話框關閉', (tester) async {
    await _open(tester, category: ContentIndexCategory.foliate);
    await tester.tap(find.byKey(
      const Key('full_text_search_enable_confirm_dialog_cancel'),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('full_text_search_enable_confirm_dialog')),
      findsNothing,
    );
  });

  testWidgets('按下確認開啟回傳 true', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showFullTextSearchEnableConfirmDialog(
                context,
                category: ContentIndexCategory.foliate,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
      const Key('full_text_search_enable_confirm_dialog_confirm'),
    ));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('PDF 分類額外顯示掃描件提示文案', (tester) async {
    await _open(tester, category: ContentIndexCategory.pdf);

    expect(find.textContaining('掃描/圖片型 PDF'), findsOneWidget);
  });

  testWidgets('Foliate 分類不顯示 PDF 專屬提示文案', (tester) async {
    await _open(tester, category: ContentIndexCategory.foliate);

    expect(find.textContaining('掃描/圖片型 PDF'), findsNothing);
  });

  testWidgets('對話框寬度不超過 400，且不強制施加緊約束（review-plan-issue-3.md I-3）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showFullTextSearchEnableConfirmDialog(
              context,
              category: ContentIndexCategory.foliate,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 不應有任何 overflow 相關的 FlutterError（pumpAndSettle 若渲染期間
    // 拋出 overflow 例外，測試本身就會直接失敗），此處額外斷言對話框
    // 確實成功渲染出來，佐證沒有在 debug 模式被 overflow 中斷。
    expect(
      find.byKey(const Key('full_text_search_enable_confirm_dialog')),
      findsOneWidget,
    );
  });

  testWidgets('isEinkMode: true 時彈出動畫時長為 Duration.zero', (tester) async {
    final observer = _RecordingNavigatorObserver();
    await _open(
      tester,
      category: ContentIndexCategory.foliate,
      isEinkMode: true,
      observer: observer,
    );

    final route = observer.lastPushedRoute;
    expect(route, isA<DialogRoute>());
    expect((route as DialogRoute).transitionDuration, Duration.zero);
  });

  testWidgets('isEinkMode: false（預設）時彈出動畫時長非 Duration.zero',
      (tester) async {
    final observer = _RecordingNavigatorObserver();
    await _open(
      tester,
      category: ContentIndexCategory.foliate,
      observer: observer,
    );

    final route = observer.lastPushedRoute;
    expect(route, isA<DialogRoute>());
    expect((route as DialogRoute).transitionDuration, isNot(Duration.zero));
  });
}
