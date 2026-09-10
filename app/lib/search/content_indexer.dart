// app/lib/search/content_indexer.dart
import '../library/models/book.dart';

/// 單一格式的內容擷取器，把一本書轉換成一連串可索引的精確定位片段
/// （epic-10-search Issue 1，見 spec.md §3.1）。
///
/// [PdfContentIndexer]（純 Dart/FFI）與 [FoliateContentIndexer]（驅動
/// HeadlessInAppWebView）是目前僅有的兩個實作，由 `ContentIndexingScheduler`
/// 依 `book.format` 分派。
abstract class ContentIndexer {
  /// [resumeFromChapter] 非 null 時從該章節（含）開始擷取，用於背景排程
  /// 暫停後的續跑（見 `content_indexing_scheduler.dart`）。yield 順序即寫入
  /// 順序，呼叫端逐筆寫入 `book_content_index` 並可隨時中斷（例如排程被
  /// 要求暫停）——中斷後尚未被呼叫端消費的 segment 會隨 Stream 一併捨棄，
  /// 這是刻意的簡化設計（見 plan-issue-1.md Global Constraints「暫停粒度」）。
  Stream<IndexedSegment> indexBook(Book book, {int? resumeFromChapter});
}

/// 一個可索引、可精確跳轉的內容片段。
class IndexedSegment {
  /// Foliate：spine section index；PDF：頁碼（0-indexed）。
  final int chapterIndex;

  /// Foliate：CFI 字串；PDF：`jsonEncode({"page":int,"rect":{...}})`
  /// （`rect` 為 [PercentRect] 的欄位，見 `pdf_content_indexer.dart`）。
  final String locator;

  /// 原始文字（未經 `tokenizeForIndex()` 處理），供 UI 顯示片段用。
  final String rawText;

  const IndexedSegment({
    required this.chapterIndex,
    required this.locator,
    required this.rawText,
  });
}
