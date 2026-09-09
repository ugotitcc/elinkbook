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
import '../reader/writing_mode.dart';
import 'widgets/eb_field_card.dart';
import 'widgets/eb_option_chip_group.dart';
import 'widgets/eb_stepper.dart';

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
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '⚙️ 版面設定',
                    style: TextStyle(fontWeight: FontWeight.bold),
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
          Expanded(
            child: DefaultTabController(
              length: 4,
              child: Column(
                children: [
                  const TabBar(
                    key: Key('reader_settings_tab_bar'),
                    tabs: [
                      Tab(
                        key: Key('reader_settings_tab_text_content'),
                        text: '文字',
                      ),
                      Tab(key: Key('reader_settings_tab_boundary'), text: '邊界'),
                      Tab(
                        key: Key('reader_settings_tab_presentation'),
                        text: '呈現',
                      ),
                      Tab(
                        key: Key('reader_settings_tab_preferences'),
                        text: '預設集',
                      ),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      // 【不可逆的技術決策】必須為 NeverScrollableScrollPhysics，
                      // 只能點擊 TabBar 切換——「文字」／「邊界」頁籤內
                      // 各有數個橫向拖曳型 Slider，TabBarView 底層 PageView 的
                      // 預設水平滑動手勢會與這些 Slider 搶手勢競技場，導致調整
                      // 滑桿時意外切換頁籤。**注意**：這與被借鏡的既有先例
                      // TocBottomSheet（app/lib/screens/toc_bottom_sheet.dart）
                      // 不同——該處頁籤內容是章節清單/縮圖格/搜尋結果，沒有
                      // 橫向拖曳型控制項，不需要這道防護，不可為了「跟先例一致」
                      // 而移除本行（epic-28-reader-settings-enhancements Issue 5
                      // 審查發現，詳見 design.md「2026-08-15 追加」審查回應）。
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildTextContentTab(),
                        _buildBoundaryTab(),
                        _buildPresentationTab(),
                        _buildPreferencesTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
    return ListView(
      key: const Key('reader_settings_tab_text_content_list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _buildFontFamilyDropdown(),
        _buildSliderRow(
          keyPrefix: 'reader_settings_font_size',
          label: '字型大小',
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
          label: '字型粗細',
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
          label: '行高',
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
          label: '段落間距',
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
          label: '字距',
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
            title: const Text('停用書本 CSS'),
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
    return ListView(
      key: const Key('reader_settings_tab_boundary_list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _buildSliderRow(
          keyPrefix: 'reader_settings_margin_top',
          label: '上邊界',
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
          label: '下邊界',
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
          label: '左邊界',
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
          label: '右邊界',
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
            title: const Text('顯示頁首'),
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
            title: const Text('顯示頁尾'),
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
    return ListView(
      key: const Key('reader_settings_tab_presentation_list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        EBFieldCard(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            key: const Key('reader_settings_fullscreen'),
            title: const Text('全螢幕模式'),
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
      ],
    );
  }

  Widget _buildPreferencesTab() {
    return ListView(
      key: const Key('reader_settings_tab_preferences_list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [_buildLayoutPresetSection()],
    );
  }

  Widget _buildColumnModeRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('欄數'),
          const SizedBox(height: 4),
          EBOptionChipGroup<ColumnMode>(
            items:
                [
                  (ColumnMode.auto, 'auto', Icons.auto_awesome, '自動', '自動'),
                  (
                    ColumnMode.single,
                    'single',
                    Icons.crop_portrait,
                    '單欄',
                    '單欄',
                  ),
                  (ColumnMode.double, 'double', Icons.book, '雙欄', '雙欄'),
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
                        ? '欄位大小'
                        : '欄位大小 ${_columnSize.round()}px',
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
    return EBFieldCard(
      child: Row(
        children: [
          const Expanded(child: Text('單書閱讀字型')),
          DropdownButton<String?>(
            key: const Key('reader_settings_font_family'),
            value: _fontFamily,
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('使用書本內建字型'),
              ),
              ...AppFont.values.map(
                (font) => DropdownMenuItem<String?>(
                  value: font.familyName,
                  child: Text(_fontDisplayName(font)),
                ),
              ),
              ...widget.customFonts.map(
                (font) => DropdownMenuItem<String?>(
                  value: font.familyName,
                  child: Text(font.displayName),
                ),
              ),
            ],
            onChanged: (value) => setState(() {
              _fontFamily = value;
              _notifyChanged();
            }),
          ),
        ],
      ),
    );
  }

  String _fontDisplayName(AppFont font) {
    switch (font) {
      case AppFont.sourceHanSans:
        return '思源黑體';
      case AppFont.sourceHanSerif:
        return '思源宋體';
      case AppFont.guanKiapTsingKhai:
        return '原俠正楷';
      case AppFont.taiwanPearl:
        return '台灣圓體';
      case AppFont.genRyuMinTW:
        return '源流明體';
    }
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
    final divisions = ((max - min) / step).round();
    final clampedValue = value.clamp(min, max);
    return EBFieldCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
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
                    _buildOverrideBadge('此書已覆寫'),
                    IconButton(
                      key: Key('${keyPrefix}_reset'),
                      icon: const Icon(Icons.block),
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      tooltip: '恢復本書原樣式',
                      onPressed: onReset,
                    ),
                  ],
                )
              else if (isOverridden == false)
                Tooltip(
                  message: '跟隨本書原樣式，尚未調整',
                  child: _buildOverrideBadge(
                    '使用全域預設',
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
    const options = [
      (EpubTextAlign.center, Icons.format_align_center, '置中', '置中'),
      (EpubTextAlign.justify, Icons.format_align_justify, '左右對齊', '齊行'),
      (EpubTextAlign.start, Icons.first_page, '起始邊對齊', '起始'),
      (EpubTextAlign.end, Icons.last_page, '結尾邊對齊', '結尾'),
      (EpubTextAlign.left, Icons.format_align_left, '靠左', '靠左'),
      (EpubTextAlign.right, Icons.format_align_right, '靠右', '靠右'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('文字對齊'),
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
    const options = [
      (null, 'book', Icons.auto_stories, '採用書籍排版', '書籍'),
      (
        WritingMode.vertical,
        'vertical',
        Icons.text_rotate_vertical,
        '強制直排',
        '直排',
      ),
      (
        WritingMode.horizontal,
        'horizontal',
        Icons.text_rotation_none,
        '強制橫排',
        '橫排',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('排版方向模式'),
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
    const options = [
      (null, 'global', Icons.tune, '使用全域預設', '全域'),
      (PageTurnMode.paginated, 'paginated', Icons.menu_book, '點擊翻頁', '點擊'),
      (PageTurnMode.scroll, 'scroll', Icons.swap_vert, '滾動翻頁', '滾動'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('翻頁模式覆寫'),
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

  /// 螢幕方向覆寫（FR-10／FR-37，全域/單書雙層解析）：`null`＝使用全域
  /// 預設值（見 `ReaderScreen._resolvedScreenOrientation`），非 `null`＝
  /// 單書覆寫。0°／180° 與 90°／270° 分別共用同一個 Material icon，以
  /// `Transform.rotate` 配合角度旋轉提升視覺辨識度，tooltip 文字消歧。
  Widget _buildScreenOrientationOverrideRow() {
    // (setting, keySuffix, icon, tooltip, rotationAngle, label)
    const options =
        <(ScreenOrientationSetting?, String, IconData, String, double, String)>[
          (null, 'global', Icons.tune, '使用全域預設', 0.0, '全域'),
          (
            ScreenOrientationSetting.auto,
            'auto',
            Icons.screen_rotation,
            '自動旋轉',
            0.0,
            '自動',
          ),
          (
            ScreenOrientationSetting.lock0,
            'lock0',
            Icons.stay_current_portrait,
            '鎖定 0°',
            0.0,
            '0°',
          ),
          (
            ScreenOrientationSetting.lock90,
            'lock90',
            Icons.stay_current_landscape,
            '鎖定 90°',
            0.0,
            '90°',
          ),
          (
            ScreenOrientationSetting.lock180,
            'lock180',
            Icons.stay_current_portrait,
            '鎖定 180°',
            pi,
            '180°',
          ),
          (
            ScreenOrientationSetting.lock270,
            'lock270',
            Icons.stay_current_landscape,
            '鎖定 270°',
            pi * 1.5,
            '270°',
          ),
        ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('螢幕方向鎖定覆寫'),
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
  /// Issue 3）：3 個 slot 卡片（存在則顯示名稱＋更新日期＋套用/刪除
  /// 按鈕，空則顯示「（空）」）、「另存為新預設集」按鈕、「從其他書籍
  /// 複製」兩顆按鈕。本 widget 只負責觸發對應 callback，實際 I/O、
  /// 「存量是否已滿 3 組」判斷、命名輸入、覆蓋選擇/確認對話框皆由呼叫端
  /// （`ReaderScreen`）完成，見 spec.md「UI 元件責任劃分」。
  Widget _buildLayoutPresetSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('版面設定預設集', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...List.generate(3, _buildPresetSlot),
        const SizedBox(height: 8),
        ElevatedButton(
          key: const Key('reader_settings_save_as_preset'),
          onPressed: () => widget.onSaveAsPreset(_currentDraft),
          child: const Text('另存為新預設集'),
        ),
        const SizedBox(height: 16),
        const Text('從其他書籍複製', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('reader_settings_copy_from_book_current'),
                onPressed: _handleCopyFromBookToCurrent,
                child: const Text('複製到本書'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const Key('reader_settings_copy_from_book_others'),
                onPressed: _handleCopyFromBookToOthers,
                child: const Text('複製到其他書籍'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetSlot(int index) {
    if (index >= widget.layoutPresets.length) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '（空）',
          key: Key('reader_settings_preset_slot_${index}_empty'),
        ),
      );
    }
    final preset = widget.layoutPresets[index];
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = preset.prefs == _currentDraft;
    final foregroundColor = isActive ? colorScheme.onInverseSurface : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        key: Key('reader_settings_preset_slot_${index}_row'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? colorScheme.inverseSurface : null,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? null
              : Border.all(color: colorScheme.outline, width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${preset.name}（${preset.updatedAt.year}/${preset.updatedAt.month}/${preset.updatedAt.day}）',
                key: Key('reader_settings_preset_slot_${index}_label'),
                style: TextStyle(color: foregroundColor),
              ),
            ),
            if (isActive)
              Row(
                key: Key(
                  'reader_settings_preset_slot_${index}_active_indicator',
                ),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, color: foregroundColor, size: 18),
                  const SizedBox(width: 4),
                  Text('已套用', style: TextStyle(color: foregroundColor)),
                ],
              )
            else
              IconButton(
                key: Key('reader_settings_preset_slot_${index}_apply_current'),
                icon: const Icon(Icons.check),
                tooltip: '套用到本書',
                onPressed: () => widget.onApplyPreset(
                  preset,
                  targetBookIds: [widget.bookId],
                ),
              ),
            IconButton(
              key: Key('reader_settings_preset_slot_${index}_apply_others'),
              icon: Icon(Icons.library_books, color: foregroundColor),
              tooltip: '套用到其他書籍',
              onPressed: () => _handleApplyPresetToOthers(preset),
            ),
            IconButton(
              key: Key('reader_settings_preset_slot_${index}_delete'),
              icon: Icon(Icons.delete, color: foregroundColor),
              tooltip: '刪除',
              onPressed: () => widget.onDeletePreset(preset.id!),
            ),
          ],
        ),
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
