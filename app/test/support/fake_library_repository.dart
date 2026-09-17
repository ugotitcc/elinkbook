import 'package:elinkbook/library/library_repository.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';

/// 供 widget test 使用的記憶體內 [LibraryRepository] 假實作，避免 widget
/// test 依賴真實 sqflite（見 docs/epics/epic-1-library/spec.md「測試決策」）。
/// 群組 CRUD 的業務規則（保護「未分類」、拒絕重複名稱、刪除時書籍歸位）
/// 與 `SqliteLibraryRepository`（Issue 1）語意一致，供 Issue 7 的分類群組
/// 管理 widget test 驅動真實可觀察的行為。
class FakeLibraryRepository implements LibraryRepository {
  FakeLibraryRepository({
    List<Book> initialBooks = const [],
    this.throwOnListBooks = false,
    this.detectedIsFixedLayout = false,
  })  : _books = List.of(initialBooks),
        _groups = {
          BookGroup.uncategorized,
          for (final book in initialBooks) book.groupName,
        };

  final bool throwOnListBooks;

  /// 供測試模擬 [findByRemoteBookId] 拋出例外（例如暫時性 SQLite 錯誤），
  /// 驗證呼叫端的錯誤處理（epic-30-calibre-remote-library Issue 3，
  /// `reviews/review-issue-3.md` Important 採納）。刻意為可變欄位、非
  /// [throwOnListBooks] 那樣的建構參數——呼叫端透過 cascade（`..`）在
  /// 建構後才設定，用法比照 `test/support/fake_remote_server_repository.dart`
  /// 的 `deleteServerError`／`saveServerError` 既有慣例。
  bool throwOnFindByRemoteBookId = false;

  /// 供測試模擬 [findByCloudFileId] 拋出例外，驗證呼叫端的錯誤處理（比照
  /// 上方 [throwOnFindByRemoteBookId] 既有慣例，epic-29-cloud-import
  /// Issue 5）。
  bool throwOnFindByCloudFileId = false;

  /// 供測試控制 [detectAndCacheEpubLayout] 的模擬回傳值（比照本檔案「假
  /// 實作」定位——真實的 method channel 呼叫只發生在
  /// `SqliteLibraryRepository`，這裡不觸及任何原生端）。
  final bool detectedIsFixedLayout;

  /// 記錄每次 [detectAndCacheEpubLayout] 呼叫的 bookId，供測試驗證呼叫
  /// 次數/對象（例如驗證「只在 isFixedLayout == null 時才觸發」）。
  final List<String> detectAndCacheEpubLayoutCalls = [];

  final List<Book> _books;
  final Set<String> _groups;

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

  /// 記錄每次 [deleteBook] 呼叫的 id，供測試驗證「每個已選取 id 各被呼叫
  /// 一次」（epic-19 Issue 2，比照既有 detectAndCacheEpubLayoutCalls 的
  /// 呼叫紀錄慣例）。
  final List<String> deleteBookCalls = [];

  @override
  Future<void> deleteBook(String id) async {
    deleteBookCalls.add(id);
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
  Future<List<BookGroup>> listGroups() async {
    final names = _groups.toList()..sort();
    return names.map(BookGroup.new).toList();
  }

  @override
  Future<void> upsertGroup(String name) async {
    _groups.add(name);
  }

  @override
  Future<void> renameGroup(String oldName, String newName) async {
    if (oldName == BookGroup.uncategorized) {
      throw LibraryRepositoryException(
          '系統保留群組「${BookGroup.uncategorized}」不可重新命名');
    }
    if (_groups.contains(newName)) {
      throw LibraryRepositoryException('分類「$newName」已存在');
    }
    _groups
      ..remove(oldName)
      ..add(newName);
    for (var i = 0; i < _books.length; i++) {
      if (_books[i].groupName == oldName) {
        _books[i] = _withGroupName(_books[i], newName);
      }
    }
  }

  @override
  Future<void> deleteGroup(String name) async {
    if (name == BookGroup.uncategorized) {
      throw LibraryRepositoryException(
          '系統保留群組「${BookGroup.uncategorized}」不可刪除');
    }
    _groups.remove(name);
    for (var i = 0; i < _books.length; i++) {
      if (_books[i].groupName == name) {
        _books[i] = _withGroupName(_books[i], BookGroup.uncategorized);
      }
    }
  }

  @override
  Future<bool> detectAndCacheEpubLayout(String bookId, String filePath) async {
    detectAndCacheEpubLayoutCalls.add(bookId);
    final index = _books.indexWhere((b) => b.id == bookId);
    if (index != -1) {
      _books[index] =
          _books[index].copyWith(isFixedLayout: detectedIsFixedLayout);
    }
    return detectedIsFixedLayout;
  }

  @override
  Future<List<Book>> listReflowableEpubBooks({String? excludeBookId}) async {
    final filtered = _books.where((b) {
      if (excludeBookId != null && b.id == excludeBookId) return false;
      if (!b.filePath.toLowerCase().endsWith('.epub')) return false;
      return b.isFixedLayout != true;
    }).toList();
    filtered.sort((a, b) => a.title.compareTo(b.title));
    return filtered;
  }

  @override
  Future<Book?> findByRemoteBookId(String serverId, String remoteBookId) async {
    if (throwOnFindByRemoteBookId) {
      throw Exception('模擬 findByRemoteBookId 查詢失敗');
    }
    for (final book in _books) {
      if (book.remoteServerId == serverId && book.remoteBookId == remoteBookId) {
        return book;
      }
    }
    return null;
  }

  @override
  Future<Book?> findByContentFingerprint(String fingerprint) async {
    for (final book in _books) {
      if (book.contentFingerprint == fingerprint) return book;
    }
    return null;
  }

  @override
  Future<Book?> findByCloudFileId(BookSource provider, String cloudFileId) async {
    if (throwOnFindByCloudFileId) {
      throw Exception('模擬 findByCloudFileId 查詢失敗');
    }
    for (final book in _books) {
      if (book.source == provider && book.cloudFileId == cloudFileId) {
        return book;
      }
    }
    return null;
  }

  @override
  Future<List<Book>> listUndownloadedBooksForRemoteServer(String serverId) async {
    return _books
        .where((b) => b.remoteServerId == serverId && !b.isDownloaded)
        .toList();
  }

  @override
  Future<Book?> findBookById(String id) async {
    for (final book in _books) {
      if (book.id == id) return book;
    }
    return null;
  }

  Book _withGroupName(Book book, String groupName) => Book(
        id: book.id,
        title: book.title,
        author: book.author,
        format: book.format,
        filePath: book.filePath,
        source: book.source,
        coverPath: book.coverPath,
        progress: book.progress,
        epubLocator: book.epubLocator,
        pdfPageIndex: book.pdfPageIndex,
        isFixedLayout: book.isFixedLayout,
        contentFingerprint: book.contentFingerprint,
        positionUpdatedAt: book.positionUpdatedAt,
        positionSyncedServerUpdatedAt: book.positionSyncedServerUpdatedAt,
        remoteServerId: book.remoteServerId,
        remoteBookId: book.remoteBookId,
        remoteDownloadUrl: book.remoteDownloadUrl,
        isDownloaded: book.isDownloaded,
        cloudFileId: book.cloudFileId,
        groupName: groupName,
        createTime: book.createTime,
        lastReadTime: book.lastReadTime,
      );
}
