import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/reader/layout_preset_repository.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_client.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';
import 'package:elinkbook/cloud_import/google_drive_oauth_client.dart';
import 'package:elinkbook/cloud_import/onedrive_oauth_client.dart';
import 'package:elinkbook/remote/opds_client.dart';
import 'package:elinkbook/l10n/app_locale.dart';
import 'package:elinkbook/theme/app_theme.dart';

import '../support/fake_bookmarks_repository.dart';
import '../support/fake_highlights_repository.dart';
import '../support/fake_notes_repository.dart';
import '../support/fake_custom_fonts_repository.dart';
import '../support/fake_book_import_service.dart';
import '../support/fake_book_reader_prefs_repository.dart';
import '../support/fake_cloud_account_repository.dart';
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_remote_server_repository.dart';
import '../support/fake_opds_client.dart';
import '../support/fake_remote_thumbnail_cache.dart';
import '../support/fake_reading_stats_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('LibraryReaderFeatureRepositories 原樣持有六個注入的依賴，未提供時預設皆為 null', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    final bookmarksRepository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    final customFontsRepository = FakeCustomFontsRepository();
    final layoutPresetRepository = LayoutPresetRepository(db);
    final bookReaderPrefsRepository = FakeBookReaderPrefsRepository();

    const empty = LibraryReaderFeatureRepositories();
    expect(empty.bookmarksRepository, isNull);
    expect(empty.highlightsRepository, isNull);
    expect(empty.notesRepository, isNull);
    expect(empty.customFontsRepository, isNull);
    expect(empty.layoutPresetRepository, isNull);
    expect(empty.bookReaderPrefsRepository, isNull);

    final dependencies = LibraryReaderFeatureRepositories(
      bookmarksRepository: bookmarksRepository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
      customFontsRepository: customFontsRepository,
      layoutPresetRepository: layoutPresetRepository,
      bookReaderPrefsRepository: bookReaderPrefsRepository,
    );
    expect(dependencies.bookmarksRepository, same(bookmarksRepository));
    expect(dependencies.highlightsRepository, same(highlightsRepository));
    expect(dependencies.notesRepository, same(notesRepository));
    expect(dependencies.customFontsRepository, same(customFontsRepository));
    expect(dependencies.layoutPresetRepository, same(layoutPresetRepository));
    expect(dependencies.bookReaderPrefsRepository, same(bookReaderPrefsRepository));
  });

  test('LibraryReaderFeatureRepositories.readingStatsRepository 預設為 null，'
      '傳入時原樣持有同一個實例（epic-9-stats Issue 4）', () {
    const empty = LibraryReaderFeatureRepositories();
    expect(empty.readingStatsRepository, isNull);

    final statsRepository = FakeReadingStatsRepository();
    final dependencies = LibraryReaderFeatureRepositories(
        readingStatsRepository: statsRepository);
    expect(dependencies.readingStatsRepository, same(statsRepository));
  });

  test('LibraryReaderFeatureRepositories.bookImportService 預設為 null，'
      '傳入時原樣持有同一個實例（epic-15-storage-permission Issue 0）', () {
    const empty = LibraryReaderFeatureRepositories();
    expect(empty.bookImportService, isNull);

    final importService = FakeBookImportService();
    final dependencies =
        LibraryReaderFeatureRepositories(bookImportService: importService);
    expect(dependencies.bookImportService, same(importService));
  });

  test('LibrarySyncDependencies 原樣持有三個注入的依賴，未提供時預設皆為 null', () {
    final syncAccountRepository = SyncAccountRepository();
    final syncClient = SyncClient(accountRepository: syncAccountRepository);
    final syncCheckpointTrigger = SyncCheckpointTrigger(
      isLoggedIn: () async => false,
      runCheckpoint: () async {},
    );

    const empty = LibrarySyncDependencies();
    expect(empty.syncAccountRepository, isNull);
    expect(empty.syncClient, isNull);
    expect(empty.syncCheckpointTrigger, isNull);

    final dependencies = LibrarySyncDependencies(
      syncAccountRepository: syncAccountRepository,
      syncClient: syncClient,
      syncCheckpointTrigger: syncCheckpointTrigger,
    );
    expect(dependencies.syncAccountRepository, same(syncAccountRepository));
    expect(dependencies.syncClient, same(syncClient));
    expect(dependencies.syncCheckpointTrigger, same(syncCheckpointTrigger));
  });

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
