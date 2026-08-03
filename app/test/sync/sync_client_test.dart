import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_client.dart';

void main() {
  late FlutterSecureStoragePlatform originalPlatform;
  late SyncAccountRepository accountRepository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalPlatform = FlutterSecureStoragePlatform.instance;
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform({});
    accountRepository = SyncAccountRepository();
  });

  tearDown(() {
    FlutterSecureStoragePlatform.instance = originalPlatform;
  });

  test('testConnection 成功時回傳 true，並把 baseUrl 與憑證寫入 SyncAccountRepository',
      () async {
    final mockClient = MockClient((request) async {
      expect(
        request.url.path,
        '/api/collections/users/auth-with-password',
      );
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['identity'], 'reader@example.com');
      expect(body['password'], 'correct-password');
      return http.Response(
        jsonEncode({
          'token': 'token-abc',
          'record': {
            'id': 'user-123',
            'collectionId': '_pb_users_auth_',
            'collectionName': 'users',
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final client = SyncClient(
      accountRepository: accountRepository,
      clientFactory: (baseUrl) =>
          PocketBase(baseUrl, httpClientFactory: () => mockClient),
    );

    final result = await client.testConnection(
      'http://127.0.0.1:8090',
      'reader@example.com',
      'correct-password',
    );

    expect(result, true);
    expect(await accountRepository.loadBaseUrl(), 'http://127.0.0.1:8090');
    expect(await accountRepository.loadAuthToken(), 'token-abc');
    expect(await accountRepository.loadUserId(), 'user-123');
    expect(await accountRepository.loadEmail(), 'reader@example.com');
  });

  test('testConnection 的 baseUrl 前後夾帶空白時，實際使用與寫入的皆為修剪後的值',
      () async {
    final mockClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'token': 'token-abc',
          'record': {'id': 'user-123'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    String? receivedBaseUrl;
    final client = SyncClient(
      accountRepository: accountRepository,
      clientFactory: (baseUrl) {
        receivedBaseUrl = baseUrl;
        return PocketBase(baseUrl, httpClientFactory: () => mockClient);
      },
    );

    final result = await client.testConnection(
      '  http://127.0.0.1:8090  ',
      'reader@example.com',
      'correct-password',
    );

    expect(result, true);
    expect(receivedBaseUrl, 'http://127.0.0.1:8090');
    expect(await accountRepository.loadBaseUrl(), 'http://127.0.0.1:8090');
  });

  test('testConnection 帳密錯誤時回傳 false，不寫入任何憑證與 baseUrl', () async {
    final mockClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'status': 400,
          'message': 'Failed to authenticate.',
          'data': {},
        }),
        400,
        headers: {'content-type': 'application/json'},
      );
    });

    final client = SyncClient(
      accountRepository: accountRepository,
      clientFactory: (baseUrl) =>
          PocketBase(baseUrl, httpClientFactory: () => mockClient),
    );

    final result = await client.testConnection(
      'http://127.0.0.1:8090',
      'reader@example.com',
      'wrong-password',
    );

    expect(result, false);
    expect(await accountRepository.loadAuthToken(), isNull);
    expect(await accountRepository.loadBaseUrl(), '');
  });

  test('testConnection 連線錯誤（例如逾時/連線被拒）時回傳 false，不寫入任何憑證', () async {
    final mockClient = MockClient((request) async {
      throw const SocketException('Connection refused');
    });

    final client = SyncClient(
      accountRepository: accountRepository,
      clientFactory: (baseUrl) =>
          PocketBase(baseUrl, httpClientFactory: () => mockClient),
    );

    final result = await client.testConnection(
      'http://127.0.0.1:8090',
      'reader@example.com',
      'correct-password',
    );

    expect(result, false);
    expect(await accountRepository.loadAuthToken(), isNull);
  });

  test('logout 清除全部憑證，不影響本機資料', () async {
    await accountRepository.saveCredentials(
      authToken: 'token-abc',
      userId: 'user-123',
      email: 'reader@example.com',
    );
    final client = SyncClient(accountRepository: accountRepository);

    await client.logout();

    expect(await accountRepository.loadAuthToken(), isNull);
    expect(await accountRepository.loadUserId(), isNull);
    expect(await accountRepository.loadEmail(), isNull);
  });
}
