import 'dart:convert';

/// [FoliateReaderView] 目前定位變動時（開書完成、翻頁、跳轉）一次性回報
/// 的位置資訊（epic-5-toc-pagination Issue 2）。原生 Readium 路徑
/// `EpubReaderView` 已於 epic-18-reader-device-qa Issue 5 移除，本類別現在
/// 只有一個 producer——`app/lib/reader/foliate_bridge_codec.dart` 的
/// `parseLocatorChanged()`，解析 `main.js` `onLocatorChanged` handler 送出
/// 的 JS→Dart 橋接參數。
/// [locatorJson] 是 epic-17-epub-render-migration Issue 6 新增的 CFI 格式
/// JSON 字串（`{"cfi":...,"index":...,"fraction":...}`，見 spec.md「資料
/// 模型」），Dart 端不解析其內部結構，只負責持久化與之後原樣傳回 JS 端
/// 還原。[locatorJson] 會被持久化到書籤／劃線／備註／閱讀進度並跨裝置
/// 同步，內容必須與底下四個頁碼欄位（僅供即時 UI 顯示用途、不落地持久化）
/// 完全脫鉤（epic-26-architecture-hardening Issue 10 規劃階段查證）。
/// [progression] 是 `main.js` 額外拆出的全書進度比例平面數值，供 Dart 端
/// 直接用於 `Book.progress` 而不需要自行解析 [locatorJson] 的巢狀 JSON
/// 結構。
///
/// [locationIndex]/[locationTotal] 與 [visualPageIndex]/[visualTotalPages]
/// （epic-26-architecture-hardening Issue 10，取代原本混用的 pageIndex/
/// totalPages）是兩組精度完全不同、互斥的頁碼欄位——同一本書恆有一組為
/// `null`，由 `main.js` 依 `view.isFixedLayout` 分支組裝：
/// - [locationIndex]/[locationTotal]：流式格式（EPUB 流式／TXT／MD）專用，
///   foliate-js `SectionProgress.getProgress()` 的 `location.current`／
///   `location.total`——以 spine 檔案未壓縮位元組數除以固定常數 1500 算出
///   的近似刻度（epic-26 Issue 11／ADR 0024 起，已渲染過的 section 改用
///   實測視覺頁數密度校正），與畫面實際渲染出來的視覺頁仍有誤差，僅供
///   粗略進度顯示用途（見 `CONTEXT.md`「Location 刻度」詞條）。FXL／CBZ
///   恆為 `null`。
/// - [visualPageIndex]/[visualTotalPages]：固定版面（FXL）／CBZ 專用，
///   foliate-js `FixedLayout`（`fixed-layout.js`）的 `page`/`pages`——全書
///   真實視覺頁數，精度等同實際渲染結果（見 `CONTEXT.md`「視覺頁碼」
///   詞條）。流式格式恆為 `null`——刻意不追求讓流式格式也擁有真實視覺頁碼
///   （會需要強制渲染全書，見 `CONTEXT.md`「視覺頁碼」詞條、ADR 0024）。
///
/// 建構子以 debug-only assert 強制上述互斥不變式：兩組欄位不可同時非
/// `null`。這個保證目前只靠 `main.js` 的分支結構「碰巧」維持，Dart 端過去
/// 完全沒有防禦——違反時應在開發/測試階段直接拋出例外，不該讓 release
/// build 或 UI 層默默表現成難以定位的頁碼顯示異常。
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
  }) : assert(
          !((locationIndex != null || locationTotal != null) &&
              (visualPageIndex != null || visualTotalPages != null)),
          'locationIndex/locationTotal 與 visualPageIndex/visualTotalPages '
          '互斥，同一本書恆有一組為 null（見 CONTEXT.md「Location 刻度」／'
          '「視覺頁碼」詞條）',
        );

  /// 優先採用精確的視覺頁碼，只有在該格式沒有視覺頁碼資料時（目前是全部
  /// 流式格式）才退回估計刻度。
  int? get displayPageIndex => visualPageIndex ?? locationIndex;
  int? get displayTotalPages => visualTotalPages ?? locationTotal;

  /// 代表「位置」的比較鍵：取 [locatorJson] 中的 cfi 與 index，忽略會因重排而
  /// 來回微幅抖動的 fraction（真機日誌實證）。解析失敗或不是 JSON 物件時退回
  /// 整段字串。用來判斷兩次回報是不是「同一個位置的重複回報」。
  String get positionKey {
    try {
      final map = jsonDecode(locatorJson);
      if (map is Map) return '${map['cfi']}|${map['index']}';
    } catch (_) {}
    return locatorJson;
  }

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
