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
/// 環境用的「升級」migration，冪等（用 `hasField` 判斷是否已存在再新增，
/// 避免對已經手動補過欄位的環境〔例如本專案測試用的 `pbdev.jigong.org`，
/// 已於 2026-08-04 透過 Admin API 直接補上〕重複套用時出錯）。
///
/// 使用方式同 `1785715200_create_sync_collections.js`：複製到
/// PocketBase 執行檔同層的 `pb_migrations/` 目錄下，重啟 PocketBase
/// （或執行 `./pocketbase migrate up`）即會套用。

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
}, (app) => {
  // 降版：移除本次新增的兩個欄位（若存在）。
  for (const name of [
    "sync_reading_positions",
    "sync_bookmarks",
    "sync_highlights",
    "sync_notes",
  ]) {
    const collection = app.findCollectionByNameOrId(name);
    for (const fieldName of ["created", "updated"]) {
      const field = collection.fields.getByName(fieldName);
      if (field) collection.fields.removeById(field.id);
    }
    app.save(collection);
  }
});
