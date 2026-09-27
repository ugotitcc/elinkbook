import 'dart:math';

import 'package:flutter/material.dart';

import '../reader/app_font.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/custom_font.dart';
import '../reader/column_mode.dart';
import '../reader/epub_text_align.dart';
import '../reader/layout_preset.dart';
import '../reader/page_turn_mode.dart';
import '../reader/screen_orientation_setting.dart';
import '../reader/text_conversion_mode.dart';
import '../l10n/app_localizations.dart';
import '../reader/writing_mode.dart';
import 'widgets/eb_field_card.dart';
import 'widgets/eb_option_chip_group.dart';
import 'widgets/eb_stepper.dart';
import 'widgets/text_conversion_icon.dart';

/// 版面設定 Bottom Sheet（FR-09／FR-10 字型、數值型控制項與三個持久化覆寫
/// 選擇器），比照 prototype/index.html 第 1379-1520 行設計。
///
/// 純展示、無 I/O：每次互動即時透過 [onChanged] 回報目前完整的
/// [BookReaderPrefs]，持久化與更新 `EpubReaderView` 建構參數、螢幕方向鎖定
/// 皆由呼叫端（`ReaderScreen`）負責——本 widget 只負責回報使用者選擇的覆寫
/// 值，不負責解析「覆寫值 `??` 自動偵測結果／全域預設值」的最終生效值
/// （見 `ReaderScreen._resolvedWritingMode`／`_resolvedPageTurnMode`／
/// `_resolvedScreenOrientation`）。[isEinkMode] 決定 `_buildSliderRow`
/// 數值列採用一般主題的 `Slider`＋±按鈕，或 E-Ink 模式的 `EBStepper`。
class ReaderSettingsSheet extends StatefulWidget {
  final BookReaderPrefs prefs;
  final ValueChanged<BookReaderPrefs> onChanged;
  final List<CustomFont> customFonts;
  /// 已下載的內建字型（epic-49）。字型選單只列出這些內建字型，
  /// 選了一定有效果；一款都沒有時在選單下方提示去字型管理下載。
  final Set<AppFont> installedFonts;
  final String bookId;
  final List<LayoutPreset> layoutPresets;
  final void Function(BookReaderPrefs currentDraft) onSaveAsPreset;
  final void Function(
    LayoutPreset preset, {
    required List<String> targetBookIds,
  })
  onApplyPreset;
  final void Function(
    String sourceBookId, {
    required List<String> targetBookIds,
  })
  onApplyFromBook;
  final Future<List<String>?> Function({required bool multiSelect})
  onRequestBookPicker;
  final void Function(int id) onDeletePreset;
  final bool isEinkMode;

  const ReaderSettingsSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
    this.customFonts = const [],
    this.installedFonts = const {},
    required this.bookId,
    this.layoutPresets = const [],
    required this.onSaveAsPreset,
    required this.onApplyPreset,
    required this.onApplyFromBook,
    required this.onRequestBookPicker,
    required this.onDeletePreset,
    required this.isEinkMode,
  });

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  // 尚未有持久化覆寫（對應欄位為 null）時，滑桿顯示的初始位置，與
  // prototype/index.html 的示範數值一致；互動前不會被送出/持久化，只影響
  // 滑桿位置。
  static const _defaultFontSize = 16.0;
  static const _defaultFontWeightMultiplier = 1.0; // 倍率，UI 顯示 400（1.0 × 400）
  static const _defaultLineHeight = 1.0;
  static const _defaultParagraphSpacing = 10.0;
  static const _defaultLetterSpacing = 0.0;
  static const _defaultMarginTop = 32.0;
  static const _defaultMarginBottom = 16.0;
  static const _defaultMarginLeft = 24.0;
  static const _defaultMarginRight = 24.0;

  late String? _fontFamily;
  late double _fontSize;
  late bool _fontSizeOverridden;
  late double _fontWeightMultiplier;
  late bool _fontWeightOverridden;
  late double _lineHeight;
  late bool _lineHeightOverridden;
  late double _paragraphSpacing;
  late bool _paragraphSpacingOverridden;
  late double _letterSpacing;
  late bool _letterSpacingOverridden;
  late double _marginTop;
  late double _marginBottom;
  late double _marginLeft;
  late double _marginRight;
  late EpubTextAlign? _textAlign;
  late bool _publisherStyles;
  late WritingMode? _writingModeOverride;
  late PageTurnMode? _pageTurnModeOverride;
  late ScreenOrientationSetting? _screenOrientationOverride;
  late TextConversionMode? _textConversionOverride;
  late bool _showHeader;
  late bool _showFooter;
  late bool _fullscreen;
  late ColumnMode _columnMode;
  late double _columnSize;

  @override
  void initState() {
    super.initState();
    _fontFamily = widget.prefs.fontFamily;
    _fontSize = widget.prefs.fontSize != null
        ? (widget.prefs.fontSize! * 16.0).roundToDouble()
        : _defaultFontSize;
    _fontSizeOverridden = widget.prefs.fontSize != null;
    _fontWeightMultiplier =
        widget.prefs.fontWeight ?? _defaultFontWeightMultiplier;
    _fontWeightOverridden = widget.prefs.fontWeight != null;
    _lineHeight = widget.prefs.lineHeight ?? _defaultLineHeight;
    _lineHeightOverridden = widget.prefs.lineHeight != null;
    _paragraphSpacing = widget.prefs.paragraphSpacing != null
        ? (widget.prefs.paragraphSpacing! * 10.0).roundToDouble()
        : _defaultParagraphSpacing;
    _paragraphSpacingOverridden = widget.prefs.paragraphSpacing != null;
    _letterSpacing = widget.prefs.letterSpacing ?? _defaultLetterSpacing;
    _letterSpacingOverridden = widget.prefs.letterSpacing != null;
    _marginTop = widget.prefs.marginTop ?? _defaultMarginTop;
    _marginBottom = widget.prefs.marginBottom ?? _defaultMarginBottom;
    _marginLeft = widget.prefs.marginLeft ?? _defaultMarginLeft;
    _marginRight = widget.prefs.marginRight ?? _defaultMarginRight;
    _textAlign = widget.prefs.textAlign;
    _publisherStyles = widget.prefs.publisherStyles ?? true;
    _writingModeOverride = widget.prefs.writingModeOverride;
    _pageTurnModeOverride = widget.prefs.pageTurnModeOverride;
    _screenOrientationOverride = widget.prefs.screenOrientationOverride;
    _textConversionOverride = widget.prefs.textConversionOverride;
    _showHeader = widget.prefs.showHeader ?? false;
    _showFooter = widget.prefs.showFooter ?? false;
    _fullscreen = widget.prefs.fullscreen ?? false;
    _columnMode = widget.prefs.columnMode ?? ColumnMode.auto;
    _columnSize = widget.prefs.columnSize ?? 720.0;
  }

  @override
  void didUpdateWidget(ReaderSettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prefs != oldWidget.prefs) {
      setState(() {
        _fontFamily = widget.prefs.fontFamily;
        _fontSize = widget.prefs.fontSize != null
            ? (widget.prefs.fontSize! * 16.0).roundToDouble()
            : _defaultFontSize;
        _fontSizeOverridden = widget.prefs.fontSize != null;
        _fontWeightMultiplier =
            widget.prefs.fontWeight ?? _defaultFontWeightMultiplier;
        _fontWeightOverridden = widget.prefs.fontWeight != null;
        _lineHeight = widget.prefs.lineHeight ?? _defaultLineHeight;
        _lineHeightOverridden = widget.prefs.lineHeight != null;
        _paragraphSpacing = widget.prefs.paragraphSpacing != null
            ? (widget.prefs.paragraphSpacing! * 10.0).roundToDouble()
            : _defaultParagraphSpacing;
        _paragraphSpacingOverridden = widget.prefs.paragraphSpacing != null;
        _letterSpacing = widget.prefs.letterSpacing ?? _defaultLetterSpacing;
        _letterSpacingOverridden = widget.prefs.letterSpacing != null;
        _marginTop = widget.prefs.marginTop ?? _defaultMarginTop;
        _marginBottom = widget.prefs.marginBottom ?? _defaultMarginBottom;
        _marginLeft = widget.prefs.marginLeft ?? _defaultMarginLeft;
        _marginRight = widget.prefs.marginRight ?? _defaultMarginRight;
        _textAlign = widget.prefs.textAlign;
        _publisherStyles = widget.prefs.publisherStyles ?? true;
        _writingModeOverride = widget.prefs.writingModeOverride;
        _pageTurnModeOverride = widget.prefs.pageTurnModeOverride;
        _screenOrientationOverride = widget.prefs.screenOrientationOverride;
        _textConversionOverride = widget.prefs.textConversionOverride;
        _showHeader = widget.prefs.showHeader ?? false;
        _showFooter = widget.prefs.showFooter ?? false;
        _fullscreen = widget.prefs.fullscreen ?? false;
        _columnMode = widget.prefs.columnMode ?? ColumnMode.auto;
        _columnSize = widget.prefs.columnSize ?? 720.0;
      });
    }
  }

  double _toMultiplier(double value, double base) {
    return ((value / base) * 10000).round() / 10000;
  }

  /// **epic-28-reader-settings-enhancements Issue 4 審查回應**：這裡回傳的
  /// `null`（未覆寫）不只影響本書畫面即時渲染，也會被 [_buildLayoutPresetSection]
  /// 的「另存為新預設集」／「複製到其他書籍」原封不動存進 [LayoutPreset]／
  /// 寫進目標書籍——`BookReaderPrefsRepository.save()`／`saveMultiple()`
  /// 是「整列覆寫」語意（`INSERT OR REPLACE`，見該檔案 class doc），並非
  /// 逐欄位合併。因此：使用者若存一個只調整過部分欄位的預設集，套用到
  /// 另一本已有自訂覆寫值的書籍時，本欄位若仍是未覆寫狀態，會把目標書籍
  /// 對應欄位一併清空回該書自己的原生樣式，不是只套用預設集裡「有值」的
  /// 那幾項。這是「整列覆寫」既有設計（Epic 28 Issue 3 上線時就如此）與
  /// 本次修復（未觸碰欄位正確維持 `null`）疊加後的預期結果，不是缺陷——
  /// 比修復前「未觸碰欄位一律凍結成當時滑桿顯示的預設數字」更符合直覺，
  /// 但屬於容易被誤判為回歸的跨 Issue 行為，記錄於此供日後排查參考。
  BookReaderPrefs get _currentDraft => BookReaderPrefs(
    fontFamily: _fontFamily,
    fontSize: _fontSizeOverridden ? _toMultiplier(_fontSize, 16.0) : null,
    fontWeight: _fontWeightOverridden ? _fontWeightMultiplier : null,
    lineHeight: _lineHeightOverridden ? _lineHeight : null,
    paragraphSpacing: _paragraphSpacingOverridden
        ? _toMultiplier(_paragraphSpacing, 10.0)
        : null,
    letterSpacing: _letterSpacingOverridden ? _letterSpacing : null,
    marginTop: _marginTop,
    marginBottom: _marginBottom,
    marginLeft: _marginLeft,
    marginRight: _marginRight,
    textAlign: _textAlign,
    publisherStyles: _publisherStyles,
    writingModeOverride: _writingModeOverride,
    pageTurnModeOverride: _pageTurnModeOverride,
    screenOrientationOverride: _screenOrientationOverride,
    textConversionOverride: _textConversionOverride,
    showHeader: _showHeader,
    showFooter: _showFooter,
    fullscreen: _fullscreen,
    columnMode: _columnMode,
    columnSize: _columnSize,
  );

  void _notifyChanged() {
    widget.onChanged(_currentDraft);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: ConstrainedBox(
        // 面板最高到螢幕 85%（DESIGN.md#L235 抽屜高度上限），內容不夠高時
        // 就縮到內容高度，不再撐滿整個螢幕。
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.readerSettingsTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    key: const Key('reader_settings_close_button'),
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: DefaultTabController(
                length: 4,
                // 切換分頁不要有任何滑動動畫，點了就直接切過去（2026-09-28
                // 使用者需求；E-Ink 上動畫會殘影）。
                animationDuration: Duration.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TabBar(
                      key: const Key('reader_settings_tab_bar'),
                      tabs: [
                        Tab(
                          key: const Key('reader_settings_tab_text_content'),
                          text: l10n.readerSettingsTabText,
                        ),
                        Tab(
                          key: const Key('reader_settings_tab_boundary'),
                          text: l10n.readerSettingsTabBoundary,
                        ),
                        Tab(
                          key: const Key('reader_settings_tab_presentation'),
                          text: l10n.readerSettingsTabPresentation,
                        ),
                        Tab(
                          key: const Key('reader_settings_tab_preferences'),
                          text: l10n.readerSettingsTabPreferences,
                        ),
                      ],
                    ),
                    Flexible(
                      // 【不可逆的技術決策】分頁內容用 IndexedStack，不用 TabBarView：
                      // 1. 高度：TabBarView 一定撐滿父層給的高度，加上呼叫端
                      //    isScrollControlled: true，面板會永遠佔滿整個螢幕，短分頁下面
                      //    一大片空白（2026-09-28 真機回報）。IndexedStack 取「最高那個
                      //    分頁」的高度，切分頁時面板高度不變，E-Ink 上不會多閃一次。
                      // 2. 手勢：「文字」／「邊界」頁籤內有橫向拖曳的 Slider，TabBarView
                      //    底層 PageView 的水平滑動會跟它們搶手勢，調滑桿時意外切頁籤
                      //    （epic-28-reader-settings-enhancements Issue 5）。IndexedStack
                      //    沒有滑動手勢，只能點 TabBar 切換。不可改回可滑動的 TabBarView。
                      // 各分頁的 ListView 是 shrinkWrap，內容超過可用高度（上限見上方
                      // maxHeight）時仍可在分頁內捲動。
                      child: Builder(
                        builder: (context) {
                          final tabController = DefaultTabController.of(
                            context,
                          );
                          return AnimatedBuilder(
                            animation: tabController,
                            builder: (context, _) => IndexedStack(
                              index: tabController.index,
                              children: [
                                _buildTextContentTab(),
                                _buildBoundaryTab(),
                                _buildPresentationTab(),
                                _buildPreferencesTab(),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 【不可逆的技術決策】以下 4 個 `_buildXxxTab()` 方法（文字／邊界／
  /// 呈現／預設集）僅是本 State 的 `build()` 展示分支，一律不得抽成獨立
  /// `StatefulWidget`。Issue 4 新增的 5 個「是否已覆寫」旗標（`_fontSizeOverridden`
  /// 等）與其餘全部草稿狀態皆留在 `_ReaderSettingsSheetState` 根層級，這些方法
  /// 只是直接讀寫同一組欄位——若日後為了重用或拆檔而把某個頁籤抽成獨立
  /// StatefulWidget，該旗標會變成兩份不同 State 各自管理，Tab 切換時容易被
  /// 意外重建/遺失（epic-28-reader-settings-enhancements Issue 5 審查，詳見
  /// design.md「2026-08-15 追加」審查回應 Important #3）。
  Widget _buildTextContentTab() {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      key: const Key('reader_settings_tab_text_content_list'),
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _buildFontFamilyDropdown(),
        _buildSliderRow(
          keyPrefix: 'reader_settings_font_size',
          label: l10n.readerSettingsFontSizeLabel,
          value: _fontSize,
          min: 12,
          max: 80,
          step: 1,
          displayValue: _fontSize.round().toString(),
          isOverridden: _fontSizeOverridden,
          onReset: () => setState(() {
            _fontSizeOverridden = false;
            _fontSize = _defaultFontSize;
            _notifyChanged();
          }),
          onChanged: (v) => setState(() {
            _fontSize = v;
            _fontSizeOverridden = true;
            _notifyChanged();
          }),
        ),
        _buildSliderRow(
          keyPrefix: 'reader_settings_font_weight',
          label: l10n.readerSettingsFontWeightLabel,
          value: _fontWeightMultiplier * 400,
          min: 300,
          max: 900,
          step: 100,
          displayValue: (_fontWeightMultiplier * 400).round().toString(),
          isOverridden: _fontWeightOverridden,
          onReset: () => setState(() {
            _fontWeightOverridden = false;
            _fontWeightMultiplier = _defaultFontWeightMultiplier;
            _notifyChanged();
          }),
          onChanged: (v) => setState(() {
            _fontWeightMultiplier = v / 400;
            _fontWeightOverridden = true;
            _notifyChanged();
          }),
        ),
        _buildSliderRow(
          keyPrefix: 'reader_settings_line_height',
          label: l10n.readerSettingsLineHeightLabel,
          value: _lineHeight,
          min: 0,
          max: 3,
          step: 0.1,
          displayValue: _lineHeight.toStringAsFixed(1),
          isOverridden: _lineHeightOverridden,
          onReset: () => setState(() {
            _lineHeightOverridden = false;
            _lineHeight = _defaultLineHeight;
            _notifyChanged();
          }),
          onChanged: (v) => setState(() {
            _lineHeight = double.parse(v.toStringAsFixed(1));
            _lineHeightOverridden = true;
            _notifyChanged();
          }),
        ),
        _buildSliderRow(
          keyPrefix: 'reader_settings_paragraph_spacing',
          label: l10n.readerSettingsParagraphSpacingLabel,
          value: _paragraphSpacing,
          min: 0,
          max: 40,
          step: 1,
          displayValue: _paragraphSpacing.round().toString(),
          isOverridden: _paragraphSpacingOverridden,
          onReset: () => setState(() {
            _paragraphSpacingOverridden = false;
            _paragraphSpacing = _defaultParagraphSpacing;
            _notifyChanged();
          }),
          onChanged: (v) => setState(() {
            _paragraphSpacing = v;
            _paragraphSpacingOverridden = true;
            _notifyChanged();
          }),
        ),
        _buildSliderRow(
          keyPrefix: 'reader_settings_letter_spacing',
          label: l10n.readerSettingsLetterSpacingLabel,
          value: _letterSpacing,
          min: -0.05,
          max: 1,
          step: 0.01,
          displayValue: '${_letterSpacing.toStringAsFixed(2)}em',
          isOverridden: _letterSpacingOverridden,
          onReset: () => setState(() {
            _letterSpacingOverridden = false;
            _letterSpacing = _defaultLetterSpacing;
            _notifyChanged();
          }),
          onChanged: (v) => setState(() {
            _letterSpacing = double.parse(v.toStringAsFixed(2));
            _letterSpacingOverridden = true;
            _notifyChanged();
          }),
        ),
        EBFieldCard(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            key: const Key('reader_settings_disable_book_css'),
            title: Text(l10n.readerSettingsDisableBookCssLabel, style: TextStyle(fontWeight: FontWeight.bold)),
            value: !_publisherStyles,
            onChanged: (v) => setState(() {
              _publisherStyles = !v;
              _notifyChanged();
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildBoundaryTab() {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      key: const Key('reader_settings_tab_boundary_list'),
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _buildSliderRow(
          keyPrefix: 'reader_settings_margin_top',
          label: l10n.readerSettingsMarginTopLabel,
          value: _marginTop,
          min: 0,
          max: 120,
          step: 2,
          displayValue: _marginTop.round().toString(),
          onChanged: (v) => setState(() {
            _marginTop = v;
            _notifyChanged();
          }),
        ),
        _buildSliderRow(
          keyPrefix: 'reader_settings_margin_bottom',
          label: l10n.readerSettingsMarginBottomLabel,
          value: _marginBottom,
          min: 0,
          max: 120,
          step: 2,
          displayValue: _marginBottom.round().toString(),
          onChanged: (v) => setState(() {
            _marginBottom = v;
            _notifyChanged();
          }),
        ),
        _buildSliderRow(
          keyPrefix: 'reader_settings_margin_left',
          label: l10n.readerSettingsMarginLeftLabel,
          value: _marginLeft,
          min: 0,
          max: 120,
          step: 2,
          displayValue: _marginLeft.round().toString(),
          onChanged: (v) => setState(() {
            _marginLeft = v;
            _notifyChanged();
          }),
        ),
        _buildSliderRow(
          keyPrefix: 'reader_settings_margin_right',
          label: l10n.readerSettingsMarginRightLabel,
          value: _marginRight,
          min: 0,
          max: 120,
          step: 2,
          displayValue: _marginRight.round().toString(),
          onChanged: (v) => setState(() {
            _marginRight = v;
            _notifyChanged();
          }),
        ),
        EBFieldCard(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            key: const Key('reader_settings_show_header'),
            title: Text(l10n.readerShowHeaderLabel, style: TextStyle(fontWeight: FontWeight.bold)),
            value: _showHeader,
            onChanged: (v) => setState(() {
              _showHeader = v;
              _notifyChanged();
            }),
          ),
        ),
        EBFieldCard(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            key: const Key('reader_settings_show_footer'),
            title: Text(l10n.readerShowFooterLabel, style: TextStyle(fontWeight: FontWeight.bold)),
            value: _showFooter,
            onChanged: (v) => setState(() {
              _showFooter = v;
              _notifyChanged();
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildPresentationTab() {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      key: const Key('reader_settings_tab_presentation_list'),
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        EBFieldCard(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            key: const Key('reader_settings_fullscreen'),
            title: Text(l10n.readerFullscreenModeLabel, style: TextStyle(fontWeight: FontWeight.bold)),
            value: _fullscreen,
            onChanged: (v) => setState(() {
              _fullscreen = v;
              _notifyChanged();
            }),
          ),
        ),
        const SizedBox(height: 8),
        _buildColumnModeRow(),
        const SizedBox(height: 8),
        _buildTextAlignRow(),
        const SizedBox(height: 8),
        _buildWritingModeOverrideRow(),
        const SizedBox(height: 8),
        _buildScreenOrientationOverrideRow(),
        const SizedBox(height: 8),
        _buildPageTurnModeOverrideRow(),
        const SizedBox(height: 8),
        _buildTextConversionOverrideRow(),
      ],
    );
  }

  Widget _buildPreferencesTab() {
    return ListView(
      key: const Key('reader_settings_tab_preferences_list'),
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [_buildLayoutPresetSection()],
    );
  }

  Widget _buildColumnModeRow() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.readerSettingsColumnCountLabel, style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          EBOptionChipGroup<ColumnMode>(
            items:
                [
                  (ColumnMode.auto, 'auto', Icons.auto_awesome, l10n.readerSettingsColumnAutoLabel, l10n.readerSettingsColumnAutoLabel),
                  (ColumnMode.single, 'single', Icons.crop_portrait, l10n.readerSettingsColumnSingleLabel, l10n.readerSettingsColumnSingleLabel),
                  (ColumnMode.double, 'double', Icons.book, l10n.readerSettingsColumnDoubleLabel, l10n.readerSettingsColumnDoubleLabel),
                ].map((option) {
                  final (mode, keySuffix, icon, tooltip, label) = option;
                  return EBOptionChipItem<ColumnMode>(
                    itemKey: Key('reader_settings_column_mode_$keySuffix'),
                    value: mode,
                    icon: icon,
                    label: label,
                    tooltip: tooltip,
                  );
                }).toList(),
            groupValue: _columnMode,
            visualDensity: VisualDensity.compact,
            onSelected: (v) => setState(() {
              _columnMode = v;
              _notifyChanged();
            }),
          ),
          if (_columnMode == ColumnMode.auto) ...[
            const SizedBox(height: 8),
            // 視覺還原：Reference 截圖只有「欄位大小」這一列有邊框卡片，
            // 「欄數」本身的三顆選項按鈕不用額外的外框包裹（各按鈕自身
            // 已有邊框，見 ReaderOptionTile），故只包這一區塊。
            EBFieldCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 審查修正 M1（review-plan-issue-3.md）：isEinkMode 時標題
                  // 不帶數值，避免與下方 EBStepper 內部顯示的數值重複（比照
                  // Issue 2 C1 對 _buildSliderRow 已建立的先例——一般主題下
                  // Slider 不具備數值回饋能力，標題仍須保留數值）。
                  Text(
                    widget.isEinkMode
                        ? l10n.readerSettingsColumnSizeLabel
                         : l10n.readerSettingsColumnSizeWithValueLabel(_columnSize.round()),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  widget.isEinkMode
                      ? EBStepper(
                          keyPrefix: 'reader_settings_column_size',
                          value: _columnSize,
                          min: 360.0,
                          max: 1440.0,
                          step: 60.0,
                          displayValue: '${_columnSize.round()}px',
                          onChanged: (v) => setState(() {
                            _columnSize = v;
                            _notifyChanged();
                          }),
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        )
                      : Slider(
                          key: const Key('reader_settings_column_size_slider'),
                          value: _columnSize,
                          min: 360.0,
                          max: 1440.0,
                          divisions: 18, // (1440 - 360) / 60 = 18
                          label: '${_columnSize.round()}px',
                          onChanged: (v) => setState(() {
                            _columnSize = v;
                            _notifyChanged();
                          }),
                        ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFontFamilyDropdown() {
    final l10n = AppLocalizations.of(context)!;
    // 依 AppFont.values 的順序列出，不受集合迭代順序影響
    final builtInFonts =
        AppFont.values.where(widget.installedFonts.contains).toList();
    return EBFieldCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l10n.readerSettingsFontFamilyLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              // DropdownButton 內部以 IndexedStack 疊放「所有」選項來決定自身寬度
              // （不只是目前選中的值），字型名稱過長（尤其使用者自訂字型）時會把
              // 整顆 Row 撐爆版。isExpanded:true 讓寬度改吃 Expanded 給的可用空間，
              // 搭配 Text 的 overflow: ellipsis 讓過長名稱改為截斷顯示，而非溢位。
              Expanded(
                child: DropdownButton<String?>(
                  key: const Key('reader_settings_font_family'),
                  isExpanded: true,
                  // 偏好設定可能指向已停用（epic-48）或尚未下載／已刪除（epic-49）的
                  // 內建字型，該值不在選項中時 DropdownButton 會 assert 失敗，改顯示為
                  // 「使用書本字型」。只影響顯示，不改寫偏好設定，字型下載後舊設定
                  // 自然生效。
                  value: {
                    ...builtInFonts.map((f) => f.familyName),
                    ...widget.customFonts.map((f) => f.familyName),
                  }.contains(_fontFamily)
                      ? _fontFamily
                      : null,
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l10n.readerSettingsUseBookFontLabel, overflow: TextOverflow.ellipsis),
                    ),
                    ...builtInFonts.map(
                      (font) => DropdownMenuItem<String?>(
                        value: font.familyName,
                        child: Text(font.displayName(l10n),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    ...widget.customFonts.map(
                      (font) => DropdownMenuItem<String?>(
                        value: font.familyName,
                        child: Text(font.displayName,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _fontFamily = value;
                    _notifyChanged();
                  }),
                ),
              ),
            ],
          ),
          if (builtInFonts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.readerSettingsDownloadMoreFontsHint,
                key: const Key('reader_settings_download_fonts_hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverrideBadge(String text, {Key? key}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outline.withValues(
            alpha: widget.isEinkMode ? 1.0 : 0.35,
          ),
          width: widget.isEinkMode ? 1.5 : 1.0,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildSliderRow({
    required String keyPrefix,
    required String label,
    required double value,
    required double min,
    required double max,
    required double step,
    required String displayValue,
    required ValueChanged<double> onChanged,
    bool? isOverridden,
    VoidCallback? onReset,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final divisions = ((max - min) / step).round();
    final clampedValue = value.clamp(min, max);
    return EBFieldCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (isOverridden == null && !widget.isEinkMode)
                Text(displayValue)
              else if (isOverridden == true)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!widget.isEinkMode) ...[
                      Text(displayValue),
                      const SizedBox(width: 8),
                    ],
                    _buildOverrideBadge(l10n.readerSettingsOverriddenBadge),
                    IconButton(
                      key: Key('${keyPrefix}_reset'),
                      icon: const Icon(Icons.block),
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      tooltip: l10n.readerSettingsResetToBookStyleTooltip,
                      onPressed: onReset,
                    ),
                  ],
                )
              else if (isOverridden == false)
                Tooltip(
                  message: l10n.readerSettingsNotOverriddenTooltip,
                  child: _buildOverrideBadge(
                    l10n.readerUseGlobalDefaultTooltip,
                    key: Key('${keyPrefix}_unset_indicator'),
                  ),
                ),
            ],
          ),
          widget.isEinkMode
              ? EBStepper(
                  keyPrefix: keyPrefix,
                  value: clampedValue,
                  min: min,
                  max: max,
                  step: step,
                  displayValue: displayValue,
                  onChanged: onChanged,
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                )
              : Row(
                  children: [
                    IconButton(
                      key: Key('${keyPrefix}_decrement'),
                      icon: const Icon(Icons.remove),
                      onPressed: clampedValue - step < min - 1e-9
                          ? null
                          : () => onChanged(
                              (clampedValue - step).clamp(min, max),
                            ),
                    ),
                    Expanded(
                      child: Slider(
                        key: Key('${keyPrefix}_slider'),
                        value: clampedValue,
                        min: min,
                        max: max,
                        divisions: divisions,
                        onChanged: (v) => onChanged(v.clamp(min, max)),
                      ),
                    ),
                    IconButton(
                      key: Key('${keyPrefix}_increment'),
                      icon: const Icon(Icons.add),
                      onPressed: clampedValue + step > max + 1e-9
                          ? null
                          : () => onChanged(
                              (clampedValue + step).clamp(min, max),
                            ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildTextAlignRow() {
    final l10n = AppLocalizations.of(context)!;
    final options = [
      (EpubTextAlign.center, Icons.format_align_center, l10n.readerSettingsTextAlignCenterLabel, l10n.readerSettingsTextAlignCenterLabel),
      (EpubTextAlign.justify, Icons.format_align_justify, l10n.readerSettingsTextAlignJustifyTooltip, l10n.readerSettingsTextAlignJustifyLabel),
      (EpubTextAlign.start, Icons.first_page, l10n.readerSettingsTextAlignStartTooltip, l10n.readerSettingsTextAlignStartLabel),
      (EpubTextAlign.end, Icons.last_page, l10n.readerSettingsTextAlignEndTooltip, l10n.readerSettingsTextAlignEndLabel),
      (EpubTextAlign.left, Icons.format_align_left, l10n.readerSettingsTextAlignLeftLabel, l10n.readerSettingsTextAlignLeftLabel),
      (EpubTextAlign.right, Icons.format_align_right, l10n.readerSettingsTextAlignRightLabel, l10n.readerSettingsTextAlignRightLabel),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.readerSettingsTextAlignLabel, style: TextStyle(fontWeight: FontWeight.bold)),
        EBOptionChipGroup<EpubTextAlign>(
          items: options.map((option) {
            final (align, icon, tooltip, label) = option;
            return EBOptionChipItem<EpubTextAlign>(
              itemKey: Key('reader_settings_text_align_${align.name}'),
              value: align,
              icon: icon,
              label: label,
              tooltip: tooltip,
            );
          }).toList(),
          groupValue: _textAlign ?? EpubTextAlign.justify,
          visualDensity: VisualDensity.compact,
          onSelected: (v) => setState(() {
            _textAlign = v;
            _notifyChanged();
          }),
        ),
      ],
    );
  }

  /// 排版方向覆寫（三態，FR-10）：`null`＝採用書籍排版（自動偵測結果，見
  /// `ReaderScreen._resolvedWritingMode`）、`vertical`＝強制直排、
  /// `horizontal`＝強制橫排。
  Widget _buildWritingModeOverrideRow() {
    final l10n = AppLocalizations.of(context)!;
    final options = [
      (null, 'book', Icons.auto_stories, l10n.readerSettingsWritingModeBookTooltip, l10n.readerSettingsWritingModeBookLabel),
      (
        WritingMode.vertical,
        'vertical',
        Icons.text_rotate_vertical,
        l10n.readerSettingsWritingModeVerticalTooltip,
        l10n.readerSettingsWritingModeVerticalLabel,
      ),
      (
        WritingMode.horizontal,
        'horizontal',
        Icons.text_rotation_none,
        l10n.readerSettingsWritingModeHorizontalTooltip,
        l10n.readerSettingsWritingModeHorizontalLabel,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.readerSettingsWritingModeLabel, style: TextStyle(fontWeight: FontWeight.bold)),
        EBOptionChipGroup<WritingMode?>(
          items: options.map((option) {
            final (mode, keySuffix, icon, tooltip, label) = option;
            // 【審查修正 Important：見 reviews/review-issue-5-8.md Issue 6
            // Important #1】原本用「某個真實 enum 值當 sentinel 代表 null」
            // （例如 WritingMode.horizontal），但 options 清單裡剛好也有一個
            // 真實選項是 WritingMode.horizontal，兩者的 effectiveValue 會
            // 撞在一起，導致 _writingModeOverride == null 時「採用書籍排版」
            // 與「強制橫排」兩顆 tile 同時判定為選中。改用
            // EBOptionChipItem<WritingMode?>，value 直接傳原始 nullable 值，
            // 不需要 fallback，null 只會跟 null 相等。
            return EBOptionChipItem<WritingMode?>(
              itemKey: Key('reader_settings_writing_mode_$keySuffix'),
              value: mode,
              icon: icon,
              label: label,
              tooltip: tooltip,
            );
          }).toList(),
          groupValue: _writingModeOverride,
          visualDensity: VisualDensity.compact,
          onSelected: (v) => setState(() {
            _writingModeOverride = v;
            _notifyChanged();
          }),
        ),
      ],
    );
  }

  /// 翻頁模式覆寫（FR-10／FR-38，全域/單書雙層解析）：`null`＝使用全域
  /// 預設值（見 `ReaderScreen._resolvedPageTurnMode`），非 `null`＝單書
  /// 覆寫。
  Widget _buildPageTurnModeOverrideRow() {
    final l10n = AppLocalizations.of(context)!;
    final options = [
      (null, 'global', Icons.tune, l10n.readerUseGlobalDefaultTooltip, l10n.readerGlobalLabel),
      (PageTurnMode.paginated, 'paginated', Icons.menu_book, l10n.readerSettingsPageTurnPaginatedTooltip, l10n.readerSettingsPageTurnPaginatedLabel),
      (PageTurnMode.scroll, 'scroll', Icons.swap_vert, l10n.readerSettingsPageTurnScrollTooltip, l10n.readerSettingsPageTurnScrollLabel),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.readerSettingsPageTurnModeLabel, style: TextStyle(fontWeight: FontWeight.bold)),
        EBOptionChipGroup<PageTurnMode?>(
          items: options.map((option) {
            final (mode, keySuffix, icon, tooltip, label) = option;
            // 【審查修正 Important，同排版方向覆寫的修法】改用
            // EBOptionChipItem<PageTurnMode?>，避免 sentinel 值與真實選項
            // （PageTurnMode.scroll）衝突。
            return EBOptionChipItem<PageTurnMode?>(
              itemKey: Key('reader_settings_page_turn_mode_$keySuffix'),
              value: mode,
              icon: icon,
              label: label,
              tooltip: tooltip,
            );
          }).toList(),
          groupValue: _pageTurnModeOverride,
          visualDensity: VisualDensity.compact,
          onSelected: (v) => setState(() {
            _pageTurnModeOverride = v;
            _notifyChanged();
          }),
        ),
      ],
    );
  }

  /// 簡繁轉換覆寫（FR-48，全域/單書雙層解析，見 `resolveTextConversion()`）：
  /// `null`＝使用全域預設，非 `null`＝單書覆寫。
  Widget _buildTextConversionOverrideRow() {
    final l10n = AppLocalizations.of(context)!;
    final items = [
      EBOptionChipItem<TextConversionMode?>(
        itemKey: const Key('reader_settings_text_conversion_global'),
        value: null,
        icon: Icons.tune,
        label: l10n.readerGlobalLabel,
        tooltip: l10n.readerUseGlobalDefaultTooltip,
      ),
      EBOptionChipItem<TextConversionMode?>(
        itemKey: const Key('reader_settings_text_conversion_original'),
        value: TextConversionMode.original,
        icon: Icons.article_outlined,
        label: l10n.readerTextConversionOriginalLabel,
        tooltip: l10n.readerTextConversionOriginalLabel,
      ),
      EBOptionChipItem<TextConversionMode?>(
        itemKey: const Key('reader_settings_text_conversion_traditional'),
        value: TextConversionMode.toTraditional,
        iconWidget: const TextConversionIcon(mode: TextConversionMode.toTraditional),
        label: l10n.readerTextConversionTraditionalLabel,
        tooltip: l10n.readerTextConversionTraditionalTooltip,
      ),
      EBOptionChipItem<TextConversionMode?>(
        itemKey: const Key('reader_settings_text_conversion_simplified'),
        value: TextConversionMode.toSimplified,
        iconWidget: const TextConversionIcon(mode: TextConversionMode.toSimplified),
        label: l10n.readerTextConversionSimplifiedLabel,
        tooltip: l10n.readerTextConversionSimplifiedTooltip,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.readerTextConversionOverrideLabel, style: TextStyle(fontWeight: FontWeight.bold)),
        EBOptionChipGroup<TextConversionMode?>(
          items: items,
          groupValue: _textConversionOverride,
          visualDensity: VisualDensity.compact,
          onSelected: (v) => setState(() {
            _textConversionOverride = v;
            _notifyChanged();
          }),
        ),
      ],
    );
  }

  /// 螢幕方向覆寫（FR-10／FR-37，全域/單書雙層解析）：`null`＝使用全域
  /// 預設值（見 `ReaderScreen._resolvedScreenOrientation`），非 `null`＝
  /// 單書覆寫。0°／180° 與 90°／270° 分別共用同一個 Material icon，以
  /// `Transform.rotate` 配合角度旋轉提升視覺辨識度，tooltip 文字消歧。
  Widget _buildScreenOrientationOverrideRow() {
    final l10n = AppLocalizations.of(context)!;
    // (setting, keySuffix, icon, tooltip, rotationAngle, label)
    final options =
        <(ScreenOrientationSetting?, String, IconData, String, double, String)>[
          (null, 'global', Icons.tune, l10n.readerUseGlobalDefaultTooltip, 0.0, l10n.readerGlobalLabel),
          (
            ScreenOrientationSetting.auto,
            'auto',
            Icons.screen_rotation,
            l10n.readerSettingsOrientationAutoTooltip,
            0.0,
            l10n.readerSettingsOrientationAutoLabel,
          ),
          (
            ScreenOrientationSetting.lock0,
            'lock0',
            Icons.stay_current_portrait,
            l10n.readerSettingsOrientationLock0Tooltip,
            0.0,
            '0°',
          ),
          (
            ScreenOrientationSetting.lock90,
            'lock90',
            Icons.stay_current_landscape,
            l10n.readerSettingsOrientationLock90Tooltip,
            0.0,
            '90°',
          ),
          (
            ScreenOrientationSetting.lock180,
            'lock180',
            Icons.stay_current_portrait,
            l10n.readerSettingsOrientationLock180Tooltip,
            pi,
            '180°',
          ),
          (
            ScreenOrientationSetting.lock270,
            'lock270',
            Icons.stay_current_landscape,
            l10n.readerSettingsOrientationLock270Tooltip,
            pi * 1.5,
            '270°',
          ),
        ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.readerSettingsScreenOrientationLabel, style: TextStyle(fontWeight: FontWeight.bold)),
        EBOptionChipGroup<ScreenOrientationSetting?>(
          items: options.map((option) {
            final (setting, keySuffix, icon, tooltip, _, label) = option;
            // 【審查修正 Important，同排版方向覆寫的修法】改用
            // EBOptionChipItem<ScreenOrientationSetting?>，避免 sentinel 值
            // 與真實選項（ScreenOrientationSetting.auto）衝突。
            return EBOptionChipItem<ScreenOrientationSetting?>(
              itemKey: Key('reader_settings_screen_orientation_$keySuffix'),
              value: setting,
              icon: icon,
              label: label,
              tooltip: tooltip,
            );
          }).toList(),
          groupValue: _screenOrientationOverride,
          visualDensity: VisualDensity.compact,
          onSelected: (v) => setState(() {
            _screenOrientationOverride = v;
            _notifyChanged();
          }),
        ),
      ],
    );
  }

  /// 版面設定預設集管理區塊（epic-28-reader-settings-enhancements
  /// Issue 3）：一顆「重設為本書原樣式」固定列＋3 個 slot 卡片（存在則
  /// 顯示名稱＋摘要＋套用/刪除按鈕，空則顯示「（空）」）、「將目前設定
  /// 存為新預設集」按鈕、「從其他書籍複製」兩顆按鈕。本 widget 只負責觸發
  /// 對應 callback，實際 I/O、「存量是否已滿 3 組」判斷、命名輸入、覆蓋
  /// 選擇/確認對話框皆由呼叫端（`ReaderScreen`）完成，見 spec.md「UI 元件
  /// 責任劃分」。
  ///
  /// 視覺還原（Visual Accuracy Mode，`docs/research/uiux/reference/
  /// 版面設定_預設集.png`）：「另存為新預設集」移到清單最上方、改為滿版
  /// 實心按鈕；移除原本置頂的「版面設定預設集」標題（Bottom Sheet 分頁籤
  /// 本身已標示「預設集」，重複標題與 Reference 不符）；卡片改用
  /// `colorScheme.primary`/`onPrimary` 標示已套用列，對齊全 App 已統一的
  /// 「選中態＝主色實心填滿」語彙（`ReaderOptionTile`／`Switch` 皆同），
  /// 取代原本的 `inverseSurface`/`onInverseSurface`。
  Widget _buildLayoutPresetSection() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('reader_settings_save_as_preset'),
            onPressed: () => widget.onSaveAsPreset(_currentDraft),
            icon: const Icon(Icons.add),
            label: Text(l10n.readerSettingsSaveAsPresetButton),
          ),
        ),
        const SizedBox(height: 16),
        Text(l10n.readerSettingsSavedPresetsLabel, style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildResetToBookDefaultRow(),
        ...List.generate(3, _buildPresetSlot),
        const SizedBox(height: 16),
        Text(l10n.readerSettingsCopyFromBookLabel, style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('reader_settings_copy_from_book_current'),
                onPressed: _handleCopyFromBookToCurrent,
                child: Text(l10n.readerSettingsCopyToCurrentBookButton),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const Key('reader_settings_copy_from_book_others'),
                onPressed: _handleCopyFromBookToOthers,
                child: Text(l10n.readerSettingsCopyToOtherBooksButton),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 卡片列共用外殼：套用中（[isActive]）時整列改為 `primary` 實心填滿＋
  /// `onPrimary` 前景色，否則維持 `outline` 邊框卡片，供固定的「重設為本書
  /// 原樣式」列與 [_buildPresetSlot] 共用同一套視覺語彙。
  Widget _buildPresetRow({
    required Key rowKey,
    required Key titleKey,
    required String title,
    required String subtitle,
    required bool isActive,
    required Widget trailing,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = isActive ? colorScheme.onPrimary : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        key: rowKey,
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive ? colorScheme.primary : null,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? null
              : Border.all(color: colorScheme.outline, width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    key: titleKey,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: foregroundColor,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: foregroundColor ?? colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  /// 有邊框的方形圖示按鈕，比照 `EBStepper._StepperButton` 既有樣式
  /// （8dp 圓角＋`outline` 邊框），供預設集卡片列的「套用到其他書籍」／
  /// 「刪除」按鈕使用；[borderColor] 於套用中（primary 底色）列改傳
  /// `onPrimary`，確保邊框在實心底色上仍清晰可見。
  Widget _buildBorderedIconButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? color,
    Color? borderColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor ?? colorScheme.outline, width: 1.5),
      ),
      child: IconButton(
        key: key,
        icon: Icon(icon, color: color),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }

  /// 固定列（非使用者建立的預設集，不佔用 3 個 slot 名額、不可刪除）：
  /// 一鍵把「字級／字重／行距／段落間距／字距」5 個目前有覆寫的數值欄位
  /// 全部清空，改回本書原始樣式（等同逐一按下每個欄位既有的「恢復本書
  /// 原樣式」按鈕）。副標題刻意不顯示具體數值——這 5 個欄位在「未覆寫」
  /// 狀態下實際套用的是書本自身的原生樣式，App 沒有一個對應的全域數值
  /// 設定可供顯示（`GlobalReaderPrefs` 只涵蓋翻頁模式／螢幕方向／熱區等
  /// 欄位，見 `global_reader_prefs.dart`），顯示假數字會誤導使用者。
  Widget _buildResetToBookDefaultRow() {
    final l10n = AppLocalizations.of(context)!;
    final isActive = !_fontSizeOverridden &&
        !_fontWeightOverridden &&
        !_lineHeightOverridden &&
        !_paragraphSpacingOverridden &&
        !_letterSpacingOverridden;
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = isActive ? colorScheme.onPrimary : null;
    return _buildPresetRow(
      rowKey: const Key('reader_settings_preset_reset_row'),
      titleKey: const Key('reader_settings_preset_reset_label'),
      title: l10n.readerSettingsResetPresetTitle,
      subtitle: l10n.readerSettingsResetPresetSubtitle,
      isActive: isActive,
      trailing: isActive
          ? Row(
              key: const Key('reader_settings_preset_reset_active_indicator'),
              mainAxisSize: MainAxisSize.min,
              children: [Icon(Icons.check, color: foregroundColor)],
            )
          : OutlinedButton(
              key: const Key('reader_settings_preset_reset_apply'),
              onPressed: _resetToBookDefault,
              child: Text(l10n.readerSettingsApplyButton),
            ),
    );
  }

  void _resetToBookDefault() {
    setState(() {
      _fontSizeOverridden = false;
      _fontSize = _defaultFontSize;
      _fontWeightOverridden = false;
      _fontWeightMultiplier = _defaultFontWeightMultiplier;
      _lineHeightOverridden = false;
      _lineHeight = _defaultLineHeight;
      _paragraphSpacingOverridden = false;
      _paragraphSpacing = _defaultParagraphSpacing;
      _letterSpacingOverridden = false;
      _letterSpacing = _defaultLetterSpacing;
      _notifyChanged();
    });
  }

  /// 「字級X・行距Y・橫排/直排」摘要文字（Reference 卡片副標題）：
  /// 對應欄位在 [prefs] 為 `null`（該 preset 未收錄這個欄位）時顯示
  /// 「預設」，不捏造具體數字。
  String _presetSummary(BookReaderPrefs prefs, AppLocalizations l10n) {
    final fontSize =
        prefs.fontSize != null ? (prefs.fontSize! * 16).round().toString() : l10n.readerSettingsPresetDefaultValue;
    final lineHeight =
        prefs.lineHeight != null ? prefs.lineHeight!.toStringAsFixed(1) : l10n.readerSettingsPresetDefaultValue;
    final writingMode = switch (prefs.writingModeOverride) {
      WritingMode.vertical => l10n.readerSettingsWritingModeVerticalLabel,
      WritingMode.horizontal => l10n.readerSettingsWritingModeHorizontalLabel,
      null => l10n.readerSettingsPresetSummaryAutoLabel,
    };
    return l10n.readerSettingsPresetSummaryFormat(fontSize, lineHeight, writingMode);
  }

  Widget _buildPresetSlot(int index) {
    final l10n = AppLocalizations.of(context)!;
    if (index >= widget.layoutPresets.length) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          l10n.readerSettingsPresetEmptySlot,
          key: Key('reader_settings_preset_slot_${index}_empty'),
        ),
      );
    }
    final preset = widget.layoutPresets[index];
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = preset.prefs == _currentDraft;
    final foregroundColor = isActive ? colorScheme.onPrimary : null;
    return _buildPresetRow(
      rowKey: Key('reader_settings_preset_slot_${index}_row'),
      titleKey: Key('reader_settings_preset_slot_${index}_label'),
      title: preset.name,
      subtitle: _presetSummary(preset.prefs, l10n),
      isActive: isActive,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive)
            Row(
              key: Key(
                'reader_settings_preset_slot_${index}_active_indicator',
              ),
              mainAxisSize: MainAxisSize.min,
              children: [Icon(Icons.check, color: foregroundColor)],
            )
          else
            OutlinedButton(
              key: Key('reader_settings_preset_slot_${index}_apply_current'),
              onPressed: () => widget.onApplyPreset(
                preset,
                targetBookIds: [widget.bookId],
              ),
              child: Text(l10n.readerSettingsApplyButton),
            ),
          const SizedBox(width: 4),
          _buildBorderedIconButton(
            key: Key('reader_settings_preset_slot_${index}_apply_others'),
            icon: Icons.library_books,
            tooltip: l10n.readerSettingsApplyToOtherBooksTooltip,
            onPressed: () => _handleApplyPresetToOthers(preset),
            color: foregroundColor,
            borderColor: isActive ? foregroundColor : null,
          ),
          const SizedBox(width: 4),
          _buildBorderedIconButton(
            key: Key('reader_settings_preset_slot_${index}_delete'),
            icon: Icons.delete,
            tooltip: l10n.readerSettingsDeletePresetTooltip,
            onPressed: () => widget.onDeletePreset(preset.id!),
            color: foregroundColor,
            borderColor: isActive ? foregroundColor : null,
          ),
        ],
      ),
    );
  }

  Future<void> _handleApplyPresetToOthers(LayoutPreset preset) async {
    final targets = await widget.onRequestBookPicker(multiSelect: true);
    if (targets == null || targets.isEmpty) return;
    widget.onApplyPreset(preset, targetBookIds: targets);
  }

  Future<void> _handleCopyFromBookToCurrent() async {
    final sources = await widget.onRequestBookPicker(multiSelect: false);
    if (sources == null || sources.isEmpty) return;
    widget.onApplyFromBook(sources.first, targetBookIds: [widget.bookId]);
  }

  Future<void> _handleCopyFromBookToOthers() async {
    final sources = await widget.onRequestBookPicker(multiSelect: false);
    if (sources == null || sources.isEmpty) return;
    final targets = await widget.onRequestBookPicker(multiSelect: true);
    if (targets == null || targets.isEmpty) return;
    widget.onApplyFromBook(sources.first, targetBookIds: targets);
  }
}
