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
     * 合併 [preferences] 到目前生效狀態並套用（目前只有 fitMode 一個欄位，
     * 之後 Issue 3-6 會擴充濾鏡/裁切欄位）。書本尚未成功開啟
     * （renderer 仍為 null）時仍安全執行——applyFitMode() 內部若沒有已渲染
     * 的 bitmap 會靜默不做事。
     */
    private fun setPdfPreferences(preferences: Map<String, Any?>?) {
        if (preferences == null) return
        (preferences["fitMode"] as? String)?.let { fitMode = it }
        applyFitMode()
    }

    private fun openBook(path: String?, initialPreferences: Map<String, Any?>?) {
        if (path == null) {
            channel.invokeMethod("onError", "缺少檔案路徑")
            return
        }
        (initialPreferences?.get("fitMode") as? String)?.let { fitMode = it }
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

        // 取得螢幕密度（density）來計算高解析度的 Bitmap，至少為 2.0 倍以保證清晰度，最高限制為 3.0 倍以避免 OutOfMemory
        val density = context.resources.displayMetrics.density
        val scale = density.coerceIn(2.0f, 3.0f)

        val width = (page.width * scale).toInt()
        val height = (page.height * scale).toInt()

        try {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val matrix = android.graphics.Matrix().apply {
                postScale(scale, scale)
            }
            page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            imageView.setImageBitmap(bitmap)
            applyFitMode()
        } catch (e: OutOfMemoryError) {
            // 如果發生 OutOfMemory，回退到原始尺寸渲染以確保不會崩潰
            try {
                val fallbackBitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
                page.render(fallbackBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                imageView.setImageBitmap(fallbackBitmap)
                applyFitMode()
            } catch (ignored: Exception) {}
        }

        page.close()
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
