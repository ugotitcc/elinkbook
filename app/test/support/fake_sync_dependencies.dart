import 'package:elinkbook/screens/sync_dependencies.dart';
import 'package:elinkbook/sync/sync_account_repository.dart';
import 'package:elinkbook/sync/sync_checkpoint_result.dart';
import 'package:elinkbook/sync/sync_checkpoint_trigger.dart';
import 'package:elinkbook/sync/sync_client.dart';

/// 預設全 fake 的同步依賴組（ADR 0037）。只覆寫情境需要的欄位；每次呼叫都建新實例。
/// `SyncAccountRepository()`／`SyncClient(...)` 建構時不做 I/O，可直接用於 widget test。
SyncDependencies fakeSyncDependencies({
  SyncAccountRepository? syncAccountRepository,
  SyncClient? syncClient,
  SyncCheckpointTrigger? syncCheckpointTrigger,
  Future<SyncCheckpointResult> Function()? onManualSync,
  Future<int?> Function()? loadLastSyncedAt,
}) {
  final account = syncAccountRepository ?? SyncAccountRepository();
  return SyncDependencies(
    syncAccountRepository: account,
    syncClient: syncClient ?? SyncClient(accountRepository: account),
    syncCheckpointTrigger:
        syncCheckpointTrigger ??
        SyncCheckpointTrigger(
          runCheckpoint: () async => SyncCheckpointResult.notLoggedIn,
        ),
    onManualSync: onManualSync ?? () async => SyncCheckpointResult.notLoggedIn,
    loadLastSyncedAt: loadLastSyncedAt ?? () async => null,
  );
}
