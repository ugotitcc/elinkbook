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

  /// 本 epic 固定為 `0`（真實閱讀進度回寫屬於 epic-8-sync，見 design.md）。
  final double progress;

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
      groupName: map['groupName'] as String,
      createTime: DateTime.fromMillisecondsSinceEpoch(map['createTime'] as int),
      lastReadTime:
          DateTime.fromMillisecondsSinceEpoch(map['lastReadTime'] as int),
    );
  }
}
