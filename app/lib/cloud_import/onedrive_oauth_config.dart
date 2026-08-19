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
