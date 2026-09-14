# Epic 40 — 自帶編譯進 FTS5 的 SQLite：Discovery

## 緣起

`epic-10-search`（全文檢索）Issue 6 已處理「部分裝置系統內建 SQLite 沒有 FTS5 模組」的優雅降級（App 正常開機、全文檢索功能顯示「本裝置不支援」），但沒有解決根本問題。Issue 5 合併後，人類在兩台實機上測試皆顯示「本裝置不支援全文檢索」；連上其中一台已連結的實機（`3CEF42ECD491687`，`9491G`／`Hera_Vis_WIFI`，MediaTek 客製化 E-Ink ROM，Android 15——與 Issue 6 當初發現相容性缺陷的同一型號）以 `adb logcat` 實測捕捉到：

```
E SQLiteLog: (1) statement aborts at 29: [CREATE VIRTUAL TABLE book_content_fts USING fts5(...)] no such module: fts5
```

確認 Issue 6 的優雅降級機制運作如預期，但同時證實根本原因未解：`sqflite` 在 Android 上呼叫的是**系統內建**的 SQLite（透過平台 channel），是否編譯進 FTS5 模組完全取決於各裝置廠商／ROM 的客製化決定，與 Android 版本高低沒有必然關係。人類判斷「一般 E-Ink 裝置很可能普遍缺 FTS5」，決議評估讓 App 自己編譯/攜帶一份保證含 FTS5 的 SQLite 動態函式庫，取代目前依賴系統版本的做法。本次 `/mattpocock-skills:grill-with-docs`（2026-09-11）完整定案範圍與技術路線。

## 現有程式碼現況（決定了本 Epic 的實際改動面有多大）

- **全專案只有一個資料庫開啟點。** `SqliteLibraryRepository.open()`（`sqlite_library_repository.dart:49-53`）是唯一呼叫 `openDatabase()` 的地方，回傳的 `Database` 物件由 `main.dart` 逐層透過建構子參數傳給其餘全部 12+ 個 repository（`HighlightsRepository`／`BookmarksRepository`／`NotesRepository`／`SyncMetadataRepository` 等）。這些 repository 一律只認 `package:sqflite/sqflite.dart` 匯出的 `Database`/`Batch`/`Transaction` 型別（定義於 `sqflite_common`），不各自開連線。
- **`sqflite`（平台 channel）與 `sqflite_common_ffi`（FFI）是同一組 `sqflite_common` 介面的兩種底層實作**，型別完全相容，換底層引擎理論上不需要更動任何一個 repository 的程式碼，只需要換 `SqliteLibraryRepository.open()` 這一個呼叫點背後所用的 `DatabaseFactory`。
- **原生 Kotlin 端沒有任何程式碼直接碰觸這個資料庫檔案**（已 grep `app/android/app/src/main` 確認），不受影響。
- **`sqflite_common_ffi`／`sqlite3`（Dart 綁定）皆已是既有依賴**（`sqflite_common_ffi: ^2.4.0+3`，目前僅 dev_dependency，供桌面開發機測試環境使用；遞移解析到的 `sqlite3` 為 3.5.0，已在 pub cache）。`sqlite3` 3.x 起原生函式庫改由 Dart Native Assets（建置掛鉤 `hook/build.dart`）在建置時自動下載/編譯含 FTS5 的 `libsqlite3.so`，**不需要（也不應該）額外引入 `sqlite3_flutter_libs`**——這個套件僅適用於 `sqlite3` 2.x 世代，最新版本 `0.6.0+eol` 已無任何實體檔案。本 Epic 唯一需要的相依變更，是把既有的 `sqflite_common_ffi` 從 dev_dependency 提升為正式 dependency。
- **ADR 0027 決策 1（排除 FTS5 `trigram` tokenizer，改採 Dart 端 CJK 字元層級 token 化）當初的排除理由是「Android 11 系統 SQLite 3.28.0 不支援 trigram（需 3.34+）」**，這個理由在換成自帶版本後技術上不再成立，本次一併重新評估是否要改用 trigram tokenizer（見下方「重新評估 trigram tokenizer」）。
- **ADR 0027「曾考慮的替代方案」段落已明確評估過本次要採用的方案**（`sqlite3_flutter_libs` 取代系統版本），當時判斷「牽動既有 23 版 migration 歷史與全部既有測試，風險與範圍遠超本 Epic」而排除——事後看來，該判斷低估了「系統版本缺 FTS5」這個問題本身的嚴重性與普遍性（不是只影響 trigram，而是完全沒有 FTS5 模組，導致全文檢索在部分裝置上永久無法使用）。
- **`book_content_fts` 建表 SQL 沒有 `IF NOT EXISTS` 防護**（`sqlite_library_repository.dart:902-926`），對已成功建表的裝置無條件重跑會拋出「table already exists」——任何後續遷移邏輯都必須先查 `sqlite_master` 確認表不存在才嘗試建立。
- **既有的「重建索引」按鈕（`FullTextSearchSettingsRepository.rebuildIndex()`，`epic-10-search` Issue 3）已經是「清空該分類索引 → 重新批次插入 pending → 喚醒排程器」的完整實作**，只要 `book_content_fts` 與其三個同步 trigger 存在，重跑一次即可正確回填——這代表既有裝置的資料回補不需要任何新機制，直接沿用這顆既有按鈕即可。

## 本次落地範圍

### 1. 技術路線：`sqflite_common_ffi`（`sqlite3` 3.x Native Assets 建置掛鉤自帶 FTS5 二進位）

`main.dart` 在第一次 `openDatabase()` 之前呼叫一次 `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;`，讓 `SqliteLibraryRepository.open()` 內的 `openDatabase()` 呼叫改由 FFI 直連 `sqlite3` 套件透過 Native Assets 建置掛鉤自動下載/編譯、打包進 APK 的 `libsqlite3.so`（各 Android ABI 各自一份，確定含 FTS5），不再透過平台 channel 呼叫系統版本。**只處理 Android 正式建置路徑**——桌面測試環境（`sqflite_common_ffi` 依賴開發機系統既有 sqlite3，本來就沒有 FTS5 缺失問題）與 iOS（`epic-13-ios` 尚未啟動，屆時 iOS 系統 SQLite 是否含 FTS5 是完全獨立的另一個問題）皆維持現狀不動。真機整合測試（`app/integration_test/`）在 Android 上執行時不經過 `lib/main.dart`，需在 `flutter_test_config.dart` 同步初始化，細節見 `spec.md` 第 2、7 節。

### 2. 既有裝置遷移：DB version 24 → 25

新增一個遷移步驟，**先查 `sqlite_master` 確認 `book_content_fts` 表尚不存在，才嘗試呼叫建表**（避免對系統版本本來就有 FTS5、已成功建表的裝置重複建表報錯）。對於原本因缺 FTS5 而跳過建表的裝置，換引擎後這次遷移應能成功建表；`isFullTextSearchAvailable` 查詢邏輯（查 `sqlite_master`，`sqlite_library_repository.dart:421-429`）不需要更動，本來就是每次開啟資料庫時即時判斷。

### 3. 既有裝置的索引資料回補：不做自動化，沿用既有「重建索引」按鈕

對於原本 `isFullTextSearchAvailable=false` 但使用者已經開啟「啟用全文檢索」開關的裝置，換引擎後表建成功，但索引可能是空的（或不完整）。**不自動觸發背景全量重建**（避免使用者未察覺的情況下觸發背景 CPU/WebView 資源消耗，違反 spec.md 既有「背景索引與正在閱讀互斥」的使用者知情前提），也不加任何一次性提示 UI。依賴 `epic-10-search` Issue 3 既有的「重建索引」按鈕，使用者本來就可能因為懷疑索引不完整而手動點擊；不成比例地為這個過渡期邊界情況新增機制。

### 4. Issue 6 既有優雅降級機制：保留不拔

`_createBookContentFtsTableIfSupported()` 這層 try/catch 防線（偵測「no such module: fts5」訊息時靜默跳過建表）維持不動，作為零成本的縱深防禦——即使換成自帶編譯的版本，理論上不會再觸發，但這是已運作正常、有測試覆蓋的既有程式碼，沒有理由因為「理論上用不到」而移除。

### 5. 重新評估 trigram tokenizer：查證後維持現狀，不採用

查證 SQLite 官方文件確認 FTS5 `trigram` tokenizer 有一個關鍵限制：**少於 3 個 Unicode 字元的子字串查詢，保證比對不到任何資料列**（"Substrings consisting of fewer than 3 unicode characters do not match any rows when used with a full-text query."）。對照現行方案（`cjk_tokenizer.dart` 的 `tokenizeForQuery()`：CJK 逐字空白分隔後包成 FTS5 phrase query），**現行方案對單一中文字的查詢也能正確比對**（例如搜尋「明」會產生 `"明"`，`unicode61` 正常匹配）。若改用 trigram，會是一個功能倒退——中文搜尋情境下單字/雙字查詢並不罕見。且現行方案已用真實規模（800 萬列）通過 NFR-2 效能驗證，沒有精度或效能上的既有痛點。**結論：重新評估後維持現行 `unicode61`＋Dart 端字元層級 token 化方案，不改用 trigram**（技術排除理由已不成立，但重新評估後判斷現行方案本身沒有問題、且 trigram 存在現行方案沒有的短查詢缺陷，換了反而倒退）。

## 明確排除範圍（Out of scope）

- 不處理 iOS／桌面平台的資料庫引擎（見上方第 1 節）。
- 不改動 tokenizer（見上方第 5 節）。
- 不為既有裝置設計自動索引回補機制（見上方第 3 節）。
- 不移除 Issue 6 既有的優雅降級防線（見上方第 4 節）。

## 下一步

Architecting：新增 ADR 0028 記錄本次決策，並在 `spec.md` 定義遷移步驟的確切實作方式；ADR 0027「曾考慮的替代方案」段落尾端加一句指標性註記，不重寫本文。
