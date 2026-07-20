package cc.ugotit.elinkbook

import java.util.concurrent.atomic.AtomicInteger

/**
 * 追蹤目前是否有原生 Reader PlatformView（EpubReaderView／PdfReaderView）
 * 附加於畫面上，供 MainActivity.dispatchKeyEvent()（epic-7-interaction
 * Issue 7）判斷是否應攔截音量鍵。攔截依據刻意採用原生端可自行觀測的真實
 * 狀態，而非 Dart 端經 MethodChannel 主動通知的 async 旗標（design.md
 * 決策 #19 審查修正：async 旗標與 Flutter route 離開之間存在理論上的
 * 競態窗口，PlatformView 附加/移除是原生端唯一可靠、無額外非同步延遲的
 * 真實訊號）。
 *
 * 假設同時最多一個原生 Reader View 附加（見 spec.md「已知限制」）：目前
 * 架構下 ReaderScreen 同時只會掛載一個 EpubReaderView 或 PdfReaderView，
 * 計數器語意（>0 即攔截）在此前提下正確。
 */
object ReaderViewAttachmentTracker {
    private val count = AtomicInteger(0)

    /** 目前是否有任一 Reader PlatformView 附加。 */
    val isAnyAttached: Boolean
        get() = count.get() > 0

    /**
     * Dart 端 ReaderScreen 的 PopScope.onPopInvokedWithResult 於 pop 動作
     * 啟動當下（早於退場轉場動畫、更早於 PlatformView.dispose()）透過
     * notifyLeavingReader method channel 呼叫設為 true，讓
     * dispatchKeyEvent() 立即停止攔截音量鍵，不必等待 detach() 才釋放
     * （轉場動畫期間 PlatformView 尚未 dispose，isAnyAttached 仍為
     * true）。attach() 時重設回 false——下次真正開新書時恢復正常攔截。
     */
    @Volatile
    var suppressedUntilReattach: Boolean = false

    /** EpubReaderView／PdfReaderView 建構時（init 區塊）呼叫。 */
    fun attach() {
        count.incrementAndGet()
        suppressedUntilReattach = false
    }

    /**
     * EpubReaderView／PdfReaderView 的 dispose() 內呼叫。下限保護在 0
     * （`maxOf(0, it - 1)`，審查修正）：Flutter PlatformView 生命週期保證
     * 每個實例只會 dispose() 一次，正常路徑不會重複 detach()；但用
     * `getAndUpdate` 保護下限，避免任何未預期的重複呼叫讓計數器變負數、
     * 需要多次 attach() 才能恢復 isAnyAttached，是零成本的防禦性寫法。
     */
    fun detach() {
        count.getAndUpdate { maxOf(0, it - 1) }
    }
}
