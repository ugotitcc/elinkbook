# Epic 16 — 橫向雙頁顯示：規格 (Spec)

這是實作 `epic-16-dual-page` 的唯一事實來源。決策的完整討論過程與理由請見 `design.md`。

> **頁碼索引慣例**：全文一律 0-indexed（`currentPageIndex` 從 0 起算，對應 `PdfReaderView.kt` 現行慣例）。
>
> **版本紀錄**：本文件於 2026-07-11 依 `/superpowers:requesting-code-review` 審查報告（`tmp/epic-16/reviews/review-design-spec.md`，4 項 Critical、8 項 Important、3 項 Minor）修訂，修正項目在對應章節以「（審查修正）」標註首次出現處。

## 模組 (Modules)

- **`BookReaderPrefs`**（Dart，異動既有 `app/lib/reader/book_reader_prefs.dart`）—— 新增 3 個雙頁專屬 nullable 欄位（見下方「資料模型」），沿用既有「全欄位 nullable、跨格式共用單一表」模式。
- **`DualPageMode`／`DualPageDirection`**（Dart，新增，`app/lib/reader/dual_page_mode.dart`／`dual_page_direction.dart`）—— 列舉型別。
- **`ReaderScreen`**（Dart，異動既有 `app/lib/screens/reader_screen.dart`）—— 
  - **方向偵測**（審查修正 C-2）：在 `build()` 中透過 `MediaQuery.of(context).orientation`（或 `OrientationBuilder`）偵測當前是否為橫向（`Orientation.landscape`），結果存為 `bool isLandscape`，透過 `PdfReaderView`／`EpubReaderView` 新增的 `isLandscape` 建構參數下傳（見「方向偵測契約」一節的完整 Method Channel 定義），用以決定 `auto` 模式下是否啟用雙頁。
  - **設定入口**：打破「固定版面不顯示設定齒輪」的現有慣例。當格式為 EPUB 且 `isFixedLayout == true` 時，由於整個 Scaffold AppBar 被隱藏（`reader_screen.dart` 現行 `appBar: _isFixedLayout ? null : AppBar(...)`），改在畫面右上角（與左上角半透明懸浮返回按鈕 `Key('reader_fixed_layout_back_button')` 對稱）新增一個圓形半透明懸浮設定按鈕（新增 `Key('reader_fixed_layout_settings_button')`），點擊時開啟 `FxlSettingsSheet`。
  - **Null 預設值解析**（審查修正 I-3；因 `docs/superpowers/plans/2026-07-12-refactor-reader-prefs-manager.md`〔已完成並合併回 `main`，發生於本文件撰寫之後〕把 null 合併解析邏輯整個從 `ReaderScreen` 搬到 `ReaderPrefsManager` 深模組，原文件所述的 `_resolvedPdfFitMode` 之類 getter 現已不存在，本段落同步更新）：新增 `dualPageMode: DualPageMode`、`dualPageCoverAlone: bool`、`dualPageDirection: DualPageDirection`（皆 non-nullable）三個欄位到 `ResolvedPreferences`（`app/lib/reader/resolved_preferences.dart`），並在 `ReaderPrefsManagerImpl.resolve()`（`app/lib/reader/reader_prefs_manager_impl.dart`）比照既有 `pdfFitMode: book.pdfFitMode ?? PdfFitMode.pageFit` 慣例新增 `dualPageMode: book.dualPageMode ?? DualPageMode.auto`、`dualPageCoverAlone: book.dualPageCoverAlone ?? true`、`dualPageDirection: book.dualPageDirection ?? DualPageDirection.rtl`（Issue 4 決策：elinkBook 全域固定預設為右到左，見 `docs/epics/epic-16-dual-page/issues.md` Issue 4）三行；`ReaderScreen` 透過既有 `resolved.dualPageMode` 等欄位讀取已解析值後下傳給原生端，不新增任何 `_resolvedXxx` getter；原生端一律收到已解析的非 null 值，不需自行處理 null 語意。
- **`FxlSettingsSheet`**（Dart，新增 widget，`app/lib/screens/fxl_settings_sheet.dart`）—— 新增精簡版 Bottom Sheet，專為 EPUB 固定版面設計。提供「雙頁模式」三態切換選項，並為未來 FR-42（全螢幕顯示開關）留出擴充空間（審查修正 M-3：僅預留 UI 擴充位置，本 epic **不**實作 FR-42 功能本身，避免範圍蔓延）。
- **`PdfSettingsSheet`**（Dart，異動既有 `app/lib/screens/pdf_settings_sheet.dart`）—— 在「顯示」分頁中加入雙頁相關選項：雙頁模式（自動／永遠雙頁／永遠單頁）、封面獨立（開關）、頁面方向（左到右／右到左）。
- **`PdfReaderView`**（Dart，異動既有 `app/lib/reader/pdf_reader_view.dart`）—— 建構子新增 `dualPageMode`、`dualPageCoverAlone`、`dualPageDirection`、`isLandscape`（審查修正 C-2，由 `ReaderScreen` 解析後下傳，見上方「Null 預設值解析」，皆為非 null 值）參數；`didUpdateWidget` 偵測任一變動時，統一透過 `setPdfPreferences` Method Channel 送出。
- **`PdfReaderView.kt`**（Android，異動既有，`renderCurrentPage()` 更名為 **`renderCurrentSpread()`**——審查修正 M-2：現行 5 處呼叫點 `setPdfPreferences`／`openBook`／`exitCropEditMode`／`nextPage`／`previousPage` 皆須同步改名，避免遺漏）—— 
  - `openBook` 與 `setPdfPreferences` 接收新參數（含 `isLandscape: Boolean`，見「方向偵測契約」）；`renderCurrentSpread()` 演算法：
    1. 判斷目前是否應啟用雙頁（若 `dualPageMode == "always"`，或 `dualPageMode == "auto"` 且 `isLandscape == true`，且目前**未處於手動裁切編輯模式下**）。若啟用智慧自動裁切（autoDetect）且尚無快取矩形時，優先以單頁當前頁進行邊界偵測與快取（此矩形為**全書共用單一矩形**，非逐頁偵測，見步驟 4 說明與「已知限制」），計算完成後才套用於雙頁拼接。
    2. 若啟用雙頁且 `dualPageCoverAlone == true`：當 `currentPageIndex == 0` 時，渲染單一封面頁（另一側留白）；當 `currentPageIndex > 0` 時，執行奇偶雙頁配對。
    3. 配對規則依 `dualPageDirection` 處理：
       - `ltr`（左到右）：左頁 = `currentPageIndex`，右頁 = `currentPageIndex + 1`
       - `rtl`（右到左）：右頁 = `currentPageIndex`，左頁 = `currentPageIndex + 1`
       - 若 `currentPageIndex + 1` 超出總頁數，另一側以白色背景填充。
    4. 左右頁（審查修正 I-5：套用**同一個全書 `cropRect`**——現行 `cropRect` 欄位本就是全書單一矩形，並非逐頁獨立偵測，本 epic 不新增 per-page 裁切）渲染出各自的點陣圖後，橫向拼接成一張大點陣圖。
    5. **OOM 回退**（審查修正 I-4）：拼接前依兩頁尺寸估算拼接後 Bitmap 記憶體用量；若拼接階段（建立拼接畫布或逐頁繪製時）拋出 `OutOfMemoryError`，回退為只渲染 `currentPageIndex` 單頁（不進行拼接，`dualPageMode` 判定暫時視為不生效），`onPageChanged` 依然回報 `currentPageIndex`。
    6. 拼接後（或步驟 5 回退後的單頁）點陣圖統一套用加粗濾鏡（型態學膨脹），並將 `imageView` 設定 `colorFilter`（對比度、亮度）與 `fitMode`（Matrix 縮放）。
  - **翻頁步進變更**（審查修正 C-4：補齊後退到封面的對稱規則，避免負索引）：當雙頁模式生效時：
    - 前進（`nextPage()`）：若當前顯示第 0 頁封面且 `dualPageCoverAlone == true`，步進為 1（跳到 spread `[1,2]`）；其餘情境步進為 2。
    - 後退（`previousPage()`）：若當前 spread 左頁 index 為 1 且 `dualPageCoverAlone == true`（即目前在 `[1,2]`），步進為 1（回到封面 `[0]`）；其餘情境步進為 2。一律以「目的地 spread 的左頁 index」定義後退目標，不得對負數 index 呼叫 `openPage()`。
    - `dualPageMode == "never"`，或 `"auto"` 且非橫向時，維持現行單頁步進 1 不變。
  - **頁碼回報**（審查修正 I-7：改為與方向無關的錨點，消除「較小」與「左側」在 RTL 下互斥的矛盾）：雙頁生效時，原生 `onPageChanged` 一律回報 `currentPageIndex`（即步驟 3 配對規則的錨點索引：`ltr` 下為左頁、`rtl` 下為右頁），Dart 端依 `dualPageDirection` 自行推算配對頁與左右呈現位置。
  - **手動裁切互動範圍**（審查修正 I-8，完整規範決策 #10）：進入裁切編輯模式時，`CropOverlayView` 一律以 `currentPageIndex`（步驟 3 定義的 spread 錨點）為預覽基準單頁渲染（沿用既有 `renderFullPageForCropPreview()`，`CropOverlayView` 本身不需改動，只處理單頁座標）；確認後更新的是唯一的全書 `cropRect`（步驟 4），退出裁切模式回到雙頁時，左右頁皆套用此更新後的矩形。
- **`EpubReaderView`**（Dart，異動既有 `app/lib/reader/epub_reader_view.dart`）—— 建構子新增 `dualPageMode`、`isLandscape`（審查修正 C-2）參數，`didUpdateWidget` 偵測任一變動時送出 `setPreferences`。
- **`EpubReaderView.kt`**（Android，異動既有）—— `setPreferences` 接收 `dualPageMode`、`isLandscape` 參數：
  - **Spread 型別對應**（審查修正 C-1；2026-07-14 依 Issue 6 實作定案更新）：`buildPreferencesFromMap()` 新增 `spread = if (isDualPageEnabled(dualPageMode, isLandscape)) Spread.ALWAYS else Spread.NEVER`——經反編譯 `readium-navigator` 確認其型別為 `org.readium.r2.navigator.preferences.Spread` **enum**（非 Boolean），實測只有 `NEVER`／`ALWAYS` 兩個成員。`isLandscape` 不直接傳給 Readium API，而是與 `dualPageMode` 一併在 Kotlin 端算出是否啟用雙頁後手動切換 `ALWAYS`/`NEVER`，**不使用** `Spread.AUTO`（Issue 1 驗證確認 `AUTO` 不被 `EpubPreferences` 接受，見「待驗證風險與收斂關卡」）。
  - **`applyFxlFitScale()` 雙頁適配演算法**（審查修正 I-2，取代原「重新計算」的空泛描述；因 `epic-16-dual-page` Issue 8〔已完成並合併回 `main`，發生於本文件撰寫之後〕已將 `applyFxlFitScale()` 內的縮放係數／置中位移計算抽離為獨立 pure-Kotlin 模組 `EpubFxlScaler.kt`，本段落同步更新為與抽離後的架構一致，取代原本「直接在 `applyFxlFitScale()` 內就地新增算式」的舊描述）：`applyFxlFitScale()` 目前呼叫 `EpubFxlScaler.computeFitScale()`／`computeCenteringTranslation()` 取得縮放係數與置中位移；雙頁邏輯**應在 `EpubFxlScaler` 內擴充純函式**（而非退回在 `EpubReaderView.kt` 就地實作，見 `EpubFxlScaler.kt` 自身 KDoc 對 Issue 6 實作者的提示），呼叫端（`EpubReaderView.kt`）負責：偵測到 spread 生效（`findViewsByType<WebView>(container)` 回傳 2 個以上可見 WebView）時，把每個 WebView 的縮放基準 `availableWidth` 改為「container 寬度 / 2」（而非現行讓每個 WebView 各自以整個 container 寬度置中——該邏輯在雙頁下會使兩個 WebView 的置中位移互相重疊，見「已知限制」），並依 WebView 在螢幕上的左右順序（`getLocationOnScreen` 判斷）把各自 slot 的置中結果換算回螢幕絕對座標；`availableHeight` 不受影響。`cachedFxlFitScale` 是綁定單一 `EpubReaderView` 實例生命週期的快取狀態，維持留在 `EpubReaderView.kt`（不搬進 `EpubFxlScaler`），快取鍵需新增「是否為 spread 模式」維度，單頁/雙頁切換或裝置旋轉時皆須使快取失效重算（`removeFxlLayoutListener()` 現行機制在 `isFixedLayout` 為 false 時觸發清快取，但裝置旋轉時 `MainActivity` 以 `configChanges="orientation"` 使 Activity 不重建，不會自動呼叫此方法，需額外在方向變化回呼中主動清除 `cachedFxlFitScale`）。

## 資料模型 (Data Model)

### `book_reader_prefs`（SQLite，新增 3 欄位，既有表 ALTER）

```sql
ALTER TABLE book_reader_prefs ADD COLUMN dual_page_mode TEXT;            -- DualPageMode.name，NULL = auto（預設）
ALTER TABLE book_reader_prefs ADD COLUMN dual_page_cover_alone INTEGER;    -- 1=開啟, 0=關閉，NULL = 1（預設）
ALTER TABLE book_reader_prefs ADD COLUMN dual_page_direction TEXT;      -- DualPageDirection.name，NULL = rtl（Issue 4 決策後的預設，原為 ltr）
```

> **NULL 解析位置**（審查修正 I-3，2026-07-12 依 `ReaderPrefsManager` 重構同步修訂）：上述「NULL = 預設值」僅描述 SQL 層的語意，實際解析動作發生在 `ReaderPrefsManagerImpl.resolve()`（見「模組」一節），產出不可變的 `ResolvedPreferences` 值物件，`ReaderScreen` 只讀取其欄位（`resolved.dualPageMode` 等），原生端收到的 Method Channel 參數永遠是已解析的非 null 值，不會出現「原生端對 null 直接做 `== true` 判斷」的情形。

### `BookReaderPrefs`（Dart model，新增欄位）

```dart
class BookReaderPrefs {
  // ... 既有欄位不變 ...

  final DualPageMode? dualPageMode;
  final bool? dualPageCoverAlone;
  final DualPageDirection? dualPageDirection;

  // copyWith / toMap / fromMap 依既有模式平行擴充。
  // SQLite 沒有布林值，對應關係：dualPageCoverAlone 為 true 轉為 1，false 轉為 0。
}
```

### 新增列舉型別

```dart
// app/lib/reader/dual_page_mode.dart
enum DualPageMode { auto, always, never }

// app/lib/reader/dual_page_direction.dart
enum DualPageDirection { ltr, rtl }
```

## 介面 (Interfaces)

### 原生 Method Channel 契約異動

#### PDF 頻道 (`cc.ugotit.elinkbook/pdf_reader_view_$id`)
- **`openBook`** / **`setPdfPreferences`**：Map 擴充參數：
  - `dualPageMode`：`String`（`auto`／`always`／`never`，由 `ReaderScreen` 解析 null 後一律傳非 null 值，見「Null 預設值解析」）
  - `dualPageCoverAlone`：`bool`（同上，一律非 null）
  - `dualPageDirection`：`String`（`ltr`／`rtl`，同上，一律非 null）
  - `isLandscape`：`bool`（審查修正 C-2 新增，見下方「方向偵測契約」）

#### EPUB 頻道 (`cc.ugotit.elinkbook/epub_reader_view_$id`)
- **`openBook`** / **`setPreferences`**：Map 擴充參數：
  - `dualPageMode`：`String`（`auto`／`always`／`never`，一律非 null）
  - `isLandscape`：`bool`（審查修正 C-2 新增，見下方「方向偵測契約」）

### 方向偵測契約（審查修正 C-2）

原「模組」節（`ReaderScreen`）與「介面」節對方向偵測的資料流向互相矛盾——前者說 Dart 偵測後下傳，後者未列出對應欄位。以下為定案的唯一版本：

1. **偵測位置**：`ReaderScreen.build()` 透過 `MediaQuery.of(context).orientation == Orientation.landscape` 判斷，不在原生端重複偵測。
2. **傳遞方式**：`PdfReaderView`／`EpubReaderView` 建構子新增 `isLandscape: bool` 參數（非 nullable，`ReaderScreen` 必定提供實際偵測值），`didUpdateWidget` 偵測到方向變化時，與其他雙頁參數一併透過 `setPdfPreferences`／`setPreferences` 送出（不新增獨立的 Method Channel 呼叫）。
3. **`auto` 模式的實際生效條件**（2026-07-14 依 Issue 6 實作定案更新）：PDF 與 EPUB 兩端皆以 `isDualPageEnabled(dualPageMode, isLandscape)` 同一組語意判定啟用雙頁（`always` 一律生效；`auto` 僅橫向生效；`never` 一律不生效）；PDF 原生端據此決定是否拼接雙頁（見 `renderCurrentSpread()` 步驟 1），EPUB 原生端據此手動切換 Readium `Spread.ALWAYS`/`Spread.NEVER`（不使用 `Spread.AUTO`，Issue 1 已驗證確認該值不被 `EpubPreferences` 接受）。
4. **PlatformView 不得因旋轉重建**（design.md 已知風險項）：`MainActivity` 現行以 `android:configChanges="orientation|screenSize"`（需在 `AndroidManifest.xml` 確認涵蓋兩者）避免 Activity 重建，此為 PDF／EPUB 兩條 `PlatformView` 在旋轉時維持存活、僅接收新 `isLandscape` 值重繪的前提；本 epic 實作時須以真機旋轉驗證兩個 View 皆不重建（沒有黑屏或重新 `openBook`）。

## 待驗證風險與收斂關卡（審查修正 I-1）

以下風險在 design.md 中被列為「待 Architecting 階段確認」，但本文件（實作唯一事實來源）在其操作段落曾以肯定語氣描述為已解決；經審查指出後，此處明訂**必須在進入 Scrum Master 拆解前**以 spike（`prototype` 技能或等效的一次性真機驗證）完成並回填結論，不得留待實作階段才發現：

> **Issue 1 驗證結果（2026-07-12）：4 項中 Q1 部分通過、Q2 失敗、Q3 元資料正確但渲染未驗證、Q4 未測試**——完整證據見 `reviews/spike-readium-spread.md`。Q2 失敗（`Spread.AUTO` 不被 `EpubPreferences` 接受）已確定退回方案：EPUB 側手動依 `isLandscape` 切換 `ALWAYS`/`NEVER`。Q1 發現 Readium FXL 的 `Spread.ALWAYS` 僅產生半寬 WebView（不建立雙 WebView），Issue 6 需自行管理雙頁顯示（建議先以控制組二次確認）。Q3 延後驗證，Q4 延後但實作可參考 Task 4 演算法草稿。

1. **Readium `Spread.AUTO`/`Spread.ALWAYS` 是否無間距**：真機驗證啟用後頁間是否有可見間距（FR-41 硬性要求「不留空白」）。若無法消除間距，回退方案：改用與 PDF 相同的「拼接」策略（即 EPUB FXL 頁面各自渲染為圖片後手動並排），需另立工單並重新評估 `applyFxlFitScale()` 相關段落。
   > **Issue 1 驗證結果（2026-07-12）：⚠️ 部分通過**——`Spread.ALWAYS` 使 WebView 寬度 = 螢幕寬度 × 50%（直向 800/1600、橫向 1200/2400），但僅建立一個 WebView（無 `firstWebView`/`secondWebView` 配對）。FR-41「不留空白」若指雙頁並排中間無縫隙則 N/A（僅單頁）；若指整體畫面無非內容空白則不通過（兩側各 25% 空白）。退回方案：Issue 6 需自行管理雙 WebView 的建立與配置，不依賴 Readium 內建 spread 機制（提醒：本結論主要基於漫畫素材，建議 Issue 6 啟動時先以控制組的一般 spread 頁進行二次確認）。
> >
> > **補充驗證（2026-07-13，`reviews/spike-readium-spread-webview-count.md`）：先前結論已被推翻。** Issue 1 原始驗證只測試到封面頁（page: center，Readium 規範下本就只會是單頁），翻到非封面配對頁面後，Readium 確實會自動建立 2 個無縫並排的 WebView（`x=0`/`x=1200`，container 寬度 2400）。原「需自行管理雙 WebView」的退回方案已撤銷，`plans/plan-issue-6.md` 改回簡化路線：原生端只需切換 `spread` 並修正 `applyFxlFitScale()` 偵測到 2 個 WebView 時的縮放/置中運算。
2. **`Spread.AUTO` 是否等同「橫向才雙頁」**：若 Readium 的 `AUTO` 語意與螢幕方向無關（例如依內容尺寸比例判斷），則 EPUB 側需改為直接依 `isLandscape` 手動在 `ALWAYS`/`NEVER` 間切換，不使用 `AUTO`。
   > **Issue 1 驗證結果（2026-07-12）：❌ 失敗**——`Spread.AUTO` 不被 `EpubPreferences` 接受（`require(spread in listOf(null, Spread.NEVER, Spread.ALWAYS))`），設定後觸發 `IllegalArgumentException`。退回方案（已確定）：EPUB 側**手動依 `isLandscape` 切換** `Spread.ALWAYS`（橫向）/ `Spread.NEVER`（直向），不使用 `Spread.AUTO`。
3. **`page-spread-left/right` metadata 配對是否正確**：驗證多本實際漫畫 FXL EPUB 的頁面配對結果符合預期（尤其含蝴蝶頁/跨頁大圖的邊界情況）。
   > **Issue 1 驗證結果（2026-07-12）：⚠️ 元資料正確，渲染未驗證**——漫畫 manifest 確認 `readingProgression=rtl`、封面 `page=center`、其後嚴格交替 `page=left`/`page=right`。但因 Readium FXL 僅建立單一 WebView（見 Q1），無法驗證配對渲染是否正確。延後至 Issue 6 建立雙頁顯示後再驗證。
4. **`applyFxlFitScale()` 雙頁下是否真的不再重疊**：驗證「已知限制」與模組節所述的半寬置中演算法在真機上確實讓兩個 WebView 並排而非重疊。
   > **Issue 1 驗證結果（2026-07-12）：⚠️ 未測試**——前提（雙 WebView 存在）不成立（見 Q1），無法驗證。延後至 Issue 6 解決 WebView 管理問題後再驗證（實作時可參考 reviews 報告中 Task 4 的 slotLeft 演算法草稿做為起點）。
> >
> > **補充驗證（2026-07-13，`reviews/spike-readium-spread-webview-count.md`）：** 補充 Spike 確認 Readium 在翻頁至非封面頁面後自動建立 2 個 WebView，Item 1 的補充結論同步更新此項：`applyFxlFitScale()` 已在 Issue 6 實作中依此結論改寫（可見性篩選 + 排序後 index 分配 slot + slotOffsetX 換算），不再需要自行管理雙 WebView。

若上述任一項驗證失敗，對應工單需改為「退回自行實作」路線，並在 issue 拆解前更新本文件對應段落——不得由實作者在工單執行階段自行決定退回與否。

---

## 測試決策 (Testing Decisions)

### 1. 單元測試 (Unit Tests)
- **列舉與資料模型**：驗證 `DualPageMode` 與 `DualPageDirection` 列舉定義；驗證 `BookReaderPrefs` 新欄位的 serialization/deserialization。
- **資料庫遷移**：驗證 `ALTER TABLE` 成功升級，升級後歷史書籍的新欄位預設皆為 `NULL`，不影響既有 EPUB 書籍之載入。

### 2. Widget 測試 (Widget Tests)
- **`PdfSettingsSheet`**：驗證「顯示」分頁新增的 3 個雙頁控制項：
  - 點擊「雙頁模式」選項會觸發 `onChanged` 傳回對應的 `BookReaderPrefs`。
  - 切換「封面獨立」與「閱讀方向」開關會觸發 `onChanged`。
- **`FxlSettingsSheet`**：驗證固定版面 EPUB 的設定 Sheet 能正常泵起（pump），且點擊「雙頁模式」選項會正確觸發 `onChanged`。
- **`ReaderScreen`**：
  - 驗證裝置轉為橫向時，會透過 `isLandscape` 參數將當前螢幕方向狀態正確反映給 `PdfReaderView`／`EpubReaderView`（審查修正 C-2：驗證方式為斷言下傳給 `PlatformView` 建構參數的 `isLandscape` 值，而非「Native View」這種無法在 widget test 層級觀察的說法）。
  - 驗證 EPUB 固定版面（`isFixedLayout == true`）開書後，畫面右上角出現半透明懸浮設定按鈕 `Key('reader_fixed_layout_settings_button')`（審查修正 C-3：修正原「齒輪按鈕依然在 AppBar 顯示」的錯誤描述——固定版面 AppBar 為 `null`，此按鈕是獨立於 AppBar 之外的懸浮元件），且點擊能開啟 `FxlSettingsSheet`。

### 3. 整合測試 (Integration Tests，真實裝置)
- **PDF 橫向自動雙頁**：
  - 開啟 PDF，方向鎖定為 `auto`，模擬裝置旋轉至橫向，驗證畫面進入雙頁顯示，且每次點擊翻頁手勢，原生回傳的頁碼步進為 2。
  - 模擬裝置旋轉回直向，驗證畫面自動還原為單頁顯示，翻頁步進恢復為 1。
- **PDF 雙頁無間距**（審查修正 I-6，補齊 FR-41 核心驗收點）：橫向雙頁顯示時，斷言拼接後的點陣圖左右兩頁之間沒有可見間距/接縫（例如比對拼接點陣圖寬度等於兩頁個別寬度之和，不含額外留白像素）。
- **PDF 封面獨立與配對驗證**：
  - `dualPageCoverAlone` 為 `true` 時，第 0 頁（封面）應單頁顯示。往後翻一頁，畫面應顯示第 1 頁與第 2 頁的拼接，且回報 index 為 1。
  - `dualPageCoverAlone` 為 `false` 時，第 0 頁應與第 1 頁拼接並排顯示。
  - **從 (1,2) 往回翻應回到封面**（審查修正 I-6／C-4）：在 spread `[1,2]` 呼叫 `previousPage()`，驗證畫面回到單頁封面（index 0），而非崩潰或卡在 index 1 不動。
  - **奇數總頁數的最後一頁落單**（審查修正 I-6，決策 #8c）：以總頁數為奇數的 PDF 驗證最後一個 spread 只顯示單頁、另一側為白色背景填充。
- **PDF 閱讀方向（LTR/RTL）驗證**（審查修正 I-7：以 `currentPageIndex` 錨點取代「較小頁碼」的方向相關措辭）：
  - `dualPageDirection` 為 `ltr` 時，`onPageChanged` 回報值等於 `currentPageIndex`（左頁），畫面左側顯示該頁、右側顯示 `currentPageIndex + 1`。
  - `dualPageDirection` 為 `rtl` 時，`onPageChanged` 回報值同樣等於 `currentPageIndex`，但畫面右側顯示該頁、左側顯示 `currentPageIndex + 1`。
- **PDF 拼接 OOM 回退**（審查修正 I-4／I-6）：以裝置可用記憶體受限或超大頁面尺寸情境模擬拼接階段 `OutOfMemoryError`，驗證畫面回退為單頁渲染（不崩潰），且 `onPageChanged` 回報值為 `currentPageIndex`。
- **EPUB FXL 雙頁切換**（2026-07-14 依 Issue 6 實作定案更新）：
  - 橫向狀態下，`dualPageMode = auto` 使 `isDualPageEnabled()` 判定為 `true`、原生端切換為 `Spread.ALWAYS`（不使用 `Spread.AUTO`），翻頁至非封面內頁後驗證畫面成功並排顯示兩頁、頁間無可見間距（FR-41 核心驗收點）、封面頁維持單頁、且無翻頁崩潰——已於真機以真實漫畫素材（`tmp/一弦定音！(06).epub`）人工視覺確認通過（見 `plans/plan-issue-6.md`「Bugfix 紀錄」）。
- **裁切與雙頁互動安全**：
  - 雙頁模式下點擊「手動選區」，驗證進入裁切模式時畫面會立刻暫時切回單頁渲染（以 spread 錨點 `currentPageIndex` 為預覽基準）；完成裁切並確認後，畫面回到雙頁模式，且左右兩頁皆正確套用新裁切白邊（同一個全書 `cropRect`）。
- **旋轉發生在手動裁切編輯模式中**（審查修正 I-6）：進入裁切編輯模式後將裝置旋轉，驗證 `CropOverlayView.onSizeChanged` 既有的旋轉重算邏輯正常運作、不因雙頁/單頁狀態切換而錯位或崩潰。

---

## 已知限制

- **拼接 Bitmap 記憶體風險**：在低階 E-Ink 裝置上，雙頁拼接後的 Bitmap 記憶體佔用較高。若拼接階段拋出 `OutOfMemoryError`，依 `renderCurrentSpread()` 步驟 5（審查修正 I-4）回退為只渲染 `currentPageIndex` 單頁，以確保閱讀器不崩潰——原描述「將自動回退到單頁渲染」在初版中僅見於本節、未落實於演算法步驟，且與現行單頁 OOM catch（同頁以原始未縮放尺寸重繪，並非切換渲染模式）是不同機制，現已在演算法步驟中明訂為雙頁拼接專屬的回退路徑。
- **裁切矩形為全書共用、非逐頁偵測**（審查修正 I-5）：雙頁模式下左右頁套用的是同一個 `cropRect`（現行 `PdfReaderView.kt` 的 autoDetect 本就是全書統一矩形，非逐頁重算）。當左右頁天然白邊寬度不同（常見於掃描書）時，可能導致裁切不理想（切到內容或留白不均）；本 epic 不新增 per-page 裁切偵測（YAGNI）。
- **裁切切換視覺閃爍**：進入手動裁切時會強制從雙頁切換為單頁預覽，這在視覺上會有一次瞬時閃爍，此為設計上的折衷（YAGNI），不進行額外的平滑動畫處理。
- **EPUB FXL 換頁縮放跳動（2026-07-14 記錄，待優化）**：真機視覺驗收確認 Issue 6 bug 修正後雙頁並排/無縫隙已正確，但每次換頁時會觀察到一次縮放動作（`applyFxlFitScale()` 的 `OnGlobalLayoutListener` 重新觸發套用 `scaleX`/`scaleY`/`translationX`/`translationY`），略為影響閱讀體驗。根因尚未排查（可能與 `cachedFxlFitScale` 重新計算時機、或換頁瞬間 WebView 尺寸量測時序有關），留待後續 issue 處理，不阻塞 Issue 6 完成。
- **PDF／EPUB 漫畫全版面沉浸顯示（2026-07-14 記錄，未來考慮）**：目前 PDF／EPUB 固定版面在橫向雙頁（甚至單頁）模式下仍保留系統狀態列與導覽列。未來可考慮讓這兩種格式在此情境下改為全版面沉浸顯示（隱藏系統列），與 `FxlSettingsSheet` 已預留但未實作的 FR-42 全螢幕開關 UI 擴充空間相關，屬獨立於本 epic 範圍的後續功能，留待後續規劃。
