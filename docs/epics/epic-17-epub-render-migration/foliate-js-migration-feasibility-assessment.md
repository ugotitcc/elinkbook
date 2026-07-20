# Readium 替換為 foliate-js 之可行性與架構評估報告

**建立時間**：2026-07-20  
**專案**：elinkBook (Flutter Android 電子書閱讀器)  
**標的**：評估將 EPUB 原生渲染引擎由 Readium (Kotlin Native Toolkit) 切換至 [readest/foliate-js](https://github.com/readest/foliate-js) 之可行性與架構衝擊。

---

## 1. 摘要與評估結論

**評估結論：可行性極高（High Feasibility），建議採用。**

將 Readium 替換為 `foliate-js` 能夠完全解決目前專案在**繁體中文直排（`writing-mode: vertical-rl`）**與 CSS 版面掌控上的原生缺口，同時能**刪除 Kotlin 原生層超過 1,500 行的複雜 Workaround 程式碼**（如 View 樹手動縮放 `EpubFxlScaler`、`fontWeight` 強制下發等）。

透過轉接層（Bridge Adapter）設計，對現有 Flutter Dart 層（`ReaderScreen`）與 SQLite 資料庫無破壞性影響，架構切面（Seam）與契約完全保持穩定。

---

## 2. 共識決策樹總覽 (Decisions Summary)

| 評估維度 | 決策方案 | 說明與優勢 |
| :--- | :--- | :--- |
| **1. 替換核心動機** | **繁體中文直排與 CSS 相容性** | 徹底解決 Readium 在 Android Native WebView 下直排分頁、字體與邊距控制的相容性缺陷，改由現代 Chromium 瀏覽器引擎原生支援。 |
| **2. 定位資料相容性** | **Bridge Adapter 相容封裝** | 在 JS Bridge 將 `foliate-js` 的 CFI 與位置資訊封裝為包含 `href` + `progression` + `cfi` 的相容 JSON。**Dart 層與 SQLite 閱讀位置、目錄、劃線備註 100% 相容續用**。 |
| **3. Native 載體與串流** | **PlatformView + `WebViewAssetLoader`** | 保留 Kotlin 原生 `EpubReaderView.kt` 作為 `PlatformView` 載體，並利用 `WebViewAssetLoader` 攔截 `https://` 本地請求串流 EPUB 檔案，**零 OOM 風險且不改動 Flutter 介面契約**。 |
| **4. WebView 相容標準** | **Android 11 (Chromium 83+ target)** | 前端 Vite / ESBuild 打包時設定 `target: 'chrome83'`。**確保無 Google Play 更新的 Android 11 離線 E-Ink 閱讀器不白畫面**。 |
| **5. 固定版面與字數統計**| **完全交由 JS 層處理** | 刪除 Kotlin 原生 `EpubFxlScaler.kt` 與 `EpubCharacterCounter.kt`。FXL 雙頁縮放與全書字數統計完全在 Web Worker/JS 層計算後拋給 Dart。 |
| **6. 3×3 熱區與沉浸模式** | **統一由 JS 層處理** | 簡化現有「FXL 透明疊加層 vs 流式 InputListener」的雙軌邏輯，全由 JS 層判斷 3×3 熱區點擊，僅將 `menu`（選單）事件拋回 Dart 觸發沉浸模式。 |

---

## 3. 程式碼衝擊與簡化範圍 (Codebase Impact)

### 3.1 原生層 (Kotlin) —— 大幅簡化與瘦身
* 🗑️ **完全刪除** `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubFxlScaler.kt`：原先為了修補 Readium 固定版面縮放與雙頁中縫空白的 300+ 行矩陣運算程式碼可直接移除。
* 🗑️ **完全刪除** `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubCharacterCounter.kt`：原先背景協程解壓 EPUB 算字數的邏輯，改由 `foliate-js` 背景 Worker 處理。
* ✂️ **大幅重構** `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`：
  * 移除 Readium `EpubNavigatorFragment`、`FragmentFactory` 與複雜的生命週期防護。
  * 移除 `findViewsByType` 遞迴尋找多個 WebView 並注入 CSS `font-weight` cascade 的補修。
  * 簡化為：單一 `android.webkit.WebView` + `WebViewAssetLoader` + `JavascriptInterface` 通訊。

### 3.2 Flutter 層 (Dart) —— 契約維持穩定
* ✅ `app/lib/screens/reader_screen.dart`：**零改動**。閱讀器入口切面、頂端/底端控制列、沉浸模式切換邏輯完全維持原樣。
* ✅ `app/lib/reader/book_reader_prefs.dart` & 偏好資料庫：**零改動**。所有偏好設定（字型、字級、直橫排、翻頁模式等）依然透過 `buildPreferencesMap()` 送給原生層。
* 🔧 `app/lib/reader/epub_reader_view.dart`：僅微調內部的通道通訊與事件接收器，對外公開的 static helper（如 `jumpToProgression`, `loadTableOfContents`, `setDecorations`）強型別 API **簽章保持不變**。

---

## 4. 預估實作步驟與階段 (Implementation Roadmap)

1. **Phase 1：前端靜態資源打包 (Foliate Web Bundle)**
   * 將 [readest/foliate-js](https://github.com/readest/foliate-js) 引入為模組，使用 Vite 配置打包腳本，設定 `target: 'chrome83'`，產出單一 `reader.html` 與 JS/CSS assets 放置於 Android `assets/foliate/`。
2. **Phase 2：Kotlin Native PlatformView 替換**
   * 在 `EpubReaderView.kt` 中引入 `WebViewAssetLoader`，建立 `JavascriptInterface` (JS Bridge)，接管原本 `MethodChannel` 的 `openBook`, `setPreferences`, `jumpToLocator` 指令。
3. **Phase 3：驗證直排與定位 Adapter**
   * 測試繁體中文直排（`writing-mode: vertical-rl`）表現、目錄跳轉、CFI 與 Readium Locator JSON 轉接層。
4. **Phase 4：清理舊程式碼與整合測試**
   * 移除 `EpubFxlScaler.kt` 等舊 Readium workaround，執行 `flutter analyze` 與 `integration_test` 驗收。
