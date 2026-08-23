# Epic 24 Issue 11 — PDF 新增「換頁動畫」選項（滑動／無） 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PDF 版面設定新增「換頁動畫」選項（滑動／無），滑動維持現行 200ms 動畫效果（預設，零回歸），無動畫則瞬間跳頁（`Duration.zero`），比照既有 `dualPageMode`／`pdfCropMode` 等單書偏好欄位的貫穿模式（`BookReaderPrefs` → `ResolvedPreferences` → `PdfReaderView` 建構參數），並在 `PdfSettingsSheet` 新增對應 UI 選項。

**Architecture:** 新增 `PdfPageTurnAnimation`（`slide`/`none`）列舉，作為 `BookReaderPrefs` 的單書偏好欄位（`null` = 未覆寫，`resolve()` 回退為 `slide`，即目前既有行為）。`PdfReaderView` 新增對應建構參數，內部算出一個 `Duration`（`none` → `Duration.zero`；`slide` → 現行預設 `Duration(milliseconds: 200)`），套用到**全部 4 處**呼叫 `pdfrx` `PdfViewerController` 導頁 API 的位置：`_jumpToPage`／`_nextPage`／`_previousPage`（皆呼叫 `_controller.goToPage()`）與雙頁模式下的 `_goToSpread`（呼叫 `_controller.goToArea()`）——**這比 `issues.md` Issue 11 原始文字描述的「兩處」多兩處**：原始調查是在 Issue 2（雙頁並列）合併之前寫的，`_goToSpread`／`goToArea()` 是雙頁模式跳頁的實際呼叫路徑，本計畫依目前實際程式碼（4 處）為準。`pdfrx` 的 `goToPage()`/`goToArea()` 底層 `_goTo()` 對 `duration == Duration.zero` 有專門的同步捷徑（直接 `setValueWithoutNormalization`、不跑動畫 ticker），這讓「無動畫」與「滑動」兩種設定在 widget test 環境下可用真實時間推進行為區分驗證，不需要 mock。

**Tech Stack:** Flutter/Dart、`pdfrx`（`PdfViewerController.goToPage`/`goToArea` 皆原生支援 `duration` 具名參數，見 `pdfrx-2.4.7/lib/src/widgets/pdf_viewer.dart:4147-4160`，不需要額外套件或原生程式碼）。

**Spec:** `docs/epics/epic-24-pdf-engine-rebuild/issues.md`「Issue 11」。

## Global Constraints

- `PdfPageTurnAnimation` 為**單書偏好欄位**（`BookReaderPrefs`），比照 `dualPageMode`／`pdfCropMode`／`pdfFitMode` 既有模式，**不是**全域偏好（不比照 `GlobalReaderPrefs.consoleLogEnabled` 那條路徑）。
- 預設值為 `PdfPageTurnAnimation.slide`（`null` 回退值），對應現行 `pdfrx` 預設的 200ms 動畫——確保任何既有使用者/既有測試在不指定本欄位時行為與本計畫合併前逐位元組相同（零回歸）。
- `Duration.zero`（`none`）與 `Duration(milliseconds: 200)`（`slide`）**必須套用到全部 4 處**導頁呼叫（`_jumpToPage`／`_nextPage`／`_previousPage`／`_goToSpread`），不得遺漏雙頁模式路徑。
- 只影響 PDF（`PdfReaderView`／`PdfSettingsSheet`）。EPUB／TXT 不在範圍內。
- SQLite `book_reader_prefs` 表新增 1 個欄位，`version` 由 19 提升為 20，比照既有 `_addLetterSpacingColumn`（`epic-28` Issue 1）等單欄位新增的既有慣例（`onUpgrade` 的 `else` 分支內、`oldVersion < 20` 判斷、`_createBookReaderPrefsTable` 同步更新供全新安裝）。
- 每完成一個 Task 就跑一次 `flutter analyze`，維持乾淨。

---

### Task 1：資料層——`PdfPageTurnAnimation` 列舉＋`BookReaderPrefs` 欄位＋SQLite Migration

**Files:**
- Create: `app/lib/reader/pdf_page_turn_animation.dart`
- Modify: `app/lib/reader/book_reader_prefs.dart`
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/reader/book_reader_prefs_test.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Produces: `PdfPageTurnAnimation`（`enum { slide, none }`）；`BookReaderPrefs.pdfPageTurnAnimation`（`PdfPageTurnAnimation?`，`null` = 未覆寫，由 `ResolvedPreferences`/`resolve()` 回退為 `slide`）。

- [x] **Step 1：新增 `PdfPageTurnAnimation` 列舉**

新增 `app/lib/reader/pdf_page_turn_animation.dart`：

```dart
/// PDF 換頁動畫選項（epic-24-pdf-engine-rebuild Issue 11）。[slide]
/// 沿用 pdfrx 預設 200ms 滑動動畫（預設值，null 回退值）；[none] 瞬間跳頁
/// （`Duration.zero`），見 docs/epics/epic-24-pdf-engine-rebuild/issues.md
/// 「Issue 11」。
enum PdfPageTurnAnimation { slide, none }
```

- [x] **Step 2：寫失敗測試——`BookReaderPrefs.pdfPageTurnAnimation` 預設值/相等性/toMap/fromMap/copyWith**

編輯 `app/test/reader/book_reader_prefs_test.dart`：

於檔案開頭 import 區塊新增：

```dart
import 'package:elinkbook/reader/pdf_page_turn_animation.dart';
```

於 `test('BookReaderPrefs.empty 所有欄位皆為 null', ...)`（第 15-42 行）內，`expect(prefs.letterSpacing, isNull);` 之後新增：

```dart
    expect(prefs.pdfPageTurnAnimation, isNull);
```

於 `test('dualPageCoverAlone 為 true／false／null 皆正確 round-trip（避免布林值 0/1 轉換錯誤）', ...)`（第 229-245 行）之後、`test('頁首/頁尾欄位 BookReaderPrefs.empty 為 null...', ...)`（第 247 行）之前，新增以下 3 則測試：

```dart
  test('換頁動畫欄位值完全相同的 BookReaderPrefs 視為相等', () {
    const a = BookReaderPrefs(pdfPageTurnAnimation: PdfPageTurnAnimation.none);
    const b = BookReaderPrefs(pdfPageTurnAnimation: PdfPageTurnAnimation.none);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('換頁動畫欄位不同時視為不相等', () {
    const a = BookReaderPrefs(pdfPageTurnAnimation: PdfPageTurnAnimation.slide);
    const b = BookReaderPrefs(pdfPageTurnAnimation: PdfPageTurnAnimation.none);
    expect(a, isNot(b));
  });

  test('換頁動畫欄位的 toMap／fromMap round-trip 保留欄位值，null 亦正確 round-trip',
      () {
    const withNone =
        BookReaderPrefs(pdfPageTurnAnimation: PdfPageTurnAnimation.none);
    final noneMap = withNone.toMap('book-anim-1');
    expect(noneMap['pdf_page_turn_animation'], 'none');
    expect(BookReaderPrefs.fromMap(noneMap), withNone);

    const withNull = BookReaderPrefs.empty;
    final nullMap = withNull.toMap('book-anim-2');
    expect(nullMap['pdf_page_turn_animation'], isNull);
    expect(BookReaderPrefs.fromMap(nullMap).pdfPageTurnAnimation, isNull);
  });
```

於 `test('copyWith 只更新指定欄位，其餘欄位保留原值', ...)` 之後新增一則：

```dart
  test('copyWith 更新 pdfPageTurnAnimation 時，其餘欄位保留原值', () {
    const original = BookReaderPrefs(
      pdfContrast: 10,
      pdfPageTurnAnimation: PdfPageTurnAnimation.slide,
    );
    final updated =
        original.copyWith(pdfPageTurnAnimation: PdfPageTurnAnimation.none);

    expect(updated.pdfContrast, 10);
    expect(updated.pdfPageTurnAnimation, PdfPageTurnAnimation.none);
  });
```

- [x] **Step 3：執行測試確認失敗**

執行：`cd app && flutter test test/reader/book_reader_prefs_test.dart`
預期：編譯錯誤（`pdfPageTurnAnimation` 具名參數/getter 不存在於 `BookReaderPrefs`，`PdfPageTurnAnimation` 型別不存在）。

- [x] **Step 4：`BookReaderPrefs` 新增 `pdfPageTurnAnimation` 欄位**

編輯 `app/lib/reader/book_reader_prefs.dart`：

於 import 區塊（第 1-10 行）新增（依既有字母序插入 `pdf_fit_mode.dart` 之前）：

```dart
import 'pdf_page_turn_animation.dart';
```

於第 51 行 `final DualPageDirection? dualPageDirection; // null=rtl（僅 PDF 有效）` 之後、第 52 行空行之後（`showHeader` 欄位之前）新增：

```dart

  /// PDF 換頁動畫（epic-24-pdf-engine-rebuild Issue 11）。null=slide
  /// （預設，200ms 滑動動畫，即現行既有行為）。
  final PdfPageTurnAnimation? pdfPageTurnAnimation;
```

於建構子（第 66-97 行）的 `this.dualPageDirection,` 之後新增：

```dart
    this.pdfPageTurnAnimation,
```

於 `toMap()`（第 102-138 行）的 `'dual_page_direction': dualPageDirection?.name,` 之後新增：

```dart
      'pdf_page_turn_animation': pdfPageTurnAnimation?.name,
```

於 `fromMap()`（第 140-206 行）的以下區塊：

```dart
      dualPageDirection: map['dual_page_direction'] == null
          ? null
          : DualPageDirection.values
              .byName(map['dual_page_direction'] as String),
```

之後新增：

```dart
      pdfPageTurnAnimation: map['pdf_page_turn_animation'] == null
          ? null
          : PdfPageTurnAnimation.values
              .byName(map['pdf_page_turn_animation'] as String),
```

於 `operator ==`（第 208-240 行）的 `other.dualPageDirection == dualPageDirection &&` 之後新增：

```dart
      other.pdfPageTurnAnimation == pdfPageTurnAnimation &&
```

於 `hashCode`（第 242-274 行）的 `dualPageDirection,` 之後新增：

```dart
        pdfPageTurnAnimation,
```

於 `copyWith()`（第 281-346 行）參數列的 `DualPageDirection? dualPageDirection,` 之後新增 `PdfPageTurnAnimation? pdfPageTurnAnimation,`；回傳建構式的 `dualPageDirection: dualPageDirection ?? this.dualPageDirection,` 之後新增：

```dart
      pdfPageTurnAnimation: pdfPageTurnAnimation ?? this.pdfPageTurnAnimation,
```

- [x] **Step 5：執行測試確認通過**

執行：`cd app && flutter test test/reader/book_reader_prefs_test.dart`
預期：全數 PASS。

- [x] **Step 6：寫失敗測試——SQLite Migration（version 19→20 新增欄位、全新安裝含括）**

編輯 `app/test/library/sqlite_library_repository_test.dart`：

於 `test('全新安裝的 book_reader_prefs 表包含 letter_spacing 欄位（version 19 起 onCreate 已含括）', ...)`（約第 1794-1805 行）之後新增：

```dart
  test('全新安裝的 book_reader_prefs 表包含 pdf_page_turn_animation 欄位（version 20 起 onCreate 已含括）',
      () async {
    await repository.insertBook(_book('b_page_turn_anim'));
    await repository.database.insert('book_reader_prefs', {
      'book_id': 'b_page_turn_anim',
      'pdf_page_turn_animation': 'none',
    });
    final row = (await repository.database.query('book_reader_prefs',
            where: 'book_id = ?', whereArgs: ['b_page_turn_anim']))
        .single;
    expect(row['pdf_page_turn_animation'], 'none');
  });
```

於 `test('既有 version 18 裝置升級到 version 19，book_reader_prefs 新增 letter_spacing 欄位，既有 margin_top 值不受影響', ...)`（約第 2044-2167 行）之後新增（重建「version 19」舊資料庫結構——與 version 18 結構的差異只多了 `letter_spacing REAL` 這一欄，其餘沿用同一份簡化寫法慣例）：

```dart
  test('既有 version 19 裝置升級到 version 20，book_reader_prefs 新增 pdf_page_turn_animation 欄位，既有 margin_top 值不受影響',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v19_to_v20_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 19」的舊資料庫：book_reader_prefs 表結構自
    // version 19（letter_spacing 欄位加入）起到本次升級前都沒有再變動過，
    // 比照既有 v18→v19 遷移測試的簡化寫法。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 19,
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
              letter_spacing REAL
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

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=19 →
    // newVersion=20），驗證既有 margin_top 值不受影響、pdf_page_turn_animation
    // 新欄位存在且可寫入。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final row = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['margin_top'], 72.0); // 既有資料不受影響
    expect(row['pdf_page_turn_animation'], isNull); // 新欄位存在且預設 NULL

    // 證明新欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'book_reader_prefs',
      {'pdf_page_turn_animation': 'none'},
      where: 'book_id = ?',
      whereArgs: ['b1'],
    );
    final updated = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(updated['pdf_page_turn_animation'], 'none');
  });
```

- [x] **Step 7：執行測試確認失敗**

執行：`cd app && flutter test test/library/sqlite_library_repository_test.dart`
預期：全新安裝測試失敗（`pdf_page_turn_animation` 欄位不存在於新建的表）；升級測試因目前 `SqliteLibraryRepository.open` 仍是 `version: 19`，升級不會被觸發（`oldVersion=19` 已等於目前版本），新欄位同樣不存在，一併失敗。

- [x] **Step 8：SQLite Migration——新增欄位、`version` 提升為 20**

編輯 `app/lib/library/sqlite_library_repository.dart`：

第 42 行 `version: 19,` 改為：

```dart
      version: 20,
```

`_createBookReaderPrefsTable()`（第 307-347 行）的 `CREATE TABLE` 內，第 344 行 `letter_spacing REAL` 改為（新增逗號＋新欄位）：

```dart
        letter_spacing REAL,
        pdf_page_turn_animation TEXT
```

`onUpgrade` 的 `else` 分支（第 113-193 行）內，`if (oldVersion < 19) { ... await _addLetterSpacingColumn(db); }`（第 184-192 行）之後新增：

```dart
          if (oldVersion < 20) {
            // epic-24-pdf-engine-rebuild Issue 11：PDF 換頁動畫新增的 1
            // 個欄位。必須放在 else 分支內（oldVersion >= 2）——理由同
            // _addLetterSpacingColumn：oldVersion < 2 時
            // _createBookReaderPrefsTable 已一步到位建表含
            // pdf_page_turn_animation，若在 else 分支外無條件執行
            // ALTER TABLE，oldVersion == 1 的裝置會重複 ALTER TABLE 拋出
            // 崩潰。
            await _addPdfPageTurnAnimationColumn(db);
          }
```

於 `_addLetterSpacingColumn()`（第 573-583 行）之後新增一個結構相同的新方法：

```dart
  static Future<void> _addPdfPageTurnAnimationColumn(Database db) async {
    // epic-24-pdf-engine-rebuild Issue 11：PDF 換頁動畫欄位，補追加到既有
    // （version 2 起已存在）的 book_reader_prefs 表。比照 _addLetterSpacingColumn
    // 既有慣例，僅在表已存在時才執行 ALTER TABLE。
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='book_reader_prefs'");
    if (tables.isNotEmpty) {
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN pdf_page_turn_animation TEXT');
    }
  }
```

- [x] **Step 9：執行測試確認通過**

執行：`cd app && flutter test test/library/sqlite_library_repository_test.dart`
預期：全數 PASS。

- [x] **Step 10：執行完整分析與既有測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test test/reader/book_reader_prefs_test.dart test/library/sqlite_library_repository_test.dart`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS。

- [x] **Step 11：Commit**

```bash
git add app/lib/reader/pdf_page_turn_animation.dart app/lib/reader/book_reader_prefs.dart app/lib/library/sqlite_library_repository.dart app/test/reader/book_reader_prefs_test.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-24): Issue 11 Task 1——BookReaderPrefs 新增 pdfPageTurnAnimation 欄位，SQLite version 20"
```

---

### Task 2：`ResolvedPreferences` ＋ `ReaderPrefsManagerImpl.resolve()` 透傳

**Files:**
- Modify: `app/lib/reader/resolved_preferences.dart`
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart`
- Test: `app/test/reader/reader_prefs_manager_test.dart`

**Interfaces:**
- Consumes: `BookReaderPrefs.pdfPageTurnAnimation`（Task 1 產出）。
- Produces: `ResolvedPreferences.pdfPageTurnAnimation`（`PdfPageTurnAnimation`，non-null，`resolve()` 內 `book.pdfPageTurnAnimation ?? PdfPageTurnAnimation.slide`）。

- [x] **Step 1：寫失敗測試——`resolve()` 預設值與單書覆寫**

編輯 `app/test/reader/reader_prefs_manager_test.dart`：

於 import 區塊新增：

```dart
import 'package:elinkbook/reader/pdf_page_turn_animation.dart';
```

於既有 `test('全部欄位皆未覆寫時，回傳的 non-null 欄位皆為既存安全預設值', ...)`（第 39-66 行）內，`expect(resolved.dualPageDirection, DualPageDirection.rtl);` 之後新增：

```dart
      expect(resolved.pdfPageTurnAnimation, PdfPageTurnAnimation.slide);
```

於既有 `test('單書覆寫存在時，優先套用單書覆寫，忽略全域預設', ...)`（第 68-100 行）內，`BookReaderPrefs(...)` 建構式的 `dualPageDirection: DualPageDirection.rtl,` 之後新增：

```dart
          pdfPageTurnAnimation: PdfPageTurnAnimation.none,
```

並於同一則測試內的 `expect(resolved.dualPageDirection, DualPageDirection.rtl);` 斷言之後新增：

```dart
      expect(resolved.pdfPageTurnAnimation, PdfPageTurnAnimation.none);
```

- [x] **Step 2：執行測試確認失敗**

執行：`cd app && flutter test test/reader/reader_prefs_manager_test.dart`
預期：編譯錯誤（`pdfPageTurnAnimation` 具名參數/getter 不存在於 `ResolvedPreferences`）。

- [x] **Step 3：`ResolvedPreferences` 新增 `pdfPageTurnAnimation` 欄位**

編輯 `app/lib/reader/resolved_preferences.dart`：

於 import 區塊新增（依既有字母序插入 `pdf_fit_mode.dart` 之前）：

```dart
import 'pdf_page_turn_animation.dart';
```

於第 62 行 `final DualPageDirection dualPageDirection;` 之後新增：

```dart

  /// PDF 換頁動畫（epic-24-pdf-engine-rebuild Issue 11）：恆非 null，
  /// resolve() 內 book.pdfPageTurnAnimation ?? PdfPageTurnAnimation.slide
  /// （預設維持現行 200ms 滑動動畫）。
  final PdfPageTurnAnimation pdfPageTurnAnimation;
```

於建構子（第 86-121 行）的 `required this.dualPageDirection,` 之後新增：

```dart
    this.pdfPageTurnAnimation = PdfPageTurnAnimation.slide,
```

- [x] **Step 4：`ReaderPrefsManagerImpl.resolve()` 透傳**

編輯 `app/lib/reader/reader_prefs_manager_impl.dart`，於 `resolve()` 內（第 189-191 行）：

```dart
      dualPageMode: book.dualPageMode ?? DualPageMode.auto,
      dualPageCoverAlone: book.dualPageCoverAlone ?? true,
      dualPageDirection: book.dualPageDirection ?? DualPageDirection.rtl,
```

之後新增：

```dart
      pdfPageTurnAnimation:
          book.pdfPageTurnAnimation ?? PdfPageTurnAnimation.slide,
```

- [x] **Step 5：執行測試確認通過**

執行：`cd app && flutter test test/reader/reader_prefs_manager_test.dart`
預期：全數 PASS。

- [x] **Step 6：執行完整分析與既有測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test test/reader/`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS。

- [x] **Step 7：Commit**

```bash
git add app/lib/reader/resolved_preferences.dart app/lib/reader/reader_prefs_manager_impl.dart app/test/reader/reader_prefs_manager_test.dart
git commit -m "feat(epic-24): Issue 11 Task 2——ResolvedPreferences 透傳 pdfPageTurnAnimation"
```

---

### Task 3：`PdfReaderView` 接線——4 處導頁呼叫套用動畫時長

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Test: `app/test/reader/pdf_reader_view_test.dart`

**Interfaces:**
- Consumes: `ResolvedPreferences.pdfPageTurnAnimation`（Task 2 產出）。
- Produces: `PdfReaderView.pdfPageTurnAnimation`（`PdfPageTurnAnimation` 建構參數，預設 `PdfPageTurnAnimation.slide`）。

- [x] **Step 1：寫失敗測試——`pdfPageTurnAnimation=none` 時導頁立即反映，預設（slide）時仍需等待動畫**

編輯 `app/test/reader/pdf_reader_view_test.dart`：

於 import 區塊新增：

```dart
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_page_turn_animation.dart';
```

於既有 `testWidgets('pageCount／jumpToPage 正確運作，含邊界情況', ...)`（第 65-104 行）之後新增以下 4 則測試：

```dart
  testWidgets(
      'pdfPageTurnAnimation=none 時，jumpToPage 後單一 pump（無經過時間）已立即反映新頁碼',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
          pdfPageTurnAnimation: PdfPageTurnAnimation.none,
        ),
      ),
    );

    await tester.runAsync(() async {
      for (var i = 0; i < 30 && renderedCount == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(lastPageInfo?.pageIndex, 0);

    PdfReaderView.jumpToPage(key, 4);
    await tester.pump(); // 單一 frame、無經過時間。
    expect(lastPageInfo?.pageIndex, 4);
  });

  testWidgets(
      '預設 pdfPageTurnAnimation（slide）時，jumpToPage 後單一 pump（無經過時間）尚未反映新頁碼，需等待 200ms 動畫',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );

    await tester.runAsync(() async {
      for (var i = 0; i < 30 && renderedCount == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(lastPageInfo?.pageIndex, 0);

    PdfReaderView.jumpToPage(key, 4);
    await tester.pump(); // 單一 frame、無經過時間——動畫尚未跑完。
    expect(lastPageInfo?.pageIndex, 0); // 仍是舊頁碼。

    await tester.pump(const Duration(milliseconds: 300)); // 200ms 動畫跑完。
    expect(lastPageInfo?.pageIndex, 4);
  });

  testWidgets(
      'pdfPageTurnAnimation=none 時，nextPage()／previousPage() 也在單一 pump 後立即反映新頁碼',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
          pdfPageTurnAnimation: PdfPageTurnAnimation.none,
        ),
      ),
    );

    await tester.runAsync(() async {
      for (var i = 0; i < 30 && renderedCount == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(lastPageInfo?.pageIndex, 0);

    PdfReaderView.nextPage(key);
    await tester.pump();
    expect(lastPageInfo?.pageIndex, 1);

    PdfReaderView.previousPage(key);
    await tester.pump();
    expect(lastPageInfo?.pageIndex, 0);
  });

  testWidgets(
      'dualPageMode=always 且 pdfPageTurnAnimation=none 時，跳頁在單一 pump 後立即反映（涵蓋雙頁 _goToSpread／goToArea 路徑）',
      (tester) async {
    var renderedCount = 0;
    PdfPageInfo? lastPageInfo;
    final key = GlobalKey<State<PdfReaderView>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
          dualPageMode: DualPageMode.always,
          pdfPageTurnAnimation: PdfPageTurnAnimation.none,
        ),
      ),
    );

    await tester.runAsync(() async {
      for (var i = 0; i < 30 && renderedCount == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump(); // 讓雙頁版面計算（_layoutSpreadPages）完成一輪 build。
    final initialIndex = lastPageInfo?.pageIndex;

    PdfReaderView.nextPage(key);
    await tester.pump(); // 單一 frame、無經過時間。
    expect(lastPageInfo?.pageIndex, isNot(initialIndex));
  });
```

- [x] **Step 2：執行測試確認失敗**

執行：`cd app && flutter test test/reader/pdf_reader_view_test.dart`
預期：編譯錯誤（`pdfPageTurnAnimation` 具名參數不存在於 `PdfReaderView`）。

- [x] **Step 3：`PdfReaderView` 新增 `pdfPageTurnAnimation` 建構參數與內部 `Duration` 換算**

編輯 `app/lib/reader/pdf_reader_view.dart`：

於 import 區塊（第 10-26 行）新增（依既有慣例插入 `pdf_page_info.dart` 之前）：

```dart
import 'pdf_page_turn_animation.dart';
```

於第 55 行 `final bool isLandscape;` 之後新增：

```dart

  // ── epic-24-pdf-engine-rebuild Issue 11 新增 ──
  /// PDF 換頁動畫，預設 [PdfPageTurnAnimation.slide]（現行既有 200ms 動畫，
  /// 未傳此參數的既有呼叫端行為不變）。
  final PdfPageTurnAnimation pdfPageTurnAnimation;
```

於建構子（第 91-118 行）的 `this.isLandscape = false,` 之後新增：

```dart
    this.pdfPageTurnAnimation = PdfPageTurnAnimation.slide,
```

於 `_PdfReaderViewState` 內（緊接第 264-269 行 `_dualPageEnabled` getter 之後）新增一個私有 getter：

```dart

  /// [pdfPageTurnAnimation] 對應的實際 [Duration]，供全部 4 處導頁呼叫
  /// （_jumpToPage/_nextPage/_previousPage/_goToSpread）共用單一定義來源。
  /// pdfrx 的 goToPage()/goToArea() 對 Duration.zero 有專門的同步捷徑（見
  /// pdfrx-2.4.7 pdf_viewer.dart `_goTo()` 的 `if (duration == Duration.zero)`
  /// 分支），瞬間跳頁不會跑動畫 ticker。
  Duration get _pageTurnDuration => widget.pdfPageTurnAnimation ==
          PdfPageTurnAnimation.none
      ? Duration.zero
      : const Duration(milliseconds: 200);
```

於 `_jumpToPage`（第 559-569 行）的：

```dart
      _controller.goToPage(pageNumber: pageIndex + 1); // Issue 1 原邏輯。
```

改為：

```dart
      _controller.goToPage(
        pageNumber: pageIndex + 1, // Issue 1 原邏輯。
        duration: _pageTurnDuration,
      );
```

於 `_nextPage`（第 571-585 行）的：

```dart
      _controller.goToPage(pageNumber: current + 1);
```

改為：

```dart
      _controller.goToPage(
        pageNumber: current + 1,
        duration: _pageTurnDuration,
      );
```

於 `_previousPage`（第 587-601 行）的：

```dart
      _controller.goToPage(pageNumber: current - 1);
```

改為：

```dart
      _controller.goToPage(
        pageNumber: current - 1,
        duration: _pageTurnDuration,
      );
```

於 `_goToSpread`（第 680-686 行）的：

```dart
  void _goToSpread(int spreadIndex, PdfSpreadLayout layout) {
    if (spreadIndex < 0 || spreadIndex >= layout.spreadCount) return;
    unawaited(_controller.goToArea(
      rect: layout.spreadRects[spreadIndex],
      anchor: PdfPageAnchor.all,
    ));
  }
```

改為：

```dart
  void _goToSpread(int spreadIndex, PdfSpreadLayout layout) {
    if (spreadIndex < 0 || spreadIndex >= layout.spreadCount) return;
    unawaited(_controller.goToArea(
      rect: layout.spreadRects[spreadIndex],
      anchor: PdfPageAnchor.all,
      duration: _pageTurnDuration,
    ));
  }
```

- [x] **Step 4：執行測試確認通過**

執行：`cd app && flutter test test/reader/pdf_reader_view_test.dart`
預期：全數 PASS。

- [x] **Step 5：執行完整分析與既有測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test test/reader/`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS（尤其確認既有「pageCount／jumpToPage 正確運作，含邊界情況」等測試未因新增可選建構參數而回歸——新參數有預設值 `slide`，既有呼叫端行為逐位元組不變）。

- [x] **Step 6：Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_test.dart
git commit -m "feat(epic-24): Issue 11 Task 3——PdfReaderView 4 處導頁呼叫套用 pdfPageTurnAnimation"
```

---

### Task 4：`reader_screen.dart` 傳遞 `resolved.pdfPageTurnAnimation`

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: `ResolvedPreferences.pdfPageTurnAnimation`（Task 2 產出）、`PdfReaderView.pdfPageTurnAnimation`（Task 3 產出）。

- [x] **Step 1：寫失敗測試——持久化的 `pdfPageTurnAnimation` 正確載入並傳給 `PdfReaderView`**

編輯 `app/test/screens/reader_screen_test.dart`：

於既有 `testWidgets('尚未持久化雙頁偏好設定時，FoliateEpubReaderView 的 dualPageMode 為 auto（預設值）', ...)`（第 286-305 行）之後新增以下 2 則測試：

```dart
  testWidgets('開啟該書已有的持久化換頁動畫偏好設定後，PdfReaderView 的 pdfPageTurnAnimation 正確載入',
      (tester) async {
    await prefsManager.saveBookPrefs(
      'b1',
      const BookReaderPrefs(
        pdfPageTurnAnimation: PdfPageTurnAnimation.none,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView =
        tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.pdfPageTurnAnimation, PdfPageTurnAnimation.none);
  });

  testWidgets('尚未持久化換頁動畫偏好設定時，PdfReaderView 的 pdfPageTurnAnimation 為 slide（預設值）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView =
        tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.pdfPageTurnAnimation, PdfPageTurnAnimation.slide);
  });
```

若檔案 import 區塊尚未有 `PdfPageTurnAnimation`，一併新增：

```dart
import 'package:elinkbook/reader/pdf_page_turn_animation.dart';
```

- [x] **Step 2：執行測試確認失敗**

執行：`cd app && flutter test test/screens/reader_screen_test.dart`
預期：編譯錯誤（`pdfPageTurnAnimation` getter 不存在於 `PdfReaderView`，若 Task 3 已完成則改為斷言失敗——`reader_screen.dart` 尚未傳遞此參數，`pdfView.pdfPageTurnAnimation` 恆為 widget 層預設值 `slide`，第一則測試會失敗）。

- [x] **Step 3：`reader_screen.dart` 傳遞 `resolved.pdfPageTurnAnimation`**

編輯 `app/lib/screens/reader_screen.dart`，於 `case BookFormat.pdf:` 分支內（約第 2325-2327 行）：

```dart
          dualPageMode: resolved.dualPageMode,
          dualPageCoverAlone: resolved.dualPageCoverAlone,
          dualPageDirection: resolved.dualPageDirection,
```

之後新增：

```dart
          pdfPageTurnAnimation: resolved.pdfPageTurnAnimation,
```

- [x] **Step 4：執行測試確認通過**

執行：`cd app && flutter test test/screens/reader_screen_test.dart`
預期：全數 PASS。

- [x] **Step 5：執行完整分析與全專案測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS。

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-24): Issue 11 Task 4——reader_screen.dart 傳遞 resolved.pdfPageTurnAnimation"
```

---

### Task 5：UI——`PdfSettingsSheet` 新增「換頁動畫」選項

**Files:**
- Modify: `app/lib/screens/pdf_settings_sheet.dart`
- Test: `app/test/screens/pdf_settings_sheet_test.dart`

**Interfaces:**
- Consumes: `BookReaderPrefs.pdfPageTurnAnimation`（Task 1 產出）。
- Produces：使用者互動後，透過既有 `onChanged`（`ValueChanged<BookReaderPrefs>`）回報包含 `pdfPageTurnAnimation` 的完整 `BookReaderPrefs`。

- [x] **Step 1：寫失敗測試——選項存在、點擊觸發 `onChanged`、不清空既有值**

編輯 `app/test/screens/pdf_settings_sheet_test.dart`：

於 import 區塊新增：

```dart
import 'package:elinkbook/reader/pdf_page_turn_animation.dart';
```

於檔案結尾第一個 helper 函式（`Future<void> _pumpSheet(...)`，約第 567 行）之前，新增以下 4 則測試：

```dart
  testWidgets('換頁動畫兩個選項皆存在', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(
      find.byKey(const Key('pdf_settings_page_turn_animation_slide')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('pdf_settings_page_turn_animation_none')),
      findsOneWidget,
    );
  });

  testWidgets('點擊「無」選項後，onChanged 帶入 pdfPageTurnAnimation=none', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => notified = prefs);

    await tester
        .tap(find.byKey(const Key('pdf_settings_page_turn_animation_none')));
    await tester.pump();

    expect(notified?.pdfPageTurnAnimation, PdfPageTurnAnimation.none);
  });

  testWidgets('點擊「滑動」選項後，onChanged 帶入 pdfPageTurnAnimation=slide', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfPageTurnAnimation: PdfPageTurnAnimation.none),
      (prefs) => notified = prefs,
    );

    await tester
        .tap(find.byKey(const Key('pdf_settings_page_turn_animation_slide')));
    await tester.pump();

    expect(notified?.pdfPageTurnAnimation, PdfPageTurnAnimation.slide);
  });

  testWidgets(
      '已持久化 pdfPageTurnAnimation 時，調整濾鏡分頁不會清空 pdfPageTurnAnimation（回歸檢查）',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfPageTurnAnimation: PdfPageTurnAnimation.none),
      (prefs) => notified = prefs,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_contrast_increment')));
    await tester.pump();

    expect(notified?.pdfPageTurnAnimation, PdfPageTurnAnimation.none); // 關鍵斷言：未被清空
  });
```

- [x] **Step 2：執行測試確認失敗**

執行：`cd app && flutter test test/screens/pdf_settings_sheet_test.dart`
預期：找不到 `Key('pdf_settings_page_turn_animation_slide')`／`Key('pdf_settings_page_turn_animation_none')`。

- [x] **Step 3：`PdfSettingsSheet` 新增「換頁動畫」UI 選項**

編輯 `app/lib/screens/pdf_settings_sheet.dart`：

於 import 區塊（第 1-7 行）新增：

```dart
import '../reader/pdf_page_turn_animation.dart';
```

於 `_PdfSettingsSheetState` 欄位宣告（第 37-49 行）的 `late DualPageDirection _dualPageDirection;` 之後新增：

```dart
  late PdfPageTurnAnimation _pageTurnAnimation;
```

於 `initState()`（第 51-65 行）的 `_dualPageDirection = widget.prefs.dualPageDirection ?? DualPageDirection.rtl;` 之後新增：

```dart
    _pageTurnAnimation =
        widget.prefs.pdfPageTurnAnimation ?? PdfPageTurnAnimation.slide;
```

於 `_notifyChanged()`（第 73-91 行）的 `dualPageDirection: _dualPageDirection,` 之後新增：

```dart
      pdfPageTurnAnimation: _pageTurnAnimation,
```

於 `_buildDisplayTab()`（第 143-273 行）開頭的既有選項常數宣告（`fitOptions`／`dualPageOptions`／`directionOptions`，第 144-168 行）之後新增：

```dart
    const pageTurnAnimationOptions = [
      (PdfPageTurnAnimation.slide, 'slide', Icons.swipe, '滑動'),
      (PdfPageTurnAnimation.none, 'none', Icons.flash_on, '無'),
    ];
```

於「頁面方向」`Wrap` 區塊（第 249-268 行）之後、`Column` 的 `children` 清單結尾（第 269 行 `],` 之前）新增：

```dart
            const SizedBox(height: 16),
            const Text('換頁動畫'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: pageTurnAnimationOptions.map((option) {
                final (animation, keySuffix, icon, tooltip) = option;
                final selected = _pageTurnAnimation == animation;
                return IconButton(
                  key: Key('pdf_settings_page_turn_animation_$keySuffix'),
                  icon: Icon(icon),
                  tooltip: tooltip,
                  color:
                      selected ? Theme.of(context).colorScheme.primary : null,
                  onPressed: () => setState(() {
                    _pageTurnAnimation = animation;
                    _notifyChanged();
                  }),
                );
              }).toList(),
            ),
```

- [x] **Step 4：執行測試確認通過**

執行：`cd app && flutter test test/screens/pdf_settings_sheet_test.dart`
預期：全數 PASS（含 Step 1 新增的 4 則測試與全部既有測試）。

- [x] **Step 5：執行完整分析與全專案測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS。

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/pdf_settings_sheet.dart app/test/screens/pdf_settings_sheet_test.dart
git commit -m "feat(epic-24): Issue 11 Task 5——PdfSettingsSheet 新增換頁動畫選項"
```

---

## 完成後的驗證（對照 `issues.md` Issue 11 驗收標準）

- [x] `flutter analyze`：全專案 "No issues found!"
- [x] `flutter test`：全專案通過，零回歸
- [ ] （建議，非本計畫強制自動化）於真機或模擬器：開啟一本多頁 PDF，於「版面設定」切換「換頁動畫」為「無」，確認翻頁（含雙頁模式）為瞬間跳轉、無滑動效果；切回「滑動」確認恢復原本的動畫效果。
