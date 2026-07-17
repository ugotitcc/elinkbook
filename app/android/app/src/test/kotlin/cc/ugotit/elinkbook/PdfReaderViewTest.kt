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

    // ---- DualPageMode.fromWireValue ----

    @Test
    fun `DualPageMode fromWireValue 傳入 always 時回傳 ALWAYS`() {
        val mode = PdfReaderView.DualPageMode.fromWireValue("always")
        assertEquals(PdfReaderView.DualPageMode.ALWAYS, mode)
    }

    @Test
    fun `DualPageMode fromWireValue 傳入 never 時回傳 NEVER`() {
        val mode = PdfReaderView.DualPageMode.fromWireValue("never")
        assertEquals(PdfReaderView.DualPageMode.NEVER, mode)
    }

    @Test
    fun `DualPageMode fromWireValue 傳入 auto 時回傳 AUTO`() {
        val mode = PdfReaderView.DualPageMode.fromWireValue("auto")
        assertEquals(PdfReaderView.DualPageMode.AUTO, mode)
    }

    @Test
    fun `DualPageMode fromWireValue 傳入 null 時回傳預設值 AUTO`() {
        val mode = PdfReaderView.DualPageMode.fromWireValue(null)
        assertEquals(PdfReaderView.DualPageMode.AUTO, mode)
    }

    @Test
    fun `DualPageMode fromWireValue 傳入未知字串時回傳預設值 AUTO`() {
        val mode = PdfReaderView.DualPageMode.fromWireValue("unknown-garbage")
        assertEquals(PdfReaderView.DualPageMode.AUTO, mode)
    }

    // ---- DualPageDirection.fromWireValue ----

    @Test
    fun `DualPageDirection fromWireValue 傳入 rtl 時回傳 RTL`() {
        val direction = PdfReaderView.DualPageDirection.fromWireValue("rtl")
        assertEquals(PdfReaderView.DualPageDirection.RTL, direction)
    }

    @Test
    fun `DualPageDirection fromWireValue 傳入 ltr 時回傳 LTR`() {
        val direction = PdfReaderView.DualPageDirection.fromWireValue("ltr")
        assertEquals(PdfReaderView.DualPageDirection.LTR, direction)
    }

    @Test
    fun `DualPageDirection fromWireValue 傳入 null 時回傳預設值 RTL`() {
        val direction = PdfReaderView.DualPageDirection.fromWireValue(null)
        assertEquals(PdfReaderView.DualPageDirection.RTL, direction)
    }

    @Test
    fun `DualPageDirection fromWireValue 傳入未知字串時回傳預設值 RTL`() {
        val direction = PdfReaderView.DualPageDirection.fromWireValue("unknown-garbage")
        assertEquals(PdfReaderView.DualPageDirection.RTL, direction)
    }

    // ---- isDualPageEnabled ----

    @Test
    fun `isDualPageEnabled always 模式一律生效`() {
        val enabled = PdfReaderView.isDualPageEnabled(
            dualPageMode = PdfReaderView.DualPageMode.ALWAYS,
            isLandscape = false,
            cropEditModeActive = false,
        )
        assertEquals(true, enabled)
    }

    @Test
    fun `isDualPageEnabled never 模式一律不生效`() {
        val enabled = PdfReaderView.isDualPageEnabled(
            dualPageMode = PdfReaderView.DualPageMode.NEVER,
            isLandscape = true,
            cropEditModeActive = false,
        )
        assertEquals(false, enabled)
    }

    @Test
    fun `isDualPageEnabled auto 模式橫向時生效`() {
        val enabled = PdfReaderView.isDualPageEnabled(
            dualPageMode = PdfReaderView.DualPageMode.AUTO,
            isLandscape = true,
            cropEditModeActive = false,
        )
        assertEquals(true, enabled)
    }

    @Test
    fun `isDualPageEnabled auto 模式直向時不生效`() {
        val enabled = PdfReaderView.isDualPageEnabled(
            dualPageMode = PdfReaderView.DualPageMode.AUTO,
            isLandscape = false,
            cropEditModeActive = false,
        )
        assertEquals(false, enabled)
    }

    @Test
    fun `isDualPageEnabled 手動裁切編輯模式中一律強制不生效`() {
        val enabled = PdfReaderView.isDualPageEnabled(
            dualPageMode = PdfReaderView.DualPageMode.ALWAYS,
            isLandscape = true,
            cropEditModeActive = true,
        )
        assertEquals(false, enabled)
    }

    // ---- pairIndices ----

    @Test
    fun `pairIndices ltr 方向左頁為 anchor、右頁為 anchor 加 1`() {
        val (left, right) = PdfReaderView.pairIndices(3, PdfReaderView.DualPageDirection.LTR)
        assertEquals(3, left)
        assertEquals(4, right)
    }

    @Test
    fun `pairIndices rtl 方向右頁為 anchor、左頁為 anchor 加 1`() {
        val (left, right) = PdfReaderView.pairIndices(3, PdfReaderView.DualPageDirection.RTL)
        assertEquals(4, left)
        assertEquals(3, right)
    }

    // ---- nextPageStep ----

    @Test
    fun `nextPageStep 雙頁未生效時步進 1`() {
        val step = PdfReaderView.nextPageStep(
            currentPageIndex = 5,
            dualPageEnabled = false,
            coverAlone = true,
        )
        assertEquals(1, step)
    }

    @Test
    fun `nextPageStep 雙頁生效且目前在封面且封面獨立開啟時步進 1`() {
        val step = PdfReaderView.nextPageStep(
            currentPageIndex = 0,
            dualPageEnabled = true,
            coverAlone = true,
        )
        assertEquals(1, step)
    }

    @Test
    fun `nextPageStep 雙頁生效但封面獨立關閉時，index 0 也步進 2`() {
        val step = PdfReaderView.nextPageStep(
            currentPageIndex = 0,
            dualPageEnabled = true,
            coverAlone = false,
        )
        assertEquals(2, step)
    }

    @Test
    fun `nextPageStep 雙頁生效且非封面情境時步進 2`() {
        val step = PdfReaderView.nextPageStep(
            currentPageIndex = 3,
            dualPageEnabled = true,
            coverAlone = true,
        )
        assertEquals(2, step)
    }

    // ---- previousPageStep（C-4 對稱規則）----

    @Test
    fun `previousPageStep 雙頁未生效時步進 1`() {
        val step = PdfReaderView.previousPageStep(
            currentPageIndex = 5,
            dualPageEnabled = false,
            coverAlone = true,
        )
        assertEquals(1, step)
    }

    @Test
    fun `previousPageStep 雙頁生效且目前在 spread 1,2 且封面獨立開啟時步進 1（回到封面）`() {
        val step = PdfReaderView.previousPageStep(
            currentPageIndex = 1,
            dualPageEnabled = true,
            coverAlone = true,
        )
        assertEquals(1, step)
    }

    @Test
    fun `previousPageStep 雙頁生效但封面獨立關閉時，index 1 也步進 2`() {
        val step = PdfReaderView.previousPageStep(
            currentPageIndex = 1,
            dualPageEnabled = true,
            coverAlone = false,
        )
        assertEquals(2, step)
    }

    @Test
    fun `previousPageStep 雙頁生效且非回封面情境時步進 2`() {
        val step = PdfReaderView.previousPageStep(
            currentPageIndex = 5,
            dualPageEnabled = true,
            coverAlone = true,
        )
        assertEquals(2, step)
    }

    // ---- isAnnotationSelectionEligible（epic-6-annotations Issue 3）----

    @Test
    fun `isAnnotationSelectionEligible PAGE_FIT、非裁切、非雙頁時允許框選`() {
        val eligible = PdfReaderView.isAnnotationSelectionEligible(
            fitMode = PdfReaderView.PdfFitMode.PAGE_FIT,
            dualPageEnabled = false,
            cropEditModeActive = false,
        )
        assertEquals(true, eligible)
    }

    @Test
    fun `isAnnotationSelectionEligible 非 PAGE_FIT 時不允許框選`() {
        val eligible = PdfReaderView.isAnnotationSelectionEligible(
            fitMode = PdfReaderView.PdfFitMode.FIT_WIDTH,
            dualPageEnabled = false,
            cropEditModeActive = false,
        )
        assertEquals(false, eligible)
    }

    @Test
    fun `isAnnotationSelectionEligible 雙頁模式生效時不允許框選`() {
        val eligible = PdfReaderView.isAnnotationSelectionEligible(
            fitMode = PdfReaderView.PdfFitMode.PAGE_FIT,
            dualPageEnabled = true,
            cropEditModeActive = false,
        )
        assertEquals(false, eligible)
    }

    @Test
    fun `isAnnotationSelectionEligible 裁切編輯模式中不允許框選`() {
        val eligible = PdfReaderView.isAnnotationSelectionEligible(
            fitMode = PdfReaderView.PdfFitMode.PAGE_FIT,
            dualPageEnabled = false,
            cropEditModeActive = true,
        )
        assertEquals(false, eligible)
    }
}
