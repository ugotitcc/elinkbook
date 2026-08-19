# Epic 29 Issue 2：OneDrive 帳號連結／解除連結 實作計劃

> **給執行者：** 本計劃必須搭配 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行。每個 Step 用 checkbox（`- [ ]`）追蹤，完成後改為 `- [x]`。

**Goal：** 讓使用者能在設定頁用真實 Microsoft 帳號完成 OneDrive 匯入來源帳號的連結／解除連結，沿用 Issue 1 已建好的 `CloudAccountRepository` 與 `CloudAccountSettingsScreen`，只新增 OneDrive 專屬的 OAuth 串接與畫面區塊。

**Architecture：** 完全比照 Issue 1 已驗證過的 `GoogleDriveOAuthClient` 結構，新增平行的 `OneDriveOAuthClient`（Microsoft identity platform v2.0 端點、`Files.Read` scope，PKCE 流程與 `ensureValidAccessToken()` 續期邏輯與 Google 版本同構，差異僅在端點/scope/refresh_token 滾動行為）。刻意**不**把兩個 OAuth client 抽成共用抽象介面——`CloudAccountSettingsScreen` 已經是分別對兩個具體型別各自持有獨立狀態/方法的結構（`_googleDriveLinked`／`_link()` 等），沿用同一種「每個 provider 一組平行欄位/方法」模式新增 OneDrive 對稱區塊，是本 Issue 唯一要求的範圍；是否日後要把兩個 client 收斂成一個介面，留給未來真正感受到重複之痛時的架構審查決定（YAGNI，也避免動到 Issue 1 已審查合併的既有程式碼）。`CloudAccountSettingsScreen` 新增 `oneDriveOAuthClient`（必要參數，比照既有 `googleDriveOAuthClient`），透過既有的 `SettingsScreen`→`LibraryScreen`→`ElinkBookApp`→`main.dart` 可選參數貫穿慣例注入。

**Tech Stack：** Flutter／Dart、`flutter_web_auth_2`（已是 Issue 1 引入的既有依賴）、`crypto`（PKCE code challenge，既有依賴）、`http`（token 端點呼叫，既有依賴）。

**Spec：** `docs/epics/epic-29-cloud-import/spec.md`（Architecting 階段產出，本 Issue 對應「帳號模組：`CloudAccountRepository`」「OAuth 登入機制」兩節的 OneDrive 部分，已通過 `reviews/review-spec.md` 審查修訂）。

## Global Constraints

- `CloudAccountRepository`／`CloudProvider`／`CloudAccountTokens`（Issue 1 已建置）**不需要任何修改**——`CloudProvider.oneDrive` 這個 case 從 Issue 1 起就已存在，本 Issue 只是第一個實際使用它的呼叫端。
- OneDrive OAuth scope 採 Microsoft Graph 的 `Files.Read`（唯讀存取使用者可存取的所有檔案）＋`offline_access`（Microsoft identity platform 換發 refresh token 的**必要條件**，與 Google 的 `access_type=offline` 參數不同機制、不可省略）＋`email openid profile`（供取得帳號 email 顯示用）。
- OAuth 一律系統瀏覽器（`flutter_web_auth_2`）導向的 Authorization Code Flow ＋ PKCE（RFC 7636）＋ `state` 參數，**不使用內嵌 WebView**——與 Issue 1 Google Drive 同一套政策要求。
- **Microsoft Entra ID（Azure AD）應用程式註冊的用戶端 ID 是本專案程式碼庫無法內含的外部設定值**——`app/lib/cloud_import/onedrive_oauth_config.dart` 內的 `oneDriveOAuthClientId`／`oneDriveOAuthRedirectScheme` 常數需要開發者各自從自己的 Azure 入口網站應用程式註冊取得真實值填入，這是 App 上線前的必要人工設定步驟；`AndroidManifest.xml` 新增的 intent-filter `scheme`／`host` 必須與 `oneDriveOAuthRedirectScheme` 完全一致，兩處變更需同步維護（比照 Issue 1 對 Google 用戶端 ID 的既定處理原則）。
- OneDrive／Microsoft 的 redirect URI 走**自訂 scheme**（MSAL 慣例，例如 `msal<CLIENT_ID>://auth`），與 Google 的**反向客戶端 ID 格式**不同，`spec.md`「OAuth 登入機制」審查 Minor #5 已定案兩者不可套用同一組設定。
- OneDrive OAuth 實際登入流程（真實瀏覽器導向＋換 token）**不做自動化測試**，留待真機/人工用真實 Microsoft 帳號驗證（比照 Issue 1 對 Google Drive 的既定測試範圍）；`OneDriveOAuthClient.ensureValidAccessToken()` 的 token 續期 HTTP 邏輯可用 `MockClient` 測試，不受此限制。
- 完成後 `flutter analyze` 必須乾淨（"No issues found!"），`flutter test` 必須全數通過、零回歸（Google Drive 既有功能不受影響）。
- 所有程式碼註解、doc comment、commit message、本計劃文件本身，一律使用正體中文（zh-TW），不得出現簡體中文。

---

## Task 1：`OneDriveOAuthClient`（Microsoft identity platform PKCE 登入流程）＋ AndroidManifest redirect URI

**Files：**
- Create: `app/lib/cloud_import/onedrive_oauth_config.dart`
- Create: `app/lib/cloud_import/onedrive_oauth_client.dart`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Test: `app/test/cloud_import/onedrive_oauth_client_test.dart`

**Interfaces：**
- Consumes：Issue 1 的 `CloudAccountRepository`／`CloudAccountTokens`／`CloudProvider`／`FakeCloudAccountRepository`。
- Produces：`class OneDriveOAuthClient { Future<bool> link(); Future<void> unlink(); Future<String?> ensureValidAccessToken(); }`，供 Task 2（UI）使用；方法簽章與 Issue 1 的 `GoogleDriveOAuthClient` 完全同構。

- [ ] **Step 1：建立 OneDrive OAuth 設定常數檔**

建立 `app/lib/cloud_import/onedrive_oauth_config.dart`：

```dart
/// Microsoft Entra ID（Azure AD）「應用程式註冊」建立的用戶端 ID（平台
/// 類型選「行動裝置與桌面應用程式」，公開客戶端、無 client secret，
/// 符合 spec.md「OAuth 登入機制」對 PKCE 公開客戶端流程的要求）。
///
/// **這是外部設定值，無法寫死在版本控制的程式碼內視為「已完成」**——每個
/// 開發者/建置環境需要各自從自己的 Azure 入口網站應用程式註冊取得真實值
/// 填入下方常數，才能實際發起登入流程（比照 Issue 1
/// `google_oauth_config.dart` 對 Google 用戶端 ID 的既定處理原則）。
const String oneDriveOAuthClientId = 'YOUR_ONEDRIVE_OAUTH_CLIENT_ID';

/// 對應 [oneDriveOAuthClientId] 的自訂 scheme redirect URI（MSAL 慣例，
/// `spec.md`「OAuth 登入機制」審查 Minor #5 採納：OneDrive/Microsoft 與
/// Google 的反向客戶端 ID 格式不同，走自訂 scheme）。**必須與
/// `AndroidManifest.xml` 新增的 intent-filter `android:scheme`／
/// `android:host` 完全一致**，兩處變更需同步維護——實際值同樣需要開發者
/// 從 Azure 應用程式註冊取得真實用戶端 ID 後代入 `msal<CLIENT_ID>` 樣板。
const String oneDriveOAuthRedirectScheme = 'msalYOUR_ONEDRIVE_OAUTH_CLIENT_ID';

const String oneDriveOAuthRedirectUri = '$oneDriveOAuthRedirectScheme://auth';
```

- [ ] **Step 2：`AndroidManifest.xml` 新增 redirect URI intent-filter**

在 `app/android/app/src/main/AndroidManifest.xml` 找到 Issue 1 新增的 Google redirect intent-filter：

```xml
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="com.googleusercontent.apps.YOUR_GOOGLE_OAUTH_CLIENT_ID"/>
            </intent-filter>
```

在其後新增（`android:host="auth"` 對應 `msal<CLIENT_ID>://auth` 的 authority 部分，MSAL 慣例）：

```xml
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="msalYOUR_ONEDRIVE_OAUTH_CLIENT_ID" android:host="auth"/>
            </intent-filter>
```

`android:scheme` 的值必須與 Step 1 的 `oneDriveOAuthRedirectScheme` 常數完全一致；開發者填入真實用戶端 ID 時，這兩處需同步更新（Global Constraints 已註明）。

- [ ] **Step 3：寫入失敗的 `ensureValidAccessToken()` 測試**

建立 `app/test/cloud_import/onedrive_oauth_client_test.dart`：

```dart
import 'dart:convert';

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
}
```

- [ ] **Step 4：執行測試確認失敗**

執行：`flutter test test/cloud_import/onedrive_oauth_client_test.dart`
預期：編譯失敗（`OneDriveOAuthClient` 尚未定義）。

- [ ] **Step 5：實作 `OneDriveOAuthClient`**

建立 `app/lib/cloud_import/onedrive_oauth_client.dart`：

```dart
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import 'cloud_account_repository.dart';
import 'cloud_provider.dart';
import 'onedrive_oauth_config.dart';

const _authorizationEndpoint =
    'https://login.microsoftonline.com/common/oauth2/v2.0/authorize';
const _tokenEndpoint = 'https://login.microsoftonline.com/common/oauth2/v2.0/token';
const _userInfoEndpoint = 'https://graph.microsoft.com/v1.0/me';
const _filesReadScope = 'Files.Read offline_access email openid profile';

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
      'client_id': oneDriveOAuthClientId,
      'redirect_uri': oneDriveOAuthRedirectUri,
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
        callbackUrlScheme: oneDriveOAuthRedirectScheme,
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
        'client_id': oneDriveOAuthClientId,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': oneDriveOAuthRedirectUri,
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
        'client_id': oneDriveOAuthClientId,
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
```

- [ ] **Step 6：執行測試確認通過**

執行：`flutter test test/cloud_import/onedrive_oauth_client_test.dart`
預期：全數 PASS。

- [ ] **Step 7：執行完整測試套件與靜態分析確認零回歸**

執行：`flutter analyze`
預期："No issues found!"

執行：`flutter test`
預期：全數 PASS（Google Drive 既有功能不受影響）。

- [ ] **Step 8：Commit**

```bash
git add app/lib/cloud_import/onedrive_oauth_config.dart app/lib/cloud_import/onedrive_oauth_client.dart app/android/app/src/main/AndroidManifest.xml app/test/cloud_import/onedrive_oauth_client_test.dart
git commit -m "feat(epic-29): Issue 2——OneDriveOAuthClient（PKCE 登入/續期）與 AndroidManifest redirect URI"
```

---

## Task 2：`CloudAccountSettingsScreen` 擴充 OneDrive 區塊

**Files：**
- Modify: `app/lib/screens/cloud_account_settings_screen.dart`
- Test: `app/test/screens/cloud_account_settings_screen_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `OneDriveOAuthClient`。
- Produces：`CloudAccountSettingsScreen` 新增必要參數 `oneDriveOAuthClient`（比照既有 `googleDriveOAuthClient`），供 Task 3 貫穿注入使用。

- [ ] **Step 1：寫入失敗的 widget test**

在 `app/test/screens/cloud_account_settings_screen_test.dart` 找到檔案開頭 import 區塊：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/cloud_import/cloud_account_repository.dart';
import 'package:elinkbook/cloud_import/cloud_provider.dart';
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';
import 'package:elinkbook/screens/cloud_account_settings_screen.dart';

import '../support/fake_cloud_account_repository.dart';
```

改為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/cloud_import/cloud_account_repository.dart';
import 'package:elinkbook/cloud_import/cloud_provider.dart';
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';
import 'package:elinkbook/cloud_import/onedrive_oauth_client.dart';
import 'package:elinkbook/screens/cloud_account_settings_screen.dart';

import '../support/fake_cloud_account_repository.dart';
```

在既有的 3 個 `testWidgets` 內，找到每一處 `CloudAccountSettingsScreen(` 建構呼叫（皆為以下形式）：

```dart
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
      ),
```

**全部 3 處**皆改為：

```dart
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
        oneDriveOAuthClient:
            OneDriveOAuthClient(accountRepository: accountRepository),
      ),
```

在檔案末尾（最後一個 `});` 之後、檔案結尾 `}` 之前）新增 3 個新測試：

```dart

  testWidgets('未連結時 OneDrive 區塊顯示「未連結」與「連結」按鈕，不顯示 email', (tester) async {
    final accountRepository = FakeCloudAccountRepository();
    await tester.pumpWidget(MaterialApp(
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
        oneDriveOAuthClient:
            OneDriveOAuthClient(accountRepository: accountRepository),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('cloud_account_settings_onedrive_unlinked_text')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('cloud_account_settings_onedrive_link_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('cloud_account_settings_onedrive_linked_email')),
      findsNothing,
    );
  });

  testWidgets('已連結時 OneDrive 區塊顯示帳號 email 與「解除連結」按鈕', (tester) async {
    final accountRepository = FakeCloudAccountRepository();
    await accountRepository.link(
      CloudProvider.oneDrive,
      CloudAccountTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        email: 'reader@outlook.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
        oneDriveOAuthClient:
            OneDriveOAuthClient(accountRepository: accountRepository),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('已連結：reader@outlook.com'), findsOneWidget);
    expect(
      find.byKey(const Key('cloud_account_settings_onedrive_unlink_button')),
      findsOneWidget,
    );
  });

  testWidgets('點擊 OneDrive「解除連結」後畫面更新為未連結狀態，Google Drive 區塊不受影響', (tester) async {
    final accountRepository = FakeCloudAccountRepository();
    await accountRepository.link(
      CloudProvider.googleDrive,
      CloudAccountTokens(
        accessToken: 'gd-access-1',
        refreshToken: 'gd-refresh-1',
        email: 'reader@gmail.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    await accountRepository.link(
      CloudProvider.oneDrive,
      CloudAccountTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        email: 'reader@outlook.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
        oneDriveOAuthClient:
            OneDriveOAuthClient(accountRepository: accountRepository),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cloud_account_settings_onedrive_unlink_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('cloud_account_settings_onedrive_unlinked_text')),
      findsOneWidget,
    );
    expect(await accountRepository.isLinked(CloudProvider.oneDrive), false);
    // Google Drive 區塊維持已連結狀態，證明兩個 provider 的狀態彼此獨立。
    expect(find.text('已連結：reader@gmail.com'), findsOneWidget);
    expect(await accountRepository.isLinked(CloudProvider.googleDrive), true);
  });
```

- [ ] **Step 2：執行測試確認失敗**

執行：`flutter test test/screens/cloud_account_settings_screen_test.dart`
預期：編譯失敗（`CloudAccountSettingsScreen` 沒有 `oneDriveOAuthClient` 具名參數，`onedrive_oauth_client.dart` 匯入路徑不存在——若 Task 1 已完成，只有第一個原因會出現）。

- [ ] **Step 3：擴充 `CloudAccountSettingsScreen` 加入 OneDrive 區塊**

在 `app/lib/screens/cloud_account_settings_screen.dart` 找到檔案開頭：

```dart
import 'package:flutter/material.dart';

import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/cloud_provider.dart';
import '../cloud_import/google_drive_oauth_client.dart';

/// Settings「已連結的雲端匯入帳戶」子頁面（spec.md「UI 落地位置」）：
/// 顯示 Google Drive 連結狀態（未連結／已連結＋帳號 email），提供連結／
/// 解除連結操作。比照 `SyncSettingsScreen` 的載入中/已連結/未連結三態
/// 結構，但資料來源是 [CloudAccountRepository]，與 `SyncAccountRepository`
/// 完全獨立、不共用元件狀態。OneDrive 由 Issue 2 擴充。
class CloudAccountSettingsScreen extends StatefulWidget {
  final CloudAccountRepository cloudAccountRepository;
  final GoogleDriveOAuthClient googleDriveOAuthClient;

  const CloudAccountSettingsScreen({
    super.key,
    required this.cloudAccountRepository,
    required this.googleDriveOAuthClient,
  });

  @override
  State<CloudAccountSettingsScreen> createState() =>
      _CloudAccountSettingsScreenState();
}

class _CloudAccountSettingsScreenState
    extends State<CloudAccountSettingsScreen> {
  bool _loading = true;
  bool _linking = false;
  bool _googleDriveLinked = false;
  String? _googleDriveEmail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final linked =
        await widget.cloudAccountRepository.isLinked(CloudProvider.googleDrive);
    final email = linked
        ? await widget.cloudAccountRepository
            .loadAccountEmail(CloudProvider.googleDrive)
        : null;
    if (!mounted) return;
    setState(() {
      _googleDriveLinked = linked;
      _googleDriveEmail = email;
      _loading = false;
      // 【審查修正 review-issue-1.md Important #1】_link() 成功後改呼叫
      // 這個方法完成畫面狀態刷新，若不在這裡一併重設 _linking，之後解除
      // 連結會讓「連結」按鈕永久卡在轉圈停用狀態——_load() 是畫面「已完成
      // 處理、可以恢復互動」的唯一收斂點，比照其餘 transient 旗標在此
      // 一併清空，而非在呼叫端（_link()）用 setState 外的裸賦值處理。
      _linking = false;
    });
  }

  Future<void> _link() async {
    setState(() => _linking = true);
    final success = await widget.googleDriveOAuthClient.link();
    if (!mounted) return;
    if (success) {
      await _load();
    } else {
      setState(() => _linking = false);
    }
  }

  Future<void> _unlink() async {
    await widget.googleDriveOAuthClient.unlink();
    if (!mounted) return;
    setState(() {
      _googleDriveLinked = false;
      _googleDriveEmail = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('已連結的雲端匯入帳戶')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('cloud_account_settings_loading_indicator'),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: _buildGoogleDriveTile(),
            ),
    );
  }

  Widget _buildGoogleDriveTile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Google Drive', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_googleDriveLinked) ...[
          Text(
            '已連結：${_googleDriveEmail ?? ''}',
            key: const Key('cloud_account_settings_google_drive_linked_email'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            key: const Key('cloud_account_settings_google_drive_unlink_button'),
            onPressed: _unlink,
            child: const Text('解除連結'),
          ),
        ] else ...[
          const Text(
            '未連結',
            key: Key('cloud_account_settings_google_drive_unlinked_text'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            key: const Key('cloud_account_settings_google_drive_link_button'),
            onPressed: _linking ? null : _link,
            child: _linking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('連結'),
          ),
        ],
      ],
    );
  }
}
```

整份改為：

```dart
import 'package:flutter/material.dart';

import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/cloud_provider.dart';
import '../cloud_import/google_drive_oauth_client.dart';
import '../cloud_import/onedrive_oauth_client.dart';

/// Settings「已連結的雲端匯入帳戶」子頁面（spec.md「UI 落地位置」）：
/// 顯示 Google Drive／OneDrive 各自的連結狀態（未連結／已連結＋帳號
/// email），各自提供連結／解除連結操作。比照 `SyncSettingsScreen` 的
/// 載入中/已連結/未連結三態結構，但資料來源是 [CloudAccountRepository]，
/// 與 `SyncAccountRepository` 完全獨立、不共用元件狀態。兩個 provider
/// 的狀態各自獨立維護（各自一組 `_xxxLinked`/`_xxxEmail`/`_xxxLinking`
/// 欄位與 `_linkXxx()`/`_unlinkXxx()` 方法），不共用單一 transient 旗標，
/// 避免其中一個 provider 的連結流程進行中時誤鎖另一個 provider 的按鈕。
class CloudAccountSettingsScreen extends StatefulWidget {
  final CloudAccountRepository cloudAccountRepository;
  final GoogleDriveOAuthClient googleDriveOAuthClient;
  final OneDriveOAuthClient oneDriveOAuthClient;

  const CloudAccountSettingsScreen({
    super.key,
    required this.cloudAccountRepository,
    required this.googleDriveOAuthClient,
    required this.oneDriveOAuthClient,
  });

  @override
  State<CloudAccountSettingsScreen> createState() =>
      _CloudAccountSettingsScreenState();
}

class _CloudAccountSettingsScreenState
    extends State<CloudAccountSettingsScreen> {
  bool _loading = true;
  bool _googleDriveLinking = false;
  bool _googleDriveLinked = false;
  String? _googleDriveEmail;
  bool _oneDriveLinking = false;
  bool _oneDriveLinked = false;
  String? _oneDriveEmail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final googleDriveLinked =
        await widget.cloudAccountRepository.isLinked(CloudProvider.googleDrive);
    final googleDriveEmail = googleDriveLinked
        ? await widget.cloudAccountRepository
            .loadAccountEmail(CloudProvider.googleDrive)
        : null;
    final oneDriveLinked =
        await widget.cloudAccountRepository.isLinked(CloudProvider.oneDrive);
    final oneDriveEmail = oneDriveLinked
        ? await widget.cloudAccountRepository
            .loadAccountEmail(CloudProvider.oneDrive)
        : null;
    if (!mounted) return;
    setState(() {
      _googleDriveLinked = googleDriveLinked;
      _googleDriveEmail = googleDriveEmail;
      _oneDriveLinked = oneDriveLinked;
      _oneDriveEmail = oneDriveEmail;
      _loading = false;
      // 【審查修正 review-issue-1.md Important #1，OneDrive 比照沿用】
      // _load() 是畫面「已完成處理、可以恢復互動」的唯一收斂點，兩個
      // provider 的 linking 旗標皆在此一併清空。
      _googleDriveLinking = false;
      _oneDriveLinking = false;
    });
  }

  Future<void> _linkGoogleDrive() async {
    setState(() => _googleDriveLinking = true);
    final success = await widget.googleDriveOAuthClient.link();
    if (!mounted) return;
    if (success) {
      await _load();
    } else {
      setState(() => _googleDriveLinking = false);
    }
  }

  Future<void> _unlinkGoogleDrive() async {
    await widget.googleDriveOAuthClient.unlink();
    if (!mounted) return;
    setState(() {
      _googleDriveLinked = false;
      _googleDriveEmail = null;
    });
  }

  Future<void> _linkOneDrive() async {
    setState(() => _oneDriveLinking = true);
    final success = await widget.oneDriveOAuthClient.link();
    if (!mounted) return;
    if (success) {
      await _load();
    } else {
      setState(() => _oneDriveLinking = false);
    }
  }

  Future<void> _unlinkOneDrive() async {
    await widget.oneDriveOAuthClient.unlink();
    if (!mounted) return;
    setState(() {
      _oneDriveLinked = false;
      _oneDriveEmail = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('已連結的雲端匯入帳戶')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('cloud_account_settings_loading_indicator'),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProviderTile(
                    title: 'Google Drive',
                    keyPrefix: 'google_drive',
                    linked: _googleDriveLinked,
                    linking: _googleDriveLinking,
                    email: _googleDriveEmail,
                    onLink: _linkGoogleDrive,
                    onUnlink: _unlinkGoogleDrive,
                  ),
                  const SizedBox(height: 24),
                  _buildProviderTile(
                    title: 'OneDrive',
                    keyPrefix: 'onedrive',
                    linked: _oneDriveLinked,
                    linking: _oneDriveLinking,
                    email: _oneDriveEmail,
                    onLink: _linkOneDrive,
                    onUnlink: _unlinkOneDrive,
                  ),
                ],
              ),
            ),
    );
  }

  /// 單一 provider 的連結狀態區塊，`keyPrefix` 對應
  /// `cloud_account_settings_<keyPrefix>_...` 系列既有測試 key 慣例
  /// （Google Drive 沿用 Issue 1 已核准的 `google_drive` 前綴，維持不變，
  /// 不因抽出共用 helper 而變動既有 key 字串，避免破壞 Issue 1 既有
  /// widget test）。
  Widget _buildProviderTile({
    required String title,
    required String keyPrefix,
    required bool linked,
    required bool linking,
    required String? email,
    required VoidCallback onLink,
    required VoidCallback onUnlink,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (linked) ...[
          Text(
            '已連結：${email ?? ''}',
            key: Key('cloud_account_settings_${keyPrefix}_linked_email'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            key: Key('cloud_account_settings_${keyPrefix}_unlink_button'),
            onPressed: onUnlink,
            child: const Text('解除連結'),
          ),
        ] else ...[
          Text(
            '未連結',
            key: Key('cloud_account_settings_${keyPrefix}_unlinked_text'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            key: Key('cloud_account_settings_${keyPrefix}_link_button'),
            onPressed: linking ? null : onLink,
            child: linking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('連結'),
          ),
        ],
      ],
    );
  }
}
```

**注意**：`_buildProviderTile()` 是把 Issue 1 的 `_buildGoogleDriveTile()` 泛化為兩個 provider 共用的私有 helper——這是因為擴充 OneDrive 後兩段 UI 完全同構（只有標題文字/key 前綴/資料來源不同），此時再各寫一份重複的 `_buildOneDriveTile()` 會是單純複製貼上，泛化成單一 helper 更符合 DRY；`keyPrefix` 對外可見的既有 test key 字串（`cloud_account_settings_google_drive_*`）刻意維持與 Issue 1 完全相同，不因這次重構而改變，Issue 1 既有 3 個 widget test 不需要修改即可繼續通過。

- [ ] **Step 4：執行測試確認通過**

執行：`flutter test test/screens/cloud_account_settings_screen_test.dart`
預期：全數 PASS（含 Issue 1 既有 3 個測試，零回歸）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/cloud_account_settings_screen.dart app/test/screens/cloud_account_settings_screen_test.dart
git commit -m "feat(epic-29): Issue 2——CloudAccountSettingsScreen 擴充 OneDrive 區塊"
```

---

## Task 3：貫穿注入 `oneDriveOAuthClient`（`SettingsScreen`→`LibraryScreen`→`ElinkBookApp`→`main.dart`）

**Files：**
- Modify: `app/lib/screens/settings_screen.dart`
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/test/screens/settings_screen_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `OneDriveOAuthClient`，Task 2 的擴充後 `CloudAccountSettingsScreen`。
- Produces：`SettingsScreen`／`LibraryScreen`／`ElinkBookApp` 新增可選具名參數 `oneDriveOAuthClient`，`main.dart` 正式組裝真實實例。

- [ ] **Step 1：修正既有 `settings_screen_test.dart` 的 `CloudAccountSettingsScreen` 呼叫測試**

在 `app/test/screens/settings_screen_test.dart` 找到：

```dart
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';
import 'package:elinkbook/screens/settings_screen.dart';
```

改為：

```dart
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';
import 'package:elinkbook/cloud_import/onedrive_oauth_client.dart';
import 'package:elinkbook/screens/settings_screen.dart';
```

找到：

```dart
  testWidgets('SettingsScreen 顯示「已連結的雲端匯入帳戶」入口，點擊導航至 CloudAccountSettingsScreen',
      (tester) async {
    final cloudAccountRepository = FakeCloudAccountRepository();
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        prefsManager: FakeReaderPrefsManager(),
        cloudAccountRepository: cloudAccountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: cloudAccountRepository),
      ),
    ));
```

改為：

```dart
  testWidgets('SettingsScreen 顯示「已連結的雲端匯入帳戶」入口，點擊導航至 CloudAccountSettingsScreen',
      (tester) async {
    final cloudAccountRepository = FakeCloudAccountRepository();
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        prefsManager: FakeReaderPrefsManager(),
        cloudAccountRepository: cloudAccountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: cloudAccountRepository),
        oneDriveOAuthClient:
            OneDriveOAuthClient(accountRepository: cloudAccountRepository),
      ),
    ));
```

- [ ] **Step 2：執行測試確認失敗**

執行：`flutter test test/screens/settings_screen_test.dart --plain-name "已連結的雲端匯入帳戶"`
預期：編譯失敗（`SettingsScreen` 沒有 `oneDriveOAuthClient` 具名參數；即使有此參數，`CloudAccountSettingsScreen` 建構呼叫因缺少必要參數 `oneDriveOAuthClient` 而編譯失敗，因為 Task 2 已把它改為必要參數）。

- [ ] **Step 3：`SettingsScreen` 新增 `oneDriveOAuthClient` 參數**

在 `app/lib/screens/settings_screen.dart` 找到：

```dart
import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/google_drive_oauth_client.dart';
import '../reader/custom_fonts_repository.dart';
```

改為：

```dart
import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/google_drive_oauth_client.dart';
import '../cloud_import/onedrive_oauth_client.dart';
import '../reader/custom_fonts_repository.dart';
```

找到：

```dart
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;

  const SettingsScreen({
    super.key,
    required this.prefsManager,
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.customFontsRepository,
    this.syncAccountRepository,
    this.syncClient,
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
  });
```

改為：

```dart
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
  final OneDriveOAuthClient? oneDriveOAuthClient;

  const SettingsScreen({
    super.key,
    required this.prefsManager,
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.customFontsRepository,
    this.syncAccountRepository,
    this.syncClient,
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
  });
```

找到「已連結的雲端匯入帳戶」`ListTile`：

```dart
          ListTile(
            key: const Key('settings_cloud_account_button'),
            title: const Text('已連結的雲端匯入帳戶'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.cloudAccountRepository == null ||
                    widget.googleDriveOAuthClient == null
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => CloudAccountSettingsScreen(
                          cloudAccountRepository: widget.cloudAccountRepository!,
                          googleDriveOAuthClient: widget.googleDriveOAuthClient!,
                        ),
                      ),
                    );
                  },
          ),
```

改為：

```dart
          ListTile(
            key: const Key('settings_cloud_account_button'),
            title: const Text('已連結的雲端匯入帳戶'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.cloudAccountRepository == null ||
                    widget.googleDriveOAuthClient == null ||
                    widget.oneDriveOAuthClient == null
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => CloudAccountSettingsScreen(
                          cloudAccountRepository: widget.cloudAccountRepository!,
                          googleDriveOAuthClient: widget.googleDriveOAuthClient!,
                          oneDriveOAuthClient: widget.oneDriveOAuthClient!,
                        ),
                      ),
                    );
                  },
          ),
```

- [ ] **Step 4：執行測試確認通過**

執行：`flutter test test/screens/settings_screen_test.dart`
預期：全數 PASS。

- [ ] **Step 5：`LibraryScreen` 新增參數並貫穿兩個既有呼叫點**

在 `app/lib/screens/library_screen.dart` 找到：

```dart
import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/google_drive_oauth_client.dart';
import '../library/book_content_fingerprint.dart';
```

改為：

```dart
import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/google_drive_oauth_client.dart';
import '../cloud_import/onedrive_oauth_client.dart';
import '../library/book_content_fingerprint.dart';
```

找到：

```dart
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
  final RemoteServerRepository? remoteServerRepository;
```

改為：

```dart
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
  final OneDriveOAuthClient? oneDriveOAuthClient;
  final RemoteServerRepository? remoteServerRepository;
```

找到建構子內：

```dart
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.remoteServerRepository,
```

改為：

```dart
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
    this.remoteServerRepository,
```

找到分類篩選畫面的自我遞迴導航點：

```dart
              cloudAccountRepository: widget.cloudAccountRepository,
              googleDriveOAuthClient: widget.googleDriveOAuthClient,
              currentTheme: widget.currentTheme,
```

改為：

```dart
              cloudAccountRepository: widget.cloudAccountRepository,
              googleDriveOAuthClient: widget.googleDriveOAuthClient,
              oneDriveOAuthClient: widget.oneDriveOAuthClient,
              currentTheme: widget.currentTheme,
```

找到 `SettingsScreen` 建構呼叫點：

```dart
                  cloudAccountRepository: widget.cloudAccountRepository,
                  googleDriveOAuthClient: widget.googleDriveOAuthClient,
                ),
```

改為：

```dart
                  cloudAccountRepository: widget.cloudAccountRepository,
                  googleDriveOAuthClient: widget.googleDriveOAuthClient,
                  oneDriveOAuthClient: widget.oneDriveOAuthClient,
                ),
```

- [ ] **Step 6：`main.dart` 組裝真實實例並貫穿 `ElinkBookApp`**

在 `app/lib/main.dart` 找到：

```dart
import 'cloud_import/cloud_account_repository.dart';
import 'cloud_import/google_drive_oauth_client.dart';
import 'cloud_import/secure_storage_cloud_account_repository.dart';
import 'library/book_content_fingerprint.dart';
```

改為：

```dart
import 'cloud_import/cloud_account_repository.dart';
import 'cloud_import/google_drive_oauth_client.dart';
import 'cloud_import/onedrive_oauth_client.dart';
import 'cloud_import/secure_storage_cloud_account_repository.dart';
import 'library/book_content_fingerprint.dart';
```

找到：

```dart
  // epic-29-cloud-import Issue 1：雲端匯入帳號模組
  final cloudAccountRepository = SecureStorageCloudAccountRepository();
  final googleDriveOAuthClient = GoogleDriveOAuthClient(
    accountRepository: cloudAccountRepository,
  );
```

改為：

```dart
  // epic-29-cloud-import Issue 1/2：雲端匯入帳號模組
  final cloudAccountRepository = SecureStorageCloudAccountRepository();
  final googleDriveOAuthClient = GoogleDriveOAuthClient(
    accountRepository: cloudAccountRepository,
  );
  final oneDriveOAuthClient = OneDriveOAuthClient(
    accountRepository: cloudAccountRepository,
  );
```

找到 `runApp(ElinkBookApp(...))` 內：

```dart
      cloudAccountRepository: cloudAccountRepository,
      googleDriveOAuthClient: googleDriveOAuthClient,
      remoteServerRepository: remoteServerRepository,
```

改為：

```dart
      cloudAccountRepository: cloudAccountRepository,
      googleDriveOAuthClient: googleDriveOAuthClient,
      oneDriveOAuthClient: oneDriveOAuthClient,
      remoteServerRepository: remoteServerRepository,
```

找到 `ElinkBookApp` 的欄位宣告：

```dart
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
  final RemoteServerRepository? remoteServerRepository;
```

改為：

```dart
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
  final OneDriveOAuthClient? oneDriveOAuthClient;
  final RemoteServerRepository? remoteServerRepository;
```

找到 `ElinkBookApp` 建構子內：

```dart
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.remoteServerRepository,
```

改為：

```dart
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
    this.oneDriveOAuthClient,
    this.remoteServerRepository,
```

找到 `build()` 內 `LibraryScreen(...)` 建構呼叫點：

```dart
        cloudAccountRepository: widget.cloudAccountRepository,
        googleDriveOAuthClient: widget.googleDriveOAuthClient,
        remoteServerRepository: widget.remoteServerRepository,
```

改為：

```dart
        cloudAccountRepository: widget.cloudAccountRepository,
        googleDriveOAuthClient: widget.googleDriveOAuthClient,
        oneDriveOAuthClient: widget.oneDriveOAuthClient,
        remoteServerRepository: widget.remoteServerRepository,
```

- [ ] **Step 7：執行完整測試套件與靜態分析確認零回歸**

執行：`flutter analyze`
預期："No issues found!"

執行：`flutter test`
預期：全數 PASS（Google Drive 既有功能不受影響）。

- [ ] **Step 8：Commit**

```bash
git add app/lib/screens/settings_screen.dart app/lib/screens/library_screen.dart app/lib/main.dart app/test/screens/settings_screen_test.dart
git commit -m "feat(epic-29): Issue 2——貫穿注入 OneDriveOAuthClient 至 SettingsScreen"
```

---

## Self-Review（撰寫計劃時的自我檢查記錄）

**1. Spec 涵蓋範圍檢查：**
- `spec.md`「OAuth 登入機制」的 OneDrive／Microsoft Graph `Files.Read` scope、系統瀏覽器＋PKCE＋`state`、自訂 scheme redirect URI → Task 1 涵蓋。
- `issues.md` Issue 2「沿用 Issue 1 的 `CloudAccountRepository`」→ Global Constraints 已明確排除重複修改，Task 1/2 皆只消費既有介面。
- `issues.md` Issue 2「`AndroidManifest.xml` 新增 OneDrive 專用 redirect URI intent-filter（與 Google 反向客戶端 ID 格式不同，走自訂 scheme）」→ Task 1 Step 2 涵蓋，且與 Google 既有 intent-filter 並存、不互相修改。
- `issues.md` Issue 2「設定頁「已連結的雲端匯入帳戶」區塊擴充顯示 OneDrive 連結狀態」→ Task 2 涵蓋。
- `issues.md` Issue 2 單元測試要求逐項對照：設定頁區塊擴充後涵蓋 OneDrive 已連結/未連結狀態的 widget test（Task 2 Step 1）、OneDrive OAuth 實際登入流程不做自動化測試（Task 1 僅測試不涉及瀏覽器的 `ensureValidAccessToken()`）、驗收標準「Google Drive 既有功能不受影響」（Task 2 Step 1 第三個新測試明確驗證兩個 provider 狀態互不干擾；Task 1/2/3 每個 Step 皆執行完整 `flutter test` 確認零回歸）——全數涵蓋。

**2. 佔位符掃描：** 全文檢查過，所有 Step 皆含完整可執行的程式碼區塊。`onedrive_oauth_config.dart` 的用戶端 ID 常數值同 Issue 1 的 Google 版本，是必要的外部設定佔位（Azure 應用程式註冊各不相同，無法從程式碼庫推導），已在 Global Constraints 與檔案內 doc comment 明確標註。

**3. 型別一致性檢查：** `OneDriveOAuthClient` 的 `link()`/`unlink()`/`ensureValidAccessToken()` 方法簽章與 Issue 1 的 `GoogleDriveOAuthClient` 完全一致（`Future<bool>`/`Future<void>`/`Future<String?>`），供 `CloudAccountSettingsScreen` 以相同呼叫模式使用；`CloudAccountSettingsScreen` 內 `_buildProviderTile()` 的具名參數與 Task 2/3 各處呼叫一致；`SettingsScreen`／`LibraryScreen`／`ElinkBookApp` 三層的 `oneDriveOAuthClient` 具名參數命名與型別（可選、nullable）與既有 `googleDriveOAuthClient` 完全對稱。既有 `cloud_account_settings_google_drive_*` 系列 key 字串在 Task 2 重構後維持不變，確認 Issue 1 既有 widget test 不受影響。
