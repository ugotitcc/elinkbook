import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../reader/annotation_list_item.dart';
import '../reader/bookmark.dart';
import '../reader/bookmark_position_context.dart';
import '../reader/bookmarks_repository.dart';
import '../reader/highlight.dart';
import '../reader/highlight_style.dart';
import '../reader/highlights_repository.dart';
import '../reader/note.dart';
import '../reader/notes_repository.dart';
import '../reader/text_conversion.dart';
import '../reader/text_conversion_mode.dart';
import '../reader/markdown_export.dart';
import '../theme/elink_tokens.dart';
import 'note_edit_dialog.dart';
import 'widgets/eb_field_card.dart';
import 'widgets/eb_sheet_shell.dart';

/// 統一的「筆記」入口 Bottom Sheet 外殼（epic-6-annotations Issue 1，
/// spec.md「統一入口與 Bottom Sheet」）：帶「🔖 書籤」／「✏️ 劃線與備註」
/// 兩個分頁籤，兩分頁底下的資料層完全獨立（design.md 決策 #1）。「書籤」
/// 分頁於 Issue 1 完整實作；「劃線與備註」分頁於 Issue 2 針對流式 EPUB
/// 正式生效（`highlightsRepository`／`notesRepository` 皆提供時），PDF
/// 支援留待 Issue 3；未提供這兩個 repository 時（FXL、尚未支援的 PDF）
/// 仍維持空狀態佔位符。
class NotesBottomSheet extends StatefulWidget {
  final String bookId;
  final BookmarksRepository bookmarksRepository;

  /// 供「導出為 Markdown」使用的書籍中繼資料（epic-6-annotations
  /// Issue 5）。皆為必填——唯一正式呼叫端 `ReaderScreen._openNotesSheet`
  /// 一定會提供值（見 plan-issue-5.md Global Constraints）。
  final String bookTitle;
  final String? bookAuthor;
  final double bookProgress;

  /// 開啟當下的目前位置上下文，供書籤 toggle 按鈕判斷目前位置是否已有
  /// 書籤、以及新增書籤時計算預設名稱（Global Constraints「書籤 toggle
  /// 的相等性判斷」）。
  final BookmarkPositionContext currentPosition;

  /// 使用者點選某筆書籤時觸發，呼叫端負責實際跳轉並關閉本 Bottom Sheet。
  final ValueChanged<Bookmark> onBookmarkSelected;

  /// 劃線／備註資料存取層（epic-6-annotations Issue 2）。兩者皆為
  /// 可選具名參數，且必須「同時提供」才會顯示真實內容——未提供（或只提供
  /// 其中一個）時「✏️」分頁維持 Issue 1 既有的空狀態佔位符，讓 FXL
  /// （不支援劃線/備註，見 issues.md Issue 4）與尚未做完 Issue 3 的 PDF
  /// 呼叫端零回歸沿用。
  final HighlightsRepository? highlightsRepository;
  final NotesRepository? notesRepository;

  /// 使用者點選某筆合併項目時觸發，呼叫端負責實際跳轉並關閉本 Bottom
  /// Sheet（比照 [onBookmarkSelected] 既有模式）。
  final ValueChanged<AnnotationListItem>? onAnnotationSelected;

  /// 本 Bottom Sheet 內任何劃線/備註 CRUD 動作完成後觸發，供呼叫端
  /// （ReaderScreen）重新查詢並把最新標記清單送給原生端重繪 Decorator
  /// （見 Task 10）。
  final VoidCallback? onAnnotationsChanged;

  /// 開啟後預設停在哪個分頁（0＝🔖書籤、1＝✏️劃線與備註）。
  /// `epic-38-reader-chrome-tts-redesign` Issue 1：底部「✎ 劃線筆記」按鈕
  /// 傳入 `1`，預設停在劃線分頁；既有呼叫端不傳則維持既有分頁 0。
  final int initialTabIndex;

  /// 簡繁顯示轉換模式（FR-48，epic-42-text-conversion Issue 3）：套用在
  /// 書籤清單的 [Bookmark.name] 上。**不套用**在備註文字（[Note.text]）
  /// 上——備註是使用者輸入的自由文字，恆維持原樣。issues.md Issue 3
  /// 提及的「劃線清單摘要片段」轉換在目前程式碼中無對應渲染點可修改：
  /// 本專案 `Highlight` model 從未儲存劃線框住的原文片段，劃線清單只
  /// 顯示樣式標籤（見 `markdown_export.dart` 開頭文件註解的既有設計
  /// 決策），此為刻意留白、非遺漏（詳見 plan-issue-3.md Global
  /// Constraints）。預設 `TextConversionMode.original`（向後相容既有
  /// 呼叫端／測試）。
  final TextConversionMode textConversion;

  const NotesBottomSheet({
    super.key,
    required this.bookId,
    required this.bookTitle,
    this.bookAuthor,
    required this.bookProgress,
    required this.bookmarksRepository,
    required this.currentPosition,
    required this.onBookmarkSelected,
    this.highlightsRepository,
    this.notesRepository,
    this.onAnnotationSelected,
    this.onAnnotationsChanged,
    this.initialTabIndex = 0,
    this.textConversion = TextConversionMode.original,
  });

  @override
  State<NotesBottomSheet> createState() => _NotesBottomSheetState();
}

class _NotesBottomSheetState extends State<NotesBottomSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<Bookmark> _bookmarks = [];
  List<Highlight> _highlights = [];
  List<Note> _notes = [];
  // 重新命名對話框使用的 TextEditingController（審查修正：修補洩漏）。
  // 刻意不在 _renameBookmark 的 showDialog 呼叫結束後立即 dispose——
  // showDialog 回傳的 Future 會在 Navigator.pop() 當下就完成，早於
  // AlertDialog 的退場轉場動畫實際跑完，此時其底下的 TextField 仍會在
  // 後續幾個 frame 被重新 build，若此時已 dispose 會拋出
  // 「TextEditingController used after being disposed」。故改為交由本
  // State 自己的生命週期保管：每次重新命名時若有前一個實例則先 dispose，
  // 並在 [dispose] 一併清理，確保退場動畫跑完後仍安全、且不會永久洩漏。
  TextEditingController? _renameController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _loadBookmarks();
    _loadAnnotations();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _renameController?.dispose();
    super.dispose();
  }

  Future<void> _loadBookmarks() async {
    final list = await widget.bookmarksRepository.listByBook(widget.bookId);
    if (!mounted) return;
    setState(() => _bookmarks = list);
  }

  Future<void> _loadAnnotations() async {
    final highlightsRepository = widget.highlightsRepository;
    final notesRepository = widget.notesRepository;
    if (highlightsRepository == null || notesRepository == null) return;
    final highlights = await highlightsRepository.listByBook(widget.bookId);
    final notes = await notesRepository.listByBook(widget.bookId);
    if (!mounted) return;
    setState(() {
      _highlights = highlights;
      _notes = notes;
    });
  }

  /// 【審查修正 M-1】包在 try-catch 內——`getTemporaryDirectory()`／
  /// `writeAsString()`／`SharePlus.instance.share()` 皆涉及非同步 I/O 與
  /// 平台通道，極端環境（例如儲存空間不足、使用者中途取消系統分享面板
  /// 拋出例外）下不應讓整個 Bottom Sheet 崩潰，比照專案既有對外部 I/O
  /// 失敗的防禦性慣例（見 `_loadFxlBookmarks()` 既有寫法）。
  Future<void> _exportMarkdown() async {
    try {
      final markdown = generateMarkdownExport(
        bookTitle: widget.bookTitle,
        bookAuthor: widget.bookAuthor,
        progress: widget.bookProgress,
        exportTime: DateTime.now(),
        bookmarks: _bookmarks,
        annotations: mergeAnnotations(_highlights, _notes),
      );
      final tempDir = await getTemporaryDirectory();
      final fileName = 'notes-${sanitizeMarkdownFileName(widget.bookTitle)}.md';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(markdown);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'text/markdown')]),
      );
    } catch (e) {
      debugPrint('Failed to export markdown: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // `DESIGN.md` §10／§14.2：筆記面板由 `EBSheetShell` 統一包裹（拖曳
    // 把手／標題／關閉按鈕／高度上限 85% 螢幕高度），取代原本自建的
    // SafeArea+SizedBox(固定高度)+手刻標題列；「導出為 Markdown」透過
    // `EBSheetShell.actions` 插入標題列。
    return EBSheetShell(
      title: '筆記',
      actions: [
        IconButton(
          key: const Key('notes_sheet_export_markdown'),
          onPressed: _exportMarkdown,
          icon: const Icon(Icons.ios_share),
          tooltip: '導出為 Markdown',
        ),
      ],
      child: Column(
        children: [
          // `DESIGN.md` §14.2：分頁標籤一律搭配圖示＋文字，不使用 Emoji
          // （舊版曾用 🔖／✏️ 作為分頁圖示，已淘汰）。
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(
                key: Key('notes_sheet_tab_bookmarks'),
                icon: Icon(Icons.bookmark_outline),
                text: '書籤',
              ),
              Tab(
                key: Key('notes_sheet_tab_annotations'),
                icon: Icon(Icons.edit_note),
                text: '劃線與備註',
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBookmarksTab(),
                _buildAnnotationsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookmarksTab() {
    final existing = _bookmarkAtCurrentPosition;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('notes_sheet_bookmark_toggle'),
                  icon: Icon(existing != null ? Icons.star : Icons.star_border),
                  label: Text(existing != null ? '已加入此頁書籤' : '加入此頁書籤'),
                  onPressed: _toggleBookmark,
                ),
              ),
              IconButton(
                key: const Key('notes_sheet_delete_all_bookmarks'),
                icon: const Icon(Icons.delete_sweep),
                tooltip: '刪除該書所有書籤',
                onPressed:
                    _bookmarks.isEmpty ? null : _confirmDeleteAllBookmarks,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const Key('notes_sheet_bookmark_list'),
            itemCount: _bookmarks.length,
            itemBuilder: (context, index) =>
                _buildBookmarkRow(_bookmarks[index]),
          ),
        ),
      ],
    );
  }

  /// 目前位置是否已有書籤——EPUB／FXL 比對 epubLocatorJson 是否完全相同
  /// 字串，PDF 比對 pdfPageIndex 是否相同（見 Global Constraints「書籤
  /// toggle 的相等性判斷」，審查修正 1.1）。
  bool _matchesCurrentPosition(Bookmark bookmark) {
    final pdfPageIndex = widget.currentPosition.pdfPageIndex;
    if (pdfPageIndex != null) return bookmark.pdfPageIndex == pdfPageIndex;
    final epubLocatorJson = widget.currentPosition.epubLocatorJson;
    if (epubLocatorJson != null) {
      return bookmark.epubLocatorJson == epubLocatorJson;
    }
    return false;
  }

  Bookmark? get _bookmarkAtCurrentPosition {
    for (final bookmark in _bookmarks) {
      if (_matchesCurrentPosition(bookmark)) return bookmark;
    }
    return null;
  }

  Future<void> _toggleBookmark() async {
    final existing = _bookmarkAtCurrentPosition;
    if (existing != null) {
      await widget.bookmarksRepository.delete(existing.id);
    } else {
      await widget.bookmarksRepository.insert(Bookmark(
        id: const Uuid().v4(),
        bookId: widget.bookId,
        name: Bookmark.defaultName(widget.currentPosition),
        epubLocatorJson: widget.currentPosition.epubLocatorJson,
        progression: widget.currentPosition.progression,
        pdfPageIndex: widget.currentPosition.pdfPageIndex,
      ));
    }
    await _loadBookmarks();
  }

  Future<void> _renameBookmark(Bookmark bookmark) async {
    // 前一次重新命名的 controller 若還沒被回收（正常情況下對話框是 modal，
    // 不會有並行呼叫），先行 dispose 避免累積多個未釋放的實例。
    _renameController?.dispose();
    final controller = TextEditingController(text: bookmark.name);
    _renameController = controller;
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重新命名書籤'),
        content: TextField(
          key: const Key('notes_sheet_rename_field'),
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('notes_sheet_rename_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    if (newName == null || newName.trim().isEmpty) return;
    await widget.bookmarksRepository.rename(bookmark.id, newName.trim());
    await _loadBookmarks();
  }

  Future<void> _deleteBookmark(Bookmark bookmark) async {
    await widget.bookmarksRepository.delete(bookmark.id);
    await _loadBookmarks();
  }

  Future<void> _confirmDeleteAllBookmarks() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('確定要刪除全部書籤嗎？（共 ${_bookmarks.length} 筆）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('notes_sheet_delete_all_bookmarks_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.bookmarksRepository.deleteAllForBook(widget.bookId);
    await _loadBookmarks();
  }

  Widget _buildBookmarkRow(Bookmark bookmark) {
    return EBFieldCard(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        key: Key('notes_sheet_bookmark_${bookmark.id}'),
        title: Text(convertText(bookmark.name, widget.textConversion)),
        onTap: () => widget.onBookmarkSelected(bookmark),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: Key('notes_sheet_bookmark_rename_${bookmark.id}'),
              icon: const Icon(Icons.edit),
              tooltip: '重新命名',
              onPressed: () => _renameBookmark(bookmark),
            ),
            IconButton(
              key: Key('notes_sheet_bookmark_delete_${bookmark.id}'),
              icon: const Icon(Icons.delete),
              tooltip: '刪除',
              onPressed: () => _deleteBookmark(bookmark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnnotationsTab() {
    final highlightsRepository = widget.highlightsRepository;
    final notesRepository = widget.notesRepository;
    if (highlightsRepository == null || notesRepository == null) {
      return const Center(
        child: Text('尚無劃線或備註', key: Key('notes_sheet_annotations_placeholder')),
      );
    }
    final items = mergeAnnotations(_highlights, _notes);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('notes_sheet_delete_all_highlights'),
                  onPressed: _highlights.isEmpty ? null : _confirmDeleteAllHighlights,
                  child: const Text('刪除所有劃線'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const Key('notes_sheet_delete_all_notes'),
                  onPressed: _notes.isEmpty ? null : _confirmDeleteAllNotes,
                  child: const Text('刪除所有備註'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text('尚無劃線或備註', key: Key('notes_sheet_annotations_placeholder')),
                )
              : ListView.builder(
                  key: const Key('notes_sheet_annotation_list'),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _buildAnnotationRow(items[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildAnnotationRow(AnnotationListItem item) {
    final highlight = item.highlight;
    final note = item.note;
    return EBFieldCard(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        key: Key('notes_sheet_annotation_${item.key}'),
        leading: Icon(
          Icons.circle,
          color: highlight != null
              ? highlightStyleColor(highlight.style,
                  tokens: Theme.of(context).extension<ElinkTokens>()!)
              : noteOnlyTint,
        ),
        title: Text(highlight != null
            ? _highlightStyleLabel(highlight.style)
            : '備註'),
        subtitle: note != null
            ? Text(note.text, maxLines: 2, overflow: TextOverflow.ellipsis)
            : null,
        onTap: () => widget.onAnnotationSelected?.call(item),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (note != null)
              IconButton(
                key: Key('notes_sheet_annotation_edit_${note.id}'),
                icon: const Icon(Icons.edit),
                tooltip: '編輯備註',
                onPressed: () => _editNoteText(note),
              ),
            IconButton(
              key: Key('notes_sheet_annotation_delete_${item.key}'),
              icon: const Icon(Icons.delete),
              tooltip: '刪除',
              onPressed: () => _deleteAnnotationItem(item),
            ),
          ],
        ),
      ),
    );
  }

  /// 供劃線清單項目顯示用的中文標籤。【審查修正】刻意不放在
  /// `reader/highlight_style.dart`（領域模型層）——`reader/` 目錄下的其他
  /// 列舉（`BookFormat`／`WritingMode`／`PdfCropMode` 等）皆不含 UI 顯示
  /// 字串，是純格式無關的領域模型；本函式是唯一消費端，收斂在這裡避免
  /// 領域模型檔案摻雜 UI 層級的字串常數。
  String _highlightStyleLabel(HighlightStyle style) {
    switch (style) {
      case HighlightStyle.highlighterYellow:
        return '螢光筆（黃）';
      case HighlightStyle.highlighterPink:
        return '螢光筆（粉）';
      case HighlightStyle.highlighterBlue:
        return '螢光筆（藍）';
      case HighlightStyle.underline:
        return '底線';
    }
  }

  Future<void> _editNoteText(Note note) async {
    final newText = await showNoteTextDialog(context, initialText: note.text, title: '編輯備註');
    if (newText == null) return;
    await widget.notesRepository!.updateText(note.id, newText);
    await _loadAnnotations();
    widget.onAnnotationsChanged?.call();
  }

  /// 單筆刪除＝整筆一起刪（spec.md 決策 #13）：不依賴 FK `ON DELETE SET
  /// NULL` 的自動退化（那是給批次刪除劃線情境用的），明確分別刪除兩張表
  /// 各自的列。
  Future<void> _deleteAnnotationItem(AnnotationListItem item) async {
    if (item.note != null) await widget.notesRepository!.delete(item.note!.id);
    if (item.highlight != null) await widget.highlightsRepository!.delete(item.highlight!.id);
    await _loadAnnotations();
    widget.onAnnotationsChanged?.call();
  }

  /// 「批次刪除全部」確認 Dialog 共用邏輯（審查修正：`_confirmDeleteAllHighlights`
  /// 與 `_confirmDeleteAllNotes` 原本各自重複同一套 `AlertDialog` 結構，僅
  /// 標籤文字、Key、實際刪除呼叫不同，收斂為單一輔助方法）。[itemLabel] 為
  /// 顯示於確認標題的項目名稱（例如「劃線」／「備註」），[count] 為顯示的
  /// 筆數，[confirmKey] 供測試辨識「刪除」按鈕，[onConfirm] 為使用者確認後
  /// 才執行的實際刪除／重新整理／通知邏輯。
  Future<void> _confirmDeleteAll({
    required String itemLabel,
    required int count,
    required Key confirmKey,
    required Future<void> Function() onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('確定要刪除全部$itemLabel嗎？（共 $count 筆）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: confirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await onConfirm();
  }

  Future<void> _confirmDeleteAllHighlights() {
    return _confirmDeleteAll(
      itemLabel: '劃線',
      count: _highlights.length,
      confirmKey: const Key('notes_sheet_delete_all_highlights_confirm'),
      onConfirm: () async {
        await widget.highlightsRepository!.deleteAllForBook(widget.bookId);
        await _loadAnnotations();
        widget.onAnnotationsChanged?.call();
      },
    );
  }

  Future<void> _confirmDeleteAllNotes() {
    return _confirmDeleteAll(
      itemLabel: '備註',
      count: _notes.length,
      confirmKey: const Key('notes_sheet_delete_all_notes_confirm'),
      onConfirm: () async {
        await widget.notesRepository!.deleteAllForBook(widget.bookId);
        await _loadAnnotations();
        widget.onAnnotationsChanged?.call();
      },
    );
  }
}
