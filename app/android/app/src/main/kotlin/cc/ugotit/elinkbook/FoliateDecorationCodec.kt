package cc.ugotit.elinkbook

/**
 * 劃線/備註（epic-17-epub-render-migration Issue 8）從 Dart 端
 * EpubDecoration.toWire() 格式（{"id", "locatorJson", "tint", "isUnderline"}）
 * 轉換為 main.js window.setDecorations() 所需的 JS 端格式：cfi（供
 * view.addAnnotation({value: cfi}) 定位）＋color（CSS 顏色字串，供
 * Overlayer.highlight()/underline() 的 fill/stroke 屬性，不能是原始
 * 整數）。純函式，不觸碰 WebView，供 JVM 單元測試直接驗證。
 */
object FoliateDecorationCodec {
    /**
     * 把 Dart Color.toARGB32()／Android Color int 皆採用的 0xAARRGGBB
     * 版面轉換為 SVG fill/stroke 屬性可直接使用的 rgba() CSS 字串。
     */
    fun argbIntToCssColor(argb: Int): String {
        val a = (argb ushr 24) and 0xFF
        val r = (argb ushr 16) and 0xFF
        val g = (argb ushr 8) and 0xFF
        val b = argb and 0xFF
        return "rgba($r, $g, $b, ${a / 255.0})"
    }

    /**
     * 把 Dart 端送來的完整標記清單（見 EpubDecoration.toWire()）轉換為
     * main.js 端需要的 {"id", "cfi", "color", "isUnderline"} 清單。單筆
     * locatorJson 解析失敗（FoliateLocatorCodec.extractCfi() 回傳
     * null——缺席、格式錯誤、或既有流式書籍留下的舊格式 Readium Locator
     * JSON，ADR 0011「既有資料視為失效」）、或缺少 id／tint 欄位時該筆
     * 略過，不影響其餘標記，比照 EpubReaderView.kt
     * applyDecorationsFromWire() 既有的非致命錯誤略過原則。
     */
    fun buildDecorationEntries(list: List<Map<String, Any?>>): List<Map<String, Any?>> {
        return list.mapNotNull { entry ->
            val id = entry["id"] as? String ?: return@mapNotNull null
            val locatorJson = entry["locatorJson"] as? String
            val cfi = FoliateLocatorCodec.extractCfi(locatorJson) ?: return@mapNotNull null
            val tint = (entry["tint"] as? Number)?.toInt() ?: return@mapNotNull null
            val isUnderline = entry["isUnderline"] as? Boolean ?: false
            mapOf(
                "id" to id,
                "cfi" to cfi,
                "color" to argbIntToCssColor(tint),
                "isUnderline" to isUnderline,
            )
        }
    }
}
