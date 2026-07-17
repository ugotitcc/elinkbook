import 'percent_rect.dart';

/// [PdfReaderView] 使用者長按拖曳框選劃線範圍完成時回報的資訊
/// （epic-6-annotations Issue 3）。[rect] 為框選矩形相對「目前顯示中
/// bitmap 內容範圍」的百分比值（見 plan-issue-3.md Global Constraints
/// 「PDF 座標協定」），[pageIndex] 為框選發生的頁碼（0-indexed）。
class PdfSelectionInfo {
  final int pageIndex;
  final PercentRect rect;

  const PdfSelectionInfo({required this.pageIndex, required this.rect});

  @override
  bool operator ==(Object other) =>
      other is PdfSelectionInfo && other.pageIndex == pageIndex && other.rect == rect;

  @override
  int get hashCode => Object.hash(pageIndex, rect);

  @override
  String toString() => 'PdfSelectionInfo(pageIndex: $pageIndex, rect: $rect)';
}
