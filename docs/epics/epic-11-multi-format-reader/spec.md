# Epic 11 — 多格式閱讀擴充（KF8/CBZ/TXT/MD）：Spec

> 本文件為本 Epic 的唯一事實來源，取代 `design.md` 對應章節的暫定內容。決策依據見 `design.md`（Discovery）、`docs/adr/0023-multi-format-foliate-pipeline-txt-route-reversal.md`（核心架構決策）、`issues.md` Issue 1 Spike 結果（`reviews/spike-issue1-kf8-cbz-drm.md`／`reviews/review-issue-1-spike-execution.md`）與 `docs/prd.md` FR-43。

## Problem Statement

elinkBook 目前只能讀 ePub3、PDF、TXT 三種格式，繁體中文讀者手上大量的 Kindle 電子書（KF8/AZW3）、下載的漫畫壓縮檔（CBZ）、以及個人筆記/文件（Markdown）完全無法匯入使用——使用者必須為了讀這些檔案另外安裝其他 App，破壞了「一個 App 讀所有格式、統一版面客製化」的核心價值主張。TXT 格式雖然已支援，但採用的技術路線（獨立自訂排版引擎規劃，尚未實作）注定會讓 TXT 的直排/避頭尾/劃線/書籤體驗與 EPUB 產生落差，且需要重複造輪子維護一套排版與定位系統。

## Solution

擴充支援 KF8 (AZW3)、CBZ、Markdown (MD) 三種新格式，並將 TXT 的技術路線從「自訂輕量排版引擎」改為與新格式共用同一套已在 EPUB／FXL 上打磨兩輪（`epic-17`/`epic-20`）的 `foliate-js` 渲染管線——KF8 因本質是 EPUB3 衍生格式，透過 `mobi.js` 解出內容後直接享有與 EPUB 完全相同的直排/避頭尾/CFI/劃線/書籤/目錄/同步能力；CBZ 因是圖像漫畫，透過 `comic-book.js` 解出圖片序列後復用既有的 EPUB FXL 雙頁/RTL/裁切基礎設施；TXT／MD 於匯入時預處理為 EPUB 相容的「合成書籍結構」後同樣走這條管線。四種格式合稱「Foliate 格式」（`CONTEXT.md`），與獨立的 `PdfReaderView` 並列為 `ReaderScreen` 僅有的兩條渲染分派路徑。

## User Stories

1. As 持有 Kindle 電子書（AZW3）的讀者, I want 直接匯入並開啟 KF8 檔案, so that 我不需要先轉檔或另外安裝 Kindle App。
2. As KF8 讀者, I want 開啟後能像 EPUB 一樣切換直排/橫排, so that 我閱讀繁體中文小說時有一致的直排體驗。
3. As KF8 讀者, I want 標點符號正確轉向與避頭尾, so that 直排排版品質與 EPUB 沒有落差。
4. As KF8 讀者, I want 使用目錄、書籤、劃線、備註功能, so that 我在 KF8 書籍上的閱讀體驗與 EPUB 完全一致，不需要重新學習。
5. As KF8 讀者, I want 我的閱讀進度、劃線、書籤能跨裝置同步, so that 我換裝置閱讀 KF8 書籍時不會遺失記錄。
6. As 誤匯入受 DRM 保護 KF8 檔案的使用者, I want 系統立刻告訴我這本書不支援、而不是卡在空白畫面或匯入一本打不開的書, so that 我知道問題出在哪、不會誤以為 App 故障。
7. As 持有大量漫畫壓縮檔（CBZ）的讀者, I want 直接匯入並開啟 CBZ 檔案, so that 我不需要另外安裝漫畫 App。
8. As CBZ 讀者, I want 圖片依正確頁碼順序顯示（不因檔名是 `1.jpg`/`10.jpg`/`2.jpg` 這種非零填補格式而錯位）, so that 我看漫畫時頁面順序不會亂掉。
9. As 讀日漫（右翻）的 CBZ 讀者, I want 切換成 RTL 翻頁方向, so that 翻頁方向符合日漫閱讀習慣。
10. As 讀美漫（左翻）的 CBZ 讀者, I want 維持預設的 LTR 翻頁方向, so that 翻頁方向符合我平常的閱讀習慣。
11. As 平板/橫向持機的 CBZ 讀者, I want 橫向時雙頁並排顯示, so that 大螢幕閱讀體驗更接近實體漫畫。
12. As CBZ 讀者, I want 封面自動使用壓縮檔內第一張圖片, so that 書架上能一眼認出這本漫畫。
13. As CBZ 讀者, I want 版面設定（翻頁方向、雙頁、裁切、影像濾鏡）操作方式跟既有的 EPUB 固定版面（漫畫）書籍一致, so that 我不需要學一套新的設定介面。
14. As CBZ 讀者, I want 系統清楚告訴我這個格式不支援劃線/備註（而非讓我點了沒反應、疑惑功能是否故障）, so that 我理解這是圖像格式的固有限制。
15. As 持有網路小說 TXT 檔案的讀者, I want 匯入後系統自動偵測編碼（含繁中常見的 Big5）, so that 我的 TXT 檔案不會因編碼判斷錯誤而變成亂碼。
16. As TXT 讀者, I want 系統自動偵測章節標題並產生目錄, so that 我可以快速跳到特定章節，不需要一直捲動。
17. As 持有超大型 TXT 檔案（例如百萬字網路小說）的讀者, I want 開書速度不受檔案大小拖累、也不會讓 App 卡死或閃退, so that 大檔案跟小檔案的閱讀體驗一樣流暢。
18. As TXT 讀者, I want 直排/橫排、字型、劃線、書籤、目錄等功能與 EPUB 完全一致, so that 我不需要因為讀的是 TXT 而放棄任何既有功能。
19. As 持有 Markdown 筆記/文件的讀者, I want 直接匯入並開啟 MD 檔案, so that 我可以用 elinkBook 閱讀我的筆記，不需要另外開筆記軟體。
20. As MD 讀者, I want 系統從 YAML Frontmatter 讀出標題/作者/封面, so that 我的筆記在書架上有正確的書名與封面，不是只顯示檔名。
21. As MD 讀者, I want 系統依標題階層（H1-H6）自動產生目錄, so that 我可以快速跳到筆記的特定章節。
22. As MD 讀者, I want 程式碼區塊與表格在直排模式下維持橫排、可橫向捲動閱讀, so that 程式碼/表格不會因為直排而變得無法閱讀。
23. As MD 讀者, I want 直排/橫排、字型、劃線、書籤功能與其他格式一致, so that 我不需要為了讀筆記而學習另一套操作邏輯。
24. As 使用者, I want 書架封面能正確反映 KF8/CBZ/MD 各自的格式特性（KF8 用內嵌封面、CBZ 用第一張圖片、MD 用 Frontmatter 或動態生成）, so that 我在書架上能快速分辨不同書籍。
25. As 使用者, I want 匯入 KF8/CBZ/MD 時走跟現有格式一樣的檔案選擇器/資料夾批次匯入流程, so that 匯入操作不會因為格式不同而變得複雜。
26. As 使用者, I want 全文檢索（書名/作者/內容）未來也能涵蓋這些新格式, so that 我不會因為換了格式就找不到書（本 Epic 只需確保資料結構相容，實際檢索留待 `epic-10-search`）。
27. As 開發者/未來維護者, I want KF8/CBZ 的 metadata/封面/DRM 偵測邏輯是純 Dart 實作、不依賴任何原生 platform channel, so that 未來 iOS 移植（`epic-13-ios`）不需要重寫這層。
28. As 開發者/未來維護者, I want TXT/MD 匯入產生的合成書籍結構在刪除書籍時一併清理, so that 圖書庫不會累積孤兒檔案佔用儲存空間。
29. As 開發者/未來維護者, I want TXT/MD 的跨裝置內容指紋（`contentFingerprint`）對原始輸入檔案計算，不受合成轉換的非決定性因素影響, so that 同步引擎能正確判斷「這是不是同一本書」。
30. As E-Ink 裝置使用者, I want KF8/CBZ/TXT/MD 都能套用 E-Ink 高對比模式, so that 這些新格式在墨水屏上的可讀性跟既有格式一樣好。

## Implementation Decisions

### 格式偵測與渲染分派

- `app/lib/reader/book_format.dart` 的 `BookFormat` enum 新增 `azw3`、`cbz`、`txt`、`md` 值（沿用既有「依副檔名判斷、無法識別一律回傳 `unknown`、絕不拋出例外」的既有契約）；`detectBookFormat()` 內部分派邏輯簡化為「pdf 走 `PdfReaderView`，其餘（epub/azw3/cbz/txt/md）走泛化後的 Foliate widget」二元判斷。
- `app/lib/library/models/library_enums.dart` 的 `BookFileFormat` enum 新增對應值，命名依現有慣例採副檔名字串（`azw3`，非 `kf8`——`epub`/`pdf`/`txt` 現有列舉值皆以副檔名命名，非格式正式名稱），確保 SQLite `books.format` 欄位既有的「以 `.name` 存字串」序列化機制無需 schema 遷移即可直接支援新值；需新增對應的既有升級測試涵蓋。
- `app/lib/reader/foliate_epub_reader_view.dart`（class/檔名 `FoliateEpubReaderView`）泛化重構為 `FoliateReaderView`（`app/lib/reader/foliate_reader_view.dart`），服務全部經 Foliate 管線渲染的格式；`ReaderScreen` 對 KF8/CBZ/TXT/MD 一律建構這個泛化後的 widget，不新增分支。`CLAUDE.md`「`ReaderScreen`」架構小節同步更新反映新名稱與新格式涵蓋範圍。
- `mobi.js`（KF8）、`comic-book.js`（CBZ）皆已用 GitHub API 查證存在於本專案已釘定的 `readest/foliate-js` commit（`dd71f2be356563c16a23272686189fcfb45d0b82`），Issue 1 Spike 已用真機驗證兩者可正確整合；新增 vendor 至 `app/android/app/src/main/assets/foliate/`（`mobi.js`、`comic-book.js`、`vendor/fflate.js` 三個新檔案，其餘既有 10 個檔案不動）。`view.js` 的 `makeBook()` 對這兩種格式皆為**全自動偵測分派**（KF8/MOBI 靠檔案 magic bytes、CBZ 靠副檔名/MIME），Dart／Kotlin 端呼叫端不需要自己判斷格式再手動 `import` 對應模組。

### KF8 (AZW3) 支援

- KF8 走既有 EPUB 相容渲染路徑：直排/避頭尾、CFI 定位、劃線/備註/書籤、目錄、跨裝置同步全數繼承既有機制，不需要新增格式專屬的閱讀功能程式碼（Issue 1 Spike 已用真機驗證 `mobi.js` 解出的內容能正確流入既有直排管線，包含 `book.transformTarget` CSS 覆蓋機制與 `epub.js` 完全同源）。
- **DRM 偵測**：於純 Dart metadata 擷取階段完成，讀取 PDB header（record 0 內 offset 12、2 bytes、大端序，`PALMDOC_HEADER.encryption` 欄位語意——已用 Issue 1 Spike 的 Python/Node 雙重驗證確認此 offset 邏輯正確，`ByteData.getUint16(record0Offset + 12, Endian.big)`）；值非 0 即代表加密（1＝舊版 Mobipocket 加密、2＝Mobipocket 加密），拋出專用例外（`DrmProtectedException`），中止該書匯入、**不寫入 `Book` 記錄**，呼叫端顯示友善錯誤訊息（例如「此檔案受 DRM 保護，暫不支援」）——比照 `book_import_service_impl.dart` 現有「單本 metadata 擷取失敗（`PlatformException`）不中斷整批匯入、降級處理」的批次容錯慣例，但 DRM 屬於「明確不支援、不該讓使用者以為匯入成功」的情況，不可比照降級為「無封面/檔名為標題」繼續建立書籍記錄。`mobi.js` 本身不會因此欄位非 0 而拒絕開啟，偵測必須獨立於 `mobi.js` 之外實作。

### CBZ 支援

- CBZ 復用既有 `Book.isFixedLayout = true` 分派路徑與 `FxlSettingsSheet`（`epic-20` 產物），不新增平行欄位或獨立設定面板；不支援劃線/備註（比照既有 FXL 圖像無文字節點的既定限制），UI 上對 CBZ 隱藏劃線/備註相關入口而非顯示後點擊無反應。
- **自然排序**：`comic-book.js` 的 `makeComicBook()` 對圖片檔名僅用字典序 `.sort()`，**沒有**自然排序邏輯（Issue 1 Spike 已用真機驗證：非零填補檔名如 `1.jpg`/`10.jpg`/`2.jpg` 會被排成 `1,10,2,3...`）。匯入管線（Dart 端）須在建立 `Book` 記錄前對 CBZ 內部圖片檔名做自然排序，並依排序結果重新命名/重建壓縮檔內部索引（不能依賴 `comic-book.js` 內建排序）。封面固定取排序後的第一張圖片。
- **翻頁方向（RTL/LTR）**：`comic-book.js` 回傳的 `book` 物件不含 `dir` 欄位，`fixed-layout.js` 的 RTL 判定完全依賴 `book.dir === 'rtl'`（Issue 1 Spike 已驗證此覆寫機制本身可行）。`main.js` 整合層須依使用者於 `FxlSettingsSheet` 設定的翻頁方向偏好，於 `makeComicBook()` 之後、`view.open(book)` 之前設定 `book.dir`。**此決策的驗證範圍需涵蓋導覽層**：Issue 1 Spike 僅證實 `book.dir` 覆寫值能正確傳遞到 `view.book.dir`，尚未驗證 `view.js` 的 `goLeft()`/`goRight()`（或本專案既有 3×3 熱區 `ZoneAction` 分派邏輯）在 RTL 模式下是否對使用者實際點擊熱區回傳正確的翻頁方向——此點須在本 Epic 的實作/測試階段補齊驗證，不可視為已完成。
- 橫向雙頁顯示（PRD FR-41）直接復用 `epic-20` 已為 EPUB FXL 建立的雙頁/封面獨立顯示/`fixed-layout.js` spread 配對機制，CBZ 不需要額外開發。
- **目錄/進度回報格式**：預設提供「第 1 頁／第 2 頁／…／第 N 頁」的虛擬頁碼目錄（依自然排序後的頁面順序自動生成，不需要額外的章節語意），滿足「目前頁 / 總頁數」與快速跳頁的最低需求；`fixed-layout.js` 既有機制是否可直接複用此虛擬目錄的呈現/跳轉留給 Scrum Master 拆解對應工單查證。

### TXT／Markdown 合成書籍結構

- TXT／MD 於**匯入時**（非開書時）落地轉換為「合成書籍結構」——EPUB/XHTML 相容的衍生檔案，存於 App 私有目錄，`Book.filePath` 之後指向此衍生檔案（比照既有 `coverPath` 衍生檔案慣例）；原始檔案僅於匯入當下讀取一次，之後不再參照。合成結構恆為流式（`isFixedLayout = false`）。**命名與存放須以 book id 為鍵、獨立子目錄存放，確保跨書籍不會產生檔名碰撞**——比照 `book_import_service_impl.dart` 現有 `_landCover()` 以 `$bookId.png` 存於獨立 `covers/` 子目錄的既有慣例，非另創新規則；具體副檔名/目錄名稱留給實作階段的 `plan-issue-N.md` 決定。
- **`contentFingerprint` 計算順序（關鍵約束）**：`book_content_fingerprint.dart` 的 `computeBookContentFingerprint(filePath, ...)` 對傳入路徑逐位元組雜湊；匯入管線串接 TXT/MD 合成步驟時，**必須**對「原始輸入檔案」（合成轉換之前的路徑）計算指紋，不可用合成後的衍生檔案路徑計算——不同裝置/轉換器版本產出的合成檔案（zip 時間戳、內部檔案順序等非決定性因素）會讓 SHA-256 不一致，導致 `epic-8-sync` 的跨裝置「同一本書」比對失效。
- **合成檔案生命週期**：比照 `library_screen.dart` 既有 `coverPath` 刪除清理模式（`try`/`deleteSync()`、單筆失敗不中斷批次迴圈、`content://` URI 因 `existsSync()` 恆為 `false` 天然免疫），TXT/MD 的合成檔案須在刪除書籍時一併清理，避免孤兒檔案殘留。
- **TXT 編碼偵測**：Big5 優先梯隊（`[utf8, big5, big5-hkscs, gbk, utf16]`），純 Dart 自建 Big5↔Unicode 對照表（無原生 platform channel 依賴）；自動偵測失敗時的退回行為（例如以 UTF-8 強制解讀並提示使用者）於實作階段決定，非本文件預先鎖定。**編碼偵測、Big5 轉碼、章節分塊等運算須包裝於 `Isolate.run()`（或 `compute()`）背景執行**，比照 `book_content_fingerprint.dart` 對大檔案 SHA-256 計算的既有作法（「避免大檔案阻塞 UI isolate、也避免一次性讀入整個檔案」），大型網路小說 TXT（5MB~20MB 量級）的編碼識別與轉碼運算量不小，不可在 UI isolate 同步執行。
- **TXT 章節/目錄**：正則比對常見章節標題格式（例如「第 X 章/回/卷/節/集」、`Chapter N`）自動產生目錄。
- **TXT 雙重分塊防護**：優先依正則 TOC 切分章節；若無 TOC 或單一章節超過閾值（建議 300~500KB）須再依段落邊界次級分塊，避免單一巨大 XHTML section 造成 WebView DOM 節點過大／記憶體暴增（常見於缺乏規範章節標記的網路小說 TXT）。
- **MD 解析**：YAML Frontmatter 抽取標題/作者/封面（Frontmatter 未指定封面時，退回比照 TXT 既有的「依書名文字動態生成封面」機制）；依標題階層（H1-H6）自動生成目錄；`<pre><code>` 與表格強制注入 `writing-mode: horizontal-tb; direction: ltr;` 並提供橫向捲動，避免直排模式下破版。

### 資料模型異動

- `Book.isFixedLayout` 欄位（`app/lib/library/models/book.dart`）語意由「EPUB 專屬」廣義化為跨格式通用旗標：EPUB／KF8 依書本 metadata 判斷（KF8 沿用與 EPUB 相同的 `rendition:layout` 判讀邏輯）、CBZ 恆 `true`（無流式變體）、TXT／MD 合成後恆 `false`（合成結構本質流式）、PDF 維持 `null`（不適用）。欄位本身與既有 `detectAndCacheEpubLayout()`/「人工版面覆蓋」機制不需要改名或搬遷，僅更新欄位註解反映新語意範圍。
- `Book.epubLocator` 欄位語意隨 KF8/TXT/MD 加入將進一步廣義化為「Foliate 閱讀位置（CFI/Locator）」——欄位名稱維持不變（避免不必要的 SQLite 欄位搬遷），僅更新註解說明；該欄位現有 doc 註解描述為「Readium Locator」已因 ADR 0011/0017（Readium Locator → Foliate CFI）過時，此為與本 Epic 無關的既有文件落差，一併於本次順手修正註解但不視為本 Epic 的新增決策。

### Metadata／封面擷取

- 新格式的 metadata／封面擷取一律純 Dart 實作（`archive`＋`xml`＋自建 Big5 對照表，`archive` 套件由現有 dev_dependencies 升為正式 dependencies，新增 `xml` 依賴），不引入任何原生 platform channel 依賴（例如 `charset_converter`）——保留未來 `epic-13-ios` 移植彈性。EPUB 既有 Readium 擷取路徑（`BookMetadataChannel.kt`）不動，不併入本次範圍。
- 封面策略（PRD FR-27，已修訂）：KF8 使用內嵌封面圖（PDB/EXTH 標頭讀取封面圖片 Image Record）；CBZ 使用壓縮檔內第一張圖片（依自然排序後的順序）；TXT／MD 以書名文字動態生成封面（MD 若 Frontmatter 有指定封面圖則優先使用）。

## Testing Decisions

- **Seam 1（主要）：匯入/解析管線，`flutter test` 對真實/合成 fixture 檔案直接驗證，不需要真機**——涵蓋新增的純 Dart 解析器模組：KF8 metadata/封面/DRM 位元組偵測、CBZ metadata/封面/自然排序、TXT/MD 合成書籍結構產生器（編碼偵測、章節 TOC 正則、分塊防護、Frontmatter 解析）。比照既有 `book_content_fingerprint_test.dart` 對 `computeBookContentFingerprint()` 的測試模式（直接對 fixture 檔案斷言函式回傳值），以及 Issue 1 Spike 已驗證過的位元組解析邏輯（`ByteData.getUint16(offset, Endian.big)`）可直接沿用同一組合成測試緩衝區（`encryption=0/1/2` 三種情境）。何謂好測試：只驗證外部可觀察行為（擷取出的 title/author/cover bytes、DRM 偵測結果、自然排序後的檔名順序、TOC 項目內容），不斷言第三方套件內部實作細節。
- **Seam 2：`FoliateReaderView`（泛化後）／`ReaderScreen`，既有「唯一閱讀器 seam」**——widget-level `flutter test` 驗證建構參數傳遞與狀態機轉換（比照既有 `foliate_epub_reader_view_test.dart`／`reader_screen_test.dart` 對 EPUB 的測試模式，直接呼叫 widget 暴露的回呼模擬狀態變化，不模擬底層原生事件）；原生渲染是否真的成功（KF8 直排是否生效、CBZ 頁序/RTL 是否正確顯示）因涉及 WebView 實際渲染，需要 `integration_test/` 真機驗證（CLAUDE.md 既有兩層測試架構），比照既有 `integration_test/foliate_epub_reader_view_test.dart` 的斷言方式（等待 `Key('reader_loading_indicator')` 消失且無 `Key('reader_error_text')`）。
- **新增測試 fixture**：`app/test/fixtures/` 需新增 `.azw3`／`.cbz`／`.md`（`.txt` 尚未有）測試素材，提交進版控，比照既有 `sample.epub`／`sample.pdf` 慣例；Issue 1 Spike 已驗證可行的取得方式可直接沿用——KF8 用 Standard Ebooks 提供的公版、DRM-free AZW3（已驗證下載連結有效）；CBZ 用 Python `zipfile`＋合成純色 PNG 手工組裝（含至少一份零填補、一份非零填補檔名的變體供自然排序測試）；DRM 測試用 Python 合成的最小 PDB/MOBI 位元組緩衝區（**不使用任何真實受 DRM 保護的檔案**，理由見 `design.md`「明確排除」）。
- CBZ RTL 導覽方向的端到端驗證（`goLeft()`/`goRight()` 或既有 `ZoneAction` 分派在 `book.dir='rtl'` 時的實際行為）須有明確測試覆蓋，不可只驗證 `book.dir` 覆寫值傳遞——此為 Issue 1 Spike 審查（`reviews/review-issue-1-spike-execution.md` Important #1）明確指出的驗證缺口，實作階段對應工單須補上。

## Out of Scope

- **MOBI、FB2**：經 Discovery 階段評估後排除，列為未來獨立 Backlog 項目，不在本 Epic 開 Issue（`design.md`「明確排除」）。
- **Readium 完全退場**（`BookMetadataChannel.kt` 遷移純 Dart）：與新格式上線無必要關聯，另立獨立技術債 Epic。
- **CBZ 劃線／備註**：比照既有 FXL 圖像無文字節點的既定限制，不支援。
- **全書庫全文檢索涵蓋新格式的實際檢索邏輯**：`epic-10-search`（Backlog，尚未開始）範圍，本 Epic 只需確保資料結構相容。
- **手寫/自由繪圖標註**：PRD 既有明確排除範圍，不因格式擴充而重新評估。
- **iOS 實作**：`epic-13-ios` 仍是最低優先順序，純 Dart-only 解析策略是為其鋪路，非本次驗收範圍。
- **CBZ「零排版缺陷」驗收門檻**：CBZ 為圖像格式，驗收門檻已由 PRD 成功準則 #6 明確改為「圖片正確顯示且翻頁方向正確」，不套用文字格式的排版品質門檻。
- **MD 內嵌本機相對路徑圖片的優雅降級**：單一 `.md` 檔案匯入時，若其中引用相對路徑圖片（例如 `![](./img/1.png)`），該圖片資源不會隨匯入一併帶入，瀏覽器/WebView 對缺失圖片資源已有預設行為（顯示破圖圖示，不中斷分頁計算或拋出例外），比照本專案既有對任何格式缺失資源的既有容錯水準，不額外開發 alt 文字/佔位符等優雅降級機制——現階段匯入單位是單一檔案而非資料夾/壓縮包，此為範圍本身的自然限制，非缺陷。

## 審查回應（`reviews/review-spec.md`，2026-08-16，結論 APPROVED / READY FOR SCRUM MASTER）

審查結論為核准通過，2 項 Important／2 項 Minor 皆為「實作層級建議」而非阻擋工單拆解的缺陷。逐項查證後處置如下：

| 項目 | 查證結果 | 處置 |
|---|---|---|
| Important #1 合成檔案命名/目錄隔離 | 查證 `book_import_service_impl.dart` 現有 `_landCover()` 已用「以 book id 為檔名鍵、存於獨立 `covers/` 子目錄」的既有慣例——**建議屬實且與既有模式一致**，非另創新規則。採納，但依 `to-spec` skill 規則「Implementation Decisions 不得包含具體檔案路徑」，寫成「以 book id 為鍵、獨立子目錄」的原則層級決策，不硬性鎖定審查建議的字面路徑（`app_flutter/synthetic_books/`），具體路徑留給 `plan-issue-N.md` |
| Important #2 Isolate 隔離 | 查證屬實——現有 `book_content_fingerprint.dart` 對大檔案 SHA-256 計算已採 `Isolate.run()` 同類防禦，spec.md 原文的「TXT 編碼偵測」條目遺漏此要求。已補上，並引用既有程式碼的既有理由（避免大檔案阻塞 UI isolate） |
| Minor #1 CBZ 虛擬 TOC | 合理提案，與研究報告既有建議（頁面清單虛擬目錄）一致，成本低、消除實作歧義。採納，「目錄/進度回報格式」條目由完全開放問題改為預設「第 N 頁」虛擬目錄，實作細節仍留待查證 |
| Minor #2 MD 本機相對路徑圖片容錯 | **技術評估後不採納「優雅降級機制」本身**：瀏覽器/WebView 對缺失 `<img>` 資源已有預設容錯行為（顯示破圖、不中斷分頁/不拋例外），比照本專案對任何格式缺失資源的既有容忍水準，不需要額外開發 alt 文字/佔位符邏輯（YAGNI）；改為在 Out of Scope 明確記錄此為「單檔匯入」範圍的自然限制，避免後續被誤認為遺漏 |

## Further Notes

- Scrum Master 階段（`issues.md` 後續 Issue 拆解）沿用 `design.md` 決策 #12 既定順序：KF8+CBZ 先（已完成 Issue 1 Spike 驗證，風險最低），TXT+MD 後（需新寫 Dart 預處理器，工作量與風險較高）。CBZ RTL 導覽方向驗證缺口建議併入 CBZ 相關工單的驗收標準，不另立獨立工單。
- KF8/CBZ 的 vendor 資產整合、DRM 位元組偵測邏輯、CBZ 自然排序/RTL 覆蓋可行性皆已於 Issue 1 Spike 真機驗證，實作階段可直接依本文件「Implementation Decisions」落地，不需要重新做技術驗證。
- 測試 fixture 的具體檔案內容、編碼偵測失敗時的退回行為細節、CBZ 目錄/進度回報格式，留給實作階段第一個相關工單的 `plans/plan-issue-N.md` 具體決定並附上驗證證據，本文件僅定義方向與應維持的既有原則。
