import 'package:flutter/services.dart';

import 'models/book.dart';
import 'models/book_group.dart';
import 'models/library_enums.dart';

/// 原生端 `BookMetadataChannel` 對應的 MethodChannel 名稱，
/// 供 Dart 側所有需要呼叫原生書籍中繼資料的檔案共用。
const kBookMetadataChannel = MethodChannel('elinkbook/book_metadata');

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

  /// 回傳所有**流式 EPUB** 書籍（排除 PDF 與 `isFixedLayout == true` 的
  /// FXL EPUB），供版面設定預設集套用的書籍選擇器（Issue 3
  /// `LayoutPresetBookPickerScreen`）使用。排序固定 `title ASC`（依書名
  /// 筆畫排序），方便使用者快速定位目標書籍。
  Future<List<Book>> listReflowableEpubBooks();
}

/// `LibraryRepository` 操作違反資料規則時拋出（例如嘗試刪除/重新命名系統
/// 保留的「未分類」群組、或重新命名為已存在的群組名稱）。
class LibraryRepositoryException implements Exception {
  final String message;
  const LibraryRepositoryException(this.message);

  @override
  String toString() => 'LibraryRepositoryException: $message';
}
