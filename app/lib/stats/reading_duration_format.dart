// app/lib/stats/reading_duration_format.dart
import '../l10n/app_localizations.dart';

/// 把閱讀秒數格式化成「X 小時 Y 分鐘」或「Y 分鐘」。
///
/// 秒數無條件捨去到分鐘；有紀錄但不滿 1 分鐘者顯示「1 分鐘」（避免出現
/// 「0 分鐘」，epic.md Issue 1 原型定案）；完全沒有紀錄（0 秒）顯示「0 分鐘」。
String formatReadingDuration(AppLocalizations l10n, int seconds) {
  // repository 保證秒數不為負；這裡仍防禦性歸零，避免顯示「-2 分鐘」。
  if (seconds <= 0) return l10n.statsMinutesFormat(0);
  var minutes = seconds ~/ 60;
  if (seconds > 0 && minutes == 0) minutes = 1;
  final hours = minutes ~/ 60;
  return hours > 0
      ? l10n.statsHoursMinutesFormat(hours, minutes % 60)
      : l10n.statsMinutesFormat(minutes);
}
