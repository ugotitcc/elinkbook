import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'sync_models.dart';

/// 一筆待處理的同步紀錄（epic-8-sync Issue 4，spec.md「跨裝置參照
/// 設計」）：`book_fingerprint` 查無對應本機書籍時暫緩合併，落地於
/// `sync_pending_records`，等待使用者之後匯入同一本書。
class PendingSyncRecord {
  final SyncCollection collection;
  final String clientId;
  final String bookFingerprint;
  final String remoteId;
  final int? deletedAt;
  final Map<String, Object?> fields;

  const PendingSyncRecord({
    required this.collection,
    required this.clientId,
    required this.bookFingerprint,
    required this.remoteId,
    required this.deletedAt,
    required this.fields,
  });
}

/// 同步中繼資料存取層（epic-8-sync Issue 4，spec.md「本機 Schema
/// 變更」／「跨裝置參照設計」）：包裝 Issue 1 已建立的 `sync_metadata`
/// 表，以及本 Issue 新增的 `sync_remote_ids`／`sync_pending_records`
/// 兩張表（見 plan-issue-4.md Task 1）。`sync_metadata` 恆為單列
/// （`id = 1`，Issue 1 已保證存在）。
class SyncMetadataRepository {
  final Database _db;

  const SyncMetadataRepository(this._db);

  Future<int?> loadLastPushCompletedAt() async {
    final rows = await _db.query('sync_metadata', where: 'id = 1');
    return rows.single['last_push_completed_at'] as int?;
  }

  Future<void> saveLastPushCompletedAt(int value) {
    return _db.update(
      'sync_metadata',
      {'last_push_completed_at': value},
      where: 'id = 1',
    );
  }

  static const _cursorColumns = {
    SyncCollection.bookmarks: 'last_pulled_server_updated_at_bookmarks',
    SyncCollection.highlights: 'last_pulled_server_updated_at_highlights',
    SyncCollection.notes: 'last_pulled_server_updated_at_notes',
  };

  Future<String?> loadPulledCursor(SyncCollection collection) async {
    final rows = await _db.query('sync_metadata', where: 'id = 1');
    return rows.single[_cursorColumns[collection]] as String?;
  }

  Future<void> savePulledCursor(SyncCollection collection, String value) {
    return _db.update(
      'sync_metadata',
      {_cursorColumns[collection]!: value},
      where: 'id = 1',
    );
  }

  Future<Map<String, String>> loadRemoteIds(SyncCollection collection) async {
    final rows = await _db.query(
      'sync_remote_ids',
      where: 'collection = ?',
      whereArgs: [collection.name],
    );
    return {
      for (final row in rows) row['client_id'] as String: row['remote_id'] as String,
    };
  }

  Future<void> saveRemoteId(
    SyncCollection collection,
    String clientId,
    String remoteId,
  ) {
    return _db.insert(
      'sync_remote_ids',
      {'collection': collection.name, 'client_id': clientId, 'remote_id': remoteId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<PendingSyncRecord>> listPendingRecords() async {
    final rows = await _db.query('sync_pending_records');
    return rows.map((row) {
      final payload = jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
      return PendingSyncRecord(
        collection: SyncCollection.values.byName(row['collection'] as String),
        clientId: row['client_id'] as String,
        bookFingerprint: row['book_fingerprint'] as String,
        remoteId: payload['remoteId'] as String,
        deletedAt: payload['deletedAt'] as int?,
        fields: (payload['fields'] as Map).cast<String, Object?>(),
      );
    }).toList();
  }

  Future<void> savePendingRecord({
    required SyncCollection collection,
    required String clientId,
    required String bookFingerprint,
    required String remoteId,
    required int? deletedAt,
    required Map<String, Object?> fields,
  }) {
    return _db.insert(
      'sync_pending_records',
      {
        'collection': collection.name,
        'client_id': clientId,
        'book_fingerprint': bookFingerprint,
        'payload_json': jsonEncode({
          'remoteId': remoteId,
          'deletedAt': deletedAt,
          'fields': fields,
        }),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deletePendingRecord(SyncCollection collection, String clientId) {
    return _db.delete(
      'sync_pending_records',
      where: 'collection = ? AND client_id = ?',
      whereArgs: [collection.name, clientId],
    );
  }

  /// 閱讀位置的下載游標（epic-8-sync Issue 5，補上 spec.md 原始設計
  /// 遺漏的「本機無 dirty 異動、但其他裝置已更新過」情境，見
  /// plan-issue-5.md「審查修正紀錄」Critical #1）：`last_pulled_server_updated_at_reading_positions`
  /// 欄位自 Issue 1（v16→v17 migration）就已存在，但直到本 Issue 才真正
  /// 被使用——刻意不套用既有 `_cursorColumns`／`SyncCollection` 那套機制
  /// （`sync_reading_positions` 的資料形狀與其餘 3 個 collection 本質
  /// 不同，見 plan-issue-5.md「與 spec.md 的落差說明」第 1 點），改用
  /// 獨立的方法直接存取這個欄位。
  Future<String?> loadReadingPositionsCursor() async {
    final rows = await _db.query('sync_metadata', where: 'id = 1');
    return rows.single['last_pulled_server_updated_at_reading_positions'] as String?;
  }

  Future<void> saveReadingPositionsCursor(String value) {
    return _db.update(
      'sync_metadata',
      {'last_pulled_server_updated_at_reading_positions': value},
      where: 'id = 1',
    );
  }
}
