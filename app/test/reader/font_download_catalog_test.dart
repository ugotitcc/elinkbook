import 'dart:convert';
import 'dart:io';

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

    // epic-49 Issue 8：恢復的 3 款
    final guanKiap = fontDownloadSpecOf(AppFont.guanKiapTsingKhai);
    expect(guanKiap.publishPath, 'v1/GuanKiapTsingKhai.ttf');
    expect(guanKiap.sizeBytes, 14675776);
    expect(guanKiap.sha256,
        '758632243c499e431fd0c847f5e8c431acf59a9b41a26237a819466139994d38');

    final pearl = fontDownloadSpecOf(AppFont.taiwanPearl);
    expect(pearl.publishPath, 'v1/TaiwanPearl-Regular.ttf');
    expect(pearl.sizeBytes, 21704488);
    expect(pearl.sha256,
        '51b3c9a4ab1b6b45dcdad7c5ae93386aea399fd3dabb85d2ac41110dc57f211d');

    final genRyu = fontDownloadSpecOf(AppFont.genRyuMinTW);
    expect(genRyu.publishPath, 'v1/GenRyuMinTW-Regular.ttf');
    expect(genRyu.sizeBytes, 15976964);
    expect(genRyu.sha256,
        '9178c199d633075b8bb91902216c3e1bc977a11fde12471a2c9a250434402927');

    final bailu = fontDownloadSpecOf(AppFont.bailuKai);
    expect(bailu.publishPath, 'v1/BailuKai-Medium.ttf');
    expect(bailu.sizeBytes, 14711412);
    expect(bailu.sha256,
        '4678fe023d707ad29dadc39cdf5f64c7d3a0dfdc2b43520454de5d10f8defdcd');

    final swei = fontDownloadSpecOf(AppFont.sweiB2Sugar);
    expect(swei.publishPath, 'v1/SweiB2SugarCJKtc-Medium.ttf');
    expect(swei.sizeBytes, 25859984);
    expect(swei.sha256,
        'c0024df2d9c4996a4e8f44025a4e7eb729cb91540fb089555160e7c770e72c2e');
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

  test('基底網址是正式的下載服務（https，不是開發用的 .invalid 保留網域）（epic-49 Issue 4）', () {
    final uri = Uri.parse(kFontDownloadBaseUrl);
    expect(uri.scheme, 'https');
    expect(uri.host, isNot(endsWith('.invalid')));
    expect(uri.host, 'elinkbook-fonts.huthief.workers.dev');
  });

  test('字型目錄與 fonts-cdn/fonts.json 的路徑、大小、SHA-256 完全一致（工單審查 I-1）', () {
    // flutter test 的工作目錄是 app/，字型清單在 repo 根目錄的 fonts-cdn/
    final manifest = jsonDecode(File('../fonts-cdn/fonts.json').readAsStringSync())
        as Map<String, dynamic>;
    final entries = {
      for (final entry in (manifest['fonts'] as List).cast<Map<String, dynamic>>())
        entry['id'] as String: entry,
    };
    for (final font in AppFont.values) {
      final entry = entries[font.name];
      expect(entry, isNotNull, reason: '${font.name} 不在 fonts-cdn/fonts.json 中');
      final spec = fontDownloadSpecOf(font);
      expect(spec.publishPath, entry!['path'], reason: font.name);
      expect(spec.sizeBytes, entry['bytes'], reason: font.name);
      expect(spec.sha256, entry['sha256'], reason: font.name);
    }
  });
}
