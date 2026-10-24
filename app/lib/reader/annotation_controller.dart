import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'annotation_list_item.dart';
import 'annotation_resolution.dart';
import 'epub_selection_info.dart';
import 'highlight.dart';
import 'highlight_style.dart';
import 'highlights_repository.dart';
import 'note.dart';
import 'notes_repository.dart';
import 'pdf_selection_info.dart';
import 'percent_rect.dart';

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

/// 使用者在畫面上選取的範圍（EPUB／PDF 統一）。
///
/// 兩個 View 的回呼型別（[EpubSelectionInfo]／[PdfSelectionInfo]）維持不變，
/// 由 `ReaderScreen` 接線處用 [AnnotationSelection.fromEpub]／
/// [AnnotationSelection.fromPdf] 轉換。`annotation_controller.dart` 因此仍
/// 看得見兩個格式專屬型別，但只在這兩個 factory 與 [isIgnoredPdfSelection]
/// 用到。
@immutable
class AnnotationSelection {
  const AnnotationSelection({
    required this.locator,
    required this.text,
    required this.anchorRect,
    this.existingAnnotationId,
  });

  factory AnnotationSelection.fromEpub(EpubSelectionInfo info) {
    return AnnotationSelection(
      locator: AnnotationLocator.epub(
        locatorJson: info.locatorJson,
        progression: info.progression,
      ),
      text: info.text,
      anchorRect: info.rect,
      existingAnnotationId: info.existingAnnotationId,
    );
  }

  factory AnnotationSelection.fromPdf(PdfSelectionInfo info) {
    return AnnotationSelection(
      locator: AnnotationLocator.pdf(pageIndex: info.pageIndex, rect: info.rect),
      text: info.text,
      // PDF 工具列用 widgetRect（相對整個 widget 尺寸，含 letterbox 留白），
      // 持久化仍用 locator 內的 rect（相對 bitmap 內容範圍）。
      anchorRect: info.widgetRect,
    );
  }

  final AnnotationLocator locator;
  final String text;

  /// 工具列定位用的錨點矩形：EPUB 為 `EpubSelectionInfo.rect`，PDF 為
  /// `PdfSelectionInfo.widgetRect`。
  final PercentRect anchorRect;

  /// 只有 EPUB 有（JS 端 hit-test 結果）；PDF 靠矩形重疊判斷既有標註。
  final String? existingAnnotationId;
}

/// PDF 退化選取（單點長按，`rect.left == rect.right`）且沒命中既有標註時
/// 回傳 `true`（這種選取是無效操作，應忽略、不彈工具列）。
///
/// 退化選取判定沿用 [PdfSelectionInfo.rect]——`pointPercentRect()` 保證
/// 零面積矩形的左右界精確相等。命中判斷用 [PdfSelectionInfo.rect] 與既有
/// 標註重疊（與 [AnnotationController.existingItem] 同一條規則）。
bool isIgnoredPdfSelection({
  required PdfSelectionInfo info,
  required List<Highlight> highlights,
  required List<Note> notes,
}) {
  final isDegenerate = info.rect.left == info.rect.right;
  if (!isDegenerate) return false;
  return resolvePdfExistingAnnotation(
        pageIndex: info.pageIndex,
        rect: info.rect,
        highlights: highlights,
        notes: notes,
      ) ==
      null;
}

/// 「標註」module：擁有目前選取範圍、同一次選取中剛建立的劃線 id
/// （`pendingHighlightId`，供接著建立的備註連結）、本書的劃線與備註清單，
/// 以及劃線／備註的新增、更新、刪除。
///
/// 不通知（不是 `ChangeNotifier`）：呼叫端（`ReaderScreen`）呼叫後自己
/// `setState`；也不碰 `BuildContext`／`GlobalKey`——備註對話框、複製提示、
/// 送原生端重畫都留在畫面層。
class AnnotationController {
  AnnotationController({
    required this.highlightsRepository,
    required this.notesRepository,
    required this.bookId,
  });

  final HighlightsRepository highlightsRepository;
  final NotesRepository notesRepository;
  final String bookId;

  List<Highlight> _highlights = const [];
  List<Note> _notes = const [];
  AnnotationSelection? _selection;
  String? _pendingHighlightId;
  int _reloadSeq = 0;

  List<Highlight> get highlights => _highlights;

  List<Note> get notes => _notes;

  AnnotationSelection? get selection => _selection;

  /// 同一次選取中剛建立的劃線 id（EPUB 的
  /// `_pendingHighlightIdForSelection`／PDF 的
  /// `_pendingPdfHighlightIdForSelection` 統一後的位置）。
  String? get pendingHighlightId => _pendingHighlightId;

  /// 目前選取命中的既有劃線／備註：EPUB 用 JS 端回報的
  /// `existingAnnotationId` 反查，PDF 用框選矩形重疊掃描。無選取或未命中
  /// 時回傳 `null`。
  AnnotationListItem? get existingItem {
    final selection = _selection;
    if (selection == null) return null;
    final pageIndex = selection.locator.pdfPageIndex;
    if (pageIndex != null) {
      final rect = selection.locator.pdfRect;
      if (rect == null) return null;
      return resolvePdfExistingAnnotation(
        pageIndex: pageIndex,
        rect: rect,
        highlights: _highlights,
        notes: _notes,
      );
    }
    return resolveEpubExistingAnnotation(
      existingAnnotationId: selection.existingAnnotationId,
      highlights: _highlights,
      notes: _notes,
    );
  }

  /// 設定選取，同時清掉上一次選取留下的 `pendingHighlightId`。
  void select(AnnotationSelection selection) {
    _selection = selection;
    _pendingHighlightId = null;
  }

  void clearSelection() {
    _selection = null;
    _pendingHighlightId = null;
  }

  /// 重新載入本書的劃線與備註清單（世代保護見 epic-54 Issue 32）：每次呼叫
  /// 遞增序號 [_reloadSeq]，在劃線與備註兩個查詢都完成後只檢查一次；若有較新的
  /// [reload] 已發出則兩份清單一起丟掉，否則兩份清單一起套用。不加 `try/catch`，
  /// 查詢失敗時例外照舊往外丟。
  Future<void> reload() async {
    final seq = ++_reloadSeq;
    final highlights = await highlightsRepository.listByBook(bookId);
    final notes = await notesRepository.listByBook(bookId);
    // 有較新的 reload 已發出：這次結果過期，兩份一起丟掉（Issue 32）。
    if (seq != _reloadSeq) return;
    _highlights = highlights;
    _notes = notes;
  }

  /// 依目前選取建立劃線；沒有選取時不動作。成功後把新劃線 id 設為
  /// [pendingHighlightId]，讓使用者接著按「備註」時能把備註連到這筆劃線。
  Future<void> createHighlight(HighlightStyle style) async {
    final selection = _selection;
    if (selection == null) return;
    final id = const Uuid().v4();
    final locator = selection.locator;
    await highlightsRepository.insert(Highlight(
      id: id,
      bookId: bookId,
      style: style,
      epubLocatorJson: locator.epubLocatorJson,
      progression: locator.progression,
      pdfPageIndex: locator.pdfPageIndex,
      pdfRect: locator.pdfRect,
    ));
    await reload();
    _pendingHighlightId = id;
  }

  /// `existing != null` 時更新該備註的文字，否則以 [selection] 的定位新增
  /// 備註。備註要依附哪一筆劃線，在真正寫入前才讀 [pendingHighlightId]
  /// ——比照原流程「對話框關閉後才取值」的時機。完成後清空選取與
  /// [pendingHighlightId]。
  Future<void> saveNote({
    required AnnotationSelection selection,
    required String text,
    Note? existing,
  }) async {
    final locator = selection.locator;
    if (existing != null) {
      await notesRepository.updateText(existing.id, text);
    } else {
      await notesRepository.insert(Note(
        id: const Uuid().v4(),
        bookId: bookId,
        text: text,
        epubLocatorJson: locator.epubLocatorJson,
        progression: locator.progression,
        pdfPageIndex: locator.pdfPageIndex,
        pdfRect: locator.pdfRect,
        highlightId: _pendingHighlightId,
      ));
    }
    await reload();
    _selection = null;
    _pendingHighlightId = null;
  }

  /// 刪除清單項目所含的備註／劃線，並重新載入清單。
  Future<void> deleteExisting(AnnotationListItem item) async {
    final note = item.note;
    final highlight = item.highlight;
    if (note != null) await notesRepository.delete(note.id);
    if (highlight != null) await highlightsRepository.delete(highlight.id);
    await reload();
  }
}
