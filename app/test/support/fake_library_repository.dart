import 'package:elinkbook/library/library_repository.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';

/// 供 widget test 使用的記憶體內 [LibraryRepository] 假實作，避免 widget
/// test 依賴真實 sqflite（見 docs/epics/epic-1-library/spec.md「測試決策」）。
class FakeLibraryRepository implements LibraryRepository {
  FakeLibraryRepository({
    List<Book> initialBooks = const [],
    this.throwOnListBooks = false,
  }) : _books = List.of(initialBooks);

  final bool throwOnListBooks;
  final List<Book> _books;

  @override
  Future<Book> insertBook(Book book) async {
    _books.add(book);
    return book;
  }

  @override
  Future<void> updateBook(Book book) async {
    final index = _books.indexWhere((b) => b.id == book.id);
    if (index != -1) _books[index] = book;
  }

  @override
  Future<void> deleteBook(String id) async {
    _books.removeWhere((b) => b.id == id);
  }

  @override
  Future<List<Book>> listBooks({
    LibrarySortBy sortBy = LibrarySortBy.lastRead,
    String? groupFilter,
  }) async {
    if (throwOnListBooks) {
      throw Exception('模擬資料庫錯誤');
    }
    final filtered = groupFilter == null
        ? List.of(_books)
        : _books.where((b) => b.groupName == groupFilter).toList();
    filtered.sort(_comparatorFor(sortBy));
    return filtered;
  }

  int Function(Book, Book) _comparatorFor(LibrarySortBy sortBy) {
    switch (sortBy) {
      case LibrarySortBy.lastRead:
        return (a, b) => b.lastReadTime.compareTo(a.lastReadTime);
      case LibrarySortBy.createTime:
        return (a, b) => b.createTime.compareTo(a.createTime);
      case LibrarySortBy.author:
        return (a, b) => (a.author ?? '').compareTo(b.author ?? '');
      case LibrarySortBy.title:
        return (a, b) => a.title.compareTo(b.title);
    }
  }

  @override
  Future<List<BookGroup>> listGroups() async =>
      const [BookGroup(BookGroup.uncategorized)];

  @override
  Future<void> upsertGroup(String name) async {}

  @override
  Future<void> renameGroup(String oldName, String newName) async {}

  @override
  Future<void> deleteGroup(String name) async {}
}
