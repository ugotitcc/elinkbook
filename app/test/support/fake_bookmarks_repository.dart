import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmarks_repository.dart';

/// 測試用 Fake，比照 [FakeReadingPositionRepository] 模式。
class FakeBookmarksRepository implements BookmarksRepository {
  final List<Bookmark> _storage = [];

  @override
  Future<void> insert(Bookmark bookmark) async {
    _storage.add(Bookmark(
      id: bookmark.id,
      bookId: bookmark.bookId,
      name: bookmark.name,
      epubLocatorJson: bookmark.epubLocatorJson,
      progression: bookmark.progression,
      pdfPageIndex: bookmark.pdfPageIndex,
    ));
  }

  @override
  Future<List<Bookmark>> listByBook(String bookId) async {
    final list = _storage.where((b) => b.bookId == bookId).toList();
    list.sort((a, b) {
      final posA = a.pdfPageIndex?.toDouble() ?? a.progression ?? 0;
      final posB = b.pdfPageIndex?.toDouble() ?? b.progression ?? 0;
      return posA.compareTo(posB);
    });
    return list;
  }

  @override
  Future<void> rename(String id, String newName) async {
    final index = _storage.indexWhere((b) => b.id == id);
    if (index == -1) return;
    _storage[index] = _storage[index].copyWith(name: newName);
  }

  @override
  Future<void> delete(String id) async {
    _storage.removeWhere((b) => b.id == id);
  }

  @override
  Future<void> deleteAllForBook(String bookId) async {
    _storage.removeWhere((b) => b.bookId == bookId);
  }
}
