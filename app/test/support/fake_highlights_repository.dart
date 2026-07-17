import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlights_repository.dart';

/// 測試用 Fake，比照 [FakeBookmarksRepository] 模式。
class FakeHighlightsRepository implements HighlightsRepository {
  final List<Highlight> _storage = [];
  int _nextId = 1;

  @override
  Future<int> insert(Highlight highlight) async {
    final id = _nextId++;
    _storage.add(Highlight(
      id: id,
      bookId: highlight.bookId,
      style: highlight.style,
      epubLocatorJson: highlight.epubLocatorJson,
      progression: highlight.progression,
    ));
    return id;
  }

  @override
  Future<List<Highlight>> listByBook(String bookId) async {
    final list = _storage.where((h) => h.bookId == bookId).toList();
    list.sort((a, b) => (a.progression ?? 0).compareTo(b.progression ?? 0));
    return list;
  }

  @override
  Future<void> delete(int id) async {
    _storage.removeWhere((h) => h.id == id);
  }

  @override
  Future<void> deleteAllForBook(String bookId) async {
    _storage.removeWhere((h) => h.bookId == bookId);
  }
}
