# Epic 17 — EPUB 渲染引擎遷移評估：工單清單 (Issues)

依 `design.md`（`tmp/epic-17/reviews/design-review.md` 審查修正）拆解出的工單。Issue 1 為 Discovery 階段的前置技術驗證 Spike（已完成，GO）。Issue 2 起依 `spec.md`／[ADR 0011](../../adr/0011-epub-reflowable-migrate-to-foliate-js.md) 拆解 Phase 1（流式 EPUB 遷移）的垂直切片工單，經 `/to-issues` 與人類確認拆分方式定案：Issue 2（資料層基礎建設）與 Issue 7（劃線/備註 Spike）可立即平行開始；Issue 3 依賴 Issue 2；Issue 4、5、6 依賴 Issue 3；Issue 8 依賴 Issue 3 與 Issue 7；Issue 9（收尾）依賴 Issue 2-8 全部完成。

---

## Issue 1：Spike——`readest/foliate-js` 真機直排分頁穩定性驗證

**Status:** ✅ 已完成。依 `plans/plan-issue-1.md` Task 1-5 完成 Harness 建置、真機插樁量測與判準分類，結論寫入 `reviews/spike-foliate-js-vertical.md`。以釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`（2026-07-19）打包的 `readest/foliate-js`，在真機 Android WebView（`3CEF42ECD491687`，Android 15／API 35）上對 `issue9_vertical_pagejump.epub` 正文段落連續觸發 3 次「下一頁」+ 3 次「上一頁」：6 次觸發皆可視內容無縫銜接、內部 `fraction` 皆為預期單步變化（無多步跳躍、無 0 步被吃掉），且往返路徑以截圖逐位元組比對（`prev-1≡next-2`、`prev-2≡next-1`、`prev-3≡start`）證實完全對稱。依 `design.md`「判準」表分類為**通過**，構成 **GO** 訊號。**下一步進入 Architecting 階段**，撰寫 `spec.md`，並重新逐項確認 `foliate-js-migration-feasibility-assessment.md` 既有的 6 項共識決策。Harness throwaway 專案已從裝置解除安裝，過程中的暫時性素材（截圖、logcat、Harness Android 專案）皆位於 `tmp/`（已 gitignore），未進版控。

**依賴：** 無（起始工單，可立即開始）

**描述：**

`design.md` 已確認「直排繁體中文上下翻頁跳頁」是 Readium 生態系已知、且官方已擱置的缺口（`readium/kotlin-toolkit#458`、`readium/css#141`），非本專案整合問題。`foliate-js`（`readest/foliate-js` fork）是候選替代方案，但是否值得投入完整遷移，取決於它在真機 Android WebView 上能否穩定處理直排分頁——這正是本工單要驗證的唯一問題。

本工單為一次性研究/驗證工作，產出是一份判定報告與明確的 GO/NO-GO 結論，不是長期功能程式碼：

- **Harness 建置**：新建一個獨立、throwaway 的最小 Android 專案（單一 `Activity` + 單一 `android.webkit.WebView`），不屬於 `app/`、不修改 `app/` 下任何檔案。
  - 打包 `readest/foliate-js` 的必要 JS/CSS assets 與一個最小 HTML 載入頁面（比照 `foliate-js-migration-feasibility-assessment.md` 3.1 節設想的靜態資源打包方式）。
  - 釘定 `readest/foliate-js` 特定 Git commit SHA 打包，不追蹤 main 分支最新狀態，確保結果可重複驗證。
  - 配置 `WebViewAssetLoader` 或啟用 `setAllowFileAccessFromFileURLs(true)`（僅限本 throwaway spike），避免 `file://` 同源政策擋下動態 `import()`/`fetch()` 讀取的 EPUB 內容（zip 內字型/圖片/XHTML/CSS）。
  - Harness 需能：載入本機 EPUB 檔案、切換為 `vertical-rl` 排版、提供「上一頁」/「下一頁」兩個可程式化觸發的操作（畫面按鈕或可由 `adb shell input tap` 觸發的固定座標元件即可）。
- **重現素材**：沿用 `app/test/fixtures/issue9_vertical_pagejump.epub`（與 `epic-7-interaction` Issue 9 spike 同一份素材，確保可與既有 Readium 基準直接比較）。
- **觸發量測**：排版方向固定 `vertical-rl`；選擇有正文內容的章節頁面；至少連續 3 次「下一頁」+ 至少連續 3 次「上一頁」單次觸發，每次觸發間隔足夠時間讓畫面穩定。每次觸發前後記錄：(a) 可視內容是否連續——操作型定義為「翻頁前畫面最後一個字/詞，是否與翻頁後畫面第一個字/詞無縫銜接」；(b) `foliate-js` 內部分頁進度指標（`Paginator`/`View` 暴露的頁碼或位置狀態）前後值。
- **判準**（見 `design.md`「Spike 驗證方法與判準」）：
  - **通過**：所有觸發皆內容連續、內部分頁位置皆單步變化 → GO 訊號。
  - **計數器層級抖動（不算失敗）**：內容連續，但周邊計數器（頁碼標籤/總頁數）不同步 → 仍視為 GO 訊號，但記錄為已知殘留風險。
  - **失敗**：任一次觸發內容真正跳過/重複、或內部分頁位置多步跳躍、或觸發被吃掉（0 步變化） → NO-GO 訊號。
- **GO/NO-GO 決策路徑**：
  - GO（通過或計數器抖動）：於 `design.md` 記錄 Spike 結果，進入 Architecting 階段（撰寫 `spec.md`），本工單即算完成，不在本工單內展開架構設計。
  - NO-GO（失敗）：記錄具體失敗證據於本 Epic `reviews/`，`design.md` 補上「已評估並否決」的結論與理由，ADR 0001 維持現狀不變，Epic 標記完成並歸檔。

**單元測試要求：** 無（研究/驗證性質，比照 `epic-7-interaction` Issue 1／Issue 9 先例；過程中若產生暫時性程式碼或素材，驗證後需清理，不留在版本控制中）

**驗收標準：**
- 4 種組合中實際只需要「直排 × 上一頁」「直排 × 下一頁」兩類觸發（本 Spike 只驗證 `vertical-rl` 這個維度，見 `design.md` 決策 #1／範圍外段落），至少 3+3 次觸發皆有明確數據與結論。
- 明確依判準表分類（通過／計數器抖動／失敗），並附具體證據（截圖、DOM 文字比對、`Paginator`/`View` 前後狀態值），寫入驗證報告（建議路徑：`docs/epics/epic-17-epub-render-migration/reviews/spike-foliate-js-vertical.md`）。
- 依 GO/NO-GO 結果更新 `design.md` 對應段落；若 NO-GO，一併確認 ADR 0001 是否需要註記。
- Harness 打包的 `readest/foliate-js` commit SHA 已記錄於報告中，供未來重現。
- 過程中的暫時性程式碼/素材已清理，`git status` 乾淨（不含本 Epic 目錄下的正式文件更新）。

---

## Issue 2：資料層基礎建設——EPUB FXL/流式判斷與回填

**Status:** `ready-for-agent`

**依賴：** 無（起始工單，可與 Issue 7 平行開始）

**描述：**

Phase 1 需要在「建構閱讀器 widget 之前」就知道一本 EPUB 是固定版面（FXL）還是流式（reflowable），但現況（`isFixedLayout` 只有 Readium 開書後才回報，見 `spec.md`「模組」節）完全沒有這個資訊。本工單是純資料層/匯入管線的 prefactor 工作，本身不改變任何使用者可見行為（`ReaderScreen` 尚未接上新 widget，Issue 3 才會真正用到這裡新增的欄位）：

- **`BookMetadataChannel.kt`**：`extractEpubMetadata()`（第 215-267 行）已經呼叫 `PublicationOpener.open()` 取得完整 `Publication` 物件供標題/作者/封面萃取；新增讀取 `publication.metadata.layout == Layout.FIXED`，一併存入回傳的 map（新增 `"isFixedLayout": Boolean`），不需要新的解析路徑。
- **`BookMetadataChannel.kt`**：新增方法 `detectEpubLayout(path, result)`，與 `extractEpubMetadata()` 共用同一套 `AssetRetriever`/`PublicationOpener` 開檔模式，但跳過封面點陣圖解碼（最耗時的部分），只讀 `publication.metadata.layout`，比照 `extractEpubMetadata()` 既有的 `try { ... } finally { publication.close() }` 慣用語法確保例外情況下仍會關閉，回傳 `{"isFixedLayout": Boolean}`。
- **`sqlite_library_repository.dart`**：`books` 資料表 schema migration 至 version 11，新增 `is_fixed_layout INTEGER`（nullable：`NULL`=尚未判斷、`0`=流式、`1`=FXL），比照既有 `if (oldVersion < N)` 累加式慣例，僅在表已存在時執行 `ALTER TABLE`。`Book` model 對應新增 `bool? isFixedLayout` 欄位。
- **`book_import_service_impl.dart`**：`_importSingleFile()` 呼叫 `extractMetadata` 後，把回傳 map 新增的 `isFixedLayout` 欄位一併寫入建構出的 `Book`（`format == BookFormat.epub` 時才有此欄位，PDF/TXT 為 `null`，語意上不適用）。
- **既有書籍回填流程的呼叫入口**（不含 `ReaderScreen` 實際接線，那是 Issue 3 的範圍）：`LibraryRepository` 新增一個方法（例如 `detectAndCacheEpubLayout(bookId, filePath)`），呼叫 `detectEpubLayout` method channel 取得結果後寫回資料庫對應列的 `is_fixed_layout` 欄位。

**單元測試要求：**
- `Book` model 新增 `isFixedLayout` 欄位的 `copyWith`／`==`／`hashCode`。
- `sqlite_library_repository.dart` schema migration（v10→v11）round-trip：新裝置直接建表含新欄位且可讀寫；既有裝置升級後既有資料列 `is_fixed_layout` 為 `NULL`（比照既有 migration 測試模式）。
- `book_import_service_impl.dart`：匯入 EPUB 時 mock method channel 回傳 `isFixedLayout: true/false`，驗證寫入的 `Book` 物件對應欄位正確；PDF/TXT 匯入路徑不受影響（欄位維持 `null`）。
- `LibraryRepository.detectAndCacheEpubLayout()`：mock method channel 回傳結果後，驗證資料庫對應列被正確更新。

**驗收標準：**
- 上述測試皆通過。
- `flutter analyze` 乾淨。
- JVM 單元測試：若 `detectEpubLayout` 的開檔/關閉邏輯抽出可測的純邏輯，補上對應測試；否則至少確認 `./gradlew :app:testDebugUnitTest` 既有測試不受影響。
- 本工單不需要真實裝置即可驗收（`AssetRetriever`/`PublicationOpener` 呼叫可透過既有測試替身模式驗證，比照 `extractEpubMetadata` 既有測試慣例）。

---

## Issue 3：核心 Widget 建置——`FoliateEpubReaderView` 開書渲染

**Status:** `ready-for-agent`

**依賴：** Issue 2

**描述：**

本工單是 Phase 1 第一個使用者可見的垂直切片：真實圖書庫匯入的流式 EPUB，改由 `readest/foliate-js` 渲染出內容（尚無排版設定、換頁、目錄、劃線——這些是後續 Issue 4-8 的範圍）。

- **`FoliateEpubReaderView.kt` + `FoliateEpubReaderViewFactory.kt`**（新增，比照 `EpubReaderView.kt`/`EpubReaderViewFactory.kt` 對稱檔名慣例）：`PlatformView` 實作，單一 `android.webkit.WebView`，透過 `WebViewAssetLoader` 載入釘定 commit（`dd71f2be356563c16a23272686189fcfb45d0b82`）的 `readest/foliate-js`（8 個檔案，複製進 `app/android/app/src/main/assets/foliate/`，進版控，比照 `plans/plan-issue-1.md` Task 2 已驗證清單，不引入 Node 建置工具鏈）。
- **任意裝置路徑 `PathHandler`**：`AssetsPathHandler` 只服務 `assets/` 底下內容，需新增/自訂支援讀取使用者實際匯入、儲存在 App 私有目錄任意路徑下 EPUB 檔案的 `PathHandler`。**安全要求**：`handle(path)` 實作必須對請求路徑做正規化檢查（例如 `File(requestedPath).canonicalPath.startsWith(appFilesDir.canonicalPath)`），拒絕解析後落在允許目錄之外的請求，防止路徑穿越——`PathHandler` 服務的請求來自 WebView 內 JS（`foliate-js` 本身或書本內容），不可假設請求路徑必然合法。
- **`.js` MIME 類型覆寫**：比照 Spike 已驗證的 `shouldInterceptRequest` 對 `.js` 路徑明確覆寫為 `text/javascript`（`plans/plan-issue-1.md` Task 1 已驗證機制）。
- **`MainActivity.kt`**：新增 `viewType` 註冊 `cc.ugotit.elinkbook/foliate_epub_reader_view`；`FoliateEpubReaderView` 建構子／`dispose()` 呼叫 `ReaderViewAttachmentTracker.attach()`/`detach()`（比照 `EpubReaderView`/`PdfReaderView` 既有慣例，音量鍵攔截計數器與渲染引擎無關）。
- **`main.js`**（`assets/foliate/`）：`makeBook()` + `view.open(book)` + `await view.init({})`（比照 Spike 已驗證的兩段式呼叫與時序理由，`plans/plan-issue-1.md` Task 2 註解）；`onPageRendered`/`onError` 對稱既有契約。
- **`app/lib/reader/foliate_epub_reader_view.dart`**（新增）：公開建構參數與既有 `EpubReaderView` 對稱（本工單先做 `filePath`／`onPageRendered`／`onError`／`onLayoutResolved`——`onLayoutResolved` 本 widget 恆回傳 `isFixedLayout: false`），其餘偏好/換頁/目錄/劃線參數留待 Issue 4-8 補上。
- **`ReaderScreen`**：新增分支——讀取 `widget.book.isFixedLayout`；若為 `null`（既有書籍），呼叫 Issue 2 新增的 `detectAndCacheEpubLayout()` 一次性判斷並回寫；依結果決定建構 `EpubReaderView`（`true`）或 `FoliateEpubReaderView`（`false`）。PDF/TXT 路徑（`detectBookFormat()`）完全不受影響。

**單元測試要求：**
- `foliate_epub_reader_view.dart` widget test：比照既有 `epub_reader_view_test.dart` 結構，透過 mock method channel 驗證 `openBook` 呼叫、`onPageRendered`/`onError` 回呼正確轉發。
- `ReaderScreen` widget test：`isFixedLayout == true` 建構 `EpubReaderView`；`isFixedLayout == false` 建構 `FoliateEpubReaderView`；`isFixedLayout == null` 觸發 `detectAndCacheEpubLayout()` 呼叫且依非同步回傳結果建構對應 widget。
- JVM 單元測試：`PathHandler` 路徑正規化檢查的邊界案例（合法路徑、`../` 穿越嘗試、符號連結指向允許目錄外——依實際實作方式挑選可測的純邏輯抽出測試）。

**驗收標準：**
- 上述測試皆通過。
- `flutter analyze` 乾淨、`./gradlew :app:testDebugUnitTest` 全過。
- `integration_test`（真實裝置）：真實圖書庫「匯入書籍」流程匯入一本流式 EPUB，開啟後由 `FoliateEpubReaderView` 成功渲染出內容（比照既有 `Key('reader_loading_indicator')`／`Key('reader_error_text')` 觀察慣例，非直接掛 callback）；已存在的 FXL 書籍開啟行為不受影響（仍由 `EpubReaderView`/Readium 處理）。
- 真機驗證 `PathHandler` 路徑穿越防護：嘗試以精心構造的路徑請求存取允許目錄外的檔案，確認被拒絕。

---

## Issue 4：排版方向與版面偏好設定

**Status:** `ready-for-agent`

**依賴：** Issue 3

**描述：**

- **雙向 `writing-mode` CSS 覆蓋**：`main.js` 透過 `book.transformTarget` 的 `'data'` 事件在 CSS 資源解析前附加覆蓋規則（比照 Spike 已驗證的注入時序，`plans/plan-issue-1.md` Task 3 註解），依目前 `writingMode` 偏好注入 `vertical-rl` 或 `horizontal-tb`——**Spike 只驗證了強制直排這一個方向**，本工單需額外驗證強制橫排（覆蓋書本自己宣告的 `vertical-rl`）同樣可靠。
- **FR-06 自動判斷**：`openBook` 時不主動送出 `writingMode` 覆蓋（比照 ADR 0003 既有原則）；原生端讀取書本第一個 section 的 CSS 是否已宣告 `writing-mode`／`-epub-writing-mode`（透過 `transformTarget` 攔截到的原始 CSS 文字做字串/正規表達式檢查）；有宣告就尊重書本自己的值並回報給 Dart（比照 ADR 0003 `onWritingModeResolved` 對稱位置）；判斷不出來則預設橫排。**不使用書本 `language` metadata 做語言猜測**。
- **`setPreferences` 批次送出**：既有 10 項偏好參數（`writingMode`／`pageTurnMode`／`fontFamily`／`fontSize`／`fontWeight`／`lineHeight`／`paragraphSpacing`／`pageMargins`／`textAlign`／`publisherStyles`）完整移植到 `foliate_epub_reader_view.dart` 的建構參數與 `_buildPreferencesMap()`，原生端透過 JS 橋接把對應 CSS 屬性/選項套用到 `foliate-js` 的 renderer。`pageTurnMode == scroll` 時原生端行為對應 `flow: 'scrolled'`（`view.renderer.setAttribute('flow', ...)`）。

**單元測試要求：**
- 字串/正規表達式判斷 CSS 是否已宣告 `writing-mode`：含宣告與不含宣告兩種輸入的邊界測試。
- `foliate_epub_reader_view.dart`：`didUpdateWidget` 偵測到偏好變動時送出 `setPreferences`，比照既有 `_preferencesChanged()` 測試模式。

**驗收標準：**
- 上述測試皆通過、`flutter analyze` 乾淨。
- `integration_test`（真實裝置）：
  - 用一份書本自己宣告 `writing-mode: vertical-rl` 的素材開書，確認初始即為直排（不需使用者手動切換）。
  - 用一份完全不宣告 `writing-mode` 的素材（例如 Spike 既有 `issue9_vertical_pagejump.epub`）開書，確認初始為橫排。
  - 手動切換橫排→直排、直排→橫排皆正確即時生效（不重新開書）。
  - 字型/字級/行距等既有偏好設定套用後畫面正確反映變更。

---

## Issue 5：換頁與 3×3 導航熱區

**Status:** `ready-for-agent`

**依賴：** Issue 3

**描述：**

- **`nextPage`／`previousPage`**：`foliate_epub_reader_view.dart` 新增對稱既有 `EpubReaderView.nextPage`/`previousPage` 的強型別 static helper，原生端呼叫 `view.next()`/`view.prev()`。
- **3×3 導航熱區**：**不在原生端判讀**——`foliate_epub_reader_view.dart` 直接複用 `epic-7-interaction` 為 FXL 建立的「Dart 端 `Stack` 兄弟節點疊加 `GestureDetector`」模式與既有 `hitTestZoneIndex()` 純函式（見該 epic `spec.md`「介面」節），`navZoneActions`／`onZoneAction`／`showNavZoneDebugOverlay` 三個建構參數的處理方式與現有 `EpubReaderView` 的 FXL 分支邏輯相同。原生端 `FoliateEpubReaderView.kt` 完全不需要移植 `NavZoneHitTester.cellIndex()` 或 `InputListener` 註冊邏輯。
- **`jumpToProgression`**：新增對稱既有 static helper，原生端呼叫 `view.goToFraction(progression)`。
- **`ReaderScreen._handleZoneAction`**：新增流式 `foliate-js` 分支，接上 `onZoneAction`（與 FXL 分支邏輯相同，複用同一個分派入口）。

**單元測試要求：**
- `foliate_epub_reader_view.dart` widget test：9 個 `Key('nav_zone_$index')` widget 存在且可點擊，點擊後觸發 `onZoneAction` 回呼、傳入正確的 `ZoneAction`（比照 `EpubReaderView` FXL 分支既有測試模式）。
- `ReaderScreen` widget test：流式 `foliate-js` 開書後點擊選單格觸發沉浸模式切換；翻頁動作不影響沉浸模式狀態（design.md 決策 #14 一致性）。

**驗收標準：**
- 上述測試皆通過、`flutter analyze` 乾淨。
- `integration_test`（真實裝置）：9 格熱區逐一點擊觸發正確換頁/沉浸模式切換；「無動作」格正確攔截觸控（不穿透到底層 WebView）。

---

## Issue 6：目錄跳轉與定位持久化／頁碼顯示

**Status:** `ready-for-agent`

**依賴：** Issue 3

**描述：**

- **`getTableOfContents`**：原生端讀 `book.toc`，透過 `book.resolveHref(item.href)` 取得 `{index, anchor}` 建構可跳轉的定位，序列化為現有 `TocEntry` wire 格式（Dart 端型別完全重用，不新增）。
- **`jumpToLocator`**：新增對稱既有 static helper，原生端解析傳入的新格式 JSON（見下）取出 `cfi` 後呼叫 `view.goTo(cfi)`。**跳轉精度驗收**（原「待驗證風險」#4，併入本工單驗收標準，不另立 Spike）：FR-08 200ms 時限內完成跳轉、跳轉後畫面內容與目錄項目對應章節/段落一致。
- **新增定位 JSON 格式**（僅供本 widget 使用，與 Readium `Locator.toJSON()` 完全不同、不相容）：
  ```json
  { "cfi": "epubcfi(/6/8!/4[story-2-2],/60/3:32,/70/1:32)", "index": 3, "fraction": 0.042091 }
  ```
  對應 `relocate` 事件（`view.js` `#onRelocate()`）回傳的 `cfi`／`index`／`fraction` 三欄位。`onLocatorChanged`／`initialLocatorJson` 的 `locatorJson: String` 欄位裝的就是這段 JSON 序列化後的字串，Dart 端 `EpubPositionInfo` 型別簽章不變。
- **舊格式資料的優雅退回**：`initialLocatorJson` 若是既有流式書籍留下的 Readium Locator JSON（ADR 0011 已接受視為失效），原生端解析新格式失敗時，**不拋出例外**，視為「無既有位置記錄」、從書本開頭開始（比照設計文件「已知限制」段落）。
- **頁尾頁碼**：`onLocatorChanged` 新增欄位（或 `EpubPositionInfo` 擴充 `pageIndex`/`totalPages`，加法性擴充不影響既有呼叫端）帶出 `relocate` 事件內建的 `location.current`／`location.total`（`SectionProgress.getProgress()`）；**不送出 `totalCharacterCount`、不呼叫任何字數統計**（`EpubCharacterCounter` 完全不適用本 widget）。

**單元測試要求：**
- 新格式 JSON 序列化/反序列化 round-trip。
- 舊格式（Readium Locator JSON 樣式）解析失敗時的優雅退回邏輯（不拋例外、視為無記錄）。
- `foliate_epub_reader_view.dart`：`onLocatorChanged`/`onCharacterCountReady`（本 widget 不觸發，確認呼叫端不會誤判）。

**驗收標準：**
- 上述測試皆通過、`flutter analyze` 乾淨。
- `integration_test`（真實裝置）：目錄樹狀清單顯示正確、點擊項目 200ms 內跳轉至對應內容；`ReaderFooter` 頁碼顯示正確反映 `location.current`/`total`；用一份帶有舊格式（Readium）`initialLocatorJson` 的既有流式書籍開書，確認不崩潰、從書本開頭開始（驗證 ADR 0011「既有資料視為失效」的優雅退回）。

---

## Issue 7：Spike——劃線/備註可行性驗證（`overlayer.js`）

**Status:** ✅ 已完成。依 `plans/plan-issue-7.md` Task 1-6 完成 Harness 建置、`readest/foliate-js`（釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`）真機插樁驗證與結論收斂，結論寫入 `reviews/spike-overlayer-annotations.md`。在真機 Android WebView（`3CEF42ECD491687`，Android 15／API 35）上，三項研究問題**皆得到正面驗證**：(1) `Overlayer.highlight`/`underline` 的多色螢光筆＋獨立底線子類型繪製正確（顏色可辨、底線方向以 SVG 幾何屬性客觀證實為垂直方向）；(2) 選取範圍的螢幕座標百分比換算公式正確，經真機原生長按拖曳手勢與程式化退路雙重交叉驗證通過；(3) 點擊既有標記可靠觸發 `show-annotation` 並識別正確 CFI（4/4 全數通過、負面對照無誤判）。過程中發現並修正兩個真實的既有 API 陷阱（皆非顯而易見、需真機執行＋Chrome DevTools Protocol 即時檢視才能定位）：CFI round-trip 會把 `selectNodeContents(element)` 產生的元素層級 Range 靜默壓扁成 collapsed（改用文字節點邊界建構 Range 解決）；`'load'` 事件對 look-ahead 預讀章節同樣會觸發，導致依賴該事件快取的模組級變數讀到錯誤/非可見的 doc（改用 `view.lastLocation` 即時查詢解決，在兩條獨立程式碼路徑上各自獨立重現，屬系統性風險）。另發現一項非 `Overlayer` 本身缺陷、但對正式 App 熱區設計有意義的整合風險：導覽熱區與可標記內容區域重疊時會攔截點擊，事件根本傳不到 `hitTest()`。**結論：ADR 0011（劃線/備註完整涵蓋在 Phase 1 範圍）維持不變，不需要人類重新確認範圍**；但 Issue 8 必須把上述兩個 API 陷阱的修正方式與熱區設計提醒當作硬性實作約束，避免重蹈覆轍，詳見報告「風險分級與後續建議」一節。Harness throwaway 專案已從裝置解除安裝，過程中的暫時性素材（截圖、logcat、Harness Android 專案）皆位於 `tmp/`（已 gitignore），未進版控。

**依賴：** 無（可與 Issue 2 平行開始）

**描述：**

`spec.md`「待驗證風險與收斂關卡」#1，本 Epic 風險最高、完全沒有 Spike 證據的單一項目。`readest/foliate-js` 有 `overlayer.js`（`Overlayer` 類別），概念上對應 Readium 的 `Decorator`（在頁面上疊加任意 SVG 元素、`hitTest()` 判斷點擊），但這次 `plans/plan-issue-1.md` 的 Spike 完全沒有驗證過。本工單延續 `plans/plan-issue-1.md` 建立的 throwaway harness 模式（不修改 `app/`），驗證：

- **多色劃線＋獨立螢光筆子類型**：`Overlayer.add(key, range, draw, options)` 的 `draw` callback 能否依 `tint`（ARGB 色值）與 `isUnderline`（畫底線 vs 半透明矩形背景）畫出對應視覺，比照現有 `EpubDecoration` 欄位語意。
- **選取範圍即時回報座標**：使用者原生選字手勢建立/變動選取範圍時，能否即時取得對應的螢幕座標百分比（供浮動工具列定位，比照現有 `onSelectionChanged` 的 `PercentRect` 格式），`foliate-js` 側的 `Range`/`getBoundingClientRect()` 換算方式。
- **點擊既有標記觸發回呼**：`Overlayer.hitTest(event)` 的實際回傳形狀與可靠度，能否可靠對應到被點擊的具體標記 id。

**單元測試要求：** 無（研究/驗證性質，比照 Issue 1 先例；過程中若產生暫時性程式碼或素材，驗證後需清理，不留在版本控制中）

**驗收標準：**
- 上述 3 項問題皆有明確結論與證據（真機截圖、DOM/JS 主控台觀察），寫入驗證報告（建議路徑：`docs/epics/epic-17-epub-render-migration/reviews/spike-overlayer-annotations.md`）。
- 若任一項驗證結果顯示 `overlayer.js` 無法滿足現有劃線/備註視覺與互動需求，需在報告中明確記錄具體落差與可能的替代做法，供 Issue 8 依循（不得由 Issue 8 實作者在工單執行階段才發現並自行決定退回方案）；若落差嚴重到可能動搖「劃線/備註完整涵蓋在 Phase 1」這個既有決策（ADR 0011），需標記為需要人類重新確認範圍。
- 過程中的暫時性程式碼/素材已清理，`git status` 乾淨（不含本 Epic 目錄下的正式文件更新）。

---

## Issue 8：劃線與備註

**Status:** `ready-for-agent`

**依賴：** Issue 3、Issue 7

**描述：**

依 Issue 7 的驗證結論，把流式 EPUB 的劃線/備註功能對接到 `foliate-js` 的 `overlayer.js`：

- **`setDecorations`**：把目前應顯示的完整標記清單一次性送給原生端（比照既有整組送出慣例，非增量 diff），原生端解析 `EpubDecoration.locatorJson`（新 CFI 格式）為 `foliate-js` 的 CFI 物件（`CFI.parse()`），透過 `Overlayer.add()` 疊加。
- **`onSelectionChanged`／`onSelectionCleared`**：使用者原生選字手勢建立/變動/清除選取範圍時觸發，`locatorJson` 為新格式、`rect: PercentRect` 依 Issue 7 驗證出的座標換算方式。
- **`onAnnotationActivated`**：使用者點擊既有標記時觸發，傳回該筆標記的 id 字串（沿用既有 `EpubDecoration.forHighlight`/`forNote` 編碼慣例與 `decodeAnnotationId()` 解析函式，完全不需要修改）。
- **`ReaderScreen`**：流式 `foliate-js` 分支接上上述三個回呼，複用既有的浮動工具列/編輯 Dialog 邏輯（`epic-6-annotations` 既有元件，非本工單新增）。

**單元測試要求：**
- `foliate_epub_reader_view.dart`：mock method channel 驗證 `onSelectionChanged`/`onSelectionCleared`/`onAnnotationActivated` 正確解析與轉發；`setDecorations` 正確序列化 `EpubDecoration` 清單。
- JVM 單元測試：CFI 解析與 `Overlayer.add()` 呼叫的橋接邏輯（若抽出可測的純邏輯）。

**驗收標準：**
- 上述測試皆通過、`flutter analyze` 乾淨。
- `integration_test`（真實裝置，比照 `epic-6-annotations` 既有 `epub_highlights_notes_test.dart` 涵蓋範圍）：新增劃線（三色＋螢光筆）、新增備註、點擊既有標記觸發編輯、直排/橫排切換時劃線/備註視覺一致（FR-13/14/15/16 對流式 EPUB 的既有驗收標準，換引擎後行為等價）。

---

## Issue 9：真機端到端驗證與收尾

**Status:** `ready-for-agent`

**依賴：** Issue 2、3、4、5、6、7、8 全部完成

**描述：**

比照 `epic-7-interaction` Issue 8、`epic-16-dual-page` Issue 7 既有模式，本工單為 Phase 1 的整合驗證與收尾：

- **端到端組合驗證**：真實圖書庫匯入多本不同結構的流式 EPUB（含/不含自身 `writing-mode` 宣告、含/不含既有劃線備註），驗證開書、換頁、熱區、排版切換、目錄跳轉、劃線/備註、頁碼顯示全部正確運作。
- **既有書籍回填流程實測**：用 Phase 1 上線前已匯入（`is_fixed_layout` 為 `null`）的既有流式 EPUB 書籍實測 `detectAndCacheEpubLayout()` 一次性判斷與回填正確，第二次開書不再重複判斷。
- **FXL 路徑不受影響**：抽測既有 FXL EPUB 開書行為與 Phase 1 上線前一致（`EpubReaderView.kt`/Readium 完全未修改）。
- 彙整驗證紀錄，更新 `docs/epics.md` 狀態列，若驗證中發現需要後續處理的落差，比照既有慣例另立後續 issue 追蹤，不阻塞本 Phase 1 收尾。

**單元測試要求：** 無新增自動化單元測試（本工單以整合/裝置驗證為主）

**驗收標準：**
- 端到端組合驗證產出書面紀錄（比照 `qa-issue-N-*.md` 既有慣例）。
- `flutter analyze` 乾淨、`flutter test` 全數通過、`./gradlew :app:testDebugUnitTest` 全過。
- 若有發現需要後續處理的落差，已建立對應的後續 issue 追蹤，不阻塞本 Phase 1 收尾。
