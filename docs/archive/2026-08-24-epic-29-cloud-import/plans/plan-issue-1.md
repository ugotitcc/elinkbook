# Epic 29 Issue 1：Google Drive 帳號連結／解除連結 實作計劃

> **給執行者：** 本計劃必須搭配 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行。每個 Step 用 checkbox（`- [ ]`）追蹤，完成後改為 `- [x]`。

**Goal：** 讓使用者能在設定頁用真實 Google 帳號完成 Google Drive 匯入來源帳號的連結／解除連結，帳號狀態持久化並可跨 App 重啟保留，token 過期時能靜默續期。

**Architecture：** 新增 `app/lib/cloud_import/` 模組，比照 `app/lib/sync/`（`SyncAccountRepository`＋`SyncClient` 的既有分工：repository 只負責「登入後怎麼存」，client 負責「怎麼登入／怎麼續期」）與 `app/lib/remote/`（`RemoteServerRepository` 抽象介面＋`SqliteRemoteServerRepository` 實作＋`FakeRemoteServerRepository` 測試替身三件套）兩個既有模式的組合：`CloudAccountRepository`（抽象介面，純儲存，以 `CloudProvider` enum 區分 provider，供 Issue 2 的 OneDrive 沿用）＋`SecureStorageCloudAccountRepository`（`FlutterSecureStorage` 實作，讀取失敗安全退回未連結）＋`FakeCloudAccountRepository`（測試替身）；`GoogleDriveOAuthClient` 是獨立於 repository 之外的一層，持有系統瀏覽器 OAuth Authorization Code + PKCE 流程與 token 換發/續期的所有細節，UI 只認識這個 client、不直接碰 repository 的寫入邏輯（比照 `SyncClient`）。設定頁新增 `CloudAccountSettingsScreen` 子頁面（比照 `SyncSettingsScreen` 的載入中/已連結/未連結三態結構），透過既有 `SettingsScreen`→`LibraryScreen`→`ElinkBookApp`→`main.dart` 的既定可選（nullable）參數逐層貫穿慣例（`syncAccountRepository`／`remoteServerRepository` 皆已是這個模式的先例）注入。

**Tech Stack：** Flutter／Dart、`flutter_secure_storage`（已是既有依賴）、`crypto`（已是既有依賴，PKCE code challenge 用）、`http`（已是既有依賴，token 端點呼叫用）、`flutter_web_auth_2`（本 Issue 新增，系統瀏覽器 OAuth redirect 攔截）。

**Spec：** `docs/epics/epic-29-cloud-import/spec.md`（Architecting 階段產出，本 Issue 對應「帳號模組：`CloudAccountRepository`」「OAuth 登入機制」「UI 落地位置」三節，已通過 `reviews/review-spec.md` 審查修訂）。

## Global Constraints

- `CloudProvider` enum 目前只需要 `googleDrive` 一個 case 真正可用（`oneDrive` case 由 Issue 2 接手，但 enum 本身兩個 case 皆須存在，供 `CloudAccountRepository` 介面的 provider 參數型別完整）。
- Google Drive OAuth scope 採 `https://www.googleapis.com/auth/drive.readonly`（唯讀存取使用者所有檔案，非 `drive.file`）＋`email`（供取得帳號 email 顯示用）——理由見 `spec.md`「OAuth 登入機制」：Discovery 階段已定案「使用者可瀏覽任意雲端資料夾挑書」，`drive.file` 無法達成。
- OAuth 一律系統瀏覽器（`flutter_web_auth_2`）導向的 Authorization Code Flow ＋ PKCE（RFC 7636）＋ `state` 參數，**不使用內嵌 WebView**（Google 政策明確禁止）。
- **Google Cloud Console 用戶端 ID 是本專案程式碼庫無法內含的外部設定值**——`app/lib/cloud_import/google_oauth_config.dart` 內的 `googleOAuthClientId`／`googleOAuthRedirectScheme` 常數需要開發者各自從自己的 Google Cloud Console 專案取得真實值填入，這是 App 上線前的必要人工設定步驟（`spec.md`「Google 應用程式驗證是外部時間風險」），不是本計劃可以/應該補全的程式碼缺漏；`AndroidManifest.xml` 新增的 intent-filter `scheme` 必須與 `googleOAuthRedirectScheme` 完全一致，兩處變更需同步維護。
- Google OAuth 實際登入流程（真實瀏覽器導向＋換 token）**不做自動化測試**，留待真機/人工用真實 Google 帳號驗證（`issues.md` Issue 1 已定案的測試範圍）；`GoogleDriveOAuthClient.ensureValidAccessToken()` 的 token 續期 HTTP 邏輯可用 `MockClient` 測試，不受此限制。
- 完成後 `flutter analyze` 必須乾淨（"No issues found!"），`flutter test` 必須全數通過、零回歸。
- 所有程式碼註解、doc comment、commit message、本計劃文件本身，一律使用正體中文（zh-TW），不得出現簡體中文。

---

## Task 1：`CloudAccountRepository` 抽象介面＋`SecureStorageCloudAccountRepository` 實作＋`FakeCloudAccountRepository` 測試替身

**Files：**
- Create: `app/lib/cloud_import/cloud_provider.dart`
- Create: `app/lib/cloud_import/cloud_account_repository.dart`
- Create: `app/lib/cloud_import/secure_storage_cloud_account_repository.dart`
- Create: `app/test/support/fake_cloud_account_repository.dart`
- Test: `app/test/cloud_import/secure_storage_cloud_account_repository_test.dart`

**Interfaces：**
- Produces：
  - `enum CloudProvider { googleDrive, oneDrive }`
  - `class CloudAccountTokens { final String accessToken; final String refreshToken; final String email; final DateTime expiresAt; }`
  - `abstract class CloudAccountRepository { Future<void> link(CloudProvider, CloudAccountTokens); Future<void> unlink(CloudProvider); Future<bool> isLinked(CloudProvider); Future<String?> loadAccountEmail(CloudProvider); Future<CloudAccountTokens?> loadTokens(CloudProvider); }`
  - `class SecureStorageCloudAccountRepository implements CloudAccountRepository`
  - `class FakeCloudAccountRepository implements CloudAccountRepository`（供 Task 2/3/4 測試使用）

- [x] **Step 1：建立 `CloudProvider` enum**

建立 `app/lib/cloud_import/cloud_provider.dart`：

```dart
/// 雲端匯入來源帳號的 provider（epic-29-cloud-import，spec.md「帳號模組」）：
/// 與 `CONTEXT.md`「雲端匯入來源帳號」對應，語意上與 `epic-30`「遠端書庫」
/// （Calibre／OPDS，`RemoteServerProfile`）完全獨立，不共用型別。[oneDrive]
/// 目前僅預留資料結構，實際串接留給 Issue 2。
enum CloudProvider { googleDrive, oneDrive }
```

- [x] **Step 2：建立 `CloudAccountRepository` 抽象介面**

建立 `app/lib/cloud_import/cloud_account_repository.dart`：

```dart
import 'cloud_provider.dart';

/// 單一雲端匯入來源帳號連結後取得的憑證組合（spec.md「帳號模組」）。
/// [expiresAt] 為 [accessToken] 的到期時間，供 `GoogleDriveOAuthClient`
/// 判斷是否需要靜默續期。
class CloudAccountTokens {
  final String accessToken;
  final String refreshToken;
  final String email;
  final DateTime expiresAt;

  const CloudAccountTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.email,
    required this.expiresAt,
  });
}

/// 雲端匯入來源帳號的持久化介面（spec.md「帳號模組：`CloudAccountRepository`」）：
/// 單一 repository 處理所有 provider（不拆成兩個類別），所有方法皆以
/// [CloudProvider] 參數區分。刻意只負責「怎麼存」，不知道 OAuth 流程細節
/// （怎麼登入／怎麼續期是 `GoogleDriveOAuthClient` 的職責，比照
/// `SyncAccountRepository`／`SyncClient` 的既有分工）。
abstract class CloudAccountRepository {
  Future<void> link(CloudProvider provider, CloudAccountTokens tokens);
  Future<void> unlink(CloudProvider provider);
  Future<bool> isLinked(CloudProvider provider);
  Future<String?> loadAccountEmail(CloudProvider provider);
  Future<CloudAccountTokens?> loadTokens(CloudProvider provider);
}
```

- [x] **Step 3：寫入失敗的 `SecureStorageCloudAccountRepository` 測試**

建立 `app/test/cloud_import/secure_storage_cloud_account_repository_test.dart`：

```dart
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/cloud_import/cloud_account_repository.dart';
import 'package:elinkbook/cloud_import/cloud_provider.dart';
import 'package:elinkbook/cloud_import/secure_storage_cloud_account_repository.dart';

/// 只在本檔案內使用，不需要獨立於 `test/support/` 建檔（YAGNI，比照
/// `sync_account_repository_test.dart` 既有慣例）。
class _ThrowingSecureStoragePlatform extends FlutterSecureStoragePlatform {
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    throw PlatformException(code: 'read_error', message: 'Keystore 損毀');
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {}

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      false;

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {}

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      {};

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {}
}

void main() {
  late FlutterSecureStoragePlatform originalPlatform;

  setUp(() {
    originalPlatform = FlutterSecureStoragePlatform.instance;
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
  });

  tearDown(() {
    FlutterSecureStoragePlatform.instance = originalPlatform;
  });

  final tokens = CloudAccountTokens(
    accessToken: 'access-1',
    refreshToken: 'refresh-1',
    email: 'reader@example.com',
    expiresAt: DateTime.fromMillisecondsSinceEpoch(2000000000000),
  );

  test('未 link 時 isLinked 回傳 false，loadAccountEmail／loadTokens 回傳 null', () async {
    final repo = SecureStorageCloudAccountRepository();

    expect(await repo.isLinked(CloudProvider.googleDrive), false);
    expect(await repo.loadAccountEmail(CloudProvider.googleDrive), isNull);
    expect(await repo.loadTokens(CloudProvider.googleDrive), isNull);
  });

  test('link 後 isLinked 回傳 true，loadAccountEmail／loadTokens 回傳正確值', () async {
    final repo = SecureStorageCloudAccountRepository();

    await repo.link(CloudProvider.googleDrive, tokens);

    expect(await repo.isLinked(CloudProvider.googleDrive), true);
    expect(await repo.loadAccountEmail(CloudProvider.googleDrive), 'reader@example.com');
    final loaded = await repo.loadTokens(CloudProvider.googleDrive);
    expect(loaded?.accessToken, 'access-1');
    expect(loaded?.refreshToken, 'refresh-1');
    expect(loaded?.expiresAt, tokens.expiresAt);
  });

  test('link 後 unlink，isLinked 回傳 false 且 loadTokens 回傳 null', () async {
    final repo = SecureStorageCloudAccountRepository();
    await repo.link(CloudProvider.googleDrive, tokens);

    await repo.unlink(CloudProvider.googleDrive);

    expect(await repo.isLinked(CloudProvider.googleDrive), false);
    expect(await repo.loadTokens(CloudProvider.googleDrive), isNull);
  });

  test('兩個 provider 各自獨立：link 一個不影響另一個的連結狀態', () async {
    final repo = SecureStorageCloudAccountRepository();

    await repo.link(CloudProvider.googleDrive, tokens);

    expect(await repo.isLinked(CloudProvider.googleDrive), true);
    expect(await repo.isLinked(CloudProvider.oneDrive), false);
  });

  test('Keystore 讀取拋出例外時，isLinked／loadAccountEmail／loadTokens 皆安全回退為 false/null', () async {
    FlutterSecureStoragePlatform.instance = _ThrowingSecureStoragePlatform();
    final repo = SecureStorageCloudAccountRepository();

    expect(await repo.isLinked(CloudProvider.googleDrive), false);
    expect(await repo.loadAccountEmail(CloudProvider.googleDrive), isNull);
    expect(await repo.loadTokens(CloudProvider.googleDrive), isNull);
  });
}
```

- [x] **Step 4：執行測試確認失敗**

執行：`flutter test test/cloud_import/secure_storage_cloud_account_repository_test.dart`
預期：編譯失敗（`SecureStorageCloudAccountRepository` 尚未定義）。

- [x] **Step 5：實作 `SecureStorageCloudAccountRepository`**

建立 `app/lib/cloud_import/secure_storage_cloud_account_repository.dart`：

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'cloud_account_repository.dart';
import 'cloud_provider.dart';

/// [CloudAccountRepository] 的 `FlutterSecureStorage` 實作（Android
/// Keystore／iOS Keychain 加密），比照 `SyncAccountRepository` 既有的安全
/// 儲存與讀取失敗回退模式。每個 provider 的四個欄位各自存成獨立 key
/// （前綴 `cloud_account_<provider>_`），彼此互不影響。
class SecureStorageCloudAccountRepository implements CloudAccountRepository {
  final FlutterSecureStorage _secureStorage;

  SecureStorageCloudAccountRepository({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  String _accessTokenKey(CloudProvider p) => 'cloud_account_${p.name}_access_token';
  String _refreshTokenKey(CloudProvider p) => 'cloud_account_${p.name}_refresh_token';
  String _emailKey(CloudProvider p) => 'cloud_account_${p.name}_email';
  String _expiresAtKey(CloudProvider p) => 'cloud_account_${p.name}_expires_at';

  @override
  Future<void> link(CloudProvider provider, CloudAccountTokens tokens) async {
    await _secureStorage.write(key: _accessTokenKey(provider), value: tokens.accessToken);
    await _secureStorage.write(key: _refreshTokenKey(provider), value: tokens.refreshToken);
    await _secureStorage.write(key: _emailKey(provider), value: tokens.email);
    await _secureStorage.write(
      key: _expiresAtKey(provider),
      value: tokens.expiresAt.millisecondsSinceEpoch.toString(),
    );
  }

  @override
  Future<void> unlink(CloudProvider provider) async {
    await _secureStorage.delete(key: _accessTokenKey(provider));
    await _secureStorage.delete(key: _refreshTokenKey(provider));
    await _secureStorage.delete(key: _emailKey(provider));
    await _secureStorage.delete(key: _expiresAtKey(provider));
  }

  @override
  Future<bool> isLinked(CloudProvider provider) async =>
      await _readSafe(_accessTokenKey(provider)) != null;

  @override
  Future<String?> loadAccountEmail(CloudProvider provider) => _readSafe(_emailKey(provider));

  @override
  Future<CloudAccountTokens?> loadTokens(CloudProvider provider) async {
    final accessToken = await _readSafe(_accessTokenKey(provider));
    final refreshToken = await _readSafe(_refreshTokenKey(provider));
    final email = await _readSafe(_emailKey(provider));
    final expiresAtRaw = await _readSafe(_expiresAtKey(provider));
    if (accessToken == null || refreshToken == null || email == null || expiresAtRaw == null) {
      return null;
    }
    return CloudAccountTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      email: email,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(int.parse(expiresAtRaw)),
    );
  }

  /// 部分機種（OEM 客製 Android Keystore 有瑕疵的裝置）讀取時會拋出
  /// `PlatformException`，比照 `SyncAccountRepository` 既有的安全回退模式：
  /// 讀取失敗一律視同「該欄位不存在」，不拋出例外中斷呼叫端。
  Future<String?> _readSafe(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (_) {
      return null;
    }
  }
}
```

- [x] **Step 6：執行測試確認通過**

執行：`flutter test test/cloud_import/secure_storage_cloud_account_repository_test.dart`
預期：全數 PASS。

- [x] **Step 7：建立 `FakeCloudAccountRepository`**

建立 `app/test/support/fake_cloud_account_repository.dart`：

```dart
import 'package:elinkbook/cloud_import/cloud_account_repository.dart';
import 'package:elinkbook/cloud_import/cloud_provider.dart';

/// 供 widget test 使用的記憶體內 [CloudAccountRepository] 假實作（比照
/// `FakeRemoteServerRepository`／`FakeLibraryRepository` 既有命名慣例），
/// 避免 widget test 依賴真實 `FlutterSecureStorage`。
class FakeCloudAccountRepository implements CloudAccountRepository {
  final Map<CloudProvider, CloudAccountTokens> _linked = {};

  @override
  Future<void> link(CloudProvider provider, CloudAccountTokens tokens) async {
    _linked[provider] = tokens;
  }

  @override
  Future<void> unlink(CloudProvider provider) async {
    _linked.remove(provider);
  }

  @override
  Future<bool> isLinked(CloudProvider provider) async => _linked.containsKey(provider);

  @override
  Future<String?> loadAccountEmail(CloudProvider provider) async => _linked[provider]?.email;

  @override
  Future<CloudAccountTokens?> loadTokens(CloudProvider provider) async => _linked[provider];
}
```

- [x] **Step 8：執行完整測試套件確認零回歸**

執行：`flutter test`
預期：全數 PASS（`FakeCloudAccountRepository` 目前尚無呼叫端，僅需確認編譯成功、不影響既有測試）。

- [x] **Step 9：Commit**

```bash
git add app/lib/cloud_import/cloud_provider.dart app/lib/cloud_import/cloud_account_repository.dart app/lib/cloud_import/secure_storage_cloud_account_repository.dart app/test/support/fake_cloud_account_repository.dart app/test/cloud_import/secure_storage_cloud_account_repository_test.dart
git commit -m "feat(epic-29): Issue 1——CloudAccountRepository 抽象介面/SecureStorage 實作/Fake 測試替身"
```

---

## Task 2：Google OAuth PKCE 登入流程（`GoogleDriveOAuthClient`）＋ AndroidManifest redirect URI

**Files：**
- Modify: `app/pubspec.yaml`
- Create: `app/lib/cloud_import/google_oauth_config.dart`
- Create: `app/lib/cloud_import/google_drive_oauth_client.dart`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Test: `app/test/cloud_import/google_drive_oauth_client_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `CloudAccountRepository`／`CloudAccountTokens`／`CloudProvider`／`FakeCloudAccountRepository`。
- Produces：`class GoogleDriveOAuthClient { Future<bool> link(); Future<void> unlink(); Future<String?> ensureValidAccessToken(); }`，供 Task 3（UI）與後續 Issue 3（Google Drive 瀏覽＋下載，呼叫 `ensureValidAccessToken()` 取得可用 access token）使用。

- [x] **Step 1：新增 `flutter_web_auth_2` 依賴**

執行：`flutter pub add flutter_web_auth_2`

執行後確認 `app/pubspec.yaml` 的 `dependencies:` 區塊新增了一行 `flutter_web_auth_2: ^<版本號>`（實際版本由 `flutter pub add` 自動解析為當下相容的最新版本，`spec.md`「Further Notes」已定案不在計劃中寫死版本號）。

- [x] **Step 2：執行 `flutter pub get` 確認無相容性衝突**

執行：`flutter pub get`
預期：成功解析，無版本衝突錯誤。若出現衝突，對照 `pubspec.yaml` 內既有的 `win32`/`package_info_plus` 版本鎖定歷史註解排查（`spec.md`「Further Notes」已標記此風險）。

- [x] **Step 3：建立 Google OAuth 設定常數檔**

建立 `app/lib/cloud_import/google_oauth_config.dart`：

```dart
/// Google Cloud Console 建立的 OAuth 2.0 用戶端 ID（Android 應用程式類型，
/// 公開客戶端、無 client secret，符合 spec.md「OAuth 登入機制」對 PKCE
/// 公開客戶端流程的要求）。
///
/// **這是外部設定值，無法寫死在版本控制的程式碼內視為「已完成」**——每個
/// 開發者/建置環境需要各自從自己的 Google Cloud Console 專案取得真實值
/// 填入下方常數，才能實際發起登入流程（`spec.md`「Google 應用程式驗證是
/// 外部時間風險」）。開發/測試期間可用 Google Cloud Console 的「測試使用者」
/// 白名單機制讓白名單內帳號正常登入（僅顯示「未驗證應用程式」過場警告）。
const String googleOAuthClientId = 'YOUR_GOOGLE_OAUTH_CLIENT_ID.apps.googleusercontent.com';

/// 對應 [googleOAuthClientId] 的反向客戶端 ID格式 redirect URI scheme
/// （Android 慣例，`spec.md`「OAuth 登入機制」審查 Minor #5 採納）。
/// **必須與 `AndroidManifest.xml` 新增的 intent-filter `android:scheme`
/// 完全一致**，兩處變更需同步維護——實際值同樣需要開發者從 Google Cloud
/// Console 取得真實用戶端 ID 後反轉網域片段而來。
const String googleOAuthRedirectScheme =
    'com.googleusercontent.apps.YOUR_GOOGLE_OAUTH_CLIENT_ID';

const String googleOAuthRedirectUri = '$googleOAuthRedirectScheme:/oauth2redirect';
```

- [x] **Step 4：`AndroidManifest.xml` 新增 redirect URI intent-filter**

在 `app/android/app/src/main/AndroidManifest.xml` 找到 `.MainActivity` 既有的 launcher intent-filter：

```xml
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
```

在其後新增（`.MainActivity` 已宣告 `android:launchMode="singleTop"`，OAuth redirect 導回時不會重啟整個 App）：

```xml
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="com.googleusercontent.apps.YOUR_GOOGLE_OAUTH_CLIENT_ID"/>
            </intent-filter>
```

`android:scheme` 的值必須與 Step 3 的 `googleOAuthRedirectScheme` 常數完全一致；開發者填入真實用戶端 ID 時，這兩處需同步更新（Global Constraints 已註明）。

- [x] **Step 5：寫入失敗的 `ensureValidAccessToken()` 測試**

建立 `app/test/cloud_import/google_drive_oauth_client_test.dart`：

```dart
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
}
```

- [x] **Step 6：執行測試確認失敗**

執行：`flutter test test/cloud_import/google_drive_oauth_client_test.dart`
預期：編譯失敗（`GoogleDriveOAuthClient` 尚未定義）。

- [x] **Step 7：實作 `GoogleDriveOAuthClient`**

建立 `app/lib/cloud_import/google_drive_oauth_client.dart`：

```dart
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import 'cloud_account_repository.dart';
import 'cloud_provider.dart';
import 'google_oauth_config.dart';

const _authorizationEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
const _userInfoEndpoint = 'https://www.googleapis.com/oauth2/v2/userinfo';
const _driveReadonlyScope = 'https://www.googleapis.com/auth/drive.readonly';

/// Google Drive 匯入來源帳號的 OAuth 登入流程執行者（spec.md「OAuth 登入
/// 機制」）：負責「怎麼登入／怎麼續期」，登入成功後把憑證交給
/// [CloudAccountRepository] 儲存（比照 `SyncClient` 對 `SyncAccountRepository`
/// 的既有分工），UI 層只呼叫這個 client，不直接碰 repository 的寫入邏輯。
class GoogleDriveOAuthClient {
  GoogleDriveOAuthClient({
    required CloudAccountRepository accountRepository,
    http.Client? httpClient,
  })  : _accountRepository = accountRepository,
        _httpClient = httpClient ?? http.Client();

  final CloudAccountRepository _accountRepository;
  final http.Client _httpClient;

  /// 走系統瀏覽器 OAuth Authorization Code Flow ＋ PKCE（不使用內嵌
  /// WebView，Google 政策明確禁止）；成功後寫入 [CloudAccountRepository]
  /// 並回傳 `true`。使用者取消登入、`state` 不吻合（可能是 CSRF/攔截
  /// 攻擊）、或任何一步網路呼叫失敗，皆回傳 `false`，不拋出例外。
  Future<bool> link() async {
    final verifier = _generateRandomUrlSafeString(64);
    final challenge = _codeChallengeFor(verifier);
    final state = _generateRandomUrlSafeString(16);

    final authUrl = Uri.parse(_authorizationEndpoint).replace(queryParameters: {
      'client_id': googleOAuthClientId,
      'redirect_uri': googleOAuthRedirectUri,
      'response_type': 'code',
      'scope': '$_driveReadonlyScope email',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
      'access_type': 'offline',
      'prompt': 'consent',
    });

    String resultUrl;
    try {
      resultUrl = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: googleOAuthRedirectScheme,
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
        'client_id': googleOAuthClientId,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': googleOAuthRedirectUri,
      });
    } catch (_) {
      return false;
    }
    if (tokenResponse.statusCode != 200) return false;

    final tokenJson = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
    final accessToken = tokenJson['access_token'] as String?;
    final refreshToken = tokenJson['refresh_token'] as String?;
    final expiresIn = tokenJson['expires_in'] as int?;
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
      response = await _httpClient.post(Uri.parse(_tokenEndpoint), body: {
        'refresh_token': tokens.refreshToken,
        'client_id': googleOAuthClientId,
        'grant_type': 'refresh_token',
      });
    } catch (_) {
      return null;
    }
    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final newAccessToken = json['access_token'] as String?;
    final expiresIn = json['expires_in'] as int?;
    if (newAccessToken == null || expiresIn == null) return null;

    // Google 換發時通常不會回傳新的 refresh_token，沿用既有值。
    await _accountRepository.link(
      CloudProvider.googleDrive,
      CloudAccountTokens(
        accessToken: newAccessToken,
        refreshToken: tokens.refreshToken,
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
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['email'] as String?;
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

- [x] **Step 8：執行測試確認通過**

執行：`flutter test test/cloud_import/google_drive_oauth_client_test.dart`
預期：全數 PASS。

- [x] **Step 9：執行完整測試套件與靜態分析確認零回歸**

執行：`flutter analyze`
預期："No issues found!"

執行：`flutter test`
預期：全數 PASS。

- [x] **Step 10：Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/cloud_import/google_oauth_config.dart app/lib/cloud_import/google_drive_oauth_client.dart app/android/app/src/main/AndroidManifest.xml app/test/cloud_import/google_drive_oauth_client_test.dart
git commit -m "feat(epic-29): Issue 1——GoogleDriveOAuthClient（PKCE 登入/續期）與 AndroidManifest redirect URI"
```

---

## Task 3：設定頁子畫面 `CloudAccountSettingsScreen`

**Files：**
- Create: `app/lib/screens/cloud_account_settings_screen.dart`
- Test: `app/test/screens/cloud_account_settings_screen_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `CloudAccountRepository`／`CloudProvider`／`FakeCloudAccountRepository`，Task 2 的 `GoogleDriveOAuthClient`。
- Produces：`class CloudAccountSettingsScreen extends StatefulWidget { required CloudAccountRepository cloudAccountRepository; required GoogleDriveOAuthClient googleDriveOAuthClient; }`，供 Task 4 從 `SettingsScreen` 導航進入。

- [x] **Step 1：寫入失敗的 widget test**

建立 `app/test/screens/cloud_account_settings_screen_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/cloud_import/cloud_account_repository.dart';
import 'package:elinkbook/cloud_import/cloud_provider.dart';
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';
import 'package:elinkbook/screens/cloud_account_settings_screen.dart';

import '../support/fake_cloud_account_repository.dart';

void main() {
  testWidgets('未連結時顯示「未連結」與「連結」按鈕，不顯示 email', (tester) async {
    final accountRepository = FakeCloudAccountRepository();
    await tester.pumpWidget(MaterialApp(
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('cloud_account_settings_google_drive_unlinked_text')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('cloud_account_settings_google_drive_link_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('cloud_account_settings_google_drive_linked_email')),
      findsNothing,
    );
  });

  testWidgets('已連結時顯示帳號 email 與「解除連結」按鈕', (tester) async {
    final accountRepository = FakeCloudAccountRepository();
    await accountRepository.link(
      CloudProvider.googleDrive,
      CloudAccountTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        email: 'reader@example.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('已連結：reader@example.com'), findsOneWidget);
    expect(
      find.byKey(const Key('cloud_account_settings_google_drive_unlink_button')),
      findsOneWidget,
    );
  });

  testWidgets('點擊「解除連結」後畫面更新為未連結狀態', (tester) async {
    final accountRepository = FakeCloudAccountRepository();
    await accountRepository.link(
      CloudProvider.googleDrive,
      CloudAccountTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        email: 'reader@example.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: CloudAccountSettingsScreen(
        cloudAccountRepository: accountRepository,
        googleDriveOAuthClient:
            GoogleDriveOAuthClient(accountRepository: accountRepository),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cloud_account_settings_google_drive_unlink_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('cloud_account_settings_google_drive_unlinked_text')),
      findsOneWidget,
    );
    expect(await accountRepository.isLinked(CloudProvider.googleDrive), false);
  });
}
```

- [x] **Step 2：執行測試確認失敗**

執行：`flutter test test/screens/cloud_account_settings_screen_test.dart`
預期：編譯失敗（`CloudAccountSettingsScreen` 尚未定義）。

- [x] **Step 3：實作 `CloudAccountSettingsScreen`**

建立 `app/lib/screens/cloud_account_settings_screen.dart`：

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

- [x] **Step 4：執行測試確認通過**

執行：`flutter test test/screens/cloud_account_settings_screen_test.dart`
預期：全數 PASS。

- [x] **Step 5：Commit**

```bash
git add app/lib/screens/cloud_account_settings_screen.dart app/test/screens/cloud_account_settings_screen_test.dart
git commit -m "feat(epic-29): Issue 1——設定頁子畫面 CloudAccountSettingsScreen"
```

---

## Task 4：貫穿注入（`SettingsScreen`→`LibraryScreen`→`ElinkBookApp`→`main.dart`）

**Files：**
- Modify: `app/lib/screens/settings_screen.dart`
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/screens/settings_screen_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `CloudAccountRepository`，Task 2 的 `GoogleDriveOAuthClient`，Task 3 的 `CloudAccountSettingsScreen`。
- Produces：`SettingsScreen`／`LibraryScreen`／`ElinkBookApp` 新增可選具名參數 `cloudAccountRepository`／`googleDriveOAuthClient`，`main.dart` 正式組裝真實實例。

- [x] **Step 1：寫入失敗的 `SettingsScreen` 導航測試**

在 `app/test/screens/settings_screen_test.dart` 找到既有的「同步」入口測試（`'SettingsScreen 顯示「同步」入口，點擊導航至 SyncSettingsScreen'`）之後，插入：

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

    expect(
      find.byKey(const Key('settings_cloud_account_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('settings_cloud_account_button')));
    await tester.pumpAndSettle();

    expect(find.text('已連結的雲端匯入帳戶'), findsOneWidget);
  });
```

在該檔案頂部 import 區塊新增：

```dart
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';
```

```dart
import '../support/fake_cloud_account_repository.dart';
```

- [x] **Step 2：執行測試確認失敗**

執行：`flutter test test/screens/settings_screen_test.dart --plain-name "已連結的雲端匯入帳戶"`
預期：編譯失敗（`SettingsScreen` 沒有 `cloudAccountRepository`／`googleDriveOAuthClient` 具名參數）。

- [x] **Step 3：`SettingsScreen` 新增參數與 ListTile**

在 `app/lib/screens/settings_screen.dart` 頂部 import 區塊，找到：

```dart
import '../reader/custom_fonts_repository.dart';
import '../reader/reader_prefs_manager.dart';
import '../sync/sync_account_repository.dart';
import '../sync/sync_client.dart';
import '../theme/app_theme.dart';
import 'about_screen.dart';
import 'font_management_screen.dart';
import 'nav_zone_settings_screen.dart';
import 'reader_console_log_screen.dart';
import 'reading_defaults_screen.dart';
import 'sync_settings_screen.dart';
```

改為：

```dart
import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/google_drive_oauth_client.dart';
import '../reader/custom_fonts_repository.dart';
import '../reader/reader_prefs_manager.dart';
import '../sync/sync_account_repository.dart';
import '../sync/sync_client.dart';
import '../theme/app_theme.dart';
import 'about_screen.dart';
import 'cloud_account_settings_screen.dart';
import 'font_management_screen.dart';
import 'nav_zone_settings_screen.dart';
import 'reader_console_log_screen.dart';
import 'reading_defaults_screen.dart';
import 'sync_settings_screen.dart';
```

找到：

```dart
  final CustomFontsRepository? customFontsRepository;
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;

  const SettingsScreen({
    super.key,
    required this.prefsManager,
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.customFontsRepository,
    this.syncAccountRepository,
    this.syncClient,
  });
```

改為：

```dart
  final CustomFontsRepository? customFontsRepository;
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;
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

找到「同步」`ListTile` 區塊結尾：

```dart
          ListTile(
            key: const Key('settings_sync_button'),
            title: const Text('同步'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.syncAccountRepository == null ||
                    widget.syncClient == null
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => SyncSettingsScreen(
                          accountRepository: widget.syncAccountRepository!,
                          syncClient: widget.syncClient!,
                        ),
                      ),
                    );
                  },
          ),
          ListTile(
            key: const Key('settings_reader_console_log_button'),
```

改為：

```dart
          ListTile(
            key: const Key('settings_sync_button'),
            title: const Text('同步'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.syncAccountRepository == null ||
                    widget.syncClient == null
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => SyncSettingsScreen(
                          accountRepository: widget.syncAccountRepository!,
                          syncClient: widget.syncClient!,
                        ),
                      ),
                    );
                  },
          ),
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
          ListTile(
            key: const Key('settings_reader_console_log_button'),
```

- [x] **Step 4：執行測試確認通過**

執行：`flutter test test/screens/settings_screen_test.dart`
預期：全數 PASS。

- [x] **Step 5：`LibraryScreen` 新增參數並貫穿兩個既有呼叫點**

在 `app/lib/screens/library_screen.dart` 頂部 import 區塊，找到：

```dart
import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
```

改為：

```dart
import '../cloud_import/cloud_account_repository.dart';
import '../cloud_import/google_drive_oauth_client.dart';
import '../library/book_content_fingerprint.dart';
import '../library/book_import_service.dart';
```

找到：

```dart
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;
  final SyncCheckpointTrigger? syncCheckpointTrigger;
```

改為：

```dart
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;
  final SyncCheckpointTrigger? syncCheckpointTrigger;
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
```

找到建構子內：

```dart
    this.syncAccountRepository,
    this.syncClient,
    this.syncCheckpointTrigger,
```

改為：

```dart
    this.syncAccountRepository,
    this.syncClient,
    this.syncCheckpointTrigger,
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
```

找到 Step 5a 遞迴自我導航呼叫點（分類篩選畫面）：

```dart
              syncAccountRepository: widget.syncAccountRepository,
              syncClient: widget.syncClient,
              syncCheckpointTrigger: widget.syncCheckpointTrigger,
```

改為：

```dart
              syncAccountRepository: widget.syncAccountRepository,
              syncClient: widget.syncClient,
              syncCheckpointTrigger: widget.syncCheckpointTrigger,
              cloudAccountRepository: widget.cloudAccountRepository,
              googleDriveOAuthClient: widget.googleDriveOAuthClient,
```

找到 `SettingsScreen` 建構呼叫點：

```dart
                builder: (context) => SettingsScreen(
                  prefsManager: widget.prefsManager,
                  currentTheme: widget.currentTheme,
                  isEinkMode: widget.isEinkMode,
                  onThemeChanged: widget.onThemeChanged,
                  customFontsRepository: widget.customFontsRepository,
                  syncAccountRepository: widget.syncAccountRepository,
                  syncClient: widget.syncClient,
                ),
```

改為：

```dart
                builder: (context) => SettingsScreen(
                  prefsManager: widget.prefsManager,
                  currentTheme: widget.currentTheme,
                  isEinkMode: widget.isEinkMode,
                  onThemeChanged: widget.onThemeChanged,
                  customFontsRepository: widget.customFontsRepository,
                  syncAccountRepository: widget.syncAccountRepository,
                  syncClient: widget.syncClient,
                  cloudAccountRepository: widget.cloudAccountRepository,
                  googleDriveOAuthClient: widget.googleDriveOAuthClient,
                ),
```

- [x] **Step 6：`main.dart` 組裝真實實例並貫穿 `ElinkBookApp`**

在 `app/lib/main.dart` 頂部 import 區塊，找到：

```dart
import 'library/book_content_fingerprint.dart';
import 'library/book_import_service.dart';
```

改為：

```dart
import 'cloud_import/cloud_account_repository.dart';
import 'cloud_import/google_drive_oauth_client.dart';
import 'cloud_import/secure_storage_cloud_account_repository.dart';
import 'library/book_content_fingerprint.dart';
import 'library/book_import_service.dart';
```

找到：

```dart
  final syncAccountRepository = SyncAccountRepository();
  final syncClient = SyncClient(accountRepository: syncAccountRepository);
```

改為：

```dart
  final syncAccountRepository = SyncAccountRepository();
  final syncClient = SyncClient(accountRepository: syncAccountRepository);
  final cloudAccountRepository = SecureStorageCloudAccountRepository();
  final googleDriveOAuthClient =
      GoogleDriveOAuthClient(accountRepository: cloudAccountRepository);
```

找到 `runApp(ElinkBookApp(...))` 內：

```dart
      syncAccountRepository: syncAccountRepository,
      syncClient: syncClient,
      syncCheckpointTrigger: syncCheckpointTrigger,
```

改為：

```dart
      syncAccountRepository: syncAccountRepository,
      syncClient: syncClient,
      syncCheckpointTrigger: syncCheckpointTrigger,
      cloudAccountRepository: cloudAccountRepository,
      googleDriveOAuthClient: googleDriveOAuthClient,
```

找到 `ElinkBookApp` 的欄位宣告：

```dart
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;
  final SyncCheckpointTrigger? syncCheckpointTrigger;
```

改為：

```dart
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;
  final SyncCheckpointTrigger? syncCheckpointTrigger;
  final CloudAccountRepository? cloudAccountRepository;
  final GoogleDriveOAuthClient? googleDriveOAuthClient;
```

找到 `ElinkBookApp` 建構子內：

```dart
    this.syncAccountRepository,
    this.syncClient,
    this.syncCheckpointTrigger,
```

改為：

```dart
    this.syncAccountRepository,
    this.syncClient,
    this.syncCheckpointTrigger,
    this.cloudAccountRepository,
    this.googleDriveOAuthClient,
```

找到 `build()` 內 `LibraryScreen(...)` 建構呼叫點：

```dart
        syncAccountRepository: widget.syncAccountRepository,
        syncClient: widget.syncClient,
        syncCheckpointTrigger: widget.syncCheckpointTrigger,
```

改為：

```dart
        syncAccountRepository: widget.syncAccountRepository,
        syncClient: widget.syncClient,
        syncCheckpointTrigger: widget.syncCheckpointTrigger,
        cloudAccountRepository: widget.cloudAccountRepository,
        googleDriveOAuthClient: widget.googleDriveOAuthClient,
```

- [x] **Step 7：執行完整測試套件與靜態分析確認零回歸**

執行：`flutter analyze`
預期："No issues found!"

執行：`flutter test`
預期：全數 PASS。

- [x] **Step 8：Commit**

```bash
git add app/lib/screens/settings_screen.dart app/lib/screens/library_screen.dart app/lib/main.dart app/test/screens/settings_screen_test.dart
git commit -m "feat(epic-29): Issue 1——貫穿注入 CloudAccountRepository/GoogleDriveOAuthClient 至 SettingsScreen"
```

---

## Self-Review（撰寫計劃時的自我檢查記錄）

**1. Spec 涵蓋範圍檢查：**
- `spec.md`「帳號模組：`CloudAccountRepository`」的 `link`/`unlink`/`isLinked`/`loadAccountEmail`（含讀取失敗安全退回未連結）→ Task 1 涵蓋；`loadTokens` 為額外新增的必要方法，供 `ensureValidAccessToken()` 讀取完整憑證，未偏離 spec 精神。
- `spec.md`「OAuth 登入機制」的系統瀏覽器＋PKCE＋`state`、不用內嵌 WebView、`drive.readonly` scope、Token 過期靜默續期 → Task 2 涵蓋。
- `spec.md`「OAuth 登入機制」的 `AndroidManifest.xml` Google 專用 redirect URI intent-filter（反向客戶端 ID 格式）→ Task 2 Step 4 涵蓋。
- `spec.md`「UI 落地位置」的設定頁「已連結的雲端匯入帳戶」區塊，比照 `SyncSettingsScreen` UI 慣例但資料來源獨立 → Task 3／Task 4 涵蓋。
- `issues.md` Issue 1 單元測試要求逐項對照：`CloudAccountRepository` 的 `link`/`unlink`/`isLinked` 狀態轉換與安全退回（Task 1 Step 3）、`FakeCloudAccountRepository` 驅動的已連結/未連結畫面呈現與解除連結互動 widget test（Task 3 Step 1）、Google OAuth 實際登入流程不做自動化測試（Task 2／Task 3 皆未對 `link()` 的瀏覽器流程本身寫自動化測試，僅測試不涉及瀏覽器的 `ensureValidAccessToken()` HTTP 邏輯）——全數涵蓋。

**2. 佔位符掃描：** 全文檢查過，所有 Step 皆含完整可執行的程式碼區塊。`google_oauth_config.dart` 的用戶端 ID 常數值本身是必要的外部設定佔位（Google Cloud Console 專案各不相同，無法從程式碼庫推導），已在 Global Constraints 與檔案內 doc comment 明確標註為「開發者需自行填入的外部設定值」，不是計劃遺漏的實作細節。

**3. 型別一致性檢查：** `CloudProvider`／`CloudAccountTokens`／`CloudAccountRepository` 在 Task 1-4 全數四個檔案（`secure_storage_cloud_account_repository.dart`／`fake_cloud_account_repository.dart`／`google_drive_oauth_client.dart`／`cloud_account_settings_screen.dart`）與對應測試檔案中型別與具名參數命名一致；`GoogleDriveOAuthClient` 的 `link()`/`unlink()`/`ensureValidAccessToken()` 三個公開方法簽章在 Task 2（定義）與 Task 3/4（消費端）完全一致；`SettingsScreen`／`LibraryScreen`／`ElinkBookApp` 三層的 `cloudAccountRepository`／`googleDriveOAuthClient` 具名參數命名與型別（皆為可選、nullable）全數一致，比照既有 `syncAccountRepository`／`syncClient` 貫穿模式。
