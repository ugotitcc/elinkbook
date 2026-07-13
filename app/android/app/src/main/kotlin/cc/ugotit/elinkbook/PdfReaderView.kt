package cc.ugotit.elinkbook

import android.content.Context
import android.graphics.Bitmap
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

    // 解析自 Dart PdfFitMode.name 字串，預設 PAGE_FIT，與
    // BookReaderPrefs.pdfFitMode 為 null 時的語意一致。
    private var fitMode: PdfFitMode = PdfFitMode.PAGE_FIT

    // Dart contrast／brightness 值，-100..100，預設 0（無調整），與
    // BookReaderPrefs.pdfContrast/pdfBrightness 為 null 時的語意一致。
    private var contrast: Float = 0f
    private var brightness: Float = 0f

    // Dart boldStrength 值，0..1，預設 0（無加粗），與
    // BookReaderPrefs.pdfBoldStrength 為 null 時的語意一致。
    private var boldStrength: Float = 0f

    // 解析自 Dart PdfCropMode.name 字串，預設 NONE，與
    // BookReaderPrefs.pdfCropMode 為 null 時的語意一致。
    private var cropMode: PdfCropMode = PdfCropMode.NONE

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

    // 解析自 Dart DualPageMode.name 字串，預設 AUTO，與
    // BookReaderPrefs.dualPageMode 為 null 時的語意一致（epic-16-dual-page）。
    private var dualPageMode: DualPageMode = DualPageMode.AUTO

    // 封面是否獨立單頁顯示（FR-41），預設 true，與
    // BookReaderPrefs.dualPageCoverAlone 為 null 時的語意一致。
    private var dualPageCoverAlone: Boolean = true

    // 解析自 Dart DualPageDirection.name 字串，預設 RTL（Issue 4 決策：
    // elinkBook 全域固定預設為右到左，見 issues.md Issue 4），與
    // BookReaderPrefs.dualPageDirection 為 null 時的語意一致。
    private var dualPageDirection: DualPageDirection = DualPageDirection.RTL

    // 目前裝置是否為橫向（ReaderScreen 透過 MediaQuery 偵測後下傳，見
    // spec.md「方向偵測契約」），預設 false（直向）。
    private var isLandscape: Boolean = false

    // 依目前 dualPageMode／isLandscape／cropEditModeActive 三個狀態欄位算出
    // 「雙頁顯示現在是否生效」，供 renderCurrentSpread()／nextPage()／
    // previousPage() 三處共用，避免各自重複呼叫同一組參數（Task 5 的
    // companion object 函式 isDualPageEnabled(...)）。刻意取名
    // dualPageEnabled（而非與 companion 函式同名的 isDualPageEnabled）
    // ——雖然 Kotlin 允許屬性與函式同名並依呼叫語法消歧義，但同名容易讓
    // 之後的維護者誤讀，取不同名稱更清楚。
    private val dualPageEnabled: Boolean
        get() = isDualPageEnabled(dualPageMode, isLandscape, cropEditModeActive)

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

    /**
     * 橫向雙頁顯示觸發模式（FR-41，epic-16-dual-page），對應 Dart
     * DualPageMode 列舉（`app/lib/reader/dual_page_mode.dart`）透過
     * Method Channel 傳來的 `.name` 字串（'auto'／'always'／'never'）。
     */
    internal enum class DualPageMode {
        AUTO, ALWAYS, NEVER;

        companion object {
            /** 未知或非 String 的原始值一律正規化為 [AUTO]（預設），與
             * BookReaderPrefs.dualPageMode 為 null 時的既有語意一致。*/
            fun fromWireValue(value: String?): DualPageMode = when (value) {
                "always" -> ALWAYS
                "never" -> NEVER
                else -> AUTO
            }
        }
    }

    /**
     * PDF 雙頁顯示的頁面配對閱讀方向（FR-41），對應 Dart DualPageDirection
     * 列舉（`app/lib/reader/dual_page_direction.dart`）透過 Method Channel
     * 傳來的 `.name` 字串（'ltr'／'rtl'）。
     */
    internal enum class DualPageDirection {
        LTR, RTL;

        companion object {
            /** 未知或非 String 的原始值一律正規化為 [RTL]（預設，Issue 4
             * 決策：elinkBook 全域固定預設為右到左），與
             * BookReaderPrefs.dualPageDirection 為 null 時的語意一致。*/
            fun fromWireValue(value: String?): DualPageDirection = when (value) {
                "ltr" -> LTR
                else -> RTL
            }
        }
    }

    companion object {
        /**
         * 雙頁顯示是否應該生效（spec.md renderCurrentSpread() 步驟 1）：
         * `always` 一律生效；`auto` 僅在橫向時生效；`never` 一律不生效；
         * 手動裁切編輯模式中一律強制視為不生效（spec.md I-8）。抽成
         * internal 純函式（不依賴任何 Android View/Bitmap），可脫離真機
         * 直接以 JVM 單元測試涵蓋——本 epic 技術風險最高的 C-4 對稱規則
         * 即靠這組純函式把邏輯與必須真機驗證的像素渲染切開。
         */
        internal fun isDualPageEnabled(
            dualPageMode: DualPageMode,
            isLandscape: Boolean,
            cropEditModeActive: Boolean,
        ): Boolean {
            if (cropEditModeActive) return false
            return dualPageMode == DualPageMode.ALWAYS ||
                (dualPageMode == DualPageMode.AUTO && isLandscape)
        }

        /**
         * 依 [direction] 決定 spread 左右頁的 index 配對（spec.md
         * renderCurrentSpread() 步驟 3）：[anchor] 是目前的
         * currentPageIndex；`ltr` 時左頁＝anchor、右頁＝anchor+1，`rtl`
         * 時左右對調。回傳 Pair(leftIndex, rightIndex)，呼叫端仍需自行
         * 檢查各 index 是否落在 `0 until totalPages` 範圍內（超出範圍的
         * 一側以白色背景留白）。
         */
        internal fun pairIndices(anchor: Int, direction: DualPageDirection): Pair<Int, Int> =
            if (direction == DualPageDirection.RTL) {
                Pair(anchor + 1, anchor)
            } else {
                Pair(anchor, anchor + 1)
            }

        /**
         * 雙頁模式生效時，`nextPage()` 的翻頁步進量（審查修正 C-4）：目前
         * 顯示第 0 頁封面且 [coverAlone] 開啟時步進 1（跳到 spread
         * `[1,2]`），其餘情境步進 2；雙頁未生效時維持既有單頁步進 1。
         */
        internal fun nextPageStep(
            currentPageIndex: Int,
            dualPageEnabled: Boolean,
            coverAlone: Boolean,
        ): Int {
            if (!dualPageEnabled) return 1
            return if (currentPageIndex == 0 && coverAlone) 1 else 2
        }

        /**
         * 雙頁模式生效時，`previousPage()` 的翻頁步進量（審查修正 C-4，
         * 後退到封面的對稱規則）：目前 spread 左頁 index 為 1 且
         * [coverAlone] 開啟時（即目前在 `[1,2]`）步進 1（回到封面
         * index 0），其餘情境步進 2；雙頁未生效時維持既有單頁步進 1。
         * 呼叫端仍須確認 `currentPageIndex - step >= 0` 才可實際翻頁，
         * 避免對負數 index 呼叫 `openPage()`。
         */
        internal fun previousPageStep(
            currentPageIndex: Int,
            dualPageEnabled: Boolean,
            coverAlone: Boolean,
        ): Int {
            if (!dualPageEnabled) return 1
            return if (currentPageIndex == 1 && coverAlone) 1 else 2
        }
    }

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
        (preferences["fitMode"] as? String)?.let { fitMode = PdfFitMode.fromWireValue(it) }
        (preferences["contrast"] as? Number)?.let { contrast = it.toFloat() }
        (preferences["brightness"] as? Number)?.let { brightness = it.toFloat() }
        val boldChanged = (preferences["boldStrength"] as? Number)?.let {
            val newValue = it.toFloat()
            val changed = newValue != boldStrength
            boldStrength = newValue
            changed
        } ?: false
        val cropChanged = (preferences["cropMode"] as? String)?.let {
            val newValue = PdfCropMode.fromWireValue(it)
            val changed = newValue != cropMode
            cropMode = newValue
            changed
        } ?: false
        parseCropRect(preferences["cropRect"])?.let { cropRect = it }
        val dualPageChanged = applyDualPagePreferences(preferences)
        // 裁切編輯模式中（cropEditModeActive）畫面必須維持
        // enterCropEditMode() 設定的「全頁、未裁切、FIT_CENTER、無濾鏡」
        // 預覽狀態，不能被本次偏好變動觸發的任何重新渲染覆蓋掉——提升為
        // 整個方法最前面的守衛，不論原本會落入下方哪個分支，一律優先呼叫
        // renderFullPageForCropPreview() 並提前 return。
        //
        // 這個守衛同時堵住兩個入口：(1) isLandscape（裝置旋轉時由
        // ReaderScreen 透過 MediaQuery 偵測送出，與裁切互動完全無關）改變
        // 觸發 dualPageChanged=true 時，若呼叫 renderCurrentSpread()，
        // dualPageEnabled 會因 cropEditModeActive=true 而判定為 false，改
        // 渲染 renderSingleSpread()（套用目前 cropMode/濾鏡、非
        // FIT_CENTER）；(2) 僅 contrast/brightness 變動、三個 *Changed 旗標
        // 皆為 false 時，會落入下方 else 分支呼叫 applyFitMode()（可能把
        // scaleType 改成 MATRIX）與 applyFilters()（套用 colorFilter），兩者
        // 都會直接覆蓋 renderFullPageForCropPreview() 設定的 FIT_CENTER／
        // colorFilter=null 狀態。兩種情況都會讓 CropOverlayView 的座標假設
        // 與實際畫面不同步（epic-16-dual-page Issue 5 發現，spec.md 決策
        // #10／I-8 的安全延伸；`/superpowers:requesting-code-review` 對本
        // 計劃的審查意見 Finding 4 指出原始修法只堵了 if 分支的
        // renderCurrentSpread() 入口，遺漏了 else 分支的 applyFitMode()／
        // applyFilters()，此處改為統一在方法最前面攔截，兩個入口一次堵死）。
        if (cropEditModeActive) {
            renderFullPageForCropPreview()
            return
        }
        if (boldChanged || cropChanged || dualPageChanged) {
            renderCurrentSpread()
        } else {
            applyFitMode()
            applyFilters()
        }
    }

    /**
     * 解析 [preferences] 中的雙頁／橫向相關欄位並更新對應欄位，回傳是否有
     * 任一欄位實際改變（供 setPdfPreferences 判斷是否需要完整重新渲染
     * spread，而非僅重套用 fit/濾鏡顯示層）。
     */
    private fun applyDualPagePreferences(preferences: Map<String, Any?>): Boolean {
        var changed = false
        (preferences["dualPageMode"] as? String)?.let {
            val newValue = DualPageMode.fromWireValue(it)
            if (newValue != dualPageMode) changed = true
            dualPageMode = newValue
        }
        (preferences["dualPageCoverAlone"] as? Boolean)?.let {
            if (it != dualPageCoverAlone) changed = true
            dualPageCoverAlone = it
        }
        (preferences["dualPageDirection"] as? String)?.let {
            val newValue = DualPageDirection.fromWireValue(it)
            if (newValue != dualPageDirection) changed = true
            dualPageDirection = newValue
        }
        (preferences["isLandscape"] as? Boolean)?.let {
            if (it != isLandscape) changed = true
            isLandscape = it
        }
        return changed
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
        (initialPreferences?.get("fitMode") as? String)?.let { fitMode = PdfFitMode.fromWireValue(it) }
        (initialPreferences?.get("contrast") as? Number)?.let { contrast = it.toFloat() }
        (initialPreferences?.get("brightness") as? Number)?.let { brightness = it.toFloat() }
        (initialPreferences?.get("boldStrength") as? Number)?.let { boldStrength = it.toFloat() }
        (initialPreferences?.get("cropMode") as? String)?.let { cropMode = PdfCropMode.fromWireValue(it) }
        parseCropRect(initialPreferences?.get("cropRect"))?.let { cropRect = it }
        if (initialPreferences != null) applyDualPagePreferences(initialPreferences)
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
            renderCurrentSpread()
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

    /**
     * PDF 雙頁渲染的統一入口（spec.md「模組」段落 `renderCurrentSpread()`
     * 演算法步驟 1-6）：依目前雙頁生效判斷與封面獨立設定，分派到單頁
     * （[renderSingleSpread]）或雙頁拼接路徑；拼接階段 OutOfMemoryError
     * 時回退為單頁（步驟 5）。
     */
    private fun renderCurrentSpread() {
        if (renderer == null) return
        val coverAlone = dualPageCoverAlone && currentPageIndex == 0
        if (!dualPageEnabled || coverAlone) {
            renderSingleSpread(currentPageIndex)
            return
        }
        // leftBitmap／rightBitmap／stitched 宣告在 try 區塊之外（而非直接
        // 用 val 綁在 try 內部），是為了讓 catch 區塊也能存取到「渲染到
        // 一半、已成功配置」的點陣圖——若 leftBitmap 配置成功後，緊接著
        // 渲染 rightBitmap 或 stitchBitmaps() 拼接才拋出 OutOfMemoryError，
        // 已配置的點陣圖若無法在 catch 中被 recycle()，會在 Java heap 永久
        // 洩漏，使緊接著的單頁 OOM 回退因記憶體更緊繃而更容易再次失敗。
        var leftBitmap: Bitmap? = null
        var rightBitmap: Bitmap? = null
        var stitched: Bitmap? = null
        try {
            val (leftIndex, rightIndex) = pairIndices(currentPageIndex, dualPageDirection)
            leftBitmap = if (leftIndex in 0 until totalPages) renderPageBitmap(leftIndex) else null
            rightBitmap = if (rightIndex in 0 until totalPages) renderPageBitmap(rightIndex) else null
            stitched = stitchBitmaps(leftBitmap, rightBitmap)
            displayFinalBitmap(stitched)
        } catch (e: OutOfMemoryError) {
            // 拼接階段記憶體不足，依 spec.md 步驟 5 回退為只渲染
            // currentPageIndex 單頁（不進行拼接），onPageChanged 仍回報
            // currentPageIndex（呼叫端 nextPage()/previousPage() 負責）。
            // 防禦性釋放任何已成功配置的點陣圖，避免記憶體洩漏。
            stitched?.recycle()
            leftBitmap?.recycle()
            rightBitmap?.recycle()
            renderSingleSpread(currentPageIndex)
        }
    }

    /**
     * 單頁渲染路徑：雙頁未生效、封面獨立顯示、或雙頁拼接 OOM 回退時皆走
     * 這條路徑。OOM 回退邏輯沿用抽離前既有行為（原始未縮放尺寸重繪），
     * 非本次新增。
     */
    private fun renderSingleSpread(pageIndex: Int) {
        try {
            val bitmap = renderPageBitmap(pageIndex)
            displayFinalBitmap(bitmap)
        } catch (e: OutOfMemoryError) {
            try {
                val page = renderer!!.openPage(pageIndex)
                val fallbackBitmap = PdfImageProcessor.createOpaqueWhiteBitmap(page.width, page.height)
                page.render(fallbackBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                page.close()
                imageView.setImageBitmap(fallbackBitmap)
                applyFitMode()
                applyFilters()
            } catch (ignored: Exception) {}
        }
    }

    /**
     * 渲染單一頁面（套用目前 [cropMode]/[cropRect] 與縮放係數），回傳未經
     * 加粗/fit/濾鏡處理的原始點陣圖——加粗/fit/濾鏡統一由
     * [displayFinalBitmap] 在拼接（或單頁）完成後套用一次（spec.md 步驟
     * 6）。智慧自動裁切偵測只在 [pageIndex] 為目前的 currentPageIndex（即
     * spread 錨點頁）時觸發一次（spec.md 步驟 1：「以單頁當前頁進行邊界
     * 偵測」），不論該頁最終落在 spread 的左側或右側。
     */
    private fun renderPageBitmap(pageIndex: Int): Bitmap {
        val page = renderer!!.openPage(pageIndex)
        try {
            if (cropMode == PdfCropMode.AUTO_DETECT && cropRect == null && pageIndex == currentPageIndex) {
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

            val effectiveCrop = if (cropMode != PdfCropMode.NONE) cropRect else null
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
            val bitmap = PdfImageProcessor.createOpaqueWhiteBitmap(width, height)
            val matrix = android.graphics.Matrix().apply {
                // 先把裁切區域的左上角平移到原點，再統一縮放——順序不可
                // 顛倒。effectiveCrop 為 null 時 renderLeft/renderTop 皆為
                // 0，退化為既有（無裁切）行為。
                postTranslate(-renderLeft, -renderTop)
                postScale(scale, scale)
            }
            page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            return bitmap
        } finally {
            page.close()
        }
    }

    /**
     * 把 [left]／[right] 兩個點陣圖橫向無縫拼接成一張大點陣圖（spec.md
     * 步驟 4，FR-41「不留空白」）：拼接後寬度恆等於左右兩頁寬度之和，
     * 不含任何額外留白像素。其中一側為 null 時（另一側超出總頁數，spec.md
     * 步驟 3「超出總頁數側留白」）以白色背景填充，尺寸比照有內容的一側
     * （呼叫端已保證 [left]/[right] 至少有一側非 null，因為其中一側必為
     * currentPageIndex 本身，恆落在 `0 until totalPages` 範圍內）。
     */
    private fun stitchBitmaps(left: Bitmap?, right: Bitmap?): Bitmap {
        val reference = left ?: right!!
        val leftBmp = left ?: PdfImageProcessor.createOpaqueWhiteBitmap(reference.width, reference.height)
        val rightBmp = right ?: PdfImageProcessor.createOpaqueWhiteBitmap(reference.width, reference.height)
        try {
            val width = leftBmp.width + rightBmp.width
            val height = maxOf(leftBmp.height, rightBmp.height)
            val canvasBitmap = PdfImageProcessor.createOpaqueWhiteBitmap(width, height)
            val canvas = android.graphics.Canvas(canvasBitmap)
            canvas.drawBitmap(leftBmp, 0f, 0f, null)
            canvas.drawBitmap(rightBmp, leftBmp.width.toFloat(), 0f, null)
            // 拼接完成後兩個半頁點陣圖已無用途，優先釋放以降低雙頁拼接的記憶體
            // 峰值（正是最容易觸發 OOM 的階段，見 spec.md「已知限制」）。
            leftBmp.recycle()
            rightBmp.recycle()
            return canvasBitmap
        } catch (e: OutOfMemoryError) {
            // 畫布配置時記憶體不足，先釋放合成出來的白色填充點陣圖再往外
            // 拋出，讓呼叫端 renderCurrentSpread() 的 catch 區塊能接手處理
            // （recycle stitched/leftBitmap/rightBitmap 後回退單頁）。
            leftBmp.recycle()
            rightBmp.recycle()
            throw e
        }
    }

    /**
     * 拼接（或單頁）完成後統一套用加粗濾鏡、imageView 的 fit 模式與
     * 對比度/亮度濾鏡（spec.md 步驟 6）。
     */
    private fun displayFinalBitmap(bitmap: Bitmap) {
        val finalBitmap = if (boldStrength > 0f) PdfImageProcessor.applyBoldEffect(bitmap, boldStrength) else bitmap
        imageView.setImageBitmap(finalBitmap)
        applyFitMode()
        applyFilters()
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
            cropMode = PdfCropMode.MANUAL
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
        renderCurrentSpread()
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
        val step = nextPageStep(currentPageIndex, dualPageEnabled, dualPageCoverAlone)
        val newIndex = currentPageIndex + step
        if (newIndex < totalPages) {
            currentPageIndex = newIndex
            renderCurrentSpread()
            channel.invokeMethod("onPageChanged", currentPageIndex)
        }
    }

    private fun previousPage() {
        if (cropEditModeActive) return
        val step = previousPageStep(currentPageIndex, dualPageEnabled, dualPageCoverAlone)
        val newIndex = currentPageIndex - step
        if (newIndex >= 0) {
            currentPageIndex = newIndex
            renderCurrentSpread()
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
