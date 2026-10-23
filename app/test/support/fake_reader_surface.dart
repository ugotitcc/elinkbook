import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/pdf_search_match.dart';
import 'package:elinkbook/reader/pdf_toc_item.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/reader_jump_target.dart';
import 'package:elinkbook/reader/reader_surface.dart';
import 'package:elinkbook/reader/toc_entry.dart';
import 'package:elinkbook/reader/tts_segment_cfi.dart';
import 'package:elinkbook/theme/elink_tokens.dart';

/// 記錄指令的 [ReaderSurface] fake（epic-54 Issue 23）：不碰任何 View，只把
/// 指令名稱依序寫進 [calls]，供測試斷言「ReaderScreen 下了哪些指令」。
///
/// 兩個 facet 與其 `viewKey` 都是真實物件，且與本 surface 共用同一份 [calls]
/// 記錄（facet 指令帶 `foliate.`／`pdf.` 前綴），讓注入 fake 時
/// `ReaderScreen` 仍能用 `viewKey` 建構並掛載真實的 View（View 不會收到指令）。
class FakeReaderSurface implements ReaderSurface {
  FakeReaderSurface.foliate({this.showsTransientHighlight = false}) : pdf = null {
    foliate = FakeFoliateFacet(calls);
  }

  FakeReaderSurface.pdf({this.showsTransientHighlight = false}) {
    pdf = FakePdfFacet(calls);
  }

  /// [showTransientHighlight] 的回傳值，由測試指定。
  final bool showsTransientHighlight;

  /// 指令名稱，依呼叫順序。
  final List<String> calls = [];

  /// [jumpTo] 與 [showTransientHighlight] 收到的目標，依呼叫順序。
  final List<ReaderJumpTarget> jumpTargets = [];

  /// [refreshAnnotations] 收到的最後一組資料。
  List<Highlight> lastHighlights = const [];
  List<Note> lastNotes = const [];

  @override
  FakeFoliateFacet? foliate;

  @override
  FakePdfFacet? pdf;

  @override
  void nextPage() => calls.add('nextPage');

  @override
  void previousPage() => calls.add('previousPage');

  @override
  void jumpTo(ReaderJumpTarget target) {
    calls.add('jumpTo');
    jumpTargets.add(target);
  }

  @override
  bool showTransientHighlight(ReaderJumpTarget target) {
    calls.add('showTransientHighlight');
    jumpTargets.add(target);
    return showsTransientHighlight;
  }

  @override
  void clearTransientHighlight() => calls.add('clearTransientHighlight');

  @override
  void clearSelection() => calls.add('clearSelection');

  @override
  void suspendSelection() => calls.add('suspendSelection');

  @override
  void restoreSelection() => calls.add('restoreSelection');

  @override
  void refreshAnnotations({
    required List<Highlight> highlights,
    required List<Note> notes,
    required ElinkTokens tokens,
  }) {
    calls.add('refreshAnnotations');
    lastHighlights = highlights;
    lastNotes = notes;
  }
}

class FakeFoliateFacet implements FoliateFacet {
  FakeFoliateFacet(this._calls);

  final List<String> _calls;

  @override
  final GlobalKey<State<FoliateReaderView>> viewKey = GlobalKey();

  /// 測試可預先指定的查詢回傳值。
  List<TocEntry> toc = const [];
  List<TtsSegmentCfi> ttsSegments = const [];
  int segmentIndex = 0;

  @override
  Future<List<TocEntry>> loadTableOfContents() async {
    _calls.add('foliate.loadTableOfContents');
    return toc;
  }

  @override
  Future<List<TtsSegmentCfi>> loadTtsSegments(int sectionIndex) async {
    _calls.add('foliate.loadTtsSegments');
    return ttsSegments;
  }

  @override
  Future<int> lookupSegmentByCfi(
    String visibleCfi,
    List<String> segmentCfis,
  ) async {
    _calls.add('foliate.lookupSegmentByCfi');
    return segmentIndex;
  }

  @override
  void showTtsHighlight(
    String cfi, {
    required bool vertical,
    required bool einkMode,
  }) =>
      _calls.add('foliate.showTtsHighlight');

  @override
  void clearTtsHighlight() => _calls.add('foliate.clearTtsHighlight');
}

class FakePdfFacet implements PdfFacet {
  FakePdfFacet(this._calls);

  final List<String> _calls;

  @override
  final GlobalKey<State<PdfReaderView>> viewKey = GlobalKey();

  List<PdfTocItem> toc = const [];
  List<PdfSearchMatch> matches = const [];

  @override
  Future<List<PdfTocItem>> loadTableOfContents() async {
    _calls.add('pdf.loadTableOfContents');
    return toc;
  }

  @override
  void cancelActiveSelectionDrag() =>
      _calls.add('pdf.cancelActiveSelectionDrag');

  @override
  Future<List<PdfSearchMatch>> search(String query) async {
    _calls.add('pdf.search');
    return matches;
  }

  @override
  void setSearchHighlights(
    List<PdfSearchMatch> matches, {
    required int? currentIndex,
  }) =>
      _calls.add('pdf.setSearchHighlights');

  @override
  void jumpToPageAtRect(int pageIndex, PercentRect rect) =>
      _calls.add('pdf.jumpToPageAtRect');

  @override
  Future<ui.Image?> renderThumbnail(
    int pageIndex, {
    required double maxWidth,
  }) async {
    _calls.add('pdf.renderThumbnail');
    return null;
  }
}
