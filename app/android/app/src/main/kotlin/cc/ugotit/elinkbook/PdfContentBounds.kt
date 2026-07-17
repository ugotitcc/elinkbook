package cc.ugotit.elinkbook

import android.graphics.RectF

/**
 * FIT_CENTER letterbox 數學：內容依長寬比置中縮放至剛好完整顯示於容器內，
 * 多餘空間留白（epic-6-annotations Issue 3，抽出自
 * `CropOverlayView.computeContentBounds()`，供新增的
 * `HighlightSelectionOverlayView` 共用，見 plan-issue-3.md Task 7）。
 * [contentWidthPx]／[contentHeightPx] 是目前顯示中內容（PDF 頁面渲染出的
 * bitmap，可能已反映裁切狀態）的像素尺寸；回傳值是該內容在
 * `viewWidth`×`viewHeight` 容器內的實際顯示範圍。
 */
internal fun computeFitCenterContentBounds(
    viewWidth: Int,
    viewHeight: Int,
    contentWidthPx: Int,
    contentHeightPx: Int,
): RectF {
    if (viewWidth <= 0 || viewHeight <= 0 || contentWidthPx <= 0 || contentHeightPx <= 0) {
        // 注意：刻意不使用 RectF(left, top, right, bottom) 這個 4 引數建構子——
        // Android Gradle Plugin 的 JVM 單元測試（`testDebugUnitTest`）以「stub
        // android.jar」執行，任何 android.* 方法（含建構子）呼叫都會被置換為
        // no-op／拋例外，導致透過建構子設定的欄位值全部遺失、實際讀到
        // 0（見 PdfContentBoundsTest 除錯過程）。改用無參數建構子（其真實實作
        // 本來就是空函式，stub 與否結果相同）搭配直接欄位賦值（`left =`／
        // `.apply{}` 內的欄位寫入是純 JVM 欄位存取，不經過任何方法呼叫，不受
        // stub 影響），讓本函式在 JVM 單元測試與真實 Android 執行環境下行為
        // 一致。
        return RectF().apply {
            left = 0f
            top = 0f
            right = viewWidth.toFloat()
            bottom = viewHeight.toFloat()
        }
    }
    val viewRatio = viewWidth.toFloat() / viewHeight.toFloat()
    val contentRatio = contentWidthPx.toFloat() / contentHeightPx.toFloat()
    return if (contentRatio > viewRatio) {
        // 內容較「寬」：滿版寬度，上下留白
        val displayHeight = viewWidth / contentRatio
        val top = (viewHeight - displayHeight) / 2f
        RectF().apply {
            left = 0f
            this.top = top
            right = viewWidth.toFloat()
            bottom = top + displayHeight
        }
    } else {
        // 內容較「高」：滿版高度，左右留白
        val displayWidth = viewHeight * contentRatio
        val left = (viewWidth - displayWidth) / 2f
        RectF().apply {
            this.left = left
            top = 0f
            right = left + displayWidth
            bottom = viewHeight.toFloat()
        }
    }
}
