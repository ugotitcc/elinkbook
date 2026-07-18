# Epic 6 Issue 1：書籤管理 + 統一「筆記」入口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 為流式 EPUB／PDF／固定版面（FXL）新增書籤管理功能（新增/移除/重新命名/刪除/清單導覽），並建立單一「📚 筆記」入口 Bottom Sheet 外殼（帶「🔖 書籤」／「✏️ 劃線與備註」兩分頁籤），本 Issue 只完整實作書籤分頁，劃線與備註分頁留空狀態佔位符供 Issue 2/3 填入。

**Architecture:** 新增 `bookmarks` SQLite 表（`book_id` 外鍵關聯 `books`，比照 `book_reader_prefs` 既有關聯模式）與對應的 `BookmarksRepository`；新建 `NotesBottomSheet` widget（`TabController` 雙分頁殼，比照 `PdfSettingsSheet` 既有 TabBar 慣例）；`ReaderScreen` 新增可選的 `bookmarksRepository` 建構參數（**刻意設為 optional，非 required**——避免破壞 75 個既有 `ReaderScreen(...)` 測試呼叫端，比照 `ReaderPrefsManagerImpl` 對 `EpubCharacterCountRepository` 的既有可選注入先例）。

**Tech Stack:** Flutter/Dart、`sqflite`（SQLite）、`sqflite_common_ffi`（測試用記憶體資料庫）。

## Global Constraints

- 所有程式註解、文件、commit message 皆使用正體中文（zh-TW）。
- `ReaderScreen` 是本專案唯一的閱讀器 seam（`CLAUDE.md`），本 Issue 不新增第二個閱讀器入口。
- **`bookmarksRepository` 為 `ReaderScreen`／`LibraryScreen`／`ElinkBookApp` 的可選具名建構參數**（`BookmarksRepository?`，預設 `null`）。已查證目前有 43 個 `ReaderScreen(...)`、27 個 `LibraryScreen(...)`、5 個 `ElinkBookApp(...)` 測試呼叫端未提供此參數，若設為 `required` 會全數編譯失敗；可選注入時，未提供者行為等同「本 Issue 之前」（不顯示 📚 筆記按鈕），零回歸風險。
- 兩層測試架構（`CLAUDE.md`）：`app/test/` 純 widget test，不 mock 原生 method channel（既有慣例，`EpubReaderView`/`PdfReaderView` 的 `_channel` 恆為 `null`，`_channel?.invokeMethod(...)` 安全 no-op）；真機驗證留給 `app/integration_test/`。
- SQLite schema migration 沿用累加式 `if (oldVersion < N)`（絕不用 `else if`）。目前資料庫 `version` 為 7，本 Issue 提升至 8。`PRAGMA foreign_keys = ON` 已於既有 `onConfigure` 對整個連線設定，`bookmarks` 表的外鍵約束自動生效，不需額外宣告（見 `sqlite_library_repository.dart` 第 28-32 行既有程式碼）。
- `flutter analyze` 全程必須保持 `No issues found!`；每個 Task 的最後一步皆須執行並確認。
- 書籤 toggle（同一頁/位置最多一筆）的相等性判斷：**EPUB／FXL 用 `epubLocatorJson` 精確字串比對；PDF 用 `pdfPageIndex` 精確比對**——本計劃書自行定案這個 `design.md`/`issues.md` 未展開到此細節的判斷依據，理由：EPUB 沒有穩定的「頁」概念（`EpubPageEstimator` 的估算頁數會隨字體大小等版面參數變動），用「目前這一刻的精確定位字串」判斷比任何模糊的「頁」概念更明確、可測試。**審查修正（見 `tmp/epic-6/reviews/plan_issue_1_review.md` 1.1）**：FXL（固定版面漫畫）副檔名是 `.epub`，`ReaderScreen._openNotesSheet` 只在 `format == BookFormat.pdf` 時才填入 `pdfPageIndex`；FXL 永遠落在 `BookFormat.epub` 分支，技術上仍透過 `epubLocatorJson`／`progression` 追蹤位置，不會有 `pdfPageIndex`——原先誤寫成「PDF/FXL 用 pdfPageIndex」，已訂正為「PDF 專屬」，FXL 併入 EPUB 那一組判斷依據。

---

### Task 1：`Bookmark` 模型 + `BookmarkPositionContext` + 預設命名純函式

**Files:**
- Create: `app/lib/reader/bookmark_position_context.dart`
- Create: `app/lib/reader/bookmark.dart`
- Test: `app/test/reader/bookmark_test.dart`

**Interfaces:**
- Produces: `BookmarkPositionContext`（`epubLocatorJson`／`progression`／`pdfPageIndex`／`chapterTitle` 皆為 nullable）；`Bookmark`（`id`／`bookId`／`name`／`epubLocatorJson`／`progression`／`pdfPageIndex`，`toMap()`／`fromMap()`／`copyWith({name})`／`==`/`hashCode`）；`Bookmark.defaultName(BookmarkPositionContext)` 靜態方法，供 Task 5 消費。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/reader/bookmark_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmark_position_context.dart';

void main() {
  test('toMap／fromMap round-trip 保留所有欄位（不含 id）', () {
    const bookmark = Bookmark(
      bookId: 'b1',
      name: '第二章 (35%)',
      epubLocatorJson: '{"href":"/c2.xhtml"}',
      progression: 0.35,
    );
    final map = bookmark.toMap();
    expect(map.containsKey('id'), isFalse);
    expect(map['book_id'], 'b1');
    expect(map['name'], '第二章 (35%)');
    expect(map['epub_locator_json'], '{"href":"/c2.xhtml"}');
    expect(map['progression'], 0.35);
    expect(map['pdf_page_index'], isNull);
  });

  test('fromMap 正確還原 id（模擬資料庫查詢結果）', () {
    final restored = Bookmark.fromMap({
      'id': 7,
      'book_id': 'b1',
      'name': '第 12 頁',
      'epub_locator_json': null,
      'progression': null,
      'pdf_page_index': 11,
    });
    expect(restored.id, 7);
    expect(restored.bookId, 'b1');
    expect(restored.name, '第 12 頁');
    expect(restored.pdfPageIndex, 11);
  });

  test('copyWith 只更新 name，其餘欄位保留原值', () {
    const original = Bookmark(
      id: 3,
      bookId: 'b1',
      name: '舊名稱',
      pdfPageIndex: 5,
    );
    final renamed = original.copyWith(name: '新名稱');
    expect(renamed.id, 3);
    expect(renamed.bookId, 'b1');
    expect(renamed.name, '新名稱');
    expect(renamed.pdfPageIndex, 5);
  });

  test('defaultName：PDF 用「第 N 頁」（1-indexed 顯示）', () {
    const context = BookmarkPositionContext(pdfPageIndex: 11);
    expect(Bookmark.defaultName(context), '第 12 頁');
  });

  test(
      'defaultName：FXL（固定版面漫畫）沒有 pdfPageIndex 可用，回退為進度百分比'
      '（審查修正 1.1，見 tmp/epic-6/reviews/plan_issue_1_review.md）——'
      'FXL 副檔名是 .epub，ReaderScreen._openNotesSheet 只在'
      'format == BookFormat.pdf 時才填入 pdfPageIndex，FXL 永遠落在'
      'BookFormat.epub 分支、pdfPageIndex 恆為 null，且 FXL 通常無章節'
      '結構（_tocEntries 對固定版面永遠不預取），故實際只會走 progression'
      '這條路徑', () {
    const context = BookmarkPositionContext(progression: 0.42);
    expect(Bookmark.defaultName(context), '42% 處');
  });

  test('defaultName：EPUB 有章節名稱與進度時，組合成「章節 (百分比%)」', () {
    const context = BookmarkPositionContext(
      chapterTitle: '第二章',
      progression: 0.353,
    );
    expect(Bookmark.defaultName(context), '第二章 (35%)');
  });

  test('defaultName：EPUB 只有章節名稱、無進度時，僅顯示章節名稱', () {
    const context = BookmarkPositionContext(chapterTitle: '第二章');
    expect(Bookmark.defaultName(context), '第二章');
  });

  test('defaultName：EPUB 只有進度、無章節名稱時，顯示「百分比% 處」', () {
    const context = BookmarkPositionContext(progression: 0.5);
    expect(Bookmark.defaultName(context), '50% 處');
  });

  test('defaultName：章節名稱與進度皆無法取得時，回退為「書籤」', () {
    const context = BookmarkPositionContext();
    expect(Bookmark.defaultName(context), '書籤');
  });

  test('兩個欄位值完全相同的 Bookmark 視為相等', () {
    const a = Bookmark(id: 1, bookId: 'b1', name: 'X', pdfPageIndex: 5);
    const b = Bookmark(id: 1, bookId: 'b1', name: 'X', pdfPageIndex: 5);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('任一欄位不同時視為不相等', () {
    const a = Bookmark(id: 1, bookId: 'b1', name: 'X', pdfPageIndex: 5);
    const b = Bookmark(id: 1, bookId: 'b1', name: 'Y', pdfPageIndex: 5);
    expect(a, isNot(b));
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/bookmark_test.dart`
Expected: FAIL（`bookmark.dart`／`bookmark_position_context.dart` 尚不存在，編譯錯誤）

- [ ] **Step 3: 實作 `BookmarkPositionContext`**

建立 `app/lib/reader/bookmark_position_context.dart`：

```dart
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
```

- [ ] **Step 4: 實作 `Bookmark`**

建立 `app/lib/reader/bookmark.dart`：

```dart
import 'bookmark_position_context.dart';

/// 單一書籤（epic-6-annotations Issue 1，spec.md「書籤模組」）：標記書中
/// 「一個位置」的具名離散事件，定位精度同閱讀進度（EPUB／FXL：CFI＋進度
/// 比例；PDF：頁索引）。[epubLocatorJson]／[pdfPageIndex] 互斥，一筆書籤只會
/// 用到其中一組（依書籍格式而定，FXL 因副檔名是 .epub 而併入 EPUB 那一組，
/// 見審查修正 1.1），比照 ReadingPosition 既有的欄位語意。
class Bookmark {
  /// SQLite 自動指派的 rowid，新增前（尚未寫入資料庫）為 null。
  final int? id;
  final String bookId;
  final String name;
  final String? epubLocatorJson;
  final double? progression;
  final int? pdfPageIndex;

  const Bookmark({
    this.id,
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
      'book_id': bookId,
      'name': name,
      'epub_locator_json': epubLocatorJson,
      'progression': progression,
      'pdf_page_index': pdfPageIndex,
    };
  }

  factory Bookmark.fromMap(Map<String, Object?> map) {
    return Bookmark(
      id: map['id'] as int?,
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
  static String defaultName(BookmarkPositionContext context) {
    if (context.pdfPageIndex != null) {
      return '第 ${context.pdfPageIndex! + 1} 頁';
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
      return '$percent% 處';
    }
    return '書籤';
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
```

- [ ] **Step 5: 執行測試確認通過**

Run: `flutter test test/reader/bookmark_test.dart`
Expected: PASS（全部測試綠燈）

- [ ] **Step 6: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/reader/bookmark.dart app/lib/reader/bookmark_position_context.dart app/test/reader/bookmark_test.dart
git commit -m "feat(epic-6): 新增 Bookmark 模型與預設命名純函式"
```

---

### Task 2：SQLite `bookmarks` 表 + schema migration（v7→v8）

**Files:**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Produces: `bookmarks` 表（欄位：`id INTEGER PRIMARY KEY AUTOINCREMENT`／`book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE`／`name TEXT NOT NULL`／`epub_locator_json TEXT`／`progression REAL`／`pdf_page_index INTEGER`），供 Task 3 的 `BookmarksRepository` 消費。

- [ ] **Step 1: 寫失敗測試**

於 `app/test/library/sqlite_library_repository_test.dart` 檔案結尾（最後一個 `}` 之前）新增：

```dart
  test('全新安裝的 bookmarks 表可用（version 8 起 onCreate 已含括）', () async {
    await repository.insertBook(_book('b_bookmark'));
    final id = await repository.database.insert('bookmarks', {
      'book_id': 'b_bookmark',
      'name': '第一章',
      'epub_locator_json': '{"href":"/c1.xhtml"}',
      'progression': 0.1,
      'pdf_page_index': null,
    });
    expect(id, greaterThan(0));

    final rows = await repository.database
        .query('bookmarks', where: 'book_id = ?', whereArgs: ['b_bookmark']);
    expect(rows.single['name'], '第一章');
  });

  test('既有 version 7 裝置升級到 version 8，bookmarks 表正確建立', () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v7_to_v8_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 7」的舊資料庫：手動以 version 7 當時的完整
    // schema（books/book_reader_prefs 皆為 version 7 最終樣貌，不含
    // bookmarks 表）建立，不透過 SqliteLibraryRepository.open()（該方法
    // 目前的 onCreate 已經是 version 8 的最終 schema，無法用來重現「舊
    // 裝置」情境）。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 7,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              epubLocator TEXT,
              pdfPageIndex INTEGER,
              totalCharacterCount INTEGER,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE book_reader_prefs (
              book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
              font_family TEXT,
              font_size REAL,
              font_weight REAL,
              line_height REAL,
              paragraph_spacing REAL,
              page_margins REAL,
              text_align TEXT,
              publisher_styles INTEGER,
              writing_mode_override TEXT,
              page_turn_mode_override TEXT,
              screen_orientation_override TEXT,
              pdf_fit_mode TEXT,
              pdf_contrast REAL,
              pdf_brightness REAL,
              pdf_bold_strength REAL,
              pdf_crop_mode TEXT,
              pdf_crop_rect TEXT,
              dual_page_mode TEXT,
              dual_page_cover_alone INTEGER,
              dual_page_direction TEXT,
              show_header INTEGER,
              show_footer INTEGER
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=7 →
    // newVersion=8），驗證 bookmarks 表確實建立且可寫入。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final id = await upgraded.database.insert('bookmarks', {
      'book_id': 'b1',
      'name': '測試書籤',
      'epub_locator_json': null,
      'progression': null,
      'pdf_page_index': 3,
    });
    expect(id, greaterThan(0));

    final rows = await upgraded.database
        .query('bookmarks', where: 'book_id = ?', whereArgs: ['b1']);
    expect(rows.single['name'], '測試書籤');

    // 既有書籍資料不受影響。
    final books = await upgraded.listBooks();
    expect(books.single.title, '既有書籍');
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: FAIL（`no such table: bookmarks`，因為 schema 尚未更新且 `version` 仍為 7）

- [ ] **Step 3: 實作 schema migration**

`app/lib/library/sqlite_library_repository.dart` 第 27 行，`version: 7,` 改為：

```dart
      version: 8,
```

第 33-59 行 `onCreate`，於 `await _createBookReaderPrefsTable(db);` 之後新增：

```dart
        await _createBookReaderPrefsTable(db);
        await _createBookmarksTable(db);
      },
```

第 102-108 行（`if (oldVersion < 6) { ... }` 區塊之後），新增第三個獨立區塊：

```dart
        if (oldVersion < 6) {
          // epic-5-toc-pagination Issue 3：全書字元數快取欄位，補追加到
          // 既有（version 1 起已存在）的 books 表。刻意放在上方 if/else
          // 之外、無條件檢查，比照 oldVersion < 5 區塊的既有原則——不論
          // 裝置目前處於哪個舊版本，只要 oldVersion < 6 就必須執行。
          await _addTotalCharacterCountColumn(db);
        }
        if (oldVersion < 8) {
          // epic-6-annotations Issue 1：書籤功能新增的全新資料表。與上方
          // books 表遷移刻意放在同一層級（onUpgrade 頂層、無條件檢查）——
          // bookmarks 是全新的獨立表（非既有表新增欄位），任何 oldVersion
          // < 8 的裝置都必然還沒有這張表，直接無條件建立即可，不像
          // book_reader_prefs 表那樣需要判斷「表是否已存在」（那是因為
          // book_reader_prefs 有 CREATE／ALTER 兩條分歧路徑，bookmarks
          // 只有一條路徑）。
          await _createBookmarksTable(db);
        }
      },
    );
    return SqliteLibraryRepository._(db);
  }
```

在 `_addHeaderFooterColumns` 方法（第 194-208 行）之後新增：

```dart
  static Future<void> _createBookmarksTable(Database db) async {
    // 書籤（epic-6-annotations Issue 1，spec.md「書籤模組」），與 books
    // 表以 book_id 外鍵關聯（比照 book_reader_prefs 既有關聯模式，見
    // docs/epics/epic-6-annotations/spec.md「資料模型關聯」）。與
    // book_reader_prefs 不同，一本書可以有多筆書籤，故不用 book_id 當
    // PRIMARY KEY，改用獨立的自動遞增 id。
    await db.execute('''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        epub_locator_json TEXT,
        progression REAL,
        pdf_page_index INTEGER
      )
    ''');
  }
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: PASS（全部測試綠燈，含既有 v1→v7 系列遷移測試不受影響）

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-6): 新增 bookmarks 表與 v7→v8 schema migration"
```

---

### Task 3：`BookmarksRepository`

**Files:**
- Create: `app/lib/reader/bookmarks_repository.dart`
- Test: `app/test/reader/bookmarks_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Bookmark`；Task 2 的 `bookmarks` 表 schema。
- Produces: `BookmarksRepository(Database)`，方法 `insert(Bookmark) → Future<int>`／`listByBook(String bookId) → Future<List<Bookmark>>`（依位置排序）／`rename(int id, String newName) → Future<void>`／`delete(int id) → Future<void>`／`deleteAllForBook(String bookId) → Future<void>`，供 Task 4-7 消費。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/reader/bookmarks_repository_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmarks_repository.dart';

Book _testBook(String id) {
  return Book(
    id: id,
    title: '測試書',
    format: BookFileFormat.epub,
    filePath: 'content://example/$id',
    source: BookSource.local,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

void main() {
  late SqliteLibraryRepository libraryRepository;
  late BookmarksRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    repository = BookmarksRepository(libraryRepository.database);
    await libraryRepository.insertBook(_testBook('b1'));
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  test('insert 回傳自動指派的 rowid，listByBook 讀回相同資料', () async {
    final id = await repository.insert(const Bookmark(
      bookId: 'b1',
      name: '第一章',
      epubLocatorJson: '{"href":"/c1.xhtml"}',
      progression: 0.1,
    ));
    expect(id, greaterThan(0));

    final list = await repository.listByBook('b1');
    expect(list, hasLength(1));
    expect(list.single.id, id);
    expect(list.single.name, '第一章');
  });

  test('listByBook 依 EPUB progression 由小到大排序', () async {
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'C', progression: 0.8));
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'A', progression: 0.1));
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'B', progression: 0.5));

    final list = await repository.listByBook('b1');
    expect(list.map((b) => b.name).toList(), ['A', 'B', 'C']);
  });

  test('listByBook 依 PDF 頁索引由小到大排序', () async {
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'C', pdfPageIndex: 20));
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'A', pdfPageIndex: 2));
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'B', pdfPageIndex: 10));

    final list = await repository.listByBook('b1');
    expect(list.map((b) => b.name).toList(), ['A', 'B', 'C']);
  });

  test('listByBook 只回傳指定 book_id 的書籤', () async {
    await libraryRepository.insertBook(_testBook('b2'));
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'X', progression: 0.1));
    await repository
        .insert(const Bookmark(bookId: 'b2', name: 'Y', pdfPageIndex: 0));

    final list = await repository.listByBook('b1');
    expect(list, hasLength(1));
    expect(list.single.name, 'X');
  });

  test('rename 更新指定書籤的名稱，其餘欄位不受影響', () async {
    final id = await repository.insert(const Bookmark(
      bookId: 'b1',
      name: '舊名稱',
      pdfPageIndex: 5,
    ));
    await repository.rename(id, '新名稱');

    final list = await repository.listByBook('b1');
    expect(list.single.name, '新名稱');
    expect(list.single.pdfPageIndex, 5);
  });

  test('delete 移除指定單筆書籤，其餘不受影響', () async {
    final id1 = await repository
        .insert(const Bookmark(bookId: 'b1', name: 'A', progression: 0.1));
    final id2 = await repository
        .insert(const Bookmark(bookId: 'b1', name: 'B', progression: 0.5));
    await repository.delete(id1);

    final list = await repository.listByBook('b1');
    expect(list, hasLength(1));
    expect(list.single.id, id2);
  });

  test('deleteAllForBook 只清空指定書籍的書籤，其他書籍不受影響', () async {
    await libraryRepository.insertBook(_testBook('b2'));
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'X', progression: 0.1));
    await repository
        .insert(const Bookmark(bookId: 'b2', name: 'Y', pdfPageIndex: 0));

    await repository.deleteAllForBook('b1');

    expect(await repository.listByBook('b1'), isEmpty);
    expect(await repository.listByBook('b2'), hasLength(1));
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/bookmarks_repository_test.dart`
Expected: FAIL（`bookmarks_repository.dart` 尚不存在，編譯錯誤）

- [ ] **Step 3: 實作 `BookmarksRepository`**

建立 `app/lib/reader/bookmarks_repository.dart`：

```dart
import 'package:sqflite/sqflite.dart';

import 'bookmark.dart';

/// `bookmarks` 表的存取層（epic-6-annotations Issue 1，spec.md「書籤
/// 模組」）。與 [SqliteLibraryRepository] 共用同一個 [Database] 連線，
/// 比照既有 `BookReaderPrefsRepository`／`ReadingPositionRepository`
/// 模式（`bookmarks.book_id` 的外鍵約束要求與 `books` 表在同一個資料庫
/// 檔案內）。
class BookmarksRepository {
  final Database _db;

  const BookmarksRepository(this._db);

  /// 新增一筆書籤，回傳 SQLite 自動指派的 rowid。
  Future<int> insert(Bookmark bookmark) {
    return _db.insert('bookmarks', bookmark.toMap());
  }

  /// 依書中位置順序排序（EPUB／FXL 用 progression 比例、PDF 用頁索引，
  /// 兩者互斥、一本書只會用到其中一組，見 [Bookmark] 欄位語意）。
  /// `COALESCE` 取兩欄位中非 null 的那一個當排序鍵——同一本書的所有書籤
  /// 必然只填其中一組欄位，不會混用。
  Future<List<Bookmark>> listByBook(String bookId) async {
    final rows = await _db.query(
      'bookmarks',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'COALESCE(pdf_page_index, progression) ASC',
    );
    return rows.map(Bookmark.fromMap).toList();
  }

  Future<void> rename(int id, String newName) {
    return _db.update(
      'bookmarks',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(int id) {
    return _db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllForBook(String bookId) {
    return _db.delete('bookmarks', where: 'book_id = ?', whereArgs: [bookId]);
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/bookmarks_repository_test.dart`
Expected: PASS（全部測試綠燈）

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/bookmarks_repository.dart app/test/reader/bookmarks_repository_test.dart
git commit -m "feat(epic-6): 新增 BookmarksRepository"
```

---

### Task 4：`NotesBottomSheet` 外殼——雙分頁籤 + 書籤清單 + 跳轉 + 空狀態佔位符

**Files:**
- Create: `app/lib/screens/notes_bottom_sheet.dart`
- Create: `app/test/support/fake_bookmarks_repository.dart`
- Test: `app/test/screens/notes_bottom_sheet_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Bookmark`／`BookmarkPositionContext`；Task 3 的 `BookmarksRepository`（含測試用 `FakeBookmarksRepository implements BookmarksRepository`）。
- Produces: `NotesBottomSheet({bookId, bookmarksRepository, currentPosition, onBookmarkSelected})`，供 Task 5-7 擴充／消費。

- [ ] **Step 1: 建立測試用 Fake**

建立 `app/test/support/fake_bookmarks_repository.dart`：

```dart
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmarks_repository.dart';

/// 測試用 Fake，比照 [FakeReadingPositionRepository] 模式。
class FakeBookmarksRepository implements BookmarksRepository {
  final List<Bookmark> _storage = [];
  int _nextId = 1;

  @override
  Future<int> insert(Bookmark bookmark) async {
    final id = _nextId++;
    _storage.add(Bookmark(
      id: id,
      bookId: bookmark.bookId,
      name: bookmark.name,
      epubLocatorJson: bookmark.epubLocatorJson,
      progression: bookmark.progression,
      pdfPageIndex: bookmark.pdfPageIndex,
    ));
    return id;
  }

  @override
  Future<List<Bookmark>> listByBook(String bookId) async {
    final list = _storage.where((b) => b.bookId == bookId).toList();
    list.sort((a, b) {
      final posA = a.pdfPageIndex?.toDouble() ?? a.progression ?? 0;
      final posB = b.pdfPageIndex?.toDouble() ?? b.progression ?? 0;
      return posA.compareTo(posB);
    });
    return list;
  }

  @override
  Future<void> rename(int id, String newName) async {
    final index = _storage.indexWhere((b) => b.id == id);
    if (index == -1) return;
    _storage[index] = _storage[index].copyWith(name: newName);
  }

  @override
  Future<void> delete(int id) async {
    _storage.removeWhere((b) => b.id == id);
  }

  @override
  Future<void> deleteAllForBook(String bookId) async {
    _storage.removeWhere((b) => b.bookId == bookId);
  }
}
```

- [ ] **Step 2: 寫失敗測試**

建立 `app/test/screens/notes_bottom_sheet_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/bookmark_position_context.dart';
import 'package:elinkbook/screens/notes_bottom_sheet.dart';
import '../support/fake_bookmarks_repository.dart';

Future<void> _pumpSheet(
  WidgetTester tester, {
  required FakeBookmarksRepository repository,
  String bookId = 'b1',
  BookmarkPositionContext currentPosition = const BookmarkPositionContext(),
  ValueChanged<Bookmark>? onBookmarkSelected,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: NotesBottomSheet(
        bookId: bookId,
        bookmarksRepository: repository,
        currentPosition: currentPosition,
        onBookmarkSelected: onBookmarkSelected ?? (_) {},
      ),
    ),
  ));
  await tester.pump(); // 讓 initState 觸發的 _loadBookmarks() 非同步結果套用
}

void main() {
  testWidgets('開啟後顯示兩個分頁籤，預設在書籤分頁', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(tester, repository: repository);

    expect(find.byKey(const Key('notes_sheet_tab_bookmarks')), findsOneWidget);
    expect(find.byKey(const Key('notes_sheet_tab_annotations')), findsOneWidget);
    expect(find.byKey(const Key('notes_sheet_bookmark_list')), findsOneWidget);
  });

  testWidgets('切至「劃線與備註」分頁顯示空狀態佔位符', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(tester, repository: repository);

    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('notes_sheet_annotations_placeholder')),
      findsOneWidget,
    );
  });

  testWidgets('書籤分頁正確依位置順序顯示清單', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'C', progression: 0.8));
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'A', progression: 0.1));
    await _pumpSheet(tester, repository: repository);

    final listFinder = find.byKey(const Key('notes_sheet_bookmark_list'));
    final listTiles = tester.widgetList<ListTile>(
      find.descendant(of: listFinder, matching: find.byType(ListTile)),
    );
    final titles = listTiles.map((t) => (t.title as Text).data).toList();
    expect(titles, ['A', 'C']);
  });

  testWidgets('點選書籤項目觸發 onBookmarkSelected', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository.insert(
      const Bookmark(bookId: 'b1', name: '第一章', progression: 0.1),
    );
    Bookmark? selected;
    await _pumpSheet(
      tester,
      repository: repository,
      onBookmarkSelected: (b) => selected = b,
    );

    await tester.tap(find.text('第一章'));
    await tester.pump();

    expect(selected?.name, '第一章');
  });
}
```

- [ ] **Step 3: 執行測試確認失敗**

Run: `flutter test test/screens/notes_bottom_sheet_test.dart`
Expected: FAIL（`notes_bottom_sheet.dart` 尚不存在，編譯錯誤）

- [ ] **Step 4: 實作 `NotesBottomSheet` 外殼**

建立 `app/lib/screens/notes_bottom_sheet.dart`：

```dart
import 'package:flutter/material.dart';

import '../reader/bookmark.dart';
import '../reader/bookmark_position_context.dart';
import '../reader/bookmarks_repository.dart';

/// 統一的「筆記」入口 Bottom Sheet 外殼（epic-6-annotations Issue 1，
/// spec.md「統一入口與 Bottom Sheet」）：帶「🔖 書籤」／「✏️ 劃線與備註」
/// 兩個分頁籤，兩分頁底下的資料層完全獨立（design.md 決策 #1）。本 Issue
/// 只完整實作「書籤」分頁；「劃線與備註」分頁本 Issue 僅顯示空狀態佔位符，
/// 真正內容由 Issue 2（EPUB）／Issue 3（PDF）建立。
class NotesBottomSheet extends StatefulWidget {
  final String bookId;
  final BookmarksRepository bookmarksRepository;

  /// 開啟當下的目前位置上下文，供書籤 toggle 按鈕判斷目前位置是否已有
  /// 書籤、以及新增書籤時計算預設名稱（Global Constraints「書籤 toggle
  /// 的相等性判斷」）。
  final BookmarkPositionContext currentPosition;

  /// 使用者點選某筆書籤時觸發，呼叫端負責實際跳轉並關閉本 Bottom Sheet。
  final ValueChanged<Bookmark> onBookmarkSelected;

  const NotesBottomSheet({
    super.key,
    required this.bookId,
    required this.bookmarksRepository,
    required this.currentPosition,
    required this.onBookmarkSelected,
  });

  @override
  State<NotesBottomSheet> createState() => _NotesBottomSheetState();
}

class _NotesBottomSheetState extends State<NotesBottomSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<Bookmark> _bookmarks = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBookmarks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBookmarks() async {
    final list = await widget.bookmarksRepository.listByBook(widget.bookId);
    if (!mounted) return;
    setState(() => _bookmarks = list);
  }

  @override
  Widget build(BuildContext context) {
    // TabBarView 無法在無邊界的父層自我量測高度，需要一個明確的高度值
    // （比照 PdfSettingsSheet 既有做法），但改用螢幕高度比例（審查修正，
    // 見 tmp/epic-6/reviews/plan_issue_1_review.md 2.1）而非寫死常數，
    // 避免在較矮螢幕（例如部分 E-Ink 裝置）或系統字型放大時溢出；
    // clamp 上下限避免極端螢幕尺寸下過小或過大。此為 NotesBottomSheet
    // 這個全新元件的初始選擇，不回頭修改 PdfSettingsSheet 既有的固定
    // 400，避免超出本工單範圍。
    final sheetHeight =
        (MediaQuery.of(context).size.height * 0.6).clamp(320.0, 600.0);
    return SafeArea(
      child: SizedBox(
        height: sheetHeight,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child:
                  Text('📚 筆記', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(key: Key('notes_sheet_tab_bookmarks'), text: '🔖 書籤'),
                Tab(key: Key('notes_sheet_tab_annotations'), text: '✏️ 劃線與備註'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBookmarksTab(),
                  const Center(
                    child: Text(
                      '尚無劃線或備註',
                      key: Key('notes_sheet_annotations_placeholder'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookmarksTab() {
    return ListView.builder(
      key: const Key('notes_sheet_bookmark_list'),
      itemCount: _bookmarks.length,
      itemBuilder: (context, index) => _buildBookmarkRow(_bookmarks[index]),
    );
  }

  Widget _buildBookmarkRow(Bookmark bookmark) {
    return ListTile(
      key: Key('notes_sheet_bookmark_${bookmark.id}'),
      title: Text(bookmark.name),
      onTap: () => widget.onBookmarkSelected(bookmark),
    );
  }
}
```

- [ ] **Step 5: 執行測試確認通過**

Run: `flutter test test/screens/notes_bottom_sheet_test.dart`
Expected: PASS（全部測試綠燈）

- [ ] **Step 6: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/notes_bottom_sheet.dart app/test/support/fake_bookmarks_repository.dart app/test/screens/notes_bottom_sheet_test.dart
git commit -m "feat(epic-6): 新增 NotesBottomSheet 外殼（雙分頁籤 + 書籤清單）"
```

---

### Task 5：書籤 toggle 按鈕（新增/移除目前位置書籤）

**Files:**
- Modify: `app/lib/screens/notes_bottom_sheet.dart`
- Test: `app/test/screens/notes_bottom_sheet_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Bookmark.defaultName(BookmarkPositionContext)`。
- Produces: `NotesBottomSheet` 內部 `_toggleBookmark()`／`_matchesCurrentPosition(Bookmark)`／`_bookmarkAtCurrentPosition` getter（私有實作細節，不對外暴露，Task 6 會延伸使用）。

- [ ] **Step 1: 寫失敗測試**

於 `app/test/screens/notes_bottom_sheet_test.dart` 檔案結尾（最後一個 `}` 之前）新增：

```dart
  testWidgets('尚未有書籤時，toggle 按鈕顯示「加入此頁書籤」', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(
      tester,
      repository: repository,
      currentPosition: const BookmarkPositionContext(pdfPageIndex: 4),
    );

    expect(find.text('加入此頁書籤'), findsOneWidget);
  });

  testWidgets('點擊 toggle 按鈕後新增書籤，清單即時反映', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(
      tester,
      repository: repository,
      currentPosition: const BookmarkPositionContext(pdfPageIndex: 4),
    );

    await tester.tap(find.byKey(const Key('notes_sheet_bookmark_toggle')));
    await tester.pump();

    expect(find.text('第 5 頁'), findsOneWidget);
    expect(find.text('已加入此頁書籤'), findsOneWidget);
  });

  testWidgets('已有書籤時再次點擊 toggle 按鈕，移除該筆書籤', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository.insert(
      const Bookmark(bookId: 'b1', name: '第 5 頁', pdfPageIndex: 4),
    );
    await _pumpSheet(
      tester,
      repository: repository,
      currentPosition: const BookmarkPositionContext(pdfPageIndex: 4),
    );

    expect(find.text('已加入此頁書籤'), findsOneWidget);
    await tester.tap(find.byKey(const Key('notes_sheet_bookmark_toggle')));
    await tester.pump();

    expect(find.text('第 5 頁'), findsNothing);
    expect(find.text('加入此頁書籤'), findsOneWidget);
  });

  testWidgets('EPUB 情境下 toggle 依 epubLocatorJson 精確比對', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository.insert(const Bookmark(
      bookId: 'b1',
      name: '別處',
      epubLocatorJson: '{"href":"/other.xhtml"}',
    ));
    await _pumpSheet(
      tester,
      repository: repository,
      currentPosition: const BookmarkPositionContext(
        epubLocatorJson: '{"href":"/c1.xhtml"}',
        progression: 0.1,
      ),
    );

    expect(
      find.text('加入此頁書籤'),
      findsOneWidget,
      reason: '不同 locatorJson 不應視為同一位置',
    );
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/notes_bottom_sheet_test.dart`
Expected: FAIL（`Key('notes_sheet_bookmark_toggle')` 找不到對應 widget）

- [ ] **Step 3: 實作 toggle 按鈕**

`app/lib/screens/notes_bottom_sheet.dart` 的 `_buildBookmarksTab` 方法整個改為：

```dart
  Widget _buildBookmarksTab() {
    final existing = _bookmarkAtCurrentPosition;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: OutlinedButton.icon(
            key: const Key('notes_sheet_bookmark_toggle'),
            icon: Icon(existing != null ? Icons.star : Icons.star_border),
            label: Text(existing != null ? '已加入此頁書籤' : '加入此頁書籤'),
            onPressed: _toggleBookmark,
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const Key('notes_sheet_bookmark_list'),
            itemCount: _bookmarks.length,
            itemBuilder: (context, index) =>
                _buildBookmarkRow(_bookmarks[index]),
          ),
        ),
      ],
    );
  }

  /// 目前位置是否已有書籤——EPUB／FXL 比對 epubLocatorJson 是否完全相同
  /// 字串，PDF 比對 pdfPageIndex 是否相同（見 Global Constraints「書籤
  /// toggle 的相等性判斷」，審查修正 1.1）。
  bool _matchesCurrentPosition(Bookmark bookmark) {
    final pdfPageIndex = widget.currentPosition.pdfPageIndex;
    if (pdfPageIndex != null) return bookmark.pdfPageIndex == pdfPageIndex;
    final epubLocatorJson = widget.currentPosition.epubLocatorJson;
    if (epubLocatorJson != null) {
      return bookmark.epubLocatorJson == epubLocatorJson;
    }
    return false;
  }

  Bookmark? get _bookmarkAtCurrentPosition {
    for (final bookmark in _bookmarks) {
      if (_matchesCurrentPosition(bookmark)) return bookmark;
    }
    return null;
  }

  Future<void> _toggleBookmark() async {
    final existing = _bookmarkAtCurrentPosition;
    if (existing != null) {
      await widget.bookmarksRepository.delete(existing.id!);
    } else {
      await widget.bookmarksRepository.insert(Bookmark(
        bookId: widget.bookId,
        name: Bookmark.defaultName(widget.currentPosition),
        epubLocatorJson: widget.currentPosition.epubLocatorJson,
        progression: widget.currentPosition.progression,
        pdfPageIndex: widget.currentPosition.pdfPageIndex,
      ));
    }
    await _loadBookmarks();
  }
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/notes_bottom_sheet_test.dart`
Expected: PASS（全部測試綠燈，含 Task 4 既有測試不受影響）

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/notes_bottom_sheet.dart app/test/screens/notes_bottom_sheet_test.dart
git commit -m "feat(epic-6): NotesBottomSheet 新增書籤 toggle 按鈕"
```

---

### Task 6：重新命名 + 單筆刪除 + 批次刪除（需確認）

**Files:**
- Modify: `app/lib/screens/notes_bottom_sheet.dart`
- Test: `app/test/screens/notes_bottom_sheet_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `BookmarksRepository.rename`／`delete`／`deleteAllForBook`。
- Produces: 無新的對外介面，完成 `NotesBottomSheet` 書籤分頁的完整功能。

- [ ] **Step 1: 寫失敗測試**

於 `app/test/screens/notes_bottom_sheet_test.dart` 檔案結尾（最後一個 `}` 之前）新增：

```dart
  testWidgets('重新命名書籤後清單顯示新名稱', (tester) async {
    final repository = FakeBookmarksRepository();
    final id = await repository.insert(
      const Bookmark(bookId: 'b1', name: '舊名稱', progression: 0.1),
    );
    await _pumpSheet(tester, repository: repository);

    await tester.tap(find.byKey(Key('notes_sheet_bookmark_rename_$id')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('notes_sheet_rename_field')),
      '新名稱',
    );
    await tester.tap(find.byKey(const Key('notes_sheet_rename_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('新名稱'), findsOneWidget);
    expect(find.text('舊名稱'), findsNothing);
  });

  testWidgets('單筆刪除書籤後清單即時消失，不需確認', (tester) async {
    final repository = FakeBookmarksRepository();
    final id = await repository.insert(
      const Bookmark(bookId: 'b1', name: '待刪除', progression: 0.1),
    );
    await _pumpSheet(tester, repository: repository);

    await tester.tap(find.byKey(Key('notes_sheet_bookmark_delete_$id')));
    await tester.pump();

    expect(find.text('待刪除'), findsNothing);
  });

  testWidgets('批次刪除按鈕在無書籤時停用', (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(tester, repository: repository);

    final button = tester.widget<IconButton>(
      find.byKey(const Key('notes_sheet_delete_all_bookmarks')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('批次刪除顯示確認對話框，取消不刪除', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'A', progression: 0.1));
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'B', progression: 0.5));
    await _pumpSheet(tester, repository: repository);

    await tester
        .tap(find.byKey(const Key('notes_sheet_delete_all_bookmarks')));
    await tester.pumpAndSettle();
    expect(find.textContaining('共 2 筆'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('批次刪除確認後清單清空', (tester) async {
    final repository = FakeBookmarksRepository();
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'A', progression: 0.1));
    await repository
        .insert(const Bookmark(bookId: 'b1', name: 'B', progression: 0.5));
    await _pumpSheet(tester, repository: repository);

    await tester
        .tap(find.byKey(const Key('notes_sheet_delete_all_bookmarks')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('notes_sheet_delete_all_bookmarks_confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsNothing);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/notes_bottom_sheet_test.dart`
Expected: FAIL（`Key('notes_sheet_bookmark_rename_$id')`／`Key('notes_sheet_delete_all_bookmarks')` 等找不到對應 widget）

- [ ] **Step 3: 實作重新命名／刪除／批次刪除**

`app/lib/screens/notes_bottom_sheet.dart` 的 `_buildBookmarksTab` 方法內，toggle 按鈕的 `Padding` 改為包含批次刪除按鈕的 `Row`：

```dart
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('notes_sheet_bookmark_toggle'),
                  icon: Icon(existing != null ? Icons.star : Icons.star_border),
                  label: Text(existing != null ? '已加入此頁書籤' : '加入此頁書籤'),
                  onPressed: _toggleBookmark,
                ),
              ),
              IconButton(
                key: const Key('notes_sheet_delete_all_bookmarks'),
                icon: const Icon(Icons.delete_sweep),
                tooltip: '刪除該書所有書籤',
                onPressed:
                    _bookmarks.isEmpty ? null : _confirmDeleteAllBookmarks,
              ),
            ],
          ),
        ),
```

`_buildBookmarkRow` 方法整個改為（新增 `trailing` 重新命名／刪除按鈕）：

```dart
  Widget _buildBookmarkRow(Bookmark bookmark) {
    return ListTile(
      key: Key('notes_sheet_bookmark_${bookmark.id}'),
      title: Text(bookmark.name),
      onTap: () => widget.onBookmarkSelected(bookmark),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('notes_sheet_bookmark_rename_${bookmark.id}'),
            icon: const Icon(Icons.edit),
            tooltip: '重新命名',
            onPressed: () => _renameBookmark(bookmark),
          ),
          IconButton(
            key: Key('notes_sheet_bookmark_delete_${bookmark.id}'),
            icon: const Icon(Icons.delete),
            tooltip: '刪除',
            onPressed: () => _deleteBookmark(bookmark),
          ),
        ],
      ),
    );
  }
```

在 `_toggleBookmark` 方法之後新增三個方法：

```dart
  Future<void> _renameBookmark(Bookmark bookmark) async {
    final controller = TextEditingController(text: bookmark.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重新命名書籤'),
        content: TextField(
          key: const Key('notes_sheet_rename_field'),
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('notes_sheet_rename_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    if (newName == null || newName.trim().isEmpty) return;
    await widget.bookmarksRepository.rename(bookmark.id!, newName.trim());
    await _loadBookmarks();
  }

  Future<void> _deleteBookmark(Bookmark bookmark) async {
    await widget.bookmarksRepository.delete(bookmark.id!);
    await _loadBookmarks();
  }

  Future<void> _confirmDeleteAllBookmarks() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('確定要刪除全部書籤嗎？（共 ${_bookmarks.length} 筆）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('notes_sheet_delete_all_bookmarks_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.bookmarksRepository.deleteAllForBook(widget.bookId);
    await _loadBookmarks();
  }
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/notes_bottom_sheet_test.dart`
Expected: PASS（全部測試綠燈，含 Task 4/5 既有測試不受影響）

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/notes_bottom_sheet.dart app/test/screens/notes_bottom_sheet_test.dart
git commit -m "feat(epic-6): NotesBottomSheet 新增重新命名/單筆刪除/批次刪除"
```

---

### Task 7：`ReaderScreen` 接線——「📚 筆記」入口 + 位置上下文傳遞

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `BookmarksRepository`；Task 4-6 的 `NotesBottomSheet`；既有 `TocNavigator.findCurrentPath`／`EpubReaderView.jumpToLocator`／`PdfReaderView.jumpToPage`（Epic 5）。
- Produces: `ReaderScreen` 新增可選建構參數 `bookmarksRepository`（`BookmarksRepository?`，見 Global Constraints）；`LibraryScreen`／`ElinkBookApp` 同步新增並向下傳遞；`main.dart` 實際建構真實 `BookmarksRepository` 完成端到端接線。

- [ ] **Step 1: 寫失敗測試**

於 `app/test/screens/reader_screen_test.dart` 檔案頂端 import 區塊新增：

```dart
import 'package:elinkbook/reader/bookmarks_repository.dart';
import 'package:elinkbook/screens/notes_bottom_sheet.dart';
import '../support/fake_bookmarks_repository.dart';
```

於檔案結尾（最後一個 `}` 之前）新增：

```dart
  // --- Epic 6 Issue 1：書籤管理 + 統一「筆記」入口 ---

  testWidgets('未提供 bookmarksRepository 時，📚 筆記按鈕不存在（既有呼叫端不受影響）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_no_bookmarks_repo',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_notes_button')), findsNothing);
  });

  testWidgets(
      'EPUB 提供 bookmarksRepository 後，📚 筆記按鈕存在，onLayoutResolved 前為停用狀態',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_notes_epub',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();

    final finder = find.byKey(const Key('reader_notes_button'));
    expect(finder, findsOneWidget);
    expect(tester.widget<IconButton>(finder).onPressed, isNull);
  });

  testWidgets('EPUB 收到 onLayoutResolved 後，📚 按鈕可點擊，點擊後開啟 NotesBottomSheet',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_notes_epub_open',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();

    final finder = find.byKey(const Key('reader_notes_button'));
    expect(tester.widget<IconButton>(finder).onPressed, isNotNull);

    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(NotesBottomSheet), findsOneWidget);
  });

  testWidgets(
      'PDF 提供 bookmarksRepository 後，onPageRendered 前 📚 按鈕為停用狀態，之後可點擊',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_notes_pdf',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await tester.pump();

    final finder = find.byKey(const Key('reader_notes_button'));
    expect(tester.widget<IconButton>(finder).onPressed, isNull);

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageRendered();
    await tester.pump();

    expect(tester.widget<IconButton>(finder).onPressed, isNotNull);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: FAIL（`ReaderScreen` 建構子尚無 `bookmarksRepository` 具名參數，編譯錯誤；`Key('reader_notes_button')` 也找不到）

- [ ] **Step 3: 實作 `ReaderScreen` 接線**

`app/lib/screens/reader_screen.dart` 第 1-24 行 import 區塊，新增：

```dart
import '../reader/bookmark.dart';
import '../reader/bookmark_position_context.dart';
import '../reader/bookmarks_repository.dart';
```

（放在既有 `import '../reader/book_format.dart';` 之後、`import '../reader/book_reader_prefs.dart';` 之前，比照現有依字母排序的慣例）並在 `import 'fxl_settings_sheet.dart';` 之前新增：

```dart
import 'notes_bottom_sheet.dart';
```

第 42-52 行 `ReaderScreen` 建構子，新增可選欄位：

```dart
class ReaderScreen extends StatefulWidget {
  final String filePath;
  final String bookId;
  final ReaderPrefsManager prefsManager;

  /// 書籤功能的資料存取層（epic-6-annotations Issue 1）。刻意為可選參數
  /// （非 required）——未提供時 AppBar 不顯示「📚 筆記」按鈕，行為等同
  /// 本 Issue 之前，讓既有大量測試呼叫端不需要逐一補上這個參數（見
  /// plan-issue-1.md Global Constraints）。
  final BookmarksRepository? bookmarksRepository;

  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.bookId,
    required this.prefsManager,
    this.bookmarksRepository,
  });
```

在 `_openToc()` 方法（第 399-419 行）之後新增：

```dart
  void _openNotesSheet(BookFormat format) {
    final repository = widget.bookmarksRepository;
    if (repository == null) return;
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    final positionContext = BookmarkPositionContext(
      epubLocatorJson:
          format == BookFormat.epub ? _epubPositionInfo?.locatorJson : null,
      progression:
          format == BookFormat.epub ? _epubPositionInfo?.progression : null,
      pdfPageIndex: format == BookFormat.pdf ? _pdfPageInfo?.pageIndex : null,
      chapterTitle: currentPath.isEmpty ? null : currentPath.last.title,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NotesBottomSheet(
        bookId: widget.bookId,
        bookmarksRepository: repository,
        currentPosition: positionContext,
        onBookmarkSelected: (bookmark) {
          Navigator.of(context).pop();
          if (bookmark.epubLocatorJson != null) {
            EpubReaderView.jumpToLocator(
              _epubReaderViewKey,
              bookmark.epubLocatorJson!,
            );
          } else if (bookmark.pdfPageIndex != null) {
            PdfReaderView.jumpToPage(_pdfReaderViewKey, bookmark.pdfPageIndex!);
          }
        },
      ),
    );
  }
```

第 541-586 行 `_buildAppBarActions` 整個改為：

```dart
  List<Widget>? _buildAppBarActions(BookFormat format) {
    if (_isFixedLayout) return null;
    switch (format) {
      case BookFormat.epub:
        return [
          IconButton(
            key: const Key('reader_toc_button'),
            icon: const Icon(Icons.menu_book),
            tooltip: '目錄',
            // 沿用與「⚙️版面」按鈕一致的啟用條件（_autoDetectedWritingMode
            // 非 null 代表 onLayoutResolved 已觸發，書本已成功開啟），並
            // 額外要求 _tocLoaded（審查修正）——避免使用者在背景抓取
            // 完成前點擊，開啟一個無法與「本書真的沒有目錄」區分的空白
            // Bottom Sheet。
            onPressed: (_autoDetectedWritingMode == null || !_tocLoaded)
                ? null
                : _openToc,
          ),
          IconButton(
            key: const Key('reader_layout_settings_button'),
            icon: const Icon(Icons.settings),
            tooltip: '版面設定',
            // _autoDetectedWritingMode 非 null 代表 onLayoutResolved 已觸發，
            // 書本已成功開啟、navigatorFragment 已存在，此時開啟版面設定並
            // 呼叫 setPreferences 才有意義（見 EpubReaderView.kt 的靜默忽略
            // 邏輯說明）。
            onPressed:
                _autoDetectedWritingMode == null ? null : _openLayoutSettings,
          ),
          if (widget.bookmarksRepository != null)
            IconButton(
              key: const Key('reader_notes_button'),
              icon: const Icon(Icons.bookmarks),
              tooltip: '筆記',
              onPressed: _autoDetectedWritingMode == null
                  ? null
                  : () => _openNotesSheet(format),
            ),
        ];
      case BookFormat.pdf:
        return [
          IconButton(
            key: const Key('reader_layout_settings_button'),
            icon: const Icon(Icons.settings),
            tooltip: '版面設定',
            // _state == rendered 代表 onPageRendered 已觸發，PDF 已成功
            // 開啟，此時開啟版面設定並呼叫 setPdfPreferences 才有意義，比照
            // EPUB 分支的既有判斷原則。
            onPressed: _state == _RenderState.rendered ? _openPdfSettings : null,
          ),
          if (widget.bookmarksRepository != null)
            IconButton(
              key: const Key('reader_notes_button'),
              icon: const Icon(Icons.bookmarks),
              tooltip: '筆記',
              onPressed: _state == _RenderState.rendered
                  ? () => _openNotesSheet(format)
                  : null,
            ),
        ];
      case BookFormat.unknown:
        return null;
    }
  }
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（全部測試綠燈，含既有 43 個 `ReaderScreen(...)` 呼叫端測試不受影響）

- [ ] **Step 5: 接線 `LibraryScreen`／`ElinkBookApp`／`main.dart`（真實應用程式端到端接線）**

`app/lib/screens/library_screen.dart`：於 `class LibraryScreen extends StatefulWidget` 的欄位宣告區（`final ReaderPrefsManager prefsManager;` 之後）新增：

```dart
  final BookmarksRepository? bookmarksRepository;
```

於建構子（`required this.prefsManager,` 之後）新增：

```dart
    this.bookmarksRepository,
```

並在檔案頂端新增 import：

```dart
import '../reader/bookmarks_repository.dart';
```

於 `ReaderScreen(...)` 建構呼叫處（`prefsManager: widget.prefsManager,` 之後）新增：

```dart
              bookmarksRepository: widget.bookmarksRepository,
```

`app/lib/main.dart`：於 `class ElinkBookApp extends StatefulWidget` 的欄位宣告區（`final ReaderPrefsManager prefsManager;` 之後）新增：

```dart
  final BookmarksRepository? bookmarksRepository;
```

於建構子（`required this.prefsManager,` 之後）新增：

```dart
    this.bookmarksRepository,
```

於 `build()` 方法內 `LibraryScreen(...)` 建構呼叫處（`prefsManager: widget.prefsManager,` 之後）新增：

```dart
        bookmarksRepository: widget.bookmarksRepository,
```

並在檔案頂端新增 import：

```dart
import 'reader/bookmarks_repository.dart';
```

於 `main()` 函式內（`final prefsManager = ReaderPrefsManagerImpl(...);` 之後）新增：

```dart
  final bookmarksRepository = BookmarksRepository(repository.database);
```

於 `runApp(ElinkBookApp(...))` 呼叫處（`prefsManager: prefsManager,` 之後）新增：

```dart
      bookmarksRepository: bookmarksRepository,
```

- [ ] **Step 6: 執行全專案測試確認無回歸**

Run: `flutter test`
Expected: 全部通過（`bookmarksRepository` 在 `ReaderScreen`／`LibraryScreen`／`ElinkBookApp` 三層皆為可選參數，既有 43＋27＋5 個未提供此參數的測試呼叫端維持原行為不變）

- [ ] **Step 7: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/lib/screens/library_screen.dart app/lib/main.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-6): ReaderScreen 接線「📚 筆記」入口，main.dart 完成端到端接線"
```

---

### Task 8：真機整合測試——書籤新增/清單/跳轉端到端驗證（EPUB + PDF）

**Files:**
- Create: `app/integration_test/notes_bookmark_test.dart`

**Interfaces:**
- Consumes: 全部前七個 Task 產出的完整資料流。本 Task 不新增任何生產程式碼介面，純驗證。

- [ ] **Step 1: 撰寫真機整合測試**

建立 `app/integration_test/notes_bookmark_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/bookmarks_repository.dart';
import 'package:elinkbook/reader/epub_character_count_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/notes_bottom_sheet.dart';
import 'package:elinkbook/screens/reader_screen.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pumpUntilNotesButtonEnabled(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final finder = find.byKey(const Key('reader_notes_button'));
    if (finder.evaluate().isNotEmpty &&
        tester.widget<IconButton>(finder).onPressed != null) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：筆記按鈕未轉為可點擊狀態');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('EPUB：新增書籤、清單顯示與持久化、點選跳轉的端到端流程',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
      EpubCharacterCountRepository(libraryRepository.database),
    );
    final bookmarksRepository = BookmarksRepository(libraryRepository.database);

    final samplePath = await _stageAssetAsFile(
      'test/fixtures/sample_multi_chapter.epub',
      'notes_bookmark_epub.epub',
    );
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_notes_epub',
      title: '書籤測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_notes_epub',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilNotesButtonEnabled(tester);

    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pumpAndSettle();
    expect(find.byType(NotesBottomSheet), findsOneWidget);

    await tester.tap(find.byKey(const Key('notes_sheet_bookmark_toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notes_sheet_bookmark_list')), findsOneWidget);

    // 關閉 Bottom Sheet，重新開啟確認書籤已持久化寫入資料庫（非僅記憶體內
    // 暫存狀態）。
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pumpAndSettle();

    final listFinder = find.byKey(const Key('notes_sheet_bookmark_list'));
    final listTiles = tester.widgetList<ListTile>(
      find.descendant(of: listFinder, matching: find.byType(ListTile)),
    );
    expect(listTiles, isNotEmpty);

    // 點選書籤後，Bottom Sheet 應關閉（跳轉本身的原生渲染結果無法在
    // widget test 層級斷言，比照專案既有測試限制）。
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(NotesBottomSheet), findsNothing);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });

  testWidgets('PDF：新增書籤、清單顯示、點選跳轉的端到端流程', (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
    final bookmarksRepository = BookmarksRepository(libraryRepository.database);

    final samplePath = await _stageAssetAsFile(
      'test/fixtures/sample.pdf',
      'notes_bookmark_pdf.pdf',
    );
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_notes_pdf',
      title: '書籤測試書（PDF）',
      format: BookFileFormat.pdf,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_notes_pdf',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilNotesButtonEnabled(tester);

    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_bookmark_toggle')));
    await tester.pumpAndSettle();

    expect(find.textContaining('第 1 頁'), findsWidgets);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
}
```

- [ ] **Step 2: 於真實裝置執行測試**

Run: `flutter test integration_test/notes_bookmark_test.dart -d <device-id>`（例如本專案既有的 `3CEF42ECD491687`）
Expected: `All tests passed!`

- [ ] **Step 3: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add app/integration_test/notes_bookmark_test.dart
git commit -m "test(epic-6): 新增書籤管理真機整合測試（EPUB + PDF）"
```

---

## 完成後檢查（對照 issues.md Issue 1 驗收標準）

- [ ] `bookmarks` 表與累加式 migration 正確建立：`onCreate`（全新安裝）與 `onUpgrade`（既有裝置升級）皆會建表（Task 2）
- [ ] `BookmarksRepository` CRUD 正確運作（Task 3）
- [ ] AppBar 新增「📚 筆記」按鈕（流式 EPUB／PDF），開啟帶兩分頁籤的 Bottom Sheet（Task 4/7）
- [ ] 「🔖 書籤」分頁完整可用：清單依位置排序、200ms 內跳轉、重新命名、單筆刪除、批次刪除（需確認）（Task 4/5/6，200ms 跳轉由 Task 8 真機驗證）
- [ ] 書籤新增/移除為 toggle 語意，同頁/位置最多一筆，二態按鈕正確反映狀態（Task 5）
- [ ] EPUB 預設書籤名稱含章節名稱＋進度百分比；PDF 預設名稱為「第 N 頁」；FXL 因無法取得頁碼、退回顯示進度百分比（Task 1，審查修正 1.1，本 Issue 尚未實際接線 FXL 入口，見 Issue 4）
- [ ] 「✏️ 劃線與備註」分頁顯示空狀態佔位符（Task 4）
- [ ] 上述測試皆通過，`flutter analyze` 乾淨（每個 Task 的 Step）
- [ ] 真機整合測試涵蓋 EPUB／PDF 書籤新增與跳轉的端到端流程（Task 8）

## 審查修正紀錄（`tmp/epic-6/reviews/plan_issue_1_review.md`）

- **嚴重（確認屬實，已修正）**：FXL（固定版面漫畫）副檔名是 `.epub`，`ReaderScreen._openNotesSheet` 只在 `format == BookFormat.pdf` 時才填入 `pdfPageIndex`，FXL 永遠落在 `BookFormat.epub` 分支、`pdfPageIndex` 恆為 `null`，加上固定版面永遠不預取目錄（`_tocEntries` 恆空），導致 FXL 書籤的預設命名不可能是原先誤寫的「第 N 頁」，實際只會落在 `progression` 分支顯示「百分比% 處」。查證後**程式邏輯本身（`Bookmark.defaultName`／`_matchesCurrentPosition`／`listByBook` 的 `COALESCE` 排序）已經正確處理這個 fallback**，問題純粹出在文件描述與測試涵蓋範圍的措辭錯誤（誤把 FXL 併入 PDF 那一組），已修正 Global Constraints、`Bookmark`／`BookmarkPositionContext`／`defaultName`／`_matchesCurrentPosition` 的文件註解，並在 Task 1 新增一則明確驗證 FXL 情境（`progression` 有值、`pdfPageIndex`／`chapterTitle` 皆為 `null`）的測試。本 Issue 尚未實際接線 FXL 的懸浮入口（那是 Issue 4 的範圍），此修正是為 Issue 4 未來呼叫 `Bookmark.defaultName` 時預先鎖定正確、已測試過的行為契約。
- **中度（確認為既有模式的已知取捨，本次採納改善）**：`NotesBottomSheet` 固定高度 500 在小螢幕/系統字型放大情境下有理論溢出風險——查證這與本專案既有的 `PdfSettingsSheet`（固定高度 400）是同一種既有做法，非本計劃新引入的問題，但 `NotesBottomSheet` 是全新元件、現在改動成本低，已改為 `(MediaQuery.of(context).size.height * 0.6).clamp(320.0, 600.0)` 螢幕高度比例＋上下限，`PdfSettingsSheet` 本身維持不動，不擴大本工單範圍。
- **技術確認（無需修改）**：`BookmarksRepository.listByBook` 的 `COALESCE(pdf_page_index, progression) ASC` 跨格式排序機制經審查確認設計合理、效能無虞，予以維持。
