# `epic-63-dictionary-lookup` 字典查詢（離線匯入＋可選線上查詞）

**狀態：** 🟡 開發中 (Active)（Discovery／Architecting／Scrum Master 已完成，尚未開始實作）
**存放路徑：** `docs/epics/epic-63-dictionary-lookup/`
**關聯文件：** `spec.md`、`issues.md`
**調查文件：** `docs/research/dictionary/PHASE1_AUDIT.md`、`DICTIONARY_FORMATS_AND_LICENSES.md`、`READEST_ANALYSIS_AND_PROPOSAL.md`
**關聯 PRD 章節：** 尚無字典需求。`docs/prd.md` 的 FR 條目與 `CONTEXT.md` 詞條在 Issue 8 補上

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
| MDX 解析器 | 未選定。Issue 1 用真實字典驗證 `dict_reader` 與 `mdict_flutter`。**不用 `readest/js-mdict`**（v7 起 AGPL-3.0），2026-10-19 決定；備案見 `DICTIONARY_FORMATS_AND_LICENSES.md` |
| CC-CEDICT | Phase 1 新增 `CedictImporter`（它不是 JSON、CSV 或 MDX）；不內建、不散布，使用者自行下載。拼音顯示轉成聲調符號（`pīnyīn`），資料庫存原文；注音留待後續 |
| MDX 外部 CSS | 匯入時可多選 `.mdx`、`.mdd`、`.css`；CSS 依詞條 `<link href>` 的檔名配對；缺檔仍可讀並提醒，可事後補匯入 |
| 驗收用字典 | `tmp/dictionary/` 下的教育部 MDX、簡明古漢語 MDX、CC-CEDICT；只作本機測試，不進版控、不放 fixtures |


---

以下章節沿用調查階段的編號（見 `spec.md` 開頭說明）。

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
| 舊 MDX 用 LZO | 匯入失敗 | 匯入時偵測並顯示明確訊息；驗證階段決定是否自寫 |
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
| 沒有 LZO 驗收檔 | 無法驗證 LZO 支援 | 需人類另外提供一本 LZO 壓縮的 MDX |
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
3. **詞彙表**：`CONTEXT.md` 尚無字典相關詞條。建議實作時補上「字典來源」「查詢請求」等詞。本次依指示未修改。
4. **ADR**：以下兩點符合「難以回復、事後令人意外、有真實取捨」，建議實作時各寫一份 ADR：
   - 字典資料獨立於主庫（`dictionary.db`）。
   - 線上查詢請求型別不含前後文。
5. **顯示方式**：已確認（2026-10-19，審查 Important 2）：Phase 1 用分段選擇器，一次只顯示一本字典，加返回堆疊。取代原本的「分區」預設。
6. **Epic 編號與順位**：已轉成 Epic（2026-10-19）。編號 `epic-63` 是目前最大編號加一，順位 64 是看板最後一列。若要調整，請告知。
7. **PRD 與詞彙表**：統一在 Issue 8 補 `docs/prd.md` 的 FR 條目與 `CONTEXT.md` 詞條。
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
