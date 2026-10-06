import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'fake_downloadable_font_store.dart';
import 'fake_reader_feature_dependencies.dart';

/// epic-54 Issue 16：真機 integration 測試中，Android 原生的
/// `WebViewAssetLoader.InternalStoragePathHandler` 會拒絕不存在的目錄，
/// 導致 `InAppWebView` 建立失敗。所以 Android 上 fake store 的目錄必須真實存在。
void main() {
  test('預設目錄維持 /fake/downloaded-fonts（單元測試行為不變）', () {
    expect(FakeDownloadableFontStore().directory, '/fake/downloaded-fonts');
  });

  test('可以指定目錄', () {
    expect(FakeDownloadableFontStore(directory: '/tmp/x').directory, '/tmp/x');
  });

  test('forPlatform(isAndroid: true) 回傳真實存在、且位於 cache/ 底下的目錄', () {
    // Android 的 systemTemp 指向 code_cache/，是 WebViewAssetLoader 的禁用目錄；
    // 允許的是同一層的 cache/。用假的 data 目錄模擬這個結構，不碰主機真實目錄。
    final dataDir = Directory.systemTemp.createTempSync('fake-data');
    addTearDown(() => dataDir.deleteSync(recursive: true));
    final codeCache = Directory('${dataDir.path}/code_cache')..createSync();

    final store = FakeDownloadableFontStore.forPlatform(
      isAndroid: true,
      systemTemp: codeCache,
    );

    expect(Directory(store.directory).existsSync(), isTrue);
    // 桌面主機是反斜線，統一成正斜線再比對
    String norm(String path) => path.replaceAll(r'\', '/');
    expect(
      norm(store.directory).startsWith('${norm(dataDir.path)}/cache/'),
      isTrue,
    );
    expect(store.directory.contains('code_cache'), isFalse);
  });

  test('forPlatform(isAndroid: false) 維持假目錄，不在磁碟建立東西', () {
    final store = FakeDownloadableFontStore.forPlatform(isAndroid: false);
    expect(store.directory, '/fake/downloaded-fonts');
  });

  test('fakeReaderFeatureDependencies 在桌面主機上預設仍是假目錄', () {
    final deps = fakeReaderFeatureDependencies();
    expect(deps.downloadableFontStore.directory, '/fake/downloaded-fonts');
  });
}
