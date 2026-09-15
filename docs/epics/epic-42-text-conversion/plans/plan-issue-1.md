# Epic 42 Issue 1 — 資料模型＋全域/單書 UI 入口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 為簡繁轉換（FR-48）建立資料模型與雙層（全域預設＋單書覆寫）UI 入口——`BookReaderPrefs.textConversionOverride`／`ReadingDefaults.textConversion`／`resolveTextConversion()` 三個型別/函式介面，供 Issue 2-5 消費；並在「閱讀預設值」全域畫面與「版面設定」單書 Bottom Sheet（流式／FXL 兩種）加上對應選擇器。切換此偏好目前尚不會改變畫面文字（轉換效果由 Issue 2／3 接上），本 Issue 只交付「可正確持久化的偏好設定管線＋UI」。

**Architecture:** 比照專案既有「全域 `ReadingDefaults` 欄位＋單書 `BookReaderPrefs` 覆寫欄位＋`book.override ?? global.value` 雙層解析」模式（`pageTurnModeOverride`／`screenOrientationOverride` 已是此模式的既有先例）。新增一個獨立的頂層純函式 `resolveTextConversion()`（非併入 `ReaderPrefsManagerImpl.resolve()`／`ResolvedPreferences`），因為 Issue 3-5 的呼叫點（書架畫面、全文檢索結果清單等）多數不持有完整 `ResolvedPreferences`，只持有 `BookReaderPrefs`＋`GlobalReaderPrefs`，比照既有 `resolveZoneActions()` 頂層純函式先例。

**Tech Stack:** Flutter/Dart（`flutter_test`）、SQLite（`sqflite`，`book_reader_prefs` 表 schema 遷移 v25→v26）、`SharedPreferences`（全域偏好）。

**Spec:** `docs/epics/epic-42-text-conversion/issues.md` Issue 1（另見 `docs/epics/epic-42-text-conversion/spec.md`、`docs/adr/0032-text-conversion-taiwan-phrases-with-piecewise-offset-map.md`〔取代 ADR 0030，本 Issue 資料模型/UI 範圍不受此次轉換演算法改版影響〕、`docs/adr/0031-text-conversion-dual-runtime-dictionary-not-opencc-js.md`）。

## Global Constraints

- `TextConversionMode`（Issue 0 已定案，`app/lib/reader/text_conversion_mode.dart`：`original`／`toTraditional`／`toSimplified`）的型別與 enum 名稱字串是既有穩定介面，本 Issue 不得更動。
- `BookReaderPrefs.textConversionOverride`／`ReadingDefaults.textConversion`／`resolveTextConversion()` 的型別與函式簽章是 Issue 2-5 直接依賴消費的介面，本 Issue 完成後不得隨意改名或調整參數順序（比照 plan-issue-0.md 對 `TextConversionMode`／`convertText()` 的既有承諾）。
- `BookReaderPrefs` 新增欄位一律 nullable、`null`＝未覆寫；`copyWith()` 是 `newValue ?? this.value` 語意，不支援明確清成 `null`——任何需要把該欄位清回 `null`（例如單書設定畫面選「使用全域預設」）的呼叫端，必須用整列字面量建構（`BookReaderPrefs(...)`），不得用 `copyWith()`（見 `book_reader_prefs.dart` `copyWith()` 既有文件註解）。
- `ReadingDefaults` 新增欄位一律 non-nullable，`ReadingDefaults()`／`.initial()` 提供硬編碼預設值 `TextConversionMode.original`。
- SQLite `book_reader_prefs` 表新增欄位的遷移程式碼，必須放在 `sqlite_library_repository.dart` 既有 `else`（`oldVersion >= 2`）分支內的 `if (oldVersion < 26)`，不得放在 if/else 區塊外（否則 `oldVersion == 1` 裝置升級會對剛建好、已含新欄位的表重複 `ALTER TABLE` 拋出崩潰，比照 plan-issue-0.md 引用的既有慣例）。
- `PdfSettingsSheet` 不新增此欄位（PDF 不適用簡繁轉換 UI，見 `epic.md` Discovery 結論）。

---

## File Structure

- Modify: `app/lib/reader/book_reader_prefs.dart` — 新增 `textConversionOverride` 欄位（`toMap`/`fromMap`/`copyWith`/`==`/`hashCode`/`reflowableEpubFields()`）。
- Modify: `app/test/reader/book_reader_prefs_test.dart` — 對應新欄位測試。
- Modify: `app/lib/library/sqlite_library_repository.dart` — SQLite v25→v26 遷移。
- Modify: `app/test/library/sqlite_library_repository_test.dart` — 遷移測試。
- Modify: `app/lib/reader/reading_defaults.dart` — 新增 `textConversion` 欄位。
- Modify: `app/test/reader/reading_defaults_test.dart` — 對應新欄位測試。
- Create: `app/lib/reader/resolve_text_conversion.dart` — `resolveTextConversion()` 純函式。
- Create: `app/test/reader/resolve_text_conversion_test.dart` — 對應測試。
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart` — 全域 `textConversion` 的 SharedPreferences 讀寫。
- Modify: `app/test/reader/reader_prefs_manager_test.dart` — 對應測試。
- Modify: `app/lib/screens/reading_defaults_screen.dart` — 全域三態選擇器 UI。
- Modify: `app/test/screens/reading_defaults_screen_test.dart` — 對應 widget test。
- Modify: `app/lib/screens/reader_settings_sheet.dart` — 流式 EPUB 四態覆寫選擇器 UI。
- Modify: `app/test/screens/reader_settings_sheet_test.dart` — 對應 widget test。
- Modify: `app/lib/screens/fxl_settings_sheet.dart` — FXL 四態覆寫選擇器 UI＋新建構參數 `showTextConversion`。
- Modify: `app/test/screens/fxl_settings_sheet_test.dart` — 對應 widget test。
- Modify: `app/lib/screens/reader_screen.dart` — `_openFxlSettings()` 依格式判斷傳入 `showTextConversion`。
- Modify: `app/test/screens/reader_screen_test.dart` — 對應 widget test。

---

### Task 1: `BookReaderPrefs` 新增 `textConversionOverride` 欄位

**Files:**
- Modify: `app/lib/reader/book_reader_prefs.dart`
- Test: `app/test/reader/book_reader_prefs_test.dart`

**Interfaces:**
- Consumes: `app/lib/reader/text_conversion_mode.dart` 的 `TextConversionMode`（Issue 0）。
- Produces: `BookReaderPrefs.textConversionOverride`（`TextConversionMode?`），供 Task 4 `resolveTextConversion()`、Task 7/8 UI 消費。

- [ ] **Step 1: 修改測試檔，新增/擴充失敗測試**

在 `app/test/reader/book_reader_prefs_test.dart` 頂部 import 區塊新增：

```dart
import 'package:elinkbook/reader/text_conversion_mode.dart';
```

找到第 16-44 行的 `'BookReaderPrefs.empty 所有欄位皆為 null'` 測試，在 `expect(prefs.pdfPageTurnAnimation, isNull);` 後新增一行：

```dart
    expect(prefs.textConversionOverride, isNull);
```

找到第 256-260 行 `'換頁動畫欄位不同時視為不相等'` 測試之後（審查修正 M-3：原指示插入點恰好夾在「換頁動畫相等」與「換頁動畫不相等」兩個成對測試中間，打斷既有欄位的成對測試排列，改插在這組測試全部結束之後），新增：

```dart
  test('textConversionOverride 值相同的 BookReaderPrefs 視為相等', () {
    const a = BookReaderPrefs(
      textConversionOverride: TextConversionMode.toTraditional,
    );
    const b = BookReaderPrefs(
      textConversionOverride: TextConversionMode.toTraditional,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('textConversionOverride 不同時視為不相等', () {
    const a = BookReaderPrefs(
      textConversionOverride: TextConversionMode.toTraditional,
    );
    const b = BookReaderPrefs(
      textConversionOverride: TextConversionMode.toSimplified,
    );
    expect(a, isNot(b));
  });

```

找到第 448-458 行的 `'letterSpacing 為具體數值／null 皆正確 toMap／fromMap round-trip'` 測試，在其後（第 459 行空行後）新增：

```dart
  test('textConversionOverride 為具體值／null 皆正確 toMap／fromMap round-trip', () {
    const withValue =
        BookReaderPrefs(textConversionOverride: TextConversionMode.toSimplified);
    final valueMap = withValue.toMap('book1');
    expect(valueMap['text_conversion_override'], 'toSimplified');
    expect(BookReaderPrefs.fromMap(valueMap).textConversionOverride,
        TextConversionMode.toSimplified);

    const withNull = BookReaderPrefs();
    final nullMap = withNull.toMap('book1');
    expect(nullMap['text_conversion_override'], isNull);
    expect(BookReaderPrefs.fromMap(nullMap).textConversionOverride, isNull);
  });

```

找到第 475-485 行的 `'copyWith 更新 pdfPageTurnAnimation 時，其餘欄位保留原值'` 測試，在其後（第 486 行空行後）新增：

```dart
  test('copyWith 更新 textConversionOverride 時，其餘欄位保留原值', () {
    const original = BookReaderPrefs(
      fontSize: 18,
      textConversionOverride: TextConversionMode.original,
    );
    final updated = original.copyWith(
      textConversionOverride: TextConversionMode.toTraditional,
    );

    expect(updated.fontSize, 18);
    expect(updated.textConversionOverride, TextConversionMode.toTraditional);
  });

```

找到第 501-527 行 `'fromMap 對未知的列舉名稱字串安全降級為 null...'` 測試，在 `..['pdf_page_turn_animation'] = 'not_a_real_enum_value';` 後補上分號前的新一行（把該行結尾的 `;` 移到新增行）：

```dart
      ..['pdf_page_turn_animation'] = 'not_a_real_enum_value'
      ..['text_conversion_override'] = 'not_a_real_enum_value';
```

並在 `expect(restored.pdfPageTurnAnimation, isNull);` 後新增：

```dart
    expect(restored.textConversionOverride, isNull);
```

找到第 529 行 `reflowableEpubFields()` 測試的標題字串，將 `'其餘 20 個流式 EPUB 欄位保留'` 改為 `'其餘 21 個流式 EPUB 欄位保留'`；在該測試的 `BookReaderPrefs(...)` 建構參數最後一行 `pdfPageTurnAnimation: PdfPageTurnAnimation.slide,` 後新增：

```dart
      textConversionOverride: TextConversionMode.toTraditional,
```

並在 `// 20 個保留欄位。` 註解區塊（`expect(filtered.columnSize, 800);` 之後、`// 11 個強制清空欄位。` 之前）新增：

```dart
    expect(filtered.textConversionOverride, TextConversionMode.toTraditional);
```

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/reader/book_reader_prefs_test.dart`
Expected: 編譯錯誤（`textConversionOverride`／`text_conversion_override` 不存在於 `BookReaderPrefs`），或執行期斷言失敗。

- [ ] **Step 3: 修改 `book_reader_prefs.dart` 加入新欄位**

在 import 區塊（`screen_orientation_setting.dart` 之後、`writing_mode.dart` 之前）新增：

```dart
import 'text_conversion_mode.dart';
```

在 `fullscreen` 欄位宣告（第 84 行）之後新增：

```dart

  /// 簡繁顯示轉換覆寫（FR-48，全域/單書雙層解析，見 `resolveTextConversion()`）。
  /// null=使用全域預設（`ReadingDefaults.textConversion`）。
  final TextConversionMode? textConversionOverride;
```

在建構子參數列（`this.fullscreen,` 之後）新增：

```dart
    this.textConversionOverride,
```

在 `toMap()` 的 return map（`'fullscreen': fullscreen == null ? null : (fullscreen! ? 1 : 0),` 之後）新增：

```dart
      'text_conversion_override': textConversionOverride?.name,
```

在 `fromMap()` 的建構參數列（`fullscreen: map['fullscreen'] == null ? null : (map['fullscreen'] as int) == 1,` 之後）新增：

```dart
      textConversionOverride: enumByNameOrNull(
          TextConversionMode.values,
          map['text_conversion_override'] as String?),
```

在 `operator ==`（`other.fullscreen == fullscreen &&` 之後）新增：

```dart
      other.textConversionOverride == textConversionOverride;
```

（並把原本 `other.fullscreen == fullscreen;` 行尾的 `;` 改為 `&&`）

在 `hashCode` 的 `Object.hashAll([...])` 列表（`fullscreen,` 之後）新增：

```dart
        textConversionOverride,
```

在 `copyWith()` 參數列（`bool? fullscreen,` 之後）新增：

```dart
    TextConversionMode? textConversionOverride,
```

在 `copyWith()` 的 return 建構（`fullscreen: fullscreen ?? this.fullscreen,` 之後）新增：

```dart
      textConversionOverride:
          textConversionOverride ?? this.textConversionOverride,
```

在 `reflowableEpubFields()` 的 return 建構（`columnSize: columnSize,` 之後）新增：

```dart
      textConversionOverride: textConversionOverride,
```

**審查修正 M-2**：`reflowableEpubFields()` 上方（第 365 行）的 doc comment 「只保留 `ReaderSettingsSheet`（流式 EPUB 版面設定）實際呈現的 20 個欄位」須同步改為「21 個欄位」，維持文件與程式碼欄位計數一致。

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/reader/book_reader_prefs_test.dart`
Expected: PASS，全數通過。

- [ ] **Step 5: Commit**

```bash
git add app/lib/reader/book_reader_prefs.dart app/test/reader/book_reader_prefs_test.dart
git commit -m "feat(reader): BookReaderPrefs 新增 textConversionOverride 欄位"
```

---

### Task 2: SQLite `book_reader_prefs` schema 遷移（v25→v26）

**Files:**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `BookReaderPrefs.toMap()`/`fromMap()`（欄位名稱 `text_conversion_override`）。
- Produces: `book_reader_prefs` 表的 `text_conversion_override TEXT` 欄位，供 `BookReaderPrefsRepository.save()`/`load()`（既有、無需改動）持久化 Task 1 新欄位。

- [ ] **Step 1: 新增失敗的遷移測試**

在 `app/test/library/sqlite_library_repository_test.dart`，找到第 1839-1850 行 `'全新安裝的 book_reader_prefs 表包含 pdf_page_turn_animation 欄位...'` 測試，在其後新增：

```dart
  test('全新安裝的 book_reader_prefs 表包含 text_conversion_override 欄位（version 26 起 onCreate 已含括）',
      () async {
    await repository.insertBook(_book('b_text_conversion'));
    await repository.database.insert('book_reader_prefs', {
      'book_id': 'b_text_conversion',
      'text_conversion_override': 'toTraditional',
    });
    final row = (await repository.database.query('book_reader_prefs',
            where: 'book_id = ?', whereArgs: ['b_text_conversion']))
        .single;
    expect(row['text_conversion_override'], 'toTraditional');
  });
```

找到第 2214-2334 行 `'既有 version 19 裝置升級到 version 20...'` 測試區塊之後（該 test 結尾的 `});` 之後），新增一個結構完全對應的新測試：

```dart
  test('既有 version 25 裝置升級到 version 26，book_reader_prefs 新增 text_conversion_override 欄位，既有 margin_top 值不受影響',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v25_to_v26_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 25」的舊資料庫：book_reader_prefs 表結構自
    // version 20（pdf_page_turn_animation 欄位加入）起到本次升級前都沒有
    // 再變動過，比照既有 v19→v20 遷移測試的簡化寫法。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 25,
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
              lastReadTime INTEGER NOT NULL,
              content_fingerprint TEXT,
              position_updated_at INTEGER,
              position_synced_server_updated_at TEXT
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
              fullscreen INTEGER,
              letter_spacing REAL,
              pdf_page_turn_animation TEXT
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
      'margin_top': 72.0,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=25 →
    // newVersion=26），驗證既有 margin_top 值不受影響、
    // text_conversion_override 新欄位存在且可寫入。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final row = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['margin_top'], 72.0); // 既有資料不受影響
    expect(row['text_conversion_override'], isNull); // 新欄位存在且預設 NULL

    // 證明新欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'book_reader_prefs',
      {'text_conversion_override': 'toSimplified'},
      where: 'book_id = ?',
      whereArgs: ['b1'],
    );
    final updated = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(updated['text_conversion_override'], 'toSimplified');
  });
```

再新增一個 `oldVersion == 1` 跳級升級測試（審查修正 I-1，`issues.md:53` 明訂但先前遺漏；比照 `sqlite_library_repository_test.dart:2577-2654` 既有的跳級測試先例，驗證 `oldVersion < 2` 時 `_createBookReaderPrefsTable` 一步到位建表含新欄位，`else` 分支的 `ALTER TABLE` 不會被誤觸發）：

```dart
  test(
      '既有 version 1 裝置（無 book_reader_prefs 表）跳級升級到 version 26，'
      'book_reader_prefs 表正確建立含 text_conversion_override，且不拋出 duplicate column name 例外',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v1_to_v26_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
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
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '最早期書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.close();

    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    await upgraded.database.insert('book_reader_prefs', {
      'book_id': 'b1',
      'text_conversion_override': 'toTraditional',
    });
    final row = (await upgraded.database.query('book_reader_prefs',
            where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['text_conversion_override'], 'toTraditional');
  });
```

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: FAIL（`text_conversion_override` 欄位不存在，`no such column` 或斷言失敗）。

- [ ] **Step 3: 修改 `sqlite_library_repository.dart` 加入遷移**

第 55 行，將：

```dart
      version: 25,
```

改為：

```dart
      version: 26,
```

找到第 229-238 行 `if (oldVersion < 20) { ... }` 區塊，在其後（仍在同一個 `else` 分支內、第 239 行 `}` 之前）新增：

```dart
          if (oldVersion < 26) {
            // epic-42-text-conversion Issue 1：簡繁轉換單書覆寫欄位。
            // 必須放在 else 分支內（oldVersion >= 2）——理由同
            // _addPdfPageTurnAnimationColumn：oldVersion < 2 時
            // _createBookReaderPrefsTable 已一步到位建表含
            // text_conversion_override，若在 else 分支外無條件執行
            // ALTER TABLE，oldVersion == 1 的裝置會重複 ALTER TABLE
            // 拋出崩潰。
            await _addTextConversionOverrideColumn(db);
          }
```

找到 `_createBookReaderPrefsTable()`（第 452-493 行）的 `CREATE TABLE` 字串，將：

```dart
        pdf_page_turn_animation TEXT
      )
```

改為：

```dart
        pdf_page_turn_animation TEXT,
        text_conversion_override TEXT
      )
```

找到 `_addPdfPageTurnAnimationColumn()`（第 731-740 行）之後，新增新的 helper 方法：

```dart

  static Future<void> _addTextConversionOverrideColumn(Database db) async {
    // epic-42-text-conversion Issue 1：簡繁轉換覆寫欄位，補追加到既有
    // （version 2 起已存在）的 book_reader_prefs 表。比照
    // _addPdfPageTurnAnimationColumn 既有慣例，僅在表已存在時才執行
    // ALTER TABLE。
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='book_reader_prefs'");
    if (tables.isNotEmpty) {
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN text_conversion_override TEXT');
    }
  }
```

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: PASS，全數通過。

- [ ] **Step 5: Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(library): book_reader_prefs 表新增 text_conversion_override 欄位（v25→v26）"
```

---

### Task 3: `ReadingDefaults` 新增 `textConversion` 欄位

**Files:**
- Modify: `app/lib/reader/reading_defaults.dart`
- Test: `app/test/reader/reading_defaults_test.dart`

**Interfaces:**
- Consumes: `app/lib/reader/text_conversion_mode.dart` 的 `TextConversionMode`。
- Produces: `ReadingDefaults.textConversion`（`TextConversionMode`，預設 `TextConversionMode.original`），供 Task 4 `resolveTextConversion()`、Task 5 `ReaderPrefsManagerImpl`、Task 6 UI 消費。

- [ ] **Step 1: 修改測試檔，新增/擴充失敗測試**

在 `app/test/reader/reading_defaults_test.dart` 頂部 import 區塊新增：

```dart
import 'package:elinkbook/reader/text_conversion_mode.dart';
```

找到第 7-16 行 `'ReadingDefaults.initial() 回傳與現行硬編碼預設一致的值'` 測試，在 `expect(prefs.showFooter, isFalse);` 後新增：

```dart
    expect(prefs.textConversion, TextConversionMode.original);
```

找到第 30-41 行 `'copyWith 可個別更新 volumeKeyEnabled／fullscreen／openLastBookOnLaunch'` 測試之後（第 42 行空行後），新增：

```dart
  test('copyWith 可個別更新 textConversion', () {
    const original = ReadingDefaults.initial();
    final updated =
        original.copyWith(textConversion: TextConversionMode.toTraditional);
    expect(updated.textConversion, TextConversionMode.toTraditional);
    expect(updated.pageTurnMode, original.pageTurnMode);
  });

```

找到第 51-72 行 `'七個欄位值皆相同的 ReadingDefaults 視為相等'` 測試，標題改為 `'八個欄位值皆相同的 ReadingDefaults 視為相等'`，並在 `a`／`b` 兩個建構參數列的 `showFooter: true,` 後皆新增：

```dart
      textConversion: TextConversionMode.toSimplified,
```

找到第 74-85 行 `'任一欄位不同時視為不相等'` 測試，在 `expect(a == a.copyWith(showFooter: true), isFalse);` 後新增：

```dart
    expect(
        a == a.copyWith(textConversion: TextConversionMode.toTraditional),
        isFalse);
```

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/reader/reading_defaults_test.dart`
Expected: 編譯錯誤（`textConversion` 不存在於 `ReadingDefaults`）。

- [ ] **Step 3: 修改 `reading_defaults.dart` 加入新欄位**

在 import 區塊新增：

```dart
import 'text_conversion_mode.dart';
```

在 `showFooter` 欄位宣告（第 28 行）之後新增：

```dart

  /// 簡繁顯示轉換全域預設值（FR-48），預設 `original`（不轉換，維持既有
  /// 行為）。與單書層 `BookReaderPrefs.textConversionOverride` 為雙層解析
  /// 關係，見 `resolveTextConversion()`。
  final TextConversionMode textConversion;
```

在建構子參數列（`this.showFooter = false,` 之後）新增：

```dart
    this.textConversion = TextConversionMode.original,
```

在 `copyWith()` 參數列（`bool? showFooter,` 之後）新增：

```dart
    TextConversionMode? textConversion,
```

在 `copyWith()` 的 return 建構（`showFooter: showFooter ?? this.showFooter,` 之後）新增：

```dart
      textConversion: textConversion ?? this.textConversion,
```

在 `operator ==`（`other.showFooter == showFooter;` 行）改為：

```dart
      other.showFooter == showFooter &&
      other.textConversion == textConversion;
```

在 `hashCode` 的 `Object.hash(...)`（`showFooter,` 之後）新增：

```dart
        textConversion,
```

**審查修正 M-2**：類別最上方（第 4 行）的 doc comment 「對應的 7 個欄位」須同步改為「8 個欄位」，維持文件與程式碼欄位計數一致。

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/reader/reading_defaults_test.dart`
Expected: PASS，全數通過。

- [ ] **Step 5: Commit**

```bash
git add app/lib/reader/reading_defaults.dart app/test/reader/reading_defaults_test.dart
git commit -m "feat(reader): ReadingDefaults 新增 textConversion 欄位"
```

---

### Task 4: `resolveTextConversion()` 純函式

**Files:**
- Create: `app/lib/reader/resolve_text_conversion.dart`
- Test: `app/test/reader/resolve_text_conversion_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `BookReaderPrefs.textConversionOverride`；Task 3 的 `ReadingDefaults.textConversion`。
- Produces: `TextConversionMode resolveTextConversion(BookReaderPrefs book, ReadingDefaults global)`，供 Issue 2-5 所有顯示/轉換呼叫點直接消費（此簽章為固定介面，不得更動參數順序或型別，見 Global Constraints）。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/reader/resolve_text_conversion_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/reading_defaults.dart';
import 'package:elinkbook/reader/resolve_text_conversion.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';

void main() {
  group('resolveTextConversion', () {
    test('book.textConversionOverride 非 null 時優先於 global.textConversion', () {
      const book =
          BookReaderPrefs(textConversionOverride: TextConversionMode.toSimplified);
      const global = ReadingDefaults(textConversion: TextConversionMode.toTraditional);
      expect(resolveTextConversion(book, global), TextConversionMode.toSimplified);
    });

    test('book.textConversionOverride 為 null 時回退 global.textConversion', () {
      const book = BookReaderPrefs.empty;
      const global = ReadingDefaults(textConversion: TextConversionMode.toTraditional);
      expect(resolveTextConversion(book, global), TextConversionMode.toTraditional);
    });

    test('兩者皆未設定時回傳 original（硬編碼預設值一致）', () {
      const book = BookReaderPrefs.empty;
      const global = ReadingDefaults.initial();
      expect(resolveTextConversion(book, global), TextConversionMode.original);
    });
  });
}
```

- [ ] **Step 2: 執行測試，確認失敗（找不到檔案）**

Run: `flutter test test/reader/resolve_text_conversion_test.dart`
Expected: FAIL，錯誤訊息為找不到 `package:elinkbook/reader/resolve_text_conversion.dart`。

- [ ] **Step 3: 寫最小實作**

建立 `app/lib/reader/resolve_text_conversion.dart`：

```dart
import 'book_reader_prefs.dart';
import 'reading_defaults.dart';
import 'text_conversion_mode.dart';

/// 解析單一書籍實際生效的簡繁顯示轉換模式（FR-48）：[book] 的單書覆寫值
/// 存在時優先採用，否則回退 [global] 的全域預設值。
///
/// 獨立頂層純函式（不併入 `ReaderPrefsManagerImpl.resolve()`／
/// `ResolvedPreferences`）——Issue 2-5 的呼叫點（JS DOM Walker 偏好注入、
/// 目錄/書籤/劃線清單、書架畫面、全文檢索結果清單、TTS 朗讀段）多數不持有
/// 完整 `ResolvedPreferences`，只持有 [BookReaderPrefs]／[ReadingDefaults]，
/// 比照既有 `resolveZoneActions()` 頂層純函式先例。此簽章為 Issue 1-5 共用
/// 的固定介面，不得更動參數順序或型別。
TextConversionMode resolveTextConversion(
  BookReaderPrefs book,
  ReadingDefaults global,
) {
  return book.textConversionOverride ?? global.textConversion;
}
```

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/reader/resolve_text_conversion_test.dart`
Expected: PASS，3/3。

- [ ] **Step 5: Commit**

```bash
git add app/lib/reader/resolve_text_conversion.dart app/test/reader/resolve_text_conversion_test.dart
git commit -m "feat(reader): 新增 resolveTextConversion() 純函式"
```

---

### Task 5: `ReaderPrefsManagerImpl` 讀寫全域 `textConversion`

**Files:**
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart`
- Test: `app/test/reader/reader_prefs_manager_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `ReadingDefaults.textConversion`。
- Produces: `loadGlobalPrefs()`／`saveGlobalPrefs()` 正確讀寫 `GlobalReaderPrefs.reading.textConversion` 至 SharedPreferences，供 Task 6 `ReadingDefaultsScreen` 消費。

- [ ] **Step 1: 寫失敗測試**

在 `app/test/reader/reader_prefs_manager_test.dart`，找到第 461-480 行 `'saveGlobalPrefs 寫入 showHeader／showFooter／ttsVoiceId／defaultTtsSpeed 至既有慣例命名的 SharedPreferences key'` 測試，在其 `reading:` 建構參數的 `showFooter: true,` 後新增：

```dart
        textConversion: TextConversionMode.toTraditional,
```

並在該測試方法末尾（`expect(loaded.globalPrefs.reading.showHeader, isTrue);` 之後）新增（審查修正 M-1：本測試主要目的即防護 SharedPreferences 鍵名字串，比照同測試既有其他欄位斷言，一併驗證鍵名 `'global_reader_text_conversion'` 而不只驗證讀回值）：

```dart
      expect(
        loaded.globalPrefs.reading.textConversion,
        TextConversionMode.toTraditional,
      );
      expect(sp.getString('global_reader_text_conversion'), 'toTraditional');
```

在第 482-489 行 `'showHeader／showFooter／defaultTtsSpeed 未儲存過（缺鍵）時，安全回退為預設值...'` 測試末尾新增：

```dart
      expect(loaded.globalPrefs.reading.textConversion, TextConversionMode.original);
```

在頂部 import 區塊新增：

```dart
import 'package:elinkbook/reader/text_conversion_mode.dart';
```

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/reader/reader_prefs_manager_test.dart`
Expected: 編譯錯誤（`textConversion` 不存在於 `ReadingDefaults` 建構參數，或 `TextConversionMode` 找不到 import）——若 Task 3 已完成則改為執行期斷言失敗（`textConversion` 未被 `saveGlobalPrefs`/`loadGlobalPrefs` 持久化，讀回硬編碼預設值而非測試寫入值）。

- [ ] **Step 3: 修改 `reader_prefs_manager_impl.dart` 加入讀寫邏輯**

在 import 區塊（`screen_orientation_setting.dart` 之後、`writing_mode.dart` 之前）新增：

```dart
import 'text_conversion_mode.dart';
```

在 `_showFooterKey` 宣告（第 47 行）之後新增：

```dart
  static const _textConversionKey = 'global_reader_text_conversion';
```

在 `loadGlobalPrefs()` 的 `ReadingDefaults(...)` 建構（`showFooter: sp.getBool(_showFooterKey) ?? false,` 之後）新增：

```dart
        textConversion: _readEnum(sp, _textConversionKey, TextConversionMode.values) ??
            TextConversionMode.original,
```

在 `saveGlobalPrefs()` 方法（`await sp.setBool(_showFooterKey, prefs.reading.showFooter);` 之後）新增：

```dart
    await sp.setString(_textConversionKey, prefs.reading.textConversion.name);
```

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/reader/reader_prefs_manager_test.dart`
Expected: PASS，全數通過。

- [ ] **Step 5: Commit**

```bash
git add app/lib/reader/reader_prefs_manager_impl.dart app/test/reader/reader_prefs_manager_test.dart
git commit -m "feat(reader): ReaderPrefsManagerImpl 讀寫全域 textConversion"
```

---

### Task 6: `ReadingDefaultsScreen` 三態選擇器 UI

**Files:**
- Modify: `app/lib/screens/reading_defaults_screen.dart`
- Test: `app/test/screens/reading_defaults_screen_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `ReadingDefaults.textConversion`；Task 5 的 `saveGlobalPrefs()`/`loadGlobalPrefs()`。
- Produces: 無（葉節點 UI）。

- [ ] **Step 1: 寫失敗測試**

在 `app/test/screens/reading_defaults_screen_test.dart` 頂部 import 區塊新增：

```dart
import 'package:elinkbook/reader/text_conversion_mode.dart';
```

找到第 109-125 行 `'點選螢幕方向選項立即呼叫 saveGlobalPrefs 更新為對應設定'` 測試之後，新增（審查修正 I-3：新控制項排在螢幕方向〔5 項〕之後，累積 Y 座標在預設 800x600 視口下已超出可見範圍，比照同檔案 `fullscreen_switch` 既有測試〔第 83 行〕的 `ensureVisible` 用法，並依 `issues.md:50`「可正確切換並持久化（重新載入後值不變）」要求，重新以同一個 `fakeManager` 建構第二個 widget tree 驗證持久化還原）：

```dart

  testWidgets('點選簡繁轉換選項立即呼叫 saveGlobalPrefs 更新為對應模式，且重新載入後反映新值',
      (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final traditionalFinder =
        find.byKey(const Key('reading_defaults_text_conversion_traditional'));
    await tester.ensureVisible(traditionalFinder);
    await tester.pumpAndSettle();
    await tester.tap(traditionalFinder);
    await tester.pumpAndSettle();

    expect(
      fakeManager.savedGlobalPrefsCalls.last.reading.textConversion,
      TextConversionMode.toTraditional,
    );

    // 重新載入持久化（issues.md:50 規定）：以同一個 fakeManager 重建畫面，
    // 驗證剛才儲存的值會反映在選中狀態。
    await tester.pumpWidget(MaterialApp(
      home: ReadingDefaultsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    final reloadedFinder =
        find.byKey(const Key('reading_defaults_text_conversion_traditional'));
    await tester.ensureVisible(reloadedFinder);
    final traditionalTile =
        tester.widget<RadioListTile<TextConversionMode>>(reloadedFinder);
    expect(traditionalTile.checked, isTrue);
  });
```

在第 10-56 行 `'載入完成前顯示載入指示器...'` 測試的 `GlobalReaderPrefs.initial().copyWith(...)` 建構的 `reading: ReadingDefaults(...)` 參數列（`fullscreen: true,` 之後）新增：

```dart
          textConversion: TextConversionMode.toSimplified,
```

並在該測試方法末尾（`expect(find.byKey(const Key('reading_defaults_screen_orientation_lock90')), findsOneWidget);` 之後）新增（審查修正 I-3：`RadioListTile.value` 是寫死在建構參數上的靜態值，無論是否被選中恆為 `toSimplified`，無鑑別力，改斷言 `checked`，並先 `ensureVisible` 避免視口外例外）：

```dart

    final simplifiedFinder =
        find.byKey(const Key('reading_defaults_text_conversion_simplified'));
    await tester.ensureVisible(simplifiedFinder);
    final simplifiedTile =
        tester.widget<RadioListTile<TextConversionMode>>(simplifiedFinder);
    expect(simplifiedTile.checked, isTrue);
```

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/screens/reading_defaults_screen_test.dart`
Expected: FAIL（找不到 `Key('reading_defaults_text_conversion_traditional')` 等元件）。

- [ ] **Step 3: 修改 `reading_defaults_screen.dart` 加入三態選擇器**

在 import 區塊新增：

```dart
import '../reader/text_conversion_mode.dart';
```

在 `build()` 方法的 `ListView` children 列表中，找到：

```dart
                const Divider(height: 1),
                SwitchListTile(
                  key: const Key('reading_defaults_fullscreen_switch'),
```

改為（在原本的 `Divider` 前插入新區塊）：

```dart
                const Divider(height: 1),
                _buildSectionHeader(context, '簡繁轉換顯示'),
                RadioGroup<TextConversionMode>(
                  groupValue: _prefs.reading.textConversion,
                  onChanged: (mode) => _update(
                    _prefs.copyWith(
                      reading: _prefs.reading.copyWith(textConversion: mode),
                    ),
                  ),
                  child: Column(
                    children: [
                      RadioListTile<TextConversionMode>(
                        key: const Key('reading_defaults_text_conversion_original'),
                        title: const Text('原文'),
                        value: TextConversionMode.original,
                      ),
                      RadioListTile<TextConversionMode>(
                        key: const Key('reading_defaults_text_conversion_traditional'),
                        title: const Text('轉換為繁體'),
                        value: TextConversionMode.toTraditional,
                      ),
                      RadioListTile<TextConversionMode>(
                        key: const Key('reading_defaults_text_conversion_simplified'),
                        title: const Text('轉換為簡體'),
                        value: TextConversionMode.toSimplified,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  key: const Key('reading_defaults_fullscreen_switch'),
```

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/screens/reading_defaults_screen_test.dart`
Expected: PASS，全數通過。

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/reading_defaults_screen.dart app/test/screens/reading_defaults_screen_test.dart
git commit -m "feat(screens): ReadingDefaultsScreen 新增簡繁轉換三態選擇器"
```

---

### Task 7: `ReaderSettingsSheet` 四態覆寫選擇器 UI（流式 EPUB）

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart`
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `BookReaderPrefs.textConversionOverride`。
- Produces: 無（葉節點 UI）。

- [ ] **Step 1: 寫失敗測試**

在 `app/test/screens/reader_settings_sheet_test.dart` 頂部 import 區塊新增：

```dart
import 'package:elinkbook/reader/text_conversion_mode.dart';
```

找到第 702-719 行 `'點擊「滾動翻頁」圖示後，onChanged 帶入 PageTurnMode.scroll'` 測試之後，新增：

```dart

  testWidgets('點擊「轉換為繁體」圖示後，onChanged 帶入 TextConversionMode.toTraditional',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      BookReaderPrefs.empty,
      (prefs) => result = prefs,
    );
    await switchToTab(tester, '呈現');

    await tester.tap(
      find.byKey(const Key('reader_settings_text_conversion_traditional')),
    );
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.textConversionOverride, TextConversionMode.toTraditional);
  });

  testWidgets(
      'textConversionOverride 初始為 toSimplified 時，點擊「使用全域預設」圖示後，'
      'onChanged 帶入 null', (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(
        textConversionOverride: TextConversionMode.toSimplified,
      ),
      (prefs) => result = prefs,
    );
    await switchToTab(tester, '呈現');

    await tester.tap(
      find.byKey(const Key('reader_settings_text_conversion_global')),
    );
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.textConversionOverride, isNull);
  });
```

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: FAIL（找不到 `Key('reader_settings_text_conversion_traditional')` 等元件）。

- [ ] **Step 3: 修改 `reader_settings_sheet.dart` 加入四態選擇器**

在 import 區塊（`screen_orientation_setting.dart` 之後）新增：

```dart
import '../reader/text_conversion_mode.dart';
```

在 State 欄位宣告（`late ScreenOrientationSetting? _screenOrientationOverride;` 之後）新增：

```dart
  late TextConversionMode? _textConversionOverride;
```

在 `initState()`（`_screenOrientationOverride = widget.prefs.screenOrientationOverride;` 之後）新增：

```dart
    _textConversionOverride = widget.prefs.textConversionOverride;
```

在 `didUpdateWidget()` 同一個 `setState` 區塊內（相同位置）新增同一行：

```dart
        _textConversionOverride = widget.prefs.textConversionOverride;
```

在 `_currentDraft` getter 的 `BookReaderPrefs(...)` 建構（`columnSize: _columnSize,` 之後）新增：

```dart
    textConversionOverride: _textConversionOverride,
```

在 `_buildPageTurnModeOverrideRow()` 方法（第 920-953 行）之後新增新方法：

```dart

  /// 簡繁轉換覆寫（FR-48，全域/單書雙層解析，見 `resolveTextConversion()`）：
  /// `null`＝使用全域預設，非 `null`＝單書覆寫。
  Widget _buildTextConversionOverrideRow() {
    const options = [
      (null, 'global', Icons.tune, '使用全域預設', '全域'),
      (TextConversionMode.original, 'original', Icons.article_outlined, '原文', '原文'),
      (TextConversionMode.toTraditional, 'traditional', Icons.translate, '轉換為繁體', '繁體'),
      (TextConversionMode.toSimplified, 'simplified', Icons.g_translate, '轉換為簡體', '簡體'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('簡繁轉換覆寫', style: TextStyle(fontWeight: FontWeight.bold)),
        EBOptionChipGroup<TextConversionMode?>(
          items: options.map((option) {
            final (mode, keySuffix, icon, tooltip, label) = option;
            return EBOptionChipItem<TextConversionMode?>(
              itemKey: Key('reader_settings_text_conversion_$keySuffix'),
              value: mode,
              icon: icon,
              label: label,
              tooltip: tooltip,
            );
          }).toList(),
          groupValue: _textConversionOverride,
          visualDensity: VisualDensity.compact,
          onSelected: (v) => setState(() {
            _textConversionOverride = v;
            _notifyChanged();
          }),
        ),
      ],
    );
  }
```

在 `_buildPresentationTab()` 的 children 列表（`_buildPageTurnModeOverrideRow(),` 之後）新增：

```dart
        const SizedBox(height: 8),
        _buildTextConversionOverrideRow(),
```

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: PASS，全數通過。

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "feat(screens): ReaderSettingsSheet 新增簡繁轉換覆寫四態選擇器"
```

---

### Task 8: `FxlSettingsSheet` 四態覆寫選擇器 UI＋`reader_screen.dart` 呼叫端

**Files:**
- Modify: `app/lib/screens/fxl_settings_sheet.dart`
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/fxl_settings_sheet_test.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `BookReaderPrefs.textConversionOverride`。
- Produces: `FxlSettingsSheet` 新建構參數 `final bool showTextConversion;`（預設 `true`），供 `reader_screen.dart` 依格式傳入。

**重要設計決策**：`FxlSettingsSheet._notifyChanged()` 目前用 `widget.prefs.copyWith(...)`（僅更新 `dualPageMode`/`dualPageDirection`/`fullscreen`/`showHeader`/`showFooter` 五個既有欄位，皆非 nullable-with-explicit-null 語意）。`textConversionOverride` 是本檔案第一個「使用者可選『使用全域預設』把欄位清回 `null`」的欄位，而 `copyWith()` 是 `newValue ?? this.value` 語意、無法明確清空（見 Global Constraints／`book_reader_prefs.dart` 既有文件註解）——若沿用 `copyWith()`，選擇「使用全域預設」時傳入的 `null` 會被 `?? this.value` 吃掉，實際上永遠清不掉舊的覆寫值。因此本 Task 把 `_notifyChanged()` 改為整列字面量建構（比照 `ReaderSettingsSheet._currentDraft` 既有模式），明確列出 `widget.prefs` 的其餘所有欄位以保留原值。

- [ ] **Step 1: 寫失敗測試**

在 `app/test/screens/fxl_settings_sheet_test.dart` 頂部 import 區塊新增：

```dart
import 'package:elinkbook/reader/text_conversion_mode.dart';
```

找到 `main()` 函式結尾的 `}`（`fxl_settings_sheet_test.dart:384`，其後為頂層 helper 函式 `_pumpModalSheet`——審查修正 I-2：若逕自在「檔案末尾」貼上 `testWidgets`，會落在 `main()` 外導致 Dart 編譯錯誤），在該 `}` 之前新增：

```dart

testWidgets('showTextConversion: true 時顯示簡繁轉換覆寫選項', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FxlSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (_) {},
          isEinkMode: false,
          showTextConversion: true,
        ),
      ),
    ),
  );

  expect(
    find.byKey(const Key('fxl_settings_text_conversion_global')),
    findsOneWidget,
  );
});

testWidgets('showTextConversion: false 時不顯示簡繁轉換覆寫選項（CBZ）', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FxlSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (_) {},
          isEinkMode: false,
          showTextConversion: false,
        ),
      ),
    ),
  );

  expect(
    find.byKey(const Key('fxl_settings_text_conversion_global')),
    findsNothing,
  );
});

testWidgets('省略 showTextConversion 參數時，預設顯示簡繁轉換覆寫選項（向後相容）',
    (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FxlSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (_) {},
          isEinkMode: false,
        ),
      ),
    ),
  );

  expect(
    find.byKey(const Key('fxl_settings_text_conversion_global')),
    findsOneWidget,
  );
});

testWidgets('點擊「轉換為繁體」圖示後，onChanged 帶入 TextConversionMode.toTraditional，其餘欄位維持原值',
    (tester) async {
  BookReaderPrefs? changed;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FxlSettingsSheet(
          prefs: const BookReaderPrefs(dualPageMode: DualPageMode.always),
          onChanged: (prefs) => changed = prefs,
          isEinkMode: false,
          showTextConversion: true,
        ),
      ),
    ),
  );

  await tester.tap(
    find.byKey(const Key('fxl_settings_text_conversion_traditional')),
  );
  await tester.pump();

  expect(changed?.textConversionOverride, TextConversionMode.toTraditional);
  expect(changed?.dualPageMode, DualPageMode.always);
});

testWidgets(
    'textConversionOverride 初始為 toSimplified 時，點擊「使用全域預設」圖示後，'
    'onChanged 帶入 null，其餘欄位不受影響', (tester) async {
  BookReaderPrefs? changed;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FxlSettingsSheet(
          prefs: const BookReaderPrefs(
            dualPageMode: DualPageMode.never,
            textConversionOverride: TextConversionMode.toSimplified,
          ),
          onChanged: (prefs) => changed = prefs,
          isEinkMode: false,
          showTextConversion: true,
        ),
      ),
    ),
  );

  await tester.tap(
    find.byKey(const Key('fxl_settings_text_conversion_global')),
  );
  await tester.pump();

  expect(changed?.textConversionOverride, isNull);
  expect(changed?.dualPageMode, DualPageMode.never);
});
```

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/screens/fxl_settings_sheet_test.dart`
Expected: 編譯錯誤（`showTextConversion` 不是 `FxlSettingsSheet` 已知的具名參數）。

- [ ] **Step 3: 修改 `fxl_settings_sheet.dart` 加入四態選擇器**

在 import 區塊新增：

```dart
import '../reader/text_conversion_mode.dart';
```

在 `FxlSettingsSheet` 欄位宣告（`final bool isEinkMode;` 之後）新增：

```dart
  final bool showTextConversion;
```

在建構子參數列（`required this.isEinkMode,` 之後）新增：

```dart
    this.showTextConversion = true,
```

在 `_FxlSettingsSheetState` 欄位宣告（`late bool _showFooter;` 之後）新增：

```dart
  late TextConversionMode? _textConversionOverride;
```

在 `initState()`（`_showFooter = widget.prefs.showFooter ?? false;` 之後）新增：

```dart
    _textConversionOverride = widget.prefs.textConversionOverride;
```

將 `_notifyChanged()` 整個方法從：

```dart
  void _notifyChanged() {
    widget.onChanged(
      widget.prefs.copyWith(
        dualPageMode: _dualPageMode,
        dualPageDirection: _dualPageDirection,
        fullscreen: _fullscreen,
        showHeader: _showHeader,
        showFooter: _showFooter,
      ),
    );
  }
```

改為（整列字面量建構，理由見本 Task 開頭「重要設計決策」）：

```dart
  void _notifyChanged() {
    widget.onChanged(
      BookReaderPrefs(
        fontFamily: widget.prefs.fontFamily,
        fontSize: widget.prefs.fontSize,
        fontWeight: widget.prefs.fontWeight,
        lineHeight: widget.prefs.lineHeight,
        paragraphSpacing: widget.prefs.paragraphSpacing,
        letterSpacing: widget.prefs.letterSpacing,
        pageMargins: widget.prefs.pageMargins,
        marginTop: widget.prefs.marginTop,
        marginBottom: widget.prefs.marginBottom,
        marginLeft: widget.prefs.marginLeft,
        marginRight: widget.prefs.marginRight,
        textAlign: widget.prefs.textAlign,
        publisherStyles: widget.prefs.publisherStyles,
        writingModeOverride: widget.prefs.writingModeOverride,
        pageTurnModeOverride: widget.prefs.pageTurnModeOverride,
        screenOrientationOverride: widget.prefs.screenOrientationOverride,
        pdfFitMode: widget.prefs.pdfFitMode,
        pdfContrast: widget.prefs.pdfContrast,
        pdfBrightness: widget.prefs.pdfBrightness,
        pdfBoldStrength: widget.prefs.pdfBoldStrength,
        pdfCropMode: widget.prefs.pdfCropMode,
        pdfCropRect: widget.prefs.pdfCropRect,
        dualPageMode: _dualPageMode,
        dualPageCoverAlone: widget.prefs.dualPageCoverAlone,
        dualPageDirection: _dualPageDirection,
        pdfPageTurnAnimation: widget.prefs.pdfPageTurnAnimation,
        showHeader: _showHeader,
        showFooter: _showFooter,
        columnMode: widget.prefs.columnMode,
        columnSize: widget.prefs.columnSize,
        fullscreen: _fullscreen,
        textConversionOverride: _textConversionOverride,
      ),
    );
  }
```

在 `build()` 方法內，找到：

```dart
            const SizedBox(height: 16),
            EBFieldCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                key: const Key('fxl_settings_fullscreen'),
```

改為（在其前插入條件式區塊，用集合 `if` 語法比照本檔案既有 inline 風格，不額外拆分 `_build*Row()` 方法）：

```dart
            if (widget.showTextConversion) ...[
              const SizedBox(height: 16),
              const Text('簡繁轉換覆寫', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              EBOptionChipGroup<TextConversionMode?>(
                items: const [
                  (null, 'global', Icons.tune, '使用全域預設', '全域'),
                  (
                    TextConversionMode.original,
                    'original',
                    Icons.article_outlined,
                    '原文',
                    '原文',
                  ),
                  (
                    TextConversionMode.toTraditional,
                    'traditional',
                    Icons.translate,
                    '轉換為繁體',
                    '繁體',
                  ),
                  (
                    TextConversionMode.toSimplified,
                    'simplified',
                    Icons.g_translate,
                    '轉換為簡體',
                    '簡體',
                  ),
                ].map((option) {
                  final (mode, keySuffix, icon, tooltip, label) = option;
                  return EBOptionChipItem<TextConversionMode?>(
                    itemKey: Key('fxl_settings_text_conversion_$keySuffix'),
                    value: mode,
                    icon: icon,
                    label: label,
                    tooltip: tooltip,
                  );
                }).toList(),
                groupValue: _textConversionOverride,
                visualDensity: VisualDensity.compact,
                onSelected: (v) => setState(() {
                  _textConversionOverride = v;
                  _notifyChanged();
                }),
              ),
            ],
            const SizedBox(height: 16),
            EBFieldCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                key: const Key('fxl_settings_fullscreen'),
```

**注意**：`EBOptionChipGroup<TextConversionMode?>` 的 `items` 用 `const [...]` record 字面量清單時，record 內的 `IconData`（如 `Icons.tune`）與 enum 值皆為編譯期常數，`const` 合法；若編譯器對此處 `const` 提出疑慮（record 語法在部分 Dart 版本的 const context 限制），改為非 `const` 的一般 `[...]` 字面量即可，不影響行為。

- [ ] **Step 4: 執行測試，確認通過**

Run: `flutter test test/screens/fxl_settings_sheet_test.dart`
Expected: PASS，全數通過（含既有測試，證明 `_notifyChanged()` 改為整列字面量建構後，`dualPageMode`/`dualPageDirection`/`fullscreen`/`showHeader`/`showFooter` 既有行為零回歸）。

- [ ] **Step 5: 修改 `reader_screen.dart` 的 `_openFxlSettings()` 呼叫端**

找到 `_openFxlSettings()` 方法：

```dart
  void _openFxlSettings() {
    _showThemedModalBottomSheet<void>(
      builder: (_) => FxlSettingsSheet(
        prefs: _prefs,
        onChanged: _handlePrefsChanged,
        isEinkMode: widget.isEinkMode,
      ),
    );
  }
```

改為：

```dart
  void _openFxlSettings() {
    _showThemedModalBottomSheet<void>(
      builder: (_) => FxlSettingsSheet(
        prefs: _prefs,
        onChanged: _handlePrefsChanged,
        isEinkMode: widget.isEinkMode,
        showTextConversion:
            detectBookFormat(widget.filePath) != BookFormat.cbz,
      ),
    );
  }
```

在 `app/test/screens/reader_screen_test.dart`，找到第 1428-1469 行 `'EPUB 固定版面開書後，畫面右上角出現懸浮設定按鈕，點擊能開啟 FxlSettingsSheet'` 測試，在 `expect(find.byType(FxlSettingsSheet), findsOneWidget);` 之後新增：

```dart

    expect(
      tester.widget<FxlSettingsSheet>(find.byType(FxlSettingsSheet)).showTextConversion,
      isTrue,
    );
```

在同一個測試檔案的 CBZ 測試群組附近（第 1100-1124 行 `'CBZ 書籍建構 FoliateReaderView 時，isComicBookHint 正確傳為 true'` 測試之後）新增：

```dart

  testWidgets('CBZ 書籍開啟 FxlSettingsSheet 時 showTextConversion 為 false（不顯示簡繁轉換選項）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.cbz',
          bookId: 'b1',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(
      find.byKey(const Key('reader_chrome_layout_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(FxlSettingsSheet), findsOneWidget);
    expect(
      tester.widget<FxlSettingsSheet>(find.byType(FxlSettingsSheet)).showTextConversion,
      isFalse,
    );
  });
```

- [ ] **Step 6: 執行測試，確認通過**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS，全數通過。

- [ ] **Step 7: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: 執行完整 `flutter test`（本計畫最後一個 Task，比照專案慣例跑一次全套）**

Run: `flutter test`
Expected: 全數通過（既有已知不穩定案例除外，例如 `adaptive_shell_scaffold_test.dart` 既有 2 個失敗案例，非本次異動引入）。

- [ ] **Step 9: Commit**

```bash
git add app/lib/screens/fxl_settings_sheet.dart app/lib/screens/reader_screen.dart app/test/screens/fxl_settings_sheet_test.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(screens): FxlSettingsSheet 新增簡繁轉換覆寫四態選擇器與 showTextConversion 參數"
```

---

## Self-Review

**Spec 覆蓋度**：對照 `issues.md` Issue 1「範圍」逐項核對——(1) `BookReaderPrefs.textConversionOverride` 欄位（含 `toMap`/`fromMap`/`copyWith`/`==`/`hashCode`/`reflowableEpubFields()`）→ Task 1；(2) `ReadingDefaults.textConversion` 欄位 → Task 3；(3) `ReaderPrefsManagerImpl` SharedPreferences 讀寫 → Task 5；(4) `resolveTextConversion()` 純函式 → Task 4；(5) SQLite v25→v26 遷移 → Task 2；(6) 全域預設 UI（`ReadingDefaultsScreen`）→ Task 6；(7) 單書覆寫 UI（`ReaderSettingsSheet`／`FxlSettingsSheet`＋`showTextConversion` 建構參數）→ Task 7／Task 8。六項單元測試要求（欄位往返、`resolveTextConversion()` 雙層解析、SQLite migration、`ReadingDefaultsScreen`／`ReaderSettingsSheet`／`FxlSettingsSheet` widget test）皆已對應到具體 Task 步驟。無遺漏。

**佔位符掃描**：全文檢查過，沒有 TBD／「之後補上」／「類似 Task N」等字樣；所有程式碼步驟皆為可直接執行的完整程式碼區塊。

**型別一致性**：`TextConversionMode`（Issue 0 既有）→ `BookReaderPrefs.textConversionOverride`（Task 1）／`ReadingDefaults.textConversion`（Task 3）→ `resolveTextConversion(BookReaderPrefs, ReadingDefaults)`（Task 4）→ `ReaderPrefsManagerImpl`（Task 5）→ UI（Task 6-8）全程使用同一個型別、同一組欄位/函式名稱，無命名漂移。`FxlSettingsSheet.showTextConversion`（Task 8 新增）與 `reader_screen.dart` 呼叫端傳入值型別一致（`bool`）。

**架構風險點（本計畫已處理，執行時務必落實）**：`FxlSettingsSheet._notifyChanged()` 由 `copyWith()` 改為整列字面量建構，是本 Issue範圍內對既有程式碼的必要架構調整（而非新增功能的附帶重構）——若沿用原本的 `copyWith()`，「使用全域預設」選項將永久失效（`copyWith(textConversionOverride: null)` 不會清空既有覆寫值），Task 8 的兩個新增測試（「其餘欄位維持原值」「其餘欄位不受影響」）明確驗證這個修正的正確性。

**審查修訂記錄**：2026-09-15 `reviews/review-plan-issue-1.md`（0 Critical／3 Important／4 Minor）已全數套用至本計畫——I-1（Task 2 補上 `oldVersion == 1` 跳級升級測試）、I-2（Task 8 Step 1 插入點修正為 `main()` 結尾 `}` 之前，避免落在頂層 scope 導致編譯錯誤）、I-3（Task 6 Step 1 補 `ensureVisible`、斷言改為 `checked`、追加重新載入持久化驗證）、M-1（Task 5 補 SharedPreferences 鍵名字串斷言）、M-2（Task 1／Task 3 doc comment 欄位計數同步更新為 21／8）、M-3（Task 1 Step 1 測試插入點調整，不再打斷既有成對測試）、M-4（Task 8 補「省略 `showTextConversion` 預設為 `true`」向後相容測試）。另同步更新「Spec:」引用行，標明 ADR 0030 已由 ADR 0032 取代（本 Issue 範圍不受該次轉換演算法改版影響，僅為文件引用精確化）。
