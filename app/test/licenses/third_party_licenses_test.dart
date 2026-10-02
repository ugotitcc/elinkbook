import 'dart:convert';

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
    test('Issue 1 範圍：5 項程式元件，順序與名稱符合 spec', () {
      expect(kThirdPartyLicenses.map((l) => l.packageName).toList(), [
        'foliate-js',
        'zip.js',
        'fflate',
        'OpenCC',
        'Readium kotlin-toolkit',
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
    test('以真實 rootBundle 登錄：5 筆、packages 與清單一致、全文含上游版權關鍵字', () async {
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
      for (final text in textByPackage.values) {
        expect(text.trim(), isNotEmpty);
      }
    });

    test('某個 asset 讀不到時，其他 4 筆仍登錄成功', () async {
      final texts = {
        for (final l in kThirdPartyLicenses)
          l.assetPath: '${l.packageName} 授權全文',
      }..remove(kThirdPartyLicenses[1].assetPath); // 拿掉 zip.js

      registerThirdPartyLicenses(bundle: _FakeBundle(texts));

      final entries = await _readAllLicenses();
      expect(entries.map((e) => e.packages.single).toList(), [
        'foliate-js',
        'fflate',
        'OpenCC',
        'Readium kotlin-toolkit',
      ]);
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
      expect(entries.length, 4);
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
      expect(entries.length, 4);
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
}
