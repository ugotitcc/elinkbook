import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 同步帳號持久化（spec.md「帳號模組」、ADR 0019）：`baseUrl` 為非敏感
/// 設定，存 [SharedPreferences]；`authToken`／`userId`／`email` 三項憑證
/// 存 [FlutterSecureStorage]（Android Keystore／iOS Keychain 加密），是
/// 本專案首次引入的安全性相關儲存機制，僅限這三項，其餘既有偏好設定
/// 不受影響。
class SyncAccountRepository {
  static const _baseUrlKey = 'sync_base_url';
  static const _authTokenKey = 'sync_auth_token';
  static const _userIdKey = 'sync_user_id';
  static const _emailKey = 'sync_email';

  /// 本專案採自架架構（ADR 0019 決策 1：base URL 由使用者自行輸入，不
  /// 寫死單一官方端點），沒有官方公開服務可預填；空字串代表「尚未設定」，
  /// 畫面需引導使用者輸入自架的 base URL。
  static const defaultBaseUrl = '';

  final FlutterSecureStorage _secureStorage;

  SyncAccountRepository({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  Future<String> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey) ?? defaultBaseUrl;
  }

  Future<void> saveBaseUrl(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, baseUrl);
  }

  /// 部分機種（尤其 OEM 客製 Android Keystore 有瑕疵的裝置，官方套件
  /// GitHub issue 已有多起真實回報，例如 Keystore 憑證損毀／韌體更新後
  /// 解密失敗）讀取時會拋出 `PlatformException`，非本專案能控制的環境
  /// 因素；讀取失敗時安全回退為「視同未登入」（回傳 `null`），迫使使用者
  /// 重新登入，而不是讓 `SyncSettingsScreen` 卡在載入畫面或讓例外往上
  /// 拋出中斷整個 Settings 畫面（2026-08-03 審查修正，
  /// tmp/epic-8/plan-issue-2-review.md 建議 2）。
  Future<String?> loadAuthToken() async {
    try {
      return await _secureStorage.read(key: _authTokenKey);
    } catch (_) {
      return null;
    }
  }

  Future<String?> loadUserId() async {
    try {
      return await _secureStorage.read(key: _userIdKey);
    } catch (_) {
      return null;
    }
  }

  Future<String?> loadEmail() async {
    try {
      return await _secureStorage.read(key: _emailKey);
    } catch (_) {
      return null;
    }
  }

  /// 登入態：spec.md「帳號模組」定義 `authToken == null` 即視為未登入
  /// （讀取失敗時 [loadAuthToken] 已回退為 `null`，同樣視為未登入）。
  Future<bool> isLoggedIn() async => await loadAuthToken() != null;

  Future<void> saveCredentials({
    required String authToken,
    required String userId,
    required String email,
  }) async {
    await _secureStorage.write(key: _authTokenKey, value: authToken);
    await _secureStorage.write(key: _userIdKey, value: userId);
    await _secureStorage.write(key: _emailKey, value: email);
  }

  /// 只清除同步憑證（FR-30），不影響任何本機資料（design.md 決策 9）。
  Future<void> clearCredentials() async {
    await _secureStorage.delete(key: _authTokenKey);
    await _secureStorage.delete(key: _userIdKey);
    await _secureStorage.delete(key: _emailKey);
  }
}
