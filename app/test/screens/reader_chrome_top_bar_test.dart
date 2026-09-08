import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/reader_chrome_top_bar.dart';

void main() {
  Widget buildTopBar({
    VoidCallback? onBack,
    String chapterTitle = '第七章',
    VoidCallback? onSearchTap,
    bool isBottomChromeVisible = true,
    VoidCallback? onToggleBottomChrome,
    VoidCallback? onTocTap,
    bool showTtsIndicator = false,
    bool isEinkMode = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ReaderChromeTopBar(
          onBack: onBack ?? () {},
          chapterTitle: chapterTitle,
          onSearchTap: onSearchTap ?? () {},
          isBottomChromeVisible: isBottomChromeVisible,
          onToggleBottomChrome: onToggleBottomChrome ?? () {},
          onTocTap: onTocTap,
          showTtsIndicator: showTtsIndicator,
          backgroundColor: Colors.white,
          iconColor: Colors.black,
          isEinkMode: isEinkMode,
        ),
      ),
    );
  }

  testWidgets('顯示章節標題文字', (tester) async {
    await tester.pumpWidget(buildTopBar(chapterTitle: '第七章 · 弦外之音'));
    expect(find.text('第七章 · 弦外之音'), findsOneWidget);
  });

  testWidgets('點擊返回按鈕觸發 onBack', (tester) async {
    var called = false;
    await tester.pumpWidget(buildTopBar(onBack: () => called = true));
    await tester.tap(find.byKey(const Key('reader_chrome_back_button')));
    expect(called, isTrue);
  });

  testWidgets('點擊搜尋按鈕觸發 onSearchTap', (tester) async {
    var called = false;
    await tester.pumpWidget(buildTopBar(onSearchTap: () => called = true));
    await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
    expect(called, isTrue);
  });

  testWidgets('點擊 ⬓ 按鈕觸發 onToggleBottomChrome', (tester) async {
    var called = false;
    await tester.pumpWidget(
      buildTopBar(onToggleBottomChrome: () => called = true),
    );
    await tester.tap(
      find.byKey(const Key('reader_chrome_immersive_toggle_button')),
    );
    expect(called, isTrue);
  });

  testWidgets('isBottomChromeVisible: true 時，⬓ 按鈕顯示實心 dock 圖示'
      '（2026-09-08 /grill-with-docs 使用者需求，取代眼睛圖示）', (tester) async {
    await tester.pumpWidget(buildTopBar(isBottomChromeVisible: true));
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('reader_chrome_immersive_toggle_button')),
        matching: find.byType(Icon),
      ),
    );
    expect(icon.icon, Icons.dock);
  });

  testWidgets('isBottomChromeVisible: false 時，⬓ 按鈕顯示外框 dock 圖示'
      '（2026-09-08 /grill-with-docs 使用者需求，取代眼睛圖示）', (tester) async {
    await tester.pumpWidget(buildTopBar(isBottomChromeVisible: false));
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('reader_chrome_immersive_toggle_button')),
        matching: find.byType(Icon),
      ),
    );
    expect(icon.icon, Icons.dock_outlined);
  });

  testWidgets('onTocTap 為 null 時，目錄按鈕為停用狀態', (tester) async {
    await tester.pumpWidget(buildTopBar(onTocTap: null));
    final button = tester.widget<IconButton>(
      find.byKey(const Key('reader_chrome_toc_button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('onTocTap 非 null 時，點擊目錄按鈕觸發它', (tester) async {
    var called = false;
    await tester.pumpWidget(buildTopBar(onTocTap: () => called = true));
    await tester.tap(find.byKey(const Key('reader_chrome_toc_button')));
    expect(called, isTrue);
  });

  testWidgets('showTtsIndicator: false 時，小喇叭圖示不存在', (tester) async {
    await tester.pumpWidget(buildTopBar(showTtsIndicator: false));
    expect(
      find.byKey(const Key('reader_chrome_tts_indicator_icon')),
      findsNothing,
    );
  });

  testWidgets('showTtsIndicator: true 時，小喇叭圖示存在', (tester) async {
    await tester.pumpWidget(buildTopBar(showTtsIndicator: true));
    expect(
      find.byKey(const Key('reader_chrome_tts_indicator_icon')),
      findsOneWidget,
    );
  });

  testWidgets('isEinkMode: true 時，觸控目標實際渲染尺寸為 56dp', (tester) async {
    await tester.pumpWidget(buildTopBar(isEinkMode: true));
    final size = tester.getSize(
      find.byKey(const Key('reader_chrome_back_button')),
    );
    expect(size.width, greaterThanOrEqualTo(56));
    expect(size.height, greaterThanOrEqualTo(56));
  });

  testWidgets('isEinkMode: false（預設）時，觸控目標為一般 48dp', (tester) async {
    await tester.pumpWidget(buildTopBar(isEinkMode: false));
    final size = tester.getSize(
      find.byKey(const Key('reader_chrome_back_button')),
    );
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.width, lessThan(56));
  });
}
