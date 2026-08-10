import 'percent_rect.dart';

/// 單筆 PDF 內文搜尋符合結果（epic-24-pdf-engine-rebuild Issue 6）。
/// [pageIndex] 為 0-indexed（比照專案既有慣例），[rect] 是相對整頁（未經
/// 裁切轉換）的 `PercentRect`——與 [PdfAnnotationDecoration.rect]
/// （`pdf_annotation_decoration.dart`）採用同一種座標語意，`PdfReaderView`
/// 疊加渲染時會比照劃線/備註的既有作法，在裁切模式啟用時另外呼叫
/// `originalToCropRelativePercent()` 換算為裁切相對座標。
class PdfSearchMatch {
  final int pageIndex;
  final String text;
  final PercentRect rect;

  const PdfSearchMatch({
    required this.pageIndex,
    required this.text,
    required this.rect,
  });

  @override
  bool operator ==(Object other) =>
      other is PdfSearchMatch &&
      other.pageIndex == pageIndex &&
      other.text == text &&
      other.rect == rect;

  @override
  int get hashCode => Object.hash(pageIndex, text, rect);

  @override
  String toString() =>
      'PdfSearchMatch(pageIndex: $pageIndex, text: $text, rect: $rect)';
}
