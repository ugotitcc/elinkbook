package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Test

class PdfContentBoundsTest {

    @Test
    fun `內容比容器寬時，上下留白、滿版寬度`() {
        val bounds = computeFitCenterContentBounds(
            viewWidth = 200, viewHeight = 200, contentWidthPx = 400, contentHeightPx = 100,
        )
        assertEquals(0f, bounds.left)
        assertEquals(200f, bounds.right)
        assertEquals(75f, bounds.top)
        assertEquals(125f, bounds.bottom)
    }

    @Test
    fun `內容比容器高時，左右留白、滿版高度`() {
        val bounds = computeFitCenterContentBounds(
            viewWidth = 200, viewHeight = 200, contentWidthPx = 100, contentHeightPx = 400,
        )
        assertEquals(75f, bounds.left)
        assertEquals(125f, bounds.right)
        assertEquals(0f, bounds.top)
        assertEquals(200f, bounds.bottom)
    }

    @Test
    fun `容器或內容尺寸為 0 時，退回整個容器範圍（避免除以零）`() {
        val bounds = computeFitCenterContentBounds(
            viewWidth = 200, viewHeight = 100, contentWidthPx = 0, contentHeightPx = 0,
        )
        assertEquals(0f, bounds.left)
        assertEquals(0f, bounds.top)
        assertEquals(200f, bounds.right)
        assertEquals(100f, bounds.bottom)
    }
}
