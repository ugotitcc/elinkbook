# Epic 40 — 自帶編譯進 FTS5 的 SQLite：Issues

**依賴：** 承接 `epic-10-search` Issue 5／Issue 6，本 Epic 內部只有一張 Issue，無需依賴圖。

## Issue 0：改用自帶編譯的 sqlite3（含 FTS5）取代系統內建版本

**Status:** ready-for-agent（`design.md`／`spec.md`／[ADR 0028](../../adr/0028-bundled-sqlite3-for-fts5.md) 已完成，待撰寫 `plans/plan-issue-0.md`）

**依賴：** 無

**來源：** `spec.md` 全文（本 Epic 只有一份 spec，此 Issue 是唯一切片）

**背景／目標：**

`epic-10-search` Issue 6 已處理「系統 SQLite 缺 FTS5 模組」的優雅降級，但沒有解決根本問題——真機驗證（`9491G`／`Hera_Vis_WIFI`）確認全文檢索在此類裝置上永久不可用。本工單改用 `sqflite_common_ffi` + `sqlite3_flutter_libs`，讓 App 自己攜帶一份保證含 FTS5 的 sqlite3 原生函式庫，取代依賴 Android 系統版本的做法（只處理 Android，桌面/iOS 不動）。

**Solution：**

1. `pubspec.yaml` 新增正式相依 `sqlite3_flutter_libs`；`sqflite_common_ffi` 從 `dev_dependencies` 移至 `dependencies`（見 `spec.md` §1）。
2. `main.dart` 在 `WidgetsFlutterBinding.ensureInitialized()` 之後、`SqliteLibraryRepository.open()` 之前，呼叫 `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;`（見 `spec.md` §2）。
3. `sqlite_library_repository.dart`：DB `version` 由 24 升至 25，`onUpgrade` 新增 `oldVersion < 25` 分支——先查 `sqlite_master` 確認 `book_content_fts` 尚不存在才呼叫 `_createBookContentFtsTableIfSupported()`（見 `spec.md` §3，**這裡的存在性檢查是本工單唯一容易出錯的細節，務必依 spec 逐字實作**）。
4. 不新增任何索引回補程式碼（見 `spec.md` §4）；不修改 Issue 6 既有降級機制（見 `spec.md` §5）；不修改 tokenizer（見 `spec.md` §6）。

**單元測試要求（見 `spec.md` §7）：**

- 模擬既有裝置（version 24、`book_content_fts` 已存在）升級到 version 25：不拋例外，`isFullTextSearchAvailable` 仍為 `true`。
- 模擬 Issue 6 場景裝置（version 24、`book_content_fts` 不存在）升級到 version 25：不拋例外，`isFullTextSearchAvailable` 變為 `true`，`book_content_fts` 表與三個同步 trigger 皆已建立（用一筆 `book_content_index` INSERT 驗證觸發同步寫入 `book_content_fts`）。
- 全新安裝（`onCreate` 直接建到 version 25）：`isFullTextSearchAvailable` 為 `true`，行為與現行版本一致（零回歸）。
- 既有 `epic-10-search` Issue 0／Issue 6 測試套件全數通過，無回歸。

**驗收標準：**

- `flutter analyze` 乾淨。
- 上述遷移測試三種情境皆通過。
- **真機重新驗證**（收尾步驟，人工執行，不寫自動化測試）：在 `9491G`／`Hera_Vis_WIFI` 上，(a) 全新安裝新版 APK，驗證 `isFullTextSearchAvailable=true`、全文檢索畫面不再顯示「本裝置不支援」；(b) 先安裝換引擎前的舊版 APK 重現 Issue 6 場景，再升級安裝新版 APK，驗證既有裝置升級路徑同樣變為可用且不崩潰。
