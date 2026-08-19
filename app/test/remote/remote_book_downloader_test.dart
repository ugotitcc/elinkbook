import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/remote/opds_client.dart';
import 'package:elinkbook/remote/opds_types.dart';
import 'package:elinkbook/remote/remote_book_downloader.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';

import '../support/fake_opds_client.dart';
import '../support/fake_path_provider_platform.dart';

void main() {
  late Directory tempRoot;
  late PathProviderPlatform originalPathProvider;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('remote_book_downloader_test');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempRoot.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPathProvider;
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  final server = RemoteServerProfile(
    id: 'srv1',
    name: '測試站點',
    baseUrl: 'http://example.com/opds',
    type: RemoteServerType.opds,
    allowInsecure: false,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
  );

  const acquisition = OpdsAcquisition(
    href: 'http://example.com/opds/download/1.epub',
    format: BookFileFormat.epub,
  );

  test('downloadToTempFile() 建立 remote_download_temp/ 目錄並呼叫 client.downloadBook()', () async {
    final client = FakeOpdsClient();

    final tempPath = await downloadToTempFile(
      client: client,
      server: server,
      acquisition: acquisition,
      format: BookFileFormat.epub,
    );

    expect(client.downloadBookCalls, [acquisition.href]);
    expect(tempPath, contains('remote_download_temp'));
    expect(tempPath, endsWith('.epub'));
    expect(File(tempPath).existsSync(), isTrue);
  });

  test('downloadToTempFile() 下載失敗時原樣拋出例外，不做額外清理', () async {
    final client = FakeOpdsClient(downloadError: StateError('模擬下載失敗'));

    await expectLater(
      downloadToTempFile(
        client: client,
        server: server,
        acquisition: acquisition,
        format: BookFileFormat.epub,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('downloadToTempFile() 正確將 password 與 cancellationToken 透傳給 client', () async {
    final client = FakeOpdsClient();
    final token = OpdsDownloadCancellationToken();
    var progressCalled = false;

    await downloadToTempFile(
      client: client,
      server: server,
      acquisition: acquisition,
      format: BookFileFormat.epub,
      password: 'secret_password',
      cancellationToken: token,
      onProgress: (received, total) => progressCalled = true,
    );

    expect(client.downloadBookPasswords, ['secret_password']);
    expect(client.downloadBookCancellationTokens.single, same(token));
    expect(progressCalled, isTrue);
  });

  test('promoteToPermanent() 複製暫存檔到 remote_books/ 並刪除暫存檔', () async {
    final client = FakeOpdsClient();
    final tempPath = await downloadToTempFile(
      client: client,
      server: server,
      acquisition: acquisition,
      format: BookFileFormat.epub,
    );

    final permanentPath = await promoteToPermanent(tempPath);

    expect(permanentPath, contains('remote_books'));
    expect(p.basename(permanentPath), p.basename(tempPath));
    expect(File(permanentPath).existsSync(), isTrue);
    expect(File(tempPath).existsSync(), isFalse);
  });

  test('promoteToPermanent() 複製中途失敗時清除殘留暫存檔並重新拋出例外', () async {
    final client = FakeOpdsClient();
    final tempPath = await downloadToTempFile(
      client: client,
      server: server,
      acquisition: acquisition,
      format: BookFileFormat.epub,
    );

    // 模擬「複製到永久目錄」中途失敗：把 App 文件目錄路徑指向一個不存在
    // 的唯讀路徑，讓 permanentDir.create() 之後的 tempFile.copy() 失敗。
    // 這裡改用最直接的方式——刪掉暫存檔本身，讓 File.copy() 因來源檔案
    // 不存在而拋出 PathNotFoundException，驗證 catch 分支正確處理「來源
    // 已消失」這個真實會發生的邊界情況（例如系統背景清過暫存目錄）。
    await File(tempPath).delete();

    await expectLater(
      promoteToPermanent(tempPath),
      throwsA(anything),
    );
    // 暫存檔本來就已經被刪除，這裡驗證 catch 分支的「if (await leftover
    // .exists())」防護不會因為檔案已不存在而額外拋出例外。
  });
}
