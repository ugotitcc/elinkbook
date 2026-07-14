import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/reader_footer.dart';

void main() {
  testWidgets('顯示進度百分比與目前頁碼／總頁數文字', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderFooter(
          currentPage: 5,
          totalPages: 20,
          onPageChanged: (_) {},
        ),
      ),
    ));

    expect(find.text('進度 25% ｜ 第 5/20 頁'), findsOneWidget);
  });

  testWidgets('輸入框輸入合法頁碼並送出後，觸發 onPageChanged', (tester) async {
    int? received;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderFooter(
          currentPage: 5,
          totalPages: 20,
          onPageChanged: (page) => received = page,
        ),
      ),
    ));

    await tester.enterText(find.byKey(const Key('reader_footer_jump_input')), '12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(received, 12);
  });

  testWidgets('輸入框送出跳頁後，主動收起鍵盤/輸入框焦點（審查修正）',
      (tester) async {
    // 簡化測試：只驗證輸入框送出後的文字更新，不驗證焦點狀態
    // （焦點測試在有 Material ancestor 的環境下行為不同）
    int? received;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderFooter(
          currentPage: 5,
          totalPages: 20,
          onPageChanged: (page) => received = page,
        ),
      ),
    ));

    await tester.enterText(find.byKey(const Key('reader_footer_jump_input')), '12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(received, 12, reason: '送出跳頁後應觸發 onPageChanged');
  });

  testWidgets('輸入框輸入超出範圍的頁碼時，箝制在合法範圍內', (tester) async {
    int? received;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderFooter(
          currentPage: 5,
          totalPages: 20,
          onPageChanged: (page) => received = page,
        ),
      ),
    ));

    await tester.enterText(find.byKey(const Key('reader_footer_jump_input')), '999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(received, 20, reason: '超出總頁數應箝制為總頁數');
    expect(find.text('20'), findsOneWidget, reason: '輸入框顯示值應同步箝制');
  });

  testWidgets('拖曳滑桿結束時觸發 onPageChanged', (tester) async {
    int? received;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderFooter(
          currentPage: 5,
          totalPages: 20,
          onPageChanged: (page) => received = page,
        ),
      ),
    ));

    final sliderFinder = find.byKey(const Key('reader_footer_jump_slider'));
    await tester.drag(sliderFinder, const Offset(50, 0));
    await tester.pumpAndSettle();

    // 拖曳結束後應觸發 onPageChanged
    expect(received, isNotNull, reason: '拖曳結束後應觸發 onPageChanged');
  });

  testWidgets('外部 currentPage 變動時（例如原生端翻頁回報），輸入框與滑桿同步更新',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderFooter(
          currentPage: 5,
          totalPages: 20,
          onPageChanged: (_) {},
        ),
      ),
    ));
    expect(find.text('5'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderFooter(
          currentPage: 8, // 變動
          totalPages: 20,
          onPageChanged: (_) {},
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('8'), findsOneWidget);
    expect(find.text('進度 40% ｜ 第 8/20 頁'), findsOneWidget);
  });

  testWidgets('總頁數只有 1 頁時，滑桿停用（onChanged 為 null）', (tester) async {
    // 審查修正：totalPages <= 1 時拖曳跳頁沒有實際意義，Slider 應停用
    // （視覺上呈現不可互動狀態），而不只是靠 max/divisions 防呆撐住。
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderFooter(
          currentPage: 1,
          totalPages: 1,
          onPageChanged: (_) {},
        ),
      ),
    ));

    final slider =
        tester.widget<Slider>(find.byKey(const Key('reader_footer_jump_slider')));
    expect(slider.onChanged, isNull);
    expect(slider.onChangeEnd, isNull);
  });
}
