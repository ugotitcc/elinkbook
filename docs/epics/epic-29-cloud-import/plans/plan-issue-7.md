# Epic 29 Issue 7：雲端服務 OAuth 統一外部設定檔 實作計劃

> **給執行者：** 本計劃必須搭配 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行。每個 Step 用 checkbox（`- [ ]`）追蹤，完成後改為 `- [x]`。

**Goal：** 把 Google Drive／OneDrive 的 OAuth 用戶端 ID 與其反推出的 redirect scheme，從目前分散在 3 個檔案（2 個 Dart 常數檔＋`AndroidManifest.xml` 2 組 intent-filter）的手動同步維護，收斂為單一 `app/config/cloud_oauth.json` 設定檔維護點。

**Architecture：** Dart 端新增 `CloudOAuthConfig`（取代 `google_oauth_config.dart`／`onedrive_oauth_config.dart` 兩個檔案），以 `String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID'/...)` 讀取 `--dart-define-from-file=config/cloud_oauth.json` 注入的編譯期常數，未提供時回退既有樣板 placeholder 值；`googleRedirectScheme`／`oneDriveRedirectScheme` 等維持既有推導公式，只是從常數改為由 client ID 計算的 getter。Android 端 `build.gradle.kts` 獨立解析同一份 `app/config/cloud_oauth.json`（Dart 編譯期常數對 Gradle 建置腳本不可見，這是兩條完全獨立的建置管線，無法共用同一次解析結果——`docs/research/cloud_oauth_unified_configuration_architecture.md` 提出的方案對此有正確認知，`/diagnose` 已核實），推導出的 scheme 寫入 `manifestPlaceholders`，`AndroidManifest.xml` 的兩組既有 intent-filter 改用 `${googleOAuthScheme}`／`${oneDriveOAuthScheme}` 佔位符。兩套推導公式（Dart getter／Gradle Kotlin 運算）各自獨立實作，程式碼內以註解互相參照，明確要求日後修改其中一處務必同步修改另一處（已知殘餘風險，見 `issues.md` Issue 7「技術可行性核實」段落，比現況「手動同步最終字串到 3 處」風險小得多但非歸零）。

**Tech Stack：** Flutter／Dart（`String.fromEnvironment`、`--dart-define-from-file`，Flutter 3.7+ 標準機制）、Android Gradle Plugin（`manifestPlaceholders`）、Groovy `JsonSlurper`（Gradle 核心內建，Kotlin DSL `.kts` 腳本可直接 import 使用）。

**Spec：** `docs/research/cloud_oauth_unified_configuration_architecture.md`（使用者提供的參考研究報告）與 `docs/epics/epic-29-cloud-import/issues.md` Issue 7（`/diagnose` 核實報告技術可行性後立案，含逐項核實紀錄與已知殘餘風險）。

## Global Constraints

- `google_oauth_config.dart`／`onedrive_oauth_config.dart` 兩個檔案的既有 scheme／URI **推導公式本身不變動**，只是從「寫死的 `const` 字串」改為「由 client ID 計算的 `static String get`」——確認過現行 `googleRedirectScheme`＝`'com.googleusercontent.apps.' + (client id 去掉 '.apps.googleusercontent.com' 尾碼)`、`oneDriveRedirectScheme`＝`'msal' + client id`，Task 1 直接沿用這兩條公式。
- `grep` 已核實全 `app/test/` 目錄零測試依賴 `googleOAuthClientId`／`googleOAuthRedirectScheme`／`oneDriveOAuthClientId`／`oneDriveOAuthRedirectScheme` 這幾個常數的具體字面值（`GoogleDriveOAuthClient`／`OneDriveOAuthClient` 既有測試僅注入 mock `http.Client`／`FakeCloudAccountRepository`），本次重構對這兩份既有測試套件**零回歸**、不需修改。
- `app/android/app/build.gradle.kts` 內存取 `project.rootDir` 時，其值恆等於 Gradle **根專案**目錄（`app/android/`，`settings.gradle.kts` 所在位置），*不是* `:app` 子專案自己的目錄——這是 Gradle 官方 API 語意（`Project.getRootDir()` 定義為「根專案的專案目錄」，不論從哪個子專案的建置腳本存取皆然），`project.rootDir.parentFile` 因此等於 `app/`。**這個依賴關係必須在程式碼內加註解**，避免日後被改成看似更直覺、實則指向錯誤路徑的寫法（例如誤用 `project.projectDir.parentFile`）。
- Gradle 端字串推導公式必須與 Dart 端 `CloudOAuthConfig.googleRedirectScheme`／`oneDriveRedirectScheme` 完全一致——兩處程式碼須以註解互相參照。
- 完成後 `flutter analyze` 必須乾淨（"No issues found!"），`flutter test` 必須全數通過、零回歸。Gradle／`AndroidManifest.xml` 變更不在 `flutter test` 涵蓋範圍內，改以本計劃 Task 2 明確列出的手動建置驗證步驟核驗（`issues.md` Issue 7 已載明此限制，非本計劃遺漏）。
- 所有程式碼註解、doc comment、commit message、本計劃文件本身，一律使用正體中文（zh-TW），不得出現簡體中文。

---

## Task 1：`CloudOAuthConfig` 統一設定類別（取代兩個舊 Dart 常數檔）

**Files：**
- Create: `app/lib/cloud_import/cloud_oauth_config.dart`
- Delete: `app/lib/cloud_import/google_oauth_config.dart`
- Delete: `app/lib/cloud_import/onedrive_oauth_config.dart`
- Modify: `app/lib/cloud_import/google_drive_oauth_client.dart`
- Modify: `app/lib/cloud_import/onedrive_oauth_client.dart`
- Test: `app/test/cloud_import/cloud_oauth_config_test.dart`

**Interfaces：**
- Produces：`abstract class CloudOAuthConfig { static const String googleClientId; static String get googleRedirectScheme; static String get googleRedirectUri; static const String oneDriveClientId; static String get oneDriveRedirectScheme; static String get oneDriveRedirectUri; }`，供 `GoogleDriveOAuthClient`／`OneDriveOAuthClient`（Task 1 內同步更新）與 Task 2 的 Gradle 腳本（僅供對照，Gradle 無法直接讀取 Dart 常數）使用。

- [x] **Step 1：寫入失敗的 `CloudOAuthConfig` 測試**

建立 `app/test/cloud_import/cloud_oauth_config_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/cloud_import/cloud_oauth_config.dart';

void main() {
  test('googleClientId 未提供 --dart-define 時回退為樣板 placeholder 值', () {
    expect(
      CloudOAuthConfig.googleClientId,
      'YOUR_GOOGLE_OAUTH_CLIENT_ID.apps.googleusercontent.com',
    );
  });

  test('googleRedirectScheme 由 googleClientId 正確推導出反向網域格式', () {
    expect(
      CloudOAuthConfig.googleRedirectScheme,
      'com.googleusercontent.apps.YOUR_GOOGLE_OAUTH_CLIENT_ID',
    );
  });

  test('googleRedirectUri 由 googleRedirectScheme 正確組成', () {
    expect(
      CloudOAuthConfig.googleRedirectUri,
      'com.googleusercontent.apps.YOUR_GOOGLE_OAUTH_CLIENT_ID:/oauth2redirect',
    );
  });

  test('oneDriveClientId 未提供 --dart-define 時回退為樣板 placeholder 值', () {
    expect(CloudOAuthConfig.oneDriveClientId, 'YOUR_ONEDRIVE_OAUTH_CLIENT_ID');
  });

  test('oneDriveRedirectScheme 由 oneDriveClientId 正確推導出 MSAL 格式', () {
    expect(
      CloudOAuthConfig.oneDriveRedirectScheme,
      'msalYOUR_ONEDRIVE_OAUTH_CLIENT_ID',
    );
  });

  test('oneDriveRedirectUri 由 oneDriveRedirectScheme 正確組成', () {
    expect(
      CloudOAuthConfig.oneDriveRedirectUri,
      'msalYOUR_ONEDRIVE_OAUTH_CLIENT_ID://auth',
    );
  });
}
```

**說明**：`flutter test` 執行時不帶 `--dart-define-from-file`，`String.fromEnvironment` 必然回退 `defaultValue`，故上述測試只驗證「未設定時的樣板值」與「兩條推導公式本身正確」，不驗證「真實憑證注入後的值」（那需要真的帶 `--dart-define-from-file` 執行，見 Task 2 手動驗證步驟）。

- [x] **Step 2：執行測試確認失敗**

執行：`flutter test test/cloud_import/cloud_oauth_config_test.dart`
預期：編譯失敗（`CloudOAuthConfig` 尚未定義）。

- [x] **Step 3：建立 `CloudOAuthConfig`**

建立 `app/lib/cloud_import/cloud_oauth_config.dart`：

```dart
/// 雲端服務 OAuth 2.0 統一設定管理器（epic-29-cloud-import Issue 7，取代
/// 原本分散在 `google_oauth_config.dart`／`onedrive_oauth_config.dart`
/// 兩個檔案的常數）。支援從編譯期環境常數（`flutter run`／`flutter build`
/// 加上 `--dart-define-from-file=config/cloud_oauth.json`）讀取外部設定，
/// 未提供時安全回退至樣板 placeholder 值。
///
/// **這是外部設定值，無法寫死在版本控制的程式碼內視為「已完成」**——每個
/// 開發者/建置環境需要各自從 Google Cloud Console／Azure 應用程式註冊
/// 取得真實憑證，填入不進版控的 `app/config/cloud_oauth.json`（樣板見
/// `app/config/cloud_oauth.example.json`），才能實際發起登入流程。
abstract class CloudOAuthConfig {
  // ==================== Google Drive ====================

  /// Google Cloud Console 建立的 OAuth 2.0 用戶端 ID（Android 應用程式
  /// 類型，公開客戶端、無 client secret，符合 spec.md「OAuth 登入機制」
  /// 對 PKCE 公開客戶端流程的要求）。開發/測試期間可用 Google Cloud
  /// Console 的「測試使用者」白名單機制讓白名單內帳號正常登入（僅顯示
  /// 「未驗證應用程式」過場警告）。
  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_ID',
    defaultValue: 'YOUR_GOOGLE_OAUTH_CLIENT_ID.apps.googleusercontent.com',
  );

  /// 依 [googleClientId] 推導的反向客戶端 ID格式 redirect URI scheme
  /// （Android 慣例，`spec.md`「OAuth 登入機制」審查 Minor #5 採納）。
  /// **必須與 `AndroidManifest.xml` 內 `${googleOAuthScheme}` 佔位符——
  /// 於 `app/android/app/build.gradle.kts` 獨立解析出的值——完全一致**：
  /// Dart 編譯期常數無法被 Gradle 建置腳本讀取，兩處各自獨立實作同一套
  /// 推導公式，修改這裡務必同步修改該處（見該檔案內對應註解）。
  static String get googleRedirectScheme {
    final prefix = googleClientId.replaceAll('.apps.googleusercontent.com', '');
    return 'com.googleusercontent.apps.$prefix';
  }

  static String get googleRedirectUri => '$googleRedirectScheme:/oauth2redirect';

  // ==================== OneDrive (Microsoft Graph) ====================

  /// Microsoft Entra ID（Azure AD）「應用程式註冊」建立的用戶端 ID（平台
  /// 類型選「行動裝置與桌面應用程式」，公開客戶端、無 client secret）。
  static const String oneDriveClientId = String.fromEnvironment(
    'ONEDRIVE_OAUTH_CLIENT_ID',
    defaultValue: 'YOUR_ONEDRIVE_OAUTH_CLIENT_ID',
  );

  /// 依 [oneDriveClientId] 推導的 MSAL 自訂 scheme（`spec.md`「OAuth
  /// 登入機制」審查 Minor #5 採納：OneDrive/Microsoft 與 Google 的反向
  /// 客戶端 ID 格式不同，走自訂 scheme）。**必須與 `AndroidManifest.xml`
  /// 內 `${oneDriveOAuthScheme}` 佔位符一致**，理由同 [googleRedirectScheme]。
  static String get oneDriveRedirectScheme => 'msal$oneDriveClientId';

  static String get oneDriveRedirectUri => '$oneDriveRedirectScheme://auth';
}
```

- [x] **Step 4：執行測試確認通過**

執行：`flutter test test/cloud_import/cloud_oauth_config_test.dart`
預期：全數 PASS。

- [x] **Step 5：`GoogleDriveOAuthClient` 改用 `CloudOAuthConfig`**

在 `app/lib/cloud_import/google_drive_oauth_client.dart` 找到 import 區塊：

```dart
import 'cloud_account_repository.dart';
import 'cloud_provider.dart';
import 'google_oauth_config.dart';
```

改為：

```dart
import 'cloud_account_repository.dart';
import 'cloud_oauth_config.dart';
import 'cloud_provider.dart';
```

找到 `link()` 內的 `authUrl` 建構區塊：

```dart
    final authUrl = Uri.parse(_authorizationEndpoint).replace(queryParameters: {
      'client_id': googleOAuthClientId,
      'redirect_uri': googleOAuthRedirectUri,
      'response_type': 'code',
```

改為：

```dart
    final authUrl = Uri.parse(_authorizationEndpoint).replace(queryParameters: {
      'client_id': CloudOAuthConfig.googleClientId,
      'redirect_uri': CloudOAuthConfig.googleRedirectUri,
      'response_type': 'code',
```

找到 `FlutterWebAuth2.authenticate` 呼叫：

```dart
      resultUrl = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: googleOAuthRedirectScheme,
      );
```

改為：

```dart
      resultUrl = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: CloudOAuthConfig.googleRedirectScheme,
      );
```

找到 `link()` 內換發 token 的請求本文：

```dart
      tokenResponse = await _httpClient.post(Uri.parse(_tokenEndpoint), body: {
        'code': code,
        'client_id': googleOAuthClientId,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': googleOAuthRedirectUri,
      });
```

改為：

```dart
      tokenResponse = await _httpClient.post(Uri.parse(_tokenEndpoint), body: {
        'code': code,
        'client_id': CloudOAuthConfig.googleClientId,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': CloudOAuthConfig.googleRedirectUri,
      });
```

找到 `ensureValidAccessToken()` 內續期請求本文：

```dart
      response = await _httpClient.post(Uri.parse(_tokenEndpoint), body: {
        'refresh_token': tokens.refreshToken,
        'client_id': googleOAuthClientId,
        'grant_type': 'refresh_token',
      });
```

改為：

```dart
      response = await _httpClient.post(Uri.parse(_tokenEndpoint), body: {
        'refresh_token': tokens.refreshToken,
        'client_id': CloudOAuthConfig.googleClientId,
        'grant_type': 'refresh_token',
      });
```

- [x] **Step 6：`OneDriveOAuthClient` 改用 `CloudOAuthConfig`**

在 `app/lib/cloud_import/onedrive_oauth_client.dart` 找到 import 區塊：

```dart
import 'cloud_account_repository.dart';
import 'cloud_provider.dart';
import 'onedrive_oauth_config.dart';
```

改為：

```dart
import 'cloud_account_repository.dart';
import 'cloud_oauth_config.dart';
import 'cloud_provider.dart';
```

找到 `link()` 內的 `authUrl` 建構區塊：

```dart
    final authUrl = Uri.parse(_authorizationEndpoint).replace(queryParameters: {
      'client_id': oneDriveOAuthClientId,
      'redirect_uri': oneDriveOAuthRedirectUri,
      'response_type': 'code',
```

改為：

```dart
    final authUrl = Uri.parse(_authorizationEndpoint).replace(queryParameters: {
      'client_id': CloudOAuthConfig.oneDriveClientId,
      'redirect_uri': CloudOAuthConfig.oneDriveRedirectUri,
      'response_type': 'code',
```

找到 `FlutterWebAuth2.authenticate` 呼叫：

```dart
      resultUrl = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: oneDriveOAuthRedirectScheme,
      );
```

改為：

```dart
      resultUrl = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: CloudOAuthConfig.oneDriveRedirectScheme,
      );
```

找到 `link()` 內換發 token 的請求本文：

```dart
      tokenResponse = await _httpClient.post(Uri.parse(_tokenEndpoint), body: {
        'code': code,
        'client_id': oneDriveOAuthClientId,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': oneDriveOAuthRedirectUri,
        'scope': _filesReadScope,
      });
```

改為：

```dart
      tokenResponse = await _httpClient.post(Uri.parse(_tokenEndpoint), body: {
        'code': code,
        'client_id': CloudOAuthConfig.oneDriveClientId,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': CloudOAuthConfig.oneDriveRedirectUri,
        'scope': _filesReadScope,
      });
```

找到 `ensureValidAccessToken()` 內續期請求本文：

```dart
      response = await _httpClient.post(Uri.parse(_tokenEndpoint), body: {
        'refresh_token': tokens.refreshToken,
        'client_id': oneDriveOAuthClientId,
        'grant_type': 'refresh_token',
        'scope': _filesReadScope,
      });
```

改為：

```dart
      response = await _httpClient.post(Uri.parse(_tokenEndpoint), body: {
        'refresh_token': tokens.refreshToken,
        'client_id': CloudOAuthConfig.oneDriveClientId,
        'grant_type': 'refresh_token',
        'scope': _filesReadScope,
      });
```

- [x] **Step 7：刪除舊有兩個設定檔**

```bash
git rm app/lib/cloud_import/google_oauth_config.dart app/lib/cloud_import/onedrive_oauth_config.dart
```

- [x] **Step 8：執行既有 OAuth client 測試與新測試確認通過**

執行：`flutter test test/cloud_import/`
預期：全數 PASS（`cloud_oauth_config_test.dart`、`google_drive_oauth_client_test.dart`、`onedrive_oauth_client_test.dart` 皆綠燈，後兩者零回歸——`grep` 已核實它們不依賴被刪除的舊常數字面值）。

- [x] **Step 9：執行完整測試套件與靜態分析確認零回歸**

執行：`flutter analyze`
預期："No issues found!"

執行：`flutter test`
預期：全數 PASS。

- [x] **Step 10：Commit**

```bash
git add app/lib/cloud_import/cloud_oauth_config.dart app/lib/cloud_import/google_drive_oauth_client.dart app/lib/cloud_import/onedrive_oauth_client.dart app/test/cloud_import/cloud_oauth_config_test.dart
git commit -m "refactor(epic-29): Issue 7——CloudOAuthConfig 取代分散的 google/onedrive_oauth_config.dart"
```

---

## Task 2：`app/config/cloud_oauth.json` 外部設定檔＋ Gradle 自動注入 `AndroidManifest.xml`

**Files：**
- Create: `app/config/cloud_oauth.example.json`
- Modify: `.gitignore`（根目錄）
- Modify: `app/android/app/build.gradle.kts`
- Modify: `app/android/app/src/main/AndroidManifest.xml`

**Interfaces：**
- Consumes：Task 1 的 `CloudOAuthConfig`（同一份 `app/config/cloud_oauth.json` 的 key 名稱 `GOOGLE_OAUTH_CLIENT_ID`／`ONEDRIVE_OAUTH_CLIENT_ID` 須與 Task 1 `String.fromEnvironment()` 讀取的 key 名稱完全一致）。
- Produces：`AndroidManifest.xml` 兩組 intent-filter 的 `android:scheme` 由 `app/config/cloud_oauth.json`（若存在）或樣板值（若不存在）自動推導填入，無需手動編輯 XML。

**本 Task 沒有 `flutter test` 可涵蓋的自動化測試 seam**（`/diagnose` 已於 `issues.md` Issue 7 標註此為已知限制，非本計劃遺漏）——Gradle 建置腳本與 Android manifest merge 皆發生在 `flutter test` 執行範圍之外，改以下方明確的手動建置驗證步驟核驗。

- [x] **Step 1：建立 JSON 設定樣板檔**

建立 `app/config/cloud_oauth.example.json`：

```json
{
  "GOOGLE_OAUTH_CLIENT_ID": "YOUR_GOOGLE_OAUTH_CLIENT_ID.apps.googleusercontent.com",
  "ONEDRIVE_OAUTH_CLIENT_ID": "YOUR_ONEDRIVE_OAUTH_CLIENT_ID"
}
```

- [x] **Step 2：`.gitignore` 新增本機真實設定檔排除規則**

在 `U:\MyDeveloper\AI\elinkBook\.gitignore` 找到：

```
tmp/
```

在其前新增一行：

```
# epic-29-cloud-import Issue 7：雲端服務 OAuth 本機真實憑證設定檔（樣板見
# app/config/cloud_oauth.example.json，此檔含開發者個人真實憑證不進版控）。
app/config/cloud_oauth.json
tmp/
```

- [x] **Step 3：`build.gradle.kts` 解析設定檔並注入 `manifestPlaceholders`**

在 `app/android/app/build.gradle.kts` 找到檔案開頭：

```kotlin
import java.text.SimpleDateFormat
import java.util.Date

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 建置當下的系統時間，供 BuildConfig.BUILD_TIME 使用（見下方 defaultConfig）。
val buildTimeString: String = SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(Date())
```

改為：

```kotlin
import groovy.json.JsonSlurper
import java.text.SimpleDateFormat
import java.util.Date

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 建置當下的系統時間，供 BuildConfig.BUILD_TIME 使用（見下方 defaultConfig）。
val buildTimeString: String = SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(Date())

// epic-29-cloud-import Issue 7：雲端服務 OAuth 統一外部設定檔。
//
// 【重要】project.rootDir 依 Gradle 官方語意恆等於「根專案」目錄
// （app/android/，settings.gradle.kts 所在位置），不論從哪個子專案的
// build.gradle.kts 存取皆然——不是「這個子專案自己的目錄」。因此
// project.rootDir.parentFile 等於 app/，下方路徑才會正確解析為
// app/config/cloud_oauth.json。切勿改成 project.projectDir.parentFile
// （那會變成 android/ 而非 app/，靜默指向錯誤路徑）。
val cloudOAuthConfigFile = File(project.rootDir.parentFile, "config/cloud_oauth.json")
val cloudOAuthExampleFile = File(project.rootDir.parentFile, "config/cloud_oauth.example.json")
val cloudOAuthTargetFile =
    if (cloudOAuthConfigFile.exists()) cloudOAuthConfigFile else cloudOAuthExampleFile

@Suppress("UNCHECKED_CAST")
val cloudOAuthJson: Map<String, Any>? = if (cloudOAuthTargetFile.exists()) {
    try {
        JsonSlurper().parseText(cloudOAuthTargetFile.readText()) as? Map<String, Any>
    } catch (e: Exception) {
        null
    }
} else null

val rawGoogleOAuthClientId = cloudOAuthJson?.get("GOOGLE_OAUTH_CLIENT_ID") as? String
    ?: "YOUR_GOOGLE_OAUTH_CLIENT_ID.apps.googleusercontent.com"
val rawOneDriveOAuthClientId = cloudOAuthJson?.get("ONEDRIVE_OAUTH_CLIENT_ID") as? String
    ?: "YOUR_ONEDRIVE_OAUTH_CLIENT_ID"

// 下列兩條推導公式必須與 app/lib/cloud_import/cloud_oauth_config.dart 內
// CloudOAuthConfig.googleRedirectScheme／oneDriveRedirectScheme 完全一致
// ——Dart 編譯期常數無法被這份 Gradle 建置腳本讀取，兩處各自獨立實作，
// 修改其中一處務必同步修改另一處。
val googleOAuthScheme =
    "com.googleusercontent.apps." + rawGoogleOAuthClientId.replace(".apps.googleusercontent.com", "")
val oneDriveOAuthScheme = "msal$rawOneDriveOAuthClientId"
```

找到 `defaultConfig` 區塊：

```kotlin
    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cc.ugotit.elinkbook"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 每次執行 Gradle 建置當下的系統時間，供「關於」頁面顯示，方便真機測試時
        // 確認手上安裝的是哪一次建置（見 docs/epics/epic-3-fonts-layout/issues.md
        // Issue 6 追加需求）。
        buildConfigField("String", "BUILD_TIME", "\"$buildTimeString\"")
    }
```

改為：

```kotlin
    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cc.ugotit.elinkbook"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 每次執行 Gradle 建置當下的系統時間，供「關於」頁面顯示，方便真機測試時
        // 確認手上安裝的是哪一次建置（見 docs/epics/epic-3-fonts-layout/issues.md
        // Issue 6 追加需求）。
        buildConfigField("String", "BUILD_TIME", "\"$buildTimeString\"")

        // epic-29-cloud-import Issue 7：自動將 app/config/cloud_oauth.json
        // 推導出的 OAuth redirect scheme 注入 AndroidManifest.xml 的
        // ${googleOAuthScheme}／${oneDriveOAuthScheme} 佔位符。
        manifestPlaceholders["googleOAuthScheme"] = googleOAuthScheme
        manifestPlaceholders["oneDriveOAuthScheme"] = oneDriveOAuthScheme
    }
```

- [x] **Step 4：`AndroidManifest.xml` 改用動態佔位符**

在 `app/android/app/src/main/AndroidManifest.xml` 找到：

```xml
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="com.googleusercontent.apps.YOUR_GOOGLE_OAUTH_CLIENT_ID"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="msalYOUR_ONEDRIVE_OAUTH_CLIENT_ID" android:host="auth"/>
            </intent-filter>
```

改為：

```xml
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="${googleOAuthScheme}"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="${oneDriveOAuthScheme}" android:host="auth"/>
            </intent-filter>
```

- [x] **Step 5：手動驗證——未提供真實設定檔時，退回樣板值仍可正常建置**

執行（在 `app/` 目錄下，確認此時 `app/config/cloud_oauth.json` 不存在）：

```bash
flutter build apk --debug
```

預期：建置成功（BUILD SUCCESSFUL），與 Issue 7 之前的既有行為一致，不因這次重構而新增建置失敗風險。

- [x] **Step 6：手動驗證——提供真實設定檔時，`manifestPlaceholders` 確實生效**

建立一個僅供本次驗證用、**不會被提交**的暫存設定檔（`app/config/cloud_oauth.json` 已在 Step 2 加入 `.gitignore`，此步驟操作安全）。以下提供 Bash（Git Bash／POSIX sh）與 PowerShell 兩種等效寫法，依實際可用的終端擇一：

Bash：

```bash
cat > app/config/cloud_oauth.json <<'EOF'
{
  "GOOGLE_OAUTH_CLIENT_ID": "999999999999-testverify.apps.googleusercontent.com",
  "ONEDRIVE_OAUTH_CLIENT_ID": "test-verify-id-1234"
}
EOF
flutter build apk --debug --dart-define-from-file=config/cloud_oauth.json
```

PowerShell：

```powershell
@'
{
  "GOOGLE_OAUTH_CLIENT_ID": "999999999999-testverify.apps.googleusercontent.com",
  "ONEDRIVE_OAUTH_CLIENT_ID": "test-verify-id-1234"
}
'@ | Out-File -FilePath app/config/cloud_oauth.json -Encoding utf8
flutter build apk --debug --dart-define-from-file=config/cloud_oauth.json
```

建置完成後，核對編譯後的 `AndroidManifest.xml` 確實反映新 scheme（Android Studio 內建的 `Merged Manifest` 檢視器，或用 `aapt2 dump xmltree` 對 `build/app/outputs/flutter-apk/app-debug.apk` 核對，尋找 `android:scheme` 屬性值應為 `com.googleusercontent.apps.999999999999-testverify` 與 `msaltest-verify-id-1234`）。

驗證完成後，清除暫存檔避免殘留混淆本機開發狀態：

Bash：`rm app/config/cloud_oauth.json`
PowerShell：`Remove-Item app/config/cloud_oauth.json`

- [x] **Step 7：Commit**

```bash
git add app/config/cloud_oauth.example.json .gitignore app/android/app/build.gradle.kts app/android/app/src/main/AndroidManifest.xml
git commit -m "feat(epic-29): Issue 7——Gradle 自動注入 app/config/cloud_oauth.json 至 AndroidManifest"
```

---

## Task 3：文件更新與最終回歸驗證

**Files：**
- Modify: `CLAUDE.md`（根目錄）

**Interfaces：**
- Consumes：Task 1、Task 2 的完整成果。

- [x] **Step 1：`CLAUDE.md`「常用指令」補上帶設定檔的建置指令**

在根目錄 `CLAUDE.md` 找到：

```
所有指令皆在 `app/` 目錄下執行。

```bash
flutter pub get
flutter test
flutter test test/screens/reader_screen_test.dart

# 提交前必須乾淨（"No issues found!"）
flutter analyze

flutter devices

# 必須指定真實裝置/模擬器（見下方「兩層測試架構」，一般 flutter test 做不到這件事）
flutter test integration_test/reader_screen_test.dart -d <device-id>

flutter build apk --debug
```
```

改為：

```
所有指令皆在 `app/` 目錄下執行。

```bash
flutter pub get
flutter test
flutter test test/screens/reader_screen_test.dart

# 提交前必須乾淨（"No issues found!"）
flutter analyze

flutter devices

# 必須指定真實裝置/模擬器（見下方「兩層測試架構」，一般 flutter test 做不到這件事）
flutter test integration_test/reader_screen_test.dart -d <device-id>

flutter build apk --debug

# 需要測試 Google Drive／OneDrive 真實 OAuth 登入流程時才需要帶入這個設定檔
# （app/config/cloud_oauth.json，樣板見 cloud_oauth.example.json，不進版控，
# 見 docs/epics/epic-29-cloud-import/issues.md Issue 7）；一般開發／
# flutter analyze／flutter test 不涉及真實登入流程，維持上方指令即可，
# 不帶這個旗標時會自動退回樣板 placeholder 值，不影響任何既有功能。
flutter run --dart-define-from-file=config/cloud_oauth.json
flutter build apk --release --dart-define-from-file=config/cloud_oauth.json
```
```

- [x] **Step 2：執行完整測試套件與靜態分析最終確認**

執行：`flutter analyze`
預期："No issues found!"

執行：`flutter test`
預期：全數 PASS，零回歸。

- [x] **Step 3：Commit**

```bash
git add CLAUDE.md
git commit -m "docs(epic-29): Issue 7——CLAUDE.md 常用指令補上 --dart-define-from-file 用法"
```

---

## Self-Review（撰寫計劃時的自我檢查記錄）

**1. Spec 涵蓋範圍檢查：**
- `docs/research/cloud_oauth_unified_configuration_architecture.md` 步驟 3.1（JSON 設定檔與樣板）、3.2（Dart 統一設定類別）、3.3（Gradle 解析注入 manifestPlaceholders）、3.4（`AndroidManifest.xml` 動態佔位符）→ Task 1／Task 2 逐一對應涵蓋。
- `issues.md` Issue 7「What to build」4 個項目（`CloudOAuthConfig`＋刪除舊檔、JSON 樣板檔＋`.gitignore`、`build.gradle.kts` 解析注入、`CLAUDE.md` 常用指令更新）→ Task 1（第 1 項）、Task 2（第 2、3 項）、Task 3（第 4 項）逐一對應涵蓋。
- `issues.md` Issue 7「單元測試要求」3 項（`CloudOAuthConfig` getter 純 Dart 測試、既有 OAuth client 測試零回歸、Gradle/manifest 手動建置驗證）→ Task 1 Step 1-8、Task 2 Step 5-6 逐一對應涵蓋。
- 研究報告「效益評估」提到的 CI/CD／多環境部署（`cloud_oauth.prod.json` 等）非本 Issue 明確要求範圍（`issues.md` 未列入 What to build），YAGNI，不在本計劃實作。

**2. 佔位符掃描：** 全文檢查過，所有 Step 皆含完整可執行的程式碼／指令區塊。Task 2 Step 5-6 的手動驗證步驟明確列出指令與預期結果，不是「請自行測試」這類空泛描述。

**3. 型別一致性檢查：** `CloudOAuthConfig` 的 6 個成員（`googleClientId`／`googleRedirectScheme`／`googleRedirectUri`／`oneDriveClientId`／`oneDriveRedirectScheme`／`oneDriveRedirectUri`）在 Task 1 定義後，於 `google_drive_oauth_client.dart`／`onedrive_oauth_client.dart`（Task 1 Step 5-6）的呼叫全數對應一致；`app/config/cloud_oauth.json` 的兩個 key 名稱（`GOOGLE_OAUTH_CLIENT_ID`／`ONEDRIVE_OAUTH_CLIENT_ID`）在 Task 1 的 `String.fromEnvironment()` 與 Task 2 的 Gradle `cloudOAuthJson?.get(...)` 兩處完全一致；`manifestPlaceholders` 的兩個 key（`googleOAuthScheme`／`oneDriveOAuthScheme`）在 Task 2 Step 3（Gradle 寫入）與 Step 4（`AndroidManifest.xml` 讀取 `${...}`）完全一致。
