import 'dual_page_mode.dart';

/// 三態雙頁模式 × 螢幕方向 → 是否實際啟用雙頁並列
/// （epic-24-pdf-engine-rebuild Issue 2）。比照已刪除的舊 Kotlin
/// `PdfReaderView.isDualPageEnabled()` 純函式設計精神重新實作。
///
/// 注意：裁切編輯模式互斥（舊版有 `cropEditModeActive` 參數）屬 Issue 3
/// 範圍，本函式刻意不含該參數——屆時新增具名參數（預設 false）即可，
/// 不影響本工單既有呼叫點。
bool isDualPageEnabled({required DualPageMode mode, required bool isLandscape}) {
  switch (mode) {
    case DualPageMode.always:
      return true;
    case DualPageMode.never:
      return false;
    case DualPageMode.auto:
      return isLandscape;
  }
}

/// 依「封面獨立顯示」規則，把 [totalPages] 頁切成一組組 spread。
///
/// 每個元素是該 spread 含的 0-indexed pageIndex，依文件順序排列（非顯示
/// 順序——RTL 的左右鏡像只發生在幾何排版階段，見 [computeSpreadLayout]）。
///
/// `coverAlone == true` ： `[[0], [1,2], [3,4], ...]`
/// `coverAlone == false`： `[[0,1], [2,3], [4,5], ...]`
/// 末尾未滿一組時該 spread 只含 1 頁（依總頁數奇偶性而定）。
List<List<int>> buildSpreads({required int totalPages, required bool coverAlone}) {
  final spreads = <List<int>>[];
  var i = 0;
  if (coverAlone && totalPages > 0) {
    spreads.add([0]);
    i = 1;
  }
  while (i < totalPages) {
    if (i + 1 < totalPages) {
      spreads.add([i, i + 1]);
      i += 2;
    } else {
      spreads.add([i]);
      i += 1;
    }
  }
  return spreads;
}
