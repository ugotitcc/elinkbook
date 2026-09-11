// app/test/support/fake_search_repository.dart
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/search/search_repository.dart';

/// 供 widget test 使用的記憶體內 [SearchRepository] 假實作
/// （epic-10-search Issue 4），避免 widget test 依賴真實 sqflite（比照
/// `test/support/fake_library_repository.dart` 既有慣例）。
class FakeSearchRepository implements SearchRepository {
  FakeSearchRepository({
    List<Book> titleAuthorResults = const [],
    List<BookContentMatches> contentResults = const [],
  })  : _titleAuthorResults = titleAuthorResults,
        _contentResults = contentResults;

  final List<Book> _titleAuthorResults;
  final List<BookContentMatches> _contentResults;

  /// 記錄每次呼叫的查詢字串，供測試驗證 debounce 行為（只在延遲後觸發
  /// 一次）。
  final List<String> searchTitleAuthorCalls = [];
  final List<String> searchContentCalls = [];

  @override
  Future<List<Book>> searchTitleAuthor(String query) async {
    searchTitleAuthorCalls.add(query);
    return _titleAuthorResults;
  }

  @override
  Future<List<BookContentMatches>> searchContent(
    String query, {
    int perBookLimit = 3,
  }) async {
    searchContentCalls.add(query);
    return _contentResults;
  }
}
