import 'sync_models.dart';
import 'sync_table_specs.dart';

/// PocketBase 的 number 欄位在未設值時預設為 0，而非真正的 SQL NULL
/// （Issue 7 的 pb_hooks 墓碑清理腳本審查時已發現並修正的同一個特性，
/// 見 plan-issue-7.md「實作結果審查修正紀錄」）。下載端讀取 deleted_at
/// 時必須把 0 視同未刪除（null），不能直接轉型。
int? normalizeDeletedAt(Object? raw) {
  if (raw == null) return null;
  final value = (raw as num).toInt();
  return value == 0 ? null : value;
}

/// 下載合併判定純函式（spec.md「跨裝置參照設計」／「Testing
/// Decisions」）：[booksByFingerprint] 為目前本機所有
/// `books.content_fingerprint` -> (id, format) 的對照表（呼叫端一次查詢、
/// 供本次 checkpoint 下載的所有紀錄共用）；[notDirtyUpdatedAt] 是合併寫入
/// 本機時要填入的 `updated_at` 值——刻意不用 `DateTime.now()`，而是使用
/// 本次 checkpoint 剛寫入的 `lastPushCompletedAt` 值，確保剛合併進來的
/// 遠端紀錄不會在下一次 checkpoint 被誤判為本機 dirty、造成不必要的
/// 重複推送。
MergeDecision resolveMergeDecision({
  required SyncTableSpec spec,
  required RemoteRecordMergeInput input,
  required Map<String, BookLookup> booksByFingerprint,
  required int notDirtyUpdatedAt,
}) {
  final book =
      input.bookFingerprint == null ? null : booksByFingerprint[input.bookFingerprint];
  if (book == null) {
    return const MergeDecision(resolved: false);
  }
  return MergeDecision(resolved: true, localRow: {
    'id': input.clientId,
    'book_id': book.id,
    'deleted_at': input.deletedAt,
    'updated_at': notDirtyUpdatedAt,
    ...spec.buildLocalFields(input.rawFields, book.format),
  });
}

/// 墓碑清理篩選純函式（spec.md「墓碑清理」）：回傳應真正 DELETE 的 id
/// 清單——`deleted_at` 非空且早於 [now] 減去 [retention]（預設 30 天）。
List<String> idsPastTombstoneRetention({
  required List<Map<String, Object?>> rows,
  required DateTime now,
  Duration retention = const Duration(days: 30),
}) {
  final cutoff = now.subtract(retention).millisecondsSinceEpoch;
  return rows
      .where((row) => row['deleted_at'] != null && (row['deleted_at'] as int) < cutoff)
      .map((row) => row['id'] as String)
      .toList();
}

/// 找出多筆遠端紀錄的 `updated` 系統欄位字串中最大的一個（PocketBase 的
/// `updated` 為固定格式、可直接用字串比較排序的時間戳記，見 spec.md
/// 「PocketBase Collection Schema」），供更新 `sync_metadata` 的下載游標
/// 使用；[current] 為目前游標值，回傳結果不會比它舊。
String? maxUpdatedCursor(List<String> updatedValues, String? current) {
  var result = current;
  for (final value in updatedValues) {
    if (result == null || value.compareTo(result) > 0) {
      result = value;
    }
  }
  return result;
}
