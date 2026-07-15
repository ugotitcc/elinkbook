/// 單一書籍的本機閱讀位置（epic-5-toc-pagination Issue 2），對應 `books`
/// 表的 `epubLocator`/`pdfPageIndex`/`progress` 3 個欄位。一本書只會用到
/// [epubLocatorJson] 或 [pdfPageIndex] 其中之一（依格式而定），兩者可能
/// 同時為 null（尚無記錄）。
class ReadingPosition {
  /// 序列化後的 Readium `Locator`（`Locator.toJSON().toString()`）。
  final String? epubLocatorJson;

  /// PDF 頁索引（0-indexed）。
  final int? pdfPageIndex;

  /// 閱讀進度百分比（0.0-1.0）。
  final double progress;

  const ReadingPosition({
    this.epubLocatorJson,
    this.pdfPageIndex,
    this.progress = 0,
  });

  @override
  bool operator ==(Object other) =>
      other is ReadingPosition &&
      other.epubLocatorJson == epubLocatorJson &&
      other.pdfPageIndex == pdfPageIndex &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(epubLocatorJson, pdfPageIndex, progress);

  @override
  String toString() =>
      'ReadingPosition(epubLocatorJson: $epubLocatorJson, pdfPageIndex: $pdfPageIndex, progress: $progress)';
}
