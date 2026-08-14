import 'package:flutter/material.dart';

import '../library/models/book.dart';

/// 版面設定預設集／書籍設定複製的書籍選擇器（epic-28-reader-settings-
/// enhancements Issue 3「UI 元件責任劃分」`onRequestBookPicker`），純
/// 展示 widget，不做任何 Repository I/O——[books] 由呼叫端
/// （`ReaderScreen`，已透過 `LibraryRepository.listReflowableEpubBooks()`
/// 過濾為僅流式 EPUB）傳入。[multiSelect] 為 `false` 時單選、點擊項目
/// 立即以 `[book.id]` 關閉畫面；為 `true` 時可複選，AppBar「確定」按鈕
/// （至少選取 1 本才啟用）關閉畫面並回傳已選取 id 清單。使用者直接返回
/// （無選取）時回傳 `null`。
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.multiSelect ? '選擇書籍（可複選）' : '選擇書籍'),
        actions: widget.multiSelect
            ? [
                TextButton(
                  key: const Key('layout_preset_book_picker_confirm'),
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_selected.toList()),
                  child: const Text('確定'),
                ),
              ]
            : null,
      ),
      body: widget.books.isEmpty
          ? const Center(child: Text('沒有可選擇的流式 EPUB 書籍'))
          : ListView.builder(
              itemCount: widget.books.length,
              itemBuilder: (context, index) {
                final book = widget.books[index];
                if (widget.multiSelect) {
                  return CheckboxListTile(
                    key: Key('layout_preset_book_picker_item_${book.id}'),
                    title: Text(book.title),
                    subtitle: book.author == null ? null : Text(book.author!),
                    value: _selected.contains(book.id),
                    onChanged: (checked) => setState(() {
                      if (checked ?? false) {
                        _selected.add(book.id);
                      } else {
                        _selected.remove(book.id);
                      }
                    }),
                  );
                }
                return ListTile(
                  key: Key('layout_preset_book_picker_item_${book.id}'),
                  title: Text(book.title),
                  subtitle: book.author == null ? null : Text(book.author!),
                  onTap: () => Navigator.of(context).pop([book.id]),
                );
              },
            ),
    );
  }
}
