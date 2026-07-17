package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PdfAnnotationOverlayTest {

    @Test
    fun `正確解析完整欄位的單筆標記`() {
        val list = PdfReaderView.parsePdfAnnotationOverlays(listOf(
            mapOf(
                "pageIndex" to 3,
                "left" to 0.1,
                "top" to 0.2,
                "right" to 0.3,
                "bottom" to 0.4,
                "tint" to 0x73FDE047,
                "isUnderline" to false,
                "isNoteOnly" to false,
            ),
        ))
        assertEquals(1, list.size)
        assertEquals(3, list.single().pageIndex)
        assertEquals(0x73FDE047, list.single().tint)
    }

    @Test
    fun `缺少必要數值欄位的項目略過、不影響其餘項目`() {
        val list = PdfReaderView.parsePdfAnnotationOverlays(listOf(
            mapOf("pageIndex" to 1, "left" to 0.0, "top" to 0.0, "right" to 1.0), // 缺 bottom/tint
            mapOf(
                "pageIndex" to 2, "left" to 0.0, "top" to 0.0, "right" to 1.0, "bottom" to 1.0,
                "tint" to 0x73D1D5DB,
            ),
        ))
        assertEquals(1, list.size)
        assertEquals(2, list.single().pageIndex)
    }

    @Test
    fun `isUnderline／isNoteOnly 缺席時預設為 false`() {
        val list = PdfReaderView.parsePdfAnnotationOverlays(listOf(
            mapOf(
                "pageIndex" to 0, "left" to 0.0, "top" to 0.0, "right" to 1.0, "bottom" to 1.0,
                "tint" to 1,
            ),
        ))
        assertTrue(!list.single().isUnderline)
        assertTrue(!list.single().isNoteOnly)
    }
}
