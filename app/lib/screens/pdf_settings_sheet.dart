import 'package:flutter/material.dart';

import '../reader/book_reader_prefs.dart';
import '../reader/pdf_fit_mode.dart';

/// PDF 專屬版面設定 Bottom Sheet（FR-11），三分頁結構：顯示／濾鏡／裁切，
/// 見 docs/epics/epic-4-pdf-enhance/design.md 決策 #10（不與 EPUB 用的
/// `ReaderSettingsSheet` 共用元件）。本 issue（Issue 2）僅實作「顯示」分頁
/// （Fit 模式三選一）；「濾鏡」「裁切」分頁為 Issue 3-6 預留的空白佔位。
///
/// 純展示、無 I/O：每次選擇立即透過 [onChanged] 回報目前完整的
/// [BookReaderPrefs]（本 issue 只包含 [BookReaderPrefs.pdfFitMode] 欄位，
/// 其餘 PDF 欄位由 Issue 3-6 各自擴充 [_notifyChanged]，比照
/// `ReaderSettingsSheet._notifyChanged` 的既有模式——只需重建目前已追蹤的
/// 本地狀態欄位，因為同一本書不會同時是 EPUB 又是 PDF，未追蹤的欄位維持
/// null 不影響實際使用情境）。持久化由呼叫端（`ReaderScreen`）負責。
class PdfSettingsSheet extends StatefulWidget {
  final BookReaderPrefs prefs;
  final ValueChanged<BookReaderPrefs> onChanged;

  const PdfSettingsSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fitMode = widget.prefs.pdfFitMode ?? PdfFitMode.pageFit;
    _contrast = widget.prefs.pdfContrast ?? 0;
    _brightness = widget.prefs.pdfBrightness ?? 0;
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
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('⚙️ PDF 版面設定',
                  style: TextStyle(fontWeight: FontWeight.bold)),
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
                  _buildPlaceholderTab('裁切功能即將推出'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisplayTab(BuildContext context) {
    const options = [
      (PdfFitMode.pageFit, 'page_fit', Icons.fit_screen, 'Page-fit（整頁）'),
      (PdfFitMode.fitWidth, 'fit_width', Icons.swap_horiz, 'Fit Width（頁寬）'),
      (PdfFitMode.actualSize, 'actual_size', Icons.crop_original, '真實比例 1:1'),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fit 模式'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: options.map((option) {
              final (mode, keySuffix, icon, tooltip) = option;
              final selected = _fitMode == mode;
              return IconButton(
                key: Key('pdf_settings_fit_mode_$keySuffix'),
                icon: Icon(icon),
                tooltip: tooltip,
                color: selected ? Theme.of(context).colorScheme.primary : null,
                onPressed: () => setState(() {
                  _fitMode = mode;
                  _notifyChanged();
                }),
              );
            }).toList(),
          ),
        ],
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

  Widget _buildPlaceholderTab(String message) {
    return Center(child: Text(message));
  }
}
