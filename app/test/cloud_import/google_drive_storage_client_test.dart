import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elinkbook/cloud_import/cloud_account_repository.dart';
import 'package:elinkbook/cloud_import/cloud_provider.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';
import 'package:elinkbook/cloud_import/google_drive_storage_client.dart';
import 'package:elinkbook/library/models/library_enums.dart';

import '../support/fake_cloud_account_repository.dart';

void main() {
  late FakeCloudAccountRepository accountRepository;
  late GoogleDriveOAuthClient oauthClient;

  setUp(() async {
    accountRepository = FakeCloudAccountRepository();
    await accountRepository.link(
      CloudProvider.googleDrive,
      CloudAccountTokens(
        accessToken: 'valid-token',
        refreshToken: 'refresh-1',
        email: 'reader@example.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    oauthClient = GoogleDriveOAuthClient(accountRepository: accountRepository);
  });

  test('未連結時 listFolder 拋出 CloudAuthRequiredException', () async {
    final unlinkedAccountRepository = FakeCloudAccountRepository();
    final unlinkedOauthClient =
        GoogleDriveOAuthClient(accountRepository: unlinkedAccountRepository);
    final client = GoogleDriveStorageClient(oauthClient: unlinkedOauthClient);

    expect(() => client.listFolder(), throwsA(isA<CloudAuthRequiredException>()));
  });

  test('listFolder 正確解析回傳的資料夾與檔案，過濾掉不支援格式', () async {
    final mockClient = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer valid-token');
      expect(request.url.queryParameters['q'], contains("'root' in parents"));
      return http.Response.bytes(
        utf8.encode(jsonEncode({
          'files': [
            {'id': 'f1', 'name': '小說', 'mimeType': 'application/vnd.google-apps.folder'},
            {'id': 'f2', 'name': 'book.epub', 'mimeType': 'application/epub+zip', 'size': '1024'},
            {'id': 'f3', 'name': 'photo.jpg', 'mimeType': 'image/jpeg'},
          ],
        })),
        200,
      );
    });
    final client =
        GoogleDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    final listing = await client.listFolder();

    expect(listing.truncated, false);
    expect(listing.entries, hasLength(2));
    expect(listing.entries[0].isFolder, true);
    expect(listing.entries[1].format, BookFileFormat.epub);
    expect(listing.entries[1].sizeBytes, 1024);
  });

  test('listFolder 指定 folderId 時查詢對應資料夾內容', () async {
    final mockClient = MockClient((request) async {
      expect(request.url.queryParameters['q'], contains("'folder-123' in parents"));
      return http.Response(jsonEncode({'files': <dynamic>[]}), 200);
    });
    final client =
        GoogleDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    await client.listFolder(folderId: 'folder-123');
  });

  test('listFolder 跨分頁累加直到 nextPageToken 為 null', () async {
    var callCount = 0;
    final mockClient = MockClient((request) async {
      callCount++;
      if (callCount == 1) {
        expect(request.url.queryParameters.containsKey('pageToken'), false);
        return http.Response(
          jsonEncode({
            'nextPageToken': 'page2',
            'files': [
              {'id': 'f1', 'name': 'a.epub', 'mimeType': 'application/epub+zip'},
            ],
          }),
          200,
        );
      }
      expect(request.url.queryParameters['pageToken'], 'page2');
      return http.Response(
        jsonEncode({
          'files': [
            {'id': 'f2', 'name': 'b.pdf', 'mimeType': 'application/pdf'},
          ],
        }),
        200,
      );
    });
    final client =
        GoogleDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    final listing = await client.listFolder();

    expect(callCount, 2);
    expect(listing.entries, hasLength(2));
  });

  test('累積達 1000 筆時標記 truncated 並停止讀取後續分頁', () async {
    var callCount = 0;
    final mockClient = MockClient((request) async {
      callCount++;
      final files = List.generate(
        1000,
        (i) => {'id': 'f$i', 'name': 'book$i.epub', 'mimeType': 'application/epub+zip'},
      );
      return http.Response(
        jsonEncode({'nextPageToken': 'page2', 'files': files}),
        200,
      );
    });
    final client =
        GoogleDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    final listing = await client.listFolder();

    expect(listing.truncated, true);
    expect(listing.entries, hasLength(1000));
    expect(callCount, 1);
  });

  group('非 200 回應的分類（epic-54 Issue 2）', () {
    GoogleDriveStorageClient clientReturning(int status) =>
        GoogleDriveStorageClient(
          oauthClient: oauthClient,
          httpClient: MockClient((request) async => http.Response('', status)),
        );

    final entry = const CloudFileEntry(
      id: 'file-1',
      name: 'a.epub',
      isFolder: false,
      format: BookFileFormat.epub,
    );

    test('listFolder 回 401：拋出 CloudAuthRequiredException', () async {
      await expectLater(
        clientReturning(401).listFolder(),
        throwsA(isA<CloudAuthRequiredException>()),
      );
    });

    test('downloadFile 回 401：拋出 CloudAuthRequiredException，且不留目的檔', () async {
      final dir = Directory.systemTemp.createTempSync('gdrive_401_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/out.epub';

      await expectLater(
        clientReturning(401).downloadFile(entry, path),
        throwsA(isA<CloudAuthRequiredException>()),
      );
      expect(File(path).existsSync(), isFalse);
    });

    test('fetchThumbnail 回 401：拋出 CloudAuthRequiredException', () async {
      await expectLater(
        clientReturning(401).fetchThumbnail('https://example.com/t'),
        throwsA(isA<CloudAuthRequiredException>()),
      );
    });

    for (final code in [403, 500]) {
      test('listFolder 回 $code：拋出一般例外，不是 CloudAuthRequiredException',
          () async {
        await expectLater(
          clientReturning(code).listFolder(),
          throwsA(
            predicate((e) => e is Exception && e is! CloudAuthRequiredException),
          ),
        );
      });
    }

    test('換發 token 時斷網：listFolder 拋出的不是 CloudAuthRequiredException', () async {
      final expiringRepository = FakeCloudAccountRepository();
      await expiringRepository.link(
        CloudProvider.googleDrive,
        CloudAccountTokens(
          accessToken: 'expiring-token',
          refreshToken: 'refresh-1',
          email: 'reader@example.com',
          expiresAt: DateTime.now().add(const Duration(seconds: 10)),
        ),
      );
      final offlineOauth = GoogleDriveOAuthClient(
        accountRepository: expiringRepository,
        httpClient: MockClient(
          (request) async => throw const SocketException('offline'),
        ),
      );
      final client = GoogleDriveStorageClient(oauthClient: offlineOauth);

      await expectLater(
        client.listFolder(),
        throwsA(
          predicate((e) => e is Exception && e is! CloudAuthRequiredException),
        ),
      );
    });
  });
}
