# ADR 0027：全庫搜尋索引——字元層級 Tokenization 與 Headless Foliate 驅動批次擷取

## 狀態

已採納

## 背景

`epic-10-search`（全文檢索）Discovery（`docs/epics/epic-10-search/design.md`）已定案：中文書內全文比對採「逐字/子字串層級」，且跳轉精度目標為「精確位置級」（Foliate 格式句級 CFI、PDF 頁碼＋頁內座標），而非 PRD FR-04 字面最低要求的章節級。

`design.md` 審查（`reviews/review-design.md`）指出兩個必須在進入 Architecting 前拍板、否則會直接導致實作走不下去的技術限制：

1. `sqflite`（`^2.4.2+1`）在 Android 上呼叫**系統內建 SQLite**，不綁定自帶版本。Android 11（PRD NFR-6 最低支援版本）系統 SQLite 為 3.28.0，早於 SQLite FTS5 `trigram` tokenizer 所需的 3.34+，在最低支援版本上建表必然失敗。
2. Foliate 格式取得句級 CFI 目前唯一的既有機制是 TTS 朗讀的 `main.js` `buildTtsSegments()`（`epic-34-tts-readalong`），但它只在**使用者朗讀到該章節、且有可見 `FoliateReaderView` 實例掛載**時即時呼叫單一章節。本 Epic 需要的是「背景批次跑過一本書的所有章節」，且不能要求使用者先把書打開——這是本專案第一次需要在**沒有可見閱讀畫面**的情況下驅動 `foliate-js`。

## 決策

1. **排除 FTS5 `trigram` tokenizer，改採「Dart 端 CJK 字元層級 Token 化」**：寫入索引與查詢時，皆對文字中的 CJK 字元（Unicode Han 表意文字範圍）逐字插入空白分隔，ASCII 字母/數字詞彙維持原樣不拆；交給 FTS5 標準 `unicode61` tokenizer 處理（該 tokenizer 預設以空白/標點為分隔符，逐字空白分隔後每個 CJK 字元即成為獨立 token）。查詢時使用者輸入比照相同轉換，再包成 FTS5 phrase query（雙引號包住轉換後字串，要求 token 依序相鄰），達成等效子字串比對效果。
2. **Foliate 格式的批次句級 CFI 擷取，採用 `flutter_inappwebview`（`^6.1.5`，既有依賴、非新增套件）本身已支援的 `HeadlessInAppWebView`**，載入與現有 `FoliateReaderView` 相同的 `assets/foliate/index.html` 資源（沿用 ADR 0018 `WebViewAssetLoader` 串流機制），以新增的 URL query 旗標（例如 `mode=index`）進入「索引模式」：跳過一般閱讀期才需要的 TTS/劃線/書籤/音量鍵橋接初始化，僅依序對每個 spine section 呼叫新增的批次抽取 JS 函式（從 `buildTtsSegments()` 抽出共用核心邏輯，改成不綁定「目前朗讀章節」的批次版本），取得該 section 全部句子的「文字＋CFI」。
3. **一次僅處理一本書、一個 `HeadlessInAppWebView` 實例；每處理完一本書即 dispose，下一本重新建立**，作為資源治理的簡單上限（不嘗試做記憶體閾值偵測，複雜度換取的收益不確定，且無現成量測 API 可低成本取得可靠訊號）。
4. **索引資料採單層設計**（`book_content_index` 規則表 ＋ `book_content_fts` 外部內容 FTS5 虛擬表），不預先建置「書籍/章節粗篩＋句級明細」的兩層架構。是否需要兩層，留待以近真實規模資料實測 NFR-2（500ms/1,000 本書）後才決定是否加開後續 Issue（見 `spec.md`「效能驗證」一節）。

## 曾考慮的替代方案

- **改用 FTS5 `trigram` tokenizer**：Android 11 系統 SQLite 3.28.0 不支援（需 3.34+），排除。
- **改用第三方 bundling 較新 SQLite 的套件（如 `sqlite3_flutter_libs`）取代 `sqflite` 系統版本**：可解決 `trigram` 問題，但代表整個 App 現有全部資料表都要換一套 SQLite runtime，牽動既有 23 版 migration 歷史與全部既有測試，風險與範圍遠超本 Epic，排除。
- **中文分詞（jieba 等）取代逐字層級**：無成熟穩定的純 Dart 函式庫，維護與準確度風險高，且逐字層級行為對「翻書找一句話」場景更可預期（Discovery 階段已定案，見 `design.md`），排除。
- **Foliate 端一律於使用者實際開書當下才即時建索引（比照現有 `buildTtsSegments()` 用法，不做背景批次）**：無法涵蓋「使用者根本沒開過的舊書」與「背景漸進回填」需求，不符 Discovery 已定案的「App 更新後自動背景漸進建立」，排除。
- **兩層式索引（書籍/章節粗篩＋句級明細）直接列為必建架構**：在沒有實測數據前直接雙倍索引維護成本（兩套 schema、兩套同步 trigger、粗篩誤判的邊界情況），有過度工程風險；改為先用單層設計＋強制效能驗證，未達標才加開，排除直接內建為預設架構。

## 後果

- 新增資料表 `book_content_index`／`book_content_fts`／`content_index_status`，`sqlite_library_repository.dart` DB `version` 由 23 升至 24（見 `spec.md` 第 1 節）。
- `main.js` 新增批次抽取 JS 函式與 `mode=index` 進入點；新增一支 Dart 類別驅動 `HeadlessInAppWebView`（見 `spec.md` 第 3 節）。
- 若後續效能驗證未達 NFR-2，需另開 Issue 補建兩層式索引，屬於在既有單層 schema 上新增彙總層，不影響既有資料、非砍掉重練。
