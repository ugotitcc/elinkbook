package cc.ugotit.elinkbook

/**
 * EpubReaderView 用到的固定版面（FXL）縮放數值計算邏輯：從 EpubReaderView.kt
 * 抽離而成的 pure-Kotlin 模組（見 docs/epics.md「EpubReaderView.kt FXL 縮放邏輯
 * 抽離為 EpubFxlScaler」列、docs/epics/epic-16-dual-page/plans/plan-issue-8.md）：
 * 不依賴 WebView、ViewTreeObserver 或任何 Android View 型別，只接受量測完成後的
 * 純數值輸入/輸出，可在純 JVM 單元測試（app/src/test）直接以固定數值驗證，不需要
 * 真機/模擬器即可執行。刻意設計為無狀態（object，不持有任何 var）——跨頁快取
 * （cachedFxlFitScale）是綁定單一 EpubReaderView 實例生命週期的狀態，留在
 * EpubReaderView.kt 內，不搬進此模組。
 *
 * 【給 Epic 16 Issue 6（EPUB FXL 雙頁）實作者的提示】依本檔案 plan-issue-8.md
 * 的 Global Constraints，雙頁模式的縮放邏輯應在此模組內擴充，而非退回在
 * EpubReaderView.kt 就地實作。雙頁（spread）生效時，`computeFitScale` 目前接受
 * 的 `availableWidth` 語意會不再等於「單一 WebView 可用的寬度」——每個 WebView
 * 只佔可視寬度的一半，且左右兩頁併排時通常需要扣除中縫（gap）寬度。實作時可考慮
 * 新增一個明確接受「每頁可用寬度」（呼叫端已算好 `(containerWidth - gap) / 2`
 * 後再傳入）的多載或新函式，讓 `computeFitScale`/`computeCenteringTranslation`
 * 本身仍只處理「一個內容區塊 fit 進一個可用區塊」這個單一職責，雙頁的寬度切分/
 * 中縫扣除邏輯留給呼叫端（或新的專屬函式）決定，避免這兩個既有函式的參數語意
 * 因為雙頁模式而變得模糊。
 */
object EpubFxlScaler {

    /**
     * 依可用容器尺寸（[availableWidth]／[availableHeight]，通常是 container 的
     * 量測寬高）與內容原始尺寸（[contentWidth]／[contentHeight]，通常是 WebView
     * 的量測寬高）計算等比縮放係數。取寬度縮放比與高度縮放比中較小的一個（確保
     * 兩個維度都不會溢出容器，對應 Fit.CONTAIN 語意），並以 `coerceAtMost(1f)`
     * 夾限——FXL 縮放只縮小內容以符合可視範圍，不會把原本就比容器小的內容放大。
     */
    fun computeFitScale(
        availableWidth: Int,
        availableHeight: Int,
        contentWidth: Int,
        contentHeight: Int,
    ): Float {
        return minOf(
            availableWidth.toFloat() / contentWidth.toFloat(),
            availableHeight.toFloat() / contentHeight.toFloat(),
        ).coerceAtMost(1f)
    }

    /** [computeCenteringTranslation] 的回傳值：縮放後內容需要疊加的水平/垂直位移
     * （對應 `View.translationX`/`translationY`），使縮放後內容在可用容器內置中。*/
    data class Translation(val x: Float, val y: Float)

    /**
     * 依可用容器尺寸（[availableWidth]／[availableHeight]）、內容原始尺寸
     * （[contentWidth]／[contentHeight]）、已算好的縮放係數 [scale]，以及內容目前
     * （未經校正、由呼叫端透過 `View.getLocationOnScreen()` 量測所得）相對容器的
     * 原始位置（[currentLeft]／[currentTop]），計算需要疊加的 translationX/Y，使
     * 縮放後的內容剛好水平和垂直置中在容器裡。
     *
     * [currentLeft]／[currentTop] 可能非零、甚至為負值——呼叫端的排版系統（例如
     * Readium 內建 XML 對 WebView 做的置中）可能在這個函式執行前就已經把內容擺在
     * 某個非原點的位置；本函式不假設呼叫端的排版邏輯，只單純計算「從目前位置到
     * 置中位置」所需要的位移量，不論起點在哪裡都能算出正確的最終位置。
     */
    fun computeCenteringTranslation(
        availableWidth: Int,
        availableHeight: Int,
        contentWidth: Int,
        contentHeight: Int,
        scale: Float,
        currentLeft: Float,
        currentTop: Float,
    ): Translation {
        val scaledWidth = contentWidth * scale
        val scaledHeight = contentHeight * scale
        val desiredLeft = (availableWidth - scaledWidth) / 2f
        val desiredTop = (availableHeight - scaledHeight) / 2f
        return Translation(desiredLeft - currentLeft, desiredTop - currentTop)
    }
}
