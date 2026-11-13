// 舊版 WebView（Chrome 83，例如 iReader Ocean 4 Plus）降級副本的守衛測試。
//
// 這些測試不能代替真機驗證（無法在 Dart 測試裡執行 Chrome 83），只擋「忘了重新
// 產生降級副本」與「載入分流邏輯被改掉」這兩種回歸。真機結果見 tool/README.md。
import 'dart:io';

import 'package:elinkbook/library/android_epub_metadata.dart';
import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final foliateDir = Directory('android/app/src/main/assets/foliate');
  final legacyDir = Directory('${foliateDir.path}/legacy');

  List<String> relativeJsFiles(Directory root, {bool skipLegacy = false}) {
    return root
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.js'))
        .map((f) => f.path
            .substring(root.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/'))
        .where((p) => !(skipLegacy && p.startsWith('legacy/')))
        .toList()
      ..sort();
  }

  group('foliate legacy 降級副本', () {
    test('每個原始 .js 都有對應的降級副本（升級 foliate 後忘了重新產生會失敗）', () {
      final source = relativeJsFiles(foliateDir, skipLegacy: true);
      final legacy = relativeJsFiles(legacyDir);
      expect(source, isNotEmpty);
      expect(legacy, source);
    });

    test('降級副本沒有殘留私有方法宣告（Chrome 84 才支援）', () {
      // 行首的 `#name(`／`static #name(`／`async #name(` 才是方法宣告；
      // 註解與 CSS 字串裡的 `#id` 不會落在這個形狀。
      final privateMethod =
          RegExp(r'^\s*(static\s+|async\s+|get\s+|set\s+)*#[A-Za-z_]\w*\s*\(',
              multiLine: true);
      for (final file in legacyDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.js'))) {
        expect(privateMethod.hasMatch(file.readAsStringSync()), isFalse,
            reason: '${file.path} 仍含私有方法宣告，請重新執行 tool/foliate_legacy 的 pnpm build');
      }
    });

    test('降級副本沒有 Chrome 88 才支援的 CSS :is()', () {
      final paginator =
          File('${legacyDir.path}/paginator.js').readAsStringSync();
      expect(paginator, isNot(contains(':is(#header, #footer)')));
    });
  });

  group('載入分流', () {
    test('index.html 依 Chrome 主版號 < 84 載入 legacy/，否則載入原始 main.js', () {
      final html = File('${foliateDir.path}/index.html').readAsStringSync();
      expect(html, contains('Chrome\\/(\\d+)'));
      expect(html, contains('< 84'));
      expect(html, contains("'./legacy/'"));
      expect(html, contains("'main.js'"));
    });

    test('探針頁依版本載入 legacy 版，且不使用頂層 await（Chrome 89）', () {
      final html = androidProbeHtml(1);
      expect(html, contains('/assets/foliate/legacy/metadata-probe.js'));
      expect(html, contains('/assets/foliate/metadata-probe.js'));
      expect(html, contains('chromeMajor < 84'));
      // 呼叫探針的 await 必須在 async IIFE 之內（出現在 `(async () => {` 之後）。
      final iife = html.indexOf('(async () => {');
      expect(iife, greaterThan(-1));
      expect(html.indexOf('await readBookMetadataByRange'), greaterThan(iife));
      expect(html.indexOf('await import(probePath)'), greaterThan(iife));
    });

    test('esCompatPolyfillJs 補上 replaceChildren（Chrome 86）', () {
      expect(esCompatPolyfillJs, contains('replaceChildren'));
    });
  });
}
