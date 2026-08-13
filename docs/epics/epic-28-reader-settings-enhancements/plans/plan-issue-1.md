# Epic 28 Issue 1：流式 EPUB 版面設定新增字距（letter-spacing）選項 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓使用者可以在流式 EPUB 的「版面設定」畫面調整字距（CSS `letter-spacing`），數值即時生效、持久化並在直排/橫排下皆正確套用。

**Architecture:** 完全比照本專案既有 `lineHeight`/`paragraphSpacing` 欄位的既有資料流：`ReaderSettingsSheet`（UI 滑桿）→ `BookReaderPrefs`（單書覆寫，SQLite 持久化）→ `ReaderPrefsManagerImpl.resolve()` → `ResolvedPreferences`（最終生效值）→ `reader_screen.dart` 建構 `FoliateEpubReaderView` → `buildFoliatePreferencesMap()` 序列化成 JSON → `main.js` 的 `buildOverrideCss()` 組成 CSS 規則、透過 `Paginator.setStyles()` 套用。全程無新架構、無新型別，純粹在既有每一層各加一個欄位。

**Tech Stack:** Flutter/Dart、sqflite（SQLite）、`flutter_inappwebview`（`InAppWebView`）、`readest/foliate-js`（vendored JS，`main.js`）。

**Spec:** `docs/epics/epic-28-reader-settings-enhancements/design.md`（「Issue 1：字距選項」）、`docs/epics/epic-28-reader-settings-enhancements/issues.md`（「Issue 1」）、`docs/epics/epic-28-reader-settings-enhancements/spec.md`（「反序列化容錯要求」，`double` 欄位轉型慣例對本 Issue 同樣適用）。

## Global Constraints

- 數值範圍 `-0.05em ~ 1em`，預設 `0`（`null` = 不覆蓋書本原生字距），UI 滑桿 step `0.01em`。
- 橫排／直排（`vertical-rl`）皆套用同一份 CSS 規則，`main.js` 不做排版方向的特殊分支。
- 所有 `double` 欄位的 SQLite/JSON 反序列化一律使用 `(map['field'] as num?)?.toDouble()`，不可寫成 `map['field'] as double?`（`spec.md`「反序列化容錯要求」）。
- 每完成一個 Task 就跑一次 `flutter analyze`，維持乾淨（專案提交前的既有硬性要求，見 `CLAUDE.md`）。

## 審查回應（`docs/epics/epic-28-reader-settings-enhancements/reviews/review-plan-issue-1.md`，2026-08-14）

- **Important #1（`resolve()` 透傳測試缺失）**：**採納**，已在 Task 1 補上 `reader_prefs_manager_test.dart` 的失敗測試步驟（新 Step 7-8），確認先失敗、再實作 `ResolvedPreferences`/`resolve()`，符合 TDD 順序。
- **Minor #2（`_addLetterSpacingColumn` 應加 `PRAGMA table_info` 欄位存在檢查）**：**不採納**——查證同檔案內全部 7 個既有「新增單一欄位」helper（`_addFullscreenColumn`／`_addMarginColumns`／`_addColumnModeColumns`／`_addSingleColumnColumn`／`_addHeaderFooterColumns`／`_addDualPageColumns`／`_addPdfReaderPrefsColumns`）皆只檢查「表是否存在」，不檢查「欄位是否存在」，一致依賴 `onUpgrade` 的 `if (oldVersion < N)` 版本號 gate（sqflite 以 `PRAGMA user_version` 追蹤、只在真正版本落後時觸發一次）防止重複執行。審查建議的 `PRAGMA table_info` 欄位檢查是 `_migrateFontFamilyValues` 的既有用法，但那是「檢查欄位是否存在以判斷是否需要搬移資料」的資料遷移邏輯，與「新增欄位」helper 的用途不同，直接套用會讓 `_addLetterSpacingColumn` 與其餘 7 個同類 helper 的防禦程度不一致，不符合「比照既有慣例」的計畫前提。若要為所有 8 個「新增欄位」helper 統一補上此檢查，屬於一次獨立的架構強化決策，不在本 Issue 範圍內，暫不採納。
- **Minor #3（`letterSpacing === 0` 時應跳過 CSS 注入，避免覆寫書本原生非零字距）**：**技術上成立，但需要人類決定，尚未修改計畫**——`ReaderSettingsSheet` 目前對 `lineHeight`／`paragraphSpacing`／`marginTop` 等既有欄位皆採用「開啟 Sheet 即具現化為非 null 預設值」的既定設計（`CONTEXT.md`「設定面板草稿具現化原則」），此設計的前提是「null 與具體預設值解析結果永遠相同」——但比對 `main.js` 現行 `buildOverrideCss()` 的既有邏輯，`lineHeight`/`paragraphSpacing` 等既有欄位其實同樣不滿足這個前提（一旦使用者開過 Sheet 並觸碰任一控制項，這些欄位就會被具現化為非 null 值一併存入，進而覆寫書本原生對應樣式，即使使用者從未主動調整過該特定欄位）。`letterSpacing` 只是照既有模式新增的第 9 個欄位，審查抓到的並非本計畫新引入的缺陷，而是一個既有、已被 `CONTEXT.md` 記錄為「安全」的架構層級既定行為——是否要現在特別為 `letterSpacing` 加上 `!== 0` 例外（讓它與 8 個既有欄位的行為不一致），或維持現狀（與既有欄位一致），或另立獨立 Issue 全面檢討這個既定原則，需要你決定，詳見對話中的提問。
- **Minor #4／Recommendation #2（真機測試涵蓋 CJK 標點斷裂、SVG/MathML 書籍、極值）**：**採納**，已併入計畫末尾「完成後的驗證」段落。

---

### Task 1：資料層——`BookReaderPrefs` / `ResolvedPreferences` / `ReaderPrefsManagerImpl.resolve()`

**Files:**
- Modify: `app/lib/reader/book_reader_prefs.dart`
- Modify: `app/lib/reader/resolved_preferences.dart`
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart:154-196`（`resolve()`）
- Test: `app/test/reader/book_reader_prefs_test.dart`

**Interfaces:**
- Produces: `BookReaderPrefs.letterSpacing`（`double?`，`null` = 未覆寫）；`ResolvedPreferences.letterSpacing`（`double?`，`null` = 不套用覆蓋，沿用書本原生字距）。

- [ ] **Step 1: 寫失敗測試——`BookReaderPrefs.empty` 應含 `letterSpacing: null`**

在 `app/test/reader/book_reader_prefs_test.dart` 第 15-41 行的 `test('BookReaderPrefs.empty 所有欄位皆為 null', ...)` 內，於第 40 行 `expect(prefs.marginRight, isNull);` 之後新增：

```dart
    expect(prefs.letterSpacing, isNull);
```

- [ ] **Step 2: 執行測試確認失敗**

執行：`cd app && flutter test test/reader/book_reader_prefs_test.dart`
預期：編譯錯誤（`letterSpacing` getter 不存在於 `BookReaderPrefs`）。

- [ ] **Step 3: 在 `BookReaderPrefs` 新增 `letterSpacing` 欄位**

編輯 `app/lib/reader/book_reader_prefs.dart`：

於第 24 行 `final double? paragraphSpacing;` 之後新增欄位宣告：

```dart
  final double? letterSpacing; // em 單位，-0.05~1，null=不覆蓋書本原生字距
```

於第 70 行 `this.paragraphSpacing,` 之後（建構子參數列）新增：

```dart
    this.letterSpacing,
```

於 `toMap()`（第 100-135 行）的 `'paragraph_spacing': paragraphSpacing,` 之後新增：

```dart
      'letter_spacing': letterSpacing,
```

於 `fromMap()`（第 137-202 行）的 `paragraphSpacing: (map['paragraph_spacing'] as num?)?.toDouble(),` 之後新增：

```dart
      letterSpacing: (map['letter_spacing'] as num?)?.toDouble(),
```

於 `operator ==`（第 204-235 行）的 `other.paragraphSpacing == paragraphSpacing &&` 之後新增：

```dart
      other.letterSpacing == letterSpacing &&
```

於 `hashCode`（第 237-268 行）的 `paragraphSpacing,` 之後新增：

```dart
        letterSpacing,
```

於 `copyWith()`（第 275-338 行）：參數列的 `double? paragraphSpacing,` 之後新增 `double? letterSpacing,`；回傳建構式的 `paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,` 之後新增：

```dart
      letterSpacing: letterSpacing ?? this.letterSpacing,
```

- [ ] **Step 4: 執行測試確認通過**

執行：`cd app && flutter test test/reader/book_reader_prefs_test.dart`
預期：PASS。

- [ ] **Step 5: 寫失敗測試——`toMap`/`fromMap` 往返，含 int 型別防呆**

在 `app/test/reader/book_reader_prefs_test.dart` 檔案最後一個 `test(...)` 之後（`copyWith 更新 fullscreen 時，其餘欄位保留原值` 那組測試之後）新增：

```dart
  test('letterSpacing 為具體數值／null 皆正確 toMap／fromMap round-trip', () {
    const withValue = BookReaderPrefs(letterSpacing: 0.15);
    final valueMap = withValue.toMap('book1');
    expect(valueMap['letter_spacing'], 0.15);
    expect(BookReaderPrefs.fromMap(valueMap).letterSpacing, 0.15);

    const withNull = BookReaderPrefs();
    final nullMap = withNull.toMap('book1');
    expect(nullMap['letter_spacing'], isNull);
    expect(BookReaderPrefs.fromMap(nullMap).letterSpacing, isNull);
  });

  test('fromMap 餵入 int 型別的 letter_spacing（模擬 SQLite/JSON 對整數值的型別行為）不拋例外，正確轉為 double',
      () {
    final prefs = BookReaderPrefs.fromMap({'letter_spacing': 0});
    expect(prefs.letterSpacing, 0.0);
    expect(prefs.letterSpacing, isA<double>());
  });

  test('copyWith 更新 letterSpacing 時，其餘欄位保留原值', () {
    const original = BookReaderPrefs(fontSize: 18, letterSpacing: 0.1);
    final updated = original.copyWith(letterSpacing: 0.2);

    expect(updated.fontSize, 18);
    expect(updated.letterSpacing, 0.2);
  });
```

- [ ] **Step 6: 執行測試確認通過**

執行：`cd app && flutter test test/reader/book_reader_prefs_test.dart`
預期：全數 PASS。

- [ ] **Step 7: 寫失敗測試——`resolve()` 對 `letterSpacing` 的預設與透傳語意**

（2026-08-14 `/superpowers:receiving-code-review` 審查 Important #1 發現：原計畫直接跳到實作 `ResolvedPreferences`/`resolve()`，遺漏了 `reader_prefs_manager_test.dart` 這個既有測試檔案——`marginTop`/`paragraphSpacing` 等既有欄位皆在此檔案有透傳測試，`letterSpacing` 須比照辦理，先寫失敗測試再實作。）

編輯 `app/test/reader/reader_prefs_manager_test.dart`：

於既有 `test('EPUB 字型/排版欄位原樣透傳（不套用任何預設值，維持既有 pass-through 語意）', ...)`（約第 205-227 行）內，於 `expect(resolved.marginRight, isNull);` 之後新增：

```dart
      expect(resolved.letterSpacing, isNull);
```

於既有 `test('BookReaderPrefs 的邊距 4 個欄位正確透傳到 ResolvedPreferences', ...)`（約第 240-255 行）之後新增一個結構相同的獨立測試：

```dart
    test('BookReaderPrefs 的 letterSpacing 正確透傳到 ResolvedPreferences', () {
      final loaded = LoadedPrefs(
        bookPrefs: const BookReaderPrefs(letterSpacing: 0.15),
        globalPrefs: const GlobalReaderPrefs.initial(),
      );
      final resolved = manager.resolve(loaded);
      expect(resolved.letterSpacing, 0.15);
    });
```

- [ ] **Step 8: 執行測試確認失敗**

執行：`cd app && flutter test test/reader/reader_prefs_manager_test.dart`
預期：編譯錯誤（`letterSpacing` getter 不存在於 `ResolvedPreferences`）。

- [ ] **Step 9: `ResolvedPreferences` 新增 `letterSpacing` 欄位**

編輯 `app/lib/reader/resolved_preferences.dart`：

於第 32 行 `final double? paragraphSpacing;` 之後新增：

```dart
  final double? letterSpacing;
```

於建構子（第 80-113 行）的 `this.paragraphSpacing,` 之後新增：

```dart
    this.letterSpacing,
```

- [ ] **Step 10: `ReaderPrefsManagerImpl.resolve()` 透傳新欄位**

編輯 `app/lib/reader/reader_prefs_manager_impl.dart`，於第 166 行 `paragraphSpacing: book.paragraphSpacing,` 之後新增：

```dart
      letterSpacing: book.letterSpacing,
```

- [ ] **Step 11: 執行測試確認通過**

執行：`cd app && flutter test test/reader/reader_prefs_manager_test.dart`
預期：全數 PASS。

- [ ] **Step 12: 執行完整 Dart 分析與既有測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test test/reader/`
預期：`flutter analyze` 顯示 "No issues found!"；`flutter test` 全數 PASS。

- [ ] **Step 13: Commit**

```bash
git add app/lib/reader/book_reader_prefs.dart app/lib/reader/resolved_preferences.dart app/lib/reader/reader_prefs_manager_impl.dart app/test/reader/book_reader_prefs_test.dart app/test/reader/reader_prefs_manager_test.dart
git commit -m "feat(epic-28): Issue 1 Task 1——BookReaderPrefs/ResolvedPreferences 新增 letterSpacing 欄位"
```

---

### Task 2：SQLite 持久化——`letter_spacing` 欄位 migration（version 19）

**Files:**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes: 無（獨立資料庫層變更，`toMap`/`fromMap` 已由 Task 1 完成）。
- Produces: `book_reader_prefs.letter_spacing` 欄位（`REAL`，nullable），全新安裝與既有裝置升級皆存在。

- [ ] **Step 1: 寫失敗測試——全新安裝的 `book_reader_prefs` 表含 `letter_spacing` 欄位**

在 `app/test/library/sqlite_library_repository_test.dart` 找到既有的 `test('全新安裝的 book_reader_prefs 表包含 fullscreen 欄位（version 15 起 onCreate 已含括）', ...)`（約第 1780 行），在同一個 `group`/檔案內（緊接其後）新增一個結構相同的測試：

```dart
  test('全新安裝的 book_reader_prefs 表包含 letter_spacing 欄位（version 19 起 onCreate 已含括）',
      () async {
    await repository.insertBook(_book('b_letter_spacing'));
    await repository.database.insert('book_reader_prefs', {
      'book_id': 'b_letter_spacing',
      'letter_spacing': 0.15,
    });
    final row = (await repository.database.query('book_reader_prefs',
            where: 'book_id = ?', whereArgs: ['b_letter_spacing']))
        .single;
    expect(row['letter_spacing'], 0.15);
  });
```

（`_book(...)` helper 與 `repository` 變數沿用該檔案既有的 test setup，比照緊鄰的 `全新安裝的 book_reader_prefs 表包含 fullscreen 欄位` 測試寫法。）

- [ ] **Step 2: 執行測試確認失敗**

執行：`cd app && flutter test test/library/sqlite_library_repository_test.dart`
預期：FAIL（`letter_spacing` 欄位不存在，`no such column` 或 insert 時報錯）。

- [ ] **Step 3: 在 `_createBookReaderPrefsTable` 新增欄位（供全新安裝）**

編輯 `app/lib/library/sqlite_library_repository.dart`，第 330-335 行原為：

```dart
        margin_top REAL,
        margin_bottom REAL,
        margin_left REAL,
        margin_right REAL,
        fullscreen INTEGER
      )
    ''');
```

改為：

```dart
        margin_top REAL,
        margin_bottom REAL,
        margin_left REAL,
        margin_right REAL,
        fullscreen INTEGER,
        letter_spacing REAL
      )
    ''');
```

- [ ] **Step 4: 新增 `_addLetterSpacingColumn`（供既有裝置升級）**

在 `app/lib/library/sqlite_library_repository.dart` 的 `_addFullscreenColumn` 方法（第 551-561 行）之後新增：

```dart
  static Future<void> _addLetterSpacingColumn(Database db) async {
    // epic-28-reader-settings-enhancements Issue 1：字距欄位，補追加到既有
    // （version 2 起已存在）的 book_reader_prefs 表。比照 _addFullscreenColumn
    // 既有慣例，僅在表已存在時才執行 ALTER TABLE。
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='book_reader_prefs'");
    if (tables.isNotEmpty) {
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN letter_spacing REAL');
    }
  }
```

- [ ] **Step 5: 在 `onUpgrade` 掛上新的 `if (oldVersion < 19)` 分支**

編輯 `app/lib/library/sqlite_library_repository.dart`，於第 175-183 行（`if (oldVersion < 16) { ... await _migrateFontFamilyValues(db); }`）之後、`else` 區塊結束的 `}`（第 184 行）之前，新增：

```dart
          if (oldVersion < 19) {
            // epic-28-reader-settings-enhancements Issue 1：字距新增的 1
            // 個欄位。必須放在 else 分支內（oldVersion >= 2）——理由同
            // _migrateFontFamilyValues：oldVersion < 2 時
            // _createBookReaderPrefsTable 已一步到位建表含
            // letter_spacing，若在 else 分支外無條件執行 ALTER TABLE，
            // oldVersion == 1 的裝置會重複 ALTER TABLE 拋出崩潰。
            await _addLetterSpacingColumn(db);
          }
```

- [ ] **Step 6: 版本號 `18` → `19`**

編輯 `app/lib/library/sqlite_library_repository.dart` 第 42 行，將：

```dart
      version: 18,
```

改為：

```dart
      version: 19,
```

- [ ] **Step 7: 執行測試確認通過**

執行：`cd app && flutter test test/library/sqlite_library_repository_test.dart`
預期：全數 PASS（含 Step 1 新增的測試）。

- [ ] **Step 8: 寫失敗測試——既有 version 18 裝置升級到 version 19**

在 `app/test/library/sqlite_library_repository_test.dart` 找到既有的 `test('既有 version 14 裝置升級到 version 15，book_reader_prefs 新增 fullscreen 欄位...')`（約第 1913-2029 行），在其後新增一個結構相同、模擬 version 18→19 的測試：

```dart
  test('既有 version 18 裝置升級到 version 19，book_reader_prefs 新增 letter_spacing 欄位，既有 margin_top 值不受影響',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v18_to_v19_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 18」的舊資料庫：book_reader_prefs 表結構自
    // version 15（fullscreen 欄位加入）起到 version 18 都沒有再變動過
    // （16/17/18 只動了 books/custom_fonts/sync_* 表），故只需重建
    // groups/books/book_reader_prefs 三張表即可重現，比照既有
    // v14→v15 遷移測試的簡化寫法（onUpgrade 的其餘分支在 oldVersion=18
    // 時皆已是「已滿足」狀態，不會被觸發，見 Global Constraints 對應
    // 討論）。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 18,
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
              fullscreen INTEGER
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

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=18 →
    // newVersion=19），驗證既有 margin_top 值不受影響、letter_spacing
    // 新欄位存在且可寫入。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final row = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['margin_top'], 72.0); // 既有資料不受影響
    expect(row['letter_spacing'], isNull); // 新欄位存在且預設 NULL

    // 證明新欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'book_reader_prefs',
      {'letter_spacing': 0.2},
      where: 'book_id = ?',
      whereArgs: ['b1'],
    );
    final updated = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(updated['letter_spacing'], 0.2);
  });
```

- [ ] **Step 9: 執行測試確認通過**

執行：`cd app && flutter test test/library/sqlite_library_repository_test.dart`
預期：全數 PASS。

- [ ] **Step 10: 執行完整分析與既有測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test test/library/`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS。

- [ ] **Step 11: Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-28): Issue 1 Task 2——book_reader_prefs 新增 letter_spacing 欄位，version 19 migration"
```

---

### Task 3：Foliate 橋接——`FoliateEpubReaderView` 參數 / `buildFoliatePreferencesMap` / `foliatePreferencesChanged` / `main.js` CSS / `reader_screen.dart` 傳遞

**Files:**
- Modify: `app/lib/reader/foliate_epub_reader_view.dart`
- Modify: `app/lib/screens/reader_screen.dart:2283`
- Modify: `app/android/app/src/main/assets/foliate/main.js`
- Test: `app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes: `ResolvedPreferences.letterSpacing`（Task 1 產出）。
- Produces: `FoliateEpubReaderView.letterSpacing`（`double?` 建構參數）；`buildFoliatePreferencesMap()` 輸出 map 含 `letterSpacing` key（非 null 時）；JS 端 `prefs.letterSpacing` 驅動 CSS `letter-spacing` 規則。

- [ ] **Step 1: 寫失敗測試——`buildFoliatePreferencesMap` 含 `letterSpacing`**

編輯 `app/test/reader/foliate_epub_reader_view_test.dart`：

在既有 `test('所有非 null 建構參數皆正確出現於 map', ...)`（第 136-181 行）內，於建構參數的 `paragraphSpacing: 1.2,` 之後新增 `letterSpacing: 0.1,`；於期望的 map 內容中，`'paragraphSpacing': 1.2,` 之後新增 `'letterSpacing': 0.1,`。修改後該測試片段變為：

```dart
    test('所有非 null 建構參數皆正確出現於 map', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.vertical,
        pageTurnMode: PageTurnMode.scroll,
        fontFamily: 'SourceHanSansTC',
        fontSize: 1.125,
        fontWeight: 1.75,
        lineHeight: 1.6,
        paragraphSpacing: 1.2,
        letterSpacing: 0.1,
        marginTop: 72,
        marginBottom: 20,
        marginLeft: 30,
        marginRight: 30,
        textAlign: EpubTextAlign.justify,
        publisherStyles: false,
        columnMode: ColumnMode.single,
        columnSize: 600.0,
        showFooter: false,
        textColor: Color(0xFFE8E8EC),
        backgroundColor: Color(0xFF121214),
      );
      expect(buildFoliatePreferencesMap(view), {
        'writingMode': 'vertical',
        'pageTurnMode': 'scroll',
        'fontFamily': 'SourceHanSansTC',
        'fontSize': 1.125,
        'fontWeight': 1.75,
        'lineHeight': 1.6,
        'paragraphSpacing': 1.2,
        'letterSpacing': 0.1,
        'marginTop': 72.0,
        'marginBottom': 20.0,
        'marginLeft': 30.0,
        'marginRight': 30.0,
        'textAlign': 'justify',
        'publisherStyles': false,
        'columnMode': 'single',
        'columnSize': 600.0,
        'showFooter': false,
        'textColor': '#e8e8ec',
        'backgroundColor': '#121214',
        'isLandscape': false,
      });
    });
```

另新增一個獨立測試，緊接在上面那個測試之後：

```dart
    test('letterSpacing 未設定（null）時 map 不含該 key', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      );
      expect(
        buildFoliatePreferencesMap(view).containsKey('letterSpacing'),
        isFalse,
      );
    });
```

- [ ] **Step 2: 執行測試確認失敗**

執行：`cd app && flutter test test/reader/foliate_epub_reader_view_test.dart`
預期：編譯錯誤（`letterSpacing` 建構參數不存在於 `FoliateEpubReaderView`）。

- [ ] **Step 3: `FoliateEpubReaderView` 新增 `letterSpacing` 建構參數**

編輯 `app/lib/reader/foliate_epub_reader_view.dart`：

於第 355 行 `final double? paragraphSpacing;` 之後新增：

```dart
  final double? letterSpacing;
```

於建構子第 392 行 `this.paragraphSpacing,` 之後新增：

```dart
    this.letterSpacing,
```

- [ ] **Step 4: `buildFoliatePreferencesMap()` 加入 `letterSpacing`**

於 `buildFoliatePreferencesMap()`（第 236-274 行）第 250-252 行：

```dart
  if (view.paragraphSpacing != null) {
    map['paragraphSpacing'] = view.paragraphSpacing;
  }
```

之後新增：

```dart
  if (view.letterSpacing != null) map['letterSpacing'] = view.letterSpacing;
```

- [ ] **Step 5: `foliatePreferencesChanged()` 加入 `letterSpacing` 比較**

於 `foliatePreferencesChanged()`（第 279-304 行）第 289 行 `oldView.paragraphSpacing != newView.paragraphSpacing ||` 之後新增：

```dart
      oldView.letterSpacing != newView.letterSpacing ||
```

- [ ] **Step 6: 執行測試確認通過**

執行：`cd app && flutter test test/reader/foliate_epub_reader_view_test.dart`
預期：全數 PASS。

- [ ] **Step 7: 寫失敗測試——`foliatePreferencesChanged` 偵測 `letterSpacing` 變動**

在 `app/test/reader/foliate_epub_reader_view_test.dart` 的 `group('foliatePreferencesChanged', ...)` 內，於既有 `test('writingMode 變動回傳 true', ...)`（第 339-353 行）之後新增：

```dart
    test('letterSpacing 變動回傳 true', () {
      const oldView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        letterSpacing: 0.1,
      );
      const newView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        letterSpacing: 0.2,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });
```

- [ ] **Step 8: 執行測試確認通過**

執行：`cd app && flutter test test/reader/foliate_epub_reader_view_test.dart`
預期：全數 PASS。

- [ ] **Step 9: `main.js` 的 `buildOverrideCss()` 新增 `letter-spacing` CSS 規則**

編輯 `app/android/app/src/main/assets/foliate/main.js`，於第 112-114 行：

```js
  if (typeof prefs.paragraphSpacing === 'number') {
    rules.push(`p { margin-bottom: ${prefs.paragraphSpacing}em !important; }`)
  }
```

之後新增：

```js
  if (typeof prefs.letterSpacing === 'number') {
    // epic-28-reader-settings-enhancements Issue 1：letter-spacing 作用於
    // inline 軸方向，vertical-rl 下 inline 軸即為垂直方向，語意依然合法，
    // 橫排/直排皆套用同一份規則，不需要依 writingMode 分支處理。沿用
    // fontWeight/lineHeight 既有的廣 selector，避免書本自己直接宣告
    // letter-spacing 時覆蓋無效（比照 Issue 34 既有教訓）。
    rules.push(`${selector} { letter-spacing: ${prefs.letterSpacing}em !important; }`)
  }
```

（本步驟無自動化測試覆蓋——`main.js` 是 vendored JS、無 Node 測試框架，`app/tool/check_foliate_es_compat.js` 僅做 ES 相容性靜態掃描，非功能測試。Task 4 完成後、進入真機/模擬器驗證階段時，於「測試計畫」一併手動確認 CSS 實際生效。）

- [ ] **Step 10: `reader_screen.dart` 傳遞 `resolved.letterSpacing`**

編輯 `app/lib/screens/reader_screen.dart`，於第 2283-2284 行：

```dart
          lineHeight: resolved.lineHeight,
          paragraphSpacing: resolved.paragraphSpacing,
```

之後新增：

```dart
          letterSpacing: resolved.letterSpacing,
```

- [ ] **Step 11: 執行完整分析與既有測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS。

- [ ] **Step 12: Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/lib/screens/reader_screen.dart app/android/app/src/main/assets/foliate/main.js app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "feat(epic-28): Issue 1 Task 3——letterSpacing 貫穿 FoliateEpubReaderView／main.js CSS"
```

---

### Task 4：UI——`ReaderSettingsSheet` 字距滑桿

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart`
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes: `BookReaderPrefs.letterSpacing`（Task 1 產出，經 `widget.prefs` 傳入）。
- Produces: 使用者互動後，`widget.onChanged` 回報的 `BookReaderPrefs.letterSpacing` 更新值。

- [ ] **Step 1: 寫失敗測試——初始值正確反映**

編輯 `app/test/screens/reader_settings_sheet_test.dart`，於既有 `test('初始值正確反映傳入的 BookReaderPrefs', ...)`（第 13-100 行附近）：

於建構的 `const prefs = BookReaderPrefs(...)` 內，`lineHeight: 1.8,` 之後新增 `letterSpacing: 0.2,`。

於期望斷言區塊，`reader_settings_line_height_slider` 的 `expect` 之後新增：

```dart
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_letter_spacing_slider')))
          .value,
      0.2,
    );
```

- [ ] **Step 2: 寫失敗測試——null 時顯示預設值 0**

於既有 `test('任一欄位為 null 時，滑桿顯示原型範例預設值', ...)`（第 102-168 行），於 `reader_settings_line_height_slider` 的 `expect` 之後新增：

```dart
    expect(
      tester
          .widget<Slider>(
              find.byKey(const Key('reader_settings_letter_spacing_slider')))
          .value,
      0.0,
    );
```

- [ ] **Step 3: 寫失敗測試——增量按鈕觸發 `onChanged`**

在檔案內任一既有 `testWidgets('點擊...+ 按鈕後...')` 測試（例如「點擊上邊界 + 按鈕」）之後，新增：

```dart
  testWidgets('點擊字距 + 按鈕後，onChanged 帶入 letterSpacing+0.01 且其他欄位不變',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(letterSpacing: 0.10, marginTop: 64),
      (prefs) => result = prefs,
    );

    await tester.tap(
        find.byKey(const Key('reader_settings_letter_spacing_increment')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.letterSpacing, closeTo(0.11, 1e-9));
    expect(result!.marginTop, 64.0, reason: '未被觸碰的欄位應維持原值');
  });
```

- [ ] **Step 4: 執行測試確認失敗**

執行：`cd app && flutter test test/screens/reader_settings_sheet_test.dart`
預期：FAIL（找不到 `Key('reader_settings_letter_spacing_slider')`／`letterSpacing` 建構參數不存在）。

- [ ] **Step 5: `ReaderSettingsSheet` 新增字距滑桿**

編輯 `app/lib/screens/reader_settings_sheet.dart`：

於第 46 行 `static const _defaultParagraphSpacing = 10.0;` 之後新增：

```dart
  static const _defaultLetterSpacing = 0.0;
```

於第 56 行 `late double _paragraphSpacing;` 之後新增：

```dart
  late double _letterSpacing;
```

於 `initState()`（第 72-98 行）第 83 行 `_paragraphSpacing = ...` 賦值敘述之後新增：

```dart
    _letterSpacing = widget.prefs.letterSpacing ?? _defaultLetterSpacing;
```

於 `didUpdateWidget()`（第 100-130 行）對應位置（第 111-113 行 `_paragraphSpacing = ...` 之後）同步新增相同一行：

```dart
        _letterSpacing = widget.prefs.letterSpacing ?? _defaultLetterSpacing;
```

於 `_notifyChanged()`（第 136-158 行）第 142 行 `paragraphSpacing: _toMultiplier(_paragraphSpacing, 10.0),` 之後新增：

```dart
      letterSpacing: _letterSpacing,
```

於 `build()` 內，第 229-241 行「段落間距」`_buildSliderRow` 之後新增一組新的滑桿：

```dart
                _buildSliderRow(
                  keyPrefix: 'reader_settings_letter_spacing',
                  label: '字距',
                  value: _letterSpacing,
                  min: -0.05,
                  max: 1,
                  step: 0.01,
                  displayValue: '${_letterSpacing.toStringAsFixed(2)}em',
                  onChanged: (v) => setState(() {
                    _letterSpacing = double.parse(v.toStringAsFixed(2));
                    _notifyChanged();
                  }),
                ),
```

- [ ] **Step 6: 執行測試確認通過**

執行：`cd app && flutter test test/screens/reader_settings_sheet_test.dart`
預期：全數 PASS。

- [ ] **Step 7: 執行完整分析與全專案測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS。

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "feat(epic-28): Issue 1 Task 4——ReaderSettingsSheet 新增字距滑桿"
```

---

## 完成後的驗證（對照 `issues.md` Issue 1 驗收標準）

- [ ] `flutter analyze`：全專案 "No issues found!"
- [ ] `flutter test`：全專案通過，零回歸
- [ ] （建議，非本計畫強制自動化，採納 2026-08-14 審查 Minor #4／Recommendation #2）於真機或模擬器開啟以下情境，肉眼確認排版無異常：
  - 一般流式 EPUB：拖動「字距」滑桿，確認橫排與切換至直排後皆有視覺變化，且數值持久化（關閉重開書本後維持上次設定）。
  - 帶特殊排版/精排版的流式 EPUB（例如 Calibre 轉檔書籍）：確認字距覆蓋在這類書上依然生效（比照既有 line-height Issue 34 的教訓，書本自行宣告樣式時容易覆蓋無效）。
  - 含大量 SVG 圖形或 MathML 數學公式的書籍：確認 `letter-spacing` 覆蓋規則不會意外影響 SVG 內部 `<text>` 排版（尤其 `publisherStyles === false` 時 selector 改用萬用 `*`）。
  - 滑桿拉至兩端極值（`1.0em`／`-0.05em`），並切換「停用書本 CSS」開關前後，觀察直排 CJK 標點（引號「」、破折號——、刪節號……）是否出現重疊、斷裂或跑位——這是 CSS `letter-spacing` 的通用渲染限制，非本計畫程式碼可修正，若發現嚴重問題另立 Issue 追蹤，不阻塞本 Issue 驗收。
