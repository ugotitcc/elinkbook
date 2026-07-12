package cc.ugotit.elinkbook

import org.junit.Assert.assertArrayEquals
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

    // ---- detectCropRectFromPixels ----

    @Test
    fun `10x10 網格中央 6x6 黑色區塊被正確偵測為裁切邊界（含 1% 邊距）`() {
        val pixels = buildPixels(10, 10) { x, y ->
            if (x in 2..7 && y in 2..7) BLACK else WHITE
        }

        val result = PdfImageProcessor.detectCropRectFromPixels(pixels, width = 10, height = 10)

        assertEquals(0.19f, result.left, 1e-4f)
        assertEquals(0.19f, result.top, 1e-4f)
        assertEquals(0.71f, result.right, 1e-4f)
        assertEquals(0.71f, result.bottom, 1e-4f)
    }

    @Test
    fun `全白網格（無內容）時掃描收斂到角落退化矩形，不拋例外`() {
        val pixels = buildPixels(10, 10) { _, _ -> WHITE }

        val result = PdfImageProcessor.detectCropRectFromPixels(pixels, width = 10, height = 10)

        assertEquals(0.89f, result.left, 1e-4f)
        assertEquals(0.89f, result.top, 1e-4f)
        assertEquals(0.91f, result.right, 1e-4f)
        assertEquals(0.91f, result.bottom, 1e-4f)
    }

    @Test
    fun `全黑網格時內容從四邊緣即被偵測到，left top 因負邊距被 coerceIn 夾到 0`() {
        val pixels = buildPixels(10, 10) { _, _ -> BLACK }

        val result = PdfImageProcessor.detectCropRectFromPixels(pixels, width = 10, height = 10)

        assertEquals(0f, result.left, 1e-4f)
        assertEquals(0f, result.top, 1e-4f)
        assertEquals(0.91f, result.right, 1e-4f)
        assertEquals(0.91f, result.bottom, 1e-4f)
    }

    @Test
    fun `唯一內容像素落在原點時四邊掃描收斂到同一列行，驗證邊距下限與掃描步進`() {
        val pixels = buildPixels(10, 10) { x, y -> if (x == 0 && y == 0) BLACK else WHITE }

        val result = PdfImageProcessor.detectCropRectFromPixels(pixels, width = 10, height = 10)

        assertEquals(0f, result.left, 1e-4f)
        assertEquals(0f, result.top, 1e-4f)
        assertEquals(0.01f, result.right, 1e-4f)
        assertEquals(0.01f, result.bottom, 1e-4f)
    }

    // ---- contrastBrightnessColorMatrix ----

    @Test
    fun `contrast 與 brightness 皆為 0 時回傳單位矩陣（無視覺變化）`() {
        val matrix = PdfImageProcessor.contrastBrightnessColorMatrix(contrast = 0f, brightness = 0f)

        val expected = floatArrayOf(
            1f, 0f, 0f, 0f, 0f,
            0f, 1f, 0f, 0f, 0f,
            0f, 0f, 1f, 0f, 0f,
            0f, 0f, 0f, 1f, 0f,
        )
        assertArrayEquals(expected, matrix, 1e-4f)
    }

    @Test
    fun `contrast=50 brightness=20 時依標準公式算出對應的 ColorMatrix 係數`() {
        val matrix = PdfImageProcessor.contrastBrightnessColorMatrix(contrast = 50f, brightness = 20f)

        // contrastFactor = (100+50)/100 = 1.5
        // brightnessOffset = 20 * 2.55 = 51.0
        // translate = 51.0 + (255 - 1.5*255)/2 = 51.0 - 63.75 = -12.75
        val expected = floatArrayOf(
            1.5f, 0f, 0f, 0f, -12.75f,
            0f, 1.5f, 0f, 0f, -12.75f,
            0f, 0f, 1.5f, 0f, -12.75f,
            0f, 0f, 0f, 1f, 0f,
        )
        assertArrayEquals(expected, matrix, 1e-4f)
    }

    // ---- pageRenderScale ----

    @Test
    fun `density 低於下限 2_0 時夾限為 2_0`() {
        val scale = PdfImageProcessor.pageRenderScale(density = 1.0f)

        assertEquals(2.0f, scale, 1e-4f)
    }

    @Test
    fun `density 剛好等於下限 2_0 時原樣返回`() {
        val scale = PdfImageProcessor.pageRenderScale(density = 2.0f)

        assertEquals(2.0f, scale, 1e-4f)
    }

    @Test
    fun `density 落在區間內時原樣返回，不夾限`() {
        val scale = PdfImageProcessor.pageRenderScale(density = 2.75f)

        assertEquals(2.75f, scale, 1e-4f)
    }

    @Test
    fun `density 高於上限 3_0 時夾限為 3_0`() {
        val scale = PdfImageProcessor.pageRenderScale(density = 4.0f)

        assertEquals(3.0f, scale, 1e-4f)
    }
}
