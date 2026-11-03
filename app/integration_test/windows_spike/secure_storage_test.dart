// 安全儲存探針（epic-66 Issue 1 Task 10，過關條件 7）。
//
// 確認 flutter_secure_storage 在 Windows 桌面可寫入／讀回／刪除憑證鍵
// （雲端 OAuth token 的存放前提；此建置需要 VS C++ ATL 元件，見計畫
// Task 1 環境前置條件）。
//
// 執行：flutter test integration_test/windows_spike/secure_storage_test.dart -d windows

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FlutterSecureStorage 寫入 authToken 可讀回，刪除後為 null', (
    tester,
  ) async {
    const storage = FlutterSecureStorage();
    const key = 'authToken';

    // 清掉可能的殘留，確保測試從乾淨狀態開始。
    await storage.delete(key: key);

    await storage.write(key: key, value: 'epic66-spike-token');
    final readBack = await storage.read(key: key);
    expect(readBack, 'epic66-spike-token', reason: '寫入後應可讀回相同值');

    await storage.delete(key: key);
    expect(await storage.read(key: key), isNull, reason: '刪除後應讀不到');
  });
}
