/// 格式無關的目錄項目抽象介面（epic-24-pdf-engine-rebuild Issue 5，
/// spec.md「目錄（TOC）」）：EPUB（[TocEntry]，`toc_entry.dart`）與 PDF
/// （`PdfTocItem`，`pdf_toc_item.dart`）的目錄項目皆實作本介面，
/// `TocBottomSheet` 只依賴這個介面渲染，不再直接依賴任一格式專屬的目錄
/// 項目型別。
///
/// 刻意只包含 [title]／[children]／[stableId] 三個成員：目錄項目的
/// 「定位點」（EPUB 的 CFI locator 字串、PDF 的 0-indexed 頁碼整數）與
/// 「目前章節高亮」演算法所需的排序鍵（EPUB 的 progression double、PDF
/// 的頁碼 int）在兩種格式之間型別完全不同，無法無損收斂進同一個抽象
/// 欄位，改由各自的 Navigator（`TocNavigator`／`PdfTocNavigator`）與
/// 呼叫端（`reader_screen.dart`）各自處理，不勉強塞進本介面。
abstract class BookTocItem {
  String get title;

  /// 供 Widget `Key` 使用的穩定識別字串，同一次目錄樹中須全域唯一（不只
  /// 是同層兄弟節點唯一）。EPUB 沿用既有的 [TocEntry.locatorJson]；PDF
  /// 由 `PdfTocItem` 在解析大綱時以遞增計數器產生，因為 PDF 大綱可能有
  /// 多個節點指向同一頁碼，無法用頁碼本身保證唯一。
  String get stableId;

  List<BookTocItem> get children;
}
