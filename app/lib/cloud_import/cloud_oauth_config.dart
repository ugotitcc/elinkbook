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

  /// Google Cloud Console 建立的 OAuth 2.0 用戶端 ID（電腦應用程式類型）。
  /// 開發/測試期間可用 Google Cloud Console 的「測試使用者」白名單機制
  /// 讓白名單內帳號正常登入（僅顯示「未驗證應用程式」過場警告）。
  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_ID',
    defaultValue: 'YOUR_GOOGLE_OAUTH_CLIENT_ID.apps.googleusercontent.com',
  );

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
