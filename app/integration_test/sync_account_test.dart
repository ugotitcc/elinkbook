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
