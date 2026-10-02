import 'dart:convert';
import 'dart:io';

import 'package:elinkbook/licenses/third_party_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假 bundle：[texts] 內有的路徑回傳該文字，[throwing] 內的路徑丟出例外，
/// 其餘路徑視為找不到（丟出 FlutterError，與真實 bundle 行為一致）。
class _FakeBundle extends AssetBundle {
  _FakeBundle(this.texts, {this.throwing = const {}});

  final Map<String, String> texts;
  final Set<String> throwing;

  @override
  Future<ByteData> load(String key) async {
    if (throwing.contains(key)) throw StateError('模擬讀取失敗：$key');
    final text = texts[key];
    if (text == null) throw FlutterError('Unable to load asset: $key');
    final bytes = Uint8List.fromList(utf8.encode(text));
    return ByteData.sublistView(bytes);
  }

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) async => parser(await loadString(key));
}

/// 讀出目前登錄的所有授權項目。
Future<List<LicenseEntry>> _readAllLicenses() =>
    LicenseRegistry.licenses.toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 清掉其他登錄（含 Flutter 自帶的），只留本測試登錄的。
    LicenseRegistry.reset();
  });

  tearDown(() {
    // 還原全域狀態，避免本檔登錄的 collector 殘留影響後續測試。
    LicenseRegistry.reset();
  });

  group('kThirdPartyLicenses 清單', () {
    test('10 項：5 項程式元件加 5 款字型，順序與名稱符合 spec', () {
      expect(kThirdPartyLicenses.map((l) => l.packageName).toList(), [
        'foliate-js',
        'zip.js',
        'fflate',
        'OpenCC',
        'Readium kotlin-toolkit',
        '思源黑體',
        '思源宋體',
        '原俠正楷',
        '台灣圓體',
        '源流明體',
      ]);
    });

    test('packageName 與 assetPath 皆不重複', () {
      final names = kThirdPartyLicenses.map((l) => l.packageName).toSet();
      final paths = kThirdPartyLicenses.map((l) => l.assetPath).toSet();
      expect(names.length, kThirdPartyLicenses.length);
      expect(paths.length, kThirdPartyLicenses.length);
    });
  });

  group('registerThirdPartyLicenses', () {
    test('以真實 rootBundle 登錄：10 筆、packages 與清單一致、全文含上游版權關鍵字', () async {
      registerThirdPartyLicenses();

      final entries = await _readAllLicenses();

      expect(
        entries.map((e) => e.packages.single).toList(),
        kThirdPartyLicenses.map((l) => l.packageName).toList(),
      );
      final textByPackage = {
        for (final e in entries)
          e.packages.single: e.paragraphs.map((p) => p.text).join('\n'),
      };
      // 每筆全文非空，且含上游原檔的關鍵字（證明 asset 路徑與內容正確）
      expect(textByPackage['foliate-js'], contains('John Factotum'));
      expect(textByPackage['zip.js'], contains('Gildas Lormeau'));
      expect(textByPackage['fflate'], contains('Arjun Barrett'));
      expect(textByPackage['OpenCC'], contains('Apache License'));
      expect(textByPackage['Readium kotlin-toolkit'], contains('Readium'));
      // 5 款字型：皆為 SIL OFL 1.1，並含各自上游的版權關鍵字
      for (final font in ['思源黑體', '思源宋體', '原俠正楷', '台灣圓體', '源流明體']) {
        expect(
          textByPackage[font],
          contains('SIL Open Font License'),
          reason: '$font 授權全文應含 OFL 條款',
        );
      }
      expect(textByPackage['思源黑體'], contains('Adobe'));
      expect(textByPackage['思源宋體'], contains('Adobe'));
      expect(textByPackage['源流明體'], contains('Adobe'));
      expect(textByPackage['原俠正楷'], contains('Tony Huang'));
      // 中文 Reserved Font Name 要能正確讀出（UTF-8）
      expect(textByPackage['原俠正楷'], contains('原俠'));
      for (final text in textByPackage.values) {
        expect(text.trim(), isNotEmpty);
      }
    });

    test('台灣圓體：原檔沒有版權行，不補寫版權人／年份；僅附 README 來源說明', () async {
      registerThirdPartyLicenses();

      final entries = await _readAllLicenses();
      final text = entries
          .firstWhere((e) => e.packages.single == '台灣圓體')
          .paragraphs
          .map((p) => p.text)
          .join('\n');

      expect(text, contains('SIL Open Font License'));
      expect(text, contains('改造Adobe和Google所開發、發表的「思源黑體」字型'));
      // 沒有「Copyright 2022」或「Copyright (c) 2022」這種「版權年份＋持有人」行。
      // 注意不能檢查「以 Copyright 開頭」：OFL 條款本文的「Copyright Holder...」
      // 本來就會換行後出現在行首。
      expect(
        RegExp(
          r'^\s*Copyright\s+(\(c\)\s*)?\d{4}',
          multiLine: true,
          caseSensitive: false,
        ).hasMatch(text),
        isFalse,
      );
    });

    test('某個 asset 讀不到時，其他筆仍登錄成功', () async {
      final texts = {
        for (final l in kThirdPartyLicenses)
          l.assetPath: '${l.packageName} 授權全文',
      }..remove(kThirdPartyLicenses[1].assetPath); // 拿掉 zip.js

      registerThirdPartyLicenses(bundle: _FakeBundle(texts));

      final entries = await _readAllLicenses();
      expect(
        entries.map((e) => e.packages.single).toList(),
        kThirdPartyLicenses
            .map((l) => l.packageName)
            .where((n) => n != 'zip.js')
            .toList(),
      );
    });

    test('某個 asset 丟出非 FlutterError 的任意例外，也只略過該筆', () async {
      final texts = {
        for (final l in kThirdPartyLicenses)
          l.assetPath: '${l.packageName} 授權全文',
      };

      registerThirdPartyLicenses(
        bundle: _FakeBundle(
          texts,
          throwing: {kThirdPartyLicenses[0].assetPath},
        ),
      );

      final entries = await _readAllLicenses();
      expect(entries.length, kThirdPartyLicenses.length - 1);
      expect(
        entries.map((e) => e.packages.single),
        isNot(contains('foliate-js')),
      );
    });

    test('asset 內容是空白時略過，不登錄空授權', () async {
      final texts = {
        for (final l in kThirdPartyLicenses)
          l.assetPath: '${l.packageName} 授權全文',
        kThirdPartyLicenses[2].assetPath: '  \n\t\n',
      };

      registerThirdPartyLicenses(bundle: _FakeBundle(texts));

      final entries = await _readAllLicenses();
      expect(entries.length, kThirdPartyLicenses.length - 1);
      expect(entries.map((e) => e.packages.single), isNot(contains('fflate')));
    });

    test('授權全文保留中文與段落分隔', () async {
      // LicenseEntryWithLineBreaks 會把「同段內的單一換行」折成空格，
      // 只有空行才是段落分隔，所以用空行測試段落保留。
      final texts = {
        for (final l in kThirdPartyLicenses)
          l.assetPath: '第一段\n\n第二段 版權所有',
      };

      registerThirdPartyLicenses(bundle: _FakeBundle(texts));

      final entries = await _readAllLicenses();
      final joined = entries.first.paragraphs.map((p) => p.text).join('\n');
      expect(joined, contains('第一段\n第二段 版權所有'));
    });
  });

  group('字型授權 asset 與 fonts-cdn 原檔一致', () {
    // asset 檔名（不含 .txt） -> fonts-cdn/fonts/licenses/ 內的原檔名（不含 .txt）。
    // 這張對照表刻意獨立於 kThirdPartyLicenses，讓本 group 在清單尚未加入字型時就能先紅燈。
    // 台灣圓體另有附加的 README 來源說明，不在此表，見下方獨立測試。
    const fontLicenseSources = {
      'font-source-han-sans': 'SourceHanSans-LICENSE',
      'font-source-han-serif': 'SourceHanSerif-LICENSE',
      'font-guan-kiap-tsing-khai': 'GuanKiapTsingKhai-LICENSE',
      'font-gen-ryu-min': 'GenRyuMin-LICENSE',
    };

    // git 索引內是 LF，但 Windows（autocrlf=true）工作目錄是 CRLF；
    // 比對前統一成 LF，避免在不同平台或 CI 上誤判。
    String normalize(String s) => s.replaceAll('\r\n', '\n');

    for (final entry in fontLicenseSources.entries) {
      test('${entry.key}.txt 內容與 fonts-cdn 的 ${entry.value}.txt 相同', () {
        // flutter test 的工作目錄是 app/，字型授權原檔在 repo 根目錄的 fonts-cdn/
        final asset = File('assets/licenses/${entry.key}.txt');
        final source = File('../fonts-cdn/fonts/licenses/${entry.value}.txt');

        expect(asset.existsSync(), isTrue, reason: '${asset.path} 不存在');
        expect(source.existsSync(), isTrue, reason: '${source.path} 不存在');
        expect(
          normalize(asset.readAsStringSync()),
          normalize(source.readAsStringSync()),
        );
      });
    }

    test('font-taiwan-pearl.txt 以 fonts-cdn 的 TaiwanPearl-LICENSE.txt 全文開頭，並附 README 來源說明', () {
      final asset = File('assets/licenses/font-taiwan-pearl.txt');
      final source = File('../fonts-cdn/fonts/licenses/TaiwanPearl-LICENSE.txt');

      expect(asset.existsSync(), isTrue, reason: '${asset.path} 不存在');
      expect(source.existsSync(), isTrue, reason: '${source.path} 不存在');
      final assetText = normalize(asset.readAsStringSync());
      final sourceText = normalize(source.readAsStringSync());

      // 授權原文逐字不動（design Q3），說明只能附加在後面
      expect(assetText.startsWith(sourceText), isTrue);
      final note = assetText.substring(sourceText.length);
      expect(note, contains('來源說明'));
      expect(note, contains('非 SIL OFL 授權條款的一部分'));
      expect(note, contains('改造Adobe和Google所開發、發表的「思源黑體」字型'));
      expect(
        note,
        contains('https://github.com/max32002/TaiwanPearl/blob/master/README.md'),
      );
    });
  });
}
