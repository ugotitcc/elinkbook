import 'package:flutter/material.dart';

import '../reader/book_reader_prefs.dart';
import '../reader/dual_page_direction.dart';
import '../reader/dual_page_mode.dart';
import '../reader/pdf_fit_mode.dart';
import '../reader/pdf_crop_mode.dart';
import '../reader/pdf_page_turn_animation.dart';

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
class PdfSettingsSheet extends StatefulWidget {
  final BookReaderPrefs prefs;
  final ValueChanged<BookReaderPrefs> onChanged;
  final VoidCallback onRequestManualCrop;

  const PdfSettingsSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
    required this.onRequestManualCrop,
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
    _dualPageDirection = widget.prefs.dualPageDirection ?? DualPageDirection.rtl;
    _pageTurnAnimation =
        widget.prefs.pdfPageTurnAnimation ?? PdfPageTurnAnimation.slide;
    _showFooter = widget.prefs.showFooter ?? true;
    _fullscreen = widget.prefs.fullscreen ?? false;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _notifyChanged() {
    widget.onChanged(BookReaderPrefs(
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
      showFooter: _showFooter,
      fullscreen: _fullscreen,
    ));
  }

  @override
  Widget build(BuildContext context) {
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
                  const Expanded(
                    child: Text('⚙️ PDF 版面設定',
                        style: TextStyle(fontWeight: FontWeight.bold)),
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
              tabs: const [
                Tab(key: Key('pdf_settings_tab_display'), text: '顯示'),
                Tab(key: Key('pdf_settings_tab_filters'), text: '濾鏡'),
                Tab(key: Key('pdf_settings_tab_crop'), text: '裁切'),
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
    const fitOptions = [
      (PdfFitMode.pageFit, 'page_fit', Icons.fit_screen, 'Page-fit（整頁）'),
      (PdfFitMode.fitWidth, 'fit_width', Icons.swap_horiz, 'Fit Width（頁寬）'),
      (PdfFitMode.actualSize, 'actual_size', Icons.crop_original, '真實比例 1:1'),
    ];
    const dualPageOptions = [
      (DualPageMode.auto, 'auto', Icons.stay_current_landscape, '自動（橫向雙頁）'),
      (DualPageMode.always, 'always', Icons.view_column, '永遠雙頁'),
      (DualPageMode.never, 'never', Icons.crop_portrait, '永遠單頁'),
    ];
    const directionOptions = [
      (
        DualPageDirection.ltr,
        'ltr',
        Icons.format_textdirection_l_to_r,
        '左到右',
      ),
      (
        DualPageDirection.rtl,
        'rtl',
        Icons.format_textdirection_r_to_l,
        '右到左（日漫慣例）',
      ),
    ];
    const pageTurnAnimationOptions = [
      (PdfPageTurnAnimation.slide, 'slide', Icons.swipe, '滑動'),
      (PdfPageTurnAnimation.none, 'none', Icons.flash_on, '無'),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      // 外層 Bottom Sheet 是固定 height: 400（見 build() 的 SizedBox），
      // 本分頁持續新增控制項會讓內容總高度有機會超出固定高度；改用
      // SingleChildScrollView 包裹，避免觸發 RenderFlex overflow（審查
      // 修正，見 tmp/epic-16/reviews/review-plan-issue-4.md）。
      child: SingleChildScrollView(
        key: const Key('pdf_settings_display_scroll'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Fit 模式'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: fitOptions.map((option) {
                final (mode, keySuffix, icon, tooltip) = option;
                final selected = _fitMode == mode;
                return IconButton(
                  key: Key('pdf_settings_fit_mode_$keySuffix'),
                  icon: Icon(icon),
                  tooltip: tooltip,
                  color:
                      selected ? Theme.of(context).colorScheme.primary : null,
                  onPressed: () => setState(() {
                    _fitMode = mode;
                    _notifyChanged();
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('雙頁模式'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: dualPageOptions.map((option) {
                final (mode, keySuffix, icon, tooltip) = option;
                final selected = _dualPageMode == mode;
                return IconButton(
                  key: Key('pdf_settings_dual_page_mode_$keySuffix'),
                  icon: Icon(icon),
                  tooltip: tooltip,
                  color:
                      selected ? Theme.of(context).colorScheme.primary : null,
                  onPressed: () => setState(() {
                    _dualPageMode = mode;
                    _notifyChanged();
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              key: const Key('pdf_settings_dual_page_cover_alone'),
              title: const Text('封面獨立顯示'),
              value: _dualPageCoverAlone,
              onChanged: (v) => setState(() {
                _dualPageCoverAlone = v;
                _notifyChanged();
              }),
            ),
            SwitchListTile(
              key: const Key('pdf_settings_show_footer'),
              title: const Text('顯示頁尾'),
              value: _showFooter,
              onChanged: (v) => setState(() {
                _showFooter = v;
                _notifyChanged();
              }),
            ),
            SwitchListTile(
              key: const Key('pdf_settings_fullscreen'),
              title: const Text('全螢幕模式'),
              value: _fullscreen,
              onChanged: (v) => setState(() {
                _fullscreen = v;
                _notifyChanged();
              }),
            ),
            const SizedBox(height: 16),
            const Text('頁面方向'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: directionOptions.map((option) {
                final (direction, keySuffix, icon, tooltip) = option;
                final selected = _dualPageDirection == direction;
                return IconButton(
                  key: Key('pdf_settings_dual_page_direction_$keySuffix'),
                  icon: Icon(icon),
                  tooltip: tooltip,
                  color:
                      selected ? Theme.of(context).colorScheme.primary : null,
                  onPressed: () => setState(() {
                    _dualPageDirection = direction;
                    _notifyChanged();
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('換頁動畫'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: pageTurnAnimationOptions.map((option) {
                final (animation, keySuffix, icon, tooltip) = option;
                final selected = _pageTurnAnimation == animation;
                return IconButton(
                  key: Key('pdf_settings_page_turn_animation_$keySuffix'),
                  icon: Icon(icon),
                  tooltip: tooltip,
                  color:
                      selected ? Theme.of(context).colorScheme.primary : null,
                  onPressed: () => setState(() {
                    _pageTurnAnimation = animation;
                    _notifyChanged();
                  }),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSliderRow(
            keyPrefix: 'pdf_settings_contrast',
            label: '對比度',
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
            label: '亮度',
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
            label: '加粗強度',
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
    );
  }

  Widget _buildCropTab(BuildContext context) {
    const options = [
      (PdfCropMode.none, 'none', Icons.crop_free, '不裁切'),
      (PdfCropMode.autoDetect, 'auto', Icons.auto_fix_high, '智慧自動'),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('裁切模式'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              ...options.map((option) {
                final (mode, keySuffix, icon, tooltip) = option;
                final selected = _cropMode == mode;
                return IconButton(
                  key: Key('pdf_settings_crop_mode_$keySuffix'),
                  icon: Icon(icon),
                  tooltip: tooltip,
                  color:
                      selected ? Theme.of(context).colorScheme.primary : null,
                  onPressed: () => setState(() {
                    _cropMode = mode;
                    _notifyChanged();
                  }),
                );
              }),
              // 手動選區：點擊只通知呼叫端進入裁切互動模式（不直接改變
              // _cropMode／呼叫 _notifyChanged），實際的 pdfCropMode=manual
              // 與 pdfCropRect 由 ReaderScreen 在使用者完成框選確認後才
              // 一併寫入（見 spec.md「ReaderScreen 內部行為異動」）。
              IconButton(
                key: const Key('pdf_settings_crop_mode_manual'),
                icon: const Icon(Icons.crop),
                tooltip: '手動選區',
                onPressed: widget.onRequestManualCrop,
              ),
            ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(label), Text(clampedValue.round().toString())],
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
}
