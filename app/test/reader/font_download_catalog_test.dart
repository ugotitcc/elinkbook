import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/font_download_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('啟用中的字型對應 spec.md「字型目錄」表格的數值（epic-49）', () {
    final sans = fontDownloadSpecOf(AppFont.sourceHanSans);
    expect(sans.publishPath, 'v1/SourceHanSansTC-VF.ttf');
    expect(sans.sizeBytes, 36034016);
    expect(sans.sha256,
        '1a273a56aa47250c7af95e461ee0c8236c60d7141e14a37bd18baccb1e851b19');

    final serif = fontDownloadSpecOf(AppFont.sourceHanSerif);
    expect(serif.publishPath, 'v1/SourceHanSerifTC-VF.ttf');
    expect(serif.sizeBytes, 59898316);
    expect(serif.sha256,
        '71354ed752104c8a3cbcff18943c6110d179d01cc6eaaf1aff7ea14c4a447879');
  });

  test('每款字型的發布路徑互不相同，格式為 v<N>/<檔名>.ttf，雜湊為 64 字元小寫十六進位', () {
    final specs = AppFont.values.map(fontDownloadSpecOf).toList();
    expect(specs.map((s) => s.publishPath).toSet().length, specs.length);
    for (final spec in specs) {
      expect(spec.publishPath, matches(RegExp(r'^v[1-9][0-9]*/[A-Za-z0-9._-]+\.ttf$')));
      expect(spec.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(spec.sizeBytes, greaterThan(0));
    }
  });

  test('基底網址以斜線結尾，讓 Uri.resolve 能正確接上發布路徑', () {
    expect(kFontDownloadBaseUrl, endsWith('/'));
    expect(Uri.parse(kFontDownloadBaseUrl).resolve('v1/A.ttf').path, '/v1/A.ttf');
  });
}
