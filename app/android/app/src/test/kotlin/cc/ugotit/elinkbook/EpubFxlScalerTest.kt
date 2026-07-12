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
}
