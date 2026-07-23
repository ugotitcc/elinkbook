package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FoliateDecorationCodecTest {

    // --- argbIntToCssColor ---

    @Test
    fun `完全不透明色值換算 alpha 為 1_0`() {
        assertEquals(
            "rgba(255, 0, 0, 1.0)",
            FoliateDecorationCodec.argbIntToCssColor(0xFFFF0000.toInt()),
        )
    }

    @Test
    fun `完全透明色值換算 alpha 為 0_0`() {
        assertEquals(
            "rgba(0, 255, 0, 0.0)",
            FoliateDecorationCodec.argbIntToCssColor(0x0000FF00),
        )
    }

    @Test
    fun `半透明色值正確拆解 RGB 並換算 alpha 為 0-1 浮點數`() {
        // highlighterYellowTint = Color(0x73FDE047)，見 highlight_style.dart。
        val result = FoliateDecorationCodec.argbIntToCssColor(0x73FDE047)
        assertEquals("rgba(253, 224, 71, ${115 / 255.0})", result)
    }

    // --- buildDecorationEntries ---

    @Test
    fun `新格式 locatorJson 正確轉換為 cfi／color／isUnderline`() {
        val list = listOf(
            mapOf(
                "id" to "highlight:5",
                "locatorJson" to """{"cfi":"epubcfi(/6/8!/4[story-2-2])","index":3,"fraction":0.04}""",
                "tint" to 0xFFFF0000.toInt(),
                "isUnderline" to false,
            ),
        )
        val entries = FoliateDecorationCodec.buildDecorationEntries(list)
        assertEquals(1, entries.size)
        assertEquals("highlight:5", entries[0]["id"])
        assertEquals("epubcfi(/6/8!/4[story-2-2])", entries[0]["cfi"])
        assertEquals("rgba(255, 0, 0, 1.0)", entries[0]["color"])
        assertEquals(false, entries[0]["isUnderline"])
    }

    @Test
    fun `isUnderline 缺席時預設為 false`() {
        val list = listOf(
            mapOf(
                "id" to "note:1",
                "locatorJson" to """{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}""",
                "tint" to 0x73D1D5DB,
            ),
        )
        val entries = FoliateDecorationCodec.buildDecorationEntries(list)
        assertEquals(false, entries[0]["isUnderline"])
    }

    @Test
    fun `舊格式（Readium Locator JSON）locatorJson 該筆略過`() {
        val list = listOf(
            mapOf(
                "id" to "highlight:1",
                "locatorJson" to """{"href":"/OEBPS/chapter1.xhtml","locations":{"progression":0.1}}""",
                "tint" to 0xFFFF0000.toInt(),
                "isUnderline" to false,
            ),
        )
        assertTrue(FoliateDecorationCodec.buildDecorationEntries(list).isEmpty())
    }

    @Test
    fun `缺少 id 欄位的項目該筆略過`() {
        val list = listOf(
            mapOf(
                "locatorJson" to """{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}""",
                "tint" to 0xFFFF0000.toInt(),
            ),
        )
        assertTrue(FoliateDecorationCodec.buildDecorationEntries(list).isEmpty())
    }

    @Test
    fun `缺少 tint 欄位的項目該筆略過`() {
        val list = listOf(
            mapOf(
                "id" to "highlight:1",
                "locatorJson" to """{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}""",
            ),
        )
        assertTrue(FoliateDecorationCodec.buildDecorationEntries(list).isEmpty())
    }

    @Test
    fun `多筆項目保留順序，單筆失敗不影響其餘`() {
        val list = listOf(
            mapOf(
                "id" to "highlight:1",
                "locatorJson" to """{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}""",
                "tint" to 0xFFFF0000.toInt(),
                "isUnderline" to false,
            ),
            mapOf(
                "id" to "highlight:2",
                "locatorJson" to """{"href":"/OEBPS/chapter1.xhtml"}""",
                "tint" to 0xFF00FF00.toInt(),
                "isUnderline" to false,
            ),
            mapOf(
                "id" to "note:1",
                "locatorJson" to """{"cfi":"epubcfi(/6/6)","index":1,"fraction":0.5}""",
                "tint" to 0x73D1D5DB,
                "isUnderline" to true,
            ),
        )
        val entries = FoliateDecorationCodec.buildDecorationEntries(list)
        assertEquals(2, entries.size)
        assertEquals("highlight:1", entries[0]["id"])
        assertEquals("note:1", entries[1]["id"])
        assertEquals(true, entries[1]["isUnderline"])
    }

    @Test
    fun `空清單回傳空清單`() {
        assertTrue(FoliateDecorationCodec.buildDecorationEntries(emptyList()).isEmpty())
    }

    @Test
    fun `重複 cfi 的兩筆項目皆原樣保留，本函式不去重（已知限制，記錄於 main_js window_setDecorations 註解）`() {
        // spike-overlayer-annotations.md 第 63 行明確建議補一則此邊界情況的
        // 單元測試：兩筆不同標記剛好指向完全相同的 CFI 時，Kotlin 端本身
        // 不負責去重/覆蓋——實際的「後寫入覆蓋前者」行為發生在 JS 端的
        // decorationIdByCfi Map 語意（main.js window.setDecorations()），
        // 本函式的職責僅止於逐筆轉換 wire 格式，不對輸入清單做任何去重
        // 邏輯，此測試鎖定這個「原樣保留」的既定行為，避免未來有人誤以為
        // 這裡已經處理過重複 key。
        val sameCfi = """{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}"""
        val list = listOf(
            mapOf(
                "id" to "highlight:1",
                "locatorJson" to sameCfi,
                "tint" to 0xFFFF0000.toInt(),
                "isUnderline" to false,
            ),
            mapOf(
                "id" to "highlight:2",
                "locatorJson" to sameCfi,
                "tint" to 0xFF0000FF.toInt(),
                "isUnderline" to false,
            ),
        )
        val entries = FoliateDecorationCodec.buildDecorationEntries(list)
        assertEquals(2, entries.size)
        assertEquals("highlight:1", entries[0]["id"])
        assertEquals("epubcfi(/6/4)", entries[0]["cfi"])
        assertEquals("highlight:2", entries[1]["id"])
        assertEquals("epubcfi(/6/4)", entries[1]["cfi"])
    }
}
