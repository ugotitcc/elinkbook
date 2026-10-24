import 'annotation_list_item.dart';
import 'epub_decoration.dart';
import 'highlight.dart';
import 'note.dart';
import 'percent_rect.dart';

/// 依 EPUB 選取範圍回報的 [existingAnnotationId]（JS 端 hit-test 結果，
/// 見 main.js `reportSelection()`），反查是哪一筆既有畫線/備註記錄
/// （epic-27-reader-device-compat Issue 11）。純函式，不依賴
/// `_ReaderScreenState` 內部狀態，方便獨立單元測試；[highlights]/[notes]
/// 由呼叫端傳入目前的完整清單。查無對應記錄（理論上不會發生，id 皆由
/// `EpubDecoration` 具名建構子產生）時回傳 `null`。
AnnotationListItem? resolveEpubExistingAnnotation({
  required String? existingAnnotationId,
  required List<Highlight> highlights,
  required List<Note> notes,
}) {
  if (existingAnnotationId == null) return null;
  final decoded = decodeAnnotationId(existingAnnotationId);
  if (decoded == null) return null;
  switch (decoded.kind) {
    case AnnotationKind.highlight:
      for (final highlight in highlights) {
        if (highlight.id == decoded.id) {
          Note? note;
          for (final n in notes) {
            if (n.highlightId == highlight.id) {
              note = n;
              break;
            }
          }
          return AnnotationListItem(highlight: highlight, note: note);
        }
      }
      return null;
    case AnnotationKind.note:
      for (final note in notes) {
        if (note.id == decoded.id) return AnnotationListItem(note: note);
      }
      return null;
  }
}

/// 依 PDF 框選矩形，掃描同一頁既有畫線/備註是否與框選矩形重疊
/// （epic-27-reader-device-compat Issue 11）。PDF 框選不像 EPUB 走
/// WebView，沒有 JS 端可以預先算好命中結果，直接在這裡用純 Dart 矩形
/// 重疊比對；先掃畫線（連同它依附的備註一併回傳），沒有才掃純備註（比照
/// `ReaderScreen._sendAnnotationsToNative` 既有的
/// `note.highlightId == null` 判斷慣例，避免已依附畫線的備註被誤判為
/// 獨立命中）。
AnnotationListItem? resolvePdfExistingAnnotation({
  required int pageIndex,
  required PercentRect rect,
  required List<Highlight> highlights,
  required List<Note> notes,
}) {
  for (final highlight in highlights) {
    if (highlight.pdfPageIndex == pageIndex &&
        highlight.pdfRect != null &&
        highlight.pdfRect!.overlaps(rect)) {
      Note? note;
      for (final n in notes) {
        if (n.highlightId == highlight.id) {
          note = n;
          break;
        }
      }
      return AnnotationListItem(highlight: highlight, note: note);
    }
  }
  for (final note in notes) {
    if (note.highlightId == null &&
        note.pdfPageIndex == pageIndex &&
        note.pdfRect != null &&
        note.pdfRect!.overlaps(rect)) {
      return AnnotationListItem(note: note);
    }
  }
  return null;
}
