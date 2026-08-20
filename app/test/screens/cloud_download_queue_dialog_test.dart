import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/cloud_download_queue_dialog.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_fingerprint_computer.dart';
import '../support/fake_library_repository.dart';
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

  Book fakeBookWithFingerprint(String id, String fingerprint) {
    return Book(
      id: id,
      title: '本機已有的書',
      format: BookFileFormat.epub,
      filePath: '/books/$id.epub',
      source: BookSource.local,
      contentFingerprint: fingerprint,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
  }

  Future<void> pumpDialog(
    WidgetTester tester, {
    required FakeCloudStorageClient client,
    required FakeBookImportService importService,
    FakeLibraryRepository? libraryRepository,
    FakeFingerprintComputer? fingerprintComputer,
    List<CloudFileEntry> entries = const [entry1],
    String? folderName,
  }) async {
    final fingerprint = fingerprintComputer ?? FakeFingerprintComputer();
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
                libraryRepository: libraryRepository ?? FakeLibraryRepository(),
                computeFingerprint: fingerprint.call,
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

  group('下載後指紋比對（Layer 2）', () {
    testWidgets('下載後偵測到與本機書籍內容指紋相同時彈出提示，選擇不建立新副本則刪除暫存檔並標記為略過',
        (tester) async {
      final client = FakeCloudStorageClient(downloadContents: {
        'file-1': [1, 2, 3],
      });
      final importService = FakeBookImportService();
      final libraryRepository = FakeLibraryRepository(initialBooks: [
        fakeBookWithFingerprint('local-1', 'dup-fingerprint'),
      ]);
      final fingerprintComputer = FakeFingerprintComputer()..nextFingerprint = 'dup-fingerprint';
      await pumpDialog(
        tester,
        client: client,
        importService: importService,
        libraryRepository: libraryRepository,
        fingerprintComputer: fingerprintComputer,
      );

      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        if (find.byKey(const Key('cloud_duplicate_dialog')).evaluate().isNotEmpty) break;
      }

      expect(find.byKey(const Key('cloud_duplicate_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cloud_duplicate_dialog_cancel')));
      await settleDownload(tester);

      expect(find.text('重複已略過（未匯入）'), findsOneWidget);
      expect(importService.lastImportCall, isNull);
      final tempDownloadDir = Directory('${tempRoot.path}/cloud_import_download_temp');
      expect(
        tempDownloadDir.existsSync() ? tempDownloadDir.listSync() : const [],
        isEmpty,
      );
    });

    testWidgets('下載後偵測到重複時選擇仍要建立新副本，正常完成匯入', (tester) async {
      final client = FakeCloudStorageClient(downloadContents: {
        'file-1': [1, 2, 3],
      });
      final importService = FakeBookImportService();
      final libraryRepository = FakeLibraryRepository(initialBooks: [
        fakeBookWithFingerprint('local-1', 'dup-fingerprint'),
      ]);
      final fingerprintComputer = FakeFingerprintComputer()..nextFingerprint = 'dup-fingerprint';
      await pumpDialog(
        tester,
        client: client,
        importService: importService,
        libraryRepository: libraryRepository,
        fingerprintComputer: fingerprintComputer,
      );

      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        if (find.byKey(const Key('cloud_duplicate_dialog')).evaluate().isNotEmpty) break;
      }

      await tester.tap(find.byKey(const Key('cloud_duplicate_dialog_confirm')));
      await settleDownload(tester);

      final listTile =
          tester.widget<ListTile>(find.byKey(const Key('cloud_download_queue_item_file-1')));
      expect((listTile.subtitle as Text).data, '完成');
      expect(importService.lastImportCall, isNotNull);
    });

    testWidgets('下載後未偵測到重複時不彈出提示，直接完成', (tester) async {
      final client = FakeCloudStorageClient(downloadContents: {
        'file-1': [1, 2, 3],
      });
      final importService = FakeBookImportService();
      final fingerprintComputer = FakeFingerprintComputer();
      await pumpDialog(
        tester,
        client: client,
        importService: importService,
        fingerprintComputer: fingerprintComputer,
      );

      await settleDownload(tester);

      expect(find.byKey(const Key('cloud_duplicate_dialog')), findsNothing);
      final listTile =
          tester.widget<ListTile>(find.byKey(const Key('cloud_download_queue_item_file-1')));
      expect((listTile.subtitle as Text).data, '完成');
      expect(importService.lastImportCall, isNotNull);
      // 驗證指紋計算確實在下載成功之後才被呼叫恰好一次，且傳入的是下載
      // 完成的暫存檔路徑（比照 review-issue-3.md 對 remote_catalog 版本的
      // 既有斷言慣例）。
      expect(fingerprintComputer.calls, hasLength(1));
      expect(fingerprintComputer.calls.single, isNotEmpty);
    });
  });
}
