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

  /// Google OAuth 用戶端密鑰（電腦應用程式類型需要，用於 token 交換）。
  static const String googleClientSecret = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_SECRET',
    defaultValue: 'YOUR_GOOGLE_OAUTH_CLIENT_SECRET',
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
