# Epic 8 Issue 2：同步帳號模組 + Settings「同步」子頁面 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度。

**Goal:** 新增可選（opt-in）的 PocketBase 同步帳號模組（base URL 可設定、email+password 登入、憑證加密儲存）與對應的 Settings「同步」子頁面，供 Epic 8 其餘工單（Issue 4／5／6 的同步引擎）依賴。

**Architecture:** `SyncAccountRepository` 負責持久化（base URL 走 `SharedPreferences`，憑證走 `flutter_secure_storage`）；`SyncClient` 包裝官方 `pocketbase` Dart package 的 `authWithPassword`，成功即完成登入（無兩段式「測試/正式登入」設計）；`SyncSettingsScreen` 是純 UI 層，讀寫上述兩者，比照既有「導航熱區」子頁面的 `StatefulWidget` + `initState` 非同步載入模式。三者皆透過建構子注入依賴，不依賴任何全域單例，比照本專案既有 repository/screen 慣例。

**Tech Stack:** `pocketbase`（官方 Dart SDK）、`flutter_secure_storage`（Android Keystore／iOS Keychain）、既有的 `shared_preferences`。

## Global Constraints

- **依 `spec.md`「帳號模組」**：`baseUrl` 讀寫 `SharedPreferences`，key 固定為 `sync_base_url`；`authToken`／`userId`／`email` 讀寫 `flutter_secure_storage`，僅這三項使用加密儲存；登入態定義為 `authToken == null` 即視為未登入。
- **依 `spec.md`「帳號模組」**：`testConnection()` 呼叫 PocketBase `authWithPassword`，成功即完成登入（token 直接存入 `flutter_secure_storage`），不做「先測試、丟棄、再登入」兩段式設計；`logout()` 只清除三項憑證，不影響任何本機資料。
- **依 `spec.md`「Settings『同步』子頁面」**：入口比照既有「佈景」子頁面模式加進 `SettingsScreen`；未登入時顯示 base URL／email／password 輸入欄位＋「連線／登入」按鈕；已登入時顯示登出按鈕。
- **與 spec.md 字面表述的落差（本計畫階段定案，供合併後回頭同步 spec.md 措辭參考）**：spec.md「帳號模組」寫「未設定時的預設值為官方 base URL（實際網址由實作階段依專案實際部署節點填入）」——本專案採自架架構（ADR 0019 決策 1：base URL 由使用者自行輸入，不寫死單一官方端點），全部既有文件（design.md／ADR 0019／`pocketbase-self-hosting.md`）都沒有出現過任何一個「官方公開 PocketBase 服務」網址，也不應該無中生有杜撰一個網域。改採 `defaultBaseUrl = ''`（空字串代表「尚未設定」），畫面引導使用者輸入自架的 base URL，與 ADR 0019「自架優先、去中心化」的產品定位一致。
- **依套件官方文件（2026-08-03 查證）**：`pocketbase` 最新版本 `0.24.0+1`；`flutter_secure_storage` 最新版本 `10.3.1`（依賴 `flutter_secure_storage_platform_interface: ^2.0.1`，minSdk 需求 23，本專案 minSdk 24 已滿足，見 CLAUDE.md）；`http` 最新版本 `1.6.0`。
- **AndroidManifest 新增需求（本計畫查證發現，非 spec.md 既有內容，見 Task 1）**：本專案目前完全沒有 `INTERNET` 權限宣告（`android/app/src/main/AndroidManifest.xml` 現況零網路相依套件），任何網路呼叫都會失敗；且 `pocketbase-self-hosting.md` 文件的測試/自架情境一律使用純 `http://`（無反向代理 TLS），Android API 28+ 預設封鎖明文流量，不加白名單會讓 `testConnection()` 對任何 `http://` base URL 一律連線失敗。
- **`flutter_secure_storage` 官方 README 建議（2026-08-03 查證）**：Android 端加 `android:allowBackup="false"`，避免 Auto Backup 還原時觸發 `InvalidKeyException`（Keystore 金鑰與備份還原後的裝置不匹配）。

---

### Task 1：依賴新增 + AndroidManifest 設定 + `SyncAccountRepository`

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Create: `app/lib/sync/sync_account_repository.dart`
- Create: `app/test/sync/sync_account_repository_test.dart`

**Interfaces:**
- Produces：`SyncAccountRepository`（`app/lib/sync/sync_account_repository.dart`）
  - `SyncAccountRepository({FlutterSecureStorage? secureStorage})`
  - `static const String defaultBaseUrl` — `''`
  - `Future<String> loadBaseUrl()`
  - `Future<void> saveBaseUrl(String baseUrl)`
  - `Future<String?> loadAuthToken()`
  - `Future<String?> loadUserId()`
  - `Future<String?> loadEmail()`
  - `Future<bool> isLoggedIn()`
  - `Future<void> saveCredentials({required String authToken, required String userId, required String email})`
  - `Future<void> clearCredentials()`

- [x] **Step 1：新增 `pubspec.yaml` 依賴**

在 `dependencies:` 區塊、`flutter_inappwebview: ^6.1.5` 之後新增：

```yaml
  # PocketBase 同步（epic-8-sync）：官方 Dart SDK。
  pocketbase: ^0.24.0
  # 同步帳號憑證（authToken/userId/email）加密儲存，Android Keystore／
  # iOS Keychain（ADR 0019 決策 3，本專案首次引入的安全性相關儲存機制）。
  flutter_secure_storage: ^10.3.1
```

在 `dev_dependencies:` 區塊、`archive: ^4.0.9` 之後新增：

```yaml
  # flutter_secure_storage 測試替身：官方套件本身提供
  # TestFlutterSecureStoragePlatform（見 sync_account_repository_test.dart），
  # 需要這個 platform interface 套件才能取得 FlutterSecureStoragePlatform
  # 型別以設定 .instance。
  flutter_secure_storage_platform_interface: ^2.0.1
  # 測試 SyncClient 時以 MockClient 取代真實網路請求（sync_client_test.dart）。
  http: ^1.6.0
```

- [x] **Step 2：執行 `flutter pub get`，確認依賴解析成功**

Run: `flutter pub get`
Expected: 成功結束，無版本衝突錯誤（若與既有 `win32`/`http` 版本鏈衝突，比照 `pubspec.yaml` 既有 `share_plus` 版本鎖定手法，於此新增註解記錄實際衝突與選擇理由）。

- [x] **Step 3：修改 AndroidManifest.xml——新增 `INTERNET` 權限、`allowBackup="false"`、`usesCleartextTraffic="true"`**

`app/android/app/src/main/AndroidManifest.xml` 目前 `<application>` 標籤（第 2-5 行）：

```xml
    <application
        android:label="elinkBook"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
```

改為：

```xml
    <application
        android:label="elinkBook"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:allowBackup="false"
        android:usesCleartextTraffic="true">
```

並在 `</application>` 結束標籤（第 42 行）之後、既有的 `<queries>` 區塊之前，新增權限宣告：

```xml
    <!-- epic-8-sync：PocketBase 同步需要網路存取；本專案自架架構下
         base URL 常見為純 http://（見 docs/epics/epic-8-sync/
         pocketbase-self-hosting.md「測試環境」），故同時允許明文流量。 -->
    <uses-permission android:name="android.permission.INTERNET"/>
```

`allowBackup="false"` 理由：`flutter_secure_storage` 官方 README 建議停用 Android Auto Backup，避免使用者換機/還原備份後，Keystore 加密金鑰與新裝置不匹配觸發 `InvalidKeyException` 崩潰。

（此步驟本身無法用 `flutter test` 驗證，實際生效與否由 Task 5 的 `integration_test` 於真機上間接驗證——若權限/明文流量設定有誤，`testConnection()` 對真實 PocketBase 實例會直接連線失敗。）

- [x] **Step 4：撰寫 `SyncAccountRepository` 的失敗測試**

Create `app/test/sync/sync_account_repository_test.dart`：

```dart
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';

/// 模擬部分機種讀取 Keystore 時拋出 `PlatformException` 的情境
/// （2026-08-03 審查修正，tmp/epic-8/plan-issue-2-review.md 建議 2），
/// 只在本檔案內使用，不需要獨立於 `test/support/` 建檔（YAGNI）。
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
    SharedPreferences.setMockInitialValues({});
    originalPlatform = FlutterSecureStoragePlatform.instance;
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform({});
  });

  tearDown(() {
    FlutterSecureStoragePlatform.instance = originalPlatform;
  });

  test('Keystore 讀取拋出例外時，loadAuthToken／loadUserId／loadEmail 皆安全回退為 null，isLoggedIn 回傳 false',
      () async {
    FlutterSecureStoragePlatform.instance = _ThrowingSecureStoragePlatform();
    final repo = SyncAccountRepository();

    expect(await repo.loadAuthToken(), isNull);
    expect(await repo.loadUserId(), isNull);
    expect(await repo.loadEmail(), isNull);
    expect(await repo.isLoggedIn(), false);
  });

  test('尚未設定過 base URL 時，loadBaseUrl 回傳空字串（本專案自架架構無官方預設值）',
      () async {
    final repo = SyncAccountRepository();
    expect(await repo.loadBaseUrl(), '');
  });

  test('saveBaseUrl 寫入後，loadBaseUrl 讀回相同的值', () async {
    final repo = SyncAccountRepository();
    await repo.saveBaseUrl('http://127.0.0.1:8090');
    expect(await repo.loadBaseUrl(), 'http://127.0.0.1:8090');
  });

  test('尚未登入時，loadAuthToken／loadUserId／loadEmail 皆回傳 null，isLoggedIn 回傳 false',
      () async {
    final repo = SyncAccountRepository();
    expect(await repo.loadAuthToken(), isNull);
    expect(await repo.loadUserId(), isNull);
    expect(await repo.loadEmail(), isNull);
    expect(await repo.isLoggedIn(), false);
  });

  test('saveCredentials 寫入後，三項憑證皆可讀回，isLoggedIn 回傳 true', () async {
    final repo = SyncAccountRepository();
    await repo.saveCredentials(
      authToken: 'token-abc',
      userId: 'user-123',
      email: 'reader@example.com',
    );
    expect(await repo.loadAuthToken(), 'token-abc');
    expect(await repo.loadUserId(), 'user-123');
    expect(await repo.loadEmail(), 'reader@example.com');
    expect(await repo.isLoggedIn(), true);
  });

  test('clearCredentials 清除全部三項憑證，不影響 base URL', () async {
    final repo = SyncAccountRepository();
    await repo.saveBaseUrl('http://127.0.0.1:8090');
    await repo.saveCredentials(
      authToken: 'token-abc',
      userId: 'user-123',
      email: 'reader@example.com',
    );

    await repo.clearCredentials();

    expect(await repo.loadAuthToken(), isNull);
    expect(await repo.loadUserId(), isNull);
    expect(await repo.loadEmail(), isNull);
    expect(await repo.isLoggedIn(), false);
    expect(await repo.loadBaseUrl(), 'http://127.0.0.1:8090');
  });
}
```

- [x] **Step 5：執行測試，確認因 `SyncAccountRepository` 尚不存在而失敗**

Run: `flutter test test/sync/sync_account_repository_test.dart`
Expected: FAIL，錯誤訊息指出找不到 `package:elinkbook/sync/sync_account_repository.dart`（或找不到 `SyncAccountRepository` 類別）。

- [x] **Step 6：實作 `SyncAccountRepository`**

Create `app/lib/sync/sync_account_repository.dart`：

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 同步帳號持久化（spec.md「帳號模組」、ADR 0019）：`baseUrl` 為非敏感
/// 設定，存 [SharedPreferences]；`authToken`／`userId`／`email` 三項憑證
/// 存 [FlutterSecureStorage]（Android Keystore／iOS Keychain 加密），是
/// 本專案首次引入的安全性相關儲存機制，僅限這三項，其餘既有偏好設定
/// 不受影響。
class SyncAccountRepository {
  static const _baseUrlKey = 'sync_base_url';
  static const _authTokenKey = 'sync_auth_token';
  static const _userIdKey = 'sync_user_id';
  static const _emailKey = 'sync_email';

  /// 本專案採自架架構（ADR 0019 決策 1：base URL 由使用者自行輸入，不
  /// 寫死單一官方端點），沒有官方公開服務可預填；空字串代表「尚未設定」，
  /// 畫面需引導使用者輸入自架的 base URL。
  static const defaultBaseUrl = '';

  final FlutterSecureStorage _secureStorage;

  SyncAccountRepository({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  Future<String> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey) ?? defaultBaseUrl;
  }

  Future<void> saveBaseUrl(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, baseUrl);
  }

  /// 部分機種（尤其 OEM 客製 Android Keystore 有瑕疵的裝置，官方套件
  /// GitHub issue 已有多起真實回報，例如 Keystore 憑證損毀／韌體更新後
  /// 解密失敗）讀取時會拋出 `PlatformException`，非本專案能控制的環境
  /// 因素；讀取失敗時安全回退為「視同未登入」（回傳 `null`），迫使使用者
  /// 重新登入，而不是讓 `SyncSettingsScreen` 卡在載入畫面或讓例外往上
  /// 拋出中斷整個 Settings 畫面（2026-08-03 審查修正，
  /// tmp/epic-8/plan-issue-2-review.md 建議 2）。
  Future<String?> loadAuthToken() async {
    try {
      return await _secureStorage.read(key: _authTokenKey);
    } catch (_) {
      return null;
    }
  }

  Future<String?> loadUserId() async {
    try {
      return await _secureStorage.read(key: _userIdKey);
    } catch (_) {
      return null;
    }
  }

  Future<String?> loadEmail() async {
    try {
      return await _secureStorage.read(key: _emailKey);
    } catch (_) {
      return null;
    }
  }

  /// 登入態：spec.md「帳號模組」定義 `authToken == null` 即視為未登入
  /// （讀取失敗時 [loadAuthToken] 已回退為 `null`，同樣視為未登入）。
  Future<bool> isLoggedIn() async => await loadAuthToken() != null;

  Future<void> saveCredentials({
    required String authToken,
    required String userId,
    required String email,
  }) async {
    await _secureStorage.write(key: _authTokenKey, value: authToken);
    await _secureStorage.write(key: _userIdKey, value: userId);
    await _secureStorage.write(key: _emailKey, value: email);
  }

  /// 只清除同步憑證（FR-30），不影響任何本機資料（design.md 決策 9）。
  Future<void> clearCredentials() async {
    await _secureStorage.delete(key: _authTokenKey);
    await _secureStorage.delete(key: _userIdKey);
    await _secureStorage.delete(key: _emailKey);
  }
}
```

- [x] **Step 7：執行測試，確認全數通過**

Run: `flutter test test/sync/sync_account_repository_test.dart`
Expected: PASS（6 個測試全數通過）。

- [x] **Step 8：Commit**

```bash
git add pubspec.yaml android/app/src/main/AndroidManifest.xml lib/sync/sync_account_repository.dart test/sync/sync_account_repository_test.dart
git commit -m "feat(epic-8-sync): Issue 2 Task 1 — 新增同步相依套件、AndroidManifest 網路設定、SyncAccountRepository"
```

---

### Task 2：`SyncClient`（登入／登出）

**Files:**
- Create: `app/lib/sync/sync_client.dart`
- Create: `app/test/sync/sync_client_test.dart`

**Interfaces:**
- Consumes：`SyncAccountRepository`（Task 1）—— `saveBaseUrl()`／`saveCredentials()`／`clearCredentials()`
- Produces：`SyncClient`（`app/lib/sync/sync_client.dart`）
  - `typedef PocketBaseClientFactory = PocketBase Function(String baseUrl)`
  - `SyncClient({required SyncAccountRepository accountRepository, PocketBaseClientFactory? clientFactory})`
  - `Future<bool> testConnection(String baseUrl, String email, String password)`
  - `Future<void> logout()`

- [x] **Step 1：撰寫 `SyncClient` 的失敗測試**

Create `app/test/sync/sync_client_test.dart`：

```dart
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
```

- [x] **Step 2：執行測試，確認因 `SyncClient` 尚不存在而失敗**

Run: `flutter test test/sync/sync_client_test.dart`
Expected: FAIL，錯誤訊息指出找不到 `package:elinkbook/sync/sync_client.dart`（或找不到 `SyncClient` 類別）。

- [x] **Step 3：實作 `SyncClient`**

Create `app/lib/sync/sync_client.dart`：

```dart
import 'package:pocketbase/pocketbase.dart';

import 'sync_account_repository.dart';

/// 建立 [PocketBase] client 的工廠函式型別，供測試替換為指向
/// `package:http/testing.dart` `MockClient` 的假伺服器（見
/// sync_client_test.dart），正式執行時使用 [PocketBase.new]。
typedef PocketBaseClientFactory = PocketBase Function(String baseUrl);

/// 同步帳號的核心操作（spec.md「帳號模組」）：測試連線即完成登入
/// （design.md 決策 14——UI 只需一顆按鈕，不做「先測試、丟棄、再登入」
/// 兩段式設計），以及登出。
class SyncClient {
  final SyncAccountRepository _accountRepository;
  final PocketBaseClientFactory _clientFactory;

  SyncClient({
    required SyncAccountRepository accountRepository,
    PocketBaseClientFactory? clientFactory,
  })  : _accountRepository = accountRepository,
        _clientFactory = clientFactory ?? PocketBase.new;

  /// 呼叫 PocketBase `authWithPassword`；成功即視為登入成功，直接把
  /// [baseUrl] 與回傳的憑證寫入 [SyncAccountRepository]。失敗（連線
  /// 錯誤／帳密錯誤）回傳 `false`，不寫入任何憑證（FR-30）。
  ///
  /// [baseUrl] 先 `.trim()`：使用者從其他地方複製貼上網址時常見夾帶
  /// 前後空白，未修剪會讓 `Uri.parse` 在底層產生格式不符預期的結果
  /// （2026-08-03 審查修正，tmp/epic-8/plan-issue-2-review.md 建議 1
  /// 之「Trim」部分）。**不**額外移除結尾斜線——`pocketbase` SDK 的
  /// `PocketBase.buildURL()` 本身已處理 `baseURL` 是否以 `/` 結尾的情況
  /// （`baseURL + (baseURL.endsWith("/") ? "" : "/")`），重複移除是
  /// 多餘的防禦（見審查回應）。
  Future<bool> testConnection(
    String baseUrl,
    String email,
    String password,
  ) async {
    final trimmedBaseUrl = baseUrl.trim();
    final pb = _clientFactory(trimmedBaseUrl);
    try {
      final authData =
          await pb.collection('users').authWithPassword(email, password);
      final userId = authData.record?.id;
      if (userId == null || userId.isEmpty) return false;
      await _accountRepository.saveBaseUrl(trimmedBaseUrl);
      await _accountRepository.saveCredentials(
        authToken: authData.token,
        userId: userId,
        email: email,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 清除本機憑證，不影響任何本機資料（FR-30，design.md 決策 9）。
  Future<void> logout() => _accountRepository.clearCredentials();
}
```

- [x] **Step 4：執行測試，確認全數通過**

Run: `flutter test test/sync/sync_client_test.dart`
Expected: PASS（5 個測試全數通過）。

- [x] **Step 5：Commit**

```bash
git add lib/sync/sync_client.dart test/sync/sync_client_test.dart
git commit -m "feat(epic-8-sync): Issue 2 Task 2 — SyncClient（testConnection/logout）"
```

---

### Task 3：`SyncSettingsScreen`

**Files:**
- Create: `app/lib/screens/sync_settings_screen.dart`
- Create: `app/test/screens/sync_settings_screen_test.dart`

**Interfaces:**
- Consumes：`SyncAccountRepository`（Task 1）、`SyncClient`（Task 2）
- Produces：`SyncSettingsScreen`（`app/lib/screens/sync_settings_screen.dart`）
  - `SyncSettingsScreen({required SyncAccountRepository accountRepository, required SyncClient syncClient})`
  - 對外可觀察的 Key：`sync_settings_loading_indicator`／`sync_settings_base_url_field`／`sync_settings_email_field`／`sync_settings_password_field`／`sync_settings_connect_button`／`sync_settings_error_text`／`sync_settings_logged_in_email`／`sync_settings_logout_button`

- [x] **Step 1：撰寫 `SyncSettingsScreen` 的失敗測試**

Create `app/test/screens/sync_settings_screen_test.dart`：

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/screens/sync_settings_screen.dart';
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

  SyncClient buildClient(MockClient mockClient) => SyncClient(
        accountRepository: accountRepository,
        clientFactory: (baseUrl) =>
            PocketBase(baseUrl, httpClientFactory: () => mockClient),
      );

  testWidgets('未登入時，載入完成後顯示三個輸入欄位與「連線／登入」按鈕，不顯示登出按鈕',
      (tester) async {
    final client = buildClient(MockClient((request) async {
      throw StateError('本測試不應該真的發出網路請求');
    }));

    await tester.pumpWidget(MaterialApp(
      home: SyncSettingsScreen(
        accountRepository: accountRepository,
        syncClient: client,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sync_settings_base_url_field')),
        findsOneWidget);
    expect(
        find.byKey(const Key('sync_settings_email_field')), findsOneWidget);
    expect(find.byKey(const Key('sync_settings_password_field')),
        findsOneWidget);
    expect(find.byKey(const Key('sync_settings_connect_button')),
        findsOneWidget);
    expect(
        find.byKey(const Key('sync_settings_logout_button')), findsNothing);
  });

  testWidgets('已登入時，載入完成後顯示登入中的 email 與登出按鈕，不顯示輸入欄位',
      (tester) async {
    await accountRepository.saveCredentials(
      authToken: 'token-abc',
      userId: 'user-123',
      email: 'reader@example.com',
    );
    final client = buildClient(MockClient((request) async {
      throw StateError('本測試不應該真的發出網路請求');
    }));

    await tester.pumpWidget(MaterialApp(
      home: SyncSettingsScreen(
        accountRepository: accountRepository,
        syncClient: client,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('已登入：reader@example.com'), findsOneWidget);
    expect(
        find.byKey(const Key('sync_settings_logout_button')), findsOneWidget);
    expect(
        find.byKey(const Key('sync_settings_email_field')), findsNothing);
  });

  testWidgets('點擊「連線／登入」成功後，畫面切換為已登入檢視', (tester) async {
    final client = buildClient(MockClient((request) async {
      return http.Response(
        jsonEncode({
          'token': 'token-abc',
          'record': {'id': 'user-123'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }));

    await tester.pumpWidget(MaterialApp(
      home: SyncSettingsScreen(
        accountRepository: accountRepository,
        syncClient: client,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('sync_settings_base_url_field')),
      'http://127.0.0.1:8090',
    );
    await tester.enterText(
      find.byKey(const Key('sync_settings_email_field')),
      'reader@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('sync_settings_password_field')),
      'correct-password',
    );
    await tester.tap(find.byKey(const Key('sync_settings_connect_button')));
    await tester.pumpAndSettle();

    expect(find.text('已登入：reader@example.com'), findsOneWidget);
    expect(
        find.byKey(const Key('sync_settings_logout_button')), findsOneWidget);
  });

  testWidgets('點擊「連線／登入」失敗時，顯示錯誤文字，畫面維持在登入表單', (tester) async {
    final client = buildClient(MockClient((request) async {
      return http.Response(
        jsonEncode({'status': 400, 'message': 'Failed to authenticate.'}),
        400,
        headers: {'content-type': 'application/json'},
      );
    }));

    await tester.pumpWidget(MaterialApp(
      home: SyncSettingsScreen(
        accountRepository: accountRepository,
        syncClient: client,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('sync_settings_email_field')),
      'reader@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('sync_settings_password_field')),
      'wrong-password',
    );
    await tester.tap(find.byKey(const Key('sync_settings_connect_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sync_settings_error_text')), findsOneWidget);
    expect(find.byKey(const Key('sync_settings_email_field')),
        findsOneWidget);
  });

  testWidgets('點擊「登出」後，畫面切換回登入表單', (tester) async {
    await accountRepository.saveCredentials(
      authToken: 'token-abc',
      userId: 'user-123',
      email: 'reader@example.com',
    );
    final client = buildClient(MockClient((request) async {
      throw StateError('本測試不應該真的發出網路請求');
    }));

    await tester.pumpWidget(MaterialApp(
      home: SyncSettingsScreen(
        accountRepository: accountRepository,
        syncClient: client,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sync_settings_logout_button')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('sync_settings_email_field')), findsOneWidget);
    expect(
        find.byKey(const Key('sync_settings_logout_button')), findsNothing);
  });
}
```

- [x] **Step 2：執行測試，確認因 `SyncSettingsScreen` 尚不存在而失敗**

Run: `flutter test test/screens/sync_settings_screen_test.dart`
Expected: FAIL，錯誤訊息指出找不到 `package:elinkbook/screens/sync_settings_screen.dart`。

- [x] **Step 3：實作 `SyncSettingsScreen`**

Create `app/lib/screens/sync_settings_screen.dart`：

```dart
import 'package:flutter/material.dart';

import '../sync/sync_account_repository.dart';
import '../sync/sync_client.dart';

/// Settings「同步」子頁面（spec.md「Settings『同步』子頁面」）：未登入時
/// 顯示 base URL／email／password 輸入欄位＋「連線／登入」按鈕；已登入
/// 時顯示登入中的 email＋登出按鈕。同步功能完全可選（opt-in，design.md
/// 決策 9），不影響任何既有單機功能。
class SyncSettingsScreen extends StatefulWidget {
  final SyncAccountRepository accountRepository;
  final SyncClient syncClient;

  const SyncSettingsScreen({
    super.key,
    required this.accountRepository,
    required this.syncClient,
  });

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  bool _loading = true;
  bool _isLoggedIn = false;
  bool _connecting = false;
  String? _loggedInEmail;
  String? _errorText;

  final _baseUrlController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final baseUrl = await widget.accountRepository.loadBaseUrl();
    final isLoggedIn = await widget.accountRepository.isLoggedIn();
    final email = await widget.accountRepository.loadEmail();
    if (!mounted) return;
    setState(() {
      _baseUrlController.text = baseUrl;
      _isLoggedIn = isLoggedIn;
      _loggedInEmail = email;
      _loading = false;
    });
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _errorText = null;
    });
    final success = await widget.syncClient.testConnection(
      _baseUrlController.text,
      _emailController.text,
      _passwordController.text,
    );
    if (!mounted) return;
    if (success) {
      setState(() {
        _connecting = false;
        _isLoggedIn = true;
        _loggedInEmail = _emailController.text;
        _passwordController.clear();
      });
    } else {
      setState(() {
        _connecting = false;
        _errorText = '連線失敗，請確認伺服器網址與帳號密碼是否正確';
      });
    }
  }

  Future<void> _logout() async {
    await widget.syncClient.logout();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
      _loggedInEmail = null;
      _emailController.clear();
      _passwordController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('同步')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('sync_settings_loading_indicator'),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: _isLoggedIn ? _buildLoggedInView() : _buildLoginForm(),
            ),
    );
  }

  Widget _buildLoggedInView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '已登入：${_loggedInEmail ?? ''}',
          key: const Key('sync_settings_logged_in_email'),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          key: const Key('sync_settings_logout_button'),
          onPressed: _logout,
          child: const Text('登出'),
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('sync_settings_base_url_field'),
          controller: _baseUrlController,
          decoration: const InputDecoration(labelText: '伺服器網址'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('sync_settings_email_field'),
          controller: _emailController,
          // 帳密欄位停用自動校正／輸入法建議，避免鍵盤記憶敏感帳密
          // （2026-08-03 審查修正，tmp/epic-8/plan-issue-2-review.md 建議 3）。
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('sync_settings_password_field'),
          controller: _passwordController,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: '密碼'),
        ),
        const SizedBox(height: 16),
        if (_errorText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _errorText!,
              key: const Key('sync_settings_error_text'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ElevatedButton(
          key: const Key('sync_settings_connect_button'),
          onPressed: _connecting ? null : _connect,
          child: _connecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('連線／登入'),
        ),
      ],
    );
  }
}
```

- [x] **Step 4：執行測試，確認全數通過**

Run: `flutter test test/screens/sync_settings_screen_test.dart`
Expected: PASS（5 個測試全數通過）。

- [x] **Step 5：Commit**

```bash
git add lib/screens/sync_settings_screen.dart test/screens/sync_settings_screen_test.dart
git commit -m "feat(epic-8-sync): Issue 2 Task 3 — SyncSettingsScreen"
```

---

### Task 4：`SettingsScreen` 新增「同步」入口 + 全域接線

**Files:**
- Modify: `app/lib/screens/settings_screen.dart`
- Modify: `app/lib/screens/library_screen.dart:29-57,629-635`
- Modify: `app/lib/main.dart`
- Modify: `app/test/screens/settings_screen_test.dart`

**Interfaces:**
- Consumes：`SyncAccountRepository`（Task 1）、`SyncClient`（Task 2）、`SyncSettingsScreen`（Task 3）

- [x] **Step 1：`SettingsScreen` 新增「同步」入口——先改測試**

`app/test/screens/settings_screen_test.dart` 現有 `setUp`（第 13-23 行）需要補上 `flutter_secure_storage`／`SharedPreferences` 的測試替身（`SyncSettingsScreen` 內部經由 `SyncAccountRepository` 存取兩者），並新增測試：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/screens/settings_screen.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_client.dart';
import 'package:elinkbook/theme/app_theme.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_custom_fonts_repository.dart';

const _appInfoChannel = MethodChannel('elinkbook/app_info');

void main() {
  late FlutterSecureStoragePlatform originalPlatform;

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'elinkBook',
      packageName: 'cc.ugotit.elinkbook',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appInfoChannel, (call) async => null);
    SharedPreferences.setMockInitialValues({});
    originalPlatform = FlutterSecureStoragePlatform.instance;
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appInfoChannel, null);
    FlutterSecureStoragePlatform.instance = originalPlatform;
  });

  // ……既有測試不變……

  testWidgets('SettingsScreen 顯示「同步」入口，點擊導航至 SyncSettingsScreen',
      (tester) async {
    final accountRepository = SyncAccountRepository();
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        prefsManager: FakeReaderPrefsManager(),
        syncAccountRepository: accountRepository,
        syncClient: SyncClient(accountRepository: accountRepository),
      ),
    ));

    expect(find.byKey(const Key('settings_sync_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_sync_button')));
    await tester.pumpAndSettle();

    expect(find.text('同步'), findsOneWidget);
  });
}
```

（既有測試第一則「顯示設定標題與『佈景』『關於』『導航熱區』入口」不需要修改斷言內容——本 Task 只新增入口，不移除既有項目。）

- [x] **Step 2：執行測試，確認新測試因入口不存在而失敗**

Run: `flutter test test/screens/settings_screen_test.dart`
Expected: FAIL（`find.byKey(const Key('settings_sync_button'))` 找不到任何 widget，其餘既有測試維持 PASS）。

- [x] **Step 3：`SettingsScreen` 新增欄位與入口**

`app/lib/screens/settings_screen.dart` 第 1-28 行 import 與欄位宣告，改為：

```dart
import 'package:flutter/material.dart';

import '../reader/custom_fonts_repository.dart';
import '../reader/reader_prefs_manager.dart';
import '../sync/sync_account_repository.dart';
import '../sync/sync_client.dart';
import '../theme/app_theme.dart';
import 'about_screen.dart';
import 'font_management_screen.dart';
import 'nav_zone_settings_screen.dart';
import 'reading_defaults_screen.dart';
import 'sync_settings_screen.dart';

/// 設定畫面：「佈景」（主題圓點，原位於 `LibraryScreen` AppBar，見
/// `epic-18-reader-device-qa` 工具列溢位修復）、「字型管理」、「閱讀預設值」、
/// 「導航熱區」、「同步」與「關於」六個項目。
class SettingsScreen extends StatelessWidget {
  final ReaderPrefsManager prefsManager;
  final AppTheme currentTheme;
  final bool isEinkMode;
  final ValueChanged<AppTheme>? onThemeChanged;
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

在既有「導航熱區」`ListTile`（第 81-93 行）與「關於」`ListTile`（第 94-103 行）之間，新增：

```dart
          ListTile(
            key: const Key('settings_sync_button'),
            title: const Text('同步'),
            trailing: const Icon(Icons.chevron_right),
            onTap: syncAccountRepository == null || syncClient == null
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => SyncSettingsScreen(
                          accountRepository: syncAccountRepository!,
                          syncClient: syncClient!,
                        ),
                      ),
                    );
                  },
          ),
```

- [x] **Step 4：`LibraryScreen` 新增欄位並轉傳給 `SettingsScreen`**

`app/lib/screens/library_screen.dart` 第 29-57 行欄位宣告與建構子，新增 `syncAccountRepository`／`syncClient`：

```dart
class LibraryScreen extends StatefulWidget {
  final LibraryRepository repository;
  final BookImportService importService;
  final ReaderPrefsManager prefsManager;
  final BookmarksRepository? bookmarksRepository;
  final HighlightsRepository? highlightsRepository;
  final NotesRepository? notesRepository;
  final CustomFontsRepository? customFontsRepository;
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;
  final AppTheme currentTheme;
  final bool isEinkMode;
  final ValueChanged<AppTheme>? onThemeChanged;
  final ValueChanged<bool>? onEinkModeChanged;
  final String? groupFilter;

  const LibraryScreen({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsManager,
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.customFontsRepository,
    this.syncAccountRepository,
    this.syncClient,
    this.currentTheme = AppTheme.light,
    this.isEinkMode = false,
    this.onThemeChanged,
    this.onEinkModeChanged,
    this.groupFilter,
  });
```

並在檔案頂端 import 區塊新增：

```dart
import '../sync/sync_account_repository.dart';
import '../sync/sync_client.dart';
```

第 629-635 行 `SettingsScreen` 建構呼叫改為：

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

- [x] **Step 5：`main.dart` 建立實例並接線**

`app/lib/main.dart` 第 1-19 行 import 區塊新增：

```dart
import 'sync/sync_account_repository.dart';
import 'sync/sync_client.dart';
```

第 42-58 行（`customFontsRepository` 建立之後、`runApp` 之前）新增：

```dart
  final syncAccountRepository = SyncAccountRepository();
  final syncClient = SyncClient(accountRepository: syncAccountRepository);
  runApp(
    ElinkBookApp(
      repository: repository,
      importService: importService,
      prefsManager: prefsManager,
      bookmarksRepository: bookmarksRepository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
      customFontsRepository: customFontsRepository,
      syncAccountRepository: syncAccountRepository,
      syncClient: syncClient,
      initialTheme: initialTheme,
      initialEinkMode: initialEinkMode,
      themePreferences: themePreferences,
    ),
  );
```

`ElinkBookApp` 欄位宣告（第 64-88 行）新增對應欄位：

```dart
class ElinkBookApp extends StatefulWidget {
  final LibraryRepository repository;
  final BookImportService importService;
  final ReaderPrefsManager prefsManager;
  final BookmarksRepository? bookmarksRepository;
  final HighlightsRepository? highlightsRepository;
  final NotesRepository? notesRepository;
  final CustomFontsRepository? customFontsRepository;
  final SyncAccountRepository? syncAccountRepository;
  final SyncClient? syncClient;
  final AppThemePreferences themePreferences;
  final AppTheme initialTheme;
  final bool initialEinkMode;

  ElinkBookApp({
    super.key,
    required this.repository,
    required this.importService,
    required this.prefsManager,
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.customFontsRepository,
    this.syncAccountRepository,
    this.syncClient,
    this.initialTheme = AppTheme.light,
    this.initialEinkMode = false,
    AppThemePreferences? themePreferences,
  }) : themePreferences = themePreferences ?? AppThemePreferences();
```

`build()` 內 `LibraryScreen` 建構呼叫（第 124-136 行）新增轉傳：

```dart
      home: LibraryScreen(
        repository: widget.repository,
        importService: widget.importService,
        prefsManager: widget.prefsManager,
        bookmarksRepository: widget.bookmarksRepository,
        highlightsRepository: widget.highlightsRepository,
        notesRepository: widget.notesRepository,
        customFontsRepository: widget.customFontsRepository,
        syncAccountRepository: widget.syncAccountRepository,
        syncClient: widget.syncClient,
        currentTheme: _theme,
        isEinkMode: _isEinkMode,
        onThemeChanged: _handleThemeChanged,
        onEinkModeChanged: _handleEinkModeChanged,
      ),
```

- [x] **Step 6：執行測試，確認全數通過**

Run: `flutter test test/screens/settings_screen_test.dart`
Expected: PASS（既有測試與新測試全數通過）。

Run: `flutter analyze`
Expected: `No issues found!`（`library_screen_test.dart` 等既有測試檔案未直接傳入新的可選參數，型別皆為可空、預設 `null`，不需要跟著修改既有呼叫端）。

- [x] **Step 7：Commit**

```bash
git add lib/screens/settings_screen.dart lib/screens/library_screen.dart lib/main.dart test/screens/settings_screen_test.dart
git commit -m "feat(epic-8-sync): Issue 2 Task 4 — SettingsScreen 新增「同步」入口，全域接線"
```

---

### Task 5：`integration_test`——對真實 PocketBase 測試實例登入/登出

**Files:**
- Create: `app/integration_test/sync_account_test.dart`

**Interfaces:**
- Consumes：`SyncAccountRepository`（Task 1）、`SyncClient`（Task 2），對 Issue 7 產出的可連線測試用 PocketBase 實例（`docs/epics/epic-8-sync/pocketbase-self-hosting.md`「測試環境」）發出真實網路請求。

- [x] **Step 1：確認測試用 PocketBase 實例正在運作**

依 `docs/epics/epic-8-sync/pocketbase-self-hosting.md`「測試環境」一節，`http://pbdev.jigong.org` 已是一份持續運作的正式測試實例（Docker + Traefik 自架，2026-08-03 確認可連線，`/api/health` 回傳 200），不需要開發者各自在本機另外起一個——**這是本計畫原始撰寫時規劃「本機 127.0.0.1:8090」之後的變更**，Task 5 全部步驟已改用這個固定網域。

- [x] **Step 2：確認本 Issue 專用的測試帳號已存在**

已於 `http://pbdev.jigong.org` 建立（2026-08-03，`POST /api/collections/users/records` 回傳 200 與 `"id":"5xdjm5yysd9rkuc"`）：

```bash
curl -s http://pbdev.jigong.org/api/collections/users/records \
  -H "Content-Type: application/json" \
  -d '{"email":"epic8-issue2-test@example.com","password":"epic8-test-password-123","passwordConfirm":"epic8-test-password-123"}'
```

若之後需要在其他環境重建同一組測試帳號，重跑本指令即可；帳號已存在時會回傳 400，可略過直接使用既有帳號。

- [x] **Step 3：撰寫 `integration_test`**

Create `app/integration_test/sync_account_test.dart`：

```dart
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // http://pbdev.jigong.org 是持續運作的正式測試實例（見
  // pocketbase-self-hosting.md「測試環境」），開發機／Android 模擬器／
  // 實體裝置皆可直接用同一個 base URL 連線，不需要依連線來源切換
  // 127.0.0.1／10.0.2.2／區網 IP（2026-08-03 改用固定測試網域後的
  // 修正）。目前是 HTTP（非 HTTPS），與下方 SyncClient 呼叫方式無關，
  // PocketBase Dart SDK 對 http/https 一視同仁。
  const testBaseUrl = 'http://pbdev.jigong.org';
  const testEmail = 'epic8-issue2-test@example.com';
  const testPassword = 'epic8-test-password-123';

  testWidgets(
      '對真實 PocketBase 測試實例登入成功，憑證正確落地於裝置端 flutter_secure_storage；'
      '登出後正確清除', (tester) async {
    final accountRepository = SyncAccountRepository();
    // 先清除裝置上可能殘留的上次測試憑證，確保測試起點乾淨。
    await accountRepository.clearCredentials();

    final client = SyncClient(accountRepository: accountRepository);

    final success = await client.testConnection(
      testBaseUrl,
      testEmail,
      testPassword,
    );

    expect(success, true);
    expect(await accountRepository.loadAuthToken(), isNotNull);
    expect(await accountRepository.loadUserId(), isNotNull);
    expect(await accountRepository.loadEmail(), testEmail);
    expect(await accountRepository.loadBaseUrl(), testBaseUrl);

    await client.logout();

    expect(await accountRepository.loadAuthToken(), isNull);
    expect(await accountRepository.loadUserId(), isNull);
    expect(await accountRepository.loadEmail(), isNull);
  });
}
```

- [x] **Step 4：於真實裝置/模擬器上執行，確認通過**

Run: `flutter devices`（取得可用裝置/模擬器 ID）
Run: `flutter test integration_test/sync_account_test.dart -d <device-id>`
Expected: PASS——這代表（a）Task 1 新增的 `INTERNET` 權限與明文流量白名單設定正確生效，（b）`flutter_secure_storage` 在真實 Android Keystore 上正確加密寫入/讀出/清除三項憑證，（c）`SyncClient` 對真實 PocketBase 實例的 `authWithPassword` 呼叫成功。

- [x] **Step 5：Commit**

```bash
git add integration_test/sync_account_test.dart
git commit -m "test(epic-8-sync): Issue 2 Task 5 — 對真實 PocketBase 測試實例登入/登出的 integration_test"
```

---

## Self-Review Notes

- **spec.md 覆蓋檢查**：「帳號模組」（`SyncAccountRepository`／`SyncClient`／`baseUrl`/`authToken`/`userId`/`email` 讀寫位置與 key）✅ Task 1-2；「Settings『同步』子頁面」（入口＋欄位＋按鈕）✅ Task 3-4；`pocketbase` 依賴 ✅ Task 1。閱讀位置/劃線/備註同步、墓碑清理、checkpoint 觸發皆非本 Issue 範圍（見 issues.md Issue 4-6），未涉及。
- **與既有專案慣例的差異說明**：
  1. `defaultBaseUrl` 採空字串而非「官方 URL」——見 Global Constraints，理由是專案沒有、也不應該虛構一個官方網域。
  2. AndroidManifest 新增 `INTERNET` 權限／`allowBackup="false"`／`usesCleartextTraffic="true"` 三項，皆為本計畫查證後發現的必要前提（非 spec.md 原文要求），已在 Global Constraints 與 Task 1 詳列理由，供合併後回頭同步 `spec.md`「帳號模組」措辭時參考。
  3. 未採用 `pocketbase` SDK 自帶的 `AsyncAuthStore` 序列化整包憑證機制，改為手動拆成三個獨立 `flutter_secure_storage` key——因為 spec.md 明確定義三個獨立讀寫方法（`authToken`／`userId`／`email`），且避免依賴 PocketBase SDK 內部序列化格式的穩定性。
  4. `SyncSettingsScreen` 已登入檢視**不**顯示 spec.md 提到「可顯示『上次同步時間』等輔助資訊」——該資訊來源（`sync_metadata.lastPushCompletedAt`）要到 Issue 4 同步引擎才會有實際寫入的值，本 Issue 若顯示只會永遠是「從未同步」的空狀態，意義不大；spec.md 原文也用「可顯示」而非「必須顯示」，故本計畫延後到 Issue 4/5 完成、有真實資料可顯示時再一併補上（不在本計畫的驗收範圍內）。
- **Placeholder 掃描**：全部程式碼區塊皆為可直接執行的完整內容，無 TBD/TODO；`main.dart`/`library_screen.dart`/`settings_screen.dart` 的既有程式碼片段皆取自實際檔案內容（非杜撰行號）。
- **型別一致性檢查**：`SyncAccountRepository`／`SyncClient`／`SyncSettingsScreen` 三者的建構子參數名稱與型別在 Task 1-4 全程一致（`accountRepository`/`syncClient`/`clientFactory`），`PocketBaseClientFactory` typedef 於 Task 2 定義、Task 2-3 測試檔一致使用。

## 審查修正紀錄（`tmp/epic-8/plan-issue-2-review.md`）

程式碼審查（`/superpowers:requesting-code-review`，2026-08-03）結論「正式通過」，0 Critical/Important，附帶 3 項輕量優化建議。逐項核對後：

- **建議 1「Base URL 字串修飾」，部分採納**：`.trim()` 部分確認屬實並採納——使用者從其他地方複製貼上網址常見夾帶前後空白，已於 Task 2 `SyncClient.testConnection()` 補上 `trimmedBaseUrl = baseUrl.trim()`，實際用於建立 client 與寫入 `SyncAccountRepository` 皆改用修剪後的值，並補上對應測試（`sync_client_test.dart` 新增「baseUrl 前後夾帶空白」測試）。**移除結尾斜線的部分未採納**：查證 `pocketbase` Dart SDK 原始碼（`PocketBase.buildURL()`）發現該方法本身已處理 `baseURL` 是否以 `/` 結尾的情況（`baseURL + (baseURL.endsWith("/") ? "" : "/")`），結尾多一個 `/` 不會造成路徑重複或請求失敗，本計畫層級再處理一次是多餘的防禦，已在 Task 2 程式碼註解記錄此查證結果與理由。
- **建議 2「flutter_secure_storage 例外保護」，確認屬實，已採納**：查證 `flutter_secure_storage` 官方 GitHub issue 列表，確認這不是假設性風險——已有多起真實回報（例如 OEM 客製 Keystore 在特定機種／韌體更新後讀取拋出 `PlatformException`／`BadPaddingException`），本專案目標裝置又明確涵蓋較冷門的 E-Ink 閱讀器，風險並非空談。已於 Task 1 `SyncAccountRepository.loadAuthToken()`/`loadUserId()`/`loadEmail()` 三個讀取方法加上 `try/catch`，讀取失敗時安全回退為 `null`（等同「視為未登入」，避免 `SyncSettingsScreen` 卡在載入畫面或例外向上拋出中斷整個 Settings 畫面），並補上對應測試（新增 `_ThrowingSecureStoragePlatform` 測試替身與 1 則測試案例）。**未擴及**寫入方法（`saveCredentials`/`clearCredentials`）——審查意見僅點名 `.read()`，寫入失敗屬於不同的失敗模式（使用者會誤以為登入成功但憑證其實沒真的落地），需要另外設計「回報給呼叫端」的方式，不屬於本次審查範圍，不擅自擴大修改。
- **建議 3「密碼輸入框體驗優化」，確認屬實，已採納**：已於 Task 3 `SyncSettingsScreen` 的 email／password 兩個 `TextField` 加上 `autocorrect: false`／`enableSuggestions: false`，防止輸入法記憶敏感帳密。

## 實作結果審查修正紀錄（`tmp/epic-8/plan-issue-2-implementation-review.md`）

程式碼審查對象改為「本計畫的實際實作結果」（`feat/epic-8-issue-2-sync-account` 分支，`cf56f54..91be184` 共 6 個 commit），結論「正式通過」，0 Critical，2 項 Important（皆屬流程性，非程式碼缺陷）、2 項 Minor：

- **確認屬實，已處理**：本計畫 Task 1-5 共 28 個 Step 的核取方塊當時仍全數維持 `- [ ]`（僅 Task 5 Step 1/2 例外），與實際程式碼／測試皆已完成且通過的真實狀態不符，違反 CLAUDE.md「每完成一個 Step 需即時勾選」的 SDD 紀律。已將全部 28 個 Step 改回 `- [x]`。
- **確認屬實，已處理**：Task 5 Step 4（於真機執行 `integration_test` 確認通過）原本無跡象顯示已實際執行過。已在真實 Android 裝置（`3CEF42ECD491687`，Android 15）上執行 `flutter test integration_test/sync_account_test.dart`，過程中發現一次真實的環境問題並排除：`pbdev.jigong.org` 實際掛在 Tailscale 私有網路（解析為 CGNAT IP `100.98.175.79`），裝置上 Tailscale 若未連線會導致 `testConnection()` 正確地回傳 `false`（非程式碼 bug，是連線失敗的預期行為）；裝置端 Tailscale 連線後重跑，測試通過（`testConnection returned: true`、`All tests passed!`）。
- **確認屬實，已採納**：Task 1 Step 7「Expected: PASS（7 個測試全數通過）」為計畫文字筆誤，`sync_account_repository_test.dart` 實際只有 6 個 `test()` 案例（`grep -c "^  test("` 核實），程式碼本身完全依 Step 6 給出的內容原樣實作，不算實作偏離計畫。已修正計畫文字為「6 個測試」。
- **確認屬實，暫不處理（維持既定範圍）**：`saveCredentials()`/`clearCredentials()` 寫入路徑無 try/catch，`testConnection()` 理論上存在「baseUrl 已覆寫成新值、但憑證寫入中途失敗仍停留舊值」的極低機率不一致風險。此為本計畫「審查修正紀錄」建議 2 已明確聲明**刻意不擴及**的範圍（寫入失敗屬於不同的失敗模式，需要另外設計），不在本 Issue 處理，留待 Issue 4（同步引擎核心）視需要一併考慮。
