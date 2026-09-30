import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/available_fonts.dart';
import 'package:elinkbook/reader/column_mode.dart';
import 'package:elinkbook/reader/custom_font.dart';
import 'package:elinkbook/screens/widgets/reader_option_tile.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/layout_preset.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/screens/reader_settings_sheet.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

const _activeDraftPrefs = BookReaderPrefs(
  marginTop: 32.0,
  marginBottom: 16.0,
  marginLeft: 24.0,
  marginRight: 24.0,
  publisherStyles: true,
  showHeader: false,
  showFooter: false,
  fullscreen: false,
  columnMode: ColumnMode.auto,
  columnSize: 720.0,
);

void main() {
  testWidgets(
      '4 個頁籤皆可切換，切換後對應欄位的既有 Key 可見、其餘頁籤內容不可見'
      '（epic-28-reader-settings-enhancements Issue 5）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);

    // 預設應停在「文字」頁籤（index 0）。
    expect(find.byKey(const Key('reader_settings_font_size_slider')),
        findsOneWidget);
    expect(find.byKey(const Key('reader_settings_margin_top_slider')),
        findsNothing);

    await switchToTab(tester, '邊界');
    expect(find.byKey(const Key('reader_settings_margin_top_slider')),
        findsOneWidget);
    expect(find.byKey(const Key('reader_settings_font_size_slider')),
        findsNothing);

    await switchToTab(tester, '呈現');
    expect(
        find.byKey(const Key('reader_settings_fullscreen')), findsOneWidget);
    expect(find.byKey(const Key('reader_settings_margin_top_slider')),
        findsNothing);

    await switchToTab(tester, '預設集');
    expect(find.byKey(const Key('reader_settings_save_as_preset')),
        findsOneWidget);
    expect(
        find.byKey(const Key('reader_settings_fullscreen')), findsNothing);

    await switchToTab(tester, '文字');
    expect(find.byKey(const Key('reader_settings_font_size_slider')),
        findsOneWidget);
    expect(find.byKey(const Key('reader_settings_save_as_preset')),
        findsNothing);
  });

  testWidgets(
      '在「文字」頁籤內對 Slider 做橫向拖曳手勢，頁籤不會被意外切換'
      '（epic-28-reader-settings-enhancements Issue 5：TabBarView 需設定 '
      'NeverScrollableScrollPhysics，避免與 Slider 搶手勢競技場）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);

    final tabController = DefaultTabController.of(
      tester.element(find.byKey(const Key('reader_settings_font_size_slider'))),
    );
    expect(tabController.index, 0);

    await tester.drag(
      find.byKey(const Key('reader_settings_font_size_slider')),
      const Offset(200, 0),
    );
    await tester.pump();

    expect(tabController.index, 0,
        reason: '對 Slider 的橫向拖曳應被 Slider 自己吃掉並調整數值，不應被 TabBarView '
            '判定為切換頁籤手勢');
  });

  testWidgets(
      '在「邊界」頁籤內對邊界 Slider 做橫向拖曳手勢，頁籤不會被意外切換'
      '（epic-28-reader-settings-enhancements Issue 5）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    await switchToTab(tester, '邊界');

    final tabController = DefaultTabController.of(
      tester.element(find.byKey(const Key('reader_settings_margin_top_slider'))),
    );
    expect(tabController.index, 1);

    await tester.drag(
      find.byKey(const Key('reader_settings_margin_top_slider')),
      const Offset(200, 0),
    );
    await tester.pump();

    expect(tabController.index, 1);
  });

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

    // 「文字」頁籤（預設）。
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
          .widget<SwitchListTile>(
              find.byKey(const Key('reader_settings_disable_book_css')))
          .value,
      true,
    );

    // 「邊界」頁籤。
    await switchToTab(tester, '邊界');
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
  });

  testWidgets('任一欄位為 null 時，滑桿顯示原型範例預設值', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);

    // 「文字」頁籤（預設）。
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
          .widget<SwitchListTile>(
              find.byKey(const Key('reader_settings_disable_book_css')))
          .value,
      false,
    );

    // 「邊界」頁籤。
    await switchToTab(tester, '邊界');
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
  });

  testWidgets(
      '只切換「顯示頁首」開關，onChanged 帶出的字級/粗細/行高/段落間距/字距皆維持 null'
      '（epic-28-reader-settings-enhancements Issue 4：草稿具現化不應覆寫書本原生樣式）',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => result = prefs,
    );
    await switchToTab(tester, '邊界');

    await tester.tap(find.byKey(const Key('reader_settings_show_header')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.showHeader, isTrue);
    expect(result!.fontSize, isNull,
        reason: '使用者從未調整過字級，不應被草稿具現化悄悄寫入');
    expect(result!.fontWeight, isNull,
        reason: '使用者從未調整過字型粗細，不應被草稿具現化悄悄寫入');
    expect(result!.lineHeight, isNull,
        reason: '使用者從未調整過行高，不應被草稿具現化悄悄寫入');
    expect(result!.paragraphSpacing, isNull,
        reason: '使用者從未調整過段落間距，不應被草稿具現化悄悄寫入');
    expect(result!.letterSpacing, isNull,
        reason: '使用者從未調整過字距，不應被草稿具現化悄悄寫入');
  });

  testWidgets(
      '只調整字距 + 按鈕，onChanged 帶出的字級/粗細/行高/段落間距仍維持 null，'
      '只有字距被覆寫（epic-28-reader-settings-enhancements Issue 4）',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => result = prefs,
    );

    await tester.tap(
        find.byKey(const Key('reader_settings_letter_spacing_increment')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.letterSpacing, closeTo(0.01, 1e-9));
    expect(result!.fontSize, isNull);
    expect(result!.fontWeight, isNull);
    expect(result!.lineHeight, isNull);
    expect(result!.paragraphSpacing, isNull);
  });

  testWidgets(
      '5 個受本 Issue 影響欄位皆為 null 時，顯示「原樣式」禁止圖示取代數字；'
      '邊界 4 個欄位不受影響，仍顯示具體數字，也不出現重置按鈕'
      '（epic-28-reader-settings-enhancements Issue 4）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);

    for (final keyPrefix in [
      'reader_settings_font_size',
      'reader_settings_font_weight',
      'reader_settings_line_height',
      'reader_settings_paragraph_spacing',
      'reader_settings_letter_spacing',
    ]) {
      expect(find.byKey(Key('${keyPrefix}_unset_indicator')), findsOneWidget,
          reason: '$keyPrefix 尚未被使用者調整過，應顯示原樣式圖示而非數字');
      expect(find.byKey(Key('${keyPrefix}_reset')), findsNothing,
          reason: '$keyPrefix 尚未覆寫，不應出現重置按鈕');
    }

    // epic-28-reader-settings-enhancements Issue 5 審查：必須真的切到「邊界
    // 首尾」頁籤才能驗證邊界欄位「不支援本機制」是設計使然，而非單純因為
    // 該頁籤尚未被掛載而巧合通過。
    await switchToTab(tester, '邊界');
    for (final keyPrefix in [
      'reader_settings_margin_top',
      'reader_settings_margin_bottom',
      'reader_settings_margin_left',
      'reader_settings_margin_right',
    ]) {
      expect(find.byKey(Key('${keyPrefix}_unset_indicator')), findsNothing,
          reason: '$keyPrefix 是 App 版面留白設定，與書本原生樣式無關，不適用本機制');
      expect(find.byKey(Key('${keyPrefix}_reset')), findsNothing);
    }
  });

  testWidgets(
      '依序調整 5 個受影響欄位，每次只有剛調整的欄位轉為顯示數字＋重置按鈕，'
      '其餘尚未調整的欄位持續顯示原樣式圖示（不互相污染，'
      'epic-28-reader-settings-enhancements Issue 4）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);

    const steps = [
      ('reader_settings_font_size', 'reader_settings_font_size_increment'),
      (
        'reader_settings_font_weight',
        'reader_settings_font_weight_increment'
      ),
      (
        'reader_settings_line_height',
        'reader_settings_line_height_increment'
      ),
      (
        'reader_settings_paragraph_spacing',
        'reader_settings_paragraph_spacing_increment'
      ),
      (
        'reader_settings_letter_spacing',
        'reader_settings_letter_spacing_increment'
      ),
    ];

    for (var i = 0; i < steps.length; i++) {
      final (keyPrefix, incrementKey) = steps[i];
      await tester.tap(find.byKey(Key(incrementKey)));
      await tester.pump();

      expect(find.byKey(Key('${keyPrefix}_unset_indicator')), findsNothing,
          reason: '$keyPrefix 剛被調整，應改顯示數字');
      expect(find.byKey(Key('${keyPrefix}_reset')), findsOneWidget,
          reason: '$keyPrefix 剛被調整，應出現重置按鈕');

      for (var j = i + 1; j < steps.length; j++) {
        final (untouchedPrefix, _) = steps[j];
        expect(find.byKey(Key('${untouchedPrefix}_unset_indicator')),
            findsOneWidget,
            reason: '$untouchedPrefix 尚未被調整，不應被 $keyPrefix 的互動連帶影響');
      }
    }
  });

  testWidgets(
      '按下字距重置按鈕後，onChanged 帶出 letterSpacing=null，滑桿回到預設位置、'
      '重新顯示原樣式圖示（epic-28-reader-settings-enhancements Issue 4）',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(letterSpacing: 0.3),
      (prefs) => result = prefs,
    );

    expect(find.byKey(const Key('reader_settings_letter_spacing_reset')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const Key('reader_settings_letter_spacing_reset')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.letterSpacing, isNull);
    expect(
        tester
            .widget<Slider>(find
                .byKey(const Key('reader_settings_letter_spacing_slider')))
            .value,
        0.0,
        reason: '重置後滑桿應回到原型範例預設位置');
    expect(
        find.byKey(
            const Key('reader_settings_letter_spacing_unset_indicator')),
        findsOneWidget);
    expect(find.byKey(const Key('reader_settings_letter_spacing_reset')),
        findsNothing);
  });

  testWidgets(
      '按下字型大小重置按鈕後，onChanged 帶出 fontSize=null，滑桿回到 16px 預設位置'
      '（epic-28-reader-settings-enhancements Issue 4，涵蓋倍率換算路徑）',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(fontSize: 1.375), // UI 22.0
      (prefs) => result = prefs,
    );

    expect(find.byKey(const Key('reader_settings_font_size_reset')),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('reader_settings_font_size_reset')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.fontSize, isNull);
    expect(
        tester
            .widget<Slider>(
                find.byKey(const Key('reader_settings_font_size_slider')))
            .value,
        16.0,
        reason: '重置後滑桿應回到原型範例預設位置');
    expect(
        find.byKey(const Key('reader_settings_font_size_unset_indicator')),
        findsOneWidget);
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
    await switchToTab(tester, '邊界');

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
    await switchToTab(tester, '呈現');

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
    await switchToTab(tester, '呈現');

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
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
    await switchToTab(tester, '呈現');

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
    await switchToTab(tester, '呈現');

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
    await switchToTab(tester, '呈現');

    await tester
        .tap(find.byKey(const Key('reader_settings_page_turn_mode_scroll')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.pageTurnModeOverride, PageTurnMode.scroll);
  });

  testWidgets('點擊「轉換為繁體」圖示後，onChanged 帶入 TextConversionMode.toTraditional',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => result = prefs,
    );
    await switchToTab(tester, '呈現');

    await tester.tap(
      find.byKey(const Key('reader_settings_text_conversion_traditional')),
    );
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.textConversionOverride, TextConversionMode.toTraditional);
  });

  testWidgets(
      'textConversionOverride 初始為 toSimplified 時，點擊「使用全域預設」圖示後，'
      'onChanged 帶入 null', (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(
        textConversionOverride: TextConversionMode.toSimplified,
      ),
      (prefs) => result = prefs,
    );
    await switchToTab(tester, '呈現');

    await tester.tap(
      find.byKey(const Key('reader_settings_text_conversion_global')),
    );
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.textConversionOverride, isNull);
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
    await switchToTab(tester, '呈現');

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
    await switchToTab(tester, '呈現');

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
    await switchToTab(tester, '邊界');

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
    await switchToTab(tester, '邊界');

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
    await switchToTab(tester, '邊界');

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
    await switchToTab(tester, '邊界');

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
    await switchToTab(tester, '呈現');

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
    await switchToTab(tester, '呈現');

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
    await switchToTab(tester, '呈現');

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
    await switchToTab(tester, '呈現');

    await tester.tap(find.byKey(const Key('reader_settings_column_mode_single')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.writingModeOverride, WritingMode.vertical);
    expect(result!.pageTurnModeOverride, PageTurnMode.scroll);
  });

  testWidgets('columnMode 預設 auto 時，自動按鈕高亮、Slider 可見', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});
    await switchToTab(tester, '呈現');

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
    await switchToTab(tester, '呈現');

    // Slider 不應存在
    expect(find.byKey(const Key('reader_settings_column_size_slider')), findsNothing);
  });

  testWidgets('columnMode=double 時，Slider 不可見', (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(columnMode: ColumnMode.double),
      (_) {},
    );
    await switchToTab(tester, '呈現');

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
    await switchToTab(tester, '呈現');

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
    await switchToTab(tester, '邊界');

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

  testWidgets('英文介面下字型選單的內建字型名稱以英文顯示（epic-48，epic-49 Issue 8）',
      (tester) async {
    await _pumpSheet(tester, const BookReaderPrefs(), (_) {},
        locale: const Locale('en'));

    await tester.tap(find.byKey(const Key('reader_settings_font_family')));
    await tester.pumpAndSettle();

    expect(find.text('Source Han Sans'), findsWidgets);
    expect(find.text('Source Han Serif'), findsWidgets);
    expect(find.text('GuanKiapTsingKhai'), findsWidgets);
    expect(find.text('TaiwanPearl'), findsWidgets);
    expect(find.text('GenRyuMin TW'), findsWidgets);
    expect(find.text('思源黑體'), findsNothing);
  });

  testWidgets('偏好設定存著不認得的字型名稱時，面板正常開啟且下拉選單顯示「使用書本字型」（epic-48）',
      (tester) async {
    // epic-49 Issue 8 恢復原俠正楷後，改用真的不存在的名稱，保留「不認得也不會壞」的意圖
    await _pumpSheet(
        tester, const BookReaderPrefs(fontFamily: 'NoSuchFont'), (_) {});

    expect(tester.takeException(), isNull);
    final dropdown = tester.widget<DropdownButton<String?>>(
        find.byKey(const Key('reader_settings_font_family')));
    expect(dropdown.value, isNull);
  });

  group('只列出已下載的內建字型（epic-49 Issue 4）', () {
    testWidgets('只下載思源黑體時，選單只有思源黑體，沒有思源宋體', (tester) async {
      await _pumpSheet(tester, const BookReaderPrefs(), (_) {},
          installedFonts: {AppFont.sourceHanSans});

      await tester.tap(find.byKey(const Key('reader_settings_font_family')));
      await tester.pumpAndSettle();

      expect(find.text('思源黑體'), findsWidgets);
      expect(find.text('思源宋體'), findsNothing);
    });

    testWidgets('只下載台灣圓體時，選單只有台灣圓體（Issue 8）', (tester) async {
      await _pumpSheet(tester, const BookReaderPrefs(), (_) {},
          installedFonts: {AppFont.taiwanPearl});

      await tester.tap(find.byKey(const Key('reader_settings_font_family')));
      await tester.pumpAndSettle();

      expect(find.text('台灣圓體'), findsWidgets);
      expect(find.text('原俠正楷'), findsNothing);
      expect(find.text('思源黑體'), findsNothing);
    });

    testWidgets('偏好為已下載的原俠正楷時，選單顯示原俠正楷（Issue 8）', (tester) async {
      await _pumpSheet(
          tester, const BookReaderPrefs(fontFamily: 'GuanKiapTsingKhai'), (_) {},
          installedFonts: {AppFont.guanKiapTsingKhai});

      final dropdown = tester.widget<DropdownButton<String?>>(
          find.byKey(const Key('reader_settings_font_family')));
      expect(dropdown.value, 'GuanKiapTsingKhai');
    });

    testWidgets('一款內建字型都沒下載時，選單下方顯示提示（即使有自訂字型）', (tester) async {
      await _pumpSheet(
        tester,
        const BookReaderPrefs(),
        (_) {},
        installedFonts: const {},
        customFonts: const [
          CustomFont(
            id: 1,
            displayName: '我的自訂字型',
            familyName: 'MyCustomFamily',
            fontUri: 'content://example/font1',
          ),
        ],
      );

      final hint = find.byKey(const Key('reader_settings_download_fonts_hint'));
      expect(hint, findsOneWidget);
      expect(tester.widget<Text>(hint).data, '到「字型管理」下載更多字型');
    });

    testWidgets('有已下載的內建字型時，不顯示提示', (tester) async {
      await _pumpSheet(tester, const BookReaderPrefs(), (_) {},
          installedFonts: {AppFont.sourceHanSerif});

      expect(find.byKey(const Key('reader_settings_download_fonts_hint')), findsNothing);
    });

    testWidgets('偏好值指向未下載的內建字型時，面板正常開啟並顯示「使用書本字型」（審查重點 5）',
        (tester) async {
      await _pumpSheet(tester, const BookReaderPrefs(fontFamily: 'SourceHanSerifTC'), (_) {},
          installedFonts: {AppFont.sourceHanSans});

      expect(tester.takeException(), isNull);
      final dropdown = tester.widget<DropdownButton<String?>>(
          find.byKey(const Key('reader_settings_font_family')));
      expect(dropdown.value, isNull);
    });

    testWidgets('英文介面的提示文字', (tester) async {
      await _pumpSheet(tester, const BookReaderPrefs(), (_) {},
          installedFonts: const {}, locale: const Locale('en'));

      expect(
          tester.widget<Text>(find.byKey(const Key('reader_settings_download_fonts_hint'))).data,
          'Download more fonts in Font Management');
    });
  });

  testWidgets('字型選單合併顯示內建 2 款與傳入的自訂字型清單', (tester) async {
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

  testWidgets(
      '自訂字型清單中存在過長顯示名稱時，字型下拉選單不應造成 RenderFlex overflow'
      '（bugfix：DropdownButton 內部以 IndexedStack 疊放「所有」選項決定自身寬度，'
      '不只是目前選中的值，過長字型名稱會把整顆 Row 撐爆版）', (tester) async {
    // 比照畫面截圖的手機寬度（412 logical px），_pumpSheet 預設的 800 寬度太寬
    // 不會重現這個 overflow。
    tester.view.physicalSize = const Size(412, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ReaderSettingsSheet(
          // 刻意選 null（顯示最短的「使用書本內建字型」），驗證即使目前選中值
          // 很短，只要清單中存在過長名稱仍會撐爆版（而非只有選中過長值時才會）。
          prefs: const BookReaderPrefs(),
          onChanged: _noopOnChanged,
          bookId: 'b1',
          availableFonts: const AvailableFonts(
            customFonts: [
              CustomFont(
                id: 1,
                displayName: '這是一個非常非常非常長的自訂字型顯示名稱範例測試用',
              familyName: 'CustomLongFontName',
              fontUri: 'content://example/font1',
            ),
            ],
          ),
          layoutPresets: const [],
          isEinkMode: false,
          onSaveAsPreset: _noopSaveAsPreset,
          onApplyPreset: _noopApplyPreset,
          onApplyFromBook: _noopApplyFromBook,
          onRequestBookPicker: _noopRequestBookPicker,
          onDeletePreset: _noopDeletePreset,
        ),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  group('「系統預設」固定列（一鍵重置字級/字重/行距/段落間距/字距覆寫）', () {
    testWidgets('沒有任何覆寫時，固定列顯示打勾指示器，不顯示套用按鈕', (tester) async {
      await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
      await switchToTab(tester, '預設集');

      expect(
          find.byKey(const Key('reader_settings_preset_reset_active_indicator')),
          findsOneWidget);
      expect(find.byKey(const Key('reader_settings_preset_reset_apply')),
          findsNothing);
    });

    testWidgets('任一受影響欄位被覆寫時，固定列改顯示套用按鈕，點擊後 onChanged 帶出 5 個欄位皆為 null',
        (tester) async {
      BookReaderPrefs? notified;
      await _pumpSheet(
        tester,
        const BookReaderPrefs(
          fontSize: 18 / 16,
          fontWeight: 1.5,
          lineHeight: 2.0,
          paragraphSpacing: 1.5,
          letterSpacing: 0.05,
        ),
        (prefs) => notified = prefs,
      );
      await switchToTab(tester, '預設集');

      expect(
          find.byKey(const Key('reader_settings_preset_reset_active_indicator')),
          findsNothing);
      await tester.ensureVisible(
          find.byKey(const Key('reader_settings_preset_reset_apply')));
      await tester
          .tap(find.byKey(const Key('reader_settings_preset_reset_apply')));
      await tester.pump();

      expect(notified, isNotNull);
      expect(notified!.fontSize, isNull);
      expect(notified!.fontWeight, isNull);
      expect(notified!.lineHeight, isNull);
      expect(notified!.paragraphSpacing, isNull);
      expect(notified!.letterSpacing, isNull);

      // 套用後固定列本身也應立即反映為已套用狀態。
      expect(
          find.byKey(const Key('reader_settings_preset_reset_active_indicator')),
          findsOneWidget);
    });

    testWidgets('套用後不影響邊界（marginTop 等）欄位既有值', (tester) async {
      BookReaderPrefs? notified;
      await _pumpSheet(
        tester,
        const BookReaderPrefs(fontSize: 18 / 16, marginTop: 40.0),
        (prefs) => notified = prefs,
      );
      await switchToTab(tester, '預設集');

      await tester.ensureVisible(
          find.byKey(const Key('reader_settings_preset_reset_apply')));
      await tester
          .tap(find.byKey(const Key('reader_settings_preset_reset_apply')));
      await tester.pump();

      expect(notified!.marginTop, 40.0);
    });
  });

  testWidgets('空 slot 顯示「（空）」，已存的 slot 顯示名稱', (tester) async {
    final preset = LayoutPreset(
      id: 1,
      name: '臥室夜讀直排',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 8, 14),
      prefs: BookReaderPrefs.empty,
    );
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged,
        layoutPresets: [preset]);
    await switchToTab(tester, '預設集');

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
    await switchToTab(tester, '預設集');

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
    await switchToTab(tester, '預設集');

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
    await switchToTab(tester, '預設集');

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
    await switchToTab(tester, '預設集');

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
    await switchToTab(tester, '預設集');

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
    await switchToTab(tester, '預設集');

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
    await switchToTab(tester, '預設集');

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
    await switchToTab(tester, '預設集');
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
    await switchToTab(tester, '預設集');

    expect(find.byKey(const Key('reader_settings_preset_slot_0_label')),
        findsOneWidget);
  });

  testWidgets(
      '「呈現」頁籤內圖示列的 ReaderOptionTile 皆使用緊湊視覺密度以節省垂直空間'
      '（epic-27-reader-device-compat Issue 6 Task 3：IconButton 已重構為 ReaderOptionTile）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    await switchToTab(tester, '呈現');

    // 【重要】find.byKey 回傳持有 key 的 Container（ReaderOptionTile 內部子元件）
    // 改用 find.descendant 從呈現頁籤的 ListView 向下搜尋所有 ReaderOptionTile
    final presentationList =
        find.byKey(const Key('reader_settings_tab_presentation_list'));
    final tiles = find.descendant(
      of: presentationList,
      matching: find.byType(ReaderOptionTile),
    );
    final tileWidgets = tester.widgetList<ReaderOptionTile>(tiles);
    for (final tile in tileWidgets) {
      expect(tile.visualDensity, VisualDensity.compact);
    }
  });

  testWidgets('ReaderSettingsSheet 文字對齊與排版方向在 E-Ink 模式下具備高對比選中底色', (tester) async {
    // 設定較大的 Viewport（與 _pumpSheet 一致），以防 ListView 元件超出
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildEinkThemeData(),
      home: Scaffold(
        body: ReaderSettingsSheet(
          bookId: 'test-book',
          prefs: const BookReaderPrefs(textAlign: EpubTextAlign.justify),
          isEinkMode: true,
          onChanged: (_) {},
          onSaveAsPreset: (_) {},
          onApplyPreset: (_, {required targetBookIds}) {},
          onApplyFromBook: (_, {required targetBookIds}) {},
          onRequestBookPicker: ({required multiSelect}) async => null,
          onDeletePreset: (_) {},
        ),
      ),
    ));

    // 切換到「呈現」頁籤（文字對齊選項已搬移至此）
    await switchToTab(tester, '呈現');

    // 【審查修正 Important】key 直接掛在帶 BoxDecoration 的 Container 上
    // （見 Task 1 ReaderOptionTile 實作），不再用
    // find.descendant(...).first 這種依賴子樹結構的脆弱寫法。
    final justifyTile = find.byKey(const Key('reader_settings_text_align_justify'));
    expect(justifyTile, findsOneWidget);
    final container = tester.widget<Container>(justifyTile);
    expect((container.decoration as BoxDecoration).color, Colors.black);
  });

  // 【審查修正 Important：見 reviews/review-issue-5-8.md Issue 6
  // Important #1】排版方向／翻頁模式／螢幕方向三組含 null（採用書籍/
  // 全域預設）選項的 ReaderOptionTile 群組，原本用「某個真實 enum 值當
  // sentinel 代表 null」，但該 sentinel 剛好也是清單中的一個真實選項，
  // 導致 override 為 null（預設狀態）時兩顆 tile 同時判定為選中。這個
  // bug 在既有測試套件下完全不可見（既有 E-Ink 測試只測了文字對齊，不
  // 含 null 分支），故補上這則測試直接鑑別「override 為 null 時只有
  // 一顆 tile 選中」。
  testWidgets('排版方向覆寫為 null（預設）時，僅「採用書籍排版」一顆 tile 呈現選中底色',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildEinkThemeData(),
      home: Scaffold(
        body: ReaderSettingsSheet(
          bookId: 'test-book',
          prefs: BookReaderPrefs.empty,
          isEinkMode: true,
          onChanged: (_) {},
          onSaveAsPreset: (_) {},
          onApplyPreset: (_, {required targetBookIds}) {},
          onApplyFromBook: (_, {required targetBookIds}) {},
          onRequestBookPicker: ({required multiSelect}) async => null,
          onDeletePreset: (_) {},
        ),
      ),
    ));
    await switchToTab(tester, '呈現');

    Color tileColor(String keySuffix) {
      final container = tester.widget<Container>(
        find.byKey(Key('reader_settings_writing_mode_$keySuffix')),
      );
      return (container.decoration as BoxDecoration).color!;
    }

    expect(tileColor('book'), Colors.black, reason: '採用書籍排版：null 覆寫，應為選中');
    expect(tileColor('vertical'), Colors.white, reason: '強制直排：非選中');
    expect(tileColor('horizontal'), Colors.white, reason: '強制橫排：非選中，過去的 bug 會誤判成選中');
  });

  testWidgets(
      'isOverridden 為 false（未覆寫）時，顯示文字徽章「使用全域預設」，'
      '且維持掛載既有 _unset_indicator Key（epic-39-layout-settings-redesign Issue 2）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);

    expect(find.text('使用全域預設'), findsNWidgets(5),
        reason: '文字分頁 5 個受影響欄位皆未覆寫，應各自顯示一個文字徽章');
    expect(
        find.byKey(const Key('reader_settings_font_size_unset_indicator')),
        findsOneWidget,
        reason: '既有測試依賴此 Key 判斷未覆寫狀態，Key 語意不變');
  });

  testWidgets(
      'isOverridden 為 true 且一般主題（isEinkMode: false）時，顯示「此書已覆寫」文字徽章，'
      '且仍保留原始數值文字與可運作的重置按鈕（審查修正 C1，review-plan-issue-2.md：'
      '一般主題的 Slider 不具備數值回饋能力，不可把數值文字整個拿掉）',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(letterSpacing: 0.3),
      (prefs) => result = prefs,
    );

    expect(find.text('此書已覆寫'), findsOneWidget);
    expect(find.text('0.30em'), findsOneWidget,
        reason: '一般主題下必須保留原始數值文字，供使用者確認目前數值');
    expect(find.byKey(const Key('reader_settings_letter_spacing_reset')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const Key('reader_settings_letter_spacing_reset')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.letterSpacing, isNull, reason: '重置行為應零回歸');
  });

  testWidgets(
      'isOverridden 為 true 且 isEinkMode: true 時，頂列只顯示「此書已覆寫」文字徽章與重置按鈕，'
      '不重複顯示原始數值文字（審查修正 C1，review-plan-issue-2.md：僅 E-Ink 模式隱藏，'
      '因為只有 EBStepper 本身會另外顯示一次數值）',
      (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(letterSpacing: 0.3),
      _noopOnChanged,
      isEinkMode: true,
    );

    expect(find.text('此書已覆寫'), findsOneWidget);
    // Task 3 後 EBStepper 會顯示一次數值，頂列不再顯示，因此全域恰好一次且位於 EBStepper 內
    expect(find.text('0.30em'), findsOneWidget,
        reason: 'E-Ink 模式下數值改由 EBStepper 顯示一次，頂列不應重複');
    final letterSpacingValueWidget = tester.widget<Text>(
      find.byKey(const Key('reader_settings_letter_spacing_value')),
    );
    expect(letterSpacingValueWidget.data, '0.30em',
        reason: '唯一一次顯示應在 EBStepper 的 _value 文字上');
    expect(find.byKey(const Key('reader_settings_letter_spacing_reset')),
        findsOneWidget);
  });

  testWidgets(
      '覆寫徽章依 isEinkMode 套用不同邊框樣式（審查修正 I1，review-plan-issue-2.md：'
      'E-Ink 主題的 surfaceContainerHighest 與 surface 皆為純白，徽章若無邊框會視覺隱形）',
      (tester) async {
    // E-Ink 主題：純黑 1.5dp 邊框。
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildEinkThemeData(),
      home: Scaffold(
        body: ReaderSettingsSheet(
          bookId: 'test-book',
          prefs: BookReaderPrefs.empty,
          isEinkMode: true,
          onChanged: (_) {},
          onSaveAsPreset: (_) {},
          onApplyPreset: (_, {required targetBookIds}) {},
          onApplyFromBook: (_, {required targetBookIds}) {},
          onRequestBookPicker: ({required multiSelect}) async => null,
          onDeletePreset: (_) {},
        ),
      ),
    ));

    final einkContainer = tester.widget<Container>(
      find.byKey(const Key('reader_settings_font_size_unset_indicator')),
    );
    final einkBorder =
        (einkContainer.decoration as BoxDecoration).border as Border;
    expect(einkBorder.top.color, Colors.black);
    expect(einkBorder.top.width, 1.5);
  });

  testWidgets(
      '一般主題下覆寫徽章邊框為 outline 35% 透明度、寬度 1.0dp'
      '（審查修正 I1，review-plan-issue-2.md）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);

    final context = tester.element(
      find.byKey(const Key('reader_settings_font_size_unset_indicator')),
    );
    final expectedColor =
        Theme.of(context).colorScheme.outline.withValues(alpha: 0.35);
    final container = tester.widget<Container>(
      find.byKey(const Key('reader_settings_font_size_unset_indicator')),
    );
    final border = (container.decoration as BoxDecoration).border as Border;

    expect(border.top.color, expectedColor);
    expect(border.top.width, 1.0);
  });

  testWidgets(
      'isEinkMode: true 時，文字分頁與邊界分頁共 9 個數值列皆改為 EBStepper，'
      '不存在任何 Slider（邊界分頁 4 欄不支援覆寫語意，EBStepper 版本同樣不顯示覆寫徽章，'
      'epic-39-layout-settings-redesign Issue 2）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged,
        isEinkMode: true);

    for (final keyPrefix in [
      'reader_settings_font_size',
      'reader_settings_font_weight',
      'reader_settings_line_height',
      'reader_settings_paragraph_spacing',
      'reader_settings_letter_spacing',
    ]) {
      expect(find.byKey(Key('${keyPrefix}_value')), findsOneWidget,
          reason: '$keyPrefix 應改為 EBStepper（僅 EBStepper 具備 _value Key）');
    }
    expect(find.byType(Slider), findsNothing,
        reason: '文字分頁在 E-Ink 模式下不應存在任何 Slider');

    await switchToTab(tester, '邊界');
    for (final keyPrefix in [
      'reader_settings_margin_top',
      'reader_settings_margin_bottom',
      'reader_settings_margin_left',
      'reader_settings_margin_right',
    ]) {
      expect(find.byKey(Key('${keyPrefix}_value')), findsOneWidget,
          reason: '$keyPrefix 應改為 EBStepper');
      expect(find.byKey(Key('${keyPrefix}_unset_indicator')), findsNothing,
          reason: '$keyPrefix 不支援覆寫語意（isOverridden == null），'
              'EBStepper 版本同樣不應顯示覆寫徽章（issues.md Issue 2 單元測試要求）');
      expect(find.byKey(Key('${keyPrefix}_reset')), findsNothing,
          reason: '$keyPrefix 不支援覆寫語意，不應出現重置按鈕');
    }
    expect(find.byType(Slider), findsNothing,
        reason: '邊界分頁在 E-Ink 模式下不應存在任何 Slider');
  });

  testWidgets(
      'isEinkMode: true 時，點擊 EBStepper 的 + 觸發 onChanged，行為與 Slider 模式等價'
      '（epic-39-layout-settings-redesign Issue 2）',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => result = prefs,
      isEinkMode: true,
    );

    await tester.tap(find.byKey(const Key('reader_settings_font_size_increment')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.fontSize, closeTo(17 / 16, 1e-9),
        reason: '預設 16px + step 1 = 17px，換算倍率應為 17/16');
  });

  testWidgets(
      'isEinkMode: true 時，邊界分頁數值列頂端不重複顯示數值文字'
      '（審查修正 M1，spec.md／review-plan-issue-1.md：EBStepper 內部已顯示一次，'
      '頂列不應再顯示第二次，epic-39-layout-settings-redesign Issue 2）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged,
        isEinkMode: true);
    await switchToTab(tester, '邊界');

    expect(find.text('32'), findsOneWidget,
        reason: '上邊界預設值 32 只應出現一次（EBStepper 內部），頂列不應重複顯示');
    final marginTopValueWidget = tester.widget<Text>(
      find.byKey(const Key('reader_settings_margin_top_value')),
    );
    expect(marginTopValueWidget.data, '32',
        reason: '唯一一次顯示應在 EBStepper 的 _value 文字上');
  });

  testWidgets(
      'isEinkMode: true 且文字分頁欄位已覆寫時，數值只透過 EBStepper 顯示一次'
      '（審查修正 M1／M1-補充，review-plan-issue-2.md：Task 2 已讓 isEinkMode 時頂列'
      '不顯示原始數值，本測試驗證接上 EBStepper 後該數值改由 EBStepper 顯示，'
      '總出現次數維持恰好一次，epic-39-layout-settings-redesign Issue 2）',
      (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(fontSize: 1.125), // UI 18px
      _noopOnChanged,
      isEinkMode: true,
    );

    expect(find.text('18'), findsOneWidget,
        reason: '字型大小 18px 只應出現一次，來源是 EBStepper 的 _value 文字');
    final fontSizeValueWidget = tester.widget<Text>(
      find.byKey(const Key('reader_settings_font_size_value')),
    );
    expect(fontSizeValueWidget.data, '18',
        reason: '唯一一次顯示應在 EBStepper 的 _value 文字上，而非頂列殘留的舊 Text(displayValue)');
  });

  testWidgets(
      '「文字對齊」已從「邊界」分頁搬到「呈現」分頁'
      '（epic-39-layout-settings-redesign Issue 3：spec.md「既有元件異動」'
      'ReaderSettingsSheet 第 4 條）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    await switchToTab(tester, '邊界');

    expect(
      find.descendant(
        of: find.byKey(const Key('reader_settings_tab_boundary_list')),
        matching: find.text('文字對齊'),
      ),
      findsNothing,
      reason: '文字對齊已搬離邊界分頁',
    );

    await switchToTab(tester, '呈現');

    expect(
      find.descendant(
        of: find.byKey(const Key('reader_settings_tab_presentation_list')),
        matching: find.text('文字對齊'),
      ),
      findsOneWidget,
      reason: '文字對齊應出現在呈現分頁',
    );
  });

  testWidgets(
      '欄數群組改用 EBOptionChipGroup 後，3 個選項皆顯示 spec.md 選項標籤對照表'
      '定義的短標籤（epic-39-layout-settings-redesign Issue 3）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    await switchToTab(tester, '呈現');

    for (final item in [
      ('auto', '自動'),
      ('single', '單欄'),
      ('double', '雙欄'),
    ]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('reader_settings_column_mode_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'reader_settings_column_mode_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets(
      '文字對齊群組改用 EBOptionChipGroup 後，6 個選項皆顯示短標籤且全部存在'
      '（epic-39-layout-settings-redesign Issue 3）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    await switchToTab(tester, '呈現');

    for (final item in [
      ('center', '置中'),
      ('justify', '齊行'),
      ('start', '起始'),
      ('end', '結尾'),
      ('left', '靠左'),
      ('right', '靠右'),
    ]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('reader_settings_text_align_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'reader_settings_text_align_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets(
      '書寫方向覆寫群組改用 EBOptionChipGroup 後，3 個選項皆顯示短標籤'
      '（epic-39-layout-settings-redesign Issue 3）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    await switchToTab(tester, '呈現');

    for (final item in [
      ('book', '書籍'),
      ('vertical', '直排'),
      ('horizontal', '橫排'),
    ]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('reader_settings_writing_mode_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'reader_settings_writing_mode_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets(
      '翻頁模式覆寫群組改用 EBOptionChipGroup 後，3 個選項皆顯示短標籤'
      '（epic-39-layout-settings-redesign Issue 3）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    await switchToTab(tester, '呈現');

    for (final item in [
      ('global', '全域'),
      ('paginated', '點擊'),
      ('scroll', '滾動'),
    ]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('reader_settings_page_turn_mode_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'reader_settings_page_turn_mode_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets(
      '螢幕方向覆寫群組改用 EBOptionChipGroup 後，6 個選項皆顯示短標籤'
      '（epic-39-layout-settings-redesign Issue 3）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    await switchToTab(tester, '呈現');

    for (final item in [
      ('global', '全域'),
      ('auto', '自動'),
      ('lock0', '0°'),
      ('lock90', '90°'),
      ('lock180', '180°'),
      ('lock270', '270°'),
    ]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('reader_settings_screen_orientation_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'reader_settings_screen_orientation_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets(
      'isEinkMode: true 且 columnMode=auto 時，欄位大小改為 EBStepper，'
      '點擊 + 觸發 onChanged 帶入 columnSize+60（審查修正 C3/I3，'
      'review-spec.md／review-issues.md：reader_settings_column_size_slider '
      '未經過 _buildSliderRow，需獨立處理，epic-39-layout-settings-redesign Issue 3）',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => result = prefs,
      isEinkMode: true,
    );
    await switchToTab(tester, '呈現');

    expect(find.byKey(const Key('reader_settings_column_size_slider')),
        findsNothing,
        reason: 'E-Ink 模式不應存在 Slider');
    expect(find.byKey(const Key('reader_settings_column_size_value')),
        findsOneWidget);
    expect(find.text('欄位大小'), findsOneWidget,
        reason: '審查修正 M1（review-plan-issue-3.md）：E-Ink 模式下標題不應帶數值，'
            '避免與 EBStepper 內部顯示的數值重複（比照 Issue 2 C1 對 _buildSliderRow '
            '已建立的先例）');
    expect(find.text('欄位大小 720px'), findsNothing,
        reason: '標題與 EBStepper 顯示同一個數值視為重複顯示');

    await tester
        .tap(find.byKey(const Key('reader_settings_column_size_increment')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.columnSize, 780.0, reason: '預設 720 + step 60 = 780');
  });

  testWidgets(
      'isEinkMode: false（預設）時，欄位大小維持既有 Slider 與帶數值標題（既有行為零回歸）'
      '（epic-39-layout-settings-redesign Issue 3）',
      (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    await switchToTab(tester, '呈現');

    expect(find.byKey(const Key('reader_settings_column_size_slider')),
        findsOneWidget);
    expect(find.byKey(const Key('reader_settings_column_size_value')),
        findsNothing);
    expect(find.text('欄位大小 720px'), findsOneWidget,
        reason: '一般主題下 Slider 本身不具備數值回饋能力，標題必須保留數值'
            '（比照 Issue 2 C1 對 _buildSliderRow 已建立的先例）');
  });

  testWidgets(
      '目前草稿與某預設集 prefs 完全相等時，該列反白（底色 colorScheme.primary、'
      '前景色 colorScheme.onPrimary）並顯示打勾指示器，「套用到本書」'
      '按鈕改為隱藏；其餘不相等的預設集列維持一般樣式（既有行為零回歸）'
      '（epic-39-layout-settings-redesign Issue 4）',
      (tester) async {
    final activePreset = LayoutPreset(
      id: 1,
      name: '目前套用中預設集',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      prefs: _activeDraftPrefs,
    );
    final otherPreset = LayoutPreset(
      id: 2,
      name: '未套用預設集',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      prefs: BookReaderPrefs.empty,
    );
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged,
        layoutPresets: [activePreset, otherPreset]);
    await switchToTab(tester, '預設集');

    final context = tester.element(
      find.byKey(const Key('reader_settings_preset_slot_0_row')),
    );
    final colorScheme = Theme.of(context).colorScheme;

    final activeContainer = tester.widget<Container>(
      find.byKey(const Key('reader_settings_preset_slot_0_row')),
    );
    expect((activeContainer.decoration as BoxDecoration).color,
        colorScheme.primary);

    final activeLabel = tester.widget<Text>(
      find.byKey(const Key('reader_settings_preset_slot_0_label')),
    );
    expect(activeLabel.style?.color, colorScheme.onPrimary);

    expect(
        find.byKey(const Key('reader_settings_preset_slot_0_active_indicator')),
        findsOneWidget);
    expect(find.byKey(const Key('reader_settings_preset_slot_0_apply_current')),
        findsNothing);
    expect(find.byKey(const Key('reader_settings_preset_slot_0_apply_others')),
        findsOneWidget);
    expect(find.byKey(const Key('reader_settings_preset_slot_0_delete')),
        findsOneWidget);

    // 審查修正 I1（review-plan-issue-4.md）：spec.md 明確要求反白列「所有」
    // 文字與圖示前景色皆為 colorScheme.onPrimary，不能只驗證標籤
    // 文字——若實作漏寫某顆 Icon 的 color 參數，只斷言文字顏色的測試不會
    // 抓到這個對比度缺陷，故逐一驗證 apply_others／delete／active_indicator
    // 內的 Check 圖示三者的前景色。
    final activeIndicatorIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_settings_preset_slot_0_active_indicator')),
      matching: find.byType(Icon),
    ));
    expect(activeIndicatorIcon.color, colorScheme.onPrimary);

    final applyOthersIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_settings_preset_slot_0_apply_others')),
      matching: find.byType(Icon),
    ));
    expect(applyOthersIcon.color, colorScheme.onPrimary);

    final deleteIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_settings_preset_slot_0_delete')),
      matching: find.byType(Icon),
    ));
    expect(deleteIcon.color, colorScheme.onPrimary);

    // Slot 1（未套用，既有行為零回歸）
    final otherContainer = tester.widget<Container>(
      find.byKey(const Key('reader_settings_preset_slot_1_row')),
    );
    expect((otherContainer.decoration as BoxDecoration?)?.color, isNull,
        reason: '未套用的列不應套用反白底色（審查修正 M1，review-plan-issue-4.md：'
            '改用可空安全轉型，即使日後改成 decoration: null 也不會讓測試拋出 '
            'TypeError 而是回報清楚的斷言失敗）');
    expect(
        find.byKey(const Key('reader_settings_preset_slot_1_active_indicator')),
        findsNothing);
    expect(find.byKey(const Key('reader_settings_preset_slot_1_apply_current')),
        findsOneWidget);
  });

  testWidgets(
      '使用者調整任一數值後，草稿不再與預設集相等，先前反白的列恢復一般樣式'
      '（epic-39-layout-settings-redesign Issue 4）',
      (tester) async {
    final activePreset = LayoutPreset(
      id: 1,
      name: '目前套用中預設集',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      prefs: _activeDraftPrefs,
    );
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged,
        layoutPresets: [activePreset]);
    await switchToTab(tester, '預設集');

    expect(
        find.byKey(const Key('reader_settings_preset_slot_0_active_indicator')),
        findsOneWidget,
        reason: '互動前草稿與預設集相等，應顯示已套用');

    await switchToTab(tester, '文字');
    await tester
        .tap(find.byKey(const Key('reader_settings_font_size_increment')));
    await tester.pump();
    await switchToTab(tester, '預設集');

    expect(
        find.byKey(const Key('reader_settings_preset_slot_0_active_indicator')),
        findsNothing,
        reason: '字級已調整，fontSize 不再是 null，草稿不再與預設集相等');
    expect(find.byKey(const Key('reader_settings_preset_slot_0_apply_current')),
        findsOneWidget,
        reason: '恢復一般樣式後，套用到本書按鈕應重新出現');
  });

  testWidgets(
      'E-Ink 模式下反白列使用純黑底（colorScheme.primary）與純白前景'
      '（colorScheme.onPrimary），驗證不會出現深底深字對比度不足的組合'
      '（epic-39-layout-settings-redesign Issue 4）',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final activePreset = LayoutPreset(
      id: 1,
      name: '目前套用中預設集',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      prefs: _activeDraftPrefs,
    );

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildEinkThemeData(),
      home: Scaffold(
        body: ReaderSettingsSheet(
          bookId: 'test-book',
          prefs: BookReaderPrefs.empty,
          isEinkMode: true,
          layoutPresets: [activePreset],
          onChanged: (_) {},
          onSaveAsPreset: (_) {},
          onApplyPreset: (_, {required targetBookIds}) {},
          onApplyFromBook: (_, {required targetBookIds}) {},
          onRequestBookPicker: ({required multiSelect}) async => null,
          onDeletePreset: (_) {},
        ),
      ),
    ));
    await switchToTab(tester, '預設集');

    final container = tester.widget<Container>(
      find.byKey(const Key('reader_settings_preset_slot_0_row')),
    );
    expect((container.decoration as BoxDecoration).color, Colors.black);

    final label = tester.widget<Text>(
      find.byKey(const Key('reader_settings_preset_slot_0_label')),
    );
    expect(label.style?.color, Colors.white);

    // 審查修正 I1（review-plan-issue-4.md）：E-Ink 模式同樣須驗證圖示前景色，
    // 不能只驗證文字，理由同上方一般主題測試。
    final einkActiveIndicatorIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_settings_preset_slot_0_active_indicator')),
      matching: find.byType(Icon),
    ));
    expect(einkActiveIndicatorIcon.color, Colors.white);

    final einkApplyOthersIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_settings_preset_slot_0_apply_others')),
      matching: find.byType(Icon),
    ));
    expect(einkApplyOthersIcon.color, Colors.white);

    final einkDeleteIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_settings_preset_slot_0_delete')),
      matching: find.byType(Icon),
    ));
    expect(einkDeleteIcon.color, Colors.white);
  });

  testWidgets('英文介面下四個分頁籤標題與版面設定標題正確以英文渲染', (tester) async {
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (_) {},
      locale: const Locale('en'),
    );

    expect(find.text('⚙️ Layout Settings'), findsOneWidget);
    expect(find.text('Text'), findsOneWidget);
    expect(find.text('Margins'), findsOneWidget);
    expect(find.text('Display'), findsOneWidget);
    expect(find.text('Presets'), findsOneWidget);
  });

  testWidgets('正體中文介面下字型標籤與欄數「單欄」選項正確渲染', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);

    expect(find.text('字型'), findsOneWidget);

    await switchToTab(tester, '呈現');
    expect(
      find.descendant(
        of: find.byKey(const Key('reader_settings_column_mode_single')),
        matching: find.text('單欄'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('簡體中文介面下字型標籤與欄數「单栏」選項正確以簡體渲染', (tester) async {
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      _noopOnChanged,
      locale: const Locale('zh', 'CN'),
    );

    expect(find.text('字体'), findsOneWidget);
    expect(find.text('字型'), findsNothing);

    await switchToTab(tester, '呈现');
    expect(
      find.descendant(
        of: find.byKey(const Key('reader_settings_column_mode_single')),
        matching: find.text('单栏'),
      ),
      findsOneWidget,
    );
    expect(find.text('單欄'), findsNothing);
  });

  testWidgets('英文介面下字型標籤與欄數「Single」選項正確以英文渲染', (tester) async {
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      _noopOnChanged,
      locale: const Locale('en'),
    );

    expect(find.text('Font'), findsOneWidget);
    expect(find.text('字型'), findsNothing);

    await switchToTab(tester, 'Display');
    expect(
      find.descendant(
        of: find.byKey(const Key('reader_settings_column_mode_single')),
        matching: find.text('Single'),
      ),
      findsOneWidget,
    );
    expect(find.text('單欄'), findsNothing);
  });

  // 真機回報（2026-09-28）：版面設定面板永遠撐滿整個螢幕，內容較短的
  // 分頁下方一大片空白。面板高度應等於「最高那個分頁的內容高度」，切換
  // 分頁時高度不變，且不超過螢幕 85%。用真實呼叫端的開法
  // （showModalBottomSheet + isScrollControlled: true）驗證。
  // 使用者需求（2026-09-28）：四個分頁切換時不要有任何捲動／滑動動畫，
  // 點下去就直接切過去（E-Ink 上動畫會殘影）。點一下、只 pump 一個 frame，
  // 分頁與底線指示器就必須已經切完（不檢查點擊水波紋，那不是捲動）。
  testWidgets('切換分頁沒有動畫：點一下只 pump 一個 frame 就切完', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, _noopOnChanged);
    final tabController = DefaultTabController.of(
      tester.element(find.byKey(const Key('reader_settings_font_size_slider'))),
    );

    for (final (label, index) in [('邊界', 1), ('呈現', 2), ('預設集', 3), ('文字', 0)]) {
      await tester.tap(find.widgetWithText(Tab, label));
      await tester.pump();
      expect(tabController.index, index, reason: label);
      expect(tabController.animation!.value, index.toDouble(), reason: label);
    }
  });

  testWidgets('版面設定面板高度跟最高分頁一樣，不撐滿螢幕，切分頁高度不變',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => ReaderSettingsSheet(
                prefs: BookReaderPrefs.empty,
                onChanged: _noopOnChanged,
                availableFonts: AvailableFonts(installedBuiltIn: AppFont.values.toSet()),
                bookId: 'b1',
                layoutPresets: const [],
                isEinkMode: false,
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

    final sheet = find.byType(ReaderSettingsSheet);
    final textTabHeight = tester.getSize(sheet).height;
    expect(textTabHeight, lessThan(1400 * 0.85 + 0.01));
    // 最高的分頁內容約 700 多，面板不該再撐到接近 1400。
    expect(textTabHeight, lessThan(1000));

    for (final tab in ['邊界', '呈現', '預設集']) {
      await switchToTab(tester, tab);
      expect(tester.getSize(sheet).height, textTabHeight, reason: tab);
    }
  });
}

Future<void> _pumpSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged, {
  List<CustomFont> customFonts = const [],
  Set<AppFont>? installedFonts,
  String bookId = 'b1',
  List<LayoutPreset> layoutPresets = const [],
  void Function(BookReaderPrefs)? onSaveAsPreset,
  void Function(LayoutPreset, {required List<String> targetBookIds})? onApplyPreset,
  void Function(String, {required List<String> targetBookIds})? onApplyFromBook,
  Future<List<String>?> Function({required bool multiSelect})? onRequestBookPicker,
  void Function(int)? onDeletePreset,
  bool isEinkMode = false,
  Locale locale = const Locale('zh', 'TW'),
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
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ReaderSettingsSheet(
        prefs: prefs,
        onChanged: onChanged,
        // 既有測試的前提都是「內建字型已經可用」，沿用這個前提：沒指定時視為全部已下載。
        // 驗證「只列出已下載字型」的新測試會明確傳入集合。
        availableFonts: AvailableFonts(
          installedBuiltIn: installedFonts ?? AppFont.values.toSet(),
          customFonts: customFonts,
        ),
        bookId: bookId,
        layoutPresets: layoutPresets,
        isEinkMode: isEinkMode,
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
      isEinkMode: false,
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
  ValueChanged<BookReaderPrefs> onChanged, {
  bool isEinkMode = false,
  Locale locale = const Locale('zh', 'TW'),
}) async {
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
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
              isEinkMode: isEinkMode,
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

/// 點擊 `TabBar` 上文字為 [tabLabel] 的頁籤並等待切換動畫完成
/// （epic-28-reader-settings-enhancements Issue 5）。
Future<void> switchToTab(WidgetTester tester, String tabLabel) async {
  await tester.tap(find.widgetWithText(Tab, tabLabel));
  await tester.pumpAndSettle();
}
