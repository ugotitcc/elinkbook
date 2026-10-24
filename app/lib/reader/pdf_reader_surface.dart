import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../theme/elink_tokens.dart';
import 'highlight.dart';
import 'highlight_style.dart';
import 'note.dart';
import 'pdf_annotation_decoration.dart';
import 'pdf_reader_view.dart';
import 'pdf_search_match.dart';
import 'pdf_toc_item.dart';
import 'percent_rect.dart';
import 'reader_jump_target.dart';
import 'reader_surface.dart';

/// 把劃線與備註轉成 PDF 的 [PdfAnnotationDecoration] 清單（原樣搬自
/// `ReaderScreen._sendAnnotationsToNative` 的 PDF 分支）：劃線在前、備註在後；頁碼與
/// 座標都有才轉換；備註只轉換「獨立備註」（`highlightId` 為 null）。
List<PdfAnnotationDecoration> buildPdfAnnotationDecorations({
  required List<Highlight> highlights,
  required List<Note> notes,
  required ElinkTokens tokens,
}) {
  return <PdfAnnotationDecoration>[
    for (final highlight in highlights)
      if (highlight.pdfPageIndex != null && highlight.pdfRect != null)
        PdfAnnotationDecoration.forHighlight(
          pageIndex: highlight.pdfPageIndex!,
          rect: highlight.pdfRect!,
          tint: highlightStyleColor(highlight.style, tokens: tokens).toARGB32(),
          isUnderline: highlight.style == HighlightStyle.underline,
        ),
    for (final note in notes)
      if (note.highlightId == null &&
          note.pdfPageIndex != null &&
          note.pdfRect != null)
        PdfAnnotationDecoration.forNote(
          pageIndex: note.pdfPageIndex!,
          rect: note.pdfRect!,
          tint: noteOnlyTint.toARGB32(),
        ),
  ];
}

/// [ReaderSurface] 的 PDF 實作：每個指令逐一轉呼叫 [PdfReaderView] 的 static
/// 方法，未掛載時的靜默忽略與預設回傳值由那些 static 方法本身負責。
class PdfReaderSurface implements ReaderSurface, PdfFacet {
  PdfReaderSurface({GlobalKey<State<PdfReaderView>>? viewKey})
      : viewKey = viewKey ?? GlobalKey<State<PdfReaderView>>();

  @override
  final GlobalKey<State<PdfReaderView>> viewKey;

  @override
  FoliateFacet? get foliate => null;

  @override
  PdfFacet get pdf => this;

  @override
  void nextPage() => PdfReaderView.nextPage(viewKey);

  @override
  void previousPage() => PdfReaderView.previousPage(viewKey);

  @override
  void jumpTo(ReaderJumpTarget target) {
    final pageIndex = target.pdfPageIndex;
    if (pageIndex != null) PdfReaderView.jumpToPage(viewKey, pageIndex);
  }

  @override
  bool showTransientHighlight(ReaderJumpTarget target) {
    final pageIndex = target.pdfPageIndex;
    final rect = target.pdfRect;
    if (pageIndex == null || rect == null) return false;
    PdfReaderView.showTemporaryHighlight(viewKey, pageIndex, rect);
    return true;
  }

  @override
  void clearTransientHighlight() => PdfReaderView.clearTemporaryHighlight(viewKey);

  // PDF 的選取框是 Flutter 自己畫的，沒有 WebView 原生選取，這三個是空操作；
  // Dart 端的選取狀態由 ReaderScreen 清除（EPUB／PDF 共用同一個關閉流程）。
  @override
  void clearSelection() {}

  @override
  void suspendSelection() {}

  @override
  void restoreSelection() {}

  @override
  void refreshAnnotations({
    required List<Highlight> highlights,
    required List<Note> notes,
    required ElinkTokens tokens,
  }) {
    PdfReaderView.refreshAnnotations(
      viewKey,
      buildPdfAnnotationDecorations(
        highlights: highlights,
        notes: notes,
        tokens: tokens,
      ),
    );
  }

  @override
  Future<List<PdfTocItem>> loadTableOfContents() =>
      PdfReaderView.loadTableOfContents(viewKey);

  @override
  void cancelActiveSelectionDrag() =>
      PdfReaderView.cancelActiveSelectionDrag(viewKey);

  @override
  Future<List<PdfSearchMatch>> search(String query) =>
      PdfReaderView.search(viewKey, query);

  @override
  void setSearchHighlights(
    List<PdfSearchMatch> matches, {
    required int? currentIndex,
  }) =>
      PdfReaderView.setSearchHighlights(viewKey, matches, currentIndex: currentIndex);

  @override
  void jumpToPageAtRect(int pageIndex, PercentRect rect) =>
      PdfReaderView.jumpToPageAtRect(viewKey, pageIndex, rect);

  @override
  Future<ui.Image?> renderThumbnail(int pageIndex, {required double maxWidth}) =>
      PdfReaderView.renderThumbnail(viewKey, pageIndex, maxWidth: maxWidth);
}
