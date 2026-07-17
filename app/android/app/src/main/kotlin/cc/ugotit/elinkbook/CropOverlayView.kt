package cc.ugotit.elinkbook

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.MotionEvent
import android.view.View

/**
 * 手動裁切互動疊加層（design.md 決策 #14）：疊加於 PdfReaderView 的
 * imageView 之上，顯示可拖拉四角控制點的裁切框，並提供一個固定位置
 * （右下角）的確認按鈕。只在 PdfReaderView.enterCropEditMode() 期間加入
 * View 樹，exitCropEditMode() 時移除。
 *
 * 座標系統：[pageWidthPx]／[pageHeightPx] 是目前頁面渲染時使用的像素尺寸
 * （由呼叫端提供），用來計算 FIT_CENTER letterbox 後頁面內容在本 View 內
 * 的實際顯示範圍 [contentBounds]；裁切框的拖拉範圍限制在 [contentBounds]
 * 內。[onConfirm] 回傳的矩形已換算為相對頁面座標（0.0-1.0），對應
 * PdfCropRect 的語意——呼叫端（PdfReaderView）收到後只透過 channel 通知
 * Dart 端（onCropRectSelected），不在此處自行移除 overlay，等待 Dart 端
 * 依宣告式流程送回 exitCropEditMode 才清理（見 plan-issue-6.md Global
 * Constraints「PdfReaderView 契約異動皆為宣告式」）。
 */
class CropOverlayView(
    context: Context,
    private val pageWidthPx: Int,
    private val pageHeightPx: Int,
    initialRelativeRect: PdfImageProcessor.CropRect,
    private val onConfirm: (PdfImageProcessor.CropRect) -> Unit,
) : View(context) {

    companion object {
        private const val HANDLE_RADIUS_DP = 10f
        private const val HANDLE_TOUCH_SLOP_DP = 24f
        private const val MIN_CROP_FRACTION = 0.1f // 裁切框最小尺寸，相對 contentBounds 的比例
        private const val CONFIRM_BUTTON_RADIUS_DP = 24f
        private const val CONFIRM_BUTTON_MARGIN_DP = 16f
    }

    private val density = context.resources.displayMetrics.density
    private val handleRadiusPx = HANDLE_RADIUS_DP * density
    private val touchSlopPx = HANDLE_TOUCH_SLOP_DP * density
    private val confirmRadiusPx = CONFIRM_BUTTON_RADIUS_DP * density
    private val confirmMarginPx = CONFIRM_BUTTON_MARGIN_DP * density

    private val dimPaint = Paint().apply { color = Color.argb(153, 0, 0, 0) } // 60% 黑，裁切框外遮罩
    private val borderPaint = Paint().apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 2f * density
    }
    private val handlePaint = Paint().apply { color = Color.WHITE; style = Paint.Style.FILL }
    // 確認按鈕刻意採用黑底白勾（而非審查報告原始草稿中的綠色），確保在
    // E-Ink 16 階灰階裝置（見 AppThemePreferences 的 E-Ink 高對比模式）與
    // 一般彩色螢幕上都維持清楚可辨的對比度，不需要另外新增主題感知管線
    // （PdfReaderView 契約目前完全不感知主題，見 spec.md，本 issue 不新增
    // 這類管線，改用不依賴主題資訊即可維持高對比的固定配色）。
    private val confirmBgPaint = Paint().apply { color = Color.BLACK; style = Paint.Style.FILL }
    private val confirmCheckPaint = Paint().apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 3f * density
        strokeCap = Paint.Cap.ROUND
    }

    // 頁面內容在本 View 內的實際顯示範圍（FIT_CENTER letterbox），layout
    // 完成、寬高已知後才計算，見 onSizeChanged()。
    private var contentBounds = RectF()

    // 裁切框目前狀態（View 像素座標，限制在 contentBounds 內）。
    private var cropRectPx = RectF()

    // 只在第一次 onSizeChanged（初次 layout）時套用初始矩形。
    private var pendingInitialRect: PdfImageProcessor.CropRect? = initialRelativeRect

    private var activeHandle: Handle? = null
    private var confirmPressed = false

    private enum class Handle { TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }

    /**
     * 裝置旋轉等原因造成 View 尺寸變化時，重新計算 contentBounds；若已經
     * 在編輯中途（pendingInitialRect 已為 null，代表初始矩形已套用過），
     * 先用「舊」contentBounds 把目前的裁切框換算回相對座標（0.0-1.0），
     * 再用「新」contentBounds 換算回像素座標，讓裁切框的相對位置與比例
     * 不受旋轉影響（審查意見 2.2：避免旋轉後裁切框停留在舊的絕對像素
     * 位置、與新版面完全錯位）。
     */
    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val oldBounds = contentBounds
        contentBounds = computeContentBounds(w, h)

        val rect = pendingInitialRect
        if (rect != null) {
            cropRectPx = RectF(
                contentBounds.left + rect.left * contentBounds.width(),
                contentBounds.top + rect.top * contentBounds.height(),
                contentBounds.left + rect.right * contentBounds.width(),
                contentBounds.top + rect.bottom * contentBounds.height(),
            )
            pendingInitialRect = null
        } else if (oldBounds.width() > 0f && oldBounds.height() > 0f) {
            val relLeft = (cropRectPx.left - oldBounds.left) / oldBounds.width()
            val relTop = (cropRectPx.top - oldBounds.top) / oldBounds.height()
            val relRight = (cropRectPx.right - oldBounds.left) / oldBounds.width()
            val relBottom = (cropRectPx.bottom - oldBounds.top) / oldBounds.height()
            cropRectPx = RectF(
                contentBounds.left + relLeft * contentBounds.width(),
                contentBounds.top + relTop * contentBounds.height(),
                contentBounds.left + relRight * contentBounds.width(),
                contentBounds.top + relBottom * contentBounds.height(),
            )
        }
    }

    /**
     * FIT_CENTER letterbox 數學：委派給共用函式
     * [computeFitCenterContentBounds]（epic-6-annotations Issue 3 抽出，見
     * `PdfContentBounds.kt`），本類別不再自行重複實作同一段數學。
     */
    private fun computeContentBounds(viewWidth: Int, viewHeight: Int): RectF =
        computeFitCenterContentBounds(viewWidth, viewHeight, pageWidthPx, pageHeightPx)

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        // 裁切框外的四塊區域畫暗色遮罩，讓使用者聚焦於選取範圍。
        canvas.drawRect(0f, 0f, width.toFloat(), cropRectPx.top, dimPaint)
        canvas.drawRect(0f, cropRectPx.bottom, width.toFloat(), height.toFloat(), dimPaint)
        canvas.drawRect(0f, cropRectPx.top, cropRectPx.left, cropRectPx.bottom, dimPaint)
        canvas.drawRect(cropRectPx.right, cropRectPx.top, width.toFloat(), cropRectPx.bottom, dimPaint)

        canvas.drawRect(cropRectPx, borderPaint)
        canvas.drawCircle(cropRectPx.left, cropRectPx.top, handleRadiusPx, handlePaint)
        canvas.drawCircle(cropRectPx.right, cropRectPx.top, handleRadiusPx, handlePaint)
        canvas.drawCircle(cropRectPx.left, cropRectPx.bottom, handleRadiusPx, handlePaint)
        canvas.drawCircle(cropRectPx.right, cropRectPx.bottom, handleRadiusPx, handlePaint)

        val confirmCx = width - confirmMarginPx - confirmRadiusPx
        val confirmCy = height - confirmMarginPx - confirmRadiusPx
        canvas.drawCircle(confirmCx, confirmCy, confirmRadiusPx, confirmBgPaint)
        // 簡易打勾圖案（兩段折線）
        canvas.drawLine(
            confirmCx - confirmRadiusPx * 0.4f, confirmCy,
            confirmCx - confirmRadiusPx * 0.1f, confirmCy + confirmRadiusPx * 0.35f,
            confirmCheckPaint,
        )
        canvas.drawLine(
            confirmCx - confirmRadiusPx * 0.1f, confirmCy + confirmRadiusPx * 0.35f,
            confirmCx + confirmRadiusPx * 0.45f, confirmCy - confirmRadiusPx * 0.35f,
            confirmCheckPaint,
        )
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val confirmCx = width - confirmMarginPx - confirmRadiusPx
        val confirmCy = height - confirmMarginPx - confirmRadiusPx

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val dxConfirm = event.x - confirmCx
                val dyConfirm = event.y - confirmCy
                if (dxConfirm * dxConfirm + dyConfirm * dyConfirm <= confirmRadiusPx * confirmRadiusPx) {
                    confirmPressed = true
                } else {
                    activeHandle = nearestHandle(event.x, event.y)
                }
                // 本 View 是裁切互動期間的獨佔遮罩層，ACTION_DOWN 恆回傳
                // true 攔截並消費事件——若回傳 false（例如沒有精確命中控制
                // 點或確認按鈕），Android 觸控分發機制會導致本 View 收不到
                // 該手勢後續的 ACTION_MOVE/ACTION_UP，且事件會穿透到底層
                // imageView，可能引發非預期的翻頁/縮放手勢（審查意見
                // 1.1：ACTION_DOWN 事件穿透與後續事件丟失）。
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val handle = activeHandle ?: return false
                updateHandle(handle, event.x, event.y)
                invalidate()
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (confirmPressed) {
                    confirmPressed = false
                    val dxConfirm = event.x - confirmCx
                    val dyConfirm = event.y - confirmCy
                    if (dxConfirm * dxConfirm + dyConfirm * dyConfirm <= confirmRadiusPx * confirmRadiusPx) {
                        onConfirm(currentRelativeRect())
                    }
                    return true
                }
                activeHandle = null
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    private fun nearestHandle(x: Float, y: Float): Handle? {
        val candidates = listOf(
            Handle.TOP_LEFT to (cropRectPx.left to cropRectPx.top),
            Handle.TOP_RIGHT to (cropRectPx.right to cropRectPx.top),
            Handle.BOTTOM_LEFT to (cropRectPx.left to cropRectPx.bottom),
            Handle.BOTTOM_RIGHT to (cropRectPx.right to cropRectPx.bottom),
        )
        var nearest: Handle? = null
        var nearestDistSq = touchSlopPx * touchSlopPx
        for ((handle, point) in candidates) {
            val dx = x - point.first
            val dy = y - point.second
            val distSq = dx * dx + dy * dy
            if (distSq <= nearestDistSq) {
                nearest = handle
                nearestDistSq = distSq
            }
        }
        return nearest
    }

    private fun updateHandle(handle: Handle, x: Float, y: Float) {
        val minSize = minOf(contentBounds.width(), contentBounds.height()) * MIN_CROP_FRACTION
        val clampedX = x.coerceIn(contentBounds.left, contentBounds.right)
        val clampedY = y.coerceIn(contentBounds.top, contentBounds.bottom)
        when (handle) {
            Handle.TOP_LEFT -> {
                cropRectPx.left = clampedX.coerceAtMost(cropRectPx.right - minSize)
                cropRectPx.top = clampedY.coerceAtMost(cropRectPx.bottom - minSize)
            }
            Handle.TOP_RIGHT -> {
                cropRectPx.right = clampedX.coerceAtLeast(cropRectPx.left + minSize)
                cropRectPx.top = clampedY.coerceAtMost(cropRectPx.bottom - minSize)
            }
            Handle.BOTTOM_LEFT -> {
                cropRectPx.left = clampedX.coerceAtMost(cropRectPx.right - minSize)
                cropRectPx.bottom = clampedY.coerceAtLeast(cropRectPx.top + minSize)
            }
            Handle.BOTTOM_RIGHT -> {
                cropRectPx.right = clampedX.coerceAtLeast(cropRectPx.left + minSize)
                cropRectPx.bottom = clampedY.coerceAtLeast(cropRectPx.top + minSize)
            }
        }
    }

    private fun currentRelativeRect(): PdfImageProcessor.CropRect {
        val left = ((cropRectPx.left - contentBounds.left) / contentBounds.width()).coerceIn(0f, 1f)
        val top = ((cropRectPx.top - contentBounds.top) / contentBounds.height()).coerceIn(0f, 1f)
        val right = ((cropRectPx.right - contentBounds.left) / contentBounds.width()).coerceIn(0f, 1f)
        val bottom = ((cropRectPx.bottom - contentBounds.top) / contentBounds.height()).coerceIn(0f, 1f)
        return PdfImageProcessor.CropRect(left, top, right, bottom)
    }
}
