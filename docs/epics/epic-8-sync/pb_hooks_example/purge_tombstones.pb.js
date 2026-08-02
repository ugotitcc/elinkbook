/// @file purge_tombstones.pb.js
/// 定期清理 sync_bookmarks/sync_highlights/sync_notes 三個 collection
/// 中超過 30 天的軟刪除紀錄（deleted_at 為毫秒時間戳記，與本機 App 端
/// 透傳的值同單位，見 docs/epics/epic-8-sync/spec.md「墓碑清理」）。
/// 使用方式：把本檔案複製到 PocketBase 執行檔同層的 pb_hooks/ 目錄下
/// （沒有這個目錄就自己建立一個），重啟 PocketBase 即會自動載入。

cronAdd("purgeOldTombstones", "0 3 * * *", () => {
  const collections = ["sync_bookmarks", "sync_highlights", "sync_notes"];
  const thirtyDaysMillis = 30 * 24 * 60 * 60 * 1000;
  const cutoffMillis = Date.now() - thirtyDaysMillis;

  for (const collectionName of collections) {
    const records = $app.findRecordsByFilter(
      collectionName,
      "deleted_at != null && deleted_at < {:cutoff}",
      "",
      500,
      0,
      { cutoff: cutoffMillis }
    );
    let purged = 0;
    for (const record of records) {
      try {
        $app.delete(record);
        purged++;
      } catch (e) {
        console.log(
          `[purgeOldTombstones] ${collectionName}: 刪除紀錄 ${record.id} 失敗，將於下次排程重試：${e}`
        );
      }
    }
    console.log(
      `[purgeOldTombstones] ${collectionName}: 清理 ${purged}/${records.length} 筆超過 30 天的墓碑`
    );
  }
});
