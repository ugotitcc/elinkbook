import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/reader_chrome_top_bar.dart';
import 'package:elinkbook/l10n/app_localizations.dart';

void main() {
  Widget buildTopBar({
    VoidCallback? onBack,
    String chapterTitle = '第七章',
    VoidCallback? onSearchTap,
    bool isHeaderVisible = true,
    bool isToolbarVisible = true,
    bool isBottomChromeVisible = true,
    VoidCallback? onToggleBottomChrome,
    bool showTtsIndicator = false,
    bool isEinkMode = false,
    Locale locale = const Locale('zh', 'TW'),
  }) {
    return MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ReaderChromeTopBar(
          onBack: onBack ?? () {},
          chapterTitle: chapterTitle,
          onSearchTap: onSearchTap ?? () {},
          isHeaderVisible: isHeaderVisible,
          isToolbarVisible: isToolbarVisible,
          isBottomChromeVisible: isBottomChromeVisible,
          onToggleBottomChrome: onToggleBottomChrome ?? () {},
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

  // 2026-09-10 修正：頁首（標題文字）／工具列（返回/搜尋/⬓）拆成兩組各自
  // 獨立的顯示開關，理由與完整狀態表見 CONTEXT.md「Chrome Bar」詞條。
  // 目錄按鈕已移到 ReaderChromeBottomBar，相關測試搬到
  // reader_chrome_bottom_bar_test.dart。
  testWidgets('isHeaderVisible: false 時，標題文字不存在，但工具列按鈕仍在', (tester) async {
    await tester.pumpWidget(
      buildTopBar(chapterTitle: '第七章', isHeaderVisible: false),
    );
    expect(find.text('第七章'), findsNothing);
    expect(find.byKey(const Key('reader_chrome_back_button')), findsOneWidget);
    expect(
      find.byKey(const Key('reader_chrome_immersive_toggle_button')),
      findsOneWidget,
    );
  });

  testWidgets('isToolbarVisible: false 時，返回/搜尋/⬓ 按鈕不存在，但標題文字仍在', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTopBar(chapterTitle: '第七章', isToolbarVisible: false),
    );
    expect(find.text('第七章'), findsOneWidget);
    expect(find.byKey(const Key('reader_chrome_back_button')), findsNothing);
    expect(find.byKey(const Key('reader_chrome_search_button')), findsNothing);
    expect(
      find.byKey(const Key('reader_chrome_immersive_toggle_button')),
      findsNothing,
    );
  });

  testWidgets(
    'isHeaderVisible／isToolbarVisible／showTtsIndicator 皆為 false 時，整列不佔版面',
    (tester) async {
      await tester.pumpWidget(
        buildTopBar(
          isHeaderVisible: false,
          isToolbarVisible: false,
          showTtsIndicator: false,
        ),
      );
      final size = tester.getSize(find.byType(ReaderChromeTopBar));
      expect(size.height, 0);
    },
  );

  // 真機回報（2026-09-28）：「顯示頁首」開＋工具列收合時，頂部仍留一條
  // 空白色帶。原因是 2026-09-12 起 reader_screen 傳入的 chapterTitle 恆為
  // 空字串（頁首文字改由 _buildFoliateHeaderText 另外顯示），但本元件只看
  // isHeaderVisible 就決定要畫整條。標題是空的就等於沒有頁首可顯示。
  testWidgets(
    'isHeaderVisible: true 但標題為空、工具列收合、無 TTS 時，整列不佔版面',
    (tester) async {
      await tester.pumpWidget(
        buildTopBar(
          chapterTitle: '',
          isHeaderVisible: true,
          isToolbarVisible: false,
          showTtsIndicator: false,
        ),
      );
      final size = tester.getSize(find.byType(ReaderChromeTopBar));
      expect(size.height, 0);
    },
  );

  testWidgets('isToolbarVisible: false 時，showTtsIndicator 仍能顯示小喇叭圖示', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTopBar(isToolbarVisible: false, showTtsIndicator: true),
    );
    expect(
      find.byKey(const Key('reader_chrome_tts_indicator_icon')),
      findsOneWidget,
    );
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

  testWidgets('英文介面下返回/搜尋 tooltip 正確以英文渲染', (tester) async {
    await tester.pumpWidget(buildTopBar(locale: const Locale('en')));

    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Search in book'), findsOneWidget);
  });
}
