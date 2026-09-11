import 'dart:io';

import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../library/models/library_enums.dart';
import '../search/full_text_search_settings_repository.dart';

/// 收斂 `LibraryScreen` 5 個批次操作（搬移分類／強制 FXL／恢復自動判斷／
/// 刪除／移除本機快取）共用的執行骨架（epic-26-architecture-hardening
/// Issue 8，候選 2＋候選 6）：原本 5 個方法各自重複「過濾選取集合中符合
/// 條件的書籍 → 逐筆呼叫 repository」這段骨架，本類別把骨架收斂為私有
/// [_runEach]，5 個公開方法只提供差異化的「單本書該做什麼」與（若需要）
/// 篩選條件。
///
/// **刻意不含**：`_selectedBookIds` 擷取、`_exitSelectionMode()`、任何
/// 需要 `BuildContext` 的確認對話框（搬移分類的目的地選擇、刪除前的確認
/// 對話框）、完成後的重新載入——這些是 UI 生命週期與導覽相關的職責，留在
/// `_LibraryScreenState`（見 `plans/plan-issue-8.md`「規劃階段查證」）。
class LibraryBatchActions {
  const LibraryBatchActions({
    required this.repository,
    this.fullTextSearchSettingsRepository,
  });

  final LibraryRepository repository;

  /// epic-10-search Issue 2（spec.md §7）：移除本機快取時一併清除搜尋
  /// 索引資料。`null` 時（例如既有測試未提供）完全略過，行為與本工單
  /// 之前完全一致。
  final FullTextSearchSettingsRepository? fullTextSearchSettingsRepository;

  Future<void> _runEach(
    Set<String> selectedIds,
    List<Book> books,
    Future<void> Function(Book book) action, {
    bool Function(Book book)? shouldInclude,
  }) async {
    for (final book in books) {
      if (!selectedIds.contains(book.id)) continue;
      if (shouldInclude != null && !shouldInclude(book)) continue;
      await action(book);
    }
  }

  /// 搬移到分類（對應原 `_moveSelectedBooksToGroup()` 迴圈本體）。
  Future<void> moveToGroup(
    Set<String> selectedIds,
    List<Book> books,
    String destination,
  ) {
    return _runEach(
      selectedIds,
      books,
      (book) => repository.updateBook(book.copyWith(groupName: destination)),
    );
  }

  /// 對選取集合中所有 EPUB 書籍手動覆寫「引擎分派判斷」結果為固定版面
  /// （FXL）——救濟部分漫畫 EPUB 因來源檔案 metadata 不完整/不規範，被
  /// 「引擎分派判斷」誤判為流式的情況（見 CONTEXT.md「人工版面覆蓋」）。
  /// 非 EPUB 書籍（PDF/TXT）自動跳過，不影響、不拋錯（對應原
  /// `_forceFixedLayoutForSelectedBooks()`）。
  Future<void> forceFixedLayout(Set<String> selectedIds, List<Book> books) {
    return _runEach(
      selectedIds,
      books,
      (book) => repository.updateBook(book.copyWith(isFixedLayout: true)),
      shouldInclude: (book) => book.format == BookFileFormat.epub,
    );
  }

  /// 對選取集合中所有 EPUB 書籍重新呼叫既有 detectAndCacheEpubLayout()，
  /// 回到系統原始的「引擎分派判斷」結果——用於復原誤按/誤判後想撤銷人工
  /// 覆蓋的情況（見 CONTEXT.md「人工版面覆蓋」）。非 EPUB 書籍自動跳過
  /// （對應原 `_restoreAutoLayoutForSelectedBooks()`）。
  Future<void> restoreAutoLayout(Set<String> selectedIds, List<Book> books) {
    return _runEach(
      selectedIds,
      books,
      (book) => repository.detectAndCacheEpubLayout(book.id, book.filePath),
      shouldInclude: (book) => book.format == BookFileFormat.epub,
    );
  }

  /// 刪除書籍：資料庫紀錄一律刪除；實體檔案／封面刪除失敗時靜默略過，不
  /// 中斷批次（對應原 `_deleteSelectedBooks()` 迴圈本體）。
  /// `existsSync()` 防護對 `content://` 來源的 `filePath` 安全（design.md
  /// 調查結論——`content://` 字串永遠不會判定為存在的本機路徑，故此處不
  /// 需要分辨 `filePath` 是本機複本還是原始外部檔案參照）；用
  /// `deleteSync()` 而非 `await delete()`——widget test 的 fake zone 無法
  /// 完成真實 I/O 的 Future，`deleteSync()` 是同步系統呼叫，可直接完成，
  /// 不受 zone 限制。
  Future<void> deleteBooks(Set<String> selectedIds, List<Book> books) {
    return _runEach(selectedIds, books, (book) async {
      await repository.deleteBook(book.id);
      try {
        if (File(book.filePath).existsSync()) {
          File(book.filePath).deleteSync();
        }
        final coverPath = book.coverPath;
        if (coverPath != null && File(coverPath).existsSync()) {
          File(coverPath).deleteSync();
        }
      } catch (_) {
        // 檔案刪除失敗時靜默略過，不中斷主流程；資料庫紀錄已刪除，殘留
        // 檔案不影響功能正確性。
      }
    });
  }

  /// 移除本機快取：對選取集合中所有 Calibre 來源且已下載的書籍，刪除實體
  /// 檔案並標記 `isDownloaded = false`。保留 epubLocator / progress /
  /// 書籤 / 劃線 / 備註等使用者資料（對應原
  /// `_removeLocalCacheForSelectedBooks()`）。
  Future<void> removeLocalCache(Set<String> selectedIds, List<Book> books) {
    return _runEach(
      selectedIds,
      books,
      (book) async {
        try {
          if (File(book.filePath).existsSync()) {
            File(book.filePath).deleteSync();
          }
        } catch (_) {
          // 檔案刪除失敗時靜默略過——資料庫標記更新才是核心操作。
        }
        await repository.updateBook(book.copyWith(isDownloaded: false));
        try {
          await fullTextSearchSettingsRepository?.clearBookIndex(book.id);
        } catch (_) {
          // 【review-plan-issue-2.md M-1】靜默略過——避免單一書籍的索引
          // 清除異常中斷整個批次迴圈，導致後面幾本書的實體檔案快取無法
          // 被刪除；索引資料為衍生性資料，維護失敗不應影響核心的快取
          // 移除操作。
        }
      },
      shouldInclude: (book) =>
          book.source == BookSource.calibreOpds && book.isDownloaded,
    );
  }
}
