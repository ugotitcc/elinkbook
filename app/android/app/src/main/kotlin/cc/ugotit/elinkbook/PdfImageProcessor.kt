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

    /** 裁切矩形（相對座標 0.0-1.0）。原本是 PdfReaderView 的巢狀類別，隨影像
     * 處理邏輯一併移至此處——CropOverlayView.kt 與 PdfReaderView.kt 皆改參照
     * PdfImageProcessor.CropRect。*/
    data class CropRect(val left: Float, val top: Float, val right: Float, val bottom: Float)

    // 智慧自動裁切邊界偵測參數，見 detectCropRectFromPixels() 演算法說明。
    private const val CROP_WHITE_THRESHOLD = 245
    private const val CROP_MARGIN = 0.01f
    private const val CROP_SCAN_STEP = 4

    // 加粗（型態學膨脹）運算的效能策略常數：對縮小版工作副本做膨脹，而非對
    // 全解析度 bitmap 直接運算（見 docs/epics/epic-4-pdf-enhance/plans/
    // plan-issue-4.md「演算法決策」）。
    private const val BOLD_DOWNSCALE_FACTOR = 0.25f
    private const val BOLD_MAX_RADIUS = 3

    // PDF 頁面渲染縮放係數的夾限範圍，見 pageRenderScale()。
    private const val PAGE_RENDER_MIN_SCALE = 2.0f
    private const val PAGE_RENDER_MAX_SCALE = 3.0f

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

    /**
     * PDF 頁面渲染縮放係數：以裝置螢幕密度 [density] 為基準，夾限在
     * [PAGE_RENDER_MIN_SCALE]（2.0）到 [PAGE_RENDER_MAX_SCALE]（3.0）之間，
     * 避免極端 density 值造成渲染解析度過低（模糊）或過高（記憶體/效能問題）。
     * `PdfReaderView.kt` 的 `renderCurrentPage()`／`renderFullPageForCropPreview()`／
     * `applyFitMode()` 的 `actualSize` 分支原本各自重複硬編碼
     * `density.coerceIn(2.0f, 3.0f)`，此為抽離後的單一事實來源（見
     * docs/epics.md「PdfReaderView.kt 縮放係數與白底 Bitmap 建立邏輯重複」列、
     * docs/epics/epic-4-pdf-enhance/plans/plan-issue-9.md）。
     */
    fun pageRenderScale(density: Float): Float =
        density.coerceIn(PAGE_RENDER_MIN_SCALE, PAGE_RENDER_MAX_SCALE)

    /**
     * 建立一張 [width]x[height] 的不透明白底 ARGB_8888 Bitmap。
     * `Bitmap.createBitmap()` 預設是全透明（ARGB 皆為 0），而
     * `PdfRenderer.Page.render()` 只會畫出 PDF 內容本身有實際筆劃的像素，頁面
     * 「空白背景」區域若 PDF 本身沒有明確畫白色矩形，會維持透明、不會被填成
     * 不透明白色。`applyFilters()` 的 `ColorMatrixColorFilter` 第 4 列
     * （alpha）是單位矩陣（保留原始 alpha），因此透明像素無論 contrast／
     * brightness 設多少都不會產生視覺變化——必須在渲染前先手動填滿不透明
     * 白色背景，濾鏡才能對「背景」區域也生效（見 task-4-diagnose-report.md
     * 根因分析）。`PdfReaderView.kt` 原本在智慧裁切偵測、主渲染流程、OOM
     * Fallback 流程、`renderFullPageForCropPreview()` 四處各自重複呼叫
     * `Bitmap.createBitmap(...)` + `eraseColor(Color.WHITE)`，此為抽離後的
     * 單一事實來源（見 docs/epics/epic-4-pdf-enhance/plans/plan-issue-9.md）。
     *
     * 與 [applyBoldEffect]／[dilate]／[detectCropRect] 相同，本函式直接呼叫
     * 真實 `android.graphics.Bitmap` 方法，無法在純 JVM 環境單元測試（需要
     * Robolectric 或真機），依專案既有慣例不新增自動化測試，正確性由既有真機
     * `integration_test` 回歸把關（見 plan-issue-9.md Task 3）。
     */
    fun createOpaqueWhiteBitmap(width: Int, height: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(android.graphics.Color.WHITE)
        return bitmap
    }
}
