import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../library/book_import_service.dart';
import '../library/library_repository.dart';
import '../library/models/book.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

/// 圖書庫主畫面：讀取 [LibraryRepository] 的真實資料，取代
/// epic-0-skeleton 遺留的固定範例書籍清單佔位版本（見
/// docs/epics/epic-1-library/spec.md）。書架/列表雙重呈現與書籍卡片渲染由
/// Issue 5 Task 2 補上；本檔案先建立資料載入、空清單狀態與匯入動作骨架。
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
    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        return ListTile(
          key: Key('book_item_${book.id}'),
          title: Text(book.title),
          subtitle: Text(book.author ?? ''),
          onTap: () => _openBook(book),
        );
      },
    );
  }
}
