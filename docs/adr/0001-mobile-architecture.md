# ADR 0001：手機端架構 —— Flutter 外殼、Readium 處理 EPUB、平台原生 PDF

## 狀態

已採納；「EPUB 渲染：Readium」這項決策，對**流式（reflowable）EPUB**已被 [ADR 0011](0011-epub-reflowable-migrate-to-foliate-js.md) 取代（改用 `readest/foliate-js`，Phase 1）——本文件第 27 行預留的伏筆條款（「若 Readium 的直排支援或 Decorator...被證實不足，應重新檢視本 ADR」）已在 `epic-17-epub-render-migration` 觸發並收斂。**固定版面（FXL）EPUB 與 PDF 渲染的決策維持不變**，本 ADR 其餘決策（App 外殼、平台優先順序等）維持有效。

## 背景

elinkBook 目前尚無任何程式碼。先前曾有一次實作嘗試（記錄於專案歷史 `elinkApp/docs/todo.md` 中），採用以 WebView 為主的跨平台技術棧（Capacitor + epub.js），並反覆在對本產品最關鍵的區域出現缺陷：直排中文文字的跳轉導航，以及在直排/橫排切換時劃線/備註的一致性。本產品的核心差異化在於高品質的直排繁體中文排版（FR-32：標點轉向、避頭尾換行），因此閱讀內容的渲染方式是整個專案中風險最高的架構決策。

曾考慮並排除兩個極端方案：

- **完全自寫原生渲染、完全不使用任何瀏覽器引擎**（用 Rust/C++ 或各平台原生程式碼從零寫一套 EPUB reflow——也就是 XHTML/CSS——排版引擎）：判定對此團隊規模不可行。EPUB 的 reflow 內容本質就是 XHTML+CSS；從零打造渲染器代表要重新實作 HTML 解析、CSS cascade、box-model 排版與文字塑形——等於複製一套瀏覽器排版引擎。沒有任何主流 EPUB 閱讀器（Apple Books、Kobo、Kindle）是這樣做的。
- **每平台完全各自寫原生 UI、沒有共用外殼**（Swift/iOS 與 Kotlin/Android 各自獨立的 App，各自重新實作整個應用程式——圖書庫、設定、同步、書籤、統計）：排除，因為這會讓未來每個新功能的實作成本都乘以平台數量，而且是無止盡的，不只是閱讀引擎而已。

## 決策

- **App 外殼**：Flutter，跨平台共用，負責所有非閱讀相關的 UI（圖書庫、設定、同步狀態、書籤/劃線/備註清單、閱讀統計、關於頁）。
- **EPUB 渲染**：Readium 官方原生 SDK——`readium-kotlin-toolkit`（Android）與 `readium-swift-toolkit`（iOS，稍後導入）。這兩者內部仍是 WebView（WKWebView/Android WebView），但成熟、專門打造，且被正式產品採用（Thorium Reader、Palace/SimplyE）。它們提供 `Locator`（等同 CFI 的定位）與 `Decorator`（劃線/備註疊加）API——正是先前 DIY（epub.js）嘗試中導致缺陷的那些子系統。透過 `PlatformView` 嵌入 Flutter。
- **PDF 渲染**：各平台內建 API——Android `PdfRenderer`、iOS `PDFKit`——不使用像 PDFium 這類第三方函式庫。整合較單純；PDF 本質是固定版面、非 reflow，平台 API 已足夠應付。透過 `PlatformView` 嵌入 Flutter。
- **TXT 渲染**：自訂的輕量直排 CJK 文字排版引擎（獨立的未來 Epic，`epic-11-txt-engine`）。與 EPUB 不同，純文字沒有 HTML/CSS 那層需要重新實作，因此從零打造引擎在這裡是可行的——這是唯一一種自訂原生渲染（可能搭配共用的 Rust/C++ 核心）真正合理的格式。
- **平台優先順序**：Android 優先，iOS 其次（`epic-13-ios`，刻意排在 Epic 順序的最後）。初期幾波不含桌面版目標——Readium 的工具鏈與社群支援在手機端最為成熟。

## 後果

- 不論 Flutter 外殼與否，EPUB 與 PDF 的整合程式碼本質上都是各平台原生的（Android 用 Kotlin 處理 Readium/PdfRenderer，之後 iOS 用 Swift 處理 Readium/PDFKit）——外殼的價值在於不用把 App 其餘約 70%（圖書庫、設定、同步、書籤、統計）在每個平台各自重寫一次。
- 因為 Readium 內部仍使用 WebView，這並未完全消除 WebView 相關風險——只是把「自己拼裝的 WebView 整合」換成「成熟、專門打造的 WebView 整合」。若 Readium 的直排支援或 Decorator 在 `epic-0-skeleton` 或 `epic-2-vertical-core` 階段被證實不足，應重新檢視本 ADR。
- EPUB 或 PDF 都沒有引入共用的 Rust/C++ 核心。共用核心仍是值得重新考慮的選項，但特別是針對 TXT 引擎（`epic-11-txt-engine`）——在那裡「只寫一次、沒有 HTML/CSS 複雜度」的論點才真正成立。
- 本地資料庫（SQLite）、同步（PocketBase）整合、以及狀態管理的選擇不在本 ADR 涵蓋範圍內——這些是後續 Epic 的獨立決策。

## 曾考慮的替代方案

- Capacitor/Tauri + Web 技術 UI（整個 App、不只 EPUB，都放進 WebView）：根據先前在這個確切領域的實作歷史予以排除。
- Flutter + Flutter 自身的文字引擎處理全部內容（不用 PlatformView、不用 Readium）：排除——Flutter 基於 Skia 的文字引擎缺乏成熟的直排模式支援，而這正是本產品的核心差異化。
- PDFium（透過 FFI 或原生外掛橋接）取代平台原生 PDF API：這一階段予以排除，改採更單純的平台原生整合；若平台 API 無法滿足 FR-11 的影像濾鏡/裁切需求，可再重新檢視。
