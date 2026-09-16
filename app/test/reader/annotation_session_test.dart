import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/annotation_session.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/percent_rect.dart';

void main() {
  group('AnnotationSnapshot', () {
    test('內容相同時視為相等', () {
      const highlight = Highlight(
        id: 'h1',
        bookId: 'b1',
        style: HighlightStyle.highlighterYellow,
        epubLocatorJson: 'loc',
      );
      const note = Note(id: 'n1', bookId: 'b1', text: 'hi', epubLocatorJson: 'loc');
      const a = AnnotationSnapshot(highlights: [highlight], notes: [note]);
      const b = AnnotationSnapshot(highlights: [highlight], notes: [note]);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('highlights 清單內容不同時不相等', () {
      const h1 = Highlight(id: 'h1', bookId: 'b1', style: HighlightStyle.highlighterYellow);
      const h2 = Highlight(id: 'h2', bookId: 'b1', style: HighlightStyle.highlighterYellow);
      const a = AnnotationSnapshot(highlights: [h1], notes: []);
      const b = AnnotationSnapshot(highlights: [h2], notes: []);

      expect(a == b, isFalse);
    });
  });

  group('AnnotationLocator', () {
    test('.epub 只帶 EPUB 欄位，PDF 欄位皆為 null', () {
      const locator = AnnotationLocator.epub(locatorJson: 'loc', progression: 0.5);

      expect(locator.epubLocatorJson, 'loc');
      expect(locator.progression, 0.5);
      expect(locator.pdfPageIndex, isNull);
      expect(locator.pdfRect, isNull);
    });

    test('.pdf 只帶 PDF 欄位，EPUB 欄位皆為 null', () {
      const rect = PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.5);
      const locator = AnnotationLocator.pdf(pageIndex: 3, rect: rect);

      expect(locator.pdfPageIndex, 3);
      expect(locator.pdfRect, rect);
      expect(locator.epubLocatorJson, isNull);
      expect(locator.progression, isNull);
    });
  });
}
