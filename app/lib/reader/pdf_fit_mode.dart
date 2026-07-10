/// PDF 頁面顯示縮放模式（FR-11）。[pageFit] 整頁完整顯示（預設）；
/// [fitWidth] 頁寬滿版、可視高度不足時可捲動；[actualSize] 真實比例
/// 1:1（1 PDF point = 1 Android 邏輯像素 dp，非物理像素，見
/// docs/epics/epic-4-pdf-enhance/design.md「已知風險」的 DPI 定義）。
enum PdfFitMode { pageFit, fitWidth, actualSize }
