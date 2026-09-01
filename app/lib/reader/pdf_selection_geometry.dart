import 'dart:ui' show Offset, Size;

import 'pdf_crop_rect.dart';
import 'percent_rect.dart';

/// PDF 長按框選座標換算純函式核心（epic-24-pdf-engine-rebuild Issue 4）。
/// 不依賴 pdfrx/Flutter widget（僅用 dart:ui 的 Offset/Size 值型別），
/// 可在純 Dart 環境直接呼叫、單元測試。

/// 把使用者拖曳的起訖座標（[start]／[end]，皆為相對 [areaSize] 這塊區域
/// 左上角的局部座標，單位與 [areaSize] 相同）換算為正規化（left<right、
/// top<bottom）且夾限在 [0,1] 範圍內的 [PercentRect]。
///
/// [minFraction] 為最小有效選取比例（預設 1%）：寬度或高度小於這個比例
/// 時視為使用者長按後幾乎沒有移動（誤觸/退化選取，不是有意義的框選），
/// 回傳 null，呼叫端應視同「取消」處理，不建立劃線/備註。移植自已刪除
/// 原生 `PdfReaderView.kt` 的 `minFraction = 0.01f` 既有防呆常數。
PercentRect? percentRectFromDrag({
  required Offset start,
  required Offset end,
  required Size areaSize,
  double minFraction = 0.01,
}) {
  double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
  final left = clamp01((start.dx < end.dx ? start.dx : end.dx) / areaSize.width);
  final right = clamp01((start.dx > end.dx ? start.dx : end.dx) / areaSize.width);
  final top = clamp01((start.dy < end.dy ? start.dy : end.dy) / areaSize.height);
  final bottom = clamp01((start.dy > end.dy ? start.dy : end.dy) / areaSize.height);
  if ((right - left) < minFraction || (bottom - top) < minFraction) return null;
  return PercentRect(left: left, top: top, right: right, bottom: bottom);
}

/// 把觸控落點 [point]（相對 [areaSize] 這塊區域左上角的局部座標，單位與
/// [areaSize] 相同）換算為零面積（[left]==[right]、[top]==[bottom]）的
/// [PercentRect]，供「長按沒有明顯拖曳位移」（退化選取，見
/// [percentRectFromDrag] 的 [minFraction] 判定）時，仍要送出一個代表
/// 「使用者按在哪裡」的矩形使用（epic-25-annotation-interaction-qa
/// Issue 6）。[left]/[right] 與 [top]/[bottom] 皆指派同一個算好的值，
/// 保證是精確相等（非浮點數運算巧合），呼叫端可用 `rect.left == rect.right`
/// 可靠判斷「這是不是一個退化選取換算出來的點矩形」，不需要額外的旗標欄位。
PercentRect pointPercentRect({
  required Offset point,
  required Size areaSize,
}) {
  double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
  final x = clamp01(point.dx / areaSize.width);
  final y = clamp01(point.dy / areaSize.height);
  return PercentRect(left: x, top: y, right: x, bottom: y);
}

/// 把「相對裁切後可視內容」的百分比矩形 [rect]，換算回「相對原始整頁」
/// 的百分比矩形——持久化選取結果前使用，確保之後裁切矩形變更或關閉時
/// 既有標記位置仍然正確（不會跟著上一次的裁切範圍跑位）。[cropRect] 為
/// null（裁切未啟用）時原樣回傳，等同單位轉換。
PercentRect cropRelativeToOriginalPercent({
  required PercentRect rect,
  required PdfCropRect? cropRect,
}) {
  if (cropRect == null) return rect;
  final w = cropRect.right - cropRect.left;
  final h = cropRect.bottom - cropRect.top;
  return PercentRect(
    left: cropRect.left + rect.left * w,
    top: cropRect.top + rect.top * h,
    right: cropRect.left + rect.right * w,
    bottom: cropRect.top + rect.bottom * h,
  );
}

/// [cropRelativeToOriginalPercent] 的反函式：把「相對原始整頁」的既有
/// 標記矩形 [rect] 換算為「相對裁切後可視內容」的矩形，供裁切啟用時渲染
/// 既有標記使用。完全落在裁切範圍外時回傳 null，呼叫端應跳過渲染這筆
/// 標記；部分重疊時換算結果會被夾限到 [0,1]（只顯示可見的那一部分）。
/// [cropRect] 為 null 時原樣回傳。
PercentRect? originalToCropRelativePercent({
  required PercentRect rect,
  required PdfCropRect? cropRect,
}) {
  if (cropRect == null) return rect;
  if (rect.right <= cropRect.left ||
      rect.left >= cropRect.right ||
      rect.bottom <= cropRect.top ||
      rect.top >= cropRect.bottom) {
    return null; // 完全落在裁切範圍外。
  }
  final w = cropRect.right - cropRect.left;
  final h = cropRect.bottom - cropRect.top;
  double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
  return PercentRect(
    left: clamp01((rect.left - cropRect.left) / w),
    top: clamp01((rect.top - cropRect.top) / h),
    right: clamp01((rect.right - cropRect.left) / w),
    bottom: clamp01((rect.bottom - cropRect.top) / h),
  );
}
