import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/library/models/book_group.dart';

void main() {
  group('isReservedGroupName', () {
    test('三語言保留字（含大小寫變體與前後空白）皆判定為保留名稱', () {
      for (final name in [
        '未分類',
        '未分类',
        'uncategorized',
        'UNCATEGORIZED',
        'Uncategorized',
        '  uncategorized  ',
        '  未分類  ',
        '  未分类  ',
      ]) {
        expect(isReservedGroupName(name), isTrue, reason: '「$name」應判定為保留名稱');
      }
    });

    test('一般分類名稱不誤判為保留名稱', () {
      for (final name in ['小說', 'Novels', '未分類上', 'uncategorized2', '']) {
        expect(isReservedGroupName(name), isFalse, reason: '「$name」不應判定為保留名稱');
      }
    });
  });

  group('localizeGroupName / BookGroupL10n.displayName', () {
    test('系統保留分類依三語言正確轉譯', () {
      final zhTW = lookupAppLocalizations(const Locale('zh', 'TW'));
      final zhCN = lookupAppLocalizations(const Locale('zh', 'CN'));
      final en = lookupAppLocalizations(const Locale('en'));

      expect(localizeGroupName(BookGroup.uncategorized, zhTW), '未分類');
      expect(localizeGroupName(BookGroup.uncategorized, zhCN), '未分类');
      expect(localizeGroupName(BookGroup.uncategorized, en), 'Uncategorized');
    });

    test('一般自訂分類名稱原樣不變，不受介面語言影響', () {
      final zhTW = lookupAppLocalizations(const Locale('zh', 'TW'));
      final en = lookupAppLocalizations(const Locale('en'));

      expect(localizeGroupName('小說', zhTW), '小說');
      expect(localizeGroupName('小說', en), '小說');
    });

    test('BookGroupL10n.displayName() 轉發至 localizeGroupName()', () {
      final zhCN = lookupAppLocalizations(const Locale('zh', 'CN'));
      expect(
        const BookGroup(BookGroup.uncategorized).displayName(zhCN),
        '未分类',
      );
      expect(const BookGroup('奇幻').displayName(zhCN), '奇幻');
    });
  });
}
