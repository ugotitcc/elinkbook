# Epic 17 — EPUB 渲染引擎遷移（Phase 1：流式 EPUB）：規格 (Spec)

這是實作 `epic-17-epub-render-migration` Phase 1 的唯一事實來源。決策的完整討論過程與理由請見 `design.md`（Discovery）與 `/grill-with-docs` 逐項確認記錄；架構決策見 [ADR 0011](../../adr/0011-epub-reflowable-migrate-to-foliate-js.md)（取代 ADR 0001 對流式 EPUB 的渲染引擎決策）。

> **範圍界定**：本文件只涵蓋 Phase 1——**流式（reflowable）EPUB** 改用 `readest/foliate-js`（釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`，見 `reviews/spike-foliate-js-vertical.md`）。**FXL（固定版面）EPUB 完全不受影響，繼續使用現有 `EpubReaderView.kt`（Readium）**，該檔案本次不修改。

## 模組 (Modules)

- **`BookMetadataChannel.kt`（異動，`extractEpubMetadata()`，第 215-267 行）**——匯入時已經呼叫 `PublicationOpener.open()` 取得完整 `Publication` 物件供標題/作者/封面萃取；本次新增讀取 `publication.metadata.layout == Layout.FIXED`，一併存入回傳的 map（新增 `"isFixedLayout": Boolean`）。**這是免費取得的資訊**——不需要另外寫一個與兩套渲染引擎皆無關的 OPF 解析器（`/grill-with-docs` 討論當下的假設，經查證後修正：Readium 的 `Publication` 本來就已經在這裡被建構，多讀一個既有欄位即可，不需要新程式碼路徑）。
- **`BookMetadataChannel.kt`（新增方法 `detectEpubLayout(path, result)`）**——供「補判斷」情境使用（見下方 Data Model「既有書籍回填」）：與 `extractEpubMetadata()` 共用同一套 `AssetRetriever`/`PublicationOpener` 開檔模式，但**跳過封面點陣圖解碼**（`extractEpubMetadata()` 最耗時的部分），只讀 `publication.metadata.layout`，比照 `extractEpubMetadata()` 既有的 `try { ... } finally { publication.close() }` 慣用語法（第 239-258 行），確保解析過程拋出例外時仍會關閉 `publication`、不洩漏檔案控制代碼/解包串流，回傳 `{"isFixedLayout": Boolean}`。
- **`book_import_service_impl.dart`（異動）**——`_importSingleFile()` 呼叫 `extractMetadata` 後，把回傳 map 新增的 `isFixedLayout` 欄位一併寫入建構出的 `Book`。
- **`sqlite_library_repository.dart`（異動）**——`books` 資料表 schema migration 至 version 11：新增欄位 `is_fixed_layout INTEGER`（nullable，SQLite 慣例 0/1/NULL；`NULL` 語意為「尚未判斷過」，涵蓋 Phase 1 上線前已匯入的既有書籍）。`Book` model 對應新增 `bool? isFixedLayout` 欄位。
- **`FoliateEpubReaderView.kt` + `FoliateEpubReaderViewFactory.kt`（新增，比照 `EpubReaderView.kt`/`EpubReaderViewFactory.kt` 對稱檔名慣例）**——`PlatformView` 實作，單一 `android.webkit.WebView`（不含 Readium `EpubNavigatorFragment`/`FragmentFactory`），透過 `WebViewAssetLoader` 載入釘定 commit 的 `readest/foliate-js`（assets 路徑 `assets/foliate/`，8 個檔案，見 `plans/plan-issue-1.md` Task 2 已驗證清單）與待開啟的 EPUB（`assets/` 之外，透過 `WebViewAssetLoader` 額外 `PathHandler` 指向裝置端實際檔案路徑，比照 `AssetsPathHandler` 但改用 `InputStreamPathHandler`／自訂 handler 讀取任意裝置路徑，因為正式書籍不像 Spike 素材是內建 asset）。`MainActivity.configureFlutterEngine()` 新增註冊 `viewType`：`cc.ugotit.elinkbook/foliate_epub_reader_view`。
- **`MainActivity.kt`（異動）**——新的 `viewType` 註冊；`FoliateEpubReaderView` 建構子／`dispose()` 比照 `EpubReaderView`/`PdfReaderView` 既有慣例呼叫 `ReaderViewAttachmentTracker.attach()`/`detach()`（音量鍵攔截計數器與渲染引擎無關，沿用不變，見 `epic-7-interaction spec.md`「`MainActivity.kt`」段落）。
- **`app/lib/reader/foliate_epub_reader_view.dart`（新增）**——Flutter widget，公開建構參數與既有 `EpubReaderView` 完全對稱（見下方「介面」節逐一列出的方法/回呼契約），**重用既有的所有 Dart 端支援型別**（`EpubPositionInfo`／`EpubSelectionInfo`／`EpubDecoration`／`TocEntry`／`WritingMode`／`PageTurnMode`／`ZoneAction` 等）不新增任何新型別——這些型別本身只包一個 `locatorJson` 字串或既有的列舉/數值，對「這個字串現在裝的是 CFI-based JSON 而非 Readium Locator JSON」完全不知情、也不需要知情（下游的書籤/劃線/備註 repository 只當作不透明字串存取資料庫，見「已知限制」）。
- **`ReaderScreen`（異動）**——`_openBook()`（或對應的初始化流程）新增分支：讀取 `widget.book.isFixedLayout`；若為 `null`（既有書籍尚未判斷過），呼叫新的 `detectEpubLayout` method channel 一次性判斷並回寫資料庫（透過既有 `LibraryRepository` 更新機制），再決定要建構 `EpubReaderView`（`isFixedLayout == true`）還是 `FoliateEpubReaderView`（`isFixedLayout == false`）。**PDF/TXT 路徑完全不受影響**（`detectBookFormat()` 既有的副檔名判斷維持原樣，本次只在「已知是 EPUB」之後、選擇哪個 EPUB widget 之前，多這一層子判斷）。
- **`main.js`（新增，`assets/foliate/`）**——production 版本，架構與 Spike 驗證通過的版本一致（`plans/plan-issue-1.md` Task 2/3），但需擴充為完整契約實作（見「介面」節），非 Spike 當時的最小驗證版本。

## 資料模型 (Data Model)

### `books` 資料表新增欄位

```sql
-- schema version 11
ALTER TABLE books ADD COLUMN is_fixed_layout INTEGER; -- nullable：NULL=尚未判斷、0=流式、1=FXL
```

`onUpgrade` 比照既有 `if (oldVersion < N)` 累加式慣例（見 `_addHeaderFooterColumns` 等既有遷移函式），新增 `_addEpubLayoutColumn(db)`，僅在 `books` 表已存在時執行 `ALTER TABLE`。

### 既有書籍回填流程

Phase 1 上線前已匯入的 EPUB，`is_fixed_layout` 一律為 `NULL`。`ReaderScreen` 開書時偵測到 `null` → 呼叫 `detectEpubLayout` → 取得結果後：(a) 用於當次選擇 widget，(b) 透過 `LibraryRepository` 寫回資料庫，之後重開同一本書不再需要重複判斷。**這一次性判斷會建構並立即關閉一個 Readium `Publication` 物件**（與 FXL 路徑後續實際渲染時的 `Publication` 是兩個不同的實例，各自開關）——可接受的一次性成本，優於要求使用者重新匯入。

### 新增的原生↔Dart 定位資料格式（僅供 `FoliateEpubReaderView` 使用）

`FoliateEpubReaderView` 的 `onLocatorChanged`／`initialLocatorJson`／`EpubDecoration.locatorJson`／`onSelectionChanged` 之 `locatorJson` 欄位，內容改為以下 JSON 結構（**與 Readium `Locator.toJSON()` 完全不同的格式，兩者不相容，也不需要相容**——見 ADR 0011「既有流式書資料視為失效」決策）：

```json
{
  "cfi": "epubcfi(/6/8!/4[story-2-2],/60/3:32,/70/1:32)",
  "index": 3,
  "fraction": 0.042091
}
```

對應 `foliate-js` `relocate` 事件（`view.js` `#onRelocate()`）原生回傳的 `cfi`／`index`／`fraction` 三欄位（Spike `plans/plan-issue-1.md` 已驗證這三欄位的實際數值行為）。Dart 端 `EpubPositionInfo`/`EpubSelectionInfo` 兩個既有型別的 `locatorJson: String` 欄位裝的就是這段 JSON 序列化後的字串，型別簽章不變。

### `EpubDecoration` 對應到 `overlayer.js` 的欄位映射

既有 `EpubDecoration`（`id`／`locatorJson`／`tint`／`isUnderline`）欄位語意不變；`locatorJson` 改用上述新格式。原生端收到後，呼叫 JS 橋接方法解析 `cfi` 為 `foliate-js` 的 CFI 物件（`CFI.parse()`），透過 `overlayer.js` 的 `Overlayer.add(key, range, draw, options)` 疊加：`isUnderline == true` 時 `draw` 畫一條底線（顏色取 `tint`），否則畫一個半透明矩形背景（顏色取 `tint`，對應現有「螢光筆三色與純備註灰底」視覺）。

## 介面 (Interfaces)

### `FoliateEpubReaderView` Method Channel 契約（`cc.ugotit.elinkbook/foliate_epub_reader_view_$id`）

與現有 `EpubReaderView` 的契約**逐一對稱**（呼叫端 `ReaderScreen`／`foliate_epub_reader_view.dart` 不需要因為換了引擎而改變呼叫方式，只有原生端內部實作不同）：

| 方向 | 方法 | 參數/回傳 | 對照現有契約 |
|---|---|---|---|
| Dart→原生 | `openBook` | `path`／`initialPreferences`（見下）／`initialLocatorJson`（新格式）／`totalCharacterCount`（**不再送出**，見下方頁碼估算段落） | 對稱 |
| Dart→原生 | `setPreferences` | 同 `initialPreferences` 結構，新增/覆寫時整組送出（比照既有 ADR 0006「批次送出」慣例） | 對稱 |
| Dart→原生 | `jumpToProgression` | `progression: double`（全書 0-1），原生端呼叫 `view.goToFraction(progression)` | 對稱（語意不變，底層改呼叫 `foliate-js` API） |
| Dart→原生（request/response）| `getTableOfContents` | 回傳 `List<TocEntry>` 對應 wire 格式；原生端讀 `book.toc`，透過 `book.resolveHref(item.href)` 取得 `{index, anchor}` 建構可跳轉的定位 | 對稱 |
| Dart→原生 | `jumpToLocator` | `locatorJson`（新格式字串），原生端解析出 `cfi` 呼叫 `view.goTo(cfi)` | 對稱 |
| Dart→原生 | `nextPage`／`previousPage` | 無參數，呼叫 `view.next()`/`view.prev()` | 對稱 |
| Dart→原生 | `setDecorations` | `decorations: List<Map>`（`EpubDecoration.toWire()`），整組送出非增量 diff | 對稱 |
| 原生→Dart | `onPageRendered`／`onError` | 同現有語意 | 對稱 |
| 原生→Dart | `onLayoutResolved` | **本 widget 恆回傳 `isFixedLayout: false`**（`ReaderScreen` 已經在建構這個 widget 之前就確定是流式書，此回呼純粹是保留既有介面形狀，供共用的呼叫端程式碼不需要為兩種 widget 寫兩套處理） | 對稱，語意窄化 |
| 原生→Dart | `onLocatorChanged` | 新格式 JSON | 對稱，格式不同 |
| 原生→Dart | `onSelectionChanged`／`onSelectionCleared` | 同現有語意，`locatorJson` 為新格式 | 對稱 |
| 原生→Dart | `onAnnotationActivated` | 同現有語意（`EpubDecoration` 的 `id` 編碼慣例不變） | 對稱 |
| 原生→Dart | `onCharacterCountReady` | **本 widget 不觸發**（見下方頁碼估算段落） | 不適用 |

### 直排/橫排 CSS 覆蓋（雙向）

沿用 Spike 已驗證的 `book.transformTarget` 注入機制（`plans/plan-issue-1.md` Task 3），但需擴充為**雙向**（Spike 只驗證了強制直排；production 需要能強制橫排，因為 ADR 0003 的既有契約允許使用者雙向切換）：

```js
book.transformTarget?.addEventListener('data', (e) => {
  if (e.detail.type === 'text/css') {
    const override = currentWritingMode === 'vertical'
      ? 'writing-mode: vertical-rl !important;'
      : 'writing-mode: horizontal-tb !important;'
    e.detail.data = Promise.resolve(e.detail.data).then(
      (css) => `${css}\nhtml, body { ${override} }\n`,
    )
  }
})
```

**首次開書的初始值判斷（FR-06）**：`openBook` 時**不**主動送出 `writingMode` 覆蓋（比照 ADR 0003 既有「初次開書不主動設定、讓判斷結果自然呈現」原則），原生端改讀取書本自己第一個 section 的 CSS 是否已宣告 `writing-mode`（透過 `book.transformTarget` 的 `'data'` 事件攔截到的原始 CSS 文字，用正規表達式檢查是否含 `writing-mode`／`-epub-writing-mode`）；有宣告就尊重書本自己的值、透過 `onLayoutResolved` 對稱位置新增的欄位（或既有 `writingMode` 回報機制，比照 ADR 0003 `onWritingModeResolved`）回報給 Dart；判斷不出來（書本完全沒宣告）則預設橫排。**不使用書本 `language` metadata 做語言猜測**（`/grill-with-docs` 決策，比 Readium 原本的判斷邏輯更保守）。

### 3×3 導航熱區

**不在原生端判讀**——`foliate_epub_reader_view.dart` 直接複用 `epic-7-interaction` 為 FXL 建立的「Dart 端 `Stack` 兄弟節點疊加 `GestureDetector`」模式與既有 `hitTestZoneIndex()` 純函式（見該 epic `spec.md`「介面」節），`navZoneActions`／`onZoneAction`／`showNavZoneDebugOverlay` 三個建構參數的處理方式與現有 `EpubReaderView` 的 FXL 分支逐位元組相同。原生端 `FoliateEpubReaderView.kt` **完全不需要**移植 `NavZoneHitTester.cellIndex()` 或 `InputListener` 註冊邏輯。

### 頁碼估算

`openBook`／`setPreferences` **不送出** `totalCharacterCount`；原生端**不呼叫**任何字數統計。頁尾頁碼顯示改讀 `relocate` 事件內建的 `location.current`／`location.total`（`foliate-js` `SectionProgress.getProgress()`，見 ADR 0011「頁碼估算」決策），透過 `onLocatorChanged` 一併送出（新增欄位，或既有 `EpubPositionInfo` 擴充一個 `pageIndex: int?`／`totalPages: int?` 欄位——具體型別擴充方式留待實作階段依 `ReaderFooter` 既有介面需求決定，兩者皆是相容的加法性擴充，不影響既有呼叫端）。

## 待驗證風險與收斂關卡

比照 `epic-16-dual-page`／`epic-7-interaction` 慣例，以下風險須在進入 Scrum Master 拆解前以獨立 Spike 工單驗證並回填結論：

1. **`overlayer.js` 的 `Overlayer`／`hitTest()` 是否能滿足現有劃線/備註視覺與互動需求**：多色劃線＋獨立螢光筆子類型（`draw()` callback 依 `tint`/`isUnderline` 畫不同 SVG）、選取範圍即時回報座標（供浮動工具列定位，`onSelectionChanged` 的 `rect: PercentRect` 現有格式如何從 foliate-js 的 `Range`/`getBoundingClientRect()` 換算）、點擊既有標記觸發 `onAnnotationActivated`（`Overlayer.hitTest(event)` 的實際回傳形狀與可靠度）。**完全沒有 Spike 證據**，是 Phase 1 範圍內風險最高的單一項目。
2. **CSS 覆蓋雙向切換的實際可靠度**：Spike 只驗證了「強制直排」，「強制橫排」（覆蓋書本自己宣告的 `vertical-rl`）需要額外真機驗證；此外「開書當下讀取書本 CSS 判斷是否已宣告 `writing-mode`」的正規表達式判斷方式需要用真實含 `writing-mode` 宣告的 EPUB 素材驗證（本次 Spike 素材恰好沒有宣告，需另外找/製作一份會宣告的測試素材）。
3. **`WebViewAssetLoader` 讀取裝置端任意路徑（非內建 asset）EPUB 檔案的 `PathHandler` 實作**：Spike 只驗證了 EPUB 素材本身是內建 assets；production 需要讀取使用者實際匯入、儲存在 App 私有目錄任意路徑下的檔案，`AssetsPathHandler` 本身只服務 `assets/` 底下的內容，需要改用或新增支援任意檔案路徑的 `PathHandler` 實作（`androidx.webkit` 是否有現成的、或需要自訂）。**安全要求（審查採納項目）**：自訂 `PathHandler` 的 `handle(path)` 實作必須對請求路徑做正規化檢查（例如 `File(requestedPath).canonicalPath.startsWith(appFilesDir.canonicalPath)`），拒絕解析後落在允許目錄之外的請求，防止路徑穿越（path traversal）——`PathHandler` 服務的請求來自 WebView 內 JS（`foliate-js` 本身或書本內容），不可假設請求路徑必然合法。
4. **`book.toc`／`resolveHref()` 建構的目錄跳轉定位精度**：現有 `getTableOfContents` 透過 Readium `Publication.locatorFromLink()` 為每個目錄節點建構含錨點精度的 Locator（`epic-5-toc-pagination` Issue 4 決策）；`foliate-js` 對等的 `book.resolveHref(item.href)` 是否能達到相同精度（FR-08 200ms 時限跳轉），需要真機驗證。

若上述任一項驗證結果與本文件假設不符，對應段落需在 Spike 完成後更新，不得由實作者在工單執行階段自行決定退回方案。

## 測試決策 (Testing Decisions)

### 1. 單元測試（`flutter test`，無需裝置）
- `Book` model 新增 `isFixedLayout` 欄位的 `copyWith`／`==`／`hashCode`。
- `sqlite_library_repository.dart` schema migration（v10→v11）round-trip：新裝置直接建表含新欄位；既有裝置升級後既有資料列 `is_fixed_layout` 為 `NULL`。
- `foliate_epub_reader_view.dart` widget test：比照現有 `epub_reader_view_test.dart` 既有測試結構（透過 mock method channel 驗證 `openBook`／`setPreferences` 送出的 map 內容、`onLocatorChanged`/`onSelectionChanged` 等回呼正確解析新格式 JSON）。

### 2. JVM 單元測試（Kotlin，比照 `PdfImageProcessor`/`EpubFxlScaler` 抽離慣例）
- 若 CSS `writing-mode` 偵測正規表達式抽成獨立純函式，針對含/不含宣告的 CSS 文字各補測試案例。

### 3. Widget 測試
- `ReaderScreen`：`isFixedLayout == null`（既有書籍）觸發 `detectEpubLayout` 呼叫並依結果建構對應 widget；`isFixedLayout` 非 null 時直接依值建構、不呼叫偵測。

### 4. `integration_test`（真機，`-d <device-id>`）
- 開書、換頁、直排/橫排雙向切換、目錄跳轉、劃線/備註新增與點擊、書籤新增，比照現有 `epub_*_test.dart` 系列既有涵蓋範圍逐項對應驗證。
- FR-06 自動判斷：分別用「書本自己宣告 `writing-mode`」與「完全不宣告」兩份素材驗證初始排版方向正確。

## 已知限制

- **既有流式 EPUB 書籍的書籤/劃線/備註/閱讀進度視為失效**（ADR 0011 已接受的已知風險）——`is_fixed_layout` 回填流程只解決「這本書該用哪個引擎開」，不解決「這本書舊有的定位資料還讀不讀得懂」；`bookmarks`／`highlights`／`notes`／`books.epubLocator` 資料表中，屬於流式 EPUB 的既有列會在下次開書時被實質忽略（原生端拿到不是 CFI 格式的字串，解析失敗，等同無此筆記錄），不會清除資料庫記錄本身、也不主動提示使用者。
- **`FoliateEpubReaderView.kt` 與 `EpubReaderView.kt` 是兩份完全獨立、無共用程式碼的原生實作**（ADR 0011 決策）——兩者對「同一份 Dart 端型別」（`EpubDecoration`／`TocEntry` 等）的解析邏輯需要人工保持語意一致，未來若其中一方修改欄位語意，須同步檢查另一方。
- **`EpubCharacterCounter.kt`／`EpubPageEstimator` 兩個模組僅在 FXL 路徑（Readium）繼續存在**——`FoliateEpubReaderView.kt` 完全不呼叫，是否連 FXL 路徑也一併清理留待未來評估，不在本次 Phase 1 範圍。
