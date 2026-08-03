import 'sync_models.dart';
import 'sync_table_specs.dart';

/// 判斷一筆本機紀錄自上次成功推送後是否有新異動（純本機時鐘比較，見
/// spec.md「同步引擎」：只跟自己過去的 lastPushCompletedAt 比較，不跨
/// 裝置比較）。[lastPushCompletedAt] 為 `null` 代表從未推送過，任何
/// [updatedAt] 皆視為 dirty。
bool isDirtyRow(int updatedAt, int? lastPushCompletedAt) {
  return updatedAt > (lastPushCompletedAt ?? 0);
}

/// 組裝單一 collection 的推送操作清單（純函式，spec.md「Testing
/// Decisions」）。[joinedRows] 為已與 `books` 表 JOIN 取得
/// `book_fingerprint` 的本機異動列（見 SyncEngine 呼叫端 `_queryDirtyRows`）；
/// [remoteIdsByClientId] 為本機 `sync_remote_ids` 快取（有對照代表已知
/// PocketBase 記錄 id，走 update；查無對照代表尚未推送過，走 create）。
/// `book_fingerprint` 仍為 `null`（該書尚未有指紋，補算失敗或跳過）的列
/// 會被排除，等待下次 checkpoint 重試。
List<PushOperation> buildPushOperations({
  required SyncTableSpec spec,
  required List<Map<String, Object?>> joinedRows,
  required Map<String, String> remoteIdsByClientId,
  required String userId,
}) {
  final operations = <PushOperation>[];
  for (final row in joinedRows) {
    final bookFingerprint = row['book_fingerprint'] as String?;
    if (bookFingerprint == null) continue;
    final clientId = row['id'] as String;
    final body = <String, Object?>{
      'user': userId,
      'client_id': clientId,
      'book_fingerprint': bookFingerprint,
      'deleted_at': row['deleted_at'],
      ...spec.buildPushFields(row),
    };
    operations.add(PushOperation(
      collection: spec.collection,
      remoteId: remoteIdsByClientId[clientId],
      body: body,
    ));
  }
  return operations;
}

/// 依固定上限（預設 100 筆/批，spec.md「同步引擎」）把推送操作拆成多個
/// 依序送出的批次。
List<List<PushOperation>> planPushBatches(
  List<PushOperation> operations, {
  int batchLimit = 100,
}) {
  final batches = <List<PushOperation>>[];
  for (var i = 0; i < operations.length; i += batchLimit) {
    final end = (i + batchLimit < operations.length) ? i + batchLimit : operations.length;
    batches.add(operations.sublist(i, end));
  }
  return batches;
}
