import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';

class FakeBookReaderPrefsRepository implements BookReaderPrefsRepository {
  final Map<String, BookReaderPrefs> _storage = {};

  @override
  Future<BookReaderPrefs> load(String bookId) async {
    return _storage[bookId] ?? BookReaderPrefs.empty;
  }

  @override
  Future<void> save(String bookId, BookReaderPrefs prefs) async {
    _storage[bookId] = prefs;
  }
}
