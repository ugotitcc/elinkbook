# Issue 6：偏好指向未下載的內建字型時，閱讀器改用書本字型 實作計畫

> **給執行者（agentic worker）：** 必須使用子技能 superpowers:subagent-driven-development（建議）或 superpowers:executing-plans，逐一執行本計畫的 Task。步驟使用核取方塊（`- [ ]`），完成一個就改成 `- [x]`。

**目標：** 書籍偏好的字型是還沒下載（或已刪除）的思源黑體／思源宋體時，閱讀器實際使用書本字型，和閱讀設定選單顯示的「使用書本字型」一致；書籍偏好本身不改寫，字型下載後重新開書自然恢復。

**架構：**
- 問題出在 `ReaderScreen` 把偏好值原封不動傳給 `FoliateReaderView`（`lib/screens/reader_screen.dart:3312` 的 `fontFamily: resolved.fontFamily`），`main.js` 會注入 `font-family: '<偏好值>' !important`。因為沒有對應的 `@font-face`，WebView 改用系統預設字型，把書本 CSS 的字型蓋掉。
- 修法：`_ReaderScreenState` 新增私有方法 `_renderedFontFamily(String? fontFamily)`，只在傳給閱讀器的那一行過濾。偏好（`_prefs`）、設定面板收到的 `prefs`、存檔內容都不變。

```
書籍偏好 fontFamily = 'SourceHanSerifTC'
        │
        ├─> _prefs ───────────> ReaderSettingsSheet（Issue 4：選單顯示「使用書本字型」）
        │                       存檔內容不變
        │
        └─> _renderedFontFamily()
              ├ 沒有 store ─────────────────> 'SourceHanSerifTC'（維持原行為）
              ├ 內建字型、已下載 ───────────> 'SourceHanSerifTC'
              ├ 內建字型、未下載／讀取失敗 ─> null（書本字型）   ← 本 Issue
              └ 自訂字型／不認得的名稱 ─────> 原值
                          │
                          v
                  FoliateReaderView.fontFamily
```

**技術：** Flutter／Dart。不新增任何套件、不改 `main.js`、不新增在地化字串。

**規格：** `docs/epics/epic-49-downloadable-fonts/issues.md` Issue 6（來源：`reviews/review-issue-4.md` M-1）、`spec.md` 使用者故事 24（「暫時由書本或系統字型補位」）。

**分支：** 從最新的 `main` 建立 `epic-49/issue-6-uninstalled-font-fallback`。

## 全域限制

- 所有指令在 `app/` 目錄執行。
- 啟用中的內建字型只有 `AppFont.sourceHanSans`（`'SourceHanSansTC'`）、`AppFont.sourceHanSerif`（`'SourceHanSerifTC'`）；epic-48 停用的 3 款仍是 `[字型停用]` 註解，不在 `AppFont.values` 裡，本 Issue 不恢復。
- **不改寫偏好**：不可呼叫 `saveBookPrefs`，也不可修改 `_prefs`／`_loaded`／`_resolved`。過濾只發生在傳給 `FoliateReaderView` 的參數上。
- 不改 `ReaderSettingsSheet`、`FoliateReaderView`、`buildFoliatePreferencesMap()`、`main.js`。
- PDF 路徑（`PdfReaderView`）不使用 `fontFamily`，不受影響。
- 程式註解與文件使用正體中文。
- 單一 Task 只跑異動到的測試檔；完整 `flutter test`（約 7 分鐘）只在 Task 2 執行一次。

**計畫決定（issues.md Issue 6 要求寫進計畫）：沒有傳入 `downloadableFontStore` 時照原值傳遞，不過濾。**
- 理由 1：沒有 store 的情境只出現在測試與舊呼叫端；正式環境的 3 個開書入口都有傳 store（Issue 4 程式審查已確認）。
- 理由 2：和 Issue 4 的原則一致——「沒有傳入 store 時開書行為與現在相同」（工單審查 M-1）。若改成一律過濾，沒有 store 時 `_installedFonts` 恆為空，所有內建字型偏好都會被丟掉，等於改變既有測試與呼叫端的行為。
- 對照：**有 store 但 `installedFonts()` 讀取失敗**時，`_installedFonts` 為空、`buildFontFaceCss()` 也不會輸出任何內建字型的 `@font-face`，字型本來就不可能套用，所以**要**過濾（改傳 `null`）。

**與 issues.md 的差異（刻意）：** 無。

## 審查重點（Review Focus）

1. **有 store，但讀取已下載字型失敗**：書仍然要能開，而且畫面應該用書本字型，不是系統預設字型蓋掉書本字型。→ Task 1 測試「installedFonts() 失敗時，內建字型偏好改傳 null」。
2. **閱讀中從設定面板選了一款已下載的內建字型**：選完要立即套用，不可以被過濾掉。→ Task 1 測試「閱讀中改選已下載字型，閱讀器立即收到新字型」。
3. **偏好是自訂字型，而且一款內建字型都沒下載**：自訂字型照常套用，不受本 Issue 影響。→ Task 1 測試「自訂字型照原值傳遞」。
4. **偏好是 epic-48 停用字型的名稱**（例如 `'GuanKiapTsingKhai'`）：不在 `AppFont.values`，照原值傳，行為不變（issues.md 明訂「未知的 family name 行為不變」）。→ Task 1 測試「不認得的字型名稱照原值傳遞」。
5. **沒有傳入 store**（測試與舊呼叫端）：內建字型偏好照原值傳，行為和現在完全相同。→ Task 1 測試「沒有 store 時照原值傳遞」。

---

## 檔案結構

| 檔案 | 動作 | 責任 |
|---|---|---|
| `lib/screens/reader_screen.dart` | 修改 | 新增 `_renderedFontFamily()`；建構 `FoliateReaderView` 時改用它 |
| `test/screens/reader_screen_test.dart` | 修改 | 在既有 group「已下載字型（epic-49 Issue 4）」後新增 group「未下載字型改用書本字型（epic-49 Issue 6）」，8 個測試 |
| `docs/epics/epic-49-downloadable-fonts/plans/plan-issue-6.md`、`issues.md`、`epic.md`、`docs/epics.md` | 修改 | 勾選步驟與進度記錄（Task 2） |

---

### Task 1：`ReaderScreen` 渲染時過濾未下載的內建字型

**Files:**
- Modify: `lib/screens/reader_screen.dart`（新方法放在 `_loadDownloadedFonts()` 之後，約 `:1328`；呼叫點約 `:3312`）
- Test: `test/screens/reader_screen_test.dart`（新 group 放在 group「已下載字型（epic-49 Issue 4）」結尾之後，約 `:6671`）

**Interfaces:**
- Consumes（皆已存在）：
  - `_ReaderScreenState._installedFonts`：`Set<AppFont>`，開書時由 `_loadDownloadedFonts()` 讀入；讀取失敗或沒有 store 時為 `const {}`。
  - `widget.downloadableFontStore`：`DownloadableFontStore?`。
  - `AppFont.values`、`AppFontFamilyName.familyName`（`lib/reader/app_font.dart`，`reader_screen.dart` 已 import）。
  - 測試用：`FakeDownloadableFontStore`（`installed`、`installedFontsGate`）、`FakeCustomFontsRepository`、`FakeReaderPrefsManager`（`saveBookPrefs()`、`bookPrefsByBookId`）；`prefsManager` 是檔案頂層 `setUp` 建立的共用實例（`:171`）。
- Produces：`String? _renderedFontFamily(String? fontFamily)`（私有，僅供本檔使用）。

- [ ] **Step 1：寫測試**

在 `test/screens/reader_screen_test.dart` 的 group「已下載字型（epic-49 Issue 4）」結束的 `});` 之後，新增下面整個 group。它有自己的 `pumpReader`，和上一個 group 的寫法相同（刻意不共用，兩個 group 各自獨立閱讀）。

```dart
  group('未下載字型改用書本字型（epic-49 Issue 6）', () {
    Future<void> pumpReader(WidgetTester tester,
        {DownloadableFontStore? store,
        FakeCustomFontsRepository? customFontsRepository}) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b1',
            prefsManager: prefsManager,
            customFontsRepository: customFontsRepository,
            downloadableFontStore: store,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
    }

    FoliateReaderView readerView(WidgetTester tester) =>
        tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));

    testWidgets('偏好為未下載的內建字型時，閱讀器收到 null，偏好本身不改寫', (tester) async {
      await prefsManager.saveBookPrefs(
          'b1', const BookReaderPrefs(fontFamily: 'SourceHanSerifTC'));
      final store = FakeDownloadableFontStore()..installed.add(AppFont.sourceHanSans);

      await pumpReader(tester, store: store);

      expect(readerView(tester).fontFamily, isNull);
      expect(prefsManager.bookPrefsByBookId['b1']!.fontFamily, 'SourceHanSerifTC');
    });

    testWidgets('偏好為 null（使用書本字型）時，閱讀器收到 null（計畫審查 M-2）',
        (tester) async {
      await prefsManager.saveBookPrefs('b1', const BookReaderPrefs());
      final store = FakeDownloadableFontStore()..installed.add(AppFont.sourceHanSerif);

      await pumpReader(tester, store: store);

      expect(readerView(tester).fontFamily, isNull);
    });

    testWidgets('偏好為已下載的內建字型時，照原值傳遞', (tester) async {
      await prefsManager.saveBookPrefs(
          'b1', const BookReaderPrefs(fontFamily: 'SourceHanSerifTC'));
      final store = FakeDownloadableFontStore()..installed.add(AppFont.sourceHanSerif);

      await pumpReader(tester, store: store);

      expect(readerView(tester).fontFamily, 'SourceHanSerifTC');
    });

    testWidgets('installedFonts() 失敗時，內建字型偏好改傳 null（審查重點 1）', (tester) async {
      await prefsManager.saveBookPrefs(
          'b1', const BookReaderPrefs(fontFamily: 'SourceHanSerifTC'));
      final store = FakeDownloadableFontStore()
        ..installed.add(AppFont.sourceHanSerif)
        ..installedFontsGate = Completer<void>();

      await pumpReader(tester, store: store);
      store.installedFontsGate!.completeError(StateError('denied'));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(readerView(tester).fontFamily, isNull);
    });

    testWidgets('閱讀中改選已下載字型，閱讀器立即收到新字型（審查重點 2）', (tester) async {
      await prefsManager.saveBookPrefs(
          'b1', const BookReaderPrefs(fontFamily: 'SourceHanSerifTC'));
      final store = FakeDownloadableFontStore()..installed.add(AppFont.sourceHanSans);
      await pumpReader(tester, store: store);
      expect(readerView(tester).fontFamily, isNull);

      // 開啟版面設定（比照 Issue 4「已下載字型集合傳給 ReaderSettingsSheet」測試）
      readerView(tester).onLayoutResolved?.call(const EpubLayoutInfo(
            isFixedLayout: false,
            writingMode: WritingMode.horizontal,
          ));
      await tester.pump();
      await tester.tap(find.byKey(const Key('reader_chrome_layout_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final sheet = tester.widget<ReaderSettingsSheet>(find.byType(ReaderSettingsSheet));
      sheet.onChanged(sheet.prefs.copyWith(fontFamily: 'SourceHanSansTC'));
      await tester.pump();

      expect(readerView(tester).fontFamily, 'SourceHanSansTC');
    });

    testWidgets('自訂字型照原值傳遞，即使沒有任何已下載的內建字型（審查重點 3）',
        (tester) async {
      await prefsManager.saveBookPrefs(
          'b1', const BookReaderPrefs(fontFamily: 'KingHwa_OldSong'));

      await pumpReader(tester,
          store: FakeDownloadableFontStore(),
          customFontsRepository: FakeCustomFontsRepository());

      expect(readerView(tester).fontFamily, 'KingHwa_OldSong');
    });

    testWidgets('不認得的字型名稱（含 epic-48 停用字型）照原值傳遞（審查重點 4）',
        (tester) async {
      await prefsManager.saveBookPrefs(
          'b1', const BookReaderPrefs(fontFamily: 'GuanKiapTsingKhai'));

      await pumpReader(tester, store: FakeDownloadableFontStore());

      expect(readerView(tester).fontFamily, 'GuanKiapTsingKhai');
    });

    testWidgets('沒有 store 時照原值傳遞，行為與 Issue 4 相同（審查重點 5）', (tester) async {
      await prefsManager.saveBookPrefs(
          'b1', const BookReaderPrefs(fontFamily: 'SourceHanSerifTC'));

      await pumpReader(tester);

      expect(readerView(tester).fontFamily, 'SourceHanSerifTC');
    });
  });
```

注意：`EpubLayoutInfo`、`WritingMode`、`ReaderSettingsSheet`、`BookReaderPrefs`、`AppFont`、`DownloadableFontStore`、`FakeDownloadableFontStore`、`FakeCustomFontsRepository` 在這個測試檔都已經 import（Issue 4 的 group 已在用），不需要新增 import。若 `flutter analyze` 回報缺少 import，照它指出的檔案補上，放在同類 import 旁邊（`package:` 與 `package:` 放一起，`../support/` 與 `../support/` 放一起）。

- [ ] **Step 2：執行測試，確認紅燈**

執行：`flutter test test/screens/reader_screen_test.dart --plain-name "未下載字型改用書本字型"`

預期：**3 個失敗**，其餘 5 個通過。
- 失敗：「偏好為未下載的內建字型時，閱讀器收到 null…」、「installedFonts() 失敗時…改傳 null」、「閱讀中改選已下載字型…」（這個測試開頭先斷言開書時是 `null`，所以同樣在那一行失敗），錯誤都是 `Expected: null  Actual: 'SourceHanSerifTC'`。
- 通過：其餘 5 個描述的是現在就正確、本 Issue 不可以破壞的行為。

如果失敗數不是 3，或失敗原因不是上面這個 `Actual: 'SourceHanSerifTC'`，先停下來查原因，不要進入 Step 3。

- [ ] **Step 3：實作**

在 `lib/screens/reader_screen.dart` 的 `_loadDownloadedFonts()` 方法結束之後新增：

```dart
  /// 實際交給閱讀器渲染的字型家族名稱（epic-49 Issue 6，Issue 4 程式審查 M-1）。
  ///
  /// 偏好指向還沒下載（或已刪除）的內建字型時改傳 null，讓書本字型生效，和設定
  /// 面板顯示的「使用書本字型」一致；否則 main.js 會注入一個沒有 @font-face 的
  /// 字型名稱，由系統預設字型蓋掉書本字型。只影響渲染、不改寫偏好，字型下載後
  /// 重新開書自然恢復。
  ///
  /// - 沒有傳入 store（測試與舊呼叫端）：照原值傳，維持 Issue 4 之前的行為。
  /// - 讀取已下載字型失敗：_installedFonts 為空，@font-face 也不會輸出，同樣改傳 null。
  /// - 自訂字型與不認得的名稱（含 epic-48 停用的字型）：照原值傳。
  String? _renderedFontFamily(String? fontFamily) {
    // 沒有 store，或偏好本來就是「使用書本字型」：照原值傳（計畫審查 M-1）
    if (widget.downloadableFontStore == null || fontFamily == null) return fontFamily;
    final isBuiltIn = AppFont.values.any((f) => f.familyName == fontFamily);
    final isInstalled = _installedFonts.any((f) => f.familyName == fontFamily);
    return isBuiltIn && !isInstalled ? null : fontFamily;
  }
```

再把 `_buildNativeView()` 裡建構 `FoliateReaderView` 的這一行：

```dart
          fontFamily: resolved.fontFamily,
```

改成：

```dart
          fontFamily: _renderedFontFamily(resolved.fontFamily),
```

`reader_screen.dart` 只有這一處把 `fontFamily` 傳給閱讀器（可用 `git grep -n "fontFamily: resolved" -- lib/screens/reader_screen.dart` 確認只有一筆）。

- [ ] **Step 4：執行測試，確認綠燈**

執行：`flutter test test/screens/reader_screen_test.dart --plain-name "未下載字型改用書本字型"`

預期：8 個全部通過。

- [ ] **Step 5：變異檢查**

暫時把 `_renderedFontFamily()` 第一行的條件改成只剩 `if (fontFamily == null) return fontFamily;`（拿掉「沒有 store」的判斷），再跑 Step 4 的指令。

預期：只有「沒有 store 時照原值傳遞…」失敗（`Expected: 'SourceHanSerifTC'  Actual: <null>`）。確認後**改回**，再跑一次 Step 4，確認 8 個全部通過。把結果（哪個測試失敗）記下來，Task 2 寫進 `epic.md`。

- [ ] **Step 6：跑整個測試檔與靜態檢查**

執行：
```bash
flutter test test/screens/reader_screen_test.dart
flutter analyze
```

預期：`reader_screen_test.dart` 全部通過（Issue 4 合併時是 242 個，加上本 Issue 8 個，共 250 個）；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 7：Commit**

```bash
git add lib/screens/reader_screen.dart test/screens/reader_screen_test.dart ../docs/epics/epic-49-downloadable-fonts/plans/plan-issue-6.md
git commit -m "fix(reader): 偏好指向未下載的內建字型時閱讀器改用書本字型，不改寫偏好（epic-49 Issue 6）"
```

commit 訊息結尾加上 `Co-Authored-By` 署名行（依當次工作階段的 system reminder）。

---

### Task 2：整體驗證與進度記錄

**Files:**
- Modify: `docs/epics/epic-49-downloadable-fonts/plans/plan-issue-6.md`（勾選步驟）
- Modify: `docs/epics/epic-49-downloadable-fonts/issues.md`（Issue 6 的 `**Status:**`）
- Modify: `docs/epics/epic-49-downloadable-fonts/epic.md`（開發記錄）
- Modify: `docs/epics.md`（epic-49 那一列的備註）

**Interfaces:**
- Consumes：Task 1 的變異檢查結果與測試數字。
- Produces：無。

- [ ] **Step 1：完整測試**

執行：`flutter test`

預期：`All tests passed!`。通過數約為 2872＋8＝2880（Issue 4 合併前為 2872 通過、1 跳過；實際數字以輸出為準，照實記錄）。

- [ ] **Step 2：靜態檢查與 l10n 檢查**

執行：
```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```

預期：`No issues found!`；l10n 檢查兩行都是 `PASS`（本 Issue 沒有新增字串，只是確認沒有破壞）。

- [ ] **Step 3：更新文件**

1. `issues.md` 的 Issue 6：`**Status:** ready-for-agent` 改成 `**Status:** completed`。
2. `epic.md` 的「開發記錄」最後新增一段，格式比照既有的「Issue 4 完成」段落：
   ```markdown
   **2026-MM-DD Issue 6 完成**（分支 `epic-49/issue-6-uninstalled-font-fallback`，待 PR 合併）

   - `ReaderScreen` 新增 `_renderedFontFamily()`：有 store 且偏好指向未下載的內建字型時，傳給 `FoliateReaderView` 的 `fontFamily` 改為 `null`（書本字型）；不改寫偏好。沒有 store 時照原值傳（計畫決定）；讀取已下載字型失敗時也改傳 `null`；自訂字型與不認得的名稱照原值傳。
   - 新增 8 個測試（`reader_screen_test.dart` group「未下載字型改用書本字型（epic-49 Issue 6）」）。
   - 變異檢查：<照實填寫 Task 1 Step 5 的結果>。
   - 完整 `flutter test`：<通過數> 通過、<跳過數> 跳過；`flutter analyze`：`No issues found!`；l10n 檢查：兩行 PASS。
   ```
   日期用實際完成日期；角括號內照實填寫。
3. `docs/epics.md` epic-49 那一列的備註改成：`Issue 1～4、6 已完成，待 Issue 5 真機驗證`。
4. 本計畫檔所有已完成的步驟改成 `- [x]`。

- [ ] **Step 4：Commit**

```bash
git add ../docs/epics.md ../docs/epics/epic-49-downloadable-fonts/issues.md ../docs/epics/epic-49-downloadable-fonts/epic.md ../docs/epics/epic-49-downloadable-fonts/plans/plan-issue-6.md
git commit -m "docs(epic-49): 記錄 Issue 6 完成"
```

commit 訊息結尾加上 `Co-Authored-By` 署名行。
