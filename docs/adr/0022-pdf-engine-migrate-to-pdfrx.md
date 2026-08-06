# ADR 0022：PDF 渲染引擎由平台原生 API 遷移至 pdfrx（PDFium + Dart FFI）

## 狀態

已採納；**部分取代 [ADR 0001](0001-mobile-architecture.md) 第 20 行、第 35 行**（「PDF 渲染：各平台內建 API——不使用像 PDFium 這類第三方函式庫」與「PDFium 這一階段予以排除」）。ADR 0001 其餘決策（App 外殼、EPUB 渲染、TXT 引擎、平台優先順序）維持不變。

## 背景

ADR 0001 當初排除 PDFium 的理由是「整合較單純；PDF 本質是固定版面、非 reflow，平台 API 已足夠應付」，並明文保留重新檢視條款：「若平台 API 無法滿足 FR-11 的影像濾鏡/裁切需求，可再重新檢視」。FR-11（影像濾鏡/智慧裁切）已於 `epic-4-pdf-enhance` 用現行原生架構（`android.graphics.pdf.PdfRenderer` + `PdfImageProcessor.kt`）完整實作並上線，該保留條款並未真正被觸發——本次重新檢視的理由是**全新需求**，非原條款預期的情境：

- **TOC 目錄解析**：`android.graphics.pdf.PdfRenderer` 完全不提供解析 PDF 內部大綱/書籤樹（outline dictionary）的 API。`epic-23-pdf-fab-toolbar`（Discovery 階段即發現此限制）確認要在現行架構做到 PDF 目錄，需要手寫一套 PDF outline dictionary 解析邏輯，非小工程，技術可行性未經驗證。
- **雙頁並列、內文搜尋、頁碼縮圖**：現行架構皆需自行從零實作（`PdfRenderer` 一次僅能渲染單頁點陣圖，沒有文字層、沒有頁面物件模型可供搜尋/縮圖/精準文字定位）。

`tmp/pdf_reader_solutions_research.md`（2026-08-06 研究報告）比較三種架構方向（原生 PlatformView／PDFium+FFI／WebView+PDF.js），確認 `pdfrx`（PDFium 透過 `dart:ffi` 直連，[espresso3389/pdfrx](https://github.com/espresso3389/pdfrx)）內建 `loadOutline()`、`spreadMode`、`FPDFText_*` 文字定位 API，可一次滿足上述全部缺口，且 Android/iOS 共用同一份 Dart 程式碼（雖然本專案目前 iOS 仍是最低優先順序、非本次決策驅動因素）。

## 決策

- **PDF 渲染引擎由 `android.graphics.pdf.PdfRenderer`（Android）／`PDFKit`（iOS，尚未實作）完全遷移至 `pdfrx`（PDFium + Dart FFI）**，非漸進式共存——現行 `PdfReaderView.kt`／`PdfReaderView`（`AndroidView` PlatformView 包裝）整套退場，改用 `pdfrx` 提供的 Dart widget 直接渲染，不再透過 `PlatformView`。
- **不先做技術 Spike**：專案過往遇到同等級重大渲染引擎替換（`epic-20`，FXL 從 Readium 遷移至 `foliate-js`）皆先跑真機 Spike 驗證關鍵假設後才投入全面實作；本次經與人類確認，**不比照該模式**，直接進入 Architecting／實作。技術風險（大檔效能、E-Ink 影像濾鏡可行性、`content://` URI 相容性等）改為在實作階段以真機驗證與可能的範圍調整處理，非事前 Spike 排除。
- **E-Ink 影像濾鏡/裁切（FR-11）功能對等為必要驗收條件**：對比度/亮度濾鏡、型態學膨脹加粗、智慧/手動裁切須在新引擎（Dart 端，操作 `pdfrx` 頁面點陣圖輸出）重新實作，達到與現行 `PdfImageProcessor.kt` 相當的功能與可用效能，**不接受功能退化**——這是本次決策與研究報告最大的落差（報告本身承認此為缺口、未給具體方案），須列為新 Epic（`epic-24-pdf-engine-rebuild`）的驗收範圍。
- **手寫/自由繪圖標註（stylus freehand annotation，Saber 案例的核心能力）明確排除於本次範圍**：與既有「選取文字→高亮/備註」劃線系統（`AnnotationToolbar`／`HighlightsRepository`）是完全不同的互動模式，PRD 未描述過此需求，另立後續獨立 Epic 評估，不與引擎遷移綁定。
- **內文搜尋範圍**：本次「搜尋」指單一已開啟 PDF 文件內的搜尋（比照 `pdfrx` 官方 viewer 範例的 in-document search），與全書庫全文檢索（FTS5，`docs/epics.md` Backlog、尚未開始）是不同功能，不在本次範圍內互相依賴。
- **`epic-23-pdf-fab-toolbar`（尚未開始實作）併入本 Epic**：原規劃「PDF 工具列改用 FAB 呈現」是針對現行 `PdfReaderView` 設計，若先在舊引擎上實作、新引擎上線後又要重做一次，是重複工。`epic-23` 目錄未曾進版控，直接撤銷，FAB 化工作併入 `epic-24-pdf-engine-rebuild` 一併對新 `pdfrx` 視圖設計。

## 後果

- 現行 `PdfReaderView.kt`（原生 Kotlin，`android.graphics.pdf.PdfRenderer` + `PdfImageProcessor.kt` 影像處理）、`PdfReaderView`（Dart `AndroidView` 包裝）、對應 method channel 契約（`openBook`/`onPageRendered`/`onError`）全部退場，是本專案至今最大規模的單一格式渲染路徑重寫。
- `ReaderScreen` 對 PDF 的既有假設（`_pdfPageInfo`、頁碼 0-indexed、`Bookmark.pdfPageIndex`、`BookmarkPositionContext.pdfPageIndex`）皆為引擎無關的頁碼概念，資料層（SQLite `bookmarks`／`highlights`／`notes`／`book_reader_prefs`）不需要 schema 遷移；`Book.filePath`（`content://`/`file://` URI，ADR 0002）是否能直接餵給 `pdfrx` 或仍需既有的落地複本策略，留給 `spec.md` 確認。
- 新增 `dart:ffi` 原生函式庫依賴（PDFium `.so`/`.xcframework`），改變了本專案先前「PDF 不引入第三方原生函式庫」的既有假設，需評估 APK 體積、建置流程（`build.gradle.kts`）與既有 `minSdk 24` 相容性影響。
- 不做 Spike 直接進入實作，代表大檔效能、E-Ink 影像濾鏡重寫可行性等風險會在實作／真機驗證階段才浮現，而非事前排除——已明確告知並經人類確認接受此風險排序。

## 曾考慮的替代方案

- **只加 `pdfrx` 補 TOC，其餘維持現行原生架構共存**：被排除——經與人類確認，選擇完全替換（研究報告的建議），理由是雙引擎共存的長期維護成本與架構複雜度高於一次性完整遷移。
- **維持現行架構、TOC 用手寫 outline dictionary 解析器補齊**：技術可行性未驗證、工程量不小，且無法一併解決雙頁/搜尋/縮圖缺口，被 `pdfrx` 的完整內建能力取代。
