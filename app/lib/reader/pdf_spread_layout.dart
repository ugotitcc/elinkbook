import 'dart:ui' show Rect, Size;

import 'dual_page_direction.dart';
import 'dual_page_mode.dart';

/// 三態雙頁模式 × 螢幕方向 → 是否實際啟用雙頁並列
/// （epic-24-pdf-engine-rebuild Issue 2）。比照已刪除的舊 Kotlin
/// `PdfReaderView.isDualPageEnabled()` 純函式設計精神重新實作。
///
/// 注意：裁切編輯模式互斥（舊版有 `cropEditModeActive` 參數）屬 Issue 3
/// 範圍，本函式刻意不含該參數——屆時新增具名參數（預設 false）即可，
/// 不影響本工單既有呼叫點。
bool isDualPageEnabled({required DualPageMode mode, required bool isLandscape}) {
  switch (mode) {
    case DualPageMode.always:
      return true;
    case DualPageMode.never:
      return false;
    case DualPageMode.auto:
      return isLandscape;
  }
}

/// 依「封面獨立顯示」規則，把 [totalPages] 頁切成一組組 spread。
///
/// 每個元素是該 spread 含的 0-indexed pageIndex，依文件順序排列（非顯示
/// 順序——RTL 的左右鏡像只發生在幾何排版階段，見 [computeSpreadLayout]）。
///
/// `coverAlone == true` ： `[[0], [1,2], [3,4], ...]`
/// `coverAlone == false`： `[[0,1], [2,3], [4,5], ...]`
/// 末尾未滿一組時該 spread 只含 1 頁（依總頁數奇偶性而定）。
List<List<int>> buildSpreads({required int totalPages, required bool coverAlone}) {
  final spreads = <List<int>>[];
  var i = 0;
  if (coverAlone && totalPages > 0) {
    spreads.add([0]);
    i = 1;
  }
  while (i < totalPages) {
    if (i + 1 < totalPages) {
      spreads.add([i, i + 1]);
      i += 2;
    } else {
      spreads.add([i]);
      i += 1;
    }
  }
  return spreads;
}

/// 雙頁版面的完整計算結果。純函式輸出，不持有任何 pdfrx/Flutter widget
/// 狀態。
class PdfSpreadLayout {
  const PdfSpreadLayout({
    required this.pageRects,
    required this.spreadRects,
    required this.spreads,
    required this.pageToSpread,
    required this.documentSize,
  });

  /// 逐「單一頁面」的文件座標矩形，index == 0-indexed pageIndex，長度
  /// == totalPages。矩形大小即該頁原始尺寸（不含 margin）。
  ///
  /// 【Issue 4 相容性契約】劃線/選取要換算「相對單一頁面本身邊界」的
  /// 百分比矩形時，一律查這裡，不要用 [spreadRects]（那是合併後的跨頁
  /// 矩形）。見 spec.md「劃線/備註/選取機制」。
  final List<Rect> pageRects;

  /// 逐 spread 的「導航目標矩形」，index == spreadIndex。寬度一律等於
  /// 文件內容寬度（`documentSize.width - margin * 2`），讓單頁 spread
  /// （封面、收尾單頁）與雙頁 spread 的 fit 縮放比例一致，翻頁時頁面
  /// 視覺大小不跳動。
  final List<Rect> spreadRects;

  /// [buildSpreads] 的結果，供測試與除錯直接斷言配對。
  final List<List<int>> spreads;

  /// pageIndex → spreadIndex 的 O(1) 反查表，長度 == totalPages。
  final List<int> pageToSpread;

  final Size documentSize;

  int get spreadCount => spreads.length;

  /// 0-indexed pageIndex → 所屬 spreadIndex。超界時 clamp 到合法範圍
  /// （呼叫端不需要自行防呆）。
  int spreadIndexOf(int pageIndex) {
    if (pageToSpread.isEmpty) return 0;
    final clamped = pageIndex.clamp(0, pageToSpread.length - 1);
    return pageToSpread[clamped];
  }

  /// spreadIndex → 該 spread 的「錨點頁」= 組內最小的 pageIndex。對外
  /// 回報的目前頁碼、翻頁步進基準皆用錨點頁（沿用已刪除的舊 Kotlin
  /// currentPageIndex 語意）。
  int anchorPageOf(int spreadIndex) {
    final clamped = spreadIndex.clamp(0, spreads.length - 1);
    return spreads[clamped].first;
  }

  /// 下一個 spread 的錨點頁 index；已在最後一個 spread 時回傳 null。
  int? nextSpreadAnchor(int fromPageIndex) {
    final current = spreadIndexOf(fromPageIndex);
    if (current >= spreads.length - 1) return null;
    return anchorPageOf(current + 1);
  }

  /// 上一個 spread 的錨點頁 index；已在第一個 spread 時回傳 null。
  int? previousSpreadAnchor(int fromPageIndex) {
    final current = spreadIndexOf(fromPageIndex);
    if (current <= 0) return null;
    return anchorPageOf(current - 1);
  }
}

/// 計算雙頁並列版面。純函式：輸入只有頁面尺寸與設定，無 pdfrx 相依。
///
/// [pageSizes] 各頁原始尺寸（依文件順序）。[margin] 取自
/// `PdfViewerParams.margin`（pdfrx 預設 8.0）。
PdfSpreadLayout computeSpreadLayout({
  required List<Size> pageSizes,
  required double margin,
  required bool coverAlone,
  required DualPageDirection direction,
}) {
  final totalPages = pageSizes.length;
  final spreads = buildSpreads(totalPages: totalPages, coverAlone: coverAlone);

  if (totalPages == 0) {
    return PdfSpreadLayout(
      pageRects: const [],
      spreadRects: const [],
      spreads: const [],
      pageToSpread: const [],
      documentSize: Size(margin * 2, margin),
    );
  }

  // 每個 spread 的內容寬度（該 spread 內各頁寬度總和）與內容高度（該
  // spread 內最高頁面的高度）。
  final rowWidths = <double>[];
  final rowHeights = <double>[];
  for (final spread in spreads) {
    var w = 0.0;
    var h = 0.0;
    for (final p in spread) {
      w += pageSizes[p].width;
      if (pageSizes[p].height > h) h = pageSizes[p].height;
    }
    rowWidths.add(w);
    rowHeights.add(h);
  }
  final contentWidth = rowWidths.fold<double>(0, (a, b) => a > b ? a : b);
  final docWidth = contentWidth + margin * 2;

  final pageRects = List<Rect?>.filled(totalPages, null);
  final spreadRects = <Rect>[];
  final pageToSpread = List<int>.filled(totalPages, 0);

  var y = margin;
  for (var s = 0; s < spreads.length; s++) {
    final spread = spreads[s];
    // RTL：文件順序在後者的頁面顯示在左側，鏡像已刪除的舊 Kotlin
    // pairIndices(anchor, RTL) == (anchor+1, anchor) 定義。
    final Iterable<int> order =
        direction == DualPageDirection.rtl ? spread.reversed : spread;
    var x = margin + (contentWidth - rowWidths[s]) / 2;
    for (final p in order) {
      final size = pageSizes[p];
      final rect = Rect.fromLTWH(
        x,
        y + (rowHeights[s] - size.height) / 2,
        size.width,
        size.height,
      );
      pageRects[p] = rect;
      pageToSpread[p] = s;
      x += size.width; // spread 內兩頁緊貼，無 gutter。
    }
    spreadRects.add(Rect.fromLTWH(margin, y, contentWidth, rowHeights[s]));
    y += rowHeights[s] + margin;
  }

  return PdfSpreadLayout(
    pageRects: pageRects.cast<Rect>(),
    spreadRects: spreadRects,
    spreads: spreads,
    pageToSpread: pageToSpread,
    documentSize: Size(docWidth, y),
  );
}
