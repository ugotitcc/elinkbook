# Epic 40 — 自帶編譯進 FTS5 的 SQLite：Issues

**依賴：** 承接 `epic-10-search` Issue 5／Issue 6，本 Epic 內部只有一張 Issue，無需依賴圖。

## Issue 0：改用自帶編譯的 sqlite3（含 FTS5）取代系統內建版本

**Status:** ready-for-agent（`design.md`／`spec.md`／[ADR 0028](../../adr/0028-bundled-sqlite3-for-fts5.md) 已完成，待撰寫 `plans/plan-issue-0.md`）

**依賴：** 無

**來源：** `spec.md` 全文（本 Epic 只有一份 spec，此 Issue 是唯一切片）

**背景／目標：**

`epic-10-search` Issue 6 已處理「系統 SQLite 缺 FTS5 模組」的優雅降級，但沒有解決根本問題——真機驗證（`9491G`／`Hera_Vis_WIFI`）確認全文檢索在此類裝置上永久不可用。本工單改用 `sqflite_common_ffi`（其遞移解析的 `sqlite3` 3.x 透過 Dart Native Assets 建置掛鉤自動打包含 FTS5 的原生函式庫），讓 App 自己攜帶一份保證含 FTS5 的 sqlite3 原生函式庫，取代依賴 Android 系統版本的做法（只處理 Android，桌面/iOS 不動）。

**Solution：**

1. `pubspec.yaml`：`sqflite_common_ffi` 從 `dev_dependencies` 移至 `dependencies`（見 `spec.md` §1）。**不新增 `sqlite3_flutter_libs`**——該套件僅適用於已淘汰的 `sqlite3` 2.x 世代，現行 `sqlite3` 3.5.0 改由 Native Assets 建置掛鉤自動提供含 FTS5 的原生函式庫。
2. `main.dart` 在 `WidgetsFlutterBinding.ensureInitialized()` 之後、`SqliteLibraryRepository.open()` 之前，呼叫 `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;`（見 `spec.md` §2）。**同步**在 `app/integration_test/flutter_test_config.dart` 的 `testExecutable` 內、`testMain()` 執行之前加入相同初始化——真機整合測試在 Android 上執行時不經過 `lib/main.dart`（見 `spec.md` §2、§7）。
3. `sqlite_library_repository.dart`：DB `version` 由 24 升至 25，`onUpgrade` 新增 `oldVersion < 25` 分支——先查 `sqlite_master` 確認 `book_content_fts` 尚不存在才呼叫 `_createBookContentFtsTableIfSupported()`（見 `spec.md` §3，**這裡的存在性檢查是本工單唯一容易出錯的細節，務必依 spec 逐字實作**）。
4. 不新增任何索引回補程式碼（見 `spec.md` §4）；不修改 Issue 6 既有降級機制（見 `spec.md` §5）；不修改 tokenizer（見 `spec.md` §6）。

**單元測試要求（見 `spec.md` §7）：**

- 模擬既有裝置（version 24、`book_content_fts` 已存在）升級到 version 25：不拋例外，`isFullTextSearchAvailable` 仍為 `true`。
- 模擬 Issue 6 場景裝置（version 24、`book_content_fts` 不存在，可重用既有 `createBookContentFtsTable` 覆寫機制模擬）升級到 version 25：不拋例外，`isFullTextSearchAvailable` 變為 `true`，`book_content_fts` 表與三個同步 trigger（AI/AD/AU）皆已建立——分別對 `book_content_index` 執行 INSERT、UPDATE、DELETE，驗證三者都能正確同步寫入 `book_content_fts`。
- 全新安裝（`onCreate` 直接建到 version 25）：`isFullTextSearchAvailable` 為 `true`，行為與現行版本一致（零回歸）。
- 既有 `epic-10-search` Issue 0／Issue 6 測試套件全數通過，無回歸。

**驗收標準：**

- `flutter analyze` 乾淨。
- 上述遷移測試三種情境皆通過。
- **真機重新驗證**（收尾步驟，人工執行，不寫自動化測試）：在 `9491G`／`Hera_Vis_WIFI` 上：
  1. 全新安裝新版 APK（`adb install <new_app.apk>`），驗證 `isFullTextSearchAvailable=true`、全文檢索畫面不再顯示「本裝置不支援」。
  2. 安裝換引擎前的舊版 APK（重現 Issue 6 場景），確認為 version 24 且無 `book_content_fts`。
  3. 以 `adb install -r <new_app.apk>`（覆蓋安裝、保留 App 資料，不可用 `flutter run` 或不帶 `-r` 的安裝方式，避免誤觸解除安裝重裝而清空本機資料庫）升級安裝新版 APK，驗證既有裝置升級路徑同樣變為可用且不崩潰。
