// content:// 區段讀取與 foliate-js 探針實機驗證（epic-66 Issue 12 審查補驗）。
//
// 用 createTestContentUri（FileProvider）取得真正的 content:// URI，驗證：
// 1. contentUriLength／readContentUriRange 與本機檔案的位元組一致（含 end 超過長度夾回、起點越界回 null）；
// 2. 經 content:// 時，foliate-js 探針與 Readium 的 metadata 一致。
//
// 執行：cd app && flutter test integration_test/content_uri_range_metadata_test.dart -d <device-id>

import 'dart:io';

import 'package:elinkbook/library/android_epub_metadata.dart';
import 'package:elinkbook/library/book_range_reader.dart';
import 'package:elinkbook/library/library_repository.dart'
    show kBookMetadataChannel;
import 'package:elinkbook/library/metadata_comparison.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('content:// 區段讀取與 foliate-js／Readium metadata 一致', (tester) async {
    final path =
        await _stageAssetAsFile('test/fixtures/sample.epub', 'range_probe.epub');
    addTearDown(() async {
      final f = File(path);
      if (await f.exists()) await f.delete();
    });
    final local = await File(path).readAsBytes();

    final uri = await kBookMetadataChannel
        .invokeMethod<String>('createTestContentUri', {'path': path});
    expect(uri, isNotNull);
    expect(uri!.startsWith('content://'), isTrue);

    // 長度
    expect(await bookLength(uri), local.length);

    // 區段內容
    final head = await readBookRange(uri, 0, 100);
    expect(head, local.sublist(0, 100));
    final mid = await readBookRange(uri, 50, 400);
    expect(mid, local.sublist(50, 400));

    // end 超過長度：夾回檔尾
    final tail = await readBookRange(uri, local.length - 10, local.length + 500);
    expect(tail, local.sublist(local.length - 10));

    // 起點不小於長度、起點為負、超過 4 MB 上限：回 null
    expect(await readBookRange(uri, local.length, local.length + 10), isNull);
    expect(await readBookRange(uri, -1, 10), isNull);
    expect(await readBookRange(uri, 0, 5 * 1024 * 1024), isNull);

    // metadata：經 content:// 兩邊一致
    final readium = await kBookMetadataChannel
        .invokeMapMethod<String, Object?>(
            'extractMetadata', {'uri': uri, 'format': 'epub'});
    final foliate = await readEpubMetadataOnAndroid(uri);
    expect(readium, isNotNull);
    // ignore: avoid_print
    print('[content_uri_probe] title=${foliate['title']} '
        'author=${foliate['author']} identifier=${foliate['identifier']} '
        'cover=${(foliate['coverBytes'] as Uint8List?)?.length}');
    expect(diffBookMetadata(readium!, foliate), isEmpty);
    expect(foliate['title'], isNotNull);
  });
}
