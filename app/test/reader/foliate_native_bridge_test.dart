import 'dart:async';

import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/custom_font.dart';
import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:elinkbook/reader/font_download_catalog.dart';
import 'package:elinkbook/reader/reader_console_log.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('沒有已下載的內建字型時，不輸出任何內建字型規則（epic-49 Issue 4）', () {
    final css = buildFontFaceCss();
    expect('@font-face'.allMatches(css).length, 0);
    expect(css, isNot(contains('/assets/fonts/')));
  });

  test('只下載思源黑體時，只輸出一條規則，網址指向 /downloaded-fonts/v1/…', () {
    final css = buildFontFaceCss(installedFonts: {AppFont.sourceHanSans});
    expect(css,
        "@font-face { font-family: 'SourceHanSansTC'; "
        "src: url('https://appassets.androidplatform.net/downloaded-fonts/v1/SourceHanSansTC-VF.ttf'); }");
    expect(css, isNot(contains('SourceHanSerifTC')));
  });

  test('網址等於前綴加上字型目錄的 publishPath，和 store 存檔路徑一致（審查重點 3）', () {
    final css = buildFontFaceCss(installedFonts: AppFont.values.toSet());
    expect('@font-face'.allMatches(css).length, AppFont.values.length);
    for (final font in AppFont.values) {
      expect(css, contains(
          "src: url('https://appassets.androidplatform.net$kDownloadedFontsPathPrefix"
          "${fontDownloadSpecOf(font).publishPath}')"));
    }
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
    // 沒有傳入已下載字型，所以只有自訂字型這一條規則。
    expect('@font-face'.allMatches(css).length, 1);
  });

  test('已下載字型與自訂字型同時存在時，兩者的規則都輸出，自訂字型規則不受影響', () {
    final css = buildFontFaceCss(
      installedFonts: {AppFont.sourceHanSerif},
      customFonts: const [
        CustomFont(
          id: 1,
          displayName: '我的字型',
          familyName: 'MyCustomFamily',
          fontUri: 'content://example/font1',
        ),
      ],
    );
    expect('@font-face'.allMatches(css).length, 2);
    expect(css, contains('/downloaded-fonts/v1/SourceHanSerifTC-VF.ttf'));
    expect(css, contains(
      "@font-face { font-family: 'MyCustomFamily'; "
      "src: url('https://appassets.androidplatform.net/assets/custom-fonts/MyCustomFamily'); }",
    ));
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

  test('內建字型一律不打包進 App（pubspec 未宣告，改由 epic-49 下載提供）', () async {
    for (final path in const [
      'assets/fonts/SourceHanSansTC-VF.ttf',
      'assets/fonts/SourceHanSerifTC-VF.ttf',
      'assets/fonts/GuanKiapTsingKhai.ttf',
      'assets/fonts/TaiwanPearl-Regular.ttf',
      'assets/fonts/GenRyuMinTW-Regular.ttf',
    ]) {
      await expectLater(() => rootBundle.load(path), throwsA(anything), reason: path);
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

  group('probeStorageAccessViaChannel（epic-15-storage-permission Issue 1）', () {
    const channel = MethodChannel('elinkbook/reader_resources_cache');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    for (final entry in {
      'readable': StorageAccessProbeResult.readable,
      'permissionRevoked': StorageAccessProbeResult.permissionRevoked,
      'fileNotFound': StorageAccessProbeResult.fileNotFound,
      'unknownError': StorageAccessProbeResult.unknownError,
    }.entries) {
      test('原生回傳 "${entry.key}" 對應到 ${entry.value}', () async {
        MethodCall? captured;
        messenger.setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return entry.key;
        });

        final result = await probeStorageAccessViaChannel(
            'content://com.example.provider/book.epub');

        expect(result, entry.value);
        expect(captured!.method, 'probeUriAccess');
        expect(captured!.arguments,
            {'uri': 'content://com.example.provider/book.epub'});
      });
    }

    test('無法辨識的代碼回傳 unknownError', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => 'somethingNew');
      expect(await probeStorageAccessViaChannel('content://x/a.epub'),
          StorageAccessProbeResult.unknownError);
    });

    test('原生回傳 null 時回傳 unknownError', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await probeStorageAccessViaChannel('content://x/a.epub'),
          StorageAccessProbeResult.unknownError);
    });

    test('原生回傳非字串（型別不符）回傳 unknownError，不拋出 TypeError', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => 42);
      expect(await probeStorageAccessViaChannel('content://x/a.epub'),
          StorageAccessProbeResult.unknownError);
    });

    test('PlatformException 回傳 unknownError', () async {
      messenger.setMockMethodCallHandler(
          channel, (call) async => throw PlatformException(code: 'boom'));
      expect(await probeStorageAccessViaChannel('content://x/a.epub'),
          StorageAccessProbeResult.unknownError);
    });

    test('通道沒有原生實作（MissingPluginException）回傳 unknownError',
        () async {
      // 不註冊任何 handler：對應 widget test／無原生實作的環境。
      expect(await probeStorageAccessViaChannel('content://x/a.epub'),
          StorageAccessProbeResult.unknownError);
    });

    test('原生逾時未回應時回傳 unknownError', () async {
      final never = Completer<String>();
      messenger.setMockMethodCallHandler(channel, (call) => never.future);
      expect(
        await probeStorageAccessViaChannel('content://x/a.epub',
            timeout: const Duration(milliseconds: 50)),
        StorageAccessProbeResult.unknownError,
      );
    });

    test('非 content:// 輸入不呼叫通道，直接回傳 unknownError', () async {
      var called = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        called = true;
        return 'readable';
      });
      expect(await probeStorageAccessViaChannel('/data/user/0/app/book.epub'),
          StorageAccessProbeResult.unknownError);
      expect(called, isFalse);
    });

    test('結果寫入 ReaderConsoleLog', () async {
      ReaderConsoleLog.clear();
      messenger.setMockMethodCallHandler(
          channel, (call) async => 'permissionRevoked');
      await probeStorageAccessViaChannel('content://x/a.epub');
      expect(
        ReaderConsoleLog.entries.value.last,
        contains('content://x/a.epub → permissionRevoked'),
      );
    });

    test('probeStorageAccess 預設指向 probeStorageAccessViaChannel', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => 'readable');
      expect(await probeStorageAccess('content://x/a.epub'),
          StorageAccessProbeResult.readable);
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
