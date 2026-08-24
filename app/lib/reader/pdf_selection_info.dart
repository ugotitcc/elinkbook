import 'percent_rect.dart';

/// [PdfReaderView] 使用者長按拖曳框選劃線範圍完成時回報的資訊
/// （epic-6-annotations Issue 3）。[rect] 為框選矩形相對「目前顯示中
/// bitmap 內容範圍」的百分比值（見 plan-issue-3.md Global Constraints
/// 「PDF 座標協定」），供持久化（[Highlight]/[Note]）與 Bitmap 重繪使用，
/// 內容範圍不含 letterbox 留白。[widgetRect] 為同一筆框選改以相對「整個
/// widget/View 尺寸」（含 letterbox 留白）換算出的百分比值，僅供 UI
/// 定位使用（例如浮動 `AnnotationToolbar`）——PAGE_FIT 模式下頁面經常因
/// 長寬比與螢幕不同而產生 letterbox，若拿 [rect] 直接乘上整個 widget
/// 尺寸來定位 UI，會偏移 letterbox 留白的量（見 review 修正 Finding 1）。
/// [pageIndex] 為框選發生的頁碼（0-indexed）。
///
/// [text]（epic-27-reader-device-compat Issue 11）為框選矩形內萃取出的
/// 文字（見 `_PdfReaderViewState._extractTextInRect`），供
/// `AnnotationToolbar` 的「複製」按鈕使用；預設空字串。PDF 沒有對應
/// EPUB 的 `existingAnnotationId` 欄位——PDF 的既有標記命中判斷直接在
/// `ReaderScreen`（已持有 `_highlights`/`_notes`）用
/// `resolvePdfExistingAnnotation` 純函式計算，不需要像 EPUB 那樣跨
/// WebView bridge 傳遞一個中間編碼字串。
class PdfSelectionInfo {
  final int pageIndex;
  final PercentRect rect;
  final PercentRect widgetRect;
  final String text;

  const PdfSelectionInfo({
    required this.pageIndex,
    required this.rect,
    required this.widgetRect,
    this.text = '',
  });

  @override
  bool operator ==(Object other) =>
      other is PdfSelectionInfo &&
      other.pageIndex == pageIndex &&
      other.rect == rect &&
      other.widgetRect == widgetRect &&
      other.text == text;

  @override
  int get hashCode => Object.hash(pageIndex, rect, widgetRect, text);

  @override
  String toString() =>
      'PdfSelectionInfo(pageIndex: $pageIndex, rect: $rect, widgetRect: $widgetRect, text: $text)';
}

