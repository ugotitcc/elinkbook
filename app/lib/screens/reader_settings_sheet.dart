import 'dart:math';

import 'package:flutter/material.dart';

import '../reader/app_font.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/column_mode.dart';
import '../reader/epub_text_align.dart';
import '../reader/page_turn_mode.dart';
import '../reader/screen_orientation_setting.dart';
import '../reader/writing_mode.dart';

/// 版面設定 Bottom Sheet（FR-09／FR-10 字型、數值型控制項與三個持久化覆寫
/// 選擇器），比照 prototype/index.html 第 1379-1520 行設計。
///
/// 純展示、無 I/O：每次互動即時透過 [onChanged] 回報目前完整的
/// [BookReaderPrefs]，持久化與更新 `EpubReaderView` 建構參數、螢幕方向鎖定
/// 皆由呼叫端（`ReaderScreen`）負責——本 widget 只負責回報使用者選擇的覆寫
/// 值，不負責解析「覆寫值 `??` 自動偵測結果／全域預設值」的最終生效值
/// （見 `ReaderScreen._resolvedWritingMode`／`_resolvedPageTurnMode`／
/// `_resolvedScreenOrientation`）。
class ReaderSettingsSheet extends StatefulWidget {
  final BookReaderPrefs prefs;
  final ValueChanged<BookReaderPrefs> onChanged;

  const ReaderSettingsSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
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
  static const _defaultLineHeight = 1.5;
  static const _defaultParagraphSpacing = 10.0;
  static const _defaultPageMargins = 15.0;

  late AppFont? _fontFamily;
  late double _fontSize;
  late double _fontWeightMultiplier; // Readium 倍率語意，UI 顯示時 ×400
  late double _lineHeight;
  late double _paragraphSpacing;
  late double _pageMargins;
  late EpubTextAlign? _textAlign;
  late bool _publisherStyles;
  late WritingMode? _writingModeOverride;
  late PageTurnMode? _pageTurnModeOverride;
  late ScreenOrientationSetting? _screenOrientationOverride;
  late bool _showHeader;
  late bool _showFooter;
  late ColumnMode _columnMode;
  late double _columnSize;

  @override
  void initState() {
    super.initState();
    _fontFamily = widget.prefs.fontFamily;
    _fontSize = widget.prefs.fontSize != null
        ? (widget.prefs.fontSize! * 16.0).roundToDouble()
        : _defaultFontSize;
    _fontWeightMultiplier = widget.prefs.fontWeight ?? _defaultFontWeightMultiplier;
    _lineHeight = widget.prefs.lineHeight ?? _defaultLineHeight;
    _paragraphSpacing = widget.prefs.paragraphSpacing != null
        ? (widget.prefs.paragraphSpacing! * 10.0).roundToDouble()
        : _defaultParagraphSpacing;
    _pageMargins = widget.prefs.pageMargins != null
        ? (widget.prefs.pageMargins! * 15.0).roundToDouble()
        : _defaultPageMargins;
    _textAlign = widget.prefs.textAlign;
    _publisherStyles = widget.prefs.publisherStyles ?? true;
    _writingModeOverride = widget.prefs.writingModeOverride;
    _pageTurnModeOverride = widget.prefs.pageTurnModeOverride;
    _screenOrientationOverride = widget.prefs.screenOrientationOverride;
    _showHeader = widget.prefs.showHeader ?? true;
    _showFooter = widget.prefs.showFooter ?? true;
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
        _fontWeightMultiplier = widget.prefs.fontWeight ?? _defaultFontWeightMultiplier;
        _lineHeight = widget.prefs.lineHeight ?? _defaultLineHeight;
        _paragraphSpacing = widget.prefs.paragraphSpacing != null
            ? (widget.prefs.paragraphSpacing! * 10.0).roundToDouble()
            : _defaultParagraphSpacing;
        _pageMargins = widget.prefs.pageMargins != null
            ? (widget.prefs.pageMargins! * 15.0).roundToDouble()
            : _defaultPageMargins;
        _textAlign = widget.prefs.textAlign;
        _publisherStyles = widget.prefs.publisherStyles ?? true;
        _writingModeOverride = widget.prefs.writingModeOverride;
        _pageTurnModeOverride = widget.prefs.pageTurnModeOverride;
        _screenOrientationOverride = widget.prefs.screenOrientationOverride;
        _showHeader = widget.prefs.showHeader ?? true;
        _showFooter = widget.prefs.showFooter ?? true;
        _columnMode = widget.prefs.columnMode ?? ColumnMode.auto;
        _columnSize = widget.prefs.columnSize ?? 720.0;
      });
    }
  }

  double _toMultiplier(double value, double base) {
    return ((value / base) * 10000).round() / 10000;
  }

  void _notifyChanged() {
    widget.onChanged(BookReaderPrefs(
      fontFamily: _fontFamily,
      fontSize: _toMultiplier(_fontSize, 16.0),
      fontWeight: _fontWeightMultiplier,
      lineHeight: _lineHeight,
      paragraphSpacing: _toMultiplier(_paragraphSpacing, 10.0),
      pageMargins: _toMultiplier(_pageMargins, 15.0),
      textAlign: _textAlign,
      publisherStyles: _publisherStyles,
      writingModeOverride: _writingModeOverride,
      pageTurnModeOverride: _pageTurnModeOverride,
      screenOrientationOverride: _screenOrientationOverride,
      showHeader: _showHeader,
      showFooter: _showFooter,
      columnMode: _columnMode,
      columnSize: _columnSize,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                _buildFontFamilyDropdown(),
                _buildSliderRow(
                  keyPrefix: 'reader_settings_font_size',
                  label: '字型大小',
                  value: _fontSize,
                  min: 12,
                  max: 40,
                  step: 1,
                  displayValue: _fontSize.round().toString(),
                  onChanged: (v) => setState(() {
                    _fontSize = v;
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
                  onChanged: (v) => setState(() {
                    _fontWeightMultiplier = v / 400;
                    _notifyChanged();
                  }),
                ),
                _buildSliderRow(
                  keyPrefix: 'reader_settings_line_height',
                  label: '行高',
                  value: _lineHeight,
                  min: 1.2,
                  max: 2.5,
                  step: 0.1,
                  displayValue: _lineHeight.toStringAsFixed(1),
                  onChanged: (v) => setState(() {
                    _lineHeight = double.parse(v.toStringAsFixed(1));
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
                  onChanged: (v) => setState(() {
                    _paragraphSpacing = v;
                    _notifyChanged();
                  }),
                ),
                _buildSliderRow(
                  keyPrefix: 'reader_settings_page_margins',
                  label: '邊距',
                  value: _pageMargins,
                  min: 0,
                  max: 50,
                  step: 1,
                  displayValue: _pageMargins.round().toString(),
                  onChanged: (v) => setState(() {
                    _pageMargins = v;
                    _notifyChanged();
                  }),
                ),
                const SizedBox(height: 12),
                _buildTextAlignRow(),
                const SizedBox(height: 12),
                SwitchListTile(
                  key: const Key('reader_settings_disable_book_css'),
                  title: const Text('停用書本 CSS'),
                  value: !_publisherStyles,
                  onChanged: (v) => setState(() {
                    _publisherStyles = !v;
                    _notifyChanged();
                  }),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  key: const Key('reader_settings_show_header'),
                  title: const Text('顯示頁首'),
                  value: _showHeader,
                  onChanged: (v) => setState(() {
                    _showHeader = v;
                    _notifyChanged();
                  }),
                ),
                SwitchListTile(
                  key: const Key('reader_settings_show_footer'),
                  title: const Text('顯示頁尾'),
                  value: _showFooter,
                  onChanged: (v) => setState(() {
                    _showFooter = v;
                    _notifyChanged();
                  }),
                ),
                const SizedBox(height: 12),
                _buildColumnModeRow(),
                const SizedBox(height: 12),
                _buildWritingModeOverrideRow(),
                const SizedBox(height: 12),
                _buildScreenOrientationOverrideRow(),
                const SizedBox(height: 12),
                _buildPageTurnModeOverrideRow(),
              ],
            ),
          ),
        ],
      ),
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
          Row(
            children: [
              IconButton(
                key: const Key('reader_settings_column_mode_auto'),
                icon: const Icon(Icons.auto_awesome),
                tooltip: '自動',
                color: _columnMode == ColumnMode.auto
                    ? Theme.of(context).colorScheme.primary
                    : null,
                onPressed: () => setState(() {
                  _columnMode = ColumnMode.auto;
                  _notifyChanged();
                }),
              ),
              IconButton(
                key: const Key('reader_settings_column_mode_single'),
                icon: const Icon(Icons.crop_portrait),
                tooltip: '單欄',
                color: _columnMode == ColumnMode.single
                    ? Theme.of(context).colorScheme.primary
                    : null,
                onPressed: () => setState(() {
                  _columnMode = ColumnMode.single;
                  _notifyChanged();
                }),
              ),
              IconButton(
                key: const Key('reader_settings_column_mode_double'),
                icon: const Icon(Icons.book),
                tooltip: '雙欄',
                color: _columnMode == ColumnMode.double
                    ? Theme.of(context).colorScheme.primary
                    : null,
                onPressed: () => setState(() {
                  _columnMode = ColumnMode.double;
                  _notifyChanged();
                }),
              ),
            ],
          ),
          if (_columnMode == ColumnMode.auto) ...[
            const SizedBox(height: 8),
            Text('欄位大小 ${_columnSize.round()}px'),
            Slider(
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
        ],
      ),
    );
  }

  Widget _buildFontFamilyDropdown() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Expanded(child: Text('單書閱讀字型')),
          DropdownButton<AppFont?>(
            key: const Key('reader_settings_font_family'),
            value: _fontFamily,
            items: [
              const DropdownMenuItem<AppFont?>(
                value: null,
                child: Text('使用書本內建字型'),
              ),
              ...AppFont.values.map(
                (font) => DropdownMenuItem<AppFont?>(
                  value: font,
                  child: Text(_fontDisplayName(font)),
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

  Widget _buildSliderRow({
    required String keyPrefix,
    required String label,
    required double value,
    required double min,
    required double max,
    required double step,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    final divisions = ((max - min) / step).round();
    final clampedValue = value.clamp(min, max);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(label), Text(displayValue)],
          ),
          Row(
            children: [
              IconButton(
                key: Key('${keyPrefix}_decrement'),
                icon: const Icon(Icons.remove),
                onPressed: clampedValue - step < min - 1e-9
                    ? null
                    : () => onChanged((clampedValue - step).clamp(min, max)),
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
                    : () => onChanged((clampedValue + step).clamp(min, max)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextAlignRow() {
    const options = [
      (EpubTextAlign.center, Icons.format_align_center, '置中'),
      (EpubTextAlign.justify, Icons.format_align_justify, '左右對齊'),
      (EpubTextAlign.start, Icons.first_page, '起始邊對齊'),
      (EpubTextAlign.end, Icons.last_page, '結尾邊對齊'),
      (EpubTextAlign.left, Icons.format_align_left, '靠左'),
      (EpubTextAlign.right, Icons.format_align_right, '靠右'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('文字對齊'),
        Wrap(
          spacing: 4,
          children: options.map((option) {
            final (align, icon, tooltip) = option;
            final selected = _textAlign == align;
            return IconButton(
              key: Key('reader_settings_text_align_${align.name}'),
              icon: Icon(icon),
              tooltip: tooltip,
              color: selected ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => setState(() {
                _textAlign = align;
                _notifyChanged();
              }),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 排版方向覆寫（三態，FR-10）：`null`＝採用書籍排版（自動偵測結果，見
  /// `ReaderScreen._resolvedWritingMode`）、`vertical`＝強制直排、
  /// `horizontal`＝強制橫排。
  Widget _buildWritingModeOverrideRow() {
    const options = [
      (null, 'book', Icons.auto_stories, '採用書籍排版'),
      (WritingMode.vertical, 'vertical', Icons.text_rotate_vertical, '強制直排'),
      (WritingMode.horizontal, 'horizontal', Icons.text_rotation_none, '強制橫排'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('排版方向模式'),
        Wrap(
          spacing: 4,
          children: options.map((option) {
            final (mode, keySuffix, icon, tooltip) = option;
            final selected = _writingModeOverride == mode;
            return IconButton(
              key: Key('reader_settings_writing_mode_$keySuffix'),
              icon: Icon(icon),
              tooltip: tooltip,
              color: selected ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => setState(() {
                _writingModeOverride = mode;
                _notifyChanged();
              }),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 翻頁模式覆寫（FR-10／FR-38，全域/單書雙層解析）：`null`＝使用全域
  /// 預設值（見 `ReaderScreen._resolvedPageTurnMode`），非 `null`＝單書
  /// 覆寫。
  Widget _buildPageTurnModeOverrideRow() {
    const options = [
      (null, 'global', Icons.tune, '使用全域預設'),
      (PageTurnMode.paginated, 'paginated', Icons.menu_book, '點擊翻頁'),
      (PageTurnMode.scroll, 'scroll', Icons.swap_vert, '滾動翻頁'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('翻頁模式覆寫'),
        Wrap(
          spacing: 4,
          children: options.map((option) {
            final (mode, keySuffix, icon, tooltip) = option;
            final selected = _pageTurnModeOverride == mode;
            return IconButton(
              key: Key('reader_settings_page_turn_mode_$keySuffix'),
              icon: Icon(icon),
              tooltip: tooltip,
              color: selected ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => setState(() {
                _pageTurnModeOverride = mode;
                _notifyChanged();
              }),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 螢幕方向覆寫（FR-10／FR-37，全域/單書雙層解析）：`null`＝使用全域
  /// 預設值（見 `ReaderScreen._resolvedScreenOrientation`），非 `null`＝
  /// 單書覆寫。0°／180° 與 90°／270° 分別共用同一個 Material icon，以
  /// `Transform.rotate` 配合角度旋轉提升視覺辨識度，tooltip 文字消歧。
  Widget _buildScreenOrientationOverrideRow() {
    // (setting, keySuffix, icon, tooltip, rotationAngle)
    const options = <(
      ScreenOrientationSetting?,
      String,
      IconData,
      String,
      double,
    )>[
      (null, 'global', Icons.tune, '使用全域預設', 0.0),
      (ScreenOrientationSetting.auto, 'auto', Icons.screen_rotation, '自動旋轉', 0.0),
      (ScreenOrientationSetting.lock0, 'lock0', Icons.stay_current_portrait, '鎖定 0°', 0.0),
      (ScreenOrientationSetting.lock90, 'lock90', Icons.stay_current_landscape, '鎖定 90°', 0.0),
      (ScreenOrientationSetting.lock180, 'lock180', Icons.stay_current_portrait, '鎖定 180°', pi),
      (ScreenOrientationSetting.lock270, 'lock270', Icons.stay_current_landscape, '鎖定 270°', pi * 1.5),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('螢幕方向鎖定覆寫'),
        Wrap(
          spacing: 4,
          children: options.map((option) {
            final (setting, keySuffix, icon, tooltip, angle) = option;
            final selected = _screenOrientationOverride == setting;
            final iconWidget = Icon(icon);
            return IconButton(
              key: Key('reader_settings_screen_orientation_$keySuffix'),
              icon: angle == 0.0
                  ? iconWidget
                  : Transform.rotate(angle: angle, child: iconWidget),
              tooltip: tooltip,
              color: selected ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => setState(() {
                _screenOrientationOverride = setting;
                _notifyChanged();
              }),
            );
          }).toList(),
        ),
      ],
    );
  }
}
