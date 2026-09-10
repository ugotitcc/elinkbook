# Epic 36 Issue 7：書架每頁列數改為動態計算 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 書架每頁顯示的列數改為依裝置實際可用高度動態計算（不再寫死「1 行」），維持 `PagingBar`／`LibraryPagingCursor` 離散換頁架構不變。

**Architecture:** 新增純函式 `libraryRowsForHeight()` 依可用高度算出可完整顯示的列數；`LibraryPagingCursor.clamp()`／`applyOrientationChange()` 兩個方法合併為一個（因為 pageSize 現在只有 `build()` 執行當下、`LayoutBuilder` 量測完成後才知道正確值）；`_buildBookList()` 用 `LayoutBuilder` 量測 Grid 區域實際可用寬高，換算出 `pageSize = crossAxisCount * rows` 後才呼叫 `_paging.clamp()`；`PagingBar` 因此必須移進 `LayoutBuilder` 的回傳子樹（與量測結果同一次 build 產生），不再是外層 `Column` 的獨立 sibling。

**Tech Stack:** Flutter/Dart，`flutter_test`（widget test + 純 Dart unit test）。

**Spec:** `docs/epics/epic-36-adaptive-shelf-navigation/issues.md` Issue 7（本計劃的技術設計完全承接該處已定案的 Solution 段落，不重新論證）。

## Global Constraints

- `flutter analyze` 全程須維持乾淨（"No issues found!"）。
- 每個 Task 只跑「這次異動實際觸及」的測試檔，不需每次重跑全套；本計劃最後一個 Task 才跑一次完整 `flutter test`（比照 `CLAUDE.md`「測試執行範圍」規範）。
- `LibraryPagingCursor.goToNextPage()`／`goToPreviousPage()` 不加內部邊界防呆——呼叫端保證只在合法範圍內才會觸發（`CLAUDE.md`「不要為不可能發生的情境寫防禦」，Issue 6 既有慣例延續）。
- Commit message 一律用多個 `-m` 參數，不使用 Bash heredoc（PowerShell 環境 `<` 為保留字元，`review-plan-issue-6.md` M-2 已確認的慣例）。
- 提交前務必先 `git status` 確認只有本計劃預期異動的檔案被加入暫存區。

---

### Task 1：新增純函式 `libraryRowsForHeight()`

**Files:**
- Modify: `app/lib/screens/library_paging.dart`
- Test: `app/test/screens/library_paging_test.dart`

**Interfaces:**
- Produces: `int libraryRowsForHeight({required double availableHeight, required double rowContentHeight, required double rowSpacing})`——供 Task 4 的 `_buildBookList()` 呼叫。

- [ ] **Step 1: 寫失敗測試**

在 `app/test/screens/library_paging_test.dart` 檔案最上方（`libraryPageSizeForOrientation` 測試之前）新增：

```dart
  group('libraryRowsForHeight', () {
    test('一般情況：無條件捨去到能完整放下的列數', () {
      // 3 列總高度 = 3*100 + 2*10 = 320；4 列總高度 = 4*100 + 3*10 = 430；
      // availableHeight=350 能放下 3 列但放不下 4 列。
      expect(
        libraryRowsForHeight(
          availableHeight: 350,
          rowContentHeight: 100,
          rowSpacing: 10,
        ),
        3,
      );
    });

    test('邊界值：availableHeight 恰好等於 n 列總高度時回傳 n（不多算不少算）', () {
      // 2 列總高度 = 2*100 + 1*10 = 210，恰好等於 availableHeight。
      expect(
        libraryRowsForHeight(
          availableHeight: 210,
          rowContentHeight: 100,
          rowSpacing: 10,
        ),
        2,
      );
    });

    test('availableHeight 小於一列高度時保底回傳 1（不回傳 0，避免空白頁）', () {
      expect(
        libraryRowsForHeight(
          availableHeight: 50,
          rowContentHeight: 100,
          rowSpacing: 10,
        ),
        1,
      );
      expect(
        libraryRowsForHeight(
          availableHeight: 0,
          rowContentHeight: 100,
          rowSpacing: 10,
        ),
        1,
      );
      expect(
        libraryRowsForHeight(
          availableHeight: -20,
          rowContentHeight: 100,
          rowSpacing: 10,
        ),
        1,
      );
    });

    test('rowContentHeight <= 0（異常輸入防禦）安全回傳 1，不除以零', () {
      expect(
        libraryRowsForHeight(
          availableHeight: 500,
          rowContentHeight: 0,
          rowSpacing: 10,
        ),
        1,
      );
      expect(
        libraryRowsForHeight(
          availableHeight: 500,
          rowContentHeight: -5,
          rowSpacing: 10,
        ),
        1,
      );
    });
  });

```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/library_paging_test.dart`（於 `app/` 目錄下執行）
Expected: 編譯失敗（`libraryRowsForHeight` 未定義）。

- [ ] **Step 3: 實作最小函式**

在 `app/lib/screens/library_paging.dart`，於 `libraryRecalculatePage()` 函式之後（`LibraryPagingCursor` 類別之前）新增：

```dart
/// 依可用高度計算書架每頁可完整顯示的列數（epic-36 Issue 7，取代 Issue 3
/// 寫死「1 行」的舊假設）。[availableHeight] 為扣除 AppBar／搜尋列／繼續
/// 閱讀列／`PagingBar`／Grid 自身 padding 等 chrome 後的實際可用高度
/// （呼叫端透過 `LayoutBuilder` 量測取得，見 `library_screen.dart`
/// `_buildBookList()`；`review-plan-issue-7.md` C-1：呼叫端務必記得扣除
/// `GridView` 自身上下 padding，不只是 `PagingBar` 高度）；[rowContentHeight]
/// 為單列高度（含封面與文字說明區的整個 cell 高度）；[rowSpacing] 為列間
/// 距。無條件捨去，且保底至少 1 行（即便完全放不下也顯示 1 行，不出現 0
/// 行空白頁）。
int libraryRowsForHeight({
  required double availableHeight,
  required double rowContentHeight,
  required double rowSpacing,
}) {
  if (rowContentHeight <= 0) return 1;
  // n 列總高度 = n*rowContentHeight + (n-1)*rowSpacing <= availableHeight。
  // 除法前加極小容差 1e-5，避免理論上剛好整除的邊界值因浮點誤差算成
  // 「N - 極小值」而被 floor() 多捨去 1 列（review-plan-issue-7.md M-2）。
  final rows =
      ((availableHeight + rowSpacing + 1e-5) / (rowContentHeight + rowSpacing))
          .floor();
  return rows < 1 ? 1 : rows;
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/library_paging_test.dart`
Expected: 全數通過（含既有 `LibraryPagingCursor` 測試，本步驟尚未改動它們）。

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/library_paging.dart app/test/screens/library_paging_test.dart
git commit -m "feat(epic-36): 新增 libraryRowsForHeight() 純函式" \
  -m "依可用高度計算書架每頁可完整顯示的列數，供 Issue 7 動態列數計算使用。" \
  -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" \
  -m "Claude-Session: https://claude.ai/code/session_018cGrtkUbvK5UfG3aZdLCfT"
```

---

### Task 2：`LibraryPagingCursor.clamp()`／`applyOrientationChange()` 合併為一個方法

**Files:**
- Modify: `app/lib/screens/library_paging.dart`
- Test: `app/test/screens/library_paging_test.dart`

**Interfaces:**
- Consumes: 無（純 Dart 類別內部重構）。
- Produces: `int LibraryPagingCursor.clamp({required int itemCount, required int pageSize})`——取代原本 `({int pageCount, int pageSize}) clamp({required int itemCount, required Orientation orientation})` 與 `bool applyOrientationChange(Orientation orientation)` 兩個方法。供 Task 4 的 `_buildBookList()` 呼叫。

- [ ] **Step 1: 改寫測試（先讓它們對新簽章失敗）**

用以下內容**整段取代** `app/test/screens/library_paging_test.dart` 裡 `group('LibraryPagingCursor', () { ... });` 整個區塊（Step 1 新增的 `libraryRowsForHeight` group 之後、檔案原本的 `group('LibraryPagingCursor', ...)` 位置）：

```dart
  group('LibraryPagingCursor', () {
    test('初始 currentPage 為 0', () {
      final cursor = LibraryPagingCursor();
      expect(cursor.currentPage, 0);
    });

    test('clamp()：itemCount 在範圍內時回傳正確 pageCount，頁碼維持不變', () {
      final cursor = LibraryPagingCursor();
      final pageCount = cursor.clamp(itemCount: 10, pageSize: 3);
      expect(pageCount, 4); // libraryPageCount(10, 3) = 4
      expect(cursor.currentPage, 0);
    });

    test('clamp()：itemCount 縮小時箝制頁碼並回傳新 pageCount（越界情境）', () {
      final cursor = LibraryPagingCursor();
      cursor.clamp(itemCount: 10, pageSize: 3); // pageCount=4
      cursor.goToNextPage();
      cursor.goToNextPage();
      cursor.goToNextPage();
      expect(cursor.currentPage, 3); // 走到最後一頁（0-based）

      // 模擬刪書：itemCount 驟降為 2，合法頁碼只剩 0（pageCount=1）。
      final pageCount = cursor.clamp(itemCount: 2, pageSize: 3);
      expect(pageCount, 1);
      expect(cursor.currentPage, 0);
    });

    test(
      'clamp()：itemCount 為 0（空書庫）時回傳 pageCount 1，頁碼維持 0'
      '（review-plan-issue-6.md M-1）',
      () {
        final cursor = LibraryPagingCursor();
        final pageCount = cursor.clamp(itemCount: 0, pageSize: 3);
        expect(pageCount, 1); // libraryPageCount(0, 3) = 1
        expect(cursor.currentPage, 0);
      },
    );

    test('clamp()：pageSize 未改變時不觸發比例換算，頁碼維持原值', () {
      final cursor = LibraryPagingCursor();
      cursor.clamp(itemCount: 10, pageSize: 3);
      cursor.goToNextPage();
      expect(cursor.currentPage, 1);

      cursor.clamp(itemCount: 10, pageSize: 3);
      expect(cursor.currentPage, 1, reason: 'pageSize 沒變，不應該觸發比例換算');
    });

    test('clamp()：pageSize 改變時（旋轉/視窗高度變化）先依比例換算才箝制', () {
      final cursor = LibraryPagingCursor();
      cursor.clamp(itemCount: 10, pageSize: 3); // pageSize=3
      cursor.goToNextPage();
      cursor.goToNextPage();
      expect(cursor.currentPage, 2); // 第一項全域 index = 6

      cursor.clamp(itemCount: 10, pageSize: 4); // newPageSize=4
      expect(
        cursor.currentPage,
        1,
        reason:
            'libraryRecalculatePage(oldPage: 2, oldPageSize: 3, newPageSize: 4) = 6 ~/ 4 = 1',
      );
    });

    test(
      'clamp()：冷啟動（第一次呼叫）時不會誤判成 pageSize 改變、不做多餘換算',
      () {
        final cursor = LibraryPagingCursor();
        final pageCount = cursor.clamp(itemCount: 10, pageSize: 4);
        expect(pageCount, 3); // libraryPageCount(10, 4) = 3
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
      cursor.clamp(itemCount: 10, pageSize: 4);
      cursor.goToNextPage();
      cursor.resetToFirstPage();
      expect(cursor.currentPage, 0);
    });

    test(
      'review-plan-issue-3.md M-2 情境迴歸測試：clamp() 箝制後的頁碼才是下一次 '
      'pageSize 改變時的換算基準，不會用到過期的越界頁碼',
      () {
        final cursor = LibraryPagingCursor();
        // 10 本書，pageSize=3（pageCount=4），走到最後一頁 page=3
        // （第一項全域 index = 9）。
        cursor.clamp(itemCount: 10, pageSize: 3);
        cursor.goToNextPage();
        cursor.goToNextPage();
        cursor.goToNextPage();
        expect(cursor.currentPage, 3);

        // 模擬刪書：itemCount 驟降為 2（pageCount=1），下一次 build() 呼叫
        // clamp() 應把 currentPage 箝制回 0，而不是留著越界的 3。
        cursor.clamp(itemCount: 2, pageSize: 3);
        expect(
          cursor.currentPage,
          0,
          reason: 'itemCount 縮小後應立即箝制，不殘留越界頁碼',
        );

        // 緊接著旋轉螢幕（pageSize 3→4）。若換算基準用的是箝制前的過期頁碼
        // 3，libraryRecalculatePage(oldPage: 3, oldPageSize: 3,
        // newPageSize: 4) = 9 ~/ 4 = 2，會對這 2 本書而言算出一個同樣越界
        // 的頁碼；用箝制後的頁碼 0，結果應為 0。
        cursor.clamp(itemCount: 2, pageSize: 4);
        expect(
          cursor.currentPage,
          0,
          reason: '換算基準必須是箝制後的頁碼，不是過期的越界值',
        );
      },
    );
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/library_paging_test.dart`
Expected: 編譯失敗（`clamp()` 仍是舊簽章 `{required int itemCount, required Orientation orientation}`，`applyOrientationChange` 呼叫點也已從測試中移除但生產程式碼仍缺 `pageSize` 版本的 `clamp()`）。

- [ ] **Step 3: 實作新簽章**

在 `app/lib/screens/library_paging.dart`，**整段取代**現有 `class LibraryPagingCursor { ... }`（含其上方的 doc comment）：

```dart
/// 書架分頁狀態的唯一負責者（epic-36 Issue 6，架構回顧衍生；Issue 7 進一
/// 步簡化）：取代原本散落在 `LibraryScreen` 的 `build()`／
/// `didChangeMetrics()`／排序/分類切換/換頁按鈕共 7 處各自寫入的
/// `_currentPage`／`_lastPageSize` 欄位。
///
/// 純 Dart 類別，不是 `ChangeNotifier`——分頁狀態只有 `_LibraryScreenState`
/// 一個消費者，不需要監聽機制；呼叫端在呼叫任一方法後自行 `setState(() {})`。
class LibraryPagingCursor {
  int _currentPage = 0;
  int? _lastPageSize;

  int get currentPage => _currentPage;

  /// `build()` 每次呼叫一次：以本次量測到的 [pageSize] 箝制頁碼。若
  /// [pageSize] 相較上次記錄的值改變（旋轉、視窗高度變化導致列數重
  /// 算），先依「目前頁第一項全域 index ÷ 新 pageSize」做比例換算，才
  /// 箝制到合法範圍（吸收 itemCount 縮小造成的越界殘留，原
  /// `review-plan-issue-3.md` M-2）。
  ///
  /// 取代 Issue 6 的 `clamp()`／`applyOrientationChange()` 兩個方法——
  /// pageSize 現在只有 `build()` 執行當下（`LayoutBuilder` 量測完成後）
  /// 才知道正確值，`didChangeMetrics()` 無法再提前算好，兩個關注點收斂
  /// 回同一次呼叫（見 `issues.md` Issue 7）。
  int clamp({required int itemCount, required int pageSize}) {
    final pageCount = libraryPageCount(itemCount, pageSize);
    final oldPageSize = _lastPageSize;
    if (oldPageSize != null && oldPageSize != pageSize) {
      _currentPage = libraryRecalculatePage(
        oldPage: _currentPage,
        oldPageSize: oldPageSize,
        newPageSize: pageSize,
      );
    }
    _currentPage = libraryClampPage(_currentPage, pageCount);
    _lastPageSize = pageSize;
    return pageCount;
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
Expected: 全數通過。

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/library_paging.dart app/test/screens/library_paging_test.dart
git commit -m "refactor(epic-36): LibraryPagingCursor.clamp() 與 applyOrientationChange() 合併" \
  -m "pageSize 改為呼叫端量測後傳入，兩個關注點收斂回單一 clamp() 呼叫。" \
  -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" \
  -m "Claude-Session: https://claude.ai/code/session_018cGrtkUbvK5UfG3aZdLCfT"
```

---

### Task 3：`PagingBar` 曝露自身固定高度供外部換算使用

**Files:**
- Modify: `app/lib/screens/widgets/paging_bar.dart`
- Test: `app/test/screens/widgets/paging_bar_test.dart`（若不存在則新建）

**Interfaces:**
- Produces: `static double PagingBar.resolvedHeight(bool isEinkMode)`——供 Task 4 的 `_buildBookList()` 換算 Grid 可用高度時參照，避免兩處各自寫一份 `52.0`/`56.0` 字面值。

- [ ] **Step 1: 確認既有測試檔案是否存在**

Run: `ls app/test/screens/widgets/paging_bar_test.dart`（於 `app/` 目錄下執行；若指令回報找不到檔案，代表尚無此測試檔，Step 2 需新建整個檔案；若已存在，Step 2 改為在既有檔案內新增一個 `test()`）。

- [ ] **Step 2: 寫失敗測試**

若檔案不存在，建立 `app/test/screens/widgets/paging_bar_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/widgets/paging_bar.dart';

void main() {
  test('PagingBar.resolvedHeight()：一般模式 52.0，E-Ink 模式 56.0（epic-36 Issue 7）', () {
    expect(PagingBar.resolvedHeight(false), 52.0);
    expect(PagingBar.resolvedHeight(true), 56.0);
  });
}
```

若檔案已存在，在既有 `main()` 內新增上述 `test(...)` 區塊即可，不需重複 import。

- [ ] **Step 3: 執行測試確認失敗**

Run: `flutter test test/screens/widgets/paging_bar_test.dart`
Expected: 編譯失敗（`PagingBar.resolvedHeight` 未定義）。

- [ ] **Step 4: 實作**

在 `app/lib/screens/widgets/paging_bar.dart`，於 `class PagingBar extends StatelessWidget {` 開頭（`final` 欄位宣告之前）新增靜態方法：

```dart
class PagingBar extends StatelessWidget {
  /// `PagingBar` 自身固定高度（`DESIGN.md` §7.2：一般模式 48dp 觸控目標
  /// ／E-Ink 模式 56dp），曝露給外部元件換算可用空間時參照，避免各處各自
  /// 寫一份 `52.0`/`56.0` 字面值（epic-36 Issue 7，`library_screen.dart`
  /// `_buildBookList()` 換算 Grid 可用高度時使用）。
  static double resolvedHeight(bool isEinkMode) => isEinkMode ? 56.0 : 52.0;

  final int currentPage; // 0-based
```

接著修改 `build()` 內原本的：

```dart
    final barHeight = isEinkMode ? 56.0 : 52.0;
```

改為：

```dart
    final barHeight = resolvedHeight(isEinkMode);
```

- [ ] **Step 5: 執行測試確認通過**

Run: `flutter test test/screens/widgets/paging_bar_test.dart`
Expected: 通過。

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/widgets/paging_bar.dart app/test/screens/widgets/paging_bar_test.dart
git commit -m "feat(epic-36): PagingBar 曝露 resolvedHeight() 靜態方法" \
  -m "供 library_screen.dart 動態列數計算換算可用高度時參照，避免重複字面值。" \
  -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" \
  -m "Claude-Session: https://claude.ai/code/session_018cGrtkUbvK5UfG3aZdLCfT"
```

---

### Task 4：`_buildBookList()` 改為 `LayoutBuilder` 動態列數計算

這是本 Issue 的核心整合任務，橫跨 `library_screen.dart` 的三處：`crossAxisCount` 改呼叫既有 `libraryPageSizeForOrientation()`（消弭與其重複的字面值，避免 Task 2 的 `clamp()` 重構讓該函式變成孤兒——見下方 Step 3 說明）、`didChangeMetrics()` 簡化、`_buildBookList()` 主體改用 `LayoutBuilder`。

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: `libraryRowsForHeight()`（Task 1）、`LibraryPagingCursor.clamp({itemCount, pageSize})`（Task 2）、`PagingBar.resolvedHeight()`（Task 3）、既有 `libraryPageSizeForOrientation(Orientation)`（`library_paging.dart`，本 Task 更新其 doc comment，行為不變）。**不消費** `gridTileFooterHeight(TextScaler)`——`review-plan-issue-7.md` C-2 確認 `_kCellAspectRatio`（即原 `_kCoverAspectRatio`）本身已涵蓋文字說明區高度，`_buildBookList()` 不需要另外呼叫它（`_BookGridTile`／`_GroupGridTile` 內部仍照舊使用，不受影響）。

- [ ] **Step 1: 改寫既有 widget test（先讓它們對新行為失敗）**

在 `app/test/screens/library_screen_test.dart` 頂部 import 區塊新增（`import 'package:elinkbook/screens/library_screen.dart';` 附近）：

```dart
import 'package:elinkbook/screens/library_paging.dart';
```

在檔案底部 `Book _testBook({` 函式定義之前，新增一個私有測試輔助函式：

```dart
/// 量測目前畫面樹上 `library_grid_view`／`library_list_view` 實際渲染了
/// 幾個書籍項目（`book_item_*` key）——用來在動態列數計算後，量到「當下
/// 裝置尺寸／字級底下真正算出的 pageSize」，取代寫死的舊「3/4」假設常數
/// （epic-36 Issue 7：pageSize 現在依實際可用高度動態計算，測試不能再
/// 預先假設固定列數）。呼叫時機：itemCount 必須大於等於這個裝置理論上
/// 可能算出的最大 pageSize（本檔案相關測試皆準備至少 20 本書），確保第
/// 一頁一定被塞滿、量到的數字就是真正的 pageSize，而非因為書不夠多被
/// itemCount 截斷的結果。
int _measuredPageSize(WidgetTester tester) {
  final finder = find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith('book_item_');
  });
  return finder.evaluate().length;
}
```

**整段取代**以下 5 則既有測試（用檔案內既有的測試標題字串定位，逐一取代測試本體，測試標題與其餘測試的相對順序不變），並在第 5 則測試之後**新增**第 6 則全新測試（`issues.md#L302` 明文要求、原計劃書漏掉的「同直向不同高度」對比測試，`review-plan-issue-7.md` I-1）：

1. 取代 `'直向（3 項/頁）與橫向（4 項/頁）第一頁顯示的項目數正確'`：

```dart
  testWidgets('直向與橫向的每頁項目數依可用空間動態計算，橫向欄數多於直向', (tester) async {
    final books = List.generate(20, (i) => _testBook(id: '$i', title: '書$i'));

    tester.view.physicalSize = const Size(800, 1200); // portrait
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: books),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final portraitPageSize = _measuredPageSize(tester);
    expect(portraitPageSize, greaterThanOrEqualTo(3), reason: '直向至少要能完整顯示 1 行（3 欄）');
    expect(portraitPageSize % 3, 0, reason: '直向 3 欄，pageSize 必為 3 的倍數（整數列，不可半截列）');
    expect(
      find.text('1 / ${libraryPageCount(20, portraitPageSize)}'),
      findsOneWidget,
    );

    tester.view.physicalSize = const Size(1200, 800); // landscape
    await tester.pumpAndSettle();

    final landscapePageSize = _measuredPageSize(tester);
    expect(landscapePageSize, greaterThanOrEqualTo(4), reason: '橫向至少要能完整顯示 1 行（4 欄）');
    expect(landscapePageSize % 4, 0, reason: '橫向 4 欄，pageSize 必為 4 的倍數（整數列，不可半截列）');
  });
```

2. 取代 `'點擊 PagingBar 下一頁/上一頁切換書架顯示的書籍'`：

```dart
  testWidgets('點擊 PagingBar 下一頁/上一頁切換書架顯示的書籍', (tester) async {
    final books = List.generate(20, (i) => _testBook(id: '$i', title: '書$i'));

    tester.view.physicalSize = const Size(800, 1200); // portrait
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: books),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pageSize = _measuredPageSize(tester);
    final pageCount = libraryPageCount(20, pageSize);
    expect(find.byKey(const Key('book_item_0')), findsOneWidget);
    expect(
      find.byKey(Key('book_item_$pageSize')),
      findsNothing,
      reason: '第一頁不該出現下一頁才有的項目',
    );
    expect(find.text('1 / $pageCount'), findsOneWidget);

    await tester.tap(find.byKey(const Key('paging_bar_next_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_0')), findsNothing);
    expect(
      find.byKey(Key('book_item_$pageSize')),
      findsOneWidget,
      reason: '第二頁第一項全域 index 應等於 pageSize',
    );
    expect(find.text('2 / $pageCount'), findsOneWidget);

    await tester.tap(find.byKey(const Key('paging_bar_previous_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_0')), findsOneWidget);
    expect(find.text('1 / $pageCount'), findsOneWidget);
  });
```

3. 取代 `'旋轉螢幕時目前頁碼依新每頁容量正確換算，不跳到看不懂的地方'`：

```dart
  testWidgets('旋轉螢幕時目前頁碼依新每頁容量正確換算，不跳到看不懂的地方', (tester) async {
    final books = List.generate(60, (i) => _testBook(id: '$i', title: '書$i'));

    tester.view.physicalSize = const Size(800, 1200); // portrait
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: books),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final portraitPageSize = _measuredPageSize(tester);

    await tester.tap(find.byKey(const Key('paging_bar_next_button')));
    await tester.pumpAndSettle();

    // 走到第 2 頁（0-based page=1），第一項全域 index = portraitPageSize。
    expect(find.byKey(Key('book_item_$portraitPageSize')), findsOneWidget);

    tester.view.physicalSize = const Size(1200, 800); // landscape
    await tester.pumpAndSettle();

    final landscapePageSize = _measuredPageSize(tester);
    final expectedPage = libraryRecalculatePage(
      oldPage: 1,
      oldPageSize: portraitPageSize,
      newPageSize: landscapePageSize,
    );
    final expectedPageCount = libraryPageCount(60, landscapePageSize);
    expect(find.text('${expectedPage + 1} / $expectedPageCount'), findsOneWidget);
    expect(
      find.byKey(Key('book_item_${expectedPage * landscapePageSize}')),
      findsOneWidget,
      reason: '換算後頁面第一項全域 index 應等於 expectedPage * landscapePageSize',
    );
  });
```

4. 取代 `'切換排序條件後頁碼重置為第一頁'`：

```dart
  testWidgets('切換排序條件後頁碼重置為第一頁', (tester) async {
    final books = List.generate(20, (i) => _testBook(id: '$i', title: '書$i'));

    tester.view.physicalSize = const Size(800, 1200); // portrait
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: books),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pageSize = _measuredPageSize(tester);
    final pageCount = libraryPageCount(20, pageSize);

    await tester.tap(find.byKey(const Key('paging_bar_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('2 / $pageCount'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_option_title')));
    await tester.pumpAndSettle();

    expect(find.text('1 / $pageCount'), findsOneWidget);
  });
```

5. 取代 `'進入/離開分類下鑽時頁碼重置為第一頁'`：

```dart
  testWidgets('進入/離開分類下鑽時頁碼重置為第一頁', (tester) async {
    final groupBooks = List.generate(
      20,
      (i) => _testBook(id: 'g$i', title: '分類書$i', groupName: '奇幻'),
    );

    tester.view.physicalSize = const Size(800, 1200); // portrait
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: groupBooks),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    final pageSize = _measuredPageSize(tester);
    final pageCount = libraryPageCount(20, pageSize);
    expect(find.text('1 / $pageCount'), findsOneWidget);

    await tester.tap(find.byKey(const Key('paging_bar_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('2 / $pageCount'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_back_from_group_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    expect(
      find.text('1 / $pageCount'),
      findsOneWidget,
      reason: '再次下鑽同一分類時頁碼應已重置，不殘留上次離開時的頁碼',
    );
  });
```

6. **新增**（issues.md 明文要求，原計劃書遺漏，`review-plan-issue-7.md` I-1）：

```dart
  testWidgets('同一直向裝置在較矮／較高兩種高度下，書架每頁列數確實跟著變動（矮裝置少於高裝置）', (
    tester,
  ) async {
    final books = List.generate(60, (i) => _testBook(id: '$i', title: '書$i'));

    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    tester.view.physicalSize = const Size(800, 600); // 較矮
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: books),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final shortPageSize = _measuredPageSize(tester);
    expect(shortPageSize % 3, 0, reason: '直向 3 欄，pageSize 必為 3 的倍數（整數列）');

    tester.view.physicalSize = const Size(800, 1400); // 較高，同一裝置寬度不變
    await tester.pumpAndSettle();
    final tallPageSize = _measuredPageSize(tester);
    expect(tallPageSize % 3, 0, reason: '直向 3 欄，pageSize 必為 3 的倍數（整數列）');

    expect(
      tallPageSize,
      greaterThan(shortPageSize),
      reason:
          '較高裝置可用高度較多，應能顯示比較矮裝置更多列；若動態計算退化回寫死'
          '1 行，兩者會相等，測試須能抓到這種回歸',
    );
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: 上述 6 則測試失敗（生產程式碼仍是 Issue 3/6 的寫死「1 行」邏輯與舊版 `clamp(orientation:)` 呼叫，此時尚未同步修改 `library_screen.dart`，本步驟應該連編譯都過不了——`_paging.clamp(itemCount: itemCount, orientation: orientation)` 呼叫點的簽章已在 Task 2 被改掉，這是預期中的失敗，屬於本 Task Step 3 才會修正的範圍）。

- [ ] **Step 3: 實作 `library_screen.dart` 異動**

**3a. `crossAxisCount` 改呼叫 `libraryPageSizeForOrientation()`**（消弭與該函式重複的字面值——Task 2 的 `clamp()` 重構移除了該函式原本在 `LibraryPagingCursor` 內部的唯一呼叫點，若不在這裡接上新呼叫點，`libraryPageSizeForOrientation()` 會變成沒有生產程式碼呼叫的孤兒函式，違反 `CLAUDE.md`「移除你的異動造成的孤兒」原則；`_buildBookList()` 原本就有一份完全相同邏輯的字面值 `orientation == Orientation.landscape ? 4 : 3`，改呼叫既有函式同時消弭了這處既有重複）：

找到第 943 行：

```dart
      final crossAxisCount = orientation == Orientation.landscape ? 4 : 3;
```

**整段取代**（連同上下文重新確認位置——這行目前在 `if (_viewMode == LibraryViewMode.grid) {` 區塊內，Step 3c 會把整個 `_buildBookList()` 主體重寫，這裡先只描述這一行本身的異動意圖，實際修改直接併入 Step 3c 的完整重寫版本）為：

```dart
      final crossAxisCount = libraryPageSizeForOrientation(orientation);
```

**3a-ii. 更新 `libraryPageSizeForOrientation()` 過期的 doc comment**（`review-plan-issue-7.md` I-3：該函式原本語意是「每頁筆數」，Issue 7 起只剩「欄數供應者」，不再等於 `pageSize`，doc comment 若不同步會誤導後續維護者）：

在 `app/lib/screens/library_paging.dart`，找到：

```dart
/// 每頁筆數固定依螢幕方向決定（`DESIGN.md#L267`／`#L335`：直排 1 行 3
/// 欄、橫排 1 行 4 欄），格狀／清單兩種檢視一視同仁，不因檢視模式而異
/// （見 plans/plan-issue-3.md「計劃範圍澄清」第 3 點）。
int libraryPageSizeForOrientation(Orientation orientation) =>
    orientation == Orientation.landscape ? 4 : 3;
```

**整段取代**為：

```dart
/// 取得特定方向下的預設欄數（crossAxisCount：直排 3、橫排 4）。**Issue 7
/// 起不再等於每頁筆數（pageSize）**——Issue 3／6 時每頁只有 1 行，欄數剛好
/// 等於 pageSize；Issue 7 起 `pageSize = crossAxisCount * rows`，rows 依可
/// 用高度動態計算（見 `libraryRowsForHeight()`），函式名稱沿用舊名只是為
/// 了不做無謂的改名（呼叫端／測試都已改用新語意呼叫），語意以本段
/// doc comment 為準（`review-plan-issue-7.md` I-3）。格狀／清單兩種檢視
/// 一視同仁，不因檢視模式而異（見 plans/plan-issue-3.md「計劃範圍澄清」
/// 第 3 點）。
int libraryPageSizeForOrientation(Orientation orientation) =>
    orientation == Orientation.landscape ? 4 : 3;
```

（本次修改僅止於 doc comment，函式本體與回傳值完全不變，`library_paging_test.dart` 既有的 `libraryPageSizeForOrientation` 測試不需要跟著改。）

**3b. `didChangeMetrics()` 簡化，並比對 `physicalSize` 保留 E-Ink 防抖保護**（`review-plan-issue-7.md` I-4：鍵盤顯隱改變的是 `viewInsets`，不是 `physicalSize`，比對後可以繼續攔截這類無關變化，不需要接受計劃書原案「兩者都觸發 setState()」的取捨）：

在 `_LibraryScreenState`，找到第 107 行 `final LibraryPagingCursor _paging = LibraryPagingCursor();` 欄位宣告，在它之後新增一個欄位：

```dart
  /// `didChangeMetrics()` 用來比對「是否真的尺寸改變」的暫存值——鍵盤彈出
  /// /收起改變的是 `viewInsets`，不是 `physicalSize`，比對後可以繼續攔截
  /// 這類無關 metrics 變化，延續 Issue 6（`review-plan-issue-6.md` I-1）
  /// 建立的 E-Ink 防抖保護（`review-plan-issue-7.md` I-4）。
  Size? _lastPhysicalSize;
```

接著找到第 169-190 行整個 `didChangeMetrics()` 方法，**整段取代**為：

```dart
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final physicalSize = View.of(context).physicalSize;
    // App 退到背景、螢幕休眠、多視窗模式調整分割大小、可折疊裝置展開
    // 過渡瞬間，physicalSize 可能暫時回報為 0x0——此時 `0 > 0` 為
    // false，會被誤判為 portrait，若裝置原本是 landscape 就會觸發一次
    // 不必要的重建。直接略過這種暫態，等下一次真正有效的 metrics 變化
    // 再處理（`review-plan-issue-3.md` I-2）。
    if (physicalSize.isEmpty) return;
    // pageSize 改為由 build() 內的 LayoutBuilder 依實際量測高度計算
    // （epic-36 Issue 7）——didChangeMetrics() 不再自己算 pageSize、也
    // 不再呼叫 LibraryPagingCursor 的任何方法，實際箝制／比例換算全部
    // 延後到下一次 build() 呼叫 _paging.clamp() 時處理。但仍比對
    // physicalSize 是否真的改變才 setState()：軟體鍵盤彈出/收起改變的是
    // viewInsets，不是 physicalSize，這裡比對後可以繼續攔截這類無關變化
    // 觸發整頁重建，延續 Issue 6 建立的 E-Ink 防抖保護
    // （`review-plan-issue-6.md` I-1／`review-plan-issue-7.md` I-4）。
    if (_lastPhysicalSize == physicalSize) return;
    _lastPhysicalSize = physicalSize;
    setState(() {});
  }
```

**3c. `_buildBookList()` 改用 `LayoutBuilder`**：

找到第 884-996 行整個 `Widget _buildBookList(List<Book> books) { ... }` 方法，**整段取代**為：

```dart
  Widget _buildBookList(List<Book> books) {
    final selectedIds = _selectedBookIds;
    final groupTiles = _activeGroupFilter == null
        ? _buildGroupTiles(books)
        : const <_GroupTile>[];
    final visibleBooks = _activeGroupFilter == null
        ? books.where((b) => b.groupName == BookGroup.uncategorized).toList()
        : books.where((b) => b.groupName == _activeGroupFilter).toList();
    final itemCount = groupTiles.length + visibleBooks.length;

    final orientation = MediaQuery.orientationOf(context);
    final crossAxisCount = libraryPageSizeForOrientation(orientation);

    Widget itemBuilder(
      BuildContext context,
      int globalIndex, {
      required bool isGrid,
    }) {
      if (globalIndex < groupTiles.length) {
        final tile = groupTiles[globalIndex];
        final onTap =
            _inSelectionMode ? null : () => _openGroupFilteredView(tile.name);
        return isGrid
            ? _GroupGridTile(tile: tile, onTap: onTap)
            : _GroupListTile(tile: tile, onTap: onTap);
      }
      final book = visibleBooks[globalIndex - groupTiles.length];
      return isGrid
          ? _BookGridTile(
              book: book,
              selectionMode: _inSelectionMode,
              selected: selectedIds?.contains(book.id) ?? false,
              onTap: () => _onBookTap(book),
              onLongPress: () => _onBookLongPress(book),
              onMenuTap: () => _openBookActionSheet(book),
            )
          : _BookListTile(
              book: book,
              selectionMode: _inSelectionMode,
              selected: selectedIds?.contains(book.id) ?? false,
              onTap: () => _onBookTap(book),
              onLongPress: () => _onBookLongPress(book),
              onMenuTap: () => _openBookActionSheet(book),
            );
    }

    return Column(
      children: [
        if (_activeGroupFilter == null && _mostRecentBook != null)
          _ContinueReadingRow(
            book: _mostRecentBook!,
            // 多選模式進行中時停用點擊（`review-plan-issue-3.md` M-3）：
            // 本列沒有勾選指示器，若不停用，使用者在多選時點到它會在
            // 毫無視覺反饋的情況下切換 _mostRecentBook 的選取狀態，比照
            // `_GroupGridTile`／`_GroupListTile` 在 _inSelectionMode 時
            // 一律把 onTap 傳 null 的既有慣例。
            onTap: _inSelectionMode ? null : () => _onBookTap(_mostRecentBook!),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 依實際可用寬高動態計算每頁列數（epic-36 Issue 7），取代
              // Issue 3 寫死「1 行」的舊假設。寬度換算封面格寬/高；高度
              // 扣掉 PagingBar 自身固定高度、以及 GridView 自身上下
              // padding（各 8dp，合計 16dp）後才是 Grid 內容真正可用高度
              // ——這兩者是本區塊唯一需要手動參照的高度常數（PagingBar
              // 因為它被移進了這個 LayoutBuilder 的回傳子樹，GridView
              // padding 因為它是 GridView 自己的既有參數，不是外層
              // Column 佈局能自動消化的東西），AppBar／搜尋列／繼續閱讀
              // 列的高度則由外層 Column／Expanded 佈局自然算出剩餘空
              // 間，不需要在這裡手動加總（`issues.md` Issue 7 Solution
              // 段落；`review-plan-issue-7.md` C-1：原計劃書漏算了
              // GridView 自身 padding，會在邊界高度裁切底列內容）。
              const gridPadding = 8.0;
              const gridSpacing = 8.0;
              const rowSpacing = 12.0;
              final cellWidth = (constraints.maxWidth -
                      2 * gridPadding -
                      (crossAxisCount - 1) * gridSpacing) /
                  crossAxisCount;
              // `_kCellAspectRatio` 是 GridView 每個 cell「整體」的寬高比
              // （封面＋文字說明區合計，見 `_BookGridTile`：外層 Column
              // 的總高度受 `childAspectRatio` 約束，封面只是 Expanded
              // 取得的剩餘空間），不是純封面的寬高比——`cellWidth /
              // _kCellAspectRatio` 本身就已經是含文字說明區的整個 cell
              // 高度，不能再另外疊加 footerHeight（`review-plan-issue-7.md`
              // C-2：疊加會造成單列高度虛增 30~50dp，動態列數因此算得比
              // 實際能放下的還要少，違背 Issue 7「消除留白」的目的）。
              final rowContentHeight = cellWidth / _kCellAspectRatio;
              final pagingBarHeight =
                  PagingBar.resolvedHeight(widget.themeDependencies.isEinkMode);
              final availableGridHeight =
                  constraints.maxHeight - pagingBarHeight - 2 * gridPadding;
              final rows = libraryRowsForHeight(
                availableHeight: availableGridHeight,
                rowContentHeight: rowContentHeight,
                rowSpacing: rowSpacing,
              );
              final pageSize = crossAxisCount * rows;

              final pageCount = _paging.clamp(itemCount: itemCount, pageSize: pageSize);
              final safePage = _paging.currentPage;
              final pageStart = safePage * pageSize;
              final pageEnd = (pageStart + pageSize).clamp(0, itemCount);
              final pageItemCount = pageEnd - pageStart;

              final Widget gridOrList;
              if (_viewMode == LibraryViewMode.grid) {
                gridOrList = GridView.builder(
                  key: const Key('library_grid_view'),
                  padding: const EdgeInsets.all(gridPadding),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: _kCellAspectRatio,
                    crossAxisSpacing: gridSpacing,
                    mainAxisSpacing: rowSpacing,
                  ),
                  itemCount: pageItemCount,
                  itemBuilder: (context, index) =>
                      itemBuilder(context, pageStart + index, isGrid: true),
                );
              } else {
                gridOrList = ListView.builder(
                  key: const Key('library_list_view'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: pageItemCount,
                  itemBuilder: (context, index) =>
                      itemBuilder(context, pageStart + index, isGrid: false),
                );
              }

              return Column(
                children: [
                  Expanded(
                    child: Align(alignment: Alignment.topCenter, child: gridOrList),
                  ),
                  PagingBar(
                    key: const Key('library_paging_bar'),
                    currentPage: safePage,
                    pageCount: pageCount,
                    onPrevious: safePage > 0
                        ? () => setState(() => _paging.goToPreviousPage())
                        : null,
                    onNext: safePage < pageCount - 1
                        ? () => setState(() => _paging.goToNextPage())
                        : null,
                    isEinkMode: widget.themeDependencies.isEinkMode,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
```

**3d. 新增具名常數 `_kCellAspectRatio`**：

在檔案頂部（`class LibraryScreen extends StatefulWidget {` 之前，import 區塊之後）新增：

```dart
/// 書架 GridView 每個 cell「整體」的寬高比（cell 寬度 / 高度，封面＋文字
/// 說明區合計，非純封面寬高比——見 `_BookGridTile`：外層 Column 總高度受
/// `childAspectRatio` 約束，封面只是 Expanded 取得的剩餘空間），沿用
/// `SliverGridDelegateWithFixedCrossAxisCount.childAspectRatio` 既有字面
/// 值——抽成具名常數避免 Grid 渲染與 Issue 7 動態列數計算
/// （`_buildBookList()`）各自寫一份 `0.62`，日後改一處漏改另一處
/// （epic-36 Issue 7；`review-plan-issue-7.md` C-2 已確認 `childAspectRatio`
/// 涵蓋整個 cell，不是只有封面部分，命名從 `_kCoverAspectRatio` 正名為
/// `_kCellAspectRatio`）。
const _kCellAspectRatio = 0.62;
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: 全數通過，包含 Step 1 改寫／新增的 6 則測試，以及檔案內其餘既有測試（例如「直立時封面格數為 3 欄」「橫放時為 4 欄」「裝置旋轉後欄數即時變化」「格狀檢視含欄格間距」等——這些測試只驗證 `crossAxisCount`／`crossAxisSpacing`／`mainAxisSpacing`，不涉及列數，Task 4 的異動不影響其斷言）。

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`（於 `app/` 目錄下執行）
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-36): 書架每頁列數改為依可用高度動態計算" \
  -m "_buildBookList() 改用 LayoutBuilder 量測 Grid 區域，取代 Issue 3 寫死 1 行的舊假設；" \
  -m "didChangeMetrics() 相應簡化，crossAxisCount 改呼叫既有 libraryPageSizeForOrientation()。" \
  -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" \
  -m "Claude-Session: https://claude.ai/code/session_018cGrtkUbvK5UfG3aZdLCfT"
```

---

### Task 5：`DESIGN.md` §11.2／§15.1 文字同步更新

**Files:**
- Modify: `DESIGN.md`

**Interfaces:** 無（純文件異動，不影響任何程式碼介面）。

- [ ] **Step 1: 找到並改寫既有段落（DESIGN.md 有兩處，皆須修訂——`review-plan-issue-7.md` I-2）**

在 `DESIGN.md` 搜尋「1 行 3 欄」，會命中兩處幾乎相同的文字，兩處都要改，否則文件內部會自相矛盾：

**§11.2（約 Line 267）**，找到：

```markdown
- **佈局規格**：書架網格在**直排 (Portrait) 時為 1 行 3 欄，橫排 (Landscape) 時為 1 行 4 欄**。每個分類格子佔用 1 欄，每本獨立書亦佔用 1 欄。
```

**整段取代**為：

```markdown
- **佈局規格**：書架網格**直排 3 欄、橫排 4 欄**（欄數固定）；每頁**列數**
  依裝置實際可用高度動態計算，矮/高裝置皆完整顯示整數列，不寫死「1
  行」（epic-36 Issue 7，詳見 §15.1）。每個分類格子佔用 1 欄，每本獨立書
  亦佔用 1 欄。
```

**§15.1（約 Line 335）**，找到：

```markdown
  - 書架網格排版在**直排時為 1 行 3 欄，橫排時為 1 行 4 欄**。
```

**整段取代**為：

```markdown
  - 書架網格排版直排 3 欄、橫排 4 欄（欄數不變）；每頁**列數**依裝置實際
    可用高度動態計算（`libraryRowsForHeight()`，見 `library_paging.dart`），
    矮/高裝置皆完整顯示整數列，不寫死「1 行」、不留白、也不出現半截列
    跑版（epic-36 Issue 7）。分頁本身仍為離散換頁（`PagingBar`），不是
    捲動。
```

（若既有段落的確切措辭與上述搜尋字串不完全一致，以語意最接近、描述「書架每頁固定列數」的段落為準，兩處都要找到並替換，替換原則相同：把「固定列數」改寫為「動態列數」，並保留「離散換頁、非捲動」這個既有架構事實不變。）

- [ ] **Step 2: Commit**

```bash
git add DESIGN.md
git commit -m "docs(epic-36): DESIGN.md §11.2／§15.1 同步書架動態列數計算" \
  -m "反映 Issue 7 書架每頁列數改為依可用高度動態計算，取代兩處舊有固定 1 行的文字規格。" \
  -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" \
  -m "Claude-Session: https://claude.ai/code/session_018cGrtkUbvK5UfG3aZdLCfT"
```

---

### Task 6：全套測試收尾確認

**Files:** 無新增/修改（純驗證任務）。

- [ ] **Step 1: 執行完整測試套件**

Run: `flutter test`（於 `app/` 目錄下執行，不帶檔案路徑）
Expected: 除 `epic-37-test-suite-flakiness` 已追蹤在案、與本 Issue 無關的 `remote_catalog_screen_test.dart` 既有不穩定測試外，其餘全數通過。若失敗集中在本 Issue 觸及的檔案（`library_paging_test.dart`／`library_screen_test.dart`／`paging_bar_test.dart`），須回頭排查，不可略過。

- [ ] **Step 2: 執行 `flutter analyze` 最終確認**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 回報並待人類決定是否發起程式審查／發 PR**

本步驟不需要 commit——若 Step 1／Step 2 有異常，回到對應 Task 修正後再重跑本 Task；若皆通過，知會使用者本計劃已全數完成，等待後續指示（`/superpowers:requesting-code-review` 或直接發 PR）。

---

## Self-Review（撰寫計劃時的自我檢查記錄）

**Spec 覆蓋度**：issues.md Issue 7 的四項 Solution 要點（`LibraryPagingCursor` 介面合併、`libraryRowsForHeight()` 新增、`_buildBookList()` 改造、`DESIGN.md` §11.2／§15.1 更新）依序對應 Task 2、Task 1、Task 4、Task 5；「單元測試要求」四項（`libraryRowsForHeight()` 邊界測試、`clamp()` 新簽章測試、widget test 矮高裝置列數變動、旋轉頁碼換算回歸）依序對應 Task 1 Step 1、Task 2 Step 1、Task 4 Step 1（測試 6）、Task 4 Step 1（測試 3）。`PagingBar.resolvedHeight()`（Task 3）是 issues.md 原文未明訂但技術設計上必要的補充——`_buildBookList()` 要換算 Grid 可用高度必須知道 `PagingBar` 自身固定高度，若不曝露成可參照的靜態方法，`library_screen.dart` 只能重複寫一份 `52.0`/`56.0` 字面值，違反 Issue 7 Solution 段落本身「避免各處各自寫一份高度常數」的精神，故補上此 Task。

**佔位符掃描**：全計劃無 TBD/之後補上等字樣，所有程式碼區塊皆為可直接套用的完整內容。

**型別一致性**：`libraryRowsForHeight()` 簽章（Task 1 定義／Task 4 呼叫）、`LibraryPagingCursor.clamp()` 新簽章（Task 2 定義／Task 4 呼叫）、`PagingBar.resolvedHeight()`（Task 3 定義／Task 4 呼叫）、`_kCellAspectRatio`（Task 4 Step 3d 定義／Step 3c 呼叫）四處定義與呼叫端型別/參數名稱一致。

**`review-plan-issue-7.md` 修訂對照**（2026-09-07 依審查報告修訂，2 Critical／4 Important／2 Minor 全數採納，無不採納項目）：
- C-1（GridView 垂直 padding 漏算）→ Task 1 Step 3 doc comment、Task 4 Step 3c `availableGridHeight` 公式。
- C-2（`rowContentHeight` 重複疊加 footerHeight）→ Task 4 Step 3c／3d，`_kCoverAspectRatio` 正名 `_kCellAspectRatio`，移除 `footerHeight` 相關程式碼。
- I-1（缺矮/高裝置對比測試）→ Task 4 Step 1 新增第 6 則測試。
- I-2（`DESIGN.md` §11.2 漏改）→ Task 5 Step 1 兩處一併修訂。
- I-3（`libraryPageSizeForOrientation` 過期註解）→ Task 4 Step 3a-ii。
- I-4（`didChangeMetrics()` 無條件 setState）→ Task 4 Step 3b，新增 `_lastPhysicalSize` 欄位＋比對。
- M-1（`$(printf ...)` 非 PowerShell 相容）→ 全 Task commit 範例改為兩個獨立 `-m`。
- M-2（浮點數 epsilon）→ Task 1 Step 3 `libraryRowsForHeight()` 除法前加 `1e-5`。
