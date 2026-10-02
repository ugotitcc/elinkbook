/// @file purge_tombstones.pb.js
/// 定期清理 sync_bookmarks/sync_highlights/sync_notes 三個 collection
/// 中超過 30 天的軟刪除紀錄（deleted_at 為毫秒時間戳記，與本機 App 端
/// 透傳的值同單位，見 docs/sync-protocol.md「墓碑清理」）。
/// 使用方式：把本檔案複製到 PocketBase 執行檔同層的 pb_hooks/ 目錄下
/// （沒有這個目錄就自己建立一個），重啟 PocketBase 即會自動載入。
///
/// 篩選條件刻意用 `deleted_at > 0` 而非 `deleted_at != null`：PocketBase
/// 的 number 欄位沒有「可為 NULL」這個選項，從未被軟刪除的正常紀錄，
/// `deleted_at` 實際存的是數字 0、不是 SQL NULL，`!= null` 對這些正常
/// 紀錄永遠成立、會被誤判成「超過 30 天的墓碑」整批刪除（已用真實
/// PocketBase 實例重現並驗證此修正）。

cronAdd("purgeOldTombstones", "0 3 * * *", () => {
  const collections = ["sync_bookmarks", "sync_highlights", "sync_notes"];
  const thirtyDaysMillis = 30 * 24 * 60 * 60 * 1000;
  const cutoffMillis = Date.now() - thirtyDaysMillis;

  for (const collectionName of collections) {
    const records = $app.findRecordsByFilter(
      collectionName,
      "deleted_at > 0 && deleted_at < {:cutoff}",
      "",
      500,
      0,
      { cutoff: cutoffMillis }
    );
    let purged = 0;
    for (const record of records) {
      // 個別紀錄刪除失敗（例如資料庫瞬間鎖定）不應該中斷整批清理——
      // 沒清到的紀錄下一次排程（明天同一時間）會再嘗試一次，不需要
      // 在單一次失敗時就放棄同一批次裡其餘本來刪得掉的紀錄。
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
