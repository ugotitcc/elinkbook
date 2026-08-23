# Epic 24 — PDF 渲染引擎重建（遷移至 pdfrx/PDFium）：Discovery

## 背景

使用者依據 `tmp/pdf_reader_solutions_research.md`（2026-08-06 研究報告）提出：現行 PDF 渲染架構（`android.graphics.pdf.PdfRenderer` 原生 API，`PdfReaderView.kt` + `PdfReaderView` `AndroidView` 包裝）無法滿足 5 大優先需求（雙頁並列、TOC 目錄解析、頁次頁碼、書籤、畫線註記），建議改用 `pdfrx`（PDFium + Dart FFI，[espresso3389/pdfrx](https://github.com/espresso3389/pdfrx)），並參考 [saber-notes/saber](https://github.com/saber-notes/saber)（開源手寫筆記/PDF 標註應用）。

`/grill-with-docs` 逐項確認範圍前，先查證既有架構決策：[ADR 0001](../../adr/0001-mobile-architecture.md) 第 20/35 行明確記錄過「PDFium 這一階段予以排除」，並保留「若平台 API 無法滿足 FR-11 影像濾鏡/裁切需求，可再重新檢視」的伏筆條款——該條款已在 `epic-4-pdf-enhance` 用現行原生架構成功滿足 FR-11，並未真正觸發。本次重新檢視的理由是全新需求（TOC/雙頁/搜尋/縮圖），非原條款預期情境，詳細決策記於新增的 [ADR 0022](../../adr/0022-pdf-engine-migrate-to-pdfrx.md)。

此外，`epic-23-pdf-fab-toolbar`（前一輪 `/diagnose` 立案，「PDF 工具列改用 FAB 呈現」，尚未開始實作）因為是針對現行 `PdfReaderView` 設計，若先在舊引擎做、新引擎上線後又要重做，屬重複工，已確認併入本 Epic、原目錄撤銷。

## 決策（`/grill-with-docs` 逐項確認）

1. **替換範圍：完全替換，非漸進共存**。現行 `PdfReaderView.kt`（Kotlin 原生）／`PdfReaderView`（Dart `AndroidView` 包裝）／`openBook`/`onPageRendered`/`onError` method channel 契約全部退場，改用 `pdfrx` 提供的 Dart widget 直接渲染 PDF，不再透過 `PlatformView`。單頁/雙頁、搜尋、縮圖、畫線註記全部統一在新引擎上實作，不維持雙引擎並存。
2. **E-Ink 影像濾鏡/裁切（FR-11）功能對等，列為本 Epic 必須完成的驗收條件**。對比度/亮度濾鏡、型態學膨脹加粗（PDF 加粗）、智慧自動裁切、手動選區裁切，現行實作於 `PdfImageProcessor.kt`（直接操作 Android `Bitmap`），須在新引擎（Dart 端操作 `pdfrx` 頁面點陣圖輸出）重新實作、達到功能與可用效能對等，不接受功能退化。研究報告本身承認這是缺口（「需在 Dart 端操作 `Uint8List` 或封裝 C/C++ 影像處理」），未給具體方案，實作階段需要自行設計。
3. **手寫/自由繪圖標註明確排除於本 Epic**。使用者引用 Saber 案例是指真正的自由繪圖（stylus 壓力感測、向量筆畫直接畫在頁面上），與 elinkBook 現有「選取文字→高亮/備註」劃線系統（`AnnotationToolbar`／`HighlightsRepository`，PRD 未描述過自由繪圖需求）是完全不同的互動模式。確認後另立獨立後續 Epic 評估，不與本次引擎遷移綁定；本 Epic 的「畫線註記」範圍僅指既有文字選取劃線系統遷移到新引擎（可望受益於 `pdfrx` 的 `FPDFText_*` API 取得更精準的文字 bounding box，取代現行需要原生端計算選取矩形座標的作法）。
4. **內文搜尋範圍**：指單一已開啟 PDF 文件內的搜尋（比照 `pdfrx` 官方 viewer 範例的 in-document search 高亮），與全書庫全文檢索（FTS5，`docs/epics.md` Backlog 尚未開始）是不同功能，兩者互不依賴、不在本次範圍內整合。
5. **不先做技術 Spike**，直接進入 Architecting（`spec.md`）。專案過往同等級渲染引擎替換決策（`epic-20`，FXL 遷移至 `foliate-js`）皆先跑真機 Spike 驗證關鍵假設，本次經與人類確認不比照該模式。技術風險（100MB+ 大檔開書效能、E-Ink 影像濾鏡重寫可行性、`content://` URI 相容性）改於實作階段以真機驗證處理，非事前排除——此為已知、經人類確認接受的風險排序，非疏漏。
6. **`epic-23-pdf-fab-toolbar` 併入本 Epic**：PDF 頂部工具列（返回/版面設定/筆記）＋頁面導覽（進度/跳頁）＋新增書籤 toggle，皆改為 FAB 圓形浮動按鈕呈現，直接對新 `pdfrx` 視圖設計，比照 EPUB 既有 FAB 樣式（重用 Epic 22 的 `_themedFabBackgroundColor`/`_themedFabIconColor` 顏色 getter）。**目錄（TOC）FAB 這次可以真的加上**（`epic-23` 原本因技術可行性未知而排除，`pdfrx` 的 `loadOutline()` 解除了這個限制），PDF 因此可望達到與 EPUB 相同的 6 顆 FAB 按鈕（返回/目錄/版面設定/書籤/筆記/進度-跳頁）。
7. **書籤/劃線/備註資料層不需要 schema 遷移**：`Bookmark.pdfPageIndex`／`BookmarkPositionContext.pdfPageIndex` 是引擎無關的頁碼概念（0-indexed），`pdfrx` 同樣以頁碼定位，既有 SQLite schema（`bookmarks`／`highlights`／`notes`／`book_reader_prefs`）直接沿用。
8. **E-Ink 影像處理（決策 2）不得佔用 UI 主執行緒**（`/superpowers:receiving-code-review` 審查回應，見下方）：對比度/亮度/加粗/裁切這類逐像素運算一律在 Dart `Isolate`（比照專案既有前例 `lib/library/book_content_fingerprint.dart` 的 `compute()` 用法）背景執行；若 Isolate 效能仍不足以達成決策 2 的功能對等驗收條件，保留封裝 C/C++ FFI 影像處理模組作為效能備案（`pdfrx` 本身已引入 PDFium 原生函式庫，技術上已有 FFI 邊界可擴充）。

## 5 大需求範圍界定（依研究報告優先順序）

1. **雙頁並列閱讀（Facing Pages）**：`pdfrx` 的 `spreadMode`／`layoutPages` 原生支援，比照 EPUB FXL 既有「雙頁模式（Dual-Page Mode）」三態設計（自動/永遠雙頁/永遠單頁，`CONTEXT.md` 既有詞彙）。
2. **TOC 目錄解析**：`pdfrx.loadOutline()`，比照 EPUB 既有 `TocBottomSheet`／`TocNavigator` UI 元件與互動模式（可能重用或另建 PDF 專屬版本，留給 `spec.md` 決定）。
3. **頁次頁數應用**：`pageCount`／`jumpToPage`／`FPDF_GetPageLabel`（PDF 邏輯頁碼標籤，例如封面羅馬數字），現行 `ReaderFooter`／頁碼顯示邏輯需確認是否需要一併支援 Page Label（原生邏輯頁碼）或維持現行純數字頁碼，留給 `spec.md` 決定。
4. **書籤管理**：App 層既有 SQLite 持久化，三方案皆無差異，見決策 7。
5. **畫線註記**：見決策 3，範圍限定既有文字選取劃線系統遷移，不含自由繪圖。

（額外）**頁碼縮圖（Thumbnails）**：`pdfrx` 官方 viewer 範例內建功能，本 Epic 一併納入，作為 TOC 之外的另一種快速導覽方式。

## 範圍界定

- 涵蓋：PDF 渲染引擎完全遷移至 `pdfrx`；雙頁/TOC/搜尋/縮圖/書籤/畫線註記皆在新引擎上實作；E-Ink 影像濾鏡功能對等；PDF 工具列 FAB 化（含新增目錄與書籤 toggle）。
- 不涵蓋：手寫/自由繪圖標註（另立後續 Epic）；全書庫全文檢索 FTS5（既有 Backlog，不整合）；EPUB 任何既有行為變更；iOS 實作（`epic-13-ios` 仍是最低優先順序，`pdfrx` 的 iOS 相容性是附帶效益，非本次驗收範圍）。
- 技術風險不透過事前 Spike 排除，改於實作／真機驗證階段處理（決策 5）。

## 開放問題（留給 Architecting／`spec.md`）

- **`content://` URI 相容性**（`/superpowers:receiving-code-review` 審查回應，見下方）：`Book.filePath`（`content://`/`file://` URI，ADR 0002）能否直接餵給 `pdfrx`。PDFium C++ 核心不太可能直接接受一個 URI 字串，但**不應以「一律落地複製到本機快取」解決**——ADR 0002 當初明確決定「不複製、直接引用原始檔案」，理由正是「100MB 以上的 PDF、多本書籍匯入會造成可觀的雙倍儲存空間佔用」，現行原生 `PdfRenderer` 也確實透過 `ContentResolver.openFileDescriptor()` 直接餵 `ParcelFileDescriptor`、不落地複製。`pdfrx` 提供 `PdfDocument.openCustom(read: FutureOr<int> Function(Uint8List buffer, int position, int size), ...)`，可從自訂來源（例如既有的 `ParcelFileDescriptor`／`ContentResolver` 串流）讀取，不需要真實檔案路徑也不需要整包複製——**spec.md 應優先評估用 `openCustom` 橋接既有檔案描述符存取方式，維持 ADR 0002 的不複製原則；只有這條路徑證實不可行（例如 FFI 邊界與非同步 platform channel 讀取的介接問題）才退回落地複製到本機快取**，且落地複製須僅限於這個回退情境，不做為預設行為。
- 新增 `dart:ffi` 原生函式庫依賴（PDFium `.so`）對 APK 體積、建置流程（`build.gradle.kts`）、既有 `minSdk 24` 相容性的影響。
- PDF 專屬 TOC UI 元件是重用 EPUB 既有 `TocBottomSheet`（格式無關化）還是另建一份——傾向重用：規劃一個格式無關的抽象項目介面（例如 `BookTocItem`，涵蓋標題／定位點／子項層級），讓 `TocBottomSheet` 消費這個抽象介面而非直接依賴 EPUB 的 `TocEntry`，PDF 端提供 `loadOutline()` 結果轉換出的對應實作，避免 EPUB／PDF 兩份平行 UI 在樣式或 E-Ink 主題適配上出現不一致（`spec.md` 需具體定義該抽象介面的欄位）。
- 是否需要支援 PDF 邏輯頁碼標籤（Page Label），或維持現行純數字頁碼顯示——傾向雙顯示（例如「iii (3/150)」，邏輯頁碼＋實體頁碼/總頁數並列），跳頁/進度換算邏輯一律以絕對 0-indexed `pdfPageIndex` 為準，避免 Page Label 非數字（羅馬數字等）或不連續時導致跳頁運算錯誤。
- `_openPdfProgressSheet()`／`_openFoliateProgressSheet()`（原 `epic-23` 開放問題，見決策 6）沿用討論：兩者高度相似，是否值得抽出共用邏輯。

## 審查回應（`/superpowers:receiving-code-review`，2026-08-06）

`tmp/epic-24/design_review_report.md` 對本文件審查結論為「原則上通過」，0 Critical／2 Important／2 Minor。逐項核實程式碼現況後：

- **Important 1（E-Ink 影像處理效能）**：技術上合理，設計文件原本沒有規範影像處理執行緒策略，採納，新增決策 8。
- **Important 2（`content://` URI 相容性）**：底層疑慮（PDFium 核心通常需要檔案路徑或明確 byte 來源）成立，但建議的解法（強制落地複製，經由「`BookStorageService`」）**部分駁回**——`grep` 確認 `BookStorageService`在整個 codebase 中不存在，且「一律落地複製」直接推翻既有 **ADR 0002**（當初明確決定不複製、避免大型 PDF 雙倍儲存空間佔用）。查證 `pdfrx` 官方文件確認 `PdfDocument.openCustom()` 支援自訂讀取 callback，技術上可以橋接既有 `ContentResolver` 檔案描述符存取、不需要落地複製，已改寫開放問題為「優先評估 `openCustom`，只有證實不可行才退回落地複製」。
- **Minor 3（Page Label 顯示）／Minor 4（TOC 元件重用）**：技術上合理，予以採納，充實對應開放問題的具體方向。
