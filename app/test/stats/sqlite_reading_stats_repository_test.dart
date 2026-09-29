// app/test/stats/sqlite_reading_stats_repository_test.dart
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/stats/sqlite_reading_stats_repository.dart';

import 'reading_stats_repository_contract.dart';

Book _book(String id, {String title = '書名'}) => Book(
      id: id,
      title: title,
      format: BookFileFormat.epub,
      filePath: '/books/$id',
      source: BookSource.local,
      createTime: DateTime(2026, 1, 1),
      lastReadTime: DateTime(2026, 1, 1),
    );

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // 每個案例各開一個全新的記憶體資料庫（singleInstance: false，避免共用連線）
  final opened = <SqliteLibraryRepository>[];
  tearDown(() async {
    for (final r in opened) {
      await r.close();
    }
    opened.clear();
  });

  Future<SqliteLibraryRepository> openLibrary() async {
    final r = await SqliteLibraryRepository.open(inMemoryDatabasePath,
        singleInstance: false);
    opened.add(r);
    return r;
  }

  runReadingStatsRepositoryContract('SqliteReadingStatsRepository', () async {
    final library = await openLibrary();
    return SqliteReadingStatsRepository(database: library.database);
  });

  group('SqliteReadingStatsRepository 專屬行為', () {
    test('刪除書籍後：統計時數與書名快照仍可透過 repository 查到', () async {
      final library = await openLibrary();
      final stats = SqliteReadingStatsRepository(database: library.database);
      await library.insertBook(_book('b1', title: '會被刪除的書'));
      await stats.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '會被刪除的書', seconds: 600);

      await library.deleteBook('b1');

      expect(await stats.getTotalReadingSeconds(), 600);
      final detail = await stats.getBookStatsForDate('2026-09-29');
      expect(detail.single.bookTitle, '會被刪除的書');
      expect(detail.single.readingSeconds, 600);
    });

    test('updated_at 取自注入的時鐘，每次累加都會更新', () async {
      final library = await openLibrary();
      final stats = SqliteReadingStatsRepository(database: library.database);

      await withClock(
          Clock.fixed(DateTime.fromMillisecondsSinceEpoch(1000)),
          () => stats.addReadingSeconds(
              date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 10));
      await withClock(
          Clock.fixed(DateTime.fromMillisecondsSinceEpoch(2000)),
          () => stats.addReadingSeconds(
              date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 10));

      final rows = await library.database.query('daily_reading_stats');
      expect(rows.single['updated_at'], 2000);
      expect(rows.single['reading_seconds'], 20);
    });
  });
}
