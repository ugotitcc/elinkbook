# Issue 2：模型、介面、`dictionary.db` 與 `DictionaryStore` 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立字典功能的資料層地基：模型、三個抽象介面、獨立的 `dictionary.db`，以及 `DictionaryStore`（來源與詞條的讀寫）。

**Architecture:** 新增 `app/lib/dictionary/`，只放純 Dart 與 `sqflite`，不碰 UI、不碰主庫。`dictionary.db` 自帶版本號（`version: 1`），連線層級的 `PRAGMA foreign_keys = ON` 放在 `onConfigure`，比照 `SqliteLibraryRepository.open`。`DictionaryStore` 包一個 `Database`，所有 SQL 都用參數化查詢。

**Tech Stack:** Dart／Flutter、`sqflite ^2.4.2+1`、`sqflite_common_ffi`（測試用）、`path`。不新增任何套件。

**Spec:** `docs/epics/epic-63-dictionary-lookup/spec.md` §3.1、§3.2、§3.3、§4、§7、§9（驗收 28）；`issues.md` 的 Issue 2。

## Global Constraints

- 不動主資料庫：`SqliteLibraryRepository.open` 的 `version` 仍為 `28`。
- 不登錄 `sync_table_specs.dart`（字典資料不進同步）。
- `PRAGMA foreign_keys = ON` 必須在 `openDatabase(..., onConfigure: ...)`，不可只放 `onCreate`。
- `headword_norm` 公式：`headword.trim().toLowerCase()`。不做 Unicode 正規化。
- `LookupRequest` 只有 `word` 一個欄位。
- 表結構逐字照 `spec.md` §4（兩張表加 `idx_entries_lookup`）。
- 所有文件與程式碼註解用正體中文；commit 訊息不加 `Co-Authored-By`。
- 每個 Task 只跑觸及的測試檔；完整 `flutter test` 只在最後一個 Task 跑一次。

## Review Focus

1. **同一 `headword_norm` 多筆**（`IT`、`it`）：預期兩筆都回傳，依 `id` 排序。
2. **查詢詞有前後空白或大小寫**（`' Run '` 查 `run`）：預期命中，因為查詢先套同一個公式。
3. **刪除不存在的來源**：預期不丟例外。
4. **空字串查詢**：預期回傳空清單，不丟例外、不回傳整本字典。
5. **詞條含 SQL 特殊字元與 CJK**（`'; DROP TABLE x;--`、`相濡以沫`）、**超大詞條**（1 MB 的 `body`）：預期原樣存取。

## 已決定事項（spec 沒寫清楚，本計畫的選擇）

- `DictionaryLang` 不建立。`spec.md` §3.1 列了它，但 §3.2 的模型用 `String`。以 §3.2 為準。
- `ImportRequest`、`ImportProgress`、`CancelToken` 在 spec 只有名字、沒有欄位。本 Issue 只放最小版本（見 Task 1），Issue 3 需要時再擴充。
- `headword_norm` 由 `DictionaryStore.insertEntries` 計算並寫入，匯入器不需自己算。查詢端用同一個頂層函式 `headwordNorm()`，公式只存在一處。
- `content_id`、`referenced_css` 欄位在表裡建立，但本 Issue 的 Store 不讀寫它們（Issue 3、6a 才用）。
- 單一交易包住整個匯入的 API，留給 Issue 3 加。

---

## 檔案結構

```text
app/lib/dictionary/
├── models/
│   ├── dictionary_source.dart     DictionaryFormat、DictionarySource
│   ├── dictionary_entry.dart      EntryBodyKind、DictionaryEntry、headwordNorm()
│   ├── lookup_request.dart        LookupRequest
│   └── lookup_result.dart         OutcomeStatus、ProviderOutcome、LookupResult
├── providers/
│   ├── dictionary_provider.dart         DictionaryProvider
│   └── online_dictionary_provider.dart  OnlineDictionaryProvider
├── importers/
│   └── dictionary_importer.dart   DictionaryImporter、ImportRequest、ImportProgress、CancelToken
└── storage/
    ├── dictionary_database.dart   DictionaryDatabase.open
    └── dictionary_store.dart      DictionaryStore

app/test/dictionary/
├── lookup_request_test.dart
├── dictionary_interfaces_test.dart
├── dictionary_database_test.dart
└── dictionary_store_test.dart
```

---

### Task 1：模型與抽象介面

**Files:**
- Create: `app/lib/dictionary/models/dictionary_source.dart`、`dictionary_entry.dart`、`lookup_request.dart`、`lookup_result.dart`
- Create: `app/lib/dictionary/providers/dictionary_provider.dart`、`online_dictionary_provider.dart`
- Create: `app/lib/dictionary/importers/dictionary_importer.dart`
- Test: `app/test/dictionary/lookup_request_test.dart`、`app/test/dictionary/dictionary_interfaces_test.dart`

**Interfaces:**
- Produces（Task 3、4 與後續 Issue 使用，名稱與型別照 `spec.md` §3.2、§3.3）：
  - `enum DictionaryFormat { jsonCsv, cedict, mdx }`
  - `class DictionarySource`：`const` 建構子，全部 `required` 具名參數；欄位 `id`、`name`、`format`、`sourceLang`、`targetLang`、`priority`、`enabled`、`storagePath`、`entryCount`、`licenseNote`、`importedAt`（型別見 spec §3.2）。
  - `enum EntryBodyKind { plainText, html }`
  - `class DictionaryEntry`：`const` 建構子；`sourceId`、`headword`、`body`、`bodyKind` 為 `required`，`pronunciation`、`partOfSpeech` 為可空具名參數。
  - `String headwordNorm(String headword)`：回傳 `headword.trim().toLowerCase()`。
  - `class LookupRequest { const LookupRequest(this.word); final String word; }`，覆寫 `==`、`hashCode`。
  - `enum OutcomeStatus { found, notFound, skipped, failed }`
  - `class ProviderOutcome`：`const` 建構子；`providerId`、`displayName`、`status` 為 `required`，`entries` 預設 `const []`，`attribution`、`errorCode` 可空。
  - `class LookupResult`：`const` 建構子；`request`、`outcomes`（兩者 `required`）。
  - `abstract class DictionaryProvider { String get id; Future<ProviderOutcome> lookup(LookupRequest request); }`
  - `abstract class OnlineDictionaryProvider implements DictionaryProvider {}`
  - `class CancelToken { bool get isCancelled; void cancel(); }`
  - `class ImportRequest { final String filePath; final String fileName; final String sourceLang; final String targetLang; }`（`const` 建構子，全部 `required`）
  - `class ImportProgress { final int processed; final int total; }`（`const` 建構子，全部 `required`）
  - `abstract class DictionaryImporter { bool canHandle(String fileName); Stream<ImportProgress> import(ImportRequest request, {required CancelToken cancel}); }`

- [ ] **Step 1: 寫失敗的測試 `lookup_request_test.dart`**

測試名稱與斷言：
- `test('相同的詞視為相等')`：`expect(const LookupRequest('run'), const LookupRequest('run'))`；`expect(const LookupRequest('run'), isNot(const LookupRequest('ran')))`。
- `test('型別只有 word 一個欄位，防止日後加前後文欄位')`：用 `File('lib/dictionary/models/lookup_request.dart').readAsStringSync()` 讀原始碼，以 `RegExp(r'^\s*(final|late|var)\s', multiLine: true)` 數欄位宣告，`expect(count, 1)`，並 `expect(source, contains('final String word;'))`。測試註解說明：Dart 無法反射列舉欄位，所以用原始碼掃描守住這條隱私底線（對應 spec §3.2 的「從型別上保證不可能把書中內容送出去」）。

- [ ] **Step 2: 寫失敗的測試 `dictionary_interfaces_test.dart`**

在測試檔內寫一個 `_FakeProvider implements DictionaryProvider` 與一個 `_FakeOnline implements OnlineDictionaryProvider`，一個 `_FakeImporter implements DictionaryImporter`。
- `test('DictionaryProvider 回傳 ProviderOutcome')`：`lookup(const LookupRequest('run'))` 回傳 `status == OutcomeStatus.found`、`entries.length == 1`。
- `test('OnlineDictionaryProvider 也是 DictionaryProvider')`：`expect(_FakeOnline(), isA<DictionaryProvider>())`。
- `test('CancelToken 取消後 isCancelled 為 true')`：建構後 `isCancelled == false`；`cancel()` 後 `true`。
- `test('headwordNorm 去頭尾空白並轉小寫')`：`headwordNorm('  IT ')` 等於 `'it'`；`headwordNorm('相濡以沫')` 原樣不變。

- [ ] **Step 3: 執行測試，確認失敗**

Run（在 `app/`）: `flutter test test/dictionary/lookup_request_test.dart test/dictionary/dictionary_interfaces_test.dart`
Expected: FAIL，錯誤為找不到 `package:elinkbook/dictionary/...`（import 找不到）。

- [ ] **Step 4: 實作上述 Interfaces 區塊列出的所有型別**

放在「Files」列出的檔案。每個檔案頂端用中文類別註解說明用途；`LookupRequest` 的註解要寫明「刻意只有一個詞，沒有前後文欄位」。`CancelToken` 用單一私有 `bool` 實作。

- [ ] **Step 5: 執行測試，確認通過**

Run: `flutter test test/dictionary/lookup_request_test.dart test/dictionary/dictionary_interfaces_test.dart`
Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add app/lib/dictionary app/test/dictionary
git commit -m "feat(epic-63): Issue 2 字典模型與抽象介面"
```

---

### Task 2：`dictionary.db` 開啟與版本

**Files:**
- Create: `app/lib/dictionary/storage/dictionary_database.dart`
- Test: `app/test/dictionary/dictionary_database_test.dart`

**Interfaces:**
- Consumes: 無（只用 `sqflite`）。
- Produces: `abstract final class DictionaryDatabase { static const int version = 1; static Future<Database> open(String path, {bool singleInstance = true}); }`。`open` 比照 `SqliteLibraryRepository.open`：`singleInstance` 預設 `true`；測試要在同一個 process 開多個 `:memory:` 時傳 `false`。

- [ ] **Step 1: 寫失敗的測試 `dictionary_database_test.dart`**

`setUpAll` 比照 `app/test/search/search_repository_test.dart`：`sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;`。測試名稱與斷言：
- `test('建立兩張表與查詢索引')`：開 `inMemoryDatabasePath`（`singleInstance: false`），查 `sqlite_master`，斷言有表 `dictionary_sources`、`dictionary_entries` 與索引 `idx_entries_lookup`。
- `test('版本為 1')`：`expect(await db.getVersion(), 1)`。
- `test('每次開啟連線，外鍵都是開啟的')`：用 `Directory.systemTemp.createTempSync()` 下的檔案路徑。第一次開啟 → 寫入一筆來源（用原生 `db.insert('dictionary_sources', {...})`，欄位照 spec §4，`imported_at` 給 ISO 字串）與兩筆詞條 → `close()` → **第二次**用 `singleInstance: false` 重新開啟同一路徑 → 斷言 `PRAGMA foreign_keys` 回傳 `1`；刪除該來源列後，`dictionary_entries` 的 `count(*)` 為 `0`。`tearDown` 刪除暫存目錄。
- `test('主資料庫版本仍為 28')`：`final repo = await SqliteLibraryRepository.open(inMemoryDatabasePath, singleInstance: false)`；`expect(await repo.database.getVersion(), 28)`；`await repo.close()`。
- `test('dictionary.db 與主庫是不同檔案')`：用兩個不同暫存路徑各開一個，確認 `dictionary_sources` 不存在於主庫（`sqlite_master` 查無）。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/dictionary/dictionary_database_test.dart`
Expected: FAIL，找不到 `DictionaryDatabase`。

- [ ] **Step 3: 實作 `DictionaryDatabase.open`**

`openDatabase(path, version: version, singleInstance: singleInstance, onConfigure: ..., onCreate: ...)`。`onConfigure` 只執行 `PRAGMA foreign_keys = ON`；`onCreate` 逐字執行 `spec.md` §4 的兩個 `CREATE TABLE` 與一個 `CREATE INDEX`。類別註解寫明：外鍵設定放 `onConfigure` 的原因（連線層級，每次開啟都要設），並指向 `sqlite_library_repository.dart` 的同一做法。

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/dictionary/dictionary_database_test.dart`
Expected: PASS（5 個測試）。

- [ ] **Step 5: Commit**

```bash
git add app/lib/dictionary/storage/dictionary_database.dart app/test/dictionary/dictionary_database_test.dart
git commit -m "feat(epic-63): Issue 2 dictionary.db 開啟與外鍵設定"
```

---

### Task 3：`DictionaryStore`

**Files:**
- Create: `app/lib/dictionary/storage/dictionary_store.dart`
- Test: `app/test/dictionary/dictionary_store_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `DictionarySource`、`DictionaryEntry`、`DictionaryFormat`、`EntryBodyKind`、`headwordNorm()`；Task 2 的 `DictionaryDatabase.open`。
- Produces（Issue 3、5 使用）：
  ```dart
  class DictionaryStore {
    DictionaryStore(this._db); // Database
    Future<void> insertSource(DictionarySource source);
    Future<List<DictionarySource>> listSources({bool enabledOnly = false});
    Future<void> setEnabled(String sourceId, bool enabled);
    Future<void> setPriority(String sourceId, int priority);
    Future<void> deleteSource(String sourceId);
    Future<void> insertEntries(List<DictionaryEntry> entries);
    Future<List<DictionaryEntry>> lookup(String sourceId, String word);
  }
  ```
  - `listSources` 排序：`priority ASC, imported_at ASC, id ASC`。
  - `insertEntries` 用 `Batch` 一次寫入，計算並寫入 `headword_norm`。
  - `lookup` 先把 `word` 套 `headwordNorm()`，比對 `source_id` 與 `headword_norm`，依 `id` 排序；`word` 去空白後為空時直接回傳 `const []`。
  - `format` 存 `DictionaryFormat.name`、`body_kind` 存 `EntryBodyKind.name`、`imported_at` 存 UTC 的 ISO 8601 字串；`storagePath`、`licenseNote` 空字串存成 `''`（讀回仍是 `''`）。

- [ ] **Step 1: 寫失敗的測試 `dictionary_store_test.dart`**

`setUp` 開 `inMemoryDatabasePath`（`singleInstance: false`）並建立 `DictionaryStore`；`tearDown` 關閉。測試檔內寫 `_source({id, priority, enabled})` 與 `_entry(sourceId, headword, {body})` 兩個小工廠。測試名稱與斷言：
- `test('寫入來源後可完整讀回')`：每個欄位相等，含 `importedAt`（UTC）與 `format`。
- `test('依優先順序列出，數字小者在前')`：priority 3、1、2 → 讀回 id 順序為 priority 1、2、3；priority 相同時依 `imported_at` 再依 `id`。
- `test('enabledOnly 只回傳啟用的來源')`：停用一本後 `listSources(enabledOnly: true)` 不含它；`listSources()` 仍含。
- `test('setEnabled 與 setPriority 會更新並影響排序')`。
- `test('寫入詞條並以 headword_norm 查詢')`：寫 `Run`，`lookup(id, 'run')` 與 `lookup(id, 'RUN')` 都命中，回傳的 `headword` 仍是 `Run`（保留原樣）。
- `test('查詢詞有前後空白也命中')`（Review Focus 2）：`lookup(id, ' Run ')` 命中。
- `test('同一 headword_norm 多筆全回傳，依 id 排序')`（Review Focus 1）：寫 `IT`、`it`，`lookup(id, 'it')` 回傳兩筆，順序為寫入順序。
- `test('只查指定來源')`：兩本字典各有 `run`，`lookup` 只回傳指定那本的。
- `test('空字串與純空白查詢回傳空清單')`（Review Focus 4）：寫入一些詞條後 `lookup(id, '')`、`lookup(id, '   ')` 皆為空清單。
- `test('刪除來源會連帶刪除詞條')`：刪除後 `lookup` 為空清單，且 `dictionary_entries` 的 `count(*)` 為 `0`。
- `test('刪除不存在的來源不丟例外')`（Review Focus 3）。
- `test('刪除一本不影響另一本的詞條')`。
- `test('SQL 特殊字元、CJK 與超大詞條原樣存取')`（Review Focus 5）：`headword` 用 `"'; DROP TABLE dictionary_entries;--"` 與 `'相濡以沫'`；`body` 用 1,000,000 字元的字串；讀回相等，且表仍存在。
- `test('重複的來源 id 寫入失敗，且不留下半筆')`：第二次 `insertSource` 同 id → `expect(..., throwsA(isA<DatabaseException>()))`；`listSources()` 仍只有一筆。
- `test('寫入詞條給不存在的來源會失敗（外鍵生效）')`：`expect(store.insertEntries([_entry('missing', 'x')]), throwsA(isA<DatabaseException>()))`。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/dictionary/dictionary_store_test.dart`
Expected: FAIL，找不到 `DictionaryStore`。

- [ ] **Step 3: 實作 `DictionaryStore`**

簽章見 Interfaces。所有 SQL 用 `?` 參數或 `db.insert/query/update/delete` 的 `where`/`whereArgs`，不拼字串。來源與詞條的 `Map` 轉換寫成兩個私有方法（`_sourceToRow`／`_rowToSource`、`_entryToRow`／`_rowToEntry`）。類別註解註明：`headword_norm` 公式只存在 `headwordNorm()` 一處。

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/dictionary/dictionary_store_test.dart`
Expected: PASS（14 個測試）。

- [ ] **Step 5: Commit**

```bash
git add app/lib/dictionary/storage/dictionary_store.dart app/test/dictionary/dictionary_store_test.dart
git commit -m "feat(epic-63): Issue 2 DictionaryStore 來源與詞條讀寫"
```

---

### Task 4：整體驗證與進度更新

**Files:**
- Modify: `docs/epics/epic-63-dictionary-lookup/issues.md`（Issue 2 的 `Status`）
- Modify: `docs/epics/epic-63-dictionary-lookup/plans/plan-issue-2.md`（勾選步驟）

- [ ] **Step 1: 執行本 Issue 全部測試**

Run（在 `app/`）: `flutter test test/dictionary/`
Expected: 全數 PASS。

- [ ] **Step 2: 靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 兩支檢查腳本**

Run: `node tool/check_l10n_hardcoded_strings.js` 與 `node tool/check_integration_keys.js`
Expected: 兩支都通過（本 Issue 沒有 UI，預期無變化）。

- [ ] **Step 4: 確認沒有碰到禁區**

Run（在專案根目錄）: `git diff main --stat -- app/lib/library app/lib/sync app/pubspec.yaml`
Expected: 無輸出（主庫、同步、`pubspec.yaml` 都沒動）。

- [ ] **Step 5: 完整 `flutter test`（整張計畫最後一個 Task）**

Run: `flutter test`
Expected: 全數 PASS。把通過時間與 commit 記進 PR 說明。

- [ ] **Step 6: 更新 `issues.md` 的 Issue 2 狀態，勾選本計畫所有步驟，Commit**

```bash
git add docs/epics/epic-63-dictionary-lookup
git commit -m "docs(epic-63): Issue 2 實作完成，更新狀態"
```

---

## 自我檢查

- **Spec 覆蓋：** Issue 2 的 6 條 What-to-build 對應 Task 1（模型、介面）、Task 2（資料庫、`onConfigure`、不動主庫）、Task 3（Store）。4 條測試要求對應 `dictionary_store_test.dart`、`lookup_request_test.dart`、`dictionary_database_test.dart`（版本 28、重開後 cascade）。驗收 28 在 Task 2。
- **型別一致：** `headwordNorm()`、`DictionaryStore.lookup`、`DictionaryDatabase.open` 的名稱在 Task 1、2、3 之間一致。
- **比例：** 計畫只寫簽章、測試名稱與斷言，不寫函式本體。
