import 'book_group.dart';
import 'library_enums.dart';

/// 圖書庫中一本書籍的詮釋資料，對應 sqflite `books` 表的一列（見
/// docs/epics/epic-1-library/spec.md「資料模型」章節）。
class Book {
  final String id;
  final String title;
  final String? author;
  final BookFileFormat format;

  /// 檔案系統路徑或 `content://`/`file://` URI 字串（見
  /// docs/adr/0002-content-uri-reader-contract.md）。
  final String filePath;
  final BookSource source;

  /// 產生後封面圖檔的本機路徑（PNG）；`null` 表示尚未產生或產生失敗。
  final String? coverPath;

  /// 閱讀進度百分比（0.0-1.0），由 epic-5-toc-pagination Issue 2 起正式
  /// 活化——EPUB 用 Readium `Locator.locations.totalProgression`，PDF 用
  /// `(pdfPageIndex + 1) / 總頁數`，寫入時機見 [epubLocator]/[pdfPageIndex]。
  final double progress;

  /// EPUB 序列化後的 Readium `Locator`（`Locator.toJSON().toString()`），
  /// `null` 代表尚無記錄（例如書籍從未被開啟過，或本書為 PDF 格式）。與
  /// [pdfPageIndex] 互斥（一本書只會用到其中之一），但兩欄位皆可能同時
  /// 為 null（見 docs/epics/epic-5-toc-pagination/spec.md「本機閱讀位置
  /// 記憶」——位置資料是系統追蹤的狀態，故放在 Book 而非
  /// BookReaderPrefs）。
  final String? epubLocator;

  /// PDF 頁索引（0-indexed），`null` 代表尚無記錄。與 [epubLocator] 互斥。
  final int? pdfPageIndex;

  final String groupName;
  final DateTime createTime;
  final DateTime lastReadTime;

  const Book({
    required this.id,
    required this.title,
    this.author,
    required this.format,
    required this.filePath,
    required this.source,
    this.coverPath,
    this.progress = 0,
    this.epubLocator,
    this.pdfPageIndex,
    this.groupName = BookGroup.uncategorized,
    required this.createTime,
    required this.lastReadTime,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'format': format.name,
      'filePath': filePath,
      'source': source.name,
      'coverPath': coverPath,
      'progress': progress,
      'epubLocator': epubLocator,
      'pdfPageIndex': pdfPageIndex,
      'groupName': groupName,
      'createTime': createTime.millisecondsSinceEpoch,
      'lastReadTime': lastReadTime.millisecondsSinceEpoch,
    };
  }

  factory Book.fromMap(Map<String, Object?> map) {
    return Book(
      id: map['id'] as String,
      title: map['title'] as String,
      author: map['author'] as String?,
      format: BookFileFormat.values.byName(map['format'] as String),
      filePath: map['filePath'] as String,
      source: BookSource.values.byName(map['source'] as String),
      coverPath: map['coverPath'] as String?,
      progress: (map['progress'] as num).toDouble(),
      epubLocator: map['epubLocator'] as String?,
      pdfPageIndex: map['pdfPageIndex'] as int?,
      groupName: map['groupName'] as String,
      createTime: DateTime.fromMillisecondsSinceEpoch(map['createTime'] as int),
      lastReadTime:
          DateTime.fromMillisecondsSinceEpoch(map['lastReadTime'] as int),
    );
  }

  /// 回傳欄位值與自身相同的新物件，僅覆寫明確傳入的參數（目前只需要
  /// 覆寫 [groupName]——供 Issue 10 的批次分類異動使用）。
  Book copyWith({String? groupName}) {
    return Book(
      id: id,
      title: title,
      author: author,
      format: format,
      filePath: filePath,
      source: source,
      coverPath: coverPath,
      progress: progress,
      epubLocator: epubLocator,
      pdfPageIndex: pdfPageIndex,
      groupName: groupName ?? this.groupName,
      createTime: createTime,
      lastReadTime: lastReadTime,
    );
  }
}
