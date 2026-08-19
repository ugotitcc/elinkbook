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
