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
/// [startAtBottom] 為 true 且沒有候選位置時，縱向落在單元底端（規則 4：相對步進往回換到上一個單元）；橫向起始側不受影響。
PagedViewport clampPagedViewport({
  required Rect unitContent,
  required Size viewSize,
  required double baseZoom,
  required double maxZoom,
  required double zoom,
  Offset? candidateTopLeft,
  required DualPageDirection direction,
  bool startAtBottom = false,
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
    startAtEnd: startAtBottom,
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

// ── epic-56 Issue 5：長頁步進、帶高亮跳轉、閱讀活動 ──

/// 規則 5：相對步進時與上一個畫面保留的重疊量，佔可視高度的比例。
/// 初始值，待真機校準。
const double kPagedStepOverlapFraction = 0.10;

/// 判定「已到頁底／已在頁頂」的容許誤差（邏輯像素）。spec 明定頁底 1 像素；
/// 頁頂以相同值對稱處理，避免次像素偏移造成多出一次捲不到 1 像素的空按。
const double kPagedEdgeTolerance = 1.0;

/// 規則 9：頁內垂直拖曳每累積這麼多邏輯像素回報一次閱讀活動。初始值，待真機校準。
const double kPagedActivityDragThreshold = 20.0;

enum PagedStepKind { scroll, changeUnit, none }

/// [pagedRelativeStep] 的結果。
class PagedStep {
  /// 頁內捲動，[offset] 為新的頁內偏移（螢幕像素）。
  const PagedStep.scroll(double offset)
      : kind = PagedStepKind.scroll,
        scrollOffset = offset,
        landAtBottom = false;

  /// 換到相鄰單元；[landAtBottom] 為 true 時落在該單元底端，否則落在頂端。
  const PagedStep.changeUnit({required this.landAtBottom})
      : kind = PagedStepKind.changeUnit,
        scrollOffset = 0;

  /// 無動作（第一／最後單元再往外）。
  const PagedStep.none()
      : kind = PagedStepKind.none,
        scrollOffset = 0,
        landAtBottom = false;

  final PagedStepKind kind;

  /// 僅 [PagedStepKind.scroll] 有意義。
  final double scrollOffset;

  /// 僅 [PagedStepKind.changeUnit] 有意義。
  final bool landAtBottom;
}

/// 規則 3、4、5：逐頁下熱區與音量鍵的相對步進。
///
/// [scrollOffset] 與 [maxScroll] 皆為螢幕像素（縮放後）：[scrollOffset] 是目前可視
/// 頂端相對單元頂端的位移（單元置中時可為負），[maxScroll] 是該單元在目前縮放下的
/// 最大縱向捲動量（沒有溢出為 0）。步距＝可視高度減去 [kPagedStepOverlapFraction]
/// 的重疊量。
///
/// - 下一頁：還能往下捲（最大捲動量大於容許誤差，且偏移離頁底超過容許誤差）就頁內
///   捲動，上限為最大捲動量；否則換到下一個單元頂端；沒有下一個單元則無動作。
/// - 上一頁：偏移大於容許誤差就頁內往上捲，下限 0；否則換到上一個單元並落在底端；
///   沒有上一個單元則無動作。
PagedStep pagedRelativeStep({
  required bool forward,
  required double scrollOffset,
  required double maxScroll,
  required double viewHeight,
  required bool hasAdjacentUnit,
}) {
  final distance = viewHeight - viewHeight * kPagedStepOverlapFraction;
  if (forward) {
    if (maxScroll > kPagedEdgeTolerance &&
        scrollOffset < maxScroll - kPagedEdgeTolerance) {
      return PagedStep.scroll(math.min(scrollOffset + distance, maxScroll));
    }
    return hasAdjacentUnit
        ? const PagedStep.changeUnit(landAtBottom: false)
        : const PagedStep.none();
  }
  if (scrollOffset > kPagedEdgeTolerance) {
    return PagedStep.scroll(math.max(scrollOffset - distance, 0.0));
  }
  return hasAdjacentUnit
      ? const PagedStep.changeUnit(landAtBottom: true)
      : const PagedStep.none();
}

/// 規則 7：帶高亮矩形的跳轉。回傳「可視矩形頂端」（文件座標），讓 [highlight]
/// 看得到。呼叫時視窗應已在該單元、縮放為 [zoom]。
///
/// - 單元沒有縱向溢出：置中（與 [clampPagedViewport] 一致）。
/// - 高亮在頂端對齊的視窗內完整可見：維持頂端。
/// - 高亮比可視高度還高：上緣貼齊可視上緣。
/// - 其餘：高亮垂直置中。
/// 結果夾在「單元頂端～單元底端 − 可視高度」之內。
double pagedTopForHighlight({
  required Rect unitContent,
  required Rect highlight,
  required double viewHeight,
  required double zoom,
}) {
  final visibleHeight = viewHeight / zoom;
  final extent = unitContent.height;
  if (extent <= visibleHeight + 1e-6) {
    return unitContent.top + extent / 2 - visibleHeight / 2;
  }
  final minTop = unitContent.top;
  final maxTop = unitContent.bottom - visibleHeight;
  double top;
  // 1e-4 容許浮點誤差：高亮由百分比乘頁面尺寸換算、可視高度由除以縮放換算，貼著視窗
  // 底緣時尾數可能差 1e-12；沒有容許值會把「其實完整可見」的高亮誤判成不可見而置中。
  if (highlight.top >= minTop - 1e-4 &&
      highlight.bottom <= minTop + visibleHeight + 1e-4) {
    top = minTop;
  } else if (highlight.height > visibleHeight) {
    top = highlight.top;
  } else {
    top = highlight.center.dy - visibleHeight / 2;
  }
  return math.min(math.max(top, minTop), maxTop);
}

/// 規則 9：頁內垂直拖曳的閱讀活動累積器。累積絕對位移，每達 [threshold] 回報一次
/// （[add] 回傳 true，餘數保留）；換單元或呼叫 [reset]（換手勢）後歸零。
class PagedDragActivityAccumulator {
  PagedDragActivityAccumulator({this.threshold = kPagedActivityDragThreshold})
      : assert(threshold > 0, 'threshold 必須為正數');

  final double threshold;
  double _accumulated = 0;
  int? _unit;

  bool add(double dy, {required int unit}) {
    if (!dy.isFinite) return false;
    if (_unit != unit) {
      _accumulated = 0;
      _unit = unit;
    }
    _accumulated += dy.abs();
    if (_accumulated < threshold) return false;
    _accumulated = _accumulated % threshold;
    return true;
  }

  void reset() {
    _accumulated = 0;
    _unit = null;
  }
}
