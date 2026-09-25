import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/app_font.dart';

void main() {
  test('每個 AppFont 都有對應的家族名稱字串，且彼此互不相同', () {
    const expected = {
      AppFont.sourceHanSans: 'SourceHanSansTC',
      AppFont.sourceHanSerif: 'SourceHanSerifTC',
    };
    // epic-48：內建字型目前只保留思源黑體／思源宋體，其餘 3 款已停用。
    expect(AppFont.values, [AppFont.sourceHanSans, AppFont.sourceHanSerif]);
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
}
