import 'package:flutter/material.dart';

import '../reader/app_font.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/epub_text_align.dart';

/// 版面設定 Bottom Sheet（FR-09／FR-10 字型與數值型控制項），比照
/// prototype/index.html 第 1379-1520 行設計。排版方向／翻頁模式／螢幕方向
/// 三個覆寫選擇器屬 Issue 4，尚未加入本檔案。
///
/// 純展示、無 I/O：每次互動即時透過 [onChanged] 回報目前完整的
/// [BookReaderPrefs]，持久化與更新 `EpubReaderView` 建構參數皆由呼叫端
/// （`ReaderScreen`）負責。[prefs] 中本 widget 不控制的三個欄位
/// （`writingModeOverride`／`pageTurnModeOverride`／`screenOrientationOverride`，
/// Issue 4 範圍）在每次 [onChanged] 回呼時原樣保留，不會被清空或覆寫。
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
  static const _defaultFontWeightMultiplier = 1.0; // UI 顯示 400
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
  late bool _disableBookCss; // publisherStyles 的反向語意

  @override
  void initState() {
    super.initState();
    _fontFamily = widget.prefs.fontFamily;
    _fontSize = widget.prefs.fontSize ?? _defaultFontSize;
    _fontWeightMultiplier =
        widget.prefs.fontWeight ?? _defaultFontWeightMultiplier;
    _lineHeight = widget.prefs.lineHeight ?? _defaultLineHeight;
    _paragraphSpacing =
        widget.prefs.paragraphSpacing ?? _defaultParagraphSpacing;
    _pageMargins = widget.prefs.pageMargins ?? _defaultPageMargins;
    _textAlign = widget.prefs.textAlign;
    _disableBookCss = widget.prefs.publisherStyles == false;
  }

  void _notifyChanged() {
    widget.onChanged(BookReaderPrefs(
      fontFamily: _fontFamily,
      fontSize: _fontSize,
      fontWeight: _fontWeightMultiplier,
      lineHeight: _lineHeight,
      paragraphSpacing: _paragraphSpacing,
      pageMargins: _pageMargins,
      textAlign: _textAlign,
      publisherStyles: !_disableBookCss,
      // Issue 4 範圍的三個欄位：原樣保留，本 widget 不控制。
      writingModeOverride: widget.prefs.writingModeOverride,
      pageTurnModeOverride: widget.prefs.pageTurnModeOverride,
      screenOrientationOverride: widget.prefs.screenOrientationOverride,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          const Text('⚙️ 版面設定', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
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
            value: _disableBookCss,
            onChanged: (v) => setState(() {
              _disableBookCss = v;
              _notifyChanged();
            }),
          ),
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
                onPressed: clampedValue - step < min
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
                onPressed: clampedValue + step > max
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
}
