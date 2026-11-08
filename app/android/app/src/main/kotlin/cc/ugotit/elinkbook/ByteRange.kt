package cc.ugotit.elinkbook

/**
 * 依 [length] 與 [maxBytes] 夾取位元組區段範圍（[start, end)）。
 *
 * 檢查順序與 Windows 端 `readFileRange` 保持一致：
 * 1. 先用呼叫端傳入的原始數值檢查：`start < 0`、`end <= start`、或 `end - start > maxBytes` 任一成立時回傳 null；
 * 2. 再用實際長度檢查：`start >= length` 回傳 null；
 * 3. 最後若 `end` 超過 `length`，夾回 `length`；
 * 4. 回傳 `start until clampedEnd`。
 */
fun clampByteRange(start: Long, end: Long, length: Long, maxBytes: Long): LongRange? {
    if (start < 0 || end <= start || end - start > maxBytes) {
        return null
    }
    if (start >= length) {
        return null
    }
    val clampedEnd = if (end > length) length else end
    return start until clampedEnd
}
