# Epic 16 Issue 8：EpubReaderView.kt FXL 縮放邏輯抽離為 EpubFxlScaler 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `EpubReaderView.kt` 內與 `WebView`/`ViewTreeObserver` 等 Android View 型別無關的固定版面（FXL）縮放**數值計算**邏輯——縮放係數計算（`computeFitScale`）、置中位移計算（`computeCenteringTranslation`）——抽離成獨立 pure-Kotlin 物件 `EpubFxlScaler`，讓這兩塊核心計算可在純 JVM 環境（`app/src/test`）直接單元測試，不需要真機/模擬器。

**Architecture:** 新建 `EpubFxlScaler`（Kotlin `object`，位於與 `EpubReaderView` 相同套件 `cc.ugotit.elinkbook`），比照 `epic-4-pdf-enhance` Issue 8 已驗證過的 `PdfImageProcessor` 抽離模式：只抽出「輸入純數值、輸出純數值」的計算部分，所有需要真實 Android View 環境的部分（`WebView.width`/`height` 量測、`getLocationOnScreen()`、`ViewTreeObserver.OnGlobalLayoutListener` 監聽、`scaleX`/`scaleY`/`translationX`/`translationY`/`pivotX`/`pivotY` 賦值、`cachedFxlFitScale` 這個綁定單一 `EpubReaderView` 實例生命週期的快取狀態）全部留在 `EpubReaderView.kt`，不搬移。這是抽離重構，不是新功能——抽離前後的計算公式必須逐行等價，任何既有視覺效果（縮放比例、置中位置）都不能改變。

**Tech Stack:** Kotlin（Android 原生端）、JUnit 4（`app/android/app/build.gradle.kts` 已由 `epic-4-pdf-enhance` Issue 8 加入 `testImplementation("junit:junit:4.13.2")`，本計劃不需重複新增）、Gradle（`app/android` 模組既有 AGP + Kotlin plugin 設定）。

## Global Constraints

- 這是抽離重構，不是新功能：`EpubFxlScaler` 內的兩個計算函式（`computeFitScale`／`computeCenteringTranslation`）必須與 `EpubReaderView.kt` 現有 `applyFxlFitScale()` 內對應的算式逐行等價——不得在搬移過程中「順手」調整公式、常數或行為，即使發現看起來可以改進的地方（例如四捨五入方式、`coerceAtMost` 的邊界處理）。
- **抽離範圍嚴格限定於純數值計算**：`WebView` 量測（`.width`/`.height`）、`getLocationOnScreen()`、`ViewTreeObserver.OnGlobalLayoutListener` 的註冊/移除、`scaleX`/`scaleY`/`translationX`/`translationY`/`pivotX`/`pivotY` 這些 View 屬性賦值，以及 `cachedFxlFitScale`（綁定單一 `EpubReaderView` 實例生命週期、需要在 `removeFxlLayoutListener()` 時清空）這個實例狀態，皆維持留在 `EpubReaderView.kt`，**不**搬進 `EpubFxlScaler`——`EpubFxlScaler` 設計為無狀態（`object`，不持有任何 `var`），呼叫端每次需要時把當下讀到的數值傳進去，而不是讓 `EpubFxlScaler` 自己記憶跨呼叫的快取。
- **這是一次刻意提前執行的 Speculative 重構**：`docs/epics.md` 對應 Backlog 列與 `issues.md` Issue 6 原描述皆記錄此抽離原本設計為「Issue 6（EPUB FXL 雙頁）落地、且 `applyFxlFitScale()` 屆時判斷已過度龐雜後才視情況執行」的順序（YAGNI）。本計劃是人類明確決定提前於 Issue 6 之前執行，不等待該判斷時機。因此本計劃執行完成後，**`issues.md` Issue 6 的「就地實作，不預先抽離」描述已不再適用**，Issue 6 未來新增雙頁縮放邏輯時應改為在 `EpubFxlScaler` 內擴充純函式，而非退回在 `EpubReaderView.kt` 就地擴充（`issues.md` Issue 8 已記錄此銜接方向，Issue 6 實作者開工前需重新確認 `EpubFxlScaler.kt` 當時的函式簽章）。
- 新增的 JVM 單元測試一律針對純數值輸入/輸出的函式（`computeFitScale`／`computeCenteringTranslation`），不引入 Robolectric 或任何 Android 框架模擬依賴——`EpubReaderView.kt` 內實際呼叫 `WebView`/`ViewTreeObserver` 的整合邏輯本身不新增自動化測試，其正確性由 Task 3 的既有真機 `integration_test` 回歸把關。
- 測試指令慣例：原生 JVM 單元測試用 Gradle `./gradlew testDebugUnitTest`（於 `app/android` 目錄執行，`gradlew`/`gradlew.bat` 為 `.gitignore` 排除產物，若尚不存在先於 `app/` 目錄執行一次 `flutter build apk --debug` 讓 Flutter 產生）；Dart 測試用 `flutter test`（於 `app/` 目錄執行）。
- `minSdk = 24`（見專案 `CLAUDE.md`）：本計劃不涉及 API level 相關邏輯變動，`computeFitScale`/`computeCenteringTranslation` 皆為純 `Float`/`Int` 運算，不引用任何有 API 版本門檻的 Android API。

---

## File Structure

- **Create** `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubFxlScaler.kt`：新的 pure-Kotlin FXL 縮放計算模組，見上方 Architecture。
- **Create** `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/EpubFxlScalerTest.kt`：針對 `EpubFxlScaler` 的 JVM 單元測試（不需要真機/模擬器）。
- **Modify** `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`：`applyFxlFitScale()`（第 317-366 行）內部改呼叫 `EpubFxlScaler.computeFitScale()`／`EpubFxlScaler.computeCenteringTranslation()`，取代原本內嵌的算式；`cachedFxlFitScale`（第 315 行）等狀態欄位維持不動。

---

### Task 1：`computeFitScale()` 縮放係數計算抽離

**Files:**
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubFxlScaler.kt`
- Create: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/EpubFxlScalerTest.kt`

**Interfaces:**
- Produces：`EpubFxlScaler`（`object`，套件 `cc.ugotit.elinkbook`）：
  - `fun computeFitScale(availableWidth: Int, availableHeight: Int, contentWidth: Int, contentHeight: Int): Float`——供 Task 3 的 `EpubReaderView.kt` 呼叫端使用；Task 2 會在同一個檔案內繼續新增 `computeCenteringTranslation`。

- [ ] **Step 1：寫失敗測試**

建立 `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/EpubFxlScalerTest.kt`（新目錄，與 `epic-4-pdf-enhance` Issue 8 建立的 `PdfImageProcessorTest.kt` 同一層級）：

```kotlin
package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Test

class EpubFxlScalerTest {

    // ---- computeFitScale ----

    @Test
    fun `高度為縮放瓶頸時，取較小的高度縮放比`() {
        // available 1000x1600、content 800x1600：寬度比 1000/800=1.25，
        // 高度比 1600/1600=1.0，取較小值 1.0（本例高度比本身已是瓶頸）。
        val scale = EpubFxlScaler.computeFitScale(
            availableWidth = 1000,
            availableHeight = 1600,
            contentWidth = 800,
            contentHeight = 1600,
        )

        assertEquals(1.0f, scale, 1e-4f)
    }

    @Test
    fun `寬度為縮放瓶頸時，取較小的寬度縮放比`() {
        // available 800x2000、content 1600x2000：寬度比 800/1600=0.5，
        // 高度比 2000/2000=1.0，取較小值 0.5（寬度是瓶頸）。
        val scale = EpubFxlScaler.computeFitScale(
            availableWidth = 800,
            availableHeight = 2000,
            contentWidth = 1600,
            contentHeight = 2000,
        )

        assertEquals(0.5f, scale, 1e-4f)
    }

    @Test
    fun `內容小於容器時不放大，縮放比被 coerceAtMost 夾在 1`() {
        // available 2000x2000、content 1000x1000：兩軸比例皆為 2.0，
        // 若不夾限會放大成 2 倍，但 FXL 縮放語意是「只縮小、不放大」。
        val scale = EpubFxlScaler.computeFitScale(
            availableWidth = 2000,
            availableHeight = 2000,
            contentWidth = 1000,
            contentHeight = 1000,
        )

        assertEquals(1.0f, scale, 1e-4f)
    }

    @Test
    fun `寬高比例一放大一縮小時，仍取較小值（縮小方向勝出）`() {
        // available 1000x1000、content 500x2000：寬度比 1000/500=2.0（若單看
        // 這一軸會放大），高度比 1000/2000=0.5（這一軸需要縮小）。取較小值
        // 0.5，確保高度方向不會溢出容器，即使寬度方向原本還有放大空間。
        val scale = EpubFxlScaler.computeFitScale(
            availableWidth = 1000,
            availableHeight = 1000,
            contentWidth = 500,
            contentHeight = 2000,
        )

        assertEquals(0.5f, scale, 1e-4f)
    }
}
```

- [ ] **Step 2：執行測試確認失敗（編譯錯誤，`EpubFxlScaler` 尚不存在）**

於 `app/android` 目錄執行：

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.EpubFxlScalerTest"
```

（若 `./gradlew` 不存在：先於 `app/` 目錄執行一次 `flutter build apk --debug`，讓 Flutter 產生 `app/android/gradlew`／`gradlew.bat`，再重新執行上述指令。）

Expected：編譯失敗，錯誤訊息包含 `unresolved reference: EpubFxlScaler`。

- [ ] **Step 3：實作 EpubFxlScaler.kt（本步驟只含 computeFitScale）**

建立 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubFxlScaler.kt`：

```kotlin
package cc.ugotit.elinkbook

/**
 * EpubReaderView 用到的固定版面（FXL）縮放數值計算邏輯：從 EpubReaderView.kt
 * 抽離而成的 pure-Kotlin 模組（見 docs/epics.md「EpubReaderView.kt FXL 縮放邏輯
 * 抽離為 EpubFxlScaler」列、docs/epics/epic-16-dual-page/plans/plan-issue-8.md）：
 * 不依賴 WebView、ViewTreeObserver 或任何 Android View 型別，只接受量測完成後的
 * 純數值輸入/輸出，可在純 JVM 單元測試（app/src/test）直接以固定數值驗證，不需要
 * 真機/模擬器即可執行。刻意設計為無狀態（object，不持有任何 var）——跨頁快取
 * （cachedFxlFitScale）是綁定單一 EpubReaderView 實例生命週期的狀態，留在
 * EpubReaderView.kt 內，不搬進此模組。
 *
 * 【給 Epic 16 Issue 6（EPUB FXL 雙頁）實作者的提示】依本檔案 plan-issue-8.md
 * 的 Global Constraints，雙頁模式的縮放邏輯應在此模組內擴充，而非退回在
 * EpubReaderView.kt 就地實作。雙頁（spread）生效時，`computeFitScale` 目前接受
 * 的 `availableWidth` 語意會不再等於「單一 WebView 可用的寬度」——每個 WebView
 * 只佔可視寬度的一半，且左右兩頁併排時通常需要扣除中縫（gap）寬度。實作時可考慮
 * 新增一個明確接受「每頁可用寬度」（呼叫端已算好 `(containerWidth - gap) / 2`
 * 後再傳入）的多載或新函式，讓 `computeFitScale`/`computeCenteringTranslation`
 * 本身仍只處理「一個內容區塊 fit 進一個可用區塊」這個單一職責，雙頁的寬度切分/
 * 中縫扣除邏輯留給呼叫端（或新的專屬函式）決定，避免這兩個既有函式的參數語意
 * 因為雙頁模式而變得模糊。
 */
object EpubFxlScaler {

    /**
     * 依可用容器尺寸（[availableWidth]／[availableHeight]，通常是 container 的
     * 量測寬高）與內容原始尺寸（[contentWidth]／[contentHeight]，通常是 WebView
     * 的量測寬高）計算等比縮放係數。取寬度縮放比與高度縮放比中較小的一個（確保
     * 兩個維度都不會溢出容器，對應 Fit.CONTAIN 語意），並以 `coerceAtMost(1f)`
     * 夾限——FXL 縮放只縮小內容以符合可視範圍，不會把原本就比容器小的內容放大。
     */
    fun computeFitScale(
        availableWidth: Int,
        availableHeight: Int,
        contentWidth: Int,
        contentHeight: Int,
    ): Float {
        return minOf(
            availableWidth.toFloat() / contentWidth.toFloat(),
            availableHeight.toFloat() / contentHeight.toFloat(),
        ).coerceAtMost(1f)
    }
}
```

- [ ] **Step 4：執行測試確認通過**

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.EpubFxlScalerTest"
```

Expected：`BUILD SUCCESSFUL`，4 個測試（`高度為縮放瓶頸時...`／`寬度為縮放瓶頸時...`／`內容小於容器時不放大...`／`寬高比例一放大一縮小時...`）皆通過。

- [ ] **Step 5：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubFxlScaler.kt \
        app/android/app/src/test/kotlin/cc/ugotit/elinkbook/EpubFxlScalerTest.kt
git commit -m "feat(epic-16): 新增 EpubFxlScaler，先抽離 FXL 縮放係數計算 computeFitScale"
```

---

### Task 2：`computeCenteringTranslation()` 置中位移計算抽離

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubFxlScaler.kt`（Task 1 建立的檔案，新增 `Translation`／`computeCenteringTranslation`）
- Modify: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/EpubFxlScalerTest.kt`（Task 1 建立的檔案，新增測試）

**Interfaces:**
- Consumes：無（獨立於 Task 1 的 `computeFitScale`，呼叫端自行傳入已算好的 `scale`）。
- Produces：
  - `EpubFxlScaler.Translation`（`data class`，欄位 `x`／`y: Float`）——Task 3 會把 `EpubReaderView.kt` 對 `webView.translationX`/`translationY` 的賦值改為讀取這裡的 `x`/`y`。
  - `fun computeCenteringTranslation(availableWidth: Int, availableHeight: Int, contentWidth: Int, contentHeight: Int, scale: Float, currentLeft: Float, currentTop: Float): Translation`

- [ ] **Step 1：寫失敗測試**

在 `EpubFxlScalerTest.kt` 的 `class EpubFxlScalerTest { ... }` 內、`computeFitScale` 測試群組後面新增：

```kotlin
    // ---- computeCenteringTranslation ----

    @Test
    fun `原始位置在原點時，置中位移等於容器與縮放後內容尺寸差的一半`() {
        // available 1000x1000、content 800x800、scale=1.0（縮放後仍是 800x800）、
        // currentLeft/currentTop=0（尚未有任何位移）：置中位移 = (1000-800)/2 = 100。
        val translation = EpubFxlScaler.computeCenteringTranslation(
            availableWidth = 1000,
            availableHeight = 1000,
            contentWidth = 800,
            contentHeight = 800,
            scale = 1.0f,
            currentLeft = 0f,
            currentTop = 0f,
        )

        assertEquals(100f, translation.x, 1e-4f)
        assertEquals(100f, translation.y, 1e-4f)
    }

    @Test
    fun `原始位置非原點（含負值偏移）時，置中位移會扣掉目前已有的偏移量`() {
        // available 1080x1600、content 1080x1920、scale=0.75（縮放後 810x1440）：
        // desiredLeft=(1080-810)/2=135，desiredTop=(1600-1440)/2=80。
        // currentLeft=50（Readium 排版已有的水平偏移）、currentTop=-20（垂直方向
        // 已往上偏移，對應 EpubReaderView.kt 註解描述的「WebView 天然高度比容器
        // 可用高度更高、置中後往上位移」情境）：
        // x = 135 - 50 = 85；y = 80 - (-20) = 100。
        val translation = EpubFxlScaler.computeCenteringTranslation(
            availableWidth = 1080,
            availableHeight = 1600,
            contentWidth = 1080,
            contentHeight = 1920,
            scale = 0.75f,
            currentLeft = 50f,
            currentTop = -20f,
        )

        assertEquals(85f, translation.x, 1e-4f)
        assertEquals(100f, translation.y, 1e-4f)
    }

    @Test
    fun `縮放後內容剛好等於容器尺寸且無原始偏移時，置中位移為零`() {
        val translation = EpubFxlScaler.computeCenteringTranslation(
            availableWidth = 1200,
            availableHeight = 900,
            contentWidth = 1200,
            contentHeight = 900,
            scale = 1.0f,
            currentLeft = 0f,
            currentTop = 0f,
        )

        assertEquals(0f, translation.x, 1e-4f)
        assertEquals(0f, translation.y, 1e-4f)
    }
```

- [ ] **Step 2：執行測試確認失敗**

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.EpubFxlScalerTest"
```

Expected：編譯失敗，錯誤訊息包含 `unresolved reference: computeCenteringTranslation`。

- [ ] **Step 3：在 EpubFxlScaler.kt 新增 Translation／computeCenteringTranslation**

編輯 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubFxlScaler.kt`，在 `computeFitScale` 函式之後（檔案最後）新增：

```kotlin

    /** [computeCenteringTranslation] 的回傳值：縮放後內容需要疊加的水平/垂直位移
     * （對應 `View.translationX`/`translationY`），使縮放後內容在可用容器內置中。*/
    data class Translation(val x: Float, val y: Float)

    /**
     * 依可用容器尺寸（[availableWidth]／[availableHeight]）、內容原始尺寸
     * （[contentWidth]／[contentHeight]）、已算好的縮放係數 [scale]，以及內容目前
     * （未經校正、由呼叫端透過 `View.getLocationOnScreen()` 量測所得）相對容器的
     * 原始位置（[currentLeft]／[currentTop]），計算需要疊加的 translationX/Y，使
     * 縮放後的內容剛好水平和垂直置中在容器裡。
     *
     * [currentLeft]／[currentTop] 可能非零、甚至為負值——呼叫端的排版系統（例如
     * Readium 內建 XML 對 WebView 做的置中）可能在這個函式執行前就已經把內容擺在
     * 某個非原點的位置；本函式不假設呼叫端的排版邏輯，只單純計算「從目前位置到
     * 置中位置」所需要的位移量，不論起點在哪裡都能算出正確的最終位置。
     */
    fun computeCenteringTranslation(
        availableWidth: Int,
        availableHeight: Int,
        contentWidth: Int,
        contentHeight: Int,
        scale: Float,
        currentLeft: Float,
        currentTop: Float,
    ): Translation {
        val scaledWidth = contentWidth * scale
        val scaledHeight = contentHeight * scale
        val desiredLeft = (availableWidth - scaledWidth) / 2f
        val desiredTop = (availableHeight - scaledHeight) / 2f
        return Translation(desiredLeft - currentLeft, desiredTop - currentTop)
    }
```

- [ ] **Step 4：執行測試確認通過**

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.EpubFxlScalerTest"
```

Expected：`BUILD SUCCESSFUL`，7 個測試（Task 1 的 4 個 + 本 Task 的 3 個）皆通過。

- [ ] **Step 5：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubFxlScaler.kt \
        app/android/app/src/test/kotlin/cc/ugotit/elinkbook/EpubFxlScalerTest.kt
git commit -m "feat(epic-16): EpubFxlScaler 新增置中位移計算 computeCenteringTranslation，抽離工作全數完成"
```

---

### Task 3：`EpubReaderView.kt` 改用 `EpubFxlScaler`，真機回歸驗證

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`

**Interfaces:**
- Consumes：`EpubFxlScaler.computeFitScale(Int, Int, Int, Int): Float`／`EpubFxlScaler.computeCenteringTranslation(Int, Int, Int, Int, Float, Float, Float): EpubFxlScaler.Translation`（皆為 Task 1-2 產出）。
- Produces：無新公開介面——本 Task 純粹是呼叫端切換，`EpubReaderView` 對外的 method channel 契約（`openBook`／`setPreferences`）與 `EpubNavigatorFragment.Listener`/`PaginationListener` 實作完全不變。

此 Task 不寫新測試（沒有新增行為），而是用既有的真機 `integration_test` 作回歸驗證——見 Step 3。

- [ ] **Step 1：修改 EpubReaderView.kt——applyFxlFitScale() 內部改呼叫 EpubFxlScaler**

原本（`applyFxlFitScale()` 內的 `ViewTreeObserver.OnGlobalLayoutListener` lambda，第 330-361 行）：

```kotlin
            for (webView in findViewsByType<WebView>(container)) {
                val contentWidth = webView.width
                val contentHeight = webView.height
                if (contentWidth <= 0 || contentHeight <= 0) continue
                val fitScale = cachedFxlFitScale ?: minOf(
                    availableWidth.toFloat() / contentWidth.toFloat(),
                    availableHeight.toFloat() / contentHeight.toFloat(),
                ).coerceAtMost(1f).also { cachedFxlFitScale = it }

                // 先歸零位移、以左上角為錨點，量出這一輪「未經校正」的原始 layout
                // 位置（pivot 在 (0,0) 時縮放不會移動錨點本身，所以量到的位置就是
                // Readium 自己排版（含它內部的置中位移）算出來的原始位置）。
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

                // 縮放後的內容尺寸若小於可用空間，置中留白（水平/垂直皆可能發生，
                // 對應 Fit.CONTAIN 的語意）。
                val scaledWidth = contentWidth * fitScale
                val scaledHeight = contentHeight * fitScale
                val desiredLeft = (availableWidth - scaledWidth) / 2f
                val desiredTop = (availableHeight - scaledHeight) / 2f

                webView.translationX = desiredLeft - currentLeft
                webView.translationY = desiredTop - currentTop
            }
```

改為（縮放係數與置中位移的計算公式改呼叫 `EpubFxlScaler`，View 屬性量測/賦值與 `cachedFxlFitScale` 狀態管理不變）：

```kotlin
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

                // 先歸零位移、以左上角為錨點，量出這一輪「未經校正」的原始 layout
                // 位置（pivot 在 (0,0) 時縮放不會移動錨點本身，所以量到的位置就是
                // Readium 自己排版（含它內部的置中位移）算出來的原始位置）。
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
```

- [ ] **Step 2：靜態檢查與既有 JVM 測試回歸**

於 `app/` 目錄執行：

```bash
flutter analyze
```

Expected：`No issues found!`（本 Task 未變動任何 Dart 程式碼，此步驟純粹確認沒有意外波及）。

於 `app/android` 目錄執行新增的原生單元測試，確認 Task 1-2 的邏輯仍完整可用（本 Task 沒有修改 `EpubFxlScaler.kt` 本身，此步驟是防止 Step 1 的編輯誤觸該檔案）：

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.EpubFxlScalerTest"
```

Expected：`BUILD SUCCESSFUL`，7 個測試全數通過。

- [ ] **Step 3：真機回歸驗證（integration_test）**

列出可用的真實裝置/模擬器：

```bash
flutter devices
```

於 `app/` 目錄，針對既有涵蓋定樣式（FXL）EPUB 開書的真機測試執行回歸（`-d <device-id>` 依上一步列出的裝置代號替換）：

```bash
flutter test integration_test/epub_reader_view_test.dart -d <device-id>
```

Expected：全部測試皆通過，尤其留意以下涵蓋本次抽離邏輯的既有測試（測試名稱不變，行為應與抽離前完全一致）：

- `開啟定樣式範例 EPUB，onLayoutResolved 回報 isFixedLayout 為 true`

此測試本身只驗證 `isFixedLayout` 詮釋資料回報，不會斷言縮放/置中的實際像素結果（`scaleX`/`translationX` 等 View 屬性未透過 method channel 暴露給 Dart 端，`flutter test`/`integration_test` 皆無法直接斷言）。因此除了跑通這個既有測試（確認開書流程本身無回歸），**還需要人工視覺確認**：在真機上開啟一本固定版面（漫畫）EPUB，肉眼比對抽離前後的縮放比例與置中位置是否一致（頁面內容置中顯示、無明顯裁切或留白異常，旋轉裝置後重新計算正確）。若手邊沒有現成的固定版面測試素材，可使用 `app/test/fixtures/sample_fixed_layout.epub`（既有測試 fixture，已在版本控制中）。

若測試失敗，先確認失敗原因是否為本次抽離造成的行為差異（例如公式謄寫錯誤、參數傳遞順序打錯），而非既有已知限制。

- [ ] **Step 4：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
git commit -m "refactor(epic-16): EpubReaderView 改用 EpubFxlScaler，FXL 縮放計算邏輯抽離完成"
```

---

## Self-Review

**Spec coverage：** `docs/epics.md`「`EpubReaderView.kt` FXL 縮放邏輯抽離為 `EpubFxlScaler`」列與 `issues.md` Issue 8 要求的抽離範圍——縮放係數計算（Task 1）、置中位移計算（Task 2）——皆有對應 Task，且 Task 3 完成呼叫端切換與真機回歸驗證收尾。架構審查（`tmp/epic-16/reviews/architecture-review-1783800246.html` Candidate #3）要求的「pure Kotlin、可 JVM 單元測試」已達成，且比照 `epic-4-pdf-enhance` Issue 8 已驗證過的抽離模式（薄包裝 + 純函式核心），維持了與既有程式碼一致的架構風格。

**Placeholder scan：** 已逐一檢查，所有 Step 皆含完整可執行程式碼與明確指令/預期輸出，無 TBD／「依需要調整」等佔位敘述。

**Type consistency：** `EpubFxlScaler.computeFitScale`（`(Int, Int, Int, Int) -> Float`）／`EpubFxlScaler.Translation`（`data class(x: Float, y: Float)`）／`EpubFxlScaler.computeCenteringTranslation`（`(Int, Int, Int, Int, Float, Float, Float) -> Translation`）的簽章在 Task 1-2（定義處）與 Task 3（呼叫處）皆一致核對過；`fitScale`／`translation.x`／`translation.y` 的變數命名與型別（`Float`）在呼叫端與 `webView.scaleX`/`scaleY`/`translationX`/`translationY`（皆為 Kotlin `Float` 屬性）相容。

**與 Issue 6 的銜接：** 已在 Global Constraints 與 `issues.md` Issue 8 明確記錄「本抽離提前於 Issue 6 之前執行，Issue 6 未來的雙頁縮放邏輯應在 `EpubFxlScaler` 內擴充」，避免 Issue 6 實作者依循 `issues.md` Issue 6 舊描述「就地實作」而重新引入耦合。

---

**Plan complete and saved to `docs/epics/epic-16-dual-page/plans/plan-issue-8.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - 逐一 Task 派遣獨立 subagent 實作，每個 Task 完成後審查、快速迭代

**2. Inline Execution** - 在本 session 內依 Task 順序批次執行，設檢查點供人工確認

**Which approach？**
