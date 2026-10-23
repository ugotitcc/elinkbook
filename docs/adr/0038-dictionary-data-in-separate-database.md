# ADR 0038：字典資料放在獨立的 `dictionary.db`

## 狀態

已採納（2026-10-22）。對應 `epic-63-dictionary-lookup` Issue 2、Issue 6a。

## 背景

字典查詢需要兩張表（來源與詞條），資料量與生命週期都和書庫不同：

- 詞條數量可以是十幾萬筆（例如 CC-CEDICT 12 萬筆、教育部辭典 16 萬筆），與書籍、劃線、書籤的資料量不同級。
- 使用者可以隨時刪除整本字典、重新匯入、調整優先順序；這些操作與書庫資料無關。
- 書庫主資料庫（`library.db`）已到 `version: 28`，且同步機制以 `app/lib/sync/sync_table_specs.dart` 明確登錄要同步的表。
- `spec.md` §4 已定出 `dictionary_sources`／`dictionary_entries` 的 schema 與 `headword_norm` 查詢索引。

## 決策

1. 字典資料放獨立資料庫 `dictionary.db`（`app/lib/dictionary/storage/dictionary_database.dart`），路徑為 App 文件目錄下的 `dictionary.db`，**不改動主資料庫的 `version: 28`**，也不在 `sync_table_specs.dart` 登錄字典表。
2. `dictionary.db` 自帶版本號（目前 `DictionaryDatabase.version == 1`），遷移只影響字典資料。
3. 外鍵（`PRAGMA foreign_keys = ON`）放在 `openDatabase` 的 `onConfigure`，與主庫做法一致；每次開啟連線都生效，刪除來源時詞條以 `ON DELETE CASCADE` 連帶刪除（`dictionary_database_test.dart::每次開啟連線，外鍵都是開啟的`、`dictionary_store_test.dart::刪除來源會連帶刪除詞條`）。
4. MDX 原檔與附屬檔不放資料庫，放 App 私有目錄；刪除字典時由流程一併刪除（`dictionary_manager_test.dart::delete：來源、詞條、私有目錄都消失`）。
5. 跨庫查詢不存在：字典查詢只讀 `dictionary.db`，書庫只讀 `library.db`；需要組合的資訊（例如字典清單與書庫設定）在 Dart 端組合。
6. 守衛測試：`dictionary_database_test.dart::主資料庫版本仍為 28` 與 `::dictionary.db 與主庫是不同檔案，主庫沒有字典表`。

## 替代方案與取捨

- **放進主資料庫**：被否決。理由：(1) 每次字典 schema 變動都要動主庫版本與遷移，風險擴散到書庫、劃線、閱讀進度；(2) 字典表若被誤登錄進同步規格，十幾萬筆詞條會跟著帳號同步，違反「字典資料不進同步」的決定（`spec.md` §4）；(3) 使用者「刪掉整本字典重來」變成對主庫的大量刪除，transaction 與磁碟回收成本都壓在書庫上。
- **每本字典一個 SQLite 檔**：被否決。來源清單與優先順序需要跨檔彙整，排序與「一次只顯示一本」的分段查詢都得自己實作；`dictionary.db` 內的單表查詢已足夠快（p95 < 300 ms，開發機測試 `dictionary_service_test.dart::本機查詢 p95 小於 300 ms（含候選鏈）`）。
- **MDX 詞條全量轉入 SQLite**：被否決。MDX 本身就是索引化的字典檔，解析後再全量複製會讓磁碟用量加倍（100 MB 的字典變 200 MB 以上），且失去原檔的圖片與 CSS 資源。MDX 保留原檔，查詢時經 `MdxReader` 讀取（見 `app/third_party/dict_reader/PATCH.md` 的記憶體量測）。

## 後果

- 專案同時有兩個 SQLite 檔：`library.db`（書庫、同步）與 `dictionary.db`（字典）。備份或清除資料時要記得兩者。
- 字典可以整個刪除、整個重建，不影響書庫；主庫的 `version: 28` 與同步表規格完全不動（驗收 28）。
- 需要跨庫組合的查詢只能寫在 Dart 端；不能靠 SQL JOIN。
- 缺點是「開啟字典」多一次資料庫開啟成本，因此 `DictionaryService` 採延遲開啟（`dictionary_service_test.dart::建構時不開啟；第一次 lookup 才開，之後重用同一個 store`）。
