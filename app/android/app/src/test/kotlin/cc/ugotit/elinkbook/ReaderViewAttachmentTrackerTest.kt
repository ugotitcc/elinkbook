package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * ReaderViewAttachmentTracker 是頂層 object（單例），狀態會在同一個 JVM
 * 測試行程內跨測試方法殘留。每個測試案例刻意平衡自己呼叫的
 * attach()/detach() 次數，並只斷言呼叫前後的「相對」狀態變化，不假設一個
 * 全域的初始 0 基準——避免測試執行順序影響結果。
 */
class ReaderViewAttachmentTrackerTest {

    @Test
    fun `attach 後 isAnyAttached 為 true，detach 後恢復呼叫前狀態`() {
        val before = ReaderViewAttachmentTracker.isAnyAttached
        ReaderViewAttachmentTracker.attach()
        assertTrue(ReaderViewAttachmentTracker.isAnyAttached)
        ReaderViewAttachmentTracker.detach()
        assertEquals(before, ReaderViewAttachmentTracker.isAnyAttached)
    }

    @Test
    fun `多次 attach 後單次 detach 仍為 attached`() {
        ReaderViewAttachmentTracker.attach()
        ReaderViewAttachmentTracker.attach()
        assertTrue(ReaderViewAttachmentTracker.isAnyAttached)
        ReaderViewAttachmentTracker.detach()
        assertTrue(ReaderViewAttachmentTracker.isAnyAttached)
        ReaderViewAttachmentTracker.detach() // 平衡第二次 attach()，恢復測試前狀態
    }

    @Test
    fun `suppressedUntilReattach 設為 true 後，attach() 會重設回 false`() {
        ReaderViewAttachmentTracker.suppressedUntilReattach = true
        assertTrue(ReaderViewAttachmentTracker.suppressedUntilReattach)
        ReaderViewAttachmentTracker.attach()
        assertFalse(ReaderViewAttachmentTracker.suppressedUntilReattach)
        ReaderViewAttachmentTracker.detach() // 平衡呼叫，恢復測試前狀態
    }

    @Test
    fun `detach() 不會重設 suppressedUntilReattach，只有 attach() 才會`() {
        ReaderViewAttachmentTracker.attach()
        ReaderViewAttachmentTracker.suppressedUntilReattach = true
        ReaderViewAttachmentTracker.detach()
        assertTrue(ReaderViewAttachmentTracker.suppressedUntilReattach)
        ReaderViewAttachmentTracker.suppressedUntilReattach = false // 恢復測試前狀態
    }

    @Test
    fun `detach() 呼叫次數多於 attach()，計數器下限保護在 0（單次 attach 即恢復 attached）`() {
        val before = ReaderViewAttachmentTracker.isAnyAttached
        ReaderViewAttachmentTracker.detach() // 多餘的 detach()，模擬異常生命週期情境
        ReaderViewAttachmentTracker.detach() // 再一次多餘的 detach()
        ReaderViewAttachmentTracker.attach()
        assertTrue(
            "計數器應保持下限在 0，單次 attach() 後即應為 attached，不因先前多餘 detach() " +
                "累積負數而需要多次 attach() 才能恢復",
            ReaderViewAttachmentTracker.isAnyAttached,
        )
        ReaderViewAttachmentTracker.detach() // 恢復到測試前狀態
        assertEquals(before, ReaderViewAttachmentTracker.isAnyAttached)
    }
}
