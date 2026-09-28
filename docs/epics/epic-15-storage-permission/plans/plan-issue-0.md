# Epic 15 Issue 0：閱讀器改用「目前生效的檔案路徑」，匯入服務併入依賴 bundle — 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 不改變任何使用者可見行為的前提下，讓 `ReaderScreen` 的檔案路徑改由 State 持有，並讓 `BookImportService` 能經由既有依賴 bundle 一路傳到閱讀器，替 Issue 1、2 鋪路。

**Architecture:**
- `LibraryReaderFeatureRepositories` 新增可為 null 的 `bookImportService` 欄位，並沿著三條既有管線傳到 `ReaderScreen`：
  - `main.dart` 建立 bundle 時填入。
  - `buildReaderScreen` 轉交給 `ReaderScreen`。
  - `ReaderScreen` 開啟單書搜尋時重建 bundle，這裡也要轉送。
- `_ReaderScreenState` 新增 `_activeFilePath`，初始值為 `widget.filePath`。State 內 15 處原本讀 `widget.filePath` 的地方全部改讀它。
- 閱讀視圖維持原本的 GlobalKey，不加 `ValueKey`（見 issues.md Issue 0、spec.md「重新開書的復位清單」）。

**Tech Stack:** Flutter／Dart 3、`flutter_test`、`sqflite_common_ffi`（既有測試用）。

**Spec:** [`../spec.md`](../spec.md)、[`../issues.md`](../issues.md) Issue 0

## Global Constraints

- 本 Issue **不改任何使用者可見行為**，也不新增任何使用者可見字串，所以不動 ARB、不跑 `flutter gen-l10n`。
- 閱讀視圖（`FoliateReaderView`／`PdfReaderView`）的 `key:` 維持 `_foliateEpubReaderViewKey`／`_pdfReaderViewKey`，**禁止**改成 `ValueKey` 或外包 `KeyedSubtree`。
- 新欄位與新參數一律可為 null、預設 null。`const LibraryReaderFeatureRepositories()` 必須仍然能編譯，既有呼叫端不需要改動。
- 命名固定為：
  - bundle 欄位與 `ReaderScreen` 建構參數：`bookImportService`
  - State 欄位：`_activeFilePath`
- 本 Issue 不使用 `bookImportService`，也不提供任何改變 `_activeFilePath` 的途徑。這兩件事分別屬於 Issue 2。
- 程式碼註解使用正體中文，並比照檔案內既有註解，標註 `epic-15-storage-permission Issue 0`。
- 每個 Task 只跑該 Task 觸及的測試檔；最後一個 Task 跑一次完整 `flutter test`（issues.md Issue 0 明訂）。
- 提交前 `flutter analyze` 必須是 "No issues found!"。
- 所有指令都在 `app/` 目錄下執行。

## Review Focus

1. **閱讀器 → 單書搜尋 → 閱讀器** 這條路徑遺失匯入服務：`ReaderScreen._openBookSearch` 是手動逐欄重建 bundle，最容易漏掉新欄位。由 Task 3 的 widget test 釘住。
2. **`main.dart` 沒填入**：所有單元測試都會通過，但正式 App 中 `bookImportService` 永遠是 null，Issue 2 的按鈕永遠不會出現。Task 3 以 grep 檢查，並在程式碼旁註明用途。
3. **有漏網的 `widget.filePath`**：15 處只要漏改一處，Issue 2 重新開書時就會有部分邏輯（例如 EPUB 版面偵測、書籤／劃線定位的 `Book` 組裝）仍用舊路徑。Task 4 以 grep 斷言 State 內只剩初始化那一處。
4. **`_activeFilePath` 的初始化時機**：第一次被讀取的時機有兩種情況：
   - `widget.isFixedLayout == null` 時，在 `initState()` 呼叫 `_resolveEpubEngineDispatch()` 時讀取。
   - `widget.isFixedLayout` 不是 null 時，該方法會提早 return，第一次讀取延後到 `build()` 的第一行。

   兩種情況下 `widget` 都已經可用。必須用 `late String _activeFilePath = widget.filePath;`（惰性初始化），不可以在欄位宣告處直接讀 `widget`。這一點由既有的 `reader_screen_test.dart` 覆蓋，因為它同時有 `isFixedLayout` 為 null 與不為 null 的案例。
5. **父層以不同 `filePath` 重建同一個 `ReaderScreen`**：改造後 State 不再跟隨 `widget.filePath` 變動。現況沒有任何呼叫端會這樣做（閱讀器一律由 `MaterialPageRoute` 建立一次，`ReaderScreen` 也沒有 `didUpdateWidget`），因此行為不變。Task 4 在欄位註解寫明這個前提，不另外加 `didUpdateWidget`（YAGNI）。

---

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/screens/library_screen_dependencies.dart` | Modify | bundle 新增 `bookImportService` 欄位 |
| `app/lib/screens/reader_screen_route.dart` | Modify | `buildReaderScreen` 轉交 `features.bookImportService` |
| `app/lib/screens/reader_screen.dart` | Modify | 新增建構參數 `bookImportService`；`_openBookSearch` 轉送；新增 `_activeFilePath` 並取代 15 處 `widget.filePath` |
| `app/lib/main.dart` | Modify | 建立 bundle 時填入 `widget.importService` |
| `app/test/screens/library_screen_dependencies_test.dart` | Modify | 新欄位的預設 null／保留同一實例斷言 |
| `app/test/screens/reader_screen_route_test.dart` | Modify | `buildReaderScreen` 轉交斷言 |
| `app/test/screens/reader_screen_test.dart` | Modify | 閱讀器開單書搜尋時轉送斷言 |

---

### Task 1：`LibraryReaderFeatureRepositories` 新增 `bookImportService` 欄位

**Files:**
- Modify: `app/lib/screens/library_screen_dependencies.dart`（import 區、class 欄位區、`const` 建構子）
- Test: `app/test/screens/library_screen_dependencies_test.dart`

**Interfaces:**
- Consumes: 既有 `BookImportService`（`app/lib/library/book_import_service.dart`）
- Produces: `LibraryReaderFeatureRepositories.bookImportService`，型別 `BookImportService?`，建構子具名參數 `this.bookImportService`，預設 null

- [x] **Step 1：寫失敗的測試**

在 `library_screen_dependencies_test.dart` 的 `main()` 內，緊接在既有測試「LibraryReaderFeatureRepositories 原樣持有六個注入的依賴…」之後新增：

```dart
  test('LibraryReaderFeatureRepositories.bookImportService 預設為 null，'
      '傳入時原樣持有同一個實例（epic-15-storage-permission Issue 0）', () {
    const empty = LibraryReaderFeatureRepositories();
    expect(empty.bookImportService, isNull);

    final importService = FakeBookImportService();
    final dependencies =
        LibraryReaderFeatureRepositories(bookImportService: importService);
    expect(dependencies.bookImportService, same(importService));
  });
```

在檔案頂端 import 區補上（若尚未 import）：

```dart
import '../support/fake_book_import_service.dart';
```

- [x] **Step 2：執行測試，確認失敗**

Run: `flutter test test/screens/library_screen_dependencies_test.dart`
Expected: 編譯錯誤，訊息為 `The getter 'bookImportService' isn't defined` 或 `No named parameter with the name 'bookImportService'`。

- [x] **Step 3：最小實作**

`library_screen_dependencies.dart` import 區，依字母順序插在 `../cloud_import/...` 之後、`../reader/...` 之前：

```dart
import '../library/book_import_service.dart';
```

在 `LibraryReaderFeatureRepositories` 的 `final SearchRepository? searchRepository;` 之後新增欄位：

```dart
  /// epic-15-storage-permission Issue 0：書籍匯入服務，供閱讀器在檔案存取
  /// 失效時「重新連結」書籍使用（Issue 2 才會實際使用）。放進本 bundle
  /// 而非各畫面各自新增建構參數，是因為本 bundle 已貫穿所有開啟閱讀器的
  /// 路徑（書架、全庫搜尋、單書搜尋、閱讀器→單書搜尋→閱讀器）。`null`
  /// 時閱讀器不提供重新連結功能。
  final BookImportService? bookImportService;
```

在 `const LibraryReaderFeatureRepositories({...})` 參數列的 `this.searchRepository,` 之後新增：

```dart
    this.bookImportService,
```

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test test/screens/library_screen_dependencies_test.dart`
Expected: All tests passed.

- [x] **Step 5：Commit**

```bash
git add lib/screens/library_screen_dependencies.dart test/screens/library_screen_dependencies_test.dart
git commit -m "refactor(library): LibraryReaderFeatureRepositories 新增 bookImportService 欄位（epic-15 Issue 0）"
```

---

### Task 2：`ReaderScreen` 新增 `bookImportService` 參數，`buildReaderScreen` 轉交

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`（`ReaderScreen` 欄位區與 `const ReaderScreen({...})` 建構子，約第 222–268 行；import 區）
- Modify: `app/lib/screens/reader_screen_route.dart`（`buildReaderScreen` 的 `ReaderScreen(...)` 呼叫）
- Test: `app/test/screens/reader_screen_route_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `LibraryReaderFeatureRepositories.bookImportService`（`BookImportService?`）
- Produces: `ReaderScreen.bookImportService`（`final BookImportService?`，建構子具名參數，預設 null）。Task 3 與 Issue 2 會讀取它。

- [x] **Step 1：寫失敗的測試**

在 `reader_screen_route_test.dart` 的 `group('buildReaderScreen', ...)` 內，既有「欄位對帳」測試之後新增兩個測試：

```dart
    test('bundle 帶 bookImportService 時，原樣轉交給 ReaderScreen'
        '（epic-15-storage-permission Issue 0）', () {
      final importService = FakeBookImportService();
      final screen = buildReaderScreen(
        book: _testBook(),
        prefsManager: FakeReaderPrefsManager(),
        features: LibraryReaderFeatureRepositories(
          bookImportService: importService,
        ),
        sync: const LibrarySyncDependencies(),
        libraryRepository: FakeLibraryRepository(),
        isEinkMode: false,
      );

      expect(screen.bookImportService, same(importService));
    });

    test('bundle 未帶 bookImportService 時，ReaderScreen.bookImportService 為 null',
        () {
      final screen = buildReaderScreen(
        book: _testBook(),
        prefsManager: FakeReaderPrefsManager(),
        features: const LibraryReaderFeatureRepositories(),
        sync: const LibrarySyncDependencies(),
        libraryRepository: FakeLibraryRepository(),
        isEinkMode: false,
      );

      expect(screen.bookImportService, isNull);
    });
```

import 區補上：

```dart
import '../support/fake_book_import_service.dart';
```

同時更新既有的「欄位對帳」測試。它是 `epic-41` 建立的對帳點，承諾「features 每個欄位都給非空值、逐一斷言」，新增欄位時必須同步：

1. 測試名稱中的 `'欄位對帳：features 13 個欄位＋book／sync／isEinkMode 皆給非空值，'` 改為 `'欄位對帳：features 14 個欄位＋book／sync／isEinkMode 皆給非空值，'`。
2. 在 `final searchRepository = FakeSearchRepository();` 之後新增：

   ```dart
      final importService = FakeBookImportService();
   ```

3. 在 `features = LibraryReaderFeatureRepositories(...)` 參數列的 `isFullTextSearchAvailable: false,` 之後新增：

   ```dart
        bookImportService: importService,
   ```

4. 在該測試既有 `expect(...)` 斷言區段的最後一行之後新增：

   ```dart
      expect(screen.bookImportService, same(importService));
   ```

上面新增的兩個獨立測試照樣保留：一個驗證單獨注入時會轉交，一個驗證未注入時預設為 null。

- [x] **Step 2：執行測試，確認失敗**

Run: `flutter test test/screens/reader_screen_route_test.dart`
Expected: 編譯錯誤 `The getter 'bookImportService' isn't defined for the type 'ReaderScreen'`。

- [x] **Step 3：最小實作**

`reader_screen.dart` import 區，在 `import '../library/library_repository.dart';` 之前新增（若尚未 import）：

```dart
import '../library/book_import_service.dart';
```

在 `ReaderScreen` 的 `final bool isFullTextSearchAvailable;` 之後新增欄位：

```dart
  /// epic-15-storage-permission Issue 0：書籍匯入服務，由
  /// `LibraryReaderFeatureRepositories.bookImportService` 經
  /// `buildReaderScreen` 轉交。供 Issue 2「檔案存取失效時重新連結書籍」
  /// 使用；`null` 時不提供重新連結功能（比照 [libraryRepository] 等既有
  /// 選用依賴的慣例，既有測試呼叫端零回歸）。
  final BookImportService? bookImportService;
```

在 `const ReaderScreen({...})` 參數列的 `this.isFullTextSearchAvailable = true,` 之後新增：

```dart
    this.bookImportService,
```

`reader_screen_route.dart` 的 `ReaderScreen(...)` 呼叫中，`isFullTextSearchAvailable: features.isFullTextSearchAvailable,` 之後新增：

```dart
    bookImportService: features.bookImportService,
```

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test test/screens/reader_screen_route_test.dart`
Expected: All tests passed（含既有的「欄位對帳」測試）。

- [x] **Step 5：Commit**

```bash
git add lib/screens/reader_screen.dart lib/screens/reader_screen_route.dart test/screens/reader_screen_route_test.dart
git commit -m "refactor(reader): ReaderScreen 新增 bookImportService 參數並由 buildReaderScreen 轉交（epic-15 Issue 0）"
```

---

### Task 3：閱讀器開單書搜尋時轉送 `bookImportService`，`main.dart` 填入實例

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`（`_openBookSearch` 內 `LibraryReaderFeatureRepositories(...)`，約第 1870 行）
- Modify: `app/lib/main.dart`（約第 515 行 `readerFeatureRepositories: LibraryReaderFeatureRepositories(...)`）
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 的 bundle 欄位、Task 2 的 `ReaderScreen.bookImportService`
- Produces: 無新介面。完成後，所有開啟閱讀器的路徑都能帶著匯入服務。

- [x] **Step 1：寫失敗的測試**

在 `reader_screen_test.dart` 中，找到既有測試「isFullTextSearchAvailable: false 時，推入的 BookSearchScreen 正確帶入 false（不落回預設值 true）」，在同一個 group 內緊接其後新增：

```dart
    testWidgets(
        'bookImportService 會轉送給推入的 BookSearchScreen'
        '（epic-15-storage-permission Issue 0：閱讀器→單書搜尋→閱讀器路徑不遺失）',
        (tester) async {
      final importService = FakeBookImportService();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_search_import_service',
            prefsManager: FakeReaderPrefsManager(),
            searchRepository: FakeSearchRepository(),
            libraryRepository: FakeLibraryRepository(),
            bookImportService: importService,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
      await tester.pumpAndSettle();

      final pushed =
          tester.widget<BookSearchScreen>(find.byType(BookSearchScreen));
      expect(pushed.readerFeatureRepositories.bookImportService,
          same(importService));
    });
```

若 `reader_screen_test.dart` 尚未 import 測試替身，補上：

```dart
import '../support/fake_book_import_service.dart';
```

- [x] **Step 2：執行測試，確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "bookImportService 會轉送給推入的 BookSearchScreen"`
Expected: FAIL。`Expected: same instance as <Instance of 'FakeBookImportService'>  Actual: <null>`。

- [x] **Step 3：最小實作**

`reader_screen.dart` 的 `_openBookSearch` 內，`LibraryReaderFeatureRepositories(...)` 參數列的 `isFullTextSearchAvailable: widget.isFullTextSearchAvailable,` 之後新增：

```dart
            // epic-15-storage-permission Issue 0：這裡是手動逐欄重建
            // bundle，新欄位必須一併轉送，否則「閱讀器→單書搜尋→閱讀器」
            // 開啟的閱讀器會遺失匯入服務、無法重新連結失效書籍。
            bookImportService: widget.bookImportService,
```

`main.dart` 的 `readerFeatureRepositories: LibraryReaderFeatureRepositories(...)` 參數列中，`searchRepository: widget.searchRepository,` 之後新增：

```dart
          // epic-15-storage-permission Issue 0：閱讀器在檔案存取失效時
          // 重新連結書籍需要匯入服務（Issue 2 使用），與上方
          // importService 參數是同一個實例。
          bookImportService: widget.importService,
```

- [x] **Step 4：執行測試，確認通過**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "BookSearchScreen"`
Expected: 所有名稱含 `BookSearchScreen` 的測試通過，包含新測試與既有的 `isFullTextSearchAvailable` 轉送測試。

- [x] **Step 5：確認 `main.dart` 有填入（Review Focus #2）**

Run: `grep -n "bookImportService: widget.importService" lib/main.dart`
Expected: 恰好 1 行輸出。

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add lib/screens/reader_screen.dart lib/main.dart test/screens/reader_screen_test.dart
git commit -m "refactor(reader): 閱讀器開單書搜尋時轉送 bookImportService，main.dart 填入實例（epic-15 Issue 0）"
```

---

### Task 4：`_ReaderScreenState` 改用 `_activeFilePath`（不改行為）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`：
  - `_ReaderScreenState` 欄位區，約第 340–352 行，`_errorMessage` 附近。
  - 15 處 `widget.filePath`，約在第 617、674、752、987、1677、1689、1723、1756、1779、1827、1834、2320、3334、3423、3504 行。行號可能因 Task 2、3 的新增而位移，請以 grep 為準。

**Interfaces:**
- Consumes: 無
- Produces: `_ReaderScreenState._activeFilePath`（`late String`，State 私有欄位）。Issue 1 用它判斷是否為 `content://`，Issue 2 在 Re-link 成功時更新它。

這個 Task 是純重構，沒有新的外部行為可以先寫失敗測試。驗證方式改為：改動前先確認相關測試全綠，改動後再跑同一組測試，並用 grep 斷言沒有漏改。

- [x] **Step 1：改動前先跑一次基準**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: All tests passed。記下通過的測試數量，Step 5 會拿來比對。

- [x] **Step 2：新增欄位**

在 `_ReaderScreenState` 的 `String? _errorMessage;` 之後新增：

```dart
  /// epic-15-storage-permission Issue 0：目前生效的書籍檔案路徑（`content://`
  /// URI 或本機路徑，見 ADR 0002）。初始值為建構參數 [ReaderScreen.filePath]；
  /// State 內一律讀取本欄位，不再直接讀 `widget.filePath`，讓 Issue 2 在
  /// 「重新連結」成功後能原地換成新路徑並重新開書。
  ///
  /// 使用 `late` 惰性初始化：第一次讀取發生在 `initState()` 的
  /// `_resolveEpubEngineDispatch()`（`widget.isFixedLayout` 為 null 時），
  /// 或延後到 `build()`（非 null 時該方法提早 return），兩者 `widget` 皆已
  /// 可用。
  ///
  /// 刻意不在 `didUpdateWidget` 跟隨 `widget.filePath` 變動：閱讀器一律由
  /// `MaterialPageRoute` 建立一次，沒有任何呼叫端會以不同 `filePath` 重建
  /// 同一個 `ReaderScreen`。
  late String _activeFilePath = widget.filePath;
```

- [x] **Step 3：取代 15 處 `widget.filePath`**

先列出目前所有位置：

Run: `grep -n "widget.filePath" lib/screens/reader_screen.dart`
Expected: 15 行（Step 2 新增的欄位初始化是第 16 處，不要改它）。

逐一把 `widget.filePath` 改成 `_activeFilePath`，共兩類：

- `detectBookFormat(widget.filePath)`，共 11 處，改成 `detectBookFormat(_activeFilePath)`。
- 其餘 4 處改成：
  - `repository.detectAndCacheEpubLayout(widget.bookId, _activeFilePath)`（`_resolveEpubEngineDispatch` 內）
  - 組裝 `Book` 的 `filePath: _activeFilePath,`（約第 1834 行，`_toBookFileFormat` 附近）
  - `FoliateReaderView(...)` 與 `PdfReaderView(...)` 的 `filePath: _activeFilePath,`（約第 3334、3423 行）

  這兩個閱讀視圖的 `key: _foliateEpubReaderViewKey`／`key: _pdfReaderViewKey` **保持不動**。

- [x] **Step 4：用 grep 斷言沒有漏改（Review Focus #3）**

Run: `grep -n "widget.filePath" lib/screens/reader_screen.dart`
Expected: 恰好 1 行，就是 `late String _activeFilePath = widget.filePath;`。

Run: `grep -n "key: _foliateEpubReaderViewKey\|key: _pdfReaderViewKey" lib/screens/reader_screen.dart`
Expected: 2 行，閱讀視圖的 GlobalKey 仍在。

Run: `grep -n "ValueKey(_activeFilePath)\|KeyedSubtree" lib/screens/reader_screen.dart`
Expected: 沒有輸出。

- [x] **Step 5：執行受影響測試，確認行為不變**

Run: `flutter test test/screens/reader_screen_test.dart test/screens/reader_screen_route_test.dart test/screens/library_search_screen_test.dart test/screens/book_search_screen_test.dart test/screens/library_screen_test.dart`
Expected: All tests passed。這 5 個是 issues.md Issue 0 列出的畫面測試，涵蓋所有經由 bundle 開啟閱讀器的路徑。

Step 1 的基準是在 Task 4 開始前跑的，那時 Task 3 新增的測試已經在裡面。所以 `reader_screen_test.dart` 的通過數量應該和 Step 1 **相同**，不多不少；數量不同就代表本 Task 改變了行為。

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6：Commit**

```bash
git add lib/screens/reader_screen.dart
git commit -m "refactor(reader): ReaderScreen State 改讀 _activeFilePath 取代 widget.filePath（epic-15 Issue 0）"
```

- [x] **Step 7：完整測試（issues.md Issue 0 明訂：本 Issue 大範圍改動 `ReaderScreen`）**

Run: `flutter test`
Expected: All tests passed（全專案約 1,800 個測試、約 5 分鐘）。若有失敗，先確認是否為 `docs/archive/*epic-37-test-suite-flakiness*` 記錄的既有不穩定測試：單獨重跑該檔案確認，並在 `epic.md` 記錄，不要為了讓它通過而修改本 Issue 範圍外的程式碼。

Run: `node tool/check_l10n_hardcoded_strings.js`
Expected: 無新增違規（本 Issue 不新增字串，這一步只是確認沒有意外）。

- [x] **Step 8：更新進度文件並 commit**

- 把 `docs/epics/epic-15-storage-permission/issues.md` Issue 0 的 `**Status:** ready-for-agent` 改為 `**Status:** completed`。
- 在 `docs/epics/epic-15-storage-permission/epic.md` 的「目前狀態」之前，新增一段 Issue 0 完成記錄，內容包含：完成日期、4 個 commit、完整 `flutter test` 的結果與執行時的 commit。
- 把 `docs/epics.md` 的 epic-15 備註改為 `Issue 0 已完成`。

```bash
git add ../docs/epics/epic-15-storage-permission/issues.md ../docs/epics/epic-15-storage-permission/epic.md ../docs/epics.md
git commit -m "docs(epic-15): 記錄 Issue 0 完成"
```
