# CLAUDE.md

本檔案為 Claude Code（claude.ai/code）在此儲存庫中工作時的指引文件。

## 儲存庫現況

大多數核心閱讀體驗 Epic 已完成並歸檔（`docs/archive/`）：技術骨架、圖書庫管理（匯入/分類/排序）、直排/橫排核心、字型與版面設定、PDF 專業增強、目錄與頁碼、註記（書籤/劃線/備註）、互動控制（音量鍵/導航熱區）、雙頁顯示、EPUB 渲染引擎遷移（Readium→foliate-js，見下方）皆已可用。尚未開始的功能見 `docs/epics.md` Backlog 列（雲端同步、閱讀統計、全文檢索、TXT 引擎、社群分享、iOS 移植、系統設定、傳統儲存權限）。目前 Active 的 Epic 包含真機 UI 精修與書架/閱讀體驗強化，以及 `epic-24-pdf-engine-rebuild`（PDF 渲染引擎自平台原生 API 遷移至 pdfrx／PDFium，見下方「技術棧（已決策）」的「架構遷移中」說明——Issue 1-8 全數已合併），現況與優先順序一律以 `docs/epics.md` 為準——本檔案不重複記錄逐一 Epic 的完成狀態。

`prototype/index.html` 是一份獨立、依需求文件製作的 HTML/CSS/JS UI/UX 原型（手機外殼模擬器），後續功能性 Epic 設計畫面時應先參考它，細節見下方「UI/UX 原型參考」。

## 常用指令

所有指令皆在 `app/` 目錄下執行。

```bash
flutter pub get
flutter test
flutter test test/screens/reader_screen_test.dart

# 提交前必須乾淨（"No issues found!"）
flutter analyze

flutter devices

# 必須指定真實裝置/模擬器（見下方「兩層測試架構」，一般 flutter test 做不到這件事）
flutter test integration_test/reader_screen_test.dart -d <device-id>

flutter build apk --debug
```

## 高層架構

### `ReaderScreen`：唯一的閱讀器 seam

`app/lib/screens/reader_screen.dart` 是格式無關的統一入口，依 `detectBookFormat()`（`app/lib/reader/book_format.dart`，依副檔名判斷 `epub`/`pdf`/`unknown`）與（EPUB 專屬）`Book.isFixedLayout`（是否為固定版面 FXL）分派到兩條完全獨立的渲染路徑之一：

- `PdfReaderView`（`app/lib/reader/pdf_reader_view.dart`）——純 Dart widget，底層為 `pdfrx`（PDFium 透過 `dart:ffi` 直接呼叫，非 `PlatformView`，見 ADR 0022、`epic-24-pdf-engine-rebuild` Issue 1，2026-08-07 已合併）。單頁顯示＋頁碼＋跳頁＋`content://` URI 存取（Issue 1）、三態雙頁並列（Issue 2，2026-08-09 已合併，底層改由 `pdfrx` 的 `layoutPages`/`calculateCurrentPageNumber` 客製化排版 API 實作，取代自行拼接點陣圖）與 E-Ink 影像濾鏡/裁切（Issue 3，2026-08-09 已合併：對比度/亮度用 `ColorFiltered` 即時渲染、加粗/裁切透過 `page.render()`＋背景 Isolate＋`pageOverlaysBuilder` 疊加覆蓋圖——`Isolate.run()` 的 closure 須宣告為獨立於 State 之外、參數列僅含可跨 isolate 傳遞型別的頂層函式，否則 Dart VM 會把 closure 所在整個詞法作用域一併打包，牽連 `PdfPage`/`PdfDocument` 內部不可傳遞的 rxdart `BehaviorSubject` 導致執行期例外）與劃線/備註/書籤遷移（Issue 4，2026-08-10 已合併：長按拖曳框選矩形＋`AnnotationToolbar` 接線＋書籤 toggle，`pageOverlaysBuilder` 逐頁疊加手勢層使雙頁模式下座標歸屬單一頁面有構造性保證）已實作。目錄（TOC，Issue 5，2026-08-10 已合併）：新增格式無關的 `BookTocItem` 抽象介面，EPUB 既有 `TocEntry` 透過 Dart 協變泛型零成本接入（見 `app/lib/reader/toc_entry.dart`／`book_toc_item.dart`），PDF 端由 `PdfReaderView.loadTableOfContents` 解析 `pdfrx` 大綱轉換為 `PdfTocItem`；`TocBottomSheet` 新增 `format` 參數，PDF 版以 `DefaultTabController` 提供「章節目錄／縮圖／搜尋」三分頁殼層（縮圖/搜尋分頁為 Issue 6/7 預留，目前僅佔位文字）；PDF 目錄的可見觸發按鈕（`reader_pdf_toc_button` FAB）已隨 Issue 8 接線完成（見下方）。內文搜尋（Issue 6，2026-08-10 已合併）：新增純函式模組 `pdf_search_match.dart`／`pdf_search_geometry.dart`（`PdfSearchMatch`、PDF points→`PercentRect` 座標轉換，含邊界 `.clamp`）與 `pdf_search_state.dart`；`PdfReaderView.search()`/`setSearchHighlights()` 刻意避開 `PdfTextSearcher`/`PdfViewerController.useDocument`（實測確認在 `testWidgets`/fake-async 環境下有死鎖風險），改直接呼叫 `page.loadStructuredText()`/`PdfPageText.allMatches()`，高亮渲染重用既有 `_buildProcessedOverlay`/`originalToCropRelativePercent()` 管道取得裁切模式相容性；`TocBottomSheet` 新增 `searchTabContent: Widget?` 插槽掛載新增的 `PdfSearchPanel` widget（500ms 防手震、上一個/下一個循環導覽）；`ReaderScreen` 以雙層世代 ID（`PdfReaderView._searchSessionId` + `ReaderScreen._pdfSearchRequestId`）防護非同步競態。頁碼縮圖（Issue 7，2026-08-10 已合併）：新增與 `dart:ui`/Flutter 無關的泛型 `PdfThumbnailCache<T>`（純 Dart LRU 快取，供釋放策略獨立可測試）；`PdfReaderView.renderThumbnail()` 靜態方法透過 `page.render(fullWidth:, fullHeight:)` 依頁面原始長寬比等比例換算縮圖尺寸，不需額外 Isolate（已查證 pdfrx 底層透過 `BackgroundWorker` 背景 worker 執行）；新增 `PdfThumbnailPanel` widget（`GridView.builder` 延遲建構＋`PdfThumbnailCache` 整合，與 `ReaderScreen`／`PdfReaderView` 完全解耦，比照 `PdfSearchPanel` 既有設計，只透過 `renderThumbnail`/`onPageSelected` 兩個函式型別參數溝通）；`TocBottomSheet` 新增 `thumbnailTabContent: Widget?` 插槽掛載此 widget；`ReaderScreen` 依 `devicePixelRatio` 換算實際渲染寬度（夾限 `[1.0, 3.0]`）。閱讀工具列 FAB 化（Issue 8，2026-08-11 已合併）：PDF 頂部常駐 `AppBar` 與對應原生 method channel 契約完全退場，改為 6 顆浮動圓形按鈕（返回／目錄／版面設定／書籤 toggle／筆記／進度-跳頁），視覺與位置比照 EPUB 既有樣式；新增 `_PdfNavZoneTapDetector` 提供 PDF 版 3×3 導覽熱區，手勢隔離策略與 EPUB 既有 `_NavZoneTapDetector` 相同（`Listener` + `HitTestBehavior.translucent`，不進手勢競技場），但按壓時長改用 `package:clock` 的 `clock.now()`（而非該檔案用的 `DateTime.now()`）量測——`flutter_test` 的 FakeAsync 會攔截 `clock` 套件的 Zone 覆寫使其隨 `tester.pump()` 正確推進，正式裝置上則一律取得真實系統時間，不像一度嘗試過的 `SchedulerBinding.currentSystemFrameTimeStamp` 只在畫面有新 frame 排程時才更新；兩者刻意各自獨立實作、不抽成共用模組。Page Label（PDF 邏輯頁碼標籤雙顯示）因 `pdfrx` 未暴露對應 API，移出本工單範圍，目前僅純數字頁碼顯示。**Epic 24 規劃的全部 8 個 Issue 皆已完成**，查閱前務必先看 `docs/epics.md` 確認 `epic-24` 最新狀態。
- `FoliateEpubReaderView`（`app/lib/reader/foliate_epub_reader_view.dart`）——**所有 EPUB 使用**（FXL 與流式），`readest/foliate-js`（釘定 commit、直接複製進版控、不經 npm 建置，見 `app/android/app/src/main/assets/foliate/`）跑在 `flutter_inappwebview` 的 `InAppWebView` 內，**不是**傳統 `AndroidView`/`PlatformView`（`MainActivity.kt` 沒有為它註冊 `PlatformView` 類型字串），透過 `foliate_native_bridge.dart` 與原生端（`elinkbook/volume_key` 頻道的 `attachReaderView`/`detachReaderView`）溝通生命週期，JS↔Dart 契約定義在 `main.js`（見 ADR 0011、ADR 0013、ADR 0017）。這份釘定的 vendor 程式碼會無條件使用較新的 ES 內建方法（真機 `/diagnose` 已發現兩輪：`Object.groupBy`/`Map.groupBy`、`Array.prototype.at`/`findLastIndex`），較舊的 Android System WebView 不支援時需要在 `_esCompatPolyfillJs` 補 polyfill（透過 `initialUserScripts` 於 `AT_DOCUMENT_START` 注入，不修改釘定版本本身）；**每次升級這份釘定版本後**都要跑 `node app/tool/check_foliate_es_compat.js` 靜態掃描有沒有新的較新 API 用法還沒設防（見 `app/tool/README.md`）。

`PdfReaderView` 對外建構參數為 `filePath`/`onPageRendered`/`onError`/`initialPageIndex`/`onPageChanged`（Issue 1）加上 `dualPageMode`/`dualPageCoverAlone`/`dualPageDirection`/`isLandscape`（Issue 2，`dualPageMode` widget 層預設 `DualPageMode.never`，維持既有呼叫端零回歸；產品預設 `auto` 由 `reader_screen.dart` 明確傳入），靜態 helper（`jumpToPage`/`previousPage`/`nextPage`/`refreshAnnotations`，後者目前為 Issue 4 落地前的暫時性 no-op）維持與舊版相容的方法簽章。`content://` URI 存取走原生端 `ReaderResourceChannel.kt`（`elinkbook/reader_resources` channel 的 `readContentUriAll` 方法）串流複製到本機暫存檔後回傳路徑字串，再以 `PdfDocument.openFile()` 開啟——這是計畫原先優先評估的 `pdfrx.openCustom()` 隨機存取分段讀取被證實有 FFI 非同步限制後、已文件記錄的回退路徑，非整包讀進記憶體（見 `ReaderResourceChannel.kt` class doc）。`FoliateEpubReaderView` 刻意不比照這個模式（見上方）。EPUB 一律建構 `FoliateEpubReaderView`，不再依 FXL/流式分派到不同 widget（見 ADR 0017）。

`ReaderScreen` 對外的公開建構參數為 `filePath`／`bookId`／`prefsRepository`／`bookTitle`（`bookTitle` 由 Issue 23 新增，頁首找不到章節資訊時的回退顯示文字；其餘由 `epic-3-fonts-layout` Issue 3 新增；`prefsRepository` 由 `main.dart` 建構後，與 `LibraryRepository`/`BookImportService` 平行、逐層透過建構子參數傳遞下來，`LibraryRepository` 抽象介面本身不受影響，見 `docs/adr/0007-reader-screen-book-id-contract.md`）——載入中／錯誤狀態是內部實作細節，透過固定的 `Key('reader_loading_indicator')`／`Key('reader_error_text')` 暴露給測試觀察，刻意不新增公開 callback 參數。

`MainActivity` 仍是 `FlutterFragmentActivity`（而非 Flutter 預設的 `FlutterActivity`）——ADR 0017 原規劃隨 Readium FXL 路徑退場一併改回 `FlutterActivity`，但實作 epic-20 Issue 5 時發現資料夾匯入功能（`epic-1` Issue 8）的 `openDocumentTreeLauncher = registerForActivityResult(...)` 依賴 `FragmentActivity` 家族才能使用，`FlutterActivity` 不支援，故維持 `FlutterFragmentActivity`；與 Readium 的 `EpubNavigatorFragment` 已無關。

### 兩層測試架構

- `app/test/`——純 Dart／widget test，`flutter test` 即可執行，不需裝置。適用於格式偵測邏輯，以及不涉及原生 `PlatformView` 渲染的畫面行為。
- `app/integration_test/`——**必須**在真實 Android 裝置/模擬器上執行（`-d <device-id>`）。一般 widget test 無法觀察 `PlatformView` 內部的真實渲染結果，因此「原生渲染是否真的成功」一律由這裡驗證：斷言方式是等待 `Key('reader_loading_indicator')` 消失且無 `Key('reader_error_text')`，而非直接掛 callback（`ReaderScreen` 對外沒有暴露 callback，見上方）。
- 已提交版本控制的範例測試檔：`app/test/fixtures/sample.epub`／`sample.pdf`（在 `pubspec.yaml` 宣告為 asset），供上述測試使用（見下方「`LibraryScreen` 與圖書庫管理」）。

### `LibraryScreen` 與圖書庫管理

`app/lib/screens/library_screen.dart` 是真正的書架畫面，資料一律經 `LibraryRepository`（抽象介面，`app/lib/library/library_repository.dart`；正式實作 `SqliteLibraryRepository`，`sqflite`）存取，不再有固定範例書籍。核心概念：

- **`Book`**（`app/lib/library/models/book.dart`）：`filePath` 是 `content://`/`file://` URI 或本機路徑（見 ADR 0002）——匯入時是否落地成 App 私有複本依權限/副檔名判斷情況而定，不能假設一定是本機檔案；`coverPath` 一律是本機複本。`groupName` 為單選分類（非多對多標籤），系統保留值 `BookGroup.uncategorized`（「未分類」）不可刪除/改名。
- **匯入**：`BookImportService`（檔案/資料夾選取，可選依資料夾名稱自動建立分類）。
- **批次操作**：長按書籍項目進入選取模式（`_selectedBookIds`），選取工具列目前支援「移動到分類」（其餘批次動作視各 Epic 進度增減，見 `docs/epics.md`）。
- **檢視模式**：格狀（`SliverGridDelegateWithFixedCrossAxisCount`，欄數依螢幕方向調整）／列表，皆由 `LibraryPreferences`（`SharedPreferences`）記住使用者上次選擇。
- 舊有的固定範例書籍機制（`sample_books.dart`/`stageSampleBookFile()`）已隨圖書庫管理實作完成而移除；`app/test/fixtures/sample.epub`／`sample.pdf` 現在純粹是測試/整合測試 fixture，不再供 `LibraryScreen` 展示使用。

## 這是什麼產品

elinkBook（全能跨平台電子書閱讀器）是一款跨平台電子書閱讀器，核心差異化在於正確、高品質支援**直排（Vertical Writing）繁體中文排版**——包含正確的標點符號位置（破折號、引號）與避頭尾（換行規則）——並提供深度排版客製化與無縫跨裝置同步。

完整需求請見 `docs/prd.md`。實作前需要知道的重點：

### 支援格式與渲染方式
- **ePub3**（流式與定樣式）、**PDF**、**TXT** 為三大核心格式（P0）。
- ePub：自動偵測排版方向（見 FR-06），依書本 CSS 是否已宣告 `writing-mode` 判斷（判斷不出來則預設橫排），不做語言猜測。渲染架構已定案——見下方「技術棧（已決策）」（FXL 與流式皆用 foliate-js）。
- PDF：目標為 100MB 以上檔案開啟速度小於 2 秒；支援影像濾鏡（對比度/亮度/加粗）、智慧/手動裁切，預設採用 page-fit。渲染架構見下方「技術棧（已決策）」（`epic-24-pdf-engine-rebuild` 遷移至 pdfrx／PDFium 進行中，Issue 1 已合併——影像濾鏡/裁切/雙頁等能力待 Issue 2-8 陸續補回，見 `docs/epics.md`）。
- TXT：自動偵測編碼與章節標題，合成具估算頁碼的階層式目錄（固定字元數量的分頁換算啟發式）。
- 檔案匯入：本機檔案選擇器，並支援 Google Drive 與 OneDrive 雲端存取。Google Drive 登入/驗證/下載須在無 Google Play Services 的裝置上（例如部分 E-Ink 閱讀器）持續正常運作。

### 版面與排版
- ePub3/TXT 支援橫排與直排(vertical-RL) 一鍵切換。
- 內建預設字型皆完全離線渲染（本地 `@font-face`）：思源黑體與思源宋體（開源 SIL OFL 基礎字型），加上三款商用授權字型——原俠正楷、台灣圓體、源流明體。刪除目前使用中的自訂字型時須自動退回預設字型。
- 版面控制項：行距、段落間距、獨立的上/下/左/右邊距滑桿、換頁模式（捲動 vs. 無）、文字對齊、螢幕方向鎖定（0/90/180/270°）、「停用書本 CSS」開關。每個數值型控制項（字體大小、字重、行距/段落間距、邊距）除滑桿外都需要 +/- 微調按鈕。當螢幕方向未鎖定時，裝置旋轉須為新的可視範圍重新計算分頁。
- 直排(vertical-RL) 模式不得讓圖片或標題被切斷至跨頁。
- 標點符號在直排中文排版中必須正確轉向/置中，換行須遵守避頭尾規則（禁止特定字元出現於行首/行尾），符合 CNS 11643 或同等標準（FR-32）。
- 主題切換：深色、羊皮紙色、預設淺色主題，並與獨立的 E-Ink 高對比模式並存。

### 導航、註記、書籤
- 跨三種格式的通用目錄元件，顯示標題+頁碼，須於 200ms 內跳轉至目標位置。
- 書籤儲存一個定位點（EPUB：CFI；PDF：頁碼；TXT：字元偏移量）+ 章節名稱；支援重新命名、單筆刪除、「刪除該書所有書籤」。書籤管理屬於 MVP 範圍，並非後續階段項目。
- 劃線與備註是各自獨立的物件類型（備註不會覆蓋劃線）；兩者在直排/橫排切換時都須保持視覺一致。支援單筆編輯/刪除，以及劃線與備註各自的一鍵全刪（批次刪除前需經確認對話框）。
- 劃線支援多種顏色，加上獨立的「螢光筆」子類型。劃線/備註的定位精度須高於書籤：EPUB 用 CFI，PDF 用頁碼+頁內座標（不只是頁碼），TXT 用字元偏移量。
- 統一側邊欄列出所有劃線與備註（不含書籤，書籤有自己獨立的清單/畫面），點擊可跳轉至該位置。
- Markdown 導出涵蓋劃線、個人備註與書籤清單。

### 搜尋
- 全書庫全文檢索（書名、作者、書內內容），即使在約 1,000 本書規模下也要於 500ms 內出結果。建議做法：SQLite FTS5（或同等方案）索引。搜尋結果須支援跳轉至章節，並須將書名/作者匹配與書內內容匹配分開呈現。

### 同步
- 同步後端決策：**PocketBase**（曾考慮 Firebase/Supabase 作為替代方案）。
- 閱讀位置（EPUB：CFI；PDF：頁碼；TXT：字元偏移量）在 App 關閉/切換書籍時自動同步，並正確處理直排/橫排模式間的轉換；目標延遲 <2 秒，衝突解決成功率 99.9%。若開啟書籍時雲端同步的位置與本機位置不一致，須先詢問使用者確認才跳轉——絕不可靜默覆蓋。
- 閱讀時長統計每日儲存於本機，彙整成約 365 天規模的熱點圖/貢獻圖（參考模式：Readest）；點擊方格顯示當日詳情。計時須基於偵測到的實際閱讀活動（翻頁/捲動/長按），排除閒置或背景狀態的時間。

### 圖書庫管理
- 書架視圖：每列 6 本封面；另有含元數據+進度百分比的列表視圖。App 須記住使用者上次選擇的檢視模式。
- 封面產生策略：ePub → 內嵌封面圖；PDF → 首頁渲染；TXT → 依書名文字動態產生封面。
- 排序方式：最後閱讀（預設）、建立時間、作者或書名。

### 明確排除範圍（Out of scope）
- 不支援解除 DRM（例如 Adobe DRM）。
- 不提供電子書商店/購買或租閱流程。
- 不支援 PDF 內容編輯（文字/圖片修改）。
- 不含完整社交平台（動態牆、好友）——僅支援單向分享劃線/統計圖片。

### 互動模式
- 極簡、低干擾 UI；核心導航、目錄、基礎調整都須可透過可自訂的熱區單手操作。
- 導航區域：可自訂的 3×3 點擊九宮格，提供多種對應模式（傳統/單手/類 Kindle）；直排(RTL) 模式下，熱區映射須左右鏡像以符合由右至左的翻頁邏輯。
- 需支援音量鍵翻頁；離開閱讀畫面後，音量鍵須恢復正常系統音量控制。
- E-Ink 友善的高對比模式，並減少過渡動畫（避免殘影）。
- 手機版與桌面版應維持相近的按鈕/選單佈局邏輯，降低跨裝置重新學習的成本。

## 目前在此儲存庫中的工作方式

請將此處的任務視為：(a) 修訂 `docs/prd.md` 本身，或 (b) 透過下方的 SDD 工作流程進行後續 Epic 的開發（現況與優先順序一律以 `docs/epics.md` 為準）。

### UI/UX 原型參考

`prototype/index.html` 是依需求文件製作的獨立 HTML 原型（手機外殼模擬器 + 控制面板，涵蓋書架視圖、直排/橫排排版切換、多主題、版面客製化、九宮格導航熱區等）。`epic-0-skeleton` 之後的所有功能性 Epic（`epic-1` 起）在設計畫面 UI/UX 時，須先參考此原型既有的視覺與互動設計，作為 Flutter 實作的依據起點，而非重新發明。

### 技術棧（已決策）

- **App 外殼**：Flutter，跨平台共用。
- **手機優先，Android 先於 iOS。** 初期幾波不含桌面版目標（見 `docs/epics.md` 的 epic-13）。
- **Android 最低支援版本：Android 11 (API 30)**（見 `docs/prd.md` NFR-6）——不得將 Android 專案的 `minSdk`/相容性設定限制在比 API 30 更新的門檻。實際 `minSdk` 目前是 `24`（比政策門檻寬鬆；由 Readium `kotlin-toolkit`〔要求 23〕與 `integration_test` 外掛〔要求 24〕兩者疊加後的真實下限決定，見 `app/android/app/build.gradle.kts`），不是刻意收緊。
- **EPUB（單引擎，`readest/foliate-js`，見 ADR 0011、ADR 0017）**：
  - **所有 EPUB（FXL 與流式）**：`readest/foliate-js`（釘定 commit、直接複製進版控，不引入 Node.js/npm 建置工具鏈）跑在 `flutter_inappwebview` 的 `InAppWebView` 內（見 ADR 0013——標準 Flutter `AndroidView`+`android.webkit.WebView` 的觸控轉發機制無法完整還原「長按選字→拖曳選取控點」手勢，`flutter_inappwebview` 有自己獨立的原生嵌入機制解決此限制）。`_dispatchedIsFixedLayout` 決定 UI 版面語意（單頁/雙頁），不再決定要建構哪個 widget——EPUB 一律建構 `FoliateEpubReaderView`。
  - **歷史演進**：最初規劃「全部 EPUB 都用 Readium」（epic-0 時期），但 Readium reflowable Navigator 在直排/橫排跳頁上的已知缺口（CSS Multicolumn 規格層級限制，Readium 官方已擱置）促成 ADR 0011 決策改用 foliate-js 處理流式 EPUB；ADR 0017 進一步將 FXL 也遷移至 foliate-js，移除 `readium-navigator` 依賴。`readium-shared`／`readium-streamer` 保留供 `BookMetadataChannel.kt` 使用。
- **PDF（架構遷移中，`epic-24-pdf-engine-rebuild`，Active）**：此決策已被 [ADR 0022](docs/adr/0022-pdf-engine-migrate-to-pdfrx.md) 取代——改用 `pdfrx`（PDFium 透過 `dart:ffi` 直接呼叫，非 `PlatformView`）。**Issue 1（引擎基礎替換：單頁開書/頁碼/跳頁/`content://` 存取）已於 2026-08-07 合併**，舊原生 `android.graphics.pdf.PdfRenderer`／`PlatformView` 渲染叢集已完全清退，不再與新架構並存。**Issue 2（雙頁並列 Facing Spread）已於 2026-08-09 合併**，底層改由 `pdfrx` 的 `layoutPages`/`calculateCurrentPageNumber` 客製化排版 API 實作。**Issue 3（E-Ink 影像濾鏡/裁切功能對等）已於 2026-08-09 合併**，對比度/亮度改用 Flutter 內建 `ColorFiltered` 即時渲染（刻意偏離 `spec.md` 字面「一律 Isolate/debounce」要求，經人類確認採用）、加粗與裁切透過背景 Isolate 處理像素。**Issue 4（劃線/備註/書籤遷移）已於 2026-08-10 合併**，保留現行長按拖曳框選矩形為主要選取機制、`ReaderScreen` 接回既有死碼狀態機串接 `AnnotationToolbar`、新增書籤 toggle（直查 repository 避免快取未載入時的重複新增競態）。**Issue 5（目錄 TOC，`BookTocItem` 抽象介面）已於 2026-08-10 合併**，`TocBottomSheet` 泛化為 EPUB／PDF 共用元件，並補上 `issues.md` 要求、原規劃階段遺漏的分頁籤殼層（章節目錄／縮圖／搜尋）。**Issue 6（內文搜尋）已於 2026-08-10 合併**，`PdfReaderView.search()` 直接呼叫低階 `page.loadStructuredText()`/`PdfPageText.allMatches()`（避開 `PdfTextSearcher` 已知的測試環境死鎖風險），搜尋高亮重用既有裁切座標轉換管道、`PdfSearchPanel` 掛載於 Issue 5 的搜尋分頁。**Issue 7（頁碼縮圖）已於 2026-08-10 合併**，新增與 Flutter 無關的泛型 `PdfThumbnailCache<T>`（純 Dart LRU 快取），`PdfReaderView.renderThumbnail()` 透過 `page.render(fullWidth:, fullHeight:)` 依原始長寬比等比例換算縮圖尺寸（不需額外 Isolate），`PdfThumbnailPanel` widget（`GridView.builder` 延遲建構＋LRU 快取整合，與 `ReaderScreen`／`PdfReaderView` 完全解耦）掛載於 Issue 5 的縮圖分頁。**Issue 8（閱讀工具列 FAB 化，6 顆按鈕整合）已於 2026-08-11 合併**，PDF 頂部常駐 `AppBar` 與對應原生 method channel 契約完全退場，改為與 EPUB 對稱的 6 顆浮動圓形按鈕，並新增 `_PdfNavZoneTapDetector` 提供 PDF 版 3×3 導覽熱區（按壓時長改用 `package:clock` 的 `clock.now()`，兼顧正式裝置真實時間與 `flutter_test` FakeAsync 相容性）；Page Label（PDF 邏輯頁碼標籤雙顯示）因 `pdfrx` 未暴露對應 API 移出範圍，僅純數字頁碼顯示。**Epic 24 規劃的全部 8 個 Issue 皆已完成，PDF 閱讀的暫時性能力退化窗口已結束**，查閱前務必先看 `docs/epics.md` 確認 `epic-24` 最新狀態。手寫/自由繪圖標註明確排除、另立後續 Epic。
- **TXT**：自訂的輕量直排 CJK 排版引擎（獨立 epic —— `epic-11-txt-engine`，尚未開始），不採用 Readium/WebView 方案，因為純文字沒有 HTML/CSS 那層需要重新實作。

## Spec-Driven Development (SDD) 工作流程

本儲存庫採用結合 BMad Method 角色分工、Matt Pocock 規格先行嚴謹度、以及 Superpowers 審查機制的規格驅動開發工作流程。可執行實作工作的有兩個角色：**Claude Code** 與 **Antigravity CLI**。切換到 Antigravity CLI 一律由人工手動指定——絕不可自行假設或觸發。若需要派出「實作者」子代理但人類尚未明確指定使用 Antigravity CLI，一律使用 Claude Code 的 subagent（也就是目前正在使用的同一個 LLM/工具），不可模擬呼叫 Antigravity。

**審查一律先產出報告，嚴禁直接修改。** 不論是文件審查（`design.md`/`spec.md`/`plans/plan-issue-N.md`）或程式審查，審查者（Claude Code）必須先產出審查報告（存於該 Epic 的 `reviews/`），列出發現的問題，交由人類或原作者決定如何處理；審查者本身不得在審查當下直接修改被審查的文件或程式碼。

### 目錄結構

```
docs/
├── adr/                    # 全域：架構決定紀錄
├── epics/                  # 進行中的 Epic 沙盒（design.md、spec.md、issues.md、plans/、reviews/）
├── archive/                # 已完成的 Epic，搬移至 <YYYY-MM-DD>-<簡稱>/
├── prd.md                  # 全域：產品需求
├── CONTEXT.md              # 全域：通用語言詞彙表（domain-modeling skill 維護）
└── epics.md                # 全域：Epic 狀態看板 —— 見下方說明
```

新建立一個 Epic 時，須將該 Epic 的 `docs/epics/<epic-name>/reviews/` 加入根目錄 `.gitignore`（例如 `docs/epics/epic-2-vertical-core/reviews/`）——審查報告不進版控，僅作為審查當下交付給人類/原作者的暫時性產物。歸檔該 Epic 時，連同該行一併從 `.gitignore` 移除。

### `docs/epics.md` —— 全域狀態看板

每個 Epic 佔一列：代號/名稱、狀態、目前存放路徑、關聯的 PRD 章節、備註。

- ⚪ **未開始 (Backlog)**——已規劃但尚未啟動，尚無目錄
- 🟡 **開發中 (Active)**——設計/規格/程式撰寫進行中，存放於 `docs/epics/<epic-name>/`
- 🟢 **已歸檔 (Archived)**——已合併且穩定，已搬移至 `docs/archive/<YYYY-MM-DD>-<簡稱>/`

在啟動一個 Epic 的 Discovery 階段*之前*，須先在此登錄該 Epic（狀態設為 `Active`，填入路徑）。歸檔時將狀態/路徑更新為 `Archived`。這份檔案是唯一能查到「我要找的 Epic 在哪裡、目前狀態如何」的地方——目前的 Epic 清單與優先順序請見 `docs/epics.md` 本身。

### 生命週期

1. **任務分類**（人類）：新功能/重構 → 建立新 Epic；Bug 修復 → 找到受影響的 Epic，於其 `reviews/` 目錄下處理。
2. **Discovery**（Claude Code，扮演 PM/Analyst）—— `/brainstorming` + `/grill-with-docs` → `docs/epics/<epic-name>/design.md`。Bug 修復則改用 `/diagnose` → `docs/epics/<epic-name>/reviews/bugfix-repro.md`。
3. **Architecting**（Claude Code，扮演 Architect）—— 若架構有異動則撰寫 ADR，並在 `docs/epics/<epic-name>/spec.md` 中定義核心介面/型別（自此成為該 Epic 的唯一事實來源）。
4. **Scrum Master 階段**（Claude Code）—— 將 Epic 拆解為細粒度的垂直切片工單，寫入 `docs/epics/<epic-name>/issues.md`，每個工單皆須附上所需的單元測試要求。
5. **規劃與審查**（實作者為作者、Claude Code 為審查者）—— 實作者認領工單，撰寫 `docs/epics/<epic-name>/plans/plan-issue-<N>.md`，在開始寫程式碼前發起審查（`requesting-code-review`/`receiving-code-review`）；審查者先產出報告，不得直接修改該計劃。
6. **TDD 實作與 QA**（實作者為作者、Claude Code 為審查者）—— 紅-綠-重構循環；每完成一個 Task 的 Step，須將 `plans/plan-issue-<N>.md` 中該 Step 前面的 `- [ ]` 改為 `- [x]`，讓計劃檔案隨開發進度即時反映完成狀態，方便後續確認/複查追蹤；接著進行程式碼審查；審查者先產出報告，不得直接修改程式碼；結果歸檔至 `docs/epics/<epic-name>/reviews/review-issue-<N>.md`；交由人類進行合併。
7. **歸檔**（人類指定）—— 將整個 Epic 目錄搬移至 `docs/archive/<YYYY-MM-DD>-<簡稱>/`，並將其在 `docs/epics.md` 的該列狀態更新為 `Archived`、填入新路徑。

## Agent skills

### Issue tracker

本機 Markdown 檔案管理，存放於各 Epic 目錄下（`docs/epics/<epic-name>/`）。詳見 [issue-tracker.md](./docs/agents/issue-tracker.md)。

### Triage labels

採用標準的五個分流標籤（`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`）。詳見 [triage-labels.md](./docs/agents/triage-labels.md)。

### Domain docs

使用單一情境（single-context）配置，以根目錄的 [CONTEXT.md](./CONTEXT.md) 及 `docs/adr/` 作為架構與領域知識的唯一事實來源。詳見 [domain.md](./docs/agents/domain.md)。
