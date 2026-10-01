import 'dart:async';

import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/foliate_native_bridge.dart'
    show StorageAccessProbeResult;
import 'package:elinkbook/reader/open_book_flow.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假計時器：由測試手動觸發，不依賴真實時間。
class _FakeTimer implements Timer {
  _FakeTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool cancelled = false;
  bool fired = false;

  /// 模擬時間到。已取消的計時器不會觸發（與真實 Timer 一致）。
  void fire() {
    if (cancelled) return;
    fired = true;
    _callback();
  }

  /// 模擬「計時器剛好在 cancel 之前已把 callback 排進事件佇列」：無視取消狀態
  /// 直接呼叫 callback，用來驗證 [OpenBookFlow] 自己的狀態 guard，而不是只
  /// 靠 cancel() 擋住。
  void forceFire() {
    fired = true;
    _callback();
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled && !fired;

  @override
  int get tick => fired ? 1 : 0;
}

const _contentUri = 'content://com.example.provider/book.epub';
const _newUri = 'content://com.example.provider/moved/book.epub';
const _picked = (uri: _newUri, displayName: 'book.epub');

Book _book(String filePath) => Book(
      id: 'b1',
      title: '測試書',
      format: BookFileFormat.epub,
      filePath: filePath,
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(0),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
    );

void main() {
  late List<_FakeTimer> timers;
  late List<String> probeCalls;

  setUp(() {
    timers = [];
    probeCalls = [];
  });

  /// 建立一個以假計時器與假探測組成的 [OpenBookFlow]。
  OpenBookFlow buildFlow({
    String filePath = _contentUri,
    OpenBookProbe? probe,
    OpenBookRelink? relinkBook,
  }) {
    final flow = OpenBookFlow(
      filePath: filePath,
      probe: (uri) {
        probeCalls.add(uri);
        return (probe ?? (_) async => StorageAccessProbeResult.unknownError)(uri);
      },
      relinkBook: relinkBook,
      timerFactory: (duration, callback) {
        final timer = _FakeTimer(duration, callback);
        timers.add(timer);
        return timer;
      },
    );
    addTearDown(flow.dispose);
    return flow;
  }

  /// 讓微任務佇列跑完（探測／relink 的 await 結果回來）。
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('初始與成功', () {
    test('start 後為 Loading 並啟動 30 秒計時器', () {
      final flow = buildFlow()..start();

      expect(flow.state, isA<OpenBookLoading>());
      expect(flow.isLoading, isTrue);
      expect(flow.isRendered, isFalse);
      expect(flow.isFailed, isFalse);
      expect(flow.failure, isNull);
      expect(timers.single.duration, const Duration(seconds: 30));
    });

    test('onRendered：切到 Rendered 並取消計時器', () {
      final flow = buildFlow()..start();

      flow.onRendered();

      expect(flow.state, isA<OpenBookRendered>());
      expect(flow.isRendered, isTrue);
      expect(timers.single.cancelled, isTrue);
    });

    test('onRendered 重複呼叫只通知一次', () {
      final flow = buildFlow()..start();
      var notifications = 0;
      flow.addListener(() => notifications++);

      flow.onRendered();
      flow.onRendered();

      expect(notifications, 1);
    });

    test('已 dispose 或已 Rendered 後呼叫 start：不建立新計時器', () {
      final disposed = buildFlow()..start();
      disposed.dispose();
      disposed.start();
      expect(timers, hasLength(1));

      final rendered = buildFlow()..start();
      rendered.onRendered();
      rendered.start();
      expect(timers, hasLength(2));
    });

    test('Rendered 之後的視圖錯誤與逾時一律忽略', () async {
      final flow = buildFlow()..start();
      flow.onRendered();

      flow.onViewError('晚到的良性警告');
      timers.single.fire();
      await settle();

      expect(flow.state, isA<OpenBookRendered>());
      expect(probeCalls, isEmpty);
    });

    test('Rendered 之後即使逾時 callback 仍被呼叫，狀態也不變（guard 本身）', () async {
      final flow = buildFlow()..start();
      flow.onRendered();

      timers.single.forceFire();
      await settle();

      expect(flow.state, isA<OpenBookRendered>());
      expect(probeCalls, isEmpty);
    });

    test('Failed 之後即使逾時 callback 仍被呼叫，不覆蓋失敗來源', () async {
      final flow = buildFlow(filePath: '/data/books/a.epub')..start();
      flow.onViewError('boom');
      final before = flow.state;

      timers.single.forceFire();

      expect(flow.state, same(before));
    });

    test('重複呼叫 start：先取消舊計時器再建立新的', () {
      final flow = buildFlow()..start();

      flow.start();

      expect(timers, hasLength(2));
      expect(timers.first.cancelled, isTrue);
      expect(timers.last.cancelled, isFalse);
    });
  });

  group('視圖回報錯誤', () {
    test('content://：先進入 Probing（仍算載入中），探測完成後 Failed', () async {
      final pending = Completer<StorageAccessProbeResult>();
      final flow = buildFlow(probe: (_) => pending.future)..start();

      flow.onViewError('boom');

      expect(flow.state, isA<OpenBookProbing>());
      expect(flow.isLoading, isTrue);
      expect(flow.isFailed, isFalse);
      expect(timers.single.cancelled, isTrue);
      expect(probeCalls, [_contentUri]);

      pending.complete(StorageAccessProbeResult.permissionRevoked);
      await settle();

      final failed = flow.state as OpenBookFailed;
      expect(failed.source, OpenBookFailureSource.viewError);
      expect(failed.viewMessage, 'boom');
      expect(failed.probeResult, StorageAccessProbeResult.permissionRevoked);
      expect(flow.isFailed, isTrue);
      expect(flow.failure, same(failed));
    });

    test('非 content://：不探測，直接 Failed 且 probeResult 為 null', () {
      final flow = buildFlow(filePath: '/data/books/a.epub')..start();

      flow.onViewError('boom');

      final failed = flow.state as OpenBookFailed;
      expect(failed.viewMessage, 'boom');
      expect(failed.probeResult, isNull);
      expect(probeCalls, isEmpty);
    });

    test('Probing 期間再收到視圖錯誤：只探測一次', () async {
      final pending = Completer<StorageAccessProbeResult>();
      final flow = buildFlow(probe: (_) => pending.future)..start();

      flow.onViewError('第一次');
      flow.onViewError('第二次');

      expect(probeCalls, hasLength(1));
      pending.complete(StorageAccessProbeResult.fileNotFound);
      await settle();
      expect((flow.state as OpenBookFailed).viewMessage, '第一次');
    });

    test('探測函式拋出例外：視為 unknownError，不停在 Probing', () async {
      final flow = buildFlow(probe: (_) async => throw StateError('probe 爆掉'))
        ..start();

      flow.onViewError('boom');
      await settle();

      expect((flow.state as OpenBookFailed).probeResult,
          StorageAccessProbeResult.unknownError);
    });

    test('Probing 期間 onRendered 先到：維持 Rendered，探測結果不覆蓋（Review Focus 2）',
        () async {
      final pending = Completer<StorageAccessProbeResult>();
      final flow = buildFlow(probe: (_) => pending.future)..start();
      flow.onViewError('boom');

      flow.onRendered();
      pending.complete(StorageAccessProbeResult.permissionRevoked);
      await settle();

      expect(flow.state, isA<OpenBookRendered>());
    });
  });

  group('開書逾時', () {
    test('content:// 逾時且權限已撤銷：Failed(timeout) 帶探測結果（Review Focus 1）', () async {
      final flow = buildFlow(
          probe: (_) async => StorageAccessProbeResult.permissionRevoked)
        ..start();

      timers.single.fire();
      expect(flow.state, isA<OpenBookProbing>());
      await settle();

      final failed = flow.state as OpenBookFailed;
      expect(failed.source, OpenBookFailureSource.timeout);
      expect(failed.viewMessage, isNull);
      expect(failed.probeResult, StorageAccessProbeResult.permissionRevoked);
      expect(probeCalls, [_contentUri]);
    });

    test('content:// 逾時但探測為 readable：仍是 Failed(timeout)，由畫面顯示逾時訊息',
        () async {
      final flow = buildFlow(probe: (_) async => StorageAccessProbeResult.readable)
        ..start();

      timers.single.fire();
      await settle();

      final failed = flow.state as OpenBookFailed;
      expect(failed.source, OpenBookFailureSource.timeout);
      expect(failed.probeResult, StorageAccessProbeResult.readable);
    });

    test('非 content:// 逾時：不探測，直接 Failed(timeout)', () {
      final flow = buildFlow(filePath: '/data/books/a.epub')..start();

      timers.single.fire();

      final failed = flow.state as OpenBookFailed;
      expect(failed.source, OpenBookFailureSource.timeout);
      expect(failed.probeResult, isNull);
      expect(probeCalls, isEmpty);
    });

    test('逾時後探測未完成時 onRendered 先到：維持 Rendered（Review Focus 2）', () async {
      final pending = Completer<StorageAccessProbeResult>();
      final flow = buildFlow(probe: (_) => pending.future)..start();
      timers.single.fire();

      flow.onRendered();
      pending.complete(StorageAccessProbeResult.fileNotFound);
      await settle();

      expect(flow.state, isA<OpenBookRendered>());
    });

    test('逾時探測期間再收到視圖錯誤：忽略，只探測一次', () async {
      final pending = Completer<StorageAccessProbeResult>();
      final flow = buildFlow(probe: (_) => pending.future)..start();
      timers.single.fire();

      flow.onViewError('晚到的錯誤');
      pending.complete(StorageAccessProbeResult.fileNotFound);
      await settle();

      expect(probeCalls, hasLength(1));
      expect((flow.state as OpenBookFailed).source,
          OpenBookFailureSource.timeout);
    });
  });

  group('dispose 之後', () {
    test('探測結果回來：不拋例外、不通知（Review Focus 3）', () async {
      final pending = Completer<StorageAccessProbeResult>();
      final flow = buildFlow(probe: (_) => pending.future)..start();
      flow.onViewError('boom');
      var notifications = 0;
      flow.addListener(() => notifications++);

      flow.dispose();
      pending.complete(StorageAccessProbeResult.permissionRevoked);
      await settle();

      expect(notifications, 0);
    });

    test('dispose 取消計時器；之後的事件與重複 dispose 都不拋例外', () {
      final flow = buildFlow()..start();

      flow.dispose();

      expect(timers.single.cancelled, isTrue);
      flow.onViewError('晚到');
      flow.onRendered();
      flow.dispose();
    });

    test('dispose 後即使逾時 callback 仍被呼叫：不探測、不通知', () async {
      final flow = buildFlow()..start();
      var notifications = 0;
      flow.addListener(() => notifications++);

      flow.dispose();
      timers.single.forceFire();
      await settle();

      expect(probeCalls, isEmpty);
      expect(notifications, 0);
    });
  });

  group('重新連結', () {
    /// 讓 flow 進入 Failed（權限已撤銷）。
    Future<OpenBookFlow> failedFlow({OpenBookRelink? relinkBook}) async {
      final flow = buildFlow(
        probe: (_) async => StorageAccessProbeResult.permissionRevoked,
        relinkBook: relinkBook,
      )..start();
      flow.onViewError('boom');
      await settle();
      expect(flow.state, isA<OpenBookFailed>());
      return flow;
    }

    test('不在 Failed 狀態：回傳 cancelled，且不呼叫選檔', () async {
      final flow = buildFlow(
          relinkBook: (_, _) async => BookRelinkSuccess(_book(_newUri)))
        ..start();
      var pickCalls = 0;

      final outcome = await flow.relink(() async {
        pickCalls++;
        return _picked;
      });

      expect(outcome, isA<OpenBookRelinkCancelled>());
      expect(pickCalls, 0);
    });

    test('沒有注入 relinkBook：回傳 cancelled', () async {
      final flow = await failedFlow();
      var pickCalls = 0;

      final outcome = await flow.relink(() async {
        pickCalls++;
        return _picked;
      });

      expect(outcome, isA<OpenBookRelinkCancelled>());
      expect(pickCalls, 0);
      expect(flow.state, isA<OpenBookFailed>());
    });

    test('成功：Relinking → Loading，路徑更新並重新啟動 30 秒計時器', () async {
      final calls = <(String, String?)>[];
      final flow = await failedFlow(relinkBook: (uri, displayName) async {
        calls.add((uri, displayName));
        return BookRelinkSuccess(_book('/data/imported/b1.epub'));
      });
      final states = <OpenBookState>[];
      flow.addListener(() => states.add(flow.state));

      final outcome = await flow.relink(() async => _picked);

      expect(calls, [(_newUri, 'book.epub')]);
      expect((outcome as OpenBookRelinkReopened).newPath,
          '/data/imported/b1.epub');
      expect(states.first, isA<OpenBookRelinking>());
      expect(flow.state, isA<OpenBookLoading>());
      expect(flow.filePath, '/data/imported/b1.epub');
      // 第 1 個是 start() 的計時器（已被視圖錯誤取消），第 2 個是重開後新建的。
      expect(timers, hasLength(2));
      expect(timers.last.cancelled, isFalse);
    });

    test('Relinking 期間 failure 仍指向進入前的 Failed', () async {
      final pending = Completer<BookRelinkResult>();
      final flow = await failedFlow(relinkBook: (_, _) => pending.future);
      final before = flow.failure;

      final future = flow.relink(() async => _picked);
      await settle();

      expect(flow.state, isA<OpenBookRelinking>());
      expect(flow.isFailed, isTrue);
      expect(flow.failure, same(before));

      pending.complete(const BookRelinkFailure(BookRelinkFailureReason.failed));
      await future;
    });

    test('選檔取消：回傳 cancelled、不呼叫 relinkBook、回到原 Failed', () async {
      var relinkCalls = 0;
      final flow = await failedFlow(relinkBook: (_, _) async {
        relinkCalls++;
        return BookRelinkSuccess(_book(_newUri));
      });
      final before = flow.state;

      final outcome = await flow.relink(() async => null);

      expect(outcome, isA<OpenBookRelinkCancelled>());
      expect(relinkCalls, 0);
      expect(flow.state, same(before));
    });

    for (final reason in BookRelinkFailureReason.values) {
      test('$reason：回傳 failed 並回到原 Failed，不重新開書', () async {
        final flow = await failedFlow(
            relinkBook: (_, _) async => BookRelinkFailure(reason));
        final before = flow.state;
        final timersBefore = timers.length;

        final outcome = await flow.relink(() async => _picked);

        expect((outcome as OpenBookRelinkFailed).reason, reason);
        expect(flow.state, same(before));
        expect(flow.filePath, _contentUri);
        expect(timers, hasLength(timersBefore));
      });
    }

    test('relinkBook 拋出例外：視為 failed', () async {
      final flow = await failedFlow(
          relinkBook: (_, _) async => throw StateError('爆掉'));

      final outcome = await flow.relink(() async => _picked);

      expect((outcome as OpenBookRelinkFailed).reason,
          BookRelinkFailureReason.failed);
      expect(flow.state, isA<OpenBookFailed>());
    });

    test('選檔函式拋出例外：視為 failed', () async {
      final flow = await failedFlow(
          relinkBook: (_, _) async => BookRelinkSuccess(_book(_newUri)));

      final outcome = await flow.relink(() async => throw StateError('爆掉'));

      expect((outcome as OpenBookRelinkFailed).reason,
          BookRelinkFailureReason.failed);
    });

    test('處理中再次呼叫 relink：回傳 cancelled，選檔只開一次（Review Focus 4）', () async {
      final pendingPick = Completer<OpenBookPickedFile?>();
      final flow = await failedFlow(
          relinkBook: (_, _) async => BookRelinkSuccess(_book(_newUri)));
      var pickCalls = 0;

      final first = flow.relink(() {
        pickCalls++;
        return pendingPick.future;
      });
      final second = flow.relink(() async {
        pickCalls++;
        return _picked;
      });

      expect(await second, isA<OpenBookRelinkCancelled>());
      expect(pickCalls, 1);
      pendingPick.complete(null);
      await first;
    });

    test('Relinking 期間的視圖錯誤與 onRendered 一律忽略（Review Focus 4）', () async {
      final pending = Completer<BookRelinkResult>();
      final flow = await failedFlow(relinkBook: (_, _) => pending.future);
      final future = flow.relink(() async => _picked);
      await settle();

      flow.onViewError('雜訊');
      flow.onRendered();

      expect(flow.state, isA<OpenBookRelinking>());
      expect(probeCalls, hasLength(1));
      pending.complete(const BookRelinkFailure(BookRelinkFailureReason.failed));
      await future;
    });

    test('選檔期間 dispose：不呼叫 relinkBook、不拋例外、不通知（Review Focus 3）', () async {
      final pendingPick = Completer<OpenBookPickedFile?>();
      var relinkCalls = 0;
      final flow = await failedFlow(relinkBook: (_, _) async {
        relinkCalls++;
        return BookRelinkSuccess(_book(_newUri));
      });
      final future = flow.relink(() => pendingPick.future);
      var notifications = 0;
      flow.addListener(() => notifications++);

      flow.dispose();
      pendingPick.complete(_picked);
      final outcome = await future;

      expect(outcome, isA<OpenBookRelinkCancelled>());
      expect(relinkCalls, 0);
      expect(notifications, 0);
    });

    test('relinkBook 處理中 dispose：結果回來不拋例外、不通知（Review Focus 3）', () async {
      final pending = Completer<BookRelinkResult>();
      final flow = await failedFlow(relinkBook: (_, _) => pending.future);
      final future = flow.relink(() async => _picked);
      await settle();
      var notifications = 0;
      flow.addListener(() => notifications++);

      flow.dispose();
      pending.complete(BookRelinkSuccess(_book(_newUri)));
      await future;

      expect(notifications, 0);
    });

    test('重新開書後再次視圖錯誤：以新路徑重新探測（Review Focus 5）', () async {
      final flow = await failedFlow(
          relinkBook: (_, _) async => BookRelinkSuccess(_book(_newUri)));
      await flow.relink(() async => _picked);

      flow.onViewError('又失敗');
      await settle();

      expect(probeCalls, [_contentUri, _newUri]);
      expect(flow.state, isA<OpenBookFailed>());
    });

    test('重新開書後再次卡住：新的 30 秒計時器到期會觸發逾時（Review Focus 5）', () async {
      final flow = await failedFlow(
          relinkBook: (_, _) async => BookRelinkSuccess(_book(_newUri)));
      await flow.relink(() async => _picked);

      timers.last.fire();
      await settle();

      expect((flow.state as OpenBookFailed).source,
          OpenBookFailureSource.timeout);
      expect(probeCalls, [_contentUri, _newUri]);
    });
  });
}