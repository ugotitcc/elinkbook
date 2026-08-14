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
  final List<CustomFont> customFonts;
  final String bookId;
  final List<LayoutPreset> layoutPresets;
  final void Function(BookReaderPrefs currentDraft) onSaveAsPreset;
  final void Function(LayoutPreset preset, {required List<String> targetBookIds})
      onApplyPreset;
  final void Function(String sourceBookId, {required List<String> targetBookIds})
      onApplyFromBook;
  final Future<List<String>?> Function({required bool multiSelect})
      onRequestBookPicker;
  final void Function(int id) onDeletePreset;

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
  late double _fontWeightMultiplier;
  late double _lineHeight;
  late double _paragraphSpacing;
  late double _letterSpacing;
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
    _fontWeightMultiplier = widget.prefs.fontWeight ?? _defaultFontWeightMultiplier;
    _lineHeight = widget.prefs.lineHeight ?? _defaultLineHeight;
    _paragraphSpacing = widget.prefs.paragraphSpacing != null
        ? (widget.prefs.paragraphSpacing! * 10.0).roundToDouble()
        : _defaultParagraphSpacing;
    _letterSpacing = widget.prefs.letterSpacing ?? _defaultLetterSpacing;
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
        _fontWeightMultiplier = widget.prefs.fontWeight ?? _defaultFontWeightMultiplier;
        _lineHeight = widget.prefs.lineHeight ?? _defaultLineHeight;
        _paragraphSpacing = widget.prefs.paragraphSpacing != null
            ? (widget.prefs.paragraphSpacing! * 10.0).roundToDouble()
            : _defaultParagraphSpacing;
        _letterSpacing = widget.prefs.letterSpacing ?? _defaultLetterSpacing;
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

  BookReaderPrefs get _currentDraft => BookReaderPrefs(
        fontFamily: _fontFamily,
        fontSize: _toMultiplier(_fontSize, 16.0),
        fontWeight: _fontWeightMultiplier,
        lineHeight: _lineHeight,
        paragraphSpacing: _toMultiplier(_paragraphSpacing, 10.0),
        letterSpacing: _letterSpacing,
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
                  max: 80,
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
                  min: 0,
                  max: 3,
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
                  keyPrefix: 'reader_settings_letter_spacing',
                  label: '字距',
                  value: _letterSpacing,
                  min: -0.05,
                  max: 1,
                  step: 0.01,
                  displayValue: '${_letterSpacing.toStringAsFixed(2)}em',
                  onChanged: (v) => setState(() {
                    _letterSpacing = double.parse(v.toStringAsFixed(2));
                    _notifyChanged();
                  }),
                ),
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
                SwitchListTile(
                  key: const Key('reader_settings_fullscreen'),
                  title: const Text('全螢幕模式'),
                  value: _fullscreen,
                  onChanged: (v) => setState(() {
                    _fullscreen = v;
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
                const SizedBox(height: 12),
                _buildLayoutPresetSection(),
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
        child: Text('（空）', key: Key('reader_settings_preset_slot_${index}_empty')),
      );
    }
    final preset = widget.layoutPresets[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${preset.name}（${preset.updatedAt.year}/${preset.updatedAt.month}/${preset.updatedAt.day}）',
              key: Key('reader_settings_preset_slot_${index}_label'),
            ),
          ),
          IconButton(
            key: Key('reader_settings_preset_slot_${index}_apply_current'),
            icon: const Icon(Icons.check),
            tooltip: '套用到本書',
            onPressed: () =>
                widget.onApplyPreset(preset, targetBookIds: [widget.bookId]),
          ),
          IconButton(
            key: Key('reader_settings_preset_slot_${index}_apply_others'),
            icon: const Icon(Icons.library_books),
            tooltip: '套用到其他書籍',
            onPressed: () => _handleApplyPresetToOthers(preset),
          ),
          IconButton(
            key: Key('reader_settings_preset_slot_${index}_delete'),
            icon: const Icon(Icons.delete),
            tooltip: '刪除',
            onPressed: () => widget.onDeletePreset(preset.id!),
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
