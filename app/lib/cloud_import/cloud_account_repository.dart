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
