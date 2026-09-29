// app/test/support/fake_reading_stats_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/stats/daily_book_reading_stat.dart';

import '../stats/reading_stats_repository_contract.dart';
import 'fake_reading_stats_repository.dart';

void main() {
  runReadingStatsRepositoryContract(
    'FakeReadingStatsRepository',
    () async => FakeReadingStatsRepository(),
  );

  group('FakeReadingStatsRepository 輔助功能', () {
    test('initialStats 預先填入的資料可被查詢', () async {
      final repo = FakeReadingStatsRepository(initialStats: {
        '2026-09-29': [
          const DailyBookReadingStat(
              bookId: 'b1', bookTitle: '書', readingSeconds: 300),
        ],
      });
      expect(await repo.getTotalReadingSeconds(), 300);
      expect((await repo.getBookStatsForDate('2026-09-29')).single.bookId, 'b1');
    });

    test('addReadingSecondsError 非 null 時 addReadingSeconds 拋出它且不寫入；清除後恢復正常',
        () async {
      final repo = FakeReadingStatsRepository()
        ..addReadingSecondsError = StateError('模擬寫入失敗');

      await expectLater(
        repo.addReadingSeconds(
            date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 60),
        throwsA(isA<StateError>()),
      );
      expect(await repo.getTotalReadingSeconds(), 0);

      repo.addReadingSecondsError = null;
      await repo.addReadingSeconds(
          date: '2026-09-29', bookId: 'b1', bookTitle: '書', seconds: 60);
      expect(await repo.getTotalReadingSeconds(), 60);
    });
  });
}
