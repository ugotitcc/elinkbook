import 'package:flutter/material.dart';

import '../reader/bookmark.dart';
import '../reader/bookmark_position_context.dart';
import '../reader/bookmarks_repository.dart';

/// 統一的「筆記」入口 Bottom Sheet 外殼（epic-6-annotations Issue 1，
/// spec.md「統一入口與 Bottom Sheet」）：帶「🔖 書籤」／「✏️ 劃線與備註」
/// 兩個分頁籤，兩分頁底下的資料層完全獨立（design.md 決策 #1）。本 Issue
/// 只完整實作「書籤」分頁；「劃線與備註」分頁本 Issue 僅顯示空狀態佔位符，
/// 真正內容由 Issue 2（EPUB）／Issue 3（PDF）建立。
class NotesBottomSheet extends StatefulWidget {
  final String bookId;
  final BookmarksRepository bookmarksRepository;

  /// 開啟當下的目前位置上下文，供書籤 toggle 按鈕判斷目前位置是否已有
  /// 書籤、以及新增書籤時計算預設名稱（Global Constraints「書籤 toggle
  /// 的相等性判斷」）。
  final BookmarkPositionContext currentPosition;

  /// 使用者點選某筆書籤時觸發，呼叫端負責實際跳轉並關閉本 Bottom Sheet。
  final ValueChanged<Bookmark> onBookmarkSelected;

  const NotesBottomSheet({
    super.key,
    required this.bookId,
    required this.bookmarksRepository,
    required this.currentPosition,
    required this.onBookmarkSelected,
  });

  @override
  State<NotesBottomSheet> createState() => _NotesBottomSheetState();
}

class _NotesBottomSheetState extends State<NotesBottomSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<Bookmark> _bookmarks = [];
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
    _tabController = TabController(length: 2, vsync: this);
    _loadBookmarks();
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

  @override
  Widget build(BuildContext context) {
    // TabBarView 無法在無邊界的父層自我量測高度，需要一個明確的高度值
    // （比照 PdfSettingsSheet 既有做法），但改用螢幕高度比例（審查修正，
    // 見 tmp/epic-6/reviews/plan_issue_1_review.md 2.1）而非寫死常數，
    // 避免在較矮螢幕（例如部分 E-Ink 裝置）或系統字型放大時溢出；
    // clamp 上下限避免極端螢幕尺寸下過小或過大。此為 NotesBottomSheet
    // 這個全新元件的初始選擇，不回頭修改 PdfSettingsSheet 既有的固定
    // 400，避免超出本工單範圍。
    final sheetHeight =
        (MediaQuery.of(context).size.height * 0.6).clamp(320.0, 600.0);
    return SafeArea(
      child: SizedBox(
        height: sheetHeight,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child:
                  Text('📚 筆記', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(key: Key('notes_sheet_tab_bookmarks'), text: '🔖 書籤'),
                Tab(key: Key('notes_sheet_tab_annotations'), text: '✏️ 劃線與備註'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBookmarksTab(),
                  const Center(
                    child: Text(
                      '尚無劃線或備註',
                      key: Key('notes_sheet_annotations_placeholder'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
      await widget.bookmarksRepository.delete(existing.id!);
    } else {
      await widget.bookmarksRepository.insert(Bookmark(
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
    await widget.bookmarksRepository.rename(bookmark.id!, newName.trim());
    await _loadBookmarks();
  }

  Future<void> _deleteBookmark(Bookmark bookmark) async {
    await widget.bookmarksRepository.delete(bookmark.id!);
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
    return ListTile(
      key: Key('notes_sheet_bookmark_${bookmark.id}'),
      title: Text(bookmark.name),
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
    );
  }
}
