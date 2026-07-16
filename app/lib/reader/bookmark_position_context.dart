/// ReaderScreen 開啟 NotesBottomSheet 時傳入的目前位置上下文
/// （epic-6-annotations Issue 1 審查修正 1.2，見
/// tmp/epic-6/reviews/issues_review.md）：供書籤 toggle 按鈕判斷目前位置
/// 是否已有書籤、以及新增書籤時計算預設名稱。EPUB／PDF 兩組欄位互斥
/// （一本書只會用到其中一組，比照 ReadingPosition 既有的欄位語意）。
class BookmarkPositionContext {
  /// EPUB 目前定位（Locator JSON），EPUB 專屬。
  final String? epubLocatorJson;

  /// EPUB 全書閱讀進度比例（0.0-1.0），EPUB 專屬，供排序與預設命名使用。
  final double? progression;

  /// PDF 目前頁索引（0-indexed），PDF 專屬。FXL（固定版面漫畫）雖然也是
  /// 分頁式書籍，但副檔名是 .epub、Dart 端仍透過 EPUB 定位機制
  /// （[epubLocatorJson]／[progression]）追蹤位置，不使用這個欄位
  /// （審查修正，見 Global Constraints「書籤 toggle 的相等性判斷」）。
  final int? pdfPageIndex;

  /// EPUB 目前章節名稱，無法判斷時為 null（例如目錄尚未載入完成，或本書
  /// 沒有目錄）。
  final String? chapterTitle;

  const BookmarkPositionContext({
    this.epubLocatorJson,
    this.progression,
    this.pdfPageIndex,
    this.chapterTitle,
  });
}
