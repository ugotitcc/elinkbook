# Issue 4：查詢面板、`AnnotationToolbar` 按鈕、選字規則、依賴注入 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 使用者在 EPUB／TXT／MD 選字後，工具列出現「查字典」；點下去開底部面板，顯示 Issue 3 的本機查詢結果。

**Architecture:** 面板是純 Flutter 的 `StatefulWidget`，不碰 `InAppWebView`（MDX 是 Issue 6a）。面板收到一個 `Future<DictionaryLookupResponse>`，依回傳型別分派到各狀態畫面。`DictionaryService` 由 `main.dart` 建構一次，放進 `ReaderFeatureDependencies`（ADR 0037）。`reader_screen.dart` 只做三件事：EPUB 端傳 `onLookupPressed`、呼叫 `EBSheetShell.show`、不動選取狀態。

**Tech Stack:** Flutter、既有 `EBSheetShell`、`gen-l10n`（四份 ARB）。不新增套件，不動 `pubspec.yaml`、主資料庫、`main.js`。

**Spec:** `docs/epics/epic-63-dictionary-lookup/spec.md` §3.4（選字處理與狀態）、§3.5、§3.6、§9（驗收 3、4、5、12、26、32）；`issues.md` 的 Issue 4；Issue 3 延後項見 `plan-issue-3.md` 尾端「交給後續 Issue」。

## Global Constraints

- 不新增套件；不動 `pubspec.yaml`、主資料庫（`version: 28`）、`main.js`、`sync_table_specs.dart`。
- 面板沒有動畫：`EBSheetShell.show(isEinkMode: true)` 已用 `AnimationStyle.noAnimation`；面板內部不加任何 `AnimatedXxx`。E-Ink 用邊框，不用陰影。
- 本 Issue 不放 `InAppWebView`。`DictionaryFormat.mdx` 的 HTML 詞條（`EntryBodyKind.html`）目前不會出現，若出現就當純文字顯示，不要渲染 HTML。
- 關閉面板只 `Navigator.pop`，**不得**呼叫 `_handleSelectionCleared`、`_handleCloseAnnotationToolbar`、`FoliateReaderView.clearSelection`。
- FXL 與 CBZ 不新增任何程式：`_handleSelectionChanged` 在 `_isFixedLayout` 時已直接 return（`reader_screen.dart:1879`），工具列不會出現。本 Issue 只加測試證明這點。
- PDF 端 `onLookupPressed` 傳 `null`，工具列不顯示按鈕。
- 字串一律走 `AppLocalizations`；新字串同時加進四份 ARB（`app_zh_TW.arb` 為範本，要附 `@key` 說明）。
- 所有文件與註解用正體中文；commit 訊息不加 `Co-Authored-By`。
- 每個 Task 只跑觸及的測試檔；完整 `flutter test` 只在最後一個 Task 跑一次。

## Review Focus

1. **關閉面板後工具列只有一個**：開面板→關面板，`AnnotationToolbar` 仍是 1 個實例，`onSelectionChanged` 沒有被重新觸發（Task 5）。
2. **原生選取控點不蓋住面板**：只能真機確認（Task 6）。
3. **沒有字典 vs 沒有符合的字典**：兩種情況畫面文字要不同（Task 1、4）。
4. **快速連點兩次「查字典」**：不得疊出兩個面板（Task 5）。
5. **面板開著時 `ReaderScreen` 被銷毀**（返回鍵、跳轉）：`await` 回來後不得再用 `context`（Task 5）。

## 已決定事項（spec 沒寫清楚，本計畫的選擇）

- **M-5（Issue 3 審查延後）：`LookupCompleted` 新增 `bool hasEnabledDictionary`。** `outcomes` 為空且 `hasEnabledDictionary == false` → 「尚未匯入字典」；`outcomes` 為空但 `hasEnabledDictionary == true` → 「沒有適用於這段文字的字典」（例如只有英文字典卻選了中文）。不用 enum，因為只有兩種情況。
- **「前往字典設定」入口本 Issue 不做。** 設定畫面是 Issue 5 才建立。面板的 `onOpenSettings` 是選填 callback，本 Issue 的 `reader_screen.dart` 傳 `null`，面板在 `null` 時不顯示連結；Issue 5 補接線。
- **「線上查詢已關閉」狀態只做畫面。** 目前 `DictionaryService` 不會產生 `OutcomeStatus.skipped`；面板先支援這個狀態（顯示文字，`onOpenSettings` 為 `null` 時不顯示連結），Issue 7 才有資料。
- **拼音轉換放在面板，不放在服務。** `entry.pronunciation` 一律經 `pinyinToneMarks()` 顯示。這個函式對不符合「音節＋聲調數字」的片段原樣保留，所以 JSON／CSV 的 IPA 或英文發音不受影響。資料庫與 `DictionaryEntry` 仍存原文（驗收 37）。
- **面板高度：** 用 `EBSheetShell` 既有的 85% 上限；內容用 `ListView`，不另外設高度。
- **分段選擇器：** 用 `SegmentedButton<String>`（Material 3 內建）。分段多時外包橫向 `SingleChildScrollView`。選中分段的邊框在 E-Ink 模式加粗（`BorderSide(width: 2)`），其他模式用主題預設。
- **預設選中的分段：** 第一個 `status == found` 的分段；都沒有就選第一個。
- **面板開啟時的查詢：** 面板在 `initState` 呼叫一次 `service.lookup(text)`，結果存成 `Future` 欄位。不在 `build` 內呼叫，避免重建時重查。
- **選取文字傳給面板：** 用 `EpubSelectionInfo.text` 原字串；去頭尾標點與長度判斷由 `DictionaryService` 處理（Issue 3），面板不重複判斷。

---

## 檔案結構

```text
app/lib/
├── dictionary/dictionary_service.dart            [修改] LookupCompleted 加 hasEnabledDictionary
├── screens/
│   ├── annotation_toolbar.dart                   [修改] onLookupPressed 與按鈕
│   ├── reader_feature_dependencies.dart          [修改] 加 dictionaryService
│   ├── reader_screen.dart                        [修改] EPUB 端傳 callback、開面板
│   └── widgets/dictionary_lookup_sheet.dart      新增：面板
├── l10n/app_{zh_TW,zh,zh_CN,en}.arb              [修改] 新字串
└── main.dart                                     [修改] 建構 DictionaryService

app/test/
├── dictionary/dictionary_service_test.dart       [修改] hasEnabledDictionary
├── screens/annotation_toolbar_test.dart          [修改] 新按鈕
├── screens/widgets/dictionary_lookup_sheet_test.dart  新增
├── screens/reader_screen_test.dart               [修改] 接線案例
└── support/fake_reader_feature_dependencies.dart [修改] 預設 fake
```

---

### Task 1：`LookupCompleted.hasEnabledDictionary`

**Files:**
- Modify: `app/lib/dictionary/dictionary_service.dart`
- Test: `app/test/dictionary/dictionary_service_test.dart`

**Interfaces:**
- Consumes: Issue 3 的 `DictionaryService`、`LookupCompleted`。
- Produces: `LookupCompleted({required LookupResult result, required bool hasEnabledDictionary})`；`final bool hasEnabledDictionary`（`listSources(enabledOnly: true)` 是否非空）。

- [ ] **Step 1: 寫失敗的測試**

`dictionary_service_test.dart` 新增：
- `test('沒有任何啟用字典：outcomes 為空且 hasEnabledDictionary 為 false')`
- `test('有英文字典、選中文：outcomes 為空但 hasEnabledDictionary 為 true')`
- `test('有符合的字典：hasEnabledDictionary 為 true')`
- 既有案例若直接 `const LookupCompleted(...)` 建構，補上新參數。

- [ ] **Step 2: 執行測試，確認失敗**

Run（在 `app/`）: `flutter test test/dictionary/dictionary_service_test.dart`
Expected: FAIL（`hasEnabledDictionary` 不存在）。

- [ ] **Step 3: 實作**

`LookupCompleted` 加欄位（`required`）。`lookup()` 取得 `sources` 後以 `sources.isNotEmpty` 傳入。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/dictionary app/test/dictionary
git commit -m "feat(epic-63): Issue 4 LookupCompleted 區分沒有字典與沒有適用字典"
```

---

### Task 2：`AnnotationToolbar` 的「查字典」按鈕

**Files:**
- Modify: `app/lib/screens/annotation_toolbar.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`
- Test: `app/test/screens/annotation_toolbar_test.dart`

**Interfaces:**
- Produces: `AnnotationToolbar` 新增選填 `VoidCallback? onLookupPressed`；非 `null` 時，在第二列「複製」之後、「備註」之前顯示 `IconButton`，`Key('annotation_toolbar_lookup')`，`Icons.menu_book_outlined`，tooltip 為 `l10n.readerAnnotationLookupTooltip`。
- l10n：`readerAnnotationLookupTooltip`（zh_TW「查字典」、en「Look up」）。

- [ ] **Step 1: 寫失敗的測試**

`annotation_toolbar_test.dart` 新增：
- `test`／`testWidgets('onLookupPressed 為 null 時不顯示查字典按鈕')`
- `testWidgets('onLookupPressed 非 null：顯示按鈕，點擊觸發一次 callback')`
- `testWidgets('查字典按鈕的 tooltip 隨語言切換')`（zh_TW 與 en 各斷言一次）。沿用該檔既有的 pump 輔助。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/screens/annotation_toolbar_test.dart`
Expected: FAIL。

- [ ] **Step 3: 實作**

四份 ARB 加字串後執行 `flutter gen-l10n`。按鈕寫法比照同列「複製」按鈕。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/annotation_toolbar.dart app/lib/l10n app/test/screens/annotation_toolbar_test.dart
git commit -m "feat(epic-63): Issue 4 工具列新增查字典按鈕"
```

---

### Task 3：依賴注入

**Files:**
- Modify: `app/lib/screens/reader_feature_dependencies.dart`
- Modify: `app/lib/main.dart`
- Create: `app/test/support/fake_dictionary_service.dart`
- Modify: `app/test/support/fake_reader_feature_dependencies.dart`
- Test: `app/test/support/fake_reader_feature_dependencies_test.dart`

**Interfaces:**
- Produces: `ReaderFeatureDependencies.dictionaryService`（`required`，`DictionaryService`，non-null）。
- `main.dart`：用既有的 `defaultDictionaryDatabasePath()`（`dictionary_database.dart:10`）取得路徑，`DictionaryDatabase.open` 開啟 `dictionary.db`，`DictionaryService(store: DictionaryStore(db))` 建構一次，放進 `readerFeatures`。
- 測試工廠：`fakeReaderFeatureDependencies({DictionaryService? dictionaryService})`，預設值為 `FakeDictionaryService()`。
- 新增 `app/test/support/fake_dictionary_service.dart`：`class FakeDictionaryService implements DictionaryService`，不碰資料庫。`lookup` 回傳可由建構子設定的 `DictionaryLookupResponse`（預設 `LookupCompleted`，`outcomes` 為空、`hasEnabledDictionary: false`），並記錄每次呼叫的參數 `calls`。
- **不改 `DictionaryService` 的型別結構。** 已實測：`implements` 一個含私有成員的類別（跨檔案）可以編譯執行，不需要抽介面或改名。

- [ ] **Step 1: 寫失敗的測試**

`fake_reader_feature_dependencies_test.dart` 新增 `test('預設帶有 DictionaryService，且每次呼叫是新實例')`；`test('可覆寫 dictionaryService')`。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/support/fake_reader_feature_dependencies_test.dart`
Expected: FAIL（編譯錯誤：沒有 `dictionaryService`）。

- [ ] **Step 3: 實作**

建立 `FakeDictionaryService`（見 Interfaces），工廠預設用它。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2；再跑 `flutter analyze` 確認所有 `ReaderFeatureDependencies(` 呼叫處（`main.dart` 與測試）都編譯過。
Expected: PASS、No issues found。

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/reader_feature_dependencies.dart app/lib/main.dart app/test/support
git commit -m "feat(epic-63): Issue 4 DictionaryService 加入 ReaderFeatureDependencies"
```

---

### Task 4：`DictionaryLookupSheet`

**Files:**
- Create: `app/lib/screens/widgets/dictionary_lookup_sheet.dart`
- Modify: 四份 ARB
- Test: `app/test/screens/widgets/dictionary_lookup_sheet_test.dart`

**Interfaces:**
- Produces: `class DictionaryLookupSheet extends StatefulWidget`，建構參數 `{required String selectedText, required Future<DictionaryLookupResponse> response, required bool isEinkMode, VoidCallback? onOpenSettings}`；`static Future<void> show(BuildContext, {required String selectedText, required DictionaryService service, required bool isEinkMode, VoidCallback? onOpenSettings})` 內部呼叫 `EBSheetShell.show` 並只呼叫一次 `service.lookup(selectedText)`。
- 固定 Key：`dictionary_lookup_loading`、`dictionary_lookup_rejected`（含 `…_invalid`／`…_too_long` 後綴不需要，用文字斷言）、`dictionary_lookup_empty_no_dictionary`、`dictionary_lookup_empty_no_match`、`dictionary_lookup_segments`（分段選擇器）、`dictionary_lookup_entry_<index>`、`dictionary_lookup_not_found`、`dictionary_lookup_skipped`、`dictionary_lookup_failed`。
- l10n（zh_TW 文字）：標題「查字典」；`dictionaryLookupInvalidSelection`「選取內容含有標點，請重新選取」；`dictionaryLookupTooLong`「選取範圍太長，請縮短後再查」；`dictionaryLookupNoDictionary`「尚未匯入字典」；`dictionaryLookupNoMatchingDictionary`「沒有適用於這段文字的字典」；`dictionaryLookupNotFound`「查無此詞」；`dictionaryLookupOnlineDisabled`「線上查詢已關閉」；`dictionaryLookupFailed`「這本字典查詢失敗。請稍後再試，或到字典設定確認這本字典。」；`dictionaryLookupOpenSettings`「前往字典設定」；`dictionaryLookupLoading`「查詢中…」（en `Looking up…`）；分段狀態後綴 `dictionaryLookupSegmentNotFound`「（無）」、`dictionaryLookupSegmentSkipped`「（略過）」、`dictionaryLookupSegmentFailed`「（失敗）」（en 為 ` (None)`、` (Skipped)`、` (Failed)`）。四份 ARB 都要加，zh_TW 附 `@key` 說明。

顯示規則：
- 等待中：`isEinkMode` 為 `true` 時顯示靜態 `Text(l10n.dictionaryLookupLoading)`（旋轉指示會造成持續局刷與殘影）；否則顯示 `CircularProgressIndicator`。
- 查詢丟出未攔截的例外（`FutureBuilder` 的 `snapshot.hasError`）：顯示 `dictionaryLookupFailed`，不留空白。
- `LookupRejected`：依 `problem` 顯示兩句其中之一。
- `LookupCompleted`，`outcomes` 為空：依 `hasEnabledDictionary` 顯示兩句其中之一。
- `outcomes` 只有一個：不顯示選擇器，直接顯示內容。
- 多個：頂端 `SegmentedButton`。**每個**分段標籤都是 `displayName` 加狀態後綴（不只選中的那個）：`found` 不加、`notFound` 加 `dictionaryLookupSegmentNotFound`、`skipped` 加 `…Skipped`、`failed` 加 `…Failed`。
- 內容：`found` → 每筆詞條一張卡片：詞頭、拼音（經 `pinyinToneMarks`）、詞性、內文（純文字，可選取）；`notFound` → 「查無此詞」；`skipped` → 「線上查詢已關閉」；`failed` → 失敗訊息。
- 底部固定一行來源名稱（`displayName`）；有 `attribution` 時一併顯示。

版面（`EBSheetShell` 的 `child` 外面是 `Flexible`，所以內容要自己貼合高度）：

```dart
Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    if (outcomes.length > 1) segmentedBar,
    Flexible(child: ListView(shrinkWrap: true, children: content)),
    footer,
  ],
)
```

內容少時貼合內容高度，內容多時最高到 85% 螢幕並可捲動。不要用 `Expanded`（短內容也會撐滿），也不要放沒有 `shrinkWrap` 的 `ListView`（高度無限會丟例外）。

- [ ] **Step 1: 寫失敗的測試**

`dictionary_lookup_sheet_test.dart`（用 `pumpLocalizedWidget` 比照其他 widget test；`response` 直接傳 `Future.value(...)`）：
- `等待中顯示載入指示`（用永不完成的 `Completer.future`）。
- `LookupRejected(invalidSelection)` 顯示含標點提示；`LookupRejected(tooLong)` 顯示太長提示。
- `outcomes 為空且 hasEnabledDictionary=false` 顯示「尚未匯入字典」；`true` 顯示「沒有適用於這段文字的字典」。
- `單一 provider：不顯示分段選擇器`。
- `多個 provider：預設選中第一個 found 的分段`（第一個 notFound、第二個 found → 選中第二個）；`都沒有 found：選第一個`。
- `點另一個分段會切換內容`。
- `notFound 分段顯示查無此詞`、`skipped 顯示線上查詢已關閉`、`failed 顯示失敗訊息`。
- `每個分段標籤都帶狀態後綴（包含未選中的）`。
- `E-Ink 模式等待中顯示「查詢中…」文字，不出現 CircularProgressIndicator；一般模式則出現`。
- `response 丟出例外時顯示失敗訊息`。
- `短內容時面板不撐滿、長內容可捲動且不丟 RenderFlex 例外`（用 `tester.takeException()` 為 null 斷言）。
- `onOpenSettings 為 null 時不顯示前往設定連結；非 null 時顯示且可觸發`。
- `拼音 pin1 yin1 顯示為 pīn yīn`；`沒有拼音的詞條不顯示拼音列`。
- `E-Ink 模式：選中分段有邊框、頁面上找不到 AnimatedXxx 類 widget`（至少斷言 `find.byType(AnimatedSwitcher)` 與 `AnimatedContainer` 為空）。
- `show() 只呼叫一次 service.lookup`（用計數的 fake）。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/screens/widgets/dictionary_lookup_sheet_test.dart`
Expected: FAIL（找不到檔案）。

- [ ] **Step 3: 實作**

先加 ARB 並 `flutter gen-l10n`，再寫 widget。`SegmentedButton` 的 `selected` 用分段的 `providerId`。切換只呼叫 `setState`，不重新查詢。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/widgets/dictionary_lookup_sheet.dart app/lib/l10n app/test/screens/widgets
git commit -m "feat(epic-63): Issue 4 字典查詢面板"
```

---

### Task 5：`reader_screen.dart` 接線

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`（新增 group）

**Interfaces:**
- Consumes: Task 2 的 `onLookupPressed`、Task 3 的 `dictionaryService`、Task 4 的 `DictionaryLookupSheet.show`。
- 新增 `_handleLookupPressed(String text)`：用 `_lookupSheetOpen` 旗標擋重複點擊；`await DictionaryLookupSheet.show(...)`；回來後在 `finally` 把旗標還原（不呼叫 `setState`，除非 `mounted`）。
- EPUB 端 `AnnotationToolbar(... onLookupPressed: () => _handleLookupPressed(selection.text))`；PDF 端不傳。

- [ ] **Step 1: 寫失敗的測試**

`reader_screen_test.dart` 新增 `group('Epic 63 Issue 4：查字典')`，沿用 5005 行附近「複製」案例的 pump 與 `onSelectionChanged` 寫法：
- `流式 EPUB 選字後工具列有查字典按鈕`。
- `點查字典：開啟面板，並以選取文字呼叫 DictionaryService.lookup 一次`（fake 記錄呼叫參數）。
- `快速點兩次查字典只開一個面板`。
- `關閉面板後 AnnotationToolbar 仍只有一個實例，且 onSelectionChanged 沒有被再次呼叫`（計數；用 `find.byType(AnnotationToolbar)`）。
- `關閉面板不會呼叫 clearSelection`（沿用該檔既有攔截 `clearSelection` 的方式；若沒有，改斷言 `_currentSelection` 造成的工具列仍在）。
- `FXL（isFixedLayout: true）：呼叫 onSelectionChanged 後找不到查字典按鈕`。
- `CBZ（副檔名 .cbz）：同上`。
- `PDF 選取：工具列沒有查字典按鈕`（沿用該檔 PDF 選取案例的寫法）。
- `面板開著時移除 ReaderScreen 不丟例外`。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "Epic 63 Issue 4"`
Expected: FAIL。

- [ ] **Step 3: 實作**

用 `widget.dependencies.dictionaryService` 取服務（`reader_screen.dart:128` 的欄位名稱）。`isEinkMode` 用 `widget.isEinkMode`。`onOpenSettings` 傳 `null`。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2，再跑 `flutter test test/screens/annotation_toolbar_test.dart test/screens/widgets/dictionary_lookup_sheet_test.dart`。
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-63): Issue 4 閱讀器接上字典查詢面板"
```

---

### Task 6：全套驗證與真機確認

**Files:** 無新增。

- [ ] **Step 1: 靜態檢查**

在 `app/` 執行：
```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
node tool/check_integration_keys.js
```
Expected: 三者皆乾淨。

- [ ] **Step 2: 完整測試（整張計畫唯一一次）**

Run: `flutter test`
Expected: All tests passed。

- [ ] **Step 3: 回歸確認**

- `app/lib/` 沒有 `main.js` 變更：`git diff main -- app/android` 無輸出。
- 主資料庫版本仍為 28：`git diff main -- app/lib/library` 無輸出。

- [ ] **Step 4: 真機確認（人工）**

在真機執行 `flutter run`，匯入一本小字典（JSON），開 EPUB 長按選字：
1. 工具列出現「查字典」，點擊開面板、有結果。
2. 原生選取控點不蓋住面板文字。
3. 關閉面板後，選取範圍與工具列仍在，可接著劃線。
4. 選一段含標點的字、一段超過 8 字的中文，各出現對應提示。
5. E-Ink 模式：面板無動畫，選中分段有邊框。
6. 開 FXL 書與 CBZ，長按沒有工具列。

- [ ] **Step 5: 更新文件並 Commit**

把 `issues.md` Issue 4 狀態改成 `in-review`；`docs/epics/epic-63-dictionary-lookup/plans/plan-issue-4.md` 的 Step 全部勾選。

```bash
git add docs/epics/epic-63-dictionary-lookup
git commit -m "docs(epic-63): Issue 4 實作完成，更新狀態"
```

---

## 交給後續 Issue

- **Issue 5：** 字典設定畫面；接上面板的 `onOpenSettings`（「尚未匯入字典」與「線上查詢已關閉」的入口）。
- **Issue 6a：** `EntryBodyKind.html` 的 `InAppWebView` 顯示、分段切換時丟棄舊 WebView、返回堆疊。
- **Issue 7：** 線上分段（`OutcomeStatus.skipped` 的實際產生處）。

---

## 自我檢查

- **Spec 覆蓋：** 驗收 3（Task 2、5）、4（Task 5 FXL／CBZ 測試）、5（本機查詢本來就不連網，Task 4 無網路程式）、12（Task 4 兩個提示）、26（Task 4 無動畫斷言＋Task 6 真機）、32（Task 4 分段選擇器，一次只顯示一本）。
- **Issue 3 延後項：** M-5（Task 1、4）；拼音轉換（Task 4）；`DictionaryService` 注入（Task 3）。
- **型別一致：** `hasEnabledDictionary` 只在 Task 1 定義，Task 4 使用；`onLookupPressed` 只在 Task 2 定義，Task 5 使用；`DictionaryLookupSheet.show` 只在 Task 4 定義，Task 5 使用。

---

## 計畫審查後修訂（`reviews/review-plan-issue-4.md`）

- **I-1（部分採用）：** 審查說「`implements` 含私有成員的類別會編譯錯誤」，實測不成立（跨檔 `implements` 可編譯執行）。所以不改名、不抽介面；測試替身 `FakeDictionaryService implements DictionaryService`，不碰資料庫。審查要「先拍板」的部分採用。
- **I-2：** 補齊 `dictionaryLookupLoading` 與三個分段狀態後綴字串。
- **I-3：** 每個分段標籤都帶狀態後綴，不只選中的。
- **I-4：** 面板版面寫明 `Column(min)` + `Flexible(ListView(shrinkWrap))`。
- **M-1：** `main.dart` 用既有的 `defaultDictionaryDatabasePath()`。
- **M-2：** 欄位名稱定為 `widget.dependencies`。
- **M-3：** E-Ink 等待中固定顯示靜態文字。
- **M-4：** `response` 丟例外時顯示失敗訊息，並補測試。

