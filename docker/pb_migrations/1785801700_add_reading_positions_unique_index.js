/// @file 1785801700_add_reading_positions_unique_index.js
/// 對 `sync_reading_positions` 加上 unique index，強制「每個使用者對每
/// 本書（`book_fingerprint`）至多一筆紀錄」——這個約束原本只是設計文件中的約束，完全沒有任何機制執行，理論上
/// 兩台裝置第一次同時推送同一本書、或本機同一本書匯入兩次，皆可能建出
/// 重複列，導致 `SyncEngine._syncReadingPositions()` 的
/// `getList(perPage: 1)` 查詢拿到不穩定的其中一筆、反覆誤判衝突（審查時發現）。
///
/// **套用前必須先確認 collection 內沒有既存的重複紀錄**——若已有重複，
/// 這支 migration 套用時會直接失敗（`UNIQUE constraint failed`），且
/// PocketBase 服務會啟動失敗、整個掛掉，不是優雅降級（已於撰寫本檔案
/// 時用本機 PocketBase v0.39.10 binary 實測確認）。確認/清理：先在 Admin UI 以
/// (user, book_fingerprint) 分組找出重複列、刪除多餘者，再套用本 migration。
///
/// 比照 `1785801600_add_created_updated_autodate_fields.js` 已確立的
/// 模式：新增獨立檔案而非修改舊的 `1785715200_...`（已套用過的環境不會
/// 因為舊檔案內容更新而重新執行）。
///
/// **降版（down）刻意設計為 no-op，不移除索引**（比照
/// `1785801600_...` 已確立的理由）：這支 migration 的 up 是冪等的，在
/// 「索引已經存在」的環境（例如已透過
/// Admin API 手動加上索引的環境）上會直接
/// `alreadyExists` 早退、什麼都沒做；若 down 無條件依名稱移除索引，
/// 單獨降版這支檔案就會把「其實不是這支 migration 建立的」索引一併
/// 刪掉，靜默重現本檔案要修正的原始 bug。需要真的移除索引時請直接
/// 透過 Admin UI／API 手動處理。

migrate((app) => {
  const collection = app.findCollectionByNameOrId("sync_reading_positions");
  const indexName = "idx_sync_reading_positions_user_fp";
  const alreadyExists = collection.indexes.some((idx) => idx.includes(indexName));
  if (alreadyExists) return; // 冪等：已經套用過（例如已手動補過）就跳過

  collection.indexes.push(
    `CREATE UNIQUE INDEX \`${indexName}\` ON \`sync_reading_positions\` (\`user\`, \`book_fingerprint\`)`
  );
  app.save(collection);
}, (_app) => {
  // 降版刻意為 no-op：見檔案開頭「降版（down）刻意設計為 no-op」說明。
});
