# Issue 6a：MDX 匯入、詞條顯示、交叉參照與錨點、返回堆疊 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 使用者能匯入 `.mdx`（可附 `.mdd`、`.css`），選字查詢時 MDX 詞條在查詢面板用 `InAppWebView` 顯示（JavaScript 關閉、擋所有網路與檔案請求），交叉參照可點、可返回，錨點可跳轉，圖片從 `.mdd` 顯示，深色與 E-Ink 下可讀。

**Architecture:** 套件 `dict_reader 1.6.1` 藏在 `MdxReader` 薄封裝後面（補它缺的規則與統一錯誤型別）。MDX 不轉入 SQLite：匯入時整檔檢查、搬進私有目錄、建一列 `format = mdx` 的來源；查詢時 `MdxDictionaryProvider` 回傳 `bodyKind = html` 的詞條。HTML 前處理、資源網址轉換、連結分類都是純函式（可單元測試）；`MdxEntryView` 只負責把它們接到 `InAppWebView`。查詢面板一次只放一個 WebView，並擁有返回堆疊。

**Tech Stack:** Flutter、`dict_reader 1.6.1`（MIT，新增）、既有 `flutter_inappwebview`、`gen-l10n`（四份 ARB）。

**Spec:** `docs/epics/epic-63-dictionary-lookup/spec.md` §3.6、§3.7、§5、§9（驗收 11、16、17、18、19、21、22、34、35、36、39）；`issues.md` 的 Issue 6a；調查結論見 `docs/research/dictionary/DICTIONARY_FORMATS_AND_LICENSES.md`「驗證結果（Issue 1）」；Issue 5 延後項見 `plan-issue-5.md` 尾端「交給後續 Issue」。

## Global Constraints

- 新增套件只有 `dict_reader: 1.6.1`（精確版本）；加入前先把七個授權全文放進 `app/assets/licenses/` 並登錄 `third_party_licenses.dart`（見 Task 2）。不動 `pubspec.yaml` 的其他相依、主資料庫（`version: 28`）、`main.js`、`sync_table_specs.dart`；`dictionary.db` 版本與表結構不變（`referenced_css`、`storage_path` 欄位已存在）。
- 程式碼中不得有取自 Readest 或其他 AGPL／GPL 專案的內容；不得參考 `js-mdict` v7 以後的程式碼（`DICTIONARY_FORMATS_AND_LICENSES.md` §4）。
- WebView：`javaScriptEnabled: false`；擋所有網路與檔案請求；只載入我們傳入的 HTML 字串，`loadDataWithBaseURL`，baseUrl 固定 `https://dict.local/`；畫面上同時最多一個 `InAppWebView`，沒有巢狀捲動。
- 對所有 `http(s)` 請求（含 `favicon.ico`、`data:` 之外的一切）必須回傳明確回應，找不到回 404 空內容；回傳 `null` 會讓 WebView 走真實網路。
- 所有攔截到的非 MDX 內部連結（`http`、`https`、`file` 等）一律不載入、不開啟。
- 圖片資源鍵轉換順序：網址 → 去掉 baseUrl 與開頭 `/` → `Uri.decodeComponent` → 把 `/` 換成 `\` → 前面加 `\`；找不到再試不加開頭 `\` 的形式。依副檔名設 `contentType`：`image/jpeg`、`image/png`、`image/gif`、`image/webp`、`image/svg+xml`。
- 區塊壓縮型態為 LZO 時，匯入顯示三段式錯誤「這本字典使用 LZO 壓縮，目前不支援。請改用 zlib 版本，或用 MDict 工具重新打包。」並整批回復、不留半成品（驗收 39）。`Encrypted=2` 必須支援；記錄區塊加密（`Encrypted` 含 1）匯入時偵測並顯示三段式錯誤（驗收 21）。
- 錯誤訊息三段式；字串走 `AppLocalizations`，四份 ARB 同步（zh_TW 範本附 `@key` 說明、zh_CN 為簡體）；畫面不加 `AnimatedXxx`，E-Ink 用邊框不用陰影。
- 所有文件與註解用正體中文；commit 訊息不加 `Co-Authored-By`；每個 Task 只跑觸及的測試檔，完整 `flutter test` 只在最後一個 Task 跑一次。

## Review Focus

1. **匯入中途失敗或取消不留半成品**：LZO、截斷、加密、取消，任何一種之後，`dictionary_sources` 沒有新列、私有目錄沒有殘留檔（Task 5）。
2. **WebView 不連網**：任何 `http(s)` 請求都得到明確回應；`entry://`、`bword://` 以外的連結點了沒反應（Task 4、7 的純函式測試＋Task 9 真機）。
3. **記憶體**：開啟 MDX 後增量（含 `KeyCaseSensitive=No` 的折疊索引、32 MB 區塊快取）在 E-Ink 上實測，不得讓 App 被系統回收（Task 1、Task 9）。
4. **同名詞與查無**：同一個詞多筆都要回傳；查不到回 `notFound`，不丟例外（Task 3、6）。
5. **刪除與取代**：刪除 MDX 字典後私有目錄整個清掉；取代時 `referenced_css` 重新抽樣；已開啟的 reader 要先關閉再刪檔（Task 5、6）。

## 已決定事項（spec 沒寫清楚，本計畫的選擇）

- **Task 1 是量測與決策關卡，不是寫程式。** 要在 E-Ink 實機用真實 CJK 檔補測記憶體（`issues.md` 第一個任務）。結果超過 50 MB 增量時，停下來問使用者要不要走備案（vendor 修補 `dict_reader`），不自行改方向。
- **`MdxReader` 介面（`storage/mdx_reader.dart`）：** `open(path)`、`meta`（標題、編碼、`keyCaseSensitive`、`stripKey`、`encrypted`、`entryCount`）、`lookupAll(key)`（同鍵多筆）、`resource(key)`（只對 `.mdd` 有意義）、`validateBlocks()`（匯入時整檔檢查）、`close()`。查詢字串規則（`KeyCaseSensitive=No` 折疊、`StripKey=Yes` 去空白標點）寫在這一層，上層不知道。
- **統一錯誤：** `MdxException(MdxErrorKind kind)`，`kind` 為 `unsupportedCompression`、`encryptedRecords`、`corrupt`、`notFound`、`other`；`dict_reader` 丟的字串與各種例外都包成它。匯入失敗時轉成 `DictionaryImportException` 的新碼：`unsupportedCompression`、`encryptedRecords`、`corruptFile`（既有碼不變）。
- **標題：** 標頭 `Title` 是預設佔位字串（以 `Title (No HTML code allowed)` 開頭）或空白時，改用 `Description` 第一行（去 HTML 標籤與空白），再不行用檔名（不含副檔名）。結果只用於 `ImportHints.name` 的預填。
- **匯入的整檔檢查：** `validateBlocks()` 掃描所有記錄區塊：每塊的壓縮型態必須是 0 或 2（zlib 為 2），每塊的位移加壓縮後長度不得超過檔案大小；型態 1（LZO）→ `unsupportedCompression`，超出檔案 → `corrupt`。實作者可自選逐塊讀 8 位元組標頭或透過 `readWithOffset()`，但不得把整份記錄區塊解壓進記憶體；在背景 `Isolate`（頂層函式、參數只含可跨 Isolate 傳遞的型別）執行，主 Isolate 只收進度與結果。
- **搬檔：** 先 `File.rename` 到私有目錄，失敗（跨掛載點）改串流複製再刪來源；不整檔讀進記憶體。目標為 `<DictionaryFileStore.dirFor(sourceId)>/<原檔名>`；`storage_path` 存這個私有路徑。`.mdd`、`.css` 同目錄。
- **`ImportRequest` 加選填 `companions`：** `List<({String path, String name})>`，預設空；MDX 匯入器用它接 `.mdd`、`.css`。不改其他匯入器。
- **來源語言／方向：** 沿用 Issue 5 的三選一對話框；MDX 的 `ImportHints` 不帶語言（標頭沒有可靠欄位），所以方向由使用者必選。
- **`referenced_css`：** 匯入時抽樣前 200 筆詞條（用 `extractReferencedCssNames`），結果寫入來源列；取代時重新抽樣。
- **Reader 池：** `MdxReaderPool`（`storage/mdx_reader_pool.dart`）最多同時保留 2 個已開啟的 `MdxReader`，LRU 淘汰；每個 reader 以來源 id 為鍵。刪除或取代字典前呼叫 `pool.evict(sourceId)`。理由：E-Ink 上開啟一本 20 MB 字典要約 1.8 秒，不能每次查詢重開；同時開太多會超過記憶體預算。Task 1 的量測結果若顯示一個就太多，改成最多 1 個。
- **面板拿資源的方式：** `DictionaryService` 加三個方法（都依來源 id）：`mdxResource(sourceId, key)`、`mdxCss(sourceId)`（回傳該字典私有目錄內所有 `.css` 的檔名→內容對照）、`lookupInSource(sourceId, word)`（交叉參照用）。WebView 元件只認這三個函式，不認 `MdxReader`。
- **WebView 元件可替換：** 查詢面板接收 `MdxEntryViewBuilder`（預設建 `MdxEntryView`），widget test 注入假元件；`InAppWebView` 本身只在真機整合測試與手動確認驗證，單元測試驗它的純函式。
- **返回堆疊：** 屬於面板（`DictionaryLookupSheet`）的狀態：每次點交叉參照把「目前顯示的詞條」推入；面板標題列在堆疊非空時顯示返回鈕（`Key('dictionary_lookup_back')`）。切換分段時清空堆疊並丟棄舊 WebView。
- **`sound://`：** 連結不可點，維持原樣顯示（前處理時把 `href` 移除，文字保留）。
- **深色與 E-Ink：** 前處理注入一段覆寫樣式，蓋掉詞條寫死的文字與背景色；顏色取自目前主題的 `ColorScheme`（E-Ink 為純黑字白底、無背景圖）。

---

## 檔案結構

```text
app/
├── pubspec.yaml                                  [修改] 加 dict_reader: 1.6.1
├── assets/licenses/                              [新增] 七個授權全文
├── tool/make_test_mdx.py                         [新增] 自製 MDX／MDD 產生器（自寫，進版控）
├── lib/
│   ├── licenses/third_party_licenses.dart        [修改] 登錄七項
│   ├── dictionary/
│   │   ├── importers/
│   │   │   ├── dictionary_importer.dart          [修改] ImportRequest.companions、新錯誤碼
│   │   │   └── mdx_importer.dart                 [新增]
│   │   ├── storage/
│   │   │   ├── mdx_reader.dart                   [新增] 薄封裝
│   │   │   ├── mdx_reader_pool.dart              [新增]
│   │   │   └── dictionary_store.dart             [修改] _decodeCssNames 容錯
│   │   ├── providers/mdx_dictionary_provider.dart [新增]
│   │   ├── mdx_html_prepare.dart                 [新增] 純函式：錨點、CSS 內嵌、sound、覆寫樣式
│   │   ├── mdx_link_policy.dart                  [新增] 純函式：連結分類、資源鍵轉換、contentType
│   │   ├── dictionary_file_store.dart            [修改] 檔名消毒、搬檔
│   │   ├── dictionary_manager.dart               [修改] evict、刪除前關 reader
│   │   └── dictionary_service.dart               [修改] 依 format 選 provider、三個 mdx* 方法
│   ├── screens/
│   │   ├── widgets/mdx_entry_view.dart           [新增] InAppWebView 元件
│   │   ├── widgets/dictionary_lookup_sheet.dart  [修改] html 詞條、返回堆疊、builder 注入
│   │   └── dictionary_settings_screen.dart       [修改] MDX 群組匯入
│   ├── l10n/app_{zh_TW,zh,zh_CN,en}.arb          [修改]
│   └── main.dart                                 [修改] 註冊 MdxImporter 與 reader 池
└── test/
    ├── fixtures/mdx/                             [新增] 自製小檔
    ├── dictionary/ mdx_reader_test.dart、mdx_importer_test.dart、mdx_html_prepare_test.dart、
    │               mdx_link_policy_test.dart、mdx_dictionary_provider_test.dart、mdx_reader_pool_test.dart
    ├── screens/widgets/ dictionary_lookup_sheet_test.dart（修改）、mdx_entry_view_test.dart
    └── screens/dictionary_settings_screen_test.dart  [修改]
app/integration_test/dictionary_mdx_test.dart     [新增] 真機：WebView 行為
```

---

### Task 1：E-Ink 記憶體量測與決策（controller 與使用者在真機執行，不派子代理）

**Files:**
- Modify: `docs/research/dictionary/DICTIONARY_FORMATS_AND_LICENSES.md`（在「驗證結果」補「Issue 6a 補測」一節）

**Interfaces:** 無程式介面；產出是數字與一個 go／no-go 結論。

- [ ] **Step 1: 準備量測檔**

用 `.scratch/mdx_spike/`（不進版控）既有的探針 App 與 `bench.dart`；檔案：`tmp/dictionary/教育部重編國語辭典.mdx`（真實 CJK、UTF-16、163,085 筆）。再用 `make_test_mdx.py` 產一個 UTF-16 的 40 萬筆合成大檔（`--entries 400000`，鍵改成 CJK；需要時擴充產生器的鍵格式，不進版控）。

- [ ] **Step 2: 在 E-Ink 實機（Allwinner WAVE）量測**

每個檔各量三次（每次先強制停止 App）：開啟後記憶體增量、**隨機鍵**（從全部鍵隨機抽 500 個，不是前 1000 筆）查詢後的穩態記憶體、p50／p95、開啟後峰值。

- [ ] **Step 3: 決策**

增量（含快取穩態）≤ 50 MB：記錄結果，繼續 Task 2。超過：**停下來**，把數字與兩個選項（vendor 修補 `dict_reader` 改成依區塊延遲載入鍵；Reader 池改成最多 1 個並接受更慢的第二次查詢）交給使用者決定，不自行選。

- [ ] **Step 4: Commit**

```bash
git add docs/research/dictionary/DICTIONARY_FORMATS_AND_LICENSES.md
git commit -m "docs(epic-63): Issue 6a E-Ink 真實 CJK 大檔記憶體補測"
```

---

### Task 2：加入 `dict_reader`、授權與測試 fixture

**Files:**
- Modify: `app/pubspec.yaml`、`app/lib/licenses/third_party_licenses.dart`
- Create: `app/assets/licenses/{dict-reader,blockchain-utils,pointycastle,charset,convert,collection-typed-data,html-unescape}.txt`（檔名可依既有慣例調整）、`app/tool/make_test_mdx.py`、`app/test/fixtures/mdx/*.mdx|*.mdd|*.css`
- Test: 既有授權頁測試（`test/licenses/` 下找現有檔名，擴充）

**Interfaces:**
- Produces: `dict_reader: 1.6.1` 可 import；七項授權登錄；fixtures（見下）。
- Fixtures（全部自製，進版控）：`zlib.mdx`（50 筆，`KeyCaseSensitive=No`）、`mdd.mdd`、`fake-lzo.mdx`、`truncated.mdx`、`cut-records.mdx`（截在記錄區段）、`html.mdx`（詞條含 `entry://`、`bword://`、`entry://#x`、`#x`、`<img src="pic/a b.png">`、`<link href="ghychyz.css">`、`sound://`、`http://example.com` 連結，標頭有 `StyleSheet`）、`strip-key.mdx`（`StripKey=Yes`）、`placeholder-title.mdx`（`Title (No HTML code allowed)`、有 `Description`）。`.scratch/mdx_spike/fixtures/` 的前五個可直接複製；後三個用 `make_test_mdx.py` 新增 kind 產生。`large.mdx` 不進版控。

- [ ] **Step 1: 寫失敗的測試**

授權頁測試：`kThirdPartyLicenses` 含七個新套件名稱，且每個 `assetPath` 都在 asset bundle 內讀得到、非空、含該授權的關鍵字（MIT／BSD／Apache）。

- [ ] **Step 2: 執行測試，確認失敗**

Run（在 `app/`）: `flutter test test/licenses`
Expected: FAIL（找不到新套件與 asset）。

- [ ] **Step 3: 實作**

`flutter pub add dict_reader:1.6.1` 後確認 `pubspec.lock` 只新增研究文件列的六個遞移套件（`dict_reader`、`blockchain_utils`、`charset`、`convert`、`html_unescape`、`pointycastle`），`win32` 相依鏈不變。授權全文逐字複製自各套件的 `LICENSE`（pub cache），不改寫。產生器 `make_test_mdx.py` 以 spike 版為基礎，加 `html`、`strip-key`、`placeholder-title` 三個 kind，並在檔頭註明是自寫、無第三方程式碼。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2；再跑 `flutter analyze`。Expected: PASS、No issues found。

- [ ] **Step 5: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/assets/licenses app/lib/licenses app/tool/make_test_mdx.py app/test/fixtures/mdx app/test/licenses
git commit -m "feat(epic-63): Issue 6a 加入 dict_reader 與授權、MDX 測試檔"
```

---

### Task 3：`MdxReader` 薄封裝

**Files:**
- Create: `app/lib/dictionary/storage/mdx_reader.dart`
- Test: `app/test/dictionary/mdx_reader_test.dart`

**Interfaces:**
- Produces:
  - `enum MdxErrorKind { unsupportedCompression, encryptedRecords, corrupt, notFound, other }`；`class MdxException implements Exception { const MdxException(this.kind, [this.detail]); }`
  - `class MdxMeta { final String title; final String? description; final bool keyCaseSensitive; final bool stripKey; final int encrypted; final int entryCount; }`；`title` 已套用「標題佔位字串」規則的前一步（原始 `Title`），最終顯示名稱由 `String displayName(String fileName)` 決定。
  - `class MdxReader { static Future<MdxReader> open(String path); MdxMeta get meta; String displayName(String fileName); Future<List<String>> lookupAll(String key); Future<List<int>?> resource(String key); Future<void> validateBlocks({void Function(int done, int total)? onProgress}); Future<void> close(); }`

- [ ] **Step 1: 寫失敗的測試**（用 Task 2 的 fixtures）

- `open` 成功：`entryCount == 50`；檔案不存在 → `MdxException(notFound)`；`truncated.mdx` 在 10 秒內 → `corrupt`；`open` 失敗後不留半初始化狀態（再 `open` 同路徑的好檔可成功）。
- `lookupAll`：命中回傳 HTML 字串清單；查無回傳空清單；空字串與純空白不丟例外；`KeyCaseSensitive=No` 的 `APPLE` 查得到 `apple`；`strip-key.mdx` 的 `' 一 '`、`'一，'` 查得到 `一`；同一個鍵兩筆記錄都回傳。
- `displayName`：`placeholder-title.mdx` 回傳 `Description` 第一行（無標籤）；`Description` 也空時回傳檔名不含副檔名；正常 `Title` 原樣回傳。
- `resource`：`mdd.mdd` 以 `\pic\a b.png` 查得到位元組；查無回傳 `null`。
- `validateBlocks`：`zlib.mdx` 通過；`fake-lzo.mdx` → `unsupportedCompression`；`cut-records.mdx`（`open` 能成功）→ `corrupt`；`onProgress` 被呼叫、最後一次 `done == total`。
- `meta.encrypted`：以 `tmp/dictionary/教育部重編國語辭典.mdx` 為真實驗收檔的案例，檔案不存在時 `skip`（`Encrypted=2` 可開啟並查詢，驗收 34）。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/dictionary/mdx_reader_test.dart`
Expected: FAIL（找不到檔案）。

- [ ] **Step 3: 實作**

`dict_reader` 的各種失敗（含它對不支援壓縮丟的**字串**、`FormatException`、`StateError`、`RangeError`、`FileSystemException`）全部在此轉成 `MdxException`。`KeyCaseSensitive=No` 的折疊：對鍵與查詢字串套同一個 `toLowerCase`；若需另建折疊索引，只建「折疊後鍵 → 原鍵清單」的對照，並在 class doc 記下記憶體代價。`StripKey=Yes`：查詢字串去掉空白與標點（Unicode 標點類別 `\p{P}`、全形空白）後再查。記錄區塊加密（`Encrypted` 含 1）在 `open` 後立刻 `encryptedRecords`。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2；`flutter analyze`。Expected: PASS、No issues found。

- [ ] **Step 5: Commit**

```bash
git add app/lib/dictionary/storage/mdx_reader.dart app/test/dictionary/mdx_reader_test.dart
git commit -m "feat(epic-63): Issue 6a MdxReader 薄封裝與統一錯誤"
```

---

### Task 4：HTML 前處理與連結政策（純函式）

**Files:**
- Create: `app/lib/dictionary/mdx_html_prepare.dart`、`app/lib/dictionary/mdx_link_policy.dart`
- Test: `app/test/dictionary/mdx_html_prepare_test.dart`、`app/test/dictionary/mdx_link_policy_test.dart`

**Interfaces:**
- Produces（`mdx_html_prepare.dart`）:
  - `String prepareEntryHtml(String html, {required Map<String, String> cssByFileName, required MdxTheme theme})`：依序做（1）`href="entry://#x"` 與 `href='entry://#x'` 改寫成 `#x`；（2）`<link ... href="x.css">` 依**檔名**（只比對檔名、不分大小寫）換成內嵌 `<style>`，沒有對應檔案的 `<link>` 移除，所有 `@import` 移除；（3）`sound://` 連結移除 `href` 保留文字；（4）在 `<head>` 或文件開頭注入 `theme` 的覆寫樣式；回傳完整 HTML 文件字串（沒有 `<html>` 外殼時自動包上，並含 `<meta charset>`、`<meta name="viewport">`）。
  - `class MdxTheme { const MdxTheme({required Color foreground, required Color background, required bool isEink}); String get overrideCss; }`（`Color` 轉 `#rrggbb`；E-Ink 為純黑字白底、`*{background-image:none!important}`）。
- Produces（`mdx_link_policy.dart`）:
  - `const String kMdxBaseUrl = 'https://dict.local/';`
  - `sealed class MdxLinkAction`：`MdxEntryLink(String word)`（`entry://詞`、`bword://詞`，已 URL 解碼、去掉結尾 `/`）、`MdxAnchorLink`（純 `#x` 或 `https://dict.local/#x`，不攔截）、`MdxBlockedLink`（其餘一切，含 `http`、`https`、`file`、`sound`、`javascript`）。
  - `MdxLinkAction classifyLink(String url)`。
  - `List<String> resourceKeyCandidates(String requestUrl)`：依 Global Constraints 的轉換順序，回傳 `[r'\pic\a b.png', r'pic\a b.png']`（先帶開頭 `\` 後不帶）；網址不在 `kMdxBaseUrl` 下時回傳空清單。
  - `String? contentTypeFor(String key)`：依副檔名（不分大小寫）回傳 `image/jpeg`（`.jpg`、`.jpeg`）、`image/png`、`image/gif`、`image/webp`、`image/svg+xml`；其他回 `application/octet-stream`；無副檔名回 `null`。

- [ ] **Step 1: 寫失敗的測試**

`mdx_html_prepare_test.dart`：
- `entry://#top` 變 `#top`；`entry://詞` 不動；單引號版本也改寫。
- `<link rel="stylesheet" href="GHYCHYZ.css">` 且 `cssByFileName` 含 `ghychyz.css` → 換成含該 CSS 內容的 `<style>`；`href="css/a.css"` 只比對檔名 `a.css`；沒有對應檔案 → `<link>` 被移除；`@import url(x.css);` 被移除。
- `<a href="sound://a.mp3">發音</a>` → 不含 `sound://`、文字「發音」仍在。
- 深色 `MdxTheme` 的覆寫樣式出現在輸出；E-Ink 版含 `background-image:none`；輸出含 `<meta charset`。
- 沒有 `<html>` 的片段與完整文件都能處理；空字串回傳有效文件。

`mdx_link_policy_test.dart`：
- `classifyLink`：`entry://apple`、`bword://apple` → `MdxEntryLink('apple')`；`entry://%E5%A4%A9%E5%9C%B0/` → `MdxEntryLink('天地')`；`#x`、`https://dict.local/#x` → `MdxAnchorLink`；`https://example.com`、`http://dict.local/x`（非 https）、`file:///x`、`sound://a`、`javascript:alert(1)` → `MdxBlockedLink`。
- `resourceKeyCandidates('https://dict.local/pic/a%20b.png')` 等於 `[r'\pic\a b.png', r'pic\a b.png']`；含編碼斜線 `%2F` 的網址先剝 baseUrl 再解碼；非 dict.local 網址 → 空清單。
- `contentTypeFor`：五種副檔名與大小寫、未知副檔名、無副檔名。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/dictionary/mdx_html_prepare_test.dart test/dictionary/mdx_link_policy_test.dart`
Expected: FAIL。

- [ ] **Step 3: 實作**

兩檔都只放純函式與型別，不 import `flutter_inappwebview`。HTML 用正規表示式處理即可（不引入 HTML 解析套件）；`<link>` 比對要容忍屬性順序、單雙引號、大小寫。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2；`flutter analyze`。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/dictionary/mdx_html_prepare.dart app/lib/dictionary/mdx_link_policy.dart app/test/dictionary
git commit -m "feat(epic-63): Issue 6a MDX HTML 前處理與連結政策純函式"
```

---

### Task 5：`MdxImporter`、私有目錄、`DictionaryManager` 接線與 Issue 5 延後項

**Files:**
- Create: `app/lib/dictionary/importers/mdx_importer.dart`
- Modify: `app/lib/dictionary/importers/dictionary_importer.dart`、`app/lib/dictionary/dictionary_file_store.dart`、`app/lib/dictionary/dictionary_manager.dart`、`app/lib/dictionary/storage/dictionary_store.dart`、`app/lib/main.dart`
- Test: `app/test/dictionary/mdx_importer_test.dart`、`dictionary_manager_test.dart`、`dictionary_store_test.dart`、`dictionary_file_store_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `MdxReader`、`MdxException`；Issue 5 的 `DictionaryFileStore`、`DictionaryManager`、`extractReferencedCssNames`。
- Produces:
  - `ImportRequest` 加選填 `List<({String path, String name})> companions`（預設 `const []`）。
  - `DictionaryImportException` 新碼：`unsupportedCompression`、`encryptedRecords`、`corruptFile`。
  - `class MdxImporter implements DictionaryImporter { MdxImporter({required DictionaryStore store, required DictionaryFileStore files}); }`：`canHandle` 為副檔名 `.mdx`（不分大小寫）；`readHints` 回傳 `ImportHints(name: reader.displayName(fileName))`（語言為 `null`）；`import`：重複偵測（`computeContentId`，與 JSON 路徑同一套，含 `replaceExisting`）→ `open` → `validateBlocks`（進度回報 `ImportStage.parsing`）→ 搬檔進 `files.dirFor(sourceId)` → 複製 `.mdd`／`.css` → 抽樣前 200 筆詞條寫 `referenced_css` → 寫入 `format = mdx` 的來源列（`entryCount = meta.entryCount`、`storagePath` 為私有複本路徑）→ `done`。任何一步失敗或取消：刪除該 `sourceId` 的私有目錄、不留來源列。取代時沿用舊字典的 `id`、`priority`、`enabled`。
  - `DictionaryFileStore.moveInto(String sourceId, String path, String name)`（先 `rename`，失敗改串流複製再刪來源）；`copyInto`／`dirFor` 對檔名取 `p.basename` 並拒絕空字串與 `..`（Issue 5 延後項）。
  - `DictionaryManager.delete`／取代前先呼叫注入的 `onEvict(sourceId)`（Task 6 的 reader 池接上；本 Task 先接一個可注入的 callback，預設空）。
  - `DictionaryStore._decodeCssNames` 遇到壞 JSON 或非字串元素回傳空清單（Issue 5 延後項）。
  - `main.dart`：`importerFactories` 加 `(s) => MdxImporter(store: s, files: dictionaryFileStore)`。

- [ ] **Step 1: 寫失敗的測試**

`mdx_importer_test.dart`（記憶體 DB＋暫存目錄＋Task 2 fixtures）：
- 匯入 `html.mdx`＋`mdd.mdd`＋一個 `.css`：來源列 `format == mdx`、`entryCount` 正確、`storagePath` 在私有目錄內且檔案存在、私有目錄含 `.mdd` 與 `.css`；`referenced_css` 含 `ghychyz.css`；`list()` 的 `missingCss` 在 `.css` 缺席時含它、在場時為空（驗收 38）。
- `fake-lzo.mdx` → stream 以 `DictionaryImportException('unsupportedCompression')` 結束；**沒有來源列、私有目錄不存在**（驗收 39、Review Focus 1）。
- `cut-records.mdx` → `corruptFile`，同樣無殘留。
- 取消（匯入中取消訂閱）→ 無殘留。
- 重複匯入同一檔 → `DuplicateDictionaryException`；`replaceExisting: true` 後 `id`、`priority`、`enabled` 不變、`referenced_css` 重新抽樣。
- `readHints('placeholder-title.mdx')` 的名稱是 `Description` 第一行（驗收 36）。
- 記錄區塊加密的檔案（以 `MdxReader` 測試用假檔或直接 stub `MdxException(encryptedRecords)`）→ `encryptedRecords`。

`dictionary_manager_test.dart`：刪除 MDX 字典後私有目錄整個不在；`delete` 會先呼叫 `onEvict`；`DictionaryManager.import` 帶 `companions` 時會傳給匯入器。
`dictionary_store_test.dart`：`referenced_css` 欄位寫入壞 JSON（`rawUpdate`）時 `getSource`／`listSources` 不丟例外且 `referencedCss` 為空。
`dictionary_file_store_test.dart`：檔名含 `../x`、`a/b.css`、空字串時只取 basename 或丟 `ArgumentError`；`moveInto` 跨目錄成功且來源檔消失。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/dictionary/mdx_importer_test.dart test/dictionary/dictionary_manager_test.dart test/dictionary/dictionary_store_test.dart test/dictionary/dictionary_file_store_test.dart`
Expected: FAIL。

- [ ] **Step 3: 實作**

整檔檢查在 `Isolate` 內做時，closure 必須是頂層函式（見 `CLAUDE.md` 的「不可逆的技術決策」）。匯入器把整個流程包在 `try/finally`，失敗路徑統一走「刪私有目錄」的清理函式；清理本身失敗只記錄、不蓋掉原錯誤。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2；`flutter analyze`。Expected: PASS、No issues found。

- [ ] **Step 5: Commit**

```bash
git add app/lib/dictionary app/lib/main.dart app/test/dictionary
git commit -m "feat(epic-63): Issue 6a MDX 匯入器、私有目錄與整檔檢查"
```

---

### Task 6：`MdxReaderPool`、`MdxDictionaryProvider` 與服務接線

**Files:**
- Create: `app/lib/dictionary/storage/mdx_reader_pool.dart`、`app/lib/dictionary/providers/mdx_dictionary_provider.dart`
- Modify: `app/lib/dictionary/dictionary_service.dart`、`app/lib/dictionary/dictionary_manager.dart`、`app/lib/main.dart`、`app/test/support/fake_dictionary_service.dart`
- Test: `app/test/dictionary/mdx_reader_pool_test.dart`、`mdx_dictionary_provider_test.dart`、`dictionary_service_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `MdxReader`；Task 5 的 `DictionaryFileStore`。
- Produces:
  - `class MdxReaderPool { MdxReaderPool({int maxOpen = 2, Future<MdxReader> Function(String path)? opener}); Future<MdxReader> acquire(String sourceId, String path); Future<void> evict(String sourceId); Future<void> closeAll(); }`：同一來源重複 `acquire` 回傳同一個 reader；超過 `maxOpen` 時關閉最久未用的；`opener` 可注入（測試用假 reader）。
  - `class MdxDictionaryProvider implements DictionaryProvider { MdxDictionaryProvider({required MdxReaderPool pool, required DictionarySource source}); }`：用既有 `lookupCandidates`／`dedupeByHeadwordNorm`（`lang: source.sourceLang`）逐一 `reader.lookupAll`，第一個有結果的候選停；回傳 `ProviderOutcome(status: found, entries: [...DictionaryEntry(bodyKind: html, body: html, headword: 候選)])`；查無回 `notFound`；`MdxException` 回 `failed`（`errorCode` 用 `kind.name`），不丟例外。
  - `DictionaryService`：建構子多接 `MdxReaderPool? mdxPool` 與 `DictionaryFileStore? files`（`fromProvider` 與 `lazy` 都選填；未提供時遇到 MDX 來源回 `failed`，`errorCode: 'mdxUnavailable'`）；`_lookupOne` 依 `source.format` 選 provider；新增 `Future<List<int>?> mdxResource(String sourceId, String key)`、`Future<Map<String, String>> mdxCss(String sourceId)`、`Future<List<DictionaryEntry>> lookupInSource(String sourceId, String word)`（交叉參照；不走候選鏈以外的語言過濾）。
  - `main.dart`：建立一個 `MdxReaderPool`，傳給 `DictionaryService.fromProvider` 與 `DictionaryManager.onEvict`。
  - `FakeDictionaryService` 補上三個方法（記錄呼叫、可設定回傳）。

- [ ] **Step 1: 寫失敗的測試**

`mdx_reader_pool_test.dart`（注入假 `opener`）：重複 `acquire` 同一來源只開一次；開第三個時第一個被關閉（`maxOpen: 2`）；`evict` 關閉並移除，之後再 `acquire` 會重開；`closeAll` 全關；開啟失敗不記住（下次重試）。
`mdx_dictionary_provider_test.dart`（真 `MdxReader`＋fixtures）：`zlib.mdx` 查 `apple` → `found`、`bodyKind == html`；英文候選鏈（`ran`→`run` 類，用 fixtures 中適用的詞）命中；查無 → `notFound`；`fake-lzo.mdx` 的查詢 → `failed` 且 `errorCode == 'unsupportedCompression'`，不丟例外；同鍵兩筆都回傳。
`dictionary_service_test.dart` 新增：含一個 JSON 來源與一個 MDX 來源時 `outcomes` 兩個分段依優先序；未提供 pool 時 MDX 來源 `failed`；`mdxResource`、`mdxCss`（回傳私有目錄內 `.css` 的檔名→內容，檔名維持原寫法）、`lookupInSource` 各一個正向與一個查無案例。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/dictionary/mdx_reader_pool_test.dart test/dictionary/mdx_dictionary_provider_test.dart test/dictionary/dictionary_service_test.dart`
Expected: FAIL。

- [ ] **Step 3: 實作**

池內的 reader 以 `Future` 記錄（避免並發 `acquire` 開兩次）。`evict`／`closeAll` 要等進行中的查詢結束再關（用每個 reader 的簡單排隊即可，不加鎖套件）。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2；`flutter analyze`。Expected: PASS、No issues found。

- [ ] **Step 5: Commit**

```bash
git add app/lib/dictionary app/lib/main.dart app/test/dictionary app/test/support
git commit -m "feat(epic-63): Issue 6a MDX 查詢提供者、reader 池與服務接線"
```

---

### Task 7：`MdxEntryView`、查詢面板的 HTML 顯示與返回堆疊

**Files:**
- Create: `app/lib/screens/widgets/mdx_entry_view.dart`
- Modify: `app/lib/screens/widgets/dictionary_lookup_sheet.dart`、`app/lib/screens/reader_screen.dart`（只傳入 service 已有的方法，不動選取）、四份 ARB
- Test: `app/test/screens/widgets/dictionary_lookup_sheet_test.dart`（修改）、`app/test/screens/widgets/mdx_entry_view_test.dart`（新增）

**Interfaces:**
- Consumes: Task 4 的 `prepareEntryHtml`、`classifyLink`、`resourceKeyCandidates`、`contentTypeFor`、`MdxTheme`、`kMdxBaseUrl`；Task 6 的 `DictionaryService.mdxResource`／`mdxCss`／`lookupInSource`。
- Produces:
  - `typedef MdxEntryViewBuilder = Widget Function(BuildContext context, MdxEntryViewConfig config);`
  - `class MdxEntryViewConfig { final String sourceId; final String html; final bool isEinkMode; final Future<List<int>?> Function(String key) loadResource; final Future<Map<String, String>> Function() loadCss; final void Function(String word) onEntryLink; }`
  - `class MdxEntryView extends StatefulWidget { const MdxEntryView({super.key, required this.config}); }`：`Key('mdx_entry_view')`；建構 `InAppWebView`，設定：`javaScriptEnabled: false`、`allowFileAccess: false`、`allowContentAccess: false`、`cacheEnabled: false`、`useShouldOverrideUrlLoading: true`、`useShouldInterceptRequest: true`；以 `loadDataWithBaseURL(baseUrl: kMdxBaseUrl)` 載入 `prepareEntryHtml(...)` 的結果；`shouldOverrideUrlLoading` 用 `classifyLink`：`MdxEntryLink` → `onEntryLink(word)` 並 `CANCEL`，`MdxAnchorLink` → `ALLOW`，`MdxBlockedLink` → `CANCEL`；`shouldInterceptRequest`：`https://dict.local/` 下的圖片以 `resourceKeyCandidates` 依序 `loadResource`，命中回 `WebResourceResponse`（`contentType` 用 `contentTypeFor`、`statusCode: 200`），**其餘所有 `http(s)` 請求（含 `favicon.ico`）一律回 404 空內容**，永不回傳 `null`。
  - `DictionaryLookupSheet`：新增選填 `MdxEntryViewBuilder? mdxEntryViewBuilder`（預設建 `MdxEntryView`）與 `DictionaryService`-衍生的 `mdxHandlers`（把 service 的三個方法包成 `({loadResource, loadCss, lookupInSource})`，由 `show()` 組好傳入）；選中分段的詞條 `bodyKind == html` 時，該分段內容以 `Expanded` 放一個 builder 產生的元件（獨佔面板剩餘高度，不放進 `ListView`）；`plainText` 詞條行為不變。
  - 返回堆疊：面板狀態 `List<_ViewedEntry>`；`onEntryLink(word)` → 呼叫 `lookupInSource(sourceId, word)`，有結果就推入目前詞條並顯示新詞條，查無則在面板頂端顯示一行提示（`dictionaryLookupLinkNotFound`，三段式不需要，屬提示），不推入；堆疊非空時標題列顯示返回鈕 `Key('dictionary_lookup_back')`，點了彈出並還原上一個詞條；切換分段清空堆疊並讓舊元件被丟棄（不同時保留兩個）。
  - l10n：`dictionaryLookupBack`（tooltip，zh_TW「返回上一個詞條」）、`dictionaryLookupLinkNotFound`（zh_TW「找不到這個詞條」）。

- [ ] **Step 1: 寫失敗的測試**

`mdx_entry_view_test.dart`：`MdxEntryViewConfig` 的純邏輯測試（不建 `InAppWebView`）：把 `shouldOverrideUrlLoading` 與 `shouldInterceptRequest` 的決策寫成 `MdxEntryView` 內可單元測試的靜態函式（例：`static NavigationDecision decideNavigation(String url, void Function(String) onEntryLink)`、`static Future<InterceptResult> decideRequest(String url, Future<List<int>?> Function(String) loadResource)`），測：`entry://apple` → 取消並回呼 `apple`；`#x` → 放行；`https://example.com` → 取消且不回呼；圖片網址命中 → 200 與正確 `contentType`、先試帶 `\` 的鍵再試不帶；圖片查無 → 404；`https://dict.local/favicon.ico` → 404；`https://example.com/a.png` → 404（不回傳 `null`）；任何情況都不回傳 `null`。
`dictionary_lookup_sheet_test.dart` 新增（注入假 builder，假元件把 `config` 存起來並放一個 `Key('fake_mdx_view')`）：選中 MDX 分段時畫面上有一個假元件、沒有 `ListView` 內的純文字詞條；切換到非 MDX 分段時假元件被移除（同一時間最多一個，驗收 32）；呼叫 `config.onEntryLink('x')`：`lookupInSource` 被呼叫、顯示新詞條、出現返回鈕；再連點兩次後返回兩次回到原詞條；`lookupInSource` 回空 → 顯示提示、不出現返回鈕；切換分段清空堆疊；E-Ink 模式找不到 `AnimatedXxx`。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/screens/widgets/mdx_entry_view_test.dart test/screens/widgets/dictionary_lookup_sheet_test.dart`
Expected: FAIL。

- [ ] **Step 3: 實作**

先加 ARB 並 `flutter gen-l10n`。`MdxEntryView` 的決策函式是純的，`InAppWebView` 只做轉接。主題色取自 `Theme.of(context).colorScheme`。載入前 `await config.loadCss()`；`loadCss` 失敗當作沒有 CSS。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2，再跑 `flutter test test/screens/reader_screen_test.dart --plain-name "Epic 63"` 確認 Issue 4、5 沒有回歸；`flutter analyze`、`node tool/check_l10n_hardcoded_strings.js`。
Expected: PASS、No issues found。

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens app/lib/l10n app/test/screens
git commit -m "feat(epic-63): Issue 6a MDX 詞條 WebView 顯示與返回堆疊"
```

---

### Task 8：設定畫面的 MDX 匯入流程

**Files:**
- Modify: `app/lib/screens/dictionary_settings_screen.dart`、四份 ARB
- Test: `app/test/screens/dictionary_settings_screen_test.dart`

**Interfaces:**
- Consumes: Task 5 的 `MdxImporter`（經 `manager.canImport('x.mdx')` 為真）、`ImportRequest.companions`、新錯誤碼；Issue 5 的 `planCompanions`／`CompanionPlan`。
- 流程變更（取代 Issue 5 的「這個版本還不能匯入 MDX」分支）:
  - `manager.canImport(group.mdx.name)` 為真時，對每個 `MdxGroup`：`readHints` → 匯入對話框（名稱預填、方向必選、授權說明）→ `import(request.copyWith companions: [group.mdd, ...group.css])`，其餘沿用 Issue 5 的進度遮罩、取消、重複匯入提示、摘要。
  - 摘要多一行：若匯入後 `list()` 該字典有 `missingCss`，列出「詞條引用了 … 但沒有匯入」並提示可用「新增附屬檔案」補上。
  - 三個新錯誤碼各一則三段式訊息（LZO 用 Global Constraints 的文字）；`dictionaryImportMdxNotYet` 不再使用（保留 ARB 鍵待下一次清理，或一併刪除並確認 `check_l10n_hardcoded_strings.js` 通過）。
  - 匯入完成後對每個新匯入的 `.mdx` 呼叫 `FilePicker.clearTemporaryFiles()`（`try/catch` 包住，失敗只記錄；Issue 5 延後項）。
- l10n：`dictionaryImportErrorUnsupportedCompression`、`dictionaryImportErrorEncryptedRecords`、`dictionaryImportErrorCorruptFile`、`dictionaryImportMissingCssAfterImport(files)`。

- [ ] **Step 1: 寫失敗的測試**（用 `FakeDictionaryManager`，`canImportFn` 對 `.mdx` 回真）

- 選 `a.mdx`＋`a.mdd`＋`x.css`：`import` 被呼叫一次，`request.companions` 含 `a.mdd` 與 `x.css`；對話框的方向未選時「匯入」按鈕停用。
- `import` stream 丟 `DictionaryImportException('unsupportedCompression')`／`encryptedRecords`／`corruptFile`：各顯示對應三段式訊息，且畫面上沒有原始碼字串；LZO 訊息含「改用 zlib 版本」。
- 匯入成功但新字典 `missingCss` 非空：摘要含缺檔提醒。
- 同批 `a.mdx`＋`b.json`：兩者各跳一次對話框、各匯入一次；`.mdx` 失敗不影響 `b.json`。
- 只選 `.css`（沒有 `.mdx`）：仍顯示「沒有可附加的字典」提醒。
- `canImport('a.mdx')` 為假時（沒有 MDX 匯入器的組態）：維持 Issue 5 的「還不能匯入」行為（回歸保護）。
- 匯入完成後呼叫了清除暫存檔的注入函式（`clearTempFiles` 以建構參數注入，測試記錄呼叫）。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/screens/dictionary_settings_screen_test.dart`
Expected: FAIL。

- [ ] **Step 3: 實作**

先加 ARB 並 `flutter gen-l10n`。`clearTempFiles` 預設用 `FilePicker.clearTemporaryFiles`，建構參數可注入（與 `pickFiles` 同一個風格）。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2；`flutter analyze`、`node tool/check_l10n_hardcoded_strings.js`。
Expected: PASS、No issues found。

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens app/lib/l10n app/test/screens
git commit -m "feat(epic-63): Issue 6a 設定畫面 MDX 匯入流程"
```

---

### Task 9：全套驗證與真機確認

**Files:**
- Create: `app/integration_test/dictionary_mdx_test.dart`
- Modify: `docs/epics/epic-63-dictionary-lookup/issues.md`（狀態 `in-review`）、本計畫（勾選）

- [ ] **Step 1: 寫整合測試（真機）**

`dictionary_mdx_test.dart`（`-d <device-id>`；用 Task 2 的 fixtures 放進私有目錄後直接建 `MdxEntryView`，不經檔案選擇器）：MDX 詞條在 WebView 顯示、JavaScript 不執行（詞條內放 `<script>` 改動 `document.title` 或 DOM，斷言沒變）、對外網路請求被擋（請求計數器回 404）、`entry://` 可點可返回、`#錨點` 與 `entry://#錨點`（改寫後）可跳轉、`.mdd` 圖片在無 JavaScript 下顯示（含路徑帶反斜線與空白）、深色與 E-Ink 配色下文字可讀。依 `app/tool/README.md` 的格式引用 Key，並跑 `node tool/check_integration_keys.js`。

- [ ] **Step 2: 靜態檢查**

在 `app/` 執行：
```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
node tool/check_integration_keys.js
```
Expected: 三者皆乾淨。

- [ ] **Step 3: 完整測試（整張計畫唯一一次）**

Run: `flutter test`
Expected: All tests passed。

- [ ] **Step 4: 回歸確認**

- `git diff main -- app/android app/lib/library app/lib/sync` 無輸出；`pubspec.yaml` 只多 `dict_reader`。
- 主資料庫版本仍為 28；`dictionary.db` 版本仍為 1。
- 授權：`app/assets/licenses/` 七項齊全，授權頁顯示。
- 程式碼中沒有取自 Readest／AGPL／GPL 專案的內容（自查：`dict_reader` 之外的 MDX 解析程式都是自寫）。

- [ ] **Step 5: 真機確認（人工）**

在 E-Ink 機與一般機各做（驗收檔：`tmp/dictionary/教育部重編國語辭典.mdx`、`簡明古漢語常用字字典.mdx`，只作本機測試）：
1. 匯入教育部 MDX：進度、名稱（有意義的書名）、方向必選、完成摘要。
2. 匯入古漢語 MDX：名稱不是佔位字串（用 `Description`）；摘要顯示缺 `ghychyz.css`；用「新增附屬檔案」補一個 `.css` 後提醒消失（驗收 36、38）。
3. 閱讀器選字查詢：MDX 分段顯示在 WebView，排版可讀；`StyleSheet` 展開（畫面上沒有 `` `數字` `` 殘留，驗收 35）。
4. 詞條內的 `entry://` 交叉參照可點、可返回；`#錨點` 可跳；圖片（如有 `.mdd`）顯示。
5. 深色佈景與 E-Ink：文字與背景對比可讀（驗收 19）。
6. 匯入 LZO 假檔（`fake-lzo.mdx`）、截斷檔：顯示三段式錯誤，清單沒多一本、私有目錄沒殘留（`adb shell run-as` 檢查）。
7. 刪除 MDX 字典後私有目錄整個清掉；刪除後查詢不再出現。
8. 記憶體：E-Ink 上開啟教育部字典後 `dumpsys meminfo` 增量在 Task 1 的結果範圍內；面板開關與切換分段 10 次後 App 沒被系統回收。
9. 面板開著時旋轉螢幕或按返回鍵：不當掉，選取與工具列維持（Issue 4 約束）。

- [ ] **Step 6: 更新文件並 Commit**

把 `issues.md` Issue 6a 狀態改成 `in-review`；本計畫 Step 全部勾選；在計畫尾端補真機結果。

```bash
git add docs/epics/epic-63-dictionary-lookup app/integration_test
git commit -m "docs(epic-63): Issue 6a 實作完成，更新狀態"
```

---

## 交給後續 Issue

- **Issue 6b：** MDX 圖片的進階處理、獨立 CSS 的更多情境、深色與 E-Ink 配色的精修（本 Issue 只做「可讀」的覆寫樣式）。
- **Issue 7：** 線上查詞分段；面板的「線上查詢已關閉」入口（Issue 5 已接上設定連結）。
- **Issue 8：** 授權頁與隱私頁的 MDX 說明、l10n 收尾、整合測試補齊；字典設定的說明文字註明「JavaScript 關閉時，依賴 `onclick` 的互動（例如牛津 9 的圖片放大）不會運作」。

---

## 自我檢查

- **Spec 覆蓋：** §3.6 的 MDX 處理表——`entry://`／`bword://`（Task 4、7）、`#錨點` 改寫（Task 4）、圖片與 `contentType`（Task 4、7）、外部 CSS 內嵌與移除（Task 4、5）、深色與 E-Ink（Task 4）、LZO（Task 3、5、8）、加密（Task 3、5、8）、`StyleSheet`（`dict_reader` 內建，真機 Task 9 確認）、`StripKey`／`KeyCaseSensitive`（Task 3）、標題（Task 3、5）、`sound://`（Task 4）；§3.6 面板規則——獨佔高度、一次一個 WebView、返回堆疊、切換分段丟棄（Task 7）；§3.7 MDX 匯入（Task 5、8）；驗收 11、16、17、18、19、21、22、34、35、36、39（Task 3 至 9）。
- **Issue 5 延後項：** `_decodeCssNames` 容錯、檔名消毒、取代時重抽 `referenced_css`、`clearTemporaryFiles`、`.mdx` 分支換成實際匯入（Task 5、8）。
- **型別一致：** `MdxReader`／`MdxException` 只在 Task 3 定義；`prepareEntryHtml`、`classifyLink` 等只在 Task 4 定義；`MdxReaderPool`、`MdxDictionaryProvider` 只在 Task 6 定義；`MdxEntryViewConfig`、`MdxEntryViewBuilder` 只在 Task 7 定義；`ImportRequest.companions` 只在 Task 5 定義，Task 8 使用。
- **比例：** 測試案例與簽章佔大宗，沒有函式本體。
