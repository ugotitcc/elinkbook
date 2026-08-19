import 'package:elinkbook/cloud_import/cloud_account_repository.dart';
import 'package:elinkbook/cloud_import/cloud_provider.dart';

/// 供 widget test 使用的記憶體內 [CloudAccountRepository] 假實作（比照
/// `FakeRemoteServerRepository`／`FakeLibraryRepository` 既有命名慣例），
/// 避免 widget test 依賴真實 `FlutterSecureStorage`。
class FakeCloudAccountRepository implements CloudAccountRepository {
  final Map<CloudProvider, CloudAccountTokens> _linked = {};

  @override
  Future<void> link(CloudProvider provider, CloudAccountTokens tokens) async {
    _linked[provider] = tokens;
  }

  @override
  Future<void> unlink(CloudProvider provider) async {
    _linked.remove(provider);
  }

  @override
  Future<bool> isLinked(CloudProvider provider) async => _linked.containsKey(provider);

  @override
  Future<String?> loadAccountEmail(CloudProvider provider) async => _linked[provider]?.email;

  @override
  Future<CloudAccountTokens?> loadTokens(CloudProvider provider) async => _linked[provider];
}
