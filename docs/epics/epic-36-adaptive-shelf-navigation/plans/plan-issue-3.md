# Epic 36 Issue 3：繼續閱讀列與 PagingBar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 書架瀏覽（格狀／清單兩種檢視）從無限捲動改為固定每頁一整排（直向 3 項／橫向 4 項）的 `PagingBar` 換頁，旋轉螢幕時頁碼正確換算；新增常駐「繼續閱讀列」，顯示使用者最後閱讀的書籍與進度。

**Architecture：** 新增兩個獨立、可脫離 widget 樹單元測試的純函式模組（`library_paging.dart` 分頁數學）與一個純呈現元件（`paging_bar.dart`），兩者皆不知道彼此、也不知道 `LibraryScreen` 的存在。`library_screen.dart` 是唯一的整合點：`_LibraryScreenState` 新增 `_currentPage`／`_lastPageSize` 兩個欄位與 `WidgetsBindingObserver` mixin，`_buildBookList()` 從「渲染全部項目＋捲動」改為「用純函式算出目前頁的子區間＋只渲染這個子區間＋底部固定 `PagingBar`」；`_mostRecentBook` 由既有的 `_onBookListChanged()` 監聽器同步計算，`_activeGroupFilter == null` 時於書架最上方（見下方「計劃範圍澄清」第 1 點）渲染 `_ContinueReadingRow`。

**Tech Stack：** Flutter 3.41.9、既有 `flutter_test` widget test 慣例；`tester.view.physicalSize = ...` 觸發旋轉（已確認會呼叫 `platformDispatcher.onMetricsChanged`，見 `flutter_test/lib/src/window.dart:1106-1136`，故能真正觸發 `WidgetsBindingObserver.didChangeMetrics()`）。

**Spec：** `docs/epics/epic-36-adaptive-shelf-navigation/spec.md` §功能③、`docs/epics/epic-36-adaptive-shelf-navigation/issues.md` Issue 3、上游 `DESIGN.md` §15.1（書架格子/PagingBar 規格）、§11.2（下鑽格局）。

## Global Constraints

- 本 Epic 全程只碰 Navigation／Library UI／Settings UI／Bottom sheets／Dialogs／Layout，不碰 OPDS／WebDAV／雲端來源實作、書籍儲存、閱讀進度持久化等核心架構清單項目（`UI_DESIGN_RULES.md`）。
- 每頁筆數固定 `orientation == landscape ? 4 : 3`（`DESIGN.md#L267`／`#L335` 明文「直排 1 行 3 欄、橫排 1 行 4 欄」），**不採納** `review-spec.md` I-1 建議的 2 列×3 欄＝6 本——`spec.md` Further Notes 已兩輪核對並訂正，本計劃沿用不變。
- 每個 Task 完成後只跑該 Task 實際觸及的測試檔，全套 `flutter test`（不帶路徑）留到最後一個 Task 收尾時執行一次（比照 `CLAUDE.md`「測試執行範圍」）。
- `flutter analyze` 必須在每個 Task 結束時保持乾淨（`No issues found!`）。
- **（`review-plan-issue-2.md` I-1 教訓沿用）**：任何 Task 的收尾 Commit 前，該 Task 實際觸及的測試檔必須 100% PASS，不得把已知失敗留到下一個 Task 才修——每個 Task 若需要修改既有測試，遷移步驟併入同一個 Task，不得跨 Task 分割成「先讓測試變紅、下個 Task 才修好」的中繼狀態。

## 計劃範圍澄清（撰寫本計劃時發現並解決的 issues.md／spec.md 內部落差）

1. **「搜尋列下方」渲染繼續閱讀列——查證後確認本專案目前完全沒有搜尋列**：`spec.md` §功能③與 `DESIGN.md#L297`（§15.1）皆寫「繼續閱讀列於搜尋列下方渲染」，但 `spec.md` 自己的 Out of Scope 段落也承認「現有程式碼是否已有搜尋機制需在 Issue 3 規劃階段另行查證」。已查證：對 `app/lib/screens/library_screen.dart` 全文搜尋 `TextField`／`SearchBar`／`search`，**沒有任何一個搜尋列存在**（書架搜尋是 `DESIGN.md` §15.2 描述的未來功能，本 Epic 明確排除）。本計劃將繼續閱讀列改為渲染於書架 body **最上方**（分類拼貼格/書籍清單之前），語意等同「搜尋列下方」在搜尋列不存在時的退化情況，不算偏離規格——待未來 Epic 真的加上搜尋列時，繼續閱讀列的插入點只需往下挪到搜尋列之後即可，不影響本次架構。
2. **關鍵修正：`didChangeMetrics()` 內不可用 `MediaQuery.orientationOf(context)` 判斷新方向，會讀到過期資料**——`spec.md` 原文建議「`didChangeMetrics()` 偵測到 `_pageSize` 實際改變時...套用換算公式」，但沒有明講在 `didChangeMetrics()` 內部要怎麼取得「新」的方向。查證 Flutter SDK 原始碼（`flutter/lib/src/widgets/binding.dart:855-862`）：`handleMetricsChanged()` 只是同步逐一呼叫每個已註冊 observer 的 `didChangeMetrics()`，中間**不會**觸發任何 widget 重建；而 `MediaQuery.of(context)` 讀到的是「當前這一幀已經建好的」`InheritedWidget` 資料，此時祖先的 `MediaQuery` 供應者（`View`/`WidgetsApp`）即使自己也監聽了同一個 metrics 變化事件，也只是呼叫了 `setState()`（**排入**下一次重建，不是立即重建）——所以在 `didChangeMetrics()` 執行的當下，`MediaQuery.orientationOf(context)` 仍然回傳**舊**方向，用它來跟「記錄下來的舊 `_lastPageSize`」比較，會永遠比較不出差異（因為兩者都反映舊狀態），旋轉後的頁碼換算永遠不會被觸發。Flutter 官方文件（`binding.dart:255-267`）的 `didChangeMetrics()` 範例程式碼示範的正是改用 `View.of(context).physicalSize`（直接讀平台當下的原始 metrics，不經過 `InheritedWidget` 重建管線）取得**即時**新尺寸。本計劃 `didChangeMetrics()` 一律改用 `View.of(context).physicalSize`（寬>高＝landscape）判斷新方向，`_buildBookList()`（`build()` 階段，此時 `MediaQuery` 已經是新資料）才繼續使用既有的 `MediaQuery.orientationOf(context)`——兩處用途不同、互不衝突。
3. **`_pageSize` 對格狀與清單兩種檢視一視同仁，並非規劃疏漏**：`DESIGN.md#L317`（§15.1）明文「書架格狀／清單視圖不使用無限捲動」，`spec.md` 的 `_pageSize` 計算式也沒有依 `_viewMode` 分支——也就是說切到清單檢視時，每頁一樣只顯示 3（直向）／4（橫向）項，不會因為清單列比格狀方塊窄而多顯示幾項。這是上游設計的明確決定（換頁控制列本身也不分檢視模式），實作時不得自行覺得「清單應該能顯示更多」而擅自放寬。
4. **「管理分類」對話框完成後不重置 `_currentPage`**：`spec.md` 明文只列「排序/搜尋/分類切換」三種情境需要重置頁碼，未列管理分類（新增/刪除/改名分類）。管理分類可能改變 `itemCount`（例如合併分類），但既有的 `libraryClampPage()` 純函式（Task 1）已經會把任何越界的 `_currentPage` 箝制回有效範圍，不需要額外重置邏輯，也不在本計劃新增。
5. **`_toggleViewMode()`（格狀/清單切換）不重置 `_currentPage`**：`_pageSize` 只取決於螢幕方向（見第 3 點），與檢視模式無關；切換檢視模式時目前頁碼所代表的「全域項目區間」不變，維持原頁碼、只是換一種排版方式顯示同一批項目，才是正確行為。
6. **既有測試相容性已於規劃階段查證——範圍限於 Task 3 的分頁邏輯**：全文搜尋 `library_screen_test.dart`（3700+ 行）確認：(a) 沒有任何測試依賴無限捲動行為（搜尋 `捲動`／`scroll`／`Scrollable`／`.drag(` 均無相關命中）；(b) 沒有任何測試在單一情境下同時建立超過 4 個頂層項目（分類拼貼格＋書籍加總）並斷言其「同時全部可見」——僅有的兩處 `List.generate(4, ...)` 皆把 4 本書歸入同一分類（只產生 1 個分類拼貼格，遠低於任何方向的每頁容量）；(c) `flutter_test` 預設測試視窗為 `800×600`（`flutter_test/lib/src/binding.dart:99`，寬>高即橫向，`_pageSize` 預設為 4），既有多數未手動設定 `tester.view.physicalSize` 的測試因此落在每頁 4 項的分支。综合以上，既有測試理論上不會被**分頁邏輯**破壞，但 Task 3 仍會執行一次全套 `library_screen_test.dart` 作為安全網（若真的發現受影響的既有測試，判斷原則：若該測試情境的項目數不超過當下方向的每頁容量，屬於本計劃查證疏漏，改用等於或小於每頁容量的資料量重寫；若該測試恰好在驗證分頁前「多本同時可見」的假設且該假設已被本 Issue 的驗收標準明確推翻，改寫為透過 `PagingBar` 換頁後逐頁驗證）。**（`review-plan-issue-3.md` I-1 修正）**：這項查證當時只涵蓋 Task 3 的分頁/捲動行為，沒有涵蓋 Task 4 才引入的 `_ContinueReadingRow`——後者會在頂層書架另外渲染 `book.title`／進度文字，見下方第 8 點。
7. **`_openGroupFilteredView`／`_exitGroupFilteredView` 補上 `_currentPage = 0`，兌現 Issue 2 計劃的明文延後事項**：`plans/plan-issue-2.md`「計劃範圍澄清」第 3 點當時明確記錄「`_currentPage` 欄位屬於 Issue 3 才會新增，Issue 3 的計劃撰寫者屆時需要在這兩個方法裡各自補上一行 `_currentPage = 0;`」——本計劃 Task 3 兌現這個延後事項。
8. **`_ContinueReadingRow`（Task 4）會破壞 3 處既有測試的未限定範圍 `find.text` 斷言**：`_testBook()` 預設 `lastReadTime: lastReadTime ?? now`（視為已讀過），任何「畫面上只有 1 本書、未特別設定 `lastReadTime`」的既有測試，該書都會自動成為 `_mostRecentBook` 並在繼續閱讀列裡重複渲染書名／進度文字，讓 `library_screen_test.dart:132-153`（`'有書籍時，書架 grid 呈現正確渲染書籍項目...'`）與 `:311-374`（`'從閱讀器返回書架時，重新載入書籍清單...'`）共 3 處 `find.text('紅樓夢')`／`find.text('0%')`／`find.text('50%')` 斷言的計數必然對不上。已於 Task 4 Step 5 明文列出遷移步驟（改用 `find.descendant(of: find.byKey('book_item_1'), ...)` 限定查找範圍），併入 Task 4 收尾前一併修正，不留到 Task 5 才處理（`review-plan-issue-3.md` I-1）。

---

## Task 1：`library_paging.dart`（純分頁計算函式）

**Files:**
- Create: `app/lib/screens/library_paging.dart`
- Test: `app/test/screens/library_paging_test.dart`

**Interfaces:**
- Produces:
  - `int libraryPageSizeForOrientation(Orientation orientation)`
  - `int libraryPageCount(int itemCount, int pageSize)`
  - `int libraryClampPage(int page, int pageCount)`
  - `int libraryRecalculatePage({required int oldPage, required int oldPageSize, required int newPageSize})`

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/screens/library_paging_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/library_paging.dart';

void main() {
  test('libraryPageSizeForOrientation：portrait 回傳 3，landscape 回傳 4', () {
    expect(libraryPageSizeForOrientation(Orientation.portrait), 3);
    expect(libraryPageSizeForOrientation(Orientation.landscape), 4);
  });

  test('libraryPageCount：itemCount 為 0 時回傳 1（避免空頁面／除以零）', () {
    expect(libraryPageCount(0, 3), 1);
    expect(libraryPageCount(0, 4), 1);
  });

  test('libraryPageCount：一般情況無條件進位', () {
    expect(libraryPageCount(10, 3), 4);
    expect(libraryPageCount(9, 3), 3);
    expect(libraryPageCount(1, 4), 1);
    expect(libraryPageCount(4, 4), 1);
    expect(libraryPageCount(5, 4), 2);
  });

  test('libraryClampPage：頁碼超出範圍時箝制在有效區間內', () {
    expect(libraryClampPage(5, 4), 3);
    expect(libraryClampPage(-1, 4), 0);
    expect(libraryClampPage(2, 4), 2);
    expect(libraryClampPage(0, 1), 0);
  });

  test('libraryClampPage：pageCount <= 0（異常輸入）時安全回傳 0，不拋例外（review-plan-issue-3.md M-1）', () {
    expect(libraryClampPage(5, 0), 0);
    expect(libraryClampPage(5, -1), 0);
  });

  test('libraryRecalculatePage：依全域 index 比例換算新頁碼（旋轉螢幕情境）', () {
    // 舊頁 2（0-based），舊每頁 3 項，第一項全域 index = 6；換算到新每頁 4 項
    // 應落在第 1 頁（0-based），6 ~/ 4 = 1。
    expect(
      libraryRecalculatePage(oldPage: 2, oldPageSize: 3, newPageSize: 4),
      1,
    );
    expect(
      libraryRecalculatePage(oldPage: 0, oldPageSize: 3, newPageSize: 4),
      0,
    );
    // 舊頁 1，舊每頁 4 項，第一項全域 index = 4；換算到新每頁 3 項，
    // 4 ~/ 3 = 1。
    expect(
      libraryRecalculatePage(oldPage: 1, oldPageSize: 4, newPageSize: 3),
      1,
    );
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/library_paging_test.dart`
Expected: FAIL（`library_paging.dart` 不存在）

- [ ] **Step 3: 實作**

建立 `app/lib/screens/library_paging.dart`：

```dart
import 'package:flutter/widgets.dart';

/// 書架分頁的純數學計算（epic-36-adaptive-shelf-navigation Issue 3
/// spec.md §功能③）：不依賴 widget 樹、不依賴 `LibraryScreen` 任何狀態，
/// 獨立可單元測試。

/// 每頁筆數固定依螢幕方向決定（`DESIGN.md#L267`／`#L335`：直排 1 行 3
/// 欄、橫排 1 行 4 欄），格狀／清單兩種檢視一視同仁，不因檢視模式而異
/// （見 plans/plan-issue-3.md「計劃範圍澄清」第 3 點）。
int libraryPageSizeForOrientation(Orientation orientation) =>
    orientation == Orientation.landscape ? 4 : 3;

/// [itemCount] 為 0 時仍回傳 1（避免 0 頁或除以零），呼叫端據此顯示
/// 「1 / 1」而非崩潰或顯示「0 / 0」。
int libraryPageCount(int itemCount, int pageSize) =>
    itemCount == 0 ? 1 : (itemCount / pageSize).ceil();

/// 把可能越界的頁碼（例如刪除書籍/合併分類後 itemCount 減少）箝制回
/// `0..pageCount-1` 的有效範圍。`pageCount <= 0` 為異常輸入（正常情況下
/// `libraryPageCount()` 保證 >= 1，這裡仍防禦，因為本函式獨立公開、
/// 呼叫端不保證一定先過 `libraryPageCount()`，見 `review-plan-issue-3.md`
/// M-1）安全回傳 0，不拋 `ArgumentError`。
int libraryClampPage(int page, int pageCount) {
  if (pageCount <= 0) return 0;
  return page.clamp(0, pageCount - 1);
}

/// 旋轉螢幕、每頁筆數改變時，依「目前頁第一項的全域 index ÷ 新每頁
/// 容量」重新換算頁碼，讓使用者瀏覽位置大致不變（不是精確對齊，這是
/// 已知且接受的近似值，見 spec.md §功能③）。三個參數皆非負，用 Dart
/// 原生整數截斷除法 `~/`，不需要 `/`+`.floor()` 的浮點數運算
/// （`review-plan-issue-3.md` M-1）。
int libraryRecalculatePage({
  required int oldPage,
  required int oldPageSize,
  required int newPageSize,
}) => (oldPage * oldPageSize) ~/ newPageSize;
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/library_paging_test.dart`
Expected: PASS（全部案例）

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/library_paging.dart app/test/screens/library_paging_test.dart
git commit -m "feat(epic-36): 新增書架分頁純數學計算函式 library_paging.dart"
```

---

## Task 2：`PagingBar`（純呈現換頁控制列）

**Files:**
- Create: `app/lib/screens/widgets/paging_bar.dart`
- Test: `app/test/screens/widgets/paging_bar_test.dart`

**Interfaces:**
- Consumes: 無（不依賴 Task 1，`PagingBar` 本身不知道分頁邏輯，純粹接收 `currentPage`/`pageCount` 顯示）。
- Produces: `PagingBar` widget，建構參數 `currentPage`（0-based）／`pageCount`／`onPrevious`／`onNext`／`isEinkMode`（預設 `false`）；Key 契約：`paging_bar_previous_button`／`paging_bar_next_button`。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/screens/widgets/paging_bar_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/widgets/paging_bar.dart';

void main() {
  testWidgets('顯示目前頁碼與總頁數（1-based 呈現）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagingBar(
            currentPage: 1,
            pageCount: 5,
            onPrevious: () {},
            onNext: () {},
          ),
        ),
      ),
    );

    expect(find.text('2 / 5'), findsOneWidget);
  });

  testWidgets('onPrevious 為 null 時上一頁按鈕停用', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagingBar(
            currentPage: 0,
            pageCount: 3,
            onPrevious: null,
            onNext: () {},
          ),
        ),
      ),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const Key('paging_bar_previous_button')),
    );
    expect(button.onPressed, isNull);
    await tester.tap(
      find.byKey(const Key('paging_bar_previous_button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('onNext 為 null 時下一頁按鈕停用，點擊不崩潰', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagingBar(
            currentPage: 2,
            pageCount: 3,
            onPrevious: () {},
            onNext: null,
          ),
        ),
      ),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const Key('paging_bar_next_button')),
    );
    expect(button.onPressed, isNull);
    await tester.tap(
      find.byKey(const Key('paging_bar_next_button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('一般模式整體高度為 52dp，isEinkMode 時為 56dp（review-plan-issue-3.md C-1：高度需隨觸控目標自適應，不可寫死 52 夾傷 56dp 按鈕）', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagingBar(currentPage: 0, pageCount: 1, onPrevious: null, onNext: null),
        ),
      ),
    );
    expect(tester.getSize(find.byType(PagingBar)).height, 52);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagingBar(
            currentPage: 0,
            pageCount: 1,
            onPrevious: null,
            onNext: null,
            isEinkMode: true,
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(PagingBar)).height, 56);
  });

  testWidgets('一般模式觸控目標 48dp，isEinkMode 時為 56dp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagingBar(
            currentPage: 0,
            pageCount: 1,
            onPrevious: () {},
            onNext: () {},
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('paging_bar_previous_button'))),
      const Size(48, 48),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagingBar(
            currentPage: 0,
            pageCount: 1,
            onPrevious: () {},
            onNext: () {},
            isEinkMode: true,
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('paging_bar_previous_button'))),
      const Size(56, 56),
    );
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/widgets/paging_bar_test.dart`
Expected: FAIL（`paging_bar.dart` 不存在）

- [ ] **Step 3: 實作**

建立 `app/lib/screens/widgets/paging_bar.dart`：

```dart
import 'package:flutter/material.dart';

/// 書架換頁控制列（`DESIGN.md#L317` §15.1）：純呈現、無狀態，不知道
/// 分頁邏輯本身——`currentPage`/`pageCount` 由呼叫端算好傳入，
/// `onPrevious`/`onNext` 為 `null` 時代表已在邊界頁，按鈕自動停用。
class PagingBar extends StatelessWidget {
  final int currentPage; // 0-based
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool isEinkMode;

  const PagingBar({
    super.key,
    required this.currentPage,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
    this.isEinkMode = false,
  });

  @override
  Widget build(BuildContext context) {
    // 觸控目標依 DESIGN.md §7.2：一般模式 48dp、E-Ink 模式 56dp。用
    // SizedBox 給 IconButton 緊約束（tight constraints），確保實際渲染
    // 尺寸精確等於指定值，不受 IconButton 內建最小尺寸影響。
    final buttonSize = isEinkMode ? 56.0 : 48.0;
    // `DESIGN.md#L344` 原文是「高度最小 52dp」，不是寫死 52——E-Ink 模式
    // 按鈕本身就要 56dp，外層若仍固定 52 會把 56dp 的子項在 cross axis
    // 方向夾扁回 52（`SizedBox` 對子項的 tight constraints 會被父層更小
    // 的 maxHeight `enforce()` 蓋掉），E-Ink 觸控目標實際上根本沒有做到
    // 56dp（`review-plan-issue-3.md` C-1）。外層高度改為跟隨按鈕尺寸。
    final barHeight = isEinkMode ? 56.0 : 52.0;
    return SizedBox(
      height: barHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: buttonSize,
            height: buttonSize,
            child: IconButton(
              key: const Key('paging_bar_previous_button'),
              icon: const Icon(Icons.chevron_left),
              tooltip: '上一頁',
              onPressed: onPrevious,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('${currentPage + 1} / $pageCount'),
          ),
          SizedBox(
            width: buttonSize,
            height: buttonSize,
            child: IconButton(
              key: const Key('paging_bar_next_button'),
              icon: const Icon(Icons.chevron_right),
              tooltip: '下一頁',
              onPressed: onNext,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/widgets/paging_bar_test.dart`
Expected: PASS（全部案例）

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/widgets/paging_bar.dart app/test/screens/widgets/paging_bar_test.dart
git commit -m "feat(epic-36): 新增 PagingBar 換頁控制列元件"
```

---

## Task 3：`LibraryScreen` 串接分頁邏輯（無限捲動→固定每頁換頁）

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `libraryPageSizeForOrientation`／`libraryPageCount`／`libraryClampPage`／`libraryRecalculatePage`；Task 2 的 `PagingBar`。
- Produces：`_LibraryScreenState` 新增欄位 `int _currentPage`／`int? _lastPageSize`，新增 `with WidgetsBindingObserver`；新增 `Key('library_paging_bar')`（`PagingBar` 實例）、`paging_bar_previous_button`／`paging_bar_next_button`（Task 2 已定義，這裡是實際掛載點）。

- [ ] **Step 1: 寫失敗測試——新增分頁核心回歸測試**

在 `app/test/screens/library_screen_test.dart` 的 `main()` 內、既有 `long按進入選取模式後...` 測試群組附近（任一位置皆可，本檔案既有測試彼此無順序依賴）新增：

```dart
  testWidgets('直向（3 項/頁）與橫向（4 項/頁）第一頁顯示的項目數正確', (tester) async {
    final books = List.generate(5, (i) => _testBook(id: '$i', title: '書$i'));

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

    expect(find.byKey(const Key('book_item_0')), findsOneWidget);
    expect(find.byKey(const Key('book_item_1')), findsOneWidget);
    expect(find.byKey(const Key('book_item_2')), findsOneWidget);
    expect(find.byKey(const Key('book_item_3')), findsNothing, reason: '直向每頁只顯示 3 項');
    expect(find.text('1 / 2'), findsOneWidget);

    tester.view.physicalSize = const Size(1200, 800); // landscape
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('book_item_3')),
      findsOneWidget,
      reason: '橫向每頁顯示 4 項，旋轉後第一頁應多出第 4 項',
    );
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('點擊 PagingBar 下一頁/上一頁切換書架顯示的書籍', (tester) async {
    final books = List.generate(5, (i) => _testBook(id: '$i', title: '書$i'));

    tester.view.physicalSize = const Size(800, 1200); // portrait，pageSize=3
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

    expect(find.byKey(const Key('book_item_0')), findsOneWidget);
    expect(find.byKey(const Key('book_item_3')), findsNothing);
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('paging_bar_next_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_0')), findsNothing);
    expect(find.byKey(const Key('book_item_3')), findsOneWidget);
    expect(find.byKey(const Key('book_item_4')), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('paging_bar_previous_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_item_0')), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('旋轉螢幕時目前頁碼依新每頁容量正確換算，不跳到看不懂的地方', (tester) async {
    final books = List.generate(10, (i) => _testBook(id: '$i', title: '書$i'));

    tester.view.physicalSize = const Size(800, 1200); // portrait，pageSize=3
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

    await tester.tap(find.byKey(const Key('paging_bar_next_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('paging_bar_next_button')));
    await tester.pumpAndSettle();
    // 10 本書，pageSize 3 → pageCount = 4；目前在第 3 頁（0-based page=2），
    // 第一項全域 index = 6。
    expect(find.text('3 / 4'), findsOneWidget);
    expect(find.byKey(const Key('book_item_6')), findsOneWidget);

    tester.view.physicalSize = const Size(1200, 800); // landscape，pageSize=4
    await tester.pumpAndSettle();

    // libraryRecalculatePage(oldPage: 2, oldPageSize: 3, newPageSize: 4)
    // = floor(6/4) = 1 → 顯示「2 / 3」（pageCount = ceil(10/4) = 3）。
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.byKey(const Key('book_item_4')), findsOneWidget);
  });

  testWidgets('切換排序條件後頁碼重置為第一頁', (tester) async {
    final books = List.generate(5, (i) => _testBook(id: '$i', title: '書$i'));

    tester.view.physicalSize = const Size(800, 1200); // portrait，pageSize=3
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

    await tester.tap(find.byKey(const Key('paging_bar_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_sort_view_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_sort_option_title')));
    await tester.pumpAndSettle();

    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('進入/離開分類下鑽時頁碼重置為第一頁', (tester) async {
    final groupBooks = List.generate(
      5,
      (i) => _testBook(id: 'g$i', title: '分類書$i', groupName: '奇幻'),
    );

    tester.view.physicalSize = const Size(800, 1200); // portrait，pageSize=3
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
    // 5 本書，pageSize 3 → pageCount = 2。
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('paging_bar_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_back_from_group_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    expect(
      find.text('1 / 2'),
      findsOneWidget,
      reason: '再次下鑽同一分類時頁碼應已重置，不殘留上次離開時的頁碼',
    );
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/library_screen_test.dart --name "第一頁顯示的項目數正確|切換書架顯示的書籍|不跳到看不懂的地方|頁碼重置為第一頁"`
Expected: FAIL（`PagingBar`／分頁邏輯尚未接上，`paging_bar_next_button` 等 Key 不存在）

- [ ] **Step 3: 實作**

編輯 `app/lib/screens/library_screen.dart`：

**3a. import 新增**：

```dart
import 'library_paging.dart';
import 'widgets/paging_bar.dart';
```

**3b. `_LibraryScreenState` 新增 `WidgetsBindingObserver` 與分頁欄位**：

```dart
class _LibraryScreenState extends State<LibraryScreen> with WidgetsBindingObserver {
  final _preferences = LibraryPreferences();
  late final LibraryBookListController _bookListController;
  late final LibraryBatchActions _batchActions;

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
```

**3c. `initState()`／`dispose()` 註冊/解除 `WidgetsBindingObserver`**：

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bookListController = LibraryBookListController(
      repository: widget.repository,
    )..addListener(_onBookListChanged);
    _batchActions = LibraryBatchActions(repository: widget.repository);
    widget.refreshSignal?.addListener(_onExternalRefreshRequested);
    _initialize();
  }
```

```dart
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.refreshSignal?.removeListener(_onExternalRefreshRequested);
    _bookListController.dispose();
    super.dispose();
  }
```

**3d. 新增 `didChangeMetrics()`（見「計劃範圍澄清」第 2 點——一律用 `View.of(context).physicalSize`，不可用 `MediaQuery.orientationOf(context)`）**：

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

**3e. `_openGroupFilteredView`／`_exitGroupFilteredView` 補上頁碼重置（兌現 Issue 2 的延後事項，見「計劃範圍澄清」第 7 點）**：

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

**3f. 新增 `_changeSortBy()`，取代 AppBar 選單直接呼叫 `_bookListController.changeSortBy`**：

```dart
  void _changeSortBy(LibrarySortBy sortBy) {
    setState(() => _currentPage = 0);
    _bookListController.changeSortBy(sortBy);
  }
```

`_buildNormalAppBar()` 內排序選單項目的 `onTap` 改為：

```dart
                PopupMenuItem<void>(
                  key: Key('library_sort_option_${sortBy.name}'),
                  onTap: () => _changeSortBy(sortBy),
```

（其餘 `PopupMenuItem` 內容不變，只改這一行 `onTap`。）

**3g. `_buildBookList()` 整段改為分頁渲染**：

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
    // M-2）。比照下方 `_lastPageSize = pageSize;` 同樣的既有寫法。
    _currentPage = safePage;
    final pageStart = safePage * pageSize;
    final pageEnd = (pageStart + pageSize).clamp(0, itemCount);

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
            )
          : _BookListTile(
              book: book,
              selectionMode: _inSelectionMode,
              selected: selectedIds?.contains(book.id) ?? false,
              onTap: () => _onBookTap(book),
              onLongPress: () => _onBookLongPress(book),
            );
    }

    final pageItemCount = pageEnd - pageStart;
    final Widget gridOrList;
    if (_viewMode == LibraryViewMode.grid) {
      final crossAxisCount = orientation == Orientation.landscape ? 4 : 3;
      gridOrList = GridView.builder(
        key: const Key('library_grid_view'),
        padding: const EdgeInsets.all(8),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.62,
          crossAxisSpacing: 8,
          mainAxisSpacing: 12,
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
        Expanded(child: Align(alignment: Alignment.topCenter, child: gridOrList)),
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
      ],
    );
  }
```

（`crossAxisCount` 與 `pageSize` 在數值上恆相等——這是設計上的內部一致性：一頁固定顯示「一整排」，見「計劃範圍澄清」第 3 點；兩者刻意分開計算而非共用一個變數，因為前者是 `GridView` 排版參數、後者是分頁筆數，語意不同，只是巧合地同值。）

- [ ] **Step 4: 執行新測試確認通過**

Run: `flutter test test/screens/library_screen_test.dart --name "第一頁顯示的項目數正確|切換書架顯示的書籍|不跳到看不懂的地方|頁碼重置為第一頁"`
Expected: 上述新增測試 100% PASS。

- [ ] **Step 5: 執行整個 `library_screen_test.dart`，依「計劃範圍澄清」第 6 點的判斷原則修正任何既有測試**

Run: `flutter test test/screens/library_screen_test.dart`

反覆執行、依失敗訊息修正，直到全數 PASS（規劃階段查證判斷不會有既有測試受影響，若真的出現失敗，逐一核對是否符合「計劃範圍澄清」第 6 點列出的兩種修正情境，不得略過或silently跳過任何失敗）。

Expected: PASS（全部案例，0 失敗——本 Task 收尾 Commit 前必須全綠，`review-plan-issue-2.md` I-1 教訓）

- [ ] **Step 6: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-36): 書架瀏覽改為固定每頁一整排的 PagingBar 換頁，移除無限捲動"
```

---

## Task 4：繼續閱讀列 `_ContinueReadingRow`

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `_buildBookList()` Column 結構（本 Task 在其最上方新增一個條件式 child）。
- Produces：`_LibraryScreenState` 新增欄位 `Book? _mostRecentBook`；新增私有 widget `_ContinueReadingRow`，Key 契約：`library_continue_reading_row`。

- [ ] **Step 1: 寫失敗測試——5 則情境測試**

在 `app/test/screens/library_screen_test.dart` 新增：

```dart
  testWidgets('書庫全空時不渲染繼續閱讀列', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_continue_reading_row')), findsNothing);
  });

  testWidgets('有書籍但全部 lastReadTime 為 epoch 0（從未閱讀）時不渲染繼續閱讀列', (
    tester,
  ) async {
    final bookA = _testBook(
      id: '1',
      title: 'A書',
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
    );
    final bookB = _testBook(
      id: '2',
      title: 'B書',
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [bookA, bookB]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_continue_reading_row')), findsNothing);
  });

  testWidgets('至少一本書 lastReadTime > 0 時渲染繼續閱讀列，顯示最近閱讀那本並可點擊繼續閱讀', (
    tester,
  ) async {
    final older = _testBook(
      id: 'older',
      title: '較早閱讀的書',
      lastReadTime: DateTime(2026, 1, 1),
      filePath: 'content://example/older.txt',
    );
    final newer = _testBook(
      id: 'newer',
      title: '最近閱讀的書',
      lastReadTime: DateTime(2026, 6, 1),
      filePath: 'content://example/newer.txt',
    );
    final neverRead = _testBook(
      id: 'never',
      title: '沒讀過的書',
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository:
              FakeLibraryRepository(initialBooks: [older, newer, neverRead]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_continue_reading_row')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('library_continue_reading_row')),
        matching: find.text('最近閱讀的書'),
      ),
      findsOneWidget,
      reason: '應顯示 lastReadTime 最新的那一本，而不是任何一本有讀過的書',
    );

    await tester.tap(find.byKey(const Key('library_continue_reading_row')));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderScreen), findsOneWidget);
  });

  testWidgets('下鑽檢視分類時不渲染繼續閱讀列', (tester) async {
    final book = _testBook(
      id: '1',
      title: 'A書',
      groupName: '奇幻',
      lastReadTime: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library_continue_reading_row')), findsOneWidget);

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('library_continue_reading_row')),
      findsNothing,
      reason: '繼續閱讀列是頂層書架的常駐列，下鑽檢視分類時不應出現',
    );
  });

  testWidgets('多選模式進行中，繼續閱讀列不可點擊（review-plan-issue-3.md M-3：避免無勾選指示反饋卻誤觸切換選取狀態）', (
    tester,
  ) async {
    final mostRecent = _testBook(
      id: 'recent',
      title: '最近閱讀的書',
      lastReadTime: DateTime(2026, 6, 1),
    );
    final other = _testBook(
      id: 'other',
      title: '另一本書',
      lastReadTime: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [mostRecent, other]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library_continue_reading_row')), findsOneWidget);

    await tester.longPress(find.byKey(const Key('book_item_other')));
    await tester.pumpAndSettle();
    expect(find.text('已選取 1 本'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('library_continue_reading_row')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(
      find.text('已選取 1 本'),
      findsOneWidget,
      reason: '點擊繼續閱讀列不應該把 mostRecent 加進選取集合，選取數量應維持不變',
    );
    expect(find.byType(ReaderScreen), findsNothing);
  });
```

（`_testBook()` 預設 `lastReadTime: lastReadTime ?? now`，即預設視為「已讀過」；上述測試需要「從未閱讀」情境時皆已明確傳入 `DateTime.fromMillisecondsSinceEpoch(0)`，比照 `book_import_service_impl.dart:434` 既有的「從未閱讀」sentinel 值寫法。）

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/library_screen_test.dart --name "繼續閱讀列|多選模式進行中，繼續閱讀列不可點擊"`
Expected: FAIL（`library_continue_reading_row` 不存在）

- [ ] **Step 3: 實作**

編輯 `app/lib/screens/library_screen.dart`：

**3a. `_LibraryScreenState` 新增 `_mostRecentBook` 欄位**（緊接在 `_lastPageSize` 之後）：

```dart
  /// 使用者最後閱讀的書籍（`lastReadTime` 最新且 > epoch 0 者），供頂層
  /// 書架的常駐「繼續閱讀列」使用；`_onBookListChanged()` 每次書籍清單
  /// 變動時重新計算。
  Book? _mostRecentBook;
```

**3b. `_onBookListChanged()` 改為同時重新計算 `_mostRecentBook`**：

```dart
  void _onBookListChanged() {
    if (!mounted) return;
    setState(() => _mostRecentBook = _computeMostRecentBook());
  }

  Book? _computeMostRecentBook() {
    final books = _bookListController.books;
    if (books == null) return null;
    Book? mostRecent;
    for (final book in books) {
      if (book.lastReadTime.millisecondsSinceEpoch <= 0) continue;
      if (mostRecent == null || book.lastReadTime.isAfter(mostRecent.lastReadTime)) {
        mostRecent = book;
      }
    }
    return mostRecent;
  }
```

**3c. `_buildBookList()` 的 `Column` 最上方新增條件式 `_ContinueReadingRow`**：

```dart
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
        Expanded(child: Align(alignment: Alignment.topCenter, child: gridOrList)),
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
      ],
    );
```

（只新增最上方那個 `if` child，`Expanded`／`PagingBar` 兩個既有 child 內容不變。）

**3d. 新增 `_ContinueReadingRow` private widget**（放在檔案內既有 `_GroupTile`／`_GroupGridTile` 等 private widget 群組附近，例如 `_BookListTile` 類別定義之後）：

```dart
/// 頂層書架常駐「繼續閱讀列」（`DESIGN.md#L297` §15.1）：顯示使用者最後
/// 閱讀的那本書與進度，點擊直接跳轉繼續閱讀；不受下方分頁影響，
/// `_activeGroupFilter != null`（下鑽檢視分類）時由呼叫端負責不渲染
/// 本元件，本元件本身不做這個判斷。
class _ContinueReadingRow extends StatelessWidget {
  final Book book;
  final VoidCallback? onTap; // null＝多選模式進行中，停用點擊（見呼叫端註解）

  const _ContinueReadingRow({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('library_continue_reading_row'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            SizedBox(width: 40, height: 56, child: BookCover(book: book)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('繼續閱讀', style: TextStyle(fontSize: 12)),
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(_progressText(book), style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 執行新測試確認通過**

Run: `flutter test test/screens/library_screen_test.dart --name "繼續閱讀列|多選模式進行中，繼續閱讀列不可點擊"`
Expected: 5 則新測試 100% PASS。

- [ ] **Step 5: 既有測試遷移——3 處未限定範圍的 `find.text` 斷言（`review-plan-issue-3.md` I-1）**

`_ContinueReadingRow` 會在頂層書架渲染 `Text(book.title)`／`Text(_progressText(book))`，任何「只有 1 本書、該書 `lastReadTime` 使用 `_testBook()` 預設值（即視為已讀過）」的既有測試，會讓這本書同時成為 `_mostRecentBook`，導致下列既有斷言重複計數、必然失敗。逐一修正：

**5a. `library_screen_test.dart:132-153`**（測試名稱：`'有書籍時，書架 grid 呈現正確渲染書籍項目（標題、進度固定 0%）'`）。第 151-152 行改為：

```dart
    final bookItemFinder = find.byKey(const Key('book_item_1'));
    // Issue 9：該書無 coverPath，BookCover 退回 CoverPlaceholder，其內建的
    // 書名縮略文字跟 _BookGridTile 本身的標題 caption 各自顯示一次「紅樓
    // 夢」，兩者皆是核准設計、非回歸，預期恰好 2 個匹配；限定在
    // book_item_1 範圍內查找，避免繼續閱讀列（Issue 3）額外渲染的同名
    // 文字被誤計入（`review-plan-issue-3.md` I-1）。
    expect(
      find.descendant(of: bookItemFinder, matching: find.text('紅樓夢')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: bookItemFinder, matching: find.text('0%')),
      findsOneWidget,
    );
```

**5b. `library_screen_test.dart:311-374`**（測試名稱：`'從閱讀器返回書架時，重新載入書籍清單，避免後續操作以過期資料覆寫最新進度'`）。第 336 行改為：

```dart
    expect(
      find.descendant(
        of: find.byKey(const Key('book_item_1')),
        matching: find.text('0%'),
      ),
      findsOneWidget,
    );
```

第 365-370 行附近改為：

```dart
    expect(
      find.descendant(
        of: find.byKey(const Key('book_item_1')),
        matching: find.text('50%'),
      ),
      findsOneWidget,
      reason:
          '返回書架後應重新載入書籍清單，顯示閱讀器寫入的最新進度，'
          '而非停留在舊快照的 0%',
    );
```

**驗證方式**：修正前先執行 `flutter test test/screens/library_screen_test.dart` 確認這兩則測試確實因 Step 3 的改動而失敗（重複計數），修正後再次執行確認轉為 PASS——不得跳過「先確認真的紅燈」這一步，避免誤判成本次改動無關的既有失敗。

- [ ] **Step 6: 執行整個 `library_screen_test.dart` 確認無回歸**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: PASS（全部案例，0 失敗——本 Task 收尾 Commit 前必須全綠，`review-plan-issue-2.md` I-1 教訓）

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-36): 新增書架常駐繼續閱讀列 _ContinueReadingRow"
```

---

## Task 5：全套驗證與收尾

**Files:** 無新增/修改，純驗證。

- [ ] **Step 1: 執行全套 `flutter test`（不帶檔案路徑）**

Run: `flutter test`
Expected: 全數通過（比照 `CLAUDE.md`「測試執行範圍」，這是整份計劃收尾的唯一一次全套執行）。若有失敗，比對是否為本計劃改動觸及的檔案；非本計劃觸及範圍的既有不穩定測試（例如已追蹤的 `epic-37-test-suite-flakiness`）記錄下來，不在本 Issue 修復範圍內。

- [ ] **Step 2: 執行 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 逐條核對 `issues.md` Issue 3 驗收標準**

- [ ] 書架瀏覽改為固定每頁一整排的換頁控制列（直向 3／橫向 4），無限捲動行為移除
- [ ] 旋轉螢幕時頁碼正確換算、不跳到看不懂的地方
- [ ] 繼續閱讀列依三種邊界條件正確顯示/隱藏
- [ ] `flutter analyze` 乾淨、`flutter test` 全數通過

- [ ] **Step 4: 更新 `docs/epics.md` 備註欄位**

將 Epic 36 該列備註改為「Issue 1-3 已完成，待認領 Issue 4/5」（執行時以 `issues.md` 實際狀態為準調整措辭，Issue 5 若已由其他人平行完成則一併反映）。

- [ ] **Step 5: 依 `superpowers:requesting-code-review` 發起本 Issue 的程式碼審查**

審查者先產出報告至 `docs/epics/epic-36-adaptive-shelf-navigation/reviews/review-issue-3.md`，不得直接修改程式碼（比照專案 SDD 工作流程第 6 步）。審查請求內容須包含「計劃範圍澄清」第 2 點的 `didChangeMetrics()`／`MediaQuery` 時序備註，供審查者重點覆核這處容易寫錯但不容易在一般測試環境下被發現的細節。

---

## Self-Review 紀錄（撰寫本計劃時的覆核結果）

- **Spec 覆蓋**：`spec.md` §功能③／`issues.md` Issue 3 的 Solution 逐條對照——`PagingBar`（Task 2）、`_pageSize`/`GridView`/`ListView` 改為 `shrinkWrap`+分頁（Task 3）、旋轉換算（Task 3 `didChangeMetrics()`，含關鍵時序修正）、排序/分類切換重置頁碼（Task 3，含兌現 Issue 2 延後事項）、繼續閱讀列三種邊界條件（Task 4）皆有對應 Task，無遺漏。
- **`issues.md`「單元測試要求」四項逐條對照**：`PagingBar` 純 widget test（Task 2）、分頁計算純函式獨立單元測試（Task 1）、portrait/landscape 個別頁面項目數（Task 3 Step 1 第一則測試）、繼續閱讀列三種情境（Task 4，另加下鑽時隱藏的第四則測試呼應 `spec.md` 明文要求）皆已納入。
- **型別一致性**：`libraryPageSizeForOrientation`／`libraryPageCount`／`libraryClampPage`／`libraryRecalculatePage` 在 Task 1 定義（具名參數 `oldPage`/`oldPageSize`/`newPageSize`），Task 3 的 `didChangeMetrics()`／`_buildBookList()` 原樣使用，命名與參數簽章一致；`PagingBar` 的 `currentPage`/`pageCount`/`onPrevious`/`onNext`/`isEinkMode` 在 Task 2 定義、Task 3/4 建構時原樣使用。
- **範圍落差已於「計劃範圍澄清」段落明文記錄並解決**：無搜尋列可依附的渲染位置調整（第 1 點）、`didChangeMetrics()` 內 `MediaQuery` 時序缺陷（第 2 點，屬於本計劃規劃階段發現、若逐字套用 spec.md 字面指示會導致旋轉換算永遠不觸發的功能性缺陷）、`_pageSize` 不分檢視模式的設計確認（第 3 點）、管理分類/檢視模式切換不重置頁碼的範圍邊界（第 4、5 點）、既有測試相容性查證（第 6 點，含 `review-plan-issue-3.md` I-1 修正後補上的第 8 點範圍澄清）、兌現 Issue 2 延後事項（第 7 點）。

## 複審修訂紀錄（`reviews/review-plan-issue-3.md`，2026-09-05）

- **C-1（Critical，已修正）**：Task 2 `PagingBar` 外層 `SizedBox` 原本固定 `height: 52`，`isEinkMode: true` 時內部按鈕要求的 `56dp` 高度會被父層更小的 `maxHeight` 約束 `enforce()` 蓋掉、實際渲染縮回 52dp，導致 E-Ink 觸控目標名不副實、Task 2 Step 1 的尺寸斷言也會失敗。已改為 `barHeight = isEinkMode ? 56.0 : 52.0` 隨觸控目標自適應（`DESIGN.md#L344` 原文本來就是「高度最小 52dp」，不是寫死），Task 2 Step 1 高度測試同步擴充為驗證一般/E-Ink 兩種高度。
- **I-1（Important，已修正）**：Task 4 引入 `_ContinueReadingRow` 會破壞 `library_screen_test.dart` 3 處既有測試（`:132-153`／`:311-374`）未限定範圍的 `find.text('紅樓夢')`／`find.text('0%')`／`find.text('50%')` 斷言（重複計數）——這項既有測試影響先前遺漏於「計劃範圍澄清」第 6 點的查證範圍（該點只涵蓋 Task 3 分頁邏輯）。已在 Task 4 新增 Step 5 明文列出遷移步驟（改用 `find.descendant` 限定 `book_item_1` 範圍），並在「計劃範圍澄清」新增第 8 點記錄這個範圍邊界。
- **I-2（Important，已修正）**：`didChangeMetrics()` 未防護 `physicalSize.isEmpty`——Android 應用退到背景/螢幕休眠/多視窗調整等情境下 `physicalSize` 可能暫時回報 `0x0`，`0 > 0` 為 `false` 會被誤判為 portrait，若裝置原本是 landscape 會觸發一次錯誤的頁碼換算。已在 Task 3 Step 3d 讀取 `physicalSize` 後立即加上 `if (physicalSize.isEmpty) return;` 防護。
- **M-1（Minor，已採納）**：`libraryRecalculatePage` 改用 Dart 原生整數截斷除法 `~/`（三個參數皆非負，功能等價於原本的 `/`+`.floor()`，更地道且免浮點數運算）；`libraryClampPage` 補上 `pageCount <= 0` 防禦，避免異常輸入時 `page.clamp(0, -1)` 拋出 `ArgumentError`，Task 1 新增對應單元測試。
- **M-2（Minor，已採納）**：`_buildBookList()` 計算出 `safePage` 後補上 `_currentPage = safePage;`（純賦值、非 `setState`，比照既有 `_lastPageSize = pageSize;` 的寫法），避免 `itemCount` 因批次刪除等操作縮減後，`_currentPage` 欄位持續殘留越界值、影響之後 `didChangeMetrics()` 的換算基準。
- **M-3（Minor，已採納）**：`_ContinueReadingRow` 的 `onTap` 在 `_inSelectionMode` 時傳 `null`（比照 `_GroupGridTile`／`_GroupListTile` 既有慣例），避免使用者在多選模式下點擊繼續閱讀列時，在毫無勾選指示反饋的情況下誤觸切換 `_mostRecentBook` 的選取狀態；`_ContinueReadingRow.onTap` 型別同步改為 `VoidCallback?`，Task 4 新增對應回歸測試。
