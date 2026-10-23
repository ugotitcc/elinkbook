import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/annotation_controller.dart';
import 'package:elinkbook/reader/annotation_list_item.dart';
import 'package:elinkbook/reader/epub_selection_info.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/pdf_selection_info.dart';
import 'package:elinkbook/reader/percent_rect.dart';

import '../support/fake_highlights_repository.dart';
import '../support/fake_notes_repository.dart';

const _epubRect = PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3);

/// 建一個只依賴兩個 fake repository 的 controller；[bookId] 固定 `b1`。
AnnotationController _controller(
  FakeHighlightsRepository highlightsRepo,
  FakeNotesRepository notesRepo,
) {
  return AnnotationController(
    highlightsRepository: highlightsRepo,
    notesRepository: notesRepo,
    bookId: 'b1',
  );
}

AnnotationSelection _epubSelection({
  String locatorJson = 'loc-a',
  double progression = 0.2,
  String text = '選取文字',
  String? existingAnnotationId,
}) {
  return AnnotationSelection.fromEpub(EpubSelectionInfo(
    locatorJson: locatorJson,
    progression: progression,
    rect: _epubRect,
    text: text,
    existingAnnotationId: existingAnnotationId,
  ));
}

Highlight _highlight({
  String id = 'h1',
  int? pdfPageIndex,
  PercentRect? pdfRect,
  String? epubLocatorJson = 'loc',
}) {
  return Highlight(
    id: id,
    bookId: 'b1',
    style: HighlightStyle.highlighterYellow,
    epubLocatorJson: epubLocatorJson,
    pdfPageIndex: pdfPageIndex,
    pdfRect: pdfRect,
  );
}

void main() {
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

  group('AnnotationController.reload', () {
    test('載入後 highlights／notes 為兩個 repository 的完整清單', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      await highlightsRepo.insert(_highlight(id: 'h1'));
      await notesRepo.insert(const Note(
        id: 'n1',
        bookId: 'b1',
        text: 'hi',
        epubLocatorJson: 'loc',
        progression: 0.1,
      ));
      final controller = _controller(highlightsRepo, notesRepo);

      await controller.reload();

      expect(controller.highlights, hasLength(1));
      expect(controller.highlights.single.id, 'h1');
      expect(controller.notes, hasLength(1));
      expect(controller.notes.single.id, 'n1');
    });

    // M-2（審查修訂）：不同 bookId 的資料須被過濾掉，避免未來實作遺漏
    // bookId 參數過濾而混入其他書籍的劃線/備註。
    test('只載入指定 bookId 的資料，其他書籍的劃線/備註不混入', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      await highlightsRepo.insert(_highlight(id: 'h1'));
      await highlightsRepo.insert(Highlight(
        id: 'h-other',
        bookId: 'b_other',
        style: HighlightStyle.highlighterYellow,
        epubLocatorJson: 'loc',
      ));
      await notesRepo.insert(
        const Note(id: 'n1', bookId: 'b1', text: 'hi', epubLocatorJson: 'loc'),
      );
      await notesRepo.insert(
        const Note(id: 'n-other', bookId: 'b_other', text: 'hi', epubLocatorJson: 'loc'),
      );
      final controller = _controller(highlightsRepo, notesRepo);

      await controller.reload();

      expect(controller.highlights, hasLength(1));
      expect(controller.highlights.single.id, 'h1');
      expect(controller.notes, hasLength(1));
      expect(controller.notes.single.id, 'n1');
    });
  });

  group('AnnotationController.createHighlight', () {
    test('EPUB：寫入 epubLocatorJson/progression，PDF 欄位維持 null，新 id 成為 pendingHighlightId',
        () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final controller = _controller(highlightsRepo, notesRepo);
      controller.select(_epubSelection(locatorJson: 'loc-a', progression: 0.2));

      await controller.createHighlight(HighlightStyle.highlighterYellow);

      expect(controller.highlights, hasLength(1));
      final inserted = controller.highlights.single;
      expect(inserted.id, controller.pendingHighlightId);
      expect(inserted.epubLocatorJson, 'loc-a');
      expect(inserted.progression, 0.2);
      expect(inserted.pdfPageIndex, isNull);
      expect(inserted.pdfRect, isNull);
    });

    test('PDF：寫入 pdfPageIndex/pdfRect，EPUB 欄位維持 null', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final controller = _controller(highlightsRepo, notesRepo);
      const rect = PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2);
      controller.select(AnnotationSelection.fromPdf(const PdfSelectionInfo(
        pageIndex: 4,
        rect: rect,
        widgetRect: rect,
        text: 'PDF 選取',
      )));

      await controller.createHighlight(HighlightStyle.underline);

      final inserted = controller.highlights.single;
      expect(inserted.id, controller.pendingHighlightId);
      expect(inserted.pdfPageIndex, 4);
      expect(inserted.pdfRect, rect);
      expect(inserted.epubLocatorJson, isNull);
      expect(inserted.progression, isNull);
    });

    test('無選取時不寫入任何劃線，pendingHighlightId 維持 null', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final controller = _controller(highlightsRepo, notesRepo);

      await controller.createHighlight(HighlightStyle.highlighterYellow);

      expect(controller.highlights, isEmpty);
      expect(controller.pendingHighlightId, isNull);
    });
  });

  group('AnnotationController.saveNote', () {
    test('existing 為 null 時新增備註', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final controller = _controller(highlightsRepo, notesRepo);
      final selection = _epubSelection(locatorJson: 'loc-a', progression: 0.3);

      await controller.saveNote(selection: selection, text: '新備註');

      expect(controller.notes, hasLength(1));
      expect(controller.notes.single.text, '新備註');
      expect(controller.notes.single.highlightId, isNull);
    });

    test('existing 非 null 時更新文字而非新增', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      const existing = Note(
        id: 'n1',
        bookId: 'b1',
        text: '舊文字',
        epubLocatorJson: 'loc-a',
        progression: 0.3,
      );
      await notesRepo.insert(existing);
      final controller = _controller(highlightsRepo, notesRepo);

      await controller.saveNote(
        selection: _epubSelection(locatorJson: 'loc-a', progression: 0.3),
        text: '改過的文字',
        existing: existing,
      );

      expect(controller.notes, hasLength(1));
      expect(controller.notes.single.id, 'n1');
      expect(controller.notes.single.text, '改過的文字');
    });

    test('剛建立的劃線成為新備註的 highlightId', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final controller = _controller(highlightsRepo, notesRepo);
      final selection = _epubSelection();
      controller.select(selection);
      await controller.createHighlight(HighlightStyle.highlighterYellow);
      final highlightId = controller.pendingHighlightId;

      await controller.saveNote(selection: selection, text: '依附的備註');

      expect(controller.notes.single.highlightId, highlightId);
    });

    // I-1（審查修訂）：前 3 則測試皆用 EPUB locator，完全沒有覆蓋 PDF
    // 新增路徑——若實作組裝 Note(...) 時漏傳 pdfPageIndex/pdfRect，前 3 則
    // 測試仍會全數通過，無法在單元測試層攔截。
    test('PDF：existing 為 null 時正確寫入 pdfPageIndex/pdfRect，EPUB 欄位維持 null',
        () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final controller = _controller(highlightsRepo, notesRepo);
      const rect = PercentRect(left: 0.1, top: 0.2, right: 0.8, bottom: 0.4);

      await controller.saveNote(
        selection: AnnotationSelection.fromPdf(const PdfSelectionInfo(
          pageIndex: 2,
          rect: rect,
          widgetRect: rect,
          text: 'PDF備註',
        )),
        text: 'PDF備註',
      );

      expect(controller.notes, hasLength(1));
      final inserted = controller.notes.single;
      expect(inserted.text, 'PDF備註');
      expect(inserted.pdfPageIndex, 2);
      expect(inserted.pdfRect, rect);
      expect(inserted.epubLocatorJson, isNull);
      expect(inserted.progression, isNull);
    });

    test('完成後清空選取與 pendingHighlightId', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final controller = _controller(highlightsRepo, notesRepo);
      final selection = _epubSelection();
      controller.select(selection);
      await controller.createHighlight(HighlightStyle.highlighterYellow);

      await controller.saveNote(selection: selection, text: '備註');

      expect(controller.selection, isNull);
      expect(controller.pendingHighlightId, isNull);
    });
  });

  group('AnnotationController 選取狀態', () {
    test('select 設定選取並清空上一次的 pendingHighlightId', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final controller = _controller(highlightsRepo, notesRepo);
      controller.select(_epubSelection());
      await controller.createHighlight(HighlightStyle.highlighterYellow);
      expect(controller.pendingHighlightId, isNotNull);
      final next = _epubSelection(locatorJson: 'loc-b', progression: 0.6);

      controller.select(next);

      expect(controller.selection, same(next));
      expect(controller.pendingHighlightId, isNull);
    });

    test('clearSelection 清空選取與 pendingHighlightId', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final controller = _controller(highlightsRepo, notesRepo);
      controller.select(_epubSelection());
      await controller.createHighlight(HighlightStyle.highlighterYellow);

      controller.clearSelection();

      expect(controller.selection, isNull);
      expect(controller.pendingHighlightId, isNull);
    });
  });

  group('AnnotationController.existingItem', () {
    test('EPUB：以 existingAnnotationId 命中劃線，並帶出其依附備註', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final highlight = _highlight(id: 'h1');
      const note = Note(
        id: 'n1',
        bookId: 'b1',
        text: '依附備註',
        epubLocatorJson: 'loc',
        highlightId: 'h1',
      );
      await highlightsRepo.insert(highlight);
      await notesRepo.insert(note);
      final controller = _controller(highlightsRepo, notesRepo);
      await controller.reload();

      controller.select(_epubSelection(existingAnnotationId: 'highlight:h1'));

      final item = controller.existingItem;
      expect(item?.highlight?.id, 'h1');
      expect(item?.note?.id, 'n1');
    });

    test('EPUB：沒命中既有標註時回傳 null', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final controller = _controller(highlightsRepo, notesRepo);
      await controller.reload();

      controller.select(_epubSelection());

      expect(controller.existingItem, isNull);
    });

    test('PDF：以框選矩形與既有劃線重疊命中', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      const rect = PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.3);
      await highlightsRepo.insert(
        _highlight(id: 'h-pdf', epubLocatorJson: null, pdfPageIndex: 0, pdfRect: rect),
      );
      final controller = _controller(highlightsRepo, notesRepo);
      await controller.reload();
      final selection = AnnotationSelection.fromPdf(const PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
        widgetRect: PercentRect(left: 0.2, top: 0.15, right: 0.4, bottom: 0.25),
      ));

      controller.select(selection);

      expect(controller.existingItem?.highlight?.id, 'h-pdf');
    });

    test('沒有選取時回傳 null', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final controller = _controller(highlightsRepo, notesRepo);

      expect(controller.existingItem, isNull);
    });
  });

  group('isIgnoredPdfSelection', () {
    const rect = PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.3);

    test('非退化選取（有拖曳範圍）一律不忽略', () {
      const info = PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.1, top: 0.1, right: 0.4, bottom: 0.3),
        widgetRect: PercentRect(left: 0.1, top: 0.1, right: 0.4, bottom: 0.3),
      );

      expect(
        isIgnoredPdfSelection(info: info, highlights: const [], notes: const []),
        isFalse,
      );
    });

    test('退化選取且未命中既有標註時忽略（單點長按不彈工具列）', () {
      const info = PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.3, top: 0.5, right: 0.3, bottom: 0.5),
        widgetRect: PercentRect(left: 0.3, top: 0.5, right: 0.3, bottom: 0.5),
      );

      expect(
        isIgnoredPdfSelection(info: info, highlights: const [], notes: const []),
        isTrue,
      );
    });

    test('退化選取但命中既有劃線時不忽略（顯示編輯工具列）', () {
      const info = PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.3, top: 0.2, right: 0.3, bottom: 0.2),
        widgetRect: PercentRect(left: 0.3, top: 0.2, right: 0.3, bottom: 0.2),
      );

      expect(
        isIgnoredPdfSelection(
          info: info,
          highlights: [
            _highlight(epubLocatorJson: null, pdfPageIndex: 0, pdfRect: rect),
          ],
          notes: const [],
        ),
        isFalse,
      );
    });
  });

  group('AnnotationSelection 欄位對映', () {
    test('fromEpub：locator 為 EPUB 定位、anchorRect 為 rect、帶 existingAnnotationId', () {
      final selection = AnnotationSelection.fromEpub(const EpubSelectionInfo(
        locatorJson: 'loc-a',
        progression: 0.4,
        rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
        text: '選取文字',
        existingAnnotationId: 'note:n1',
      ));

      expect(selection.locator.epubLocatorJson, 'loc-a');
      expect(selection.locator.progression, 0.4);
      expect(selection.locator.pdfPageIndex, isNull);
      expect(selection.text, '選取文字');
      expect(selection.anchorRect, const PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3));
      expect(selection.existingAnnotationId, 'note:n1');
    });

    test('fromPdf：locator 為 PDF 定位、anchorRect 取 widgetRect（含 letterbox）且無 existingAnnotationId',
        () {
      final selection = AnnotationSelection.fromPdf(const PdfSelectionInfo(
        pageIndex: 5,
        rect: PercentRect(left: 0.1, top: 0.1, right: 0.4, bottom: 0.2),
        widgetRect: PercentRect(left: 0.15, top: 0.2, right: 0.45, bottom: 0.3),
        text: 'PDF 選取',
      ));

      expect(selection.locator.pdfPageIndex, 5);
      expect(selection.locator.pdfRect, const PercentRect(left: 0.1, top: 0.1, right: 0.4, bottom: 0.2));
      expect(selection.locator.epubLocatorJson, isNull);
      expect(selection.text, 'PDF 選取');
      expect(selection.anchorRect, const PercentRect(left: 0.15, top: 0.2, right: 0.45, bottom: 0.3));
      expect(selection.existingAnnotationId, isNull);
    });
  });

  group('AnnotationController.deleteExisting', () {
    test('只有 highlight 時只刪除 highlight', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final highlight = _highlight(id: 'h1');
      await highlightsRepo.insert(highlight);
      final controller = _controller(highlightsRepo, notesRepo);
      await controller.reload();

      await controller.deleteExisting(AnnotationListItem(highlight: highlight));

      expect(controller.highlights, isEmpty);
    });

    test('只有 note 時只刪除 note', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      const note = Note(id: 'n1', bookId: 'b1', text: '純備註', epubLocatorJson: 'loc');
      await notesRepo.insert(note);
      final controller = _controller(highlightsRepo, notesRepo);
      await controller.reload();

      await controller.deleteExisting(const AnnotationListItem(note: note));

      expect(controller.notes, isEmpty);
    });

    test('highlight 與依附備註皆有時兩者一併刪除', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final highlight = _highlight(id: 'h1');
      const note = Note(
        id: 'n1',
        bookId: 'b1',
        text: '依附備註',
        epubLocatorJson: 'loc',
        highlightId: 'h1',
      );
      await highlightsRepo.insert(highlight);
      await notesRepo.insert(note);
      final controller = _controller(highlightsRepo, notesRepo);
      await controller.reload();

      await controller.deleteExisting(
        AnnotationListItem(highlight: highlight, note: note),
      );

      expect(controller.highlights, isEmpty);
      expect(controller.notes, isEmpty);
    });
  });
}
