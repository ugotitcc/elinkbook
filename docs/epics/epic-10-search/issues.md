# Epic 10 — 全文檢索：工單清單 (Issues)

依 `spec.md`（Architecting 階段唯一事實來源，已經 `/superpowers:receiving-code-review` 依 `reviews/review-spec.md` 審查修訂）與 [ADR 0027](../../adr/0027-search-index-tokenization-and-headless-foliate-extraction.md) 拆解為 8 個細粒度垂直切片工單（Issue 0-6 已完成，2026-09-12 依 spec.md §9 追加 Issue 7 與 Issue 8）。跟 `spec.md` 對應段落的引用一律用 `spec.md §N` 標示，實作者動手前應先讀那一段的完整說明（含 SQL/型別定義），這裡只列摘要與驗收標準，不重複貼程式碼片段（避免與 `spec.md` 內容漂移）。

**依賴順序：** Issue 0 → Issue 1 為一條鏈（Issue 1 的排程器/索引器直接寫入 Issue 0 建立的 schema，並重用其 tokenizer）。**「啟用全文檢索」拆成 PDF／其他格式兩個獨立開關後**（人類需求，見 Issue 3 背景），Issue 2 的下載完成事件連動（`spec.md` §7：下載完成時是否補插入 `pending` 列）需要判斷該書格式對應的分類**當下是否已啟用**，因此改為依賴 Issue 3（`FullTextSearchSettingsRepository`/`ContentIndexCategory`），**不再與 Issue 3 平行**——這是本次新增拆分後唯一牽動既有依賴圖的地方。Issue 4 依賴 Issue 1（需要有實際索引資料可查）與 Issue 3（需要兩個開關/引導卡片的狀態），**不依賴 Issue 2**（CBZ/DRM/下載邊界情況不影響搜尋畫面本身能否運作）。Issue 5 依賴 Issue 4（需要有搜尋結果可點擊跳轉）。Issue 7 依賴 Issue 4 與 Issue 5（全庫搜尋卡片下鑽與單書全文檢索畫面）。Issue 8 依賴 Issue 7（閱讀器 TopBar 搜尋按鈕接上單書搜尋畫面）。

```
Issue 0 → Issue 1 → Issue 3 → Issue 2
                            → Issue 4 → Issue 5 → Issue 7 → Issue 8

Issue 6（獨立，無依賴，真機相容性已修復並合併）
```

---

## Issue 0：資料庫 Schema＋中文 Tokenizer＋效能驗證 Spike

**Status:** completed（`plans/plan-issue-0.md` 3 個 Task 全數完成，`reviews/review-issue-0.md` 審查 Ready to merge: With fixes，I-1 已修訂；效能驗證結論見 `epic.md`）

**依賴：** 無（可立即開始）

**來源：** `spec.md` §1（資料庫 Schema）、§2（中文 Token 化規則）、§8（效能驗證）

**背景／目標：** 本 Epic 所有後續工單都建立在同一份資料庫 schema 與 tokenizer 之上，且 [ADR 0027](../../adr/0027-search-index-tokenization-and-headless-foliate-extraction.md) 決策 4 採單層索引設計、把「是否需要兩層式索引」的判斷留給實測結果，因此這張工單**必須**在其餘工單開始前完成，且產出的 schema/tokenizer 是正式產品程式碼，不是驗證完就丟的 Spike 腳本。

**Solution：**
- 新增資料庫遷移（DB version 23→24）：`content_index_status`／`book_content_index`／`book_content_fts` 三張表與同步 trigger（`spec.md` §1 完整 SQL），**務必同時在 `onConfigure` 新增 `PRAGMA recursive_triggers = ON;`**（與既有 `PRAGMA foreign_keys = ON` 同一處）——這是 FTS5 external-content 表能正確被級聯刪除同步清空的必要條件，遺漏這行會導致書籍刪除後 FTS 殘留孤兒索引（`spec.md` §1 已有完整技術背景說明）。
- 新增 `app/lib/search/cjk_tokenizer.dart`：`tokenizeForIndex()`／`tokenizeForQuery()` 兩個純函式（`spec.md` §2）。
- 效能驗證：產生近似真實規模的合成測試資料（約 1,000 本書、每本 7,000-12,000 句），寫入新 schema，實測 `book_content_fts MATCH` 查詢延遲是否符合 NFR-2（1,000 本書規模、500ms 內回應）。驗證結果寫進本工單完成備註（`epic.md`）：**符合**則維持單層設計結案；**不符合**則另開一張新工單（依 `spec.md` §8 已規劃的兩層式索引備案）補建彙總層，不影響本工單已交付的 schema。

**單元測試要求：**
- Migration 測試：驗證 DB 23→24 升級後三張新表存在、既有資料不受影響（比照既有 `sqlite_library_repository_test.dart` 升級測試慣例）。
- 級聯刪除測試（**驗證 C-1 修法確實生效，是本工單最重要的回歸測試**）：插入一本書＋對應 `book_content_index`/`content_index_status` 資料，`deleteBook()` 後斷言 `book_content_fts` 對應 rowid 也一併消失（不能只驗證 `book_content_index` 被刪，必須驗證 FTS 表本身同步）。
- `tokenizeForIndex`/`tokenizeForQuery` 純函式測試：CJK 逐字切分、ASCII 單字維持原樣、混合中英文、空字串邊界。
- 效能驗證腳本本身可以是獨立的 benchmark test（不必跑在一般 `flutter test` CI 套件裡，避免拖慢日常套件；於本工單 PR 描述附上實測數據）。

**驗收標準：** `flutter analyze` 乾淨；上述單元測試全數通過；效能驗證有明確數據結論（符合或不符合 NFR-2），寫入 `epic.md`。

---

## Issue 1：背景索引排程器＋PDF／Foliate 內容擷取（端到端）

**Status:** completed（`plans/plan-issue-1.md` 7 個 Task 全數完成，`reviews/review-issue-1.md` 審查 Ready to merge: Yes，0 Critical／0 Important／3 Minor；PR #230 已合併；真機驗證期間另發現 Issue 6 相容性缺陷，與本工單無關）

**依賴：** Issue 0

**來源：** `spec.md` §3（索引建置管線，含 3.1 抽象介面、3.2 兩個實作、3.3 排程器）

**背景／目標：** 本工單是全文檢索的核心引擎——讓一本書（PDF 或 Foliate 格式）從「尚未索引」自動變成「可被全文查詢到、且能精確跳轉」，全程在背景執行且與使用者正在閱讀互斥。PDF 與 Foliate 兩條路徑技術複雜度差異大（PDF 純 Dart/FFI，Foliate 需要 Headless WebView），但共用同一個排程器與 `ContentIndexer` 抽象，合併成一張工單一次交付完整可驗證的端到端行為。

**Solution：**
- 新增 `ContentIndexer` 抽象介面與 `IndexedSegment`（`spec.md` §3.1）。
- 新增 `PdfContentIndexer`：直接 `PdfDocument.openFile()`＋`loadStructuredText()` 逐頁擷取，不需 Widget、不需額外 Isolate（`spec.md` §3.2）。
- 新增 `FoliateContentIndexer`：**必須**重用既有 `cacheBookForServing()`＋`InternalStoragePathHandler` 三件套讓 `HeadlessInAppWebView` 能讀到書籍內容（不是單純帶 URL query 就能運作，`spec.md` §3.2 已記錄這個曾經審查抓到的錯誤設計，實作前務必重讀）；`main.js` 新增 `mode=index`／`window.getSectionCount()`／`window.buildSegmentsForSection(sectionIndex)`；單書處理完畢、被中斷或例外時**無條件**刪除該實例的快取子目錄（比照 `foliate_reader_view.dart` 既有 `dispose()` 清理邏輯），避免磁碟空間洩漏。
- 新增 `ReaderActivityTracker`（`ReaderScreen.initState()`/`dispose()` 呼叫）＋ `ContentIndexingScheduler`：只在「App 前台（`AppLifecycleState.resumed`）且無閱讀畫面開啟」時處理佇列；使用者開書或 App 背景化立即暫停並寫入 `content_index_status.last_chapter_index` 作續跑游標（`spec.md` §3.3）。
- 一次僅處理一本書、一個 `HeadlessInAppWebView`/PDF 文件實例（ADR 0027 決策 3）。

**單元測試要求：**
- `PdfContentIndexer`：對測試 fixture PDF 擷取後比對已知文字內容與頁碼/座標是否正確。
- `FoliateContentIndexer`：對測試 fixture EPUB 擷取後比對已知句子與 CFI 是否正確（可能需要真實裝置/模擬器執行，比照專案既有「牽涉 WebView 渲染的行為一律在 `integration_test/` 驗證」慣例）。
- `ContentIndexingScheduler`：widget/單元測試驗證「開閱讀畫面→暫停」「關閉/背景化→視情況恢復」「續跑游標」三種狀態轉換；FakeAsync／假 `ReaderActivityTracker`／假 `WidgetsBindingObserver` 訊號皆可注入，不需要真的開啟 UI。
- 端到端驗證（本工單的「demoable」標準）：一本 PDF 與一本 EPUB fixture 各自從 `content_index_status='pending'` 到背景排程完成後轉為 `'done'`，且 `book_content_fts` 能查到已知內容並取回正確 `locator`。

**驗收標準：** 上述測試全數通過；`flutter analyze` 乾淨；PDF 與 Foliate 兩條路徑皆有至少一個端到端測試證明「background indexing 真的能把一本書的內容變成可查詢」。

---

## Issue 2：CBZ／DRM KF8／未下載與移除快取書籍的索引狀態處理

**Status:** completed（`plans/plan-issue-2.md` 5 個 Task 全數完成，`reviews/review-plan-issue-2.md` 計畫審查 2 Critical／2 Important／2 Minor 全數採納修訂後，`reviews/review-issue-2.md` 程式審查 0 Critical／1 Important／3 Minor，Important〔計畫文件收尾 commit 編碼損毀〕與 Minor〔多餘 unused_import 抑制註解〕皆已修正；PR #233 已合併。DRM KF8 查證後確認現行匯入架構下無 `Book` 記錄可標記，不實作任何程式碼，詳見計畫 Global Constraints）

**依賴：** Issue 1、**Issue 3**（下載完成事件需要查詢 `FullTextSearchSettingsRepository.isEnabled(category)` 判斷該格式當下是否啟用，才知道要不要插入 `pending`——這是「啟用全文檢索」拆成 PDF／其他格式兩個開關後新增的依賴，原提案 Issue 2 與 Issue 3 可平行，現在不行）

**來源：** `spec.md` §7

**背景／目標：** 讓 Issue 1 的排程器正確跳過本來就不該索引的書籍，並讓雲端/遠端書庫書籍的下載/移除快取事件正確連動索引的建立/清除，避免排程器浪費資源嘗試索引不存在或不支援的內容。

**Solution：**
- CBZ、偵測到 DRM 加密的 KF8：匯入/偵測當下即寫入 `content_index_status.status = 'unsupported'`，排程器查詢 pending 佇列時天生排除（不需要額外的格式判斷邏輯散落在排程器內）。
- 雲端匯入/遠端書庫書籍下載完成（`books.is_downloaded` 轉為 `1`）時，由既有下載完成事件流程（`download_queue_controller.dart`／`remote_book_downloader.dart` 既有回呼點）依該書 `format` 對應的 `ContentIndexCategory` 是否已啟用（呼叫 Issue 3 的 `FullTextSearchSettingsRepository.isEnabled()`），才補插入一筆 `content_index_status(status='pending')`；未啟用則不插入，比照一般匯入同樣受開關管控。
- 移除本機快取（`is_downloaded` 轉回 `0`）時，由既有移除快取的呼叫路徑一併執行「重建索引」同一段清除邏輯（`DELETE FROM book_content_index`／`content_index_status` WHERE book_id = ?），可抽成共用函式供兩處呼叫。

**單元測試要求：**
- CBZ／DRM KF8 匯入後 `content_index_status.status == 'unsupported'`，且排程器的 pending 查詢不會選到它。
- 下載完成事件觸發後，對應書籍出現一筆 `status='pending'`。
- 移除快取事件觸發後，對應書籍的 `book_content_index`/`content_index_status`/`book_content_fts` 資料列皆清空。

**驗收標準：** 上述測試全數通過；`flutter analyze` 乾淨；不影響既有下載/移除快取流程的既有測試。

---

## Issue 3：「啟用全文檢索」設定模型＋雙入口＋確認 Dialog

**Status:** completed（`plans/plan-issue-3.md` 5 個 Task 全數完成，`reviews/review-plan-issue-3.md` 計畫審查 1 Critical／4 Important／3 Minor 全數採納修訂後，`reviews/review-issue-3.md` 程式審查 Ready to merge: Yes，0 Critical／0 Important／2 Minor〔程式碼〕＋1 Minor〔文件筆誤〕皆已修正；PR #232 已合併。本工單只落地「系統設定閱讀分區」單一入口，「全庫搜尋畫面 AppBar 常駐設定選單」第二入口與雙入口一致性驗證留給 Issue 4）

**依賴：** Issue 1（需要排程器 API 供開/關連動）

**來源：** `spec.md` §4

**背景／目標：** 落地使用者控制全文檢索開啟/關閉的完整流程：**兩個獨立開關**（PDF／其他格式，人類需求：兩者索引成本與效果特性不同，見 `design.md` 決策 3 修正後的完整理由）、各自的確認對話框、雙入口共用同一份狀態、開啟時批次回填既有書庫、關閉時立即清除該格式索引資料（不影響另一個開關）。

**Solution：**
- 新增 `FullTextSearchSettingsRepository`（`SharedPreferences` 實作，`ContentIndexCategory { pdf, foliate }` 列舉區分兩個獨立布林值），獨立於 `GlobalReaderPrefs`（`spec.md` §4 已說明理由：本開關會連動資料庫層排程與清除，語意上不是純閱讀偏好）。
- 開啟前彈出確認 Dialog：兩個分類共用同一個 Dialog widget，依 `category` 帶入不同文案——PDF 額外提醒「部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容」；比照 `DESIGN.md` §9.1 一般對話框排版慣例，**不套用** §9.2 破壞性操作的 error 色按鈕慣例；`EBDialogShell` 若屆時已由其他 Epic 落地則直接沿用，尚未落地則用一般 `AlertDialog` 手動符合排版規則。
- `setEnabled(category, true)`：確認後把 `content_index_status` 中尚無資料列、且 `books.format` 屬於該 `category` 的既有書籍批次插入 `pending`（含既有書庫舊書回填），交給 Issue 1 的排程器處理（排程器本身不需感知 `category`，格式篩選責任在這一步）。
- `setEnabled(category, false)`：立即清除**該分類對應格式**的索引資料（`book_content_index`/`content_index_status`），該分類的佇列停止並捨棄目前進度；**不影響另一個分類已建立的索引**。
- 雙入口：全庫搜尋畫面 AppBar 常駐設定選單（含兩個開關＋各自目前索引進度＋各自手動重建索引）＋系統設定「閱讀」分區新增一項（底下列出同樣兩個開關），兩者共用同一個 `FullTextSearchSettingsRepository` 實例（依既有依賴注入模式往下傳遞，不重複實作）。

**單元測試要求：**
- `FullTextSearchSettingsRepository`：`setEnabled(category, true/false)` 對兩個分類分別的持久化與資料庫連動行為（mock 排程器/資料庫），驗證關閉其中一個分類不影響另一個分類的既有索引資料。
- 確認 Dialog：widget test 驗證「確認開啟」才真的呼叫 `setEnabled(category, true)`，「取消」該開關彈回關閉狀態；驗證 PDF/Foliate 兩種文案正確依 `category` 顯示。
- 雙入口一致性：widget test 驗證兩個入口的兩個開關狀態各自同步（其中一個畫面切換後，另一個畫面重新開啟時反映最新狀態）。
- 「重建索引」按鈕：驗證觸發後對應分類書籍的 `content_index_status` 重置為 `pending`，不影響另一分類。

**驗收標準：** 上述測試全數通過；`flutter analyze` 乾淨；兩個入口皆可各自正常開/關兩個開關、各自觸發重建索引，且互不干擾。

---

## Issue 4：全庫搜尋畫面（`LibrarySearchScreen`）

**Status:** completed（`plans/plan-issue-4.md` 4 個 Task 全數完成，`reviews/review-plan-issue-4.md` 計畫審查 1 Critical／5 Important／4 Minor 全數採納修訂後，`reviews/review-issue-4.md` 程式審查 0 Critical／0 Important／3 Minor，3 項 Minor 皆已修正；PR #234 已合併）

**依賴：** Issue 1（需要有實際索引資料可查）、Issue 3（需要開關/引導卡片狀態）

**來源：** `spec.md` §5

**背景／目標：** 交付使用者實際操作全文檢索的畫面本身：書架快速過濾欄位下方的入口、獨立搜尋輸入框、書名/作者與內容匹配兩區呈現。

**Solution：**
- `SearchRepository`：`searchTitleAuthor()`（不經 FTS5，永遠可用）／`searchContent()`（空查詢在 Dart 端直接回傳 `[]`；`tokenizeForQuery()` 轉換後對 `book_content_fts MATCH` 查詢，依 `bm25()` 排序＋`ROW_NUMBER() OVER (PARTITION BY book_id)` 限制每本書最多 3 筆，回傳 `BookContentMatches` 分組型別，`spec.md` §5 有完整 SQL 範例）。
- 新增 `app/lib/screens/library_search_screen.dart`：入口為書架快速過濾欄位下方固定黏著的提示列（不受結果清單捲動/分頁影響）；畫面本身有獨立輸入框（帶入前一步關鍵字，可修改）＋300ms debounce；結果分「書名/作者匹配」／「內容匹配」兩區；`searchContent()` 本身不需要分類參數（索引資料天生只反映已啟用的分類），但引導卡片文案需依 Issue 3 的兩個 `isEnabled(category)` 分別判斷：兩者皆關閉顯示通用引導；只有一個開啟時顯示精確提示（例如「已啟用『其他格式』全文檢索，PDF 內容尚未啟用」）。
- E-Ink 模式：比照 `DESIGN.md` §18 既有慣例（`Duration.zero` 零轉場、結果清單離散分頁），沿用既有基礎設施，不重新發明。

**單元測試要求：**
- `SearchRepository.searchTitleAuthor()`／`searchContent()`：對測試資料庫驗證查詢正確性、空查詢邊界、每本書筆數上限。
- `LibrarySearchScreen`：widget test 驗證 debounce 行為、兩區呈現、兩個開關各種開/關組合下引導卡片文案是否正確（兩者皆關閉／只開 PDF／只開其他格式／兩者皆開啟並顯示真實結果）。
- 入口連結：`library_screen.dart` 快速過濾結果下方連結點擊後帶同一組關鍵字導航至本畫面。

**驗收標準：** 上述測試全數通過；`flutter analyze` 乾淨；手動驗證（或 `integration_test/`）確認搜尋一個已知存在於索引中的詞能在「內容匹配」區看到結果。

---

## Issue 5：搜尋跳轉 Seam（`ReaderScreen.initialJumpTarget`＋暫態高亮）

**Status:** completed（PR #235 已合併；真機驗證發現 E-Ink 裝置系統 SQLite 普遍缺 FTS5 模組，見 `epic.md` 對應日誌，已另立後續分析方向）

**依賴：** Issue 4

**來源：** `spec.md` §6

**背景／目標：** 這是本 Epic 對使用者而言最終、頭牌的完整體驗——點擊全庫搜尋的內容匹配片段後，真正開書跳轉到精確位置並給予暫態視覺提示，且不覆蓋使用者原本的閱讀進度。

**Solution：**
- `ReaderScreen` 新增可選參數 `initialJumpTarget`（`ReaderJumpTarget` 型別，`spec.md` §6）：只影響開書當下「建構子傳給底層 View 的初始定位參數」來源（優先權高於資料庫 `lastPosition`），**不新增任何「暫停進度儲存」旗標**——現行 `_writeCurrentPosition()` 本來就只在背景化/dispose 這種 checkpoint 時機讀取當下即時狀態，`initialJumpTarget` 消費後即完全比照一般開書流程運作，使用者後續翻頁會被正常存檔（`spec.md` §6 已記錄這個比審查建議更簡化的設計理由）。
- Foliate 端新增 `window.showSearchHighlight(cfi)`／`window.clearSearchHighlight()`，使用獨立於 TTS 的 `currentSearchHighlightValue` 變數。
- PDF 端複用既有 `pageOverlaysBuilder` 疊加機制畫暫態高亮矩形。
- 暫態高亮生命週期由 Dart 端 `Timer` 主導：3 秒自動清除，或使用者提前翻頁/點擊畫面時立即清除（取兩者較早發生者）。
- `LibrarySearchScreen`（Issue 4）點擊內容匹配片段時，帶 `ReaderJumpTarget` 開啟 `ReaderScreen`。

**單元測試要求：**
- `ReaderScreen`：widget test 驗證帶入 `initialJumpTarget` 時，初始定位參數確實來自跳轉目標而非資料庫存的 `lastPosition`；且後續一般翻頁行為（含 checkpoint 存檔）與未帶入 `initialJumpTarget` 時完全一致（不因為曾經是搜尋跳轉而有任何殘留特殊狀態）。
- 暫態高亮：`FakeAsync`／`package:clock` 驗證 3 秒自動消失，以及提前翻頁/點擊觸發的提前清除。
- Foliate 端 `showSearchHighlight()`/`clearSearchHighlight()` 不影響 TTS 播放狀態（若同時有 TTS 在播放，搜尋高亮消失不應連帶清除 TTS 朗讀高亮，反之亦然）。

**驗收標準：** 上述測試全數通過；`flutter analyze` 乾淨；`integration_test/` 或手動驗證：從全庫搜尋點擊一則內容匹配，真的跳到該精確位置並看到 3 秒暫態高亮，且原本的閱讀進度不受影響。

---

## Issue 6：FTS5 模組可用性偵測＋全文檢索優雅降級（真機相容性缺陷）

**Status:** completed（`plans/plan-issue-6.md` Task 1 六個 Step 全數完成，`reviews/review-issue-6.md` 審查 Ready to merge: Yes，0 Critical／0 Important／2 Minor；PR #231 已合併；Step 7 真機驗證已於 2026-09-11 補做完成，見 `epic.md` 對應日誌——`9491G`／`Hera_Vis_WIFI` logcat 實測確認 `no such module: fts5`，優雅降級如預期運作、App 正常開機）

**依賴：** 無，獨立於 Issue 0→1→3→2／4→5 依賴鏈，可立即開始；但直接修改 Issue 0 已交付並合併的 schema migration 程式碼，需與 Issue 0 產出物一併考量

**來源：** 真機除錯發現（非 `design.md`／`spec.md` 既定切片，Epic 10 Issue 1 端到端驗證期間於真機上重現）；根因與 [ADR 0027](../../adr/0027-search-index-tokenization-and-headless-foliate-extraction.md)「技術限制」1 描述的風險同源但更嚴重

**背景／目標：**

在 `9491G`／`Hera_Vis_WIFI`（MediaTek 客製化 E-Ink ROM，Android 15）真機上，全新安裝任何包含 Epic 10 Issue 0 資料庫遷移（DB v23→v24）的版本後，App **完全無法啟動、卡在啟動畫面**。經 logcat 重現確認根因：

```
DatabaseException(no such module: fts5 (code 1 SQLITE_ERROR))
sql 'CREATE VIRTUAL TABLE book_content_fts USING fts5(...)' during open, closing...
#2 SqliteLibraryRepository._createBookContentFtsTable (sqlite_library_repository.dart:871)
#3 SqliteLibraryRepository.open.<anonymous closure> (sqlite_library_repository.dart:383)
```

因果鏈：`main.dart:82` 的 `await SqliteLibraryRepository.open(dbPath)` 未包 try/catch／`runZonedGuarded`；`onUpgrade`（`oldVersion < 24`）無條件呼叫 `_createBookContentFtsTable()`；此裝置系統內建 SQLite **完全沒有編譯 FTS5 模組**（不只是版本過舊，是模組本身不存在）；例外一路往上炸穿 `main()`，`runApp()` 永遠不會被呼叫，Flutter 永遠不產出第一幀，原生啟動畫面永遠不消失——**這是完全阻斷 App 啟動的缺陷，影響範圍不只是搜尋功能無法使用**，任何缺少 FTS5 模組的裝置皆會遇到。

ADR 0027「技術限制」1 已討論過相近風險（系統 SQLite 版本可能不支援 FTS5 `trigram` tokenizer，因此決策 1 改採 `unicode61`），但沒有涵蓋「FTS5 模組本身完全不存在」這個更底層的狀況——本工單是對該已知風險類別的延伸，需要重新檢視 ADR 0027 決策 1 是否要補充或修訂。

**Solution（方向草案，待 Scrum Master／人類拍板後細化為可執行計畫，非最終定案）：**
- 在 `SqliteLibraryRepository.open()` 執行 `_createBookContentFtsTable()` 前，先偵測 FTS5 模組是否可用（例如以 try/catch 包裹一次性探測、或查詢 `pragma_compile_options` 是否含 `ENABLE_FTS5`），不可用時**跳過**建立 `book_content_fts` 虛擬表與其三個同步 trigger，但仍正常建立 `content_index_status`／`book_content_index` 兩張一般表，讓 App 能正常開機。
- 需要一個機制讓「本裝置全文檢索不可用」這個狀態能被後續 Issue（尤其 Issue 3 設定畫面、Issue 4 搜尋畫面）查詢到並優雅呈現（例如搜尋入口顯示「此裝置不支援全文檢索」而非讓使用者以為功能存在卻永遠沒有結果），避免這個裝置相容性缺口被靜默吞掉而使用者不明所以。
- 影響範圍評估：這是否只影響這一台裝置（MediaTek 客製化韌體常見於白牌 E-Ink 閱讀器），或有更廣泛的裝置族群受影響，需要人類／Scrum Master 決定調查深度與修復優先序——包含是否要在 Issue 1 合併前搶修，或可先合併 Issue 1（其本身不是造成此缺陷的原因）再另排本工單。

**單元測試要求：**
- FTS5 不可用時的降級路徑：模擬／假造 FTS5 建表拋出 `no such module: fts5` 例外，驗證 `SqliteLibraryRepository.open()` 仍能成功回傳（不重新拋出例外），且 `content_index_status`／`book_content_index` 兩張表仍存在。
- 回歸測試：FTS5 可用的一般情況（現有 CI 環境／大多數裝置）行為不變，`book_content_fts` 仍正常建立，既有 Issue 0 級聯刪除測試不受影響。
- 需要新增一個查詢（例如 `LibraryRepository.isFullTextSearchAvailable`）供 Issue 3／4 判斷是否顯示「本裝置不支援」提示，並有對應測試。

**驗收標準：** 在真實缺少 FTS5 模組的裝置（或以 mock 模擬同等情境的測試）上，App 能正常開機並使用除全文檢索以外的所有既有功能；`flutter analyze` 乾淨；不影響 Issue 0 既有測試套件。

---

## Issue 7：全庫搜尋書籍結果 Drill-Down 與單書全文檢索畫面（`BookSearchScreen`）

**Status:** completed（`plans/plan-issue-7.md` 4 個 Task 全數完成，`reviews/review-issue-7.md` 程式審查 Ready to merge: Yes，0 Critical／1 Important／2 Minor；Important〔`plan-issue-7.md` 未同步複審核准修訂〕與 2 項 Minor〔`searchContentInBook` 查詢合併、BM25 排序測試強化〕皆已修正；PR #237 已合併）

**依賴：** Issue 4（全庫搜尋畫面）、Issue 5（搜尋跳轉 Seam）

**來源：** `spec.md` §9.1、§9.2、§9.3

**背景／目標：**
全庫搜尋目前依 `perBookLimit = 3` 硬限制每本書最多只取出前 3 筆片段，且 SQL 與模型未帶出總命中筆數；使用者無法在一本書中檢視更多匹配結果。本工單提供單書全文檢索的資料存取層擴充、全庫搜尋卡片下鑽（Drill-down）提示按鈕，以及獨立的「單書全文檢索畫面（`BookSearchScreen`）」，支援在本書內即時重搜、切換書中順序/相關度排序、位置標籤顯示與關鍵字高亮強調。

**Solution：**
- **資料存取層擴充（`app/lib/search/search_repository.dart`）**：
  - `ContentMatchSnippet` 新增 `final int? chapterIndex;` 欄位。
  - `BookContentMatches` 新增 `final int totalMatches;` 欄位。
  - `SqliteSearchRepository.searchContent()` 查詢改進：在子查詢中加入 `COUNT(*) OVER (PARTITION BY bci.book_id) AS total_count`，單一 SQL 一併取得總命中筆數，無額外 DB 開銷。
  - 新增 `BookSearchDetailResult` 模型（含 `book`, `matches`, `totalMatches`, `isTruncated`）。
  - 新增 `SearchRepository.searchContentInBook(String bookId, String query, {int limit = 200, bool sortByBookOrder = true})`：過濾指定 `bookId`，支援 `sortByBookOrder: true`（`bci.chapter_index ASC, bci.rowid ASC`，預設）與 `false`（BM25 `score ASC`），上限預設 200 筆。
- **全庫搜尋畫面 Drill-Down 入口（`app/lib/screens/library_search_screen.dart`）**：
  - 在 `_buildContentGroupCard` 底部，當 `group.totalMatches > group.matches.length`（即命中 > 3 筆）時顯示按鈕：`查看全部 ${group.totalMatches} 筆結果（還有 ${group.totalMatches - group.matches.length} 筆）`。
  - 當 `totalMatches <= group.matches.length` 時不顯示額外按鈕。
  - 點擊按鈕透過 `Navigator.push` 導航至 `BookSearchScreen`。
- **單書全文檢索畫面（`app/lib/screens/book_search_screen.dart`）**：
  - 頂部搜尋輸入框：帶入初始關鍵字，支援 300ms 防手震即時搜尋與清除按鈕。
  - 統計摘要與排序切換：顯示書名、作者與命中統計摘要（若 `isTruncated` 為 true 提示「僅顯示前 200 筆，共 X 筆」），並提供按鈕切換「依書中順序」與「依相關度排序」。
  - 片段清單渲染：
    - 位置標籤：PDF 顯示「第 X 頁」，EPUB/其他格式顯示「第 X 章」（或章節編號）。
    - 關鍵字高亮：非 E-Ink 粗體＋淡色背景；E-Ink 模式粗體＋底線（高對比）。
  - 分頁策略：非 E-Ink 模式連續捲動；E-Ink 模式使用 `PagingBar` 離散分頁（每頁 10 筆）。
  - 點擊片段：若 `fromReader == false`，呼叫 `Navigator.push` 開啟 `ReaderScreen`（帶 `initialJumpTarget: ReaderJumpTarget.fromContentLocator(...)`）。

**單元測試要求：**
- `SearchRepository.searchContent()`：驗證 `totalMatches` 正確反映每本書在資料庫的總命中數（例如單書插入 5 筆符合內容，`matches.length == 3` 但 `totalMatches == 5`）。
- `SearchRepository.searchContentInBook()`：驗證指定 `bookId` 查詢、`sortByBookOrder: true`（書中順序）與 `false`（相關度排序）、上限 200 筆與 `isTruncated` 旗標、空查詢與邊界輸入處理。
- `LibrarySearchScreen`：widget test 驗證當 `totalMatches > 3` 時卡片顯示「查看全部」按鈕，`<= 3` 時不顯示；點擊按鈕推入 `BookSearchScreen`。
- `BookSearchScreen`：widget test 驗證初始查詢結果呈現、關鍵字重搜與 debounce、排序切換、E-Ink 模式離散分頁列、點選項目導航開書帶入 `initialJumpTarget`。

**驗收標準：** `flutter analyze` 乾淨；上述單元與 widget 測試全數通過；在全庫搜尋畫面中，命中超過 3 筆的書籍卡片出現按鈕並能順利進入單書結果頁面檢視完整結果與跳轉。

---

## Issue 8：閱讀器 TopBar「搜尋內文」接線與就地跳轉

**Status:** completed（`plans/plan-issue-8.md` 2 個實作 Task（＋1 個驗證收尾 Task）全數完成）

**依賴：** Issue 7（需要 `BookSearchScreen`）

**來源：** `spec.md` §9.4

**背景／目標：**
閱讀器頂部工具列已存在 `reader_chrome_search_button` 按鈕（`ReaderChromeTopBar`），但目前點擊僅彈出「功能開發中」SnackBar。本工單將其正式接上 Issue 7 的 `BookSearchScreen`，並讓從閱讀器進入的使用者在點選片段後直接 pop 回傳跳轉目標，於閱讀器就地跳轉與疊加暫態高亮，不銷毀重建閱讀器 session。

**Solution：**
- 在 `ReaderScreen._buildChromeTopBar` 中，將 `onSearchTap` 接上開啟 `BookSearchScreen(book: _currentBook, fromReader: true, ...)`。
- `BookSearchScreen` 支援 `fromReader: true` 模式：點選片段直接 `Navigator.of(context).pop(jumpTarget)`。
- `ReaderScreen` 接收到 `jumpTarget` 後，直接就地執行跳轉與暫態高亮（Foliate: `FoliateReaderView.showSearchHighlight`／`jumpToLocator`；PDF: `PdfReaderView.jumpToPage`／`showTemporaryHighlight`），並啟動 3 秒計時器清除高亮（重用 Issue 5 邏輯）。

**單元測試要求：**
- `ReaderScreen` widget test：點擊 `reader_chrome_search_button` 驗證推入 `BookSearchScreen`。
- 跳轉與高亮測試：模擬 `BookSearchScreen` 回傳 `ReaderJumpTarget`，驗證 `ReaderScreen` 正確呼叫底層 view 執行跳轉與暫態高亮，且不重新初始化整個閱讀畫面。

**驗收標準：** `flutter analyze` 乾淨；上述測試全數通過；閱讀器頂部搜尋按鈕不再顯示「功能開發中」，點擊能開啟本書搜尋並於選取後立即跳轉至目標文字處。
