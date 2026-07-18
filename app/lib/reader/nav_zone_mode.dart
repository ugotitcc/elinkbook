import 'zone_action.dart';

/// 熱區映射模式：3 個固定模板（[leftFlip]/[rightFlip]/[oneHand]）與
/// [custom]（完全自由編輯 9 格）四選一互斥，不可個別微調固定模板
/// （design.md 決策 #2、#7）。
enum NavZoneMode { leftFlip, rightFlip, oneHand, custom }

/// `leftFlip`：左欄＝下一頁、中欄＝選單、右欄＝上一頁（design.md 決策 #4）。
const List<ZoneAction> leftFlipZoneTemplate = [
  ZoneAction.nextPage, ZoneAction.menu, ZoneAction.previousPage,
  ZoneAction.nextPage, ZoneAction.menu, ZoneAction.previousPage,
  ZoneAction.nextPage, ZoneAction.menu, ZoneAction.previousPage,
];

/// `rightFlip`：左欄＝上一頁、中欄＝選單、右欄＝下一頁（design.md 決策 #5）。
/// 也是 [NavZoneMode] 與 `GlobalReaderPrefs.navZoneCustomActions` 的預設/
/// 回退值來源（spec.md「資料模型」）。
const List<ZoneAction> rightFlipZoneTemplate = [
  ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
  ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
  ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
];

/// `oneHand`：左右欄對稱，上排＝選單、中排＝上一頁、下排＝下一頁，中間欄
/// 全部無動作（design.md 決策 #6）。
const List<ZoneAction> oneHandZoneTemplate = [
  ZoneAction.menu, ZoneAction.none, ZoneAction.menu,
  ZoneAction.previousPage, ZoneAction.none, ZoneAction.previousPage,
  ZoneAction.nextPage, ZoneAction.none, ZoneAction.nextPage,
];

/// 依 [mode] 查表回傳對應的 9 格熱區動作陣列；[mode] 為
/// [NavZoneMode.custom] 時直接回傳 [customActions] 原樣（不重新排序/
/// 轉換/複製）。
List<ZoneAction> resolveZoneActions(
  NavZoneMode mode,
  List<ZoneAction> customActions,
) {
  switch (mode) {
    case NavZoneMode.leftFlip:
      return leftFlipZoneTemplate;
    case NavZoneMode.rightFlip:
      return rightFlipZoneTemplate;
    case NavZoneMode.oneHand:
      return oneHandZoneTemplate;
    case NavZoneMode.custom:
      return customActions;
  }
}
