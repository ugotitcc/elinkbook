import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('每個 AppFont 都有對應的家族名稱字串，且彼此互不相同', () {
    const expected = {
      AppFont.sourceHanSans: 'SourceHanSansTC',
      AppFont.sourceHanSerif: 'SourceHanSerifTC',
      AppFont.guanKiapTsingKhai: 'GuanKiapTsingKhai',
      AppFont.taiwanPearl: 'TaiwanPearl',
      AppFont.genRyuMinTW: 'GenRyuMinTW',
      AppFont.bailuKai: 'BailuKai',
      AppFont.sweiB2Sugar: 'SweiB2SugarCJKtc',
    };
    // epic-49 Issue 8：epic-48 停用的 3 款恢復為可下載字型，順序即字型管理與閱讀設定的列出順序
    expect(AppFont.values, [
      AppFont.sourceHanSans,
      AppFont.sourceHanSerif,
      AppFont.guanKiapTsingKhai,
      AppFont.taiwanPearl,
      AppFont.genRyuMinTW,
      AppFont.bailuKai,
      AppFont.sweiB2Sugar,
    ]);
    for (final font in AppFont.values) {
      expect(font.familyName, expected[font]);
    }
    final allNames = AppFont.values.map((f) => f.familyName).toSet();
    expect(
      allNames.length,
      AppFont.values.length,
      reason: '家族名稱字串必須互不相同，否則原生端登記時後者會覆蓋前者',
    );
  });

  test('三種介面語系的顯示名稱（epic-49 Issue 8）', () {
    String namesIn(Locale locale) {
      final l10n = lookupAppLocalizations(locale);
      return AppFont.values.map((f) => f.displayName(l10n)).join('、');
    }

    expect(namesIn(const Locale('zh', 'TW')), '思源黑體、思源宋體、原俠正楷、台灣圓體、源流明體、白鷺楷、獅尾B2加糖宋體');
    expect(namesIn(const Locale('zh', 'CN')), '思源黑体、思源宋体、原侠正楷、台湾圆体、源流明体、白鹭楷、狮尾B2加糖宋体');
    expect(namesIn(const Locale('en')),
        'Source Han Sans、Source Han Serif、GuanKiapTsingKhai、TaiwanPearl、GenRyuMin TW、'
            'Bailu Kai、Swei B2 Sugar Song');
  });
}
