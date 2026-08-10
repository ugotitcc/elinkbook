import 'book_toc_item.dart';

/// PDF 目錄樹狀清單的單一節點（epic-24-pdf-engine-rebuild Issue 5，
/// spec.md「目錄（TOC）」）：由 `PdfReaderView._loadTableOfContents()`
/// 一次性把 `pdfrx` 的 `PdfOutlineNode` 樹轉換而來，保留完整巢狀階層。
///
/// 刻意不覆寫 `==`/`hashCode`（比照 `TocEntry` 既有慣例，維持預設的物件
/// 識別語意）——`PdfTocNavigator` 回傳的「目前章節路徑」與 UI 的展開狀態
/// 集合，判斷依據都是「是否為同一個節點物件參照」。
class PdfTocItem implements BookTocItem {
  @override
  final String title;

  /// 大綱項目的目標頁碼（0-indexed，比照專案既有慣例），`null` 代表該
  /// 大綱節點在原始 PDF 中沒有有效的目的地（`PdfOutlineNode.dest ==
  /// null`）——這是合法但少見的 PDF 寫法（例如純粹用來分組子項的標題列，
  /// 自身不指向任何頁面）。點擊 `pageIndex == null` 的節點時，呼叫端
  /// （`reader_screen.dart`）不執行跳轉，但節點仍正常顯示於目錄樹中。
  final int? pageIndex;

  @override
  final String stableId;

  @override
  final List<PdfTocItem> children;

  const PdfTocItem({
    required this.title,
    required this.pageIndex,
    required this.stableId,
    this.children = const [],
  });
}
