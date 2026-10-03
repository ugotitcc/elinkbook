import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/dual_page_direction.dart';
import '../reader/dual_page_mode.dart';
import '../reader/text_conversion_mode.dart';
import 'widgets/eb_field_card.dart';
import 'widgets/eb_option_chip_group.dart';
import 'widgets/text_conversion_icon.dart';

/// EPUB 固定版面（FXL 漫畫）專屬的精簡版設定 Bottom Sheet（見
/// docs/epics/epic-16-dual-page/spec.md「模組」段落）：提供「雙頁模式」
/// 三態切換與「全螢幕模式」開關（epic-19-shelf-reading-enhance Issue 1），
/// 不與 PdfSettingsSheet／ReaderSettingsSheet 共用元件（固定版面沒有
/// 字型/裁切/濾鏡等其餘設定）。[isEinkMode] 目前不影響任何渲染分支（本
/// 畫面沒有數值型 Slider/EBStepper 需要二選一切換），僅為呼叫端三個
/// 版面設定面板統一介面而保留（見 epic-39-layout-settings-redesign
/// spec.md「FxlSettingsSheet」段落）。
class FxlSettingsSheet extends StatefulWidget {
  final BookReaderPrefs prefs;
  final ValueChanged<BookReaderPrefs> onChanged;
  final bool isEinkMode;
  final bool showTextConversion;

  const FxlSettingsSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
    required this.isEinkMode,
    this.showTextConversion = true,
  });

  @override
  State<FxlSettingsSheet> createState() => _FxlSettingsSheetState();
}

class _FxlSettingsSheetState extends State<FxlSettingsSheet> {
  late DualPageMode _dualPageMode;
  late DualPageDirection _dualPageDirection;
  late bool _fullscreen;
  late bool _showHeader;
  late bool _showFooter;
  late TextConversionMode? _textConversionOverride;

  @override
  void initState() {
    super.initState();
    _dualPageMode = widget.prefs.dualPageMode ?? DualPageMode.auto;
    _dualPageDirection =
        widget.prefs.dualPageDirection ?? DualPageDirection.rtl;
    _fullscreen = widget.prefs.fullscreen ?? false;
    _showHeader = widget.prefs.showHeader ?? false;
    _showFooter = widget.prefs.showFooter ?? false;
    _textConversionOverride = widget.prefs.textConversionOverride;
  }

  void _notifyChanged() {
    // 【重要設計決策】textConversionOverride 是此面板第一個「使用者可選
    // 『使用全域預設』把欄位清回 null」的欄位，而 `copyWith()` 是
    // `newValue ?? this.value` 語意、無法明確清空（見 book_reader_prefs.dart
    // 既有文件註解）——故改為整列字面量建構（比照 ReaderSettingsSheet.
    // _currentDraft 既有模式），明確列出 widget.prefs 的其餘所有欄位以保留
    // 原值，並以 state 變數覆寫五個既有欄位與 textConversionOverride。
    widget.onChanged(
      BookReaderPrefs(
        fontFamily: widget.prefs.fontFamily,
        fontSize: widget.prefs.fontSize,
        fontWeight: widget.prefs.fontWeight,
        lineHeight: widget.prefs.lineHeight,
        paragraphSpacing: widget.prefs.paragraphSpacing,
        letterSpacing: widget.prefs.letterSpacing,
        pageMargins: widget.prefs.pageMargins,
        marginTop: widget.prefs.marginTop,
        marginBottom: widget.prefs.marginBottom,
        marginLeft: widget.prefs.marginLeft,
        marginRight: widget.prefs.marginRight,
        textAlign: widget.prefs.textAlign,
        publisherStyles: widget.prefs.publisherStyles,
        writingModeOverride: widget.prefs.writingModeOverride,
        pageTurnModeOverride: widget.prefs.pageTurnModeOverride,
        screenOrientationOverride: widget.prefs.screenOrientationOverride,
        pdfFitMode: widget.prefs.pdfFitMode,
        pdfContrast: widget.prefs.pdfContrast,
        pdfBrightness: widget.prefs.pdfBrightness,
        pdfBoldStrength: widget.prefs.pdfBoldStrength,
        pdfCropMode: widget.prefs.pdfCropMode,
        pdfCropRect: widget.prefs.pdfCropRect,
        dualPageMode: _dualPageMode,
        dualPageCoverAlone: widget.prefs.dualPageCoverAlone,
        dualPageDirection: _dualPageDirection,
        pdfPageTurnAnimation: widget.prefs.pdfPageTurnAnimation,
        pdfPageTurnMode: widget.prefs.pdfPageTurnMode,
        showHeader: _showHeader,
        showFooter: _showFooter,
        columnMode: widget.prefs.columnMode,
        columnSize: widget.prefs.columnSize,
        fullscreen: _fullscreen,
        textConversionOverride: _textConversionOverride,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dualPageOptions = [
      (
        DualPageMode.auto,
        'auto',
        Icons.stay_current_landscape,
        l10n.readerDualPageAutoTooltip,
        l10n.readerDualPageAutoLabel,
      ),
      (
        DualPageMode.always,
        'always',
        Icons.view_column,
        l10n.readerDualPageAlwaysTooltip,
        l10n.readerDualPageAlwaysLabel,
      ),
      (
        DualPageMode.never,
        'never',
        Icons.crop_portrait,
        l10n.readerDualPageNeverTooltip,
        l10n.readerDualPageNeverLabel,
      ),
    ];
    final directionOptions = [
      (
        DualPageDirection.ltr,
        'ltr',
        Icons.arrow_forward,
        l10n.readerDualPageDirectionLtrTooltip,
        l10n.readerDualPageDirectionLtrLabel,
      ),
      (
        DualPageDirection.rtl,
        'rtl',
        Icons.arrow_back,
        l10n.readerDualPageDirectionRtlTooltip,
        l10n.readerDualPageDirectionRtlLabel,
      ),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.readerFxlSettingsTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  key: const Key('fxl_settings_close_button'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(l10n.readerDualPageModeLabel,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            EBOptionChipGroup<DualPageMode>(
              items: dualPageOptions.map((option) {
                final (mode, keySuffix, icon, tooltip, label) = option;
                return EBOptionChipItem<DualPageMode>(
                  itemKey: Key('fxl_settings_dual_page_mode_$keySuffix'),
                  value: mode,
                  icon: icon,
                  label: label,
                  tooltip: tooltip,
                );
              }).toList(),
              groupValue: _dualPageMode,
              visualDensity: VisualDensity.compact,
              onSelected: (v) => setState(() {
                _dualPageMode = v;
                _notifyChanged();
              }),
            ),
            const SizedBox(height: 16),
            Text(l10n.readerPageDirectionLabel,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            EBOptionChipGroup<DualPageDirection>(
              items: directionOptions.map((option) {
                final (direction, keySuffix, icon, tooltip, label) = option;
                return EBOptionChipItem<DualPageDirection>(
                  itemKey: Key('fxl_settings_direction_$keySuffix'),
                  value: direction,
                  icon: icon,
                  label: label,
                  tooltip: tooltip,
                );
              }).toList(),
              groupValue: _dualPageDirection,
              visualDensity: VisualDensity.compact,
              onSelected: (v) => setState(() {
                _dualPageDirection = v;
                _notifyChanged();
              }),
            ),
            const SizedBox(height: 16),
            if (widget.showTextConversion) ...[
              Text(l10n.readerTextConversionOverrideLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              EBOptionChipGroup<TextConversionMode?>(
                items: [
                  EBOptionChipItem<TextConversionMode?>(
                    itemKey: const Key('fxl_settings_text_conversion_global'),
                    value: null,
                    icon: Icons.tune,
                    label: l10n.readerGlobalLabel,
                    tooltip: l10n.readerUseGlobalDefaultTooltip,
                  ),
                  EBOptionChipItem<TextConversionMode?>(
                    itemKey: const Key('fxl_settings_text_conversion_original'),
                    value: TextConversionMode.original,
                    icon: Icons.article_outlined,
                    label: l10n.readerTextConversionOriginalLabel,
                    tooltip: l10n.readerTextConversionOriginalLabel,
                  ),
                  EBOptionChipItem<TextConversionMode?>(
                    itemKey: const Key('fxl_settings_text_conversion_traditional'),
                    value: TextConversionMode.toTraditional,
                    iconWidget:
                        const TextConversionIcon(mode: TextConversionMode.toTraditional),
                    label: l10n.readerTextConversionTraditionalLabel,
                    tooltip: l10n.readerTextConversionTraditionalTooltip,
                  ),
                  EBOptionChipItem<TextConversionMode?>(
                    itemKey: const Key('fxl_settings_text_conversion_simplified'),
                    value: TextConversionMode.toSimplified,
                    iconWidget:
                        const TextConversionIcon(mode: TextConversionMode.toSimplified),
                    label: l10n.readerTextConversionSimplifiedLabel,
                    tooltip: l10n.readerTextConversionSimplifiedTooltip,
                  ),
                ],
                groupValue: _textConversionOverride,
                visualDensity: VisualDensity.compact,
                onSelected: (v) => setState(() {
                  _textConversionOverride = v;
                  _notifyChanged();
                }),
              ),
              const SizedBox(height: 16),
            ],
            EBFieldCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                key: const Key('fxl_settings_fullscreen'),
                title: Text(l10n.readerFullscreenModeLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                value: _fullscreen,
                onChanged: (v) => setState(() {
                  _fullscreen = v;
                  _notifyChanged();
                }),
              ),
            ),
            EBFieldCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                key: const Key('fxl_settings_show_header'),
                title: Text(l10n.readerShowHeaderLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
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
                key: const Key('fxl_settings_show_footer'),
                title: Text(l10n.readerShowFooterLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                value: _showFooter,
                onChanged: (v) => setState(() {
                  _showFooter = v;
                  _notifyChanged();
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
