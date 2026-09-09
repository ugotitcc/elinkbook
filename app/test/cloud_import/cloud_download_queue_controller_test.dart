import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/cloud_import/cloud_download_queue_controller.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_fingerprint_computer.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_path_provider_platform.dart';

/// 視覺還原（Visual Accuracy Mode，`docs/research/uiux/VISUAL_ANALYSIS.md`）：
/// 下載迴圈本身已從 `CloudDownloadQueueDialog`（已刪除）搬到這個純 Dart
/// `ChangeNotifier`，這份測試取代原本 `cloud_download_queue_dialog_test.dart`
/// 的涵蓋範圍，改為直接測控制器、不需要 pump 任何 widget。
void main() {
  late Directory tempRoot;
  late PathProviderPlatform originalPathProvider;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync(
      'cloud_download_queue_controller_test',
    );
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
  const entry2 = CloudFileEntry(
    id: 'file-2',
    name: '西遊記.epub',
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

  CloudDownloadQueueController buildController({
    Future<bool> Function(String message)? onDuplicateConfirm,
  }) {
    return CloudDownloadQueueController(
      onDuplicateConfirm: onDuplicateConfirm ?? (_) async => false,
    );
  }

  /// 佇列處理是非同步跑在背景（`enqueue()` 不 await），測試需要輪詢直到
  /// 條件成立或逾時，比照原本 dialog 測試的 `settleDownload()` 既有慣例。
  Future<void> waitUntil(
    bool Function() condition, {
    int maxAttempts = 40,
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('下載成功後標記完成，importFiles 正確帶入 source/cloudFileIds/folderName', () async {
    final client = FakeCloudStorageClient(
      downloadContents: {
        'file-1': [1, 2, 3],
      },
    );
    final importService = FakeBookImportService();
    final controller = buildController();

    controller.enqueue(
      entries: const [entry1],
      client: client,
      importService: importService,
      libraryRepository: FakeLibraryRepository(),
      computeFingerprint: FakeFingerprintComputer().call,
      source: BookSource.googleDrive,
      folderName: '小說',
    );

    await waitUntil(
      () => controller.items.single.status == CloudDownloadItemStatus.done,
    );

    expect(controller.items.single.status, CloudDownloadItemStatus.done);
    expect(controller.items.single.progress, 1.0);
    expect(importService.lastImportCall?.source, BookSource.googleDrive);
    expect(importService.lastImportCall?.cloudFileIds, {
      importService.lastImportCall!.uris.single: 'file-1',
    });
  });

  test('下載失敗顯示失敗狀態，可手動重試', () async {
    // 初始時 downloadContents 為空，下載會失敗。
    final client = FakeCloudStorageClient(downloadContents: {});
    final importService = FakeBookImportService();
    final controller = buildController();

    controller.enqueue(
      entries: const [entry1],
      client: client,
      importService: importService,
      libraryRepository: FakeLibraryRepository(),
      computeFingerprint: FakeFingerprintComputer().call,
      source: BookSource.googleDrive,
    );

    await waitUntil(
      () => controller.items.single.status == CloudDownloadItemStatus.failed,
    );
    expect(controller.items.single.status, CloudDownloadItemStatus.failed);

    // 補上這次會成功的下載內容再重試。
    client.downloadContents['file-1'] = [1, 2, 3];
    await controller.retry('file-1');

    expect(controller.items.single.status, CloudDownloadItemStatus.done);
    expect(importService.lastImportCall, isNotNull);
  });

  test('下載中呼叫 cancel 後顯示已取消狀態，暫存檔不殘留', () async {
    final client = FakeCloudStorageClient(
      downloadContents: {
        'file-1': [1, 2, 3],
      },
    );
    client.pendingDownloadCompleter = Completer<void>();
    final controller = buildController();

    controller.enqueue(
      entries: const [entry1],
      client: client,
      importService: FakeBookImportService(),
      libraryRepository: FakeLibraryRepository(),
      computeFingerprint: FakeFingerprintComputer().call,
      source: BookSource.googleDrive,
    );

    await waitUntil(
      () =>
          controller.items.single.status == CloudDownloadItemStatus.downloading,
    );
    controller.cancel('file-1');
    client.pendingDownloadCompleter!.complete();

    await waitUntil(
      () => controller.items.single.status == CloudDownloadItemStatus.cancelled,
    );

    expect(controller.items.single.status, CloudDownloadItemStatus.cancelled);
    final tempDownloadDir = Directory(
      '${tempRoot.path}/cloud_import_download_temp',
    );
    expect(
      tempDownloadDir.existsSync() ? tempDownloadDir.listSync() : const [],
      isEmpty,
    );
  });

  group('下載後指紋比對（Layer 2）', () {
    test('偵測到與本機書籍內容指紋相同時詢問是否仍要建立，選擇否則標記略過並清除暫存檔', () async {
      final client = FakeCloudStorageClient(
        downloadContents: {
          'file-1': [1, 2, 3],
        },
      );
      final importService = FakeBookImportService();
      final libraryRepository = FakeLibraryRepository(
        initialBooks: [fakeBookWithFingerprint('local-1', 'dup-fingerprint')],
      );
      final fingerprintComputer = FakeFingerprintComputer()
        ..nextFingerprint = 'dup-fingerprint';
      var confirmCalls = 0;
      final controller = buildController(
        onDuplicateConfirm: (message) async {
          confirmCalls++;
          expect(message, contains('紅樓夢.epub'));
          return false;
        },
      );

      controller.enqueue(
        entries: const [entry1],
        client: client,
        importService: importService,
        libraryRepository: libraryRepository,
        computeFingerprint: fingerprintComputer.call,
        source: BookSource.googleDrive,
      );

      await waitUntil(
        () =>
            controller.items.single.status ==
            CloudDownloadItemStatus.duplicateSkipped,
      );

      expect(confirmCalls, 1);
      expect(importService.lastImportCall, isNull);
      final tempDownloadDir = Directory(
        '${tempRoot.path}/cloud_import_download_temp',
      );
      expect(
        tempDownloadDir.existsSync() ? tempDownloadDir.listSync() : const [],
        isEmpty,
      );
    });

    test('偵測到重複時選擇仍要建立新副本，正常完成匯入', () async {
      final client = FakeCloudStorageClient(
        downloadContents: {
          'file-1': [1, 2, 3],
        },
      );
      final importService = FakeBookImportService();
      final libraryRepository = FakeLibraryRepository(
        initialBooks: [fakeBookWithFingerprint('local-1', 'dup-fingerprint')],
      );
      final fingerprintComputer = FakeFingerprintComputer()
        ..nextFingerprint = 'dup-fingerprint';
      final controller = buildController(onDuplicateConfirm: (_) async => true);

      controller.enqueue(
        entries: const [entry1],
        client: client,
        importService: importService,
        libraryRepository: libraryRepository,
        computeFingerprint: fingerprintComputer.call,
        source: BookSource.googleDrive,
      );

      await waitUntil(
        () => controller.items.single.status == CloudDownloadItemStatus.done,
      );

      expect(importService.lastImportCall, isNotNull);
    });

    test('未偵測到重複時不詢問，直接完成，指紋只計算一次', () async {
      final client = FakeCloudStorageClient(
        downloadContents: {
          'file-1': [1, 2, 3],
        },
      );
      final importService = FakeBookImportService();
      final fingerprintComputer = FakeFingerprintComputer();
      var confirmCalls = 0;
      final controller = buildController(
        onDuplicateConfirm: (_) async {
          confirmCalls++;
          return false;
        },
      );

      controller.enqueue(
        entries: const [entry1],
        client: client,
        importService: importService,
        libraryRepository: FakeLibraryRepository(),
        computeFingerprint: fingerprintComputer.call,
        source: BookSource.googleDrive,
      );

      await waitUntil(
        () => controller.items.single.status == CloudDownloadItemStatus.done,
      );

      expect(confirmCalls, 0);
      expect(importService.lastImportCall, isNotNull);
      expect(fingerprintComputer.calls, hasLength(1));
    });
  });

  test('依序處理，不平行下載：第二筆在第一筆完成前維持 pending', () async {
    final client = FakeCloudStorageClient(
      downloadContents: {
        'file-1': [1, 2, 3],
        'file-2': [4, 5, 6],
      },
    );
    client.pendingDownloadCompleter = Completer<void>();
    final controller = buildController();

    controller.enqueue(
      entries: const [entry1, entry2],
      client: client,
      importService: FakeBookImportService(),
      libraryRepository: FakeLibraryRepository(),
      computeFingerprint: FakeFingerprintComputer().call,
      source: BookSource.googleDrive,
    );

    await waitUntil(
      () =>
          controller.items.first.status == CloudDownloadItemStatus.downloading,
    );

    expect(controller.items.first.status, CloudDownloadItemStatus.downloading);
    expect(controller.items.last.status, CloudDownloadItemStatus.pending);

    client.pendingDownloadCompleter!.complete();
    await waitUntil(
      () => controller.items.last.status == CloudDownloadItemStatus.done,
    );
    expect(controller.items.first.status, CloudDownloadItemStatus.done);
    expect(controller.items.last.status, CloudDownloadItemStatus.done);
  });

  test('dismiss 從清單移除項目', () async {
    final client = FakeCloudStorageClient(
      downloadContents: {
        'file-1': [1, 2, 3],
      },
    );
    final controller = buildController();

    controller.enqueue(
      entries: const [entry1],
      client: client,
      importService: FakeBookImportService(),
      libraryRepository: FakeLibraryRepository(),
      computeFingerprint: FakeFingerprintComputer().call,
      source: BookSource.googleDrive,
    );
    await waitUntil(
      () => controller.items.single.status == CloudDownloadItemStatus.done,
    );

    controller.dismiss('file-1');

    expect(controller.items, isEmpty);
  });

  test('enqueue 會呼叫 notifyListeners，畫面可依此重繪', () async {
    final client = FakeCloudStorageClient(
      downloadContents: {
        'file-1': [1, 2, 3],
      },
    );
    final controller = buildController();
    var notifyCount = 0;
    controller.addListener(() => notifyCount++);

    controller.enqueue(
      entries: const [entry1],
      client: client,
      importService: FakeBookImportService(),
      libraryRepository: FakeLibraryRepository(),
      computeFingerprint: FakeFingerprintComputer().call,
      source: BookSource.googleDrive,
    );

    expect(notifyCount, greaterThan(0));
    await waitUntil(
      () => controller.items.single.status == CloudDownloadItemStatus.done,
    );
    expect(notifyCount, greaterThan(1));
  });
}
