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

/// 書架分頁狀態的唯一負責者（epic-36 Issue 6，架構回顧衍生）：取代原本
/// 散落在 `LibraryScreen` 的 `build()`／`didChangeMetrics()`／排序/分類
/// 切換/換頁按鈕共 7 處各自寫入的 `_currentPage`／`_lastPageSize` 欄位。
///
/// 純 Dart 類別，不是 `ChangeNotifier`——分頁狀態只有 `_LibraryScreenState`
/// 一個消費者，不需要監聽機制；呼叫端在呼叫任一方法後自行 `setState(() {})`。
class LibraryPagingCursor {
  int _currentPage = 0;
  int? _lastPageSize;

  int get currentPage => _currentPage;

  /// `build()` 每次呼叫一次：依目前 [itemCount]／[orientation] 箝制頁碼到
  /// 合法範圍，回傳目前 `pageCount` 與 `pageSize`。不做旋轉的比例換算
  /// （那是 [applyOrientationChange] 的職責）——單純箝制，用來吸收刪除
  /// 書籍／合併分類等造成 `itemCount` 縮小時的越界殘留（原
  /// `review-plan-issue-3.md` M-2）。回傳值一併帶出 `pageSize`，讓呼叫端
  /// 不需要再另外呼叫一次 `libraryPageSizeForOrientation()`
  /// （`review-plan-issue-6.md` I-2）。
  ({int pageCount, int pageSize}) clamp({
    required int itemCount,
    required Orientation orientation,
  }) {
    final pageSize = libraryPageSizeForOrientation(orientation);
    final pageCount = libraryPageCount(itemCount, pageSize);
    _currentPage = libraryClampPage(_currentPage, pageCount);
    _lastPageSize = pageSize;
    return (pageCount: pageCount, pageSize: pageSize);
  }

  /// `didChangeMetrics()` 呼叫：偵測到真正的方向改變（跟上一次 [clamp]
  /// 或本方法記錄的每頁筆數不同）時，才依「目前頁第一項的全域 index ÷
  /// 新每頁容量」按比例換算頁碼，並回傳 `true`；方向沒變時
  /// （`_lastPageSize` 相同，或尚未有任何記錄）不做任何事、回傳
  /// `false`。**回傳值的用途**：`didChangeMetrics()` 不只在裝置旋轉時
  /// 觸發，軟體鍵盤彈出/收起、分螢調整、系統狀態列顯隱等 metrics 變化
  /// 都會觸發——呼叫端須依回傳值判斷是否真的需要 `setState()`，不能無
  /// 條件重繪，否則會在這些無關情境下也觸發整頁 rebuild，在 E-Ink
  /// 裝置上造成非必要刷新（`review-plan-issue-6.md` I-1）。
  bool applyOrientationChange(Orientation orientation) {
    final newPageSize = libraryPageSizeForOrientation(orientation);
    final oldPageSize = _lastPageSize;
    _lastPageSize = newPageSize;
    if (oldPageSize != null && oldPageSize != newPageSize) {
      _currentPage = libraryRecalculatePage(
        oldPage: _currentPage,
        oldPageSize: oldPageSize,
        newPageSize: newPageSize,
      );
      return true;
    }
    return false;
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
