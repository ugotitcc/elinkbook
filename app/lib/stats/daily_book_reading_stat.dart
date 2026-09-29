// app/lib/stats/daily_book_reading_stat.dart

/// 某一天、某一本書的累計閱讀秒數（epic-9-stats，見 spec.md「核心介面」）。
///
/// [bookTitle] 是寫入當下的書名快照：書被刪除後這筆統計仍保留，詳情畫面
/// 直接顯示這個快照，不回頭查 `books` 表。
class DailyBookReadingStat {
  final String bookId;
  final String bookTitle;
  final int readingSeconds;

  const DailyBookReadingStat({
    required this.bookId,
    required this.bookTitle,
    required this.readingSeconds,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyBookReadingStat &&
          other.bookId == bookId &&
          other.bookTitle == bookTitle &&
          other.readingSeconds == readingSeconds;

  @override
  int get hashCode => Object.hash(bookId, bookTitle, readingSeconds);

  @override
  String toString() =>
      'DailyBookReadingStat($bookId, $bookTitle, $readingSeconds)';
}
