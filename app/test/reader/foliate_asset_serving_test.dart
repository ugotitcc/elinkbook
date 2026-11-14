// Foliate 資源供應（Foliate Asset Serving）的純值測試。
//
// 重點：這是「請求路徑進、回應純值出」的 interface，不需要 WebView；
// 過去四個 WebView 使用者的攔截回呼從沒被測試觸發過。
import 'dart:convert';
import 'dart:typed_data';

import 'package:elinkbook/reader/foliate_asset_serving.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 記錄被詢問的相對路徑，並依表回傳位元組（沒有就回 null）。
  Future<Uint8List?> Function(String) fakeLoader(
    Map<String, String> files,
    List<String> asked,
  ) {
    return (relativePath) async {
      asked.add(relativePath);
      final content = files[relativePath];
      return content == null ? null : Uint8List.fromList(utf8.encode(content));
    };
  }

  group('serveFoliateAsset', () {
    test('.js 回 text/javascript，內容原樣回傳', () async {
      final asked = <String>[];
      final res = await serveFoliateAsset(
        '/assets/foliate/main.js',
        loadAsset: fakeLoader({'foliate/main.js': 'var a=1;'}, asked),
      );
      expect(res, isNotNull);
      expect(res!.statusCode, 200);
      expect(res.contentType, 'text/javascript');
      expect(utf8.decode(res.data), 'var a=1;');
    });

    test('.css 回 text/css（過去三處誤回 text/html）', () async {
      final res = await serveFoliateAsset(
        '/assets/foliate/style.css',
        loadAsset: fakeLoader({'foliate/style.css': 'a{}'}, []),
      );
      expect(res!.contentType, 'text/css');
    });

    test('.html 與未知副檔名維持 text/html', () async {
      final html = await serveFoliateAsset(
        '/assets/foliate/index.html',
        loadAsset: fakeLoader({'foliate/index.html': '<p/>'}, []),
      );
      final other = await serveFoliateAsset(
        '/assets/foliate/data.bin',
        loadAsset: fakeLoader({'foliate/data.bin': 'x'}, []),
      );
      expect(html!.contentType, 'text/html');
      expect(other!.contentType, 'text/html');
    });

    test('相對路徑為 foliate/ 加上前綴之後的部分，含 legacy 與 vendor 子目錄', () async {
      final asked = <String>[];
      final loader = fakeLoader({
        'foliate/legacy/view.js': 'l',
        'foliate/vendor/zip.js': 'z',
      }, asked);
      await serveFoliateAsset('/assets/foliate/legacy/view.js', loadAsset: loader);
      await serveFoliateAsset('/assets/foliate/vendor/zip.js', loadAsset: loader);
      expect(asked, ['foliate/legacy/view.js', 'foliate/vendor/zip.js']);
    });

    test('找不到資源回明確 404 與空內容，不回 null（避免 WebView 連網）', () async {
      final res = await serveFoliateAsset(
        '/assets/foliate/missing.js',
        loadAsset: fakeLoader({}, []),
      );
      expect(res, isNotNull);
      expect(res!.statusCode, 404);
      expect(res.data, isEmpty);
    });

    test('不在 /assets/foliate/ 底下的路徑回 null（不是本 module 的事）', () async {
      final asked = <String>[];
      final loader = fakeLoader({}, asked);
      expect(await serveFoliateAsset('/book/current.epub', loadAsset: loader), isNull);
      expect(await serveFoliateAsset('/assets/custom-fonts/x', loadAsset: loader), isNull);
      expect(await serveFoliateAsset('/assets/foliate', loadAsset: loader), isNull);
      expect(asked, isEmpty, reason: '不該為不相關路徑讀任何資產');
    });

    test('讀取資產拋例外時視為找不到，回 404', () async {
      final res = await serveFoliateAsset(
        '/assets/foliate/main.js',
        loadAsset: (_) async => throw StateError('io'),
      );
      expect(res!.statusCode, 404);
    });
  });

  group('toWebResourceResponse', () {
    test('200：保留 MIME 與內容，且不設 statusCode／reasonPhrase／headers（與變更前一致，Android 走三參數建構子）', () {
      final res = FoliateAssetResponse(
        statusCode: 200,
        contentType: 'text/css',
        data: Uint8List.fromList([1, 2, 3]),
      ).toWebResourceResponse();
      expect(res.contentType, 'text/css');
      expect(res.data, Uint8List.fromList([1, 2, 3]));
      expect(res.statusCode, isNull);
      expect(res.reasonPhrase, isNull);
      expect(res.headers, isNull);
    });

    test('404：statusCode、reasonPhrase、headers 三者齊備（外掛要求一起設）', () {
      final res = FoliateAssetResponse(
        statusCode: 404,
        contentType: 'text/plain',
        data: Uint8List(0),
      ).toWebResourceResponse();
      expect(res.statusCode, 404);
      expect(res.reasonPhrase, 'Not Found');
      expect(res.headers, isNotNull);
      expect(res.data, isEmpty);
    });
  });
}
