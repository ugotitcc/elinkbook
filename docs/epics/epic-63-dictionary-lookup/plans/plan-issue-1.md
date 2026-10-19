# Issue 1：MDX 解析器技術驗證 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 驗證 `dict_reader` 在真實檔、合成檔與實機上的行為並量出數字，決定能否採用；`mdict_flutter` 已在真實檔上淘汰（見下方），只留可重現的證據。

**Architecture:** 驗證程式全放在 `.scratch/mdx_spike/`（已被 `.gitignore` 排除，不進版控）。一個 Python 產生器造測試檔；一個純 Dart 套件放 `dict_reader` 轉接層與正確性測試；一個最小 Flutter 應用在實機量測效能並驗證 WebView 行為。最後只有文件變更進版控。

**Tech Stack:** Dart／Flutter（`app/pubspec.yaml` 的 `sdk: ^3.11.5`）、`dict_reader 1.6.1`（MIT）、`mdict_flutter 0.1.1`（BSD-3-Clause，僅作淘汰證據）、`flutter_inappwebview ^6.1.5`、Python 3（僅造測試檔）。

**Spec:** `docs/epics/epic-63-dictionary-lookup/spec.md`（§3.6 MDX 處理表、§9 驗收 34、35、36、39）、`issues.md` 的 Issue 1、`docs/research/dictionary/DICTIONARY_FORMATS_AND_LICENSES.md` §4。審查報告：`reviews/review-plan-issue-1.md`。

## 已知事實（2026-10-19 實測，計畫據此簡化）

兩個真實檔案（`Encrypted=2`）的開啟結果，審查者與計畫作者各自獨立跑過，結果一致：

| | 教育部 MDX（20 MB、UTF-16、有 `StyleSheet`） | 古漢語 MDX（464 KB、UTF-8、`StripKey=Yes`） |
|---|---|---|
| `dict_reader 1.6.1` | 開啟成功，`locate('一')` 命中，樣式表已展開（無 `` `數字` `` 殘留） | 開啟成功，`locate('一')` 命中 |
| `mdict_flutter 0.1.1` | `open()` 丟 `FormatException: Filter error, bad data` | 同左 |

- 依決策規則 1，`mdict_flutter` 已淘汰。本 Issue 不再為它寫轉接層、差異測試與效能量測，只保留一個重現證據的測試（Task 3）。
- `mdict_flutter` 另有一項設計缺陷（讀原始碼確認）：記錄區塊壓縮型態不是 zlib 時 `return null`，與「查無此詞」無法區分。寫進文件，不測。
- `dict_reader` 遇到不支援的壓縮型態時，丟的是**字串**（`throw "Compression method not supported"`），不是 `Exception`。
- `dict_reader` 會把所有鍵載入記憶體。這是它最可能在記憶體門檻失敗之處，Task 4 要量。

## Global Constraints

- 不得引入 `readest/js-mdict` v7 以後的任何程式碼，也不得閱讀其實作來照寫（AGPL-3.0；2026-10-19 決定）。
- **不修改 `app/pubspec.yaml`。** 候選套件只加在 `.scratch/` 的專案裡。選定後加入 `app/` 屬於 Issue 6a。
- `tmp/dictionary/` 的三個檔案是第三方打包檔，授權不明：不進版控、不複製到 `.scratch/` 以外、文件只寫格式資訊，不貼內容。
- 測試用 fixtures 一律自製。
- 效能目標（`DICTIONARY_FORMATS_AND_LICENSES.md` §8，待實測）：本機精確查詢 p95 小於 300 ms；開啟 100 MB MDX 的記憶體增量小於 50 MB。
- Android `minSdk = 24`。
- 所有文件用正體中文；commit 訊息不加 `Co-Authored-By`。
- 兩個真實檔案：`教育部重編國語辭典(第五版).mdx`（163,085 筆）、`簡明古漢語常用字字典（川大版2003）正體.mdx`（7,587 筆，引用不存在的 `ghychyz.css`）。兩者都只有 zlib。

## Review Focus

1. **LZO 區塊**：`dict_reader` 丟的是字串。預期：轉接層一律包成 `MdxSpikeError(unsupportedCompression)`，呼叫端不會因 `catch (e is Exception)` 漏接而當掉。
2. **截斷或損壞的檔案**：預期 10 秒內丟出明確錯誤，不無限迴圈、不吃光記憶體。
3. **UTF-16 與 CJK 鍵**：教育部 MDX 是 UTF-16。預期：用 CJK 單字查得到、前綴查詢回傳合理結果。
4. **空字串、純空白、不存在的鍵**：預期回傳「查無」，不丟例外、不回傳整本字典。
5. **含全形括號與 CJK 的檔名**：預期 Android 上複製到 App 私有目錄後仍能開啟。

---

## 檔案結構

```text
.scratch/mdx_spike/                        # 不進版控
├── pubspec.yaml                           # 純 Dart 套件
├── tools/
│   ├── make_test_mdx.py                   # 測試檔產生器
│   └── test_make_test_mdx.py              # 產生器自身的單元測試
├── lib/
│   └── dict_reader_adapter.dart           # MdxSpikeError 與 DictReaderAdapter
├── test/
│   ├── synthetic_fixtures_test.dart       # 合成檔：自製、可重現
│   ├── real_files_test.dart               # 真實檔：靠環境變數啟用
│   └── mdict_flutter_elimination_test.dart  # 淘汰證據：只記錄，不作為通過條件
├── app/                                   # 最小 Flutter 應用（實機）
│   └── lib/{main.dart, bench.dart, webview_probe.dart}
└── report/                                # 量測結果 JSON（人類貼進文件）
docs/research/dictionary/DICTIONARY_FORMATS_AND_LICENSES.md   # 改：新增「驗證結果」一節
docs/epics/epic-63-dictionary-lookup/issues.md                # 改：Issue 1 狀態與 6a 的套件名稱
docs/epics/epic-63-dictionary-lookup/epic.md                  # 改：MDX 解析器結論
```

---

### Task 1: 測試檔產生器

**Files:**
- Create: `.scratch/mdx_spike/tools/make_test_mdx.py`
- Test: `.scratch/mdx_spike/tools/test_make_test_mdx.py`

**Interfaces:**
- Produces: 命令列 `python3 -X utf8 make_test_mdx.py <kind> <out_path> [--entries N] [--body-bytes N]`，`kind` 為下列之一：
  - `zlib`：UTF-8、v2.0、`Encrypted=0`、zlib 的 MDX，預設 50 筆，鍵含 `apple`、`Apple`、`café`、`相濡以沫`。
  - `fake-lzo`：同上，但記錄區塊的壓縮型態標成 1（LZO），內容為任意位元組。
  - `truncated`：`zlib` 檔案砍掉後半。
  - `mdd`：UTF-16LE 的 MDD，鍵為 `\pic\a b.png`、`\css\x.css`，記錄為二進位。
  - `large`：`zlib` 型態，預設 `--entries 400000 --body-bytes 330`，鍵為遞增的合成詞。**詞條內文必須是低壓縮率的內容**：用固定種子 `random.Random(0)` 產生的隨機位元組做 base64（zlib 壓縮率約 75%）。重複性高的內文會壓成 10 MB 以下，使效能量測失去代表性。
- Produces: Python 函式 `build_mdx(entries: list[tuple[str,str]], *, encoding: str, record_compression: int) -> bytes` 與 `build_mdd(entries: list[tuple[str,bytes]]) -> bytes`。

**檔案格式（產生器必須遵守，v2.0）：**
- 檔頭：4 位元組大端長度 + UTF-16LE 的 XML 標頭 + 4 位元組小端 Adler-32。**XML 標頭字串結尾要有 `\x00\x00`（UTF-16 空字元）；前 4 位元組的長度與 Adler-32 都計入這兩個位元組。** 兩個真實檔都是這樣（已核對）。標頭屬性：`GeneratedByEngineVersion="2.0"`、`Encrypted="0"`、`Encoding`、`Format="Html"`、`KeyCaseSensitive="No"`、`StripKey="No"`、`Title`。
- 關鍵字區段標頭：5 個 8 位元組大端整數（區塊數、詞條數、索引區解壓大小、索引區壓縮大小、關鍵字區塊總大小） + 4 位元組大端 Adler-32。
- 每個壓縮區塊 = 4 位元組小端「壓縮型態」（0 無、1 LZO、2 zlib） + 4 位元組大端 Adler-32（解壓後資料） + 資料。關鍵字索引區與關鍵字區塊一律 zlib。
- 關鍵字區塊內每筆：8 位元組大端記錄偏移 + 鍵文字 + 結尾空字元（UTF-16 為兩個）。鍵依小寫排序。
- 關鍵字索引每區塊一筆：詞條數(8) + 首鍵長度(2)與首鍵(含一個字元的結尾) + 末鍵長度(2)與末鍵 + 壓縮大小(8) + 解壓大小(8)。
- 記錄區段標頭：4 個 8 位元組大端整數（記錄區塊數、詞條數、記錄區塊資訊大小、記錄區塊總大小）；接著每區塊一組 (壓縮大小, 解壓大小)（各 8 位元組大端）；再接區塊本體。
- MDX 記錄 = 內文 + 結尾空字元；偏移為記錄在「全部解壓記錄串接」中的位置。MDD 記錄不加空字元。每個記錄區塊解壓後最大 64 KB。

- [x] **Step 1: 寫失敗的測試**

`test_make_test_mdx.py`（`unittest`）：
- `test_zlib_header_fields`：`build_mdx([("apple","蘋果")], encoding="UTF-8", record_compression=2)` 的前 4 位元組大端長度等於 UTF-16LE 標頭（含結尾 `\x00\x00`）的位元組數；標頭字串含 `GeneratedByEngineVersion="2.0"` 與 `Encoding="UTF-8"`；標頭最後兩個位元組為 `\x00\x00`。
- `test_fake_lzo_marks_record_block_type_1`：輸出的第一個記錄區塊前 4 位元組小端值為 `1`，關鍵字索引區與關鍵字區塊型態為 `2`。
- `test_truncated_is_shorter_than_half_of_full`：`truncated` 的大小小於 `zlib` 同內容檔的 60%。
- `test_keys_sorted_case_insensitive`：`apple`、`Apple`、`banana` 產生的鍵順序為 `apple`、`Apple`、`banana`（穩定排序）。
- `test_large_body_is_not_highly_compressible`：以 2,000 筆、330 位元組內文產生，檔案大小不小於原始內文總和的 60%。

- [x] **Step 2: 執行測試確認失敗**

Run: `python3 -X utf8 -m unittest .scratch/mdx_spike/tools/test_make_test_mdx.py -v`
Expected: FAIL（`ModuleNotFoundError` 或 `make_test_mdx` 未定義）。

- [x] **Step 3: 實作 `build_mdx`、`build_mdd` 與命令列**

在 `make_test_mdx.py`。用標準庫 `zlib`、`struct`、`base64`、`random`、`argparse`。格式照上方清單。`fake-lzo` 的記錄資料用固定的 64 位元組任意內容。

- [x] **Step 4: 執行測試確認通過**

Run: `python3 -X utf8 -m unittest .scratch/mdx_spike/tools/test_make_test_mdx.py -v`
Expected: 5 個測試 PASS。

- [x] **Step 5: 產生所有測試檔**

Run（逐一）：`python3 -X utf8 .scratch/mdx_spike/tools/make_test_mdx.py <kind> .scratch/mdx_spike/fixtures/<kind>.<mdx|mdd>`，`kind` 為 `zlib`、`fake-lzo`、`truncated`、`mdd`、`large`。
Expected: `fixtures/large.mdx` 大小介於 90 與 130 MB；若不在範圍，調整 `--body-bytes`（內文隨機位元組須維持低壓縮率），不要放寬範圍。（`fixtures/` 在 `.scratch/` 下，不進版控。）

---

### Task 2: `dict_reader` 轉接層與合成檔正確性測試

**Files:**
- Create: `.scratch/mdx_spike/pubspec.yaml`、`lib/dict_reader_adapter.dart`
- Test: `.scratch/mdx_spike/test/synthetic_fixtures_test.dart`

**Interfaces:**
- Consumes: Task 1 產生的 `fixtures/*.mdx`、`fixtures/mdd.mdd`。
- Produces（Task 3、4、5 都依賴）：

```dart
class MdxSpikeError implements Exception {
  final String kind; // 'unsupportedCompression' | 'corrupt' | 'notFound' | 'other'
  final String message;
}

class DictReaderAdapter {
  Future<void> open(String path);                    // 失敗一律丟 MdxSpikeError
  Future<int> get entryCount;
  Future<String?> lookup(String key);                // 查無回傳 null
  Future<List<String>> prefix(String prefix, {int limit = 50});
  Future<List<int>?> resource(String key);           // 只對 .mdd 有意義，查無回傳 null
  Map<String, String> get header;
  Future<void> close();
}
```

- [x] **Step 1: 建立專案並確認相依解析**

`pubspec.yaml`：`environment: sdk: ^3.11.5`，依賴 `dict_reader: 1.6.1`，dev 依賴 `test: ^1.25.8`、`mdict_flutter: 0.1.1`（僅供 Task 3 的淘汰證據）。
Run: `cd .scratch/mdx_spike && dart pub get`
Expected: 成功，無版本衝突。（`flutter pub add dict_reader --dry-run` 在 `app/` 已於 2026-10-19 確認可解析：新增 `blockchain_utils`、`charset`、`convert`、`html_unescape`、`pointycastle` 與 `dict_reader` 本身，皆為新增，無升降級。）

- [x] **Step 2: 寫失敗的測試 `synthetic_fixtures_test.dart`**

**每個測試自己開啟對應的 fixture，並在 `tearDown` 呼叫 `close()`；不要在 `setUp` 共用一個預設檔案**（MDX 測試與 MDD 測試的檔案型態不同）。

- `opens zlib fixture and reports 50 entries`：`entryCount == 50`。
- `lookup hit returns definition containing 蘋果`：`lookup('apple')` 含 `蘋果`。
- `lookup is case insensitive when KeyCaseSensitive=No`：`lookup('APPLE')` 不為 null。
- `lookup miss returns null`：`lookup('zzzz-not-here') == null`。
- `empty and whitespace keys return null or empty, never throw`：`lookup('')`、`lookup('   ')` 不丟例外（Review Focus 4）。
- `prefix search returns matches within limit`：`prefix('app')` 含 `apple`，長度不超過 `limit`。
- `cjk key lookup`：`lookup('相濡以沫')` 不為 null（Review Focus 3）。
- `fake lzo throws MdxSpikeError(unsupportedCompression)`：開啟 `fake-lzo.mdx`，呼叫 `lookup('apple')`（若 `open` 已丟錯則在 `open` 斷言），斷言 `kind == 'unsupportedCompression'`（Review Focus 1）。
- `truncated file throws MdxSpikeError(corrupt) within 10 seconds`：用 `.timeout(Duration(seconds: 10))`（Review Focus 2）。
- `missing file throws MdxSpikeError(notFound)`。
- `mdd resource lookup`：開啟 `mdd.mdd`，分別以 `\pic\a b.png`、`/pic/a b.png`、`pic/a b.png` 呼叫 `resource`，**三種結果寫入** `report/mdd_key_forms.json`（資訊用，不作為通過條件），並斷言至少一種非 null。

- [x] **Step 3: 執行測試確認失敗**

Run: `cd .scratch/mdx_spike && dart test test/synthetic_fixtures_test.dart`
Expected: FAIL（`dict_reader_adapter.dart` 不存在）。

- [x] **Step 4: 實作 `DictReaderAdapter`**

`open` 呼叫 `DictReader(path).initDict()`；`lookup` 用 `locate(key)` 再 `readOneMdx`；`prefix` 用 `search(prefix, limit: limit)`；`resource` 用 `locate` 再 `readOneMdd`；`header` 取其 `header`。所有 `catch (e)` 轉成 `MdxSpikeError`：`e is String && e.contains('Compression')` → `unsupportedCompression`；`FormatException`／`StateError`／`RangeError` → `corrupt`；檔案不存在的 `FileSystemException` → `notFound`；其餘 → `other`。這一層只做 API 對應與錯誤分類，不補功能；它同時是之後 `MdxReader` 錯誤包裝的原型。

- [x] **Step 5: 執行測試，記錄結果**

Run: `cd .scratch/mdx_spike && dart test test/synthetic_fixtures_test.dart --reporter expanded`
Expected: 全數 PASS。若有失敗，**不要修轉接層去掩蓋**：把測試名稱與錯誤貼進 `report/synthetic_failures.md`，並在 Task 5 判斷是否影響採用。

---

### Task 3: 真實檔案測試與淘汰證據

**Files:**
- Test: `.scratch/mdx_spike/test/real_files_test.dart`、`.scratch/mdx_spike/test/mdict_flutter_elimination_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `DictReaderAdapter`；環境變數 `MDX_SPIKE_DIR`（指向 `tmp/dictionary/`），未設定時兩個測試檔都 `skip`。

- [x] **Step 1: 寫 `real_files_test.dart`**

對兩個真實檔案各跑（`dict_reader` 唯一候選）：
- `opens real file (Encrypted=2) and entryCount matches header`：教育部 `entryCount == 163085`；古漢語 `== 7587`。
- `cjk single character lookup hits`：兩個檔案 `lookup('一')` 不為 null。
- `sampled keys all resolve`：取 `prefix('', limit: 200)`，每個鍵 `lookup` 不為 null 且內容非空。
- `stylesheet expanded (教育部)`：200 筆取樣的 `lookup` 結果都不含正規表示式 `` `\d+` ``（spec §9 驗收 35）。
- `stripkey behavior recorded (古漢語)`：`lookup('一')`、`lookup(' 一 ')`、`lookup('一，')` 是否命中，寫入 `report/stripkey.json`（資訊用）。
- `title placeholder detected (古漢語)`：`header['Title']` 等於 `Title (No HTML code allowed)`，`header['Description']` 非空。
- `unresolved css link is present (古漢語)`：`lookup('一')` 的內容含 `ghychyz.css`（確認 Issue 6a 需處理缺檔 CSS）。

- [x] **Step 2: 寫 `mdict_flutter_elimination_test.dart`**

兩個真實檔各一個測試：用 `MdictReader(path).open()`，**不作為通過條件**：測試永遠通過，把結果（成功或例外型別與訊息）寫進 `report/mdict_flutter_elimination.json`。目的是留下可重現的淘汰證據。預期結果：兩者皆 `FormatException: Filter error, bad data`。

- [x] **Step 3: 執行**

Run（PowerShell）：`$env:MDX_SPIKE_DIR='U:\MyDeveloper\AI\elinkBook\tmp\dictionary'; cd .scratch\mdx_spike; dart test test/real_files_test.dart test/mdict_flutter_elimination_test.dart --reporter expanded`
Expected: `real_files_test.dart` 全數 PASS。**`dict_reader` 在任一真實檔開啟失敗，是整個 Issue 的必過項目失敗**：貼進 `report/real_failures.md`，直接跳到 Task 5 的規則 4。

---

### Task 4: 實機量測與 WebView 行為（人類在實機執行）

**Files:**
- Create: `.scratch/mdx_spike/app/`（`flutter create` 的最小專案，Android only）、`lib/bench.dart`、`lib/webview_probe.dart`

**Interfaces:**
- Consumes: Task 2 的 `DictReaderAdapter`（以 `path:` 相依引用 `.scratch/mdx_spike`）、Task 1 的 `fixtures/large.mdx` 與 `mdd.mdd`。

- [x] **Step 1: 實作 `bench.dart`**

函式 `Future<Map<String, Object>> runBench(String path)`，回傳 JSON：`openMs`、`rssBeforeMb`、`rssAfterOpenMb`、`rssAfterLookupsMb`（用 `ProcessInfo.currentRss`）、`lookupP50Ms`、`lookupP95Ms`（100 次，鍵隨機取自 `prefix('', limit: 1000)`）、`firstLookupMs`。結果寫到 App 外部檔案目錄的 `bench_<file>.json`。**每次只量一個檔案，量完結束行程**（UI 只提供「量測教育部」「量測 large」兩個按鈕，每次量測前以 `adb shell am force-stop <applicationId>` 重新啟動 App），避免前一次的記憶體基準汙染增量。

- [x] **Step 2: 實作 `webview_probe.dart`（`javaScriptEnabled: false`）**

一個畫面載入下列 HTML，用 `loadDataWithBaseURL`，`baseUrl = https://dict.local/`，`useShouldInterceptRequest: true`：
- 頁首一個連結 `<a href="#target">`，頁尾 `<h2 id="target">`，中間夠長（超過 3 個螢幕高度）。
- 一個連結 `<a href="entry://apple">`。
- 三張圖：`<img src="pic/a b.png">`、`<img src="pic/a%20b.png">`、`<img src="\pic\a b.png">`。

畫面上記錄並顯示三件事，同時寫進 `webview_probe.json`：
1. `shouldOverrideUrlLoading` 收到的所有網址（原樣字串）。
2. `shouldInterceptRequest` 收到的所有網址（原樣字串），並一律回傳 200 與一個 1×1 PNG。
3. 點擊 `#target` 連結後的 `controller.getScrollY()`：**點擊後每 50 ms 輪詢一次，直到連續兩次相同或累計 1 秒，取最後一次的值**（Android WebView 的錨點捲動是非同步的，立刻讀會得到假的 0）。同時記錄輪詢過程的所有取樣值。

- [x] **Step 3: 在實機執行並收集結果**

Run（人類）：把 `tmp/dictionary/教育部重編國語辭典(第五版).mdx` 與 `fixtures/large.mdx` 推到裝置：`adb push ... /sdcard/Android/data/<applicationId>/files/`。接著 `flutter run -d <device-id> --release`，依畫面按鈕執行 bench 與 probe。
裝置：**至少一台實機；有 E-Ink 閱讀器就必須在上面量**（`issues.md` Issue 1 的驗收要求 E-Ink）。若只有一般手機，仍照做，並在 Task 5 的文件中明確寫「E-Ink 未驗證」，該項留為 Issue 6a 開工前的待辦，不阻擋本 Issue 完成。有多台時，一般手機作為對照組。
Expected: 每台各產生 `bench_*.json` 與 `webview_probe.json`，`adb pull` 回 `.scratch/mdx_spike/report/<device>/`。

- [x] **Step 4: 判讀 WebView 結果**

人類依 `webview_probe.json` 填入：
- 輪詢後的 `getScrollY() > 0`：`javaScriptEnabled:false` 下錨點可原生跳轉（成立 → `spec.md` §3.6 的「Dart 端改寫 `entry://#x` 為 `#x`」做法可行）；不成立 → 記錄，並在決策文件提出替代案。
- `#target` 點擊是否出現在 `shouldOverrideUrlLoading` 的網址清單。
- 三張圖在 `shouldInterceptRequest` 看到的網址形式（是否已 URL 編碼、反斜線是否保留、是否帶 baseUrl）。

---

### Task 5: 決策、文件與提交

**Files:**
- Modify: `docs/research/dictionary/DICTIONARY_FORMATS_AND_LICENSES.md`（新增「驗證結果」一節，位置在「驗證清單」之後）
- Modify: `docs/epics/epic-63-dictionary-lookup/issues.md`（Issue 1 狀態；Issue 6a 的套件名稱）
- Modify: `docs/epics/epic-63-dictionary-lookup/epic.md`（Discovery 決策表的「MDX 解析器」列）

**決策規則（先定好，再看數字）：**

| 順序 | 條件 | 結果 |
|---|---|---|
| 1 | `mdict_flutter` 在兩個真實檔案開啟失敗（2026-10-19 已確認） | 淘汰，不再評估 |
| 2 | `dict_reader` 在任一真實檔案開啟失敗，或遞移相依有 GPL／AGPL／LGPL | 淘汰，跳到規則 4 |
| 3 | `dict_reader` 通過規則 2，且 `large.mdx` 的記憶體增量 < 50 MB、p95 < 300 ms（所有量到的實機） | **採用 `dict_reader`** |
| 4 | `dict_reader` 被淘汰，或規則 3 的門檻不過 | 不直接採用。備案：(a) 在 MIT 授權下修補（vendor）`dict_reader`，改成依區塊延遲載入鍵（記憶體不過時優先）；(b) 把 MIT 的 `js-mdict` v6.0.7 移植成 Dart。開新 Issue，Issue 6a 狀態改 `needs-info` |

- [x] **Step 1: 授權確認**

讀 `dict_reader` 的 `LICENSE`，以及 `dart pub deps --style=list` 列出的遞移相依的授權（至少 `blockchain_utils`、`pointycastle`、`charset`、`convert`、`html_unescape`）。結果寫成表，欄位為套件、版本、授權、是否需要放進 `app/assets/licenses/`。任何 GPL／AGPL／LGPL 的遞移相依 → 觸發規則 2。

- [x] **Step 2: 寫「驗證結果」一節**

內容：
- 決策規則表與最終結論。
- `mdict_flutter` 淘汰證據：兩個真實檔的錯誤訊息（引用 `report/mdict_flutter_elimination.json`）、讀原始碼確認的靜默 `null` 缺陷。
- `dict_reader` × 兩個真實檔案的結果表（開啟、筆數、`Encrypted=2`、樣式表展開、取樣查詢）。
- 效能表：每台裝置 × 檔案的 `openMs`、RSS 增量、p50、p95。
- 合成檔測試的失敗清單（若有）。
- WebView 結果：錨點、`shouldOverrideUrlLoading`／`shouldInterceptRequest` 看到的網址形式、對 `spec.md` §3.6 的影響。
- `MdxReader` 薄封裝必須補的功能清單，例如：`StripKey` 與 `KeyCaseSensitive` 查詢規則（`dict_reader` 未處理）、標題佔位字串處理、把字串例外包成統一錯誤、缺檔 CSS 的處理。
- 驗證清單第 1 至 11 項逐項打勾或註明未完成原因（未驗證項目：Big5 編碼、v3、真實 `.mdd`、E-Ink 若無裝置）。

- [x] **Step 3: 更新 Issue 狀態與引用**

`issues.md`：Issue 1 的 `Status` 改為 `done`；Issue 6a 的「What to build」把「`mdx_reader.dart` 薄封裝（隔離所選套件）」補上套件名稱與版本；若走規則 4，6a 的狀態改為 `needs-info`。`epic.md`：「MDX 解析器」列填入結論。

- [x] **Step 4: 提交文件**

```bash
git status --short    # 確認只有 docs/ 下的三個檔案；.scratch/ 與 tmp/ 不在清單
git add docs/research/dictionary/DICTIONARY_FORMATS_AND_LICENSES.md docs/epics/epic-63-dictionary-lookup/issues.md docs/epics/epic-63-dictionary-lookup/epic.md
git commit -m "docs(epic-63): Issue 1 MDX 解析器驗證結果與選型"
```

Expected: commit 只含文件。`flutter analyze` 與 `flutter test` 不需執行（`app/` 沒有任何變更）。

---

## 自我檢查紀錄

- **Spec 覆蓋**：Issue 1 驗收「驗證清單都有數字或結論」→ Task 3、4、5；「授權全文與相依套件授權已讀過」→ Task 5 Step 1；「E-Ink 裝置量測」→ Task 4 Step 3（無裝置時明確標示未驗證）；追加驗證（錨點、MDD 路徑）→ Task 2、4；`Encrypted=2`、`StyleSheet`、`StripKey`、標題佔位 → Task 3；LZO 錯誤路徑 → Task 2。
- **審查回應**：I-1 → Task 1（低壓縮內文與壓縮率測試）；I-2、I-3 → 以實測確認 `mdict_flutter` 已淘汰，移除其轉接層與差異測試，改為證據測試；I-4 → Task 4 Step 2 輪詢；M-1 → Task 4 Step 3；M-2 → Task 4 Step 1；M-3 → Task 2 Step 2；M-4 → Task 1 格式說明與測試。
- **未涵蓋**：Big5 編碼的 MDX、v3 格式、真實 `.mdd`（只有合成 MDD），文件中列為「未驗證」。
- **類型一致**：`MdxSpikeError.kind` 的值（`unsupportedCompression`、`corrupt`、`notFound`、`other`）與 `DictReaderAdapter` 方法簽名在 Task 2、3、4 使用一致。
- **比例**：計畫以介面、測試名稱與決策規則為主。

## 執行偏差（2026-10-19，勾選框依此完成）

- Task 2 Step 5、Task 3：`KeyCaseSensitive=No` 的大小寫測試與後來新增的兩個「`open()` 單獨呼叫能否擋下假 LZO／截斷檔」測試會失敗，已用 `wrapper-gap` 標籤保留並記錄，完成判定用 `--exclude-tags wrapper-gap`。
- Task 3 的真實檔測試是在記錄第三方套件的行為，沒有「缺程式碼」的失敗階段；改用錯誤的 `MDX_SPIKE_DIR` 確認測試會因 `notFound` 失敗。
- Task 4：`runBench` 放在 `.scratch/mdx_spike/lib/bench.dart`（CLI 與 App 共用）；實機為一般 Android 平板，沒有 E-Ink 裝置；`adb push` 無法推入含 CJK 的檔名，改由 App 複製成 CJK 檔名；探針 App 補了 `INTERNET` 權限。
- Task 4 Step 2：錨點的 `scrollY` 輪詢掛在 `onUpdateVisitedHistory`，實測純 `#錨點` 導航不會觸發，所以沒有數值，以截圖為證（`report/oppo_opd2102/anchor_before.png`、`anchor_after.png`）。補一個手動取樣按鈕留待下次有裝置時做。
- Task 5：同時修改了 `spec.md` §3.6（圖片鍵轉換與錨點說明），因為實測推翻了原規則。
- 最後審查與程式審查後新增的測試與修正，見 `reviews/review-code-issue-1.md` 與 `.scratch/mdx_spike/report/ledger_plan_issue_1.md`。
