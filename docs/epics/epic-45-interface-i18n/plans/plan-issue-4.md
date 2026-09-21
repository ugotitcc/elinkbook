# Epic 45 Issue 4：閱讀器 Chrome Bar 模組字串抽取＋測試遷移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把閱讀器 Chrome Bar 模組（`ReaderScreen` 本體與其頂部/底部列、目錄、劃線/備註、TTS、PDF/EPUB 版面設定、搜尋、縮圖、閱讀位置衝突等全部彈窗/面板）的硬編碼中文字串改為 `AppLocalizations` key，三語言皆補上真實翻譯，對應測試檔同步遷移至 `pumpLocalizedWidget()`，零使用者可見行為變動（除新增語言支援本身）。

**Architecture:** 沿用 Issue 2／3 已確立的模式——`AppLocalizations.of(context)!`（non-null assertion）＋新增 ARB key（三語言真實翻譯＋`app_zh.arb` fallback 同步）＋既有測試改用 `pumpLocalizedWidget()`。本 Issue 規模遠大於 Issue 3（約 16 個生產檔案、260+ 處字串、330+ 處測試遷移，`reader_screen.dart`／`reader_screen_test.dart` 兩檔案本身就佔整體規模一半以上），故拆為 21 個 Task，大型檔案（`reader_settings_sheet.dart`／`fxl_settings_sheet.dart`／`reader_screen.dart`／`reader_screen_test.dart`）的生產程式碼與測試遷移拆成相鄰獨立 Task（比照 `plan-issue-3.md` Task 5/6 先例）。

**範圍已依實際 grep 盤點修正**（`issues.md` 本身註明「代表性範圍，實際檔案清單以認領當下重新 grep 盤點為準」）：
- **移出**：`toc_bottom_sheet_pdf.dart`（檔案不存在——PDF／EPUB 共用同一份 `toc_bottom_sheet.dart`，透過既有 `BookTocItem` 格式無關抽象介面實作三分頁 TabBar，`issues.md` 這個檔名引用已過時）、`reader_footer.dart`（grep 確認零硬編碼中文字串——內容僅為「當前頁/總頁數」與百分比等純數字組成的文字，不需要翻譯；其測試 `reader_footer_test.dart` 因此也不需要遷移，見 Global Constraints）、`widgets/eb_sheet_shell.dart`（`issues.md` 本身已註明「已在 Issue 0 處理，本 Issue 不重複修改」，本計畫比照辦理）、`full_text_search_confirm_dialog.dart`（已在 Issue 3 完整在地化，`issues.md` 本身已註明，本計畫不重複處理）、`widgets/eb_option_chip_group.dart`／`widgets/eb_section_header.dart`／`widgets/eb_stepper.dart`／`widgets/eb_field_card.dart`／`widgets/reader_option_tile.dart`（grep 確認皆為 0 處硬編碼字串，純結構性共用元件）、`widgets/text_conversion_icon.dart`（grep 命中的 4 處 `'简'`／`'繁'` 並非待翻譯 UI 文字，而是「簡轉繁／繁轉簡」示意圖示本身要呈現的目標文字樣本——這個 widget 的存在意義就是視覺化展示這兩個字，不隨語言切換而改變，比照 `design.md`「內建字型品牌名不翻譯」的例外原則，本 Issue 不修改此檔案）。
- **確認保留**：`reader_screen.dart`（`_buildSearchableBook()` 內 `groupName: BookGroup.uncategorized` 那一行除外，見 Global Constraints「不可變性例外」）、`widgets/paging_bar.dart`（雖然也被 `library_screen.dart`／`library_search_screen.dart`〔Issue 3〕共用，但本 Issue 修改的是元件本身，不觸碰 Issue 3 已完成的呼叫端）。

**Tech Stack:** Flutter `flutter_localizations`／`intl`（ARB／`gen-l10n`，含 ICU `plural`、`DateFormat`）。

**Spec:** `docs/epics/epic-45-interface-i18n/spec.md`（§5.1 `localizeGroupName()`／`BookGroupL10n`、§8 測試相容性）、`docs/epics/epic-45-interface-i18n/issues.md`（Issue 4 段落）。

## Global Constraints

- 所有新增 ARB key 必須同步寫入四份檔案：`app_zh_TW.arb`（含 `@key` description）、`app_zh_CN.arb`、`app_en.arb`（皆為真實翻譯，非機器翻譯佔位）、`app_zh.arb`（與 `app_zh_TW.arb` 相同值，不含 `@key` description block）。
- **不可變性例外（唯一一處）**：`reader_screen.dart` 的 `_buildSearchableBook()`（約第 1747-1762 行）內 `groupName: BookGroup.uncategorized` 這一行絕對不可改為 `localizeGroupName()`／`displayName()`——這是純暫態、不落地的搜尋用 `Book` 佔位物件（見既有程式碼註解「不影響任何實際行為」），維持底層 Sentinel 字面值（`spec.md` §5.1，Issue 2 已確立的區分原則）。除此之外，`reader_screen.dart` 全檔案其餘字串皆在本 Issue 範圍內（含本檔案本身，不同於 Issue 2／3 對本檔案的「嚴禁觸碰」限制——那是針對「非閱讀器模組」的限制，本 Issue 就是閱讀器模組本身）。
- `AppLocalizations.of(context)!` 一律用 non-null assertion，不得使用 `l10n?.xxx ?? '硬編碼字面值'` 的 nullable fallback 寫法（Issue 2 審查 `review-issue-2.md` Important #1 確立的教訓，Issue 3 審查驗證未重現）。
- **`initState()` 存取 l10n 陷阱（Issue 3 審查 `review-plan-issue-3.md` C-1 確立的鐵律）**：任何 `State.initState()` 執行期間呼叫 `AppLocalizations.of(context)!`（透過 `context.dependOnInheritedWidgetOfExactType()`）會拋出 `FlutterError`——框架要到 `initState()` 返回後才將 `_debugLifecycleState` 轉為 `initialized`。本 Issue 多個 `StatefulWidget`（`PdfThumbnailPanel`／`PdfSearchPanel`／`TocBottomSheet`／`NotesBottomSheet`／`ReaderSettingsSheet`／`FxlSettingsSheet`／`PdfSettingsSheet`）皆有 `initState()`，但逐一核對後這些 `initState()` 內容皆只讀取 `widget.prefs`／設定本地 state 欄位，不涉及任何字串/l10n 存取，故不受影響；`reader_screen.dart` 的 `_ReaderScreenState.initState()` 同樣不直接呼叫任何新增的 l10n key（見 Task 18/19 逐一確認）。
- ICU plural 全域規則：任何計數字串（英文有單複數變化）一律用 ARB `plural` 語法；中文三語言（`zh_TW`/`zh_CN`/`zh`）雖無文法複數變化，仍比照既有先例維持 `plural` 語法結構（`=1{...} other{...}` 兩分支填相同中文措辭）。本 Issue 逐一盤點後**沒有發現**需要 ICU plural 的計數字串（與 Issue 3 不同，本模組字串多為固定選項標籤/tooltip，唯一疑似計數情境是 `PdfSearchPanel`／`_TtsSleepTimerSheet` 的位置計數，但這些是格式化的「目前索引 / 總數」或分鐘數字，非「N 個項目」式單複數句子，不套用 plural）。
- 字型品牌名不翻譯：`reader_settings_sheet.dart._fontDisplayName()` 回傳的思源黑體／思源宋體／原俠正楷／台灣圓體／源流明體五個字型顯示名稱維持原樣不抽取（`design.md` 排除範圍，比照 Issue 5 `font_management_screen.dart` 既有原則）。
- 既有測試檔遷移至 `pumpLocalizedWidget()`（`app/test/support/pump_localized_widget.dart`）；若測試檔以自訂 helper（例如 `_wrap()`/`_open()`/`_buildApp()`）包裝 `MaterialApp`，直接在該 helper 內補上 `localizationsDelegates`/`supportedLocales`/`locale` 參數，不強制呼叫端改用 `pumpLocalizedWidget()` 本身。
- 測試執行範圍：單一 Task 完成後只跑該 Task 觸及的測試檔；完整 `flutter test`／`flutter analyze` 僅在 Task 21（最後一個 Task）執行一次。
- Commit 訊息前綴統一 `feat(epic-45):`，Task 21 除外用 `docs(epic-45):`。

---

### Task 1: `reader_chrome_top_bar.dart`

**Files:**
- Modify: `app/lib/screens/reader_chrome_top_bar.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/reader_chrome_top_bar_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`。
- Produces：ARB key `readerBackTooltip`/`readerSearchTooltip`/`readerHideToolbarTooltip`/`readerShowToolbarTooltip`。

- [x] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 檔尾新增：
```json
  "readerBackTooltip": "返回",
  "@readerBackTooltip": {
    "description": "閱讀器頂部 Chrome 列返回按鈕的無障礙提示文字"
  },
  "readerSearchTooltip": "搜尋內文",
  "@readerSearchTooltip": {
    "description": "閱讀器頂部 Chrome 列搜尋按鈕的無障礙提示文字"
  },
  "readerHideToolbarTooltip": "隱藏工具列",
  "@readerHideToolbarTooltip": {
    "description": "閱讀器頂部 Chrome 列收合底部工具列按鈕的提示文字（底部工具列目前顯示中）"
  },
  "readerShowToolbarTooltip": "顯示工具列",
  "@readerShowToolbarTooltip": {
    "description": "閱讀器頂部 Chrome 列展開底部工具列按鈕的提示文字（底部工具列目前收合中）"
  }
```

`app_zh_CN.arb` 檔尾新增：
```json
  "readerBackTooltip": "返回",
  "readerSearchTooltip": "搜索内文",
  "readerHideToolbarTooltip": "隐藏工具栏",
  "readerShowToolbarTooltip": "显示工具栏"
```

`app_en.arb` 檔尾新增：
```json
  "readerBackTooltip": "Back",
  "readerSearchTooltip": "Search in book",
  "readerHideToolbarTooltip": "Hide toolbar",
  "readerShowToolbarTooltip": "Show toolbar"
```

`app_zh.arb` 檔尾新增：
```json
  "readerBackTooltip": "返回",
  "readerSearchTooltip": "搜尋內文",
  "readerHideToolbarTooltip": "隱藏工具列",
  "readerShowToolbarTooltip": "顯示工具列"
```

- [x] **Step 2: 執行 `flutter gen-l10n`**

Run: `flutter gen-l10n`
Expected: 無錯誤。

- [x] **Step 3: 修改 `reader_chrome_top_bar.dart`**

在檔案頂部新增 import：
```dart
import '../l10n/app_localizations.dart';
```

`build()` 方法內新增一行取得 `l10n`，並替換 3 處 tooltip 字面值（其餘程式碼原樣不動）：

```dart
  @override
  Widget build(BuildContext context) {
    // 三組皆不需要顯示時整個不佔版面（全沉浸體驗）。
    if (!isHeaderVisible && !isToolbarVisible && !showTtsIndicator) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    // ...（_height／minSize／buttonStyle／borderColor 計算原樣不動）
```

3 處字面值替換（依原檔案行號，僅替換 `tooltip:` 這一行的值，其餘 `IconButton` 建構參數不變）：
- 第 102 行 `tooltip: '返回',` → `tooltip: l10n.readerBackTooltip,`
- 第 134 行 `tooltip: '搜尋內文',` → `tooltip: l10n.readerSearchTooltip,`
- 第 143 行 `tooltip: isBottomChromeVisible ? '隱藏工具列' : '顯示工具列',` → `tooltip: isBottomChromeVisible ? l10n.readerHideToolbarTooltip : l10n.readerShowToolbarTooltip,`

- [x] **Step 4: 遷移既有測試檔**

`app/test/screens/reader_chrome_top_bar_test.dart` 有 1 處 `MaterialApp(`。找到該處呼叫，補上：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```
並在該 `MaterialApp(` 建構式內新增：
```dart
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
```
（保留原有 `theme:`/`home:` 等既有參數不動；若該檔案沒有指定 `locale:`，維持不指定——`pumpLocalizedWidget()` 的既有慣例是預設 `zh_TW`，但這裡是直接在既有 `MaterialApp(` 補參數，不引入 `pumpLocalizedWidget()`，`Flutter` 在未指定 `locale` 時會用系統/測試環境 locale 解析；為避免非決定性，額外明確加上 `locale: const Locale('zh', 'TW'),`）。

- [x] **Step 5: 新增三語言渲染驗證測試**

在檔案 `main()` 最後一個 `testWidgets` 之後新增：
```dart
  testWidgets('英文介面下返回/搜尋 tooltip 正確以英文渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ReaderChromeTopBar(
          onBack: () {},
          chapterTitle: 'Chapter 1',
          onSearchTap: () {},
          isHeaderVisible: true,
          isToolbarVisible: true,
          isBottomChromeVisible: true,
          onToggleBottomChrome: () {},
          showTtsIndicator: false,
          backgroundColor: Colors.white,
          iconColor: Colors.black,
        ),
      ),
    );

    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Search in book'), findsOneWidget);
  });
```

> 若上述建構參數與檔案既有 `testWidgets` 實際使用的建構寫法不完全一致（例如既有測試已有可重用的 `_buildTopBar()` helper），改用該 helper 並傳入 `locale: const Locale('en')`，斷言邏輯不變。

- [x] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/reader_chrome_top_bar_test.dart`
Expected: 全數通過（既有＋新增 1 個）。

- [x] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/reader_chrome_top_bar.dart test/screens/reader_chrome_top_bar_test.dart`
Expected: No issues found!

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/reader_chrome_top_bar.dart app/test/screens/reader_chrome_top_bar_test.dart app/lib/l10n/
git commit -m "feat(epic-45): reader_chrome_top_bar.dart 字串抽取三語言在地化"
```

---

### Task 2: `reader_chrome_bottom_bar.dart`

**Files:**
- Modify: `app/lib/screens/reader_chrome_bottom_bar.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/reader_chrome_bottom_bar_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`。
- Produces：ARB key `readerTocTooltip`/`readerBookmarkAddedTooltip`/`readerBookmarkAddTooltip`/`readerAnnotationsTooltip`/`readerLayoutTooltip`/`readerTtsTooltip`。

- [x] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 檔尾新增：
```json
  "readerTocTooltip": "目錄",
  "@readerTocTooltip": {
    "description": "閱讀器底部選單列「目錄」按鈕的無障礙提示文字"
  },
  "readerBookmarkAddedTooltip": "已加入此頁書籤",
  "@readerBookmarkAddedTooltip": {
    "description": "閱讀器底部選單列書籤按鈕提示文字：目前頁已加入書籤"
  },
  "readerBookmarkAddTooltip": "加入此頁書籤",
  "@readerBookmarkAddTooltip": {
    "description": "閱讀器底部選單列書籤按鈕提示文字：目前頁尚未加入書籤"
  },
  "readerAnnotationsTooltip": "劃線筆記",
  "@readerAnnotationsTooltip": {
    "description": "閱讀器底部選單列「劃線筆記」按鈕的無障礙提示文字"
  },
  "readerLayoutTooltip": "版面",
  "@readerLayoutTooltip": {
    "description": "閱讀器底部選單列「版面」按鈕的無障礙提示文字"
  },
  "readerTtsTooltip": "朗讀",
  "@readerTtsTooltip": {
    "description": "閱讀器底部選單列「朗讀」按鈕的無障礙提示文字"
  }
```

`app_zh_CN.arb` 檔尾新增：
```json
  "readerTocTooltip": "目录",
  "readerBookmarkAddedTooltip": "已加入此页书签",
  "readerBookmarkAddTooltip": "加入此页书签",
  "readerAnnotationsTooltip": "划线笔记",
  "readerLayoutTooltip": "版面",
  "readerTtsTooltip": "朗读"
```

`app_en.arb` 檔尾新增：
```json
  "readerTocTooltip": "Table of contents",
  "readerBookmarkAddedTooltip": "Bookmarked",
  "readerBookmarkAddTooltip": "Add bookmark",
  "readerAnnotationsTooltip": "Highlights & notes",
  "readerLayoutTooltip": "Layout",
  "readerTtsTooltip": "Read aloud"
```

`app_zh.arb` 檔尾新增：
```json
  "readerTocTooltip": "目錄",
  "readerBookmarkAddedTooltip": "已加入此頁書籤",
  "readerBookmarkAddTooltip": "加入此頁書籤",
  "readerAnnotationsTooltip": "劃線筆記",
  "readerLayoutTooltip": "版面",
  "readerTtsTooltip": "朗讀"
```

- [x] **Step 2: 執行 `flutter gen-l10n`**

Run: `flutter gen-l10n`
Expected: 無錯誤。

- [x] **Step 3: 修改 `reader_chrome_bottom_bar.dart`**

新增 import：
```dart
import '../l10n/app_localizations.dart';
```

`build()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`（緊接 `final minSize = ...` 之前），並替換 6 處 tooltip：
- `tooltip: '目錄',` → `tooltip: l10n.readerTocTooltip,`
- `tooltip: isBookmarked ? '已加入此頁書籤' : '加入此頁書籤',` → `tooltip: isBookmarked ? l10n.readerBookmarkAddedTooltip : l10n.readerBookmarkAddTooltip,`
- `tooltip: '劃線筆記',` → `tooltip: l10n.readerAnnotationsTooltip,`
- `tooltip: '版面',` → `tooltip: l10n.readerLayoutTooltip,`
- `tooltip: '朗讀',` → `tooltip: l10n.readerTtsTooltip,`

其餘 `Row`／`DecoratedBox`／`Material` 版面結構原樣不動。

- [x] **Step 4: 遷移既有測試檔**

`app/test/screens/reader_chrome_bottom_bar_test.dart` 1 處 `MaterialApp(`，比照 Task 1 Step 4 補上 `localizationsDelegates`/`supportedLocales`/`locale: const Locale('zh', 'TW')`。

- [x] **Step 5: 新增三語言渲染驗證測試**

新增一則 `testWidgets('英文介面下選單列 tooltip 正確以英文渲染', ...)`，沿用檔案既有的 `ReaderChromeBottomBar` 建構寫法（`bookTitle`/`pageProgressText`/`footer`/`onTocTap`/`isBookmarked`/`onBookmarkTap`/`onAnnotationsTap`/`onLayoutTap`/`onTtsTap`/`backgroundColor`/`iconColor` 皆填入非 null 測試值，其中 `onTtsTap` 需非 null 才會渲染朗讀按鈕），把 `locale` 改為 `const Locale('en')`，斷言 `find.byTooltip('Table of contents')`／`find.byTooltip('Highlights & notes')`／`find.byTooltip('Layout')`／`find.byTooltip('Read aloud')` 皆 `findsOneWidget`。

- [x] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/reader_chrome_bottom_bar_test.dart`

- [x] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/reader_chrome_bottom_bar.dart test/screens/reader_chrome_bottom_bar_test.dart`

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/reader_chrome_bottom_bar.dart app/test/screens/reader_chrome_bottom_bar_test.dart app/lib/l10n/
git commit -m "feat(epic-45): reader_chrome_bottom_bar.dart 字串抽取三語言在地化"
```

---

### Task 3: `widgets/paging_bar.dart`

**Files:**
- Modify: `app/lib/screens/widgets/paging_bar.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/widgets/paging_bar_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`。
- Produces：ARB key `readerPagingPreviousTooltip`/`readerPagingNextTooltip`。

- [x] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "readerPagingPreviousTooltip": "上一頁",
  "@readerPagingPreviousTooltip": {
    "description": "PagingBar「上一頁」按鈕的無障礙提示文字"
  },
  "readerPagingNextTooltip": "下一頁",
  "@readerPagingNextTooltip": {
    "description": "PagingBar「下一頁」按鈕的無障礙提示文字"
  }
```

`app_zh_CN.arb`：
```json
  "readerPagingPreviousTooltip": "上一页",
  "readerPagingNextTooltip": "下一页"
```

`app_en.arb`：
```json
  "readerPagingPreviousTooltip": "Previous page",
  "readerPagingNextTooltip": "Next page"
```

`app_zh.arb`：
```json
  "readerPagingPreviousTooltip": "上一頁",
  "readerPagingNextTooltip": "下一頁"
```

- [x] **Step 2: 執行 `flutter gen-l10n`**

- [x] **Step 3: 修改 `paging_bar.dart`**

新增 import：`import '../../l10n/app_localizations.dart';`（本檔案在 `screens/widgets/` 下，相對路徑為兩層）。

`build()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`，替換：
- `tooltip: '上一頁',` → `tooltip: l10n.readerPagingPreviousTooltip,`
- `tooltip: '下一頁',` → `tooltip: l10n.readerPagingNextTooltip,`

`Text('${currentPage + 1} / $pageCount')` 為純數字格式，不需要翻譯，原樣保留。

- [x] **Step 4: 遷移既有測試檔（8 處 `MaterialApp(`）**

`app/test/screens/widgets/paging_bar_test.dart` 8 處皆補上 `localizationsDelegates`/`supportedLocales`/`locale: const Locale('zh', 'TW')`（若檔案已有共用 helper 包裝 `MaterialApp`，只需修改該 helper 一處）。

- [x] **Step 5: 新增三語言渲染驗證測試**

新增 `testWidgets('英文介面下上一頁/下一頁 tooltip 正確以英文渲染', ...)`，沿用既有 `PagingBar` 建構寫法，`locale: const Locale('en')`，斷言 `find.byTooltip('Previous page')`／`find.byTooltip('Next page')` 皆 `findsOneWidget`。

- [x] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/widgets/paging_bar_test.dart`

- [x] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/widgets/paging_bar.dart test/screens/widgets/paging_bar_test.dart`

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/widgets/paging_bar.dart app/test/screens/widgets/paging_bar_test.dart app/lib/l10n/
git commit -m "feat(epic-45): paging_bar.dart 字串抽取三語言在地化"
```

---

### Task 4: `pdf_thumbnail_panel.dart`

**Files:**
- Modify: `app/lib/screens/pdf_thumbnail_panel.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/pdf_thumbnail_panel_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`。
- Produces：ARB key `readerPdfNoPagesAvailable`。

- [x] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "readerPdfNoPagesAvailable": "無可用頁面",
  "@readerPdfNoPagesAvailable": {
    "description": "PDF 縮圖面板在 totalPages <= 0 時顯示的空狀態文字"
  }
```

`app_zh_CN.arb`：`"readerPdfNoPagesAvailable": "无可用页面"`

`app_en.arb`：`"readerPdfNoPagesAvailable": "No pages available"`

`app_zh.arb`：`"readerPdfNoPagesAvailable": "無可用頁面"`

- [x] **Step 2: 執行 `flutter gen-l10n`**

- [x] **Step 3: 修改 `pdf_thumbnail_panel.dart`**

新增 import：`import '../l10n/app_localizations.dart';`

`build()` 方法：
```dart
  @override
  Widget build(BuildContext context) {
    if (widget.totalPages <= 0) {
      return Center(
        key: const Key('pdf_thumbnail_panel_empty'),
        child: Text(AppLocalizations.of(context)!.readerPdfNoPagesAvailable),
      );
    }
    // ...（GridView.builder 以下原樣不動）
```

（原本 `const Center(...)` 因內容改為動態不再能是 `const`，移除 `const` 關鍵字。）

- [x] **Step 4: 遷移既有測試檔（9 處 `MaterialApp(`）**

`app/test/screens/pdf_thumbnail_panel_test.dart` 9 處補上 `localizationsDelegates`/`supportedLocales`/`locale`（同樣優先修改共用 helper，若存在）。

- [x] **Step 5: 新增英文渲染驗證測試**

新增 `testWidgets('英文介面下無頁面時顯示英文空狀態文字', ...)`，建構 `PdfThumbnailPanel(totalPages: 0, ...)`，`locale: const Locale('en')`，斷言 `find.text('No pages available')` `findsOneWidget`。

- [x] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/pdf_thumbnail_panel_test.dart`

- [x] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/pdf_thumbnail_panel.dart test/screens/pdf_thumbnail_panel_test.dart`

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/pdf_thumbnail_panel.dart app/test/screens/pdf_thumbnail_panel_test.dart app/lib/l10n/
git commit -m "feat(epic-45): pdf_thumbnail_panel.dart 字串抽取三語言在地化"
```

---

### Task 5: `note_edit_dialog.dart`

**Files:**
- Modify: `app/lib/screens/note_edit_dialog.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/note_edit_dialog_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`；`cancel`（Issue 2 既有共用 key）。
- Produces：ARB key `readerNoteDialogSaveButton`/`readerNoteDialogDefaultTitle`。

**計劃範圍澄清**：`showNoteTextDialog(BuildContext context, {String initialText = '', String title = '備註'})` 的 `title` 具名參數預設值 `'備註'`——查證全部 3 個呼叫端（`reader_screen.dart` 2 處、`notes_bottom_sheet.dart` 1 處）皆明確傳入 `title:`（見 Task 18/Task 11），這個預設值在目前程式碼中不可觸及。但 `showNoteTextDialog` 本身即接收 `BuildContext context` 作為函式參數（不同於 `ReaderScreen.bookTitle` 是「widget 建構子預設值」、必須是編譯期常數的限制），故本 Task 直接把預設值改為 `null`、在函式本體內用 `title ?? AppLocalizations.of(context)!.readerNoteDialogDefaultTitle` 解析，比 Task 18 的 `bookTitle` 處理更單純，不需要拆 `FutureBuilder`。

- [x] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "readerNoteDialogSaveButton": "儲存",
  "@readerNoteDialogSaveButton": {
    "description": "備註編輯對話框「儲存」按鈕文字"
  },
  "readerNoteDialogDefaultTitle": "備註",
  "@readerNoteDialogDefaultTitle": {
    "description": "showNoteTextDialog() 呼叫端未明確指定 title 時的預設對話框標題（目前所有呼叫端皆明確指定，此為防禦性預設值）"
  }
```

`app_zh_CN.arb`：
```json
  "readerNoteDialogSaveButton": "保存",
  "readerNoteDialogDefaultTitle": "备注"
```

`app_en.arb`：
```json
  "readerNoteDialogSaveButton": "Save",
  "readerNoteDialogDefaultTitle": "Note"
```

`app_zh.arb`：
```json
  "readerNoteDialogSaveButton": "儲存",
  "readerNoteDialogDefaultTitle": "備註"
```

- [x] **Step 2: 執行 `flutter gen-l10n`**

- [x] **Step 3: 修改 `note_edit_dialog.dart`**

```dart
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// （原有 class 文件註解不動）
Future<String?> showNoteTextDialog(
  BuildContext context, {
  String initialText = '',
  String? title,
}) {
  final resolvedTitle = title ?? AppLocalizations.of(context)!.readerNoteDialogDefaultTitle;
  return showDialog<String>(
    context: context,
    builder: (dialogContext) =>
        _NoteTextDialog(initialText: initialText, title: resolvedTitle),
  );
}
```

`_NoteTextDialog`／`_NoteTextDialogState` 的欄位/建構子/`initState`/`dispose` 原樣不動（`title` 欄位型別仍是 `String`，因為傳進去的已經是解析後的非 null 字串）。`build()` 內取代兩處字面值：

```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('note_edit_dialog_field'),
        controller: _controller,
        autofocus: true,
        maxLines: 4,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const Key('note_edit_dialog_confirm'),
          onPressed: () {
            final text = _controller.text.trim();
            Navigator.of(context).pop(text.isEmpty ? null : text);
          },
          child: Text(l10n.readerNoteDialogSaveButton),
        ),
      ],
    );
  }
```

- [x] **Step 4: 遷移既有測試檔（4 處 `MaterialApp(`）**

`app/test/screens/note_edit_dialog_test.dart` 4 處補上 l10n 三參數。既有測試若有斷言預設標題「備註」的案例（呼叫 `showNoteTextDialog(context)` 不傳 `title`），因預設 locale 為 `zh_TW`，斷言值不變、無需修改斷言內容。

- [x] **Step 5: 新增英文渲染驗證測試**

新增 `testWidgets('英文介面下取消/儲存按鈕正確以英文渲染', ...)`，`locale: const Locale('en')`，斷言 `find.text('Cancel')`／`find.text('Save')` `findsOneWidget`。

- [x] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/note_edit_dialog_test.dart`

- [x] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/note_edit_dialog.dart test/screens/note_edit_dialog_test.dart`

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/note_edit_dialog.dart app/test/screens/note_edit_dialog_test.dart app/lib/l10n/
git commit -m "feat(epic-45): note_edit_dialog.dart 字串抽取三語言在地化"
```

---

### Task 6: `annotation_toolbar.dart`

**Files:**
- Modify: `app/lib/screens/annotation_toolbar.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/annotation_toolbar_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`；`close`（Issue 0 既有共用 key，`關閉` tooltip 直接複用，不新增）。
- Produces：ARB key `readerAnnotationUnderlineTooltip`/`readerAnnotationCopyTooltip`/`readerAnnotationEditNoteTooltip`/`readerAnnotationAddNoteTooltip`/`readerAnnotationDeleteHighlightAndNote`/`readerAnnotationDeleteHighlight`/`readerAnnotationDeleteNote`（後三個供 Task 18 的 `reader_screen.dart._annotationDeleteButtonLabel()` 使用）。

- [x] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "readerAnnotationUnderlineTooltip": "底線",
  "@readerAnnotationUnderlineTooltip": {
    "description": "選字浮動工具列「底線」樣式按鈕的無障礙提示文字"
  },
  "readerAnnotationCopyTooltip": "複製",
  "@readerAnnotationCopyTooltip": {
    "description": "選字浮動工具列「複製」按鈕的無障礙提示文字"
  },
  "readerAnnotationEditNoteTooltip": "編輯備註",
  "@readerAnnotationEditNoteTooltip": {
    "description": "選字浮動工具列備註按鈕提示文字：這次選取已有備註"
  },
  "readerAnnotationAddNoteTooltip": "新增備註",
  "@readerAnnotationAddNoteTooltip": {
    "description": "選字浮動工具列備註按鈕提示文字：這次選取尚無備註"
  },
  "readerAnnotationDeleteHighlightAndNote": "刪除畫線與備註",
  "@readerAnnotationDeleteHighlightAndNote": {
    "description": "選字浮動工具列刪除按鈕提示文字：這次選取同時命中劃線與備註"
  },
  "readerAnnotationDeleteHighlight": "刪除畫線",
  "@readerAnnotationDeleteHighlight": {
    "description": "選字浮動工具列刪除按鈕提示文字：這次選取只命中劃線"
  },
  "readerAnnotationDeleteNote": "刪除備註",
  "@readerAnnotationDeleteNote": {
    "description": "選字浮動工具列刪除按鈕提示文字：這次選取只命中備註"
  }
```

`app_zh_CN.arb`：
```json
  "readerAnnotationUnderlineTooltip": "底线",
  "readerAnnotationCopyTooltip": "复制",
  "readerAnnotationEditNoteTooltip": "编辑备注",
  "readerAnnotationAddNoteTooltip": "新增备注",
  "readerAnnotationDeleteHighlightAndNote": "删除划线与备注",
  "readerAnnotationDeleteHighlight": "删除划线",
  "readerAnnotationDeleteNote": "删除备注"
```

`app_en.arb`：
```json
  "readerAnnotationUnderlineTooltip": "Underline",
  "readerAnnotationCopyTooltip": "Copy",
  "readerAnnotationEditNoteTooltip": "Edit note",
  "readerAnnotationAddNoteTooltip": "Add note",
  "readerAnnotationDeleteHighlightAndNote": "Delete highlight & note",
  "readerAnnotationDeleteHighlight": "Delete highlight",
  "readerAnnotationDeleteNote": "Delete note"
```

`app_zh.arb`：
```json
  "readerAnnotationUnderlineTooltip": "底線",
  "readerAnnotationCopyTooltip": "複製",
  "readerAnnotationEditNoteTooltip": "編輯備註",
  "readerAnnotationAddNoteTooltip": "新增備註",
  "readerAnnotationDeleteHighlightAndNote": "刪除畫線與備註",
  "readerAnnotationDeleteHighlight": "刪除畫線",
  "readerAnnotationDeleteNote": "刪除備註"
```

- [x] **Step 2: 執行 `flutter gen-l10n`**

- [x] **Step 3: 修改 `annotation_toolbar.dart`**

新增 import：`import '../l10n/app_localizations.dart';`

`build()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`（緊接 `final tokens = ...`／`final colorScheme = ...` 之後），替換 4 處字面值：
- `tooltip: '底線',` → `tooltip: l10n.readerAnnotationUnderlineTooltip,`
- `tooltip: '關閉',` → `tooltip: l10n.close,`（複用 Issue 0 既有共用 key，不新增）
- `tooltip: '複製',` → `tooltip: l10n.readerAnnotationCopyTooltip,`
- `tooltip: hasExistingNote ? '編輯備註' : '新增備註',` → `tooltip: hasExistingNote ? l10n.readerAnnotationEditNoteTooltip : l10n.readerAnnotationAddNoteTooltip,`

- [x] **Step 4: 遷移既有測試檔（14 處 `MaterialApp(`）**

`app/test/screens/annotation_toolbar_test.dart` 14 處補上 l10n 三參數（優先修改共用 helper）。

- [x] **Step 5: 新增英文渲染驗證測試**

新增 `testWidgets('英文介面下底線/關閉/複製/備註 tooltip 正確以英文渲染', ...)`，`locale: const Locale('en')`，斷言 `find.byTooltip('Underline')`／`find.byTooltip('Close')`／`find.byTooltip('Copy')`／`find.byTooltip('Add note')` 皆 `findsOneWidget`。

- [x] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/annotation_toolbar_test.dart`

- [x] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/annotation_toolbar.dart test/screens/annotation_toolbar_test.dart`

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/annotation_toolbar.dart app/test/screens/annotation_toolbar_test.dart app/lib/l10n/
git commit -m "feat(epic-45): annotation_toolbar.dart 字串抽取三語言在地化"
```

---

### Task 7: `pdf_search_panel.dart`

**Files:**
- Modify: `app/lib/screens/pdf_search_panel.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/pdf_search_panel_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`。
- Produces：ARB key `readerPdfSearchHint`/`readerPdfSearchNoMatches`/`readerPdfSearchPreviousTooltip`/`readerPdfSearchNextTooltip`。

- [x] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "readerPdfSearchHint": "搜尋文字…",
  "@readerPdfSearchHint": {
    "description": "PDF 內文搜尋面板輸入框的 hintText"
  },
  "readerPdfSearchNoMatches": "找不到符合的文字",
  "@readerPdfSearchNoMatches": {
    "description": "PDF 內文搜尋查無結果時的提示文字"
  },
  "readerPdfSearchPreviousTooltip": "上一個",
  "@readerPdfSearchPreviousTooltip": {
    "description": "PDF 內文搜尋「上一個」按鈕的無障礙提示文字"
  },
  "readerPdfSearchNextTooltip": "下一個",
  "@readerPdfSearchNextTooltip": {
    "description": "PDF 內文搜尋「下一個」按鈕的無障礙提示文字"
  }
```

`app_zh_CN.arb`：
```json
  "readerPdfSearchHint": "搜索文字…",
  "readerPdfSearchNoMatches": "找不到符合的文字",
  "readerPdfSearchPreviousTooltip": "上一个",
  "readerPdfSearchNextTooltip": "下一个"
```

`app_en.arb`：
```json
  "readerPdfSearchHint": "Search text…",
  "readerPdfSearchNoMatches": "No matching text found",
  "readerPdfSearchPreviousTooltip": "Previous",
  "readerPdfSearchNextTooltip": "Next"
```

`app_zh.arb`：
```json
  "readerPdfSearchHint": "搜尋文字…",
  "readerPdfSearchNoMatches": "找不到符合的文字",
  "readerPdfSearchPreviousTooltip": "上一個",
  "readerPdfSearchNextTooltip": "下一個"
```

- [x] **Step 2: 執行 `flutter gen-l10n`**

- [x] **Step 3: 修改 `pdf_search_panel.dart`**

新增 import：`import '../l10n/app_localizations.dart';`

`build()` 方法（`_PdfSearchPanelState`）：
```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('pdf_search_field'),
            controller: _controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l10n.readerPdfSearchHint,
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: _handleChanged,
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<PdfSearchState>(
            valueListenable: widget.searchStateListenable,
            builder: (context, state, _) {
              if (state.query.isEmpty) return const SizedBox.shrink();
              if (state.isSearching) {
                return const Padding(
                  key: Key('pdf_search_loading'),
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (state.matchCount == 0) {
                return Padding(
                  key: const Key('pdf_search_empty'),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: Text(l10n.readerPdfSearchNoMatches)),
                );
              }
              return Row(
                key: const Key('pdf_search_counter'),
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${(state.currentIndex ?? 0) + 1} / ${state.matchCount}'),
                  Row(
                    children: [
                      IconButton(
                        key: const Key('pdf_search_prev_button'),
                        icon: const Icon(Icons.keyboard_arrow_up),
                        tooltip: l10n.readerPdfSearchPreviousTooltip,
                        onPressed: widget.onPrevious,
                      ),
                      IconButton(
                        key: const Key('pdf_search_next_button'),
                        icon: const Icon(Icons.keyboard_arrow_down),
                        tooltip: l10n.readerPdfSearchNextTooltip,
                        onPressed: widget.onNext,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
```

（`state.matchCount`／`state.currentIndex` 組成的 `'N / M'` 是純數字格式，不需要 ICU plural，原樣保留。）

- [x] **Step 4: 遷移既有測試檔（7 處 `MaterialApp(`）**

`app/test/screens/pdf_search_panel_test.dart` 7 處補上 l10n 三參數。

- [x] **Step 5: 新增英文渲染驗證測試**

新增 `testWidgets('英文介面下搜尋提示與上一個/下一個 tooltip 正確以英文渲染', ...)`，`locale: const Locale('en')`，斷言輸入框 hint 與 `find.byTooltip('Previous')`／`find.byTooltip('Next')`（觸發搜尋有結果情境）。

- [x] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/pdf_search_panel_test.dart`

- [x] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/pdf_search_panel.dart test/screens/pdf_search_panel_test.dart`

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/pdf_search_panel.dart app/test/screens/pdf_search_panel_test.dart app/lib/l10n/
git commit -m "feat(epic-45): pdf_search_panel.dart 字串抽取三語言在地化"
```

---

### Task 8: `reading_position_conflict_dialog.dart`

**Files:**
- Modify: `app/lib/screens/reading_position_conflict_dialog.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/reading_position_conflict_dialog_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`；`cancel`（不使用，本對話框無取消按鈕）。
- Produces：ARB key `readerPositionConflictTitle`/`readerPositionConflictMessage`/`readerPositionConflictPdfLocation`/`readerPositionConflictEpubLocation`/`readerPositionConflictKeepCloud`/`readerPositionConflictKeepLocal`。

**計劃範圍澄清**：`_describeReadingPosition()` 是頂層私有函式（非 Widget 方法），目前簽章 `String _describeReadingPosition(ReadingPositionSnapshot snapshot, BookFileFormat format)` 沒有 `BuildContext`／`AppLocalizations` 可用。本 Task 新增 `AppLocalizations l10n` 參數，由唯一呼叫端 `showReadingPositionConflictDialog()` 的 `builder:` 回呼內（已持有 `dialogContext`）解析後傳入。

- [x] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "readerPositionConflictTitle": "「{bookTitle}」的閱讀進度不一致",
  "@readerPositionConflictTitle": {
    "description": "閱讀位置衝突對話框標題，{bookTitle} 為書名（使用者資料，不翻譯）",
    "placeholders": {
      "bookTitle": {
        "type": "String"
      }
    }
  },
  "readerPositionConflictMessage": "偵測到另一台裝置也更新過這本書的閱讀進度，請選擇要保留哪一邊：\n\n本機：{local}\n雲端：{remote}",
  "@readerPositionConflictMessage": {
    "description": "閱讀位置衝突對話框內容，{local}／{remote} 為已格式化的位置描述文字（readerPositionConflictPdfLocation 或 readerPositionConflictEpubLocation 的結果）",
    "placeholders": {
      "local": {
        "type": "String"
      },
      "remote": {
        "type": "String"
      }
    }
  },
  "readerPositionConflictPdfLocation": "第 {page} 頁（進度 {percent}%）",
  "@readerPositionConflictPdfLocation": {
    "description": "PDF 格式的位置描述，{page} 為頁碼（1-based），{percent} 為進度百分比整數",
    "placeholders": {
      "page": {
        "type": "int"
      },
      "percent": {
        "type": "int"
      }
    }
  },
  "readerPositionConflictEpubLocation": "進度 {percent}%",
  "@readerPositionConflictEpubLocation": {
    "description": "非 PDF 格式（CFI 定位無法簡單轉人類可讀文字）的位置描述，{percent} 為進度百分比整數",
    "placeholders": {
      "percent": {
        "type": "int"
      }
    }
  },
  "readerPositionConflictKeepCloud": "保留雲端",
  "@readerPositionConflictKeepCloud": {
    "description": "閱讀位置衝突對話框「保留雲端」按鈕文字"
  },
  "readerPositionConflictKeepLocal": "保留本機",
  "@readerPositionConflictKeepLocal": {
    "description": "閱讀位置衝突對話框「保留本機」按鈕文字"
  }
```

`app_zh_CN.arb`：
```json
  "readerPositionConflictTitle": "“{bookTitle}”的阅读进度不一致",
  "readerPositionConflictMessage": "侦测到另一台装置也更新过这本书的阅读进度，请选择要保留哪一边：\n\n本机：{local}\n云端：{remote}",
  "readerPositionConflictPdfLocation": "第 {page} 页（进度 {percent}%）",
  "readerPositionConflictEpubLocation": "进度 {percent}%",
  "readerPositionConflictKeepCloud": "保留云端",
  "readerPositionConflictKeepLocal": "保留本机"
```

`app_en.arb`：
```json
  "readerPositionConflictTitle": "Reading position for “{bookTitle}” doesn't match",
  "readerPositionConflictMessage": "Another device also updated the reading position for this book. Choose which one to keep:\n\nThis device: {local}\nCloud: {remote}",
  "readerPositionConflictPdfLocation": "Page {page} ({percent}% progress)",
  "readerPositionConflictEpubLocation": "{percent}% progress",
  "readerPositionConflictKeepCloud": "Keep cloud",
  "readerPositionConflictKeepLocal": "Keep this device"
```

`app_zh.arb`：
```json
  "readerPositionConflictTitle": "「{bookTitle}」的閱讀進度不一致",
  "readerPositionConflictMessage": "偵測到另一台裝置也更新過這本書的閱讀進度，請選擇要保留哪一邊：\n\n本機：{local}\n雲端：{remote}",
  "readerPositionConflictPdfLocation": "第 {page} 頁（進度 {percent}%）",
  "readerPositionConflictEpubLocation": "進度 {percent}%",
  "readerPositionConflictKeepCloud": "保留雲端",
  "readerPositionConflictKeepLocal": "保留本機"
```

- [x] **Step 2: 執行 `flutter gen-l10n`**

- [x] **Step 3: 修改 `reading_position_conflict_dialog.dart`**

```dart
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../library/models/library_enums.dart';
import '../sync/sync_reading_position.dart';

/// 把單一版本的閱讀位置快照轉成人類可讀的描述，供 [showReadingPositionConflictDialog]
/// 顯示——PDF 額外顯示頁碼（1-indexed，[ReadingPositionSnapshot.pdfPageIndex]
/// 本身是 0-indexed），EPUB 僅顯示進度百分比（CFI 定位字串本身無法簡單
/// 轉成人類可讀文字）。
String _describeReadingPosition(
  ReadingPositionSnapshot snapshot,
  BookFileFormat format,
  AppLocalizations l10n,
) {
  final percent = (snapshot.progress * 100).round();
  if (format == BookFileFormat.pdf && snapshot.pdfPageIndex != null) {
    return l10n.readerPositionConflictPdfLocation(
      snapshot.pdfPageIndex! + 1,
      percent,
    );
  }
  return l10n.readerPositionConflictEpubLocation(percent);
}

/// （原有函式文件註解不動）
Future<ReadingPositionChoice?> showReadingPositionConflictDialog(
  BuildContext context,
  ReadingPositionConflict conflict,
) {
  return showDialog<ReadingPositionChoice>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      return AlertDialog(
        title: Text(l10n.readerPositionConflictTitle(conflict.bookTitle)),
        content: Text(
          l10n.readerPositionConflictMessage(
            _describeReadingPosition(conflict.local, conflict.format, l10n),
            _describeReadingPosition(conflict.remote, conflict.format, l10n),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('reading_position_conflict_keep_cloud'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(ReadingPositionChoice.keepCloud),
            child: Text(l10n.readerPositionConflictKeepCloud),
          ),
          TextButton(
            key: const Key('reading_position_conflict_keep_local'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(ReadingPositionChoice.keepLocal),
            child: Text(l10n.readerPositionConflictKeepLocal),
          ),
        ],
      );
    },
  );
}
```

- [x] **Step 4: 遷移既有測試檔（1 處 `MaterialApp(`）**

`app/test/screens/reading_position_conflict_dialog_test.dart` 補上 l10n 三參數。既有斷言若用 `find.textContaining(...)` 比對組合後的中文訊息，因預設 `zh_TW`、且組合結果與原字面值相同，不需修改斷言內容。

- [x] **Step 5: 新增英文渲染驗證測試**

新增 `testWidgets('英文介面下標題/訊息/按鈕正確以英文渲染', ...)`，`locale: const Locale('en')`，斷言 `find.textContaining('doesn't match')`／`find.text('Keep cloud')`／`find.text('Keep this device')`。

- [x] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/reading_position_conflict_dialog_test.dart`

- [x] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/reading_position_conflict_dialog.dart test/screens/reading_position_conflict_dialog_test.dart`

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/reading_position_conflict_dialog.dart app/test/screens/reading_position_conflict_dialog_test.dart app/lib/l10n/
git commit -m "feat(epic-45): reading_position_conflict_dialog.dart 字串抽取三語言在地化"
```

---

### Task 9: `toc_bottom_sheet.dart`

**Files:**
- Modify: `app/lib/screens/toc_bottom_sheet.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/toc_bottom_sheet_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`。
- Produces：ARB key `readerTocTitle`/`readerTocEmptyMessage`/`readerTocTabChapters`/`readerTocTabThumbnails`/`readerTocTabSearch`/`readerFeatureComingSoon`。

- [x] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "readerTocTitle": "📖 目錄",
  "@readerTocTitle": {
    "description": "目錄 Bottom Sheet 標題列文字（含書本 Emoji，比照既有設計慣例保留）"
  },
  "readerTocEmptyMessage": "本書無目錄資料",
  "@readerTocEmptyMessage": {
    "description": "本書解析不出任何目錄項目時的空狀態提示"
  },
  "readerTocTabChapters": "章節目錄",
  "@readerTocTabChapters": {
    "description": "PDF 目錄 Bottom Sheet 第一個分頁籤：章節目錄"
  },
  "readerTocTabThumbnails": "縮圖",
  "@readerTocTabThumbnails": {
    "description": "PDF 目錄 Bottom Sheet 第二個分頁籤：頁碼縮圖"
  },
  "readerTocTabSearch": "搜尋",
  "@readerTocTabSearch": {
    "description": "PDF 目錄 Bottom Sheet 第三個分頁籤：內文搜尋"
  },
  "readerFeatureComingSoon": "此功能將於後續版本提供",
  "@readerFeatureComingSoon": {
    "description": "縮圖/搜尋分頁內容為 null 時的佔位文字（目前兩個分頁皆已實作，此為向後相容的防禦性回退）"
  }
```

`app_zh_CN.arb`：
```json
  "readerTocTitle": "📖 目录",
  "readerTocEmptyMessage": "本书无目录资料",
  "readerTocTabChapters": "章节目录",
  "readerTocTabThumbnails": "缩图",
  "readerTocTabSearch": "搜索",
  "readerFeatureComingSoon": "此功能将于后续版本提供"
```

`app_en.arb`：
```json
  "readerTocTitle": "📖 Table of Contents",
  "readerTocEmptyMessage": "This book has no table of contents",
  "readerTocTabChapters": "Chapters",
  "readerTocTabThumbnails": "Thumbnails",
  "readerTocTabSearch": "Search",
  "readerFeatureComingSoon": "This feature is coming in a future version"
```

`app_zh.arb`：
```json
  "readerTocTitle": "📖 目錄",
  "readerTocEmptyMessage": "本書無目錄資料",
  "readerTocTabChapters": "章節目錄",
  "readerTocTabThumbnails": "縮圖",
  "readerTocTabSearch": "搜尋",
  "readerFeatureComingSoon": "此功能將於後續版本提供"
```

- [x] **Step 2: 執行 `flutter gen-l10n`**

- [x] **Step 3: 修改 `toc_bottom_sheet.dart`**

新增 import：`import '../l10n/app_localizations.dart';`

`_buildTocList()` 方法內第一個 `itemBuilder` 分支（index == 0 的標題列）與 `isEmpty` 分支：
```dart
  Widget _buildTocList() {
    final l10n = AppLocalizations.of(context)!;
    final isEmpty = widget.entries.isEmpty;
    return ListView.builder(
      key: const Key('toc_bottom_sheet_list'),
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      itemCount: _visibleRows.length + 1 + (isEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.readerTocTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  key: const Key('toc_bottom_sheet_close_button'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        }
        if (isEmpty && index == 1) {
          return Padding(
            key: const Key('toc_bottom_sheet_empty_text'),
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text(l10n.readerTocEmptyMessage)),
          );
        }
        return _buildEntryRow(_visibleRows[index - 1]);
      },
    );
  }
```

`build()` 方法（PDF 三分頁籤 `TabBar`／`TabBarView`）：
```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: widget.format == BookFormat.pdf
          ? DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  TabBar(
                    tabs: [
                      Tab(text: l10n.readerTocTabChapters),
                      Tab(text: l10n.readerTocTabThumbnails),
                      Tab(text: l10n.readerTocTabSearch),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildTocList(),
                        widget.thumbnailTabContent ??
                            Center(child: Text(l10n.readerFeatureComingSoon)),
                        widget.searchTabContent ??
                            Center(child: Text(l10n.readerFeatureComingSoon)),
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

（`const TabBar(...)` 因子項不再是 `const` 而移除 `const`；`_buildEntryRow()` 方法本身不含硬編碼字串，僅 `pageLabel` 這種純數字/省略號 `'…'`，維持原樣不動。）

- [x] **Step 4: 遷移既有測試檔（8 處 `MaterialApp(`）**

`app/test/screens/toc_bottom_sheet_test.dart` 8 處補上 l10n 三參數。

- [x] **Step 5: 新增英文渲染驗證測試**

新增 `testWidgets('英文介面下標題/空狀態/PDF 分頁籤正確以英文渲染', ...)`，需覆蓋一則 EPUB 情境（斷言 `find.text('📖 Table of Contents')`）與一則 PDF 情境（`format: BookFormat.pdf`，斷言 `find.text('Chapters')`／`find.text('Thumbnails')`／`find.text('Search')`）。

- [x] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/toc_bottom_sheet_test.dart`

- [x] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/toc_bottom_sheet.dart test/screens/toc_bottom_sheet_test.dart`

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/toc_bottom_sheet.dart app/test/screens/toc_bottom_sheet_test.dart app/lib/l10n/
git commit -m "feat(epic-45): toc_bottom_sheet.dart 字串抽取三語言在地化"
```

---

### Task 10: `tts_panel.dart`

**Files:**
- Modify: `app/lib/screens/tts_panel.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/tts_panel_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`。
- Produces：ARB key `readerTtsCbzUnsupportedTooltip`/`readerTtsPreviousTooltip`/`readerTtsPauseTooltip`/`readerTtsPlayTooltip`/`readerTtsNextTooltip`/`readerTtsSpeedTooltip`/`readerTtsVoiceTooltip`/`readerTtsSleepTimerLabel`/`readerTtsSleepTimerLabelWithMinutes`/`readerTtsCollapseLabel`/`readerTtsExpandLabel`/`readerTtsStopLabel`。

- [x] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "readerTtsCbzUnsupportedTooltip": "CBZ 為純圖像格式，不支援語音朗讀",
  "@readerTtsCbzUnsupportedTooltip": {
    "description": "TTS 面板播放鍵在 CBZ（純圖像格式）停用狀態下的提示文字"
  },
  "readerTtsPreviousTooltip": "上一句",
  "@readerTtsPreviousTooltip": {
    "description": "TTS 面板「上一句」按鈕的無障礙提示文字"
  },
  "readerTtsPauseTooltip": "暫停朗讀",
  "@readerTtsPauseTooltip": {
    "description": "TTS 面板播放/暫停鍵提示文字：目前朗讀中，點擊暫停"
  },
  "readerTtsPlayTooltip": "開始朗讀",
  "@readerTtsPlayTooltip": {
    "description": "TTS 面板播放/暫停鍵提示文字：目前暫停中，點擊開始"
  },
  "readerTtsNextTooltip": "下一句",
  "@readerTtsNextTooltip": {
    "description": "TTS 面板「下一句」按鈕的無障礙提示文字"
  },
  "readerTtsSpeedTooltip": "朗讀語速：{speed}x（點擊切換）",
  "@readerTtsSpeedTooltip": {
    "description": "TTS 面板語速按鈕的無障礙提示文字，{speed} 為目前語速（已格式化為小數點後兩位的字串）",
    "placeholders": {
      "speed": {
        "type": "String"
      }
    }
  },
  "readerTtsVoiceTooltip": "選擇語音",
  "@readerTtsVoiceTooltip": {
    "description": "TTS 面板「選擇語音」按鈕的無障礙提示文字"
  },
  "readerTtsSleepTimerLabel": "定時",
  "@readerTtsSleepTimerLabel": {
    "description": "TTS 面板睡眠定時器按鈕文字：尚未設定定時器"
  },
  "readerTtsSleepTimerLabelWithMinutes": "定時 {minutes} 分",
  "@readerTtsSleepTimerLabelWithMinutes": {
    "description": "TTS 面板睡眠定時器按鈕文字：已設定定時器，{minutes} 為剩餘分鐘數",
    "placeholders": {
      "minutes": {
        "type": "int"
      }
    }
  },
  "readerTtsCollapseLabel": "收合",
  "@readerTtsCollapseLabel": {
    "description": "TTS 面板收合/展開按鈕文字：目前展開中，點擊收合"
  },
  "readerTtsExpandLabel": "展開",
  "@readerTtsExpandLabel": {
    "description": "TTS 面板收合/展開按鈕文字：目前收合中，點擊展開"
  },
  "readerTtsStopLabel": "停止",
  "@readerTtsStopLabel": {
    "description": "TTS 面板「停止朗讀」按鈕文字"
  }
```

`app_zh_CN.arb`：
```json
  "readerTtsCbzUnsupportedTooltip": "CBZ 为纯图像格式，不支持语音朗读",
  "readerTtsPreviousTooltip": "上一句",
  "readerTtsPauseTooltip": "暂停朗读",
  "readerTtsPlayTooltip": "开始朗读",
  "readerTtsNextTooltip": "下一句",
  "readerTtsSpeedTooltip": "朗读语速：{speed}x（点击切换）",
  "readerTtsVoiceTooltip": "选择语音",
  "readerTtsSleepTimerLabel": "定时",
  "readerTtsSleepTimerLabelWithMinutes": "定时 {minutes} 分",
  "readerTtsCollapseLabel": "收起",
  "readerTtsExpandLabel": "展开",
  "readerTtsStopLabel": "停止"
```

`app_en.arb`：
```json
  "readerTtsCbzUnsupportedTooltip": "CBZ is image-only and doesn't support read-aloud",
  "readerTtsPreviousTooltip": "Previous sentence",
  "readerTtsPauseTooltip": "Pause",
  "readerTtsPlayTooltip": "Play",
  "readerTtsNextTooltip": "Next sentence",
  "readerTtsSpeedTooltip": "Speed: {speed}x (tap to change)",
  "readerTtsVoiceTooltip": "Choose voice",
  "readerTtsSleepTimerLabel": "Timer",
  "readerTtsSleepTimerLabelWithMinutes": "Timer {minutes} min",
  "readerTtsCollapseLabel": "Collapse",
  "readerTtsExpandLabel": "Expand",
  "readerTtsStopLabel": "Stop"
```

`app_zh.arb`：
```json
  "readerTtsCbzUnsupportedTooltip": "CBZ 為純圖像格式，不支援語音朗讀",
  "readerTtsPreviousTooltip": "上一句",
  "readerTtsPauseTooltip": "暫停朗讀",
  "readerTtsPlayTooltip": "開始朗讀",
  "readerTtsNextTooltip": "下一句",
  "readerTtsSpeedTooltip": "朗讀語速：{speed}x（點擊切換）",
  "readerTtsVoiceTooltip": "選擇語音",
  "readerTtsSleepTimerLabel": "定時",
  "readerTtsSleepTimerLabelWithMinutes": "定時 {minutes} 分",
  "readerTtsCollapseLabel": "收合",
  "readerTtsExpandLabel": "展開",
  "readerTtsStopLabel": "停止"
```

- [x] **Step 2: 執行 `flutter gen-l10n`**

- [x] **Step 3: 修改 `tts_panel.dart`**

新增 import：`import '../l10n/app_localizations.dart';`

`build()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`（緊接 `final playing = ...` 之前），依序替換：
- `tooltip: 'CBZ 為純圖像格式，不支援語音朗讀',` → `tooltip: l10n.readerTtsCbzUnsupportedTooltip,`
- `tooltip: '上一句',` → `tooltip: l10n.readerTtsPreviousTooltip,`
- `tooltip: playing ? '暫停朗讀' : '開始朗讀',` → `tooltip: playing ? l10n.readerTtsPauseTooltip : l10n.readerTtsPlayTooltip,`
- `tooltip: '下一句',` → `tooltip: l10n.readerTtsNextTooltip,`
- `tooltip: '朗讀語速：${speed.toStringAsFixed(2)}x（點擊切換）',` → `tooltip: l10n.readerTtsSpeedTooltip(speed.toStringAsFixed(2)),`
- `tooltip: '選擇語音',` → `tooltip: l10n.readerTtsVoiceTooltip,`
- `label: Text(sleepTimerRemaining == null ? '定時' : '定時 ${sleepTimerRemaining!.inMinutes} 分'),` → `label: Text(sleepTimerRemaining == null ? l10n.readerTtsSleepTimerLabel : l10n.readerTtsSleepTimerLabelWithMinutes(sleepTimerRemaining!.inMinutes)),`
- `label: Text(isCollapsed ? '展開' : '收合'),` → `label: Text(isCollapsed ? l10n.readerTtsExpandLabel : l10n.readerTtsCollapseLabel),`
- `label: const Text('停止'),` → `label: Text(l10n.readerTtsStopLabel),`（移除 `const`）

- [x] **Step 4: 遷移既有測試檔（1 處 `MaterialApp(`）**

`app/test/screens/tts_panel_test.dart` 補上 l10n 三參數。

- [x] **Step 5: 新增英文渲染驗證測試**

新增 `testWidgets('英文介面下播放/收合/停止按鈕文字正確以英文渲染', ...)`，`locale: const Locale('en')`，斷言 `find.byTooltip('Play')` 或 `find.byTooltip('Pause')`（依 `status` 測試值而定）、`find.text('Stop')`。

- [x] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/tts_panel_test.dart`

- [x] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/tts_panel.dart test/screens/tts_panel_test.dart`

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/tts_panel.dart app/test/screens/tts_panel_test.dart app/lib/l10n/
git commit -m "feat(epic-45): tts_panel.dart 字串抽取三語言在地化"
```

---

### Task 11: `notes_bottom_sheet.dart`

**Files:**
- Modify: `app/lib/screens/notes_bottom_sheet.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/notes_bottom_sheet_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`；`cancel`（Issue 2 共用 key）／`readerNoteDialogSaveButton`（Task 5）／`readerBookmarkAddedTooltip`／`readerBookmarkAddTooltip`（Task 2）／`readerAnnotationEditNoteTooltip`／`readerAnnotationAddNoteTooltip`（Task 6，重用其「編輯備註」／「新增備註」文字，同時作為本檔案的按鈕 tooltip 與對話框標題——三處語意相同、文字完全相同）。
- Produces：ARB key `readerNotesSheetTitle`/`readerNotesSheetExportMarkdownTooltip`/`readerNotesSheetTabBookmarks`/`readerNotesSheetTabAnnotations`/`readerNotesSheetDeleteAllBookmarksTooltip`/`readerNotesSheetRenameBookmarkTitle`/`readerDeleteConfirmButton`/`readerNotesSheetDeleteAllBookmarksConfirm`/`readerNotesSheetRenameTooltip`/`readerNotesSheetDeleteItemTooltip`/`readerNotesSheetNoAnnotationsPlaceholder`/`readerNotesSheetDeleteAllHighlightsButton`/`readerNotesSheetDeleteAllNotesButton`/`readerNotesSheetNoteLabel`/`readerHighlightStyleYellow`/`readerHighlightStylePink`/`readerHighlightStyleBlue`/`readerHighlightStyleUnderline`/`readerNotesSheetDeleteAllHighlightsConfirm`/`readerNotesSheetDeleteAllNotesConfirm`。

**計劃範圍澄清（架構必要偏離）**：原始 `_confirmDeleteAll({required String itemLabel, required int count, ...})` 把中文詞彙 `itemLabel`（'劃線'/'備註'）直接嵌進 `'確定要刪除全部$itemLabel嗎？（共 $count 筆）'` 字串模板——這種「詞彙插槽」模式在英文語序下無法正確運作（例如「Delete all highlights?」而非「Delete all $itemLabel?」的直譯語序）。本 Task 改為呼叫端各自傳入**已完整解析好的在地化標題字串**（`title` 參數取代 `itemLabel`），`_confirmDeleteAll` 本身不再組字串。

- [x] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "readerNotesSheetTitle": "筆記",
  "@readerNotesSheetTitle": {
    "description": "筆記 Bottom Sheet（書籤／劃線與備註）的標題"
  },
  "readerNotesSheetExportMarkdownTooltip": "導出為 Markdown",
  "@readerNotesSheetExportMarkdownTooltip": {
    "description": "筆記 Bottom Sheet 標題列「導出為 Markdown」按鈕的無障礙提示文字"
  },
  "readerNotesSheetTabBookmarks": "書籤",
  "@readerNotesSheetTabBookmarks": {
    "description": "筆記 Bottom Sheet 第一個分頁籤：書籤"
  },
  "readerNotesSheetTabAnnotations": "劃線與備註",
  "@readerNotesSheetTabAnnotations": {
    "description": "筆記 Bottom Sheet 第二個分頁籤：劃線與備註"
  },
  "readerNotesSheetDeleteAllBookmarksTooltip": "刪除該書所有書籤",
  "@readerNotesSheetDeleteAllBookmarksTooltip": {
    "description": "書籤分頁「刪除該書所有書籤」按鈕的無障礙提示文字"
  },
  "readerNotesSheetRenameBookmarkTitle": "重新命名書籤",
  "@readerNotesSheetRenameBookmarkTitle": {
    "description": "重新命名書籤對話框標題"
  },
  "readerDeleteConfirmButton": "刪除",
  "@readerDeleteConfirmButton": {
    "description": "筆記 Bottom Sheet 內各種刪除確認對話框的「刪除」按鈕文字（書籤/劃線/備註批次刪除共用）"
  },
  "readerNotesSheetDeleteAllBookmarksConfirm": "確定要刪除全部書籤嗎？（共 {count} 筆）",
  "@readerNotesSheetDeleteAllBookmarksConfirm": {
    "description": "刪除全部書籤確認對話框標題，{count} 為目前書籤總數",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "readerNotesSheetRenameTooltip": "重新命名",
  "@readerNotesSheetRenameTooltip": {
    "description": "書籤列項目「重新命名」按鈕的無障礙提示文字"
  },
  "readerNotesSheetDeleteItemTooltip": "刪除",
  "@readerNotesSheetDeleteItemTooltip": {
    "description": "書籤/劃線/備註單筆項目「刪除」按鈕的無障礙提示文字"
  },
  "readerNotesSheetNoAnnotationsPlaceholder": "尚無劃線或備註",
  "@readerNotesSheetNoAnnotationsPlaceholder": {
    "description": "劃線與備註分頁的空狀態提示文字"
  },
  "readerNotesSheetDeleteAllHighlightsButton": "刪除所有劃線",
  "@readerNotesSheetDeleteAllHighlightsButton": {
    "description": "劃線與備註分頁「刪除所有劃線」按鈕文字"
  },
  "readerNotesSheetDeleteAllNotesButton": "刪除所有備註",
  "@readerNotesSheetDeleteAllNotesButton": {
    "description": "劃線與備註分頁「刪除所有備註」按鈕文字"
  },
  "readerNotesSheetNoteLabel": "備註",
  "@readerNotesSheetNoteLabel": {
    "description": "劃線與備註合併清單中，純備註項目（無對應劃線）的項目標題"
  },
  "readerHighlightStyleYellow": "螢光筆（黃）",
  "@readerHighlightStyleYellow": {
    "description": "劃線清單項目標題：黃色螢光筆樣式"
  },
  "readerHighlightStylePink": "螢光筆（粉）",
  "@readerHighlightStylePink": {
    "description": "劃線清單項目標題：粉色螢光筆樣式"
  },
  "readerHighlightStyleBlue": "螢光筆（藍）",
  "@readerHighlightStyleBlue": {
    "description": "劃線清單項目標題：藍色螢光筆樣式"
  },
  "readerHighlightStyleUnderline": "底線",
  "@readerHighlightStyleUnderline": {
    "description": "劃線清單項目標題：底線樣式"
  },
  "readerNotesSheetDeleteAllHighlightsConfirm": "確定要刪除全部劃線嗎？（共 {count} 筆）",
  "@readerNotesSheetDeleteAllHighlightsConfirm": {
    "description": "刪除全部劃線確認對話框標題，{count} 為目前劃線總數",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "readerNotesSheetDeleteAllNotesConfirm": "確定要刪除全部備註嗎？（共 {count} 筆）",
  "@readerNotesSheetDeleteAllNotesConfirm": {
    "description": "刪除全部備註確認對話框標題，{count} 為目前備註總數",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  }
```

`app_zh_CN.arb`：
```json
  "readerNotesSheetTitle": "笔记",
  "readerNotesSheetExportMarkdownTooltip": "导出为 Markdown",
  "readerNotesSheetTabBookmarks": "书签",
  "readerNotesSheetTabAnnotations": "划线与备注",
  "readerNotesSheetDeleteAllBookmarksTooltip": "删除该书所有书签",
  "readerNotesSheetRenameBookmarkTitle": "重新命名书签",
  "readerDeleteConfirmButton": "删除",
  "readerNotesSheetDeleteAllBookmarksConfirm": "确定要删除全部书签吗？（共 {count} 笔）",
  "readerNotesSheetRenameTooltip": "重新命名",
  "readerNotesSheetDeleteItemTooltip": "删除",
  "readerNotesSheetNoAnnotationsPlaceholder": "尚无划线或备注",
  "readerNotesSheetDeleteAllHighlightsButton": "删除所有划线",
  "readerNotesSheetDeleteAllNotesButton": "删除所有备注",
  "readerNotesSheetNoteLabel": "备注",
  "readerHighlightStyleYellow": "萤光笔（黄）",
  "readerHighlightStylePink": "萤光笔（粉）",
  "readerHighlightStyleBlue": "萤光笔（蓝）",
  "readerHighlightStyleUnderline": "底线",
  "readerNotesSheetDeleteAllHighlightsConfirm": "确定要删除全部划线吗？（共 {count} 笔）",
  "readerNotesSheetDeleteAllNotesConfirm": "确定要删除全部备注吗？（共 {count} 笔）"
```

`app_en.arb`：
```json
  "readerNotesSheetTitle": "Notes",
  "readerNotesSheetExportMarkdownTooltip": "Export as Markdown",
  "readerNotesSheetTabBookmarks": "Bookmarks",
  "readerNotesSheetTabAnnotations": "Highlights & Notes",
  "readerNotesSheetDeleteAllBookmarksTooltip": "Delete all bookmarks for this book",
  "readerNotesSheetRenameBookmarkTitle": "Rename bookmark",
  "readerDeleteConfirmButton": "Delete",
  "readerNotesSheetDeleteAllBookmarksConfirm": "Delete all {count} bookmark(s)?",
  "readerNotesSheetRenameTooltip": "Rename",
  "readerNotesSheetDeleteItemTooltip": "Delete",
  "readerNotesSheetNoAnnotationsPlaceholder": "No highlights or notes yet",
  "readerNotesSheetDeleteAllHighlightsButton": "Delete all highlights",
  "readerNotesSheetDeleteAllNotesButton": "Delete all notes",
  "readerNotesSheetNoteLabel": "Note",
  "readerHighlightStyleYellow": "Highlighter (Yellow)",
  "readerHighlightStylePink": "Highlighter (Pink)",
  "readerHighlightStyleBlue": "Highlighter (Blue)",
  "readerHighlightStyleUnderline": "Underline",
  "readerNotesSheetDeleteAllHighlightsConfirm": "Delete all {count} highlight(s)?",
  "readerNotesSheetDeleteAllNotesConfirm": "Delete all {count} note(s)?"
```

`app_zh.arb`：
```json
  "readerNotesSheetTitle": "筆記",
  "readerNotesSheetExportMarkdownTooltip": "導出為 Markdown",
  "readerNotesSheetTabBookmarks": "書籤",
  "readerNotesSheetTabAnnotations": "劃線與備註",
  "readerNotesSheetDeleteAllBookmarksTooltip": "刪除該書所有書籤",
  "readerNotesSheetRenameBookmarkTitle": "重新命名書籤",
  "readerDeleteConfirmButton": "刪除",
  "readerNotesSheetDeleteAllBookmarksConfirm": "確定要刪除全部書籤嗎？（共 {count} 筆）",
  "readerNotesSheetRenameTooltip": "重新命名",
  "readerNotesSheetDeleteItemTooltip": "刪除",
  "readerNotesSheetNoAnnotationsPlaceholder": "尚無劃線或備註",
  "readerNotesSheetDeleteAllHighlightsButton": "刪除所有劃線",
  "readerNotesSheetDeleteAllNotesButton": "刪除所有備註",
  "readerNotesSheetNoteLabel": "備註",
  "readerHighlightStyleYellow": "螢光筆（黃）",
  "readerHighlightStylePink": "螢光筆（粉）",
  "readerHighlightStyleBlue": "螢光筆（藍）",
  "readerHighlightStyleUnderline": "底線",
  "readerNotesSheetDeleteAllHighlightsConfirm": "確定要刪除全部劃線嗎？（共 {count} 筆）",
  "readerNotesSheetDeleteAllNotesConfirm": "確定要刪除全部備註嗎？（共 {count} 筆）"
```

- [x] **Step 2: 執行 `flutter gen-l10n`**

- [x] **Step 3: 修改 `notes_bottom_sheet.dart`**

新增 import：`import '../l10n/app_localizations.dart';`

`build()` 方法：
```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return EBSheetShell(
      title: l10n.readerNotesSheetTitle,
      actions: [
        IconButton(
          key: const Key('notes_sheet_export_markdown'),
          onPressed: _exportMarkdown,
          icon: const Icon(Icons.ios_share),
          tooltip: l10n.readerNotesSheetExportMarkdownTooltip,
        ),
      ],
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                key: const Key('notes_sheet_tab_bookmarks'),
                icon: const Icon(Icons.bookmark_outline),
                text: l10n.readerNotesSheetTabBookmarks,
              ),
              Tab(
                key: const Key('notes_sheet_tab_annotations'),
                icon: const Icon(Icons.edit_note),
                text: l10n.readerNotesSheetTabAnnotations,
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBookmarksTab(),
                _buildAnnotationsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
```

`_buildBookmarksTab()`：
```dart
  Widget _buildBookmarksTab() {
    final l10n = AppLocalizations.of(context)!;
    final existing = _bookmarkAtCurrentPosition;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('notes_sheet_bookmark_toggle'),
                  icon: Icon(existing != null ? Icons.star : Icons.star_border),
                  label: Text(existing != null
                      ? l10n.readerBookmarkAddedTooltip
                      : l10n.readerBookmarkAddTooltip),
                  onPressed: _toggleBookmark,
                ),
              ),
              IconButton(
                key: const Key('notes_sheet_delete_all_bookmarks'),
                icon: const Icon(Icons.delete_sweep),
                tooltip: l10n.readerNotesSheetDeleteAllBookmarksTooltip,
                onPressed:
                    _bookmarks.isEmpty ? null : _confirmDeleteAllBookmarks,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const Key('notes_sheet_bookmark_list'),
            itemCount: _bookmarks.length,
            itemBuilder: (context, index) =>
                _buildBookmarkRow(_bookmarks[index]),
          ),
        ),
      ],
    );
  }
```

`_renameBookmark()`（僅 `showDialog` 內的 `AlertDialog` 需修改）：
```dart
  Future<void> _renameBookmark(Bookmark bookmark) async {
    _renameController?.dispose();
    final controller = TextEditingController(text: bookmark.name);
    _renameController = controller;
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(l10n.readerNotesSheetRenameBookmarkTitle),
          content: TextField(
            key: const Key('notes_sheet_rename_field'),
            controller: controller,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
              key: const Key('notes_sheet_rename_confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(l10n.readerNoteDialogSaveButton),
            ),
          ],
        );
      },
    );
    if (newName == null || newName.trim().isEmpty) return;
    await widget.bookmarksRepository.rename(bookmark.id, newName.trim());
    await _loadBookmarks();
  }
```

`_confirmDeleteAllBookmarks()`：
```dart
  Future<void> _confirmDeleteAllBookmarks() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(
            l10n.readerNotesSheetDeleteAllBookmarksConfirm(_bookmarks.length),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              key: const Key('notes_sheet_delete_all_bookmarks_confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(dialogContext).colorScheme.error),
              child: Text(l10n.readerDeleteConfirmButton),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await widget.bookmarksRepository.deleteAllForBook(widget.bookId);
    await _loadBookmarks();
  }
```

`_buildBookmarkRow()`：
```dart
  Widget _buildBookmarkRow(Bookmark bookmark) {
    final l10n = AppLocalizations.of(context)!;
    return EBFieldCard(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        key: Key('notes_sheet_bookmark_${bookmark.id}'),
        title: Text(convertText(bookmark.name, widget.textConversion)),
        onTap: () => widget.onBookmarkSelected(bookmark),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: Key('notes_sheet_bookmark_rename_${bookmark.id}'),
              icon: const Icon(Icons.edit),
              tooltip: l10n.readerNotesSheetRenameTooltip,
              onPressed: () => _renameBookmark(bookmark),
            ),
            IconButton(
              key: Key('notes_sheet_bookmark_delete_${bookmark.id}'),
              icon: const Icon(Icons.delete),
              tooltip: l10n.readerNotesSheetDeleteItemTooltip,
              onPressed: () => _deleteBookmark(bookmark),
            ),
          ],
        ),
      ),
    );
  }
```

`_buildAnnotationsTab()`：
```dart
  Widget _buildAnnotationsTab() {
    final l10n = AppLocalizations.of(context)!;
    final highlightsRepository = widget.highlightsRepository;
    final notesRepository = widget.notesRepository;
    if (highlightsRepository == null || notesRepository == null) {
      return Center(
        child: Text(l10n.readerNotesSheetNoAnnotationsPlaceholder,
            key: const Key('notes_sheet_annotations_placeholder')),
      );
    }
    final items = mergeAnnotations(_highlights, _notes);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('notes_sheet_delete_all_highlights'),
                  onPressed: _highlights.isEmpty ? null : _confirmDeleteAllHighlights,
                  child: Text(l10n.readerNotesSheetDeleteAllHighlightsButton),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const Key('notes_sheet_delete_all_notes'),
                  onPressed: _notes.isEmpty ? null : _confirmDeleteAllNotes,
                  child: Text(l10n.readerNotesSheetDeleteAllNotesButton),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(l10n.readerNotesSheetNoAnnotationsPlaceholder,
                      key: const Key('notes_sheet_annotations_placeholder')),
                )
              : ListView.builder(
                  key: const Key('notes_sheet_annotation_list'),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _buildAnnotationRow(items[index]),
                ),
        ),
      ],
    );
  }
```

`_buildAnnotationRow()`：
```dart
  Widget _buildAnnotationRow(AnnotationListItem item) {
    final l10n = AppLocalizations.of(context)!;
    final highlight = item.highlight;
    final note = item.note;
    return EBFieldCard(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        key: Key('notes_sheet_annotation_${item.key}'),
        leading: Icon(
          Icons.circle,
          color: highlight != null
              ? highlightStyleColor(highlight.style,
                  tokens: Theme.of(context).extension<ElinkTokens>()!)
              : noteOnlyTint,
        ),
        title: Text(highlight != null
            ? _highlightStyleLabel(highlight.style, l10n)
            : l10n.readerNotesSheetNoteLabel),
        subtitle: note != null
            ? Text(note.text, maxLines: 2, overflow: TextOverflow.ellipsis)
            : null,
        onTap: () => widget.onAnnotationSelected?.call(item),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (note != null)
              IconButton(
                key: Key('notes_sheet_annotation_edit_${note.id}'),
                icon: const Icon(Icons.edit),
                tooltip: l10n.readerAnnotationEditNoteTooltip,
                onPressed: () => _editNoteText(note),
              ),
            IconButton(
              key: Key('notes_sheet_annotation_delete_${item.key}'),
              icon: const Icon(Icons.delete),
              tooltip: l10n.readerNotesSheetDeleteItemTooltip,
              onPressed: () => _deleteAnnotationItem(item),
            ),
          ],
        ),
      ),
    );
  }

  /// 供劃線清單項目顯示用的標籤（[l10n] 由呼叫端傳入，供三語言轉譯）。
  String _highlightStyleLabel(HighlightStyle style, AppLocalizations l10n) {
    switch (style) {
      case HighlightStyle.highlighterYellow:
        return l10n.readerHighlightStyleYellow;
      case HighlightStyle.highlighterPink:
        return l10n.readerHighlightStylePink;
      case HighlightStyle.highlighterBlue:
        return l10n.readerHighlightStyleBlue;
      case HighlightStyle.underline:
        return l10n.readerHighlightStyleUnderline;
    }
  }
```

`_editNoteText()`：
```dart
  Future<void> _editNoteText(Note note) async {
    final l10n = AppLocalizations.of(context)!;
    final newText = await showNoteTextDialog(context,
        initialText: note.text, title: l10n.readerAnnotationEditNoteTooltip);
    if (newText == null) return;
    await widget.notesRepository!.updateText(note.id, newText);
    await _loadAnnotations();
    widget.onAnnotationsChanged?.call();
  }
```

`_confirmDeleteAll()`（簽章變更，`itemLabel` 改為 `title`）：
```dart
  Future<void> _confirmDeleteAll({
    required String title,
    required Key confirmKey,
    required Future<void> Function() onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(title),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              key: confirmKey,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(dialogContext).colorScheme.error),
              child: Text(l10n.readerDeleteConfirmButton),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await onConfirm();
  }

  Future<void> _confirmDeleteAllHighlights() {
    final l10n = AppLocalizations.of(context)!;
    return _confirmDeleteAll(
      title: l10n.readerNotesSheetDeleteAllHighlightsConfirm(_highlights.length),
      confirmKey: const Key('notes_sheet_delete_all_highlights_confirm'),
      onConfirm: () async {
        await widget.highlightsRepository!.deleteAllForBook(widget.bookId);
        await _loadAnnotations();
        widget.onAnnotationsChanged?.call();
      },
    );
  }

  Future<void> _confirmDeleteAllNotes() {
    final l10n = AppLocalizations.of(context)!;
    return _confirmDeleteAll(
      title: l10n.readerNotesSheetDeleteAllNotesConfirm(_notes.length),
      confirmKey: const Key('notes_sheet_delete_all_notes_confirm'),
      onConfirm: () async {
        await widget.notesRepository!.deleteAllForBook(widget.bookId);
        await _loadAnnotations();
        widget.onAnnotationsChanged?.call();
      },
    );
  }
```

（`_loadBookmarks()`／`_loadAnnotations()`／`_exportMarkdown()`／`_matchesCurrentPosition()`／`_bookmarkAtCurrentPosition`／`_toggleBookmark()`／`_deleteBookmark()`／`_deleteAnnotationItem()`／`initState()`／`dispose()` 等其餘方法不含硬編碼字串或無需改動，原樣保留。）

- [x] **Step 4: 遷移既有測試檔（2 處 `MaterialApp(`）**

`app/test/screens/notes_bottom_sheet_test.dart` 2 處補上 l10n 三參數。既有測試若直接呼叫 `widget._confirmDeleteAll` 或依賴 `itemLabel` 具名參數（不太可能，該方法是 private），無需修改；若有測試建構 `_TtsSleepTimerSheet`（不相關）忽略。

- [x] **Step 5: 新增英文渲染驗證測試**

新增 `testWidgets('英文介面下分頁籤/按鈕/空狀態文字正確以英文渲染', ...)`，`locale: const Locale('en')`，斷言 `find.text('Notes')`／`find.text('Bookmarks')`／`find.text('Highlights & Notes')`。

- [x] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/notes_bottom_sheet_test.dart`

- [x] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/notes_bottom_sheet.dart test/screens/notes_bottom_sheet_test.dart`

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/notes_bottom_sheet.dart app/test/screens/notes_bottom_sheet_test.dart app/lib/l10n/
git commit -m "feat(epic-45): notes_bottom_sheet.dart 字串抽取三語言在地化"
```

---

### Task 12: `fxl_settings_sheet.dart`（production）

**Files:**
- Modify: `app/lib/screens/fxl_settings_sheet.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`。
- Produces：本 Task 建立的 ARB key 中，以下 **9 個為「三份版面設定 Bottom Sheet 共用」key**，Task 14（`pdf_settings_sheet.dart`）與 Task 15/16（`reader_settings_sheet.dart`）直接消費、不重複新增：`readerDualPageAutoTooltip`/`readerDualPageAutoLabel`/`readerDualPageAlwaysTooltip`/`readerDualPageAlwaysLabel`/`readerDualPageNeverTooltip`/`readerDualPageNeverLabel`/`readerFullscreenModeLabel`/`readerShowFooterLabel`/`readerUseGlobalDefaultTooltip`/`readerGlobalLabel`。其餘為 fxl 專屬：`readerFxlSettingsTitle`/`readerDualPageModeLabel`/`readerPageDirectionLabel`/`readerDualPageDirectionLtrTooltip`/`readerDualPageDirectionLtrLabel`/`readerDualPageDirectionRtlTooltip`/`readerDualPageDirectionRtlLabel`/`readerTextConversionOverrideLabel`/`readerTextConversionOriginalLabel`/`readerTextConversionTraditionalLabel`/`readerTextConversionTraditionalTooltip`/`readerTextConversionSimplifiedLabel`/`readerTextConversionSimplifiedTooltip`/`readerShowHeaderLabel`（`readerTextConversionOverrideLabel` 等 6 個文字轉換相關 key 與 `readerShowHeaderLabel` 之後也會被 Task 15/16 `reader_settings_sheet.dart` 重用，一併在本 Task 建立）。

- [x] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "readerFxlSettingsTitle": "⚙️ 漫畫版面設定",
  "@readerFxlSettingsTitle": {
    "description": "FXL（固定版面）版面設定 Bottom Sheet 標題"
  },
  "readerDualPageModeLabel": "雙頁模式",
  "@readerDualPageModeLabel": {
    "description": "雙頁模式選項群組的小標題，fxl_settings_sheet.dart／pdf_settings_sheet.dart 共用"
  },
  "readerDualPageAutoTooltip": "自動（橫向雙頁）",
  "@readerDualPageAutoTooltip": {
    "description": "雙頁模式「自動」選項 tooltip，fxl_settings_sheet.dart／pdf_settings_sheet.dart 共用"
  },
  "readerDualPageAutoLabel": "自動",
  "@readerDualPageAutoLabel": {
    "description": "雙頁模式「自動」選項短標籤，fxl_settings_sheet.dart／pdf_settings_sheet.dart 共用"
  },
  "readerDualPageAlwaysTooltip": "永遠雙頁",
  "@readerDualPageAlwaysTooltip": {
    "description": "雙頁模式「永遠雙頁」選項 tooltip，fxl_settings_sheet.dart／pdf_settings_sheet.dart 共用"
  },
  "readerDualPageAlwaysLabel": "雙頁",
  "@readerDualPageAlwaysLabel": {
    "description": "雙頁模式「永遠雙頁」選項短標籤，fxl_settings_sheet.dart／pdf_settings_sheet.dart 共用"
  },
  "readerDualPageNeverTooltip": "永遠單頁",
  "@readerDualPageNeverTooltip": {
    "description": "雙頁模式「永遠單頁」選項 tooltip，fxl_settings_sheet.dart／pdf_settings_sheet.dart 共用"
  },
  "readerDualPageNeverLabel": "單頁",
  "@readerDualPageNeverLabel": {
    "description": "雙頁模式「永遠單頁」選項短標籤，fxl_settings_sheet.dart／pdf_settings_sheet.dart 共用"
  },
  "readerPageDirectionLabel": "翻頁方向",
  "@readerPageDirectionLabel": {
    "description": "fxl_settings_sheet.dart 翻頁方向選項群組的小標題"
  },
  "readerDualPageDirectionLtrTooltip": "左到右（LTR，美漫慣例）",
  "@readerDualPageDirectionLtrTooltip": {
    "description": "fxl_settings_sheet.dart 翻頁方向「左到右」選項 tooltip"
  },
  "readerDualPageDirectionLtrLabel": "左翻",
  "@readerDualPageDirectionLtrLabel": {
    "description": "fxl_settings_sheet.dart 翻頁方向「左到右」選項短標籤"
  },
  "readerDualPageDirectionRtlTooltip": "右到左（RTL，日漫慣例）",
  "@readerDualPageDirectionRtlTooltip": {
    "description": "fxl_settings_sheet.dart 翻頁方向「右到左」選項 tooltip"
  },
  "readerDualPageDirectionRtlLabel": "右翻",
  "@readerDualPageDirectionRtlLabel": {
    "description": "fxl_settings_sheet.dart 翻頁方向「右到左」選項短標籤"
  },
  "readerTextConversionOverrideLabel": "簡繁轉換覆寫",
  "@readerTextConversionOverrideLabel": {
    "description": "簡繁轉換覆寫選項群組的小標題，fxl_settings_sheet.dart／reader_settings_sheet.dart 共用"
  },
  "readerGlobalLabel": "全域",
  "@readerGlobalLabel": {
    "description": "「使用全域預設」選項的短標籤，簡繁轉換覆寫／翻頁模式覆寫／螢幕方向覆寫共用"
  },
  "readerUseGlobalDefaultTooltip": "使用全域預設",
  "@readerUseGlobalDefaultTooltip": {
    "description": "「使用全域預設」選項的 tooltip，簡繁轉換覆寫／翻頁模式覆寫／螢幕方向覆寫共用"
  },
  "readerTextConversionOriginalLabel": "原文",
  "@readerTextConversionOriginalLabel": {
    "description": "簡繁轉換覆寫「原文」選項的標籤與 tooltip（兩者文字相同，共用一個 key）"
  },
  "readerTextConversionTraditionalLabel": "繁體",
  "@readerTextConversionTraditionalLabel": {
    "description": "簡繁轉換覆寫「繁體」選項短標籤"
  },
  "readerTextConversionTraditionalTooltip": "轉換為繁體",
  "@readerTextConversionTraditionalTooltip": {
    "description": "簡繁轉換覆寫「繁體」選項 tooltip"
  },
  "readerTextConversionSimplifiedLabel": "簡體",
  "@readerTextConversionSimplifiedLabel": {
    "description": "簡繁轉換覆寫「簡體」選項短標籤"
  },
  "readerTextConversionSimplifiedTooltip": "轉換為簡體",
  "@readerTextConversionSimplifiedTooltip": {
    "description": "簡繁轉換覆寫「簡體」選項 tooltip"
  },
  "readerFullscreenModeLabel": "全螢幕模式",
  "@readerFullscreenModeLabel": {
    "description": "全螢幕模式開關標題，fxl_settings_sheet.dart／pdf_settings_sheet.dart／reader_settings_sheet.dart 共用"
  },
  "readerShowHeaderLabel": "顯示頁首",
  "@readerShowHeaderLabel": {
    "description": "顯示頁首開關標題，fxl_settings_sheet.dart／reader_settings_sheet.dart 共用"
  },
  "readerShowFooterLabel": "顯示頁尾",
  "@readerShowFooterLabel": {
    "description": "顯示頁尾開關標題，fxl_settings_sheet.dart／pdf_settings_sheet.dart／reader_settings_sheet.dart 共用"
  }
```

`app_zh_CN.arb`：
```json
  "readerFxlSettingsTitle": "⚙️ 漫画版面设定",
  "readerDualPageModeLabel": "双页模式",
  "readerDualPageAutoTooltip": "自动（横向双页）",
  "readerDualPageAutoLabel": "自动",
  "readerDualPageAlwaysTooltip": "永远双页",
  "readerDualPageAlwaysLabel": "双页",
  "readerDualPageNeverTooltip": "永远单页",
  "readerDualPageNeverLabel": "单页",
  "readerPageDirectionLabel": "翻页方向",
  "readerDualPageDirectionLtrTooltip": "左到右（LTR，美漫惯例）",
  "readerDualPageDirectionLtrLabel": "左翻",
  "readerDualPageDirectionRtlTooltip": "右到左（RTL，日漫惯例）",
  "readerDualPageDirectionRtlLabel": "右翻",
  "readerTextConversionOverrideLabel": "简繁转换覆盖",
  "readerGlobalLabel": "全局",
  "readerUseGlobalDefaultTooltip": "使用全局预设",
  "readerTextConversionOriginalLabel": "原文",
  "readerTextConversionTraditionalLabel": "繁体",
  "readerTextConversionTraditionalTooltip": "转换为繁体",
  "readerTextConversionSimplifiedLabel": "简体",
  "readerTextConversionSimplifiedTooltip": "转换为简体",
  "readerFullscreenModeLabel": "全屏模式",
  "readerShowHeaderLabel": "显示页首",
  "readerShowFooterLabel": "显示页尾"
```

`app_en.arb`：
```json
  "readerFxlSettingsTitle": "⚙️ Comic Layout Settings",
  "readerDualPageModeLabel": "Dual-page mode",
  "readerDualPageAutoTooltip": "Auto (dual-page in landscape)",
  "readerDualPageAutoLabel": "Auto",
  "readerDualPageAlwaysTooltip": "Always dual-page",
  "readerDualPageAlwaysLabel": "Dual",
  "readerDualPageNeverTooltip": "Always single-page",
  "readerDualPageNeverLabel": "Single",
  "readerPageDirectionLabel": "Page direction",
  "readerDualPageDirectionLtrTooltip": "Left to right (LTR, Western comic convention)",
  "readerDualPageDirectionLtrLabel": "LTR",
  "readerDualPageDirectionRtlTooltip": "Right to left (RTL, manga convention)",
  "readerDualPageDirectionRtlLabel": "RTL",
  "readerTextConversionOverrideLabel": "Script conversion override",
  "readerGlobalLabel": "Global",
  "readerUseGlobalDefaultTooltip": "Use global default",
  "readerTextConversionOriginalLabel": "Original",
  "readerTextConversionTraditionalLabel": "Traditional",
  "readerTextConversionTraditionalTooltip": "Convert to Traditional",
  "readerTextConversionSimplifiedLabel": "Simplified",
  "readerTextConversionSimplifiedTooltip": "Convert to Simplified",
  "readerFullscreenModeLabel": "Fullscreen mode",
  "readerShowHeaderLabel": "Show header",
  "readerShowFooterLabel": "Show footer"
```

`app_zh.arb`：
```json
  "readerFxlSettingsTitle": "⚙️ 漫畫版面設定",
  "readerDualPageModeLabel": "雙頁模式",
  "readerDualPageAutoTooltip": "自動（橫向雙頁）",
  "readerDualPageAutoLabel": "自動",
  "readerDualPageAlwaysTooltip": "永遠雙頁",
  "readerDualPageAlwaysLabel": "雙頁",
  "readerDualPageNeverTooltip": "永遠單頁",
  "readerDualPageNeverLabel": "單頁",
  "readerPageDirectionLabel": "翻頁方向",
  "readerDualPageDirectionLtrTooltip": "左到右（LTR，美漫慣例）",
  "readerDualPageDirectionLtrLabel": "左翻",
  "readerDualPageDirectionRtlTooltip": "右到左（RTL，日漫慣例）",
  "readerDualPageDirectionRtlLabel": "右翻",
  "readerTextConversionOverrideLabel": "簡繁轉換覆寫",
  "readerGlobalLabel": "全域",
  "readerUseGlobalDefaultTooltip": "使用全域預設",
  "readerTextConversionOriginalLabel": "原文",
  "readerTextConversionTraditionalLabel": "繁體",
  "readerTextConversionTraditionalTooltip": "轉換為繁體",
  "readerTextConversionSimplifiedLabel": "簡體",
  "readerTextConversionSimplifiedTooltip": "轉換為簡體",
  "readerFullscreenModeLabel": "全螢幕模式",
  "readerShowHeaderLabel": "顯示頁首",
  "readerShowFooterLabel": "顯示頁尾"
```

- [x] **Step 2: 執行 `flutter gen-l10n`**

- [x] **Step 3: 修改 `fxl_settings_sheet.dart`**

新增 import：`import '../l10n/app_localizations.dart';`

`build()` 方法開頭新增 `final l10n = AppLocalizations.of(context)!;`，並依下表把每一處字面值替換為對應 `l10n.xxx`（其餘版面結構、`EBOptionChipGroup`／`EBFieldCard`／`SwitchListTile` 巢狀不動）：

| 原字面值 | 新表達式 |
|---|---|
| `'⚙️ 漫畫版面設定'` | `l10n.readerFxlSettingsTitle` |
| `'雙頁模式'`（Text 標題） | `l10n.readerDualPageModeLabel` |
| `dualPageOptions` 內 `'自動（橫向雙頁）'`／`'自動'` | `l10n.readerDualPageAutoTooltip`／`l10n.readerDualPageAutoLabel` |
| `dualPageOptions` 內 `'永遠雙頁'`／`'雙頁'` | `l10n.readerDualPageAlwaysTooltip`／`l10n.readerDualPageAlwaysLabel` |
| `dualPageOptions` 內 `'永遠單頁'`／`'單頁'` | `l10n.readerDualPageNeverTooltip`／`l10n.readerDualPageNeverLabel` |
| `'翻頁方向'`（Text 標題） | `l10n.readerPageDirectionLabel` |
| `directionOptions` 內 `'左到右（LTR，美漫慣例）'`／`'左翻'` | `l10n.readerDualPageDirectionLtrTooltip`／`l10n.readerDualPageDirectionLtrLabel` |
| `directionOptions` 內 `'右到左（RTL，日漫慣例）'`／`'右翻'` | `l10n.readerDualPageDirectionRtlTooltip`／`l10n.readerDualPageDirectionRtlLabel` |
| `'簡繁轉換覆寫'`（Text 標題） | `l10n.readerTextConversionOverrideLabel` |
| `EBOptionChipItem` `'全域'`／`'使用全域預設'` | `l10n.readerGlobalLabel`／`l10n.readerUseGlobalDefaultTooltip` |
| `EBOptionChipItem` `'原文'`／`'原文'` | `l10n.readerTextConversionOriginalLabel`（label／tooltip 皆用此 key） |
| `EBOptionChipItem` `'繁體'`／`'轉換為繁體'` | `l10n.readerTextConversionTraditionalLabel`／`l10n.readerTextConversionTraditionalTooltip` |
| `EBOptionChipItem` `'簡體'`／`'轉換為簡體'` | `l10n.readerTextConversionSimplifiedLabel`／`l10n.readerTextConversionSimplifiedTooltip` |
| `'全螢幕模式'`（`SwitchListTile.title`） | `Text(l10n.readerFullscreenModeLabel, ...)` |
| `'顯示頁首'`（`SwitchListTile.title`） | `Text(l10n.readerShowHeaderLabel, ...)` |
| `'顯示頁尾'`（`SwitchListTile.title`） | `Text(l10n.readerShowFooterLabel, ...)` |

例（`dualPageOptions`／`directionOptions`／文字轉換 `items` 三處 `const` 陣列因值不再是編譯期常數，改為方法內非 `const` `final` 區域變數，`const (...)` tuple literal 移除最外層 `const`；`EBOptionChipItem` 陣列的 `const [...]` 同理移除）：

```dart
    final dualPageOptions = [
      (
        DualPageMode.auto,
        'auto',
        Icons.stay_current_landscape,
        l10n.readerDualPageAutoTooltip,
        l10n.readerDualPageAutoLabel,
      ),
      (DualPageMode.always, 'always', Icons.view_column, l10n.readerDualPageAlwaysTooltip, l10n.readerDualPageAlwaysLabel),
      (DualPageMode.never, 'never', Icons.crop_portrait, l10n.readerDualPageNeverTooltip, l10n.readerDualPageNeverLabel),
    ];
    final directionOptions = [
      (
        DualPageDirection.ltr,
        'ltr',
        Icons.arrow_forward,
        l10n.readerDualPageDirectionLtrTooltip,
        l10n.readerDualPageDirectionLtrLabel,
      ),
      (DualPageDirection.rtl, 'rtl', Icons.arrow_back, l10n.readerDualPageDirectionRtlTooltip, l10n.readerDualPageDirectionRtlLabel),
    ];
```

文字轉換 `EBOptionChipGroup<TextConversionMode?>` 的 `items:` 由 `const [...]` 改為 `[...]`（移除 `const`），四個 `EBOptionChipItem` 的 `label:`／`tooltip:` 依上表替換，`itemKey`／`value`／`iconWidget` 不動。

- [x] **Step 4: 執行測試確認未觸及的測試檔仍通過（本 Task 不遷移測試，預期紅燈）**

Run: `flutter test test/screens/fxl_settings_sheet_test.dart`
Expected: 因缺少 `localizationsDelegates`，測試會以 `Null check operator used on a null value` 失敗——此為預期中的紅燈，留給 Task 13 修復。

- [x] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/fxl_settings_sheet.dart`
Expected: No issues found!

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/fxl_settings_sheet.dart app/lib/l10n/
git commit -m "feat(epic-45): fxl_settings_sheet.dart 字串抽取三語言在地化（測試遷移見下個 commit）"
```

---

### Task 13: `fxl_settings_sheet_test.dart` 測試遷移

**Files:**
- Test: `app/test/screens/fxl_settings_sheet_test.dart`（21 處裸 `MaterialApp(`）

**Interfaces:**
- Consumes：Task 12 產出的 `FxlSettingsSheet`（介面簽章未變動，僅內部文字改用 l10n）。

- [x] **Step 1: 遷移 21 處 `MaterialApp(` 呼叫**

先 Grep 確認實際寫法分布：`grep -c "MaterialApp(" test/screens/fxl_settings_sheet_test.dart` 應為 21。若檔案已有共用 helper（例如 `_wrap()`／`_pumpSheet()`）包裝 `MaterialApp`，優先只修改該 helper 一處，補上：
```dart
localizationsDelegates: AppLocalizations.localizationsDelegates,
supportedLocales: AppLocalizations.supportedLocales,
locale: const Locale('zh', 'TW'),
```
並在檔案頂部新增 `import 'package:elinkbook/l10n/app_localizations.dart';`。若 21 處是分散在各個 `testWidgets` 內各自建構（無共用 helper），逐一比照相同規則補上三個參數——純機械式改動，不變動任何既有斷言內容（預設 `zh_TW` 讓既有中文 `find.text(...)` 斷言維持通過）。

- [x] **Step 2: 新增三語言渲染驗證測試**

新增 `testWidgets('英文介面下雙頁模式/翻頁方向/全螢幕開關文字正確以英文渲染', ...)`，`locale: const Locale('en')`，斷言 `find.text('Dual-page mode')`／`find.text('Fullscreen mode')`。

- [x] **Step 3: 執行測試確認全數通過**

Run: `flutter test test/screens/fxl_settings_sheet_test.dart`
Expected: 全數通過（既有＋新增 1 個）。

- [x] **Step 4: `grep` 驗證零殘留**

Run: `grep -c "MaterialApp(" test/screens/fxl_settings_sheet_test.dart`（若已改用共用 helper 且該 helper 仍含一處 `MaterialApp(`，此數字應為 1；若逐一內嵌則應為 0，取決於 Step 1 實際採用的模式，Task 執行者需在此記錄實際數字與說明）。

- [x] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze test/screens/fxl_settings_sheet_test.dart`

- [x] **Step 6: Commit**

```bash
git add app/test/screens/fxl_settings_sheet_test.dart
git commit -m "test(epic-45): fxl_settings_sheet_test.dart 遷移至 pumpLocalizedWidget 相容寫法"
```

---

### Task 14: `pdf_settings_sheet.dart`（production ＋ 測試，3 處 `MaterialApp(` 合併同一 Task）

**Files:**
- Modify: `app/lib/screens/pdf_settings_sheet.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/pdf_settings_sheet_test.dart`（僅 3 處 `MaterialApp(`，規模小，生產程式碼與測試遷移合併同一 Task）

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`；Task 12 共用 key `readerDualPageModeLabel`/`readerDualPageAutoTooltip`/`readerDualPageAutoLabel`/`readerDualPageAlwaysTooltip`/`readerDualPageAlwaysLabel`/`readerDualPageNeverTooltip`/`readerDualPageNeverLabel`/`readerFullscreenModeLabel`/`readerShowFooterLabel`。
- Produces：`readerPdfSettingsTitle`/`readerPdfSettingsTabDisplay`/`readerPdfSettingsTabFilters`/`readerPdfSettingsTabCrop`/`readerPdfFitModeLabel`/`readerPdfFitPageTooltip`/`readerPdfFitPageLabel`/`readerPdfFitWidthTooltip`/`readerPdfFitWidthLabel`/`readerPdfFitActualTooltip`/`readerPdfFitActualLabel`/`readerPdfDualPageCoverAloneLabel`/`readerPdfPageOrientationLabel`/`readerPdfDirectionLtrTooltip`/`readerPdfDirectionLtrLabel`/`readerPdfDirectionRtlTooltip`/`readerPdfDirectionRtlLabel`/`readerPdfPageTurnAnimationLabel`/`readerPdfPageTurnAnimationSlide`/`readerPdfPageTurnAnimationNone`/`readerPdfContrastLabel`/`readerPdfBrightnessLabel`/`readerPdfBoldStrengthLabel`/`readerPdfCropModeLabel`/`readerPdfCropNoneTooltip`/`readerPdfCropNoneLabel`/`readerPdfCropAutoTooltip`/`readerPdfCropAutoLabel`/`readerPdfCropManualLabel`/`readerPdfCropManualTooltip`。

- [x] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "readerPdfSettingsTitle": "⚙️ PDF 版面設定",
  "@readerPdfSettingsTitle": { "description": "PDF 版面設定 Bottom Sheet 標題" },
  "readerPdfSettingsTabDisplay": "顯示",
  "@readerPdfSettingsTabDisplay": { "description": "PDF 版面設定第一個分頁籤：顯示" },
  "readerPdfSettingsTabFilters": "濾鏡",
  "@readerPdfSettingsTabFilters": { "description": "PDF 版面設定第二個分頁籤：濾鏡" },
  "readerPdfSettingsTabCrop": "裁切",
  "@readerPdfSettingsTabCrop": { "description": "PDF 版面設定第三個分頁籤：裁切" },
  "readerPdfFitModeLabel": "Fit 模式",
  "@readerPdfFitModeLabel": { "description": "PDF 顯示分頁「Fit 模式」選項群組小標題" },
  "readerPdfFitPageTooltip": "Page-fit（整頁）",
  "@readerPdfFitPageTooltip": { "description": "PDF Fit 模式「整頁」選項 tooltip" },
  "readerPdfFitPageLabel": "整頁",
  "@readerPdfFitPageLabel": { "description": "PDF Fit 模式「整頁」選項短標籤" },
  "readerPdfFitWidthTooltip": "Fit Width（頁寬）",
  "@readerPdfFitWidthTooltip": { "description": "PDF Fit 模式「頁寬」選項 tooltip" },
  "readerPdfFitWidthLabel": "頁寬",
  "@readerPdfFitWidthLabel": { "description": "PDF Fit 模式「頁寬」選項短標籤" },
  "readerPdfFitActualTooltip": "真實比例 1:1",
  "@readerPdfFitActualTooltip": { "description": "PDF Fit 模式「原比」選項 tooltip" },
  "readerPdfFitActualLabel": "原比",
  "@readerPdfFitActualLabel": { "description": "PDF Fit 模式「原比」選項短標籤" },
  "readerPdfDualPageCoverAloneLabel": "封面獨立顯示",
  "@readerPdfDualPageCoverAloneLabel": { "description": "PDF 雙頁模式「封面獨立顯示」開關標題" },
  "readerPdfPageOrientationLabel": "頁面方向",
  "@readerPdfPageOrientationLabel": { "description": "PDF 顯示分頁「頁面方向」選項群組小標題" },
  "readerPdfDirectionLtrTooltip": "左到右",
  "@readerPdfDirectionLtrTooltip": { "description": "PDF 頁面方向「左到右」選項 tooltip" },
  "readerPdfDirectionLtrLabel": "左翻",
  "@readerPdfDirectionLtrLabel": { "description": "PDF 頁面方向「左到右」選項短標籤" },
  "readerPdfDirectionRtlTooltip": "右到左（日漫慣例）",
  "@readerPdfDirectionRtlTooltip": { "description": "PDF 頁面方向「右到左」選項 tooltip" },
  "readerPdfDirectionRtlLabel": "右翻",
  "@readerPdfDirectionRtlLabel": { "description": "PDF 頁面方向「右到左」選項短標籤" },
  "readerPdfPageTurnAnimationLabel": "換頁動畫",
  "@readerPdfPageTurnAnimationLabel": { "description": "PDF 顯示分頁「換頁動畫」選項群組小標題" },
  "readerPdfPageTurnAnimationSlide": "滑動",
  "@readerPdfPageTurnAnimationSlide": { "description": "換頁動畫「滑動」選項標籤與 tooltip（文字相同）" },
  "readerPdfPageTurnAnimationNone": "無",
  "@readerPdfPageTurnAnimationNone": { "description": "換頁動畫「無」選項標籤與 tooltip（文字相同）" },
  "readerPdfContrastLabel": "對比度",
  "@readerPdfContrastLabel": { "description": "PDF 濾鏡分頁「對比度」滑桿標籤" },
  "readerPdfBrightnessLabel": "亮度",
  "@readerPdfBrightnessLabel": { "description": "PDF 濾鏡分頁「亮度」滑桿標籤" },
  "readerPdfBoldStrengthLabel": "加粗強度",
  "@readerPdfBoldStrengthLabel": { "description": "PDF 濾鏡分頁「加粗強度」滑桿標籤" },
  "readerPdfCropModeLabel": "裁切模式",
  "@readerPdfCropModeLabel": { "description": "PDF 裁切分頁「裁切模式」選項群組小標題" },
  "readerPdfCropNoneTooltip": "不裁切",
  "@readerPdfCropNoneTooltip": { "description": "裁切模式「不裁切」選項 tooltip" },
  "readerPdfCropNoneLabel": "不裁",
  "@readerPdfCropNoneLabel": { "description": "裁切模式「不裁切」選項短標籤" },
  "readerPdfCropAutoTooltip": "智慧自動",
  "@readerPdfCropAutoTooltip": { "description": "裁切模式「智慧自動」選項 tooltip" },
  "readerPdfCropAutoLabel": "智慧",
  "@readerPdfCropAutoLabel": { "description": "裁切模式「智慧自動」選項短標籤" },
  "readerPdfCropManualLabel": "手動",
  "@readerPdfCropManualLabel": { "description": "裁切模式「手動」選項短標籤" },
  "readerPdfCropManualTooltip": "手動選區",
  "@readerPdfCropManualTooltip": { "description": "裁切模式「手動」選項 tooltip" }
```

`app_zh_CN.arb`：
```json
  "readerPdfSettingsTitle": "⚙️ PDF 版面设定",
  "readerPdfSettingsTabDisplay": "显示",
  "readerPdfSettingsTabFilters": "滤镜",
  "readerPdfSettingsTabCrop": "裁切",
  "readerPdfFitModeLabel": "Fit 模式",
  "readerPdfFitPageTooltip": "Page-fit（整页）",
  "readerPdfFitPageLabel": "整页",
  "readerPdfFitWidthTooltip": "Fit Width（页宽）",
  "readerPdfFitWidthLabel": "页宽",
  "readerPdfFitActualTooltip": "真实比例 1:1",
  "readerPdfFitActualLabel": "原比",
  "readerPdfDualPageCoverAloneLabel": "封面独立显示",
  "readerPdfPageOrientationLabel": "页面方向",
  "readerPdfDirectionLtrTooltip": "左到右",
  "readerPdfDirectionLtrLabel": "左翻",
  "readerPdfDirectionRtlTooltip": "右到左（日漫惯例）",
  "readerPdfDirectionRtlLabel": "右翻",
  "readerPdfPageTurnAnimationLabel": "换页动画",
  "readerPdfPageTurnAnimationSlide": "滑动",
  "readerPdfPageTurnAnimationNone": "无",
  "readerPdfContrastLabel": "对比度",
  "readerPdfBrightnessLabel": "亮度",
  "readerPdfBoldStrengthLabel": "加粗强度",
  "readerPdfCropModeLabel": "裁切模式",
  "readerPdfCropNoneTooltip": "不裁切",
  "readerPdfCropNoneLabel": "不裁",
  "readerPdfCropAutoTooltip": "智能自动",
  "readerPdfCropAutoLabel": "智能",
  "readerPdfCropManualLabel": "手动",
  "readerPdfCropManualTooltip": "手动选区"
```

`app_en.arb`：
```json
  "readerPdfSettingsTitle": "⚙️ PDF Layout Settings",
  "readerPdfSettingsTabDisplay": "Display",
  "readerPdfSettingsTabFilters": "Filters",
  "readerPdfSettingsTabCrop": "Crop",
  "readerPdfFitModeLabel": "Fit mode",
  "readerPdfFitPageTooltip": "Page-fit",
  "readerPdfFitPageLabel": "Page",
  "readerPdfFitWidthTooltip": "Fit Width",
  "readerPdfFitWidthLabel": "Width",
  "readerPdfFitActualTooltip": "Actual size 1:1",
  "readerPdfFitActualLabel": "Actual",
  "readerPdfDualPageCoverAloneLabel": "Show cover alone",
  "readerPdfPageOrientationLabel": "Page direction",
  "readerPdfDirectionLtrTooltip": "Left to right",
  "readerPdfDirectionLtrLabel": "LTR",
  "readerPdfDirectionRtlTooltip": "Right to left (manga convention)",
  "readerPdfDirectionRtlLabel": "RTL",
  "readerPdfPageTurnAnimationLabel": "Page-turn animation",
  "readerPdfPageTurnAnimationSlide": "Slide",
  "readerPdfPageTurnAnimationNone": "None",
  "readerPdfContrastLabel": "Contrast",
  "readerPdfBrightnessLabel": "Brightness",
  "readerPdfBoldStrengthLabel": "Bold strength",
  "readerPdfCropModeLabel": "Crop mode",
  "readerPdfCropNoneTooltip": "No crop",
  "readerPdfCropNoneLabel": "None",
  "readerPdfCropAutoTooltip": "Smart auto-crop",
  "readerPdfCropAutoLabel": "Smart",
  "readerPdfCropManualLabel": "Manual",
  "readerPdfCropManualTooltip": "Manual selection"
```

`app_zh.arb`：
```json
  "readerPdfSettingsTitle": "⚙️ PDF 版面設定",
  "readerPdfSettingsTabDisplay": "顯示",
  "readerPdfSettingsTabFilters": "濾鏡",
  "readerPdfSettingsTabCrop": "裁切",
  "readerPdfFitModeLabel": "Fit 模式",
  "readerPdfFitPageTooltip": "Page-fit（整頁）",
  "readerPdfFitPageLabel": "整頁",
  "readerPdfFitWidthTooltip": "Fit Width（頁寬）",
  "readerPdfFitWidthLabel": "頁寬",
  "readerPdfFitActualTooltip": "真實比例 1:1",
  "readerPdfFitActualLabel": "原比",
  "readerPdfDualPageCoverAloneLabel": "封面獨立顯示",
  "readerPdfPageOrientationLabel": "頁面方向",
  "readerPdfDirectionLtrTooltip": "左到右",
  "readerPdfDirectionLtrLabel": "左翻",
  "readerPdfDirectionRtlTooltip": "右到左（日漫慣例）",
  "readerPdfDirectionRtlLabel": "右翻",
  "readerPdfPageTurnAnimationLabel": "換頁動畫",
  "readerPdfPageTurnAnimationSlide": "滑動",
  "readerPdfPageTurnAnimationNone": "無",
  "readerPdfContrastLabel": "對比度",
  "readerPdfBrightnessLabel": "亮度",
  "readerPdfBoldStrengthLabel": "加粗強度",
  "readerPdfCropModeLabel": "裁切模式",
  "readerPdfCropNoneTooltip": "不裁切",
  "readerPdfCropNoneLabel": "不裁",
  "readerPdfCropAutoTooltip": "智慧自動",
  "readerPdfCropAutoLabel": "智慧",
  "readerPdfCropManualLabel": "手動",
  "readerPdfCropManualTooltip": "手動選區"
```

- [x] **Step 2: 執行 `flutter gen-l10n`**

- [x] **Step 3: 修改 `pdf_settings_sheet.dart`**

新增 import：`import '../l10n/app_localizations.dart';`

`build()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`，替換：
- `'⚙️ PDF 版面設定'` → `l10n.readerPdfSettingsTitle`
- `Tab(key: Key('pdf_settings_tab_display'), text: '顯示')` → `text: l10n.readerPdfSettingsTabDisplay`（同理 `_tab_filters`/`濾鏡`→`readerPdfSettingsTabFilters`、`_tab_crop`/`裁切`→`readerPdfSettingsTabCrop`；`const [...]` 陣列因子項不再是常數改為非 `const`）

`_buildDisplayTab(BuildContext context)` 方法開頭新增 `final l10n = AppLocalizations.of(context)!;`，`fitOptions`／`dualPageOptions`／`directionOptions`／`pageTurnAnimationOptions` 四個 `const [...]` 皆改為非 `const` `final [...]`，依下表替換元組內容：

| 原 tuple 元素 | 新表達式 |
|---|---|
| `'Page-fit（整頁）'`／`'整頁'` | `l10n.readerPdfFitPageTooltip`／`l10n.readerPdfFitPageLabel` |
| `'Fit Width（頁寬）'`／`'頁寬'` | `l10n.readerPdfFitWidthTooltip`／`l10n.readerPdfFitWidthLabel` |
| `'真實比例 1:1'`／`'原比'` | `l10n.readerPdfFitActualTooltip`／`l10n.readerPdfFitActualLabel` |
| `'自動（橫向雙頁）'`／`'自動'` | `l10n.readerDualPageAutoTooltip`／`l10n.readerDualPageAutoLabel`（Task 12 共用 key） |
| `'永遠雙頁'`／`'雙頁'` | `l10n.readerDualPageAlwaysTooltip`／`l10n.readerDualPageAlwaysLabel`（Task 12 共用 key） |
| `'永遠單頁'`／`'單頁'` | `l10n.readerDualPageNeverTooltip`／`l10n.readerDualPageNeverLabel`（Task 12 共用 key） |
| `'左到右'`／`'左翻'` | `l10n.readerPdfDirectionLtrTooltip`／`l10n.readerPdfDirectionLtrLabel` |
| `'右到左（日漫慣例）'`／`'右翻'` | `l10n.readerPdfDirectionRtlTooltip`／`l10n.readerPdfDirectionRtlLabel` |
| `'滑動'`／`'滑動'` | `l10n.readerPdfPageTurnAnimationSlide`（label／tooltip 共用） |
| `'無'`／`'無'` | `l10n.readerPdfPageTurnAnimationNone`（label／tooltip 共用） |

同方法內文字標題：`'Fit 模式'`→`l10n.readerPdfFitModeLabel`、`'雙頁模式'`→`l10n.readerDualPageModeLabel`（Task 12 共用 key）、`'封面獨立顯示'`（`SwitchListTile.title`）→`Text(l10n.readerPdfDualPageCoverAloneLabel, ...)`、`'顯示頁尾'`→`Text(l10n.readerShowFooterLabel, ...)`（Task 12 共用 key）、`'全螢幕模式'`→`Text(l10n.readerFullscreenModeLabel, ...)`（Task 12 共用 key）、`'頁面方向'`→`l10n.readerPdfPageOrientationLabel`、`'換頁動畫'`→`l10n.readerPdfPageTurnAnimationLabel`。

`_buildFiltersTab()` 方法開頭新增 `final l10n = AppLocalizations.of(context)!;`，三處 `_buildSliderRow(label: '對比度', ...)`／`'亮度'`／`'加粗強度'` 分別改為 `l10n.readerPdfContrastLabel`／`l10n.readerPdfBrightnessLabel`／`l10n.readerPdfBoldStrengthLabel`。

`_buildCropTab(BuildContext context)` 方法開頭新增 `final l10n = AppLocalizations.of(context)!;`，`const options = [...]` 改為非 `const` `final options = [...]`：
- `'不裁切'`／`'不裁'` → `l10n.readerPdfCropNoneTooltip`／`l10n.readerPdfCropNoneLabel`
- `'智慧自動'`／`'智慧'` → `l10n.readerPdfCropAutoTooltip`／`l10n.readerPdfCropAutoLabel`
- `'裁切模式'` → `l10n.readerPdfCropModeLabel`
- 手動選區 `EBOptionChipItem`：`label: '手動'` → `l10n.readerPdfCropManualLabel`，`tooltip: '手動選區'` → `l10n.readerPdfCropManualTooltip`

- [x] **Step 4: 遷移既有測試檔（3 處 `MaterialApp(`）**

`app/test/screens/pdf_settings_sheet_test.dart` 3 處補上 l10n 三參數。

- [x] **Step 5: 新增英文渲染驗證測試**

新增 `testWidgets('英文介面下分頁籤/Fit 模式/裁切模式文字正確以英文渲染', ...)`，`locale: const Locale('en')`，斷言 `find.text('Display')`／`find.text('Filters')`／`find.text('Crop')`。

- [x] **Step 6: 執行測試確認全數通過**

Run: `flutter test test/screens/pdf_settings_sheet_test.dart`

- [x] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/pdf_settings_sheet.dart test/screens/pdf_settings_sheet_test.dart`

- [x] **Step 8: Commit**

```bash
git add app/lib/screens/pdf_settings_sheet.dart app/test/screens/pdf_settings_sheet_test.dart app/lib/l10n/
git commit -m "feat(epic-45): pdf_settings_sheet.dart 字串抽取三語言在地化"
```

---

### Task 15: `reader_settings_sheet.dart`（production 第 1 部分：標題／文字分頁／邊界分頁）

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`；Task 12 共用 key `readerShowHeaderLabel`/`readerShowFooterLabel`/`readerUseGlobalDefaultTooltip`。
- Produces：`readerSettingsTitle`/`readerSettingsTabText`/`readerSettingsTabBoundary`/`readerSettingsTabPresentation`/`readerSettingsTabPreferences`/`readerSettingsFontSizeLabel`/`readerSettingsFontWeightLabel`/`readerSettingsLineHeightLabel`/`readerSettingsParagraphSpacingLabel`/`readerSettingsLetterSpacingLabel`/`readerSettingsDisableBookCssLabel`/`readerSettingsMarginTopLabel`/`readerSettingsMarginBottomLabel`/`readerSettingsMarginLeftLabel`/`readerSettingsMarginRightLabel`/`readerSettingsOverriddenBadge`/`readerSettingsResetToBookStyleTooltip`/`readerSettingsNotOverriddenTooltip`/`readerSettingsUseBookFontLabel`（本 Task 建立但也供 Task 16 使用：`readerSettingsTabPresentation`/`readerSettingsTabPreferences`）。

**計劃範圍澄清**：`reader_settings_sheet.dart` 依 Global Constraints「不得抽成獨立 StatefulWidget」的既有不可逆技術決策，全檔案 4 個 `_buildXxxTab()` 皆是同一個 `_ReaderSettingsSheetState` 的方法；本 Task 只處理 `build()`（標題列＋ TabBar 4 個標籤）與 `_buildTextContentTab()`／`_buildBoundaryTab()`／`_buildFontFamilyDropdown()`／`_buildOverrideBadge()`／`_buildSliderRow()` 五個方法，`_fontDisplayName()`（字型品牌名，Global Constraints 明訂不翻譯）不動。

- [x] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "readerSettingsTitle": "⚙️ 版面設定",
  "@readerSettingsTitle": { "description": "EPUB 版面設定 Bottom Sheet 標題" },
  "readerSettingsTabText": "文字",
  "@readerSettingsTabText": { "description": "版面設定第一個分頁籤：文字" },
  "readerSettingsTabBoundary": "邊界",
  "@readerSettingsTabBoundary": { "description": "版面設定第二個分頁籤：邊界" },
  "readerSettingsTabPresentation": "呈現",
  "@readerSettingsTabPresentation": { "description": "版面設定第三個分頁籤：呈現" },
  "readerSettingsTabPreferences": "預設集",
  "@readerSettingsTabPreferences": { "description": "版面設定第四個分頁籤：預設集" },
  "readerSettingsFontSizeLabel": "字級",
  "@readerSettingsFontSizeLabel": { "description": "文字分頁「字級」滑桿標籤" },
  "readerSettingsFontWeightLabel": "字重",
  "@readerSettingsFontWeightLabel": { "description": "文字分頁「字重」滑桿標籤" },
  "readerSettingsLineHeightLabel": "行距",
  "@readerSettingsLineHeightLabel": { "description": "文字分頁「行距」滑桿標籤" },
  "readerSettingsParagraphSpacingLabel": "段落間距",
  "@readerSettingsParagraphSpacingLabel": { "description": "文字分頁「段落間距」滑桿標籤" },
  "readerSettingsLetterSpacingLabel": "字距",
  "@readerSettingsLetterSpacingLabel": { "description": "文字分頁「字距」滑桿標籤" },
  "readerSettingsDisableBookCssLabel": "停用書本 CSS",
  "@readerSettingsDisableBookCssLabel": { "description": "文字分頁「停用書本 CSS」開關標題" },
  "readerSettingsMarginTopLabel": "上邊界",
  "@readerSettingsMarginTopLabel": { "description": "邊界分頁「上邊界」滑桿標籤" },
  "readerSettingsMarginBottomLabel": "下邊界",
  "@readerSettingsMarginBottomLabel": { "description": "邊界分頁「下邊界」滑桿標籤" },
  "readerSettingsMarginLeftLabel": "左邊界",
  "@readerSettingsMarginLeftLabel": { "description": "邊界分頁「左邊界」滑桿標籤" },
  "readerSettingsMarginRightLabel": "右邊界",
  "@readerSettingsMarginRightLabel": { "description": "邊界分頁「右邊界」滑桿標籤" },
  "readerSettingsOverriddenBadge": "此書已覆寫",
  "@readerSettingsOverriddenBadge": { "description": "數值型設定已對本書覆寫時顯示的徽章文字" },
  "readerSettingsResetToBookStyleTooltip": "恢復本書原樣式",
  "@readerSettingsResetToBookStyleTooltip": { "description": "已覆寫欄位旁「恢復本書原樣式」按鈕的無障礙提示文字" },
  "readerSettingsNotOverriddenTooltip": "跟隨本書原樣式，尚未調整",
  "@readerSettingsNotOverriddenTooltip": { "description": "未覆寫欄位「使用全域預設」徽章的 Tooltip 說明文字" },
  "readerSettingsUseBookFontLabel": "使用書本內建字型",
  "@readerSettingsUseBookFontLabel": { "description": "字型下拉選單「使用書本內建字型」選項（不指定自訂字型）" }
```

`app_zh_CN.arb`：
```json
  "readerSettingsTitle": "⚙️ 版面设定",
  "readerSettingsTabText": "文字",
  "readerSettingsTabBoundary": "边界",
  "readerSettingsTabPresentation": "呈现",
  "readerSettingsTabPreferences": "预设集",
  "readerSettingsFontSizeLabel": "字级",
  "readerSettingsFontWeightLabel": "字重",
  "readerSettingsLineHeightLabel": "行距",
  "readerSettingsParagraphSpacingLabel": "段落间距",
  "readerSettingsLetterSpacingLabel": "字距",
  "readerSettingsDisableBookCssLabel": "停用书本 CSS",
  "readerSettingsMarginTopLabel": "上边界",
  "readerSettingsMarginBottomLabel": "下边界",
  "readerSettingsMarginLeftLabel": "左边界",
  "readerSettingsMarginRightLabel": "右边界",
  "readerSettingsOverriddenBadge": "此书已覆盖",
  "readerSettingsResetToBookStyleTooltip": "恢复本书原样式",
  "readerSettingsNotOverriddenTooltip": "跟随本书原样式，尚未调整",
  "readerSettingsUseBookFontLabel": "使用书本内建字体"
```

`app_en.arb`：
```json
  "readerSettingsTitle": "⚙️ Layout Settings",
  "readerSettingsTabText": "Text",
  "readerSettingsTabBoundary": "Margins",
  "readerSettingsTabPresentation": "Display",
  "readerSettingsTabPreferences": "Presets",
  "readerSettingsFontSizeLabel": "Font size",
  "readerSettingsFontWeightLabel": "Font weight",
  "readerSettingsLineHeightLabel": "Line height",
  "readerSettingsParagraphSpacingLabel": "Paragraph spacing",
  "readerSettingsLetterSpacingLabel": "Letter spacing",
  "readerSettingsDisableBookCssLabel": "Disable book CSS",
  "readerSettingsMarginTopLabel": "Top margin",
  "readerSettingsMarginBottomLabel": "Bottom margin",
  "readerSettingsMarginLeftLabel": "Left margin",
  "readerSettingsMarginRightLabel": "Right margin",
  "readerSettingsOverriddenBadge": "Overridden for this book",
  "readerSettingsResetToBookStyleTooltip": "Reset to book's original style",
  "readerSettingsNotOverriddenTooltip": "Following book's original style, not yet adjusted",
  "readerSettingsUseBookFontLabel": "Use book's built-in font"
```

`app_zh.arb`：
```json
  "readerSettingsTitle": "⚙️ 版面設定",
  "readerSettingsTabText": "文字",
  "readerSettingsTabBoundary": "邊界",
  "readerSettingsTabPresentation": "呈現",
  "readerSettingsTabPreferences": "預設集",
  "readerSettingsFontSizeLabel": "字級",
  "readerSettingsFontWeightLabel": "字重",
  "readerSettingsLineHeightLabel": "行距",
  "readerSettingsParagraphSpacingLabel": "段落間距",
  "readerSettingsLetterSpacingLabel": "字距",
  "readerSettingsDisableBookCssLabel": "停用書本 CSS",
  "readerSettingsMarginTopLabel": "上邊界",
  "readerSettingsMarginBottomLabel": "下邊界",
  "readerSettingsMarginLeftLabel": "左邊界",
  "readerSettingsMarginRightLabel": "右邊界",
  "readerSettingsOverriddenBadge": "此書已覆寫",
  "readerSettingsResetToBookStyleTooltip": "恢復本書原樣式",
  "readerSettingsNotOverriddenTooltip": "跟隨本書原樣式，尚未調整",
  "readerSettingsUseBookFontLabel": "使用書本內建字型"
```

- [x] **Step 2: 執行 `flutter gen-l10n`**

- [x] **Step 3: 修改 `reader_settings_sheet.dart`**

新增 import：`import '../l10n/app_localizations.dart';`

`build()` 方法：標題 `Text('⚙️ 版面設定', ...)` → `Text(AppLocalizations.of(context)!.readerSettingsTitle, ...)`；4 個 `Tab(text: ...)` 依序改為 `l10n.readerSettingsTabText`/`readerSettingsTabBoundary`/`readerSettingsTabPresentation`/`readerSettingsTabPreferences`（`const TabBar(...)` 因子項不再是常數，移除該層 `const`；`build()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`）。

`_buildTextContentTab()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`，5 個 `_buildSliderRow(label: 'X', ...)` 呼叫的 `label:` 依序改為 `l10n.readerSettingsFontSizeLabel`/`readerSettingsFontWeightLabel`/`readerSettingsLineHeightLabel`/`readerSettingsParagraphSpacingLabel`/`readerSettingsLetterSpacingLabel`；`SwitchListTile(title: const Text('停用書本 CSS', ...))` → `title: Text(l10n.readerSettingsDisableBookCssLabel, ...)`（移除 `const`）。

`_buildBoundaryTab()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`，4 個 `_buildSliderRow(label: 'X邊界', ...)` 依序改為 `l10n.readerSettingsMarginTopLabel`/`readerSettingsMarginBottomLabel`/`readerSettingsMarginLeftLabel`/`readerSettingsMarginRightLabel`；`'顯示頁首'`／`'顯示頁尾'`（`SwitchListTile.title`）分別改為 `Text(l10n.readerShowHeaderLabel, ...)`／`Text(l10n.readerShowFooterLabel, ...)`（Task 12 共用 key）。

`_buildFontFamilyDropdown()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`，`DropdownMenuItem<String?>(value: null, child: Text('使用書本內建字型', ...))` → `Text(l10n.readerSettingsUseBookFontLabel, ...)`。

`_buildOverrideBadge()` 方法簽章不變，呼叫端傳入的文字改變即可（見下方 `_buildSliderRow`），方法本體不動。

`_buildSliderRow()` 方法開頭新增 `final l10n = AppLocalizations.of(context)!;`，3 處文字替換：
```dart
                _buildOverrideBadge(l10n.readerSettingsOverriddenBadge),
                IconButton(
                  key: Key('${keyPrefix}_reset'),
                  icon: const Icon(Icons.block),
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.readerSettingsResetToBookStyleTooltip,
                  onPressed: onReset,
                ),
              ],
            )
          else if (isOverridden == false)
            Tooltip(
              message: l10n.readerSettingsNotOverriddenTooltip,
              child: _buildOverrideBadge(
                l10n.readerUseGlobalDefaultTooltip,
                key: Key('${keyPrefix}_unset_indicator'),
              ),
            ),
```
（`'此書已覆寫'`→`l10n.readerSettingsOverriddenBadge`、`'恢復本書原樣式'`→`l10n.readerSettingsResetToBookStyleTooltip`、`'跟隨本書原樣式，尚未調整'`→`l10n.readerSettingsNotOverriddenTooltip`、`'使用全域預設'`徽章文字→`l10n.readerUseGlobalDefaultTooltip`〔Task 12 共用 key〕；其餘 `EBStepper`／`Slider`／`IconButton` 結構不動。）

- [x] **Step 4: 執行測試確認未觸及的測試檔仍通過（本 Task 不遷移測試，預期紅燈）**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: `Null check operator used on a null value`，留給 Task 17 修復。

- [x] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/reader_settings_sheet.dart`

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/lib/l10n/
git commit -m "feat(epic-45): reader_settings_sheet.dart 字串抽取第 1 部分（標題/文字分頁/邊界分頁）"
```

---

### Task 16: `reader_settings_sheet.dart`（production 第 2 部分：呈現分頁／預設集分頁）

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`；Task 12 共用 key `readerFullscreenModeLabel`/`readerGlobalLabel`/`readerUseGlobalDefaultTooltip`/`readerTextConversionOverrideLabel`/`readerTextConversionOriginalLabel`/`readerTextConversionTraditionalLabel`/`readerTextConversionTraditionalTooltip`/`readerTextConversionSimplifiedLabel`/`readerTextConversionSimplifiedTooltip`；Task 11 共用 key `readerDeleteConfirmButton`（誤用排除，見下方，本檔案套用/刪除按鈕不使用該 key，各自獨立）。
- Produces：`readerSettingsColumnCountLabel`/`readerSettingsColumnAutoLabel`/`readerSettingsColumnSingleLabel`/`readerSettingsColumnDoubleLabel`/`readerSettingsColumnSizeLabel`/`readerSettingsColumnSizeWithValueLabel`/`readerSettingsTextAlignLabel`/`readerSettingsTextAlignCenterLabel`/`readerSettingsTextAlignJustifyTooltip`/`readerSettingsTextAlignJustifyLabel`/`readerSettingsTextAlignStartTooltip`/`readerSettingsTextAlignStartLabel`/`readerSettingsTextAlignEndTooltip`/`readerSettingsTextAlignEndLabel`/`readerSettingsTextAlignLeftLabel`/`readerSettingsTextAlignRightLabel`/`readerSettingsWritingModeLabel`/`readerSettingsWritingModeBookTooltip`/`readerSettingsWritingModeBookLabel`/`readerSettingsWritingModeVerticalTooltip`/`readerSettingsWritingModeVerticalLabel`/`readerSettingsWritingModeHorizontalTooltip`/`readerSettingsWritingModeHorizontalLabel`/`readerSettingsPageTurnModeLabel`/`readerSettingsPageTurnPaginatedTooltip`/`readerSettingsPageTurnPaginatedLabel`/`readerSettingsPageTurnScrollTooltip`/`readerSettingsPageTurnScrollLabel`/`readerSettingsScreenOrientationLabel`/`readerSettingsOrientationAutoTooltip`/`readerSettingsOrientationAutoLabel`/`readerSettingsOrientationLock0Tooltip`/`readerSettingsOrientationLock90Tooltip`/`readerSettingsOrientationLock180Tooltip`/`readerSettingsOrientationLock270Tooltip`/`readerSettingsSaveAsPresetButton`/`readerSettingsSavedPresetsLabel`/`readerSettingsCopyFromBookLabel`/`readerSettingsCopyToCurrentBookButton`/`readerSettingsCopyToOtherBooksButton`/`readerSettingsResetPresetTitle`/`readerSettingsResetPresetSubtitle`/`readerSettingsApplyButton`/`readerSettingsPresetDefaultValue`/`readerSettingsPresetSummaryAutoLabel`/`readerSettingsPresetSummaryFormat`/`readerSettingsPresetEmptySlot`/`readerSettingsApplyToOtherBooksTooltip`/`readerSettingsDeletePresetTooltip`。

**計劃範圍澄清**：0°／90°／180°／270° 這四個螢幕方向覆寫選項的**短標籤**（`label`，例如 `'0°'`）是語言無關的純數字＋角度符號記號，不經 ARB 翻譯，維持 Dart 字面值；但**tooltip**（例如 `'鎖定 0°'`）含動詞，三語言用字不同，需要 ARB key。

- [x] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "readerSettingsColumnCountLabel": "欄數",
  "@readerSettingsColumnCountLabel": { "description": "呈現分頁「欄數」選項群組小標題" },
  "readerSettingsColumnAutoLabel": "自動",
  "@readerSettingsColumnAutoLabel": { "description": "欄數「自動」選項標籤與 tooltip（文字相同）" },
  "readerSettingsColumnSingleLabel": "單欄",
  "@readerSettingsColumnSingleLabel": { "description": "欄數「單欄」選項標籤與 tooltip" },
  "readerSettingsColumnDoubleLabel": "雙欄",
  "@readerSettingsColumnDoubleLabel": { "description": "欄數「雙欄」選項標籤與 tooltip" },
  "readerSettingsColumnSizeLabel": "欄位大小",
  "@readerSettingsColumnSizeLabel": { "description": "E-Ink 模式下欄位大小標題（不含數值，避免與 EBStepper 內顯示的數值重複）" },
  "readerSettingsColumnSizeWithValueLabel": "欄位大小 {size}px",
  "@readerSettingsColumnSizeWithValueLabel": {
    "description": "一般主題下欄位大小標題（含目前數值），{size} 為像素數",
    "placeholders": { "size": { "type": "int" } }
  },
  "readerSettingsTextAlignLabel": "文字對齊",
  "@readerSettingsTextAlignLabel": { "description": "呈現分頁「文字對齊」選項群組小標題" },
  "readerSettingsTextAlignCenterLabel": "置中",
  "@readerSettingsTextAlignCenterLabel": { "description": "文字對齊「置中」選項標籤與 tooltip" },
  "readerSettingsTextAlignJustifyTooltip": "左右對齊",
  "@readerSettingsTextAlignJustifyTooltip": { "description": "文字對齊「齊行」選項 tooltip" },
  "readerSettingsTextAlignJustifyLabel": "齊行",
  "@readerSettingsTextAlignJustifyLabel": { "description": "文字對齊「齊行」選項短標籤" },
  "readerSettingsTextAlignStartTooltip": "起始邊對齊",
  "@readerSettingsTextAlignStartTooltip": { "description": "文字對齊「起始」選項 tooltip" },
  "readerSettingsTextAlignStartLabel": "起始",
  "@readerSettingsTextAlignStartLabel": { "description": "文字對齊「起始」選項短標籤" },
  "readerSettingsTextAlignEndTooltip": "結尾邊對齊",
  "@readerSettingsTextAlignEndTooltip": { "description": "文字對齊「結尾」選項 tooltip" },
  "readerSettingsTextAlignEndLabel": "結尾",
  "@readerSettingsTextAlignEndLabel": { "description": "文字對齊「結尾」選項短標籤" },
  "readerSettingsTextAlignLeftLabel": "靠左",
  "@readerSettingsTextAlignLeftLabel": { "description": "文字對齊「靠左」選項標籤與 tooltip" },
  "readerSettingsTextAlignRightLabel": "靠右",
  "@readerSettingsTextAlignRightLabel": { "description": "文字對齊「靠右」選項標籤與 tooltip" },
  "readerSettingsWritingModeLabel": "排版方向模式",
  "@readerSettingsWritingModeLabel": { "description": "呈現分頁「排版方向模式」選項群組小標題" },
  "readerSettingsWritingModeBookTooltip": "採用書籍排版",
  "@readerSettingsWritingModeBookTooltip": { "description": "排版方向「採用書籍排版」選項 tooltip" },
  "readerSettingsWritingModeBookLabel": "書籍",
  "@readerSettingsWritingModeBookLabel": { "description": "排版方向「採用書籍排版」選項短標籤" },
  "readerSettingsWritingModeVerticalTooltip": "強制直排",
  "@readerSettingsWritingModeVerticalTooltip": { "description": "排版方向「強制直排」選項 tooltip" },
  "readerSettingsWritingModeVerticalLabel": "直排",
  "@readerSettingsWritingModeVerticalLabel": { "description": "排版方向「強制直排」選項短標籤，亦供預設集摘要文字重用" },
  "readerSettingsWritingModeHorizontalTooltip": "強制橫排",
  "@readerSettingsWritingModeHorizontalTooltip": { "description": "排版方向「強制橫排」選項 tooltip" },
  "readerSettingsWritingModeHorizontalLabel": "橫排",
  "@readerSettingsWritingModeHorizontalLabel": { "description": "排版方向「強制橫排」選項短標籤，亦供預設集摘要文字重用" },
  "readerSettingsPageTurnModeLabel": "翻頁模式覆寫",
  "@readerSettingsPageTurnModeLabel": { "description": "呈現分頁「翻頁模式覆寫」選項群組小標題" },
  "readerSettingsPageTurnPaginatedTooltip": "點擊翻頁",
  "@readerSettingsPageTurnPaginatedTooltip": { "description": "翻頁模式「點擊翻頁」選項 tooltip" },
  "readerSettingsPageTurnPaginatedLabel": "點擊",
  "@readerSettingsPageTurnPaginatedLabel": { "description": "翻頁模式「點擊翻頁」選項短標籤" },
  "readerSettingsPageTurnScrollTooltip": "滾動翻頁",
  "@readerSettingsPageTurnScrollTooltip": { "description": "翻頁模式「滾動翻頁」選項 tooltip" },
  "readerSettingsPageTurnScrollLabel": "滾動",
  "@readerSettingsPageTurnScrollLabel": { "description": "翻頁模式「滾動翻頁」選項短標籤" },
  "readerSettingsScreenOrientationLabel": "螢幕方向鎖定覆寫",
  "@readerSettingsScreenOrientationLabel": { "description": "呈現分頁「螢幕方向鎖定覆寫」選項群組小標題" },
  "readerSettingsOrientationAutoTooltip": "自動旋轉",
  "@readerSettingsOrientationAutoTooltip": { "description": "螢幕方向「自動旋轉」選項 tooltip" },
  "readerSettingsOrientationAutoLabel": "自動",
  "@readerSettingsOrientationAutoLabel": { "description": "螢幕方向「自動旋轉」選項短標籤" },
  "readerSettingsOrientationLock0Tooltip": "鎖定 0°",
  "@readerSettingsOrientationLock0Tooltip": { "description": "螢幕方向「鎖定 0°」選項 tooltip" },
  "readerSettingsOrientationLock90Tooltip": "鎖定 90°",
  "@readerSettingsOrientationLock90Tooltip": { "description": "螢幕方向「鎖定 90°」選項 tooltip" },
  "readerSettingsOrientationLock180Tooltip": "鎖定 180°",
  "@readerSettingsOrientationLock180Tooltip": { "description": "螢幕方向「鎖定 180°」選項 tooltip" },
  "readerSettingsOrientationLock270Tooltip": "鎖定 270°",
  "@readerSettingsOrientationLock270Tooltip": { "description": "螢幕方向「鎖定 270°」選項 tooltip" },
  "readerSettingsSaveAsPresetButton": "將目前設定存為新預設集",
  "@readerSettingsSaveAsPresetButton": { "description": "預設集分頁「另存為新預設集」按鈕文字" },
  "readerSettingsSavedPresetsLabel": "已儲存的預設集",
  "@readerSettingsSavedPresetsLabel": { "description": "預設集分頁「已儲存的預設集」區塊標題" },
  "readerSettingsCopyFromBookLabel": "從其他書籍複製",
  "@readerSettingsCopyFromBookLabel": { "description": "預設集分頁「從其他書籍複製」區塊標題" },
  "readerSettingsCopyToCurrentBookButton": "複製到本書",
  "@readerSettingsCopyToCurrentBookButton": { "description": "「複製到本書」按鈕文字" },
  "readerSettingsCopyToOtherBooksButton": "複製到其他書籍",
  "@readerSettingsCopyToOtherBooksButton": { "description": "「複製到其他書籍」按鈕文字" },
  "readerSettingsResetPresetTitle": "系統預設",
  "@readerSettingsResetPresetTitle": { "description": "固定列（重設為本書原樣式）的標題" },
  "readerSettingsResetPresetSubtitle": "移除本書所有字級/字重/行距/段落間距/字距覆寫，改用書本原始樣式",
  "@readerSettingsResetPresetSubtitle": { "description": "固定列（重設為本書原樣式）的副標題說明" },
  "readerSettingsApplyButton": "套用",
  "@readerSettingsApplyButton": { "description": "預設集卡片列「套用」按鈕文字，固定列與各 preset slot 共用" },
  "readerSettingsPresetDefaultValue": "預設",
  "@readerSettingsPresetDefaultValue": { "description": "預設集摘要文字中，欄位未收錄時的回退顯示（例如字級/行距缺席）" },
  "readerSettingsPresetSummaryAutoLabel": "自動",
  "@readerSettingsPresetSummaryAutoLabel": { "description": "預設集摘要文字中，排版方向欄位為 null（自動偵測）時的顯示文字" },
  "readerSettingsPresetSummaryFormat": "字級{fontSize}・行距{lineHeight}・{writingMode}",
  "@readerSettingsPresetSummaryFormat": {
    "description": "預設集卡片副標題摘要格式，三個 placeholder 皆為已格式化完成的字串（含 readerSettingsPresetDefaultValue／readerSettingsPresetSummaryAutoLabel 等回退值）",
    "placeholders": {
      "fontSize": { "type": "String" },
      "lineHeight": { "type": "String" },
      "writingMode": { "type": "String" }
    }
  },
  "readerSettingsPresetEmptySlot": "（空）",
  "@readerSettingsPresetEmptySlot": { "description": "預設集尚未使用的空 slot 顯示文字" },
  "readerSettingsApplyToOtherBooksTooltip": "套用到其他書籍",
  "@readerSettingsApplyToOtherBooksTooltip": { "description": "預設集卡片列「套用到其他書籍」圖示按鈕的無障礙提示文字" },
  "readerSettingsDeletePresetTooltip": "刪除",
  "@readerSettingsDeletePresetTooltip": { "description": "預設集卡片列「刪除」圖示按鈕的無障礙提示文字" }
```

`app_zh_CN.arb`：
```json
  "readerSettingsColumnCountLabel": "栏数",
  "readerSettingsColumnAutoLabel": "自动",
  "readerSettingsColumnSingleLabel": "单栏",
  "readerSettingsColumnDoubleLabel": "双栏",
  "readerSettingsColumnSizeLabel": "栏位大小",
  "readerSettingsColumnSizeWithValueLabel": "栏位大小 {size}px",
  "readerSettingsTextAlignLabel": "文字对齐",
  "readerSettingsTextAlignCenterLabel": "置中",
  "readerSettingsTextAlignJustifyTooltip": "左右对齐",
  "readerSettingsTextAlignJustifyLabel": "齐行",
  "readerSettingsTextAlignStartTooltip": "起始边对齐",
  "readerSettingsTextAlignStartLabel": "起始",
  "readerSettingsTextAlignEndTooltip": "结尾边对齐",
  "readerSettingsTextAlignEndLabel": "结尾",
  "readerSettingsTextAlignLeftLabel": "靠左",
  "readerSettingsTextAlignRightLabel": "靠右",
  "readerSettingsWritingModeLabel": "排版方向模式",
  "readerSettingsWritingModeBookTooltip": "采用书籍排版",
  "readerSettingsWritingModeBookLabel": "书籍",
  "readerSettingsWritingModeVerticalTooltip": "强制直排",
  "readerSettingsWritingModeVerticalLabel": "直排",
  "readerSettingsWritingModeHorizontalTooltip": "强制横排",
  "readerSettingsWritingModeHorizontalLabel": "横排",
  "readerSettingsPageTurnModeLabel": "翻页模式覆盖",
  "readerSettingsPageTurnPaginatedTooltip": "点击翻页",
  "readerSettingsPageTurnPaginatedLabel": "点击",
  "readerSettingsPageTurnScrollTooltip": "滚动翻页",
  "readerSettingsPageTurnScrollLabel": "滚动",
  "readerSettingsScreenOrientationLabel": "屏幕方向锁定覆盖",
  "readerSettingsOrientationAutoTooltip": "自动旋转",
  "readerSettingsOrientationAutoLabel": "自动",
  "readerSettingsOrientationLock0Tooltip": "锁定 0°",
  "readerSettingsOrientationLock90Tooltip": "锁定 90°",
  "readerSettingsOrientationLock180Tooltip": "锁定 180°",
  "readerSettingsOrientationLock270Tooltip": "锁定 270°",
  "readerSettingsSaveAsPresetButton": "将目前设定存为新预设集",
  "readerSettingsSavedPresetsLabel": "已保存的预设集",
  "readerSettingsCopyFromBookLabel": "从其他书籍复制",
  "readerSettingsCopyToCurrentBookButton": "复制到本书",
  "readerSettingsCopyToOtherBooksButton": "复制到其他书籍",
  "readerSettingsResetPresetTitle": "系统预设",
  "readerSettingsResetPresetSubtitle": "移除本书所有字级/字重/行距/段落间距/字距覆盖，改用书本原始样式",
  "readerSettingsApplyButton": "套用",
  "readerSettingsPresetDefaultValue": "预设",
  "readerSettingsPresetSummaryAutoLabel": "自动",
  "readerSettingsPresetSummaryFormat": "字级{fontSize}・行距{lineHeight}・{writingMode}",
  "readerSettingsPresetEmptySlot": "（空）",
  "readerSettingsApplyToOtherBooksTooltip": "套用到其他书籍",
  "readerSettingsDeletePresetTooltip": "删除"
```

`app_en.arb`：
```json
  "readerSettingsColumnCountLabel": "Columns",
  "readerSettingsColumnAutoLabel": "Auto",
  "readerSettingsColumnSingleLabel": "Single",
  "readerSettingsColumnDoubleLabel": "Double",
  "readerSettingsColumnSizeLabel": "Column size",
  "readerSettingsColumnSizeWithValueLabel": "Column size {size}px",
  "readerSettingsTextAlignLabel": "Text align",
  "readerSettingsTextAlignCenterLabel": "Center",
  "readerSettingsTextAlignJustifyTooltip": "Justify",
  "readerSettingsTextAlignJustifyLabel": "Justify",
  "readerSettingsTextAlignStartTooltip": "Align to start edge",
  "readerSettingsTextAlignStartLabel": "Start",
  "readerSettingsTextAlignEndTooltip": "Align to end edge",
  "readerSettingsTextAlignEndLabel": "End",
  "readerSettingsTextAlignLeftLabel": "Left",
  "readerSettingsTextAlignRightLabel": "Right",
  "readerSettingsWritingModeLabel": "Writing mode override",
  "readerSettingsWritingModeBookTooltip": "Use book's writing mode",
  "readerSettingsWritingModeBookLabel": "Book",
  "readerSettingsWritingModeVerticalTooltip": "Force vertical",
  "readerSettingsWritingModeVerticalLabel": "Vertical",
  "readerSettingsWritingModeHorizontalTooltip": "Force horizontal",
  "readerSettingsWritingModeHorizontalLabel": "Horizontal",
  "readerSettingsPageTurnModeLabel": "Page-turn mode override",
  "readerSettingsPageTurnPaginatedTooltip": "Tap to turn page",
  "readerSettingsPageTurnPaginatedLabel": "Tap",
  "readerSettingsPageTurnScrollTooltip": "Scroll to read",
  "readerSettingsPageTurnScrollLabel": "Scroll",
  "readerSettingsScreenOrientationLabel": "Screen orientation lock override",
  "readerSettingsOrientationAutoTooltip": "Auto-rotate",
  "readerSettingsOrientationAutoLabel": "Auto",
  "readerSettingsOrientationLock0Tooltip": "Lock 0°",
  "readerSettingsOrientationLock90Tooltip": "Lock 90°",
  "readerSettingsOrientationLock180Tooltip": "Lock 180°",
  "readerSettingsOrientationLock270Tooltip": "Lock 270°",
  "readerSettingsSaveAsPresetButton": "Save current settings as new preset",
  "readerSettingsSavedPresetsLabel": "Saved presets",
  "readerSettingsCopyFromBookLabel": "Copy from another book",
  "readerSettingsCopyToCurrentBookButton": "Copy to this book",
  "readerSettingsCopyToOtherBooksButton": "Copy to other books",
  "readerSettingsResetPresetTitle": "System default",
  "readerSettingsResetPresetSubtitle": "Remove this book's font size/weight/line height/paragraph spacing/letter spacing overrides and use the book's original style",
  "readerSettingsApplyButton": "Apply",
  "readerSettingsPresetDefaultValue": "Default",
  "readerSettingsPresetSummaryAutoLabel": "Auto",
  "readerSettingsPresetSummaryFormat": "Size {fontSize} · Line height {lineHeight} · {writingMode}",
  "readerSettingsPresetEmptySlot": "(Empty)",
  "readerSettingsApplyToOtherBooksTooltip": "Apply to other books",
  "readerSettingsDeletePresetTooltip": "Delete"
```

`app_zh.arb`：
```json
  "readerSettingsColumnCountLabel": "欄數",
  "readerSettingsColumnAutoLabel": "自動",
  "readerSettingsColumnSingleLabel": "單欄",
  "readerSettingsColumnDoubleLabel": "雙欄",
  "readerSettingsColumnSizeLabel": "欄位大小",
  "readerSettingsColumnSizeWithValueLabel": "欄位大小 {size}px",
  "readerSettingsTextAlignLabel": "文字對齊",
  "readerSettingsTextAlignCenterLabel": "置中",
  "readerSettingsTextAlignJustifyTooltip": "左右對齊",
  "readerSettingsTextAlignJustifyLabel": "齊行",
  "readerSettingsTextAlignStartTooltip": "起始邊對齊",
  "readerSettingsTextAlignStartLabel": "起始",
  "readerSettingsTextAlignEndTooltip": "結尾邊對齊",
  "readerSettingsTextAlignEndLabel": "結尾",
  "readerSettingsTextAlignLeftLabel": "靠左",
  "readerSettingsTextAlignRightLabel": "靠右",
  "readerSettingsWritingModeLabel": "排版方向模式",
  "readerSettingsWritingModeBookTooltip": "採用書籍排版",
  "readerSettingsWritingModeBookLabel": "書籍",
  "readerSettingsWritingModeVerticalTooltip": "強制直排",
  "readerSettingsWritingModeVerticalLabel": "直排",
  "readerSettingsWritingModeHorizontalTooltip": "強制橫排",
  "readerSettingsWritingModeHorizontalLabel": "橫排",
  "readerSettingsPageTurnModeLabel": "翻頁模式覆寫",
  "readerSettingsPageTurnPaginatedTooltip": "點擊翻頁",
  "readerSettingsPageTurnPaginatedLabel": "點擊",
  "readerSettingsPageTurnScrollTooltip": "滾動翻頁",
  "readerSettingsPageTurnScrollLabel": "滾動",
  "readerSettingsScreenOrientationLabel": "螢幕方向鎖定覆寫",
  "readerSettingsOrientationAutoTooltip": "自動旋轉",
  "readerSettingsOrientationAutoLabel": "自動",
  "readerSettingsOrientationLock0Tooltip": "鎖定 0°",
  "readerSettingsOrientationLock90Tooltip": "鎖定 90°",
  "readerSettingsOrientationLock180Tooltip": "鎖定 180°",
  "readerSettingsOrientationLock270Tooltip": "鎖定 270°",
  "readerSettingsSaveAsPresetButton": "將目前設定存為新預設集",
  "readerSettingsSavedPresetsLabel": "已儲存的預設集",
  "readerSettingsCopyFromBookLabel": "從其他書籍複製",
  "readerSettingsCopyToCurrentBookButton": "複製到本書",
  "readerSettingsCopyToOtherBooksButton": "複製到其他書籍",
  "readerSettingsResetPresetTitle": "系統預設",
  "readerSettingsResetPresetSubtitle": "移除本書所有字級/字重/行距/段落間距/字距覆寫，改用書本原始樣式",
  "readerSettingsApplyButton": "套用",
  "readerSettingsPresetDefaultValue": "預設",
  "readerSettingsPresetSummaryAutoLabel": "自動",
  "readerSettingsPresetSummaryFormat": "字級{fontSize}・行距{lineHeight}・{writingMode}",
  "readerSettingsPresetEmptySlot": "（空）",
  "readerSettingsApplyToOtherBooksTooltip": "套用到其他書籍",
  "readerSettingsDeletePresetTooltip": "刪除"
```

- [x] **Step 2: 執行 `flutter gen-l10n`**

- [x] **Step 3: 修改 `reader_settings_sheet.dart`**

`_buildPresentationTab()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`，`SwitchListTile(title: const Text('全螢幕模式', ...))` → `Text(l10n.readerFullscreenModeLabel, ...)`（移除 `const`）。

`_buildColumnModeRow()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`，`[...].map(...)` 前的字面值陣列改為非 `const`，依表替換：

| 原 tuple 元素 | 新表達式 |
|---|---|
| `'欄數'`（Text 標題） | `l10n.readerSettingsColumnCountLabel` |
| `'自動'`／`'自動'`（auto） | `l10n.readerSettingsColumnAutoLabel`（label／tooltip 共用） |
| `'單欄'`／`'單欄'` | `l10n.readerSettingsColumnSingleLabel` |
| `'雙欄'`／`'雙欄'` | `l10n.readerSettingsColumnDoubleLabel` |
| `'欄位大小'`（isEinkMode 分支） | `l10n.readerSettingsColumnSizeLabel` |
| `'欄位大小 ${_columnSize.round()}px'`（一般主題分支） | `l10n.readerSettingsColumnSizeWithValueLabel(_columnSize.round())` |

`_buildTextAlignRow()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`，`const options = [...]` 改為非 `const`：

| 原 tuple | 新表達式 |
|---|---|
| `'置中'`／`'置中'` | `l10n.readerSettingsTextAlignCenterLabel` |
| `'左右對齊'`／`'齊行'` | `l10n.readerSettingsTextAlignJustifyTooltip`／`l10n.readerSettingsTextAlignJustifyLabel` |
| `'起始邊對齊'`／`'起始'` | `l10n.readerSettingsTextAlignStartTooltip`／`l10n.readerSettingsTextAlignStartLabel` |
| `'結尾邊對齊'`／`'結尾'` | `l10n.readerSettingsTextAlignEndTooltip`／`l10n.readerSettingsTextAlignEndLabel` |
| `'靠左'`／`'靠左'` | `l10n.readerSettingsTextAlignLeftLabel` |
| `'靠右'`／`'靠右'` | `l10n.readerSettingsTextAlignRightLabel` |

`'文字對齊'`（Text 標題）→ `l10n.readerSettingsTextAlignLabel`。

`_buildWritingModeOverrideRow()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`，`const options = [...]` 改為非 `const`：

| 原 tuple | 新表達式 |
|---|---|
| `'採用書籍排版'`／`'書籍'` | `l10n.readerSettingsWritingModeBookTooltip`／`l10n.readerSettingsWritingModeBookLabel` |
| `'強制直排'`／`'直排'` | `l10n.readerSettingsWritingModeVerticalTooltip`／`l10n.readerSettingsWritingModeVerticalLabel` |
| `'強制橫排'`／`'橫排'` | `l10n.readerSettingsWritingModeHorizontalTooltip`／`l10n.readerSettingsWritingModeHorizontalLabel` |

`'排版方向模式'`（Text 標題）→ `l10n.readerSettingsWritingModeLabel`。

`_buildPageTurnModeOverrideRow()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`，`const options = [...]` 改為非 `const`：

| 原 tuple | 新表達式 |
|---|---|
| `'使用全域預設'`／`'全域'` | `l10n.readerUseGlobalDefaultTooltip`／`l10n.readerGlobalLabel`（Task 12 共用 key） |
| `'點擊翻頁'`／`'點擊'` | `l10n.readerSettingsPageTurnPaginatedTooltip`／`l10n.readerSettingsPageTurnPaginatedLabel` |
| `'滾動翻頁'`／`'滾動'` | `l10n.readerSettingsPageTurnScrollTooltip`／`l10n.readerSettingsPageTurnScrollLabel` |

`'翻頁模式覆寫'`（Text 標題）→ `l10n.readerSettingsPageTurnModeLabel`。

`_buildTextConversionOverrideRow()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`，`items` 列表（原本是 `final items = [const EBOptionChipItem(...), ...]`，四個 `const` 子項因值不再是常數個別移除 `const`）依 Task 12 共用 key 替換：`'全域'`／`'使用全域預設'`→`l10n.readerGlobalLabel`／`l10n.readerUseGlobalDefaultTooltip`；`'原文'`→`l10n.readerTextConversionOriginalLabel`；`'繁體'`／`'轉換為繁體'`→`l10n.readerTextConversionTraditionalLabel`／`l10n.readerTextConversionTraditionalTooltip`；`'簡體'`／`'轉換為簡體'`→`l10n.readerTextConversionSimplifiedLabel`／`l10n.readerTextConversionSimplifiedTooltip`。`'簡繁轉換覆寫'`（Text 標題）→ `l10n.readerTextConversionOverrideLabel`（Task 12 共用 key）。

`_buildScreenOrientationOverrideRow()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`，`const options = <(...)>[...]` 改為非 `const`；**label 維持字面值 `'全域'`／`'自動'`／`'0°'`／`'90°'`／`'180°'`／`'270°'` 不動除了「全域」（改用 `l10n.readerGlobalLabel`）與「自動」（改用 `l10n.readerSettingsOrientationAutoLabel`）**，tooltip 依表替換：

| 原 tooltip 字面值 | 新表達式 |
|---|---|
| `'使用全域預設'` | `l10n.readerUseGlobalDefaultTooltip`（Task 12 共用 key） |
| `'自動旋轉'` | `l10n.readerSettingsOrientationAutoTooltip` |
| `'鎖定 0°'` | `l10n.readerSettingsOrientationLock0Tooltip` |
| `'鎖定 90°'` | `l10n.readerSettingsOrientationLock90Tooltip` |
| `'鎖定 180°'` | `l10n.readerSettingsOrientationLock180Tooltip` |
| `'鎖定 270°'` | `l10n.readerSettingsOrientationLock270Tooltip` |

`'螢幕方向鎖定覆寫'`（Text 標題）→ `l10n.readerSettingsScreenOrientationLabel`。

`_buildLayoutPresetSection()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`：
- `label: const Text('將目前設定存為新預設集')` → `Text(l10n.readerSettingsSaveAsPresetButton)`
- `const Text('已儲存的預設集', ...)` → `Text(l10n.readerSettingsSavedPresetsLabel, ...)`
- `const Text('從其他書籍複製', ...)` → `Text(l10n.readerSettingsCopyFromBookLabel, ...)`
- `child: const Text('複製到本書')` → `Text(l10n.readerSettingsCopyToCurrentBookButton)`
- `child: const Text('複製到其他書籍')` → `Text(l10n.readerSettingsCopyToOtherBooksButton)`

`_buildResetToBookDefaultRow()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`：
- `title: '系統預設'` → `title: l10n.readerSettingsResetPresetTitle`
- `subtitle: '移除本書所有字級/字重/行距/段落間距/字距覆寫，改用書本原始樣式'` → `subtitle: l10n.readerSettingsResetPresetSubtitle`
- `child: const Text('套用')` → `Text(l10n.readerSettingsApplyButton)`

`_presetSummary()` 方法新增 `AppLocalizations l10n` 參數（純函式，非 State 方法呼叫端context已足夠但為求一致與可測試性改採參數注入）：
```dart
  String _presetSummary(BookReaderPrefs prefs, AppLocalizations l10n) {
    final fontSize = prefs.fontSize != null
        ? (prefs.fontSize! * 16).round().toString()
        : l10n.readerSettingsPresetDefaultValue;
    final lineHeight = prefs.lineHeight != null
        ? prefs.lineHeight!.toStringAsFixed(1)
        : l10n.readerSettingsPresetDefaultValue;
    final writingMode = switch (prefs.writingModeOverride) {
      WritingMode.vertical => l10n.readerSettingsWritingModeVerticalLabel,
      WritingMode.horizontal => l10n.readerSettingsWritingModeHorizontalLabel,
      null => l10n.readerSettingsPresetSummaryAutoLabel,
    };
    return l10n.readerSettingsPresetSummaryFormat(fontSize, lineHeight, writingMode);
  }
```

`_buildPresetSlot()` 開頭新增 `final l10n = AppLocalizations.of(context)!;`，呼叫 `_presetSummary(preset.prefs)` 改為 `_presetSummary(preset.prefs, l10n)`；`Text('（空）', ...)` → `Text(l10n.readerSettingsPresetEmptySlot, ...)`；`child: const Text('套用')` → `Text(l10n.readerSettingsApplyButton)`；`tooltip: '套用到其他書籍'` → `l10n.readerSettingsApplyToOtherBooksTooltip`；`tooltip: '刪除'` → `l10n.readerSettingsDeletePresetTooltip`。

- [x] **Step 4: 執行測試確認未觸及的測試檔仍通過（本 Task 不遷移測試，預期紅燈）**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: `Null check operator used on a null value`，留給 Task 17 修復。

- [x] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/reader_settings_sheet.dart`

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/lib/l10n/
git commit -m "feat(epic-45): reader_settings_sheet.dart 字串抽取第 2 部分（呈現分頁/預設集分頁）"
```

---

### Task 17: `reader_settings_sheet_test.dart` 測試遷移

**Files:**
- Test: `app/test/screens/reader_settings_sheet_test.dart`（8 處裸 `MaterialApp(`）

**Interfaces:**
- Consumes：Task 15／16 產出的 `ReaderSettingsSheet`（介面簽章未變動，僅內部文字改用 l10n）。

- [x] **Step 1: 遷移 8 處 `MaterialApp(` 呼叫**

比照 Task 13 Step 1 規則：優先修改共用 helper（若存在），否則逐一補上 `localizationsDelegates`/`supportedLocales`/`locale: const Locale('zh', 'TW')` 與頂部 `import 'package:elinkbook/l10n/app_localizations.dart';`。

- [x] **Step 2: 新增三語言渲染驗證測試**

新增 `testWidgets('英文介面下四個分頁籤標題與版面設定標題正確以英文渲染', ...)`，`locale: const Locale('en')`，斷言 `find.text('⚙️ Layout Settings')`／`find.text('Text')`／`find.text('Margins')`／`find.text('Display')`／`find.text('Presets')`。

- [x] **Step 3: 執行測試確認全數通過**

Run: `flutter test test/screens/reader_settings_sheet_test.dart`
Expected: 全數通過（既有＋新增 1 個）。

- [x] **Step 4: `grep` 驗證零殘留**

Run: `grep -c "MaterialApp(" test/screens/reader_settings_sheet_test.dart`，記錄實際數字（依 Step 1 是否採用共用 helper 而定，見 Task 13 Step 4 同等說明）。

- [x] **Step 5: `flutter analyze` 確認乾淨**

Run: `flutter analyze test/screens/reader_settings_sheet_test.dart`

- [x] **Step 6: Commit**

```bash
git add app/test/screens/reader_settings_sheet_test.dart
git commit -m "test(epic-45): reader_settings_sheet_test.dart 遷移至 pumpLocalizedWidget 相容寫法"
```

---

### Task 18: `reader_screen.dart`（production 第 1 部分：`bookTitle` nullable 化＋版面預設集對話框批次）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/lib/screens/reader_screen_route.dart`（確認呼叫端不受影響，見 Step 3 查證）
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`；`cancel`（Issue 2 共用 key）。
- Produces：ARB key `readerUnknownBookTitle`/`readerSaveAsPresetUnavailableMessage`/`readerSaveAsPresetFailedMessage`/`readerOverwritePresetPickerTitle`/`readerOverwritePresetOptionLabel`/`readerConfirmOverwriteTitle`/`readerOverwritePresetConfirmMessage`/`readerConfirmApplyTitle`/`readerApplyToOthersConfirmMessage`/`readerApplyPresetFailedMessage`/`readerConfirmDeleteTitle`/`readerDeletePresetConfirmMessage`/`readerDeletePresetFailedMessage`。`ReaderScreen.bookTitle` 欄位型別由 `final String bookTitle` 改為 `final String? bookTitle`（見下方「計劃範圍澄清」），供 Task 19 的 `_displayBookTitle` getter 消費。

**計劃範圍澄清（`bookTitle` 建構子預設值處理）**：`reader_screen.dart:140` 欄位宣告 `final String bookTitle;`、`reader_screen.dart:240` 建構子 `this.bookTitle = '未知書籍',`。因建構子預設值必須是編譯期常數，無法在此直接呼叫 `AppLocalizations.of(context)!`。已查證：全專案唯一正式生產呼叫端 `buildReaderScreen()`（`reader_screen_route.dart:34`）永遠明確傳入 `bookTitle: book.title`，這個預設值只有測試直接建構 `ReaderScreen(...)` 未帶 `bookTitle` 時才會命中（`reader_screen_test.dart:9594`）。本 Task 把欄位改為 `final String? bookTitle;`（建構子該參數移除預設值、允許 `null`），在 Task 19 的 `_displayBookTitle` getter（`build()` 執行期間才會被存取，非 `initState()`）內解析 `null` 為 `AppLocalizations.of(context)!.readerUnknownBookTitle`——完整實作見 Task 19，本 Task 只改欄位型別／建構子，`_displayBookTitle` getter 留給 Task 19 一併處理（避免同一段落被兩個 Task 重複touch）。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "readerUnknownBookTitle": "未知書籍",
  "@readerUnknownBookTitle": {
    "description": "ReaderScreen.bookTitle 未提供（僅測試直接建構時可能發生，正式生產路徑必定提供書名）時的回退顯示文字"
  },
  "readerSaveAsPresetUnavailableMessage": "暫時無法儲存預設集",
  "@readerSaveAsPresetUnavailableMessage": {
    "description": "layoutPresetRepository 未提供時，點擊「另存為新預設集」顯示的 SnackBar 訊息"
  },
  "readerSaveAsPresetFailedMessage": "另存為新預設集失敗：{error}",
  "@readerSaveAsPresetFailedMessage": {
    "description": "另存為新預設集過程發生例外時顯示的 SnackBar 訊息，{error} 為例外物件的字串表示",
    "placeholders": { "error": { "type": "String" } }
  },
  "readerOverwritePresetPickerTitle": "選擇要覆蓋的預設集",
  "@readerOverwritePresetPickerTitle": {
    "description": "已存滿 3 組預設集時，選擇要覆蓋哪一組的對話框標題"
  },
  "readerOverwritePresetOptionLabel": "{name}（最後更新：{date}）",
  "@readerOverwritePresetOptionLabel": {
    "description": "覆蓋預設集選單的單一選項文字，{name} 為預設集名稱，{date} 為已依 DateFormat.yMd() 格式化的最後更新日期字串",
    "placeholders": {
      "name": { "type": "String" },
      "date": { "type": "String" }
    }
  },
  "readerConfirmOverwriteTitle": "確認覆蓋",
  "@readerConfirmOverwriteTitle": {
    "description": "覆蓋預設集二次確認對話框標題與確認按鈕（兩處文字相同，共用一個 key）"
  },
  "readerOverwritePresetConfirmMessage": "即將覆蓋預設集「{name}」，此動作無法復原。",
  "@readerOverwritePresetConfirmMessage": {
    "description": "覆蓋預設集二次確認訊息，{name} 為預設集名稱",
    "placeholders": { "name": { "type": "String" } }
  },
  "readerConfirmApplyTitle": "確認套用",
  "@readerConfirmApplyTitle": {
    "description": "套用版面設定到其他書籍的確認對話框標題與確認按鈕（兩處文字相同，共用一個 key）"
  },
  "readerApplyToOthersConfirmMessage": "{count, plural, =1{即將覆蓋 1 本書的版面設定，此動作無法復原。} other{即將覆蓋 {count} 本書的版面設定，此動作無法復原。}}",
  "@readerApplyToOthersConfirmMessage": {
    "description": "套用版面設定到其他書籍的確認訊息，{count} 為目標書籍數",
    "placeholders": { "count": { "type": "int" } }
  },
  "readerApplyPresetFailedMessage": "套用版面設定失敗：{error}",
  "@readerApplyPresetFailedMessage": {
    "description": "套用版面設定（來自預設集或來自其他書籍）過程發生例外時顯示的 SnackBar 訊息，{error} 為例外物件的字串表示，兩處呼叫端共用",
    "placeholders": { "error": { "type": "String" } }
  },
  "readerConfirmDeleteTitle": "確認刪除",
  "@readerConfirmDeleteTitle": {
    "description": "刪除預設集確認對話框標題與確認按鈕（兩處文字相同，共用一個 key）"
  },
  "readerDeletePresetConfirmMessage": "即將刪除預設集「{name}」，此動作無法復原。",
  "@readerDeletePresetConfirmMessage": {
    "description": "刪除預設集確認訊息，{name} 為預設集名稱",
    "placeholders": { "name": { "type": "String" } }
  },
  "readerDeletePresetFailedMessage": "刪除預設集失敗：{error}",
  "@readerDeletePresetFailedMessage": {
    "description": "刪除預設集過程發生例外時顯示的 SnackBar 訊息，{error} 為例外物件的字串表示",
    "placeholders": { "error": { "type": "String" } }
  }
```

`app_zh_CN.arb`：
```json
  "readerUnknownBookTitle": "未知书籍",
  "readerSaveAsPresetUnavailableMessage": "暂时无法保存预设集",
  "readerSaveAsPresetFailedMessage": "另存为新预设集失败：{error}",
  "readerOverwritePresetPickerTitle": "选择要覆盖的预设集",
  "readerOverwritePresetOptionLabel": "{name}（最后更新：{date}）",
  "readerConfirmOverwriteTitle": "确认覆盖",
  "readerOverwritePresetConfirmMessage": "即将覆盖预设集“{name}”，此操作无法复原。",
  "readerConfirmApplyTitle": "确认套用",
  "readerApplyToOthersConfirmMessage": "{count, plural, =1{即将覆盖 1 本书的版面设定，此操作无法复原。} other{即将覆盖 {count} 本书的版面设定，此操作无法复原。}}",
  "readerApplyPresetFailedMessage": "套用版面设定失败：{error}",
  "readerConfirmDeleteTitle": "确认删除",
  "readerDeletePresetConfirmMessage": "即将删除预设集“{name}”，此操作无法复原。",
  "readerDeletePresetFailedMessage": "删除预设集失败：{error}"
```

`app_en.arb`：
```json
  "readerUnknownBookTitle": "Unknown Book",
  "readerSaveAsPresetUnavailableMessage": "Can't save preset right now",
  "readerSaveAsPresetFailedMessage": "Failed to save new preset: {error}",
  "readerOverwritePresetPickerTitle": "Choose a preset to overwrite",
  "readerOverwritePresetOptionLabel": "{name} (updated {date})",
  "readerConfirmOverwriteTitle": "Confirm Overwrite",
  "readerOverwritePresetConfirmMessage": "This will overwrite preset “{name}”. This can't be undone.",
  "readerConfirmApplyTitle": "Confirm Apply",
  "readerApplyToOthersConfirmMessage": "{count, plural, =1{This will overwrite the layout settings of 1 book. This can't be undone.} other{This will overwrite the layout settings of {count} books. This can't be undone.}}",
  "readerApplyPresetFailedMessage": "Failed to apply layout settings: {error}",
  "readerConfirmDeleteTitle": "Confirm Delete",
  "readerDeletePresetConfirmMessage": "This will delete preset “{name}”. This can't be undone.",
  "readerDeletePresetFailedMessage": "Failed to delete preset: {error}"
```

`app_zh.arb`：
```json
  "readerUnknownBookTitle": "未知書籍",
  "readerSaveAsPresetUnavailableMessage": "暫時無法儲存預設集",
  "readerSaveAsPresetFailedMessage": "另存為新預設集失敗：{error}",
  "readerOverwritePresetPickerTitle": "選擇要覆蓋的預設集",
  "readerOverwritePresetOptionLabel": "{name}（最後更新：{date}）",
  "readerConfirmOverwriteTitle": "確認覆蓋",
  "readerOverwritePresetConfirmMessage": "即將覆蓋預設集「{name}」，此動作無法復原。",
  "readerConfirmApplyTitle": "確認套用",
  "readerApplyToOthersConfirmMessage": "{count, plural, =1{即將覆蓋 1 本書的版面設定，此動作無法復原。} other{即將覆蓋 {count} 本書的版面設定，此動作無法復原。}}",
  "readerApplyPresetFailedMessage": "套用版面設定失敗：{error}",
  "readerConfirmDeleteTitle": "確認刪除",
  "readerDeletePresetConfirmMessage": "即將刪除預設集「{name}」，此動作無法復原。",
  "readerDeletePresetFailedMessage": "刪除預設集失敗：{error}"
```

- [ ] **Step 2: 執行 `flutter gen-l10n`**

- [ ] **Step 3: 查證 `reader_screen_route.dart` 不受影響**

Run: `grep -n "bookTitle" app/lib/screens/reader_screen_route.dart`
Expected: 僅一行 `bookTitle: book.title,`——`book.title`（`Book` model 欄位）本身是 `String`（非 nullable），賦值給改為 `String?` 的具名參數完全相容，無需修改此檔案。

- [ ] **Step 4: 修改 `reader_screen.dart` 欄位與建構子**

新增 import（若尚未存在）：`import 'package:intl/intl.dart';`（供 Step 5 的 `DateFormat.yMd()` 使用；`app_localizations.dart` import 已由更早的 Issue 0 引入，確認存在）。

第 140 行欄位宣告：
```dart
  final String? bookTitle;
```

第 240 行建構子參數：
```dart
    this.bookTitle,
```
（移除 `= '未知書籍'` 預設值。）

- [ ] **Step 5: 修改版面預設集對話框批次（`_handleSaveAsPreset`／`_selectPresetToOverwrite`／`_confirmOverwrite`／`_confirmApplyToOtherBooks`／`_applyPrefsToTargets`／`_handleApplyFromBook`／`_handleDeletePreset`／`_confirmDeletePreset`）**

依序替換（`debugPrint(...)` 內的中文診斷文字**不**屬於本 Epic 範圍，維持原樣不動，只替換 `SnackBar`／`AlertDialog` 內使用者可見的文字）：

`_handleSaveAsPreset()`：
```dart
  Future<void> _handleSaveAsPreset(BookReaderPrefs currentDraft) async {
    final l10n = AppLocalizations.of(context)!;
    final repository = widget.layoutPresetRepository;
    if (repository == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('reader_save_as_preset_repository_unavailable_snackbar'),
          content: Text(l10n.readerSaveAsPresetUnavailableMessage),
        ),
      );
      return;
    }
    try {
      final name = await showLayoutPresetNameDialog(context);
      if (name == null || !mounted) return;
      final filteredPrefs = currentDraft.reflowableEpubFields();
      List<LayoutPreset> updated;
      if (_layoutPresets.length < 3) {
        updated = await layout_preset_actions.insertNewLayoutPreset(
          repository,
          name: name,
          prefs: filteredPrefs,
        );
      } else {
        final target = await _selectPresetToOverwrite();
        if (target == null || !mounted) return;
        final confirmed = await _confirmOverwrite(target.name);
        if (!confirmed || !mounted) return;
        updated = await layout_preset_actions.overwriteLayoutPreset(
          repository,
          target: target,
          name: name,
          prefs: filteredPrefs,
        );
      }
      if (!mounted) return;
      setState(() => _layoutPresets = updated);
    } catch (e, stackTrace) {
      debugPrint('另存為新預設集失敗：$e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('reader_save_as_preset_error_snackbar'),
          content: Text(l10n.readerSaveAsPresetFailedMessage('$e')),
        ),
      );
    }
  }
```

`_selectPresetToOverwrite()`（日期格式化改用 `DateFormat.yMd()`）：
```dart
  Future<LayoutPreset?> _selectPresetToOverwrite() {
    final l10n = AppLocalizations.of(context)!;
    final dateFormat = DateFormat.yMd(Localizations.localeOf(context).toString());
    return showDialog<LayoutPreset>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.readerOverwritePresetPickerTitle),
        children: [
          ..._layoutPresets.map((preset) => SimpleDialogOption(
                key: Key('layout_preset_overwrite_option_${preset.id}'),
                onPressed: () => Navigator.of(dialogContext).pop(preset),
                child: Text(l10n.readerOverwritePresetOptionLabel(
                  preset.name,
                  dateFormat.format(preset.updatedAt),
                )),
              )),
          SimpleDialogOption(
            key: const Key('layout_preset_overwrite_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }
```

`_confirmOverwrite()`：
```dart
  Future<bool> _confirmOverwrite(String name) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.readerConfirmOverwriteTitle),
        content: Text(l10n.readerOverwritePresetConfirmMessage(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('layout_preset_overwrite_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.readerConfirmOverwriteTitle),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
```

`_confirmApplyToOtherBooks()`：
```dart
  Future<bool> _confirmApplyToOtherBooks(int count) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.readerConfirmApplyTitle),
        content: Text(l10n.readerApplyToOthersConfirmMessage(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('layout_preset_apply_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.readerConfirmApplyTitle),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
```

`_applyPrefsToTargets()`（僅 `catch` 分支的 `SnackBar` 內容需改）：
```dart
    } catch (e, stackTrace) {
      debugPrint('套用版面設定失敗：$e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('reader_apply_preset_error_snackbar'),
          content: Text(AppLocalizations.of(context)!.readerApplyPresetFailedMessage('$e')),
        ),
      );
    }
```

`_handleApplyFromBook()`（同樣僅 `catch` 分支）：
```dart
    } catch (e, stackTrace) {
      debugPrint('套用版面設定失敗：$e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('reader_apply_preset_error_snackbar'),
          content: Text(AppLocalizations.of(context)!.readerApplyPresetFailedMessage('$e')),
        ),
      );
    }
```

`_handleDeletePreset()`（僅 `catch` 分支）：
```dart
    } catch (e, stackTrace) {
      debugPrint('刪除預設集失敗：$e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('reader_delete_preset_error_snackbar'),
          content: Text(AppLocalizations.of(context)!.readerDeletePresetFailedMessage('$e')),
        ),
      );
    }
```

`_confirmDeletePreset()`：
```dart
  Future<bool> _confirmDeletePreset(String name) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.readerConfirmDeleteTitle),
        content: Text(l10n.readerDeletePresetConfirmMessage(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('layout_preset_delete_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.readerConfirmDeleteTitle),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
```

- [ ] **Step 6: 執行測試確認未觸及的測試檔仍通過（本 Task 不遷移測試，預期紅燈）**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: 因 `bookTitle` 型別變動與新增 l10n 呼叫，既有測試會出現大量失敗（缺少 `localizationsDelegates` 的 `Null check operator` 與型別不符）——此為預期中的紅燈，留給 Task 19 完成剩餘字串抽取、Task 20 完成測試遷移後才會轉綠。**本 Step 僅確認 `flutter analyze` 乾淨、編譯無誤**，不要求測試通過。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/reader_screen.dart`
Expected: No issues found!（`reader_screen_route.dart` 亦一併確認：`flutter analyze lib/screens/reader_screen_route.dart`）

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/lib/l10n/
git commit -m "feat(epic-45): reader_screen.dart 字串抽取第 1 部分（bookTitle nullable 化/版面預設集對話框）"
```

---

### Task 19: `reader_screen.dart`（production 第 2 部分：`_displayBookTitle` 安全解析＋其餘字串批次）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`；`readerUnknownBookTitle`（Task 18）；`readerAnnotationDeleteHighlightAndNote`/`readerAnnotationDeleteHighlight`/`readerAnnotationDeleteNote`/`readerAnnotationEditNoteTooltip`/`readerAnnotationAddNoteTooltip`（Task 6，重用）。
- Produces：ARB key `readerSearchUnavailableMessage`/`readerOpenBookTimeoutMessage`/`readerCopiedToClipboardMessage`/`readerTtsVoicePickerTitle`/`readerUnsupportedFormatMessage`/`readerFailedToLoadBookMessage`/`readerTtsSleepTimerOptionMinutes`/`readerTtsSleepTimerNoLimitLabel`。

**計劃範圍澄清**：`_TtsSleepTimerSheet.options` 由既有唯一呼叫端固定傳入 `[15, 30, 45, 60]` 分鐘（`Duration` 清單，不含 1 分鐘選項），故 `'${option.inMinutes} 分鐘'` 不需要 ICU plural（比照 Global Constraints 已聲明「本模組未發現需要 plural 的計數字串」的判斷，這是唯一一處計數字串，經確認不會遇到單數情境）。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb`：
```json
  "readerSearchUnavailableMessage": "搜尋功能暫時無法使用",
  "@readerSearchUnavailableMessage": {
    "description": "searchRepository／libraryRepository 未提供或書籍格式無法辨識時，點擊搜尋顯示的 SnackBar 訊息"
  },
  "readerOpenBookTimeoutMessage": "開書逾時，可能是系統 WebView 版本過舊或檔案異常",
  "@readerOpenBookTimeoutMessage": {
    "description": "開書逾時錯誤畫面顯示的訊息"
  },
  "readerCopiedToClipboardMessage": "已複製到剪貼簿",
  "@readerCopiedToClipboardMessage": {
    "description": "選字工具列「複製」按鈕點擊後的 SnackBar 提示"
  },
  "readerTtsVoicePickerTitle": "朗讀語音",
  "@readerTtsVoicePickerTitle": {
    "description": "TTS 選擇語音選單的標題列文字"
  },
  "readerUnsupportedFormatMessage": "不支援的檔案格式",
  "@readerUnsupportedFormatMessage": {
    "description": "書籍格式無法辨識（BookFormat.unknown）時的畫面中央提示文字"
  },
  "readerFailedToLoadBookMessage": "無法載入書籍",
  "@readerFailedToLoadBookMessage": {
    "description": "開書失敗且 _errorMessage 為 null 時的回退錯誤文字"
  },
  "readerTtsSleepTimerOptionMinutes": "{minutes} 分鐘",
  "@readerTtsSleepTimerOptionMinutes": {
    "description": "TTS 睡眠定時器選單的分鐘數選項文字，{minutes} 為分鐘數（固定選項 15/30/45/60，恆大於 1，不需要 ICU plural）",
    "placeholders": { "minutes": { "type": "int" } }
  },
  "readerTtsSleepTimerNoLimitLabel": "不限時",
  "@readerTtsSleepTimerNoLimitLabel": {
    "description": "TTS 睡眠定時器選單「不限時」選項文字"
  }
```

`app_zh_CN.arb`：
```json
  "readerSearchUnavailableMessage": "搜索功能暂时无法使用",
  "readerOpenBookTimeoutMessage": "开书逾时，可能是系统 WebView 版本过旧或文件异常",
  "readerCopiedToClipboardMessage": "已复制到剪贴板",
  "readerTtsVoicePickerTitle": "朗读语音",
  "readerUnsupportedFormatMessage": "不支持的文件格式",
  "readerFailedToLoadBookMessage": "无法载入书籍",
  "readerTtsSleepTimerOptionMinutes": "{minutes} 分钟",
  "readerTtsSleepTimerNoLimitLabel": "不限时"
```

`app_en.arb`：
```json
  "readerSearchUnavailableMessage": "Search is temporarily unavailable",
  "readerOpenBookTimeoutMessage": "Timed out opening the book. The system WebView may be outdated, or the file may be corrupted.",
  "readerCopiedToClipboardMessage": "Copied to clipboard",
  "readerTtsVoicePickerTitle": "Voice",
  "readerUnsupportedFormatMessage": "Unsupported file format",
  "readerFailedToLoadBookMessage": "Failed to load book",
  "readerTtsSleepTimerOptionMinutes": "{minutes} min",
  "readerTtsSleepTimerNoLimitLabel": "No limit"
```

`app_zh.arb`：
```json
  "readerSearchUnavailableMessage": "搜尋功能暫時無法使用",
  "readerOpenBookTimeoutMessage": "開書逾時，可能是系統 WebView 版本過舊或檔案異常",
  "readerCopiedToClipboardMessage": "已複製到剪貼簿",
  "readerTtsVoicePickerTitle": "朗讀語音",
  "readerUnsupportedFormatMessage": "不支援的檔案格式",
  "readerFailedToLoadBookMessage": "無法載入書籍",
  "readerTtsSleepTimerOptionMinutes": "{minutes} 分鐘",
  "readerTtsSleepTimerNoLimitLabel": "不限時"
```

- [ ] **Step 2: 執行 `flutter gen-l10n`**

- [ ] **Step 3: `_displayBookTitle` getter 安全解析 `null`**

```dart
  /// 依 [_textConversionMode] 轉換後的書名，供頁首／底部工具列／單書
  /// 搜尋標題等「單書情境」渲染點統一取用。[widget.bookTitle] 為 `null`
  /// 時（僅測試直接建構 `ReaderScreen` 未帶 `bookTitle` 才會發生，正式
  /// 生產路徑 `buildReaderScreen()` 恆傳入書名，見 Task 18 計劃範圍
  /// 澄清）回退為 `readerUnknownBookTitle` 在地化文字——此 getter 僅在
  /// `build()` 或使用者互動 callback 內被呼叫（非 `initState()`），
  /// 存取 `AppLocalizations.of(context)!` 安全。
  String get _displayBookTitle {
    final title = widget.bookTitle ??
        AppLocalizations.of(context)!.readerUnknownBookTitle;
    return convertText(title, _textConversionMode);
  }
```

- [ ] **Step 4: 其餘字串批次替換**

`_openBookSearch()`：`content: Text('搜尋功能暫時無法使用')` → `content: Text(AppLocalizations.of(context)!.readerSearchUnavailableMessage)`。

`_handleOpenBookTimeout()`：`_errorMessage = '開書逾時，可能是系統 WebView 版本過舊或檔案異常';` → `_errorMessage = AppLocalizations.of(context)!.readerOpenBookTimeoutMessage;`。

`_handleCopySelection()`：`content: Text('已複製到剪貼簿')` → `content: Text(AppLocalizations.of(context)!.readerCopiedToClipboardMessage)`。

`_annotationDeleteButtonLabel()`：
```dart
  String _annotationDeleteButtonLabel(AnnotationListItem item) {
    final l10n = AppLocalizations.of(context)!;
    final hasHighlight = item.highlight != null;
    final hasNote = item.note != null;
    if (hasHighlight && hasNote) return l10n.readerAnnotationDeleteHighlightAndNote;
    if (hasHighlight) return l10n.readerAnnotationDeleteHighlight;
    return l10n.readerAnnotationDeleteNote;
  }
```
（重用 Task 6 已建立的 3 個 key。）

`_handleNotePressed()`／`_handlePdfNotePressed()`（各自的 `showNoteTextDialog` 呼叫，`title:` 參數）：
```dart
    final l10n = AppLocalizations.of(context)!;
    final text = await showNoteTextDialog(
      context,
      initialText: existing?.text ?? '',
      title: existing != null ? l10n.readerAnnotationEditNoteTooltip : l10n.readerAnnotationAddNoteTooltip,
    );
```
（兩處呼叫端皆比照此改法，重用 Task 6 的 `readerAnnotationEditNoteTooltip`／`readerAnnotationAddNoteTooltip`；`l10n` 區域變數若該方法內已有其他地方宣告需避免重複宣告，若無則在 `showNoteTextDialog` 呼叫前新增這一行。）

TTS 語音選單（`_openVoicePicker` 或等效方法內，`'朗讀語音'` 標題）：
```dart
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    AppLocalizations.of(context)!.readerTtsVoicePickerTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
```
（原 `const Padding(...)` 因子項不再是常數，移除該層 `const`。）

`_buildBody()`：
```dart
  Widget _buildBody(BookFormat format, bool isLandscape) {
    final l10n = AppLocalizations.of(context)!;
    if (format == BookFormat.unknown) {
      return Stack(
        children: [
          Center(child: Text(l10n.readerUnsupportedFormatMessage)),
          if (!_cropEditModeActive) _buildChromeTopBar(format),
        ],
      );
    }
    if (_state == _RenderState.error) {
      return Stack(
        children: [
          Center(
            child: Text(
              _errorMessage ?? l10n.readerFailedToLoadBookMessage,
              key: const Key('reader_error_text'),
            ),
          ),
          if (!_cropEditModeActive) _buildChromeTopBar(format),
        ],
      );
    }
    // ...（其餘 _buildBody 內容原樣不動）
```

`_TtsSleepTimerSheet.build()`（獨立 `StatelessWidget`，自身 `context` 可安全使用）：
```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final primaryColor = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            ListTile(
              key: Key('reader_tts_sleep_timer_option_${option.inMinutes}'),
              title: Text(l10n.readerTtsSleepTimerOptionMinutes(option.inMinutes)),
              trailing:
                  selected == option ? Icon(Icons.check, color: primaryColor) : null,
              onTap: () => onSelected(option),
            ),
          ListTile(
            key: const Key('reader_tts_sleep_timer_option_none'),
            title: Text(l10n.readerTtsSleepTimerNoLimitLabel),
            trailing: selected == null ? Icon(Icons.check, color: primaryColor) : null,
            onTap: () => onSelected(null),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 5: 確認 `_buildSearchableBook()` 的 Sentinel 字面值零異動**

Run: `grep -n "groupName: BookGroup.uncategorized" lib/screens/reader_screen.dart`
Expected: 恰好 1 處命中（`_buildSearchableBook()` 內），維持原樣未被本 Task 或 Task 18 誤觸。

- [ ] **Step 6: 執行測試確認未觸及的測試檔仍通過（本 Task 不遷移測試，預期紅燈）**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: 生產程式碼字串抽取已全數完成，但測試檔尚未遷移，預期仍是紅燈（`Null check operator used on a null value`），留給 Task 20 修復。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `flutter analyze lib/screens/reader_screen.dart`
Expected: No issues found!

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/lib/l10n/
git commit -m "feat(epic-45): reader_screen.dart 字串抽取第 2 部分（_displayBookTitle 安全解析/其餘字串批次，生產程式碼全數完成）"
```

---

### Task 20: `reader_screen_test.dart` 測試遷移（227 處裸 `MaterialApp(`，全計畫規模最大單一步驟）

**Files:**
- Test: `app/test/screens/reader_screen_test.dart`（10537 行，227 處裸 `MaterialApp(`）

**Interfaces:**
- Consumes：Task 18／19 完成的 `ReaderScreen`（`bookTitle` 改為 `String?`，其餘公開建構參數簽章不變）。

**盤點結果（已實際 grep／抽樣核實，見下方各模式的驗證指令）**：227 處依「`MaterialApp(` 之後緊接的下一行」分類，共 7 種模式：

| 模式 | 出現次數 | 特徵 |
|---|---|---|
| A | 202 | `theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),` 緊接 `home: ReaderScreen(...)` |
| B | 12 | `theme: buildThemeData(AppTheme.dark)` 或 `buildThemeData(AppTheme.light)` 緊接 `home: ReaderScreen(...)` |
| C | 5 | `home: Builder(builder: (context) => Scaffold(body: ... ElevatedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(...))))))`（模擬「從書架點擊書籍進入閱讀器」的導覽情境） |
| D | 5 | `const MaterialApp(home: SizedBox.shrink())`（測試階段之間的狀態重置佔位，不渲染任何 `ReaderScreen`／l10n 相關 widget） |
| E | 1 | `theme: resolveThemeData(theme: AppTheme.light, isEinkMode: true),` 緊接 `home: ReaderScreen(...)`（唯一一處 E-Ink 模式測試） |
| F | 1 | `home: PdfReaderView(...)`（直接測試 `PdfReaderView` 本身，不經過 `ReaderScreen`，不含任何 `AppLocalizations` 呼叫） |
| G | 1 | `home: MediaQuery(data: const MediaQueryData(...), child: ReaderScreen(...))` |

- [ ] **Step 1: 驗證模式分布與本計畫記錄一致**

Run（在 `app/` 目錄下）：
```bash
grep -c "MaterialApp(" test/screens/reader_screen_test.dart
grep -c "theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false)," test/screens/reader_screen_test.dart
grep -c "theme: buildThemeData(" test/screens/reader_screen_test.dart
grep -c "home: Builder(" test/screens/reader_screen_test.dart
grep -c "home: SizedBox.shrink())" test/screens/reader_screen_test.dart
grep -c "isEinkMode: true)," test/screens/reader_screen_test.dart
grep -c "home: PdfReaderView(" test/screens/reader_screen_test.dart
grep -c "home: MediaQuery(" test/screens/reader_screen_test.dart
```
Expected：227／202／12／5／5／1／1／1（若實際數字與此有出入，以實際 grep 結果為準重新分類，不強行套用本表；下列 Step 2-6 的轉換規則對任何微小數字落差皆穩健適用，只要每一類別涵蓋的實際寫法符合下方特徵描述）。

- [ ] **Step 2: 檔案頂部新增 import**

```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```
（加在既有 `package:elinkbook/...` import 區塊。）

- [ ] **Step 3: 轉換規則 A／B／E（合計 215 處，緊接 `home: ReaderScreen(...)` 的所有變體）**

不論 `theme:` 是 `resolveThemeData(theme: AppTheme.light, isEinkMode: false/true)` 或 `buildThemeData(AppTheme.dark/light)`，在同一個 `MaterialApp(` 呼叫的參數列新增以下三行（緊接 `theme:` 之前或之後皆可，建議緊接 `MaterialApp(` 之後、`theme:` 之前，維持全檔案風格一致）：
```dart
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
```

實際範例（模式 A，`reader_screen_test.dart:191-194`，修改前後）：
```dart
// 修改前
await tester.pumpWidget(
  MaterialApp(
    theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
    home: ReaderScreen(
      filePath: 'test/fixtures/sample_multi_page.pdf',
      ...

// 修改後
await tester.pumpWidget(
  MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
    home: ReaderScreen(
      filePath: 'test/fixtures/sample_multi_page.pdf',
      ...
```

實際範例（模式 B，`reader_screen_test.dart:5489-5492`）：
```dart
// 修改前
await tester.pumpWidget(
  MaterialApp(
    theme: buildThemeData(AppTheme.dark),
    home: ReaderScreen(
      ...

// 修改後
await tester.pumpWidget(
  MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildThemeData(AppTheme.dark),
    home: ReaderScreen(
      ...
```

模式 E（`reader_screen_test.dart:6708` 附近，`isEinkMode: true`）套用完全相同規則，只是 `theme:` 那一行本身的 `isEinkMode` 引數維持 `true` 不動。

這是全 Task 工作量最大的部分（215 處機械式插入），逐一在每個符合「`MaterialApp(` 後緊接 `theme:`」特徵的位置插入上述三行，**不變動任何既有 `home: ReaderScreen(...)` 建構參數或其後的斷言內容**。

- [ ] **Step 4: 轉換規則 C（5 處 `home: Builder(...)` 導覽情境）**

實際範例（`reader_screen_test.dart:3444-3455`，修改前後）：
```dart
// 修改前
await tester.pumpWidget(
  MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('open_reader'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReaderScreen(
                  filePath: 'test/fixtures/sample.pdf',
                  ...

// 修改後
await tester.pumpWidget(
  MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('open_reader'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReaderScreen(
                  filePath: 'test/fixtures/sample.pdf',
                  ...
```

`MaterialPageRoute` 推入的 `ReaderScreen` 沿用外層 `MaterialApp` 的 `Navigator`，其 `localizationsDelegates` 一併生效，不需要在 `MaterialPageRoute` 內額外處理。

- [ ] **Step 5: 轉換規則 D／F（6 處不含 `ReaderScreen` 或任何 l10n 消費者，維持不動）**

模式 D（5 處 `const MaterialApp(home: SizedBox.shrink())`）與模式 F（1 處 `home: PdfReaderView(...)`，直接測試 `PdfReaderView` 本身、不經過 `ReaderScreen`，`pdf_reader_view.dart` 不在本 Issue 範圍、未消費任何 `AppLocalizations`）**皆不需要修改**——這兩種寫法渲染的 widget 樹完全不含任何會呼叫 `AppLocalizations.of(context)!` 的元件，加上 `localizationsDelegates` 對它們而言是多餘的防禦性寫法。執行 Step 1 的 grep 指令確認這 6 處的行號後，逐一核對其 widget 樹內容符合「不含 `ReaderScreen`」的描述，若核對後發現其中有任何一處其實間接建構了本 Issue 已在地化的元件，改套用 Step 3 規則處理。

- [ ] **Step 6: 轉換規則 G（1 處 `home: MediaQuery(...)`）**

`reader_screen_test.dart:5375-5384` 附近：
```dart
// 修改前
await tester.pumpWidget(
  MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(
        viewPadding: EdgeInsets.only(bottom: 48),
      ),
      child: ReaderScreen(
        filePath: 'test/fixtures/sample.epub',
        ...

// 修改後
await tester.pumpWidget(
  MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: const MediaQueryData(
        viewPadding: EdgeInsets.only(bottom: 48),
      ),
      child: ReaderScreen(
        filePath: 'test/fixtures/sample.epub',
        ...
```

- [ ] **Step 7: 修正 `bookTitle` 預設值相關斷言（`reader_screen_test.dart:9594` 附近）**

該測試建構 `ReaderScreen(...)` 時未傳 `bookTitle`（命中 Task 18 的 nullable 預設值），斷言 `expect(ttsAudioHandler.mediaItem.value?.title, '未知書籍');`。因該測試所在的 `MaterialApp(` 已依 Step 3 規則補上 `locale: const Locale('zh', 'TW')`，`AppLocalizations.of(context)!.readerUnknownBookTitle` 在 `zh_TW` 下的值就是 `'未知書籍'`（Task 18 ARB 定義），**斷言字面值不需要修改**，只需確認該測試所在的 `MaterialApp(` 確實已套用 Step 3 規則（即補上 `locale: const Locale('zh', 'TW')`），執行 Step 9 測試時這一則會是驗證此行為的迴歸測試。

- [ ] **Step 8: 新增三語言渲染驗證測試**

在檔案 `main()` 最後新增 4 個測試（沿用檔案既有的 `ReaderScreen` 建構模式，找一個已存在、建構參數最精簡的 `testWidgets` 作為範本複製調整 `locale`）：

```dart
  testWidgets('英文介面下 bookTitle 為 null 時回退顯示 Unknown Book',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_en_unknown_title',
          prefsManager: FakeReaderPrefsManager(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unknown Book'), findsWidgets);
  });

  testWidgets('簡體中文介面下版面設定 Bottom Sheet 標題正確以簡體渲染',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_zh_cn_settings',
          bookTitle: '書名',
          prefsManager: FakeReaderPrefsManager(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 開啟版面設定 Bottom Sheet（比照既有測試找到對應按鈕的方式，
    // 例如 find.byKey(const Key('reader_chrome_layout_button')) 或
    // 等效鍵盤操作，依檔案既有慣例調整）。

    expect(find.text('⚙️ 版面设定'), findsOneWidget);
  });

  testWidgets('英文介面下目錄 Bottom Sheet 標題正確以英文渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_en_toc',
          bookTitle: 'Title',
          prefsManager: FakeReaderPrefsManager(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 開啟目錄 Bottom Sheet（比照既有測試找到 toc 按鈕的方式）。

    expect(find.text('📖 Table of Contents'), findsOneWidget);
  });

  testWidgets('英文介面下不支援格式提示正確以英文渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.unknown',
          bookId: 'b_en_unsupported',
          prefsManager: FakeReaderPrefsManager(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unsupported file format'), findsOneWidget);
  });
```

> 上述 4 則測試中「開啟版面設定／目錄 Bottom Sheet」的實際互動步驟（點擊哪個 `Key`）請對照檔案內既有 `testWidgets`（例如既有的「開啟版面設定」「開啟目錄」測試）採用相同手法，本計畫不重複列出已存在於檔案中的既有互動序列。

- [ ] **Step 9: 執行測試確認全數通過**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: 全數通過（既有全部＋新增 4 個）。若有個別既存測試因本次型別/l10n 變動而失敗，逐一排查是否為斷言依賴了未同步更新的中文字面值（理論上不應發生，因預設 `zh_TW` 讓既有中文斷言不受影響）。

- [ ] **Step 10: `grep` 驗證零殘留**

Run: `grep -c "MaterialApp(" test/screens/reader_screen_test.dart`
Expected: 仍為 227（本 Task 是「補參數」而非「移除／替換 `MaterialApp(`」，數量不變；驗證方式改為確認 `grep -c "localizationsDelegates: AppLocalizations.localizationsDelegates" test/screens/reader_screen_test.dart` 至少為 221〔215 處規則 A/B/E＋5 處規則 C＋1 處規則 G，模式 D／F 的 6 處刻意不補——這 6 處是刻意排除的純佔位與非 l10n 測試〔見上方模式 D／F 定義：`const MaterialApp(home: SizedBox.shrink())` 與直接測試 `PdfReaderView` 本身的案例，皆不含任何會呼叫 `AppLocalizations.of(context)!` 的元件〕，不是漏遷移，後續維護者比對這個數字時不需要補上這 6 處〕）。

- [ ] **Step 11: `flutter analyze` 確認乾淨**

Run: `flutter analyze test/screens/reader_screen_test.dart`
Expected: No issues found!

- [ ] **Step 12: Commit**

```bash
git add app/test/screens/reader_screen_test.dart
git commit -m "test(epic-45): reader_screen_test.dart 227 處測試遷移至在地化相容寫法＋新增三語言渲染驗證"
```

---

### Task 21: 完整驗收與進度文件更新

**Files:**
- Modify: `docs/epics/epic-45-interface-i18n/issues.md`
- Modify: `docs/epics/epic-45-interface-i18n/epic.md`
- Modify: `docs/epics.md`

- [ ] **Step 1: 完整 `flutter analyze`**

Run（在 `app/` 目錄下）：
```bash
flutter analyze
```
Expected: No issues found!

- [ ] **Step 2: 完整 `flutter test`**

Run:
```bash
flutter test
```
Expected: 全數通過，與本 Issue 認領前的 base commit 相比零新增失敗（若有既存不穩定測試，需與 base commit 重跑比對，證實非本 Issue 引入，比照 Issue 0／3 既有先例的查證方式）。

- [ ] **Step 3: 確認 `_buildSearchableBook()` Sentinel 字面值最終零異動**

Run: `git diff main -- lib/screens/reader_screen.dart | grep -A2 -B2 "BookGroup.uncategorized"`
Expected: 該行未出現在 diff 中（或出現但確認只是上下文行、實際內容未變）。

- [ ] **Step 4: 確認範圍修正已同步記錄**

在 `docs/epics/epic-45-interface-i18n/issues.md`「Issue 4」段落：
1. `**Status:** ready-for-agent` 改為 `**Status:** completed`。
2. 在「What to build」段落後新增「**實際執行範圍修正記錄（認領時 grep 盤點）**」段落，內容比照 Issue 3 先例，記錄：移出 `toc_bottom_sheet_pdf.dart`（不存在）、`reader_footer.dart`（零硬編碼字串）、`widgets/eb_option_chip_group.dart`／`widgets/eb_section_header.dart`／`widgets/eb_stepper.dart`／`widgets/eb_field_card.dart`／`widgets/reader_option_tile.dart`（零硬編碼字串）、`widgets/text_conversion_icon.dart`（4 處命中是簡/繁字元示意圖示本身要呈現的文字，非待翻譯 UI 文案，不修改）。

- [ ] **Step 5: 更新 `epic.md`**

在「開發記錄」段落末尾新增一則，比照既有格式，記錄：Task 1-21 完成概況、`reader_screen.dart`／`reader_screen_test.dart` 的規模與處理方式（bookTitle nullable 化、227 處測試遷移採用轉換規則而非逐一列舉）、跨三個版面設定 Bottom Sheet（`fxl_settings_sheet.dart`／`pdf_settings_sheet.dart`／`reader_settings_sheet.dart`）共用 10 個 ARB key 的 DRY 設計、`flutter analyze`／`flutter test` 最終結果。

- [ ] **Step 6: 更新 `docs/epics.md`**

`epic-45-interface-i18n` 該列備註欄位改為「Issue 0／1／2／3／4 已完成，待認領 Issue 5-6」。

- [ ] **Step 7: Commit**

```bash
git add app/ docs/epics/epic-45-interface-i18n/issues.md docs/epics/epic-45-interface-i18n/epic.md docs/epics.md
git commit -m "docs(epic-45): 標記 Issue 4 為 completed，記錄實際執行範圍修正並更新 epic.md/epics.md"
```

---

## Self-Review

**1. Spec 覆蓋度**：對照 `issues.md` Issue 4 段落逐項檢查——
- 「What to build」列出的 16 個候選檔案（扣除已排除的 6 個：`toc_bottom_sheet_pdf.dart` 不存在、`reader_footer.dart` 零字串、`eb_sheet_shell.dart`／`full_text_search_confirm_dialog.dart` 已在他 Issue 處理、`eb_option_chip_group.dart`／`eb_section_header.dart`／`eb_stepper.dart`／`eb_field_card.dart`／`reader_option_tile.dart` 零字串）皆有對應 Task：`reader_screen.dart`（Task 18／19）、`reader_chrome_top_bar.dart`（Task 1）、`reader_chrome_bottom_bar.dart`（Task 2）、`toc_bottom_sheet.dart`（Task 9）、`notes_bottom_sheet.dart`（Task 11）、`note_edit_dialog.dart`（Task 5）、`annotation_toolbar.dart`（Task 6）、`tts_panel.dart`（Task 10）、`pdf_search_panel.dart`（Task 7）、`pdf_settings_sheet.dart`（Task 14）、`fxl_settings_sheet.dart`（Task 12／13）、`reader_settings_sheet.dart`（Task 15／16／17）、`pdf_thumbnail_panel.dart`（Task 4）、`paging_bar.dart`（Task 3）、`reading_position_conflict_dialog.dart`（Task 8）、`text_conversion_icon.dart`（確認排除，記錄於 Architecture 段落）。
- 「不可變性警示」（`_buildSearchableBook()` 的 Sentinel 字面值）在 Global Constraints 明訂，Task 18／19／21 皆有對應查證步驟。
- `reader_screen_test.dart`（Task 20）涵蓋全部 227 處裸 `MaterialApp`。
- 無遺漏的 spec 需求。

**2. Placeholder 掃描**：全計畫搜尋「TBD」／「TODO」／「待補」／「同 Task N」等紅旗字樣，僅出現在 Task 4 Step 5／Task 9 Step 5 等處以「沿用既有寫法」描述測試細節、Task 20 Step 8 註明「開啟 Bottom Sheet 的互動步驟依既有測試慣例」——這些皆非「跳過不寫」的 placeholder，而是明確指向「檔案中已存在、可直接查閱複製」的既有具體寫法，比照 `plan-issue-3.md` Task 3 Step 5 的既有先例（同樣以「若既有寫法不完全一致，以檔案中其他測試為準」收尾），不構成計畫失敗。所有 ARB key 皆有完整四語言真實文字，所有程式碼 Step 皆為可直接套用的具體 diff 或完整方法。

**3. 型別一致性**：
- `ReaderScreen.bookTitle`：Task 18 改為 `String?`，Task 19 的 `_displayBookTitle` getter 消費型別與此一致；`reader_screen_route.dart` 呼叫端傳入非 nullable `String`（`book.title`），與具名參數新型別 `String?` 相容，已於 Task 18 Step 3 查證。
- `_confirmDeleteAll()`（`notes_bottom_sheet.dart`，Task 11）簽章由 `{itemLabel, count}` 改為 `{title}`，兩處呼叫端（`_confirmDeleteAllHighlights()`／`_confirmDeleteAllNotes()`）皆已同步更新為傳入已解析完成的 `title` 字串。
- `_presetSummary()`（`reader_settings_sheet.dart`，Task 16）新增 `AppLocalizations l10n` 參數，唯一呼叫端 `_buildPresetSlot()` 已同步更新呼叫方式。
- `_describeReadingPosition()`（`reading_position_conflict_dialog.dart`，Task 8）新增 `AppLocalizations l10n` 參數，唯一呼叫端已同步更新。
- 跨檔案共用 ARB key（Task 12 建立、Task 14／15／16 消費）的 key 名稱與參數型別（`String`／無 placeholder）在各 Task 內一致引用，無拼字或型別落差。

**4. 架構偏離記錄**：
- `_confirmDeleteAll()` 從「`itemLabel` 詞彙插槽」改為「呼叫端傳入完整已解析標題」——Task 11 已記錄為「架構必要偏離」，理由是原始模式在英文語序下無法正確運作。
- `bookTitle` 從「編譯期常數預設值」改為「nullable＋執行期於 `_displayBookTitle` 解析」——Task 18／19 已詳細記錄查證依據與安全性論證（僅 `build()`／使用者互動 callback 存取，非 `initState()`）。
- 三個版面設定 Bottom Sheet 共用 10 個 ARB key（`readerDualPageAutoTooltip` 等）——Task 12 已記錄哪些 key 供哪些後續 Task 重用，避免 Task 14／15／16 重複定義相同字串產生不一致翻譯。

無發現需要在計畫定案前修正的缺口。
