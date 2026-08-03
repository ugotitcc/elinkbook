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
      return; // 同步失敗：整批放棄，不更新任何 sync_metadata 游標
    }

    // `lastPushCompletedAt` 刻意不在這裡寫入——spec.md「同步引擎」步驟 7
    // 要求「不局部套用已完成的步驟」，若推送一成功就立刻持久化，下載
    // 階段（Task 8）萬一失敗會違反這個原子性要求。實際持久化時機挪到
    // Task 8：整個 checkpoint（推送＋下載）皆成功後才一次寫入所有游標
    // （見文末「審查修正紀錄」）。下載/合併/墓碑清理見 Task 8（本方法
    // 於該 Task 接續擴充）。
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
}
