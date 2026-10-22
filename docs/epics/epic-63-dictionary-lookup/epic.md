# `epic-63-dictionary-lookup` 字典查詢（離線匯入＋可選線上查詞）

**狀態：** 🟡 收尾中（Issue 1 至 7 已合併，Issue 8 進行中）
**存放路徑：** `docs/epics/epic-63-dictionary-lookup/`
**關聯文件：** `spec.md`、`issues.md`
**調查文件：** `docs/research/dictionary/PHASE1_AUDIT.md`、`DICTIONARY_FORMATS_AND_LICENSES.md`、`READEST_ANALYSIS_AND_PROPOSAL.md`
**關聯 PRD 章節：** `docs/prd.md` FR-50～53（Issue 8 補上）；詞彙見 `CONTEXT.md`「字典查詢」一節；架構決定見 ADR 0038、0039

## 背景

使用者希望在閱讀時選字後查字典，涵蓋三個方向：英→繁中、中→英、中→中。使用者可以匯入自己的字典檔、管理已安裝字典、離線查詢。線上查詞為選用，且可設定。

稽核結論（2026-10-19，詳見 `PHASE1_AUDIT.md`）：

- 專案內沒有任何字典功能。`text_conversion_dict.dart` 是 OpenCC 簡繁轉換表，與字典無關。
- 選字文字已經從 `main.js` 傳到 Dart（`EpubSelectionInfo.text`），不需要改 JavaScript。
- 查字典按鈕掛在 `AnnotationToolbar`。
- 專案只有 Android。主資料庫已到 `version: 28`，字典資料另開 `dictionary.db`。
- `AndroidManifest.xml` 設了 `usesCleartextTraffic="true"`，線上請求要在 Dart 端強制 `https`。

## Discovery 決策（`/grill-with-docs`，2026-10-19）

| 問題 | 結論 |
|---|---|
| 平台 | 只做 Android |
| 查詢入口 | `AnnotationToolbar` 新增按鈕，開底部面板 |
| 匯入格式 | JSON/CSV、CC-CEDICT、MDX。StarDict 延後 |
| 字典存放 | 獨立的 `dictionary.db` |
| 線上查詞 | 預設關閉；預設端點為萌典；第一次使用要同意；只送選取的詞 |
| 自訂網址 | 不做（Phase 2 候選：外開連結版） |
| 三個方向 | 每本字典標記來源與目標語言；依選字的字元類型挑字典；使用者可調順序 |
| MDX 顯示 | WebView，關閉 JavaScript、擋所有網路 |
| Readest 分析採納 | 查詢候選鏈與英文詞形還原；片語與 CJK 8 字元規則；MDX 最低要求（交叉參照、錨點、圖片、CSS、配色） |
| MDX 解析器 | **採用 `dict_reader 1.6.1`（MIT）**，Issue 1 驗證（2026-10-19）：兩個真實檔都能開，實機（一般平板與 E-Ink Allwinner WAVE）效能在門檻內；`mdict_flutter` 淘汰（真實檔開啟失敗）。記憶體裕度只有約 4–5 MB，真實 CJK 大檔待 Issue 6a 補測。**不用 `readest/js-mdict`**（v7 起 AGPL-3.0），2026-10-19 決定；備案見 `DICTIONARY_FORMATS_AND_LICENSES.md` |
| CC-CEDICT | Phase 1 新增 `CedictImporter`（它不是 JSON、CSV 或 MDX）；不內建、不散布，使用者自行下載。拼音顯示轉成聲調符號（`pīn yīn`，音節間保留空白），資料庫存原文；注音留待後續 |
| MDX 外部 CSS | 匯入時可多選 `.mdx`、`.mdd`、`.css`；CSS 依詞條 `<link href>` 的檔名配對；缺檔仍可讀並提醒，可事後補匯入 |
| 驗收用字典 | `tmp/dictionary/` 下的教育部 MDX、簡明古漢語 MDX、CC-CEDICT；只作本機測試，不進版控、不放 fixtures |


---

以下章節沿用調查階段的編號（見 `spec.md` 開頭說明）。

## 進度記錄

| Issue | 狀態 | PR | 摘要 |
|---|---|---|---|
| 1 MDX 解析器技術驗證 | done（2026-10-19） | #343 | 採用 `dict_reader 1.6.1`；`mdict_flutter` 淘汰。實機（平板、E-Ink）效能在門檻內，large.mdx 開啟後記憶體增量最高 45.7 MB，裕度約 4 MB。結論與封裝必補清單見 `docs/research/dictionary/DICTIONARY_FORMATS_AND_LICENSES.md`「驗證結果」。 |
| 2 模型、介面、`dictionary.db` 與 `DictionaryStore` | done（2026-10-19） | #344 | 純 Dart 資料層，35 個測試。`LookupRequest` 為 `final class`（只有 `word`）。`DictionaryStore` 持有 `DatabaseExecutor`，提供 `transaction()` 供 Issue 3 取消匯入時整批回復。主庫仍為 version 28。 |
| 3 JSON/CSV 與 CC-CEDICT 匯入、重複匯入偵測、查詢候選鏈、本機查詢 | done（2026-10-20） | #345 | 三種匯入器（JSON、CSV、CC-CEDICT）各自分批寫入、略過空詞頭；重複匯入以內容偵測並提示；查詢候選鏈（原字串、大小寫、去變音符號、英文詞形還原）第一個命中就停。本機 p95 在門檻內（`dictionary_service_test.dart`）。 |
| 4 查詢面板、`AnnotationToolbar` 按鈕、選字規則、依賴注入 | done（2026-10-20） | #347 | 「查字典」按鈕掛上 `AnnotationToolbar`；選字先去除頭尾標點，片語整串查，CJK 上限 8 字元、內部含標點不查且零請求；查詢面板為分段選擇器，一次顯示一本。FXL 與 CBZ 不出現按鈕。 |
| 5 字典設定畫面 | done（2026-10-20） | #349 | 字典清單、啟用、排序、刪除與匯入入口；來源語言與目標語言必填。刪除連動清除詞條與私有附屬檔。 |
| 6a MDX 匯入、詞條顯示、交叉參照與錨點、返回堆疊 | done（2026-10-21） | #350 | `MdxReader` ＋ vendor 修補的 `dict_reader`；詞條在關閉 JavaScript 的 WebView 顯示，`entry://`／`bword://` 交叉參照與同詞條錨點可用；分段選擇器加返回堆疊。E-Ink 真實 CJK 大檔記憶體與鍵比對延遲已量測。 |
| 6b MDX 圖片、獨立 CSS、深色與 E-Ink 配色 | done（2026-10-22） | #352 | `.mdd` 圖片經 `DictionaryService` 提供、外部 `.css` 依 `<link href>` 檔名內嵌、深色與 E-Ink 配色覆寫。驗收 25 僅部分證實，固定版面與 CBZ 縮放未真機驗證（見 PR 說明）。 |
| 7 線上查詞（萌典）、同意對話框、隱私更新 | done（2026-10-21） | #351 | 預設關閉；第一次開啟前顯示同意對話框，同意狀態存 `onlineConsentAt`；未同意零請求。請求只帶 `word`、僅 `https`、5 秒逾時，結果原文顯示並附固定來源標示。 |
| 8 授權頁、隱私頁、l10n 收尾、整合測試 | 進行中 | | 授權頁補萌典與 CC-CEDICT 資料來源標示、`dict_reader` 修補版註記；PRD 與 `CONTEXT.md` 詞條、ADR 0038／0039、`CLAUDE.md` 字典查詢段落；驗收 1 至 39 逐項盤點與缺口測試。 |

**Issue 3 規劃時要處理（Issue 2 程式審查延後項，見 `reviews/review-code-issue-2.md`）——Issue 3、5 已完成，以下皆已處理：**
- M-7：`insertEntries` 不分批，匯入器要自己每批 2,000 筆。
- M-8：去空白後為空的詞頭會寫入但永遠查不到，匯入器要略過並計數。
- M-9：整個匯入在單一交易內，會擋住同連線的查詢。要決定匯入期間是否允許查詢。
- Issue 5：`listSources()` 遇到未知 `format` 字串會整個失敗（M-2）。

**Issue 6a 第一個任務**：在 E-Ink 上補測真實 CJK 大檔、隨機鍵查詢與含快取的穩態記憶體。（已完成，見 `plans/plan-issue-6a.md` Task 9）

## 1. 已決定的範圍

| 決定 | 內容 |
|---|---|
| 平台 | 只做 Android |
| 入口 | `AnnotationToolbar` 新增「查字典」按鈕，點了開底部面板 |
| 匯入格式 | JSON/CSV、CC-CEDICT、MDX。StarDict 延後 |
| 字典存放 | 獨立的 `dictionary.db`，不動主庫（`version: 28`） |
| 線上查詞 | 預設關閉。預設端點為萌典。第一次使用要同意。只送選取的詞 |
| 自訂網址 | 不做 |
| 方向 | 每本字典標記來源語言與目標語言。依選字內容的字元類型挑字典。使用者可調順序 |
| MDX 顯示 | 在 WebView 顯示，關閉 JavaScript，擋掉所有網路連線 |
| 查詢候選 | 產出有序候選清單（大小寫、Unicode 正規化、英文詞形還原、去變音符號），第一個命中就停 |
| 選字規則 | 按鈕一律顯示。有空白視為片語整串查；CJK 不含標點且最多 8 個字元；超過就提示「選取範圍太長」，不發出任何查詢 |
| MDX 顯示最低要求 | 交叉參照（`entry://`、`bword://`）、同詞條錨點、圖片、獨立 `.css`、深色與 E-Ink 配色 |
| 文件位置 | 調查文件在 `docs/research/dictionary/`；Epic 文件在本目錄（`epic.md`、`spec.md`、`issues.md`） |

決定依據見 `docs/research/dictionary/READEST_ANALYSIS_AND_PROPOSAL.md`。

## 2. 不做的事

- 不內建任何字典資料。
- 不做 StarDict、自訂線上網址、PDF 選字查詢、桌面版。
- 不做 MDX 的 `sound://` 音訊、外開連結範本、外部字典 App 呼叫（列為 Phase 2 候選，見 §11）。
- 不複製 Readest 或任何 AGPL／GPL 專案的程式碼。
- 不改 `main.js`、CFI、閱讀進度、劃線、TTS。
- 不把字典資料放進同步。
- 不送出書名、前後文、閱讀位置。

## 6. 風險與緩解

| 風險 | 影響 | 緩解 |
|---|---|---|
| MDX 套件品質不明 | 無法開啟或查詢錯誤 | Issue 1 先做技術驗證；介面隔離，可換套件 |
| 舊 MDX 用 LZO | 匯入失敗 | Phase 1 不支援 LZO；匯入時偵測並顯示三段式錯誤。使用者回報有需求再開工單，備案是移植 MIT 的 `js-mdict` v6.0.7 |
| 英→繁中免費字典稀少 | 使用者沒有資料可用 | 文件說明；Phase 1 只保證匯入機制 |
| 萌典無服務保證 | 查詢失敗 | 逾時、錯誤分類、不阻塞閱讀 |
| 萌典 ND 授權 | 違規改動詞條 | 原文顯示、固定來源標示、不做簡繁轉換 |
| `cleartext` 允許 | 誤走 `http` | Dart 端只接受 `https`，有單元測試 |
| `win32` 相依鏈 | `pub get` 失敗 | 加套件前先試解析；失敗就退回備案 |
| 面板內的 WebView 在 E-Ink 太慢 | 體驗差 | 真機量測；不通過則 MDX 改顯示純文字（備案） |
| 大 MDX 佔記憶體 | 閃退 | 驗證階段量測；設定檔案大小警告 |
| 匯入凍結 UI | 體驗差 | 解析放進 `Isolate.run()`，寫入留在主 Isolate 分批進行（見 `spec.md` §3.3）；closure 用頂層函式（見 `CLAUDE.md`、`AGENTS.md`） |
| Dart 無 Unicode 正規化 | 分解形式的詞查不到 | Phase 1 不做 NFC／NFD；真機回報後再評估套件與授權（見 `spec.md` §3.4） |
| 真實 MDX 的特殊設定 | 套件打不開或顯示殘留標記 | 兩個實檔都是 `Encrypted=2`；一個有 `StyleSheet`、一個 `StripKey=Yes`。列為 Issue 1 必過項目，缺的功能在 `MdxReader` 補 |
| 沒有 LZO 驗收檔 | 無法用真實字典驗證 LZO | 已決定（2026-10-19）Phase 1 不支援 LZO，只驗證錯誤路徑：用自製的假區塊（壓縮型態標成 LZO）測試，不需要真字典 |
| 選字太長 | 查不到、版面爆掉 | 片語與 CJK 8 字元規則（見 §3.4），超過不發任何查詢 |
| 新資料庫遷移 | 資料遺失 | `dictionary.db` 自有版本；刪除不影響書庫 |
| MDX 真實世界相容性 | 版面壞掉、連結失效 | Readest 一路修了許多 MDX 渲染問題（見 `READEST_ANALYSIS_AND_PROPOSAL.md` §2.7），預期會遇到。用 2 至 3 本真實字典驗收 |
| Android 原生選取控點與面板重疊 | 面板被控點蓋住 | 計畫保留選取以便劃線。真機確認；不行就在面板開啟時隱藏控點 |
| 關閉面板後工具列重新出現 | 體驗差 | Readest 曾因此出錯（#5526、#5585）。加入 widget 測試案例 |
| 詞形還原誤判 | 查到錯的詞 | 只在精確比對全數落空後才用；候選只用於本機字典 |
| 授權污染 | 法律風險 | 不複製 Readest 或任何 AGPL／GPL 程式碼。寫規格與寫程式分開 |

遷移風險：主庫 schema 不變，所以沒有主庫遷移風險。

## 10. 待確認項目

已確認（2026-10-19）：

- 選字規則改採 §3.4（片語整串查、CJK 8 字元上限）。取代原本的 50 字元與縮短重試。
- 英文詞形還原納入 Phase 1。取代原本的「只轉小寫」。
- MDX 最低要求納入 Phase 1，Issue 6 拆成 6a、6b。
- 外開連結與外部字典 App 列入 Phase 2 候選。

仍是預設假設，請確認或修改：

1. **PDF**：Phase 1 不接。PDF 的選字走 `PdfSelectionInfo`，後續另立 Issue。（預設：不做）
2. **線上結果出現時機**：本機有結果時，線上也一起查。（預設：一起查，作為最後一個分段）
3. **詞彙表**：`CONTEXT.md` 尚無字典相關詞條。建議實作時補上「字典來源」「查詢請求」等詞。本次依指示未修改。（已完成（Issue 8）：`CONTEXT.md` 新增「字典查詢」一節）
4. **ADR**：以下兩點符合「難以回復、事後令人意外、有真實取捨」，建議實作時各寫一份 ADR：（已完成（Issue 8）：ADR 0038、0039）
   - 字典資料獨立於主庫（`dictionary.db`）。
   - 線上查詢請求型別不含前後文。
5. **顯示方式**：已確認（2026-10-19，審查 Important 2）：Phase 1 用分段選擇器，一次只顯示一本字典，加返回堆疊。取代原本的「分區」預設。
6. **Epic 編號與順位**：已轉成 Epic（2026-10-19）。編號 `epic-63` 是目前最大編號加一，順位 64 是看板最後一列。若要調整，請告知。
7. **PRD 與詞彙表**：統一在 Issue 8 補 `docs/prd.md` 的 FR 條目與 `CONTEXT.md` 詞條。（已完成（Issue 8）：FR-50～53 與「字典查詢」詞條）
8. **CC-CEDICT 拼音顯示**：已確認（2026-10-19）：聲調符號。
9. **MDX 外部 CSS 的配對方式**：已確認（2026-10-19）：多選匯入，依詞條 `<link href>` 的檔名配對。

## 11. Phase 2 候選

不在 Phase 1 範圍。依優先順序：

1. **StarDict 匯入**：沿用 Readest 證明可行的策略：不轉入資料庫，掃一次 `.idx` 取偏移量，二分搜尋，LRU 快取。多檔依主檔名分組，不完整的組合明確回報。
2. **MDX `sound://` 音訊**：用現有 `just_audio` 播放。先在真機驗證 MIME 與播放時機。
3. **外開連結範本**：範本含 `%WORD%`，僅允許 `https`。結果頁只顯示「在 {名稱} 開啟」卡片，使用者點擊後才用系統瀏覽器開啟。不嵌入、不解析。
4. **外部字典 App 呼叫**：`ACTION_PROCESS_TEXT`，需 `AndroidManifest.xml` 加 `<queries>` 與過濾廠商瀏覽器。
5. **PDF 選字查詢**。
6. 每本字典獨立的瀏覽歷史（目前只有面板層級的返回堆疊）。

明確不做：把前後文送去 AI 服務。若日後要做，必須是另一個請求型別，有獨立的同意流程，不與 `LookupRequest` 共用。
