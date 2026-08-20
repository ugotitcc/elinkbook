import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elinkbook/cloud_import/cloud_account_repository.dart';
import 'package:elinkbook/cloud_import/cloud_provider.dart';
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';

import '../support/fake_cloud_account_repository.dart';

void main() {
  late FakeCloudAccountRepository accountRepository;

  setUp(() {
    accountRepository = FakeCloudAccountRepository();
  });

  test('未連結時 ensureValidAccessToken 回傳 null，不發出任何 HTTP 請求', () async {
    final mockClient = MockClient((request) async {
      fail('本測試不應該真的發出網路請求');
    });
    final client = GoogleDriveOAuthClient(
      accountRepository: accountRepository,
      httpClient: mockClient,
    );

    expect(await client.ensureValidAccessToken(), isNull);
  });

  test('access token 距離到期還很久時，直接回傳既有值，不發出 HTTP 請求', () async {
    final mockClient = MockClient((request) async {
      fail('本測試不應該真的發出網路請求');
    });
    await accountRepository.link(
      CloudProvider.googleDrive,
      CloudAccountTokens(
        accessToken: 'still-valid-token',
        refreshToken: 'refresh-1',
        email: 'reader@example.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    final client = GoogleDriveOAuthClient(
      accountRepository: accountRepository,
      httpClient: mockClient,
    );

    expect(await client.ensureValidAccessToken(), 'still-valid-token');
  });

  test('access token 即將到期時，成功換發新 token 並更新 repository', () async {
    await accountRepository.link(
      CloudProvider.googleDrive,
      CloudAccountTokens(
        accessToken: 'expiring-token',
        refreshToken: 'refresh-1',
        email: 'reader@example.com',
        expiresAt: DateTime.now().add(const Duration(seconds: 10)),
      ),
    );
    final mockClient = MockClient((request) async {
      expect(request.url.toString(), 'https://oauth2.googleapis.com/token');
      expect(request.bodyFields['refresh_token'], 'refresh-1');
      expect(request.bodyFields['grant_type'], 'refresh_token');
      return http.Response(
        jsonEncode({'access_token': 'refreshed-token', 'expires_in': 3600}),
        200,
      );
    });
    final client = GoogleDriveOAuthClient(
      accountRepository: accountRepository,
      httpClient: mockClient,
    );

    final result = await client.ensureValidAccessToken();

    expect(result, 'refreshed-token');
    final updated = await accountRepository.loadTokens(CloudProvider.googleDrive);
    expect(updated?.accessToken, 'refreshed-token');
    // Google 換發時通常不回傳新的 refresh_token，沿用既有值。
    expect(updated?.refreshToken, 'refresh-1');
  });

  test('access token 即將到期且換發失敗（例如授權已被撤銷）時，回傳 null', () async {
    await accountRepository.link(
      CloudProvider.googleDrive,
      CloudAccountTokens(
        accessToken: 'expiring-token',
        refreshToken: 'revoked-refresh-token',
        email: 'reader@example.com',
        expiresAt: DateTime.now().add(const Duration(seconds: 10)),
      ),
    );
    final mockClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'error': 'invalid_grant'}),
        400,
      );
    });
    final client = GoogleDriveOAuthClient(
      accountRepository: accountRepository,
      httpClient: mockClient,
    );

    expect(await client.ensureValidAccessToken(), isNull);
  });

  group('client_secret 是否併入 token 請求 body（Epic 29 Issue 8）', () {
    test('未傳入 clientSecret（沿用預設空字串，等同 Android 公開客戶端）時，'
        'refresh token 換發不帶 client_secret', () async {
      await accountRepository.link(
        CloudProvider.googleDrive,
        CloudAccountTokens(
          accessToken: 'expiring-token',
          refreshToken: 'refresh-1',
          email: 'reader@example.com',
          expiresAt: DateTime.now().add(const Duration(seconds: 10)),
        ),
      );
      final mockClient = MockClient((request) async {
        expect(request.bodyFields.containsKey('client_secret'), isFalse);
        return http.Response(
          jsonEncode({'access_token': 'refreshed-token', 'expires_in': 3600}),
          200,
        );
      });
      final client = GoogleDriveOAuthClient(
        accountRepository: accountRepository,
        httpClient: mockClient,
      );

      final result = await client.ensureValidAccessToken();

      expect(result, 'refreshed-token');
    });

    test('傳入非空 clientSecret（等同電腦應用程式機密客戶端）時，'
        'refresh token 換發帶入正確的 client_secret', () async {
      await accountRepository.link(
        CloudProvider.googleDrive,
        CloudAccountTokens(
          accessToken: 'expiring-token',
          refreshToken: 'refresh-1',
          email: 'reader@example.com',
          expiresAt: DateTime.now().add(const Duration(seconds: 10)),
        ),
      );
      final mockClient = MockClient((request) async {
        expect(request.bodyFields['client_secret'], 'test-secret-value');
        return http.Response(
          jsonEncode({'access_token': 'refreshed-token', 'expires_in': 3600}),
          200,
        );
      });
      final client = GoogleDriveOAuthClient(
        accountRepository: accountRepository,
        httpClient: mockClient,
        clientSecret: 'test-secret-value',
      );

      final result = await client.ensureValidAccessToken();

      expect(result, 'refreshed-token');
    });
  });
}
