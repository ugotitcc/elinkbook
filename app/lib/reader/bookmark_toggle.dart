import 'bookmark.dart';
import 'bookmarks_repository.dart';

/// 收斂 EPUB／PDF 書籤 toggle 成一個共用 module（Epic 26 Issue 1）：兩者
/// 原本各自實作幾乎相同的「查 repository → 比對目前位置是否已有書籤 →
/// insert/delete」演算法，PDF 端已修過的「存在性判斷直查 repository、
/// 不依賴呼叫端記憶體快取」競態修復從未傳到 EPUB 端——EPUB 端原本用
/// 可能尚未載入的 `_fxlBookmarks` 快取判斷，開書後在使用者尚未打開過
/// 筆記面板前第一次點擊書籤按鈕會誤判無書籤而重複新增（見
/// `reviews/bugfix-repro.md`）。呼叫端各自傳入比對邏輯（[matches]：EPUB
/// 用 `epubLocatorJson`、PDF 用 `pdfPageIndex`）與建構邏輯（[build]），
/// 存在性判斷一律直查 [repository]，不依賴呼叫端任何快取是否已載入。
Future<void> toggleBookmark({
  required BookmarksRepository repository,
  required String bookId,
  required bool Function(Bookmark bookmark) matches,
  required Bookmark Function() build,
}) async {
  final all = await repository.listByBook(bookId);
  Bookmark? existing;
  for (final bookmark in all) {
    if (matches(bookmark)) {
      existing = bookmark;
      break;
    }
  }
  if (existing != null) {
    await repository.delete(existing.id);
  } else {
    await repository.insert(build());
  }
}
