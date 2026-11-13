import 'dart:io';

import 'package:elinkbook/dictionary/storage/dictionary_database.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../support/fake_path_provider_platform.dart';

void main() {
  Directory createTempDocsDir() {
    final dir = Directory.systemTemp.createTempSync('data location 測試 ');
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

  test('Windows：資料庫路徑在 elinkbook 底下', () async {
    final base = createTempDocsDir();
    setupFakePathProvider(base.path);
    overridePlatform(TargetPlatform.windows);

    final libPath = await defaultLibraryDatabasePath();
    final dictPath = await defaultDictionaryDatabasePath();

    expect(libPath, equals(p.join(base.path, 'elinkbook', 'library.db')));
    expect(dictPath, equals(p.join(base.path, 'elinkbook', 'dictionary.db')));
  });

  test('Android：資料庫路徑維持在文件根目錄', () async {
    final base = createTempDocsDir();
    setupFakePathProvider(base.path);
    overridePlatform(TargetPlatform.android);

    final libPath = await defaultLibraryDatabasePath();
    final dictPath = await defaultDictionaryDatabasePath();

    expect(libPath, equals(p.join(base.path, 'library.db')));
    expect(dictPath, equals(p.join(base.path, 'dictionary.db')));
  });
}
