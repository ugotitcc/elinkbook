package cc.ugotit.elinkbook

import kotlin.math.floor

/**
 * 依點擊座標換算 3×3 導航熱區的格子索引（0-8，列優先，見
 * docs/epics/epic-7-interaction/spec.md「格子索引慣例」）。與 Dart 端
 * `hitTestZoneIndex()`（app/lib/reader/zone_hit_test.dart）平行實作相同演算法
 * ——供 EPUB 流式（`isFixedLayout == false`）路徑的原生 `InputListener.onTap()`
 * 使用；PDF／EPUB FXL 兩條 Flutter 端手勢路徑已各自在 Dart 端處理，不使用本
 * 物件。純 Kotlin、不依賴任何 Android 型別，可在 JVM 單元測試（app/src/test）
 * 直接驗證，比照 `EpubFxlScaler`／`PdfImageProcessor` 既有抽離慣例。
 */
object NavZoneHitTester {

    /**
     * [dx]/[dy] 為點擊座標（像素，相對容器左上角），[width]/[height] 為容器
     * 尺寸（像素）。回傳值以 `coerceIn` 保證落在 0-8，不因浮點誤差在邊界產生
     * 超界索引。[width]/[height] 為 0 或負數時直接回傳格子 4（正中央），比照
     * Dart 端 `hitTestZoneIndex()` 的邊界防護（避免除以 0 產生 `NaN`/
     * `Infinity`）。
     */
    fun cellIndex(dx: Float, dy: Float, width: Float, height: Float): Int {
        if (width <= 0f || height <= 0f) return 4
        val col = floor((dx / width) * 3).toInt().coerceIn(0, 2)
        val row = floor((dy / height) * 3).toInt().coerceIn(0, 2)
        return row * 3 + col
    }
}
