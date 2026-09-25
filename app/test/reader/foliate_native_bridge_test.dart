import 'package:elinkbook/reader/custom_font.dart';
import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildFontFaceCss 只產生思源黑體／思源宋體 2 款內建字型的 @font-face 宣告（epic-48）', () {
    final css = buildFontFaceCss();
    expect(css, contains(
      "@font-face { font-family: 'SourceHanSansTC'; "
      "src: url('https://appassets.androidplatform.net/assets/fonts/SourceHanSansTC-VF.ttf'); }",
    ));
    expect(css, contains(
      "@font-face { font-family: 'SourceHanSerifTC'; "
      "src: url('https://appassets.androidplatform.net/assets/fonts/SourceHanSerifTC-VF.ttf'); }",
    ));
    expect(css, isNot(contains('GuanKiapTsingKhai')));
    expect('@font-face'.allMatches(css).length, 2);
  });

  test('buildFontFaceCss 帶入 customFonts 時，額外輸出自訂字型的 @font-face 宣告',
      () {
    final css = buildFontFaceCss(customFonts: const [
      CustomFont(
        id: 1,
        displayName: '我的字型',
        familyName: 'MyCustomFamily',
        fontUri: 'content://example/font1',
      ),
    ]);

    expect(css, contains(
      "@font-face { font-family: 'MyCustomFamily'; "
      "src: url('https://appassets.androidplatform.net/assets/custom-fonts/MyCustomFamily'); }",
    ));
    // 內建 2 款字型仍照舊輸出，不受影響。
    expect('@font-face'.allMatches(css).length, 3);
  });

  test('buildFontFaceCss 的自訂字型虛擬路徑對 family name 做 URL 編碼', () {
    final css = buildFontFaceCss(customFonts: const [
      CustomFont(
        id: 1,
        displayName: '含空白字型',
        familyName: 'My Custom Family',
        fontUri: 'content://example/font2',
      ),
    ]);

    expect(css, contains(
      "src: url('https://appassets.androidplatform.net/assets/custom-fonts/My%20Custom%20Family'); }",
    ));
  });

  test('buildFontFaceCss 未帶 customFonts 參數時（既有零參數呼叫）行為不變', () {
    final css = buildFontFaceCss();
    expect('@font-face'.allMatches(css).length, 2);
  });

  test('loadCustomFontBytes 呼叫 elinkbook/reader_resources 的 readCustomFontBytes',
      () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/reader_resources'),
      (call) async {
        captured = call;
        return Uint8List.fromList([4, 5, 6]);
      },
    );

    final bytes =
        await loadCustomFontBytes('content://example.provider/font1.ttf');

    expect(captured!.method, 'readCustomFontBytes');
    expect(captured!.arguments, {'uri': 'content://example.provider/font1.ttf'});
    expect(bytes, [4, 5, 6]);
  });

  test('loadAndroidAsset 呼叫 elinkbook/reader_resources 的 readAndroidAsset', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/reader_resources'),
      (call) async {
        captured = call;
        return Uint8List.fromList([1, 2, 3]);
      },
    );

    final bytes = await loadAndroidAsset('foliate/main.js');

    expect(captured!.method, 'readAndroidAsset');
    expect(captured!.arguments, {'path': 'foliate/main.js'});
    expect(bytes, [1, 2, 3]);
  });

  test('attachReaderView／detachReaderView 呼叫 elinkbook/volume_key 對應 case', () async {
    final calledMethods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/volume_key'),
      (call) async {
        calledMethods.add(call.method);
        return null;
      },
    );

    await attachReaderView();
    await detachReaderView();

    expect(calledMethods, ['attachReaderView', 'detachReaderView']);
  });

  test('loadFlutterFontAsset 透過 rootBundle 讀取 Flutter 字型 asset', () async {
    // epic-48 起內建字型一款都不打包，改用測試 fixture 驗證讀取行為本身。
    final bytes = await loadFlutterFontAsset('test/fixtures/sample.ttf');
    expect(bytes, isNotNull);
    expect(bytes!.isNotEmpty, isTrue);
  });

  test('內建字型一律不打包進 App（pubspec 未宣告，改由 epic-49 下載提供）', () async {
    for (final path in const [
      'assets/fonts/SourceHanSansTC-VF.ttf',
      'assets/fonts/SourceHanSerifTC-VF.ttf',
      'assets/fonts/GuanKiapTsingKhai.ttf',
      'assets/fonts/TaiwanPearl-Regular.ttf',
      'assets/fonts/GenRyuMinTW-Regular.ttf',
    ]) {
      expect(await loadFlutterFontAsset(path), isNull, reason: path);
    }
  });

  test('cacheBookForServing 呼叫 elinkbook/reader_resources_cache 的 cacheBookForServing', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/reader_resources_cache'),
      (call) async {
        captured = call;
        return '/fake/cache/dir/current.epub';
      },
    );

    // 使用 content:// URI 測試（不經過檔案存在檢查，直接呼叫原生端）
    final result = await cacheBookForServing('content://com.example.provider/book.epub', 'test_instance');

    expect(captured!.method, 'cacheBookForServing');
    expect(captured!.arguments, {
      'uri': 'content://com.example.provider/book.epub',
      'instanceId': 'test_instance',
      'extension': 'epub',
    });
    expect(result, '/fake/cache/dir/current.epub');
  });

  test('cacheBookForServing 對 CBZ 來源正確帶入 extension: cbz（epic-11 Issue 3，CBZ 開書前置修復）', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/reader_resources_cache'),
      (call) async {
        captured = call;
        return '/fake/cache/dir/current.cbz';
      },
    );

    await cacheBookForServing('content://com.example.provider/comic.cbz', 'test_instance');

    expect(captured!.arguments, {
      'uri': 'content://com.example.provider/comic.cbz',
      'instanceId': 'test_instance',
      'extension': 'cbz',
    });
  });

  group('cacheFileExtension', () {
    test('依副檔名推導，小寫化', () {
      expect(cacheFileExtension('foo/bar.CBZ'), 'cbz');
      expect(cacheFileExtension('foo/bar.epub'), 'epub');
      expect(cacheFileExtension('foo/bar.azw3'), 'azw3');
    });

    test('content:// URI 帶有可辨識副檔名時正確推導', () {
      expect(
        cacheFileExtension('content://com.example.provider/comic.cbz'),
        'cbz',
      );
    });

    test('無副檔名時退回 epub（維持 Issue 3 之前對 EPUB／AZW3 的既有行為）', () {
      expect(
        cacheFileExtension('content://com.android.providers.media.documents/document/document%3A1000001716'),
        'epub',
      );
    });
  });
}
