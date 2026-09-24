# CLAUDE.md

本檔案為 Claude Code（claude.ai/code）在此儲存庫中工作時的指引文件。

## 儲存庫現況

大多數核心閱讀體驗功能已完成並歸檔（`docs/archive/`）。**Epic／Issue 進度與優先順序一律以 `docs/epics.md` 為準，本檔案不記錄逐一 Epic 或 Issue 的完成狀態、日期或 PR 編號**——本檔案只描述架構的目前最終樣貌，新 Issue 合併不需要回頭修改本檔案，除非它改變了下方描述的架構事實本身。

`prototype/elinkbook_theme_prototype.html` 是目前唯一權威的 HTML/CSS/JS UI/UX 原型（手機外殼模擬器＋開發工具側欄，依 `DESIGN.md` 三主題＋E-Ink 修飾子色彩 Token 系統製作），後續功能性 Epic 設計畫面時應先參考它，細節見下方「UI/UX 原型參考」。舊版 `prototype/index.html`（E-Ink 被當成第 4 個獨立主題，與 `DESIGN.md` 定案的「E-Ink 是修飾子」原則衝突）已停用，不應再作為畫面設計依據。

## 常用指令

所有指令皆在 `app/` 目錄下執行。

```bash
flutter pub get
flutter test
flutter test test/screens/reader_screen_test.dart

# 提交前必須乾淨（"No issues found!"）
flutter analyze

# 新增/修改畫面字串後，提交前跑一次：偵測 Widget 字串參數位置上未經 AppLocalizations
# 包裝的硬編碼中文字串（純 Node，免安裝；見 app/tool/README.md）
node tool/check_l10n_hardcoded_strings.js

flutter devices

# 必須指定真實裝置/模擬器（見下方「兩層測試架構」，一般 flutter test 做不到這件事）
flutter test integration_test/reader_screen_test.dart -d <device-id>

flutter build apk --debug

# 需要測試 Google Drive／OneDrive 真實 OAuth 登入流程時才需要帶入這個設定檔
# （app/config/cloud_oauth.json，樣板見 cloud_oauth.example.json，不進版控，
# 見 docs/archive/2026-08-24-epic-29-cloud-import/issues.md Issue 7）；一般開發／
# flutter analyze／flutter test 不涉及真實登入流程，維持上方指令即可，
# 不帶這個旗標時會自動退回樣板 placeholder 值，不影響任何既有功能。
flutter run --dart-define-from-file=config/cloud_oauth.json
flutter build apk --release --dart-define-from-file=config/cloud_oauth.json
```

## 高層架構

### `ReaderScreen`：唯一的閱讀器 seam

`app/lib/screens/reader_screen.dart` 是格式無關的統一入口，依 `detectBookFormat()`（`app/lib/reader/book_format.dart`，依副檔名判斷 `epub`/`pdf`/`azw3`/`cbz`/`txt`/`md`/`unknown`）與 `Book.isFixedLayout`（是否為固定版面 FXL；語意已由「EPUB 專屬」廣義化為跨格式通用旗標，見 ADR 0023）分派到兩條完全獨立的渲染路徑之一：

- `PdfReaderView`（`app/lib/reader/pdf_reader_view.dart`）——純 Dart widget，底層為 `pdfrx`（PDFium 透過 `dart:ffi` 直接呼叫，非 `PlatformView`，見 ADR 0022）。目前功能：單頁／三態雙頁並列顯示（底層由 `pdfrx` 的 `layoutPages`/`calculateCurrentPageNumber` 客製化排版 API 實作）、頁碼與跳頁、`content://` URI 存取、E-Ink 影像濾鏡（對比度/亮度用 `ColorFiltered` 即時渲染、加粗/裁切透過 `page.render()`＋背景 Isolate＋`pageOverlaysBuilder` 疊加覆蓋圖）、智慧/手動裁切、劃線/備註/書籤（長按拖曳框選矩形＋`AnnotationToolbar`，`pageOverlaysBuilder` 逐頁疊加手勢層使雙頁模式下座標歸屬單一頁面有構造性保證）、目錄（TOC，格式無關的 `BookTocItem` 抽象介面，見下方）、內文搜尋（`page.loadStructuredText()`/`PdfPageText.allMatches()`）、頁碼縮圖（`PdfThumbnailCache<T>` 純 Dart LRU 快取＋`page.render()`）、6 顆浮動 FAB 工具列＋3×3 導覽熱區（共用 `TapZoneDetector`，見下方「不可逆的技術決策」）。
  - **已知限制**：Page Label（PDF 邏輯頁碼標籤，例如封面羅馬數字）尚未支援——`pdfrx` 未暴露對應 API，目前僅純數字頁碼。手寫/自由繪圖標註明確排除於範圍外。
  - **不可逆的技術決策，改動前務必知悉**：`Isolate.run()` 的 closure 須宣告為獨立於 State 之外、參數列僅含可跨 isolate 傳遞型別的頂層函式——否則 Dart VM 會把 closure 所在詞法作用域一併打包，牽連 `PdfPage`/`PdfDocument` 內部不可傳遞的 rxdart `BehaviorSubject` 導致執行期例外。EPUB／PDF 熱區點擊偵測已收斂為共用 `TapZoneDetector`（`app/lib/reader/tap_zone_detector.dart`，`epic-26-architecture-hardening` Issue 2）：`nowMs`（計時來源）／`tapMaxDurationMs`（快速點擊時長門檻）為建構參數注入；`tapSlop`（位移容許值）／`tapDebounceMs`（防彈跳門檻）已收斂為模組層級共用常數 `kTapZoneSlop`／`kTapZoneDebounceMs`（`epic-31-touch-intent-unification` Issue 3），並作為建構子預設值，呼叫端不再各自宣告字面值。`tapMaxDurationMs` 則刻意維持兩端各自明確傳字面值、不設共用預設值：PDF 呼叫端傳入 `clock.now()`／700ms、EPUB 呼叫端傳入 `DateTime.now()`／700ms——EPUB 的 700ms 是 `epic-25` Issue 1 真機校準值，PDF 的 700ms 是 `epic-31-touch-intent-unification` Issue 3 刻意對齊、未經真機驗證的決定，兩者數值目前剛好相同但校準狀態不同，若之後真機回報 PDF 端門檻不合適，需另立工單依真機資料重新校準（比照 `epic-25` Issue 1／`epic-26` Issue 3 先例，不可逕自沿用 EPUB 數值）——PDF 端用 `package:clock` 的 `clock.now()` 而非裸 `DateTime.now()`，讓 `flutter_test` 的 FakeAsync 能攔截其 Zone 覆寫、隨 `tester.pump()` 正確推進，同時正式裝置上仍取得真實系統時間。`content://` URI 存取走原生端 `ReaderResourceChannel.kt` 串流複製到本機暫存檔後再開啟——`pdfrx.openCustom()` 隨機存取分段讀取已證實有 FFI 非同步限制，此為已文件記錄的回退路徑，不要嘗試改回 `openCustom()`。內文搜尋刻意避開 `PdfTextSearcher`/`PdfViewerController.useDocument`（`testWidgets`/fake-async 環境下有死鎖風險）。縮圖 `renderThumbnail()` 不需額外 Isolate（`pdfrx` 底層已透過 `BackgroundWorker` 背景 worker 執行）。
- `FoliateReaderView`（`app/lib/reader/foliate_reader_view.dart`）——**所有 Foliate 格式使用**（EPUB 流式與 FXL、KF8/AZW3、CBZ，以及 TXT／MD——後兩者匯入時已落地合成為最小合法 EPUB3／XHTML 相容結構，`Book.filePath` 指向合成檔案、原始檔僅匯入當下讀取一次，之後與一般 EPUB 走完全相同的渲染/分頁/CFI/劃線路徑，見 ADR 0023），`readest/foliate-js`（釘定 commit、直接複製進版控、不經 npm 建置，見 `app/android/app/src/main/assets/foliate/`）跑在 `flutter_inappwebview` 的 `InAppWebView` 內，**不是**傳統 `AndroidView`/`PlatformView`（`MainActivity.kt` 沒有為它註冊 `PlatformView` 類型字串），透過 `foliate_native_bridge.dart` 與原生端（`elinkbook/volume_key` 頻道的 `attachReaderView`/`detachReaderView`）溝通生命週期，JS↔Dart 契約定義在 `main.js`（見 ADR 0011、ADR 0013、ADR 0017）。這份釘定的 vendor 程式碼會無條件使用較新的 ES 內建方法，較舊的 Android System WebView 不支援時需要在 `_esCompatPolyfillJs` 補 polyfill（透過 `initialUserScripts` 於 `AT_DOCUMENT_START` 注入，不修改釘定版本本身）；**每次升級這份釘定版本後**都要跑 `node app/tool/check_foliate_es_compat.js` 靜態掃描有沒有新的較新 API 用法還沒設防（見 `app/tool/README.md`）。

`PdfReaderView` 對外建構參數為 `filePath`/`onPageRendered`/`onError`/`initialPageIndex`/`onPageChanged`/`dualPageMode`/`dualPageCoverAlone`/`dualPageDirection`/`isLandscape` 等；`dualPageMode` widget 層預設 `DualPageMode.never`，產品預設 `auto` 由 `reader_screen.dart` 明確傳入。靜態 helper（`jumpToPage`/`previousPage`/`nextPage`/`refreshAnnotations`）維持穩定方法簽章供 `ReaderScreen` 呼叫。`content://` URI 存取走原生端 `ReaderResourceChannel.kt`（`elinkbook/reader_resources_cache` channel 的 `readContentUriAll` 方法——`epic-44-wifi-book-transfer` Issue 0 起改走背景任務佇列，避免大檔案複製時阻塞主執行緒觸發 ANR，原生端同一個 `onMethodCall()` 本來就同時服務主執行緒／背景佇列兩條 channel）串流複製到本機暫存檔後回傳路徑字串，再以 `PdfDocument.openFile()` 開啟，非整包讀進記憶體（見 `ReaderResourceChannel.kt` class doc）。`FoliateReaderView` 刻意不比照這個模式（見上方）。所有 Foliate 格式（EPUB/KF8/CBZ/TXT/MD）一律建構 `FoliateReaderView`，不再依 FXL/流式分派到不同 widget（見 ADR 0017、ADR 0023）。

`ReaderScreen` 對外的公開建構參數為 `filePath`／`bookId`／`prefsRepository`／`bookTitle`（頁首找不到章節資訊時的回退顯示文字；`prefsRepository` 由 `main.dart` 建構後，與 `LibraryRepository`/`BookImportService` 平行、逐層透過建構子參數傳遞下來，見 `docs/adr/0007-reader-screen-book-id-contract.md`）——載入中／錯誤狀態是內部實作細節，透過固定的 `Key('reader_loading_indicator')`／`Key('reader_error_text')` 暴露給測試觀察，刻意不新增公開 callback 參數。

`MainActivity` 是 `FlutterFragmentActivity`（而非 Flutter 預設的 `FlutterActivity`）——**不要嘗試改回 `FlutterActivity`**：資料夾匯入功能的 `openDocumentTreeLauncher = registerForActivityResult(...)` 依賴 `FragmentActivity` 家族才能使用，`FlutterActivity` 不支援。

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
- PDF：目標為 100MB 以上檔案開啟速度小於 2 秒；支援影像濾鏡（對比度/亮度/加粗）、智慧/手動裁切，預設採用 page-fit。渲染架構見下方「技術棧（已決策）」與上方「`ReaderScreen`」小節。
- TXT：自動偵測編碼（UTF-8/UTF-16/Big5/GBK）與章節標題（正則抽取＋分塊防護），匯入時落地合成為最小合法 EPUB3 結構（真實章節/目錄，非估算頁碼），之後與一般 EPUB 走完全相同的 `FoliateReaderView` 渲染/分頁/CFI 路徑（見 ADR 0023）。
- KF8(AZW3)、CBZ、Markdown (MD) 為 P1 擴充格式，同樣經 `readest/foliate-js` 單引擎渲染（CBZ 恆為固定版面；MD 比照 TXT 於匯入時落地合成 EPUB3 結構），細節見 ADR 0023。
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
- 書籤儲存一個定位點（EPUB／KF8／CBZ／TXT／MD 等所有 Foliate 格式皆為 CFI，見上方「合成書籍結構」；PDF：頁碼）+ 章節名稱；支援重新命名、單筆刪除、「刪除該書所有書籤」。書籤管理屬於 MVP 範圍，並非後續階段項目。
- 劃線與備註是各自獨立的物件類型（備註不會覆蓋劃線）；兩者在直排/橫排切換時都須保持視覺一致。支援單筆編輯/刪除，以及劃線與備註各自的一鍵全刪（批次刪除前需經確認對話框）。
- 劃線支援多種顏色，加上獨立的「螢光筆」子類型。劃線/備註的定位精度須高於書籤：Foliate 格式（EPUB／KF8／CBZ／TXT／MD）用 CFI，PDF 用頁碼+頁內座標（不只是頁碼）。
- 統一側邊欄列出所有劃線與備註（不含書籤，書籤有自己獨立的清單/畫面），點擊可跳轉至該位置。
- Markdown 導出涵蓋劃線、個人備註與書籤清單。

### 搜尋
- 全書庫全文檢索（書名、作者、書內內容），即使在約 1,000 本書規模下也要於 500ms 內出結果。建議做法：SQLite FTS5（或同等方案）索引。搜尋結果須支援跳轉至章節，並須將書名/作者匹配與書內內容匹配分開呈現。

### 同步
- 同步後端：**PocketBase**。
- 閱讀位置（Foliate 格式：CFI；PDF：頁碼）在 App 關閉/切換書籍時自動同步，並正確處理直排/橫排模式間的轉換；目標延遲 <2 秒，衝突解決成功率 99.9%。若開啟書籍時雲端同步的位置與本機位置不一致，須先詢問使用者確認才跳轉——絕不可靜默覆蓋。
- 閱讀時長統計每日儲存於本機，彙整成約 365 天規模的熱點圖/貢獻圖（參考模式：Readest）；點擊方格顯示當日詳情。計時須基於偵測到的實際閱讀活動（翻頁/捲動/長按），排除閒置或背景狀態的時間。

### 圖書庫管理
- 書架視圖：每列 3 本封面；另有含元數據+進度百分比的列表視圖。App 須記住使用者上次選擇的檢視模式。
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

`prototype/elinkbook_theme_prototype.html` 是依 `docs/research/uiux/eink-redesign-rebuild-plan.md` 定案結果製作的獨立 HTML 原型（手機外殼模擬器 + 開發工具側欄，涵蓋書架視圖〔含「繼續閱讀」列／長按動作 Sheet〕、來源畫面〔含麵包屑導覽〕、閱讀器〔直排/橫排切換〕、設定四分區、版面設定四分頁，並實作 Light/Dark/Sepia 三主題＋E-Ink 修飾子完整主題系統）。`epic-0-skeleton` 之後的所有功能性 Epic（`epic-1` 起）在設計畫面 UI/UX 時，須先參考此原型既有的視覺與互動設計，作為 Flutter 實作的依據起點，而非重新發明。

舊版 `prototype/index.html`（曾為官方原型，畫面覆蓋含九宮格導航熱區設定等細節）已停用——其主題系統把 E-Ink 當作第 4 個獨立主題，與 `DESIGN.md` 定案的「E-Ink 是修飾子，不是第四個主題」原則衝突，不應再作為畫面設計依據；若某個細節畫面（例如九宮格熱區配置）在 `elinkbook_theme_prototype.html` 中只有選單入口、尚無完整互動示範，須另行與人類確認，不可逕自沿用 `index.html` 的舊版互動邏輯。`prototype/eink_redesign_prototype.html` 為更早期的純黑白 E-Ink 版本，依 `eink-redesign-rebuild-plan.md` 保留作對照，同樣不作為主要設計依據。

### 技術棧（已決策）

- **App 外殼**：Flutter，跨平台共用。
- **手機優先，Android 先於 iOS。** 初期幾波不含桌面版目標（見 `docs/epics.md` 的 epic-13）。
- **Android 最低支援版本：Android 11 (API 30)**（見 `docs/prd.md` NFR-6）——不得將 Android 專案的 `minSdk`/相容性設定限制在比 API 30 更新的門檻。實際 `minSdk` 目前是 `24`（比政策門檻寬鬆；由 Readium `kotlin-toolkit`〔要求 23〕與 `integration_test` 外掛〔要求 24〕兩者疊加後的真實下限決定，見 `app/android/app/build.gradle.kts`），不是刻意收緊。
- **EPUB/KF8/CBZ/TXT/MD（單引擎，`readest/foliate-js`，見 ADR 0011、ADR 0017、ADR 0023）**：所有 Foliate 格式（EPUB、KF8/AZW3、CBZ、TXT、MD）皆用 `readest/foliate-js`（釘定 commit、直接複製進版控，不引入 Node.js/npm 建置工具鏈），跑在 `flutter_inappwebview` 的 `InAppWebView` 內（見 ADR 0013——標準 Flutter `AndroidView`+`android.webkit.WebView` 的觸控轉發機制無法完整還原「長按選字→拖曳選取控點」手勢）。`_dispatchedIsFixedLayout` 只決定 UI 版面語意（單頁/雙頁），不決定要建構哪個 widget——所有 Foliate 格式一律建構 `FoliateReaderView`。TXT／MD 匯入時落地合成為 EPUB3／XHTML 相容結構（`Book.filePath` 改指向合成檔案，原始檔案僅匯入當下讀取一次），合成後即以一般 EPUB 身分處理（含 CFI 定位、劃線、書籤）；CBZ 恆為固定版面（`isFixedLayout=true`），復用既有 FXL 分派路徑與 `FxlSettingsSheet`。`readium-shared`／`readium-streamer` 保留供 `BookMetadataChannel.kt` 使用，其餘 Readium 依賴已移除；決策沿革見 ADR 0011／0017／0023，不在此重複。
- **PDF**：改用 `pdfrx`（PDFium 透過 `dart:ffi` 直接呼叫，非 `PlatformView`），決策見 [ADR 0022](docs/adr/0022-pdf-engine-migrate-to-pdfrx.md)，功能細節見上方「`ReaderScreen`」小節的 `PdfReaderView` 說明。舊原生 `android.graphics.pdf.PdfRenderer`／`PlatformView` 渲染叢集已完全清退。手寫/自由繪圖標註明確排除、另立後續 Epic。
- **TXT／MD 的排版引擎路線已推翻**：`epic-11-txt-engine` 原案（獨立自訂輕量直排 CJK 排版引擎，不採用 Readium/WebView 方案）已由 [ADR 0023](docs/adr/0023-multi-format-foliate-pipeline-txt-route-reversal.md) 正式作廢，改併入上方「EPUB/KF8/CBZ/TXT/MD」的 `readest/foliate-js` 單引擎管線，不再維護獨立排版/定位系統。

## Spec-Driven Development (SDD) 工作流程

本儲存庫採用結合 BMad Method 角色分工、Matt Pocock 規格先行嚴謹度、以及 Superpowers 審查機制的規格驅動開發工作流程。可執行實作工作的有兩個角色：**Claude Code** 與 **Antigravity CLI**。切換到 Antigravity CLI 一律由人工手動指定——絕不可自行假設或觸發。若需要派出「實作者」子代理但人類尚未明確指定使用 Antigravity CLI，一律使用 Claude Code 的 subagent（也就是目前正在使用的同一個 LLM/工具），不可模擬呼叫 Antigravity。

**審查一律先產出報告，嚴禁直接修改。** 不論是文件審查（`design.md`/`spec.md`/`plans/plan-issue-N.md`）或程式審查，審查者（Claude Code）必須先產出審查報告（存於該 Epic 的 `reviews/`），列出發現的問題，交由人類或原作者決定如何處理；審查者本身不得在審查當下直接修改被審查的文件或程式碼。

**測試執行範圍（避免重複跑全套 `flutter test`）：** 全專案測試案例已逾 1,800 個（144 個測試檔），完整跑一次約需 5 分鐘。單一 Task 的 TDD 步驟、單輪程式審查、審查後的修復驗證，一律只跑「這次異動實際觸及」的測試檔（例如 `flutter test test/reader/tts_controller_test.dart`），不需要每次都重跑全套；完整 `flutter test`（無參數）只在以下兩個時機執行一次：(1) 整張 `plan-issue-N.md` 計畫的最後一個 Task 完成時（既有慣例，計畫檔案本身已這樣安排）、(2) 該 Issue 準備發 PR／合併進 `main` 前的最終確認。程式審查報告若要聲稱「零回歸」，只需列出「已跑過異動檔案的測試」＋「上一次全套通過的時間點／commit」，不必為了同一個結論在同一個 Issue 內反覆重跑全套。

目錄結構、`docs/epics.md` 圖例與 Discovery→歸檔的完整七步驟生命週期見 `sdd-workflow` skill（做 Epic/Issue 規劃工作時載入）。

## Agent skills

### Issue tracker

本機 Markdown 檔案管理，存放於各 Epic 目錄下（`docs/epics/<epic-name>/`）。詳見 [issue-tracker.md](./docs/agents/issue-tracker.md)。

### Triage labels

採用標準的五個分流標籤（`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`）。詳見 [triage-labels.md](./docs/agents/triage-labels.md)。

### Domain docs

使用單一情境（single-context）配置，以根目錄的 [CONTEXT.md](./CONTEXT.md) 及 `docs/adr/` 作為架構與領域知識的唯一事實來源。詳見 [domain.md](./docs/agents/domain.md)。
