# Epic 45 Issue 9 — 收斂清理：其餘邊角測試檔遷移至 `pumpLocalizedWidget()` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `app/test/` 內不再有裸 `MaterialApp(...)`（缺少 `localizationsDelegates`/`supportedLocales`）的既有測試檔，收斂 Issue 3-6 未觸及的殘餘邊角測試檔，並補上一份代表性畫面的跨語言渲染驗證測試。

**Architecture:** 本 Issue 是純測試基礎設施收斂工作，**不修改任何 production 程式碼、不新增任何 ARB key**。逐檔為裸 `MaterialApp(...)` 呼叫補上 `locale`/`localizationsDelegates`/`supportedLocales` 三個參數（比照 `plan-issue-5.md` 對「無共用 helper」測試檔的既定做法：直接在每個 `MaterialApp(` 呼叫點插入三行參數，不改用 `pumpLocalizedWidget()` 包裝——因為本 Issue 觸及的檔案多半以本地 helper 函式或多種不同建構模式包裝 `MaterialApp`，逐一改寫成 `pumpLocalizedWidget(tester, home)` 簽章反而增加不必要的結構性風險，直接補參數是風險最低的機械式轉換），不改變任何既有斷言邏輯。額外新增 `app/test/l10n/locale_switch_test.dart`（`spec.md` §8 定案項目），針對 `SettingsScaffold`／`LibraryScreen` 兩個代表性畫面驗證 `zh_CN`/`en` locale 下關鍵字串正確渲染。

**Tech Stack:** Flutter widget test（`flutter_test`）、`AppLocalizations`（`flutter gen-l10n` 產生）。

**Spec:** `docs/epics/epic-45-interface-i18n/spec.md` §8（測試套件相容性契約）

## Global Constraints

- **範圍盤點方法與結果，含 `review-plan-issue-9.md` I-1 修正**：最初以 `grep -rl "MaterialApp(" app/test` 取檔案清單、再與 `grep -rl "localizationsDelegates\|pumpLocalizedWidget" app/test` 取差集的「檔案級」盤點法，經審查指出存在**遮蔽漏洞**——只要檔案內任一處出現過 `localizationsDelegates`／`pumpLocalizedWidget` 字樣（即使只是該檔其他測試由先前 Issue 局部遷移過），整份檔案就會被視為「已完成」而從差集中被抹除，即便檔案內其餘裸 `MaterialApp(` 呼叫點完全未遷移。逐一核對後確認漏列 **4 個檔案、29 處**呼叫點：`test/reader/pdf_reader_view_test.dart`（7 處，行 23/99/179/202/235/270/307；該檔行 49/75/134 已由 Issue 7 局部遷移為 `pumpLocalizedWidget`，導致整檔被誤判已完成）、`test/reader/foliate_reader_view_test.dart`（15 處，行 766/809/839/878/927/961/988/1012/1043/1079/1106/1138/1169/1914/1925；該檔行 1940/1970/1995 已由 Issue 7 局部遷移，同樣誤判）、`test/screens/reader_screen_test.dart`（6 處，行 404/457/2129/2157/10682 為 `const MaterialApp(home: SizedBox.shrink())` dispose 觸發容器、行 3605 為 `MaterialApp(home: PdfReaderView(...))`；Issue 4 遷移 220+ 處時遺漏這 6 處）、`test/screens/widgets/eb_sheet_shell_test.dart`（1 處，行 26 `_pumpAndOpen()` helper；該檔行 52 已使用 `pumpLocalizedWidget`，導致整檔被誤判已完成）。修訂後的完整清單（依 `MaterialApp(` 出現次數標註）：
  - `test/screens/widgets/text_conversion_icon_test.dart`（4）
  - `test/screens/widgets/eb_option_chip_group_test.dart`（4）
  - `test/screens/widgets/eb_stepper_test.dart`（1）
  - `test/screens/widgets/eb_section_header_test.dart`（2）
  - `test/screens/widgets/eb_sheet_shell_test.dart`（1，`_pumpAndOpen()` helper；另有 1 處 fallback 測試刻意不遷移，見下方白名單說明）
  - `test/screens/widgets/reader_option_tile_test.dart`（4）
  - `test/library/widgets/book_cover_test.dart`（5）
  - `test/library/widgets/cover_placeholder_test.dart`（1）
  - `test/screens/reader_footer_test.dart`（10）
  - `test/reader/tap_zone_detector_test.dart`（2）
  - `test/reader/bounce_tolerant_long_press_detector_test.dart`（1）
  - `test/reader/pdf_crop_frame_overlay_test.dart`（2）
  - `test/support/pump_until_pdf_ready_test.dart`（3）
  - `test/theme/app_theme_data_test.dart`（1）
  - `test/reader/pdf_reader_view_jump_highlight_test.dart`（3）
  - `test/reader/pdf_reader_view_nav_zone_test.dart`（8）
  - `test/reader/pdf_reader_view_toc_test.dart`（2）
  - `test/reader/pdf_reader_view_thumbnail_test.dart`（3）
  - `test/reader/pdf_reader_view_search_test.dart`（7）
  - `test/reader/pdf_reader_view_selection_test.dart`（20）
  - `test/reader/pdf_reader_view_filters_test.dart`（20）
  - `test/reader/pdf_reader_view_dual_page_test.dart`（16）
  - `test/reader/pdf_reader_view_test.dart`（7）
  - `test/reader/foliate_reader_view_test.dart`（15）
  - `test/screens/reader_screen_test.dart`（6）

  合計 **25 個檔案、148 處** `MaterialApp(` 呼叫需要遷移。`issues.md` 原文提及的 `app/test/l10n/locale_switch_test.dart` 經查證**尚不存在**（`app/test/l10n/` 目前只有 `app_locale_preferences_test.dart`／`app_locale_test.dart`／`app_localizations_generated_test.dart`／`elinkbook_app_locale_test.dart` 四個檔案），本 Issue 需全新建立（見 Task 14），非「補完」既有檔案。
- **白名單例外（`review-plan-issue-9.md` I-3 修正）**：`test/screens/widgets/eb_sheet_shell_test.dart:82-105`「AppLocalizations 不存在（裸 MaterialApp）時，tooltip 回退既有中文字面值」這個測試的存在目的就是驗證上層 widget 樹**未配置** `localizationsDelegates` 時 `EBSheetShell` 能安全降級為預設中文字串 `'關閉'`，不因 `AppLocalizations.of(context)!` 拋出 null check 例外——這是刻意保留的裸 `MaterialApp`，**嚴禁**在本 Issue 任何 Task 中修改或注入 delegates，否則會直接摧毀這個測試唯一的驗證語意。Task 1（見下）與 Task 15 的驗收腳本皆須明確排除此處。
- **統一遷移模式**：在每個 `MaterialApp(` 呼叫的參數列第一行插入：
  ```dart
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
  ```
  原本用 `const MaterialApp(...)` 宣告的呼叫點，因新增非常數運算式（`AppLocalizations.localizationsDelegates` 等）必須移除外層 `const`（`plan-issue-5.md` 既定作法）；這類呼叫點的內層子樹（例如 `Scaffold(...)`）原始程式碼本身**沒有**顯式寫 `const`，只是透過外層 `const MaterialApp(...)` 的常數語境（constant context）被隱性視為常數——外層 `const` 移除後該常數語境隨之消失，若要維持原本的效能優化，須在內層**顯式補上** `const`（例如改寫為 `home: const Scaffold(...)`），而非「維持不變動」（`review-plan-issue-9.md` M-1 修正：此為單純敘述用詞澄清，各 Task 內的實際範例程式碼原本就已正確寫出 `const Scaffold(...)`，不涉及程式碼修改）。
- 每個檔案異動前先用 `grep -c "MaterialApp(" <file>` 確認實際出現次數是否與上方盤點結果一致（認領到執行之間可能有既有測試檔案被其他工作異動過），異動後用同一指令確認次數不變（代表沒有誤刪或誤合併任何呼叫點；`eb_sheet_shell_test.dart` 例外，該檔異動後次數應維持 2 不變——1 處補參數＋1 處刻意保留的 fallback）。
- 每個檔案頂部新增 `import 'package:elinkbook/l10n/app_localizations.dart';`（若既有 import 區塊已有其他 `package:elinkbook/...` import，插入在同一群組內、依字母序鄰近位置即可，不強制精確排序）。
- **不改變任何既有斷言內容**——本 Issue 純粹是幫裸 `MaterialApp(...)` 補上在地化基礎設施參數，不新增任何 `zh_CN`/`en` 渲染驗證測試（這點與 Issue 3-6「逐檔字串抽取」不同，那些 Issue 因為改動了 production 字串來源才需要新增跨語言驗證；本 Issue 沒有觸碰任何 production 檔案，25 個檔案中多數底層 widget 本身甚至不消費 `AppLocalizations`，強行新增跨語言驗證測試沒有實質驗證對象）。唯一的跨語言驗證新增在獨立的 Task 14（`locale_switch_test.dart`），針對兩個「確實會消費 `AppLocalizations`」的代表性整合畫面。
- 測試執行範圍：每個 Task 完成後只跑該 Task 觸及的測試檔；完整 `flutter test`／`flutter analyze` 僅在最後一個 Task（Task 15）執行一次。
- Commit 訊息前綴：純測試遷移一律 `test(epic-45):`；Task 14（新增測試檔）用 `test(epic-45):`、Task 15（文件收尾）用 `docs(epic-45):`（沿用本 Epic 全程一致的慣例——查證 Issue 3-8 每一則收尾 commit 皆為不含 Issue 編號的 `docs(epic-45): 標記 Issue N 為 completed...` 格式，未曾使用 `docs(epic-45-issue-N):` 這種帶編號前綴的變體；`review-plan-issue-9.md` M-3 建議改用後者會偏離本 Epic 已建立的一致慣例，經查證後不採納，維持原計畫寫法）。

---

### Task 1：共用小元件測試遷移（一）—— `screens/widgets/` 群組 A

**Files:**
- Modify: `app/test/screens/widgets/text_conversion_icon_test.dart`（4 處）
- Modify: `app/test/screens/widgets/eb_option_chip_group_test.dart`（4 處）
- Modify: `app/test/screens/widgets/eb_stepper_test.dart`（1 處）
- Modify: `app/test/screens/widgets/eb_section_header_test.dart`（2 處）
- Modify: `app/test/screens/widgets/eb_sheet_shell_test.dart`（1 處，`_pumpAndOpen()` helper；`review-plan-issue-9.md` I-1 補記歸屬，另有 1 處刻意保留的 fallback 測試**不得**修改，見下方 Step 6 與 Global Constraints 白名單說明）

**Interfaces:**
- Consumes：`AppLocalizations.localizationsDelegates`/`AppLocalizations.supportedLocales`（`package:elinkbook/l10n/app_localizations.dart`，Issue 0 已產生）。
- Produces：無（純測試檔異動，不影響其他 Task）。

- [ ] **Step 1：確認五個檔案目前測試皆為綠燈（遷移前基線）**

Run: `flutter test test/screens/widgets/text_conversion_icon_test.dart test/screens/widgets/eb_option_chip_group_test.dart test/screens/widgets/eb_stepper_test.dart test/screens/widgets/eb_section_header_test.dart test/screens/widgets/eb_sheet_shell_test.dart`
Expected: 全數 PASS（4+8+7+2+6 = 27 個測試）。

- [ ] **Step 2：`text_conversion_icon_test.dart` —— 4 處 `const MaterialApp(` 移除 `const` 並補參數**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（`text_conversion_icon_test.dart:9-17`，修改前後）：
```dart
// 修改前
await tester.pumpWidget(
  const MaterialApp(
    home: Scaffold(
      body: TextConversionIcon(
        mode: TextConversionMode.toTraditional,
      ),
    ),
  ),
);

// 修改後
await tester.pumpWidget(
  MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(
      body: TextConversionIcon(
        mode: TextConversionMode.toTraditional,
      ),
    ),
  ),
);
```
其餘 3 處（`toSimplified`／`original`／「繼承 IconTheme」三個測試，行號約 26、42、57）套用相同規則：外層 `MaterialApp` 移除 `const` 並插入三行參數，內層 `Scaffold(...)` 顯式補上 `const`。

- [ ] **Step 3：`eb_option_chip_group_test.dart` —— 4 處 `MaterialApp(` 補參數**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（`buildGroup()` helper，`eb_option_chip_group_test.dart:48-59`，修改前後）：
```dart
// 修改前
return MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: width,
      child: EBOptionChipGroup<String>(
        items: buildItems(onManualTap: onManualTap),
        groupValue: groupValue,
        onSelected: onSelected ?? (_) {},
      ),
    ),
  ),
);

// 修改後
return MaterialApp(
  locale: const Locale('zh', 'TW'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SizedBox(
      width: width,
      child: EBOptionChipGroup<String>(
        items: buildItems(onManualTap: onManualTap),
        groupValue: groupValue,
        onSelected: onSelected ?? (_) {},
      ),
    ),
  ),
);
```
`buildGroup()` 這個 helper 本身補上參數即可讓所有呼叫 `buildGroup(...)` 的測試一併受益，不需逐一修改呼叫端。其餘 3 處為不經過 `buildGroup()` 的獨立 `MaterialApp(` 呼叫（行號約 142「6 個項目」測試、198 `StatefulBuilder` 內的 `MaterialApp`、256「自訂 iconWidget」測試），各自套用相同三行參數插入規則（198 那處是 `builder: (context, setState) => MaterialApp(...)`，插入位置在 `MaterialApp(` 之後、`home:` 之前，與其餘位置相同）。

- [ ] **Step 4：`eb_stepper_test.dart` —— 1 處 `MaterialApp(` 補參數**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

`buildStepper()` helper（`eb_stepper_test.dart:14-27`）：
```dart
// 修改前
return MaterialApp(
  home: Scaffold(
    body: EBStepper(
      keyPrefix: 'test_stepper',
      value: value,
      min: min,
      max: max,
      step: step,
      displayValue: displayValue,
      onChanged: onChanged ?? (_) {},
    ),
  ),
);

// 修改後
return MaterialApp(
  locale: const Locale('zh', 'TW'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: EBStepper(
      keyPrefix: 'test_stepper',
      value: value,
      min: min,
      max: max,
      step: step,
      displayValue: displayValue,
      onChanged: onChanged ?? (_) {},
    ),
  ),
);
```

- [ ] **Step 5：`eb_section_header_test.dart` —— 2 處 `const MaterialApp(` 移除 `const` 並補參數**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（`eb_section_header_test.dart:7-11`，修改前後）：
```dart
// 修改前
await tester.pumpWidget(
  const MaterialApp(
    home: Scaffold(body: EBSectionHeader(title: '外觀')),
  ),
);

// 修改後
await tester.pumpWidget(
  MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: EBSectionHeader(title: '外觀')),
  ),
);
```
第二處（行號約 18，「文字樣式為粗體」測試）套用相同規則。

- [ ] **Step 6：`eb_sheet_shell_test.dart` —— 1 處 `MaterialApp(` 補參數（`_pumpAndOpen()` helper），第 2 處刻意保留不動**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

`_pumpAndOpen()` helper（`eb_sheet_shell_test.dart:20-42`，修改前後）：
```dart
// 修改前
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

// 修改後
Future<void> _pumpAndOpen(
  WidgetTester tester, {
  bool isEinkMode = false,
  NavigatorObserver? observer,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: observer == null ? [] : [observer],
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
```
此檔案「拖曳把手存在」／「右上角關閉按鈕能關閉 Sheet」／「isEinkMode: true...」／「isEinkMode: false...」共 4 個測試皆透過 `_pumpAndOpen(...)` 建構，補完 helper 即涵蓋全部呼叫點。**第 82-105 行「AppLocalizations 不存在（裸 MaterialApp）時，tooltip 回退既有中文字面值」測試禁止修改**——這個測試故意保留裸 `MaterialApp(home: Builder(...))`（無 `locale`/`localizationsDelegates`/`supportedLocales`），驗證的正是 `EBSheetShell` 在沒有 `AppLocalizations` 委派時能安全回退成固定中文字面值 `'關閉'`，若比照本 Task 其他呼叫點補上三行參數，會讓這個測試永遠無法再驗證到 fallback 分支（見 Global Constraints 白名單例外）。

- [ ] **Step 7：重新確認五個檔案 `MaterialApp(` 出現次數未變（4/4/1/2/2）且全數測試通過**

Run: `grep -c "MaterialApp(" test/screens/widgets/text_conversion_icon_test.dart test/screens/widgets/eb_option_chip_group_test.dart test/screens/widgets/eb_stepper_test.dart test/screens/widgets/eb_section_header_test.dart test/screens/widgets/eb_sheet_shell_test.dart`
Expected: 依序 `4`／`4`／`1`／`2`／`2`（`eb_sheet_shell_test.dart` 維持 2 不變——1 處已補參數＋1 處刻意保留的 fallback）。

Run: `flutter test test/screens/widgets/text_conversion_icon_test.dart test/screens/widgets/eb_option_chip_group_test.dart test/screens/widgets/eb_stepper_test.dart test/screens/widgets/eb_section_header_test.dart test/screens/widgets/eb_sheet_shell_test.dart`
Expected: 全數 PASS，零回歸（`eb_sheet_shell_test.dart` 的 fallback 測試必須仍然通過，代表回退邏輯確實未被破壞）。

- [ ] **Step 8：Commit**

```bash
git add test/screens/widgets/text_conversion_icon_test.dart test/screens/widgets/eb_option_chip_group_test.dart test/screens/widgets/eb_stepper_test.dart test/screens/widgets/eb_section_header_test.dart test/screens/widgets/eb_sheet_shell_test.dart
git commit -m "test(epic-45): 共用小元件測試遷移（text_conversion_icon／eb_option_chip_group／eb_stepper／eb_section_header／eb_sheet_shell）"
```

---

### Task 2：共用小元件測試遷移（二）—— `reader_option_tile`／`book_cover`／`cover_placeholder`

**Files:**
- Modify: `app/test/screens/widgets/reader_option_tile_test.dart`（4 處）
- Modify: `app/test/library/widgets/book_cover_test.dart`（5 處）
- Modify: `app/test/library/widgets/cover_placeholder_test.dart`（1 處）

**Interfaces:**
- Consumes：同 Task 1。
- Produces：無。

- [ ] **Step 1：確認三個檔案目前測試皆為綠燈**

Run: `flutter test test/screens/widgets/reader_option_tile_test.dart test/library/widgets/book_cover_test.dart test/library/widgets/cover_placeholder_test.dart`
Expected: 全數 PASS（4+5+8 = 17 個測試）。

- [ ] **Step 2：`reader_option_tile_test.dart` —— 4 處 `MaterialApp(` 補參數（其中 2 處已帶 `theme:` 參數）**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（`reader_option_tile_test.dart:10-13`，修改前後，注意此處已有 `theme:` 參數）：
```dart
// 修改前
await tester.pumpWidget(MaterialApp(
  theme: buildEinkThemeData(),
  home: Scaffold(

// 修改後
await tester.pumpWidget(MaterialApp(
  theme: buildEinkThemeData(),
  locale: const Locale('zh', 'TW'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
```
其餘 3 處（行號約 58、101、137）套用相同規則：三行參數插入在既有參數列（`theme:` 若存在則接續其後，否則直接在 `MaterialApp(` 後）與 `home:` 之間。

- [ ] **Step 3：`book_cover_test.dart` —— 5 處 `MaterialApp(` 補參數（皆已帶 `theme:` 參數）**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（`book_cover_test.dart:25-28`，修改前後）：
```dart
// 修改前
await tester.pumpWidget(MaterialApp(
  theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
  home: BookCover(book: _book(isDownloaded: false)),
));

// 修改後
await tester.pumpWidget(MaterialApp(
  theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
  locale: const Locale('zh', 'TW'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: BookCover(book: _book(isDownloaded: false)),
));
```
其餘 4 處（行號約 34、43、57、70）套用相同規則。

- [ ] **Step 4：`cover_placeholder_test.dart` —— 1 處 `MaterialApp(` 補參數（`wrap()` helper）**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

`wrap()` helper（`cover_placeholder_test.dart:9-12`）：
```dart
// 修改前
Widget wrap(Widget child, {required bool isEinkMode}) {
  return MaterialApp(
    theme: resolveThemeData(theme: AppTheme.light, isEinkMode: isEinkMode),
    home: Center(child: child),
  );
}

// 修改後
Widget wrap(Widget child, {required bool isEinkMode}) {
  return MaterialApp(
    theme: resolveThemeData(theme: AppTheme.light, isEinkMode: isEinkMode),
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Center(child: child),
  );
}
```
此檔案全部 8 個測試皆透過 `wrap(...)` 建構，補完 helper 即涵蓋全部呼叫點。

- [ ] **Step 5：重新確認次數未變（4/5/1）且全數測試通過**

Run: `grep -c "MaterialApp(" test/screens/widgets/reader_option_tile_test.dart test/library/widgets/book_cover_test.dart test/library/widgets/cover_placeholder_test.dart`
Expected: 依序 `4`／`5`／`1`。

Run: `flutter test test/screens/widgets/reader_option_tile_test.dart test/library/widgets/book_cover_test.dart test/library/widgets/cover_placeholder_test.dart`
Expected: 全數 PASS，零回歸。

- [ ] **Step 6：Commit**

```bash
git add test/screens/widgets/reader_option_tile_test.dart test/library/widgets/book_cover_test.dart test/library/widgets/cover_placeholder_test.dart
git commit -m "test(epic-45): 共用小元件測試遷移（reader_option_tile／book_cover／cover_placeholder）"
```

---

### Task 3：閱讀器共用元件與工具測試遷移

**Files:**
- Modify: `app/test/screens/reader_footer_test.dart`（10 處）
- Modify: `app/test/reader/tap_zone_detector_test.dart`（2 處）
- Modify: `app/test/reader/bounce_tolerant_long_press_detector_test.dart`（1 處）
- Modify: `app/test/reader/pdf_crop_frame_overlay_test.dart`（2 處）
- Modify: `app/test/support/pump_until_pdf_ready_test.dart`（3 處）
- Modify: `app/test/theme/app_theme_data_test.dart`（1 處）

**Interfaces:**
- Consumes：同 Task 1。
- Produces：無。

- [ ] **Step 1：確認六個檔案目前測試皆為綠燈**

Run: `flutter test test/screens/reader_footer_test.dart test/reader/tap_zone_detector_test.dart test/reader/bounce_tolerant_long_press_detector_test.dart test/reader/pdf_crop_frame_overlay_test.dart test/support/pump_until_pdf_ready_test.dart test/theme/app_theme_data_test.dart`
Expected: 全數 PASS。

- [ ] **Step 2：`reader_footer_test.dart` —— 10 處 `MaterialApp(` 補參數**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（`reader_footer_test.dart:7-15`，修改前後）：
```dart
// 修改前
await tester.pumpWidget(MaterialApp(
  home: Scaffold(
    body: ReaderFooter(
      currentPage: 5,
      totalPages: 20,
      onPageChanged: (_) {},
    ),
  ),
));

// 修改後
await tester.pumpWidget(MaterialApp(
  locale: const Locale('zh', 'TW'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: ReaderFooter(
      currentPage: 5,
      totalPages: 20,
      onPageChanged: (_) {},
    ),
  ),
));
```
其餘 9 處（行號約 22、41、75、95、115、126、144、161、180，皆為同構的 `MaterialApp(home: Scaffold(body: ReaderFooter(...)))` 呼叫）套用相同規則。

- [ ] **Step 3：`tap_zone_detector_test.dart` —— 2 處 `MaterialApp(` 補參數（1 處在 `wrap()` helper、1 處獨立呼叫）**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

`wrap()` helper（`tap_zone_detector_test.dart:14-24`）：
```dart
// 修改前
return MaterialApp(
  home: TapZoneDetector(
    onTap: onTap,
    nowMs: nowMs,
    tapMaxDurationMs: tapMaxDurationMs,
    tapSlop: tapSlop,
    tapDebounceMs: tapDebounceMs,
    onDebugEvent: onDebugEvent,
    child: const SizedBox(width: 100, height: 100),
  ),
);

// 修改後
return MaterialApp(
  locale: const Locale('zh', 'TW'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: TapZoneDetector(
    onTap: onTap,
    nowMs: nowMs,
    tapMaxDurationMs: tapMaxDurationMs,
    tapSlop: tapSlop,
    tapDebounceMs: tapDebounceMs,
    onDebugEvent: onDebugEvent,
    child: const SizedBox(width: 100, height: 100),
  ),
);
```
第二處是「未明確傳入 tapSlop 時，建構子預設值等同 kTapZoneSlop」測試（行號約 236）刻意不透過 `wrap()`、直接寫 `MaterialApp(home: TapZoneDetector(...))`，同樣套用三行參數插入規則。

- [ ] **Step 4：`bounce_tolerant_long_press_detector_test.dart` —— 1 處 `MaterialApp(` 補參數（`wrap()` helper）**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

`wrap()` helper（`bounce_tolerant_long_press_detector_test.dart:15-26`），在 `return MaterialApp(` 後插入三行參數，`home: BounceTolerantLongPressDetector(...)` 其餘內容不變（此檔案全部測試皆透過 `wrap(...)` 建構）。

- [ ] **Step 5：`pdf_crop_frame_overlay_test.dart` —— 2 處 `MaterialApp(` 補參數（1 處在 `wrap()` helper、1 處獨立呼叫）**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

`wrap()` helper（`pdf_crop_frame_overlay_test.dart:13-15`）：
```dart
// 修改前
Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 800, height: 1600, child: child)),
    );

// 修改後
Widget wrap(Widget child) => MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SizedBox(width: 800, height: 1600, child: child)),
    );
```
第二處是「包含 CustomPaint 遮罩層與帶背景之 Material 按鈕」測試（行號約 162）獨立寫了一個 `MaterialApp(home: Scaffold(body: SizedBox(...child: PdfCropFrameOverlay(...))))`，不經過 `wrap()`，同樣套用三行參數插入規則。

- [ ] **Step 6：`pump_until_pdf_ready_test.dart` —— 3 處單行 `const MaterialApp(home: SizedBox())` 改為多行非 const 形式**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（`pump_until_pdf_ready_test.dart:9`，修改前後）：
```dart
// 修改前
await tester.pumpWidget(const MaterialApp(home: SizedBox()));

// 修改後
await tester.pumpWidget(
  MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const SizedBox(),
  ),
);
```
其餘 2 處（行號約 30、48，皆為逐字相同的 `const MaterialApp(home: SizedBox())`）套用相同規則。

- [ ] **Step 7：`app_theme_data_test.dart` —— 1 處 `MaterialApp(` 補參數（已帶 `theme:` 參數）**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（`app_theme_data_test.dart:111-114`，修改前後）：
```dart
// 修改前
await tester.pumpWidget(
  MaterialApp(
    theme: theme,
    home: const Scaffold(

// 修改後
await tester.pumpWidget(
  MaterialApp(
    theme: theme,
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(
```

- [ ] **Step 8：重新確認六個檔案次數未變（10/2/1/2/3/1）且全數測試通過**

Run: `grep -c "MaterialApp(" test/screens/reader_footer_test.dart test/reader/tap_zone_detector_test.dart test/reader/bounce_tolerant_long_press_detector_test.dart test/reader/pdf_crop_frame_overlay_test.dart test/support/pump_until_pdf_ready_test.dart test/theme/app_theme_data_test.dart`
Expected: 依序 `10`／`2`／`1`／`2`／`3`／`1`。

Run: `flutter test test/screens/reader_footer_test.dart test/reader/tap_zone_detector_test.dart test/reader/bounce_tolerant_long_press_detector_test.dart test/reader/pdf_crop_frame_overlay_test.dart test/support/pump_until_pdf_ready_test.dart test/theme/app_theme_data_test.dart`
Expected: 全數 PASS，零回歸。

- [ ] **Step 9：Commit**

```bash
git add test/screens/reader_footer_test.dart test/reader/tap_zone_detector_test.dart test/reader/bounce_tolerant_long_press_detector_test.dart test/reader/pdf_crop_frame_overlay_test.dart test/support/pump_until_pdf_ready_test.dart test/theme/app_theme_data_test.dart
git commit -m "test(epic-45): 閱讀器共用元件與工具測試遷移（reader_footer／tap_zone_detector／bounce_tolerant_long_press_detector／pdf_crop_frame_overlay／pump_until_pdf_ready／app_theme_data）"
```

---

### Task 4：`pdf_reader_view_jump_highlight_test.dart` 測試遷移

**Files:**
- Modify: `app/test/reader/pdf_reader_view_jump_highlight_test.dart`（3 處，皆帶 `theme:` 參數）

**Interfaces:**
- Consumes：同 Task 1。
- Produces：無。

- [ ] **Step 1：確認目前測試皆為綠燈**

Run: `flutter test test/reader/pdf_reader_view_jump_highlight_test.dart`
Expected: 全數 PASS。

- [ ] **Step 2：3 處 `MaterialApp(` 補參數**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（`pdf_reader_view_jump_highlight_test.dart:19-25`，修改前後）：
```dart
// 修改前
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},

// 修改後
      MaterialApp(
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
```
其餘 2 處（行號約 49、82，皆為同構的 `MaterialApp(theme: ..., home: PdfReaderView(...))`）套用相同規則。

- [ ] **Step 3：重新確認次數未變（3）且測試通過**

Run: `grep -c "MaterialApp(" test/reader/pdf_reader_view_jump_highlight_test.dart`
Expected: `3`。

Run: `flutter test test/reader/pdf_reader_view_jump_highlight_test.dart`
Expected: 全數 PASS，零回歸。

- [ ] **Step 4：Commit**

```bash
git add test/reader/pdf_reader_view_jump_highlight_test.dart
git commit -m "test(epic-45): pdf_reader_view_jump_highlight_test.dart 測試遷移"
```

---

### Task 5：`pdf_reader_view_nav_zone_test.dart` 測試遷移

**Files:**
- Modify: `app/test/reader/pdf_reader_view_nav_zone_test.dart`（8 處，皆不帶 `theme:` 參數）

**Interfaces:**
- Consumes：同 Task 1。
- Produces：無。

- [ ] **Step 1：確認目前測試皆為綠燈**

Run: `flutter test test/reader/pdf_reader_view_nav_zone_test.dart`
Expected: 全數 PASS。

- [ ] **Step 2：8 處 `MaterialApp(` 補參數**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（`pdf_reader_view_nav_zone_test.dart:18-24`，修改前後）：
```dart
// 修改前
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onZoneAction: (action) => triggered = action,
        ),

// 修改後
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onZoneAction: (action) => triggered = action,
        ),
```
其餘 7 處（行號約 47、82、105、134、172、202、238，皆為同構的 `MaterialApp(home: PdfReaderView(...))`）套用相同規則。

- [ ] **Step 3：重新確認次數未變（8）且測試通過**

Run: `grep -c "MaterialApp(" test/reader/pdf_reader_view_nav_zone_test.dart`
Expected: `8`。

Run: `flutter test test/reader/pdf_reader_view_nav_zone_test.dart`
Expected: 全數 PASS，零回歸。

- [ ] **Step 4：Commit**

```bash
git add test/reader/pdf_reader_view_nav_zone_test.dart
git commit -m "test(epic-45): pdf_reader_view_nav_zone_test.dart 測試遷移"
```

---

### Task 6：`pdf_reader_view_toc_test.dart` ＋ `pdf_reader_view_thumbnail_test.dart` 測試遷移

**Files:**
- Modify: `app/test/reader/pdf_reader_view_toc_test.dart`（2 處）
- Modify: `app/test/reader/pdf_reader_view_thumbnail_test.dart`（3 處）

**Interfaces:**
- Consumes：同 Task 1。
- Produces：無。

- [ ] **Step 1：確認兩個檔案目前測試皆為綠燈**

Run: `flutter test test/reader/pdf_reader_view_toc_test.dart test/reader/pdf_reader_view_thumbnail_test.dart`
Expected: 全數 PASS。

- [ ] **Step 2：`pdf_reader_view_toc_test.dart` —— 2 處 `MaterialApp(` 補參數**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（`pdf_reader_view_toc_test.dart:20-25`，修改前後）：
```dart
// 修改前
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_pdf_toc.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),

// 修改後
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_pdf_toc.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
```
第二處（行號約 68）套用相同規則。

- [ ] **Step 3：`pdf_reader_view_thumbnail_test.dart` —— 3 處 `MaterialApp(` 補參數**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（`pdf_reader_view_thumbnail_test.dart:16-21`，修改前後）：
```dart
// 修改前
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),

// 修改後
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
```
其餘 2 處（行號約 45、77）套用相同規則。

- [ ] **Step 4：重新確認次數未變（2/3）且測試通過**

Run: `grep -c "MaterialApp(" test/reader/pdf_reader_view_toc_test.dart test/reader/pdf_reader_view_thumbnail_test.dart`
Expected: 依序 `2`／`3`。

Run: `flutter test test/reader/pdf_reader_view_toc_test.dart test/reader/pdf_reader_view_thumbnail_test.dart`
Expected: 全數 PASS，零回歸。

- [ ] **Step 5：Commit**

```bash
git add test/reader/pdf_reader_view_toc_test.dart test/reader/pdf_reader_view_thumbnail_test.dart
git commit -m "test(epic-45): pdf_reader_view_toc_test.dart／pdf_reader_view_thumbnail_test.dart 測試遷移"
```

---

### Task 7：`pdf_reader_view_search_test.dart` 測試遷移

**Files:**
- Modify: `app/test/reader/pdf_reader_view_search_test.dart`（7 處，其中 3 處帶 `theme:` 參數）

**Interfaces:**
- Consumes：同 Task 1。
- Produces：無。

- [ ] **Step 1：確認目前測試皆為綠燈**

Run: `flutter test test/reader/pdf_reader_view_search_test.dart`
Expected: 全數 PASS。

- [ ] **Step 2：7 處 `MaterialApp(` 補參數**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（不帶 `theme:` 的一般形式，`pdf_reader_view_search_test.dart:18-23`，修改前後）：
```dart
// 修改前
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),

// 修改後
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
        ),
```
帶 `theme:` 的形式（行號約 114、141、190）套用 Task 4 已示範的規則（三行參數插入在 `theme:` 之後、`home:` 之前）。其餘不帶 `theme:` 的形式（行號約 47、69、91）套用上方規則。合計 7 處。

- [ ] **Step 3：重新確認次數未變（7）且測試通過**

Run: `grep -c "MaterialApp(" test/reader/pdf_reader_view_search_test.dart`
Expected: `7`。

Run: `flutter test test/reader/pdf_reader_view_search_test.dart`
Expected: 全數 PASS，零回歸。

- [ ] **Step 4：Commit**

```bash
git add test/reader/pdf_reader_view_search_test.dart
git commit -m "test(epic-45): pdf_reader_view_search_test.dart 測試遷移"
```

---

### Task 8：`pdf_reader_view_selection_test.dart` 測試遷移

**Files:**
- Modify: `app/test/reader/pdf_reader_view_selection_test.dart`（20 處，全檔 851 行，全為 `await tester.pumpWidget(\n  MaterialApp(\n    home: PdfReaderView(...` 同構形式，不帶 `theme:`）

**Interfaces:**
- Consumes：同 Task 1。
- Produces：無。

- [ ] **Step 1：確認目前測試皆為綠燈**

Run: `flutter test test/reader/pdf_reader_view_selection_test.dart`
Expected: 全數 PASS。

- [ ] **Step 2：20 處 `MaterialApp(` 補參數**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（`pdf_reader_view_selection_test.dart:25-29`，修改前後）：
```dart
// 修改前
    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',

// 修改後
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
```
全檔其餘 19 處（行號約 53、96、161、204、249、285、354、388 及後續，皆為 `await tester.pumpWidget(\n  MaterialApp(\n    home: PdfReaderView(...` 同構形式，逐一確認 `grep -n "MaterialApp(" test/reader/pdf_reader_view_selection_test.dart` 完整清單後逐一套用相同規則）。

- [ ] **Step 3：重新確認次數未變（20）且測試通過**

Run: `grep -c "MaterialApp(" test/reader/pdf_reader_view_selection_test.dart`
Expected: `20`。

Run: `flutter test test/reader/pdf_reader_view_selection_test.dart`
Expected: 全數 PASS，零回歸。

- [ ] **Step 4：Commit**

```bash
git add test/reader/pdf_reader_view_selection_test.dart
git commit -m "test(epic-45): pdf_reader_view_selection_test.dart 測試遷移"
```

---

### Task 9：`pdf_reader_view_filters_test.dart` 測試遷移

**Files:**
- Modify: `app/test/reader/pdf_reader_view_filters_test.dart`（20 處，全檔 554 行，同構形式，不帶 `theme:`；其中一處 `home:` 是 `SizedBox(height: 2000, child: PdfReaderView(...))` 而非直接 `PdfReaderView(...)`）

**Interfaces:**
- Consumes：同 Task 1。
- Produces：無。

- [ ] **Step 1：確認目前測試皆為綠燈**

Run: `flutter test test/reader/pdf_reader_view_filters_test.dart`
Expected: 全數 PASS。

- [ ] **Step 2：20 處 `MaterialApp(` 補參數**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（`pdf_reader_view_filters_test.dart:25-29`，修改前後）：
```dart
// 修改前
      await tester.pumpWidget(
        MaterialApp(
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',

// 修改後
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfReaderView(
            key: key,
            filePath: 'test/fixtures/sample_multi_page.pdf',
```
包含 `SizedBox` 包裝的那一處（行號約 165-168，`home: SizedBox(height: 2000, child: PdfReaderView(...))`）套用相同規則——三行參數插入在 `MaterialApp(` 之後、`home:` 之前，不受 `home` 內層是否為 `SizedBox` 包裝影響。全檔其餘 18 處（先用 `grep -n "MaterialApp(" test/reader/pdf_reader_view_filters_test.dart` 取得完整行號清單）逐一套用相同規則。

- [ ] **Step 3：重新確認次數未變（20）且測試通過**

Run: `grep -c "MaterialApp(" test/reader/pdf_reader_view_filters_test.dart`
Expected: `20`。

Run: `flutter test test/reader/pdf_reader_view_filters_test.dart`
Expected: 全數 PASS，零回歸。

- [ ] **Step 4：Commit**

```bash
git add test/reader/pdf_reader_view_filters_test.dart
git commit -m "test(epic-45): pdf_reader_view_filters_test.dart 測試遷移"
```

---

### Task 10：`pdf_reader_view_dual_page_test.dart` 測試遷移

**Files:**
- Modify: `app/test/reader/pdf_reader_view_dual_page_test.dart`（16 處，全檔 596 行，同構形式，不帶 `theme:`）

**Interfaces:**
- Consumes：同 Task 1。
- Produces：無。

- [ ] **Step 1：確認目前測試皆為綠燈**

Run: `flutter test test/reader/pdf_reader_view_dual_page_test.dart`
Expected: 全數 PASS。

- [ ] **Step 2：16 處 `MaterialApp(` 補參數**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（`pdf_reader_view_dual_page_test.dart:19-23`，修改前後）：
```dart
// 修改前
    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',

// 修改後
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
```
全檔其餘 15 處（行號約 54、82、110、139、179、222、262 及後續，先用 `grep -n "MaterialApp(" test/reader/pdf_reader_view_dual_page_test.dart` 取得完整行號清單）逐一套用相同規則。

- [ ] **Step 3：重新確認次數未變（16）且測試通過**

Run: `grep -c "MaterialApp(" test/reader/pdf_reader_view_dual_page_test.dart`
Expected: `16`。

Run: `flutter test test/reader/pdf_reader_view_dual_page_test.dart`
Expected: 全數 PASS，零回歸。

- [ ] **Step 4：Commit**

```bash
git add test/reader/pdf_reader_view_dual_page_test.dart
git commit -m "test(epic-45): pdf_reader_view_dual_page_test.dart 測試遷移"
```

---

### Task 11：`pdf_reader_view_test.dart` 測試遷移（`review-plan-issue-9.md` I-1 補記歸屬）

**Files:**
- Modify: `app/test/reader/pdf_reader_view_test.dart`（7 處，`PdfReaderView` 主測試檔，全檔 10 個測試中另有 3 個已由 Issue 7 遷移為 `pumpLocalizedWidget`，行號 49／75／134，本 Task 不觸碰）

**Interfaces:**
- Consumes：同 Task 1。
- Produces：無。

**背景**：本檔案是 `PdfReaderView` 的主要測試檔，因檔案內已有 3 處由 Issue 7 遷移為 `pumpLocalizedWidget`，導致原始「檔案級差集」盤點法誤判整檔已完成而漏列（`review-plan-issue-9.md` I-1）。

- [ ] **Step 1：確認目前測試皆為綠燈**

Run: `flutter test test/reader/pdf_reader_view_test.dart`
Expected: 全數 PASS（10 個測試）。

- [ ] **Step 2：7 處 `MaterialApp(` 補參數**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（`pdf_reader_view_test.dart:23-28`，修改前後）：
```dart
// 修改前
      MaterialApp(
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (msg) => errorMessage = msg,
        ),

// 修改後
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (msg) => errorMessage = msg,
        ),
```
其餘 6 處（行號約 99、179、202、235、270、307，皆為同構的 `MaterialApp(home: PdfReaderView(...))` 形式，其中行 179 是 `content://` URI 測試情境，不影響參數插入位置）套用相同規則。**不得**觸碰行 49、75、134 這 3 處既有的 `pumpLocalizedWidget(...)` 呼叫。

- [ ] **Step 3：重新確認次數未變（7）且測試通過**

Run: `grep -c "MaterialApp(" test/reader/pdf_reader_view_test.dart`
Expected: `7`（`pumpLocalizedWidget(` 呼叫不計入此關鍵字比對）。

Run: `flutter test test/reader/pdf_reader_view_test.dart`
Expected: 全數 PASS，零回歸。

- [ ] **Step 4：Commit**

```bash
git add test/reader/pdf_reader_view_test.dart
git commit -m "test(epic-45): pdf_reader_view_test.dart 測試遷移（review-plan-issue-9.md I-1 補記歸屬）"
```

---

### Task 12：`foliate_reader_view_test.dart` 測試遷移（`review-plan-issue-9.md` I-1 補記歸屬）

**Files:**
- Modify: `app/test/reader/foliate_reader_view_test.dart`（15 處，`FoliateReaderView` 主測試檔，全檔 17 個測試中另有 3 個已由 Issue 7 遷移為 `pumpLocalizedWidget`，行號 1940／1970／1995，本 Task 不觸碰）

**Interfaces:**
- Consumes：同 Task 1。
- Produces：無。

**背景**：本檔案是 EPUB／Foliate 渲染引擎的核心測試檔，與 Task 11 同樣因檔案內已有局部遷移而被原始盤點法誤判漏列（`review-plan-issue-9.md` I-1）。

- [ ] **Step 1：確認目前測試皆為綠燈**

Run: `flutter test test/reader/foliate_reader_view_test.dart`
Expected: 全數 PASS（17 個測試）。

- [ ] **Step 2：13 處「直接 `home: FoliateReaderView(...)`」形式的 `MaterialApp(` 補參數**

新增 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（`foliate_reader_view_test.dart:766-772`，修改前後）：
```dart
// 修改前
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
            navZoneActions: const [

// 修改後
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
            navZoneActions: const [
```
其餘 12 處（行號約 809、839、878、927、961、988、1012、1043、1079、1106、1138、1169，皆為同構的 `MaterialApp(home: FoliateReaderView(...))` 形式）套用相同規則。

- [ ] **Step 3：2 處「`dispose during cache does not leak cache directory` 測試」內的 `MaterialApp(` 補參數（含 1 處 `Scaffold` 包裝、1 處單行 `const` 形式）**

實際範例（`foliate_reader_view_test.dart:1914-1921`，修改前後）：
```dart
// 修改前
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      ));

      // 移除 widget（觸發 dispose），此時快取尚未完成
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));

// 修改後
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      ));

      // 移除 widget（觸發 dispose），此時快取尚未完成
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox()),
        ),
      );
```
第二處原本是單行 `const MaterialApp(home: Scaffold(body: SizedBox()))`——因新增非常數參數必須移除外層 `const`、改為多行形式，內層 `Scaffold(body: SizedBox())` 補上 `const`。**不得**觸碰行 1940、1970、1995 這 3 處既有的 `pumpLocalizedWidget(...)` 呼叫（緊接在本測試之後的 3 個「cache 失敗顯示訊息」測試，屬 Issue 7 既有範圍）。

- [ ] **Step 4：重新確認次數未變（15）且測試通過**

Run: `grep -c "MaterialApp(" test/reader/foliate_reader_view_test.dart`
Expected: `15`。

Run: `flutter test test/reader/foliate_reader_view_test.dart`
Expected: 全數 PASS，零回歸。

- [ ] **Step 5：Commit**

```bash
git add test/reader/foliate_reader_view_test.dart
git commit -m "test(epic-45): foliate_reader_view_test.dart 測試遷移（review-plan-issue-9.md I-1 補記歸屬）"
```

---

### Task 13：`reader_screen_test.dart` 殘留裸 `MaterialApp` 遷移（`review-plan-issue-9.md` I-1 補記歸屬）

**Files:**
- Modify: `app/test/screens/reader_screen_test.dart`（6 處殘留；全檔另有 220+ 處已於 Issue 4 遷移，本 Task 僅處理 Issue 4 當時遺漏的殘留呼叫點）

**Interfaces:**
- Consumes：同 Task 1。
- Produces：無。

**背景**：Issue 4 曾將本檔案 227 處裸 `MaterialApp` 遷移為 `locale: const Locale('zh', 'TW')` 與在地化委派（見 `epic.md` Issue 4 完成記錄），但盤點漏了 6 處——5 處是「換掉整棵 widget 樹以觸發 `ReaderScreen.dispose()`」用途的 `const MaterialApp(home: SizedBox.shrink())` 容器、1 處是獨立的 `PdfReaderView` 靜態方法測試（`review-plan-issue-9.md` I-1 補記歸屬）。

- [ ] **Step 1：確認目前測試皆為綠燈（本檔案規模龐大，僅需一次完整執行作為本 Task 前後基線比對）**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: 全數 PASS（237 個測試，比照 Issue 4 完成記錄的既有基線）。

- [ ] **Step 2：5 處 `const MaterialApp(home: SizedBox.shrink())` dispose 觸發容器改為多行非 const 形式**

新增 import（若既有 import 區塊尚未包含）：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

實際範例（`reader_screen_test.dart:400-401`，修改前後）：
```dart
// 修改前
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

// 修改後
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SizedBox.shrink(),
        ),
      );
      await tester.pump();
```
其餘 4 處（行號約 457、2129、2157、10682，皆為逐字相同的 `const MaterialApp(home: SizedBox.shrink())`，唯一差異是後面接續的斷言內容，不受本次修改影響）套用相同規則。

- [ ] **Step 3：1 處 `MaterialApp(home: PdfReaderView(...))` 補參數**

實際範例（`reader_screen_test.dart:3604-3612`，修改前後）：
```dart
// 修改前
    await tester.pumpWidget(
      MaterialApp(
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );

// 修改後
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfReaderView(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          onPageRendered: () => renderedCount++,
          onError: (_) {},
          onPageChanged: (info) => lastPageInfo = info,
        ),
      ),
    );
```

- [ ] **Step 4：確認本 Task 觸及的 6 處呼叫點皆已補上參數，且測試通過**

**注意**：本檔案其餘 227+ 處已於 Issue 4 改為 `locale: const Locale('zh', 'TW')` inline 參數風格，`grep -c "MaterialApp("` 對整份檔案計數會回傳 233（227+6），無法用來單獨驗證這 6 處是否修改成功（這正是 `review-plan-issue-9.md` I-1／I-2 指出的「檔案級盤點法」盲區在單一檔案內部的同構問題）。改用以下指令，確認裸 `const MaterialApp(home: SizedBox.shrink())`／未帶 `locale:` 的 `MaterialApp(home: PdfReaderView(...))` 這兩種本 Task 目標模式已不存在：

Run: `grep -c "const MaterialApp(home: SizedBox.shrink())" test/screens/reader_screen_test.dart`
Expected: `0`（原本 5 處已全數改寫為多行非 `const` 形式）。

Run: `sed -n '3604,3620p' test/screens/reader_screen_test.dart`
Expected: 目視確認 `MaterialApp(` 後緊接 `locale:`／`localizationsDelegates:`／`supportedLocales:` 三行，`home: PdfReaderView(...)` 內容未變動。

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: 全數 PASS，零回歸（237 個測試，與 Step 1 基線一致）。

- [ ] **Step 5：Commit**

```bash
git add test/screens/reader_screen_test.dart
git commit -m "test(epic-45): reader_screen_test.dart 補齊 Issue 4 遺漏的 6 處殘留裸 MaterialApp（review-plan-issue-9.md I-1 補記歸屬）"
```

---

### Task 14：新增 `app/test/l10n/locale_switch_test.dart`

**Files:**
- Create: `app/test/l10n/locale_switch_test.dart`

**Interfaces:**
- Consumes：`pumpLocalizedWidget()`（`app/test/support/pump_localized_widget.dart`，`locale` 具名參數）、`SettingsScaffold(prefsManager: ...)`（`package:elinkbook/screens/settings_scaffold.dart`）、`LibraryScreen(repository:, importService:, prefsManager:)`（`package:elinkbook/screens/library_screen.dart`）、`FakeReaderPrefsManager`／`FakeLibraryRepository`／`FakeBookImportService`（`app/test/support/`）。
- Produces：無（獨立驗證測試檔，不影響其他 Task）。

**背景**：`spec.md` §8 定案「新增 `app/test/l10n/locale_switch_test.dart`：針對少數代表性畫面（例如 `SettingsScaffold`、`LibraryScreen`）分別在 `zh_CN`/`en` locale 下驗證關鍵字串正確渲染」。查證 ARB 現行翻譯：`settingsScaffoldTitle`（"設定"／"设定"／"Settings"）、`settingsAppearanceSectionTitle`（"外觀"／"外观"／"Appearance"）、`libraryShelfTitle`（"書架"／"书架"／"Library"）、`libraryEmptyStateMessage`（"尚未匯入書籍"／"尚未导入书籍"／"No books imported yet"）。**每個畫面 group 額外補上一則 `zh_TW`（預設 locale）斷言（`review-plan-issue-9.md` M-2 修正）**，讓本檔案本身就是 `zh_TW`／`zh_CN`／`en` 三語言的完整閉環對照，不必依賴讀者跳去其他模組測試檔才能確認正體中文基準。`SettingsScaffold` 的部分沿用 `settings_scaffold_test.dart` 既有 `setUp()`/`tearDown()` 安全網（`PackageInfo`／`elinkbook/app_info` channel／`SharedPreferences`／`FlutterSecureStoragePlatform` 四項 mock）——即使本測試只斷言最上層的標題與「外觀」分區文字，`SettingsScaffold` 內部四分區以 `IndexedStack` 長駐掛載（見 `settings_scaffold.dart:121` 註解），其餘分區（例如「關於」讀取 `PackageInfo`、「同步與帳號」讀取 `FlutterSecureStoragePlatform`）在 widget tree 建構當下即被一併掛載，缺少對應 mock 會在 `pumpWidget()` 階段拋出 `MissingPluginException`。

- [ ] **Step 1：撰寫測試檔（一次寫完，無需紅燈階段——本 Task 不修改任何 production 邏輯，純粹是對既有已完成的 Issue 1／3 在地化成果做一次跨檔案整合驗證）**

建立 `app/test/l10n/locale_switch_test.dart`：
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/reader/global_reader_prefs.dart';
import 'package:elinkbook/reader/reading_defaults.dart';
import 'package:elinkbook/screens/library_screen.dart';
import 'package:elinkbook/screens/settings_scaffold.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/pump_localized_widget.dart';

const _appInfoChannel = MethodChannel('elinkbook/app_info');

void main() {
  group('SettingsScaffold 代表性字串跨語言渲染', () {
    late FlutterSecureStoragePlatform originalPlatform;

    setUp(() {
      // 沿用 settings_scaffold_test.dart 既有安全網：SettingsScaffold 內部
      // 四分區以 IndexedStack 長駐掛載，即使本測試只看「外觀」分區，其餘
      // 分區（關於／同步與帳號）仍會在 pumpWidget() 當下一併掛載並讀取這些
      // 平台依賴。
      PackageInfo.setMockInitialValues(
        appName: 'elinkBook',
        packageName: 'cc.ugotit.elinkbook',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_appInfoChannel, (call) async => null);
      SharedPreferences.setMockInitialValues({});
      originalPlatform = FlutterSecureStoragePlatform.instance;
      FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
        {},
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_appInfoChannel, null);
      FlutterSecureStoragePlatform.instance = originalPlatform;
    });

    testWidgets('zh_TW locale（預設）下標題與外觀分區正確以正體中文渲染', (tester) async {
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
      );

      expect(find.text('設定'), findsOneWidget);
      expect(find.text('外觀'), findsOneWidget);
    });

    testWidgets('zh_CN locale 下標題與外觀分區正確以簡體中文渲染', (tester) async {
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
        locale: const Locale('zh', 'CN'),
      );

      expect(find.text('设定'), findsOneWidget);
      expect(find.text('外观'), findsOneWidget);
    });

    testWidgets('en locale 下標題與外觀分區正確以英文渲染', (tester) async {
      await pumpLocalizedWidget(
        tester,
        SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
        locale: const Locale('en'),
      );

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
    });
  });

  group('LibraryScreen 代表性字串跨語言渲染', () {
    setUp(() {
      // LibraryScreen.initState() 會呼叫 SharedPreferences.getInstance()，
      // 純 Dart widget test 環境需要官方測試替身（沿用 library_screen_test.dart
      // 既有慣例）。
      SharedPreferences.setMockInitialValues({});
    });

    LibraryScreen buildScreen() => LibraryScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
          prefsManager: FakeReaderPrefsManager(
            globalPrefs: const GlobalReaderPrefs.initial().copyWith(
              // 避免 openLastBookOnLaunch 預設 true 導致自動導覽到
              // ReaderScreen，干擾本測試對書架空狀態文字的斷言（沿用
              // library_screen_test.dart 既有慣例）。
              reading: const ReadingDefaults(openLastBookOnLaunch: false),
            ),
          ),
        );

    testWidgets('zh_TW locale（預設）下書架標題與空狀態文字正確以正體中文渲染', (tester) async {
      await pumpLocalizedWidget(tester, buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('書架'), findsOneWidget);
      expect(find.text('尚未匯入書籍'), findsOneWidget);
    });

    testWidgets('zh_CN locale 下書架標題與空狀態文字正確以簡體中文渲染', (tester) async {
      await pumpLocalizedWidget(
        tester,
        buildScreen(),
        locale: const Locale('zh', 'CN'),
      );
      await tester.pumpAndSettle();

      expect(find.text('书架'), findsOneWidget);
      expect(find.text('尚未导入书籍'), findsOneWidget);
    });

    testWidgets('en locale 下書架標題與空狀態文字正確以英文渲染', (tester) async {
      await pumpLocalizedWidget(
        tester,
        buildScreen(),
        locale: const Locale('en'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Library'), findsOneWidget);
      expect(find.text('No books imported yet'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2：執行測試確認全數通過**

Run: `flutter test test/l10n/locale_switch_test.dart`
Expected: 6 個測試全數 PASS（`SettingsScaffold`／`LibraryScreen` 各 3 個：`zh_TW`／`zh_CN`／`en`）。

- [ ] **Step 3：Commit**

```bash
git add test/l10n/locale_switch_test.dart
git commit -m "test(epic-45): 新增 locale_switch_test.dart 驗證 SettingsScaffold／LibraryScreen 跨語言渲染"
```

---

### Task 15：完整驗收與進度文件更新

**Files:**
- Modify: `docs/epics/epic-45-interface-i18n/issues.md`（Issue 9 標記 `completed`，補記實際盤點結果）
- Modify: `docs/epics/epic-45-interface-i18n/epic.md`（新增開發記錄段落）
- Modify: `docs/epics.md`（若備註欄位需要更新最後處理的 Issue 編號）

**Interfaces:**
- Consumes：Task 1-14 的全部異動。
- Produces：無（本 Issue 最後一個 Task）。

- [ ] **Step 1：完整 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2：完整 `flutter test`**

Run: `flutter test`
Expected: 全數 PASS（與 Issue 8 merge 後的 base commit 基準比對，僅本 Issue 新增的 6 個 `locale_switch_test.dart` 測試為新增項目，其餘測試數量不變、零新增失敗）。

- [ ] **Step 3：確認 `app/test/` 內不再有殘餘裸 `MaterialApp(...)`（`review-plan-issue-9.md` I-2 修正：改用呼叫點層級腳本，不再重用 Global Constraints 當初產生盲區的檔案級 `comm -23` 差集）**

**問題背景**：原始驗收指令 `comm -23 <(grep -rl "MaterialApp(") <(grep -rl "localizationsDelegates\|pumpLocalizedWidget")` 與 Global Constraints 當初產生遮蔽漏洞的盤點邏輯完全相同——只要檔案中任一處出現過 `localizationsDelegates`／`pumpLocalizedWidget`，整份檔案就會被視為已完成，即使檔案內仍有未遷移的裸呼叫點也偵測不到，形同「循環驗證陷阱」。改用以下逐呼叫點掃描的 Node 腳本（不需額外套件，`node` 本身已是本專案既有工具鏈的一部分，見 `app/tool/check_foliate_es_compat.js` 先例），對每個 `MaterialApp(`／`const MaterialApp(` 呼叫點各自用括號配對找出其完整參數列範圍，檢查範圍內是否含 `localizationsDelegates`；白名單只允許 `eb_sheet_shell_test.dart` 剛好殘留 1 處（Global Constraints 白名單例外，見上）：

在 `app/` 目錄下建立暫時性腳本 `tool/_check_bare_material_app.js`（驗收用，不需納入版控——若要保留供未來重複使用，可另外評估併入 Issue 10 的稽核腳本範圍，本 Task 僅作一次性驗收）：
```js
const fs = require('fs');
const path = require('path');

function walk(dir, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith('.dart')) out.push(full);
  }
}

function findMatchingParen(content, openIndex) {
  let depth = 0;
  for (let i = openIndex; i < content.length; i++) {
    if (content[i] === '(') depth++;
    else if (content[i] === ')') {
      depth--;
      if (depth === 0) return i;
    }
  }
  return content.length - 1;
}

const files = [];
walk('test', files);

const WHITELIST_ONE_BARE = path.join('test', 'screens', 'widgets', 'eb_sheet_shell_test.dart');

const violations = [];
for (const file of files) {
  const content = fs.readFileSync(file, 'utf8');
  const regex = /(?:const\s+)?MaterialApp\s*\(/g;
  let match;
  const bareIndices = [];
  while ((match = regex.exec(content)) !== null) {
    const openParenIndex = regex.lastIndex - 1; // 最後一個字元就是 '('
    const closeParenIndex = findMatchingParen(content, openParenIndex);
    const span = content.slice(openParenIndex, closeParenIndex + 1);
    if (!span.includes('localizationsDelegates')) {
      bareIndices.push(match.index);
    }
  }
  const relPath = path.relative('.', file);
  if (relPath === WHITELIST_ONE_BARE) {
    if (bareIndices.length !== 1) {
      violations.push(`${relPath}: 預期恰好 1 處合法 fallback 裸 MaterialApp，實際 ${bareIndices.length} 處`);
    }
    continue;
  }
  if (bareIndices.length > 0) {
    violations.push(`${relPath}: ${bareIndices.length} 處裸 MaterialApp（索引 ${bareIndices.join(', ')}）`);
  }
}

if (violations.length > 0) {
  console.error('發現裸 MaterialApp 殘留：');
  violations.forEach((v) => console.error('  ' + v));
  process.exit(1);
} else {
  console.log('PASS：除 eb_sheet_shell_test.dart 刻意保留的 1 處 fallback 測試外，零殘留裸 MaterialApp');
}
```

Run（於 `app/` 目錄下執行）：`node tool/_check_bare_material_app.js`
Expected：輸出 `PASS：除 eb_sheet_shell_test.dart 刻意保留的 1 處 fallback 測試外，零殘留裸 MaterialApp`，exit code 0。

驗收完成後刪除此暫時性腳本（非本 Issue 正式交付物，Issue 10 稽核腳本若需要類似邏輯會另行設計）：
```bash
rm tool/_check_bare_material_app.js
```

- [ ] **Step 4：更新 `issues.md` Issue 9 段落**

在 `docs/epics/epic-45-interface-i18n/issues.md` Issue 9 段落（`## Issue 9：...`）的 `**Status:**` 改為 `completed`，並在「依賴」之後、「背景」之前插入一段「實際執行範圍修正記錄」，內容比照本計畫 Global Constraints 記載的 25 個檔案清單與 148 處出現次數統計（含 `review-plan-issue-9.md` I-1 修正補記歸屬的 `pdf_reader_view_test.dart`／`foliate_reader_view_test.dart`／`reader_screen_test.dart`／`eb_sheet_shell_test.dart` 4 個檔案），並記錄 `eb_sheet_shell_test.dart:82` 刻意保留 1 處裸 `MaterialApp` fallback 測試不遷移、`locale_switch_test.dart` 是全新建立（非補完既有檔案）。

- [ ] **Step 5：更新 `epic.md`**

在 `docs/epics/epic-45-interface-i18n/epic.md` 末尾新增一則開發記錄段落（格式比照既有 Issue 完成記錄），內容涵蓋：25 個檔案 148 處 `MaterialApp(` 補上在地化參數（含計畫審查 `review-plan-issue-9.md` I-1 抓出的檔案級盤點盲區與後續補記歸屬的 4 個檔案）、`eb_sheet_shell_test.dart` 白名單例外、`locale_switch_test.dart` 新增內容與驗證結果（含 `zh_TW`/`zh_CN`/`en` 三語言閉環）、`flutter analyze`／`flutter test` 結果、下一步建議（認領 Issue 10：防遺漏稽核腳本）。

- [ ] **Step 6：Commit**

```bash
git add docs/epics/epic-45-interface-i18n/issues.md docs/epics/epic-45-interface-i18n/epic.md
git commit -m "docs(epic-45): 標記 Issue 9 為 completed，記錄實際執行範圍並更新 epic.md"
```
