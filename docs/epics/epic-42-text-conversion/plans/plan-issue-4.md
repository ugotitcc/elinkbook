# Epic 42 Issue 4 — 全文檢索多變體查詢擴充 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓全文檢索（書名/作者匹配、書內內容匹配）在簡繁轉換功能上線後仍能正確命中——查詢字串一律同時比對原文/繁體/簡體三種可能字形（Multi-variant Query Expansion），而非依目前顯示模式做「反向字典轉換」（該方案已被 spec.md 證明有漏檢風險，見下方 Global Constraints）；並讓搜尋結果的內容匹配摘要片段、書名/作者依「跨書情境」規則轉換後呈現，同時修正跨字形命中時的截斷定位與關鍵字高亮。

**Architecture:** 新增一個共用純函式模組 `search_query_variants.dart`（`queryVariants()` 產生三個變體、`findMatchingVariant()` 找出文字中實際命中的變體），供 `SqliteSearchRepository`（查詢端，組出 FTS5 `MATCH`／SQL `LIKE` 的 OR 組合）與 UI 層（`BookSearchScreen`／`LibrarySearchScreen`，高亮比對）共用同一份邏輯，避免兩處各自重新實作。索引寫入端（`book_content_fts`）完全不變、永遠索引原文；顯示層轉換（摘要片段、書名、作者）在 UI 層取得 `GlobalReaderPrefs.reading.textConversion` 後套用，資料存取層（`SqliteSearchRepository`）不依賴偏好設定。

**Tech Stack:** Flutter/Dart（`flutter_test`）、SQLite FTS5（`sqflite`）。本 Issue 純 Dart／SQLite 邏輯，不涉及 WebView／原生渲染，不需要 `app/integration_test/`。

**Spec:** `docs/epics/epic-42-text-conversion/issues.md` Issue 4（另見 `docs/epics/epic-42-text-conversion/spec.md`「全文檢索整合」，含推翻原「查詢端反向字典轉換」方案的完整理由）。

## Global Constraints

- `convertText(String input, TextConversionMode mode)`（`app/lib/reader/text_conversion.dart`，Issue 0）簽章不得更動。
- **不做反向字典轉換**：查詢字串一律正向產生三個變體（原文、`toTraditional`、`toSimplified`）分別送查，**絕不**依「目前顯示模式」反推回原文再查詢——簡化字存在多對一併字（「後」「后」皆簡化為「后」；「幹」「乾」「干」皆簡化為「干」），沒有無損的反向字典，反向轉換會讓繁體原文書在「轉換為簡體」模式下用簡體字搜尋卻 0 筆命中（spec.md 已詳述此錯誤根源，見「全文檢索整合」段落開頭）。
- **索引寫入端不變**：`book_content_fts`／`book_content_index`（`foliate_content_indexer.dart` 等既有索引建置路徑）永遠索引原文，本計畫完全不觸碰寫入路徑。
- **顯示層轉換一律採「跨書情境」全域預設值**（`GlobalReaderPrefs.reading.textConversion`），**不做任何單書覆寫**——這適用於書名/作者匹配區、內容匹配摘要片段，即使在 `BookSearchScreen`（單書搜尋畫面）內也一樣：該畫面 AppBar 的書名/作者採單書情境（`resolveTextConversion()`），但畫面內容匹配摘要片段本身採全域跨書情境——兩者刻意不同層級，這是 spec.md 明文的呼叫點分流規則，不是不一致的 bug，實作時不要「順手」把摘要片段也改成單書覆寫。**審查修正 review-plan-issue-4.md I-2**：`BookSearchScreen` AppBar 的單書情境轉換截至 Issue 3 合併時**只在 `ReaderScreen._buildSearchableBook()` 這一個入口正確**（該入口會先用自己已解析的單書生效值轉換過書名/作者才建構傳入的 `Book`）；`LibrarySearchScreen._openBookSearch()` 下鑽入口傳入的是未轉換的原始 `Book`，AppBar 會顯示原文——這是 Issue 3 當時明文記錄、留給本 Issue 處理的落差。本計畫 Task 3 透過讓 `BookSearchScreen` **自行**解析單書情境生效值（而非依賴呼叫端是否已預先轉換）修補這個落差，使其對任何入口皆正確，`LibrarySearchScreen._openBookSearch()` 因此不需要修改。
- `queryVariants(String q0)` 回傳型別固定為 `List<String>`，`q0` 恆為第一個元素，重複值自動去除（例如英數字查詢時三個變體相同，回傳長度為 1 的清單，等同既有行為不變）。
- `findMatchingVariant(String text, List<String> variants)` 回傳 `String?`：找不到任何變體時回傳 `null`，呼叫端各自決定保底邏輯（截斷視窗退回從頭截斷；高亮退回不比對到任何內容、不顯示任何高亮片段——兩者皆是既有的既定保底行為，不需要新增例外處理）。
- 本計畫涉及的檔案（`search_query_variants.dart`／`search_repository.dart`／`book_search_screen.dart`／`library_search_screen.dart`／`highlight_segments.dart`）皆已有既有測試檔可供沿用既有 fixture／測試手法，不新增測試基礎設施。
- 所有新增測試一律使用既有 `convertText()` 測試已驗證過的字元對（「国电脑」↔「國電腦」、「电脑」↔「電腦」，`test/reader/text_conversion_test.dart` 既有測試向量），不自行發明未經驗證的字元映射。

---

## File Structure

- Create: `app/lib/search/search_query_variants.dart` — `queryVariants()`／`findMatchingVariant()` 共用純函式。
- Create: `app/test/search/search_query_variants_test.dart` — 對應單元測試。
- Modify: `app/test/search/highlight_segments_test.dart` — 新增 `splitHighlightSegments` 跨字形命中整合測試（審查修正 I-3）。
- Modify: `app/lib/search/search_repository.dart` — `searchTitleAuthor()`／`searchContent()`／`searchContentInBook()`／`_truncate()` 改用多變體查詢。
- Modify: `app/test/search/search_repository_test.dart` — 新增跨字形命中／截斷定位測試。
- Modify: `app/lib/screens/book_search_screen.dart` — 內容匹配摘要片段套用全域顯示轉換、關鍵字高亮改用跨字形變體比對；AppBar 標題／工具列作者改為畫面自行解析單書情境轉換模式（審查修正 I-2），不再假設呼叫端已預先轉換。
- Modify: `app/test/screens/book_search_screen_test.dart` — 新增對應測試。
- Modify: `app/lib/screens/library_search_screen.dart` — 書名/作者匹配區、內容匹配區書籍標頭與摘要片段套用全域顯示轉換，含 `BookCover.textConversion`（審查修正 C-1）。
- Modify: `app/test/screens/library_search_screen_test.dart` — 新增對應測試。

---

### Task 1: `queryVariants()`／`findMatchingVariant()` 共用工具函式

**Files:**
- Create: `app/lib/search/search_query_variants.dart`
- Test: `app/test/search/search_query_variants_test.dart`
- Test: `app/test/search/highlight_segments_test.dart`（審查修正 I-3：補上 `splitHighlightSegments` 跨字形命中整合測試，issues.md Issue 4 單元測試要求第 6 項明文要求）

**Interfaces:**
- Consumes: `convertText(String, TextConversionMode)`（Issue 0，`app/lib/reader/text_conversion.dart`）。
- Produces: `List<String> queryVariants(String q0)`、`String? findMatchingVariant(String text, List<String> variants)`，供 Task 2（`SqliteSearchRepository`）與 Task 3（`BookSearchScreen`）消費。

- [ ] **Step 1: 新增失敗測試**

建立 `app/test/search/search_query_variants_test.dart`：

```dart
// app/test/search/search_query_variants_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/search/search_query_variants.dart';

void main() {
  group('queryVariants', () {
    test('回傳原文／簡轉繁／繁轉簡三個變體，原文恆為第一個元素', () {
      final variants = queryVariants('国电脑');
      expect(variants.first, '国电脑');
      expect(variants, containsAll(['国电脑', '國電腦']));
    });

    test('轉換後與原文相同時自動去重（例如英數字查詢不受簡繁轉換影響）', () {
      expect(queryVariants('Dune'), ['Dune']);
    });

    test('空字串輸入回傳單一空字串變體，不拋出例外', () {
      expect(queryVariants(''), ['']);
    });
  });

  group('findMatchingVariant', () {
    test('回傳第一個能在文字中以 indexOf 找到的變體', () {
      final result = findMatchingVariant('電腦維修站', ['电脑', '電腦']);
      expect(result, '電腦');
    });

    test('依 variants 清單順序找，第一個找到的優先，不繼續嘗試後面的', () {
      final result = findMatchingVariant('电脑電腦都有', ['电脑', '電腦']);
      expect(result, '电脑');
    });

    test('不分大小寫比對（英數字查詢情境）', () {
      final result = findMatchingVariant('Dune Messiah', ['dune']);
      expect(result, 'dune');
    });

    test('全部變體皆找不到時回傳 null', () {
      final result = findMatchingVariant('完全不相關的內容', ['电脑', '電腦']);
      expect(result, isNull);
    });
  });
}
```

**審查修正 I-3**：`issues.md` Issue 4 單元測試要求第 6 項明文要求「驗證 `splitHighlightSegments` 在原文字形與查詢詞字形不同時，改用能匹配上的變體後可正確產出 `isMatch: true` 的高亮片段」——這是 `splitHighlightSegments`（純函式，`app/lib/search/highlight_segments.dart`）本身搭配 `findMatchingVariant`／`queryVariants` 的純單元測試，與 Task 3 的 Widget Test（驗證 `BookSearchScreen` 實際渲染結果）是兩個不同層級的驗證，缺一不可。

在 `app/test/search/highlight_segments_test.dart` 第 3 行（`import 'package:elinkbook/search/highlight_segments.dart';`）之後新增：

```dart
import 'package:elinkbook/search/search_query_variants.dart';
```

找到 `group('splitHighlightSegments', ...)` 結尾的 `});`（緊接在「大小寫混合比對」測試之後）與 `group('HighlightSegment', ...)` 開始之間，新增一個新的 group：

```dart

  group('跨字形高亮整合（epic-42-text-conversion Issue 4 審查修正 I-3）', () {
    test('查詢詞字形與內文字形不同時，改用 findMatchingVariant 取得之變體切分，正確產出 isMatch: true 的高亮片段', () {
      const text = '這裡是電腦維修中心';
      const query = '电脑维修'; // 簡體查詢，繁體內文
      final matchVariant = findMatchingVariant(text, queryVariants(query));
      expect(matchVariant, '電腦維修');

      final segments = splitHighlightSegments(text, matchVariant!);
      expect(segments, [
        const HighlightSegment('這裡是', false),
        const HighlightSegment('電腦維修', true),
        const HighlightSegment('中心', false),
      ]);
    });

    test('三個變體皆找不到時，findMatchingVariant 回傳 null，呼叫端保底退回原始查詢字串仍安全（不拋例外、無高亮片段）', () {
      const text = '完全不相關的內容';
      const query = '电脑';
      final matchVariant = findMatchingVariant(text, queryVariants(query));
      expect(matchVariant, isNull);

      final segments = splitHighlightSegments(text, matchVariant ?? query);
      expect(segments, [const HighlightSegment('完全不相關的內容', false)]);
    });
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/search/search_query_variants_test.dart test/search/highlight_segments_test.dart`
Expected: FAIL（`package:elinkbook/search/search_query_variants.dart` 找不到，兩個測試檔皆編譯錯誤）。

- [ ] **Step 3: 實作 `queryVariants()`／`findMatchingVariant()`**

建立 `app/lib/search/search_query_variants.dart`：

```dart
// app/lib/search/search_query_variants.dart
import '../reader/text_conversion.dart';
import '../reader/text_conversion_mode.dart';

/// 依原始查詢字串 [q0] 產生簡繁三個變體（spec.md「全文檢索整合」
/// Multi-variant Query Expansion）：原文、轉換為繁體、轉換為簡體，去重後
/// 依序回傳（[q0] 恆為第一個元素）。**不假設任何反向關係**——簡化字存在
/// 多對一併字（「後」「后」皆簡化為「后」），沒有無損的反向字典，因此
/// 一律正向查三種可能字形，而非嘗試依目前顯示模式反推回原文（見
/// spec.md 對推翻原「查詢端反向字典轉換」方案的完整說明）。
List<String> queryVariants(String q0) {
  return <String>{
    q0,
    convertText(q0, TextConversionMode.toTraditional),
    convertText(q0, TextConversionMode.toSimplified),
  }.toList(growable: false);
}

/// 在 [variants] 中依序找出第一個能在 [text] 中以 [String.indexOf]（不分
/// 大小寫）找到的變體；全部找不到時回傳 `null`。供截斷視窗定位
/// （`SqliteSearchRepository._truncate()`）與關鍵字高亮
/// （`BookSearchScreen._buildHighlightedText()`）共用，讓「命中內容字形與
/// 使用者輸入字形不同」（跨字形命中）時仍能正確定位／高亮（spec.md 審查
/// 修正 I-2）。
String? findMatchingVariant(String text, List<String> variants) {
  final lowerText = text.toLowerCase();
  for (final variant in variants) {
    if (variant.isNotEmpty && lowerText.contains(variant.toLowerCase())) {
      return variant;
    }
  }
  return null;
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/search/search_query_variants_test.dart test/search/highlight_segments_test.dart`
Expected: 全數 PASS（`search_query_variants_test.dart` 7 個測試＋`highlight_segments_test.dart` 既有測試零回歸＋新增 2 個測試）。

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/search/search_query_variants.dart app/test/search/search_query_variants_test.dart app/test/search/highlight_segments_test.dart
git commit -m "feat(search): 新增 queryVariants/findMatchingVariant 多變體查詢共用工具"
```

---

### Task 2: `SqliteSearchRepository` 三個查詢方法改用多變體查詢

**Files:**
- Modify: `app/lib/search/search_repository.dart`
- Test: `app/test/search/search_repository_test.dart`

**Interfaces:**
- Consumes: `queryVariants(String)`／`findMatchingVariant(String, List<String>)`（Task 1）。
- Produces: 無新增公開介面——`SearchRepository` 抽象介面（`searchTitleAuthor`／`searchContent`／`searchContentInBook`）簽章完全不變，本 Task 只改內部實作，`FakeSearchRepository`（`test/support/fake_search_repository.dart`）與所有既有呼叫端（`BookSearchScreen`／`LibrarySearchScreen`）零回歸、不需修改。

- [ ] **Step 1: 新增失敗測試**

在 `app/test/search/search_repository_test.dart` 找到第 95-104 行「查詢字串含 % 或 _ 時視為一般字元比對」測試結尾的 `});`（第 103 行）與 `group('searchTitleAuthor', ...)` 結尾的 `});`（第 104 行）之間，新增：

```dart

    test('跨字形命中：簡體查詢可命中繁體書名，繁體查詢也可命中繁體書名（epic-42-text-conversion Issue 4）',
        () async {
      await repository.insertBook(_book('b1', title: '電腦維修入門'));
      await repository.insertBook(_book('b2', title: '完全不相關的書名'));

      final bySimplified = await searchRepository.searchTitleAuthor('电脑');
      expect(bySimplified.map((b) => b.id).toList(), ['b1']);

      final byTraditional = await searchRepository.searchTitleAuthor('電腦');
      expect(byTraditional.map((b) => b.id).toList(), ['b1']);
    });
```

找到第 201-208 行「searchContent 回傳的 ContentMatchSnippet 包含 chapterIndex」測試結尾的 `});` 與 `group('searchContent', ...)` 結尾的 `});`（第 209 行）之間，新增：

```dart

    test(
        '跨字形命中：內容為繁體時可用簡體查詢命中，內容為簡體時可用繁體查詢命中'
        '（spec.md 審查修正 C-1 核心回歸案例：不因目前顯示模式而漏檢）', () async {
      await repository.insertBook(_book('b1', title: '繁體書'));
      await insertContentRow('b1', '這一段含有電腦維修的內容');
      await repository.insertBook(_book('b2', title: '簡體書'));
      await insertContentRow('b2', '这一段含有电脑维修的内容');

      final bySimplified = await searchRepository.searchContent('电脑');
      expect(bySimplified.map((m) => m.book.id).toSet(), {'b1', 'b2'});

      final byTraditional = await searchRepository.searchContent('電腦');
      expect(byTraditional.map((m) => m.book.id).toSet(), {'b1', 'b2'});
    });

    test('跨字形截斷定位：命中內容字形與查詢字形不同時，截斷視窗仍以實際命中的變體為中心（審查修正 I-2）',
        () async {
      await repository.insertBook(_book('b1'));
      const keyword = '電腦維修';
      final prefix = List.filled(40, '填').join();
      final suffix = List.filled(66, '填').join();
      final rawText = '$prefix$keyword$suffix';
      await insertContentRow('b1', rawText);

      // 使用者輸入簡體「电脑维修」，命中的原文卻是繁體「電腦維修」。
      final results = await searchRepository.searchContent('电脑维修');

      final snippet = results.single.matches.single.snippet;
      expect(
        snippet,
        contains(keyword),
        reason: '截斷視窗必須以實際命中的繁體變體為中心，而非誤判為找不到後退回從頭截斷',
      );
      expect(snippet, startsWith('…'));
      expect(snippet, endsWith('…'));
    });
```

找到第 304-310 行「空查詢或 tokenizeForQuery 為空時回傳 null」測試與第 312-318 行「指定 bookId 不存在時回傳 null」測試之間（第 311 行空行後），新增：

```dart
    test('跨字形命中：單書搜尋時簡體查詢可命中繁體內容，繁體查詢也可命中（epic-42-text-conversion Issue 4）',
        () async {
      await repository.insertBook(_book('b1', title: '書一'));
      await insertContentRow('b1', '這裡有電腦維修的說明');

      final bySimplified =
          await searchRepository.searchContentInBook('b1', '电脑维修');
      expect(bySimplified, isNotNull);
      expect(bySimplified!.matches, hasLength(1));

      final byTraditional =
          await searchRepository.searchContentInBook('b1', '電腦維修');
      expect(byTraditional, isNotNull);
      expect(byTraditional!.matches, hasLength(1));
    });

```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/search/search_repository_test.dart`
Expected: 新增的 4 個測試皆 FAIL（目前查詢只比對單一原始查詢字串，簡體查詢命中不到繁體內容，反之亦然）。

- [ ] **Step 3: 實作多變體查詢**

在 `app/lib/search/search_repository.dart` 第 5 行（`import 'cjk_tokenizer.dart';`）之後新增：

```dart
import 'search_query_variants.dart';
```

修改 `searchTitleAuthor()`（第 96-114 行），把：

```dart
  @override
  Future<List<Book>> searchTitleAuthor(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    // 【審查修正 M-3】跳脫 LIKE 萬用字元 `%`／`_`（先跳脫反斜線本身，避免
    // 跳脫序列彼此汙染），否則使用者輸入的 `%` 會被當成萬用字元比對到
    // 全部書籍。
    final escaped = trimmed
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final rows = await _database.query(
      'books',
      where: "title LIKE ? ESCAPE '\\' OR author LIKE ? ESCAPE '\\'",
      whereArgs: ['%$escaped%', '%$escaped%'],
      orderBy: 'lastReadTime DESC',
    );
    return rows.map(Book.fromMap).toList();
  }
```

改為：

```dart
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
```

修改 `searchContent()`（第 117-124 行開頭部分），把：

```dart
  Future<List<BookContentMatches>> searchContent(
    String query, {
    int perBookLimit = 3,
  }) async {
    final trimmedQuery = query.trim();
    final tokenized = tokenizeForQuery(trimmedQuery);
    if (tokenized.isEmpty) return const [];
```

改為：

```dart
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
```

修改同一方法內 `rawQuery` 的參數列（第 143-165 行區塊結尾），把：

```dart
        JOIN books b ON b.id = sub.book_id
        WHERE sub.rn <= ?
        ORDER BY sub.rn, sub.score
      ''', [tokenized, perBookLimit]);
```

改為：

```dart
        JOIN books b ON b.id = sub.book_id
        WHERE sub.rn <= ?
        ORDER BY sub.rn, sub.score
      ''', [matchQuery, perBookLimit]);
```

修改同一方法內組裝 `ContentMatchSnippet` 的 `_truncate()` 呼叫（第 188-194 行），把：

```dart
      snippetsByBookId.putIfAbsent(bookId, () => []).add(
            ContentMatchSnippet(
              snippet: _truncate(row['raw_text'] as String, trimmedQuery),
              locator: row['locator'] as String,
              chapterIndex: row['chapter_index'] as int?,
            ),
          );
```

改為：

```dart
      snippetsByBookId.putIfAbsent(bookId, () => []).add(
            ContentMatchSnippet(
              snippet: _truncate(row['raw_text'] as String, variants),
              locator: row['locator'] as String,
              chapterIndex: row['chapter_index'] as int?,
            ),
          );
```

修改 `searchContentInBook()`（第 213-216 行），把：

```dart
    final trimmedQuery = query.trim();
    final tokenized = tokenizeForQuery(trimmedQuery);
    if (tokenized.isEmpty) return null;
```

改為：

```dart
    final trimmedQuery = query.trim();
    final variants = queryVariants(trimmedQuery);
    // 審查修正 M-3：見 searchContent() 同一處註解說明。
    final tokenizedVariants =
        variants.map(tokenizeForQuery).where((t) => t.isNotEmpty).toSet();
    if (tokenizedVariants.isEmpty) return null;
    final matchQuery = tokenizedVariants.join(' OR ');
```

修改同一方法內 `rawQuery` 的參數列（第 248-262 行區塊結尾），把：

```dart
        ) sub
        $orderClause
        LIMIT ?
      ''', [tokenized, bookId, limit]);
```

改為：

```dart
        ) sub
        $orderClause
        LIMIT ?
      ''', [matchQuery, bookId, limit]);
```

修改同一方法內組裝 `ContentMatchSnippet` 的 `_truncate()` 呼叫（第 277-283 行），把：

```dart
    final totalMatches = rows.first['total_count'] as int;
    final matches = rows
        .map((row) => ContentMatchSnippet(
              snippet: _truncate(row['raw_text'] as String, trimmedQuery),
              locator: row['locator'] as String,
              chapterIndex: row['chapter_index'] as int?,
            ))
        .toList();
```

改為：

```dart
    final totalMatches = rows.first['total_count'] as int;
    final matches = rows
        .map((row) => ContentMatchSnippet(
              snippet: _truncate(row['raw_text'] as String, variants),
              locator: row['locator'] as String,
              chapterIndex: row['chapter_index'] as int?,
            ))
        .toList();
```

修改 `_truncate()`（第 293-320 行），把：

```dart
  /// 【審查修正 I-4，推翻原計畫第一版「固定從頭截斷」設計】以 [query]
  /// （未經 `tokenizeForQuery()` 轉換的原始查詢字串）在 [text] 中的位置
  /// 為中心截斷，而非固定取前 [_maxSnippetRunes] 個字元——CJK 統一表意
  /// 文字（U+4E00-U+9FFF）皆落在 UTF-16 基本多文種平面（BMP）內，
  /// `String.indexOf()` 回傳的 UTF-16 code unit 索引與 rune 索引一致，
  /// 可直接當作 rune 索引使用；`token_text` 只用於索引比對，`raw_text`
  /// 保留原始未加空白的文字序列，[query] 理論上會以連續子字串的形式
  /// 出現在 [text] 中。
  static String _truncate(String text, String query) {
    final runes = text.runes.toList();
    if (runes.length <= _maxSnippetRunes) return text;

    final matchIndex = text.toLowerCase().indexOf(query.toLowerCase());
    if (matchIndex < 0) {
      // 找不到（理論上不會發生，見上方說明，但輸入型態多樣不假設一定
      // 找得到）：退回從頭截斷的保底邏輯。
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
```

改為：

```dart
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
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/search/search_repository_test.dart`
Expected: 全數 PASS（既有測試零回歸＋新增 4 個測試通過）。

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/search/search_repository.dart app/test/search/search_repository_test.dart
git commit -m "feat(search): SqliteSearchRepository 三個查詢方法改用多變體查詢擴充"
```

---

### Task 3: `BookSearchScreen` 內容匹配摘要片段轉換＋跨字形高亮

**Files:**
- Modify: `app/lib/screens/book_search_screen.dart`
- Test: `app/test/screens/book_search_screen_test.dart`

**Interfaces:**
- Consumes: `queryVariants(String)`／`findMatchingVariant(String, List<String>)`（Task 1）、`convertText(String, TextConversionMode)`（Issue 0）、`resolveTextConversion(BookReaderPrefs, ReadingDefaults)`（Issue 1）。
- Produces: 無（本 Task 為終端 UI 消費者）。

**審查修正說明（review-plan-issue-4.md I-2，架構調整，非原樣採納審查建議的程式碼）**：審查發現 `LibrarySearchScreen._openBookSearch()` 下鑽開啟本畫面時傳入未轉換的原始 `Book`，導致 AppBar 標題／作者顯示原文。審查建議的修法是讓 `LibrarySearchScreen` 在下鑽前用**全域**模式預先轉換 `book.title`／`book.author` 再傳入——但本畫面 AppBar 標題／作者依 Issue 3 既定設計是**單書情境**（`resolveTextConversion(bookPrefs, global)`，可被該書的 `textConversionOverride` 覆寫），若改用呼叫端的全域模式預先轉換，當目標書籍有單書覆寫、且覆寫值與全域值不同時，會與從 `ReaderScreen` 進入本畫面時顯示的字形不一致（同一本書、同一個 `BookSearchScreen`，卻依入口不同顯示不同字形）；且預先轉換後的字串會被存進傳給 `_handleSnippetTap()` 開書路徑（`buildReaderScreen(book: widget.book, ...)`）的 `Book` 物件，有非必要的雙重轉換風險。改為讓 `BookSearchScreen` **自行**呼叫 `widget.prefsManager.load(widget.book.id)` 解析該書的單書情境生效值——與 `ReaderScreen` 使用同一套 `resolveTextConversion()` 邏輯，對任何入口（`ReaderScreen` 或 `LibrarySearchScreen`）都能得到一致且正確的結果，`LibrarySearchScreen._openBookSearch()` 因此不需要修改（Task 4 不再包含這項）。

- [ ] **Step 1: 新增失敗測試**

在 `app/test/screens/book_search_screen_test.dart` 第 14 行（`import 'package:elinkbook/search/search_repository.dart';`）之後新增：

```dart
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';
```

找到檔案結尾「片段清單關鍵字高亮文字大小應與一般清單項目一致」測試結尾的 `});`，在其後、`main()` 結尾的 `}`（第 446 行）之前新增：

```dart

  testWidgets('全域簡繁轉換為繁體時，內容匹配摘要片段依轉換模式呈現（epic-42-text-conversion Issue 4）',
      (tester) async {
    final searchRepo = FakeSearchRepository(
      bookSearchDetailResult: BookSearchDetailResult(
        book: _testBook(),
        matches: const [
          ContentMatchSnippet(
            snippet: '国电脑维修站',
            locator: 'epubcfi(/6/2)',
            chapterIndex: 1,
          ),
        ],
        totalMatches: 1,
        isTruncated: false,
      ),
    );
    final prefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(
          textConversion: TextConversionMode.toTraditional,
        ),
      ),
    );

    await tester.pumpWidget(_wrap(BookSearchScreen(
      book: _testBook(),
      initialQuery: '国电脑',
      searchRepository: searchRepo,
      prefsManager: prefsManager,
      libraryRepository: FakeLibraryRepository(),
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('國電腦維修站'), findsOneWidget);
    expect(find.textContaining('国电脑维修站'), findsNothing);
  });

  testWidgets('跨字形高亮：轉換後顯示的文字仍能正確高亮使用者輸入的查詢字詞（spec.md 審查修正 I-2）',
      (tester) async {
    final searchRepo = FakeSearchRepository(
      bookSearchDetailResult: BookSearchDetailResult(
        book: _testBook(),
        matches: const [
          ContentMatchSnippet(
            snippet: '這裡有電腦維修的說明',
            locator: 'epubcfi(/6/2)',
            chapterIndex: 1,
          ),
        ],
        totalMatches: 1,
        isTruncated: false,
      ),
    );

    // 顯示模式維持 original（不轉換），片段本身已是繁體「電腦」，使用者
    // 卻用簡體「电脑」搜尋——高亮比對必須改用能在文字中找到的變體
    // 「電腦」，而非直接用使用者輸入的「电脑」（否則 indexOf 找不到，
    // 完全不會產生任何高亮片段）。
    await tester.pumpWidget(_wrap(BookSearchScreen(
      book: _testBook(),
      initialQuery: '电脑',
      searchRepository: searchRepo,
      prefsManager: FakeReaderPrefsManager(),
      libraryRepository: FakeLibraryRepository(),
    )));
    await tester.pumpAndSettle();

    final texts = tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('book_search_snippet_0')),
        matching: find.byType(Text),
      ),
    );
    final richText = texts.firstWhere((t) => t.textSpan != null);
    final boldSpans = (richText.textSpan as TextSpan)
        .children!
        .whereType<TextSpan>()
        .where((s) => s.style?.fontWeight == FontWeight.bold)
        .toList();
    expect(boldSpans, hasLength(1));
    expect(boldSpans.single.text, '電腦');
  });

  testWidgets(
      '單書覆寫簡繁轉換時，AppBar 標題／工具列作者依該書生效模式呈現，與內容摘要片段的全域轉換模式各自獨立'
      '（epic-42-text-conversion Issue 4，審查修正 review-plan-issue-4.md I-2）', (tester) async {
    final book = _testBook(title: '国电脑维修', author: '电脑作者');
    final searchRepo = FakeSearchRepository(
      bookSearchDetailResult: BookSearchDetailResult(
        book: book,
        matches: const [
          ContentMatchSnippet(
            snippet: '国电脑维修站',
            locator: 'epubcfi(/6/2)',
            chapterIndex: 1,
          ),
        ],
        totalMatches: 1,
        isTruncated: false,
      ),
    );
    final prefsManager = FakeReaderPrefsManager(
      bookPrefsByBookId: {
        book.id: const BookReaderPrefs(
          textConversionOverride: TextConversionMode.toSimplified,
        ),
      },
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(
          textConversion: TextConversionMode.toTraditional,
        ),
      ),
    );

    await tester.pumpWidget(_wrap(BookSearchScreen(
      book: book,
      initialQuery: '国电脑',
      searchRepository: searchRepo,
      prefsManager: prefsManager,
      libraryRepository: FakeLibraryRepository(),
    )));
    await tester.pumpAndSettle();

    // AppBar 標題（單書情境，該書覆寫值 toSimplified）維持簡體原文不變，
    // 不受全域值 toTraditional 影響。
    expect(find.widgetWithText(AppBar, '国电脑维修'), findsOneWidget);
    // 內容摘要片段（跨書情境，一律採全域值 toTraditional）轉為繁體。
    expect(find.textContaining('國電腦維修站'), findsOneWidget);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/book_search_screen_test.dart`
Expected: 新增的 3 個測試皆 FAIL（摘要片段仍是未轉換的原文；高亮比對找不到任何變體，`boldSpans` 為空清單；AppBar 標題仍是 `_testBook()` 預設的「測試書」，非測試傳入的覆寫書名）。

- [ ] **Step 3: 實作轉換與跨字形高亮**

在 `app/lib/screens/book_search_screen.dart` 第 10 行（`import '../reader/reader_prefs_manager.dart';`）之後新增：

```dart
import '../reader/resolve_text_conversion.dart';
import '../reader/text_conversion.dart';
import '../reader/text_conversion_mode.dart';
```

在第 11 行（`import '../search/highlight_segments.dart';`）之後新增：

```dart
import '../search/search_query_variants.dart';
```

在第 67 行（`static const _kEinkItemsPerPage = 10;`）之後、第 70 行 `void initState()` 之前新增：

```dart

  /// 內容匹配摘要片段的顯示轉換模式（FR-48，epic-42-text-conversion
  /// Issue 4，spec.md「全文檢索整合」）：一律採全域預設值（「跨書情境」
  /// 規則），不做單書覆寫。
  TextConversionMode _contentTextConversion = TextConversionMode.original;

  /// AppBar 書名／工具列作者的顯示轉換模式（FR-48，單書情境）：依
  /// [widget.book] 所屬的 `resolveTextConversion()` 解析值——與
  /// [_contentTextConversion] 刻意不同層級（見 spec.md「Dart 端字元轉換
  /// 模組」呼叫點分流規則）。本畫面自行解析、不依賴呼叫端是否已預先轉換
  /// 過傳入的 [widget.book]（審查修正 review-plan-issue-4.md I-2）：
  /// `LibrarySearchScreen` 下鑽入口與 `ReaderScreen` 單書搜尋入口皆傳入
  /// 未轉換的原始 `Book`，本畫面統一在此處解析，兩個入口顯示結果一致。
  TextConversionMode _titleTextConversion = TextConversionMode.original;
```

修改 `initState()`（第 70-80 行），把：

```dart
  @override
  void initState() {
    super.initState();
    // 裝置不支援全文檢索時跳過初始查詢，由 UI 呈現降級提示（review-plan-issue-7.md I-3）。
    if (!widget.readerFeatureRepositories.isFullTextSearchAvailable) {
      return;
    }
    final initial = widget.initialQuery.trim();
    if (initial.isNotEmpty) {
      _runSearch(initial);
    }
  }
```

改為（審查修正 I-1：原稿以 `unawaited(_loadTextConversion())` 讓「讀偏好」與「初始查詢」並行，若初始查詢先 resolve，畫面會先以未轉換原文渲染、隨後才跳變為轉換後文字。改為 `await` 讓偏好完整載入後才觸發初始查詢，徹底消除這個競態與閃爍——比照 `review-plan-issue-3.md` I-2 對 `LibraryScreen._initialize()` 的同一套修法）：

```dart
  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final loaded = await widget.prefsManager.load(widget.book.id);
    if (!mounted) return;
    setState(() {
      _contentTextConversion = loaded.globalPrefs.reading.textConversion;
      _titleTextConversion = resolveTextConversion(
        loaded.bookPrefs,
        loaded.globalPrefs.reading,
      );
    });
    // 裝置不支援全文檢索時跳過初始查詢，由 UI 呈現降級提示（review-plan-issue-7.md I-3）。
    if (!widget.readerFeatureRepositories.isFullTextSearchAvailable) {
      return;
    }
    final initial = widget.initialQuery.trim();
    if (initial.isNotEmpty) {
      _runSearch(initial);
    }
  }
```

修改 `build()` 的 AppBar 標題（第 166-172 行），把：

```dart
      appBar: AppBar(
        title: Text(
          widget.book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
```

改為：

```dart
      appBar: AppBar(
        title: Text(
          convertText(widget.book.title, _titleTextConversion),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
```

修改 `_buildToolbar()` 的作者顯示（第 237-245 行），把：

```dart
          if (widget.book.author != null && widget.book.author!.isNotEmpty)
            Flexible(
              child: Text(
                widget.book.author!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
```

改為：

```dart
          if (widget.book.author != null && widget.book.author!.isNotEmpty)
            Flexible(
              child: Text(
                convertText(widget.book.author!, _titleTextConversion),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
```

修改 `_buildResults()`（比對 `trimmedQuery` 宣告處），把：

```dart
    final trimmedQuery = _controller.text.trim();
    final isPdf = widget.book.format == BookFileFormat.pdf;

    if (!widget.isEinkMode) {
      // 非 E-Ink：連續捲動
      return ListView.builder(
        itemCount: result.matches.length,
        itemBuilder: (context, index) => _buildSnippetTile(
          result.matches[index],
          index,
          trimmedQuery,
          isPdf,
        ),
      );
    }
```

改為（審查修正 M-1：`variants` 在此預先算一次，避免每筆結果各自重複呼叫 `queryVariants()`）：

```dart
    final trimmedQuery = _controller.text.trim();
    final variants = queryVariants(trimmedQuery);
    final isPdf = widget.book.format == BookFileFormat.pdf;

    if (!widget.isEinkMode) {
      // 非 E-Ink：連續捲動
      return ListView.builder(
        itemCount: result.matches.length,
        itemBuilder: (context, index) => _buildSnippetTile(
          result.matches[index],
          index,
          variants,
          isPdf,
        ),
      );
    }
```

修改 E-Ink 分支的 `_buildSnippetTile()` 呼叫，把：

```dart
              for (var i = pageStart; i < pageEnd; i++)
                _buildSnippetTile(result.matches[i], i, trimmedQuery, isPdf),
```

改為：

```dart
              for (var i = pageStart; i < pageEnd; i++)
                _buildSnippetTile(result.matches[i], i, variants, isPdf),
```

修改 `_buildSnippetTile()`（第 327-346 行），把：

```dart
  Widget _buildSnippetTile(
    ContentMatchSnippet snippet,
    int index,
    String query,
    bool isPdf,
  ) {
    // 位置標籤：PDF「第 X 頁」，其餘「第 X 章」（chapterIndex 為 0-based）。
    final chapterIndex = snippet.chapterIndex;
    final locationText = chapterIndex != null
        ? (isPdf ? '第 ${chapterIndex + 1} 頁' : '第 ${chapterIndex + 1} 章')
        : null;

    return ListTile(
      key: Key('book_search_snippet_$index'),
      dense: true,
      title: _buildHighlightedText(snippet.snippet, query),
      subtitle: locationText != null ? Text(locationText) : null,
      onTap: () => _handleSnippetTap(snippet),
    );
  }
```

改為：

```dart
  Widget _buildSnippetTile(
    ContentMatchSnippet snippet,
    int index,
    List<String> variants,
    bool isPdf,
  ) {
    // 位置標籤：PDF「第 X 頁」，其餘「第 X 章」（chapterIndex 為 0-based）。
    final chapterIndex = snippet.chapterIndex;
    final locationText = chapterIndex != null
        ? (isPdf ? '第 ${chapterIndex + 1} 頁' : '第 ${chapterIndex + 1} 章')
        : null;
    final displaySnippet = convertText(snippet.snippet, _contentTextConversion);

    return ListTile(
      key: Key('book_search_snippet_$index'),
      dense: true,
      title: _buildHighlightedText(displaySnippet, variants),
      subtitle: locationText != null ? Text(locationText) : null,
      onTap: () => _handleSnippetTap(snippet),
    );
  }
```

修改 `_buildHighlightedText()`（第 353-354 行），把：

```dart
  Widget _buildHighlightedText(String text, String query) {
    final segments = splitHighlightSegments(text, query);
```

改為（審查修正 I-2〔spec.md 原有編號〕＋ M-1：`variants` 改由呼叫端預先算好傳入，不在本方法內重複呼叫 `queryVariants()`）：

```dart
  Widget _buildHighlightedText(String text, List<String> variants) {
    // 跨字形高亮：命中內容字形可能與使用者輸入字形不同（例如使用者輸入
    // 簡體「电脑」命中繁體原文「電腦」的章節），改用 findMatchingVariant()
    // 依序嘗試 indexOf，取第一個能在 text 中找到的變體做為高亮比對
    // 基準，而非只用原始查詢字串——找不到任何變體時（理論上不會發生，
    // 見 search_query_variants.dart 說明）保底退回 variants.first（恆為
    // 原始查詢字串 q0，見 queryVariants() 文件註解），交由
    // splitHighlightSegments() 既有「找不到則不高亮」邏輯安全處理。
    final matchQuery = findMatchingVariant(text, variants) ?? variants.first;
    final segments = splitHighlightSegments(text, matchQuery);
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/book_search_screen_test.dart`
Expected: 全數 PASS（既有測試零回歸＋新增 3 個測試通過）。

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/book_search_screen.dart app/test/screens/book_search_screen_test.dart
git commit -m "feat(search): BookSearchScreen 內容匹配摘要片段接上顯示轉換與跨字形高亮"
```

---

### Task 4: `LibrarySearchScreen` 書名/作者與內容匹配摘要片段轉換

**Files:**
- Modify: `app/lib/screens/library_search_screen.dart`
- Test: `app/test/screens/library_search_screen_test.dart`

**Interfaces:**
- Consumes: `convertText(String, TextConversionMode)`（Issue 0）、`GlobalReaderPrefs.reading.textConversion`（Issue 1）、`BookCover.textConversion`（Issue 3 既有交付，`app/lib/library/widgets/book_cover.dart`，本 Task 只是新增一個呼叫端傳入，不修改 `book_cover.dart` 本身）。
- Produces: 無（本計畫最後一個 Task）。

**範圍澄清（已與使用者確認）**：issues.md Issue 4 字面範圍只提到「內容匹配摘要片段」需轉換，但 spec.md「Dart 端字元轉換模組」跨書情境條列把「書架書名/作者渲染（LibraryScreen）、全庫搜尋結果片段（書名/作者匹配區＋內容匹配區）」寫在同一句——本 Task 依 spec.md（唯一事實來源）辦理，一併轉換 `_buildTitleAuthorTile()` 與 `_buildContentGroupCard()` 書籍標頭的書名/作者，不只轉換內容匹配摘要片段，避免使用者從已轉換的 `LibraryScreen` 進到 `LibrarySearchScreen` 時書名字形突然跳回原文。

- [ ] **Step 1: 新增失敗測試**

在 `app/test/screens/library_search_screen_test.dart` 找到既有 import 區塊內 `import 'package:elinkbook/reader/percent_rect.dart';` 之後新增：

```dart
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';
```

找到第 196-240 行「結果分「書名/作者匹配」與「內容匹配」兩區呈現」測試結尾的 `});`，在其後新增：

```dart

  testWidgets(
      '全域簡繁轉換為繁體時，書名/作者匹配區、內容匹配區書籍標頭與摘要片段皆依轉換模式呈現'
      '（epic-42-text-conversion Issue 4）', (tester) async {
    final matchedBook = _testBook(id: 'b1', title: '国电脑维修', author: '电脑作者');
    final searchRepository = FakeSearchRepository(
      titleAuthorResults: [matchedBook],
      contentResults: [
        BookContentMatches(
          book: matchedBook,
          matches: const [
            ContentMatchSnippet(
              snippet: '含有电脑维修关键字的句子',
              locator: 'epubcfi(/6/2)',
            ),
          ],
        ),
      ],
    );
    final prefsManager = FakeReaderPrefsManager(
      globalPrefs: const GlobalReaderPrefs.initial().copyWith(
        reading: const ReadingDefaults(
          textConversion: TextConversionMode.toTraditional,
        ),
      ),
    );

    await tester.pumpWidget(
      wrap(LibrarySearchScreen(
        initialQuery: '国电脑',
        searchRepository: searchRepository,
        prefsManager: prefsManager,
        libraryRepository: FakeLibraryRepository(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          fullTextSearchSettingsRepository:
              FakeFullTextSearchSettingsRepository(initialEnabled: {
            ContentIndexCategory.pdf: true,
            ContentIndexCategory.foliate: true,
          }),
        ),
      )),
    );
    await tester.pumpAndSettle();

    // 審查修正 C-1：BookCover 無封面圖時會退回 CoverPlaceholder 渲染書名
    // 縮略文字（本畫面兩處 BookCover 皆為 40×56 尺寸，已達 CoverPlaceholder
    // 顯示文字的門檻——見 app/lib/library/widgets/book_cover.dart
    // _titleRowMinHeight/_titleRowMinWidth），與 ListTile.title／書籍標頭
    // 各顯示一次已轉換文字，兩處合計 2 個 widget；比照
    // library_screen_test.dart 既有測試慣例。
    expect(
      find.descendant(
        of: find.byKey(const Key('library_search_title_author_result_b1')),
        matching: find.text('國電腦維修'),
      ),
      findsNWidgets(2),
      reason: 'CoverPlaceholder 縮略與 ListTile.title 各顯示一次',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('library_search_title_author_result_b1')),
        matching: find.text('国电脑维修'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('library_search_title_author_result_b1')),
        matching: find.text('電腦作者'),
      ),
      findsOneWidget,
      reason: '作者僅顯示於列表副標題，CoverPlaceholder 不含作者欄位',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('library_search_content_group_b1')),
        matching: find.text('國電腦維修'),
      ),
      findsNWidgets(2),
      reason: '內容匹配卡片的 CoverPlaceholder 縮略與書籍標頭各顯示一次，皆需要轉換',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('library_search_content_group_b1')),
        matching: find.text('国电脑维修'),
      ),
      findsNothing,
    );
    expect(find.text('含有電腦維修關鍵字的句子'), findsOneWidget);
    expect(find.text('含有电脑维修关键字的句子'), findsNothing);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/library_search_screen_test.dart`
Expected: 新增的測試 FAIL（書名/作者/摘要片段仍是未轉換的原文；即使補上 `_textConversion` 轉換邏輯而未同步修正 `BookCover` 呼叫點，`findsNWidgets(2)` 也會因 `CoverPlaceholder` 仍顯示原文而只找到 1 個繁體 widget，持續失敗）。

- [ ] **Step 3: 實作轉換**

在 `app/lib/screens/library_search_screen.dart` 第 10 行（`import '../reader/reader_prefs_manager.dart';`）之後新增：

```dart
import '../reader/text_conversion.dart';
import '../reader/text_conversion_mode.dart';
```

在第 73 行（`static const _kEinkResultsPerPage = 5;`）之後、第 76 行 `void initState()` 之前新增：

```dart

  /// 書名/作者匹配區＋內容匹配區的顯示轉換模式（FR-48，epic-42-text-
  /// conversion Issue 4，spec.md「Dart 端字元轉換模組」跨書情境條列：
  /// 「全庫搜尋結果片段（書名/作者匹配區＋內容匹配區）」）：一律採全域
  /// 預設值，不做任何單書覆寫。
  TextConversionMode _textConversion = TextConversionMode.original;
```

修改 `initState()`（第 76-83 行），把：

```dart
  @override
  void initState() {
    super.initState();
    _loadFullTextSearchSettings();
    final initial = widget.initialQuery.trim();
    if (initial.isNotEmpty) {
      _runSearch(initial);
    }
  }
```

改為（審查修正 I-1：原稿以 `unawaited(_loadTextConversion())` 讓「讀偏好」與「初始查詢」並行，若初始查詢先 resolve，畫面會先以未轉換原文渲染、隨後才跳變為轉換後文字。改為 `Future.wait` 讓 `_loadFullTextSearchSettings()`／`_loadTextConversion()` 兩個獨立偏好並行載入完成後才觸發初始查詢，徹底消除這個競態與閃爍——比照 `review-plan-issue-3.md` I-2 對 `LibraryScreen._initialize()` 的同一套修法）：

```dart
  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await Future.wait([
      _loadFullTextSearchSettings(),
      _loadTextConversion(),
    ]);
    if (!mounted) return;
    final initial = widget.initialQuery.trim();
    if (initial.isNotEmpty) {
      _runSearch(initial);
    }
  }

  Future<void> _loadTextConversion() async {
    final globalPrefs = await widget.prefsManager.loadGlobalPrefs();
    if (!mounted) return;
    setState(() => _textConversion = globalPrefs.reading.textConversion);
  }
```

修改 `_buildTitleAuthorTile()`（第 299-311 行），把：

```dart
  Widget _buildTitleAuthorTile(Book book) {
    return ListTile(
      key: Key('library_search_title_author_result_${book.id}'),
      leading: SizedBox(width: 40, height: 56, child: BookCover(book: book)),
      title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        book.author ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _openBook(book),
    );
  }
```

改為（審查修正 C-1：`BookCover` 未傳 `textConversion` 時退回預設 `original`，無封面圖時 `CoverPlaceholder` 會顯示未轉換的原文書名縮略字，與右側已轉換的 `ListTile.title` 字形矛盾）：

```dart
  Widget _buildTitleAuthorTile(Book book) {
    return ListTile(
      key: Key('library_search_title_author_result_${book.id}'),
      leading: SizedBox(
        width: 40,
        height: 56,
        child: BookCover(book: book, textConversion: _textConversion),
      ),
      title: Text(convertText(book.title, _textConversion),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        convertText(book.author ?? '', _textConversion),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _openBook(book),
    );
  }
```

修改 `_buildContentGroupCard()` 的書籍標頭與 `BookCover`（第 322-336 行），把：

```dart
            leading: SizedBox(
              width: 40,
              height: 56,
              child: BookCover(book: group.book),
            ),
            title: Text(
              group.book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              group.book.author ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
```

改為（審查修正 C-1，同上）：

```dart
            leading: SizedBox(
              width: 40,
              height: 56,
              child: BookCover(book: group.book, textConversion: _textConversion),
            ),
            title: Text(
              convertText(group.book.title, _textConversion),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              convertText(group.book.author ?? '', _textConversion),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
```

修改 `_buildContentGroupCard()` 的摘要片段（第 344 行），把：

```dart
              title: Text(group.matches[i].snippet),
```

改為：

```dart
              title: Text(convertText(group.matches[i].snippet, _textConversion)),
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/library_search_screen_test.dart`
Expected: 全數 PASS（既有測試零回歸＋新增測試通過）。

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: 執行完整 `flutter test`（本計畫最後一個 Task，比照專案慣例跑一次全套）**

Run: `flutter test`
Expected: 全數通過（既有已知不穩定案例除外，例如 `adaptive_shell_scaffold_test.dart` 既有失敗案例，非本次異動引入）。

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/library_search_screen.dart app/test/screens/library_search_screen_test.dart
git commit -m "feat(search): LibrarySearchScreen 書名/作者與內容匹配摘要片段接上全域顯示轉換"
```

---

## Self-Review

**Spec 覆蓋度**：對照 `issues.md` Issue 4「範圍」逐項核對——(1) 產生 `variants = distinct([q0, qt, qs])` → Task 1；(2) 內容匹配查詢 `searchContent`／`searchContentInBook` 以 FTS5 `OR` 組合 → Task 2；(3) 書名/作者查詢 `searchTitleAuthor` 以 SQL `OR` 串接 `whereArgs` → Task 2；(4) 內容匹配摘要片段依跨書情境轉換 → Task 3（`BookSearchScreen`）＋ Task 4（`LibrarySearchScreen`）；(5) 索引寫入端不變 → 全程未觸碰，見 Global Constraints；(6) 跨字形截斷定位與高亮連動（審查修正 I-2，`_truncate`／`splitHighlightSegments`）→ Task 2（`_truncate`）＋ Task 3（`_buildHighlightedText`）。六項單元測試要求（多變體 MATCH 組合、跨字形命中回歸、`searchTitleAuthor` OR 串接、摘要片段依全域顯示模式轉換、`_truncate` 跨字形定位、`splitHighlightSegments` 跨字形高亮）皆已對應到具體 Task 的測試步驟。額外依 spec.md（唯一事實來源）於 Task 4 補上 issues.md 字面未列出的 `LibrarySearchScreen` 書名/作者匹配區轉換（已於 Task 4 開頭「範圍澄清」註明依據與理由，非遺漏）。

**佔位符掃描**：全文檢查過，沒有 TBD／「之後補上」／「類似 Task N」等字樣；所有程式碼步驟皆為可直接執行的完整程式碼區塊；測試斷言使用既有已驗證字元對（「国电脑」↔「國電腦」、「电脑」↔「電腦」），未自行發明字元映射。

**型別一致性**：`queryVariants(String q0)` 回傳 `List<String>`、`findMatchingVariant(String text, List<String> variants)` 回傳 `String?`，兩者簽章在 Task 1 定案後，Task 2（`_truncate(String text, List<String> variants)`）、Task 3（`_buildHighlightedText(String text, List<String> variants)`，審查修正 M-1 改為接收預先算好的 `variants` 而非重複呼叫 `queryVariants()`）呼叫端完全依此簽章使用，無型別或參數順序不一致。`SearchRepository` 抽象介面（`searchTitleAuthor`／`searchContent`／`searchContentInBook`）三個公開方法簽章全程不變，`FakeSearchRepository`／既有呼叫端零回歸，已於 Task 2 Interfaces 段落明確記錄。`BookSearchScreen` 有兩個 `TextConversionMode` 欄位（`_contentTextConversion`＝跨書情境／`_titleTextConversion`＝單書情境，審查修正 review-plan-issue-4.md I-2 新增區分），`LibrarySearchScreen` 只有一個 `_textConversion`（純跨書情境），三者皆透過各自的載入方法於 `initState()`／`_initialize()` 非同步載入後才觸發初始查詢（審查修正 I-1）。

**已知限制**：`_truncate()`／`_buildHighlightedText()` 在 `findMatchingVariant()` 回傳 `null`（三個變體皆找不到）時的保底行為，理論上不會發生於本計畫測試涵蓋的情境（tokenizeForQuery 產生的 FTS5 MATCH 結果保證原始文字至少包含其中一個變體的子字串），但無法窮舉所有邊界輸入，兩處保底邏輯（截斷從頭開始／高亮完全不顯示）皆延續既有既定的保底設計，不視為本計畫的功能缺口。

**審查修訂記錄**（`reviews/review-plan-issue-4.md`）：C-1（`LibrarySearchScreen` 的 `BookCover` 漏傳 `textConversion` 導致封面縮略字與標題字形矛盾，且測試斷言數量未考量 `CoverPlaceholder` 雙字串行為）、I-1（`BookSearchScreen`／`LibrarySearchScreen` 的 `initState()` 用 `unawaited` 讓偏好載入與初始查詢並行，造成畫面閃爍競態）、I-3（缺少 `splitHighlightSegments` 跨字形命中的純函式單元測試）、M-1（`_buildHighlightedText` 每筆結果重複呼叫 `queryVariants`）、M-2（Task 1 測試數量文字誤植）、M-3（`tokenizedVariants` 建議去重防禦）均已採納並落地於對應 Task。**I-2 未原樣採納審查建議的程式碼**：審查建議讓 `LibrarySearchScreen._openBookSearch()` 用呼叫端的全域模式預先轉換 `book.title`／`book.author` 再傳入 `BookSearchScreen`——技術上與 Issue 3 既定的「`BookSearchScreen` AppBar 為單書情境」設計不一致（若目標書籍有單書覆寫、且覆寫值與全域值不同，會依入口不同顯示不同字形），且預先轉換後的字串會流入 `_handleSnippetTap()` 開書路徑重新建構的 `Book` 物件，有非必要的雙重轉換風險。改為讓 `BookSearchScreen` 自行呼叫 `widget.prefsManager.load(widget.book.id)` 解析單書情境生效值（Task 3），對任何入口皆一致正確，`LibrarySearchScreen._openBookSearch()` 因此不需要修改；已於 Task 3 開頭與 Global Constraints 補充完整技術理由。
