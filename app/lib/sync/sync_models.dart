import 'package:elinkbook/library/models/library_enums.dart';

/// 三種可同步的本機標註 collection（epic-8-sync Issue 4，spec.md「本機
/// Schema 變更」／「PocketBase Collection Schema」）。閱讀位置
/// （`sync_reading_positions`）不在此列——由 Issue 5 另外處理，不共用
/// 本檔案的推送/合併純函式（見 plan-issue-4.md Global Constraints）。
enum SyncCollection {
  bookmarks,
  highlights,
  notes;

  String get localTable => switch (this) {
        SyncCollection.bookmarks => 'bookmarks',
        SyncCollection.highlights => 'highlights',
        SyncCollection.notes => 'notes',
      };

  String get remoteCollection => switch (this) {
        SyncCollection.bookmarks => 'sync_bookmarks',
        SyncCollection.highlights => 'sync_highlights',
        SyncCollection.notes => 'sync_notes',
      };
}

/// 一筆待送出的推送操作（純資料，見 sync_push_planner.dart）。
/// [remoteId] 為 `null` 代表本機從未推送過此紀錄（走 PocketBase create），
/// 非 `null` 代表已知對應的 PocketBase 記錄 id（走 update）。
class PushOperation {
  final SyncCollection collection;
  final String? remoteId;
  final Map<String, Object?> body;

  const PushOperation({
    required this.collection,
    required this.remoteId,
    required this.body,
  });
}

/// 一筆下載回來、待合併判定的遠端紀錄（純資料，見 sync_merge.dart）。
/// [deletedAt] 已正規化（PocketBase 的 0 視為未刪除、已轉為 null，見
/// sync_merge.dart `normalizeDeletedAt`）；[rawFields] 為**尚未**依書籍
/// 格式正規化的原始欄位（見 sync_table_specs.dart「與 spec.md／Issue 7
/// 的落差說明」），實際正規化延後到書籍格式已知的合併/佇列解析當下才
/// 執行（見 SyncEngine）。
class RemoteRecordMergeInput {
  final String remoteId;
  final String clientId;
  final String? bookFingerprint;
  final int? deletedAt;
  final Map<String, Object?> rawFields;

  const RemoteRecordMergeInput({
    required this.remoteId,
    required this.clientId,
    required this.bookFingerprint,
    required this.deletedAt,
    required this.rawFields,
  });
}

/// 本機書籍查找結果（依 content_fingerprint 查得），供合併判定需要知道
/// 書籍格式才能正確解析 [RemoteRecordMergeInput.rawFields]（見上方）。
class BookLookup {
  final String id;
  final BookFileFormat format;

  const BookLookup({required this.id, required this.format});
}

/// 合併判定結果（純資料）：[resolved] 為 false 代表 book_fingerprint 查無
/// 對應本機書籍，應暫緩合併（寫入 sync_pending_records）；true 代表
/// [localRow] 是可直接寫入本機資料表的完整一列（含 id/book_id/deleted_at/
/// updated_at）。
class MergeDecision {
  final bool resolved;
  final Map<String, Object?>? localRow;

  const MergeDecision({required this.resolved, this.localRow});
}
