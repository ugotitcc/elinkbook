# Epic 26 Issue 5：收斂已死的 EPUB 頁次估算管線（`totalCharacterCount`／`EpubPageEstimator`）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 移除 epic-20（Readium → foliate-js 遷移）後留下的孤兒程式碼——`Book.totalCharacterCount`、`EpubPageEstimator`、`EpubCharacterCountRepository`，以及依賴它們的 `_buildEpubFooter()`（頁尾死路徑）與 `TocBottomSheet` 的 EPUB 頁碼估算分支。完成後 `totalCharacterCount` 不再以任何形式被 App 讀寫（Issue 5 選項 A：整批除役，不重新設計字元數回報管道）。

**Architecture:** 依賴鏈由外而內分四層拆除，每層完成後專案仍可編譯、測試全數通過：(1) `Book` 資料模型層；(2) `ReaderScreen` 頁尾死路徑層；(3) `TocBottomSheet` 頁碼估算分支層＋`EpubPageEstimator` 檔案本體；(4) `EpubCharacterCountRepository`／`LoadedPrefs.totalCharacterCount`／`ReaderPrefsManager.saveTotalCharacterCount` 層（含 `main.dart` 組裝與全部測試/整合測試呼叫端）。SQLite `books.totalCharacterCount` 實體欄位**不刪除**（見 Global Constraints），只是不再被任何 Dart 程式碼讀寫。

**Tech Stack:** Flutter/Dart、`flutter_test`、`sqflite`／`sqflite_common_ffi`、`integration_test`。

**Spec:** `docs/epics/epic-26-architecture-hardening/issues.md`（「Issue 5」，含完整根因鏈與已決策範圍）；深度背景見 `docs/zoomout/pagination-flowable-formats.md` 第三部分。

## Global Constraints

- **不刪除 SQLite `books.totalCharacterCount` 實體欄位，不新增 schema migration。** 理由：`ALTER TABLE ... DROP COLUMN` 需要 SQLite 3.35+（2021-03 發布），而本專案 `minSdk=24`（Android 7.0）與政策門檻 API 30（Android 11）對應的系統內建 SQLite 版本皆遠低於 3.35，`sqflite` 在 Android 平台直接使用系統內建 SQLite（非自帶版本），無法保證所有支援裝置都能安全執行 `DROP COLUMN`。因此本計畫只移除 Dart 層（`Book` 模型／`SqliteLibraryRepository` 以外的所有讀寫）對這個欄位的依賴，欄位本身保留在 schema 中、永久不再被讀寫（見 Task 1 對 `sqlite_library_repository.dart` 的註解補充）。
- **`flutter analyze` 涵蓋 `app/integration_test/`**（`analysis_options.yaml` 未排除此目錄），因此即使 `integration_test` 需要真實裝置才能*執行*，本計畫的每個 Task 完成後仍必須確保該目錄下的檔案能**編譯**通過（`flutter analyze` 乾淨），不能只驗證 `app/test/` 底下的檔案。
- 每個 Task 完成後執行 `cd app && flutter analyze`（預期 `No issues found!`）與該 Task 涉及檔案對應的 `flutter test`，確認乾淨/全數通過才進下一個 Task。全部 Task 完成後於 Task 5 跑一次全專案 `flutter test`。
- 本計畫**不修改** `docs/adr/`、已歸檔的 `docs/epics/epic-17-*`／`docs/epics/epic-20-*` 目錄——這些是历史決策紀錄，不因本次清理回頭改寫。
- 遇到用本計畫指定的 old_string 做編輯卻找不到完全匹配（多半是空白字元轉錄落差）時，改用 Grep 在該檔案內定位確切位置，逐一以實際文字為 old_string 個別編輯，不得略過。
- Commit message 慣例沿用本 Epic 既有格式：`refactor(epic-26): Issue 5 Task N——<描述>`（異動生產程式碼時）或 `test(epic-26): Issue 5 Task N——<描述>`（純測試檔案異動時）。

---

### Task 1：移除 `Book.totalCharacterCount`

**Files:**
- Modify: `app/lib/library/models/book.dart`
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Modify: `app/test/library/models/book_test.dart`
- Modify: `app/test/support/fake_library_repository.dart`
- Modify: `app/test/support/fake_library_repository_test.dart`
- Modify: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Produces: `Book` 建構子／`toMap()`／`fromMap()`／`==`／`hashCode` 皆不再涉及 `totalCharacterCount`——Task 2-4 皆不消費此欄位。

**背景**：`books.totalCharacterCount` 實體欄位保留（見 Global Constraints），但 `Book` 模型與其所有測試/fake 消費端此後完全不讀寫它。

- [ ] **Step 1：`book.dart` 移除欄位／建構子／`toMap`／`fromMap`／`==`／`hashCode`**

編輯 `app/lib/library/models/book.dart`，共 6 處編輯：

1）移除欄位宣告與其文件註解：

```dart
  final int? pdfPageIndex;

  /// 全書字元數快取（epic-5-toc-pagination Issue 3，spec.md「分頁估算
  /// 模組」決策 #16），僅 EPUB 有值。`null` 代表尚未計算過，開書時原生端
  /// 據此觸發一次背景計算；非 `null` 則直接讀取快取，不重新走訪全書。
  final int? totalCharacterCount;

  /// 本書是否為固定版面（FXL）EPUB
```

取代為：

```dart
  final int? pdfPageIndex;

  /// 本書是否為固定版面（FXL）EPUB
```

2）移除建構子具名參數：

```dart
    this.pdfPageIndex,
    this.totalCharacterCount,
    this.isFixedLayout,
```

取代為：

```dart
    this.pdfPageIndex,
    this.isFixedLayout,
```

3）移除 `toMap()` 內的鍵值：

```dart
      'pdfPageIndex': pdfPageIndex,
      'totalCharacterCount': totalCharacterCount,
      // 欄位名刻意用 snake_case
```

取代為：

```dart
      'pdfPageIndex': pdfPageIndex,
      // 欄位名刻意用 snake_case
```

4）移除 `fromMap()` 內的鍵值：

```dart
      pdfPageIndex: map['pdfPageIndex'] as int?,
      totalCharacterCount: map['totalCharacterCount'] as int?,
      isFixedLayout: map['is_fixed_layout'] == null
```

取代為：

```dart
      pdfPageIndex: map['pdfPageIndex'] as int?,
      isFixedLayout: map['is_fixed_layout'] == null
```

5）移除 `copyWith()` 內部建構時帶入的值：

```dart
      pdfPageIndex: pdfPageIndex,
      totalCharacterCount: totalCharacterCount,
      contentFingerprint: contentFingerprint,
```

取代為：

```dart
      pdfPageIndex: pdfPageIndex,
      contentFingerprint: contentFingerprint,
```

6）移除 `==` 與 `hashCode` 內的比較/雜湊項：

```dart
          pdfPageIndex == other.pdfPageIndex &&
          totalCharacterCount == other.totalCharacterCount &&
          isFixedLayout == other.isFixedLayout &&
```

取代為：

```dart
          pdfPageIndex == other.pdfPageIndex &&
          isFixedLayout == other.isFixedLayout &&
```

```dart
        pdfPageIndex,
        totalCharacterCount,
        isFixedLayout,
```

取代為：

```dart
        pdfPageIndex,
        isFixedLayout,
```

- [ ] **Step 2：`sqlite_library_repository.dart` 補充孤兒欄位註解**

編輯 `app/lib/library/sqlite_library_repository.dart`，在 `CREATE TABLE books` 的 `totalCharacterCount INTEGER,` 這一行正上方新增註解：

```dart
            pdfPageIndex INTEGER,
            totalCharacterCount INTEGER,
            is_fixed_layout INTEGER,
```

取代為：

```dart
            pdfPageIndex INTEGER,
            // 【epic-26-architecture-hardening Issue 5】此欄位自 Issue 5 起
            // 不再被任何 Dart 程式碼讀寫（Book 模型已移除對應欄位）——刻意保留
            // 於 schema 中不刪除，因 ALTER TABLE DROP COLUMN 需要 SQLite 3.35+，
            // 本專案 minSdk=24 對應的系統內建 SQLite 版本無法保證支援，見
            // plan-issue-5.md Global Constraints。
            totalCharacterCount INTEGER,
            is_fixed_layout INTEGER,
```

同一檔案的 `_addTotalCharacterCountColumn` migration 方法（`ALTER TABLE books ADD COLUMN totalCharacterCount INTEGER` 那一行所在方法）不需要修改——它是既有裝置升級路徑的一部分，欄位既然保留，這個 migration 仍須存在。

- [ ] **Step 3：`book_test.dart` 刪除 2 個 `totalCharacterCount` 專屬測試**

編輯 `app/test/library/models/book_test.dart`，刪除以下整段（含前後各自的空行，共 2 個 `test(...)` 區塊）：

```dart
  test('totalCharacterCount 欄位可正確往返（Issue 3 新增）', () {
    final book = Book(
      id: 'b6',
      title: 'EPUB 書籍',
      format: BookFileFormat.epub,
      filePath: '/storage/emulated/0/book.epub',
      source: BookSource.local,
      totalCharacterCount: 123456,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.totalCharacterCount, 123456);
  });

  test('totalCharacterCount 未設定時，往返後仍為 null（代表尚未計算過）', () {
    final book = Book(
      id: 'b7',
      title: 'EPUB 書籍',
      format: BookFileFormat.epub,
      filePath: '/storage/emulated/0/book2.epub',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final restored = Book.fromMap(book.toMap());

    expect(restored.totalCharacterCount, isNull);
  });

```

（緊接其後的 `test('isFixedLayout 欄位可正確往返...` 保持不變。）

- [ ] **Step 4：`fake_library_repository.dart` 移除 `_withGroupName` 內的欄位帶入**

編輯 `app/test/support/fake_library_repository.dart`：

```dart
        epubLocator: book.epubLocator,
        pdfPageIndex: book.pdfPageIndex,
        totalCharacterCount: book.totalCharacterCount,
        isFixedLayout: book.isFixedLayout,
```

取代為：

```dart
        epubLocator: book.epubLocator,
        pdfPageIndex: book.pdfPageIndex,
        isFixedLayout: book.isFixedLayout,
```

- [ ] **Step 5：`fake_library_repository_test.dart` 移除對應建構參數與斷言**

編輯 `app/test/support/fake_library_repository_test.dart`：

```dart
        epubLocator: '{"href":"/c1.xhtml"}',
        pdfPageIndex: null,
        totalCharacterCount: 12345,
        isFixedLayout: false,
```

取代為：

```dart
        epubLocator: '{"href":"/c1.xhtml"}',
        pdfPageIndex: null,
        isFixedLayout: false,
```

```dart
      expect(book.epubLocator, '{"href":"/c1.xhtml"}');
      expect(book.totalCharacterCount, 12345);
      expect(book.isFixedLayout, false);
```

取代為：

```dart
      expect(book.epubLocator, '{"href":"/c1.xhtml"}');
      expect(book.isFixedLayout, false);
```

- [ ] **Step 6：`sqlite_library_repository_test.dart` 把 3 個 migration 測試改用原生 SQL 查詢驗證**

這 3 個測試驗證的是「schema migration 是否正確補上欄位、欄位是否可寫入」——這件事本身不受本 Issue 影響（欄位保留），只是不能再透過 `Book.fromMap()`／`repository.listBooks()` 間接驗證（`Book` 已無此欄位），改為直接查詢資料表。

編輯 `app/test/library/sqlite_library_repository_test.dart`：

```dart
  test('全新安裝的 books 表包含 totalCharacterCount 欄位（version 6 起 onCreate 已含括）',
      () async {
    await repository.insertBook(_book('b_char_count').copyWith());
    await repository.database.update(
      'books',
      {'totalCharacterCount': 55000},
      where: 'id = ?',
      whereArgs: ['b_char_count'],
    );

    final books = await repository.listBooks();
    expect(books.single.totalCharacterCount, 55000);
  });
```

取代為：

```dart
  test('全新安裝的 books 表包含 totalCharacterCount 欄位（version 6 起 onCreate 已含括，'
      '欄位保留但不再經 Book 模型讀寫，見 epic-26 Issue 5）', () async {
    await repository.insertBook(_book('b_char_count').copyWith());
    await repository.database.update(
      'books',
      {'totalCharacterCount': 55000},
      where: 'id = ?',
      whereArgs: ['b_char_count'],
    );

    final row = (await repository.database.query(
      'books',
      columns: ['totalCharacterCount'],
      where: 'id = ?',
      whereArgs: ['b_char_count'],
    ))
        .single;
    expect(row['totalCharacterCount'], 55000);
  });
```

```dart
    final books = await upgraded.listBooks();
    expect(books.single.title, 'Version 5 既有書籍'); // 既有資料不受影響
    expect(books.single.progress, 0.3);
    expect(books.single.totalCharacterCount, isNull); // 新欄位存在且預設 NULL

    // 證明欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'books',
      {'totalCharacterCount': 88888},
      where: 'id = ?',
      whereArgs: ['b1'],
    );
    final updated = await upgraded.listBooks();
    expect(updated.single.totalCharacterCount, 88888);
  });
```

取代為：

```dart
    final books = await upgraded.listBooks();
    expect(books.single.title, 'Version 5 既有書籍'); // 既有資料不受影響
    expect(books.single.progress, 0.3);
    final rowBeforeWrite = (await upgraded.database.query(
      'books',
      columns: ['totalCharacterCount'],
      where: 'id = ?',
      whereArgs: ['b1'],
    ))
        .single;
    expect(rowBeforeWrite['totalCharacterCount'], isNull); // 新欄位存在且預設 NULL

    // 證明欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'books',
      {'totalCharacterCount': 88888},
      where: 'id = ?',
      whereArgs: ['b1'],
    );
    final rowAfterWrite = (await upgraded.database.query(
      'books',
      columns: ['totalCharacterCount'],
      where: 'id = ?',
      whereArgs: ['b1'],
    ))
        .single;
    expect(rowAfterWrite['totalCharacterCount'], 88888);
  });
```

```dart
    final books = await upgraded.listBooks();
    expect(books.single.title, '最早期書籍');
    expect(books.single.epubLocator, isNull);
    expect(books.single.pdfPageIndex, isNull);
    expect(books.single.totalCharacterCount, isNull);

    await upgraded.database.update(
      'books',
      {'totalCharacterCount': 12345},
      where: 'id = ?',
      whereArgs: ['b1'],
    );
    final updated = await upgraded.listBooks();
    expect(updated.single.totalCharacterCount, 12345);
  });
```

取代為：

```dart
    final books = await upgraded.listBooks();
    expect(books.single.title, '最早期書籍');
    expect(books.single.epubLocator, isNull);
    expect(books.single.pdfPageIndex, isNull);
    final rowBeforeWrite = (await upgraded.database.query(
      'books',
      columns: ['totalCharacterCount'],
      where: 'id = ?',
      whereArgs: ['b1'],
    ))
        .single;
    expect(rowBeforeWrite['totalCharacterCount'], isNull);

    await upgraded.database.update(
      'books',
      {'totalCharacterCount': 12345},
      where: 'id = ?',
      whereArgs: ['b1'],
    );
    final rowAfterWrite = (await upgraded.database.query(
      'books',
      columns: ['totalCharacterCount'],
      where: 'id = ?',
      whereArgs: ['b1'],
    ))
        .single;
    expect(rowAfterWrite['totalCharacterCount'], 12345);
  });
```

- [ ] **Step 7：執行測試確認全數通過**

執行：
```bash
cd app && flutter test test/library/models/book_test.dart test/library/sqlite_library_repository_test.dart test/support/fake_library_repository_test.dart
```
預期：全數 PASS。

執行：`cd app && flutter analyze`
預期：`No issues found!`

- [ ] **Step 8：Commit**

```bash
git add app/lib/library/models/book.dart app/lib/library/sqlite_library_repository.dart app/test/library/models/book_test.dart app/test/support/fake_library_repository.dart app/test/support/fake_library_repository_test.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "refactor(epic-26): Issue 5 Task 1——移除 Book.totalCharacterCount 模型層讀寫，schema 欄位保留"
```

---

### Task 2：移除 `_buildEpubFooter()` 死路徑（`ReaderScreen` 部分）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: 無新介面（純刪除）。
- Produces: `ReaderScreen` 不再持有 `_totalCharacterCount` 欄位；`EpubPageEstimator` 檔案本身**尚未刪除**（`toc_bottom_sheet.dart` 仍在使用，留給 Task 3 一併處理）。

**背景**：`_buildEpubFooter()` 因 `_totalCharacterCount` 恆為 `null`（Task 1 之前就已如此，Task 1 只是移除了模型層對它的支援）而從未在正式路徑上被建構，是 epic-17 遷移後的死路徑。本 Task 只處理 `reader_screen.dart` 對它的依賴，不動 `epub_page_estimator.dart` 檔案本體（`toc_bottom_sheet.dart` 還在用）。

- [ ] **Step 1：移除頁尾建構呼叫與其條件式**

編輯 `app/lib/screens/reader_screen.dart`：

```dart
            Expanded(child: body),
            if (isFoliateFormat(format) &&
                !_isFixedLayout &&
                _totalCharacterCount != null &&
                _resolved != null &&
                _resolved!.showFooter &&
                _chromeVisible)
              _buildEpubFooter(_resolved!, _totalCharacterCount!),
          ],
```

取代為：

```dart
            Expanded(child: body),
          ],
```

- [ ] **Step 2：移除 `_buildEpubFooter()` 方法本體**

編輯 `app/lib/screens/reader_screen.dart`，刪除整段方法（含其文件註解）：

```dart
  /// EPUB 估算頁碼頁尾（Epic 5 Issue 3）：依目前生效版面參數＋全書字元數
  /// 快取換算總頁數，再依 _epubPositionInfo 的全書進度比例換算目前頁碼；
  /// 任一版面參數變動時，本方法在下一次 build() 會以新的 [resolved] 重新
  /// 計算，不需要額外的快取/失效邏輯（見 spec.md「估計頁數重算時機」）。
  Widget _buildEpubFooter(ResolvedPreferences resolved, int totalCharacterCount) {
    final screenSize = MediaQuery.of(context).size;
    final charsPerScreen = EpubPageEstimator.estimateCharsPerScreen(
      screenWidth: screenSize.width,
      screenHeight: screenSize.height,
      fontSize: resolved.fontSize,
      lineHeight: resolved.lineHeight,
      paragraphSpacing: resolved.paragraphSpacing,
      letterSpacing: resolved.letterSpacing,
      marginTop: resolved.marginTop,
      marginBottom: resolved.marginBottom,
      marginLeft: resolved.marginLeft,
      marginRight: resolved.marginRight,
    );
    final totalPages = EpubPageEstimator.estimateTotalPages(
      totalCharacterCount: totalCharacterCount,
      charsPerScreen: charsPerScreen,
    );
    final currentPage = EpubPageEstimator.estimateCurrentPage(
      progression: _epubPositionInfo?.progression,
      totalPages: totalPages,
    );
    return ReaderFooter(
      currentPage: currentPage,
      totalPages: totalPages,
      onPageChanged: (targetPage) {
        final progression = EpubPageEstimator.estimateProgression(
          targetPage: targetPage,
          totalPages: totalPages,
        );
        FoliateReaderView.jumpToProgression(_foliateEpubReaderViewKey, progression);
      },
    );
  }

```

- [ ] **Step 3：移除 `_totalCharacterCount` 欄位與其賦值**

編輯 `app/lib/screens/reader_screen.dart`：

```dart
  EpubPositionInfo? _epubPositionInfo;
  // EPUB 全書字元數快取，由 LoadedPrefs.totalCharacterCount 載入（若有）
  // 或 EpubReaderView.onCharacterCountReady 回報更新（Epic 5 Issue 3）。
  // null 代表尚未計算完成，此時 EPUB 頁尾不顯示（比照 PDF 頁尾等待
  // _pdfPageInfo 非 null 的既有模式）。
  int? _totalCharacterCount;
  // 目錄樹狀結構快取（Epic 5 Issue 4）
```

取代為：

```dart
  EpubPositionInfo? _epubPositionInfo;
  // 目錄樹狀結構快取（Epic 5 Issue 4）
```

```dart
        _initialPosition = loaded.readingPosition;
        _totalCharacterCount = loaded.totalCharacterCount;
        _totalCharacterCountNotifier.value = loaded.totalCharacterCount;
        _resolved = widget.prefsManager.resolve(
```

取代為：

```dart
        _initialPosition = loaded.readingPosition;
        _totalCharacterCountNotifier.value = loaded.totalCharacterCount;
        _resolved = widget.prefsManager.resolve(
```

（`_totalCharacterCountNotifier` 本身留給 Task 3 一併移除，此處只移除 `_totalCharacterCount` 這一行。）

- [ ] **Step 4：移除 `epub_page_estimator.dart` 的 import**

編輯 `app/lib/screens/reader_screen.dart`，刪除這一行：

```dart
import '../reader/epub_page_estimator.dart';
```

- [ ] **Step 5：更新 `_buildFoliateEpubFooter()` 的文件註解，移除對已刪除方法的引用**

編輯 `app/lib/screens/reader_screen.dart`：

```dart
  /// 流式 EPUB（FoliateReaderView）頁尾（epic-17-epub-render-migration
  /// Issue 6）：直接使用原生端 relocate 事件回報的 pageIndex／totalPages
  /// （foliate-js SectionProgress.getProgress() 的 location.current／
  /// location.total，近似頁碼概念，非精確渲染頁數，見 spec.md「頁碼
  /// 估算」）——與 _buildEpubFooter（Readium 遺留路徑，依全書字元數估算
  /// 頁數，post-epic-17 對流式書籍已是死路徑，見 plans/plan-issue-5.md
  /// 對 onZoneTapped 的相同結論）刻意不同，不重用其估算邏輯；本 widget
  /// 完全不呼叫任何字數統計（不送出 totalCharacterCount）。pageIndex 為
  /// 0-indexed（比照原生端既有慣例），ReaderFooter 要求 1-indexed，此處
  /// +1 換算。onPageChanged 透過既有 jumpToProgression（Issue 5）換算
  /// 目標頁對應的全書進度比例，與 _buildEpubFooter 的 onPageChanged 作法
  /// 相同（近似值，非精確反解頁碼）。
  Widget _buildFoliateEpubFooter(EpubPositionInfo info) {
```

取代為：

```dart
  /// 流式 EPUB（FoliateReaderView）頁尾（epic-17-epub-render-migration
  /// Issue 6）：直接使用原生端 relocate 事件回報的 pageIndex／totalPages
  /// （foliate-js SectionProgress.getProgress() 的 location.current／
  /// location.total，近似頁碼概念，非精確渲染頁數，見 spec.md「頁碼
  /// 估算」）。pageIndex 為 0-indexed（比照原生端既有慣例），ReaderFooter
  /// 要求 1-indexed，此處 +1 換算。onPageChanged 透過既有
  /// jumpToProgression（Issue 5）換算目標頁對應的全書進度比例（近似值，
  /// 非精確反解頁碼）。舊有依全書字元數估算頁數的 Readium 遺留路徑
  /// （`_buildEpubFooter`／`EpubPageEstimator`）已於
  /// epic-26-architecture-hardening Issue 5 移除，見
  /// docs/epics/epic-26-architecture-hardening/plans/plan-issue-5.md。
  Widget _buildFoliateEpubFooter(EpubPositionInfo info) {
```

- [ ] **Step 6：`reader_screen_test.dart` 刪除全部 4 個專測死路徑的 `testWidgets` 區塊**

**【審查修正 Minor #1】** 原計畫草稿只處理了 1 個測試，遺漏了緊接在它之前、同樣圍繞已移除的 `onCharacterCountReady` 回呼打造的另外 3 個測試（第 1324、1360、1399 行起）。這 4 個測試共用同一段（`// --- Epic 5 Issue 3：EPUB 頁碼顯示 + 跳頁 ---` 註解開始）連續區塊，一併刪除。

編輯 `app/test/screens/reader_screen_test.dart`，刪除以下整段（保留其後緊接著的 `testWidgets('PDF 頁尾行為不受本工單影響...`，該測試不變）：

```dart
  // --- Epic 5 Issue 3：EPUB 頁碼顯示 + 跳頁 ---

  testWidgets('EPUB reflowable 開書後，收到 onCharacterCountReady 回報時，頁尾正確顯示估算頁碼', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_epub_footer_test',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
    // 先回報非固定版面（頁尾只在流式 EPUB 顯示）。
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    // TODO(epic-20): FoliateReaderView 目前尚未提供
    // onCharacterCountReady callback，頁尾不會渲染——符合預期。
    // 當 FoliateReaderView 加入 onCharacterCountReady 後，
    // 取消註解並還原驗證邏輯。
    // epubView.onCharacterCountReady?.call(5000);
    // await tester.pump();

    // FoliateReaderView 無 onCharacterCountReady，頁尾不應出現。
    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  testWidgets('EPUB 收到 onLocatorChanged 的 progression 後，頁尾目前頁碼正確更新', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_epub_footer_progression',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    // TODO(epic-20): FoliateReaderView 目前無 onCharacterCountReady。
    // epubView.onCharacterCountReady?.call(5000); // 總頁數 10
    await tester.pump();
    epubView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"href":"/c1.xhtml"}',
        progression: 0.5,
      ),
    );
    await tester.pump();

    // 無 onCharacterCountReady，頁尾不出現，進度文字也不應存在。
    expect(find.text('5/10'), findsNothing);
  });

  testWidgets('EPUB 固定版面（FXL）開書後，即使收到 onCharacterCountReady 也不顯示頁尾', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_epub_fxl_no_footer',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: true,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    // TODO(epic-20): FoliateReaderView 目前無 onCharacterCountReady。
    // epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  testWidgets('版面設定（字型大小）變動後，EPUB 頁尾估算總頁數即時重新計算', (tester) async {
    // 【Task 4 修正】FoliateReaderView 無 onCharacterCountReady 回調
    //（EpubReaderView 獨有），改透過 FakeReaderPrefsManager 的
    // totalCharacterCountByBookId 在開書載入階段注入全書字元數（5000）。
    // ReaderScreen._initState 路徑：prefsManager.load(bookId) →
    // LoadedPrefs.totalCharacterCount → _totalCharacterCount，觸發 EPUB
    // 頁尾渲染（_buildBody 條件：_totalCharacterCount != null）。
    final footerPrefsManager = FakeReaderPrefsManager(
      totalCharacterCountByBookId: {'b_epub_footer_recalc': 5000},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_epub_footer_recalc',
          prefsManager: footerPrefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
    epubView.onPageRendered();
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    await tester.pump();

    // Issue 46：screenWidth=800/screenHeight=600（flutter_test 預設視窗
    // 尺寸）、其餘版面參數皆為預設值時，estimateCharsPerScreen() = 1598
    // （見 epub_page_estimator_test.dart 對應測試），totalPages =
    // ceil(5000/1598) = 4，progression 尚未收到任何回報（null）→ 第 1 頁。
    expect(find.text('1/4'), findsOneWidget);

    // 開啟版面設定，把字型大小從 16 調到 32（加倍），觸發真正的
    // _handlePrefsChanged → setState → rebuild 路徑（而非直接建構帶有
    // fontSize 覆寫值的 FakeReaderPrefsManager）。ReaderSettingsSheet 透過
    // onChanged 立即呼叫 ReaderScreen._handlePrefsChanged（見
    // reader_settings_sheet.dart _notifyChanged()），不需要關閉 Bottom
    // Sheet——底下的 ReaderScreen（含頁尾）仍在 widget tree 中並隨之
    // rebuild，find.text() 不受 Bottom Sheet 疊加在視覺上層影響。
    //
    // 【先前失敗原因，記錄供未來維護者知悉】原本此處省略了
    // onPageRendered()，導致 _state 停留在 loading、Stack 內的
    // CircularProgressIndicator（不定長動畫）持續繪製，任何後續
    // pumpAndSettle() 永遠不會收斂而逾時——這才是先前版本改用
    // FakeReaderPrefsManager 預先帶入 fontSize 覆寫值、完全繞開 Bottom
    // Sheet 互動的真正原因，並非 Bottom Sheet 本身在測試環境下無法渲染。
    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();
    // 每次點擊之間須 pump 一次，讓 ReaderSettingsSheet 以新的 _fontSize 值
    // 重新 build——否則 IconButton.onPressed 閉包捕捉到的仍是上一次 build
    // 當下的 clampedValue，16 次點擊會重複套用同一個遞增結果，而非累加。
    for (var i = 0; i < 16; i++) {
      await tester.tap(
        find.byKey(const Key('reader_settings_font_size_increment')),
      );
      await tester.pump();
    }

    // fontSize 倍率變成 2.0。epic-28-reader-settings-enhancements Issue 4
    // 修復後，ReaderSettingsSheet 只有「使用者實際觸碰過的欄位」才會送出
    // 具體數值——lineHeight 未被觸碰，因此正確維持 null，不再被具現化；
    // 邊界（margin）4 個欄位屬於 App 自身版面留白設定、與「書本原生樣式」
    // 無關，不在本次修復範圍內，_notifyChanged() 仍會送出目前 UI 顯示值
    // （32-16-24-24）。兩者皆與 estimateCharsPerScreen() 自身的獨立
    // fallback（lineHeight ?? 1.0 等，見 epub_page_estimator.dart）相同，
    // 頁碼估算數值不受影響。
    // fontSize=2.0、screenWidth=800/screenHeight=600 下
    // estimateCharsPerScreen() = 391（見 epub_page_estimator_test.dart
    // 對應測試），totalPages = ceil(5000/391) = 13。
    expect(find.text('1/13'), findsOneWidget);
  });

```

- [ ] **Step 7：`reader_screen_test.dart` 移除其餘 3 處指向已移除回呼的死註解**

**【審查修正 Minor #1】** 除了下方第一處，同一份檔案還有另外 2 處一模一樣的 `TODO(epic-20)` 死註解（分別位於「showHeader=true 且 showFooter=false」與「showHeader=false 且 showFooter=true」兩個測試內）——這兩個測試本身驗證的是頁首/頁尾顯示開關的合法功能，不在本 Issue 移除範圍內，只需清掉過時註解，測試其餘部分不變。

編輯 `app/test/screens/reader_screen_test.dart`，第一處：

```dart
    await tester.pump();
    // TODO(epic-20): FoliateReaderView 目前無 onCharacterCountReady。
    // epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsNothing);
    // 頁尾關閉不影響頁首（預設開啟）——驗證兩者互相獨立。
```

取代為：

```dart
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsNothing);
    // 頁尾關閉不影響頁首（預設開啟）——驗證兩者互相獨立。
```

第二處：

```dart
    await tester.pump();
    // TODO(epic-20): FoliateReaderView 目前無 onCharacterCountReady。
    // epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(
      find.byKey(const Key('reader_appbar_chapter_title')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  testWidgets('showHeader=false 且 showFooter=true 組合：頁首為靜態文字、頁尾顯示', (
```

取代為：

```dart
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('reader_appbar_chapter_title')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  testWidgets('showHeader=false 且 showFooter=true 組合：頁首為靜態文字、頁尾顯示', (
```

第三處：

```dart
    await tester.pump();
    // TODO(epic-20): FoliateReaderView 目前無 onCharacterCountReady。
    // epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(find.byKey(const Key('reader_appbar_static_title')), findsOneWidget);
    // 無 onCharacterCountReady，頁尾不出現。
    expect(find.byKey(const Key('reader_footer')), findsNothing);
```

取代為：

```dart
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('reader_appbar_static_title')), findsOneWidget);
    expect(find.byKey(const Key('reader_footer')), findsNothing);
```

- [ ] **Step 8：`reader_screen.dart` 更新 2 處指向已刪除 `_buildEpubFooter` 的過時佈局註解**

**【審查修正 Minor #2】** `Scaffold` 建構處與 `_buildBody()` 內各有一段解釋「為何頁尾切換會造成 body resize」的歷史說明，其中提到「僅 `EpubReaderView`＋`_buildEpubFooter()`（legacy reflowable 內容）路徑仍受此限制」——Step 1-2 已把 `_buildEpubFooter()` 整段刪除，這段說明所指的路徑已不存在，需一併更新避免誤導後續讀者。

編輯 `app/lib/screens/reader_screen.dart`，第一處（`Scaffold` 建構子註解）：

```dart
        // extendBodyBehindAppBar：搭配 _buildBody() 內的 Padding+SafeArea(top:
        // false) 改造（審查修正），讓 body 版面約束不受 AppBar 顯示/隱藏
        // 影響，AppBar 只是視覺疊加、不觸發 body 底下 PlatformView 的
        // resize。【最終審查修正】這只解決了 AppBar 這一半的問題——頁尾
        // （ReaderFooter／_buildEpubFooter，見 _buildBody() 內同樣受
        // _chromeVisible 控制的 in-flow Column 子項）顯示/隱藏仍會改變
        // body 實際配置高度，PlatformView 仍會 resize。PDF 目前僅是微幅
        // 重繪、可接受；但這代表本機制尚未完全解決 resize 問題，Issue 6
        // （EPUB 流式、Readium WebView）若要沿用同一套 _chromeVisible／
        // _buildBody() 基礎設施，必須先把頁尾也改為浮動疊加層（而非
        // in-flow），否則頁尾切換仍會觸發 WebView 整本重新分頁。
        // 【Issue 7 更新】流式 EPUB（FoliateReaderView）的頁尾已改為
        // _buildBody() 內的浮動疊加層（見下方新增區塊），上述 resize 問題對
        // 這條路徑已解決；僅 EpubReaderView＋_buildEpubFooter()（legacy
        // reflowable 內容）路徑仍受此限制。
        extendBodyBehindAppBar: true,
```

取代為：

```dart
        // extendBodyBehindAppBar：搭配 _buildBody() 內的 Padding+SafeArea(top:
        // false) 改造（審查修正），讓 body 版面約束不受 AppBar 顯示/隱藏
        // 影響，AppBar 只是視覺疊加、不觸發 body 底下 PlatformView 的
        // resize。流式 EPUB（FoliateReaderView）的進度/頁尾已改為浮動疊加層
        // 與 Modal Bottom Sheet（見 _buildFoliateProgressText()／
        // _openFoliateProgressSheet()），不佔用 body 版面空間，resize 問題
        // 已解決；PDF 頁尾為 PDF 專屬頁尾（見下方對應建構處），目前僅微幅
        // 重繪、可接受。舊有 in-flow 頁尾路徑（`_buildEpubFooter`）已於
        // epic-26-architecture-hardening Issue 5 移除。
        extendBodyBehindAppBar: true,
```

第二處（`_buildBody()` 內的 `Padding` 註解）：

```dart
      // 改用不受 AppBar 影響、只反映裝置實際安全區域（狀態列/瀏海）的
      // MediaQuery.viewPadding.top，SafeArea 本身關閉頂端判斷（top:
      // false），讓 AppBar 顯示/隱藏不再改變 body 高度。頁尾（下方
      // ReaderFooter／_buildEpubFooter）仍是 in-flow 子項，其顯示/隱藏
      // 仍會改變 body 實際高度——這是另一個尚未解決的 resize 來源，見上方
      // Scaffold 建構處的完整說明。
      padding: EdgeInsets.only(top: MediaQuery.of(context).viewPadding.top),
```

取代為：

```dart
      // 改用不受 AppBar 影響、只反映裝置實際安全區域（狀態列/瀏海）的
      // MediaQuery.viewPadding.top，SafeArea 本身關閉頂端判斷（top:
      // false），讓 AppBar 顯示/隱藏不再改變 body 高度。流式 EPUB 的進度/
      // 頁尾已改為浮動疊加層與 Modal Bottom Sheet，非 in-flow 子項，不影響
      // body 實際高度，見上方 Scaffold 建構處的完整說明。
      padding: EdgeInsets.only(top: MediaQuery.of(context).viewPadding.top),
```

- [ ] **Step 9：執行測試確認全數通過**

執行：
```bash
cd app && flutter test test/screens/reader_screen_test.dart
```
預期：全數 PASS（原本會涉及已刪除測試的案例數減少 4——1 個字型大小重算測試 + 3 個 `onCharacterCountReady` 測試）。

執行：`cd app && flutter analyze`
預期：`No issues found!`（`toc_bottom_sheet.dart` 仍匯入 `epub_page_estimator.dart`，該檔案尚未刪除，不會報錯）。

- [ ] **Step 10：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "refactor(epic-26): Issue 5 Task 2——移除 ReaderScreen 的 _buildEpubFooter 死路徑"
```

---

### Task 3：移除 `TocBottomSheet` 頁碼估算分支，刪除 `EpubPageEstimator`

**Files:**
- Modify: `app/lib/screens/toc_bottom_sheet.dart`
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/lib/reader/pdf_search_state.dart`
- Delete: `app/lib/reader/epub_page_estimator.dart`
- Delete: `app/test/reader/epub_page_estimator_test.dart`
- Write (full rewrite): `app/test/screens/toc_bottom_sheet_test.dart`
- Write (full rewrite): `app/test/screens/toc_bottom_sheet_pdf_test.dart`

**Interfaces:**
- Consumes: 無。
- Produces: `TocBottomSheet` 建構子不再有 `totalCharacterCountListenable`／`resolved` 參數；`EpubPageEstimator` 類別自本 Task 起不存在。

**背景**：`toc_bottom_sheet.dart` 是 `EpubPageEstimator` 最後一個消費端（Task 2 已移除 `reader_screen.dart` 的消費）。移除後才能安全刪除 `epub_page_estimator.dart` 本體。`_totalCharacterCountNotifier`／`_pdfDummyCharacterCountNotifier` 這兩個 `reader_screen.dart` 欄位存在的唯一目的是餵給 `TocBottomSheet.totalCharacterCountListenable`，本 Task 一併移除。

- [ ] **Step 1：`toc_bottom_sheet.dart` 移除 import 與類別文件註解**

編輯 `app/lib/screens/toc_bottom_sheet.dart`：

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../reader/book_format.dart';
import '../reader/book_toc_item.dart';
import '../reader/epub_page_estimator.dart';
import '../reader/pdf_toc_item.dart';
import '../reader/resolved_preferences.dart';
import '../reader/toc_entry.dart';
```

取代為：

```dart
import 'package:flutter/material.dart';

import '../reader/book_format.dart';
import '../reader/book_toc_item.dart';
import '../reader/pdf_toc_item.dart';
```

（`package:flutter/foundation.dart` 一併移除——本檔案原本用它取得 `ValueListenable`／`ValueChanged`，Step 2 移除 `totalCharacterCountListenable` 欄位後只剩 `onEntrySelected: ValueChanged<BookTocItem>` 用得到 `ValueChanged`，而 `ValueChanged` 已經由 `package:flutter/material.dart` 透過 `widgets.dart` 轉出匯出，不需要再獨立匯入 `foundation.dart`；保留會被 `flutter_lints` 的 `unused_import` 規則擋下。）

```dart
/// 泛化為消費 [BookTocItem]（epic-24 Issue 5）：EPUB 與 PDF 的目錄項目
/// 透過同一個介面傳入，`_buildEntryRow` 內部以 `is TocEntry`／
/// `is PdfTocItem` 分流頁碼顯示邏輯。
```

取代為：

```dart
/// 泛化為消費 [BookTocItem]（epic-24 Issue 5）：EPUB 與 PDF 的目錄項目
/// 透過同一個介面傳入，`_buildEntryRow` 內部以 `is PdfTocItem` 判斷是否
/// 顯示頁碼標籤——EPUB／TXT／MD（[TocEntry]）不顯示頁碼標籤
/// （epic-26-architecture-hardening Issue 5，見 plan-issue-5.md）。
```

- [ ] **Step 2：`toc_bottom_sheet.dart` 移除 `totalCharacterCountListenable`／`resolved` 欄位與建構子參數**

編輯 `app/lib/screens/toc_bottom_sheet.dart`：

```dart
  /// 全書字元數快取，`null` 時所有 EPUB 項目的頁碼顯示佔位符（`…`）；
  /// PDF 項目不使用此欄位（頁碼在解析大綱當下就已知，見
  /// `PdfReaderView._loadTableOfContents`），PDF 呼叫端可傳入任何值
  /// （建議 `ValueNotifier<int?>(null)`）。
  final ValueListenable<int?> totalCharacterCountListenable;

  /// 目前生效的版面參數，供換算「每螢幕可容納字元數」（僅 EPUB 項目使用，
  /// 見 [_buildEntryRow]）。
  final ResolvedPreferences resolved;

  final ValueChanged<BookTocItem> onEntrySelected;
```

取代為：

```dart
  final ValueChanged<BookTocItem> onEntrySelected;
```

```dart
    required this.currentEntry,
    required this.totalCharacterCountListenable,
    required this.resolved,
    required this.onEntrySelected,
```

取代為：

```dart
    required this.currentEntry,
    required this.onEntrySelected,
```

- [ ] **Step 3：`toc_bottom_sheet.dart` 簡化 `build()`，移除 `ValueListenableBuilder`**

編輯 `app/lib/screens/toc_bottom_sheet.dart`：

```dart
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ValueListenableBuilder<int?>(
        valueListenable: widget.totalCharacterCountListenable,
        builder: (context, totalCharacterCount, _) {
          if (widget.format == BookFormat.pdf) {
            return DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: '章節目錄'),
                      Tab(text: '縮圖'),
                      Tab(text: '搜尋'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildTocList(totalCharacterCount),
                        widget.thumbnailTabContent ??
                            const Center(child: Text('此功能將於後續版本提供')),
                        widget.searchTabContent ??
                            const Center(child: Text('此功能將於後續版本提供')),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return _buildTocList(totalCharacterCount);
        },
      ),
    );
  }
```

取代為：

```dart
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: widget.format == BookFormat.pdf
          ? DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: '章節目錄'),
                      Tab(text: '縮圖'),
                      Tab(text: '搜尋'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildTocList(),
                        widget.thumbnailTabContent ??
                            const Center(child: Text('此功能將於後續版本提供')),
                        widget.searchTabContent ??
                            const Center(child: Text('此功能將於後續版本提供')),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : _buildTocList(),
    );
  }
```

- [ ] **Step 4：`toc_bottom_sheet.dart` 簡化 `_buildTocList()` 與 `_buildEntryRow()`**

編輯 `app/lib/screens/toc_bottom_sheet.dart`：

```dart
  Widget _buildTocList(int? totalCharacterCount) {
```

取代為：

```dart
  Widget _buildTocList() {
```

```dart
        return _buildEntryRow(_visibleRows[index - 1], totalCharacterCount);
```

取代為：

```dart
        return _buildEntryRow(_visibleRows[index - 1]);
```

```dart
  Widget _buildEntryRow(_FlatTocRow row, int? totalCharacterCount) {
    final node = row.entry;
    final isCurrent = identical(node, widget.currentEntry);
    final String pageLabel;
    if (node is TocEntry) {
      final screenSize = MediaQuery.of(context).size;
      // 審查修正：totalCharacterCount 已就緒不代表這個節點本身就有可用的
      // progression——原生端兩層 fallback（locatorFromLink() 自帶的
      // totalProgression、比對 positions() 的近似值）都可能查無資料，此時
      // node.progression 仍是 null。EpubPageEstimator.estimateCurrentPage
      // 對 progression == null 的既有語意是回傳第 1 頁（給「尚未收到任何
      // onLocatorChanged 回報」這個完全不同的情境使用），若不在這裡額外判斷
      // node.progression == null，會讓「查無位置」的章節被誤植成「第 1
      // 頁」，比顯示佔位符更誤導使用者。
      pageLabel = (totalCharacterCount == null || node.progression == null)
          ? '…'
          : EpubPageEstimator.estimateCurrentPage(
              progression: node.progression,
              totalPages: EpubPageEstimator.estimateTotalPages(
                totalCharacterCount: totalCharacterCount,
                charsPerScreen: EpubPageEstimator.estimateCharsPerScreen(
                  screenWidth: screenSize.width,
                  screenHeight: screenSize.height,
                  fontSize: widget.resolved.fontSize,
                  lineHeight: widget.resolved.lineHeight,
                  paragraphSpacing: widget.resolved.paragraphSpacing,
                  letterSpacing: widget.resolved.letterSpacing,
                  marginTop: widget.resolved.marginTop,
                  marginBottom: widget.resolved.marginBottom,
                  marginLeft: widget.resolved.marginLeft,
                  marginRight: widget.resolved.marginRight,
                ),
              ),
            ).toString();
    } else if (node is PdfTocItem) {
      // PDF 大綱項目的目標頁碼在解析當下就已知（見
      // PdfReaderView._loadTableOfContents），不像 EPUB 需要背景估算，
      // 不使用 totalCharacterCount／EpubPageEstimator。
      pageLabel = node.pageIndex == null ? '…' : (node.pageIndex! + 1).toString();
    } else {
      pageLabel = '…';
    }

    return Padding(
      padding: EdgeInsets.only(left: row.depth * 16),
      child: ListTile(
        key: Key('toc_entry_${node.stableId}'),
        title: Text(
          node.title,
          style: isCurrent ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
        selected: isCurrent,
        onTap: () => widget.onEntrySelected(node),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(pageLabel, key: Key('toc_entry_page_${node.stableId}')),
            if (node.children.isNotEmpty)
              IconButton(
                key: Key('toc_entry_expand_${node.stableId}'),
                icon: Icon(
                  _expanded.contains(node) ? Icons.expand_less : Icons.expand_more,
                ),
                onPressed: () => _toggleExpanded(node),
              ),
          ],
        ),
      ),
    );
  }
```

取代為：

```dart
  /// [pageLabel] 為 `null` 時目錄項目不顯示頁碼標籤（epic-26-architecture-hardening
  /// Issue 5，選項 A：EPUB／TXT／MD 目錄項目不再嘗試估算頁碼，見
  /// plan-issue-5.md）——目前只有 [PdfTocItem] 在解析大綱當下就已知目標
  /// 頁碼，其餘 [BookTocItem] 實作一律不顯示頁碼標籤，僅顯示標題。
  Widget _buildEntryRow(_FlatTocRow row) {
    final node = row.entry;
    final isCurrent = identical(node, widget.currentEntry);
    final String? pageLabel = node is PdfTocItem
        ? (node.pageIndex == null ? '…' : (node.pageIndex! + 1).toString())
        : null;

    return Padding(
      padding: EdgeInsets.only(left: row.depth * 16),
      child: ListTile(
        key: Key('toc_entry_${node.stableId}'),
        title: Text(
          node.title,
          style: isCurrent ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
        selected: isCurrent,
        onTap: () => widget.onEntrySelected(node),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pageLabel != null)
              Text(pageLabel, key: Key('toc_entry_page_${node.stableId}')),
            if (node.children.isNotEmpty)
              IconButton(
                key: Key('toc_entry_expand_${node.stableId}'),
                icon: Icon(
                  _expanded.contains(node) ? Icons.expand_less : Icons.expand_more,
                ),
                onPressed: () => _toggleExpanded(node),
              ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 5：`reader_screen.dart` 移除 `_pdfDummyCharacterCountNotifier`／`_totalCharacterCountNotifier` 欄位**

編輯 `app/lib/screens/reader_screen.dart`：

```dart
class _ReaderScreenState extends State<ReaderScreen> with WidgetsBindingObserver {
  // PDF 目錄 Bottom Sheet 不需要字元數快取（頁碼在解析大綱時已知），
  // 但 TocBottomSheet 的建構子要求 ValueListenable<int?> 參數。
  // 共用同一個靜態實例，避免每次開啟都新建 ValueNotifier（Minor #3 修正）。
  static final _pdfDummyCharacterCountNotifier = ValueNotifier<int?>(null);

  // ── PDF 內文搜尋狀態（epic-24 Issue 6）──
```

取代為：

```dart
class _ReaderScreenState extends State<ReaderScreen> with WidgetsBindingObserver {
  // ── PDF 內文搜尋狀態（epic-24 Issue 6）──
```

```dart
  PdfSelectionInfo? _currentPdfSelection;
  String? _pendingPdfHighlightIdForSelection;
  // 供 TocBottomSheet 訂閱、在已開啟的目錄畫面即時反映全書字元數背景計算
  // 完成事件（spec.md「目錄模組」載入中狀態決策）——與 _totalCharacterCount
  // 這個驅動頁尾 rebuild 的既有欄位（Issue 3）刻意分開維護，避免耦合兩條
  // 目的不同的更新路徑（頁尾靠 setState 觸發整個 ReaderScreen rebuild；
  // 目錄靠 ValueNotifier 只更新已開啟的 Bottom Sheet 子樹，不驚動
  // ReaderScreen 本身）。
  final _totalCharacterCountNotifier = ValueNotifier<int?>(null);
  // 開書時讀到的既有位置記錄（若有），只在 initState 賦值一次，之後
```

取代為：

```dart
  PdfSelectionInfo? _currentPdfSelection;
  String? _pendingPdfHighlightIdForSelection;
  // 開書時讀到的既有位置記錄（若有），只在 initState 賦值一次，之後
```

```dart
        _initialPosition = loaded.readingPosition;
        _totalCharacterCountNotifier.value = loaded.totalCharacterCount;
        _resolved = widget.prefsManager.resolve(
```

取代為：

```dart
        _initialPosition = loaded.readingPosition;
        _resolved = widget.prefsManager.resolve(
```

```dart
    _volumeKeyChannel.setMethodCallHandler(null);
    _totalCharacterCountNotifier.dispose();
    _pdfSearchStateNotifier.dispose();
```

取代為：

```dart
    _volumeKeyChannel.setMethodCallHandler(null);
    _pdfSearchStateNotifier.dispose();
```

- [ ] **Step 6：`reader_screen.dart` 移除兩個 `TocBottomSheet(...)` 呼叫端的多餘參數**

編輯 `app/lib/screens/reader_screen.dart`：

```dart
        currentEntry: currentPath.isEmpty ? null : currentPath.last,
        totalCharacterCountListenable: _totalCharacterCountNotifier,
        resolved: _resolved!,
        onEntrySelected: (entry) {
          Navigator.of(context).pop();
          _jumpToEpubLocator((entry as TocEntry).locatorJson);
        },
```

取代為：

```dart
        currentEntry: currentPath.isEmpty ? null : currentPath.last,
        onEntrySelected: (entry) {
          Navigator.of(context).pop();
          _jumpToEpubLocator((entry as TocEntry).locatorJson);
        },
```

```dart
        currentEntry: currentPath.isEmpty ? null : currentPath.last,
        totalCharacterCountListenable: _pdfDummyCharacterCountNotifier,
        resolved: _resolved!,
        onEntrySelected: (entry) {
          Navigator.of(context).pop();
          final pageIndex = (entry as PdfTocItem).pageIndex;
```

取代為：

```dart
        currentEntry: currentPath.isEmpty ? null : currentPath.last,
        onEntrySelected: (entry) {
          Navigator.of(context).pop();
          final pageIndex = (entry as PdfTocItem).pageIndex;
```

- [ ] **Step 7：`pdf_search_state.dart` 修正指向已移除欄位的類別文件註解**

編輯 `app/lib/reader/pdf_search_state.dart`：

```dart
/// PDF 內文搜尋的目前狀態（epic-24-pdf-engine-rebuild Issue 6），由
/// `ReaderScreen` 擁有並透過 `ValueNotifier<PdfSearchState>` 廣播給
/// `PdfSearchPanel`（`ValueListenableBuilder`），讓已開啟的目錄 Bottom
/// Sheet 能在背景搜尋完成當下即時更新——比照 `TocBottomSheet` 既有的
/// `totalCharacterCountListenable` 解決同一類「外部非同步狀態更新已開啟
/// 的 Bottom Sheet」問題的既有模式。
```

取代為：

```dart
/// PDF 內文搜尋的目前狀態（epic-24-pdf-engine-rebuild Issue 6），由
/// `ReaderScreen` 擁有並透過 `ValueNotifier<PdfSearchState>` 廣播給
/// `PdfSearchPanel`（`ValueListenableBuilder`），讓已開啟的目錄 Bottom
/// Sheet 能在背景搜尋完成當下即時更新。
```

- [ ] **Step 8：刪除 `epub_page_estimator.dart` 與其測試**

```bash
git rm app/lib/reader/epub_page_estimator.dart app/test/reader/epub_page_estimator_test.dart
```

- [ ] **Step 9：完整重寫 `toc_bottom_sheet_test.dart`**

用 Write 工具，把 `app/test/screens/toc_bottom_sheet_test.dart` 整檔內容取代為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_toc_item.dart';
import 'package:elinkbook/reader/toc_entry.dart';
import 'package:elinkbook/screens/toc_bottom_sheet.dart';

void main() {
  final ch1 =
      const TocEntry(title: '第一章', locatorJson: 'l1', progression: 0.0);
  final ch2s1 =
      const TocEntry(title: '第一節', locatorJson: 'l2s1', progression: 0.35);
  final ch2s2 =
      const TocEntry(title: '第二節', locatorJson: 'l2s2', progression: 0.45);
  final ch2 = TocEntry(
    title: '第二章',
    locatorJson: 'l2',
    progression: 0.3,
    children: [ch2s1, ch2s2],
  );
  final ch3s1 =
      const TocEntry(title: '附錄一', locatorJson: 'l3s1', progression: 0.85);
  final ch3 = TocEntry(
    title: '第三章',
    locatorJson: 'l3',
    progression: 0.7,
    children: [ch3s1],
  );
  final entries = [ch1, ch2, ch3];

  testWidgets('多層級結構正確渲染，當前章節路徑預設展開、其餘章節預設收起',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: entries,
          initiallyExpandedEntries: {ch2, ch2s1},
          currentEntry: ch2s1,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(find.text('第一章'), findsOneWidget);
    expect(find.text('第二章'), findsOneWidget);
    expect(find.text('第一節'), findsOneWidget); // ch2 已預設展開
    expect(find.text('第二節'), findsOneWidget);
    expect(find.text('第三章'), findsOneWidget);
    expect(find.text('附錄一'),
        findsNothing); // ch3 未在目前路徑內，預設收起

    await tester
        .tap(find.byKey(Key('toc_entry_expand_${ch3.locatorJson}')));
    await tester.pump();

    expect(find.text('附錄一'), findsOneWidget);
  });

  testWidgets('當前章節項目標題以粗體高亮顯示，其餘項目不受影響', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: entries,
          initiallyExpandedEntries: {ch2, ch2s1},
          currentEntry: ch2s1,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    final currentTitle = tester.widget<Text>(find.text('第一節'));
    expect(currentTitle.style?.fontWeight, FontWeight.bold);

    final otherTitle = tester.widget<Text>(find.text('第一章'));
    expect(otherTitle.style?.fontWeight, isNot(FontWeight.bold));
  });

  testWidgets('點選項目標題觸發 onEntrySelected 並傳遞正確的 TocEntry',
      (tester) async {
    BookTocItem? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: entries,
          initiallyExpandedEntries: const {},
          currentEntry: null,
          onEntrySelected: (entry) => selected = entry,
        ),
      ),
    ));

    await tester.tap(find.text('第一章'));
    await tester.pump();

    expect(selected, ch1);
  });

  testWidgets('點擊展開/收起按鈕不會觸發 onEntrySelected（兩個熱區互不干擾）',
      (tester) async {
    var selectedCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: entries,
          initiallyExpandedEntries: const {},
          currentEntry: null,
          onEntrySelected: (_) => selectedCount++,
        ),
      ),
    ));

    await tester
        .tap(find.byKey(Key('toc_entry_expand_${ch2.locatorJson}')));
    await tester.pump();

    expect(selectedCount, 0);
    expect(find.text('第一節'), findsOneWidget,
        reason: '展開按鈕本身仍應正常運作');
  });

  testWidgets(
      'EPUB／TXT／MD 目錄項目不顯示頁碼標籤（僅標題），epic-26-architecture-hardening '
      'Issue 5：EpubPageEstimator／totalCharacterCount 估算管線已移除', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: entries,
          initiallyExpandedEntries: const {},
          currentEntry: null,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(
      find.byKey(Key('toc_entry_page_${ch1.locatorJson}')),
      findsNothing,
      reason: 'EPUB 目錄項目不再顯示頁碼標籤（Issue 5 選項 A：不重新設計字元數回報管道）',
    );
    expect(find.text('第一章'), findsOneWidget, reason: '標題仍正常顯示');
  });

  testWidgets('點擊右上角 X 取消按鈕後，Bottom Sheet 關閉（Navigator.pop 生效）',
      (tester) async {
    await _pumpModalSheet(tester, entries);

    expect(find.byType(TocBottomSheet), findsOneWidget);

    await tester.tap(find.byKey(const Key('toc_bottom_sheet_close_button')));
    await tester.pumpAndSettle();

    expect(find.byType(TocBottomSheet), findsNothing);
  });
}

Future<void> _pumpModalSheet(
  WidgetTester tester,
  List<TocEntry> entries,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => TocBottomSheet(
              entries: entries,
              initiallyExpandedEntries: const {},
              currentEntry: null,
              onEntrySelected: (_) {},
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
```

- [ ] **Step 10：完整重寫 `toc_bottom_sheet_pdf_test.dart`**

用 Write 工具，把 `app/test/screens/toc_bottom_sheet_pdf_test.dart` 整檔內容取代為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_format.dart';
import 'package:elinkbook/reader/pdf_toc_item.dart';
import 'package:elinkbook/screens/toc_bottom_sheet.dart';

void main() {
  final ch1 = const PdfTocItem(title: 'Part One', pageIndex: 0, stableId: 'p0');
  final ch1s1 =
      const PdfTocItem(title: 'Chapter 1', pageIndex: 0, stableId: 'p1');
  final ch1WithChild = PdfTocItem(
    title: 'Part One',
    pageIndex: 0,
    stableId: 'p0',
    children: [ch1s1],
  );
  final noDest =
      const PdfTocItem(title: '無目的地章節', pageIndex: null, stableId: 'pNull');

  testWidgets('PDF 節點頁碼顯示為 pageIndex+1（1-indexed），不使用 EpubPageEstimator',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: [ch1WithChild],
          initiallyExpandedEntries: {ch1WithChild},
          currentEntry: null,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(
      tester.widget<Text>(find.byKey(const Key('toc_entry_page_p0'))).data,
      '1',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('toc_entry_page_p1'))).data,
      '1',
    );
  });

  testWidgets('pageIndex 為 null 的 PDF 節點顯示佔位符', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: [noDest],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(
      tester.widget<Text>(find.byKey(const Key('toc_entry_page_pNull'))).data,
      '…',
    );
  });

  testWidgets('點選 PDF 項目觸發 onEntrySelected 並傳遞正確的 PdfTocItem',
      (tester) async {
    PdfTocItem? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: [ch1],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          onEntrySelected: (entry) => selected = entry as PdfTocItem,
        ),
      ),
    ));

    await tester.tap(find.text('Part One'));
    await tester.pump();

    expect(selected, ch1);
  });

  testWidgets('entries 為空清單時顯示提示文字，不拋出例外', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: const [],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(find.byKey(const Key('toc_bottom_sheet_empty_text')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PDF 格式下顯示三個分頁籤，且縮圖與搜尋分頁顯示佔位文字', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          format: BookFormat.pdf,
          entries: [ch1],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('章節目錄'), findsOneWidget);
    expect(find.text('縮圖'), findsOneWidget);
    expect(find.text('搜尋'), findsOneWidget);

    // 預設顯示章節目錄
    expect(find.byKey(const Key('toc_bottom_sheet_list')), findsOneWidget);

    // 切換到縮圖分頁
    await tester.tap(find.text('縮圖'));
    await tester.pumpAndSettle();
    expect(find.text('此功能將於後續版本提供'), findsOneWidget);

    // 切換到搜尋分頁
    await tester.tap(find.text('搜尋'));
    await tester.pumpAndSettle();
    expect(find.text('此功能將於後續版本提供'), findsOneWidget);
  });

  testWidgets('傳入 searchTabContent 時，切換到搜尋分頁顯示該內容而非預設佔位文字',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          format: BookFormat.pdf,
          entries: const [],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          onEntrySelected: (_) {},
          searchTabContent: const Text('SEARCH_PANEL_PLACEHOLDER'),
        ),
      ),
    ));

    await tester.tap(find.text('搜尋'));
    await tester.pumpAndSettle();

    expect(find.text('SEARCH_PANEL_PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('未傳入 searchTabContent 時，搜尋分頁維持既有佔位文字（零回歸）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          format: BookFormat.pdf,
          entries: const [],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    await tester.tap(find.text('搜尋'));
    await tester.pumpAndSettle();

    expect(find.text('此功能將於後續版本提供'), findsOneWidget, reason: '搜尋分頁維持既有佔位文字（縮圖分頁不在 widget tree 中）');
  });

  testWidgets('傳入 thumbnailTabContent 時，切換到縮圖分頁顯示該內容而非預設佔位文字',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          format: BookFormat.pdf,
          entries: const [],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          onEntrySelected: (_) {},
          thumbnailTabContent: const Text('THUMBNAIL_GRID_PLACEHOLDER'),
        ),
      ),
    ));

    await tester.tap(find.text('縮圖'));
    await tester.pumpAndSettle();

    expect(find.text('THUMBNAIL_GRID_PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('未傳入 thumbnailTabContent 時，縮圖分頁維持既有佔位文字（零回歸）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          format: BookFormat.pdf,
          entries: const [],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    await tester.tap(find.text('縮圖'));
    await tester.pumpAndSettle();

    expect(find.text('此功能將於後續版本提供'), findsOneWidget);
  });
}
```

- [ ] **Step 11：執行測試確認全數通過**

執行：
```bash
cd app && flutter test test/screens/toc_bottom_sheet_test.dart test/screens/toc_bottom_sheet_pdf_test.dart test/screens/reader_screen_test.dart
```
預期：全數 PASS（`toc_bottom_sheet_test.dart` 測試案例數從 7 個減為 6 個：移除 2 個佔位符測試、新增 1 個「不顯示頁碼標籤」測試）。

執行：`cd app && flutter analyze`
預期：`No issues found!`

- [ ] **Step 12：Commit**

```bash
git add app/lib/screens/toc_bottom_sheet.dart app/lib/screens/reader_screen.dart app/lib/reader/pdf_search_state.dart app/test/screens/toc_bottom_sheet_test.dart app/test/screens/toc_bottom_sheet_pdf_test.dart
git rm app/lib/reader/epub_page_estimator.dart app/test/reader/epub_page_estimator_test.dart 2>/dev/null || true
git commit -m "refactor(epic-26): Issue 5 Task 3——移除 TocBottomSheet EPUB 頁碼估算分支，刪除 EpubPageEstimator"
```

---

### Task 4：刪除 `EpubCharacterCountRepository`／`LoadedPrefs.totalCharacterCount`／`saveTotalCharacterCount`

**Files:**
- Delete: `app/lib/reader/epub_character_count_repository.dart`
- Delete: `app/test/support/fake_epub_character_count_repository.dart`
- Modify: `app/lib/reader/reader_prefs_manager.dart`
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/support/fake_reader_prefs_manager.dart`
- Modify: `app/test/reader/reader_prefs_manager_test.dart`
- Modify: `app/integration_test/custom_font_rendering_test.dart`
- Modify: `app/integration_test/epub_highlights_notes_test.dart`
- Modify: `app/integration_test/epub_toc_test.dart`
- Modify: `app/integration_test/foliate_highlights_notes_test.dart`
- Modify: `app/integration_test/fxl_bookmarks_test.dart`
- Modify: `app/integration_test/markdown_export_test.dart`
- Modify: `app/integration_test/notes_bookmark_test.dart`
- Modify: `app/integration_test/pdf_highlights_notes_test.dart`
- Modify: `app/integration_test/epub_pagination_test.dart`

**Interfaces:**
- Consumes: 無（Task 1-3 完成後，`totalCharacterCount` 已不再被 `Book`／`ReaderScreen`／`TocBottomSheet` 讀寫，本 Task 是最後一層：移除唯一還持有這個概念的 `LoadedPrefs`／`ReaderPrefsManager` 與其實作、以及儲存層 `EpubCharacterCountRepository`）。
- Produces: `ReaderPrefsManagerImpl` 建構子僅接受 2 個必要位置參數；`ReaderPrefsManager.saveTotalCharacterCount` 不存在。

- [ ] **Step 1：`reader_prefs_manager.dart` 移除 `LoadedPrefs.totalCharacterCount` 與 `saveTotalCharacterCount` 抽象方法**

編輯 `app/lib/reader/reader_prefs_manager.dart`：

```dart
class LoadedPrefs {
  final BookReaderPrefs bookPrefs;
  final GlobalReaderPrefs globalPrefs;
  final ReadingPosition readingPosition;
  final int? totalCharacterCount;

  const LoadedPrefs({
    required this.bookPrefs,
    required this.globalPrefs,
    this.readingPosition = const ReadingPosition(),
    this.totalCharacterCount,
  });
}
```

取代為：

```dart
class LoadedPrefs {
  final BookReaderPrefs bookPrefs;
  final GlobalReaderPrefs globalPrefs;
  final ReadingPosition readingPosition;

  const LoadedPrefs({
    required this.bookPrefs,
    required this.globalPrefs,
    this.readingPosition = const ReadingPosition(),
  });
}
```

```dart
  Future<void> saveReadingPosition(String bookId, ReadingPosition position);

  /// 寫入全書字元數快取（epic-5-toc-pagination Issue 3）。呼叫時機為原生端
  /// 背景計算完成、透過 EpubReaderView.onCharacterCountReady 回報之後，
  /// 只在該書尚無快取值時觸發一次（見 spec.md「執行緒與快取」）。
  Future<void> saveTotalCharacterCount(String bookId, int totalCharacterCount);

  /// 純同步合併（單書覆寫 `??` 全域預設／既存安全預設值），不觸發任何
```

取代為：

```dart
  Future<void> saveReadingPosition(String bookId, ReadingPosition position);

  /// 純同步合併（單書覆寫 `??` 全域預設／既存安全預設值），不觸發任何
```

- [ ] **Step 2：`reader_prefs_manager_impl.dart` 移除 `EpubCharacterCountRepository` 相關程式碼**

編輯 `app/lib/reader/reader_prefs_manager_impl.dart`：

```dart
import 'reader_prefs_manager.dart';
import 'reading_position.dart';
import 'epub_character_count_repository.dart';
import 'reading_position_repository.dart';
```

取代為：

```dart
import 'reader_prefs_manager.dart';
import 'reading_position.dart';
import 'reading_position_repository.dart';
```

```dart
class ReaderPrefsManagerImpl implements ReaderPrefsManager {
  final BookReaderPrefsRepository _sqliteRepository;
  final ReadingPositionRepository _positionRepository;
  final EpubCharacterCountRepository? _characterCountRepository;

  const ReaderPrefsManagerImpl(
    this._sqliteRepository,
    this._positionRepository, [
    this._characterCountRepository,
  ]);
```

取代為：

```dart
class ReaderPrefsManagerImpl implements ReaderPrefsManager {
  final BookReaderPrefsRepository _sqliteRepository;
  final ReadingPositionRepository _positionRepository;

  const ReaderPrefsManagerImpl(
    this._sqliteRepository,
    this._positionRepository,
  );
```

```dart
  @override
  Future<LoadedPrefs> load(String bookId) async {
    final results = await Future.wait([
      _sqliteRepository.load(bookId),
      loadGlobalPrefs(),
      _positionRepository.load(bookId),
      _characterCountRepository?.load(bookId) ?? Future.value(null),
    ]);
    return LoadedPrefs(
      bookPrefs: results[0] as BookReaderPrefs,
      globalPrefs: results[1] as GlobalReaderPrefs,
      readingPosition: results[2] as ReadingPosition,
      totalCharacterCount: results[3] as int?,
    );
  }
```

取代為：

```dart
  @override
  Future<LoadedPrefs> load(String bookId) async {
    final results = await Future.wait([
      _sqliteRepository.load(bookId),
      loadGlobalPrefs(),
      _positionRepository.load(bookId),
    ]);
    return LoadedPrefs(
      bookPrefs: results[0] as BookReaderPrefs,
      globalPrefs: results[1] as GlobalReaderPrefs,
      readingPosition: results[2] as ReadingPosition,
    );
  }
```

```dart
  @override
  Future<void> saveReadingPosition(String bookId, ReadingPosition position) =>
      _positionRepository.save(bookId, position);

  @override
  Future<void> saveTotalCharacterCount(String bookId, int totalCharacterCount) =>
      _characterCountRepository?.save(bookId, totalCharacterCount) ??
      Future.value();

  @override
  ResolvedPreferences resolve(
```

取代為：

```dart
  @override
  Future<void> saveReadingPosition(String bookId, ReadingPosition position) =>
      _positionRepository.save(bookId, position);

  @override
  ResolvedPreferences resolve(
```

- [ ] **Step 3：`main.dart` 移除 `EpubCharacterCountRepository` 組裝**

編輯 `app/lib/main.dart`：

```dart
import 'reader/epub_character_count_repository.dart';
```

刪除這一行（找到該 import 所在位置刪除即可，不需替換）。

```dart
  final prefsManager = ReaderPrefsManagerImpl(
    prefsRepository,
    ReadingPositionRepository(repository.database),
    EpubCharacterCountRepository(repository.database),
  );
```

取代為：

```dart
  final prefsManager = ReaderPrefsManagerImpl(
    prefsRepository,
    ReadingPositionRepository(repository.database),
  );
```

- [ ] **Step 4：`reader_screen.dart` 移除 `_handlePrefsChanged` 內對已刪除欄位的引用**

編輯 `app/lib/screens/reader_screen.dart`：

```dart
        final newLoaded = LoadedPrefs(
          bookPrefs: prefs,
          globalPrefs: loaded.globalPrefs,
          readingPosition: loaded.readingPosition,
          totalCharacterCount: loaded.totalCharacterCount,
        );
```

取代為：

```dart
        final newLoaded = LoadedPrefs(
          bookPrefs: prefs,
          globalPrefs: loaded.globalPrefs,
          readingPosition: loaded.readingPosition,
        );
```

- [ ] **Step 5：完整重寫 `fake_reader_prefs_manager.dart`**

用 Write 工具，把 `app/test/support/fake_reader_prefs_manager.dart` 整檔內容取代為：

```dart
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/reader_prefs_manager.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position.dart';
import 'package:elinkbook/reader/resolved_preferences.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'fake_book_reader_prefs_repository.dart';
import 'fake_reading_position_repository.dart';

/// 供 `reader_screen_test.dart` 使用的假 [ReaderPrefsManager]：`load`／
/// `save*` 皆為純記憶體內操作；`resolve` 直接委派給
/// [ReaderPrefsManagerImpl.resolve]（純函式、無 I/O，不需要另外假造）以
/// 確保測試驗證的合併邏輯與正式實作完全一致。
class FakeReaderPrefsManager implements ReaderPrefsManager {
  final Map<String, BookReaderPrefs> bookPrefsByBookId;
  final Map<String, ReadingPosition> readingPositionByBookId;
  GlobalReaderPrefs globalPrefs;
  final List<String> savedBookPrefsCalls = [];
  final List<GlobalReaderPrefs> savedGlobalPrefsCalls = [];
  final List<MapEntry<String, ReadingPosition>> savedReadingPositionCalls = [];

  FakeReaderPrefsManager({
    Map<String, BookReaderPrefs>? bookPrefsByBookId,
    Map<String, ReadingPosition>? readingPositionByBookId,
    this.globalPrefs = const GlobalReaderPrefs.initial(),
  })  : bookPrefsByBookId = bookPrefsByBookId ?? {},
        readingPositionByBookId = readingPositionByBookId ?? {};

  /// 預設 BookReaderPrefs：showHeader/showFooter 為 true，避免多數測試
  /// 需要逐一手動傳入（Issue 23 預設值從 true 改為 false 後的測試適配）。
  static const _defaultBookPrefs = BookReaderPrefs(
    showHeader: true,
    showFooter: true,
  );

  final _delegate = ReaderPrefsManagerImpl(
    FakeBookReaderPrefsRepository(),
    FakeReadingPositionRepository(),
  );

  @override
  Future<LoadedPrefs> load(String bookId) async {
    return LoadedPrefs(
      bookPrefs: bookPrefsByBookId[bookId] ?? _defaultBookPrefs,
      globalPrefs: globalPrefs,
      readingPosition:
          readingPositionByBookId[bookId] ?? const ReadingPosition(),
    );
  }

  @override
  Future<GlobalReaderPrefs> loadGlobalPrefs() async => globalPrefs;

  @override
  Future<void> saveBookPrefs(String bookId, BookReaderPrefs prefs) async {
    bookPrefsByBookId[bookId] = prefs;
    savedBookPrefsCalls.add(bookId);
  }

  @override
  Future<void> saveGlobalPrefs(GlobalReaderPrefs prefs) async {
    globalPrefs = prefs;
    savedGlobalPrefsCalls.add(prefs);
  }

  @override
  Future<void> saveReadingPosition(String bookId, ReadingPosition position) async {
    readingPositionByBookId[bookId] = position;
    savedReadingPositionCalls.add(MapEntry(bookId, position));
  }

  @override
  ResolvedPreferences resolve(
    LoadedPrefs loaded, {
    WritingMode? autoDetectedWritingMode,
  }) =>
      _delegate.resolve(loaded, autoDetectedWritingMode: autoDetectedWritingMode);
}
```

- [ ] **Step 6：`reader_prefs_manager_test.dart` 移除 import 與 2 個 `EpubCharacterCountRepository` 專屬測試**

編輯 `app/test/reader/reader_prefs_manager_test.dart`：

```dart
import 'package:elinkbook/reader/reading_position.dart';
import 'package:elinkbook/reader/epub_character_count_repository.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
```

取代為：

```dart
import 'package:elinkbook/reader/reading_position.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
```

刪除以下整段（緊接在其前的 `test('saveReadingPosition 寫入後...` 測試的收尾 `});` 之後，group 收尾的 `});` `}` 之前）：

```dart
    test('EpubCharacterCountRepository 有註冊時，load 回傳 totalCharacterCount，saveTotalCharacterCount 寫入後可讀回',
        () async {
      final managerWithCounting = ReaderPrefsManagerImpl(
        BookReaderPrefsRepository(libraryRepository.database),
        ReadingPositionRepository(libraryRepository.database),
        EpubCharacterCountRepository(libraryRepository.database),
      );

      final beforeSave = await managerWithCounting.load('b1');
      expect(beforeSave.totalCharacterCount, isNull);

      await managerWithCounting.saveTotalCharacterCount('b1', 12345);
      final afterSave = await managerWithCounting.load('b1');
      expect(afterSave.totalCharacterCount, 12345);
    });

    test('未提供 EpubCharacterCountRepository（第 3 個建構參數省略）時，totalCharacterCount 一律為 null 且 saveTotalCharacterCount 安全無操作',
        () async {
      // manager 沿用既有（2 參數）setUp 建立的實例，驗證省略第 3 個建構
      // 參數時仍可安全編譯與執行（見 Global Constraints）。
      await manager.saveTotalCharacterCount('b1', 999); // 不應拋出例外
      final loaded = await manager.load('b1');
      expect(loaded.totalCharacterCount, isNull);
    });
```

- [ ] **Step 7：刪除 `epub_character_count_repository.dart` 與其 fake**

```bash
git rm app/lib/reader/epub_character_count_repository.dart app/test/support/fake_epub_character_count_repository.dart
```

- [ ] **Step 8：更新 8 個「機械式」`integration_test` 檔案——移除 import 與建構參數**

以下 8 個檔案皆做**相同兩處編輯**：(a) 刪除 `import 'package:elinkbook/reader/epub_character_count_repository.dart';` 這一行；(b) 從 `ReaderPrefsManagerImpl(...)` 呼叫中刪除 `EpubCharacterCountRepository(...)` 那一行參數。逐檔案確切內容：

**`app/integration_test/custom_font_rendering_test.dart`**：

```dart
    final prefsManager = ReaderPrefsManagerImpl(
      prefsRepository,
      ReadingPositionRepository(repository.database),
      EpubCharacterCountRepository(repository.database),
    );
```

取代為：

```dart
    final prefsManager = ReaderPrefsManagerImpl(
      prefsRepository,
      ReadingPositionRepository(repository.database),
    );
```

**`app/integration_test/epub_highlights_notes_test.dart`、`app/integration_test/epub_toc_test.dart`、`app/integration_test/foliate_highlights_notes_test.dart`、`app/integration_test/fxl_bookmarks_test.dart`、`app/integration_test/markdown_export_test.dart`、`app/integration_test/notes_bookmark_test.dart`、`app/integration_test/pdf_highlights_notes_test.dart`**（此 7 個檔案的建構呼叫逐字相同）：

```dart
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
      EpubCharacterCountRepository(libraryRepository.database),
    );
```

取代為：

```dart
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );
```

（每個檔案各自的 `import 'package:elinkbook/reader/epub_character_count_repository.dart';` 一併刪除。若 Edit 工具的 old_string 因該檔案內只出現一次而不需要 `replace_all`，逐檔案個別執行即可；8 個檔案需各自獨立編輯 8 次，不可用單一跨檔案指令。）

- [ ] **Step 9：完整重寫 `epub_pagination_test.dart`**

這個檔案深度依賴已移除的字元數快取行為敘述，需要比其餘 8 個檔案更多的內容調整（不只是移除建構參數）。

**【審查修正】原計畫草稿誤植頁尾架構**：草稿版本假設 EPUB 頁尾在開書後會自動以 in-flow 元件（`Key('reader_footer')`）出現，這其實是已在 Task 2 刪除的 Readium 遺留死路徑（`_buildEpubFooter`）的行為。現行流式 EPUB 架構（`epic-18-reader-device-qa` Issue 7）是：畫面固定顯示一個小型浮動進度文字 `Key('reader_foliate_progress_text')`（內容格式 `'$currentPage/$totalPages'`，見 `reader_screen.dart:2521-2535` 的 `_buildFoliateProgressText()`）；含跳頁輸入框的完整 `ReaderFooter`（`Key('reader_footer')`／`Key('reader_footer_progress_text')`／`Key('reader_footer_jump_input')`）**只在**使用者點擊浮動按鈕 `Key('reader_foliate_progress_button')` 後才以 Modal Bottom Sheet 形式出現（見 `reader_screen.dart:2546-2554` 的 `_openFoliateProgressSheet()`，內部呼叫 `_buildFoliateEpubFooter()`）。以下內容已改用正確架構。

用 Write 工具，把 `app/integration_test/epub_pagination_test.dart` 整檔內容取代為：

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
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/reader_screen.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// 持續 pump，直到載入指示器消失或逾時，比照
/// integration_test/reading_position_test.dart 的既有 helper。
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

/// 持續 pump，直到浮動進度文字（reader_foliate_progress_text）出現或逾時——
/// foliate-js 完成首次 relocate 回報前不會顯示，與「載入指示器消失」是兩個
/// 獨立的時間點。這個小型文字（`_buildFoliateProgressText()`）與含跳頁
/// 輸入框的完整 `ReaderFooter`（`Key('reader_footer')`）不同——後者只在
/// 點擊 `reader_foliate_progress_button` 開啟 Bottom Sheet 後才存在，見
/// `reader_screen.dart` 的 `_openFoliateProgressSheet()`。
Future<void> _pumpUntilProgressVisible(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (find.byKey(const Key('reader_foliate_progress_text')).evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：浮動進度文字未出現');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('EPUB 開書後浮動進度文字顯示正確格式（epic-26 Issue 5：不再依賴全書字元數快取）',
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

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_long_vertical.epub', 'epub_pagination_integration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_epub_pagination',
      title: 'EPUB 分頁估算測試書 1',
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
          bookId: 'b_epub_pagination',
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    await _pumpUntilProgressVisible(tester);
    final progressTextFinder = find.byKey(const Key('reader_foliate_progress_text'));
    final progressText = (tester.widget<Text>(progressTextFinder)).data ?? '';
    expect(progressText, matches(RegExp(r'^\d+/\d+$')),
        reason: '浮動進度文字應顯示「currentPage/totalPages」格式');
  });

  testWidgets('點擊浮動進度按鈕開啟頁尾 Bottom Sheet，輸入框跳頁後畫面確實跳轉到目標頁附近',
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

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'epub_pagination_jump_integration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    // 【審查修正】同上，先插入書籍列。
    await libraryRepository.insertBook(Book(
      id: 'b_epub_pagination_jump',
      title: 'EPUB 分頁估算測試書 2',
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
          bookId: 'b_epub_pagination_jump',
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilProgressVisible(tester);

    // 【審查修正】含跳頁輸入框的 ReaderFooter 只存在於 Bottom Sheet 內，
    // 開書後不會自動出現，須先點擊浮動按鈕開啟。
    await tester.tap(find.byKey(const Key('reader_foliate_progress_button')));
    await tester.pumpAndSettle();

    final footerProgressTextFinder =
        find.byKey(const Key('reader_footer_progress_text'));
    expect(footerProgressTextFinder, findsOneWidget);
    final totalPagesText =
        (tester.widget<Text>(footerProgressTextFinder)).data ?? '';
    final match = RegExp(r'第 \d+/(\d+) 頁').firstMatch(totalPagesText);
    expect(match, isNotNull);
    final totalPages = int.parse(match!.group(1)!);
    final targetPage = (totalPages / 2).ceil().clamp(1, totalPages);

    await tester.enterText(
        find.byKey(const Key('reader_footer_jump_input')), '$targetPage');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final progressText =
        (tester.widget<Text>(footerProgressTextFinder)).data ?? '';
    expect(progressText, contains('第 $targetPage/$totalPages 頁'),
        reason: '輸入框跳頁後 Bottom Sheet 內的頁尾應更新為目標頁');
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
}
```

- [ ] **Step 10：執行測試確認全數通過**

執行：
```bash
cd app && flutter test test/reader/reader_prefs_manager_test.dart test/screens/reader_screen_test.dart
```
預期：全數 PASS。

執行：`cd app && flutter analyze`
預期：`No issues found!`（此步驟會一併驗證 `app/integration_test/` 下所有已編輯檔案能正確編譯——`integration_test` 目錄本身不會被 `flutter test` 執行，但會被 `flutter analyze` 檢查，見 Global Constraints）。

- [ ] **Step 11：Commit**

```bash
git add app/lib/reader/reader_prefs_manager.dart app/lib/reader/reader_prefs_manager_impl.dart app/lib/main.dart app/lib/screens/reader_screen.dart app/test/support/fake_reader_prefs_manager.dart app/test/reader/reader_prefs_manager_test.dart app/integration_test/custom_font_rendering_test.dart app/integration_test/epub_highlights_notes_test.dart app/integration_test/epub_toc_test.dart app/integration_test/foliate_highlights_notes_test.dart app/integration_test/fxl_bookmarks_test.dart app/integration_test/markdown_export_test.dart app/integration_test/notes_bookmark_test.dart app/integration_test/pdf_highlights_notes_test.dart app/integration_test/epub_pagination_test.dart
git rm app/lib/reader/epub_character_count_repository.dart app/test/support/fake_epub_character_count_repository.dart 2>/dev/null || true
git commit -m "refactor(epic-26): Issue 5 Task 4——刪除 EpubCharacterCountRepository，totalCharacterCount 管線正式除役"
```

---

### Task 5：全專案最終驗證

**Files:** 無新增/修改（純驗證）。

- [ ] **Step 1：全專案 `flutter analyze`**

執行：`cd app && flutter analyze`
預期：`No issues found!`

- [ ] **Step 2：全專案 `flutter test`**

執行：`cd app && flutter test`
預期：全數 PASS，零回歸。

- [ ] **Step 3：確認 `totalCharacterCount` 只剩 schema 層與遷移測試的原生 SQL 引用**

執行：
```bash
cd app && grep -rn "totalCharacterCount" lib/ test/ integration_test/ | grep -v "totalCharacterCount INTEGER\|columns: \['totalCharacterCount'\]\|row\['totalCharacterCount'\]\|rowBeforeWrite\['totalCharacterCount'\]\|rowAfterWrite\['totalCharacterCount'\]\|{'totalCharacterCount'"
```
預期：無輸出（代表所有殘留引用都只是 schema 定義或 Task 1 Step 6 改寫後的原生 SQL 查詢，沒有任何 `Book`/`LoadedPrefs`/`EpubPageEstimator`/`EpubCharacterCountRepository` 層級的殘留引用）。

- [ ] **Step 4：確認驗收標準逐項達成**

對照 `docs/epics/epic-26-architecture-hardening/issues.md` Issue 5 的驗收標準逐項核對：
- `EpubPageEstimator`、`EpubCharacterCountRepository`、`Book.totalCharacterCount` 相關程式碼（含死路徑 `_buildEpubFooter()`、TOC 頁碼估算分支）全數移除 ✓（Task 1-4）。
- `Book.totalCharacterCount` 欄位處理方式已定案並記錄：**維持欄位存在但停止讀寫**（非 `DROP COLUMN`，理由見 Global Constraints）✓（Task 1 Step 2）。
- `flutter analyze` 乾淨、`flutter test` 全數通過、零回歸 ✓（Step 1-2）。

不需要額外 commit——此 Task 純粹是驗證，若 Step 1-3 有任何一項失敗，回頭修正對應 Task 後重新執行本 Task。
