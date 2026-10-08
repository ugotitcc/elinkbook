import 'package:flutter/foundation.dart';

import '../sync/sync_account_repository.dart';
import '../sync/sync_checkpoint_result.dart';
import '../sync/sync_checkpoint_trigger.dart';
import '../sync/sync_client.dart';

/// 同步依賴組（ADR 0037）：`SettingsScaffold`（同步設定入口）與其上層
/// `AdaptiveShellScaffold`／`ElinkBookApp`（進背景時觸發 checkpoint）接收這一個
/// 物件，取代逐欄傳遞。
///
/// 全部 non-null、required：`main.dart` 啟動時全部都會建好。
/// `syncCheckpointTrigger` 同時也屬於閱讀器依賴組，**由 `main()` 建構一次、同一
/// 實例放進兩組**，不得各組自行建構（ADR 0037 §1）。
@immutable
class SyncDependencies {
  final SyncAccountRepository syncAccountRepository;
  final SyncClient syncClient;
  final SyncCheckpointTrigger syncCheckpointTrigger;

  /// 「立即同步」按鈕：刻意收窄成單一 callback 而非整個 `SyncEngine`，讓
  /// `SyncSettingsScreen` 的 widget test 可注入輕量假 closure，不需要真實 sqflite。
  final Future<SyncCheckpointResult> Function() onManualSync;
  final Future<int?> Function() loadLastSyncedAt;

  const SyncDependencies({
    required this.syncAccountRepository,
    required this.syncClient,
    required this.syncCheckpointTrigger,
    required this.onManualSync,
    required this.loadLastSyncedAt,
  });
}
