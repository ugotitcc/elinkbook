import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'cloud_account_repository.dart';
import 'cloud_provider.dart';

/// [CloudAccountRepository] 的 `FlutterSecureStorage` 實作（Android
/// Keystore／iOS Keychain 加密），比照 `SyncAccountRepository` 既有的安全
/// 儲存與讀取失敗回退模式。每個 provider 的四個欄位各自存成獨立 key
/// （前綴 `cloud_account_<provider>_`），彼此互不影響。
class SecureStorageCloudAccountRepository implements CloudAccountRepository {
  final FlutterSecureStorage _secureStorage;

  SecureStorageCloudAccountRepository({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  String _accessTokenKey(CloudProvider p) => 'cloud_account_${p.name}_access_token';
  String _refreshTokenKey(CloudProvider p) => 'cloud_account_${p.name}_refresh_token';
  String _emailKey(CloudProvider p) => 'cloud_account_${p.name}_email';
  String _expiresAtKey(CloudProvider p) => 'cloud_account_${p.name}_expires_at';

  @override
  Future<void> link(CloudProvider provider, CloudAccountTokens tokens) async {
    await _secureStorage.write(key: _accessTokenKey(provider), value: tokens.accessToken);
    await _secureStorage.write(key: _refreshTokenKey(provider), value: tokens.refreshToken);
    await _secureStorage.write(key: _emailKey(provider), value: tokens.email);
    await _secureStorage.write(
      key: _expiresAtKey(provider),
      value: tokens.expiresAt.millisecondsSinceEpoch.toString(),
    );
  }

  @override
  Future<void> unlink(CloudProvider provider) async {
    await _secureStorage.delete(key: _accessTokenKey(provider));
    await _secureStorage.delete(key: _refreshTokenKey(provider));
    await _secureStorage.delete(key: _emailKey(provider));
    await _secureStorage.delete(key: _expiresAtKey(provider));
  }

  @override
  Future<bool> isLinked(CloudProvider provider) async =>
      await _readSafe(_accessTokenKey(provider)) != null;

  @override
  Future<String?> loadAccountEmail(CloudProvider provider) => _readSafe(_emailKey(provider));

  @override
  Future<CloudAccountTokens?> loadTokens(CloudProvider provider) async {
    final accessToken = await _readSafe(_accessTokenKey(provider));
    final refreshToken = await _readSafe(_refreshTokenKey(provider));
    final email = await _readSafe(_emailKey(provider));
    final expiresAtRaw = await _readSafe(_expiresAtKey(provider));
    if (accessToken == null || refreshToken == null || email == null || expiresAtRaw == null) {
      return null;
    }
    // expires_at 若因未知原因損毀而無法解析為數字，比照其餘欄位的安全
    // 回退慣例視同「憑證不存在」，不拋出例外中斷呼叫端。
    final expiresAtMillis = int.tryParse(expiresAtRaw);
    if (expiresAtMillis == null) return null;
    return CloudAccountTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      email: email,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMillis),
    );
  }

  /// 部分機種（OEM 客製 Android Keystore 有瑕疵的裝置）讀取時會拋出
  /// `PlatformException`，比照 `SyncAccountRepository` 既有的安全回退模式：
  /// 讀取失敗一律視同「該欄位不存在」，不拋出例外中斷呼叫端。
  Future<String?> _readSafe(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (_) {
      return null;
    }
  }
}
