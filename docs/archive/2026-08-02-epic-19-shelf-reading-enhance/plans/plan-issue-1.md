# Epic 19 Issue 1 — 全螢幕模式 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增一個獨立於既有「沉浸模式」的每本書持久化開關「全螢幕模式」，開啟時隱藏 Android 系統狀態列與導覽列，不影響 App 自己的 AppBar/Footer/頁首/頁尾/懸浮按鈕。

**Architecture:** 資料層新增 `BookReaderPrefs.fullscreen`（`bool?`，SQLite schema v14→v15）→ `ResolvedPreferences.fullscreen`（`bool`，`ReaderPrefsManagerImpl.resolve()` 決成 `false`）→ 三個設定面板新增開關寫回 → `ReaderScreen` 依 `_resolved.fullscreen` 呼叫新增的 `elinkbook/fullscreen` platform channel → `MainActivity.kt` 透過原生 `WindowInsetsControllerCompat` 實際隱藏/顯示系統列。

**Tech Stack:** Flutter/Dart（`BookReaderPrefs`／`ResolvedPreferences`／`ReaderPrefsManagerImpl`／`ReaderScreen`／3 個設定面板）、SQLite（`sqflite`）、Kotlin（`MainActivity.kt`）、`androidx.core:core-ktx`（`WindowCompat`/`WindowInsetsControllerCompat`/`WindowInsetsCompat`）。

## Global Constraints

- **語言**：所有程式碼註解、commit 訊息、計畫文件皆用正體中文（`CLAUDE.md`）。
- **`minSdk` 不得高於 API 30**（目前實際為 24，不因本次變動調整，`WindowInsetsControllerCompat` 是 AndroidX 相容性 API，支援回溯到 API 14）。
- **`compileSdk`/`targetSdk` 維持 Flutter 預設值（目前 36）不動**——本次改走原生 `WindowInsetsControllerCompat` 正是為了避免調整這兩個全域設定（見 ADR 0015）。
- **不修改 `readest/foliate-js` 釘定版本本身**——本 Issue 完全不涉及 `main.js`/`paginator.js`。
- **全螢幕模式與既有「沉浸模式」（`_chromeVisible`）、`showHeader`/`showFooter` 三者互不干涉**——`_applySystemUiMode()` 只呼叫 `elinkbook/fullscreen` 頻道，不讀取/不修改另外兩者的狀態。
- **`BookReaderPrefs.fullscreen` 為 nullable bool，`null`＝未覆寫**，比照既有 `showHeader`/`showFooter` 欄位慣例（無全域預設層），`resolve()` 決成 `false`（預設關閉）。
- **參考文件**：`docs/epics/epic-19-shelf-reading-enhance/design.md`「決策」①全螢幕模式；`docs/epics/epic-19-shelf-reading-enhance/spec.md`「功能 ① 全螢幕模式」；`docs/adr/0015-fullscreen-native-window-insets-controller.md`。

---

### Task 1: `BookReaderPrefs.fullscreen` 欄位

**Files:**
- Modify: `app/lib/reader/book_reader_prefs.dart`
- Test: `app/test/reader/book_reader_prefs_test.dart`

**Interfaces:**
- Produces: `BookReaderPrefs.fullscreen`（`bool?`，建構參數／`toMap`/`fromMap`/`copyWith`/`==`/`hashCode` 皆涵蓋）——後續 Task 依賴此欄位名稱與型別。

- [x] **Step 1: 撰寫失敗測試**

在 `app/test/reader/book_reader_prefs_test.dart` 檔案末尾（`}` 之前）新增：

```dart
  test('全螢幕模式欄位 BookReaderPrefs.empty 為 null（未覆寫，交由 ResolvedPreferences 決定預設值 false）',
      () {
    const prefs = BookReaderPrefs.empty;
    expect(prefs.fullscreen, isNull);
  });

  test('全螢幕模式欄位值完全相同的 BookReaderPrefs 視為相等', () {
    const a = BookReaderPrefs(fullscreen: true);
    const b = BookReaderPrefs(fullscreen: true);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('全螢幕模式欄位值不同時視為不相等', () {
    const a = BookReaderPrefs(fullscreen: true);
    const b = BookReaderPrefs(fullscreen: false);
    expect(a, isNot(b));
  });

  test('fullscreen 為 true／false／null 皆正確 toMap／fromMap round-trip（避免布林值 0/1 轉換錯誤）',
      () {
    const withTrue = BookReaderPrefs(fullscreen: true);
    final trueMap = withTrue.toMap('book-fs-1');
    expect(trueMap['fullscreen'], 1);
    expect(BookReaderPrefs.fromMap(trueMap).fullscreen, isTrue);

    const withFalse = BookReaderPrefs(fullscreen: false);
    final falseMap = withFalse.toMap('book-fs-2');
    expect(falseMap['fullscreen'], 0);
    expect(BookReaderPrefs.fromMap(falseMap).fullscreen, isFalse);

    const withNull = BookReaderPrefs.empty;
    final nullMap = withNull.toMap('book-fs-3');
    expect(nullMap['fullscreen'], isNull);
    expect(BookReaderPrefs.fromMap(nullMap).fullscreen, isNull);
  });

  test('copyWith 更新 fullscreen 時，其餘欄位保留原值', () {
    const original = BookReaderPrefs(fontSize: 18, fullscreen: false);
    final updated = original.copyWith(fullscreen: true);

    expect(updated.fontSize, 18);
    expect(updated.fullscreen, isTrue);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/book_reader_prefs_test.dart`
Expected: FAIL——`The named parameter 'fullscreen' isn't defined`（`BookReaderPrefs` 建構子尚未有這個參數）。

- [x] **Step 3: 實作欄位**

編輯 `app/lib/reader/book_reader_prefs.dart`：

在 `columnMode`/`columnSize` 欄位宣告之後（第 56-57 行）新增：

```dart
  final ColumnMode? columnMode; // null=未覆寫（使用 auto 預設），見 epic-18 Issue 6
  final double? columnSize; // null=未覆寫（使用 720.0 預設），360~1440px，僅 columnMode=auto 時有效

  /// 全螢幕模式（epic-19-shelf-reading-enhance Issue 1）：只控制 Android
  /// 系統狀態列/導覽列，與 showHeader/showFooter、既有的沉浸模式
  /// （_chromeVisible）完全獨立，互不干涉。null=未覆寫，resolve() 決成
  /// false（預設關閉），實際隱藏/顯示機制見 ADR 0015（原生
  /// WindowInsetsControllerCompat，非 Flutter SystemChrome）。
  final bool? fullscreen;
```

在建構子參數列（`this.columnMode,`/`this.columnSize,` 之後）新增：

```dart
    this.columnMode,
    this.columnSize,
    this.fullscreen,
  });
```

在 `toMap()` 的 `'column_size': columnSize,` 之後新增：

```dart
      'column_size': columnSize,
      'fullscreen': fullscreen == null ? null : (fullscreen! ? 1 : 0),
    };
```

在 `fromMap()` 的 `columnSize: (map['column_size'] as num?)?.toDouble(),` 之後新增：

```dart
      columnSize: (map['column_size'] as num?)?.toDouble(),
      fullscreen:
          map['fullscreen'] == null ? null : (map['fullscreen'] as int) == 1,
    );
  }
```

在 `==` 運算子的 `other.columnSize == columnSize &&` 之後新增：

```dart
      other.columnSize == columnSize &&
      other.fullscreen == fullscreen;
```

在 `hashCode` 的 `columnSize,` 之後新增：

```dart
        columnSize,
        fullscreen,
      ]);
```

在 `copyWith()` 的參數列與回傳值皆新增 `fullscreen`：

```dart
  BookReaderPrefs copyWith({
    // ...既有參數不變...
    ColumnMode? columnMode,
    double? columnSize,
    bool? fullscreen,
  }) {
    return BookReaderPrefs(
      // ...既有欄位不變...
      columnMode: columnMode ?? this.columnMode,
      columnSize: columnSize ?? this.columnSize,
      fullscreen: fullscreen ?? this.fullscreen,
    );
  }
```

- [x] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/book_reader_prefs_test.dart`
Expected: PASS（全部測試通過，含既有測試無回歸）。

- [x] **Step 5: Commit**

```bash
git add app/lib/reader/book_reader_prefs.dart app/test/reader/book_reader_prefs_test.dart
git commit -m "feat(epic-19): Issue 1 Task 1 新增 BookReaderPrefs.fullscreen 欄位"
```

---

### Task 2: SQLite schema v14→v15，`book_reader_prefs` 表新增 `fullscreen` 欄位

**Files:**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes: 無（純資料庫 schema 變更）。
- Produces: `book_reader_prefs.fullscreen` 欄位（`INTEGER`，nullable）——Task 3 的 `BookReaderPrefsRepository`（透過 `BookReaderPrefs.toMap`/`fromMap`，已在 Task 1 完成）依賴此欄位存在。

- [x] **Step 1: 撰寫失敗測試（全新安裝）**

在 `app/test/library/sqlite_library_repository_test.dart` 找到現有的「全新安裝的 book_reader_prefs 表包含邊距 4 個欄位（version 14 起 onCreate 已含括）」測試（約第 1748 行），在其後新增：

```dart
  test('全新安裝的 book_reader_prefs 表包含 fullscreen 欄位（version 15 起 onCreate 已含括）',
      () async {
    await repository.insertBook(_book('b_fullscreen'));
    await repository.database.insert('book_reader_prefs', {
      'book_id': 'b_fullscreen',
      'fullscreen': 1,
    });

    final row = (await repository.database.query('book_reader_prefs',
            where: 'book_id = ?', whereArgs: ['b_fullscreen']))
        .single;
    expect(row['fullscreen'], 1);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/library/sqlite_library_repository_test.dart -n "全新安裝的 book_reader_prefs 表包含 fullscreen 欄位"`
Expected: FAIL——`DatabaseException(table book_reader_prefs has no column named fullscreen)`。

- [x] **Step 3: 實作 `_createBookReaderPrefsTable` 與 schema version**

編輯 `app/lib/library/sqlite_library_repository.dart`：

`open()` 內 `version: 14,` 改為：

```dart
      version: 15,
```

`_createBookReaderPrefsTable()`（第 190-222 行）的 `CREATE TABLE` 陳述式，在 `margin_right REAL` 之後新增一欄（注意：最後一欄不加逗號，需把逗號移到 `margin_right REAL` 後面）：

```dart
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
```

- [x] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/library/sqlite_library_repository_test.dart -n "全新安裝的 book_reader_prefs 表包含 fullscreen 欄位"`
Expected: PASS。

- [x] **Step 5: 撰寫失敗測試（既有裝置升級）**

在同一測試檔案，緊接著 v13→v14 遷移測試（約第 1885 行 `});` 之後）新增：

```dart
  test('既有 version 14 裝置升級到 version 15，book_reader_prefs 新增 fullscreen 欄位，既有 margin_top 值不受影響',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v14_to_v15_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 14」的舊資料庫：手動以 version 14 當時的完整
    // schema（book_reader_prefs 含邊距 4 個欄位、不含 fullscreen）建立，
    // 不透過 SqliteLibraryRepository.open()（該方法目前的 onCreate 已經是
    // version 15 的最終 schema），比照既有 v13→v14 遷移測試寫法。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 14,
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
              margin_right REAL
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

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=14 →
    // newVersion=15），驗證既有 margin_top 值不受影響、fullscreen 新欄位
    // 存在且可寫入。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final row = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['margin_top'], 72.0); // 既有資料不受影響
    expect(row['fullscreen'], isNull); // 新欄位存在且預設 NULL

    // 證明新欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'book_reader_prefs',
      {'fullscreen': 1},
      where: 'book_id = ?',
      whereArgs: ['b1'],
    );
    final updated = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(updated['fullscreen'], 1);
  });
```

- [x] **Step 6: 執行測試確認失敗**

Run: `cd app && flutter test test/library/sqlite_library_repository_test.dart -n "既有 version 14 裝置升級到 version 15"`
Expected: FAIL——`row['fullscreen']` 會拋出 `NoSuchMethodError` 或欄位不存在的錯誤（`onUpgrade` 尚未處理 `oldVersion < 15`）。

- [x] **Step 7: 實作 `_addFullscreenColumn` 與 `onUpgrade` 分支**

編輯 `app/lib/library/sqlite_library_repository.dart`：

在 `_addMarginColumns()` 方法定義之後（第 418 行 `}` 之後）新增：

```dart
  static Future<void> _addFullscreenColumn(Database db) async {
    // epic-19-shelf-reading-enhance Issue 1：全螢幕模式開關欄位，補追加到
    // 既有（version 2 起已存在）的 book_reader_prefs 表。比照
    // _addMarginColumns 既有慣例，僅在表已存在時才執行 ALTER TABLE。
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='book_reader_prefs'");
    if (tables.isNotEmpty) {
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN fullscreen INTEGER');
    }
  }
```

`onUpgrade` 內既有的 `if (oldVersion < 14) { await _addMarginColumns(db); }` 分支之後（仍在 `else` 區塊內，第 124-125 行之後、第 126 行 `}` 之前）新增：

```dart
          if (oldVersion < 14) {
            // ...既有註解與程式碼不變...
            await _addMarginColumns(db);
          }
          if (oldVersion < 15) {
            // epic-19-shelf-reading-enhance Issue 1：全螢幕模式開關新增的
            // 1 個欄位。必須放在 else 分支內（oldVersion >= 2）——理由同
            // _addMarginColumns：oldVersion < 2 時 _createBookReaderPrefsTable
            // 已一步到位建表含 fullscreen，若在 else 分支外無條件執行
            // ALTER TABLE，oldVersion == 1 的裝置會重複 ALTER TABLE 拋出
            // 崩潰。
            await _addFullscreenColumn(db);
          }
        }
```

- [x] **Step 8: 執行測試確認通過**

Run: `cd app && flutter test test/library/sqlite_library_repository_test.dart`
Expected: PASS（全部測試通過，含既有測試無回歸）。

- [x] **Step 9: Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-19): Issue 1 Task 2 SQLite schema v14→v15，新增 fullscreen 欄位"
```

---

### Task 3: `ResolvedPreferences.fullscreen` 與 `ReaderPrefsManagerImpl.resolve()` 接通

**Files:**
- Modify: `app/lib/reader/resolved_preferences.dart`
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart`
- Test: `app/test/reader/reader_prefs_manager_test.dart`

**Interfaces:**
- Consumes: `BookReaderPrefs.fullscreen`（Task 1）。
- Produces: `ResolvedPreferences.fullscreen`（`bool`，non-nullable，預設 `false`）——Task 5（`ReaderScreen`）依賴此欄位。

- [x] **Step 1: 撰寫失敗測試**

在 `app/test/reader/reader_prefs_manager_test.dart` 找到「全部欄位皆未覆寫時，回傳的 non-null 欄位皆為既存安全預設值」測試（約第 39 行），在 `expect(resolved.showNavZoneDebugOverlay, isFalse);` 之後新增：

```dart
      expect(resolved.showNavZoneDebugOverlay, isFalse);
      expect(resolved.fullscreen, isFalse);
    });
```

找到「單書覆寫存在時，優先套用單書覆寫，忽略全域預設」測試（約第 65 行），在 `bookPrefs` 建構子的 `columnSize: 600.0,` 之後新增 `fullscreen: true,`，並在 `expect(resolved.columnSize, 600.0);` 之後新增：

```dart
      expect(resolved.columnSize, 600.0);
      expect(resolved.fullscreen, isTrue);
    });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/reader_prefs_manager_test.dart`
Expected: FAIL——`The getter 'fullscreen' isn't defined for the class 'ResolvedPreferences'`。

- [x] **Step 3: 實作**

編輯 `app/lib/reader/resolved_preferences.dart`：

在 `showNavZoneDebugOverlay` 欄位宣告（第 70 行）之後新增：

```dart
  final bool showNavZoneDebugOverlay;

  /// 全螢幕模式（epic-19-shelf-reading-enhance Issue 1）：恆非 null，
  /// resolve() 內 book.fullscreen ?? false（預設關閉，無全域預設層，比照
  /// showHeader/showFooter 的既有慣例）。
  final bool fullscreen;
```

建構子的 `required this.showNavZoneDebugOverlay,` 之後新增：

```dart
    required this.showNavZoneDebugOverlay,
    this.fullscreen = false,
  });
```

編輯 `app/lib/reader/reader_prefs_manager_impl.dart`：

`resolve()` 內 `showNavZoneDebugOverlay: global.showNavZoneDebugOverlay,` 之後新增：

```dart
      showNavZoneDebugOverlay: global.showNavZoneDebugOverlay,
      fullscreen: book.fullscreen ?? false,
    );
```

- [x] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/reader/reader_prefs_manager_test.dart`
Expected: PASS。

- [x] **Step 5: 執行全專案測試確認無回歸**

Run: `cd app && flutter test`
Expected: PASS（`ResolvedPreferences` 建構子新增的 `fullscreen` 有預設值 `false`，既有呼叫端不需要修改也不會壞）。

- [x] **Step 6: Commit**

```bash
git add app/lib/reader/resolved_preferences.dart app/lib/reader/reader_prefs_manager_impl.dart app/test/reader/reader_prefs_manager_test.dart
git commit -m "feat(epic-19): Issue 1 Task 3 ResolvedPreferences.fullscreen 接通 resolve()"
```

---

### Task 4：原生 `elinkbook/fullscreen` platform channel（`WindowInsetsControllerCompat`）

**Files:**
- Modify: `app/android/app/build.gradle.kts`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`

**Interfaces:**
- Consumes: 無。
- Produces: platform channel `elinkbook/fullscreen`，方法 `setEnabled(bool)`——Task 5（`ReaderScreen`）依賴此頻道名稱與方法簽章。

**測試說明（比照 `spec.md`「測試決策」與本專案既有慣例）**：這是純原生 Kotlin 呼叫 Android Window API 的膠水程式碼，`WindowInsetsControllerCompat` 需要真實 `Window`/`View`，本專案沒有 Robolectric 等原生 UI 模擬框架（比照既有 `main.js`/`FoliateEpubReaderView.kt` 的 `setAttribute`/`evaluateJavascript` 呼叫「無 JVM/JS 單元測試」的既有慣例），本 Task 無自動化測試步驟，正確性由 Task 7 真機驗收確認。

- [x] **Step 1: 新增 `androidx.core:core-ktx` 依賴**

編輯 `app/android/app/build.gradle.kts`，在 `dependencies`區塊既有的 `implementation("androidx.fragment:fragment-ktx:1.8.9")` 之後新增：

```kotlin
    implementation("androidx.fragment:fragment-ktx:1.8.9")
    implementation("androidx.core:core-ktx:1.15.0")
```

- [x] **Step 2: 新增 platform channel**

編輯 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`：

在檔案頂部既有 import 區塊（`import io.flutter.plugin.common.MethodChannel` 之後）新增：

```kotlin
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.plugin.common.MethodChannel
```

在 `configureFlutterEngine()` 內既有 `volumeKeyChannel` 設定區塊（第 165-189 行）之後、方法結尾 `}` 之前新增：

```kotlin
        volumeKeyChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "elinkbook/volume_key")
        volumeKeyChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "notifyLeavingReader" -> {
                    ReaderViewAttachmentTracker.suppressedUntilReattach = true
                    result.success(null)
                }
                "attachReaderView" -> {
                    ReaderViewAttachmentTracker.attach()
                    result.success(null)
                }
                "detachReaderView" -> {
                    ReaderViewAttachmentTracker.detach()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // 全螢幕模式（epic-19-shelf-reading-enhance Issue 1，見 ADR 0015）：
        // Flutter 官方 SystemChrome.setEnabledSystemUIMode() 在本專案目前
        // targetSdk（36）下已確認無效（Flutter SDK 官方文件：API 36+ 一律
        // 強制 edgeToEdge、無退出方法），改用原生 WindowInsetsControllerCompat
        // 直接操作 Window，不經過 Flutter 引擎的 SystemUiMode 限制。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "elinkbook/fullscreen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        val enabled = call.arguments as Boolean
                        val controller =
                            WindowCompat.getInsetsController(window, window.decorView)
                        if (enabled) {
                            controller.systemBarsBehavior =
                                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                            controller.hide(WindowInsetsCompat.Type.systemBars())
                        } else {
                            controller.show(WindowInsetsCompat.Type.systemBars())
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
```

（上述區塊取代原本檔案結尾的 `}` `}`——新增的 `elinkbook/fullscreen` 頻道註冊插入在 `volumeKeyChannel` 設定之後、`configureFlutterEngine()` 方法與 `MainActivity` 類別的結尾大括號之前。）

- [x] **Step 3: 編譯確認無語法錯誤**

Run: `cd app && flutter build apk --debug`
Expected: `BUILD SUCCESSFUL`，無 Kotlin 編譯錯誤。

- [x] **Step 4: Commit**

```bash
git add app/android/app/build.gradle.kts app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt
git commit -m "feat(epic-19): Issue 1 Task 4 新增 elinkbook/fullscreen 原生頻道（WindowInsetsControllerCompat）"
```

---

### Task 5：`ReaderScreen` Dart 端接通全螢幕模式

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: `ResolvedPreferences.fullscreen`（Task 3）、platform channel `elinkbook/fullscreen`（Task 4）。
- Produces: `ReaderScreen._applySystemUiMode()`（供本檔案內部呼叫，無對外公開介面異動）。

- [x] **Step 1: 撰寫失敗測試（`_applySystemUiMode` 基本行為）**

在 `app/test/screens/reader_screen_test.dart` 找到既有 `elinkbook/volume_key` 頻道測試（約第 2748-2760 行的 mock handler 寫法）附近，新增以下獨立的 `testWidgets`：

```dart
  testWidgets('開啟全螢幕模式偏好後，elinkbook/fullscreen 頻道收到 setEnabled(true)',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const fullscreenChannel = MethodChannel('elinkbook/fullscreen');
    final calls = <MethodCall>[];
    binaryMessenger.setMockMethodCallHandler(fullscreenChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => binaryMessenger.setMockMethodCallHandler(fullscreenChannel, null),
    );

    final prefsManager = FakeReaderPrefsManager(
      bookPrefsByBookId: {'b1': const BookReaderPrefs(fullscreen: true)},
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

    expect(calls, hasLength(1));
    expect(calls.single.method, 'setEnabled');
    expect(calls.single.arguments, isTrue);
  });

  testWidgets('離開 ReaderScreen 時，elinkbook/fullscreen 頻道收到 setEnabled(false) 無條件還原',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const fullscreenChannel = MethodChannel('elinkbook/fullscreen');
    final calls = <MethodCall>[];
    binaryMessenger.setMockMethodCallHandler(fullscreenChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => binaryMessenger.setMockMethodCallHandler(fullscreenChannel, null),
    );

    final prefsManager = FakeReaderPrefsManager(
      bookPrefsByBookId: {'b1': const BookReaderPrefs(fullscreen: true)},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              key: const Key('open_reader'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReaderScreen(
                    filePath: 'test/fixtures/sample.pdf',
                    bookId: 'b1',
                    prefsManager: prefsManager,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_reader')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    // 模擬原生端 onPageRendered，讓畫面脫離 loading（純 flutter test 環境下
    // AndroidView 不會真正觸發原生回呼，比照本檔案既有測試慣例，見既有
    // 「離開閱讀器時通知原生端」測試）——CircularProgressIndicator 為不定長
    // 動畫，若一直停留在 loading，後續 pumpAndSettle() 永遠不會收斂而逾時。
    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();
    calls.clear();

    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    navigatorState.maybePop();
    await tester.pumpAndSettle();

    expect(calls, contains(predicate<MethodCall>((c) =>
        c.method == 'setEnabled' && c.arguments == false)));
  });

  testWidgets(
      'App 從背景恢復時，即使 fullscreen 值未變，_applySystemUiMode 仍重新呼叫 elinkbook/fullscreen',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const fullscreenChannel = MethodChannel('elinkbook/fullscreen');
    final calls = <MethodCall>[];
    binaryMessenger.setMockMethodCallHandler(fullscreenChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => binaryMessenger.setMockMethodCallHandler(fullscreenChannel, null),
    );

    final prefsManager = FakeReaderPrefsManager(
      bookPrefsByBookId: {'b1': const BookReaderPrefs(fullscreen: true)},
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
    expect(calls, hasLength(1)); // 初次套用

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(calls, hasLength(2), reason: 'resumed 應強制重新呼叫，不受等值節流影響');
    expect(calls.last.method, 'setEnabled');
    expect(calls.last.arguments, isTrue);
  });
```

`FakeReaderPrefsManager`（`app/test/support/fake_reader_prefs_manager.dart`）已是 `reader_screen_test.dart` 既有匯入的測試替身（既有 `prefsManager = FakeReaderPrefsManager();` 用法見同檔案第 57 行），`bookPrefsByBookId` 是其既有建構參數（`Map<String, BookReaderPrefs>?`），`resolve()` 內部委派給真正的 `ReaderPrefsManagerImpl.resolve()`（見該檔案第 35-39、80-85 行），故驗證的合併邏輯與正式實作完全一致，不需要新增測試替身。

- [x] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/reader_screen_test.dart -n "elinkbook/fullscreen"`
Expected: FAIL——`calls` 為空（`_applySystemUiMode()` 尚未實作，`ReaderScreen` 從未呼叫 `elinkbook/fullscreen` 頻道）。

- [x] **Step 3: 實作 `ReaderScreen` 端**

編輯 `app/lib/screens/reader_screen.dart`：

在既有 `_volumeKeyChannel` 宣告（第 51 行）之後新增：

```dart
const _volumeKeyChannel = MethodChannel('elinkbook/volume_key');

/// 全螢幕模式頻道（epic-19-shelf-reading-enhance Issue 1，見 ADR 0015）：
/// 呼叫原生 WindowInsetsControllerCompat 隱藏/顯示系統狀態列與導覽列，
/// 不經過 Flutter SystemChrome（本專案目前 targetSdk 下已知失效）。
const _fullscreenChannel = MethodChannel('elinkbook/fullscreen');
```

在既有 `_lastAppliedOrientation`（第 239 行）之後新增：

```dart
  ScreenOrientationSetting? _lastAppliedOrientation;
  // 記錄上一次實際套用給系統的全螢幕模式狀態，避免偏好設定頻繁變動時
  // 重複呼叫 elinkbook/fullscreen 頻道；App 從背景恢復時會被強制清空
  // （見 didChangeAppLifecycleState），確保系統列真的被 OS 重新顯示時
  // 能重新套用。
  bool? _lastAppliedFullscreen;
```

在既有 `_applyScreenOrientation()` 方法（第 389-397 行）之後新增：

```dart
  /// 依 [_resolved] 的 fullscreen 呼叫 elinkbook/fullscreen 頻道，比照
  /// _applyScreenOrientation() 的節流寫法，避免偏好設定頻繁變動時重複
  /// 呼叫 platform channel。
  void _applySystemUiMode() {
    final resolved = _resolved;
    if (resolved == null) return;
    if (resolved.fullscreen == _lastAppliedFullscreen) return;
    _lastAppliedFullscreen = resolved.fullscreen;
    _fullscreenChannel.invokeMethod('setEnabled', resolved.fullscreen);
  }
```

在 `initState()` 內既有的 `_applyScreenOrientation();`（第 267 行）之後新增：

```dart
      _applyScreenOrientation();
      _applySystemUiMode();
    });
  }
```

在 `_handlePrefsChanged()` 內既有的 `_applyScreenOrientation();`（第 441 行）之後新增：

```dart
    widget.prefsManager.saveBookPrefs(widget.bookId, prefs);
    _applyScreenOrientation();
    _applySystemUiMode();
  }
```

`dispose()`（第 301-314 行）內既有 `SystemChrome.setPreferredOrientations(const []);`（第 313 行）之後新增：

```dart
    SystemChrome.setPreferredOrientations(const []);
    // 全螢幕模式離開閱讀畫面時無條件還原，不判斷 _lastAppliedFullscreen
    // （比照上一行既有的螢幕方向無條件還原寫法），避免外溢到書架等其他畫面。
    _fullscreenChannel.invokeMethod('setEnabled', false);
    super.dispose();
  }
```

`didChangeAppLifecycleState()`（第 322-326 行）改為：

```dart
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _writeCurrentPosition();
    } else if (state == AppLifecycleState.resumed) {
      // App 從背景恢復時，Android 系統列可能已被 OS 自動重新顯示，
      // _lastAppliedFullscreen 等值節流防護會誤判不需重套用，故強制清空
      // 快取後無條件重新呼叫一次（epic-19 Issue 1 review Critical 2）。
      _lastAppliedFullscreen = null;
      _applySystemUiMode();
    }
  }
```

- [x] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: PASS（新增 3 個測試通過，既有測試無回歸）。

- [x] **Step 5: 執行全專案測試確認無回歸**

Run: `cd app && flutter test`
Expected: PASS。`flutter analyze` 亦須乾淨。

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-19): Issue 1 Task 5 ReaderScreen 接通全螢幕模式頻道與生命週期還原"
```

---

### Task 6：三個設定面板新增「全螢幕模式」開關

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart`
- Modify: `app/lib/screens/pdf_settings_sheet.dart`
- Modify: `app/lib/screens/fxl_settings_sheet.dart`
- Test: `app/test/screens/reader_settings_sheet_test.dart`
- Test: `app/test/screens/pdf_settings_sheet_test.dart`
- Test: `app/test/screens/fxl_settings_sheet_test.dart`

**Interfaces:**
- Consumes: `BookReaderPrefs.fullscreen`（Task 1）。
- Produces: 無新對外介面（三個既有 Widget 的 `onChanged` callback 行為擴充）。

- [x] **Step 1: 撰寫失敗測試（`ReaderSettingsSheet`）**

在 `app/test/screens/reader_settings_sheet_test.dart` 找到既有「已持久化 showHeader=false 時，頁首開關初始值反映為關閉」與「關閉頁首開關後，onChanged 帶入 showHeader=false...」兩個測試（約第 459-486 行）附近，新增：

```dart
  testWidgets('已持久化 fullscreen=true 時，全螢幕模式開關初始值反映為開啟', (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(fullscreen: true),
      (_) {},
    );

    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('reader_settings_fullscreen')))
          .value,
      isTrue,
    );
  });

  testWidgets('開啟全螢幕模式開關後，onChanged 帶入 fullscreen=true 且不影響 showHeader',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => result = prefs);

    await tester.tap(find.byKey(const Key('reader_settings_fullscreen')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.fullscreen, isTrue);
    expect(result!.showHeader, isTrue);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/reader_settings_sheet_test.dart -n "全螢幕模式"`
Expected: FAIL——`find.byKey(const Key('reader_settings_fullscreen'))` 找不到（`ReaderSettingsSheet` 尚未有此開關）。

- [x] **Step 3: 實作 `ReaderSettingsSheet`**

編輯 `app/lib/screens/reader_settings_sheet.dart`：

在 `late bool _showFooter;` 之後新增：

```dart
  late bool _showFooter;
  late bool _fullscreen;
```

`initState()` 內 `_showFooter = widget.prefs.showFooter ?? true;` 之後新增：

```dart
    _showFooter = widget.prefs.showFooter ?? true;
    _fullscreen = widget.prefs.fullscreen ?? false;
```

`didUpdateWidget()` 內同樣位置新增：

```dart
        _showFooter = widget.prefs.showFooter ?? true;
        _fullscreen = widget.prefs.fullscreen ?? false;
```

`_notifyChanged()` 內 `showFooter: _showFooter,` 之後新增：

```dart
      showFooter: _showFooter,
      fullscreen: _fullscreen,
```

`build()` 內既有的 `SwitchListTile(key: const Key('reader_settings_show_footer'), ...)` 之後（`欄數` 區塊 `_buildColumnModeRow()` 之前）新增：

```dart
                SwitchListTile(
                  key: const Key('reader_settings_show_footer'),
                  title: const Text('顯示頁尾'),
                  value: _showFooter,
                  onChanged: (v) => setState(() {
                    _showFooter = v;
                    _notifyChanged();
                  }),
                ),
                SwitchListTile(
                  key: const Key('reader_settings_fullscreen'),
                  title: const Text('全螢幕模式'),
                  value: _fullscreen,
                  onChanged: (v) => setState(() {
                    _fullscreen = v;
                    _notifyChanged();
                  }),
                ),
                const SizedBox(height: 12),
                _buildColumnModeRow(),
```

- [x] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/screens/reader_settings_sheet_test.dart`
Expected: PASS。

- [x] **Step 5: 撰寫失敗測試（`PdfSettingsSheet`）**

在 `app/test/screens/pdf_settings_sheet_test.dart` 既有 `pdf_settings_show_footer` 測試附近新增：

```dart
  testWidgets('已持久化 fullscreen=true 時，全螢幕模式開關初始值反映為開啟', (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(fullscreen: true),
      (_) {},
    );

    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('pdf_settings_fullscreen')))
          .value,
      isTrue,
    );
  });

  testWidgets('開啟全螢幕模式開關後，onChanged 帶入 fullscreen=true', (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (prefs) => notified = prefs);

    await tester.ensureVisible(find.byKey(const Key('pdf_settings_fullscreen')));
    await tester.tap(find.byKey(const Key('pdf_settings_fullscreen')));
    await tester.pump();

    expect(notified?.fullscreen, isTrue);
  });
```

- [x] **Step 6: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/pdf_settings_sheet_test.dart -n "全螢幕模式"`
Expected: FAIL——找不到 `pdf_settings_fullscreen` key。

- [x] **Step 7: 實作 `PdfSettingsSheet`**

編輯 `app/lib/screens/pdf_settings_sheet.dart`：

在 `late bool _showFooter;` 之後新增：

```dart
  late bool _showFooter;
  late bool _fullscreen;
```

`initState()` 內 `_showFooter = widget.prefs.showFooter ?? true;` 之後新增：

```dart
    _showFooter = widget.prefs.showFooter ?? true;
    _fullscreen = widget.prefs.fullscreen ?? false;
```

`_notifyChanged()` 內 `showFooter: _showFooter,` 之後新增：

```dart
      showFooter: _showFooter,
      fullscreen: _fullscreen,
```

`_buildDisplayTab()` 內既有 `SwitchListTile(key: const Key('pdf_settings_show_footer'), ...)` 之後新增：

```dart
            SwitchListTile(
              key: const Key('pdf_settings_show_footer'),
              title: const Text('顯示頁尾'),
              value: _showFooter,
              onChanged: (v) => setState(() {
                _showFooter = v;
                _notifyChanged();
              }),
            ),
            SwitchListTile(
              key: const Key('pdf_settings_fullscreen'),
              title: const Text('全螢幕模式'),
              value: _fullscreen,
              onChanged: (v) => setState(() {
                _fullscreen = v;
                _notifyChanged();
              }),
            ),
            const SizedBox(height: 16),
            const Text('頁面方向'),
```

- [x] **Step 8: 執行測試確認通過**

Run: `cd app && flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: PASS。

- [x] **Step 9: 撰寫失敗測試（`FxlSettingsSheet`）**

在 `app/test/screens/fxl_settings_sheet_test.dart` 新增（`FxlSettingsSheet` 目前沒有任何開關，這是第一個）：

```dart
  testWidgets('已持久化 fullscreen=true 時，全螢幕模式開關初始值反映為開啟', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FxlSettingsSheet(
          prefs: const BookReaderPrefs(fullscreen: true),
          onChanged: (_) {},
        ),
      ),
    );

    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('fxl_settings_fullscreen')))
          .value,
      isTrue,
    );
  });

  testWidgets('開啟全螢幕模式開關後，onChanged 帶入 fullscreen=true 且不清空 dualPageMode',
      (tester) async {
    BookReaderPrefs? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: FxlSettingsSheet(
          prefs: const BookReaderPrefs(dualPageMode: DualPageMode.always),
          onChanged: (prefs) => changed = prefs,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('fxl_settings_fullscreen')));
    await tester.pump();

    expect(changed?.fullscreen, isTrue);
    expect(changed?.dualPageMode, DualPageMode.always);
  });
```

- [x] **Step 10: 執行測試確認失敗**

Run: `cd app && flutter test test/screens/fxl_settings_sheet_test.dart -n "全螢幕模式"`
Expected: FAIL——找不到 `fxl_settings_fullscreen` key。

- [x] **Step 11: 實作 `FxlSettingsSheet`**

編輯 `app/lib/screens/fxl_settings_sheet.dart`：

在 `late DualPageMode _dualPageMode;` 之後新增：

```dart
  late DualPageMode _dualPageMode;
  late bool _fullscreen;
```

`initState()` 內 `_dualPageMode = widget.prefs.dualPageMode ?? DualPageMode.auto;` 之後新增：

```dart
    _dualPageMode = widget.prefs.dualPageMode ?? DualPageMode.auto;
    _fullscreen = widget.prefs.fullscreen ?? false;
```

`_notifyChanged()` 改為：

```dart
  void _notifyChanged() {
    widget.onChanged(widget.prefs.copyWith(
      dualPageMode: _dualPageMode,
      fullscreen: _fullscreen,
    ));
  }
```

`build()` 內既有的雙頁模式 `Wrap` 區塊之後（`],` 之後、外層 `Column` 的 `children` 列表結尾之前）新增：

```dart
            const SizedBox(height: 16),
            SwitchListTile(
              key: const Key('fxl_settings_fullscreen'),
              title: const Text('全螢幕模式'),
              value: _fullscreen,
              onChanged: (v) => setState(() {
                _fullscreen = v;
                _notifyChanged();
              }),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [x] **Step 12: 執行測試確認通過**

Run: `cd app && flutter test test/screens/fxl_settings_sheet_test.dart`
Expected: PASS。

- [x] **Step 13: 執行全專案測試確認無回歸**

Run: `cd app && flutter test`
Expected: PASS。若既有測試因新增的 `SwitchListTile` 把畫面內容推出 viewport（比照 `epic-18-reader-device-qa` Issue 14 曾發生的既有先例）而失敗，將對應測試檔案 `_pumpSheet` 的 `Size(800, 1600)` 高度調高（例如改為 `Size(800, 1700)`），重新執行確認通過。

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [x] **Step 14: Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/lib/screens/pdf_settings_sheet.dart app/lib/screens/fxl_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart app/test/screens/pdf_settings_sheet_test.dart app/test/screens/fxl_settings_sheet_test.dart
git commit -m "feat(epic-19): Issue 1 Task 6 三個設定面板新增全螢幕模式開關"
```

---

### Task 7：真機驗收

**Files:** 無程式碼異動，僅驗收記錄。

- [x] **Step 1: 建置並安裝 debug APK**

Run: `cd app && flutter clean && flutter build apk --debug`

安裝到既有測試裝置（`3CEF42ECD491687` 或目前可用裝置）。

- [x] **Step 2: 三種格式逐一驗收全螢幕模式開關**

分別開啟一本 EPUB 流式書、一本 FXL（固定版面）書、一本 PDF，各自：
1. 開啟版面設定面板，開啟「全螢幕模式」開關，確認系統狀態列與導覽列消失、App 自己的頁首/頁尾/浮動按鈕不受影響（仍照 `showHeader`/`showFooter`/沉浸模式既有邏輯顯示）。
2. 從螢幕邊緣滑入，確認系統列可暫時浮現（`BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE`），放開後自動再收起。
3. 關閉開關，確認系統列恢復正常顯示。

- [x] **Step 3: 驗收生命週期還原**

開啟全螢幕模式後，按 Home 鍵切到背景，再切回 App，確認系統列仍然隱藏（未被 OS 重新顯示後卡住——這是 code review Critical 2 發現的 bug，須重點確認）。

- [x] **Step 4: 驗收離開閱讀畫面還原**

開啟全螢幕模式後，返回書架畫面，確認系統列恢復正常顯示，不外溢到書架或其他畫面。

- [x] **Step 5: 回歸確認既有功能**

確認既有的沉浸模式（九宮格中央熱區）、`showHeader`/`showFooter` 開關、螢幕方向鎖定、音量鍵翻頁等既有功能皆不受本次變動影響。

- [x] **Step 6: 更新 `issues.md`**

將 `docs/epics/epic-19-shelf-reading-enhance/issues.md` Issue 1 的 `Status:` 改為 `✅ 已完成`，並記錄上述真機驗收結果。
