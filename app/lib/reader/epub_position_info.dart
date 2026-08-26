/// [EpubReaderView]／[FoliateEpubReaderView] 目前定位變動時（開書完成、
/// 翻頁、跳轉）一次性回報的位置資訊（epic-5-toc-pagination Issue 2）。
/// [locatorJson] 對 [EpubReaderView] 是原生端 `Locator.toJSON().toString()`
/// 的原樣字串；對 [FoliateEpubReaderView] 是 epic-17-epub-render-migration
/// Issue 6 新增的 CFI 格式 JSON 字串（`{"cfi":...,"index":...,"fraction":...}`，
/// 見 spec.md「資料模型」）——兩種格式完全不相容，但 Dart 端不解析其內部
/// 結構、只負責持久化與之後原樣傳回原生端還原，型別簽章不需要區分兩者。
/// [locatorJson] 會被持久化到書籤／劃線／備註／閱讀進度並跨裝置同步，
/// 內容必須與底下四個頁碼欄位（僅供即時 UI 顯示用途、不落地持久化）完全
/// 脫鉤（epic-26-architecture-hardening Issue 10 規劃階段查證）。
/// [progression] 是原生端額外拆出的全書進度比例平面數值，供 Dart 端直接
/// 用於 `Book.progress` 而不需要自行解析 [locatorJson] 的巢狀 JSON 結構。
///
/// [locationIndex]/[locationTotal] 與 [visualPageIndex]/[visualTotalPages]
/// （epic-26-architecture-hardening Issue 10，取代原本混用的 pageIndex/
/// totalPages）是兩組精度完全不同、互斥的頁碼欄位——同一本書恆有一組為
/// `null`，只有 [FoliateEpubReaderView] 會回報非 null 值，[EpubReaderView]
/// （Readium）兩組皆永遠為 `null`：
/// - [locationIndex]/[locationTotal]：流式格式（EPUB 流式／TXT／MD）專用，
///   foliate-js `SectionProgress.getProgress()` 的 `location.current`／
///   `location.total`——以 spine 檔案未壓縮位元組數除以固定常數 1500 算出的
///   近似刻度，與畫面實際渲染出來的視覺頁完全無關，僅供粗略進度顯示用途
///   （見 `CONTEXT.md`「Location 刻度」詞條）。FXL／CBZ 恆為 `null`。
/// - [visualPageIndex]/[visualTotalPages]：固定版面（FXL）／CBZ 專用，
///   foliate-js `FixedLayout`（`fixed-layout.js`）的 `page`/`pages`——全書
///   真實視覺頁數，精度等同實際渲染結果（見 `CONTEXT.md`「視覺頁碼」
///   詞條）。流式格式恆為 `null`（`docs/research/
///   architecture-review-flowable-pagination-precision.md` 候選 2 落地後
///   才會有值）。
/// [displayPageIndex]/[displayTotalPages] 是集中「挑值」邏輯的便利 getter，
/// `ReaderScreen` 建構頁尾一律用這兩個 getter，不直接依賴任何一組單獨欄位。
class EpubPositionInfo {
  final String locatorJson;
  final double? progression;
  final int? locationIndex;
  final int? locationTotal;
  final int? visualPageIndex;
  final int? visualTotalPages;

  const EpubPositionInfo({
    required this.locatorJson,
    this.progression,
    this.locationIndex,
    this.locationTotal,
    this.visualPageIndex,
    this.visualTotalPages,
  });

  /// 優先採用精確的視覺頁碼，只有在該格式沒有視覺頁碼資料時（目前是全部
  /// 流式格式）才退回估計刻度。
  int? get displayPageIndex => visualPageIndex ?? locationIndex;
  int? get displayTotalPages => visualTotalPages ?? locationTotal;

  @override
  bool operator ==(Object other) =>
      other is EpubPositionInfo &&
      other.locatorJson == locatorJson &&
      other.progression == progression &&
      other.locationIndex == locationIndex &&
      other.locationTotal == locationTotal &&
      other.visualPageIndex == visualPageIndex &&
      other.visualTotalPages == visualTotalPages;

  @override
  int get hashCode => Object.hash(locatorJson, progression, locationIndex,
      locationTotal, visualPageIndex, visualTotalPages);

  @override
  String toString() =>
      'EpubPositionInfo(locatorJson: $locatorJson, progression: $progression, '
      'locationIndex: $locationIndex, locationTotal: $locationTotal, '
      'visualPageIndex: $visualPageIndex, visualTotalPages: $visualTotalPages)';
}
