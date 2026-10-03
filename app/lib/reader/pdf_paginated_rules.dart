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

// ── epic-56 Issue 4：逐頁幾何隔離、單元視窗夾制、相對步進 ──

/// 逐頁單元之間，在「可視矩形縱向超出量」之上額外保留的間距（文件座標，pt）。
/// 見 spec.md「幾何隔離」間距公式（Issue 3 spike 實測決定）。
const double kPaginatedGapPadding = 50.0;

/// 與 pdfrx 預設單頁版面相同的堆疊版面：頁面水平置中，由 [margin] 起依
/// 「頁高 + margin」往下累加；文件寬為最寬頁加兩側 margin。逐頁模式在沒有
/// 雙頁與裁切時以它當作隔離前的基礎版面。
({List<Rect> rects, Size documentSize}) stackPageRects({
  required List<Size> pageSizes,
  required double margin,
}) {
  final width = pageSizes.fold<double>(0.0, (w, s) => math.max(w, s.width)) + margin * 2;
  final rects = <Rect>[];
  var y = margin;
  for (final size in pageSizes) {
    rects.add(Rect.fromLTWH((width - size.width) / 2, y, size.width, size.height));
    y += size.height + margin;
  }
  return (rects: rects, documentSize: Size(width, y));
}

/// 單元在基準縮放下，可視矩形縱向超出單元方框的最大量（文件座標）：
/// `max(0, (視窗高 ÷ 基準縮放 − 單元高) ÷ 2)`。[contentSize] 為單元含頁邊距的
/// 方框尺寸。基準以 [maxZoom] 夾住（與 `fitZoomForUnit` 一致）；算不出有效
/// 基準時回傳 0。
double paginatedUnitOverflow({
  required PdfFitMode mode,
  required Size contentSize,
  required Size viewSize,
  required double maxZoom,
}) {
  final base = fitBaseScale(mode: mode, contentSize: contentSize, viewSize: viewSize);
  if (!base.isFinite || base <= 0) return 0.0;
  final zoom = math.min(base, maxZoom);
  return math.max(0.0, (viewSize.height / zoom - contentSize.height) / 2);
}

/// [isolatePaginatedUnits] 的結果。
class PaginatedLayout {
  const PaginatedLayout({
    required this.pageRects,
    required this.unitRects,
    required this.pageToUnit,
    required this.unitAnchorPages,
    required this.documentSize,
  });

  /// 隔離後各頁矩形（pdfrx 版面座標，index i ＝第 i+1 頁）。
  final List<Rect> pageRects;

  /// 各單元矩形：單元內頁面矩形的聯集，不含頁邊距。
  final List<Rect> unitRects;

  /// 頁索引（0-based）→ 單元索引。
  final List<int> pageToUnit;

  /// 單元索引 → 錨點頁索引（0-based，單元內最小頁索引）。
  final List<int> unitAnchorPages;

  final Size documentSize;

  int get unitCount => unitRects.length;
}

/// 逐頁的幾何隔離（spec.md「幾何隔離」）：把既有版面（單頁堆疊、spread、裁切）
/// 的各單元在縱向拉開，使任何可達的可視矩形只與目前單元相交。
///
/// [pageToUnit] 為各頁所屬單元索引，必須由 0 起單調不減且每個單元至少一頁
/// （spread 版面與單頁版面都滿足）。單元方框＝單元矩形加 [margin]；相鄰方框
/// 間距＝`max(超出量(前), 超出量(後)) + kPaginatedGapPadding`。第一個單元不動，
/// 單元內頁面的相對位置不變，橫向位置不變。[viewSize] 任一邊為 0（尚未量測）
/// 時不移動任何頁面。
PaginatedLayout isolatePaginatedUnits({
  required List<Rect> pageRects,
  required List<int> pageToUnit,
  List<Rect>? baseUnitRects,
  required Size documentSize,
  required double margin,
  required PdfFitMode mode,
  required Size viewSize,
  required double maxZoom,
}) {
  final unitCount = pageToUnit.isEmpty ? 0 : pageToUnit.last + 1;
  final unions = List<Rect?>.filled(unitCount, null);
  final anchors = List<int>.filled(unitCount, 0);
  for (var i = 0; i < pageRects.length; i++) {
    final u = pageToUnit[i];
    final current = unions[u];
    if (current == null) {
      unions[u] = pageRects[i];
      anchors[u] = i;
    } else {
      unions[u] = current.expandToInclude(pageRects[i]);
    }
  }
  // 單元矩形優先取呼叫端傳入的 baseUnitRects（C-1：雙頁的 spreadRects 寬度已正規化為
  // 文件內容寬，單頁封面才不會因為聯集較窄而得到不同的縮放基準）；未傳時才用聯集。
  final units = (baseUnitRects != null && baseUnitRects.length == unitCount)
      ? List<Rect>.of(baseUnitRects)
      : [for (final r in unions) r!];

  if (unitCount == 0 ||
      !viewSize.isFinite ||
      viewSize.width <= 0 ||
      viewSize.height <= 0) {
    return PaginatedLayout(
      pageRects: pageRects,
      unitRects: units,
      pageToUnit: pageToUnit,
      unitAnchorPages: anchors,
      documentSize: documentSize,
    );
  }

  final overflows = [
    for (final u in units)
      paginatedUnitOverflow(
        mode: mode,
        contentSize: u.inflate(margin).size,
        viewSize: viewSize,
        maxZoom: maxZoom,
      ),
  ];
  final shifts = List<double>.filled(unitCount, 0.0);
  var previousBottom = units.first.inflate(margin).bottom;
  for (var u = 1; u < unitCount; u++) {
    final box = units[u].inflate(margin);
    final gap = math.max(overflows[u - 1], overflows[u]) + kPaginatedGapPadding;
    final newTop = previousBottom + gap;
    shifts[u] = newTop - box.top;
    previousBottom = newTop + box.height;
  }

  return PaginatedLayout(
    pageRects: [
      for (var i = 0; i < pageRects.length; i++)
        pageRects[i].shift(Offset(0, shifts[pageToUnit[i]])),
    ],
    unitRects: [
      for (var u = 0; u < unitCount; u++) units[u].shift(Offset(0, shifts[u])),
    ],
    pageToUnit: pageToUnit,
    unitAnchorPages: anchors,
    documentSize: Size(documentSize.width, previousBottom),
  );
}

/// [clampPagedViewport] 的結果。
class PagedViewport {
  const PagedViewport({required this.zoom, required this.topLeft});

  /// 最終縮放（已夾在 [baseZoom, maxZoom]）。
  final double zoom;

  /// 可視矩形左上角（文件座標；pdfrx `goToPosition(documentOffset:)` 的語意）。
  final Offset topLeft;
}

/// 逐頁的視窗夾制（規則 1、2、6）：把縮放夾在 `[baseZoom, maxZoom]`，並把可視
/// 矩形鎖在 [unitContent]（單元含頁邊距的方框，文件座標）內。
///
/// - 某維度的單元方框不比可視範圍大：置中（可視左上角在該軸可為負）。
/// - 某維度溢出：[candidateTopLeft] 夾在「單元起點～單元終點 − 可視長度」；
///   [candidateTopLeft] 為 null（跳轉）時取起點——縱向頂端、橫向依 [direction]
///   的閱讀起始側（左到右靠左、右到左靠右）。
PagedViewport clampPagedViewport({
  required Rect unitContent,
  required Size viewSize,
  required double baseZoom,
  required double maxZoom,
  required double zoom,
  Offset? candidateTopLeft,
  required DualPageDirection direction,
}) {
  final z = math.min(math.max(zoom, baseZoom), maxZoom);
  final x = _pagedAxis(
    start: unitContent.left,
    end: unitContent.right,
    visible: viewSize.width / z,
    candidate: candidateTopLeft?.dx,
    startAtEnd: direction == DualPageDirection.rtl,
  );
  final y = _pagedAxis(
    start: unitContent.top,
    end: unitContent.bottom,
    visible: viewSize.height / z,
    candidate: candidateTopLeft?.dy,
    startAtEnd: false,
  );
  return PagedViewport(zoom: z, topLeft: Offset(x, y));
}

double _pagedAxis({
  required double start,
  required double end,
  required double visible,
  required double? candidate,
  required bool startAtEnd,
}) {
  final extent = end - start;
  // 1e-6 容許浮點誤差：Fit Width 的基準會讓可視寬度恰好等於單元寬度，
  // 不應因為最後一位小數而在「置中」與「溢出」之間來回。
  if (extent <= visible + 1e-6) return start + extent / 2 - visible / 2;
  final min = start;
  final max = end - visible;
  // candidate 非有限（NaN／無限大）時視同沒有候選位置，避免污染矩陣。
  if (candidate == null || !candidate.isFinite) return startAtEnd ? max : min;
  return math.min(math.max(candidate, min), max);
}

/// 規則 3、4 的 Page-fit 子集（Issue 4）：相對步進時的目標單元。第一個單元往前、
/// 最後一個單元往後、或沒有單元時回傳 null（無動作）。Issue 5 會在這之前加入
/// 頁內逐屏步進，再回頭呼叫本函式決定換單元。
int? pagedAdjacentUnit({
  required int currentUnit,
  required int unitCount,
  required bool forward,
}) {
  final target = forward ? currentUnit + 1 : currentUnit - 1;
  if (target < 0 || target >= unitCount) return null;
  return target;
}
