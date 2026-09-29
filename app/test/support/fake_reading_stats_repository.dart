// app/test/support/fake_reading_stats_repository.dart
import 'dart:async';

import 'package:elinkbook/stats/daily_book_reading_stat.dart';
import 'package:elinkbook/stats/reading_stats_repository.dart';

/// 供 widget／單元測試使用的記憶體內 [ReadingStatsRepository] 假實作
/// （epic-9-stats Issue 2），行為與 `SqliteReadingStatsRepository` 一致，
/// 兩者共用同一組契約測試（`reading_stats_repository_contract.dart`）。
class FakeReadingStatsRepository implements ReadingStatsRepository {
  /// [initialStats]：預先填入的資料，`date -> 該日書籍統計清單`。
  FakeReadingStatsRepository({
    Map<String, List<DailyBookReadingStat>> initialStats = const {},
  }) {
    initialStats.forEach((date, list) {
      for (final s in list) {
        _rows[(date, s.bookId)] = s;
      }
    });
  }

  final Map<(String, String), DailyBookReadingStat> _rows = {};
  final StreamController<void> _clearedController =
      StreamController<void>.broadcast();

  /// 測試用：非 null 時 [addReadingSeconds] 會拋出它，模擬資料庫寫入失敗
  /// （供 Issue 4 驗證 ReaderScreen 寫入失敗時不崩潰、不中斷閱讀）。
  Object? addReadingSecondsError;

  @override
  Future<void> addReadingSeconds({
    required String date,
    required String bookId,
    required String bookTitle,
    required int seconds,
  }) async {
    if (addReadingSecondsError != null) throw addReadingSecondsError!;
    if (seconds <= 0) return;
    final existing = _rows[(date, bookId)];
    _rows[(date, bookId)] = DailyBookReadingStat(
      bookId: bookId,
      bookTitle: bookTitle,
      readingSeconds: (existing?.readingSeconds ?? 0) + seconds,
    );
  }

  @override
  Future<Map<String, int>> getDailyTotals({
    required String startDate,
    required String endDate,
  }) async {
    final totals = <String, int>{};
    _rows.forEach((key, stat) {
      final date = key.$1;
      if (date.compareTo(startDate) >= 0 && date.compareTo(endDate) <= 0) {
        totals[date] = (totals[date] ?? 0) + stat.readingSeconds;
      }
    });
    // 與 SQLite 實作一致：鍵依日期由早到晚排列
    final sortedDates = totals.keys.toList()..sort();
    return {for (final d in sortedDates) d: totals[d]!};
  }

  @override
  Future<List<DailyBookReadingStat>> getBookStatsForDate(String date) async {
    final list = [
      for (final e in _rows.entries)
        if (e.key.$1 == date) e.value,
    ];
    list.sort((a, b) {
      final bySeconds = b.readingSeconds.compareTo(a.readingSeconds);
      if (bySeconds != 0) return bySeconds;
      final byTitle = a.bookTitle.compareTo(b.bookTitle);
      if (byTitle != 0) return byTitle;
      return a.bookId.compareTo(b.bookId);
    });
    return list;
  }

  @override
  Future<int> getTotalReadingSeconds() async =>
      _rows.values.fold<int>(0, (sum, s) => sum + s.readingSeconds);

  @override
  Future<void> clearAllStats() async {
    _rows.clear();
    _clearedController.add(null);
  }

  @override
  Stream<void> get onCleared => _clearedController.stream;
}
