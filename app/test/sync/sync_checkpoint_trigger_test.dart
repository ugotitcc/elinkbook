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
}
