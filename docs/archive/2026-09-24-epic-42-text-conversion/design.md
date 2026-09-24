# Epic 42 — 簡繁轉換（FR-48）：Discovery

## 緣起與範圍界定

`docs/prd.md` FR-48 已定義基本需求：閱讀 ePub3、KF8 (AZW3)、TXT、Markdown (MD) 時，提供「原文／轉換為繁體／轉換為簡體」三態顯示切換，支援雙向轉換；**純顯示層轉換，不修改原始檔案內容**；可於系統設定提供全域預設，個別書籍可覆寫（比照 FR-10／FR-37／FR-38 全域預設＋單書覆寫雙層模式）。**CBZ（純圖像格式）、PDF（非可重排文字渲染架構）不適用**。PRD 同時明確排除與本 Epic 無關的兩件事：

- 與 TXT 匯入既有之**編碼偵測**（FR-12，Big5／GBK 等位元組→文字解碼）為不同層級的獨立功能——編碼偵測是「把位元組正確解碼成文字」，本 Epic 是「文字解碼完成後，才進一步做的字元對照顯示轉換」，互不影響。
- 與**多語系介面**（FR-49，App 自身介面文字語言切換）是明確區分的兩個不同概念，可任意組合，互不影響，本 Epic 不涉及介面字串翻譯。

PRD 原文亦記載「簡繁轉換（FR-48）之技術架構：尚無研究報告⋯留待該功能啟動 Discovery／Architecting 階段決定」。`docs/epics.md` 原僅列為後續擴展的一句話備註，本次 2026-09-14／2026-09-15 透過 `/grill-with-docs` 完整定案範圍、技術路線與各畫面互動邊界。

## 現有程式碼現況

- **從零開始，無既有程式碼可沿用**：全庫檢索 `OpenCC|簡體|簡轉繁|繁轉簡` 等關鍵字，程式碼庫（`app/` 底下）沒有任何既有簡繁轉換機制。
- **全域預設＋單書覆寫已有成熟先例可直接沿用**：`GlobalReaderPrefs`（`shared_preferences`）＋ `book_reader_prefs`（SQLite，與 `books` 表 1:1）雙層解析模式已用於排版方向覆寫、螢幕方向覆寫、翻頁模式覆寫等多個既有欄位，本 Epic 的三態切換值可直接比照新增欄位，不需要新的資料模型。
- **`book_reader_prefs`／`BookReaderPrefs` 完全沒有被 `app/lib/sync/` 引用**——確認這類單書版面設定本來就不在 `epic-8-sync` 的同步範圍內（只有閱讀進度／劃線／備註／書籤四個 collection 會同步）。本 Epic 的偏好設定沿用同一慣例，不進入同步範圍。
- **`BookTocItem.title`（`app/lib/reader/book_toc_item.dart:13-23`）是純 Dart `String`**，目錄面板透過 Flutter widget 渲染，不在 WebView DOM 裡——代表「WebView 顯示層轉換」這個技術路線不會自動涵蓋目錄／書籤／劃線備註清單／搜尋結果等 Flutter 端渲染的文字，需要額外一條 Dart 端純字串轉換路徑（見下方第 8 點）。
- **`readest/foliate-js` 的 vendoring 慣例已有明確先例**：釘定 commit、直接複製檔案進版控（`app/android/app/src/main/assets/foliate/`），不引入 Node.js/npm 建置工具鏈。任何新的 JS 依賴都必須比照這個模式。

## 本次落地範圍

### 1. 轉換範圍與精細度

- 三態顯示切換：原文／轉換為繁體／轉換為簡體，雙向。
- 轉換精細度採**字元對字元 1:1 轉換**（等同 OpenCC `s2t`/`t2s` 等級），不做詞彙/片語＋兩岸慣用詞感知等級（`s2twp`/`tw2sp`）的轉換。**這是審查修訂（見 `reviews/review-epic-and-design.md` C-2）後的定案，推翻本輪 Discovery 原先確認的 Q1 決定**：詞彙級轉換必然產生非等長字元變化（例如「字节」2字→「位元組」3字），會讓 WebView live DOM 文字節點長度改變，進而讓 `epubcfi.js` 的 Range/Selection offset 計算在轉換前後的 DOM 之間失真，導致劃線/書籤位移或觸發 `IndexSizeError` 而靜默消失（詳見下方「技術架構」與 ADR 待辦）。1:1 字元轉換下每個字元恆定替換為一個字元，ΔL 永遠為 0，從結構上排除這個風險，以犧牲兩岸慣用詞轉換品質換取零風險。
- 標點符號風格（“”／「」）**不**隨此轉換連動，維持原書排版風格——標點是版面/排版設計的一部分，跟文字是簡體字/繁體字並非绑定關係（例如繁體字書也可能刻意用西式引號）。**審查提醒（M-1）**：第 4 點改用 OpenCC 最底層的純字元對照表（`STCharacters.txt`／`TSCharacters.txt`）作為唯一資料來源，而非套件包裝好的詞彙/慣用詞 bundle，Architecting 階段仍須確認這份原始字元表本身不含引號等標點字元的替換條目，避免間接違反本條。

### 2. 技術架構：執行位置與相容性策略

**採 WebView JS 顯示層轉換，而非 Dart 端預轉換。** 理由：Dart 端預轉換需要在餵給 WebView 之前整份改寫 spine/section 的 HTML 文字內容，若轉換後文字的字元數改變，會讓「渲染出來的 DOM」跟「CFI 定位所依據的原始內容」產生落差，導致既有劃線/書籤在切換簡繁時位移或跳轉錯誤。

**核心架構限制（不可違反）**：CFI 的生成與解析永遠只對「原文」DOM 運作，從不感知目前顯示模式；轉換只發生在「畫面上看到什麼字」這一層，不牽動任何定位邏輯。**這個限制之所以能夠成立，前提是第 1 點定案的「1:1 字元轉換」**——`epubcfi.js` 的 `fromRange`/`toRange`（`app/android/app/src/main/assets/foliate/epubcfi.js:302-334`）直接依賴 live DOM 當下的 Range/Selection offset，只有在每個文字節點轉換前後長度恆等（ΔL=0）時，同一個 offset 在「轉換後畫面」與「原文 DOM」之間才會指向同一個字元位置；若採詞彙級轉換（非等長），這個限制在數學上不可能成立（審查 C-2 已用具體案例證明），這正是本輪推翻 Q1、退回 1:1 字元轉換的直接原因。這樣劃線/書籤/搜尋跳轉在任何顯示模式下都精確，且切換模式不需要重新計算「Location 刻度」等既有估計值（其計算基礎——spine 檔案未壓縮位元組數——不受顯示層轉換影響）。

DOM 走訪策略**不依賴任何第三方套件內建的語系標籤（`lang`/`xml:lang`）匹配機制**（審查 I-3：許多 EPUB 未標註或使用非標準語系屬性，依賴 `lang` 匹配會導致整本書不被轉換）——改為自行實作一個無條件走訪可見文字節點、逐字元查表替換的 DOM Walker（排除 `<rt>`/`<script>`/`<style>` 等標籤），比照 `main.js` 既有 `extractSegmentsForSection` 的 `TreeWalker` 寫法。具體實作細節（走訪範圍的標籤排除清單、與既有 CSS 注入時機的整合點）留待 Architecting 階段定案，但「逐字元查表、不做任何多字元 pattern 比對」是本輪 Discovery 直接拍板的限制，確保 ΔL 恆為 0 這件事不會因實作疏忽而被打破。

### 3. 轉換時機：逐 section Lazy 轉換

切換顯示模式時，比照既有渲染管線（`paginator.js` 逐 section 渲染、TTS 逐段即時建立朗讀段）採 lazy 策略：只在使用者實際翻到/捲動到某個 section 時才轉換該段內容，不在切換當下把整本書一次全部轉換完，避免大書切換模式時卡頓。

### 4. 函式庫選型（審查修正：不再 vendor `opencc-js`，改用純字元對照表＋雙端各自輕量實作）

**審查 C-1 指出的問題**：`app/pubspec.yaml` 只有 `flutter_inappwebview`，專案沒有任何 headless JS 引擎，Dart AOT 執行環境無法直接呼叫 JS 函式庫；書架（`LibraryScreen`）、全庫搜尋等畫面底層完全沒有 WebView 實例，原案「Dart 端也呼叫 `opencc-js`」在架構上不成立。**加上第 1 點退回 1:1 字元轉換後，也不再需要 `opencc-js` 的詞彙/慣用詞字典與 `HTMLConverter`**，函式庫需求大幅簡化：

- **唯一資料來源**：OpenCC 專案最底層的字元對照表（`STCharacters.txt`／`TSCharacters.txt`，純簡繁字元一對一映射，Apache-2.0 授權，寬鬆授權可直接 vendor），JS 端與 Dart 端**共用同一份資料來源**產生各自的查找表，確保兩端轉換結果一致（不會出現「內文轉換結果」與「目錄/書架轉換結果」因字典不同而不一致的情況）。
- **JS 端**（WebView 內文轉換）：以該字元表產生一份輕量 JS 查找模組（純物件字面量／`Map`，不含 `opencc-js` 其餘詞彙/慣用詞/`HTMLConverter` 邏輯），比照 `foliate-js` 釘定 commit＋複製進版控慣例。體積遠小於原案規劃的 `s2twp`/`tw2sp` 子集 bundle，審查 I-4 的低階裝置 JS Heap 疑慮因此大幅緩解。
- **Dart 端**（目錄/書架/搜尋/書籤等純 Dart 渲染文字，見第 8 點）：以**同一份**字元對照表產生對應的純 Dart 字典（`Map<String, String>`，編譯進程式碼或 asset），同步執行、零 IPC、零 WebView 依賴，解決 C-1。字元級表遠小於詞彙級（估計數十 KB 等級），可直接嵌入 Widget `build()` 與 Repository 映射層。
- 兩端各自的 DOM Walker／字串走訪邏輯皆不依賴任何第三方套件的語系標籤匹配機制（見第 2 點，規避審查 I-3）。
- 資料來源具體版本釘定、雙端查找表的產生方式（是否用同一支腳本從原始字元表生成兩份格式）、放置路徑，留待 Architecting 階段定案。

### 5. 資料儲存與同步範圍

`GlobalReaderPrefs` 與 `book_reader_prefs` 各新增一個欄位（三態 enum：原文/轉繁/轉簡），不新增資料表——語意與既有「排版方向覆寫」「螢幕方向覆寫」等欄位完全同構。**不同步到雲端**，比照 `book_reader_prefs` 既有慣例（現有版面偏好設定本來就不在 `epic-8-sync` 同步範圍內）。

### 6. UI 入口

雙入口，比照「全域預設值」既有標準模式：

- 系統設定「閱讀」分區（全域預設，比照 `ReadingDefaultsScreen` 既有集中呈現模式）。
- 各格式版面設定 Bottom Sheet（單書覆寫）。

CBZ／PDF 的版面設定畫面**完全不顯示**此控制項，比照「雙頁模式」「欄數」等既有「格式不適用就不佔版面」模式，不發明「顯示但停用」的新樣式。

### 7. 匯入時行為

匯入時**不**自動偵測書籍原文是簡體或繁體、不給預設建議，一律預設「原文」，轉換完全被動、由使用者手動切換。理由：(a) FR-48 原文未涵蓋這個範圍；(b) 自動偵測簡繁本身有誤判風險（混合內容、專有名詞），錯誤的預設建議造成的困惑可能大於幫助；(c) 這是可以獨立於本輪之後再迭代加上的功能，第一版先求簡單正確（YAGNI）。

### 8. 各畫面轉換規則：情境分流

第 2 點的 WebView 顯示層轉換架構不會自動涵蓋 Flutter 端直接渲染的文字（目錄面板、書籤清單、劃線/備註清單、全庫搜尋結果片段、書架書名/作者），需要額外呼叫第 4 點的 Dart 端純字典轉換函式（與 JS 端共用同一份字元對照表來源，結果一致）。依「情境」分兩類處理：

- **單書情境**（目錄面板、書籤清單章節名稱、劃線清單的書本原文摘要片段——皆在 `ReaderScreen` 內針對「目前這本書」開啟）：跟隨該書目前生效的顯示模式（全域預設＋單書覆寫解析後的結果），與內文一致。
- **跨書情境**（書架書名/作者、全庫搜尋結果片段——橫跨整個圖書庫，沒有「目前這本書」的語境）：只跟隨「全域預設值」，不做單書覆寫。沒設定全域預設（維持「原文」）時則不轉換。

### 9. 使用者自建內容排除於轉換範圍外

「備註（Note）」是使用者自己輸入的自由文字內容，不是書本原文——簡繁轉換**永遠不套用**在備註文字本身，維持使用者輸入原樣（使用者可能就是刻意用簡體打的筆記，不代表看繁體書就要被連帶改筆記）。劃線清單顯示的「摘要文字」則是從書本原文擷取的片段，屬於書本內文範疇，比照第 8 點「單書情境」規則轉換。清單畫面上兩者混合顯示時，只轉換摘要片段那一半。

### 10. Markdown 匯出行為

匯出的 Markdown 檔案（劃線/備註/書籤清單）**永遠匯出原文**，不受匯出當下畫面顯示模式影響——匯出的 Markdown 是一份「資料」而非「畫面顯示」，理應忠於書本原文，避免使用者事後查閱匯出檔案時因為匯出當下剛好切換了哪個顯示模式而內容不一致。使用者自己輸入的備註文字本來就維持原樣（同第 9 點）。**審查澄清（M-2）**：這件事不需要匯出流程額外做「反向轉碼」——`highlights`/`notes`/`bookmarks` 資料表儲存的摘要片段欄位本來就恆為原文（顯示層轉換只發生在畫面渲染當下，從不寫回資料庫），匯出服務只要直接讀 DB 欄位即自然保證原文，不是一個需要實作的轉換步驟。

### 11. 與既有功能的互動邊界

- **全文檢索（FTS5）——審查修正（I-1）**：索引維持「原文單套索引」不變（不佔用額外儲存空間，也不需要維護雙套索引）。但原案「搜尋比對永遠針對原文、切換顯示模式後用畫面上的字搜尋可能 0 筆結果」會被使用者當成 Bug——修正為在 `SearchRepository` **查詢端做 Query Expansion**：使用者輸入的查詢字串先依第 4 點的字元對照表轉換回原文字形，再送進 FTS5 `MATCH`；搜尋結果回傳的內容匹配摘要片段（`ContentMatchSnippet`）則依目前顯示模式轉換後呈現，保持搜尋結果列表與閱讀畫面字形一致。書名/作者半段的搜尋（不經 FTS5，直接查 `books` 表）比照同一邏輯做查詢端轉換。
- **TTS 朗讀——審查修正（I-2）**：`main.js` 的 `extractSegmentsForSection`／`createDocument()` 是重新解析章節原始內容產生的獨立 DOM（**不是**目前畫面上已轉換顯示的 live paginator DOM），用它算出來的 `segments[].text` 因此必然是原文——「朗讀文字採目前畫面顯示的變體」不是自動繼承畫面顯示狀態，而是需要對 `extractSegmentsForSection` 回傳的 `text`（在傳回 Dart 端前，或 Dart 端接收後）**額外做一次第 4 點的字元轉換**供語音合成器朗讀；`cfi` 欄位與 `showTtsHighlight` 傳入的定位錨點維持對應原文 `createDocument()` DOM，不受轉換影響，確保朗讀同步高亮的定位精確度不因顯示模式而改變。

## 明確排除於本 Epic 之外

- **CBZ、PDF**：不適用（CBZ 純圖像無文字層；PDF 非可重排文字渲染架構），已於 PRD 定案。
- **標點符號風格轉換**：不隨簡繁轉換連動，維持原書排版。
- **使用者備註文字轉換**：永遠排除，維持使用者輸入原樣。
- **匯入時自動偵測簡繁並給預設建議**：不做，一律預設「原文」。
- **跨裝置同步此偏好設定**：不做，比照 `book_reader_prefs` 既有慣例。
- **全文檢索索引隨顯示模式切換**：不做，索引永遠針對原文。
- **App 介面文字語言切換（FR-49 多語系介面）**：是明確區分的不同功能，不在本 Epic 範圍。

## 待 Architecting 階段確認的技術風險

（2026-09-15 依 [`reviews/review-epic-and-design.md`](./reviews/review-epic-and-design.md) 審查修訂——原案的「CFI-safe DOM 轉換策略」與「vendor `opencc-js`」兩項風險已隨第 1/2/4 點的架構修正而結構性解決或大幅簡化，以下是修訂後仍待 Architecting 確認的項目）：

- **1:1 字元轉換的 DOM Walker 實作仍需以既有劃線/書籤測試案例驗證**：雖然 ΔL=0 已從數學上排除 CFI 偏移風險，但實作本身（逐字元查表替換、`<rt>`/`<script>`/`<style>` 排除清單是否完整）仍須在 Architecting 階段以既有劃線/書籤測試案例驗證切換顯示模式前後定位不受影響，避免實作疏漏造成非預期的 ΔL≠0。
- **`STCharacters.txt`／`TSCharacters.txt` 的版本釘定與雙端查找表產生方式**：釘定哪個版本/commit、JS 端與 Dart 端查找表的具體產生流程（例如是否用同一支腳本從原始字元表生成兩份格式，確保兩端資料同源不漂移）、放置路徑，並依 M-1 確認原始字元表不含標點字元替換條目。
- **`GlobalReaderPrefs`／`book_reader_prefs` 新欄位的具體命名與型別**、既有書籍升級後的欄位預設值遷移方式。
- **`SearchRepository` Query Expansion 與 TTS 分段轉換的具體介面**（I-1／I-2）：查詢字串轉換的呼叫點、`extractSegmentsForSection` 回傳 `text` 的轉換時機（JS 端回傳前 or Dart 端接收後）。
- **前置阻塞項（I-4，與本 Epic 決策無關的既有 bug，但會擋到本 Epic 的 Architecting 工作）**：`app/tool/check_foliate_es_compat.js` 的 `extractPolyfillSource()` 仍寫死抓取 `foliate_reader_view.dart` 裡的 `_esCompatPolyfillJs`，但該常數已搬到 `foliate_native_bridge.dart:219` 且改名為 `esCompatPolyfillJs`（無底線前綴），腳本執行必定拋例外。Architecting 階段一旦要修改 `main.js`／`foliate_native_bridge.dart`（本 Epic 必然會動到），必須先修好這支守門腳本的引用路徑，否則新增的 vendor 檔案不會被 ES 相容性檢查涵蓋到。
- **低階 E-Ink 裝置 JS Heap 水位**：改用字元級查找表後記憶體疑慮已大幅緩解，但 Architecting 階段仍應在低階裝置（2GB/3GB RAM）上實測記憶體水位，確認無明顯 GC 頓挫。
- 本 Epic 的兩項架構決策——「WebView 顯示層 1:1 字元轉換、CFI 永遠對原文運作」與「vendor OpenCC 原始字元表、雙端各自輕量實作而非套件」——皆符合 ADR 三要件（難以逆轉、脫離脈絡會讓人疑惑、真實的技術取捨——尤其前者是本輪 Discovery 過程中先定案又被審查推翻的決策，脫離脈絡格外容易讓人疑惑），依專案慣例（Architecting 階段負責撰寫 ADR）留待 `spec.md` 階段正式記錄為 ADR，不在本 Discovery 階段撰寫。

## 下一步

Architecting：撰寫 `spec.md`，定義三態轉換 enum 的具體型別與欄位命名、OpenCC 原始字元表 vendoring 的具體版本/路徑與雙端查找表產生流程、WebView 端 1:1 字元 DOM Walker 模組的介面（含既有劃線/書籤測試案例驗證結論）、Dart 端純字典 helper 的呼叫點清單（目錄/書籤/劃線清單/搜尋結果/書架書名作者）、`SearchRepository` Query Expansion 與 TTS 分段轉換的具體介面，並正式記錄上述兩項 ADR。開始改動 `main.js`／`foliate_native_bridge.dart` 前，須先修復 `check_foliate_es_compat.js` 的既有引用漂移 bug（見「待 Architecting 階段確認的技術風險」）。
