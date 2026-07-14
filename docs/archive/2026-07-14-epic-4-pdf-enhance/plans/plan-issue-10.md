# Epic 4 Issue 10：PdfReaderView.kt fitMode/cropMode 改用 Kotlin enum 取代 String 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `PdfReaderView.kt` 原生端的 `fitMode`／`cropMode` 欄位從 `String` 改為 Kotlin `enum class`，消除獨立程式碼審查指出的 Primitive Obsession（直接字串比對，例如 `cropMode == "autoDetect"`），提高型別安全性。

**Architecture:** 在 `PdfReaderView` 類別內新增兩個巢狀 `internal enum class`：`PdfFitMode { PAGE_FIT, FIT_WIDTH, ACTUAL_SIZE }` 與 `PdfCropMode { NONE, AUTO_DETECT, MANUAL }`，比照既有 `CropOverlayView.Handle` 巢狀 enum 慣例（`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/CropOverlayView.kt:81`）。每個 enum 皆附 `companion object` 的 `fromWireValue(value: String?)` 解析函式，在 `setPdfPreferences()`／`openBook()` 收到 Method Channel 傳來的原始字串當下**立即**解析為 enum，`fitMode`／`cropMode` 欄位型別與後續所有比對邏輯（`renderCurrentPage()`／`applyFitMode()`／`enterCropEditMode()` 回呼）改用 enum。**Method Channel 的資料交換格式完全不變**——Dart 端 `PdfFitMode`/`PdfCropMode`（`app/lib/reader/pdf_fit_mode.dart`／`pdf_crop_mode.dart`）透過 `.name` 送出的字串字面值（`'pageFit'`/`'fitWidth'`/`'actualSize'`、`'none'`/`'autoDetect'`/`'manual'`）維持原樣，Dart 端不需任何修改，只有原生端內部表示法從 `String` 換成 `enum`，屬於原生端內部重構。

**Tech Stack:** Kotlin（Android 原生端）、JUnit 4（`app/android/app/build.gradle.kts` 已由 Issue 8 加入 `testImplementation("junit:junit:4.13.2")`，本計劃不需重複新增）、Gradle（`app/android` 模組既有 AGP + Kotlin plugin 設定）。

## Global Constraints

- 這是抽離重構，不是新功能：`PdfFitMode`／`PdfCropMode` 對應的字面值集合（`'pageFit'`/`'fitWidth'`/`'actualSize'`、`'none'`/`'autoDetect'`/`'manual'`）與各自的預設值（`PAGE_FIT`／`NONE`）必須與原本字串版本逐一等價——不得新增/刪減合法值，也不得調整預設值。
- **與逐行等價原則的唯一已知落差，明確授權的例外**：抽離前 `renderCurrentPage()` 用 `cropMode != "none"` 判斷是否套用裁切——任何**不等於** `"none"` 的原始字串（含未知垃圾值）都會被視為「裁切生效」。抽離後 `PdfCropMode.fromWireValue()` 把未知值正規化為 `NONE`（視為不裁切），這在理論上不是逐行等價。**此差異在正式產品路徑中不可觸及**：Dart 端唯一呼叫來源 `PdfCropMode.name`（`app/lib/reader/pdf_crop_mode.dart` 的 `enum PdfCropMode { none, autoDetect, manual }`）只會產生上述三個合法字面值之一，不會送出其他字串；且 Kotlin 端本來就用 `(preferences["cropMode"] as? String)` 先過濾非 String 型別。因此屬於零風險的死碼路徑差異，Task 2 會明確測試並記錄此行為，不需要人類每次審查時重新確認。`fitMode` 沒有這個落差——原本 `when(fitMode) { "fitWidth"->...; "actualSize"->...; else->pageFit }` 本來就是「其餘一律視為 pageFit」的完整覆蓋語意，`PdfFitMode.fromWireValue()` 逐行等價。
- Method Channel 的 key 名稱（`"fitMode"`／`"cropMode"`／`"cropRect"` 等 Map key 字串）與 Dart 端序列化格式完全不變，本計劃只改動原生端如何**內部表示**收到的值，不改動任何跨語言邊界的資料格式；`app/lib/` 底下任何 Dart 檔案本計劃皆不需修改。
- `PdfFitMode`／`PdfCropMode` 宣告為 `internal enum class`（而非 `private`）：`internal` 讓 `app/src/test` 的 JVM 單元測試可以直接存取 `PdfReaderView.PdfFitMode`／`PdfReaderView.PdfCropMode`，比照 `PdfImageProcessor.kt` 既有 `internal fun dilatePixels(...)`／`internal fun detectCropRectFromPixels(...)` 讓 `PdfImageProcessorTest.kt` 可直接呼叫的慣例（同一 Gradle 模組內 `internal` 可跨 `src/main`／`src/test` 存取，此模式在本專案已驗證可行）。
- 本次刻意不處理、範圍不重疊的既有技術債：`CropOverlayView.kt` 的 `Handle` enum（型別已經是 enum，不在本次範圍內）；`fitMode`/`cropMode` 以外的其他欄位（`contrast`／`brightness`／`boldStrength`／`cropRect`）維持現狀，不受本計劃影響。
- 測試指令慣例：Dart 測試用 `flutter test`（於 `app/` 目錄執行，本計劃預期無 Dart 測試異動）；原生 JVM 單元測試用 Gradle `./gradlew testDebugUnitTest`（於 `app/android` 目錄執行，`gradlew`/`gradlew.bat` 為 `.gitignore` 排除產物，若尚不存在先於 `app/` 目錄執行一次 `flutter build apk --debug` 讓 Flutter 產生）。
- `minSdk = 24`（見專案 `CLAUDE.md`）：本計劃不涉及 API level 相關邏輯變動，Kotlin `enum class` 與 `when` 表達式皆為純語言特性，不引用任何有 API 版本門檻的 Android API。

---

## File Structure

- **Modify** `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`：新增巢狀 `internal enum class PdfFitMode`／`PdfCropMode`（各附 `fromWireValue()`）；`fitMode`／`cropMode` 欄位型別改為對應 enum；`setPdfPreferences()`／`openBook()`／`renderCurrentPage()`／`enterCropEditMode()`／`applyFitMode()` 內所有相關字串比對改為 enum 比對。
- **Create** `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfReaderViewTest.kt`：針對 `PdfFitMode.fromWireValue()`／`PdfCropMode.fromWireValue()` 的 JVM 單元測試（不需要真機/模擬器）。

---

### Task 1：`PdfFitMode` enum 抽離

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`
- Create: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfReaderViewTest.kt`

**Interfaces:**
- Produces：`PdfReaderView.PdfFitMode`（`internal enum class`，值 `PAGE_FIT`／`FIT_WIDTH`／`ACTUAL_SIZE`）與 `PdfReaderView.PdfFitMode.fromWireValue(value: String?): PdfFitMode`——供 Task 3 的呼叫端使用；Task 2 會在同一個檔案內繼續新增 `PdfCropMode`。

- [ ] **Step 1：寫失敗測試**

建立 `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfReaderViewTest.kt`（新檔案）：

```kotlin
package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Test

class PdfReaderViewTest {

    // ---- PdfFitMode.fromWireValue ----

    @Test
    fun `fromWireValue 傳入 fitWidth 時回傳 FIT_WIDTH`() {
        val mode = PdfReaderView.PdfFitMode.fromWireValue("fitWidth")

        assertEquals(PdfReaderView.PdfFitMode.FIT_WIDTH, mode)
    }

    @Test
    fun `fromWireValue 傳入 actualSize 時回傳 ACTUAL_SIZE`() {
        val mode = PdfReaderView.PdfFitMode.fromWireValue("actualSize")

        assertEquals(PdfReaderView.PdfFitMode.ACTUAL_SIZE, mode)
    }

    @Test
    fun `fromWireValue 傳入 pageFit 時回傳 PAGE_FIT`() {
        val mode = PdfReaderView.PdfFitMode.fromWireValue("pageFit")

        assertEquals(PdfReaderView.PdfFitMode.PAGE_FIT, mode)
    }

    @Test
    fun `fromWireValue 傳入 null 時回傳預設值 PAGE_FIT`() {
        val mode = PdfReaderView.PdfFitMode.fromWireValue(null)

        assertEquals(PdfReaderView.PdfFitMode.PAGE_FIT, mode)
    }

    @Test
    fun `fromWireValue 傳入未知字串時回傳預設值 PAGE_FIT`() {
        val mode = PdfReaderView.PdfFitMode.fromWireValue("unknown-garbage")

        assertEquals(PdfReaderView.PdfFitMode.PAGE_FIT, mode)
    }
}
```

- [ ] **Step 2：執行測試確認失敗（編譯錯誤，`PdfFitMode` 尚不存在）**

於 `app/android` 目錄執行：

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfReaderViewTest"
```

（若 `./gradlew` 不存在：先於 `app/` 目錄執行一次 `flutter build apk --debug`，讓 Flutter 產生 `app/android/gradlew`／`gradlew.bat`，再重新執行上述指令。）

Expected：編譯失敗，錯誤訊息包含 `unresolved reference: PdfFitMode`。

- [ ] **Step 3：在 PdfReaderView.kt 新增 PdfFitMode 巢狀 enum**

編輯 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`，在既有的：

```kotlin
    private var cropEditModeActive: Boolean = false
    private var cropOverlayView: CropOverlayView? = null

    init {
        channel.setMethodCallHandler(this)
    }
```

改為（在 `cropOverlayView` 欄位與 `init` 區塊之間插入新的巢狀 enum）：

```kotlin
    private var cropEditModeActive: Boolean = false
    private var cropOverlayView: CropOverlayView? = null

    /**
     * PDF 頁面顯示縮放模式（FR-11），對應 Dart PdfFitMode 列舉
     * （`app/lib/reader/pdf_fit_mode.dart`）透過 Method Channel 傳來的
     * `.name` 字串（'pageFit'／'fitWidth'／'actualSize'）。原生端原本
     * 直接以 String 儲存並用字串比對（Primitive Obsession，見
     * tmp/epic-4/reviews/code-review-report.md），改用此列舉提高型別
     * 安全性，見 docs/epics/epic-4-pdf-enhance/plans/plan-issue-10.md。
     */
    internal enum class PdfFitMode {
        PAGE_FIT, FIT_WIDTH, ACTUAL_SIZE;

        companion object {
            /** 未知或非 String 的原始值一律正規化為 [PAGE_FIT]（預設），
             * 與抽離前 applyFitMode() 的 when...else 退回 pageFit 行為的
             * 語意完全等價——原本任何不等於 "fitWidth"／"actualSize" 的
             * 字串（含 null／未知垃圾值）都會落到 else 分支，本函式維持
             * 相同的「其餘一律視為 pageFit」語意。*/
            fun fromWireValue(value: String?): PdfFitMode = when (value) {
                "fitWidth" -> FIT_WIDTH
                "actualSize" -> ACTUAL_SIZE
                else -> PAGE_FIT
            }
        }
    }

    init {
        channel.setMethodCallHandler(this)
    }
```

- [ ] **Step 4：執行測試確認通過**

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfReaderViewTest"
```

Expected：`BUILD SUCCESSFUL`，5 個測試（`fromWireValue 傳入 fitWidth...`／`actualSize...`／`pageFit...`／`null...`／`未知字串...`）皆通過。

- [ ] **Step 5：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt \
        app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfReaderViewTest.kt
git commit -m "feat(epic-4): PdfReaderView 新增 PdfFitMode enum，抽離 fitMode 字串比對"
```

---

### Task 2：`PdfCropMode` enum 抽離

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`（Task 1 已修改的檔案，新增 `PdfCropMode`）
- Modify: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfReaderViewTest.kt`（Task 1 建立的檔案，新增測試）

**Interfaces:**
- Consumes：無（獨立於 Task 1 的 `PdfFitMode`）。
- Produces：`PdfReaderView.PdfCropMode`（`internal enum class`，值 `NONE`／`AUTO_DETECT`／`MANUAL`）與 `PdfReaderView.PdfCropMode.fromWireValue(value: String?): PdfCropMode`——供 Task 3 的呼叫端使用。

- [ ] **Step 1：寫失敗測試**

在 `PdfReaderViewTest.kt` 的 `class PdfReaderViewTest { ... }` 內、`PdfFitMode.fromWireValue` 測試群組後面新增：

```kotlin

    // ---- PdfCropMode.fromWireValue ----

    @Test
    fun `fromWireValue 傳入 autoDetect 時回傳 AUTO_DETECT`() {
        val mode = PdfReaderView.PdfCropMode.fromWireValue("autoDetect")

        assertEquals(PdfReaderView.PdfCropMode.AUTO_DETECT, mode)
    }

    @Test
    fun `fromWireValue 傳入 manual 時回傳 MANUAL`() {
        val mode = PdfReaderView.PdfCropMode.fromWireValue("manual")

        assertEquals(PdfReaderView.PdfCropMode.MANUAL, mode)
    }

    @Test
    fun `fromWireValue 傳入 none 時回傳 NONE`() {
        val mode = PdfReaderView.PdfCropMode.fromWireValue("none")

        assertEquals(PdfReaderView.PdfCropMode.NONE, mode)
    }

    @Test
    fun `fromWireValue 傳入 null 時回傳預設值 NONE`() {
        val mode = PdfReaderView.PdfCropMode.fromWireValue(null)

        assertEquals(PdfReaderView.PdfCropMode.NONE, mode)
    }

    @Test
    fun `fromWireValue 傳入未知字串時正規化為 NONE（已知且經授權的行為差異，見 PdfCropMode KDoc）`() {
        val mode = PdfReaderView.PdfCropMode.fromWireValue("unknown-garbage")

        assertEquals(PdfReaderView.PdfCropMode.NONE, mode)
    }
```

- [ ] **Step 2：執行測試確認失敗**

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfReaderViewTest"
```

Expected：編譯失敗，錯誤訊息包含 `unresolved reference: PdfCropMode`。

- [ ] **Step 3：在 PdfReaderView.kt 新增 PdfCropMode 巢狀 enum**

編輯 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`，在 Task 1 新增的 `PdfFitMode` 巢狀 enum 之後（`init { channel.setMethodCallHandler(this) }` 之前）新增：

```kotlin

    /**
     * PDF 頁面裁切模式（FR-11），對應 Dart PdfCropMode 列舉
     * （`app/lib/reader/pdf_crop_mode.dart`）透過 Method Channel 傳來的
     * `.name` 字串（'none'／'autoDetect'／'manual'）。抽離理由同
     * [PdfFitMode]。
     */
    internal enum class PdfCropMode {
        NONE, AUTO_DETECT, MANUAL;

        companion object {
            /**
             * 未知或非 String 的原始值正規化為 [NONE]。
             *
             * 【與逐行等價原則的唯一已知落差，經人類明確授權的例外，見
             * plan-issue-10.md Global Constraints】抽離前 renderCurrentPage()
             * 用 `cropMode != "none"` 判斷是否套用裁切，任何不等於 "none"
             * 的原始字串（含未知垃圾值）都會被視為「裁切生效」；抽離後
             * fromWireValue() 把未知值正規化為 NONE（視為不裁切），行為並
             * 不完全等價。此差異在正式產品路徑中不可觸及——Dart 端唯一
             * 呼叫來源 PdfCropMode.name（見 app/lib/reader/pdf_crop_mode.dart）
             * 只會產生 'none'／'autoDetect'／'manual' 三個合法字面值之一，
             * 不會送出其他字串，因此屬於零風險的死碼路徑差異。
             */
            fun fromWireValue(value: String?): PdfCropMode = when (value) {
                "autoDetect" -> AUTO_DETECT
                "manual" -> MANUAL
                else -> NONE
            }
        }
    }
```

- [ ] **Step 4：執行測試確認通過**

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfReaderViewTest"
```

Expected：`BUILD SUCCESSFUL`，10 個測試（Task 1 的 5 個 + 本 Task 的 5 個）皆通過。

- [ ] **Step 5：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt \
        app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfReaderViewTest.kt
git commit -m "feat(epic-4): PdfReaderView 新增 PdfCropMode enum，抽離 cropMode 字串比對"
```

---

### Task 3：`PdfReaderView.kt` 呼叫端改用 enum，真機回歸驗證

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`

**Interfaces:**
- Consumes：`PdfReaderView.PdfFitMode.fromWireValue(String?): PdfFitMode`／`PdfReaderView.PdfCropMode.fromWireValue(String?): PdfCropMode`（皆為 Task 1-2 產出）。
- Produces：無新公開介面——本 Task 純粹是內部型別切換，`PdfReaderView` 對外的 method channel 契約（`openBook`／`setPdfPreferences`／`nextPage`／`previousPage`／`enterCropEditMode`／`exitCropEditMode`）與 Map key 名稱（`"fitMode"`／`"cropMode"`）完全不變，Dart 端零改動。

此 Task 不寫新測試（沒有新增行為），而是用既有的真機 `integration_test` 作回歸驗證——見 Step 3。

- [ ] **Step 1：修改 PdfReaderView.kt——欄位型別改為 enum**

1. `fitMode` 欄位（原第 58-60 行）：

原本：
```kotlin
    // Dart PdfFitMode.name 對應字串（'pageFit'／'fitWidth'／'actualSize'），
    // 預設 "pageFit"，與 BookReaderPrefs.pdfFitMode 為 null 時的語意一致。
    private var fitMode: String = "pageFit"
```

改為：
```kotlin
    // 解析自 Dart PdfFitMode.name 字串，預設 PAGE_FIT，與
    // BookReaderPrefs.pdfFitMode 為 null 時的語意一致。
    private var fitMode: PdfFitMode = PdfFitMode.PAGE_FIT
```

2. `cropMode` 欄位（原第 71-73 行）：

原本：
```kotlin
    // Dart PdfCropMode.name 對應字串（'none'／'autoDetect'／'manual'），
    // 預設 "none"，與 BookReaderPrefs.pdfCropMode 為 null 時的語意一致。
    private var cropMode: String = "none"
```

改為：
```kotlin
    // 解析自 Dart PdfCropMode.name 字串，預設 NONE，與
    // BookReaderPrefs.pdfCropMode 為 null 時的語意一致。
    private var cropMode: PdfCropMode = PdfCropMode.NONE
```

- [ ] **Step 2：修改 PdfReaderView.kt——setPdfPreferences() 與 openBook() 改用 fromWireValue()**

1. `setPdfPreferences()` 內的 `fitMode`（原第 139 行）：

原本：
```kotlin
        (preferences["fitMode"] as? String)?.let { fitMode = it }
```

改為：
```kotlin
        (preferences["fitMode"] as? String)?.let { fitMode = PdfFitMode.fromWireValue(it) }
```

2. `setPdfPreferences()` 內的 `cropChanged`（原第 148-152 行）：

原本：
```kotlin
        val cropChanged = (preferences["cropMode"] as? String)?.let {
            val changed = it != cropMode
            cropMode = it
            changed
        } ?: false
```

改為：
```kotlin
        val cropChanged = (preferences["cropMode"] as? String)?.let {
            val newValue = PdfCropMode.fromWireValue(it)
            val changed = newValue != cropMode
            cropMode = newValue
            changed
        } ?: false
```

3. `openBook()` 內的 `fitMode`（原第 179 行）：

原本：
```kotlin
        (initialPreferences?.get("fitMode") as? String)?.let { fitMode = it }
```

改為：
```kotlin
        (initialPreferences?.get("fitMode") as? String)?.let { fitMode = PdfFitMode.fromWireValue(it) }
```

4. `openBook()` 內的 `cropMode`（原第 183 行）：

原本：
```kotlin
        (initialPreferences?.get("cropMode") as? String)?.let { cropMode = it }
```

改為：
```kotlin
        (initialPreferences?.get("cropMode") as? String)?.let { cropMode = PdfCropMode.fromWireValue(it) }
```

- [ ] **Step 3：修改 PdfReaderView.kt——renderCurrentPage()／enterCropEditMode()／applyFitMode() 改用 enum 比對**

1. `renderCurrentPage()` 的智慧自動裁切判斷（原第 215 行）：

原本：
```kotlin
        if (cropMode == "autoDetect" && cropRect == null) {
```

改為：
```kotlin
        if (cropMode == PdfCropMode.AUTO_DETECT && cropRect == null) {
```

2. `renderCurrentPage()` 的 `effectiveCrop`（原第 235 行）：

原本：
```kotlin
        val effectiveCrop = if (cropMode != "none") cropRect else null
```

改為：
```kotlin
        val effectiveCrop = if (cropMode != PdfCropMode.NONE) cropRect else null
```

3. `enterCropEditMode()` 的 `CropOverlayView` 確認回呼（原第 320-321 行）：

原本：
```kotlin
            cropRect = result
            cropMode = "manual"
```

改為：
```kotlin
            cropRect = result
            cropMode = PdfCropMode.MANUAL
```

4. `applyFitMode()`（原第 407-434 行）——`when` 分支從字串比對改為 enum 比對，且改成涵蓋全部 3 個 enum 值的窮舉 `when`（Kotlin 編譯器會強制檢查涵蓋所有分支，不再需要 `else` 兜底，這正是本次重構要達成的型別安全效果）：

原本：
```kotlin
    private fun applyFitMode() {
        when (fitMode) {
            "fitWidth" -> {
                val viewWidth = imageView.width
                val bitmapWidth = imageView.drawable?.intrinsicWidth ?: 0
                if (viewWidth <= 0 || bitmapWidth <= 0) return
                val scale = viewWidth.toFloat() / bitmapWidth.toFloat()
                imageView.scaleType = ImageView.ScaleType.MATRIX
                imageView.imageMatrix = android.graphics.Matrix().apply { setScale(scale, scale) }
            }
            "actualSize" -> {
                val bitmapWidth = imageView.drawable?.intrinsicWidth ?: 0
                if (bitmapWidth <= 0) return
                val density = context.resources.displayMetrics.density
                // 與 renderCurrentPage() 算 bitmap 尺寸時使用的同一個
                // PdfImageProcessor.pageRenderScale()，換算回「1 PDF point =
                // 1 dp」的真實顯示比例。兩處呼叫同一個共用函式，不再是各自
                // 硬編碼、需要手動同步的隱式耦合（見
                // docs/epics/epic-4-pdf-enhance/plans/plan-issue-9.md）。
                val bitmapRenderScale = PdfImageProcessor.pageRenderScale(density)
                val displayScale = density / bitmapRenderScale
                imageView.scaleType = ImageView.ScaleType.MATRIX
                imageView.imageMatrix = android.graphics.Matrix().apply { setScale(displayScale, displayScale) }
            }
            else -> { // "pageFit"（預設）
                imageView.scaleType = ImageView.ScaleType.FIT_CENTER
            }
        }
    }
```

改為：
```kotlin
    private fun applyFitMode() {
        when (fitMode) {
            PdfFitMode.FIT_WIDTH -> {
                val viewWidth = imageView.width
                val bitmapWidth = imageView.drawable?.intrinsicWidth ?: 0
                if (viewWidth <= 0 || bitmapWidth <= 0) return
                val scale = viewWidth.toFloat() / bitmapWidth.toFloat()
                imageView.scaleType = ImageView.ScaleType.MATRIX
                imageView.imageMatrix = android.graphics.Matrix().apply { setScale(scale, scale) }
            }
            PdfFitMode.ACTUAL_SIZE -> {
                val bitmapWidth = imageView.drawable?.intrinsicWidth ?: 0
                if (bitmapWidth <= 0) return
                val density = context.resources.displayMetrics.density
                // 與 renderCurrentPage() 算 bitmap 尺寸時使用的同一個
                // PdfImageProcessor.pageRenderScale()，換算回「1 PDF point =
                // 1 dp」的真實顯示比例。兩處呼叫同一個共用函式，不再是各自
                // 硬編碼、需要手動同步的隱式耦合（見
                // docs/epics/epic-4-pdf-enhance/plans/plan-issue-9.md）。
                val bitmapRenderScale = PdfImageProcessor.pageRenderScale(density)
                val displayScale = density / bitmapRenderScale
                imageView.scaleType = ImageView.ScaleType.MATRIX
                imageView.imageMatrix = android.graphics.Matrix().apply { setScale(displayScale, displayScale) }
            }
            PdfFitMode.PAGE_FIT -> {
                imageView.scaleType = ImageView.ScaleType.FIT_CENTER
            }
        }
    }
```

- [ ] **Step 4：靜態檢查與既有 JVM 測試回歸**

於 `app/` 目錄執行：

```bash
flutter analyze
```

Expected：`No issues found!`（本 Task 未變動任何 Dart 程式碼，此步驟純粹確認沒有意外波及）。

於 `app/android` 目錄執行：

```bash
./gradlew testDebugUnitTest
```

Expected：`BUILD SUCCESSFUL`，`PdfReaderViewTest`（10 個）、`PdfImageProcessorTest`（13 個）、`EpubFxlScalerTest`（7 個）共 30 個測試全數通過（確認 Step 1-3 的編輯沒有波及其他既有測試）。

- [ ] **Step 5：真機回歸驗證（integration_test）**

列出可用的真實裝置/模擬器：

```bash
flutter devices
```

於 `app/` 目錄，針對既有涵蓋 PDF Fit 模式／智慧自動裁切／手動裁切的真機測試執行回歸（`-d <device-id>` 依上一步列出的裝置代號替換）：

```bash
flutter test integration_test/reader_screen_test.dart -d <device-id>
flutter test integration_test/pdf_reader_view_test.dart -d <device-id>
```

Expected：全部測試皆通過，尤其留意以下涵蓋本次改動的既有測試（測試名稱不變，行為應與改動前完全一致）：

- `PDF 切換三種 Fit 模式，畫面持續渲染成功、無 onError`（涵蓋 `applyFitMode()` 三個 enum 分支）
- `調整 PDF Fit 模式後關閉重開該書，設定被正確記住`（涵蓋 `openBook()` 的 `fromWireValue()` 解析）
- `PDF 切換至智慧自動裁切，畫面持續渲染成功、無 onError`（涵蓋 `renderCurrentPage()` 的 `AUTO_DETECT` 比對）
- `智慧自動裁切計算後關閉重開該書，pdf_crop_rect 不重新計算（值一致）`
- `PDF 進入手動裁切互動模式後，翻頁手勢暫停回應（不觸發頁面錯誤或意外離開裁切模式）`
- `PDF 手動裁切拖拉四角控制點確認後，pdf_crop_mode/pdf_crop_rect 正確寫入且畫面套用新裁切結果`（涵蓋 `enterCropEditMode()` 回呼賦值 `PdfCropMode.MANUAL`）

若測試失敗，先確認失敗原因是否為本次改動造成的行為差異（例如 `fromWireValue()` 字面值謄寫錯誤、`when` 分支對應錯誤的 enum 值），而非既有已知限制。

- [ ] **Step 6：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt
git commit -m "refactor(epic-4): PdfReaderView fitMode/cropMode 改用 Kotlin enum，Primitive Obsession 技術債清償完成"
```

---

## Self-Review

**Spec coverage：** `docs/epics.md`「`PdfReaderView.kt` `fitMode`/`cropMode` 改用 Kotlin enum 取代 String」列與 `issues.md` Issue 10 要求的兩個欄位（`fitMode`、`cropMode`）皆有對應 Task（Task 1/Task 2 新增 enum 定義，Task 3 完成所有呼叫端切換），且 Task 3 涵蓋原始碼審查提到的具體範例（`cropMode == "autoDetect"`）。

**Placeholder scan：** 已逐一檢查，所有 Step 皆含完整可執行程式碼與明確指令/預期輸出，無 TBD／「依需要調整」等佔位敘述。

**Type consistency：** `PdfReaderView.PdfFitMode`（值 `PAGE_FIT`／`FIT_WIDTH`／`ACTUAL_SIZE`）／`PdfReaderView.PdfCropMode`（值 `NONE`／`AUTO_DETECT`／`MANUAL`）的列舉值命名，在 Task 1-2（定義處＋測試）與 Task 3（欄位型別、`fromWireValue()` 呼叫、`when` 分支）皆一致核對過；`fitMode: PdfFitMode`／`cropMode: PdfCropMode` 欄位型別與既有下游用法（`cropRect`／`cropEditModeActive` 等其他欄位、`PdfImageProcessor` 呼叫）不衝突，未變動其他欄位型別。

**Method Channel 契約：** 已於 Global Constraints 明確記錄 Dart 端 `.name` 序列化格式與 Map key 名稱完全不變，`app/lib/` 底下零改動；已用 grep 確認 `fitMode`／`cropMode` 僅在 `PdfReaderView.kt` 內被使用（`CropOverlayView.kt` 及其餘原生檔案皆無參照），本計劃範圍完整、無遺漏呼叫點。

**與 Epic 16 的關係：** 本 issue 是純技術債清償，範圍與 `epic-16-dual-page` 無重疊；`docs/epics.md` 原始 Backlog 列記錄「待 Epic 16 PDF 側 issue 完成後再做，避免撞同一段程式碼」，本計劃是人類明確決定提前執行以減少帶入 Epic 16 的技術債——Epic 16 PDF 側 issue（`renderCurrentPage()`→`renderCurrentSpread()` 改寫）開工時將直接看到型別安全的 enum，不需要再處理字串比對。

---

**Plan complete and saved to `docs/epics/epic-4-pdf-enhance/plans/plan-issue-10.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - 逐一 Task 派遣獨立 subagent 實作，每個 Task 完成後審查、快速迭代

**2. Inline Execution** - 在本 session 內依 Task 順序批次執行，設檢查點供人工確認

**Which approach？**
