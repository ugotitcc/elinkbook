# Epic 40 — 自帶編譯進 FTS5 的 SQLite：Spec

**設計依據：** `design.md`（Discovery）、[ADR 0028](../../adr/0028-bundled-sqlite3-for-fts5.md)（架構決策）。本文件是本 Epic 的唯一事實來源，後續 Issue 拆分與實作皆以本文件為準。

## 1. 依賴變更

`app/pubspec.yaml`：

- `sqflite_common_ffi`（目前 `^2.4.0+3`，位於 `dev_dependencies`）**移動到 `dependencies`**——它現在同時服務正式 Android 建置（透過 `databaseFactoryFfi`）與既有桌面測試環境，不再只是測試專用。
- **不新增 `sqlite3_flutter_libs`**：這個套件僅適用於 `package:sqlite3` 2.x 世代，本專案透過 `sqflite_common_ffi: ^2.4.0+3` 遞移解析到的是 `sqlite3: 3.5.0`（見 `app/pubspec.lock`）。`sqlite3` 3.x 起改用 Dart 官方 Native Assets（建置掛鉤，`hook/build.dart`）機制，會在 `flutter build apk`／`flutter run` 時自動下載（或視平台自行編譯）含 `SQLITE_ENABLE_FTS5` 的原生 `libsqlite3.so` 並打包進 APK，不需要也不應該引入已標記 `0.6.0+eol`、內容已清空的 `sqlite3_flutter_libs`。
- （可選，作為明確防禦）可在 `dependencies` 明確宣告 `sqlite3: ^3.5.0`，鎖定 v3.x 以上、確定走 Native Assets 路線的版本。
- **建置期網路需求**：`flutter build apk`／`flutter run` 首次為某個 ABI 建置時，`sqlite3` 的建置掛鉤需要透過 HTTPS 從 `github.com/simolus3/sqlite3.dart/releases` 下載對應的預編譯二進位檔案；離線建置環境需自行準備好這個快取或改用其他建置掛鉤設定。

## 2. `main.dart`：初始化 FFI factory

在 `main()` 函式最前面（`WidgetsFlutterBinding.ensureInitialized()` 之後、任何 `openDatabase()` 呼叫——即 `SqliteLibraryRepository.open()`——之前）新增：

```dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  // ...既有初始化流程照舊...
}
```

這一段只涵蓋正式 App 執行路徑（`flutter run`／`flutter build apk` 啟動後實際跑的 `lib/main.dart`）。**真機整合測試（`app/integration_test/`）在 Android 上執行時不會呼叫 `lib/main.dart` 的 `main()`**——`flutter test integration_test/<file>.dart -d <device-id>` 是把該測試檔自己的 `main()` 當作 Android 測試 APK 的入口，見下方第 7 節。

## 3. 資料庫遷移：version 24 → 25

`sqlite_library_repository.dart` 的 `onUpgrade` 新增一個分支，**必須放在既有 `if (oldVersion < 24) { ... }` 分支之後、`onUpgrade` 函式結尾之前**：

```dart
if (oldVersion < 25) {
  // epic-40-bundled-sqlite：資料庫引擎換成自帶編譯的 sqlite3
  // （見 ADR 0028）後，原本因系統 SQLite 缺 FTS5 模組而被
  // _createBookContentFtsTableIfSupported() 跳過建表的裝置，這次應該
  // 能成功建表。但 CREATE VIRTUAL TABLE 沒有 IF NOT EXISTS 防護，對
  // 系統版本本來就有 FTS5、已成功建表的裝置（多數裝置，oldVersion
  // 已經 >= 24 且當初建表成功）若無條件重跑會拋出「table already
  // exists」，因此必須先查 sqlite_master 確認表尚不存在才嘗試建立。
  final existing = await db.query(
    'sqlite_master',
    columns: ['name'],
    where: "type = 'table' AND name = 'book_content_fts'",
    limit: 1,
  );
  if (existing.isEmpty) {
    await _createBookContentFtsTableIfSupported(db);
  }
}
```

`open()` 方法結尾既有的 `isFullTextSearchAvailable: ftsTableRows.isNotEmpty`（查 `sqlite_master`）判斷邏輯**不需要更動**——它本來就是每次開啟資料庫時即時查詢，這次遷移成功建表後，下一行自然會查到表存在、回傳 `true`。

**全新安裝**（`onCreate`，DB 直接建到 version 25）**不需要額外處理**：`onCreate` 呼叫的 `_createBookContentFtsTableIfSupported(db)` 這時已經是透過自帶引擎執行，正常情況下會直接建表成功，走既有路徑即可，不需要额外的存在性檢查（`onCreate` 是全新資料庫，`book_content_fts` 必然不存在）。

`SqliteLibraryRepository` 的 `openDatabase(..., version: 24, ...)` 呼叫改為 `version: 25`。

## 4. 既有裝置索引資料回補

不新增任何程式碼。原本因缺 FTS5 而 `isFullTextSearchAvailable=false` 的裝置，遷移成功後查詢會回傳 `true`，全文檢索功能自然恢復可見；若使用者先前已開啟「啟用全文檢索」開關但索引不完整，依賴 `FullTextSearchSettingsRepository.rebuildIndex(category)`（`epic-10-search` Issue 3 既有功能，`full_text_search_settings_repository.dart:105-109`）由使用者手動觸發即可，該方法本已是「清空索引 → 重新批次插入 pending → 喚醒排程器」的完整實作。

## 5. Issue 6 既有優雅降級機制

`_createBookContentFtsTableIfSupported()`（`sqlite_library_repository.dart:937-950`）不修改。

## 6. Tokenizer

不修改。`cjk_tokenizer.dart`／`unicode61` 方案維持現狀（見 `design.md` 第 5 節、ADR 0028 決策 5）。

## 7. 測試要求

- **既有純 Dart／widget 測試套件零回歸**：`sqflite_common_ffi` 測試環境（Windows/Linux/macOS 開發機）本來就依賴系統既有 sqlite3（一律含 FTS5），`main.dart` 的 `databaseFactory` 初始化只影響**正式 Android 執行路徑**，`app/test/` 下的測試檔案透過 `sqflite_common_ffi` 直接呼叫 `databaseFactoryFfi`/`inMemoryDatabasePath` 開資料庫，不經過 `main()`，不受影響。
- **真機整合測試環境須同步初始化**：`app/integration_test/` 在 Android 真機上執行時不經過 `lib/main.dart` 的 `main()`（見上方第 2 節），需在全域整合測試入口 [`app/integration_test/flutter_test_config.dart`](../../../app/integration_test/flutter_test_config.dart) 的 `testExecutable` 函式內、`testMain()` 執行之前，補上：
  ```dart
  import 'package:sqflite_common_ffi/sqflite_ffi.dart';

  Future<void> testExecutable(FutureOr<void> Function() testMain) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    await testMain();
  }
  ```
  確保所有 `integration_test/` 測試檔（含目前未各自補寫 `sqfliteFfiInit()` 的 `library_screen_test.dart`／`manual_import_acceptance_test.dart` 等）與正式 App 一致使用自帶 SQLite 引擎，而非回退到系統平台 channel。
- 新增遷移測試（比照既有 `onUpgrade` 遷移測試慣例，`sqlite_library_repository_test.dart`）：
  1. 模擬一個 version 24 的既有資料庫、`book_content_fts` 表已存在（模擬系統版本本來就有 FTS5 的裝置）——升級到 version 25 後，`open()` 不拋出例外，`isFullTextSearchAvailable` 仍為 `true`。
  2. 模擬一個 version 24 的既有資料庫、`book_content_fts` 表**不存在**（模擬 Issue 6 場景，系統版本當初缺 FTS5 而跳過建表；可重用既有頂層變數 `createBookContentFtsTable` 覆寫機制模擬，與 `sqlite_library_repository_test.dart` 既有 Issue 6 測試同構）——升級到 version 25 後（測試環境的 `sqflite_common_ffi` 一律有 FTS5，模擬「換引擎後這次建表會成功」），`open()` 不拋出例外，`isFullTextSearchAvailable` 變為 `true`，且 `book_content_fts` 表與三個同步 trigger（`book_content_index_ai`/`book_content_index_ad`/`book_content_index_au`）皆已建立——分別對 `book_content_index` 執行一筆 INSERT、UPDATE、DELETE，驗證三個 trigger 都能正確同步變更到 `book_content_fts`，不只驗證 INSERT。
  3. 全新安裝（`onCreate` 直接建到 version 25）：`isFullTextSearchAvailable` 為 `true`，行為與現行版本一致（零回歸）。
- **真機重新驗證**（收尾步驟，不寫自動化測試）：在 `9491G`／`Hera_Vis_WIFI` 這台已知原本缺 FTS5 的實機上：
  1. 全新安裝新版 APK（`adb install <new_app.apk>`），驗證 `isFullTextSearchAvailable=true`。
  2. 安裝換引擎前的舊版 APK（重現 Issue 6 場景），開機確認為 version 24 且無 `book_content_fts`（或全文檢索畫面顯示「本裝置不支援」）。
  3. 以 `adb install -r <new_app.apk>`（`-r` 為覆蓋安裝、保留既有 App 資料，切勿用 `flutter run` 或未帶 `-r` 的安裝方式，否則可能觸發解除安裝重裝、清空本機資料庫，導致測不到 version 24→25 的 `onUpgrade` 遷移路徑）升級安裝新版 APK，驗證既有裝置升級路徑同樣變為 `isFullTextSearchAvailable=true` 且不崩潰。

## 明確排除（沿用 `design.md`，此處重申以免實作時誤觸）

- 不處理 iOS／桌面平台的資料庫引擎。
- 不改動 tokenizer。
- 不為既有裝置設計自動索引回補機制。
- 不移除 Issue 6 既有的優雅降級防線。

## 下一步

Scrum Master：拆 `docs/epics/epic-40-bundled-sqlite/issues.md`，整個 Epic 只開一張 Issue（範圍集中在單一方法內，不需要垂直切片）。
