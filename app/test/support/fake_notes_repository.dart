import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/notes_repository.dart';

/// 測試用 Fake。刻意不模擬 FK `ON DELETE SET NULL` 的資料庫層退化行為
/// （那已由 Task 4 的真實 SQLite repository 測試涵蓋）——本 Fake 供
/// widget test 使用，widget test 只需要驗證「假設資料已經是退化後的
/// 狀態」時 UI 是否正確呈現，不需要重新模擬 FK 機制本身。
class FakeNotesRepository implements NotesRepository {
  final List<Note> _storage = [];
  int _nextId = 1;

  @override
  Future<int> insert(Note note) async {
    final id = _nextId++;
    _storage.add(Note(
      id: id,
      bookId: note.bookId,
      text: note.text,
      epubLocatorJson: note.epubLocatorJson,
      progression: note.progression,
      highlightId: note.highlightId,
    ));
    return id;
  }

  @override
  Future<List<Note>> listByBook(String bookId) async {
    final list = _storage.where((n) => n.bookId == bookId).toList();
    list.sort((a, b) => (a.progression ?? 0).compareTo(b.progression ?? 0));
    return list;
  }

  @override
  Future<void> updateText(int id, String text) async {
    final index = _storage.indexWhere((n) => n.id == id);
    if (index == -1) return;
    _storage[index] = _storage[index].copyWith(text: text);
  }

  @override
  Future<void> delete(int id) async {
    _storage.removeWhere((n) => n.id == id);
  }

  @override
  Future<void> deleteAllForBook(String bookId) async {
    _storage.removeWhere((n) => n.bookId == bookId);
  }
}
