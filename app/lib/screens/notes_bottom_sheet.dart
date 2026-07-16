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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBookmarks();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
    return ListView.builder(
      key: const Key('notes_sheet_bookmark_list'),
      itemCount: _bookmarks.length,
      itemBuilder: (context, index) => _buildBookmarkRow(_bookmarks[index]),
    );
  }

  Widget _buildBookmarkRow(Bookmark bookmark) {
    return ListTile(
      key: Key('notes_sheet_bookmark_${bookmark.id}'),
      title: Text(bookmark.name),
      onTap: () => widget.onBookmarkSelected(bookmark),
    );
  }
}
