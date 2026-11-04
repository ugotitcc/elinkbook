import 'dart:async';

import 'package:elinkbook/downloads/download_queue_controller.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/library/book_update_models.dart';
import 'package:elinkbook/library/book_update_settle.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/widgets/download_queue_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeQueuedDownloadJob implements QueuedDownloadJob {
  _FakeQueuedDownloadJob({required this.id, required this.name});

  @override
  final String id;
  @override
  final String name;

  final _downloadCompleter = Completer<String>();
  bool _cancelled = false;

  @override
  bool get isCancelled => _cancelled;

  @override
  Future<String> download({
    required void Function(int received, int total) onProgress,
  }) =>
      _downloadCompleter.future;

  @override
  void cancel() {
    _cancelled = true;
    if (!_downloadCompleter.isCompleted) {
      _downloadCompleter.completeError(StateError('cancelled'));
    }
  }

  void completeDownload() {
    if (!_downloadCompleter.isCompleted) _downloadCompleter.complete('/tmp/fake');
  }

  void failDownload(Object error) {
    if (!_downloadCompleter.isCompleted) _downloadCompleter.completeError(error);
  }

  @override
  Future<String> computeFingerprint(String tempPath) async => 'fingerprint-$id';

  @override
  Future<bool> hasDuplicate(String fingerprint) async => false;

  @override
  Future<String> promote(String tempPath) async => tempPath;

  @override
  Future<void> import(String permanentPath) async {}

  @override
  bool isAuthFailure(Object error) => error is _AuthFailure;

  @override
  Future<BookUpdateCandidate?> detectUpdate(String tempPath) async => null;

  @override
  Future<BookUpdateSettleResult> settleUpdate(
    BookUpdateCandidate candidate,
    BookUpdateChoice choice,
  ) async {
    if (choice is ReplaceChoice) {
      return const BookUpdateSettleResult(BookUpdateSettleOutcome.replaced);
    } else if (choice is CoexistChoice) {
      return const BookUpdateSettleResult(BookUpdateSettleOutcome.coexisted);
    } else {
      return const BookUpdateSettleResult(BookUpdateSettleOutcome.skipped);
    }
  }
}

class _AuthFailure implements Exception {}

void main() {
  Future<void> pumpPanel(
    WidgetTester tester,
    DownloadQueueController controller, {
    Locale locale = const Locale('zh', 'TW'),
    bool isEinkMode = false,
  }) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: DownloadQueuePanel(controller: controller, isEinkMode: isEinkMode)),
    ));
  }

  testWidgets('沒有任何項目時整個區塊不渲染', (tester) async {
    final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
    await pumpPanel(tester, controller);
    expect(find.text('下載佇列'), findsNothing);
  });

  testWidgets('下載中項目顯示標題／狀態標籤／取消按鈕，取消後變更為已取消並可重試', (tester) async {
    final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
    final job = _FakeQueuedDownloadJob(id: 'book-1', name: '測試書籍');
    await pumpPanel(tester, controller);

    controller.enqueueJobs([job]);
    await tester.pump();

    expect(find.text('下載佇列'), findsOneWidget);
    expect(find.text('下載中'), findsOneWidget);
    final cancelButton = tester.widget<IconButton>(
      find.byKey(const Key('sources_download_queue_cancel_book-1')),
    );
    expect(cancelButton.tooltip, '取消');

    await tester.tap(find.byKey(const Key('sources_download_queue_cancel_book-1')));
    await tester.pump();

    expect(find.text('已取消'), findsOneWidget);
    final retryButton = tester.widget<IconButton>(
      find.byKey(const Key('sources_download_queue_retry_book-1')),
    );
    expect(retryButton.tooltip, '重試');
  });

  testWidgets('下載成功完成後顯示「完成」標籤與「從清單移除」按鈕', (tester) async {
    final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
    final job = _FakeQueuedDownloadJob(id: 'book-2', name: '測試書籍2');
    await pumpPanel(tester, controller);

    controller.enqueueJobs([job]);
    await tester.pump();
    job.completeDownload();
    await tester.pump();
    await tester.pump();

    expect(find.text('完成'), findsOneWidget);
    final dismissButton = tester.widget<IconButton>(
      find.byKey(const Key('sources_download_queue_dismiss_book-2')),
    );
    expect(dismissButton.tooltip, '從清單移除');
  });

  testWidgets('授權失效造成的失敗顯示「需重新連結帳號」並保留重試鈕', (tester) async {
    final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
    final job = _FakeQueuedDownloadJob(id: 'book-4', name: '測試書籍4');
    await pumpPanel(tester, controller);

    controller.enqueueJobs([job]);
    await tester.pump();
    job.failDownload(_AuthFailure());
    await tester.pump();
    await tester.pump();

    expect(find.text('需重新連結帳號'), findsOneWidget);
    expect(find.text('失敗'), findsNothing);
    expect(
      find.byKey(const Key('sources_download_queue_retry_book-4')),
      findsOneWidget,
    );
  });

  testWidgets('一般失敗仍顯示「失敗」，不顯示需重新連結', (tester) async {
    final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
    final job = _FakeQueuedDownloadJob(id: 'book-5', name: '測試書籍5');
    await pumpPanel(tester, controller);

    controller.enqueueJobs([job]);
    await tester.pump();
    job.failDownload(StateError('network'));
    await tester.pump();
    await tester.pump();

    expect(find.text('失敗'), findsOneWidget);
    expect(find.text('需重新連結帳號'), findsNothing);
  });

  testWidgets('英文介面下授權失效顯示對應英文', (tester) async {
    final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
    final job = _FakeQueuedDownloadJob(id: 'book-6', name: 'Test Book');
    await pumpPanel(tester, controller, locale: const Locale('en'));

    controller.enqueueJobs([job]);
    await tester.pump();
    job.failDownload(_AuthFailure());
    await tester.pump();
    await tester.pump();

    expect(find.text('Account needs reconnecting'), findsOneWidget);
  });

  testWidgets('英文介面下標題與狀態標籤正確顯示', (tester) async {
    final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
    final job = _FakeQueuedDownloadJob(id: 'book-3', name: 'Test Book');
    await pumpPanel(tester, controller, locale: const Locale('en'));

    controller.enqueueJobs([job]);
    await tester.pump();

    expect(find.text('Download Queue'), findsOneWidget);
    expect(find.text('Downloading'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sources_download_queue_cancel_book-3')));
    await tester.pump();
    expect(find.text('Cancelled'), findsOneWidget);
  });

  group("待確認更新面板呈現與互動（epic-67 Issue 4 Task 5）", () {
    BookUpdateCandidate makeCandidate(String id) {
      return BookUpdateCandidate(
        sourceUri: "file:///tmp/candidate-$id.epub",
        displayName: "更新版書籍-$id.epub",
        format: BookFileFormat.epub,
        stagedPath: "/tmp/staging-$id.epub",
        confidence: UpdateConfidence.high,
        candidateBooks: [
          Book(
            id: "book-$id",
            title: "舊版書籍-$id",
            format: BookFileFormat.epub,
            source: BookSource.local,
            filePath: "/data/book-$id.epub",
            createTime: DateTime(2026, 1, 1),
            lastReadTime: DateTime(2026, 1, 1),
          ),
        ],
      );
    }

    testWidgets("待確認項目呈現：顯示「待確認更新」標籤、review 按鈕與 dismiss 按鈕都在（Review Focus 3）", (tester) async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final job = _FakeQueuedDownloadJob(id: "job-1", name: "更新版書");
      final candidate = makeCandidate("1");
      await pumpPanel(tester, controller);

      controller.enqueueJobs([job]);
      final item = controller.items.first;
      item.status = DownloadItemStatus.awaitingUpdateConfirmation;
      item.updateCandidate = candidate;
      controller.notifyListeners();
      await tester.pumpAndSettle();

      expect(find.text("待確認更新"), findsOneWidget);
      expect(find.byKey(const Key("sources_download_queue_review_job-1")), findsOneWidget);
      expect(find.byKey(const Key("sources_download_queue_dismiss_job-1")), findsOneWidget);
    });

    testWidgets("點 review 開對話框，選取代套用後呼叫 resolveUpdate 並彈出 SnackBar", (tester) async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final job = _FakeQueuedDownloadJob(id: "job-1", name: "更新版書");
      final candidate = makeCandidate("1");
      await pumpPanel(tester, controller);

      controller.enqueueJobs([job]);
      final item = controller.items.first;
      item.status = DownloadItemStatus.awaitingUpdateConfirmation;
      item.updateCandidate = candidate;
      controller.notifyListeners();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key("sources_download_queue_review_job-1")));
      await tester.pumpAndSettle();

      expect(find.text("更新版書籍-1.epub"), findsOneWidget);
      expect(find.byKey(const Key("book_update_apply")), findsOneWidget);

      await tester.tap(find.byKey(const Key("book_update_apply")));
      await tester.pumpAndSettle();

      expect(find.text("已更新 1 本"), findsOneWidget);
      expect(item.status, DownloadItemStatus.done);
    });

    testWidgets("對話框按取消：候選未結算、項目仍在面板且仍為待確認（D4）", (tester) async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final job = _FakeQueuedDownloadJob(id: "job-1", name: "更新版書");
      final candidate = makeCandidate("1");
      await pumpPanel(tester, controller);

      controller.enqueueJobs([job]);
      final item = controller.items.first;
      item.status = DownloadItemStatus.awaitingUpdateConfirmation;
      item.updateCandidate = candidate;
      controller.notifyListeners();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key("sources_download_queue_review_job-1")));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key("book_update_cancel")));
      await tester.pumpAndSettle();

      expect(item.status, DownloadItemStatus.awaitingUpdateConfirmation);
      expect(controller.items, hasLength(1));
    });

    testWidgets("點待確認項目的 dismiss：resolveUpdate 帶入 SkipChoice 且項目消失", (tester) async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final job = _FakeQueuedDownloadJob(id: "job-1", name: "更新版書");
      final candidate = makeCandidate("1");
      await pumpPanel(tester, controller);

      controller.enqueueJobs([job]);
      final item = controller.items.first;
      item.status = DownloadItemStatus.awaitingUpdateConfirmation;
      item.updateCandidate = candidate;
      controller.notifyListeners();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key("sources_download_queue_dismiss_job-1")));
      await tester.pumpAndSettle();

      expect(controller.items, isEmpty);
    });
  });
}

