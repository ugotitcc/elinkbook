import 'package:flutter/material.dart';

import '../library/models/book.dart';
import '../library/widgets/book_cover.dart';
import '../l10n/app_localizations.dart';
import '../theme/elink_tokens.dart';

/// 版面設定預設集／書籍設定複製的書籍選擇器（epic-28-reader-settings-
/// enhancements Issue 3「UI 元件責任劃分」`onRequestBookPicker`；格線化＋
/// 統一確認機制見 Issue 6），純展示 widget，不做任何 Repository I/O——
/// [books] 由呼叫端（`ReaderScreen`，已透過
/// `LibraryRepository.listReflowableEpubBooks()` 過濾為僅流式 EPUB）傳入。
/// [multiSelect] 為 `false` 時單選（Radio 語意，同時最多選 1 格）、`true`
/// 時可複選（Checkbox 語意）；兩者皆須點擊 AppBar「確定」按鈕（未選取任何
/// 項目時停用）才會關閉畫面並回傳已選取 id 清單。使用者未點擊「確定」、
/// 直接以返回鍵/系統手勢離開畫面時，一律回傳 `null`——這是既有呼叫端
/// （`reader_settings_sheet.dart` 的 4 處 `onRequestBookPicker` 呼叫）依賴
/// 的既有契約，不可破壞。
class LayoutPresetBookPickerScreen extends StatefulWidget {
  final List<Book> books;
  final bool multiSelect;

  const LayoutPresetBookPickerScreen({
    super.key,
    required this.books,
    required this.multiSelect,
  });

  @override
  State<LayoutPresetBookPickerScreen> createState() =>
      _LayoutPresetBookPickerScreenState();
}

class _LayoutPresetBookPickerScreenState
    extends State<LayoutPresetBookPickerScreen> {
  final Set<String> _selected = {};
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Book> get _filteredBooks {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return widget.books;
    return widget.books.where((book) {
      if (book.title.toLowerCase().contains(query)) return true;
      final author = book.author;
      return author != null && author.toLowerCase().contains(query);
    }).toList();
  }

  void _handleItemTap(Book book) {
    setState(() {
      if (widget.multiSelect) {
        if (_selected.contains(book.id)) {
          _selected.remove(book.id);
        } else {
          _selected.add(book.id);
        }
      } else {
        // Radio 語意：單選模式下每次點擊一律清空既有選取，只保留剛點擊的
        // 這一格，不支援「再點一次取消選取」。
        _selected
          ..clear()
          ..add(book.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final filteredBooks = _filteredBooks;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.multiSelect
              ? l10n.layoutPresetBookPickerTitleMulti
              : l10n.layoutPresetBookPickerTitleSingle,
        ),
        actions: [
          TextButton(
            key: const Key('layout_preset_book_picker_confirm'),
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected.toList()),
            child: Text(l10n.confirm),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              key: const Key('layout_preset_book_picker_search_field'),
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.layoutPresetBookPickerSearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        key: const Key(
                            'layout_preset_book_picker_search_clear'),
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: widget.books.isEmpty
                ? Center(child: Text(l10n.layoutPresetBookPickerEmptyBooks))
                : filteredBooks.isEmpty
                    ? Center(child: Text(l10n.layoutPresetBookPickerNoMatch))
                    : _buildGrid(filteredBooks),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<Book> books) {
    final orientation = MediaQuery.orientationOf(context);
    final crossAxisCount = orientation == Orientation.landscape ? 4 : 3;
    return GridView.builder(
      key: const Key('layout_preset_book_picker_grid'),
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.62,
        crossAxisSpacing: 8,
        mainAxisSpacing: 12,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        return _BookGridItem(
          book: book,
          selected: _selected.contains(book.id),
          onTap: () => _handleItemTap(book),
        );
      },
    );
  }
}

/// 書籍格：封面圖＋書名＋右上角選取指示圖示。單選/複選共用同一套視覺
/// （`check_circle`／`radio_button_unchecked`＋半透明黑底圓圈確保任何封面
/// 底色下都有足夠對比度），比照 `LibraryScreen._BookGridTile` 既有的選取
/// 指示視覺語言。
class _BookGridItem extends StatelessWidget {
  final Book book;
  final bool selected;
  final VoidCallback onTap;

  const _BookGridItem({
    required this.book,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    return InkWell(
      key: Key('layout_preset_book_picker_item_${book.id}'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                BookCover(book: book),
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: tokens.badgeScrim,
                        shape: BoxShape.circle,
                      ),
                      // 未選取狀態圖示前景維持寫死白色，理由同
                      // book_cover.dart 雲朵徽章（見本計劃「範圍決定」）。
                      child: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        key: Key(
                            'layout_preset_book_picker_item_${book.id}_selected'),
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
