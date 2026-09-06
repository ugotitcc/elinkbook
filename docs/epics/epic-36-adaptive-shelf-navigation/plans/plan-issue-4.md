# Epic 36 Issue 4：單書「⋮」動作選單 `BookActionSheet` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（recommended）or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增以書本卡片上「⋮」圖示觸發、與長按多選互斥的單書動作選單，提供「詳細資料／移動／版面覆寫／移除快取／刪除」五個選項，重用既有批次操作底層邏輯；「版面覆寫」對話框必須保留該書其他既有個人化設定不被清空。

**Architecture：** 新增兩個獨立、可脫離 `LibraryScreen` 單元測試的公開元件——`EBSheetShell`（`DESIGN.md` §10 基礎 Bottom Sheet 外殼，本 Epic 首次落地，只給本 Issue 用）與 `BookActionSheet`（純呈現的五選項清單）。`library_screen.dart` 是唯一整合點：`_BookGridTile`／`_BookListTile` 新增 `onMenuTap` 建構參數並疊加 `book_action_menu_${id}` 圖示，`_LibraryScreenState` 新增 `_openBookActionSheet()`／五個對應處理方法／兩個新的 private 對話框（`_BookDetailsDialog`／`_LayoutOverrideDialog`），皆重用既有 `LibraryBatchActions`／`_confirmDeleteBooks()`／`LibraryMoveToGroupDialog` 底層邏輯，不重寫。

**Tech Stack：** Flutter 3.41.9（`showModalBottomSheet` 的 `sheetAnimationStyle`／`AnimationStyle.noAnimation` 已原生支援，見「計劃範圍澄清」查證）；既有 `flutter_test` widget test 慣例；`BookReaderPrefsRepository` 為具體類別（非 abstract interface），既有 `test/support/fake_book_reader_prefs_repository.dart`（`implements`）與本檔案既有的真實 `BookReaderPrefsRepository(libraryRepository.database)`（`sqflite_common_ffi` in-memory）兩種既有測試替身可用。

**Spec：** `docs/epics/epic-36-adaptive-shelf-navigation/spec.md` §功能④、`docs/epics/epic-36-adaptive-shelf-navigation/issues.md` Issue 4、上游 `DESIGN.md` §10（底部抽屜模式）／§11.3（單書動作選單）。

## Global Constraints

- 本 Epic 全程只碰 Navigation／Library UI／Settings UI／Bottom sheets／Dialogs／Layout，不碰 OPDS／WebDAV／雲端來源實作、書籍儲存、閱讀進度持久化等核心架構清單項目（`UI_DESIGN_RULES.md`）。
- `EBButton`／`EBIconButton`／`EBStepper`／`EBRadius` 等 `DESIGN.md` 第一層基礎元件命名本 Epic 明確排除（`spec.md` Out of Scope）；`EBSheetShell` 內部圓角/顏色值一律直接寫字面值，不預先建立這些空殼型別。
- 既有 `NotesBottomSheet`／閱讀器內既有 Bottom Sheet 改用新建的 `EBSheetShell`：不在本 Issue 範圍內，`EBSheetShell` 本次只有 `BookActionSheet` 一個使用者。
- 每個 Task 完成後只跑該 Task 實際觸及的測試檔，全套 `flutter test`（不帶路徑）留到最後一個 Task 收尾時執行一次（比照 `CLAUDE.md`「測試執行範圍」）。
- `flutter analyze` 必須在每個 Task 結束時保持乾淨（`No issues found!`）。
- **（`review-plan-issue-2.md` I-1 教訓沿用）**：任何 Task 的收尾 Commit 前，該 Task 實際觸及的測試檔必須 100% PASS，不得把已知失敗留到下一個 Task 才修。

## 計劃範圍澄清（撰寫本計劃時發現並解決的 spec.md 內部落差）

1. **`BookActionSheet` 建構子缺少 `showLayoutOverride` 欄位，spec.md 本身前後矛盾**：spec.md「模組」段落給的 `BookActionSheet` 建構子片段只有 `showRemoveCache`（`bool`）控制「移除快取」選項是否渲染，`onLayoutOverride` 型別是非 nullable 的 `VoidCallback`，沒有對應的布林旗標；但同一份 spec.md 稍後在「`library_screen.dart`（異動）」段落又明文要求「`widget.readerFeatureRepositories.bookReaderPrefsRepository == null` 時『版面覆寫』選項整項不顯示（比照 `showRemoveCache` 的不渲染慣例，而非停用）」——這個行為在只給定的建構子欄位下無法實現。查證後確認這是 spec.md 撰寫時的遺漏（後面的行為要求明確存在，只是前面的型別片段忘了同步），不是刻意的設計決定。本計劃在 `BookActionSheet` 補上 `final bool showLayoutOverride;`，語意與渲染邏輯完全比照 `showRemoveCache`；`onLayoutOverride` 維持 spec.md 原文的非 nullable `VoidCallback`（呼叫端一律準備好回呼，只是選項本身依 `showLayoutOverride` 決定要不要渲染）。
2. **關鍵正確性修正：`_LayoutOverrideDialog` 儲存邏輯不可用 spec.md 範例程式碼裡的 `copyWith()`**——spec.md「版面覆寫對話框」段落文字本身已經講對原則（「必須先 `load()` 取得完整既有 `BookReaderPrefs`...再 `copyWith()` 只改這兩個欄位」），但緊接著的程式碼註解只寫「`_existingPrefs.copyWith(writingModeOverride: ..., pageTurnModeOverride: ...)` 後 `save()`」，這行範例程式碼本身有一個未被文字說明覆蓋到的缺陷：查證 `app/lib/reader/book_reader_prefs.dart:296-363` 的 `copyWith()` 實作，其語意是 `newValue ?? this.value`（文件註解明講「不支援明確清成 null」），也就是說當使用者在對話框裡選擇「使用預設」（本地狀態明確為 `null`，語意上想把該欄位清空）時，`copyWith(writingModeOverride: null)` 的 `null ?? this.writingModeOverride` 只會落回原本的值，完全不會被清空——這正是使用者故事 33「能讓我...不影響全域預設值」所要求的「清回預設」情境，若照抄範例程式碼會讓這個情境靜默失效（選了「使用預設」，儲存後其實還是原本的覆寫值）。查證同檔案 `app/lib/screens/reader_settings_sheet.dart:186-208` 的既有 `_currentDraft` getter，發現本專案早有解法：需要明確清空欄位的情境一律用 `BookReaderPrefs(...)` 整列建構、把每個既有欄位原樣帶入、只有真正要改變的欄位改用本地狀態變數（可為 `null`），不使用 `copyWith()`（`book_reader_prefs.dart:365-374` 的 `reflowableEpubFields()` 文件註解也明講這個既有慣例：「刻意不使用 `copyWith()`——`copyWith()` 是 `newValue ?? this.value` 語意，無法明確把欄位清成 `null`」）。本計劃 `_LayoutOverrideDialog._save()` 比照 `_currentDraft` 既有寫法，整列重建 29 個欄位（`writingModeOverride`／`pageTurnModeOverride` 用本地狀態、其餘 27 個原樣帶入既有值），Task 5 的核心回歸測試明確涵蓋「選『使用預設』後真的清成 null」這個情境，不只測「改成別的覆寫值」這種會漏掉本缺陷的弱斷言。
3. **`onRemoveCache`／`onDelete` 完成後「重新計算 `_mostRecentBook`」已由 Issue 3 既有機制自動達成，不需要額外程式碼**——spec.md 文字讀起來像是要求一個獨立的「重新計算」步驟，但查證 `app/lib/screens/library_screen.dart:136-152`（`epic-36` Issue 3 引入）：`_bookListController` 的建構式已經 `addListener(_onBookListChanged)`，而 `_onBookListChanged()` 本身就會 `setState(() => _mostRecentBook = _computeMostRecentBook())`；`LibraryBookListController.loadBooks()`（`library_book_list_controller.dart:91`）成功時一律呼叫 `notifyListeners()`。也就是說，任何呼叫端只要呼叫了 `await _bookListController.loadBooks();`，`_mostRecentBook` 就會自動重新計算——這正是既有 `_moveSelectedBooksToGroup()`／`_forceFixedLayoutForSelectedBooks()`／`_deleteSelectedBooks()`／`_removeLocalCacheForSelectedBooks()` 四個既有批次方法的既有寫法，它們從未手動重新計算過任何衍生狀態，也從未因此出過問題。本計劃 Task 4 的單書版本方法比照這四個既有方法的既有寫法，呼叫 `_bookListController.loadBooks()` 即完整滿足 spec.md 的正確性要求，Task 4 附帶一則整合回歸測試直接驗證「刪除 `_mostRecentBook` 後繼續閱讀列同步消失」，證明這個既有機制確實涵蓋這個新情境，不需要額外寫程式碼。
4. **`_testBook()` 測試輔助函式擴充 `source`／`isDownloaded` 兩個可選參數，向下相容**：既有 `_testBook()`（`app/test/screens/library_screen_test.dart:3882`）目前把 `source` 寫死為 `BookSource.local`、`isDownloaded` 完全未傳入（因此吃 `Book` 建構子自己的預設值 `true`）。本 Issue 的測試需要建立「Calibre 來源且已下載」（`showRemoveCache` 為 true 的情境）與「未下載」（`_BookDetailsDialog` 顯示「尚未下載」的情境）的書籍，故新增 `BookSource source = BookSource.local`／`bool isDownloaded = true` 兩個具名參數，預設值與現況完全相同——純加法變更，不影響任何既有呼叫點。
5. **`book_action_menu_${id}` 在格狀檢視中與既有 `book_selection_indicator_${id}` 共用同一視覺位置（右上角）**：兩者由 `selectionMode` 布林值互斥渲染（`if (selectionMode) ... else ...`），不是疊加後才手動避讓——`selectionMode == true` 時只會渲染勾選指示器、`false` 時只會渲染「⋮」，執行期畫面上兩者永遠不會同時出現，這正是 spec.md「`selectionMode == true` 時隱藏 `book_action_menu` 按鈕」這句話所描述的行為，不是額外的排版妥協。
6. **`_LayoutOverrideDialog`／`_BookDetailsDialog` 為 `library_screen.dart` 內的 private widget，無法比照 `EBSheetShell`／`BookActionSheet`「獨立測試」**——spec.md「Testing Decisions」對 `EBSheetShell`／`BookActionSheet` 明文要求「獨立 widget test，不透過 `LibraryScreen` 間接測」，但對 `_LayoutOverrideDialog` 只說「widget test 驗證...」、沒有講「獨立」二字；查證後確認這兩個對話框的 class 定義本身帶底線前綴、且規劃在 `library_screen.dart` 檔案內（見 spec.md 模組段落的檔案歸屬），Dart 的 library-level 隱私語意下 `library_screen_test.dart`（不同檔案＝不同 library）無法直接具現化這兩個 private class——本計劃 Task 3／Task 5 對這兩個對話框的測試皆透過完整 `LibraryScreen` 互動路徑（點擊 `book_action_menu_${id}` → 點擊對應選項 → 對話框出現）驅動，這與 spec.md 的字面差異是語言表述落差，不是規劃疏漏。

---

## Task 1：`EBSheetShell`（底部抽屜外殼基礎元件）

**Files:**
- Create: `app/lib/screens/widgets/eb_sheet_shell.dart`
- Test: `app/test/screens/widgets/eb_sheet_shell_test.dart`

**Interfaces:**
- Produces：
  - `class EBSheetShell extends StatelessWidget`，建構參數 `title`（`String`）／`child`（`Widget`）／`isEinkMode`（`bool`，預設 `false`）。
  - `static Future<T?> EBSheetShell.show<T>(BuildContext context, {required String title, required WidgetBuilder builder, bool isEinkMode = false})`。
  - Key 契約：`eb_sheet_shell_drag_handle`／`eb_sheet_shell_close_button`。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/screens/widgets/eb_sheet_shell_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/widgets/eb_sheet_shell.dart';

/// 捕捉 Navigator 實際推入的 Route，供斷言 `ModalBottomSheetRoute` 的
/// `transitionDuration` 是否真的依 `isEinkMode` 走到 `AnimationStyle.
/// noAnimation`——`showModalBottomSheet()` 沒有回傳值可以直接檢查，這是
/// Flutter 官方支援的既有觀察手法（`NavigatorObserver.didPush`）。
class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushedRoute = route;
  }
}

Future<void> _pumpAndOpen(
  WidgetTester tester, {
  bool isEinkMode = false,
  NavigatorObserver? observer,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: observer == null ? [] : [observer],
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => EBSheetShell.show<void>(
            context,
            title: '標題',
            isEinkMode: isEinkMode,
            builder: (context) => const Text('內容'),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
}

void main() {
  testWidgets('拖曳把手存在', (tester) async {
    await _pumpAndOpen(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('eb_sheet_shell_drag_handle')), findsOneWidget);
  });

  testWidgets('右上角關閉按鈕能關閉 Sheet', (tester) async {
    await _pumpAndOpen(tester);
    await tester.pumpAndSettle();
    expect(find.text('內容'), findsOneWidget);

    await tester.tap(find.byKey(const Key('eb_sheet_shell_close_button')));
    await tester.pumpAndSettle();

    expect(find.text('內容'), findsNothing);
  });

  testWidgets('isEinkMode: true 時彈出動畫時長為 Duration.zero', (tester) async {
    final observer = _RecordingNavigatorObserver();
    await _pumpAndOpen(tester, isEinkMode: true, observer: observer);
    await tester.pump();

    final route = observer.lastPushedRoute;
    expect(route, isA<ModalBottomSheetRoute>());
    expect((route as ModalBottomSheetRoute).transitionDuration, Duration.zero);

    await tester.pumpAndSettle();
  });

  testWidgets('isEinkMode: false（預設）時彈出動畫時長非 Duration.zero', (tester) async {
    final observer = _RecordingNavigatorObserver();
    await _pumpAndOpen(tester, observer: observer);
    await tester.pump();

    final route = observer.lastPushedRoute;
    expect(route, isA<ModalBottomSheetRoute>());
    expect(
      (route as ModalBottomSheetRoute).transitionDuration,
      isNot(Duration.zero),
    );

    await tester.pumpAndSettle();
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/widgets/eb_sheet_shell_test.dart`
Expected: FAIL（`eb_sheet_shell.dart` 不存在）

- [ ] **Step 3: 實作**

建立 `app/lib/screens/widgets/eb_sheet_shell.dart`：

```dart
import 'package:flutter/material.dart';

/// 底部抽屜外殼基礎元件（`DESIGN.md` §10）：拖曳把手＋標題＋右上角關閉
/// 按鈕＋高度限制，本 Epic 首次落地、只給 `BookActionSheet` 使用（既有
/// `NotesBottomSheet`／閱讀器內既有 Bottom Sheet 不在本次改用範圍，見
/// plans/plan-issue-4.md Global Constraints）。
class EBSheetShell extends StatelessWidget {
  final String title;
  final Widget child;
  final bool isEinkMode;

  const EBSheetShell({
    super.key,
    required this.title,
    required this.child,
    this.isEinkMode = false,
  });

  /// `isEinkMode: true` 時用 `AnimationStyle.noAnimation`（`duration`／
  /// `reverseDuration` 皆為 `Duration.zero`）達成「瞬間具現化顯示」
  /// （`DESIGN.md` §10.2）；`showModalBottomSheet` 的 `sheetAnimationStyle`
  /// 參數為 Flutter 3.41+ 原生支援（已查證 `bottom_sheet.dart` SDK 原始
  /// 碼），不需要自建 `AnimationController`（自建需要 `TickerProvider`，
  /// 靜態方法無法取得，且呼叫端須負責 dispose，有記憶體洩漏風險）。
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required WidgetBuilder builder,
    bool isEinkMode = false,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: isEinkMode ? AnimationStyle.noAnimation : null,
      builder: (context) => EBSheetShell(
        title: title,
        isEinkMode: isEinkMode,
        child: Builder(builder: builder),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return SafeArea(
      child: ConstrainedBox(
        // `DESIGN.md#L235`：「最大高度」限制為螢幕高度的 50% 至 85%，指的
        // 是抽屜高度的上限箝制，不是任何抽屜都要強制撐滿至少 50% 螢幕高
        // （【review-plan-issue-4.md I-2】內容少時若寫死 minHeight: 0.5
        // 會在平板等大螢幕上產生巨大無意義留白）；超出上限時內部改採
        // ListView 滾動（由呼叫端的 child 自行決定，本元件不強制）。
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              key: const Key('eb_sheet_shell_drag_handle'),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                // `EBRadius` 尚未落地（見 Global Constraints），直接寫
                // 字面值。
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const Key('eb_sheet_shell_close_button'),
                    icon: const Icon(Icons.close),
                    tooltip: '關閉',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/widgets/eb_sheet_shell_test.dart`
Expected: PASS（全部案例）

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/widgets/eb_sheet_shell.dart app/test/screens/widgets/eb_sheet_shell_test.dart
git commit -m "feat(epic-36): 新增底部抽屜外殼基礎元件 EBSheetShell"
```

---

## Task 2：`BookActionSheet`（單書動作選單內容）

**Files:**
- Create: `app/lib/screens/book_action_sheet.dart`
- Test: `app/test/screens/book_action_sheet_test.dart`

**Interfaces:**
- Consumes: 無（不依賴 Task 1，測試以 `showModalBottomSheet` 直接驅動，不需要真的透過 `EBSheetShell`）。
- Produces：`class BookActionSheet extends StatelessWidget`，建構參數 `book`（`Book`）／`showRemoveCache`（`bool`）／`showLayoutOverride`（`bool`，見「計劃範圍澄清」第 1 點）／`onShowDetails`／`onMove`／`onLayoutOverride`（皆 `VoidCallback`）／`onRemoveCache`（`VoidCallback?`）／`onDelete`（`VoidCallback`）。Key 契約：`book_action_details`／`book_action_move`／`book_action_layout_override`／`book_action_remove_cache`／`book_action_delete`。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/screens/book_action_sheet_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/book_action_sheet.dart';

Book _book() {
  return Book(
    id: '1',
    title: '書名',
    format: BookFileFormat.epub,
    filePath: 'content://example/1.epub',
    source: BookSource.local,
    createTime: DateTime(2026, 1, 1),
    lastReadTime: DateTime(2026, 1, 1),
  );
}

Future<void> _openSheet(
  WidgetTester tester, {
  bool showRemoveCache = true,
  bool showLayoutOverride = true,
  VoidCallback? onShowDetails,
  VoidCallback? onMove,
  VoidCallback? onLayoutOverride,
  VoidCallback? onRemoveCache,
  VoidCallback? onDelete,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (context) => BookActionSheet(
              book: _book(),
              showRemoveCache: showRemoveCache,
              showLayoutOverride: showLayoutOverride,
              onShowDetails: onShowDetails ?? () {},
              onMove: onMove ?? () {},
              onLayoutOverride: onLayoutOverride ?? () {},
              onRemoveCache: onRemoveCache,
              onDelete: onDelete ?? () {},
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('showRemoveCache: false 時「移除快取」選項不存在', (tester) async {
    await _openSheet(tester, showRemoveCache: false);
    expect(find.byKey(const Key('book_action_remove_cache')), findsNothing);
  });

  testWidgets('showLayoutOverride: false 時「版面覆寫」選項不存在', (tester) async {
    await _openSheet(tester, showLayoutOverride: false);
    expect(find.byKey(const Key('book_action_layout_override')), findsNothing);
  });

  testWidgets('showRemoveCache／showLayoutOverride 皆為 true 時五個選項全部存在', (
    tester,
  ) async {
    await _openSheet(tester);
    expect(find.byKey(const Key('book_action_details')), findsOneWidget);
    expect(find.byKey(const Key('book_action_move')), findsOneWidget);
    expect(find.byKey(const Key('book_action_layout_override')), findsOneWidget);
    expect(find.byKey(const Key('book_action_remove_cache')), findsOneWidget);
    expect(find.byKey(const Key('book_action_delete')), findsOneWidget);
  });

  testWidgets('點擊「詳細資料」關閉 Sheet 並呼叫 onShowDetails', (tester) async {
    var called = 0;
    await _openSheet(tester, onShowDetails: () => called++);
    await tester.tap(find.byKey(const Key('book_action_details')));
    await tester.pumpAndSettle();
    expect(called, 1);
    expect(find.byKey(const Key('book_action_details')), findsNothing);
  });

  testWidgets('點擊「移動」關閉 Sheet 並呼叫 onMove', (tester) async {
    var called = 0;
    await _openSheet(tester, onMove: () => called++);
    await tester.tap(find.byKey(const Key('book_action_move')));
    await tester.pumpAndSettle();
    expect(called, 1);
  });

  testWidgets('點擊「版面覆寫」關閉 Sheet 並呼叫 onLayoutOverride', (tester) async {
    var called = 0;
    await _openSheet(tester, onLayoutOverride: () => called++);
    await tester.tap(find.byKey(const Key('book_action_layout_override')));
    await tester.pumpAndSettle();
    expect(called, 1);
  });

  testWidgets('點擊「移除快取」關閉 Sheet 並呼叫 onRemoveCache', (tester) async {
    var called = 0;
    await _openSheet(tester, onRemoveCache: () => called++);
    await tester.tap(find.byKey(const Key('book_action_remove_cache')));
    await tester.pumpAndSettle();
    expect(called, 1);
  });

  testWidgets('點擊「刪除」關閉 Sheet 並呼叫 onDelete', (tester) async {
    var called = 0;
    await _openSheet(tester, onDelete: () => called++);
    await tester.tap(find.byKey(const Key('book_action_delete')));
    await tester.pumpAndSettle();
    expect(called, 1);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/book_action_sheet_test.dart`
Expected: FAIL（`book_action_sheet.dart` 不存在）

- [ ] **Step 3: 實作**

建立 `app/lib/screens/book_action_sheet.dart`：

```dart
import 'package:flutter/material.dart';

import '../library/models/book.dart';

/// 單書「⋮」動作選單內容（`DESIGN.md` §11.3／`spec.md` 功能④）：純呈現，
/// 不知道各選項實際邏輯，五個 callback 由呼叫端（`library_screen.dart`）
/// 提供。每個選項點擊後先關閉外層 Sheet 再呼叫對應 callback（比照既有
/// Dialog／Sheet 選項慣例，避免 callback 內再彈出的新 Dialog 跟尚未關閉的
/// Sheet 疊在一起）。
class BookActionSheet extends StatelessWidget {
  final Book book;

  /// `book.source == BookSource.calibreOpds && book.isDownloaded` 時為
  /// true；`false` 時「移除快取」選項整項不渲染（本機匯入書籍沒有遠端
  /// 來源可重新下載，不該讓使用者以為「這本書其實可以移除快取只是現在
  /// 按不了」）。
  final bool showRemoveCache;

  /// `widget.readerFeatureRepositories.bookReaderPrefsRepository != null`
  /// 時為 true；`false` 時「版面覆寫」選項整項不渲染，比照 [showRemoveCache]
  /// 的不渲染慣例（`plans/plan-issue-4.md`「計劃範圍澄清」第 1 點：
  /// spec.md 原始建構子片段遺漏這個欄位，此為補充）。
  final bool showLayoutOverride;

  final VoidCallback onShowDetails;
  final VoidCallback onMove;
  final VoidCallback onLayoutOverride;
  final VoidCallback? onRemoveCache; // showRemoveCache == false 時不會被觸發
  final VoidCallback onDelete;

  const BookActionSheet({
    super.key,
    required this.book,
    required this.showRemoveCache,
    required this.showLayoutOverride,
    required this.onShowDetails,
    required this.onMove,
    required this.onLayoutOverride,
    required this.onRemoveCache,
    required this.onDelete,
  });

  void _handle(BuildContext context, VoidCallback? callback) {
    Navigator.of(context).pop();
    callback?.call();
  }

  @override
  Widget build(BuildContext context) {
    // 【review-plan-issue-4.md C-1】外層包 SingleChildScrollView：橫向
    // （Landscape）或無障礙大字級下，`EBSheetShell` 的 `Flexible` 給予的
    // 高度可能小於 5 個 ListTile 的總高度（56dp × 5 = 280dp），裸 Column
    // 會拋出 RenderFlex overflow 例外（`DESIGN.md#L235` §10.1 明文要求
    // 「高於此限制時內部採用 ListView 滾動」，由本元件的 child 自行實作）。
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('book_action_details'),
            leading: const Icon(Icons.info_outline),
            title: const Text('詳細資料'),
            onTap: () => _handle(context, onShowDetails),
          ),
          ListTile(
            key: const Key('book_action_move'),
            leading: const Icon(Icons.drive_file_move),
            title: const Text('移動'),
            onTap: () => _handle(context, onMove),
          ),
          if (showLayoutOverride)
            ListTile(
              key: const Key('book_action_layout_override'),
              leading: const Icon(Icons.view_column_outlined),
              title: const Text('版面覆寫'),
              onTap: () => _handle(context, onLayoutOverride),
            ),
          if (showRemoveCache)
            ListTile(
              key: const Key('book_action_remove_cache'),
              leading: const Icon(Icons.cloud_off_outlined),
              title: const Text('移除快取'),
              onTap: () => _handle(context, onRemoveCache),
            ),
          ListTile(
            key: const Key('book_action_delete'),
            leading: const Icon(Icons.delete),
            title: const Text('刪除'),
            onTap: () => _handle(context, onDelete),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/book_action_sheet_test.dart`
Expected: PASS（全部案例）

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/book_action_sheet.dart app/test/screens/book_action_sheet_test.dart
git commit -m "feat(epic-36): 新增 BookActionSheet 單書動作選單內容"
```

---

## Task 3：`library_screen.dart` 串接「⋮」圖示＋詳細資料對話框

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `EBSheetShell.show()`；Task 2 的 `BookActionSheet`。
- Produces：`_BookGridTile`／`_BookListTile` 新增 `final VoidCallback onMenuTap;` 建構參數；`_LibraryScreenState` 新增 `_openBookActionSheet(Book)`／`_showBookDetails(Book)`；新增 private widget `_BookDetailsDialog`。新增 Key：`book_action_menu_${book.id}`（本 Task 掛載點，Task 2 已定義 Sheet 內部五個選項 Key）、`book_details_dialog`。`_testBook()` 擴充 `source`／`isDownloaded` 兩個可選參數（見「計劃範圍澄清」第 4 點）。

- [ ] **Step 1: 寫失敗測試**

**1a. 擴充 `_testBook()`**（`app/test/screens/library_screen_test.dart:3882` 附近）：

```dart
Book _testBook({
  required String id,
  required String title,
  String? author,
  String groupName = BookGroup.uncategorized,
  String? filePath,
  String? coverPath,
  bool? isFixedLayout,
  BookFileFormat format = BookFileFormat.epub,
  DateTime? lastReadTime,
  BookSource source = BookSource.local,
  bool isDownloaded = true,
}) {
```

`Book(...)` 建構呼叫內 `source: BookSource.local,` 改為 `source: source,`，並新增一行 `isDownloaded: isDownloaded,`（緊接在 `groupName: groupName,` 之後即可，順序不影響具名參數呼叫）。

**1b. 新增測試**（`main()` 內任一位置皆可）：

```dart
  testWidgets('點擊 book_action_menu 後 BookActionSheet／EBSheetShell 出現在畫面上', (
    tester,
  ) async {
    final book = _testBook(id: '1', title: '書A');
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

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();

    expect(find.byType(EBSheetShell), findsOneWidget);
    expect(find.byType(BookActionSheet), findsOneWidget);
  });

  testWidgets('多選模式進行中時 book_action_menu 不顯示（與長按多選互斥）', (tester) async {
    final book = _testBook(id: '1', title: '書A');
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

    await tester.longPress(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_action_menu_1')), findsNothing);
  });

  testWidgets('詳細資料：book.isDownloaded == false 時顯示「尚未下載」，不查詢檔案', (
    tester,
  ) async {
    final book = _testBook(id: '1', title: '書A', isDownloaded: false);
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

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_action_details')));
    await tester.pumpAndSettle();

    expect(find.text('尚未下載'), findsOneWidget);
  });

  testWidgets('詳細資料：content:// URI 或讀取失敗時顯示「未知大小」，不崩潰', (tester) async {
    final book = _testBook(id: '1', title: '書A', isDownloaded: true);
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

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_action_details')));
    await tester.pumpAndSettle();

    expect(find.text('未知大小'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('詳細資料：已下載且為本機真實檔案時顯示格式化後的檔案大小', (tester) async {
    final tempFile = File(
      '${Directory.systemTemp.path}/book_details_test_'
      '${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    await tempFile.writeAsBytes(List.filled(2048, 0));
    addTearDown(() async {
      if (await tempFile.exists()) await tempFile.delete();
    });

    final book = _testBook(
      id: '1',
      title: '書A',
      filePath: tempFile.path,
      isDownloaded: true,
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

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_action_details')));
    await tester.pumpAndSettle();

    expect(find.textContaining('2.0 KB'), findsOneWidget);
  });

  testWidgets('詳細資料：lastReadTime 為 epoch 0 時顯示「尚未閱讀」，而非誤導性的 1970 年日期', (
    tester,
  ) async {
    final book = _testBook(
      id: '1',
      title: '書A',
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(0),
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

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_action_details')));
    await tester.pumpAndSettle();

    expect(find.text('尚未閱讀'), findsOneWidget);
  });

  testWidgets(
    '清單檢視模式下 book_action_menu 圖示存在，點擊後 BookActionSheet 出現'
    '（review-plan-issue-4.md I-3：Step 3c 修改 _BookListTile 的 trailing '
    '結構為 Row，先前測試只覆蓋了格狀模式，補上清單模式的整合測試）',
    (tester) async {
      final book = _testBook(id: '1', title: '書A');
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

      // 切換為清單檢視（既有既有慣例：見本檔案「library_sort_view_button」
      // /「library_sort_view_toggle_option」的既有測試）。
      await tester.tap(find.byKey(const Key('library_sort_view_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library_sort_view_toggle_option')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('library_list_view')), findsOneWidget);

      expect(find.byKey(const Key('book_action_menu_1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('book_action_menu_1')));
      await tester.pumpAndSettle();

      expect(find.byType(EBSheetShell), findsOneWidget);
      expect(find.byType(BookActionSheet), findsOneWidget);
    },
  );
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/library_screen_test.dart --name "book_action_menu|詳細資料"`
Expected: FAIL（`book_action_menu_1` 等 Key 不存在，`EBSheetShell`／`BookActionSheet` 尚未匯入使用）

- [ ] **Step 3: 實作**

編輯 `app/lib/screens/library_screen.dart`：

**3a. import 新增**：

```dart
import 'book_action_sheet.dart';
import 'widgets/eb_sheet_shell.dart';
```

**3b. `_BookGridTile` 新增 `onMenuTap` 並疊加「⋮」圖示**（與既有 `book_selection_indicator_${book.id}` 互斥渲染於同一右上角位置，見「計劃範圍澄清」第 5 點）：

```dart
class _BookGridTile extends StatelessWidget {
  final Book book;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMenuTap;

  const _BookGridTile({
    required this.book,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMenuTap,
  });
```

`build()` 內的 `Stack` children，把既有 `if (selectionMode) Align(...)` 改為 `if/else`：

```dart
                if (selectionMode)
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: tokens.badgeScrim,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          key: Key('book_selection_indicator_${book.id}'),
                          color: selected ? colorScheme.primary : Colors.white,
                        ),
                      ),
                    ),
                  )
                else
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Container(
                        decoration: BoxDecoration(
                          color: tokens.badgeScrim,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          key: Key('book_action_menu_${book.id}'),
                          icon: const Icon(
                            Icons.more_vert,
                            color: Colors.white,
                          ),
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                          tooltip: '更多',
                          onPressed: onMenuTap,
                        ),
                      ),
                    ),
                  ),
```

**3c. `_BookListTile` 新增 `onMenuTap`，`trailing` 改為 `Row`（既有 icon+進度 Column 之後，`!selectionMode` 時附加「⋮」）**：

```dart
class _BookListTile extends StatelessWidget {
  final Book book;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMenuTap;

  const _BookListTile({
    required this.book,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMenuTap,
  });
```

```dart
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_sourceIcon(book.source), size: 16),
              Text(_progressText(book), style: const TextStyle(fontSize: 10)),
            ],
          ),
          if (!selectionMode)
            IconButton(
              key: Key('book_action_menu_${book.id}'),
              icon: const Icon(Icons.more_vert),
              tooltip: '更多',
              onPressed: onMenuTap,
            ),
        ],
      ),
```

**3d. `_buildBookList()` 的 `itemBuilder` 兩處建構呼叫皆補上 `onMenuTap`**：

```dart
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
```

**3e. 新增 `_openBookActionSheet()`／`_showBookDetails()`**（放在 `_openManageGroupsDialog()` 之後即可）：

```dart
  /// `onMove`／`onRemoveCache`／`onDelete` 於 Task 4 實作；`onLayoutOverride`
  /// 於 Task 5 實作（`showLayoutOverride` 暫時固定 false，Task 5 才依
  /// `bookReaderPrefsRepository` 是否提供切換）。
  Future<void> _openBookActionSheet(Book book) {
    return EBSheetShell.show<void>(
      context,
      title: book.title,
      isEinkMode: widget.themeDependencies.isEinkMode,
      builder: (context) => BookActionSheet(
        book: book,
        showRemoveCache:
            book.source == BookSource.calibreOpds && book.isDownloaded,
        showLayoutOverride: false,
        onShowDetails: () => _showBookDetails(book),
        onMove: () {},
        onLayoutOverride: () {},
        onRemoveCache: null,
        onDelete: () {},
      ),
    );
  }

  void _showBookDetails(Book book) {
    showDialog<void>(
      context: context,
      builder: (context) => _BookDetailsDialog(book: book),
    );
  }
```

**3f. 新增 `_BookDetailsDialog`（檔案結尾，`_ContinueReadingRow` 之後）**：

```dart
/// 單書「詳細資料」對話框（`spec.md` 功能④）：檔案大小查詢為非同步、
/// 具防護——`!book.isDownloaded` 直接顯示「尚未下載」不查詢檔案；
/// `content://` URI 或讀取失敗（`FileSystemException`）一律顯示
/// 「未知大小」，不得讓例外未捕捉往外拋（`review-spec.md` I-4）。
class _BookDetailsDialog extends StatefulWidget {
  final Book book;
  const _BookDetailsDialog({required this.book});

  @override
  State<_BookDetailsDialog> createState() => _BookDetailsDialogState();
}

class _BookDetailsDialogState extends State<_BookDetailsDialog> {
  late final Future<String> _fileSizeFuture;

  @override
  void initState() {
    super.initState();
    _fileSizeFuture = _resolveFileSizeText(widget.book);
  }

  static Future<String> _resolveFileSizeText(Book book) async {
    if (!book.isDownloaded) return '尚未下載';
    try {
      final length = await File(book.filePath).length();
      return _formatFileSize(length);
    } catch (_) {
      return '未知大小';
    }
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _formatLastReadTime(DateTime time) {
    if (time.millisecondsSinceEpoch <= 0) return '尚未閱讀';
    final y = time.year;
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    return AlertDialog(
      key: const Key('book_details_dialog'),
      title: Text(book.title),
      content: FutureBuilder<String>(
        future: _fileSizeFuture,
        builder: (context, snapshot) {
          // 【review-plan-issue-4.md M-2】`_resolveFileSizeText()` 內部已用
          // try-catch 保證 Future 本身不會拋錯，但 FutureBuilder 遭遇未預期
          // 的 error 狀態時，`snapshot.data` 為 null 會讓畫面永遠卡在
          // 「讀取中...」，改為明確判斷 hasError。
          final fileSizeText = snapshot.hasError
              ? '未知大小'
              : (snapshot.data ?? '讀取中...');
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('作者：${book.author ?? '未知'}'),
              Text('格式：${book.format.name}'),
              Text('檔案大小：$fileSizeText'),
              Text('進度：${_progressText(book)}'),
              Text('最後閱讀：${_formatLastReadTime(book.lastReadTime)}'),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          key: const Key('book_details_dialog_close_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('關閉'),
        ),
      ],
    );
  }
}
```

編輯 `app/test/screens/library_screen_test.dart`：新增 import：

```dart
import 'package:elinkbook/screens/book_action_sheet.dart';
import 'package:elinkbook/screens/widgets/eb_sheet_shell.dart';
```

- [ ] **Step 4: 執行新測試確認通過**

Run: `flutter test test/screens/library_screen_test.dart --name "book_action_menu|詳細資料"`
Expected: 上述新增測試 100% PASS。

- [ ] **Step 5: 執行整個 `library_screen_test.dart`，確認無回歸**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: PASS（全部案例，0 失敗——本 Task 收尾 Commit 前必須全綠，`review-plan-issue-2.md` I-1 教訓）。若既有測試因為 `_BookGridTile`／`_BookListTile` 新增必填 `onMenuTap` 參數而編譯失敗，逐一補上（僅 `_buildBookList()` 內的兩處建構呼叫，見 Step 3d，不應該有其他呼叫點）。

- [ ] **Step 6: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-36): 書架書本卡片新增「⋮」動作選單與詳細資料對話框"
```

---

## Task 4：`onMove`／`onRemoveCache`／`onDelete` 單書版本

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `_openBookActionSheet()`；既有 `LibraryBatchActions.moveToGroup`／`removeLocalCache`／`deleteBooks`；既有 `LibraryMoveToGroupDialog`／`_confirmDeleteBooks()`。
- Produces：`_LibraryScreenState` 新增 `_moveBookToGroup(Book)`／`_removeBookCache(Book)`／`_deleteBook(Book)`。新增 Key：`book_action_remove_cache_confirm_button`。

- [ ] **Step 1: 寫失敗測試**

```dart
  testWidgets('點擊「移動」選擇分類後，該書 groupName 更新，其他書籍不受影響', (tester) async {
    final book = _testBook(id: '1', title: '書A');
    final groupSeed = _testBook(id: '2', title: '書B', groupName: '奇幻');
    final repository = FakeLibraryRepository(initialBooks: [book, groupSeed]);

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_action_move')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_move_to_group_option_奇幻')));
    await tester.pumpAndSettle();

    final updated = await repository.listBooks();
    expect(updated.firstWhere((b) => b.id == '1').groupName, '奇幻');
    expect(
      updated.firstWhere((b) => b.id == '2').groupName,
      '奇幻',
      reason: '既有書籍不應受影響',
    );
  });

  testWidgets('點擊「移除快取」確認後，該書 isDownloaded 變 false，本機檔案被刪除', (tester) async {
    final tempFile = File(
      '${Directory.systemTemp.path}/remove_cache_test_'
      '${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    await tempFile.writeAsBytes([1, 2, 3]);
    addTearDown(() async {
      if (await tempFile.exists()) await tempFile.delete();
    });

    final book = _testBook(
      id: '1',
      title: '書A',
      filePath: tempFile.path,
      source: BookSource.calibreOpds,
      isDownloaded: true,
    );
    final repository = FakeLibraryRepository(initialBooks: [book]);

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book_action_remove_cache')), findsOneWidget);
    await tester.tap(find.byKey(const Key('book_action_remove_cache')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('book_action_remove_cache_confirm_button')),
    );
    await tester.pumpAndSettle();

    final updated = await repository.listBooks();
    expect(updated.firstWhere((b) => b.id == '1').isDownloaded, isFalse);
    expect(await tempFile.exists(), isFalse, reason: '本機快取檔案應被刪除');
  });

  testWidgets(
    '點擊「刪除」確認後，該書從畫面上消失；若恰為 _mostRecentBook，繼續閱讀列同步消失'
    '（plan-issue-4.md「計劃範圍澄清」第 3 點：驗證 loadBooks() 既有機制已自動'
    '涵蓋重新計算，無需額外程式碼）',
    (tester) async {
      final book = _testBook(id: '1', title: '書A', lastReadTime: DateTime(2026, 6, 1));
      final repository = FakeLibraryRepository(initialBooks: [book]);

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: LibraryScreen(
            repository: repository,
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('library_continue_reading_row')), findsOneWidget);

      await tester.tap(find.byKey(const Key('book_action_menu_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book_action_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library_delete_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('book_item_1')), findsNothing);
      expect(
        find.byKey(const Key('library_continue_reading_row')),
        findsNothing,
        reason: '被刪除的書恰為 _mostRecentBook，繼續閱讀列不應殘留無效書籍參照',
      );
    },
  );
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/library_screen_test.dart --name "點擊「移動」|點擊「移除快取」|點擊「刪除」確認後"`
Expected: FAIL（`_openBookActionSheet()` 目前把 `onMove`／`onRemoveCache`／`onDelete` 接成空操作／`null`，選單點了沒有反應）

- [ ] **Step 3: 實作**

編輯 `app/lib/screens/library_screen.dart`：

**3a. 新增三個方法**（放在 `_openBookActionSheet()`／`_showBookDetails()` 之後）：

```dart
  Future<void> _moveBookToGroup(Book book) async {
    final destination = await showDialog<String>(
      context: context,
      builder: (context) =>
          LibraryMoveToGroupDialog(groups: _bookListController.groups),
    );
    if (destination == null) return;
    if (!mounted) return;
    final books = _bookListController.books;
    if (books == null) return;
    await _batchActions.moveToGroup({book.id}, books, destination);
    await _bookListController.loadBooks();
  }

  Future<bool?> _confirmRemoveBookCache(Book book) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移除本機快取'),
        content: Text(
          '將移除「${book.title}」的本機檔案，書籍紀錄與閱讀進度會保留，之後可重新'
          '下載。確定要移除嗎？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('book_action_remove_cache_confirm_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeBookCache(Book book) async {
    final confirmed = await _confirmRemoveBookCache(book);
    if (confirmed != true) return;
    if (!mounted) return;
    final books = _bookListController.books;
    if (books == null) return;
    await _batchActions.removeLocalCache({book.id}, books);
    await _bookListController.loadBooks();
  }

  /// 【計劃範圍澄清第 3 點】不需要額外手動重新計算 `_mostRecentBook`——
  /// `_bookListController.loadBooks()` 成功後一律 `notifyListeners()`，
  /// `initState()` 已註冊的 `_onBookListChanged()` 監聽器會自動重算，比照
  /// 既有 `_deleteSelectedBooks()` 等批次方法的既有寫法。
  Future<void> _deleteBook(Book book) async {
    final confirmed = await _confirmDeleteBooks(1);
    if (confirmed != true) return;
    if (!mounted) return;
    final books = _bookListController.books;
    if (books == null) return;
    await _batchActions.deleteBooks({book.id}, books);
    await _bookListController.loadBooks();
  }
```

**3b. `_openBookActionSheet()` 的 `onMove`／`onRemoveCache`／`onDelete` 改接真正方法**：

```dart
  Future<void> _openBookActionSheet(Book book) {
    final showRemoveCache =
        book.source == BookSource.calibreOpds && book.isDownloaded;
    return EBSheetShell.show<void>(
      context,
      title: book.title,
      isEinkMode: widget.themeDependencies.isEinkMode,
      builder: (context) => BookActionSheet(
        book: book,
        showRemoveCache: showRemoveCache,
        showLayoutOverride: false,
        onShowDetails: () => _showBookDetails(book),
        onMove: () => _moveBookToGroup(book),
        onLayoutOverride: () {},
        onRemoveCache: showRemoveCache ? () => _removeBookCache(book) : null,
        onDelete: () => _deleteBook(book),
      ),
    );
  }
```

- [ ] **Step 4: 執行新測試確認通過**

Run: `flutter test test/screens/library_screen_test.dart --name "點擊「移動」|點擊「移除快取」|點擊「刪除」確認後"`
Expected: 上述新增測試 100% PASS。

- [ ] **Step 5: 執行整個 `library_screen_test.dart`，確認無回歸**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: PASS（全部案例，0 失敗）。

- [ ] **Step 6: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-36): 單書動作選單串接移動/移除快取/刪除，重用既有批次操作邏輯"
```

---

## Task 5：`_LayoutOverrideDialog`（版面覆寫對話框）

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes: 既有 `BookReaderPrefsRepository`（`load`/`save`）；既有 `ReaderOptionTile<T>`（`app/lib/screens/widgets/reader_option_tile.dart`）；`WritingMode`／`PageTurnMode` 列舉。
- Produces：`_LibraryScreenState` 新增 `_showLayoutOverrideDialog(Book)`；新增 private widget `_LayoutOverrideDialog`／`_LayoutOverrideDialogState`。新增 Key：`layout_override_dialog`／`layout_override_writing_mode_default`／`_horizontal`／`_vertical`／`layout_override_page_turn_mode_default`／`_paginated`／`_scroll`／`layout_override_save_button`／`layout_override_cancel_button`。

- [ ] **Step 1: 寫失敗測試**

```dart
  testWidgets('bookReaderPrefsRepository 未提供時，「版面覆寫」選項不顯示', (tester) async {
    final book = _testBook(id: '1', title: '書A');
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

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_action_layout_override')), findsNothing);
  });

  testWidgets(
    '版面覆寫：儲存後只有 writingModeOverride/pageTurnModeOverride 改變，其他既有欄位'
    '原樣保留，選「使用預設」能真的清成 null（plan-issue-4.md「計劃範圍澄清」'
    '第 2 點核心回歸測試：不可誤用 copyWith()）',
    (tester) async {
      final book = _testBook(id: '1', title: '書A');
      final repository = FakeLibraryRepository(initialBooks: [book]);
      // 【review-plan-issue-4.md C-2】不可用 BookReaderPrefsRepository(
      // libraryRepository.database)：`libraryRepository` 是本檔案 setUp()
      // 另外開立的 SqliteLibraryRepository，其 SQLite books 表裡沒有 id
      // == '1' 這筆書籍（book 只放進了上面的記憶體 FakeLibraryRepository），
      // book_reader_prefs.book_id 是 REFERENCES books(id) 的外鍵，直接
      // save() 會立即拋出 FOREIGN KEY constraint failed。改用純記憶體的
      // FakeBookReaderPrefsRepository，徹底繞開這個約束、測試也更快更純粹。
      final bookReaderPrefsRepository = FakeBookReaderPrefsRepository();
      await bookReaderPrefsRepository.save(
        '1',
        const BookReaderPrefs(
          fontSize: 1.5,
          marginTop: 24,
          writingModeOverride: WritingMode.horizontal,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: LibraryScreen(
            repository: repository,
            importService: FakeBookImportService(),
            prefsManager: prefsManager,
            readerFeatureRepositories: LibraryReaderFeatureRepositories(
              bookReaderPrefsRepository: bookReaderPrefsRepository,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_action_menu_1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('book_action_layout_override')), findsOneWidget);
      await tester.tap(find.byKey(const Key('book_action_layout_override')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('layout_override_writing_mode_default')));
      await tester.tap(find.byKey(const Key('layout_override_page_turn_mode_scroll')));
      await tester.tap(find.byKey(const Key('layout_override_save_button')));
      await tester.pumpAndSettle();

      final saved = await bookReaderPrefsRepository.load('1');
      expect(saved.fontSize, 1.5, reason: '既有 fontSize 不應被清空');
      expect(saved.marginTop, 24, reason: '既有 marginTop 不應被清空');
      expect(
        saved.writingModeOverride,
        isNull,
        reason:
            '選「使用預設」須真的清成 null，若誤用 copyWith() 的 ?? 語意則仍會殘留'
            '原本的 horizontal',
      );
      expect(saved.pageTurnModeOverride, PageTurnMode.scroll);
    },
  );
```

**1a. `app/test/screens/library_screen_test.dart` 新增 import**（【review-plan-issue-4.md I-1】本檔案目前只 import 了 `book_reader_prefs_repository.dart`；`Step 1` 的測試程式碼直接引用 `BookReaderPrefs`／`WritingMode`／`PageTurnMode`，以及〔C-2 修訂後〕`FakeBookReaderPrefsRepository`，皆須補齊 import，否則編譯失敗 `Error: 'BookReaderPrefs' isn't a type.`）：

```dart
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import '../support/fake_book_reader_prefs_repository.dart';
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/library_screen_test.dart --name "版面覆寫"`
Expected: FAIL（`layout_override_dialog` 等 Key 不存在）

- [ ] **Step 3: 實作**

編輯 `app/lib/screens/library_screen.dart`：

**3a. import 新增**：

```dart
import '../reader/book_reader_prefs.dart';
import '../reader/book_reader_prefs_repository.dart';
import '../reader/page_turn_mode.dart';
import '../reader/writing_mode.dart';
import 'widgets/reader_option_tile.dart';
```

**3b. `_openBookActionSheet()` 改接真正的版面覆寫邏輯**：

```dart
  Future<void> _openBookActionSheet(Book book) {
    final showRemoveCache =
        book.source == BookSource.calibreOpds && book.isDownloaded;
    final bookReaderPrefsRepository =
        widget.readerFeatureRepositories.bookReaderPrefsRepository;
    return EBSheetShell.show<void>(
      context,
      title: book.title,
      isEinkMode: widget.themeDependencies.isEinkMode,
      builder: (context) => BookActionSheet(
        book: book,
        showRemoveCache: showRemoveCache,
        showLayoutOverride: bookReaderPrefsRepository != null,
        onShowDetails: () => _showBookDetails(book),
        onMove: () => _moveBookToGroup(book),
        onLayoutOverride: bookReaderPrefsRepository == null
            ? () {}
            : () => _showLayoutOverrideDialog(book, bookReaderPrefsRepository),
        onRemoveCache: showRemoveCache ? () => _removeBookCache(book) : null,
        onDelete: () => _deleteBook(book),
      ),
    );
  }

  void _showLayoutOverrideDialog(
    Book book,
    BookReaderPrefsRepository repository,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) =>
          _LayoutOverrideDialog(bookId: book.id, repository: repository),
    );
  }
```

**3c. 新增 `_LayoutOverrideDialog`（檔案結尾，`_BookDetailsDialog` 之後）**：

```dart
/// 單書版面覆寫對話框（`spec.md` 功能④「版面覆寫對話框」）。
///
/// **關鍵正確性要求**：`BookReaderPrefsRepository.save()` 是整列覆寫
/// （`INSERT OR REPLACE`），不是只更新有變動的欄位。`_save()` 必須先
/// `load()` 取得該書完整既有 `BookReaderPrefs`，只改
/// `writingModeOverride`/`pageTurnModeOverride` 兩個欄位、其餘欄位原樣
/// 帶回——**不可用 `copyWith()`**：`BookReaderPrefs.copyWith()` 是
/// `newValue ?? this.value` 語意（見 `book_reader_prefs.dart` 文件註解），
/// 選「使用預設」時本地狀態明確為 `null`，若用
/// `copyWith(writingModeOverride: null)` 會被 `??` 吃掉、不會真的清空既有
/// 覆寫值。比照 `reader_settings_sheet.dart` 既有 `_currentDraft` 的整列
/// 重建寫法（`plans/plan-issue-4.md`「計劃範圍澄清」第 2 點）。
class _LayoutOverrideDialog extends StatefulWidget {
  final String bookId;
  final BookReaderPrefsRepository repository;
  const _LayoutOverrideDialog({required this.bookId, required this.repository});

  @override
  State<_LayoutOverrideDialog> createState() => _LayoutOverrideDialogState();
}

class _LayoutOverrideDialogState extends State<_LayoutOverrideDialog> {
  BookReaderPrefs? _existingPrefs;
  WritingMode? _writingMode;
  PageTurnMode? _pageTurnMode;
  bool _isSaving = false; // 【review-plan-issue-4.md M-1】連點防護

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await widget.repository.load(widget.bookId);
    if (!mounted) return;
    setState(() {
      _existingPrefs = prefs;
      _writingMode = prefs.writingModeOverride;
      _pageTurnMode = prefs.pageTurnModeOverride;
    });
  }

  Future<void> _save() async {
    // 【review-plan-issue-4.md M-1】連續快速敲擊「儲存」時，第一次 await
    // 尚未返回前若觸發第二次 _save()，會導致連彈兩層路由（可能誤將呼叫端
    // 的畫面一併 pop 掉）。
    if (_isSaving) return;
    _isSaving = true;
    final existing = _existingPrefs;
    if (existing == null) return;
    final updated = BookReaderPrefs(
      fontFamily: existing.fontFamily,
      fontSize: existing.fontSize,
      fontWeight: existing.fontWeight,
      lineHeight: existing.lineHeight,
      paragraphSpacing: existing.paragraphSpacing,
      letterSpacing: existing.letterSpacing,
      pageMargins: existing.pageMargins,
      marginTop: existing.marginTop,
      marginBottom: existing.marginBottom,
      marginLeft: existing.marginLeft,
      marginRight: existing.marginRight,
      textAlign: existing.textAlign,
      publisherStyles: existing.publisherStyles,
      writingModeOverride: _writingMode,
      pageTurnModeOverride: _pageTurnMode,
      screenOrientationOverride: existing.screenOrientationOverride,
      pdfFitMode: existing.pdfFitMode,
      pdfContrast: existing.pdfContrast,
      pdfBrightness: existing.pdfBrightness,
      pdfBoldStrength: existing.pdfBoldStrength,
      pdfCropMode: existing.pdfCropMode,
      pdfCropRect: existing.pdfCropRect,
      dualPageMode: existing.dualPageMode,
      dualPageCoverAlone: existing.dualPageCoverAlone,
      dualPageDirection: existing.dualPageDirection,
      pdfPageTurnAnimation: existing.pdfPageTurnAnimation,
      showHeader: existing.showHeader,
      showFooter: existing.showFooter,
      columnMode: existing.columnMode,
      columnSize: existing.columnSize,
      fullscreen: existing.fullscreen,
    );
    await widget.repository.save(widget.bookId, updated);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_existingPrefs == null) {
      // 【review-plan-issue-4.md M-3】loading 狀態仍保留 title／取消按鈕，
      // 避免儲存層載入慢時使用者無法從畫面上退出。
      return AlertDialog(
        key: const Key('layout_override_dialog'),
        title: const Text('版面覆寫'),
        content: const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
        actions: [
          TextButton(
            key: const Key('layout_override_cancel_button'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      );
    }
    return AlertDialog(
      key: const Key('layout_override_dialog'),
      title: const Text('版面覆寫'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('排版方向'),
            Wrap(
              spacing: 4,
              children: [
                ReaderOptionTile<WritingMode?>(
                  itemKey: const Key('layout_override_writing_mode_default'),
                  value: null,
                  groupValue: _writingMode,
                  icon: Icons.auto_awesome,
                  tooltip: '使用書籍排版',
                  onSelected: (v) => setState(() => _writingMode = v),
                ),
                ReaderOptionTile<WritingMode?>(
                  itemKey: const Key('layout_override_writing_mode_horizontal'),
                  value: WritingMode.horizontal,
                  groupValue: _writingMode,
                  icon: Icons.text_rotation_none,
                  tooltip: '橫排',
                  onSelected: (v) => setState(() => _writingMode = v),
                ),
                ReaderOptionTile<WritingMode?>(
                  itemKey: const Key('layout_override_writing_mode_vertical'),
                  value: WritingMode.vertical,
                  groupValue: _writingMode,
                  icon: Icons.text_rotate_vertical,
                  tooltip: '直排',
                  onSelected: (v) => setState(() => _writingMode = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('翻頁模式'),
            Wrap(
              spacing: 4,
              children: [
                ReaderOptionTile<PageTurnMode?>(
                  itemKey: const Key('layout_override_page_turn_mode_default'),
                  value: null,
                  groupValue: _pageTurnMode,
                  icon: Icons.tune,
                  tooltip: '使用全域預設',
                  onSelected: (v) => setState(() => _pageTurnMode = v),
                ),
                ReaderOptionTile<PageTurnMode?>(
                  itemKey: const Key('layout_override_page_turn_mode_paginated'),
                  value: PageTurnMode.paginated,
                  groupValue: _pageTurnMode,
                  icon: Icons.menu_book,
                  tooltip: '分頁',
                  onSelected: (v) => setState(() => _pageTurnMode = v),
                ),
                ReaderOptionTile<PageTurnMode?>(
                  itemKey: const Key('layout_override_page_turn_mode_scroll'),
                  value: PageTurnMode.scroll,
                  groupValue: _pageTurnMode,
                  icon: Icons.swap_vert,
                  tooltip: '捲動',
                  onSelected: (v) => setState(() => _pageTurnMode = v),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('layout_override_cancel_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('layout_override_save_button'),
          onPressed: _save,
          child: const Text('儲存'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: 執行新測試確認通過**

Run: `flutter test test/screens/library_screen_test.dart --name "版面覆寫"`
Expected: 上述新增測試 100% PASS。

- [ ] **Step 5: 執行整個 `library_screen_test.dart`，確認無回歸**

Run: `flutter test test/screens/library_screen_test.dart`
Expected: PASS（全部案例，0 失敗）。

- [ ] **Step 6: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-36): 新增單書版面覆寫對話框，整列重建保留既有個人化設定"
```

---

## Task 6：全套驗證與收尾

**Files:** 無新增/修改，純驗證。

- [ ] **Step 1: 執行全套 `flutter test`（不帶檔案路徑）**

Run: `flutter test`
Expected: 全數通過（比照 `CLAUDE.md`「測試執行範圍」，這是整份計劃收尾的唯一一次全套執行）。若有失敗，比對是否為本計劃改動觸及的檔案；非本計劃觸及範圍的既有不穩定測試（例如已追蹤的 `epic-37-test-suite-flakiness`）記錄下來，不在本 Issue 修復範圍內。

- [ ] **Step 2: 執行 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 逐條核對 `issues.md` Issue 4 驗收標準**

- [ ] 點擊「⋮」彈出單書動作選單，與長按多選互不干擾
- [ ] 五個選項功能正確且與既有批次操作共用底層邏輯
- [ ] 版面覆寫不清空既有其他個人化設定
- [ ] 檔案大小查詢不因 `content://` URI 或未下載書籍而崩潰
- [ ] `flutter analyze` 乾淨、`flutter test` 全數通過

- [ ] **Step 4: 更新 `docs/epics.md` 備註欄位**

將 Epic 36 該列備註改為「Issue 1-4 已完成，待認領 Issue 5」（執行時以 `issues.md` 實際狀態為準調整措辭）。

- [ ] **Step 5: 依 `superpowers:requesting-code-review` 發起本 Issue 的程式碼審查**

審查者先產出報告至 `docs/epics/epic-36-adaptive-shelf-navigation/reviews/review-issue-4.md`，不得直接修改程式碼（比照專案 SDD 工作流程第 6 步）。審查請求內容須包含「計劃範圍澄清」第 2 點的 `_LayoutOverrideDialog` 整列重建（而非 `copyWith()`）正確性要求，供審查者重點覆核這處資料遺失等級的細節；以及第 1 點 `BookActionSheet.showLayoutOverride` 是本計劃對 spec.md 遺漏欄位的補充，非隨意增加的參數。

---

## Self-Review 紀錄（撰寫本計劃時的覆核結果）

- **Spec 覆蓋**：`spec.md` §功能④／`issues.md` Issue 4 的 Solution 逐條對照——`EBSheetShell`（Task 1）、`BookActionSheet` 五個選項（Task 2）、「⋮」圖示與長按多選互斥（Task 3）、詳細資料含檔案大小防護（Task 3）、移動/移除快取/刪除重用既有批次邏輯與自動刷新（Task 4）、版面覆寫整列重建保留既有設定（Task 5）皆有對應 Task，無遺漏。
- **`issues.md`「單元測試要求」五項逐條對照**：`EBSheetShell` 獨立 widget test（Task 1：拖曳把手／關閉按鈕／E-Ink 零動畫）、`BookActionSheet` 獨立 widget test（Task 2：`showRemoveCache`/`showLayoutOverride` 為 false 時不渲染、五個 callback 各被呼叫一次）、`_BookDetailsDialog` 四種情境（Task 3：未下載／`content://`／真實檔案／`lastReadTime` epoch 0）、`onRemoveCache`/`onDelete` 完成後重新載入與 `_mostRecentBook` 同步（Task 4）、`_LayoutOverrideDialog` 核心回歸測試（Task 5：既有欄位保留＋「使用預設」真的清成 null）、`library_screen.dart` 整合測試（Task 3：點擊 `book_action_menu` 後 Sheet 出現）皆已納入。
- **型別一致性**：`BookActionSheet` 的 `showRemoveCache`/`showLayoutOverride`/`onShowDetails`/`onMove`/`onLayoutOverride`/`onRemoveCache`/`onDelete` 在 Task 2 定義，Task 3-5 建構時原樣使用、依序補齊 `onMove`/`onRemoveCache`/`onDelete`/`onLayoutOverride` 四個一開始接空操作的欄位；`_BookGridTile`/`_BookListTile` 的 `onMenuTap` 在 Task 3 定義並在同一 Task 的 `_buildBookList()` 呼叫端補齊，未跨 Task 留下編譯失敗的中繼狀態。
- **範圍落差已於「計劃範圍澄清」段落明文記錄並解決**：`BookActionSheet` 缺 `showLayoutOverride` 欄位（第 1 點）、`_LayoutOverrideDialog` 不可用 `copyWith()` 的關鍵正確性修正（第 2 點，這是本計劃規劃階段發現、若逐字套用 spec.md 範例程式碼會導致「使用預設」選項靜默失效的功能性缺陷）、「重新計算 `_mostRecentBook`」已由既有機制自動涵蓋（第 3 點）、`_testBook()` 加法擴充（第 4 點）、「⋮」與選取指示器共用位置的互斥設計確認（第 5 點）、`_LayoutOverrideDialog`/`_BookDetailsDialog` 私有性導致無法獨立測試的語言表述落差（第 6 點）。
