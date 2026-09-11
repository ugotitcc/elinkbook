import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/library_batch_actions.dart';
// ignore: unused_import
import 'package:elinkbook/search/full_text_search_settings_repository.dart';

import '../support/fake_full_text_search_settings_repository.dart';
import '../support/fake_library_repository.dart';

void main() {
  test('moveToGroup() 只更新選取集合中的書籍，未選取的維持原分類', () async {
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1', groupName: '未分類'),
      _book(id: '2', groupName: '未分類'),
    ]);
    final actions = LibraryBatchActions(repository: repository);
    final books = await repository.listBooks();

    await actions.moveToGroup({'1'}, books, '奇幻');

    final updated = await repository.listBooks();
    expect(updated.firstWhere((b) => b.id == '1').groupName, '奇幻');
    expect(updated.firstWhere((b) => b.id == '2').groupName, '未分類');
  });

  test('forceFixedLayout() 只處理選取集合中的 EPUB 書籍，非 EPUB 自動跳過',
      () async {
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1', format: BookFileFormat.epub),
      _book(id: '2', format: BookFileFormat.pdf),
    ]);
    final actions = LibraryBatchActions(repository: repository);
    final books = await repository.listBooks();

    await actions.forceFixedLayout({'1', '2'}, books);

    final updated = await repository.listBooks();
    expect(updated.firstWhere((b) => b.id == '1').isFixedLayout, isTrue);
    expect(updated.firstWhere((b) => b.id == '2').isFixedLayout, isNull);
  });

  test('restoreAutoLayout() 只對選取集合中的 EPUB 書籍呼叫 detectAndCacheEpubLayout()',
      () async {
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1', format: BookFileFormat.epub),
      _book(id: '2', format: BookFileFormat.pdf),
    ]);
    final actions = LibraryBatchActions(repository: repository);
    final books = await repository.listBooks();

    await actions.restoreAutoLayout({'1', '2'}, books);

    expect(repository.detectAndCacheEpubLayoutCalls, ['1']);
  });

  test('deleteBooks() 刪除選取集合中每一本書的資料庫紀錄', () async {
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1'),
      _book(id: '2'),
    ]);
    final actions = LibraryBatchActions(repository: repository);
    final books = await repository.listBooks();

    await actions.deleteBooks({'1'}, books);

    final remaining = await repository.listBooks();
    expect(remaining.map((b) => b.id), ['2']);
  });

  test(
      'removeLocalCache() 只處理選取集合中「Calibre 來源且已下載」的書籍，'
      '其餘來源與未下載的書籍不受影響', () async {
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1', source: BookSource.calibreOpds, isDownloaded: true),
      _book(id: '2', source: BookSource.local, isDownloaded: true),
      _book(id: '3', source: BookSource.calibreOpds, isDownloaded: false),
    ]);
    final actions = LibraryBatchActions(repository: repository);
    final books = await repository.listBooks();

    await actions.removeLocalCache({'1', '2', '3'}, books);

    final updated = await repository.listBooks();
    expect(updated.firstWhere((b) => b.id == '1').isDownloaded, isFalse);
    expect(updated.firstWhere((b) => b.id == '2').isDownloaded, isTrue);
    expect(updated.firstWhere((b) => b.id == '3').isDownloaded, isFalse);
  });

  test(
      'removeLocalCache() 對被處理的書籍呼叫 clearBookIndex 清除搜尋索引'
      '（epic-10-search Issue 2）', () async {
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1', source: BookSource.calibreOpds, isDownloaded: true),
      _book(id: '2', source: BookSource.local, isDownloaded: true),
    ]);
    final fullTextSearchSettingsRepository =
        FakeFullTextSearchSettingsRepository();
    final actions = LibraryBatchActions(
      repository: repository,
      fullTextSearchSettingsRepository: fullTextSearchSettingsRepository,
    );
    final books = await repository.listBooks();

    await actions.removeLocalCache({'1', '2'}, books);

    // 書籍 2 是 local 來源，shouldInclude 過濾後不會被處理，只有書籍 1
    // 應該觸發 clearBookIndex。
    expect(fullTextSearchSettingsRepository.clearBookIndexCalls, ['1']);
  });
}

Book _book({
  required String id,
  String groupName = BookGroup.uncategorized,
  BookFileFormat format = BookFileFormat.epub,
  BookSource source = BookSource.local,
  bool isDownloaded = true,
}) {
  final now = DateTime.now();
  return Book(
    id: id,
    title: '測試書 $id',
    author: null,
    format: format,
    filePath: 'content://example/$id.epub',
    source: source,
    coverPath: null,
    groupName: groupName,
    isDownloaded: isDownloaded,
    createTime: now,
    lastReadTime: now,
  );
}
