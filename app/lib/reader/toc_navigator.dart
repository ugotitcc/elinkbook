import 'foliate_bridge_codec.dart';
import 'toc_entry.dart';

/// EPUB 目錄樹狀清單的目前章節判定邏輯（epic-5-toc-pagination Issue 4，
/// spec.md「目錄模組」：「當前章節所屬層級預設展開，其餘收起；當前章節
/// 項目需視覺高亮」）。純函式、無 I/O，供 `ReaderScreen` 開啟目錄前計算。
class TocNavigator {
  const TocNavigator._();

  /// 找出讀者目前所在（或剛通過）的章節，回傳從樹根到該章節的完整祖先
  /// 路徑（含自身）。演算法：對整棵樹做深度優先前序走訪（此順序即為書本
  /// 閱讀順序——子章節緊接在父章節標題之後，早於下一個同層級兄弟節點），
  /// 逐一判斷每個節點「是否已被讀者通過」，只要通過就把「目前累積路徑」
  /// 更新為目前為止最新符合的一筆；走訪結束時保留的即為讀者目前最深、最新
  /// 通過的章節。
  ///
  /// 「已通過」的判定（epic-54 Issue 19）：
  /// - 節點與目前位置都有 spine index（[extractChapterIndex]）時，**先比
  ///   spine index**：節點在目前 spine 之前＝已通過、之後＝未通過；同一個
  ///   spine 內，節點沒有 progression（章節起點、無頁內錨點）視為已通過，
  ///   有 progression 才與 [currentProgression] 比大小。
  /// - 任一方缺 index（例如目錄節點 href 無法解析、locatorJson 為空字串，
  ///   或 [currentSpineIndex] 為 `null`）則退回舊規則：節點 progression
  ///   與 [currentProgression] 皆非 null 且 `<=` 才算通過。
  ///
  /// 為什麼不能只靠全書 progression：頂層章節沒有頁內錨點，`TocEntry
  /// .progression` 結構性為 `null`；而開書當下 foliate 的全書 fraction 估計
  /// 偏高（小章節單頁時位元組估計 double-count），兩者疊加會讓開書當下命中
  /// 後面章節的子節。spine index 是章節層級的精確資訊，不受此影響。
  ///
  /// epic-54 Issue 20：[currentTocItemId]（`EpubPositionInfo.tocItemId`，
  /// foliate 以 live DOM `Range.comparePoint` 判定的目前目錄項 id）優先於上述
  /// 兩種規則，解決同一 spine 內多個錨點時依 progression 猜測的不精確。
  ///
  /// [currentProgression]、[currentSpineIndex]、[currentTocItemId] 皆為 `null`（例如尚未收到
  /// 任何 `onLocatorChanged` 回報）或沒有任何節點通過時，回傳空清單——
  /// 呼叫端據此不預設展開任何層級、不高亮任何項目。
  static List<TocEntry> findCurrentPath(
    List<TocEntry> entries,
    double? currentProgression, {
    int? currentSpineIndex,
    int? currentTocItemId,
  }) {
    if (currentProgression == null &&
        currentSpineIndex == null &&
        currentTocItemId == null) {
      return const [];
    }
    // epic-54 Issue 20：foliate 以 live DOM 判定的目前目錄項，精確度最高，
    // 有命中就直接採用；查無（id 缺席、目錄尚未載入、節點缺 tocId）則
    // 往下退回 spine index／progression 規則。注意 id 0 是合法值，
    // 一律以 `!= null` 判斷，不可用 truthy。
    if (currentTocItemId != null) {
      final byId = _pathToTocId(entries, currentTocItemId, const []);
      if (byId != null) return byId;
    }
    List<TocEntry>? bestPath;
    void walk(List<TocEntry> nodes, List<TocEntry> path) {
      for (final node in nodes) {
        final newPath = [...path, node];
        if (_hasPassed(node, currentProgression, currentSpineIndex)) {
          bestPath = newPath;
        }
        walk(node.children, newPath);
      }
    }

    walk(entries, const []);
    return bestPath ?? const [];
  }

  /// DFS 找出 [TocEntry.tocId] 等於 [tocId] 的節點，回傳根到該節點的路徑；
  /// 查無回傳 `null`。
  static List<TocEntry>? _pathToTocId(
    List<TocEntry> nodes,
    int tocId,
    List<TocEntry> path,
  ) {
    for (final node in nodes) {
      if (node.tocId == tocId) return [...path, node];
      final found = _pathToTocId(node.children, tocId, [...path, node]);
      if (found != null) return found;
    }
    return null;
  }

  /// 單一節點是否已被讀者通過，規則見 [findCurrentPath] 的文件註解。
  ///
  /// 每個節點都會重新解析一次 locatorJson（[extractChapterIndex] 內含
  /// `jsonDecode`）：EPUB 目錄規模小（數十至數百節點）、解析為微秒級，刻意
  /// 維持純函式、不加快取，避免引入物件狀態。
  static bool _hasPassed(
    TocEntry node,
    double? currentProgression,
    int? currentSpineIndex,
  ) {
    final nodeIndex = extractChapterIndex(node.locatorJson);
    if (currentSpineIndex != null && nodeIndex != null) {
      if (nodeIndex < currentSpineIndex) return true;
      if (nodeIndex > currentSpineIndex) return false;
      // 同一個 spine 內：無錨點的章節起點視為已通過。
      final progression = node.progression;
      if (progression == null || currentProgression == null) return true;
      return progression <= currentProgression;
    }
    final progression = node.progression;
    return progression != null &&
        currentProgression != null &&
        progression <= currentProgression;
  }
}