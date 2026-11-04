import 'dart:async';
import 'dart:io';

import 'package:elinkbook/downloads/download_queue_controller.dart';
import 'package:elinkbook/library/book_update_models.dart';
import 'package:elinkbook/library/book_update_settle.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:flutter_test/flutter_test.dart';

BookUpdateCandidate _makeTestCandidate(String id) {
  return BookUpdateCandidate(
    sourceUri: 'file:///tmp/download-$id.epub',
    format: BookFileFormat.epub,
    stagedPath: '/tmp/staging-$id.epub',
    confidence: UpdateConfidence.high,
    candidateBooks: [
      Book(
        id: 'target-$id',
        title: '目標書',
        format: BookFileFormat.epub,
        filePath: '/data/target.epub',
        source: BookSource.local,
        createTime: DateTime(2026, 1, 1),
        lastReadTime: DateTime(2026, 1, 1),
      ),
    ],
  );
}

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
    this.authFailurePredicate,
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

  /// 判斷哪些例外算「授權失效」；預設 null 代表一律不是。
  bool Function(Object error)? authFailurePredicate;

  @override
  bool isAuthFailure(Object error) => authFailurePredicate?.call(error) ?? false;

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
    callSequence.add('computeFingerprint');
    return fingerprint;
  }

  BookUpdateCandidate? detectResult;
  Object? detectThrows;
  int detectCalls = 0;
  final List<String> callSequence = [];

  @override
  Future<BookUpdateCandidate?> detectUpdate(String tempPath) async {
    detectCalls++;
    callSequence.add('detect');
    if (detectThrows != null) throw detectThrows!;
    return detectResult;
  }

  BookUpdateSettleResult settleResult =
      const BookUpdateSettleResult(BookUpdateSettleOutcome.replaced);
  Completer<BookUpdateSettleResult>? settleCompleter;
  final List<(BookUpdateCandidate, BookUpdateChoice)> settleCalls = [];

  @override
  Future<BookUpdateSettleResult> settleUpdate(
    BookUpdateCandidate candidate,
    BookUpdateChoice choice,
  ) async {
    settleCalls.add((candidate, choice));
    if (settleCompleter != null) return await settleCompleter!.future;
    return settleResult;
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
    await pumpEventQueue(times: 50);

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
    await pumpEventQueue(times: 50);

    // jobA 卡在 completer 尚未 complete，jobB 應該還沒被呼叫到 download()。
    expect(jobA.downloadCalls, 1);
    expect(jobB.downloadCalls, 0);

    completerA.complete();
    await pumpEventQueue(times: 50);

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
    await pumpEventQueue(times: 50);

    expect(controller.items, hasLength(1));
  });

  test('偵測到重複且 onDuplicateConfirm 回傳 false 時，標記為略過且不呼叫 import', () async {
    final controller = DownloadQueueController(
      onDuplicateConfirm: (_) async => false,
    );
    final job = FakeQueuedDownloadJob(id: 'book-1', hasDuplicateResult: true);

    controller.enqueueJobs([job]);
    await pumpEventQueue(times: 50);

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
    await pumpEventQueue(times: 50);

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
    await pumpEventQueue(times: 50);

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
    await pumpEventQueue(times: 50);
    controller.cancel('book-1');
    completer.complete();
    await pumpEventQueue(times: 50);

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
    await pumpEventQueue(times: 50);
    expect(controller.items.single.status, DownloadItemStatus.failed);

    job.downloadError = null;
    await controller.retry('book-1');

    expect(job.downloadCalls, 2);
    expect(controller.items.single.status, DownloadItemStatus.done);
  });

  group('授權失效標示（epic-54 Issue 2）', () {
    test('download() 拋出的例外被 isAuthFailure 判為真：failed 且 needsReauth', () async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final job = FakeQueuedDownloadJob(
        id: 'book-1',
        downloadError: StateError('auth'),
        authFailurePredicate: (e) => e is StateError,
      );

      controller.enqueueJobs([job]);
      await pumpEventQueue(times: 50);

      final item = controller.items.single;
      expect(item.status, DownloadItemStatus.failed);
      expect(item.needsReauth, isTrue);
    });

    test('isAuthFailure 為假的失敗（例如 OPDS 下載）：failed 但 needsReauth 為 false', () async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final job = FakeQueuedDownloadJob(id: 'book-1', downloadError: StateError('x'));

      controller.enqueueJobs([job]);
      await pumpEventQueue(times: 50);

      final item = controller.items.single;
      expect(item.status, DownloadItemStatus.failed);
      expect(item.needsReauth, isFalse);
    });

    test('已被使用者取消的工作：即使 isAuthFailure 為真，也是 cancelled 且 needsReauth 為 false', () async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final completer = Completer<void>();
      final job = FakeQueuedDownloadJob(
        id: 'book-1',
        pendingCompleter: completer,
        authFailurePredicate: (_) => true,
      );

      controller.enqueueJobs([job]);
      await pumpEventQueue(times: 50);
      controller.cancel('book-1');
      completer.complete();
      await pumpEventQueue(times: 50);

      final item = controller.items.single;
      expect(item.status, DownloadItemStatus.cancelled);
      expect(item.needsReauth, isFalse);
    });

    test('授權失效後重試成功：needsReauth 重設為 false', () async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final job = FakeQueuedDownloadJob(
        id: 'book-1',
        downloadError: StateError('auth'),
        authFailurePredicate: (e) => e is StateError,
      );
      controller.enqueueJobs([job]);
      await pumpEventQueue(times: 50);
      expect(controller.items.single.needsReauth, isTrue);

      job.downloadError = null;
      await controller.retry('book-1');

      final item = controller.items.single;
      expect(item.status, DownloadItemStatus.done);
      expect(item.needsReauth, isFalse);
    });

    test('授權失效後重試又遇一般失敗：仍是 failed，但 needsReauth 重設為 false', () async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final job = FakeQueuedDownloadJob(
        id: 'book-1',
        downloadError: StateError('auth'),
        authFailurePredicate: (e) => e is StateError,
      );
      controller.enqueueJobs([job]);
      await pumpEventQueue(times: 50);
      expect(controller.items.single.needsReauth, isTrue);

      // 使用者重新連結後重試，這次是斷網之類的一般失敗，不該還顯示需重新連結。
      job.downloadError = Exception('network down');
      await controller.retry('book-1');

      final item = controller.items.single;
      expect(item.status, DownloadItemStatus.failed);
      expect(item.needsReauth, isFalse);
    });
  });

  test('dismiss() 移除項目', () async {
    final controller = DownloadQueueController(
      onDuplicateConfirm: (_) async => false,
    );
    final job = FakeQueuedDownloadJob(id: 'book-1');

    controller.enqueueJobs([job]);
    await pumpEventQueue(times: 50);
    expect(controller.items, hasLength(1));

    controller.dismiss('book-1');
    expect(controller.items, isEmpty);
  });

  group('待確認更新狀態機與結算（epic-67 Issue 4）', () {
    test('更新版進入待確認且佇列繼續（Review Focus 1）', () async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final candidate = _makeTestCandidate('1');
      final job1 = FakeQueuedDownloadJob(id: 'job-1')..detectResult = candidate;
      final job2 = FakeQueuedDownloadJob(id: 'job-2');

      controller.enqueueJobs([job1, job2]);
      await pumpEventQueue(times: 50);

      expect(controller.items, hasLength(2));
      final item1 = controller.items.firstWhere((e) => e.id == 'job-1');
      final item2 = controller.items.firstWhere((e) => e.id == 'job-2');

      expect(item1.status, DownloadItemStatus.awaitingUpdateConfirmation);
      expect(item1.updateCandidate, candidate);
      expect(job1.importCalls, 0);
      expect(job1.promoteCalls, 0);

      expect(item2.status, DownloadItemStatus.done);
      expect(job2.importCalls, 1);
    });

    test('待確認期間再 enqueue 不受影響', () async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final job1 = FakeQueuedDownloadJob(id: 'job-1')
        ..detectResult = _makeTestCandidate('1');

      controller.enqueueJobs([job1]);
      await pumpEventQueue(times: 50);

      final job2 = FakeQueuedDownloadJob(id: 'job-2');
      controller.enqueueJobs([job2]);
      await pumpEventQueue(times: 50);

      expect(controller.items.firstWhere((e) => e.id == 'job-2').status, DownloadItemStatus.done);
    });

    test('原暫存檔在進入待確認後被刪除', () async {
      final tempDir = await Directory.systemTemp.createTemp('download_test_');
      final tempFile = File('${tempDir.path}/download.epub');
      await tempFile.writeAsString('download content');

      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final job = FakeQueuedDownloadJob(
        id: 'job-1',
        tempPath: tempFile.path,
      )..detectResult = _makeTestCandidate('1');

      controller.enqueueJobs([job]);
      await pumpEventQueue(times: 50);

      expect(await tempFile.exists(), isFalse);
      await tempDir.delete(recursive: true);
    });

    test('偵測先於指紋與重複對話框（Review Focus 5）', () async {
      var confirmCalled = false;
      final controller = DownloadQueueController(
        onDuplicateConfirm: (_) async {
          confirmCalled = true;
          return false;
        },
      );
      final candidate = _makeTestCandidate('1');
      final job = FakeQueuedDownloadJob(
        id: 'job-1',
        hasDuplicateResult: true,
      )..detectResult = candidate;

      controller.enqueueJobs([job]);
      await pumpEventQueue(times: 50);

      expect(confirmCalled, isFalse);
      expect(job.computeFingerprintCalls, 0);
      expect(job.callSequence, ['detect']);

      // 迴歸測試：detectResult 為 null 且 hasDuplicate 為 true，仍呼叫 onDuplicateConfirm
      final job2 = FakeQueuedDownloadJob(
        id: 'job-2',
        hasDuplicateResult: true,
      );
      controller.enqueueJobs([job2]);
      await pumpEventQueue(times: 50);
      expect(confirmCalled, isTrue);
      expect(job2.computeFingerprintCalls, 1);
      expect(job2.callSequence, ['detect', 'computeFingerprint']);
    });

    test('偵測拋例外走既有流程（Review Focus 4）', () async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final job = FakeQueuedDownloadJob(id: 'job-1')..detectThrows = Exception('detect failed');

      controller.enqueueJobs([job]);
      await pumpEventQueue(times: 50);

      expect(controller.items.single.status, DownloadItemStatus.done);
      expect(job.importCalls, 1);
    });

    test('resolveUpdate 取代／並存成功：狀態為 done，通知 onCoverChanged', () async {
      final coversChanged = <String>[];
      final controller = DownloadQueueController(
        onDuplicateConfirm: (_) async => false,
        onCoverChanged: coversChanged.add,
      );
      final candidate = _makeTestCandidate('1');
      final job = FakeQueuedDownloadJob(id: 'job-1')..detectResult = candidate;
      job.settleResult = const BookUpdateSettleResult(
        BookUpdateSettleOutcome.replaced,
        changedCoverPaths: {'/covers/old.png', '/covers/new.png'},
      );

      controller.enqueueJobs([job]);
      await pumpEventQueue(times: 50);

      final result = await controller.resolveUpdate(
        'job-1',
        const ReplaceChoice('target-1'),
      );

      expect(result.outcome, BookUpdateSettleOutcome.replaced);
      expect(controller.items.single.status, DownloadItemStatus.done);
      expect(controller.items.single.progress, 1.0);
      expect(controller.items.single.updateCandidate, isNull);
      expect(job.settleCalls, [(candidate, const ReplaceChoice('target-1'))]);
      expect(coversChanged, containsAll(['/covers/old.png', '/covers/new.png']));
    });

    test('resolveUpdate 跳過：項目從 items 移除，settleCalls 含 SkipChoice', () async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final candidate = _makeTestCandidate('1');
      final job = FakeQueuedDownloadJob(id: 'job-1')..detectResult = candidate;
      job.settleResult = const BookUpdateSettleResult(BookUpdateSettleOutcome.skipped);

      controller.enqueueJobs([job]);
      await pumpEventQueue(times: 50);

      final result = await controller.resolveUpdate('job-1', const SkipChoice());

      expect(result.outcome, BookUpdateSettleOutcome.skipped);
      expect(controller.items, isEmpty);
      expect(job.settleCalls, [(candidate, const SkipChoice())]);
    });

    test('resolveUpdate 失敗：項目變為 failed，updateCandidate 清空，可 retry 成功', () async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final candidate = _makeTestCandidate('1');
      final job = FakeQueuedDownloadJob(id: 'job-1')..detectResult = candidate;
      job.settleResult = const BookUpdateSettleResult(BookUpdateSettleOutcome.failed);

      controller.enqueueJobs([job]);
      await pumpEventQueue(times: 50);

      final result = await controller.resolveUpdate('job-1', const ReplaceChoice('target-1'));

      expect(result.outcome, BookUpdateSettleOutcome.failed);
      final item = controller.items.single;
      expect(item.status, DownloadItemStatus.failed);
      expect(item.updateCandidate, isNull);

      // retry 重新下載
      job.detectResult = null; // 重新下載後這次當一般成功
      await controller.retry('job-1');
      expect(item.status, DownloadItemStatus.done);
      expect(job.downloadCalls, 2);
    });

    test('重入與錯誤狀態防護（Review Focus 3）', () async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final candidate = _makeTestCandidate('1');
      final job = FakeQueuedDownloadJob(id: 'job-1')..detectResult = candidate;
      final settleCompleter = Completer<BookUpdateSettleResult>();
      job.settleCompleter = settleCompleter;

      controller.enqueueJobs([job]);
      await pumpEventQueue(times: 50);

      // 對非待確認狀態呼叫 resolveUpdate 回 failed 且不呼叫 settleUpdate
      final nonExistentResult = await controller.resolveUpdate('not-exist', const SkipChoice());
      expect(nonExistentResult.outcome, BookUpdateSettleOutcome.failed);

      // 同時呼叫兩次 resolveUpdate
      final future1 = controller.resolveUpdate('job-1', const ReplaceChoice('target-1'));
      final future2 = controller.resolveUpdate('job-1', const ReplaceChoice('target-1'));

      // 第二次立即回傳 failed，不重複進入 settleUpdate
      final result2 = await future2;
      expect(result2.outcome, BookUpdateSettleOutcome.failed);
      expect(job.settleCalls, hasLength(1));

      // 結算途中呼叫 dismiss 不動作（項目仍在，settleCalls 不增加）
      await controller.dismiss('job-1');
      expect(controller.items, hasLength(1));
      expect(job.settleCalls, hasLength(1));

      // 解鎖第一次結算
      settleCompleter.complete(const BookUpdateSettleResult(BookUpdateSettleOutcome.replaced));
      final result1 = await future1;
      expect(result1.outcome, BookUpdateSettleOutcome.replaced);
    });

    test('未提供 onCoverChanged 時取代成功不拋例外（審查 M-2）', () async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final candidate = _makeTestCandidate('1');
      final job = FakeQueuedDownloadJob(id: 'job-1')..detectResult = candidate;
      job.settleResult = const BookUpdateSettleResult(
        BookUpdateSettleOutcome.replaced,
        changedCoverPaths: {'/covers/test.png'},
      );

      controller.enqueueJobs([job]);
      await pumpEventQueue(times: 50);

      final result = await controller.resolveUpdate('job-1', const ReplaceChoice('target-1'));
      expect(result.outcome, BookUpdateSettleOutcome.replaced);
    });

    test('dismiss 待確認項目會先結算為 SkipChoice 再移除', () async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final candidate = _makeTestCandidate('1');
      final job = FakeQueuedDownloadJob(id: 'job-1')..detectResult = candidate;
      job.settleResult = const BookUpdateSettleResult(BookUpdateSettleOutcome.skipped);

      controller.enqueueJobs([job]);
      await pumpEventQueue(times: 50);

      await controller.dismiss('job-1');
      expect(job.settleCalls, [(candidate, const SkipChoice())]);
      expect(controller.items, isEmpty);
    });

    test('retry 對待確認項目不動作', () async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final job = FakeQueuedDownloadJob(id: 'job-1')
        ..detectResult = _makeTestCandidate('1');

      controller.enqueueJobs([job]);
      await pumpEventQueue(times: 50);

      expect(job.downloadCalls, 1);
      await controller.retry('job-1');
      expect(job.downloadCalls, 1);
    });
  });
}
