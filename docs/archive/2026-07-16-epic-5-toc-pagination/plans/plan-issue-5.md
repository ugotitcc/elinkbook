# Issue 5：頁首／頁尾顯示切換設定 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓使用者能各自獨立開關 EPUB／PDF 閱讀畫面的頁首（AppBar 標題）與頁尾（`ReaderFooter`）顯示，兩者預設皆為顯示、單書持久化；頁首開啟時 AppBar 標題改為顯示目前章節名稱且可點擊開啟目錄（沿用 Issue 4 的 `TocNavigator`／`TocBottomSheet`）；FXL（固定版面）完全不受影響。

**Architecture:** 沿用 `BookReaderPrefs`（單書覆寫，nullable）→ `ReaderPrefsManagerImpl.resolve()`（合併出 `ResolvedPreferences` 的最終生效值，non-nullable，安全預設 `true`）→ `ReaderScreen` 消費 `_resolved!.showHeader`／`_resolved!.showFooter` 這條既有三層架構，不新增任何新的資料流路徑。頁首邏輯只改動 `ReaderScreen.build()` 的 `AppBar.title`（新增 `_buildAppBarTitle()`），`actions` 完全不變；頁尾邏輯只在既有的兩個 `if` 顯示條件上各自附加 `&& showFooter`。EPUB 設定面板（`ReaderSettingsSheet`）新增兩個開關，PDF 設定面板（`PdfSettingsSheet`）依 issues.md 決策只新增頁尾開關（頁首對 PDF 無實際作用，無章節概念可顯示）。

**Tech Stack:** Flutter/Dart、`sqflite`（SQLite schema migration，累加式 `if (oldVersion < N)`）、`flutter_test`／`integration_test`（兩層測試架構，見 `CLAUDE.md`）。

## Global Constraints

- 所有程式註解、文件、commit message 皆使用正體中文（zh-TW）。
- `BookReaderPrefs` 所有欄位皆 nullable：`null` 代表未覆寫；本 Issue 新增的 `showHeader`／`showFooter` 沿用既有 `publisherStyles`／`dualPageCoverAlone` 的 `bool?` + `toMap`/`fromMap` 用 `== 1`/`? 1 : 0` 編碼慣例。
- `BookReaderPrefs.copyWith` 語意固定為 `newValue ?? this.value`，不支援「明確清空為 null」；本 Issue 新增欄位需比照既有欄位延伸 `copyWith` 簽章。
- `ResolvedPreferences` 欄位是否宣告 non-nullable 的既有判斷依據（見 `resolved_preferences.dart` 檔案開頭註解）：只有已有明確安全預設值的欄位才 non-nullable。`showHeader`／`showFooter` 預設值明確為 `true`（見 spec「預設皆為顯示」），故宣告為 `required bool`，比照 `pageTurnMode`／`dualPageCoverAlone` 等既有欄位。
- SQLite schema migration 必須沿用累加式 `if (oldVersion < N)`（絕不用 `else if`），見 `SqliteLibraryRepository.open()` 現有 `onUpgrade` 的既有註解與教訓（version 1→5 跳級升級曾因誤用互斥分支漏掉遷移）。目前 `version: 6`，本 Issue 新增 `book_reader_prefs` 的 2 個欄位，比照既有 `_addPdfReaderPrefsColumns`／`_addDualPageColumns` 的模式（放在 `else` 分支內，`oldVersion >= 2` 時才需要 `ALTER TABLE`），新增 `_addHeaderFooterColumns`，並在 `_createBookReaderPrefsTable` 的 `CREATE TABLE` 內同步補上兩欄，確保全新安裝一步到位。
- PDF 不提供頁首開關（issues.md 決策 #4：「頁首對 PDF 無實際作用（無內容可顯示）」）——`PdfSettingsSheet` 只新增 `showFooter` 開關，`BookReaderPrefs.showHeader` 對 PDF 書籍永遠維持未覆寫（`null`），`ReaderScreen` 的頁首邏輯本身已用 `format == BookFormat.epub` 排除 PDF，不需要額外防呆。
- FXL（固定版面）完全不受影響：`ReaderScreen.build()` 現有的 `appBar: _isFixedLayout ? null : AppBar(...)` 分支維持不變——FXL 開書時整個 Scaffold AppBar 不建構，頁首邏輯的 `_buildAppBarTitle()` 根本不會被呼叫；FXL 既有的懸浮返回鍵／設定鍵（`reader_fixed_layout_back_button`／`reader_fixed_layout_settings_button`）不在本 Issue 變動範圍內。
- 測試環境限制（見 `CLAUDE.md`「兩層測試架構」）：純 `flutter_test` 環境下 `EpubReaderView._channel` 恆為 `null`，`EpubReaderView.loadTableOfContents()` 恆回傳空清單（`_tocEntries` 永遠是 `[]`），因此無法在 widget test 層級驗證「AppBar 標題真的顯示出正確章節名稱文字」——這件事留給 Task 7 的真機整合測試（用 `test/fixtures/sample_multi_chapter.epub`，已有真實 TOC）。Widget test 只驗證「頁首開啟時 AppBar 標題切換成正確的 Key（`reader_appbar_chapter_title` vs `reader_appbar_static_title`）＋是否可點擊」，不驗證文字內容是否為真實章節名稱。
- `flutter analyze` 全程必須保持 `No issues found!`；每個 Task 的最後一步皆須執行並確認。
- 新增的測試 Key 命名：`reader_settings_show_header`／`reader_settings_show_footer`（`ReaderSettingsSheet`）、`pdf_settings_show_footer`（`PdfSettingsSheet`）、`reader_appbar_chapter_title`／`reader_appbar_static_title`（`ReaderScreen` AppBar 標題）。

---

### Task 1：`BookReaderPrefs` 新增 `showHeader`／`showFooter` 欄位

**Files:**
- Modify: `app/lib/reader/book_reader_prefs.dart`
- Test: `app/test/reader/book_reader_prefs_test.dart`

**Interfaces:**
- Produces: `BookReaderPrefs.showHeader`（`bool?`）、`BookReaderPrefs.showFooter`（`bool?`），供 Task 2（SQLite 欄位對應）、Task 3（`resolve()` 合併邏輯）、Task 4/5（設定面板讀寫）消費。

- [x] **Step 1: 寫失敗測試**

於 `app/test/reader/book_reader_prefs_test.dart` 檔案結尾（最後一個 `}` 之前）新增：

```dart
  test('頁首/頁尾欄位 BookReaderPrefs.empty 為 null（未覆寫，交由 ResolvedPreferences 決定預設值 true）',
      () {
    const prefs = BookReaderPrefs.empty;
    expect(prefs.showHeader, isNull);
    expect(prefs.showFooter, isNull);
  });

  test('頁首/頁尾欄位值完全相同的 BookReaderPrefs 視為相等', () {
    const a = BookReaderPrefs(showHeader: false, showFooter: true);
    const b = BookReaderPrefs(showHeader: false, showFooter: true);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('頁首/頁尾欄位任一不同時視為不相等', () {
    const a = BookReaderPrefs(showHeader: true);
    const b = BookReaderPrefs(showHeader: false);
    expect(a, isNot(b));
  });

  test('showHeader／showFooter 為 true／false／null 皆正確 toMap／fromMap round-trip（避免布林值 0/1 轉換錯誤）',
      () {
    const withTrue = BookReaderPrefs(showHeader: true, showFooter: true);
    final trueMap = withTrue.toMap('book-10');
    expect(trueMap['show_header'], 1);
    expect(trueMap['show_footer'], 1);
    expect(BookReaderPrefs.fromMap(trueMap).showHeader, isTrue);
    expect(BookReaderPrefs.fromMap(trueMap).showFooter, isTrue);

    const withFalse = BookReaderPrefs(showHeader: false, showFooter: false);
    final falseMap = withFalse.toMap('book-11');
    expect(falseMap['show_header'], 0);
    expect(falseMap['show_footer'], 0);
    expect(BookReaderPrefs.fromMap(falseMap).showHeader, isFalse);
    expect(BookReaderPrefs.fromMap(falseMap).showFooter, isFalse);

    const withNull = BookReaderPrefs.empty;
    final nullMap = withNull.toMap('book-12');
    expect(nullMap['show_header'], isNull);
    expect(nullMap['show_footer'], isNull);
    expect(BookReaderPrefs.fromMap(nullMap).showHeader, isNull);
    expect(BookReaderPrefs.fromMap(nullMap).showFooter, isNull);
  });

  test('copyWith 更新 showHeader／showFooter 時，其餘欄位保留原值', () {
    const original =
        BookReaderPrefs(fontSize: 18, showHeader: true, showFooter: true);
    final updated = original.copyWith(showFooter: false);

    expect(updated.fontSize, 18);
    expect(updated.showHeader, isTrue);
    expect(updated.showFooter, isFalse);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/book_reader_prefs_test.dart`
Expected: FAIL（編譯錯誤，`showHeader`/`showFooter` 尚未存在於 `BookReaderPrefs` 建構子）

- [x] **Step 3: 實作 `BookReaderPrefs` 欄位擴充**

`app/lib/reader/book_reader_prefs.dart` 第 39-42 行（`dualPageDirection` 欄位宣告之後）新增：

```dart
  final DualPageMode? dualPageMode; // null=auto（橫向自動雙頁）
  final bool? dualPageCoverAlone; // null=true（封面獨立，僅 PDF 有效）
  final DualPageDirection? dualPageDirection; // null=rtl（僅 PDF 有效）

  final bool? showHeader; // null=true（預設顯示頁首，僅 EPUB 有效，見 spec.md「頁首/頁尾顯示切換」）
  final bool? showFooter; // null=true（預設顯示頁尾，EPUB／PDF 皆有效）
```

第 43-64 行的建構子，於 `this.dualPageDirection,` 之後新增：

```dart
    this.dualPageDirection,
    this.showHeader,
    this.showFooter,
  });
```

第 69-95 行 `toMap`，於 `'dual_page_direction': dualPageDirection?.name,` 之後新增：

```dart
      'dual_page_direction': dualPageDirection?.name,
      'show_header': showHeader == null ? null : (showHeader! ? 1 : 0),
      'show_footer': showFooter == null ? null : (showFooter! ? 1 : 0),
    };
```

第 97-150 行 `fromMap`，於 `dualPageDirection: ...` 之後新增：

```dart
      dualPageDirection: map['dual_page_direction'] == null
          ? null
          : DualPageDirection.values
              .byName(map['dual_page_direction'] as String),
      showHeader:
          map['show_header'] == null ? null : (map['show_header'] as int) == 1,
      showFooter:
          map['show_footer'] == null ? null : (map['show_footer'] as int) == 1,
    );
  }
```

第 152-174 行 `operator ==`，於 `other.dualPageDirection == dualPageDirection` 之後新增：

```dart
      other.dualPageDirection == dualPageDirection &&
      other.showHeader == showHeader &&
      other.showFooter == showFooter;
```

第 176-198 行 `hashCode`，於 `dualPageDirection,` 之後新增：

```dart
        dualPageDirection,
        showHeader,
        showFooter,
      ]);
```

第 205-250 行 `copyWith`，簽章於 `DualPageDirection? dualPageDirection,` 之後新增：

```dart
    DualPageDirection? dualPageDirection,
    bool? showHeader,
    bool? showFooter,
  }) {
```

`copyWith` 回傳的建構呼叫，於 `dualPageDirection: dualPageDirection ?? this.dualPageDirection,` 之後新增：

```dart
      dualPageDirection: dualPageDirection ?? this.dualPageDirection,
      showHeader: showHeader ?? this.showHeader,
      showFooter: showFooter ?? this.showFooter,
    );
  }
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/book_reader_prefs_test.dart`
Expected: PASS（全部測試綠燈）

- [x] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/reader/book_reader_prefs.dart app/test/reader/book_reader_prefs_test.dart
git commit -m "feat(epic-5): BookReaderPrefs 新增 showHeader/showFooter 欄位"
```

---

### Task 2：SQLite schema migration（`book_reader_prefs` v6→v7）

**Files:**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `show_header`/`show_footer` 欄位命名（`BookReaderPrefs.toMap`/`fromMap` 已用這兩個欄位名）。
- Produces: `book_reader_prefs` 表新增 `show_header INTEGER`／`show_footer INTEGER` 兩欄，資料庫 `version` 由 6 提升為 7。

- [x] **Step 1: 寫失敗測試**

於 `app/test/library/sqlite_library_repository_test.dart` 檔案結尾（第 891 行，最後一個 `}` 之前）新增：

```dart
  test('既有 version 6 裝置升級到 version 7，book_reader_prefs 新增頁首/頁尾欄位且既有資料不受影響',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v6_to_v7_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 6」的舊資料庫：手動以 version 6 當時的完整
    // schema（book_reader_prefs 不含 show_header/show_footer）建立，不透過
    // SqliteLibraryRepository.open()（該方法目前的 onCreate 已經是
    // version 7 的最終 schema，無法用來重現「舊裝置」情境）。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 6,
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
              dual_page_direction TEXT
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
    await oldDb.insert('book_reader_prefs', {
      'book_id': 'b1',
      'font_size': 18.0,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=6 →
    // newVersion=7），驗證既有資料不受影響、且頁首/頁尾新欄位可用。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final row = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['font_size'], 18.0); // 既有資料不受影響
    expect(row['show_header'], isNull); // 新欄位存在且預設 NULL
    expect(row['show_footer'], isNull);

    // 證明欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'book_reader_prefs',
      {'show_header': 0, 'show_footer': 1},
      where: 'book_id = ?',
      whereArgs: ['b1'],
    );
    final updated = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(updated['show_header'], 0);
    expect(updated['show_footer'], 1);
  });

  test('全新安裝的 book_reader_prefs 表包含 show_header/show_footer 欄位（version 7 起 onCreate 已含括）',
      () async {
    await repository.insertBook(_book('b_header_footer'));
    await repository.database.insert('book_reader_prefs', {
      'book_id': 'b_header_footer',
      'show_header': 0,
      'show_footer': 1,
    });

    final row = (await repository.database.query('book_reader_prefs',
            where: 'book_id = ?', whereArgs: ['b_header_footer']))
        .single;
    expect(row['show_header'], 0);
    expect(row['show_footer'], 1);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: FAIL（`no such column: show_header`，因為 schema 尚未更新且 `version` 仍為 6，`onUpgrade` 不會被觸發到新遷移邏輯）

- [x] **Step 3: 實作 schema migration**

`app/lib/library/sqlite_library_repository.dart` 第 27 行，`version: 6,` 改為：

```dart
      version: 7,
```

第 111-135 行 `_createBookReaderPrefsTable` 的 `CREATE TABLE`，於 `dual_page_direction TEXT` 之後新增兩欄（注意逗號移動）：

```dart
        dual_page_mode TEXT,
        dual_page_cover_alone INTEGER,
        dual_page_direction TEXT,
        show_header INTEGER,
        show_footer INTEGER
      )
    ''');
  }
```

> **【審查修正，取代本 Step 原始版本】** 本 Step 原始版本要求把 `if (oldVersion < 7)`
> 放在 `if (oldVersion < 2) {...} else {...}` 這組 if/else **之外**（頂層、無條件
> 執行），且 `_addHeaderFooterColumns` 不做任何表格存在性檢查，並宣稱「結果等價」。
> 這個宣稱是錯的：`tmp/epic-5/reviews/review-issue-5-independent.md` I-1 項透過
> 交叉比對本檔案既有（未被本 Issue 改動）的兩個回歸測試證明，該版本會讓既有升級
> 路徑崩潰——
> 1. 「既有 version 1 裝置跳級升級到 version 6」測試：`oldVersion < 2` 為真，會呼叫
>    `_createBookReaderPrefsTable(db)`（已含 `show_header`/`show_footer`）；若頂層
>    又無條件再對同一張表 `ALTER TABLE ADD COLUMN show_header` 一次，會拋出
>    `duplicate column name: show_header`。
> 2. 「既有 version 5 裝置升級到 version 6」測試：該測試模擬的舊資料庫**沒有**
>    `book_reader_prefs` 表；若沒有存在性檢查就對它執行 `ALTER TABLE`，會拋出
>    `no such table: book_reader_prefs`。
>
> 下方步驟已改為分支邏輯與存在性檢查兼具的正確版本（與 `feat/epic5-issue5-header-footer-toggle`
> 分支實際合併的程式碼一致），後續依此計畫實作/複查的人請以此為準，不要沿用舊版
> 「頂層無條件執行」的說法。

第 94-100 行（`if (oldVersion < 6) { ... }` 區塊之後），新增第三個無條件檢查區塊；並在
第 78-83 行既有的 `if (oldVersion < 2) {...} else { if (oldVersion < 3) {...} if
(oldVersion < 4) {...} }` 這組 `else` 分支**內**，於 `if (oldVersion < 4)` 區塊之後
新增 `if (oldVersion < 7)` 區塊（放在 `else` 分支內的理由：`oldVersion < 2` 時
`_createBookReaderPrefsTable` 已一步到位建表、不需要再 `ALTER TABLE`；只有
`book_reader_prefs` 表本來就已存在（`oldVersion >= 2`）時才需要補欄位）：

```dart
        if (oldVersion < 2) {
          await _createBookReaderPrefsTable(db);
        } else {
          if (oldVersion < 3) {
            await _addPdfReaderPrefsColumns(db);
          }
          if (oldVersion < 4) {
            await _addDualPageColumns(db);
          }
          if (oldVersion < 7) {
            // epic-5-toc-pagination Issue 5：頁首/頁尾顯示切換新增的 2 個
            // 欄位，補追加到既有（version 2 起已存在）的 book_reader_prefs
            // 表。放在 else 分支內（oldVersion >= 2）——因為 oldVersion < 2
            // 時 _createBookReaderPrefsTable 已一步到位建表含
            // show_header/show_footer，不需要再 ALTER TABLE。
            await _addHeaderFooterColumns(db);
          }
        }
        if (oldVersion < 5) {
          await _addReadingPositionColumns(db);
        }
        if (oldVersion < 6) {
          // epic-5-toc-pagination Issue 3：全書字元數快取欄位，補追加到
          // 既有（version 1 起已存在）的 books 表。刻意放在上方 if/else
          // 之外、無條件檢查，比照 oldVersion < 5 區塊的既有原則——不論
          // 裝置目前處於哪個舊版本，只要 oldVersion < 6 就必須執行。
          await _addTotalCharacterCountColumn(db);
        }
      },
    );
    return SqliteLibraryRepository._(db);
  }
```

在 `_addTotalCharacterCountColumn` 方法（第 177-182 行）之後新增：

```dart
  static Future<void> _addHeaderFooterColumns(Database db) async {
    // 頁首/頁尾顯示切換（epic-5-toc-pagination Issue 5）新增的 2 個欄位，
    // 補追加到既有（version 2 起已存在）的 book_reader_prefs 表，見
    // docs/epics/epic-5-toc-pagination/spec.md「頁首/頁尾顯示切換」。
    // 僅在表已存在時才執行 ALTER TABLE（某些測試情境下 oldVersion >= 2
    // 但 book_reader_prefs 表可能不存在，見 v5→v6 升級測試）。
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='book_reader_prefs'");
    if (tables.isNotEmpty) {
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN show_header INTEGER');
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN show_footer INTEGER');
    }
  }
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: PASS（全部測試綠燈，含既有 v1→v6 系列遷移測試不受影響）

- [x] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-5): book_reader_prefs 新增 show_header/show_footer 欄位（v6→v7）"
```

---

### Task 3：`ResolvedPreferences` + `ReaderPrefsManagerImpl.resolve()` 擴充

**Files:**
- Modify: `app/lib/reader/resolved_preferences.dart`
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart`
- Modify: `app/test/reader/resolved_preferences_test.dart`（既有測試直接建構 `ResolvedPreferences(...)`，`showHeader`/`showFooter` 改為 `required` 後需補上，見 Step 5）
- Modify: `app/test/screens/toc_bottom_sheet_test.dart`（同上，見 Step 5）
- Test: `app/test/reader/reader_prefs_manager_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `BookReaderPrefs.showHeader`/`showFooter`（`bool?`）。
- Produces: `ResolvedPreferences.showHeader`/`showFooter`（`required bool`，安全預設 `true`），供 Task 6（`ReaderScreen`）消費。

- [x] **Step 1: 寫失敗測試**

於 `app/test/reader/reader_prefs_manager_test.dart` 第 36-56 行的測試（`'全部欄位皆未覆寫時，回傳的 non-null 欄位皆為既存安全預設值'`）內，於 `expect(resolved.dualPageDirection, DualPageDirection.rtl);` 之後新增：

```dart
      expect(resolved.dualPageDirection, DualPageDirection.rtl);
      expect(resolved.showHeader, isTrue);
      expect(resolved.showFooter, isTrue);
    });
```

於第 58-80 行的測試（`'單書覆寫存在時，優先套用單書覆寫，忽略全域預設'`）的 `bookPrefs` 中新增覆寫值，並於斷言區塊新增對應驗證：

```dart
        bookPrefs: const BookReaderPrefs(
          pageTurnModeOverride: PageTurnMode.scroll,
          screenOrientationOverride: ScreenOrientationSetting.lock90,
          pdfFitMode: PdfFitMode.fitWidth,
          pdfContrast: 20,
          dualPageMode: DualPageMode.always,
          dualPageCoverAlone: false,
          dualPageDirection: DualPageDirection.rtl,
          showHeader: false,
          showFooter: false,
        ),
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      final resolved = manager.resolve(loaded);

      expect(resolved.pageTurnMode, PageTurnMode.scroll);
      expect(resolved.screenOrientation, ScreenOrientationSetting.lock90);
      expect(resolved.pdfFitMode, PdfFitMode.fitWidth);
      expect(resolved.pdfContrast, 20);
      expect(resolved.dualPageMode, DualPageMode.always);
      expect(resolved.dualPageCoverAlone, isFalse);
      expect(resolved.dualPageDirection, DualPageDirection.rtl);
      expect(resolved.showHeader, isFalse);
      expect(resolved.showFooter, isFalse);
    });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/reader_prefs_manager_test.dart`
Expected: FAIL（編譯錯誤，`ResolvedPreferences`/`BookReaderPrefs` 尚未有 `showHeader`/`showFooter`——`BookReaderPrefs` 部分已由 Task 1 完成，故僅 `ResolvedPreferences.showHeader` 缺失導致 `resolved.showHeader` 編譯失敗）

- [x] **Step 3: 實作 `ResolvedPreferences` 擴充**

`app/lib/reader/resolved_preferences.dart` 第 45-47 行（`dualPageDirection` 欄位宣告之後）新增：

```dart
  final DualPageMode dualPageMode;
  final bool dualPageCoverAlone;
  final DualPageDirection dualPageDirection;

  final bool showHeader;
  final bool showFooter;
```

第 49-70 行建構子，於 `required this.dualPageDirection,` 之後新增：

```dart
    required this.dualPageDirection,
    required this.showHeader,
    required this.showFooter,
  });
```

- [x] **Step 4: 實作 `ReaderPrefsManagerImpl.resolve()` 擴充**

`app/lib/reader/reader_prefs_manager_impl.dart` 第 121-130 行 `resolve()` 回傳的 `ResolvedPreferences(...)`，於 `dualPageDirection: book.dualPageDirection ?? DualPageDirection.rtl,` 之後新增：

```dart
      dualPageMode: book.dualPageMode ?? DualPageMode.auto,
      dualPageCoverAlone: book.dualPageCoverAlone ?? true,
      dualPageDirection: book.dualPageDirection ?? DualPageDirection.rtl,
      showHeader: book.showHeader ?? true,
      showFooter: book.showFooter ?? true,
    );
  }
}
```

- [x] **Step 5: 修正因 `ResolvedPreferences` 新增 `required` 欄位而編譯失敗的既有測試檔案**

`ResolvedPreferences` 新增 `showHeader`/`showFooter` 兩個 `required bool` 欄位後，程式碼庫中所有繞過 `resolve()`、直接建構 `ResolvedPreferences(...)` 的既有測試會編譯失敗（審查意見 `tmp/epic-5/reviews/plan-issue-5-review.md` Critical 項，已核對codebase 確認為真：兩處皆為既有測試檔案、與 `resolve()` 本身無關，需個別補上欄位值）。

`app/test/reader/resolved_preferences_test.dart` 第 33 行（`dualPageDirection: DualPageDirection.ltr,`）之後新增：

```dart
      dualPageDirection: DualPageDirection.ltr,
      showHeader: true,
      showFooter: true,
    );
```

`app/test/screens/toc_bottom_sheet_test.dart` 第 23 行（`dualPageDirection: DualPageDirection.rtl,`）之後新增：

```dart
  dualPageDirection: DualPageDirection.rtl,
  showHeader: true,
  showFooter: true,
);
```

- [x] **Step 6: 執行測試確認通過**

Run: `flutter test test/reader/reader_prefs_manager_test.dart test/reader/resolved_preferences_test.dart test/screens/toc_bottom_sheet_test.dart`
Expected: PASS（全部測試綠燈）

- [x] **Step 7: 執行全專案測試確認無回歸**

Run: `flutter test`
Expected: 全部通過（Step 5 已補上程式碼庫中僅有的兩處既有 `ResolvedPreferences(...)` 直接建構點；若此步驟仍發現其他編譯失敗的建構點，代表 Step 5 的範圍調查有遺漏，需一併補上 `showHeader: true, showFooter: true,`）

- [x] **Step 8: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 9: Commit**

```bash
git add app/lib/reader/resolved_preferences.dart app/lib/reader/reader_prefs_manager_impl.dart app/test/reader/reader_prefs_manager_test.dart app/test/reader/resolved_preferences_test.dart app/test/screens/toc_bottom_sheet_test.dart
git commit -m "feat(epic-5): ResolvedPreferences 新增 showHeader/showFooter，resolve() 合併安全預設值 true"
```

---

### Task 4：`ReaderSettingsSheet`（EPUB）新增頁首／頁尾開關

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart`
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `BookReaderPrefs.showHeader`/`showFooter`。
- Produces: 使用者互動後透過既有 `onChanged(BookReaderPrefs)` 回報包含 `showHeader`/`showFooter` 的完整 `BookReaderPrefs`，供 `ReaderScreen`（既有 `_handlePrefsChanged` 呼叫路徑，本 Task 不變動）持久化。

- [x] **Step 1: 寫失敗測試**

於 `app/test/screens/reader_settings_sheet_test.dart` 檔案結尾（最後一個 `}` 之前，`_pumpSheet` 定義之前）新增：

```dart
testWidgets('頁首/頁尾開關初始值反映 prefs（未持久化時預設開啟）', (tester) async {
  await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

  expect(
    tester
        .widget<SwitchListTile>(
            find.byKey(const Key('reader_settings_show_header')))
        .value,
    isTrue,
  );
  expect(
    tester
        .widget<SwitchListTile>(
            find.byKey(const Key('reader_settings_show_footer')))
        .value,
    isTrue,
  );
});

testWidgets('已持久化 showHeader=false 時，頁首開關初始值反映為關閉', (tester) async {
  await _pumpSheet(
    tester,
    const BookReaderPrefs(showHeader: false),
    (_) {},
  );

  expect(
    tester
        .widget<SwitchListTile>(
            find.byKey(const Key('reader_settings_show_header')))
        .value,
    isFalse,
  );
});

testWidgets('關閉頁首開關後，onChanged 帶入 showHeader=false 且不影響 showFooter',
    (tester) async {
  BookReaderPrefs? result;
  await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => result = prefs);

  await tester.tap(find.byKey(const Key('reader_settings_show_header')));
  await tester.pump();

  expect(result, isNotNull);
  expect(result!.showHeader, isFalse);
  expect(result!.showFooter, isTrue);
});

testWidgets('關閉頁尾開關後，onChanged 帶入 showFooter=false 且不影響 showHeader',
    (tester) async {
  BookReaderPrefs? result;
  await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => result = prefs);

  await tester.tap(find.byKey(const Key('reader_settings_show_footer')));
  await tester.pump();

  expect(result, isNotNull);
  expect(result!.showFooter, isFalse);
  expect(result!.showHeader, isTrue);
});

testWidgets('切換頁首/頁尾開關不會清空其他既有覆寫欄位（回歸檢查）', (tester) async {
  BookReaderPrefs? result;
  await _pumpSheet(
    tester,
    const BookReaderPrefs(
      writingModeOverride: WritingMode.vertical,
      pageTurnModeOverride: PageTurnMode.scroll,
    ),
    (prefs) => result = prefs,
  );

  await tester.tap(find.byKey(const Key('reader_settings_show_header')));
  await tester.pump();

  expect(result, isNotNull);
  expect(result!.writingModeOverride, WritingMode.vertical);
  expect(result!.pageTurnModeOverride, PageTurnMode.scroll);
});
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: FAIL（`find.byKey(const Key('reader_settings_show_header'))` 找不到對應 widget）

- [x] **Step 3: 實作 `ReaderSettingsSheet` 擴充**

`app/lib/screens/reader_settings_sheet.dart` 第 53-55 行（State 欄位宣告，`_screenOrientationOverride` 之後）新增：

```dart
  late WritingMode? _writingModeOverride;
  late PageTurnMode? _pageTurnModeOverride;
  late ScreenOrientationSetting? _screenOrientationOverride;
  late bool _showHeader;
  late bool _showFooter;
```

第 57-77 行 `initState`，於 `_screenOrientationOverride = widget.prefs.screenOrientationOverride;` 之後新增：

```dart
    _screenOrientationOverride = widget.prefs.screenOrientationOverride;
    _showHeader = widget.prefs.showHeader ?? true;
    _showFooter = widget.prefs.showFooter ?? true;
  }
```

第 79-103 行 `didUpdateWidget`，同樣位置新增：

```dart
        _screenOrientationOverride = widget.prefs.screenOrientationOverride;
        _showHeader = widget.prefs.showHeader ?? true;
        _showFooter = widget.prefs.showFooter ?? true;
      });
    }
  }
```

第 109-123 行 `_notifyChanged`，於 `screenOrientationOverride: _screenOrientationOverride,` 之後新增：

```dart
      screenOrientationOverride: _screenOrientationOverride,
      showHeader: _showHeader,
      showFooter: _showFooter,
    ));
  }
```

第 200-211 行（`SwitchListTile(key: reader_settings_disable_book_css, ...)` 之後、`_buildWritingModeOverrideRow()` 之前）新增兩個開關：

```dart
          SwitchListTile(
            key: const Key('reader_settings_disable_book_css'),
            title: const Text('停用書本 CSS'),
            value: !_publisherStyles,
            onChanged: (v) => setState(() {
              _publisherStyles = !v;
              _notifyChanged();
            }),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            key: const Key('reader_settings_show_header'),
            title: const Text('顯示頁首'),
            value: _showHeader,
            onChanged: (v) => setState(() {
              _showHeader = v;
              _notifyChanged();
            }),
          ),
          SwitchListTile(
            key: const Key('reader_settings_show_footer'),
            title: const Text('顯示頁尾'),
            value: _showFooter,
            onChanged: (v) => setState(() {
              _showFooter = v;
              _notifyChanged();
            }),
          ),
          const SizedBox(height: 12),
          _buildWritingModeOverrideRow(),
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: PASS（全部測試綠燈，含既有測試不受影響）

- [x] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "feat(epic-5): ReaderSettingsSheet 新增顯示頁首/頁尾開關"
```

---

### Task 5：`PdfSettingsSheet`（PDF）新增頁尾開關（不含頁首）

**Files:**
- Modify: `app/lib/screens/pdf_settings_sheet.dart`
- Test: `app/test/screens/pdf_settings_sheet_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `BookReaderPrefs.showFooter`（PDF 不使用 `showHeader`，見 Global Constraints）。
- Produces: 使用者互動後透過既有 `onChanged(BookReaderPrefs)` 回報包含 `showFooter` 的完整 `BookReaderPrefs`。

- [x] **Step 1: 寫失敗測試**

於 `app/test/screens/pdf_settings_sheet_test.dart` 檔案結尾（最後一個 `}` 之前，`_pumpSheet` 定義之前）新增：

```dart
testWidgets('頁尾開關初始值反映 prefs（未持久化時預設開啟）', (tester) async {
  await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

  expect(
    tester
        .widget<SwitchListTile>(
            find.byKey(const Key('pdf_settings_show_footer')))
        .value,
    isTrue,
  );
});

testWidgets('已持久化 showFooter=false 時，頁尾開關初始值反映為關閉', (tester) async {
  await _pumpSheet(
    tester,
    const BookReaderPrefs(showFooter: false),
    (_) {},
  );

  expect(
    tester
        .widget<SwitchListTile>(
            find.byKey(const Key('pdf_settings_show_footer')))
        .value,
    isFalse,
  );
});

testWidgets('關閉頁尾開關後，onChanged 帶入 showFooter=false', (tester) async {
  BookReaderPrefs? notified;
  await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => notified = prefs);

  await tester.tap(find.byKey(const Key('pdf_settings_show_footer')));
  await tester.pump();

  expect(notified?.showFooter, isFalse);
});

testWidgets('已持久化 showFooter=false 時，調整雙頁模式不會清空該欄位（回歸檢查）',
    (tester) async {
  BookReaderPrefs? notified;
  await _pumpSheet(
    tester,
    const BookReaderPrefs(showFooter: false),
    (prefs) => notified = prefs,
  );

  await tester.tap(find.byKey(const Key('pdf_settings_dual_page_mode_always')));
  await tester.pump();

  expect(notified?.dualPageMode, DualPageMode.always);
  expect(notified?.showFooter, isFalse, reason: '關鍵斷言：未被清空');
});
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: FAIL（`find.byKey(const Key('pdf_settings_show_footer'))` 找不到對應 widget）

- [x] **Step 3: 實作 `PdfSettingsSheet` 擴充**

`app/lib/screens/pdf_settings_sheet.dart` 第 46-47 行（State 欄位宣告，`_dualPageDirection` 之後）新增：

```dart
  late DualPageDirection _dualPageDirection;
  late bool _showFooter;
```

第 50-61 行 `initState`，於 `_dualPageDirection = widget.prefs.dualPageDirection ?? DualPageDirection.rtl;` 之後新增：

```dart
    _dualPageDirection = widget.prefs.dualPageDirection ?? DualPageDirection.rtl;
    _showFooter = widget.prefs.showFooter ?? true;
  }
```

第 69-85 行 `_notifyChanged`，於 `dualPageDirection: _dualPageDirection,` 之後新增：

```dart
      dualPageDirection: _dualPageDirection,
      showFooter: _showFooter,
    ));
  }
```

第 203-212 行（`SwitchListTile(key: pdf_settings_dual_page_cover_alone, ...)` 之後、`const SizedBox(height: 16)` + `const Text('頁面方向')` 之前）新增：

```dart
            SwitchListTile(
              key: const Key('pdf_settings_dual_page_cover_alone'),
              title: const Text('封面獨立顯示'),
              value: _dualPageCoverAlone,
              onChanged: (v) => setState(() {
                _dualPageCoverAlone = v;
                _notifyChanged();
              }),
            ),
            SwitchListTile(
              key: const Key('pdf_settings_show_footer'),
              title: const Text('顯示頁尾'),
              value: _showFooter,
              onChanged: (v) => setState(() {
                _showFooter = v;
                _notifyChanged();
              }),
            ),
            const SizedBox(height: 16),
            const Text('頁面方向'),
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: PASS（全部測試綠燈，含既有測試不受影響）

- [x] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/pdf_settings_sheet.dart app/test/screens/pdf_settings_sheet_test.dart
git commit -m "feat(epic-5): PdfSettingsSheet 新增顯示頁尾開關（不含頁首，PDF 無章節概念）"
```

---

### Task 6：`ReaderScreen` 接線——頁首標題替換 + 頁尾顯示切換

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `ResolvedPreferences.showHeader`/`showFooter`；既有 `TocNavigator.findCurrentPath(List<TocEntry>, double?)`（Issue 4）、既有 `_tocEntries`/`_tocLoaded`/`_epubPositionInfo`/`_openToc()`（Issue 4）。
- Produces: 無新的公開介面——`ReaderScreen` 對外建構參數不變，行為變化透過既有 `Key('reader_appbar_chapter_title')`（新增）/`Key('reader_appbar_static_title')`（新增）/`Key('reader_footer')`（既有）供測試觀察。

- [x] **Step 1: 寫失敗測試**

於 `app/test/screens/reader_screen_test.dart` 檔案結尾（最後一個 `}` 之前）新增：

```dart
  // --- Epic 5 Issue 5：頁首/頁尾顯示切換 ---

  testWidgets('EPUB reflowable 預設（未持久化）showHeader=true，開書後 AppBar 標題為可點擊的章節標題元件',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_header_default',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_appbar_chapter_title')), findsOneWidget);
    expect(find.byKey(const Key('reader_appbar_static_title')), findsNothing);
    // 「⚙️版面」按鈕仍在 actions 內，頁首開關不影響既有版面設定入口
    // （issues.md 驗收條件：既有的版面設定入口維持可用）。
    expect(find.byKey(const Key('reader_layout_settings_button')), findsOneWidget);
  });

  testWidgets('已持久化 showHeader=false 時，AppBar 標題維持靜態「閱讀器」文字',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b_header_off',
      const BookReaderPrefs(showHeader: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_header_off',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_appbar_static_title')), findsOneWidget);
    expect(find.text('閱讀器'), findsOneWidget);
    expect(find.byKey(const Key('reader_appbar_chapter_title')), findsNothing);
    expect(find.byKey(const Key('reader_toc_button')), findsOneWidget,
        reason: '頁首關閉不影響目錄按鈕仍存在於 actions');
  });

  testWidgets('PDF 開書後，AppBar 標題恆為靜態「閱讀器」文字（頁首概念僅限 EPUB）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_pdf_header',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_appbar_static_title')), findsOneWidget);
    expect(find.byKey(const Key('reader_appbar_chapter_title')), findsNothing);
  });

  testWidgets('頁首啟用且目錄背景抓取完成後，點擊 AppBar 標題可開啟 TocBottomSheet',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_header_tap',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    // 比照既有目錄按鈕測試：_tocLoaded 由 loadTableOfContents() 的 .then()
    // callback 設定，需要多一次 pump 讓其 microtask 完成。
    await tester.pump();

    final titleFinder = find.byKey(const Key('reader_appbar_chapter_title'));
    expect(tester.widget<InkWell>(titleFinder).onTap, isNotNull);

    await tester.tap(titleFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TocBottomSheet), findsOneWidget);
  });

  // 【刻意不測試】「頁首啟用但目錄尚未載入完成前，標題不可點擊」的中間狀態：
  // 本次會話稍早針對 Issue 4 目錄按鈕的等價測試已證實這個中間狀態在純
  // flutter test（channel 恆為 null）環境下的可觀察時機對 pump() 次數
  // 極度敏感、不可靠（見 tmp/epic-5/reviews/review-issue-4-independent.md
  // 之後的修正紀錄）。改為只驗證下方「目錄背景抓取完成後可點擊」的終態，
  // gating 邏輯本身（`_autoDetectedWritingMode == null || !_tocLoaded`）
  // 與既有目錄按鈕 onPressed 共用同一組條件，已由既有測試涵蓋其正確性。

  testWidgets('showFooter=false 時，EPUB 頁尾即使收到 onCharacterCountReady 也不顯示',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b_footer_off_epub',
      const BookReaderPrefs(showFooter: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_footer_off_epub',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsNothing);
    // 頁尾關閉不影響頁首（預設開啟）——驗證兩者互相獨立。
    expect(find.byKey(const Key('reader_appbar_chapter_title')), findsOneWidget);
  });

  testWidgets('showFooter=false 時，PDF 頁尾即使收到 onPageChanged 也不顯示',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b_footer_off_pdf',
      const BookReaderPrefs(showFooter: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_footer_off_pdf',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageChanged?.call(const PdfPageInfo(pageIndex: 0, totalPages: 12));
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  testWidgets('showHeader=true 且 showFooter=false 組合：頁首顯示章節標題元件、頁尾不顯示',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b_header_on_footer_off',
      const BookReaderPrefs(showHeader: true, showFooter: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_header_on_footer_off',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(find.byKey(const Key('reader_appbar_chapter_title')), findsOneWidget);
    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  testWidgets('showHeader=false 且 showFooter=true 組合：頁首為靜態文字、頁尾顯示',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b_header_off_footer_on',
      const BookReaderPrefs(showHeader: false, showFooter: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_header_off_footer_on',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(find.byKey(const Key('reader_appbar_static_title')), findsOneWidget);
    expect(find.byKey(const Key('reader_footer')), findsOneWidget);
  });

  testWidgets('EPUB 固定版面（FXL）開書後，即使 showHeader=false/showFooter=false，懸浮返回/設定按鈕仍正常顯示（FXL 完全不受影響）',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b_fxl_untouched',
      const BookReaderPrefs(showHeader: false, showFooter: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fxl_untouched',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    expect(find.byType(AppBar), findsNothing, reason: 'FXL 不建構 Scaffold AppBar，頁首邏輯不適用');
    expect(find.byKey(const Key('reader_fixed_layout_back_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_fixed_layout_settings_button')), findsOneWidget);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: FAIL（`find.byKey(const Key('reader_appbar_chapter_title'))`/`Key('reader_appbar_static_title')` 找不到對應 widget，`AppBar.title` 目前仍是寫死的 `const Text('閱讀器')`）

- [x] **Step 3: 實作 `ReaderScreen` 接線**

`app/lib/screens/reader_screen.dart` 第 504-514 行 `build()` 內的 `Scaffold`，`title: const Text('閱讀器'),` 改為：

```dart
      child: Scaffold(
        appBar: _isFixedLayout
            ? null // 固定版面（如漫畫）隱藏 Scaffold AppBar，改用 Stack 懸浮半透明按鈕，避免裁切大圖
            : AppBar(
                title: _buildAppBarTitle(format),
                actions: _buildAppBarActions(format),
              ),
        body: _buildBody(format, isLandscape),
      ),
    );
  }

  /// 頁首顯示切換（epic-5-toc-pagination Issue 5，spec.md「頁首/頁尾顯示
  /// 切換」）：`showHeader == false` 或非 EPUB 格式時維持既有的靜態標題；
  /// `showHeader == true`（含尚未載入完成前的安全預設值，見
  /// `ResolvedPreferences.showHeader`）時改用目前章節名稱，可點擊開啟目錄
  /// （沿用 Issue 4 的 `TocNavigator.findCurrentPath`／`_openToc`）。章節
  /// 名稱在目錄背景抓取完成（`_tocLoaded`）前一律回退顯示「閱讀器」佔位
  /// 文字，`onTap` 同步以 `_tocLoaded` 防呆，比照 `_buildAppBarActions` 的
  /// 目錄按鈕既有 gating 條件，避免點擊到空白 Bottom Sheet。
  Widget _buildAppBarTitle(BookFormat format) {
    final showHeader = format == BookFormat.epub && (_resolved?.showHeader ?? true);
    if (!showHeader) {
      return const Text('閱讀器', key: Key('reader_appbar_static_title'));
    }
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    final chapterTitle = currentPath.isEmpty ? '閱讀器' : currentPath.last.title;
    return InkWell(
      key: const Key('reader_appbar_chapter_title'),
      onTap: (_autoDetectedWritingMode == null || !_tocLoaded) ? null : _openToc,
      child: Text(chapterTitle, overflow: TextOverflow.ellipsis),
    );
  }
```

第 630-643 行頁尾顯示條件，於既有兩個 `if` 各自附加 `showFooter` 檢查：

```dart
          if (format == BookFormat.pdf &&
              _pdfPageInfo != null &&
              (_resolved?.showFooter ?? true))
            ReaderFooter(
              currentPage: _pdfPageInfo!.pageIndex + 1,
              totalPages: _pdfPageInfo!.totalPages,
              onPageChanged: (page1Indexed) {
                // 審查修正：透過強型別 static helper 呼叫，不使用 as dynamic。
                PdfReaderView.jumpToPage(_pdfReaderViewKey, page1Indexed - 1);
              },
            ),
          if (format == BookFormat.epub &&
              !_isFixedLayout &&
              _totalCharacterCount != null &&
              _resolved != null &&
              _resolved!.showFooter)
            _buildEpubFooter(_resolved!, _totalCharacterCount!),
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（全部測試綠燈，含既有測試不受影響——尤其第 38-51 行的 TXT 格式測試與第 53-72 行未觸發 `onLayoutResolved` 的 EPUB 測試，兩者的 AppBar 標題皆維持 `_buildAppBarTitle` 回傳的靜態文字分支，`find.text('閱讀器')` 斷言不受影響）

- [x] **Step 5: 執行全專案測試確認無回歸**

Run: `flutter test`
Expected: 全部通過

- [x] **Step 6: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 7: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-5): ReaderScreen 接線頁首標題替換與頁尾顯示切換"
```

---

### Task 7：真機整合測試——頁首/頁尾切換端對端驗證（EPUB + PDF）

**Files:**
- Create: `app/integration_test/reader_header_footer_toggle_test.dart`

**Interfaces:**
- Consumes: 全部前六個 Task 產出的完整資料流（`BookReaderPrefs` → SQLite → `resolve()` → `ReaderScreen`）。本 Task 不新增任何生產程式碼介面，純驗證。

- [x] **Step 1: 撰寫真機整合測試**

建立 `app/integration_test/reader_header_footer_toggle_test.dart`：

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
import 'package:elinkbook/reader/epub_character_count_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/screens/reader_settings_sheet.dart';
import 'package:elinkbook/screens/pdf_settings_sheet.dart';

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

Future<void> _pumpUntilTocButtonEnabled(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final finder = find.byKey(const Key('reader_toc_button'));
    if (finder.evaluate().isNotEmpty &&
        tester.widget<IconButton>(finder).onPressed != null) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：目錄按鈕未轉為可點擊狀態（背景目錄抓取未完成）');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('EPUB：頁首預設顯示真實章節名稱、關閉頁首後恢復靜態標題、頁尾可獨立切換',
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

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub', 'header_footer_epub.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_header_footer_epub',
      title: '頁首頁尾測試書',
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
          bookId: 'b_header_footer_epub',
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilTocButtonEnabled(tester);

    // 預設 showHeader=true：AppBar 標題應顯示真實章節名稱（非佔位符
    // 「閱讀器」），證明 _tocEntries／_epubPositionInfo 已成功串接到
    // TocNavigator.findCurrentPath——這是純 flutter test 環境（channel 恆
    // 為 null）無法驗證的部分，見 plan-issue-5.md Global Constraints。
    expect(find.byKey(const Key('reader_appbar_chapter_title')), findsOneWidget);
    expect(find.text('第一章：起始'), findsOneWidget,
        reason: '開書起始頁應落在第一章，AppBar 標題應顯示真實章節名稱而非佔位符');

    // 點擊頁首開啟目錄（複用 Issue 4 已驗證的目錄互動邏輯）。
    await tester.tap(find.byKey(const Key('reader_appbar_chapter_title')));
    await tester.pumpAndSettle();
    expect(find.text('第二章：發展'), findsOneWidget);
    await tester.tap(find.text('第三章：結局'));
    await tester.pumpAndSettle();

    // 開啟版面設定，關閉頁首開關。
    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSettingsSheet), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader_settings_show_header')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reader_settings_show_footer')));
    await tester.pump();
    await tester.tapAt(const Offset(20, 20)); // 點擊 Bottom Sheet 外部關閉
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader_appbar_static_title')), findsOneWidget,
        reason: '關閉頁首後應恢復靜態「閱讀器」標題');
    expect(find.byKey(const Key('reader_appbar_chapter_title')), findsNothing);
    expect(find.byKey(const Key('reader_footer')), findsNothing,
        reason: '關閉頁尾後不應再顯示頁尾，且與頁首關閉狀態互相獨立驗證');
  });

  testWidgets('PDF：頁尾可透過設定面板獨立切換顯示/隱藏，AppBar 標題全程維持靜態文字',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );

    final samplePath =
        await _stageAssetAsFile('test/fixtures/sample.pdf', 'header_footer_pdf.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_header_footer_pdf',
      title: '頁首頁尾測試書（PDF）',
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
          bookId: 'b_header_footer_pdf',
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);

    expect(find.byKey(const Key('reader_appbar_static_title')), findsOneWidget,
        reason: 'PDF 無頁首概念，AppBar 標題全程應維持靜態文字');
    expect(find.byKey(const Key('reader_footer')), findsOneWidget,
        reason: '預設 showFooter=true，頁尾應顯示');

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();
    expect(find.byType(PdfSettingsSheet), findsOneWidget);
    await tester.tap(find.byKey(const Key('pdf_settings_show_footer')));
    await tester.pump();
    await tester.tapAt(const Offset(20, 20)); // 點擊 Bottom Sheet 外部關閉
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader_footer')), findsNothing,
        reason: '關閉頁尾開關後頁尾應消失');
    expect(find.byKey(const Key('reader_appbar_static_title')), findsOneWidget,
        reason: 'PDF 頁尾切換不應影響 AppBar 標題');
  });
}
```

- [x] **Step 2: 於真實裝置執行測試**

Run: `flutter test integration_test/reader_header_footer_toggle_test.dart -d <device-id>`（例如本專案既有的 `3CEF42ECD491687`）
Expected: `All tests passed!`

- [x] **Step 3: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 4: Commit**

```bash
git add app/integration_test/reader_header_footer_toggle_test.dart
git commit -m "test(epic-5): 新增頁首/頁尾切換真機整合測試（EPUB + PDF）"
```

---

## 完成後檢查（對照 issues.md 驗收條件）

- [x] 設定面板存在對應開關，預設皆為開啟（Task 4/5）
- [x] 頁首開啟時 AppBar 標題正確顯示可點擊的目前章節名稱（Task 6 widget test + Task 7 真機驗證真實文字內容）
- [x] 頁首關閉時正確恢復原本的靜態標題（Task 6）
- [x] 頁尾顯示與頁首顯示互不影響、可獨立切換（Task 6 兩個組合測試 + Task 7 真機驗證）
- [x] FXL（固定版面）完全不受影響（Task 6 專屬測試）
- [x] 所有新增/既有單元測試與 `flutter analyze` 皆通過、無回歸（每個 Task 的 Step 5/6）
- [x] 真機整合測試涵蓋 EPUB 與 PDF 兩種格式的頁首/頁尾切換端對端流程（Task 7）
