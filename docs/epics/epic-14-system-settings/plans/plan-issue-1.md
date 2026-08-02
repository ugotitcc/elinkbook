# Epic 14 Issue 1 — 自訂字型資料模型 + 二進位解析器 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 `custom_fonts` 表與 `book_reader_prefs.font_family` 資料遷移（SQLite v15→v16）、把 `fontFamily` 的 Dart 型別從封閉列舉 `AppFont?` 改為任意字串 `String?`（貫穿既有讀寫管線，行為完全不變）、新增手刻 TTF/OTF `name` table 二進位解析器。純 Dart + SQLite，不涉及原生程式碼，不需要真實裝置。本 Issue 完成後**尚未**新增任何使用者可見的新功能（字型管理畫面是 Issue 2 的範圍）——這是刻意的垂直切片邊界，本 Issue 純粹是行為保留的資料層基礎建設。

**Architecture:** 沿用本專案既有的「累加式 `if (oldVersion < N)`、全新安裝與既有裝置升級兩條路徑皆須涵蓋」migration 模式（`epic-6` Issue 1 的全新安裝防禦教訓）。`fontFamily` 型別遷移沿用「型別在型別擁有者改、呼叫端維持傳遞不動」的既有慣例——多數呼叫端（`reader_prefs_manager_impl.dart`、`reader_screen.dart`）是單純傳遞，型別兩端同步改變後不需要任何程式碼異動。

**Tech Stack:** Flutter/Dart、`sqflite`（真機）、`sqflite_common_ffi`（單元測試）。

## Global Constraints

- `custom_fonts.family_name` 有 `UNIQUE` 約束——Issue 2 的重複阻擋邏輯可以直接依賴這個資料庫層保證，但本 Issue 不涉及任何插入邏輯（`FontManagementScreen` 是 Issue 2 範圍），此處只建表。
- `font_family` 這個 SQL 欄位本身**型別不變**（一直是 `TEXT`），本 Issue 只遷移「既有資料的內容格式」（`AppFont.name` 字串 → 實際 family name 字串），不需要 `ALTER TABLE` 改欄位型別（SQLite 本來就沒有嚴格欄位型別）。
- `fontFamily` 的 Dart 型別遷移範圍：`BookReaderPrefs`／`ResolvedPreferences`／`FoliateEpubReaderView`／`ReaderSettingsSheet` 四處宣告型別的地方都要改；`reader_prefs_manager_impl.dart`（`resolve()` 第 153 行 `fontFamily: book.fontFamily,`）與 `reader_screen.dart`（第 1808 行 `fontFamily: resolved.fontFamily,`）是純傳遞，兩端型別同步改為 `String?` 後**不需要修改這兩處程式碼**，僅需確認 `flutter analyze` 仍乾淨。
- `foliate_epub_reader_view.dart:103` 目前寫 `map['fontFamily'] = view.fontFamily!.familyName;`（呼叫 `AppFont` 的 `.familyName` extension getter）。型別改為 `String?` 後，值本身已經是 family name 字串，此行**簡化**為 `map['fontFamily'] = view.fontFamily!;`——這是型別遷移的自然結果，不是額外行為變更。
- `reader_settings_sheet.dart` 的字型下拉選單本 Issue **只做型別置換，不做內容擴充**：選項仍然只列出內建 5 款字型（下拉選單的 `value` 改用 `font.familyName`〔`String`〕而非 `font`〔`AppFont`〕本身），合併自訂字型清單是 Issue 2 的範圍。
- 二進位解析器是全新、獨立的純函式模組，本 Issue 不會被任何既有程式碼呼叫（呼叫端在 Issue 2 的上傳流程），純粹先建好並以單元測試驗證正確性。
- 測試 fixture：`app/test/fixtures/sample.ttf`（已存在於版本控制中，「KingHwa\_OldSong」字型，約 36MB）已驗證其 `name` table 的 Platform 3／EncodingID 1／nameID=1 記錄值為 `"KingHwa_OldSong"`（以 Python 手動解析二進位結構核實，見本計畫撰寫過程紀錄），作為解析器「真實檔案」測試案例；Mac Platform 1 記錄與畸形檔案兩種邊界案例改用測試檔案內以 `BytesBuilder` 手刻的最小合成 sfnt 位元組陣列，不額外新增二進位 fixture 檔案。
- 資料庫 schema 版本目前是 `15`（`app/lib/library/sqlite_library_repository.dart:30`），本 Issue 升到 `16`。

---

### Task 1：`custom_fonts` 表 + `font_family` 既有資料遷移（SQLite v15→v16）

**Files:**
- Modify：`app/lib/library/sqlite_library_repository.dart`
- Test：`app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes：無（起始工單）
- Produces：`custom_fonts` 表（`id`／`display_name`／`family_name UNIQUE`／`font_uri`）；`book_reader_prefs.font_family` 既有 5 種列舉值字串資料轉換為對應 family name 字串。供 Issue 2 的 `FontManagementScreen` 使用。

- [ ] **Step 1：撰寫失敗測試——全新安裝的 `custom_fonts` 表**

在 `app/test/library/sqlite_library_repository_test.dart` 最後一個 `test(...)` 區塊（`既有 version 14 裝置升級到 version 15...`，約第 1901-2017 行）之後、`group('detectAndCacheEpubLayout', ...)` 之前，新增：

```dart
  test('全新安裝的 custom_fonts 表可用（version 16 起 onCreate 已含括）', () async {
    await repository.database.insert('custom_fonts', {
      'display_name': '我的字型',
      'family_name': 'MyCustomFont',
      'font_uri': 'content://example/font1',
    });

    final row =
        (await repository.database.query('custom_fonts')).single;
    expect(row['display_name'], '我的字型');
    expect(row['family_name'], 'MyCustomFont');
    expect(row['font_uri'], 'content://example/font1');
  });

  test('custom_fonts.family_name 具備 UNIQUE 約束', () async {
    await repository.database.insert('custom_fonts', {
      'display_name': 'A',
      'family_name': 'DupFamily',
      'font_uri': 'content://example/a',
    });

    expect(
      () => repository.database.insert('custom_fonts', {
        'display_name': 'B',
        'family_name': 'DupFamily',
        'font_uri': 'content://example/b',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
```

- [ ] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/library/sqlite_library_repository_test.dart
```

Expected：FAIL——`custom_fonts` 表不存在，`no such table: custom_fonts`。

- [ ] **Step 3：新增 `_createCustomFontsTable` 並接上 `onCreate`／`onUpgrade`**

`app/lib/library/sqlite_library_repository.dart` 第 30 行版本號：

```dart
      version: 16,
```

`onCreate`（第 62-65 行 `await _createBookReaderPrefsTable(db);` 等 4 行）之後新增：

```dart
        await _createCustomFontsTable(db);
```

`onUpgrade` 最後一段（第 181-188 行 `if (oldVersion < 11) { ... await _addEpubLayoutColumn(db); }`）之後新增：

```dart
        if (oldVersion < 16) {
          // epic-14-system-settings Issue 1：自訂字型清單新增的全新資料表。
          // 與 bookmarks（oldVersion < 8）／highlights／notes（oldVersion <
          // 9）比照同一原則——任何 oldVersion < 16 的裝置都必然還沒有這張
          // 表，無條件建立即可，不需要判斷「表是否已存在」。
          await _createCustomFontsTable(db);
        }
```

在 `_addFullscreenColumn`（第 430-440 行）之後、`Database get database => _db;`（第 444 行）之前新增：

```dart
  static Future<void> _createCustomFontsTable(Database db) async {
    // 自訂字型清單（epic-14-system-settings FR-35），見
    // docs/epics/epic-14-system-settings/spec.md「字型管理模組」。字型檔案
    // 本身不落地複本（ADR 0021），font_uri 存 content:// URI。
    await db.execute('''
      CREATE TABLE custom_fonts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        display_name TEXT NOT NULL,
        family_name TEXT NOT NULL UNIQUE,
        font_uri TEXT NOT NULL
      )
    ''');
  }
```

- [ ] **Step 4：執行測試，確認通過**

```bash
flutter test test/library/sqlite_library_repository_test.dart
```

Expected：新增的 2 個測試 PASS；既有測試（含既有 version 14→15 等 migration 測試）不受影響，全數維持 PASS。

- [ ] **Step 5：撰寫失敗測試——既有裝置升級時 `font_family` 既有資料正確轉換**

在剛新增的兩個測試之後繼續新增：

```dart
  test('既有 version 15 裝置升級到 version 16，book_reader_prefs.font_family 既有列舉值字串轉換為 family name，NULL 不受影響',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v15_to_v16_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 15」的舊資料庫：手動以 version 15 當時的完整
    // schema（book_reader_prefs 含 fullscreen、不含 custom_fonts 表）建立，
    // font_family 欄位存的是舊格式的 AppFont 列舉值字串，比照既有
    // v14→v15 遷移測試寫法。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 15,
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
              column_size REAL,
              margin_top REAL,
              margin_bottom REAL,
              margin_left REAL,
              margin_right REAL,
              fullscreen INTEGER
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍（黑體）',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.insert('books', {
      'id': 'b2',
      'title': '既有書籍（未設字型）',
      'format': 'epub',
      'filePath': 'content://example/b2',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.insert('book_reader_prefs', {
      'book_id': 'b1',
      'font_family': 'sourceHanSans',
    });
    await oldDb.insert('book_reader_prefs', {
      'book_id': 'b2',
      'font_family': null,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=15 →
    // newVersion=16），驗證既有列舉值字串正確轉換、NULL 不受影響、
    // custom_fonts 表已建立。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final row1 = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row1['font_family'], 'SourceHanSansTC');

    final row2 = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b2']))
        .single;
    expect(row2['font_family'], isNull);

    final customFontsTables = await upgraded.database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='custom_fonts'");
    expect(customFontsTables, isNotEmpty);
  });

  test('font_family 全部 5 種既有列舉值字串皆正確轉換為對應 family name', () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_font_family_all_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 15,
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
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              progress REAL NOT NULL DEFAULT 0,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE book_reader_prefs (
              book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
              font_family TEXT
            )
          ''');
        },
      ),
    );
    const legacyValues = [
      'sourceHanSans',
      'sourceHanSerif',
      'guanKiapTsingKhai',
      'taiwanPearl',
      'genRyuMinTW',
    ];
    for (var i = 0; i < legacyValues.length; i++) {
      await oldDb.insert('books', {
        'id': 'b$i',
        'title': '書 $i',
        'format': 'epub',
        'filePath': 'content://example/b$i',
        'source': 'local',
        'progress': 0.0,
        'groupName': '未分類',
        'createTime': 1000,
        'lastReadTime': 1000,
      });
      await oldDb.insert('book_reader_prefs',
          {'book_id': 'b$i', 'font_family': legacyValues[i]});
    }
    await oldDb.close();

    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    const expected = [
      'SourceHanSansTC',
      'SourceHanSerifTC',
      'GuanKiapTsingKhai',
      'TaiwanPearl',
      'GenRyuMinTW',
    ];
    for (var i = 0; i < legacyValues.length; i++) {
      final row = (await upgraded.database.query('book_reader_prefs',
              where: 'book_id = ?', whereArgs: ['b$i']))
          .single;
      expect(row['font_family'], expected[i], reason: 'index $i');
    }
  });
```

- [ ] **Step 6：執行測試，確認失敗**

```bash
flutter test test/library/sqlite_library_repository_test.dart
```

Expected：FAIL——`font_family` 欄位值仍是舊格式（`'sourceHanSans'` 而非 `'SourceHanSansTC'`）。

- [ ] **Step 7：新增 `_migrateFontFamilyValues` 並接上 `onUpgrade`**

`onUpgrade` 的 `else` 分支（第 73-135 行），在 `if (oldVersion < 15) { ... await _addFullscreenColumn(db); }`（第 126-134 行）之後新增：

```dart
          if (oldVersion < 16) {
            // epic-14-system-settings Issue 1：font_family 型別由 AppFont
            // 封閉列舉字串改為任意 family name 字串（決策 2），既有 5
            // 種列舉值資料需逐筆轉換。必須放在 else 分支內（oldVersion
            // >= 2，即 book_reader_prefs 表已存在）——oldVersion < 2 時
            // 該表剛由 _createBookReaderPrefsTable 全新建立，不會有任何
            // 舊格式資料需要轉換。
            await _migrateFontFamilyValues(db);
          }
```

`_createCustomFontsTable`（Step 3 新增的方法）之後繼續新增：

```dart
  static Future<void> _migrateFontFamilyValues(Database db) async {
    // book_reader_prefs.font_family 型別由 AppFont 封閉列舉字串改為任意
    // family name 字串（epic-14-system-settings 決策 2），既有 5 種列舉
    // 值資料需逐筆轉換為對應的實際 family name（取自 app_font.dart 現行
    // AppFontFamilyName.familyName），NULL 不受影響。
    const legacyToFamilyName = {
      'sourceHanSans': 'SourceHanSansTC',
      'sourceHanSerif': 'SourceHanSerifTC',
      'guanKiapTsingKhai': 'GuanKiapTsingKhai',
      'taiwanPearl': 'TaiwanPearl',
      'genRyuMinTW': 'GenRyuMinTW',
    };
    for (final entry in legacyToFamilyName.entries) {
      await db.update(
        'book_reader_prefs',
        {'font_family': entry.value},
        where: 'font_family = ?',
        whereArgs: [entry.key],
      );
    }
  }
```

- [ ] **Step 8：執行測試，確認通過**

```bash
flutter test test/library/sqlite_library_repository_test.dart
```

Expected：全數 PASS。

- [ ] **Step 9：`flutter analyze` + Commit**

```bash
flutter analyze
git add lib/library/sqlite_library_repository.dart test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-14): custom_fonts 表 + font_family 既有資料遷移（v15→v16）"
```

Expected：`flutter analyze` "No issues found!"。

---

### Task 2：`fontFamily` 型別遷移貫穿既有管線（`AppFont?` → `String?`，行為不變）

**Files:**
- Modify：`app/lib/reader/book_reader_prefs.dart`
- Modify：`app/lib/reader/resolved_preferences.dart`
- Modify：`app/lib/reader/foliate_epub_reader_view.dart`
- Modify：`app/lib/screens/reader_settings_sheet.dart`
- Test：`app/test/reader/book_reader_prefs_test.dart`
- Test：`app/test/reader/reader_prefs_manager_test.dart`
- Test：`app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes：Task 1 的 SQLite 資料已轉換為新格式字串，`toMap`/`fromMap` 需同步改為直接讀寫字串（不再透過 `AppFont.values.byName`）
- Produces：`BookReaderPrefs.fontFamily`／`ResolvedPreferences.fontFamily`／`FoliateEpubReaderView.fontFamily` 皆為 `String?`；`reader_settings_sheet.dart` 字型下拉選單型別同步改為 `String?`，選項內容不變（仍只列內建 5 款）；供 Issue 2 的 `FontManagementScreen` 與擴充後的字型選單使用

- [ ] **Step 1：撰寫失敗測試——`BookReaderPrefs.fontFamily` 改為 `String?`**

`app/test/reader/book_reader_prefs_test.dart` 第 46、51、94 行，把 `fontFamily: AppFont.sourceHanSans`／`AppFont.taiwanPearl` 改為對應的 family name 字串：

```dart
      fontFamily: 'SourceHanSansTC',
```

```dart
      fontFamily: 'SourceHanSansTC',
```

```dart
      fontFamily: 'TaiwanPearl',
```

（`app_font.dart` 的 import 若因此變成未使用，一併移除；若檔案內仍有其他 `AppFont` 用途則保留。）

- [ ] **Step 2：執行測試，確認失敗**

```bash
flutter test test/reader/book_reader_prefs_test.dart
```

Expected：FAIL——編譯錯誤或型別不符（`BookReaderPrefs` 建構子的 `fontFamily` 參數仍是 `AppFont?`，收到 `String` 型別實參）。

- [ ] **Step 3：修改 `book_reader_prefs.dart`**

第 1 行 `import 'app_font.dart';` 移除（`fontFamily` 型別遷移後此檔案不再需要 `AppFont`）。

第 21 行：

```dart
  final String? fontFamily;
```

第 104 行 `toMap()`：

```dart
      'font_family': fontFamily,
```

第 140-142 行 `fromMap()`：

```dart
      fontFamily: map['font_family'] as String?,
```

第 279 行 `copyWith()` 具名參數：

```dart
    String? fontFamily,
```

（`operator ==`／`hashCode`／`copyWith` 回傳式中的 `fontFamily` 比較/賦值寫法不需改動——皆是型別無關的直接比較/賦值。）

- [ ] **Step 4：執行測試，確認通過**

```bash
flutter test test/reader/book_reader_prefs_test.dart
```

Expected：全數 PASS。

- [ ] **Step 5：撰寫失敗測試——`ResolvedPreferences.fontFamily` 改為 `String?`**

`app/test/reader/reader_prefs_manager_test.dart` 第 176 行 `expect(resolved.fontFamily, isNull);` 維持不動（`isNull` 斷言與型別無關）；額外新增一個非 null 情境測試（若既有測試檔案沒有涵蓋，於同一 `test(...)` 群組內新增）：

```dart
  test('resolve() 正確傳遞單書 fontFamily 字串值', () async {
    await manager.saveBookPrefs(
        'b1', const BookReaderPrefs(fontFamily: 'SourceHanSansTC'));
    final loaded = await manager.load('b1');

    expect(manager.resolve(loaded).fontFamily, 'SourceHanSansTC');
  });
```

（依既有測試檔案的 `manager`／`saveBookPrefs`／`load` 實際變數名稱與既有測試寫法調整，若已有等義測試則不必重複新增。）

- [ ] **Step 6：執行測試，確認失敗**

```bash
flutter test test/reader/reader_prefs_manager_test.dart
```

Expected：FAIL——`BookReaderPrefs(fontFamily: 'SourceHanSansTC')` 型別不符（`ResolvedPreferences`／`BookReaderPrefs` 仍宣告 `AppFont?`，此步驟先改 `ResolvedPreferences`，`BookReaderPrefs` 已於 Step 3 改完）。

- [ ] **Step 7：修改 `resolved_preferences.dart`**

第 29 行：

```dart
  final String? fontFamily;
```

第 1 行 `import 'app_font.dart';` 若因此無其他用途則移除（需先確認檔案內是否還有其他 `AppFont` 型別欄位——目前只有 `fontFamily` 使用，其餘為 `WritingMode`／`double` 等，故可移除）。

- [ ] **Step 8：執行測試，確認通過**

```bash
flutter test test/reader/reader_prefs_manager_test.dart
```

Expected：全數 PASS（`reader_prefs_manager_impl.dart:153` 的 `fontFamily: book.fontFamily,` 純傳遞寫法本身不需修改，兩端型別已同步為 `String?`）。

- [ ] **Step 9：修改 `foliate_epub_reader_view.dart`**

第 169 行：

```dart
  final String? fontFamily;
```

第 103 行（簡化，型別遷移後值本身已是 family name 字串，不再需要 `.familyName`）：

```dart
  if (view.fontFamily != null) map['fontFamily'] = view.fontFamily!;
```

第 1 行附近若有 `import 'app_font.dart';` 且移除 `AppFont` 型別後無其他用途，一併移除（需先確認檔案內 `AppFont` 是否還有其他用途，若有則保留 import）。

- [ ] **Step 10：`flutter analyze`，確認 `reader_screen.dart`／`reader_prefs_manager_impl.dart` 無需修改**

```bash
flutter analyze
```

Expected：`reader_screen.dart:1808`（`fontFamily: resolved.fontFamily,`）與 `reader_prefs_manager_impl.dart:153`（`fontFamily: book.fontFamily,`）皆為純傳遞，型別兩端同步改為 `String?` 後應自動維持型別正確，`flutter analyze` 對這兩處不應有任何新增警告。若有，回頭檢查是否遺漏其他型別宣告點。

- [ ] **Step 11：撰寫失敗測試——`reader_settings_sheet.dart` 字型下拉選單改用 `String?`**

`app/test/screens/reader_settings_sheet_test.dart` 第 15、31-35、231、236 行：

```dart
      fontFamily: 'SourceHanSerifTC',
```

```dart
    expect(
      tester
          .widget<DropdownButton<String?>>(
              find.byKey(const Key('reader_settings_font_family')))
          .value,
      'SourceHanSerifTC',
    );
```

```dart
      const BookReaderPrefs(fontFamily: 'TaiwanPearl'),
```

```dart
    tester.widget<DropdownButton<String?>>(dropdown).onChanged!(null);
```

- [ ] **Step 12：執行測試，確認失敗**

```bash
flutter test test/screens/reader_settings_sheet_test.dart
```

Expected：FAIL——`reader_settings_sheet.dart` 仍宣告 `DropdownButton<AppFont?>` 與 `late AppFont? _fontFamily`，與測試傳入的 `String` 型別不符。

- [ ] **Step 13：修改 `reader_settings_sheet.dart`**

第 49 行：

```dart
  late String? _fontFamily;
```

第 422-435 行（`value:` 改用 `font.familyName`，泛型改 `String?`，選項內容不變，仍只列內建 5 款——合併自訂字型清單留給 Issue 2）：

```dart
          DropdownButton<String?>(
            key: const Key('reader_settings_font_family'),
            value: _fontFamily,
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('使用書本內建字型'),
              ),
              ...AppFont.values.map(
                (font) => DropdownMenuItem<String?>(
                  value: font.familyName,
                  child: Text(_fontDisplayName(font)),
                ),
              ),
            ],
            onChanged: (value) => setState(() {
              _fontFamily = value;
              _notifyChanged();
            }),
          ),
```

（`_fontDisplayName(AppFont font)` 函式簽章本身不變——`AppFont.values.map` 疊代時仍拿得到 `font` 這個 `AppFont` 實例本身供 `_fontDisplayName` 使用，只是 `DropdownMenuItem.value` 改存 `font.familyName` 字串；`app_font.dart` 的 import 保留，`AppFont.values`／`_fontDisplayName` 仍需要它。）

- [ ] **Step 14：執行測試，確認通過**

```bash
flutter test test/screens/reader_settings_sheet_test.dart
```

Expected：全數 PASS。

- [ ] **Step 15：全專案回歸測試 + `flutter analyze`**

```bash
flutter test
flutter analyze
```

Expected：`flutter test` 全數 PASS（含本 Task 新增/修改的測試，以及既有全部測試不受影響——特別留意任何其他直接建構 `BookReaderPrefs(fontFamily: AppFont....)` 的既有測試檔案，若有遺漏會在此步驟才浮現，需回頭比照 Step 1/11 補改）；`flutter analyze` "No issues found!"。

- [ ] **Step 16：Commit**

```bash
git add lib/reader/book_reader_prefs.dart lib/reader/resolved_preferences.dart lib/reader/foliate_epub_reader_view.dart lib/screens/reader_settings_sheet.dart test/reader/book_reader_prefs_test.dart test/reader/reader_prefs_manager_test.dart test/screens/reader_settings_sheet_test.dart
git commit -m "refactor(epic-14): fontFamily 型別由 AppFont 封閉列舉改為 String（行為不變）"
```

---

### Task 3：手刻 TTF/OTF `name` table 二進位解析器

**Files:**
- Create：`app/lib/reader/font_name_parser.dart`
- Test：`app/test/reader/font_name_parser_test.dart`

**Interfaces:**
- Consumes：無（純函式，不依賴本 Epic 其他任何模組）
- Produces：`String? parseFontFamilyName(Uint8List bytes)`——供 Issue 2 的 `FontManagementScreen` 上傳流程呼叫，找不到可用 family name 時回傳 `null`（呼叫端負責退回檔名，不在此函式範圍內）

- [ ] **Step 1：撰寫失敗測試——真實字型檔案（Platform 3 Unicode）**

新建 `app/test/reader/font_name_parser_test.dart`：

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/font_name_parser.dart';

/// 手刻最小合成 sfnt 位元組陣列，僅含一張 `name` table（其餘 sfnt table
/// 皆省略——解析器只讀取 table directory 定位 `name` table，不理會其他
/// table 內容，省略對解析結果無影響）。
Uint8List _buildSfntWithNameTable(List<_NameRecord> records) {
  final strings = <List<int>>[];
  final recordBytes = BytesBuilder();
  var stringOffset = 0;
  for (final r in records) {
    final bytes = r.bytes;
    recordBytes.add(_u16(r.platformId));
    recordBytes.add(_u16(r.encodingId));
    recordBytes.add(_u16(r.languageId));
    recordBytes.add(_u16(r.nameId));
    recordBytes.add(_u16(bytes.length));
    recordBytes.add(_u16(stringOffset));
    strings.add(bytes);
    stringOffset += bytes.length;
  }

  final nameTable = BytesBuilder();
  nameTable.add(_u16(0)); // format
  nameTable.add(_u16(records.length)); // count
  nameTable.add(_u16(6 + records.length * 12)); // stringOffset
  nameTable.add(recordBytes.toBytes());
  for (final s in strings) {
    nameTable.add(s);
  }
  final nameTableBytes = nameTable.toBytes();

  const sfntHeaderLen = 12;
  const tableRecordLen = 16;
  final nameTableStart = sfntHeaderLen + tableRecordLen;

  final result = BytesBuilder();
  result.add(_u32(0x00010000)); // sfnt version
  result.add(_u16(1)); // numTables
  result.add(_u16(0)); // searchRange（解析器不使用，任意值）
  result.add(_u16(0)); // entrySelector
  result.add(_u16(0)); // rangeShift
  result.add('name'.codeUnits); // tag
  result.add(_u32(0)); // checksum（解析器不驗證，任意值）
  result.add(_u32(nameTableStart)); // offset
  result.add(_u32(nameTableBytes.length)); // length
  result.add(nameTableBytes);
  return result.toBytes();
}

class _NameRecord {
  final int platformId;
  final int encodingId;
  final int languageId;
  final int nameId;
  final List<int> bytes;
  _NameRecord(this.platformId, this.encodingId, this.languageId, this.nameId,
      this.bytes);
}

List<int> _u16(int value) => [(value >> 8) & 0xff, value & 0xff];
List<int> _u32(int value) => [
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];

List<int> _utf16be(String s) {
  final bytes = <int>[];
  for (final code in s.codeUnits) {
    bytes.add((code >> 8) & 0xff);
    bytes.add(code & 0xff);
  }
  return bytes;
}

void main() {
  test('真實字型檔案（app/test/fixtures/sample.ttf，KingHwa_OldSong）正確解析出 family name',
      () async {
    final bytes = await File('test/fixtures/sample.ttf').readAsBytes();

    expect(parseFontFamilyName(bytes), 'KingHwa_OldSong');
  });

  test('Platform 3（Windows）Unicode nameID=1 記錄優先於 Platform 1（Mac）記錄',
      () {
    final bytes = _buildSfntWithNameTable([
      _NameRecord(1, 0, 0, 1, 'MacName'.codeUnits),
      _NameRecord(3, 1, 0x0409, 1, _utf16be('WindowsName')),
    ]);

    expect(parseFontFamilyName(bytes), 'WindowsName');
  });

  test('僅有 Platform 1（Mac）nameID=1 記錄時，回退使用該記錄', () {
    final bytes = _buildSfntWithNameTable([
      _NameRecord(1, 0, 0, 1, 'MacOnlyName'.codeUnits),
    ]);

    expect(parseFontFamilyName(bytes), 'MacOnlyName');
  });

  test('無 nameID=1 記錄時，回退使用 nameID=4（Full Name）', () {
    final bytes = _buildSfntWithNameTable([
      _NameRecord(3, 1, 0x0409, 4, _utf16be('FullNameOnly')),
    ]);

    expect(parseFontFamilyName(bytes), 'FullNameOnly');
  });

  test('無 nameID=1/4，回退使用 nameID=6（PostScript Name）', () {
    final bytes = _buildSfntWithNameTable([
      _NameRecord(3, 1, 0x0409, 6, _utf16be('PostScriptNameOnly')),
    ]);

    expect(parseFontFamilyName(bytes), 'PostScriptNameOnly');
  });

  test('name table 完全沒有可用記錄（例如僅有 nameID=2 子家族名稱）時回傳 null',
      () {
    final bytes = _buildSfntWithNameTable([
      _NameRecord(3, 1, 0x0409, 2, _utf16be('Regular')),
    ]);

    expect(parseFontFamilyName(bytes), isNull);
  });

  test('sfnt table directory 找不到 name table 時回傳 null', () {
    final result = BytesBuilder();
    result.add(_u32(0x00010000));
    result.add(_u16(1)); // numTables
    result.add(_u16(0));
    result.add(_u16(0));
    result.add(_u16(0));
    result.add('cmap'.codeUnits); // 只有 cmap，沒有 name
    result.add(_u32(0));
    result.add(_u32(28));
    result.add(_u32(4));
    result.add([0, 0, 0, 0]);

    expect(parseFontFamilyName(result.toBytes()), isNull);
  });

  test('二進位結構損壞（過短、不足以構成合法 sfnt 標頭）時回傳 null，不拋出例外',
      () {
    expect(parseFontFamilyName(Uint8List.fromList([1, 2, 3])), isNull);
    expect(parseFontFamilyName(Uint8List(0)), isNull);
  });
}
```

- [ ] **Step 2：執行測試，確認失敗**

```bash
cd app
flutter test test/reader/font_name_parser_test.dart
```

Expected：FAIL——`package:elinkbook/reader/font_name_parser.dart` 找不到（尚未建立）。

- [ ] **Step 3：建立 `font_name_parser.dart`**

```dart
import 'dart:convert';
import 'dart:typed_data';

/// 手刻最小化 TTF/OTF `name` table 二進位解析器，取得字型的實際 family
/// name（epic-14-system-settings FR-35，見
/// docs/epics/epic-14-system-settings/design.md 決策 1／spec.md「字型管理
/// 模組」）。不引入第三方套件——只需要解析 `name` table 這一個子集合，
/// 比照本專案「foliate-js 釘定複製、TXT 引擎自訂輕量解析」的既有慣例
/// （不為小範圍、格式明確的問題引入完整字型渲染函式庫依賴）。
///
/// 解碼優先順序：Platform 3（Windows）Unicode BMP（encodingID
/// 1／10）、nameID=1（Font Family）→ Platform 1（Macintosh），nameID=1 →
/// nameID=4（Full Name）→ nameID=6（PostScript Name）。找不到任何可用記錄，
/// 或二進位結構不足以構成合法 sfnt 標頭／name table 時回傳 `null`（呼叫端
/// 負責退回檔名邏輯，不在此函式範圍內）。
String? parseFontFamilyName(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);

  int? nameTableOffset;
  int? nameTableLength;
  try {
    if (bytes.length < 12) return null;
    final numTables = data.getUint16(4);
    const headerLen = 12;
    const recordLen = 16;
    if (bytes.length < headerLen + numTables * recordLen) return null;
    for (var i = 0; i < numTables; i++) {
      final recordOffset = headerLen + i * recordLen;
      final tag = ascii.decode(
          bytes.sublist(recordOffset, recordOffset + 4),
          allowInvalid: true);
      if (tag == 'name') {
        nameTableOffset = data.getUint32(recordOffset + 8);
        nameTableLength = data.getUint32(recordOffset + 12);
        break;
      }
    }
  } catch (_) {
    return null;
  }
  if (nameTableOffset == null) return null;

  try {
    if (nameTableOffset + 6 > bytes.length) return null;
    final count = data.getUint16(nameTableOffset + 2);
    final stringAreaOffset =
        nameTableOffset + data.getUint16(nameTableOffset + 4);
    if (nameTableLength != null &&
        nameTableOffset + nameTableLength > bytes.length) {
      return null;
    }

    String? macCandidate;
    String? fullNameCandidate;
    String? postScriptCandidate;

    for (var i = 0; i < count; i++) {
      final recordOffset = nameTableOffset + 6 + i * 12;
      if (recordOffset + 12 > bytes.length) break;
      final platformId = data.getUint16(recordOffset);
      final languageIdOrUnused = data.getUint16(recordOffset + 4);
      final nameId = data.getUint16(recordOffset + 6);
      final length = data.getUint16(recordOffset + 8);
      final offset = data.getUint16(recordOffset + 10);
      final strStart = stringAreaOffset + offset;
      if (strStart + length > bytes.length) continue;
      final raw = bytes.sublist(strStart, strStart + length);

      String decoded;
      if (platformId == 3) {
        decoded = _decodeUtf16Be(raw);
      } else if (platformId == 1) {
        decoded = ascii.decode(raw, allowInvalid: true);
      } else {
        continue;
      }
      if (decoded.isEmpty) continue;

      if (nameId == 1) {
        // Platform 3（Windows）優先於 Platform 1（Mac），找到 Windows
        // 記錄立刻回傳；Mac 記錄先暫存，全部記錄掃完都沒有 Windows
        // 記錄時才使用。
        if (platformId == 3) return decoded;
        macCandidate ??= decoded;
      } else if (nameId == 4) {
        fullNameCandidate ??= decoded;
      } else if (nameId == 6) {
        postScriptCandidate ??= decoded;
      }
      // ignore: unused_local_variable
      languageIdOrUnused;
    }

    return macCandidate ?? fullNameCandidate ?? postScriptCandidate;
  } catch (_) {
    return null;
  }
}

String _decodeUtf16Be(List<int> bytes) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add((bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(units);
}
```

- [ ] **Step 4：執行測試，確認通過**

```bash
flutter test test/reader/font_name_parser_test.dart
```

Expected：全數 PASS（含讀取真實 36MB `sample.ttf` fixture 的測試——執行時間可能明顯長於其他純記憶體測試，屬預期現象，非效能異常）。

- [ ] **Step 5：全專案回歸測試 + `flutter analyze`**

```bash
flutter test
flutter analyze
```

Expected：全數 PASS，`flutter analyze` "No issues found!"。

- [ ] **Step 6：Commit**

```bash
git add lib/reader/font_name_parser.dart test/reader/font_name_parser_test.dart
git commit -m "feat(epic-14): 手刻 TTF/OTF name table 二進位解析器"
```

---

## Self-Review Notes（撰寫計劃時的自我檢查）

- **spec 覆蓋度**：`spec.md`「字型管理模組」的 `custom_fonts` 表定義、`fontFamily` 型別遷移、解碼優先順序（Platform 3→Platform 1→nameID 4/6→回退檔名）三者皆有對應任務；`issues.md` Issue 1 驗收標準（migration 全新安裝/升級皆驗證、Unicode/Mac 兩種記錄解析、畸形檔案退回檔名）皆有對應測試。「退回檔名」邏輯本身留給 Issue 2（上傳流程呼叫端），本 Issue 的 `parseFontFamilyName` 只需在無法決定時回傳 `null`，已於函式文件註解明確標註責任邊界。
- **型別遷移的完整性排查**：以 `grep -rln "\.fontFamily\b"` 找出全部 9 個引用檔案，逐一核對每處是純傳遞（型別同步後零程式碼異動：`reader_prefs_manager_impl.dart`／`reader_screen.dart`）或需要實際型別宣告異動（`book_reader_prefs.dart`／`resolved_preferences.dart`／`foliate_epub_reader_view.dart`／`reader_settings_sheet.dart`），避免遺漏任何一處造成編譯失敗；3 個測試檔案（`book_reader_prefs_test.dart`／`reader_prefs_manager_test.dart`／`reader_settings_sheet_test.dart`）已知的既有 `AppFont.xxx` 建構呼叫皆已列出確切行號待改，Step 15 的全專案回歸測試作為最後防線，補抓任何本計畫撰寫時遺漏的呼叫點。
- **測試 fixture 策略**：`app/test/fixtures/sample.ttf`（已存在版本控制、KingHwa_OldSong 字型）用 Python 手動解析二進位結構核實其 Platform 3／nameID=1 記錄值為 `"KingHwa_OldSong"`，作為解析器「真實檔案」測試案例的斷言依據，非憑空假設；其餘編碼優先順序/邊界案例改用測試檔案內手刻的合成 sfnt 位元組陣列，避免新增多個大型二進位 fixture 檔案。
- **無佔位符掃描**：所有步驟皆附完整程式碼與確切檔案位置/行號，無 "TODO"/"視情況" 等字樣。
- **型別/介面一致性**：`custom_fonts` 表欄位命名（`display_name`／`family_name`／`font_uri`）與 `spec.md`「新增的資料模型」章節逐字一致；`_migrateFontFamilyValues`／`_createCustomFontsTable` 函式命名比照既有 `_addFullscreenColumn`／`_addEpubLayoutColumn` 慣例；`parseFontFamilyName` 為頂層純函式（非包在類別內），比照本專案既有 `hitTestZoneIndex()`／`pageRenderScale()` 等純函式慣例。
