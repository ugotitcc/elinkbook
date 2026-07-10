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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fitMode = widget.prefs.pdfFitMode ?? PdfFitMode.pageFit;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _notifyChanged() {
    widget.onChanged(BookReaderPrefs(pdfFitMode: _fitMode));
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
                  _buildPlaceholderTab('濾鏡功能即將推出'),
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
      (PdfFitMode.fitWidth, 'fit_width', Icons.swap_horiz, 'Fit Width（項寬）'),
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

  Widget _buildPlaceholderTab(String message) {
    return Center(child: Text(message));
  }
}
