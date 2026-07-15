import 'package:elinkbook/reader/reading_position.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';

/// 測試用 Fake，比照 [FakeBookReaderPrefsRepository] 模式。
class FakeReadingPositionRepository implements ReadingPositionRepository {
  final Map<String, ReadingPosition> _storage = {};

  @override
  Future<ReadingPosition> load(String bookId) async {
    return _storage[bookId] ?? const ReadingPosition();
  }

  @override
  Future<void> save(String bookId, ReadingPosition position) async {
    _storage[bookId] = position;
  }
}
