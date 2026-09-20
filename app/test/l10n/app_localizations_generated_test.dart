import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';

void main() {
  test('三語言 ARB 皆能正確產生 groupUncategorized 字串', () {
    expect(
      lookupAppLocalizations(const Locale('zh', 'TW')).groupUncategorized,
      '未分類',
    );
    expect(
      lookupAppLocalizations(const Locale('zh', 'CN')).groupUncategorized,
      '未分类',
    );
    expect(
      lookupAppLocalizations(const Locale('en')).groupUncategorized,
      'Uncategorized',
    );
  });

  test('三語言 ARB 皆能正確產生 close 字串（/receiving-code-review M-4 修正）', () {
    expect(lookupAppLocalizations(const Locale('zh', 'TW')).close, '關閉');
    expect(lookupAppLocalizations(const Locale('zh', 'CN')).close, '关闭');
    expect(lookupAppLocalizations(const Locale('en')).close, 'Close');
  });
}
