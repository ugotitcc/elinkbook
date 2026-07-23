/// [EpubReaderView]／[FoliateEpubReaderView] 目前定位變動時（開書完成、
/// 翻頁、跳轉）一次性回報的位置資訊（epic-5-toc-pagination Issue 2）。
/// [locatorJson] 對 [EpubReaderView] 是原生端 `Locator.toJSON().toString()`
/// 的原樣字串；對 [FoliateEpubReaderView] 是 epic-17-epub-render-migration
/// Issue 6 新增的 CFI 格式 JSON 字串（`{"cfi":...,"index":...,"fraction":...}`，
/// 見 spec.md「資料模型」）——兩種格式完全不相容，但 Dart 端不解析其內部
/// 結構、只負責持久化與之後原樣傳回原生端還原，型別簽章不需要區分兩者。
/// [progression] 是原生端額外拆出的全書進度比例平面數值，供 Dart 端直接
/// 用於 `Book.progress` 而不需要自行解析 [locatorJson] 的巢狀 JSON 結構。
///
/// [pageIndex]／[totalPages]（epic-17-epub-render-migration Issue 6，加法性
/// 擴充）僅 [FoliateEpubReaderView] 會回報非 null 值——`foliate-js`
/// `SectionProgress.getProgress()` 的 `location.current`／`location.total`
/// （近似頁碼概念，非精確渲染頁數，見 spec.md「頁碼估算」），供
/// `ReaderScreen` 建構頁尾時直接使用，不需要另外估算。[EpubReaderView]
/// （Readium）永遠不填這兩個欄位，維持既有行為不受影響。
class EpubPositionInfo {
  final String locatorJson;
  final double? progression;
  final int? pageIndex;
  final int? totalPages;

  const EpubPositionInfo({
    required this.locatorJson,
    this.progression,
    this.pageIndex,
    this.totalPages,
  });

  @override
  bool operator ==(Object other) =>
      other is EpubPositionInfo &&
      other.locatorJson == locatorJson &&
      other.progression == progression &&
      other.pageIndex == pageIndex &&
      other.totalPages == totalPages;

  @override
  int get hashCode =>
      Object.hash(locatorJson, progression, pageIndex, totalPages);

  @override
  String toString() =>
      'EpubPositionInfo(locatorJson: $locatorJson, progression: $progression, '
      'pageIndex: $pageIndex, totalPages: $totalPages)';
}
