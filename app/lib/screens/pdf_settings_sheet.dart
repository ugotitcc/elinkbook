import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../reader/book_reader_prefs.dart';
import '../reader/dual_page_direction.dart';
import '../reader/dual_page_mode.dart';
import '../reader/pdf_fit_mode.dart';
import '../reader/pdf_crop_mode.dart';
import '../reader/pdf_page_turn_animation.dart';
import '../reader/pdf_page_turn_mode.dart';
import 'widgets/eb_field_card.dart';
import 'widgets/eb_option_chip_group.dart';
import 'widgets/eb_stepper.dart';

/// PDF 專屬版面設定 Bottom Sheet（FR-11），三分頁結構：顯示／濾鏡／裁切，
/// 見 docs/epics/epic-4-pdf-enhance/design.md 決策 #10（不與 EPUB 用的
/// `ReaderSettingsSheet` 共用元件）。三分頁（Fit 模式、濾鏡、裁切模式）
/// 皆已完整實作。
///
/// 純展示、無 I/O：每次選擇立即透過 [onChanged] 回報目前完整的
/// [BookReaderPrefs]（`_notifyChanged` 只需重建目前已追蹤的本地狀態欄位
/// ＋ 原樣帶回 [BookReaderPrefs.pdfCropRect]——因為同一本書不會同時是
/// EPUB 又是 PDF，未追蹤的 EPUB 欄位維持 null 不影響實際使用情境）。
/// 「手動選區」選項點擊時透過 [onRequestManualCrop] 通知呼叫端
/// （`PdfSettingsSheet` 本身不直接操作 `PdfReaderView`，維持既有單向資料
/// 流，見 spec.md「模組」段落）；持久化由呼叫端（`ReaderScreen`）負責。
/// [isEinkMode] 決定濾鏡分頁數值列採用一般主題的 `Slider`＋±按鈕，或
/// E-Ink 模式的 `EBStepper`。
class PdfSettingsSheet extends StatefulWidget {
  final BookReaderPrefs prefs;
  final ValueChanged<BookReaderPrefs> onChanged;
  final VoidCallback onRequestManualCrop;
  final bool isEinkMode;

  const PdfSettingsSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
    required this.onRequestManualCrop,
    required this.isEinkMode,
  });

  @override
  State<PdfSettingsSheet> createState() => _PdfSettingsSheetState();
}

class _PdfSettingsSheetState extends State<PdfSettingsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late PdfFitMode _fitMode;
  late double _contrast;
  late double _brightness;
  late double _boldStrength; // 內部儲存為 UI 顯示用的 0..100，送出前才換算回 0..1
  late PdfCropMode _cropMode;
  late DualPageMode _dualPageMode;
  late bool _dualPageCoverAlone;
  late DualPageDirection _dualPageDirection;
  late PdfPageTurnAnimation _pageTurnAnimation;
  late PdfPageTurnMode _pageTurnMode;
  late bool _showFooter;
  late bool _fullscreen;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fitMode = widget.prefs.pdfFitMode ?? PdfFitMode.pageFit;
    _contrast = widget.prefs.pdfContrast ?? 0;
    _brightness = widget.prefs.pdfBrightness ?? 0;
    _boldStrength = (widget.prefs.pdfBoldStrength ?? 0) * 100;
    _cropMode = widget.prefs.pdfCropMode ?? PdfCropMode.none;
    _dualPageMode = widget.prefs.dualPageMode ?? DualPageMode.auto;
    _dualPageCoverAlone = widget.prefs.dualPageCoverAlone ?? true;
    _dualPageDirection =
        widget.prefs.dualPageDirection ?? DualPageDirection.rtl;
    _pageTurnAnimation =
        widget.prefs.pdfPageTurnAnimation ?? PdfPageTurnAnimation.slide;
    _pageTurnMode = widget.prefs.pdfPageTurnMode ?? PdfPageTurnMode.paginated;
    _showFooter = widget.prefs.showFooter ?? true;
    _fullscreen = widget.prefs.fullscreen ?? false;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _notifyChanged() {
    widget.onChanged(
      BookReaderPrefs(
        pdfFitMode: _fitMode,
        pdfContrast: _contrast,
        pdfBrightness: _brightness,
        pdfBoldStrength: _boldStrength / 100,
        pdfCropMode: _cropMode,
        // pdfCropRect 由原生端計算、透過 ReaderScreen.onCropRectComputed
        // 另一條路徑寫入，本分頁不直接控制，但必須原樣帶回（讀取目前的
        // widget.prefs，不是本地狀態），否則使用者調整本分頁任何一個控制項
        // 都會把已算好的裁切矩形靜默清空成 null。
        pdfCropRect: widget.prefs.pdfCropRect,
        dualPageMode: _dualPageMode,
        dualPageCoverAlone: _dualPageCoverAlone,
        dualPageDirection: _dualPageDirection,
        pdfPageTurnAnimation: _pageTurnAnimation,
        pdfPageTurnMode: _pageTurnMode,
        showFooter: _showFooter,
        fullscreen: _fullscreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: SizedBox(
        // TabBarView 無法在無邊界的父層自我量測高度（不同於 ReaderSettingsSheet
        // 用 ListView(shrinkWrap: true) 的做法），固定高度是本 widget 刻意的
        // 簡化選擇。
        height: 400,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.readerPdfSettingsTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    key: const Key('pdf_settings_close_button'),
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(key: const Key('pdf_settings_tab_display'), text: l10n.readerPdfSettingsTabDisplay),
                Tab(key: const Key('pdf_settings_tab_filters'), text: l10n.readerPdfSettingsTabFilters),
                Tab(key: const Key('pdf_settings_tab_crop'), text: l10n.readerPdfSettingsTabCrop),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDisplayTab(context),
                  _buildFiltersTab(),
                  _buildCropTab(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisplayTab(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fitOptions = [
      (
        PdfFitMode.pageFit,
        'page_fit',
        Icons.fit_screen,
        l10n.readerPdfFitPageTooltip,
        l10n.readerPdfFitPageLabel
      ),
      (
        PdfFitMode.fitWidth,
        'fit_width',
        Icons.swap_horiz,
        l10n.readerPdfFitWidthTooltip,
        l10n.readerPdfFitWidthLabel,
      ),
      (
        PdfFitMode.actualSize,
        'actual_size',
        Icons.crop_original,
        l10n.readerPdfFitActualTooltip,
        l10n.readerPdfFitActualLabel,
      ),
    ];
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
        l10n.readerDualPageAlwaysLabel
      ),
      (
        DualPageMode.never,
        'never',
        Icons.crop_portrait,
        l10n.readerDualPageNeverTooltip,
        l10n.readerDualPageNeverLabel
      ),
    ];
    final directionOptions = [
      (
        DualPageDirection.ltr,
        'ltr',
        Icons.format_textdirection_l_to_r,
        l10n.readerPdfDirectionLtrTooltip,
        l10n.readerPdfDirectionLtrLabel,
      ),
      (
        DualPageDirection.rtl,
        'rtl',
        Icons.format_textdirection_r_to_l,
        l10n.readerPdfDirectionRtlTooltip,
        l10n.readerPdfDirectionRtlLabel,
      ),
    ];
    final pageTurnModeOptions = [
      (
        PdfPageTurnMode.paginated,
        'paginated',
        Icons.looks_one,
        l10n.readerPdfPageTurnModePaginatedTooltip,
        l10n.readerPdfPageTurnModePaginatedLabel,
      ),
      (
        PdfPageTurnMode.scroll,
        'scroll',
        Icons.swap_vert,
        l10n.readerPdfPageTurnModeScrollTooltip,
        l10n.readerPdfPageTurnModeScrollLabel,
      ),
    ];
    final pageTurnAnimationOptions = [
      (PdfPageTurnAnimation.slide, 'slide', Icons.swipe, l10n.readerPdfPageTurnAnimationSlide, l10n.readerPdfPageTurnAnimationSlide),
      (PdfPageTurnAnimation.none, 'none', Icons.flash_on, l10n.readerPdfPageTurnAnimationNone, l10n.readerPdfPageTurnAnimationNone),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        key: const Key('pdf_settings_display_scroll'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.readerPdfFitModeLabel, style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            EBOptionChipGroup<PdfFitMode>(
              items: fitOptions.map((option) {
                final (mode, keySuffix, icon, tooltip, label) = option;
                return EBOptionChipItem<PdfFitMode>(
                  itemKey: Key('pdf_settings_fit_mode_$keySuffix'),
                  value: mode,
                  icon: icon,
                  label: label,
                  tooltip: tooltip,
                );
              }).toList(),
              groupValue: _fitMode,
              onSelected: (v) => setState(() {
                _fitMode = v;
                _notifyChanged();
              }),
            ),
            const SizedBox(height: 16),
            Text(l10n.readerPdfPageTurnModeLabel, style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            EBOptionChipGroup<PdfPageTurnMode>(
              items: pageTurnModeOptions.map((option) {
                final (mode, keySuffix, icon, tooltip, label) = option;
                return EBOptionChipItem<PdfPageTurnMode>(
                  itemKey: Key('pdf_settings_page_turn_mode_$keySuffix'),
                  value: mode,
                  icon: icon,
                  label: label,
                  tooltip: tooltip,
                );
              }).toList(),
              groupValue: _pageTurnMode,
              onSelected: (v) => setState(() {
                _pageTurnMode = v;
                _notifyChanged();
              }),
            ),
            const SizedBox(height: 16),
            Text(l10n.readerDualPageModeLabel, style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            EBOptionChipGroup<DualPageMode>(
              items: dualPageOptions.map((option) {
                final (mode, keySuffix, icon, tooltip, label) = option;
                return EBOptionChipItem<DualPageMode>(
                  itemKey: Key('pdf_settings_dual_page_mode_$keySuffix'),
                  value: mode,
                  icon: icon,
                  label: label,
                  tooltip: tooltip,
                );
              }).toList(),
              groupValue: _dualPageMode,
              onSelected: (v) => setState(() {
                _dualPageMode = v;
                _notifyChanged();
              }),
            ),
            const SizedBox(height: 16),
            EBFieldCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                key: const Key('pdf_settings_dual_page_cover_alone'),
                title: Text(l10n.readerPdfDualPageCoverAloneLabel, style: TextStyle(fontWeight: FontWeight.bold)),
                value: _dualPageCoverAlone,
                onChanged: (v) => setState(() {
                  _dualPageCoverAlone = v;
                  _notifyChanged();
                }),
              ),
            ),
            EBFieldCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                key: const Key('pdf_settings_show_footer'),
                title: Text(l10n.readerShowFooterLabel, style: TextStyle(fontWeight: FontWeight.bold)),
                value: _showFooter,
                onChanged: (v) => setState(() {
                  _showFooter = v;
                  _notifyChanged();
                }),
              ),
            ),
            EBFieldCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                key: const Key('pdf_settings_fullscreen'),
                title: Text(l10n.readerFullscreenModeLabel, style: TextStyle(fontWeight: FontWeight.bold)),
                value: _fullscreen,
                onChanged: (v) => setState(() {
                  _fullscreen = v;
                  _notifyChanged();
                }),
              ),
            ),
            const SizedBox(height: 16),
            Text(l10n.readerPdfPageOrientationLabel, style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            EBOptionChipGroup<DualPageDirection>(
              items: directionOptions.map((option) {
                final (direction, keySuffix, icon, tooltip, label) = option;
                return EBOptionChipItem<DualPageDirection>(
                  itemKey: Key('pdf_settings_dual_page_direction_$keySuffix'),
                  value: direction,
                  icon: icon,
                  label: label,
                  tooltip: tooltip,
                );
              }).toList(),
              groupValue: _dualPageDirection,
              onSelected: (v) => setState(() {
                _dualPageDirection = v;
                _notifyChanged();
              }),
            ),
            if (_pageTurnMode == PdfPageTurnMode.scroll) ...[
              const SizedBox(height: 16),
              Text(l10n.readerPdfPageTurnAnimationLabel, style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              EBOptionChipGroup<PdfPageTurnAnimation>(
                items: pageTurnAnimationOptions.map((option) {
                  final (animation, keySuffix, icon, tooltip, label) = option;
                  return EBOptionChipItem<PdfPageTurnAnimation>(
                    itemKey: Key('pdf_settings_page_turn_animation_$keySuffix'),
                    value: animation,
                    icon: icon,
                    label: label,
                    tooltip: tooltip,
                  );
                }).toList(),
                groupValue: _pageTurnAnimation,
                onSelected: (v) => setState(() {
                  _pageTurnAnimation = v;
                  _notifyChanged();
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersTab() {
    final l10n = AppLocalizations.of(context)!;
    // 視覺還原（VISUAL_ANALYSIS.md）：每個數值列改用 EBFieldCard 包裹後
    // 整體高度增加，固定 400px 高的 Bottom Sheet（見 build() 註解）容不下
    // 3 列，比照 _buildDisplayTab 既有的 SingleChildScrollView 做法補上
    // 捲動，避免 RenderFlex 溢位。
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        key: const Key('pdf_settings_filters_scroll'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSliderRow(
              keyPrefix: 'pdf_settings_contrast',
              label: l10n.readerPdfContrastLabel,
              value: _contrast,
              min: -100,
              max: 100,
              step: 5,
              onChanged: (v) => setState(() {
                _contrast = v;
                _notifyChanged();
              }),
            ),
            _buildSliderRow(
              keyPrefix: 'pdf_settings_brightness',
              label: l10n.readerPdfBrightnessLabel,
              value: _brightness,
              min: -100,
              max: 100,
              step: 5,
              onChanged: (v) => setState(() {
                _brightness = v;
                _notifyChanged();
              }),
            ),
            _buildSliderRow(
              keyPrefix: 'pdf_settings_bold_strength',
              label: l10n.readerPdfBoldStrengthLabel,
              value: _boldStrength,
              min: 0,
              max: 100,
              step: 10,
              onChanged: (v) => setState(() {
                _boldStrength = v;
                _notifyChanged();
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCropTab(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final options = [
      (
        PdfCropMode.none,
        'none',
        Icons.crop_free,
        l10n.readerPdfCropNoneTooltip,
        l10n.readerPdfCropNoneLabel
      ),
      (
        PdfCropMode.autoDetect,
        'auto',
        Icons.auto_fix_high,
        l10n.readerPdfCropAutoTooltip,
        l10n.readerPdfCropAutoLabel
      ),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.readerPdfCropModeLabel, style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          EBOptionChipGroup<PdfCropMode>(
            items: [
              ...options.map((option) {
                final (mode, keySuffix, icon, tooltip, label) = option;
                return EBOptionChipItem<PdfCropMode>(
                  itemKey: Key('pdf_settings_crop_mode_$keySuffix'),
                  value: mode,
                  icon: icon,
                  label: label,
                  tooltip: tooltip,
                );
              }),
              // 手動選區：點擊只通知呼叫端進入裁切互動模式（不直接改變
              // _cropMode／呼叫 _notifyChanged），實際的 pdfCropMode=manual
              // 與 pdfCropRect 由 ReaderScreen 在使用者完成框選確認後才
              // 一併寫入（見 spec.md「ReaderScreen 內部行為異動」）。
              // 審查修正 I4（review-issues.md）／I1（review-spec.md）：改用
              // EBOptionChipItem.onTap 承載，value 直接填入真實的
              // PdfCropMode.manual——EBOptionChipGroup 對 onTap != null 的
              // 項目預設強制 forceUnselected: true，不需要再用 bool sentinel
              // （value: true, groupValue: false）製造「恆不相等」的效果。
              // epic-60：本項另傳 highlightWhenCurrent: true 作為例外，見下方。
              EBOptionChipItem<PdfCropMode>(
                itemKey: const Key('pdf_settings_crop_mode_manual'),
                value: PdfCropMode.manual,
                icon: Icons.crop,
                label: l10n.readerPdfCropManualLabel,
                tooltip: l10n.readerPdfCropManualTooltip,
                onTap: () => widget.onRequestManualCrop(),
                // epic-60：目前模式為 manual 時反白，否則三顆全不反白、
                // 使用者看不出目前是手動裁切。點擊仍是重新框選。
                highlightWhenCurrent: true,
              ),
            ],
            groupValue: _cropMode,
            onSelected: (v) => setState(() {
              _cropMode = v;
              _notifyChanged();
            }),
          ),
        ],
      ),
    );
  }

  /// 比照 `ReaderSettingsSheet._buildSliderRow` 的既有樣式（滑桿＋±微調
  /// 按鈕），本 widget 依 design.md 決策 #10 不與 `ReaderSettingsSheet`
  /// 共用元件，故獨立實作一份同樣式的 helper。
  Widget _buildSliderRow({
    required String keyPrefix,
    required String label,
    required double value,
    required double min,
    required double max,
    required double step,
    required ValueChanged<double> onChanged,
  }) {
    final divisions = ((max - min) / step).round();
    final clampedValue = value.clamp(min, max);
    final displayValue = clampedValue.round().toString();
    return EBFieldCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (!widget.isEinkMode) Text(displayValue),
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
}
