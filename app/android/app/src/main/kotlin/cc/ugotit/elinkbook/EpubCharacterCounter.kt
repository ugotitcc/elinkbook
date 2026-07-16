package cc.ugotit.elinkbook

/**
 * EPUB 全書字元數估算（epic-5-toc-pagination Issue 3，spec.md「分頁估算
 * 模組」）用到的純文字字元計算邏輯：從單一 resource 的 HTML/XHTML 原始
 * 內容中去除標籤與多餘空白後計算純文字字元數。純 Kotlin、不依賴
 * Android／Readium 執行環境，可在 JVM 單元測試（app/src/test）直接以
 * 固定字串驗證，比照 EpubFxlScaler 的既有先例。真正走訪
 * `Publication.readingOrder` 取得每個 resource 內容的邏輯留在
 * EpubReaderView.kt（需要 Readium 的 suspend Resource API，無法脫離
 * 真機/模擬器環境以純 JUnit 驗證，見該檔案的說明）。
 */
object EpubCharacterCounter {

    /**
     * 去除所有 HTML/XHTML 標籤（含跨行的標籤）與 HTML entity（概略以單一
     * 空白取代，不需要精確解碼實際字元——此為粗略估算用途，非逐字精確
     * 渲染），再把連續空白（含換行）收斂為單一空白後計算字元數。
     */
    fun countCharacters(html: String): Int {
        val withoutTags = html.replace(Regex("<[^>]*>", RegexOption.DOT_MATCHES_ALL), " ")
        val withoutEntities = withoutTags.replace(Regex("&[a-zA-Z#0-9]+;"), " ")
        val collapsed = withoutEntities.replace(Regex("\\s+"), " ").trim()
        return collapsed.length
    }
}
