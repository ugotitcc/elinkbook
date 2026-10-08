# Issue 10：`BookReaderPrefs` 整列重建全欄位保留守衛 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:executing-plans` 逐 Task 執行本計畫（延續 Issue 12／13／14「嚴禁 subagent」的做法，不要用 `subagent-driven-development`；若使用者改變主意，以使用者當下指示為準）。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 讓「整列重建 `BookReaderPrefs`」的每一處，在新增欄位而漏帶時**測試會失敗**（現況是編譯器不報錯、使用者設定被靜默清空）；做法是一份「33 個欄位全部填滿」的種子，加上逐欄位比對的守衛。

**Architecture：** 測試優先。新增 `test/support/full_book_reader_prefs.dart`（種子 `fullBookReaderPrefsSeed` ＋ 比對函式 `expectPrefsPreserved`），再對 4 個整列重建點各補一個守衛測試：書架版面覆寫 `_save()`、`FxlSettingsSheet`、`PdfSettingsSheet`、`ReaderSettingsSheet`。`PdfSettingsSheet` 目前實際會丟掉欄位（見下方「已查證的事實」），其守衛預期先紅；修法是改用 `widget.prefs.copyWith(...)`（該面板送出的欄位全是非 null，不需要清空語意），是否納入本 Issue 見附錄 A Q2。最後用變異驗證（刻意漏帶一個欄位）證明每道守衛真的會紅。

**Tech Stack：** Flutter／Dart、`flutter_test`。指令一律在 `app/` 目錄下執行，以 **Bash 工具（Git Bash）** 為準。

**Spec：** `docs/epics/epic-54-architecture-optimization/issues.md` 第 10 列；`epic.md`「2026-10-03 新增 Issue 10」；來源為 `epic-57-layout-override-save-drops-fields` 程式審查 M-1（epic-56、epic-57 已各自漏帶一次）。模型定義見 `app/lib/reader/book_reader_prefs.dart`。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **不改既有測試**：既有測試一字不動，新測試以新增方式附加；不得為了通過而改弱斷言、加 `skip`。
- **`lib/` 異動範圍**：預設只允許改 `app/lib/screens/pdf_settings_sheet.dart` 的 `_notifyChanged()`（且僅在附錄 A Q2 答「納入」時）。其餘 `lib/` 檔案最終 diff 必須為空；變異驗證（Task 6）暫改的檔案必須全數還原、不得 commit。
- **不改 `BookReaderPrefs` 模型**：不動 `copyWith` 簽章、不加 Sentinel（理由與替代方案見附錄 A Q1）。
- **比對方式**：一律用 `toMap()` 的欄位名逐一比對並在失敗訊息列出欄位名，不用整物件 `==`（整物件不相等時看不出是哪個欄位）。
- **測試範圍**（`CLAUDE.md`）：單一 Task 只跑該 Task 觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（`run_in_background`，在 `app/` 下）。
- **提交前**：`flutter analyze` 必須 "No issues found!"；改了測試後跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Windows 環境**：多數原始檔是 CRLF，`Edit` 的定位字串不要含換行。提交一律明確路徑 `git add`。Commit 結尾須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：本計畫先審查再動手；程式審查先出報告（存 `reviews/`），審查者不直接改程式。實作在獨立 worktree（Task 0 建立）；PR 合併後的進度同步（`issues.md` 第 10 列、`epic.md`、`docs/epics.md`）才在 `main` 直接 commit＋push。

## 已查證的事實（撰寫計畫時對照 `lib/` 與 `test/` 所得，執行者開工前須再確認一次）

### `BookReaderPrefs` 共 33 個欄位

`toMap()` 輸出 34 個鍵（含 `book_id`）。`lib/` 內「整列字面量建構」共 4 處，加模型自己的 `copyWith`／`reflowableEpubFields`／`fromMap`（模型內部，不在本守衛範圍，已有 `book_reader_prefs_test.dart` 覆蓋）：

| # | 位置 | 現況 | 風險 |
|---|---|---|---|
| S1 | `screens/library_screen.dart:1922` `_LayoutOverrideDialog._save()` | 逐一列出 33 個欄位，2 個取本地狀態（`writingModeOverride`、`pageTurnModeOverride`），31 個取 `existing`。**現在完整**。需要整列重建是因為「使用預設」要把欄位清成 `null`，`copyWith` 做不到 | 日後新增欄位漏帶 → 儲存版面覆寫時靜默清空（epic-56、epic-57 各發生一次） |
| S2 | `screens/fxl_settings_sheet.dart:66` `_notifyChanged()` | 逐一列出 33 個欄位，5 個取本地狀態＋`textConversionOverride`。**現在完整**。同樣因為簡繁轉換要能清回 `null` | 同上 |
| S3 | `screens/pdf_settings_sheet.dart:91` `_notifyChanged()` | **只帶 13 個欄位**（`pdfFitMode`…`fullscreen`），其餘 20 個欄位（`fontFamily`、4 個邊距、`pageTurnModeOverride`、`writingModeOverride`、`screenOrientationOverride`、`textConversionOverride`、`showHeader`、`columnMode`…）被丟掉。註解假設「同一本書不會同時是 EPUB 又是 PDF，未追蹤的 EPUB 欄位維持 null」 | 假設不成立：書架「版面覆寫」對任何格式的書都可開（`library_screen_test.dart:5293` 的 epic-56 回歸測試用的正是 PDF 翻頁模式），使用者在書架對 PDF 書設了 `pageTurnModeOverride`／`writingModeOverride` 後，進閱讀器開 PDF 設定面板任一操作，這些覆寫就被清成 `null`。`ReaderScreen._handlePrefsChanged`（`reader_screen.dart:757`）把收到的整列直接 `saveBookPrefs` |
| S4 | `screens/reader_settings_sheet.dart:208` `_currentDraft` | 只帶流式 EPUB 的 21 個欄位，丟掉 `pageMargins`、8 個 `pdf*`、3 個 `dualPage*` 共 12 個。這是 epic-28 Issue 3 的刻意設計（欄位污染防護，與 `reflowableEpubFields()` 同集合） | 21 個欄位若漏帶就被清空；12 個被丟的欄位是設計 |

另：`LayoutPreset` 套用（`saveMultiple`）是「整列覆寫」，`reader_settings_sheet.dart:196-207` 的註解已說明為既有設計，**不在本 Issue 範圍**。

### 現有守衛的缺口

`library_screen_test.dart:5293、5332、5374` 三個測試各自只抽查 1～3 個欄位（`pdfPageTurnMode`、`textConversionOverride`、`fontSize`／`marginTop`）。這正是 epic-56、epic-57 的做法——**每次出事後補抽查那一個欄位**，下一個新欄位照樣可以漏。S2、S3、S4 目前完全沒有「其他欄位原樣保留」的測試（`fxl_settings_sheet_test.dart` 只有「不清空 dualPageMode」之類單欄位斷言）。

### 測試素材（皆已存在）

| 項目 | 事實 | 出處 |
|---|---|---|
| 假儲存庫 | `FakeBookReaderPrefsRepository`：`save` 整列覆寫、`load` 沒有則回 `BookReaderPrefs.empty` | `test/support/fake_book_reader_prefs_repository.dart` |
| 書架版面覆寫測試骨架 | `_testBook(id:, title:)`、`FakeLibraryRepository(initialBooks:)`、`pumpLocalizedWidget`、`fakeAppearanceDependencies()`、`fakeSourceDependencies()`、`fakeReaderFeatureDependencies(... bookReaderPrefsRepository:)`；Key：`book_action_menu_1`、`book_action_layout_override`、`layout_override_writing_mode_default`、`layout_override_page_turn_mode_scroll`、`layout_override_save_button` | `library_screen_test.dart:5293-5440` |
| `FxlSettingsSheet` | 建構子 `prefs`／`onChanged`／`isEinkMode`／`showTextConversion = true`；Key：`fxl_settings_fullscreen`、`fxl_settings_show_header`、`fxl_settings_show_footer`、`fxl_settings_dual_page_mode_{auto,always,never}`、`fxl_settings_direction_*`、`fxl_settings_text_conversion_{global,original,traditional,simplified}`；每次操作立即 `onChanged` 回報整列 | `fxl_settings_sheet.dart`、`fxl_settings_sheet_test.dart` |
| `PdfSettingsSheet` | 測試 helper `_pumpSheet(tester, prefs, onChanged)`（檔尾）；Key：`pdf_settings_fullscreen`、`pdf_settings_show_footer`、`pdf_settings_dual_page_cover_alone`；點之前需 `tester.ensureVisible(find.byKey(...))` | `pdf_settings_sheet_test.dart:590-640、1218-1241` |
| `ReaderSettingsSheet` | 測試 helper `_pumpSheet(tester, prefs, onChanged)`（檔內，已設大 viewport）；`switchToTab(tester, '呈現')` 後有 `reader_settings_fullscreen`、`reader_settings_show_footer` | `reader_settings_sheet_test.dart:2477、2622`、`reader_settings_sheet.dart:547、570` |
| 滑桿換算 | `ReaderSettingsSheet` 的 `fontSize`（×16 取整再 ÷16）與 `paragraphSpacing`（×10 取整再 ÷10）有換算；種子值必須選能無損來回的數（`fontSize: 1.5`→24→1.5；`paragraphSpacing: 1.2`→12→1.2） | `reader_settings_sheet.dart:120-132、192-194` |

## Review Focus

最可能咬到使用者（或讓守衛形同虛設）的情況，依可能性排序：

1. **新增欄位只加進模型、`toMap` 與種子，卻漏在某個整列重建點帶回。**使用者會看到「在書架調整排版方向後，之前設的字型／邊距消失」。→ 種子 33 欄位全非 null，4 個重建點各有一個逐欄位守衛；Task 6 變異驗證用「刪掉一行帶回」證明會紅。
2. **新欄位忘了加進種子，守衛對它形同虛設。**→ Task 1 的自檢測試：`fullBookReaderPrefsSeed.toMap()` 任一值為 `null` 即失敗（新欄位進了 `toMap` 但種子沒填 → 紅）。
3. **種子值剛好等於面板預設值，使「被重設成預設」測不出來。**→ 種子刻意全取「非預設」值（例如 `publisherStyles: false`、`columnMode: double`、`dualPageDirection: ltr`、`pdfPageTurnMode: scroll`）。Task 1 自檢列出對照表。
4. **PDF 面板丟欄位**（S3）：使用者實際會遇到的既有缺陷。→ Task 4 先寫守衛看它紅，再決定修（附錄 A Q2）。
5. **守衛假陽性**：`expectPrefsPreserved` 的 `except` 寫了不存在的欄位名而默默放行。→ helper 先驗證 `except` 全是 `toMap()` 的鍵。

---

## 檔案結構

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/test/support/full_book_reader_prefs.dart` | 新增 | `fullBookReaderPrefsSeed`（33 欄位全填）＋ `expectPrefsPreserved(actual, expected, {except})` |
| `app/test/reader/book_reader_prefs_test.dart` | 修改（檔尾新增一個 `group`，3 個測試） | 種子自檢：全非 null、round-trip、`copyWith()` 等價 |
| `app/test/screens/library_screen_test.dart` | 修改（在 `:5440` 之後新增 1 個測試，加 1 行 import） | S1 守衛 |
| `app/test/screens/fxl_settings_sheet_test.dart` | 修改（檔尾新增 1 個 `group`） | S2 守衛 |
| `app/test/screens/pdf_settings_sheet_test.dart` | 修改（`main()` 尾端新增 1 個 `group`） | S3 守衛 |
| `app/lib/screens/pdf_settings_sheet.dart` | 修改（僅 Q2 答「納入」） | `_notifyChanged()` 改 `widget.prefs.copyWith(...)` |
| `app/test/screens/reader_settings_sheet_test.dart` | 修改（`main()` 尾端新增 1 個 `group`） | S4 守衛 |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 進度與歷程同步 |

---

### Task 0：建立基準、worktree 與取得設計決定

**Files:** 無程式修改。

- [x] **Step 1：確認起點乾淨**

在 repo 根目錄執行：

```bash
git status --short
git log -1 --oneline
git branch --show-current
```

預期：無未提交變更、目前在 `main`、與 `origin/main` 同步（`git fetch && git status -sb`）。

- [x] **Step 2：取得附錄 A 的使用者決定（Q1、Q2），把原話填進附錄 A**

兩題都有建議預設，但**沒有使用者回覆前不得開始 Task 1 以後的實作**。

- [x] **Step 3：建立 worktree**

```bash
git worktree add .worktrees/epic-54-issue-10 -b epic-54-issue-10
cd .worktrees/epic-54-issue-10/app && flutter pub get
```

之後所有指令都在 `.worktrees/epic-54-issue-10/app/` 下執行。

- [x] **Step 4：跑基準（異動將觸及的 5 個測試檔）**

```bash
flutter test test/reader/book_reader_prefs_test.dart test/screens/fxl_settings_sheet_test.dart test/screens/pdf_settings_sheet_test.dart test/screens/reader_settings_sheet_test.dart
flutter test test/screens/library_screen_test.dart --plain-name "版面覆寫"
```

預期：全數通過。把「通過案例數」填進附錄 C 的基準欄。若有失敗，先停下回報，不要帶著紅燈開工。

- [x] **Step 5：複核「已查證的事實」**

```bash
git grep -n "BookReaderPrefs(" -- lib
```

預期恰好 9 筆：`book_reader_prefs.dart` 內 5 筆（建構子宣告、`empty`、`fromMap`、`copyWith`、`reflowableEpubFields`）＋ S1～S4 共 4 筆。若數量不同，代表上方表格過期，停下回報。

---

### Task 1：種子與比對函式（含種子自檢）

**Files:**
- Create: `app/test/support/full_book_reader_prefs.dart`
- Modify: `app/test/reader/book_reader_prefs_test.dart`（檔尾新增 group；補 import `../support/full_book_reader_prefs.dart`）

**Interfaces:**
- Produces: `const BookReaderPrefs fullBookReaderPrefsSeed`；`void expectPrefsPreserved(BookReaderPrefs? actual, BookReaderPrefs expected, {Set<String> except = const {}})`。`except` 內放 `toMap()` 的欄位名（snake_case，如 `'writing_mode_override'`）。
- Consumes: `BookReaderPrefs.toMap(String)`。

- [x] **Step 1：先寫自檢測試（紅）**

在 `book_reader_prefs_test.dart` 的 import 區加：

```dart
import '../support/full_book_reader_prefs.dart';
```

在 `main()` 結尾（最後一個 `}` 之前）新增：

```dart
  group('fullBookReaderPrefsSeed 種子自檢（Issue 10：新增欄位漏填種子時要在這裡紅）', () {
    test('toMap 的 33 個欄位值全部非 null', () {
      final map = fullBookReaderPrefsSeed.toMap('seed');
      final nullKeys = [
        for (final e in map.entries)
          if (e.value == null) e.key,
      ];
      expect(
        nullKeys,
        isEmpty,
        reason: '種子必須填滿每個欄位，否則該欄位的「漏帶」守衛形同虛設；'
            '新增欄位時請同步補進 fullBookReaderPrefsSeed。未填：$nullKeys',
      );
      expect(map.length, 34, reason: '33 個欄位 ＋ book_id');
    });

    test('toMap／fromMap round-trip 後與種子相等', () {
      final restored =
          BookReaderPrefs.fromMap(fullBookReaderPrefsSeed.toMap('seed'));
      expect(restored, fullBookReaderPrefsSeed);
    });

    test('copyWith() 不傳參數時與種子相等（33 個欄位皆被帶回）', () {
      expect(fullBookReaderPrefsSeed.copyWith(), fullBookReaderPrefsSeed);
    });
  });
```

- [x] **Step 2：跑測試確認紅**

```bash
flutter test test/reader/book_reader_prefs_test.dart
```

預期：編譯失敗（找不到 `../support/full_book_reader_prefs.dart`）。

- [x] **Step 3：建立種子與比對函式**

建立 `app/test/support/full_book_reader_prefs.dart`：

```dart
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/column_mode.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_page_turn_animation.dart';
import 'package:elinkbook/reader/pdf_page_turn_mode.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:flutter_test/flutter_test.dart';

/// 33 個欄位全部填滿的 [BookReaderPrefs]（Issue 10「整列重建全欄位保留守衛」）。
///
/// 每個值都刻意取「與各面板預設值不同」的選項（例如 publisherStyles 預設
/// true 這裡是 false、columnMode 預設 auto 這裡是 double），這樣「漏帶後被
/// 重設成預設」也會被抓到，不會因為剛好等於預設值而漏判。
///
/// 數值也要能被 ReaderSettingsSheet 的滑桿換算無損來回：fontSize 1.5
/// （×16＝24，再 ÷16 回 1.5）、paragraphSpacing 1.2（×10＝12，再 ÷10 回 1.2）。
///
/// 新增 [BookReaderPrefs] 欄位時必須同步補進這裡，否則 book_reader_prefs_test
/// 的「種子自檢」會失敗。
const fullBookReaderPrefsSeed = BookReaderPrefs(
  fontFamily: 'SourceHanSerifTC',
  fontSize: 1.5,
  fontWeight: 1.25,
  lineHeight: 1.8,
  paragraphSpacing: 1.2,
  letterSpacing: 0.05,
  pageMargins: 20,
  marginTop: 40,
  marginBottom: 20,
  marginLeft: 28,
  marginRight: 28,
  textAlign: EpubTextAlign.justify,
  publisherStyles: false,
  writingModeOverride: WritingMode.vertical,
  pageTurnModeOverride: PageTurnMode.paginated,
  screenOrientationOverride: ScreenOrientationSetting.lock90,
  pdfFitMode: PdfFitMode.fitWidth,
  pdfContrast: 20,
  pdfBrightness: -10,
  pdfBoldStrength: 0.5,
  pdfCropMode: PdfCropMode.manual,
  pdfCropRect: PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
  dualPageMode: DualPageMode.always,
  dualPageCoverAlone: false,
  dualPageDirection: DualPageDirection.ltr,
  pdfPageTurnAnimation: PdfPageTurnAnimation.none,
  pdfPageTurnMode: PdfPageTurnMode.scroll,
  showHeader: true,
  showFooter: true,
  columnMode: ColumnMode.double,
  columnSize: 800,
  fullscreen: true,
  textConversionOverride: TextConversionMode.toTraditional,
);

/// 逐欄位比對 [actual] 與 [expected]，只有 [except] 內的欄位（`toMap()` 的
/// 欄位名，snake_case）允許不同；其他欄位只要有一個不同就失敗，並在訊息列出
/// 欄位名與前後值。
///
/// 用 `toMap()` 比對而不是整物件 `==`：整物件不相等時看不出是哪個欄位被丟。
void expectPrefsPreserved(
  BookReaderPrefs? actual,
  BookReaderPrefs expected, {
  Set<String> except = const {},
}) {
  // actual 接受 nullable：呼叫端多半是 onChanged 的捕捉變數，Dart 不會因為
  // expect(x, isNotNull) 而收窄型別，統一在這裡檢查比較不易漏。
  expect(actual, isNotNull, reason: 'onChanged／儲存庫沒有收到任何 prefs');
  final actualMap = actual!.toMap('b');
  final expectedMap = expected.toMap('b');
  // 防假陽性：except 寫錯欄位名會讓比對默默放行。
  expect(
    expectedMap.keys,
    containsAll(except),
    reason: 'except 內有不存在於 toMap() 的欄位名',
  );
  final diffs = <String>[
    for (final key in expectedMap.keys)
      if (!except.contains(key) && actualMap[key] != expectedMap[key])
        '$key：預期 ${expectedMap[key]}，實際 ${actualMap[key]}',
  ];
  expect(
    diffs,
    isEmpty,
    reason: '下列欄位被改動或清空（整列重建漏帶欄位）：\n${diffs.join('\n')}',
  );
}
```

- [x] **Step 4：跑測試確認綠**

```bash
flutter test test/reader/book_reader_prefs_test.dart
```

預期：全數通過（含新增 3 個）。若 `toMap` 長度不是 34，代表模型欄位數已變，回頭修正計畫與種子。

- [x] **Step 5：analyze 與 Commit**

```bash
flutter analyze
git add test/support/full_book_reader_prefs.dart test/reader/book_reader_prefs_test.dart
git commit -m "test(epic-54): Issue 10 BookReaderPrefs 33 欄位種子與逐欄位比對函式" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2：S1 書架版面覆寫 `_save()` 守衛

**Files:**
- Modify: `app/test/screens/library_screen_test.dart`（在 `:5440` 現有第三個版面覆寫測試之後新增 1 個測試；import 區加 `../support/full_book_reader_prefs.dart`，依檔內既有 import 排序放置）

**Interfaces:**
- Consumes: `fullBookReaderPrefsSeed`、`expectPrefsPreserved`（Task 1）。

- [x] **Step 1：寫守衛測試**

```dart
  testWidgets(
    '版面覆寫：種子 33 欄位全填，儲存後除 writingModeOverride／pageTurnModeOverride 外'
    '全數原樣相等（Issue 10 全欄位保留守衛）',
    (tester) async {
      final book = _testBook(id: '1', title: '書A');
      final repository = FakeLibraryRepository(initialBooks: [book]);
      final bookReaderPrefsRepository = FakeBookReaderPrefsRepository();
      await bookReaderPrefsRepository.save('1', fullBookReaderPrefsSeed);
      await pumpLocalizedWidget(
        tester,
        LibraryScreen(
          appearance: fakeAppearanceDependencies(),
          sources: fakeSourceDependencies(),
          dependencies: fakeReaderFeatureDependencies(
            libraryRepository: repository,
            bookImportService: FakeBookImportService(),
            prefsManager: prefsManager,
            bookReaderPrefsRepository: bookReaderPrefsRepository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book_action_menu_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book_action_layout_override')));
      await tester.pumpAndSettle();
      // 種子的 writingModeOverride 是 vertical：選「使用預設」要清成 null；
      // pageTurnModeOverride 是 paginated：改成 scroll。
      await tester.tap(
        find.byKey(const Key('layout_override_writing_mode_default')),
      );
      await tester.tap(
        find.byKey(const Key('layout_override_page_turn_mode_scroll')),
      );
      await tester.tap(find.byKey(const Key('layout_override_save_button')));
      await tester.pumpAndSettle();

      final saved = await bookReaderPrefsRepository.load('1');
      expect(saved.writingModeOverride, isNull);
      expect(saved.pageTurnModeOverride, PageTurnMode.scroll);
      expectPrefsPreserved(
        saved,
        fullBookReaderPrefsSeed,
        except: {'writing_mode_override', 'page_turn_mode_override'},
      );
    },
  );
```

- [x] **Step 2：跑測試**

```bash
flutter test test/screens/library_screen_test.dart --plain-name "版面覆寫"
```

預期：通過（S1 現況完整，這是回歸守衛，不是紅燈起點；紅燈由 Task 6 變異驗證證明）。若紅，訊息會列出被丟的欄位——代表發現新缺陷，停下回報。

- [x] **Step 3：Commit**

```bash
flutter analyze
git add test/screens/library_screen_test.dart
git commit -m "test(epic-54): Issue 10 書架版面覆寫儲存全欄位保留守衛" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：S2 `FxlSettingsSheet` 守衛

**Files:**
- Modify: `app/test/screens/fxl_settings_sheet_test.dart`（檔尾新增 group；補 import `../support/full_book_reader_prefs.dart`；`dual_page_mode`／`text_conversion_mode` 等 import 檔內已有）

**Interfaces:**
- Consumes: `fullBookReaderPrefsSeed`、`expectPrefsPreserved`。

- [x] **Step 1：寫守衛測試**

在檔尾新增（沿用檔內 `MaterialApp` 包裝寫法）：

```dart
Future<BookReaderPrefs?> _tapAndCapture(
  WidgetTester tester,
  String keyName,
) async {
  BookReaderPrefs? changed;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: FxlSettingsSheet(
            prefs: fullBookReaderPrefsSeed,
            onChanged: (prefs) => changed = prefs,
            isEinkMode: false,
          ),
        ),
      ),
    ),
  );
  await tester.ensureVisible(find.byKey(Key(keyName)));
  await tester.tap(find.byKey(Key(keyName)));
  await tester.pump();
  return changed;
}

void _fxlFullFieldGuardTests() {
  group('全欄位保留守衛（Issue 10）：種子 33 欄位，操作一個控制項後只有該欄位改變', () {
    testWidgets('切換全螢幕 → 只有 fullscreen 改變', (tester) async {
      final changed = await _tapAndCapture(tester, 'fxl_settings_fullscreen');
      expect(changed, isNotNull);
      expect(changed!.fullscreen, isFalse);
      expectPrefsPreserved(changed, fullBookReaderPrefsSeed,
          except: {'fullscreen'});
    });

    testWidgets('切換雙頁模式為「永遠單頁」→ 只有 dual_page_mode 改變', (tester) async {
      final changed =
          await _tapAndCapture(tester, 'fxl_settings_dual_page_mode_never');
      expect(changed, isNotNull);
      expect(changed!.dualPageMode, DualPageMode.never);
      expectPrefsPreserved(changed, fullBookReaderPrefsSeed,
          except: {'dual_page_mode'});
    });

    testWidgets('簡繁轉換選「使用全域預設」→ 只有 text_conversion_override 清成 null',
        (tester) async {
      final changed =
          await _tapAndCapture(tester, 'fxl_settings_text_conversion_global');
      expect(changed, isNotNull);
      expect(changed!.textConversionOverride, isNull);
      expectPrefsPreserved(changed, fullBookReaderPrefsSeed,
          except: {'text_conversion_override'});
    });
  });
}
```

並在 `main()` 尾端（最後一個 `}` 之前）加一行呼叫 `_fxlFullFieldGuardTests();`。

注意：`fxl_settings_sheet_test.dart` 現有的 `showHeader`／`showFooter` 開關預設值是 `false`，種子是 `true`，面板的本地狀態以 `?? false` 初始化——種子是非 null，所以初始值取種子值，不會被洗成預設。

- [x] **Step 2：跑測試**

```bash
flutter test test/screens/fxl_settings_sheet_test.dart
```

預期：全數通過（含新增 3 個）。若 `ensureVisible` 找不到 widget（面板內容超出預設視窗），把 `SingleChildScrollView` 外層改成 `tester.view.physicalSize = const Size(800, 2400)`（比照 `reader_settings_sheet_test.dart:2495-2500`，含 `addTearDown` 還原）。

- [x] **Step 3：Commit**

```bash
flutter analyze
git add test/screens/fxl_settings_sheet_test.dart
git commit -m "test(epic-54): Issue 10 FxlSettingsSheet 全欄位保留守衛" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4：S3 `PdfSettingsSheet` 守衛（預期先紅）與修正

**Files:**
- Modify: `app/test/screens/pdf_settings_sheet_test.dart`（`main()` 尾端新增 group；補 import `../support/full_book_reader_prefs.dart`）
- Modify: `app/lib/screens/pdf_settings_sheet.dart`（僅附錄 A Q2 答「納入」）

**Interfaces:**
- Consumes: `fullBookReaderPrefsSeed`、`expectPrefsPreserved`、檔內既有 `_pumpSheet(tester, prefs, onChanged)`。

- [ ] **Step 1：寫守衛測試**

在 `main()` 結尾（最後一個 `}` 之前）新增：

```dart
  group('全欄位保留守衛（Issue 10）：種子 33 欄位，操作一個控制項後只有該欄位改變', () {
    Future<BookReaderPrefs?> tapAndCapture(
      WidgetTester tester,
      String keyName,
    ) async {
      BookReaderPrefs? notified;
      await _pumpSheet(
        tester,
        fullBookReaderPrefsSeed,
        (prefs) => notified = prefs,
      );
      await tester.ensureVisible(find.byKey(Key(keyName)));
      await tester.tap(find.byKey(Key(keyName)));
      await tester.pump();
      return notified;
    }

    testWidgets('切換全螢幕 → 只有 fullscreen 改變', (tester) async {
      final notified = await tapAndCapture(tester, 'pdf_settings_fullscreen');
      expect(notified, isNotNull);
      expect(notified!.fullscreen, isFalse);
      expectPrefsPreserved(notified, fullBookReaderPrefsSeed,
          except: {'fullscreen'});
    });

    testWidgets('切換頁尾顯示 → 只有 show_footer 改變', (tester) async {
      final notified = await tapAndCapture(tester, 'pdf_settings_show_footer');
      expect(notified, isNotNull);
      expect(notified!.showFooter, isFalse);
      expectPrefsPreserved(notified, fullBookReaderPrefsSeed,
          except: {'show_footer'});
    });

    testWidgets('切換封面獨立 → 只有 dual_page_cover_alone 改變', (tester) async {
      final notified =
          await tapAndCapture(tester, 'pdf_settings_dual_page_cover_alone');
      expect(notified, isNotNull);
      expect(notified!.dualPageCoverAlone, isTrue);
      expectPrefsPreserved(notified, fullBookReaderPrefsSeed,
          except: {'dual_page_cover_alone'});
    });
  });
```

- [ ] **Step 2：跑測試確認紅，並記錄被丟的欄位**

```bash
flutter test test/screens/pdf_settings_sheet_test.dart --plain-name "全欄位保留守衛"
```

預期：3 個全紅，失敗訊息列出被清成 `null` 的欄位，應包含：`font_family`、`font_size`、`font_weight`、`line_height`、`paragraph_spacing`、`letter_spacing`、`page_margins`、4 個 `margin_*`、`text_align`、`publisher_styles`、`writing_mode_override`、`page_turn_mode_override`、`screen_orientation_override`、`show_header`、`column_mode`、`column_size`、`text_conversion_override`（共 20 個）。把實際輸出貼進附錄 C。**若實際沒有紅**，代表 S3 的描述有誤，停下回報，不要硬改。

- [ ] **Step 3：（依 Q2）修正 `_notifyChanged()`**

若附錄 A Q2 答「不納入」：跳過本步驟，把 3 個守衛測試加上 `skip: 'Issue 10 Q2：PDF 面板丟欄位另立工單，見 issues.md 第 N 列'`（N 為新工單編號，先登錄再 skip；**不得無 skip 帶紅燈提交**），並在 `issues.md` 登錄新工單。

若答「納入」：把 `app/lib/screens/pdf_settings_sheet.dart` 的 `_notifyChanged()` 改為：

```dart
  void _notifyChanged() {
    // Issue 10：以 widget.prefs 為底、只覆寫本面板追蹤的欄位，其餘欄位（EPUB
    // 版面、書架「版面覆寫」設的排版方向／翻頁方式等）原樣保留。本面板送出的
    // 欄位全是非 null，不需要「清回 null」的語意，所以用 copyWith 即可。
    // pdfCropRect 由原生端計算、經 ReaderScreen.onCropRectComputed 另一條路徑
    // 寫入，本分頁不控制，copyWith 不傳即原樣保留。
    widget.onChanged(
      widget.prefs.copyWith(
        pdfFitMode: _fitMode,
        pdfContrast: _contrast,
        pdfBrightness: _brightness,
        pdfBoldStrength: _boldStrength / 100,
        pdfCropMode: _cropMode,
        dualPageMode: _dualPageMode,
        dualPageCoverAlone: _dualPageCoverAlone,
        dualPageDirection: _dualPageDirection,
        pdfPageTurnAnimation: _pageTurnAnimation,
        pdfPageTurnMode: _pageTurnMode,
        showFooter: _showFooter,
        fullscreen: _fullscreen,
      ),
    );
  }
```

同時把類別文件註解（約 `:20-23`）中「未追蹤的 EPUB 欄位維持 null 不影響實際使用情境」那句改為「其餘欄位以 `widget.prefs` 為底原樣保留」。

- [ ] **Step 4：跑 PDF 面板全檔與依賴它的閱讀器測試**

```bash
flutter test test/screens/pdf_settings_sheet_test.dart
flutter test test/screens/reader_screen_test.dart --plain-name "PDF"
```

預期：全數通過。**既有測試若有因為「onChanged 帶出的 prefs 現在含其他欄位」而紅的**（例如以 `==` 比對整物件預期其他欄位為 null），逐一檢查：若測試的前提是「其他欄位為 null」且 `widget.prefs` 本來就是 `empty`，則不受影響；若真有受影響者，停下回報，不要改弱斷言。

- [ ] **Step 5：Commit**

```bash
flutter analyze
git add test/screens/pdf_settings_sheet_test.dart lib/screens/pdf_settings_sheet.dart
git commit -m "fix(epic-54): Issue 10 PdfSettingsSheet 改以 copyWith 保留其他欄位並補全欄位保留守衛" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

（Q2 答「不納入」時，只 `git add` 測試檔，commit 訊息改為 `test(epic-54): Issue 10 PdfSettingsSheet 全欄位保留守衛（skip，另立工單）`。）

---

### Task 5：S4 `ReaderSettingsSheet` 守衛

**Files:**
- Modify: `app/test/screens/reader_settings_sheet_test.dart`（`main()` 尾端新增 group；補 import `../support/full_book_reader_prefs.dart`）

**Interfaces:**
- Consumes: `fullBookReaderPrefsSeed`、`expectPrefsPreserved`、檔內既有 `_pumpSheet`、`switchToTab`。
- 預期值：`fullBookReaderPrefsSeed.reflowableEpubFields()`（21 個欄位保留、12 個清成 null——epic-28 Issue 3 的刻意設計）。

- [ ] **Step 1：寫守衛測試**

```dart
  group('全欄位保留守衛（Issue 10）：種子 33 欄位，操作一個控制項後，21 個流式欄位只有該欄位改變、'
      '其餘 12 個欄位依設計清成 null', () {
    testWidgets('切換全螢幕 → 只有 fullscreen 改變', (tester) async {
      BookReaderPrefs? notified;
      await _pumpSheet(
        tester,
        fullBookReaderPrefsSeed,
        (prefs) => notified = prefs,
      );
      await switchToTab(tester, '呈現');
      await tester.tap(find.byKey(const Key('reader_settings_fullscreen')));
      await tester.pump();

      expect(notified, isNotNull);
      expect(notified!.fullscreen, isFalse);
      // 預期基準 ＝ 種子過濾成流式 EPUB 的 21 個欄位（另 12 個為 null，是設計）。
      expectPrefsPreserved(
        notified!,
        fullBookReaderPrefsSeed.reflowableEpubFields(),
        except: {'fullscreen'},
      );
    });

    testWidgets('切換頁尾顯示 → 只有 show_footer 改變', (tester) async {
      BookReaderPrefs? notified;
      await _pumpSheet(
        tester,
        fullBookReaderPrefsSeed,
        (prefs) => notified = prefs,
      );
      await switchToTab(tester, '呈現');
      await tester.tap(find.byKey(const Key('reader_settings_show_footer')));
      await tester.pump();

      expect(notified, isNotNull);
      expect(notified!.showFooter, isFalse);
      expectPrefsPreserved(
        notified!,
        fullBookReaderPrefsSeed.reflowableEpubFields(),
        except: {'show_footer'},
      );
    });
  });
```

- [ ] **Step 2：跑測試**

```bash
flutter test test/screens/reader_settings_sheet_test.dart --plain-name "全欄位保留守衛"
```

預期：通過。若紅且被丟的是 `font_size`／`paragraph_spacing`，多半是種子值經滑桿換算有浮點差，改選能無損來回的值（並同步改 `full_book_reader_prefs.dart` 與其註解）；若是其他欄位，代表發現新缺陷，停下回報。若 `reader_settings_fullscreen` 在 `呈現` 分頁找不到，參照 `reader_settings_sheet_test.dart` 內既有 fullscreen 測試的切分頁方式。

- [ ] **Step 3：Commit**

```bash
flutter analyze
git add test/screens/reader_settings_sheet_test.dart
git commit -m "test(epic-54): Issue 10 ReaderSettingsSheet 流式欄位全欄位保留守衛" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6：變異驗證、文件同步、完整驗證與程式審查

**Files:**
- 暫改（驗完必須還原）：`lib/screens/library_screen.dart`、`lib/screens/fxl_settings_sheet.dart`、`lib/screens/pdf_settings_sheet.dart`、`lib/screens/reader_settings_sheet.dart`、`test/support/full_book_reader_prefs.dart`
- Modify：`docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md`（進度同步在 PR 合併後於 `main` 做，見 Step 6）

- [ ] **Step 1：變異驗證——證明每道守衛真的會紅**

每個變異：改一處 → 跑對應測試確認紅且訊息指出該欄位 → `git checkout -- <檔案>` 還原 → 跑同一測試確認回綠。

| # | 改動 | 跑 | 預期紅的訊息含 |
|---|---|---|---|
| M1 | `library_screen.dart` 刪掉 `fullscreen: existing.fullscreen,` 該行 | `flutter test test/screens/library_screen_test.dart --plain-name "全欄位保留守衛"` | `fullscreen：預期 1，實際 null` |
| M2 | `library_screen.dart` 刪掉 `columnSize: existing.columnSize,` | 同上 | `column_size` |
| M3 | `fxl_settings_sheet.dart` 刪掉 `columnSize: widget.prefs.columnSize,` | `flutter test test/screens/fxl_settings_sheet_test.dart --plain-name "全欄位保留守衛"` | `column_size` |
| M4 | `pdf_settings_sheet.dart` `_notifyChanged()` 還原成「`BookReaderPrefs(...)` 只帶 13 欄位」的舊寫法（`git stash` 不可用，直接手改後 `git checkout`） | `flutter test test/screens/pdf_settings_sheet_test.dart --plain-name "全欄位保留守衛"` | 20 個欄位名（僅 Q2 納入時做） |
| M5 | `reader_settings_sheet.dart` `_currentDraft` 刪掉 `textConversionOverride: _textConversionOverride,` | `flutter test test/screens/reader_settings_sheet_test.dart --plain-name "全欄位保留守衛"` | `text_conversion_override` |
| M6 | `full_book_reader_prefs.dart` 把 `textConversionOverride: TextConversionMode.toTraditional,` 那行刪掉（模擬「新欄位漏填種子」） | `flutter test test/reader/book_reader_prefs_test.dart --plain-name "種子自檢"` | `text_conversion_override`（`toMap` 值為 null） |

把每個變異的實際紅燈訊息摘要填進附錄 C。全部驗完後：

```bash
git status --short
git diff main --stat -- lib
```

預期：`git status` 乾淨；`lib/` 的 diff 只剩 `lib/screens/pdf_settings_sheet.dart`（Q2 納入）或完全為空（Q2 不納入）。

- [ ] **Step 2：靜態檢查**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```

預期：`No issues found!`；l10n 檢查兩行 PASS。

- [ ] **Step 3：完整測試（只此一次）**

```bash
flutter test
```

用 `run_in_background` 執行；通過後把「N 通過／M 略過／0 失敗」填進附錄 C。

- [ ] **Step 4：文件同步（在分支上）**

`docs/epics/epic-54-architecture-optimization/epic.md` 新增「Issue 10 實作完成」段落（內容：守衛範圍 S1～S4、PDF 面板缺陷與修法〔或另立工單編號〕、變異驗證結果、測試數）。`issues.md` 第 10 列狀態改為 🟡 實作完成待審查。**不要**動 `docs/epics.md`（合併後才改）。

```bash
git add ../docs/epics/epic-54-architecture-optimization/epic.md ../docs/epics/epic-54-architecture-optimization/issues.md ../docs/epics/epic-54-architecture-optimization/plans/plan-issue-10.md
git commit -m "docs(epic-54): Issue 10 實作完成紀錄" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5：程式審查**

交由使用者以 `superpowers:requesting-code-review` 發起（審查者先出報告，存 `reviews/review-code-issue-10.md`，不進版控，不得直接改程式）。

- [ ] **Step 6：PR 合併後（使用者通知後才做）**

切回 `main` 並 pull，`issues.md` 第 10 列改「🟢 已合併（PR #N）」，`epic.md` 補合併紀錄，`docs/epics.md` 第 55 列備註更新；直接 commit＋push `main`；清理 `.worktrees/epic-54-issue-10` 與本機／遠端分支（Windows 下若 `git worktree remove` 報 Permission denied，先 `git worktree prune` 再 PowerShell `Remove-Item -Recurse -Force`）。

---

## 附錄 A：使用者決定紀錄（Task 0 Step 2 取得後填入原話）

**Q1：要不要順手做 `copyWith` 支援明確傳 null（Sentinel）以根除整列重建？**（`issues.md` 第 10 列的「選配」）

- **A（建議）：不做。**只做全欄位保留守衛。理由：Sentinel 要把 `copyWith` 33 個參數全改成 `Object?` 或另加 33 個 `clearXxx` 旗標，失去型別檢查、波及所有 `copyWith` 呼叫點；而守衛測試已能在漏欄位時當場紅燈，達成同樣的保護目的，成本小得多。若日後仍有漏帶，再另立工單。
- B：做。S1、S2 改用 `existing.copyWith(...)`，整列重建從 `lib/` 消失。需要新增計畫 Task（模型改動＋全呼叫點驗證），範圍明顯變大。

**Q2：`PdfSettingsSheet` 丟欄位（S3）是否在本 Issue 修？**

- **A（建議）：納入。**Task 4 先讓守衛紅、再把 `_notifyChanged()` 改成 `widget.prefs.copyWith(...)`，改動約 15 行、風險小（面板送出的欄位全是非 null）。這是使用者實際會遇到的資料遺失，且若不修，守衛測試只能 `skip`，等於留一個已知紅燈。
- B：不納入，另立工單；Task 4 的 3 個守衛加 `skip` 並指向新工單編號。

填寫處：

- Q1：「NO」→ 採 A，不做 Sentinel，只做全欄位保留守衛。
- Q2：「OK」→ 採 A，納入：Task 4 先讓 PDF 面板守衛紅燈，再把 `_notifyChanged()` 改為 `widget.prefs.copyWith(...)`。

## 附錄 B：被刪除的測試清單

無。本 Issue 不刪除任何既有測試。

## 附錄 C：測試數基準與實測紀錄（執行者依實測填入）

| 項目 | 數值 |
|---|---|
| Task 0 基準（`book_reader_prefs`＋`fxl`＋`pdf`＋`reader_settings` 四檔通過數） | 審查者於 `main` 實測 232（執行者開工時仍須自測填入） |
| Task 0 基準（`library_screen_test.dart --plain-name "版面覆寫"`） | 審查者於 `main` 實測 3（同上） |
| 預期新增案例數 | 種子自檢 3＋S1 1＋S2 3＋S3 3＋S4 2 ＝ 12 |
| Task 4 Step 2 PDF 守衛紅燈訊息（被丟欄位清單） | （待填） |
| Task 6 Step 1 變異驗證 M1～M6 實際紅燈訊息 | （待填） |
| Task 6 Step 3 完整 `flutter test` | （待填） |

## Self-Review 結果

- **Spec 涵蓋**：`issues.md` 第 10 列兩項——「全欄位保留守衛（種子填滿 33 欄位，除被覆寫欄位外須原樣相等）」→ Task 1～5；「選配 Sentinel」→ 附錄 A Q1（建議不做，理由已寫明）。
- **Placeholder 掃描**：計畫內可執行步驟皆有完整程式碼或指令；「待填」僅限附錄 A／C 的使用者決定與實測紀錄欄（沿用 Issue 14 慣例）。
- **型別一致**：`fullBookReaderPrefsSeed`、`expectPrefsPreserved(actual, expected, {except})` 在 Task 1 定義，Task 2～5 以同名同簽章使用；`except` 一律用 `toMap()` 的 snake_case 欄位名。
- **Review Focus**：1→Task 2～5＋Task 6 變異；2→Task 1 自檢＋M6；3→種子取非預設值（見 `full_book_reader_prefs.dart` 註解）；4→Task 4；5→`expectPrefsPreserved` 的 `containsAll(except)`。
- **已知限制**：種子自檢只能抓「欄位進了 `toMap` 卻漏填種子」；若有人新增欄位卻**連 `toMap` 都沒加**，由既有 round-trip 測試與 `==`／`hashCode` 覆蓋範圍決定，不在本守衛範圍。
