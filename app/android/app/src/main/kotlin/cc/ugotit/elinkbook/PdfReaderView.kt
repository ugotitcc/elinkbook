package cc.ugotit.elinkbook

import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.view.View
import android.widget.ImageView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.File

/**
 * 包裝 android.graphics.pdf.PdfRenderer 的原生 PlatformView。
 * 透過 MethodChannel 接收 Flutter 的 openBook 呼叫，成功則呼叫
 * onPageRendered，失敗則呼叫 onError(message)。[path] 可能是真實檔案系統
 * 路徑，也可能是 content:// 或 file:// URI 字串（見
 * docs/adr/0002-content-uri-reader-contract.md）。
 *
 * 支援手勢翻頁：透過 nextPage／previousPage method channel 指令切換頁面，
 * 頁面變更時觸發 onPageChanged(pageIndex)。
 *
 * 支援 Fit 模式（FR-11，見 docs/epics/epic-4-pdf-enhance/spec.md）：透過
 * openBook 的 initialPreferences 或 setPdfPreferences 指令設定，只調整
 * imageView 的顯示層（scaleType／matrix），不重新解碼 PDF 頁面。
 */
class PdfReaderView(
    private val context: Context,
    id: Int,
    messenger: BinaryMessenger,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val imageView: ImageView = ImageView(context)
    private val channel: MethodChannel =
        MethodChannel(messenger, "cc.ugotit.elinkbook/pdf_reader_view_$id")

    private var renderer: PdfRenderer? = null
    private var currentPageIndex: Int = 0
    private var totalPages: Int = 0

    // Dart PdfFitMode.name 對應字串（'pageFit'／'fitWidth'／'actualSize'），
    // 預設 "pageFit"，與 BookReaderPrefs.pdfFitMode 為 null 時的語意一致。
    private var fitMode: String = "pageFit"

    // Dart contrast／brightness 值，-100..100，預設 0（無調整），與
    // BookReaderPrefs.pdfContrast/pdfBrightness 為 null 時的語意一致。
    private var contrast: Float = 0f
    private var brightness: Float = 0f

    // Dart boldStrength 值，0..1，預設 0（無加粗），與
    // BookReaderPrefs.pdfBoldStrength 為 null 時的語意一致。
    private var boldStrength: Float = 0f

    // Dart PdfCropMode.name 對應字串（'none'／'autoDetect'／'manual'），
    // 預設 "none"，與 BookReaderPrefs.pdfCropMode 為 null 時的語意一致。
    private var cropMode: String = "none"

    // 目前生效的裁切矩形（相對座標 0.0-1.0）。autoDetect 模式下由
    // detectCropRect() 首次計算後快取於此（決策 #3，全書統一比例、不逐頁
    // 重算）；也可能由 Dart 端透過 initialPreferences/setPdfPreferences
    // 直接帶入已持久化的值（避免重開書又重新計算一次）。
    private var cropRect: CropRect? = null

    /** 裁切矩形（相對座標 0.0-1.0），Kotlin 內部用資料類別，對應 Dart
     * PdfCropRect 的欄位。*/
    private data class CropRect(val left: Float, val top: Float, val right: Float, val bottom: Float)

    companion object {
        // 加粗（型態學膨脹）運算的效能策略常數，見 spec.md/design.md「已知
        // 風險」與本 issue 計劃的「效能策略」段落：對縮小版工作副本做膨脹，
        // 而非對全解析度 bitmap 直接運算。
        private const val BOLD_DOWNSCALE_FACTOR = 0.25f
        private const val BOLD_MAX_RADIUS = 3
    }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = imageView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBook" -> {
                @Suppress("UNCHECKED_CAST")
                openBook(
                    call.argument<String>("path"),
                    call.argument<Map<String, Any?>>("initialPreferences"),
                )
                result.success(null)
            }
            "setPdfPreferences" -> {
                @Suppress("UNCHECKED_CAST")
                setPdfPreferences(call.arguments as? Map<String, Any?>)
                result.success(null)
            }
            "nextPage" -> {
                nextPage()
                result.success(null)
            }
            "previousPage" -> {
                previousPage()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * 合併 [preferences] 到目前生效狀態並套用。fitMode／contrast／
     * brightness 屬於輕量顯示層調整（不需重新解碼 PDF），但
     * boldStrength 變動需要完整重新渲染（型態學膨脹是對 bitmap 像素本身
     * 的運算，不像 ColorMatrixColorFilter 是非破壞性的顯示層濾鏡）。
     */
    private fun setPdfPreferences(preferences: Map<String, Any?>?) {
        if (preferences == null) return
        (preferences["fitMode"] as? String)?.let { fitMode = it }
        (preferences["contrast"] as? Number)?.let { contrast = it.toFloat() }
        (preferences["brightness"] as? Number)?.let { brightness = it.toFloat() }
        val boldChanged = (preferences["boldStrength"] as? Number)?.let {
            val newValue = it.toFloat()
            val changed = newValue != boldStrength
            boldStrength = newValue
            changed
        } ?: false
        val cropChanged = (preferences["cropMode"] as? String)?.let {
            val changed = it != cropMode
            cropMode = it
            changed
        } ?: false
        parseCropRect(preferences["cropRect"])?.let { cropRect = it }
        if (boldChanged || cropChanged) {
            renderCurrentPage()
        } else {
            applyFitMode()
            applyFilters()
        }
    }

    /** 從 method channel map 解析裁切矩形，格式不符時回傳 null（靜默忽略，
     * 比照其餘欄位的 `as? Number` 容錯風格）。*/
    @Suppress("UNCHECKED_CAST")
    private fun parseCropRect(raw: Any?): CropRect? {
        val map = raw as? Map<String, Any?> ?: return null
        val left = (map["left"] as? Number)?.toFloat() ?: return null
        val top = (map["top"] as? Number)?.toFloat() ?: return null
        val right = (map["right"] as? Number)?.toFloat() ?: return null
        val bottom = (map["bottom"] as? Number)?.toFloat() ?: return null
        return CropRect(left, top, right, bottom)
    }

    private fun openBook(path: String?, initialPreferences: Map<String, Any?>?) {
        if (path == null) {
            channel.invokeMethod("onError", "缺少檔案路徑")
            return
        }
        (initialPreferences?.get("fitMode") as? String)?.let { fitMode = it }
        (initialPreferences?.get("contrast") as? Number)?.let { contrast = it.toFloat() }
        (initialPreferences?.get("brightness") as? Number)?.let { brightness = it.toFloat() }
        (initialPreferences?.get("boldStrength") as? Number)?.let { boldStrength = it.toFloat() }
        (initialPreferences?.get("cropMode") as? String)?.let { cropMode = it }
        parseCropRect(initialPreferences?.get("cropRect"))?.let { cropRect = it }
        var pfd: ParcelFileDescriptor? = null
        try {
            pfd = openParcelFileDescriptor(path)
            if (pfd == null) {
                channel.invokeMethod("onError", "找不到檔案或檔案已損毀：$path")
                return
            }
            renderer = PdfRenderer(pfd)
            totalPages = renderer!!.pageCount
            currentPageIndex = 0
            renderCurrentPage()
            channel.invokeMethod("onPageRendered", null)
        } catch (e: OutOfMemoryError) {
            channel.invokeMethod("onError", "記憶體不足，無法載入 PDF 檔案")
        } catch (e: Exception) {
            channel.invokeMethod("onError", e.message ?: "無法載入 PDF 檔案")
        } finally {
            // 確保任何情況下（含上方例外拋出時）原生資源都會被釋放，避免
            // 檔案描述符/渲染器洩漏。
            try { pfd?.close() } catch (ignored: Exception) {}
        }
    }

    private fun renderCurrentPage() {
        val renderer = renderer ?: return
        val page = renderer.openPage(currentPageIndex)

        // 智慧自動裁切：尚無快取矩形時，先用一次全頁、無縮放的渲染取樣
        // 偵測邊界，計算結果快取於 cropRect 並回傳給 Dart 端持久化（決策
        // #3，全書統一比例、不逐頁重算）。
        if (cropMode == "autoDetect" && cropRect == null) {
            val detectBitmap =
                Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
            detectBitmap.eraseColor(android.graphics.Color.WHITE)
            page.render(detectBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            val detected = detectCropRect(detectBitmap)
            detectBitmap.recycle()
            cropRect = detected
            channel.invokeMethod(
                "onCropRectComputed",
                mapOf(
                    "left" to detected.left.toDouble(),
                    "top" to detected.top.toDouble(),
                    "right" to detected.right.toDouble(),
                    "bottom" to detected.bottom.toDouble(),
                ),
            )
        }

        val density = context.resources.displayMetrics.density
        val scale = density.coerceIn(2.0f, 3.0f)

        val effectiveCrop = if (cropMode != "none") cropRect else null
        val renderLeft: Float
        val renderTop: Float
        val renderWidth: Float
        val renderHeight: Float
        if (effectiveCrop != null) {
            renderLeft = effectiveCrop.left * page.width
            renderTop = effectiveCrop.top * page.height
            renderWidth = (effectiveCrop.right - effectiveCrop.left) * page.width
            renderHeight = (effectiveCrop.bottom - effectiveCrop.top) * page.height
        } else {
            renderLeft = 0f
            renderTop = 0f
            renderWidth = page.width.toFloat()
            renderHeight = page.height.toFloat()
        }

        val width = (renderWidth * scale).toInt().coerceAtLeast(1)
        val height = (renderHeight * scale).toInt().coerceAtLeast(1)

        try {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            // Bitmap.createBitmap() 預設是全透明（ARGB 皆為 0），而
            // PdfRenderer.Page.render() 只會畫出 PDF 內容本身有實際筆劃的
            // 像素，頁面「空白背景」區域若 PDF 本身沒有明確畫白色矩形，會
            // 維持透明、不會被填成不透明白色。applyFilters() 的
            // ColorMatrixColorFilter 第 4 列（alpha）是單位矩陣（保留原始
            // alpha），因此透明像素無論 contrast／brightness 設多少都不會
            // 產生視覺變化——必須在渲染前先手動填滿不透明白色背景，濾鏡才能
            // 對「背景」區域也生效（見 task-4-diagnose-report.md 根因分析）。
            bitmap.eraseColor(android.graphics.Color.WHITE)
            val matrix = android.graphics.Matrix().apply {
                // 先把裁切區域的左上角平移到原點，再統一縮放——順序不可顛倒
                // （Android Matrix 的 post* 方法依呼叫順序疊加：先
                // postTranslate 再 postScale，等同「先平移、再縮放」）。
                // effectiveCrop 為 null 時 renderLeft/renderTop 皆為 0，
                // 退化為既有（無裁切）行為，不影響 Issue 2-4 既有邏輯。
                postTranslate(-renderLeft, -renderTop)
                postScale(scale, scale)
            }
            page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            val finalBitmap = if (boldStrength > 0f) applyBoldEffect(bitmap) else bitmap
            imageView.setImageBitmap(finalBitmap)
            applyFitMode()
            applyFilters()
        } catch (e: OutOfMemoryError) {
            // 如果發生 OutOfMemory，回退到原始尺寸渲染以確保不會崩潰
            try {
                val fallbackBitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
                // 同上，回退路徑也需要先填滿不透明白色背景。
                fallbackBitmap.eraseColor(android.graphics.Color.WHITE)
                page.render(fallbackBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                imageView.setImageBitmap(fallbackBitmap)
                applyFitMode()
                applyFilters()
            } catch (ignored: Exception) {}
        }

        page.close()
    }

    /**
     * 智慧自動裁切邊界偵測（見 plans/plan-issue-5.md Global Constraints
     * 「邊界偵測演算法」）：由四個邊緣向內掃描，找第一個「非全白」的
     * 列/行視為內容邊界，加一點邊距避免裁得太緊。單頁取樣，每 4 個像素
     * 跳著檢查一次以加速掃描。
     */
    private fun detectCropRect(bitmap: Bitmap): CropRect {
        val width = bitmap.width
        val height = bitmap.height
        val whiteThreshold = 245
        val margin = 0.01f
        val step = 4

        fun isRowContent(y: Int): Boolean {
            var x = 0
            while (x < width) {
                val p = bitmap.getPixel(x, y)
                val minChannel = minOf((p shr 16) and 0xFF, (p shr 8) and 0xFF, p and 0xFF)
                if (minChannel < whiteThreshold) return true
                x += step
            }
            return false
        }

        fun isColContent(x: Int): Boolean {
            var y = 0
            while (y < height) {
                val p = bitmap.getPixel(x, y)
                val minChannel = minOf((p shr 16) and 0xFF, (p shr 8) and 0xFF, p and 0xFF)
                if (minChannel < whiteThreshold) return true
                y += step
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

        val relLeft = (left.toFloat() / width - margin).coerceIn(0f, 1f)
        val relTop = (top.toFloat() / height - margin).coerceIn(0f, 1f)
        val relRight = (right.toFloat() / width + margin).coerceIn(0f, 1f)
        val relBottom = (bottom.toFloat() / height + margin).coerceIn(0f, 1f)
        return CropRect(relLeft, relTop, relRight, relBottom)
    }

    /**
     * 依 [fitMode] 設定 imageView 的 scaleType／matrix，決定已渲染的 bitmap
     * 如何顯示在畫面上（見 docs/epics/epic-4-pdf-enhance/design.md 決策
     * #6/#7/#8）。只調整顯示層，不重新渲染 bitmap，因此可在
     * setPdfPreferences 收到新 fitMode 時單獨呼叫，不需要重新解碼 PDF 頁面。
     *
     * 已知限制（本 issue 刻意簡化範圍，已與人類確認）：fitWidth／actualSize
     * 若內容超出可視範圍，超出部分目前不可捲動（無 ScrollView 容器），留待
     * 後續 issue 視需求評估是否新增捲動能力。
     *
     * 殘餘風險（留待 Task 4 真機驗證確認）：fitWidth 分支依賴
     * imageView.width 在呼叫當下已完成量測；理論上 Flutter 的 hybrid
     * composition 會在建立 PlatformView 時就給定尺寸，但無法單靠原始碼
     * 100% 確認，若真機測試發現首次開書時 fitWidth 沒有立即生效，需回頭
     * 補上 ViewTreeObserver.OnGlobalLayoutListener 之類的重新量測機制。
     */
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
                // 與 renderCurrentPage() 算 bitmap 尺寸時使用的同一個 scale，
                // 換算回「1 PDF point = 1 dp」的真實顯示比例。【隱式耦合，
                // 修改時務必同步】這裡的 density.coerceIn(2.0f, 3.0f) 必須與
                // renderCurrentPage() 內算 width/height 用的 scale 算式保持
                // 完全一致，否則 actualSize 換算出的比例會失準；若未來調整
                // renderCurrentPage() 的 scale 策略，這裡要同步更新。
                val bitmapRenderScale = density.coerceIn(2.0f, 3.0f)
                val displayScale = density / bitmapRenderScale
                imageView.scaleType = ImageView.ScaleType.MATRIX
                imageView.imageMatrix = android.graphics.Matrix().apply { setScale(displayScale, displayScale) }
            }
            else -> { // "pageFit"（預設）
                imageView.scaleType = ImageView.ScaleType.FIT_CENTER
            }
        }
    }

    /**
     * 依 [contrast]／[brightness] 設定 imageView 的 colorFilter，與
     * applyFitMode() 的 scaleType／imageMatrix 是完全獨立的顯示層機制
     * （ColorMatrixColorFilter 作用於像素色彩，不影響座標變換），呼叫順序
     * 不影響結果，但依慣例排在 applyFitMode() 之後（見 spec.md「裁切 →
     * fit 模式縮放 → 濾鏡」的管線順序）。
     *
     * 標準對比度/亮度 ColorMatrix 公式：先以 127.5（8-bit 色階灰階中點）為
     * 軸心縮放對比度，再疊加亮度位移，確保 contrast=0／brightness=0 時是
     * 單位矩陣（無視覺變化）。
     */
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

    /**
     * 型態學膨脹（加粗），對 bitmap 做「取鄰域內最小亮度值」的膨脹運算，
     * 讓深色筆畫（文字）向外擴張、變粗變黑（見 docs/epics/epic-4-pdf-enhance/
     * plans/plan-issue-4.md「演算法決策」：全 API 24+ 統一用同一套手動像素
     * 陣列運算，不分 API 24-30／31+ 兩條路徑）。
     *
     * 效能策略：先縮小到 [BOLD_DOWNSCALE_FACTOR] 工作尺寸做膨脹運算，再放大
     * 回原尺寸，避免對全解析度 bitmap 直接做二維鄰域掃描造成明顯延遲（決策
     * #13 已授權濾鏡效能寬鬆處理）。
     */
    private fun applyBoldEffect(source: Bitmap): Bitmap {
        val workWidth = (source.width * BOLD_DOWNSCALE_FACTOR).toInt().coerceAtLeast(1)
        val workHeight = (source.height * BOLD_DOWNSCALE_FACTOR).toInt().coerceAtLeast(1)
        val working = Bitmap.createScaledBitmap(source, workWidth, workHeight, true)
        val radius = (boldStrength * BOLD_MAX_RADIUS).toInt().coerceIn(1, BOLD_MAX_RADIUS)
        val dilated = dilate(working, radius)
        val result = Bitmap.createScaledBitmap(dilated, source.width, source.height, true)
        working.recycle()
        dilated.recycle()
        return result
    }

    /**
     * 對 [bitmap] 做半徑 [radius] 的膨脹（取 (2*radius+1)^2 鄰域內每個色版
     * 的最小值，讓深色像素向外擴張）。邊界像素以 coerceIn 夾到合法範圍內
     * （等同邊緣複製，非補零），避免邊框產生非預期的暗色/亮色偽影。
     */
    private fun dilate(bitmap: Bitmap, radius: Int): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
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
        val out = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        out.setPixels(result, 0, width, 0, 0, width, height)
        return out
    }

    private fun nextPage() {
        if (currentPageIndex < totalPages - 1) {
            currentPageIndex++
            renderCurrentPage()
            channel.invokeMethod("onPageChanged", currentPageIndex)
        }
    }

    private fun previousPage() {
        if (currentPageIndex > 0) {
            currentPageIndex--
            renderCurrentPage()
            channel.invokeMethod("onPageChanged", currentPageIndex)
        }
    }

    /**
     * [path] 含 "://" 者一律視為 URI，交給 ContentResolver 開啟（Android
     * 對 file:// scheme 有內建直接處理，不需額外註冊 ContentProvider）；
     * 否則視為檔案系統路徑，沿用既有 ParcelFileDescriptor.open() 邏輯。
     *
     * 已知限制：`contains("://")` 是啟發式判斷，若檔案系統路徑本身恰好含有
     * 這個子字串會被誤判為 URI 而解析失敗。此啟發式假設路徑皆為 Android
     * 慣例格式，在正常使用情境下風險可忽略，記錄於此供未來維護者知悉。
     */
    private fun openParcelFileDescriptor(path: String): ParcelFileDescriptor? {
        return if (path.contains("://")) {
            context.contentResolver.openFileDescriptor(Uri.parse(path), "r")
        } else {
            ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
        }
    }

    override fun dispose() {
        renderer?.close()
        renderer = null
        channel.setMethodCallHandler(null)
    }
}
