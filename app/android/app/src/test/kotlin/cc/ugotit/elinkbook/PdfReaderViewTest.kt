package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Test

class PdfReaderViewTest {

    // ---- PdfFitMode.fromWireValue ----

    @Test
    fun `fromWireValue 傳入 fitWidth 時回傳 FIT_WIDTH`() {
        val mode = PdfReaderView.PdfFitMode.fromWireValue("fitWidth")

        assertEquals(PdfReaderView.PdfFitMode.FIT_WIDTH, mode)
    }

    @Test
    fun `fromWireValue 傳入 actualSize 時回傳 ACTUAL_SIZE`() {
        val mode = PdfReaderView.PdfFitMode.fromWireValue("actualSize")

        assertEquals(PdfReaderView.PdfFitMode.ACTUAL_SIZE, mode)
    }

    @Test
    fun `fromWireValue 傳入 pageFit 時回傳 PAGE_FIT`() {
        val mode = PdfReaderView.PdfFitMode.fromWireValue("pageFit")

        assertEquals(PdfReaderView.PdfFitMode.PAGE_FIT, mode)
    }

    @Test
    fun `fromWireValue 傳入 null 時回傳預設值 PAGE_FIT`() {
        val mode = PdfReaderView.PdfFitMode.fromWireValue(null)

        assertEquals(PdfReaderView.PdfFitMode.PAGE_FIT, mode)
    }

    @Test
    fun `fromWireValue 傳入未知字串時回傳預設值 PAGE_FIT`() {
        val mode = PdfReaderView.PdfFitMode.fromWireValue("unknown-garbage")

        assertEquals(PdfReaderView.PdfFitMode.PAGE_FIT, mode)
    }

    // ---- PdfCropMode.fromWireValue ----

    @Test
    fun `fromWireValue 傳入 autoDetect 時回傳 AUTO_DETECT`() {
        val mode = PdfReaderView.PdfCropMode.fromWireValue("autoDetect")

        assertEquals(PdfReaderView.PdfCropMode.AUTO_DETECT, mode)
    }

    @Test
    fun `fromWireValue 傳入 manual 時回傳 MANUAL`() {
        val mode = PdfReaderView.PdfCropMode.fromWireValue("manual")

        assertEquals(PdfReaderView.PdfCropMode.MANUAL, mode)
    }

    @Test
    fun `fromWireValue 傳入 none 時回傳 NONE`() {
        val mode = PdfReaderView.PdfCropMode.fromWireValue("none")

        assertEquals(PdfReaderView.PdfCropMode.NONE, mode)
    }

    @Test
    fun `fromWireValue 傳入 null 時回傳預設值 NONE`() {
        val mode = PdfReaderView.PdfCropMode.fromWireValue(null)

        assertEquals(PdfReaderView.PdfCropMode.NONE, mode)
    }

    @Test
    fun `fromWireValue 傳入未知字串時正規化為 NONE（已知且經授權的行為差異，見 PdfCropMode KDoc）`() {
        val mode = PdfReaderView.PdfCropMode.fromWireValue("unknown-garbage")

        assertEquals(PdfReaderView.PdfCropMode.NONE, mode)
    }
}
