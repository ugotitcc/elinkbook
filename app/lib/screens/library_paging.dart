import 'package:flutter/widgets.dart';

/// 書架分頁的純數學計算（epic-36-adaptive-shelf-navigation Issue 3
/// spec.md §功能③）：不依賴 widget 樹、不依賴 `LibraryScreen` 任何狀態，
/// 獨立可單元測試。

/// 每頁筆數固定依螢幕方向決定（`DESIGN.md#L267`／`#L335`：直排 1 行 3
/// 欄、橫排 1 行 4 欄），格狀／清單兩種檢視一視同仁，不因檢視模式而異
/// （見 plans/plan-issue-3.md「計劃範圍澄清」第 3 點）。
int libraryPageSizeForOrientation(Orientation orientation) =>
    orientation == Orientation.landscape ? 4 : 3;

/// [itemCount] 為 0 時仍回傳 1（避免 0 頁或除以零），呼叫端據此顯示
/// 「1 / 1」而非崩潰或顯示「0 / 0」。
int libraryPageCount(int itemCount, int pageSize) {
  assert(pageSize > 0, 'pageSize 必須為正整數，收到 $pageSize');
  return itemCount == 0 ? 1 : (itemCount / pageSize).ceil();
}

/// 把可能越界的頁碼（例如刪除書籍/合併分類後 itemCount 減少）箝制回
/// `0..pageCount-1` 的有效範圍。`pageCount <= 0` 為異常輸入（正常情況下
/// `libraryPageCount()` 保證 >= 1，這裡仍防禦，因為本函式獨立公開、
/// 呼叫端不保證一定先過 `libraryPageCount()`，見 `review-plan-issue-3.md`
/// M-1）安全回傳 0，不拋 `ArgumentError`。
int libraryClampPage(int page, int pageCount) {
  if (pageCount <= 0) return 0;
  return page.clamp(0, pageCount - 1);
}

/// 旋轉螢幕、每頁筆數改變時，依「目前頁第一項的全域 index ÷ 新每頁
/// 容量」重新換算頁碼，讓使用者瀏覽位置大致不變（不是精確對齊，這是
/// 已知且接受的近似值，見 spec.md §功能③）。三個參數皆非負，用 Dart
/// 原生整數截斷除法 `~/`，不需要 `/`+`.floor()` 的浮點數運算
/// （`review-plan-issue-3.md` M-1）。
int libraryRecalculatePage({
  required int oldPage,
  required int oldPageSize,
  required int newPageSize,
}) {
  assert(newPageSize > 0, 'newPageSize 必須為正整數，收到 $newPageSize');
  return (oldPage * oldPageSize) ~/ newPageSize;
}
