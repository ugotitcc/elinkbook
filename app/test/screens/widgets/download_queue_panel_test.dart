import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/downloads/download_queue_controller.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/screens/widgets/download_queue_panel.dart';

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
}

class _AuthFailure implements Exception {}

void main() {
  Future<void> pumpPanel(
    WidgetTester tester,
    DownloadQueueController controller, {
    Locale locale = const Locale('zh', 'TW'),
  }) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: DownloadQueuePanel(controller: controller)),
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
}
