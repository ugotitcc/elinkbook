# Epic 29 Issue 8：Google Drive OAuth 用戶端類型改為設定檔驅動 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 Google Drive OAuth 是否為「機密客戶端」（電腦應用程式類型，需要 `client_secret`）或「公開客戶端」（Android 類型，不需要 `client_secret`）完全由 `app/config/cloud_oauth.json` 是否填入 `GOOGLE_OAUTH_CLIENT_SECRET` 決定，未來切換用戶端類型不需要修改任何 `.dart` 程式碼；同時修復 `ensureValidAccessToken()` 換發 token 時遺漏帶入 `client_secret` 的既有缺陷。

**Architecture:** `CloudOAuthConfig` 新增 `googleIsConfidentialClient` 布林 getter（`googleClientSecret.isNotEmpty`）；`GoogleDriveOAuthClient` 建構子新增可選具名參數 `clientSecret`（預設值取自 `CloudOAuthConfig.googleClientSecret` 這個編譯期常數，`main.dart` 不需要改動），新增私有共用方法 `_tokenRequestBody()` 統一組出 token 端點請求 body、只在 `clientSecret` 非空時才併入 `client_secret` 欄位；`link()`（authorization_code 換發）與 `ensureValidAccessToken()`（refresh_token 換發）兩處都改用這個共用方法，避免兩個呼叫點各自處理、彼此不一致（`/diagnose` 已核實這正是目前的實際狀況：`link()` 有帶、`ensureValidAccessToken()` 沒帶）。透過建構子注入而非直接讀 `CloudOAuthConfig` 靜態常數，讓 `client_secret` 是否帶入這件事在測試環境下可以被覆寫、可測試——`CloudOAuthConfig.googleClientSecret` 本身是 `String.fromEnvironment` 編譯期常數，`flutter test` 執行期無法動態切換其值，若不透過建構子注入就沒有測試 seam 能驗證兩種分支。

**Tech Stack:** Flutter/Dart，不新增任何依賴。

**Spec:** [`docs/epics/epic-29-cloud-import/spec.md`](../spec.md)「OAuth 登入機制」；[`docs/epics/epic-29-cloud-import/issues.md`](../issues.md) Issue 8。本次修復的根因排查記錄在對話中的 `/diagnose` 分析（已核實 commit `eaf8ba1` 實際 diff，非憑空假設），Issue 8 條目本身已完整轉述核實結果，不需要另外查閱對話記錄。

## Global Constraints

- 所有回應、程式註解、文件、commit 訊息一律使用正體中文（zh-TW），禁止簡體中文。
- 審查一律先產出報告，不得直接修改被審查的計劃/程式碼（本專案 SDD 工作流程慣例）。
- `flutter analyze` 必須保持乾淨（"No issues found!"）；`flutter test` 全數通過、零回歸。
- 不新增任何 `pubspec.yaml` 依賴。
- 每完成一個 Task 的 Step，把該 Step 前面的 `- [ ]` 改成 `- [x]`。

---

## 現況（實作前必讀）

`main` 分支目前的 `app/lib/cloud_import/google_drive_oauth_client.dart`／`cloud_oauth_config.dart` 是使用者在 commit `eaf8ba1`（「Google Drive 登入改用電腦類型服務登入」）手動改的，**沒有經過計劃/審查流程**，用來讓真機在「Android 用戶端類型需要 Google Play Console 擁有權驗證、驗證需要時間」的限制下，先改用「電腦應用程式（Desktop）」類型的 OAuth 用戶端讓開發測試能繼續進行。這次的修法要在這個既有的 Desktop 類型改動基礎上，把「client_secret 何時該帶」這件事收斂成設定檔驅動、可測試、兩處呼叫點一致，**不是**要把程式碼改回 Android-only 或 Desktop-only 寫死其中一種。

- `app/lib/cloud_import/cloud_oauth_config.dart`：目前 `googleClientSecret` 的 `defaultValue` 是樣板字串 `'YOUR_GOOGLE_OAUTH_CLIENT_SECRET'`（第 21-24 行左右，實際行號依目前檔案為準，可用 `grep -n googleClientSecret` 確認），沒有任何「是否為機密客戶端」的判斷方法。
- `app/lib/cloud_import/google_drive_oauth_client.dart`：`link()`（約第 35-110 行）的 token 交換呼叫（約第 67-79 行）目前**無條件**帶入 `'client_secret': CloudOAuthConfig.googleClientSecret,`；`ensureValidAccessToken()`（約第 120-165 行）的 refresh_token 換發呼叫（約第 128-137 行）**完全沒有**帶 `client_secret` 欄位——這是本次要修的核心不一致。
- `app/config/cloud_oauth.example.json` 目前只有 `GOOGLE_OAUTH_CLIENT_ID`／`ONEDRIVE_OAUTH_CLIENT_ID` 兩個鍵，沒有 `GOOGLE_OAUTH_CLIENT_SECRET`。
- `app/test/cloud_import/google_drive_oauth_client_test.dart` 現有 4 則測試，皆用 `MockClient` 驗證 `ensureValidAccessToken()` 的行為（`link()` 因需要 `FlutterWebAuth2.authenticate()` 無法在 widget/unit test 環境下驅動，比照 Issue 1 既定決策不做自動化測試，見 `docs/epics/epic-29-cloud-import/issues.md` Issue 1「單元測試要求」）。
- 專案內其餘 7 處建構 `GoogleDriveOAuthClient(...)` 的既有呼叫（`google_drive_storage_client_test.dart` 2 處、`cloud_account_settings_screen_test.dart` 6 處、`settings_screen_test.dart` 1 處，以及 `main.dart` 正式組裝那 1 處）皆未傳入 `httpClient` 以外的參數，只靠建構子預設值運作——這是本次新增 `clientSecret` 具名參數時必須維持零回歸的既有呼叫面。

---

## Task 1：`CloudOAuthConfig` 新增 `googleIsConfidentialClient`

**Files:**
- Modify: `app/lib/cloud_import/cloud_oauth_config.dart`
- Modify: `app/config/cloud_oauth.example.json`
- Test: `app/test/cloud_import/cloud_oauth_config_test.dart`

**Interfaces:**
- Produces：`CloudOAuthConfig.googleClientSecret`（型別不變，仍是 `String`，只改 `defaultValue`）；新增 `static bool get googleIsConfidentialClient`，供 Task 2 的 `GoogleDriveOAuthClient` 參考語意（Task 2 實際判斷邏輯直接用建構子注入值的 `.isNotEmpty`，不會呼叫這個 getter，但這個 getter 本身要存在、有測試，供其他呼叫端或未來人工核對設定時使用，語意與 Task 2 的判斷邏輯必須一致）。

- [ ] **Step 1：寫失敗測試**

在 `app/test/cloud_import/cloud_oauth_config_test.dart` 內，`oneDriveClientId` 那組測試之前（第 24 行 `test('googleRedirectUri...'` 之後）新增：

```dart
  test('googleClientSecret 未提供 --dart-define 時預設為空字串', () {
    expect(CloudOAuthConfig.googleClientSecret, '');
  });

  test('googleIsConfidentialClient 在 googleClientSecret 為空字串時為 false', () {
    expect(CloudOAuthConfig.googleIsConfidentialClient, isFalse);
  });
```

- [ ] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/cloud_import/cloud_oauth_config_test.dart --plain-name "googleClientSecret"
flutter test test/cloud_import/cloud_oauth_config_test.dart --plain-name "googleIsConfidentialClient"
```

預期：第一則因為目前 `defaultValue` 是樣板字串而非空字串，斷言失敗；第二則因為 `googleIsConfidentialClient` 尚未定義，編譯失敗。

- [ ] **Step 3：修改 `cloud_oauth_config.dart`**

找到目前的：

```dart
  /// Google OAuth 用戶端密鑰（電腦應用程式類型需要，用於 token 交換）。
  static const String googleClientSecret = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_SECRET',
    defaultValue: 'YOUR_GOOGLE_OAUTH_CLIENT_SECRET',
  );
```

改成：

```dart
  /// Google OAuth 用戶端密鑰。**是否需要填這個欄位，取決於 Google Cloud
  /// Console 建立的是哪一種類型的 OAuth 用戶端**：
  /// - **Android** 類型（公開客戶端）：Google 不核發、也不接受
  ///   client secret，這個欄位應留空（不設定 `GOOGLE_OAUTH_CLIENT_SECRET`
  ///   或設為空字串）。但 Android 類型的用戶端需要通過 Google Play
  ///   Console 的應用程式擁有權驗證（連結 SHA-1 簽署憑證）才能正常登入，
  ///   這道驗證跟 OAuth 同意畫面的「測試使用者」白名單是**兩件獨立的事**、
  ///   無法用白名單繞過，且需要時間完成（`/diagnose` 已核實，見
  ///   `docs/epics/epic-29-cloud-import/issues.md` Issue 8「背景」）。
  /// - **電腦應用程式（Desktop）** 類型（機密客戶端）：不受上面那道
  ///   Android 專屬的擁有權驗證限制，但 token 交換／換發時都必須帶入
  ///   client secret，這個欄位要填入 Google Cloud Console 該用戶端頁面
  ///   提供的密鑰值。
  ///
  /// 留空（預設值）代表目前使用 Android 類型；[GoogleDriveOAuthClient]
  /// 依這個欄位是否為空字串決定要不要在 token 請求內帶入 `client_secret`
  /// （見該類別的 `_tokenRequestBody()`），呼叫端不需要另外指定「目前是
  /// 哪一種類型」——這個欄位本身就是那個開關。
  static const String googleClientSecret = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_SECRET',
    defaultValue: '',
  );

  /// 目前設定的 [googleClientSecret] 是否代表「機密客戶端」（電腦應用程式
  /// 類型）。`false` 代表公開客戶端（Android 類型，見 [googleClientSecret]
  /// 文件說明）。
  static bool get googleIsConfidentialClient => googleClientSecret.isNotEmpty;
```

- [ ] **Step 4：更新 `cloud_oauth.example.json`**

把 `app/config/cloud_oauth.example.json` 改成：

```json
{
  "GOOGLE_OAUTH_CLIENT_ID": "YOUR_GOOGLE_OAUTH_CLIENT_ID.apps.googleusercontent.com",
  "GOOGLE_OAUTH_CLIENT_SECRET": "",
  "ONEDRIVE_OAUTH_CLIENT_ID": "YOUR_ONEDRIVE_OAUTH_CLIENT_ID"
}
```

（`GOOGLE_OAUTH_CLIENT_SECRET` 留空字串——Android 類型用戶端的正確設定就是留空；若改用電腦應用程式類型，開發者自行把這個值換成 Google Cloud Console 提供的密鑰。）

- [ ] **Step 5：執行測試，確認通過**

```bash
cd app
flutter test test/cloud_import/cloud_oauth_config_test.dart
```

預期：全數 PASS，含新增的 2 則。

- [ ] **Step 6：Commit**

```bash
git add app/lib/cloud_import/cloud_oauth_config.dart app/config/cloud_oauth.example.json app/test/cloud_import/cloud_oauth_config_test.dart
git commit -m "feat(epic-29): Issue 8 Task 1——CloudOAuthConfig 新增 googleIsConfidentialClient"
```

---

## Task 2：`GoogleDriveOAuthClient` 改為建構子注入 `clientSecret`，統一兩處 token 交換邏輯

**Files:**
- Modify: `app/lib/cloud_import/google_drive_oauth_client.dart`
- Test: `app/test/cloud_import/google_drive_oauth_client_test.dart`

**Interfaces:**
- Consumes：Task 1 產出的 `CloudOAuthConfig.googleClientSecret`（作為建構子預設值來源，編譯期常數）。
- Produces：`GoogleDriveOAuthClient` 新增的可選具名建構參數 `String clientSecret = CloudOAuthConfig.googleClientSecret`；新增私有方法 `Map<String, String> _tokenRequestBody(Map<String, String> params)`（僅本類別內部使用）。

- [ ] **Step 1：寫失敗測試——公開客戶端（預設）時，refresh token 換發不帶 `client_secret`**

在 `app/test/cloud_import/google_drive_oauth_client_test.dart` 內，找到現有第 52-83 行「access token 即將到期時，成功換發新 token 並更新 repository」這則測試，在它前後新增一個新的 `group`（或直接在檔案最後 `}` 之前新增，維持與現有測試同一層級即可）：

```dart
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
```

- [ ] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/cloud_import/google_drive_oauth_client_test.dart --plain-name "client_secret 是否併入"
```

預期：第一則因為目前 `ensureValidAccessToken()` 本來就沒帶 `client_secret`，實際上**可能已經通過**（這是本次要保護住的既有正確行為，不是要修的 bug）；第二則因為 `clientSecret` 具名參數尚未定義，編譯失敗——兩則合在一起跑會因編譯錯誤全部失敗，這是預期的。

- [ ] **Step 3：修改 `google_drive_oauth_client.dart`**

在 class 欄位宣告（第 22-29 行左右）新增 `_clientSecret`：

```dart
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
```

新增私有方法（放在 `_codeChallengeFor` 之後、class 結尾之前即可）：

```dart
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
```

修改 `link()` 內的 token 交換呼叫（原本）：

```dart
      tokenResponse = await _httpClient.post(Uri.parse(_tokenEndpoint), body: {
        'code': code,
        'client_id': CloudOAuthConfig.googleClientId,
        'client_secret': CloudOAuthConfig.googleClientSecret,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': CloudOAuthConfig.googleRedirectUri,
      });
```

改成：

```dart
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
```

修改 `ensureValidAccessToken()` 內的 refresh 呼叫（原本）：

```dart
      response = await _httpClient.post(Uri.parse(_tokenEndpoint), body: {
        'refresh_token': tokens.refreshToken,
        'client_id': CloudOAuthConfig.googleClientId,
        'grant_type': 'refresh_token',
      });
```

改成：

```dart
      response = await _httpClient.post(
        Uri.parse(_tokenEndpoint),
        body: _tokenRequestBody({
          'refresh_token': tokens.refreshToken,
          'client_id': CloudOAuthConfig.googleClientId,
          'grant_type': 'refresh_token',
        }),
      );
```

- [ ] **Step 4：執行測試，確認通過**

```bash
cd app
flutter test test/cloud_import/google_drive_oauth_client_test.dart
```

預期：全數 PASS，含新增的 2 則（原本 4 則 + 新增 2 則 = 6 則）。

- [ ] **Step 5：確認其餘既有呼叫端零回歸**

```bash
cd app
flutter test test/cloud_import/google_drive_storage_client_test.dart
flutter test test/screens/cloud_account_settings_screen_test.dart
flutter test test/screens/settings_screen_test.dart
```

預期：全數 PASS——這 3 個測試檔案內建構 `GoogleDriveOAuthClient(...)` 的 7 處呼叫皆未傳 `clientSecret`，沿用新的預設值（`CloudOAuthConfig.googleClientSecret`，測試環境下為空字串），不影響任何既有斷言。

- [ ] **Step 6：執行完整測試套件與靜態分析**

```bash
cd app
flutter analyze
flutter test
```

預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS（相對目前 main 分支的 1633 項，Task 1 新增 2 項、Task 2 新增 2 項，共增加 4 項）。

- [ ] **Step 7：Commit**

```bash
git add app/lib/cloud_import/google_drive_oauth_client.dart app/test/cloud_import/google_drive_oauth_client_test.dart
git commit -m "fix(epic-29): Issue 8 Task 2——GoogleDriveOAuthClient client_secret 改設定檔驅動，修復 ensureValidAccessToken 遺漏帶入"
```

---

## 自我審查（Self-Review）記錄

**規格覆蓋度：**
- issues.md Issue 8「切換用戶端類型不需要修改 `.dart` 程式碼，只需編輯 `cloud_oauth.json`」→ Task 1（`googleClientSecret` 預設空字串＋`googleIsConfidentialClient`）＋ Task 2（建構子預設值取自 `CloudOAuthConfig.googleClientSecret`，`main.dart` 零改動）。✅
- 「修復 `ensureValidAccessToken()` 遺漏帶入 `client_secret`」→ Task 2 Step 3 兩處呼叫皆改用 `_tokenRequestBody()`。✅
- 「兩處呼叫點不再各自處理、避免再度分岔」→ Task 2 的 `_tokenRequestBody()` 共用方法設計本身即是這個要求的落實。✅
- 「既有測試零回歸」→ Task 2 Step 5 明確列出 3 個受影響測試檔案、7 處既有呼叫端逐一確認。✅
- 使用者原始問題「能否設定檔驅動」→ 全篇皆以此為設計核心，`app/config/cloud_oauth.json`（開發者本機檔案，不進版控）是唯一需要編輯的地方。✅

**佔位符掃描：** 全文無 "TBD"／"implement later"／"add appropriate error handling" 等禁止字樣，所有程式碼區塊皆為可直接套用的完整內容。

**型別一致性檢查：** `clientSecret`／`_clientSecret` 皆為 `String`（非 `String?`，用空字串代表「未設定」，與 `CloudOAuthConfig.googleClientSecret` 的型別一致，不需要額外的 null 判斷分支）；`_tokenRequestBody(Map<String, String> params) → Map<String, String>` 的簽章在 Task 2 Step 3 的宣告與兩個呼叫點（`link()`／`ensureValidAccessToken()`）用法一致。`googleIsConfidentialClient`（Task 1）與 `_clientSecret.isEmpty`（Task 2）判斷邏輯語意一致（皆為「以空字串代表公開客戶端」），但刻意不讓 Task 2 直接呼叫 Task 1 的 `googleIsConfidentialClient`——因為 Task 2 判斷的是**建構子注入值** `_clientSecret`（測試時可能不等於 `CloudOAuthConfig.googleClientSecret`），若改呼叫 `CloudOAuthConfig.googleIsConfidentialClient` 會繞過注入值直接讀編譯期常數，讓建構子注入形同虛設、測試 seam 失效，這是刻意的設計決策而非疏漏。

**簡體字掃描：** 全文以正體中文撰寫，未使用任何簡體字。

---

## 執行方式選擇

計劃完成，已存至 `docs/epics/epic-29-cloud-import/plans/plan-issue-8.md`。兩種執行方式可選：

1. **Subagent-Driven（建議）**——每個 Task 派一個全新 subagent 實作，兩階段審查，快速迭代。
2. **Inline Execution**——在本次對話內依 Task 順序批次執行，每個檢查點暫停確認。

請問要採用哪一種方式？
