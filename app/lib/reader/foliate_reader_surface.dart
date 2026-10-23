import 'package:flutter/widgets.dart';

import '../theme/elink_tokens.dart';
import 'epub_decoration.dart';
import 'foliate_reader_view.dart';
import 'highlight.dart';
import 'highlight_style.dart';
import 'note.dart';
import 'reader_jump_target.dart';
import 'reader_surface.dart';
import 'toc_entry.dart';
import 'tts_segment_cfi.dart';

/// 把劃線與備註轉成 Foliate 的 [EpubDecoration] 清單（原樣搬自
/// `ReaderScreen._sendDecorationsToNative`）：劃線在前、備註在後；只轉換有
/// `epubLocatorJson` 的項目；備註只轉換「獨立備註」（`highlightId` 為 null，
/// 掛在劃線上的備註由劃線本身呈現）。
List<EpubDecoration> buildEpubDecorations({
  required List<Highlight> highlights,
  required List<Note> notes,
  required ElinkTokens tokens,
}) {
  return <EpubDecoration>[
    for (final highlight in highlights)
      if (highlight.epubLocatorJson != null)
        EpubDecoration.forHighlight(
          highlightId: highlight.id,
          locatorJson: highlight.epubLocatorJson!,
          tint: highlightStyleColor(highlight.style, tokens: tokens).toARGB32(),
          isUnderline: highlight.style == HighlightStyle.underline,
        ),
    for (final note in notes)
      if (note.highlightId == null && note.epubLocatorJson != null)
        EpubDecoration.forNote(
          noteId: note.id,
          locatorJson: note.epubLocatorJson!,
          tint: noteOnlyTint.toARGB32(),
        ),
  ];
}

/// [ReaderSurface] 的 Foliate 實作（EPUB／KF8／CBZ／TXT／MD 共用）：每個指令
/// 逐一轉呼叫 [FoliateReaderView] 的 static 方法，未掛載時的靜默忽略與預設
/// 回傳值由那些 static 方法本身負責。
class FoliateReaderSurface implements ReaderSurface, FoliateFacet {
  FoliateReaderSurface({GlobalKey<State<FoliateReaderView>>? viewKey})
      : viewKey = viewKey ?? GlobalKey<State<FoliateReaderView>>();

  @override
  final GlobalKey<State<FoliateReaderView>> viewKey;

  @override
  FoliateFacet get foliate => this;

  @override
  PdfFacet? get pdf => null;

  @override
  void nextPage() => FoliateReaderView.nextPage(viewKey);

  @override
  void previousPage() => FoliateReaderView.previousPage(viewKey);

  @override
  void jumpTo(ReaderJumpTarget target) {
    final cfi = target.cfi;
    final progression = target.progression;
    if (cfi != null) {
      FoliateReaderView.jumpToLocator(viewKey, cfi);
    } else if (progression != null) {
      FoliateReaderView.jumpToProgression(viewKey, progression);
    }
  }

  @override
  bool showTransientHighlight(ReaderJumpTarget target) {
    final cfi = target.cfi;
    if (cfi == null) return false;
    FoliateReaderView.showSearchHighlight(viewKey, cfi);
    return true;
  }

  @override
  void clearTransientHighlight() => FoliateReaderView.clearSearchHighlight(viewKey);

  @override
  void clearSelection() => FoliateReaderView.clearSelection(viewKey);

  @override
  void suspendSelection() => FoliateReaderView.suspendSelection(viewKey);

  @override
  void restoreSelection() => FoliateReaderView.restoreSelection(viewKey);

  @override
  void refreshAnnotations({
    required List<Highlight> highlights,
    required List<Note> notes,
    required ElinkTokens tokens,
  }) {
    FoliateReaderView.setDecorations(
      viewKey,
      buildEpubDecorations(highlights: highlights, notes: notes, tokens: tokens),
    );
  }

  @override
  Future<List<TocEntry>> loadTableOfContents() =>
      FoliateReaderView.loadTableOfContents(viewKey);

  @override
  Future<List<TtsSegmentCfi>> loadTtsSegments(int sectionIndex) =>
      FoliateReaderView.loadTtsSegments(viewKey, sectionIndex);

  @override
  Future<int> lookupSegmentByCfi(String visibleCfi, List<String> segmentCfis) =>
      FoliateReaderView.lookupSegmentByCfi(viewKey, visibleCfi, segmentCfis);

  @override
  void showTtsHighlight(
    String cfi, {
    required bool vertical,
    required bool einkMode,
  }) =>
      FoliateReaderView.showTtsHighlight(
        viewKey,
        cfi,
        vertical: vertical,
        einkMode: einkMode,
      );

  @override
  void clearTtsHighlight() => FoliateReaderView.clearTtsHighlight(viewKey);
}
