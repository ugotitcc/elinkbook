import 'package:flutter/widgets.dart';

/// 書架分頁的純數學計算（epic-36-adaptive-shelf-navigation Issue 3
/// spec.md §功能③）：不依賴 widget 樹、不依賴 `LibraryScreen` 任何狀態，
/// 獨立可單元測試。

/// 取得特定方向下的預設欄數（crossAxisCount：直排 3、橫排 4）。**Issue 7
/// 起不再等於每頁筆數（pageSize）**——Issue 3／6 時每頁只有 1 行，欄數剛好
/// 等於 pageSize；Issue 7 起 `pageSize = crossAxisCount * rows`，rows 依可
/// 用高度動態計算（見 `libraryRowsForHeight()`），函式名稱沿用舊名只是為
/// 了不做無謂的改名（呼叫端／測試都已改用新語意呼叫），語意以本段
/// doc comment 為準（`review-plan-issue-7.md` I-3）。格狀／清單兩種檢視
/// 一視同仁，不因檢視模式而異（見 plans/plan-issue-3.md「計劃範圍澄清」
/// 第 3 點）。
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

/// 依可用高度計算書架每頁可完整顯示的列數（epic-36 Issue 7，取代 Issue 3
/// 寫死「1 行」的舊假設）。[availableHeight] 為扣除 AppBar／搜尋列／繼續
/// 閱讀列／`PagingBar`／Grid 自身 padding 等 chrome 後的實際可用高度
/// （呼叫端透過 `LayoutBuilder` 量測取得，見 `library_screen.dart`
/// `_buildBookList()`；`review-plan-issue-7.md` C-1：呼叫端務必記得扣除
/// `GridView` 自身上下 padding，不只是 `PagingBar` 高度）；[rowContentHeight]
/// 為單列高度（含封面與文字說明區的整個 cell 高度）；[rowSpacing] 為列間
/// 距。無條件捨去，且保底至少 1 行（即便完全放不下也顯示 1 行，不出現 0
/// 行空白頁）。
int libraryRowsForHeight({
  required double availableHeight,
  required double rowContentHeight,
  required double rowSpacing,
}) {
  if (rowContentHeight <= 0) return 1;
  // n 列總高度 = n*rowContentHeight + (n-1)*rowSpacing <= availableHeight。
  // 除法前加極小容差 1e-5，避免理論上剛好整除的邊界值因浮點誤差算成
  // 「N - 極小值」而被 floor() 多捨去 1 列（review-plan-issue-7.md M-2）。
  final rows =
      ((availableHeight + rowSpacing + 1e-5) / (rowContentHeight + rowSpacing))
          .floor();
  return rows < 1 ? 1 : rows;
}

/// List View 模式下單一 `ListTile` 書籍列在系統字級 1.0 倍時的估計高度
/// （epic-36 Issue 7 追加修正——I-1：`_buildBookList()` 原本讓 Grid／List
/// 兩種檢視共用同一組依 Grid cell 幾何算出的 `pageSize`，但 `ListTile`
/// 實際高度遠小於 Grid cell，窄高裝置下 List 這一頁可能因
/// `NeverScrollableScrollPhysics` 而裁切掉部分項目，看得到頁碼但看不到/
/// 點不到書籍）。72.0 對應 Material 兩行式 `ListTile`（書名＋作者）在標準
/// 密度下的自然高度基準（`_BookListTile`／`_GroupListTile` 的 leading 高度
/// 64、搭配上下 padding）。
const kListRowHeightAtScale1 = 72.0;

/// 依 [textScaler] 換算 List 列高（呼叫端傳入 `MediaQuery.textScalerOf(context)`）。
/// 刻意呼叫 `scale()` 而非直接乘上 `textScaleFactor`——`book_grid_tile_
/// metrics.dart` 已有真機回報記錄同一類陷阱（Android 系統字級縮放曲線
/// 非線性）。刻意用 `ceilToDouble()` 往上估：List 列高被低估才會讓算出的
/// 列數偏多、實際裁切書籍；被高估只會讓列數偏保守、多留一點空白，兩者
/// 風險不對稱，因此設計上刻意選擇偏安全的方向（呼應 `libraryRowsForHeight()`
/// 保底至少 1 行、允許剩餘空白的既有原則）。**目前 72.0 這個基準值未經真
/// 機校準**（不像 `kGridTileFooterHeightAtScale1` 已有多輪真機回報反覆調
/// 校），若日後真機回報估計仍偏低導致裁切，比照 `book_grid_tile_metrics.dart`
/// 的校準模式另外調整，不可逕自視為精確值。
double libraryListRowHeight(TextScaler textScaler) {
  return (kListRowHeightAtScale1 * textScaler.scale(16.0) / 16.0)
      .ceilToDouble();
}

/// 書架分頁狀態的唯一負責者（epic-36 Issue 6，架構回顧衍生；Issue 7 進一
/// 步簡化）：取代原本散落在 `LibraryScreen` 的 `build()`／
/// `didChangeMetrics()`／排序/分類切換/換頁按鈕共 7 處各自寫入的
/// `_currentPage`／`_lastPageSize` 欄位。
///
/// 純 Dart 類別，不是 `ChangeNotifier`——分頁狀態只有 `_LibraryScreenState`
/// 一個消費者，不需要監聽機制；呼叫端在呼叫任一方法後自行 `setState(() {})`。
class LibraryPagingCursor {
  int _currentPage = 0;
  int? _lastPageSize;

  int get currentPage => _currentPage;

  /// `build()` 每次呼叫一次：以本次量測到的 [pageSize] 箝制頁碼。若
  /// [pageSize] 相較上次記錄的值改變（旋轉、視窗高度變化導致列數重
  /// 算），先依「目前頁第一項全域 index ÷ 新 pageSize」做比例換算，才
  /// 箝制到合法範圍（吸收 itemCount 縮小造成的越界殘留，原
  /// `review-plan-issue-3.md` M-2）。
  ///
  /// 取代 Issue 6 的 `clamp()`／`applyOrientationChange()` 兩個方法——
  /// pageSize 現在只有 `build()` 執行當下（`LayoutBuilder` 量測完成後）
  /// 才知道正確值，`didChangeMetrics()` 無法再提前算好，兩個關注點收斂
  /// 回同一次呼叫（見 `issues.md` Issue 7）。
  int clamp({required int itemCount, required int pageSize}) {
    final pageCount = libraryPageCount(itemCount, pageSize);
    final oldPageSize = _lastPageSize;
    if (oldPageSize != null && oldPageSize != pageSize) {
      _currentPage = libraryRecalculatePage(
        oldPage: _currentPage,
        oldPageSize: oldPageSize,
        newPageSize: pageSize,
      );
    }
    _currentPage = libraryClampPage(_currentPage, pageCount);
    _lastPageSize = pageSize;
    return pageCount;
  }

  /// 呼叫端（`PagingBar.onNext`）保證只在合法範圍內才會觸發，故不做內部
  /// 邊界防呆（`CLAUDE.md`「不要為不可能發生的情境寫防禦」）。
  void goToNextPage() => _currentPage++;

  /// 同 [goToNextPage]，呼叫端（`PagingBar.onPrevious`）保證只在合法範圍
  /// 內才會觸發。
  void goToPreviousPage() => _currentPage--;

  /// 排序條件／搜尋關鍵字／分類下鑽切換時呼叫，重置為第一頁。
  void resetToFirstPage() => _currentPage = 0;
}
