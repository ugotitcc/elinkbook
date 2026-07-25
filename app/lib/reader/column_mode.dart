/// 流式 EPUB 專屬的分欄模式偏好（epic-18 Issue 6）。
enum ColumnMode {
  /// 自動（由 foliate-js paginator.js 依 [columnSize] 欄位大小閾值自由決定欄數）。
  auto,

  /// 強制單欄（不論螢幕幾何或排版方向，強制單頁排版）。
  single,

  /// 硬限雙欄（最多 2 欄）。
  double,
}
