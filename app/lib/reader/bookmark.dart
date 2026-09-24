import '../l10n/app_localizations.dart';
import 'bookmark_position_context.dart';

/// 單一書籤（epic-6-annotations Issue 1，spec.md「書籤模組」）：標記書中
/// 「一個位置」的具名離散事件，定位精度同閱讀進度（EPUB／FXL：CFI＋進度
/// 比例；PDF：頁索引）。[epubLocatorJson]／[pdfPageIndex] 互斥，一筆書籤只會
/// 用到其中一組（依書籍格式而定，FXL 因副檔名是 .epub 而併入 EPUB 那一組，
/// 見審查修正 1.1），比照 ReadingPosition 既有的欄位語意。
class Bookmark {
  /// UUID primary key，新增前由呼叫端產生（例如 `reader_screen.dart`
  /// 直接呼叫 `const Uuid().v4()`）。
  final String id;
  final String bookId;
  final String name;
  final String? epubLocatorJson;
  final double? progression;
  final int? pdfPageIndex;

  const Bookmark({
    required this.id,
    required this.bookId,
    required this.name,
    this.epubLocatorJson,
    this.progression,
    this.pdfPageIndex,
  });

  /// 供 [BookmarksRepository.insert] 使用；刻意不含 `id`——新增一律交由
  /// SQLite `AUTOINCREMENT` 指派，重新命名等更新操作改用 Repository 的
  /// 目標欄位 `UPDATE`，不透過整列覆寫。
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'book_id': bookId,
      'name': name,
      'epub_locator_json': epubLocatorJson,
      'progression': progression,
      'pdf_page_index': pdfPageIndex,
    };
  }

  factory Bookmark.fromMap(Map<String, Object?> map) {
    return Bookmark(
      id: map['id'] as String,
      bookId: map['book_id'] as String,
      name: map['name'] as String,
      epubLocatorJson: map['epub_locator_json'] as String?,
      progression: (map['progression'] as num?)?.toDouble(),
      pdfPageIndex: map['pdf_page_index'] as int?,
    );
  }

  Bookmark copyWith({String? name}) {
    return Bookmark(
      id: id,
      bookId: bookId,
      name: name ?? this.name,
      epubLocatorJson: epubLocatorJson,
      progression: progression,
      pdfPageIndex: pdfPageIndex,
    );
  }

  /// EPUB 用「章節名稱＋全書進度百分比」（例如「第二章 (35%)」），PDF 用
  /// 「第 N 頁」（issues.md Issue 1 審查修正 1.3）。**FXL（固定版面漫畫）
  /// 因副檔名是 .epub、Dart 端無法在不解析 Locator JSON 內部結構的前提下
  /// 取得頁碼，加上固定版面永遠不預取目錄（_tocEntries 恆空），故實際只會
  /// 落在下方 progression 分支、顯示「百分比% 處」，不會是「第 N 頁」**
  /// （plan-issue-1.md 審查修正 1.1，見
  /// tmp/epic-6/reviews/plan_issue_1_review.md——這是本方法既有邏輯已經
  /// 正確處理的既存行為，本次修正的是文件描述本身的錯誤，不是程式邏輯）。
  /// 章節名稱／進度皆無法取得時（理論上只會發生在目錄與定位皆尚未就緒的
  /// 極短窗口）回退為通用的「書籤」字樣，不拋出例外。
  ///
  /// 文字依 [l10n]（介面語言）產生（epic-45-interface-i18n Issue 10，取代原
  /// spec.md §7 的排除）。**書籤名稱是建立當下的快照**：一旦寫入資料庫就是
  /// 使用者資料（可重新命名），不會隨之後切換介面語言而改變；切換語言前建立的
  /// 書籤維持原語言。章節名稱本身是書籍資料，不翻譯。
  static String defaultName(BookmarkPositionContext context, AppLocalizations l10n) {
    if (context.pdfPageIndex != null) {
      return l10n.bookmarkDefaultNamePdfPage(context.pdfPageIndex! + 1);
    }
    final chapterTitle = context.chapterTitle;
    final progression = context.progression;
    final percent = progression != null ? (progression * 100).round() : null;
    if (chapterTitle != null && percent != null) {
      return '$chapterTitle ($percent%)';
    }
    if (chapterTitle != null) {
      return chapterTitle;
    }
    if (percent != null) {
      return l10n.bookmarkDefaultNamePercent(percent);
    }
    return l10n.bookmarkDefaultNameFallback;
  }

  @override
  bool operator ==(Object other) =>
      other is Bookmark &&
      other.id == id &&
      other.bookId == bookId &&
      other.name == name &&
      other.epubLocatorJson == epubLocatorJson &&
      other.progression == progression &&
      other.pdfPageIndex == pdfPageIndex;

  @override
  int get hashCode => Object.hash(
        id,
        bookId,
        name,
        epubLocatorJson,
        progression,
        pdfPageIndex,
      );

  @override
  String toString() =>
      'Bookmark(id: $id, bookId: $bookId, name: $name, epubLocatorJson: $epubLocatorJson, progression: $progression, pdfPageIndex: $pdfPageIndex)';
}
