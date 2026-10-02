import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elinkbook/cloud_import/cloud_account_repository.dart';
import 'package:elinkbook/cloud_import/cloud_provider.dart';
import 'package:elinkbook/cloud_import/onedrive_oauth_client.dart';

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
    final client = OneDriveOAuthClient(
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
      CloudProvider.oneDrive,
      CloudAccountTokens(
        accessToken: 'still-valid-token',
        refreshToken: 'refresh-1',
        email: 'reader@example.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    final client = OneDriveOAuthClient(
      accountRepository: accountRepository,
      httpClient: mockClient,
    );

    expect(await client.ensureValidAccessToken(), 'still-valid-token');
  });

  test('access token 即將到期時，成功換發新 token（含新 refresh_token）並更新 repository', () async {
    await accountRepository.link(
      CloudProvider.oneDrive,
      CloudAccountTokens(
        accessToken: 'expiring-token',
        refreshToken: 'refresh-1',
        email: 'reader@example.com',
        expiresAt: DateTime.now().add(const Duration(seconds: 10)),
      ),
    );
    final mockClient = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://login.microsoftonline.com/common/oauth2/v2.0/token',
      );
      expect(request.bodyFields['refresh_token'], 'refresh-1');
      expect(request.bodyFields['grant_type'], 'refresh_token');
      return http.Response(
        jsonEncode({
          'access_token': 'refreshed-token',
          'refresh_token': 'rotated-refresh-token',
          'expires_in': 3600,
        }),
        200,
      );
    });
    final client = OneDriveOAuthClient(
      accountRepository: accountRepository,
      httpClient: mockClient,
    );

    final result = await client.ensureValidAccessToken();

    expect(result, 'refreshed-token');
    final updated = await accountRepository.loadTokens(CloudProvider.oneDrive);
    expect(updated?.accessToken, 'refreshed-token');
    // Microsoft identity platform 換發時通常會回傳新的 refresh_token，
    // 應予以採納（token 滾動，RFC 6749）。
    expect(updated?.refreshToken, 'rotated-refresh-token');
  });

  test('回應未附帶新 refresh_token 時，沿用既有值', () async {
    await accountRepository.link(
      CloudProvider.oneDrive,
      CloudAccountTokens(
        accessToken: 'expiring-token',
        refreshToken: 'refresh-1',
        email: 'reader@example.com',
        expiresAt: DateTime.now().add(const Duration(seconds: 10)),
      ),
    );
    final mockClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'access_token': 'refreshed-token', 'expires_in': 3600}),
        200,
      );
    });
    final client = OneDriveOAuthClient(
      accountRepository: accountRepository,
      httpClient: mockClient,
    );

    await client.ensureValidAccessToken();

    final updated = await accountRepository.loadTokens(CloudProvider.oneDrive);
    expect(updated?.refreshToken, 'refresh-1');
  });

  test('access token 即將到期且換發失敗（例如授權已被撤銷）時，回傳 null', () async {
    await accountRepository.link(
      CloudProvider.oneDrive,
      CloudAccountTokens(
        accessToken: 'expiring-token',
        refreshToken: 'revoked-refresh-token',
        email: 'reader@example.com',
        expiresAt: DateTime.now().add(const Duration(seconds: 10)),
      ),
    );
    final mockClient = MockClient((request) async {
      return http.Response(jsonEncode({'error': 'invalid_grant'}), 400);
    });
    final client = OneDriveOAuthClient(
      accountRepository: accountRepository,
      httpClient: mockClient,
    );

    expect(await client.ensureValidAccessToken(), isNull);
  });

  group('換發失敗的分類（epic-54 Issue 2）', () {
    Future<OneDriveOAuthClient> clientWith(MockClient mockClient) async {
      await accountRepository.link(
        CloudProvider.oneDrive,
        CloudAccountTokens(
          accessToken: 'expiring-token',
          refreshToken: 'refresh-1',
          email: 'reader@example.com',
          expiresAt: DateTime.now().add(const Duration(seconds: 10)),
        ),
      );
      return OneDriveOAuthClient(
        accountRepository: accountRepository,
        httpClient: mockClient,
      );
    }

    test('換發時斷網：往上拋出例外，不回傳 null（不能當成要重新連結）', () async {
      final client = await clientWith(
        MockClient((request) async => throw const SocketException('offline')),
      );

      await expectLater(
        client.ensureValidAccessToken(),
        throwsA(isA<SocketException>()),
      );
    });

    test('換發回 401：視為授權已被撤銷，回傳 null', () async {
      final client = await clientWith(
        MockClient((request) async => http.Response('', 401)),
      );

      expect(await client.ensureValidAccessToken(), isNull);
    });

    for (final code in [429, 500, 503]) {
      test('換發回 $code：屬暫時性，拋出例外而非回傳 null', () async {
        final client = await clientWith(
          MockClient((request) async => http.Response('', code)),
        );

        await expectLater(
          client.ensureValidAccessToken(),
          throwsA(isA<Exception>()),
        );
      });
    }
  });
}
