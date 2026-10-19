# Readest 字典功能分析與提案

分析日期：2026-10-19。對象：[readest/readest](https://github.com/readest/readest)（最後推送 2026-10-18）。

相關文件：`PHASE1_AUDIT.md`、`PHASE1_IMPLEMENTATION_PLAN.md`、`DICTIONARY_FORMATS_AND_LICENSES.md`。

**狀態：已採納（2026-10-19）。** 實作計畫已依本文更新，見 §8。

## 1. 授權警告

- Readest 是 **AGPL-3.0**。
- 它的 MDX 解析器 `packages/js-mdict` 是 Readest 的分支（fork），上游 `terasum/js-mdict` 與分支都是 **AGPL-3.0**。
- 本分析只讀程式碼，取其設計想法。
- **不複製任何程式碼，也不逐行移植。** 實作要自己寫。
- 想法與行為描述不受著作權保護，但具體實作受保護。有疑慮就走乾淨室（clean-room）流程：寫規格的人和寫程式的人分開。

## 2. Readest 怎麼做字典

### 2.1 架構

路徑都在 `apps/readest-app/src/services/dictionaries/`。

| 項目 | 做法 |
|---|---|
| 抽象 | `DictionaryProvider`（`types.ts`）：`id`、`kind`、`label`、`init()`、`lookup(word, ctx)`、`dispose()` |
| 來源種類 | `builtin`、`stardict`、`mdict`、`dict`、`slob`、`bgl`、`plugin`（Yomitan）、`web` |
| 註冊 | `registry.ts`：依使用者設定的順序與啟用旗標，產生 provider 清單。實例以模組層級快取 |
| 顯示 | 每個 provider 一個頁籤。順序由使用者決定 |
| 渲染 | provider **直接寫 DOM**：`lookup()` 把結果寫進 `ctx.container` |
| 手機 UI | 視窗寬度小於 640 用 `DictionarySheet`，否則用 `DictionaryPopup`。兩者共用 `DictionaryResultsView` |
| 設定 | `components/settings/CustomDictionaries.tsx`、`store/customDictionaryStore.ts` |

### 2.2 內建線上來源

- Wiktionary（`wiktionaryProvider.ts`）：打 `en.wiktionary.org` REST。非英文書改用該語言版本。
- Wikipedia（`wikipediaProvider.ts`）。
- 中文（`chineseDict.ts`）：抓 Wiktionary 的 wikitext，用正規表示式取拼音與釋義。**很脆弱**，要手動清 `{{...}}` 模板。
- 上述全部為內建，使用者不用設定。

### 2.3 網頁搜尋範本（`webSearchProvider.ts`、`webSearchTemplates.ts`）

- 範本用 `%WORD%` 當佔位字，代入時做 URL 編碼。
- 內建 Google、Urban Dictionary、Merriam-Webster、Goodreads。**預設全部停用。**
- 使用者可自訂範本。
- **不嵌入 iframe**。原因：這些網站送 `X-Frame-Options: DENY/SAMEORIGIN`。
- 實際做法：顯示一張卡片，上面有「在 {名稱} 開啟」連結。使用者點了才跳到瀏覽器。

### 2.4 本機字典格式

| 格式 | 讀法 |
|---|---|
| StarDict | `stardictReader.ts`：**不轉入資料庫**。掃一次 `.idx` 取每筆起點，存成 `Int32Array`；查詢時二分搜尋；每次只讀需要的小區塊；LRU 快取。`.dict.dz` 逐 chunk 解壓，LRU 約 1 MB |
| MDict | 用 `Blob.slice()` 隨機讀取，初始化只讀標頭與關鍵字索引。加密的 MDX 回報 `unsupported` |
| DICT、Slob、BGL | 各有 reader 與 provider |
| Yomitan | `plugins/`，用 Worker 與 SQLite 衍生索引 |

匯入時產生的邊車檔：`idxOffsets`、`synOffsets`（預先算好的偏移量），讓之後開啟更快。

### 2.5 查詢字串處理（`lookupCandidates.ts`）

依序嘗試，第一個有結果就停：

1. 原字串、小寫、首字大寫、全大寫。
2. 以上每種的 NFC 與 NFD 形式。
3. 詞形還原候選（`lemmatize/english.ts`）。
4. 去掉拉丁字母變音符號後再重複一次。

重點設計：**寧可多產生候選，讓字典自己判斷。** 錯誤的詞幹只是查不到，換下一個。詞形還原在 `lemmatize/index.ts` 以語言註冊。沒登錄的語言回傳空陣列，**不會硬套英文規則到中文或法文。**

### 2.6 選字入口（`isSingleLookupTerm`，`src/utils/word.ts`）

- 有空白就視為多詞，拒絕。
- 非 CJK 的單一詞：接受。
- CJK：不含標點與符號，且最多 8 個字元才接受。
- 理由：中文沒有空白，無法用詞數判斷。`Intl.Segmenter` 會把成語拆開，所以改用長度上限。
- 不符合就退回一般標註工具列，讓使用者仍可劃線或複製。

### 2.7 MDX 顯示的坑（來自它們的問題單）

Readest 的 `.claude/memory/` 記錄了許多實際遇到的問題：

| 問題 | 教訓 |
|---|---|
| 圖片：MDX 的 `<img src>` 要從 `.mdd` 取位元組 | 需要解析資源並轉成 blob URL |
| 圖片重複：牛津 9 每張圖放兩份，縮圖與隱藏的大圖，靠 `onclick` 切換 | 關掉 JS 後只看到縮圖 |
| `sound://` 連結：要從 `.mdd` 取音訊播放 | iOS 要有 MIME 型別，且要在使用者手勢內啟動播放 |
| `entry://word`、`bword://word`：詞條間交叉參照 | 要攔截並重新查詢 |
| `entry://#anchor`：同一詞條內跳轉（牛津的詞性切換） | 被誤當成詞條名稱查詢，標題顯示成一串雜湊 |
| 樣式：詞條自帶 CSS，還有隨 `.mdx` 匯入的獨立 `.css` | 用 shadow root 隔離樣式 |
| 深色模式：詞條 CSS 寫死文字顏色 | 要有 `liftDarkTextColors` 之類的覆寫 |
| E-Ink：按鈕出現黑塊 | 要有專屬樣式（`eink-inverted`） |

### 2.8 匯入的坑

- Android 的 `content://` 路徑有時沒有副檔名（例如 `…/document/msf%3A20`）。
- 用字串解析檔名會得到沒有副檔名的字串，導致 StarDict 三個檔案被判成「不完整」。
- 解法：用內容解析器取得真實檔名（`DISPLAY_NAME`），只解析一次，重複使用。
- 多檔格式（StarDict）依「主檔名」分組，不完整的組合會回報跳過。
- 每本字典算 `contentId` = 部分 MD5 + 檔案大小 + 排序後檔名。用來辨識重複匯入與跨裝置同步。

### 2.9 其他功能

- **系統字典**（`systemDictionary.ts`、Android 原生 `show_lookup_popover`）：用 `ACTION_PROCESS_TEXT` 呼叫已安裝的字典 App（欧路、GoldenDict）。
  - 要在 manifest 宣告 `<queries>`，否則 Android 11 以上看不到其他 App。
  - 部分廠商的瀏覽器會攔截此意圖，所以要過濾瀏覽器。
  - 記住使用者選的 App。
- **AI 語境字典**（`contextDictionary.ts`）：預設關閉。會把選字前後段落（每側最多 1,000 字元）送到使用者設定的 OpenAI 相容服務。
- **同步**：字典設定與（付費）字典檔案可跨裝置同步。曾有錯誤：設定頁的「字典」開關沒有真正管到字典偏好（#5465）。
- **快速動作**：選字後自動查詢，並取消選取，避免 iOS 原生選取控點畫在視窗上方。

## 3. 與我們現有計畫的比較

| 面向 | Readest | 我們的計畫 | 評語 |
|---|---|---|---|
| Provider 輸出 | 直接寫 DOM | 回傳資料（`ProviderOutcome`），UI 另外渲染 | **我們較好**：好測、不綁 UI |
| 本機儲存 | 全部原地讀取，不轉資料庫 | JSON/CSV 轉 SQLite；MDX 原地讀 | 合理，因為 JSON/CSV 不是它們支援的格式 |
| 顯示方式 | 每本字典一個頁籤 | 單一面板，分區 | 見 §4.5 |
| 詞形處理 | 候選鏈 + 詞形還原 | 只轉小寫 | **建議升級**，見 §4.1 |
| 選字限制 | 8 字元（CJK），有空白即拒絕 | 50 字元 | 見 §4.2 |
| 自訂網址 | `%WORD%` 範本，點擊後外開 | 延後 | 見 §4.3 |
| 外部字典 App | `ACTION_PROCESS_TEXT` | 沒有 | 見 §4.4 |
| 隱私 | 預設只送詞；AI 字典會送前後文 | `LookupRequest` 只有詞 | 我們較嚴，維持 |
| 授權 | AGPL | 需乾淨室 | 見 §1 |
| MDX 資源 | 圖片、音訊、CSS、交叉參照皆處理 | 圖片等「找得到就顯示」 | 見 §4.6 |
| 重複匯入 | `contentId` 辨識 | 沒有 | 見 §4.7 |

## 4. 提案

每項標明建議等級與對計畫的影響。

### 4.1 詞形候選鏈（建議納入 Phase 1，優先級：高）

做法：`lookup_text_normalizer` 產出**有序候選清單**，而不是單一字串。

```
原字串 -> 小寫 -> 首字大寫 -> 全大寫
       -> Unicode 正規化變體
       -> 語言別詞形還原（英文）
       -> 去變音符號
```

- 第一個命中就停。
- 英文詞形還原做成「語言登錄表」，只登錄英文。中文不登錄，不套用英文規則。
- 規則寧可多產生，字典負責驗證。
- 成本：純 Dart、無依賴、可完整單元測試。
- 為什麼：沒有它，`ran`、`mice`、`children` 在只存原形的字典（多數 MDX）查不到。
- 影響計畫：取代 §10 第 3 項「英文只轉小寫」，並擴充 `lookup_text_normalizer.dart`。

### 4.2 選字長度規則（建議採用，優先級：中）

- 按鈕**一律顯示**（我們的入口是明確點擊，不像 Readest 的自動查詢，不需要為了避開劃線而隱藏）。
- 但查詢內容套用規則：
  - 有空白：視為片語，**整串查一次**，不縮短。
  - CJK 且不含標點：長度上限 8 個字元。
  - 超過上限：面板顯示「選取範圍太長，請縮短後再查」，不發出任何查詢（含線上）。
- 取代計畫 §10 第 1 項（50 字元）與第 2 項（縮短重試最多 3 次）。
- 理由：8 字元上限有 Readest 的實測依據。縮短重試的行為難以預期，也增加線上請求次數。

### 4.3 自訂網址：外開連結版（建議列為 Phase 2，優先級：中）

我們在 Q8 決定先不做自訂網址。Readest 的做法提供一個**低風險版本**：

- 範本含 `%WORD%`，**僅允許 `https`**。
- 結果頁只顯示一張卡片：「在 {名稱} 開啟」。
- 使用者點擊後才用系統瀏覽器開啟。
- 不嵌入 WebView、不解析內容、不自動送出任何請求。

隱私上更乾淨：詞只在使用者主動點擊時離開 App。不需要同意對話框以外的額外機制，但仍需在設定畫面說明。

注意：Readest 的驗證函式 `isValidUrlTemplate` 接受 `http`。我們必須拒絕，因為 manifest 有 `usesCleartextTraffic="true"`。

### 4.4 外部字典 App 呼叫（建議列為 Phase 2，優先級：中）

- 用 `ACTION_PROCESS_TEXT` 把詞交給使用者已安裝的字典 App（欧路、GoldenDict 等）。
- 對 E-Ink 閱讀器使用者很有用：很多人已安裝這些 App 與自己的字典。
- 需要：
  - `AndroidManifest.xml` 加 `<queries>`（Android 11 以上才看得到其他 App）。
  - 原生端用 `MethodChannel`（`MainActivity.kt` 已有現成模式）。
  - 過濾瀏覽器，避免廠商瀏覽器攔截。
- 隱私：詞只送給本機另一個 App，不經網路。
- 風險：各家廠商行為不同，需多機種實測。

### 4.5 顯示方式：分區 vs 頁籤（待決定，優先級：低）

Readest 用頁籤，每本字典一個，並維護每個頁籤的歷史（返回上一詞）。

- 我們的計畫是單一面板分區。
- E-Ink 上頁籤能減少捲動，但切換頁籤要重繪。
- 建議：Phase 1 先用分區，只做一個簡單的**返回堆疊**（用於 `entry://` 交叉參照）。頁籤留到真機試用後再決定。

### 4.6 MDX 詞條顯示的最低要求（建議調整 Phase 1 範圍，優先級：高）

計畫原本把 `.mdd` 資源列為「找得到就顯示」。Readest 的問題單顯示，真實的 MDX 至少需要：

| 項目 | Phase 1 | 做法 |
|---|---|---|
| 詞條間交叉參照 `entry://`、`bword://` | 做 | 在 `shouldOverrideUrlLoading` 攔截，重新查詢，加入返回堆疊 |
| 同詞條錨點 `#anchor`、`entry://#anchor` | 做 | WebView 原生支援 `#anchor`；`entry://#…` 轉成錨點 |
| 圖片 | 做 | 在 `shouldInterceptRequest` 從 `.mdd` 回傳資源，不需要 JavaScript |
| 隨 MDX 匯入的獨立 `.css` | 做 | 匯入時一併複製，載入時注入 |
| 深色與 E-Ink 配色 | 做 | 覆寫寫死的文字與背景顏色，驗收條件加入 |
| `sound://` 音訊 | Phase 2 | 用現有 `just_audio` 播放；先在真機驗證 MIME 與播放時機 |
| 加密 MDX | 不支援 | 匯入時明確報錯 |

JavaScript 維持關閉。取捨：牛津 9 這類字典的圖片放大靠 `onclick` 切換，關 JS 後只看得到縮圖。這是可接受的限制，在文件註明。

影響計畫：§3.6、§9 驗收標準新增項目；Issue 6 的範圍擴大，建議拆成「6a：交叉參照與錨點」「6b：圖片與 CSS」。

### 4.7 重複匯入偵測（建議納入 Phase 1，優先級：低）

- 匯入時算 `contentId` = 檔案前後各一段位元組的雜湊 + 檔案大小 + 檔名。
- `crypto` 套件已在依賴內。
- 同一個 `contentId` 已存在時，提示「這本字典已匯入」，讓使用者選擇略過或取代。
- 不用於同步（我們不同步字典）。

### 4.8 StarDict 的設計預留（Phase 2 時採用，優先級：低）

- Readest 證明 StarDict 可以**不進資料庫**，用偏移量陣列二分搜尋，記憶體很小（10 萬筆約 420 KB）。
- 我們 Phase 2 做 StarDict 時，沿用同一策略，不必轉入 SQLite。
- 多檔匯入要依「主檔名」分組。`file_picker` 回傳的 `PlatformFile.name` 是真實檔名，要用它而不是路徑字串。
- 不完整的組合要明確回報，不要靜默略過。
- `.dict.dz` 是可隨機讀取的 gzip，需要自己解析 chunk 表。`archive` 套件是否夠用，實作前驗證。

### 4.9 AI 語境查詢（不建議，除非獨立設計）

- Readest 預設關閉，並把前後段落送出。
- 與我們「不得未經明確許可送出書籍內容」相衝突。
- 如果日後要做，必須是**另一個請求型別**（例如 `ContextLookupRequest`），有**獨立的同意流程**，不與 `LookupRequest` 共用。這樣「`LookupRequest` 沒有前後文」的型別保證才能維持。
- Phase 1 不做。

### 4.10 不採用的項目

| 項目 | 原因 |
|---|---|
| Wiktionary 內建 | 英→英，不是我們的三個方向。中文部分靠脆弱的 wikitext 抓取 |
| Yomitan | 日文為主 |
| Slob、BGL、DICT | 使用者需求不明。等 StarDict 之後再評估 |
| 字典檔跨裝置同步 | 體積大、版權風險。維持不同步 |
| 自動查詢（快速動作） | 與劃線手勢衝突。我們用明確按鈕 |

## 5. 對現有計畫的修改清單

僅供確認，**尚未修改**。

1. **§3.4 流程**：正規化改為「產出有序候選清單」。
2. **§10 第 1、2、3 項**：以 §4.1、§4.2 取代。
3. **Issue 3**：新增候選鏈與英文詞形還原。
4. **Issue 6**：拆為 6a（交叉參照、錨點）與 6b（圖片、CSS、配色）。
5. **§9 驗收標準**新增：
   - 交叉參照可點、可返回。
   - MDX 圖片在無 JavaScript 下顯示。
   - MDX 詞條在深色與 E-Ink 模式下文字可讀。
   - `ran` 能查到 `run`（英文詞形還原）。
   - 重複匯入同一檔案時提示。
6. **Phase 2 候選**：外開連結、外部字典 App、`sound://` 音訊、StarDict。
7. **§6 風險表**新增：
   - 「MDX 真實世界相容性」：Readest 一路修了許多 MDX 渲染問題，預期我們也會遇到。
   - 「Android 原生選取控點與面板重疊」：Readest 在選字後取消選取來避免。我們計畫保留選取以便劃線，需真機確認。
   - 「關閉面板後工具列重新出現」：Readest 曾因此出錯（#5526、#5585），加入測試案例。

## 6. MDX 解析器選擇的新證據

這次順便查到 `mdict_flutter` 與 `dict_reader` 的維護狀況（GitHub API）：

| 項目 | `mdict_flutter` | `dict_reader` |
|---|---|---|
| 授權 | BSD-3-Clause | MIT |
| 最後推送 | 2025-11-18（距今約 11 個月無更新） | 2026-09-24（近一個月內） |
| 倉庫大小 | 15 KB（極小） | 未查 |

- `mdict_flutter` 自稱復刻 `mdict-cpp`。GitHub 上的 `dictlab/mdict-cpp` 授權為 BSD-3-Clause，**血統看起來乾淨**。但我沒有確認 `mdict_flutter` 作者參考的就是這個倉庫。仍列為待查證。
- 同類型的 JS 解析器 `js-mdict`（Readest 所用）是 AGPL。這提醒我們：MDX 解析器常見傳染性授權，引入前務必讀 LICENSE 與相依套件。
- 維護狀況偏向 `dict_reader`。技術驗證（Issue 1）仍照原計畫做。

## 7. 需要你決定

1. **§4.1 詞形候選鏈與英文詞形還原**納入 Phase 1？（我建議：是）
2. **§4.2 選字規則**採 Readest 式（空白即片語、CJK 8 字元上限）取代原本的 50 字元與縮短重試？（我建議：是）
3. **§4.6 MDX 最低要求**（交叉參照、圖片、CSS、配色）納入 Phase 1，Issue 6 拆成兩張？（我建議：是）
4. **§4.3 外開連結**與 **§4.4 外部字典 App** 列入 Phase 2 候選？（我建議：是）
## 8. 結果

2026-10-19：以上 4 題都採納建議。`docs/dictionary/PHASE1_IMPLEMENTATION_PLAN.md` 已依 §5 更新，§6 的證據已補進 `DICTIONARY_FORMATS_AND_LICENSES.md`。
