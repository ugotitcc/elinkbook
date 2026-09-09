import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/downloads/download_queue_controller.dart';

/// [QueuedDownloadJob] 的最小可控假實作，讓
/// [DownloadQueueController] 的通用排程／重複偵測／失敗／取消邏輯可以
/// 脫離 Cloud／OPDS 兩個具體 Provider（`CloudDownloadJob`／
/// `RemoteDownloadJob`）獨立驗證——那兩個實作本身的欄位對應正確性已由
/// `cloud_browser_screen_test.dart`／`remote_catalog_screen_test.dart`
/// 的整合測試涵蓋，這裡只驗證共用控制器本身的排程/狀態機邏輯。
class FakeQueuedDownloadJob implements QueuedDownloadJob {
  FakeQueuedDownloadJob({
    required this.id,
    this.name = '假書',
    this.tempPath = '/tmp/fake-download.epub',
    this.permanentPath = '/perm/fake-download.epub',
    this.fingerprint = 'fingerprint',
    this.hasDuplicateResult = false,
    this.downloadError,
    this.pendingCompleter,
  });

  @override
  final String id;
  @override
  final String name;
  final String tempPath;
  final String permanentPath;
  final String fingerprint;
  final bool hasDuplicateResult;

  /// 非 final：部分測試需要模擬「第一次下載失敗、重試後成功」。
  Object? downloadError;
  final Completer<void>? pendingCompleter;

  bool _cancelled = false;
  int downloadCalls = 0;
  int computeFingerprintCalls = 0;
  int hasDuplicateCalls = 0;
  int promoteCalls = 0;
  int importCalls = 0;
  String? lastImportedPath;

  @override
  Future<String> download({
    required void Function(int received, int total) onProgress,
  }) async {
    downloadCalls++;
    if (pendingCompleter != null) await pendingCompleter!.future;
    if (_cancelled) throw StateError('已取消');
    if (downloadError != null) throw downloadError!;
    onProgress(1, 1);
    return tempPath;
  }

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isCancelled => _cancelled;

  @override
  Future<String> computeFingerprint(String tempPath) async {
    computeFingerprintCalls++;
    return fingerprint;
  }

  @override
  Future<bool> hasDuplicate(String fingerprint) async {
    hasDuplicateCalls++;
    return hasDuplicateResult;
  }

  @override
  Future<String> promote(String tempPath) async {
    promoteCalls++;
    return permanentPath;
  }

  @override
  Future<void> import(String permanentPath) async {
    importCalls++;
    lastImportedPath = permanentPath;
  }
}

void main() {
  test('enqueueJobs 後工作完成，狀態變為 done 並呼叫 import', () async {
    final controller = DownloadQueueController(
      onDuplicateConfirm: (_) async => false,
    );
    final job = FakeQueuedDownloadJob(id: 'book-1');

    controller.enqueueJobs([job]);
    await pumpEventQueue();

    expect(controller.items.single.status, DownloadItemStatus.done);
    expect(job.downloadCalls, 1);
    expect(job.hasDuplicateCalls, 1);
    expect(job.promoteCalls, 1);
    expect(job.importCalls, 1);
    expect(job.lastImportedPath, job.permanentPath);
  });

  test('多筆工作依序處理，非平行（第一筆未完成前第二筆不會開始下載）', () async {
    final controller = DownloadQueueController(
      onDuplicateConfirm: (_) async => false,
    );
    final completerA = Completer<void>();
    final jobA = FakeQueuedDownloadJob(id: 'book-a', pendingCompleter: completerA);
    final jobB = FakeQueuedDownloadJob(id: 'book-b');

    controller.enqueueJobs([jobA, jobB]);
    await pumpEventQueue();

    // jobA 卡在 completer 尚未 complete，jobB 應該還沒被呼叫到 download()。
    expect(jobA.downloadCalls, 1);
    expect(jobB.downloadCalls, 0);

    completerA.complete();
    await pumpEventQueue();

    expect(jobB.downloadCalls, 1);
    expect(controller.items.map((e) => e.status).toList(), [
      DownloadItemStatus.done,
      DownloadItemStatus.done,
    ]);
  });

  test('已存在的 id 再次 enqueue 時忽略，不重複加入', () async {
    final controller = DownloadQueueController(
      onDuplicateConfirm: (_) async => false,
    );
    final job = FakeQueuedDownloadJob(id: 'book-1');

    controller.enqueueJobs([job]);
    controller.enqueueJobs([FakeQueuedDownloadJob(id: 'book-1')]);
    await pumpEventQueue();

    expect(controller.items, hasLength(1));
  });

  test('偵測到重複且 onDuplicateConfirm 回傳 false 時，標記為略過且不呼叫 import', () async {
    final controller = DownloadQueueController(
      onDuplicateConfirm: (_) async => false,
    );
    final job = FakeQueuedDownloadJob(id: 'book-1', hasDuplicateResult: true);

    controller.enqueueJobs([job]);
    await pumpEventQueue();

    expect(controller.items.single.status, DownloadItemStatus.duplicateSkipped);
    expect(job.promoteCalls, 0);
    expect(job.importCalls, 0);
  });

  test('偵測到重複且 onDuplicateConfirm 回傳 true 時，仍正常 promote 並匯入', () async {
    final controller = DownloadQueueController(
      onDuplicateConfirm: (_) async => true,
    );
    final job = FakeQueuedDownloadJob(id: 'book-1', hasDuplicateResult: true);

    controller.enqueueJobs([job]);
    await pumpEventQueue();

    expect(controller.items.single.status, DownloadItemStatus.done);
    expect(job.promoteCalls, 1);
    expect(job.importCalls, 1);
  });

  test('download() 拋出例外時，狀態變為 failed', () async {
    final controller = DownloadQueueController(
      onDuplicateConfirm: (_) async => false,
    );
    final job = FakeQueuedDownloadJob(
      id: 'book-1',
      downloadError: StateError('模擬下載失敗'),
    );

    controller.enqueueJobs([job]);
    await pumpEventQueue();

    expect(controller.items.single.status, DownloadItemStatus.failed);
    expect(job.importCalls, 0);
  });

  test('cancel() 在下載進行中呼叫時，結束後狀態變為 cancelled（非 failed）', () async {
    final controller = DownloadQueueController(
      onDuplicateConfirm: (_) async => false,
    );
    final completer = Completer<void>();
    final job = FakeQueuedDownloadJob(id: 'book-1', pendingCompleter: completer);

    controller.enqueueJobs([job]);
    await pumpEventQueue();
    controller.cancel('book-1');
    completer.complete();
    await pumpEventQueue();

    expect(controller.items.single.status, DownloadItemStatus.cancelled);
  });

  test('retry() 可在失敗後重新觸發下載並成功完成', () async {
    final controller = DownloadQueueController(
      onDuplicateConfirm: (_) async => false,
    );
    final job = FakeQueuedDownloadJob(
      id: 'book-1',
      downloadError: StateError('模擬下載失敗'),
    );

    controller.enqueueJobs([job]);
    await pumpEventQueue();
    expect(controller.items.single.status, DownloadItemStatus.failed);

    job.downloadError = null;
    await controller.retry('book-1');

    expect(job.downloadCalls, 2);
    expect(controller.items.single.status, DownloadItemStatus.done);
  });

  test('dismiss() 移除項目', () async {
    final controller = DownloadQueueController(
      onDuplicateConfirm: (_) async => false,
    );
    final job = FakeQueuedDownloadJob(id: 'book-1');

    controller.enqueueJobs([job]);
    await pumpEventQueue();
    expect(controller.items, hasLength(1));

    controller.dismiss('book-1');
    expect(controller.items, isEmpty);
  });
}
