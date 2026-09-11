# ADR 0028：改用自帶編譯的 SQLite（`sqlite3_flutter_libs`）取代 Android 系統內建版本，解決 FTS5 模組缺失

## 狀態

已採納

## 背景

`sqflite`（`^2.4.2+1`）在 Android 上呼叫的是**系統內建**的 SQLite（透過平台 channel），不綁定自帶版本。`epic-10-search` ADR 0027 決策 1 已知系統版本可能過舊（Android 11 系統 SQLite 3.28.0，早於 FTS5 `trigram` tokenizer 所需的 3.34+），因而排除 trigram、改採 Dart 端字元層級 token 化繞過這個限制。

`epic-10-search` Issue 6 進一步發現：系統 SQLite 缺 FTS5 不只是「版本太舊」，在部分裝置上是**模組完全沒有編譯進去**（`no such module: fts5`），這與 Android 版本高低沒有必然關係，是各裝置廠商／ROM 客製化的編譯選項。Issue 6 為此新增優雅降級機制（偵測到此例外時跳過建表，`isFullTextSearchAvailable=false`），讓 App 至少能正常開機，但全文檢索功能在這些裝置上永久不可用。

`epic-10-search` Issue 5 合併後，人類在兩台實機測試皆顯示「本裝置不支援全文檢索」。連上其中一台已連結的實機（`9491G`／`Hera_Vis_WIFI`，MediaTek 客製化 E-Ink ROM，Android 15——與 Issue 6 當初發現問題的同一型號）以 `adb shell pm clear` 清除 App 資料觸發 `onCreate` 重新建表，即時 `adb logcat` 實測捕捉到：

```
E SQLiteLog: (1) statement aborts at 29: [CREATE VIRTUAL TABLE book_content_fts USING fts5(...)] no such module: fts5
```

確認 Issue 6 的降級機制運作如預期，但根本問題（全文檢索在此類裝置上永久不可用）未解。PRD 明文將「部分 E-Ink 閱讀器」列為目標裝置，人類判斷這不是單一裝置個案，而是一般 E-Ink 裝置系統 SQLite 可能普遍缺 FTS5 模組的結構性問題，決議評估架構級解法。

ADR 0027「曾考慮的替代方案」當時已評估過本次要採用的方案（`sqlite3_flutter_libs` 取代系統版本），並以「牽動整個 App 現有全部資料表都要換一套 SQLite runtime，風險與範圍遠超 `epic-10-search` 這一個 Epic」為由排除。事後看來，當時只把它當成「解決 trigram 版本問題」的手段來評估，低估了「系統版本可能完全沒有 FTS5」這個問題本身的嚴重性——這不是效能或精度上的次要限制，而是讓一個 PRD 明文要求的核心功能（FR-04 全文檢索）在特定裝置類型上完全無法使用。

## 決策

1. **改用 `sqflite_common_ffi` + `sqlite3_flutter_libs`，取代 Android 上依賴系統內建 SQLite 的做法**：`sqlite3_flutter_libs` 為 Android 各 ABI 各自攜帶一份預先編譯（確定含 FTS5）的原生 `libsqlite3.so`；App 啟動時（`main()`，第一次 `openDatabase()` 之前）呼叫 `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;`，讓 `SqliteLibraryRepository.open()` 這一個唯一的資料庫開啟點改由 FFI 直連這份自帶函式庫。全專案其餘 12+ 個 repository 皆只依賴 `sqflite_common` 定義的 `Database`/`Batch`/`Transaction` 型別、不各自開連線，因此這是一個集中在單一開啟點的改動，不需要更動任何 repository 的程式碼。**只處理 Android 正式建置路徑**——桌面測試環境本來就沒有 FTS5 缺失問題，iOS 留待 `epic-13-ios` 啟動時獨立評估。
2. **既有裝置遷移採 DB version 24→25，且必須先查 `sqlite_master` 確認 `book_content_fts` 表尚不存在才嘗試建立**：現行 `CREATE VIRTUAL TABLE book_content_fts USING fts5(...)` 沒有 `IF NOT EXISTS` 防護，對系統版本本來就有 FTS5、已成功建表的裝置（多數裝置）若無條件重跑會拋出「table already exists」，是這個遷移步驟唯一需要小心處理的技術細節。
3. **既有裝置的索引資料不做自動回補，沿用 `epic-10-search` Issue 3 既有的「重建索引」按鈕**：`rebuildIndex()` 本來就是「清空索引 → 重新批次插入 pending → 喚醒排程器」的完整實作，只要新的 FTS5 表與同步 trigger 存在即可正確運作，不需要新機制；也避免在使用者未察覺的情況下觸發背景索引重建。
4. **保留 Issue 6 既有的優雅降級機制**（偵測「no such module: fts5」時跳過建表）：作為零成本的縱深防禦，即使理論上換成自帶版本後不會再觸發，也沒有理由移除已運作正常、有測試覆蓋的既有程式碼。
5. **重新評估但維持排除 FTS5 `trigram` tokenizer**：技術上，「系統版本太舊」這個排除理由在自帶版本後不再成立，但重新評估後發現 trigram tokenizer 有一個現行方案沒有的限制——少於 3 個 Unicode 字元的子字串查詢保證比對不到任何資料列。現行 Dart 端字元層級 token 化方案（`cjk_tokenizer.dart`）對單一中文字查詢也能正確比對，且已用真實規模（800 萬列）通過 NFR-2 效能驗證。改用 trigram 對中文搜尋情境（單字/雙字查詢常見）會是功能倒退，維持現行方案。

## 曾考慮的替代方案

- **繼續依賴系統內建 SQLite，僅在 UI 層讓使用者知道「本裝置不支援」（維持 Issue 6 現狀不變）**：技術風險最低，但等於放棄修復一個 PRD 明文要求的核心功能在部分目標裝置（E-Ink）上的永久缺陷，不符合人類對「這是產品核心差異化功能」的判斷，排除。
- **偵測到系統 FTS5 缺失時，改用其他純 Dart 實作的全文檢索方案（例如自建倒排索引）取代 FTS5**：等於為了少數裝置重新發明一套獨立的搜尋引擎，維護成本與正確性風險遠高於直接讓 SQLite 本身具備 FTS5，排除。
- **同時重新啟用 FTS5 `trigram` tokenizer 取代現行 Dart 端字元層級 token 化**：查證後發現 trigram 對 <3 字元子字串查詢保證失效，是現行方案沒有的功能倒退，且現行方案已通過效能驗證、無已知痛點，排除（見決策 5）。

## 後果

- 新增正式相依套件 `sqlite3_flutter_libs`；`sqflite_common_ffi` 從 dev_dependency 提升為同時服務正式 Android 建置與既有桌面測試環境的相依套件。
- APK 體積增加：`sqlite3_flutter_libs` 為每個 ABI 各攜帶一份原生函式庫；Google Play App Bundle 依裝置 ABI 拆分後，單一裝置實際下載增量預期在 1-2MB 量級。
- `sqlite_library_repository.dart` DB `version` 由 24 升至 25，新增一個帶存在性防護的遷移步驟（見決策 2）。
- App 現在自己釘選 SQLite 版本，不再受各裝置系統版本差異影響——這也代表未來若要重新評估任何依賴 SQLite 版本/擴充模組的功能（例如決策 5 提及的 trigram、或其他 FTS5 進階選項），評估基準是「App 自選的版本是否支援」，不再是「系統版本是否支援」。
- 部分 ADR 0027「曾考慮的替代方案」段落記載的排除判斷已被本 ADR 推翻，該段落尾端加註指向本 ADR 的指標性註記，不重寫原文。
