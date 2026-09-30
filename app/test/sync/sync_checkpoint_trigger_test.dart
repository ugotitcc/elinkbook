import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/sync/sync_checkpoint_result.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';

void main() {
  test('trigger() 呼叫 runCheckpoint() 一次', () async {
    var runCheckpointCallCount = 0;
    final trigger = SyncCheckpointTrigger(
      runCheckpoint: () async {
        runCheckpointCallCount++;
        return SyncCheckpointResult.synced;
      },
    );

    await trigger.trigger();

    expect(runCheckpointCallCount, 1);
  });

  test('trigger() 每次呼叫都重新執行 runCheckpoint()（登入判斷由 SyncEngine 負責）', () async {
    var runCheckpointCallCount = 0;
    final trigger = SyncCheckpointTrigger(
      runCheckpoint: () async {
        runCheckpointCallCount++;
        return SyncCheckpointResult.notLoggedIn;
      },
    );

    await trigger.trigger();
    await trigger.trigger();

    expect(runCheckpointCallCount, 2);
  });

  group('登入過期提示（epic-50-sync-token-refresh、epic-53-sync-checkpoint-result）', () {
    test('checkpoint 回報 sessionExpired：呼叫 onSessionExpired 一次', () async {
      var sessionExpiredCallCount = 0;
      final trigger = SyncCheckpointTrigger(
        runCheckpoint: () async => SyncCheckpointResult.sessionExpired,
        onSessionExpired: () => sessionExpiredCallCount++,
      );

      await trigger.trigger();

      expect(sessionExpiredCallCount, 1);
    });

    test('其餘結果一律靜默：不呼叫 onSessionExpired', () async {
      for (final result in SyncCheckpointResult.values) {
        if (result == SyncCheckpointResult.sessionExpired) continue;
        var sessionExpiredCallCount = 0;
        final trigger = SyncCheckpointTrigger(
          runCheckpoint: () async => result,
          onSessionExpired: () => sessionExpiredCallCount++,
        );

        await trigger.trigger();

        expect(sessionExpiredCallCount, 0, reason: '$result 不應提示登入過期');
      }
    });

    test('未提供 onSessionExpired 時，sessionExpired 結果不會拋出例外', () async {
      final trigger = SyncCheckpointTrigger(
        runCheckpoint: () async => SyncCheckpointResult.sessionExpired,
      );

      await trigger.trigger();
    });
  });
}
