/// @file 1785801600_add_created_updated_autodate_fields.js
/// 補上 `1785715200_create_sync_collections.js` 原始版本遺漏的
/// `created`／`updated` autodate 欄位（2026-08-04 epic-8-sync Issue 5
/// Task 6 真機驗證時發現，見該檔案開頭說明與
/// docs/epics/epic-8-sync/plans/plan-issue-5.md「審查修正紀錄」）。
///
/// **為什麼是新檔案，而不是直接修改 `1785715200_create_sync_collections.js`**
/// （2026-08-04 `/superpowers:subagent-driven-development` Task 6 審查
/// Important 意見）：PocketBase 依檔名記錄「這份資料庫是否已套用過某個
/// migration 檔案」，已套用過的環境即使檔案內容事後被改掉也不會重新
/// 執行。`1785715200_create_sync_collections.js` 本身雖然已經直接補上
/// 這兩個欄位（供全新部署使用），但任何「已經套用過舊版
/// `1785715200_...` 檔案、事後也沒有另外用 Admin API 手動補欄位」的
/// 既有環境，光改那個檔案的內容完全沒有效果——本檔案就是給這種既有
/// 環境用的「升級」migration，冪等（檢查欄位名稱是否已存在再新增，
/// 避免對已經手動補過欄位的環境〔例如本專案測試用的 `pbdev.jigong.org`，
/// 已於 2026-08-04 透過 Admin API 直接補上〕重複套用時出錯）。
///
/// 使用方式同 `1785715200_create_sync_collections.js`：複製到
/// PocketBase 執行檔同層的 `pb_migrations/` 目錄下，重啟 PocketBase
/// （或執行 `./pocketbase migrate up`）即會套用。
///
/// **降版（down）刻意設計為 no-op，不還原欄位**（2026-08-04 Task 6
/// 審查發現並修正）：這個 migration 的 up 是冪等的，在「
/// `1785715200_create_sync_collections.js` 已經內建這兩個欄位」的全新
/// 部署上會直接跳過、什麼都不做——這種情況下若 down 無條件移除欄位，
/// 等於單獨降版這個檔案就會刪掉其實是另一個 migration
/// （`1785715200_...`）建立的欄位，靜默重現本檔案要修正的原始 bug。
/// PocketBase 的 migration 系統無法得知「這個欄位究竟是哪個 migration
/// 建立的」，與其實作一套追蹤欄位來源的機制（YAGNI，本專案只有一個
/// 長期運作的測試實例，不需要這種複雜度），選擇讓 down 保持 no-op，
/// 需要真的移除欄位時請直接透過 Admin UI／API 手動處理。

migrate((app) => {
  const autodateFields = () => [
    { type: "autodate", name: "created", onCreate: true, onUpdate: false },
    { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
  ];

  for (const name of [
    "sync_reading_positions",
    "sync_bookmarks",
    "sync_highlights",
    "sync_notes",
  ]) {
    const collection = app.findCollectionByNameOrId(name);
    const existingNames = collection.fields.map((f) => f.name);
    const missing = autodateFields().filter(
      (f) => !existingNames.includes(f.name)
    );
    if (missing.length === 0) continue; // 已經有欄位（例如已手動補過）：略過，維持冪等
    for (const field of missing) {
      collection.fields.add(new Field(field));
    }
    app.save(collection);
  }
}, (_app) => {
  // 降版刻意為 no-op：見檔案開頭「降版（down）刻意設計為 no-op」說明。
});
