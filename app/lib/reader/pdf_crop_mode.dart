/// PDF 頁面裁切模式（FR-11），三選一互斥。[none] 不裁切；[autoDetect]
/// 智慧自動裁切（取樣偵測邊界後全書統一套用同一比例，不逐頁重算）；
/// [manual] 手動選區裁切（全書套用使用者框選的矩形）。見
/// docs/epics/epic-4-pdf-enhance/design.md 決策 #3／#4／#5。
enum PdfCropMode { none, autoDetect, manual }
