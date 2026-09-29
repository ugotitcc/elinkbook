// app/lib/stats/sqlite_reading_stats_repository.dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:sqflite/sqflite.dart';

import 'daily_book_reading_stat.dart';
import 'reading_stats_repository.dart';

/// [ReadingStatsRepository] 正式實作：直接對 [Database] 下 SQL（比照
/// `SqliteSearchRepository` 既有慣例，不經 `LibraryRepository`）。
///
/// 查詢**一律不 JOIN `books`**：書被刪除後統計仍保留，書名只讀
/// `daily_reading_stats.book_title` 的快照。
class SqliteReadingStatsRepository implements ReadingStatsRepository {
  SqliteReadingStatsRepository({required Database database})
      : _database = database;

  final Database _database;
  final StreamController<void> _clearedController =
      StreamController<void>.broadcast();

  @override
  Future<void> addReadingSeconds({
    required String date,
    required String bookId,
    required String bookTitle,
    required int seconds,
  }) async {
    if (seconds <= 0) return;
    // upsert：主鍵衝突時累加秒數，並以最新書名覆寫快照。
    await _database.rawInsert('''
      INSERT INTO daily_reading_stats
        (date, book_id, book_title, reading_seconds, updated_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(date, book_id) DO UPDATE SET
        reading_seconds = daily_reading_stats.reading_seconds + excluded.reading_seconds,
        book_title = excluded.book_title,
        updated_at = excluded.updated_at
    ''', [date, bookId, bookTitle, seconds, clock.now().millisecondsSinceEpoch]);
  }

  @override
  Future<Map<String, int>> getDailyTotals({
    required String startDate,
    required String endDate,
  }) async {
    final rows = await _database.rawQuery('''
      SELECT date, SUM(reading_seconds) AS total
      FROM daily_reading_stats
      WHERE date >= ? AND date <= ?
      GROUP BY date
      ORDER BY date ASC
    ''', [startDate, endDate]);
    return {
      for (final row in rows) row['date'] as String: row['total'] as int,
    };
  }

  @override
  Future<List<DailyBookReadingStat>> getBookStatsForDate(String date) async {
    final rows = await _database.query(
      'daily_reading_stats',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'reading_seconds DESC, book_title ASC, book_id ASC',
    );
    return [
      for (final row in rows)
        DailyBookReadingStat(
          bookId: row['book_id'] as String,
          bookTitle: row['book_title'] as String,
          readingSeconds: row['reading_seconds'] as int,
        ),
    ];
  }

  @override
  Future<int> getTotalReadingSeconds() async {
    final rows = await _database.rawQuery(
        'SELECT COALESCE(SUM(reading_seconds), 0) AS total FROM daily_reading_stats');
    return rows.first['total'] as int;
  }

  @override
  Future<void> clearAllStats() async {
    await _database.delete('daily_reading_stats');
    _clearedController.add(null);
  }

  @override
  Stream<void> get onCleared => _clearedController.stream;
}
