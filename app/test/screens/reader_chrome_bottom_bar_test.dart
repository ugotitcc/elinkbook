import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/reader_chrome_bottom_bar.dart';

void main() {
  Widget buildBottomBar({
    String bookTitle = '一弦定音',
    String pageProgressText = '184 / 468 · 39%',
    Widget? footer,
    bool isBookmarked = false,
    VoidCallback? onBookmarkTap,
    VoidCallback? onAnnotationsTap,
    VoidCallback? onLayoutTap,
    VoidCallback? onTtsTap,
    bool isEinkMode = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ReaderChromeBottomBar(
          bookTitle: bookTitle,
          pageProgressText: pageProgressText,
          footer: footer ?? const SizedBox.shrink(),
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
}
