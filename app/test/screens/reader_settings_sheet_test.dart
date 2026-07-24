import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/screens/reader_settings_sheet.dart';

void main() {
  testWidgets('初始值正確反映傳入的 BookReaderPrefs', (tester) async {
    const prefs = BookReaderPrefs(
      fontFamily: AppFont.sourceHanSerif,
      fontSize: 1.375, // UI 22.0
      fontWeight: 1.75, // UI 700
      lineHeight: 1.8,
      paragraphSpacing: 2.0, // UI 20.0
      pageMargins: 1.6667, // UI 25.0
      textAlign: EpubTextAlign.justify,
      publisherStyles: false, // 停用書本 CSS 開關應為 true（反向語意）
    );

    await _pumpSheet(tester, prefs, (_) {});

    expect(
      tester
          .widget<DropdownButton<AppFont?>>(
              find.byKey(const Key('reader_settings_font_family')))
          .value,
      AppFont.sourceHanSerif,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_font_size_slider')))
          .value,
      22.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_font_weight_slider')))
          .value,
      700.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_line_height_slider')))
          .value,
      1.8,
    );
    expect(
      tester
          .widget<Slider>(find
              .byKey(const Key('reader_settings_paragraph_spacing_slider')))
          .value,
      20.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_page_margins_slider')))
          .value,
      25.0,
    );
    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('reader_settings_disable_book_css')))
          .value,
      true,
    );
  });

  testWidgets('任一欄位為 null 時，滑桿顯示原型範例預設值', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);

    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_font_size_slider')))
          .value,
      16.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_font_weight_slider')))
          .value,
      400.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_line_height_slider')))
          .value,
      1.5,
    );
    expect(
      tester
          .widget<Slider>(find
              .byKey(const Key('reader_settings_paragraph_spacing_slider')))
          .value,
      10.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_page_margins_slider')))
          .value,
      15.0,
    );
    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('reader_settings_disable_book_css')))
          .value,
      false,
    );
  });

  testWidgets('點擊字型大小 + 按鈕後，onChanged 帶入 fontSize+1 且其他欄位不變',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(fontSize: 1.25, lineHeight: 1.6), // UI 20.0
      (prefs) => result = prefs,
    );

    await tester
        .tap(find.byKey(const Key('reader_settings_font_size_increment')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.fontSize, 1.3125); // UI 21.0
    expect(result!.lineHeight, 1.6, reason: '未被觸碰的欄位應維持原值');
  });

  testWidgets('拖動字重滑桿到 UI 值 700 時，onChanged 帶入換算後的倍率 1.75',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => result = prefs,
    );

    final slider = find.byKey(const Key('reader_settings_font_weight_slider'));
    // 從 UI 400 直接設為 UI 700：呼叫 Slider 的 onChanged 回呼比模擬實際
    // 拖曳手勢更精準可靠（Slider 版面在 flutter test 環境下的實際像素
    // 拖曳距離換算容易受畫面尺寸影響）。
    tester.widget<Slider>(slider).onChanged!(700);
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.fontWeight, 1.75);
  });

  testWidgets('選擇字型下拉選單「使用書本內建字型」後，onChanged 帶入 fontFamily=null',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(fontFamily: AppFont.taiwanPearl),
      (prefs) => result = prefs,
    );

    final dropdown = find.byKey(const Key('reader_settings_font_family'));
    tester.widget<DropdownButton<AppFont?>>(dropdown).onChanged!(null);
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.fontFamily, isNull);
  });

  testWidgets('點擊文字對齊「置中」圖示後，onChanged 帶入 EpubTextAlign.center',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => result = prefs,
    );

    await tester
        .tap(find.byKey(const Key('reader_settings_text_align_center')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.textAlign, EpubTextAlign.center);
  });

  testWidgets('切換「停用書本 CSS」開關後，onChanged 帶入反向的 publisherStyles',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => result = prefs,
    );

    await tester
        .tap(find.byKey(const Key('reader_settings_disable_book_css')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.publisherStyles, false, reason: '停用書本 CSS 開啟＝不使用書本樣式');
  });

  testWidgets('任一控制項互動後，writingModeOverride/pageTurnModeOverride/'
      'screenOrientationOverride 三個 Issue 4 欄位維持原值不被清空',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(
        writingModeOverride: WritingMode.vertical,
        pageTurnModeOverride: PageTurnMode.scroll,
      ),
      (prefs) => result = prefs,
    );

    await tester
        .tap(find.byKey(const Key('reader_settings_text_align_justify')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.writingModeOverride, WritingMode.vertical);
    expect(result!.pageTurnModeOverride, PageTurnMode.scroll);
  });

  testWidgets('當外部 prefs 更新時，應透過 didUpdateWidget 同步 UI state', (tester) async {
    late void Function(BookReaderPrefs) updatePrefs;
    
    // 設定較大的 Viewport
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: _TestSettingsSheetWrapper(
          initialPrefs: const BookReaderPrefs(fontSize: 1.25), // UI 20.0
          onWrapperCreated: (updateFn) => updatePrefs = updateFn,
        ),
      ),
    ));

    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_font_size_slider')))
          .value,
      20.0,
    );

    updatePrefs(const BookReaderPrefs(fontSize: 1.5625)); // UI 25.0
    await tester.pump();

    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_font_size_slider')))
          .value,
      25.0,
    );
  });

  testWidgets(
      'writingModeOverride 初始為 vertical 時，點擊「採用書籍排版」圖示後，'
      'onChanged 帶入 null', (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(
        writingModeOverride: WritingMode.vertical,
      ),
      (prefs) => result = prefs,
    );

    await tester
        .tap(find.byKey(const Key('reader_settings_writing_mode_book')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.writingModeOverride, isNull);
  });

  testWidgets(
      'writingModeOverride 初始為 null 時，點擊「強制直排」圖示後，'
      'onChanged 帶入 WritingMode.vertical', (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => result = prefs,
    );

    await tester.tap(
        find.byKey(const Key('reader_settings_writing_mode_vertical')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.writingModeOverride, WritingMode.vertical);
  });

  testWidgets('點擊「滾動翻頁」圖示後，onChanged 帶入 PageTurnMode.scroll',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => result = prefs,
    );

    await tester
        .tap(find.byKey(const Key('reader_settings_page_turn_mode_scroll')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.pageTurnModeOverride, PageTurnMode.scroll);
  });

  testWidgets(
      '點擊「鎖定 90°」圖示後，onChanged 帶入 ScreenOrientationSetting.lock90',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => result = prefs,
    );

    await tester.tap(
        find.byKey(const Key('reader_settings_screen_orientation_lock90')));
    await tester.pump();

    expect(result, isNotNull);
    expect(
      result!.screenOrientationOverride,
      ScreenOrientationSetting.lock90,
    );
  });

  testWidgets(
      '點擊排版方向覆寫圖示後，pageTurnModeOverride／screenOrientationOverride '
      '維持原值不被清空', (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(
        pageTurnModeOverride: PageTurnMode.scroll,
        screenOrientationOverride: ScreenOrientationSetting.lock180,
      ),
      (prefs) => result = prefs,
    );

    await tester.tap(
        find.byKey(const Key('reader_settings_writing_mode_horizontal')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.pageTurnModeOverride, PageTurnMode.scroll);
    expect(
      result!.screenOrientationOverride,
      ScreenOrientationSetting.lock180,
    );
  });

  testWidgets('頁首/頁尾開關初始值反映 prefs（未持久化時預設開啟）', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('reader_settings_show_header')))
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('reader_settings_show_footer')))
          .value,
      isTrue,
    );
  });

  testWidgets('已持久化 showHeader=false 時，頁首開關初始值反映為關閉', (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(showHeader: false),
      (_) {},
    );

    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('reader_settings_show_header')))
          .value,
      isFalse,
    );
  });

  testWidgets('關閉頁首開關後，onChanged 帶入 showHeader=false 且不影響 showFooter',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => result = prefs);

    await tester.tap(find.byKey(const Key('reader_settings_show_header')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.showHeader, isFalse);
    expect(result!.showFooter, isTrue);
  });

  testWidgets('關閉頁尾開關後，onChanged 帶入 showFooter=false 且不影響 showHeader',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => result = prefs);

    await tester.tap(find.byKey(const Key('reader_settings_show_footer')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.showFooter, isFalse);
    expect(result!.showHeader, isTrue);
  });

  testWidgets('切換頁首/頁尾開關不會清空其他既有覆寫欄位（回歸檢查）', (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(
        writingModeOverride: WritingMode.vertical,
        pageTurnModeOverride: PageTurnMode.scroll,
      ),
      (prefs) => result = prefs,
    );

    await tester.tap(find.byKey(const Key('reader_settings_show_header')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.writingModeOverride, WritingMode.vertical);
    expect(result!.pageTurnModeOverride, PageTurnMode.scroll);
  });

  testWidgets('點擊關閉按鈕後，Bottom Sheet 關閉（Navigator.pop 生效）', (tester) async {
    await _pumpModalSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(find.byType(ReaderSettingsSheet), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader_settings_close_button')));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderSettingsSheet), findsNothing);
  });

  testWidgets('內容超出小螢幕視窗高度並捲動內容後，關閉按鈕位置維持不變（未被捲出畫面）',
      (tester) async {
    tester.view.physicalSize = const Size(400, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _pumpModalSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(find.byKey(const Key('reader_settings_close_button')), findsOneWidget);
    final beforeScroll = tester.getTopLeft(
      find.byKey(const Key('reader_settings_close_button')),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();

    expect(find.byKey(const Key('reader_settings_close_button')), findsOneWidget);
    final afterScroll = tester.getTopLeft(
      find.byKey(const Key('reader_settings_close_button')),
    );
    expect(afterScroll, beforeScroll,
        reason: '關閉列在 Column 頂端、ListView 之外，捲動內部 ListView 不應移動它的位置');
  });

  testWidgets('內容小於可用高度時，Bottom Sheet 保持緊湊包裹（不撐滿刻意放大的可用高度）',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _pumpModalSheet(tester, BookReaderPrefs.empty, (_) {});

    final sheetHeight = tester.getSize(find.byType(ReaderSettingsSheet)).height;
    expect(sheetHeight, lessThan(2500),
        reason:
            'mainAxisSize.min 應讓內容較短時 Sheet 緊湊包裹，不應撐滿刻意放大的可用高度 3000');
  });
}

Future<void> _pumpSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged,
) async {
  // 設定較大的 Viewport，以防 ListView 元件超出預設的 800x600 範圍導致 tap 失敗
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ReaderSettingsSheet(
        prefs: prefs,
        onChanged: onChanged,
      ),
    ),
  ));
}

void _noopOnChanged(BookReaderPrefs prefs) {}

class _TestSettingsSheetWrapper extends StatefulWidget {
  final BookReaderPrefs initialPrefs;
  final void Function(void Function(BookReaderPrefs)) onWrapperCreated;

  const _TestSettingsSheetWrapper({
    required this.initialPrefs,
    required this.onWrapperCreated,
  });

  @override
  State<_TestSettingsSheetWrapper> createState() => _TestSettingsSheetWrapperState();
}

class _TestSettingsSheetWrapperState extends State<_TestSettingsSheetWrapper> {
  late BookReaderPrefs _prefs;

  @override
  void initState() {
    super.initState();
    _prefs = widget.initialPrefs;
    widget.onWrapperCreated((newPrefs) {
      setState(() {
        _prefs = newPrefs;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ReaderSettingsSheet(
      prefs: _prefs,
      onChanged: (_) {},
    );
  }
}

Future<void> _pumpModalSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            enableDrag: false,
            builder: (_) => ReaderSettingsSheet(
              prefs: prefs,
              onChanged: onChanged,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
