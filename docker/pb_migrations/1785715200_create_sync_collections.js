/// @file 1785715200_create_sync_collections.js
/// 批次建立雲端同步所需的 4 個 collection（sync_reading_positions／
/// sync_bookmarks／sync_highlights／sync_notes），取代
/// docs/sync-protocol.md「PocketBase Collection Schema」逐一手動點
/// Admin UI 的做法——欄位/型別/必填/API Rules 皆與該文件的欄位表逐項
/// 對應，兩者需保持同步（若日後修改其中一邊，另一邊
/// 也要跟著更新）。
///
/// 使用方式：把本檔案複製到 PocketBase 執行檔同層的 pb_migrations/
/// 目錄下（沒有這個目錄就自己建立一個，檔名格式
/// <unix_timestamp>_<name>.js 是 PocketBase 慣例，數字部分只要是尚未
/// 用過、比未來其他 migration 檔案小的時間戳即可，不要求精確），
/// 重啟 PocketBase（或執行 `./pocketbase migrate up`）即會在一個交易
/// 內自動套用一次，之後同一份資料庫不會重複執行。
///
/// PocketBase 內建的 `id` 系統欄位每個 collection 皆自動具備，不需要在
/// 這裡另外定義。**`created`／`updated` 則相反，必須明確宣告**：
/// 真機整合測試時發現，PocketBase
/// v0.23 改版後，`created`／`updated` 改為需要在 schema 明確宣告
/// `autodate` 型別欄位才會存在，不再是每個 base collection 自動內建
/// ——本檔案原始版本沒有宣告這兩個欄位，
/// 導致 `sync_reading_positions`／`sync_bookmarks`／`sync_highlights`／
/// `sync_notes` 這 4 個 collection 的紀錄實際上完全沒有 `created`／
/// `updated` 欄位，讓依賴這兩個欄位做衝突比對／下載游標的邏輯
/// （`SyncEngine._syncReadingPositions()`／`_downloadAndMerge()`）永遠
/// 讀到 `null`。

migrate((app) => {
  const usersCollection = app.findCollectionByNameOrId("users");

  // 4 個 collection 皆用同一個 user relation 欄位（必填、指向內建
  // users、Single）與同一組 API Rules（見
  // docs/sync-protocol.md「同步流程」：這條規則只驗證送進來
  // 的 user 欄位值，App 端呼叫 Create／Batch API 時仍必須自己在 payload
  // 明確帶上 "user": "<目前登入者 user id>"，不會自動代入）。
  const userField = () => ({
    type: "relation",
    name: "user",
    required: true,
    collectionId: usersCollection.id,
    minSelect: 1,
    maxSelect: 1,
    cascadeDelete: false,
  });

  // `created`／`updated` 系統欄位（PocketBase v0.23+ 起須明確宣告，見
  // 檔案開頭說明）：4 個 collection 皆需要，抽成共用函式比照 `userField()`。
  const autodateFields = () => [
    { type: "autodate", name: "created", onCreate: true, onUpdate: false },
    { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
  ];

  const ownerOnlyRule = "user = @request.auth.id";
  const ownerOnlyRules = {
    listRule: ownerOnlyRule,
    viewRule: ownerOnlyRule,
    createRule: ownerOnlyRule,
    updateRule: ownerOnlyRule,
    deleteRule: ownerOnlyRule,
  };

  app.save(
    new Collection({
      type: "base",
      name: "sync_reading_positions",
      fields: [
        userField(),
        { type: "text", name: "book_fingerprint", required: true },
        { type: "text", name: "epub_locator", required: false },
        {
          type: "number",
          name: "pdf_page_index",
          required: false,
          onlyInt: true,
        },
        { type: "number", name: "progress", required: true, onlyInt: false },
        ...autodateFields(),
      ],
      ...ownerOnlyRules,
    })
  );

  app.save(
    new Collection({
      type: "base",
      name: "sync_bookmarks",
      fields: [
        userField(),
        { type: "text", name: "client_id", required: true },
        { type: "text", name: "book_fingerprint", required: true },
        {
          type: "number",
          name: "deleted_at",
          required: false,
          onlyInt: true,
        },
        { type: "text", name: "name", required: true },
        { type: "text", name: "epub_locator_json", required: false },
        {
          type: "number",
          name: "progression",
          required: false,
          onlyInt: false,
        },
        {
          type: "number",
          name: "pdf_page_index",
          required: false,
          onlyInt: true,
        },
        ...autodateFields(),
      ],
      ...ownerOnlyRules,
    })
  );

  app.save(
    new Collection({
      type: "base",
      name: "sync_highlights",
      fields: [
        userField(),
        { type: "text", name: "client_id", required: true },
        { type: "text", name: "book_fingerprint", required: true },
        {
          type: "number",
          name: "deleted_at",
          required: false,
          onlyInt: true,
        },
        { type: "text", name: "style", required: true },
        { type: "text", name: "epub_locator_json", required: false },
        {
          type: "number",
          name: "progression",
          required: false,
          onlyInt: false,
        },
        {
          type: "number",
          name: "pdf_page_index",
          required: false,
          onlyInt: true,
        },
        { type: "text", name: "pdf_rect_json", required: false },
        ...autodateFields(),
      ],
      ...ownerOnlyRules,
    })
  );

  app.save(
    new Collection({
      type: "base",
      name: "sync_notes",
      fields: [
        userField(),
        { type: "text", name: "client_id", required: true },
        { type: "text", name: "book_fingerprint", required: true },
        {
          type: "number",
          name: "deleted_at",
          required: false,
          onlyInt: true,
        },
        { type: "text", name: "text", required: true },
        { type: "text", name: "epub_locator_json", required: false },
        {
          type: "number",
          name: "progression",
          required: false,
          onlyInt: false,
        },
        { type: "text", name: "highlight_client_id", required: false },
        {
          type: "number",
          name: "pdf_page_index",
          required: false,
          onlyInt: true,
        },
        { type: "text", name: "pdf_rect_json", required: false },
        ...autodateFields(),
      ],
      ...ownerOnlyRules,
    })
  );
}, (app) => {
  // 降版：刪除本次建立的 4 個 collection（依建立順序反向刪除）。
  for (const name of [
    "sync_notes",
    "sync_highlights",
    "sync_bookmarks",
    "sync_reading_positions",
  ]) {
    const collection = app.findCollectionByNameOrId(name);
    app.delete(collection);
  }
});
