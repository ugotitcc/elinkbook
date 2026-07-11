# Epic 4 Issue 8：PdfReaderView.kt 影像處理邏輯抽離為 PdfImageProcessor 實作計劃

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `PdfReaderView.kt` 內與 Android View 樹/MethodChannel 無關的像素級影像處理邏輯（智慧裁切邊界偵測、加粗型態學膨脹、對比度/亮度 ColorMatrix 計算）抽離成獨立的 pure-Kotlin 物件 `PdfImageProcessor`，並讓其中的核心演算法可在純 JVM 環境（`app/src/test`）直接單元測試，不需要真機/模擬器。

**Architecture:** 新建 `PdfImageProcessor`（Kotlin `object`，位於與 `PdfReaderView` 相同套件 `cc.ugotit.elinkbook`）。對外（供 `PdfReaderView` 呼叫）維持 `Bitmap` 輸入輸出的公開函式（`detectCropRect`／`applyBoldEffect`／`dilate`／`contrastBrightnessColorMatrix`），但每個函式內部把真正的像素運算拆成不觸碰 `Bitmap` 的 `internal` 純函式（`detectCropRectFromPixels`／`dilatePixels`，皆以 `IntArray` + 寬高作為輸入輸出）——這才是能被 JVM 單元測試直接呼叫、不需要 Robolectric 或任何 Android 框架模擬的部分。`CropRect` 資料類別隨影像處理邏輯一併從 `PdfReaderView` 搬到 `PdfImageProcessor`，`PdfReaderView.kt`／`CropOverlayView.kt` 皆改參照 `PdfImageProcessor.CropRect`（同套件不需 import）。這是抽離重構，不是新功能——所有既有行為（真機視覺效果、method channel 契約、資料流時序）必須維持逐位元組一致。

**Tech Stack:** Kotlin（Android 原生端）、JUnit 4（新增的 JVM 單元測試框架）、Gradle（`app/android` 模組既有 AGP + Kotlin plugin 設定）。

## Global Constraints

- 這是抽離重構，不是新功能：`PdfImageProcessor` 內的演算法邏輯（膨脹核心迴圈、裁切邊界掃描迴圈、ColorMatrix 公式）必須與 `PdfReaderView.kt` 現有實作逐行等價——不得在搬移過程中「順手」調整演算法、常數或行為，即使發現看起來可以改進的地方。**唯一明確授權的例外**：`applyBoldEffect()` 新增 `working !== source`／`dilated !== result` 的 `recycle()` 防禦性判斷（Task 1 Step 4）——這是修正一個原本就存在於 `PdfReaderView.kt` 舊實作的潛在 Fatal Crash（`Bitmap.createScaledBitmap()` 在目的地尺寸與來源完全相同時，Android SDK 會直接回傳來源實例本身，未加防禦的 `recycle()` 會誤將呼叫端仍持有的來源 Bitmap 一併釋放），依 `tmp/epic-4/reviews/plan-issue-8-review.md` 2.1（唯一列為 🔴 必須修正的發現）加入，對任何正常尺寸輸入的既有行為零影響。
- 本計劃已依 `tmp/epic-4/reviews/plan-issue-8-review.md` 審查意見修訂：2.1（`Bitmap.recycle()` 防禦性判斷）已採納；3.2（補齊全黑網格／單點內容／1×1 極端尺寸三項邊界測試）已採納，見 Task 1/Task 2；3.1（欄掃描的 cache miss 效能，審查本身結論為「不需調整演算法，僅需註解備忘」）已採納為程式碼註解，未變更演算法。
- 新增的 JVM 單元測試一律針對 `internal` 的 `IntArray`-based 純函式（`detectCropRectFromPixels`／`dilatePixels`），不引入 Robolectric 或任何 Android 框架模擬依賴——`Bitmap` 相關的薄包裝函式（`detectCropRect`／`dilate`／`applyBoldEffect`）本身不新增自動化測試，其正確性由 Task 4 的既有真機 `integration_test` 回歸把關（沿用 Epic 4 Issue 3-7 既有測試，見 Task 4）。
- 本次刻意不處理、維持現狀的既有技術債（範圍不重疊，見 `docs/epics.md`）：
  - `density.coerceIn(2.0f, 3.0f)` 縮放係數重複、`bitmap.eraseColor(Color.WHITE)` 白底邏輯重複——這些出現在 `renderCurrentPage()`/`renderFullPageForCropPreview()`/`applyFitMode()` 的 PDF 頁面渲染/縮放邏輯裡，不屬於本次抽離範圍（智慧裁切/加粗/濾鏡的像素處理邏輯）。
  - `fitMode`/`cropMode` 改用 Kotlin enum 取代 `String`——已在 `docs/epics.md` 明確記錄「待 Epic 16 PDF 側 issue 完成後再做」，本計劃不動這兩個欄位的型別。
- 測試指令慣例：Dart 測試用 `flutter test`（於 `app/` 目錄執行）；本計劃新增的原生 JVM 單元測試改用 Gradle `./gradlew testDebugUnitTest`（於 `app/android` 目錄執行）——這是本專案第一次新增原生 Kotlin 單元測試，過去 `PdfReaderView.kt`/`CropOverlayView.kt` 的原生邏輯只能靠 `integration_test` 真機驗證（見 `issues.md` Issue 2/6 的「已知測試限制」）；`app/android/gradlew`／`gradlew.bat` 是 `.gitignore` 排除的產物（Flutter 首次建置時自動產生），若尚不存在，先於 `app/` 目錄執行一次 `flutter build apk --debug` 讓 Flutter 產生 wrapper 檔案。
- `minSdk = 24`（見專案 `CLAUDE.md`）：本計劃不涉及 API level 相關邏輯變動，`dilatePixels`/`detectCropRectFromPixels` 皆為純整數運算，不引用任何有 API 版本門檻的 Android API。

---

## File Structure

- **Create** `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt`：新的 pure-Kotlin 影像處理模組，見上方 Architecture。
- **Create** `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfImageProcessorTest.kt`：針對 `PdfImageProcessor` 的 JVM 單元測試（不需要真機/模擬器）。這是本專案第一個 `app/src/test` 目錄/檔案，需要新建目錄結構。
- **Modify** `app/android/app/build.gradle.kts`：新增 `testImplementation("junit:junit:4.13.2")`。
- **Modify** `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`：移除已抽離的 `CropRect` 資料類別、`detectCropRect()`／`applyBoldEffect()`／`dilate()` 私有方法、`BOLD_DOWNSCALE_FACTOR`／`BOLD_MAX_RADIUS` 常數（連同其所在的 `companion object` 區塊，抽離後該區塊已無其他內容）；呼叫端改為 `PdfImageProcessor.xxx(...)`；`applyFilters()` 改呼叫 `PdfImageProcessor.contrastBrightnessColorMatrix(...)` 取代原本內嵌的 `FloatArray` 建構。
- **Modify** `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/CropOverlayView.kt`：5 處 `PdfReaderView.CropRect` 型別參照改為 `PdfImageProcessor.CropRect`。

---

### Task 1：JUnit 測試框架設定 ＋ 型態學膨脹（dilate）像素核心抽離

**Files:**
- Modify: `app/android/app/build.gradle.kts:60-70`（`dependencies` 區塊）
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt`
- Create: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfImageProcessorTest.kt`

**Interfaces:**
- Produces：`PdfImageProcessor`（`object`，套件 `cc.ugotit.elinkbook`）：
  - `internal fun dilatePixels(pixels: IntArray, width: Int, height: Int, radius: Int): IntArray`——純像素陣列膨脹核心，Task 2/3 會在同一個檔案內繼續新增函式。
  - `fun dilate(bitmap: Bitmap, radius: Int): Bitmap`——`Bitmap` 薄包裝，內部呼叫 `dilatePixels`。
  - `fun applyBoldEffect(source: Bitmap, strength: Float): Bitmap`——加粗效果的完整入口（縮小工作尺寸 → `dilate` →放大），供 Task 4 的 `PdfReaderView.kt` 呼叫端使用。

- [ ] **Step 1：新增 JUnit 測試依賴**

編輯 `app/android/app/build.gradle.kts`，在既有 `dependencies { ... }` 區塊末尾新增一行：

```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    implementation("org.readium.kotlin-toolkit:readium-shared:3.3.0")
    implementation("org.readium.kotlin-toolkit:readium-streamer:3.3.0")
    implementation("org.readium.kotlin-toolkit:readium-navigator:3.3.0")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("androidx.fragment:fragment-ktx:1.8.9")
    implementation("androidx.documentfile:documentfile:1.0.1")

    testImplementation("junit:junit:4.13.2")
}
```

- [ ] **Step 2：寫失敗測試（dilatePixels）**

建立 `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfImageProcessorTest.kt`（新目錄）：

```kotlin
package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Test

class PdfImageProcessorTest {

    companion object {
        private const val WHITE = -0x1 // 0xFFFFFFFF.toInt()
        private const val BLACK = -0x1000000 // 0xFF000000.toInt()
        private const val SEMI_TRANSPARENT_WHITE = -0x55000001 // 0xAAFFFFFF.toInt()
    }

    private fun buildPixels(
        width: Int,
        height: Int,
        colorAt: (x: Int, y: Int) -> Int,
    ): IntArray {
        val pixels = IntArray(width * height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                pixels[y * width + x] = colorAt(x, y)
            }
        }
        return pixels
    }

    // ---- dilatePixels ----

    @Test
    fun `radius 為 0 時 dilatePixels 是恆等變換`() {
        val pixels = buildPixels(3, 3) { x, y -> if (x == 1 && y == 1) BLACK else WHITE }

        val result = PdfImageProcessor.dilatePixels(pixels, width = 3, height = 3, radius = 0)

        assertEquals(pixels.toList(), result.toList())
    }

    @Test
    fun `radius 為 1 時單一中心黑點在 3x3 網格內擴散至全部像素，且每個像素保留自身原始 alpha`() {
        // (0,0) 刻意用半透明白色，驗證膨脹後的 alpha 是「自身原始值」而非鄰域最小值。
        val pixels = buildPixels(3, 3) { x, y ->
            when {
                x == 0 && y == 0 -> SEMI_TRANSPARENT_WHITE
                x == 1 && y == 1 -> BLACK
                else -> WHITE
            }
        }

        val result = PdfImageProcessor.dilatePixels(pixels, width = 3, height = 3, radius = 1)

        // 中心黑點的 3x3 鄰域（radius=1，邊界 coerceIn 夾取）在這個網格大小下，
        // 涵蓋了每一個像素的鄰域查詢範圍，因此全部 9 個像素的 RGB 都被拉黑。
        assertEquals(-0x55000000, result[0 * 3 + 0]) // (0,0)：alpha=0xAA 保留，RGB 變黑 → 0xAA000000
        assertEquals(BLACK, result[1 * 3 + 1]) // (1,1) 中心：alpha=0xFF 保留，RGB 仍黑
        assertEquals(BLACK, result[2 * 3 + 2]) // (2,2) 對角遠端：alpha=0xFF 保留，RGB 被拉黑
    }

    @Test
    fun `寬高為 1 的極端尺寸下 dilatePixels 不拋出例外，結果等同單像素恆等`() {
        // 對應 applyBoldEffect() 內 Bitmap.createScaledBitmap() 短路回傳同一
        // 實例的邊界情境（見 Task 1 Step 4 的 recycle() 防禦性判斷）：來源
        // 寬高皆為 1px 時，coerceIn(0, 0) 讓鄰域掃描永遠落在唯一的 (0,0)
        // 像素，不論 radius 多大都不會索引越界。
        val pixels = intArrayOf(BLACK)

        val result = PdfImageProcessor.dilatePixels(pixels, width = 1, height = 1, radius = 3)

        assertEquals(listOf(BLACK), result.toList())
    }
}
```

- [ ] **Step 3：執行測試確認失敗（編譯錯誤，`PdfImageProcessor` 尚不存在）**

於 `app/android` 目錄執行：

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfImageProcessorTest"
```

（若 `./gradlew` 不存在：先於 `app/` 目錄執行一次 `flutter build apk --debug`，讓 Flutter 產生 `app/android/gradlew`／`gradlew.bat`，再重新執行上述指令。）

Expected：編譯失敗，錯誤訊息包含 `unresolved reference: PdfImageProcessor`。

- [ ] **Step 4：實作 PdfImageProcessor.kt（本步驟只含 dilatePixels/dilate/applyBoldEffect 與其常數）**

建立 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt`：

```kotlin
package cc.ugotit.elinkbook

import android.graphics.Bitmap

/**
 * PdfReaderView 用到的像素級影像處理邏輯：智慧自動裁切邊界偵測、加粗（型態學
 * 膨脹）、對比度/亮度 ColorMatrix 計算。從 PdfReaderView.kt 抽離而成的
 * pure-Kotlin 模組（見 docs/epics.md「PdfReaderView.kt 影像處理邏輯抽離為
 * PdfImageProcessor」列、docs/epics/epic-4-pdf-enhance/plans/plan-issue-8.md）：
 * 不依賴 Android View 樹、Context 或 MethodChannel，公開函式只透過 Bitmap
 * 輸入輸出；核心像素運算（見 internal 函式）進一步拆成 IntArray-based 的
 * 純函式，可在純 JVM 單元測試（app/src/test）直接以固定像素陣列驗證，不需要
 * 真機/模擬器即可執行。
 */
object PdfImageProcessor {

    // 加粗（型態學膨脹）運算的效能策略常數：對縮小版工作副本做膨脹，而非對
    // 全解析度 bitmap 直接運算（見 docs/archive/2026-07-10-epic-3-fonts-layout/
    // 之前的 epic-4-pdf-enhance Issue 4「演算法決策」）。
    private const val BOLD_DOWNSCALE_FACTOR = 0.25f
    private const val BOLD_MAX_RADIUS = 3

    /**
     * 型態學膨脹（加粗），對 [source] 做「取鄰域內最小亮度值」的膨脹運算，
     * 讓深色筆畫（文字）向外擴張、變粗變黑。[strength] 為 0..1，對應原
     * BookReaderPrefs.pdfBoldStrength 契約。
     *
     * 效能策略：先縮小到 [BOLD_DOWNSCALE_FACTOR] 工作尺寸做膨脹運算，再放大
     * 回原尺寸，避免對全解析度 bitmap 直接做二維鄰域掃描造成明顯延遲。
     */
    fun applyBoldEffect(source: Bitmap, strength: Float): Bitmap {
        val workWidth = (source.width * BOLD_DOWNSCALE_FACTOR).toInt().coerceAtLeast(1)
        val workHeight = (source.height * BOLD_DOWNSCALE_FACTOR).toInt().coerceAtLeast(1)
        val working = Bitmap.createScaledBitmap(source, workWidth, workHeight, true)
        val radius = (strength * BOLD_MAX_RADIUS).toInt().coerceIn(1, BOLD_MAX_RADIUS)
        val dilated = dilate(working, radius)
        val result = Bitmap.createScaledBitmap(dilated, source.width, source.height, true)
        // Bitmap.createScaledBitmap() 在目的地尺寸與來源完全相同時，Android
        // SDK 會直接回傳來源實例本身（省略複製，見 Bitmap.createBitmap(src,
        // x, y, w, h, matrix, filter) 原始碼：整張複製且矩陣為單位矩陣時直接
        // return source）。若不加防禦判斷，working.recycle() 可能誤將呼叫端
        // 仍持有的 source 一併釋放，dilated.recycle() 同理可能誤釋放正要回傳
        // 的 result，導致「Canvas: trying to use a recycled bitmap」的 Fatal
        // Crash。僅在來源寬高皆為 1px（BOLD_DOWNSCALE_FACTOR=0.25f 搭配
        // coerceAtLeast(1) 時的極端邊界，例如使用者手動裁切框選到極小範圍）
        // 才會觸發，但修正成本為零，見 tmp/epic-4/reviews/plan-issue-8-review.md
        // 2.1。
        if (working !== source) {
            working.recycle()
        }
        if (dilated !== result) {
            dilated.recycle()
        }
        return result
    }

    /** 對 [bitmap] 做半徑 [radius] 的膨脹，見 [dilatePixels]。*/
    fun dilate(bitmap: Bitmap, radius: Int): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        val result = dilatePixels(pixels, width, height, radius)
        val out = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        out.setPixels(result, 0, width, 0, 0, width, height)
        return out
    }

    /** [dilate] 的純像素陣列核心，可脫離 Bitmap 直接單元測試：對 [pixels]
     * 做半徑 [radius] 的膨脹（取 (2*radius+1)^2 鄰域內每個色版的最小值，讓
     * 深色像素向外擴張）。邊界像素以 coerceIn 夾到合法範圍內（等同邊緣複製，
     * 非補零），避免邊框產生非預期的暗色/亮色偽影。每個輸出像素的 alpha
     * 沿用其「自身」原始像素的 alpha（不受鄰域影響）。*/
    internal fun dilatePixels(pixels: IntArray, width: Int, height: Int, radius: Int): IntArray {
        val result = IntArray(width * height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                var minR = 255
                var minG = 255
                var minB = 255
                for (dy in -radius..radius) {
                    val ny = (y + dy).coerceIn(0, height - 1)
                    for (dx in -radius..radius) {
                        val nx = (x + dx).coerceIn(0, width - 1)
                        val p = pixels[ny * width + nx]
                        val r = (p shr 16) and 0xFF
                        val g = (p shr 8) and 0xFF
                        val b = p and 0xFF
                        if (r < minR) minR = r
                        if (g < minG) minG = g
                        if (b < minB) minB = b
                    }
                }
                val a = (pixels[y * width + x] shr 24) and 0xFF
                result[y * width + x] = (a shl 24) or (minR shl 16) or (minG shl 8) or minB
            }
        }
        return result
    }
}
```

- [ ] **Step 5：執行測試確認通過**

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfImageProcessorTest"
```

Expected：`BUILD SUCCESSFUL`，3 個測試（`radius 為 0 時...`／`radius 為 1 時...`／`寬高為 1 的極端尺寸下...`）皆通過。

- [ ] **Step 6：Commit**

```bash
git add app/android/app/build.gradle.kts \
        app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt \
        app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfImageProcessorTest.kt
git commit -m "feat(epic-4): 新增 PdfImageProcessor 與 JVM 單元測試框架，先抽離加粗型態學膨脹核心"
```

---

### Task 2：智慧自動裁切邊界偵測（detectCropRect）像素核心抽離

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt`（Task 1 建立的檔案，新增 `CropRect`／`detectCropRect`／`detectCropRectFromPixels`）
- Modify: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfImageProcessorTest.kt`（Task 1 建立的檔案，新增測試）

**Interfaces:**
- Consumes：無（獨立於 Task 1 的 `dilatePixels`/`dilate`/`applyBoldEffect`）。
- Produces：
  - `PdfImageProcessor.CropRect`（`data class`，欄位 `left`／`top`／`right`／`bottom: Float`，相對座標 0.0-1.0）——Task 4 會把 `PdfReaderView.kt`／`CropOverlayView.kt` 對 `PdfReaderView.CropRect` 的參照改指向這裡。
  - `fun detectCropRect(bitmap: Bitmap): CropRect`
  - `internal fun detectCropRectFromPixels(pixels: IntArray, width: Int, height: Int): CropRect`

- [ ] **Step 1：寫失敗測試（detectCropRectFromPixels）**

在 `PdfImageProcessorTest.kt` 的 `class PdfImageProcessorTest { ... }` 內、`dilatePixels` 測試群組後面新增：

```kotlin
    // ---- detectCropRectFromPixels ----

    @Test
    fun `10x10 網格中央 6x6 黑色區塊被正確偵測為裁切邊界（含 1% 邊距）`() {
        // 列/行 2..7（含）為黑色內容區塊，其餘為純白背景。
        val pixels = buildPixels(10, 10) { x, y ->
            if (x in 2..7 && y in 2..7) BLACK else WHITE
        }

        val result = PdfImageProcessor.detectCropRectFromPixels(pixels, width = 10, height = 10)

        assertEquals(0.19f, result.left, 1e-4f)
        assertEquals(0.19f, result.top, 1e-4f)
        assertEquals(0.71f, result.right, 1e-4f)
        assertEquals(0.71f, result.bottom, 1e-4f)
    }

    @Test
    fun `全白網格（無內容）時掃描收斂到角落退化矩形，不拋例外`() {
        val pixels = buildPixels(10, 10) { _, _ -> WHITE }

        val result = PdfImageProcessor.detectCropRectFromPixels(pixels, width = 10, height = 10)

        // 掃描迴圈找不到任何內容列/行時，left/top 會一路走到 width-1/height-1，
        // right/bottom 則因迴圈條件 `right > left` 立刻停在同一個值——這是既有
        // 演算法在全白頁面上的既存行為（非本次重構新增），此測試鎖定該行為，
        // 避免未來修改時無意間改變（是否需要優化留待未來另立 issue 評估）。
        assertEquals(0.89f, result.left, 1e-4f)
        assertEquals(0.89f, result.top, 1e-4f)
        assertEquals(0.91f, result.right, 1e-4f)
        assertEquals(0.91f, result.bottom, 1e-4f)
    }

    @Test
    fun `全黑網格時內容從四邊緣即被偵測到，left top 因負邊距被 coerceIn 夾到 0`() {
        val pixels = buildPixels(10, 10) { _, _ -> BLACK }

        val result = PdfImageProcessor.detectCropRectFromPixels(pixels, width = 10, height = 10)

        // 每一列/行在第一個取樣點（x=0／y=0）就偵測到內容，掃描迴圈的「往內
        // 收縮」條件從未成立：top/left 停在初始值 0，bottom/right 停在初始值
        // width-1/height-1=9（與「全白網格」情境的終值數字上相同，但成因相
        // 反——全白是「掃到底找不到內容」，全黑是「一開始就找到內容不必再
        // 掃」）。relLeft/relTop 因此為 0 - CROP_MARGIN，驗證 coerceIn(0f, 1f)
        // 下限確實生效。
        assertEquals(0f, result.left, 1e-4f)
        assertEquals(0f, result.top, 1e-4f)
        assertEquals(0.91f, result.right, 1e-4f)
        assertEquals(0.91f, result.bottom, 1e-4f)
    }

    @Test
    fun `唯一內容像素落在原點時四邊掃描收斂到同一列行，驗證邊距下限與掃描步進`() {
        val pixels = buildPixels(10, 10) { x, y -> if (x == 0 && y == 0) BLACK else WHITE }

        val result = PdfImageProcessor.detectCropRectFromPixels(pixels, width = 10, height = 10)

        // 全圖只有 (0,0) 這一個內容像素，恰好同時是 isRowContent／isColContent
        // 的第一個取樣點（x=0／y=0，不受 CROP_SCAN_STEP=4 跳步影響，證明
        // (0,0) 這個邊界情況不會被跳步掃描漏掉）。因為這是唯一含內容的列與
        // 行，「由上往下找內容列」與「由下往上找內容列」都收斂在同一列
        // （top=bottom=0），左右掃描同理（left=right=0）；relLeft/relTop 的
        // 下限被 coerceIn(0f, 1f) 夾到 0，relRight/relBottom 則是
        // (0/10 + CROP_MARGIN) = 0.01。
        assertEquals(0f, result.left, 1e-4f)
        assertEquals(0f, result.top, 1e-4f)
        assertEquals(0.01f, result.right, 1e-4f)
        assertEquals(0.01f, result.bottom, 1e-4f)
    }
```

在檔案頂端 `import org.junit.Assert.assertEquals` 旁新增：

```kotlin
import org.junit.Assert.assertEquals
```

（已存在，不需重複新增；上面的兩個新測試沿用同一個 import。）

- [ ] **Step 2：執行測試確認失敗**

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfImageProcessorTest"
```

Expected：編譯失敗，錯誤訊息包含 `unresolved reference: detectCropRectFromPixels`。

- [ ] **Step 3：在 PdfImageProcessor.kt 新增 CropRect／detectCropRect／detectCropRectFromPixels**

編輯 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt`，在 `object PdfImageProcessor {` 開頭（`BOLD_DOWNSCALE_FACTOR` 常數之前）新增 `CropRect` 資料類別與裁切掃描常數：

```kotlin
object PdfImageProcessor {

    /** 裁切矩形（相對座標 0.0-1.0）。原本是 PdfReaderView 的巢狀類別，隨影像
     * 處理邏輯一併移至此處——CropOverlayView.kt 與 PdfReaderView.kt 皆改參照
     * PdfImageProcessor.CropRect。*/
    data class CropRect(val left: Float, val top: Float, val right: Float, val bottom: Float)

    // 智慧自動裁切邊界偵測參數，見 detectCropRectFromPixels() 演算法說明。
    private const val CROP_WHITE_THRESHOLD = 245
    private const val CROP_MARGIN = 0.01f
    private const val CROP_SCAN_STEP = 4

    // 加粗（型態學膨脹）運算的效能策略常數：對縮小版工作副本做膨脹，而非對
    // 全解析度 bitmap 直接運算（見 docs/archive/2026-07-10-epic-3-fonts-layout/
    // 之前的 epic-4-pdf-enhance Issue 4「演算法決策」）。
    private const val BOLD_DOWNSCALE_FACTOR = 0.25f
    private const val BOLD_MAX_RADIUS = 3
```

並在 `applyBoldEffect`／`dilate`／`dilatePixels` 之後（檔案最後）新增：

```kotlin
    /**
     * 智慧自動裁切邊界偵測：由四個邊緣向內掃描，找第一個「非全白」的列/行
     * 視為內容邊界，加一點邊距避免裁得太緊。單頁取樣，每 [CROP_SCAN_STEP]
     * 個像素跳著檢查一次以加速掃描。
     */
    fun detectCropRect(bitmap: Bitmap): CropRect {
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        return detectCropRectFromPixels(pixels, width, height)
    }

    /** [detectCropRect] 的純像素陣列核心，可脫離 Bitmap 直接單元測試。
     * [pixels] 為 row-major、每個元素是 ARGB 打包後的 Int（與
     * Bitmap.getPixels() 的輸出格式一致）。*/
    internal fun detectCropRectFromPixels(pixels: IntArray, width: Int, height: Int): CropRect {
        fun isRowContent(y: Int): Boolean {
            var x = 0
            while (x < width) {
                val p = pixels[y * width + x]
                val minChannel = minOf((p shr 16) and 0xFF, (p shr 8) and 0xFF, p and 0xFF)
                if (minChannel < CROP_WHITE_THRESHOLD) return true
                x += CROP_SCAN_STEP
            }
            return false
        }

        // 注意：pixels 是 row-major 陣列，這裡以固定 x、遞增 y 做縱向掃描，
        // 記憶體存取並非連續（每次跳整個 width），會比同一橫向掃描多出
        // cache miss。維持現狀不調整演算法——單頁只在渲染或進入裁切模式時
        // 執行一次，且 CROP_SCAN_STEP 已跳步採樣，效能影響可忽略（見
        // tmp/epic-4/reviews/plan-issue-8-review.md 3.1）。
        fun isColContent(x: Int): Boolean {
            var y = 0
            while (y < height) {
                val p = pixels[y * width + x]
                val minChannel = minOf((p shr 16) and 0xFF, (p shr 8) and 0xFF, p and 0xFF)
                if (minChannel < CROP_WHITE_THRESHOLD) return true
                y += CROP_SCAN_STEP
            }
            return false
        }

        var top = 0
        while (top < height - 1 && !isRowContent(top)) top++
        var bottom = height - 1
        while (bottom > top && !isRowContent(bottom)) bottom--
        var left = 0
        while (left < width - 1 && !isColContent(left)) left++
        var right = width - 1
        while (right > left && !isColContent(right)) right--

        val relLeft = (left.toFloat() / width - CROP_MARGIN).coerceIn(0f, 1f)
        val relTop = (top.toFloat() / height - CROP_MARGIN).coerceIn(0f, 1f)
        val relRight = (right.toFloat() / width + CROP_MARGIN).coerceIn(0f, 1f)
        val relBottom = (bottom.toFloat() / height + CROP_MARGIN).coerceIn(0f, 1f)
        return CropRect(relLeft, relTop, relRight, relBottom)
    }
```

- [ ] **Step 4：執行測試確認通過**

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfImageProcessorTest"
```

Expected：`BUILD SUCCESSFUL`，7 個測試（Task 1 的 3 個 + 本 Task 的 4 個）皆通過。

- [ ] **Step 5：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt \
        app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfImageProcessorTest.kt
git commit -m "feat(epic-4): PdfImageProcessor 新增智慧裁切邊界偵測（detectCropRect）像素核心"
```

---

### Task 3：對比度／亮度 ColorMatrix 計算抽離

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt`
- Modify: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfImageProcessorTest.kt`

**Interfaces:**
- Consumes：無。
- Produces：`fun contrastBrightnessColorMatrix(contrast: Float, brightness: Float): FloatArray`——回傳值可直接傳入 `android.graphics.ColorMatrix(FloatArray)` 建構子；Task 4 的 `PdfReaderView.applyFilters()` 會呼叫這個函式。

- [ ] **Step 1：寫失敗測試**

在 `PdfImageProcessorTest.kt` 新增（同一個 `class` 內，接續 Task 2 的測試群組）：

```kotlin
    // ---- contrastBrightnessColorMatrix ----

    @Test
    fun `contrast 與 brightness 皆為 0 時回傳單位矩陣（無視覺變化）`() {
        val matrix = PdfImageProcessor.contrastBrightnessColorMatrix(contrast = 0f, brightness = 0f)

        val expected = floatArrayOf(
            1f, 0f, 0f, 0f, 0f,
            0f, 1f, 0f, 0f, 0f,
            0f, 0f, 1f, 0f, 0f,
            0f, 0f, 0f, 1f, 0f,
        )
        assertArrayEquals(expected, matrix, 1e-4f)
    }

    @Test
    fun `contrast=50 brightness=20 時依標準公式算出對應的 ColorMatrix 係數`() {
        val matrix = PdfImageProcessor.contrastBrightnessColorMatrix(contrast = 50f, brightness = 20f)

        // contrastFactor = (100+50)/100 = 1.5
        // brightnessOffset = 20 * 2.55 = 51.0
        // translate = 51.0 + (255 - 1.5*255)/2 = 51.0 - 63.75 = -12.75
        val expected = floatArrayOf(
            1.5f, 0f, 0f, 0f, -12.75f,
            0f, 1.5f, 0f, 0f, -12.75f,
            0f, 0f, 1.5f, 0f, -12.75f,
            0f, 0f, 0f, 1f, 0f,
        )
        assertArrayEquals(expected, matrix, 1e-4f)
    }
```

在檔案頂端 import 區塊新增 `assertArrayEquals`：

```kotlin
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
```

- [ ] **Step 2：執行測試確認失敗**

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfImageProcessorTest"
```

Expected：編譯失敗，錯誤訊息包含 `unresolved reference: contrastBrightnessColorMatrix`。

- [ ] **Step 3：在 PdfImageProcessor.kt 新增 contrastBrightnessColorMatrix**

在 `PdfImageProcessor.kt` 檔案最後（`detectCropRectFromPixels` 之後）新增：

```kotlin
    /**
     * 標準對比度/亮度 ColorMatrix 公式：先以 127.5（8-bit 色階灰階中點）為
     * 軸心縮放對比度，再疊加亮度位移，確保 contrast=0／brightness=0 時是
     * 單位矩陣（無視覺變化）。回傳值可直接傳入
     * android.graphics.ColorMatrix(FloatArray) 建構子。
     */
    fun contrastBrightnessColorMatrix(contrast: Float, brightness: Float): FloatArray {
        val contrastFactor = (100f + contrast) / 100f // -100→0.0，0→1.0，100→2.0
        val brightnessOffset = brightness * 2.55f // -100..100 映射到約 -255..255 的像素位移範圍
        val translate = brightnessOffset + (255f - contrastFactor * 255f) / 2f
        return floatArrayOf(
            contrastFactor, 0f, 0f, 0f, translate,
            0f, contrastFactor, 0f, 0f, translate,
            0f, 0f, contrastFactor, 0f, translate,
            0f, 0f, 0f, 1f, 0f,
        )
    }
```

- [ ] **Step 4：執行測試確認通過**

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfImageProcessorTest"
```

Expected：`BUILD SUCCESSFUL`，9 個測試全數通過。

- [ ] **Step 5：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfImageProcessor.kt \
        app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfImageProcessorTest.kt
git commit -m "feat(epic-4): PdfImageProcessor 新增對比度/亮度 ColorMatrix 計算，抽離工作全數完成"
```

---

### Task 4：PdfReaderView.kt／CropOverlayView.kt 改用 PdfImageProcessor，刪除重複的私有實作，真機回歸驗證

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/CropOverlayView.kt`

**Interfaces:**
- Consumes：`PdfImageProcessor.CropRect`／`PdfImageProcessor.detectCropRect(Bitmap): CropRect`／`PdfImageProcessor.applyBoldEffect(Bitmap, Float): Bitmap`／`PdfImageProcessor.contrastBrightnessColorMatrix(Float, Float): FloatArray`（皆為 Task 1-3 產出）。
- Produces：無新公開介面——本 Task 純粹是呼叫端切換 + 刪除死碼，`PdfReaderView` 對外的 method channel 契約（`openBook`／`setPdfPreferences`／`nextPage`／`previousPage`／`enterCropEditMode`／`exitCropEditMode`）完全不變。

此 Task 不寫新測試（沒有新增行為），而是用既有的真機 `integration_test` 作回歸驗證——見 Step 5。

- [ ] **Step 1：修改 PdfReaderView.kt——移除 CropRect 資料類別與 companion object 常數**

刪除以下區塊（原第 91-102 行，`CropRect` 巢狀類別的文件註解＋宣告，以及緊接著的 `companion object`）：

```kotlin
    /** 裁切矩形（相對座標 0.0-1.0），Kotlin 內部用資料類別，對應 Dart
     * PdfCropRect 的欄位。套件內可見（非 private）供 CropOverlayView.kt
     * 使用（同套件 cc.ugotit.elinkbook，Kotlin 不需額外 import）。*/
    data class CropRect(val left: Float, val top: Float, val right: Float, val bottom: Float)

    companion object {
        // 加粗（型態學膨脹）運算的效能策略常數，見 spec.md/design.md「已知
        // 風險」與本 issue 計劃的「效能策略」段落：對縮小版工作副本做膨脹，
        // 而非對全解析度 bitmap 直接運算。
        private const val BOLD_DOWNSCALE_FACTOR = 0.25f
        private const val BOLD_MAX_RADIUS = 3
    }

    init {
```

改為（`CropRect`／`companion object` 皆刪除，`init` 區塊保留）：

```kotlin
    init {
```

- [ ] **Step 2：修改 PdfReaderView.kt——CropRect 型別參照改為 PdfImageProcessor.CropRect**

以下逐行替換（皆為單純型別/建構呼叫的 `CropRect` → `PdfImageProcessor.CropRect`，行為不變）：

1. 欄位宣告：
   ```kotlin
   private var cropRect: CropRect? = null
   ```
   改為：
   ```kotlin
   private var cropRect: PdfImageProcessor.CropRect? = null
   ```

2. `parseCropRect` 回傳型別與建構呼叫：
   ```kotlin
   private fun parseCropRect(raw: Any?): CropRect? {
       val map = raw as? Map<String, Any?> ?: return null
       val left = (map["left"] as? Number)?.toFloat() ?: return null
       val top = (map["top"] as? Number)?.toFloat() ?: return null
       val right = (map["right"] as? Number)?.toFloat() ?: return null
       val bottom = (map["bottom"] as? Number)?.toFloat() ?: return null
       return CropRect(left, top, right, bottom)
   }
   ```
   改為：
   ```kotlin
   private fun parseCropRect(raw: Any?): PdfImageProcessor.CropRect? {
       val map = raw as? Map<String, Any?> ?: return null
       val left = (map["left"] as? Number)?.toFloat() ?: return null
       val top = (map["top"] as? Number)?.toFloat() ?: return null
       val right = (map["right"] as? Number)?.toFloat() ?: return null
       val bottom = (map["bottom"] as? Number)?.toFloat() ?: return null
       return PdfImageProcessor.CropRect(left, top, right, bottom)
   }
   ```

3. `enterCropEditMode()` 內的預設矩形：
   ```kotlin
   val initial = cropRect ?: CropRect(0.1f, 0.1f, 0.9f, 0.9f)
   ```
   改為：
   ```kotlin
   val initial = cropRect ?: PdfImageProcessor.CropRect(0.1f, 0.1f, 0.9f, 0.9f)
   ```

- [ ] **Step 3：修改 PdfReaderView.kt——刪除已抽離的私有方法，呼叫端改用 PdfImageProcessor**

刪除 `detectCropRect(bitmap: Bitmap): CropRect` 私有方法整段（原第 312-361 行，含文件註解），呼叫端（`renderCurrentPage()` 內）：

```kotlin
        if (cropMode == "autoDetect" && cropRect == null) {
            val detectBitmap =
                Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
            detectBitmap.eraseColor(android.graphics.Color.WHITE)
            page.render(detectBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            val detected = detectCropRect(detectBitmap)
            detectBitmap.recycle()
```

改為（只有 `detectCropRect(detectBitmap)` → `PdfImageProcessor.detectCropRect(detectBitmap)` 這一行變動，其餘不動）：

```kotlin
        if (cropMode == "autoDetect" && cropRect == null) {
            val detectBitmap =
                Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
            detectBitmap.eraseColor(android.graphics.Color.WHITE)
            page.render(detectBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            val detected = PdfImageProcessor.detectCropRect(detectBitmap)
            detectBitmap.recycle()
```

刪除 `applyBoldEffect(source: Bitmap): Bitmap` 與 `dilate(bitmap: Bitmap, radius: Int): Bitmap` 兩個私有方法整段（原第 543-601 行，含文件註解）。`renderCurrentPage()` 內的呼叫端：

```kotlin
            val finalBitmap = if (boldStrength > 0f) applyBoldEffect(bitmap) else bitmap
```

改為：

```kotlin
            val finalBitmap = if (boldStrength > 0f) PdfImageProcessor.applyBoldEffect(bitmap, boldStrength) else bitmap
```

- [ ] **Step 4：修改 PdfReaderView.kt——applyFilters() 改用 PdfImageProcessor.contrastBrightnessColorMatrix**

原本：

```kotlin
    private fun applyFilters() {
        val contrastFactor = (100f + contrast) / 100f // -100→0.0，0→1.0，100→2.0
        val brightnessOffset = brightness * 2.55f // -100..100 映射到約 -255..255 的像素位移範圍
        val translate = brightnessOffset + (255f - contrastFactor * 255f) / 2f
        val colorMatrix = android.graphics.ColorMatrix(
            floatArrayOf(
                contrastFactor, 0f, 0f, 0f, translate,
                0f, contrastFactor, 0f, 0f, translate,
                0f, 0f, contrastFactor, 0f, translate,
                0f, 0f, 0f, 1f, 0f,
            )
        )
        imageView.colorFilter = android.graphics.ColorMatrixColorFilter(colorMatrix)
    }
```

改為（保留函式上方原有的文件註解不動，只改函式本體）：

```kotlin
    private fun applyFilters() {
        val colorMatrix = android.graphics.ColorMatrix(
            PdfImageProcessor.contrastBrightnessColorMatrix(contrast, brightness)
        )
        imageView.colorFilter = android.graphics.ColorMatrixColorFilter(colorMatrix)
    }
```

- [ ] **Step 5：修改 CropOverlayView.kt——CropRect 型別參照改為 PdfImageProcessor.CropRect**

以下 5 處逐一替換（`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/CropOverlayView.kt`）：

1. 建構子參數（原第 30-31 行）：
   ```kotlin
       initialRelativeRect: PdfReaderView.CropRect,
       private val onConfirm: (PdfReaderView.CropRect) -> Unit,
   ```
   改為：
   ```kotlin
       initialRelativeRect: PdfImageProcessor.CropRect,
       private val onConfirm: (PdfImageProcessor.CropRect) -> Unit,
   ```

2. 欄位宣告（原第 76 行）：
   ```kotlin
       private var pendingInitialRect: PdfReaderView.CropRect? = initialRelativeRect
   ```
   改為：
   ```kotlin
       private var pendingInitialRect: PdfImageProcessor.CropRect? = initialRelativeRect
   ```

3. `currentRelativeRect()` 方法（原第 262-267 行附近）：
   ```kotlin
       private fun currentRelativeRect(): PdfReaderView.CropRect {
           ...
           return PdfReaderView.CropRect(left, top, right, bottom)
       }
   ```
   改為：
   ```kotlin
       private fun currentRelativeRect(): PdfImageProcessor.CropRect {
           ...
           return PdfImageProcessor.CropRect(left, top, right, bottom)
       }
   ```
   （方法內部其餘計算邏輯不動，只改函式簽章的回傳型別與 `return` 那一行的建構呼叫。）

- [ ] **Step 6：靜態檢查與既有測試回歸**

於 `app/` 目錄執行：

```bash
flutter analyze
```

Expected：`No issues found!`（本 Task 未變動任何 Dart 程式碼，此步驟純粹確認沒有意外波及）。

於 `app/android` 目錄執行新增的原生單元測試，確認 Task 1-3 的邏輯仍完整可用（本 Task 沒有修改 `PdfImageProcessor.kt` 本身，此步驟是防止 Step 1-5 的編輯誤觸該檔案）：

```bash
./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfImageProcessorTest"
```

Expected：`BUILD SUCCESSFUL`，9 個測試全數通過。

- [ ] **Step 7：真機回歸驗證（integration_test）**

列出可用的真實裝置/模擬器：

```bash
flutter devices
```

於 `app/` 目錄，針對既有涵蓋加粗/裁切/濾鏡/Fit 模式的真機測試執行回歸（`-d <device-id>` 依 Step 7 列出的裝置代號替換）：

```bash
flutter test integration_test/reader_screen_test.dart -d <device-id>
flutter test integration_test/pdf_reader_view_test.dart -d <device-id>
```

Expected：兩個檔案的全部測試皆通過，尤其留意以下涵蓋本次抽離邏輯的既有測試（測試名稱不變，行為應與抽離前完全一致）：

- `PDF 切換三種 Fit 模式，畫面持續渲染成功、無 onError`
- `調整 PDF Fit 模式後關閉重開該書，設定被正確記住`
- `PDF 調整對比度／亮度後畫面持續渲染成功、無 onError`（驗證 `contrastBrightnessColorMatrix` 抽離後濾鏡仍生效）
- `調整 PDF 對比度／亮度後關閉重開該書，設定被正確記住`
- `PDF 調整加粗強度後畫面持續渲染成功、無 onError`（驗證 `applyBoldEffect`/`dilate` 抽離後加粗仍生效）
- `調整 PDF 加粗強度後關閉重開該書，設定被正確記住`
- `PDF 切換至智慧自動裁切，畫面持續渲染成功、無 onError`（驗證 `detectCropRect` 抽離後裁切偵測仍生效）
- `智慧自動裁切計算後關閉重開該書，pdf_crop_rect 不重新計算（值一致）`
- `PDF 進入手動裁切互動模式後，翻頁手勢暫停回應（不觸發頁面錯誤或意外離開裁切模式）`
- `PDF 手動裁切拖拉四角控制點確認後，pdf_crop_mode/pdf_crop_rect 正確寫入且畫面套用新裁切結果`（驗證 `CropOverlayView` 改用 `PdfImageProcessor.CropRect` 後互動鏈路仍正確）

若任何測試失敗，先確認失敗原因是否為本次抽離造成的行為差異（例如型別替換時打錯變數名、常數值謄寫錯誤），而非既有已知限制（見 `issues.md` Issue 2/4/5 的「已知驗證缺口」/「已知限制」章節，那些是抽離前就存在的既有問題，不屬於本 Task 回歸範圍）。

- [ ] **Step 8：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt \
        app/android/app/src/main/kotlin/cc/ugotit/elinkbook/CropOverlayView.kt
git commit -m "refactor(epic-4): PdfReaderView/CropOverlayView 改用 PdfImageProcessor，刪除重複的私有影像處理實作"
```

---

## Self-Review

**Spec coverage：** `docs/epics.md`「PdfReaderView.kt 影像處理邏輯抽離為 PdfImageProcessor」列要求的三塊邏輯——加粗型態學膨脹（Task 1）、智慧裁切邊界偵測（Task 2）、對比度/亮度 ColorMatrix 計算（Task 3）——皆有對應 Task，且 Task 4 完成呼叫端切換與刪除死碼、真機回歸驗證收尾。架構審查（`tmp/epic-16/reviews/architecture-review-1783800246.html` Candidate #2）要求的「pure Kotlin、僅依賴 Bitmap 輸入輸出、可 JVM 單元測試」皆已達成（且透過 IntArray-based 核心函式比字面上的「僅依賴 Bitmap」更進一步，做到真正無 Android 框架依賴的單元測試，不需要 Robolectric）。

**Placeholder scan：** 已逐一檢查，所有 Step 皆含完整可執行程式碼與明確指令/預期輸出，無 TBD／「依需要調整」等佔位敘述。

**Type consistency：** `PdfImageProcessor.CropRect`／`detectCropRect`／`detectCropRectFromPixels`／`dilate`／`dilatePixels`／`applyBoldEffect`／`contrastBrightnessColorMatrix` 的簽章在 Task 1-3（定義處）與 Task 4（呼叫處）、以及 `CropOverlayView.kt` 的型別參照皆一致核對過。

**外部審查：** `tmp/epic-4/reviews/plan-issue-8-review.md`（2026-07-12）核准本計劃，發現一項 🔴 必須修正（`Bitmap.recycle()` 別名風險，已驗證為真實存在的 Android SDK 行為，非審查者誤判）與兩項 🟡 建議（邊界測試補充、cache locality 註解）。三項皆已採納並反映於上方 Task 1/Task 2 內容（詳見 Global Constraints「唯一明確授權的例外」段落）；JVM 單元測試總數由原本的 6 個增至 9 個。

---

**Plan complete and saved to `docs/epics/epic-4-pdf-enhance/plans/plan-issue-8.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - 逐一 Task 派遣獨立 subagent 實作，每個 Task 完成後審查、快速迭代

**2. Inline Execution** - 在本 session 內依 Task 順序批次執行，設檢查點供人工確認

**Which approach？**
