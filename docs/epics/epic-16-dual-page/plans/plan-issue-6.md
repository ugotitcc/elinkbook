# Epic 16 Issue 6 — EPUB FXL 雙頁實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐 Task 執行本計劃。每個 Step 用 checkbox（`- [ ]`）追蹤，完成後即時勾選為 `[x]`（見 CLAUDE.md SDD 生命週期第 6 步、AGENTS.md 慣例清單）。

**Goal:** 讓 EPUB 固定版面（FXL 漫畫）在橫向且 `dualPageMode` 生效時，以 Readium 內建機制自動並排顯示左右兩頁，並提供 `FxlSettingsSheet` 讓使用者切換雙頁模式。

**Architecture（本版本，取代先前「自建雙 Fragment」草案）：** 依 `reviews/spike-readium-spread-webview-count.md` 的真機驗證結論，Readium 的 `EpubNavigatorFragment` 在 `Spread.ALWAYS` 生效且翻頁至非封面的配對頁面時，底層會**自動**建立兩個並排、無縫隙的 WebView（先前 `spike-readium-spread.md` 「只建立單一半寬 WebView」的結論，是因為當時測試只停留在封面頁——封面 `page: center` 本就只會是單頁，翻到封面之後的內頁才會出現兩個 WebView）。因此**完全不需要自建雙 PlatformView／雙 Fragment 容器**：`EpubReaderView` 維持現行單一 Fragment／單一 `container` 架構，原生端只需（1）依 `dualPageMode`／`isLandscape` 切換 `EpubPreferences.spread` 為 `ALWAYS`/`NEVER`，（2）修正 `applyFxlFitScale()`，偵測到 2 個 WebView 時把可用寬度視為 `container.width / 2`，並依各 WebView 的螢幕 x 座標換算正確的置中位移。翻頁沿用 Readium 既有原生手勢（tap 分區／swipe），Dart 端不需要新增 `GestureDetector` 或 `nextPage`/`previousPage` method channel。

**Tech Stack:** Flutter（Dart）、Kotlin、Readium `kotlin-toolkit` 3.3.0（`EpubPreferences.spread`／`EpubNavigatorFragment`）、JUnit4（JVM 純函式測試）、`integration_test`（真機）。

## 兩份 Spike 報告的關係（重要，執行前務必理解）

1. `reviews/spike-readium-spread.md`（Issue 1 原始 Spike）：只測試到封面頁（page 0），觀察到「只有 1 個半寬 WebView」，因此建議 Issue 6 改走「自建雙 Fragment」（Option A）。**本計劃先前版本正是依此結論撰寫**，內容涉及自建 `leftContainer`/`rightContainer`、雙 `EpubNavigatorFragment`、`page`-屬性配對純函式、Dart `GestureDetector` 驅動翻頁等，已全數作廢，未曾套用到實際程式碼。
2. `reviews/spike-readium-spread-webview-count.md`（本次補充 Spike）：真機翻頁至封面之後的配對頁面（page 1-2），確認 Readium **自動**建立 2 個無縫並排的 WebView（`x=0`／`x=1200`，container 寬度 2400）。此結論**推翻**了第 1 份報告的推論，本計劃依此重新改為原始 `spec.md` 設計的簡化路線。

## Global Constraints

- 所有程式碼註解與說明使用正體中文（CLAUDE.md）。
- Android `minSdk` 現行為 24，不得調整。
- `EpubPreferences.spread` 型別為 `org.readium.r2.navigator.preferences.Spread`，本次補充 Spike 確認其列舉成員只有 `NEVER`／`ALWAYS`（無 `AUTO`），沿用 Issue 1 已確定的退回方案：EPUB 側手動依 `isLandscape` 在 `ALWAYS`/`NEVER` 間切換，不使用 `AUTO`。
- `EpubFxlScaler.computeFitScale`/`computeCenteringTranslation` 函式簽章不得變動——雙頁的「可用寬度減半」與「左右 slot 位移換算」邏輯留在呼叫端（`EpubReaderView.kt` 的 `applyFxlFitScale()`），不新增 `EpubFxlScaler` 函式（`EpubFxlScaler.kt` 現有 KDoc 建議新增多載函式，本計劃改採「呼叫端在既有函式呼叫前後加一層 slot 位移換算」的簡化寫法，效果等價、不增加 `EpubFxlScaler.kt` 的介面面積）。
- `cachedFxlFitScale` 快取需新增「是否為 spread 模式」維度：`dualPageMode`/`isLandscape` 任一欄位實際改變時使快取失效重算（spec.md 既有要求）。
- 單頁模式（`dualPageMode == never`，或 `auto` 且非橫向）的既有行為（原生手勢、文字選取、捲動模式、既有回呼語意）**不得回歸**——每個 Task 完成後皆需確認既有 `app/test/reader/epub_reader_view_test.dart`（4 個測試）與 `app/integration_test/epub_reader_view_test.dart`（9 個測試）維持全數通過。

---

### Task 1: `EpubPreferences.spread` 依 `dualPageMode`/`isLandscape` 切換

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`
- Create: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/EpubReaderViewDualPageTest.kt`

**Interfaces:**
- Produces：`internal enum class DualPageMode`、`internal fun isDualPageEnabled(dualPageMode: DualPageMode, isLandscape: Boolean): Boolean`（供 Task 2 沿用同一組狀態欄位）；`buildPreferencesFromMap()` 回傳值新增 `spread` 欄位。

- [ ] **Step 1: 新增 import**

在 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt` 現有 import 區塊（`import org.readium.r2.navigator.preferences.FontFamily` 附近）新增：

```kotlin
import org.readium.r2.navigator.preferences.Spread
```

- [ ] **Step 2: 新增 `DualPageMode` 巢狀列舉與雙頁狀態欄位**

在 `class EpubReaderView(...) : PlatformView, ... {` 開頭（`private val containerId = View.generateViewId()` 之前）新增：

```kotlin
    /**
     * 橫向雙頁顯示觸發模式（epic-16-dual-page），對應 Dart DualPageMode 列舉
     * （`app/lib/reader/dual_page_mode.dart`）透過 Method Channel 傳來的
     * `.name` 字串（'auto'／'always'／'never'）。與 PdfReaderView.DualPageMode
     * 是各自獨立的巢狀型別，比照既有慣例（見 PdfReaderView.kt）。
     */
    internal enum class DualPageMode {
        AUTO, ALWAYS, NEVER;

        companion object {
            fun fromWireValue(value: String?): DualPageMode = when (value) {
                "always" -> ALWAYS
                "never" -> NEVER
                else -> AUTO
            }
        }
    }

    companion object {
        /** 雙頁顯示是否應該生效：`always` 一律生效；`auto` 僅橫向生效；`never`
         * 一律不生效。用於決定送給 Readium 的 `Spread` 值（見
         * [buildPreferencesFromMap]），非 Readium API 本身的邏輯。*/
        internal fun isDualPageEnabled(dualPageMode: DualPageMode, isLandscape: Boolean): Boolean =
            dualPageMode == DualPageMode.ALWAYS ||
                (dualPageMode == DualPageMode.AUTO && isLandscape)
    }
```

在 `currentPreferences` 欄位宣告之後新增：

```kotlin
    private var dualPageMode: DualPageMode = DualPageMode.AUTO
    private var isLandscape: Boolean = false
```

- [ ] **Step 3: 新增 `applyDualPagePreferences()`，`setPreferences()`/`attachNavigator()` 呼叫它**

在 `setPreferences()` 函式之後新增：

```kotlin
    /**
     * 解析 [preferences] 中的 dualPageMode／isLandscape 欄位並更新對應欄位；
     * 任一欄位實際改變時使 FXL 縮放快取失效——單頁/雙頁切換或裝置旋轉時，
     * container 可用寬度的計算基準（見 applyFxlFitScale()）都會改變，沿用舊的
     * 快取值會算錯縮放比例。
     */
    private fun applyDualPagePreferences(preferences: Map<String, Any?>) {
        var changed = false
        (preferences["dualPageMode"] as? String)?.let {
            val newValue = DualPageMode.fromWireValue(it)
            if (newValue != dualPageMode) changed = true
            dualPageMode = newValue
        }
        (preferences["isLandscape"] as? Boolean)?.let {
            if (it != isLandscape) changed = true
            isLandscape = it
        }
        if (changed) cachedFxlFitScale = null
    }
```

找到現有 `setPreferences()`：

```kotlin
    private fun setPreferences(preferences: Map<String, Any?>?) {
        if (preferences == null) return
        currentPreferences = currentPreferences.plus(buildPreferencesFromMap(preferences))
        navigatorFragment?.submitPreferences(currentPreferences)
        applyFontWeightCascade()
    }
```

改為（`applyDualPagePreferences` 必須在 `buildPreferencesFromMap` 之前呼叫，因為後者會讀取剛更新的 `dualPageMode`/`isLandscape` 欄位來計算 `spread`）：

```kotlin
    private fun setPreferences(preferences: Map<String, Any?>?) {
        if (preferences == null) return
        applyDualPagePreferences(preferences)
        currentPreferences = currentPreferences.plus(buildPreferencesFromMap(preferences))
        navigatorFragment?.submitPreferences(currentPreferences)
        applyFontWeightCascade()
    }
```

找到 `attachNavigator()` 內：

```kotlin
            if (initialPreferences != null && initialPreferences.isNotEmpty()) {
                currentPreferences = currentPreferences.plus(buildPreferencesFromMap(initialPreferences))
                navigatorFragment?.submitPreferences(currentPreferences)
            }
```

改為：

```kotlin
            if (initialPreferences != null && initialPreferences.isNotEmpty()) {
                applyDualPagePreferences(initialPreferences)
                currentPreferences = currentPreferences.plus(buildPreferencesFromMap(initialPreferences))
                navigatorFragment?.submitPreferences(currentPreferences)
            }
```

- [ ] **Step 4: `buildPreferencesFromMap()` 新增 `spread`**

找到現有：

```kotlin
    private fun buildPreferencesFromMap(map: Map<String, Any?>): EpubPreferences {
        return EpubPreferences(
            verticalText = (map["writingMode"] as? String)?.let { it == "vertical" },
            scroll = (map["pageTurnMode"] as? String)?.let { it == "scroll" },
            fontFamily = (map["fontFamily"] as? String)?.let { FontFamily(it) },
            fontSize = (map["fontSize"] as? Number)?.toDouble(),
            fontWeight = (map["fontWeight"] as? Number)?.toDouble(),
            lineHeight = (map["lineHeight"] as? Number)?.toDouble(),
            paragraphSpacing = (map["paragraphSpacing"] as? Number)?.toDouble(),
            pageMargins = (map["pageMargins"] as? Number)?.toDouble(),
            textAlign = (map["textAlign"] as? String)?.let { textAlignFromName(it) },
            publisherStyles = map["publisherStyles"] as? Boolean,
        )
    }
```

改為：

```kotlin
    private fun buildPreferencesFromMap(map: Map<String, Any?>): EpubPreferences {
        return EpubPreferences(
            verticalText = (map["writingMode"] as? String)?.let { it == "vertical" },
            scroll = (map["pageTurnMode"] as? String)?.let { it == "scroll" },
            fontFamily = (map["fontFamily"] as? String)?.let { FontFamily(it) },
            fontSize = (map["fontSize"] as? Number)?.toDouble(),
            fontWeight = (map["fontWeight"] as? Number)?.toDouble(),
            lineHeight = (map["lineHeight"] as? Number)?.toDouble(),
            paragraphSpacing = (map["paragraphSpacing"] as? Number)?.toDouble(),
            pageMargins = (map["pageMargins"] as? Number)?.toDouble(),
            textAlign = (map["textAlign"] as? String)?.let { textAlignFromName(it) },
            publisherStyles = map["publisherStyles"] as? Boolean,
            spread = if (isDualPageEnabled(dualPageMode, isLandscape)) Spread.ALWAYS else Spread.NEVER,
        )
    }
```

- [ ] **Step 5: 撰寫 JVM 單元測試**

建立 `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/EpubReaderViewDualPageTest.kt`：

```kotlin
package cc.ugotit.elinkbook

import cc.ugotit.elinkbook.EpubReaderView.DualPageMode
import org.junit.Assert.assertEquals
import org.junit.Test

class EpubReaderViewDualPageTest {
    @Test
    fun `isDualPageEnabled always 一律生效`() {
        assertEquals(true, EpubReaderView.isDualPageEnabled(DualPageMode.ALWAYS, isLandscape = false))
    }

    @Test
    fun `isDualPageEnabled auto 僅橫向生效`() {
        assertEquals(true, EpubReaderView.isDualPageEnabled(DualPageMode.AUTO, isLandscape = true))
        assertEquals(false, EpubReaderView.isDualPageEnabled(DualPageMode.AUTO, isLandscape = false))
    }

    @Test
    fun `isDualPageEnabled never 一律不生效`() {
        assertEquals(false, EpubReaderView.isDualPageEnabled(DualPageMode.NEVER, isLandscape = true))
    }

    @Test
    fun `DualPageMode fromWireValue 對應正確，未知值一律視為 auto`() {
        assertEquals(DualPageMode.ALWAYS, DualPageMode.fromWireValue("always"))
        assertEquals(DualPageMode.NEVER, DualPageMode.fromWireValue("never"))
        assertEquals(DualPageMode.AUTO, DualPageMode.fromWireValue("auto"))
        assertEquals(DualPageMode.AUTO, DualPageMode.fromWireValue(null))
        assertEquals(DualPageMode.AUTO, DualPageMode.fromWireValue("garbage"))
    }
}
```

- [ ] **Step 6: 編譯 + 執行 JVM 測試**

```bash
cd app/android
./gradlew :app:compileDebugKotlin
./gradlew :app:testDebugUnitTest --tests "cc.ugotit.elinkbook.EpubReaderViewDualPageTest"
```

Expected: 兩者皆 `BUILD SUCCESSFUL`，4 個測試全數通過。

- [ ] **Step 7: 既有回歸測試**

```bash
cd ../../app
flutter analyze
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
```

Expected: `flutter analyze` 顯示 `No issues found!`；既有 9 個 `integration_test` 全數通過（單頁模式下 `dualPageMode` 預設為 `AUTO`、`isLandscape` 預設為 `false`，`isDualPageEnabled` 結果為 `false`，`spread` 恆為 `NEVER`，等同改動前的預設行為）。

- [ ] **Step 8: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt \
        app/android/app/src/test/kotlin/cc/ugotit/elinkbook/EpubReaderViewDualPageTest.kt
git commit -m "feat(epic-16): EpubReaderView 依 dualPageMode/isLandscape 切換 Readium spread"
```

---

### Task 2: `applyFxlFitScale()` 雙頁縮放/置中演算法

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`

**Interfaces:**
- Consumes：Task 1 的 `dualPageMode`/`isLandscape`/`isDualPageEnabled`。
- Produces：無新增對外介面，純粹修正既有 `applyFxlFitScale()` 內部演算法。

- [ ] **Step 1: 新增 spread 模式快取鍵欄位**

找到現有：

```kotlin
    private var cachedFxlFitScale: Float? = null
```

改為：

```kotlin
    private var cachedFxlFitScale: Float? = null
    private var cachedFxlFitScaleIsSpread: Boolean? = null
```

- [ ] **Step 2: 重寫 `applyFxlFitScale()` 支援雙 WebView 的可用寬度減半與左右 slot 位移換算**

找到現有 `applyFxlFitScale()` 整個函式：

```kotlin
    private fun applyFxlFitScale() {
        val isFixedLayout = publication?.metadata?.layout == Layout.FIXED
        if (!isFixedLayout) {
            removeFxlLayoutListener()
            return
        }
        if (fxlLayoutListener != null) return
        val listener = ViewTreeObserver.OnGlobalLayoutListener {
            val availableWidth = container.width
            val availableHeight = container.height
            if (availableWidth <= 0 || availableHeight <= 0) return@OnGlobalLayoutListener
            val containerLoc = IntArray(2)
            container.getLocationOnScreen(containerLoc)
            for (webView in findViewsByType<WebView>(container)) {
                val contentWidth = webView.width
                val contentHeight = webView.height
                if (contentWidth <= 0 || contentHeight <= 0) continue
                val fitScale = cachedFxlFitScale ?: EpubFxlScaler.computeFitScale(
                    availableWidth = availableWidth,
                    availableHeight = availableHeight,
                    contentWidth = contentWidth,
                    contentHeight = contentHeight,
                ).also { cachedFxlFitScale = it }

                webView.translationX = 0f
                webView.translationY = 0f
                webView.pivotX = 0f
                webView.pivotY = 0f
                webView.scaleX = fitScale
                webView.scaleY = fitScale
                val webViewLoc = IntArray(2)
                webView.getLocationOnScreen(webViewLoc)
                val currentLeft = (webViewLoc[0] - containerLoc[0]).toFloat()
                val currentTop = (webViewLoc[1] - containerLoc[1]).toFloat()

                val translation = EpubFxlScaler.computeCenteringTranslation(
                    availableWidth = availableWidth,
                    availableHeight = availableHeight,
                    contentWidth = contentWidth,
                    contentHeight = contentHeight,
                    scale = fitScale,
                    currentLeft = currentLeft,
                    currentTop = currentTop,
                )
                webView.translationX = translation.x
                webView.translationY = translation.y
            }
        }
        fxlLayoutListener = listener
        container.viewTreeObserver.addOnGlobalLayoutListener(listener)
    }
```

改為：

```kotlin
    private fun applyFxlFitScale() {
        val isFixedLayout = publication?.metadata?.layout == Layout.FIXED
        if (!isFixedLayout) {
            removeFxlLayoutListener()
            return
        }
        if (fxlLayoutListener != null) return
        val listener = ViewTreeObserver.OnGlobalLayoutListener {
            val allWebViews = findViewsByType<WebView>(container)
            // R2ViewPager 在單頁模式下也會同時保留前後相鄰頁面的 WebView（見本
            // 檔案類別 KDoc「為什麼是『全部』而不是『第一個』」，真機驗證確認
            // 同時存在 3 個 R2BasicWebView 實例，各自的 R2FXLLayout 以左右並排、
            // 由 ViewPager 位移決定哪一個落在可視範圍內）。量測「目前是否為雙頁
            // 並排」之前，先把所有找到的 WebView 的 translationX/Y 歸零——若不
            // 歸零，getLocationOnScreen() 量到的會是「上一輪計算殘留的位移」而非
            // 真正的原始 layout 位置，污染下面的可見性判斷與排序（pivot 固定為
            // (0,0) 時 scale 不影響量測到的左上角座標，只有 translationX/Y 需要
            // 歸零，不需要在這裡連 scale 也重置）。
            allWebViews.forEach {
                it.translationX = 0f
                it.translationY = 0f
            }
            val containerLoc = IntArray(2)
            container.getLocationOnScreen(containerLoc)

            // 只用「找到的 WebView 數量」判斷雙頁狀態會被 R2ViewPager 預載在
            // 螢幕外的相鄰頁面誤導（單頁模式下常態就有 3 個）。改為兩個條件都
            // 成立才視為雙頁並排：(1) 偏好設定本身啟用雙頁（isDualPageEnabled，
            // 排除「單頁模式下巧合抓到 ≥2 個螢幕外 WebView」的誤判），(2) 篩選出
            // 真正落在 container 可視範圍內的 WebView 且數量 ≥ 2（排除「雙頁
            // 偏好生效但目前停在封面頁（page: center），Readium 本身只給 1 個
            // WebView」的情況）。可見性篩選後依 x 座標由小到大排序，用排序後的
            // index 判斷左右 slot，而非數值閾值比較（過渡瞬間的量測誤差可能讓
            // 閾值判斷失準，見審查意見 Important #1）。
            val visibleWebViews = allWebViews.filter { webView ->
                val webViewLoc = IntArray(2)
                webView.getLocationOnScreen(webViewLoc)
                val currentLeft = webViewLoc[0] - containerLoc[0]
                val contentWidth = webView.width
                contentWidth > 0 && currentLeft + contentWidth > 0 && currentLeft < container.width
            }.sortedBy { webView ->
                val webViewLoc = IntArray(2)
                webView.getLocationOnScreen(webViewLoc)
                webViewLoc[0]
            }
            val isDualPageActive = isDualPageEnabled(dualPageMode, isLandscape)
            val isSpread = isDualPageActive && visibleWebViews.size >= 2
            if (cachedFxlFitScaleIsSpread != isSpread) {
                cachedFxlFitScale = null
                cachedFxlFitScaleIsSpread = isSpread
            }
            val availableWidth = if (isSpread) container.width / 2 else container.width
            val availableHeight = container.height
            if (availableWidth <= 0 || availableHeight <= 0) return@OnGlobalLayoutListener

            visibleWebViews.forEachIndexed { index, webView ->
                val contentWidth = webView.width
                val contentHeight = webView.height
                if (contentWidth <= 0 || contentHeight <= 0) return@forEachIndexed
                val fitScale = cachedFxlFitScale ?: EpubFxlScaler.computeFitScale(
                    availableWidth = availableWidth,
                    availableHeight = availableHeight,
                    contentWidth = contentWidth,
                    contentHeight = contentHeight,
                ).also { cachedFxlFitScale = it }

                webView.pivotX = 0f
                webView.pivotY = 0f
                webView.scaleX = fitScale
                webView.scaleY = fitScale
                val webViewLoc = IntArray(2)
                webView.getLocationOnScreen(webViewLoc)
                val currentLeft = (webViewLoc[0] - containerLoc[0]).toFloat()
                val currentTop = (webViewLoc[1] - containerLoc[1]).toFloat()

                // 雙頁模式下，右側 WebView 的置中運算必須在「它自己的半寬 slot」
                // 座標系裡進行，否則 computeCenteringTranslation 會把它往 slot 0
                // （螢幕左半邊）置中。做法：換算前先把 currentLeft 減去 slot 起點
                // （0 或 availableWidth），讓函式誤以為自己是在 slot 內部（座標
                // 原點在 slot 起點）計算——回傳值 translation.x = desiredLeft（相對
                // slot 起點）- 傳入的 currentLeft（已扣掉 slot 起點），展開後等於
                // 「絕對期望位置 - 原始 currentLeft」，本來就已經是可以直接疊加在
                // 原始位置上的正確絕對位移，不能再額外加回 slotOffsetX（那樣會把
                // 右側 WebView 多平移一個 slot 寬度、直接推出可視範圍外）。slot
                // 依排序後的 index 分配（index 0 = 左，1 = 右），不使用數值閾值判斷。
                val slotOffsetX = if (isSpread && index == 1) availableWidth.toFloat() else 0f

                val translation = EpubFxlScaler.computeCenteringTranslation(
                    availableWidth = availableWidth,
                    availableHeight = availableHeight,
                    contentWidth = contentWidth,
                    contentHeight = contentHeight,
                    scale = fitScale,
                    currentLeft = currentLeft - slotOffsetX,
                    currentTop = currentTop,
                )
                webView.translationX = translation.x
                webView.translationY = translation.y
            }
        }
        fxlLayoutListener = listener
        container.viewTreeObserver.addOnGlobalLayoutListener(listener)
    }
```

- [ ] **Step 3: `applyDualPagePreferences()`（Task 1 已建立）一併清除新增的快取鍵**

找到 Task 1 Step 3 建立的 `applyDualPagePreferences()`：

```kotlin
        if (changed) cachedFxlFitScale = null
```

改為：

```kotlin
        if (changed) {
            cachedFxlFitScale = null
            cachedFxlFitScaleIsSpread = null
        }
```

（Task 1 撰寫時 `cachedFxlFitScaleIsSpread` 尚未存在，只清了 `cachedFxlFitScale` 一個欄位；`applyFxlFitScale()` 的 listener 本身雖然會在偵測到 `isSpread` 實際改變時自動清快取，但若清除時機不同步，`cachedFxlFitScale` 已被歸零而 `cachedFxlFitScaleIsSpread` 卻留著過期值，會讓「快取值是否對應目前 spread 狀態」這組不變量在兩個欄位間短暫不一致，留下後續重構的潛在隱患，此處一併清除以維持狀態一致。）

- [ ] **Step 4: `removeFxlLayoutListener()` 一併清除新增的快取鍵**

找到現有：

```kotlin
    private fun removeFxlLayoutListener() {
        fxlLayoutListener?.let { container.viewTreeObserver.removeOnGlobalLayoutListener(it) }
        fxlLayoutListener = null
        cachedFxlFitScale = null
    }
```

改為：

```kotlin
    private fun removeFxlLayoutListener() {
        fxlLayoutListener?.let { container.viewTreeObserver.removeOnGlobalLayoutListener(it) }
        fxlLayoutListener = null
        cachedFxlFitScale = null
        cachedFxlFitScaleIsSpread = null
    }
```

- [ ] **Step 5: 編譯確認**

```bash
cd app/android
./gradlew :app:compileDebugKotlin
```

Expected: `BUILD SUCCESSFUL`。

- [ ] **Step 6: 既有回歸測試**

```bash
cd ../../app
flutter analyze
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
```

Expected: `flutter analyze` 乾淨；既有 9 個 `integration_test` 全數通過（單頁模式下 `isDualPageEnabled(dualPageMode, isLandscape)` 恆為 `false`，`isSpread` 因此恆為 `false`，`availableWidth = container.width`、`slotOffsetX` 恆為 0，與改動前完全等價，不應觀察到任何行為變化；`visibleWebViews` 的可見性篩選對單頁模式下 R2ViewPager 預載的螢幕外相鄰頁面正確排除，不影響目前可見那一頁的縮放計算）。

- [ ] **Step 7: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
git commit -m "fix(epic-16): applyFxlFitScale 支援 Readium 自動產生的雙 WebView 縮放/置中"
```

---

### Task 3: Dart 端 `EpubReaderView` 新增 `dualPageMode`/`isLandscape` 參數

**Files:**
- Modify: `app/lib/reader/epub_reader_view.dart`
- Modify: `app/test/reader/epub_reader_view_test.dart`

**Interfaces:**
- Produces：`EpubReaderView` 新增建構參數 `dualPageMode: DualPageMode`（預設 `DualPageMode.auto`）、`isLandscape: bool`（預設 `false`），供 Task 4 的 `ReaderScreen` 使用。翻頁沿用 Readium 既有原生手勢，本 Task 不新增 `GestureDetector` 或任何 method channel。

- [ ] **Step 1: 新增 import 與建構參數**

在 `app/lib/reader/epub_reader_view.dart` 開頭新增 import：

```dart
import 'dual_page_mode.dart';
```

在 `class EpubReaderView` 欄位宣告新增（比照既有 `writingMode`/`pageTurnMode` 等欄位，緊接在 `publisherStyles` 之後）：

```dart
  final DualPageMode dualPageMode;
  final bool isLandscape;
```

建構子新增（比照 `PdfReaderView` 對這兩個「一律由 `ReaderScreen` 解析為非 null 值」欄位的既有慣例，見 `pdf_reader_view.dart:61-64`）：

```dart
    this.dualPageMode = DualPageMode.auto,
    this.isLandscape = false,
```

- [ ] **Step 2: `_buildPreferencesMap()`／`_preferencesChanged()` 納入新欄位**

找到 `_buildPreferencesMap()` 結尾（`return map;` 之前）新增（比照 `PdfReaderView` 對已解析非 null 值欄位「一律無條件放入 map」的既有慣例，見 `pdf_reader_view.dart:122-128`）：

```dart
    map['dualPageMode'] = widget.dualPageMode.name;
    map['isLandscape'] = widget.isLandscape;
```

找到 `_preferencesChanged()`，在既有 `||` 鏈末端（`widget.publisherStyles != oldWidget.publisherStyles;` 那一行）新增：

```dart
        widget.publisherStyles != oldWidget.publisherStyles ||
        widget.dualPageMode != oldWidget.dualPageMode ||
        widget.isLandscape != oldWidget.isLandscape;
```

- [ ] **Step 3: 新增 widget test**

在 `app/test/reader/epub_reader_view_test.dart` 新增 import：

```dart
import 'package:elinkbook/reader/dual_page_mode.dart';
```

在 `main()` 內既有測試之後新增：

```dart
  testWidgets('dualPageMode/isLandscape 一律出現在 initialPreferences（非 null 慣例）',
      (tester) async {
    final calls = await _pumpEpubReaderView(
      tester,
      const EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.always,
        isLandscape: true,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    final prefs = openBookCall.arguments['initialPreferences'] as Map;
    expect(prefs['dualPageMode'], 'always');
    expect(prefs['isLandscape'], true);
  });

  testWidgets('dualPageMode 變動時 didUpdateWidget 觸發 setPreferences', (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(const MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(const MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.always,
        isLandscape: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(instanceCalls, hasLength(1));
    expect(instanceCalls.single.method, 'setPreferences');
    expect(instanceCalls.single.arguments['dualPageMode'], 'always');
    expect(instanceCalls.single.arguments['isLandscape'], true);
  });
```

- [ ] **Step 4: 執行測試**

```bash
cd app
flutter test test/reader/epub_reader_view_test.dart
flutter analyze
```

Expected: 6 個測試（既有 4 個 + 新增 2 個）全數通過；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 5: Commit**

```bash
git add app/lib/reader/epub_reader_view.dart app/test/reader/epub_reader_view_test.dart
git commit -m "feat(epic-16): EpubReaderView(Dart) 新增 dualPageMode/isLandscape 參數"
```

---

### Task 4: `ReaderScreen` 懸浮設定按鈕 + 新建 `FxlSettingsSheet`

**Files:**
- Create: `app/lib/screens/fxl_settings_sheet.dart`
- Create: `app/test/screens/fxl_settings_sheet_test.dart`
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 3 的 `EpubReaderView.dualPageMode`/`isLandscape`；既有 `ResolvedPreferences.dualPageMode`（Issue 3 已建立，non-nullable）。
- Produces：`FxlSettingsSheet({required BookReaderPrefs prefs, required ValueChanged<BookReaderPrefs> onChanged})`（Epic 內無其他消費者）。

- [ ] **Step 1: 建立 `FxlSettingsSheet`**

建立 `app/lib/screens/fxl_settings_sheet.dart`：

```dart
import 'package:flutter/material.dart';

import '../reader/book_reader_prefs.dart';
import '../reader/dual_page_mode.dart';

/// EPUB 固定版面（FXL 漫畫）專屬的精簡版設定 Bottom Sheet（見
/// docs/epics/epic-16-dual-page/spec.md「模組」段落）：只提供「雙頁模式」
/// 三態切換，不與 PdfSettingsSheet／ReaderSettingsSheet 共用元件（固定版面
/// 沒有字型/裁切/濾鏡等其餘設定）。為未來 FR-42（全螢幕顯示開關）預留擴充
/// 空間，本 issue 不實作該功能本身。
class FxlSettingsSheet extends StatefulWidget {
  final BookReaderPrefs prefs;
  final ValueChanged<BookReaderPrefs> onChanged;

  const FxlSettingsSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
  });

  @override
  State<FxlSettingsSheet> createState() => _FxlSettingsSheetState();
}

class _FxlSettingsSheetState extends State<FxlSettingsSheet> {
  late DualPageMode _dualPageMode;

  @override
  void initState() {
    super.initState();
    _dualPageMode = widget.prefs.dualPageMode ?? DualPageMode.auto;
  }

  void _notifyChanged() {
    widget.onChanged(widget.prefs.copyWith(dualPageMode: _dualPageMode));
  }

  @override
  Widget build(BuildContext context) {
    const dualPageOptions = [
      (DualPageMode.auto, 'auto', Icons.stay_current_landscape, '自動（橫向雙頁）'),
      (DualPageMode.always, 'always', Icons.view_column, '永遠雙頁'),
      (DualPageMode.never, 'never', Icons.crop_portrait, '永遠單頁'),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('⚙️ 漫畫版面設定',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('雙頁模式'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: dualPageOptions.map((option) {
                final (mode, keySuffix, icon, tooltip) = option;
                final selected = _dualPageMode == mode;
                return IconButton(
                  key: Key('fxl_settings_dual_page_mode_$keySuffix'),
                  icon: Icon(icon),
                  tooltip: tooltip,
                  color:
                      selected ? Theme.of(context).colorScheme.primary : null,
                  onPressed: () => setState(() {
                    _dualPageMode = mode;
                    _notifyChanged();
                  }),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: `FxlSettingsSheet` widget test**

建立 `app/test/screens/fxl_settings_sheet_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/screens/fxl_settings_sheet.dart';

void main() {
  testWidgets('能正常 pump 起，顯示三個雙頁模式選項', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FxlSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.byKey(const Key('fxl_settings_dual_page_mode_auto')), findsOneWidget);
    expect(find.byKey(const Key('fxl_settings_dual_page_mode_always')), findsOneWidget);
    expect(find.byKey(const Key('fxl_settings_dual_page_mode_never')), findsOneWidget);
  });

  testWidgets('點擊「永遠雙頁」觸發 onChanged', (tester) async {
    BookReaderPrefs? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: FxlSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (prefs) => changed = prefs,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('fxl_settings_dual_page_mode_always')));
    await tester.pump();

    expect(changed?.dualPageMode, DualPageMode.always);
  });

  testWidgets('已有持久化 dualPageMode 時，初始狀態正確反映', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FxlSettingsSheet(
          prefs: const BookReaderPrefs(dualPageMode: DualPageMode.never),
          onChanged: (_) {},
        ),
      ),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const Key('fxl_settings_dual_page_mode_never')),
    );
    expect(button.color, isNotNull, reason: '目前選中的選項應以主題色標示');
  });
}
```

- [ ] **Step 3: 執行 `FxlSettingsSheet` 測試**

```bash
cd app
flutter test test/screens/fxl_settings_sheet_test.dart
```

Expected: 3 個測試全數通過。

- [ ] **Step 4: `ReaderScreen` 新增懸浮設定按鈕 + 開啟 `FxlSettingsSheet`**

在 `app/lib/screens/reader_screen.dart` 新增 import：

```dart
import 'fxl_settings_sheet.dart';
```

新增開啟 Sheet 的方法（比照既有 `_openPdfSettings()`，加在其後）：

```dart
  void _openFxlSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FxlSettingsSheet(
        prefs: _prefs,
        onChanged: _handlePrefsChanged,
      ),
    );
  }
```

找到 `_buildBody()` 內固定版面返回按鈕的 `Positioned`（`Key('reader_fixed_layout_back_button')` 那一段），在同一個 `Stack` 的 `children` 列表內、緊接其後新增對稱的右上角按鈕：

```dart
        if (_isFixedLayout)
          Positioned(
            top: 16,
            right: 16,
            child: ClipOval(
              child: Container(
                color: Colors.black54,
                child: IconButton(
                  key: const Key('reader_fixed_layout_settings_button'),
                  icon: const Icon(Icons.settings, color: Colors.white),
                  tooltip: '版面設定',
                  onPressed: _openFxlSettings,
                ),
              ),
            ),
          ),
```

找到 `_buildNativeView()` 內 `EpubReaderView(...)` 建構呼叫，在其既有參數列末（`publisherStyles: resolved.publisherStyles,` 之後）新增：

```dart
          dualPageMode: resolved.dualPageMode,
          isLandscape: isLandscape,
```

- [ ] **Step 5: `ReaderScreen` widget test**

在 `app/test/screens/reader_screen_test.dart` 新增 import：

```dart
import 'package:elinkbook/screens/fxl_settings_sheet.dart';
```

在既有 EPUB 相關測試之後新增：

```dart
  testWidgets(
      'EPUB 固定版面開書後，畫面右上角出現懸浮設定按鈕，點擊能開啟 FxlSettingsSheet',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 純 flutter test 環境沒有真實裝置能觸發原生端 onLayoutResolved，直接呼叫
    // EpubReaderView 目前已知的 onLayoutResolved callback 模擬原生端回報，比照
    // 本檔案既有測試對「無法在此層級驅動原生渲染」的既定限制處理方式。
    final view = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    view.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_fixed_layout_settings_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader_fixed_layout_settings_button')));
    await tester.pumpAndSettle();

    expect(find.byType(FxlSettingsSheet), findsOneWidget);
  });
```

- [ ] **Step 6: 執行測試**

```bash
cd app
flutter test test/screens/reader_screen_test.dart
flutter analyze
```

Expected: 全數通過；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/fxl_settings_sheet.dart app/test/screens/fxl_settings_sheet_test.dart \
        app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-16): 新增 FxlSettingsSheet 與 ReaderScreen 固定版面設定按鈕"
```

---

### Task 5: 真機整合測試 + spec.md／issues.md 收尾更新

**Files:**
- Create: `app/integration_test/epub_dual_page_test.dart`
- Modify: `docs/epics/epic-16-dual-page/spec.md`
- Modify: `docs/epics/epic-16-dual-page/issues.md`

**Interfaces:** 無（本 Task 為驗收與文件收尾）。

- [ ] **Step 1: 撰寫真機整合測試**

建立 `app/integration_test/epub_dual_page_test.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/epub_reader_view.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('固定版面 EPUB 於 dualPageMode=always 下開書不崩潰',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_fixed_layout.epub', 'sample_dual_page.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: samplePath,
          dualPageMode: DualPageMode.always,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');
  });

  testWidgets('dualPageMode=never 時固定版面 EPUB 維持單頁顯示', (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_fixed_layout.epub', 'sample_single_page.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderView(
          filePath: samplePath,
          dualPageMode: DualPageMode.never,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');
  });
}
```

- [ ] **Step 2: 用真實漫畫素材人工視覺 QA（FR-41 像素級確認，無法自動化）**

把 `tmp/一弦定音！(06).epub` 暫時複製到裝置可存取路徑，`flutter run` 在橫向、`dualPageMode = auto` 下開啟並翻頁至非封面內頁，肉眼確認：
- 翻到非封面內頁後，左右兩頁確實並排顯示（比對 `reviews/spike-readium-spread-webview-count.md` 已記錄的 `x=0`/`x=1200` 佈局）
- 頁間無可見間距（FR-41 核心驗收點）
- 封面頁（page 0）維持單頁顯示
- 連續翻頁多次無崩潰、縮放/置中無明顯跳動或裁切
- 裝置橫向/直向來回旋轉，`dualPageMode = auto` 下正確在單頁/雙頁間切換，縮放比例正確重算（驗證 Task 2 新增的 `cachedFxlFitScaleIsSpread` 快取失效邏輯）

若發現任何落差，記錄為 Issue 7 的後續追蹤項，不阻塞本 Task 完成。

- [ ] **Step 3: 執行整合測試**

```bash
cd app
flutter test integration_test/epub_dual_page_test.dart -d <device-id>
```

Expected: 2 個測試全數通過。

- [ ] **Step 4: 執行全專案回歸**

```bash
flutter analyze
flutter test
cd android && ./gradlew :app:testDebugUnitTest && cd ..
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
flutter test integration_test/reader_screen_test.dart -d <device-id>
```

Expected: 全數通過，無回歸。

- [ ] **Step 5: 更新 `spec.md`**

在 `docs/epics/epic-16-dual-page/spec.md`「待驗證風險與收斂關卡」第 1 項（`Spread.ALWAYS` 是否無間距）與第 4 項（`applyFxlFitScale()` 雙頁下是否真的不再重疊）的既有 Issue 1 驗證結論之後，各自加入一段：

```markdown
> **補充驗證（2026-07-13，`reviews/spike-readium-spread-webview-count.md`）：先前結論已被推翻。** Issue 1 原始驗證只測試到封面頁（page: center，Readium 規範下本就只會是單頁），翻到非封面配對頁面後，Readium 確實會自動建立 2 個無縫並排的 WebView（`x=0`/`x=1200`，container 寬度 2400）。原「需自行管理雙 WebView」的退回方案已撤銷，`plans/plan-issue-6.md` 改回簡化路線：原生端只需切換 `spread` 並修正 `applyFxlFitScale()` 偵測到 2 個 WebView 時的縮放/置中運算。
```

- [ ] **Step 6: 更新 `issues.md` Issue 6 狀態**

在 `docs/epics/epic-16-dual-page/issues.md` Issue 6 的 `**依賴：**` 之前加入 `**Status:** ✅ 已完成`，並附簡短總結，註明依 `spike-readium-spread-webview-count.md` 補充驗證結果改回「Readium 內建 spread + `applyFxlFitScale()` 修正」路線（而非先前一度規劃的自建雙 Fragment 方案）、Task 1-5 完成情形、測試通過數量、真機人工視覺 QA 結論。

- [ ] **Step 7: Commit**

```bash
git add app/integration_test/epub_dual_page_test.dart docs/epics/epic-16-dual-page/spec.md \
        docs/epics/epic-16-dual-page/issues.md
git commit -m "test(epic-16): Issue 6 真機整合測試 + spec.md/issues.md 收尾更新"
```

---

## Self-Review（撰寫計劃時的自我檢查）

**Spec 覆蓋度**：issues.md Issue 6 的 4 項描述（`EpubReaderView` 新參數／`EpubReaderView.kt` spread 邏輯／`ReaderScreen` 懸浮按鈕／`FxlSettingsSheet`）與單元測試要求，逐一對應 Task 3（Dart 新參數）、Task 1-2（Kotlin spread/縮放邏輯）、Task 4（Sheet/ReaderScreen）、Task 5（`integration_test`）。「已知測試限制」（Readium spread 排版結果無法 `flutter test` 驗證）對應 Task 5 的真機測試與人工視覺 QA。

**占位符掃描**：全文無 TBD/待補/「同 Task N」等字樣，每個 Step 皆含可直接使用的完整程式碼。

**型別一致性**：`DualPageMode`（Kotlin，`EpubReaderView` 巢狀列舉）與 Dart `DualPageMode`（既有 `app/lib/reader/dual_page_mode.dart`）透過 `.name` 字串橋接，與既有 `PdfReaderView`/`PdfReaderView.kt` 的橋接模式一致；`isDualPageEnabled`／`applyDualPagePreferences`／`cachedFxlFitScaleIsSpread` 在 Task 1-2 引入後的命名，後續 Task 沒有再引用這些內部符號（Task 3-5 皆為 Dart/文件層級），無跨 Task 命名不一致風險。

## 審查修正紀錄（`tmp/epic-16/reviews/plan-issue-6-review.md`）

依審查報告修正 Task 2：

- **Critical（已修正）**：原 `isSpread = webViews.size >= 2` 未考慮 R2ViewPager 在單頁模式下本就同時保留前後相鄰頁面（真機驗證確認同時存在 3 個 WebView，見本檔案類別 KDoc「為什麼是『全部』而不是『第一個』」），會在單頁模式下把畫面誤縮成半寬靠左顯示。已改為「`isDualPageEnabled(dualPageMode, isLandscape)` 且螢幕可視範圍內的 WebView 數量 ≥ 2」雙重判定，並加入可見性篩選（排除螢幕外的預載 WebView）。
- **Important #1（已修正）**：原用 `currentLeft >= availableWidth` 數值閾值判斷左右 slot，過渡瞬間的量測誤差可能誤判。已改為先篩選可見 WebView、依 x 座標排序，用排序後的 index（0=左、1=右）分配 slot，不使用數值閾值。
- **Important #2（已修正）**：`applyDualPagePreferences()`（Task 1）原本只清 `cachedFxlFitScale`，未同步清 `cachedFxlFitScaleIsSpread`，會讓「快取值是否對應目前 spread 狀態」這組不變量短暫不一致。已在 Task 2 新增 Step 3 補上同步清除。
- **Minor #1（隨 Critical 修正一併解決）**：可見性篩選後只對篩選出的 WebView 做縮放/置中運算，不再對螢幕外的預載 WebView 做多餘計算。
- **額外修正（審查報告未提及，驗證程式碼時發現）**：審查建議的程式碼在篩選/排序階段量測 `getLocationOnScreen()` 時，尚未歸零 `translationX`/`translationY`——若上一輪計算已對某個 WebView 套用過位移，量到的會是「上一輪殘留的位移後座標」而非原始 layout 位置，污染本輪的可見性判斷與排序。已在篩選/排序之前，對所有找到的 WebView（含螢幕外的）先歸零 `translationX`/`translationY`（`pivotX`/`pivotY` 恆為 `(0,0)` 時 `scale` 不影響量測到的左上角座標，不需要在這裡連 scale 也重置）。

## Bugfix 紀錄（2026-07-14，真機人工視覺 QA 發現）

依本計劃實作並合併後，人類在真機上實際開啟真實漫畫素材測試，回報：翻頁至非封面內頁、滑動結束套用 fit 縮放後，**右側 WebView 內容消失（變成空白）**；封面單頁一開始也是空白，兩者回報為同一根因。

依 `superpowers:systematic-debugging` 完整跑過 Phase 1-4：因真機環境本身在本次除錯過程中出現螢幕休眠／系統 UI 焦點異常等問題，無法即時取得新的真機日誌佐證，改以嚴謹手動代入數值逐步推導 `applyFxlFitScale()` 的座標運算，確認根因並以最小改動修正：

**根因**：Task 2 的 `webView.translationX = translation.x + slotOffsetX` 重複疊加了 `slotOffsetX`。`EpubFxlScaler.computeCenteringTranslation()` 收到的 `currentLeft` 參數已經預先扣掉 `slotOffsetX`（讓函式誤以為自己是在 slot 內部座標系計算），其回傳的 `translation.x` 展開後已經等於「絕對期望位置 - 原始 currentLeft」——本身就是可以直接疊加在原始位置上的正確絕對位移。呼叫端後續再把 `slotOffsetX` 加回去，等於把右側 WebView 多平移了一個 slot 寬度（例如 container 寬度 2400、slot 寬度 1200 時，右側 WebView 會被多推移 1200px，直接推出螢幕右緣之外），因此翻到非封面內頁後右側內容消失；索引 0（左側）因為 `slotOffsetX` 恆為 0，不受影響，此路徑本身沒有 bug——這與人類回報「左側正常、只有右側消失」的現象完全吻合。封面頁的空白現象則是同一個計算路徑在 `isSpread` 被（螢幕外預載 WebView）短暫誤判為 `true` 時，同樣的多餘位移邏輯造成。

**修正**：`webView.translationX = translation.x + slotOffsetX` 改為 `webView.translationX = translation.x`（移除多餘的 `+ slotOffsetX`）。已在 `.worktrees/epic-16-issue-6` 套用，`./gradlew :app:compileDebugKotlin`／`:app:testDebugUnitTest`／`flutter analyze` 皆通過。

**人類真機複驗（2026-07-14）：通過。** 封面頁正常顯示、翻頁至內頁後左右兩頁正常顯示且無縫並排，FR-41 核心驗收點確認通過。

**已記錄的後續追蹤項（不阻塞本 issue 完成，留待後續優化/新 issue）：**
1. 每次換頁時會有縮放動作（fit 重新計算/套用的視覺跳動）影響閱讀體驗，需要後續排查優化。
2. 未來考慮讓 PDF／EPUB 漫畫在橫向雙頁模式（甚至單頁模式）下改為全版面沉浸顯示（隱藏系統狀態列與導覽列），對應 `FxlSettingsSheet` 已預留但未實作的 FR-42 全螢幕開關 UI 擴充空間。

## Execution Handoff

Plan complete and saved to `docs/epics/epic-16-dual-page/plans/plan-issue-6.md`（已取代先前「自建雙 Fragment」版本）。兩種執行方式：

1. **Subagent-Driven（推薦）**——每個 Task 交給一個全新 subagent 執行，Task 之間逐一審查，快速迭代。
2. **Inline Execution**——在本次會談中依 Task 順序批次執行，設檢查點逐一確認。

要採用哪一種方式？
