# Issue 1 實作計劃：資料層基礎建設——`BookReaderPrefs` 與全域偏好設定儲存

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 建立 Epic 3 全部後續 issue 共用的資料模型與持久化機制——單書版面偏好設定（`BookReaderPrefs`，SQLite）、全域翻頁模式／螢幕方向預設值（`GlobalReaderDefaults`，`shared_preferences`）、全域主題與 E-Ink 高對比開關（`AppThemePreferences`，`shared_preferences`）。純 Dart，不涉及原生程式碼，不需要真實裝置即可完整驗收。

**架構：** 單書偏好設定使用獨立 SQLite 表 `book_reader_prefs`，與既有 `books` 表以 `book_id` 為外鍵 1:1 關聯（`ON DELETE CASCADE`），沿用 `SqliteLibraryRepository` 既有的單一資料庫檔案（`library.db`），透過 schema 版本升級（version 1→2）新增此表；全域設定沿用 `LibraryPreferences` 已驗證的 `shared_preferences` 慣例（單一鍵值、`byName` 失敗安全回退預設值）。

**技術棧：** Dart、`sqflite`（既有依賴）、`shared_preferences`（既有依賴）、`sqflite_common_ffi`（既有測試依賴）。

## 全域限制條件

- `BookReaderPrefs` 為 SQLite 支援的資料類別，`toMap()`/`fromMap()` 沿用既有 `Book.toMap()`/`Book.fromMap()` 慣例（直接 `byName` 解析，不做防禦性 fallback——SQLite 內部資料視為可信任，比照 `Book.fromMap` 既有寫法）。
- `GlobalReaderDefaults`／`AppThemePreferences` 為 `shared_preferences` 支援的類別，**必須**沿用 `LibraryPreferences` 的防禦性 `byName` fallback 慣例（`try/catch` 對應無效字串安全回退預設值）。
- `book_reader_prefs` 表需要真正生效的外鍵約束（`ON DELETE CASCADE`），SQLite 預設不強制外鍵，需在 `openDatabase` 的 `onConfigure` 中執行 `PRAGMA foreign_keys = ON`。
- 既有 `SqliteLibraryRepository`／`Book`／`LibraryPreferences` 的既有行為與測試**不得回歸**；schema 升級需同時支援全新安裝（`onCreate`）與既有 v1 資料庫升級（`onUpgrade`）。
- `WritingMode`（`app/lib/reader/writing_mode.dart`）與 `PageTurnMode`（`app/lib/reader/page_turn_mode.dart`）沿用既有型別，不重新定義。
- 所有新增程式碼註解與文件維持正體中文。
- `flutter analyze` 全程必須維持 `No issues found!`。

---

### Task 1：`BookReaderPrefs` 模型與支援列舉型別

**Files:**
- Create: `app/lib/reader/app_font.dart`
- Create: `app/lib/reader/epub_text_align.dart`
- Create: `app/lib/reader/screen_orientation_setting.dart`
- Create: `app/lib/reader/book_reader_prefs.dart`
- Test: `app/test/reader/book_reader_prefs_test.dart`

**Interfaces:**
- Consumes: 既有 `WritingMode`（`app/lib/reader/writing_mode.dart`）、`PageTurnMode`（`app/lib/reader/page_turn_mode.dart`）
- Produces: `enum AppFont`、`enum EpubTextAlign`、`enum ScreenOrientationSetting`、`class BookReaderPrefs`（含 `toMap()`/`fromMap()`/`==`/`hashCode`），供 Task 3（`BookReaderPrefsRepository`）與後續 issue（UI 層）使用

- [ ] **Step 1：撰寫失敗測試**

建立 `app/test/reader/book_reader_prefs_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/writing_mode.dart';

void main() {
  test('BookReaderPrefs.empty 所有欄位皆為 null', () {
    const prefs = BookReaderPrefs.empty;
    expect(prefs.fontFamily, isNull);
    expect(prefs.fontSize, isNull);
    expect(prefs.fontWeight, isNull);
    expect(prefs.lineHeight, isNull);
    expect(prefs.paragraphSpacing, isNull);
    expect(prefs.pageMargins, isNull);
    expect(prefs.textAlign, isNull);
    expect(prefs.publisherStyles, isNull);
    expect(prefs.writingModeOverride, isNull);
    expect(prefs.pageTurnModeOverride, isNull);
    expect(prefs.screenOrientationOverride, isNull);
  });

  test('兩個欄位值完全相同的 BookReaderPrefs 視為相等', () {
    const a = BookReaderPrefs(
      fontFamily: AppFont.sourceHanSans,
      fontSize: 18,
      writingModeOverride: WritingMode.vertical,
    );
    const b = BookReaderPrefs(
      fontFamily: AppFont.sourceHanSans,
      fontSize: 18,
      writingModeOverride: WritingMode.vertical,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('任一欄位值不同時視為不相等', () {
    const a = BookReaderPrefs(fontSize: 18);
    const b = BookReaderPrefs(fontSize: 20);
    expect(a, isNot(b));
  });

  test('toMap／fromMap round-trip 保留所有欄位（含 book_id）', () {
    const prefs = BookReaderPrefs(
      fontFamily: AppFont.taiwanPearl,
      fontSize: 18.5,
      fontWeight: 1.75,
      lineHeight: 1.6,
      paragraphSpacing: 12,
      pageMargins: 20,
      textAlign: EpubTextAlign.justify,
      publisherStyles: false,
      writingModeOverride: WritingMode.horizontal,
      pageTurnModeOverride: PageTurnMode.scroll,
      screenOrientationOverride: ScreenOrientationSetting.lock90,
    );

    final map = prefs.toMap('book-1');
    expect(map['book_id'], 'book-1');
    expect(map['font_family'], 'taiwanPearl');
    expect(map['publisher_styles'], 0);
    expect(map['writing_mode_override'], 'horizontal');

    final restored = BookReaderPrefs.fromMap(map);
    expect(restored, prefs);
  });

  test('toMap／fromMap round-trip 正確處理全部欄位皆為 null', () {
    const prefs = BookReaderPrefs.empty;
    final map = prefs.toMap('book-2');
    final restored = BookReaderPrefs.fromMap(map);
    expect(restored, prefs);
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/reader/book_reader_prefs_test.dart
```
Expected：FAIL，找不到 `package:elinkbook/reader/app_font.dart` 等檔案（尚未建立）。

- [ ] **Step 3：建立列舉型別**

建立 `app/lib/reader/app_font.dart`：

```dart
/// App 內建的 5 款字型（FR-09）。皆為本地 asset 字型（`app/assets/fonts/`），
/// 非系統字型；自訂字型上傳/管理屬 `epic-14-system-settings`（FR-35），
/// 本 epic 僅從此固定清單中選擇。
enum AppFont {
  sourceHanSans, // 思源黑體 SourceHanSansTC-VF.ttf
  sourceHanSerif, // 思源宋體 SourceHanSerifTC-VF.ttf
  guanKiapTsingKhai, // 原俠正楷 GuanKiapTsingKhai.ttf
  taiwanPearl, // 台灣圓體 TaiwanPearl-Regular.ttf
  genRyuMinTW, // 源流明體 GenRyuMinTW-Regular.ttf
}
```

建立 `app/lib/reader/epub_text_align.dart`：

```dart
/// 對應 Readium `org.readium.r2.navigator.preferences.TextAlign`（反編譯
/// `readium-navigator:3.3.0` 確認的 6 個值，見 spec.md「已驗證的技術基礎」）。
enum EpubTextAlign { center, justify, start, end, left, right }
```

建立 `app/lib/reader/screen_orientation_setting.dart`：

```dart
/// 螢幕方向設定（FR-10／FR-37）。[auto] 依裝置方向自動旋轉並重新分頁；
/// 其餘為強制鎖定角度，鎖定時裝置旋轉不觸發重新排版。
enum ScreenOrientationSetting { auto, lock0, lock90, lock180, lock270 }
```

- [ ] **Step 4：建立 `BookReaderPrefs`**

建立 `app/lib/reader/book_reader_prefs.dart`：

```dart
import 'app_font.dart';
import 'epub_text_align.dart';
import 'page_turn_mode.dart';
import 'screen_orientation_setting.dart';
import 'writing_mode.dart';

/// 單一書籍的版面偏好設定（FR-09／FR-10），對應 `book_reader_prefs` 表的
/// 一列（見 spec.md「資料模型」）。所有欄位皆為 nullable：`null` 代表未
/// 覆寫，由呼叫端依各欄位語意決定回退值（書本內建樣式、Readium 預設，
/// 或——僅限 [pageTurnModeOverride]／[screenOrientationOverride]——全域
/// 預設值，見 `GlobalReaderDefaults`）。
class BookReaderPrefs {
  final AppFont? fontFamily;
  final double? fontSize;
  final double? fontWeight; // Readium 倍率語意（1.0 = normal），非 CSS 300-900 原始值
  final double? lineHeight;
  final double? paragraphSpacing;
  final double? pageMargins; // 單一數值，四邊同步變動，見 ADR 0005
  final EpubTextAlign? textAlign;
  final bool? publisherStyles; // 對應 Readium publisherStyles；true=使用書本內建 CSS
  final WritingMode? writingModeOverride; // null=採用書籍排版（自動偵測）
  final PageTurnMode? pageTurnModeOverride; // null=使用全域預設
  final ScreenOrientationSetting? screenOrientationOverride; // null=使用全域預設

  const BookReaderPrefs({
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.paragraphSpacing,
    this.pageMargins,
    this.textAlign,
    this.publisherStyles,
    this.writingModeOverride,
    this.pageTurnModeOverride,
    this.screenOrientationOverride,
  });

  /// 無任何覆寫，等同資料庫無對應列時的狀態。
  static const empty = BookReaderPrefs();

  Map<String, Object?> toMap(String bookId) {
    return {
      'book_id': bookId,
      'font_family': fontFamily?.name,
      'font_size': fontSize,
      'font_weight': fontWeight,
      'line_height': lineHeight,
      'paragraph_spacing': paragraphSpacing,
      'page_margins': pageMargins,
      'text_align': textAlign?.name,
      'publisher_styles':
          publisherStyles == null ? null : (publisherStyles! ? 1 : 0),
      'writing_mode_override': writingModeOverride?.name,
      'page_turn_mode_override': pageTurnModeOverride?.name,
      'screen_orientation_override': screenOrientationOverride?.name,
    };
  }

  factory BookReaderPrefs.fromMap(Map<String, Object?> map) {
    return BookReaderPrefs(
      fontFamily: map['font_family'] == null
          ? null
          : AppFont.values.byName(map['font_family'] as String),
      // SQLite 對無小數部分的 REAL 欄位可能讀回 int（見
      // Book.fromMap 的 progress 欄位既有處理方式），故用 num? 轉換，
      // 不可直接 `as double?`（會拋出 type cast 例外）。
      fontSize: (map['font_size'] as num?)?.toDouble(),
      fontWeight: (map['font_weight'] as num?)?.toDouble(),
      lineHeight: (map['line_height'] as num?)?.toDouble(),
      paragraphSpacing: (map['paragraph_spacing'] as num?)?.toDouble(),
      pageMargins: (map['page_margins'] as num?)?.toDouble(),
      textAlign: map['text_align'] == null
          ? null
          : EpubTextAlign.values.byName(map['text_align'] as String),
      publisherStyles: map['publisher_styles'] == null
          ? null
          : (map['publisher_styles'] as int) == 1,
      writingModeOverride: map['writing_mode_override'] == null
          ? null
          : WritingMode.values.byName(map['writing_mode_override'] as String),
      pageTurnModeOverride: map['page_turn_mode_override'] == null
          ? null
          : PageTurnMode.values
              .byName(map['page_turn_mode_override'] as String),
      screenOrientationOverride: map['screen_orientation_override'] == null
          ? null
          : ScreenOrientationSetting.values
              .byName(map['screen_orientation_override'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BookReaderPrefs &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.lineHeight == lineHeight &&
      other.paragraphSpacing == paragraphSpacing &&
      other.pageMargins == pageMargins &&
      other.textAlign == textAlign &&
      other.publisherStyles == publisherStyles &&
      other.writingModeOverride == writingModeOverride &&
      other.pageTurnModeOverride == pageTurnModeOverride &&
      other.screenOrientationOverride == screenOrientationOverride;

  @override
  int get hashCode => Object.hash(
        fontFamily,
        fontSize,
        fontWeight,
        lineHeight,
        paragraphSpacing,
        pageMargins,
        textAlign,
        publisherStyles,
        writingModeOverride,
        pageTurnModeOverride,
        screenOrientationOverride,
      );
}
```

- [ ] **Step 5：執行測試確認通過**

Run：
```bash
flutter test test/reader/book_reader_prefs_test.dart
```
Expected：`All tests passed!`（5 項測試）。

- [ ] **Step 6：全量測試與靜態分析確認無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter test
flutter analyze
```
Expected：`flutter test` 全數通過；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 7：Commit**

```bash
git add app/lib/reader/app_font.dart app/lib/reader/epub_text_align.dart app/lib/reader/screen_orientation_setting.dart app/lib/reader/book_reader_prefs.dart app/test/reader/book_reader_prefs_test.dart
git commit -m "Add BookReaderPrefs model and supporting enums"
```

---

### Task 2：`book_reader_prefs` SQLite schema 升級

**Files:**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes: 無（純 schema 異動）
- Produces: `book_reader_prefs` 表（見下方 `CREATE TABLE`）；`SqliteLibraryRepository` 新增 `Database get database` getter，供 Task 3 的 `BookReaderPrefsRepository` 取得同一個資料庫連線

- [ ] **Step 1：撰寫失敗測試**

開啟 `app/test/library/sqlite_library_repository_test.dart`，在檔案最後一個既有 `test`/`group` 之後、`main()` 收尾的 `}` 之前，新增：

```dart
  group('book_reader_prefs schema', () {
    test('新安裝資料庫已包含 book_reader_prefs 表，且外鍵約束會在刪除書籍時連動清除',
        () async {
      await repository.insertBook(_book('b1'));
      await repository.database.insert('book_reader_prefs', {
        'book_id': 'b1',
        'font_size': 18.0,
      });

      await repository.deleteBook('b1');

      final rows = await repository.database.query(
        'book_reader_prefs',
        where: 'book_id = ?',
        whereArgs: ['b1'],
      );
      expect(rows, isEmpty);
    });
  });
```

- [ ] **Step 2：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/library/sqlite_library_repository_test.dart
```
Expected：FAIL——`database` getter 不存在（編譯錯誤），或 `book_reader_prefs` 表不存在（`no such table` 執行期錯誤）。

- [ ] **Step 3：擴充 `SqliteLibraryRepository`**

開啟 `app/lib/library/sqlite_library_repository.dart`，把 `open` 方法：

```dart
  static Future<SqliteLibraryRepository> open(String path) async {
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE groups (
            name TEXT PRIMARY KEY
          )
        ''');
        await db.insert('groups', {'name': BookGroup.uncategorized});
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
            groupName TEXT NOT NULL DEFAULT '${BookGroup.uncategorized}',
            createTime INTEGER NOT NULL,
            lastReadTime INTEGER NOT NULL
          )
        ''');
      },
    );
    return SqliteLibraryRepository._(db);
  }

  Future<void> close() => _db.close();
```

改為：

```dart
  static Future<SqliteLibraryRepository> open(String path) async {
    final db = await openDatabase(
      path,
      version: 2,
      onConfigure: (db) async {
        // book_reader_prefs 的 ON DELETE CASCADE 需要外鍵約束真正生效，
        // SQLite 預設不強制外鍵，須逐連線手動開啟（見 epic-3 plan-issue-1）。
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE groups (
            name TEXT PRIMARY KEY
          )
        ''');
        await db.insert('groups', {'name': BookGroup.uncategorized});
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
            groupName TEXT NOT NULL DEFAULT '${BookGroup.uncategorized}',
            createTime INTEGER NOT NULL,
            lastReadTime INTEGER NOT NULL
          )
        ''');
        await _createBookReaderPrefsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createBookReaderPrefsTable(db);
        }
      },
    );
    return SqliteLibraryRepository._(db);
  }

  static Future<void> _createBookReaderPrefsTable(Database db) async {
    // 單書版面偏好設定（epic-3-fonts-layout FR-09/FR-10），與 books 表
    // 1:1 關聯；所有欄位皆為 nullable，null 代表未覆寫，見
    // docs/epics/epic-3-fonts-layout/spec.md「資料模型」。
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
  }

  /// 供 [BookReaderPrefsRepository] 等後續 repository 共用同一個資料庫連線
  /// （`book_reader_prefs` 的外鍵約束要求與 `books` 表在同一個資料庫檔案內）。
  Database get database => _db;

  Future<void> close() => _db.close();
```

- [ ] **Step 4：執行測試確認通過**

Run：
```bash
flutter test test/library/sqlite_library_repository_test.dart
```
Expected：`All tests passed!`（既有測試 + 新增的 `book_reader_prefs schema` group）。

- [ ] **Step 5：全量測試與靜態分析確認無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter test
flutter analyze
```
Expected：`flutter test` 全數通過，無回歸；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 6：Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "Add book_reader_prefs table via schema migration to v2"
```

---

### Task 3：`BookReaderPrefsRepository`

**Files:**
- Create: `app/lib/reader/book_reader_prefs_repository.dart`
- Test: `app/test/reader/book_reader_prefs_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `BookReaderPrefs`；Task 2 的 `book_reader_prefs` 表與 `SqliteLibraryRepository.database`
- Produces: `class BookReaderPrefsRepository`（`load(bookId)`/`save(bookId, prefs)`），供後續 issue（`ReaderScreen`/`ReaderSettingsSheet`）使用

- [ ] **Step 1：撰寫失敗測試**

建立 `app/test/reader/book_reader_prefs_repository_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/writing_mode.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqliteLibraryRepository libraryRepository;
  late BookReaderPrefsRepository repository;

  setUp(() async {
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    repository = BookReaderPrefsRepository(libraryRepository.database);
    await libraryRepository.insertBook(Book(
      id: 'b1',
      title: '書名',
      format: BookFileFormat.epub,
      filePath: 'content://example/b1',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    ));
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  test('尚未儲存過偏好設定時，load 回傳 BookReaderPrefs.empty', () async {
    final prefs = await repository.load('b1');
    expect(prefs, BookReaderPrefs.empty);
  });

  test('save 寫入後，load 讀回相同的值', () async {
    const prefs = BookReaderPrefs(
      fontFamily: AppFont.sourceHanSerif,
      fontSize: 20,
      writingModeOverride: WritingMode.vertical,
    );

    await repository.save('b1', prefs);

    expect(await repository.load('b1'), prefs);
  });

  test('save 覆寫既有偏好設定（同一本書再次呼叫 save）', () async {
    await repository.save('b1', const BookReaderPrefs(fontSize: 18));
    await repository.save('b1', const BookReaderPrefs(fontSize: 22));

    final prefs = await repository.load('b1');
    expect(prefs.fontSize, 22);
  });

  test('刪除書籍後，對應的偏好設定列因 ON DELETE CASCADE 一併消失', () async {
    await repository.save('b1', const BookReaderPrefs(fontSize: 18));

    await libraryRepository.deleteBook('b1');

    expect(await repository.load('b1'), BookReaderPrefs.empty);
  });

  test('當 save 寫入的數值在 SQLite 存成整數時，load 仍能安全轉換為 double 而不崩潰',
      () async {
    const prefs = BookReaderPrefs(
      fontSize: 18.0, // 無小數部分，SQLite 可能存成 INTEGER
      lineHeight: 1.0, // 同上
    );

    await repository.save('b1', prefs);

    // 若 BookReaderPrefs.fromMap 直接用 `as double?` 而非
    // `(... as num?)?.toDouble()`，此處會拋出 type cast 例外崩潰。
    final loaded = await repository.load('b1');
    expect(loaded.fontSize, 18.0);
    expect(loaded.lineHeight, 1.0);
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/reader/book_reader_prefs_repository_test.dart
```
Expected：FAIL，找不到 `package:elinkbook/reader/book_reader_prefs_repository.dart`（尚未建立）。

- [ ] **Step 3：建立 `BookReaderPrefsRepository`**

建立 `app/lib/reader/book_reader_prefs_repository.dart`：

```dart
import 'package:sqflite/sqflite.dart';

import 'book_reader_prefs.dart';

/// `book_reader_prefs` 表的存取層（見 `SqliteLibraryRepository` 的 schema
/// 定義）。與 [SqliteLibraryRepository] 共用同一個 [Database] 連線，因為
/// `book_reader_prefs.book_id` 的外鍵約束要求與 `books` 表在同一個資料庫
/// 檔案內。
class BookReaderPrefsRepository {
  final Database _db;

  const BookReaderPrefsRepository(this._db);

  /// 無對應書籍列時回傳 [BookReaderPrefs.empty]（等同所有欄位皆未覆寫）。
  Future<BookReaderPrefs> load(String bookId) async {
    final rows = await _db.query(
      'book_reader_prefs',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    if (rows.isEmpty) return BookReaderPrefs.empty;
    return BookReaderPrefs.fromMap(rows.single);
  }

  /// Upsert：若該書已有偏好設定列，整列覆寫為 [prefs] 的內容。
  ///
  /// [ConflictAlgorithm.replace] 底層是 `INSERT OR REPLACE`，主鍵衝突時
  /// SQLite 會先 `DELETE` 舊列、再 `INSERT` 新列（先刪後增）。目前沒有其他
  /// 表以 `book_reader_prefs` 為外鍵，此行為是安全的；但若未來有其他表
  /// 關聯到本表，需重新評估這個「先刪後增」是否會意外觸發連鎖刪除。
  Future<void> save(String bookId, BookReaderPrefs prefs) async {
    await _db.insert(
      'book_reader_prefs',
      prefs.toMap(bookId),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
```

- [ ] **Step 4：執行測試確認通過**

Run：
```bash
flutter test test/reader/book_reader_prefs_repository_test.dart
```
Expected：`All tests passed!`（5 項測試）。

- [ ] **Step 5：全量測試與靜態分析確認無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter test
flutter analyze
```
Expected：`flutter test` 全數通過，無回歸；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 6：Commit**

```bash
git add app/lib/reader/book_reader_prefs_repository.dart app/test/reader/book_reader_prefs_repository_test.dart
git commit -m "Add BookReaderPrefsRepository"
```

---

### Task 4：`GlobalReaderDefaults`

**Files:**
- Create: `app/lib/reader/global_reader_defaults.dart`
- Test: `app/test/reader/global_reader_defaults_test.dart`

**Interfaces:**
- Consumes: 既有 `PageTurnMode`；Task 1 的 `ScreenOrientationSetting`
- Produces: `class GlobalReaderDefaults`（`loadPageTurnMode`/`savePageTurnMode`/`loadScreenOrientation`/`saveScreenOrientation`），供後續 issue（`ReaderScreen` 的雙層解析邏輯）使用；目前無對應設定 UI（`epic-14-system-settings` 未來提供），僅資料層

- [ ] **Step 1：撰寫失敗測試**

建立 `app/test/reader/global_reader_defaults_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/reader/global_reader_defaults.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('尚未儲存過翻頁模式全域預設時，loadPageTurnMode 回傳預設值 paginated',
      () async {
    final defaults = GlobalReaderDefaults();
    expect(await defaults.loadPageTurnMode(), PageTurnMode.paginated);
  });

  test('savePageTurnMode 寫入後，loadPageTurnMode 讀回相同的值', () async {
    final defaults = GlobalReaderDefaults();
    await defaults.savePageTurnMode(PageTurnMode.scroll);
    expect(await defaults.loadPageTurnMode(), PageTurnMode.scroll);
  });

  test('尚未儲存過螢幕方向全域預設時，loadScreenOrientation 回傳預設值 auto',
      () async {
    final defaults = GlobalReaderDefaults();
    expect(
        await defaults.loadScreenOrientation(), ScreenOrientationSetting.auto);
  });

  test('saveScreenOrientation 寫入後，loadScreenOrientation 讀回相同的值',
      () async {
    final defaults = GlobalReaderDefaults();
    await defaults.saveScreenOrientation(ScreenOrientationSetting.lock90);
    expect(await defaults.loadScreenOrientation(),
        ScreenOrientationSetting.lock90);
  });

  test('已儲存的翻頁模式字串無法對應到任何列舉值時，loadPageTurnMode 安全回退為預設值',
      () async {
    SharedPreferences.setMockInitialValues({
      'global_reader_page_turn_mode': 'not_a_real_enum_value',
    });
    final defaults = GlobalReaderDefaults();
    expect(await defaults.loadPageTurnMode(), PageTurnMode.paginated);
  });

  test('已儲存的螢幕方向字串無法對應到任何列舉值時，loadScreenOrientation 安全回退為預設值',
      () async {
    SharedPreferences.setMockInitialValues({
      'global_reader_screen_orientation': 'not_a_real_enum_value',
    });
    final defaults = GlobalReaderDefaults();
    expect(
        await defaults.loadScreenOrientation(), ScreenOrientationSetting.auto);
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/reader/global_reader_defaults_test.dart
```
Expected：FAIL，找不到 `package:elinkbook/reader/global_reader_defaults.dart`（尚未建立）。

- [ ] **Step 3：建立 `GlobalReaderDefaults`**

建立 `app/lib/reader/global_reader_defaults.dart`：

```dart
import 'package:shared_preferences/shared_preferences.dart';

import 'page_turn_mode.dart';
import 'screen_orientation_setting.dart';

/// 翻頁模式／螢幕方向的全域預設值（FR-37／FR-38）。目前無對應設定 UI——
/// `epic-14-system-settings` 尚未開發，本 epic 僅實作「單書覆寫值 `??`
/// 全域預設值」的資料層，初始值沿用現有行為（不改變既有使用者體驗）；
/// `epic-14` 上線後只需在同一組 key 上補設定畫面。直接使用
/// `shared_preferences` 官方支援的測試方式驅動測試，比照
/// `LibraryPreferences`（見 docs/epics/epic-1-library/spec.md）。
class GlobalReaderDefaults {
  static const _pageTurnModeKey = 'global_reader_page_turn_mode';
  static const _screenOrientationKey = 'global_reader_screen_orientation';

  Future<PageTurnMode> loadPageTurnMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pageTurnModeKey);
    if (raw == null) return PageTurnMode.paginated;
    try {
      return PageTurnMode.values.byName(raw);
    } catch (_) {
      // 儲存的字串無法對應到任何列舉值時（例如未來改了列舉名稱、或裝置上
      // 的資料被污染），byName 會拋出 ArgumentError；安全回退為預設值。
      return PageTurnMode.paginated;
    }
  }

  Future<void> savePageTurnMode(PageTurnMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pageTurnModeKey, mode.name);
  }

  Future<ScreenOrientationSetting> loadScreenOrientation() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_screenOrientationKey);
    if (raw == null) return ScreenOrientationSetting.auto;
    try {
      return ScreenOrientationSetting.values.byName(raw);
    } catch (_) {
      return ScreenOrientationSetting.auto;
    }
  }

  Future<void> saveScreenOrientation(ScreenOrientationSetting setting) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_screenOrientationKey, setting.name);
  }
}
```

- [ ] **Step 4：執行測試確認通過**

Run：
```bash
flutter test test/reader/global_reader_defaults_test.dart
```
Expected：`All tests passed!`（6 項測試）。

- [ ] **Step 5：全量測試與靜態分析確認無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter test
flutter analyze
```
Expected：`flutter test` 全數通過，無回歸；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 6：Commit**

```bash
git add app/lib/reader/global_reader_defaults.dart app/test/reader/global_reader_defaults_test.dart
git commit -m "Add GlobalReaderDefaults for page-turn-mode/orientation global defaults"
```

---

### Task 5：`AppTheme` 列舉與 `AppThemePreferences`

**Files:**
- Create: `app/lib/theme/app_theme.dart`
- Create: `app/lib/theme/app_theme_preferences.dart`
- Test: `app/test/theme/app_theme_preferences_test.dart`

**Interfaces:**
- Consumes: 無
- Produces: `enum AppTheme`、`class AppThemePreferences`（`loadTheme`/`saveTheme`/`loadEinkMode`/`saveEinkMode`），供後續 issue（`ElinkBookApp`／`LibraryScreen` 主題切換 UI）使用

- [ ] **Step 1：撰寫失敗測試**

建立 `app/test/theme/app_theme_preferences_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('尚未儲存過主題時，loadTheme 回傳預設值 light', () async {
    final prefs = AppThemePreferences();
    expect(await prefs.loadTheme(), AppTheme.light);
  });

  test('saveTheme 寫入後，loadTheme 讀回相同的值', () async {
    final prefs = AppThemePreferences();
    await prefs.saveTheme(AppTheme.sepia);
    expect(await prefs.loadTheme(), AppTheme.sepia);
  });

  test('尚未儲存過 E-Ink 開關時，loadEinkMode 回傳預設值 false', () async {
    final prefs = AppThemePreferences();
    expect(await prefs.loadEinkMode(), false);
  });

  test('saveEinkMode 寫入後，loadEinkMode 讀回相同的值', () async {
    final prefs = AppThemePreferences();
    await prefs.saveEinkMode(true);
    expect(await prefs.loadEinkMode(), true);
  });

  test('已儲存的主題字串無法對應到任何列舉值時，loadTheme 安全回退為預設值', () async {
    SharedPreferences.setMockInitialValues({
      'app_theme': 'not_a_real_enum_value',
    });
    final prefs = AppThemePreferences();
    expect(await prefs.loadTheme(), AppTheme.light);
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

Run（於 `app/` 目錄下）：
```bash
flutter test test/theme/app_theme_preferences_test.dart
```
Expected：FAIL，找不到 `package:elinkbook/theme/app_theme.dart`（尚未建立）。

- [ ] **Step 3：建立 `AppTheme` 與 `AppThemePreferences`**

建立 `app/lib/theme/app_theme.dart`：

```dart
/// 全域閱讀主題（FR-31），三選一，跨書籍一致。E-Ink 高對比模式為獨立的
/// 全域布林開關（見 `AppThemePreferences.loadEinkMode`），不是第 4 種
/// 主題選項——兩者可同時生效，但 E-Ink 開啟時畫面一律呈現固定的高對比
/// 黑白樣式，[AppTheme] 的選擇僅在 E-Ink 關閉時才影響實際呈現（見
/// docs/epics/epic-3-fonts-layout/design.md「FR-31」與 CONTEXT.md
/// 「E-Ink 高對比模式」詞條）。
enum AppTheme { light, dark, sepia }
```

建立 `app/lib/theme/app_theme_preferences.dart`：

```dart
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

/// 全域主題與 E-Ink 高對比開關的持久化（FR-31）。直接使用
/// `shared_preferences` 官方支援的測試方式驅動測試，比照
/// `LibraryPreferences`（見 docs/epics/epic-1-library/spec.md）。
class AppThemePreferences {
  static const _themeKey = 'app_theme';
  static const _einkModeKey = 'app_eink_mode';

  Future<AppTheme> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_themeKey);
    if (raw == null) return AppTheme.light;
    try {
      return AppTheme.values.byName(raw);
    } catch (_) {
      // 儲存的字串無法對應到任何列舉值時（例如未來改了列舉名稱、或裝置上
      // 的資料被污染），byName 會拋出 ArgumentError；安全回退為預設值。
      return AppTheme.light;
    }
  }

  Future<void> saveTheme(AppTheme theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, theme.name);
  }

  Future<bool> loadEinkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_einkModeKey) ?? false;
  }

  Future<void> saveEinkMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_einkModeKey, enabled);
  }
}
```

- [ ] **Step 4：執行測試確認通過**

Run：
```bash
flutter test test/theme/app_theme_preferences_test.dart
```
Expected：`All tests passed!`（5 項測試）。

- [ ] **Step 5：全量測試與靜態分析確認無回歸**

Run（於 `app/` 目錄下）：
```bash
flutter test
flutter analyze
```
Expected：`flutter test` 全數通過，無回歸；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 6：Commit**

```bash
git add app/lib/theme/app_theme.dart app/lib/theme/app_theme_preferences.dart app/test/theme/app_theme_preferences_test.dart
git commit -m "Add AppTheme enum and AppThemePreferences"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍：** `issues.md` Issue 1 列出的 5 項產出（`AppFont`/`EpubTextAlign`/`ScreenOrientationSetting` 列舉、`BookReaderPrefs`、`book_reader_prefs` 表、`BookReaderPrefsRepository`、`GlobalReaderDefaults`、`AppThemePreferences`）依序對應 Task 1-5；`spec.md`「資料模型」章節定義的欄位與型別、`CREATE TABLE` schema 皆逐字對應到 Task 1/Task 2 的程式碼。
- **與既有慣例的一致性：** `BookReaderPrefs.toMap`/`fromMap` 比照 `Book.toMap`/`fromMap`（SQLite 內部資料不做防禦性 fallback）；`GlobalReaderDefaults`/`AppThemePreferences` 比照 `LibraryPreferences`（`shared_preferences` 資料需要防禦性 `byName` fallback）——兩種不同資料來源、兩種既有慣例，本計劃刻意不統一成同一種寫法，避免與既有程式碼風格產生不必要的落差。
- **外鍵約束的可驗證性：** Task 2 特別新增 `onConfigure` 開啟 `PRAGMA foreign_keys = ON`，並在同一個 Task 的測試中直接驗證 `ON DELETE CASCADE` 真的生效（而非只驗證 schema 建立成功），避免「表建立了但外鍵沒真的作用」這種容易被忽略的落差。
- **佔位符掃描：** 所有步驟皆含完整程式碼、明確指令與預期輸出，無 TBD/佔位文字。
- **型別/命名一致性：** `AppFont`/`EpubTextAlign`/`ScreenOrientationSetting`/`BookReaderPrefs`/`BookReaderPrefsRepository`/`GlobalReaderDefaults`/`AppTheme`/`AppThemePreferences` 的型別與方法名稱，全程與 `spec.md`「資料模型」「介面」章節定義的名稱一致，供 Issue 2-6 的實作者直接引用，不需要重新確認命名。
- **已知、記錄在案但刻意不處理的情形：** `GlobalReaderDefaults`/`AppThemePreferences` 目前皆無對應設定 UI（分別留給 `epic-14-system-settings` 與本 epic 後續 Issue 5），本 issue 僅建立資料層，這是刻意的範圍界線，非遺漏。
- **依 `tmp/epic-3/reviews/plan-issue-1-review.md` 審查意見處理：** 「SQLite 數值讀取強制轉型崩潰」（Critical）已採納並修正——`BookReaderPrefs.fromMap` 改用 `(... as num?)?.toDouble()`，比照本專案 `Book.fromMap` 對 `progress`（同為 `REAL` 欄位）的既有處理方式，並在 Task 3 補上對應的 round-trip 測試案例。「`INSERT OR REPLACE` 先刪後增副作用」（Minor）已採納，於 `BookReaderPrefsRepository.save()` 加註說明。「`AppFont` 缺少字型名稱映射」（Important）不予採納：`issues.md` 已明確將此對應表排在 Issue 2（該處才會實際宣告 `pubspec.yaml` 的 `family:` 名稱），現在加入等於在 Issue 1 猜測尚未驗證的字串，予以排除。「`SharedPreferences` 實例快取」（Minor）不予採納：查證 `shared_preferences 2.5.5`（本專案鎖定版本）原始碼確認 `getInstance()` 本身已有套件層級的 `Completer` 快取，額外的類別內快取沒有實質效能增益，且會讓寫法偏離既有的 `LibraryPreferences` 慣例。
