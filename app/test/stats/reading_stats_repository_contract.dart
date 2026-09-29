// app/test/stats/reading_stats_repository_contract.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/stats/daily_book_reading_stat.dart';
import 'package:elinkbook/stats/reading_stats_repository.dart';

/// [ReadingStatsRepository] 的共用契約測試（epic-9-stats Issue 2）。
///
/// 正式實作（SQLite）與測試替身（Fake）都必須通過同一組案例，確保 Issue 4、
/// Issue 5 用替身驗證的結果，與真實資料庫的行為一致。
void runReadingStatsRepositoryContract(
  String label,
  Future<ReadingStatsRepository> Function() create,
) {
  group('ReadingStatsRepository 契約（$label）', () {
    late ReadingStatsRepository repo;

    setUp(() async {
      repo = await create();
    });

    test('同日同書多次累加：秒數相加', () async {
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 60);
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 90);

      expect(await repo.getBookStatsForDate('2026-09-29'), [
        const DailyBookReadingStat(
            bookId: 'b1', bookTitle: '書', readingSeconds: 150),
      ]);
    });

    test('不同書、不同日各自獨立累計', () async {
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: 'A', seconds: 10);
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b2', bookTitle: 'B', seconds: 20);
      await repo.addReadingSeconds(
          date: '2026-09-30', bookId: 'b1', bookTitle: 'A', seconds: 30);

      expect(await repo.getDailyTotals(
              startDate: '2026-09-29', endDate: '2026-09-30'),
          {'2026-09-29': 30, '2026-09-30': 30});
    });

    test('書名快照以最新一次寫入為準', () async {
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '舊書名', seconds: 60);
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '新書名', seconds: 60);

      final stats = await repo.getBookStatsForDate('2026-09-29');
      expect(stats.single.bookTitle, '新書名');
      expect(stats.single.readingSeconds, 120);
    });

    test('秒數為 0 或負數：不建立紀錄、也不倒扣既有紀錄', () async {
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 0);
      expect(await repo.getBookStatsForDate('2026-09-29'), isEmpty);

      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 100);
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: -40);
      expect((await repo.getBookStatsForDate('2026-09-29')).single.readingSeconds,
          100);
    });

    test('getDailyTotals：含起訖日、只回傳有紀錄的日期、同日多本書加總', () async {
      Future<void> add(String d, String b, int s) => repo.addReadingSeconds(
          date: d, bookId: b, bookTitle: b, seconds: s);
      await add('2026-09-27', 'b1', 5); // 區間外（起日之前）
      await add('2026-09-28', 'b1', 10); // 起日
      await add('2026-09-28', 'b2', 20); // 同日另一本
      await add('2026-09-30', 'b1', 40); // 訖日
      await add('2026-10-01', 'b1', 80); // 區間外（訖日之後）

      expect(
        await repo.getDailyTotals(startDate: '2026-09-28', endDate: '2026-09-30'),
        {'2026-09-28': 30, '2026-09-30': 40},
      );
    });

    test('getDailyTotals：鍵依日期由早到晚排列，與寫入順序無關', () async {
      Future<void> add(String d) => repo.addReadingSeconds(
          date: d, bookId: 'b1', bookTitle: '書', seconds: 10);
      await add('2026-09-30'); // 故意由新到舊寫入
      await add('2026-09-28');
      await add('2026-09-29');

      final totals = await repo.getDailyTotals(
          startDate: '2026-09-01', endDate: '2026-09-30');
      expect(totals.keys.toList(), ['2026-09-28', '2026-09-29', '2026-09-30']);
    });

    test('getDailyTotals：起日晚於訖日時回傳空 Map', () async {
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 10);
      expect(
        await repo.getDailyTotals(startDate: '2026-09-30', endDate: '2026-09-28'),
        isEmpty,
      );
    });

    test('getBookStatsForDate：依秒數由大到小，同秒數依書名再依 id', () async {
      Future<void> add(String id, String title, int s) => repo.addReadingSeconds(
          date: '2026-09-29', bookId: id, bookTitle: title, seconds: s);
      await add('b3', 'C', 50);
      await add('b1', 'B', 100);
      await add('b2', 'A', 100);
      await add('b0', 'A', 100); // 書名與 b2 相同，依 id 排在 b2 之前

      final stats = await repo.getBookStatsForDate('2026-09-29');
      expect(stats.map((s) => s.bookId).toList(), ['b0', 'b2', 'b1', 'b3']);
    });

    test('getBookStatsForDate：該日沒有紀錄時回傳空清單', () async {
      expect(await repo.getBookStatsForDate('2026-01-01'), isEmpty);
    });

    test('getTotalReadingSeconds：全部紀錄加總；沒有紀錄為 0', () async {
      expect(await repo.getTotalReadingSeconds(), 0);
      await repo.addReadingSeconds(
          date: '2026-09-28', bookId: 'b1', bookTitle: 'A', seconds: 100);
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b2', bookTitle: 'B', seconds: 250);
      expect(await repo.getTotalReadingSeconds(), 350);
    });

    test('clearAllStats：清空全部資料，之後仍可再累加', () async {
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 60);
      await repo.clearAllStats();

      expect(await repo.getTotalReadingSeconds(), 0);
      expect(await repo.getBookStatsForDate('2026-09-29'), isEmpty);

      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 5);
      expect(await repo.getTotalReadingSeconds(), 5);
    });

    test('onCleared：每次清除發出一次事件，多個監聽者都收到', () async {
      var first = 0;
      var second = 0;
      final sub1 = repo.onCleared.listen((_) => first++);
      final sub2 = repo.onCleared.listen((_) => second++);
      addTearDown(sub1.cancel);
      addTearDown(sub2.cancel);

      await repo.clearAllStats();
      await pumpEventQueue();
      expect((first, second), (1, 1));

      await repo.clearAllStats(); // 沒有資料時清除也要發出事件
      await pumpEventQueue();
      expect((first, second), (2, 2));
    });

    test('onCleared：沒有監聽者時清除不拋例外', () async {
      await repo.clearAllStats();
    });

    // ---- 審查重點：規格沒明說、但使用者最可能碰到的輸入 ----

    test('區間查詢跨月、跨年：日期字串比較與日曆先後一致', () async {
      Future<void> add(String d) => repo.addReadingSeconds(
          date: d, bookId: 'b1', bookTitle: '書', seconds: 10);
      await add('2025-12-31');
      await add('2026-01-01');
      await add('2026-01-31');
      await add('2026-02-01');

      expect(
        await repo.getDailyTotals(startDate: '2025-12-30', endDate: '2026-01-02'),
        {'2025-12-31': 10, '2026-01-01': 10},
      );
      expect(
        await repo.getDailyTotals(startDate: '2026-01-01', endDate: '2026-01-31'),
        {'2026-01-01': 10, '2026-01-31': 10},
      );
    });

    test('書名含單引號、雙引號、emoji 與 SQL 關鍵字：原樣存取，不被當成 SQL', () async {
      const title = "O'Brien \"書\"; DROP TABLE daily_reading_stats; -- 😀";
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: title, seconds: 60);

      final stats = await repo.getBookStatsForDate('2026-09-29');
      expect(stats.single.bookTitle, title);
      expect(await repo.getTotalReadingSeconds(), 60);
    });

    test('同一筆同時多次累加（例如計時器 flush 重疊）：秒數不遺失', () async {
      await Future.wait([
        for (var i = 0; i < 20; i++)
          repo.addReadingSeconds(
              date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 5),
      ]);

      expect(await repo.getTotalReadingSeconds(), 100);
    });

    test('onCleared 事件送達時，資料已經清空（監聽者不會讀到舊資料）', () async {
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 60);

      final totalSeenByListener = <int>[];
      final sub = repo.onCleared.listen((_) {
        repo.getTotalReadingSeconds().then(totalSeenByListener.add);
      });
      addTearDown(sub.cancel);

      await repo.clearAllStats();
      await pumpEventQueue();

      expect(totalSeenByListener, [0]);
    });
  });
}
