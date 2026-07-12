package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Test

class EpubFxlScalerTest {

    // ---- computeFitScale ----

    @Test
    fun `高度為縮放瓶頸時，取較小的高度縮放比`() {
        // available 1000x1600、content 800x1600：寬度比 1000/800=1.25，
        // 高度比 1600/1600=1.0，取較小值 1.0（本例高度比本身已是瓶頸）。
        val scale = EpubFxlScaler.computeFitScale(
            availableWidth = 1000,
            availableHeight = 1600,
            contentWidth = 800,
            contentHeight = 1600,
        )

        assertEquals(1.0f, scale, 1e-4f)
    }

    @Test
    fun `寬度為縮放瓶頸時，取較小的寬度縮放比`() {
        // available 800x2000、content 1600x2000：寬度比 800/1600=0.5，
        // 高度比 2000/2000=1.0，取較小值 0.5（寬度是瓶頸）。
        val scale = EpubFxlScaler.computeFitScale(
            availableWidth = 800,
            availableHeight = 2000,
            contentWidth = 1600,
            contentHeight = 2000,
        )

        assertEquals(0.5f, scale, 1e-4f)
    }

    @Test
    fun `內容小於容器時不放大，縮放比被 coerceAtMost 夾在 1`() {
        // available 2000x2000、content 1000x1000：兩軸比例皆為 2.0，
        // 若不夾限會放大成 2 倍，但 FXL 縮放語意是「只縮小、不放大」。
        val scale = EpubFxlScaler.computeFitScale(
            availableWidth = 2000,
            availableHeight = 2000,
            contentWidth = 1000,
            contentHeight = 1000,
        )

        assertEquals(1.0f, scale, 1e-4f)
    }

    @Test
    fun `寬高比例一放大一縮小時，仍取較小值（縮小方向勝出）`() {
        // available 1000x1000、content 500x2000：寬度比 1000/500=2.0（若單看
        // 這一軸會放大），高度比 1000/2000=0.5（這一軸需要縮小）。取較小值
        // 0.5，確保高度方向不會溢出容器，即使寬度方向原本還有放大空間。
        val scale = EpubFxlScaler.computeFitScale(
            availableWidth = 1000,
            availableHeight = 1000,
            contentWidth = 500,
            contentHeight = 2000,
        )

        assertEquals(0.5f, scale, 1e-4f)
    }

    // ---- computeCenteringTranslation ----

    @Test
    fun `原始位置在原點時，置中位移等於容器與縮放後內容尺寸差的一半`() {
        // available 1000x1000、content 800x800、scale=1.0（縮放後仍是 800x800）、
        // currentLeft/currentTop=0（尚未有任何位移）：置中位移 = (1000-800)/2 = 100。
        val translation = EpubFxlScaler.computeCenteringTranslation(
            availableWidth = 1000,
            availableHeight = 1000,
            contentWidth = 800,
            contentHeight = 800,
            scale = 1.0f,
            currentLeft = 0f,
            currentTop = 0f,
        )

        assertEquals(100f, translation.x, 1e-4f)
        assertEquals(100f, translation.y, 1e-4f)
    }

    @Test
    fun `原始位置非原點（含負值偏移）時，置中位移會扣掉目前已有的偏移量`() {
        // available 1080x1600、content 1080x1920、scale=0.75（縮放後 810x1440）：
        // desiredLeft=(1080-810)/2=135，desiredTop=(1600-1440)/2=80。
        // currentLeft=50（Readium 排版已有的水平偏移）、currentTop=-20（垂直方向
        // 已往上偏移，對應 EpubReaderView.kt 註解描述的「WebView 天然高度比容器
        // 可用高度更高、置中後往上位移」情境）：
        // x = 135 - 50 = 85；y = 80 - (-20) = 100。
        val translation = EpubFxlScaler.computeCenteringTranslation(
            availableWidth = 1080,
            availableHeight = 1600,
            contentWidth = 1080,
            contentHeight = 1920,
            scale = 0.75f,
            currentLeft = 50f,
            currentTop = -20f,
        )

        assertEquals(85f, translation.x, 1e-4f)
        assertEquals(100f, translation.y, 1e-4f)
    }

    @Test
    fun `縮放後內容剛好等於容器尺寸且無原始偏移時，置中位移為零`() {
        val translation = EpubFxlScaler.computeCenteringTranslation(
            availableWidth = 1200,
            availableHeight = 900,
            contentWidth = 1200,
            contentHeight = 900,
            scale = 1.0f,
            currentLeft = 0f,
            currentTop = 0f,
        )

        assertEquals(0f, translation.x, 1e-4f)
        assertEquals(0f, translation.y, 1e-4f)
    }
}
