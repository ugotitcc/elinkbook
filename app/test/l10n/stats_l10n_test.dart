import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';

void main() {
  test('正體中文（zh_TW）統計字串齊備', () {
    final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));
    expect(l10n.statsScreenTitle, '閱讀統計');
    expect(l10n.statsTotalDuration, '累計閱讀時數');
    expect(l10n.statsHoursMinutesFormat(1, 5), '1 小時 5 分鐘');
    expect(l10n.statsMinutesFormat(7), '7 分鐘');
    expect(l10n.statsDailyDetailsTitle('2026/9/29'), '2026/9/29 閱讀明細');
    expect(l10n.statsNoDataOnDate, '當日無閱讀記錄');
    expect(l10n.statsLegendLess, '較少');
    expect(l10n.statsLegendMore, '較多');
    expect(l10n.statsClearAllTitle, '清除全部統計');
    expect(l10n.statsClearAllConfirmMessage, '確定要清除所有閱讀統計嗎？此動作無法復原。');
    expect(l10n.statsClearAllSuccess, '已清除全部閱讀統計');
    expect(l10n.statsWeekdayMon, '一');
    expect(l10n.statsWeekdayWed, '三');
    expect(l10n.statsWeekdayFri, '五');
  });

  test('中文通用退路（zh）與正體中文內容相同', () {
    final l10n = lookupAppLocalizations(const Locale('zh'));
    expect(l10n.statsScreenTitle, '閱讀統計');
    expect(l10n.statsHoursMinutesFormat(2, 0), '2 小時 0 分鐘');
    expect(l10n.statsDailyDetailsTitle('X'), 'X 閱讀明細');
    expect(l10n.statsWeekdayFri, '五');
  });

  test('簡體中文（zh_CN）統計字串齊備', () {
    final l10n = lookupAppLocalizations(const Locale('zh', 'CN'));
    expect(l10n.statsScreenTitle, '阅读统计');
    expect(l10n.statsTotalDuration, '累计阅读时长');
    expect(l10n.statsHoursMinutesFormat(1, 5), '1 小时 5 分钟');
    expect(l10n.statsMinutesFormat(7), '7 分钟');
    expect(l10n.statsDailyDetailsTitle('2026/9/29'), '2026/9/29 阅读明细');
    expect(l10n.statsNoDataOnDate, '当日无阅读记录');
    expect(l10n.statsLegendLess, '较少');
    expect(l10n.statsLegendMore, '较多');
    expect(l10n.statsClearAllTitle, '清除全部统计');
    expect(l10n.statsClearAllConfirmMessage, '确定要清除所有阅读统计吗？此操作无法撤销。');
    expect(l10n.statsClearAllSuccess, '已清除全部阅读统计');
    expect(l10n.statsWeekdayMon, '一');
    expect(l10n.statsWeekdayWed, '三');
    expect(l10n.statsWeekdayFri, '五');
  });

  test('英文（en）統計字串齊備', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(l10n.statsScreenTitle, 'Reading Stats');
    expect(l10n.statsTotalDuration, 'Total Reading Time');
    expect(l10n.statsHoursMinutesFormat(1, 5), '1 hr 5 min');
    expect(l10n.statsMinutesFormat(7), '7 min');
    expect(l10n.statsDailyDetailsTitle('9/29/2026'), 'Reading on 9/29/2026');
    expect(l10n.statsNoDataOnDate, 'No reading on this day');
    expect(l10n.statsLegendLess, 'Less');
    expect(l10n.statsLegendMore, 'More');
    expect(l10n.statsClearAllTitle, 'Clear All Stats');
    expect(
      l10n.statsClearAllConfirmMessage,
      'Clear all reading stats? This cannot be undone.',
    );
    expect(l10n.statsClearAllSuccess, 'All reading stats cleared');
    expect(l10n.statsWeekdayMon, 'Mon');
    expect(l10n.statsWeekdayWed, 'Wed');
    expect(l10n.statsWeekdayFri, 'Fri');
  });
}
