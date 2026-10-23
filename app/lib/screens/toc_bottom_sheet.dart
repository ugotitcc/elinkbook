import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../reader/book_format.dart';
import '../reader/book_toc_item.dart';
import '../reader/pdf_toc_item.dart';
import '../reader/text_conversion.dart';
import '../reader/text_conversion_mode.dart';
import '../reader/toc_entry.dart';

/// 目錄樹狀清單 Bottom Sheet（epic-24-pdf-engine-rebuild Issue 5，
/// spec.md「目錄（TOC）」），比照專案既有 Bottom Sheet 慣例（`PdfSettingsSheet`
/// ／`ReaderSettingsSheet`／`FxlSettingsSheet`）由呼叫端以
/// `showModalBottomSheet` 開啟。與 `ReaderScreen`／原生端完全解耦：只接收
/// 已解析好的 [entries]／[currentEntry]／[initiallyExpandedEntries]，選中
/// 項目時透過 [onEntrySelected] 回報，本身不知道呼叫端是誰、不直接碰
/// MethodChannel。
///
/// 刻意不使用 `ExpansionTile`：其整個標題列都是單一「點擊展開/收起」熱區，
/// 無法與「點擊標題跳轉」共存於同一節點。改為每個節點一律是可點擊跳轉的
/// `ListTile`，有子項的節點在 `trailing` 額外疊加一個獨立的展開/收起
/// `IconButton`——跳轉與展開/收起是兩個互不干擾的熱區。
///
/// 【審查修正】渲染改用 `ListView.builder` + 展開狀態改變時才重新計算的
/// 攤平清單（[_visibleRows]），不在 `build()` 內遞迴走訪整棵樹直接產生
/// `ListView(children: [...])`——後者會把「目前展開狀態下應可見」的節點
/// 一次性全部實例化成 widget，章節數量多時無法享有 `ListView` 的延遲載入
/// 優勢；`ListView.builder` 只會依需要（螢幕可視範圍附近）建構
/// `itemBuilder` 回傳的 widget。
///
/// 泛化為消費 [BookTocItem]（epic-24 Issue 5）：EPUB 與 PDF 的目錄項目
/// 透過同一個介面傳入，`_buildEntryRow` 內部以 `is PdfTocItem` 判斷是否
/// 顯示頁碼標籤——EPUB／TXT／MD（[TocEntry]）不顯示頁碼標籤
/// （epic-26-architecture-hardening Issue 5，見 plan-issue-5.md）。
class TocBottomSheet extends StatefulWidget {
  final BookFormat? format;
  final List<BookTocItem> entries;

  /// 開啟當下的預設展開集合（通常是 `TocNavigator.findCurrentPath`／
  /// `PdfTocNavigator.findCurrentPath` 的回傳值），僅影響初始畫面；使用者
  /// 點擊展開/收起按鈕後由本 widget 自行管理後續狀態，不會回寫給呼叫端。
  final Set<BookTocItem> initiallyExpandedEntries;

  /// 目前所在章節（用於高亮），`null` 代表尚無法判斷。
  final BookTocItem? currentEntry;

  final ValueChanged<BookTocItem> onEntrySelected;

  /// PDF「縮圖」分頁要顯示的內容（epic-24-pdf-engine-rebuild Issue 7）；
  /// `null` 時該分頁顯示既有的「此功能將於後續版本提供」佔位文字。
  final Widget? thumbnailTabContent;

  /// PDF「搜尋」分頁要顯示的內容（epic-24-pdf-engine-rebuild Issue 6）；
  /// `null` 時該分頁顯示既有的「此功能將於後續版本提供」佔位文字。本
  /// widget 刻意不知道傳入的是什麼（維持與 `ReaderScreen` 解耦的既有設計
  /// 原則，見類別 docstring），只負責把它放進分頁籤殼層的第三個分頁。
  final Widget? searchTabContent;

  /// 簡繁顯示轉換模式（FR-48，epic-42-text-conversion Issue 3）：套用在
  /// [BookTocItem.title] 上，格式無關（EPUB／PDF 目錄項目共用同一套轉換
  /// 邏輯）。預設 `TextConversionMode.original`（不轉換，向後相容既有
  /// 呼叫端／測試，比照 `FxlSettingsSheet.showTextConversion` 既有先例，
  /// 見 plan-issue-1.md Task 8）。
  final TextConversionMode textConversion;

  const TocBottomSheet({
    super.key,
    this.format,
    required this.entries,
    required this.initiallyExpandedEntries,
    required this.currentEntry,
    required this.onEntrySelected,
    this.thumbnailTabContent,
    this.searchTabContent,
    this.textConversion = TextConversionMode.original,
  });

  @override
  State<TocBottomSheet> createState() => _TocBottomSheetState();
}

/// 目錄樹狀清單攤平後的單一可見列（審查修正）：只記錄 [entry] 本身與縮排
/// [depth]，不重複記錄展開狀態——是否展開由 `_TocBottomSheetState._expanded`
/// 這個唯一事實來源判斷，[_FlatTocRow] 只是「目前依展開狀態算出、應該顯示
/// 的節點清單」的其中一列。
class _FlatTocRow {
  final BookTocItem entry;
  final int depth;

  const _FlatTocRow({required this.entry, required this.depth});
}

class _TocBottomSheetState extends State<TocBottomSheet> {
  late Set<BookTocItem> _expanded;
  late List<_FlatTocRow> _visibleRows;

  /// 一列目錄項目的預估高度（`ListTile` 預設最小高度），只用來估算開啟時的
  /// 初始捲動位置；實際位置由 [_currentRowKey] 在第一幀後校正。
  static const double _estimatedRowHeight = 56;

  /// 標記「目前章節」那一列，供第一幀後 `Scrollable.ensureVisible` 校正位置。
  final GlobalKey _currentRowKey = GlobalKey();
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _expanded = Set.of(widget.initiallyExpandedEntries);
    _visibleRows = _flatten(widget.entries, depth: 0);
    // 開啟時直接把目前章節捲進畫面，長目錄不必每次從頭往下滑；
    // 目前章節上方留約兩列，讓使用者看得到前後文。
    final currentIndex =
        _visibleRows.indexWhere((row) => identical(row.entry, widget.currentEntry));
    _scrollController = ScrollController(
      initialScrollOffset:
          currentIndex <= 2 ? 0 : (currentIndex - 2) * _estimatedRowHeight,
    );
    if (currentIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final rowContext = _currentRowKey.currentContext;
        if (!mounted || rowContext == null) return;
        Scrollable.ensureVisible(rowContext, alignment: 0.3);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 依目前 [_expanded] 狀態，把樹狀結構攤平成「目前應該顯示」的列清單
  /// （前序走訪，符合閱讀順序）——收起的子樹完全不會出現在回傳結果中，
  /// `ListView.builder` 因此連「存在但不可見」的節點都不需要知道。
  List<_FlatTocRow> _flatten(List<BookTocItem> nodes, {required int depth}) {
    final rows = <_FlatTocRow>[];
    for (final node in nodes) {
      rows.add(_FlatTocRow(entry: node, depth: depth));
      if (node.children.isNotEmpty && _expanded.contains(node)) {
        rows.addAll(_flatten(node.children, depth: depth + 1));
      }
    }
    return rows;
  }

  void _toggleExpanded(BookTocItem node) {
    setState(() {
      if (_expanded.contains(node)) {
        _expanded.remove(node);
      } else {
        _expanded.add(node);
      }
      _visibleRows = _flatten(widget.entries, depth: 0);
    });
  }

  Widget _buildTocList() {
    final l10n = AppLocalizations.of(context)!;
    final isEmpty = widget.entries.isEmpty;
    return ListView.builder(
      key: const Key('toc_bottom_sheet_list'),
      controller: _scrollController,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      // entries 為空時只有一列提示；其餘索引對應 _visibleRows[index]。
      itemCount: isEmpty ? 1 : _visibleRows.length,
      itemBuilder: (context, index) {
        if (isEmpty) {
          return Padding(
            key: const Key('toc_bottom_sheet_empty_text'),
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text(l10n.readerTocEmptyMessage)),
          );
        }
        return _buildEntryRow(_visibleRows[index]);
      },
    );
  }

  /// 固定在清單上方的標題列與關閉鈕：不放進捲動清單，長目錄往下捲時
  /// 關閉鈕仍在畫面上。
  Widget _buildHeader() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l10n.readerTocTitle,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            key: const Key('toc_bottom_sheet_close_button'),
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isPdf = widget.format == BookFormat.pdf;
    // 高度上限 85%：不蓋滿整個螢幕，頂端保留可點擊關閉的空白。
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: isPdf ? MainAxisSize.max : MainAxisSize.min,
          children: [
            _buildHeader(),
            if (isPdf)
              Expanded(child: _buildPdfTabs(l10n))
            else
              Flexible(child: _buildTocList()),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfTabs(AppLocalizations l10n) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: l10n.readerTocTabChapters),
              Tab(text: l10n.readerTocTabThumbnails),
              Tab(text: l10n.readerTocTabSearch),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildTocList(),
                widget.thumbnailTabContent ??
                    Center(child: Text(l10n.readerFeatureComingSoon)),
                widget.searchTabContent ??
                    Center(child: Text(l10n.readerFeatureComingSoon)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// [pageLabel] 為 `null` 時目錄項目不顯示頁碼標籤（epic-26-architecture-hardening
  /// Issue 5，選項 A：EPUB／TXT／MD 目錄項目不再嘗試估算頁碼，見
  /// plan-issue-5.md）——目前只有 [PdfTocItem] 在解析大綱當下就已知目標
  /// 頁碼，其餘 [BookTocItem] 實作一律不顯示頁碼標籤，僅顯示標題。
  Widget _buildEntryRow(_FlatTocRow row) {
    final node = row.entry;
    final isCurrent = identical(node, widget.currentEntry);
    final String? pageLabel = node is PdfTocItem
        ? (node.pageIndex == null ? '…' : (node.pageIndex! + 1).toString())
        : null;

    return Padding(
      key: isCurrent ? _currentRowKey : null,
      padding: EdgeInsets.only(left: row.depth * 16),
      child: ListTile(
        key: Key('toc_entry_${node.stableId}'),
        title: Text(
          convertText(node.title, widget.textConversion),
          style: isCurrent ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
        selected: isCurrent,
        onTap: () => widget.onEntrySelected(node),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pageLabel != null)
              Text(pageLabel, key: Key('toc_entry_page_${node.stableId}')),
            if (node.children.isNotEmpty)
              IconButton(
                key: Key('toc_entry_expand_${node.stableId}'),
                icon: Icon(
                  _expanded.contains(node) ? Icons.expand_less : Icons.expand_more,
                ),
                onPressed: () => _toggleExpanded(node),
              ),
          ],
        ),
      ),
    );
  }
}
