import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';
import 'package:elinkbook/cloud_import/onedrive_oauth_client.dart';
import 'package:elinkbook/remote/opds_client.dart';
import 'package:elinkbook/l10n/app_locale.dart';
import 'package:elinkbook/theme/app_theme.dart';

import '../support/fake_cloud_account_repository.dart';
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_remote_server_repository.dart';
import '../support/fake_opds_client.dart';
import '../support/fake_remote_thumbnail_cache.dart';

void main() {
  test('LibraryCloudAccountDependencies 原樣持有五個注入的依賴，未提供時預設皆為 null', () {
    final cloudAccountRepository = FakeCloudAccountRepository();
    final googleDriveOAuthClient =
        GoogleDriveOAuthClient(accountRepository: cloudAccountRepository);
    final oneDriveOAuthClient =
        OneDriveOAuthClient(accountRepository: cloudAccountRepository);
    final googleDriveStorageClient = FakeCloudStorageClient();
    final oneDriveStorageClient = FakeCloudStorageClient();

    const empty = LibraryCloudAccountDependencies();
    expect(empty.cloudAccountRepository, isNull);
    expect(empty.googleDriveOAuthClient, isNull);
    expect(empty.oneDriveOAuthClient, isNull);
    expect(empty.googleDriveStorageClient, isNull);
    expect(empty.oneDriveStorageClient, isNull);

    final dependencies = LibraryCloudAccountDependencies(
      cloudAccountRepository: cloudAccountRepository,
      googleDriveOAuthClient: googleDriveOAuthClient,
      oneDriveOAuthClient: oneDriveOAuthClient,
      googleDriveStorageClient: googleDriveStorageClient,
      oneDriveStorageClient: oneDriveStorageClient,
    );
    expect(dependencies.cloudAccountRepository, same(cloudAccountRepository));
    expect(dependencies.googleDriveOAuthClient, same(googleDriveOAuthClient));
    expect(dependencies.oneDriveOAuthClient, same(oneDriveOAuthClient));
    expect(dependencies.googleDriveStorageClient, same(googleDriveStorageClient));
    expect(dependencies.oneDriveStorageClient, same(oneDriveStorageClient));
  });

  test('LibraryRemoteLibraryDependencies 原樣持有三個注入的依賴，未提供時預設皆為 null', () {
    final remoteServerRepository = FakeRemoteServerRepository();
    OpdsClient createClient() => FakeOpdsClient();
    final thumbnailCache = FakeRemoteThumbnailCache();

    const empty = LibraryRemoteLibraryDependencies();
    expect(empty.remoteServerRepository, isNull);
    expect(empty.createOpdsClient, isNull);
    expect(empty.thumbnailCache, isNull);

    final dependencies = LibraryRemoteLibraryDependencies(
      remoteServerRepository: remoteServerRepository,
      createOpdsClient: createClient,
      thumbnailCache: thumbnailCache,
    );
    expect(dependencies.remoteServerRepository, same(remoteServerRepository));
    expect(dependencies.createOpdsClient, same(createClient));
    expect(dependencies.thumbnailCache, same(thumbnailCache));
  });

  test('LibraryThemeDependencies 原樣持有四個注入的值，未提供時 currentTheme/isEinkMode 沿用現行預設值、callback 預設為 null', () {
    const empty = LibraryThemeDependencies();
    expect(empty.currentTheme, AppTheme.light);
    expect(empty.isEinkMode, isFalse);
    expect(empty.onThemeChanged, isNull);
    expect(empty.onEinkModeChanged, isNull);

    void onThemeChanged(AppTheme theme) {}
    void onEinkModeChanged(bool enabled) {}
    final dependencies = LibraryThemeDependencies(
      currentTheme: AppTheme.dark,
      isEinkMode: true,
      onThemeChanged: onThemeChanged,
      onEinkModeChanged: onEinkModeChanged,
    );
    expect(dependencies.currentTheme, AppTheme.dark);
    expect(dependencies.isEinkMode, isTrue);
    expect(dependencies.onThemeChanged, same(onThemeChanged));
    expect(dependencies.onEinkModeChanged, same(onEinkModeChanged));
  });

  test('LibraryLocaleDependencies 原樣持有兩個注入的值，未提供時皆為 null（跟隨系統／無回呼）', () {
    const empty = LibraryLocaleDependencies();
    expect(empty.currentLocaleOverride, isNull);
    expect(empty.onLocaleChanged, isNull);

    void onLocaleChanged(AppLocale? locale) {}
    final dependencies = LibraryLocaleDependencies(
      currentLocaleOverride: AppLocale.zhCN,
      onLocaleChanged: onLocaleChanged,
    );
    expect(dependencies.currentLocaleOverride, AppLocale.zhCN);
    expect(dependencies.onLocaleChanged, same(onLocaleChanged));
  });
}
