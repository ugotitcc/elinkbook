import 'dart:io';

import 'package:flutter/material.dart';

import '../library/models/book.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.multiSelect ? '選擇書籍（可複選）' : '選擇書籍'),
        actions: [
          TextButton(
            key: const Key('layout_preset_book_picker_confirm'),
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected.toList()),
            child: const Text('確定'),
          ),
        ],
      ),
      body: widget.books.isEmpty
          ? const Center(child: Text('沒有可選擇的流式 EPUB 書籍'))
          : _buildGrid(widget.books),
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
/// 指示視覺語言（`app/lib/screens/library_screen.dart`）——因跨檔案無法
/// import 私有 class，本畫面就地實作一份精簡版，只保留封面容錯＋選取圖示，
/// 省略 `LibraryScreen` 特有的進度百分比／長按批次選取等本畫面用不到的
/// 邏輯（見 `plan-issue-6.md` Architecture「設計決策」）。
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
                _BookCover(book: book),
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
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

/// 書籍封面：有 `coverPath` 且檔案存在時顯示圖片，否則以通用書本圖示佔位。
/// 本畫面書籍恆為流式 EPUB（呼叫端已用
/// `LibraryRepository.listReflowableEpubBooks()` 過濾），不需要
/// `LibraryScreen._BookCover` 依 `book.format` 選格式專屬圖示的完整邏輯。
class _BookCover extends StatelessWidget {
  final Book book;
  const _BookCover({required this.book});

  @override
  Widget build(BuildContext context) {
    final coverPath = book.coverPath;
    if (coverPath != null && File(coverPath).existsSync()) {
      return Image.file(File(coverPath), fit: BoxFit.cover);
    }
    return const ColoredBox(
      color: Color(0xFFE0E0E0),
      child: Center(child: Icon(Icons.menu_book, size: 32)),
    );
  }
}
