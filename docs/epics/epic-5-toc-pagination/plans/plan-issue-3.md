# Epic 5 Issue 3：EPUB 頁碼顯示 + 跳頁（含全書字元數背景計算基礎設施）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 為流式 EPUB 建立模擬分頁能力（估算頁碼／總頁數／跳頁），複用 Issue 1 的 `ReaderFooter` 元件，並在原生端背景執行緒一次性計算全書字元數、快取於 `books` 表，供 Dart 端依目前生效的版面參數換算「每螢幕可容納字元數」與估計總頁數。

**Architecture:** 原生端（`EpubReaderView.kt`）新增一個純 Kotlin 字元計算模組（`EpubCharacterCounter`，可 JUnit 測試）與一段背景協程（`Dispatchers.IO`）走訪 `Publication.readingOrder` 加總全書字元數，計算結果透過既有 `MethodChannel` 模式一次性回報給 Dart，並快取到 `books.totalCharacterCount` 欄位（比照 Issue 2 的 schema migration 慣例）。Dart 端新增一個純 Dart 估算模組（`EpubPageEstimator`，可 unit test）依 `ResolvedPreferences` 的版面參數與快取字元數換算總頁數／目前頁碼，並反向換算跳頁用的全書進度比例。跳頁動作透過新的 `jumpToProgression` method channel 指令，原生端沿用 Readium 既有的 `Publication.positions()` API（design.md 決策 #5 已確認存在）挑選最接近的 Locator 後呼叫 `Navigator.go()`——刻意不另外發明字元偏移量對應 Locator 的複雜機制。`ReaderScreen` 把估算出的頁碼／總頁數接上 Issue 1 已建立、格式無關的 `ReaderFooter`，不修改該元件本身。

**Tech Stack:** Flutter/Dart（`app/lib/`）、Kotlin + Readium `kotlin-toolkit:3.3.0`（`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/`）、Kotlin Coroutines（`Dispatchers.IO`）、sqflite（SQLite）、JUnit（原生純邏輯單元測試）、`flutter_test`／`integration_test`。

## Global Constraints

- 全書字元數計算須於原生端背景執行緒（`Dispatchers.IO`）進行，不得阻塞主執行緒（spec.md「執行緒與快取」）。
- 計算結果快取於 `books.totalCharacterCount`，僅在該書首次開啟（欄位為 `null`）時觸發一次背景計算，之後每次開書直接讀取快取，不重新走訪全書（spec.md「執行緒與快取」）。
- 目前頁碼由 Readium 提供的全書閱讀進度比例（`Locator.locations.totalProgression`）換算而得，估計總頁數與目前頁碼須在任一版面參數（字體大小／行距／段落間距／邊距／排版方向）變動時立即重新計算（spec.md「分頁估算模組」）。
- 頁碼為模擬估算值，非逐頁精確值——不追求與 Readium 實際渲染逐頁對齊（spec.md「分頁估算模組」）。
- `ReaderFooter`（`app/lib/screens/reader_footer.dart`）維持 Issue 1 鎖定的格式無關介面契約（`currentPage`／`totalPages`／`onPageChanged` 三個屬性），本工單不得修改此檔案。
- Schema migration 一律使用累加式 `if (oldVersion < N)`，不得使用互斥 `if/else if`（比照 Issue 2/3 既有原則，見 issues.md 審查修正紀錄）。
- 跨 `State` 私有邊界呼叫一律透過強型別 static helper（比照 `PdfReaderView.jumpToPage` 既有模式），不使用 `as dynamic`。
- 本工單不修改 PDF 讀取畫面既有行為（`_pdfPageInfo`／`PdfReaderView` 相關程式碼維持原樣）。
- 每個 Task 完成後 `flutter analyze`（Dart 變更）或對應 Kotlin 編譯需保持乾淨，既有測試（`flutter test`、既有 JUnit）不可回歸。

---

### Task 1: `EpubCharacterCounter`（原生端純 Kotlin 字元計算邏輯）

**Files:**
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubCharacterCounter.kt`
- Test: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/EpubCharacterCounterTest.kt`

**Interfaces:**
- Produces: `EpubCharacterCounter.countCharacters(html: String): Int`——供 Task 5 的 `EpubReaderView.kt` 對每個 `readingOrder` resource 的原始內容呼叫，加總得到全書字元數。

- [ ] **Step 1: 寫失敗測試**

```kotlin
package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Test

class EpubCharacterCounterTest {

    @Test
    fun `去除標籤後計算純文字字元數`() {
        val html = "<p>Hello world</p>"
        assertEquals(11, EpubCharacterCounter.countCharacters(html))
    }

    @Test
    fun `HTML entity 概略以空白取代並收斂連續空白`() {
        val html = "<p>Tom &amp; Jerry</p>"
        assertEquals(9, EpubCharacterCounter.countCharacters(html))
    }

    @Test
    fun `多層巢狀與自我閉合標籤皆被去除，只留下標籤間文字`() {
        val html = "<div><span>你好</span><br/>世界</div>"
        assertEquals(5, EpubCharacterCounter.countCharacters(html))
    }

    @Test
    fun `文字中的換行與多重空白收斂為單一空白`() {
        val html = "<p>Line1\n\n  Line2</p>"
        assertEquals(11, EpubCharacterCounter.countCharacters(html))
    }

    @Test
    fun `空字串回傳 0`() {
        assertEquals(0, EpubCharacterCounter.countCharacters(""))
    }
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run（於 `app/android` 目錄）：`./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.EpubCharacterCounterTest"`
Expected: FAIL（`EpubCharacterCounter` 尚未定義，編譯錯誤）。若 `gradlew`/`gradlew.bat` 不存在（`.gitignore` 排除的產生檔），先於 `app/` 執行 `flutter build apk --debug` 讓 Flutter 產生 wrapper。

- [ ] **Step 3: 撰寫最小實作**

```kotlin
package cc.ugotit.elinkbook

/**
 * EPUB 全書字元數估算（epic-5-toc-pagination Issue 3，spec.md「分頁估算
 * 模組」）用到的純文字字元計算邏輯：從單一 resource 的 HTML/XHTML 原始
 * 內容中去除標籤與多餘空白後計算純文字字元數。純 Kotlin、不依賴
 * Android／Readium 執行環境，可在 JVM 單元測試（app/src/test）直接以
 * 固定字串驗證，比照 EpubFxlScaler 的既有先例。真正走訪
 * `Publication.readingOrder` 取得每個 resource 內容的邏輯留在
 * EpubReaderView.kt（需要 Readium 的 suspend Resource API，無法脫離
 * 真機/模擬器環境以純 JUnit 驗證，見該檔案的說明）。
 */
object EpubCharacterCounter {

    /**
     * 去除所有 HTML/XHTML 標籤（含跨行的標籤）與 HTML entity（概略以單一
     * 空白取代，不需要精確解碼實際字元——此為粗略估算用途，非逐字精確
     * 渲染），再把連續空白（含換行）收斂為單一空白後計算字元數。
     */
    fun countCharacters(html: String): Int {
        val withoutTags = html.replace(Regex("<[^>]*>", RegexOption.DOT_MATCHES_ALL), " ")
        val withoutEntities = withoutTags.replace(Regex("&[a-zA-Z#0-9]+;"), " ")
        val collapsed = withoutEntities.replace(Regex("\\s+"), " ").trim()
        return collapsed.length
    }
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.EpubCharacterCounterTest"`
Expected: PASS（5 個測試皆綠燈）。

- [ ] **Step 5: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubCharacterCounter.kt app/android/app/src/test/kotlin/cc/ugotit/elinkbook/EpubCharacterCounterTest.kt
git commit -m "feat(epic-5-issue3): 新增 EpubCharacterCounter 純 Kotlin 字元計算模組"
```

---

### Task 2: `EpubPageEstimator`（Dart 端純函式頁碼估算邏輯）

**Files:**
- Create: `app/lib/reader/epub_page_estimator.dart`
- Test: `app/test/reader/epub_page_estimator_test.dart`

**Interfaces:**
- Produces:
  - `EpubPageEstimator.estimateCharsPerScreen({double? fontSize, double? lineHeight, double? paragraphSpacing, double? pageMargins}) -> int`
  - `EpubPageEstimator.estimateTotalPages({required int totalCharacterCount, required int charsPerScreen}) -> int`
  - `EpubPageEstimator.estimateCurrentPage({required double? progression, required int totalPages}) -> int`
  - `EpubPageEstimator.estimateProgression({required int targetPage, required int totalPages}) -> double`
- Consumes：無（純函式，無外部相依）。供 Task 7 的 `ReaderScreen` 呼叫。

- [ ] **Step 1: 寫失敗測試**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/epub_page_estimator.dart';

void main() {
  group('estimateCharsPerScreen', () {
    test('全部參數皆為 null 時，採用預設版面參數，回傳基準值', () {
      expect(EpubPageEstimator.estimateCharsPerScreen(), 500);
    });

    test('fontSize 加倍時，每螢幕可容納字元數依平方比例縮減', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(fontSize: 2.0),
        125,
      );
    });

    test('lineHeight 加倍時，每螢幕可容納字元數依線性比例縮減', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(lineHeight: 3.0),
        250,
      );
    });

    test('pageMargins 加倍時，可容納字元數依較低權重縮減', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(pageMargins: 2.0),
        417,
      );
    });

    test('極端字體大小時，結果被箝制在下限 50，不會估算出荒謬的總頁數', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(fontSize: 10.0),
        50,
      );
    });
  });

  group('estimateTotalPages', () {
    test('字元數恰為整數倍時，總頁數為該倍數', () {
      expect(
        EpubPageEstimator.estimateTotalPages(
          totalCharacterCount: 1000,
          charsPerScreen: 500,
        ),
        2,
      );
    });

    test('字元數有餘數時，無條件進位', () {
      expect(
        EpubPageEstimator.estimateTotalPages(
          totalCharacterCount: 1001,
          charsPerScreen: 500,
        ),
        3,
      );
    });

    test('全書字元數為 0 時，至少回傳 1 頁', () {
      expect(
        EpubPageEstimator.estimateTotalPages(
          totalCharacterCount: 0,
          charsPerScreen: 500,
        ),
        1,
      );
    });
  });

  group('estimateCurrentPage', () {
    test('progression 為 null 時，回傳第 1 頁', () {
      expect(
        EpubPageEstimator.estimateCurrentPage(progression: null, totalPages: 10),
        1,
      );
    });

    test('progression 為 0.0 時，箝制在第 1 頁（不是第 0 頁）', () {
      expect(
        EpubPageEstimator.estimateCurrentPage(progression: 0.0, totalPages: 10),
        1,
      );
    });

    test('progression 為 0.5 時，回傳中間頁碼', () {
      expect(
        EpubPageEstimator.estimateCurrentPage(progression: 0.5, totalPages: 10),
        5,
      );
    });

    test('progression 為 1.0 時，回傳最後一頁', () {
      expect(
        EpubPageEstimator.estimateCurrentPage(progression: 1.0, totalPages: 10),
        10,
      );
    });
  });

  group('estimateProgression', () {
    test('目標頁碼換算成該頁區間中點的全書進度比例', () {
      expect(
        EpubPageEstimator.estimateProgression(targetPage: 5, totalPages: 10),
        0.45,
      );
    });

    test('第 1 頁換算出的比例仍在 [0,1] 範圍內', () {
      expect(
        EpubPageEstimator.estimateProgression(targetPage: 1, totalPages: 10),
        0.05,
      );
    });

    test('estimateProgression 與 estimateCurrentPage 互為反函式（往返後頁碼不變）', () {
      const totalPages = 10;
      for (var page = 1; page <= totalPages; page++) {
        final progression = EpubPageEstimator.estimateProgression(
          targetPage: page,
          totalPages: totalPages,
        );
        final roundTripPage = EpubPageEstimator.estimateCurrentPage(
          progression: progression,
          totalPages: totalPages,
        );
        expect(roundTripPage, page, reason: '第 $page 頁往返後應保持不變');
      }
    });
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/epub_page_estimator_test.dart`（於 `app/` 目錄）
Expected: FAIL（`epub_page_estimator.dart` 不存在，編譯錯誤）。

- [ ] **Step 3: 撰寫最小實作**

```dart
import 'dart:math' as math;

/// EPUB 模擬分頁估算邏輯（epic-5-toc-pagination Issue 3，spec.md「分頁估算
/// 模組」）：純 Dart、無 I/O，供 `ReaderScreen` 依目前生效的版面參數＋全書
/// 字元數快取換算「估計總頁數」／「目前頁碼」，以及頁尾跳頁互動的反向換算
/// （目標頁碼→全書進度比例）。
///
/// 明確聲明：本模組產生的頁碼為模擬估算值，不保證與 Readium 實際渲染逐頁
/// 精確對齊（見 spec.md「分頁估算模組」）。
class EpubPageEstimator {
  const EpubPageEstimator._();

  /// 對應「預設版面參數」（fontSize 倍率 1.0＝16px／lineHeight 1.5／
  /// paragraphSpacing 倍率 1.0＝10px／pageMargins 倍率 1.0＝15px，見
  /// `ReaderSettingsSheet` 的既有預設值）下，估計一螢幕可容納的字元數。
  /// 比照 TXT 引擎「固定字元數量分頁換算」啟發式的既有精神（見
  /// CLAUDE.md「支援格式與渲染方式」）。
  static const int referenceCharsPerScreen = 500;

  /// 依目前生效的版面參數估算「每螢幕可容納字元數」。`null` 代表該欄位
  /// 未被使用者覆寫（見 `ResolvedPreferences` 的既有 null 語意），套用與
  /// `ReaderSettingsSheet` 一致的預設值。字體越大／行距越高／段落間距與
  /// 邊距越寬，可視面積內能容納的字元數越少。
  static int estimateCharsPerScreen({
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? pageMargins,
  }) {
    final fontSizeFactor = fontSize ?? 1.0;
    final lineHeightFactor = (lineHeight ?? 1.5) / 1.5;
    final paragraphSpacingFactor = paragraphSpacing ?? 1.0;
    final pageMarginsFactor = pageMargins ?? 1.0;

    // 字體大小同時影響每行字數與可視行數（面積效應），故取平方項；行距為
    // 單一維度線性效應；段落間距／邊距對整體可視面積的影響較小，以較低
    // 權重（0.1／0.2）線性調整，避免這兩者把估算值推向不合理的極端。
    final areaFactor = fontSizeFactor *
        fontSizeFactor *
        lineHeightFactor *
        (1 + (paragraphSpacingFactor - 1) * 0.1) *
        (1 + (pageMarginsFactor - 1) * 0.2);

    final estimated = (referenceCharsPerScreen / areaFactor).round();
    // 防呆下限/上限，避免極端版面設定（例如字體縮到最小）估算出不合理的
    // 總頁數（例如一本 10 萬字的書被估成上萬頁）。
    return estimated.clamp(50, referenceCharsPerScreen * 4);
  }

  /// 依全書字元數快取與每螢幕可容納字元數換算估計總頁數，至少 1 頁。
  static int estimateTotalPages({
    required int totalCharacterCount,
    required int charsPerScreen,
  }) {
    if (totalCharacterCount <= 0) return 1;
    if (charsPerScreen <= 0) return 1;
    return math.max(1, (totalCharacterCount / charsPerScreen).ceil());
  }

  /// 依 Readium 提供的全書閱讀進度比例（[progression]，來自
  /// `EpubPositionInfo.progression`，可能為 `null`——見 `onLocatorChanged`
  /// 的既有 null 語意）換算目前頁碼，箝制在 `[1, totalPages]` 範圍內。
  static int estimateCurrentPage({
    required double? progression,
    required int totalPages,
  }) {
    if (progression == null) return 1;
    final page = (progression * totalPages).round();
    return page.clamp(1, totalPages);
  }

  /// [estimateCurrentPage] 的反向換算：使用者在頁尾輸入/拖曳指定
  /// [targetPage]（1-indexed）時，換算成供原生端跳轉用的全書進度比例
  /// （頁面區間中點，即 `(targetPage - 0.5) / totalPages`，與
  /// [estimateCurrentPage] 的四捨五入語意互為反函式）。
  static double estimateProgression({
    required int targetPage,
    required int totalPages,
  }) {
    if (totalPages <= 0) return 0.0;
    final progression = (targetPage - 0.5) / totalPages;
    return progression.clamp(0.0, 1.0);
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/epub_page_estimator_test.dart`
Expected: PASS（全數綠燈）。

- [ ] **Step 5: Commit**

```bash
git add app/lib/reader/epub_page_estimator.dart app/test/reader/epub_page_estimator_test.dart
git commit -m "feat(epic-5-issue3): 新增 EpubPageEstimator 純 Dart 頁碼估算模組"
```

---

### Task 3: `books` 表 schema migration（`totalCharacterCount` 欄位）

**Files:**
- Modify: `app/lib/library/models/book.dart`
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/models/book_test.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Produces: `Book.totalCharacterCount`（`int?`，`toMap`/`fromMap` 皆涵蓋）；`books` 表新增 `totalCharacterCount INTEGER` 欄位，schema version 6。
- Consumes：無新相依。

- [ ] **Step 1: 寫失敗測試（`Book` 序列化 round-trip）**

於 `app/test/library/models/book_test.dart` 新增：

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

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/library/models/book_test.dart`
Expected: FAIL（`Book` 建構子沒有 `totalCharacterCount` 具名參數，編譯錯誤）。

- [ ] **Step 3: 修改 `Book` model**

編輯 `app/lib/library/models/book.dart`，於 `pdfPageIndex` 欄位之後新增：

```dart
  /// PDF 頁索引（0-indexed），`null` 代表尚無記錄。與 [epubLocator] 互斥。
  final int? pdfPageIndex;

  /// 全書字元數快取（epic-5-toc-pagination Issue 3，spec.md「分頁估算
  /// 模組」決策 #16），僅 EPUB 有值。`null` 代表尚未計算過，開書時原生端
  /// 據此觸發一次背景計算；非 `null` 則直接讀取快取，不重新走訪全書。
  final int? totalCharacterCount;
```

建構子新增對應具名參數（緊接 `this.pdfPageIndex,` 之後）：

```dart
    this.pdfPageIndex,
    this.totalCharacterCount,
```

`toMap()` 新增：

```dart
      'pdfPageIndex': pdfPageIndex,
      'totalCharacterCount': totalCharacterCount,
```

`Book.fromMap()` 新增：

```dart
      pdfPageIndex: map['pdfPageIndex'] as int?,
      totalCharacterCount: map['totalCharacterCount'] as int?,
```

`copyWith()` 維持現狀不動（目前只支援覆寫 `groupName`，本工單不需要批次覆寫 `totalCharacterCount` 的場景）。

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/library/models/book_test.dart`
Expected: PASS。

- [ ] **Step 5: 寫失敗測試（schema migration）**

於 `app/test/library/sqlite_library_repository_test.dart` 新增（沿用檔案既有 `_book(...)` helper 與 import，僅補充新測試案例）：

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

  test('既有 version 5 裝置升級到 version 6，totalCharacterCount 欄位正確補上、既有資料不受影響',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v5_to_v6_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 5」的舊資料庫：手動以 version 5 當時的
    // schema（books 表不含 totalCharacterCount）建立，不透過
    // SqliteLibraryRepository.open()（該方法目前的 onCreate 已經是
    // version 6 的最終 schema，無法用來重現「舊裝置」情境）。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 5,
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
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.insert('books', {
            'id': 'b1',
            'title': 'Version 5 既有書籍',
            'format': 'epub',
            'filePath': 'content://example/b1',
            'source': 'local',
            'progress': 0.3,
            'groupName': '未分類',
            'createTime': 1000,
            'lastReadTime': 1000,
          });
        },
      ),
    );
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=5 →
    // newVersion=6），驗證既有書籍資料不受影響、且新欄位可用。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

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

  test('既有 version 1 裝置跳級升級到 version 6，全部遷移依序執行、既有資料不受影響',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v1_to_v6_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 1」的最原始資料庫：只有 groups/books 兩張
    // 表，完全沒有 book_reader_prefs 表，books 表也不含
    // epubLocator/pdfPageIndex/totalCharacterCount 欄位。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
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
          await db.insert('books', {
            'id': 'b1',
            'title': '最早期書籍',
            'format': 'epub',
            'filePath': 'content://example/b1',
            'source': 'local',
            'progress': 0,
            'groupName': '未分類',
            'createTime': 1000,
            'lastReadTime': 1000,
          });
        },
      ),
    );
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=1 →
    // newVersion=6）。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

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

- [ ] **Step 6: 執行測試確認失敗**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: FAIL（`totalCharacterCount` 欄位不存在，`no such column` 或欄位讀回恆為 `null` 但寫入時拋出例外）。

- [ ] **Step 7: 修改 `SqliteLibraryRepository`**

編輯 `app/lib/library/sqlite_library_repository.dart`：

`version` 從 `5` 改為 `6`：

```dart
      version: 6,
```

`onCreate` 的 `books` 表定義新增欄位（緊接 `pdfPageIndex INTEGER,` 之後）：

```dart
            pdfPageIndex INTEGER,
            totalCharacterCount INTEGER,
```

`onUpgrade` 新增一段無條件檢查（緊接既有 `if (oldVersion < 5) { ... }` 區塊之後、`onUpgrade` 回呼結尾之前）：

```dart
        if (oldVersion < 5) {
          await _addReadingPositionColumns(db);
        }
        if (oldVersion < 6) {
          // epic-5-toc-pagination Issue 3：全書字元數快取欄位，補追加到
          // 既有（version 1 起已存在）的 books 表。刻意放在上方 if/else
          // 之外、無條件檢查，比照 oldVersion < 5 區塊的既有原則——不論
          // 裝置目前處於哪個舊版本，只要 oldVersion < 6 就必須執行。
          await _addTotalCharacterCountColumn(db);
        }
```

新增對應的 static helper（緊接 `_addReadingPositionColumns` 之後）：

```dart
  static Future<void> _addTotalCharacterCountColumn(Database db) async {
    // 全書字元數快取（epic-5-toc-pagination Issue 3）新增的 1 個欄位，
    // 補追加到既有（version 1 起已存在）的 books 表，見
    // docs/epics/epic-5-toc-pagination/spec.md「分頁估算模組」決策 #16。
    await db.execute('ALTER TABLE books ADD COLUMN totalCharacterCount INTEGER');
  }
```

- [ ] **Step 8: 執行測試確認通過**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: PASS（含既有測試，全數綠燈）。

- [ ] **Step 9: Commit**

```bash
git add app/lib/library/models/book.dart app/lib/library/sqlite_library_repository.dart app/test/library/models/book_test.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-5-issue3): books 表新增 totalCharacterCount 欄位（累加式 migration）"
```

---

### Task 4: `EpubCharacterCountRepository` + `ReaderPrefsManager` 讀寫接線

**Files:**
- Create: `app/lib/reader/epub_character_count_repository.dart`
- Create: `app/test/support/fake_epub_character_count_repository.dart`
- Modify: `app/lib/reader/reader_prefs_manager.dart`
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/test/support/fake_reader_prefs_manager.dart`
- Test: `app/test/reader/reader_prefs_manager_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `books.totalCharacterCount` 欄位。
- Produces:
  - `EpubCharacterCountRepository.load(String bookId) -> Future<int?>`／`.save(String bookId, int totalCharacterCount) -> Future<void>`。
  - `LoadedPrefs.totalCharacterCount`（`int?`）。
  - `ReaderPrefsManager.saveTotalCharacterCount(String bookId, int totalCharacterCount) -> Future<void>`。
  - `ReaderPrefsManagerImpl` 建構子新增**選擇性**第 3 個位置參數 `EpubCharacterCountRepository? characterCountRepository`（省略時 `load()` 回傳 `null`、`saveTotalCharacterCount` 安全無操作，既有呼叫端不需修改，見 Global Constraints「Surgical Changes」）。供 Task 7 的 `ReaderScreen` 使用。

- [ ] **Step 1: 寫失敗測試（`EpubCharacterCountRepository` 由 `ReaderPrefsManagerImpl` 接線）**

於 `app/test/reader/reader_prefs_manager_test.dart` 的 `import` 區塊新增：

```dart
import 'package:elinkbook/reader/epub_character_count_repository.dart';
```

於 `load()` group（既有 `setUp` 之後）新增兩個測試：

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

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/reader_prefs_manager_test.dart`
Expected: FAIL（`EpubCharacterCountRepository` 不存在、`ReaderPrefsManagerImpl` 沒有第 3 個參數、`saveTotalCharacterCount`/`totalCharacterCount` 未定義，編譯錯誤）。

- [ ] **Step 3: 新增 `EpubCharacterCountRepository`**

```dart
import 'package:sqflite/sqflite.dart';

/// `books` 表 `totalCharacterCount` 欄位的存取層（epic-5-toc-pagination
/// Issue 3，spec.md「分頁估算模組」決策 #16）。與 [ReadingPositionRepository]
/// 刻意分離成獨立的小型 repository，而非併入同一個類別——`totalCharacterCount`
/// 是「全書字元數計算結果的快取」，與 [ReadingPositionRepository] 明確
/// scoped 的「本機閱讀位置」欄位（epubLocator/pdfPageIndex/progress）是
/// 各自獨立、寫入時機也不同的關注點（位置在離開/背景時寫入；字元數快取在
/// 背景計算完成當下寫入），分開後才能各自做 partial UPDATE 而不互相
/// 覆蓋對方欄位，只是恰好存放在同一張 `books` 表裡。
class EpubCharacterCountRepository {
  final Database _db;

  const EpubCharacterCountRepository(this._db);

  /// 無對應書籍列或尚未計算過時回傳 `null`（代表尚無快取值，呼叫端據此
  /// 決定是否觸發原生端背景計算，見 spec.md「執行緒與快取」）。
  Future<int?> load(String bookId) async {
    final rows = await _db.query(
      'books',
      columns: ['totalCharacterCount'],
      where: 'id = ?',
      whereArgs: [bookId],
    );
    if (rows.isEmpty) return null;
    return rows.single['totalCharacterCount'] as int?;
  }

  /// Partial update：只更新這 1 個欄位，不影響書籍的其餘欄位，比照
  /// [ReadingPositionRepository.save] 的既有模式。
  Future<void> save(String bookId, int totalCharacterCount) async {
    await _db.update(
      'books',
      {'totalCharacterCount': totalCharacterCount},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }
}
```

- [ ] **Step 4: 修改 `LoadedPrefs`／`ReaderPrefsManager` 介面**

編輯 `app/lib/reader/reader_prefs_manager.dart`，`LoadedPrefs` 新增欄位：

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

`ReaderPrefsManager` 抽象類別新增方法（緊接 `saveReadingPosition` 之後）：

```dart
  /// 寫入全書字元數快取（epic-5-toc-pagination Issue 3）。呼叫時機為原生端
  /// 背景計算完成、透過 EpubReaderView.onCharacterCountReady 回報之後，
  /// 只在該書尚無快取值時觸發一次（見 spec.md「執行緒與快取」）。
  Future<void> saveTotalCharacterCount(String bookId, int totalCharacterCount);
```

- [ ] **Step 5: 修改 `ReaderPrefsManagerImpl`**

編輯 `app/lib/reader/reader_prefs_manager_impl.dart`，新增 import：

```dart
import 'epub_character_count_repository.dart';
```

建構子改為選擇性第 3 個位置參數（不使用具名參數，避免破壞既有位置參數呼叫慣例；`[...]` 語法讓既有的兩參數呼叫端不需任何修改）：

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

`load()` 新增第 4 個平行讀取：

```dart
  @override
  Future<LoadedPrefs> load(String bookId) async {
    final results = await Future.wait([
      _sqliteRepository.load(bookId),
      _loadGlobalPrefs(),
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

新增方法實作（緊接 `saveReadingPosition` 之後）：

```dart
  @override
  Future<void> saveTotalCharacterCount(String bookId, int totalCharacterCount) =>
      _characterCountRepository?.save(bookId, totalCharacterCount) ??
      Future.value();
```

- [ ] **Step 6: 修改 `main.dart` 接線**

編輯 `app/lib/main.dart`，新增 import：

```dart
import 'reader/epub_character_count_repository.dart';
```

建構 `prefsManager` 處新增第 3 個參數：

```dart
  final prefsManager = ReaderPrefsManagerImpl(
    prefsRepository,
    ReadingPositionRepository(repository.database),
    EpubCharacterCountRepository(repository.database),
  );
```

- [ ] **Step 7: 新增 `FakeEpubCharacterCountRepository`**

```dart
import 'package:elinkbook/reader/epub_character_count_repository.dart';

/// 測試用 Fake，比照 [FakeReadingPositionRepository] 模式。
class FakeEpubCharacterCountRepository implements EpubCharacterCountRepository {
  final Map<String, int> _storage = {};

  @override
  Future<int?> load(String bookId) async => _storage[bookId];

  @override
  Future<void> save(String bookId, int totalCharacterCount) async {
    _storage[bookId] = totalCharacterCount;
  }
}
```

- [ ] **Step 8: 更新 `FakeReaderPrefsManager`**

編輯 `app/test/support/fake_reader_prefs_manager.dart`，新增 import：

```dart
import 'fake_epub_character_count_repository.dart';
```

新增欄位與建構子參數：

```dart
class FakeReaderPrefsManager implements ReaderPrefsManager {
  final Map<String, BookReaderPrefs> bookPrefsByBookId;
  final Map<String, ReadingPosition> readingPositionByBookId;
  final Map<String, int> totalCharacterCountByBookId;
  GlobalReaderPrefs globalPrefs;
  final List<String> savedBookPrefsCalls = [];
  final List<GlobalReaderPrefs> savedGlobalPrefsCalls = [];
  final List<MapEntry<String, ReadingPosition>> savedReadingPositionCalls = [];
  final List<MapEntry<String, int>> savedTotalCharacterCountCalls = [];

  FakeReaderPrefsManager({
    Map<String, BookReaderPrefs>? bookPrefsByBookId,
    Map<String, ReadingPosition>? readingPositionByBookId,
    Map<String, int>? totalCharacterCountByBookId,
    this.globalPrefs = const GlobalReaderPrefs.initial(),
  })  : bookPrefsByBookId = bookPrefsByBookId ?? {},
        readingPositionByBookId = readingPositionByBookId ?? {},
        totalCharacterCountByBookId = totalCharacterCountByBookId ?? {};

  final _delegate = ReaderPrefsManagerImpl(
    FakeBookReaderPrefsRepository(),
    FakeReadingPositionRepository(),
    FakeEpubCharacterCountRepository(),
  );
```

`load()` 新增回傳欄位：

```dart
  @override
  Future<LoadedPrefs> load(String bookId) async {
    return LoadedPrefs(
      bookPrefs: bookPrefsByBookId[bookId] ?? BookReaderPrefs.empty,
      globalPrefs: globalPrefs,
      readingPosition:
          readingPositionByBookId[bookId] ?? const ReadingPosition(),
      totalCharacterCount: totalCharacterCountByBookId[bookId],
    );
  }
```

新增方法實作（緊接 `saveReadingPosition` 之後）：

```dart
  @override
  Future<void> saveTotalCharacterCount(
      String bookId, int totalCharacterCount) async {
    totalCharacterCountByBookId[bookId] = totalCharacterCount;
    savedTotalCharacterCountCalls.add(MapEntry(bookId, totalCharacterCount));
  }
```

- [ ] **Step 9: 執行測試確認通過**

Run: `flutter test test/reader/reader_prefs_manager_test.dart`
Expected: PASS。

Run（回歸檢查，確認選擇性第 3 參數未破壞既有呼叫端）: `flutter test`
Expected: 全數 PASS，無既有測試失敗。

- [ ] **Step 10: Commit**

```bash
git add app/lib/reader/epub_character_count_repository.dart app/test/support/fake_epub_character_count_repository.dart app/lib/reader/reader_prefs_manager.dart app/lib/reader/reader_prefs_manager_impl.dart app/lib/main.dart app/test/support/fake_reader_prefs_manager.dart app/test/reader/reader_prefs_manager_test.dart
git commit -m "feat(epic-5-issue3): 新增 EpubCharacterCountRepository 並接線至 ReaderPrefsManager"
```

---

### Task 5: `EpubReaderView.kt`（背景字元數計算 + 跳頁）

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`

**Interfaces:**
- Consumes: `EpubCharacterCounter.countCharacters(String) -> Int`（Task 1）。
- Produces:
  - `openBook` method channel 新增可選引數 `totalCharacterCount`（Int）。
  - 新事件 `onCharacterCountReady`（引數：`Int`，全書字元數）。
  - 新指令 `jumpToProgression`（引數：`Double`，0.0–1.0）。

本 Task 對應 issues.md 對 Issue 3 原生端單元測試要求的但書：「先確認字元加總邏輯是否能抽出為不依賴 Android／Readium 執行環境的無狀態純 Kotlin 函式」。結論已在 Task 1 落地——可抽離的部分（單一 resource 的 HTML 轉字元數）已抽成 `EpubCharacterCounter`，走訪 `Publication.readingOrder` 逐一取得 resource 內容的迴圈本身需要 Readium 的 suspend `Resource` API 與真實 `Publication` 物件，無法脫離真機/模擬器環境以純 JUnit 驗證，故該迴圈留在 `EpubReaderView.kt`、改以 `integration_test`（Task 8）涵蓋。走訪迴圈用到的 `Publication.get(link)`／`Resource.read()`／`Resource.close()` 簽章不需另外反編譯驗證——`BookMetadataChannel.kt` 的 `findFallbackCoverBitmap()` 已是同一組簽章在本專案內實際編譯執行的先例，見 Step 5。

- [ ] **Step 1: 驗證既有死程式碼清理狀態（issues.md 驗收標準）**

Run:
```bash
grep -n "override fun onPageChanged" app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
```
Expected: 無輸出（該覆寫已於 Issue 2 的 C3 審查修正 commit `fe9827a` 移除，見該檔案第 712-731、757-763 行的說明註解）。若確認無輸出，本 Step 的驗收標準視為已滿足，不需任何程式碼變更；若意外找到輸出（例如有人之後又加回來），需先移除該覆寫再繼續本 Task（理由見 spec.md「分頁估算模組」：`onPageChanged` 對 FXL 書籍不會被呼叫，`currentLocator` StateFlow 才是唯一可靠的位置回報來源）。

- [ ] **Step 2: 新增 import**

於檔案頂端既有 `import` 區塊新增（`import kotlinx.coroutines.launch` 之後）：

```kotlin
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt
```

- [ ] **Step 3: `openBook` 新增 `initialTotalCharacterCount` 參數**

修改 `onMethodCall` 的 `"openBook"` 分支：

```kotlin
            "openBook" -> {
                @Suppress("UNCHECKED_CAST")
                openBook(
                    call.argument<String>("path"),
                    call.argument<Map<String, Any?>>("initialPreferences"),
                    call.argument<String>("initialLocatorJson"),
                    call.argument<Int>("totalCharacterCount"),
                )
                result.success(null)
            }
```

修改 `openBook()` 簽章與呼叫 `attachNavigator` 處：

```kotlin
    private fun openBook(
        path: String?,
        initialPreferences: Map<String, Any?>?,
        initialLocatorJson: String?,
        initialTotalCharacterCount: Int?,
    ) {
        if (path == null) {
            channel.invokeMethod("onError", "缺少檔案路徑")
            return
        }
        pageReported = false
        scope.launch {
            try {
                val httpClient = DefaultHttpClient()
                val assetRetriever = AssetRetriever(context.contentResolver, httpClient)
                val resolvedUrl = resolveAbsoluteUrl(path)
                if (resolvedUrl == null) {
                    channel.invokeMethod("onError", "無法解析檔案路徑或 URI：$path")
                    return@launch
                }
                val asset = assetRetriever.retrieve(resolvedUrl).getOrElse {
                    channel.invokeMethod("onError", "找不到檔案或檔案已損毀：$path")
                    return@launch
                }
                val publicationParser = DefaultPublicationParser(
                    context,
                    httpClient,
                    assetRetriever,
                    pdfFactory = null,
                )
                val publicationOpener = PublicationOpener(publicationParser)
                val openedPublication = publicationOpener.open(asset, allowUserInteraction = false).getOrElse {
                    channel.invokeMethod("onError", "無法解析 EPUB 檔案：${it.message}")
                    return@launch
                }
                if (isDisposed) {
                    openedPublication.close()
                    return@launch
                }
                attachNavigator(openedPublication, initialPreferences, initialLocatorJson, initialTotalCharacterCount)
            } catch (e: Exception) {
                channel.invokeMethod("onError", "開啟 EPUB 檔案時發生未預期的錯誤：${e.message}")
            }
        }
    }
```

（僅新增 `initialTotalCharacterCount` 參數與傳遞，其餘內容與現有程式碼相同，不變更既有錯誤處理邏輯。）

- [ ] **Step 4: `attachNavigator` 新增背景字元數計算觸發**

修改 `attachNavigator()` 簽章，新增參數；並在既有 `if (initialPreferences != null && ...)` 區塊之後（仍在 `try` 區塊內、`attachNavigator` 成功路徑）新增觸發呼叫：

```kotlin
    private fun attachNavigator(
        openedPublication: Publication,
        initialPreferences: Map<String, Any?>?,
        initialLocatorJson: String?,
        initialTotalCharacterCount: Int?,
    ) {
        try {
            publication = openedPublication
            val navigatorFactory = EpubNavigatorFactory(publication = openedPublication)
            val initialLocator = initialLocatorJson?.let {
                Locator.fromJSON(JSONObject(it))
            }
            val fragmentFactory = navigatorFactory.createFragmentFactory(
                initialLocator = initialLocator,
                listener = this,
                paginationListener = this,
                configuration = buildFontFamiliesConfiguration(),
            )
            installedFragmentFactory = fragmentFactory
            activity.supportFragmentManager.fragmentFactory = fragmentFactory
            activity.supportFragmentManager.commitNow(allowStateLoss = true) {
                add<EpubNavigatorFragment>(containerId, args = Bundle(), tag = fragmentTag)
            }
            navigatorFragment = activity.supportFragmentManager
                .findFragmentByTag(fragmentTag) as? EpubNavigatorFragment
            navigatorFragment?.currentLocator
                ?.onEach { locator ->
                    channel.invokeMethod(
                        "onLocatorChanged",
                        mapOf(
                            "locatorJson" to locator.toJSON().toString(),
                            "progression" to locator.locations.totalProgression,
                        ),
                    )
                }
                ?.launchIn(scope)
            if (initialPreferences != null && initialPreferences.isNotEmpty()) {
                applyDualPagePreferences(initialPreferences)
                currentPreferences = currentPreferences.plus(buildPreferencesFromMap(initialPreferences))
                navigatorFragment?.submitPreferences(currentPreferences)
            }
            // epic-5-toc-pagination Issue 3：僅在尚無快取值時才觸發背景字元數
            // 計算，之後每次開書直接沿用 Dart 端傳入的快取值，不重新走訪全書
            // （見 spec.md「執行緒與快取」）。
            if (initialTotalCharacterCount == null) {
                computeTotalCharacterCountInBackground(openedPublication)
            }
        } catch (e: Exception) {
            publication = null
            openedPublication.close()
            channel.invokeMethod("onError", "掛載 EPUB 閱讀畫面失敗：${e.message}")
        }
    }
```

（其餘既有內容不變，僅新增末尾的字元數計算觸發區塊與簽章的第 4 個參數。）

- [ ] **Step 5: 新增 `computeTotalCharacterCountInBackground()` 與 `jumpToProgression()`**

於 `attachNavigator()` 之後、`onPageLoaded()` 之前新增：

```kotlin
    /**
     * 全書字元數背景計算（epic-5-toc-pagination Issue 3，spec.md「分頁估算
     * 模組」決策 #16）：於 Dispatchers.IO 走訪 readingOrder 逐一取得
     * resource 內容並以 EpubCharacterCounter 計算字元數後加總，避免阻塞
     * 主執行緒；僅在尚無快取值時觸發（見 attachNavigator() 呼叫處）。
     *
     * `Publication.get(link: Link): Resource?`／`Resource.read(): Try<ByteArray,
     * ReadError>`／`Resource` 需顯式 `close()` 三件事，皆已由本檔案同目錄下
     * `BookMetadataChannel.kt`（`findFallbackCoverBitmap()`，約第 350-366 行）
     * 的既有、已編譯執行的程式碼驗證過，不需要另外反編譯確認：
     * ```kotlin
     * val resource = publication.get(coverLink) ?: return null
     * return try {
     *     val bytes = resource.read().getOrElse { null } ?: return null
     *     ...
     * } finally {
     *     resource.close()
     * }
     * ```
     * 下方寫法沿用同一組簽章與 `getOrElse { null } ?: <跳轉>` 慣例——`getOrElse`
     * 的 lambda 內不可直接寫 `continue`（Kotlin 對 inline 函式的 non-local
     * `break`/`continue` 有嚴格限制，即使是 inline function 也不允許，寫
     * `getOrElse { continue }` 會編譯失敗），須先在 lambda 內回傳 `null`，
     * 於 lambda 外再以 `?: continue` 跳出。若計算過程任何一步失敗，靜默放棄
     * 不回報 onError——這是背景增強功能，計算失敗不應該讓已成功開啟的書籍
     * 畫面跟著顯示錯誤（比照本檔案既有對「非致命背景工作」的錯誤處理原則）。
     */
    private fun computeTotalCharacterCountInBackground(publicationForCounting: Publication) {
        scope.launch(Dispatchers.IO) {
            try {
                var total = 0
                for (link in publicationForCounting.readingOrder) {
                    if (isDisposed) return@launch
                    val resource = publicationForCounting.get(link) ?: continue
                    try {
                        val bytes = resource.read().getOrElse { null } ?: continue
                        total += EpubCharacterCounter.countCharacters(bytes.toString(Charsets.UTF_8))
                    } finally {
                        // Resource 實作 Closeable，背景計算可能遍歷數十至數百個
                        // resource，不關閉會導致檔案描述符洩漏（比照
                        // BookMetadataChannel.kt findFallbackCoverBitmap() 的既有
                        // try/finally 模式）。
                        resource.close()
                    }
                }
                if (isDisposed) return@launch
                withContext(Dispatchers.Main) {
                    if (!isDisposed) channel.invokeMethod("onCharacterCountReady", total)
                }
            } catch (e: Exception) {
                // 背景估算失敗不影響已成功開啟的書籍畫面，靜默放棄（見本方法 KDoc）。
            }
        }
    }

    /**
     * 依全書進度比例（[progression]，0.0-1.0，由 Dart 端 EpubPageEstimator
     * 換算目標頁碼而來）跳轉至對應位置（epic-5-toc-pagination Issue 3，
     * FR-23）。使用 Readium 既有的 `positions()`（design.md 決策 #5 已確認
     * 存在、僅依固定 bytes 切分的既有分頁定位清單）取得一組涵蓋全書的
     * Locator 序列，依比例挑選最接近的一個作為跳轉目標——這與「每螢幕可
     * 容納字元數」估算（見 EpubPageEstimator）是兩條獨立的機制：後者只用
     * 來換算頁碼「顯示」用的分母，跳轉本身沿用 Readium 既有、已考慮全書
     * 實際章節切分的定位清單，不需要另外把字元數估算延伸成一套自製的
     * Locator 建構邏輯（見 design.md「Further Notes」對「跳轉底層定位轉換
     * 屬於實作細節」的既有授權）。走訪 positions() 亦在背景執行緒進行，
     * 計算完成後才跳回主執行緒呼叫 Navigator.go()（Android View 操作須在
     * 主執行緒）。
     */
    private fun jumpToProgression(progression: Double) {
        val currentPublication = publication ?: return
        scope.launch(Dispatchers.IO) {
            val positions = currentPublication.positions()
            if (isDisposed || positions.isEmpty()) return@launch
            val index = (progression * (positions.size - 1)).roundToInt()
                .coerceIn(0, positions.size - 1)
            val locator = positions[index]
            withContext(Dispatchers.Main) {
                if (!isDisposed) navigatorFragment?.go(locator, animated = false)
            }
        }
    }
```

- [ ] **Step 6: `onMethodCall` 新增 `jumpToProgression` 指令**

於 `onMethodCall` 的 `"previousPage"` 分支之後新增：

```kotlin
            "jumpToProgression" -> {
                val progression = (call.arguments as? Double) ?: 0.0
                jumpToProgression(progression)
                result.success(null)
            }
```

- [ ] **Step 7: 編譯驗證**

Run（於 `app/` 目錄）：`flutter build apk --debug`
Expected: 建置成功（`BUILD SUCCESSFUL`），無 Kotlin 編譯錯誤。

- [ ] **Step 8: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
git commit -m "feat(epic-5-issue3): EpubReaderView.kt 新增背景全書字元數計算與 jumpToProgression"
```

---

### Task 6: Dart `EpubReaderView` 新增字元數/跳頁介面

**Files:**
- Modify: `app/lib/reader/epub_reader_view.dart`

**Interfaces:**
- Consumes: 原生端 `onCharacterCountReady`／`jumpToProgression`（Task 5）。
- Produces:
  - `EpubReaderView.initialTotalCharacterCount`（`int?`，一次性開書起始值，語意比照 `initialLocatorJson`）。
  - `EpubReaderView.onCharacterCountReady`（`ValueChanged<int>?`）。
  - `EpubReaderView.jumpToProgression(GlobalKey<State<EpubReaderView>> key, double progression)`（static helper，比照 `PdfReaderView.jumpToPage`）。

- [ ] **Step 1: 新增建構參數**

編輯 `app/lib/reader/epub_reader_view.dart`，於 `initialLocatorJson`／`onLocatorChanged` 欄位之後新增：

```dart
  /// 開書時的全書字元數快取（epic-5-toc-pagination Issue 3）。`null` 代表
  /// 尚未計算過，原生端據此觸發一次背景計算；與 [initialLocatorJson] 同為
  /// 「一次性開書起始值」，只在 `openBook` 當下送出一次，不參與
  /// [didUpdateWidget] 的偏好設定 diff 邏輯。
  final int? initialTotalCharacterCount;

  /// 原生端背景計算全書字元數完成時觸發一次（Issue 3）。呼叫端
  /// （ReaderScreen）負責把結果快取到 `books.totalCharacterCount`。
  final ValueChanged<int>? onCharacterCountReady;
```

建構子新增對應參數：

```dart
  const EpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.writingMode,
    this.pageTurnMode,
    this.onLayoutResolved,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.paragraphSpacing,
    this.pageMargins,
    this.textAlign,
    this.publisherStyles,
    this.dualPageMode = DualPageMode.auto,
    this.isLandscape = false,
    this.onToggleFixedLayoutControls,
    this.onFixedLayoutPageTurn,
    this.initialLocatorJson,
    this.onLocatorChanged,
    this.initialTotalCharacterCount,
    this.onCharacterCountReady,
  });

  @override
  State<EpubReaderView> createState() => _EpubReaderViewState();

  /// 供外部（ReaderScreen）安全呼叫 [_EpubReaderViewState.jumpToProgression]
  /// 的強型別 static helper，比照 [PdfReaderView.jumpToPage] 既有模式，不
  /// 使用 `as dynamic` 跨越 State 的 private 邊界（見 Global Constraints）。
  static void jumpToProgression(
    GlobalKey<State<EpubReaderView>> key,
    double progression,
  ) {
    final state = key.currentState;
    if (state is _EpubReaderViewState) {
      state.jumpToProgression(progression);
    }
  }
}
```

（`@override State<EpubReaderView> createState()` 那一行是既有程式碼，接在其後新增 static helper；請確認沒有重複宣告。）

- [ ] **Step 2: `_onPlatformViewCreated` 送出快取值**

修改 `_onPlatformViewCreated`：

```dart
  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
    _channel = channel;
    channel.setMethodCallHandler(_handleMethodCall);
    channel.invokeMethod('openBook', {
      'path': widget.filePath,
      'initialPreferences': _buildPreferencesMap(),
      if (widget.initialLocatorJson != null)
        'initialLocatorJson': widget.initialLocatorJson,
      if (widget.initialTotalCharacterCount != null)
        'totalCharacterCount': widget.initialTotalCharacterCount,
    });
  }
```

- [ ] **Step 3: `_handleMethodCall` 新增事件**

於 `_handleMethodCall` 的 `switch` 新增一個 `case`（緊接 `'onLocatorChanged'` 之後）：

```dart
      case 'onCharacterCountReady':
        widget.onCharacterCountReady?.call(call.arguments as int);
        break;
```

- [ ] **Step 4: 新增 `jumpToProgression` 實例方法**

於 `previousPage()` 之後新增：

```dart
  /// 依全書進度比例（[progression]，0.0-1.0）跳轉，供頁尾跳頁互動使用
  /// （epic-5-toc-pagination Issue 3，FR-23）。呼叫端（ReaderScreen）負責
  /// 把使用者輸入的目標頁碼透過 EpubPageEstimator.estimateProgression 換算
  /// 成這個比例值。
  void jumpToProgression(double progression) =>
      _channel?.invokeMethod('jumpToProgression', progression);
```

- [ ] **Step 5: 靜態分析驗證**

Run（於 `app/` 目錄）：`flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/epub_reader_view.dart
git commit -m "feat(epic-5-issue3): EpubReaderView 新增全書字元數快取與 jumpToProgression 介面"
```

---

### Task 7: `ReaderScreen` 接上 EPUB 頁尾與跳頁

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: `EpubPageEstimator`（Task 2）、`LoadedPrefs.totalCharacterCount`／`ReaderPrefsManager.saveTotalCharacterCount`（Task 4）、`EpubReaderView.initialTotalCharacterCount`／`onCharacterCountReady`／`jumpToProgression`（Task 6）、`ReaderFooter`（既有，不修改）。

- [ ] **Step 1: 寫失敗測試（EPUB 頁尾顯示）**

於 `app/test/screens/reader_screen_test.dart` 的 `import` 區塊新增：

```dart
import 'package:elinkbook/reader/epub_position_info.dart';
```

於檔案末尾（`main()` 結尾 `}` 之前）新增：

```dart
  // --- Epic 5 Issue 3：EPUB 頁碼顯示 + 跳頁 ---

  testWidgets('EPUB reflowable 開書後，收到 onCharacterCountReady 回報時，頁尾正確顯示估算頁碼',
      (tester) async {
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

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    // 先回報非固定版面（頁尾只在流式 EPUB 顯示）。
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    // 模擬原生端背景計算完成，回報全書字元數。
    epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsOneWidget);
    // 預設版面參數下 estimateCharsPerScreen() = 500，5000/500 = 10 頁；
    // 尚未收到 onLocatorChanged，estimateCurrentPage(null, 10) = 1。
    expect(find.text('進度 10% ｜ 第 1/10 頁'), findsOneWidget);
  });

  testWidgets('EPUB 收到 onLocatorChanged 的 progression 後，頁尾目前頁碼正確更新',
      (tester) async {
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

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    epubView.onCharacterCountReady?.call(5000); // 總頁數 10
    await tester.pump();
    epubView.onLocatorChanged?.call(
      const EpubPositionInfo(locatorJson: '{"href":"/c1.xhtml"}', progression: 0.5),
    );
    await tester.pump();

    expect(find.text('進度 50% ｜ 第 5/10 頁'), findsOneWidget);
  });

  testWidgets('EPUB 固定版面（FXL）開書後，即使收到 onCharacterCountReady 也不顯示頁尾',
      (tester) async {
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

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsNothing);
  });

  testWidgets('版面設定（字型大小）變動後，EPUB 頁尾估算總頁數即時重新計算',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_epub_footer_recalc',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    epubView.onCharacterCountReady?.call(5000);
    await tester.pump();

    expect(find.text('進度 10% ｜ 第 1/10 頁'), findsOneWidget);

    // 開啟版面設定，把字型大小從 16 調到 32（加倍），觸發重新估算。
    // ReaderSettingsSheet 透過 onChanged 立即呼叫 ReaderScreen._handlePrefsChanged
    // （見 reader_settings_sheet.dart _notifyChanged()），不需要關閉 Bottom
    // Sheet——底下的 ReaderScreen（含頁尾）仍在 widget tree 中並隨之 rebuild，
    // find.text() 不受 Bottom Sheet 疊加在視覺上層影響，比照本檔案既有測試
    // 對 showModalBottomSheet 開啟中直接斷言底層狀態的既有手法。
    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 16; i++) {
      await tester.tap(find.byKey(const Key('reader_settings_font_size_increment')));
    }
    await tester.pump();

    // fontSize 倍率變成 2.0 → estimateCharsPerScreen 從 500 降為 125 →
    // totalPages 從 10 變成 40。
    expect(find.text('進度 3% ｜ 第 1/40 頁'), findsOneWidget);
  });

  testWidgets('PDF 頁尾行為不受本工單影響（既有回歸驗證）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_pdf_regression',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageChanged?.call(const PdfPageInfo(pageIndex: 0, totalPages: 12));
    await tester.pump();

    expect(find.byKey(const Key('reader_footer')), findsOneWidget);
    expect(find.text('進度 8% ｜ 第 1/12 頁'), findsOneWidget);
  });
```

> 上面「版面設定重新計算」測試中，關閉 Bottom Sheet 的寫法沿用本檔案既有測試對 `showModalBottomSheet` 的處理方式；若 `find.byType(BackButton)` 在此專案的 `ReaderSettingsSheet` 情境下找不到返回鍵，改用點擊 Bottom Sheet 外部遮罩關閉（`await tester.tapAt(const Offset(10, 10)); await tester.pumpAndSettle();`），兩者皆為本檔案既有測試已使用過的關閉手法，擇一可通過編譯與執行者為準。

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: FAIL（`EpubReaderView` 沒有 `onCharacterCountReady` 參數 wiring 到頁尾、`ReaderScreen` 尚未顯示 EPUB 頁尾，找不到 `reader_footer`）。

- [ ] **Step 3: 修改 `ReaderScreen`**

編輯 `app/lib/screens/reader_screen.dart`，新增 import：

```dart
import '../reader/epub_page_estimator.dart';
```

新增狀態欄位（緊接 `_epubPositionInfo` 之後）：

```dart
  // EPUB 目前定位狀態，由 EpubReaderView.onLocatorChanged 回報（Epic 5
  // Issue 2）。寫入本機資料庫時讀取此欄位的最新值，比照 _pdfPageInfo
  // 對 PDF 的既有作法。
  EpubPositionInfo? _epubPositionInfo;
  // EPUB 全書字元數快取，由 LoadedPrefs.totalCharacterCount 載入（若有）
  // 或 EpubReaderView.onCharacterCountReady 回報更新（Epic 5 Issue 3）。
  // null 代表尚未計算完成，此時 EPUB 頁尾不顯示（比照 PDF 頁尾等待
  // _pdfPageInfo 非 null 的既有模式）。
  int? _totalCharacterCount;
```

（`EpubPositionInfo? _epubPositionInfo;` 那一行是既有程式碼，僅在其後新增 `_totalCharacterCount` 欄位。）

新增 EPUB 專屬的 `GlobalKey`（緊接 `_pdfReaderViewKey` 之後）：

```dart
  final _pdfReaderViewKey = GlobalKey<State<PdfReaderView>>();
  // 用於呼叫 EpubReaderView.jumpToProgression(key, progression) 這個強型別
  // static helper（Epic 5 Issue 3），比照 _pdfReaderViewKey 對 PDF 的既有
  // 作法。
  final _epubReaderViewKey = GlobalKey<State<EpubReaderView>>();
```

`initState()` 內載入 `_totalCharacterCount`（緊接 `_initialPosition = loaded.readingPosition;` 之後）：

```dart
      setState(() {
        _prefs = loaded.bookPrefs;
        _loaded = loaded;
        _initialPosition = loaded.readingPosition;
        _totalCharacterCount = loaded.totalCharacterCount;
        _resolved = widget.prefsManager.resolve(
          loaded,
          autoDetectedWritingMode: _autoDetectedWritingMode,
        );
      });
```

新增回呼方法（緊接 `_handleLayoutResolved` 之後）：

```dart
  /// 原生端背景計算全書字元數完成時觸發（Epic 5 Issue 3）：更新本地狀態
  /// 驅動頁尾重新渲染，並持久化快取值——不 await，比照本類別其餘持久化
  /// 呼叫的既有慣例（見 _handlePrefsChanged）。
  void _handleCharacterCountReady(int totalCharacterCount) {
    if (!mounted) return;
    setState(() => _totalCharacterCount = totalCharacterCount);
    widget.prefsManager.saveTotalCharacterCount(widget.bookId, totalCharacterCount);
  }
```

`_buildNativeView` 的 EPUB 分支新增 `key`／`initialTotalCharacterCount`／`onCharacterCountReady`：

```dart
      case BookFormat.epub:
        return EpubReaderView(
          key: _epubReaderViewKey,
          filePath: widget.filePath,
          writingMode: resolved.writingMode,
          pageTurnMode: resolved.pageTurnMode,
          onPageRendered: _handlePageRendered,
          onError: _handleError,
          onLayoutResolved: _handleLayoutResolved,
          fontFamily: resolved.fontFamily,
          fontSize: resolved.fontSize,
          fontWeight: resolved.fontWeight,
          lineHeight: resolved.lineHeight,
          paragraphSpacing: resolved.paragraphSpacing,
          pageMargins: resolved.pageMargins,
          textAlign: resolved.textAlign,
          publisherStyles: resolved.publisherStyles,
          dualPageMode: resolved.dualPageMode,
          isLandscape: isLandscape,
          onToggleFixedLayoutControls: () => setState(
            () => _fixedLayoutControlsVisible = !_fixedLayoutControlsVisible,
          ),
          onFixedLayoutPageTurn: () =>
              setState(() => _fixedLayoutControlsVisible = false),
          initialLocatorJson: _initialPosition?.epubLocatorJson,
          onLocatorChanged: (info) {
            if (!mounted) return;
            setState(() => _epubPositionInfo = info);
          },
          initialTotalCharacterCount: _totalCharacterCount,
          onCharacterCountReady: _handleCharacterCountReady,
        );
```

（原本 `onLocatorChanged` 的 callback body 只有 `_epubPositionInfo = info;`（未包在 `setState` 內）——本 Step 改成 `setState(() => _epubPositionInfo = info);`，因為頁尾的目前頁碼需要依 `_epubPositionInfo.progression` 即時重繪，原本「不觸發 rebuild、只快取供離開時讀取」的寫法對頁尾顯示需求不夠，需改為觸發 rebuild。）

`_buildBody` 新增 EPUB 頁尾（緊接既有 PDF 頁尾 `if` 之後）：

```dart
          if (format == BookFormat.pdf && _pdfPageInfo != null)
            ReaderFooter(
              currentPage: _pdfPageInfo!.pageIndex + 1,
              totalPages: _pdfPageInfo!.totalPages,
              onPageChanged: (page1Indexed) {
                PdfReaderView.jumpToPage(_pdfReaderViewKey, page1Indexed - 1);
              },
            ),
          if (format == BookFormat.epub &&
              !_isFixedLayout &&
              _totalCharacterCount != null &&
              _resolved != null)
            _buildEpubFooter(_resolved!, _totalCharacterCount!),
```

新增私有方法（緊接 `_buildBody` 之後）：

```dart
  /// EPUB 估算頁碼頁尾（Epic 5 Issue 3）：依目前生效版面參數＋全書字元數
  /// 快取換算總頁數，再依 _epubPositionInfo 的全書進度比例換算目前頁碼；
  /// 任一版面參數變動時，本方法在下一次 build() 會以新的 [resolved] 重新
  /// 計算，不需要額外的快取/失效邏輯（見 spec.md「估計頁數重算時機」）。
  Widget _buildEpubFooter(ResolvedPreferences resolved, int totalCharacterCount) {
    final charsPerScreen = EpubPageEstimator.estimateCharsPerScreen(
      fontSize: resolved.fontSize,
      lineHeight: resolved.lineHeight,
      paragraphSpacing: resolved.paragraphSpacing,
      pageMargins: resolved.pageMargins,
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
        EpubReaderView.jumpToProgression(_epubReaderViewKey, progression);
      },
    );
  }
```

- [ ] **Step 4: 修正既有 3 個方法重建 `LoadedPrefs` 時遺漏 `readingPosition`／`totalCharacterCount`（審查修正）**

`_handlePrefsChanged`／`_handleCropRectComputed`／`_handleCropRectSelected` 這 3 個既有方法（Issue 2 起即存在，本 Task 前面的 Step 未曾修改）在 `setState` 內重建 `newLoaded` 時，只帶了 `bookPrefs`／`globalPrefs` 兩個欄位，`readingPosition`／`totalCharacterCount`（Task 4 新增）皆會被重設為預設值（`ReadingPosition()`／`null`）。目前 `ReaderPrefsManagerImpl.resolve()` 只讀 `bookPrefs`／`globalPrefs`，`_buildEpubFooter`／`_writeCurrentPosition()` 也都讀取獨立的 `_totalCharacterCount`／`_epubPositionInfo` state 欄位而非 `_loaded.totalCharacterCount`／`_loaded.readingPosition`，因此這個缺口目前對外部可觀察行為沒有影響，不需要（也無法在不深入私有欄位的前提下）另外寫黑盒測試驗證。修正它純粹是為了讓 `_loaded` 物件本身保持內部一致，避免未來有新程式碼直接讀 `_loaded.readingPosition`／`.totalCharacterCount` 時得到過期的預設值。

編輯 `app/lib/screens/reader_screen.dart`，`_handlePrefsChanged` 內的 `newLoaded` 建構補上兩個欄位：

```dart
        final newLoaded = LoadedPrefs(
          bookPrefs: prefs,
          globalPrefs: loaded.globalPrefs,
          readingPosition: loaded.readingPosition,
          totalCharacterCount: loaded.totalCharacterCount,
        );
```

`_handleCropRectComputed` 內的 `newLoaded` 建構同樣補上：

```dart
        final newLoaded = LoadedPrefs(
          bookPrefs: updated,
          globalPrefs: loaded.globalPrefs,
          readingPosition: loaded.readingPosition,
          totalCharacterCount: loaded.totalCharacterCount,
        );
```

`_handleCropRectSelected` 內的 `newLoaded` 建構同樣補上：

```dart
        final newLoaded = LoadedPrefs(
          bookPrefs: updated,
          globalPrefs: loaded.globalPrefs,
          readingPosition: loaded.readingPosition,
          totalCharacterCount: loaded.totalCharacterCount,
        );
```

- [ ] **Step 5: 執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（全數綠燈，含既有測試）。

Run（全專案回歸）: `flutter test`
Expected: 全數 PASS。

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-5-issue3): ReaderScreen 接上 EPUB 估算頁碼頁尾與跳頁"
```

---

### Task 8: 真機整合測試

**Files:**
- Create: `app/integration_test/epub_pagination_test.dart`

**Interfaces:**
- Consumes: Task 7 的完整 `ReaderScreen` 行為；`test/fixtures/sample_long_vertical.epub`（既有素材，作為「較大」EPUB 驗證背景計算不卡頓）、`test/fixtures/sample.epub`（既有素材）。

- [ ] **Step 1: 寫真機整合測試**

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/epub_character_count_repository.dart';
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

/// 持續 pump，直到頁尾（reader_footer）出現或逾時——全書字元數背景計算
/// 完成前頁尾不會顯示（見 Task 7），需要額外等待，與「載入指示器消失」是
/// 兩個獨立的時間點（見 spec.md「執行緒與快取」：開書當下畫面已可互動，
/// 計算結果延後才顯示）。
Future<void> _pumpUntilFooterVisible(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (find.byKey(const Key('reader_footer')).evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：頁尾未出現（全書字元數計算未完成）');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('EPUB 開書後畫面立即可互動（不卡頓），背景計算完成後頁尾顯示估算頁碼；第二次開啟同一本書直接讀取快取',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
      EpubCharacterCountRepository(libraryRepository.database),
    );

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_long_vertical.epub', 'epub_pagination_integration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    // 第一次開書：驗證載入指示器很快消失（開書當下即可互動，不等背景計算）。
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

    // 背景計算完成後頁尾才出現，驗證估算總頁數為正整數。
    await _pumpUntilFooterVisible(tester);
    final progressTextFinder = find.byKey(const Key('reader_footer_progress_text'));
    expect(progressTextFinder, findsOneWidget);
    final progressText =
        (tester.widget<Text>(progressTextFinder)).data ?? '';
    expect(progressText, matches(RegExp(r'第 \d+/\d+ 頁')),
        reason: '頁尾應顯示「第 N/M 頁」格式的估算頁碼');

    // 離開畫面，驗證 totalCharacterCount 已快取進資料庫。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    final cached = await EpubCharacterCountRepository(libraryRepository.database)
        .load('b_epub_pagination');
    expect(cached, isNotNull, reason: '離開後全書字元數應已快取至資料庫');

    // 第二次開啟同一本書：頁尾應能較快出現（直接讀取快取，不重新計算），
    // 沿用較短的逾時視窗做粗略驗證。
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
    expect(find.byKey(const Key('reader_footer')), findsOneWidget,
        reason: '有快取值時頁尾應與載入指示器消失同時出現，不需再等待背景計算');
  });

  testWidgets('EPUB 頁尾輸入框跳頁後，畫面確實跳轉到目標頁附近', (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
      EpubCharacterCountRepository(libraryRepository.database),
    );

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.epub', 'epub_pagination_jump_integration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

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
    await _pumpUntilFooterVisible(tester);

    final totalPagesText =
        (tester.widget<Text>(find.byKey(const Key('reader_footer_progress_text')))).data ?? '';
    final match = RegExp(r'第 \d+/(\d+) 頁').firstMatch(totalPagesText);
    expect(match, isNotNull);
    final totalPages = int.parse(match!.group(1)!);
    final targetPage = (totalPages / 2).ceil().clamp(1, totalPages);

    await tester.enterText(
        find.byKey(const Key('reader_footer_jump_input')), '$targetPage');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('第 $targetPage/$totalPages 頁'), findsOneWidget,
        reason: '輸入框跳頁後頁尾應更新為目標頁');
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
}
```

- [ ] **Step 2: 於真實裝置/模擬器執行**

Run（於 `app/` 目錄，先以 `flutter devices` 取得裝置 id）：
```bash
flutter test integration_test/epub_pagination_test.dart -d <device-id>
```
Expected: `All tests passed!`（兩個 test case 皆綠燈；若第一個測試因裝置效能導致背景計算時間超過 15 秒逾時，適度放寬 `_pumpUntilFooterVisible` 的 `Duration(seconds: 15)` 上限，不需調整其餘邏輯）。

- [ ] **Step 3: Commit**

```bash
git add app/integration_test/epub_pagination_test.dart
git commit -m "test(epic-5-issue3): 新增 EPUB 分頁估算真機整合測試"
```

---

## Self-Review 對照（spec.md／issues.md 涵蓋度）

- 開啟 EPUB 後頁尾顯示估算頁碼／總頁數 → Task 7（顯示）+ Task 8（真機驗證）。
- 全書字元數背景執行緒計算、不阻塞主執行緒 → Task 5 Step 5（`Dispatchers.IO`）+ Task 8（真機驗證開書當下可互動）。
- 計算結果快取，第二次開啟不重算 → Task 3（schema）+ Task 4（repository）+ Task 5（`initialTotalCharacterCount == null` 才觸發）+ Task 8（驗證快取重用）。
- 版面設定變動即時重新計算 → Task 7 `_buildEpubFooter` 於每次 `build()` 依當下 `_resolved` 重算，測試見 Task 7 Step 1「版面設定重新計算」案例。
- EPUB 透過 Issue 1 跳頁 UI 正確跳轉 → Task 5（`jumpToProgression` 原生指令）+ Task 6（Dart 介面）+ Task 7（接線）+ Task 8（真機驗證）。
- 死程式碼清理 → Task 5 Step 1（驗證已於 Issue 2 移除，無需重複動作）。
- 原生端單元測試但書（純函式可行性判斷）→ Task 1（`EpubCharacterCounter` JUnit 可測部分）+ Task 5 Step 5 KDoc（引用 `BookMetadataChannel.kt` 既有先例，記錄「走訪 readingOrder 迴圈本身不可行、改用 integration_test」的判斷理由）。
- `flutter analyze` 乾淨、既有測試無回歸 → 每個 Task 的驗證 Step 皆含此要求。
- PDF 讀取畫面不受影響 → Task 7 新增回歸測試案例「PDF 頁尾行為不受本工單影響」。
