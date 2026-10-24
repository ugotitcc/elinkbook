import 'dart:async';

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

/// 可手動控制 listByBook 完成順序，模擬「較舊的查詢比較新的查詢晚回來」。
/// 繼承 [FakeBookmarksRepository]：儲存與 insert／rename／delete 都沿用，只覆寫 listByBook。
class _GatedBookmarksRepository extends FakeBookmarksRepository {
  final List<Completer<void>> _gates = [];
  final List<bool> _failures = [];

  /// 下一次 listByBook 要等這個閘門；fail 為 true 時，放行後丟例外。
  Completer<void> gateNext({bool fail = false}) {
    final gate = Completer<void>();
    _gates.add(gate);
    _failures.add(fail);
    return gate;
  }

  /// 放行所有尚未完成的閘門；測試的 tearDown 呼叫，避免斷言失敗時遺留未完成的 Future。
  void releaseAll() {
    for (final gate in _gates) {
      if (!gate.isCompleted) gate.complete();
    }
    _gates.clear();
    _failures.clear();
  }

  @override
  Future<List<Bookmark>> listByBook(String bookId) async {
    // 閘門與快照都必須在第一個 await 之前同步取得：
    //  - 快照定格在「呼叫當下」的資料（先等閘門才讀資料，舊查詢也會讀到新資料，
    //    沒有世代保護時測試會偽綠）；
    //  - 閘門依「呼叫順序」分配，不受微任務排程影響。
    final snapshotFuture = super.listByBook(bookId);
    final gate = _gates.isEmpty ? null : _gates.removeAt(0);
    final fail = gate == null ? false : _failures.removeAt(0);
    final snapshot = await snapshotFuture;
    if (gate == null) return snapshot;
    await gate.future;
    if (fail) throw StateError('查詢失敗');
    return snapshot;
  }
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

  group('load 世代保護', () {
    late _GatedBookmarksRepository repository;
    late BookmarkController controller;

    setUp(() {
      repository = _GatedBookmarksRepository();
      controller = BookmarkController(
        repository: repository,
        bookId: 'b1',
      );
    });

    tearDown(() {
      // 斷言失敗時也不遺留未完成的 Future（審查 I-1）
      repository.releaseAll();
    });

    test('先發的舊 load、後發的新 load；新的先完成，舊的後完成 → bookmarks 為新值（不被過期舊結果蓋掉）',
        () async {
      await repository.insert(epubBookmark(id: 'bm1', locatorJson: 'loc-a'));

      // 舊 load：卡在第一個閘門，此時快照為 [bm1]
      final gateOld = repository.gateNext();
      final futureOld = controller.load();

      // 在兩次 load 之間新增 bm2
      await repository.insert(epubBookmark(id: 'bm2', locatorJson: 'loc-b'));

      // 新 load：卡在第二個閘門，此時快照為 [bm1, bm2]
      final gateNew = repository.gateNext();
      final futureNew = controller.load();

      // 新的先放行並完成
      gateNew.complete();
      await futureNew;
      expect(controller.bookmarks.map((b) => b.id), ['bm1', 'bm2']);

      // 舊的後放行並完成
      gateOld.complete();
      await futureOld;

      // 驗證清單維持最新值，未被舊的 [bm1] 覆蓋
      expect(controller.bookmarks.map((b) => b.id), ['bm1', 'bm2']);
    });

    test('循序兩次 load：舊的完成後才發起新的，兩次皆正常依序更新', () async {
      await repository.insert(epubBookmark(id: 'bm1', locatorJson: 'loc-a'));

      final gateOld = repository.gateNext();
      final futureOld = controller.load();
      gateOld.complete();
      await futureOld;
      expect(controller.bookmarks.map((b) => b.id), ['bm1']);

      await repository.insert(epubBookmark(id: 'bm2', locatorJson: 'loc-b'));

      final gateNew = repository.gateNext();
      final futureNew = controller.load();
      gateNew.complete();
      await futureNew;
      expect(controller.bookmarks.map((b) => b.id), ['bm1', 'bm2']);
    });

    test('並行兩次 load：舊的先完成（因新的已發出而丟棄）、新的後完成 → bookmarks 為新值',
        () async {
      await repository.insert(epubBookmark(id: 'bm1', locatorJson: 'loc-a'));

      final gateOld = repository.gateNext();
      final futureOld = controller.load();

      await repository.insert(epubBookmark(id: 'bm2', locatorJson: 'loc-b'));

      final gateNew = repository.gateNext();
      final futureNew = controller.load();

      // 舊的先放行：因為較新的 load 已發出，舊結果過期被丟棄，清單維持空值
      gateOld.complete();
      await futureOld;
      expect(controller.bookmarks, isEmpty);

      // 新的後放行並完成：套用最新結果
      gateNew.complete();
      await futureNew;
      expect(controller.bookmarks.map((b) => b.id), ['bm1', 'bm2']);
    });

    test('新的失敗、舊的成功（舊的後完成）→ 清單維持載入前的值，舊結果不套用，不丟例外', () async {
      await repository.insert(epubBookmark(id: 'bm1', locatorJson: 'loc-a'));
      // 先正常載入一次初始狀態 [bm1]
      await controller.load();
      expect(controller.bookmarks.map((b) => b.id), ['bm1']);

      // 在舊 load 發起前再加一筆 bm2
      await repository.insert(epubBookmark(id: 'bm2', locatorJson: 'loc-b'));

      // 舊 load：成功取得 [bm1, bm2]，但卡在閘門
      final gateOld = repository.gateNext();
      final futureOld = controller.load();

      // 新 load：設定 fail: true，將拋出例外
      final gateNew = repository.gateNext(fail: true);
      final futureNew = controller.load();

      // 新的先放行（失敗，catch 吞掉不拋出）
      gateNew.complete();
      await expectLater(futureNew, completes);
      // 新的失敗後，清單維持先前的 [bm1]
      expect(controller.bookmarks.map((b) => b.id), ['bm1']);

      // 舊的後放行（雖查詢成功，但因已有較新的 load 發起過，舊結果過期不套用）
      gateOld.complete();
      await expectLater(futureOld, completes);

      // 清單仍維持 [bm1]，舊結果 [bm1, bm2] 不套用
      expect(controller.bookmarks.map((b) => b.id), ['bm1']);
    });

    test('新的先成功並套用新值，舊的後失敗 → 清單維持新值，不丟例外（舊請求例外不洗掉已套用的新資料，審查 M-2）',
        () async {
      await repository.insert(epubBookmark(id: 'bm1', locatorJson: 'loc-a'));

      // 舊 load：設定 fail: true
      final gateOld = repository.gateNext(fail: true);
      final futureOld = controller.load();

      await repository.insert(epubBookmark(id: 'bm2', locatorJson: 'loc-b'));

      // 新 load：成功
      final gateNew = repository.gateNext();
      final futureNew = controller.load();

      // 新的先放行並完成
      gateNew.complete();
      await expectLater(futureNew, completes);
      expect(controller.bookmarks.map((b) => b.id), ['bm1', 'bm2']);

      // 舊的後放行並失敗
      gateOld.complete();
      await expectLater(futureOld, completes);

      // 清單仍維持新值
      expect(controller.bookmarks.map((b) => b.id), ['bm1', 'bm2']);
    });

    test('開書第一次 load 還沒回來，toggle 先完成，之後第一次 load 才完成 → bookmarks 含新書籤，at 非 null',
        () async {
      // 1. 開書第一次 load（此時資料庫為空），卡在閘門
      final gateInit = repository.gateNext();
      final futureInit = controller.load();

      // 2. 使用者點擊 toggle 新增書籤（toggle 內部查存在性、insert、內部 load 皆直接放行）
      await controller.toggle(
        position: const BookmarkPositionContext(epubLocatorJson: 'loc-a'),
        l10n: l10n,
      );
      expect(controller.bookmarks, hasLength(1));

      // 3. 第一次 load 的閘門放行（舊的空清單結果回來）
      gateInit.complete();
      await futureInit;

      // 4. 驗證新書籤未被過期的第一次 load 洗掉
      expect(controller.bookmarks, hasLength(1));
      expect(
        controller.at(const BookmarkPositionContext(epubLocatorJson: 'loc-a')),
        isNotNull,
      );
    });
  });
}
