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
