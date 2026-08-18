import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/remote/remote_thumbnail_cache.dart';

void main() {
  final server = RemoteServerProfile(
    id: 'srv1',
    name: '家用 NAS',
    baseUrl: 'http://192.168.1.100:8080/opds',
    type: RemoteServerType.opds,
    allowInsecure: false,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
  );

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('remote_thumbnail_cache_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('兩層皆未命中時呼叫網路擷取函式，結果寫入磁碟快取', () async {
    final networkCalls = <String>[];
    final cache = RemoteThumbnailCacheImpl(
      cacheDir: tempDir,
      fetchOverNetwork: (server, url, headers) async {
        networkCalls.add(url);
        return Uint8List.fromList([1, 2, 3]);
      },
    );

    final bytes = await cache.fetch(server, 'http://x/cover.jpg', const {});

    expect(bytes, [1, 2, 3]);
    expect(networkCalls, ['http://x/cover.jpg']);
    expect(tempDir.listSync(), isNotEmpty);
  });

  test('記憶體快取命中時不呼叫網路擷取函式', () async {
    final networkCalls = <String>[];
    final cache = RemoteThumbnailCacheImpl(
      cacheDir: tempDir,
      fetchOverNetwork: (server, url, headers) async {
        networkCalls.add(url);
        return Uint8List.fromList([1, 2, 3]);
      },
    );

    await cache.fetch(server, 'http://x/cover.jpg', const {});
    final bytes = await cache.fetch(server, 'http://x/cover.jpg', const {});

    expect(bytes, [1, 2, 3]);
    expect(networkCalls, ['http://x/cover.jpg']);
  });

  test('記憶體未命中但磁碟命中時，讀取磁碟內容且不呼叫網路擷取函式', () async {
    var networkCallCount = 0;
    final cacheA = RemoteThumbnailCacheImpl(
      cacheDir: tempDir,
      fetchOverNetwork: (server, url, headers) async {
        networkCallCount++;
        return Uint8List.fromList([9, 9, 9]);
      },
    );
    await cacheA.fetch(server, 'http://x/cover.jpg', const {});
    expect(networkCallCount, 1);

    // 新建一個實例，模擬「記憶體快取是每個實例獨立、磁碟快取是持久化」
    // 的情境——第二個實例的記憶體是空的，但磁碟快取檔案仍在。
    final cacheB = RemoteThumbnailCacheImpl(
      cacheDir: tempDir,
      fetchOverNetwork: (server, url, headers) async {
        networkCallCount++;
        return Uint8List.fromList([9, 9, 9]);
      },
    );
    final bytes = await cacheB.fetch(server, 'http://x/cover.jpg', const {});

    expect(bytes, [9, 9, 9]);
    expect(networkCallCount, 1);
  });

  test('記憶體 LRU 超過上限時淘汰最舊項目，磁碟快取仍保留', () async {
    var networkCallCount = 0;
    final cache = RemoteThumbnailCacheImpl(
      cacheDir: tempDir,
      memoryMaxSize: 2,
      fetchOverNetwork: (server, url, headers) async {
        networkCallCount++;
        return Uint8List.fromList(utf8.encode(url));
      },
    );

    await cache.fetch(server, 'http://x/a.jpg', const {});
    await cache.fetch(server, 'http://x/b.jpg', const {});
    await cache.fetch(server, 'http://x/c.jpg', const {});
    expect(networkCallCount, 3);

    // http://x/a.jpg 應已被 LRU 淘汰出記憶體（c 進來時 a 最舊）；刪除它
    // 對應的磁碟快取檔案後，再次 fetch 應該要嘗試重新從網路擷取（因為
    // 記憶體沒有、磁碟也被我們手動刪除了）——藉此間接驗證記憶體確實
    // 已淘汰，而非還殘留著。
    final aDiskFiles = tempDir.listSync().whereType<File>().toList();
    for (final file in aDiskFiles) {
      final content = utf8.decode(file.readAsBytesSync());
      if (content == 'http://x/a.jpg') file.deleteSync();
    }
    await cache.fetch(server, 'http://x/a.jpg', const {});
    expect(networkCallCount, 4);
  });
}
