import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 測試用 [PathProviderPlatform] 替身：`flutter test`（無真實裝置）無法
/// 觸發 path_provider 的原生實作，直接回傳呼叫端指定的真實可寫入目錄
/// （例如 `Directory.systemTemp` 底下的暫存子目錄），讓
/// `getTemporaryDirectory()` 在純 widget test 環境下也能正常運作、寫出
/// 可驗證的真實檔案。比照本專案既有 `test/support/fake_*.dart` 命名慣例。
class FakePathProviderPlatform extends PathProviderPlatform {
  final String path;

  FakePathProviderPlatform(this.path);

  @override
  Future<String?> getTemporaryPath() async => path;
}
