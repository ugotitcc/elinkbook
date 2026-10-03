# Issue 2：PDF 翻頁模式偏好、設定面板與 SQLite v28 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 新增「PDF 翻頁模式」（逐頁／連續捲動）單書偏好，從資料庫、偏好模型、設定面板一路接到 `ReaderScreen` 與 `PdfReaderView` 的建構參數；**本 Issue 不改變任何渲染行為**（逐頁幾何在 Issue 4）。

**Architecture：** 完全比照既有 `pdf_page_turn_animation` 欄位的作法：新增列舉 `PdfPageTurnMode`；`BookReaderPrefs` 加可為空欄位（`null`＝逐頁）；`ResolvedPreferences` 加非空欄位；`book_reader_prefs` 表以 `ALTER TABLE ... ADD COLUMN` 追加 `pdf_page_turn_mode TEXT`（schema 27→28）；`PdfSettingsSheet`「顯示」分頁加二選一 chip，選逐頁時隱藏「換頁動畫」但不清除其值；三個會「整列重建 `BookReaderPrefs`」的地方都要帶上新欄位。`PdfReaderView` 新增 `pdfPageTurnMode`（widget 層預設連續捲動），`ReaderScreen` 傳入解析後的值，但 widget 內**不讀取**它。

**Tech Stack：** Flutter／Dart、`sqflite`（測試用 `sqflite_common_ffi`）、`flutter_test`、`gen-l10n`（ARB）。指令一律在 `app/` 目錄下執行。

**Spec：** `docs/epics/epic-56-pdf-paginated-reading/spec.md`（「型別與偏好」「設定面板」「`PdfReaderView` 對外介面」；測試接縫 3）；工單見 `issues.md` Issue 2。

## 已查證的現況（本計畫的依據，執行者不必重查，但若不符請停下來回報）

- 最近的範本是 `pdf_page_turn_animation`：`book_reader_prefs.dart`（欄位、`toMap`、`fromMap`、`==`、`hashCode`、`copyWith`）、`resolved_preferences.dart`、`reader_prefs_manager_impl.dart`（`resolve`）、`sqlite_library_repository.dart`（建表 DDL、`onUpgrade` 的 `else` 分支內 `_addPdfPageTurnAnimationColumn`）、`pdf_settings_sheet.dart`、四份 ARB。
- 反序列化一律走 `enumByNameOrNull`，找不到名稱回傳 `null`——「無法辨識的值視為 `null`」不需新機制。
- `BookReaderPrefs` 整列重建的地方（`grep "BookReaderPrefs("`）：`library_screen.dart` `_save`（書架版面覆寫）、`fxl_settings_sheet.dart` `_notifyChanged`、`pdf_settings_sheet.dart` `_notifyChanged`、`reader_settings_sheet.dart` `_currentDraft`（流式 EPUB 專用，PDF 書不會經過，**不動**）、`book_reader_prefs.dart` 內的 `reflowableEpubFields()`（白名單式、刻意不含任何 PDF 欄位，**不需改程式**，只補測試）。
- schema 目前 `version: 27`（`sqlite_library_repository.dart` 的 `openDatabase`）。現有三個測試把版本釘在 27，升到 28 後必須同步改：`test/library/sqlite_library_repository_test.dart`（`getVersion(), 27`）、`test/stats/daily_reading_stats_schema_test.dart`（兩處 `getVersion(), 27`）。
- 生成的 `lib/l10n/app_localizations*.dart` **有進版控**，ARB 改完要執行 `flutter gen-l10n` 並把生成檔一起提交。`app_zh.arb` 必須與 `app_zh_TW.arb` 逐字相同（`arb_consistency_test` 會驗）；`app_zh_TW.arb` 每個鍵後面有 `@鍵` 描述區塊，其餘三份沒有。
- 設定面板現有「換頁動畫」（`readerPdfPageTurnAnimation*`，鍵 `pdf_settings_page_turn_animation_{slide,none}`）。本 Issue 新增的是「翻頁模式」（`readerPdfPageTurnMode*`）。名稱相近但不同，**不要重新命名現有的「換頁動畫」字串**（`CONTEXT.md` 的避用詞是針對「翻頁模式」這個詞，現有動畫字串不在範圍）。
- 現有 `pdf_settings_sheet_test.dart` 有 4 個測試用「預設偏好」去找換頁動畫選項（`換頁動畫兩個選項皆存在`、`點擊「無」選項…`、`點擊「滑動」選項…`、`換頁動畫群組改用 EBOptionChipGroup 後，2 個選項皆顯示短標籤`）。新規格下預設＝逐頁＝動畫選項隱藏，所以這 4 個測試必須改成先指定 `pdfPageTurnMode: PdfPageTurnMode.scroll`（這是規格造成的行為變更，不是回歸）。
- 所有 `.dart`／`.arb` 原始檔為 CRLF（`git config core.autocrlf true`，提交時 git 會正規化）。`Edit` 的定位字串只用**單行**，不要含換行；新增內容含多行時行尾混用 LF 無妨。唯一需要整段多行取代的地方（Task 4 Step 7）附了 Node 腳本。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **不改渲染行為**：`PdfReaderView` 內不得讀取 `pdfPageTurnMode` 去改變任何行為；既有 `pdf_reader_view_*` 測試不得因本 Issue 修改。
- **`null` 一律解讀為逐頁**；無全域預設層（spec「型別與偏好」）。
- **隱藏不清除**：選逐頁時隱藏「換頁動畫」，但 `pdfPageTurnAnimation` 的值要原樣保留並隨 `onChanged` 帶回。
- **新字串**一律經 `AppLocalizations`，四份 ARB 同步；需通過 `node tool/check_l10n_hardcoded_strings.js` 與 `arb_consistency_test`。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（約 6 分鐘，用 `run_in_background`，**必須在 `app/` 目錄下執行**）。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：計畫先審查再動手；程式審查先出報告（存於 `reviews/`，gitignore、不進版控），審查者不直接改程式；審查摘要放進 `epic.md`。
- **發版限制**（`issues.md` 開頭）：本 Issue 合併後設定面板會出現「翻頁模式」但選逐頁尚無作用，Epic 56 的 Issue 1～6 須同一個版本一起發布，中途不可切出發行版。

## 已決定事項（Ruling，執行前請確認沒有異議）

1. **設定面板的寫入慣例**：`PdfSettingsSheet` 比照既有 `_fitMode`／`_pageTurnAnimation`，以本地狀態追蹤 `_pageTurnMode`（`null` 顯示為逐頁），`_notifyChanged` 一律帶出非空值。也就是說，使用者在 PDF 設定面板動任何一個控制項，該書就會被寫入明確的 `paginated`（與現有 Fit 模式一致）。代價：若日後把「預設」改成別的值，這些書不會跟著變；spec 已明定無全域預設層，可接受。
2. **`ResolvedPreferences.pdfPageTurnMode` 建構子預設值為 `paginated`**（比照 `pdfPageTurnAnimation = slide`），讓 `resolved_preferences_test.dart` 等既有直接建構的測試不必修改。
3. **面板內順序**：翻頁模式放在 Fit 模式之後、雙頁模式之前（最影響閱讀體驗的選項靠前）；「換頁動畫」維持在原位（最底）。
4. **發現但不處理**：`library_screen.dart` `_save`（書架版面覆寫）整列重建時**漏帶 `textConversionOverride`**（既有缺陷，與本 Issue 無關，會把簡繁轉換覆寫清成 null）。本計畫不順手修，只在最終回報中提出，由使用者決定是否另開工單。

## Review Focus

最可能咬到使用者的情況（依可能性排序），每條都有對應測試：

1. **存其他設定時把翻頁模式靜默清成 null（回到逐頁）。** 書架版面覆寫、固定版面設定面板、PDF 設定面板三處整列重建。→ Task 3（書架、固定版面各一個測試）、Task 4（PDF 面板調整濾鏡後仍保留 `scroll`）。
2. **選逐頁後「換頁動畫」的值被清掉，切回連續捲動時使用者的選擇消失。** → Task 4 測「動畫＝無、切逐頁、再切連續捲動後動畫值仍為無，且隨 `onChanged` 帶出」。
3. **資料庫讀到不認得的翻頁模式名稱（例如降版後讀到未來版本寫入的值）而崩潰。** → Task 1（`fromMap`）與 Task 2（經 `BookReaderPrefsRepository.load` 讀真實資料庫列）。
4. **升級既有資料庫時遺失偏好或拋出 `duplicate column name`。** 從 v27 升級、以及從 v1（無 `book_reader_prefs` 表）一路跳級升級，兩條路徑。→ Task 2 的兩個遷移測試。
5. **預設偏好下設定面板出現「換頁動畫」或「連續捲動」被誤選。** `null` 偏好必須顯示為逐頁、動畫選項不存在。→ Task 4。另外 widget 層預設為連續捲動以保護既有大量 `PdfReaderView` 測試。→ Task 5。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/pdf_page_turn_mode.dart` | 新增 | 列舉 `PdfPageTurnMode { paginated, scroll }` |
| `app/lib/reader/book_reader_prefs.dart` | 修改 | 新欄位（序列化、相等、雜湊、`copyWith`），更新 `reflowableEpubFields` 文件註解的欄位數 |
| `app/lib/reader/resolved_preferences.dart` | 修改 | 非空欄位 `pdfPageTurnMode` |
| `app/lib/reader/reader_prefs_manager_impl.dart` | 修改 | `resolve`：單書值，否則逐頁 |
| `app/lib/library/sqlite_library_repository.dart` | 修改 | version 28、建表 DDL、`onUpgrade` 追加欄位 |
| `app/lib/screens/library_screen.dart` | 修改 | 版面覆寫 `_save` 帶上新欄位 |
| `app/lib/screens/fxl_settings_sheet.dart` | 修改 | `_notifyChanged` 帶上新欄位 |
| `app/lib/screens/pdf_settings_sheet.dart` | 修改 | 翻頁模式二選一、動畫選項條件顯示 |
| `app/lib/l10n/app_{zh_TW,zh,zh_CN,en}.arb`＋生成檔 | 修改 | 5 個新鍵 |
| `app/lib/reader/pdf_reader_view.dart` | 修改 | 新增 `pdfPageTurnMode` 建構參數（不讀取） |
| `app/lib/screens/reader_screen.dart` | 修改 | 傳 `resolved.pdfPageTurnMode` |
| 測試 | 新增／修改 | 見各 Task |
| `docs/epics/epic-56-pdf-paginated-reading/{epic.md,issues.md}` | 修改 | 開發記錄、狀態 |

## 執行前置

在 `main` 上建 worktree 與分支（比照 Issue 1）：

```bash
cd /c/Users/fycdc/AI/elinkBook
git worktree add .worktrees/epic-56-issue-2-page-turn-mode -b epic-56/issue-2-page-turn-mode main
cd .worktrees/epic-56-issue-2-page-turn-mode/app && flutter pub get
```

之後所有指令都在該 worktree 的 `app/` 下執行。

---

### Task 1：列舉、偏好模型與偏好解析（純 Dart）

**Files:**
- Create: `app/lib/reader/pdf_page_turn_mode.dart`
- Modify: `app/lib/reader/book_reader_prefs.dart`、`app/lib/reader/resolved_preferences.dart`、`app/lib/reader/reader_prefs_manager_impl.dart`
- Test: `app/test/reader/book_reader_prefs_test.dart`、`app/test/reader/reader_prefs_manager_test.dart`、`app/test/reader/resolved_preferences_test.dart`

**Interfaces:**
- Produces（後續 Task 依賴，名稱不可改）：
  - `enum PdfPageTurnMode { paginated, scroll }`（`package:elinkbook/reader/pdf_page_turn_mode.dart`）
  - `BookReaderPrefs.pdfPageTurnMode`（`PdfPageTurnMode?`）、`copyWith({PdfPageTurnMode? pdfPageTurnMode})`、`toMap` 鍵 `'pdf_page_turn_mode'`
  - `ResolvedPreferences.pdfPageTurnMode`（`PdfPageTurnMode`，建構子預設 `paginated`）

- [ ] **Step 1：寫失敗的測試（`book_reader_prefs_test.dart`）**

在檔案 import 區加：

```dart
import 'package:elinkbook/reader/pdf_page_turn_mode.dart';
```

在 `main()` 內（以單行錨點 `  test('換頁動畫欄位的 toMap／fromMap round-trip 保留欄位值，null 亦正確 round-trip',` 之前）插入：

```dart
  test('翻頁模式欄位：empty 為 null；相同值相等且雜湊一致；不同值（含 null 對非 null）不相等', () {
    expect(BookReaderPrefs.empty.pdfPageTurnMode, isNull);
    const a = BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.scroll);
    const b = BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.scroll);
    const c = BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.paginated);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
    expect(a, isNot(BookReaderPrefs.empty));
  });

  test('翻頁模式欄位的 toMap／fromMap round-trip：兩個值與 null 皆正確保留', () {
    for (final mode in PdfPageTurnMode.values) {
      final prefs = BookReaderPrefs(pdfPageTurnMode: mode);
      final map = prefs.toMap('book-mode');
      expect(map['pdf_page_turn_mode'], mode.name);
      expect(BookReaderPrefs.fromMap(map), prefs);
    }
    final nullMap = BookReaderPrefs.empty.toMap('book-mode');
    expect(nullMap['pdf_page_turn_mode'], isNull);
    expect(BookReaderPrefs.fromMap(nullMap).pdfPageTurnMode, isNull);
  });

  test('fromMap 遇到無法辨識的翻頁模式名稱（例如未來版本新增的值）時降級為 null，不拋例外', () {
    final map = BookReaderPrefs.empty.toMap('book-mode')
      ..['pdf_page_turn_mode'] = 'curl_from_the_future';
    expect(BookReaderPrefs.fromMap(map).pdfPageTurnMode, isNull);
  });

  test('copyWith 更新 pdfPageTurnMode 時其餘欄位保留；沒傳時保留原值', () {
    const original = BookReaderPrefs(
      pdfFitMode: PdfFitMode.fitWidth,
      pdfPageTurnAnimation: PdfPageTurnAnimation.none,
      pdfPageTurnMode: PdfPageTurnMode.paginated,
    );
    final updated = original.copyWith(pdfPageTurnMode: PdfPageTurnMode.scroll);
    expect(updated.pdfPageTurnMode, PdfPageTurnMode.scroll);
    expect(updated.pdfFitMode, PdfFitMode.fitWidth);
    expect(updated.pdfPageTurnAnimation, PdfPageTurnAnimation.none);
    expect(original.copyWith(pdfFitMode: PdfFitMode.pageFit).pdfPageTurnMode,
        PdfPageTurnMode.paginated);
  });
```

接著修改既有的 `reflowableEpubFields()` 測試（單行錨點定位）：
- 測試名稱 `'reflowableEpubFields() 過濾掉 PDF／雙頁／pageMargins 共 11 個欄位，其餘 21 個流式 EPUB 欄位保留（…'` 的 `11` 改為 `12`。
- 在輸入物件 `pdfPageTurnAnimation: PdfPageTurnAnimation.slide,`（該測試內，緊接 `);` 之前那一行）後加一行 `pdfPageTurnMode: PdfPageTurnMode.scroll,`。
- 在 `expect(filtered.pdfPageTurnAnimation, isNull);` 後加一行 `expect(filtered.pdfPageTurnMode, isNull);`，並把其上方註解 `// 11 個強制清空欄位。` 改為 `// 12 個強制清空欄位。`。

- [ ] **Step 2：寫失敗的測試（`reader_prefs_manager_test.dart`）**

加 import `package:elinkbook/reader/pdf_page_turn_mode.dart`。在 `resolve()` 群組內、單行錨點 `    test('單書覆寫存在時，優先套用單書覆寫，忽略全域預設', () {` 之前插入：

```dart
    test('翻頁模式：未覆寫時為逐頁；單書覆寫為連續捲動時採用單書值', () {
      final defaults = manager.resolve(LoadedPrefs(
        bookPrefs: BookReaderPrefs.empty,
        globalPrefs: const GlobalReaderPrefs.initial(),
      ));
      expect(defaults.pdfPageTurnMode, PdfPageTurnMode.paginated);

      final scroll = manager.resolve(LoadedPrefs(
        bookPrefs: const BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.scroll),
        globalPrefs: const GlobalReaderPrefs.initial(),
      ));
      expect(scroll.pdfPageTurnMode, PdfPageTurnMode.scroll);
    });

```

補強既有的集中測試（維持專案把所有列舉容錯／預設集中盤點的風格）：

- `book_reader_prefs_test.dart` 的既有測試 `fromMap 對未知的列舉名稱字串安全降級為 null，不拋出例外（…）`：在輸入 map 的鏈式指派中，`..['pdf_page_turn_animation'] = 'not_a_real_enum_value'` 之後加一行 `..['pdf_page_turn_mode'] = 'not_a_real_enum_value'`，並在 `expect(restored.pdfPageTurnAnimation, isNull);` 之後加 `expect(restored.pdfPageTurnMode, isNull);`。
- `resolved_preferences_test.dart`：加 import `package:elinkbook/reader/pdf_page_turn_mode.dart`；在第一個測試 `建構後各欄位保留傳入值，columnMode 預設 auto、columnSize 預設 720.0` 的末尾（最後一個 `expect` 之後）加 `expect(resolved.pdfPageTurnMode, PdfPageTurnMode.paginated);`，直接守住建構子預設值（Ruling 2）。

- [ ] **Step 3：執行確認失敗**

Run: `flutter test test/reader/book_reader_prefs_test.dart test/reader/reader_prefs_manager_test.dart test/reader/resolved_preferences_test.dart`
Expected: 編譯失敗（找不到 `pdf_page_turn_mode.dart`／`pdfPageTurnMode`）。

- [ ] **Step 4：實作**

建立 `app/lib/reader/pdf_page_turn_mode.dart`：

```dart
/// PDF 翻頁模式（epic-56-pdf-paginated-reading）。[paginated]（逐頁）一次只顯示
/// 一頁（開雙頁時為一個 spread）、換頁瞬間切換；[scroll]（連續捲動）頁面上下
/// 相連，即現況。偏好為 `null` 時一律解讀為 [paginated]（見 `CONTEXT.md`
/// 「翻頁模式」）。與 EPUB 的 `PageTurnMode`（分頁／捲動）是不同型別。
enum PdfPageTurnMode { paginated, scroll }
```

`book_reader_prefs.dart`（單行錨點 Edit）：
1. 在 `import 'pdf_page_turn_animation.dart';` 後加 `import 'pdf_page_turn_mode.dart';`。
2. 在 `  final PdfPageTurnAnimation? pdfPageTurnAnimation;` 後加：
   ```dart

     /// PDF 翻頁模式（epic-56 Issue 2）。null=逐頁（預設）。
     final PdfPageTurnMode? pdfPageTurnMode;
   ```
3. 建構子：在 `    this.pdfPageTurnAnimation,` 後加 `    this.pdfPageTurnMode,`。
4. `toMap`：在 `      'pdf_page_turn_animation': pdfPageTurnAnimation?.name,` 後加 `      'pdf_page_turn_mode': pdfPageTurnMode?.name,`。
5. `fromMap`：在 `          PdfPageTurnAnimation.values, map['pdf_page_turn_animation'] as String?),` 後加：
   ```dart
         pdfPageTurnMode: enumByNameOrNull(
             PdfPageTurnMode.values, map['pdf_page_turn_mode'] as String?),
   ```
6. `==`：在 `      other.pdfPageTurnAnimation == pdfPageTurnAnimation &&` 後加 `      other.pdfPageTurnMode == pdfPageTurnMode &&`。
7. `hashCode`：在 `  int get hashCode => Object.hashAll([` 後加一行 `        pdfPageTurnMode,`。
8. `copyWith`：參數在 `    PdfPageTurnAnimation? pdfPageTurnAnimation,` 後加 `    PdfPageTurnMode? pdfPageTurnMode,`；本體在 `      pdfPageTurnAnimation: pdfPageTurnAnimation ?? this.pdfPageTurnAnimation,` 後加 `      pdfPageTurnMode: pdfPageTurnMode ?? this.pdfPageTurnMode,`。
9. `reflowableEpubFields()` 的文件註解：單行 `  /// 欄位，其餘 11 個欄位（`pageMargins`、7 個 `pdf*`、3 個 `dualPage*`）` 改為 `12 個欄位（…8 個 `pdf*`…）`。**函式本體不改**（白名單式，新欄位自然被清空）。

`resolved_preferences.dart`：加 `import 'pdf_page_turn_mode.dart';`；在 `  final PdfPageTurnAnimation pdfPageTurnAnimation;` 後加：

```dart

  /// PDF 翻頁模式（epic-56 Issue 2）：恆非 null，resolve() 內
  /// book.pdfPageTurnMode ?? PdfPageTurnMode.paginated（無全域預設層）。
  final PdfPageTurnMode pdfPageTurnMode;
```

建構子在 `    this.pdfPageTurnAnimation = PdfPageTurnAnimation.slide,` 後加 `    this.pdfPageTurnMode = PdfPageTurnMode.paginated,`。

`reader_prefs_manager_impl.dart`：加 `import 'pdf_page_turn_mode.dart';`；在 `          book.pdfPageTurnAnimation ?? PdfPageTurnAnimation.slide,` 後加 `      pdfPageTurnMode: book.pdfPageTurnMode ?? PdfPageTurnMode.paginated,`。

- [ ] **Step 5：執行確認通過**

Run: `flutter test test/reader/book_reader_prefs_test.dart test/reader/reader_prefs_manager_test.dart test/reader/resolved_preferences_test.dart`
Expected: 全部 PASS。

- [ ] **Step 6：突變檢查（確認測試真的守得住）**

逐一暫時改壞後執行 Step 5 的指令，確認對應測試**變紅**，再還原：
- 在 `==` 拿掉 `other.pdfPageTurnMode == pdfPageTurnMode &&` → 「相等」測試失敗。
- `toMap` 把鍵改成 `'pdf_page_turn_modeX'` → round-trip 失敗。
- `copyWith` 本體拿掉 `?? this.pdfPageTurnMode` → copyWith 保留測試失敗。
- `resolve` 把 `?? PdfPageTurnMode.paginated` 改成 `?? PdfPageTurnMode.scroll` → 解析測試失敗。

- [ ] **Step 7：Commit**

```bash
git add app/lib/reader/pdf_page_turn_mode.dart app/lib/reader/book_reader_prefs.dart app/lib/reader/resolved_preferences.dart app/lib/reader/reader_prefs_manager_impl.dart app/test/reader/book_reader_prefs_test.dart app/test/reader/reader_prefs_manager_test.dart app/test/reader/resolved_preferences_test.dart
git commit -m "feat(reader): 新增 PDF 翻頁模式偏好欄位與解析（epic-56 Issue 2）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2：SQLite schema v28

**Files:**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`、`app/test/reader/book_reader_prefs_repository_test.dart`、`app/test/stats/daily_reading_stats_schema_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `BookReaderPrefs.pdfPageTurnMode`／`toMap` 鍵 `pdf_page_turn_mode`。
- Produces：`book_reader_prefs.pdf_page_turn_mode TEXT`（可為空）；`getVersion() == 28`。

- [ ] **Step 1：寫失敗的測試——新建資料庫與升級（`sqlite_library_repository_test.dart`）**

在單行錨點 `  test('全新安裝的 custom_fonts 表可用（version 16 起 onCreate 已含括）', () async {` 之前插入下面三個測試（檔案已有 `p`、`Directory`、`databaseFactory`、`OpenDatabaseOptions` 等 import，比照既有 v25→26 測試）：

```dart
  test('全新安裝的 book_reader_prefs 表包含 pdf_page_turn_mode 欄位（version 28 起 onCreate 已含括）',
      () async {
    await repository.insertBook(_book('b_page_turn_mode'));
    await repository.database.insert('book_reader_prefs', {
      'book_id': 'b_page_turn_mode',
      'pdf_page_turn_mode': 'scroll',
    });
    final row = (await repository.database.query('book_reader_prefs',
            where: 'book_id = ?', whereArgs: ['b_page_turn_mode']))
        .single;
    expect(row['pdf_page_turn_mode'], 'scroll');
  });

  test('既有 version 27 裝置升級到 version 28，book_reader_prefs 新增 pdf_page_turn_mode 欄位，既有 PDF 偏好完整保留',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v27_to_v28_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 27」的舊資料庫：book_reader_prefs 結構自 version 26
    // （text_conversion_override 加入）起到本次升級前沒有再變動。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 27,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              epubLocator TEXT,
              pdfPageIndex INTEGER,
              totalCharacterCount INTEGER,
              is_fixed_layout INTEGER,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL,
              content_fingerprint TEXT,
              position_updated_at INTEGER,
              position_synced_server_updated_at TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE book_reader_prefs (
              book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
              font_family TEXT,
              font_size REAL,
              font_weight REAL,
              line_height REAL,
              paragraph_spacing REAL,
              page_margins REAL,
              text_align TEXT,
              publisher_styles INTEGER,
              writing_mode_override TEXT,
              page_turn_mode_override TEXT,
              screen_orientation_override TEXT,
              pdf_fit_mode TEXT,
              pdf_contrast REAL,
              pdf_brightness REAL,
              pdf_bold_strength REAL,
              pdf_crop_mode TEXT,
              pdf_crop_rect TEXT,
              dual_page_mode TEXT,
              dual_page_cover_alone INTEGER,
              dual_page_direction TEXT,
              show_header INTEGER,
              show_footer INTEGER,
              column_mode TEXT,
              column_size REAL,
              margin_top REAL,
              margin_bottom REAL,
              margin_left REAL,
              margin_right REAL,
              fullscreen INTEGER,
              letter_spacing REAL,
              pdf_page_turn_animation TEXT,
              text_conversion_override TEXT
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有 PDF',
      'format': 'pdf',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.insert('book_reader_prefs', {
      'book_id': 'b1',
      'pdf_fit_mode': 'fitWidth',
      'pdf_contrast': 20.0,
      'dual_page_mode': 'always',
      'pdf_page_turn_animation': 'none',
      'text_conversion_override': 'toTraditional',
    });
    await oldDb.close();

    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final row = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['pdf_fit_mode'], 'fitWidth');
    expect(row['pdf_contrast'], 20.0);
    expect(row['dual_page_mode'], 'always');
    expect(row['pdf_page_turn_animation'], 'none');
    expect(row['text_conversion_override'], 'toTraditional');
    expect(row['pdf_page_turn_mode'], isNull); // 新欄位存在且預設 NULL

    await upgraded.database.update(
      'book_reader_prefs',
      {'pdf_page_turn_mode': 'scroll'},
      where: 'book_id = ?',
      whereArgs: ['b1'],
    );
    final updated = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(updated['pdf_page_turn_mode'], 'scroll');
  });

  test(
      '既有 version 1 裝置（無 book_reader_prefs 表）跳級升級到 version 28，'
      'book_reader_prefs 表正確建立含 pdf_page_turn_mode，且不拋出 duplicate column name 例外',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v1_to_v28_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '最早期書籍',
      'format': 'pdf',
      'filePath': 'content://example/b1',
      'source': 'local',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.close();

    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    await upgraded.database.insert('book_reader_prefs', {
      'book_id': 'b1',
      'pdf_page_turn_mode': 'paginated',
    });
    final row = (await upgraded.database.query('book_reader_prefs',
            where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['pdf_page_turn_mode'], 'paginated');
  });

```

- [ ] **Step 2：寫失敗的測試——經偏好倉儲讀寫（`book_reader_prefs_repository_test.dart`）**

加 import `package:elinkbook/reader/pdf_page_turn_mode.dart`。在單行錨點 `  test('save 寫入雙頁欄位後，load 讀回相同的值', () async {` 之前插入：

```dart
  test('save 寫入翻頁模式後，load 讀回相同的值（逐頁、連續捲動各一）', () async {
    for (final mode in PdfPageTurnMode.values) {
      await repository.save('b1', BookReaderPrefs(pdfPageTurnMode: mode));
      expect((await repository.load('b1')).pdfPageTurnMode, mode);
    }
  });

  test('資料庫存有無法辨識的翻頁模式名稱（例如未來版本寫入的值）時，load 不拋例外且降級為 null，其餘欄位不受影響',
      () async {
    await libraryRepository.database.insert('book_reader_prefs', {
      'book_id': 'b1',
      'font_size': 18.0,
      'pdf_page_turn_mode': 'curl_from_the_future',
    });

    final prefs = await repository.load('b1');

    expect(prefs.pdfPageTurnMode, isNull);
    expect(prefs.fontSize, 18.0);
  });

```

- [ ] **Step 3：更新釘死版本號的既有測試**

- `test/library/sqlite_library_repository_test.dart`：把
  `    test('全新安裝（onCreate 直接建到 version 27）：isFullTextSearchAvailable 為 true，'` 的 `27` 改 `28`，並把 `expect(await repository.database.getVersion(), 27);` 改為 `28`。
- `test/stats/daily_reading_stats_schema_test.dart`：把測試名稱 `'全新安裝：version 27，資料表與日期索引存在，主鍵為（date, book_id）'` 的 `27` 改 `28`；兩處 `expect(await …getVersion(), 27);`（行 36、108）都改 `28`。第 108 行所在測試（v26→v27）仍會一路升到目前版本，所以是 `28`；在該行上方加註解 `// 升級一路走到目前最新版本（28），不是只升到 27`。

- [ ] **Step 4：執行確認失敗**

Run: `flutter test test/library/sqlite_library_repository_test.dart test/reader/book_reader_prefs_repository_test.dart test/stats/daily_reading_stats_schema_test.dart`
Expected: FAIL（新欄位不存在：`no such column: pdf_page_turn_mode`／版本仍 27）。

- [ ] **Step 5：實作**

`sqlite_library_repository.dart`（單行錨點 Edit）：
1. `      version: 27,` → `      version: 28,`。
2. `onUpgrade` 的 `else` 分支內、緊接 `oldVersion < 26` 區塊的 `            await _addTextConversionOverrideColumn(db);` 之後、該區塊收尾的 `}` 之後，新增（行縮排比照上方 `if (oldVersion < 26)`，即 10 個空格）：
   ```dart
             if (oldVersion < 28) {
               // epic-56-pdf-paginated-reading Issue 2：PDF 翻頁模式欄位。必須放在
               // else 分支內（oldVersion >= 2）——理由同 _addTextConversionOverrideColumn：
               // oldVersion < 2 時 _createBookReaderPrefsTable 已一步到位建表含
               // pdf_page_turn_mode，若在 else 分支外無條件執行 ALTER TABLE，
               // oldVersion == 1 的裝置會重複 ALTER TABLE 拋出崩潰。
               await _addPdfPageTurnModeColumn(db);
             }
   ```
   實作時先 `Read` 該區段確認括號位置，插在 `if (oldVersion < 26) { … }` 區塊結束之後、`else` 分支的 `}` 之前。
3. 建表 DDL：`        text_conversion_override TEXT` → 改為 `        text_conversion_override TEXT,` 並在其後加一行 `        pdf_page_turn_mode TEXT`。
4. 在 `_addTextConversionOverrideColumn` 函式之後新增：
   ```dart
     static Future<void> _addPdfPageTurnModeColumn(Database db) async {
       // epic-56-pdf-paginated-reading Issue 2：PDF 翻頁模式欄位，補追加到既有
       // （version 2 起已存在）的 book_reader_prefs 表。比照
       // _addTextConversionOverrideColumn 既有慣例，僅在表已存在時才執行
       // ALTER TABLE。
       final tables = await db.rawQuery(
           "SELECT name FROM sqlite_master WHERE type='table' AND name='book_reader_prefs'");
       if (tables.isNotEmpty) {
         await db.execute(
             'ALTER TABLE book_reader_prefs ADD COLUMN pdf_page_turn_mode TEXT');
       }
     }
   ```

- [ ] **Step 6：執行確認通過**

Run: `flutter test test/library/sqlite_library_repository_test.dart test/reader/book_reader_prefs_repository_test.dart test/stats/daily_reading_stats_schema_test.dart`
Expected: 全部 PASS。

- [ ] **Step 7：突變檢查**

- 把 `onUpgrade` 的 `if (oldVersion < 28)` 區塊暫時移到 `else` 分支**外面**（無條件執行）→ v1 跳級測試應因 `duplicate column name` 失敗；還原。
- 拿掉建表 DDL 的新欄位 → 「全新安裝」測試失敗；還原。
- 拿掉 `onUpgrade` 的呼叫 → v27→v28 測試失敗；還原。

- [ ] **Step 8：Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart app/test/reader/book_reader_prefs_repository_test.dart app/test/stats/daily_reading_stats_schema_test.dart
git commit -m "feat(library): book_reader_prefs 新增 pdf_page_turn_mode 欄位，schema 27→28（epic-56 Issue 2）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：書架版面覆寫與固定版面設定面板帶上新欄位

**Files:**
- Modify: `app/lib/screens/library_screen.dart`、`app/lib/screens/fxl_settings_sheet.dart`
- Test: `app/test/screens/library_screen_test.dart`、`app/test/screens/fxl_settings_sheet_test.dart`

**Interfaces:**
- Consumes：`BookReaderPrefs.pdfPageTurnMode`（Task 1）。

- [ ] **Step 1：寫失敗的測試（`fxl_settings_sheet_test.dart`）**

加 import `package:elinkbook/reader/pdf_page_turn_mode.dart` 與 `package:elinkbook/reader/pdf_page_turn_animation.dart`。在單行錨點 `  testWidgets('點擊「轉換為繁體」圖示後，onChanged 帶入 TextConversionMode.toTraditional，其餘欄位維持原值',` 之前插入：

```dart
  testWidgets('已持久化 pdfPageTurnMode／pdfPageTurnAnimation 時，調整雙頁模式不會清空這兩個欄位（回歸檢查）',
      (tester) async {
    BookReaderPrefs? changed;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(
              pdfPageTurnMode: PdfPageTurnMode.scroll,
              pdfPageTurnAnimation: PdfPageTurnAnimation.none,
            ),
            onChanged: (prefs) => changed = prefs,
            isEinkMode: false,
          ),
        ),
      ),
    );

    await tester
        .tap(find.byKey(const Key('fxl_settings_dual_page_mode_always')));
    await tester.pump();

    expect(changed?.dualPageMode, DualPageMode.always);
    expect(changed?.pdfPageTurnMode, PdfPageTurnMode.scroll,
        reason: '關鍵斷言：整列重建時不可把翻頁模式清成 null');
    expect(changed?.pdfPageTurnAnimation, PdfPageTurnAnimation.none);
  });

```

- [ ] **Step 2：寫失敗的測試（`library_screen_test.dart`）**

加 import `package:elinkbook/reader/pdf_page_turn_mode.dart`。在單行錨點 `  testWidgets('bookReaderPrefsRepository 未提供時，「版面覆寫」選項不顯示', (tester) async {` 之前插入（結構比照其後的既有版面覆寫核心回歸測試）：

```dart
  testWidgets('版面覆寫：儲存後既有的 PDF 翻頁模式原樣保留（epic-56 Issue 2 回歸）',
      (tester) async {
    final book = _testBook(id: '1', title: '書A');
    final repository = FakeLibraryRepository(initialBooks: [book]);
    final bookReaderPrefsRepository = FakeBookReaderPrefsRepository();
    await bookReaderPrefsRepository.save(
      '1',
      const BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.scroll),
    );

    await pumpLocalizedWidget(
      tester,
      LibraryScreen(
        repository: repository,
        importService: FakeBookImportService(),
        prefsManager: prefsManager,
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          bookReaderPrefsRepository: bookReaderPrefsRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_action_menu_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book_action_layout_override')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layout_override_page_turn_mode_scroll')));
    await tester.tap(find.byKey(const Key('layout_override_save_button')));
    await tester.pumpAndSettle();

    final saved = await bookReaderPrefsRepository.load('1');
    expect(saved.pageTurnModeOverride, PageTurnMode.scroll);
    expect(saved.pdfPageTurnMode, PdfPageTurnMode.scroll,
        reason: '關鍵斷言：版面覆寫整列重建不可把 PDF 翻頁模式清成 null');
  });

```

- [ ] **Step 3：執行確認失敗**

Run: `flutter test test/screens/fxl_settings_sheet_test.dart test/screens/library_screen_test.dart --plain-name "pdfPageTurnMode" ; flutter test test/screens/library_screen_test.dart --plain-name "PDF 翻頁模式原樣保留"`
Expected: 兩個新測試 FAIL（`changed?.pdfPageTurnMode` 為 `null`，預期 `scroll`）。

- [ ] **Step 4：實作**

- `library_screen.dart`：在 `      pdfPageTurnAnimation: existing.pdfPageTurnAnimation,` 後加 `      pdfPageTurnMode: existing.pdfPageTurnMode,`。（同一建構子漏帶 `textConversionOverride` 是既有缺陷，**本 Issue 不處理**，見「已決定事項」第 4 點。）
- `fxl_settings_sheet.dart`：在 `        pdfPageTurnAnimation: widget.prefs.pdfPageTurnAnimation,` 後加 `        pdfPageTurnMode: widget.prefs.pdfPageTurnMode,`。

- [ ] **Step 5：執行確認通過**

Run: `flutter test test/screens/fxl_settings_sheet_test.dart test/screens/library_screen_test.dart`
Expected: 全部 PASS。

- [ ] **Step 6：突變檢查**

把 Step 4 兩行各自暫時註解掉，確認對應的新測試變紅，再還原。

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/library_screen.dart app/lib/screens/fxl_settings_sheet.dart app/test/screens/library_screen_test.dart app/test/screens/fxl_settings_sheet_test.dart
git commit -m "fix(reader): 書架版面覆寫與固定版面面板整列重建時保留 PDF 翻頁模式（epic-56 Issue 2）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4：ARB 字串與 PDF 設定面板

**Files:**
- Modify: `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`（＋ `flutter gen-l10n` 生成檔）、`app/lib/screens/pdf_settings_sheet.dart`
- Test: `app/test/screens/pdf_settings_sheet_test.dart`

**Interfaces:**
- Consumes：`PdfPageTurnMode`、`BookReaderPrefs.pdfPageTurnMode`（Task 1）。
- Produces：鍵 `pdf_settings_page_turn_mode_paginated`／`pdf_settings_page_turn_mode_scroll`；`AppLocalizations` 的 `readerPdfPageTurnModeLabel`、`readerPdfPageTurnModePaginatedTooltip`、`readerPdfPageTurnModePaginatedLabel`、`readerPdfPageTurnModeScrollTooltip`、`readerPdfPageTurnModeScrollLabel`。

- [ ] **Step 1：新增 ARB 鍵（四份）並產生 l10n**

每份 ARB 都在單行錨點 `  "readerPdfPageTurnAnimationLabel": …,` **之前**插入（該行 zh_TW 為 `"換頁動畫"`、en 為 `"Page-turn animation"`）。

`app_zh_TW.arb`（含 `@` 描述）：

```json
  "readerPdfPageTurnModeLabel": "翻頁模式",
  "@readerPdfPageTurnModeLabel": {
    "description": "PDF 顯示分頁「翻頁模式」（逐頁／連續捲動）選項群組小標題"
  },
  "readerPdfPageTurnModePaginatedTooltip": "逐頁：一次只顯示一頁，換頁瞬間切換",
  "@readerPdfPageTurnModePaginatedTooltip": {
    "description": "PDF 翻頁模式「逐頁」選項 tooltip"
  },
  "readerPdfPageTurnModePaginatedLabel": "逐頁",
  "@readerPdfPageTurnModePaginatedLabel": {
    "description": "PDF 翻頁模式「逐頁」選項短標籤"
  },
  "readerPdfPageTurnModeScrollTooltip": "連續捲動：頁面上下相連，可自由捲動",
  "@readerPdfPageTurnModeScrollTooltip": {
    "description": "PDF 翻頁模式「連續捲動」選項 tooltip"
  },
  "readerPdfPageTurnModeScrollLabel": "連續捲動",
  "@readerPdfPageTurnModeScrollLabel": {
    "description": "PDF 翻頁模式「連續捲動」選項短標籤"
  },
```

`app_zh.arb`（與 zh_TW 值逐字相同，**無** `@` 區塊，格式比照該檔既有鍵）：

```json
  "readerPdfPageTurnModeLabel": "翻頁模式",
  "readerPdfPageTurnModePaginatedTooltip": "逐頁：一次只顯示一頁，換頁瞬間切換",
  "readerPdfPageTurnModePaginatedLabel": "逐頁",
  "readerPdfPageTurnModeScrollTooltip": "連續捲動：頁面上下相連，可自由捲動",
  "readerPdfPageTurnModeScrollLabel": "連續捲動",
```

`app_zh_CN.arb`：

```json
  "readerPdfPageTurnModeLabel": "翻页模式",
  "readerPdfPageTurnModePaginatedTooltip": "逐页：一次只显示一页，换页瞬间切换",
  "readerPdfPageTurnModePaginatedLabel": "逐页",
  "readerPdfPageTurnModeScrollTooltip": "连续滚动：页面上下相连，可自由滚动",
  "readerPdfPageTurnModeScrollLabel": "连续滚动",
```

`app_en.arb`：

```json
  "readerPdfPageTurnModeLabel": "Page-turn mode",
  "readerPdfPageTurnModePaginatedTooltip": "Paged: one page at a time, instant page switch",
  "readerPdfPageTurnModePaginatedLabel": "Paged",
  "readerPdfPageTurnModeScrollTooltip": "Continuous scroll: pages are connected, scroll freely",
  "readerPdfPageTurnModeScrollLabel": "Scroll",
```

Run: `flutter gen-l10n`
Expected: 無錯誤；`git status` 顯示 `lib/l10n/app_localizations*.dart` 有變動。再跑 `flutter test test/l10n/` 應 PASS（鍵集合一致、zh 鏡像、en 無漏翻）。

- [ ] **Step 2：改既有測試——動畫選項需指定連續捲動（`pdf_settings_sheet_test.dart`）**

加 import `package:elinkbook/reader/pdf_page_turn_mode.dart`。

- 測試 `換頁動畫兩個選項皆存在`：`_pumpSheet(tester, BookReaderPrefs.empty, (_) {})` 改為 `_pumpSheet(tester, const BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.scroll), (_) {})`。
- 測試 `點擊「無」選項後，onChanged 帶入 pdfPageTurnAnimation=none`：該測試內傳給 `_pumpSheet` 的第二個參數 `BookReaderPrefs.empty` 改為 `const BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.scroll)`。
- 測試 `點擊「滑動」選項後，onChanged 帶入 pdfPageTurnAnimation=slide`：`const BookReaderPrefs(pdfPageTurnAnimation: PdfPageTurnAnimation.none)` 改為 `const BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.scroll, pdfPageTurnAnimation: PdfPageTurnAnimation.none)`。

- 測試 `換頁動畫群組改用 EBOptionChipGroup 後，2 個選項皆顯示短標籤（epic-39-layout-settings-redesign Issue 5）`：該測試內 `await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});` 的 `BookReaderPrefs.empty` 改為 `const BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.scroll)`。

（這四個測試在實作前仍通過——因為動畫選項目前一律顯示——所以此步驟沒有紅燈；紅燈由 Step 3 的新測試提供。實作後若漏改任何一個，`dragUntilVisible` 會因找不到元件而逾時失敗。）

- [ ] **Step 3：寫失敗的新測試（同檔，在單行錨點 `  testWidgets('換頁動畫兩個選項皆存在', (tester) async {` 之前插入）**

```dart
  testWidgets('翻頁模式：未覆寫（null）時顯示為逐頁，且不顯示「換頁動畫」選項', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(find.byKey(const Key('pdf_settings_page_turn_mode_paginated')),
        findsOneWidget);
    expect(find.byKey(const Key('pdf_settings_page_turn_mode_scroll')),
        findsOneWidget);
    expect(find.byKey(const Key('pdf_settings_page_turn_animation_slide')),
        findsNothing);
    expect(find.byKey(const Key('pdf_settings_page_turn_animation_none')),
        findsNothing);
  });

  testWidgets('點擊「連續捲動」後，onChanged 帶入 pdfPageTurnMode=scroll 且「換頁動畫」選項出現',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(tester, BookReaderPrefs.empty, (p) => notified = p);

    await tester
        .tap(find.byKey(const Key('pdf_settings_page_turn_mode_scroll')));
    await tester.pump();

    expect(notified?.pdfPageTurnMode, PdfPageTurnMode.scroll);
    await tester.dragUntilVisible(
      find.byKey(const Key('pdf_settings_page_turn_animation_slide')),
      find.byKey(const Key('pdf_settings_display_scroll')),
      const Offset(0, -100),
    );
    expect(find.byKey(const Key('pdf_settings_page_turn_animation_slide')),
        findsOneWidget);
  });

  testWidgets('點擊「逐頁」後，onChanged 帶入 pdfPageTurnMode=paginated 且「換頁動畫」選項隱藏',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.scroll),
      (p) => notified = p,
    );

    await tester
        .tap(find.byKey(const Key('pdf_settings_page_turn_mode_paginated')));
    await tester.pump();

    expect(notified?.pdfPageTurnMode, PdfPageTurnMode.paginated);
    expect(find.byKey(const Key('pdf_settings_page_turn_animation_slide')),
        findsNothing);
  });

  testWidgets('隱藏不清除：換頁動畫＝無，切到逐頁再切回連續捲動後，動畫值仍為無並隨 onChanged 帶出',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(
        pdfPageTurnMode: PdfPageTurnMode.scroll,
        pdfPageTurnAnimation: PdfPageTurnAnimation.none,
      ),
      (p) => notified = p,
    );

    await tester
        .tap(find.byKey(const Key('pdf_settings_page_turn_mode_paginated')));
    await tester.pump();
    expect(notified?.pdfPageTurnAnimation, PdfPageTurnAnimation.none,
        reason: '隱藏時動畫值仍須帶回，不可清成 null 或 slide');

    await tester
        .tap(find.byKey(const Key('pdf_settings_page_turn_mode_scroll')));
    await tester.pump();
    await tester
        .tap(find.byKey(const Key('pdf_settings_dual_page_mode_always')));
    await tester.pump();

    expect(notified?.pdfPageTurnMode, PdfPageTurnMode.scroll);
    expect(notified?.pdfPageTurnAnimation, PdfPageTurnAnimation.none,
        reason: '切回連續捲動後使用者先前的動畫選擇必須還在');
  });

  testWidgets('已持久化 pdfPageTurnMode＝scroll 時，調整濾鏡分頁不會清空翻頁模式（回歸檢查）',
      (tester) async {
    BookReaderPrefs? notified;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.scroll),
      (p) => notified = p,
    );

    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_contrast_increment')));
    await tester.pump();

    expect(notified?.pdfPageTurnMode, PdfPageTurnMode.scroll,
        reason: '關鍵斷言：未被清空');
  });

  testWidgets('英文介面下翻頁模式小標題正確以英文渲染', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {},
        locale: const Locale('en'));

    expect(find.text('Page-turn mode'), findsOneWidget);
  });

```

- [ ] **Step 4：執行確認失敗**

Run: `flutter test test/screens/pdf_settings_sheet_test.dart`
Expected: 新測試 FAIL（找不到 `pdf_settings_page_turn_mode_*`）。

- [ ] **Step 5：實作——`pdf_settings_sheet.dart` 狀態與 `onChanged`（單行錨點 Edit）**

1. 在 `import '../reader/pdf_page_turn_animation.dart';` 後加 `import '../reader/pdf_page_turn_mode.dart';`。
2. 在 `  late PdfPageTurnAnimation _pageTurnAnimation;` 後加 `  late PdfPageTurnMode _pageTurnMode;`。
3. `initState`：在 `        widget.prefs.pdfPageTurnAnimation ?? PdfPageTurnAnimation.slide;` 後加 `    _pageTurnMode = widget.prefs.pdfPageTurnMode ?? PdfPageTurnMode.paginated;`。
4. `_notifyChanged`：在 `        pdfPageTurnAnimation: _pageTurnAnimation,` 後加 `        pdfPageTurnMode: _pageTurnMode,`。

- [ ] **Step 6：實作——選項清單與翻頁模式 chip 群組**

在 `_buildDisplayTab` 內、`    final pageTurnAnimationOptions = [` 之前加：

```dart
    final pageTurnModeOptions = [
      (
        PdfPageTurnMode.paginated,
        'paginated',
        Icons.looks_one,
        l10n.readerPdfPageTurnModePaginatedTooltip,
        l10n.readerPdfPageTurnModePaginatedLabel,
      ),
      (
        PdfPageTurnMode.scroll,
        'scroll',
        Icons.swap_vert,
        l10n.readerPdfPageTurnModeScrollTooltip,
        l10n.readerPdfPageTurnModeScrollLabel,
      ),
    ];
```

把單行 `            Text(l10n.readerDualPageModeLabel, style: TextStyle(fontWeight: FontWeight.bold)),` 取代為（即在雙頁模式小標題之前插入翻頁模式群組）：

```dart
            Text(l10n.readerPdfPageTurnModeLabel, style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            EBOptionChipGroup<PdfPageTurnMode>(
              items: pageTurnModeOptions.map((option) {
                final (mode, keySuffix, icon, tooltip, label) = option;
                return EBOptionChipItem<PdfPageTurnMode>(
                  itemKey: Key('pdf_settings_page_turn_mode_$keySuffix'),
                  value: mode,
                  icon: icon,
                  label: label,
                  tooltip: tooltip,
                );
              }).toList(),
              groupValue: _pageTurnMode,
              onSelected: (v) => setState(() {
                _pageTurnMode = v;
                _notifyChanged();
              }),
            ),
            const SizedBox(height: 16),
            Text(l10n.readerDualPageModeLabel, style: TextStyle(fontWeight: FontWeight.bold)),
```

- [ ] **Step 7：實作——「換頁動畫」條件顯示（整段多行取代，用 Node 腳本）**

做法二選一：

- **做法 A（建議，無法用多行 Edit 時）**：下方 Node 腳本。
- **做法 B**：若所用的編輯工具能正確處理 CRLF 多行字串（先用一次小範圍多行取代試驗，確認沒有「找不到字串」），可直接把原本的 `const SizedBox(height: 16),`＋`Text(l10n.readerPdfPageTurnAnimationLabel…)`＋`const SizedBox(height: 8),`＋`EBOptionChipGroup<PdfPageTurnAnimation>(…),` 整段包進 `if (_pageTurnMode == PdfPageTurnMode.scroll) ...[ … ],`（縮排各加 2 格），效果與腳本完全相同。

做法 A：在 `app/` 下建立暫存腳本（放 scratchpad，不進版控）並執行 `node <script>`：

```js
const fs = require('fs');
const f = 'lib/screens/pdf_settings_sheet.dart';
const raw = fs.readFileSync(f, 'utf8');
const crlf = raw.includes('\r\n');
let t = raw.replace(/\r\n/g, '\n');

const startMarker =
  "            const SizedBox(height: 16),\n" +
  "            Text(l10n.readerPdfPageTurnAnimationLabel";
const start = t.indexOf(startMarker);
const endMarker = "              }),\n            ),\n";
const end0 = t.indexOf(endMarker, t.indexOf('_pageTurnAnimation = v;'));
if (start < 0 || end0 < 0) throw new Error('找不到換頁動畫區塊');
const end = end0 + endMarker.length;

const block = t.slice(start, end);
// 把整段（含上方 16px 間距）包進「連續捲動才顯示」的條件展開
const indented = block.split('\n').map((l) => (l ? '  ' + l : l)).join('\n');
const replacement =
  "            if (_pageTurnMode == PdfPageTurnMode.scroll) ...[\n" +
  indented.replace(/\n$/, '') + "\n" +
  "            ],\n";

t = t.slice(0, start) + replacement + t.slice(end);
fs.writeFileSync(f, crlf ? t.replace(/\n/g, '\r\n') : t);
console.log('OK');
```

執行後 `Read` 該區段確認語法與縮排（`...[` 內是原本 5 個 widget：間距、小標題、間距、`EBOptionChipGroup`），並跑 `dart format` **不要**（會重排整檔），只確認 `flutter analyze` 乾淨。

- [ ] **Step 8：執行確認通過**

Run: `flutter test test/screens/pdf_settings_sheet_test.dart test/l10n/`
Expected: 全部 PASS。

- [ ] **Step 9：突變檢查與靜態檢查**

- 把 `_notifyChanged` 的 `pdfPageTurnMode: _pageTurnMode,` 暫時刪掉 → 「回歸檢查（濾鏡）」「點擊連續捲動」測試應失敗；還原。
- 把條件 `_pageTurnMode == PdfPageTurnMode.scroll` 暫時改成 `true` → 「未覆寫時隱藏動畫」測試應失敗；還原。
- 把 `_pageTurnAnimation` 在條件隱藏時重設為 `slide`（模擬「隱藏就清除」的錯誤實作）→ 「隱藏不清除」測試應失敗；還原。
- Run: `node tool/check_l10n_hardcoded_strings.js` → 無新增違規；`flutter analyze` → `No issues found!`。

- [ ] **Step 10：Commit**

```bash
git add app/lib/l10n app/lib/screens/pdf_settings_sheet.dart app/test/screens/pdf_settings_sheet_test.dart
git commit -m "feat(reader): PDF 設定面板新增翻頁模式（逐頁／連續捲動），選逐頁時隱藏換頁動畫（epic-56 Issue 2）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5：`PdfReaderView` 參數與 `ReaderScreen` 接線（尚不改變渲染）

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`、`app/lib/screens/reader_screen.dart`
- Test: `app/test/reader/pdf_reader_view_test.dart`、`app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：`ResolvedPreferences.pdfPageTurnMode`（Task 1）。
- Produces：`PdfReaderView.pdfPageTurnMode`（`PdfPageTurnMode`，widget 層預設 `scroll`）。Issue 4 起才會讀取。

- [ ] **Step 1：寫失敗的測試**

`pdf_reader_view_test.dart`：加 import `package:elinkbook/reader/pdf_page_turn_mode.dart`。在 `main()` 內單行錨點 `  setUp(() => pdfrxInitialize());` 之後插入：

```dart

  test('widget 層預設翻頁模式為連續捲動（保護既有 PdfReaderView 測試；產品預設由 ReaderScreen 傳入）', () {
    final view = PdfReaderView(
      filePath: 'test/fixtures/sample.pdf',
      onPageRendered: () {},
      onError: (_) {},
    );

    expect(view.pdfPageTurnMode, PdfPageTurnMode.scroll);
  });
```

`reader_screen_test.dart`：加 import `package:elinkbook/reader/pdf_page_turn_mode.dart`。在單行錨點 `  testWidgets('開啟該書已有的持久化換頁動畫偏好設定後，PdfReaderView 的 pdfPageTurnAnimation 正確載入', (` 之前插入：

```dart
  testWidgets('開啟該書已持久化連續捲動翻頁模式後，PdfReaderView 的 pdfPageTurnMode 為 scroll', (
    tester,
  ) async {
    await prefsManager.saveBookPrefs(
      'b1',
      const BookReaderPrefs(pdfPageTurnMode: PdfPageTurnMode.scroll),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.pdfPageTurnMode, PdfPageTurnMode.scroll);
  });

  testWidgets('尚未持久化翻頁模式時，PdfReaderView 的 pdfPageTurnMode 為 paginated（產品預設逐頁）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b1',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(pdfView.pdfPageTurnMode, PdfPageTurnMode.paginated);
  });

```

- [ ] **Step 2：執行確認失敗**

Run: `flutter test test/reader/pdf_reader_view_test.dart --plain-name "widget 層預設翻頁模式" ; flutter test test/screens/reader_screen_test.dart --plain-name "翻頁模式"`
Expected: 編譯失敗（`pdfPageTurnMode` 不存在）。

- [ ] **Step 3：實作**

`pdf_reader_view.dart`：
1. 加 `import 'pdf_page_turn_mode.dart';`（緊接 `import 'pdf_page_turn_animation.dart';` 之後）。
2. 在 `  final PdfPageTurnAnimation pdfPageTurnAnimation;` 後加：
   ```dart

     /// PDF 翻頁模式（epic-56 Issue 2）。**widget 層預設刻意為連續捲動**（不是
     /// 產品預設的逐頁）：保護既有大量 `PdfReaderView` 測試；產品預設由
     /// `ReaderScreen` 以解析後的偏好明確傳入，比照 `dualPageMode`。**本 Issue
     /// 尚未讀取此參數**，逐頁渲染在 Issue 4 實作。
     final PdfPageTurnMode pdfPageTurnMode;
   ```
3. 建構子在 `    this.pdfPageTurnAnimation = PdfPageTurnAnimation.slide,` 後加 `    this.pdfPageTurnMode = PdfPageTurnMode.scroll,`。

`reader_screen.dart`：在 `          pdfPageTurnAnimation: resolved.pdfPageTurnAnimation,` 後加 `          pdfPageTurnMode: resolved.pdfPageTurnMode,`。

- [ ] **Step 4：執行確認通過（含零回歸）**

Run: `flutter test test/reader/pdf_reader_view_test.dart test/reader/pdf_reader_view_fit_mode_test.dart test/screens/reader_screen_test.dart`
Expected: 全部 PASS，且**未修改**任何既有 `pdf_reader_view_*` 測試。

- [ ] **Step 5：突變檢查**

- 把 `ReaderScreen` 的新參數行暫時註解 → 兩個 `reader_screen_test` 新測試中的 `scroll` 案例失敗；還原。
- 把 widget 層預設改成 `paginated` → widget 預設測試失敗；還原。

- [ ] **Step 6：Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/lib/screens/reader_screen.dart app/test/reader/pdf_reader_view_test.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(reader): PdfReaderView 新增 pdfPageTurnMode 參數，ReaderScreen 接線（epic-56 Issue 2，尚不改變渲染）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6：全套驗證與文件

**Files:**
- Modify: `docs/epics/epic-56-pdf-paginated-reading/epic.md`、`docs/epics/epic-56-pdf-paginated-reading/issues.md`

- [ ] **Step 1：靜態檢查**

Run（在 `app/`）：`flutter analyze` → `No issues found!`；`node tool/check_l10n_hardcoded_strings.js` → 無違規。

- [ ] **Step 2：完整測試（只在此跑一次）**

Run（`run_in_background`，在 `app/`）：`flutter test`
Expected: 全數 PASS（約 6 分鐘）。若失敗，先判斷是否為本 Issue 造成（尤其是釘死 schema 版本號或預設偏好下尋找換頁動畫選項的測試），逐一修到綠；與本 Issue 無關的既有失敗要在回報中點名。

- [ ] **Step 3：真機／手動確認清單寫入 `epic.md`**

在 `epic.md` 新增「Issue 2 開發記錄」段落，內容至少包含：
- 完成項目與提交清單、全套測試結果（通過數、日期）。
- 待真機確認：PDF 設定面板「顯示」分頁在小螢幕／E-Ink 下，新增一列 chip 後是否仍可捲到最底；選逐頁時「換頁動畫」是否確實消失。
- 提醒：本 Issue 合併後選逐頁尚無作用，須待 Issue 4。
- 發現但未處理：`library_screen.dart` 書架版面覆寫 `_save` 漏帶 `textConversionOverride`（既有缺陷）。

- [ ] **Step 4：更新 `issues.md` 狀態**

把 Issue 2 的 `**Status:** ready-for-agent` 改為 `**Status:** in-review`（PR 合併後由人類流程改為 `done（PR #N）`）。

- [ ] **Step 5：Commit**

```bash
git add docs/epics/epic-56-pdf-paginated-reading/epic.md docs/epics/epic-56-pdf-paginated-reading/issues.md docs/epics/epic-56-pdf-paginated-reading/plans/plan-issue-2.md
git commit -m "docs(epic-56): Issue 2 開發記錄與全套測試結果

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

（不 push、不發 PR；push 與 PR 由使用者明確指示後才進行。）

---

## Self-Review

**Spec 覆蓋（Issue 2 與 spec「型別與偏好」「設定面板」「`PdfReaderView` 對外介面」）：**
- 列舉、`BookReaderPrefs` 欄位、序列化／`copyWith`／相等／雜湊 → Task 1。
- `ResolvedPreferences` 非空欄位、解析規則 → Task 1。
- 資料庫欄位、v27→v28、`ALTER TABLE`、建表 DDL、無法辨識值視為 null → Task 2。
- 三個重建點（書架、固定版面、PDF 面板）→ Task 3、Task 4；`reader_settings_sheet`（流式 EPUB）與 `reflowableEpubFields` 已查證不需動，後者補測試於 Task 1。
- 設定面板二選一、選逐頁隱藏動畫、切回保留 → Task 4。
- 四份 ARB、硬編碼檢查 → Task 4。
- `PdfReaderView.pdfPageTurnMode`（widget 預設連續捲動）、`ReaderScreen` 傳入、不改渲染 → Task 5。
- 測試要求逐條：序列化往返／`null`＝逐頁／未知名稱降級（T1、T2）；v27→v28 保留、新建含欄位（T2）；三個重建點不清掉（T3、T4）；面板 widget 測試（T4）；l10n 檢查（T4、T6）。

**佔位符掃描：** 無 TBD／TODO；每個程式步驟皆附程式碼或精確的單行錨點。

**型別一致：** `PdfPageTurnMode`、`pdfPageTurnMode`、`'pdf_page_turn_mode'`、鍵 `pdf_settings_page_turn_mode_{paginated,scroll}`、ARB 鍵 `readerPdfPageTurnMode*` 在各 Task 一致；`_pageTurnMode` 為面板內部狀態名。

**已知風險／待確認：** 面板新增一列 chip 後固定 400px 高度的 sheet 是否仍可捲到最底（面板已用 `SingleChildScrollView`，列入真機確認）；`library_screen` 既有缺陷僅回報不修。
