import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'highlight.dart';
import 'highlight_style.dart';
import 'highlights_repository.dart';
import 'note.dart';
import 'notes_repository.dart';
import 'percent_rect.dart';

/// 劃線/備註 CRUD 完成後的最新清單快照（Epic 43 Issue 1）。無狀態回傳值
/// ——AnnotationSession 本身不持有狀態，呼叫端 (ReaderScreen) 拿到快照後
/// 自行 setState。
@immutable
class AnnotationSnapshot {
  const AnnotationSnapshot({required this.highlights, required this.notes});

  final List<Highlight> highlights;
  final List<Note> notes;

  @override
  bool operator ==(Object other) =>
      other is AnnotationSnapshot &&
      listEquals(other.highlights, highlights) &&
      listEquals(other.notes, notes);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(highlights), Object.hashAll(notes));
}

/// 統一 EPUB／PDF 定位方式的值物件——比照 [Highlight]/[Note] 建構子本身
/// 既有的「一組欄位皆可空」寫法，不引入正式 adapter 介面（`/grilling` Q1）。
@immutable
class AnnotationLocator {
  const AnnotationLocator.epub({required String locatorJson, this.progression})
      : epubLocatorJson = locatorJson,
        pdfPageIndex = null,
        pdfRect = null;

  const AnnotationLocator.pdf({required int pageIndex, required PercentRect rect})
      : pdfPageIndex = pageIndex,
        pdfRect = rect,
        epubLocatorJson = null,
        progression = null;

  final String? epubLocatorJson;
  final double? progression;
  final int? pdfPageIndex;
  final PercentRect? pdfRect;
}

/// 建構子注入依賴；只做 repository CRUD＋查詢，不依賴 BuildContext／
/// GlobalKey（`/grilling` Q3/Q5/Q6：送原生端、跳窗拿文字、UI 收尾皆留在
/// ReaderScreen 呼叫端），純資料物件，回傳快照而非產生副作用（Q2）。
class AnnotationSession {
  AnnotationSession({
    required this.highlightsRepository,
    required this.notesRepository,
    required this.bookId,
  });

  final HighlightsRepository highlightsRepository;
  final NotesRepository notesRepository;
  final String bookId;

  Future<AnnotationSnapshot> reload() async {
    final highlights = await highlightsRepository.listByBook(bookId);
    final notes = await notesRepository.listByBook(bookId);
    return AnnotationSnapshot(highlights: highlights, notes: notes);
  }

  /// 回傳新建 highlight 的 id（供呼叫端設定
  /// `_pendingHighlightIdForSelection`/`_pendingPdfHighlightIdForSelection`），
  /// 取代原本用 side-effect 直接寫欄位的作法。
  Future<({AnnotationSnapshot snapshot, String highlightId})> createHighlight({
    required AnnotationLocator locator,
    required HighlightStyle style,
  }) async {
    final id = const Uuid().v4();
    await highlightsRepository.insert(Highlight(
      id: id,
      bookId: bookId,
      style: style,
      epubLocatorJson: locator.epubLocatorJson,
      progression: locator.progression,
      pdfPageIndex: locator.pdfPageIndex,
      pdfRect: locator.pdfRect,
    ));
    final snapshot = await reload();
    return (snapshot: snapshot, highlightId: id);
  }
}
