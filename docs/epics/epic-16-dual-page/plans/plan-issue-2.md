# Epic 16 Issue 2 — 資料層基礎建設：雙頁偏好設定儲存 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 `DualPageMode`／`DualPageDirection` 兩個列舉型別，並在 `BookReaderPrefs`／SQLite `book_reader_prefs` 表新增 3 個雙頁專屬欄位，供本 epic 後續 Issue 3-7 共用的持久化基礎。純 Dart，不涉及原生程式碼，不需要真實裝置。

**Architecture:** 沿用本專案既有的「全欄位 nullable、跨格式共用單一表、`copyWith`/`toMap`/`fromMap` 平行擴充」模式（`epic-4-pdf-enhance` Issue 1 建立的先例）。`SqliteLibraryRepository` 的資料庫版本從 3 升到 4；`onUpgrade` 邏輯需從互斥的 `if/else if` 改為累加式 `if` 判斷（見 Task 2 說明），確保仍停留在 version 2 的裝置直接跳級到 version 4 時，PDF 欄位與雙頁欄位皆會補齊，不會漏掉中間的 PDF 欄位遷移。

**Tech Stack:** Flutter/Dart、`sqflite`（真機）、`sqflite_common_ffi`（單元測試）。

## Global Constraints

- 新 3 個欄位皆為 nullable：`dualPageMode: DualPageMode?`（null=`auto`）、`dualPageCoverAlone: bool?`（null=`true`）、`dualPageDirection: DualPageDirection?`（null=`ltr`）——這些「null=預設值」的語意**只在 SQL 層/資料模型層描述**，實際 null 合併解析發生在 `ReaderScreen`（Issue 3 的範圍，見 `spec.md` I-3「Null 預設值解析」），本 issue 不新增任何 `_resolved…` getter。
- `DualPageMode`／`DualPageDirection` 用 `.byName` 直接映射（無回退），比照 `PdfFitMode`／`PdfCropMode` 既有慣例，不建立獨立測試檔——透過 `BookReaderPrefs` 的 round-trip 測試間接驗證。
- SQLite 沒有布林值：`dualPageCoverAlone` 依既有 `publisherStyles` 欄位的慣例，`true→1`／`false→0`／`null→null`。
- `book_reader_prefs.book_id` 是外鍵、`ON DELETE CASCADE`——本 issue 新增的 3 欄位不影響此約束，沿用既有表定義即可。
- `BookReaderPrefsRepository`（`app/lib/reader/book_reader_prefs_repository.dart`）的 `load`/`save` 邏輯完全是 `Map` 驅動，**不需要修改**——這是既有慣例（epic-4 Issue 1 已驗證過），本 issue 也不例外。
- 資料庫 schema 版本目前是 `3`（`app/lib/library/sqlite_library_repository.dart:27`），本 issue 升到 `4`。

---

### Task 1：`DualPageMode`／`DualPageDirection` 列舉 + `BookReaderPrefs` 欄位擴充

**Files:**
- Create：`app/lib/reader/dual_page_mode.dart`
- Create：`app/lib/reader/dual_page_direction.dart`
- Modify：`app/lib/reader/book_reader_prefs.dart`
- Test：`app/test/reader/book_reader_prefs_test.dart`

**Interfaces:**
- Consumes：無（起始工單）
- Produces：`DualPageMode { auto, always, never }`、`DualPageDirection { ltr, rtl }`；`BookReaderPrefs` 新增 `dualPageMode: DualPageMode?`、`dualPageCoverAlone: bool?`、`dualPageDirection: DualPageDirection?` 三個唯讀欄位，供 Task 2（SQL 欄位對應）與 Issue 3+（`_resolved…` getter、Method Channel 契約）使用

- [ ] **Step 1：建立兩個列舉型別檔案**

`app/lib/reader/dual_page_mode.dart`：

```dart
/// PDF 與 EPUB 固定版面橫向雙頁顯示的觸發模式（FR-41）。[auto]
/// 橫向自動啟用雙頁、直向恢復單頁（預設）；[always] 永遠雙頁；[never]
/// 永遠單頁。見 docs/epics/epic-16-dual-page/spec.md「資料模型」。
enum DualPageMode { auto, always, never }
```

`app/lib/reader/dual_page_direction.dart`：

```dart
/// PDF 雙頁顯示時的頁面配對閱讀方向（FR-41，僅 PDF 適用；EPUB 固定版面
/// 由 Readium 依 `page-progression-direction` metadata 自動處理，見
/// docs/epics/epic-16-dual-page/spec.md「資料模型」）。[ltr] 左到右
/// （預設）；[rtl] 右到左（日漫慣例）。
enum DualPageDirection { ltr, rtl }
```

- [ ] **Step 2：撰寫失敗測試——擴充 `book_reader_prefs_test.dart`**

在 `app/test/reader/book_reader_prefs_test.dart` 檔案開頭的 import 區塊新增：

```dart
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
```

在 `test('BookReaderPrefs.empty 所有欄位皆為 null', ...)` 內、`expect(prefs.pdfCropRect, isNull);` 之後新增：

```dart
    expect(prefs.dualPageMode, isNull);
    expect(prefs.dualPageCoverAlone, isNull);
    expect(prefs.dualPageDirection, isNull);
```

在檔案最後一個 `test(...)` 區塊（`copyWith 不傳任何參數時...`）之後、`}` 之前，新增以下 4 個測試：

```dart
  test('雙頁欄位值完全相同的 BookReaderPrefs 視為相等', () {
    const a = BookReaderPrefs(
      dualPageMode: DualPageMode.always,
      dualPageCoverAlone: false,
      dualPageDirection: DualPageDirection.rtl,
    );
    const b = BookReaderPrefs(
      dualPageMode: DualPageMode.always,
      dualPageCoverAlone: false,
      dualPageDirection: DualPageDirection.rtl,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('雙頁欄位任一不同時視為不相等', () {
    const a = BookReaderPrefs(dualPageMode: DualPageMode.always);
    const b = BookReaderPrefs(dualPageMode: DualPageMode.never);
    expect(a, isNot(b));
  });

  test('雙頁欄位的 toMap／fromMap round-trip 保留所有欄位', () {
    const prefs = BookReaderPrefs(
      dualPageMode: DualPageMode.never,
      dualPageCoverAlone: false,
      dualPageDirection: DualPageDirection.rtl,
    );

    final map = prefs.toMap('book-6');
    expect(map['dual_page_mode'], 'never');
    expect(map['dual_page_cover_alone'], 0);
    expect(map['dual_page_direction'], 'rtl');

    final restored = BookReaderPrefs.fromMap(map);
    expect(restored, prefs);
  });

  test('dualPageCoverAlone 為 true／false／null 皆正確 round-trip（避免布林值 0/1 轉換錯誤）',
      () {
    const withTrue = BookReaderPrefs(dualPageCoverAlone: true);
    final trueMap = withTrue.toMap('book-7');
    expect(trueMap['dual_page_cover_alone'], 1);
    expect(BookReaderPrefs.fromMap(trueMap).dualPageCoverAlone, isTrue);

    const withFalse = BookReaderPrefs(dualPageCoverAlone: false);
    final falseMap = withFalse.toMap('book-8');
    expect(falseMap['dual_page_cover_alone'], 0);
    expect(BookReaderPrefs.fromMap(falseMap).dualPageCoverAlone, isFalse);

    const withNull = BookReaderPrefs.empty;
    final nullMap = withNull.toMap('book-9');
    expect(nullMap['dual_page_cover_alone'], isNull);
    expect(BookReaderPrefs.fromMap(nullMap).dualPageCoverAlone, isNull);
  });
```

- [ ] **Step 3：執行測試，確認失敗**

```bash
cd app
flutter test test/reader/book_reader_prefs_test.dart
```

Expected：FAIL——編譯錯誤，`BookReaderPrefs` 沒有 `dualPageMode`/`dualPageCoverAlone`/`dualPageDirection` 具名參數，或 `dual_page_mode.dart`/`dual_page_direction.dart` 找不到（若 Step 1 已建立檔案，錯誤應只來自 `BookReaderPrefs` 建構參數）。

- [ ] **Step 4：修改 `book_reader_prefs.dart` 使測試通過**

在 `app/lib/reader/book_reader_prefs.dart` 檔案開頭 import 區塊（第 1-8 行），於 `import 'app_font.dart';` 之後新增（依現有字母序插入）：

```dart
import 'dual_page_direction.dart';
import 'dual_page_mode.dart';
```

在欄位宣告區塊（原第 34-35 行 `pdfCropMode`/`pdfCropRect` 之後）新增：

```dart
  final DualPageMode? dualPageMode; // null=auto（橫向自動雙頁）
  final bool? dualPageCoverAlone; // null=true（封面獨立，僅 PDF 有效）
  final DualPageDirection? dualPageDirection; // null=ltr（僅 PDF 有效）
```

建構子（原第 37-55 行）在 `this.pdfCropRect,` 之後新增：

```dart
    this.dualPageMode,
    this.dualPageCoverAlone,
    this.dualPageDirection,
```

`toMap()`（原第 60-82 行）在 `'pdf_crop_rect': pdfCropRect?.toJson(),` 之後新增：

```dart
      'dual_page_mode': dualPageMode?.name,
      'dual_page_cover_alone':
          dualPageCoverAlone == null ? null : (dualPageCoverAlone! ? 1 : 0),
      'dual_page_direction': dualPageDirection?.name,
```

`BookReaderPrefs.fromMap()`（原第 84-127 行）在 `pdfCropRect: map['pdf_crop_rect'] == null ? null : PdfCropRect.fromJson(map['pdf_crop_rect'] as String),` 之後新增：

```dart
      dualPageMode: map['dual_page_mode'] == null
          ? null
          : DualPageMode.values.byName(map['dual_page_mode'] as String),
      dualPageCoverAlone: map['dual_page_cover_alone'] == null
          ? null
          : (map['dual_page_cover_alone'] as int) == 1,
      dualPageDirection: map['dual_page_direction'] == null
          ? null
          : DualPageDirection.values
              .byName(map['dual_page_direction'] as String),
```

`operator ==`（原第 129-148 行）在 `other.pdfCropRect == pdfCropRect;` 之前的 `&&` 鏈末尾新增（記得把原本結尾的 `;` 移到新的最後一行）：

```dart
      other.pdfCropRect == pdfCropRect &&
      other.dualPageMode == dualPageMode &&
      other.dualPageCoverAlone == dualPageCoverAlone &&
      other.dualPageDirection == dualPageDirection;
```

`hashCode`（原第 150-169 行）在 `pdfCropRect,` 之後新增：

```dart
        pdfCropRect,
        dualPageMode,
        dualPageCoverAlone,
        dualPageDirection,
      );
```

（移除原本 `pdfCropRect,` 後方緊接的 `);`，改成上面這樣把新欄位插入、`);` 移到最後。）

`copyWith()`（原第 176-215 行）具名參數列表在 `PdfCropRect? pdfCropRect,` 之後新增：

```dart
    DualPageMode? dualPageMode,
    bool? dualPageCoverAlone,
    DualPageDirection? dualPageDirection,
```

`copyWith()` 的回傳建構式在 `pdfCropRect: pdfCropRect ?? this.pdfCropRect,` 之後新增：

```dart
      dualPageMode: dualPageMode ?? this.dualPageMode,
      dualPageCoverAlone: dualPageCoverAlone ?? this.dualPageCoverAlone,
      dualPageDirection: dualPageDirection ?? this.dualPageDirection,
```

- [ ] **Step 5：執行測試，確認通過**

```bash
flutter test test/reader/book_reader_prefs_test.dart
```

Expected：全數 PASS。

- [ ] **Step 6：`flutter analyze`**

```bash
flutter analyze
```

Expected："No issues found!"

- [ ] **Step 7：Commit**

```bash
git add lib/reader/dual_page_mode.dart lib/reader/dual_page_direction.dart lib/reader/book_reader_prefs.dart test/reader/book_reader_prefs_test.dart
git commit -m "feat(epic-16): 新增 DualPageMode/DualPageDirection 列舉與 BookReaderPrefs 雙頁欄位"
```

（此步驟的 `git add` 路徑相對於 `app/` 目錄執行；若在儲存庫根目錄執行，請改用 `app/lib/...`/`app/test/...` 前綴。）

---

### Task 2：`book_reader_prefs` 表 SQLite Schema 升級（version 3 → 4）

**Files:**
- Modify：`app/lib/library/sqlite_library_repository.dart`
- Test：`app/test/library/sqlite_library_repository_test.dart`
- Test：`app/test/reader/book_reader_prefs_repository_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `BookReaderPrefs.toMap()`/`fromMap()` 已包含 `dual_page_mode`/`dual_page_cover_alone`/`dual_page_direction` 三個 key
- Produces：`book_reader_prefs` 表在 schema version 4 下包含全部既有欄位 + 3 個新欄位；全新安裝（`onCreate`）與既有裝置（`onUpgrade`）皆可正確取得完整 schema

- [ ] **Step 1：撰寫失敗測試——擴充既有「全新安裝」測試**

在 `app/test/library/sqlite_library_repository_test.dart` 的 `test('全新安裝的 book_reader_prefs 表包含 PDF 欄位（version 3 起 onCreate 已含括）', ...)` 內，把 `containsAll([...])` 清單擴充為：

```dart
    expect(columnNames, containsAll([
      'pdf_fit_mode',
      'pdf_contrast',
      'pdf_brightness',
      'pdf_bold_strength',
      'pdf_crop_mode',
      'pdf_crop_rect',
      'dual_page_mode',
      'dual_page_cover_alone',
      'dual_page_direction',
    ]));
```

（測試標題保留原樣即可，不強制改字——`containsAll` 斷言本身已經足以驗證新欄位存在，不需要為了改標題而額外異動不相關的文字。）

在檔案最後一個 `test(...)` 區塊（`既有 version 2 裝置升級後...`）之後、`}` 之前，新增以下測試（比照同一個測試的既有寫法，改為模擬 version 3 舊資料庫）：

```dart
  test('既有 version 3 裝置升級後，book_reader_prefs 新增雙頁欄位且既有 PDF 資料不受影響',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('elinkbook_migration_v3_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 3」的舊資料庫：手動以 version 3 當時的
    // schema（含 PDF 欄位、不含雙頁欄位）建立。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 3,
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
              pdf_crop_rect TEXT
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'pdf',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.insert('book_reader_prefs', {
      'book_id': 'b1',
      'pdf_fit_mode': 'fitWidth',
      'pdf_contrast': 10.0,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=3 →
    // newVersion=4），驗證既有 PDF 資料不受影響、且雙頁新欄位可用。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final row = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['pdf_fit_mode'], 'fitWidth'); // 既有 PDF 資料不受影響
    expect(row['pdf_contrast'], 10.0);
    expect(row['dual_page_mode'], isNull); // 新欄位存在且預設 NULL

    // 證明欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'book_reader_prefs',
      {'dual_page_mode': 'always', 'dual_page_cover_alone': 0},
      where: 'book_id = ?',
      whereArgs: ['b1'],
    );
    final updated = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(updated['dual_page_mode'], 'always');
    expect(updated['dual_page_cover_alone'], 0);
  });

  test('既有 version 2 裝置直接升級到 version 4，PDF 欄位與雙頁欄位皆補齊（累加式 onUpgrade 驗證）',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v2_to_v4_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 2」的舊資料庫：手動以 version 2 當時的
    // schema（不含 PDF 欄位、不含雙頁欄位）建立。這是本測試存在的理由——
    // 驗證 onUpgrade 從互斥的 if/else if 改為累加式 if 之後，oldVersion=2
    // 跳級到 newVersion=4 時，PDF 欄位遷移（oldVersion<3）與雙頁欄位遷移
    // （oldVersion<4）兩段都會執行，不會因為只命中其中一個分支而漏掉。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
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
              screen_orientation_override TEXT
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
    await oldDb.insert('book_reader_prefs', {'book_id': 'b1', 'font_size': 18.0});
    await oldDb.close();

    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final columns = await upgraded.database
        .rawQuery('PRAGMA table_info(book_reader_prefs)');
    final columnNames = columns.map((c) => c['name'] as String).toSet();
    expect(
      columnNames,
      containsAll(['pdf_fit_mode', 'dual_page_mode', 'dual_page_cover_alone']),
    );

    final row = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['font_size'], 18.0); // 既有 EPUB 資料不受影響
  });
```

- [ ] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/library/sqlite_library_repository_test.dart
```

Expected：FAIL——「全新安裝」測試因 `dual_page_mode` 等欄位不存在而斷言失敗；兩個新的 migration 測試因升級後仍缺少 `dual_page_mode` 欄位而斷言失敗（`row['dual_page_mode']` 相關斷言，或 `containsAll` 找不到欄位）。

- [ ] **Step 3：修改 `sqlite_library_repository.dart` 使測試通過**

第 27 行版本號：

```dart
      version: 4,
```

第 75-101 行 `_createBookReaderPrefsTable()`，在 `pdf_crop_rect TEXT` 之後新增 3 欄（注意最後一欄不加逗號）：

```dart
  static Future<void> _createBookReaderPrefsTable(Database db) async {
    // 單書版面偏好設定（epic-3-fonts-layout FR-09/FR-10、epic-4-pdf-enhance
    // FR-11、epic-16-dual-page FR-41），與 books 表 1:1 關聯；所有欄位皆為
    // nullable，null 代表未覆寫，見 docs/epics/epic-4-pdf-enhance/spec.md
    // 「資料模型」與 docs/epics/epic-16-dual-page/spec.md「資料模型」。
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
  }
```

在 `_addPdfReaderPrefsColumns()`（原第 103-120 行）之後新增新方法：

```dart
  static Future<void> _addDualPageColumns(Database db) async {
    // 橫向雙頁顯示（epic-16-dual-page FR-41）新增的 3 個欄位，補追加到
    // 既有（version 3 起已存在）的 book_reader_prefs 表，見
    // docs/epics/epic-16-dual-page/spec.md「資料模型」。
    await db.execute(
        'ALTER TABLE book_reader_prefs ADD COLUMN dual_page_mode TEXT');
    await db.execute(
        'ALTER TABLE book_reader_prefs ADD COLUMN dual_page_cover_alone INTEGER');
    await db.execute(
        'ALTER TABLE book_reader_prefs ADD COLUMN dual_page_direction TEXT');
  }
```

`onUpgrade`（原第 57-70 行）改為累加式判斷（**重要**：從互斥的 `if/else if` 改為依序 `if`，否則停留在 version 2 的裝置跳級到 version 4 時只會命中第一個符合的分支、漏掉 PDF 欄位遷移——見上方 Task 2 Step 1 新增的第二個 migration 測試）：

```dart
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // 舊裝置從未有過 book_reader_prefs 表，_createBookReaderPrefsTable
          // 目前的 CREATE TABLE 已包含全部欄位（含 PDF、雙頁），一步到位，
          // 不需要再跑後續的 ALTER TABLE（該表在這之前根本不存在）。
          await _createBookReaderPrefsTable(db);
          return;
        }
        if (oldVersion < 3) {
          // 裝置已經是 version 2：book_reader_prefs 表已存在但缺少 PDF
          // 欄位，只能用 ALTER TABLE 補上。注意這裡改用 if 而非
          // else if——version 2 的裝置跳級到 version 4 時，還需要緊接著
          // 執行下方 oldVersion < 4 的雙頁欄位遷移，兩段都要跑到。
          await _addPdfReaderPrefsColumns(db);
        }
        if (oldVersion < 4) {
          // 裝置已經是 version 3：book_reader_prefs 表已有 PDF 欄位但缺少
          // 雙頁欄位，只能用 ALTER TABLE 補上。
          await _addDualPageColumns(db);
        }
      },
```

- [ ] **Step 4：執行測試，確認通過**

```bash
flutter test test/library/sqlite_library_repository_test.dart
```

Expected：全數 PASS（含既有的「既有 version 2 裝置升級後...」測試——它現在實際上是 oldVersion=2 跳級到 newVersion=4 的情境，累加式 `if` 修正後應繼續通過，不需修改該測試本身）。

- [ ] **Step 5：擴充 `book_reader_prefs_repository_test.dart` 驗證雙頁欄位的 CRUD round-trip**

在 `app/test/reader/book_reader_prefs_repository_test.dart` 的 import 區塊新增：

```dart
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
```

在 `test('save 寫入 PDF 欄位後，load 讀回相同的值', ...)` 之後新增：

```dart
  test('save 寫入雙頁欄位後，load 讀回相同的值', () async {
    const prefs = BookReaderPrefs(
      dualPageMode: DualPageMode.always,
      dualPageCoverAlone: false,
      dualPageDirection: DualPageDirection.rtl,
    );

    await repository.save('b1', prefs);

    expect(await repository.load('b1'), prefs);
  });
```

- [ ] **Step 6：執行測試，確認通過**

```bash
flutter test test/reader/book_reader_prefs_repository_test.dart
```

Expected：全數 PASS（新增的測試本身不需要「先失敗」——`BookReaderPrefsRepository` 的 `load`/`save` 邏輯本就是 `Map` 驅動、無需修改，本步驟純粹是補齊 round-trip 覆蓋率，Step 4 若已通過代表底層 schema 正確，本步驟預期直接 PASS）。

- [ ] **Step 7：全專案回歸測試 + `flutter analyze`**

```bash
flutter test
flutter analyze
```

Expected：`flutter test` 全數 PASS（含 Task 1 與 Task 2 新增的測試，以及既有全部測試不受影響）；`flutter analyze` "No issues found!"。

- [ ] **Step 8：Commit**

```bash
git add lib/library/sqlite_library_repository.dart test/library/sqlite_library_repository_test.dart test/reader/book_reader_prefs_repository_test.dart
git commit -m "feat(epic-16): book_reader_prefs 表升級至 version 4，新增雙頁欄位（累加式 onUpgrade 修正）"
```

---

## Self-Review Notes（撰寫計劃時的自我檢查）

- **spec 覆蓋度**：`spec.md`「資料模型」的 SQL `ALTER TABLE` 定義、`BookReaderPrefs` 新欄位定義、`DualPageMode`/`DualPageDirection` enum 定義三者皆有對應任務（Task 1 涵蓋 Dart 模型與 enum，Task 2 涵蓋 SQL schema）；`issues.md` Issue 2 驗收標準（enum byName 映射、`toMap`/`fromMap` round-trip、EPUB/PDF 欄位互不影響、`BookReaderPrefsRepository` round-trip、migration 後既有資料讀回 NULL、不需真機）皆有對應測試。
- **無佔位符掃描**：所有步驟皆附完整程式碼與確切檔案位置/行號，無 "TODO"/"視情況" 等字樣。
- **型別/介面一致性**：`DualPageMode.auto/always/never`、`DualPageDirection.ltr/rtl` 全文用法一致；`dual_page_mode`/`dual_page_cover_alone`/`dual_page_direction` 三個 SQL 欄位名稱與 `spec.md` 原文逐字一致；`_addDualPageColumns` 函式命名比照既有 `_addPdfReaderPrefsColumns` 慣例。
- **額外發現並主動修正的問題**：既有 `onUpgrade` 的 `if/else if` 互斥結構在只有 2 段遷移（version 1→2、2→3）時沒有問題，但新增第 3 段遷移（3→4）後，若不改為累加式 `if`，會導致「停留在 version 2 的裝置跳級到 version 4」這個真實會發生的情境（使用者長時間未更新 App）漏掉 PDF 欄位遷移。Task 2 已將此改為累加式 `if` 並新增專屬回歸測試驗證，避免此問題在真機上才被發現。
