// 書檔供應（Book Serving）測試：快取複本＋（Windows）loopback 註冊的單一
// handle，一次 dispose() 全部清掉。
import 'dart:io';

import 'package:elinkbook/reader/book_serving.dart';
import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:elinkbook/reader/local_book_server.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Future<String?> Function(String, String) originalCache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('book_serving_test_');
    originalCache = cacheBookForServing;
  });

  tearDown(() {
    cacheBookForServing = originalCache;
    debugDefaultTargetPlatformOverride = null;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// 讓 cacheBookForServing 在 [root] 底下建一個實例子目錄與假書檔。
  String stubCache() {
    final dir = Directory('${root.path}/instance-1')..createSync();
    final file = File('${dir.path}/current.epub')..writeAsBytesSync([1, 2, 3]);
    cacheBookForServing = (a, b) async => file.path;
    return file.path;
  }

  test('快取失敗（回 null）時 open 回 null', () async {
    cacheBookForServing = (a, b) async => null;
    expect(await BookServing.open('/x.epub', 'i'), isNull);
  });

  test('Android：cacheDir 為快取檔所在目錄，沒有 bookBaseUri，dispose 刪目錄', () async {
    final cachedPath = stubCache();
    final serving = await BookServing.open('/x.epub', 'i');
    expect(serving, isNotNull);
    expect(serving!.cacheDir, File(cachedPath).parent.path);
    expect(serving.bookBaseUri, isNull);

    expect(serving.dispose(), isTrue);
    expect(Directory(serving.cacheDir).existsSync(), isFalse);
  });

  test('dispose 冪等：第二次不拋例外、不再動檔案', () async {
    stubCache();
    final serving = (await BookServing.open('/x.epub', 'i'))!;
    serving.dispose();
    expect(serving.dispose, returnsNormally);
  });

  test('目錄已被外部刪掉時 dispose 不拋例外，且回報 false（不是這次刪的）', () async {
    stubCache();
    final serving = (await BookServing.open('/x.epub', 'i'))!;
    Directory(serving.cacheDir).deleteSync(recursive: true);
    expect(serving.dispose(), isFalse);
  });

  group('Windows：向 loopback 註冊', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);

    test('成功時 bookBaseUri 來自註冊結果，dispose 釋放註冊並刪目錄', () async {
      final cachedPath = stubCache();
      var registeredPath = '';
      var handleDisposed = 0;
      final serving = await BookServing.open(
        '/x.epub',
        'i',
        register: (path) async {
          registeredPath = path;
          return BookServeHandle(
            bookBaseUri: Uri.parse('http://127.0.0.1:1/book/t/'),
            fileName: 'current.epub',
            onDispose: () => handleDisposed++,
          );
        },
      );
      expect(registeredPath, cachedPath);
      expect(serving!.bookBaseUri.toString(), 'http://127.0.0.1:1/book/t/');

      serving.dispose();
      serving.dispose();
      expect(handleDisposed, 1, reason: '冪等：註冊只釋放一次');
      expect(Directory(serving.cacheDir).existsSync(), isFalse);
    });

    test('註冊失敗時先刪掉剛複製的快取目錄，再把例外重拋（避免孤兒）', () async {
      final cachedPath = stubCache();
      await expectLater(
        BookServing.open('/x.epub', 'i',
            register: (_) async => throw StateError('bind failed')),
        throwsStateError,
      );
      expect(Directory(File(cachedPath).parent.path).existsSync(), isFalse);
    });
  });
}
