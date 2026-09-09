import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/downloads/download_queue_controller.dart';
import 'package:elinkbook/cloud_import/cloud_download_job.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/cloud_browser_screen.dart';
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/screens/remote_server_list_screen.dart';
import 'package:elinkbook/screens/sources_home_screen.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_fingerprint_computer.dart';
import '../support/fake_remote_server_repository.dart';
import '../support/fake_opds_client.dart';
import '../support/fake_remote_thumbnail_cache.dart';

void main() {
  const filePickerChannel = MethodChannel(
    'miguelruivo.flutter.plugins.filepicker',
  );
  const folderPickerChannel = MethodChannel('elinkbook/folder_picker');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(folderPickerChannel, null);
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
        home: SourcesHomeScreen(
          repository: FakeLibraryRepository(),
          importService: importService,
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
        home: SourcesHomeScreen(
          repository: FakeLibraryRepository(),
          importService: importService,
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

  testWidgets('雲端/OPDS 依賴缺席時對應項目為停用狀態', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SourcesHomeScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final googleDriveTile = tester.widget<ListTile>(
      find.byKey(const Key('sources_google_drive_tile')),
    );
    expect(googleDriveTile.enabled, isFalse);
    final oneDriveTile = tester.widget<ListTile>(
      find.byKey(const Key('sources_onedrive_tile')),
    );
    expect(oneDriveTile.enabled, isFalse);
    final remoteTile = tester.widget<ListTile>(
      find.byKey(const Key('sources_remote_library_tile')),
    );
    expect(remoteTile.enabled, isFalse);
  });

  testWidgets('依賴齊全時點擊 Google Drive 項目導覽至 CloudBrowserScreen', (tester) async {
    final fingerprintComputer = FakeFingerprintComputer();
    await tester.pumpWidget(
      MaterialApp(
        home: SourcesHomeScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          cloudAccountDependencies: LibraryCloudAccountDependencies(
            googleDriveStorageClient: FakeCloudStorageClient(),
          ),
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

  testWidgets('依賴齊全時點擊 OneDrive 項目導覽至 CloudBrowserScreen', (tester) async {
    final fingerprintComputer = FakeFingerprintComputer();
    await tester.pumpWidget(
      MaterialApp(
        home: SourcesHomeScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          cloudAccountDependencies: LibraryCloudAccountDependencies(
            oneDriveStorageClient: FakeCloudStorageClient(),
          ),
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

  testWidgets('依賴齊全時點擊遠端書庫項目導覽至 RemoteServerListScreen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SourcesHomeScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          remoteLibraryDependencies: LibraryRemoteLibraryDependencies(
            remoteServerRepository: FakeRemoteServerRepository(),
            createOpdsClient: () => FakeOpdsClient(),
            thumbnailCache: FakeRemoteThumbnailCache(),
          ),
          computeFingerprint: FakeFingerprintComputer().call,
          downloadQueueController: DownloadQueueController(
            onDuplicateConfirm: (_) async => false,
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
        home: SourcesHomeScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
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
    testWidgets('downloadQueueController 為 null 時，即使其餘雲端相依齊全，'
        'Google Drive／OneDrive 項目仍維持停用（下載已無法運作）', (tester) async {
      final fingerprintComputer = FakeFingerprintComputer();
      await tester.pumpWidget(
        MaterialApp(
          home: SourcesHomeScreen(
            repository: FakeLibraryRepository(),
            importService: FakeBookImportService(),
            cloudAccountDependencies: LibraryCloudAccountDependencies(
              googleDriveStorageClient: FakeCloudStorageClient(),
              oneDriveStorageClient: FakeCloudStorageClient(),
            ),
            computeFingerprint: fingerprintComputer.call,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sources_google_drive_tile')));
      await tester.pumpAndSettle();
      expect(find.byType(CloudBrowserScreen), findsNothing);

      await tester.tap(find.byKey(const Key('sources_onedrive_tile')));
      await tester.pumpAndSettle();
      expect(find.byType(CloudBrowserScreen), findsNothing);
    });

    testWidgets('downloadQueueController 沒有項目時不顯示下載佇列區塊', (tester) async {
      final controller = DownloadQueueController(
        onDuplicateConfirm: (_) async => false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SourcesHomeScreen(
            repository: FakeLibraryRepository(),
            importService: FakeBookImportService(),
            downloadQueueController: controller,
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
          home: SourcesHomeScreen(
            repository: FakeLibraryRepository(),
            importService: FakeBookImportService(),
            downloadQueueController: controller,
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
}
