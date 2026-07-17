import 'percent_rect.dart';

/// 單筆「劃線/純備註」的原生疊加樣式資訊（epic-6-annotations Issue 3），
/// 供 [PdfReaderView.refreshAnnotations] 一次性送出目前應顯示的完整標記
/// 清單（非增量 diff，比照 EPUB `EpubDecoration`／`setDecorations` 整組
/// 送出慣例）。與 [EpubDecoration] 的差異：PDF 端不支援點擊既有標記互動
/// （見 plan-issue-3.md Global Constraints），故 wire 格式不含 `id`
/// 欄位；改以 `pageIndex`＋`rect` 定位。[isNoteOnly] 為 true 時原生端
/// 額外於矩形右上角疊加一枚手繪黑白向量圖釘（圓形釘頭＋三角釘尖，見
/// `PdfReaderView.kt` 的 `drawNoteOnlyMarker`），刻意不使用系統 Emoji——
/// elinkBook 的核心場景之一是 E-Ink 黑白螢幕，Emoji 點陣化後對比度不足
/// （design.md 決策 #2，PDF 純備註畫面指示）。
class PdfAnnotationDecoration {
  final int pageIndex;
  final PercentRect rect;
  final int tint;
  final bool isUnderline;
  final bool isNoteOnly;

  const PdfAnnotationDecoration({
    required this.pageIndex,
    required this.rect,
    required this.tint,
    this.isUnderline = false,
    this.isNoteOnly = false,
  });

  factory PdfAnnotationDecoration.forHighlight({
    required int pageIndex,
    required PercentRect rect,
    required int tint,
    required bool isUnderline,
  }) {
    return PdfAnnotationDecoration(
      pageIndex: pageIndex,
      rect: rect,
      tint: tint,
      isUnderline: isUnderline,
    );
  }

  factory PdfAnnotationDecoration.forNote({
    required int pageIndex,
    required PercentRect rect,
    required int tint,
  }) {
    return PdfAnnotationDecoration(pageIndex: pageIndex, rect: rect, tint: tint, isNoteOnly: true);
  }

  Map<String, Object?> toWire() => {
        'pageIndex': pageIndex,
        'left': rect.left,
        'top': rect.top,
        'right': rect.right,
        'bottom': rect.bottom,
        'tint': tint,
        'isUnderline': isUnderline,
        'isNoteOnly': isNoteOnly,
      };
}
