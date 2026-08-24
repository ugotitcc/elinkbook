import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/annotation_resolution.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/pdf_selection_info.dart';
import 'package:elinkbook/reader/percent_rect.dart';

void main() {
  group('resolveEpubExistingAnnotation', () {
    test('existingAnnotationId 為 null 時回傳 null', () {
      final result = resolveEpubExistingAnnotation(
        existingAnnotationId: null,
        highlights: const [],
        notes: const [],
      );
      expect(result, isNull);
    });

    test('命中畫線 id 時回傳含該畫線與其依附備註的 AnnotationListItem', () {
      const highlight = Highlight(
        id: 'h1',
        bookId: 'b1',
        style: HighlightStyle.highlighterYellow,
        epubLocatorJson: '{"cfi":"epubcfi(/6/4)"}',
      );
      const note = Note(
        id: 'n1',
        bookId: 'b1',
        text: 'note text',
        epubLocatorJson: '{"cfi":"epubcfi(/6/4)"}',
        highlightId: 'h1',
      );
      final result = resolveEpubExistingAnnotation(
        existingAnnotationId: 'highlight:h1',
        highlights: const [highlight],
        notes: const [note],
      );
      expect(result?.highlight?.id, 'h1');
      expect(result?.note?.id, 'n1');
    });

    test('命中純備註 id 時回傳只含備註的 AnnotationListItem', () {
      const note = Note(
        id: 'n2',
        bookId: 'b1',
        text: 'standalone note',
        epubLocatorJson: '{"cfi":"epubcfi(/6/8)"}',
      );
      final result = resolveEpubExistingAnnotation(
        existingAnnotationId: 'note:n2',
        highlights: const [],
        notes: const [note],
      );
      expect(result?.highlight, isNull);
      expect(result?.note?.id, 'n2');
    });

    test('id 格式合法但查無對應記錄時回傳 null', () {
      final result = resolveEpubExistingAnnotation(
        existingAnnotationId: 'highlight:not-exist',
        highlights: const [],
        notes: const [],
      );
      expect(result, isNull);
    });
  });

  group('resolvePdfExistingAnnotation', () {
    test('框選矩形與既有畫線重疊時回傳含該畫線的 AnnotationListItem', () {
      const highlight = Highlight(
        id: 'h1',
        bookId: 'b1',
        style: HighlightStyle.highlighterYellow,
        pdfPageIndex: 0,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.3),
      );
      const selection = PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
        widgetRect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
      );
      final result = resolvePdfExistingAnnotation(
        selection: selection,
        highlights: const [highlight],
        notes: const [],
      );
      expect(result?.highlight?.id, 'h1');
    });

    test('框選矩形與既有畫線不重疊時回傳 null', () {
      const highlight = Highlight(
        id: 'h1',
        bookId: 'b1',
        style: HighlightStyle.highlighterYellow,
        pdfPageIndex: 0,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.2, bottom: 0.2),
      );
      const selection = PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.7, top: 0.7, right: 0.9, bottom: 0.9),
        widgetRect: PercentRect(left: 0.7, top: 0.7, right: 0.9, bottom: 0.9),
      );
      final result = resolvePdfExistingAnnotation(
        selection: selection,
        highlights: const [highlight],
        notes: const [],
      );
      expect(result, isNull);
    });

    test('不同頁的畫線即使矩形數值重疊也不命中（頁碼優先比對）', () {
      const highlight = Highlight(
        id: 'h1',
        bookId: 'b1',
        style: HighlightStyle.highlighterYellow,
        pdfPageIndex: 1,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.3),
      );
      const selection = PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
        widgetRect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
      );
      final result = resolvePdfExistingAnnotation(
        selection: selection,
        highlights: const [highlight],
        notes: const [],
      );
      expect(result, isNull);
    });

    test('框選矩形與純備註（無畫線）重疊時回傳只含備註的 AnnotationListItem', () {
      const note = Note(
        id: 'n1',
        bookId: 'b1',
        text: 'pdf standalone note',
        pdfPageIndex: 0,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.3),
      );
      const selection = PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
        widgetRect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
      );
      final result = resolvePdfExistingAnnotation(
        selection: selection,
        highlights: const [],
        notes: const [note],
      );
      expect(result?.note?.id, 'n1');
      expect(result?.highlight, isNull);
    });

    test('已依附於畫線的備註（highlightId 非 null）不會被當成獨立命中', () {
      const note = Note(
        id: 'n1',
        bookId: 'b1',
        text: 'attached note',
        pdfPageIndex: 0,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.3),
        highlightId: 'h-not-in-list',
      );
      const selection = PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
        widgetRect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
      );
      final result = resolvePdfExistingAnnotation(
        selection: selection,
        highlights: const [],
        notes: const [note],
      );
      expect(result, isNull,
          reason: '比照 _sendPdfAnnotationsToNative 既有慣例，highlightId '
              '非 null 的備註是依附於某筆畫線顯示，不應被當成獨立的純'
              '備註命中。');
    });
  });
}
