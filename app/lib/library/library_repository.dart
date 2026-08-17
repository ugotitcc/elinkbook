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

  /// 只列出流式（非 FXL）EPUB 書籍（epic-28-reader-settings-enhancements
  /// Issue 3「書籍選擇器過濾與效能」），供版面設定預設集／書籍設定複製
  /// 的書籍選擇器使用——PDF/FXL/TXT 欄位語意不共通，排除避免誤選。
  /// [excludeBookId] 用於「複製其他書籍」流程排除來源書本身。依
  /// `title ASC` 排序。
  Future<List<Book>> listReflowableEpubBooks({String? excludeBookId});

  /// 依 `(remoteServerId, remoteBookId)` 精確比對，供遠端書架選檔前置
  /// 重複匯入偵測使用（`epic-30-calibre-remote-library`，spec.md「重複
  /// 匯入偵測」）。命中回傳該本書，未命中回傳 `null`。
  Future<Book?> findByRemoteBookId(String serverId, String remoteBookId);

  /// 依 `content_fingerprint` 精確比對，供雲端/遠端書架匯入的下載後重複
  /// 匯入偵測使用（`epic-29-cloud-import`／`epic-30-calibre-remote-library`
  /// 共用，見 `CONTEXT.md`「書籍內容指紋」）。命中回傳該本書，未命中回傳
  /// `null`。
  Future<Book?> findByContentFingerprint(String fingerprint);

  /// 供遠端書庫刪除站點前的示警防護使用（epic-30-calibre-remote-library
  /// Issue 1，spec.md「站點管理」）：回傳指定站點中「僅雲端紀錄、無本機
  /// 檔案」（`isDownloaded == false`）的書籍清單。`RemoteServerRepository`
  /// 透過這個方法間接查詢，維持「`books`／`groups` 兩張表唯一存取入口」
  /// 的既有邊界（見本類別文件），不直接對 `books` 表下 SQL。
  Future<List<Book>> listUndownloadedBooksForRemoteServer(String serverId);
}

/// `LibraryRepository` 操作違反資料規則時拋出（例如嘗試刪除/重新命名系統
/// 保留的「未分類」群組、或重新命名為已存在的群組名稱）。
class LibraryRepositoryException implements Exception {
  final String message;
  const LibraryRepositoryException(this.message);

  @override
  String toString() => 'LibraryRepositoryException: $message';
}
