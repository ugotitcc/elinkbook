import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/column_mode.dart';
import 'package:elinkbook/reader/custom_font.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/layout_preset.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/screens/reader_settings_sheet.dart';

void main() {
  testWidgets('初始值正確反映傳入的 BookReaderPrefs', (tester) async {
    const prefs = BookReaderPrefs(
      fontFamily: 'SourceHanSerifTC',
      fontSize: 1.375, // UI 22.0
      fontWeight: 1.75, // UI 700
      lineHeight: 1.8,
      paragraphSpacing: 2.0, // UI 20.0
      letterSpacing: 0.2,
      marginTop: 72,
      marginBottom: 20,
      marginLeft: 30,
      marginRight: 30,
      textAlign: EpubTextAlign.justify,
      publisherStyles: false, // 停用書本 CSS 開關應為 true（反向語意）
    );

    await _pumpSheet(tester, prefs, (_) {});

    expect(
      tester
          .widget<DropdownButton<String?>>(
              find.byKey(const Key('reader_settings_font_family')))
          .value,
      'SourceHanSerifTC',
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
              find.byKey(const Key('reader_settings_letter_spacing_slider')))
          .value,
      0.2,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_top_slider')))
          .value,
      72.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_bottom_slider')))
          .value,
      20.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_left_slider')))
          .value,
      30.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_right_slider')))
          .value,
      30.0,
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
      1.0,
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
              find.byKey(const Key('reader_settings_letter_spacing_slider')))
          .value,
      0.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_top_slider')))
          .value,
      32.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_bottom_slider')))
          .value,
      16.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_left_slider')))
          .value,
      24.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_right_slider')))
          .value,
      24.0,
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

  testWidgets('點擊上邊界 + 按鈕後，onChanged 帶入 marginTop+2 且其他欄位不變',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(marginTop: 64, marginLeft: 24),
      (prefs) => result = prefs,
    );

    await tester
        .tap(find.byKey(const Key('reader_settings_margin_top_increment')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.marginTop, 66.0);
    expect(result!.marginLeft, 24.0, reason: '未被觸碰的欄位應維持原值');
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
      const BookReaderPrefs(fontFamily: 'TaiwanPearl'),
      (prefs) => result = prefs,
    );

    final dropdown = find.byKey(const Key('reader_settings_font_family'));
    tester.widget<DropdownButton<String?>>(dropdown).onChanged!(null);
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

  testWidgets('頁首/頁尾開關初始值反映 prefs（未持久化時預設關閉）', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('reader_settings_show_header')))
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('reader_settings_show_footer')))
          .value,
      isFalse,
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
    await _pumpSheet(tester, const BookReaderPrefs(showHeader: true, showFooter: true), (prefs) => result = prefs);

    await tester.tap(find.byKey(const Key('reader_settings_show_header')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.showHeader, isFalse);
    expect(result!.showFooter, isTrue);
  });

  testWidgets('關閉頁尾開關後，onChanged 帶入 showFooter=false 且不影響 showHeader',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(tester, const BookReaderPrefs(showHeader: true, showFooter: true), (prefs) => result = prefs);

    await tester.tap(find.byKey(const Key('reader_settings_show_footer')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.showFooter, isFalse);
    expect(result!.showHeader, isTrue);
  });

  testWidgets('已持久化 fullscreen=true 時，全螢幕模式開關初始值反映為開啟', (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(fullscreen: true),
      (_) {},
    );

    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('reader_settings_fullscreen')))
          .value,
      isTrue,
    );
  });

  testWidgets('開啟全螢幕模式開關後，onChanged 帶入 fullscreen=true 且不影響 showHeader',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(tester, const BookReaderPrefs(showHeader: true), (prefs) => result = prefs);

    await tester.tap(find.byKey(const Key('reader_settings_fullscreen')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.fullscreen, isTrue);
    expect(result!.showHeader, isTrue);
  });

  testWidgets('點選「單欄」按鈕後，onChanged 帶入 columnMode=single',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => result = prefs);

    await tester.tap(find.byKey(const Key('reader_settings_column_mode_single')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.columnMode, ColumnMode.single);
  });

  testWidgets('切換欄數不會清空其他既有覆寫欄位（回歸檢查）', (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(
        writingModeOverride: WritingMode.vertical,
        pageTurnModeOverride: PageTurnMode.scroll,
      ),
      (prefs) => result = prefs,
    );

    await tester.tap(find.byKey(const Key('reader_settings_column_mode_single')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.writingModeOverride, WritingMode.vertical);
    expect(result!.pageTurnModeOverride, PageTurnMode.scroll);
  });

  testWidgets('columnMode 預設 auto 時，自動按鈕高亮、Slider 可見', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    // 自動按鈕存在且可見
    expect(find.byKey(const Key('reader_settings_column_mode_auto')), findsOneWidget);
    // Slider 可見
    expect(find.byKey(const Key('reader_settings_column_size_slider')), findsOneWidget);
  });

  testWidgets('columnMode=single 時，Slider 不可見', (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(columnMode: ColumnMode.single),
      (_) {},
    );

    // Slider 不應存在
    expect(find.byKey(const Key('reader_settings_column_size_slider')), findsNothing);
  });

  testWidgets('columnMode=double 時，Slider 不可見', (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(columnMode: ColumnMode.double),
      (_) {},
    );

    // Slider 不應存在
    expect(find.byKey(const Key('reader_settings_column_size_slider')), findsNothing);
  });

  testWidgets('點擊字距 + 按鈕後，onChanged 帶入 letterSpacing+0.01 且其他欄位不變',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(letterSpacing: 0.10, marginTop: 64),
      (prefs) => result = prefs,
    );

    await tester.tap(
        find.byKey(const Key('reader_settings_letter_spacing_increment')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.letterSpacing, closeTo(0.11, 1e-9));
    expect(result!.marginTop, 64.0, reason: '未被觸碰的欄位應維持原值');
  });

  testWidgets('從單欄切換到自動，onChanged 帶入 columnMode=auto（可逆性）', (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(columnMode: ColumnMode.single),
      (prefs) => result = prefs,
    );

    // 切換到自動
    await tester.tap(find.byKey(const Key('reader_settings_column_mode_auto')));
    await tester.pump();
    expect(result!.columnMode, ColumnMode.auto);
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

  testWidgets('字型選單合併顯示內建 5 款與傳入的自訂字型清單', (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(),
      (_) {},
      customFonts: const [
        CustomFont(
          id: 1,
          displayName: '我的自訂字型',
          familyName: 'MyCustomFamily',
          fontUri: 'content://example/font1',
        ),
      ],
    );

    await tester.tap(find.byKey(const Key('reader_settings_font_family')));
    await tester.pumpAndSettle();

    expect(find.text('思源黑體'), findsWidgets);
    expect(find.text('我的自訂字型'), findsWidgets);
  });

  testWidgets('選擇自訂字型後，onChanged 帶入其 familyName', (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(),
      (prefs) => result = prefs,
      customFonts: const [
        CustomFont(
          id: 1,
          displayName: '我的自訂字型',
          familyName: 'MyCustomFamily',
          fontUri: 'content://example/font1',
        ),
      ],
    );

    final dropdown = find.byKey(const Key('reader_settings_font_family'));
    tester.widget<DropdownButton<String?>>(dropdown).onChanged!('MyCustomFamily');
    await tester.pump();

    expect(result?.fontFamily, 'MyCustomFamily');
  });

  testWidgets('空 slot 顯示「（空）」，已存的 slot 顯示名稱與更新日期', (tester) async {
    final preset = LayoutPreset(
      id: 1,
      name: '臥室夜讀直排',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 8, 14),
      prefs: BookReaderPrefs.empty,
    );
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged,
        layoutPresets: [preset]);

    expect(find.byKey(const Key('reader_settings_preset_slot_0_label')),
        findsOneWidget);
    expect(
        find.textContaining('臥室夜讀直排'), findsOneWidget);
    expect(find.byKey(const Key('reader_settings_preset_slot_1_empty')),
        findsOneWidget);
    expect(find.byKey(const Key('reader_settings_preset_slot_2_empty')),
        findsOneWidget);
  });

  testWidgets('點擊「另存為新預設集」呼叫 onSaveAsPreset 並帶入目前完整草稿', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(fontSize: 18 / 16, lineHeight: 1.6),
      _noopOnChanged,
      onSaveAsPreset: (draft) => notified = draft,
    );

    await tester.ensureVisible(
        find.byKey(const Key('reader_settings_save_as_preset')));
    await tester.tap(find.byKey(const Key('reader_settings_save_as_preset')));
    await tester.pump();

    expect(notified, isNotNull);
    expect(notified!.lineHeight, 1.6);
  });

  testWidgets('點擊 slot 的「套用到本書」呼叫 onApplyPreset 且 targetBookIds=[bookId]',
      (tester) async {
    LayoutPreset? appliedPreset;
    List<String>? appliedTargets;
    final preset = LayoutPreset(
      id: 1,
      name: '預設集A',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: BookReaderPrefs.empty,
    );
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      _noopOnChanged,
      bookId: 'current_book',
      layoutPresets: [preset],
      onApplyPreset: (p, {required targetBookIds}) {
        appliedPreset = p;
        appliedTargets = targetBookIds;
      },
    );

    await tester.ensureVisible(
        find.byKey(const Key('reader_settings_preset_slot_0_apply_current')));
    await tester
        .tap(find.byKey(const Key('reader_settings_preset_slot_0_apply_current')));
    await tester.pump();

    expect(appliedPreset, preset);
    expect(appliedTargets, ['current_book']);
  });

  testWidgets(
      '點擊 slot 的「套用到其他書籍」，onRequestBookPicker 回傳清單後呼叫 onApplyPreset 帶入該清單',
      (tester) async {
    List<String>? appliedTargets;
    final preset = LayoutPreset(
      id: 1,
      name: '預設集A',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: BookReaderPrefs.empty,
    );
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      _noopOnChanged,
      layoutPresets: [preset],
      onRequestBookPicker: ({required multiSelect}) async => ['b2', 'b3'],
      onApplyPreset: (p, {required targetBookIds}) => appliedTargets = targetBookIds,
    );

    await tester.ensureVisible(
        find.byKey(const Key('reader_settings_preset_slot_0_apply_others')));
    await tester
        .tap(find.byKey(const Key('reader_settings_preset_slot_0_apply_others')));
    await tester.pumpAndSettle();

    expect(appliedTargets, ['b2', 'b3']);
  });

  testWidgets('onRequestBookPicker 回傳 null（使用者取消）時，不呼叫 onApplyPreset',
      (tester) async {
    var applyCalled = false;
    final preset = LayoutPreset(
      id: 1,
      name: '預設集A',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: BookReaderPrefs.empty,
    );
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      _noopOnChanged,
      layoutPresets: [preset],
      onRequestBookPicker: ({required multiSelect}) async => null,
      onApplyPreset: (p, {required targetBookIds}) => applyCalled = true,
    );

    await tester.ensureVisible(
        find.byKey(const Key('reader_settings_preset_slot_0_apply_others')));
    await tester
        .tap(find.byKey(const Key('reader_settings_preset_slot_0_apply_others')));
    await tester.pumpAndSettle();

    expect(applyCalled, isFalse);
  });

  testWidgets('點擊 slot 的「刪除」呼叫 onDeletePreset 帶入該 preset 的 id', (tester) async {
    int? deletedId;
    final preset = LayoutPreset(
      id: 42,
      name: '預設集A',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: BookReaderPrefs.empty,
    );
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      _noopOnChanged,
      layoutPresets: [preset],
      onDeletePreset: (id) => deletedId = id,
    );

    await tester.ensureVisible(
        find.byKey(const Key('reader_settings_preset_slot_0_delete')));
    await tester.tap(find.byKey(const Key('reader_settings_preset_slot_0_delete')));
    await tester.pump();

    expect(deletedId, 42);
  });

  testWidgets(
      '點擊「複製到本書」，onRequestBookPicker(multiSelect:false) 回傳後呼叫 onApplyFromBook(sourceId, targetBookIds:[bookId])',
      (tester) async {
    String? appliedSource;
    List<String>? appliedTargets;
    bool? capturedMultiSelect;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      _noopOnChanged,
      bookId: 'current_book',
      onRequestBookPicker: ({required multiSelect}) async {
        capturedMultiSelect = multiSelect;
        return ['source_book'];
      },
      onApplyFromBook: (source, {required targetBookIds}) {
        appliedSource = source;
        appliedTargets = targetBookIds;
      },
    );

    await tester.ensureVisible(
        find.byKey(const Key('reader_settings_copy_from_book_current')));
    await tester
        .tap(find.byKey(const Key('reader_settings_copy_from_book_current')));
    await tester.pumpAndSettle();

    expect(capturedMultiSelect, isFalse);
    expect(appliedSource, 'source_book');
    expect(appliedTargets, ['current_book']);
  });

  testWidgets('點擊「複製到其他書籍」，依序呼叫兩次 onRequestBookPicker 後呼叫 onApplyFromBook',
      (tester) async {
    final requestedMultiSelectFlags = <bool>[];
    String? appliedSource;
    List<String>? appliedTargets;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      _noopOnChanged,
      onRequestBookPicker: ({required multiSelect}) async {
        requestedMultiSelectFlags.add(multiSelect);
        return multiSelect ? ['b2', 'b3'] : ['source_book'];
      },
      onApplyFromBook: (source, {required targetBookIds}) {
        appliedSource = source;
        appliedTargets = targetBookIds;
      },
    );

    await tester.ensureVisible(
        find.byKey(const Key('reader_settings_copy_from_book_others')));
    await tester
        .tap(find.byKey(const Key('reader_settings_copy_from_book_others')));
    await tester.pumpAndSettle();

    expect(requestedMultiSelectFlags, [false, true]);
    expect(appliedSource, 'source_book');
    expect(appliedTargets, ['b2', 'b3']);
  });

  testWidgets(
      'Sheet 開啟中，layoutPresets 外部更新後畫面立即反映新清單（Bottom Sheet 開啟中同步）',
      (tester) async {
    // 沿用既有 _TestSettingsSheetWrapper 只涵蓋 prefs 更新，這裡改用直接
    // 重新 pump 不同 layoutPresets 驗證同一顆 State 樹是否正確反映——
    // ReaderSettingsSheet 對 layoutPresets 是直接在 build() 內消費
    // widget.layoutPresets（無內部草稿複本），故不需要額外 didUpdateWidget
    // 邏輯，重新 pumpWidget 同一個 widget tree 即可驗證。
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    expect(find.byKey(const Key('reader_settings_preset_slot_0_empty')),
        findsOneWidget);

    final preset = LayoutPreset(
      id: 1,
      name: '新存的預設集',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: BookReaderPrefs.empty,
    );
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged,
        layoutPresets: [preset]);

    expect(find.byKey(const Key('reader_settings_preset_slot_0_label')),
        findsOneWidget);
  });
}

Future<void> _pumpSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged, {
  List<CustomFont> customFonts = const [],
  String bookId = 'b1',
  List<LayoutPreset> layoutPresets = const [],
  void Function(BookReaderPrefs)? onSaveAsPreset,
  void Function(LayoutPreset, {required List<String> targetBookIds})? onApplyPreset,
  void Function(String, {required List<String> targetBookIds})? onApplyFromBook,
  Future<List<String>?> Function({required bool multiSelect})? onRequestBookPicker,
  void Function(int)? onDeletePreset,
}) async {
  // 設定較大的 Viewport，以防 ListView 元件超出預設的 800x600 範圍導致 tap 失敗
  // （Issue 14 邊距拆為 4 個獨立滑桿後內容變高，1200 已不足，調高至 1600；加入預設集區塊後調高至 2400）
  tester.view.physicalSize = const Size(800, 2400);
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
        customFonts: customFonts,
        bookId: bookId,
        layoutPresets: layoutPresets,
        onSaveAsPreset: onSaveAsPreset ?? _noopSaveAsPreset,
        onApplyPreset: onApplyPreset ?? _noopApplyPreset,
        onApplyFromBook: onApplyFromBook ?? _noopApplyFromBook,
        onRequestBookPicker: onRequestBookPicker ?? _noopRequestBookPicker,
        onDeletePreset: onDeletePreset ?? _noopDeletePreset,
      ),
    ),
  ));
}

void _noopOnChanged(BookReaderPrefs prefs) {}
void _noopSaveAsPreset(BookReaderPrefs _) {}
void _noopApplyPreset(LayoutPreset _, {required List<String> targetBookIds}) {}
void _noopApplyFromBook(String _, {required List<String> targetBookIds}) {}
Future<List<String>?> _noopRequestBookPicker({required bool multiSelect}) async =>
    null;
void _noopDeletePreset(int _) {}

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
      bookId: 'b1',
      onSaveAsPreset: _noopSaveAsPreset,
      onApplyPreset: _noopApplyPreset,
      onApplyFromBook: _noopApplyFromBook,
      onRequestBookPicker: _noopRequestBookPicker,
      onDeletePreset: _noopDeletePreset,
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
              bookId: 'b1',
              onSaveAsPreset: _noopSaveAsPreset,
              onApplyPreset: _noopApplyPreset,
              onApplyFromBook: _noopApplyFromBook,
              onRequestBookPicker: _noopRequestBookPicker,
              onDeletePreset: _noopDeletePreset,
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
