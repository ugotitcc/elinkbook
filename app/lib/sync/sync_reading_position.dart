import '../library/models/library_enums.dart';

/// 單一書籍在某一端（本機或雲端）的閱讀位置快照（epic-8-sync Issue 5，
/// spec.md「同步引擎」）：與 [ReadingPosition]（`reader/reading_position.dart`）
/// 語意相同，此處獨立定義避免 `sync/` 模組反向依賴 `reader/`。
class ReadingPositionSnapshot {
  final String? epubLocatorJson;
  final int? pdfPageIndex;
  final double progress;

  const ReadingPositionSnapshot({
    this.epubLocatorJson,
    this.pdfPageIndex,
    this.progress = 0,
  });
}

/// 使用者對閱讀位置衝突的選擇。
enum ReadingPositionChoice { keepLocal, keepCloud }

/// 一次閱讀位置衝突（FR-19）：本機與雲端都變動過同一本書的位置。
class ReadingPositionConflict {
  final String bookId;
  final String bookTitle;
  final BookFileFormat format;
  final ReadingPositionSnapshot local;
  final ReadingPositionSnapshot remote;

  const ReadingPositionConflict({
    required this.bookId,
    required this.bookTitle,
    required this.format,
    required this.local,
    required this.remote,
  });
}

/// 供 [SyncEngine]（`sync_engine.dart`）注入的衝突解決回呼——`null` 代表
/// 呼叫端沒有可用的 UI（例如背景觸發的 checkpoint），此時偵測到衝突會
/// 直接跳過該本書，留待下次 checkpoint 重試；回呼本身回傳 `null` 代表
/// 使用者關閉對話框、尚未決定，同樣跳過、下次重試。
typedef ReadingPositionConflictResolver = Future<ReadingPositionChoice?>
    Function(ReadingPositionConflict conflict);

/// 閱讀位置同步判定結果三選一（spec.md「同步引擎」步驟 1／issues.md
/// Issue 5 單元測試要求逐字對應：`noAction`＝「不需要動作」、
/// `pushLocalDirectly`＝「直接套用本機」、`needsUserDecision`＝「需要
/// 詢問使用者」）。
enum ReadingPositionSyncAction { noAction, pushLocalDirectly, needsUserDecision }

/// 閱讀位置衝突判定純函式（spec.md「同步引擎」步驟 1／「Testing
/// Decisions」）。[positionUpdatedAt] 為 `null` 或未晚於 [lastPushCompletedAt]
/// 時代表本機沒有待推送的位置異動；[remoteServerUpdated] 為 `null` 代表
/// PocketBase 目前沒有這本書的既有紀錄（第一次同步，不可能衝突）；
/// [positionSyncedServerUpdatedAt] 為本機快取的「上次成功同步時的伺服器
/// 時間戳記」，與 [remoteServerUpdated] 不同（含本機快取為 `null` 但遠端
/// 已有紀錄的情況——代表本機從未確認過遠端現況，無法排除衝突）即視為
/// 衝突。
ReadingPositionSyncAction resolveReadingPositionAction({
  required int? positionUpdatedAt,
  required int? lastPushCompletedAt,
  required String? positionSyncedServerUpdatedAt,
  required String? remoteServerUpdated,
}) {
  final isDirty =
      positionUpdatedAt != null && positionUpdatedAt > (lastPushCompletedAt ?? 0);
  if (!isDirty) return ReadingPositionSyncAction.noAction;
  if (remoteServerUpdated == null) return ReadingPositionSyncAction.pushLocalDirectly;
  if (remoteServerUpdated == positionSyncedServerUpdatedAt) {
    return ReadingPositionSyncAction.pushLocalDirectly;
  }
  return ReadingPositionSyncAction.needsUserDecision;
}
