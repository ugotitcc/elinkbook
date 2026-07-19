package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * 與 app/test/reader/zone_hit_test_test.dart 的 hitTestZoneIndex() 測試案例
 * 一一對應（spec.md 要求兩端演算法輸出一致，見該檔案測試案例）。
 */
class NavZoneHitTesterTest {

    private val width = 300f
    private val height = 300f

    @Test
    fun `左上角 (0,0) 回傳格子 0`() {
        assertEquals(0, NavZoneHitTester.cellIndex(0f, 0f, width, height))
    }

    @Test
    fun `正中心回傳格子 4`() {
        assertEquals(4, NavZoneHitTester.cellIndex(150f, 150f, width, height))
    }

    @Test
    fun `右上角（寬度邊界內）回傳格子 2`() {
        assertEquals(2, NavZoneHitTester.cellIndex(299f, 0f, width, height))
    }

    @Test
    fun `左下角（高度邊界內）回傳格子 6`() {
        assertEquals(6, NavZoneHitTester.cellIndex(0f, 299f, width, height))
    }

    @Test
    fun `右下角（寬高邊界內）回傳格子 8`() {
        assertEquals(8, NavZoneHitTester.cellIndex(299f, 299f, width, height))
    }

    @Test
    fun `dx 恰好等於 width（浮點邊界）仍 clamp 在格子 2，不產生 index 9`() {
        assertEquals(2, NavZoneHitTester.cellIndex(300f, 0f, width, height))
    }

    @Test
    fun `dy 恰好等於 height（浮點邊界）仍 clamp 在格子 6，不產生超界`() {
        assertEquals(6, NavZoneHitTester.cellIndex(0f, 300f, width, height))
    }

    @Test
    fun `第一條格線正上方座標 (dx=100) 歸屬 col 1`() {
        assertEquals(4, NavZoneHitTester.cellIndex(100f, 150f, width, height))
    }

    @Test
    fun `第二條格線正上方座標 (dx=200) 歸屬 col 2`() {
        assertEquals(5, NavZoneHitTester.cellIndex(200f, 150f, width, height))
    }

    @Test
    fun `width 或 height 為 0 或負數時，安全回傳格子 4，不拋出例外`() {
        assertEquals(4, NavZoneHitTester.cellIndex(10f, 10f, 0f, 300f))
        assertEquals(4, NavZoneHitTester.cellIndex(10f, 10f, 300f, 0f))
        assertEquals(4, NavZoneHitTester.cellIndex(10f, 10f, -1f, 300f))
        assertEquals(4, NavZoneHitTester.cellIndex(10f, 10f, 300f, -1f))
    }
}
