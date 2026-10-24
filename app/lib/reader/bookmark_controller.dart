import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_localizations.dart';
import 'bookmark.dart';
import 'bookmark_position_context.dart';
import 'bookmarks_repository.dart';

/// 兩個位置是否相同（Epic 54 Issue 25，設計決策 3）：[BookmarkPositionContext]
/// 的 `pdfPageIndex` 有值時比頁碼，否則比 `epubLocatorJson` 完全相同字串；
/// 兩組欄位皆為 null（位置尚未回報）時回傳 false。
///
/// 比對規則刻意集中成頂層純函式：星號圖示（[BookmarkController.at]）與
/// 切換（[BookmarkController.toggle]）必須用同一套規則，否則會出現
/// 「顯示已加入、點擊卻新增一筆」的不一致。
bool isSameBookmarkPosition(
  Bookmark bookmark,
  BookmarkPositionContext position,
) {
  final pdfPageIndex = position.pdfPageIndex;
  if (pdfPageIndex != null) return bookmark.pdfPageIndex == pdfPageIndex;
  final epubLocatorJson = position.epubLocatorJson;
  if (epubLocatorJson != null) {
    return bookmark.epubLocatorJson == epubLocatorJson;
  }
  return false;
}

/// 本書書籤 module（Epic 54 Issue 25；詞彙見 `CONTEXT.md`「本書書籤」）：
/// 持有一本書的書籤清單，提供 [load]、[at]、[toggle]。收斂原本散在
/// `ReaderScreen`（EPUB／PDF 各一份）與 `NotesBottomSheet`（第三份）的
/// 「目前位置有沒有書籤」實作，以及 `bookmark_toggle.dart` 的切換邏輯。
///
/// 刻意不是 `ChangeNotifier`（設計決策 2）：呼叫後由呼叫端自己 `setState`，
/// 與現行流程一致。也刻意不碰 `BuildContext`——需要 `AppLocalizations` 的
/// [toggle] 由呼叫端在 `await` 前取好傳入。
class BookmarkController {
  BookmarkController({
    required BookmarksRepository repository,
    required String bookId,
  })  : _repository = repository,
        _bookId = bookId;

  final BookmarksRepository _repository;
  final String _bookId;
  List<Bookmark> _bookmarks = const [];

  /// 記憶體中的書籤清單（最近一次 [load]／[toggle] 的結果）。
  /// 只供讀取；變更請走 [load]／[toggle]。
  List<Bookmark> get bookmarks => _bookmarks;

  /// 重新讀取本書書籤清單（設計決策 8）：失敗只 `debugPrint`，清單保持舊值、
  /// 不往外丟出例外。`mounted` 檢查與 `setState` 由呼叫端負責，因此回傳
  /// `Future` 供呼叫端 `await`。
  Future<void> load() async {
    try {
      _bookmarks = await _repository.listByBook(_bookId);
    } catch (e) {
      debugPrint('Failed to load bookmarks: $e');
    }
  }

  /// 目前位置是否已有書籤，供星號圖示使用；沒有回傳 null。
  ///
  /// 只看記憶體清單（設計決策 5）：呼叫端要先 [load] 過才會有內容，因此
  /// 圖示的即時性由呼叫端的載入時機決定。切換的存在性判斷則不走這裡。
  Bookmark? at(BookmarkPositionContext position) {
    for (final bookmark in _bookmarks) {
      if (isSameBookmarkPosition(bookmark, position)) return bookmark;
    }
    return null;
  }

  /// 切換目前位置的書籤：有就刪、沒有就新增，做完自己 [load]。
  ///
  /// 存在性判斷**直查 repository**、不看 [bookmarks]（設計決策 5，Epic 26
  /// Issue 1 競態修復）：記憶體清單可能尚未載入或已過期，用它判斷會誤判
  /// 「沒有書籤」而重複新增。
  Future<void> toggle({
    required BookmarkPositionContext position,
    required AppLocalizations l10n,
  }) async {
    final all = await _repository.listByBook(_bookId);
    Bookmark? existing;
    for (final bookmark in all) {
      if (isSameBookmarkPosition(bookmark, position)) {
        existing = bookmark;
        break;
      }
    }
    if (existing != null) {
      await _repository.delete(existing.id);
    } else {
      await _repository.insert(
        Bookmark(
          id: const Uuid().v4(),
          bookId: _bookId,
          name: Bookmark.defaultName(position, l10n),
          epubLocatorJson: position.epubLocatorJson,
          progression: position.progression,
          pdfPageIndex: position.pdfPageIndex,
        ),
      );
    }
    await load();
  }
}
