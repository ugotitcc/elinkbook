// app/lib/stats/heatmap_grid.dart

/// 貢獻圖涵蓋的天數（含今天）。
const int kHeatmapWindowDays = 365;

/// 本地日期 → `YYYY-MM-DD`，與 `ReadingStatsRepository` 的日期鍵格式一致。
String formatDateKey(DateTime d) {
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-$mm-$dd';
}

/// 五級分級（以當日全部書籍總秒數判定）：
/// 0 無紀錄；1 未滿 15 分；2 未滿 30 分；3 未滿 60 分；4 六十分以上。
int heatmapLevelForSeconds(int seconds) {
  if (seconds <= 0) return 0;
  if (seconds < 15 * 60) return 1;
  if (seconds < 30 * 60) return 2;
  if (seconds < 60 * 60) return 3;
  return 4;
}

/// 月份標籤：貼在第 [weekIndex] 週的方格欄上方，[month] 為 1–12。
class HeatmapMonthLabel {
  final int weekIndex;
  final int month;

  const HeatmapMonthLabel({required this.weekIndex, required this.month});

  @override
  bool operator ==(Object other) =>
      other is HeatmapMonthLabel &&
      other.weekIndex == weekIndex &&
      other.month == month;

  @override
  int get hashCode => Object.hash(weekIndex, month);

  @override
  String toString() => 'HeatmapMonthLabel(week: $weekIndex, month: $month)';
}

/// 貢獻圖的日期網格。
///
/// [weeks] 的每個元素是一週（一欄）的七格：索引 0＝週一、6＝週日；範圍外的
/// 格子（第一週週一之前、最後一週今天之後）為 `null`，畫成不可點擊的透明佔位。
class HeatmapGrid {
  final List<List<String?>> weeks;
  final List<HeatmapMonthLabel> monthLabels;

  /// 視窗第一天與最後一天（今天），供 repository 區間查詢使用。
  final String startDate;
  final String endDate;

  const HeatmapGrid({
    required this.weeks,
    required this.monthLabels,
    required this.startDate,
    required this.endDate,
  });

  int get weekCount => weeks.length;

  /// 回傳 [date]（`YYYY-MM-DD`）所在的週序號與列；不在網格內回傳 `null`。
  ({int week, int row})? locate(String date) {
    for (var w = 0; w < weeks.length; w++) {
      final row = weeks[w].indexOf(date);
      if (row >= 0) return (week: w, row: row);
    }
    return null;
  }
}

/// 建立涵蓋「今天往前 365 天」的貢獻圖網格，一週從週一開始。
///
/// 日期運算一律用 `DateTime(y, m, d + n)`（由 `DateTime` 自行進位），天數差
/// 以 UTC 日期計算——避免夏令時間讓「本地兩日相差」不是整數個 24 小時。
HeatmapGrid buildHeatmapGrid(DateTime today) {
  final t = DateTime(today.year, today.month, today.day);
  final start = DateTime(t.year, t.month, t.day - (kHeatmapWindowDays - 1));
  // Dart 的 weekday：週一＝1…週日＝7，往回推到該週週一。
  final startMonday =
      DateTime(start.year, start.month, start.day - (start.weekday - 1));
  final spanDays = DateTime.utc(t.year, t.month, t.day)
          .difference(DateTime.utc(
              startMonday.year, startMonday.month, startMonday.day))
          .inDays +
      1;
  final weekCount = (spanDays / 7).ceil();

  // 範圍判斷一律比對 `YYYY-MM-DD` 字串（與 repository 的日期鍵約定一致），
  // 不比對 DateTime 的時分秒，避免時區／夏令時間造成的時間偏移影響邊界格。
  final startKey = formatDateKey(start);
  final endKey = formatDateKey(t);

  final weeks = <List<String?>>[];
  for (var w = 0; w < weekCount; w++) {
    final col = <String?>[];
    for (var row = 0; row < 7; row++) {
      final key = formatDateKey(DateTime(
          startMonday.year, startMonday.month, startMonday.day + w * 7 + row));
      col.add(key.compareTo(startKey) < 0 || key.compareTo(endKey) > 0
          ? null
          : key);
    }
    weeks.add(col);
  }

  // 月份標籤：某週第一個有效格的月份與前一個標籤不同時標出；第一個標籤若與
  // 第二個相距不到 2 週（會重疊）則捨棄第一個（與原型一致）。
  final labels = <HeatmapMonthLabel>[];
  var lastMonth = -1;
  for (var w = 0; w < weeks.length; w++) {
    final first = weeks[w].firstWhere((c) => c != null, orElse: () => null);
    if (first == null) continue;
    final month = int.parse(first.substring(5, 7));
    if (month != lastMonth) {
      labels.add(HeatmapMonthLabel(weekIndex: w, month: month));
      lastMonth = month;
    }
  }
  if (labels.length >= 2 && labels[1].weekIndex - labels[0].weekIndex < 2) {
    labels.removeAt(0);
  }

  return HeatmapGrid(
    weeks: weeks,
    monthLabels: labels,
    startDate: startKey,
    endDate: endKey,
  );
}
