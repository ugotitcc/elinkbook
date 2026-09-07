# Epic 36 Issue 6：收斂書架分頁狀態為 `LibraryPagingCursor` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `library_screen.dart` 裡散落的 7 個書架分頁狀態寫入點（`_currentPage`／`_lastPageSize` 兩個欄位）收斂進一個新的純 Dart 類別 `LibraryPagingCursor`，讓「分頁狀態何時該怎麼變」只有一個 module 負責，並補上目前唯一缺的迴歸測試（`review-plan-issue-3.md` M-2 越界殘留情境）。

**Architecture：** `LibraryPagingCursor` 是純 Dart 類別（不是 `ChangeNotifier`——分頁狀態只有 `_LibraryScreenState` 一個消費者），加進既有 `app/lib/screens/library_paging.dart`，包著同檔案既有的四個純函式（`libraryPageSizeForOrientation`／`libraryPageCount`／`libraryClampPage`／`libraryRecalculatePage`，皆不修改）。`_LibraryScreenState` 移除 `_currentPage`／`_lastPageSize` 兩個欄位，改持有一個 `final LibraryPagingCursor _paging`，原本 7 個直接寫欄位的地方全部改呼叫游標方法。`WidgetsBindingObserver`／`didChangeMetrics()` 整套機制維持不動，只是內部運算委派給游標——是否要讓 `build()` 單獨透過 `MediaQuery` 依賴處理旋轉是獨立問題，不在本計劃範圍內。

**Tech Stack：** Flutter 3.41.9、既有 `flutter_test`／`package:test` 慣例；`LibraryPagingCursor` 為 widget-free 的純 Dart 類別，用 `package:test`（`flutter_test` 匯出的 `test()`，非 `testWidgets()`）直接單元測試，不需要 pump widget。

**Spec：** `docs/epics/epic-36-adaptive-shelf-navigation/issues.md` Issue 6（此工單無獨立 `spec.md` 分節——是 Epic 5 個 Issue 全數合併後，`/improve-codebase-architecture` 架構回顧衍生的補強工單，設計細節經 `/grilling` Q1～Q10 十輪問答定案，完整脈絡見 `epic.md` 2026-09-07 條目）。

## Global Constraints

- 本工單**不影響任何 UI 元件、不改變任何畫面輸出或 `Key` 契約**——純粹是 `_LibraryScreenState` 內部狀態管理的重構，不影響 business logic 的可觀察行為（比照 `issues.md` 共同規則要求的四點說明：(1) 不改動任何 UI 元件本身 (2) 改的原因是分頁狀態的 7 個寫入點散落各處、locality 差 (3) 依賴它的畫面只有書架本身、且對外行為不變 (4) 不影響 business logic，純屬同一份邏輯換個地方放）。
- **不新增 `ChangeNotifier`**：`LibraryPagingCursor` 是 plain Dart 類別，`_LibraryScreenState` 呼叫其方法後自行 `setState(() {})`，游標本身不持有監聽者。
- **不觸碰 `WidgetsBindingObserver`／`didChangeMetrics()` 的存廢**：本工單只把 `didChangeMetrics()` 內部的換算邏輯委派給游標，`physicalSize.isEmpty` 暫態防護等既有邏輯原樣保留。
- **`goToNextPage()`／`goToPreviousPage()` 不加內部邊界防呆**：呼叫端（`PagingBar` 的 `onPrevious`/`onNext`）本來就只在合法範圍內才會把 callback 傳進去，比照 `CLAUDE.md`「不要為不可能發生的情境寫防禦」。
- 每個 Task 完成後只跑該 Task 實際觸及的測試檔；全套 `flutter test`（不帶路徑）留到最後一個 Task 收尾時執行一次（比照 `CLAUDE.md`「測試執行範圍」）。
- `flutter analyze` 必須在每個 Task 結束時保持乾淨（`No issues found!`）。
- 任何 Task 的收尾 Commit 前，該 Task 實際觸及的測試檔必須 100% PASS，不得把已知失敗留到下一個 Task 才修（`review-plan-issue-2.md` I-1 教訓沿用）。

---

## Task 1：`LibraryPagingCursor`（純 Dart 游標類別＋單元測試，含 M-2 迴歸測試）

**Files:**
- Modify: `app/lib/screens/library_paging.dart`
- Modify: `app/test/screens/library_paging_test.dart`

**Interfaces:**
- Consumes: 同檔案既有純函式 `libraryPageSizeForOrientation`／`libraryPageCount`／`libraryClampPage`／`libraryRecalculatePage`（不修改，不需額外 import）。
- Produces: `class LibraryPagingCursor`：`int get currentPage`；`({int pageCount, int pageSize}) clamp({required int itemCount, required Orientation orientation})`；`bool applyOrientationChange(Orientation orientation)`（回傳是否真的觸發了比例換算，供呼叫端判斷要不要 `setState()`，見 `review-plan-issue-6.md` I-1）；`void goToNextPage()`；`void goToPreviousPage()`；`void resetToFirstPage()`。

- [ ] **Step 1: 寫失敗測試**

在 `app/test/screens/library_paging_test.dart` 現有四個純函式測試之後（`main()` 結尾 `}` 之前）新增：

```dart
  group('LibraryPagingCursor', () {
    test('初始 currentPage 為 0', () {
      final cursor = LibraryPagingCursor();
      expect(cursor.currentPage, 0);
    });

    test('clamp()：itemCount 在範圍內時回傳正確 pageCount／pageSize，頁碼維持不變', () {
      final cursor = LibraryPagingCursor();
      final result = cursor.clamp(itemCount: 10, orientation: Orientation.portrait);
      expect(result.pageCount, 4); // libraryPageCount(10, 3) = 4
      expect(result.pageSize, 3);
      expect(cursor.currentPage, 0);
    });

    test('clamp()：itemCount 縮小時箝制頁碼並回傳新 pageCount（越界情境）', () {
      final cursor = LibraryPagingCursor();
      cursor.clamp(itemCount: 10, orientation: Orientation.portrait); // pageSize=3, pageCount=4
      cursor.goToNextPage();
      cursor.goToNextPage();
      cursor.goToNextPage();
      expect(cursor.currentPage, 3); // 走到最後一頁（0-based）

      // 模擬刪書：itemCount 驟降為 2，合法頁碼只剩 0（pageCount=1）。
      final result = cursor.clamp(itemCount: 2, orientation: Orientation.portrait);
      expect(result.pageCount, 1);
      expect(cursor.currentPage, 0);
    });

    test(
      'clamp()：itemCount 為 0（空書庫）時回傳 pageCount 1，頁碼維持 0'
      '（review-plan-issue-6.md M-1）',
      () {
        final cursor = LibraryPagingCursor();
        final result = cursor.clamp(itemCount: 0, orientation: Orientation.portrait);
        expect(result.pageCount, 1); // libraryPageCount(0, 3) = 1
        expect(result.pageSize, 3);
        expect(cursor.currentPage, 0);
      },
    );

    test('applyOrientationChange()：方向未變時不觸發比例換算，回傳 false', () {
      final cursor = LibraryPagingCursor();
      cursor.clamp(itemCount: 10, orientation: Orientation.portrait);
      cursor.goToNextPage();
      expect(cursor.currentPage, 1);

      final changed = cursor.applyOrientationChange(Orientation.portrait);
      expect(changed, isFalse, reason: '方向沒變，不應該觸發比例換算');
      expect(cursor.currentPage, 1);
    });

    test('applyOrientationChange()：方向改變時依比例換算頁碼，回傳 true', () {
      final cursor = LibraryPagingCursor();
      cursor.clamp(itemCount: 10, orientation: Orientation.portrait); // pageSize=3
      cursor.goToNextPage();
      cursor.goToNextPage();
      expect(cursor.currentPage, 2); // 第一項全域 index = 6

      final changed = cursor.applyOrientationChange(Orientation.landscape); // newPageSize=4
      expect(changed, isTrue);
      expect(
        cursor.currentPage,
        1,
        reason:
            'libraryRecalculatePage(oldPage: 2, oldPageSize: 3, newPageSize: 4) = 6 ~/ 4 = 1',
      );
    });

    test(
      'applyOrientationChange()：冷啟動（尚未呼叫過 clamp()）時直接旋轉，'
      '不拋例外、頁碼維持 0、回傳 false（review-plan-issue-6.md M-1）',
      () {
        final cursor = LibraryPagingCursor();
        final changed = cursor.applyOrientationChange(Orientation.landscape);
        expect(changed, isFalse, reason: '_lastPageSize 尚未有值，沒有換算基準，不應該換算');
        expect(cursor.currentPage, 0);
      },
    );

    test('goToNextPage()／goToPreviousPage()：頁碼各自 +1／-1', () {
      final cursor = LibraryPagingCursor();
      cursor.goToNextPage();
      cursor.goToNextPage();
      expect(cursor.currentPage, 2);
      cursor.goToPreviousPage();
      expect(cursor.currentPage, 1);
    });

    test('resetToFirstPage()：頁碼歸零', () {
      final cursor = LibraryPagingCursor();
      cursor.clamp(itemCount: 10, orientation: Orientation.landscape);
      cursor.goToNextPage();
      cursor.resetToFirstPage();
      expect(cursor.currentPage, 0);
    });

    test(
      'review-plan-issue-3.md M-2 情境迴歸測試：clamp() 箝制後的頁碼才是 '
      'applyOrientationChange() 的換算基準，不會用到過期的越界頁碼',
      () {
        final cursor = LibraryPagingCursor();
        // 10 本書，portrait（pageSize=3，pageCount=4），走到最後一頁 page=3
        // （第一項全域 index = 9）。
        cursor.clamp(itemCount: 10, orientation: Orientation.portrait);
        cursor.goToNextPage();
        cursor.goToNextPage();
        cursor.goToNextPage();
        expect(cursor.currentPage, 3);

        // 模擬刪書：itemCount 驟降為 2（pageCount=1），build() 呼叫
        // clamp() 應把 currentPage 箝制回 0，而不是留著越界的 3。
        cursor.clamp(itemCount: 2, orientation: Orientation.portrait);
        expect(
          cursor.currentPage,
          0,
          reason: 'itemCount 縮小後應立即箝制，不殘留越界頁碼',
        );

        // 緊接著旋轉螢幕（portrait→landscape，pageSize 3→4）。若換算基準
        // 用的是箝制前的過期頁碼 3，libraryRecalculatePage(oldPage: 3,
        // oldPageSize: 3, newPageSize: 4) = 9 ~/ 4 = 2，會對這 2 本書
        // 而言算出一個同樣越界的頁碼；用箝制後的頁碼 0，結果應為 0。
        cursor.applyOrientationChange(Orientation.landscape);
        expect(
          cursor.currentPage,
          0,
          reason: '換算基準必須是 clamp() 箝制後的頁碼，不是過期的越界值',
        );
      },
    );
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/library_paging_test.dart`
Expected: FAIL（`LibraryPagingCursor` 類別不存在，編譯錯誤）

- [ ] **Step 3: 實作**

在 `app/lib/screens/library_paging.dart` 既有四個函式之後（檔案結尾）新增：

```dart

/// 書架分頁狀態的唯一負責者（epic-36 Issue 6，架構回顧衍生）：取代原本
/// 散落在 `LibraryScreen` 的 `build()`／`didChangeMetrics()`／排序/分類
/// 切換/換頁按鈕共 7 處各自寫入的 `_currentPage`／`_lastPageSize` 欄位。
///
/// 純 Dart 類別，不是 `ChangeNotifier`——分頁狀態只有 `_LibraryScreenState`
/// 一個消費者，不需要監聽機制；呼叫端在呼叫任一方法後自行 `setState(() {})`。
class LibraryPagingCursor {
  int _currentPage = 0;
  int? _lastPageSize;

  int get currentPage => _currentPage;

  /// `build()` 每次呼叫一次：依目前 [itemCount]／[orientation] 箝制頁碼到
  /// 合法範圍，回傳目前 `pageCount` 與 `pageSize`。不做旋轉的比例換算
  /// （那是 [applyOrientationChange] 的職責）——單純箝制，用來吸收刪除
  /// 書籍／合併分類等造成 `itemCount` 縮小時的越界殘留（原
  /// `review-plan-issue-3.md` M-2）。回傳值一併帶出 `pageSize`，讓呼叫端
  /// 不需要再另外呼叫一次 `libraryPageSizeForOrientation()`
  /// （`review-plan-issue-6.md` I-2）。
  ({int pageCount, int pageSize}) clamp({
    required int itemCount,
    required Orientation orientation,
  }) {
    final pageSize = libraryPageSizeForOrientation(orientation);
    final pageCount = libraryPageCount(itemCount, pageSize);
    _currentPage = libraryClampPage(_currentPage, pageCount);
    _lastPageSize = pageSize;
    return (pageCount: pageCount, pageSize: pageSize);
  }

  /// `didChangeMetrics()` 呼叫：偵測到真正的方向改變（跟上一次 [clamp]
  /// 或本方法記錄的每頁筆數不同）時，才依「目前頁第一項的全域 index ÷
  /// 新每頁容量」按比例換算頁碼，並回傳 `true`；方向沒變時
  /// （`_lastPageSize` 相同，或尚未有任何記錄）不做任何事、回傳
  /// `false`。**回傳值的用途**：`didChangeMetrics()` 不只在裝置旋轉時
  /// 觸發，軟體鍵盤彈出/收起、分螢調整、系統狀態列顯隱等 metrics 變化
  /// 都會觸發——呼叫端須依回傳值判斷是否真的需要 `setState()`，不能無
  /// 條件重繪，否則會在這些無關情境下也觸發整頁 rebuild，在 E-Ink
  /// 裝置上造成非必要刷新（`review-plan-issue-6.md` I-1）。
  bool applyOrientationChange(Orientation orientation) {
    final newPageSize = libraryPageSizeForOrientation(orientation);
    final oldPageSize = _lastPageSize;
    _lastPageSize = newPageSize;
    if (oldPageSize != null && oldPageSize != newPageSize) {
      _currentPage = libraryRecalculatePage(
        oldPage: _currentPage,
        oldPageSize: oldPageSize,
        newPageSize: newPageSize,
      );
      return true;
    }
    return false;
  }

  /// 呼叫端（`PagingBar.onNext`）保證只在合法範圍內才會觸發，故不做內部
  /// 邊界防呆（`CLAUDE.md`「不要為不可能發生的情境寫防禦」）。
  void goToNextPage() => _currentPage++;

  /// 同 [goToNextPage]，呼叫端（`PagingBar.onPrevious`）保證只在合法範圍
  /// 內才會觸發。
  void goToPreviousPage() => _currentPage--;

  /// 排序條件／搜尋關鍵字／分類下鑽切換時呼叫，重置為第一頁。
  void resetToFirstPage() => _currentPage = 0;
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/library_paging_test.dart`
Expected: PASS（全部案例，含既有四個純函式測試與本次新增的 `LibraryPagingCursor` group）

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

**（`review-plan-issue-6.md` M-2：commit 訊息一律用多個 `-m` 參數，不用 Bash 專用的 `cat <<'EOF'` heredoc——本專案 Issue 1～5 既有計劃書皆為此格式，heredoc 在 Windows PowerShell 下 `<` 會被當保留字報錯。）**

```bash
git add app/lib/screens/library_paging.dart app/test/screens/library_paging_test.dart
git commit -m "feat(epic-36): 新增 LibraryPagingCursor 收斂書架分頁狀態轉換邏輯" -m "純 Dart 游標類別，包著既有分頁純函式，鎖住 review-plan-issue-3.md M-2 越界殘留情境的迴歸測試。library_screen.dart 尚未串接，下個 Task 處理。" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018cGrtkUbvK5UfG3aZdLCfT"
```

---

## Task 2：`library_screen.dart` 串接 `LibraryPagingCursor`（7 個呼叫點遷移）

本 Task 是純重構（行為不變、只換內部實作），既有 widget test 本身就是這次遷移的回歸安全網，因此不走「先寫新失敗測試」的標準 TDD 開頭，改為「遷移前確認基準綠燈 → 實作 → 遷移後確認仍是綠燈」。

**Files:**
- Modify: `app/lib/screens/library_screen.dart`

**Interfaces:**
- Consumes: Task 1 的 `LibraryPagingCursor`（`currentPage`／`clamp()`→`({int pageCount, int pageSize})`／`applyOrientationChange()`→`bool`／`goToNextPage()`／`goToPreviousPage()`／`resetToFirstPage()`）。
- Produces: `_LibraryScreenState` 不再有 `_currentPage`／`_lastPageSize` 欄位，改持有 `final LibraryPagingCursor _paging`；對外行為（畫面輸出、`Key` 契約）完全不變。

- [ ] **Step 1: 確認遷移前基準——這批既有測試目前全數 PASS**

Run: `flutter test test/screens/library_screen_test.dart --name "裝置旋轉（MediaQuery 從直立變橫放）後|點擊 PagingBar 下一頁/上一頁切換書架顯示的書籍|旋轉螢幕時目前頁碼依新每頁容量正確換算，不跳到看不懂的地方|切換排序條件後頁碼重置為第一頁|進入/離開分類下鑽時頁碼重置為第一頁"`
Expected: PASS（全部案例，這是本 Task 唯一要保持不變的行為基準）

- [ ] **Step 2: 實作——5 處編輯**

編輯 `app/lib/screens/library_screen.dart`：

**2a. 欄位宣告**：`_currentPage`／`_lastPageSize` 兩個欄位改為單一 `_paging` 欄位。

Before:
```dart
  String? _activeGroupFilter;
  LibraryViewMode _viewMode = LibraryViewMode.grid;
  Set<String>? _selectedBookIds;
  final Set<String> _redownloadingBookIds = {};

  /// 目前頁碼（0-based）。分頁筆數固定依螢幕方向決定（見
  /// `library_paging.dart`），排序/分類切換時重置為 0，旋轉螢幕時依
  /// `libraryRecalculatePage()` 換算，其餘情況（管理分類、格狀/清單
  /// 切換）維持不變，見 plans/plan-issue-3.md「計劃範圍澄清」第 4、5 點。
  int _currentPage = 0;

  /// `didChangeMetrics()` 用來跟「新方向換算出的每頁筆數」比較，判斷是否
  /// 真的需要重新換算頁碼；於每次 `_buildBookList()` 呼叫後更新為最新值。
  int? _lastPageSize;

  /// 使用者最後閱讀的書籍（`lastReadTime` 最新且 > epoch 0 者），供頂層
  /// 書架的常駐「繼續閱讀列」使用；`_onBookListChanged()` 每次書籍清單
  /// 變動時重新計算。
  Book? _mostRecentBook;
```

After:
```dart
  String? _activeGroupFilter;
  LibraryViewMode _viewMode = LibraryViewMode.grid;
  Set<String>? _selectedBookIds;
  final Set<String> _redownloadingBookIds = {};

  /// 書架分頁狀態的唯一負責者（epic-36 Issue 6，架構回顧衍生）：取代原本
  /// 散落在 `build()`／`didChangeMetrics()`／排序/分類切換/換頁按鈕共 7
  /// 處各自寫入的 `_currentPage`／`_lastPageSize` 欄位，見
  /// `plans/plan-issue-6.md`。**與 `issues.md` Issue 6 原文寫的
  /// `late final` 不同，這裡改用 eager 的 `final`**：`LibraryPagingCursor()`
  /// 建構子不依賴 `widget`／`context`，不需要等到 `initState()` 才能
  /// 具現化，用 `late` 只會多一層執行期延遲初始化檢查，沒有實質好處
  /// （`review-plan-issue-6.md` M-3）。
  final LibraryPagingCursor _paging = LibraryPagingCursor();

  /// 使用者最後閱讀的書籍（`lastReadTime` 最新且 > epoch 0 者），供頂層
  /// 書架的常駐「繼續閱讀列」使用；`_onBookListChanged()` 每次書籍清單
  /// 變動時重新計算。
  Book? _mostRecentBook;
```

**2b. `didChangeMetrics()`**：換算邏輯委派給游標。

Before:
```dart
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final physicalSize = View.of(context).physicalSize;
    // App 退到背景、螢幕休眠、多視窗模式調整分割大小、可折疊裝置展開
    // 過渡瞬間，physicalSize 可能暫時回報為 0x0——此時 `0 > 0` 為
    // false，會被誤判為 portrait，若裝置原本是 landscape
    // （`_lastPageSize == 4`）就會觸發一次錯誤的頁碼換算。直接略過這種
    // 暫態，等下一次真正有效的 metrics 變化再處理（`review-plan-issue-3.md`
    // I-2）。
    if (physicalSize.isEmpty) return;
    final newOrientation = physicalSize.width > physicalSize.height
        ? Orientation.landscape
        : Orientation.portrait;
    final newPageSize = libraryPageSizeForOrientation(newOrientation);
    final oldPageSize = _lastPageSize;
    if (oldPageSize != null && oldPageSize != newPageSize) {
      setState(() {
        _currentPage = libraryRecalculatePage(
          oldPage: _currentPage,
          oldPageSize: oldPageSize,
          newPageSize: newPageSize,
        );
      });
    }
    _lastPageSize = newPageSize;
  }
```

After:
```dart
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final physicalSize = View.of(context).physicalSize;
    // App 退到背景、螢幕休眠、多視窗模式調整分割大小、可折疊裝置展開
    // 過渡瞬間，physicalSize 可能暫時回報為 0x0——此時 `0 > 0` 為
    // false，會被誤判為 portrait，若裝置原本是 landscape 就會觸發一次
    // 錯誤的頁碼換算。直接略過這種暫態，等下一次真正有效的 metrics
    // 變化再處理（`review-plan-issue-3.md` I-2）。
    if (physicalSize.isEmpty) return;
    final newOrientation = physicalSize.width > physicalSize.height
        ? Orientation.landscape
        : Orientation.portrait;
    // didChangeMetrics() 不只在裝置旋轉時觸發，軟體鍵盤彈出/收起、分螢
    // 調整、系統狀態列顯隱等都會觸發——只有 applyOrientationChange()
    // 真的換算過頁碼（方向改變）才需要 setState()，避免 E-Ink 裝置在
    // 無關的 metrics 變化時也跟著整頁重繪（`review-plan-issue-6.md` I-1）。
    final hasChanged = _paging.applyOrientationChange(newOrientation);
    if (hasChanged) {
      setState(() {});
    }
  }
```

**2c. `_openGroupFilteredView`／`_exitGroupFilteredView`**：重置頁碼改呼叫游標。

Before:
```dart
  void _openGroupFilteredView(String groupName) {
    setState(() {
      _activeGroupFilter = groupName;
      _currentPage = 0;
    });
  }

  void _exitGroupFilteredView() {
    setState(() {
      _activeGroupFilter = null;
      _currentPage = 0;
    });
  }
```

After:
```dart
  void _openGroupFilteredView(String groupName) {
    setState(() {
      _activeGroupFilter = groupName;
      _paging.resetToFirstPage();
    });
  }

  void _exitGroupFilteredView() {
    setState(() {
      _activeGroupFilter = null;
      _paging.resetToFirstPage();
    });
  }
```

**2d. `_changeSortBy`**：重置頁碼改呼叫游標。

Before:
```dart
  void _changeSortBy(LibrarySortBy sortBy) {
    setState(() => _currentPage = 0);
    _bookListController.changeSortBy(sortBy);
  }
```

After:
```dart
  void _changeSortBy(LibrarySortBy sortBy) {
    setState(() => _paging.resetToFirstPage());
    _bookListController.changeSortBy(sortBy);
  }
```

**2e. `_buildBookList()`——箝制寫回區塊**：改呼叫 `_paging.clamp()`，不再自己算 `safePage`／同步寫回欄位。

Before:
```dart
    final orientation = MediaQuery.orientationOf(context);
    final pageSize = libraryPageSizeForOrientation(orientation);
    _lastPageSize = pageSize;
    final pageCount = libraryPageCount(itemCount, pageSize);
    final safePage = libraryClampPage(_currentPage, pageCount);
    // 同步寫回欄位本身（純賦值，非 setState——目前這次 build 已經在用
    // safePage 渲染，不需要立即再觸發一次重建；純粹是讓 _currentPage
    // 欄位不殘留越界值）。若不同步，批次刪除書籍導致 itemCount 縮減、
    // 使用者又沒有手動點過 PagingBar 時，_currentPage 會一直停留在舊的
    // 越界值，之後旋轉螢幕時 didChangeMetrics() 會拿這個越界值當
    // oldPage 去換算，得出進一步錯誤的頁碼（`review-plan-issue-3.md`
    // M-2）。比照上方 `_lastPageSize = pageSize;` 同樣的既有寫法。
    _currentPage = safePage;
    final pageStart = safePage * pageSize;
    final pageEnd = (pageStart + pageSize).clamp(0, itemCount);
```

After:
```dart
    final orientation = MediaQuery.orientationOf(context);
    // 箝制頁碼＋取得目前 pageCount／pageSize 全交給 LibraryPagingCursor
    // （epic-36 Issue 6）——刪書後 itemCount 縮減導致的越界殘留（原
    // `review-plan-issue-3.md` M-2）由 clamp() 內部保證修正；pageSize
    // 直接複用 clamp() 回傳值，不再另外呼叫一次
    // libraryPageSizeForOrientation()（`review-plan-issue-6.md` I-2）。
    final result = _paging.clamp(itemCount: itemCount, orientation: orientation);
    final pageCount = result.pageCount;
    final pageSize = result.pageSize;
    final safePage = _paging.currentPage;
    final pageStart = safePage * pageSize;
    final pageEnd = (pageStart + pageSize).clamp(0, itemCount);
```

**2f. `PagingBar` 建構——`onPrevious`／`onNext`**：改呼叫游標的 `goToPreviousPage()`／`goToNextPage()`。

Before:
```dart
        PagingBar(
          key: const Key('library_paging_bar'),
          currentPage: safePage,
          pageCount: pageCount,
          onPrevious:
              safePage > 0 ? () => setState(() => _currentPage = safePage - 1) : null,
          onNext: safePage < pageCount - 1
              ? () => setState(() => _currentPage = safePage + 1)
              : null,
          isEinkMode: widget.themeDependencies.isEinkMode,
        ),
```

After:
```dart
        PagingBar(
          key: const Key('library_paging_bar'),
          currentPage: safePage,
          pageCount: pageCount,
          onPrevious:
              safePage > 0 ? () => setState(() => _paging.goToPreviousPage()) : null,
          onNext: safePage < pageCount - 1
              ? () => setState(() => _paging.goToNextPage())
              : null,
          isEinkMode: widget.themeDependencies.isEinkMode,
        ),
```

- [ ] **Step 3: 執行同一批測試，確認遷移後仍然全數 PASS**

Run: `flutter test test/screens/library_screen_test.dart --name "裝置旋轉（MediaQuery 從直立變橫放）後|點擊 PagingBar 下一頁/上一頁切換書架顯示的書籍|旋轉螢幕時目前頁碼依新每頁容量正確換算，不跳到看不懂的地方|切換排序條件後頁碼重置為第一頁|進入/離開分類下鑽時頁碼重置為第一頁"`
Expected: PASS（與 Step 1 基準一致，行為零回歸）

- [ ] **Step 4: 執行整個 `library_screen_test.dart`，確認沒有旁支回歸**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: PASS（全部案例，0 失敗——本 Task 收尾 Commit 前必須全綠，`review-plan-issue-2.md` I-1 教訓）

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: 執行整份 Epic 收尾要求的完整測試套件**

Run: `flutter test`
Expected: PASS（全部案例——本 Task 是 Epic 36 Issue 6，屬於 Epic 全數完成後的最後一個 Issue，比照 `issues.md`「收尾提醒」規範跑一次完整套件確認無全域回歸）

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/library_screen.dart
git commit -m "refactor(epic-36): library_screen.dart 改用 LibraryPagingCursor 收斂分頁狀態" -m "7 個原本各自寫入 _currentPage/_lastPageSize 的地方（build() 箝制寫回、didChangeMetrics() 旋轉換算、分類/排序切換重置、換頁按鈕 ±1）全部改呼叫 LibraryPagingCursor 方法，兩個欄位從 _LibraryScreenState 移除。純重構，行為與既有測試斷言不變。" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018cGrtkUbvK5UfG3aZdLCfT"
```

---

## 收尾提醒

- Task 2 完成即代表 Issue 6 完成。完成後把 `issues.md` Issue 6 的 `Status:` 從 `ready-for-agent` 改為 `completed`，`epic.md` 補一則完成記錄，`docs/epics.md` 該列備註同步更新為「Issue 6 已完成」。
- 依 `CLAUDE.md`「審查一律先產出報告，嚴禁直接修改」規則，完成後應發起 `/superpowers:requesting-code-review`，審查報告存於 `docs/epics/epic-36-adaptive-shelf-navigation/reviews/review-issue-6.md`，交由人類決定是否合併。
