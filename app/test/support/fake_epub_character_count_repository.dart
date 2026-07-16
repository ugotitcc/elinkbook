import 'package:elinkbook/reader/epub_character_count_repository.dart';

/// 測試用 Fake，比照 [FakeReadingPositionRepository] 模式。
class FakeEpubCharacterCountRepository implements EpubCharacterCountRepository {
  final Map<String, int> _storage = {};

  @override
  Future<int?> load(String bookId) async => _storage[bookId];

  @override
  Future<void> save(String bookId, int totalCharacterCount) async {
    _storage[bookId] = totalCharacterCount;
  }
}
