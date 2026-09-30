import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/stats/heatmap_grid.dart';

int _validCount(HeatmapGrid g) =>
    g.weeks.expand((w) => w).where((c) => c != null).length;

int _nullCount(HeatmapGrid g) =>
    g.weeks.expand((w) => w).where((c) => c == null).length;

void main() {
  group('formatDateKey', () {
    test('補零成 YYYY-MM-DD', () {
      expect(formatDateKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(formatDateKey(DateTime(2026, 12, 31, 23, 59)), '2026-12-31');
    });
  });

  group('heatmapLevelForSeconds 五級邊界', () {
    test('0 與負值為第 0 級', () {
      expect(heatmapLevelForSeconds(0), 0);
      expect(heatmapLevelForSeconds(-5), 0);
    });
    test('1..899 秒為第 1 級', () {
      expect(heatmapLevelForSeconds(1), 1);
      expect(heatmapLevelForSeconds(899), 1);
    });
    test('900..1799 秒為第 2 級', () {
      expect(heatmapLevelForSeconds(900), 2);
      expect(heatmapLevelForSeconds(1799), 2);
    });
    test('1800..3599 秒為第 3 級', () {
      expect(heatmapLevelForSeconds(1800), 3);
      expect(heatmapLevelForSeconds(3599), 3);
    });
    test('3600 秒（含）以上為第 4 級', () {
      expect(heatmapLevelForSeconds(3600), 4);
      expect(heatmapLevelForSeconds(999999), 4);
    });
  });

  group('buildHeatmapGrid（今天＝2026-09-29 週二）', () {
    final grid = buildHeatmapGrid(DateTime(2026, 9, 29, 15, 30));

    test('共 53 週、365 個有效格、6 個透明佔位', () {
      expect(grid.weekCount, 53);
      expect(grid.weeks.every((w) => w.length == 7), isTrue);
      expect(_validCount(grid), 365);
      expect(_nullCount(grid), 6);
    });

    test('起訖日為今天往前 364 天到今天', () {
      expect(grid.startDate, '2025-09-30');
      expect(grid.endDate, '2026-09-29');
    });

    test('一週從週一開始：首週週一為佔位、週二為起始日', () {
      expect(grid.weeks.first[0], isNull); // 2025-09-29 週一，早於起始日
      expect(grid.weeks.first[1], '2025-09-30'); // 週二
    });

    test('末週：週一、週二（今天）有效，週三到週日為佔位', () {
      final last = grid.weeks.last;
      expect(last[0], '2026-09-28');
      expect(last[1], '2026-09-29');
      expect(last.sublist(2).every((c) => c == null), isTrue);
    });

    test('locate 回傳日期所在的週序號與列（0＝週一）', () {
      expect(grid.locate('2026-09-29'), (week: 52, row: 1));
      expect(grid.locate('2026-09-28'), (week: 52, row: 0));
      expect(grid.locate('2026-09-27'), (week: 51, row: 6)); // 週日
      expect(grid.locate('2025-09-30'), (week: 0, row: 1));
      expect(grid.locate('2025-09-29'), isNull); // 佔位格不是有效日期
      expect(grid.locate('2026-09-30'), isNull); // 未來
    });

    test('月份標籤：第一個標籤與第二個相距不到 2 週時捨棄第一個', () {
      // 週 0 的第一個有效格是 9 月、週 1 首格是 10 月，相距 1 週 → 捨棄 9 月標籤
      expect(grid.monthLabels.first,
          const HeatmapMonthLabel(weekIndex: 1, month: 10));
      expect(grid.monthLabels[1],
          const HeatmapMonthLabel(weekIndex: 5, month: 11));
      expect(grid.monthLabels.last,
          const HeatmapMonthLabel(weekIndex: 49, month: 9));
    });
  });

  group('buildHeatmapGrid 邊界', () {
    test('今天為週日：末週為完整七格、佔位全在首週', () {
      final grid = buildHeatmapGrid(DateTime(2026, 9, 27)); // 週日
      expect(grid.weekCount, 53);
      expect(grid.weeks.last.every((c) => c != null), isTrue);
      expect(grid.weeks.last[6], '2026-09-27');
      expect(_validCount(grid), 365);
      expect(_nullCount(grid), 6);
      expect(grid.weeks.first.where((c) => c == null).length, 6);
      expect(grid.weeks.first[6], '2025-09-28'); // 起始日也是週日
    });

    test('閏日：今天為 2028-02-29 時仍是 365 格且含閏日', () {
      final grid = buildHeatmapGrid(DateTime(2028, 2, 29));
      expect(_validCount(grid), 365);
      expect(grid.endDate, '2028-02-29');
      expect(grid.startDate, '2027-03-02');
      expect(grid.locate('2028-02-29'), isNotNull);
    });

    test('今天為週一：末週只有週一一格有效', () {
      final grid = buildHeatmapGrid(DateTime(2026, 9, 28)); // 週一
      final last = grid.weeks.last;
      expect(last[0], '2026-09-28');
      expect(last.sublist(1).every((c) => c == null), isTrue);
      expect(_validCount(grid), 365);
    });
  });
}
