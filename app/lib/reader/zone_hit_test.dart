/// 依點擊座標換算 3×3 導航熱區的格子索引（0-8，列優先，見 spec.md
/// 「格子索引慣例」）。PDF／EPUB FXL 兩條 Flutter 端手勢路徑共用同一份
/// 實作；EPUB 流式熱區由原生 Kotlin `NavZoneHitTester.cellIndex()`
/// （Issue 6）平行實作相同演算法，兩端需人工保持同步。
///
/// [dx]/[dy] 為點擊座標（像素，相對容器左上角），[width]/[height] 為容器
/// 尺寸（像素）。回傳值以 `.clamp()` 保證落在 0-8，不因浮點誤差在邊界
/// 產生超界索引。[width]/[height] 為 0 或負數（例如版面尚未完成排版）時
/// 直接回傳格子 4（正中央），避免除以 0 產生 `NaN`/`Infinity` 導致
/// `.floor()` 擲出 `UnsupportedError` 而讓 App 崩潰（審查修正）。
int hitTestZoneIndex({
  required double dx,
  required double dy,
  required double width,
  required double height,
}) {
  if (width <= 0 || height <= 0) return 4;
  final col = ((dx / width) * 3).floor().clamp(0, 2).toInt();
  final row = ((dy / height) * 3).floor().clamp(0, 2).toInt();
  return row * 3 + col;
}
