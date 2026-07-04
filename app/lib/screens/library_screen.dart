import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../library/models/library_enums.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

/// 圖書庫主畫面：讀取 [LibraryRepository] 的真實資料，取代
/// epic-0-skeleton 遺留的固定範例書籍清單佔位版本（見
/// docs/epics/epic-1-library/spec.md）。
class LibraryScreen extends StatefulWidget {
  final LibraryRepository repository;
  final BookImportService importService;

  const LibraryScreen({
    super.key,
    required this.repository,
    required this.importService,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Book>? _books;
  LibraryViewMode _viewMode = LibraryViewMode.grid;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    try {
      final books = await widget.repository.listBooks();
      if (!mounted) return;
      setState(() => _books = books);
    } catch (_) {
      // 如果載入失敗，把它當作空列表，顯示既有的空狀態 UI
      if (!mounted) return;
      setState(() => _books = []);
    }
  }

  Future<void> _pickAndImportFiles() async {
    try {
      final picked = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['epub', 'pdf', 'txt'],
      );
      if (picked == null || picked.files.isEmpty) return;
      final uris =
          picked.files.map((f) => f.identifier).whereType<String>().toList();
      if (uris.isEmpty) return;
      await widget.importService.importFiles(uris);
      await _loadBooks();
    } catch (_) {
      // 匯入失敗時靜默吞掉，避免異常傳播破壞 widget 樹或留下不一致狀態
    }
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == LibraryViewMode.grid
          ? LibraryViewMode.list
          : LibraryViewMode.grid;
    });
  }

  void _openBook(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(filePath: book.filePath)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    return Scaffold(
      appBar: AppBar(
        title: const Text('書架'),
        actions: [
          IconButton(
            key: const Key('library_view_mode_toggle'),
            icon: Icon(
              _viewMode == LibraryViewMode.grid
                  ? Icons.view_list
                  : Icons.grid_view,
            ),
            tooltip: _viewMode == LibraryViewMode.grid ? '切換為列表' : '切換為書架',
            onPressed: books == null ? null : _toggleViewMode,
          ),
          IconButton(
            key: const Key('library_import_button'),
            icon: const Icon(Icons.add),
            tooltip: '匯入書籍',
            onPressed: _pickAndImportFiles,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '設定',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: books == null
          ? const Center(child: CircularProgressIndicator())
          : books.isEmpty
              ? _buildEmptyState()
              : _buildBookList(books),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('尚未匯入書籍'),
          const SizedBox(height: 12),
          ElevatedButton(
            key: const Key('library_empty_import_button'),
            onPressed: _pickAndImportFiles,
            child: const Text('匯入書籍'),
          ),
        ],
      ),
    );
  }

  Widget _buildBookList(List<Book> books) {
    if (_viewMode == LibraryViewMode.grid) {
      return GridView.builder(
        key: const Key('library_grid_view'),
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          childAspectRatio: 0.62,
        ),
        itemCount: books.length,
        itemBuilder: (context, index) => _BookGridTile(
          book: books[index],
          onTap: () => _openBook(books[index]),
        ),
      );
    }
    return ListView.builder(
      key: const Key('library_list_view'),
      itemCount: books.length,
      itemBuilder: (context, index) => _BookListTile(
        book: books[index],
        onTap: () => _openBook(books[index]),
      ),
    );
  }
}

IconData _formatIcon(BookFileFormat format) {
  switch (format) {
    case BookFileFormat.epub:
      return Icons.menu_book;
    case BookFileFormat.pdf:
      return Icons.picture_as_pdf;
    case BookFileFormat.txt:
      return Icons.article;
  }
}

IconData _sourceIcon(BookSource source) {
  switch (source) {
    case BookSource.local:
      return Icons.smartphone;
    case BookSource.googleDrive:
      return Icons.cloud;
    case BookSource.oneDrive:
      return Icons.cloud_outlined;
  }
}

String _progressText(Book book) => '${(book.progress * 100).round()}%';

/// 書籍封面：有 `coverPath` 且檔案存在時顯示圖片，否則以格式圖示佔位。
/// `existsSync()` 只是一次本機 stat 呼叫，成本低，不需要 FutureBuilder。
class _BookCover extends StatelessWidget {
  final Book book;
  const _BookCover({required this.book});

  @override
  Widget build(BuildContext context) {
    final coverPath = book.coverPath;
    if (coverPath != null && File(coverPath).existsSync()) {
      return Image.file(File(coverPath), fit: BoxFit.cover);
    }
    return ColoredBox(
      color: Colors.grey.shade300,
      child: Center(child: Icon(_formatIcon(book.format), size: 32)),
    );
  }
}

class _BookGridTile extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  const _BookGridTile({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('book_item_${book.id}'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _BookCover(book: book)),
          const SizedBox(height: 4),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            _progressText(book),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _BookListTile extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  const _BookListTile({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('book_item_${book.id}'),
      leading: SizedBox(
        width: 48,
        height: 64,
        child: _BookCover(book: book),
      ),
      title: Text(book.title),
      subtitle: Text(book.author ?? ''),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_sourceIcon(book.source), size: 16),
          Text(_progressText(book), style: const TextStyle(fontSize: 10)),
        ],
      ),
      onTap: onTap,
    );
  }
}
