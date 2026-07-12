package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Test

class PdfImageProcessorTest {

    companion object {
        private const val WHITE = -0x1 // 0xFFFFFFFF.toInt()
        private const val BLACK = -0x1000000 // 0xFF000000.toInt()
        private const val SEMI_TRANSPARENT_WHITE = -0x55000001 // 0xAAFFFFFF.toInt()
    }

    private fun buildPixels(
        width: Int,
        height: Int,
        colorAt: (x: Int, y: Int) -> Int,
    ): IntArray {
        val pixels = IntArray(width * height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                pixels[y * width + x] = colorAt(x, y)
            }
        }
        return pixels
    }

    // ---- dilatePixels ----

    @Test
    fun `radius 為 0 時 dilatePixels 是恆等變換`() {
        val pixels = buildPixels(3, 3) { x, y -> if (x == 1 && y == 1) BLACK else WHITE }

        val result = PdfImageProcessor.dilatePixels(pixels, width = 3, height = 3, radius = 0)

        assertEquals(pixels.toList(), result.toList())
    }

    @Test
    fun `radius 為 1 時單一中心黑點在 3x3 網格內擴散至全部像素，且每個像素保留自身原始 alpha`() {
        val pixels = buildPixels(3, 3) { x, y ->
            when {
                x == 0 && y == 0 -> SEMI_TRANSPARENT_WHITE
                x == 1 && y == 1 -> BLACK
                else -> WHITE
            }
        }

        val result = PdfImageProcessor.dilatePixels(pixels, width = 3, height = 3, radius = 1)

        assertEquals(0xAA shl 24, result[0 * 3 + 0])
        assertEquals(BLACK, result[1 * 3 + 1])
        assertEquals(BLACK, result[2 * 3 + 2])
    }

    @Test
    fun `寬高為 1 的極端尺寸下 dilatePixels 不拋出例外，結果等同單像素恆等`() {
        val pixels = intArrayOf(BLACK)

        val result = PdfImageProcessor.dilatePixels(pixels, width = 1, height = 1, radius = 3)

        assertEquals(listOf(BLACK), result.toList())
    }
}
