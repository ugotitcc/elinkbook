import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import 'cloud_account_repository.dart';
import 'cloud_oauth_config.dart';
import 'cloud_provider.dart';

const _authorizationEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
const _userInfoEndpoint = 'https://www.googleapis.com/oauth2/v2/userinfo';
const _driveReadonlyScope = 'https://www.googleapis.com/auth/drive.readonly email openid profile';

/// Google Drive 匯入來源帳號的 OAuth 登入流程執行者（spec.md「OAuth 登入
/// 機制」）：負責「怎麼登入／怎麼續期」，登入成功後把憑證交給
/// [CloudAccountRepository] 儲存（比照 `SyncClient` 對 `SyncAccountRepository`
/// 的既有分工），UI 層只呼叫這個 client，不直接碰 repository 的寫入邏輯。
class GoogleDriveOAuthClient {
  GoogleDriveOAuthClient({
    required CloudAccountRepository accountRepository,
    http.Client? httpClient,
    String clientSecret = CloudOAuthConfig.googleClientSecret,
  })  : _accountRepository = accountRepository,
        _httpClient = httpClient ?? http.Client(),
        _clientSecret = clientSecret;

  final CloudAccountRepository _accountRepository;
  final http.Client _httpClient;

  /// 是否在 token 請求 body 內帶入 `client_secret`，由這個值是否為空字串
  /// 決定（見 [_tokenRequestBody]）。預設值取自
  /// [CloudOAuthConfig.googleClientSecret] 這個編譯期常數，正式組裝
  /// （`main.dart`）不需要顯式傳入；測試環境透過建構子注入不同值，涵蓋
  /// Android（空字串）／電腦應用程式（非空字串）兩種情境（`flutter test`
  /// 執行期無法動態切換 `CloudOAuthConfig.googleClientSecret` 這個編譯期
  /// 常數本身的值，注入是唯一可測試的做法）。
  final String _clientSecret;

  /// 走系統瀏覽器 OAuth Authorization Code Flow ＋ PKCE（不使用內嵌
  /// WebView，Google 政策明確禁止）；成功後寫入 [CloudAccountRepository]
  /// 並回傳 `true`。使用者取消登入、`state` 不吻合（可能是 CSRF/攔截
  /// 攻擊）、或任何一步網路呼叫失敗，皆回傳 `false`，不拋出例外。
  Future<bool> link() async {
    final verifier = _generateRandomUrlSafeString(64);
    final challenge = _codeChallengeFor(verifier);
    final state = _generateRandomUrlSafeString(16);

    final authUrl = Uri.parse(_authorizationEndpoint).replace(queryParameters: {
      'client_id': CloudOAuthConfig.googleClientId,
      'redirect_uri': CloudOAuthConfig.googleRedirectUri,
      'response_type': 'code',
      'scope': _driveReadonlyScope,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
      'access_type': 'offline',
      'prompt': 'select_account',
    });

    String resultUrl;
    try {
      resultUrl = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: CloudOAuthConfig.googleRedirectScheme,
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
      tokenResponse = await _httpClient.post(
        Uri.parse(_tokenEndpoint),
        body: _tokenRequestBody({
          'code': code,
          'client_id': CloudOAuthConfig.googleClientId,
          'code_verifier': verifier,
          'grant_type': 'authorization_code',
          'redirect_uri': CloudOAuthConfig.googleRedirectUri,
        }),
      );
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
      // 狀態碼為 200 但回應本文非預期 JSON 格式（例如網路代理竄改），
      // 視同換發失敗，不拋出未捕捉例外中斷呼叫端。
      return false;
    }
    if (accessToken == null || refreshToken == null || expiresIn == null) return false;

    final email = await _fetchEmail(accessToken);
    if (email == null) return false;

    await _accountRepository.link(
      CloudProvider.googleDrive,
      CloudAccountTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        email: email,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      ),
    );
    return true;
  }

  Future<void> unlink() => _accountRepository.unlink(CloudProvider.googleDrive);

  /// 回傳目前有效的 access token；已過期或 60 秒內即將過期時，先用
  /// refresh token 靜默換發新的並更新儲存值。換發失敗（通常代表授權已被
  /// 撤銷）回傳 `null`，呼叫端視為「需要重新登入」——刻意不主動呼叫
  /// [unlink]，保留使用者手動決定是否解除連結的空間（`spec.md`「帳號
  /// 模組」）。未連結時（[CloudAccountRepository.loadTokens] 回傳 `null`）
  /// 同樣回傳 `null`，不發出任何網路請求。
  Future<String?> ensureValidAccessToken() async {
    final tokens = await _accountRepository.loadTokens(CloudProvider.googleDrive);
    if (tokens == null) return null;

    final expiringSoon =
        tokens.expiresAt.isBefore(DateTime.now().add(const Duration(seconds: 60)));
    if (!expiringSoon) return tokens.accessToken;

    http.Response response;
    try {
      response = await _httpClient.post(
        Uri.parse(_tokenEndpoint),
        body: _tokenRequestBody({
          'refresh_token': tokens.refreshToken,
          'client_id': CloudOAuthConfig.googleClientId,
          'grant_type': 'refresh_token',
        }),
      );
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
      // RFC 6749：若回應包含新的 refresh_token 應予採納（token 滾動）；
      // Google 目前預設換發時不回傳新值，此時沿用既有 refresh token。
      newRefreshToken = json['refresh_token'] as String? ?? tokens.refreshToken;
      expiresIn = json['expires_in'] as int?;
    } catch (_) {
      return null;
    }
    if (newAccessToken == null || expiresIn == null) return null;

    await _accountRepository.link(
      CloudProvider.googleDrive,
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
      return json['email'] as String?;
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

  /// 組出 token 端點請求的 body：[_clientSecret] 非空字串（電腦應用程式
  /// 機密客戶端）時併入 `client_secret` 欄位，空字串（Android 公開客戶端，
  /// 見 [CloudOAuthConfig.googleClientSecret] 文件說明）時不帶這個欄位
  /// ——[link] 與 [ensureValidAccessToken] 兩處 token 端點呼叫皆改用這個
  /// 共用方法，避免兩處各自處理、彼此不一致（此前 `link()` 有帶、
  /// `ensureValidAccessToken()` 沒帶，正是這個共用化要防止的錯誤模式）。
  Map<String, String> _tokenRequestBody(Map<String, String> params) {
    if (_clientSecret.isEmpty) return params;
    return {...params, 'client_secret': _clientSecret};
  }
}
