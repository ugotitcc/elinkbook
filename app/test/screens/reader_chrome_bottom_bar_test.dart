import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/reader_chrome_bottom_bar.dart';
import 'package:elinkbook/l10n/app_localizations.dart';

void main() {
  Widget buildBottomBar({
    String bookTitle = '一弦定音',
    String pageProgressText = '184 / 468 · 39%',
    Widget? footer,
    VoidCallback? onTocTap,
    bool isBookmarked = false,
    VoidCallback? onBookmarkTap,
    VoidCallback? onAnnotationsTap,
    VoidCallback? onLayoutTap,
    VoidCallback? onTtsTap,
    bool isEinkMode = false,
    Locale locale = const Locale('zh', 'TW'),
  }) {
    return MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ReaderChromeBottomBar(
          bookTitle: bookTitle,
          pageProgressText: pageProgressText,
          footer: footer ?? const SizedBox.shrink(),
          onTocTap: onTocTap,
          isBookmarked: isBookmarked,
          onBookmarkTap: onBookmarkTap,
          onAnnotationsTap: onAnnotationsTap,
          onLayoutTap: onLayoutTap,
          onTtsTap: onTtsTap,
          backgroundColor: Colors.white,
          iconColor: Colors.black,
          isEinkMode: isEinkMode,
        ),
      ),
    );
  }

  testWidgets('顯示書名與頁碼進度文字', (tester) async {
    await tester.pumpWidget(
      buildBottomBar(bookTitle: '一弦定音', pageProgressText: '184 / 468 · 39%'),
    );
    expect(find.text('一弦定音'), findsOneWidget);
    expect(find.text('184 / 468 · 39%'), findsOneWidget);
  });

  testWidgets('顯示呼叫端傳入的 footer widget', (tester) async {
    await tester.pumpWidget(
      buildBottomBar(footer: const Text('假跳頁列內容')),
    );
    expect(find.text('假跳頁列內容'), findsOneWidget);
  });

  // 2026-09-10：目錄按鈕從 ReaderChromeTopBar 移到本選單列最左側（書籤
  // 按鈕左邊），理由與完整狀態表見 CONTEXT.md「Chrome Bar」詞條。
  testWidgets('onTocTap 為 null 時，目錄按鈕為停用狀態（仍渲染）', (tester) async {
    await tester.pumpWidget(buildBottomBar(onTocTap: null));
    expect(find.byKey(const Key('reader_chrome_toc_button')), findsOneWidget);
    final button = tester.widget<IconButton>(
      find.byKey(const Key('reader_chrome_toc_button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('點擊目錄按鈕觸發 onTocTap', (tester) async {
    var called = false;
    await tester.pumpWidget(buildBottomBar(onTocTap: () => called = true));
    await tester.tap(find.byKey(const Key('reader_chrome_toc_button')));
    expect(called, isTrue);
  });

  testWidgets('目錄按鈕排在書籤按鈕左側', (tester) async {
    await tester.pumpWidget(buildBottomBar(onTocTap: () {}));
    final tocX = tester
        .getTopLeft(find.byKey(const Key('reader_chrome_toc_button')))
        .dx;
    final bookmarkX = tester
        .getTopLeft(find.byKey(const Key('reader_chrome_bookmark_button')))
        .dx;
    expect(tocX, lessThan(bookmarkX));
  });

  testWidgets('onBookmarkTap 為 null 時，書籤按鈕為停用狀態（仍渲染）', (tester) async {
    await tester.pumpWidget(buildBottomBar(onBookmarkTap: null));
    expect(find.byKey(const Key('reader_chrome_bookmark_button')), findsOneWidget);
    final button = tester.widget<IconButton>(
      find.byKey(const Key('reader_chrome_bookmark_button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('點擊書籤按鈕觸發 onBookmarkTap', (tester) async {
    var called = false;
    await tester.pumpWidget(buildBottomBar(onBookmarkTap: () => called = true));
    await tester.tap(find.byKey(const Key('reader_chrome_bookmark_button')));
    expect(called, isTrue);
  });

  testWidgets('點擊劃線筆記按鈕觸發 onAnnotationsTap', (tester) async {
    var called = false;
    await tester.pumpWidget(
      buildBottomBar(onAnnotationsTap: () => called = true),
    );
    await tester.tap(find.byKey(const Key('reader_chrome_annotations_button')));
    expect(called, isTrue);
  });

  testWidgets('點擊版面按鈕觸發 onLayoutTap', (tester) async {
    var called = false;
    await tester.pumpWidget(buildBottomBar(onLayoutTap: () => called = true));
    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    expect(called, isTrue);
  });

  testWidgets('onTtsTap 為 null 時，朗讀按鈕整項不渲染', (tester) async {
    await tester.pumpWidget(buildBottomBar(onTtsTap: null));
    expect(find.byKey(const Key('reader_chrome_tts_button')), findsNothing);
  });

  testWidgets('onTtsTap 非 null 時，點擊朗讀按鈕觸發它', (tester) async {
    var called = false;
    await tester.pumpWidget(buildBottomBar(onTtsTap: () => called = true));
    expect(find.byKey(const Key('reader_chrome_tts_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader_chrome_tts_button')));
    expect(called, isTrue);
  });

  // 審查修正（review-issue-1.md I-1）：比照 reader_chrome_top_bar_test.dart
  // 既有的 isEinkMode 觸控目標尺寸測試，補上選單列按鈕的等價防護。只驗證
  // 高度——選單列每顆按鈕外層包了 Expanded，寬度會被拉伸至平分整列可用
  // 寬度，不反映 minimumSize 建構參數，只有高度（Row 的 cross axis，不受
  // Expanded 影響）才是 minimumSize 生效與否的可靠訊號。
  testWidgets('isEinkMode: true 時，選單列按鈕觸控目標實際渲染高度為 56dp', (tester) async {
    await tester.pumpWidget(
      buildBottomBar(isEinkMode: true, onBookmarkTap: () {}),
    );
    final size = tester.getSize(
      find.byKey(const Key('reader_chrome_bookmark_button')),
    );
    expect(size.height, greaterThanOrEqualTo(56));
  });

  testWidgets('isEinkMode: false（預設）時，選單列按鈕觸控目標高度為一般 48dp', (tester) async {
    await tester.pumpWidget(
      buildBottomBar(isEinkMode: false, onBookmarkTap: () {}),
    );
    final size = tester.getSize(
      find.byKey(const Key('reader_chrome_bookmark_button')),
    );
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.height, lessThan(56));
  });

  testWidgets('英文介面下選單列 tooltip 正確以英文渲染', (tester) async {
    await tester.pumpWidget(
      buildBottomBar(
        locale: const Locale('en'),
        onTocTap: () {},
        onBookmarkTap: () {},
        onAnnotationsTap: () {},
        onLayoutTap: () {},
        onTtsTap: () {},
      ),
    );

    expect(find.byTooltip('Table of contents'), findsOneWidget);
    expect(find.byTooltip('Highlights & notes'), findsOneWidget);
    expect(find.byTooltip('Layout'), findsOneWidget);
    expect(find.byTooltip('Read aloud'), findsOneWidget);
  });

  // 真機回報（2026-09-28，Mobiscribe）：E-Ink 模式下底部列是黑底白字
  // （backgroundColor=onSurface／iconColor=surface），但跳頁列裡的
  // Slider／頁碼文字／跳頁輸入框沿用全域主題的黑色前景，黑畫在黑上幾乎
  // 看不到。footer 內的前景色必須改跟 iconColor 走。
  testWidgets('E-Ink 模式：跳頁列的滑桿、頁碼文字、輸入框都改用 iconColor',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ReaderChromeBottomBar(
          bookTitle: '書',
          pageProgressText: '23 / 28 · 82%',
          footer: Row(
            children: [
              const Text('23/28'),
              const SizedBox(width: 56, child: TextField()),
              Expanded(
                child: Slider(value: 23, min: 1, max: 28, onChanged: (_) {}),
              ),
            ],
          ),
          onTocTap: () {},
          isBookmarked: false,
          onBookmarkTap: () {},
          onAnnotationsTap: () {},
          onLayoutTap: () {},
          onTtsTap: null,
          backgroundColor: Colors.black,
          iconColor: Colors.white,
          isEinkMode: true,
        ),
      ),
    ));

    final sliderContext = tester.element(find.byType(Slider));
    final sliderTheme = SliderTheme.of(sliderContext);
    expect(sliderTheme.activeTrackColor, Colors.white);
    expect(sliderTheme.thumbColor, Colors.white);
    // 未讀部分也要跟黑底有明顯對比，且不可用半透明（電子紙灰階抖動問題）。
    expect(sliderTheme.inactiveTrackColor, isNot(Colors.black));
    expect(sliderTheme.inactiveTrackColor!.a, 1.0);

    final pageText = tester.widget<RichText>(
      find.descendant(of: find.text('23/28'), matching: find.byType(RichText)),
    );
    expect(pageText.text.style?.color, Colors.white);

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.style.color, Colors.white);
  });
}
