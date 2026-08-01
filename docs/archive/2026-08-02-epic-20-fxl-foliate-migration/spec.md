# Epic 20 — FXL 渲染引擎遷移至 `foliate-js`：技術規格 (Spec)

> 本文件由 `/grill-with-docs` 2026-07-31 Architecting 階段產生，架構決策見 `docs/adr/0017-fxl-migrate-to-foliate-js.md`。自本文件起為本 Epic 實作階段的唯一事實來源。

## 範圍

**本次遷移交付**：FXL EPUB 的基本閱讀能力（開書、橫向雙頁、封面獨立顯示、RTL 頁序、進度條/目錄、書籤）統一由 `FoliateEpubReaderView` 提供；`EpubReaderView`（Readium）路徑完全移除。（**修正**（Issue 2 程式碼審查發現，2026-07-31）：頁尾 `X/Y` 頁碼顯示**不**在此清單內——`FoliateEpubReaderView` 目前沒有字元數統計機制，此功能對所有透過它渲染的 EPUB 皆不可用，見 `issues.md` Issue 2「已知限制」，非本次遷移範圍內可解決的項目。）

**明確排除**：劃線/備註（`overlayer.js`）在 FXL 雙頁模式下的支援——另立後續 Epic（見 ADR 0017 決策 6）。

## 現況基線（查證，非本次新增）

- `app/android/app/src/main/assets/foliate/` 目前只有 8 個檔案（`view.js`／`epub.js`／`epubcfi.js`／`progress.js`／`overlayer.js`／`text-walker.js`／`paginator.js`／`vendor/zip.js`），**沒有 `fixed-layout.js`**——production `main.js` 從未處理過 FXL 書籍，`spread`／`dualPage` 相關程式碼在 production 端完全不存在（Spike 用的是 `tmp/epic-20/` 下完全獨立的 throwaway `main.js`，不影響 production）。
- `app/lib/reader/foliate_epub_reader_view.dart` 目前無 `dualPageMode`／`isLandscape`／FXL 相關建構參數；`buildFoliatePreferencesMap()`／`foliatePreferencesChanged()` 兩個頂層函式（見該檔案）是既有的、比照 `writingMode`/`pageTurnMode` 等既有欄位擴充偏好參數的既定模式。
- `MainActivity.kt` 的 `FlutterFragmentActivity`／`supportFragmentManager` 相關程式碼（`:60-75`）唯一服務對象是 `EpubNavigatorFragment`（Readium）。
- `BookMetadataChannel.kt` 的 `extractEpubMetadata()`／`detectEpubLayout()` 使用 `readium-shared`／`readium-streamer`，**本次不變動**。

## 核心介面異動

### 1. `app/lib/reader/foliate_epub_reader_view.dart`

新增建構參數（比照既有 `writingMode`/`pageTurnMode` 等欄位的既定模式，皆為可選）：

```dart
final DualPageMode? dualPageMode;   // 沿用既有 app/lib/reader/dual_page_mode.dart 列舉（auto/always/never）
final bool isLandscape;             // 比照舊 EpubReaderView 的必要參數，預設 false
final bool? isFixedLayoutHint;      // 對應 Book.isFixedLayout（ADR 0017 決策 3/4：僅供開書時的 UI 覆蓋提示，非引擎選擇）
```

`buildFoliatePreferencesMap()` 新增對應 3 個 key（`dualPageMode`／`isLandscape`／`isFixedLayoutHint`，命名與既有 `showFooter`/`columnMode` 同一慣例）；`foliatePreferencesChanged()` 同步新增 3 個欄位比較。

`onLayoutResolved` 回呼的 `EpubLayoutInfo.isFixedLayout` 語意不變（既有欄位，繼續由 `main.js` 開書後回報實際判定結果，供 `ReaderScreen._isFixedLayout` 驅動 FXL chrome 顯示——這條路徑本來就與 `Book.isFixedLayout`/`isFixedLayoutHint` 是兩個不同概念，見既有 `_dispatchedIsFixedLayout` 註解）。

### 2. `app/android/app/src/main/assets/foliate/`

新增 `fixed-layout.js`（釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`，Spike 已驗證的同一檔案，含 `construct-style-sheets-polyfill` no-op stub 處理，比照 Spike Task 2 Step 1 的既有作法）。

`main.js` 新增（比照既有 `applyPreferences`／`window.FoliateBridge` 既定模式，不新增額外橋接機制）：
- `openBook()` 流程內：讀取 `isFixedLayoutHint` 偏好，若為 `true` 且 `book.rendition?.layout !== 'pre-paginated'`，於呼叫 `view.open(book)` 前覆寫 `book.rendition.layout = 'pre-paginated'`（ADR 0017 決策 4，僅在不一致時覆寫）。
- `applyPreferences()` 內新增依 `dualPageMode`／`isLandscape` 計算 `isDualPageEnabled`（邏輯移植自即將刪除的 `EpubReaderView.kt` 既有 `isDualPageEnabled(dualPageMode, isLandscape)` 純函式：`ALWAYS` 恆真、`AUTO` 依 `isLandscape`、`NEVER` 恆假），呼叫 `view.renderer?.setAttribute('spread', enabled ? 'both' : 'none')`（僅在 `view.isFixedLayout === true` 時才有意義，`renderer` 非 FXL 時是 `foliate-paginator`，沒有 `spread` attribute，呼叫需防禦性判斷）。

### 3. `app/lib/screens/reader_screen.dart`

- `_buildNativeView()` 內 `BookFormat.epub` 分支移除 `if (!_dispatchedIsFixedLayout!) { ... } else { return EpubReaderView(...) }` 的雙分支，統一建構 `FoliateEpubReaderView`，新增傳入 `dualPageMode: resolved.dualPageMode`／`isLandscape: isLandscape`／`isFixedLayoutHint: widget.isFixedLayout`（既有 `ReaderScreen` 建構參數，語意不變，見 ADR 0007）。
- `_epubReaderViewKey`／`EpubReaderView.jumpToProgression` 等所有 Readium-only 呼叫點改為統一呼叫 `FoliateEpubReaderView` 對應的 static helper（多數呼叫點已是依 `_dispatchedIsFixedLayout` 三元判斷兩個 key 之一，改為恆定使用 `_foliateEpubReaderViewKey`）。
- `reader_fixed_layout_*` 系列浮動按鈕（`epic-18` Issue 15 新增的 `reader_fixed_layout_back_button` 等 4 顆）與 `reader_foliate_*` 系列浮動按鈕（既有 8 顆，含 Issue 20/21/22 訴求已涵蓋的功能）**合併為一組**，沿用 `reader_foliate_*` 系列既有 Key 命名與版面（`_isFixedLayout`／`_dispatchedIsFixedLayout` 判斷式改為以 `_chromeVisible` 為唯一 gating 條件，不再區分兩組）——實作階段需盤點既有 Widget test 對 `reader_fixed_layout_*` Key 的斷言，同步更新或移除。

### 4. 移除項目（ADR 0017 決策 1/7）

- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderViewFactory.kt`
- `app/lib/reader/epub_reader_view.dart`
- `app/android/app/build.gradle.kts` 內 `org.readium.kotlin-toolkit:readium-navigator:3.3.0`
- `MainActivity.kt`：`FlutterFragmentActivity` → `FlutterActivity`；`EpubNavigatorFragment` 相關 import 與 `:60-75` 程序還原邏輯；`configureFlutterEngine()` 內 `EpubReaderView` 的 `PlatformView` 類型字串註冊
- `app/test/reader/epub_reader_view_test.dart`（隨 widget 一併移除；`FoliateEpubReaderView` 既有測試需擴充涵蓋新參數）

### 5. 資料模型（無 schema 異動）

`Book.isFixedLayout`（`books.is_fixed_layout` 欄位）語意窄化為「UI 行為提示」（ADR 0017 決策 3），**不新增／不移除任何欄位**；`BookMetadataChannel.detectEpubLayout()`／`LibraryRepository.detectAndCacheEpubLayout()` 既有寫入邏輯不變。`epic-18` Issue 15「強制 FXL」／「恢復自動判斷」UI 與資料寫入邏輯不變，僅下游消費語意改變（見上方第 1/2 節）。

## 已知限制（明確排除，非本次交付）

- 劃線／備註（`overlayer.js`）在 FXL 雙頁模式下的視覺/定位正確性未驗證，FXL 書籍暫時不提供劃線/備註功能。
- 既有 FXL 書籍的書籤/劃線/備註/閱讀進度資料視為失效，不做遷移轉換（ADR 0017 決策 5）。

## 相關佐證

- `docs/adr/0017-fxl-migrate-to-foliate-js.md`
- `docs/epics/epic-20-fxl-foliate-migration/design.md`
- `docs/epics/epic-20-fxl-foliate-migration/reviews/spike-issue1-fxl-foliate.md`
- `app/lib/reader/foliate_epub_reader_view.dart:85-232`（`buildFoliatePreferencesMap()`／`foliatePreferencesChanged()`／建構參數既有結構）
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`（`isDualPageEnabled()` 純函式，供 `main.js` 移植參考邏輯）
- `app/lib/reader/dual_page_mode.dart`（既有 `DualPageMode` 列舉）
