// app/test/support/fake_full_text_search_settings_repository.dart
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/search/full_text_search_settings_repository.dart';

/// 供 widget test 使用的記憶體內 [FullTextSearchSettingsRepository] 假實作
/// （epic-10-search Issue 3），避免 widget test 依賴真實 SharedPreferences／
/// sqflite（比照 `test/support/fake_library_repository.dart` 既有慣例）。
class FakeFullTextSearchSettingsRepository
    implements FullTextSearchSettingsRepository {
  FakeFullTextSearchSettingsRepository({
    Map<ContentIndexCategory, bool> initialEnabled = const {},
  }) : _enabled = Map.of(initialEnabled);

  final Map<ContentIndexCategory, bool> _enabled;

  /// 記錄每次 [setEnabled] 呼叫的 `(category, value)`。
  final List<(ContentIndexCategory, bool)> setEnabledCalls = [];

  /// 記錄每次 [rebuildIndex] 呼叫的 `category`（review-plan-issue-3.md
  /// I-1）。
  final List<ContentIndexCategory> rebuildIndexCalls = [];

  /// 記錄每次 [markUnsupported]／[handleBookAvailable]／[clearBookIndex]
  /// 呼叫（epic-10-search Issue 2）。
  final List<String> markUnsupportedCalls = [];
  final List<Book> handleBookAvailableCalls = [];
  final List<String> clearBookIndexCalls = [];

  @override
  Future<bool> isEnabled(ContentIndexCategory category) async =>
      _enabled[category] ?? false;

  @override
  Future<void> setEnabled(ContentIndexCategory category, bool value) async {
    _enabled[category] = value;
    setEnabledCalls.add((category, value));
  }

  @override
  Future<void> rebuildIndex(ContentIndexCategory category) async {
    rebuildIndexCalls.add(category);
  }

  @override
  Future<void> markUnsupported(String bookId) async {
    markUnsupportedCalls.add(bookId);
  }

  @override
  Future<void> handleBookAvailable(Book book) async {
    handleBookAvailableCalls.add(book);
  }

  @override
  Future<void> clearBookIndex(String bookId) async {
    clearBookIndexCalls.add(bookId);
  }
}
