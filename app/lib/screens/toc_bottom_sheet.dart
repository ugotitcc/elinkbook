import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../reader/book_format.dart';
import '../reader/book_toc_item.dart';
import '../reader/epub_page_estimator.dart';
import '../reader/pdf_toc_item.dart';
import '../reader/resolved_preferences.dart';
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
/// 透過同一個介面傳入，`_buildEntryRow` 內部以 `is TocEntry`／
/// `is PdfTocItem` 分流頁碼顯示邏輯。
class TocBottomSheet extends StatefulWidget {
  final BookFormat? format;
  final List<BookTocItem> entries;

  /// 開啟當下的預設展開集合（通常是 `TocNavigator.findCurrentPath`／
  /// `PdfTocNavigator.findCurrentPath` 的回傳值），僅影響初始畫面；使用者
  /// 點擊展開/收起按鈕後由本 widget 自行管理後續狀態，不會回寫給呼叫端。
  final Set<BookTocItem> initiallyExpandedEntries;

  /// 目前所在章節（用於高亮），`null` 代表尚無法判斷。
  final BookTocItem? currentEntry;

  /// 全書字元數快取，`null` 時所有 EPUB 項目的頁碼顯示佔位符（`…`）；
  /// PDF 項目不使用此欄位（頁碼在解析大綱當下就已知，見
  /// `PdfReaderView._loadTableOfContents`），PDF 呼叫端可傳入任何值
  /// （建議 `ValueNotifier<int?>(null)`）。
  final ValueListenable<int?> totalCharacterCountListenable;

  /// 目前生效的版面參數，供換算「每螢幕可容納字元數」（僅 EPUB 項目使用，
  /// 見 [_buildEntryRow]）。
  final ResolvedPreferences resolved;

  final ValueChanged<BookTocItem> onEntrySelected;

  /// PDF「搜尋」分頁要顯示的內容（epic-24-pdf-engine-rebuild Issue 6）；
  /// `null` 時該分頁顯示既有的「此功能將於後續版本提供」佔位文字。本
  /// widget 刻意不知道傳入的是什麼（維持與 `ReaderScreen` 解耦的既有設計
  /// 原則，見類別 docstring），只負責把它放進分頁籤殼層的第三個分頁。
  final Widget? searchTabContent;

  const TocBottomSheet({
    super.key,
    this.format,
    required this.entries,
    required this.initiallyExpandedEntries,
    required this.currentEntry,
    required this.totalCharacterCountListenable,
    required this.resolved,
    required this.onEntrySelected,
    this.searchTabContent,
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

  @override
  void initState() {
    super.initState();
    _expanded = Set.of(widget.initiallyExpandedEntries);
    _visibleRows = _flatten(widget.entries, depth: 0);
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

  Widget _buildTocList(int? totalCharacterCount) {
    final isEmpty = widget.entries.isEmpty;
    return ListView.builder(
      key: const Key('toc_bottom_sheet_list'),
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      // +1：索引 0 固定是標題列；entries 為空時額外 +1 顯示提示列；
      // 其餘索引對應 _visibleRows[index - 1]。
      itemCount: _visibleRows.length + 1 + (isEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('📖 目錄',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  key: const Key('toc_bottom_sheet_close_button'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        }
        if (isEmpty && index == 1) {
          return const Padding(
            key: Key('toc_bottom_sheet_empty_text'),
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('本書無目錄資料')),
          );
        }
        return _buildEntryRow(_visibleRows[index - 1], totalCharacterCount);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ValueListenableBuilder<int?>(
        valueListenable: widget.totalCharacterCountListenable,
        builder: (context, totalCharacterCount, _) {
          if (widget.format == BookFormat.pdf) {
            return DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: '章節目錄'),
                      Tab(text: '縮圖'),
                      Tab(text: '搜尋'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildTocList(totalCharacterCount),
                        const Center(child: Text('此功能將於後續版本提供')),
                        widget.searchTabContent ??
                            const Center(child: Text('此功能將於後續版本提供')),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return _buildTocList(totalCharacterCount);
        },
      ),
    );
  }

  Widget _buildEntryRow(_FlatTocRow row, int? totalCharacterCount) {
    final node = row.entry;
    final isCurrent = identical(node, widget.currentEntry);
    final String pageLabel;
    if (node is TocEntry) {
      // 審查修正：totalCharacterCount 已就緒不代表這個節點本身就有可用的
      // progression——原生端兩層 fallback（locatorFromLink() 自帶的
      // totalProgression、比對 positions() 的近似值）都可能查無資料，此時
      // node.progression 仍是 null。EpubPageEstimator.estimateCurrentPage
      // 對 progression == null 的既有語意是回傳第 1 頁（給「尚未收到任何
      // onLocatorChanged 回報」這個完全不同的情境使用），若不在這裡額外判斷
      // node.progression == null，會讓「查無位置」的章節被誤植成「第 1
      // 頁」，比顯示佔位符更誤導使用者。
      pageLabel = (totalCharacterCount == null || node.progression == null)
          ? '…'
          : EpubPageEstimator.estimateCurrentPage(
              progression: node.progression,
              totalPages: EpubPageEstimator.estimateTotalPages(
                totalCharacterCount: totalCharacterCount,
                charsPerScreen: EpubPageEstimator.estimateCharsPerScreen(
                  fontSize: widget.resolved.fontSize,
                  lineHeight: widget.resolved.lineHeight,
                  paragraphSpacing: widget.resolved.paragraphSpacing,
                  pageMargins: widget.resolved.pageMargins,
                ),
              ),
            ).toString();
    } else if (node is PdfTocItem) {
      // PDF 大綱項目的目標頁碼在解析當下就已知（見
      // PdfReaderView._loadTableOfContents），不像 EPUB 需要背景估算，
      // 不使用 totalCharacterCount／EpubPageEstimator。
      pageLabel = node.pageIndex == null ? '…' : (node.pageIndex! + 1).toString();
    } else {
      pageLabel = '…';
    }

    return Padding(
      padding: EdgeInsets.only(left: row.depth * 16),
      child: ListTile(
        key: Key('toc_entry_${node.stableId}'),
        title: Text(
          node.title,
          style: isCurrent ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
        selected: isCurrent,
        onTap: () => widget.onEntrySelected(node),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
