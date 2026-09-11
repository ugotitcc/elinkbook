import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/widgets/paging_bar.dart';

void main() {
  testWidgets('顯示目前頁碼與總頁數（1-based 呈現）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagingBar(
            currentPage: 1,
            pageCount: 5,
            onPrevious: () {},
            onNext: () {},
          ),
        ),
      ),
    );

    expect(find.text('2 / 5'), findsOneWidget);
  });

  testWidgets('onPrevious 為 null 時上一頁按鈕停用', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagingBar(
            currentPage: 0,
            pageCount: 3,
            onPrevious: null,
            onNext: () {},
          ),
        ),
      ),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const Key('paging_bar_previous_button')),
    );
    expect(button.onPressed, isNull);
    await tester.tap(
      find.byKey(const Key('paging_bar_previous_button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('onNext 為 null 時下一頁按鈕停用，點擊不崩潰', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagingBar(
            currentPage: 2,
            pageCount: 3,
            onPrevious: () {},
            onNext: null,
          ),
        ),
      ),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const Key('paging_bar_next_button')),
    );
    expect(button.onPressed, isNull);
    await tester.tap(
      find.byKey(const Key('paging_bar_next_button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'keyPrefix 非 null 時，內部按鈕改用前綴 Key，避免同畫面多個 PagingBar 實例的內部按鈕 Key 重複'
      '（reviews/review-issue-4.md Minor 2）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              PagingBar(
                currentPage: 0,
                pageCount: 2,
                onPrevious: null,
                onNext: () {},
                keyPrefix: 'section_a',
              ),
              PagingBar(
                currentPage: 0,
                pageCount: 2,
                onPrevious: null,
                onNext: () {},
                keyPrefix: 'section_b',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('paging_bar_previous_button')), findsNothing);
    expect(find.byKey(const Key('paging_bar_next_button')), findsNothing);
    expect(
      find.byKey(const Key('section_a_previous_button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('section_a_next_button')), findsOneWidget);
    expect(
      find.byKey(const Key('section_b_previous_button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('section_b_next_button')), findsOneWidget);
  });

  testWidgets('一般模式整體高度為 52dp，isEinkMode 時為 56dp（review-plan-issue-3.md C-1：高度需隨觸控目標自適應，不可寫死 52 夾傷 56dp 按鈕）', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagingBar(currentPage: 0, pageCount: 1, onPrevious: null, onNext: null),
        ),
      ),
    );
    expect(tester.getSize(find.byType(PagingBar)).height, 52);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagingBar(
            currentPage: 0,
            pageCount: 1,
            onPrevious: null,
            onNext: null,
            isEinkMode: true,
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(PagingBar)).height, 56);
  });

  testWidgets('一般模式觸控目標 48dp，isEinkMode 時為 56dp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagingBar(
            currentPage: 0,
            pageCount: 1,
            onPrevious: () {},
            onNext: () {},
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('paging_bar_previous_button'))),
      const Size(48, 48),
    );
    expect(
      tester.getSize(find.byKey(const Key('paging_bar_next_button'))),
      const Size(48, 48),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagingBar(
            currentPage: 0,
            pageCount: 1,
            onPrevious: () {},
            onNext: () {},
            isEinkMode: true,
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('paging_bar_previous_button'))),
      const Size(56, 56),
    );
    expect(
      tester.getSize(find.byKey(const Key('paging_bar_next_button'))),
      const Size(56, 56),
    );
  });

  test('PagingBar.resolvedHeight()：一般模式 52.0，E-Ink 模式 56.0（epic-36 Issue 7）', () {
    expect(PagingBar.resolvedHeight(false), 52.0);
    expect(PagingBar.resolvedHeight(true), 56.0);
  });
}
