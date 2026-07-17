package cc.ugotit.elinkbook

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PointF
import android.graphics.RectF
import android.view.View

/**
 * 長按拖曳框選劃線範圍時的視覺回饋疊加層（epic-6-annotations Issue 3，
 * ADR 0008：長按直接觸發，不比照 `CropOverlayView` 的「先進入模式」既有
 * 慣例）。純粹負責繪製目前框選矩形，**完全不處理觸控事件**——長按/拖曳
 * 的辨識由 Flutter 端 `PdfReaderView.dart` 的 `GestureDetector` 主導，
 * 本疊加層只在原生端收到 Dart 送來的 `beginAnnotationSelection`／
 * `updateAnnotationSelection` method call 時才被建立/更新（見
 * plan-issue-3.md Task 8，審查修正 1.1：原生端不再自行監聽 `rootView`
 * 觸控，也就不存在「疊加層何時才被加入畫面、能否收到原始觸控序列」的
 * 問題——本類別的職責單純只是「畫出目前的矩形」，狀態從何而來與本類別
 * 無關）。
 *
 * [contentWidthPx]／[contentHeightPx] 為目前顯示中 bitmap 的像素尺寸
 * （呼叫端傳入 `imageView.drawable` 的 intrinsic 尺寸，已反映目前生效的
 * 裁切狀態，見 plan-issue-3.md Global Constraints「長按框選僅支援
 * PAGE_FIT」），用於計算 FIT_CENTER letterbox 後內容在本 View 內的實際
 * 顯示範圍 [contentBounds]。
 */
class HighlightSelectionOverlayView(
    context: Context,
    private val contentWidthPx: Int,
    private val contentHeightPx: Int,
) : View(context) {

    private val density = context.resources.displayMetrics.density
    private val fillPaint = Paint().apply {
        color = Color.argb(90, 255, 213, 79)
        style = Paint.Style.FILL
    }
    private val borderPaint = Paint().apply {
        color = Color.argb(220, 255, 179, 0)
        style = Paint.Style.STROKE
        strokeWidth = 2f * density
    }

    private var contentBounds = RectF()
    private var rectPx = RectF()

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        contentBounds = computeFitCenterContentBounds(w, h, contentWidthPx, contentHeightPx)
    }

    /**
     * 由 `PdfReaderView` 收到 Dart 端 `beginAnnotationSelection`／
     * `updateAnnotationSelection` method call 後，依目前 anchor（長按
     * 起點）／drag（目前觸點）座標呼叫，皆為 View 像素座標。矩形永遠
     * clamp 在 [contentBounds] 內（不允許框選延伸到 letterbox 留白區域）。
     */
    fun updateRect(anchorPx: PointF, currentPx: PointF) {
        if (contentBounds.width() <= 0f || contentBounds.height() <= 0f) return
        val left = minOf(anchorPx.x, currentPx.x).coerceIn(contentBounds.left, contentBounds.right)
        val right = maxOf(anchorPx.x, currentPx.x).coerceIn(contentBounds.left, contentBounds.right)
        val top = minOf(anchorPx.y, currentPx.y).coerceIn(contentBounds.top, contentBounds.bottom)
        val bottom = maxOf(anchorPx.y, currentPx.y).coerceIn(contentBounds.top, contentBounds.bottom)
        rectPx = RectF(left, top, right, bottom)
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawRect(rectPx, fillPaint)
        canvas.drawRect(rectPx, borderPaint)
    }

    /**
     * 換算目前框選矩形為相對 [contentBounds] 的百分比值（0.0-1.0），供
     * `PdfReaderView` 送給 Dart 端（見 spec.md 座標協定）。[contentBounds]
     * 尚未量測完成（極早期 layout 尚未跑過 `onSizeChanged`）時回傳全零矩形，
     * 呼叫端須視為退化案例（見 Task 8 `finishHighlightSelection` 的最小
     * 尺寸檢查，全零矩形必然小於門檻、會被當成取消處理）。
     */
    internal fun currentRelativeRect(): PercentRectPx {
        if (contentBounds.width() <= 0f || contentBounds.height() <= 0f) {
            return PercentRectPx(0f, 0f, 0f, 0f)
        }
        return PercentRectPx(
            left = (rectPx.left - contentBounds.left) / contentBounds.width(),
            top = (rectPx.top - contentBounds.top) / contentBounds.height(),
            right = (rectPx.right - contentBounds.left) / contentBounds.width(),
            bottom = (rectPx.bottom - contentBounds.top) / contentBounds.height(),
        )
    }

    /**
     * 【審查修正，Finding 1】換算目前框選矩形為相對本 View 自身完整尺寸
     * （`width`/`height`，即含 letterbox 留白的完整範圍）的百分比值，與
     * [currentRelativeRect] 的差異僅在分母／偏移基準：這裡直接除以本 View
     * 的 `width`/`height`，不扣除／不除以 [contentBounds]。供 Dart 端定位
     * 浮動 `AnnotationToolbar` 等 UI 使用——工具列疊在整個 widget 座標系
     * 之上，PAGE_FIT 模式下頁面常因長寬比與螢幕不同產生 letterbox，若拿
     * 內容相對值直接乘上整個 widget 尺寸，會偏移 letterbox 留白的量。
     * [currentRelativeRect]（內容相對值）維持不變，持久化／重繪仍使用它。
     */
    internal fun currentWidgetRelativeRect(): PercentRectPx {
        if (width <= 0 || height <= 0) {
            return PercentRectPx(0f, 0f, 0f, 0f)
        }
        return PercentRectPx(
            left = rectPx.left / width,
            top = rectPx.top / height,
            right = rectPx.right / width,
            bottom = rectPx.bottom / height,
        )
    }
}

/** 原生端內部使用的百分比矩形值物件（0.0-1.0），對應 Dart `PercentRect`。*/
internal data class PercentRectPx(val left: Float, val top: Float, val right: Float, val bottom: Float)
