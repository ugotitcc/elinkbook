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

  /// 供既有書籍（`isFixedLayout == null`）一次性補判斷 EPUB 是否為固定版面
  /// （FXL），呼叫原生端 `detectEpubLayout` method channel 後寫回 [bookId]
  /// 對應資料列的 `is_fixed_layout` 欄位，回傳判斷結果（見
  /// docs/epics/epic-17-epub-render-migration/spec.md「既有書籍回填流程」）。
  /// `ReaderScreen`（Issue 3）建構閱讀器 widget 之前呼叫。
  Future<bool> detectAndCacheEpubLayout(String bookId, String filePath);
}

/// `LibraryRepository` 操作違反資料規則時拋出（例如嘗試刪除/重新命名系統
/// 保留的「未分類」群組、或重新命名為已存在的群組名稱）。
class LibraryRepositoryException implements Exception {
  final String message;
  const LibraryRepositoryException(this.message);

  @override
  String toString() => 'LibraryRepositoryException: $message';
}
