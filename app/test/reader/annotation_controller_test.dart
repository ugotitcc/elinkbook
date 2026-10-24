import 'dart:async';

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

/// 可手動控制 listByBook 完成順序，模擬「較舊的查詢比較新的查詢晚回來」。
/// 繼承 [FakeHighlightsRepository]：儲存與 insert／delete 都沿用，只覆寫 listByBook。
class _GatedHighlightsRepository extends FakeHighlightsRepository {
  final List<Completer<void>> _gates = [];
  final List<bool> _failures = [];

  /// 下一次 listByBook 要等這個閘門；fail 為 true 時，放行後丟例外。
  Completer<void> gateNext({bool fail = false}) {
    final gate = Completer<void>();
    _gates.add(gate);
    _failures.add(fail);
    return gate;
  }

  /// 放行所有尚未完成的閘門；tearDown 呼叫，避免斷言失敗時遺留未完成的 Future。
  void releaseAll() {
    for (final gate in _gates) {
      if (!gate.isCompleted) gate.complete();
    }
    _gates.clear();
    _failures.clear();
  }

  @override
  Future<List<Highlight>> listByBook(String bookId) async {
    // 閘門與快照都在第一個 await 之前同步取得：快照定格在「呼叫當下」，
    // 閘門依「呼叫順序」分配。
    final snapshotFuture = super.listByBook(bookId);
    final gate = _gates.isEmpty ? null : _gates.removeAt(0);
    final fail = gate == null ? false : _failures.removeAt(0);
    final snapshot = await snapshotFuture;
    if (gate == null) return snapshot;
    await gate.future;
    if (fail) throw StateError('查詢失敗');
    return snapshot;
  }
}

/// 可手動控制 listByBook 完成順序；與 [_GatedHighlightsRepository] 對稱。
class _GatedNotesRepository extends FakeNotesRepository {
  final List<Completer<void>> _gates = [];
  final List<bool> _failures = [];

  Completer<void> gateNext({bool fail = false}) {
    final gate = Completer<void>();
    _gates.add(gate);
    _failures.add(fail);
    return gate;
  }

  void releaseAll() {
    for (final gate in _gates) {
      if (!gate.isCompleted) gate.complete();
    }
    _gates.clear();
    _failures.clear();
  }

  @override
  Future<List<Note>> listByBook(String bookId) async {
    final snapshotFuture = super.listByBook(bookId);
    final gate = _gates.isEmpty ? null : _gates.removeAt(0);
    final fail = gate == null ? false : _failures.removeAt(0);
    final snapshot = await snapshotFuture;
    if (gate == null) return snapshot;
    await gate.future;
    if (fail) throw StateError('查詢失敗');
    return snapshot;
  }
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

    test('寫入的是呼叫端捕捉的 selection，而非期間被 select() 換掉的選取', () async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final controller = _controller(highlightsRepo, notesRepo);
      final captured = _epubSelection(locatorJson: 'loc-a', progression: 0.3);
      controller.select(captured);
      // 模擬對話框開啟期間使用者又換了選取：寫入位置仍應取方法開頭捕捉的那個。
      controller.select(_epubSelection(locatorJson: 'loc-b', progression: 0.7));

      await controller.saveNote(selection: captured, text: '備註');

      expect(controller.notes.single.epubLocatorJson, 'loc-a');
      expect(controller.notes.single.progression, 0.3);
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

    test('退化選取但命中既有獨立備註時不忽略（與 existingItem 同一條解析規則）', () {
      const info = PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.3, top: 0.2, right: 0.3, bottom: 0.2),
        widgetRect: PercentRect(left: 0.3, top: 0.2, right: 0.3, bottom: 0.2),
      );

      expect(
        isIgnoredPdfSelection(
          info: info,
          highlights: const [],
          notes: const [
            Note(
              id: 'n-pdf',
              bookId: 'b1',
              text: '獨立備註',
              pdfPageIndex: 0,
              pdfRect: rect,
            ),
          ],
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

  group('reload 世代保護', () {
    late _GatedHighlightsRepository highlightsRepository;
    late _GatedNotesRepository notesRepository;
    late AnnotationController controller;

    setUp(() {
      highlightsRepository = _GatedHighlightsRepository();
      notesRepository = _GatedNotesRepository();
      controller = _controller(highlightsRepository, notesRepository);
    });

    tearDown(() {
      highlightsRepository.releaseAll();
      notesRepository.releaseAll();
    });

    test('先發的舊 reload、後發的新 reload；新的先完成、舊的後完成 → highlights 為新值（不被過期舊結果蓋掉）',
        () async {
      await highlightsRepository.insert(_highlight(id: 'h1'));

      final gateOld = highlightsRepository.gateNext();
      final futureOld = controller.reload();

      await highlightsRepository.insert(_highlight(id: 'h2'));

      final gateNew = highlightsRepository.gateNext();
      final futureNew = controller.reload();

      gateNew.complete();
      await futureNew;
      expect(controller.highlights.map((h) => h.id), ['h1', 'h2']);

      gateOld.complete();
      await futureOld;

      expect(controller.highlights.map((h) => h.id), ['h1', 'h2']);
    });

    test('循序兩次：第一次 reload 完成後才發第二次 → 兩次都依序套用', () async {
      await highlightsRepository.insert(_highlight(id: 'h1'));

      final gateOld = highlightsRepository.gateNext();
      final futureOld = controller.reload();
      gateOld.complete();
      await futureOld;
      expect(controller.highlights.map((h) => h.id), ['h1']);

      await highlightsRepository.insert(_highlight(id: 'h2'));

      final gateNew = highlightsRepository.gateNext();
      final futureNew = controller.reload();
      gateNew.complete();
      await futureNew;
      expect(controller.highlights.map((h) => h.id), ['h1', 'h2']);
    });

    test('並行兩次、舊的先完成：兩次 reload 都已發出，舊的先放行 → 當下 highlights 不變（舊結果丟掉），新的放行後才變成新值',
        () async {
      await highlightsRepository.insert(_highlight(id: 'h1'));

      final gateOld = highlightsRepository.gateNext();
      final futureOld = controller.reload();

      await highlightsRepository.insert(_highlight(id: 'h2'));

      final gateNew = highlightsRepository.gateNext();
      final futureNew = controller.reload();

      gateOld.complete();
      await futureOld;
      expect(controller.highlights, isEmpty);

      gateNew.complete();
      await futureNew;
      expect(controller.highlights.map((h) => h.id), ['h1', 'h2']);
    });

    test('舊的卡在第二個查詢（備註）時，新的整個完成；放行舊的 → 劃線與備註都維持新值（一起丟掉，不半套用）',
        () async {
      await highlightsRepository.insert(_highlight(id: 'h1'));
      await notesRepository.insert(
        const Note(id: 'n1', bookId: 'b1', text: 'n1', epubLocatorJson: 'loc'),
      );

      final gateNoteOld = notesRepository.gateNext();
      final futureOld = controller.reload();
      // 讓 futureOld 跑完劃線查詢（取得 [h1]）並推進到備註查詢閘門（取得快照 [n1] 並停住）
      await pumpEventQueue();

      await highlightsRepository.insert(_highlight(id: 'h2'));
      await notesRepository.insert(
        const Note(id: 'n2', bookId: 'b1', text: 'n2', epubLocatorJson: 'loc'),
      );

      await controller.reload();
      expect(controller.highlights.map((h) => h.id), ['h1', 'h2']);
      expect(controller.notes.map((n) => n.id), ['n1', 'n2']);

      gateNoteOld.complete();
      await futureOld;

      expect(controller.highlights.map((h) => h.id), ['h1', 'h2']);
      expect(controller.notes.map((n) => n.id), ['n1', 'n2']);
    });

    test('新的那次查詢失敗 → await 該次 reload() 丟例外，清單維持原值', () async {
      await highlightsRepository.insert(_highlight(id: 'h1'));
      await controller.reload();
      expect(controller.highlights.map((h) => h.id), ['h1']);

      final gateNew = highlightsRepository.gateNext(fail: true);
      final futureNew = controller.reload();
      gateNew.complete();

      await expectLater(futureNew, throwsA(isA<StateError>()));
      expect(controller.highlights.map((h) => h.id), ['h1']);
    });

    test('舊的那次查詢失敗 → await 該次 reload() 照舊丟例外，已套用的新值不變', () async {
      await highlightsRepository.insert(_highlight(id: 'h1'));

      final gateOld = highlightsRepository.gateNext(fail: true);
      final futureOld = controller.reload();

      await highlightsRepository.insert(_highlight(id: 'h2'));

      final gateNew = highlightsRepository.gateNext();
      final futureNew = controller.reload();

      gateNew.complete();
      await futureNew;
      expect(controller.highlights.map((h) => h.id), ['h1', 'h2']);

      gateOld.complete();
      await expectLater(futureOld, throwsA(isA<StateError>()));
      expect(controller.highlights.map((h) => h.id), ['h1', 'h2']);
    });

    test('開書第一次 reload（快照空）還沒回來，createHighlight 先完成，之後第一次 reload 才完成 → highlights 含新劃線，pendingHighlightId 為新劃線 id',
        () async {
      final gateInit = highlightsRepository.gateNext();
      final futureInit = controller.reload();

      controller.select(_epubSelection());
      await controller.createHighlight(HighlightStyle.highlighterYellow);
      expect(controller.highlights, hasLength(1));
      final createdId = controller.highlights.single.id;
      expect(controller.pendingHighlightId, createdId);

      gateInit.complete();
      await futureInit;

      expect(controller.highlights.map((h) => h.id), [createdId]);
      expect(controller.pendingHighlightId, createdId);
    });
  });
}
