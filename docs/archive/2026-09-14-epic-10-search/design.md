# Epic 10 — 全文檢索：Discovery

## 緣起與範圍界定

PRD FR-04（P2）與 NFR-2 已定義基本需求：全庫檢索書名/作者/內容，500ms 內回應（1,000 本書規模），結果分「書名/作者匹配」與「內容匹配」兩區、各自可跳轉。`docs/epics.md` 原本只有一句 Backlog 備註「獨立於圖書庫之外的子系統（SQLite FTS5）」，尚無任何目錄或設計文件。本次 `/grill-with-docs`（2026-09-10）完整定案範圍、UI 入口、索引精度與資源治理策略。

## 現有程式碼現況（決定了本 Epic 是「從無到有」還是「修正既有」）

- **書架快速過濾：已存在，維持不動。** `library_screen.dart` 的 `_searchController`/`_filterBooksBySearchQuery()` 純記憶體比對已載入書籍的書名/作者，程式碼註解已明確寫明與本 Epic（`epic-10-search`）分屬不同範圍，不牽動 SQLite/FTS5。
- **本書內搜尋：只有 PDF 有實作，且不是透過頂列「搜尋」按鈕開啟。** Chrome Bar 頂列「搜尋」按鈕（`reader_chrome_top_bar.dart` `onSearchTap`）**對所有格式（含 PDF）皆無條件顯示「功能開發中」SnackBar**（`reader_screen.dart:2044`，未依格式分支）。PDF 真正可用的內文搜尋（`PdfSearchPanel`，透過 `pdfrx.loadStructuredText()` 即時比對，不落地索引）是掛在「目錄」按鈕開啟的 `TocBottomSheet` 內建搜尋分頁（`_openPdfToc()`／`reader_screen.dart:1296`），Foliate 格式的 `TocBottomSheet` 沒有對應搜尋分頁。此缺口（含頂列按鈕本身的 stub）不在本 Epic 範圍。
- **SQLite schema：`books` 表已有 `title`/`author` 欄位可直接查詢，尚無任何 FTS5 virtual table 或內容索引機制。** `is_downloaded`/`cloud_file_id` 欄位已存在（`epic-29-cloud-import`／`epic-30-calibre-remote-library`），代表 `books` 表本已有「書籍存在但檔案未必在本機」的既有語意，本 Epic 直接沿用判斷，不需新增欄位。
- **`sqflite`（`^2.4.2+1`）在 Android 上呼叫系統內建 SQLite，不綁定自帶版本。** Android 11（PRD NFR-6 最低支援版本）系統 SQLite 為 3.28.0，早於 FTS5 `trigram` tokenizer 所需的 3.34+，本 Epic 因此**不能**依賴 `trigram` tokenizer（見下方「索引範圍與中文比對粒度」的修正決定）。
- **既有刪除的外鍵級聯機制可直接沿用。** `book_reader_prefs`／`bookmarks`／`highlights`／`notes` 皆宣告 `book_id ... REFERENCES books(id) ON DELETE CASCADE`，且 `PRAGMA foreign_keys = ON` 已開啟（`sqlite_library_repository.dart:66/383`），`deleteBook()`（`sqlite_library_repository.dart:1027`）本身只執行 `DELETE FROM books`，級聯完全交給 SQLite 引擎處理，App 端無需額外程式碼。
- **`AppLifecycleState.paused`/`resumed` 已有既有慣例可直接沿用。** `main.dart`／`reader_screen.dart` 皆用 `WidgetsBindingObserver` 監聽，只在真正進入背景（`paused`，不含 `inactive` 過渡態）與返回前台（`resumed`）時觸發動作，本 Epic 的背景索引排程比照同一慣例（見下方「啟用全文檢索」修正）。
- **CFI 句級擷取已有先例，但只做「即時單章節」，沒有「批次全書」版本。** TTS 朗讀（`epic-34-tts-readalong`）的 `main.js` `buildTtsSegments()` 已實作「章節內文字 → CFI 對照表」，但只在使用者朗讀到該章節時即時呼叫（透過 `FoliateReaderView`／`foliate_native_bridge.dart` 這條既有 WebView 橋接）。本 Epic 需要的是背景批次跑過一本書的所有章節，屬於既有機制的新使用模式，不是全新技術。
- **書架 AppBar 圖示已滿。** `epic-36-adaptive-shelf-navigation` 定案書架標題列固定只有 3 個圖示（排序/檢視、來源、設定），不能再新增第 4 個常駐圖示作為全庫搜尋入口——這是本 Epic 選擇「沿用書架快速過濾欄位＋下方連結」而非新增圖示的直接原因。
- **`ReaderScreen` 目前沒有「指定初始定位」的 Seam。** 建構子（`reader_screen.dart:187-208`）沒有任何可覆寫已儲存進度的定位參數，開書一律優先還原資料庫存的 `lastReadTime`/`lastPosition`；`showTtsHighlight()`（`main.js`）寫死操作 TTS 專屬的 `currentTtsAnnotationValue`，不可直接挪用做搜尋跳轉的暫態高亮（見下方「全庫搜尋畫面」修正）。

## 本次落地範圍

### 1. 索引範圍與中文比對粒度

- 書名/作者：不經 FTS5，直接查 `books` 表（`title`/`author` 子字串比對），**不受任何開關限制、永遠可用**。
- 書內全文：**逐字/子字串層級比對**，不做詞彙分詞（中文分詞目前無成熟的純 Dart 函式庫，逐字層級比對行為更可預期、無額外重依賴）。**排除 SQLite FTS5 內建 `trigram` tokenizer**——Android 11（NFR-6 最低支援版本）系統 SQLite 為 3.28.0，早於 `trigram` tokenizer 所需的 3.34+，在最低支援版本上建表必然失敗，這點在 Discovery 階段直接拍板排除，不留給 Architecting「確認」。改採 **Dart 端字元層級 token 化**：寫入與查詢前皆把 CJK 文字逐字元以空白分隔，交給 FTS5 標準 `unicode61` tokenizer 處理；確切切分粒度（逐字／bigram）與是否需要搭配自訂 tokenizer 等實作細節留待 Architecting 決定，但「不依賴 `trigram`」是本次 Discovery 的定案，非待確認風險。
- 適用格式：EPUB（流式/FXL）、KF8(AZW3)、TXT、MD（皆走 Foliate 管線）、PDF。**CBZ（無文字層）與偵測到 DRM 加密的 KF8 僅書名/作者可搜**，內容匹配區塊該書自然不出現任何結果，不需額外 UI 提示。

### 2. 索引精度與切片粒度

- 目標為**精確位置級跳轉**（高於 PRD 字面最低要求的章節級，使用者已確認要做到這個等級）。
- **Foliate 格式**：以句子為切片單位，比照 `buildTtsSegments()` 既有模式取得「句子文字＋CFI」，但索引建置時機是背景批次跑過全書所有 spine 章節（見下方「索引建置與資源治理」），不是 TTS 那種朗讀到才即時建立。
- **PDF**：沿用既有 `pdfrx.loadStructuredText()` 頁面文字＋頁內座標（與 `PdfSearchPanel` 既有邏輯同源，可重用/借鏡其擷取邏輯，但本 Epic 是落地成永久索引而非即時查詢）。

### 3. 「啟用全文檢索」開關

- **拆分為兩個獨立開關：「PDF 全文檢索」與「其他格式全文檢索」（EPUB/KF8/CBZ/TXT/MD，即所有 Foliate 格式）**，各自預設**關閉**、各自獨立生效/清除，互不連動（人類使用者需求：兩種格式的索引建置成本與效果特性不同，見下方理由）。
  - **拆分理由（修正過的分析，避免誤導後續實作）**：PDF 走 `pdfrx` 純 Dart/FFI（`PdfDocument.openFile()`＋`loadStructuredText()`），底層已有自己的 `BackgroundWorker`，資源成本相對輕；真正吃資源的是 Foliate 格式，需要背景開一個 `HeadlessInAppWebView`（等於背景跑一個完整 Chromium 渲染行程）逐章節解析（ADR 0027 決策 2/3 的生命週期治理正是為此而設）。**因此拆分的主要理由不是「PDF 比較吃資源」，而是「PDF 索引效果可能不佳」**：許多 PDF（尤其掃描/圖片型書籍）沒有真正的文字層，`loadStructuredText()` 會抓到空文字或亂碼，整本背景索引等於白工；這種情況無法像 CBZ 那樣在格式層級提前判定（CBZ 是格式上必然無文字層，匯入當下就能標記 `unsupported`），PDF 有沒有文字層是逐檔案才知道的事，沒有可靠的低成本方式在啟用前自動篩掉。讓使用者自行判斷「我書庫裡多是掃描 PDF、不值得索引」而整體關掉 PDF 這一類，是比不可靠自動偵測更務實的做法。反過來，Foliate 格式雖然資源成本較高，但幾乎必然有真正的文字層（掃描書籍不會被匯入為 EPUB/TXT），索引「效果」疑慮低，資源疑慮才是它獨立開關的理由——兩個開關的關切點剛好互補，各自成立，故兩者都值得獨立控制，不是只拆一邊。
  - **雙入口**（比照原設計）：(1) 「全庫搜尋」畫面本身——入口需**持久存在、不隨開關狀態消失**，未啟用時內容匹配區塊顯示說明卡片＋兩個開關（快速上手用），任一開關開啟後該區塊逐步被對應格式的搜尋結果取代，兩個開關與「手動重建索引」改由**畫面 AppBar 一個常駐的「設定」選單**承接；(2) **系統設定「閱讀」分區**同步新增一項「全文檢索」設定項，底下列出兩個獨立開關（含各自的目前已索引書籍數、各自的手動重建索引按鈕）。兩個入口都是同一份底層狀態（兩個布林、兩份索引進度、兩顆重建索引邏輯）的不同呈現位置，非四套獨立設定。
- 每個開關各自只控制對應格式的「內容匹配」半段（書名/作者永遠不受任何開關影響）：關閉時不建立/不查詢該格式的書內全文索引。
- 每個開關開啟時各自彈出**一次性確認 Dialog**：兩者共用同一個 Dialog 元件但文案依格式微調——PDF 版本額外提醒「部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容，索引後仍查不到属於正常情況」；Foliate 版本維持原文案「將觸發背景索引建置（含既有書庫舊書回填），過程會增加運算與電量消耗」。
- **背景索引僅在「App 前台且未開啟任何閱讀畫面」時執行**，比照既有 `AppLifecycleState.paused`/`resumed` 慣例——不使用 Foreground Service，也不嘗試在 App 背景化時繼續運算（Android 對無前台服務的背景行程有凍結/終止機制，尤其 Foliate 端仰賴的 Headless WebView 在背景化後 JS 計時器會被系統暫停，無法繼續解析）：使用者開啟任何一本書的閱讀畫面，或 App 進入背景（`paused`），背景索引皆立即暫停並記錄進度游標（目前處理到第幾本書/第幾章節）；待使用者回到書架/全庫搜尋畫面且 App 回到前台（`resumed`）後，從游標處繼續。此規則對 PDF／Foliate 兩個佇列一視同仁（PDF 雖然資源成本較低，仍比照同一互斥規則，不特殊放寬——維持行為一致、實作簡單）。
- 「全庫搜尋」畫面同時顯示**兩組**索引進度（例如「PDF：已索引 40/90 本」／「其他格式：已索引 120/350 本」），避免使用者誤把「還沒索引到」當成「內容真的沒有」。
- **關閉任一開關時立即清除該格式已建立的內容索引**（視為可重建的衍生資料），不影響另一個格式的索引資料。
- 未下載完成／已移除本機快取的雲端匯入或遠端書庫書籍：書名/作者一樣可搜；內容索引僅在檔案確實存在本機、且該書籍格式對應的開關已開啟時建立，下載完成觸發索引、移除快取時對應內容索引一併清除。

### 4. 索引回填與維護

- 既有舊書：App 更新後，各自依「PDF 全文檢索」／「其他格式全文檢索」該開關是否已開啟，**自動背景漸進建立**對應格式的索引（一個開啟、另一個關閉時，只回填已開啟那一邊的格式）。
- 設定同時提供**手動「重建索引」**入口，放在「全庫搜尋」畫面 AppBar 常駐設定選單內（與開關同一個選單），作為索引因邊界情況漏建/損毀時的救濟手段，觸發流程細節留待 Architecting／`spec.md` 定案。

### 5. 全庫搜尋畫面：入口與結果呈現

- 入口沿用「書架快速過濾」欄位：輸入關鍵字後，**固定黏著於搜尋框下方的一條輕量提示列**（不隨書單捲動／分頁位置改變，多頁搜尋結果時也一律可見）提供「搜尋書內內容」連結，帶同一組關鍵字導向獨立的「全庫搜尋」結果畫面，不需重新輸入。
- 「全庫搜尋」畫面本身**有自己的搜尋輸入框**（帶入前一步關鍵字作初始值，可修改後重新查詢），採**防抖（建議 300ms）或送出制**（點擊搜尋鍵/鍵盤 Enter 才觸發查詢）避免逐字輸入就頻繁查詢 FTS5，尤其 E-Ink 裝置上容易感受到卡頓。
- 結果分兩區：「書名/作者匹配」、「內容匹配」，依 FR-04 各自支援跳轉。
- 內容匹配每本書**最多顯示 3 則**片段，不窮舉所有命中位置；排序/相關度演算法（例如是否採 FTS5 內建 BM25）留待 Architecting 定案。
- 點擊內容匹配片段：直接跳轉到該精確位置（Foliate：句級 CFI；PDF：頁碼＋頁內座標），並給予**一次性暫態視覺提示**（沿用「朗讀高亮」既有的暫態視覺語言，不寫入 `highlights`/`notes`、不參與同步）。提示生命週期：**顯示後固定 3 秒自動淡出，若使用者提前翻頁/點擊畫面則立即消失**，取兩者較早發生者。
- **需要擴充 `ReaderScreen` 既有 Seam**：目前建構子（`reader_screen.dart:187-208`）沒有任何「指定初始定位、覆寫已儲存進度」的參數。本 Epic 需新增一個可選的初始定位參數（具體型別/命名留待 `spec.md`），優先權高於資料庫已存的 `lastPosition`，且只在「從全庫搜尋跳轉開書」這條路徑才帶入。Foliate 端另需一支與 TTS 狀態解耦的高亮 JS 方法（現有 `showTtsHighlight()` 寫死操作 TTS 專屬的 `currentTtsAnnotationValue`，不可直接借用），避免污染朗讀控制器狀態機。

### 6. 索引資料的級聯清除

- 書籍刪除（單筆或批次）時，內容索引資料須跟著清除，比照 `book_reader_prefs`／`bookmarks`／`highlights`／`notes` 既有慣例——這四張表皆宣告 `book_id ... REFERENCES books(id) ON DELETE CASCADE`，且 `PRAGMA foreign_keys = ON` 已開啟，`deleteBook()` 本身只執行 `DELETE FROM books`，級聯完全交給 SQLite 引擎處理，App 端無需額外程式碼。本 Epic 儲存內容索引的資料表（無論 Architecting 最終決定是規則表＋FTS5 外部內容表、或其他結構）**須沿用同一慣例宣告外鍵級聯**，不得另外在 `deleteBook()` 手動補程式碼清理。
- 背景索引建置過程中若產生任何暫存解壓/擷取檔案，須在單書處理完畢後立即刪除，不得遺留。

## 明確排除於本 Epic 之外

- **書架快速過濾**（純記憶體書名/作者比對）維持現狀，不整合進 FTS5，不受本 Epic 任何開關影響。
- **本書內搜尋**（Foliate 格式 Chrome Bar「搜尋」按鈕目前是 stub）不在本 Epic 範圍，是獨立的既有技術債，需要時另立 Issue。
- **搜尋索引不跨裝置同步**：索引是純本地衍生資料，每台裝置各自背景建立，`epic-8-sync` 既有的四個同步 collection（進度/劃線/備註/書籤）不擴充涵蓋索引資料。

## 待 Architecting 階段確認的技術風險

trigram tokenizer 的排除已於本輪修訂在 Discovery 階段直接拍板（見「索引範圍與中文比對粒度」），不再列為待確認風險；以下是仍需要 Architecting 具體驗證/設計的項目：

- **Dart 端字元層級 token 化的確切切分規則**：逐字元或 bigram、是否需要搭配自訂 tokenizer，需在 `spec.md` 定案並確認 FTS5 `unicode61` 對切分後 token 的比對行為符合預期。
- **句級切片的資料量級必須量化驗證，非事後補測**：以一般中文小說 20-30 萬字、7,000-12,000 句估算，1,000 本書規模會產生約 700 萬至 1,200 萬列 FTS5 記錄，遠高於「一本書一列」的量級。`spec.md` **必須**包含：(1) 以近似真實規模的測試資料實測查詢延遲是否仍符合 NFR-2 的 500ms；(2) 若不符合，將**兩層式索引**（書籍/章節級粗篩 FTS ＋ 命中後才動態查句級明細）明訂為備案架構，而非事後才評估。
- **Headless WebView 生命週期需要明訂邊界**：背景批次跑 Foliate 全書所有章節取得 CFI，需要驅動隱藏的 `InAppWebView`（`foliate-js`）逐章節解析，資源與耗時皆高於 PDF 端純 Dart 擷取（`pdfrx` 走原生 FFI，無此問題）。`spec.md` **必須**規劃：(1) 佇列/併發上限（例如一次僅處理一本書）；(2) WebView 實例的生命週期邊界（例如每處理 N 本書或達一定記憶體閾值即銷毀重建，避免單一 WebView 長時間累積 DOM/Blob 造成洩漏，比照 ADR 0018 既有 EPUB 串流限制的經驗教訓）；(3) 每完成一個章節/書籍即以非同步方式讓出事件迴圈，避免長時間佔用主執行緒造成掉幀或裝置發熱。

## 下一步

Architecting：撰寫 `spec.md`，定義 FTS5 schema（`book_content_fts` virtual table 結構、`book_id`／切片索引／CFI 或頁碼＋座標 對照表，外鍵級聯比照既有慣例）、索引建置管線介面（Foliate 背景批次擷取 vs PDF 擷取的共同抽象，含 WebView 生命週期與併發上限）、「啟用全文檢索」開關與背景索引排程（含與閱讀互斥、進度回報）的元件介面，以及 `ReaderScreen` 初始定位參數與 Foliate 端解耦高亮方法的具體簽章。
