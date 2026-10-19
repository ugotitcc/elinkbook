# Issue 3：JSON/CSV 與 CC-CEDICT 匯入、重複匯入偵測、查詢候選鏈、本機查詢 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓字典資料能進得來、查得到：兩種匯入器（JSON/CSV、CC-CEDICT）、重複匯入偵測、選字處理、查詢候選鏈，以及只查本機的 `DictionaryService`。

**Architecture:** 純 Dart，不碰 UI。兩個匯入器共用一條匯入流程（`import_pipeline.dart`）：解析放進 `Isolate.run()`（只回傳純資料），寫入留在主 Isolate，用 Issue 2 的 `DictionaryStore.transaction()` 包成單一交易，每批 2,000 筆之間檢查 `CancelToken`。查詢端是一串純函式（選字處理 → 候選清單 → 詞形還原），由 `LocalDictionaryProvider`（一本字典一個）與 `DictionaryService`（挑字典、組裝結果）串起來。

**Tech Stack:** Dart／Flutter、`sqflite`（沿用 Issue 2）、`crypto`（已有）、`uuid`（已有）、`dart:isolate`。不新增任何套件；CSV 用自寫的小解析器（`pubspec.lock` 沒有 `csv`）。

**Spec:** `docs/epics/epic-63-dictionary-lookup/spec.md` §3.3（執行緒分工）、§3.4（查詢流程與選字處理）、§4、§5、§7、§9（驗收 1、2、12、13、14、20、23、24、33、37）；`issues.md` 的 Issue 3；Issue 2 程式審查延後項見 `reviews/review-code-issue-2.md`（M-7、M-8、M-9）。

## Global Constraints

- 不新增套件；不動 `pubspec.yaml`、主資料庫（`version: 28`）、`sync_table_specs.dart`。
- `headword_norm` 公式只有一處：`headwordNorm()`（Issue 2）。寫入由 `DictionaryStore.insertEntries` 計算，匯入器不自己算。
- `Isolate.run()` 的 closure 必須是參數只含可跨 Isolate 型別的頂層函式（`CLAUDE.md`「不可逆的技術決策」）。
- 單筆 `definition` 上限 64 KB（UTF-8 位元組 65,536），超過略過並計數。
- 每批寫入 2,000 筆；取消時整個交易回復，資料庫無殘留。
- 詞形還原只登錄英文；未登錄語言回傳空清單，不把英文規則套到中文。
- 不做 Unicode NFC／NFD 正規化。
- 檔名一律用呼叫端傳入的真實檔名（`PlatformFile.name`），不從路徑解析。
- 所有文件與註解用正體中文；commit 訊息不加 `Co-Authored-By`。
- 每個 Task 只跑觸及的測試檔；完整 `flutter test` 只在最後一個 Task 跑一次。

## Review Focus

1. **Excel 匯出的 CSV**：UTF-8 BOM 開頭、CRLF 換行、欄位內有逗號與換行（引號包住）。預期：BOM 不進欄名，其餘正確解析（Task 3）。
2. **跨行選取的片語**：選字含換行或連續空白（`"kick  the\nbucket"`）。預期：整理成單一空白後整串查一次（Task 6）。
3. **取消匯入**：預期資料庫完全沒有來源列與詞條，且 `CancelToken` 在解析前就被取消也一樣（Task 3）。
4. **沒有任何有效筆數的檔案**（空陣列、全部缺欄）：預期丟出明確錯誤，不建立空字典（Task 3）。
5. **1 至 2 個字母的英文詞**（`is`、`bus`、`a`）：預期詞形還原不丟例外，也不產生空字串候選（Task 7）。

## 已決定事項（spec 沒寫清楚，本計畫的選擇）

- **已確認（使用者選保留空白）：拼音顯示保留空白。** spec §5 與驗收 37 寫 `pin1 yin1` 顯示為 `pīnyīn`（無空白），但 §7 寫「多音節以空白分隔」。CC-CEDICT 不標詞界，全部串起來會把 `zhong1 guo2 ren2` 與詞組混在一起。本計畫採**保留空白**（`pīn yīn`）。spec §5、驗收 37 與 epic.md 已同步改為 `pīn yīn`。
- **語言方向挑選：** 選字為拉丁 → 挑 `sourceLang` 主語言為 `en` 的字典；CJK → `zh`；混合 → `zh` 與 `en` 都挑。比對只看語言碼第一段（`zh-Hant`、`zh` 都算 `zh`；`en-US` 算 `en`）。
- **候選依字典語言產生：** 詞形還原依每本字典的 `sourceLang` 查登錄表，所以查中文字典時不會套英文規則（驗收 14）。
- **候選清單與去重分兩層：** `lookupCandidates()` 回傳含大小寫變體的完整清單（MDX 之後要用）；`dedupeByHeadwordNorm()` 另一個函式，由 `LocalDictionaryProvider` 套用（JSON/CSV/CEDICT 的比對本來就不分大小寫）。
- **新字典優先順序：** 取目前最大 `priority` 加 1，排在最後。
- **取代已匯入的字典：** `ImportRequest.replaceExisting = true` 且找到同 `content_id` 的舊來源時，沿用舊的 `id`、`priority`、`enabled`，在同一個交易內先刪舊來源再寫新的，所以取代失敗不會讓使用者失去舊字典，取代成功也不會打亂使用者排好的順序與開關。
- **`content_id` 不加進 `DictionarySource` 模型：** 目前只有重複偵測用它，由 Store 的 `insertSource(..., {contentId})` 與 `findSourceIdByContentId` 處理就夠。等 Issue 5／6a 真的需要從物件讀它再加（審查 I-2 提議加欄位，本計畫暫不採用）。
- **匯入期間查詢（Issue 2 審查 M-9）：** 單一交易會讓同一連線上的查詢排隊到匯入結束。本 Issue 不處理；Issue 5 的設定畫面在匯入進行中要顯示進度並暫停查詢入口，已記在計畫尾端「交給後續 Issue」。
- **`DictionaryImporter` 新增 `readHints()`：** Issue 5 的匯入畫面要在選檔後預填語言方向與名稱（spec §5：JSON 有填時代入選擇器）。這會改動 Issue 2 的介面，Task 1 同步更新 Issue 2 的測試替身。
- **`content://` 路徑：** 本 Issue 的 `content_id` 與匯入器只處理本機可讀檔案路徑（`file_picker` 會複製到快取目錄）。不呼叫原生 channel。
- **服務回傳型別：** `DictionaryService.lookup` 回傳 `sealed class DictionaryLookupResponse`（`LookupRejected` 或 `LookupCompleted`），不用例外傳遞「選取無效」。`outcomes` 為空代表沒有符合方向的字典，面板（Issue 4）顯示「尚未匯入字典」。

---

## 檔案結構

```text
app/lib/dictionary/
├── importers/
│   ├── dictionary_importer.dart   [修改] 擴充 ImportRequest／ImportProgress，新增摘要、例外、readHints
│   ├── import_pipeline.dart       解析（Isolate）→ 單一交易分批寫入 → 取消回復
│   ├── csv_rows.dart              RFC 4180 的最小 CSV 解析器
│   ├── json_csv_importer.dart     JsonCsvImporter
│   └── cedict_importer.dart       CedictImporter
├── storage/dictionary_store.dart  [修改] content_id 讀寫
├── content_id.dart                computeContentId
├── pinyin_tone_marks.dart         pinyinToneMarks
├── lookup_text_normalizer.dart    選字處理與字元類型
├── lookup_candidates.dart         lookupCandidates、dedupeByHeadwordNorm
├── lemmatize/
│   ├── lemmatizer.dart            Lemmatizer 型別與語言登錄表
│   └── english_lemmatizer.dart
├── providers/local_dictionary_provider.dart
└── dictionary_service.dart

app/test/dictionary/  對應的 *_test.dart（見各 Task）
```

---

### Task 1：匯入型別、`readHints` 與 Store 的 `content_id`

**Files:**
- Modify: `app/lib/dictionary/importers/dictionary_importer.dart`
- Modify: `app/lib/dictionary/storage/dictionary_store.dart`
- Modify: `app/test/dictionary/dictionary_interfaces_test.dart`（替身補 `readHints`）
- Test: `app/test/dictionary/dictionary_store_test.dart`（新增 group）、`app/test/dictionary/dictionary_interfaces_test.dart`

**Interfaces:**
- Consumes: Issue 2 的 `ImportRequest`、`ImportProgress`、`CancelToken`、`DictionaryStore`。
- Produces:
  - `ImportRequest` 新增具名參數（皆有預設，Issue 2 的呼叫不變）：`String? name`、`String licenseNote = ''`、`bool replaceExisting = false`。
  - `enum ImportStage { parsing, writing, done, cancelled }`
  - `class ImportSkip { final int index; final String reason; }`（`const`；`index` 為檔內第幾筆，從 1 起算；`reason` 為 `missingHeadword`、`missingDefinition`、`definitionTooLong`、`malformedLine` 之一）
  - `class ImportSummary { final String sourceId; final int importedCount; final int skippedCount; final List<ImportSkip> skipSamples; }`（`skipSamples` 最多 5 筆）
  - `ImportProgress` 新增 `ImportStage stage = ImportStage.writing`、`ImportSummary? summary`（`done` 時才有）。
  - `class ImportHints { final String name; final String? sourceLang; final String? targetLang; final String? licenseNote; }`（`const`）
  - `class DictionaryImportException implements Exception { final String code; }`，`code` 為 `unreadableFile`、`invalidEncoding`、`invalidFormat`、`noValidEntries` 之一。
  - `class DuplicateDictionaryException implements Exception { final String existingSourceId; }`
  - `DictionaryImporter` 新增 `Future<ImportHints> readHints(String filePath, String fileName);`
  - `DictionaryStore`：`insertSource(DictionarySource source, {String? contentId})`（新增選填參數）、`Future<String?> findSourceIdByContentId(String contentId)`。

- [x] **Step 1: 寫失敗的測試**

`dictionary_store_test.dart` 新增 `group('content_id')`：
- `test('寫入時帶 contentId，可用它找回來源 id')`：`insertSource(_source('a'), contentId: 'cid-1')`；`findSourceIdByContentId('cid-1')` 等於 `'a'`。
- `test('找不到 contentId 回傳 null；沒帶 contentId 的來源不會被找到')`。
- `test('刪除來源後，同一個 contentId 找不到')`。

`dictionary_interfaces_test.dart`：`_FakeImporter` 補 `readHints`（回傳 `ImportHints(name: 'x')`），新增 `test('ImportProgress 預設為寫入階段且沒有摘要')`：`const ImportProgress(processed: 1, total: 2)` 的 `stage == ImportStage.writing`、`summary == null`。

- [x] **Step 2: 執行測試，確認失敗**

Run（在 `app/`）: `flutter test test/dictionary/dictionary_store_test.dart test/dictionary/dictionary_interfaces_test.dart`
Expected: FAIL（找不到 `findSourceIdByContentId`、`ImportStage`、`ImportHints`）。

- [x] **Step 3: 實作上述 Interfaces**

型別放在 `dictionary_importer.dart`。`insertSource` 把 `contentId` 寫進 `content_id` 欄。`findSourceIdByContentId` 用參數化查詢回傳第一筆的 `id`。

- [x] **Step 4: 執行測試，確認通過**

Run: 同 Step 2。Expected: PASS。

- [x] **Step 5: Commit**

```bash
git add app/lib/dictionary app/test/dictionary
git commit -m "feat(epic-63): Issue 3 匯入型別擴充與 Store 的 content_id"
```

---

### Task 2：`content_id`（重複匯入偵測）

**Files:**
- Create: `app/lib/dictionary/content_id.dart`
- Test: `app/test/dictionary/content_id_test.dart`

**Interfaces:**
- Consumes: 無。
- Produces: `Future<String> computeContentId({required String filePath, required String fileName})`。

算法（spec §5）：檔案 ≥ 128 KB（131,072 位元組）時，取前 64 KB 與後 64 KB 各算 SHA-256；小於 128 KB 時只雜湊整個檔案。最後對 `'$headHash:$tailHash:$size:$fileName'` 再算一次 SHA-256 的十六進位字串。小檔案時 `tailHash` 用空字串。用 `RandomAccessFile` 讀區段，不整檔讀進記憶體。

- [x] **Step 1: 寫失敗的測試 `content_id_test.dart`**

用 `Directory.systemTemp.createTempSync()` 建檔，`tearDown` 刪除。
- `test('相同內容與檔名，兩次計算結果相同')`
- `test('內容不同，ID 不同')`
- `test('檔名不同，ID 不同')`
- `test('大小相同、只差中間一個位元組的大檔案，ID 相同')`：200 KB 檔案，改動第 100,000 個位元組（在前 64 KB 與後 64 KB 之外）→ ID 相同。註解寫明這是 spec 刻意的取捨（只看頭尾）。
- `test('改動頭 64 KB 或尾 64 KB 內的位元組，ID 不同')`
- `test('小於 128 KB 的檔案改動任一位元組，ID 都不同')`
- `test('空檔案可計算')`
- `test('檔案不存在丟 DictionaryImportException(unreadableFile)')`

- [x] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/dictionary/content_id_test.dart`
Expected: FAIL（找不到 `computeContentId`）。

- [x] **Step 3: 實作 `computeContentId`**

簽章見 Interfaces。`FileSystemException` 轉成 `DictionaryImportException('unreadableFile')`。

- [x] **Step 4: 執行測試，確認通過**

Run: 同 Step 2。Expected: PASS。

- [x] **Step 5: Commit**

```bash
git add app/lib/dictionary/content_id.dart app/test/dictionary/content_id_test.dart
git commit -m "feat(epic-63): Issue 3 重複匯入偵測 content_id"
```

---

### Task 3：匯入流程與 `JsonCsvImporter`

**Files:**
- Create: `app/lib/dictionary/importers/csv_rows.dart`、`import_pipeline.dart`、`json_csv_importer.dart`
- Test: `app/test/dictionary/csv_rows_test.dart`、`app/test/dictionary/json_csv_importer_test.dart`

**Interfaces:**
- Consumes: Task 1 的型別與 `DictionaryStore`；Task 2 的 `computeContentId`；Issue 2 的 `DictionarySource`、`DictionaryEntry`、`CancelToken`。
- Produces:
  - `List<List<String>> parseCsvRows(String text)`：RFC 4180。支援引號包住的逗號、換行與 `""` 跳脫；`\r\n` 與 `\n` 都算換行；忽略結尾的空列。
  - `class ParseInput { final String filePath; final String sourceId; }`（`const`，只含可跨 Isolate 傳遞的型別）
  - `class ParsedDictionary { final String? name; final String? sourceLang; final String? targetLang; final String? licenseNote; final List<DictionaryEntry> entries; final int skippedCount; final List<ImportSkip> skipSamples; }`
  - `typedef DictionaryParser = ParsedDictionary Function(ParseInput input)`（必須是頂層函式）
  - `Future<ParsedDictionary> runParserInIsolate(DictionaryParser parser, ParseInput input)`：頂層函式，內容只有 `Isolate.run(() => parser(input))`。
  - `Stream<ImportProgress> runImportPipeline({required DictionaryStore store, required ImportRequest request, required CancelToken cancel, required DictionaryFormat format, required DictionaryParser parser, String Function()? newId, DateTime Function()? now})`
  - `class JsonCsvImporter implements DictionaryImporter`，建構子 `JsonCsvImporter({required DictionaryStore store})`；`canHandle` 吃 `.json`、`.csv`（不分大小寫）。
  - 頂層解析函式 `ParsedDictionary parseJsonCsvFile(ParseInput input)`。

匯入流程 `runImportPipeline` 的行為（以事件順序描述）：
1. 發出 `ImportProgress(stage: parsing, processed: 0, total: 0)`。
2. `computeContentId`；`store.findSourceIdByContentId` 已有同 ID 且 `!replaceExisting` → `addError(DuplicateDictionaryException)` 後結束。
3. **解析前先決定 `sourceId`**（解析器在 Isolate 內建立詞條，詞條必須帶正確的 `sourceId`，主 Isolate 不再逐筆複製）：
   - `replaceExisting` 且步驟 2 找到舊來源 → 沿用舊來源的 `id`，並用 `store.getSource` 讀出舊的 `priority` 與 `enabled`，新來源原樣帶過去（使用者排好的順序與開關不因取代而重設）。
   - 其他情況 → `id` 用 `newId()`，`priority` 取目前最大值加 1，`enabled` 為 `true`。
4. `runParserInIsolate(parser, ParseInput(filePath, sourceId))`；`DictionaryImportException` 原樣 `addError`。解析結果 `entries` 為空 → `addError(DictionaryImportException('noValidEntries'))`，不碰資料庫。
5. 解析完成後若 `cancel.isCancelled` → 發出 `stage: cancelled` 結束，不碰資料庫。
6. `store.transaction((txnStore) async { … })`：**交易內所有寫入只能用 `txnStore`，不可用外層的 `store`**（外層 `store` 會等不到連線而永遠卡住，見 `DictionaryStore.transaction` 的合約註解）。內容：`replaceExisting` 且有舊來源時先 `txnStore.deleteSource(sourceId)`；`txnStore.insertSource`（用步驟 3 決定的 `id`、`priority`、`enabled`，`contentId` 帶入，`entryCount` 為 `entries.length`）；每 2,000 筆 `txnStore.insertEntries` 並發出 `ImportProgress(stage: writing, processed, total)`；每批之前檢查 `cancel.isCancelled`，已取消就丟內部例外讓交易回復，然後發出 `stage: cancelled`。
7. 成功後發出 `ImportProgress(stage: done, processed: total, total: total, summary: ...)`。
8. 所有失敗（重複、解析、空檔、寫入）一律 `controller.addError(e)` 後 `await controller.close()`，不在非同步回呼裡直接 `throw`，呼叫端才接得到。

`name` 優先序：`request.name` → 解析結果的 `name` → 去掉副檔名的 `request.fileName`。`sourceLang`／`targetLang` 以 `request` 為準。`licenseNote` 優先序：`request.licenseNote`（非空）→ 解析結果。

`parseJsonCsvFile` 規則：
- 位元組以 `utf8.decode(bytes, allowMalformed: false)` 解碼，失敗 → `DictionaryImportException('invalidEncoding')`；開頭的 BOM 先去掉。
- 依 `ParseInput.filePath` 的副檔名分流（`.json`／`.csv`）。
- JSON：頂層必須是物件且 `entries` 是陣列，否則 `invalidFormat`；每筆欄位 `headword`、`definition`（必填）、`pronunciation`、`pos`。
- CSV：第一列為標題，欄名去空白、不分大小寫；缺 `headword` 或 `definition` 欄 → `invalidFormat`。
- `headword` 去空白後為空 → 略過（`missingHeadword`）；`definition` 去空白後為空 → `missingDefinition`；`definition` 的 UTF-8 位元組超過 65,536 → `definitionTooLong`。
- 每筆 `bodyKind` 為 `plainText`；`partOfSpeech` 取自 `pos`。

- [ ] **Step 1: 寫失敗的測試**

`csv_rows_test.dart`：
- `test('基本多列多欄')`
- `test('引號內的逗號與換行不分割')`：`'a,"b,c"\n"d\ne",f'` → `[['a','b,c'],['d\ne','f']]`
- `test('"" 跳脫成單一引號')`
- `test('CRLF 與結尾空列')`：`'a,b\r\nc,d\r\n'` → 兩列。
- `test('空字串回傳空清單')`

`json_csv_importer_test.dart`（`setUp` 開記憶體 `dictionary.db`；暫存目錄寫測試檔；`runImport` 小工具把 stream 收成 list 並回傳最後一個事件）：
- `test('canHandle 依副檔名判斷，不分大小寫')`
- `test('正常 JSON：寫入來源與詞條，進度最後為 done 並帶摘要')`：`importedCount == 筆數`、`skippedCount == 0`；`store.lookup` 查得到；來源的 `name`、`sourceLang`、`targetLang`、`licenseNote` 正確。
- `test('正常 CSV')`
- `test('Excel 匯出的 CSV：UTF-8 BOM、CRLF、引號內有逗號與換行')`（Review Focus 1）：欄名 `headword` 不帶 BOM；含逗號與換行的 `definition` 原樣存入。
- `test('CSV 欄名不分大小寫與前後空白')`：`' Headword , DEFINITION '`。
- `test('缺 definition 欄的 CSV 丟 invalidFormat')`
- `test('JSON 頂層不是物件或 entries 不是陣列丟 invalidFormat')`
- `test('壞編碼丟 invalidEncoding')`：寫入 `[0xff, 0xfe, 0x00]` 之外的非法 UTF-8 位元組序列（如 `[0xC3, 0x28]`）。
- `test('缺必填欄的列略過並計數，摘要帶前 5 筆原因')`：6 筆壞資料 → `skippedCount == 6`、`skipSamples.length == 5`、`reason` 正確、`index` 為檔內序號。
- `test('超過 64 KB 的 definition 略過')`：65,537 位元組略過；恰好 65,536 位元組通過。
- `test('沒有任何有效筆數丟 noValidEntries，且不建立來源')`（Review Focus 4）：空陣列；以及全部缺欄兩種。
- `test('重複匯入同一檔案丟 DuplicateDictionaryException，帶既有來源 id')`
- `test('replaceExisting 在同一交易內取代舊字典')`：舊詞條消失、新詞條存在、來源只剩一本；另測「取代時新檔解析失敗，舊字典仍在」。
- `test('replaceExisting 保留舊字典的 id、優先順序與啟用狀態')`：先匯入兩本，把第一本 `setEnabled(false)`、`setPriority(7)`；再用同一個檔案、`replaceExisting: true` 重匯第一本 → `id` 不變、`priority == 7`、`enabled == false`，來源只剩兩本。
- `test('新字典優先順序排在最後')`
- `test('詞條的 sourceId 在解析時就已正確，寫入不發生外鍵錯誤')`：匯入後 `store.lookup(sourceId, …)` 查得到，且 `PRAGMA foreign_key_check` 無結果。
- `test('取消：解析前就取消，資料庫無來源與詞條')`（Review Focus 3）
- `test('取消：寫入中途取消，整個交易回復')`：5,000 筆、第一批寫完後 `cancel()`（用 `listen` 在收到第一個 writing 事件時取消）；最後事件 `stage == cancelled`；`listSources()` 為空、`dictionary_entries` 為 0 筆。
- `test('readHints 回傳 JSON 內的名稱與語言；沒有就用檔名')`
- `test('匯入 10 萬筆：有多個進度事件，完成後可查詢')`（驗收 24）：進度事件數大於 10；最後 `importedCount == 100000`；`testWidgets` 不用，`timeout: Timeout(Duration(seconds: 120))`。
- `test('匯入 10 萬筆可在中途取消')`：收到第 3 個 writing 事件時取消 → `cancelled`，資料庫無殘留。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/dictionary/csv_rows_test.dart test/dictionary/json_csv_importer_test.dart`
Expected: FAIL（找不到 `parseCsvRows`、`JsonCsvImporter`）。

- [ ] **Step 3: 實作 `csv_rows.dart`、`import_pipeline.dart`、`json_csv_importer.dart`**

簽章見 Interfaces。`runImportPipeline` 用 `StreamController` 驅動（交易 callback 內無法 `yield`）；內部取消用私有例外類別。`parseJsonCsvFile` 與 `runParserInIsolate` 必須是頂層函式，`Isolate.run` 的 closure 只引用 `parser` 與 `input` 兩個參數。`newId` 預設 `Uuid().v4()`，`now` 預設 `DateTime.now`。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/dictionary/importers app/test/dictionary
git commit -m "feat(epic-63): Issue 3 匯入流程與 JSON/CSV 匯入器"
```

---

### Task 4：`CedictImporter`

**Files:**
- Create: `app/lib/dictionary/importers/cedict_importer.dart`
- Test: `app/test/dictionary/cedict_importer_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `runImportPipeline`、`ParseInput`、`ParsedDictionary`。
- Produces: `class CedictImporter implements DictionaryImporter`，建構子 `CedictImporter({required DictionaryStore store})`；`canHandle` 吃 `.u8`、`.txt`（不分大小寫）；頂層 `ParsedDictionary parseCedictFile(ParseInput input)`。

行規則（spec §5）：
- 空行與 `#` 開頭的行略過；`#! license=` 的值存為 `licenseNote`（其餘 `#!` 檔頭忽略）。
- 資料行格式 `繁體 簡體 [pin1 yin1] /釋義1/釋義2/`。繁體與簡體各產生一筆詞條（兩者相同只產生一筆），共用 `pronunciation`（原文）、`body`（釋義用 `\n` 連接，一條一行）、`bodyKind == plainText`。釋義以 `/` 切開後要濾掉空字串（行尾的 `/` 會切出空項），免得 `body` 頭尾多出空行。
- 不符合格式的行略過並計數（`reason == malformedLine`）；`index` 為檔內行號。
- `readHints`：`name` 為去掉副檔名的檔名；`sourceLang == 'zh'`、`targetLang == 'en'`；`licenseNote` 取自檔頭。
- 解碼與 BOM 規則同 `parseJsonCsvFile`。

- [ ] **Step 1: 寫失敗的測試 `cedict_importer_test.dart`**

用自製小檔（不用真實 CC-CEDICT）。測試名稱與斷言：
- `test('註解行與空行略過，檔頭 license 存進 licenseNote')`：`#! license=Creative Commons Attribution-ShareAlike 4.0 International License`。
- `test('繁簡不同：各產生一個詞頭，共用內容')`：`學生 学生 [xue2 sheng5] /student/pupil/` → 查 `學生` 與 `学生` 都得到同一份 `body`（`'student\npupil'`）與 `pronunciation == 'xue2 sheng5'`。
- `test('繁簡相同：只產生一個詞頭')`：`的 的 [de5] /possessive particle/` → `importedCount == 1`。
- `test('釋義頭尾沒有空行')`：`/student/pupil/` 的 `body == 'student\npupil'`（不以 `\n` 開頭或結尾）。
- `test('拼音以原文存放，不轉聲調符號')`
- `test('交叉參照原文保留')`：`/see 學生|学生[xue2 sheng5]/` 的 `body` 原樣。
- `test('釋義內含斜線之外的特殊字元原樣保留')`：`CL:個|个[ge4]`。
- `test('壞行略過並計數')`：缺方括號、缺結尾 `/`、只有一個詞。
- `test('語言方向由 request 決定；readHints 預設 zh→en')`
- `test('canHandle 吃 .u8 與 .txt')`
- `test('全部是註解的檔案丟 noValidEntries')`
- `test('取消與重複匯入走同一條流程')`：同一檔案匯入兩次 → 第二次 `DuplicateDictionaryException`。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/dictionary/cedict_importer_test.dart`
Expected: FAIL（找不到 `CedictImporter`）。

- [ ] **Step 3: 實作 `CedictImporter` 與 `parseCedictFile`**

資料行用一個 `RegExp` 切三段（繁體、簡體、拼音、釋義）。其餘走 `runImportPipeline`，`format: DictionaryFormat.cedict`。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/dictionary/importers/cedict_importer.dart app/test/dictionary/cedict_importer_test.dart
git commit -m "feat(epic-63): Issue 3 CC-CEDICT 匯入器"
```

---

### Task 5：`pinyin_tone_marks`

**Files:**
- Create: `app/lib/dictionary/pinyin_tone_marks.dart`
- Test: `app/test/dictionary/pinyin_tone_marks_test.dart`

**Interfaces:**
- Produces: `String pinyinToneMarks(String raw)`。純函式，顯示端（Issue 4 的面板）呼叫。

規則（spec §5）：以空白切成片段，逐段處理，輸出以單一空白重新連接（見「已決定事項」第一條）。片段符合 `^[A-Za-züÜ:]+[1-5]$`（音節加聲調數字）才轉換，否則原樣保留（`3C`、`11`、單獨大寫字母、無數字的片段）。轉換：`u:`／`U:` 先變 `ü`／`Ü`；聲調 1 至 4 標在母音上，5 視為輕聲不標；標調位置：有 `a` 或 `e` 標在它上面，否則有 `ou` 標在 `o`，否則標在最後一個母音；大寫保留；聲調數字一律移除（含 5 與沒有母音的片段如 `r5` → `r`）。

- [ ] **Step 1: 寫失敗的測試 `pinyin_tone_marks_test.dart`**

- `test('聲調 1 至 4')`：`ma1`→`mā`、`ma2`→`má`、`ma3`→`mǎ`、`ma4`→`mà`。
- `test('聲調 5 與無數字為輕聲，不標')`：`ma5`→`ma`、`ma`→`ma`。
- `test('標調位置：a 或 e 優先')`：`hao3`→`hǎo`、`lei2`→`léi`、`xie4`→`xiè`。
- `test('ou 標在 o')`：`gou3`→`gǒu`。
- `test('其餘標在最後一個母音')`：`gui4`→`guì`、`liu2`→`liú`、`jiu3`→`jiǔ`。
- `test('u: 轉 ü')`：`lu:4`→`lǜ`、`nu:3`→`nǚ`、`Lu:4`→`Lǜ`。
- `test('非拼音片段原樣保留')`：`3C`、`11`、`A` 各自原樣；`A xue2` → `A xué`。
- `test('大寫保留')`：`Zhong1`→`Zhōng`。
- `test('多音節以空白分隔，空白保留')`：`pin1 yin1`→`pīn yīn`。
- `test('沒有母音的片段只去掉數字')`：`r5`→`r`。
- `test('空字串回傳空字串')`

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/dictionary/pinyin_tone_marks_test.dart`
Expected: FAIL。

- [ ] **Step 3: 實作 `pinyinToneMarks`**

母音加聲調用一張 `Map<String, List<String>>` 對照表（`a e i o u ü` 大小寫各 4 個聲調的預組字元）。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/dictionary/pinyin_tone_marks.dart app/test/dictionary/pinyin_tone_marks_test.dart
git commit -m "feat(epic-63): Issue 3 拼音聲調數字轉聲調符號"
```

---

### Task 6：`lookup_text_normalizer`

**Files:**
- Create: `app/lib/dictionary/lookup_text_normalizer.dart`
- Test: `app/test/dictionary/lookup_text_normalizer_test.dart`

**Interfaces:**
- Produces:
  - `enum SelectionProblem { invalidSelection, tooLong }`
  - `enum SelectionCharType { latin, cjk, mixed }`
  - `sealed class SelectionNormalization`；`final class NormalizedSelection extends SelectionNormalization { final String text; final SelectionCharType charType; }`；`final class RejectedSelection extends SelectionNormalization { final SelectionProblem problem; }`（皆 `const` 建構子）
  - `SelectionNormalization normalizeLookupSelection(String raw)`
  - `SelectionCharType detectCharType(String text)`

規則（spec §3.4「選字處理」，依序）：
1. 去頭尾空白與標點（Unicode `\p{P}`、`\p{S}`，含「」『』《》與各種引號）。
2. 空字串 → `invalidSelection`。
3. 內部連續空白（含換行）整理成單一空白（見 Review Focus 2）。
4. 含空白 → 片語：內部標點允許，整串視為有效，不設長度上限。
5. 不含空白：內部有標點或控制字元時，只有「不含 CJK 且該字元是 `-`、`'`、`’`」的情況允許（`state-of-the-art`、`don't`）；其餘 → `invalidSelection`（`天地，玄黃`）。
6. 不含空白且含 CJK：字元數（`runes.length`）超過 8 → `tooLong`。標點檢查先於長度檢查。
7. `detectCharType`：含 Han 字元（`RegExp(r'\p{Script=Han}', unicode: true)`，已用 Dart 確認可涵蓋擴展 B 區的 `𠀀`）為 CJK；含拉丁字母（`\p{Script=Latin}` 的字母）為拉丁；兩者皆有為 `mixed`；兩者皆無（例如純數字）歸 `latin`。

- [ ] **Step 1: 寫失敗的測試 `lookup_text_normalizer_test.dart`**

- `test('去頭尾標點：「相濡以沫」與《紅樓夢》')`：→ `相濡以沫`、`紅樓夢`，`charType == cjk`。
- `test('去頭尾空白與換行')`
- `test('內部標點：天地，玄黃 回傳 invalidSelection')`
- `test('連字號與撇號：state-of-the-art、don't、don’t 通過')`
- `test('含空白的片語允許內部標點，整串通過')`：`"Hello, world"`。
- `test('跨行選取的片語整理成單一空白')`（Review Focus 2）：`"kick  the\nbucket"` → `'kick the bucket'`。
- `test('CJK 8 字通過，9 字 tooLong')`
- `test('含空白的片語不受 8 字限制')`：長度 20 的片語通過。
- `test('標點檢查先於長度檢查')`：10 字含逗號 → `invalidSelection`。
- `test('空字串與純標點、純空白回傳 invalidSelection')`
- `test('混合文字的 CJK 長度算整串字元數')`：`iPhone手機` 通過；`iPhone手機手機手機` 超過 8 → `tooLong`。
- `test('detectCharType：拉丁、CJK、混合、純數字')`：`apple`→latin、`蘋果`→cjk、`iPhone手機`→mixed、`123`→latin。
- `test('帶重音的拉丁字母算拉丁')`：`café`。
- `test('擴展 B 區的漢字算 CJK')`：`𠀀` → `cjk`。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/dictionary/lookup_text_normalizer_test.dart`
Expected: FAIL。

- [ ] **Step 3: 實作**

用 `RegExp(..., unicode: true)` 處理 `\p{P}`、`\p{S}`、`\p{L}`。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/dictionary/lookup_text_normalizer.dart app/test/dictionary/lookup_text_normalizer_test.dart
git commit -m "feat(epic-63): Issue 3 選字處理與字元類型判斷"
```

---

### Task 7：詞形還原（`lemmatize/`）

**Files:**
- Create: `app/lib/dictionary/lemmatize/lemmatizer.dart`、`english_lemmatizer.dart`
- Test: `app/test/dictionary/english_lemmatizer_test.dart`、`app/test/dictionary/lemmatizer_registry_test.dart`

**Interfaces:**
- Produces:
  - `typedef Lemmatizer = List<String> Function(String word)`：輸入一個詞，回傳有序的詞元候選（可能為空），不含輸入本身。
  - `List<String> lemmatize(String lang, String word)`：依 `lang` 的主語言碼（`en-US`→`en`）查登錄表；未登錄回傳 `const []`。目前只登錄 `en`。
  - `List<String> lemmatizeEnglish(String word)`

`lemmatizeEnglish` 規則：
- 輸入先轉小寫；不是純 ASCII 字母（`^[a-z]+$`）一律回傳空清單（中文、帶重音、含空白、含連字號都不處理）。
- 不規則表優先（至少涵蓋 `ran→run`、`mice→mouse`、`children→child`、`went→go`、`was/were→be`、`better→good`、`feet→foot`、`men→man`、`women→woman`、`teeth→tooth`）。
- 規則：複數與第三人稱（`-s`、`-es`、`-ies→y`、`-ves→f/fe`）、過去式與過去分詞（`-ed`、`-ied→y`、雙寫子音還原如 `stopped→stop`）、`-ing`（含補回 `e`、雙寫子音還原）、比較級（`-er`、`-est`、`-ier→y`）。
- 名詞優先：`analyses` 先回 `analysis` 再回 `analyse`。
- 寧可多產生：錯的詞幹只會查不到。但不得回傳空字串或與輸入相同的字串，且清單不重複。
- 長度 1 至 2 個字母的詞不套用規則（只查不規則表），避免 `is`→`i`、`as`→`a` 之類的候選。

- [ ] **Step 1: 寫失敗的測試**

`english_lemmatizer_test.dart`：
- `test('不規則：ran→run、mice→mouse、children→child')`：`lemmatizeEnglish('ran')` 的第一個等於 `'run'`。
- `test('規則：複數')`：`cats`→含 `cat`、`boxes`→含 `box`、`flies`→含 `fly`、`wolves`→含 `wolf`。
- `test('規則：過去式')`：`walked`→含 `walk`、`studied`→含 `study`、`stopped`→含 `stop`。
- `test('規則：-ing')`：`running`→含 `run`、`making`→含 `make`、`walking`→含 `walk`。
- `test('規則：比較級')`：`bigger`→含 `big`、`happiest`→含 `happy`。
- `test('analyses 先出 analysis 再出 analyse')`：索引比較。
- `test('大寫輸入先轉小寫')`：`Running` 含 `run`。
- `test('非英文單詞回傳空清單')`：`蘋果`、`café`、`state-of-the-art`、`kick the`。
- `test('1 至 2 個字母的詞不丟例外，也不產生空字串或自身')`（Review Focus 5）：對 `a`、`is`、`as`、`us`、`be`、`bus`、`gas`、`this` 逐一驗證：每個候選非空、不等於輸入、清單無重複。
- `test('回傳清單不含輸入本身且無重複')`：抽查 20 個常見詞。

`lemmatizer_registry_test.dart`：
- `test('未登錄語言回傳空清單，不套用英文規則')`：`lemmatize('zh', 'running')` 為空；`lemmatize('fr', 'running')` 為空。
- `test('en 與 en-US 都走英文')`：`lemmatize('en-US', 'ran')` 含 `run`。
- `test('語言碼不分大小寫')`：`EN`。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/dictionary/english_lemmatizer_test.dart test/dictionary/lemmatizer_registry_test.dart`
Expected: FAIL。

- [ ] **Step 3: 實作 `lemmatizer.dart`（型別與登錄表）與 `english_lemmatizer.dart`**

登錄表為 `const Map<String, Lemmatizer>`，目前只有 `'en'`。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/dictionary/lemmatize app/test/dictionary
git commit -m "feat(epic-63): Issue 3 英文詞形還原與語言登錄表"
```

---

### Task 8：`lookup_candidates`

**Files:**
- Create: `app/lib/dictionary/lookup_candidates.dart`
- Test: `app/test/dictionary/lookup_candidates_test.dart`

**Interfaces:**
- Consumes: Task 7 的 `lemmatize`；Issue 2 的 `headwordNorm`。
- Produces:
  - `List<String> lookupCandidates(String text, {required String lang})`
  - `List<String> dedupeByHeadwordNorm(List<String> candidates)`：依 `headwordNorm()` 去重，保留第一次出現的順序與原樣字串。
  - `String stripLatinDiacritics(String text)`：對照表涵蓋 Latin-1 Supplement（`U+00C0–U+00FF`）與 Latin Extended-A（`U+0100–U+017F`）；`ß→ss`、`æ→ae`、`Æ→AE`、`œ→oe`、`Œ→OE`、`Ł→L`、`ł→l`、`Ø→O`、`ø→o`、`Đ→D`、`đ→d`；不引入新套件，不做 Unicode 正規化。

`lookupCandidates` 的順序（spec §3.4）：原字串、小寫、首字大寫（第一個字元大寫、其餘小寫）、全大寫；再接 `lemmatize(lang, 小寫)` 的結果；最後把前面每個含變音符號的候選去變音符號後附上（`café` 先於 `cafe`）。相同字串只保留第一次出現。輸入去空白後為空 → 回傳空清單。

- [ ] **Step 1: 寫失敗的測試 `lookup_candidates_test.dart`**

- `test('順序：原字串、小寫、首字大寫、全大寫')`：`'aPPle'`（lang `en`）→ 清單開頭依序為 `['aPPle','apple','Apple','APPLE']`。
- `test('首字大寫與原字串相同時去重')`：`'Apple'` → 開頭為 `['Apple','apple','APPLE']`。
- `test('小寫輸入的完整順序')`：`'run'` → `['run','Run','RUN']`（無詞形還原結果）。
- `test('詞形還原接在大小寫變體後面')`：`'ran'`（`en`）→ 清單中 `run` 的索引大於 `RAN` 的索引。
- `test('去變音符號只當備援：café 先於 cafe')`
- `test('去變音符號對照表抽查')`：`naïve→naive`、`Ångström→Angstrom`、`straße→strasse`、`Łódź→Lodz`、`œuvre→oeuvre`。
- `test('中文字典（lang zh）不套用英文詞形還原')`：`lookupCandidates('running', lang: 'zh')` 不含 `run`。
- `test('CJK 文字的大小寫變體全部相同，去重後只剩一個')`：`'蘋果'` → `['蘋果']`。
- `test('空字串與純空白回傳空清單')`
- `test('清單無重複字串')`
- `test('dedupeByHeadwordNorm：套用公式後相同的候選只留第一個')`：`['Run','run','RUN','ran']` → `['Run','ran']`。
- `test('dedupeByHeadwordNorm 保留原樣字串與順序')`

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/dictionary/lookup_candidates_test.dart`
Expected: FAIL。

- [ ] **Step 3: 實作**

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/dictionary/lookup_candidates.dart app/test/dictionary/lookup_candidates_test.dart
git commit -m "feat(epic-63): Issue 3 查詢候選清單與去變音符號"
```

---

### Task 9：`LocalDictionaryProvider` 與 `DictionaryService`

**Files:**
- Create: `app/lib/dictionary/providers/local_dictionary_provider.dart`、`app/lib/dictionary/dictionary_service.dart`
- Test: `app/test/dictionary/local_dictionary_provider_test.dart`、`app/test/dictionary/dictionary_service_test.dart`

**Interfaces:**
- Consumes: Task 6 的 `normalizeLookupSelection`、`SelectionCharType`；Task 8 的 `lookupCandidates`、`dedupeByHeadwordNorm`；Issue 2 的 `DictionaryStore`、`DictionaryProvider`、`LookupRequest`、`LookupResult`、`ProviderOutcome`、`OutcomeStatus`。
- Produces:
  - `class LocalDictionaryProvider implements DictionaryProvider`：建構子 `LocalDictionaryProvider({required DictionaryStore store, required DictionarySource source})`；`id` 為 `source.id`。`lookup`：依 `source.sourceLang` 產生候選 → `dedupeByHeadwordNorm` → 依序 `store.lookup(source.id, 候選)`，第一個有結果就停，回傳 `found`（`entries` 為該候選的全部詞條）；全部沒有結果回傳 `notFound`。`displayName` 為 `source.name`。
  - `sealed class DictionaryLookupResponse`；`final class LookupRejected extends DictionaryLookupResponse { final SelectionProblem problem; }`；`final class LookupCompleted extends DictionaryLookupResponse { final LookupResult result; }`
  - `class DictionaryService { DictionaryService({required DictionaryStore store}); Future<DictionaryLookupResponse> lookup(String selectedText); }`

`DictionaryService.lookup` 行為：
1. `normalizeLookupSelection`；`RejectedSelection` → 回傳 `LookupRejected`，**不查任何字典**。
2. `charType` 決定允許的語言：`latin`→`{en}`、`cjk`→`{zh}`、`mixed`→`{zh, en}`；`store.listSources(enabledOnly: true)` 中 `sourceLang` 主語言碼在允許集合內者（依 priority 排序）各建一個 `LocalDictionaryProvider`。
3. 逐個 provider 查詢；任何 provider 丟例外 → 該分段 `ProviderOutcome(status: failed, errorCode: 'localLookupFailed')`，不影響其他。
4. `LookupRequest` 帶的是處理後的 `text`。
5. 沒有符合的字典 → `LookupCompleted` 且 `outcomes` 為空。

- [ ] **Step 1: 寫失敗的測試**

`local_dictionary_provider_test.dart`（記憶體 `dictionary.db` ＋ 真的 `DictionaryStore`）：
- `test('命中第一個候選就停')`：字典同時有 `ran` 與 `run`，查 `ran` → `entries.single.headword == 'ran'`；以計數用的 `DictionaryStore` 子類別（覆寫 `lookup`）驗證 `store.lookup` 只被呼叫 1 次，不會再去查 `run`。
- `test('ran 能查到只存 run 的字典')`（驗收 13）：`found`，`entries.single.headword == 'run'`。
- `test('候選依序嘗試，後面的候選才命中')`：字典只有 `cafe`，查 `café` → `found`。
- `test('全部沒有結果回傳 notFound，entries 為空')`
- `test('候選依 headword_norm 去重後才查詢')`：查 `Run` 時 `store.lookup` 只被呼叫一次（不是 `Run`／`run`／`RUN` 三次）。
- `test('中文字典不套用英文詞形還原')`（驗收 14）：`sourceLang: 'zh'` 的字典有 `run`，查 `ran` → `notFound`；`sourceLang: 'en'` 同樣資料 → `found`。
- `test('同一詞頭多筆全部回傳')`：`IT`、`it`。
- `test('id 與 displayName 取自來源')`

`dictionary_service_test.dart`：
- `test('無效選取回傳 LookupRejected，且不查任何字典')`：`天地，玄黃` → `invalidSelection`；9 個 CJK 字 → `tooLong`；用會計數的 `store` 驗證 `lookup` 呼叫 0 次。
- `test('「相濡以沫」去標點後查詢')`（驗收 12）：字典有 `相濡以沫`（`sourceLang: 'zh'`）→ `found`。
- `test('方向挑選：拉丁只查 en 字典')`：同時有 `en` 與 `zh` 字典，查 `apple` → `outcomes` 只有 `en` 那本。
- `test('方向挑選：CJK 只查 zh 字典')`
- `test('方向挑選：混合文字兩種字典都查')`
- `test('語言碼只看第一段：zh-Hant、en-US')`
- `test('停用的字典不查；outcomes 依 priority 排序')`
- `test('沒有符合方向的字典：LookupCompleted 且 outcomes 為空')`
- `test('一本字典丟例外：該分段 failed，其他分段照常')`：用會對指定來源丟例外的 `store` 包裝。
- `test('跨行片語整理後整串查詢')`：`"kick  the\nbucket"` → 以 `kick the bucket` 查到詞頭。
- `test('LookupRequest 帶處理後的文字')`：`「apple」` → `result.request.word == 'apple'`。
- `test('本機查詢 p95 小於 300 ms（含候選鏈）')`（驗收 23）：10 萬筆詞條的字典，隨機查 200 次含詞形還原的詞，第 190 名（p95）耗時小於 300 ms。註解說明這是開發機基準，真機量測屬 Issue 8。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/dictionary/local_dictionary_provider_test.dart test/dictionary/dictionary_service_test.dart`
Expected: FAIL。

- [ ] **Step 3: 實作 `LocalDictionaryProvider` 與 `DictionaryService`**

語言碼比對用一個私有的 `_primaryLang(String)`（轉小寫、取 `-` 前段）。`DictionaryService` 不快取來源清單（每次查詢都讀，設定畫面改動即時生效）。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/dictionary app/test/dictionary
git commit -m "feat(epic-63): Issue 3 本機字典查詢與 DictionaryService"
```

---

### Task 10：整體驗證與進度更新

**Files:**
- Modify: `docs/epics/epic-63-dictionary-lookup/issues.md`（Issue 3 的 `Status`）
- Modify: `docs/epics/epic-63-dictionary-lookup/plans/plan-issue-3.md`（勾選步驟）

- [ ] **Step 1: 執行本 Issue 全部測試**

Run（在 `app/`）: `flutter test test/dictionary/`
Expected: 全數 PASS。

- [ ] **Step 2: 靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 兩支檢查腳本**

Run: `node tool/check_l10n_hardcoded_strings.js` 與 `node tool/check_integration_keys.js`
Expected: 兩支都 PASS（本 Issue 沒有 UI）。

- [ ] **Step 4: 確認沒有碰到禁區**

Run（專案根目錄）: `git diff main --stat -- app/lib/library app/lib/sync app/pubspec.yaml app/pubspec.lock`
Expected: 無輸出。

- [ ] **Step 5: 完整 `flutter test`（整張計畫最後一個 Task）**

Run: `flutter test`
Expected: 全數 PASS。把通過時間與 commit 記進 PR 說明。

- [ ] **Step 6: 更新 `issues.md` 的 Issue 3 狀態，勾選本計畫所有步驟，Commit**

```bash
git add docs/epics/epic-63-dictionary-lookup
git commit -m "docs(epic-63): Issue 3 實作完成，更新狀態"
```

---

## 交給後續 Issue

- **Issue 4：** 面板用 `LookupRejected.problem` 顯示「選取內容含有標點」「選取範圍太長」；`outcomes` 為空時顯示「尚未匯入字典」；拼音顯示呼叫 `pinyinToneMarks()`；`DictionaryService` 的建構與注入（`main.dart`、`ReaderFeatureDependencies`）。
- **Issue 5：** 匯入畫面呼叫 `readHints()` 預填；`DuplicateDictionaryException` 轉成「這本字典已匯入」並提供略過／取代（取代傳 `replaceExisting: true`）；`DictionaryImportException.code` 與 `ImportSummary.skipSamples` 轉成三段式 l10n 訊息；匯入進行中暫停查詢入口（Issue 2 審查 M-9）；`listSources()` 遇到未知 `format` 字串的處理（M-2）。
- **Issue 6a：** `DictionaryFormat.mdx` 的匯入與 `content_id` 的 `content://` 路徑支援。

---

## 自我檢查

- **Spec 覆蓋：** 驗收 1（JSON/CSV 匯入，Task 3）、2（語言方向，Task 9）、12（選字處理，Task 6、9）、13（候選鏈，Task 8、9）、14（只登錄英文，Task 7、9）、20（重複匯入偵測，Task 2、3）、23（p95，Task 9）、24（10 萬筆有進度可取消，Task 3）、33（CEDICT 繁簡同內容與授權，Task 4）、37（拼音，Task 5，空白保留待確認）。§7 的單元測試檔：`lookup_text_normalizer`、`lookup_candidates`、`english_lemmatizer`、`lemmatizer_registry`、`content_id`、`json_csv_importer`、`dictionary_store`（Issue 2 已有，本 Issue 補 content_id）、`cedict_importer`、`pinyin_tone_marks`、`local_dictionary_provider`、`dictionary_service` 全數有對應 Task。
- **Issue 2 延後項：** M-7（每批 2,000 筆，Task 3）、M-8（空詞頭略過，Task 3 `missingHeadword`）、M-9（交給 Issue 5）。
- **型別一致：** `ImportRequest`／`ImportProgress`／`ImportSummary`／`ImportSkip`／`ImportHints` 只在 Task 1 定義；`ParseInput`／`ParsedDictionary`／`runImportPipeline` 只在 Task 3 定義，Task 4 沿用；`SelectionCharType`、`normalizeLookupSelection` 在 Task 6 定義，Task 9 使用；`lemmatize`（Task 7）→ `lookupCandidates`（Task 8）→ `LocalDictionaryProvider`（Task 9）。
- **比例：** 計畫只寫簽章、規則、測試名稱與斷言，不寫函式本體。
