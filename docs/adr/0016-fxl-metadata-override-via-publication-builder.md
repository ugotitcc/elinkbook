# ADR 0016：強制 FXL 書籍的橫向雙頁渲染修復——重建 `Publication` 物件覆寫 `metadata.layout`，接受服務遺失風險

## 狀態

已取代（superseded by [ADR 0017](./0017-fxl-migrate-to-foliate-js.md)）——`epic-20-fxl-foliate-migration` Issue 1 Spike 確認 FXL 可完全遷移到 `foliate-js`，`EpubReaderView.kt` 整份移除，本 ADR 記錄的 `Publication.Builder` 修補決策隨之失效。保留本文作為歷史紀錄。

## 背景

Issue 15 新增「強制 FXL」人工版面覆蓋按鈕（`LibraryScreen` 多選模式），讓被「引擎分派判斷」誤判為流式的漫畫 EPUB 可以手動導向 `EpubReaderView`（Readium／FXL）路徑——這一層決定的是 `Book.isFixedLayout`，只影響 Dart 端建構哪個 widget，已於 Issue 15 真機驗收確認正確運作。

Issue 16 發現：即使 Dart 端已正確導向 `EpubReaderView`，裝置橫向且雙頁模式開啟時畫面仍只顯示一頁。查證確認根因是 Readium 官方元件 `EpubNavigatorFragment`（`readium-kotlin-toolkit`，非本專案程式碼）在 Dart 分派決定**之外**，自己獨立重新讀取這本書的 `publication.metadata.layout` 來決定渲染模式，且它唯一對外開放的組態介面 `EpubNavigatorFragment.Configuration` 沒有任何欄位可以覆寫這個判讀。

Issue 17 Spike 驗證「覆寫本專案自己的 3 個 bookkeeping 檢查點（`EpubReaderView.kt:501`／`:998`／`:1199`）」對 `EpubNavigatorFragment` 的實際渲染無效（**NO-GO**）——證實這 3 個檢查點只是本專案自己的紀錄，不是 Readium 真正讀取的東西。

Issue 18 Spike 驗證新方向：用 Readium 官方 API `Publication.Builder(manifest, container, servicesBuilder)` 重建整個 `Publication` 物件，將 `metadata.layout` 覆寫為 `Layout.FIXED`，再把重建後的物件交給 `EpubNavigatorFactory`——真機驗證 **GO**：`EpubNavigatorFragment` 正確渲染成雙頁並排，翻頁與熱區翻頁皆正常。但原始 `Publication` 的 `servicesBuilder` 是 private 建構子參數，本專案程式碼讀不到，重建時只能傳一個全新的預設 `ServicesBuilder()`；真機觀察到進度條不可見、頁數呈現模式異常，疑似服務遺失（例如 `positions()`）所致，另開 Issue 20 獨立排查是否為既有缺陷或本次改動所致。

## 決策

- **採用 Issue 18 驗證通過的方向**：`EpubReaderView.kt` 的 `attachNavigator()` 內，若 Readium 官方解析出的 `openedPublication.metadata.layout != Layout.FIXED`，用 `Publication.Builder` 重建一個 `metadata.layout` 強制為 `Layout.FIXED` 的新物件（`effectivePublication`），傳給 `EpubNavigatorFactory`；沒有 mismatch 時原樣使用 `openedPublication`，不重建——避免對本來就判斷正確的一般 FXL 書籍引入不必要的服務遺失風險。
- **不做 Dart→Kotlin 的 `isForceFxl` 旗標傳遞管線**：`EpubReaderView`（Dart widget）／`attachNavigator()`（Kotlin）只會在 `Book.isFixedLayout == true` 時才會被建構/執行——這個條件涵蓋使用者手動強制、`detectAndCacheEpubLayout()` 自動判斷、以及未提供 `libraryRepository` 時的既有退回預設值三種情況。換句話說，一旦程式跑到 `attachNavigator()`，「這本書該渲染成 FXL」在上游已經是定案，`openedPublication.metadata.layout != Layout.FIXED` 這個運行時判斷式已完整表達「Readium 官方解析器不同意上游決定」，資訊量等同一個恆為 `true` 的旗標，額外傳遞沒有必要，也不會削弱使用者透過「強制 FXL」按鈕做出的手動決定（那個決定完整保留在上游 `Book.isFixedLayout`／Dart 端 widget 分派這一層，不受本決策影響）。
- **隔離架構**：class 欄位 `publication` 全程維持指向原始 `openedPublication`（保留完整服務），新增一個欄位 `effectivePublication` 只供 3 個「FXL 判斷」檢查點（`:501`／`:998`／`:1199`）與 `EpubNavigatorFactory` 建構使用；`jumpToProgression()`／`buildTocPayloadSafely()`／`computeTotalCharacterCountInBackground()` 等既有呼叫端維持讀取 `publication`，不受服務遺失影響。此隔離設計已於 Issue 18 Spike 驗證有效。
- **明確接受服務遺失的已知代價**：`EpubNavigatorFragment` 內部（非本專案程式碼）在渲染/分頁過程中一樣會用到 `effectivePublication` 的服務（例如 `positionsByReadingOrder()`），這部分無法透過本專案自己的隔離設計保護——隔離只保護本專案自己的呼叫端，保護不到 Readium 官方元件內部的行為。Issue 18 觀察到的進度條/頁數呈現異常可能源自這裡。是否修復、修復到什麼程度，交由獨立的 **Issue 20** 排查（不確定是否為既有缺陷、與本次改動是否同一根因），不阻擋本次雙頁渲染修復本身上線。

## 曾考慮的替代方案

- **反射（reflection）取得原始 private `servicesBuilder`，完整重建保留全部服務**：技術上可能，但 Android release build 的 R8/ProGuard 可能重新命名/裁剪私有欄位，反射存取的可靠度未經驗證，且需要繞過官方 API 邊界存取內部實作細節，風險與投入不成比例，予以排除。若 Issue 20 排查後認定服務遺失是不可接受的退化，才重新評估此方案。
- **顯式 Dart→Kotlin `isForceFxl` 旗標傳遞管線**（`openBook()` 新增專屬參數、`EpubReaderView.dart` 新增建構參數）：資訊量與 `attachNavigator()` 內部運行時判斷式完全重複，徒增一條需要維護的管線與對稱的 Dart/Kotlin 契約，予以排除。
- **接受現狀限制**（Issue 16 降級為 `wontfix`，僅在 UI 上提示使用者「強制 FXL 對此類書籍的雙頁排版效果有限」）：技術上可行，但放棄了 Issue 15「強制 FXL」功能真正解決漫畫書雙頁閱讀體驗的初衷，且 Issue 18 已證實有可行的技術方案，予以排除。

## 後果

- `EpubReaderView.kt` 新增一個永久（非 Spike 用）欄位 `effectivePublication`，3 個既有檢查點改讀這個欄位或 `attachNavigator()` 函式範圍內對應的區域變數，取代各自獨立讀 `publication.metadata.layout` 的現狀。
- `epub_reader_view.dart:326` 的 `_isFixedLayout` 仍建議補上防禦性保護（比照 `ReaderScreen` 既有 `commit 97878c4` 模式）——雖然理論上修復後 native 端不會再回報 `false`，但作為 `Publication.Builder` 重建失敗等邊界情況的防禦層。
- 進度條/頁數呈現異常明確標記為已知限制，交由 Issue 20 獨立追蹤，本 ADR 不承諾其解決時程。
- 若未來升級 `readium-kotlin-toolkit` 版本、`Publication.Builder` 簽章或 `servicesBuilder` 存取權限改變，需要重新驗證本 ADR 的可行性（比照既有對 `foliate-js` 釘定版本的維護慣例）。
- `container` 參數存取需要 `@OptIn(org.readium.r2.shared.InternalReadiumApi::class)`（見 Issue 18 Spike 報告附帶發現），屬於 Readium 標記為內部/非公開穩定 API 的存取，升級 Readium 版本時需重新確認此標記與簽章是否變動。

## 相關佐證

- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 15／16／17／18／19／20
- `docs/epics/epic-18-reader-device-qa/design.md`「Issue 16／17 修復方向 Discovery」「Issue 17／18 Spike 結論」
- `docs/epics/epic-18-reader-device-qa/reviews/spike-issue16-fxl-metadata-override.md`（Issue 17 NO-GO 報告）
- `docs/epics/epic-18-reader-device-qa/reviews/spike-issue18-publication-builder-override.md`（Issue 18 GO 報告）
- `CONTEXT.md`「Readium 內部版面渲染決策」「引擎分派判斷」「人工版面覆蓋」詞彙定義
