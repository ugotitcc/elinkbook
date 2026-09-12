// app/lib/screens/book_search_screen.dart
import 'package:flutter/material.dart';

import '../library/models/book.dart';
import '../reader/reader_prefs_manager.dart';
import '../library/library_repository.dart';
import '../search/search_repository.dart';
import 'library_screen_dependencies.dart';

/// 單書全文檢索畫面（epic-10-search Issue 7，spec.md §9.3）。
/// Task 2 只建立最小 stub 供 LibrarySearchScreen drill-down 測試通過；
/// Task 3 完整實作。
class BookSearchScreen extends StatefulWidget {
  final Book book;
  final String initialQuery;
  final SearchRepository searchRepository;
  final ReaderPrefsManager prefsManager;
  final LibraryRepository libraryRepository;
  final LibraryReaderFeatureRepositories readerFeatureRepositories;
  final LibrarySyncDependencies syncDependencies;
  final bool isEinkMode;

  /// `true` 時代表從閱讀器開啟（Issue 8 接線），點選片段 pop 回傳
  /// `ReaderJumpTarget`；`false`（預設）時從全庫搜尋推入，點選片段
  /// 推入 `ReaderScreen`。
  final bool fromReader;

  const BookSearchScreen({
    super.key,
    required this.book,
    this.initialQuery = '',
    required this.searchRepository,
    required this.prefsManager,
    required this.libraryRepository,
    this.readerFeatureRepositories = const LibraryReaderFeatureRepositories(),
    this.syncDependencies = const LibrarySyncDependencies(),
    this.isEinkMode = false,
    this.fromReader = false,
  });

  @override
  State<BookSearchScreen> createState() => _BookSearchScreenState();
}

class _BookSearchScreenState extends State<BookSearchScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.book.title)),
      body: const Center(child: Text('BookSearchScreen stub')),
    );
  }
}
