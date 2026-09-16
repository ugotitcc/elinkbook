// app/lib/search/search_repository.dart
import 'package:sqflite/sqflite.dart';

import '../library/models/book.dart';
import 'cjk_tokenizer.dart';
import 'search_query_variants.dart';

/// 全庫搜尋「內容匹配」單一可跳轉片段（epic-10-search Issue 4，見
/// spec.md §5）。[snippet] 為 `raw_text` 的顯示片段（可能截斷加省略號，
/// 不做關鍵字加粗以外的處理）；[locator] 原樣透傳
/// `book_content_index.locator`，開書跳轉用（本工單只保留欄位本身，真正
/// 用於精確定位是 Issue 5 的範圍）。
class ContentMatchSnippet {
  final String snippet;
  final String locator;
  final int? chapterIndex;

  const ContentMatchSnippet({
    required this.snippet,
    required this.locator,
    this.chapterIndex,
  });
}

/// 一本書底下的內容匹配結果（spec.md §5），[matches] 長度不超過查詢時傳入
/// 的 `perBookLimit`。不重複攜帶 [book] 多份。
class BookContentMatches {
  final Book book;
  final List<ContentMatchSnippet> matches;
  final int totalMatches;

  const BookContentMatches({
    required this.book,
    required this.matches,
    this.totalMatches = 0,
  });
}

/// 單書全文檢索結果（epic-10-search Issue 7，spec.md §9.1）。
class BookSearchDetailResult {
  final Book book;
  final List<ContentMatchSnippet> matches;
  final int totalMatches;

  /// 當 [totalMatches] > 查詢時傳入的 `limit` 時為 `true`，UI 據此顯示
  /// 「僅顯示前 N 筆」提示。
  final bool isTruncated;

  const BookSearchDetailResult({
    required this.book,
    required this.matches,
    required this.totalMatches,
    required this.isTruncated,
  });
}

/// 全庫搜尋的資料存取層（epic-10-search Issue 4，spec.md §5）：書名/作者
/// 匹配與書內內容匹配是兩條完全獨立的查詢路徑——前者永遠可用（不經
/// FTS5，不受「啟用全文檢索」開關影響），後者依賴 Issue 0/1 建立的
/// `book_content_index`/`book_content_fts` 索引資料是否存在。
abstract class SearchRepository {
  Future<List<Book>> searchTitleAuthor(String query);

  Future<List<BookContentMatches>> searchContent(
    String query, {
    int perBookLimit = 3,
  });

  /// 針對指定書籍查詢全文檢索命中片段（epic-10-search Issue 7，spec.md
  /// §9.1）。[bookId] 不存在或查詢為空時回傳 `null`。
  Future<BookSearchDetailResult?> searchContentInBook(
    String bookId,
    String query, {
    int limit = 200,
    bool sortByBookOrder = true,
  });
}

/// [SearchRepository] 正式實作：直接對 [Database] 下 SQL（比照
/// `SqliteFullTextSearchSettingsRepository` 既有慣例，不經
/// `LibraryRepository` 介面）。
class SqliteSearchRepository implements SearchRepository {
  const SqliteSearchRepository({required Database database})
      : _database = database;

  final Database _database;

  /// 顯示片段的最大字元數（依 rune 計算，CJK 安全），超過則截斷並加上刪
  /// 節號（spec.md §5：「可能截斷加省略號」，未指定確切長度，取一個能在
  /// 手機寬度下顯示約 2-3 行的實用值）。
  static const _maxSnippetRunes = 80;

  /// 【審查修正 I-4】片段視窗中，命中關鍵字前方保留的字元數——關鍵字
  /// 置中而非固定從頭截斷，避免關鍵字出現在句子後段時完全落在片段外。
  static const _snippetContextBeforeRunes = 20;

  @override
  Future<List<Book>> searchTitleAuthor(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    // 【審查修正 M-3】跳脫 LIKE 萬用字元 `%`／`_`（先跳脫反斜線本身，避免
    // 跳脫序列彼此汙染），否則使用者輸入的 `%` 會被當成萬用字元比對到
    // 全部書籍。
    // 【Issue 4：多變體查詢擴充】對 queryVariants() 產生的每個變體各自
    // 跳脫萬用字元，以 SQL OR 串接（例如 2 個變體時
    // `(title LIKE ? OR author LIKE ?) OR (title LIKE ? OR author LIKE ?)`），
    // variants 只有 1 項時等同既有行為不變。
    final variants = queryVariants(trimmed);
    final whereClauses = <String>[];
    final whereArgs = <Object?>[];
    for (final variant in variants) {
      final escaped = variant
          .replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_');
      whereClauses
          .add("(title LIKE ? ESCAPE '\\' OR author LIKE ? ESCAPE '\\')");
      whereArgs.add('%$escaped%');
      whereArgs.add('%$escaped%');
    }
    final rows = await _database.query(
      'books',
      where: whereClauses.join(' OR '),
      whereArgs: whereArgs,
      orderBy: 'lastReadTime DESC',
    );
    return rows.map(Book.fromMap).toList();
  }

  @override
  Future<List<BookContentMatches>> searchContent(
    String query, {
    int perBookLimit = 3,
  }) async {
    final trimmedQuery = query.trim();
    // 【Issue 4：多變體查詢擴充，spec.md「全文檢索整合」】不假設任何
    // 反向關係，一律正向查原文/繁體/簡體三種可能字形（見本檔案
    // search_query_variants.dart 文件註解）。
    final variants = queryVariants(trimmedQuery);
    // 審查修正 M-3：改用 toSet() 去重——variants 本身雖已去重，但極端輸入
    // 下（例如經 tokenizeForQuery() 的空白正規化）仍可能有兩個不同變體
    // 產生完全相同的 tokenized 字串，避免組出 `"A" OR "A"` 冗餘子句。
    final tokenizedVariants =
        variants.map(tokenizeForQuery).where((t) => t.isNotEmpty).toSet();
    if (tokenizedVariants.isEmpty) return const [];
    final matchQuery = tokenizedVariants.join(' OR ');

    // 【審查修正 I-2，推翻原計畫第一版「分兩次查詢」設計】單一查詢直接
    // JOIN books 表帶出完整欄位，不再另外對 `books WHERE id IN (?, ?, ...)`
    // 下第二次查詢——Android 11 系統 SQLite 3.28.0 的
    // SQLITE_MAX_VARIABLE_NUMBER 上限是 999，千本書規模下一個高頻詞可能
    // 命中超過 999 個相異 book_id，分兩次查詢會在第二次查詢直接拋出
    // 「too many SQL variables」例外；單一查詢從根本上消除這個上限風險，
    // 也不再需要處理「兩次查詢之間書籍被刪除」的競態。外層額外加
    // `ORDER BY sub.rn, sub.score`（spec.md §5 原文範例沒有這行）——rn=1
    // 的列（每本書最佳匹配）依 bm25 分數排序，讓「第一次出現的 book_id
    // 順序」直接反映跨書相關性排序，分組本身在下方 Dart 端用一般 Map
    // 手動完成（不引入 package:collection，見本計畫 Global Constraints）。
    List<Map<String, Object?>> rows;
    try {
      // SQLite 不允許在 ROW_NUMBER() 的 ORDER BY 子句中直接呼叫 bm25()
      // （"unable to use function bm25 in the requested context"），因此
      // 改為兩層巢狀：內層先算出 bm25(book_content_fts) AS score，外層
      // 再以預先算好的 score 排序做 ROW_NUMBER 分組，效果與單層寫法等價
      // 但可正確執行（見 Task 1 實作階段除錯）。
      rows = await _database.rawQuery('''
        SELECT b.*, sub.locator, sub.raw_text, sub.chapter_index,
               sub.rn, sub.score, sub.total_count
        FROM (
          SELECT book_id, locator, raw_text, chapter_index, score,
                 COUNT(*) OVER (PARTITION BY book_id) AS total_count,
                 ROW_NUMBER() OVER (
                   PARTITION BY book_id
                   ORDER BY score
                 ) AS rn
          FROM (
            SELECT bci.book_id, bci.locator, bci.raw_text,
                   bci.chapter_index,
                   bm25(book_content_fts) AS score
            FROM book_content_fts
            JOIN book_content_index bci ON bci.rowid = book_content_fts.rowid
            WHERE book_content_fts MATCH ?
          )
        ) sub
        JOIN books b ON b.id = sub.book_id
        WHERE sub.rn <= ?
        ORDER BY sub.rn, sub.score
      ''', [matchQuery, perBookLimit]);
    } on DatabaseException {
      // 【審查修正 M-4】tokenizeForQuery() 保證輸出恆為合法的 FTS5 phrase
      // 語法，正常情況下不會走到這裡；無法窮舉所有邊界輸入，保留這層
      // 防禦讓極端情況下安全退回空結果，而非讓整個搜尋畫面閃退。
      return const [];
    }

    if (rows.isEmpty) return const [];

    // `b.*` 帶出 books 表全部欄位（含 `id`），`Book.fromMap()` 只讀取它
    // 需要的欄位名稱，多出的 `locator`/`raw_text`/`rn`/`score` 欄位會被
    // 忽略，不影響解析。
    final snippetsByBookId = <String, List<ContentMatchSnippet>>{};
    final booksById = <String, Book>{};
    final totalMatchesByBookId = <String, int>{};
    for (final row in rows) {
      final bookId = row['id'] as String;
      booksById.putIfAbsent(bookId, () => Book.fromMap(row));
      totalMatchesByBookId.putIfAbsent(
        bookId,
        () => row['total_count'] as int,
      );
      snippetsByBookId.putIfAbsent(bookId, () => []).add(
            ContentMatchSnippet(
              snippet: _truncate(row['raw_text'] as String, variants),
              locator: row['locator'] as String,
              chapterIndex: row['chapter_index'] as int?,
            ),
          );
    }

    return [
      for (final entry in snippetsByBookId.entries)
        BookContentMatches(
          book: booksById[entry.key]!,
          matches: entry.value,
          totalMatches: totalMatchesByBookId[entry.key] ?? 0,
        ),
    ];
  }

  @override
  Future<BookSearchDetailResult?> searchContentInBook(
    String bookId,
    String query, {
    int limit = 200,
    bool sortByBookOrder = true,
  }) async {
    final trimmedQuery = query.trim();
    final variants = queryVariants(trimmedQuery);
    // 審查修正 M-3：見 searchContent() 同一處註解說明。
    final tokenizedVariants =
        variants.map(tokenizeForQuery).where((t) => t.isNotEmpty).toSet();
    if (tokenizedVariants.isEmpty) return null;
    final matchQuery = tokenizedVariants.join(' OR ');

    // 先查詢該書是否存在，帶出 Book 物件（books 表與 book_content_fts
    // 沒有共通鍵可一次 JOIN 帶出，維持獨立查詢）。
    final bookRows = await _database.query(
      'books',
      where: 'id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    if (bookRows.isEmpty) return null;
    final book = Book.fromMap(bookRows.first);

    // 【審查修正 review-issue-7.md Minor 1，推翻 review-plan-issue-7.md M-4
    // 「維持兩次查詢」的原始決定】改用 `COUNT(*) OVER ()`（無 PARTITION BY，
    // 單書查詢不需要分組）在同一個 SQL 內與命中片段一併取得總筆數：
    // 窗函數在 WHERE 過濾之後、LIMIT 截斷之前計算，因此 total_count 仍反映
    // 全部命中筆數，不受 LIMIT 影響（與 searchContent() 的
    // `COUNT(*) OVER (PARTITION BY book_id)` 同一原理）。原本「先 COUNT
    // 再查片段」共兩次 FTS 查詢＋一次書籍存在性查詢，合併後降為一次。
    // `bm25()` 必須先在內層子查詢算出 `score` 欄位，外層才能對它排序——
    // 直接在外層 ORDER BY 呼叫 `bm25(book_content_fts)`、同時外層又有
    // `COUNT(*) OVER ()` 窗函數時，SQLite 會拋出
    // 「unable to use function bm25 in the requested context」（與
    // searchContent() 內層先算 score、外層再用 ROW_NUMBER() 排序是同一個
    // 已知限制，見該方法註解）。
    final orderClause = sortByBookOrder
        ? 'ORDER BY sub.chapter_index ASC, sub.content_rowid ASC'
        : 'ORDER BY sub.score ASC';

    List<Map<String, Object?>> rows;
    try {
      rows = await _database.rawQuery('''
        SELECT sub.locator, sub.raw_text, sub.chapter_index,
               COUNT(*) OVER () AS total_count
        FROM (
          SELECT bci.locator, bci.raw_text, bci.chapter_index,
                 bci.rowid AS content_rowid,
                 bm25(book_content_fts) AS score
          FROM book_content_fts
          JOIN book_content_index bci ON bci.rowid = book_content_fts.rowid
          WHERE book_content_fts MATCH ?
            AND bci.book_id = ?
        ) sub
        $orderClause
        LIMIT ?
      ''', [matchQuery, bookId, limit]);
    } on DatabaseException {
      return null;
    }

    if (rows.isEmpty) {
      return BookSearchDetailResult(
        book: book,
        matches: const [],
        totalMatches: 0,
        isTruncated: false,
      );
    }

    final totalMatches = rows.first['total_count'] as int;
    final matches = rows
        .map((row) => ContentMatchSnippet(
              snippet: _truncate(row['raw_text'] as String, variants),
              locator: row['locator'] as String,
              chapterIndex: row['chapter_index'] as int?,
            ))
        .toList();

    return BookSearchDetailResult(
      book: book,
      matches: matches,
      totalMatches: totalMatches,
      isTruncated: totalMatches > limit,
    );
  }

  /// 【審查修正 I-4，推翻原計畫第一版「固定從頭截斷」設計；Issue 4 再次
  /// 修正為多變體版本】以 [variants]（`queryVariants()` 產生的原文/繁體/
  /// 簡體三個變體）中第一個能在 [text] 中找到的變體為中心截斷，而非固定
  /// 取前 [_maxSnippetRunes] 個字元，也不再只用單一原始查詢字串——命中
  /// 內容字形可能與使用者輸入字形不同（跨字形命中，審查修正 I-2），例如
  /// 原文「電腦」被簡體「电脑」命中時，比對基準必須是「電腦」而非
  /// 「电脑」才能定位到正確視窗。CJK 統一表意文字（U+4E00-U+9FFF）皆落在
  /// UTF-16 基本多文種平面（BMP）內，`String.indexOf()` 回傳的 UTF-16
  /// code unit 索引與 rune 索引一致，可直接當作 rune 索引使用；
  /// `token_text` 只用於索引比對，`raw_text` 保留原始未加空白的文字序列。
  static String _truncate(String text, List<String> variants) {
    final runes = text.runes.toList();
    if (runes.length <= _maxSnippetRunes) return text;

    final matchVariant = findMatchingVariant(text, variants);
    final matchIndex = matchVariant == null
        ? -1
        : text.toLowerCase().indexOf(matchVariant.toLowerCase());
    if (matchIndex < 0) {
      // 找不到任何變體（理論上不會發生，見上方說明，但輸入型態多樣不
      // 假設一定找得到）：退回從頭截斷的保底邏輯。
      return '${String.fromCharCodes(runes.take(_maxSnippetRunes))}…';
    }

    final windowStart =
        (matchIndex - _snippetContextBeforeRunes).clamp(0, runes.length);
    final windowEnd = (windowStart + _maxSnippetRunes).clamp(0, runes.length);
    final buffer = StringBuffer();
    if (windowStart > 0) buffer.write('…');
    buffer.write(String.fromCharCodes(runes.sublist(windowStart, windowEnd)));
    if (windowEnd < runes.length) buffer.write('…');
    return buffer.toString();
  }
}
