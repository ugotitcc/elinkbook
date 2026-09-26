import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';

void main() {
  test('已登入時，trigger() 呼叫 runCheckpoint()', () async {
    var runCheckpointCallCount = 0;
    final trigger = SyncCheckpointTrigger(
      isLoggedIn: () async => true,
      runCheckpoint: () async {
        runCheckpointCallCount++;
      },
    );

    await trigger.trigger();

    expect(runCheckpointCallCount, 1);
  });

  test('未登入時，trigger() 不呼叫 runCheckpoint()', () async {
    var runCheckpointCallCount = 0;
    final trigger = SyncCheckpointTrigger(
      isLoggedIn: () async => false,
      runCheckpoint: () async {
        runCheckpointCallCount++;
      },
    );

    await trigger.trigger();

    expect(runCheckpointCallCount, 0);
  });

  test('trigger() 每次呼叫都重新檢查登入狀態', () async {
    var loggedIn = false;
    var runCheckpointCallCount = 0;
    final trigger = SyncCheckpointTrigger(
      isLoggedIn: () async => loggedIn,
      runCheckpoint: () async {
        runCheckpointCallCount++;
      },
    );

    await trigger.trigger();
    expect(runCheckpointCallCount, 0, reason: '第一次呼叫時尚未登入');

    loggedIn = true;
    await trigger.trigger();
    expect(runCheckpointCallCount, 1, reason: '第二次呼叫時已登入，應正常觸發');
  });

  group('登入過期提示（epic-50-sync-token-refresh）', () {
    test('checkpoint 期間 token 過期被清除：呼叫 onSessionExpired 一次', () async {
      var loggedIn = true;
      var sessionExpiredCallCount = 0;
      final trigger = SyncCheckpointTrigger(
        isLoggedIn: () async => loggedIn,
        // 模擬 SyncEngine 的 authRefresh 收到 401、清除 token。
        runCheckpoint: () async => loggedIn = false,
        isSessionExpired: () async => !loggedIn,
        onSessionExpired: () => sessionExpiredCallCount++,
      );

      await trigger.trigger();
      expect(sessionExpiredCallCount, 1);

      await trigger.trigger();
      expect(sessionExpiredCallCount, 1, reason: '過期後已是未登入，後續觸發直接略過，不重複提示');
    });

    test('checkpoint 後仍在登入狀態：不呼叫 onSessionExpired', () async {
      var sessionExpiredCallCount = 0;
      final trigger = SyncCheckpointTrigger(
        isLoggedIn: () async => true,
        runCheckpoint: () async {},
        isSessionExpired: () async => false,
        onSessionExpired: () => sessionExpiredCallCount++,
      );

      await trigger.trigger();

      expect(sessionExpiredCallCount, 0);
    });
  });
}
