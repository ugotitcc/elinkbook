package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Test

class EpubCharacterCounterTest {

    @Test
    fun `去除標籤後計算純文字字元數`() {
        val html = "<p>Hello world</p>"
        assertEquals(11, EpubCharacterCounter.countCharacters(html))
    }

    @Test
    fun `HTML entity 概略以空白取代並收斂連續空白`() {
        val html = "<p>Tom &amp; Jerry</p>"
        assertEquals(9, EpubCharacterCounter.countCharacters(html))
    }

    @Test
    fun `多層巢狀與自我閉合標籤皆被去除，只留下標籤間文字`() {
        val html = "<div><span>你好</span><br/>世界</div>"
        assertEquals(5, EpubCharacterCounter.countCharacters(html))
    }

    @Test
    fun `文字中的換行與多重空白收斂為單一空白`() {
        val html = "<p>Line1\n\n  Line2</p>"
        assertEquals(11, EpubCharacterCounter.countCharacters(html))
    }

    @Test
    fun `空字串回傳 0`() {
        assertEquals(0, EpubCharacterCounter.countCharacters(""))
    }
}
