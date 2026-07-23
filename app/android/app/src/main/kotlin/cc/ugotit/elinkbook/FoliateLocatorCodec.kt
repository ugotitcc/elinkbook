package cc.ugotit.elinkbook

import org.json.JSONArray
import org.json.JSONObject

/**
 * 解析/序列化 epic-17-epub-render-migration Issue 6 新增的定位 JSON 格式
 * （{"cfi": "epubcfi(...)", "index": N, "fraction": F}，見 spec.md「資料
 * 模型」），與原生 foliate-js/CFI 格式互轉——與 Readium Locator.toJSON()
 * 完全不同、不相容（ADR 0011「既有流式書資料視為失效」）。純函式，不觸碰
 * WebView，供 JVM 單元測試直接驗證，供 FoliateEpubReaderView.kt 使用。
 */
object FoliateLocatorCodec {
    /**
     * 從定位 JSON 字串取出 cfi 欄位。[locatorJson] 為 null、JSON 格式錯誤、
     * 或是既有流式書籍留下的舊格式 Readium Locator JSON（完全不同的欄位
     * 結構，例如 {"href": "...", "locations": {...}, "type": "..."}，沒有
     * cfi 這個鍵）皆回傳 null，供呼叫端優雅退回（不拋例外、視為無記錄）。
     */
    fun extractCfi(locatorJson: String?): String? {
        if (locatorJson == null) return null
        return try {
            val obj = JSONObject(locatorJson)
            if (obj.has("cfi") && !obj.isNull("cfi")) obj.getString("cfi") else null
        } catch (e: Exception) {
            null
        }
    }

    /**
     * 把 main.js window.getTableOfContents() 回傳的 JSON 陣列字串解析為
     * Dart TocEntry.fromWire() 預期的巢狀 map 結構（title／locatorJson／
     * progression／children）。[tocJson] 格式錯誤時回傳空清單，不拋出例外
     * ——目錄讀取失敗不應該讓已成功開啟的書籍畫面顯示錯誤（比照
     * FoliateEpubReaderView.kt 既有對非致命錯誤的處理原則）。
     */
    fun parseTocEntries(tocJson: String): List<Map<String, Any?>> {
        return try {
            val array = JSONArray(tocJson)
            (0 until array.length()).map { tocEntryFromJsonObject(array.getJSONObject(it)) }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun tocEntryFromJsonObject(obj: JSONObject): Map<String, Any?> {
        val childrenArray = obj.optJSONArray("children") ?: JSONArray()
        val children = (0 until childrenArray.length())
            .map { tocEntryFromJsonObject(childrenArray.getJSONObject(it)) }
        return mapOf(
            "title" to obj.optString("title", ""),
            "locatorJson" to obj.optString("locatorJson", ""),
            "progression" to if (obj.isNull("progression")) null else obj.optDouble("progression"),
            "children" to children,
        )
    }
}
