import 'package:flutter/services.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sqflite/sqflite.dart';

import '../library/book_content_fingerprint.dart';
import '../library/library_repository.dart';
import '../library/models/library_enums.dart';
import 'sync_account_repository.dart';
import 'sync_client.dart';
import 'sync_merge.dart';
import 'sync_metadata_repository.dart';
import 'sync_models.dart';
import 'sync_push_planner.dart';
import 'sync_table_specs.dart';

/// 雲端同步引擎核心（epic-8-sync Issue 4，spec.md「同步引擎」）：本 Issue
/// 只實作劃線/備註/書籤的推送/下載/合併與本機墓碑清理；閱讀位置的衝突
/// 預檢由 Issue 5 擴充同一個 [runCheckpoint]；三種觸發來源與併發鎖由
/// Issue 6 負責，本 Issue 的 [runCheckpoint] 僅需可被手動/測試呼叫。
///
/// **給 Issue 6 實作者的例外處理提醒**（審查意見 Minor #1，2026-08-04
/// `/superpowers:requesting-code-review`，見文末「審查修正紀錄」）：
/// [runCheckpoint] 只捕捉網路層的 `ClientException`（PocketBase SDK
/// 統一封裝的 HTTP 錯誤），**不**捕捉本機 SQLite 操作可能拋出的
/// `DatabaseException`（例如磁碟空間不足）——這是刻意的，本 Issue 不吞
/// 掉未預期的本機例外。Issue 6 規劃的 `_isSyncing` 執行鎖，呼叫
/// [runCheckpoint] 時**必須**用 `try { await runCheckpoint(); } finally
/// { _isSyncing = false; }` 包住，否則任何一次未預期的本機例外都會讓鎖
/// 永久卡住（需要重開 App 才能恢復），而不能假設 [runCheckpoint] 永遠
/// 不會拋出例外。
class SyncEngine {
  final Database _db;
  final SyncAccountRepository _accountRepository;
  final SyncMetadataRepository _metadataRepository;
  final PocketBaseClientFactory _clientFactory;

  SyncEngine({
    required Database db,
    required SyncAccountRepository accountRepository,
    required SyncMetadataRepository metadataRepository,
    PocketBaseClientFactory? clientFactory,
  })  : _db = db,
        _accountRepository = accountRepository,
        _metadataRepository = metadataRepository,
        _clientFactory = clientFactory ?? PocketBase.new;

  Future<void> runCheckpoint() async {
    final baseUrl = await _accountRepository.loadBaseUrl();
    final authToken = await _accountRepository.loadAuthToken();
    final userId = await _accountRepository.loadUserId();
    if (authToken == null || userId == null || baseUrl.isEmpty) return;

    final pb = _clientFactory(baseUrl);
    final headers = {'Authorization': authToken};
    final lastPushCompletedAt = await _metadataRepository.loadLastPushCompletedAt();

    final joinedRowsByCollection = <SyncCollection, List<Map<String, Object?>>>{};
    for (final spec in syncTableSpecs.values) {
      joinedRowsByCollection[spec.collection] =
          await _queryDirtyRows(spec.collection, lastPushCompletedAt);
    }

    await _backfillMissingFingerprints(joinedRowsByCollection);

    final allOperations = <PushOperation>[];
    for (final spec in syncTableSpecs.values) {
      final remoteIds = await _metadataRepository.loadRemoteIds(spec.collection);
      allOperations.addAll(buildPushOperations(
        spec: spec,
        joinedRows: joinedRowsByCollection[spec.collection]!,
        remoteIdsByClientId: remoteIds,
        userId: userId,
      ));
    }

    try {
      for (final batch in planPushBatches(allOperations)) {
        await _sendPushBatch(pb, headers, batch);
      }
    } on ClientException {
      return;
    }

    final notDirtyUpdatedAt = DateTime.now().millisecondsSinceEpoch;
    final pulledCursors = <SyncCollection, String?>{};

    try {
      await _resolvePendingRecords(notDirtyUpdatedAt: notDirtyUpdatedAt);
      for (final spec in syncTableSpecs.values) {
        pulledCursors[spec.collection] = await _downloadAndMerge(
          pb,
          headers,
          spec,
          notDirtyUpdatedAt: notDirtyUpdatedAt,
        );
      }
    } on ClientException {
      return;
    }

    await _metadataRepository.saveLastPushCompletedAt(notDirtyUpdatedAt);
    for (final entry in pulledCursors.entries) {
      final cursor = entry.value;
      if (cursor != null) {
        await _metadataRepository.savePulledCursor(entry.key, cursor);
      }
    }

    await _purgeTombstones();
  }

  /// 記憶體風險註記（審查意見 Important #2，與 `_downloadAndMerge()` 的
  /// `getFullList()` 是同一類風險，見 Task 8 該方法的說明／文末「審查
  /// 修正紀錄」）：一次性 `rawQuery` 載入該 collection 全部 dirty 列，
  /// 極端情況（單次 checkpoint 待推送異動筆數極多）可能有記憶體壓力，
  /// 目前評估暫不需要分頁讀取，先記錄於此供日後追蹤。
  Future<List<Map<String, Object?>>> _queryDirtyRows(
    SyncCollection collection,
    int? lastPushCompletedAt,
  ) async {
    final table = collection.localTable;
    final rows = await _db.rawQuery(
      'SELECT $table.*, books.content_fingerprint AS book_fingerprint '
      'FROM $table JOIN books ON $table.book_id = books.id '
      'WHERE $table.updated_at > ?',
      [lastPushCompletedAt ?? 0],
    );
    return rows.map((row) => Map<String, Object?>.from(row)).toList();
  }

  /// 對本次牽涉、但尚無指紋的書籍即時補算並回填（epic-8-sync Issue 3
  /// 「首次觸發同步時才補算回填」，回填時機由本 Issue 決定，見
  /// plan-issue-4.md「與 issues.md／spec.md 的落差說明」第 3 點）：只處理
  /// 「這次有 dirty 標註列、但所屬書籍還沒有指紋」的書籍，不對整個圖書庫
  /// 掃描補算（YAGNI——沒有待推送異動的書籍，指紋在本 Issue 範圍內不影響
  /// 任何行為）。
  Future<void> _backfillMissingFingerprints(
    Map<SyncCollection, List<Map<String, Object?>>> joinedRowsByCollection,
  ) async {
    final bookIdsNeedingFingerprint = <String>{
      for (final rows in joinedRowsByCollection.values)
        for (final row in rows)
          if (row['book_fingerprint'] == null) row['book_id'] as String,
    };
    if (bookIdsNeedingFingerprint.isEmpty) return;

    final fingerprintByBookId = <String, String>{};
    for (final bookId in bookIdsNeedingFingerprint) {
      final bookRows =
          await _db.query('books', where: 'id = ?', whereArgs: [bookId]);
      if (bookRows.isEmpty) continue;
      final filePath = bookRows.single['filePath'] as String;
      final format = BookFileFormat.values.byName(bookRows.single['format'] as String);
      String? epubIdentifier;
      if (format == BookFileFormat.epub) {
        try {
          final metadata = await kBookMetadataChannel.invokeMapMethod<String, Object?>(
            'extractMetadata',
            {'uri': filePath, 'format': format.name},
          );
          epubIdentifier = metadata?['identifier'] as String?;
        } on PlatformException {
          // 取得 OPF identifier 失敗：忽略，退回 SHA-256（比照匯入流程既有慣例，
          // 見 book_import_service_impl.dart）。
        }
      }
      try {
        final fingerprint = await computeBookContentFingerprint(
          filePath,
          format,
          epubIdentifier: epubIdentifier,
        );
        await _db.update(
          'books',
          {'content_fingerprint': fingerprint},
          where: 'id = ?',
          whereArgs: [bookId],
        );
        fingerprintByBookId[bookId] = fingerprint;
      } catch (_) {
        // 補算失敗：這本書這次不參與推送，其 dirty 列在下方被跳過，下次
        // checkpoint 會重新嘗試（比照 epic-17 detectAndCacheEpubLayout()
        // 一次性補判斷模式的失敗容忍精神）。
      }
    }

    for (final rows in joinedRowsByCollection.values) {
      for (final row in rows) {
        if (row['book_fingerprint'] == null) {
          row['book_fingerprint'] = fingerprintByBookId[row['book_id']];
        }
      }
    }
  }

  Future<void> _sendPushBatch(
    PocketBase pb,
    Map<String, String> headers,
    List<PushOperation> batch,
  ) async {
    final request = pb.createBatch();
    for (final op in batch) {
      if (op.remoteId == null) {
        request.collection(op.collection.remoteCollection).create(body: op.body);
      } else {
        request.collection(op.collection.remoteCollection).update(op.remoteId!, body: op.body);
      }
    }
    final results = await request.send(headers: headers);
    for (var i = 0; i < batch.length; i++) {
      if (batch[i].remoteId == null) {
        final body = results[i].body;
        if (body is Map) {
          final createdId = body['id'] as String?;
          if (createdId != null) {
            await _metadataRepository.saveRemoteId(
              batch[i].collection,
              batch[i].body['client_id'] as String,
              createdId,
            );
          }
        }
      }
    }
  }

  Future<void> _resolvePendingRecords({required int notDirtyUpdatedAt}) async {
    for (final record in await _metadataRepository.listPendingRecords()) {
      final bookRows = await _db.query(
        'books',
        columns: ['id', 'format'],
        where: 'content_fingerprint = ?',
        whereArgs: [record.bookFingerprint],
      );
      if (bookRows.isEmpty) continue;
      final bookId = bookRows.single['id'] as String;
      final format = BookFileFormat.values.byName(bookRows.single['format'] as String);
      final spec = syncTableSpecs[record.collection]!;
      final localRow = {
        'id': record.clientId,
        'book_id': bookId,
        'deleted_at': record.deletedAt,
        'updated_at': notDirtyUpdatedAt,
        ...spec.buildLocalFields(record.fields, format),
      };
      await _db.insert(
        spec.collection.localTable,
        localRow,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _metadataRepository.saveRemoteId(record.collection, record.clientId, record.remoteId);
      await _metadataRepository.deletePendingRecord(record.collection, record.clientId);
    }
  }

  Future<String?> _downloadAndMerge(
    PocketBase pb,
    Map<String, String> headers,
    SyncTableSpec spec, {
    required int notDirtyUpdatedAt,
  }) async {
    final cursor = await _metadataRepository.loadPulledCursor(spec.collection);
    final filter = cursor == null ? null : 'updated > "$cursor"';
    final records = await pb.collection(spec.collection.remoteCollection).getFullList(
          filter: filter,
          sort: 'updated',
          headers: headers,
        );
    if (records.isEmpty) return cursor;

    final fingerprints = records
        .map((r) => r.data['book_fingerprint'] as String?)
        .whereType<String>()
        .toSet();
    final booksByFingerprint = await _loadBooksByFingerprint(fingerprints);

    for (final remote in records) {
      final input = RemoteRecordMergeInput(
        remoteId: remote.data['id'] as String,
        clientId: remote.data['client_id'] as String,
        bookFingerprint: remote.data['book_fingerprint'] as String?,
        deletedAt: normalizeDeletedAt(remote.data['deleted_at']),
        rawFields: spec.extractRawFields(remote),
      );
      final decision = resolveMergeDecision(
        spec: spec,
        input: input,
        booksByFingerprint: booksByFingerprint,
        notDirtyUpdatedAt: notDirtyUpdatedAt,
      );
      if (decision.resolved) {
        await _db.insert(
          spec.collection.localTable,
          decision.localRow!,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await _metadataRepository.saveRemoteId(spec.collection, input.clientId, input.remoteId);
      } else if (input.bookFingerprint != null) {
        // `resolveMergeDecision()` 對「book_fingerprint 本身為 null」與
        // 「查無對應本機書籍」皆回傳 resolved: false（見 sync_merge.dart
        // 的防禦性測試），呼叫端必須分開處理：後者才是真正的「待處理
        // 佇列」情境；前者代表遠端紀錄本身缺漏這個必要欄位，沒有指紋
        // 可供之後比對，寫進待處理佇列也永遠不會被解析，因此直接跳過
        // 這一筆（審查意見 Important #2，2026-08-04 第二輪
        // `/superpowers:requesting-code-review`，見文末「審查修正
        // 紀錄」：原本無條件 `input.bookFingerprint!` 在這個分支會拋出
        // 空指標例外）。
        await _metadataRepository.savePendingRecord(
          collection: spec.collection,
          clientId: input.clientId,
          bookFingerprint: input.bookFingerprint!,
          remoteId: input.remoteId,
          deletedAt: input.deletedAt,
          fields: input.rawFields,
        );
      }
    }

    return maxUpdatedCursor(
      records.map((r) => r.data['updated'] as String).toList(),
      cursor,
    );
  }

  /// 每次查詢最多帶入的指紋數量——與 `_purgeTombstones()` 的
  /// `_tombstonePurgeChunkSize` 同一類風險（審查意見 Important #1，
  /// 2026-08-04 第二輪 `/superpowers:requesting-code-review`，見文末
  /// 「審查修正紀錄」）：全新裝置首次對一個已累積大量書籍/標註的既有
  /// 帳號執行 checkpoint 時，單次下載回來的紀錄可能橫跨遠超過 SQLite
  /// 單一陳述式變數上限（Android 常見建置預設 999）的不同 book_fingerprint，
  /// 原本未分批的 `IN (...)` 查詢會在這個核心情境下拋出
  /// `too many SQL variables` 而崩潰。
  static const _fingerprintLookupChunkSize = 500;

  Future<Map<String, BookLookup>> _loadBooksByFingerprint(Set<String> fingerprints) async {
    if (fingerprints.isEmpty) return {};
    final fingerprintList = fingerprints.toList();
    final result = <String, BookLookup>{};
    for (var i = 0; i < fingerprintList.length; i += _fingerprintLookupChunkSize) {
      final end = (i + _fingerprintLookupChunkSize < fingerprintList.length)
          ? i + _fingerprintLookupChunkSize
          : fingerprintList.length;
      final chunk = fingerprintList.sublist(i, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await _db.query(
        'books',
        columns: ['id', 'format', 'content_fingerprint'],
        where: 'content_fingerprint IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final row in rows) {
        result[row['content_fingerprint'] as String] = BookLookup(
          id: row['id'] as String,
          format: BookFileFormat.values.byName(row['format'] as String),
        );
      }
    }
    return result;
  }

  static const _tombstonePurgeChunkSize = 500;

  Future<void> _purgeTombstones() async {
    final now = DateTime.now();
    for (final collection in SyncCollection.values) {
      final table = collection.localTable;
      final rows = await _db.query(
        table,
        columns: ['id', 'deleted_at'],
        where: 'deleted_at IS NOT NULL',
      );
      final idsToDelete = idsPastTombstoneRetention(rows: rows, now: now);
      for (var i = 0; i < idsToDelete.length; i += _tombstonePurgeChunkSize) {
        final end = (i + _tombstonePurgeChunkSize < idsToDelete.length)
            ? i + _tombstonePurgeChunkSize
            : idsToDelete.length;
        final chunk = idsToDelete.sublist(i, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        await _db.delete(table, where: 'id IN ($placeholders)', whereArgs: chunk);
      }
    }
  }
}
