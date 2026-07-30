# ADR 0017：FXL EPUB 渲染引擎由 Readium 遷移至 `foliate-js`（Phase 2，取代 ADR 0011 的排除範圍）

## 狀態

已採納

## 背景

`ADR 0011`（`epic-17-epub-render-migration`）Phase 1 把**流式（reflowable）EPUB** 的渲染引擎由 Readium 換成 `readest/foliate-js`，**固定版面（FXL）EPUB 刻意留在 Readium**，並明文預留伏筆：「FXL 遷移...留待未來視 Phase 1 上線後的實際狀況另立 ADR 或 Epic 評估」。

`epic-18-reader-device-qa` Issue 15-21 這一連串工單暴露出 FXL 留在 Readium 這條路徑的深層限制：Readium 官方元件（`EpubNavigatorFragment`）對書本 metadata 的判讀、雙頁 spread 配對演算法、`positions()`/`servicesBuilder` 服務層，皆是本專案無法完全控制的官方黑盒——Issue 16-21 一路都是在這些邊界內打補丁（`Publication.Builder` 重建 metadata、`readingOrder` 索引估算頁碼、嘗試覆寫 `page-spread-center` 屬性）。

`epic-20-fxl-foliate-migration` Issue 1 Spike（`reviews/spike-issue1-fxl-foliate.md`）以真實問題書籍（《一弦定音！(11)》，202 頁 RTL 漫畫，Issue 15/17/18/19 一路使用的同一本）真機驗證：`readest/foliate-js`（本專案已 production 使用的同一釘定 commit，補上先前未 vendored 的 `fixed-layout.js`）能正確處理橫向雙頁排版、封面獨立顯示、RTL 頁序、連續翻頁穩定性，且這本書的原始 OPF metadata（`rendition:page-spread-center`／`page-spread-left`／`page-spread-right`）被 `epub.js`／`fixed-layout.js` 開箱即用、無需任何修補——Readium 路徑一路受限的「metadata 判讀黑盒」問題，在 `foliate-js` 這邊不存在。Spike 結論 **GO**。

`/grill-with-docs` 完成 Architecting 階段逐項決策，形成本 ADR。

## 決策

1. **FXL 渲染引擎完全退出 Readium，`FoliateEpubReaderView` 統一處理所有 EPUB**（不分 FXL／流式）。`EpubReaderView.kt`／`EpubReaderViewFactory.kt`（原生 FXL 渲染 widget）、Dart 端 `EpubReaderView`（`app/lib/reader/epub_reader_view.dart`）、`readium-navigator` 依賴（`build.gradle.kts`）予以移除。`ReaderScreen` 的引擎分派邏輯（`_dispatchedIsFixedLayout` 決定建構哪個 widget）同步簡化——EPUB 一律建構 `FoliateEpubReaderView`，不再有分支。
   - 理由：Spike 已用本專案實際遭遇問題的真實書籍驗證核心能力，不需要再維持兩套引擎並行的維護成本；比照 ADR 0011 Phase 1 完成後 Phase 2 的自然延續。
2. **`BookMetadataChannel.kt` 維持使用 Readium**（`readium-shared`／`readium-streamer`，`extractEpubMetadata()`／`detectEpubLayout()`：匯入時抽取封面/metadata、既有的 `Book.isFixedLayout` 判斷快取邏輯）。這一層不涉及 Fragment／畫面渲染，純解析用途，風險與本次遷移的核心動機（渲染引擎黑盒問題）無關，不在本次範圍內一併更動。
   - 後果：`readium-shared`／`readium-streamer` 這兩個 Gradle dependency 予以保留；只有 `readium-navigator`（僅 `EpubReaderView.kt` 使用）可以移除。
3. **`Book.isFixedLayout` 用途窄化為「UI 行為提示」，不再是引擎選擇依據**：由於 `FoliateEpubReaderView` 已透過 `book.rendition?.layout === 'pre-paginated'` 在開書當下自行可靠偵測 FXL（Spike 已驗證），`Book.isFixedLayout`（`BookMetadataChannel.detectEpubLayout()` 快取值）改為僅供**開書前的 UI 決策**使用（例如是否顯示雙頁模式切換選項、書架縮圖比例等不需要等到 WebView 實際開書才能決定的場景），不再決定要建構哪個原生 widget。
4. **Issue 15「強制 FXL」重新定位為 UI 行為覆蓋，非引擎選擇修正**：原始問題（書本被誤判、導向錯誤引擎）已隨決策 1 結構性消失。保留 `LibraryScreen` 的「強制 FXL」／「恢復自動判斷」按鈕與 `Book.isFixedLayout` 欄位本身（資料層零異動，比照 Issue 15 原始決策精神），但語意改為「使用者手動覆蓋 UI 預設行為的提示」；同時新增一個開書時的執行期覆蓋機制——`FoliateEpubReaderView` 開書時若 `Book.isFixedLayout == true`，在呼叫 `view.open(book)` 前覆寫 `book.rendition.layout = 'pre-paginated'`（僅在與 `epub.js` 自行解析出的值不同時才覆寫，避免對已正確判斷的書籍引入不必要的行為變化），確保使用者的手動決定在極少數 `epub.js` 也判斷不出 FXL 的邊界情況下仍然生效。
5. **既有 FXL 書籍的使用者資料（書籤/劃線/備註/閱讀進度）視為失效、不做遷移轉換**，比照 ADR 0011 對 reflowable Phase 1 的既有先例——Readium `Locator`（`href` + `position` 整數 + `totalProgression`）與 `foliate-js` 的 CFI 定位系統無可靠的一對一換算，不投入開發資源做轉換工具。
6. **本次遷移範圍僅涵蓋基本閱讀能力**（開書、橫向雙頁、封面獨立顯示、RTL 頁序、進度條/頁尾/目錄——皆是 `FoliateEpubReaderView` 既有能力，FXL 書籍藉由統一到同一個 widget 自動獲得，不需要額外開發）與**書籤**（沿用既有 CFI locator 持久化機制，無視覺 overlay，風險低）。**劃線/備註（`overlayer.js` 對接）在 FXL 雙頁模式下的行為明確排除在本次範圍外**，因跨頁選取/疊圖定位在雙頁並排時的正確性本次 Spike 完全未驗證，留待獨立的後續 Epic 評估。
7. **`MainActivity` 由 `FlutterFragmentActivity` 改回 `FlutterActivity`**：查證確認 `MainActivity.kt` 目前唯一需要 Fragment 基礎設施（`supportFragmentManager`、`EpubNavigatorFragment.createDummyFactory()` 等程序還原邏輯）的地方就是 Readium 的 `EpubNavigatorFragment`；決策 1 移除 `EpubReaderView.kt` 後，這整套機制成為死碼，一併移除。`PdfReaderView`（純 `ImageView`）、`FoliateEpubReaderView`（`flutter_inappwebview` 自有嵌入機制）皆不受影響。

## 曾考慮的替代方案

- **平行保留兩套引擎，待 production 觀察一段時間再決定是否退場 Readium**（比照 ADR 0011 Phase 1 的保守做法）：Phase 1 當時是因為 `foliate-js` 對「全新能力」（reflowable 直排分頁）尚無 production 證據；本次 FXL 遷移的核心風險（雙頁/封面獨立顯示/RTL）已用本專案實際遭遇問題的真實書籍在 Spike 階段直接驗證過，不需要比照同等保守幅度，予以排除。
- **一併把 `BookMetadataChannel.kt` 的 metadata/封面抽取也遷移到非 Readium 實作**：這一層不涉及本次遷移的核心動機（Fragment/畫面渲染黑盒問題），額外遷移只會擴大變更範圍與風險、不對應任何已知痛點，予以排除。
- **投入開發資源做 Readium Locator → foliate-js CFI 的資料轉換工具**：技術上可能可行，但准確性無法保證（兩套引擎的 reflow/分頁演算法不保證逐字對齊），比照 ADR 0011 已排除的相同理由，予以排除。
- **本次一併完成劃線/備註對 FXL 雙頁模式的支援**：跨頁 overlay 定位正確性未經驗證，貿然實作有返工風險，予以排除，留待後續 Epic。

## 後果

- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`／`EpubReaderViewFactory.kt` 整份刪除；`MainActivity.configureFlutterEngine()` 移除對應的 `PlatformView` 類型字串註冊。
- `app/lib/reader/epub_reader_view.dart` 整份刪除；`ReaderScreen._buildNativeView()`／`_epubReaderViewKey` 等 Readium 專屬程式碼一併清理。
- `app/android/app/build.gradle.kts` 移除 `org.readium.kotlin-toolkit:readium-navigator:3.3.0`；`readium-shared`／`readium-streamer` 保留（供 `BookMetadataChannel.kt` 使用）。
- `MainActivity` 由 `FlutterFragmentActivity` 改回 `FlutterActivity`，移除 `EpubNavigatorFragment` 相關的程序還原防禦程式碼。
- `epic-18-reader-device-qa` Issue 16／17／18／19 這一連串針對 `EpubReaderView.kt` 的修補（`Publication.Builder` 重建、`effectivePublication` 隔離架構等，ADR 0016 記錄的決策）隨整份檔案刪除而自然失效，不需要另外 revert——ADR 0016 予以標記 `superseded by ADR 0017`。
- `epic-18` Issue 20（進度條/頁尾 FAB）／Issue 21（封面獨立顯示/頁碼配對）／Issue 22（TOC 按鈕缺失）三者的原始訴求，藉由「FXL 統一到 `FoliateEpubReaderView`」自動獲得解決（`FoliateEpubReaderView` 已有這些能力，來自 `epic-17` Issue 6/7 為 reflowable 開發時的既有實作），不需要另外實作，三者狀態維持「不再執行」。
- 既有已安裝使用者的 FXL 書籍書籤/劃線/備註/閱讀進度資料，App 更新後首次重開該書會偵測不到（等同以新書狀態開始）——這是本 ADR 明確接受的已知使用者體感衝擊，非疏漏，比照 ADR 0011 先例，建議在該次改版的版本說明中揭露。
- 劃線/備註對 FXL 雙頁模式的支援明確不在本次範圍，另立後續 Epic 評估；本次遷移完成後 FXL 書籍暫時無法使用劃線/備註功能（書籤不受影響）。

## 相關佐證

- `docs/adr/0011-epub-reflowable-migrate-to-foliate-js.md`（Phase 1，本 ADR 為其 Phase 2）
- `docs/adr/0016-fxl-metadata-override-via-publication-builder.md`（被本 ADR 取代，Readium 路徑的修補決策隨 `EpubReaderView.kt` 移除而失效）
- `docs/epics/epic-20-fxl-foliate-migration/design.md`
- `docs/epics/epic-20-fxl-foliate-migration/reviews/spike-issue1-fxl-foliate.md`
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 15-22
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`（Fragment 還原邏輯查證）
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt`（Readium metadata/封面抽取用途查證）
