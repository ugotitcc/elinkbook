# Issue 2：標題字型渲染層實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** 讓 Issue 1 存好的 `BookReaderPrefs.headingFontFamily` 真正套用到閱讀畫面：`ReaderScreen` 只在「流式 Foliate 格式」把「可用字型過濾後的標題字型」傳給 `FoliateReaderView`，再經 `buildFoliatePreferencesMap` 送進 `main.js`，由 `buildOverrideCss` 對 `h1`–`h6` **含其後代**輸出 `font-family` 規則；並重新產生 `foliate/legacy/` 降級副本。本張**不加 UI、不動 l10n、不動資料層**（Issue 3、4）。

**Architecture：** 與 `fontFamily`／`firstLineIndent` 同一條路徑：`ReaderScreen._buildNativeView` → `FoliateReaderView` 建構子欄位 → `buildFoliatePreferencesMap`／`foliatePreferencesChanged` → JS `window.applyPreferences` → `buildOverrideCss`。差異只有兩點：(1) 傳遞條件要排除 FXL 與 CBZ（含舊資料）；(2) JS 規則的輸出**順序**有語意（依賴同特異度後者勝）。

**Tech Stack：** Flutter 3.47.9／Dart 3.13.7、`flutter_test`；`foliate/main.js`（ES module，跑在 `InAppWebView`）；`app/tool/foliate_touch_harness`（Puppeteer＋headless Chromium，Node）；`app/tool/foliate_legacy`（esbuild，目標 chrome83，pnpm）。指令一律在 `C:\Users\fycdc\AI\elinkBook\app` 下執行（另有註明者除外）。

**Spec：** `docs/epics/epic-68-heading-font/spec.md` §2（退回語意）、§3（渲染契約）；決策背景 `design.md` D3、D4、D8、D9、D14；驗收 `issues.md` Issue 2；legacy 流程 `docs/adr/0043-foliate-legacy-downlevel-for-old-webview.md`。

## 已實際查證的現況（行號僅供參考，一律以字串定位）

| 位置 | 查證結果 |
|---|---|
| `lib/reader/foliate_reader_view.dart` | `buildFoliatePreferencesMap`：`if (view.fontFamily != null) map['fontFamily'] = view.fontFamily!;`（約 162）；`foliatePreferencesChanged`：`oldView.fontFamily != newView.fontFamily \|\|`（約 213）；欄位 `final String? fontFamily;`（約 318）；建構子 `this.fontFamily,`（約 426）；`initState` 以 `jsonEncode(buildFoliatePreferencesMap(widget))` 帶初始偏好（約 670），`didUpdateWidget` 在 `foliatePreferencesChanged` 為真時呼叫 `window.applyPreferences(...)`（約 1000）。 |
| `lib/screens/reader_screen.dart` `_buildNativeView` | `case BookFormat.epub/azw3/cbz/txt/md:` 共用一個 `FoliateReaderView(...)`；`fontFamily: fonts.effectiveFamily(resolved.fontFamily),`（約 2925）；`firstLineIndent: _isFixedLayout ? null : resolved.firstLineIndent,`（約 2930）。 |
| FXL／CBZ 判斷 | `_isFixedLayout`（約 298）只在**宣告值為 true**（`widget.isFixedLayout == true`，約 605）或原生回報 FXL 後才為 true；CBZ 宣告值為 null 時 `resolveEngineDispatch` 回 `EngineDispatchKnown(true)`，只設 `_dispatchedIsFixedLayout = true`，**`_isFixedLayout` 仍為 false**。EPUB 宣告值為 null 時 `_dispatchedIsFixedLayout` 由 `detectAndCacheEpubLayout` 非同步決定，偵測為 FXL 時同樣 `_isFixedLayout` 仍為 false。故沿用 `firstLineIndent` 的條件會讓「舊資料 CBZ」與「宣告 null 的 FXL EPUB」誤收到標題字型。 |
| `foliate/main.js` `buildOverrideCss` | 主字型規則：`if (prefs.fontFamily) { rules.push(\`${selector} { font-family: '${prefs.fontFamily}' !important; }\`) }`（約 445）；`selector` 為 `publisherStyles === false ? '*' : 'body, p, div, li, span, td, th, blockquote, dd, dt, a, h1…h6'`。`@font-face` 由 `fontFaceCss`（URL 參數）一次宣告全部可用字型，與選中哪個無關，標題字型不需另外宣告字型檔。 |
| `foliate/legacy/` | 由 `app/tool/foliate_legacy/build.mjs`（esbuild 0.25.12、target `chrome83`）自 `foliate/` 產生，輸出 `foliate/legacy/`，`legacy/main.js` 已含 `prefs.fontFamily` 規則（約 230）。`app/tool/foliate_legacy` 無 `node_modules`，須先 `pnpm install`。 |
| `test/reader/foliate_legacy_assets_test.dart` | 目前只檢查「每個原始 .js 有對應降級副本」「無私有方法宣告」「無 `:is(`」「載入分流」——**不比對內容是否與原始檔同步**，所以忘了重建 legacy 時目前不會變紅；本計畫 Task 4 補一條內容守衛。 |
| `app/tool/foliate_touch_harness` | `lib/harness.mjs` 的 `launchHarnessPage({ fixtureBuffer, prefs, viewport })` 載入**原始** `foliate/main.js`（非 legacy）；既有 `scenario-first-line-indent-exclusions.mjs` 為記憶體 EPUB（`buildStoredZip`）＋`window.applyPreferences` 切換＋`report()` 的完整範例；`run-all.mjs` 自動收集 `scenario-*.mjs`；README 有「場景清單」。 |
| 既有測試位置 | `test/reader/foliate_reader_view_test.dart`（`group('buildFoliatePreferencesMap')`、`group('foliatePreferencesChanged')`）；`test/screens/reader_screen_test.dart`（`group('未下載字型改用書本字型（epic-49 Issue 6）')` 的 `readerView(tester).fontFamily` 模式；`pumpWithIndentPrefs` 的 FXL 傳遞模式；CBZ／TXT 的 `isFixedLayout: null` 測試）。 |

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **傳遞語意（spec §3.1、D4、D8）**：`headingFontFamily` 傳給 `FoliateReaderView` 的值為
  `isFixedLayoutEngine ? null : fonts.effectiveFamily(resolved.headingFontFamily)`，
  其中 `isFixedLayoutEngine = _isFixedLayout || _dispatchedIsFixedLayout == true || format == BookFormat.cbz`。
  **不可只用 `_isFixedLayout`**。標題字型不可用時傳 null、**不改寫偏好**。
- **不順手改 `firstLineIndent` 的條件**（同樣有舊資料 CBZ 缺口，但屬既有行為、不在本張範圍；只在審查報告／最終回報提及，不修改）。
- **JS 規則順序（spec §3.2）**：標題規則必須在主字型規則**之後** push。`h1 *`／`h1` 的特異度 (0,0,1) 與主字型 selector 中的 `span`、`a`、`h1`…`h6`（(0,0,1)）相同，且都是 `!important`，**由後出現者勝**；停用書本 CSS 時主規則為 `*`（0），標題規則自然勝出。不處理字重（D9）。家族名稱含單引號的處理沿用主字型規則既有作法，不擴大。
- **legacy 副本不可手改**：只能 `pnpm build` 重新產生；`main.js` 定稿後才重建，且重建結果與 `main.js` 修改**同一 Issue 內**一併 commit（ADR 0043）。
- **測試範圍（CLAUDE.md）**：每個 Task 只跑觸及的測試檔，**本張不跑完整 `flutter test`**（Epic 最後一張 Issue 4 才跑）。harness 與 legacy 驗證屬 Node 工具，不在 `flutter test` 內。
- **每個 Task 結束都必須 commit，且該 commit 可編譯、`flutter analyze` 乾淨、被觸及的測試全綠**（harness 場景先紅後綠的紅燈階段只存在於 Task 內部、不 commit）。
- **Windows 環境**：
  - Node 步驟一律用 **PowerShell 工具**；每個新的 PowerShell 工作階段先 `$env:PATH = "$env:PNPM_HOME;$env:PATH"`，`node --version` 應為 v24.x（見 memory `reference_windows-node-via-pnpm.md`）。**不要用 `pnpm exec`**；harness 用 `node`／`npx`。
  - 多數原始檔是 CRLF：Edit 的 `old_string` 不要含換行；不對整個既有檔跑 `dart format`。
- **Git**：commit 訊息正體中文、**不加 `Co-Authored-By`**；分支 `feat/epic-68-heading-font`（已存在，不新開）；`git add` 一律明確列檔，**絕不** `git add app`／`git add -A`／`git add .`，**絕不**加入 `.claude/settings.json`（工作目錄有使用者本機未提交修改）。計畫與實作同分支同 PR，不另開文件分支。

## Review Focus

1. **FXL／CBZ 排除條件**：舊資料 CBZ（宣告 null）與「宣告 null、偵測為 FXL」的 EPUB 是否都傳 null。→ Task 2 兩個專屬測試；反向驗證改回 `_isFixedLayout` 時二者必紅。
2. **規則順序**：標題規則在主字型規則之前時，`h1>span`／`h1>a`／`h2>a>span` 會被主字型蓋掉。→ Task 3 harness 場景 A 斷言＋反向驗證（把標題 push 移到主字型之前，場景必紅）。
3. **`foliatePreferencesChanged` 漏欄位**：只改標題字型時不重送偏好，須重開書才生效。→ Task 1 專屬測試。
4. **取消標題字型後規則必須消失**：`setStyles` 每次整包取代，因此傳 null（不帶 key）即消失；harness 場景 C 驗證。
5. **legacy 與原始檔同步**：忘了重建不會被現有測試抓到。→ Task 4 新增內容守衛（先紅後綠），並確認重建前基準乾淨、重建只影響 `legacy/main.js`。
6. **範圍**：`git diff 3d8bafee..HEAD --stat -- app/lib` 只應出現 `foliate_reader_view.dart`、`reader_screen.dart`（本張），不得出現 `*.arb`、設定面板、資料庫檔。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/foliate_reader_view.dart` | 修改 | 欄位、建構子、`buildFoliatePreferencesMap`、`foliatePreferencesChanged` |
| `app/test/reader/foliate_reader_view_test.dart` | 修改 | map 與 changed 測試 |
| `app/lib/screens/reader_screen.dart` | 修改 | 傳遞（排除 FXL／CBZ） |
| `app/test/screens/reader_screen_test.dart` | 修改 | 傳遞測試（新 group） |
| `app/android/app/src/main/assets/foliate/main.js` | 修改 | `buildOverrideCss` 標題規則 |
| `app/tool/foliate_touch_harness/scenario-heading-font.mjs` | 新增 | headless Chromium 回歸場景 |
| `app/tool/foliate_touch_harness/README.md` | 修改 | 「場景清單」補一條 |
| `app/android/app/src/main/assets/foliate/legacy/main.js` | 重新產生 | 由 `pnpm build`，不手改 |
| `app/test/reader/foliate_legacy_assets_test.dart` | 修改 | legacy 含標題規則且順序正確的內容守衛 |
| `docs/epics/epic-68-heading-font/issues.md`、`epic.md` | 修改 | 狀態與進度 |

測試字串統一：主字型 `'SourceHanSerifTC'`（Dart 測試）、標題字型 `'TaiwanPearl'`（與主字型不同，才能抓到「被主字型覆蓋」）；harness 用 `'BodyFont'`／`'HeadFont'`。

---

### Task 0：提交本計畫

**Files：** `docs/epics/epic-68-heading-font/plans/plan-issue-2.md`

- [x] **Step 1：** 確認分支 `git branch --show-current` 為 `feat/epic-68-heading-font`。
- [x] **Step 2：** 只提交本計畫：
  ```bash
  git add docs/epics/epic-68-heading-font/plans/plan-issue-2.md
  git commit -m "docs(epic-68): Issue 2 渲染層實作計畫"
  ```

---

### Task 1：`FoliateReaderView` 欄位、偏好 map、變更偵測

> 本 Task 純 Dart、`reader_screen.dart` 尚未傳值，新欄位預設 null，既有行為不變，commit 即綠。

**Files：**
- 修改：`app/lib/reader/foliate_reader_view.dart`
- 修改：`app/test/reader/foliate_reader_view_test.dart`

- [x] **Step 1（紅，先寫測試）：** 在 `foliate_reader_view_test.dart`：
  - `group('buildFoliatePreferencesMap')` 內，緊接 `firstLineIndent 非 null 時 map 含 firstLineIndent…`（以字串定位）之後新增：
    1. `headingFontFamily 非 null 時 map 含 headingFontFamily，且與 fontFamily 各自獨立（epic-68 Issue 2）`：建構 `FoliateReaderView(filePath: '/tmp/sample.epub', onPageRendered: _noop, onError: _noopError, fontFamily: 'SourceHanSerifTC', headingFontFamily: 'TaiwanPearl')`，`expect(buildFoliatePreferencesMap(view), {'fontFamily': 'SourceHanSerifTC', 'headingFontFamily': 'TaiwanPearl', 'isLandscape': false, 'isComicBookHint': false})`。
    2. `headingFontFamily 為 null 時 map 不含該 key（跟隨主字型，epic-68 Issue 2）`：只給 `fontFamily`，`expect(buildFoliatePreferencesMap(view).containsKey('headingFontFamily'), isFalse)`。
    3. `只有標題字型、沒有主字型時 map 只含 headingFontFamily`（主字型為「使用書本字型」的情境）：`expect(map, {'headingFontFamily': 'TaiwanPearl', 'isLandscape': false, 'isComicBookHint': false})`。
  - `group('foliatePreferencesChanged')` 內，緊接 `firstLineIndent 變動回傳 true…` 之後新增：
    1. `只有 headingFontFamily 變動回傳 true（epic-68 Issue 2：改標題字型要重送偏好）`：兩個 view 其他欄位全同（皆 `fontFamily: 'SourceHanSerifTC'`），一個 `headingFontFamily: 'TaiwanPearl'`、另一個 null → `isTrue`；兩個不同非 null 值 → `isTrue`。
    2. `headingFontFamily 相同回傳 false`（兩者皆 `'TaiwanPearl'`）→ `isFalse`。
    3. `headingFontFamily 由有值變成 null：回傳 true，且新偏好不含 headingFontFamily 鍵`（比照既有「fontFamily 由有值變成 null」測試；main.js 每次整包取代覆蓋 CSS，不帶 key 規則就會消失）。
- [x] **Step 2（確認紅）：**
  ```bash
  flutter test test/reader/foliate_reader_view_test.dart
  ```
  預期：**編譯失敗**（`headingFontFamily` 不是 `FoliateReaderView` 的參數）。
- [x] **Step 3（綠）：** 修改 `foliate_reader_view.dart`（以字串定位）：
  - 欄位：緊接 `final String? fontFamily;` 之後新增（含正體中文 doc 註解，說明 null＝跟隨主字型、由呼叫端已過濾可用性、FXL／CBZ 恆為 null）：`final String? headingFontFamily;`
  - 建構子：緊接 `this.fontFamily,` 之後 `this.headingFontFamily,`。
  - `buildFoliatePreferencesMap`：緊接 `if (view.fontFamily != null) map['fontFamily'] = view.fontFamily!;` 之後：
    ```dart
    // epic-68 Issue 2：null＝跟隨主字型，不輸出 key，main.js 就不產生標題規則。
    if (view.headingFontFamily != null) {
      map['headingFontFamily'] = view.headingFontFamily!;
    }
    ```
  - `foliatePreferencesChanged`：緊接 `oldView.fontFamily != newView.fontFamily ||` 之後新增 `oldView.headingFontFamily != newView.headingFontFamily ||`。
- [x] **Step 4（確認綠）：**
  ```bash
  flutter test test/reader/foliate_reader_view_test.dart
  flutter analyze
  ```
  預期：全綠、`No issues found!`。
- [x] **Step 5（反向驗證，暫時修改、驗完還原，不 commit）：** 把 `foliatePreferencesChanged` 新增的那一行暫時註解 → Step 1 的 changed 測試 1 與 3 必須變紅（測試 2 仍綠）；還原後再跑一次確認綠。把 `buildFoliatePreferencesMap` 新增的 `if` 暫時註解 → map 測試 1、3 必須變紅。若任一項沒變紅，改寫該測試直到能抓到。
- [x] **Step 6：commit：**
  ```bash
  git add app/lib/reader/foliate_reader_view.dart app/test/reader/foliate_reader_view_test.dart
  git commit -m "feat(epic-68): FoliateReaderView 新增標題字型參數並納入偏好 map 與變更偵測"
  ```

---

### Task 2：`ReaderScreen` 傳遞標題字型（排除 FXL 與 CBZ，含舊資料）

**Files：**
- 修改：`app/lib/screens/reader_screen.dart`
- 修改：`app/test/screens/reader_screen_test.dart`

- [x] **Step 1（紅，先寫測試）：** 在 `reader_screen_test.dart` 緊接 `group('未下載字型改用書本字型（epic-49 Issue 6）'…)` 結束之後（以字串定位，避免插入既有 group 內）新增 `group('標題字型傳遞（epic-68 Issue 2）', () { … })`。group 內自備 helper（比照 epic-49 group 與 `pumpWithIndentPrefs`，`prefsManager` 為檔案既有 `setUp` 變數）：
  ```dart
  Future<FoliateReaderView> pumpHeading(
    WidgetTester tester, {
    required String filePath,
    bool? isFixedLayout,
    FakeDownloadableFontStore? store,
    FakeLibraryRepository? libraryRepository,
  }) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: ReaderScreen(
        filePath: filePath,
        bookId: 'b1',
        isFixedLayout: isFixedLayout,
        dependencies: fakeReaderFeatureDependencies(
          prefsManager: prefsManager,
          downloadableFontStore: store,
          libraryRepository: libraryRepository,
        ),
      ),
    ));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    return tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
  }
  ```
  種子偏好一律 `const BookReaderPrefs(fontFamily: 'SourceHanSerifTC', headingFontFamily: 'TaiwanPearl')`，`store` 一律 `FakeDownloadableFontStore()..installed.addAll([AppFont.sourceHanSerif, AppFont.taiwanPearl])`（`AppFont` 成員名稱以 `grep -n "taiwan\|Pearl" lib/reader/app_font.dart`（實際檔名以 grep 為準）確認；若成員名不同，以實際為準，並確認 `'TaiwanPearl'` 對應的 `familyName` 相同，否則整組種子改用已存在的兩個內建字型名稱）。測試：
  1. `流式 EPUB（isFixedLayout: false）：標題字型已下載，照原值傳遞`：`view.headingFontFamily == 'TaiwanPearl'` 且 `view.fontFamily == 'SourceHanSerifTC'`。
  2. `流式 EPUB：標題字型未下載時傳 null，偏好本身不改寫`：store 只裝主字型；`view.headingFontFamily` isNull，`prefsManager.bookPrefsByBookId['b1']!.headingFontFamily == 'TaiwanPearl'`（D8、ADR 0035）。
  3. `標題字型為 null（跟隨主字型）時傳 null`：種子只有 `fontFamily`；`isFixedLayout: false`。
  4. `FXL EPUB（isFixedLayout: true）：不傳標題字型`：`filePath: 'test/fixtures/sample_fixed_layout.epub'`。
  5. `CBZ 宣告值為 null 的舊資料：不傳標題字型`：`filePath: 'test/fixtures/sample.cbz'`、`isFixedLayout: null`（明確寫出），`view.headingFontFamily` isNull；同時 `expect(view.isFixedLayoutHint, isTrue)` 確認這確實是 CBZ 被防禦性視為固定版面的情境（非測試自己走偏）。
  6. `EPUB 宣告值為 null、偵測為 FXL：不傳標題字型`：`filePath: 'test/fixtures/sample.epub'`、`isFixedLayout: null`（明確寫出）、`libraryRepository: FakeLibraryRepository(detectedIsFixedLayout: true)`，`view.headingFontFamily` isNull。
  7. `TXT／AZW3 宣告值為 null：視同流式，照原值傳遞`：`sample_synth.txt` 與 `sample.azw3` 各一，`view.headingFontFamily == 'TaiwanPearl'`（TXT／MD 合成後章名為 `h*`，D3）。
- [x] **Step 2（確認紅）：**
  ```bash
  flutter test test/screens/reader_screen_test.dart --plain-name "標題字型傳遞（epic-68 Issue 2）"
  ```
  預期：此時 `reader_screen.dart` 尚未傳值，`FoliateReaderView.headingFontFamily` 恆 null → 測試 1、7 紅（預期 `'TaiwanPearl'` 得 null），測試 2–6 此時直接綠（它們預期 null，屬回歸守衛，由 Step 5 反向驗證保證有效）。若編譯失敗，檢查 Task 1 已完成。
- [x] **Step 3（綠）：** 修改 `reader_screen.dart` `_buildNativeView`：
  - 在 `final textConversionMode = …` 之後（`switch (format)` 之前，以字串定位）新增：
    ```dart
    // epic-68 Issue 2：標題字型只套用流式 Foliate 格式（D4）。不能只看 _isFixedLayout——
    // 它只在「宣告值為 true」或原生回報 FXL 後才為 true；舊資料 CBZ（宣告 null，被防禦性
    // 視為固定版面）與「宣告 null、偵測為 FXL」的 EPUB 只會讓 _dispatchedIsFixedLayout
    // 為 true，_isFixedLayout 仍為 false。
    final isFixedLayoutEngine = _isFixedLayout ||
        _dispatchedIsFixedLayout == true ||
        format == BookFormat.cbz;
    ```
  - 緊接 `fontFamily: fonts.effectiveFamily(resolved.fontFamily),` 之後新增：
    ```dart
    headingFontFamily: isFixedLayoutEngine
        ? null
        : fonts.effectiveFamily(resolved.headingFontFamily),
    ```
  - **不要**改 `firstLineIndent` 那一行。
- [x] **Step 4（確認綠）：**
  ```bash
  flutter test test/screens/reader_screen_test.dart --plain-name "標題字型傳遞（epic-68 Issue 2）"
  flutter test test/screens/reader_screen_test.dart
  flutter analyze
  ```
  預期全綠（第二行整檔，確認未回歸；整檔較久，可接受）。
- [x] **Step 5（反向驗證，暫時修改、驗完還原，不 commit）：** 把條件暫時改成只有 `_isFixedLayout` → 測試 5、6 必須變紅（測試 4 仍綠，因宣告 true 時 `_isFixedLayout` 為 true）；改成「無條件傳」→ 測試 4、5、6 必須變紅；把 `fonts.effectiveFamily(` 暫時換成直接傳 `resolved.headingFontFamily` → 測試 2 必須變紅。還原後再跑一次確認綠。任一項沒變紅就改寫該測試。
- [x] **Step 6：commit：**
  ```bash
  git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
  git commit -m "feat(epic-68): ReaderScreen 傳遞標題字型，FXL 與 CBZ（含舊資料）一律不套用"
  ```

---

### Task 3：`main.js` 標題規則（harness 場景先紅後綠）

> 此 Task 的 commit 同時含場景與 `main.js` 修改（場景單獨提交會是紅的）。`legacy/` 在 Task 4 重建。

**Files：**
- 新增：`app/tool/foliate_touch_harness/scenario-heading-font.mjs`
- 修改：`app/android/app/src/main/assets/foliate/main.js`
- 修改：`app/tool/foliate_touch_harness/README.md`

- [x] **Step 0（環境與基準，PowerShell）：**
  ```powershell
  $env:PATH = "$env:PNPM_HOME;$env:PATH"
  node --version   # 應為 v24.x
  cd C:\Users\fycdc\AI\elinkBook\app\tool\foliate_touch_harness
  Test-Path node_modules   # 應為 True；否則 npm install
  npx puppeteer browsers install chrome   # 第一次才需要
  node run-all.mjs         # 基準：既有場景應「全部 PASS」，確認環境可用且與本張無關的失敗先記下來
  ```
  若基準就有場景失敗，先記錄於 `epic.md` 進度，不要把既有失敗誤判成本張回歸。
- [x] **Step 1（寫場景，先不改 `main.js`）：** 新增 `scenario-heading-font.mjs`，風格比照 `scenario-first-line-indent-exclusions.mjs`（檔頭中文註解說明目的與情境、`import { launchHarnessPage, buildStoredZip, report } from './lib/harness.mjs'`、記憶體 EPUB、`applyPrefs` 輔助、`main().catch(...)`）。內容：
  - **Fixture（單章，內文需 > 20 字元，harness 要等內文載入）**：`style.css` 為 `h1 span { font-family: 'BookSpan'; } h2 a { font-family: 'BookLink'; }`（書本自己在標題後代指定字型，證明被覆蓋）。`chapter1.xhtml` 每個目標元素給 `id`：
    ```
    <h1 id="t-h1">純標題</h1>
    <h1><span id="t-h1-span">標題內的 span</span></h1>
    <h1><a id="t-h1-a" href="#x">標題內的連結</a></h1>
    <h2><a href="#x"><span id="t-h2-a-span">巢狀 a 與 span</span></a></h2>
    <h3 id="t-h3">三</h3> <h4 id="t-h4">四</h4> <h5 id="t-h5">五</h5> <h6 id="t-h6">六</h6>
    <p id="b-p">這是一般段落，字數要夠多，harness 才會認為內文已載入完成。<span id="b-p-span">段落內 span</span><a id="b-p-a" href="#x">段落內連結</a></p>
    <div id="b-div">一般 div 文字</div>
    ```
    其餘 OPF／nav 比照既有場景（`dc:identifier` 用新的 `urn:uuid:00000000-0000-0000-0000-000000000068`）。
  - 常數 `HEADINGS = ['t-h1','t-h1-span','t-h1-a','t-h2-a-span','t-h3','t-h4','t-h5','t-h6']`、`BODIES = ['b-p','b-p-span','b-p-a','b-div']`。
  - `readFamilies(page, ids)`：`page.evaluate` 內以 `view.renderer.getContents()[0].doc` 取元素，回傳 `{id: getComputedStyle(el).fontFamily.replace(/["']/g, '')}`。**只比對 computed `font-family` 字串，不載入真實字型**。
  - `BASE_PREFS` 同既有場景。以 `launchHarnessPage({ fixtureBuffer, prefs: { fontFamily: 'BodyFont', headingFontFamily: 'HeadFont' } })` 開書。斷言（每項用 `report(名稱, 條件, 詳細)`；失敗時詳細列出實際值）：
    - `A1` 載入無 pageerror。
    - `A2 開書：h1–h6 與其後代（h1>span、h1>a、h2>a>span）全為 HeadFont`（8 個 id）。——**此項是「規則順序」守衛**：標題規則排在主字型規則之前時 `t-h1-span`、`t-h1-a`、`t-h2-a-span` 會是 BodyFont。
    - `A3 開書：p、p>span、p>a、div 仍為 BodyFont`（4 個 id）。
    - `B 停用書本 CSS（publisherStyles: false）：標題仍 HeadFont、內文仍 BodyFont`：`applyPrefs(page, { ...BASE_PREFS, fontFamily: 'BodyFont', headingFontFamily: 'HeadFont', publisherStyles: false })`。
    - `C 標題字型取消（不帶 headingFontFamily）：8 個標題元素全部退回 BodyFont，不留殘餘規則`；接著 `C2` 再次帶上 → 又全為 HeadFont（來回切換）。
    - `D 沒有主字型、只有標題字型（主字型為使用書本字型）`：`applyPrefs(page, { ...BASE_PREFS, headingFontFamily: 'HeadFont' })` → 8 個標題元素為 HeadFont；`b-p` 既不是 BodyFont 也不是 HeadFont（沿用書本／瀏覽器字型）。
  - `applyPrefs` 同既有場景：`window.applyPreferences(p)` 後等 600ms。
- [x] **Step 2（確認紅）：**
  ```powershell
  cd C:\Users\fycdc\AI\elinkBook\app\tool\foliate_touch_harness
  node scenario-heading-font.mjs
  ```
  預期：`A2`、`B`、`C2`、`D` 為 `[FAIL]`（標題仍是 BodyFont 或書本字型），`A1`、`A3`、`C` 為 `[PASS]`，exit code 非 0。**把這段輸出（FAIL 的項目名稱）貼進 `epic.md` 開發記錄或提交說明**，證明場景在沒有 `main.js` 修改時確實失敗。
- [x] **Step 3（綠）：** 修改 `foliate/main.js` `buildOverrideCss`，在主字型規則（以字串定位：`if (prefs.fontFamily) {` 那個區塊）**之後**、`if (typeof prefs.fontSize === 'number') {` 之前新增：
  ```js
  // epic-68 Issue 2：標題字型。selector 含後代（h1 *）——上面主字型規則直接指定在
  // span／a 等元素上，只寫 h1–h6 會被標題內層的 <span>／<a> 蓋回主字型。
  // 順序不可調動：h1 *（0,0,1）與主字型 selector 的 span／a（0,0,1）特異度相同且都是
  // !important，由後出現者勝，所以必須排在主字型規則之後。停用書本 CSS 時主規則為
  // *（0），h1（0,0,1）自然勝出。字重不另處理，沿用 fontWeight 規則（設計 D9）。
  // 呼叫端只在標題字型「可用」時才傳值；沒傳就不輸出，標題沿用主字型規則。
  if (prefs.headingFontFamily) {
    const headingTags = ['h1', 'h2', 'h3', 'h4', 'h5', 'h6']
    const headingSelector = headingTags.map((h) => `${h}, ${h} *`).join(', ')
    rules.push(`${headingSelector} { font-family: '${prefs.headingFontFamily}' !important; }`)
  }
  ```
  同步修改 `buildOverrideCss` 函式上方的說明註解？**不需要**（只動新增區塊，不順手改既有註解）。
- [x] **Step 4（確認綠）：**
  ```powershell
  node scenario-heading-font.mjs
  node run-all.mjs
  ```
  預期：本場景全 `[PASS]`；`run-all.mjs` 為「全部 PASS」（既有場景不回歸，特別是 `scenario-disable-publisher-styles.mjs`、`scenario-first-line-indent-exclusions.mjs`、`scenario-publisher-body-font-size.mjs`）。
- [x] **Step 5（反向驗證，暫時修改、驗完還原，不 commit）：**
  1. 把新增的 `if (prefs.headingFontFamily) {…}` 區塊整段**剪下貼到主字型規則 `if (prefs.fontFamily) {` 之前** → `A2` 必須 FAIL（且 FAIL 的是後代 id：`t-h1-span`、`t-h1-a`、`t-h2-a-span`）。
  2. 把 selector 改成只有 `headingTags.join(', ')`（拿掉 `, ${h} *`）→ `A2` 必須 FAIL（同上三個後代 id）。
  還原後重跑 `node scenario-heading-font.mjs` 確認全 PASS。任一項沒變紅，改寫場景斷言直到能抓到。
- [x] **Step 6（README）：** `app/tool/foliate_touch_harness/README.md`「場景清單」末尾新增一條 `scenario-heading-font.mjs`：標題字型（epic-68 Issue 2）。以記憶體 EPUB（書本自帶 `h1 span`／`h2 a` 字型）斷言 `h1`–`h6` 含後代（`h1>span`、`h1>a`、`h2>a>span`）套用標題字型、非標題維持主字型、停用書本 CSS 時仍勝出、取消標題字型後規則消失、無主字型時僅標題生效；規則排在主字型規則之前或拿掉後代 selector 時 A2 會 FAIL。
- [x] **Step 7：commit：**
  ```bash
  git add app/android/app/src/main/assets/foliate/main.js app/tool/foliate_touch_harness/scenario-heading-font.mjs app/tool/foliate_touch_harness/README.md
  git commit -m "feat(epic-68): main.js 對標題及其後代套用標題字型，新增 harness 回歸場景"
  ```

---

### Task 4：重新產生 `legacy/` 並補內容守衛

> ADR 0043：修改 `foliate/` 下任何 `.js` 之後，須重建降級副本並一併 commit。`main.js` 已於 Task 3 定稿（此後若再改 `main.js`，須重建）。

**Files：**
- 修改：`app/test/reader/foliate_legacy_assets_test.dart`
- 重新產生：`app/android/app/src/main/assets/foliate/legacy/main.js`（預期只有這一檔有 diff）

- [x] **Step 1（紅，先寫守衛）：** 在 `foliate_legacy_assets_test.dart` 的 `group('foliate legacy 降級副本', …)` 內，緊接 `降級副本沒有 Chrome 88 才支援的 CSS :is()` 之後新增：
  - `降級副本的 main.js 含標題字型規則，且排在主字型規則之後（epic-68 Issue 2；忘了重新產生會失敗）`：讀 `legacy/main.js` 與原始 `main.js`，兩者皆 `expect(text, contains('prefs.headingFontFamily'))`，並 `expect(text.indexOf('prefs.headingFontFamily'), greaterThan(text.indexOf('prefs.fontFamily')))`，另斷言含標題後代 selector 的實際字串（`${h} *` 展開後，例如 `h1 *`；實際輸出以 grep 確認）（順序守衛；原始檔先查證確實滿足，避免守衛本身誤報）。`reason` 寫明「請在 app/tool/foliate_legacy 執行 pnpm build」。
- [x] **Step 2（確認紅）：**
  ```bash
  flutter test test/reader/foliate_legacy_assets_test.dart
  ```
  預期：新測試紅（`legacy/main.js` 尚無 `prefs.headingFontFamily`），其餘綠。
- [x] **Step 3（基準）：** 重建前先確認 `git status --short app/android/app/src/main/assets/foliate/legacy` 為空（工作樹乾淨）。重建（Step 4）後檢查 diff 範圍：若除 `legacy/main.js` 以外還有任何 `legacy/*` 檔出現 diff，代表基準本來就不同步（esbuild 版本或釘定檔案漂移）：**停止，不 commit 這些額外檔案**，以 `git checkout -- <額外檔案>` 還原它們，並於回報中說明，讓人決定是否另案處理。
- [x] **Step 4（重建，PowerShell）：**
  ```powershell
  $env:PATH = "$env:PNPM_HOME;$env:PATH"
  cd C:\Users\fycdc\AI\elinkBook\app\tool\foliate_legacy
  pnpm install     # 可能提示 Ignored build scripts: esbuild，可忽略
  pnpm build
  ```
  預期輸出每個檔案成功、結尾顯示處理數量、無 `✗`、無 `仍含 :is()` 警告。
  確認 `pnpm install` 沒有改動 `pnpm-lock.yaml`：`git status --short app/tool/foliate_legacy` 應為空（`node_modules` 已被 `.gitignore` 忽略；若未被忽略，**不得**加入 commit，先回報）。
- [x] **Step 5（驗證降級輸出）：**
  ```bash
  git status --short app/android/app/src/main/assets/foliate/legacy
  git diff app/android/app/src/main/assets/foliate/legacy/main.js
  ```
  預期：只有 `legacy/main.js` 變更，diff 只有新增標題規則那一段（含 `prefs.headingFontFamily`、`headingTags`／`headingSelector` 與 `.map(`、`.join(`），主字型規則仍在其前。用 Grep 於 `legacy/main.js` 確認不含 `?.`／`??` 以外的非降級語法問題由 esbuild 保證，不需手查。
- [x] **Step 6（確認綠）：**
  ```bash
  flutter test test/reader/foliate_legacy_assets_test.dart
  ```
  同時在 PowerShell 跑 ES 相容靜態掃描（本張改了 `main.js`）：
  ```powershell
  cd C:\Users\fycdc\AI\elinkBook\app
  node tool/check_foliate_es_compat.js
  ```
  預期：測試全綠；掃描 exit 0（本次新增只用 `Array.prototype.map`／`join`，無較新 API）。若掃描失敗，不要自行加 polyfill，回報。
- [x] **Step 7（反向驗證，暫時修改、驗完還原，不 commit）：** 暫時把 `legacy/main.js` 內的 `prefs.headingFontFamily` 改名（例如 `prefs.headingFontFamilyX`）→ 守衛必須紅；之後**重跑 `pnpm build`** 還原（不要用 `git stash`／`git checkout`：前者會連帶 `.claude/settings.json`、後者會丟掉重建結果），再跑一次測試確認綠。
- [x] **Step 8：commit：**
  ```bash
  git add app/android/app/src/main/assets/foliate/legacy/main.js app/test/reader/foliate_legacy_assets_test.dart
  git commit -m "chore(epic-68): 重新產生 legacy 降級副本並補標題字型內容守衛"
  ```

---

### Task 5：收尾與驗收

**Files：** `docs/epics/epic-68-heading-font/issues.md`、`docs/epics/epic-68-heading-font/epic.md`

- [x] **Step 1：驗收 grep：**
  ```bash
  grep -rn "headingFontFamily" app/lib/reader/foliate_reader_view.dart app/lib/screens/reader_screen.dart app/android/app/src/main/assets/foliate/main.js app/android/app/src/main/assets/foliate/legacy/main.js
  git diff 3d8bafee..HEAD --stat -- app/lib
  ```
  預期：`foliate_reader_view.dart`（欄位／建構子／map／changed 共 4 處）、`reader_screen.dart`（`headingFontFamily:` 一處）、`main.js` 與 `legacy/main.js` 各有；`app/lib` 的 diff 在本張只新增這兩個檔（Issue 1 的檔案不在此計）；不得出現 `*.arb`、`reader_settings_sheet.dart`、資料庫檔的**本張**變更。
- [x] **Step 2：靜態檢查：**
  ```bash
  flutter analyze
  ```
  預期 `No issues found!`。本張未新增／修改 `Key`、未新增使用者可見字串，`check_l10n_hardcoded_strings.js`／`check_integration_keys.js` 非必要；測試中新增的 `MaterialApp` 皆帶 `locale`。若要順手跑（PowerShell 前置 pnpm Node）：`node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js`，預期 PASS。
- [x] **Step 3：本張觸及測試檔最終彙整再跑一輪**（不是完整 `flutter test`）：
  ```bash
  flutter test test/reader/foliate_reader_view_test.dart test/reader/foliate_legacy_assets_test.dart
  flutter test test/screens/reader_screen_test.dart
  ```
  PowerShell（前置 pnpm Node）：
  ```powershell
  cd C:\Users\fycdc\AI\elinkBook\app\tool\foliate_touch_harness
  node run-all.mjs
  cd C:\Users\fycdc\AI\elinkBook\app
  node tool/check_foliate_es_compat.js
  ```
  預期：全綠、`整體結果：全部 PASS`、掃描 exit 0。
- [x] **Step 4：文件狀態。** `issues.md` 表格 Issue 2 狀態改「完成（待 PR）」；`epic.md`「進度」補一行：Issue 2 完成——`FoliateReaderView.headingFontFamily`、map／changed、`ReaderScreen` 傳遞（排除 FXL、CBZ 含舊資料、宣告 null 偵測為 FXL）、`main.js` 標題規則（含後代、排在主字型規則之後）、`legacy/` 重建與內容守衛、harness 場景 `scenario-heading-font.mjs`（無 `main.js` 修改時 A2／B／C2／D 失敗已驗證）。註記：本張無 UI，真實 EPUB 目視確認在 Issue 3；既有 `firstLineIndent` 傳遞條件有同樣的舊資料 CBZ 缺口，未於本張處理（另案評估）。**不動** `docs/epics.md`、`CLAUDE.md`、`AGENTS.md`（本張不改變其描述的架構事實）。
- [x] **Step 5：commit（明確列檔，不含 `.claude/settings.json`）：**
  ```bash
  git add docs/epics/epic-68-heading-font/issues.md docs/epics/epic-68-heading-font/epic.md
  git commit -m "docs(epic-68): Issue 2 收尾，更新狀態與進度"
  ```
- [ ] **Step 6：** 程式審查（由獨立審查者產出，報告存 `docs/epics/epic-68-heading-font/reviews/review-code-issue-2.md`，依專案慣例審查先出報告、不直接修改）。本張無 PR（Epic 全部 Issue 完成後同一個 PR，見 `issues.md`）。

## 完成標準

1. `ReaderScreen` 對流式 EPUB／KF8／TXT／MD 傳 `fonts.effectiveFamily(headingFontFamily)`；FXL、CBZ（含宣告 null 的舊資料）、宣告 null 偵測為 FXL 的 EPUB 一律傳 null；標題字型不可用傳 null 且偏好不被改寫。
2. `buildFoliatePreferencesMap` 有值才帶 key；`foliatePreferencesChanged` 僅標題字型變動時為 true。
3. `main.js` 的標題規則涵蓋 `h1`–`h6` 與其後代、排在主字型規則之後、停用書本 CSS 時仍勝出、無值時不輸出；harness 場景全 PASS 且已證實在沒有修改時 FAIL。
4. `foliate/legacy/main.js` 與 `main.js` 同步（只有該檔變動），內容守衛測試綠；`check_foliate_es_compat.js` exit 0。
5. `flutter analyze` 乾淨；本張觸及測試檔全綠；未跑完整 `flutter test`（刻意）。

## 風險與備註

- **順序依賴**：標題規則的正確性靠 push 順序，不是靠特異度；任何人日後在主字型規則之前插入新字型規則或重排時都會破壞。harness 場景 A2 與 legacy 順序守衛是唯二防線，故不可刪。
- **harness 只驗 computed `font-family` 字串**：不載入真實字型，無法證明「字形真的換了」；真實 EPUB 目視確認移到 Issue 3。
- **harness 跑原始 `main.js`，不跑 `legacy/`**：舊 WebView（Chrome 83）上的實際行為無法在此驗證，只有降級語法與內容守衛；真機結果留待 Issue 3 之後。
- **legacy 重建基準**：若重建後 `legacy/` 出現 `main.js` 以外的差異，代表釘定檔案或 esbuild 版本漂移，不屬本張，須分開處理（Task 4 Step 3）。
- **Windows 工具鏈**：`node`／`pnpm` 只在 PowerShell 前置 `PNPM_HOME` 後可用；`run-all.mjs` 以 PATH 內 `node` 起子程序，忘了前置會讓每個場景報 nvm 錯誤；puppeteer 第一次需下載 Chromium。
- **既有缺口（不處理）**：`firstLineIndent: _isFixedLayout ? null : …` 對舊資料 CBZ 同樣有漏洞，僅提報。

## 審查處理紀錄

審查（review-plan-issue-2.md）通過，實作時套用：

1. Node 環境：PATH 上已有 node（v26）與 pnpm 11，`node --version` 可用（v24 以上）即可，不必強求 PNPM_HOME 下有 node.exe。
2. legacy 內容守衛除 `prefs.headingFontFamily` 排在 `prefs.fontFamily` 之後外，另斷言標題 selector 後代寫法（`${h} *` 展開後的實際字串，如 `h1 *`）存在。
3. Task 2 測試 3、5、6 明確寫出 isFixedLayout 值。
4. Task 5 Step 1 的 git diff 改以 Issue 1 最後 commit（3d8bafee）為基準。
