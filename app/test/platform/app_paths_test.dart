import 'dart:io';

import 'package:elinkbook/platform/app_paths.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../support/fake_path_provider_platform.dart';

void main() {
  Directory createTempDocsDir() {
    final dir = Directory.systemTemp.createTempSync('app paths 測試 ');
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
    return dir;
  }

  void setupFakePathProvider(String path) {
    final prev = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(path);
    addTearDown(() => PathProviderPlatform.instance = prev);
  }

  void overridePlatform(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  }

  test('Windows：回傳「文件」下的 elinkbook 並建立該資料夾', () async {
    final base = createTempDocsDir();
    setupFakePathProvider(base.path);
    overridePlatform(TargetPlatform.windows);

    final dir = await appDocumentsDirectory();

    final expectedPath = p.join(base.path, 'elinkbook');
    expect(dir.path, equals(expectedPath));
    expect(Directory(expectedPath).existsSync(), isTrue);
  });

  test('Windows：資料夾已存在時不報錯、重複呼叫路徑相同', () async {
    final base = createTempDocsDir();
    setupFakePathProvider(base.path);
    overridePlatform(TargetPlatform.windows);

    final existing = Directory(p.join(base.path, 'elinkbook'))..createSync();
    final keepFile = File(p.join(existing.path, 'keep.txt'))
      ..writeAsStringSync('preserve');

    final first = await appDocumentsDirectory();
    final second = await appDocumentsDirectory();

    expect(first.path, equals(existing.path));
    expect(second.path, equals(existing.path));
    expect(keepFile.existsSync(), isTrue);
    expect(keepFile.readAsStringSync(), equals('preserve'));
  });

  test('Windows：不碰「文件」根目錄原本的檔案', () async {
    final base = createTempDocsDir();
    setupFakePathProvider(base.path);
    overridePlatform(TargetPlatform.windows);

    final oldDb = File(p.join(base.path, 'library.db'))
      ..writeAsBytesSync([1, 2, 3, 4]);
    final oldCoverDir = Directory(p.join(base.path, 'covers'))..createSync();
    final oldCover = File(p.join(oldCoverDir.path, 'a.bin'))
      ..writeAsBytesSync([9, 8, 7]);

    await appDocumentsDirectory();

    expect(oldDb.readAsBytesSync(), equals([1, 2, 3, 4]));
    expect(oldCover.readAsBytesSync(), equals([9, 8, 7]));
  });

  test('Android 與 iOS：原樣回傳 getApplicationDocumentsDirectory() 的路徑，且不建立 elinkbook', () async {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      final base = createTempDocsDir();
      setupFakePathProvider(base.path);
      overridePlatform(platform);

      final expected = (await getApplicationDocumentsDirectory()).path;
      final dir = await appDocumentsDirectory();

      expect(dir.path, equals(expected));
      expect(dir.path, equals(base.path));
      expect(Directory(p.join(base.path, 'elinkbook')).existsSync(), isFalse);
    }
  });
}
