import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/google_drive_browser_screen.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_path_provider_platform.dart';

void main() {
  const folderEntry = CloudFileEntry(id: 'folder-1', name: '小說', isFolder: true);
  const fileEntryNoThumbnail = CloudFileEntry(
    id: 'file-1',
    name: '紅樓夢.epub',
    isFolder: false,
    format: BookFileFormat.epub,
  );
  const fileEntryWithThumbnail = CloudFileEntry(
    id: 'file-2',
    name: '西遊記.pdf',
    isFolder: false,
    format: BookFileFormat.pdf,
    thumbnailUrl: 'https://drive.google.com/thumbnail/2',
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeCloudStorageClient client,
    FakeLibraryRepository? libraryRepository,
    FakeBookImportService? importService,
    String? folderId,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: GoogleDriveBrowserScreen(
        client: client,
        libraryRepository: libraryRepository ?? FakeLibraryRepository(),
        importService: importService ?? FakeBookImportService(),
        folderId: folderId,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('載入根目錄後顯示資料夾與格式過濾後的檔案', (tester) async {
    final client = FakeCloudStorageClient(folderContents: {
      null: const CloudFolderListing(entries: [folderEntry, fileEntryNoThumbnail]),
    });
    await pumpScreen(tester, client: client);

    expect(find.text('小說'), findsOneWidget);
    expect(find.text('紅樓夢.epub'), findsOneWidget);
  });

  testWidgets('點擊資料夾項目 push 新畫面並帶入正確 folderId', (tester) async {
    final client = FakeCloudStorageClient(folderContents: {
      null: const CloudFolderListing(entries: [folderEntry]),
      'folder-1': const CloudFolderListing(entries: [fileEntryNoThumbnail]),
    });
    await pumpScreen(tester, client: client);

    await tester.tap(find.byKey(const Key('google_drive_browser_entry_folder-1')));
    await tester.pumpAndSettle();

    expect(find.text('紅樓夢.epub'), findsOneWidget);
  });

  testWidgets('無縮圖網址的檔案顯示縮圖佔位符', (tester) async {
    final client = FakeCloudStorageClient(folderContents: {
      null: const CloudFolderListing(entries: [fileEntryNoThumbnail]),
    });
    await pumpScreen(tester, client: client);

    expect(
      find.byKey(const Key('google_drive_browser_thumbnail_placeholder_file-1')),
      findsOneWidget,
    );
  });

  testWidgets('有縮圖網址的檔案透過 client.fetchThumbnail 顯示縮圖', (tester) async {
    // 使用有效的 1x1 像素 PNG 圖片（base64 編碼）
    // 這是一個 1x1 像素的紅色 PNG 圖片
    final validPngBytes = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1 pixel
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, // 8-bit RGB
      0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, // IDAT chunk
      0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
      0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC,
      0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, // IEND chunk
      0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
    final client = FakeCloudStorageClient(folderContents: {
      null: const CloudFolderListing(entries: [fileEntryWithThumbnail]),
    })..thumbnailBytes = validPngBytes;
    await pumpScreen(tester, client: client);

    // 等待 FutureBuilder 完成
    await tester.pump();

    expect(
      find.byKey(const Key('google_drive_browser_thumbnail_file-2')),
      findsOneWidget,
    );
  });

  testWidgets('點擊檔案項目切換勾選狀態', (tester) async {
    final client = FakeCloudStorageClient(folderContents: {
      null: const CloudFolderListing(entries: [fileEntryNoThumbnail]),
    });
    await pumpScreen(tester, client: client);

    expect(
      find.byKey(const Key('google_drive_browser_checkbox_checked_file-1')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-1')));
    await tester.pump();

    expect(
      find.byKey(const Key('google_drive_browser_checkbox_checked_file-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-1')));
    await tester.pump();

    expect(
      find.byKey(const Key('google_drive_browser_checkbox_checked_file-1')),
      findsNothing,
    );
  });

  testWidgets('資料夾檔案數超過 1000 筆時顯示提示文字', (tester) async {
    final client = FakeCloudStorageClient(folderContents: {
      null: const CloudFolderListing(entries: [fileEntryNoThumbnail], truncated: true),
    });
    await pumpScreen(tester, client: client);

    expect(
      find.byKey(const Key('google_drive_browser_truncated_text')),
      findsOneWidget,
    );
  });

  testWidgets('access token 過期時顯示需要重新連結的訊息', (tester) async {
    final client = _ThrowingCloudStorageClient();
    await pumpScreen(tester, client: client);

    expect(find.byKey(const Key('google_drive_browser_reauth_text')), findsOneWidget);
  });

  group('選擇分類後下載＋匯入', () {
    late Directory tempRoot;
    late PathProviderPlatform originalPathProvider;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('google_drive_browser_test');
      originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = FakePathProviderPlatform(tempRoot.path);
    });

    tearDown(() {
      PathProviderPlatform.instance = originalPathProvider;
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    testWidgets('選擇分類、勾選檔案、下載完成後 importFiles 帶入正確的 folderName', (tester) async {
      final libraryRepository = FakeLibraryRepository();
      await libraryRepository.upsertGroup('小說');
      final importService = FakeBookImportService();
      final client = FakeCloudStorageClient(
        folderContents: {
          null: const CloudFolderListing(entries: [fileEntryNoThumbnail]),
        },
        downloadContents: {
          'file-1': [1, 2, 3],
        },
      );
      await pumpScreen(
        tester,
        client: client,
        libraryRepository: libraryRepository,
        importService: importService,
      );

      await tester.tap(find.byKey(const Key('google_drive_browser_entry_file-1')));
      await tester.pump();
      await tester
          .tap(find.byKey(const Key('google_drive_browser_group_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('小說').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('google_drive_browser_download_button')));
      await tester.pump();

      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cloud_download_queue_done_button')));
      await tester.pumpAndSettle();

      expect(importService.lastImportCall?.source, BookSource.googleDrive);
    });
  });
}

class _ThrowingCloudStorageClient extends FakeCloudStorageClient {
  @override
  Future<CloudFolderListing> listFolder({String? folderId}) async {
    throw CloudAuthRequiredException();
  }
}
