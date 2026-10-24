import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmark_controller.dart';
import 'package:elinkbook/reader/bookmark_position_context.dart';
import 'package:elinkbook/reader/bookmarks_repository.dart';
import '../support/fake_bookmarks_repository.dart';

/// [load] 失敗案例用：可切換成「查詢時丟例外」的 repository，
/// 其餘操作照常轉給 [FakeBookmarksRepository]。
class _FlakyBookmarksRepository implements BookmarksRepository {
  final FakeBookmarksRepository _inner = FakeBookmarksRepository();

  bool failListByBook = false;

  @override
  Future<void> insert(Bookmark bookmark) => _inner.insert(bookmark);

  @override
  Future<List<Bookmark>> listByBook(String bookId) {
    if (failListByBook) throw StateError('查詢失敗');
    return _inner.listByBook(bookId);
  }

  @override
  Future<void> rename(String id, String newName) => _inner.rename(id, newName);

  @override
  Future<void> delete(String id) => _inner.delete(id);

  @override
  Future<void> deleteAllForBook(String bookId) =>
      _inner.deleteAllForBook(bookId);
}

void main() {
  // defaultName 依介面語言輸出；純 Dart 單元測試沒有 BuildContext，
  // 以 lookupAppLocalizations() 取得（比照 bookmark_test）。
  final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));

  Bookmark epubBookmark({
    String id = 'bm1',
    String bookId = 'b1',
    String? locatorJson = 'loc-a',
    double? progression,
  }) {
    return Bookmark(
      id: id,
      bookId: bookId,
      name: '書籤 $id',
      epubLocatorJson: locatorJson,
      progression: progression,
    );
  }

  group('isSameBookmarkPosition', () {
    test('PDF：頁碼相同回傳 true', () {
      const bookmark = Bookmark(
        id: 'bm1',
        bookId: 'b1',
        name: '第 1 頁',
        pdfPageIndex: 0,
      );

      expect(
        isSameBookmarkPosition(
          bookmark,
          const BookmarkPositionContext(pdfPageIndex: 0),
        ),
        isTrue,
      );
    });

    test('PDF：頁碼不同回傳 false', () {
      const bookmark = Bookmark(
        id: 'bm1',
        bookId: 'b1',
        name: '第 1 頁',
        pdfPageIndex: 0,
      );

      expect(
        isSameBookmarkPosition(
          bookmark,
          const BookmarkPositionContext(pdfPageIndex: 1),
        ),
        isFalse,
      );
    });

    test('EPUB：locator 字串相同回傳 true', () {
      expect(
        isSameBookmarkPosition(
          epubBookmark(locatorJson: 'loc-a'),
          const BookmarkPositionContext(epubLocatorJson: 'loc-a'),
        ),
        isTrue,
      );
    });

    test('EPUB：locator 字串不同回傳 false', () {
      expect(
        isSameBookmarkPosition(
          epubBookmark(locatorJson: 'loc-a'),
          const BookmarkPositionContext(epubLocatorJson: 'loc-b'),
        ),
        isFalse,
      );
    });

    test('位置兩組欄位皆為 null 時回傳 false', () {
      expect(
        isSameBookmarkPosition(
          epubBookmark(),
          const BookmarkPositionContext(),
        ),
        isFalse,
      );
    });

    test('pdfPageIndex 有值時只比頁碼，忽略 epubLocatorJson', () {
      const bookmark = Bookmark(
        id: 'bm1',
        bookId: 'b1',
        name: '第 1 頁',
        epubLocatorJson: 'loc-a',
        pdfPageIndex: 0,
      );

      expect(
        isSameBookmarkPosition(
          bookmark,
          const BookmarkPositionContext(
            epubLocatorJson: '完全不同',
            pdfPageIndex: 0,
          ),
        ),
        isTrue,
      );
    });
  });

  group('load', () {
    test('載入後 bookmarks 為 repository 的內容', () async {
      final repository = FakeBookmarksRepository();
      await repository.insert(epubBookmark(id: 'bm1', locatorJson: 'loc-a'));
      await repository.insert(epubBookmark(id: 'bm2', locatorJson: 'loc-b'));
      final controller = BookmarkController(
        repository: repository,
        bookId: 'b1',
      );

      await controller.load();

      expect(controller.bookmarks.map((b) => b.id), ['bm1', 'bm2']);
    });

    test('repository 丟例外時清單保持舊值且不往外丟出', () async {
      final repository = _FlakyBookmarksRepository();
      await repository.insert(epubBookmark(id: 'bm1'));
      final controller = BookmarkController(
        repository: repository,
        bookId: 'b1',
      );
      await controller.load();
      expect(controller.bookmarks, hasLength(1));

      repository.failListByBook = true;

      await expectLater(controller.load(), completes);
      expect(controller.bookmarks.map((b) => b.id), ['bm1']);
    });
  });

  group('at', () {
    test('命中目前位置時回傳該筆書籤', () async {
      final repository = FakeBookmarksRepository();
      await repository.insert(epubBookmark(id: 'bm1', locatorJson: 'loc-a'));
      final controller = BookmarkController(
        repository: repository,
        bookId: 'b1',
      );
      await controller.load();

      final found =
          controller.at(const BookmarkPositionContext(epubLocatorJson: 'loc-a'));

      expect(found?.id, 'bm1');
    });

    test('未命中目前位置時回傳 null', () async {
      final repository = FakeBookmarksRepository();
      await repository.insert(epubBookmark(id: 'bm1', locatorJson: 'loc-a'));
      final controller = BookmarkController(
        repository: repository,
        bookId: 'b1',
      );
      await controller.load();

      expect(
        controller.at(
          const BookmarkPositionContext(epubLocatorJson: 'loc-other'),
        ),
        isNull,
      );
    });

    test('只看記憶體清單：未 load 前即使 repository 有書籤也回 null', () async {
      final repository = FakeBookmarksRepository();
      await repository.insert(epubBookmark(id: 'bm1', locatorJson: 'loc-a'));
      final controller = BookmarkController(
        repository: repository,
        bookId: 'b1',
      );

      expect(
        controller.at(const BookmarkPositionContext(epubLocatorJson: 'loc-a')),
        isNull,
      );
    });
  });

  group('toggle', () {
    test('目前位置無書籤時，呼叫後新增一筆（位置取自 context）', () async {
      final repository = FakeBookmarksRepository();
      final controller = BookmarkController(
        repository: repository,
        bookId: 'b1',
      );

      await controller.toggle(
        position: const BookmarkPositionContext(
          epubLocatorJson: 'loc-a',
          progression: 0.35,
          chapterTitle: '第二章',
        ),
        l10n: l10n,
      );

      final saved = await repository.listByBook('b1');
      expect(saved, hasLength(1));
      expect(saved.single.bookId, 'b1');
      expect(saved.single.epubLocatorJson, 'loc-a');
      expect(saved.single.progression, 0.35);
      expect(saved.single.pdfPageIndex, isNull);
    });

    test('新增的書籤名稱使用 Bookmark.defaultName 的預設名稱', () async {
      final repository = FakeBookmarksRepository();
      final controller = BookmarkController(
        repository: repository,
        bookId: 'b1',
      );
      const position = BookmarkPositionContext(
        epubLocatorJson: 'loc-a',
        progression: 0.35,
        chapterTitle: '第二章',
      );

      await controller.toggle(position: position, l10n: l10n);

      final saved = await repository.listByBook('b1');
      expect(saved.single.name, Bookmark.defaultName(position, l10n));
      expect(saved.single.name, '第二章 (35%)');
    });

    test('PDF 位置新增時寫入 pdfPageIndex', () async {
      final repository = FakeBookmarksRepository();
      final controller = BookmarkController(
        repository: repository,
        bookId: 'b1',
      );

      await controller.toggle(
        position: const BookmarkPositionContext(pdfPageIndex: 4),
        l10n: l10n,
      );

      final saved = await repository.listByBook('b1');
      expect(saved.single.pdfPageIndex, 4);
      expect(saved.single.epubLocatorJson, isNull);
      expect(saved.single.name, '第 5 頁');
    });

    test('目前位置已有書籤時，呼叫後刪除該筆（而非重複新增）', () async {
      final repository = FakeBookmarksRepository();
      await repository.insert(epubBookmark(id: 'existing-id', locatorJson: 'loc-a'));
      final controller = BookmarkController(
        repository: repository,
        bookId: 'b1',
      );

      await controller.toggle(
        position: const BookmarkPositionContext(epubLocatorJson: 'loc-a'),
        l10n: l10n,
      );

      expect(await repository.listByBook('b1'), isEmpty);
    });

    test('repository 有多筆書籤時，只刪除命中目前位置的那一筆', () async {
      final repository = FakeBookmarksRepository();
      await repository.insert(epubBookmark(id: 'other-position', locatorJson: 'loc-b'));
      await repository.insert(epubBookmark(id: 'target-position', locatorJson: 'loc-a'));
      final controller = BookmarkController(
        repository: repository,
        bookId: 'b1',
      );

      await controller.toggle(
        position: const BookmarkPositionContext(epubLocatorJson: 'loc-a'),
        l10n: l10n,
      );

      final saved = await repository.listByBook('b1');
      expect(saved.map((b) => b.id), ['other-position']);
    });

    test('記憶體清單是舊的、資料庫已有該位置書籤時，仍刪除而非重複新增（Epic 26 Issue 1 競態）',
        () async {
      final repository = FakeBookmarksRepository();
      await repository.insert(epubBookmark(id: 'existing-id', locatorJson: 'loc-a'));
      final controller = BookmarkController(
        repository: repository,
        bookId: 'b1',
      );
      // 刻意不呼叫 load()：模擬「開書後尚未載入清單」的舊狀態。
      expect(controller.bookmarks, isEmpty);

      await controller.toggle(
        position: const BookmarkPositionContext(epubLocatorJson: 'loc-a'),
        l10n: l10n,
      );

      expect(
        await repository.listByBook('b1'),
        isEmpty,
        reason: '存在性判斷須直查 repository，不能因記憶體清單是空的就重複新增',
      );
    });

    test('toggle 完成後 bookmarks 已是最新內容', () async {
      final repository = FakeBookmarksRepository();
      final controller = BookmarkController(
        repository: repository,
        bookId: 'b1',
      );

      await controller.toggle(
        position: const BookmarkPositionContext(
          epubLocatorJson: 'loc-a',
          progression: 0.1,
        ),
        l10n: l10n,
      );

      expect(controller.bookmarks, hasLength(1));
      expect(controller.bookmarks.single.epubLocatorJson, 'loc-a');
    });
  });
}
