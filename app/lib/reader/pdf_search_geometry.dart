import 'package:pdfrx/pdfrx.dart';

import 'percent_rect.dart';

/// 把 `pdfrx` 原生的 [PdfRect]（PDF points 座標，左下角原點、Y 軸向上，
/// `top >= bottom`）換算為本專案既有的 [PercentRect]（0-1 相對頁面尺寸，
/// 左上角原點、Y 軸向下，`top <= bottom`，比照 `Rect.fromLTRB` 語意與
/// `PdfAnnotationDecoration.rect` 既有慣例）。
///
/// epic-24-pdf-engine-rebuild Issue 6：[PdfPageTextRange.bounds]
/// （`pdfrx_engine` 套件）回傳的搜尋符合位置矩形即為 [PdfRect]，需要這個
/// 轉換才能套用既有的 `PdfReaderView` 疊加渲染管線
/// （`_buildProcessedOverlay`／`originalToCropRelativePercent`）。
///
/// 換算結果一律夾在 0.0-1.0 範圍內（審查修正，review-plan-issue-6.md
/// Minor #2）：少數 PDF 字型解析出的字元 bounding box 可能微幅超出頁面
/// 邊界（例如 `top` 略大於 `pageHeight`、`left` 略小於 0），不夾範圍會讓
/// 換算結果變成負值或大於 1，下游疊加渲染（`_buildSearchHighlightWidget`）
/// 直接把 percent 乘上像素尺寸，會在頁面邊緣產生輕微視覺溢出。
PercentRect pdfRectToPercentRect({
  required PdfRect rect,
  required double pageWidth,
  required double pageHeight,
}) {
  return PercentRect(
    left: (rect.left / pageWidth).clamp(0.0, 1.0),
    right: (rect.right / pageWidth).clamp(0.0, 1.0),
    top: (1.0 - (rect.top / pageHeight)).clamp(0.0, 1.0),
    bottom: (1.0 - (rect.bottom / pageHeight)).clamp(0.0, 1.0),
  );
}
