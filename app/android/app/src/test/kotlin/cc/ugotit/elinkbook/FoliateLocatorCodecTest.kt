package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FoliateLocatorCodecTest {

    // --- extractCfi ---

    @Test
    fun `新格式 JSON 正確取出 cfi 欄位`() {
        val json = """{"cfi":"epubcfi(/6/8!/4[story-2-2],/60/3:32,/70/1:32)","index":3,"fraction":0.042091}"""
        assertEquals(
            "epubcfi(/6/8!/4[story-2-2],/60/3:32,/70/1:32)",
            FoliateLocatorCodec.extractCfi(json),
        )
    }

    @Test
    fun `舊格式 Readium Locator JSON 沒有 cfi 欄位，回傳 null（優雅退回）`() {
        val readiumLocatorJson = """
            {"href":"/OEBPS/chapter1.xhtml","type":"application/xhtml+xml",
             "title":"Chapter 1","locations":{"progression":0.42,"totalProgression":0.1}}
        """.trimIndent()
        assertNull(FoliateLocatorCodec.extractCfi(readiumLocatorJson))
    }

    @Test
    fun `格式錯誤的 JSON 字串回傳 null，不拋出例外`() {
        assertNull(FoliateLocatorCodec.extractCfi("not a json string"))
    }

    @Test
    fun `null 輸入回傳 null`() {
        assertNull(FoliateLocatorCodec.extractCfi(null))
    }

    @Test
    fun `cfi 欄位為 null 值時回傳 null`() {
        assertNull(FoliateLocatorCodec.extractCfi("""{"cfi":null,"index":0,"fraction":0}"""))
    }

    @Test
    fun `cfi 欄位為非字串型別時回傳 null`() {
        assertNull(FoliateLocatorCodec.extractCfi("""{"cfi":12345,"index":0,"fraction":0}"""))
    }

    // --- parseTocEntries ---

    @Test
    fun `解析扁平（無巢狀子項目）目錄陣列`() {
        val json = """
            [{"title":"第一章","locatorJson":"{\"cfi\":\"epubcfi(/6/4)\",\"index\":0,\"fraction\":0.0}",
              "progression":0.0,"children":[]},
             {"title":"第二章","locatorJson":"{\"cfi\":\"epubcfi(/6/6)\",\"index\":1,\"fraction\":0.5}",
              "progression":0.5,"children":[]}]
        """.trimIndent()
        val entries = FoliateLocatorCodec.parseTocEntries(json)
        assertEquals(2, entries.size)
        assertEquals("第一章", entries[0]["title"])
        assertEquals(0.5, entries[1]["progression"])
    }

    @Test
    fun `解析含巢狀子項目的目錄陣列（round-trip 驗證巢狀結構保留）`() {
        val json = """
            [{"title":"第一部","locatorJson":"","progression":null,
              "children":[
                {"title":"第一章","locatorJson":"{\"cfi\":\"epubcfi(/6/4)\",\"index\":0,\"fraction\":0.0}",
                 "progression":0.0,"children":[]}
              ]}]
        """.trimIndent()
        val entries = FoliateLocatorCodec.parseTocEntries(json)
        assertEquals(1, entries.size)
        assertNull(entries[0]["progression"])
        @Suppress("UNCHECKED_CAST")
        val children = entries[0]["children"] as List<Map<String, Any?>>
        assertEquals(1, children.size)
        assertEquals("第一章", children[0]["title"])
    }

    @Test
    fun `格式錯誤的 JSON 陣列字串回傳空清單，不拋出例外`() {
        assertTrue(FoliateLocatorCodec.parseTocEntries("not a json array").isEmpty())
    }

    @Test
    fun `空陣列回傳空清單`() {
        assertTrue(FoliateLocatorCodec.parseTocEntries("[]").isEmpty())
    }
}
