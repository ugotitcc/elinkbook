# Issue 8：授權頁、隱私頁、l10n 收尾、整合測試 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 收尾 epic-63：逐項盤點驗收 1 至 39 並補上缺口、補齊授權與資料來源標示、補 PRD／`CONTEXT.md`／ADR／`CLAUDE.md` 文件、補整合測試與真機驗收。

**Architecture:** 以「先盤點、再補缺口」進行：Task 1 產出驗收對照表與缺口清單，Task 2 至 4 各補一類缺口（授權、文件、測試），Task 5 做全套驗證。不改變任何功能行為。

**Tech Stack:** Flutter、Markdown 文件、`gen-l10n`（只有在盤點發現缺字串時才動）。不新增套件，不動 `pubspec.yaml`。

**Spec:** `docs/epics/epic-63-dictionary-lookup/spec.md` §7（測試策略）、§9（驗收 1 至 39）；`issues.md` 的 Issue 8；`epic.md` §10 第 3、4、7 項；`docs/research/dictionary/DICTIONARY_FORMATS_AND_LICENSES.md` §6、§7（授權與標示規則）；上游延後項見 `plan-issue-7.md`「交給後續 Issue」與 `plan-issue-6b.md`「交給後續」。

## Global Constraints

- 不改功能行為；不新增套件；不動 `pubspec.yaml`、主資料庫（`version: 28`）、`app/android/app/src/main/assets/foliate/main.js`、`dictionary.db` 結構。
- 授權全文取自上游原檔，不改寫（`third_party_licenses.dart` 檔頭規則，epic-55 design Q3）。
- 所有文件與註解用正體中文；專業術語可保留英文；程式碼識別字維持原樣。
- 字串一律走 `AppLocalizations`（若有新增字串，四份 ARB 同時加）。
- commit 訊息不加 `Co-Authored-By`。
- 每個 Task 只跑觸及的測試檔；完整 `flutter test` 只在最後一個 Task 跑一次。
- **整合測試警告：** `flutter test integration_test/...` 跑完會把手機上的 App 解除安裝並清掉資料。跑之前一定先告訴人類，並確認人類同意。
- 驗收 31（沒有取自 AGPL／GPL 專案的程式碼）由人類最終確認，本計畫只提供檢查證據，不代為宣告成立。
- **開工前先問人類（Task 2 之前）：** 授權 asset 採「標示聲明＋官方網址」，不內嵌 CC 法律全文。人類確認後才開始 Task 2，避免 asset 與測試返工。**已確認（2026-10-22）：採標示聲明＋官方網址。**
- 整合測試的測試資料（JSON、CC-CEDICT）一律在測試執行時用 Dart 寫入 `getTemporaryDirectory()`，不新增 `app/test/fixtures/` 檔案（新增就得改 `pubspec.yaml`）。

## Review Focus

1. **盤點遺漏**：驗收 1 至 39 逐項都要有「自動測試名稱」或「真機證據」其中之一；只靠推論的項目要標成缺口，不能假裝通過（Task 1）。
2. **授權文字被改寫**：新增的授權 asset 必須是上游原文，版權人與年份要對；非原文的說明（本 App 如何使用）要放在明確分開的段落（Task 2）。
3. **ADR 與實作不一致**：ADR 寫的決策、取捨、替代方案必須對得上實際程式（例如 `dictionary.db` 確實獨立、`LookupRequest` 確實只有 `word`）（Task 3）。
4. **整合測試清掉人類資料**：任何要在真機跑的整合測試，都要先取得人類同意（Task 4、5）。
5. **文件互相矛盾**：PRD 條目、`CONTEXT.md` 詞條、ADR、`spec.md` 的用詞與數字要一致（例如「選取上限 8 個 CJK 字元」「線上查詞預設關閉」）（Task 3）。

## 已決定事項（spec 沒寫清楚，本計畫的選擇）

- **授權 asset 的內容：** 萌典資料與 CC-CEDICT 都是「資料」不是程式碼，也都不內建在 App 裡。授權頁各放一份「標示聲明」：資料名稱、著作權人、授權名稱與網址、本 App 如何使用（萌典：使用者啟用線上查詞後即時查詢；CC-CEDICT：使用者自行匯入）。完整的 CC 法律條文以官方網址連結為準，不內嵌（CC 授權允許以網址標示授權）。這一點需要人類確認。
- **`dict_reader` 的修補：** vendor 修補版的 LICENSE 原文已在 `assets/licenses/dict-reader.txt`；授權頁的顯示名稱補上「含本專案修補，見 `app/third_party/dict_reader/PATCH.md`」，不改 LICENSE 原文。
- **ADR 編號：** 接續現有最大編號 0037，新增 0038、0039。
- **PRD 編號：** 接續現有最大編號 FR-49，新增 FR-50 起。
- **`CLAUDE.md` 與 `AGENTS.md`：** 兩份各補一小節「字典查詢」，內容相同，描述架構最終樣貌（不記進度），依該檔「只在改變架構事實時才修改」的規則。兩份的架構章節是平行的，只改一份會脫節。

## 檔案結構

| 動作 | 路徑 | 責任 |
|---|---|---|
| 建立 | `docs/epics/epic-63-dictionary-lookup/reviews/acceptance-issue-8.md` | 驗收對照表與缺口清單（`reviews/` 不進版控） |
| 建立 | `app/assets/licenses/moedict-data.txt`、`app/assets/licenses/cc-cedict.txt` | 資料來源標示聲明 |
| 修改 | `app/lib/licenses/third_party_licenses.dart` | 登錄兩筆資料來源；`dict_reader` 名稱補註 |
| 修改 | `app/test/licenses/third_party_licenses_test.dart` | 新條目的測試；既有 19 筆斷言改為 21 筆 |
| 修改 | `docs/prd.md` | 字典查詢 FR 條目、frontmatter `history`、§6 技術決策備註 |
| 修改 | `CONTEXT.md` | 字典詞條 |
| 建立 | `docs/adr/0038-dictionary-data-in-separate-database.md`、`docs/adr/0039-online-lookup-request-carries-word-only.md` | 兩份 ADR |
| 修改 | `CLAUDE.md`、`AGENTS.md` | 「字典查詢」一小節（兩份內容相同） |
| 修改 | `docs/epics/epic-63-dictionary-lookup/epic.md` | §10 第 3、4、7 項標為已完成；檔頭狀態與進度表回填 |
| 建立／修改 | `app/test/...`、`app/integration_test/dictionary_lookup_flow_test.dart` | 依盤點缺口補測試；整合測試 |

---

### Task 1：驗收 1 至 39 逐項盤點

**Files:**
- Create: `docs/epics/epic-63-dictionary-lookup/reviews/acceptance-issue-8.md`（不進版控）

**Interfaces:** 不新增程式。產出一張表：驗收編號、內容摘要、證據類型（自動測試／真機證據／人類確認／缺口）、證據位置（`檔案::測試名稱`，或 `issues.md` 的真機記錄段落）。

- [x] **Step 1: 逐項尋找證據。** 對 `spec.md` §9 的 1 至 39（注意 39 排在 34 與 35 之間）每一項，用 `grep -rn` 在 `app/test/`、`app/integration_test/`、`issues.md`、各 `plans/` 的真機記錄裡找證據。測試名稱含驗收關鍵字的優先；找不到就標「缺口」。已知已有證據：
  - 7、8、9、10、15（Issue 7 測試與計畫 Task 8 對照）。
  - 18、19（Issue 6b 測試與真機截圖）、25（6a 與 6b 的記憶體量測）、26（E-Ink 面板無動畫的既有測試）。
  - 28（主庫仍是 `version: 28`）、29（`main.js` 在 epic-63 全期無改動，用 `git log` 驗證）。
- [x] **Step 2: 缺口分類。** 缺口只有三種結論：「補自動測試」、「補真機證據（要人類在場）」、「確認為已知限制並寫進 `issues.md`」。不得標成「推論通過」。
- [x] **Step 3: 驗證指令。** 把每個指令的輸出貼進對照表：
  - 驗收 29：`git log 795b644a..HEAD --oneline -- app/android/app/src/main/assets/foliate/main.js`。`795b644a` 是 epic-63 啟動前的基準 commit。輸出為空，代表全期無改動。
  - 驗收 28：`grep -n "version: 28" app/lib/library/sqlite_library_repository.dart`。要看到第 55 行附近的 `version: 28`。
  - 驗收 31（只提供證據，不代為宣告成立）：
    1. 讀 `app/third_party/dict_reader/PATCH.md`，再跑 `git diff 795b644a..HEAD --stat -- app/third_party/dict_reader`。確認修補只含本專案自寫的延遲載入，沒有複製自 `readest/js-mdict`（AGPL-3.0）或 `mdict-cpp`。
    2. 讀 `app/pubspec.lock` 中 epic-63 新增的相依鏈（`dict_reader`、`blockchain_utils`、`pointycastle`、`charset` 等），逐一對照 `app/assets/licenses/` 的授權，確認全是 MIT、BSD-3-Clause 或 Apache-2.0，沒有 GPL／AGPL。
    3. 把查驗結果寫進 `acceptance-issue-8.md` 的驗收 31 列，標為「人類確認」。
- [x] **Step 4: 回報缺口清單給人類。** 在對話裡列出缺口與建議處理方式，等人類決定哪些要補，再進 Task 4。本 Task 不 commit（報告不進版控）。

---

### Task 2：授權與資料來源標示

**Files:**
- Create: `app/assets/licenses/moedict-data.txt`、`app/assets/licenses/cc-cedict.txt`
- Modify: `app/lib/licenses/third_party_licenses.dart`
- Test: `app/test/licenses/third_party_licenses_test.dart`

**Interfaces:**
- Consumes: `ThirdPartyLicense(packageName, assetPath)`、`kThirdPartyLicenses`（`third_party_licenses.dart`）；`MoedictProvider.attribution`（`app/lib/dictionary/providers/moedict_provider.dart`，固定標示字串）。
- Produces: `kThirdPartyLicenses` 新增兩筆：`萌典（教育部《重編國語辭典修訂本》資料）`、`CC-CEDICT 資料`；`dict_reader` 的 `packageName` 補註修補版。

- [x] **Step 1: 寫失敗測試**（`third_party_licenses_test.dart`，沿用既有的 `_FakeBundle`／真 bundle 測試風格）。先改兩個既有測試，不然改完清單它們會失敗：
  - 第 51 行 `19 項：12 項程式元件加 7 款字型…`：改名為 `21 項：12 項程式元件、2 筆資料來源加 7 款字型…`。期望清單加入兩筆新名稱，並把 `'dict_reader'` 換成補註後的完整名稱。
  - 第 86 行 `以真實 rootBundle 登錄：19 筆…`：筆數 19 改 21。第 106 行 `textByPackage['dict_reader']` 的 key 換成補註後的完整名稱。

  再新增：
  - `登錄清單含萌典資料與 CC-CEDICT 資料`：兩個名稱都在 `kThirdPartyLicenses`。
  - `新 asset 可由真實 bundle 載入`（用 `rootBundle`）：`moedict-data.txt` 含 `CC BY-ND 3.0 TW`、`教育部`、`重編國語辭典修訂本`、授權網址 `https://creativecommons.org/licenses/by-nd/3.0/tw/`；`cc-cedict.txt` 含 `CC BY-SA`、`CC-CEDICT`、授權網址。
  - `萌典標示與 provider 常數一致`：`moedict-data.txt` 內含 `MoedictProvider.attribution` 全文（避免兩處寫法不同）。
  - `dict_reader 名稱註明修補版`：名稱含 `PATCH.md`。
  - 既有「名稱不重複、asset 路徑不重複」的測試涵蓋新條目（不重寫，確認仍通過）。
  - 補註後的 `dict_reader` 完整名稱，在 `third_party_licenses.dart` 與測試裡用同一個寫法（測試可直接引用 `kThirdPartyLicenses` 的項目，不手打第二份）。
- [x] **Step 2: 執行確認失敗**
  Run: `cd app && flutter test test/licenses/third_party_licenses_test.dart`
  Expected: FAIL。
- [x] **Step 3: 寫兩個 asset 與登錄。** 每個 asset 分兩段，中間以單獨一行 `----` 分開：上段是標示聲明（資料名稱、著作權人、授權名稱與網址、本 App 如何使用）；下段是本 App 使用方式的說明。萌典：上段第一行**逐字貼上 `MoedictProvider.attribution` 全文**（`資料來源：教育部《重編國語辭典修訂本》（CC BY-ND 3.0 TW），經由萌典提供`，不改字序、不改標點），其後再補授權網址 `https://creativecommons.org/licenses/by-nd/3.0/tw/`、萌典網址 `www.moedict.tw`，以及「結果原文顯示不改動；使用者啟用線上查詞後才即時查詢，本 App 不內建、不散布」。CC-CEDICT：CC BY-SA 4.0，本 App 不內建，使用者自行匯入。著作權人與版本以 `docs/research/dictionary/DICTIONARY_FORMATS_AND_LICENSES.md` §6、§7 為準；該文件沒寫的欄位（例如 CC-CEDICT 的著作權人字樣）**不得自行編造**，改寫成「見上游網址」並向人類回報。`pubspec.yaml` 已宣告整個 `assets/licenses/` 目錄，不用改。
- [x] **Step 4: 執行確認通過**（同 Step 2 指令；另跑 `cd app && flutter analyze` 與 `node tool/check_l10n_hardcoded_strings.js`）Expected: PASS。
- [x] **Step 5: 確認 App 內沒有其他隱私或授權文字需要同步。** 執行 `grep -rn -i "privacy\|隱私" app/lib --include=*.dart -l`；若有 App 內的隱私說明畫面，補上字典與線上查詞段落（比照 `site/privacy.html` 第 7 條）並補測試；若沒有，在對話裡註明「App 內無隱私頁，只有網站」。
- [x] **Step 6: Commit**
  ```bash
  git add app/assets/licenses app/lib/licenses app/test/licenses
  git commit -m "feat(epic-63): Issue 8 授權頁補萌典與 CC-CEDICT 資料來源標示"
  ```

---

### Task 3：PRD、`CONTEXT.md`、ADR、`CLAUDE.md`

**Files:**
- Modify: `docs/prd.md`、`CONTEXT.md`、`CLAUDE.md`、`AGENTS.md`、`docs/epics/epic-63-dictionary-lookup/epic.md`
- Create: `docs/adr/0038-dictionary-data-in-separate-database.md`、`docs/adr/0039-online-lookup-request-carries-word-only.md`

**Interfaces:** 純文件。每個條目都要能對回實作或 spec 章節。

- [x] **Step 1: `docs/prd.md` 新增 FR-50 起的字典條目**（放在「4.3 互動、分析與知識管理」表格內，編號接續 FR-49，優先順序 P1）：
  - FR-50 字典查詢：EPUB／TXT／MD 選字後出現「查字典」，固定版面與 CBZ 不出現；選字規則（去頭尾標點、片語整串查、CJK 上限 8 字元、內部含標點不查）。
  - FR-51 字典匯入與管理：JSON／CSV／CC-CEDICT／MDX（含 `.mdd`、`.css`）匯入；來源語言與目標語言必填；啟用、排序、刪除；重複匯入偵測；加密與 LZO 的 MDX 顯示明確錯誤。
  - FR-52 查詢面板：分段選擇器一次顯示一本字典、返回堆疊、MDX 詞條在無 JavaScript 的 WebView 顯示（含圖片、獨立 CSS、深色與 E-Ink 配色）。
  - FR-53 線上查詞（萌典）：預設關閉、需同意、只送選取的詞、僅 `https`、結果原文顯示並附來源標示。
  - 條目文字以 `spec.md` §9 的驗收標準為依據，數字（8 字元、5 秒逾時、300 ms、50 MB）必須與 spec 完全一致。
  - 在 frontmatter `history` 新增本次修訂記錄（比照 FR-48、FR-49 的寫法）。
  - 在 §6「技術架構備註與後續規劃」補一段 FR-50～53 的決策交叉參照，指向 `docs/epics/epic-63-dictionary-lookup/` 與 ADR 0038、0039。
- [x] **Step 2: `CONTEXT.md` 新增「字典查詢」一節**，每個詞條照該檔既有格式（粗體詞、一段定義、`_Avoid_`）：字典來源（Dictionary Source）、查詢請求（Lookup Request，只含 `word`）、查詢候選鏈（Candidate Chain）、分段（Segment）、線上查詢同意（Online Lookup Consent，有值＝已同意且開啟，與 `spec`／實作的 `onlineConsentAt` 一致）、詞形還原（Lemmatization，只登錄英文）。
- [x] **Step 3: 兩份 ADR**，格式照 `docs/adr/0037-*.md`（標題、狀態、背景、決策、替代方案與取捨、後果）：
  - 0038：字典資料獨立於主庫 `dictionary.db`。要寫的取捨：不動主庫 `version: 28` 與同步表規格；字典可整個刪除或重建；代價是兩個 SQLite 檔、跨庫查詢要在 Dart 端組合；替代方案是放進主庫（被否決的理由見 `spec.md` §4）。
  - 0039：線上查詢請求型別只含詞（`LookupRequest` 只有 `word`，沒有前後文、書名、位置）。要寫的取捨：隱私優先、同意與隱私頁一致、測試固定這個型別（`lookup_request_test.dart`）；代價是將來要做「情境化查詞」必須是另一個請求型別與另一套同意流程；替代方案是送前後文以提高消歧品質（被否決）。
  - 兩份都要引用實際檔案路徑與測試名稱當證據，並註明狀態「已採納（2026-10-22）」。
- [x] **Step 4: `CLAUDE.md` 與 `AGENTS.md` 各補「字典查詢」一小節**（兩份內容相同；放在各自「`LibraryScreen` 與圖書庫管理」之後，≤ 15 行，只描述最終架構）：`DictionaryService`（協調本機與線上分段、永不丟例外）、`dictionary.db` 與 `DictionaryStore`、`MdxReader`＋vendor 修補的 `dict_reader`（`app/third_party/dict_reader/PATCH.md`）、MDX 詞條 WebView 的安全邊界（JavaScript 關閉、所有請求回明確回應、永不連網）、線上查詞預設關閉且未同意零請求、`LookupRequest` 只有 `word`。不寫進度、不寫日期、不寫 PR 編號。
- [x] **Step 5: `epic.md` 更新。** §10 的第 3、4、7 項標註「已完成（Issue 8）」。檔頭狀態改為「收尾中」。進度表的 Issue 3 至 8 回填完成狀態與 PR 摘要（PR 編號以 `git log` 為準，Issue 8 的 PR 尚未建立就留空，合併後再補）。
- [x] **Step 6: 文件一致性檢查。** 用 `grep -n "8 個\|8 字元\|5 秒\|300 ms\|50 MB" docs/prd.md CONTEXT.md docs/adr/0038-*.md docs/adr/0039-*.md CLAUDE.md AGENTS.md` 對照 `spec.md`，數字不一致的修到一致。
- [x] **Step 7: Commit**
  ```bash
  git add docs CONTEXT.md CLAUDE.md AGENTS.md
  git commit -m "docs(epic-63): Issue 8 補 PRD 字典需求、詞彙表、兩份 ADR 與 CLAUDE.md 字典查詢段落"
  ```

---

### Task 4：依盤點結果補測試與整合測試

**Files:**
- Modify／Create: 依 Task 1 缺口清單決定（`app/test/...`）
- Create: `app/integration_test/dictionary_lookup_flow_test.dart`

**Interfaces:**
- Consumes: Task 1 的缺口清單（人類確認要補的項目）。
- Produces: 每個被補的缺口有一個測試，測試名稱開頭帶驗收編號，例如 `驗收 20：重複匯入同一檔案提示已匯入`。

- [ ] **Step 1: 逐項補自動測試。** 只補人類在 Task 1 Step 4 確認要補的「補自動測試」缺口。每個缺口先寫失敗測試、確認失敗原因正確，再視需要補最小實作（若缺口其實是功能缺陷，停止並回報人類，不在本 Issue 偷偷改功能）。
- [ ] **Step 2: 寫整合測試** `dictionary_lookup_flow_test.dart`（真機）。用真實 `DictionaryService`、真實 `DictionaryManager`、真實 `dictionary.db`（暫存目錄），直接呼叫匯入器與 `DictionaryLookupSheet.show`，不經檔案選擇器。測試資料在 `setUp` 用 Dart 字串寫進 `getTemporaryDirectory()` 下的檔案（最小 JSON、最小 CC-CEDICT 文字），再把路徑交給匯入器。不依賴 `app/test/fixtures/`，做法比照 `cedict_importer_test.dart`、`json_csv_importer_test.dart`：
  - `JSON 字典匯入後，查詢面板顯示結果`：匯入 → 開面板 → 找到詞條文字。
  - `查詢候選鏈：ran 能查到只存 run 的字典`（驗收 13）。
  - `CC-CEDICT：查繁體與簡體得到同一筆，並顯示授權說明`（驗收 33）。
  - `沒有網路也能查本機字典`（驗收 5，用注入的 `isNetworkAvailable: () async => false`）。
  - `刪除字典後相關資料清除`（驗收 6）：呼叫 `DictionaryManager.delete(id)`（它會一併刪 `.mdd`、`.css` 等本機附屬檔；`DictionaryStore.deleteSource` 只刪資料庫記錄），再斷言詞條查不到、附屬檔不存在。
  沿用 `dictionary_mdx_test.dart` 的檔頭註解與暫存檔做法。
- [ ] **Step 3: 靜態檢查。** Run: `cd app && flutter analyze && node tool/check_integration_keys.js && node tool/check_l10n_hardcoded_strings.js`。Expected: `No issues found!`；兩支腳本無錯誤。
- [ ] **Step 4: 先問人類再跑整合測試。** 在對話裡說明「會把手機上的 App 解除安裝並清掉資料」，人類同意後才執行 `cd app && flutter test integration_test/dictionary_lookup_flow_test.dart -d <device-id>`。Expected: 全數通過。跑完提醒人類重新匯入字典與書。
- [ ] **Step 5: Commit**
  ```bash
  git add app/test app/integration_test
  git commit -m "test(epic-63): Issue 8 補驗收缺口測試與字典查詢整合測試"
  ```

---

### Task 5：全套驗證、真機確認與收尾

- [ ] **Step 1: 靜態檢查。** Run: `cd app && flutter analyze && node tool/check_l10n_hardcoded_strings.js && node tool/check_integration_keys.js`。Expected: `No issues found!`；兩支腳本無錯誤。
- [ ] **Step 2: 完整測試（本計畫唯一一次）。** Run: `cd app && flutter test`。Expected: 全數通過。有失敗先單獨在 `main` 跑該檔確認是不是既有失敗，一致才可註明並略過。
- [ ] **Step 3: 驗收對照表定稿。** 更新 `reviews/acceptance-issue-8.md`：Task 4 補完後每個缺口改為有證據，仍無證據的列為「已知限制」並確認已寫進 `issues.md`。
- [ ] **Step 4: 真機確認（請人類在場）**，裝置：WAVE E-Ink 機。
  0. **重建環境。** Task 4 的整合測試已把 App 解除安裝並清掉資料。先執行 `cd app && flutter run -d <device-id>` 重新安裝，再匯入一本範例 EPUB（如 `app/test/fixtures/sample.epub`）。要測字典查詞，另請人類重新匯入一本字典。
  1. 設定頁的授權頁看得到「萌典」與「CC-CEDICT」兩筆資料來源標示，內容正確、可捲動。
  2. EPUB 選字 → 查字典 → 結果顯示（選字用 `adb shell input swipe` 長按，或人類用電磁筆；這台機器手指長按有斷訊問題，見 `issues.md` 後續項目第 3 項）。
  3. 面板開啟時間與記憶體（沿用 6a、6b 的量測方式，記錄數字）。
- [ ] **Step 5: 回報。** 把結果寫進 `reviews/`（不進版控）。通過後等人類決定合併。合併後才更新 `issues.md` 狀態與 `docs/epics.md` 備註。**歸檔（搬到 `docs/archive/`）由人類指定，本計畫不做。**

---

## 交給人類

- 確認授權 asset 採「標示聲明＋官方網址」而非內嵌 CC 法律條文全文（見「已決定事項」）。
- 確認 CC-CEDICT 的著作權人字樣（研究文件沒寫的部分不得自行編造）。
- 驗收 31（沒有取自 AGPL／GPL 專案的程式碼）最終確認。
- Google Play 資料安全表單（Issue 7 隱私頁更新後仍需手動填寫）。
- 決定 epic-63 何時歸檔。

## 交給後續

- 後續優化（不在 Phase 1）：StarDict 匯入、`sound://` 音訊、外開連結範本、PDF 選字查詢、`.mdd` 分卷與放在 `.mdd` 內的 `.css`（見 `epic.md` §11 與 `plan-issue-6b.md`）。
- `issues.md` 檔尾的後續項目：選取控點蓋住面板、長按選字在 WAVE E-Ink 機難以觸發、匯入大 `.mdd` 時沒有進度或成功提示。

---

## 自我檢查

- **Spec 覆蓋：** `issues.md` Issue 8 的四個 What to build：授權（Task 2）、PRD 與 `CONTEXT.md`（Task 3）、兩份 ADR（Task 3）、整合測試與真機驗收（Task 4、5）；驗收 1 至 39 逐項盤點（Task 1、5）。
- **與 issues.md 的差異：** Issue 8 原文第一項「新增所用套件的授權全文到 `assets/licenses/`」，`dict_reader` 與其遞移相依已在 Issue 6a 完成，所以本計畫改為補「資料來源標示」與 `dict_reader` 修補版註記；`CLAUDE.md` 補一節為新增項（原文沒寫，但 `CLAUDE.md` 目前完全沒有字典架構描述）。
- **型別一致：** `kThirdPartyLicenses`、`ThirdPartyLicense`、`MoedictProvider.attribution` 都是既有名稱，Task 2 只引用不重新定義。
- **比例：** 本計畫幾乎全是檔案路徑、驗證指令與要寫的文件重點，沒有函式本體。
