import 'dart:math' as math;
import 'dart:ui';

import 'dual_page_direction.dart';
import 'pdf_fit_mode.dart';

// PDF 逐頁導覽規則（純 Dart，不依賴 Widget；見
// docs/epics/epic-56-pdf-paginated-reading/spec.md「逐頁導覽規則模組」）。
// 本檔目前只有規則 1（縮放基準與對齊）、規則 2（頁內捲動範圍）；後續 Issue
// 會在此擴充步進、跳轉、滑動判定等規則。

/// 規則 1：某個「單元」（一頁或一個 spread）在 [viewSize] 下的縮放基準。
/// [contentSize] 是單元尺寸，呼叫端須先加上 pdfrx 頁邊距。
///
/// - Page-fit：寬高各自的比例取較小者，整個單元完整放進可視範圍。
/// - Fit Width：可視寬度除以內容寬度。
/// - 真實比例：固定 1.0（1 PDF point ＝ 1 邏輯像素）。
double fitBaseScale({
  required PdfFitMode mode,
  required Size contentSize,
  required Size viewSize,
}) {
  switch (mode) {
    case PdfFitMode.pageFit:
      return math.min(
        viewSize.width / contentSize.width,
        viewSize.height / contentSize.height,
      );
    case PdfFitMode.fitWidth:
      return viewSize.width / contentSize.width;
    case PdfFitMode.actualSize:
      return 1.0;
  }
}

/// 規則 2：縮放後內容的縱向最大捲動量；內容不比可視高度高時為 0。
double maxVerticalScroll({
  required Size contentSize,
  required double scale,
  required Size viewSize,
}) {
  return math.max(0.0, contentSize.height * scale - viewSize.height);
}

/// 規則 1（對齊）：縮放後內容左上角在可視區域座標系中的位置。
///
/// 比可視範圍小的維度置中；縱向溢出時從頁頂開始；橫向溢出時從閱讀起始側
/// 開始（左到右靠左、右到左靠右）。
Offset fitOrigin({
  required Size contentSize,
  required double scale,
  required Size viewSize,
  required DualPageDirection direction,
}) {
  final width = contentSize.width * scale;
  final height = contentSize.height * scale;
  final double x;
  if (width <= viewSize.width) {
    x = (viewSize.width - width) / 2;
  } else {
    x = direction == DualPageDirection.rtl ? viewSize.width - width : 0.0;
  }
  final y = height <= viewSize.height ? (viewSize.height - height) / 2 : 0.0;
  return Offset(x, y);
}

/// 單元矩形 [unitRect]（pdfrx 版面座標，不含頁邊距）在 [viewSize] 下要套用的
/// 縮放值：內容尺寸為單元各邊加 [pageMargin]（與 pdfrx 計算「整頁放進螢幕」
/// 的方式一致），並夾在 [maxZoom] 以內。可視尺寸或內容尺寸為 0（版面尚未
/// 量測）、算出非有限或非正值時回傳 null，呼叫端應沿用 pdfrx 原本的縮放。
double? fitZoomForUnit({
  required PdfFitMode mode,
  required Rect unitRect,
  required double pageMargin,
  required Size viewSize,
  required double maxZoom,
}) {
  final base = fitBaseScale(
    mode: mode,
    contentSize: unitRect.inflate(pageMargin).size,
    viewSize: viewSize,
  );
  if (!base.isFinite || base <= 0) return null;
  return math.min(base, maxZoom);
}
