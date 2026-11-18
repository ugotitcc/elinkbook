import 'dart:ui';

import 'pdf_crop_rect.dart';

/// 把「相對畫面」的裁切框換算成「相對頁面」的 [PdfCropRect]（Issue 44／Issue 45）。
///
/// 裁切層（`PdfCropFrameOverlay`）蓋滿整個閱讀區，回報的比例相對整個畫面
/// （含頁面四周的灰邊）；[PdfCropRect] 的語意卻是相對頁面尺寸。頁面沒有
/// 填滿畫面時兩者不同，必須換算，否則套用後會多切（或少切）灰邊那一段。
/// 裁切編輯期間畫面一律顯示未裁切的完整頁面，因此換算結果恆相對完整頁面。
///
/// - [viewportRect]：框在畫面中的比例（0～1，相對 [viewportSize]）。
/// - [pageRectInViewport]：目前顯示的頁面在畫面中的矩形，可超出畫面（放大時）。
/// - 座標單位一律是邏輯像素。
/// - 框拖進灰邊的部分，夾到頁面邊界。
/// - 與頁面的交集任一邊（以頁面比例計）小於 [minFraction]，或沒有交集，
///   回傳 null，表示這次框選無效。
PdfCropRect? viewportRectToPageCropRect({
  required PdfCropRect viewportRect,
  required Size viewportSize,
  required Rect pageRectInViewport,
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

  return PdfCropRect(left: left, top: top, right: right, bottom: bottom);
}
