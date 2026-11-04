import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/cloud_import/cloud_download_job.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/downloads/download_queue_controller.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/book_update_models.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/cloud_browser_screen.dart';
import 'package:wakelock_plus/wakelock_plus.dart'
    show wakelockPlusPlatformInstance;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';
import 'package:elinkbook/screens/remote_server_list_screen.dart';
import 'package:elinkbook/screens/sources_home_screen.dart';
import 'package:elinkbook/screens/wifi_transfer_screen.dart';

import '../support/fake_wakelock_plus_platform.dart';
import '../support/fake_appearance_dependencies.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_fingerprint_computer.dart';
import '../support/fake_reader_feature_dependencies.dart';
import '../support/fake_remote_server_repository.dart';
import '../support/fake_opds_client.dart';
import '../support/fake_remote_thumbnail_cache.dart';
import '../support/fake_source_dependencies.dart';
import '../support/pump_localized_widget.dart';

void main() {
  const filePickerChannel = MethodChannel(
    'miguelruivo.flutter.plugins.filepicker',
  );
  const folderPickerChannel = MethodChannel('elinkbook/folder_picker');

  late FakeWakelockPlusPlatform fakeWakelock;
  late WakelockPlusPlatformInterface originalWakelockPlatform;

  setUp(() {
    fakeWakelock = FakeWakelockPlusPlatform();
    originalWakelockPlatform = wakelockPlusPlatformInstance;
    wakelockPlusPlatformInstance = fakeWakelock;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(folderPickerChannel, null);
    wakelockPlusPlatformInstance = originalWakelockPlatform;
  });

  testWidgets('點擊「選擇檔案」觸發 FilePicker 並匯入', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, (call) async {
          if (call.method == 'custom') {
            return [
              {
                'name': 'book.epub',
                'path': '/tmp/book.epub',
                'size': 100,
                'bytes': null,
                'identifier': 'content://example/book.epub',
              },
            ];
          }
          return null;
        });
    final importService = FakeBookImportService();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SourcesHomeScreen(
          appearance: fakeAppearanceDependencies(),
          readerFeatures: fakeReaderFeatureDependencies(
            bookImportService: importService,
          ),
          sources: fakeSourceDependencies(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sources_pick_files_button')));
    await tester.pumpAndSettle();

    expect(importService.lastImportCall, isNotNull);
    expect(importService.lastImportCall!.uris, ['content://example/book.epub']);
  });

  testWidgets('點擊「選擇資料夾」觸發 folderPickerChannel 並匯入', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(folderPickerChannel, (call) async {
          if (call.method == 'pickFolder') {
            return 'content://example/folder';
          }
          return null;
        });
    final importService = FakeBookImportService();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SourcesHomeScreen(
          appearance: fakeAppearanceDependencies(),
          readerFeatures: fakeReaderFeatureDependencies(
            bookImportService: importService,
          ),
          sources: fakeSourceDependencies(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sources_pick_folder_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_import_folder_confirm')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('library_import_folder_confirm')));
    await tester.pumpAndSettle();

    expect(importService.lastImportFolderUri, 'content://example/folder');
  });

  testWidgets('點擊 Google Drive 項目導覽至 CloudBrowserScreen', (tester) async {
    final fingerprintComputer = FakeFingerprintComputer();
    await pumpLocalizedWidget(
      tester,
      SourcesHomeScreen(
        appearance: fakeAppearanceDependencies(),
        readerFeatures: fakeReaderFeatureDependencies(
          bookImportService: FakeBookImportService(),
        ),
        sources: fakeSourceDependencies(
          googleDriveStorageClient: FakeCloudStorageClient(),
          computeFingerprint: fingerprintComputer.call,
          downloadQueueController: DownloadQueueController(
            onDuplicateConfirm: (_) async => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sources_google_drive_tile')));
    await tester.pumpAndSettle();

    expect(find.byType(CloudBrowserScreen), findsOneWidget);
  });

  testWidgets('點擊 OneDrive 項目導覽至 CloudBrowserScreen', (tester) async {
    final fingerprintComputer = FakeFingerprintComputer();
    await pumpLocalizedWidget(
      tester,
      SourcesHomeScreen(
        appearance: fakeAppearanceDependencies(),
        readerFeatures: fakeReaderFeatureDependencies(
          bookImportService: FakeBookImportService(),
        ),
        sources: fakeSourceDependencies(
          oneDriveStorageClient: FakeCloudStorageClient(),
          computeFingerprint: fingerprintComputer.call,
          downloadQueueController: DownloadQueueController(
            onDuplicateConfirm: (_) async => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sources_onedrive_tile')));
    await tester.pumpAndSettle();

    expect(find.byType(CloudBrowserScreen), findsOneWidget);
  });

  testWidgets('點擊遠端書庫項目導覽至 RemoteServerListScreen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SourcesHomeScreen(
          appearance: fakeAppearanceDependencies(),
          readerFeatures: fakeReaderFeatureDependencies(
            bookImportService: FakeBookImportService(),
          ),
          sources: fakeSourceDependencies(
            remoteServerRepository: FakeRemoteServerRepository(),
            createOpdsClient: () => FakeOpdsClient(),
            thumbnailCache: FakeRemoteThumbnailCache(),
            computeFingerprint: FakeFingerprintComputer().call,
            downloadQueueController: DownloadQueueController(
              onDuplicateConfirm: (_) async => false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sources_remote_library_tile')));
    await tester.pumpAndSettle();

    expect(find.byType(RemoteServerListScreen), findsOneWidget);
  });

  testWidgets('AppBar 書架/設定圖示呼叫對應 callback', (tester) async {
    var libraryTapped = 0;
    var settingsTapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SourcesHomeScreen(
          appearance: fakeAppearanceDependencies(),
          readerFeatures: fakeReaderFeatureDependencies(),
          sources: fakeSourceDependencies(),
          onNavigateToLibrary: () => libraryTapped++,
          onNavigateToSettings: () => settingsTapped++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sources_library_button')));
    await tester.tap(find.byKey(const Key('sources_settings_button')));

    expect(libraryTapped, 1);
    expect(settingsTapped, 1);
  });

  group('視覺還原（VISUAL_ANALYSIS.md）：常駐下載佇列', () {
    testWidgets('downloadQueueController 沒有項目時不顯示下載佇列區塊', (tester) async {
      final controller = DownloadQueueController(
        onDuplicateConfirm: (_) async => false,
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SourcesHomeScreen(
            appearance: fakeAppearanceDependencies(),
            readerFeatures: fakeReaderFeatureDependencies(),
            sources: fakeSourceDependencies(
              downloadQueueController: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('下載佇列'), findsNothing);
    });

    testWidgets('downloadQueueController 有項目時常駐顯示下載佇列區塊，'
        '狀態變化即時反映（不需要離開/重進畫面）', (tester) async {
      final controller = DownloadQueueController(
        onDuplicateConfirm: (_) async => false,
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SourcesHomeScreen(
            appearance: fakeAppearanceDependencies(),
            readerFeatures: fakeReaderFeatureDependencies(),
            sources: fakeSourceDependencies(
              downloadQueueController: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('下載佇列'), findsNothing);

      final client = FakeCloudStorageClient(
        downloadContents: {'file-1': const []},
      );
      controller.enqueueJobs([
        CloudDownloadJob(
          entry: const CloudFileEntry(
            id: 'file-1',
            name: '一弦定音.epub',
            isFolder: false,
            format: BookFileFormat.epub,
          ),
          client: client,
          importService: FakeBookImportService(),
          libraryRepository: FakeLibraryRepository(),
          computeFingerprintFn: FakeFingerprintComputer().call,
          source: BookSource.googleDrive,
        ),
      ]);
      await tester.pump();

      expect(find.text('下載佇列'), findsOneWidget);
      expect(
        find.byKey(const Key('sources_download_queue_item_file-1')),
        findsOneWidget,
      );
    });
  });

  testWidgets('點擊 WiFi 傳書入口導覽至 WifiTransferScreen', (tester) async {
    final fingerprintComputer = FakeFingerprintComputer();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SourcesHomeScreen(
          appearance: fakeAppearanceDependencies(),
          readerFeatures: fakeReaderFeatureDependencies(
            libraryRepository: FakeLibraryRepository(),
            bookImportService: FakeBookImportService(),
          ),
          sources: fakeSourceDependencies(
            computeFingerprint: fingerprintComputer.call,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sources_wifi_transfer_tile')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sources_wifi_transfer_tile')));
    await tester.pumpAndSettle();

    expect(find.byType(WifiTransferScreen), findsOneWidget);
  });

  testWidgets('開遠端書庫時，RemoteServerListScreen 拿到的是 SourceDependencies 內同一批物件', (
    tester,
  ) async {
    final sources = fakeSourceDependencies();
    await pumpLocalizedWidget(
      tester,
      SourcesHomeScreen(
        appearance: fakeAppearanceDependencies(),
        readerFeatures: fakeReaderFeatureDependencies(),
        sources: sources,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sources_remote_library_tile')));
    await tester.pumpAndSettle();

    final screen = tester.widget<RemoteServerListScreen>(
      find.byType(RemoteServerListScreen),
    );
    expect(screen.repository, same(sources.remoteServerRepository));
    expect(
      screen.dependencies.computeFingerprint,
      same(sources.computeFingerprint),
    );
    expect(screen.dependencies.thumbnailCache, same(sources.thumbnailCache));
    expect(
      screen.dependencies.createOpdsClient,
      same(sources.createOpdsClient),
    );
    expect(
      screen.downloadQueueController,
      same(sources.downloadQueueController),
    );
  });

  testWidgets(
    '開 WiFi 傳書時，WifiTransferScreen 的來源欄位取自 sources、書庫欄位取自 readerFeatures',
    (tester) async {
      final sources = fakeSourceDependencies();
      final readerFeatures = fakeReaderFeatureDependencies();
      await pumpLocalizedWidget(
        tester,
        SourcesHomeScreen(
          readerFeatures: readerFeatures,
          sources: sources,
          appearance: fakeAppearanceDependencies(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sources_wifi_transfer_tile')));
      await tester.pumpAndSettle();

      final screen = tester.widget<WifiTransferScreen>(
        find.byType(WifiTransferScreen),
      );
      expect(screen.computeFingerprint, same(sources.computeFingerprint));
      expect(
        screen.checkNetworkAvailability,
        same(sources.checkNetworkAvailability),
      );
      expect(screen.libraryRepository, same(readerFeatures.libraryRepository));
      expect(screen.importService, same(readerFeatures.bookImportService));
    },
  );

  testWidgets(
    '開 Google Drive 時，CloudBrowserScreen 拿到的是 SourceDependencies 內同一批物件',
    (tester) async {
      final sources = fakeSourceDependencies();
      final readerFeatures = fakeReaderFeatureDependencies();
      await pumpLocalizedWidget(
        tester,
        SourcesHomeScreen(
          readerFeatures: readerFeatures,
          sources: sources,
          appearance: fakeAppearanceDependencies(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sources_google_drive_tile')));
      await tester.pumpAndSettle();

      final screen = tester.widget<CloudBrowserScreen>(
        find.byType(CloudBrowserScreen),
      );
      expect(screen.client, same(sources.googleDriveStorageClient));
      expect(screen.computeFingerprint, same(sources.computeFingerprint));
      expect(
        screen.downloadQueueController,
        same(sources.downloadQueueController),
      );
      expect(
        screen.isMobileDataConnection,
        same(sources.isMobileDataConnection),
      );
      expect(screen.libraryRepository, same(readerFeatures.libraryRepository));
      expect(screen.importService, same(readerFeatures.bookImportService));
    },
  );

  testWidgets(
    '開 OneDrive 時，CloudBrowserScreen 拿到的是 SourceDependencies 內同一批物件',
    (tester) async {
      final sources = fakeSourceDependencies();
      final readerFeatures = fakeReaderFeatureDependencies();
      await pumpLocalizedWidget(
        tester,
        SourcesHomeScreen(
          readerFeatures: readerFeatures,
          sources: sources,
          appearance: fakeAppearanceDependencies(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sources_onedrive_tile')));
      await tester.pumpAndSettle();

      final screen = tester.widget<CloudBrowserScreen>(
        find.byType(CloudBrowserScreen),
      );
      expect(screen.client, same(sources.oneDriveStorageClient));
      expect(screen.computeFingerprint, same(sources.computeFingerprint));
      expect(
        screen.downloadQueueController,
        same(sources.downloadQueueController),
      );
      expect(
        screen.isMobileDataConnection,
        same(sources.isMobileDataConnection),
      );
      expect(screen.libraryRepository, same(readerFeatures.libraryRepository));
      expect(screen.importService, same(readerFeatures.bookImportService));
    },
  );

  testWidgets('英文介面下標題與各入口列文字正確顯示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SourcesHomeScreen(
          appearance: fakeAppearanceDependencies(),
          readerFeatures: fakeReaderFeatureDependencies(),
          sources: fakeSourceDependencies(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('Connected Services'), findsOneWidget);
    expect(find.text('Choose Files (multiple selection)'), findsOneWidget);
    expect(find.text('Choose Folder'), findsOneWidget);
    expect(find.text('Google Drive'), findsOneWidget);
    // 來源依賴 non-null：雲端／遠端 tile 恆啟用，不再顯示「未連結」副標。
    expect(
      find.text('Not linked yet. Please link your account in Settings.'),
      findsNothing,
    );
    expect(find.text('Remote Library (OPDS)'), findsOneWidget);
    expect(find.text('No remote library server configured yet'), findsNothing);
    expect(find.text('WiFi Book Transfer'), findsOneWidget);
    final googleDriveTile = tester.widget<ListTile>(
      find.byKey(const Key('sources_google_drive_tile')),
    );
    expect(googleDriveTile.enabled, isTrue);
    final oneDriveTile = tester.widget<ListTile>(
      find.byKey(const Key('sources_onedrive_tile')),
    );
    expect(oneDriveTile.enabled, isTrue);
    final remoteTile = tester.widget<ListTile>(
      find.byKey(const Key('sources_remote_library_tile')),
    );
    expect(remoteTile.enabled, isTrue);
  });

  group('本機匯入更新版候選整合（epic-67 Issue 2）', () {
    Book testBook(String id) {
      final now = DateTime(2026, 1, 1);
      return Book(
        id: id,
        title: '書 $id',
        format: BookFileFormat.epub,
        filePath: 'content://example/$id',
        source: BookSource.local,
        createTime: now,
        lastReadTime: now,
      );
    }

    testWidgets('選檔匯入含更新候選：出現清單，按套用後 replaceCalls 有一筆', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePickerChannel, (call) async {
            if (call.method == 'custom') {
              return [
                {
                  'name': 'book.epub',
                  'path': '/tmp/book.epub',
                  'size': 100,
                  'identifier': 'content://example/book.epub',
                },
              ];
            }
            return null;
          });

      final importService = FakeBookImportService();
      final candidate = BookUpdateCandidate(
        sourceUri: 'content://example/book.epub',
        displayName: 'book.epub',
        format: BookFileFormat.epub,
        confidence: UpdateConfidence.high,
        candidateBooks: [testBook('b1')],
      );
      importService.importFilesResult = ImportResult(
        importedBooks: const [],
        updateCandidates: [candidate],
      );
      importService.replaceResultsByBookId['b1'] = BookReplaceSuccess(testBook('b1'));

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SourcesHomeScreen(
            appearance: fakeAppearanceDependencies(),
            readerFeatures: fakeReaderFeatureDependencies(
              bookImportService: importService,
            ),
            sources: fakeSourceDependencies(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sources_pick_files_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('book_update_apply')), findsOneWidget);

      await tester.tap(find.byKey(const Key('book_update_apply')));
      await tester.pumpAndSettle();

      expect(importService.replaceCalls.length, 1);
      expect(find.text('已更新 1 本'), findsOneWidget);
    });

    testWidgets('純重複只顯示既有提示：無候選時只出現既有跳過 SnackBar，沒有更新版清單', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePickerChannel, (call) async {
            if (call.method == 'custom') {
              return [
                {
                  'name': 'dup.epub',
                  'path': '/tmp/dup.epub',
                  'size': 100,
                  'identifier': 'content://example/dup.epub',
                },
              ];
            }
            return null;
          });

      final importService = FakeBookImportService();
      importService.importFilesResult = const ImportResult(
        importedBooks: [],
        skippedDuplicateCount: 2,
        updateCandidates: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SourcesHomeScreen(
            appearance: fakeAppearanceDependencies(),
            readerFeatures: fakeReaderFeatureDependencies(
              bookImportService: importService,
            ),
            sources: fakeSourceDependencies(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sources_pick_files_button')));
      await tester.pumpAndSettle();

      expect(find.text('2 本已存在，已跳過'), findsOneWidget);
      expect(find.byKey(const Key('book_update_apply')), findsNothing);
    });

    testWidgets('提示與清單分開：同時有跳過重複與更新候選時，先見既有 SnackBar，清單照常彈出且不含跳過字樣', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePickerChannel, (call) async {
            if (call.method == 'custom') {
              return [
                {
                  'name': 'mix.epub',
                  'path': '/tmp/mix.epub',
                  'size': 100,
                  'identifier': 'content://example/mix.epub',
                },
              ];
            }
            return null;
          });

      final importService = FakeBookImportService();
      final candidate = BookUpdateCandidate(
        sourceUri: 'content://example/mix.epub',
        displayName: 'mix.epub',
        format: BookFileFormat.epub,
        confidence: UpdateConfidence.high,
        candidateBooks: [testBook('b1')],
      );
      importService.importFilesResult = ImportResult(
        importedBooks: const [],
        skippedDuplicateCount: 1,
        updateCandidates: [candidate],
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SourcesHomeScreen(
            appearance: fakeAppearanceDependencies(),
            readerFeatures: fakeReaderFeatureDependencies(
              bookImportService: importService,
            ),
            sources: fakeSourceDependencies(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sources_pick_files_button')));
      await tester.pumpAndSettle();

      expect(find.text('1 本已存在，已跳過'), findsOneWidget);
      expect(find.byKey(const Key('book_update_apply')), findsOneWidget);
      expect(find.widgetWithText(AlertDialog, '1 本已存在，已跳過'), findsNothing);
    });

    testWidgets('資料夾匯入同樣路徑：含更新候選時彈出清單', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(folderPickerChannel, (call) async {
            if (call.method == 'pickFolder') {
              return 'content://example/folder';
            }
            return null;
          });

      final importService = FakeBookImportService();
      final candidate = BookUpdateCandidate(
        sourceUri: 'content://example/folder_book.epub',
        displayName: 'folder_book.epub',
        format: BookFileFormat.epub,
        confidence: UpdateConfidence.high,
        candidateBooks: [testBook('b1')],
      );
      importService.importFolderResult = ImportResult(
        importedBooks: const [],
        updateCandidates: [candidate],
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SourcesHomeScreen(
            appearance: fakeAppearanceDependencies(),
            readerFeatures: fakeReaderFeatureDependencies(
              bookImportService: importService,
            ),
            sources: fakeSourceDependencies(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sources_pick_folder_button')));
      await tester.pumpAndSettle();

      // 確認自動分類對話框
      expect(find.byKey(const Key('library_import_folder_confirm')), findsOneWidget);
      await tester.tap(find.byKey(const Key('library_import_folder_confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('book_update_apply')), findsOneWidget);
    });
  });
}
