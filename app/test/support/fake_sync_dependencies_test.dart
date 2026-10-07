import 'package:elinkbook/sync/sync_checkpoint_result.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sync_dependencies.dart';

void main() {
  test('fakeSyncDependencies 預設全部有值（non-null），且每次呼叫是新實例', () async {
    final a = fakeSyncDependencies();
    final b = fakeSyncDependencies();
    expect(identical(a.syncCheckpointTrigger, b.syncCheckpointTrigger), isFalse);
    expect(identical(a.syncAccountRepository, b.syncAccountRepository), isFalse);
    expect(await a.onManualSync(), SyncCheckpointResult.notLoggedIn);
    expect(await a.loadLastSyncedAt(), isNull);
  });

  test('fakeSyncDependencies 具名覆寫原樣帶入（同一實例）', () {
    final trigger = fakeSyncDependencies().syncCheckpointTrigger;
    final deps = fakeSyncDependencies(syncCheckpointTrigger: trigger);
    expect(deps.syncCheckpointTrigger, same(trigger));
  });
}
