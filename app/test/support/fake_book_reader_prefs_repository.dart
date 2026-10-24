import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';

class FakeBookReaderPrefsRepository implements BookReaderPrefsRepository {
  final Map<String, BookReaderPrefs> _storage = {};

  /// 指定哪些方法要丟例外（`'load'`／`'save'`／`'saveMultiple'`），供測試注入
  /// 失敗情境（epic-54 Issue 26 計畫審查 M-3）。可在測試中途改變。
  final Set<String> failOn = {};

  /// 依呼叫順序記錄方法名稱（`'load'`／`'save'`／`'saveMultiple'`），
  /// 供測試斷言「有沒有呼叫、呼叫幾次」。
  final List<String> calls = [];

  void _record(String method) {
    calls.add(method);
    if (failOn.contains(method)) throw StateError('fake $method failed');
  }

  @override
  Future<BookReaderPrefs> load(String bookId) async {
    _record('load');
    return _storage[bookId] ?? BookReaderPrefs.empty;
  }

  @override
  Future<void> save(String bookId, BookReaderPrefs prefs) async {
    _record('save');
    _storage[bookId] = prefs;
  }

  @override
  Future<void> saveMultiple(List<String> bookIds, BookReaderPrefs prefs) async {
    _record('saveMultiple');
    for (final bookId in bookIds) {
      _storage[bookId] = prefs;
    }
  }
}
