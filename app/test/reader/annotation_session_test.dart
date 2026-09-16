import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/annotation_session.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/highlights_repository.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/notes_repository.dart';
import 'package:elinkbook/reader/percent_rect.dart';

import '../support/fake_highlights_repository.dart';
import '../support/fake_notes_repository.dart';

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

  group('AnnotationSession.reload', () {
    test('回傳兩個 repository 目前的完整清單', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      await highlightsRepo.insert(const Highlight(
        id: 'h1',
        bookId: 'b1',
        style: HighlightStyle.highlighterYellow,
        epubLocatorJson: 'loc',
        progression: 0.1,
      ));
      await notesRepo.insert(const Note(
        id: 'n1',
        bookId: 'b1',
        text: 'hi',
        epubLocatorJson: 'loc',
        progression: 0.1,
      ));
      final session = AnnotationSession(
        highlightsRepository: highlightsRepo,
        notesRepository: notesRepo,
        bookId: 'b1',
      );

      final snapshot = await session.reload();

      expect(snapshot.highlights, hasLength(1));
      expect(snapshot.highlights.single.id, 'h1');
      expect(snapshot.notes, hasLength(1));
      expect(snapshot.notes.single.id, 'n1');
    });

    // M-2（審查修訂）：不同 bookId 的資料須被過濾掉，避免未來實作遺漏
    // bookId 參數過濾而混入其他書籍的劃線/備註。
    test('只回傳指定 bookId 的資料，其他書籍的劃線/備註不混入', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      await highlightsRepo.insert(const Highlight(
        id: 'h1',
        bookId: 'b1',
        style: HighlightStyle.highlighterYellow,
        epubLocatorJson: 'loc',
      ));
      await highlightsRepo.insert(const Highlight(
        id: 'h-other',
        bookId: 'b_other',
        style: HighlightStyle.highlighterYellow,
        epubLocatorJson: 'loc',
      ));
      await notesRepo.insert(const Note(id: 'n1', bookId: 'b1', text: 'hi', epubLocatorJson: 'loc'));
      await notesRepo.insert(
        const Note(id: 'n-other', bookId: 'b_other', text: 'hi', epubLocatorJson: 'loc'),
      );
      final session = AnnotationSession(
        highlightsRepository: highlightsRepo,
        notesRepository: notesRepo,
        bookId: 'b1',
      );

      final snapshot = await session.reload();

      expect(snapshot.highlights, hasLength(1));
      expect(snapshot.highlights.single.id, 'h1');
      expect(snapshot.notes, hasLength(1));
      expect(snapshot.notes.single.id, 'n1');
    });
  });

  group('AnnotationSession.createHighlight', () {
    test('EPUB：寫入 epubLocatorJson/progression，PDF 欄位維持 null，回傳新 id', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final session = AnnotationSession(
        highlightsRepository: highlightsRepo,
        notesRepository: notesRepo,
        bookId: 'b1',
      );

      final result = await session.createHighlight(
        locator: const AnnotationLocator.epub(locatorJson: 'loc-a', progression: 0.2),
        style: HighlightStyle.highlighterYellow,
      );

      expect(result.snapshot.highlights, hasLength(1));
      final inserted = result.snapshot.highlights.single;
      expect(inserted.id, result.highlightId);
      expect(inserted.epubLocatorJson, 'loc-a');
      expect(inserted.progression, 0.2);
      expect(inserted.pdfPageIndex, isNull);
      expect(inserted.pdfRect, isNull);
    });

    test('PDF：寫入 pdfPageIndex/pdfRect，EPUB 欄位維持 null', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final session = AnnotationSession(
        highlightsRepository: highlightsRepo,
        notesRepository: notesRepo,
        bookId: 'b1',
      );
      const rect = PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2);

      final result = await session.createHighlight(
        locator: const AnnotationLocator.pdf(pageIndex: 4, rect: rect),
        style: HighlightStyle.underline,
      );

      final inserted = result.snapshot.highlights.single;
      expect(inserted.id, result.highlightId);
      expect(inserted.pdfPageIndex, 4);
      expect(inserted.pdfRect, rect);
      expect(inserted.epubLocatorJson, isNull);
      expect(inserted.progression, isNull);
    });
  });
}
