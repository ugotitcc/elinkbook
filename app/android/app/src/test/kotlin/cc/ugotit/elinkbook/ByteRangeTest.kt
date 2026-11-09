package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ByteRangeTest {
    private val maxBytes = 4L * 1024 * 1024 // 4 MB

    @Test
    fun `正常區段回傳 start until end`() {
        val range = clampByteRange(start = 0, end = 100, length = 1000, maxBytes = maxBytes)
        assertEquals(0L until 100L, range)
    }

    @Test
    fun `end 超過長度被夾回 length`() {
        val range = clampByteRange(start = 500, end = 1500, length = 1000, maxBytes = maxBytes)
        assertEquals(500L until 1000L, range)
    }

    @Test
    fun `start 為負回傳 null`() {
        assertNull(clampByteRange(start = -1, end = 100, length = 1000, maxBytes = maxBytes))
    }

    @Test
    fun `start 大於等於 length 回傳 null`() {
        assertNull(clampByteRange(start = 1000, end = 1500, length = 1000, maxBytes = maxBytes))
        assertNull(clampByteRange(start = 1001, end = 1500, length = 1000, maxBytes = maxBytes))
    }

    @Test
    fun `end 小於等於 start 回傳 null`() {
        assertNull(clampByteRange(start = 100, end = 100, length = 1000, maxBytes = maxBytes))
        assertNull(clampByteRange(start = 100, end = 99, length = 1000, maxBytes = maxBytes))
    }

    @Test
    fun `區段超過 maxBytes 回傳 null`() {
        val overMax = maxBytes + 1
        assertNull(clampByteRange(start = 0, end = overMax, length = overMax * 2, maxBytes = maxBytes))
    }

    @Test
    fun `先檢查原始區段大小：start 0, end 5MB, length 1MB, maxBytes 4MB 回傳 null`() {
        val oneMb = 1024L * 1024
        val fourMb = 4L * 1024 * 1024
        val fiveMb = 5L * 1024 * 1024
        assertNull(clampByteRange(start = 0, end = fiveMb, length = oneMb, maxBytes = fourMb))
    }

    @Test
    fun `start 0, end 3MB, length 1MB 回傳 0 until 1MB`() {
        val oneMb = 1024L * 1024
        val threeMb = 3L * 1024 * 1024
        val fourMb = 4L * 1024 * 1024
        assertEquals(0L until oneMb, clampByteRange(start = 0, end = threeMb, length = oneMb, maxBytes = fourMb))
    }
}
