/// PDF 換頁動畫選項（epic-24-pdf-engine-rebuild Issue 11）。[slide]
/// 沿用 pdfrx 預設 200ms 滑動動畫（預設值，null 回退值）；[none] 瞬間跳頁
/// （`Duration.zero`），見 docs/epics/epic-24-pdf-engine-rebuild/issues.md
/// 「Issue 11」。
enum PdfPageTurnAnimation { slide, none }
