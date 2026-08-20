import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import 'cloud_account_repository.dart';
import 'cloud_oauth_config.dart';
import 'cloud_provider.dart';

const _authorizationEndpoint =
    'https://login.microsoftonline.com/common/oauth2/v2.0/authorize';
const _tokenEndpoint = 'https://login.microsoftonline.com/common/oauth2/v2.0/token';
const _userInfoEndpoint = 'https://graph.microsoft.com/v1.0/me';
const _filesReadScope = 'Files.Read User.Read offline_access email openid profile';

/// OneDrive 匯入來源帳號的 OAuth 登入流程執行者（spec.md「OAuth 登入
/// 機制」，epic-29 Issue 2）：結構與職責分工完全比照 Issue 1 的
/// `GoogleDriveOAuthClient`（系統瀏覽器 PKCE 流程、登入成功後交給
/// [CloudAccountRepository] 儲存，UI 層只呼叫這個 client），差異僅在於
/// Microsoft identity platform 的端點與 scope；`offline_access` scope 是
/// Microsoft 換發 refresh token 的必要條件（與 Google 的
/// `access_type=offline` 參數不同機制，不可省略）。
class OneDriveOAuthClient {
  OneDriveOAuthClient({
    required CloudAccountRepository accountRepository,
    http.Client? httpClient,
  })  : _accountRepository = accountRepository,
        _httpClient = httpClient ?? http.Client();

  final CloudAccountRepository _accountRepository;
  final http.Client _httpClient;

  /// 走系統瀏覽器 OAuth Authorization Code Flow ＋ PKCE（不使用內嵌
  /// WebView）；成功後寫入 [CloudAccountRepository] 並回傳 `true`。使用者
  /// 取消登入、`state` 不吻合（可能是 CSRF/攔截攻擊）、或任何一步網路
  /// 呼叫失敗，皆回傳 `false`，不拋出例外。
  Future<bool> link() async {
    final verifier = _generateRandomUrlSafeString(64);
    final challenge = _codeChallengeFor(verifier);
    final state = _generateRandomUrlSafeString(16);

    final authUrl = Uri.parse(_authorizationEndpoint).replace(queryParameters: {
      'client_id': CloudOAuthConfig.oneDriveClientId,
      'redirect_uri': CloudOAuthConfig.oneDriveRedirectUri,
      'response_type': 'code',
      'scope': _filesReadScope,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
    });

    String resultUrl;
    try {
      resultUrl = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: CloudOAuthConfig.oneDriveRedirectScheme,
      );
    } catch (_) {
      return false;
    }

    final redirected = Uri.parse(resultUrl);
    final code = redirected.queryParameters['code'];
    final returnedState = redirected.queryParameters['state'];
    if (code == null || returnedState != state) return false;

    http.Response tokenResponse;
    try {
      tokenResponse = await _httpClient.post(Uri.parse(_tokenEndpoint), body: {
        'code': code,
        'client_id': CloudOAuthConfig.oneDriveClientId,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': CloudOAuthConfig.oneDriveRedirectUri,
        'scope': _filesReadScope,
      });
    } catch (_) {
      return false;
    }
    if (tokenResponse.statusCode != 200) return false;

    String? accessToken;
    String? refreshToken;
    int? expiresIn;
    try {
      final tokenJson = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
      accessToken = tokenJson['access_token'] as String?;
      refreshToken = tokenJson['refresh_token'] as String?;
      expiresIn = tokenJson['expires_in'] as int?;
    } catch (_) {
      // 狀態碼為 200 但回應本文非預期 JSON 格式，視同換發失敗，不拋出
      // 未捕捉例外中斷呼叫端（比照 Issue 1 `GoogleDriveOAuthClient` 既定
      // 防護，review-issue-1.md Minor #1 採納）。
      return false;
    }
    if (accessToken == null || refreshToken == null || expiresIn == null) return false;

    final email = await _fetchEmail(accessToken);
    if (email == null) return false;

    await _accountRepository.link(
      CloudProvider.oneDrive,
      CloudAccountTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        email: email,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      ),
    );
    return true;
  }

  Future<void> unlink() => _accountRepository.unlink(CloudProvider.oneDrive);

  /// 回傳目前有效的 access token；已過期或 60 秒內即將過期時，先用
  /// refresh token 靜默換發新的並更新儲存值。換發失敗（通常代表授權已被
  /// 撤銷）回傳 `null`，呼叫端視為「需要重新登入」——刻意不主動呼叫
  /// [unlink]，保留使用者手動決定是否解除連結的空間（比照 Issue 1 既定
  /// 設計）。未連結時同樣回傳 `null`，不發出任何網路請求。
  Future<String?> ensureValidAccessToken() async {
    final tokens = await _accountRepository.loadTokens(CloudProvider.oneDrive);
    if (tokens == null) return null;

    final expiringSoon =
        tokens.expiresAt.isBefore(DateTime.now().add(const Duration(seconds: 60)));
    if (!expiringSoon) return tokens.accessToken;

    http.Response response;
    try {
      response = await _httpClient.post(Uri.parse(_tokenEndpoint), body: {
        'refresh_token': tokens.refreshToken,
        'client_id': CloudOAuthConfig.oneDriveClientId,
        'grant_type': 'refresh_token',
        'scope': _filesReadScope,
      });
    } catch (_) {
      return null;
    }
    if (response.statusCode != 200) return null;

    String? newAccessToken;
    String? newRefreshToken;
    int? expiresIn;
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      newAccessToken = json['access_token'] as String?;
      // Microsoft identity platform 換發時通常會回傳新的 refresh_token
      // （token 滾動，RFC 6749），若回應未附帶則沿用既有值。
      newRefreshToken = json['refresh_token'] as String? ?? tokens.refreshToken;
      expiresIn = json['expires_in'] as int?;
    } catch (_) {
      return null;
    }
    if (newAccessToken == null || expiresIn == null) return null;

    await _accountRepository.link(
      CloudProvider.oneDrive,
      CloudAccountTokens(
        accessToken: newAccessToken,
        refreshToken: newRefreshToken,
        email: tokens.email,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      ),
    );
    return newAccessToken;
  }

  Future<String?> _fetchEmail(String accessToken) async {
    http.Response response;
    try {
      response = await _httpClient.get(
        Uri.parse(_userInfoEndpoint),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
    } catch (_) {
      return null;
    }
    if (response.statusCode != 200) return null;
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      // 個人 Microsoft 帳號的 `mail` 欄位可能為 null（尤其未設定備援
      // Email 的舊帳號），退回 `userPrincipalName`（登入用識別碼，格式
      // 通常也是 email 格式）。
      return (json['mail'] as String?) ?? (json['userPrincipalName'] as String?);
    } catch (_) {
      return null;
    }
  }

  String _generateRandomUrlSafeString(int byteLength) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _codeChallengeFor(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}
