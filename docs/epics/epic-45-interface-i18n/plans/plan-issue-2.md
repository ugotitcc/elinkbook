# Epic 45 Issue 2：系統保留分類名稱在地化契約 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓系統保留分類「未分類」在書架分類管理相關的 3 個畫面（`library_group_management_dialog.dart`／`library_move_to_group_dialog.dart`／`cloud_browser_screen.dart`）依目前介面語言正確顯示，使用者自訂分類名稱維持原樣不受影響；新增/重新命名分類時，前端攔截三語言任一保留字，不讓使用者建立出會在切換語言後與系統保留分類撞名的「幽靈重複群組」。

**Architecture:** `localizeGroupName()`/`BookGroupL10n.displayName()`（`spec.md` §5.1）新增於 `app/lib/library/models/book_group.dart`，把系統保留分類的表現層轉譯收斂成一個純函式；`isReservedGroupName()`（`spec.md` §5.2 的撞名防線邏輯）**同樣移入 `book_group.dart` 並公開（非底線開頭）**——這是本計畫對 `spec.md` 的一處刻意偏離：`spec.md` 原將其設計為 `library_group_management_dialog.dart` 內的私有頂層函式 `_isReservedGroupName()`，但 Dart 的 privacy 是以檔案為界線，私有頂層函式無法被獨立測試檔（`library_group_management_dialog_test.dart`）之外的任何檔案呼叫，會讓 `issues.md` 明訂的「`_isReservedGroupName()`（或等效抽出的頂層純函式）：純邏輯單元測試」這條要求在字面上不可能達成（只能靠 widget test 間接覆蓋）；`issues.md` 本身也用「或等效抽出的頂層純函式」這個措辭預留了彈性。改為公開頂層函式後，與 `localizeGroupName()` 同樣是「BookGroup 分類名稱政策」的核心邏輯，收斂在同一個檔案、可被獨立 `test()` 直接呼叫，`library_group_management_dialog.dart` 只是它的其中一個呼叫端。本 Issue 依審查後使用者決議（`cloud_browser_screen.dart` 範圍爭議，見下方 Global Constraints）採用「Issue 2 一次抽完」版本，因此 `cloud_browser_screen.dart` 除分類下拉選單外的其餘既有硬編碼字串（行動數據對話框、重新連結提示、下載完成提示、截斷提示等）也在本 Issue 一併抽取，`issues.md` Issue 6 的檔案清單需同步移除 `cloud_browser_screen.dart` 這一項（Task 5 處理）。

**Tech Stack:** Flutter 3.41.9 / Dart 3.11.5；`AppLocalizations`（Issue 0 已產生，Issue 1 已建立 `SettingsScaffold` 首批字串抽取先例）；`pumpLocalizedWidget()`（`app/test/support/pump_localized_widget.dart`）；ICU `plural` 語法（`cloudBrowserDownloadQueued` 計數字串，`spec.md` §1.3 全域規則：計數相關字串一律用 ICU plural，不手動拼接單複數）；`lookupAppLocalizations(Locale)`（`book_group_test.dart` 純 Dart 單元測試取得三語言實例，比照 `markdown_export_test.dart` 既有慣例）。

**Spec:** `docs/epics/epic-45-interface-i18n/spec.md` §5（`localizeGroupName()`／`BookGroupL10n`／撞名防線）；工單定義見 `docs/epics/epic-45-interface-i18n/issues.md`「Issue 2」。

## Global Constraints

- **範圍收斂為 3 個檔案**（`issues.md` review-issues C-1 修正）：`library_group_management_dialog.dart`／`library_move_to_group_dialog.dart`／`cloud_browser_screen.dart`。**嚴禁觸碰 `reader_screen.dart`／`reader_screen_test.dart` 任何一行**——原清單中 `reader_screen.dart:1759`（`_buildSearchableBook()` 內 `groupName: BookGroup.uncategorized`）查證後是建構一個純暫態、不落地的搜尋用 `Book` 佔位物件，`BookGroup.uncategorized` 必須維持底層 Sentinel 字面值，改為 `localizeGroupName()`/`displayName()` 會破壞資料語意。`library_batch_actions.dart`（「移動到分類」按鈕本身）與 `library_screen.dart` 的一般 UI 文案留給 Issue 3，不在本 Issue。
- **`cloud_browser_screen.dart` 範圍爭議已由使用者裁定「Issue 2 一次抽完」**：`issues.md` Issue 2 原文（「兩檔案其餘既有硬編碼字串一併抽取，避免留給 Issue 3/6 重複編輯」）與 Issue 6 檔案清單註記（「分類下拉選單已在 Issue 2 處理，本 Issue 處理其餘字串」）互相矛盾，2026-09-21 經使用者確認採前者——本 Issue 完整處理 `cloud_browser_screen.dart` 全部既有硬編碼字串，Task 5 需同步修訂 `issues.md` Issue 6 的檔案清單移除 `cloud_browser_screen.dart`。
- **系統保留分類轉譯不得影響底層資料庫欄位值**——`BookGroup.uncategorized`（`'未分類'` 字面值）永遠是儲存/比對用的 Sentinel，`localizeGroupName()`/`displayName()` 純粹是顯示層轉換，`DropdownMenuItem.value`／`Key(...)` 等資料/測試選擇器一律維持使用原始字面值，只有 `child: Text(...)` 顯示內容轉譯。
- **撞名防線同時防禦三語言全部保留字，不限當前介面語言**（`spec.md` §5.2 C-2 修正）：`isReservedGroupName()` 是純函式、不需要 `AppLocalizations` 參數，靜態集合 `{'未分類', '未分类', 'uncategorized'}`（英文不分大小寫、前後空白先 trim）。
- **計數相關字串一律用 ICU `plural` 語法**（`spec.md` §1.3 全域規則）：`cloud_browser_screen.dart` 的下載完成提示（`已加入下載佇列（N 個檔案）`）需正確處理英文單複數。
- **既有測試檔（`library_group_management_dialog_test.dart`／`library_move_to_group_dialog_test.dart`／`cloud_browser_screen_test.dart`）觸及的裸 `MaterialApp(...)` 一律改用 `pumpLocalizedWidget()`**（`issues.md` Issue 2 單元測試要求）。
- **`library_group_management_dialog.dart` 內非本檔案字面值的例外訊息（`e.message`，來自 `LibraryRepositoryException`）不在本 Issue 範圍**——那是 Issue 7（執行期例外訊息在地化）的範圍，本 Issue 只處理本檔案自己定義的字面值（例如 catch-all 的「操作失敗，請稍後再試」），既有測試 `find.text('分類「B」已存在')` 斷言的字串來自 `FakeLibraryRepository`/`SqliteLibraryRepository` 自己的例外訊息，維持原樣不變。
- **提交前 `flutter analyze` 必須乾淨（"No issues found!"）**；每個 Task 只需跑該 Task 觸及的測試檔，完整 `flutter test` 只在本計畫最後一個 Task 跑一次。
- 所有新增檔案/程式碼的中文說明/註解一律使用正體中文（`CLAUDE.md` 全域規則）。

所有指令皆在 `app/` 目錄下執行（`cd /c/Users/fycdc/AI/elinkBook/app`）。

---

### Task 1：`book_group.dart` — `localizeGroupName()`／`BookGroupL10n`／`isReservedGroupName()`

**Files:**
- Modify: `app/lib/library/models/book_group.dart`
- Test: `app/test/library/models/book_group_test.dart`（新檔案）

**Interfaces:**
- Produces: `String localizeGroupName(String name, AppLocalizations l10n)`；`extension BookGroupL10n on BookGroup { String displayName(AppLocalizations l10n) }`；`bool isReservedGroupName(String name)`（公開頂層函式，純邏輯、不需要 `AppLocalizations`），供 Task 2/3/4 使用。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/library/models/book_group_test.dart`：

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/library/models/book_group.dart';

void main() {
  group('isReservedGroupName', () {
    test('三語言保留字（含大小寫變體與前後空白）皆判定為保留名稱', () {
      for (final name in [
        '未分類',
        '未分类',
        'uncategorized',
        'UNCATEGORIZED',
        'Uncategorized',
        '  uncategorized  ',
        '  未分類  ',
        '  未分类  ',
      ]) {
        expect(isReservedGroupName(name), isTrue, reason: '「$name」應判定為保留名稱');
      }
    });

    test('一般分類名稱不誤判為保留名稱', () {
      for (final name in ['小說', 'Novels', '未分類上', 'uncategorized2', '']) {
        expect(isReservedGroupName(name), isFalse, reason: '「$name」不應判定為保留名稱');
      }
    });
  });

  group('localizeGroupName / BookGroupL10n.displayName', () {
    test('系統保留分類依三語言正確轉譯', () {
      final zhTW = lookupAppLocalizations(const Locale('zh', 'TW'));
      final zhCN = lookupAppLocalizations(const Locale('zh', 'CN'));
      final en = lookupAppLocalizations(const Locale('en'));

      expect(localizeGroupName(BookGroup.uncategorized, zhTW), '未分類');
      expect(localizeGroupName(BookGroup.uncategorized, zhCN), '未分类');
      expect(localizeGroupName(BookGroup.uncategorized, en), 'Uncategorized');
    });

    test('一般自訂分類名稱原樣不變，不受介面語言影響', () {
      final zhTW = lookupAppLocalizations(const Locale('zh', 'TW'));
      final en = lookupAppLocalizations(const Locale('en'));

      expect(localizeGroupName('小說', zhTW), '小說');
      expect(localizeGroupName('小說', en), '小說');
    });

    test('BookGroupL10n.displayName() 轉發至 localizeGroupName()', () {
      final zhCN = lookupAppLocalizations(const Locale('zh', 'CN'));
      expect(
        const BookGroup(BookGroup.uncategorized).displayName(zhCN),
        '未分类',
      );
      expect(const BookGroup('奇幻').displayName(zhCN), '奇幻');
    });
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/library/models/book_group_test.dart`
Expected: 編譯錯誤（`localizeGroupName`/`isReservedGroupName`/`BookGroupL10n` 尚未定義）。

- [ ] **Step 3: 實作**

修改 `app/lib/library/models/book_group.dart`：

```dart
import '../../l10n/app_localizations.dart';

/// 書籍分類群組（FR-33）。[uncategorized]（「未分類」）為系統保留群組，
/// 不可重新命名或刪除——書籍未歸類、或原群組被刪除時皆歸入此群組。
class BookGroup {
  static const String uncategorized = '未分類';

  final String name;

  const BookGroup(this.name);

  Map<String, Object?> toMap() => {'name': name};

  factory BookGroup.fromMap(Map<String, Object?> map) =>
      BookGroup(map['name'] as String);
}

/// 表現層顯示名稱轉換：系統保留分類（[BookGroup.uncategorized]）依目前介面
/// 語言轉譯；使用者自訂分類原樣顯示，不經過此轉譯（epic-45-interface-i18n
/// Issue 2）。獨立頂層函式而非只做成 [BookGroup] 擴充方法——多處畫面（例如
/// `cloud_browser_screen.dart` 的 `_selectedGroupName`）是以裸 `String`
/// 持有群組名稱，並非都經手 [BookGroup] 物件，需要能直接對字串呼叫。
String localizeGroupName(String name, AppLocalizations l10n) =>
    name == BookGroup.uncategorized ? l10n.groupUncategorized : name;

extension BookGroupL10n on BookGroup {
  /// 轉發至 [localizeGroupName]，供已持有 [BookGroup] 物件的呼叫端使用。
  String displayName(AppLocalizations l10n) => localizeGroupName(name, l10n);
}

/// elinkBook 支援語言是已知的封閉集合（正體中文／簡體中文／英文三種），
/// 保留名稱集合本身也是固定已知的——同時防禦所有支援語言的保留名稱（不限
/// 當前介面語言），英文不分大小寫。純函式、刻意公開（非底線開頭）且不需要
/// [AppLocalizations] 參數，供 `library_group_management_dialog.dart`
/// 等呼叫端在新增/重新命名分類前檢查，也供本身的純邏輯單元測試直接呼叫
/// （`plan-issue-2.md` 對 `spec.md` §5.2 的刻意偏離：原設計為
/// `library_group_management_dialog.dart` 內的私有函式 `_isReservedGroupName()`，
/// 因 Dart privacy 以檔案為界線、私有頂層函式無法被獨立測試檔呼叫，改為
/// 本檔案的公開頂層函式，`issues.md` 本身也以「或等效抽出的頂層純函式」
/// 預留了這個彈性）。
bool isReservedGroupName(String name) {
  const reserved = {'未分類', '未分类', 'uncategorized'};
  return reserved.contains(name.trim().toLowerCase());
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/library/models/book_group_test.dart`
Expected: PASS（6 個 test）。

- [ ] **Step 5: `flutter analyze`**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/library/models/book_group.dart test/library/models/book_group_test.dart
git commit -m "feat(epic-45): book_group.dart 新增 localizeGroupName/isReservedGroupName"
```

---

### Task 2：`library_group_management_dialog.dart` — 撞名防線＋字串抽取

**Files:**
- Modify: `app/lib/screens/library_group_management_dialog.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Modify: `app/test/support/fake_library_repository.dart`（新增 `upsertGroupCalls`/`renameGroupCalls` 呼叫紀錄，供本 Task 測試驗證「前端攔截後未呼叫 repository」）
- Modify: `app/test/screens/library_group_management_dialog_test.dart`

**Interfaces:**
- Consumes: `isReservedGroupName()`／`BookGroupL10n.displayName()`（Task 1）。
- Produces: ARB key `cancel`／`confirm`／`errorOperationFailed`（三者皆為通用 key，供 Task 3/4 沿用）／`libraryGroupManageTitle`／`libraryGroupAddFieldLabel`／`libraryGroupAddButton`／`libraryGroupRenameTitle`／`libraryGroupDeleteTitle`／`libraryGroupDeleteConfirmMessage`／`libraryGroupDeleteButton`／`libraryGroupReservedNameError`。

- [ ] **Step 1: 新增 ARB key（4 份檔案）**

`app/lib/l10n/app_zh_TW.arb`（在既有 `settingsLanguageEn`/`@settingsLanguageEn` 區塊之後新增，記得補上前一個區塊結尾的逗號）：

```json
  "cancel": "取消",
  "@cancel": {
    "description": "通用「取消」按鈕文字"
  },
  "confirm": "確定",
  "@confirm": {
    "description": "通用「確定」按鈕文字"
  },
  "errorOperationFailed": "操作失敗，請稍後再試",
  "@errorOperationFailed": {
    "description": "通用操作失敗的 catch-all 錯誤訊息（非例外物件原始文字，見 spec.md §6 執行期例外訊息在地化慣例）"
  },
  "libraryGroupManageTitle": "管理分類",
  "@libraryGroupManageTitle": {
    "description": "分類管理對話框標題"
  },
  "libraryGroupAddFieldLabel": "新增分類名稱",
  "@libraryGroupAddFieldLabel": {
    "description": "分類管理對話框新增分類輸入框的 labelText"
  },
  "libraryGroupAddButton": "新增",
  "@libraryGroupAddButton": {
    "description": "分類管理對話框「新增」按鈕文字"
  },
  "libraryGroupRenameTitle": "重新命名分類",
  "@libraryGroupRenameTitle": {
    "description": "重新命名分類子對話框標題"
  },
  "libraryGroupDeleteTitle": "刪除分類",
  "@libraryGroupDeleteTitle": {
    "description": "刪除分類確認子對話框標題"
  },
  "libraryGroupDeleteConfirmMessage": "確定要刪除分類「{name}」嗎？該分類下的書籍將改列為「{uncategorized}」。",
  "@libraryGroupDeleteConfirmMessage": {
    "description": "刪除分類確認訊息，{name} 為被刪除的分類名稱（使用者自訂，不翻譯），{uncategorized} 為 groupUncategorized 的已轉譯結果",
    "placeholders": {
      "name": {
        "type": "String"
      },
      "uncategorized": {
        "type": "String"
      }
    }
  },
  "libraryGroupDeleteButton": "刪除",
  "@libraryGroupDeleteButton": {
    "description": "刪除分類確認子對話框的「刪除」按鈕文字"
  },
  "libraryGroupReservedNameError": "「{name}」是系統保留的分類名稱，請使用其他名稱",
  "@libraryGroupReservedNameError": {
    "description": "新增/重新命名分類時，輸入名稱命中三語言任一保留字時顯示的錯誤訊息，{name} 為使用者實際輸入的名稱",
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  }
```

`app/lib/l10n/app_zh_CN.arb`（同樣位置新增，無 `@key` 描述區塊）：

```json
  "cancel": "取消",
  "confirm": "确定",
  "errorOperationFailed": "操作失败，请稍后再试",
  "libraryGroupManageTitle": "管理分类",
  "libraryGroupAddFieldLabel": "新增分类名称",
  "libraryGroupAddButton": "新增",
  "libraryGroupRenameTitle": "重新命名分类",
  "libraryGroupDeleteTitle": "删除分类",
  "libraryGroupDeleteConfirmMessage": "确定要删除分类「{name}」吗？该分类下的书籍将改列为「{uncategorized}」。",
  "libraryGroupDeleteButton": "删除",
  "libraryGroupReservedNameError": "「{name}」是系统保留的分类名称，请使用其他名称"
```

`app/lib/l10n/app_en.arb`：

```json
  "cancel": "Cancel",
  "confirm": "OK",
  "errorOperationFailed": "Operation failed. Please try again later.",
  "libraryGroupManageTitle": "Manage Categories",
  "libraryGroupAddFieldLabel": "New category name",
  "libraryGroupAddButton": "Add",
  "libraryGroupRenameTitle": "Rename Category",
  "libraryGroupDeleteTitle": "Delete Category",
  "libraryGroupDeleteConfirmMessage": "Delete category \"{name}\"? Books in this category will be moved to \"{uncategorized}\".",
  "libraryGroupDeleteButton": "Delete",
  "libraryGroupReservedNameError": "\"{name}\" is a reserved category name. Please use a different name."
```

`app/lib/l10n/app_zh.arb`（`gen-l10n` 基礎 fallback，沿用 zh_TW 的值）：

```json
  "cancel": "取消",
  "confirm": "確定",
  "errorOperationFailed": "操作失敗，請稍後再試",
  "libraryGroupManageTitle": "管理分類",
  "libraryGroupAddFieldLabel": "新增分類名稱",
  "libraryGroupAddButton": "新增",
  "libraryGroupRenameTitle": "重新命名分類",
  "libraryGroupDeleteTitle": "刪除分類",
  "libraryGroupDeleteConfirmMessage": "確定要刪除分類「{name}」嗎？該分類下的書籍將改列為「{uncategorized}」。",
  "libraryGroupDeleteButton": "刪除",
  "libraryGroupReservedNameError": "「{name}」是系統保留的分類名稱，請使用其他名稱"
```

- [ ] **Step 2: 重新產生 `AppLocalizations`**

Run: `flutter gen-l10n`
Expected: 無錯誤；新增 getter `cancel`/`confirm`/`errorOperationFailed`/`libraryGroupManageTitle`/`libraryGroupAddFieldLabel`/`libraryGroupAddButton`/`libraryGroupRenameTitle`/`libraryGroupDeleteTitle`/`libraryGroupDeleteButton`/`libraryGroupReservedNameError`（後者帶 `String name` 參數）；`libraryGroupDeleteConfirmMessage(String name, String uncategorized)`（帶 2 參數方法）。

- [ ] **Step 3: `FakeLibraryRepository` 新增呼叫紀錄欄位**

修改 `app/test/support/fake_library_repository.dart`，在 `final List<String> deleteBookCalls = [];` 之後新增：

```dart

  /// 記錄每次 [upsertGroup] 呼叫的 name，供測試驗證「前端攔截保留名稱後
  /// 未呼叫 repository」（epic-45-interface-i18n Issue 2）。
  final List<String> upsertGroupCalls = [];

  /// 記錄每次 [renameGroup] 呼叫的 (oldName, newName)，理由同上。
  final List<(String oldName, String newName)> renameGroupCalls = [];
```

修改 `upsertGroup()`／`renameGroup()`，在方法本體開頭補上紀錄：

```dart
  @override
  Future<void> upsertGroup(String name) async {
    upsertGroupCalls.add(name);
    _groups.add(name);
  }

  @override
  Future<void> renameGroup(String oldName, String newName) async {
    renameGroupCalls.add((oldName, newName));
    if (oldName == BookGroup.uncategorized) {
      throw LibraryRepositoryException(
          '系統保留群組「${BookGroup.uncategorized}」不可重新命名');
    }
    if (_groups.contains(newName)) {
      throw LibraryRepositoryException('分類「$newName」已存在');
    }
    _groups
      ..remove(oldName)
      ..add(newName);
    for (var i = 0; i < _books.length; i++) {
      if (_books[i].groupName == oldName) {
        _books[i] = _withGroupName(_books[i], newName);
      }
    }
  }
```

- [ ] **Step 4: 寫失敗測試（既有 3 個測試遷移 + 新增 4 個測試）**

修改 `app/test/screens/library_group_management_dialog_test.dart`，開頭新增 import：

```dart
import '../support/pump_localized_widget.dart';
```

**4a. 既有 3 個測試遷移**：把 3 處 `await tester.pumpWidget(MaterialApp(home: Builder(...)))`（第 2 個測試額外帶 `theme: theme`）改為 `await pumpLocalizedWidget(tester, Builder(...))`（第 2 個測試改為 `await pumpLocalizedWidget(tester, Builder(...), theme: AppTheme.light)`）。三個測試各自的 `Builder(...)` 內容原封不動搬移，其餘斷言不變（第 2 個測試 `find.text('分類「B」已存在')` 斷言的是 `FakeLibraryRepository` 自己的例外訊息，不受本 Issue 影響，維持不變）。

**4b. 新增 4 個測試**（加在檔案最後一個既有 `testWidgets`「「新增」按鈕須位於「關閉」按鈕右側」之後）：

```dart

  testWidgets(
      '新增分類時輸入三語言任一保留字，前端攔截、不呼叫 repository.upsertGroup()、顯示錯誤訊息',
      (tester) async {
    final repository = FakeLibraryRepository();
    final groups = await repository.listGroups();

    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => LibraryGroupManagementDialog(
                  repository: repository,
                  initialGroups: groups,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    for (final reserved in ['未分類', '未分类', 'Uncategorized']) {
      await tester.enterText(
        find.byKey(const Key('library_group_add_field')),
        reserved,
      );
      await tester.tap(find.byKey(const Key('library_group_add_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('「$reserved」是系統保留的分類名稱，請使用其他名稱'),
        findsOneWidget,
        reason: '「$reserved」應被前端攔截並顯示錯誤',
      );
    }

    expect(repository.upsertGroupCalls, isEmpty);
  });

  testWidgets(
      '重新命名分類時輸入保留字，前端攔截、不呼叫 repository.renameGroup()、顯示錯誤訊息',
      (tester) async {
    final repository = FakeLibraryRepository();
    await repository.upsertGroup('奇幻');
    final groups = await repository.listGroups();

    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => LibraryGroupManagementDialog(
                  repository: repository,
                  initialGroups: groups,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_rename_button_奇幻')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('library_group_rename_field')),
      '未分类',
    );
    await tester.tap(find.byKey(const Key('library_group_rename_confirm')));
    await tester.pumpAndSettle();

    expect(
      find.text('「未分类」是系統保留的分類名稱，請使用其他名稱'),
      findsOneWidget,
    );
    expect(repository.renameGroupCalls, isEmpty);
  });

  testWidgets('分類清單中「未分類」依目前介面語言正確轉譯，使用者自訂分類原樣顯示',
      (tester) async {
    final repository = FakeLibraryRepository();
    await repository.upsertGroup('Fantasy');
    final groups = await repository.listGroups();

    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => LibraryGroupManagementDialog(
                  repository: repository,
                  initialGroups: groups,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      locale: const Locale('zh', 'CN'),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('未分类'), findsOneWidget);
    expect(find.text('Fantasy'), findsOneWidget);
    expect(find.text('未分類'), findsNothing, reason: '不應顯示未轉譯的正體中文原字面值');
  });

  testWidgets('刪除分類確認訊息中的目的地分類名稱依目前介面語言正確轉譯', (tester) async {
    final repository = FakeLibraryRepository();
    await repository.upsertGroup('奇幻');
    final groups = await repository.listGroups();

    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => LibraryGroupManagementDialog(
                  repository: repository,
                  initialGroups: groups,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      locale: const Locale('en'),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_group_delete_button_奇幻')));
    await tester.pumpAndSettle();

    expect(
      find.text('Delete category "奇幻"? Books in this category will be '
          'moved to "Uncategorized".'),
      findsOneWidget,
    );
  });
```

- [ ] **Step 5: 執行測試確認失敗**

Run: `flutter test test/screens/library_group_management_dialog_test.dart`
Expected: 編譯錯誤（`isReservedGroupName` 已存在於 `book_group.dart`，但 `library_group_management_dialog.dart` 尚未呼叫它、`AppLocalizations` 尚未接上，既有測試因裸 `MaterialApp` 已改成 `pumpLocalizedWidget()` 呼叫但實作端尚未要求 `AppLocalizations` 故仍可能編譯通過但新測試斷言全部失敗——實際結果依編譯器判斷，兩者皆屬「未通過」的預期紅燈狀態）。

- [ ] **Step 6: 實作 `library_group_management_dialog.dart`**

完整改寫 `app/lib/screens/library_group_management_dialog.dart`：

```dart
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../library/library_repository.dart';
import '../library/models/book_group.dart';

/// 分類群組管理對話框（FR-33）：支援新增/重新命名/刪除群組。「未分類」
/// 為系統保留群組，UI 層面不提供重新命名/刪除按鈕（見
/// docs/epics/epic-1-library/issues.md Issue 7 驗收標準）。刪除前必須經過
/// 二次確認對話框。呼叫端（LibraryScreen）於對話框關閉後一律重新載入群組
/// 與書籍清單，不論使用者實際上是否做了任何變更。新增/重新命名時會先經
/// [isReservedGroupName] 前端攔截三語言任一保留字（epic-45-interface-i18n
/// Issue 2），避免使用者建立出切換語言後與系統保留分類撞名的分類。
class LibraryGroupManagementDialog extends StatefulWidget {
  final LibraryRepository repository;
  final List<BookGroup> initialGroups;

  const LibraryGroupManagementDialog({
    super.key,
    required this.repository,
    required this.initialGroups,
  });

  @override
  State<LibraryGroupManagementDialog> createState() =>
      _LibraryGroupManagementDialogState();
}

class _LibraryGroupManagementDialogState
    extends State<LibraryGroupManagementDialog> {
  late List<BookGroup> _groups;
  final _addController = TextEditingController();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _groups = List.of(widget.initialGroups);
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  Future<void> _reloadGroups() async {
    final groups = await widget.repository.listGroups();
    if (!mounted) return;
    setState(() => _groups = groups);
  }

  Future<void> _addGroup() async {
    final l10n = AppLocalizations.of(context)!;
    final name = _addController.text.trim();
    if (name.isEmpty) return;
    if (isReservedGroupName(name)) {
      setState(() => _errorMessage = l10n.libraryGroupReservedNameError(name));
      return;
    }
    try {
      await widget.repository.upsertGroup(name);
      if (!mounted) return;
      _addController.clear();
      setState(() => _errorMessage = null);
      await _reloadGroups();
    } on LibraryRepositoryException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = l10n.errorOperationFailed);
    }
  }

  Future<void> _renameGroup(String oldName) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final dialogL10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(dialogL10n.libraryGroupRenameTitle),
          content: TextField(
            key: const Key('library_group_rename_field'),
            controller: controller,
            onSubmitted: (val) => Navigator.of(dialogContext).pop(val.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(dialogL10n.cancel),
            ),
            TextButton(
              key: const Key('library_group_rename_confirm'),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(dialogL10n.confirm),
            ),
          ],
        );
      },
    );
    // 延遲 dispose 以避免在 dialog widget 樹仍在 teardown 時存取已釋放的
    // TextEditingController。使用 addPostFrameCallback() 確保整個 frame cycle
    // 完成後再進行清理。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    if (newName == null || newName.isEmpty || newName == oldName) return;
    if (isReservedGroupName(newName)) {
      if (!mounted) return;
      setState(
        () => _errorMessage = l10n.libraryGroupReservedNameError(newName),
      );
      return;
    }
    try {
      await widget.repository.renameGroup(oldName, newName);
      if (!mounted) return;
      setState(() => _errorMessage = null);
      await _reloadGroups();
    } on LibraryRepositoryException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = l10n.errorOperationFailed);
    }
  }

  Future<void> _confirmDeleteGroup(String name) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final dialogL10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(dialogL10n.libraryGroupDeleteTitle),
          content: Text(
            dialogL10n.libraryGroupDeleteConfirmMessage(
              name,
              dialogL10n.groupUncategorized,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogL10n.cancel),
            ),
            TextButton(
              key: const Key('library_group_delete_confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(dialogL10n.libraryGroupDeleteButton),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteGroup(name);
      if (!mounted) return;
      setState(() => _errorMessage = null);
      await _reloadGroups();
    } on LibraryRepositoryException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = l10n.errorOperationFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.libraryGroupManageTitle),
      content: SizedBox(
        width: double.maxFinite,
        // 【診斷修正，見 tmp/epic-18/分類異常.jpg】分類數量較多時，下方的
        // 「新增分類名稱」欄位取得焦點、系統鍵盤彈出後，AlertDialog 可用
        // 高度會被 MediaQuery.viewInsets.bottom 壓縮，但這個 Column 本身
        // 不會跟著收縮（分類清單固定用 maxHeight: 240 的 ConstrainedBox），
        // 導致底部溢位（真機回報 BOTTOM OVERFLOWED BY 21 PIXELS）。改用
        // SingleChildScrollView 包住整個內容，鍵盤把可用高度壓縮到不足時
        // 改為讓整個對話框內容可捲動，而不是讓 RenderFlex 溢位（比照既有
        // pdf_settings_sheet.dart 處理類似鍵盤/視窗高度不足情境的既有寫法）。
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  key: const Key('library_group_manage_list'),
                  shrinkWrap: true,
                  itemCount: _groups.length,
                  itemBuilder: (context, index) {
                    final group = _groups[index];
                    final isProtected = group.name == BookGroup.uncategorized;
                    return ListTile(
                      key: Key('library_group_manage_item_${group.name}'),
                      title: Text(group.displayName(l10n)),
                      trailing: isProtected
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  key: Key(
                                    'library_group_rename_button_${group.name}',
                                  ),
                                  icon: const Icon(Icons.edit, size: 20),
                                  onPressed: () => _renameGroup(group.name),
                                ),
                                IconButton(
                                  key: Key(
                                    'library_group_delete_button_${group.name}',
                                  ),
                                  icon: const Icon(Icons.delete, size: 20),
                                  onPressed: () =>
                                      _confirmDeleteGroup(group.name),
                                ),
                              ],
                            ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('library_group_add_field'),
                controller: _addController,
                decoration: InputDecoration(
                  labelText: l10n.libraryGroupAddFieldLabel,
                ),
                onSubmitted: (_) => _addGroup(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('library_group_close_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
        TextButton(
          key: const Key('library_group_add_button'),
          onPressed: _addGroup,
          child: Text(l10n.libraryGroupAddButton),
        ),
      ],
    );
  }
}
```

- [ ] **Step 7: 執行測試確認通過**

Run: `flutter test test/screens/library_group_management_dialog_test.dart`
Expected: PASS（既有 3 個測試遷移後通過＋新增 4 個測試，共 7 個，零回歸）。

- [ ] **Step 8: `flutter analyze`**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 9: Commit**

```bash
git add lib/l10n/ lib/screens/library_group_management_dialog.dart test/support/fake_library_repository.dart test/screens/library_group_management_dialog_test.dart
git commit -m "feat(epic-45): library_group_management_dialog.dart 撞名防線＋字串抽取"
```

---

### Task 3：`library_move_to_group_dialog.dart` — 字串抽取

**Files:**
- Modify: `app/lib/screens/library_move_to_group_dialog.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Modify: `app/test/screens/library_move_to_group_dialog_test.dart`

**Interfaces:**
- Consumes: `BookGroupL10n.displayName()`（Task 1）；`cancel`（Task 2 已建立的通用 ARB key）。
- Produces: ARB key `libraryMoveToGroupTitle`。

- [ ] **Step 1: 新增 ARB key（4 份檔案）**

`app/lib/l10n/app_zh_TW.arb`（在 Task 2 新增的 `libraryGroupReservedNameError`/`@libraryGroupReservedNameError` 區塊之後新增）：

```json
  "libraryMoveToGroupTitle": "移動到分類",
  "@libraryMoveToGroupTitle": {
    "description": "「移動到分類」目的地選擇對話框標題"
  }
```

`app/lib/l10n/app_zh_CN.arb`：

```json
  "libraryMoveToGroupTitle": "移动到分类"
```

`app/lib/l10n/app_en.arb`：

```json
  "libraryMoveToGroupTitle": "Move to Category"
```

`app/lib/l10n/app_zh.arb`：

```json
  "libraryMoveToGroupTitle": "移動到分類"
```

- [ ] **Step 2: 重新產生 `AppLocalizations`**

Run: `flutter gen-l10n`
Expected: 無錯誤；新增 getter `libraryMoveToGroupTitle`。

- [ ] **Step 3: 寫失敗測試（既有 2 個測試遷移 + 新增 1 個測試）**

修改 `app/test/screens/library_move_to_group_dialog_test.dart`，開頭新增 import：

```dart
import '../support/pump_localized_widget.dart';
```

**3a. 既有 2 個測試遷移**：把 2 處 `await tester.pumpWidget(MaterialApp(home: Builder(...)))` 改為 `await pumpLocalizedWidget(tester, Builder(...))`，`Builder(...)` 內容與其餘斷言原封不動搬移（預設 `zh_TW` locale 下 `find.text('移動到分類')`／`find.byKey('library_move_to_group_option_未分類')` 等既有斷言維持通過）。

**3b. 新增 1 個測試**（加在檔案最後一個既有 `testWidgets`「點擊取消後...」之後）：

```dart

  testWidgets(
      '「未分類」選項依目前介面語言正確轉譯，使用者自訂分類原樣顯示，標題亦正確轉譯，'
      '且點擊已轉譯選項回傳的仍是底層 Sentinel 原始字面值'
      '（/receiving-code-review M-2 修正：補齊 pop 回傳值斷言，鎖死「表現層轉譯不影響'
      '底層資料庫值」這條核心契約，不能只驗證畫面顯示文字）',
      (tester) async {
    String? result = 'unset';
    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showDialog<String>(
              context: context,
              builder: (_) => const LibraryMoveToGroupDialog(
                groups: [BookGroup('未分類'), BookGroup('奇幻')],
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
      locale: const Locale('en'),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Move to Category'), findsOneWidget);
    expect(find.text('Uncategorized'), findsOneWidget);
    expect(find.text('奇幻'), findsOneWidget);
    expect(find.text('未分類'), findsNothing, reason: '不應顯示未轉譯的正體中文原字面值');

    await tester.tap(find.text('Uncategorized'));
    await tester.pumpAndSettle();

    expect(
      result,
      BookGroup.uncategorized,
      reason: '英文介面下點擊已轉譯為 "Uncategorized" 的選項，pop 回傳的仍須是資料庫主鍵原始字面值'
          '「未分類」，不可是顯示用的英文字串',
    );
  });
```

- [ ] **Step 4: 執行測試確認失敗**

Run: `flutter test test/screens/library_move_to_group_dialog_test.dart`
Expected: 新增測試 FAIL（`Move to Category`/`Uncategorized` 尚未出現，畫面仍顯示正體中文原字面值）；既有 2 個測試因 `LibraryMoveToGroupDialog.build()` 尚未呼叫 `AppLocalizations.of(context)!` 目前仍可正常通過（尚未變成強制要求），故此步驟只有新測試處於紅燈，這是正常的中間狀態。

- [ ] **Step 5: 實作 `library_move_to_group_dialog.dart`**

完整改寫 `app/lib/screens/library_move_to_group_dialog.dart`：

```dart
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../library/models/book_group.dart';

/// 「移動到分類」目的地選擇對話框（Issue 10）：列出目前所有分類（含
/// 「未分類」），點擊即以該分類名稱關閉對話框。不提供新增/重新命名/刪除
/// ——群組本身的管理屬於 Issue 7 的 [LibraryGroupManagementDialog]，本對話
/// 框只負責「從既有分類中選一個」。系統保留分類名稱依目前介面語言轉譯顯示
/// （epic-45-interface-i18n Issue 2），使用者自訂分類原樣顯示。
class LibraryMoveToGroupDialog extends StatelessWidget {
  final List<BookGroup> groups;

  const LibraryMoveToGroupDialog({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SimpleDialog(
      title: Text(l10n.libraryMoveToGroupTitle),
      children: [
        for (final group in groups)
          SimpleDialogOption(
            key: Key('library_move_to_group_option_${group.name}'),
            onPressed: () => Navigator.of(context).pop(group.name),
            child: Text(group.displayName(l10n)),
          ),
        SimpleDialogOption(
          key: const Key('library_move_to_group_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
```

- [ ] **Step 6: 執行測試確認通過**

Run: `flutter test test/screens/library_move_to_group_dialog_test.dart`
Expected: PASS（既有 2 個測試＋新增 1 個，共 3 個，零回歸）。

- [ ] **Step 7: `flutter analyze`**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 8: Commit**

```bash
git add lib/l10n/ lib/screens/library_move_to_group_dialog.dart test/screens/library_move_to_group_dialog_test.dart
git commit -m "feat(epic-45): library_move_to_group_dialog.dart 字串抽取"
```

---

### Task 4：`cloud_browser_screen.dart` — 分類下拉選單在地化＋全部既有字串抽取

**Files:**
- Modify: `app/lib/screens/cloud_browser_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Modify: `app/test/screens/cloud_browser_screen_test.dart`

**Interfaces:**
- Consumes: `localizeGroupName()`（Task 1，直接呼叫、非經 `BookGroup` 物件——`_selectedGroupName`／下拉選單項目皆為裸 `String`）；`cancel`（Task 2 通用 ARB key）。
- Produces: ARB key `errorNetworkConnection`／`cloudBrowserDuplicateConfirmMessage`／`cloudBrowserDownloadQueued`（ICU plural）／`cloudBrowserMobileDataDialogTitle`／`cloudBrowserMobileDataDialogMessage`／`cloudBrowserMobileDataDialogConfirm`／`cloudBrowserDownloadSelectedTooltip`／`cloudBrowserReauthMessage`／`cloudBrowserGenericProviderLabel`／`cloudBrowserImportCategoryLabel`／`cloudBrowserTruncatedNotice`。**`errorNetworkConnection` 刻意採用 `spec.md` §6 執行期例外訊息在地化慣例已預告的 key 名稱**，供 Issue 7 未來若在其他檔案也需要相同語意時直接沿用，不必另創同義詞。

- [ ] **Step 1: 新增 ARB key（4 份檔案）**

`app/lib/l10n/app_zh_TW.arb`（在 Task 3 新增的 `libraryMoveToGroupTitle`/`@libraryMoveToGroupTitle` 區塊之後新增）：

```json
  "errorNetworkConnection": "載入失敗，請檢查網路連線",
  "@errorNetworkConnection": {
    "description": "一般網路/連線失敗的錯誤訊息（spec.md §6 執行期例外訊息在地化慣例）"
  },
  "cloudBrowserDuplicateConfirmMessage": "「{name}」之前匯入過了，仍要建立新的一份嗎？",
  "@cloudBrowserDuplicateConfirmMessage": {
    "description": "選檔前置重複偵測（Layer 1）命中既有書籍時的確認訊息，{name} 為雲端檔案名稱",
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "cloudBrowserDownloadQueued": "已加入下載佇列（{count, plural, =1{1 個檔案} other{{count} 個檔案}}），可至「來源」畫面查看進度",
  "@cloudBrowserDownloadQueued": {
    "description": "下載加入佇列後的 SnackBar 提示，{count} 為選取的檔案數，需正確處理英文單複數",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "cloudBrowserMobileDataDialogTitle": "行動數據下載提醒",
  "@cloudBrowserMobileDataDialogTitle": {
    "description": "行動數據流量警示對話框標題"
  },
  "cloudBrowserMobileDataDialogMessage": "目前使用行動數據連線，勾選的檔案中有超過 20MB 的項目，下載可能產生流量費用，確定要繼續嗎？",
  "@cloudBrowserMobileDataDialogMessage": {
    "description": "行動數據流量警示對話框內容"
  },
  "cloudBrowserMobileDataDialogConfirm": "繼續下載",
  "@cloudBrowserMobileDataDialogConfirm": {
    "description": "行動數據流量警示對話框的確認按鈕文字"
  },
  "cloudBrowserDownloadSelectedTooltip": "下載已選取",
  "@cloudBrowserDownloadSelectedTooltip": {
    "description": "AppBar 下載按鈕的無障礙提示文字（tooltip）"
  },
  "cloudBrowserReauthMessage": "登入已過期，請至「設定」重新連結 {provider} 帳號",
  "@cloudBrowserReauthMessage": {
    "description": "雲端帳號授權過期時的提示訊息，{provider} 為服務商品牌名（如 Google Drive／OneDrive，不翻譯）或找不到品牌名時的通用「雲端」標籤",
    "placeholders": {
      "provider": {
        "type": "String"
      }
    }
  },
  "cloudBrowserGenericProviderLabel": "雲端",
  "@cloudBrowserGenericProviderLabel": {
    "description": "cloudBrowserReauthMessage 在 widget.title 為 null 時的通用服務商標籤 fallback"
  },
  "cloudBrowserImportCategoryLabel": "匯入分類：",
  "@cloudBrowserImportCategoryLabel": {
    "description": "雲端瀏覽畫面「匯入分類」下拉選單前的標籤文字"
  },
  "cloudBrowserTruncatedNotice": "這個資料夾檔案較多，僅顯示前 1000 筆",
  "@cloudBrowserTruncatedNotice": {
    "description": "資料夾檔案數超過清單上限（1000 筆）時的提示文字"
  }
```

`app/lib/l10n/app_zh_CN.arb`：

```json
  "errorNetworkConnection": "加载失败，请检查网络连接",
  "cloudBrowserDuplicateConfirmMessage": "「{name}」之前已导入过，仍要建立新的一份吗？",
  "cloudBrowserDownloadQueued": "已加入下载队列（{count, plural, =1{1 个文件} other{{count} 个文件}}），可至「来源」画面查看进度",
  "cloudBrowserMobileDataDialogTitle": "移动数据下载提醒",
  "cloudBrowserMobileDataDialogMessage": "目前使用移动数据连接，勾选的文件中有超过 20MB 的项目，下载可能产生流量费用，确定要继续吗？",
  "cloudBrowserMobileDataDialogConfirm": "继续下载",
  "cloudBrowserDownloadSelectedTooltip": "下载已选取",
  "cloudBrowserReauthMessage": "登录已过期，请至「设置」重新连接 {provider} 账户",
  "cloudBrowserGenericProviderLabel": "云端",
  "cloudBrowserImportCategoryLabel": "导入分类：",
  "cloudBrowserTruncatedNotice": "这个文件夹里的文件较多，仅显示前 1000 个"
```

`app/lib/l10n/app_en.arb`：

```json
  "errorNetworkConnection": "Failed to load. Please check your network connection.",
  "cloudBrowserDuplicateConfirmMessage": "\"{name}\" was already imported before. Create a new copy anyway?",
  "cloudBrowserDownloadQueued": "Added to download queue ({count, plural, =1{1 file} other{{count} files}}), check progress in the Sources screen",
  "cloudBrowserMobileDataDialogTitle": "Mobile Data Download Notice",
  "cloudBrowserMobileDataDialogMessage": "You're currently on a mobile data connection, and some selected files are over 20MB. Downloading may incur data charges. Continue anyway?",
  "cloudBrowserMobileDataDialogConfirm": "Continue Download",
  "cloudBrowserDownloadSelectedTooltip": "Download Selected",
  "cloudBrowserReauthMessage": "Login expired. Please reconnect your {provider} account in Settings.",
  "cloudBrowserGenericProviderLabel": "cloud",
  "cloudBrowserImportCategoryLabel": "Import to category:",
  "cloudBrowserTruncatedNotice": "This folder has many files; only the first 1000 are shown."
```

`app/lib/l10n/app_zh.arb`：

```json
  "errorNetworkConnection": "載入失敗，請檢查網路連線",
  "cloudBrowserDuplicateConfirmMessage": "「{name}」之前匯入過了，仍要建立新的一份嗎？",
  "cloudBrowserDownloadQueued": "已加入下載佇列（{count, plural, =1{1 個檔案} other{{count} 個檔案}}），可至「來源」畫面查看進度",
  "cloudBrowserMobileDataDialogTitle": "行動數據下載提醒",
  "cloudBrowserMobileDataDialogMessage": "目前使用行動數據連線，勾選的檔案中有超過 20MB 的項目，下載可能產生流量費用，確定要繼續嗎？",
  "cloudBrowserMobileDataDialogConfirm": "繼續下載",
  "cloudBrowserDownloadSelectedTooltip": "下載已選取",
  "cloudBrowserReauthMessage": "登入已過期，請至「設定」重新連結 {provider} 帳號",
  "cloudBrowserGenericProviderLabel": "雲端",
  "cloudBrowserImportCategoryLabel": "匯入分類：",
  "cloudBrowserTruncatedNotice": "這個資料夾檔案較多，僅顯示前 1000 筆"
```

- [ ] **Step 2: 重新產生 `AppLocalizations`**

Run: `flutter gen-l10n`
Expected: 無錯誤；`cloudBrowserDownloadQueued(int count)`／`cloudBrowserDuplicateConfirmMessage(String name)`／`cloudBrowserReauthMessage(String provider)` 為帶參數方法，其餘為無參數 getter。

- [ ] **Step 3: 寫失敗測試（既有測試遷移 + 新增 8 個測試，含 `/receiving-code-review` I-2 修正後補齊的 title 回退路徑覆蓋、M-3 修正後拆分的單複數獨立測試）**

修改 `app/test/screens/cloud_browser_screen_test.dart`，開頭新增 import：

```dart
import '../support/pump_localized_widget.dart';
```

**3a. `pumpScreen()` 輔助函式遷移**（原第 91-122 行）：

```dart
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeCloudStorageClient client,
    FakeLibraryRepository? libraryRepository,
    FakeBookImportService? importService,
    FakeFingerprintComputer? fingerprintComputer,
    Future<bool> Function()? isMobileDataConnection,
    String? folderId,
    String? title,
    DownloadQueueController? downloadQueueController,
    Locale locale = const Locale('zh', 'TW'),
  }) async {
    await pumpLocalizedWidget(
      tester,
      CloudBrowserScreen(
        client: client,
        libraryRepository: libraryRepository ?? FakeLibraryRepository(),
        importService: importService ?? FakeBookImportService(),
        source: BookSource.googleDrive,
        computeFingerprint:
            (fingerprintComputer ?? FakeFingerprintComputer()).call,
        isMobileDataConnection: isMobileDataConnection,
        downloadQueueController:
            downloadQueueController ??
            DownloadQueueController(
              onDuplicateConfirm: (_) async => false,
            ),
        folderId: folderId,
        title: title,
      ),
      locale: locale,
    );
    await tester.pumpAndSettle();
  }
```

（新增 `locale` 具名參數、預設 `zh_TW`，供本 Task 新增的多語言測試複用同一個 helper，既有呼叫端不受影響；新增 `title` 具名參數、預設 `null`，`/receiving-code-review` I-2 修正——原本既有呼叫端一律不傳 `title`，`CloudBrowserScreen.title` 因此永遠是 `null`，任何斷言「重新連結提示顯示品牌名」的測試都不可能通過，需要能明確注入。）

**3b. 既有測試不需修改斷言內容**——全部 17 個既有 `testWidgets` 皆以 `Key(...)` 而非文字內容斷言雲端瀏覽相關 UI（已逐一查證：截斷提示、重新連結訊息、下載完成 SnackBar、行動數據對話框、重複提示對話框皆只斷言 `Key` 存在與否），`pumpScreen()` 遷移後這些測試預期原樣通過。

**3c. 新增 8 個測試**（加在檔案最後一個既有 `testWidgets`「行動數據確認對話框選擇取消時不開始下載」之後、`_ThrowingCloudStorageClient` 類別定義之前）：

```dart

  testWidgets('分類下拉選單「未分類」選項依目前介面語言正確轉譯，使用者自訂分類原樣顯示', (tester) async {
    final libraryRepository = FakeLibraryRepository();
    await libraryRepository.upsertGroup('小說');
    final client = FakeCloudStorageClient(
      folderContents: {
        null: const CloudFolderListing(entries: [fileEntryNoThumbnail]),
      },
    );
    await pumpScreen(
      tester,
      client: client,
      libraryRepository: libraryRepository,
      locale: const Locale('en'),
    );

    await tester.tap(
      find.byKey(const Key('google_drive_browser_group_dropdown')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Uncategorized').last, findsOneWidget);
    expect(find.text('小說').last, findsOneWidget);
    expect(find.text('Import to category:'), findsOneWidget);
  });

  testWidgets('英文介面下，資料夾檔案數超過 1000 筆時提示文字正確以英文渲染', (tester) async {
    final client = FakeCloudStorageClient(
      folderContents: {
        null: const CloudFolderListing(
          entries: [fileEntryNoThumbnail],
          truncated: true,
        ),
      },
    );
    await pumpScreen(tester, client: client, locale: const Locale('en'));

    expect(
      find.text('This folder has many files; only the first 1000 are shown.'),
      findsOneWidget,
    );
  });

  testWidgets(
      '英文介面下，access token 過期時重新連結訊息正確代入品牌名並以英文渲染'
      '（/receiving-code-review I-2 修正：明確傳入 title，原測試未注入 '
      'title 時 widget.title 恆為 null，斷言與實作回退邏輯不符）',
      (tester) async {
    final client = _ThrowingCloudStorageClient();
    await pumpScreen(
      tester,
      client: client,
      title: 'Google Drive',
      locale: const Locale('en'),
    );

    expect(
      find.text('Login expired. Please reconnect your Google Drive account '
          'in Settings.'),
      findsOneWidget,
    );
  });

  testWidgets(
      '英文介面下，未提供 title 時重新連結訊息正確回退為通用「cloud」標籤'
      '（/receiving-code-review I-2 修正一併補齊的回退路徑覆蓋）',
      (tester) async {
    final client = _ThrowingCloudStorageClient();
    await pumpScreen(tester, client: client, locale: const Locale('en'));

    expect(
      find.text('Login expired. Please reconnect your cloud account '
          'in Settings.'),
      findsOneWidget,
    );
  });

  testWidgets('英文介面下，一般載入失敗訊息正確以英文渲染', (tester) async {
    final client = _NetworkErrorCloudStorageClient();
    await pumpScreen(tester, client: client, locale: const Locale('en'));

    expect(
      find.text('Failed to load. Please check your network connection.'),
      findsOneWidget,
    );
  });

  testWidgets('英文介面下，行動數據對話框標題/內容/按鈕正確以英文渲染', (tester) async {
    final client = FakeCloudStorageClient(
      folderContents: {
        null: const CloudFolderListing(entries: [largeFileEntry]),
      },
    );
    await pumpScreen(
      tester,
      client: client,
      isMobileDataConnection: () async => true,
      locale: const Locale('en'),
    );

    await tester.tap(
      find.byKey(const Key('google_drive_browser_entry_file-large')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('google_drive_browser_download_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mobile Data Download Notice'), findsOneWidget);
    expect(
      find.text(
        "You're currently on a mobile data connection, and some selected "
        'files are over 20MB. Downloading may incur data charges. Continue '
        'anyway?',
      ),
      findsOneWidget,
    );
    expect(find.text('Continue Download'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets(
      '下載加入佇列（1 個檔案）SnackBar 依 ICU plural 正確以英文單數渲染 (1 file)'
      '（/receiving-code-review M-3 修正：拆分自原本單一測試內連續 pump 兩個'
      '獨立 client 的寫法，避免前次 pump 殘留的 SnackBar 排程互相干擾）',
      (tester) async {
    final client = FakeCloudStorageClient(
      folderContents: {
        null: const CloudFolderListing(entries: [fileEntryNoThumbnail]),
      },
      downloadContents: {'file-1': [1, 2, 3]},
    );
    await pumpScreen(tester, client: client, locale: const Locale('en'));
    await tester.tap(
      find.byKey(const Key('google_drive_browser_entry_file-1')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('google_drive_browser_download_button')),
    );
    await tester.pump();

    expect(find.text('Added to download queue (1 file), check progress '
        'in the Sources screen'), findsOneWidget);
  });

  testWidgets('下載加入佇列（多個檔案）SnackBar 依 ICU plural 正確以英文複數渲染 (2 files)',
      (tester) async {
    final client = FakeCloudStorageClient(
      folderContents: {
        null: const CloudFolderListing(
          entries: [fileEntryNoThumbnail, fileEntryWithThumbnail],
        ),
      },
      downloadContents: {
        'file-1': [1, 2, 3],
        'file-2': [4, 5, 6],
      },
    )..thumbnailBytes = validPngBytes;
    await pumpScreen(tester, client: client, locale: const Locale('en'));
    await tester.tap(
      find.byKey(const Key('google_drive_browser_entry_file-1')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('google_drive_browser_entry_file-2')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('google_drive_browser_download_button')),
    );
    await tester.pump();

    expect(find.text('Added to download queue (2 files), check progress '
        'in the Sources screen'), findsOneWidget);
  });
```

在檔案最後、`_ThrowingCloudStorageClient` 類別定義之後，新增第二個測試用假實作：

```dart

class _NetworkErrorCloudStorageClient extends FakeCloudStorageClient {
  @override
  Future<CloudFolderListing> listFolder({String? folderId}) async {
    throw Exception('network down');
  }
}
```

- [ ] **Step 4: 執行測試確認失敗**

Run: `flutter test test/screens/cloud_browser_screen_test.dart`
Expected: 新增的 8 個測試皆 FAIL（畫面尚未接上對應 `AppLocalizations` key，仍顯示 Step 5 實作前的原始正體中文字面值，找不到任何預期的英文文字）；既有 17 個測試預期仍 PASS（尚未變更任何既有 Key 結構）。

- [ ] **Step 5: 實作 `cloud_browser_screen.dart`**

修改 `app/lib/screens/cloud_browser_screen.dart`。

**5a. 新增 import**（在 `import '../library/models/library_enums.dart';` 之後）：

```dart
import '../l10n/app_localizations.dart';
```

**5b. `_load()` 的 catch-all 分支**（原第 151-157 行）：

```dart
    } catch (_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _loading = false;
        _errorText = l10n.errorNetworkConnection;
      });
    }
```

**5c. `_toggleSelection()` 的重複確認訊息**（原第 198-205 行）：

```dart
    if (hasDuplicate) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      final proceed = await showCloudDuplicateConfirmDialog(
        context,
        l10n.cloudBrowserDuplicateConfirmMessage(entry.name),
      );
      if (!proceed) return;
    }
```

**5d. `_startDownload()` 的 SnackBar**（原第 247-254 行）：

```dart
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('google_drive_browser_queued_snackbar'),
        content: Text(l10n.cloudBrowserDownloadQueued(selected.length)),
      ),
    );
    setState(() => _selectedIds.clear());
```

**5e. `_confirmMobileDataDownload()`**（原第 261-285 行，完整改寫）：

```dart
  Future<bool?> _confirmMobileDataDownload() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final dialogL10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          key: const Key('cloud_mobile_data_dialog'),
          title: Text(dialogL10n.cloudBrowserMobileDataDialogTitle),
          content: Text(dialogL10n.cloudBrowserMobileDataDialogMessage),
          actions: [
            TextButton(
              key: const Key('cloud_mobile_data_dialog_cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogL10n.cancel),
            ),
            TextButton(
              key: const Key('cloud_mobile_data_dialog_confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(dialogL10n.cloudBrowserMobileDataDialogConfirm),
            ),
          ],
        );
      },
    );
  }
```

**5f. `build()`**（原第 287-327 行，完整改寫）：

```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Google Drive'),
        actions: [
          IconButton(
            key: const Key('google_drive_browser_download_button'),
            icon: const Icon(Icons.download),
            tooltip: l10n.cloudBrowserDownloadSelectedTooltip,
            onPressed: _selectedIds.isEmpty ? null : _startDownload,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('google_drive_browser_loading_indicator'),
              ),
            )
          : _needsReauth
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.cloudBrowserReauthMessage(
                    widget.title ?? l10n.cloudBrowserGenericProviderLabel,
                  ),
                  key: const Key('google_drive_browser_reauth_text'),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _errorText != null
          ? Center(
              child: Text(
                _errorText!,
                key: const Key('google_drive_browser_error_text'),
              ),
            )
          : _buildContent(),
    );
  }
```

**5g. `_buildContent()`**（原第 329-383 行，完整改寫；`_buildEntryTile()`／`_buildThumbnail()` 不需改動，原樣保留）：

```dart
  Widget _buildContent() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(l10n.cloudBrowserImportCategoryLabel),
              const SizedBox(width: 8),
              DropdownButton<String>(
                key: const Key('google_drive_browser_group_dropdown'),
                value: _selectedGroupName,
                items: [
                  DropdownMenuItem(
                    value: BookGroup.uncategorized,
                    child: Text(localizeGroupName(BookGroup.uncategorized, l10n)),
                  ),
                  for (final group in _groups.where(
                    (g) => g.name != BookGroup.uncategorized,
                  ))
                    DropdownMenuItem(
                      value: group.name,
                      child: Text(group.name),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedGroupName = value);
                },
              ),
            ],
          ),
        ),
        if (_truncated)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l10n.cloudBrowserTruncatedNotice,
              key: const Key('google_drive_browser_truncated_text'),
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.6,
            ),
            itemCount: _entries.length,
            itemBuilder: (context, index) => _buildEntryTile(_entries[index]),
          ),
        ),
      ],
    );
  }
```

- [ ] **Step 6: 執行測試確認通過**

Run: `flutter test test/screens/cloud_browser_screen_test.dart`
Expected: PASS（既有 17 個測試＋新增 8 個，共 25 個，零回歸）。

- [ ] **Step 7: `flutter analyze`**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 8: Commit**

```bash
git add lib/l10n/ lib/screens/cloud_browser_screen.dart test/screens/cloud_browser_screen_test.dart
git commit -m "feat(epic-45): cloud_browser_screen.dart 分類下拉選單在地化＋全部既有字串抽取"
```

---

### Task 5：完整驗收

**Files:** `docs/epics/epic-45-interface-i18n/issues.md`／`epic.md`／`docs/epics.md`，無程式碼修改。

- [ ] **Step 1: 完整 `flutter analyze`**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 2: 完整 `flutter test`**

Run: `flutter test`
Expected: 全數通過（若有既存、與本 Issue 無關的既知不穩定測試，比對是否為 base commit 既存缺陷而非本 Issue 引入的回歸）。

- [ ] **Step 3: 確認 `reader_screen.dart`／`reader_screen_test.dart` 零異動**

Run:
```bash
git diff main -- lib/screens/reader_screen.dart test/screens/reader_screen_test.dart
```
Expected: 空輸出（無任何差異），驗證 Global Constraints「嚴禁觸碰 reader_screen.dart」承諾兌現。

- [ ] **Step 4: 手動驗證三語言下分類名稱顯示**

Run:
```bash
flutter run
```
Expected: 「設定→語言」切換至簡體中文／English 後，書架的分類管理對話框、「移動到分類」對話框、雲端匯入畫面的分類下拉選單，「未分類」皆正確顯示為「未分类」／"Uncategorized"；使用者自訂分類名稱不受影響；嘗試新增/重新命名為任一語言的保留字皆被攔截並顯示錯誤。

- [ ] **Step 5: 修訂 `issues.md`——標記 Issue 2 完成＋修正 Issue 6 檔案清單**

在「Issue 2」標題旁補上 `**Status:** completed`。

同步修正「Issue 6：其餘管理類彈窗與畫面字串抽取＋測試遷移」的「What to build」檔案清單（Global Constraints 已記錄的範圍爭議，使用者裁定 Issue 2 一次抽完），把：

```
`remote_server_list_screen.dart`／`remote_server_form_screen.dart`／`remote_catalog_screen.dart`／`cloud_browser_screen.dart`（分類下拉選單已在 Issue 2 處理，本 Issue 處理其餘字串）／`wifi_transfer_screen.dart`／`sources_home_screen.dart`／`adaptive_shell_scaffold.dart`／`support/book_import_picker_helper.dart`（本檔案同時是 Issue 7 錯誤代碼映射函式的落點，若排程上與 Issue 7 重疊建議協調）。
```

改為：

```
`remote_server_list_screen.dart`／`remote_server_form_screen.dart`／`remote_catalog_screen.dart`／`wifi_transfer_screen.dart`／`sources_home_screen.dart`／`adaptive_shell_scaffold.dart`／`support/book_import_picker_helper.dart`（本檔案同時是 Issue 7 錯誤代碼映射函式的落點，若排程上與 Issue 7 重疊建議協調）。**`cloud_browser_screen.dart` 已在 Issue 2 完整處理（含分類下拉選單與其餘既有字串），本 Issue 不再處理**（`plan-issue-2.md` Global Constraints 記錄之範圍爭議，2026-09-21 使用者裁定 Issue 2 一次抽完）。
```

- [ ] **Step 6: 更新 `epic.md`**

新增一段開發記錄，記錄本 Issue 完成情況（`book_group.dart` 新增 `localizeGroupName`/`isReservedGroupName`／3 個畫面完整字串抽取／撞名防線／`issues.md` Issue 6 範圍同步修正）與下一步（認領 Issue 3-6 任一模組）。

- [ ] **Step 7: 更新 `docs/epics.md` 進度**

把第 46 列（`epic-45-interface-i18n`）備註欄位改為反映 Issue 2 已完成（例如「Issue 0／1／2 已完成並合併，待認領 Issue 3-6」，實際 PR 編號待發 PR 時才會知道）。

- [ ] **Step 8: Commit**

```bash
git add ../docs/epics/epic-45-interface-i18n/issues.md ../docs/epics/epic-45-interface-i18n/epic.md ../docs/epics.md
git commit -m "docs(epic-45): 標記 Issue 2 為 completed，修正 issues.md Issue 6 範圍"
```

---

## Self-Review 摘要（撰寫計畫時的自我檢查紀錄）

- **Spec 覆蓋度**：`spec.md` §5.1（`localizeGroupName()`／`BookGroupL10n`）→ Task 1；§5.2（撞名防線）→ Task 1（`isReservedGroupName()` 本體）＋ Task 2（`library_group_management_dialog.dart` 整合呼叫）。`issues.md` Issue 2 的 3 條 What-to-build 項目（`book_group.dart`／`library_group_management_dialog.dart` 撞名防線與字串抽取／`library_move_to_group_dialog.dart`＋`cloud_browser_screen.dart` 分類顯示與字串抽取）依序對應 Task 1／Task 2／Task 3+4。單元測試要求 5 條（`isReservedGroupName()` 純邏輯測試／`localizeGroupName()`/`displayName()` 三語言測試／`library_group_management_dialog_test.dart` 保留字攔截／`library_move_to_group_dialog_test.dart`+`cloud_browser_screen_test.dart` 遷移／`reader_screen_test.dart` 零異動迴歸驗證）依序對應 Task 1／Task 1／Task 2／Task 3+4／Task 5 Step 3。
- **型別一致性**：`String localizeGroupName(String name, AppLocalizations l10n)`（Task 1 定義）在 Task 2/3/4 皆以相同簽章透過 `group.displayName(l10n)` 或直接呼叫 `localizeGroupName(BookGroup.uncategorized, l10n)` 消費，無簽章漂移；`bool isReservedGroupName(String name)`（Task 1 定義，公開頂層函式）在 Task 2 `_addGroup()`/`_renameGroup()` 呼叫時參數/回傳型別一致。
- **未使用 placeholder**：所有 Step 皆含可直接執行的完整程式碼／指令；Task 4 因牽涉檔案較大（477 行）與字串數量較多，`_buildEntryTile()`/`_buildThumbnail()` 兩個不需改動的方法明確註記「原樣保留」而非省略不提，避免執行者誤以為需要處理。
- **架構偏離已記錄**：`isReservedGroupName()` 從 `spec.md` §5.2 原設計的 `library_group_management_dialog.dart` 私有函式，改為 `book_group.dart` 的公開頂層函式——已在 Architecture 段落與 Task 1 程式碼註解中明確記錄偏離原因（Dart privacy 以檔案為界線，私有頂層函式無法被獨立測試檔呼叫）與 `issues.md` 措辭本身預留的彈性依據。
- **範圍爭議已由使用者裁定並反映進計畫**：`cloud_browser_screen.dart` 究竟該在 Issue 2 或 Issue 6 抽取其「分類下拉選單以外」的字串，`issues.md` Issue 2／Issue 6 文字互相矛盾，已於規劃階段提出給使用者選擇，使用者裁定「Issue 2 一次抽完」，Task 4 依此執行，Task 5 Step 5 同步修正 `issues.md` Issue 6 的檔案清單移除相關矛盾敘述，避免歸檔後留下自相矛盾的規格文件。

**2026-09-21 `/superpowers:receiving-code-review` 審查（`reviews/review-plan-issue-2.md`，結論 Changes Requested，0 Critical／2 Important／4 Minor）已處理，5 項查證屬實並修訂、1 項查證為誤判**：I-1（宣稱 Task 4 Step 3c Test 6 的 `pumpScreen(tester, client1, locale: ...)` 誤用位置參數，將導致編譯錯誤）——逐行核對計畫檔案第 1279／1303 行實際內容，兩處皆已是 `pumpScreen(tester, client: client1, locale: ...)`／`client: client2` 正確具名參數寫法，與審查報告引用的問題程式碼不符，判定為審查方誤讀（可能讀到非最終版本），**本項不修改**。I-2（重新連結測試斷言 `"Google Drive account"`，但 `pumpScreen` 未提供 `title` 參數、`widget.title` 恆為 `null`，實際會回退渲染 `"cloud account"`，斷言必然失敗——已核對 `pumpScreen` 簽章與 `build()` 的 `widget.title ?? l10n.cloudBrowserGenericProviderLabel` 回退邏輯確認屬實）——採審查建議「途徑 A」：`pumpScreen` 新增 `title` 具名參數並透傳，原測試改為明確傳入 `title: 'Google Drive'`，並額外新增一則「未提供 title 時回退為通用 cloud 標籤」測試同時覆蓋兩條路徑。M-1（`DropdownMenuItem` 直接讀 `l10n.groupUncategorized` 而非呼叫 `localizeGroupName()`，功能等價但未貼合 spec.md §5.1 API 設計初衷）——改為 `localizeGroupName(BookGroup.uncategorized, l10n)`。M-2（Task 3 新測試只驗證顯示文字，未驗證點擊「Uncategorized」選項後 `showDialog` 的 pop 回傳值是否仍為底層 Sentinel `'未分類'`）——補上 `result` 變數與對應 `expect(result, BookGroup.uncategorized)` 斷言。M-3（Test 6 單一測試內連續 pump 兩個獨立 client，建議拆分）——拆為「1 個檔案」／「多個檔案」兩個獨立 `testWidgets`。M-4（`isReservedGroupName` 測試未涵蓋中文保留字帶空白變體）——補上 `'  未分類  '`／`'  未分类  '` 兩筆案例。修訂後 Task 4 新增測試數由 6 個增至 8 個（I-2 額外測試 +1、M-3 拆分 +1），Task 4 各處「新增 6 個測試」計數同步修正為「8 個」。本輪修訂除 I-1（誤判，不修改）外，其餘 5 項全數為測試正確性、防禦性斷言與 API 一致性補強，未變動任何既有架構決策。
