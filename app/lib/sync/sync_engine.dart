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
import 'sync_reading_position.dart';
import 'sync_table_specs.dart';

/// 雲端同步引擎核心（epic-8-sync Issue 4，spec.md「同步引擎」）：本 Issue
/// 只實作劃線/備註/書籤的推送/下載/合併與本機墓碑清理；閱讀位置的衝突
/// 預檢由 Issue 5 擴充同一個 [runCheckpoint]；三種觸發來源由 Issue 6
/// 負責接上（見 `sync_checkpoint_trigger.dart`），本 Issue 的
/// [runCheckpoint] 僅需可被手動/測試呼叫。
///
/// **例外處理與併發鎖**（審查意見 Minor #1，2026-08-04
/// `/superpowers:requesting-code-review`；併發鎖由 epic-8-sync Issue 6
/// 實作，見 [_isSyncing]）：[runCheckpoint] 只捕捉網路層的
/// `ClientException`（PocketBase SDK 統一封裝的 HTTP 錯誤），**不**捕捉
/// 本機 SQLite 操作可能拋出的 `DatabaseException`（例如磁碟空間不足）
/// ——這是刻意的，本 Issue 不吞掉未預期的本機例外。[runCheckpoint] 內部
/// 一律用 `try { await _runCheckpointBody(); } finally { _isSyncing =
/// false; }` 包住實際執行內容，確保任何一次未預期的本機例外都不會讓鎖
/// 永久卡住（不需要呼叫端自行處理，也不能假設 [runCheckpoint] 永遠不會
/// 拋出例外）。
class SyncEngine {
  final Database _db;
  final SyncAccountRepository _accountRepository;
  final SyncMetadataRepository _metadataRepository;
  final PocketBaseClientFactory _clientFactory;

  /// 見建構子 [onReadingPositionConflict] 參數說明。
  ///
  /// **與併發鎖的互動**（審查意見 Minor #1，2026-08-04
  /// `/superpowers:requesting-code-review`；epic-8-sync Issue 6 實作
  /// [_isSyncing]）：這個回呼被呼叫時 [runCheckpoint] 會 `await` 它，
  /// 直到使用者做出選擇（或關閉對話框）才會繼續——若使用者放著對話框
  /// 不理，`runCheckpoint()` 會無限期停滯。[runCheckpoint] 內部的
  /// `try { ... } finally { _isSyncing = false; }` 保證鎖本身不會因此
  /// 洩漏，但使用者放著對話框不理期間，後續的 checkpoint 觸發都會因為
  /// 鎖已被佔用而直接放棄——這是可接受的行為（比照「同步失敗」的靜默
  /// 重試精神，等使用者處理完對話框、下一次觸發自然會繼續），
  /// `showReadingPositionConflictDialog()` 在使用者點擊對話框外部區域時
  /// 會正確回傳 `null`（見 `reading_position_conflict_dialog.dart` 既有
  /// 測試），不會讓 `runCheckpoint()` 真的卡死。
  final ReadingPositionConflictResolver? _onReadingPositionConflict;

  SyncEngine({
    required Database db,
    required SyncAccountRepository accountRepository,
    required SyncMetadataRepository metadataRepository,
    PocketBaseClientFactory? clientFactory,
    ReadingPositionConflictResolver? onReadingPositionConflict,
  })  : _db = db,
        _accountRepository = accountRepository,
        _metadataRepository = metadataRepository,
        _clientFactory = clientFactory ?? PocketBase.new,
        _onReadingPositionConflict = onReadingPositionConflict;

  /// epic-8-sync Issue 6（spec.md「同步引擎」併發防護）：SyncEngine 內建
  /// 單一執行鎖，避免三種 checkpoint 觸發來源（App 背景化／書籍切換／5
  /// 分鐘閒置計時器，見 `sync_checkpoint_trigger.dart`）短時間內幾乎同時
  /// 呼叫 [runCheckpoint] 時真的同時送出兩份網路請求。鎖定期間的後續
  /// 呼叫直接放棄（不排隊），比照「同步失敗」的靜默重試精神——放棄的那次
  /// 呼叫所代表的本機異動，下一次任何 checkpoint 自然會涵蓋到。
  bool _isSyncing = false;

  /// 回傳值供手動同步入口（`SyncSettingsScreen`「立即同步」按鈕，
  /// 2026-09-08 `/grill-with-docs` 使用者需求）判斷這次呼叫是否真的完成
  /// 一輪成功的 checkpoint，藉此決定要不要提示使用者同步失敗；三種既有
  /// 自動觸發來源（`sync_checkpoint_trigger.dart`）不需要這個回傳值，
  /// 沿用既有「失敗就靜默、下次觸發自然重試」精神，忽略即可。
  Future<bool> runCheckpoint() async {
    if (_isSyncing) return false;
    _isSyncing = true;
    try {
      return await _runCheckpointBody();
    } finally {
      _isSyncing = false;
    }
  }

  Future<bool> _runCheckpointBody() async {
    final baseUrl = await _accountRepository.loadBaseUrl();
    final storedAuthToken = await _accountRepository.loadAuthToken();
    final userId = await _accountRepository.loadUserId();
    if (storedAuthToken == null || userId == null || baseUrl.isEmpty) return false;

    final pb = _clientFactory(baseUrl);
    final String? authToken;
    try {
      authToken = await _refreshAuthToken(pb, storedAuthToken);
    } on ClientException catch (e) {
      // 401：token 已過期或失效，續期不可能成功，只能請使用者重新登入。
      // 只清 token、保留 email，讓同步設定畫面顯示「登入已過期」並預填
      // email（見 SyncAccountRepository.clearAuthToken）。其他錯誤（斷網、
      // 伺服器 5xx）維持登入，下次 checkpoint 自然重試。
      // 請求進行中使用者已重新登入（token 已換）時不清除，避免清掉新 token。
      if (e.statusCode == 401 &&
          await _accountRepository.loadAuthToken() == storedAuthToken) {
        await _accountRepository.clearAuthToken();
      }
      return false;
    }
    if (authToken == null) return false;
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

    Map<String, String> positionsToConfirm;
    Set<String> dirtyReadingPositionFingerprints;
    Set<String> deferredReadingPositionBookIds;
    try {
      // epic-8-sync Issue 5：閱讀位置衝突預檢＋推送，須在其餘標註推送之前
      // 完成（spec.md「同步引擎」步驟 1），仍在同一個 try 區塊內——任一
      // 環節的網路例外都應讓整個 checkpoint 視為失敗（見 plan-issue-5.md
      // 「與 spec.md 的落差說明」第 1 點：獨立的 Batch 請求，非與標註
      // 異動合併成同一個實體 HTTP 請求）。
      final readingPositionSyncResult =
          await _syncReadingPositions(pb, headers, lastPushCompletedAt, userId);
      positionsToConfirm = readingPositionSyncResult.positionsToConfirm;
      dirtyReadingPositionFingerprints = readingPositionSyncResult.dirtyFingerprints;
      deferredReadingPositionBookIds = readingPositionSyncResult.deferredBookIds;

      for (final batch in planPushBatches(allOperations)) {
        await _sendPushBatch(pb, headers, batch);
      }
    } on ClientException {
      return false;
    }

    final notDirtyUpdatedAt = DateTime.now().millisecondsSinceEpoch;
    final pulledCursors = <SyncCollection, String?>{};
    String? readingPositionsPulledCursor;

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
      // epic-8-sync Issue 5（審查修正紀錄 Critical #1，2026-08-04
      // `/superpowers:requesting-code-review`，見文末「審查修正紀錄」）：
      // 補上 spec.md 原始設計遺漏的情境——本機從未變動過位置、但其他
      // 裝置已推送新進度的書籍，步驟 1 的衝突預檢完全不會碰到它們（本機
      // 不 dirty），必須靠這個獨立的下載步驟才會學到新進度。
      readingPositionsPulledCursor = await _downloadReadingPositions(
        pb,
        headers,
        excludeFingerprints: dirtyReadingPositionFingerprints,
      );
    } on ClientException {
      return false;
    }

    await _metadataRepository.saveLastPushCompletedAt(notDirtyUpdatedAt);
    for (final entry in pulledCursors.entries) {
      final cursor = entry.value;
      if (cursor != null) {
        await _metadataRepository.savePulledCursor(entry.key, cursor);
      }
    }
    if (readingPositionsPulledCursor != null) {
      await _metadataRepository.saveReadingPositionsCursor(readingPositionsPulledCursor);
    }
    // epic-8-sync Issue 5：與 lastPushCompletedAt／下載游標同一時機才
    // 寫入，理由同上——確保推送+下載整個 checkpoint 皆成功後才一次寫
    // 入，維持 Issue 4 已確立的原子性保證（見 plan-issue-4.md「審查修正
    // 紀錄」）。
    for (final entry in positionsToConfirm.entries) {
      await _db.update(
        'books',
        {'position_synced_server_updated_at': entry.value},
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }

    // epic-8-sync Issue 5（最終全分支審查修正，2026-08-04）：偵測到衝突
    // 但本輪無法取得使用者決定（無 resolver 或使用者關閉對話框）的書籍，
    // 若放著 position_updated_at 不動，上面已寫入的 lastPushCompletedAt
    // 會前進到超過它，導致下次 checkpoint 的 dirty 判定
    // （position_updated_at > lastPushCompletedAt）變成 false——本機
    // 待推送的位置因此被靜默丟棄，而不是原本設計的「跳過、留待下次
    // 重試」。把這些書籍的 position_updated_at 蓋成比這次的
    // notDirtyUpdatedAt（也就是下次 checkpoint 的 lastPushCompletedAt）
    // 還新，確保下次 checkpoint 仍會判定為 dirty、重新走一次衝突預檢。
    for (final bookId in deferredReadingPositionBookIds) {
      await _db.update(
        'books',
        {'position_updated_at': notDirtyUpdatedAt + 1},
        where: 'id = ?',
        whereArgs: [bookId],
      );
    }

    await _purgeTombstones();
    return true;
  }

  /// epic-50-sync-token-refresh：PocketBase token 有效期從登入（或上次
  /// 續期）起算，過期後所有請求都回 401。每次 checkpoint 開頭先用目前的
  /// token 呼叫 `authRefresh` 換一張新的並存回——只要在有效期內同步過一次，
  /// token 就會持續續期，不需要登出再登入。
  ///
  /// 回傳 `null` 代表續期請求進行中帳號已變動（使用者登出或重新登入，
  /// 儲存的 token 已不是這次拿去續期的那張）：不寫回新 token（否則登出後
  /// 會變成「有 token 但沒有 email／userId」的半登入狀態），本輪同步放棄。
  Future<String?> _refreshAuthToken(PocketBase pb, String authToken) async {
    final authData = await pb
        .collection('users')
        .authRefresh(headers: {'Authorization': authToken});
    if (await _accountRepository.loadAuthToken() != authToken) return null;
    await _accountRepository.saveAuthToken(authData.token);
    return authData.token;
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
      final fingerprint = await _backfillFingerprintForBook(bookId);
      if (fingerprint != null) {
        fingerprintByBookId[bookId] = fingerprint;
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

  /// 對單一書籍計算並回填 `content_fingerprint`（epic-8-sync Issue 3；
  /// 抽出為獨立方法供 [_backfillMissingFingerprints]〔標註異動觸發〕與
  /// `_syncReadingPositions`〔閱讀位置異動觸發，epic-8-sync Issue 5〕
  /// 共用，避免重複 EPUB identifier 擷取與 SHA-256 計算邏輯）。計算失敗
  /// （原生端例外／檔案讀取失敗）時回傳 `null`，呼叫端決定如何降級
  /// （比照既有慣例，這本書這次跳過，下次 checkpoint 重新嘗試）。
  Future<String?> _backfillFingerprintForBook(String bookId) async {
    final bookRows = await _db.query('books', where: 'id = ?', whereArgs: [bookId]);
    if (bookRows.isEmpty) return null;
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
      return fingerprint;
    } catch (_) {
      return null;
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

  /// 閱讀位置推送每批最多帶入的筆數——與 PocketBase Batch API 上限一致
  /// （見 Issue 4 `planPushBatches()` 的同一個數字），審查意見 Important
  /// #1 發現本檔案原本漏了這個限制，見文末「審查修正紀錄」。
  static const _readingPositionPushChunkSize = 100;

  /// 推送階段的閱讀位置衝突預檢＋推送（epic-8-sync Issue 5，spec.md
  /// 「同步引擎」步驟 1）：只處理本機有 dirty 位置異動的書籍（見
  /// `WHERE position_updated_at > ?`），依 [resolveReadingPositionAction]
  /// 判定結果分三路——不需要動作、直接推送、或呼叫
  /// [_onReadingPositionConflict] 詢問使用者。回傳值同時帶出這次成功
  /// 確認同步的書籍（positionsToConfirm，用於延後寫入
  /// `position_synced_server_updated_at`）、這次視為 dirty 的書籍指紋
  /// 集合（dirtyFingerprints，供 [_downloadReadingPositions] 排除，
  /// 避免下載階段用舊快照覆寫這裡剛做的決定）、以及因無法取得使用者
  /// 決定而延後的書籍 id 集合（deferredBookIds，供 [runCheckpoint]
  /// 重新標記為 dirty，確保下次 checkpoint 重試）。
  Future<
      ({
        Map<String, String> positionsToConfirm,
        Set<String> dirtyFingerprints,
        Set<String> deferredBookIds
      })> _syncReadingPositions(
    PocketBase pb,
    Map<String, String> headers,
    int? lastPushCompletedAt,
    String userId,
  ) async {
    final dirtyRows = await _db.query(
      'books',
      columns: [
        'id',
        'title',
        'format',
        'content_fingerprint',
        'epubLocator',
        'pdfPageIndex',
        'progress',
        'position_updated_at',
        'position_synced_server_updated_at',
      ],
      where: 'position_updated_at > ?',
      whereArgs: [lastPushCompletedAt ?? 0],
    );
    if (dirtyRows.isEmpty) {
      return (
        positionsToConfirm: <String, String>{},
        dirtyFingerprints: <String>{},
        deferredBookIds: <String>{},
      );
    }

    final dirtyFingerprints = <String>{};
    final deferredBookIds = <String>{};
    final toPush = <_ReadingPositionPushItem>[];
    for (final row in dirtyRows) {
      final bookId = row['id'] as String;
      var fingerprint = row['content_fingerprint'] as String?;
      fingerprint ??= await _backfillFingerprintForBook(bookId);
      if (fingerprint == null) continue; // 補算失敗：這本書這次跳過，下次 checkpoint 重試
      dirtyFingerprints.add(fingerprint);

      final format = BookFileFormat.values.byName(row['format'] as String);
      final local = ReadingPositionSnapshot(
        epubLocatorJson: row['epubLocator'] as String?,
        pdfPageIndex: row['pdfPageIndex'] as int?,
        progress: (row['progress'] as num).toDouble(),
      );
      final syncedServerUpdatedAt = row['position_synced_server_updated_at'] as String?;

      // 用 pb.filter() 安全帶入 fingerprint，而非字串內插（審查意見
      // Important #2，2026-08-04 `/superpowers:requesting-code-review`，
      // 見文末「審查修正紀錄」）：EPUB 指紋優先取自 OPF `dc:identifier`
      // （見 epic-8-sync Issue 3），是書籍檔案內部的任意字串，並非本專案
      // 自己產生的可信值，若剛好含有雙引號會破壞 filter 語法；
      // `pb.filter()` 是 PocketBase Dart SDK 官方提供的具名參數安全綁定
      // 語法，自動處理特殊字元逸出。
      // epic-8-sync Issue 9：加上確定性排序（'created'，不受後續 update
      // 影響的欄位）——unique index 套用後 (user, book_fingerprint)
      // 理論上至多 1 筆，這裡純粹是防禦性語意：查詢行為本身不依賴
      // PocketBase 未指定 sort 時的預設排序保證（見 issues.md Issue 9）。
      // 相依於 `created` autodate 欄位存在（migration
      // `1785801600_add_created_updated_autodate_fields.js`）——若某個
      // PocketBase 實例只套用過 `1785715200_...` 舊版、沒有這個欄位，
      // 這裡會直接收到 400（未知的 sort 欄位），push 階段快速失敗；這是
      // 可接受的 fail-fast（該環境本來就缺 `created`/`updated`，衝突
      // 判定邏輯本來就不可靠，見 `pocketbase-self-hosting.md`）。
      final result = await pb.collection('sync_reading_positions').getList(
            filter: pb.filter('book_fingerprint = {:fp}', {'fp': fingerprint}),
            perPage: 1,
            sort: 'created',
            headers: headers,
          );
      final existing = result.items.isEmpty ? null : result.items.first;
      final remoteServerUpdated = existing?.data['updated'] as String?;

      final action = resolveReadingPositionAction(
        positionUpdatedAt: row['position_updated_at'] as int?,
        lastPushCompletedAt: lastPushCompletedAt,
        positionSyncedServerUpdatedAt: syncedServerUpdatedAt,
        remoteServerUpdated: remoteServerUpdated,
      );

      switch (action) {
        case ReadingPositionSyncAction.noAction:
          break;
        case ReadingPositionSyncAction.pushLocalDirectly:
          toPush.add(_ReadingPositionPushItem(
            bookId: bookId,
            fingerprint: fingerprint,
            remoteId: existing?.data['id'] as String?,
            local: local,
          ));
          break;
        case ReadingPositionSyncAction.needsUserDecision:
          final resolver = _onReadingPositionConflict;
          if (resolver == null) {
            // 無可用 UI（例如背景觸發）：本輪跳過。position_updated_at
            // 會在 runCheckpoint() 結尾被蓋成比這次 lastPushCompletedAt
            // 還新，確保下次 checkpoint 仍視為 dirty、重新走一次衝突
            // 預檢（2026-08-04 最終全分支審查修正——修正前這裡的「下次
            // 重試」只是註解宣稱，實際上 lastPushCompletedAt 前進後
            // 這本書會永遠不再被判定為 dirty，本機異動被靜默丟棄）。
            deferredBookIds.add(bookId);
            break;
          }
          final remote = ReadingPositionSnapshot(
            epubLocatorJson: existing!.data['epub_locator'] as String?,
            pdfPageIndex: (existing.data['pdf_page_index'] as num?)?.toInt(),
            progress: (existing.data['progress'] as num).toDouble(),
          );
          final choice = await resolver(ReadingPositionConflict(
            bookId: bookId,
            bookTitle: row['title'] as String,
            format: format,
            local: local,
            remote: remote,
          ));
          if (choice == ReadingPositionChoice.keepLocal) {
            toPush.add(_ReadingPositionPushItem(
              bookId: bookId,
              fingerprint: fingerprint,
              remoteId: existing.data['id'] as String?,
              local: local,
            ));
          } else if (choice == ReadingPositionChoice.keepCloud) {
            // 使用者已明確決定採用雲端版本：立即覆寫本機（比照 Issue 4
            // 下載合併寫入既有慣例——這是已確定的資料寫入，非游標
            // bookkeeping，不需要延後到 checkpoint 結束，見
            // plan-issue-4.md「審查修正紀錄」對兩者的區分）；
            // position_updated_at 設為不大於 lastPushCompletedAt 的值，
            // 避免下次 checkpoint 又被誤判為待推送的本機異動。
            await _db.update(
              'books',
              {
                'epubLocator': remote.epubLocatorJson,
                'pdfPageIndex': remote.pdfPageIndex,
                'progress': remote.progress,
                'position_updated_at': lastPushCompletedAt ?? 0,
                'position_synced_server_updated_at': remoteServerUpdated,
              },
              where: 'id = ?',
              whereArgs: [bookId],
            );
          } else {
            // choice 為 null（使用者關閉對話框未決定）：本輪跳過，理由
            // 同上——加入 deferredBookIds 確保下次 checkpoint 重試。
            deferredBookIds.add(bookId);
          }
          break;
      }
    }

    if (toPush.isEmpty) {
      return (
        positionsToConfirm: <String, String>{},
        dirtyFingerprints: dirtyFingerprints,
        deferredBookIds: deferredBookIds,
      );
    }

    // 分批送出（審查意見 Important #1，2026-08-04
    // `/superpowers:requesting-code-review`，見文末「審查修正紀錄」）：
    // 與 Issue 4 標註推送同一個 PocketBase Batch API 上限（100 筆/批，
    // 見 sync_push_planner.dart `planPushBatches()`）。閱讀位置絕大多數
    // checkpoint 只有 1 筆（目前正在讀的書），但長時間離線後一次累積
    // 大量書籍的位置異動時仍可能超過上限，比照本檔案既有的
    // `_purgeTombstones()`／`_loadBooksByFingerprint()` 分批慣例處理，
    // 不引入新的抽象。
    final positionsToConfirm = <String, String>{};
    for (var i = 0; i < toPush.length; i += _readingPositionPushChunkSize) {
      final end = (i + _readingPositionPushChunkSize < toPush.length)
          ? i + _readingPositionPushChunkSize
          : toPush.length;
      final chunk = toPush.sublist(i, end);

      final request = pb.createBatch();
      for (final item in chunk) {
        final body = <String, Object?>{
          'user': userId,
          'book_fingerprint': item.fingerprint,
          'epub_locator': item.local.epubLocatorJson,
          'pdf_page_index': item.local.pdfPageIndex,
          'progress': item.local.progress,
        };
        if (item.remoteId == null) {
          request.collection('sync_reading_positions').create(body: body);
        } else {
          request.collection('sync_reading_positions').update(item.remoteId!, body: body);
        }
      }
      final results = await request.send(headers: headers);

      for (var j = 0; j < chunk.length; j++) {
        final body = results[j].body;
        if (body is Map) {
          final updated = body['updated'] as String?;
          if (updated != null) {
            positionsToConfirm[chunk[j].bookId] = updated;
          }
        }
      }
    }
    return (
      positionsToConfirm: positionsToConfirm,
      dirtyFingerprints: dirtyFingerprints,
      deferredBookIds: deferredBookIds,
    );
  }

  /// 下載其他裝置對閱讀位置的異動（epic-8-sync Issue 5，補上 spec.md
  /// 原始設計遺漏的情境，見文末「審查修正紀錄」Critical #1）：對整個
  /// `sync_reading_positions` collection 查詢「自上次游標以來的所有
  /// 變動」，**不限於本機有 dirty 異動的書籍**——與 [_syncReadingPositions]
  /// 互補，該方法只處理「本機有待推送異動」的書籍，這個方法處理「本機
  /// 從未變動過、但其他裝置已經更新過」的書籍。
  ///
  /// 下載到的紀錄若 `book_fingerprint` 對得上本機既有書籍，直接覆寫本機
  /// 閱讀位置（這些書籍依定義沒有本機待推送異動，不可能發生衝突，見
  /// plan-issue-5.md「與 spec.md 的落差說明」）；對不上本機任何書籍者
  /// 直接略過，不落地暫存（理由見同一節說明第 5 點）。回傳這次應寫回
  /// `sync_metadata` 的下載游標值（`null` 代表沒有任何新紀錄、游標維持
  /// 原值）——比照 Issue 4 `_downloadAndMerge()` 的既有模式，不在這個
  /// 方法內直接持久化，實際寫入時機統一挪到 `runCheckpoint()` 最後（見
  /// 上方原子性保證說明）。
  ///
  /// [excludeFingerprints] 是這次 checkpoint 推送階段（[_syncReadingPositions]）
  /// 已經處理過的書籍指紋集合——這些書籍的最終狀態一律由推送階段決定
  /// （不論結果是已推送、已依使用者選擇覆寫、或因無法取得使用者決定而
  /// 跳過），下載階段不該用同一批（可能已過期或使用者尚未決定）的遠端
  /// 快照回頭覆寫，否則會違反 FR-19「絕不可靜默覆蓋」。
  Future<String?> _downloadReadingPositions(
    PocketBase pb,
    Map<String, String> headers, {
    required Set<String> excludeFingerprints,
  }) async {
    final cursor = await _metadataRepository.loadReadingPositionsCursor();
    final filter = cursor == null ? null : 'updated > "$cursor"';
    final records = await pb.collection('sync_reading_positions').getFullList(
          filter: filter,
          sort: 'updated',
          headers: headers,
        );
    if (records.isEmpty) return cursor;

    final fingerprints =
        records.map((r) => r.data['book_fingerprint'] as String).toSet();
    final booksByFingerprint = await _loadBooksByFingerprint(fingerprints);

    for (final remote in records) {
      final fingerprint = remote.data['book_fingerprint'] as String;
      // 這本書這次 checkpoint 的推送階段已經處理過（不論結果是已推送、
      // 已依使用者選擇覆寫、或因無法取得使用者決定而跳過）——一律不在
      // 下載階段重複處理，避免用同一批（可能已過期或使用者尚未決定）的
      // 遠端快照覆寫推送階段剛做出的決定，違反 FR-19「絕不可靜默覆蓋」。
      if (excludeFingerprints.contains(fingerprint)) continue;
      final book = booksByFingerprint[fingerprint];
      if (book == null) continue; // 這台裝置尚未匯入這本書，略過

      await _db.update(
        'books',
        {
          'epubLocator': remote.data['epub_locator'] as String?,
          'pdfPageIndex': (remote.data['pdf_page_index'] as num?)?.toInt(),
          'progress': (remote.data['progress'] as num).toDouble(),
          'position_synced_server_updated_at': remote.data['updated'] as String,
        },
        where: 'id = ?',
        whereArgs: [book.id],
      );
    }

    return maxUpdatedCursor(
      records.map((r) => r.data['updated'] as String).toList(),
      cursor,
    );
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

/// 一筆待推送的閱讀位置（epic-8-sync Issue 5）。[remoteId] 為 `null`
/// 代表 PocketBase 目前沒有這本書的既有紀錄，走 create；非 `null` 代表
/// 已查得既有紀錄的 PocketBase 內部 id，走 update。
class _ReadingPositionPushItem {
  final String bookId;
  final String fingerprint;
  final String? remoteId;
  final ReadingPositionSnapshot local;

  const _ReadingPositionPushItem({
    required this.bookId,
    required this.fingerprint,
    required this.remoteId,
    required this.local,
  });
}
