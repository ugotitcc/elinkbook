import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';

/// 模擬部分機種讀取 Keystore 時拋出 `PlatformException` 的情境
/// （2026-08-03 審查修正，tmp/epic-8/plan-issue-2-review.md 建議 2），
/// 只在本檔案內使用，不需要獨立於 `test/support/` 建檔（YAGNI）。
class _ThrowingSecureStoragePlatform extends FlutterSecureStoragePlatform {
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    throw PlatformException(code: 'read_error', message: 'Keystore 損毀');
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {}

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      false;

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {}

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      {};

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {}
}

void main() {
  late FlutterSecureStoragePlatform originalPlatform;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalPlatform = FlutterSecureStoragePlatform.instance;
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform({});
  });

  tearDown(() {
    FlutterSecureStoragePlatform.instance = originalPlatform;
  });

  test('Keystore 讀取拋出例外時，loadAuthToken／loadUserId／loadEmail 皆安全回退為 null，isLoggedIn 回傳 false',
      () async {
    FlutterSecureStoragePlatform.instance = _ThrowingSecureStoragePlatform();
    final repo = SyncAccountRepository();

    expect(await repo.loadAuthToken(), isNull);
    expect(await repo.loadUserId(), isNull);
    expect(await repo.loadEmail(), isNull);
    expect(await repo.isLoggedIn(), false);
  });

  test('尚未設定過 base URL 時，loadBaseUrl 回傳空字串（本專案自架架構無官方預設值）',
      () async {
    final repo = SyncAccountRepository();
    expect(await repo.loadBaseUrl(), '');
  });

  test('saveBaseUrl 寫入後，loadBaseUrl 讀回相同的值', () async {
    final repo = SyncAccountRepository();
    await repo.saveBaseUrl('http://127.0.0.1:8090');
    expect(await repo.loadBaseUrl(), 'http://127.0.0.1:8090');
  });

  test('尚未登入時，loadAuthToken／loadUserId／loadEmail 皆回傳 null，isLoggedIn 回傳 false',
      () async {
    final repo = SyncAccountRepository();
    expect(await repo.loadAuthToken(), isNull);
    expect(await repo.loadUserId(), isNull);
    expect(await repo.loadEmail(), isNull);
    expect(await repo.isLoggedIn(), false);
  });

  test('saveCredentials 寫入後，三項憑證皆可讀回，isLoggedIn 回傳 true', () async {
    final repo = SyncAccountRepository();
    await repo.saveCredentials(
      authToken: 'token-abc',
      userId: 'user-123',
      email: 'reader@example.com',
    );
    expect(await repo.loadAuthToken(), 'token-abc');
    expect(await repo.loadUserId(), 'user-123');
    expect(await repo.loadEmail(), 'reader@example.com');
    expect(await repo.isLoggedIn(), true);
  });

  test('clearCredentials 清除全部三項憑證，不影響 base URL', () async {
    final repo = SyncAccountRepository();
    await repo.saveBaseUrl('http://127.0.0.1:8090');
    await repo.saveCredentials(
      authToken: 'token-abc',
      userId: 'user-123',
      email: 'reader@example.com',
    );

    await repo.clearCredentials();

    expect(await repo.loadAuthToken(), isNull);
    expect(await repo.loadUserId(), isNull);
    expect(await repo.loadEmail(), isNull);
    expect(await repo.isLoggedIn(), false);
    expect(await repo.loadBaseUrl(), 'http://127.0.0.1:8090');
  });
}
