# Flutter 多載具 PDF Reader 解決方案研究分析報告

**專案名稱**：elinkBook (Flutter Android / 多載具電子書閱讀器)  
**分析日期**：2026-08-06  
**報告路徑**：`U:\MyDeveloper\AI\elinkBook\tmp\pdf_reader_solutions_research.md`  
**報告目的**：針對 Flutter 多載具（以 Android 為首要目標，兼顧 iOS/Desktop 跨平台擴充性與 E-Ink 裝置特性）評估三種主流 PDF 閱讀器技術架構方案，分析其優缺點、開源專案/APP 實例、依據五大優先需求之可行性對比、熱門 GitHub 應用案例與選型建議。

---

## 核心需求優先次序 (User Priority Framework)

1. **雙頁並列閱讀 (Facing Pages / Two-Page Spread View)** ⭐️⭐️⭐️⭐️⭐️
2. **解析 TOC 目錄 (Table of Contents / Outline Tree Parsing)** ⭐️⭐️⭐️⭐️
3. **頁次 頁數應用 (Page Metadata, Jump to Page, Page Labels)** ⭐️⭐️⭐️
4. **書籤 (App Bookmarks & Named Destinations)** ⭐️⭐️
5. **畫線註記 (Text Highlighting, Rect Annotations & Selection Overlay)** ⭐️

---

## 摘要與評估總覽

在 Flutter 跨平台開發中，PDF 閱讀器的實作主要分為以下三大架構方向：

| 評估面向 | 方案一：Native PlatformView 模式 | 方案二：C/C++ Core (PDFium/MuPDF) + Dart FFI 模式 🌟 | 方案三：Web / JS Engine (PDF.js) + WebView 模式 |
| :--- | :--- | :--- | :--- |
| **代表核心/庫** | Android `PdfRenderer` / iOS `PDFKit` / `pdfx` | Google `PDFium` / `MuPDF` / `pdfrx` | Mozilla `PDF.js` / Foliate JS |
| **iOS 相容性** | ⚠️ **需另外撰寫 iOS `PDFKit` 原生代碼** | ⚡️ **100% 完美適用 iOS (透過 iOS `.xcframework`)** | ⚡️ **支援 (iOS WKWebView)** |
| **1. 雙頁並列** | ⚠️ **需自訂 Native View繪畫/組合** | ⚡️ **原生內建 API (pdfrx 支援完整)** | ⚡️ **PDF.js spreadMode 支援** |
| **2. TOC 目錄解析** | ❌ **Android PdfRenderer 不支援** (需外掛 PDFBox) | ⚡️ **PDFium FPDFBookmark API 秒讀** | ⚡️ **PDF.js getOutline() 支援** |
| **3. 頁數頁次應用** | 🟢 **基本頁次支援，無 Page Label** | ⚡️ **頁數、Page Labels 完整** | ⚡️ **頁數、Page Labels 完整** |
| **4. 書籤管理** | 🟢 **App 層 DB 持久化無異** | 🟢 **App 層 DB 持久化無異** | 🟢 **App 層 DB 持久化無異** |
| **5. 畫線註記** | 🟡 **需手動座標對齊 (如 OverlayView)** | 🟢 **Text Bounding Box + CustomPainter** | ⚡️ **HTML Text Layer 天生選字** |
| **Android 效能** | ⭐️⭐️⭐️⭐️⭐️ (原生硬體加速) | ⭐️⭐️⭐️⭐️ (C++ 核心快，Dart 繪製) | ⭐️⭐️⭐️ (WebView 開銷較高) |
| **E-Ink 墨水屏優化** | ⭐️⭐️⭐️⭐️⭐️ (直連 Bitmap / Android Canvas 處理) | ⭐️⭐️⭐️⭐️ (Dart Canvas/Bitmap 可動態處理) | ⭐️⭐️ (DOM / Web Paint 刷屏不易控) |

---

## 🔍 特別分析：`pdfrx` (PDFium + Dart FFI) 於 iOS 之適用性說明

### 1. pdfrx 適用於 iOS 嗎？
**答：100% 適用且表現極佳！**

`pdfrx` 不僅適用於 Android，更完整原生支援 **iOS**（以及 macOS、Windows、Linux 與 Web）。

### 2. iOS 上的運作機制與架構
* **底層動態庫**：`pdfrx` 將 Google PDFium C++ 庫編譯為 iOS 專用的 iOS Framework (`.xcframework`)，並透過 CocoaPods 自動整合至 iOS 專案。
* **Dart FFI 直連**：在 iOS 執行期，Flutter 經由 `dart:ffi` 直接呼叫 iOS 應用包內的 PDFium C API。無須建立 PlatformView，直接解碼為圖像數據後在 Flutter 渲染樹繪製。

### 3. iOS 採用 pdfrx 的優勢 vs 原生 PDFKit
1. **100% 雙平台邏輯與 UI 程式碼共用**：
   * 若採用方案一 (Native View)，Android 需要寫 Kotlin `PdfRenderer`，iOS 需要寫 Swift `PDFKit`，兩平台在「雙頁並列排版」、「TOC 目錄 UI」與「劃線手勢座標」上需編寫兩套完全不同的 Native 代碼。
   * 若採用 `pdfrx`，iOS 與 Android 共享 **100% 相同的 Dart 排版與雙頁/目錄程式碼**。
2. **五大需求在 iOS 上完全一致**：
   * **雙頁並列**：在 iOS 平板 (iPad) 上同樣開箱即用支援 `spreadMode` 雙頁並列。
   * **TOC 樹狀目錄**：在 iOS 上呼叫 `loadOutline()` 速度與 Android 一樣達到毫秒級。
   * **效能出色**：得益於 Apple A/M 系列晶片的強大算力，PDFium C++ 解碼在 iOS 上流暢度極高。

---

## 🌟 熱門 GitHub 開源應用案例分析 (`pdfrx` / PDFium FFI)

以下檢列目前 GitHub 上最受歡迎、採用 `pdfrx` (PDFium + Dart FFI) 技術模式進行開發的三大熱門開源專案與優缺點分析：

### 1. [Saber (`saber-notes/saber`)](https://github.com/saber-notes/saber) — 跨平台手寫筆記與 PDF 標註 App
* **專案簡介**：GitHub 上極具盛名的開源手寫筆記與 PDF 標註應用程式，完全使用 Flutter 開發，並採用 `pdfrx` (PDFium) 作為其 PDF 頁面解碼與向量繪圖的核心。
* **優點**：
  * 完美展現了 `pdfrx` 的高效率解碼能力，將 PDF 頁面圖像與向量手寫/劃線 Overlay 完美融合。
  * 手勢縮放、滾動流暢，Stylus/手寫筆觸控延遲極低。
  * 支援全平台 (Android, iOS, Windows, macOS, Linux, Web)。
* **缺點**：
  * 偏向電子筆記與手寫板定位，缺乏電子書閱讀器專用的 TOC 書籤選單與雙頁並列切換邏輯。

### 2. [espresso3389/pdfrx (Official Viewer Engine)](https://github.com/espresso3389/pdfrx) — 官方全功能閱讀與編輯標竿
* **專案簡介**：`pdfrx` 官方儲存庫 (`packages/pdfrx/example/viewer`) 所附帶的完整閱讀與頁面處理標竿應用。
* **優點**：
  * **完整實現 5 大需求**：原生內建樹狀 TOC 目錄樹 (`loadOutline`)、單雙頁動態配置 (Facing Spread)、內文動態搜尋高亮與頁碼縮圖 (Thumbnails)。
  * **架構極度優雅**：採用純 Dart 解耦的 `pdfrx_engine` 與 UI 視圖層分離，可直接作為 elinkBook 重構 PDF 閱讀器的技術範本。
* **缺點**：
  * 屬於參考示範應用，未包含圖書資料庫 (Book Library DB) 管理與雲端同步功能。

### 3. [Paperless-Mobile (`astubenbord/paperless-mobile`)](https://github.com/astubenbord/paperless-mobile) — 開源文件歸檔與 PDF 檢視 App
* **專案簡介**：用於連接 Paperless-ngx 開源文件管理系統的 Flutter 行動客戶端，底層採用 PDFium/`pdfrx` 進行文件渲染、抽字與 PDF 檢視。
* **優點**：
  * 針對大批次、數百頁的大型掃描 PDF 文件具備優異的載入效能與記憶體控制。
  * 精準支援 PDF 內文文字選取 (Text Selection) 與 OCR 文字高亮。
* **缺點**：
  * UI 針對公務文件檢視設計，缺乏雙頁並列與小說/電子書小說式的翻頁體驗。

---

## 🔗 pdfrx (PDFium + Dart FFI) 技術官網與資源

* **`pdfrx` GitHub 官方儲存庫**：  
  👉 [https://github.com/espresso3389/pdfrx](https://github.com/espresso3389/pdfrx)
* **`pdfrx` Pub.dev 套件官網**：  
  👉 [https://pub.dev/packages/pdfrx](https://pub.dev/packages/pdfrx)
* **Google `PDFium` 底層 C++ 引擎官網**：  
  👉 [https://pdfium.googlesource.com/pdfium/](https://pdfium.googlesource.com/pdfium/)

---

## 五大優先需求之詳細技術比較

### 需求 1：雙頁並列閱讀 (Two-Page Spread View)
* **方案一 (Native PlatformView)**：
  * **難度**：中高。Android `PdfRenderer` 一次僅能 openPage 一頁並 render 到單張 Bitmap。若要雙頁，Native 端需建立 ViewPager2 / RecyclerView 的雙頁 Layout，或是手動創建一張雙倍寬度的 Bitmap 進行拼接，記憶體控管與邏輯複雜度較高；iOS 則需調用 `PDFView.displaysAsBook = true`。
* **方案二 (C/C++ Core + Dart FFI - pdfrx/PDFium)**：
  * **難度**：極低 (成熟)。`pdfrx` 在 Dart 端由 Layout Manager 統一管理視圖。只需設定 `spreadMode` 或使用 `PdfViewerParams(layoutPages: ...)` 即可在 Android 與 iOS 自由組合單頁、雙頁 (Facing Pages)、首頁獨立雙頁、連續垂直/水平滾動。
* **方案三 (Web PDF.js)**：
  * **難度**：低。PDF.js 內建 `pageLayout` 與 `spreadMode` (0=Off, 1=Odd, 2=Even)，可直接在 JS 控制切換雙頁。

### 需求 2：解析 TOC 目錄 (Table of Contents / Outlines)
* **方案一 (Native PlatformView)**：
  * **難度**：極高 (缺陷)。Android 原生 `android.graphics.pdf.PdfRenderer` **完全不提供**解析 PDF 目錄 (Outlines / Bookmarks Tree) 的 API。若要解析 TOC，必須額外打包龐大的 Java/Kotlin PDF 解析庫（如 `PdfBox-Android` 或 `iText`），導致 APP 體積爆增且維護成本極高。
* **方案二 (C/C++ Core + Dart FFI - pdfrx/PDFium)**：
  * **難度**：極低。PDFium 底層具備完整的 `FPDFBookmark_*` C API。`pdfrx` 已預設封裝 `document.loadOutline()`，在 Android 與 iOS 上均可直接異步回傳樹狀目錄階層 (Title, PageNumber, DestRect)。
* **方案三 (Web PDF.js)**：
  * **難度**：低。PDF.js API 包含 `pdfDocument.getOutline()`，異步傳回階層式的 Outline JSON 物件。

### 需求 3：頁次頁數應用 (Page Metadata, Jump to Page, Page Labels)
* **方案一 (Native PlatformView)**：
  * 提供基本的 `pageCount` 頁數與 `openPage(index)`。但不支援 PDF 邏輯頁碼標籤 (Page Labels, 如封面 Roman 數字 `i, ii`, 正文 `1, 2, 3`)。
* **方案二 (C/C++ Core + Dart FFI)**：
  * 支援 `pageCount`、`jumpToPage(index)`、雙頁動態頁碼計算，並可呼叫 PDFium `FPDF_GetPageLabel` 讀取原書邏輯頁碼標籤（Android/iOS 通用）。
* **方案三 (Web PDF.js)**：
  * 支援完整頁次跳轉、`pageCount` 以及 `pageLabel` 獲取。

### 需求 4：書籤功能 (Bookmarks Management)
* **普遍做法**：
  * 書籤分為兩類：
    1. **PDF 檔案內建書籤**：即需求 2 的 TOC 目錄或 Named Destinations。
    2. **使用者自訂書籤**：屬於 **App 應用層功能**。應用層在本地 SQLite 資料庫（elinkBook 偏好/閱讀狀態持久化）中建立 `bookmarks` 資料表（紀錄 `book_id`, `page_index`, `title`, `created_at`）。
* **方案對比**：三個方案在 App 自訂書籤方面完全平手，因為狀態與 UI 完全由 Flutter Dart 控制。

### 需求 5：畫線註記 (Text Highlighting & Annotations)
* **方案一 (Native PlatformView)**：
  * 需由原生 View 處理 Touch 手勢並計算字元矩形，或如 elinkBook 現行架構：在 Flutter 端用 `GestureDetector` 計算座標，透過 Channel 傳給原生 `HighlightSelectionOverlayView` 繪製 Canvas 劃線。
* **方案二 (C/C++ Core + Dart FFI)**：
  * PDFium 支援 `FPDFText_*` API 可精準抽字與取得各字元的 Exact Bounding Box。Dart 端可由 `CustomPainter` 在 PDF 圖層上方直接繪製高亮筆劃、畫線，並可呼叫 PDFium 保存註記 (PDF Annotations) 回原檔。
* **方案三 (Web PDF.js)**：
  * 利用 PDF.js 的 HTML Text Layer，天生具備瀏覽器文字選擇 (Text Selection) 與高亮 DOM 的能力。

---

## 方案詳細評估

### 方案一：Native Platform View 模式 (Android PdfRenderer / iOS PDFKit)
* **代表開源/實例**：`pdfx`, `flutter_pdfview`, elinkBook 現行 `PdfReaderView.kt`
* **優點**：
  * **E-Ink 墨水屏處理極佳**：Native 端 `PdfImageProcessor` 可針對 Bitmap 進行形態學膨脹（文字加粗）、對比度調整與智慧白邊裁切，極度適合 Android 電子書硬體。
* **缺點**：
  * ⚠️ **無法原生解析 TOC 目錄**（需額外引入大庫）。
  * ⚠️ **Android 與 iOS 雙平台需維護兩套 Native View 代碼**。

### 方案二：C/C++ Core (PDFium / MuPDF) + Dart FFI 模式 🌟
* **代表開源/實例**：[`pdfrx`](https://pub.dev/packages/pdfrx) (PDFium FFI), **KOReader** (MuPDF 核心), Google Chrome (PDFium 核心)
* **優點**：
  * ⚡️ **完美支援 Android 與 iOS (100% 邏輯與 UI 程式碼共用)**。
  * ⚡️ **完美滿足 5 大需求**：原生內建雙頁並列 (Facing Spread)、樹狀 TOC 解析、完整 Text Page Bounding Box 畫線註記與邏輯頁碼。
* **缺點**：
  * E-Ink 影像強化（如形態學膨脹加粗）需在 Dart 端操作 `Uint8List` 或封裝 C/C++ 影像處理。

### 方案三：Web / JS Engine (PDF.js / Foliate JS) + WebView 模式
* **代表開源/實例**：**Foliate** (Linux 閱讀器), Firefox (PDF.js)
* **優點**：
  * 架構與 `FoliateEpubReaderView` 完全統一，天生支援 HTML Text Layer 選字與 TOC。
* **缺點**：
  * ⚠️ **WebView 在 E-Ink 墨水屏殘影嚴重、刷屏效能較差，且大檔案易 OOM**。

---

## 最終結論與選型建議

根據您的 **5 大優先需求順序**（1.雙頁並列 > 2.解析TOC > 3.頁次頁數 > 4.書籤 > 5.畫線註記）與 **iOS 跨平台適配性**：

### 💡 強烈推薦選型：**方案二（`pdfrx` / PDFium + Dart FFI 模式）**

1. **完全適用於 iOS 與 Android**：
   * `pdfrx` 內建 iOS `.xcframework` 支援，能在 iOS 上完美運行。
   * **最大的好處**：Android 與 iOS 的「雙頁並列」、「TOC 樹狀目錄」與「畫線註記」完全使用 100% 相同的 Dart 程式碼，無需為 iOS 重寫 `PDFKit` 視圖。
2. **需求契合度最高**：
   * 現有 Android `PdfRenderer`（方案一）**無法直接解析 TOC** 且 **雙頁並列實現困難**。
   * `pdfrx` (PDFium) 出廠即內建 **雙頁並列 (Facing Spread)**、**樹狀 TOC 解析 (`loadOutline`)** 與 **文字定位畫線 API**。
3. **E-Ink 墨水屏相容做法**：
   * 將現有 `PdfImageProcessor` 的影像處理解析（對比度調整/智慧裁切）改在 Dart Isolate 或 C++ 層微調 Bitmap，即可同時兼顧 **E-Ink 刷屏品質** 與 **Android / iOS 多載具跨平台需求**。
