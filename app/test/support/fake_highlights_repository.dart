import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlights_repository.dart';

/// 測試用 Fake，比照 [FakeBookmarksRepository] 模式。
class FakeHighlightsRepository implements HighlightsRepository {
  final List<Highlight> _storage = [];

  @override
  Future<void> insert(Highlight highlight) async {
    _storage.add(Highlight(
      id: highlight.id,
      bookId: highlight.bookId,
      style: highlight.style,
      epubLocatorJson: highlight.epubLocatorJson,
      progression: highlight.progression,
      pdfPageIndex: highlight.pdfPageIndex,
      pdfRect: highlight.pdfRect,
    ));
  }

  @override
  Future<List<Highlight>> listByBook(String bookId) async {
    final list = _storage.where((h) => h.bookId == bookId).toList();
    list.sort((a, b) => _positionOf(a).compareTo(_positionOf(b)));
    return list;
  }

  double _positionOf(Highlight h) =>
      (h.pdfPageIndex?.toDouble()) ?? h.progression ?? 0;

  @override
  Future<void> delete(String id) async {
    _storage.removeWhere((h) => h.id == id);
  }

  @override
  Future<void> deleteAllForBook(String bookId) async {
    _storage.removeWhere((h) => h.bookId == bookId);
  }
}
