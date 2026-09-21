# Epic 45 Issue 3：書架模組字串抽取＋測試遷移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把書架模組（`LibraryScreen` 及其批次操作、書內搜尋、單書動作選單、格式選擇等相關畫面）的全部硬編碼中文字串改為 `AppLocalizations` key，三語言（正體中文／簡體中文／英文）皆補上真實翻譯，對應測試檔同步遷移至 `pumpLocalizedWidget()`，零使用者可見行為變動（除新增語言支援本身）。

**Architecture:** 沿用 Issue 2 已確立的模式——`AppLocalizations.of(context)!`（non-null assertion，因為 `main.dart`／`pumpLocalizedWidget()` 皆已保證 `localizationsDelegates` 一定存在）＋新增 ARB key（三語言真實翻譯＋`app_zh.arb` fallback 同步）＋既有測試改用 `pumpLocalizedWidget()`。計數字串一律採 ICU `plural` 語法（`spec.md`／`issues.md` 全域規則）。日期格式化改用 `intl` 的 `DateFormat`（`issues.md` I-1 明訂，本 Issue 是本 Epic第一次真正落地這個轉換）。

**範圍已依實際 grep 盤點修正**（`issues.md` 本身註明「代表性範圍，實際檔案清單以認領當下重新 grep 盤點為準」）：
- **移出**：`library_batch_actions.dart`（純邏輯類別，grep 確認零硬編碼字串，不含任何 `Text`/`Widget` 建構）、`format_selection_dialog.dart`（grep 確認唯一呼叫端是 `remote_catalog_screen.dart`，屬 Issue 6「其餘管理類彈窗」範圍，非書架模組）、`layout_preset_book_picker_screen.dart`（grep 確認唯一呼叫端是 `reader_screen.dart` 的版面預設集套用流程，屬 Issue 4「閱讀器 Chrome Bar」範圍）、`library/widgets/cover_placeholder.dart`（檔案不存在——`library/widgets/` 目錄下僅有 `book_cover.dart`，grep 確認零硬編碼字串，本身也不需要任何修改；`issues.md` 這個檔名引用已過時）。
- **新增**：`full_text_search_confirm_dialog.dart`（`showFullTextSearchEnableConfirmDialog()`，grep 確認被 `library_search_screen.dart`〔本 Issue〕與 `settings_scaffold.dart`〔Issue 5〕共用；比照 Issue 0 收斂 `eb_sheet_shell.dart` 的既有先例，由先動工的 Issue 一次處理完畢，避免 Issue 3/5 平行執行時的共用檔案衝突——本 Issue 先認領，Issue 5 屆時不再重複修改）。
- **確認保留**：`book_search_screen.dart`（雖然也被 `reader_screen.dart` 呼叫，但修改這個檔案本身不會觸碰 `reader_screen.dart`，不違反「嚴禁觸碰 `reader_screen.dart`」的範圍限制）。

**Tech Stack:** Flutter `flutter_localizations`／`intl`（ARB／`gen-l10n`，含 ICU `plural`、`DateFormat`）。

**Spec:** `docs/epics/epic-45-interface-i18n/spec.md`（§5.1 `localizeGroupName()`／`BookGroupL10n`、§6 執行期例外訊息慣例、§8 測試相容性）、`docs/epics/epic-45-interface-i18n/issues.md`（Issue 3 段落）。

## Global Constraints

- 所有新增 ARB key 必須同步寫入四份檔案：`app_zh_TW.arb`（含 `@key` description）、`app_zh_CN.arb`、`app_en.arb`（皆為真實翻譯，非機器翻譯佔位）、`app_zh.arb`（與 `app_zh_TW.arb` 相同值，不含 `@key` description block——比照既有四檔案慣例）。
- **嚴禁觸碰** `app/lib/screens/reader_screen.dart` 與 `app/test/screens/reader_screen_test.dart`（其他 Epic／Issue 範圍）。
- ICU plural 全域規則：任何計數字串（英文有單複數變化）一律用 ARB `plural` 語法，不得用字串拼接或手動 if/else 判斷單複數；中文三語言（`zh_TW`/`zh_CN`/`zh`）雖無文法複數變化，仍比照既有 `cloudBrowserDownloadQueued` 先例維持 `plural` 語法結構（`=1{...} other{...}` 兩分支填相同中文措辭），確保 `flutter gen-l10n` 產生的函式簽章在四語言間一致。
- 日期格式化：`_formatLastReadTime()` 改用 `intl` 的 `DateFormat.yMd(Localizations.localeOf(context).toString())`，不得維持手動 `'$y/$m/$d'` 字串拼接（`issues.md` I-1 明訂）。
- 既有測試檔遷移至 `pumpLocalizedWidget()`（`app/test/support/pump_localized_widget.dart`）；若測試檔用自訂 `_wrap()`/`wrap()` helper 函式包裝 `MaterialApp`，直接在該 helper 內補上 `localizationsDelegates`/`supportedLocales`/`locale` 參數（不必然要求呼叫端改用 `pumpLocalizedWidget()` 本身，保留既有 helper 的介面穩定性，這是本 Issue 對 Issue 2 模式的必要延伸——Issue 2 沒遇到這種「測試檔已有自己一層 helper」的情況）。
- `BookGroup` Sentinel 字面值 vs. 表現層轉譯的區分（`spec.md` §5.1，Issue 2 已確立）：`_activeGroupFilter`（AppBar 標題來源）與 `_GroupGridTile`/`_GroupListTile` 顯示的 `tile.name` **一律是使用者自訂分類名稱，不會是 `BookGroup.uncategorized`**——`_buildGroupTiles()` 的既有邏輯（`issues.md`／`design.md` 決策：「未分類」不產生拼貼格）保證這點，因此這些地方**不需要**呼叫 `localizeGroupName()`/`displayName()`；直接用原始字面值即可，不要誤加轉譯呼叫（會是不必要的防禦性程式碼，也可能誤導未來讀者以為這裡真的會遇到 Sentinel 值）。
- `AppLocalizations.of(context)!` 一律用 non-null assertion（不用 nullable fallback）——Issue 2 審查（`review-issue-2.md` Important #1）已確立這個教訓：任何測試檔若因此需要 `AppLocalizations`，一律遷移該測試而非放寬產品程式碼為 nullable。
- 測試執行範圍：單一 Task 完成後只跑該 Task 觸及的測試檔；完整 `flutter test`／`flutter analyze` 僅在 Task 7（最後一個 Task）執行一次。

---

### Task 1: `book_action_sheet.dart`

**Files:**
- Modify: `app/lib/screens/book_action_sheet.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/book_action_sheet_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`（`app/lib/l10n/app_localizations.dart`，Issue 0 已接線）。
- Produces：ARB key `bookActionShowDetails`/`bookActionMove`/`bookActionLayoutOverride`/`bookActionRemoveCache`/`bookActionDelete`（後續 Task 不依賴這些 key，本檔案自成一格）。

- [ ] **Step 1: 新增 ARB key（四語言）**

在 `app/lib/l10n/app_zh_TW.arb` 檔尾（`}` 前）新增：

```json
  "bookActionShowDetails": "詳細資料",
  "@bookActionShowDetails": {
    "description": "單書「⋮」動作選單「詳細資料」選項文字"
  },
  "bookActionMove": "移動",
  "@bookActionMove": {
    "description": "單書「⋮」動作選單「移動」選項文字（移動到分類）"
  },
  "bookActionLayoutOverride": "版面覆寫",
  "@bookActionLayoutOverride": {
    "description": "單書「⋮」動作選單「版面覆寫」選項文字"
  },
  "bookActionRemoveCache": "移除快取",
  "@bookActionRemoveCache": {
    "description": "單書「⋮」動作選單「移除快取」選項文字（僅 Calibre 來源已下載書籍顯示）"
  },
  "bookActionDelete": "刪除",
  "@bookActionDelete": {
    "description": "單書「⋮」動作選單「刪除」選項文字"
  }
```

在 `app/lib/l10n/app_zh_CN.arb` 檔尾新增：

```json
  "bookActionShowDetails": "详细资料",
  "bookActionMove": "移动",
  "bookActionLayoutOverride": "排版覆盖",
  "bookActionRemoveCache": "移除缓存",
  "bookActionDelete": "删除"
```

在 `app/lib/l10n/app_en.arb` 檔尾新增：

```json
  "bookActionShowDetails": "Details",
  "bookActionMove": "Move",
  "bookActionLayoutOverride": "Layout Override",
  "bookActionRemoveCache": "Remove Cache",
  "bookActionDelete": "Delete"
```

在 `app/lib/l10n/app_zh.arb` 檔尾新增（與 `app_zh_TW.arb` 相同值，不含 `@key`）：

```json
  "bookActionShowDetails": "詳細資料",
  "bookActionMove": "移動",
  "bookActionLayoutOverride": "版面覆寫",
  "bookActionRemoveCache": "移除快取",
  "bookActionDelete": "刪除"
```

- [ ] **Step 2: 執行 `flutter gen-l10n` 確認 ARB 語法正確**

Run（在 `app/` 目錄下）：
```bash
flutter gen-l10n
```
Expected: 無錯誤輸出，`app/lib/l10n/app_localizations*.dart` 新增 5 個 getter。

- [ ] **Step 3: 修改 `book_action_sheet.dart` 使用 `AppLocalizations`**

修改 `app/lib/screens/book_action_sheet.dart`：

```dart
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../library/models/book.dart';

/// 單書「⋮」動作選單的動作類型（`spec.md` 功能④）。Sheet 關閉後
/// 透過 `Navigator.pop(BookAction)` 回傳選項，由呼叫端決定實際行為
/// （比照既有 Dialog／Sheet 選項慣例，避免在 Sheet 尚未完全移除時
/// 同幀 push 新 Dialog 導致 Navigator 衝突）。
enum BookAction {
  showDetails,
  move,
  layoutOverride,
  removeCache,
  delete,
}

/// 單書「⋮」動作選單內容（`DESIGN.md` §11.3／`spec.md` 功能④）：純呈現，
/// 點擊選項後透過 `Navigator.pop(BookAction)` 回傳動作類型，由呼叫端
/// （`library_screen.dart`）負責實際邏輯。選項是否渲染由 `showRemoveCache`
/// 與 `showLayoutOverride` 控制。
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

  const BookActionSheet({
    super.key,
    required this.book,
    required this.showRemoveCache,
    required this.showLayoutOverride,
  });

  void _handle(BuildContext context, BookAction action) {
    Navigator.of(context).pop(action);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
            title: Text(l10n.bookActionShowDetails),
            onTap: () => _handle(context, BookAction.showDetails),
          ),
          ListTile(
            key: const Key('book_action_move'),
            leading: const Icon(Icons.drive_file_move),
            title: Text(l10n.bookActionMove),
            onTap: () => _handle(context, BookAction.move),
          ),
          if (showLayoutOverride)
            ListTile(
              key: const Key('book_action_layout_override'),
              leading: const Icon(Icons.view_column_outlined),
              title: Text(l10n.bookActionLayoutOverride),
              onTap: () => _handle(context, BookAction.layoutOverride),
            ),
          if (showRemoveCache)
            ListTile(
              key: const Key('book_action_remove_cache'),
              leading: const Icon(Icons.cloud_off_outlined),
              title: Text(l10n.bookActionRemoveCache),
              onTap: () => _handle(context, BookAction.removeCache),
            ),
          ListTile(
            key: const Key('book_action_delete'),
            leading: const Icon(Icons.delete),
            title: Text(l10n.bookActionDelete),
            onTap: () => _handle(context, BookAction.delete),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 遷移既有測試檔至含 `AppLocalizations` 的 `MaterialApp`**

`app/test/screens/book_action_sheet_test.dart` 的 `_buildApp()`／`_buildResultApp()` 兩個 helper 目前回傳裸 `MaterialApp(home: ...)`。修改這兩個 helper（檔案其餘部分不變）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
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

/// 建立包含 BookActionSheet 的 MaterialApp widget。
Widget _buildApp({
  bool showRemoveCache = true,
  bool showLayoutOverride = true,
  Locale locale = const Locale('zh', 'TW'),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          builder: (context) => BookActionSheet(
            book: _book(),
            showRemoveCache: showRemoveCache,
            showLayoutOverride: showLayoutOverride,
          ),
        ),
        child: const Text('open'),
      ),
    ),
  );
}

/// 建立會回傳 BookAction 結果的 MaterialApp widget。
Widget _buildResultApp({
  required ValueNotifier<BookAction?> resultNotifier,
  bool showRemoveCache = true,
  bool showLayoutOverride = true,
  Locale locale = const Locale('zh', 'TW'),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          resultNotifier.value = await showModalBottomSheet<BookAction>(
            context: context,
            builder: (context) => BookActionSheet(
              book: _book(),
              showRemoveCache: showRemoveCache,
              showLayoutOverride: showLayoutOverride,
            ),
          );
        },
        child: const Text('open'),
      ),
    ),
  );
}
```

其餘測試內容（`main()` 內 10 個 `testWidgets`）維持原樣不動——因為預設 `locale` 已釘定為 `zh_TW`，既有 `find.byKey(...)` 斷言全數不受影響（本檔案沒有 `find.text('...')` 斷言中文字面值）。

- [ ] **Step 5: 新增三語言渲染驗證測試**

在 `app/test/screens/book_action_sheet_test.dart` 檔尾 `main()` 的最後一個 `testWidgets` 之後、`}` 之前新增：

```dart
  testWidgets('英文介面下五個選項文字正確以英文渲染', (tester) async {
    await tester.pumpWidget(_buildApp(locale: const Locale('en')));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Move'), findsOneWidget);
    expect(find.text('Layout Override'), findsOneWidget);
    expect(find.text('Remove Cache'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('簡體中文介面下選項文字正確以簡體渲染', (tester) async {
    await tester.pumpWidget(
      _buildApp(locale: const Locale('zh', 'CN')),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('详细资料'), findsOneWidget);
    expect(find.text('排版覆盖'), findsOneWidget);
    expect(find.text('移除缓存'), findsOneWidget);
  });
```

- [ ] **Step 6: 執行測試確認全數通過**

Run:
```bash
flutter test test/screens/book_action_sheet_test.dart
```
Expected: 全數通過（既有 10 個＋新增 2 個，共 12 個）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run:
```bash
flutter analyze lib/screens/book_action_sheet.dart test/screens/book_action_sheet_test.dart
```
Expected: No issues found!

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/book_action_sheet.dart app/test/screens/book_action_sheet_test.dart app/lib/l10n/
git commit -m "feat(epic-45): book_action_sheet.dart 字串抽取三語言在地化"
```

---

### Task 2: `full_text_search_confirm_dialog.dart`

**Files:**
- Modify: `app/lib/screens/full_text_search_confirm_dialog.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/full_text_search_confirm_dialog_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`。
- Produces：ARB key `fullTextSearchEnableDialogTitle`/`fullTextSearchEnableMessagePdf`/`fullTextSearchEnableMessageOther`/`fullTextSearchEnableConfirmButton`；`cancel`（沿用 Issue 2 已建立的全域共用 key）。此檔案同時被 Issue 5（`settings_scaffold.dart`）呼叫，Issue 5 的計畫應直接消費這些既有 key，不重複新增。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 檔尾新增：

```json
  "fullTextSearchEnableDialogTitle": "啟用全文檢索",
  "@fullTextSearchEnableDialogTitle": {
    "description": "「啟用全文檢索」確認對話框標題（PDF／其他格式共用同一對話框）"
  },
  "fullTextSearchEnableMessagePdf": "將觸發背景索引建置（含既有書庫舊書回填），過程會增加運算與電量消耗，是否繼續？\n\n部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容，索引後仍查不到屬於正常情況。",
  "@fullTextSearchEnableMessagePdf": {
    "description": "啟用 PDF 全文檢索時的確認訊息（額外附加掃描件提示）"
  },
  "fullTextSearchEnableMessageOther": "將觸發背景索引建置（含既有書庫舊書回填），過程會增加運算與電量消耗，是否繼續？",
  "@fullTextSearchEnableMessageOther": {
    "description": "啟用其他格式（EPUB/TXT/KF8）全文檢索時的確認訊息"
  },
  "fullTextSearchEnableConfirmButton": "確認開啟",
  "@fullTextSearchEnableConfirmButton": {
    "description": "「啟用全文檢索」確認對話框的確認按鈕文字"
  }
```

`app_zh_CN.arb` 檔尾新增：

```json
  "fullTextSearchEnableDialogTitle": "启用全文检索",
  "fullTextSearchEnableMessagePdf": "将触发后台索引建立（含既有书库旧书回填），过程会增加运算与电量消耗，是否继续？\n\n部分扫描/图片型 PDF 可能没有可搜索的文字内容，索引后仍查不到属于正常情况。",
  "fullTextSearchEnableMessageOther": "将触发后台索引建立（含既有书库旧书回填），过程会增加运算与电量消耗，是否继续？",
  "fullTextSearchEnableConfirmButton": "确认开启"
```

`app_en.arb` 檔尾新增：

```json
  "fullTextSearchEnableDialogTitle": "Enable Full-Text Search",
  "fullTextSearchEnableMessagePdf": "This will start background indexing (including existing books in your library), which increases CPU and battery usage. Continue?\n\nSome scanned/image-based PDFs may not contain searchable text — it's normal if they still can't be found after indexing.",
  "fullTextSearchEnableMessageOther": "This will start background indexing (including existing books in your library), which increases CPU and battery usage. Continue?",
  "fullTextSearchEnableConfirmButton": "Enable"
```

`app_zh.arb` 檔尾新增：

```json
  "fullTextSearchEnableDialogTitle": "啟用全文檢索",
  "fullTextSearchEnableMessagePdf": "將觸發背景索引建置（含既有書庫舊書回填），過程會增加運算與電量消耗，是否繼續？\n\n部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容，索引後仍查不到屬於正常情況。",
  "fullTextSearchEnableMessageOther": "將觸發背景索引建置（含既有書庫舊書回填），過程會增加運算與電量消耗，是否繼續？",
  "fullTextSearchEnableConfirmButton": "確認開啟"
```

- [ ] **Step 2: 執行 `flutter gen-l10n`**

Run: `flutter gen-l10n`
Expected: 無錯誤。

- [ ] **Step 3: 修改 `full_text_search_confirm_dialog.dart`**

```dart
// app/lib/screens/full_text_search_confirm_dialog.dart
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../search/full_text_search_settings_repository.dart';

/// 「啟用全文檢索」確認對話框（epic-10-search Issue 3，見 spec.md §4）：
/// 兩個分類（PDF／其他格式）共用同一個對話框，依 [category] 帶入不同
/// 文案；套用 `DESIGN.md` §9.1 一般排版慣例（平板上限寬度 400dp、主動作
/// 靠右、E-Ink 模式下 Scrim 即時切換不淡入淡出），但**不套用** §9.2「破壞
/// 性操作」的 error 色按鈕慣例——啟用全文檢索不會刪除/遺失任何資料。
/// `content` 用 `ConstrainedBox(maxWidth: 400)` 而非固定寬度的 `SizedBox`
/// （review-plan-issue-3.md I-3：`AlertDialog` 預設 `insetPadding` 左右各
/// 40dp，共 80dp，`SizedBox` 施加的緊約束若沒扣掉這個值，在 360～400dp
/// 手機上會溢位；`ConstrainedBox` 只設上限，實際寬度仍依父層可用空間
/// 收縮，不會超出）。`EBDialogShell` 目前尚未落地為共用元件，手動以
/// `AlertDialog` 符合上述排版規則。
///
/// 純 UI 確認元件，本身不呼叫 [FullTextSearchSettingsRepository]——呼叫端
/// （`SettingsScaffold`）在使用者按下「確認開啟」（本函式回傳 `true`）之後
/// 才呼叫 `setEnabled(category, true)`，比照既有
/// `showCloudDuplicateConfirmDialog()` 純回傳 bool 的既有慣例。
/// 同時被 `library_search_screen.dart`（epic-45-interface-i18n Issue 3）與
/// `settings_scaffold.dart`（Issue 5）共用，本檔案的在地化已在 Issue 3
/// 一次完成。
Future<bool> showFullTextSearchEnableConfirmDialog(
  BuildContext context, {
  required ContentIndexCategory category,
  bool isEinkMode = false,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final message = category == ContentIndexCategory.pdf
      ? l10n.fullTextSearchEnableMessagePdf
      : l10n.fullTextSearchEnableMessageOther;
  final result = await showDialog<bool>(
    context: context,
    animationStyle: isEinkMode ? AnimationStyle.noAnimation : null,
    builder: (dialogContext) {
      final dialogL10n = AppLocalizations.of(dialogContext)!;
      return AlertDialog(
        key: const Key('full_text_search_enable_confirm_dialog'),
        title: Text(dialogL10n.fullTextSearchEnableDialogTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Text(message),
        ),
        actions: [
          TextButton(
            key: const Key('full_text_search_enable_confirm_dialog_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogL10n.cancel),
          ),
          TextButton(
            key: const Key('full_text_search_enable_confirm_dialog_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogL10n.fullTextSearchEnableConfirmButton),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
```

- [ ] **Step 4: 遷移既有測試檔**

`app/test/screens/full_text_search_confirm_dialog_test.dart` 有 3 處建構 `MaterialApp`：`_open()` helper（1 處）與 2 處內嵌在個別 `testWidgets` 內（無法改用 `_open()`，因為這兩個測試需要在對話框關閉「前」先取得 Future 控制權，見既有註解）。三處皆補上 `localizationsDelegates`/`supportedLocales`/`locale`：

```dart
// app/test/screens/full_text_search_confirm_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/screens/full_text_search_confirm_dialog.dart';
import 'package:elinkbook/search/full_text_search_settings_repository.dart';

/// 捕捉 Navigator 實際推入的 Route，供斷言 `DialogRoute` 的
/// `transitionDuration` 是否真的依 `isEinkMode` 走到 `AnimationStyle.
/// noAnimation`（比照 `test/screens/widgets/eb_sheet_shell_test.dart`
/// 既有手法）。
class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushedRoute = route;
  }
}

Future<bool?> _open(
  WidgetTester tester, {
  required ContentIndexCategory category,
  bool isEinkMode = false,
  NavigatorObserver? observer,
  Locale locale = const Locale('zh', 'TW'),
}) async {
  bool? result;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: observer == null ? [] : [observer],
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showFullTextSearchEnableConfirmDialog(
              context,
              category: category,
              isEinkMode: isEinkMode,
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('按下取消對話框關閉', (tester) async {
    await _open(tester, category: ContentIndexCategory.foliate);
    await tester.tap(find.byKey(
      const Key('full_text_search_enable_confirm_dialog_cancel'),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('full_text_search_enable_confirm_dialog')),
      findsNothing,
    );
  });

  testWidgets('按下確認開啟回傳 true', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showFullTextSearchEnableConfirmDialog(
                context,
                category: ContentIndexCategory.foliate,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
      const Key('full_text_search_enable_confirm_dialog_confirm'),
    ));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('PDF 分類額外顯示掃描件提示文案', (tester) async {
    await _open(tester, category: ContentIndexCategory.pdf);

    expect(find.textContaining('掃描/圖片型 PDF'), findsOneWidget);
  });

  testWidgets('Foliate 分類不顯示 PDF 專屬提示文案', (tester) async {
    await _open(tester, category: ContentIndexCategory.foliate);

    expect(find.textContaining('掃描/圖片型 PDF'), findsNothing);
  });

  testWidgets('對話框寬度不超過 400，且不強制施加緊約束（review-plan-issue-3.md I-3）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showFullTextSearchEnableConfirmDialog(
              context,
              category: ContentIndexCategory.foliate,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 不應有任何 overflow 相關的 FlutterError（pumpAndSettle 若渲染期間
    // 拋出 overflow 例外，測試本身就會直接失敗），此處額外斷言對話框
    // 確實成功渲染出來，佐證沒有在 debug 模式被 overflow 中斷。
    expect(
      find.byKey(const Key('full_text_search_enable_confirm_dialog')),
      findsOneWidget,
    );
  });

  testWidgets('isEinkMode: true 時彈出動畫時長為 Duration.zero', (tester) async {
    final observer = _RecordingNavigatorObserver();
    await _open(
      tester,
      category: ContentIndexCategory.foliate,
      isEinkMode: true,
      observer: observer,
    );

    final route = observer.lastPushedRoute;
    expect(route, isA<DialogRoute>());
    expect((route as DialogRoute).transitionDuration, Duration.zero);
  });

  testWidgets('isEinkMode: false（預設）時彈出動畫時長非 Duration.zero',
      (tester) async {
    final observer = _RecordingNavigatorObserver();
    await _open(
      tester,
      category: ContentIndexCategory.foliate,
      observer: observer,
    );

    final route = observer.lastPushedRoute;
    expect(route, isA<DialogRoute>());
    expect((route as DialogRoute).transitionDuration, isNot(Duration.zero));
  });

  testWidgets('英文介面下標題/訊息/按鈕正確以英文渲染', (tester) async {
    await _open(
      tester,
      category: ContentIndexCategory.pdf,
      locale: const Locale('en'),
    );

    expect(find.text('Enable Full-Text Search'), findsOneWidget);
    expect(find.text('Enable'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.textContaining('scanned/image-based PDFs'), findsOneWidget);
  });
}
```

- [ ] **Step 5: 執行測試確認全數通過**

Run:
```bash
flutter test test/screens/full_text_search_confirm_dialog_test.dart
```
Expected: 全數通過（既有 6 個＋新增 1 個，共 7 個）。

- [ ] **Step 6: `flutter analyze` 確認乾淨**

Run:
```bash
flutter analyze lib/screens/full_text_search_confirm_dialog.dart test/screens/full_text_search_confirm_dialog_test.dart
```
Expected: No issues found!

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/full_text_search_confirm_dialog.dart app/test/screens/full_text_search_confirm_dialog_test.dart app/lib/l10n/
git commit -m "feat(epic-45): full_text_search_confirm_dialog.dart 三語言在地化（Issue 3/5 共用，一次處理完畢）"
```

---

### Task 3: `book_search_screen.dart`

**Files:**
- Modify: `app/lib/screens/book_search_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/book_search_screen_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`。
- Produces：ARB key `bookSearchHint`/`searchClearTooltip`/`fullTextSearchUnavailableMessage`/`bookSearchResultsSummary`/`bookSearchResultsSummaryTruncated`/`bookSearchSortByPosition`/`bookSearchSortByRelevance`/`fullTextSearchNoContentMatches`/`bookSearchLocationPage`/`bookSearchLocationChapter`。**`searchClearTooltip`／`fullTextSearchUnavailableMessage`／`fullTextSearchNoContentMatches` 三個 key 在本 Task 首次定義，Task 4（`library_search_screen.dart`）會直接消費這三個既有 key，不重複新增**（兩檔案皆有完全相同語意的「清除」按鈕/「本裝置不支援全文檢索」/「查無符合的書內內容」文字）。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 檔尾新增：

```json
  "bookSearchHint": "在本書中搜尋...",
  "@bookSearchHint": {
    "description": "單書內容搜尋畫面輸入框的 hintText"
  },
  "searchClearTooltip": "清除",
  "@searchClearTooltip": {
    "description": "搜尋輸入框「清除」按鈕的無障礙提示文字，book_search_screen.dart／library_search_screen.dart 共用"
  },
  "fullTextSearchUnavailableMessage": "本裝置不支援全文檢索",
  "@fullTextSearchUnavailableMessage": {
    "description": "裝置不支援全文檢索時的提示訊息，book_search_screen.dart／library_search_screen.dart 共用"
  },
  "bookSearchResultsSummary": "{total, plural, =1{共 1 筆結果} other{共 {total} 筆結果}}",
  "@bookSearchResultsSummary": {
    "description": "單書內容搜尋結果數量摘要（未截斷情境），{total} 為結果總數",
    "placeholders": {
      "total": {
        "type": "int"
      }
    }
  },
  "bookSearchResultsSummaryTruncated": "僅顯示前 {shown} 筆，共 {total, plural, =1{1 筆結果} other{{total} 筆結果}}",
  "@bookSearchResultsSummaryTruncated": {
    "description": "單書內容搜尋結果數量摘要（截斷情境），{shown} 為目前清單實際渲染的筆數（呼叫端傳入 result.matches.length），{total} 為該書全部命中筆數（result.totalMatches）",
    "placeholders": {
      "shown": {
        "type": "int"
      },
      "total": {
        "type": "int"
      }
    }
  },
  "bookSearchSortByPosition": "依書中順序",
  "@bookSearchSortByPosition": {
    "description": "單書內容搜尋結果排序切換按鈕：依書中出現順序"
  },
  "bookSearchSortByRelevance": "依相關度排序",
  "@bookSearchSortByRelevance": {
    "description": "單書內容搜尋結果排序切換按鈕：依相關度"
  },
  "fullTextSearchNoContentMatches": "查無符合的書內內容",
  "@fullTextSearchNoContentMatches": {
    "description": "全文檢索已啟用但查無結果時的提示，book_search_screen.dart／library_search_screen.dart 共用"
  },
  "bookSearchLocationPage": "第 {page} 頁",
  "@bookSearchLocationPage": {
    "description": "PDF 搜尋結果片段的位置標籤，{page} 為頁碼（1-based）",
    "placeholders": {
      "page": {
        "type": "int"
      }
    }
  },
  "bookSearchLocationChapter": "第 {chapter} 章",
  "@bookSearchLocationChapter": {
    "description": "非 PDF 格式搜尋結果片段的位置標籤，{chapter} 為章節序號（1-based）",
    "placeholders": {
      "chapter": {
        "type": "int"
      }
    }
  }
```

`app_zh_CN.arb` 檔尾新增：

```json
  "bookSearchHint": "在本书中搜索...",
  "searchClearTooltip": "清除",
  "fullTextSearchUnavailableMessage": "本设备不支持全文检索",
  "bookSearchResultsSummary": "{total, plural, =1{共 1 条结果} other{共 {total} 条结果}}",
  "bookSearchResultsSummaryTruncated": "仅显示前 {shown} 条，共 {total, plural, =1{1 条结果} other{{total} 条结果}}",
  "bookSearchSortByPosition": "依书中顺序",
  "bookSearchSortByRelevance": "按相关度排序",
  "fullTextSearchNoContentMatches": "未找到符合的书内内容",
  "bookSearchLocationPage": "第 {page} 页",
  "bookSearchLocationChapter": "第 {chapter} 章"
```

`app_en.arb` 檔尾新增：

```json
  "bookSearchHint": "Search in this book...",
  "searchClearTooltip": "Clear",
  "fullTextSearchUnavailableMessage": "Full-text search is not supported on this device",
  "bookSearchResultsSummary": "{total, plural, =1{1 result} other{{total} results}}",
  "bookSearchResultsSummaryTruncated": "Showing first {shown} of {total, plural, =1{1 result} other{{total} results}}",
  "bookSearchSortByPosition": "By book order",
  "bookSearchSortByRelevance": "By relevance",
  "fullTextSearchNoContentMatches": "No matching content found",
  "bookSearchLocationPage": "Page {page}",
  "bookSearchLocationChapter": "Chapter {chapter}"
```

`app_zh.arb` 檔尾新增：

```json
  "bookSearchHint": "在本書中搜尋...",
  "searchClearTooltip": "清除",
  "fullTextSearchUnavailableMessage": "本裝置不支援全文檢索",
  "bookSearchResultsSummary": "{total, plural, =1{共 1 筆結果} other{共 {total} 筆結果}}",
  "bookSearchResultsSummaryTruncated": "僅顯示前 {shown} 筆，共 {total, plural, =1{1 筆結果} other{{total} 筆結果}}",
  "bookSearchSortByPosition": "依書中順序",
  "bookSearchSortByRelevance": "依相關度排序",
  "fullTextSearchNoContentMatches": "查無符合的書內內容",
  "bookSearchLocationPage": "第 {page} 頁",
  "bookSearchLocationChapter": "第 {chapter} 章"
```

- [ ] **Step 2: 執行 `flutter gen-l10n`**

Run: `flutter gen-l10n`
Expected: 無錯誤。

- [ ] **Step 3: 修改 `book_search_screen.dart` `build()`／`_buildToolbar()`／`_buildResults()`／`_buildSnippetTile()`**

修改 `app/lib/screens/book_search_screen.dart`（僅列出需要異動的方法，檔案其餘部分——`_BookSearchScreenState` 的欄位/`initState`/`_handleQueryChanged`/`_toggleSort`/`_handleSnippetTap`/`_buildHighlightedText` 等——原樣保留不動）：

首先在檔案頂部 import 區塊新增：
```dart
import '../l10n/app_localizations.dart';
```

`build()` 方法：
```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          convertText(widget.book.title, _titleTextConversion),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          // 搜尋輸入框
          Padding(
            padding: const EdgeInsets.all(12),
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final hasText = _controller.text.isNotEmpty;
                return TextField(
                  key: const Key('book_search_screen_field'),
                  controller: _controller,
                  focusNode: _searchFocusNode,
                  autofocus: false,
                  onChanged: _handleQueryChanged,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: l10n.bookSearchHint,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: hasText
                        ? IconButton(
                            key: const Key('book_search_screen_clear_button'),
                            icon: const Icon(Icons.close),
                            tooltip: l10n.searchClearTooltip,
                            onPressed: () {
                              _controller.clear();
                              _handleQueryChanged('');
                            },
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
          // 不支援提示或工具列
          if (!widget.readerFeatureRepositories.isFullTextSearchAvailable)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.fullTextSearchUnavailableMessage),
            )
          else ...[
            _buildToolbar(),
            // 結果清單
            Expanded(child: _buildResults()),
          ],
        ],
      ),
    );
  }
```

`_buildToolbar()` 方法：
```dart
  Widget _buildToolbar() {
    final result = _result;
    if (result == null || result.matches.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    final summaryText = result.isTruncated
        ? l10n.bookSearchResultsSummaryTruncated(
            result.matches.length,
            result.totalMatches,
          )
        : l10n.bookSearchResultsSummary(result.totalMatches);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          if (widget.book.author != null && widget.book.author!.isNotEmpty)
            Flexible(
              child: Text(
                convertText(widget.book.author!, _titleTextConversion),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(width: 8),
          Text(
            summaryText,
            key: const Key('book_search_summary'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          TextButton.icon(
            key: const Key('book_search_sort_toggle'),
            icon: Icon(
              _sortByBookOrder ? Icons.sort : Icons.trending_up,
              size: 18,
            ),
            label: Text(
              _sortByBookOrder
                  ? l10n.bookSearchSortByPosition
                  : l10n.bookSearchSortByRelevance,
            ),
            onPressed: _toggleSort,
          ),
        ],
      ),
    );
  }
```

`_buildResults()` 方法（只有其中一處 `Text('查無符合的書內內容')` 需要改）：
```dart
  Widget _buildResults() {
    final result = _result;
    if (result == null) return const SizedBox.shrink();
    if (result.matches.isEmpty) {
      return Center(
        child: Text(AppLocalizations.of(context)!.fullTextSearchNoContentMatches),
      );
    }

    final trimmedQuery = _controller.text.trim();
    final variants = queryVariants(trimmedQuery);
    final isPdf = widget.book.format == BookFileFormat.pdf;

    if (!widget.isEinkMode) {
      // 非 E-Ink：連續捲動
      return ListView.builder(
        itemCount: result.matches.length,
        itemBuilder: (context, index) => _buildSnippetTile(
          result.matches[index],
          index,
          variants,
          isPdf,
        ),
      );
    }

    // E-Ink 模式：離散分頁
    final pageCount = _pagingCursor.clamp(
      itemCount: result.matches.length,
      pageSize: _kEinkItemsPerPage,
    );
    final safePage = _pagingCursor.currentPage;
    final pageStart = safePage * _kEinkItemsPerPage;
    final pageEnd =
        (pageStart + _kEinkItemsPerPage).clamp(0, result.matches.length);

    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              for (var i = pageStart; i < pageEnd; i++)
                _buildSnippetTile(result.matches[i], i, variants, isPdf),
            ],
          ),
        ),
        PagingBar(
          key: const Key('book_search_paging_bar'),
          currentPage: safePage,
          pageCount: pageCount,
          onPrevious: safePage > 0
              ? () => setState(() => _pagingCursor.goToPreviousPage())
              : null,
          onNext: safePage < pageCount - 1
              ? () => setState(() => _pagingCursor.goToNextPage())
              : null,
          isEinkMode: widget.isEinkMode,
          keyPrefix: 'book_search_paging_bar',
        ),
      ],
    );
  }
```

`_buildSnippetTile()` 方法（`locationText` 改用 ARB key）：
```dart
  Widget _buildSnippetTile(
    ContentMatchSnippet snippet,
    int index,
    List<String> variants,
    bool isPdf,
  ) {
    // 位置標籤：PDF「第 X 頁」，其餘「第 X 章」（chapterIndex 為 0-based）。
    final chapterIndex = snippet.chapterIndex;
    final l10n = AppLocalizations.of(context)!;
    final locationText = chapterIndex != null
        ? (isPdf
            ? l10n.bookSearchLocationPage(chapterIndex + 1)
            : l10n.bookSearchLocationChapter(chapterIndex + 1))
        : null;
    final displaySnippet = convertText(snippet.snippet, _contentTextConversion);

    return ListTile(
      key: Key('book_search_snippet_$index'),
      dense: true,
      title: _buildHighlightedText(displaySnippet, variants),
      subtitle: locationText != null ? Text(locationText) : null,
      onTap: () => _handleSnippetTap(snippet),
    );
  }
```

- [ ] **Step 4: 遷移既有測試檔至含 `AppLocalizations` 的 `_wrap()`**

修改 `app/test/screens/book_search_screen_test.dart` 開頭的 import 與 `_wrap()`：

```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```
（加在既有 import 區塊，與其他 `package:elinkbook/...` import 排在一起）

```dart
Widget _wrap(Widget child, {Locale locale = const Locale('zh', 'TW')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: child,
    );
```

檔案其餘 18 處 `_wrap(...)` 呼叫端與既有 `testWidgets` 內容不變（預設 `locale` 為 `zh_TW`，既有中文斷言不受影響）。

- [ ] **Step 5: 新增三語言渲染驗證測試**

在 `app/test/screens/book_search_screen_test.dart` 檔尾 `main()` 最後一個 `testWidgets` 之後新增（需要先確認檔案內既有一個可重用的 `BookSearchDetailResult`／`FakeSearchRepository` 建構模式，直接沿用該檔案既有的 fixture 建構函式 `_testBook()`／`_makeResult()`）：

```dart
  testWidgets('英文介面下搜尋提示、排序按鈕、位置標籤正確以英文渲染', (tester) async {
    final book = _testBook();
    final searchRepository = FakeSearchRepository(
      bookSearchResult: _makeResult(book: book, matchCount: 2, totalMatches: 2),
    );
    await tester.pumpWidget(
      _wrap(
        BookSearchScreen(
          book: book,
          initialQuery: '關鍵字',
          searchRepository: searchRepository,
          prefsManager: FakeReaderPrefsManager(),
          libraryRepository: FakeLibraryRepository(),
          readerFeatureRepositories: const LibraryReaderFeatureRepositories(),
          syncDependencies: const LibrarySyncDependencies(),
          isEinkMode: false,
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Search in this book...'), findsOneWidget);
    expect(find.textContaining('results'), findsOneWidget);
    expect(find.text('By relevance'), findsOneWidget);
  });
```

> 若上述 fixture 建構參數（`LibraryReaderFeatureRepositories`／`LibrarySyncDependencies` 建構子欄位、`FakeSearchRepository` 建構參數名）與檔案既有寫法不完全一致，以該測試檔案中其他既有 `testWidgets` 實際使用的建構寫法為準（本 Step 的重點是「新增一則英文渲染驗證」，具體 fixture 組裝請對照同檔案其他測試）。

- [ ] **Step 6: 執行測試確認全數通過**

Run:
```bash
flutter test test/screens/book_search_screen_test.dart
```
Expected: 全數通過（既有測試＋新增 1 個）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run:
```bash
flutter analyze lib/screens/book_search_screen.dart test/screens/book_search_screen_test.dart
```
Expected: No issues found!

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/book_search_screen.dart app/test/screens/book_search_screen_test.dart app/lib/l10n/
git commit -m "feat(epic-45): book_search_screen.dart 字串抽取三語言在地化"
```

---

### Task 4: `library_search_screen.dart`

**Files:**
- Modify: `app/lib/screens/library_search_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/library_search_screen_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`；Task 2 定義的 `cancel`（間接，透過 `showFullTextSearchEnableConfirmDialog()`）；Task 3 定義的 `searchClearTooltip`/`fullTextSearchUnavailableMessage`/`fullTextSearchNoContentMatches`（直接重用，不重新定義）。
- Produces：ARB key `librarySearchSettingsSheetTitle`/`librarySearchScreenTitle`/`librarySearchSettingsTooltip`/`librarySearchFieldHint`/`librarySearchTitleAuthorSectionHeader`/`librarySearchContentSectionHeader`/`librarySearchGuidanceNotEnabled`/`librarySearchGuidancePdfOnly`/`librarySearchGuidanceOtherOnly`/`librarySearchDrillDownButton`/`librarySearchPdfToggleTitle`/`librarySearchPdfToggleSubtitle`/`librarySearchRebuildIndexTooltip`/`librarySearchFoliateToggleTitle`/`librarySearchFoliateToggleSubtitle`。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 檔尾新增：

```json
  "librarySearchSettingsSheetTitle": "全文檢索設定",
  "@librarySearchSettingsSheetTitle": {
    "description": "書內搜尋畫面 AppBar「全文檢索設定」入口彈出的 EBSheetShell 標題"
  },
  "librarySearchScreenTitle": "搜尋書內內容",
  "@librarySearchScreenTitle": {
    "description": "全庫內容搜尋畫面的 AppBar 標題"
  },
  "librarySearchSettingsTooltip": "全文檢索設定",
  "@librarySearchSettingsTooltip": {
    "description": "全庫內容搜尋畫面 AppBar 設定圖示的無障礙提示文字"
  },
  "librarySearchFieldHint": "搜尋書名、作者或書本內容...",
  "@librarySearchFieldHint": {
    "description": "全庫內容搜尋畫面輸入框的 hintText"
  },
  "librarySearchTitleAuthorSectionHeader": "書名/作者匹配",
  "@librarySearchTitleAuthorSectionHeader": {
    "description": "全庫內容搜尋結果「書名/作者匹配」分區標題"
  },
  "librarySearchContentSectionHeader": "內容匹配",
  "@librarySearchContentSectionHeader": {
    "description": "全庫內容搜尋結果「內容匹配」分區標題"
  },
  "librarySearchGuidanceNotEnabled": "尚未啟用全文檢索，開啟後才能搜尋書本內容（點擊右上角設定圖示開啟）",
  "@librarySearchGuidanceNotEnabled": {
    "description": "PDF／其他格式全文檢索皆未啟用時的引導卡片文字"
  },
  "librarySearchGuidancePdfOnly": "已啟用「PDF」全文檢索，其他格式尚未啟用",
  "@librarySearchGuidancePdfOnly": {
    "description": "僅 PDF 全文檢索已啟用時的引導卡片文字"
  },
  "librarySearchGuidanceOtherOnly": "已啟用「其他格式」全文檢索，PDF 內容尚未啟用",
  "@librarySearchGuidanceOtherOnly": {
    "description": "僅其他格式全文檢索已啟用時的引導卡片文字"
  },
  "librarySearchDrillDownButton": "{total, plural, =1{查看全部 1 筆結果} other{查看全部 {total} 筆結果}}（{remaining, plural, =1{還有 1 筆} other{還有 {remaining} 筆}}）",
  "@librarySearchDrillDownButton": {
    "description": "內容匹配卡片「查看全部」下鑽按鈕文字，{total} 為該書總命中數，{remaining} 為清單未顯示的剩餘筆數",
    "placeholders": {
      "total": {
        "type": "int"
      },
      "remaining": {
        "type": "int"
      }
    }
  },
  "librarySearchPdfToggleTitle": "PDF 全文檢索",
  "@librarySearchPdfToggleTitle": {
    "description": "全文檢索設定面板 PDF 開關項目標題"
  },
  "librarySearchPdfToggleSubtitle": "部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容",
  "@librarySearchPdfToggleSubtitle": {
    "description": "全文檢索設定面板 PDF 開關項目副標題"
  },
  "librarySearchRebuildIndexTooltip": "重建索引",
  "@librarySearchRebuildIndexTooltip": {
    "description": "全文檢索設定面板「重建索引」按鈕的無障礙提示文字，PDF／其他格式兩個開關項目共用"
  },
  "librarySearchFoliateToggleTitle": "其他格式全文檢索",
  "@librarySearchFoliateToggleTitle": {
    "description": "全文檢索設定面板「其他格式」開關項目標題"
  },
  "librarySearchFoliateToggleSubtitle": "EPUB／TXT／KF8 等格式的背景索引建置",
  "@librarySearchFoliateToggleSubtitle": {
    "description": "全文檢索設定面板「其他格式」開關項目副標題"
  }
```

`app_zh_CN.arb` 檔尾新增：

```json
  "librarySearchSettingsSheetTitle": "全文检索设置",
  "librarySearchScreenTitle": "搜索书内内容",
  "librarySearchSettingsTooltip": "全文检索设置",
  "librarySearchFieldHint": "搜索书名、作者或书本内容...",
  "librarySearchTitleAuthorSectionHeader": "书名/作者匹配",
  "librarySearchContentSectionHeader": "内容匹配",
  "librarySearchGuidanceNotEnabled": "尚未启用全文检索，开启后才能搜索书本内容（点击右上角设置图标开启）",
  "librarySearchGuidancePdfOnly": "已启用「PDF」全文检索，其他格式尚未启用",
  "librarySearchGuidanceOtherOnly": "已启用「其他格式」全文检索，PDF 内容尚未启用",
  "librarySearchDrillDownButton": "{total, plural, =1{查看全部 1 条结果} other{查看全部 {total} 条结果}}（{remaining, plural, =1{还有 1 条} other{还有 {remaining} 条}}）",
  "librarySearchPdfToggleTitle": "PDF 全文检索",
  "librarySearchPdfToggleSubtitle": "部分扫描/图片型 PDF 可能没有可搜索的文字内容",
  "librarySearchRebuildIndexTooltip": "重建索引",
  "librarySearchFoliateToggleTitle": "其他格式全文检索",
  "librarySearchFoliateToggleSubtitle": "EPUB／TXT／KF8 等格式的后台索引建立"
```

`app_en.arb` 檔尾新增：

```json
  "librarySearchSettingsSheetTitle": "Full-Text Search Settings",
  "librarySearchScreenTitle": "Search Book Content",
  "librarySearchSettingsTooltip": "Full-Text Search Settings",
  "librarySearchFieldHint": "Search by title, author, or content...",
  "librarySearchTitleAuthorSectionHeader": "Title/Author Matches",
  "librarySearchContentSectionHeader": "Content Matches",
  "librarySearchGuidanceNotEnabled": "Full-text search is not enabled yet. Enable it to search book content (tap the settings icon in the top right).",
  "librarySearchGuidancePdfOnly": "\"PDF\" full-text search is enabled; other formats are not yet enabled",
  "librarySearchGuidanceOtherOnly": "\"Other formats\" full-text search is enabled; PDF content is not yet enabled",
  "librarySearchDrillDownButton": "{total, plural, =1{View all 1 result} other{View all {total} results}} ({remaining, plural, =1{1 more} other{{remaining} more}})",
  "librarySearchPdfToggleTitle": "PDF Full-Text Search",
  "librarySearchPdfToggleSubtitle": "Some scanned/image-based PDFs may not have searchable text",
  "librarySearchRebuildIndexTooltip": "Rebuild Index",
  "librarySearchFoliateToggleTitle": "Other Formats Full-Text Search",
  "librarySearchFoliateToggleSubtitle": "Background indexing for EPUB, TXT, KF8, and other formats"
```

`app_zh.arb` 檔尾新增：

```json
  "librarySearchSettingsSheetTitle": "全文檢索設定",
  "librarySearchScreenTitle": "搜尋書內內容",
  "librarySearchSettingsTooltip": "全文檢索設定",
  "librarySearchFieldHint": "搜尋書名、作者或書本內容...",
  "librarySearchTitleAuthorSectionHeader": "書名/作者匹配",
  "librarySearchContentSectionHeader": "內容匹配",
  "librarySearchGuidanceNotEnabled": "尚未啟用全文檢索，開啟後才能搜尋書本內容（點擊右上角設定圖示開啟）",
  "librarySearchGuidancePdfOnly": "已啟用「PDF」全文檢索，其他格式尚未啟用",
  "librarySearchGuidanceOtherOnly": "已啟用「其他格式」全文檢索，PDF 內容尚未啟用",
  "librarySearchDrillDownButton": "{total, plural, =1{查看全部 1 筆結果} other{查看全部 {total} 筆結果}}（{remaining, plural, =1{還有 1 筆} other{還有 {remaining} 筆}}）",
  "librarySearchPdfToggleTitle": "PDF 全文檢索",
  "librarySearchPdfToggleSubtitle": "部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容",
  "librarySearchRebuildIndexTooltip": "重建索引",
  "librarySearchFoliateToggleTitle": "其他格式全文檢索",
  "librarySearchFoliateToggleSubtitle": "EPUB／TXT／KF8 等格式的背景索引建置"
```

- [ ] **Step 2: 執行 `flutter gen-l10n`**

Run: `flutter gen-l10n`
Expected: 無錯誤。

- [ ] **Step 3: 修改 `library_search_screen.dart`**

在 import 區塊新增：
```dart
import '../l10n/app_localizations.dart';
```

`_openQuickSettingsSheet()`：
```dart
  Future<void> _openQuickSettingsSheet() async {
    await EBSheetShell.show<void>(
      context,
      title: AppLocalizations.of(context)!.librarySearchSettingsSheetTitle,
      isEinkMode: widget.isEinkMode,
      builder: (context) => _FullTextSearchQuickSettingsPanel(
        repository:
            widget.readerFeatureRepositories.fullTextSearchSettingsRepository,
        isFullTextSearchAvailable:
            widget.readerFeatureRepositories.isFullTextSearchAvailable,
        isEinkMode: widget.isEinkMode,
      ),
    );
    // ...（其餘邏輯不變）
    await _loadFullTextSearchSettings();
    final trimmedQuery = _controller.text.trim();
    if (trimmedQuery.isNotEmpty) {
      await _runSearch(trimmedQuery);
    }
  }
```

`build()`：
```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final trimmedQuery = _controller.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.librarySearchScreenTitle),
        actions: [
          IconButton(
            key: const Key('library_search_screen_settings_button'),
            icon: const Icon(Icons.settings),
            tooltip: l10n.librarySearchSettingsTooltip,
            onPressed: _openQuickSettingsSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final hasText = _controller.text.isNotEmpty;
                return TextField(
                  key: const Key('library_search_screen_field'),
                  controller: _controller,
                  focusNode: _searchFocusNode,
                  autofocus: true,
                  onChanged: _handleQueryChanged,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: l10n.librarySearchFieldHint,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: hasText
                        ? IconButton(
                            key: const Key(
                                'library_search_screen_clear_button'),
                            icon: const Icon(Icons.close),
                            tooltip: l10n.searchClearTooltip,
                            onPressed: () {
                              _controller.clear();
                              _handleQueryChanged('');
                            },
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
          Expanded(child: _buildResults(trimmedQuery)),
        ],
      ),
    );
  }
```

`_buildResults()`：
```dart
  Widget _buildResults(String trimmedQuery) {
    if (trimmedQuery.isEmpty) return const SizedBox.shrink();
    final titleAuthorResults = _titleAuthorResults;
    final contentResults = _contentResults;
    if (titleAuthorResults == null || contentResults == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      children: [
        if (titleAuthorResults.isNotEmpty) ...[
          EBSectionHeader(title: l10n.librarySearchTitleAuthorSectionHeader),
          ..._buildSection<Book>(
            items: titleAuthorResults,
            paging: _titleAuthorPaging,
            itemBuilder: _buildTitleAuthorTile,
            pagingBarKey: 'library_search_title_author_paging_bar',
          ),
        ],
        EBSectionHeader(title: l10n.librarySearchContentSectionHeader),
        if (contentResults.isEmpty)
          _buildContentGuidanceCard()
        else
          ..._buildSection<BookContentMatches>(
            items: contentResults,
            paging: _contentPaging,
            itemBuilder: _buildContentGroupCard,
            pagingBarKey: 'library_search_content_paging_bar',
          ),
      ],
    );
  }
```

> **審查澄清（`review-plan-issue-3.md` I-2，查證：程式碼原已正確，非缺陷）**：上方兩處 `EBSectionHeader(title: l10n.xxx)` 呼叫皆**不帶** `const`——既有程式碼原為 `const EBSectionHeader(title: '書名/作者匹配')` 字面值常數，`l10n.librarySearchTitleAuthorSectionHeader`／`l10n.librarySearchContentSectionHeader` 是執行期動態值，帶 `const` 會被 Dart 編譯器直接拒絕（`Invalid constant value`）。實作時務必確認這兩行沒有殘留原本的 `const` 關鍵字。

`_buildContentGroupCard()`（下鑽按鈕）：
```dart
          if (group.totalMatches > group.matches.length)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Center(
                child: TextButton(
                  key: Key('library_search_drill_down_${group.book.id}'),
                  onPressed: () => _openBookSearch(group.book),
                  child: Text(
                    AppLocalizations.of(context)!.librarySearchDrillDownButton(
                      group.totalMatches,
                      group.totalMatches - group.matches.length,
                    ),
                  ),
                ),
              ),
            ),
```
（此段落取代原本 `Text('查看全部 ${group.totalMatches} 筆結果（還有 ${group.totalMatches - group.matches.length} 筆）')`，`_buildContentGroupCard()` 其餘結構不變。）

`_buildContentGuidanceCard()`／`_guidanceMessage()`：
```dart
  Widget _buildContentGuidanceCard() {
    final l10n = AppLocalizations.of(context)!;
    if (!widget.readerFeatureRepositories.isFullTextSearchAvailable) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(l10n.fullTextSearchUnavailableMessage),
      );
    }
    if (_pdfEnabled && _foliateEnabled) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(l10n.fullTextSearchNoContentMatches),
      );
    }
    return EBFieldCard(
      key: const Key('library_search_content_guidance_card'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(_guidanceMessage(l10n)),
    );
  }

  String _guidanceMessage(AppLocalizations l10n) {
    if (!_pdfEnabled && !_foliateEnabled) {
      return l10n.librarySearchGuidanceNotEnabled;
    }
    if (_pdfEnabled) {
      return l10n.librarySearchGuidancePdfOnly;
    }
    return l10n.librarySearchGuidanceOtherOnly;
  }
```

`_FullTextSearchQuickSettingsPanelState.build()`：
```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!widget.isFullTextSearchAvailable) {
      return Padding(
        key: const Key('library_search_full_text_search_unavailable_hint'),
        padding: const EdgeInsets.all(16),
        child: Text(l10n.fullTextSearchUnavailableMessage),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(l10n.librarySearchPdfToggleTitle),
            subtitle: Text(l10n.librarySearchPdfToggleSubtitle),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key(
                      'library_search_full_text_search_pdf_rebuild_button'),
                  icon: const Icon(Icons.refresh),
                  tooltip: l10n.librarySearchRebuildIndexTooltip,
                  onPressed:
                      !_controller.pdfEnabled || widget.repository == null
                          ? null
                          : () => widget.repository!
                              .rebuildIndex(ContentIndexCategory.pdf),
                ),
                Switch(
                  key: const Key('library_search_full_text_search_pdf_switch'),
                  value: _controller.pdfEnabled,
                  onChanged: widget.repository == null
                      ? null
                      : (value) =>
                          _handleToggle(ContentIndexCategory.pdf, value),
                ),
              ],
            ),
          ),
          ListTile(
            title: Text(l10n.librarySearchFoliateToggleTitle),
            subtitle: Text(l10n.librarySearchFoliateToggleSubtitle),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key(
                      'library_search_full_text_search_foliate_rebuild_button'),
                  icon: const Icon(Icons.refresh),
                  tooltip: l10n.librarySearchRebuildIndexTooltip,
                  onPressed:
                      !_controller.foliateEnabled || widget.repository == null
                          ? null
                          : () => widget.repository!
                              .rebuildIndex(ContentIndexCategory.foliate),
                ),
                Switch(
                  key: const Key(
                      'library_search_full_text_search_foliate_switch'),
                  value: _controller.foliateEnabled,
                  onChanged: widget.repository == null
                      ? null
                      : (value) =>
                          _handleToggle(ContentIndexCategory.foliate, value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
```

> `EBSectionHeader(title: '...')` 原本傳入 `const` 字面值字串，改傳動態 `l10n.xxx` 後該行不能再標 `const`——確認 `EBSectionHeader` 建構子本身沒有標記 `@required const` 限制（若 `flutter analyze` 在此報錯，移除誤留的 `const` 關鍵字即可）。

- [ ] **Step 4: 遷移既有測試檔至含 `AppLocalizations` 的 `wrap()`**

修改 `app/test/screens/library_search_screen_test.dart` 開頭新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

修改 `wrap()` helper：
```dart
  Widget wrap(Widget child, {Locale locale = const Locale('zh', 'TW')}) =>
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: child,
      );
```

檔案其餘 28 處 `wrap(...)` 呼叫端與既有 `testWidgets` 內容不變。

- [ ] **Step 5: 新增三語言渲染驗證測試**

在 `app/test/screens/library_search_screen_test.dart` 檔尾 `main()` 最後一個 `testWidgets` 之後新增：

```dart
  testWidgets('英文介面下 AppBar 標題、搜尋提示、分區標題正確以英文渲染', (tester) async {
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          searchRepository: FakeSearchRepository(
            titleAuthorResults: [_testBook(id: 'b1', title: 'Fantasy Book')],
          ),
          prefsManager: FakeReaderPrefsManager(),
          libraryRepository: FakeLibraryRepository(),
          initialQuery: 'fantasy',
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Search Book Content'), findsOneWidget);
    expect(find.text('Title/Author Matches'), findsOneWidget);
    expect(find.text('Content Matches'), findsOneWidget);
  });

  testWidgets('簡體中文介面下全文檢索設定面板文字正確以簡體渲染', (tester) async {
    await tester.pumpWidget(
      wrap(
        LibrarySearchScreen(
          searchRepository: FakeSearchRepository(),
          prefsManager: FakeReaderPrefsManager(),
          libraryRepository: FakeLibraryRepository(),
        ),
        locale: const Locale('zh', 'CN'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('library_search_screen_settings_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('PDF 全文检索'), findsOneWidget);
    expect(find.text('其他格式全文检索'), findsOneWidget);
  });
```

> 若 `FakeSearchRepository`／`_testBook()` 的建構參數名稱與上方範例不完全一致，以檔案內既有 `testWidgets` 的實際寫法為準（同 Task 3 Step 5 的提醒）。

- [ ] **Step 6: 執行測試確認全數通過**

Run:
```bash
flutter test test/screens/library_search_screen_test.dart
```
Expected: 全數通過（既有測試＋新增 2 個）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run:
```bash
flutter analyze lib/screens/library_search_screen.dart test/screens/library_search_screen_test.dart
```
Expected: No issues found!

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/library_search_screen.dart app/test/screens/library_search_screen_test.dart app/lib/l10n/
git commit -m "feat(epic-45): library_search_screen.dart 字串抽取三語言在地化"
```

---

### Task 5: `library_screen.dart`（production code）

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`；`cancel`（Issue 2 已建立）；`BookGroup`（`app/lib/library/models/book_group.dart`，不呼叫 `localizeGroupName()`——見 Global Constraints 說明）。
- Produces：Task 6（`library_screen_test.dart` 遷移）依賴本 Task 完成後 `LibraryScreen` 全面改用 `AppLocalizations.of(context)!` 這個事實（這正是 Task 6 需要把全部 113 處裸 `MaterialApp` 遷移至 `pumpLocalizedWidget()` 的原因）；ARB key 清單見下方 Step 1（共 53 個新 key）。

**本 Task 不修改任何測試檔**——`library_screen_test.dart` 的遷移獨立成 Task 6（下一個 Task），讓「production 字串抽取是否正確」與「測試遷移是否完整」成為兩個獨立的審查關卡。**本 Task 完成後、Task 6 執行前，`flutter test test/screens/library_screen_test.dart` 預期大量失敗（`Null check operator used on a null value`，因為裸 `MaterialApp` 尚未遷移）——這是預期中的紅燈狀態，不是本 Task 的回歸，Step 5 會明確驗證這個狀態。**

- [ ] **Step 1: 新增 ARB key（四語言，53 個 key）**

`app_zh_TW.arb` 檔尾新增（依畫面區塊分組，方便核對）：

```json
  "libraryBackButtonTooltip": "返回上層",
  "@libraryBackButtonTooltip": {
    "description": "下鑽分類檢視時 AppBar 返回按鈕的無障礙提示文字"
  },
  "libraryShelfTitle": "書架",
  "@libraryShelfTitle": {
    "description": "書架頂層（未下鑽任何分類）AppBar 標題"
  },
  "librarySortViewTooltip": "排序與檢視",
  "@librarySortViewTooltip": {
    "description": "AppBar 排序/檢視選單按鈕的無障礙提示文字"
  },
  "librarySortByLastRead": "最後閱讀",
  "@librarySortByLastRead": {
    "description": "排序選單選項：依最後閱讀時間"
  },
  "librarySortByCreateTime": "建立時間",
  "@librarySortByCreateTime": {
    "description": "排序選單選項：依建立時間"
  },
  "librarySortByAuthor": "作者",
  "@librarySortByAuthor": {
    "description": "排序選單選項：依作者"
  },
  "librarySortByTitle": "書名",
  "@librarySortByTitle": {
    "description": "排序選單選項：依書名"
  },
  "libraryToggleViewToList": "切換為列表",
  "@libraryToggleViewToList": {
    "description": "排序選單「切換檢視模式」項目文字（目前為格狀時顯示，點擊後切換為列表）"
  },
  "libraryToggleViewToShelf": "切換為書架",
  "@libraryToggleViewToShelf": {
    "description": "排序選單「切換檢視模式」項目文字（目前為列表時顯示，點擊後切換為格狀）"
  },
  "libraryManageGroupsMenuItem": "管理分類...",
  "@libraryManageGroupsMenuItem": {
    "description": "排序選單「管理分類」項目文字（僅頂層書架顯示，下鑽分類時不顯示）"
  },
  "librarySourceTooltip": "來源",
  "@librarySourceTooltip": {
    "description": "AppBar「來源」圖示按鈕的無障礙提示文字"
  },
  "librarySettingsTooltip": "設定",
  "@librarySettingsTooltip": {
    "description": "AppBar「設定」圖示按鈕的無障礙提示文字"
  },
  "libraryCancelSelectionTooltip": "取消選取",
  "@libraryCancelSelectionTooltip": {
    "description": "選取模式 AppBar「✕」取消按鈕的無障礙提示文字"
  },
  "librarySelectedCount": "{count, plural, =1{已選取 1 本} other{已選取 {count} 本}}",
  "@librarySelectedCount": {
    "description": "選取模式 AppBar 標題，{count} 為目前已選取的書籍數",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "libraryMoveToGroupTooltip": "移動到分類",
  "@libraryMoveToGroupTooltip": {
    "description": "選取模式 AppBar「移動到分類」圖示按鈕的無障礙提示文字"
  },
  "libraryForceFxlTooltip": "強制 FXL",
  "@libraryForceFxlTooltip": {
    "description": "選取模式 AppBar「強制 FXL」圖示按鈕的無障礙提示文字"
  },
  "libraryRestoreAutoLayoutTooltip": "恢復自動判斷",
  "@libraryRestoreAutoLayoutTooltip": {
    "description": "選取模式 AppBar「恢復自動判斷」圖示按鈕的無障礙提示文字"
  },
  "libraryDeleteTooltip": "刪除",
  "@libraryDeleteTooltip": {
    "description": "選取模式 AppBar「刪除」圖示按鈕的無障礙提示文字"
  },
  "libraryRemoveLocalCacheTooltip": "移除本機快取",
  "@libraryRemoveLocalCacheTooltip": {
    "description": "選取模式 AppBar「移除本機快取」圖示按鈕的無障礙提示文字，同時作為單書移除快取確認對話框標題（文字完全相同）"
  },
  "libraryEmptyStateMessage": "尚未匯入書籍",
  "@libraryEmptyStateMessage": {
    "description": "書架無任何書籍時的空狀態提示文字"
  },
  "libraryEmptyStateImportButton": "匯入書籍",
  "@libraryEmptyStateImportButton": {
    "description": "空狀態「匯入書籍」按鈕文字"
  },
  "librarySearchHint": "搜尋書名或作者...",
  "@librarySearchHint": {
    "description": "書架常駐搜尋列輸入框的 hintText"
  },
  "libraryContentSearchEntryLabel": "搜尋書本內容",
  "@libraryContentSearchEntryLabel": {
    "description": "書架搜尋列下方「搜尋書本內容」導覽橫幅文字"
  },
  "libraryNoMatchingBooks": "找不到符合的書籍",
  "@libraryNoMatchingBooks": {
    "description": "書架快速搜尋（書名/作者）查無結果時的提示文字"
  },
  "libraryDeleteBooksDialogTitle": "刪除書籍",
  "@libraryDeleteBooksDialogTitle": {
    "description": "刪除書籍確認對話框標題（單書／批次共用）"
  },
  "libraryDeleteBooksConfirmMessage": "{count, plural, =1{將刪除已選取的 1 本書籍，並一併刪除其書籤、劃線與備註，此操作無法復原。確定要刪除嗎？} other{將刪除已選取的 {count} 本書籍，並一併刪除其書籤、劃線與備註，此操作無法復原。確定要刪除嗎？}}",
  "@libraryDeleteBooksConfirmMessage": {
    "description": "刪除書籍確認對話框內容，{count} 為將被刪除的書籍數（單書刪除時為 1）",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "libraryDeleteBooksConfirmButton": "刪除",
  "@libraryDeleteBooksConfirmButton": {
    "description": "刪除書籍確認對話框的「刪除」按鈕文字"
  },
  "libraryRedownloadAction": "重新下載",
  "@libraryRedownloadAction": {
    "description": "重新下載確認對話框的標題與確認按鈕（兩處文字完全相同，共用一個 key）"
  },
  "libraryRedownloadConfirmMessage": "即將重新下載「{title}」，確定要繼續嗎？",
  "@libraryRedownloadConfirmMessage": {
    "description": "重新下載確認訊息（非行動數據連線情境），{title} 為書名",
    "placeholders": {
      "title": {
        "type": "String"
      }
    }
  },
  "libraryRedownloadConfirmMessageMobileData": "即將重新下載「{title}」，目前使用行動數據連線，可能產生流量費用，確定要繼續嗎？",
  "@libraryRedownloadConfirmMessageMobileData": {
    "description": "重新下載確認訊息（行動數據連線情境），{title} 為書名",
    "placeholders": {
      "title": {
        "type": "String"
      }
    }
  },
  "libraryRemoteDisabledMessage": "遠端書庫功能未啟用，無法重新下載",
  "@libraryRemoteDisabledMessage": {
    "description": "遠端書庫依賴未提供時，點擊重新下載顯示的 SnackBar 訊息"
  },
  "libraryRemoteServerNotFoundMessage": "找不到對應的遠端書庫站點",
  "@libraryRemoteServerNotFoundMessage": {
    "description": "重新下載時找不到書籍對應的遠端站點設定，顯示的 SnackBar 訊息"
  },
  "libraryRedownloadFailedMessage": "重新下載失敗，請稍後再試",
  "@libraryRedownloadFailedMessage": {
    "description": "重新下載過程發生例外時顯示的 SnackBar 訊息"
  },
  "libraryRemoveCacheConfirmMessage": "將移除「{title}」的本機檔案，書籍紀錄與閱讀進度會保留，之後可重新下載。確定要移除嗎？",
  "@libraryRemoveCacheConfirmMessage": {
    "description": "移除本機快取確認對話框內容，{title} 為書名",
    "placeholders": {
      "title": {
        "type": "String"
      }
    }
  },
  "libraryRemoveCacheConfirmButton": "移除",
  "@libraryRemoveCacheConfirmButton": {
    "description": "移除本機快取確認對話框的「移除」按鈕文字"
  },
  "libraryGroupBadgeLabel": "分類",
  "@libraryGroupBadgeLabel": {
    "description": "分類拼貼格（格狀檢視）左上角角標文字"
  },
  "libraryGroupTileCount": "{count, plural, =1{1 本} other{{count} 本}}",
  "@libraryGroupTileCount": {
    "description": "分類拼貼格顯示的書籍數量，{count} 為該分類書籍總數",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "libraryBookMenuTooltip": "更多",
  "@libraryBookMenuTooltip": {
    "description": "書籍格/列項目「⋮」動作選單按鈕的無障礙提示文字（格狀／列表檢視共用）"
  },
  "libraryContinueReadingLabel": "繼續閱讀",
  "@libraryContinueReadingLabel": {
    "description": "書架頂部常駐「繼續閱讀列」的小標籤文字"
  },
  "libraryBookNotDownloaded": "尚未下載",
  "@libraryBookNotDownloaded": {
    "description": "書籍詳細資料對話框「檔案大小」欄位在書籍尚未下載時顯示"
  },
  "libraryUnknownFileSize": "未知大小",
  "@libraryUnknownFileSize": {
    "description": "書籍詳細資料對話框「檔案大小」欄位在檔案不存在/讀取失敗/發生例外時的回退顯示"
  },
  "libraryLoadingEllipsis": "讀取中...",
  "@libraryLoadingEllipsis": {
    "description": "書籍詳細資料對話框「檔案大小」欄位在 FutureBuilder 尚未回傳結果時顯示"
  },
  "libraryDetailAuthorLabel": "作者：{author}",
  "@libraryDetailAuthorLabel": {
    "description": "書籍詳細資料對話框「作者」欄位，{author} 為已解析的作者顯示文字（含 libraryUnknownAuthor 回退與簡繁轉換結果）",
    "placeholders": {
      "author": {
        "type": "String"
      }
    }
  },
  "libraryUnknownAuthor": "未知",
  "@libraryUnknownAuthor": {
    "description": "書籍作者欄位為 null 時的回退文字，供組進 libraryDetailAuthorLabel 的 {author} placeholder"
  },
  "libraryDetailFormatLabel": "格式：{format}",
  "@libraryDetailFormatLabel": {
    "description": "書籍詳細資料對話框「格式」欄位，{format} 為格式名稱（epub/pdf 等，不翻譯）",
    "placeholders": {
      "format": {
        "type": "String"
      }
    }
  },
  "libraryDetailFileSizeLabel": "檔案大小：{size}",
  "@libraryDetailFileSizeLabel": {
    "description": "書籍詳細資料對話框「檔案大小」欄位，{size} 為已格式化的大小文字或上述三種回退文字之一",
    "placeholders": {
      "size": {
        "type": "String"
      }
    }
  },
  "libraryDetailProgressLabel": "進度：{progress}",
  "@libraryDetailProgressLabel": {
    "description": "書籍詳細資料對話框「進度」欄位，{progress} 為百分比字串（如 50%，不需翻譯）",
    "placeholders": {
      "progress": {
        "type": "String"
      }
    }
  },
  "libraryDetailLastReadLabel": "最後閱讀：{date}",
  "@libraryDetailLastReadLabel": {
    "description": "書籍詳細資料對話框「最後閱讀」欄位，{date} 為已依 DateFormat 格式化的日期字串或 libraryNeverRead",
    "placeholders": {
      "date": {
        "type": "String"
      }
    }
  },
  "libraryNeverRead": "尚未閱讀",
  "@libraryNeverRead": {
    "description": "書籍從未被閱讀過（lastReadTime epoch 0）時的回退文字"
  },
  "libraryLayoutOverrideTitle": "版面覆寫",
  "@libraryLayoutOverrideTitle": {
    "description": "版面覆寫對話框標題（loading／已載入兩種狀態皆使用同一文字）"
  },
  "libraryLayoutOverrideWritingModeLabel": "排版方向",
  "@libraryLayoutOverrideWritingModeLabel": {
    "description": "版面覆寫對話框「排版方向」區塊小標題"
  },
  "libraryLayoutOverrideWritingModeDefault": "使用書籍排版",
  "@libraryLayoutOverrideWritingModeDefault": {
    "description": "版面覆寫對話框排版方向選項：使用書籍原生排版（不覆寫）"
  },
  "libraryLayoutOverrideWritingModeHorizontal": "橫排",
  "@libraryLayoutOverrideWritingModeHorizontal": {
    "description": "版面覆寫對話框排版方向選項：強制橫排"
  },
  "libraryLayoutOverrideWritingModeVertical": "直排",
  "@libraryLayoutOverrideWritingModeVertical": {
    "description": "版面覆寫對話框排版方向選項：強制直排"
  },
  "libraryLayoutOverridePageTurnModeLabel": "翻頁模式",
  "@libraryLayoutOverridePageTurnModeLabel": {
    "description": "版面覆寫對話框「翻頁模式」區塊小標題"
  },
  "libraryLayoutOverridePageTurnModeDefault": "使用全域預設",
  "@libraryLayoutOverridePageTurnModeDefault": {
    "description": "版面覆寫對話框翻頁模式選項：使用全域預設（不覆寫）"
  },
  "libraryLayoutOverridePageTurnModePaginated": "分頁",
  "@libraryLayoutOverridePageTurnModePaginated": {
    "description": "版面覆寫對話框翻頁模式選項：強制分頁"
  },
  "libraryLayoutOverridePageTurnModeScroll": "捲動",
  "@libraryLayoutOverridePageTurnModeScroll": {
    "description": "版面覆寫對話框翻頁模式選項：強制捲動"
  },
  "libraryLayoutOverrideSaveButton": "儲存",
  "@libraryLayoutOverrideSaveButton": {
    "description": "版面覆寫對話框「儲存」按鈕文字"
  }
```

`app_zh_CN.arb` 檔尾新增：

```json
  "libraryBackButtonTooltip": "返回上层",
  "libraryShelfTitle": "书架",
  "librarySortViewTooltip": "排序与检视",
  "librarySortByLastRead": "最后阅读",
  "librarySortByCreateTime": "建立时间",
  "librarySortByAuthor": "作者",
  "librarySortByTitle": "书名",
  "libraryToggleViewToList": "切换为列表",
  "libraryToggleViewToShelf": "切换为书架",
  "libraryManageGroupsMenuItem": "管理分类...",
  "librarySourceTooltip": "来源",
  "librarySettingsTooltip": "设置",
  "libraryCancelSelectionTooltip": "取消选取",
  "librarySelectedCount": "{count, plural, =1{已选取 1 本} other{已选取 {count} 本}}",
  "libraryMoveToGroupTooltip": "移动到分类",
  "libraryForceFxlTooltip": "强制 FXL",
  "libraryRestoreAutoLayoutTooltip": "恢复自动判断",
  "libraryDeleteTooltip": "删除",
  "libraryRemoveLocalCacheTooltip": "移除本机缓存",
  "libraryEmptyStateMessage": "尚未导入书籍",
  "libraryEmptyStateImportButton": "导入书籍",
  "librarySearchHint": "搜索书名或作者...",
  "libraryContentSearchEntryLabel": "搜索书本内容",
  "libraryNoMatchingBooks": "找不到符合的书籍",
  "libraryDeleteBooksDialogTitle": "删除书籍",
  "libraryDeleteBooksConfirmMessage": "{count, plural, =1{将删除已选取的 1 本书籍，并一并删除其书签、划线与备注，此操作无法恢复。确定要删除吗？} other{将删除已选取的 {count} 本书籍，并一并删除其书签、划线与备注，此操作无法恢复。确定要删除吗？}}",
  "libraryDeleteBooksConfirmButton": "删除",
  "libraryRedownloadAction": "重新下载",
  "libraryRedownloadConfirmMessage": "即将重新下载「{title}」，确定要继续吗？",
  "libraryRedownloadConfirmMessageMobileData": "即将重新下载「{title}」，目前使用移动数据连接，可能产生流量费用，确定要继续吗？",
  "libraryRemoteDisabledMessage": "远程书库功能未启用，无法重新下载",
  "libraryRemoteServerNotFoundMessage": "找不到对应的远程书库站点",
  "libraryRedownloadFailedMessage": "重新下载失败，请稍后再试",
  "libraryRemoveCacheConfirmMessage": "将移除「{title}」的本机文件，书籍记录与阅读进度会保留，之后可重新下载。确定要移除吗？",
  "libraryRemoveCacheConfirmButton": "移除",
  "libraryGroupBadgeLabel": "分类",
  "libraryGroupTileCount": "{count, plural, =1{1 本} other{{count} 本}}",
  "libraryBookMenuTooltip": "更多",
  "libraryContinueReadingLabel": "继续阅读",
  "libraryBookNotDownloaded": "尚未下载",
  "libraryUnknownFileSize": "未知大小",
  "libraryLoadingEllipsis": "读取中...",
  "libraryDetailAuthorLabel": "作者：{author}",
  "libraryUnknownAuthor": "未知",
  "libraryDetailFormatLabel": "格式：{format}",
  "libraryDetailFileSizeLabel": "文件大小：{size}",
  "libraryDetailProgressLabel": "进度：{progress}",
  "libraryDetailLastReadLabel": "最后阅读：{date}",
  "libraryNeverRead": "尚未阅读",
  "libraryLayoutOverrideTitle": "排版覆盖",
  "libraryLayoutOverrideWritingModeLabel": "排版方向",
  "libraryLayoutOverrideWritingModeDefault": "使用书籍排版",
  "libraryLayoutOverrideWritingModeHorizontal": "横排",
  "libraryLayoutOverrideWritingModeVertical": "竖排",
  "libraryLayoutOverridePageTurnModeLabel": "翻页模式",
  "libraryLayoutOverridePageTurnModeDefault": "使用全局默认",
  "libraryLayoutOverridePageTurnModePaginated": "分页",
  "libraryLayoutOverridePageTurnModeScroll": "滚动",
  "libraryLayoutOverrideSaveButton": "保存"
```

`app_en.arb` 檔尾新增：

```json
  "libraryBackButtonTooltip": "Back",
  "libraryShelfTitle": "Library",
  "librarySortViewTooltip": "Sort & View",
  "librarySortByLastRead": "Last Read",
  "librarySortByCreateTime": "Date Added",
  "librarySortByAuthor": "Author",
  "librarySortByTitle": "Title",
  "libraryToggleViewToList": "Switch to List",
  "libraryToggleViewToShelf": "Switch to Grid",
  "libraryManageGroupsMenuItem": "Manage Categories...",
  "librarySourceTooltip": "Sources",
  "librarySettingsTooltip": "Settings",
  "libraryCancelSelectionTooltip": "Cancel Selection",
  "librarySelectedCount": "{count, plural, =1{1 selected} other{{count} selected}}",
  "libraryMoveToGroupTooltip": "Move to Category",
  "libraryForceFxlTooltip": "Force Fixed Layout",
  "libraryRestoreAutoLayoutTooltip": "Restore Auto-Detect",
  "libraryDeleteTooltip": "Delete",
  "libraryRemoveLocalCacheTooltip": "Remove Local Cache",
  "libraryEmptyStateMessage": "No books imported yet",
  "libraryEmptyStateImportButton": "Import Books",
  "librarySearchHint": "Search by title or author...",
  "libraryContentSearchEntryLabel": "Search Book Content",
  "libraryNoMatchingBooks": "No matching books found",
  "libraryDeleteBooksDialogTitle": "Delete Books",
  "libraryDeleteBooksConfirmMessage": "{count, plural, =1{This will delete the 1 selected book, including its bookmarks, highlights, and notes. This cannot be undone. Delete anyway?} other{This will delete the {count} selected books, including their bookmarks, highlights, and notes. This cannot be undone. Delete anyway?}}",
  "libraryDeleteBooksConfirmButton": "Delete",
  "libraryRedownloadAction": "Redownload",
  "libraryRedownloadConfirmMessage": "About to redownload \"{title}\". Continue?",
  "libraryRedownloadConfirmMessageMobileData": "About to redownload \"{title}\" on a mobile data connection, which may incur data charges. Continue?",
  "libraryRemoteDisabledMessage": "Remote library feature is not enabled; cannot redownload",
  "libraryRemoteServerNotFoundMessage": "Could not find the matching remote library server",
  "libraryRedownloadFailedMessage": "Redownload failed. Please try again later.",
  "libraryRemoveCacheConfirmMessage": "This will remove the local file for \"{title}\". The book record and reading progress will be kept, and you can redownload it later. Remove anyway?",
  "libraryRemoveCacheConfirmButton": "Remove",
  "libraryGroupBadgeLabel": "Category",
  "libraryGroupTileCount": "{count, plural, =1{1 book} other{{count} books}}",
  "libraryBookMenuTooltip": "More",
  "libraryContinueReadingLabel": "Continue Reading",
  "libraryBookNotDownloaded": "Not downloaded",
  "libraryUnknownFileSize": "Unknown size",
  "libraryLoadingEllipsis": "Loading...",
  "libraryDetailAuthorLabel": "Author: {author}",
  "libraryUnknownAuthor": "Unknown",
  "libraryDetailFormatLabel": "Format: {format}",
  "libraryDetailFileSizeLabel": "File size: {size}",
  "libraryDetailProgressLabel": "Progress: {progress}",
  "libraryDetailLastReadLabel": "Last read: {date}",
  "libraryNeverRead": "Never read",
  "libraryLayoutOverrideTitle": "Layout Override",
  "libraryLayoutOverrideWritingModeLabel": "Writing Mode",
  "libraryLayoutOverrideWritingModeDefault": "Use Book's Layout",
  "libraryLayoutOverrideWritingModeHorizontal": "Horizontal",
  "libraryLayoutOverrideWritingModeVertical": "Vertical",
  "libraryLayoutOverridePageTurnModeLabel": "Page Turn Mode",
  "libraryLayoutOverridePageTurnModeDefault": "Use Global Default",
  "libraryLayoutOverridePageTurnModePaginated": "Paginated",
  "libraryLayoutOverridePageTurnModeScroll": "Scroll",
  "libraryLayoutOverrideSaveButton": "Save"
```

`app_zh.arb` 檔尾新增（與 `app_zh_TW.arb` 完全相同的 53 個值，不含 `@key`）：

```json
  "libraryBackButtonTooltip": "返回上層",
  "libraryShelfTitle": "書架",
  "librarySortViewTooltip": "排序與檢視",
  "librarySortByLastRead": "最後閱讀",
  "librarySortByCreateTime": "建立時間",
  "librarySortByAuthor": "作者",
  "librarySortByTitle": "書名",
  "libraryToggleViewToList": "切換為列表",
  "libraryToggleViewToShelf": "切換為書架",
  "libraryManageGroupsMenuItem": "管理分類...",
  "librarySourceTooltip": "來源",
  "librarySettingsTooltip": "設定",
  "libraryCancelSelectionTooltip": "取消選取",
  "librarySelectedCount": "{count, plural, =1{已選取 1 本} other{已選取 {count} 本}}",
  "libraryMoveToGroupTooltip": "移動到分類",
  "libraryForceFxlTooltip": "強制 FXL",
  "libraryRestoreAutoLayoutTooltip": "恢復自動判斷",
  "libraryDeleteTooltip": "刪除",
  "libraryRemoveLocalCacheTooltip": "移除本機快取",
  "libraryEmptyStateMessage": "尚未匯入書籍",
  "libraryEmptyStateImportButton": "匯入書籍",
  "librarySearchHint": "搜尋書名或作者...",
  "libraryContentSearchEntryLabel": "搜尋書本內容",
  "libraryNoMatchingBooks": "找不到符合的書籍",
  "libraryDeleteBooksDialogTitle": "刪除書籍",
  "libraryDeleteBooksConfirmMessage": "{count, plural, =1{將刪除已選取的 1 本書籍，並一併刪除其書籤、劃線與備註，此操作無法復原。確定要刪除嗎？} other{將刪除已選取的 {count} 本書籍，並一併刪除其書籤、劃線與備註，此操作無法復原。確定要刪除嗎？}}",
  "libraryDeleteBooksConfirmButton": "刪除",
  "libraryRedownloadAction": "重新下載",
  "libraryRedownloadConfirmMessage": "即將重新下載「{title}」，確定要繼續嗎？",
  "libraryRedownloadConfirmMessageMobileData": "即將重新下載「{title}」，目前使用行動數據連線，可能產生流量費用，確定要繼續嗎？",
  "libraryRemoteDisabledMessage": "遠端書庫功能未啟用，無法重新下載",
  "libraryRemoteServerNotFoundMessage": "找不到對應的遠端書庫站點",
  "libraryRedownloadFailedMessage": "重新下載失敗，請稍後再試",
  "libraryRemoveCacheConfirmMessage": "將移除「{title}」的本機檔案，書籍紀錄與閱讀進度會保留，之後可重新下載。確定要移除嗎？",
  "libraryRemoveCacheConfirmButton": "移除",
  "libraryGroupBadgeLabel": "分類",
  "libraryGroupTileCount": "{count, plural, =1{1 本} other{{count} 本}}",
  "libraryBookMenuTooltip": "更多",
  "libraryContinueReadingLabel": "繼續閱讀",
  "libraryBookNotDownloaded": "尚未下載",
  "libraryUnknownFileSize": "未知大小",
  "libraryLoadingEllipsis": "讀取中...",
  "libraryDetailAuthorLabel": "作者：{author}",
  "libraryUnknownAuthor": "未知",
  "libraryDetailFormatLabel": "格式：{format}",
  "libraryDetailFileSizeLabel": "檔案大小：{size}",
  "libraryDetailProgressLabel": "進度：{progress}",
  "libraryDetailLastReadLabel": "最後閱讀：{date}",
  "libraryNeverRead": "尚未閱讀",
  "libraryLayoutOverrideTitle": "版面覆寫",
  "libraryLayoutOverrideWritingModeLabel": "排版方向",
  "libraryLayoutOverrideWritingModeDefault": "使用書籍排版",
  "libraryLayoutOverrideWritingModeHorizontal": "橫排",
  "libraryLayoutOverrideWritingModeVertical": "直排",
  "libraryLayoutOverridePageTurnModeLabel": "翻頁模式",
  "libraryLayoutOverridePageTurnModeDefault": "使用全域預設",
  "libraryLayoutOverridePageTurnModePaginated": "分頁",
  "libraryLayoutOverridePageTurnModeScroll": "捲動",
  "libraryLayoutOverrideSaveButton": "儲存"
```

- [ ] **Step 2: 執行 `flutter gen-l10n` 確認 ARB 語法正確**

Run: `flutter gen-l10n`
Expected: 無錯誤，`AppLocalizations` 新增 53 個 getter/方法。

- [ ] **Step 3: import 與 AppBar／選取模式 AppBar／空狀態／搜尋列**

在 `app/lib/screens/library_screen.dart` import 區塊新增：
```dart
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
```

`_buildNormalAppBar()`（原第 917-994 行）：
```dart
  AppBar _buildNormalAppBar(List<Book>? books) {
    final l10n = AppLocalizations.of(context)!;
    return AppBar(
      leading: _activeGroupFilter == null
          ? null
          : IconButton(
              key: const Key('library_back_from_group_button'),
              icon: const Icon(Icons.arrow_back),
              tooltip: l10n.libraryBackButtonTooltip,
              onPressed: _exitGroupFilteredView,
            ),
      title: Text(_activeGroupFilter ?? l10n.libraryShelfTitle),
      actions: [
        PopupMenuButton<void>(
          key: const Key('library_sort_view_button'),
          icon: const Icon(Icons.sort),
          tooltip: l10n.librarySortViewTooltip,
          enabled: books != null,
          itemBuilder: (context) {
            final currentSort = _bookListController.sortBy;
            final primaryColor = Theme.of(context).colorScheme.primary;
            final menuL10n = AppLocalizations.of(context)!;
            return [
              for (final sortBy in LibrarySortBy.values)
                PopupMenuItem<void>(
                  key: Key('library_sort_option_${sortBy.name}'),
                  onTap: () => _changeSortBy(sortBy),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: currentSort == sortBy
                            ? Icon(Icons.check, size: 20, color: primaryColor)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _sortLabel(sortBy, menuL10n),
                        style: TextStyle(
                          fontWeight: currentSort == sortBy
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: currentSort == sortBy ? primaryColor : null,
                        ),
                      ),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem<void>(
                key: const Key('library_sort_view_toggle_option'),
                onTap: _toggleViewMode,
                child: Text(
                  _viewMode == LibraryViewMode.grid
                      ? menuL10n.libraryToggleViewToList
                      : menuL10n.libraryToggleViewToShelf,
                ),
              ),
              if (_activeGroupFilter == null)
                PopupMenuItem<void>(
                  key: const Key('library_manage_groups_option'),
                  onTap: _openManageGroupsDialog,
                  child: Text(menuL10n.libraryManageGroupsMenuItem),
                ),
            ];
          },
        ),
        IconButton(
          key: const Key('library_source_button'),
          icon: const Icon(Icons.cloud_download),
          tooltip: l10n.librarySourceTooltip,
          onPressed: widget.onNavigateToSource,
        ),
        IconButton(
          key: const Key('library_settings_button'),
          icon: const Icon(Icons.settings),
          tooltip: l10n.librarySettingsTooltip,
          onPressed: widget.onNavigateToSettings,
        ),
      ],
    );
  }
```

`_buildSelectionAppBar()`（原第 996-1040 行）：
```dart
  AppBar _buildSelectionAppBar() {
    final count = _selectedBookIds?.length ?? 0;
    final l10n = AppLocalizations.of(context)!;
    return AppBar(
      key: const Key('library_selection_app_bar'),
      leading: IconButton(
        key: const Key('library_selection_cancel_button'),
        icon: const Icon(Icons.close),
        tooltip: l10n.libraryCancelSelectionTooltip,
        onPressed: _exitSelectionMode,
      ),
      title: Text(l10n.librarySelectedCount(count)),
      actions: [
        IconButton(
          key: const Key('library_move_to_group_button'),
          icon: const Icon(Icons.drive_file_move),
          tooltip: l10n.libraryMoveToGroupTooltip,
          onPressed: count == 0 ? null : _moveSelectedBooksToGroup,
        ),
        IconButton(
          key: const Key('library_force_fxl_button'),
          icon: const Icon(Icons.menu_book),
          tooltip: l10n.libraryForceFxlTooltip,
          onPressed: count == 0 ? null : _forceFixedLayoutForSelectedBooks,
        ),
        IconButton(
          key: const Key('library_restore_auto_layout_button'),
          icon: const Icon(Icons.restore),
          tooltip: l10n.libraryRestoreAutoLayoutTooltip,
          onPressed: count == 0 ? null : _restoreAutoLayoutForSelectedBooks,
        ),
        IconButton(
          key: const Key('library_delete_books_button'),
          icon: const Icon(Icons.delete),
          tooltip: l10n.libraryDeleteTooltip,
          onPressed: count == 0 ? null : _deleteSelectedBooks,
        ),
        IconButton(
          key: const Key('library_remove_local_cache_button'),
          icon: const Icon(Icons.cloud_off_outlined),
          tooltip: l10n.libraryRemoveLocalCacheTooltip,
          onPressed: count == 0 ? null : _removeLocalCacheForSelectedBooks,
        ),
      ],
    );
  }
```

`_buildEmptyState()`（原第 1042-1055 行）：
```dart
  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.libraryEmptyStateMessage),
          const SizedBox(height: 12),
          ElevatedButton(
            key: const Key('library_empty_import_button'),
            onPressed: widget.onNavigateToSource,
            child: Text(l10n.libraryEmptyStateImportButton),
          ),
        ],
      ),
    );
  }
```

`_buildSearchField()`（原第 791-802 行附近，只改 `hintText`）：
```dart
  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: TextField(
        key: const Key('library_search_field'),
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: AppLocalizations.of(context)!.librarySearchHint,
          isDense: true,
```
（此方法其餘內容不變，僅此一處改動。）

`_buildContentSearchEntryBanner()`（原第 864 行附近）：
```dart
            const Expanded(child: Text('搜尋書本內容')),
```
改為：
```dart
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.libraryContentSearchEntryLabel,
              ),
            ),
```
（該方法其餘 `Icon`/`InkWell` 結構不變，`const Expanded` 因子節點不再是 `const` 需移除外層 `const`。）

`build()` 方法（原第 872-915 行，`'找不到符合的書籍'` 一處）：
```dart
                  Expanded(
                    child: searchResults != null
                        ? (searchResults.isEmpty
                              ? Center(
                                  child: Text(
                                    AppLocalizations.of(context)!
                                        .libraryNoMatchingBooks,
                                  ),
                                )
                              : _buildBookList(
                                  books,
                                  searchResults: searchResults,
                                ))
                        : (books.isEmpty
                              ? _buildEmptyState()
                              : _buildBookList(books)),
                  ),
```
（`build()` 其餘結構不變。）

- [ ] **Step 4: 刪除／重新下載／移除快取三個確認對話框＋對應 SnackBar**

`_confirmDeleteBooks()`（原第 407-426 行）：
```dart
  Future<bool?> _confirmDeleteBooks(int count) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(l10n.libraryDeleteBooksDialogTitle),
          content: Text(l10n.libraryDeleteBooksConfirmMessage(count)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              key: const Key('library_delete_confirm_button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.libraryDeleteBooksConfirmButton),
            ),
          ],
        );
      },
    );
  }
```

`_confirmRedownload()`（原第 484-509 行）：
```dart
  Future<bool?> _confirmRedownload(Book book, bool isMobileData) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          key: const Key('library_redownload_dialog'),
          title: Text(l10n.libraryRedownloadAction),
          content: Text(
            isMobileData
                ? l10n.libraryRedownloadConfirmMessageMobileData(book.title)
                : l10n.libraryRedownloadConfirmMessage(book.title),
          ),
          actions: [
            TextButton(
              key: const Key('library_redownload_cancel_button'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              key: const Key('library_redownload_confirm_button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.libraryRedownloadAction),
            ),
          ],
        );
      },
    );
  }
```

`_handleRedownload()` 內的 2 個 SnackBar（原第 519-620 行，只改 SnackBar 文字部分，其餘邏輯完全不變）：

```dart
  Future<void> _handleRedownload(Book book) async {
    final remoteServerRepository =
        widget.remoteLibraryDependencies.remoteServerRepository;
    final createOpdsClient = widget.remoteLibraryDependencies.createOpdsClient;
    final remoteServerId = book.remoteServerId;
    final remoteDownloadUrl = book.remoteDownloadUrl;
    if (remoteServerRepository == null ||
        createOpdsClient == null ||
        remoteServerId == null ||
        remoteDownloadUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.libraryRemoteDisabledMessage),
        ),
      );
      return;
    }
    if (_redownloadingBookIds.contains(book.id)) return;

    final isMobileData =
        await (widget.isMobileDataConnection?.call() ?? Future.value(false));
    if (!mounted) return;
    final confirmed = await _confirmRedownload(book, isMobileData);
    if (confirmed != true) return;

    _redownloadingBookIds.add(book.id);
    String? tempPath;
    try {
      final servers = await remoteServerRepository.listServers();
      RemoteServerProfile? server;
      for (final s in servers) {
        if (s.id == remoteServerId) {
          server = s;
          break;
        }
      }
      if (server == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.libraryRemoteServerNotFoundMessage,
            ),
          ),
        );
        return;
      }
      final password = await remoteServerRepository.loadPassword(
        remoteServerId,
      );
      final client = createOpdsClient();

      tempPath = await downloadToTempFile(
        client: client,
        server: server,
        acquisition: OpdsAcquisition(
          href: remoteDownloadUrl,
          format: book.format,
        ),
        format: book.format,
        password: password,
      );

      final permanentPath = await promoteToPermanent(tempPath);

      final updatedBook = book.copyWith(
        filePath: permanentPath,
        isDownloaded: true,
      );
      await widget.repository.updateBook(updatedBook);
      try {
        await widget
            .readerFeatureRepositories.fullTextSearchSettingsRepository
            ?.handleBookAvailable(updatedBook);
      } catch (_) {
        // 靜默略過——檔案下載與資料庫標記更新才是核心操作，索引狀態可
        // 日後透過「重建索引」補上。
      }
      if (!mounted) return;
      await _bookListController.loadBooks();
    } catch (_) {
      if (tempPath != null) {
        final leftover = File(tempPath);
        if (await leftover.exists()) await leftover.delete();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.libraryRedownloadFailedMessage),
        ),
      );
    } finally {
      _redownloadingBookIds.remove(book.id);
    }
  }
```

`_confirmRemoveBookCache()`（原第 727-749 行）：
```dart
  Future<bool?> _confirmRemoveBookCache(Book book) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(l10n.libraryRemoveLocalCacheTooltip),
          content: Text(l10n.libraryRemoveCacheConfirmMessage(book.title)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              key: const Key('book_action_remove_cache_confirm_button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.libraryRemoveCacheConfirmButton),
            ),
          ],
        );
      },
    );
  }
```

- [ ] **Step 5: 執行測試確認「預期中的紅燈」——production 已改、測試尚未遷移**

Run:
```bash
flutter test test/screens/library_screen_test.dart 2>&1 | tail -20
```
Expected: 大量測試因 `Null check operator used on a null value`（`AppLocalizations.of(context)!` 在裸 `MaterialApp` 下崩潰）失敗——這證實 Step 3/4 的改動確實生效（若測試仍全數通過，代表某處改動漏掉或裸 `MaterialApp` 意外仍能運作，需回頭檢查）。這個紅燈狀態會在 Task 6 完成後轉綠，本 Step **不需要**修正任何東西，只是驗證檢查點。

- [ ] **Step 6: `flutter analyze` 確認 production 程式碼本身乾淨**

Run:
```bash
flutter analyze lib/screens/library_screen.dart
```
Expected: No issues found!（`flutter analyze` 不執行測試，不受 Step 5 的紅燈狀態影響）

- [ ] **Step 7: Commit（production code only，測試遷移留給 Task 6）**

```bash
git add app/lib/screens/library_screen.dart app/lib/l10n/
git commit -m "feat(epic-45): library_screen.dart AppBar/選取模式/對話框字串抽取（第 1 部分，測試遷移見下個 commit）"
```

---

### Task 6: `library_screen.dart`（剩餘 production 區塊）＋ `library_screen_test.dart` 全面遷移

**Files:**
- Modify: `app/lib/screens/library_screen.dart`（分類拼貼格／書籍格/列項目／繼續閱讀列／書籍詳細資料對話框／版面覆寫對話框）
- Modify: `app/test/support/pump_localized_widget.dart`（新增 `mediaQueryData` 可選參數）
- Modify: `app/test/screens/library_screen_test.dart`（113 處裸 `MaterialApp` 全面遷移）
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`（若 Task 5 一次寫入全部 53 個 key，本 Task 不需要再新增 ARB——見 Task 5 Step 1 已涵蓋本 Task 用到的全部 key）

**Interfaces:**
- Consumes：Task 5 已定義的全部 53 個 ARB key；`pumpLocalizedWidget()`（Issue 0，本 Task 擴充其簽章）。
- Produces：`library_screen_test.dart` 完整遷移後的狀態，供未來任何觸及 `LibraryScreen` 的測試檔案（含未來 Issue）直接沿用 `pumpLocalizedWidget()` 而不再需要裸 `MaterialApp` 特例處理。

- [ ] **Step 1: `pumpLocalizedWidget()` 新增 `mediaQueryData` 可選參數**

`library_screen_test.dart` 有 2 處測試需要模擬系統字級縮放，原本用 `MediaQuery(data: ..., child: MaterialApp(...))` 包裝。修改 `app/test/support/pump_localized_widget.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

/// 統一測試包裝器（epic-45-interface-i18n Issue 0，`spec.md` §8）：既有
/// 測試檔案大量各自建構裸 `MaterialApp(...)`，一旦畫面改用
/// `AppLocalizations.of(context)!` 就會因缺少 `localizationsDelegates`
/// 觸發 `Null check operator` 崩潰。本函式強制注入
/// `AppLocalizations.localizationsDelegates`/`supportedLocales`，並把
/// `locale` 預設釘定為正體中文，讓既有中文 `find.text()` 斷言在遷移期間
/// 維持通過。`theme`/`isEinkMode` 直接收 `AppTheme`/`bool`（而非裸
/// `ThemeData?`），內部呼叫既有 `resolveThemeData()`，比照既有測試檔案
/// `MaterialApp(theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false), ...)`
/// 這種既定寫法收窄參數型別。`mediaQueryData` 供需要模擬系統字級縮放等
/// `MediaQuery` 覆寫情境的測試使用（epic-45-interface-i18n Issue 3：
/// `library_screen_test.dart` 既有 2 個字級縮放測試原本手動用
/// `MediaQuery(data: ..., child: MaterialApp(...))` 包裝，缺少在地化
/// delegates，需要這個參數才能遷移而不必放棄既有的字級模擬能力）。
Future<void> pumpLocalizedWidget(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('zh', 'TW'),
  AppTheme theme = AppTheme.light,
  bool isEinkMode = false,
  GlobalKey<NavigatorState>? navigatorKey,
  List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
  MediaQueryData? mediaQueryData,
}) async {
  final app = MaterialApp(
    navigatorKey: navigatorKey,
    navigatorObservers: navigatorObservers,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: resolveThemeData(theme: theme, isEinkMode: isEinkMode),
    home: home,
  );
  await tester.pumpWidget(
    mediaQueryData == null
        ? app
        : MediaQuery(data: mediaQueryData, child: app),
  );
}
```

- [ ] **Step 2: 分類拼貼格（`_GroupGridTile`／`_GroupListTile`）＋ `_sortLabel()`**

`_GroupGridTile.build()` 內「分類」角標（原第 1345-1362 行附近）：
```dart
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      color: colorScheme.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.libraryGroupBadgeLabel,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
```

`_GroupGridTile.build()` 底部名稱+數量（原第 1395-1404 行）：
```dart
          SizedBox(
            height: gridTileFooterHeight(MediaQuery.textScalerOf(context)),
            child: Text(
              '${tile.name} (${AppLocalizations.of(context)!.libraryGroupTileCount(tile.totalCount)})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ),
```

`_GroupListTile.build()`（原第 1425-1455 行，`subtitle` 一處）：
```dart
      subtitle: Text(
        AppLocalizations.of(context)!.libraryGroupTileCount(tile.totalCount),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
```
（`title: Text(tile.name, ...)` 維持原樣不變——`tile.name` 是使用者自訂分類名稱，見 Global Constraints 說明，不需要 `localizeGroupName()`。）

`_sortLabel()` 頂層函式（原第 1458-1468 行）改為接收 `AppLocalizations`：
```dart
String _sortLabel(LibrarySortBy sortBy, AppLocalizations l10n) {
  switch (sortBy) {
    case LibrarySortBy.lastRead:
      return l10n.librarySortByLastRead;
    case LibrarySortBy.createTime:
      return l10n.librarySortByCreateTime;
    case LibrarySortBy.author:
      return l10n.librarySortByAuthor;
    case LibrarySortBy.title:
      return l10n.librarySortByTitle;
  }
}
```
（呼叫端已在 Task 5 Step 3 的 `_buildNormalAppBar()` 改為 `_sortLabel(sortBy, menuL10n)`。）

- [ ] **Step 3: 書籍格/列項目（`_BookGridTile`／`_BookListTile`）＋繼續閱讀列**

`_BookGridTile.build()`「更多」tooltip（原第 1552-1566 行）：
```dart
                        child: IconButton(
                          key: Key('book_action_menu_${book.id}'),
                          icon: const Icon(
                            Icons.more_vert,
                            color: Colors.white,
                          ),
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          tooltip: AppLocalizations.of(context)!.libraryBookMenuTooltip,
                          onPressed: onMenuTap,
                        ),
```

`_BookListTile.build()`「更多」tooltip（原第 1676-1681 行）：
```dart
          if (!selectionMode)
            IconButton(
              key: Key('book_action_menu_${book.id}'),
              icon: const Icon(Icons.more_vert),
              tooltip: AppLocalizations.of(context)!.libraryBookMenuTooltip,
              onPressed: onMenuTap,
            ),
```

`_ContinueReadingRow.build()`「繼續閱讀」小標籤（原第 1725 行）：
```dart
                  Text(
                    AppLocalizations.of(context)!.libraryContinueReadingLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
```
（原本是 `const Text('繼續閱讀', style: TextStyle(fontSize: 12))`——改為動態值後 `Text`／`TextStyle` 皆不能再是 `const`。）

- [ ] **Step 4: `_BookDetailsDialog`（含日期格式化）**

> **審查修訂（`review-plan-issue-3.md` C-1）**：原計畫第一版在 `initState()` 內呼叫 `AppLocalizations.of(context)!`，把結果傳給 `_resolveFileSizeText()` 存進 `_fileSizeFuture`。已查證這是真實的 Flutter 框架限制，非審查方誤判——`AppLocalizations.of(context)` 底層呼叫 `context.dependOnInheritedWidgetOfExactType()`，而 `StatefulElement.dependOnInheritedElement()`（`flutter/packages/flutter/lib/src/widgets/framework.dart`）明確斷言 `state._debugLifecycleState != _StateLifecycle.created`；`State.initState()` 執行期間這個欄位恆為 `created`（要到 `initState()` 返回後框架才會轉為 `initialized`），故在 `initState()` 內呼叫必定拋出 `dependOnInheritedWidgetOfExactType<AppLocalizations>() or dependOnInheritedElement() was called before _BookDetailsDialogState.initState() completed.`（已於本機 Flutter SDK 原始碼逐行追蹤確認，非僅憑文件註解）。修訂為審查建議的作法：`_resolveFileSizeText()`（更名 `_resolveFileSize()`）不再依賴 `AppLocalizations`，只負責純 I/O，回傳「位元組數或狀態」的裸資料；實際轉譯字串挪到 `FutureBuilder` 的 `builder(context, snapshot)`（`build()` 內，`context` 安全可用）內完成。

`_BookDetailsDialogState` 欄位宣告（原第 1760 行）型別隨之改變：
```dart
  late final Future<Object> _fileSizeFuture;
```
（原本是 `late final Future<String> _fileSizeFuture;`——`Object` 的實際值只會是 `int`〔已讀取到的位元組數〕或下方 `_FileSizeStatus` 列舉兩者之一，由 `build()` 內的 `switch` 分派，不會是其他型別。）

在 `_BookDetailsDialogState` 類別之前新增一個私有列舉，供 `_resolveFileSize()` 表示「尚未下載」／「無法讀取」兩種非數值狀態（原第 1755 行 `class _BookDetailsDialog extends StatelessWidget` 之前）：
```dart
enum _FileSizeStatus { notDownloaded, unknown }
```

`_resolveFileSizeText()` 更名為 `_resolveFileSize()`（原第 1768-1785 行），改為純 I/O、不接觸 `AppLocalizations`：
```dart
  static Future<Object> _resolveFileSize(Book book) async {
    if (!book.isDownloaded) return _FileSizeStatus.notDownloaded;
    try {
      final file = File(book.filePath);
      if (!file.existsSync()) return _FileSizeStatus.unknown;
      return file.statSync().size;
    } catch (_) {
      return _FileSizeStatus.unknown;
    }
  }
```

`initState()`（原第 1762-1766 行）恢復為不含任何 `AppLocalizations` 呼叫：
```dart
  @override
  void initState() {
    super.initState();
    _fileSizeFuture = _resolveFileSize(widget.book);
  }
```

`_formatLastReadTime()`（原第 1793-1799 行，`issues.md` I-1 明訂改用 `DateFormat`——本方法一律只在 `build()` 內被呼叫，不受 C-1 影響，維持原設計）：
```dart
  static String _formatLastReadTime(
    DateTime time,
    AppLocalizations l10n,
    Locale locale,
  ) {
    if (time.millisecondsSinceEpoch <= 0) return l10n.libraryNeverRead;
    return DateFormat.yMd(locale.toString()).format(time);
  }
```

`build()`（原第 1801-1840 行，`FutureBuilder<Object>` 的 `builder` 內依 `snapshot.hasError`／`hasData`／已解析出的 `_FileSizeStatus`/`int` 分派轉譯字串——`l10n` 只在這裡被存取，`context` 安全）：
```dart
  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context);
    return AlertDialog(
      key: const Key('book_details_dialog'),
      title: Text(convertText(book.title, widget.textConversion)),
      content: FutureBuilder<Object>(
        future: _fileSizeFuture,
        builder: (context, snapshot) {
          final String fileSizeText;
          if (snapshot.hasError) {
            fileSizeText = l10n.libraryUnknownFileSize;
          } else if (!snapshot.hasData) {
            fileSizeText = l10n.libraryLoadingEllipsis;
          } else {
            fileSizeText = switch (snapshot.data!) {
              _FileSizeStatus.notDownloaded => l10n.libraryBookNotDownloaded,
              _FileSizeStatus.unknown => l10n.libraryUnknownFileSize,
              final int bytes => _formatFileSize(bytes),
              _ => l10n.libraryUnknownFileSize,
            };
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.libraryDetailAuthorLabel(
                  book.author == null
                      ? l10n.libraryUnknownAuthor
                      : convertText(book.author!, widget.textConversion),
                ),
              ),
              Text(l10n.libraryDetailFormatLabel(book.format.name)),
              Text(l10n.libraryDetailFileSizeLabel(fileSizeText)),
              Text(l10n.libraryDetailProgressLabel(_progressText(book))),
              Text(
                l10n.libraryDetailLastReadLabel(
                  _formatLastReadTime(book.lastReadTime, l10n, locale),
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          key: const Key('book_details_dialog_close_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
```

> `l10n.close` 沿用 Issue 2 已建立的全域共用 key（不需要新增 `bookDetailsCloseButton`——原本這裡的「關閉」與 Issue 2 `library_group_management_dialog.dart` 的「關閉」語意完全相同）。

- [ ] **Step 5: `_LayoutOverrideDialog`**

`build()`（原第 1936-2044 行，`_load()`／`_save()` 方法本身不含字串、不需要修改）：
```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_existingPrefs == null) {
      return AlertDialog(
        key: const Key('layout_override_dialog'),
        title: Text(l10n.libraryLayoutOverrideTitle),
        content: const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
        actions: [
          TextButton(
            key: const Key('layout_override_cancel_button'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
        ],
      );
    }
    return AlertDialog(
      key: const Key('layout_override_dialog'),
      title: Text(l10n.libraryLayoutOverrideTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.libraryLayoutOverrideWritingModeLabel),
            Wrap(
              spacing: 4,
              children: [
                ReaderOptionTile<WritingMode?>(
                  itemKey: const Key('layout_override_writing_mode_default'),
                  value: null,
                  groupValue: _writingMode,
                  icon: Icons.auto_awesome,
                  tooltip: l10n.libraryLayoutOverrideWritingModeDefault,
                  onSelected: (v) => setState(() => _writingMode = v),
                ),
                ReaderOptionTile<WritingMode?>(
                  itemKey: const Key('layout_override_writing_mode_horizontal'),
                  value: WritingMode.horizontal,
                  groupValue: _writingMode,
                  icon: Icons.text_rotation_none,
                  tooltip: l10n.libraryLayoutOverrideWritingModeHorizontal,
                  onSelected: (v) => setState(() => _writingMode = v),
                ),
                ReaderOptionTile<WritingMode?>(
                  itemKey: const Key('layout_override_writing_mode_vertical'),
                  value: WritingMode.vertical,
                  groupValue: _writingMode,
                  icon: Icons.text_rotate_vertical,
                  tooltip: l10n.libraryLayoutOverrideWritingModeVertical,
                  onSelected: (v) => setState(() => _writingMode = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l10n.libraryLayoutOverridePageTurnModeLabel),
            Wrap(
              spacing: 4,
              children: [
                ReaderOptionTile<PageTurnMode?>(
                  itemKey: const Key('layout_override_page_turn_mode_default'),
                  value: null,
                  groupValue: _pageTurnMode,
                  icon: Icons.tune,
                  tooltip: l10n.libraryLayoutOverridePageTurnModeDefault,
                  onSelected: (v) => setState(() => _pageTurnMode = v),
                ),
                ReaderOptionTile<PageTurnMode?>(
                  itemKey: const Key(
                    'layout_override_page_turn_mode_paginated',
                  ),
                  value: PageTurnMode.paginated,
                  groupValue: _pageTurnMode,
                  icon: Icons.menu_book,
                  tooltip: l10n.libraryLayoutOverridePageTurnModePaginated,
                  onSelected: (v) => setState(() => _pageTurnMode = v),
                ),
                ReaderOptionTile<PageTurnMode?>(
                  itemKey: const Key('layout_override_page_turn_mode_scroll'),
                  value: PageTurnMode.scroll,
                  groupValue: _pageTurnMode,
                  icon: Icons.swap_vert,
                  tooltip: l10n.libraryLayoutOverridePageTurnModeScroll,
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
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const Key('layout_override_save_button'),
          onPressed: _save,
          child: Text(l10n.libraryLayoutOverrideSaveButton),
        ),
      ],
    );
  }
```

- [ ] **Step 6: `flutter analyze` 確認 production 程式碼乾淨**

Run:
```bash
flutter analyze lib/screens/library_screen.dart
```
Expected: No issues found!

- [ ] **Step 7: 遷移 `library_screen_test.dart` 全部 113 處裸 `MaterialApp`**

在 `app/test/screens/library_screen_test.dart` import 區塊確認已有：
```dart
import '../support/pump_localized_widget.dart';
```
（Issue 2 審查修訂時已加入此 import，若確認已存在則跳過本行新增。）

**遷移規則**（機械式轉換，逐一套用在全部 113 處）：

1. 找出所有裸 `MaterialApp(` 呼叫：
   ```bash
   grep -n "MaterialApp(" test/screens/library_screen_test.dart
   ```
2. 對每一處，依 3 種既有模式分別轉換：

   **模式 A**（最常見，約 108 處，`theme: resolveThemeData(...)` 或 `theme: theme`〔本地變數，值恆等於 `resolveThemeData(theme: AppTheme.light, isEinkMode: false)`〕）：
   ```dart
   // Before
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

   // After
   await pumpLocalizedWidget(
     tester,
     LibraryScreen(
       repository: repository,
       importService: FakeBookImportService(),
       prefsManager: prefsManager,
     ),
   );
   ```
   若該處使用本地變數 `final theme = resolveThemeData(theme: AppTheme.light, isEinkMode: false);` 且該變數只用於這一處 `MaterialApp(theme: theme, ...)`（無其他用途——用 `grep` 確認該變數在同一個 `testWidgets` 區塊內只出現這 2 次：宣告＋這裡），一併移除該行宣告。若變數另有其他用途（例如稍後用來斷言 `colorScheme`），保留宣告，僅移除 `MaterialApp(theme: theme, ...)` 這個包裝（`pumpLocalizedWidget()` 預設 `theme: AppTheme.light, isEinkMode: false` 與其值恆等，行為不變）。

   **模式 B**（2 處，`MediaQuery(data: ..., child: MaterialApp(...))` 模擬字級縮放）：
   ```dart
   // Before
   await tester.pumpWidget(
     MediaQuery(
       data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
       child: MaterialApp(
         theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
         home: LibraryScreen(
           repository: repository,
           importService: FakeBookImportService(),
           prefsManager: prefsManager,
         ),
       ),
     ),
   );

   // After
   await pumpLocalizedWidget(
     tester,
     LibraryScreen(
       repository: repository,
       importService: FakeBookImportService(),
       prefsManager: prefsManager,
     ),
     mediaQueryData: MediaQueryData(textScaler: TextScaler.linear(1.5)),
   );
   ```
   （第二處把 `data:` 換成 `const MediaQueryData(textScaler: _NonLinearTextScaler(1.5))`，其餘轉換方式相同。）

   **模式 C**（若 grep 出的 113 處中有本規則未列舉到的變體結構——例如額外帶了 `navigatorObservers`／`navigatorKey`／`locale` 參數；`grep -c "navigatorObservers\|navigatorKey" test/screens/library_screen_test.dart` 目前為 0，本規則屬預防性規則，非本檔案實際已知案例），對照該處既有參數逐一透傳給 `pumpLocalizedWidget()` 對應的具名參數，不得遺漏，例如：
   ```dart
   // Before（若出現此變體）
   await tester.pumpWidget(
     MaterialApp(
       theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
       navigatorObservers: [myObserver],
       home: LibraryScreen(
         repository: repository,
         importService: FakeBookImportService(),
         prefsManager: prefsManager,
       ),
     ),
   );

   // After
   await pumpLocalizedWidget(
     tester,
     LibraryScreen(
       repository: repository,
       importService: FakeBookImportService(),
       prefsManager: prefsManager,
     ),
     navigatorObservers: [myObserver],
   );
   ```

3. 逐一轉換完成後，重新 grep 驗證零殘留：
   ```bash
   grep -c "MaterialApp(" test/screens/library_screen_test.dart
   ```
   Expected: `0`（比對 Issue 2 遺留下 9 處已遷移＋本次全部遷移完畢後，全檔案不應再有任何 `MaterialApp(` 字面出現，除非該行是 import 語句本身，用 `grep -n` 逐一確認每個殘留都不是被遺漏的呼叫）。

- [ ] **Step 8: 執行 `library_screen_test.dart` 確認全數通過**

Run:
```bash
flutter test test/screens/library_screen_test.dart
```
Expected: 全數通過（既有全部測試，零回歸；Task 5 Step 5 的紅燈狀態應已轉綠）。

- [ ] **Step 9: 新增三語言渲染驗證測試**

在 `app/test/screens/library_screen_test.dart` 檔尾（`main()` 結尾 `}` 之前，`class _NonLinearTextScaler` 定義之前）新增：

```dart
  group('三語言渲染驗證（epic-45-interface-i18n Issue 3）', () {
    testWidgets('英文介面下 AppBar／空狀態／選取模式文字正確以英文渲染', (tester) async {
      await pumpLocalizedWidget(
        tester,
        LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
        locale: const Locale('en'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Library'), findsOneWidget);
      expect(find.text('No books imported yet'), findsOneWidget);
      expect(find.text('Import Books'), findsOneWidget);
    });

    testWidgets('英文介面下選取模式 AppBar 標題依 ICU plural 正確處理單複數', (tester) async {
      final books = [
        _testBook(id: '1', title: 'Book A'),
        _testBook(id: '2', title: 'Book B'),
      ];
      await pumpLocalizedWidget(
        tester,
        LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: books),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
        locale: const Locale('en'),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const Key('book_item_1')));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.byKey(const Key('book_item_2')));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('簡體中文介面下分類拼貼格數量與刪除確認訊息正確以簡體渲染', (tester) async {
      final book = _testBook(id: '1', title: '測試書', groupName: '奇幻');
      await pumpLocalizedWidget(
        tester,
        LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
        locale: const Locale('zh', 'CN'),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 本'), findsOneWidget);

      await tester.tap(find.byKey(const Key('group_tile_奇幻')));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('book_item_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('library_delete_books_button')));
      await tester.pumpAndSettle();

      expect(find.text('删除书籍'), findsOneWidget);
      expect(find.textContaining('将删除已选取的 1 本书籍'), findsOneWidget);
    });

    testWidgets('英文介面下書籍詳細資料對話框日期依 en 地區慣例格式化（非手動 y/m/d 拼接）',
        (tester) async {
      final book = _testBook(
        id: '1',
        title: 'Test Book',
        lastReadTime: DateTime(2026, 3, 15),
      );
      await pumpLocalizedWidget(
        tester,
        LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
        locale: const Locale('en'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_action_menu_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book_action_details')));
      await tester.pumpAndSettle();

      // DateFormat.yMd('en') 輸出格式為 "3/15/2026"（月/日/年），與手動拼接
      // 的 "2026/3/15"（年/月/日）不同，藉此驗證確實改用 DateFormat 而非
      // 殘留手動字串拼接。
      expect(find.textContaining('3/15/2026'), findsOneWidget);
    });
  });
```

> 若 `_testBook()` fixture 不支援 `groupName`／`lastReadTime` 具名參數，對照檔案既有其他測試的 `_testBook()` 呼叫寫法調整（該檔案已有多處類似用法，見既有「管理分類對話框」與「詳細資料」相關測試群組）。

- [ ] **Step 10: 執行完整測試確認新增測試通過**

Run:
```bash
flutter test test/screens/library_screen_test.dart
```
Expected: 全數通過（既有全部測試＋新增 4 個）。

- [ ] **Step 11: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/support/pump_localized_widget.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-45): library_screen.dart 剩餘字串抽取（拼貼格/書籍格/詳細資料/版面覆寫）＋ library_screen_test.dart 113 處測試全面遷移"
```

---

### Task 7: 完整驗收

**Files:** 無新增/修改程式碼檔案；更新 `docs/epics/epic-45-interface-i18n/issues.md`／`epic.md`／`docs/epics.md`。

**Interfaces:** 無。

- [ ] **Step 1: 完整 `flutter analyze`**

Run:
```bash
flutter analyze
```
Expected: No issues found!

- [ ] **Step 2: 完整 `flutter test`**

Run:
```bash
flutter test
```
Expected: 全數通過（比對 Issue 2 合併時的基準測試數，本 Issue 新增：Task 1 新增 2 個、Task 2 新增 1 個、Task 3 新增 1 個、Task 4 新增 2 個、Task 6 新增 4 個，共淨增 10 個測試）。

- [ ] **Step 3: 確認 `reader_screen.dart`／`reader_screen_test.dart` 零異動**

Run:
```bash
git diff main -- app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
```
Expected: 空輸出，驗證 Global Constraints「嚴禁觸碰 `reader_screen.dart`」承諾兌現。

- [ ] **Step 4: 手動驗證三語言下書架模組正確渲染**

Run:
```bash
flutter run
```
Expected: 「設定→語言」切換至簡體中文／English 後，書架 AppBar／選取模式工具列／排序選單／分類拼貼格／書籍詳細資料對話框／版面覆寫對話框／書內搜尋／全庫內容搜尋／單書動作選單皆正確顯示對應語言；日期格式依地區慣例呈現（英文為 M/D/Y，非年/月/日）；ICU plural 在英文下單複數正確（1 本書選取顯示 "1 selected" 非 "1 selecteds"）。

- [ ] **Step 5: 修訂 `issues.md`——標記 Issue 3 完成**

在 `docs/epics/epic-45-interface-i18n/issues.md`「Issue 3」標題旁補上 `**Status:** completed`。並在「What to build」段落末尾補註：

```
**實際執行範圍修正記錄（2026-XX-XX 認領時 grep 盤點）**：移出 `library_batch_actions.dart`（純邏輯類別，零硬編碼字串）、`format_selection_dialog.dart`（實際屬 Issue 6 範圍，唯一呼叫端為 `remote_catalog_screen.dart`）、`layout_preset_book_picker_screen.dart`（實際屬 Issue 4 範圍，唯一呼叫端為 `reader_screen.dart`）、`library/widgets/cover_placeholder.dart`（檔案不存在，`library/widgets/` 僅有 `book_cover.dart` 且零硬編碼字串）；新增 `full_text_search_confirm_dialog.dart`（與 Issue 5 `settings_scaffold.dart` 共用，比照 Issue 0 收斂 `eb_sheet_shell.dart` 先例，本 Issue 一次處理完畢）。
```

- [ ] **Step 6: 更新 `epic.md`**

新增一段開發記錄，記錄本 Issue 完成情況（`library_screen.dart`／`library_search_screen.dart`／`book_search_screen.dart`／`book_action_sheet.dart`／`full_text_search_confirm_dialog.dart` 完整字串抽取、新增 84 個 ARB key、`DateFormat` 首次落地、`library_screen_test.dart` 113 處測試全面遷移、範圍修正記錄）與下一步（認領 Issue 4-6 任一模組，Issue 5 屆時可直接沿用本 Issue 已完成的 `full_text_search_confirm_dialog.dart` 在地化）。

- [ ] **Step 7: 更新 `docs/epics.md` 進度**

把第 46 列（`epic-45-interface-i18n`）備註欄位改為反映 Issue 3 已完成（例如「Issue 0／1／2／3 已完成，待認領 Issue 4-6」）。

- [ ] **Step 8: Commit**

```bash
git add docs/epics/epic-45-interface-i18n/issues.md docs/epics/epic-45-interface-i18n/epic.md docs/epics.md
git commit -m "docs(epic-45): 標記 Issue 3 為 completed，記錄實際執行範圍修正"
```

---

## Self-Review 摘要（撰寫計畫時的自我檢查紀錄）

- **Spec 覆蓋度**：`issues.md` Issue 3 的 3 條要求（畫面字串抽取／日期格式化 `DateFormat.yMd`／ICU plural 選取數量與刪除確認訊息）依序對應 Task 5-6（`library_screen.dart` 主體）、Task 6 Step 4（`_formatLastReadTime` 改用 `DateFormat`）、Task 5 Step 1（`librarySelectedCount`/`libraryDeleteBooksConfirmMessage` 皆採 `plural` 語法）。`spec.md` §5.1（`BookGroup` Sentinel 轉譯契約）於 Global Constraints 明確排除本 Issue 觸及範圍不適用（分類名稱顯示已在 Issue 2 處理，本 Issue 的分類拼貼格只顯示使用者自訂分類名稱，不會遇到 Sentinel）。
- **型別一致性**：`_sortLabel(LibrarySortBy sortBy, AppLocalizations l10n)`（Task 6 Step 2 定義）與呼叫端 `_sortLabel(sortBy, menuL10n)`（Task 5 Step 3）簽章一致；`pumpLocalizedWidget()` 新增的 `mediaQueryData` 參數（Task 6 Step 1 定義）與 Task 6 Step 7 遷移規則模式 B 的呼叫方式一致；`_resolveFileSize(Book book)`（Task 6 Step 4，審查修訂後不再接收 `AppLocalizations`）回傳 `Future<Object>`，與欄位宣告 `late final Future<Object> _fileSizeFuture` 及 `FutureBuilder<Object>` 型別一致，其解析結果（`int`／`_FileSizeStatus`）與 `build()` 內 `switch` 分支窮盡覆蓋；`_formatLastReadTime(DateTime time, AppLocalizations l10n, Locale locale)` 與 `build()` 內呼叫端三個參數順序一致。
- **未使用 placeholder**：Task 6 Step 7（113 處測試遷移）採「轉換規則＋分類列舉」而非逐一列出全部 113 個 diff——這是刻意的設計決策而非偷懶：113 處呼叫高度結構一致（3 種模式涵蓋全部案例），逐一列出會產生近 2000 行幾乎相同的樣板程式碼，反而讓真正的變異點（模式 B 的 2 個特例）被淹沒；Step 7 的 grep 驗證步驟（轉換前定位、轉換後歸零確認）提供了機械式完整性檢查，取代逐一列舉的把關作用。其餘所有 Task 的程式碼片段皆為可直接套用的完整程式碼，無 TBD/待補。
- **架構偏離已記錄**：三處範圍修正（移出 `library_batch_actions.dart`／`format_selection_dialog.dart`／`layout_preset_book_picker_screen.dart`，新增 `full_text_search_confirm_dialog.dart`）已在計畫 Architecture 段落逐一記錄查證依據（grep 呼叫端），並排定 Task 7 Step 5 同步修正 `issues.md` 留下記錄，避免歸檔後文件與實際範圍不符。
- **與 Issue 2 既有模式的延伸點**：`AppLocalizations.of(context)!` non-null assertion（吸取 Issue 2 review-issue-2.md Important #1 教訓，一開始就用 `!`，不落入 nullable fallback 陷阱）；`cancel`/`close` 全域共用 key 直接沿用不重複定義；`pumpLocalizedWidget()` 擴充 `mediaQueryData` 參數是本 Issue 對 Issue 0 既有測試包裝器的必要延伸（Issue 2 沒有遇到 `MediaQuery` 包裝 `MaterialApp` 的既有測試案例）；`_wrap()`/`wrap()` 自訂 helper 直接補參數而非強制改用 `pumpLocalizedWidget()` 本身，是本 Issue 對「既有測試檔已有自己一層包裝函式」情境的務實處理，避免不必要的大範圍呼叫端改寫。

**2026-09-21 `/superpowers:receiving-code-review` 審查（`reviews/review-plan-issue-3.md`，結論 Changes Requested，1 Critical／2 Important／3 Minor）已處理，1 項 Critical＋2 項 Minor 查證屬實並修訂、2 項（1 Important＋1 Important 分項）查證為誤判、1 項 Minor 判定不適用本 Issue 範圍**：

- **C-1（查證屬實，已修訂）**：原 Task 6 Step 4 在 `_BookDetailsDialogState.initState()` 內呼叫 `AppLocalizations.of(context)!`，並主張「`initState()` 階段呼叫是安全的」——此主張經查證為誤，已用本機 Flutter SDK 原始碼逐行追蹤確認：`AppLocalizations.of(context)` 底層呼叫 `dependOnInheritedWidgetOfExactType()` → `StatefulElement.dependOnInheritedElement()`（`packages/flutter/lib/src/widgets/framework.dart`）明確斷言 `state._debugLifecycleState != _StateLifecycle.created`，而 `State.initState()` 執行期間這個欄位恆為 `created`，必定拋出審查報告引用的確切錯誤訊息。修訂為審查建議的作法：`_resolveFileSizeText()` 更名 `_resolveFileSize()`、不再依賴 `AppLocalizations`，只回傳位元組數（`int`）或新增的 `_FileSizeStatus`（`notDownloaded`/`unknown`）列舉；轉譯字串挪到 `FutureBuilder.builder()`（`build()` 內，`context` 安全）用 `switch` 分派；`_fileSizeFuture` 欄位型別隨之改為 `Future<Object>`；`initState()` 恢復不含任何 `AppLocalizations` 呼叫。既有 4 個「詳細資料」測試（`book.isDownloaded == false`／`content:// URI 或讀取失敗`／`已下載且為本機真實檔案`／`lastReadTime 為 epoch 0`）已完整覆蓋這條路徑的四種狀態分派，Task 6 Step 8/10 執行時會直接驗證此修訂正確性，不需要額外新增測試。
- **I-1（查證為誤判，不修改）**：宣稱 `librarySearchDrillDownButton` 的雙 `plural` ARB 訊息會導致 `flutter gen-l10n` 解析失敗——已用本機 Flutter SDK 的 `flutter_tools/lib/src/localizations/message_parser.dart`（`ST.message` 文法允許 `pluralExpr`/`selectExpr` 以任意數量的同層級 sibling 出現，非強制單一）與 `gen_l10n.dart`（`_generateMethod()` 的 DFS 遍歷對每個獨立 `pluralExpr` 節點各自產生一個 `_tempN` 暫存變數與 `Intl.pluralLogic()` 呼叫，逐一串接）逐行核對後，**實際執行 `flutter gen-l10n`**（在 scratchpad 建立最小可重現的獨立 ARB／pubspec 環境，指向與計畫完全相同的雙 plural 訊息字串）驗證：exit code 0，成功產生語法正確的 Dart 程式碼（`_temp0`／`_temp1` 各自獨立 `Intl.pluralLogic()`，`return '$_temp0 ($_temp1)';`）。**本項為審查方誤判，ARB 定義維持原樣不修改**。
- **I-2（查證為誤判，不修改程式碼，補強說明文字）**：宣稱 Task 4 Step 3 的 `EBSectionHeader(title: l10n.xxx)` 若「漏掉移除 `const`」會編譯失敗——逐行核對計畫檔案第 1381／1389 行實際內容，兩處**原本就已經**是不含 `const` 的 `EBSectionHeader(title: l10n.librarySearchTitleAuthorSectionHeader)`／`EBSectionHeader(title: l10n.librarySearchContentSectionHeader)`，且計畫中已有一段獨立說明文字記錄這個轉換注意事項（僅位置在同一 Step 較後段落）。**程式碼本身無需修改**；為降低未來閱讀者對照程式碼與提醒文字的認知負擔，已在 `_buildResults()` 程式碼區塊後緊接補上一段簡短澄清註記（原本較遠處的完整說明文字維持不動，不重複刪除）。
- **M-1（查證屬實，已修訂）**：Task 6 Step 7 模式 C 只有文字描述、缺具體範例——已補上 `navigatorObservers` 透傳的完整 before/after 程式碼範例；同時 grep 確認 `library_screen_test.dart` 目前實際零處使用 `navigatorObservers`/`navigatorKey`，此規則屬預防性規則，已在文字中註明。
- **M-2（查證屬實，已修訂）**：`@bookSearchResultsSummaryTruncated` 的 ARB description 已補強，明確點出 `{shown}` 對應呼叫端的 `result.matches.length`、`{total}` 對應 `result.totalMatches`。
- **M-3（查證為不適用本 Issue 範圍，不修改）**：建議 Task 7 驗收補上 `node app/tool/check_foliate_es_compat.js` 靜態掃描——查證 `CLAUDE.md` 對此腳本的明文觸發條件是「每次升級 foliate-js 這份釘定版本後」，Issue 3 全程只異動 Dart／ARB 檔案，未觸碰 `app/android/app/src/main/assets/foliate/` 下任何 JS 供應商程式碼，不符合觸發條件，加入本 Issue Task 7 屬於與本 Issue 範圍無關的多餘檢查（YAGNI）。**不修改 Task 7**。

本輪修訂中最關鍵的一項是 C-1——這是真實會在使用者點擊「詳細資料」時觸發執行期崩潰的阻斷性缺陷，已透過追蹤 Flutter 框架原始碼（而非僅憑審查報告或個人記憶）確認問題成立並正確修復；I-1／I-2 兩項則透過實際執行 `flutter gen-l10n`／逐行核對計畫檔案內容，確認審查方誤判，予以推翻而非照單全收。
