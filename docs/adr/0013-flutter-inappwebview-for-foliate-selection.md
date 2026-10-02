# ADR 0013：流式 EPUB 原生嵌入由 `AndroidView`+`android.webkit.WebView` 改用 `flutter_inappwebview`

## 狀態

已採納。**本 ADR 的「`readest/foliate-js` 釘定版本本身不修改」限制，已由 [ADR 0024](0024-flowable-pagination-density-calibration-reopen-adr-0011.md)（`paginator.js`／`view.js`／`progress.js`）與 [ADR 0025](0025-fixed-layout-relative-module-specifier-reopen-adr-0011.md)（`fixed-layout.js`）列出例外；其餘 vendored 檔案仍與上游逐位元組相同。**

## 背景

`epic-18-reader-device-qa` Issue 8 回報：流式 EPUB（`FoliateEpubReaderView`，ADR 0011 建立的獨立 `foliate-js` 渲染路徑）在真機上長按選字後，原生選取控點（selection handles）會出現，但拖曳控點調整範圍完全沒有反應，導致無法建立劃線/備註。

三條獨立調查路線收斂到同一個根因：

1. **`docs/epics/epic-18-reader-device-qa/reviews/issue-8-selection-detection-report.md`**：8 種方案（iframe/top-level DOM 事件監聽、Kotlin 輪詢 `getSelection()`、`setOnLongClickListener`、`setOnTouchListener`、CSS 停用原生選取改自訂 JS 觸控選取）逐一實測，全數失敗。關鍵觀察：Kotlin 端 `setOnTouchListener`／`setOnLongClickListener` 從未觸發，`DecorView.dispatchTouchEvent` 有觸發但沒傳到 `WebView`。
2. **本次 `/diagnose` session 的真機獨立驗證**：把 `foliate_epub_reader_view.dart` 疊在 `AndroidView` 上的整層 9 宮格 `GestureDetector`（含 `onTap`）完全拿掉，只留裸 `AndroidView`，用 `adb shell input` 送真實硬體層級觸控（非 Flutter 合成事件）重測，結果不變：`webView.setOnTouchListener` 依然零觸發。這排除了「Dart 端自己的手勢層搶走競技場」這個原本最直覺的假設——問題出在 Flutter `AndroidView`／`PlatformViewWrapper` 這層本身的觸控轉發機制，不是本專案 Dart/Kotlin 程式碼寫錯或可以靠調整 `GestureDetector` 解決的範圍。
3. **`docs/epics/epic-18-reader-device-qa/reviews/issue_8_new_solution_proposal.md`**：獨立提出相同根因判斷（「Flutter 的 `AndroidView` 透過 `PlatformViewWrapper` 傳遞觸控事件時，在 Native 層消費了 MotionEvent」），並指出 `anx-reader`（同樣是 Flutter + `foliate-js` 的產品）改用 `flutter_inappwebview` 後，靠監聽 `contextmenu`/`pointercancel` 事件成功取得原生選取的 DOM Range——`flutter_inappwebview` 有自己一套獨立於 Flutter 官方 `AndroidView` 的原生嵌入與觸控轉發機制，這正是它能力所在的差異點。

三條路線指向同一結論：這不是本專案程式碼缺陷，是 Flutter 官方 `AndroidView` 包裝 `android.webkit.WebView` 時，觸控事件轉發機制本身就無法完整還原「長按選字→拖曳控點」這個手勢序列給底層原生 View；靠繼續在現有包裝方式上加 Kotlin/JS 補丁（Kotlin `setOnTouchListener`、`startActionMode` 覆寫、CSS 停用原生選取改自訂 JS 選取系統等）都已被實測排除或存在同樣的底層限制。

## 決策

- **流式 EPUB（`FoliateEpubReaderView`）原生嵌入元件由 `AndroidView`+自建 `android.webkit.WebView`（`FoliateEpubReaderView.kt`），改為 `flutter_inappwebview` 套件的 `InAppWebView`**。這是本 ADR 唯一的範圍。
- **固定版面（FXL）EPUB 完全不受影響**，繼續使用 `EpubReaderView.kt`（Readium）。比照 ADR 0011 建立的「流式與 FXL 是兩條完全獨立原生路徑」既有慣例——本次只換流式這一條路徑的底層嵌入方式，不影響另一條。
- **`readest/foliate-js` 釘定版本本身不修改**（`view.js`／`paginator.js`／`overlayer.js` 等 vendored 檔案），比照 ADR 0011。本次變動只發生在「誰負責把這些靜態 JS 檔案跑起來、誰負責 JS↔原生橋接」這一層，不動 `foliate-js` 本體邏輯。
- **`main.js` 新增 Android 專用的選取偵測分支**：比照 `anx-reader` 已驗證的手法，監聽 `contextmenu`／`pointercancel` 事件取得原生選取建立/變動的訊號，配合 `document.getSelection()` 取得 Range 後比照既有流程計算 CFI／座標。非 Android 平台（iOS，未來若啟用）維持既有的 iframe `selectionchange` 監聽，因為此問題目前只在 Android WebView 上被證實存在。
- **Dart 端公開介面契約不變**：`FoliateEpubReaderView` 的建構參數與 callback（`onPageRendered`／`onSelectionChanged`／`onSelectionCleared`／`onLocatorChanged`／`onAnnotationActivated` 等）維持原樣，`ReaderScreen` 與其餘呼叫端不需要因為底層嵌入元件替換而改動任何一行——這是刻意保護的既有 seam（`spec.md`「介面」節），底層 JS↔原生橋接機制從自建 `MethodChannel`+`addJavascriptInterface` 換成 `flutter_inappwebview` 的 `addJavaScriptHandler`/`evaluateJavascript`，是實作細節、不外露。
- **9 宮格導航熱區維持既有的 Dart 端 `Stack` 疊加 `GestureDetector` 模式**（ADR 0011 已確立），但需要接上 Epic 18 Issue 8 原本規劃的「有作用中選取範圍時才放行拖曳」邏輯（`_hasActiveSelection` 狀態，見 `plans/plan-issue-8.md` Task 3B）——即使換了底層嵌入元件，Dart 端疊加層與底層 WebView 的手勢仲裁需求本質不變，只是這次底層轉發機制正確，這段邏輯才有意義生效。
- **CFI 定位系統不受影響**：本次只換 JS↔原生橋接與觸控轉發層，不涉及 `foliate-js` 的 CFI 計算邏輯，既有書籤/劃線/備註資料的定位格式與有效性不受影響（與 ADR 0011 遷移 Readium→foliate-js 時「既有資料視為失效」的情況不同，本次不是換渲染引擎本體）。
- **不做執行期 fallback 開關**：比照 ADR 0011 既有理由（專案無 remote config／staged rollout 基礎設施），退路是改版還原，不投入額外複雜度。

## 後果

- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt`／`FoliateEpubReaderViewFactory.kt` 兩個檔案的既有邏輯（`WebViewAssetLoader` 雙路徑掛載、`MethodChannel` 手動橋接、`addJavascriptInterface`）大部分被 `flutter_inappwebview` 的對應 API 取代，可大幅簡化或移除；`MainActivity.configureFlutterEngine()` 內流式 EPUB 對應的 `PlatformView` 類型註冊需同步調整。
- `app/pubspec.yaml` 新增 `flutter_inappwebview` 依賴，引入本專案目前沒有的第三方套件維護風險（版本相容性、未來升級）；FXL／PDF 路徑不使用此套件，風險侷限於流式 EPUB 這一條路徑。
- `main.js` 需要依平台分流選取偵測邏輯（Android 用 `contextmenu`/`pointercancel`，其餘平台維持既有 `selectionchange`），增加程式碼分支，需要在 Android 真機上完整回歸驗證長按選字／拖曳控點／劃線顏色與底線建立／9 宮格翻頁熱區皆正常，且無 regression（比照 Epic 18 既有真機 mutation test 方法論）。
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 8 與 `plans/plan-issue-8.md` 需要依本 ADR 重新改寫——原計畫（Dart 端修 `GestureDetector` 拖曳攔截）已被證實無法解決根本問題，需改為涵蓋本 ADR 範圍的新計畫。

## 曾考慮的替代方案

- **繼續用 `AndroidView`+`android.webkit.WebView`，覆寫 `WebView.startActionMode()` 取得選取建立/清除訊號**：本次 `/diagnose` session 已實際嘗試，且即使訊號本身能取得，`ActionMode.Callback` 本身不提供讀取底層選取 `Range`/文字內容的 API——仍然需要 `document.getSelection()` 正常運作才能算出 CFI，而這正是被證實壞掉的那一環，此路徑無法完整解決問題，予以排除。
- **繼續用 `AndroidView`+`android.webkit.WebView`，改用 CSS `user-select: none` 停用原生選取、自建 JS 觸控選取系統**（`issue-8-selection-detection-report.md` 方案 F）：已實測失敗——JS 觸控事件（`touchstart`/`pointerdown`）同樣被 Flutter 的觸控轉發機制擋住，跟原生選取的問題是同一個底層原因，予以排除。
- **評估 Crosswalk／GeckoView 等替代 WebView 引擎**：相容性風險高、無實際產品驗證先例，工作量與風險皆高於採用已在 `anx-reader` 產品環境驗證過的 `flutter_inappwebview`，予以排除。
- **放棄流式 EPUB 劃線功能，僅支援 FXL 劃線**：核心功能缺失，不符合 `docs/prd.md` 對劃線/備註的既有需求範圍，予以排除。
