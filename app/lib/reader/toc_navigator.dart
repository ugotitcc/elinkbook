import 'toc_entry.dart';

/// EPUB 目錄樹狀清單的目前章節判定邏輯（epic-5-toc-pagination Issue 4，
/// spec.md「目錄模組」：「當前章節所屬層級預設展開，其餘收起；當前章節
/// 項目需視覺高亮」）。純函式、無 I/O，供 `ReaderScreen` 開啟目錄前計算。
class TocNavigator {
  const TocNavigator._();

  /// 找出讀者目前所在（或剛通過）的章節，回傳從樹根到該章節的完整祖先
  /// 路徑（含自身）。演算法：對整棵樹做深度優先前序走訪（此順序即為書本
  /// 閱讀順序——子章節緊接在父章節標題之後，早於下一個同層級兄弟節點），
  /// 逐一檢查每個節點的 [TocEntry.progression]，只要 `<= currentProgression`
  /// 就把「目前累積路徑」更新為目前為止最新符合的一筆；走訪結束時保留的
  /// 即為讀者目前最深、最新通過的章節。
  ///
  /// [currentProgression] 為 `null`（例如尚未收到任何 `onLocatorChanged`
  /// 回報）或沒有任何節點的 progression `<= currentProgression` 時，回傳
  /// 空清單——呼叫端據此不預設展開任何層級、不高亮任何項目。
  static List<TocEntry> findCurrentPath(
    List<TocEntry> entries,
    double? currentProgression,
  ) {
    if (currentProgression == null) return const [];
    List<TocEntry>? bestPath;
    void walk(List<TocEntry> nodes, List<TocEntry> path) {
      for (final node in nodes) {
        final newPath = [...path, node];
        final progression = node.progression;
        if (progression != null && progression <= currentProgression) {
          bestPath = newPath;
        }
        walk(node.children, newPath);
      }
    }

    walk(entries, const []);
    return bestPath ?? const [];
  }
}