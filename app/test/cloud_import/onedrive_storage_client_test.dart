import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elinkbook/cloud_import/cloud_account_repository.dart';
import 'package:elinkbook/cloud_import/cloud_provider.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/cloud_import/onedrive_oauth_client.dart';
import 'package:elinkbook/cloud_import/onedrive_storage_client.dart';
import 'package:elinkbook/library/models/library_enums.dart';

import '../support/fake_cloud_account_repository.dart';

void main() {
  late FakeCloudAccountRepository accountRepository;
  late OneDriveOAuthClient oauthClient;

  setUp(() async {
    accountRepository = FakeCloudAccountRepository();
    await accountRepository.link(
      CloudProvider.oneDrive,
      CloudAccountTokens(
        accessToken: 'valid-token',
        refreshToken: 'refresh-1',
        email: 'reader@example.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    oauthClient = OneDriveOAuthClient(accountRepository: accountRepository);
  });

  test('未連結時 listFolder 拋出 CloudAuthRequiredException', () async {
    final unlinkedAccountRepository = FakeCloudAccountRepository();
    final unlinkedOauthClient =
        OneDriveOAuthClient(accountRepository: unlinkedAccountRepository);
    final client = OneDriveStorageClient(oauthClient: unlinkedOauthClient);

    expect(() => client.listFolder(), throwsA(isA<CloudAuthRequiredException>()));
  });

  test('folderId 為 null 時查詢 me/drive/root/children，正確解析資料夾與檔案，過濾掉不支援格式',
      () async {
    final mockClient = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer valid-token');
      expect(request.url.toString(), contains('me/drive/root/children'));
      return http.Response.bytes(
        utf8.encode(jsonEncode({
          'value': [
            {'id': 'f1', 'name': '小說', 'folder': {'childCount': 2}},
            {
              'id': 'f2',
              'name': 'book.epub',
              'size': 1024,
              'file': {'mimeType': 'application/epub+zip'},
            },
            {
              'id': 'f3',
              'name': 'photo.jpg',
              'size': 2048,
              'file': {'mimeType': 'image/jpeg'},
            },
          ],
        })),
        200,
      );
    });
    final client =
        OneDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    final listing = await client.listFolder();

    expect(listing.truncated, false);
    expect(listing.entries, hasLength(2));
    expect(listing.entries[0].isFolder, true);
    expect(listing.entries[1].format, BookFileFormat.epub);
    expect(listing.entries[1].sizeBytes, 1024);
  });

  test('指定 folderId 時查詢 me/drive/items/{id}/children', () async {
    final mockClient = MockClient((request) async {
      expect(request.url.toString(), contains('me/drive/items/folder-123/children'));
      return http.Response(jsonEncode({'value': <dynamic>[]}), 200);
    });
    final client =
        OneDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    await client.listFolder(folderId: 'folder-123');
  });

  test('有縮圖時正確帶出 medium 縮圖網址', () async {
    final mockClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'value': [
            {
              'id': 'f1',
              'name': 'book.pdf',
              'size': 100,
              'file': {'mimeType': 'application/pdf'},
              'thumbnails': [
                {
                  'medium': {'url': 'https://graph.microsoft.com/thumb/f1'},
                },
              ],
            },
          ],
        }),
        200,
      );
    });
    final client =
        OneDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    final listing = await client.listFolder();

    expect(listing.entries.single.thumbnailUrl, 'https://graph.microsoft.com/thumb/f1');
  });

  test('跨分頁累加，@odata.nextLink 為完整 URL 直接 GET，直到欄位不存在為止', () async {
    var callCount = 0;
    final mockClient = MockClient((request) async {
      callCount++;
      if (callCount == 1) {
        expect(request.url.toString(), contains('me/drive/root/children'));
        return http.Response(
          jsonEncode({
            '@odata.nextLink': 'https://graph.microsoft.com/v1.0/me/drive/root/children?\$skiptoken=page2',
            'value': [
              {
                'id': 'f1',
                'name': 'a.epub',
                'size': 1,
                'file': {'mimeType': 'application/epub+zip'},
              },
            ],
          }),
          200,
        );
      }
      expect(request.url.toString(), contains('skiptoken=page2'));
      return http.Response(
        jsonEncode({
          'value': [
            {
              'id': 'f2',
              'name': 'b.pdf',
              'size': 1,
              'file': {'mimeType': 'application/pdf'},
            },
          ],
        }),
        200,
      );
    });
    final client =
        OneDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    final listing = await client.listFolder();

    expect(callCount, 2);
    expect(listing.entries, hasLength(2));
  });

  test('累積達 1000 筆時標記 truncated 並停止讀取後續分頁', () async {
    var callCount = 0;
    final mockClient = MockClient((request) async {
      callCount++;
      final items = List.generate(
        1000,
        (i) => {
          'id': 'f$i',
          'name': 'book$i.epub',
          'size': 1,
          'file': {'mimeType': 'application/epub+zip'},
        },
      );
      return http.Response(
        jsonEncode({
          '@odata.nextLink': 'https://graph.microsoft.com/v1.0/me/drive/root/children?\$skiptoken=page2',
          'value': items,
        }),
        200,
      );
    });
    final client =
        OneDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    final listing = await client.listFolder();

    expect(listing.truncated, true);
    expect(listing.entries, hasLength(1000));
    expect(callCount, 1);
  });

  test('HTTP 非 200 回應時拋出例外', () async {
    final mockClient = MockClient((request) async => http.Response('', 403));
    final client =
        OneDriveStorageClient(oauthClient: oauthClient, httpClient: mockClient);

    expect(client.listFolder(), throwsException);
  });
}
