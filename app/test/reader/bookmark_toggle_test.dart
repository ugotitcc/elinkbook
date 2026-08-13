import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmark_toggle.dart';
import '../support/fake_bookmarks_repository.dart';

void main() {
  test('目前位置無書籤時，呼叫後新增一筆（build() 提供的內容）', () async {
    final repository = FakeBookmarksRepository();

    await toggleBookmark(
      repository: repository,
      bookId: 'b1',
      matches: (b) => b.epubLocatorJson == 'loc-a',
      build: () => Bookmark(
        id: 'new-id',
        bookId: 'b1',
        name: '書籤 A',
        epubLocatorJson: 'loc-a',
      ),
    );

    final saved = await repository.listByBook('b1');
    expect(saved, hasLength(1));
    expect(saved.single.id, 'new-id');
    expect(saved.single.epubLocatorJson, 'loc-a');
  });

  test('目前位置已有書籤時，呼叫後刪除該筆（而非重複新增）', () async {
    final repository = FakeBookmarksRepository();
    await repository.insert(Bookmark(
      id: 'existing-id',
      bookId: 'b1',
      name: '既有書籤',
      epubLocatorJson: 'loc-a',
    ));

    await toggleBookmark(
      repository: repository,
      bookId: 'b1',
      matches: (b) => b.epubLocatorJson == 'loc-a',
      build: () => Bookmark(
        id: 'should-not-be-used',
        bookId: 'b1',
        name: '不應被插入',
        epubLocatorJson: 'loc-a',
      ),
    );

    final saved = await repository.listByBook('b1');
    expect(saved, isEmpty);
  });

  test('repository 有多筆書籤時，只刪除 matches 命中的那一筆', () async {
    final repository = FakeBookmarksRepository();
    await repository.insert(Bookmark(
      id: 'other-position',
      bookId: 'b1',
      name: '別的位置',
      epubLocatorJson: 'loc-b',
    ));
    await repository.insert(Bookmark(
      id: 'target-position',
      bookId: 'b1',
      name: '目標位置',
      epubLocatorJson: 'loc-a',
    ));

    await toggleBookmark(
      repository: repository,
      bookId: 'b1',
      matches: (b) => b.epubLocatorJson == 'loc-a',
      build: () => throw StateError('不應被呼叫'),
    );

    final saved = await repository.listByBook('b1');
    expect(saved, hasLength(1));
    expect(saved.single.id, 'other-position');
  });
}
