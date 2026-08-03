/// @file 1785715200_create_sync_collections.js
/// 批次建立 epic-8-sync 所需的 4 個 collection（sync_reading_positions／
/// sync_bookmarks／sync_highlights／sync_notes），取代
/// docs/epics/epic-8-sync/pocketbase-self-hosting.md「建立 Collection」
/// 章節逐一手動點 Admin UI 的做法——欄位/型別/必填/API Rules 皆與該
/// 文件的欄位表逐項對應，兩者需保持同步（若日後修改其中一邊，另一邊
/// 也要跟著更新）。
///
/// 使用方式：把本檔案複製到 PocketBase 執行檔同層的 pb_migrations/
/// 目錄下（沒有這個目錄就自己建立一個，檔名格式
/// <unix_timestamp>_<name>.js 是 PocketBase 慣例，數字部分只要是尚未
/// 用過、比未來其他 migration 檔案小的時間戳即可，不要求精確），
/// 重啟 PocketBase（或執行 `./pocketbase migrate up`）即會在一個交易
/// 內自動套用一次，之後同一份資料庫不會重複執行。
///
/// PocketBase 內建的 `id` 系統欄位（每個 collection 皆自動具備）與
/// `created`／`updated` 系統欄位不需要、也不應該在這裡另外定義——見
/// pocketbase-self-hosting.md「建立 Collection」段落的說明。

migrate((app) => {
  const usersCollection = app.findCollectionByNameOrId("users");

  // 4 個 collection 皆用同一個 user relation 欄位（必填、指向內建
  // users、Single）與同一組 API Rules（見
  // pocketbase-self-hosting.md「容易誤解的地方」：這條規則只驗證送進來
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
