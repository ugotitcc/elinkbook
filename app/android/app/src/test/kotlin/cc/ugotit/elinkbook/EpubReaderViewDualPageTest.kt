package cc.ugotit.elinkbook

import cc.ugotit.elinkbook.EpubReaderView.DualPageMode
import org.junit.Assert.assertEquals
import org.junit.Test

class EpubReaderViewDualPageTest {
    @Test
    fun `isDualPageEnabled always 一律生效`() {
        assertEquals(true, EpubReaderView.isDualPageEnabled(DualPageMode.ALWAYS, isLandscape = false))
    }

    @Test
    fun `isDualPageEnabled auto 僅橫向生效`() {
        assertEquals(true, EpubReaderView.isDualPageEnabled(DualPageMode.AUTO, isLandscape = true))
        assertEquals(false, EpubReaderView.isDualPageEnabled(DualPageMode.AUTO, isLandscape = false))
    }

    @Test
    fun `isDualPageEnabled never 一律不生效`() {
        assertEquals(false, EpubReaderView.isDualPageEnabled(DualPageMode.NEVER, isLandscape = true))
    }

    @Test
    fun `DualPageMode fromWireValue 對應正確，未知值一律視為 auto`() {
        assertEquals(DualPageMode.ALWAYS, DualPageMode.fromWireValue("always"))
        assertEquals(DualPageMode.NEVER, DualPageMode.fromWireValue("never"))
        assertEquals(DualPageMode.AUTO, DualPageMode.fromWireValue("auto"))
        assertEquals(DualPageMode.AUTO, DualPageMode.fromWireValue(null))
        assertEquals(DualPageMode.AUTO, DualPageMode.fromWireValue("garbage"))
    }
}
