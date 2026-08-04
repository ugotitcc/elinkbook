/// @file 1785801700_add_reading_positions_unique_index.js
/// 對 `sync_reading_positions` 加上 unique index，強制「每個使用者對每
/// 本書（`book_fingerprint`）至多一筆紀錄」——這個約束原本只記載於
/// plan-issue-5.md 的 Global Constraints，完全沒有任何機制執行，理論上
/// 兩台裝置第一次同時推送同一本書、或本機同一本書匯入兩次，皆可能建出
/// 重複列，導致 `SyncEngine._syncReadingPositions()` 的
/// `getList(perPage: 1)` 查詢拿到不穩定的其中一筆、反覆誤判衝突（見
/// epic-8-sync issues.md Issue 9，2026-08-04 Issue 5 最終全分支審查
/// 發現）。
///
/// **套用前必須先確認 collection 內沒有既存的重複紀錄**——若已有重複，
/// 這支 migration 套用時會直接失敗（`UNIQUE constraint failed`），且
/// PocketBase 服務會啟動失敗、整個掛掉，不是優雅降級（已於撰寫本檔案
/// 時用本機 PocketBase v0.39.10 binary 實測確認）。確認/清理步驟見
/// `docs/epics/epic-8-sync/plans/plan-issue-9.md` Task 2。
///
/// 比照 `1785801600_add_created_updated_autodate_fields.js` 已確立的
/// 模式：新增獨立檔案而非修改舊的 `1785715200_...`（已套用過的環境不會
/// 因為舊檔案內容更新而重新執行）；down 只移除這個 migration 自己加的
/// 索引（用索引名稱字串比對，不會誤刪其他索引）。

migrate((app) => {
  const collection = app.findCollectionByNameOrId("sync_reading_positions");
  const indexName = "idx_sync_reading_positions_user_fp";
  const alreadyExists = collection.indexes.some((idx) => idx.includes(indexName));
  if (alreadyExists) return; // 冪等：已經套用過（例如已手動補過）就跳過

  collection.indexes.push(
    `CREATE UNIQUE INDEX \`${indexName}\` ON \`sync_reading_positions\` (\`user\`, \`book_fingerprint\`)`
  );
  app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("sync_reading_positions");
  const indexName = "idx_sync_reading_positions_user_fp";
  collection.indexes = collection.indexes.filter((idx) => !idx.includes(indexName));
  app.save(collection);
});
