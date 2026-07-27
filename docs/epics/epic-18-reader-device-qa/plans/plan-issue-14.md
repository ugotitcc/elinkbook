# Issue 14：流式 EPUB 邊距重新設計為上/下/左/右 4 個獨立欄位 實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** 讓流式 EPUB（`FoliateEpubReaderView`／`main.js`）的邊距設定從單一「邊距」滑桿，拆為「上邊界」「下邊界」「左邊界」「右邊界」4 個獨立可調欄位，並修正左右留白隨字級等比例膨脹（`em` 單位）的根因，同時讓上下邊距不再限制僅直排生效。

**架構：** `BookReaderPrefs` 新增 4 個獨立 `double?` 欄位（`marginTop`/`marginBottom`/`marginLeft`/`marginRight`，皆為 px 數值，不像既有 `pageMargins` 需要倍率換算），沿 `ResolvedPreferences` → `FoliateEpubReaderView` → `main.js` 既有透傳管線直送到底。`main.js` 的 `buildOverrideCss()` 改用 `padding-left`/`padding-right`（px，取代原本的 `em`），`applyPreferences()` 的 margin-top/margin-bottom 邏輯改為不分排版方向、統一依這兩個新欄位設定（取代原本「僅直排生效、橫排永遠固定 48px」的既有限制）。既有 `pageMargins` 欄位／`EpubReaderView`／FXL 路徑完全不受影響（依 ADR 0014）。

**Tech Stack：** Flutter/Dart、SQLite（`sqflite`）、Vanilla JS（`main.js`，無建置流程）。

## Global Constraints

- **範圍僅限流式 EPUB**（`FoliateEpubReaderView`／`main.js`）。不修改 `EpubReaderView.dart`／`FxlSettingsSheet`／Readium 原生 `EpubPreferences` 相關程式碼；既有 `pageMargins` 欄位（`BookReaderPrefs.pageMargins`／`ResolvedPreferences.pageMargins`）**保留不變、不刪除**，繼續供 `EpubReaderView` 使用。
- 4 個新欄位**直接以 px 為單位**（不像 `pageMargins` 需要 `_toMultiplier`/`* 15.0` 這類倍率換算）——`ReaderSettingsSheet` 的滑桿數值即為要送出的 `BookReaderPrefs` 欄位值，`main.js` 直接 `${value}px` 使用，不需要任何額外換算層，比照既有 `columnSize`（360-1440px，直接送出）的既有模式，而非比照 `pageMargins`（UI 顯示值與持久化倍率不同）的既有模式。
- `ResolvedPreferences` 的 4 個新欄位維持 **nullable**（`double?`），比照既有 `pageMargins`／`fontSize` 等 8 個 EPUB 字型/排版欄位的既有慣例（見 `resolved_preferences.dart:18-26` 開頭註解：null 時整個 key 省略、交由 `main.js` 內建預設值決定）——**不**比照 `columnMode`/`columnSize` 的 non-nullable 例外模式。
- `main.js` 的 `margin-top`/`margin-bottom` null-fallback 預設值定為 `64`/`16`（延續既有 Issue 4 為修正直排頂端裁切問題而定的數值），且**不再依 `showFooter` 動態調整下邊距**——Issue 7 已把流式 EPUB 頁尾改為浮動疊加層，不再壓縮 WebView 可視高度，Issue 4 當初「頁尾顯示時縮小下邊距」的補償理由已不成立，此為本計劃刻意的簡化（非遺漏）。
- 滑桿範圍/step（0-120px、step 4）為起始建議值，非最終規格，實作階段可依真機視覺效果調整（比照 Issue 2/3 既有慣例）。
- 不修改 `readest/foliate-js` 釘定版本本身（`paginator.js` 等 vendored 檔案），比照本 Epic 既有慣例（ADR 0011）。
- 真機驗收裝置固定為 `3CEF42ECD491687`。

---

## 檔案結構

- **修改：** `app/lib/reader/book_reader_prefs.dart`（新增 4 個欄位）
- **修改：** `app/lib/library/sqlite_library_repository.dart`（schema v13→v14）
- **修改：** `app/lib/reader/resolved_preferences.dart`（新增 4 個欄位）
- **修改：** `app/lib/reader/reader_prefs_manager_impl.dart`（`resolve()` 透傳）
- **修改：** `app/lib/reader/foliate_epub_reader_view.dart`（`pageMargins` 參數換成 4 個新參數）
- **修改：** `app/lib/screens/reader_screen.dart`（`FoliateEpubReaderView(...)` 建構呼叫透傳新欄位）
- **修改：** `app/lib/screens/reader_settings_sheet.dart`（單一「邊距」滑桿拆為 4 個獨立滑桿）
- **修改：** `app/android/app/src/main/assets/foliate/main.js`（`buildOverrideCss()`／`applyPreferences()` 改用新欄位）

---

### Task 1：`BookReaderPrefs` 新增 4 個欄位

**Files:**
- Modify: `app/lib/reader/book_reader_prefs.dart`
- Test: `app/test/reader/book_reader_prefs_test.dart`

**Interfaces:**
- Produces: `BookReaderPrefs.marginTop`/`marginBottom`/`marginLeft`/`marginRight`（皆為 `double?`，px 數值），`toMap()` 對應鍵 `margin_top`/`margin_bottom`/`margin_left`/`margin_right`。

- [ ] **Step 1: 撰寫會失敗的測試**

在 `app/test/reader/book_reader_prefs_test.dart` 新增（緊接既有「`toMap／fromMap round-trip` 保留所有欄位（含 `book_id`）」測試之後）：

```dart
  test('邊距 4 個獨立欄位的 toMap／fromMap round-trip 保留所有欄位', () {
    const prefs = BookReaderPrefs(
      marginTop: 72,
      marginBottom: 20,
      marginLeft: 30,
      marginRight: 30,
    );

    final map = prefs.toMap('book-margin-1');
    expect(map['margin_top'], 72);
    expect(map['margin_bottom'], 20);
    expect(map['margin_left'], 30);
    expect(map['margin_right'], 30);

    final restored = BookReaderPrefs.fromMap(map);
    expect(restored, prefs);
  });

  test('邊距 4 個欄位任一不同時視為不相等', () {
    const a = BookReaderPrefs(marginTop: 64);
    const b = BookReaderPrefs(marginTop: 72);
    expect(a, isNot(b));
  });
```

同時在既有「`BookReaderPrefs.empty` 所有欄位皆為 `null`」測試內新增 4 行：

```dart
    expect(prefs.marginTop, isNull);
    expect(prefs.marginBottom, isNull);
    expect(prefs.marginLeft, isNull);
    expect(prefs.marginRight, isNull);
```

- [ ] **Step 2: 執行測試，確認失敗**

執行：
```bash
cd app && flutter test test/reader/book_reader_prefs_test.dart
```
預期：FAIL——`BookReaderPrefs` 建構子不存在 `marginTop`/`marginBottom`/`marginLeft`/`marginRight` 具名參數，編譯錯誤。

- [ ] **Step 3: 實作**

修改 `app/lib/reader/book_reader_prefs.dart`：

1. 欄位宣告（`pageMargins` 之後）：
```dart
  final double? pageMargins; // 單一數值，四邊同步變動，見 ADR 0005（僅供 EpubReaderView／FXL 使用）

  /// 流式 EPUB 專用的獨立邊距欄位（epic-18-reader-device-qa Issue 14，見
  /// ADR 0014）。皆為 px 數值，不需要倍率換算（比照 columnSize 既有模式，
  /// 非比照 pageMargins 的倍率模式）。不影響 EpubReaderView／FXL 路徑。
  final double? marginTop;
  final double? marginBottom;
  final double? marginLeft;
  final double? marginRight;
```

2. 建構子參數（`this.pageMargins,` 之後）：
```dart
    this.marginTop,
    this.marginBottom,
    this.marginLeft,
    this.marginRight,
```

3. `toMap()`（`'page_margins': pageMargins,` 之後）：
```dart
      'margin_top': marginTop,
      'margin_bottom': marginBottom,
      'margin_left': marginLeft,
      'margin_right': marginRight,
```

4. `fromMap()`（`pageMargins: (map['page_margins'] as num?)?.toDouble(),` 之後）：
```dart
      marginTop: (map['margin_top'] as num?)?.toDouble(),
      marginBottom: (map['margin_bottom'] as num?)?.toDouble(),
      marginLeft: (map['margin_left'] as num?)?.toDouble(),
      marginRight: (map['margin_right'] as num?)?.toDouble(),
```

5. `operator ==`（`other.pageMargins == pageMargins &&` 之後）：
```dart
      other.marginTop == marginTop &&
      other.marginBottom == marginBottom &&
      other.marginLeft == marginLeft &&
      other.marginRight == marginRight &&
```

6. `hashCode`（`pageMargins,` 之後）：
```dart
        marginTop,
        marginBottom,
        marginLeft,
        marginRight,
```

7. `copyWith()` 參數列（`double? pageMargins,` 之後）：
```dart
    double? marginTop,
    double? marginBottom,
    double? marginLeft,
    double? marginRight,
```

8. `copyWith()` 回傳建構（`pageMargins: pageMargins ?? this.pageMargins,` 之後）：
```dart
      marginTop: marginTop ?? this.marginTop,
      marginBottom: marginBottom ?? this.marginBottom,
      marginLeft: marginLeft ?? this.marginLeft,
      marginRight: marginRight ?? this.marginRight,
```

- [ ] **Step 4: 執行測試，確認通過**

執行：
```bash
cd app && flutter test test/reader/book_reader_prefs_test.dart
```
預期：PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/reader/book_reader_prefs.dart app/test/reader/book_reader_prefs_test.dart
git commit -m "feat(epic-18): Issue 14 Task 1 BookReaderPrefs 新增邊距 4 個獨立欄位"
```

---

### Task 2：SQLite schema migration v13 → v14

**Files:**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `BookReaderPrefs`（新欄位需要對應的資料庫欄位才能持久化）。
- Produces: `book_reader_prefs` 表新增 `margin_top REAL`/`margin_bottom REAL`/`margin_left REAL`/`margin_right REAL` 4 個 nullable 欄位，schema `version: 14`。

- [ ] **Step 1: 確認現況**

執行：
```bash
grep -n "version: 13\|_addColumnModeColumns\|column_size REAL" app/lib/library/sqlite_library_repository.dart
```
預期看到 `version: 13`（`sqlite_library_repository.dart:30`）、`_createBookReaderPrefsTable` 的 `CREATE TABLE` 最後一欄為 `column_size REAL`（第 206 行）、`onUpgrade` 內 `if (oldVersion < 13) { await _addColumnModeColumns(db); }`（第 109-115 行）。

- [ ] **Step 2: 撰寫會失敗的 migration round-trip 測試**

在 `app/test/library/sqlite_library_repository_test.dart` 新增（緊接既有測試「既有 version 12 裝置升級到 version 13，book_reader_prefs 新增 column_mode/column_size 且 single_column 舊值清零」之後，`grep -n "既有 version 12 裝置升級到 version 13" app/test/library/sqlite_library_repository_test.dart` 確認行號；本檔案頂層已有共用的 `late SqliteLibraryRepository repository`／`setUp()` fixture 與 `_book()` helper，見檔案第 12/43/45 行）：

```dart
  test('全新安裝的 book_reader_prefs 表包含邊距 4 個欄位（version 14 起 onCreate 已含括）',
      () async {
    await repository.insertBook(_book('b_margins'));
    await repository.database.insert('book_reader_prefs', {
      'book_id': 'b_margins',
      'margin_top': 72.0,
      'margin_bottom': 20.0,
      'margin_left': 30.0,
      'margin_right': 30.0,
    });

    final row = (await repository.database.query('book_reader_prefs',
            where: 'book_id = ?', whereArgs: ['b_margins']))
        .single;
    expect(row['margin_top'], 72.0);
    expect(row['margin_bottom'], 20.0);
    expect(row['margin_left'], 30.0);
    expect(row['margin_right'], 30.0);
  });

  test('既有 version 13 裝置升級到 version 14，book_reader_prefs 新增邊距 4 個欄位，既有 page_margins 值不受影響',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v13_to_v14_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 13」的舊資料庫：手動以 version 13 當時的完整
    // schema（book_reader_prefs 含 column_mode/column_size、不含邊距 4
    // 個欄位）建立，不透過 SqliteLibraryRepository.open()（該方法目前的
    // onCreate 已經是 version 14 的最終 schema），比照既有 v12→v13
    // 遷移測試寫法。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 13,
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
              is_fixed_layout INTEGER,
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
              show_footer INTEGER,
              column_mode TEXT,
              column_size REAL
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
      'page_margins': 1.5,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=13 →
    // newVersion=14），驗證既有 page_margins 值不受影響、邊距 4 個新
    // 欄位存在且可寫入。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final row = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['page_margins'], 1.5); // 既有資料不受影響
    expect(row['margin_top'], isNull); // 新欄位存在且預設 NULL
    expect(row['margin_bottom'], isNull);
    expect(row['margin_left'], isNull);
    expect(row['margin_right'], isNull);

    // 證明新欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'book_reader_prefs',
      {'margin_top': 72.0, 'margin_left': 30.0},
      where: 'book_id = ?',
      whereArgs: ['b1'],
    );
    final updated = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(updated['margin_top'], 72.0);
    expect(updated['margin_left'], 30.0);
  });
```

- [ ] **Step 3: 執行測試，確認失敗**

執行：
```bash
cd app && flutter test test/library/sqlite_library_repository_test.dart --plain-name "邊距 4 個"
```
預期：FAIL——`version: 14` 尚未定義、`margin_top`/`margin_bottom`/`margin_left`/`margin_right` 欄位不存在。

- [ ] **Step 4: 實作**

修改 `app/lib/library/sqlite_library_repository.dart`：

1. `version: 13,` 改為 `version: 14,`（第 30 行）。

2. `_createBookReaderPrefsTable()` 的 `CREATE TABLE`，`column_size REAL` 之後新增：
```dart
        column_mode TEXT,
        column_size REAL,
        margin_top REAL,
        margin_bottom REAL,
        margin_left REAL,
        margin_right REAL
```
（把原本結尾的 `column_size REAL` 後面的右括號往後移，新增 4 欄後才是最後一欄）

3. `onUpgrade` 內，`if (oldVersion < 13) { await _addColumnModeColumns(db); }` 之後新增：
```dart
          if (oldVersion < 14) {
            // epic-18-reader-device-qa Issue 14：邊距 4 個獨立欄位。必須
            // 放在 else 分支內（oldVersion >= 2）——理由同
            // _addColumnModeColumns：oldVersion < 2 時
            // _createBookReaderPrefsTable 已一步到位建表含這 4 個欄位，若
            // 在 else 分支外無條件執行 ALTER TABLE，oldVersion == 1 的
            // 裝置會重複 ALTER TABLE 拋出崩潰。既有 page_margins 欄位不
            // 受影響、不做任何遷移（見 ADR 0014）。
            await _addMarginColumns(db);
          }
```

4. 新增 `_addMarginColumns` static 方法（緊接 `_addColumnModeColumns` 之後）：
```dart
  static Future<void> _addMarginColumns(Database db) async {
    // epic-18-reader-device-qa Issue 14：上/下/左/右邊距 4 個獨立欄位，
    // 補追加到既有（version 2 起已存在）的 book_reader_prefs 表。既有
    // page_margins 欄位不受影響、不遷移既有值（見 ADR 0014，本次新欄位
    // 僅供流式 EPUB 使用，page_margins 繼續供 EpubReaderView／FXL 使用）。
    // 比照 _addColumnModeColumns 既有慣例，僅在表已存在時才執行
    // ALTER TABLE。
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='book_reader_prefs'");
    if (tables.isNotEmpty) {
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN margin_top REAL');
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN margin_bottom REAL');
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN margin_left REAL');
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN margin_right REAL');
    }
  }
```

- [ ] **Step 5: 執行測試，確認通過**

執行：
```bash
cd app && flutter test test/library/sqlite_library_repository_test.dart
```
預期：PASS，全數通過（含既有既有 migration 測試，無回歸）。

- [ ] **Step 6: Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-18): Issue 14 Task 2 SQLite schema v13→v14 新增邊距 4 個欄位"
```

---

### Task 3：`ResolvedPreferences`／`ReaderPrefsManagerImpl` 透傳

**Files:**
- Modify: `app/lib/reader/resolved_preferences.dart`
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart`
- Test: `app/test/reader/reader_prefs_manager_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `BookReaderPrefs.marginTop`/`marginBottom`/`marginLeft`/`marginRight`。
- Produces: `ResolvedPreferences.marginTop`/`marginBottom`/`marginLeft`/`marginRight`（皆 `double?`，直接從 `BookReaderPrefs` 對應欄位透傳，無任何解析/預設值邏輯，比照既有 `pageMargins` 透傳模式）。

- [ ] **Step 1: 撰寫會失敗的測試**

在 `app/test/reader/reader_prefs_manager_test.dart` 找到既有 `expect(resolved.pageMargins, isNull);`（約第 178 行）所在的測試，於同一測試內新增：

```dart
    expect(resolved.marginTop, isNull);
    expect(resolved.marginBottom, isNull);
    expect(resolved.marginLeft, isNull);
    expect(resolved.marginRight, isNull);
```

並在同一個 `group('resolve()（純同步，不需要資料庫/SharedPreferences）', ...)` 內（`setUp()` 已建立 `manager = ReaderPrefsManagerImpl(FakeBookReaderPrefsRepository(), FakeReadingPositionRepository())`，見檔案第 30-37 行）新增一個獨立測試，直接建構 `LoadedPrefs` 驗證有值時的透傳（`resolve()` 是純同步方法，不需要 `manager.load()`，比照既有「全部欄位皆未覆寫時...」等既有測試的既有寫法）：

```dart
    test('BookReaderPrefs 的邊距 4 個欄位正確透傳到 ResolvedPreferences', () {
      final loaded = LoadedPrefs(
        bookPrefs: const BookReaderPrefs(
          marginTop: 72,
          marginBottom: 20,
          marginLeft: 30,
          marginRight: 30,
        ),
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      final resolved = manager.resolve(loaded);
      expect(resolved.marginTop, 72);
      expect(resolved.marginBottom, 20);
      expect(resolved.marginLeft, 30);
      expect(resolved.marginRight, 30);
    });
```

- [ ] **Step 2: 執行測試，確認失敗**

執行：
```bash
cd app && flutter test test/reader/reader_prefs_manager_test.dart
```
預期：FAIL——`ResolvedPreferences` 建構子不存在 `marginTop` 等具名參數、`resolved.marginTop` 存取不到，編譯錯誤。

- [ ] **Step 3: 實作**

修改 `app/lib/reader/resolved_preferences.dart`：

1. 欄位宣告（`final double? pageMargins;` 之後）：
```dart
  final double? marginTop;
  final double? marginBottom;
  final double? marginLeft;
  final double? marginRight;
```

2. 建構子參數（`this.pageMargins,` 之後）：
```dart
    this.marginTop,
    this.marginBottom,
    this.marginLeft,
    this.marginRight,
```

修改 `app/lib/reader/reader_prefs_manager_impl.dart` 的 `resolve()`（`pageMargins: book.pageMargins,` 之後）：
```dart
      marginTop: book.marginTop,
      marginBottom: book.marginBottom,
      marginLeft: book.marginLeft,
      marginRight: book.marginRight,
```

- [ ] **Step 4: 執行測試，確認通過**

執行：
```bash
cd app && flutter test test/reader/reader_prefs_manager_test.dart
```
預期：PASS。

- [ ] **Step 5: 全專案回歸**

執行：
```bash
cd app && flutter analyze
```
預期：`No issues found!`（`ResolvedPreferences` 新增欄位尚未被任何呼叫端使用，不會產生未使用警告，因為是 class 欄位非區域變數）。

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/resolved_preferences.dart app/lib/reader/reader_prefs_manager_impl.dart app/test/reader/reader_prefs_manager_test.dart
git commit -m "feat(epic-18): Issue 14 Task 3 ResolvedPreferences 新增邊距 4 個欄位透傳"
```

---

### Task 4：`FoliateEpubReaderView` 以 4 個新參數取代 `pageMargins`

**Files:**
- Modify: `app/lib/reader/foliate_epub_reader_view.dart`
- Test: `app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `ResolvedPreferences.marginTop`/`marginBottom`/`marginLeft`/`marginRight`（供 Task 5 的 `ReaderScreen` 建構呼叫使用）。
- Produces: `FoliateEpubReaderView` 的 `marginTop`/`marginBottom`/`marginLeft`/`marginRight` 建構參數（皆 `double?`），`buildFoliatePreferencesMap()` 對應輸出 `'marginTop'`/`'marginBottom'`/`'marginLeft'`/`'marginRight'` key（取代原本的 `'pageMargins'` key，`FoliateEpubReaderView` 不再有 `pageMargins` 欄位）。

- [ ] **Step 1: 修改既有測試，確認新斷言先失敗**

修改 `app/test/reader/foliate_epub_reader_view_test.dart` 既有測試「所有非 null 建構參數皆正確出現於 map」：

```dart
    test('所有非 null 建構參數皆正確出現於 map', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.vertical,
        pageTurnMode: PageTurnMode.scroll,
        fontFamily: AppFont.sourceHanSans,
        fontSize: 1.125,
        fontWeight: 1.75,
        lineHeight: 1.6,
        paragraphSpacing: 1.2,
        marginTop: 72,
        marginBottom: 20,
        marginLeft: 30,
        marginRight: 30,
        textAlign: EpubTextAlign.justify,
        publisherStyles: false,
        columnMode: ColumnMode.single,
        columnSize: 600.0,
        showFooter: false,
      );
      expect(buildFoliatePreferencesMap(view), {
        'writingMode': 'vertical',
        'pageTurnMode': 'scroll',
        'fontFamily': 'SourceHanSansTC',
        'fontSize': 1.125,
        'fontWeight': 1.75,
        'lineHeight': 1.6,
        'paragraphSpacing': 1.2,
        'marginTop': 72.0,
        'marginBottom': 20.0,
        'marginLeft': 30.0,
        'marginRight': 30.0,
        'textAlign': 'justify',
        'publisherStyles': false,
        'columnMode': 'single',
        'columnSize': 600.0,
        'showFooter': false,
      });
    });
```

- [ ] **Step 2: 執行測試，確認失敗**

執行：
```bash
cd app && flutter test test/reader/foliate_epub_reader_view_test.dart
```
預期：FAIL——`FoliateEpubReaderView` 建構子不存在 `marginTop`/`marginBottom`/`marginLeft`/`marginRight` 具名參數（仍是 `pageMargins`），編譯錯誤。

- [ ] **Step 3: 實作**

修改 `app/lib/reader/foliate_epub_reader_view.dart`：

1. `buildFoliatePreferencesMap()`（`if (view.pageMargins != null) map['pageMargins'] = view.pageMargins;` 這一行整行替換）：
```dart
  if (view.marginTop != null) map['marginTop'] = view.marginTop;
  if (view.marginBottom != null) map['marginBottom'] = view.marginBottom;
  if (view.marginLeft != null) map['marginLeft'] = view.marginLeft;
  if (view.marginRight != null) map['marginRight'] = view.marginRight;
```

2. `foliatePreferencesChanged()`（`oldView.pageMargins != newView.pageMargins ||` 這一行整行替換）：
```dart
      oldView.marginTop != newView.marginTop ||
      oldView.marginBottom != newView.marginBottom ||
      oldView.marginLeft != newView.marginLeft ||
      oldView.marginRight != newView.marginRight ||
```

3. `FoliateEpubReaderView` 欄位宣告（`final double? pageMargins;` 這一行整行替換）：
```dart
  final double? marginTop;
  final double? marginBottom;
  final double? marginLeft;
  final double? marginRight;
```

4. 建構子參數（`this.pageMargins,` 這一行整行替換）：
```dart
    this.marginTop,
    this.marginBottom,
    this.marginLeft,
    this.marginRight,
```

- [ ] **Step 4: 執行測試，確認通過**

執行：
```bash
cd app && flutter test test/reader/foliate_epub_reader_view_test.dart
```
預期：PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "feat(epic-18): Issue 14 Task 4 FoliateEpubReaderView 以 4 個邊距參數取代 pageMargins"
```

---

### Task 5：`ReaderScreen` 建構呼叫透傳新欄位

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `ResolvedPreferences.marginTop`/`marginBottom`/`marginLeft`/`marginRight`；Task 4 的 `FoliateEpubReaderView.marginTop`/`marginBottom`/`marginLeft`/`marginRight` 建構參數。

- [ ] **Step 1: 確認現況並修正編譯錯誤**

Task 4 完成後，`app/lib/screens/reader_screen.dart` 第 1893 行附近的 `FoliateEpubReaderView(...)` 建構呼叫仍寫著 `pageMargins: resolved.pageMargins,`，此時 `flutter analyze` 會報錯（`FoliateEpubReaderView` 已無 `pageMargins` 具名參數）。執行：
```bash
cd app && flutter analyze
```
預期：出現 `reader_screen.dart` 該行的 "no parameter named 'pageMargins'" 之類錯誤。

- [ ] **Step 2: 修正**

找到 `FoliateEpubReaderView(...)` 建構呼叫內的：
```dart
            pageMargins: resolved.pageMargins,
```
改為：
```dart
            marginTop: resolved.marginTop,
            marginBottom: resolved.marginBottom,
            marginLeft: resolved.marginLeft,
            marginRight: resolved.marginRight,
```

**注意**：`_buildEpubFooter()`（約第 1752 行）與 `EpubReaderView(...)` 建構呼叫（約第 1925 行）內的 `pageMargins: resolved.pageMargins,` **維持不動**——前者是既有的字元數頁碼估算 heuristic，後者是 FXL／Readium 路徑，兩者皆不在本 Issue 範圍內（見 Global Constraints）。

- [ ] **Step 3: 撰寫驗證透傳的測試**

在 `app/test/screens/reader_screen_test.dart` 新增（比照既有欄位透傳測試模式，可放在既有 `columnMode`/`columnSize` 透傳測試附近，`grep -n "columnMode.*columnSize.*透傳\|columnSize.*正確透傳" app/test/screens/reader_screen_test.dart` 找既有先例）：

```dart
  testWidgets('流式 EPUB：邊距 4 個欄位從 ResolvedPreferences 正確透傳到 FoliateEpubReaderView（Issue 14）', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b_foliate_margins',
      const BookReaderPrefs(
        marginTop: 72,
        marginBottom: 20,
        marginLeft: 30,
        marginRight: 30,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_foliate_margins',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    expect(foliateView.marginTop, 72);
    expect(foliateView.marginBottom, 20);
    expect(foliateView.marginLeft, 30);
    expect(foliateView.marginRight, 30);
  });
```

- [ ] **Step 4: 執行測試，確認通過**

執行：
```bash
cd app && flutter test test/screens/reader_screen_test.dart --plain-name "邊距 4 個欄位從 ResolvedPreferences 正確透傳"
```
預期：PASS。

- [ ] **Step 5: 全專案回歸**

執行：
```bash
cd app && flutter analyze
cd app && flutter test
```
預期：`flutter analyze` 顯示 `No issues found!`；`flutter test` 全數通過。

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-18): Issue 14 Task 5 ReaderScreen 透傳邊距 4 個欄位到 FoliateEpubReaderView"
```

---

### Task 6：`ReaderSettingsSheet` 拆為 4 個獨立滑桿

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart`
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `BookReaderPrefs.marginTop`/`marginBottom`/`marginLeft`/`marginRight`。
- Produces: 4 個新 `Key`：`reader_settings_margin_top_slider`/`_decrement`/`_increment`（同前綴規則套用於 `bottom`/`left`/`right`），透過既有 `_buildSliderRow()` 產生。

- [ ] **Step 1: 修改既有測試，確認新斷言先失敗**

修改 `app/test/screens/reader_settings_sheet_test.dart`：

1. 既有測試「初始值正確反映傳入的 `BookReaderPrefs`」（約第 13-76 行）：`pageMargins: 1.6667, // UI 25.0` 這一行改為：
```dart
      marginTop: 72,
      marginBottom: 20,
      marginLeft: 30,
      marginRight: 30,
```
並把該測試裡的：
```dart
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_page_margins_slider')))
          .value,
      25.0,
    );
```
改為：
```dart
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_top_slider')))
          .value,
      72.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_bottom_slider')))
          .value,
      20.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_left_slider')))
          .value,
      30.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_right_slider')))
          .value,
      30.0,
    );
```

2. 既有測試「任一欄位為 `null` 時，滑桿顯示原型範例預設值」：把
```dart
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_page_margins_slider')))
          .value,
      15.0,
    );
```
改為：
```dart
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_top_slider')))
          .value,
      64.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_bottom_slider')))
          .value,
      16.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_left_slider')))
          .value,
      24.0,
    );
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_margin_right_slider')))
          .value,
      24.0,
    );
```

3. 新增互動測試（比照既有「點擊字型大小 + 按鈕後」測試模式）：
```dart
  testWidgets('點擊上邊界 + 按鈕後，onChanged 帶入 marginTop+4 且其他欄位不變',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(marginTop: 64, marginLeft: 24),
      (prefs) => result = prefs,
    );

    await tester
        .tap(find.byKey(const Key('reader_settings_margin_top_increment')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.marginTop, 68.0);
    expect(result!.marginLeft, 24.0, reason: '未被觸碰的欄位應維持原值');
  });
```

- [ ] **Step 2: 執行測試，確認失敗**

執行：
```bash
cd app && flutter test test/screens/reader_settings_sheet_test.dart
```
預期：FAIL——`Key('reader_settings_margin_top_slider')` 等找不到（滑桿尚未拆分），且 `BookReaderPrefs` 尚不支援 `marginTop` 具名參數若 Task 1 未完成也會編譯失敗（本 Task 依賴 Task 1 已完成）。

- [ ] **Step 3: 實作**

修改 `app/lib/screens/reader_settings_sheet.dart`：

本 Task 移除既有的 `_pageMargins` State 欄位（連同其滑桿 UI 一併移除，取代為下方 4 個新欄位）——`BookReaderPrefs.pageMargins` 欄位本身不受影響（`ReaderSettingsSheet` 之後單純不再寫入它，比照 `FxlSettingsSheet` 從未寫入它的既有狀態，見 ADR 0014「後果」段）。

1. State 欄位：**移除** `late double _pageMargins;` 這一行，改為：
```dart
  late double _marginTop;
  late double _marginBottom;
  late double _marginLeft;
  late double _marginRight;
```

2. 預設值常數：**移除** `static const _defaultPageMargins = 15.0;` 這一行，改為：
```dart
  static const _defaultMarginTop = 64.0;
  static const _defaultMarginBottom = 16.0;
  static const _defaultMarginLeft = 24.0;
  static const _defaultMarginRight = 24.0;
```

3. `initState()`：**移除**
```dart
    _pageMargins = widget.prefs.pageMargins != null
        ? (widget.prefs.pageMargins! * 15.0).roundToDouble()
        : _defaultPageMargins;
```
改為：
```dart
    _marginTop = widget.prefs.marginTop ?? _defaultMarginTop;
    _marginBottom = widget.prefs.marginBottom ?? _defaultMarginBottom;
    _marginLeft = widget.prefs.marginLeft ?? _defaultMarginLeft;
    _marginRight = widget.prefs.marginRight ?? _defaultMarginRight;
```

4. `didUpdateWidget()` 內（同樣在 `setState()` 區塊內）：**移除**
```dart
        _pageMargins = widget.prefs.pageMargins != null
            ? (widget.prefs.pageMargins! * 15.0).roundToDouble()
            : _defaultPageMargins;
```
改為：
```dart
        _marginTop = widget.prefs.marginTop ?? _defaultMarginTop;
        _marginBottom = widget.prefs.marginBottom ?? _defaultMarginBottom;
        _marginLeft = widget.prefs.marginLeft ?? _defaultMarginLeft;
        _marginRight = widget.prefs.marginRight ?? _defaultMarginRight;
```

5. `_notifyChanged()`：**移除** `pageMargins: _toMultiplier(_pageMargins, 15.0),` 這一行（`_pageMargins` 已不存在，且 `pageMargins` 欄位之後不再由本畫面寫入，讓它繼續維持 `BookReaderPrefs` 建構子預設的 `null`），改為新增：
```dart
      marginTop: _marginTop,
      marginBottom: _marginBottom,
      marginLeft: _marginLeft,
      marginRight: _marginRight,
```

6. `build()` 內，找到既有：
```dart
                _buildSliderRow(
                  keyPrefix: 'reader_settings_page_margins',
                  label: '邊距',
                  value: _pageMargins,
                  min: 0,
                  max: 50,
                  step: 1,
                  displayValue: _pageMargins.round().toString(),
                  onChanged: (v) => setState(() {
                    _pageMargins = v;
                    _notifyChanged();
                  }),
                ),
```
整段改為 4 個獨立滑桿：
```dart
                _buildSliderRow(
                  keyPrefix: 'reader_settings_margin_top',
                  label: '上邊界',
                  value: _marginTop,
                  min: 0,
                  max: 120,
                  step: 4,
                  displayValue: _marginTop.round().toString(),
                  onChanged: (v) => setState(() {
                    _marginTop = v;
                    _notifyChanged();
                  }),
                ),
                _buildSliderRow(
                  keyPrefix: 'reader_settings_margin_bottom',
                  label: '下邊界',
                  value: _marginBottom,
                  min: 0,
                  max: 120,
                  step: 4,
                  displayValue: _marginBottom.round().toString(),
                  onChanged: (v) => setState(() {
                    _marginBottom = v;
                    _notifyChanged();
                  }),
                ),
                _buildSliderRow(
                  keyPrefix: 'reader_settings_margin_left',
                  label: '左邊界',
                  value: _marginLeft,
                  min: 0,
                  max: 120,
                  step: 4,
                  displayValue: _marginLeft.round().toString(),
                  onChanged: (v) => setState(() {
                    _marginLeft = v;
                    _notifyChanged();
                  }),
                ),
                _buildSliderRow(
                  keyPrefix: 'reader_settings_margin_right',
                  label: '右邊界',
                  value: _marginRight,
                  min: 0,
                  max: 120,
                  step: 4,
                  displayValue: _marginRight.round().toString(),
                  onChanged: (v) => setState(() {
                    _marginRight = v;
                    _notifyChanged();
                  }),
                ),
```

- [ ] **Step 4: 執行測試，確認通過**

執行：
```bash
cd app && flutter test test/screens/reader_settings_sheet_test.dart
```
預期：PASS。

- [ ] **Step 5: 全專案回歸**

執行：
```bash
cd app && flutter analyze
cd app && flutter test
```
預期：`flutter analyze` 顯示 `No issues found!`；`flutter test` 全數通過。

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "feat(epic-18): Issue 14 Task 6 ReaderSettingsSheet 邊距拆為上下左右 4 個獨立滑桿"
```

---

### Task 7：`main.js` 改用 4 個獨立邊距欄位

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes: `prefs.marginTop`/`marginBottom`/`marginLeft`/`marginRight`（Task 4 的 `buildFoliatePreferencesMap()` 輸出鍵名）。

- [ ] **Step 1: 確認現況**

執行：
```bash
grep -n "pageMargins\|margin-top\|margin-bottom" app/android/app/src/main/assets/foliate/main.js
```
預期看到 `buildOverrideCss()` 內第 99-100 行的 `pageMargins` 分支、`applyPreferences()` 內第 172-211 行的直排/橫排 margin-top/margin-bottom 邏輯（見本文件開頭「調查結論」的行號引用）。

- [ ] **Step 2: 修改 `buildOverrideCss()`**

找到：
```js
  if (typeof prefs.pageMargins === 'number') {
    rules.push(`body { padding: 0 ${1.5 * prefs.pageMargins}em !important; }`)
  }
```
改為：
```js
  // epic-18 Issue 14：左右邊距改用獨立的 px 欄位（取代原本混用 em 的
  // pageMargins），字級調整不再連帶影響左右留白（根因見 design.md
  // 「第三輪真機使用回報」項目 4）。null 時不覆寫（沿用書本/瀏覽器
  // 預設，比照既有 pageMargins null 時的既有行為）。
  if (typeof prefs.marginLeft === 'number') {
    rules.push(`body { padding-left: ${prefs.marginLeft}px !important; }`)
  }
  if (typeof prefs.marginRight === 'number') {
    rules.push(`body { padding-right: ${prefs.marginRight}px !important; }`)
  }
```

- [ ] **Step 3: 修改 `applyPreferences()` 的上下邊距邏輯**

找到（約第 172-211 行）整段：
```js
  // epic-18 Issue 4：直排上下邊距。...
  if (currentWritingMode === 'vertical') {
    // pageMargins 是既有的頁邊距倍率偏好...
    const marginMultiplier = typeof prefs.pageMargins === 'number' ? prefs.pageMargins : 1
    // 上邊距：...
    const marginTopPx = Math.round(64 * marginMultiplier)
    // 下邊距：...
    const marginBottomPx = prefs.showFooter === false
      ? Math.round(64 * marginMultiplier)
      : Math.round(16 * marginMultiplier)
    view.renderer.setAttribute('margin-top', `${marginTopPx}px`)
    view.renderer.setAttribute('margin-bottom', `${marginBottomPx}px`)
  } else {
    // 橫排：還原 paginator.js 內建預設值。...
    view.renderer.setAttribute('margin-top', '48px')
    view.renderer.setAttribute('margin-bottom', '48px')
  }
```
整段改為：
```js
  // epic-18 Issue 14：上/下邊距改用獨立的 marginTop/marginBottom 欄位
  // （取代 Issue 4 引入的 pageMargins 倍率公式），且不再限制僅直排生效
  // ——橫排模式現在也依這兩個欄位動態設定，取代原本「橫排永遠固定
  // paginator.js 內建 48px」的既有限制（見 design.md「第三輪真機使用
  // 回報」項目 4）。因為兩個方向現在共用同一套邏輯，不再需要「切換
  // 排版方向時重設回 48px」這層既有的持久性補償（原本 Issue 4 的
  // if/else 分支正是為了這個補償而存在）。
  // 未設定時的預設值（64px/16px）延續 Issue 4 當初為修正直排頂端裁切
  // 問題而定的數值；marginBottom 不再依 showFooter 動態調整——Issue 7
  // 已把頁尾改為浮動疊加層，不再壓縮 WebView 可視高度，「頁尾顯示時
  // 縮小下邊距」的補償理由已不成立，此為刻意簡化。
  const marginTopPx = typeof prefs.marginTop === 'number' ? prefs.marginTop : 64
  const marginBottomPx = typeof prefs.marginBottom === 'number' ? prefs.marginBottom : 16
  view.renderer.setAttribute('margin-top', `${marginTopPx}px`)
  view.renderer.setAttribute('margin-bottom', `${marginBottomPx}px`)
```

- [ ] **Step 4: 執行 Dart 端全部既有測試回歸**

執行：
```bash
cd app && flutter analyze
cd app && flutter test
```
預期：`flutter analyze` 顯示 `No issues found!`；`flutter test` 全數通過（`main.js` 變更本身無 JS 單元測試，比照 Issue 4/5/6/7/9 既有慣例，此步驟只確認 Dart 端未受影響）。

- [ ] **Step 5: Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "feat(epic-18): Issue 14 Task 7 main.js 邊距改用上下左右 4 個獨立欄位"
```

---

### Task 8：真機驗收

**Files:** 無程式碼異動（純真機人工驗證）。

**Interfaces:**
- Consumes: Task 1-7 完成後的完整實作。
- Produces: 驗收結果記錄（供合併前的程式碼審查／`issues.md` Issue 14 狀態更新引用）。

- [ ] **Step 1: 安裝最新 debug APK 至真機 `3CEF42ECD491687`**

```bash
cd app && flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 2: 驗證 4 個方向獨立可調**

1. 開啟一本流式 EPUB，於「版面設定」分別調整「上邊界」「下邊界」「左邊界」「右邊界」4 個滑桿。
2. 確認四個方向的留白各自獨立變化、互不影響（例如把「左邊界」調到最大，「上邊界」「下邊界」「右邊界」不受影響）。
3. 記錄：Pass/Fail + 截圖佐證。

- [ ] **Step 3: 驗證橫排模式上下邊距生效**

1. 切換為橫排，分別調整「上邊界」「下邊界」滑桿。
2. 確認橫排模式下上下留白會隨滑桿變化（修正前橫排永遠固定 48px、不受影響）。
3. 記錄：Pass/Fail。

- [ ] **Step 4: 驗證字級放大後左右留白不再失控膨脹**

1. 把字型大小滑桿調到高值（例如 60px 以上）。
2. 確認左右留白維持固定（不隨字級等比例膨脹）——此為本 Issue 修正的原始根因（`em` 改 `px`）。
3. 記錄：Pass/Fail + 截圖佐證（可與 diagnose session 稍早的字級截圖對照）。

- [ ] **Step 5: FXL 回歸確認**

1. 開啟一本 FXL（固定版面）EPUB，確認其既有行為（本 Issue 不觸碰 `EpubReaderView`／`pageMargins`／FXL 路徑）未受影響。
2. 記錄：Pass/Fail。

- [ ] **Step 6: 記錄驗收結果**

供後續程式碼審查與 `docs/epics/epic-18-reader-device-qa/issues.md` Issue 14 狀態更新引用。

---

## 相關佐證

- `design.md`「第三輪真機使用回報」項目 4
- ADR 0005（`docs/adr/0005-epub-page-margins-single-value.md`）
- ADR 0014（`docs/adr/0014-foliate-epub-independent-margins.md`）
- `docs/prd.md`「版面控制項」原始需求（獨立的上/下/左/右邊距滑桿）
