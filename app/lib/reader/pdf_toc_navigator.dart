import 'pdf_toc_item.dart';

/// PDF 目錄樹狀清單的目前章節判定邏輯（epic-24-pdf-engine-rebuild Issue 5，
/// spec.md「PDF 目錄項目點擊後的行為...與 EPUB 既有目錄 Bottom Sheet 行為
/// 一致」）。演算法與 `TocNavigator.findCurrentPath`（`toc_navigator.dart`）
/// 完全對稱，差別只在比較鍵是頁碼（int，0-indexed）而非 EPUB 的
/// progression（double，0.0-1.0）——刻意不寫成共用泛型函式，兩邊呼叫端
/// 使用的型別（`PdfTocItem` vs `TocEntry`）與比較鍵型別（int vs double）
/// 都不同，泛型化不會減少程式碼量，只會增加閱讀成本。
class PdfTocNavigator {
  const PdfTocNavigator._();

  /// 找出讀者目前所在（或剛通過）的章節，回傳從樹根到該章節的完整祖先
  /// 路徑（含自身）。[currentPageIndex] 為 `null`（尚未收到任何
  /// `onPageChanged` 回報）或沒有任何節點的 `pageIndex <= currentPageIndex`
  /// 時，回傳空清單。`pageIndex == null` 的節點（大綱項目無有效目的地）
  /// 永遠不參與比較，比照 EPUB 版本對 `progression == null` 的既有語意。
  static List<PdfTocItem> findCurrentPath(
    List<PdfTocItem> entries,
    int? currentPageIndex,
  ) {
    if (currentPageIndex == null) return const [];
    List<PdfTocItem>? bestPath;
    void walk(List<PdfTocItem> nodes, List<PdfTocItem> path) {
      for (final node in nodes) {
        final newPath = [...path, node];
        final pageIndex = node.pageIndex;
        if (pageIndex != null && pageIndex <= currentPageIndex) {
          bestPath = newPath;
        }
        walk(node.children, newPath);
      }
    }

    walk(entries, const []);
    return bestPath ?? const [];
  }
}
