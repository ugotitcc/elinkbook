import 'models/book.dart';
import 'models/book_group.dart';
import 'models/library_enums.dart';

/// 圖書庫資料的存取介面；`books`/`groups` 兩張表的唯一存取入口（見
/// docs/epics/epic-1-library/spec.md「介面」章節）。
abstract class LibraryRepository {
  Future<Book> insertBook(Book book);
  Future<void> updateBook(Book book);
  Future<void> deleteBook(String id);
  Future<List<Book>> listBooks({
    LibrarySortBy sortBy = LibrarySortBy.lastRead,
    String? groupFilter,
  });

  Future<List<BookGroup>> listGroups();
  Future<void> upsertGroup(String name);
  Future<void> renameGroup(String oldName, String newName);
  Future<void> deleteGroup(String name);
}

/// `LibraryRepository` 操作違反資料規則時拋出（例如嘗試刪除/重新命名系統
/// 保留的「未分類」群組、或重新命名為已存在的群組名稱）。
class LibraryRepositoryException implements Exception {
  final String message;
  const LibraryRepositoryException(this.message);

  @override
  String toString() => 'LibraryRepositoryException: $message';
}
