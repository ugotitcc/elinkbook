import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/stats/reading_duration_format.dart';

void main() {
  final tw = lookupAppLocalizations(const Locale('zh', 'TW'));
  final cn = lookupAppLocalizations(const Locale('zh', 'CN'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('0 秒顯示「0 分鐘」；負數秒數防禦性視為 0', () {
    expect(formatReadingDuration(tw, 0), '0 分鐘');
    expect(formatReadingDuration(tw, -120), '0 分鐘');
  });

  test('有紀錄但不滿 1 分鐘顯示「1 分鐘」（原型定案，避免出現 0 分鐘）', () {
    expect(formatReadingDuration(tw, 1), '1 分鐘');
    expect(formatReadingDuration(tw, 59), '1 分鐘');
  });

  test('未滿 1 小時只顯示分鐘（無條件捨去秒）', () {
    expect(formatReadingDuration(tw, 60), '1 分鐘');
    expect(formatReadingDuration(tw, 119), '1 分鐘');
    expect(formatReadingDuration(tw, 3599), '59 分鐘');
  });

  test('滿 1 小時顯示「X 小時 Y 分鐘」，整點也顯示「0 分鐘」', () {
    expect(formatReadingDuration(tw, 3600), '1 小時 0 分鐘');
    expect(formatReadingDuration(tw, 3900), '1 小時 5 分鐘');
    expect(formatReadingDuration(tw, 7384), '2 小時 3 分鐘');
  });

  test('簡體中文與英文', () {
    expect(formatReadingDuration(cn, 3900), '1 小时 5 分钟');
    expect(formatReadingDuration(cn, 600), '10 分钟');
    expect(formatReadingDuration(en, 3900), '1 hr 5 min');
    expect(formatReadingDuration(en, 600), '10 min');
  });
}
