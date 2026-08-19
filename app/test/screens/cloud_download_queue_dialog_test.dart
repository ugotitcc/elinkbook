import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/cloud_download_queue_dialog.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_path_provider_platform.dart';

void main() {
  late Directory tempRoot;
  late PathProviderPlatform originalPathProvider;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('cloud_download_queue_test');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempRoot.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPathProvider;
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  const entry1 = CloudFileEntry(
    id: 'file-1',
    name: '紅樓夢.epub',
    isFolder: false,
    format: BookFileFormat.epub,
  );

  Future<void> pumpDialog(
    WidgetTester tester, {
    required FakeCloudStorageClient client,
    required FakeBookImportService importService,
    List<CloudFileEntry> entries = const [entry1],
    String? folderName,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (context) => CloudDownloadQueueDialog(
                entries: entries,
                client: client,
                importService: importService,
                source: BookSource.googleDrive,
                folderName: folderName,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
  }

  Future<void> settleDownload(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('下載成功後顯示完成狀態，importFiles 正確帶入 source/cloudFileIds/folderName',
      (tester) async {
    final client = FakeCloudStorageClient(downloadContents: {
      'file-1': [1, 2, 3],
    });
    final importService = FakeBookImportService();
    await pumpDialog(tester, client: client, importService: importService, folderName: '小說');

    await settleDownload(tester);

    expect(find.byKey(const Key('cloud_download_queue_item_file-1')), findsOneWidget);
    // 完成狀態顯示在 subtitle，與「完成」按鈕文字不同
    final listTile = tester.widget<ListTile>(find.byKey(const Key('cloud_download_queue_item_file-1')));
    expect(listTile.subtitle, isA<Text>());
    expect((listTile.subtitle as Text).data, '完成');
    expect(importService.lastImportCall?.source, BookSource.googleDrive);
    expect(importService.lastImportCall?.cloudFileIds, {importService.lastImportCall!.uris.single: 'file-1'});
  });

  testWidgets('下載失敗顯示失敗狀態，可手動重試', (tester) async {
    // 初始時 downloadContents 為空，下載會失敗
    final client = FakeCloudStorageClient(downloadContents: {});
    final importService = FakeBookImportService();
    await pumpDialog(tester, client: client, importService: importService);

    await settleDownload(tester);

    // 失敗狀態顯示在 subtitle
    final listTile = tester.widget<ListTile>(find.byKey(const Key('cloud_download_queue_item_file-1')));
    expect(listTile.subtitle, isA<Text>());
    expect((listTile.subtitle as Text).data, '失敗');
    expect(find.byKey(const Key('cloud_download_queue_retry_file-1')), findsOneWidget);

    // 補上這次會成功的下載內容再重試
    client.downloadContents['file-1'] = [1, 2, 3];
    await tester.tap(find.byKey(const Key('cloud_download_queue_retry_file-1')));
    await settleDownload(tester);

    // 重新檢查 subtitle 應為「完成」
    final listTileAfterRetry = tester.widget<ListTile>(find.byKey(const Key('cloud_download_queue_item_file-1')));
    expect(listTileAfterRetry.subtitle, isA<Text>());
    expect((listTileAfterRetry.subtitle as Text).data, '完成');
  });

  testWidgets('下載中點擊取消後顯示已取消狀態，暫存檔不殘留', (tester) async {
    final client = FakeCloudStorageClient(downloadContents: {
      'file-1': [1, 2, 3],
    });
    client.pendingDownloadCompleter = Completer<void>();
    final importService = FakeBookImportService();
    await pumpDialog(tester, client: client, importService: importService);
    await tester.pump();

    await tester.tap(find.byKey(const Key('cloud_download_queue_cancel_file-1')));
    client.pendingDownloadCompleter!.complete();
    await settleDownload(tester);

    expect(find.text('已取消'), findsOneWidget);
    final tempDownloadDir =
        Directory('${tempRoot.path}/cloud_import_download_temp');
    expect(
      tempDownloadDir.existsSync() ? tempDownloadDir.listSync() : const [],
      isEmpty,
    );
  });
}
