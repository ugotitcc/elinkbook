import 'dart:ui';

import 'pdf_crop_rect.dart';
import 'pdf_selection_geometry.dart' show cropRelativeToOriginalPercent;
import 'percent_rect.dart';

/// 把「相對畫面」的裁切框換算成「相對頁面」的 [PdfCropRect]（Issue 44）。
///
/// 裁切層（`PdfCropFrameOverlay`）蓋滿整個閱讀區，回報的比例相對整個畫面
/// （含頁面四周的灰邊）；[PdfCropRect] 的語意卻是相對頁面尺寸。頁面沒有
/// 填滿畫面時兩者不同，必須換算，否則套用後會多切（或少切）灰邊那一段。
///
/// - [viewportRect]：框在畫面中的比例（0～1，相對 [viewportSize]）。
/// - [pageRectInViewport]：目前顯示的頁面在畫面中的矩形，可超出畫面（放大時）。
/// - [activeCrop]：目前**生效中**的裁切（模式不是 none 且矩形非 null）。生效時
///   畫面上顯示的是已裁切的頁面，換算結果是「相對已裁切頁面」，須合成回
///   原始整頁座標；null 表示畫面顯示的就是整頁。模式為 none 但殘留舊矩形時，
///   呼叫端必須傳 null，不可合成。
/// - 座標單位一律是邏輯像素。
/// - 框拖進灰邊的部分，夾到頁面邊界。
/// - 與頁面的交集任一邊（以頁面比例計）小於 [minFraction]，或沒有交集，
///   回傳 null，表示這次框選無效。
PdfCropRect? viewportRectToPageCropRect({
  required PdfCropRect viewportRect,
  required Size viewportSize,
  required Rect pageRectInViewport,
  PdfCropRect? activeCrop,
  double minFraction = 0.05,
}) {
  if (pageRectInViewport.width <= 0 || pageRectInViewport.height <= 0) {
    return null;
  }
  final framePx = Rect.fromLTRB(
    viewportRect.left * viewportSize.width,
    viewportRect.top * viewportSize.height,
    viewportRect.right * viewportSize.width,
    viewportRect.bottom * viewportSize.height,
  );
  final inter = framePx.intersect(pageRectInViewport);
  if (inter.width <= 0 || inter.height <= 0) return null;

  final left = (inter.left - pageRectInViewport.left) / pageRectInViewport.width;
  final right =
      (inter.right - pageRectInViewport.left) / pageRectInViewport.width;
  final top = (inter.top - pageRectInViewport.top) / pageRectInViewport.height;
  final bottom =
      (inter.bottom - pageRectInViewport.top) / pageRectInViewport.height;
  if (right - left < minFraction || bottom - top < minFraction) return null;

  if (activeCrop == null) {
    return PdfCropRect(left: left, top: top, right: right, bottom: bottom);
  }
  // 生效中的裁切：合成回相對原始整頁的座標
  final original = cropRelativeToOriginalPercent(
    rect: PercentRect(left: left, top: top, right: right, bottom: bottom),
    cropRect: activeCrop,
  );
  return PdfCropRect(
    left: original.left,
    top: original.top,
    right: original.right,
    bottom: original.bottom,
  );
}
