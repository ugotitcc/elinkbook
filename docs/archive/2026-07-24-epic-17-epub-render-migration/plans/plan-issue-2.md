# Epic 17 Issue 2 — 資料層基礎建設：EPUB FXL/流式判斷與回填 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在「建構閱讀器 widget 之前」就能知道一本 EPUB 是固定版面（FXL）還是流式（reflowable），把判斷結果快取進 `books` 資料表，供 Issue 3 的 `ReaderScreen` 分派邏輯使用。本工單純粹是資料層/匯入管線的 prefactor，不改變任何使用者可見行為。

**Architecture:** `BookMetadataChannel.kt` 匯入時既有的 `extractEpubMetadata()`（已經建構完整 Readium `Publication`）免費多讀一個 `publication.metadata.layout` 欄位；新增獨立的 `detectEpubLayout()` 方法供既有書籍「補判斷」情境使用。`sqlite_library_repository.dart` schema migration 至 version 11，新增 `books.is_fixed_layout`（nullable INTEGER）。`Book` model 對應新增 `bool? isFixedLayout` 欄位。`LibraryRepository` 新增 `detectAndCacheEpubLayout()` 方法，封裝「呼叫 method channel → 寫回資料庫」的完整流程，供 Issue 3 直接呼叫。

**Tech Stack:** Kotlin（Android 原生，Readium `kotlin-toolkit`）、Dart/Flutter（`sqflite`）、`flutter_test`（純 Dart，`sqflite_common_ffi`，不需裝置）。

## Global Constraints

- Schema migration：`sqlite_library_repository.dart` 的 `version` 由 `10` 升到 `11`（見 `docs/epics/epic-17-epub-render-migration/spec.md`「資料模型」）。
- 新欄位名稱固定為 `is_fixed_layout INTEGER`（SQL 欄位，snake_case——`spec.md` 第 25 行明確寫定，刻意與 `books` 表其餘既有欄位的 camelCase 命名不一致，這是 spec 已審定的決策，實作時不得依「跟表內其他欄位一致」的直覺改回 camelCase）；語意 `NULL`=尚未判斷、`0`=流式、`1`=FXL。
- `Book` model 對應欄位固定為 Dart camelCase：`bool? isFixedLayout`。
- `onUpgrade` 比照既有 `if (oldVersion < N)` 累加式慣例（`_addHeaderFooterColumns` 等既有遷移函式），新增的遷移函式僅在 `books` 表已存在時執行 `ALTER TABLE`。
- `BookMetadataChannel.kt` 新增的 `detectEpubLayout(path, result)` 必須比照 `extractEpubMetadata()` 既有的 `try { ... } finally { publication.close() }` 慣用語法（第 239-258 行），確保例外情況下仍會關閉 `publication`。
- 本工單**不**修改 `ReaderScreen`（`widget.book.isFixedLayout` 的實際消費與 widget 分派留給 Issue 3）。
- 本工單不需要真實裝置即可驗收；`AssetRetriever`/`PublicationOpener` 呼叫透過既有測試替身模式驗證，比照 `extractEpubMetadata` 既有測試慣例。
- `flutter analyze`（於 `app/` 目錄執行）必須維持乾淨。
- `./gradlew.bat :app:testDebugUnitTest`（於 `app/android` 目錄執行）必須維持通過（目前專案完全沒有 JVM 單元測試——`app/android/app/build.gradle.kts` 只有 `testImplementation("junit:junit:4.13.2")`，無 mockk/robolectric，本工單不引入新的測試依賴）。

---

### Task 1: `Book` model 新增 `isFixedLayout` 欄位

**Files:**
- Modify: `app/lib/library/models/book.dart`
- Test: `app/test/library/models/book_test.dart`

**Interfaces:**
- Consumes: 無（本工單起點任務）。
- Produces: `Book.isFixedLayout`（`bool?`）欄位；`Book.toMap()`/`Book.fromMap()` 對應 SQL 鍵 `'is_fixed_layout'`（`int?`，`0`/`1`/`null`）；`Book.copyWith({bool? isFixedLayout, String? groupName})`；`Book` 的 `operator ==`/`hashCode`（本工單新增，先前完全沒有）。後續 Task 2-5 皆依賴這個欄位存在。

- [ ] **Step 1: 在 `book_test.dart` 新增失敗測試**

在檔案最後（`}` 之前）新增以下測試：

```dart
  test('isFixedLayout 欄位可正確往返（epic-17-epub-render-migration Issue 2）',
      () {
    final fxlBook = Book(
      id: 'b8',
      title: 'FXL 漫畫',
      format: BookFileFormat.epub,
      filePath: '/storage/emulated/0/comic.epub',
      source: BookSource.local,
      isFixedLayout: true,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final reflowableBook = Book(
      id: 'b9',
      title: '流式小說',
      format: BookFileFormat.epub,
      filePath: '/storage/emulated/0/novel.epub',
      source: BookSource.local,
      isFixedLayout: false,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    expect(Book.fromMap(fxlBook.toMap()).isFixedLayout, isTrue);
    expect(Book.fromMap(reflowableBook.toMap()).isFixedLayout, isFalse);
  });

  test('isFixedLayout 未設定時，往返後仍為 null（代表尚未判斷過，或格式不適用）',
      () {
    final book = Book(
      id: 'b10',
      title: 'PDF 書籍',
      format: BookFileFormat.pdf,
      filePath: '/storage/emulated/0/report.pdf',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.isFixedLayout, isNull);
  });

  test('copyWith(isFixedLayout: ...) 只改變 isFixedLayout，其餘欄位保持不變',
      () {
    final book = Book(
      id: 'b11',
      title: '流式小說',
      format: BookFileFormat.epub,
      filePath: '/storage/emulated/0/novel.epub',
      source: BookSource.local,
      groupName: '小說',
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    final detected = book.copyWith(isFixedLayout: false);

    expect(detected.isFixedLayout, isFalse);
    expect(detected.id, book.id);
    expect(detected.title, book.title);
    expect(detected.groupName, book.groupName);
    expect(detected.createTime, book.createTime);
    expect(detected.lastReadTime, book.lastReadTime);
  });

  test('operator== 與 hashCode：欄位值完全相同視為相等，isFixedLayout 不同則不相等',
      () {
    Book build({bool? isFixedLayout}) => Book(
          id: 'b12',
          title: '書名',
          format: BookFileFormat.epub,
          filePath: '/storage/emulated/0/book.epub',
          source: BookSource.local,
          isFixedLayout: isFixedLayout,
          createTime: DateTime.fromMillisecondsSinceEpoch(1000),
          lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
        );

    final a = build(isFixedLayout: true);
    final b = build(isFixedLayout: true);
    final c = build(isFixedLayout: false);
    final d = build();

    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
    expect(a, isNot(equals(c)));
    expect(a, isNot(equals(d)));
  });
```

- [ ] **Step 2: 執行測試確認失敗**

於 `app/` 目錄執行：

```bash
flutter test test/library/models/book_test.dart
```

預期：編譯失敗（`isFixedLayout` 未定義的具名參數）或執行期斷言失敗（`operator==`/`copyWith` 尚未支援該參數）。

- [ ] **Step 3: 修改 `book.dart` 新增欄位**

在 `final int? totalCharacterCount;` 欄位宣告（第 39 行）後新增：

```dart
  /// 本書是否為固定版面（FXL）EPUB，`null` 代表尚未判斷過（涵蓋 Phase 1
  /// 上線前已匯入的既有書籍）或本書非 EPUB 格式（PDF/TXT 恆為 `null`，
  /// 語意上不適用，見 epic-17-epub-render-migration/spec.md「資料模型」）。
  /// 判斷結果由 `BookMetadataChannel.kt` 的 `extractEpubMetadata()`（匯入時）
  /// 或 `detectEpubLayout()`（既有書籍補判斷）提供，寫入後供 `ReaderScreen`
  /// 決定建構 `EpubReaderView`（Readium）或 `FoliateEpubReaderView`
  /// （`foliate-js`），**與 `reader/writing_mode.dart` 的
  /// `EpubLayoutInfo.isFixedLayout`（Readium 開書後才回報的執行期狀態）
  /// 是兩個不同概念，互不影響**。
  final bool? isFixedLayout;
```

在建構子（第 45-60 行）新增對應參數，緊接在 `this.totalCharacterCount,` 之後：

```dart
    this.totalCharacterCount,
    this.isFixedLayout,
```

修改 `toMap()`（第 62-79 行），在 `'totalCharacterCount': totalCharacterCount,` 之後新增：

```dart
      'totalCharacterCount': totalCharacterCount,
      // 欄位名刻意用 snake_case（spec.md「資料模型」決策），與本表其餘
      // 欄位的 camelCase 命名不一致，不是疏漏。
      'is_fixed_layout':
          isFixedLayout == null ? null : (isFixedLayout! ? 1 : 0),
```

修改 `fromMap()`（第 81-99 行），在 `totalCharacterCount: map['totalCharacterCount'] as int?,` 之後新增：

```dart
      totalCharacterCount: map['totalCharacterCount'] as int?,
      isFixedLayout: map['is_fixed_layout'] == null
          ? null
          : (map['is_fixed_layout'] as int) == 1,
```

修改 `copyWith()`（第 103-119 行），簽章與內容改為：

```dart
  /// 回傳欄位值與自身相同的新物件，僅覆寫明確傳入的參數。[groupName] 供
  /// Issue 10 的批次分類異動使用；[isFixedLayout] 供本 Issue 的 EPUB 版面
  /// 判斷/回填流程使用。
  Book copyWith({String? groupName, bool? isFixedLayout}) {
    return Book(
      id: id,
      title: title,
      author: author,
      format: format,
      filePath: filePath,
      source: source,
      coverPath: coverPath,
      progress: progress,
      epubLocator: epubLocator,
      pdfPageIndex: pdfPageIndex,
      totalCharacterCount: totalCharacterCount,
      isFixedLayout: isFixedLayout ?? this.isFixedLayout,
      groupName: groupName ?? this.groupName,
      createTime: createTime,
      lastReadTime: lastReadTime,
    );
  }
```

（附帶修正既有缺陷：目前 `copyWith()` 遺漏 `totalCharacterCount`，呼叫 `copyWith()` 會靜默把該欄位重置為 `null`；上方版本一併補上 `totalCharacterCount: totalCharacterCount,`，這是本次修改函式本體時的最小必要修正，非額外範圍擴張。）

在 `copyWith()` 之後（class 結尾 `}` 之前）新增：

```dart

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Book &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          author == other.author &&
          format == other.format &&
          filePath == other.filePath &&
          source == other.source &&
          coverPath == other.coverPath &&
          progress == other.progress &&
          epubLocator == other.epubLocator &&
          pdfPageIndex == other.pdfPageIndex &&
          totalCharacterCount == other.totalCharacterCount &&
          isFixedLayout == other.isFixedLayout &&
          groupName == other.groupName &&
          createTime == other.createTime &&
          lastReadTime == other.lastReadTime;

  @override
  int get hashCode => Object.hash(
        id,
        title,
        author,
        format,
        filePath,
        source,
        coverPath,
        progress,
        epubLocator,
        pdfPageIndex,
        totalCharacterCount,
        isFixedLayout,
        groupName,
        createTime,
        lastReadTime,
      );
```

- [ ] **Step 4: 執行測試確認通過**

```bash
flutter test test/library/models/book_test.dart
```

預期：全數 PASS（含既有的 `copyWith()` 不傳參數、`totalCharacterCount` 往返等既有測試——確認附帶修正沒有破壞既有行為）。

- [ ] **Step 5: Commit**

```bash
git add app/lib/library/models/book.dart app/test/library/models/book_test.dart
git commit -m "feat(epic-17): Book model 新增 isFixedLayout 欄位與 ==/hashCode"
```

---

### Task 2: `sqlite_library_repository.dart` schema migration v10→v11

**Files:**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Book.isFixedLayout`／`Book.toMap()`/`Book.fromMap()`（新增的 `'is_fixed_layout'` 鍵）。
- Produces: `books` 表新增 `is_fixed_layout INTEGER` 欄位（version 11）；`SqliteLibraryRepository.open()` 的 `version` 常數變為 `11`。Task 5 依賴這個欄位存在才能寫入/讀出。

- [ ] **Step 1: 在 `sqlite_library_repository_test.dart` 新增失敗測試**

在檔案最後（`}` 之前，緊接在既有的 v9→v10 遷移測試之後）新增：

```dart
  test('全新安裝的 books 表包含 is_fixed_layout 欄位（version 11 起 onCreate 已含括）',
      () async {
    await repository.insertBook(
        _book('b_layout').copyWith(isFixedLayout: true));

    final books = await repository.listBooks();
    expect(books.single.isFixedLayout, isTrue);
  });

  test('既有 version 10 裝置升級到 version 11，books 表正確補上 is_fixed_layout 欄位（ALTER TABLE 路徑）',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v10_to_v11_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 10」的舊資料庫：手動以 version 10 當時的完整
    // books 表 schema（無 is_fixed_layout 欄位）建立，不透過
    // SqliteLibraryRepository.open()（該方法目前的 onCreate 已經是
    // version 11 的最終 schema），比照既有 v9→v10 遷移測試寫法。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 10,
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

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=10 →
    // newVersion=11），驗證既有書籍資料不受影響、新欄位預設為 NULL、且可寫入。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final books = await upgraded.listBooks();
    expect(books.single.title, '既有書籍'); // 既有資料不受影響
    expect(books.single.isFixedLayout, isNull); // 新欄位存在且預設 NULL

    // 證明欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'books',
      {'is_fixed_layout': 0},
      where: 'id = ?',
      whereArgs: ['b1'],
    );
    final updated = await upgraded.listBooks();
    expect(updated.single.isFixedLayout, isFalse);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

於 `app/` 目錄執行：

```bash
flutter test test/library/sqlite_library_repository_test.dart
```

預期：FAIL（`is_fixed_layout` 欄位不存在，或 `version` 仍是 10 導致 `onUpgrade` 沒有機會執行到新遷移分支——因為固定資料庫的 `version` 還沒改，`openDatabase` 會判定不需要升級）。

- [ ] **Step 3: 修改 `sqlite_library_repository.dart`**

`version: 10,`（第 27 行）改為：

```dart
      version: 11,
```

`books` 表 `onCreate` 定義（第 40-57 行）的 `totalCharacterCount INTEGER,` 之後新增一行：

```dart
            totalCharacterCount INTEGER,
            is_fixed_layout INTEGER,
```

`onUpgrade` 內既有的：

```dart
          await _createHighlightsTable(db);
          await _createNotesTable(db);
        } else if (oldVersion < 10) {
          // epic-6-annotations Issue 3：oldVersion 為 9 的裝置，
          // highlights／notes 表已存在（上方 if 分支已處理過），但欄位
          // 版本停留在 Issue 2（無 PDF 欄位），僅需 ALTER TABLE 補上。
          await _addPdfAnnotationColumns(db);
        }
      },
```

改為（新增一個無條件的 `if (oldVersion < 11)` 區塊，比照 `oldVersion < 5`／`oldVersion < 6`／`oldVersion < 8` 既有原則——不受 highlights/notes 表的 if/else 互斥結構影響）：

```dart
          await _createHighlightsTable(db);
          await _createNotesTable(db);
        } else if (oldVersion < 10) {
          // epic-6-annotations Issue 3：oldVersion 為 9 的裝置，
          // highlights／notes 表已存在（上方 if 分支已處理過），但欄位
          // 版本停留在 Issue 2（無 PDF 欄位），僅需 ALTER TABLE 補上。
          await _addPdfAnnotationColumns(db);
        }
        if (oldVersion < 11) {
          // epic-17-epub-render-migration Issue 2：EPUB FXL/流式判斷快取
          // 欄位，補追加到既有（version 1 起已存在）的 books 表，見
          // docs/epics/epic-17-epub-render-migration/spec.md「資料模型」。
          // 刻意放在上方 if/else 之外、無條件檢查，比照 oldVersion < 5/6
          // 區塊的既有原則。
          await _addEpubLayoutColumn(db);
        }
      },
```

在 `_addPdfAnnotationColumns()` 方法定義（第 298-307 行）之後新增：

```dart

  static Future<void> _addEpubLayoutColumn(Database db) async {
    // EPUB FXL/流式判斷快取（epic-17-epub-render-migration Issue 2），補
    // 追加到既有（version 1 起已存在）的 books 表，見
    // docs/epics/epic-17-epub-render-migration/spec.md「資料模型」。
    // nullable：NULL=尚未判斷、0=流式、1=FXL。比照 _addHeaderFooterColumns
    // 既有慣例，僅在表已存在時才執行 ALTER TABLE。
    final tables = await db
        .rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='books'");
    if (tables.isNotEmpty) {
      await db.execute('ALTER TABLE books ADD COLUMN is_fixed_layout INTEGER');
    }
  }
```

- [ ] **Step 4: 執行測試確認通過**

```bash
flutter test test/library/sqlite_library_repository_test.dart
```

預期：全數 PASS，含既有全部遷移測試（v1→v5、v2→v4、v5→v6、v6→v7、v7→v8、v8→v9、v9→v10 等）不受影響。

- [ ] **Step 5: Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-17): books 表 schema migration 至 version 11，新增 is_fixed_layout 欄位"
```

---

### Task 3: `BookMetadataChannel.kt`——`extractEpubMetadata` 擴充 + 新增 `detectEpubLayout`

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt`

**Interfaces:**
- Consumes: 無新的 Dart 端依賴（本 Task 純原生端修改）。
- Produces: `extractMetadata`（`format: "epub"`）回傳 map 新增 `"isFixedLayout": Boolean`；新增 method channel 方法 `detectEpubLayout`，參數 `{"uri": String}`，成功回傳 `{"isFixedLayout": Boolean}`。Task 4（Dart 端讀取 `isFixedLayout`）與 Task 5（`detectAndCacheEpubLayout` 呼叫 `detectEpubLayout`）依賴這兩個 wire 格式。

**本 Task 無 JVM 單元測試**：`app/android/app/build.gradle.kts` 目前只有 `testImplementation("junit:junit:4.13.2")`，無 mockk/robolectric；`detectEpubLayout`／`extractEpubMetadata` 的核心邏輯（`AssetRetriever.retrieve()`／`PublicationOpener.open()`）本質上耦合 Android `Context`/`ContentResolver` 與 Readium 的非同步開檔流程，沒有可抽出、不依賴這些框架物件的純邏輯可供 JVM 測試——`resolveAbsoluteUrl()`/`openParcelFileDescriptor()` 這兩個既有的純字串邏輯本工單未修改，不需要新增測試。比照 Issue 2 驗收標準的既定退路：僅需確認 `./gradlew.bat :app:testDebugUnitTest` 既有測試（0 個測試）不受影響即可。

- [ ] **Step 1: 新增 import**

在第 21 行 `import org.readium.r2.shared.publication.services.cover` 之前新增：

```kotlin
import org.readium.r2.shared.publication.Layout
```

- [ ] **Step 2: 擴充 `extractEpubMetadata()` 讀取 `isFixedLayout`**

第 239-258 行的：

```kotlin
                try {
                    val title = publication.metadata.title
                    val author = publication.metadata.authors.firstOrNull()?.name
                    // PNG 壓縮與封面退路的 I/O／解碼皆為耗時工作，移到背景執行緒避免
                    // 阻塞主執行緒；withContext 返回後會自動切回 scope 的 Main
                    // dispatcher。
                    val coverBytes = withContext(Dispatchers.IO) {
                        val bitmap = publication.cover() ?: findFallbackCoverBitmap(publication)
                        bitmap?.let { bitmapToPngBytes(it) }
                    }
                    result.success(
                        mapOf(
                            "title" to title,
                            "author" to author,
                            "coverBytes" to coverBytes,
                        ),
                    )
                } finally {
                    publication.close()
                }
```

改為：

```kotlin
                try {
                    val title = publication.metadata.title
                    val author = publication.metadata.authors.firstOrNull()?.name
                    // epic-17-epub-render-migration Issue 2：免費多讀一個既有欄位——
                    // publication 本來就已經在這裡被建構，不需要新的解析路徑
                    // （見 docs/epics/epic-17-epub-render-migration/spec.md「模組」）。
                    val isFixedLayout = publication.metadata.layout == Layout.FIXED
                    // PNG 壓縮與封面退路的 I/O／解碼皆為耗時工作，移到背景執行緒避免
                    // 阻塞主執行緒；withContext 返回後會自動切回 scope 的 Main
                    // dispatcher。
                    val coverBytes = withContext(Dispatchers.IO) {
                        val bitmap = publication.cover() ?: findFallbackCoverBitmap(publication)
                        bitmap?.let { bitmapToPngBytes(it) }
                    }
                    result.success(
                        mapOf(
                            "title" to title,
                            "author" to author,
                            "coverBytes" to coverBytes,
                            "isFixedLayout" to isFixedLayout,
                        ),
                    )
                } finally {
                    publication.close()
                }
```

- [ ] **Step 3: 新增 `detectEpubLayout()` 方法**

在 `extractEpubMetadata()` 方法定義（結尾在原第 267 行 `}`）之後、`extractPdfMetadata()` 定義之前，新增：

```kotlin

    /**
     * 供既有書籍（`is_fixed_layout` 為 `null`）補判斷使用（見
     * docs/epics/epic-17-epub-render-migration/spec.md「既有書籍回填流程」）。
     * 與 [extractEpubMetadata] 共用同一套開檔模式，但跳過封面點陣圖解碼
     * （最耗時的部分），只讀 `publication.metadata.layout`。
     */
    private fun detectEpubLayout(path: String, result: MethodChannel.Result) {
        scope.launch {
            try {
                val httpClient = DefaultHttpClient()
                val assetRetriever = AssetRetriever(context.contentResolver, httpClient)
                val asset = assetRetriever.retrieve(resolveAbsoluteUrl(path)).getOrElse {
                    result.error("detection_failed", "找不到檔案或檔案已損毀：$path", null)
                    return@launch
                }
                val publicationParser = DefaultPublicationParser(
                    context,
                    httpClient,
                    assetRetriever,
                    pdfFactory = null,
                )
                val publicationOpener = PublicationOpener(publicationParser)
                val publication =
                    publicationOpener.open(asset, allowUserInteraction = false).getOrElse {
                        asset.close()
                        result.error("detection_failed", "無法解析 EPUB 檔案：${it.message}", null)
                        return@launch
                    }
                try {
                    val isFixedLayout = publication.metadata.layout == Layout.FIXED
                    result.success(mapOf("isFixedLayout" to isFixedLayout))
                } finally {
                    publication.close()
                }
            } catch (e: Exception) {
                result.error(
                    "detection_failed",
                    "判斷 EPUB 版面格式時發生未預期的錯誤：${e.message}",
                    null,
                )
            }
        }
    }
```

- [ ] **Step 4: 在 `onMethodCall` 新增路由**

第 79-93 行的：

```kotlin
        when (call.method) {
            "extractMetadata" -> {
                val path = call.argument<String>("uri")
                val format = call.argument<String>("format")
                if (path == null || format == null) {
                    result.error("invalid_arguments", "缺少 uri 或 format 參數", null)
                    return
                }
                when (format) {
                    "epub" -> extractEpubMetadata(path, result)
                    "pdf" -> extractPdfMetadata(path, result)
                    else -> result.error("unsupported_format", "不支援的格式：$format", null)
                }
            }
```

改為（新增 `"detectEpubLayout"` 分支，放在 `"extractMetadata"` 之後）：

```kotlin
        when (call.method) {
            "extractMetadata" -> {
                val path = call.argument<String>("uri")
                val format = call.argument<String>("format")
                if (path == null || format == null) {
                    result.error("invalid_arguments", "缺少 uri 或 format 參數", null)
                    return
                }
                when (format) {
                    "epub" -> extractEpubMetadata(path, result)
                    "pdf" -> extractPdfMetadata(path, result)
                    else -> result.error("unsupported_format", "不支援的格式：$format", null)
                }
            }
            "detectEpubLayout" -> {
                val path = call.argument<String>("uri")
                if (path == null) {
                    result.error("invalid_arguments", "缺少 uri 參數", null)
                    return
                }
                detectEpubLayout(path, result)
            }
```

- [ ] **Step 5: 編譯確認**

於 `app/android` 目錄執行：

```bash
./gradlew.bat :app:compileDebugKotlin
```

預期：`BUILD SUCCESSFUL`，無編譯錯誤。

- [ ] **Step 6: 執行既有 JVM 測試確認無回歸**

```bash
./gradlew.bat :app:testDebugUnitTest
```

預期：`BUILD SUCCESSFUL`（目前無任何測試案例，執行 0 個測試即為預期行為）。

- [ ] **Step 7: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt
git commit -m "feat(epic-17): BookMetadataChannel 新增 EPUB FXL/流式判斷（extractEpubMetadata 擴充 + detectEpubLayout）"
```

---

### Task 4: `book_import_service_impl.dart`——匯入流程寫入 `isFixedLayout`

**Files:**
- Modify: `app/lib/library/book_import_service_impl.dart`
- Test: `app/test/library/book_import_service_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Book(isFixedLayout: ...)` 具名參數；Task 3 的 `extractMetadata` 回傳 map 新增的 `"isFixedLayout"` 鍵（本 Task 的 Dart 測試以 mock method channel 驗證，不依賴真實原生端執行）。
- Produces: 匯入 EPUB 時 `Book.isFixedLayout` 正確依 `extractMetadata` 回傳值寫入；匯入 PDF/TXT 時恆為 `null`。

- [ ] **Step 1: 在 `book_import_service_test.dart` 新增失敗測試**

在既有的「匯入 EPUB 檔案呼叫 extractMetadata(format: epub) 並寫入正確詮釋資料」測試之後新增：

```dart
  test('匯入 EPUB 檔案時，extractMetadata 回傳的 isFixedLayout 正確寫入 Book',
      () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        return {
          'title': '定樣式漫畫',
          'author': null,
          'coverBytes': null,
          'isFixedLayout': true,
        };
      }
      return null;
    });

    final books = await service.importFiles(['content://example/comic.epub']);

    expect(books.single.isFixedLayout, isTrue);
  });

  test('匯入流式 EPUB（isFixedLayout: false）時正確寫入 Book', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        return {
          'title': '流式小說',
          'author': null,
          'coverBytes': null,
          'isFixedLayout': false,
        };
      }
      return null;
    });

    final books = await service.importFiles(['content://example/novel.epub']);

    expect(books.single.isFixedLayout, isFalse);
  });

  test('匯入 PDF 檔案時，isFixedLayout 維持 null（extractMetadata 回傳無此欄位）',
      () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'extractMetadata') {
        return {'title': null, 'author': null, 'coverBytes': null};
      }
      return null;
    });

    final books = await service.importFiles(['content://example/report.pdf']);

    expect(books.single.isFixedLayout, isNull);
  });

  test('匯入 TXT 檔案時，isFixedLayout 維持 null（不呼叫 extractMetadata）',
      () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      return null;
    });

    final books = await service.importFiles(['content://example/notes.txt']);

    expect(books.single.isFixedLayout, isNull);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

於 `app/` 目錄執行：

```bash
flutter test test/library/book_import_service_test.dart
```

預期：前兩個新測試 FAIL（`isFixedLayout` 未寫入，恆為 `null`）；後兩個新測試巧合通過（因為 `Book` 目前預設就是 `null`）——這是預期的，Step 3 完成後全部應仍維持通過，不會变成 FAIL。

- [ ] **Step 3: 修改 `_importSingleFile()` 寫入 `isFixedLayout`**

第 200-202 行的：

```dart
    var title = fallbackTitle;
    String? author;
    String? coverPath;
```

改為：

```dart
    var title = fallbackTitle;
    String? author;
    String? coverPath;
    bool? isFixedLayout;
```

第 213-217 行的：

```dart
        final extractedTitle = metadata?['title'] as String?;
        if (extractedTitle != null && extractedTitle.isNotEmpty) {
          title = extractedTitle;
        }
        author = metadata?['author'] as String?;
```

改為：

```dart
        final extractedTitle = metadata?['title'] as String?;
        if (extractedTitle != null && extractedTitle.isNotEmpty) {
          title = extractedTitle;
        }
        author = metadata?['author'] as String?;
        // PDF 的 extractMetadata 回傳 map 沒有這個鍵，cast 結果自然為 null，
        // 不需要另外依 format 分支判斷（見
        // docs/epics/epic-17-epub-render-migration/spec.md「模組」）。
        isFixedLayout = metadata?['isFixedLayout'] as bool?;
```

第 227-238 行的 `Book(...)` 建構呼叫，在 `coverPath: coverPath,` 之後新增一行：

```dart
    final book = Book(
      id: id,
      title: title,
      author: author,
      format: format,
      filePath: resolvedUri,
      source: BookSource.local,
      coverPath: coverPath,
      isFixedLayout: isFixedLayout,
      groupName: folderName ?? BookGroup.uncategorized,
      createTime: now,
      lastReadTime: now,
    );
```

- [ ] **Step 4: 執行測試確認通過**

```bash
flutter test test/library/book_import_service_test.dart
```

預期：全數 PASS，含既有全部匯入測試（EPUB/PDF/TXT 匯入、詮釋資料提取失敗降級、資料夾批次匯入等）不受影響。

- [ ] **Step 5: Commit**

```bash
git add app/lib/library/book_import_service_impl.dart app/test/library/book_import_service_test.dart
git commit -m "feat(epic-17): 匯入流程寫入 extractMetadata 回傳的 isFixedLayout"
```

---

### Task 5: `LibraryRepository.detectAndCacheEpubLayout()`——既有書籍回填入口

**Files:**
- Modify: `app/lib/library/library_repository.dart`
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Modify: `app/test/support/fake_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `books.is_fixed_layout` 欄位；Task 3 的 `detectEpubLayout` method channel 契約（`{"uri": String}` → `{"isFixedLayout": Boolean}`）。
- Produces: `LibraryRepository.detectAndCacheEpubLayout(String bookId, String filePath)` → `Future<bool>`（呼叫端拿到的判斷結果，同時已寫回資料庫）。Issue 3 的 `ReaderScreen` 直接呼叫這個方法。

- [ ] **Step 1: 在 `sqlite_library_repository_test.dart` 新增失敗測試**

在既有的兩個 `is_fixed_layout` schema 測試之後新增：

```dart
  group('detectAndCacheEpubLayout', () {
    const channel = MethodChannel('elinkbook/book_metadata');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('呼叫 detectEpubLayout method channel 後，正確寫回資料庫並回傳結果',
        () async {
      await repository.insertBook(_book('b_detect'));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'detectEpubLayout');
        expect((call.arguments as Map)['uri'], 'content://example/b_detect');
        return {'isFixedLayout': true};
      });

      final result = await repository.detectAndCacheEpubLayout(
          'b_detect', 'content://example/b_detect');

      expect(result, isTrue);
      final books = await repository.listBooks();
      expect(books.single.isFixedLayout, isTrue);
    });

    test('判斷結果為流式（false）時，正確寫回資料庫', () async {
      await repository.insertBook(_book('b_detect_reflowable'));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        return {'isFixedLayout': false};
      });

      final result = await repository.detectAndCacheEpubLayout(
          'b_detect_reflowable', 'content://example/b_detect_reflowable');

      expect(result, isFalse);
      final books = await repository.listBooks();
      expect(
        books.firstWhere((b) => b.id == 'b_detect_reflowable').isFixedLayout,
        isFalse,
      );
    });
  });
```

在檔案頂端 import 區塊（第 1-9 行）新增：

```dart
import 'package:flutter/services.dart';
```

（`flutter_test` 已存在於既有 import；只需新增 `package:flutter/services.dart` 供 `MethodChannel`/`TestDefaultBinaryMessengerBinding` 使用。）

`main()` 內既有的 `setUpAll` （第 36-39 行）：

```dart
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
```

改為（本檔案至今只用純 `sqflite_common_ffi`，從未需要 Flutter binding；本 Task 首次在這個檔案使用 `TestDefaultBinaryMessengerBinding`，必須先初始化，否則呼叫 `setMockMethodCallHandler` 會在執行期拋出「Binding has not yet been initialized」）：

```dart
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
```

- [ ] **Step 2: 執行測試確認失敗**

於 `app/` 目錄執行：

```bash
flutter test test/library/sqlite_library_repository_test.dart
```

預期：編譯失敗（`detectAndCacheEpubLayout` 方法不存在）。

- [ ] **Step 3: 修改 `library_repository.dart` 新增抽象方法**

第 7-20 行的 `abstract class LibraryRepository` 定義，在 `Future<void> deleteGroup(String name);` 之後新增：

```dart
  Future<void> deleteGroup(String name);

  /// 供既有書籍（`isFixedLayout == null`）一次性補判斷 EPUB 是否為固定版面
  /// （FXL），呼叫原生端 `detectEpubLayout` method channel 後寫回 [bookId]
  /// 對應資料列的 `is_fixed_layout` 欄位，回傳判斷結果（見
  /// docs/epics/epic-17-epub-render-migration/spec.md「既有書籍回填流程」）。
  /// `ReaderScreen`（Issue 3）建構閱讀器 widget 之前呼叫。
  Future<bool> detectAndCacheEpubLayout(String bookId, String filePath);
```

- [ ] **Step 4: 修改 `sqlite_library_repository.dart` 實作**

在檔案頂端 import 區塊新增：

```dart
import 'package:flutter/services.dart';
```

在 class 內新增靜態 channel 常數（與 `book_import_service_impl.dart` 使用同一個原生端 channel），放在 `final Database _db;` 宣告（第 20 行）之後：

```dart
class SqliteLibraryRepository implements LibraryRepository {
  final Database _db;

  static const _metadataChannel = MethodChannel('elinkbook/book_metadata');

  SqliteLibraryRepository._(this._db);
```

在 `close()` 方法（第 313 行）之後新增方法實作：

```dart

  @override
  Future<bool> detectAndCacheEpubLayout(String bookId, String filePath) async {
    final response = await _metadataChannel.invokeMapMethod<String, Object?>(
      'detectEpubLayout',
      {'uri': filePath},
    );
    final isFixedLayout = response?['isFixedLayout'] as bool? ?? false;
    await _db.update(
      'books',
      {'is_fixed_layout': isFixedLayout ? 1 : 0},
      where: 'id = ?',
      whereArgs: [bookId],
    );
    return isFixedLayout;
  }
```

- [ ] **Step 5: 修改 `fake_library_repository.dart` 補上介面實作**

`FakeLibraryRepository` 的建構子（第 12-19 行）改為：

```dart
class FakeLibraryRepository implements LibraryRepository {
  FakeLibraryRepository({
    List<Book> initialBooks = const [],
    this.throwOnListBooks = false,
    this.detectedIsFixedLayout = false,
  })  : _books = List.of(initialBooks),
        _groups = {
          BookGroup.uncategorized,
          for (final book in initialBooks) book.groupName,
        };

  final bool throwOnListBooks;

  /// 供測試控制 [detectAndCacheEpubLayout] 的模擬回傳值（比照本檔案「假
  /// 實作」定位——真實的 method channel 呼叫只發生在
  /// `SqliteLibraryRepository`，這裡不觸及任何原生端）。
  final bool detectedIsFixedLayout;

  /// 記錄每次 [detectAndCacheEpubLayout] 呼叫的 bookId，供測試驗證呼叫
  /// 次數/對象（例如驗證「只在 isFixedLayout == null 時才觸發」）。
  final List<String> detectAndCacheEpubLayoutCalls = [];

  final List<Book> _books;
  final Set<String> _groups;
```

在 `deleteGroup()` 方法（第 101-112 行）之後、`_withGroupName()` 方法之前新增：

```dart

  @override
  Future<bool> detectAndCacheEpubLayout(String bookId, String filePath) async {
    detectAndCacheEpubLayoutCalls.add(bookId);
    final index = _books.indexWhere((b) => b.id == bookId);
    if (index != -1) {
      _books[index] =
          _books[index].copyWith(isFixedLayout: detectedIsFixedLayout);
    }
    return detectedIsFixedLayout;
  }
```

同時修改 `_withGroupName()`（第 114-126 行），在 `progress: book.progress,` 之後新增 `isFixedLayout: book.isFixedLayout,`，避免重新命名分類時遺失既有的 `isFixedLayout` 判斷結果（該函式目前也遺漏 `epubLocator`／`pdfPageIndex`／`totalCharacterCount`，這是既有的、與本次改動無關的缺口，不在本工單範圍內一併修正）：

```dart
  Book _withGroupName(Book book, String groupName) => Book(
        id: book.id,
        title: book.title,
        author: book.author,
        format: book.format,
        filePath: book.filePath,
        source: book.source,
        coverPath: book.coverPath,
        progress: book.progress,
        isFixedLayout: book.isFixedLayout,
        groupName: groupName,
        createTime: book.createTime,
        lastReadTime: book.lastReadTime,
      );
```

- [ ] **Step 6: 執行測試確認通過**

```bash
flutter test test/library/sqlite_library_repository_test.dart
flutter test test/library/book_import_service_test.dart
```

預期：全數 PASS。（`fake_library_repository.dart` 目前沒有專屬的獨立測試檔——它被 `reader_screen_test.dart`／`library_screen_test.dart` 等既有 widget test 共用，Task 6 會執行全套 `flutter test` 確保這些既有測試不受影響。）

- [ ] **Step 7: Commit**

```bash
git add app/lib/library/library_repository.dart app/lib/library/sqlite_library_repository.dart app/test/support/fake_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-17): LibraryRepository 新增 detectAndCacheEpubLayout 既有書籍回填入口"
```

---

### Task 6: 全面驗證

**Files:** 無新增/修改檔案（純驗證任務）。

**Interfaces:**
- Consumes: Task 1-5 的全部產出。
- Produces: 本工單完成的最終確認證據，供任務審查與 `issues.md` 狀態更新使用。

- [ ] **Step 1: 執行完整 Dart 測試套件**

於 `app/` 目錄執行：

```bash
flutter test
```

預期：全數 PASS，特別留意 `test/screens/reader_screen_test.dart`／`test/screens/library_screen_test.dart` 等大量依賴 `FakeLibraryRepository`／`Book` 的既有測試不受 Task 1/5 的欄位新增與介面擴充影響。

- [ ] **Step 2: 執行 `flutter analyze`**

```bash
flutter analyze
```

預期：`No issues found!`

- [ ] **Step 3: 執行 Kotlin 編譯與 JVM 測試**

於 `app/android` 目錄執行：

```bash
./gradlew.bat :app:compileDebugKotlin
./gradlew.bat :app:testDebugUnitTest
```

預期：兩者皆 `BUILD SUCCESSFUL`。

- [ ] **Step 4: 確認 `git status` 乾淨（僅含本工單預期變更）**

```bash
git status
```

預期：僅列出 Task 1-5 修改/新增的檔案，無不相關的暫存產物。

- [ ] **Step 5: 更新 `issues.md` Issue 2 狀態**

修改 `docs/epics/epic-17-epub-render-migration/issues.md` 的「## Issue 2」區塊，在 `**Status:** \`ready-for-agent\`` 之後、`**依賴：**` 之前插入完成摘要（比照 Issue 1 既有的完成摘要寫法），例如：

```markdown
**Status:** ✅ 已完成。依 `plans/plan-issue-2.md` Task 1-6 完成 `Book` model／schema migration（v10→v11）／`BookMetadataChannel.kt`（`extractEpubMetadata` 擴充 + 新增 `detectEpubLayout`）／匯入流程／`LibraryRepository.detectAndCacheEpubLayout()`。`flutter test`／`flutter analyze`／`./gradlew.bat :app:testDebugUnitTest` 皆通過。`ReaderScreen` 尚未接線（Issue 3 範圍）。
```

- [ ] **Step 6: Commit**

```bash
git add docs/epics/epic-17-epub-render-migration/issues.md
git commit -m "docs(epic-17): Issue 2 完成，更新 issues.md 狀態"
```
