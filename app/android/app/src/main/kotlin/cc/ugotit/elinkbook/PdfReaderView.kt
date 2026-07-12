package cc.ugotit.elinkbook

import android.content.Context
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.view.View
import android.widget.FrameLayout
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

    // 手動裁切互動模式（決策 #14）需要在 imageView 之上疊加
    // CropOverlayView，因此 getView() 回傳的根 View 從單一 ImageView 改為
    // 包一層 FrameLayout；未進入裁切互動模式時，rootView 只有 imageView
    // 這一個子 View，畫面與改動前完全一致。
    private val rootView: FrameLayout = FrameLayout(context).apply {
        addView(
            imageView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
    }

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
    // 直接帶入已持久化的值（避免重開書又重新計算一次）；manual 模式下由
    // 使用者透過 CropOverlayView 框選後經 exitCropEditMode 流程間接更新
    // （見 enterCropEditMode()/CropOverlayView 的 onConfirm 回呼）。
    private var cropRect: PdfImageProcessor.CropRect? = null

    // 手動裁切互動模式是否進行中（決策 #14）：由 Dart 端
    // cropEditModeActive prop 的宣告式變化驅動（enterCropEditMode／
    // exitCropEditMode method channel 呼叫），true 時 nextPage()／
    // previousPage() 暫停回應，避免翻頁手勢與拖拉裁切框互相干擾。
    private var cropEditModeActive: Boolean = false
    private var cropOverlayView: CropOverlayView? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = rootView

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
            "enterCropEditMode" -> {
                enterCropEditMode()
                result.success(null)
            }
            "exitCropEditMode" -> {
                exitCropEditMode()
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
    private fun parseCropRect(raw: Any?): PdfImageProcessor.CropRect? {
        val map = raw as? Map<String, Any?> ?: return null
        val left = (map["left"] as? Number)?.toFloat() ?: return null
        val top = (map["top"] as? Number)?.toFloat() ?: return null
        val right = (map["right"] as? Number)?.toFloat() ?: return null
        val bottom = (map["bottom"] as? Number)?.toFloat() ?: return null
        return PdfImageProcessor.CropRect(left, top, right, bottom)
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
            val detectBitmap = PdfImageProcessor.createOpaqueWhiteBitmap(page.width, page.height)
            page.render(detectBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            val detected = PdfImageProcessor.detectCropRect(detectBitmap)
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
        val scale = PdfImageProcessor.pageRenderScale(density)

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
            val bitmap = PdfImageProcessor.createOpaqueWhiteBitmap(width, height)
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
            val finalBitmap = if (boldStrength > 0f) PdfImageProcessor.applyBoldEffect(bitmap, boldStrength) else bitmap
            imageView.setImageBitmap(finalBitmap)
            applyFitMode()
            applyFilters()
        } catch (e: OutOfMemoryError) {
            // 如果發生 OutOfMemory，回退到原始尺寸渲染以確保不會崩潰
            try {
                val fallbackBitmap = PdfImageProcessor.createOpaqueWhiteBitmap(page.width, page.height)
                page.render(fallbackBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                imageView.setImageBitmap(fallbackBitmap)
                applyFitMode()
                applyFilters()
            } catch (ignored: Exception) {}
        }

        page.close()
    }

    /**
     * 進入手動裁切互動模式（決策 #14）：暫時以「完整未裁切頁面」重新渲染
     * （不管目前 cropMode 設定為何），讓使用者能從整頁範圍框選，避免
     * 「裁切一個已經被裁切過的畫面」造成的座標混淆；並疊加
     * CropOverlayView 讓使用者拖拉四角控制點。翻頁手勢在此模式下停用
     * （見 nextPage()/previousPage() 頂端的 cropEditModeActive 判斷）。
     *
     * 由 onMethodCall 的 "enterCropEditMode" case 呼叫，只在 Dart 端
     * cropEditModeActive prop 由 false 變 true 時觸發（宣告式，見
     * PdfReaderView.dart 的 didUpdateWidget）。
     */
    private fun enterCropEditMode() {
        cropEditModeActive = true
        val renderer = renderer ?: return
        val page = renderer.openPage(currentPageIndex)
        val pageWidth = page.width
        val pageHeight = page.height
        page.close()

        // 初始框選範圍：若已有裁切矩形（無論來自先前的自動或手動裁切）
        // 沿用之，讓使用者「微調」既有選區；否則預設置中、四周各留 10%
        // 邊距。
        val initial = cropRect ?: PdfImageProcessor.CropRect(0.1f, 0.1f, 0.9f, 0.9f)

        val overlay = CropOverlayView(context, pageWidth, pageHeight, initial) { result ->
            // 只透過 channel 通知 Dart 端，不在此處自行移除 overlay——
            // 移除動作統一等待 Dart 送回 exitCropEditMode 才執行（見
            // plan-issue-6.md Global Constraints）。
            //
            // 修復真機驗證發現的重新調整裁切框 bug：僅通知 Dart 端不足夠，
            // manual 模式下重新選取矩形時 cropMode 不會變動，didUpdateWidget
            // 不會送出 setPdfPreferences，原生端 cropRect 欄位若不在此處直接更新，
            // 會停留在舊矩形直到下次 setPdfPreferences/openBook 才更新（即重開書
            // 前，畫面不會反映新選取結果）。在此直接更新原生端狀態，讓
            // exitCropEditMode() 稍後呼叫的 renderCurrentPage() 使用正確矩形。
            cropRect = result
            cropMode = "manual"
            channel.invokeMethod(
                "onCropRectSelected",
                mapOf(
                    "left" to result.left.toDouble(),
                    "top" to result.top.toDouble(),
                    "right" to result.right.toDouble(),
                    "bottom" to result.bottom.toDouble(),
                ),
            )
        }
        cropOverlayView = overlay
        rootView.addView(
            overlay,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        renderFullPageForCropPreview()
    }

    /**
     * 離開手動裁切互動模式：移除 overlay、恢復翻頁手勢，並依目前（可能
     * 已透過 onCropRectSelected 流程更新過 cropMode/cropRect 的）狀態呼叫
     * renderCurrentPage() 重新渲染畫面套用結果。
     *
     * 由 onMethodCall 的 "exitCropEditMode" case 呼叫，只在 Dart 端
     * cropEditModeActive prop 由 true 變 false 時觸發——正常情況下這只會
     * 在 Dart 端收到 onCropRectSelected 後才發生（見 plan-issue-6.md
     * Global Constraints，原生端本身絕不主動呼叫這個方法自己清理）。
     */
    private fun exitCropEditMode() {
        cropEditModeActive = false
        cropOverlayView?.let { rootView.removeView(it) }
        cropOverlayView = null
        renderCurrentPage()
    }

    /**
     * 裁切編輯模式下的預覽渲染：忽略目前 cropMode，永遠顯示完整頁面、
     * 固定 FIT_CENTER，讓 CropOverlayView 的 FIT_CENTER letterbox 座標
     * 換算單純化（見 CropOverlayView.computeContentBounds()）。刻意獨立
     * 於 renderCurrentPage()——後者的裁切/fit/濾鏡管線邏輯與此處「一律
     * 顯示全頁、不套用任何濾鏡」的需求不同，混在一起會讓兩者都變複雜。
     */
    private fun renderFullPageForCropPreview() {
        val renderer = renderer ?: return
        val page = renderer.openPage(currentPageIndex)
        val density = context.resources.displayMetrics.density
        val scale = PdfImageProcessor.pageRenderScale(density)
        val width = (page.width * scale).toInt().coerceAtLeast(1)
        val height = (page.height * scale).toInt().coerceAtLeast(1)
        try {
            val bitmap = PdfImageProcessor.createOpaqueWhiteBitmap(width, height)
            val matrix = android.graphics.Matrix().apply { postScale(scale, scale) }
            page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            imageView.setImageBitmap(bitmap)
            imageView.scaleType = ImageView.ScaleType.FIT_CENTER
            imageView.colorFilter = null
        } catch (e: OutOfMemoryError) {
            // 記憶體不足時放棄預覽渲染，overlay 仍會顯示（背景沿用上一次
            // 畫面），使用者仍可框選，只是背景畫面可能是舊的；不影響裁切
            // 結果正確性（結果仍是相對頁面座標，與背景畫面是否為最新版本
            // 無關）。
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

    /**
     * 依 [contrast]／[brightness] 設定 imageView 的 colorFilter，與
     * applyFitMode() 的 scaleType／imageMatrix 是完全獨立的顯示層機制
     * （ColorMatrixColorFilter 作用於像素色彩，不影響座標變換），呼叫順序
     * 不影響結果，但依慣例排在 applyFitMode() 之後（見 spec.md「裁切 →
     * fit 模式縮放 → 濾鏡」的管線順序）。實際 ColorMatrix 計算邏輯已搬至
     * PdfImageProcessor.contrastBrightnessColorMatrix()。
     */
    private fun applyFilters() {
        imageView.colorFilter = android.graphics.ColorMatrixColorFilter(
            android.graphics.ColorMatrix(
                PdfImageProcessor.contrastBrightnessColorMatrix(contrast, brightness)
            )
        )
    }

    private fun nextPage() {
        if (cropEditModeActive) return
        if (currentPageIndex < totalPages - 1) {
            currentPageIndex++
            renderCurrentPage()
            channel.invokeMethod("onPageChanged", currentPageIndex)
        }
    }

    private fun previousPage() {
        if (cropEditModeActive) return
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
        cropOverlayView?.let { rootView.removeView(it) }
        cropOverlayView = null
        renderer?.close()
        renderer = null
        channel.setMethodCallHandler(null)
    }
}
