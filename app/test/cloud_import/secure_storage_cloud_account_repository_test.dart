import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/cloud_import/cloud_account_repository.dart';
import 'package:elinkbook/cloud_import/cloud_provider.dart';
import 'package:elinkbook/cloud_import/secure_storage_cloud_account_repository.dart';

/// 只在本檔案內使用，不需要獨立於 `test/support/` 建檔（YAGNI，比照
/// `sync_account_repository_test.dart` 既有慣例）。
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
    originalPlatform = FlutterSecureStoragePlatform.instance;
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
  });

  tearDown(() {
    FlutterSecureStoragePlatform.instance = originalPlatform;
  });

  final tokens = CloudAccountTokens(
    accessToken: 'access-1',
    refreshToken: 'refresh-1',
    email: 'reader@example.com',
    expiresAt: DateTime.fromMillisecondsSinceEpoch(2000000000000),
  );

  test('未 link 時 isLinked 回傳 false，loadAccountEmail／loadTokens 回傳 null', () async {
    final repo = SecureStorageCloudAccountRepository();

    expect(await repo.isLinked(CloudProvider.googleDrive), false);
    expect(await repo.loadAccountEmail(CloudProvider.googleDrive), isNull);
    expect(await repo.loadTokens(CloudProvider.googleDrive), isNull);
  });

  test('link 後 isLinked 回傳 true，loadAccountEmail／loadTokens 回傳正確值', () async {
    final repo = SecureStorageCloudAccountRepository();

    await repo.link(CloudProvider.googleDrive, tokens);

    expect(await repo.isLinked(CloudProvider.googleDrive), true);
    expect(await repo.loadAccountEmail(CloudProvider.googleDrive), 'reader@example.com');
    final loaded = await repo.loadTokens(CloudProvider.googleDrive);
    expect(loaded?.accessToken, 'access-1');
    expect(loaded?.refreshToken, 'refresh-1');
    expect(loaded?.expiresAt, tokens.expiresAt);
  });

  test('link 後 unlink，isLinked 回傳 false 且 loadTokens 回傳 null', () async {
    final repo = SecureStorageCloudAccountRepository();
    await repo.link(CloudProvider.googleDrive, tokens);

    await repo.unlink(CloudProvider.googleDrive);

    expect(await repo.isLinked(CloudProvider.googleDrive), false);
    expect(await repo.loadTokens(CloudProvider.googleDrive), isNull);
  });

  test('兩個 provider 各自獨立：link 一個不影響另一個的連結狀態', () async {
    final repo = SecureStorageCloudAccountRepository();

    await repo.link(CloudProvider.googleDrive, tokens);

    expect(await repo.isLinked(CloudProvider.googleDrive), true);
    expect(await repo.isLinked(CloudProvider.oneDrive), false);
  });

  test('Keystore 讀取拋出例外時，isLinked／loadAccountEmail／loadTokens 皆安全回退為 false/null', () async {
    FlutterSecureStoragePlatform.instance = _ThrowingSecureStoragePlatform();
    final repo = SecureStorageCloudAccountRepository();

    expect(await repo.isLinked(CloudProvider.googleDrive), false);
    expect(await repo.loadAccountEmail(CloudProvider.googleDrive), isNull);
    expect(await repo.loadTokens(CloudProvider.googleDrive), isNull);
  });
}
