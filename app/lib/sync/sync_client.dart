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
      final userId = authData.record.id;
      if (userId.isEmpty) return false;
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
