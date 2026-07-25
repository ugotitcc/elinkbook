# Epic 18 Issue 5 — 新增「強制單欄」版面偏好 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增一個可由使用者在「⚙️版面設定」畫面手動開啟的布林偏好 `singleColumn`，開啟後透過 `view.renderer.setAttribute('max-column-count', '1')` 強制直排 EPUB 以單欄呈現，避免部分書籍被 `readest/foliate-js` 內建 `--_max-column-count: 2` 拆成「需要多按一次翻頁才能看完原本一頁」的兩欄版面（`design.md` 使用者回報項目 8）。**額外要求（使用者本次明確提出）**：修好後必須驗證「直排由 2 欄變成 1 欄」時，每次點擊翻頁的頁碼變化是「一次前進」，不會出現「同一個頁碼要點兩次才變化」的症狀——這正是本 Issue 要修的根本症狀本身，Task 6 會用既有的 `issue9_vertical_pagejump.epub` 測試 fixture 建立一個新的 `integration_test`，對此提供可自動化重跑的回歸保護。

**Architecture:** 偏好值沿著既有「單書覆寫」管線一路透傳，五層皆為 nullable（`null`＝未覆寫，比照 `publisherStyles`/`writingModeOverride` 既有慣例，不像 `showHeader`/`showFooter` 有「非 null 安全預設值」那一層）：`BookReaderPrefs.singleColumn`（SQLite 持久化）→ `ResolvedPreferences.singleColumn`（`ReaderPrefsManagerImpl.resolve()` 直接透傳 `book.singleColumn`，不套用任何預設值）→ `FoliateEpubReaderView.singleColumn`（建構參數，`_buildPreferencesMap()` 只在非 null 時加入 map）→ 原生端 `FoliateEpubReaderView.kt` 既有的 `Map<String, Any?>` 整包透傳機制（**不需要修改**，見 Global Constraints）→ `main.js` 的 `window.applyPreferences(prefs)` 讀到 `prefs.singleColumn` 為 `boolean` 型別時呼叫 `view.renderer.setAttribute('max-column-count', prefs.singleColumn ? '1' : '2')`（`max-column-count` 是 `paginator.js` 既有 `observedAttributes` 之一，透過既有 `attributeChangedCallback()` 自動生效，不修改 vendored 檔案）。UI 是 `ReaderSettingsSheet` 內新增一個 `SwitchListTile`，比照既有 `_showHeader`/`_showFooter` 開關的寫法。

**Tech Stack:** Flutter/Dart（`app/lib/reader/*.dart`、`app/lib/screens/*.dart`）、SQLite（`sqflite`，schema migration）、JavaScript（`app/android/app/src/main/assets/foliate/main.js`，WebView 內執行）。`flutter test` 涵蓋 Task 1-5；`main.js` 本身無 JS 單元測試（比照 Epic 17 既有慣例，`view.renderer.setAttribute()` 是框架 API 直接串接，無可抽出的純邏輯）；Task 6 用 `integration_test`（需真機/模擬器）驗證 JS 生效與使用者要求的翻頁行為；Task 7 為真機人工驗收。

## Global Constraints

- **所有指令皆在 `app/` 目錄下執行**（`cd "U:/MyDeveloper/AI/elinkBook/app"`），使用 POSIX 相容 Bash（Git Bash），非 PowerShell。
- **`flutter analyze` 必須保持乾淨**（"No issues found!"）——每個 Task 完成程式碼異動後都要跑一次。
- **`singleColumn` 是三態 nullable bool，語意比照 `publisherStyles`/`writingModeOverride`，不是 `showHeader`/`showFooter`**：`null`＝未覆寫（不出現在任何傳遞給原生端/JS 的 map 中，交由 `paginator.js` 內建 `--_max-column-count: 2` 自動判斷，這是「預設關閉」在機制層級的實作方式，見 `design.md` 決策 #3）；`true`＝強制單欄；`false`＝明確允許雙欄。**不要**像 `ResolvedPreferences.showHeader`/`showFooter` 那樣在 `ReaderPrefsManagerImpl.resolve()` 用 `?? true`/`?? false` 套一層安全預設值——`singleColumn` 在 `ResolvedPreferences` 也維持 `bool?` 型別，`resolve()` 內直接 `singleColumn: book.singleColumn`（原樣透傳，無全域預設層）。
- **頁碼估算既有限制不變，測試斷言不可過度承諾**：`app/lib/reader/epub_position_info.dart` 的既有文件註解已明載 `pageIndex`/`totalPages` 是 `foliate-js` `SectionProgress.getProgress()` 的 `location.current`/`location.total`——「近似頁碼概念，非精確渲染頁數」，計算基礎是全書字元數（`sizePerLoc = 1500` 字元/location，見 `progress.js` `SectionProgress` 建構子），與目前顯示欄數（1 或 2）無直接數學關聯。本 Issue 修的是「2 欄模式下，點擊只移動到同一頁的第二欄時，`pageIndex` 完全不會前進，需要再點一次才前進」這個症狀本身（`design.md` 使用者回報項目 8 的具體描述：同一個「第 13/186 頁」被拆成兩張畫面）；改為單欄後，**每一次點擊都會移動到全新內容**，`pageIndex` 保證會前進，但**不保證每次前進的量恆為 1**（不同段落字元密度不同，屬既有架構已知/已文件化的近似值特性）。因此 Task 6 的自動化測試與 Task 7 的真機驗收，斷言的是「連續點擊時 `pageIndex`／頁尾頁碼絕不會停留在原數值（不需要點兩次才看到變化）」，**不**斷言「每次點擊的差值恆為 1」——後者是比既有架構承諾更強的保證，寫這種測試會導致測試本身不穩定（flaky）且與既有文件化限制矛盾。
- **`main.js` 不修改 vendored 檔案**：`paginator.js`／`view.js`／`overlayer.js`／`progress.js` 皆不可修改，`max-column-count` 已是 `paginator.js` 既有 `Paginator.observedAttributes` 成員（`paginator.js:1159`）與既有 `attributeChangedCallback()`（`paginator.js:1556` 一帶）已支援的外部可設定屬性，本 Issue 只在 `main.js` 呼叫既有的 `view.renderer.setAttribute()` API。
- **`max-column-count` 不需要 CSS 單位**：與 Issue 4 的 `margin-top`/`margin-bottom`（長度屬性，`setAttribute` 值必須帶 `px` 等單位）不同，`max-column-count` 是純數字乘數（用於 CSS `calc()`），`setAttribute('max-column-count', '1')` 傳入不帶單位的數字字串即可，不要誤用 Issue 4 的單位規則。
- **`FoliateEpubReaderView.kt`（原生端 Kotlin）不需要修改**：`openBook`/`setPreferences` method channel case 現行寫法已是把整個 `Map<String, Any?>` 序列化為 JSON 字串、透過 `evaluateJavascript("window.applyPreferences($prefsJson)", null)` 整包送給 JS 端（見 `FoliateEpubReaderView.kt:139-275` 一帶），新增的 `singleColumn` 欄位會自動包含在這個既有透傳機制中，不需要新增 method channel case 或修改 Kotlin 程式碼。
- **SQLite schema 版本**：目前 `SqliteLibraryRepository.open()` 的 `version` 為 `11`（`app/lib/library/sqlite_library_repository.dart:30`），本 Issue 升級至 `12`。
- **`book_reader_prefs` 表的 `else` 分支陷阱（撰寫本計劃時已追蹤 `onUpgrade` 既有結構確認，務必依此設計，不可放錯位置）**：`onUpgrade` 目前結構是 `if (oldVersion < 2) { 建全新 book_reader_prefs 表（一步到位含所有欄位） } else { if (oldVersion < 3) {...} if (oldVersion < 4) {...} if (oldVersion < 7) { await _addHeaderFooterColumns(db); } }`。新增的 `_addSingleColumnColumn(db)` 呼叫**必須放在這個 `else` 分支內**（`oldVersion < 7` 判斷式之後），**不可**像 `_addEpubLayoutColumn`（`books` 表專用，`books` 表從未在 `onUpgrade` 內被整表重建，故可安全放在頂層無條件執行）那樣放在整個 `if/else` 區塊外的頂層。原因：一旦 `_createBookReaderPrefsTable()` 更新為含 `single_column` 欄位（Task 2 會做），若 `_addSingleColumnColumn` 又在頂層對 `oldVersion < 12` 無條件執行，`oldVersion == 1` 的裝置會先在 `if (oldVersion < 2)` 分支透過 `_createBookReaderPrefsTable()` 建出「已含 `single_column` 欄位」的全新表，接著又在頂層對同一張表執行 `ALTER TABLE ADD COLUMN single_column`，觸發 SQLite `duplicate column name` 例外、升級直接崩潰。放在 `else` 分支內（只有 `oldVersion >= 2`、表已存在且是舊欄位組合時）才會安全跳過這個衝突。
- **既有測試裝置**：`3CEF42ECD491687`（9491G，Android 15／API 35），Task 7 使用；`design.md` 提及的其餘尺寸裝置本 Issue 不強制要求（Issue 5 的核心是行為正確性，非版面尺寸適配，`issues.md` 驗收標準只指定這一台）。
- **Task 5 的 `_notifyChanged()` 刻意沿用既有的整列 `BookReaderPrefs(...)` 建構方式，不改用 `copyWith(...)`（`tmp/epic-18/reviews/review-plan-issue-5.md` Important #1 已評估並否決）**：`book_reader_prefs.dart:215-219` 的 `copyWith()` 文件註解已明確記載「不支援明確清成 null——需要清空欄位的情境（例如 `ReaderSettingsSheet` 的排版方向三態選擇器）請繼續用既有的整列建構方式，不要用這個方法」。`ReaderSettingsSheet._buildWritingModeOverrideRow()`/`_buildPageTurnModeOverrideRow()`/`_buildScreenOrientationOverrideRow()` 三個既有三態選擇器，使用者選擇「採用書籍排版」/「使用全域預設」時會把對應的 `_writingModeOverride`/`_pageTurnModeOverride`/`_screenOrientationOverride` 設為 `null` 再呼叫 `_notifyChanged()`——若改用 `copyWith(writingModeOverride: _writingModeOverride, ...)`，`copyWith` 的 `newValue ?? this.value` 語意會讓這個 `null` 被忽略、悄悄保留舊的覆寫值，導致使用者永遠無法把已設定的排版方向/翻頁模式/螢幕方向覆寫清回「採用書籍/全域預設」，是實質的功能回歸，而非理論疑慮。審查報告擔心的「儲存 EPUB 偏好時意外清空 PDF/雙頁欄位」在目前架構下不會發生——PDF 欄位只透過 `PdfSettingsSheet`、`dualPageMode` 只透過 `PdfSettingsSheet`/`FxlSettingsSheet` 寫入，兩者與 `ReaderSettingsSheet`（僅流式 EPUB 使用）不會作用於同一本書的同一列資料（書籍格式/FXL 判定為固定值，不會中途變更），故維持既有整列建構方式，不在本 Issue 改動 `_notifyChanged()` 的既有結構。
- **`_singleColumn` 在 `ReaderSettingsSheet` 內宣告為 `late bool`（`?? false`），不宣告為保留三態的 `bool?`（`review-plan-issue-5.md` Minor #2 已評估並否決）**：同一個 `_ReaderSettingsSheetState` 內既有的 `_showHeader`/`_showFooter` 已是相同的「初始化時 `?? true` 退化為明確布林值，使用者調整任一其他欄位即可能把原本 `null` 的欄位明確寫成 `0`/`1`」既有模式（`reader_settings_sheet.dart:79-80`）。只讓新增的 `_singleColumn` 改用 `bool?` 保留三態，會讓同一個畫面的三個外觀相同的 `SwitchListTile` 有不一致的底層語意，對日後維護反而更難懂；若要讓三者皆保留三態語意，屬於既有 `showHeader`/`showFooter` 行為的既有設計選擇，超出本 Issue 範圍，不在此順手修改。

---

## File Structure

| 檔案 | 異動類型 | 職責 |
|---|---|---|
| `app/lib/reader/book_reader_prefs.dart` | 修改 | 新增 `singleColumn` 欄位（`toMap`/`fromMap`/`copyWith`/`==`/`hashCode`） |
| `app/test/reader/book_reader_prefs_test.dart` | 修改（新增測試） | `singleColumn` round-trip／相等性／`copyWith` 測試 |
| `app/lib/library/sqlite_library_repository.dart` | 修改 | schema 升級至 `version: 12`，`book_reader_prefs` 表新增 `single_column` 欄位 |
| `app/test/library/sqlite_library_repository_test.dart` | 修改（新增測試） | 全新安裝／`version: 11→12` 升級路徑的 round-trip 測試 |
| `app/lib/reader/foliate_epub_reader_view.dart` | 修改 | 新增 `singleColumn` 建構參數，`_buildPreferencesMap()`／`_preferencesChanged()` 同步更新 |
| `app/test/reader/foliate_epub_reader_view_test.dart` | 修改（新增測試） | `singleColumn` 出現/不出現於 `initialPreferences` map、`didUpdateWidget` 變動時觸發 `setPreferences` |
| `app/lib/reader/resolved_preferences.dart` | 修改 | 新增 `singleColumn` 欄位（`bool?`，無預設值） |
| `app/lib/reader/reader_prefs_manager_impl.dart` | 修改 | `resolve()` 新增 `singleColumn: book.singleColumn` 透傳 |
| `app/lib/screens/reader_screen.dart` | 修改 | `_buildNativeView()` 的 `FoliateEpubReaderView(...)` 建構呼叫新增 `singleColumn: resolved.singleColumn` |
| `app/test/reader/resolved_preferences_test.dart` | 修改（擴充既有測試） | `singleColumn` 保留傳入值 |
| `app/test/reader/reader_prefs_manager_test.dart` | 修改（擴充既有測試） | `singleColumn` 無預設值透傳（null／非 null 兩種情境） |
| `app/test/screens/reader_screen_test.dart` | 修改（擴充既有測試） | `ReaderSettingsSheet` 變動 `singleColumn` 後正確傳遞到 `FoliateEpubReaderView` |
| `app/lib/screens/reader_settings_sheet.dart` | 修改 | 新增「強制單欄（直排）」`SwitchListTile` |
| `app/test/screens/reader_settings_sheet_test.dart` | 修改（新增測試） | 開關初始值／點擊後 `onChanged`／不影響其他欄位 |
| `app/android/app/src/main/assets/foliate/main.js` | 修改 | `window.applyPreferences(prefs)` 新增 `max-column-count` 的 `setAttribute` 呼叫 |
| `app/integration_test/foliate_single_column_test.dart` | 新增 | 真機/模擬器驗證單欄模式下連續翻頁 `pageIndex` 皆前進（本 Issue 核心症狀回歸測試） |

---

### Task 1：`BookReaderPrefs.singleColumn` 欄位

**Files:**
- Modify: `app/lib/reader/book_reader_prefs.dart`
- Test: `app/test/reader/book_reader_prefs_test.dart`

**Interfaces:**
- Produces：`BookReaderPrefs.singleColumn`（`bool?`，`null`＝未覆寫），`toMap()` 輸出 `'single_column'` key（`null`→`null`、`true`→`1`、`false`→`0`，比照既有 `show_header`/`show_footer` 布林轉換），`fromMap()`／`copyWith()`／`==`／`hashCode` 皆涵蓋此欄位

- [x] **Step 1：撰寫失敗測試**

在 `app/test/reader/book_reader_prefs_test.dart` 末尾（`main()` 函式結尾 `}` 之前）新增：

```dart
  test('singleColumn 欄位 BookReaderPrefs.empty 為 null（未覆寫，交由 foliate-js 內建 --_max-column-count 自動判斷）',
      () {
    const prefs = BookReaderPrefs.empty;
    expect(prefs.singleColumn, isNull);
  });

  test('singleColumn 欄位值完全相同的 BookReaderPrefs 視為相等', () {
    const a = BookReaderPrefs(singleColumn: true);
    const b = BookReaderPrefs(singleColumn: true);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('singleColumn 欄位不同時視為不相等', () {
    const a = BookReaderPrefs(singleColumn: true);
    const b = BookReaderPrefs(singleColumn: false);
    expect(a, isNot(b));
  });

  test('singleColumn 為 true／false／null 皆正確 toMap／fromMap round-trip（避免布林值 0/1 轉換錯誤）',
      () {
    const withTrue = BookReaderPrefs(singleColumn: true);
    final trueMap = withTrue.toMap('book-13');
    expect(trueMap['single_column'], 1);
    expect(BookReaderPrefs.fromMap(trueMap).singleColumn, isTrue);

    const withFalse = BookReaderPrefs(singleColumn: false);
    final falseMap = withFalse.toMap('book-14');
    expect(falseMap['single_column'], 0);
    expect(BookReaderPrefs.fromMap(falseMap).singleColumn, isFalse);

    const withNull = BookReaderPrefs.empty;
    final nullMap = withNull.toMap('book-15');
    expect(nullMap['single_column'], isNull);
    expect(BookReaderPrefs.fromMap(nullMap).singleColumn, isNull);
  });

  test('copyWith 更新 singleColumn 時，其餘欄位保留原值', () {
    const original = BookReaderPrefs(fontSize: 18, singleColumn: false);
    final updated = original.copyWith(singleColumn: true);

    expect(updated.fontSize, 18);
    expect(updated.singleColumn, isTrue);
  });
```

- [x] **Step 2：執行測試確認失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/book_reader_prefs_test.dart
```

Expected：新增的 5 個測試皆因 `singleColumn` 尚不存在而編譯失敗（`The named parameter 'singleColumn' isn't defined`）。

- [x] **Step 3：實作 `BookReaderPrefs.singleColumn`**

在 `app/lib/reader/book_reader_prefs.dart` 第 43-44 行（`showHeader`/`showFooter` 欄位宣告）之後新增欄位宣告：

```dart
  final bool? showHeader; // null=true（預設顯示頁首，僅 EPUB 有效，見 spec.md「頁首/頁尾顯示切換」）
  final bool? showFooter; // null=true（預設顯示頁尾，EPUB／PDF 皆有效）

  final bool? singleColumn; // null=未覆寫（交由 foliate-js 內建 --_max-column-count: 2 自動判斷）、true=強制單欄、false=明確允許雙欄，僅直排 EPUB 有效，見 epic-18-reader-device-qa spec.md「singleColumn 偏好」
```

建構子（第 46-69 行）新增參數：

```dart
  const BookReaderPrefs({
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.paragraphSpacing,
    this.pageMargins,
    this.textAlign,
    this.publisherStyles,
    this.writingModeOverride,
    this.pageTurnModeOverride,
    this.screenOrientationOverride,
    this.pdfFitMode,
    this.pdfContrast,
    this.pdfBrightness,
    this.pdfBoldStrength,
    this.pdfCropMode,
    this.pdfCropRect,
    this.dualPageMode,
    this.dualPageCoverAlone,
    this.dualPageDirection,
    this.showHeader,
    this.showFooter,
    this.singleColumn,
  });
```

`toMap()`（第 74-102 行）在 `'show_footer'` 那行之後新增：

```dart
      'show_header': showHeader == null ? null : (showHeader! ? 1 : 0),
      'show_footer': showFooter == null ? null : (showFooter! ? 1 : 0),
      'single_column': singleColumn == null ? null : (singleColumn! ? 1 : 0),
    };
  }
```

`fromMap()`（第 104-161 行）在 `showFooter:` 那行之後新增：

```dart
      showHeader:
          map['show_header'] == null ? null : (map['show_header'] as int) == 1,
      showFooter:
          map['show_footer'] == null ? null : (map['show_footer'] as int) == 1,
      singleColumn: map['single_column'] == null
          ? null
          : (map['single_column'] as int) == 1,
    );
  }
```

`operator ==`（第 163-187 行）在 `other.showFooter == showFooter` 之後新增：

```dart
      other.showHeader == showHeader &&
      other.showFooter == showFooter &&
      other.singleColumn == singleColumn;
```

`hashCode`（第 189-213 行）在 `showFooter,` 之後新增：

```dart
        showHeader,
        showFooter,
        singleColumn,
      ]);
```

`copyWith()`（第 220-269 行）參數清單在 `bool? showFooter,` 之後新增：

```dart
    bool? showHeader,
    bool? showFooter,
    bool? singleColumn,
  }) {
```

`copyWith()` 回傳的建構呼叫在 `showFooter: showFooter ?? this.showFooter,` 之後新增：

```dart
      showHeader: showHeader ?? this.showHeader,
      showFooter: showFooter ?? this.showFooter,
      singleColumn: singleColumn ?? this.singleColumn,
    );
  }
```

- [x] **Step 4：執行測試確認通過**

```bash
flutter test test/reader/book_reader_prefs_test.dart
```

Expected：全數通過（`All tests passed!`）。

- [x] **Step 5：`flutter analyze`**

```bash
flutter analyze
```

Expected：`No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/reader/book_reader_prefs.dart app/test/reader/book_reader_prefs_test.dart
git commit -m "feat(epic-18): BookReaderPrefs 新增 singleColumn 欄位"
```

---

### Task 2：SQLite schema 升級至 `version: 12`（`book_reader_prefs.single_column`）

**Files:**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes：`BookReaderPrefs.singleColumn`（Task 1）透過 `BookReaderPrefsRepository`（`toMap`/`fromMap` 已包含 `single_column` key，無需修改該檔案）
- Produces：`book_reader_prefs` 表新增 `single_column INTEGER`（nullable）欄位；全新安裝直接建出含此欄位的表；既有 `version <= 11` 裝置透過 `ALTER TABLE` 補上

- [x] **Step 1：撰寫失敗測試——全新安裝**

在 `app/test/library/sqlite_library_repository_test.dart`，緊接在既有 `既有 version 10 裝置升級到 version 11...` 測試（第 1423-1496 行）之後、`group('detectAndCacheEpubLayout', ...)`（第 1498 行）之前，插入：

```dart
  test('全新安裝的 book_reader_prefs 表包含 single_column 欄位（version 12 起 onCreate 已含括）',
      () async {
    await repository.insertBook(_book('b_single_column'));
    await repository.database.insert('book_reader_prefs', {
      'book_id': 'b_single_column',
      'single_column': 1,
    });

    final row = (await repository.database.query('book_reader_prefs',
            where: 'book_id = ?', whereArgs: ['b_single_column']))
        .single;
    expect(row['single_column'], 1);
  });

  test('既有 version 11 裝置升級到 version 12，book_reader_prefs 表正確補上 single_column 欄位（ALTER TABLE 路徑）',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v11_to_v12_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 11」的舊資料庫：手動以 version 11 當時的完整
    // schema（books 表含 is_fixed_layout；book_reader_prefs 表不含
    // single_column）建立，不透過 SqliteLibraryRepository.open()（該方法
    // 目前的 onCreate 已經是 version 12 的最終 schema，無法用來重現「舊
    // 裝置」情境），比照既有 v10→v11 遷移測試寫法。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 11,
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
              lastReadTime INTEGER NOT NULL
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
              show_footer INTEGER
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.insert('book_reader_prefs', {
      'book_id': 'b1',
      'font_size': 18.0,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=11 →
    // newVersion=12），驗證既有資料不受影響、新欄位存在且預設 NULL、且可寫入。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final row = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(row['font_size'], 18.0); // 既有資料不受影響
    expect(row['single_column'], isNull); // 新欄位存在且預設 NULL

    // 證明欄位真的可寫入（不只是巧合為 null），確認 ALTER TABLE 確實生效。
    await upgraded.database.update(
      'book_reader_prefs',
      {'single_column': 1},
      where: 'book_id = ?',
      whereArgs: ['b1'],
    );
    final updated = (await upgraded.database
            .query('book_reader_prefs', where: 'book_id = ?', whereArgs: ['b1']))
        .single;
    expect(updated['single_column'], 1);
  });
```

- [x] **Step 2：執行測試確認失敗**

```bash
flutter test test/library/sqlite_library_repository_test.dart
```

Expected：兩個新測試皆失敗——第一個因為 `single_column` 欄位不存在（`no such column`），第二個因為 `SqliteLibraryRepository.open()` 內部 `version: 11` 與手動建立的 `oldDb` 版本相同（11 == 11），`onUpgrade` 不會觸發，欄位同樣不存在。

- [x] **Step 3：實作 schema 升級**

修改 `app/lib/library/sqlite_library_repository.dart` 第 30 行：

```dart
      version: 12,
```

修改 `_createBookReaderPrefsTable()`（第 158-190 行）的 `CREATE TABLE` 陳述式，在 `show_footer INTEGER` 之後新增欄位：

```dart
        show_header INTEGER,
        show_footer INTEGER,
        single_column INTEGER
      )
    ''');
  }
```

在 `onUpgrade` 的 `else` 分支內（第 91-98 行，`if (oldVersion < 7) { await _addHeaderFooterColumns(db); }` 之後、`else` 區塊結束的 `}` 之前）新增：

```dart
          if (oldVersion < 7) {
            // epic-5-toc-pagination Issue 5：頁首/頁尾顯示切換新增的 2 個
            // 欄位，補追加到既有（version 2 起已存在）的 book_reader_prefs
            // 表。放在 else 分支內（oldVersion >= 2）——因為 oldVersion < 2
            // 時 _createBookReaderPrefsTable 已一步到位建表含
            // show_header/show_footer，不需要再 ALTER TABLE。
            await _addHeaderFooterColumns(db);
          }
          if (oldVersion < 12) {
            // epic-18-reader-device-qa Issue 5：強制單欄版面偏好新增的 1
            // 個欄位，補追加到既有（version 2 起已存在）的
            // book_reader_prefs 表。必須放在 else 分支內（oldVersion >= 2）
            // ——理由同上：oldVersion < 2 時 _createBookReaderPrefsTable
            // 已一步到位建表含 single_column，若在 else 分支外無條件執行
            // ALTER TABLE，oldVersion == 1 的裝置會對剛建好、已有該欄位的
            // 表重複 ALTER TABLE，拋出 duplicate column name 例外。
            await _addSingleColumnColumn(db);
          }
```

在 `_addEpubLayoutColumn()`（第 321-332 行）之後新增新的 helper 函式：

```dart
  static Future<void> _addSingleColumnColumn(Database db) async {
    // 強制單欄版面偏好（epic-18-reader-device-qa Issue 5），補追加到既有
    // （version 2 起已存在）的 book_reader_prefs 表，見
    // docs/epics/epic-18-reader-device-qa/spec.md「singleColumn 偏好」。
    // nullable：NULL=未覆寫（交由 foliate-js 內建 --_max-column-count: 2
    // 自動判斷）、0=false、1=true。比照 _addHeaderFooterColumns／
    // _addEpubLayoutColumn 既有慣例，僅在表已存在時才執行 ALTER TABLE。
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='book_reader_prefs'");
    if (tables.isNotEmpty) {
      await db.execute(
          'ALTER TABLE book_reader_prefs ADD COLUMN single_column INTEGER');
    }
  }
```

- [x] **Step 4：執行測試確認通過**

```bash
flutter test test/library/sqlite_library_repository_test.dart
```

Expected：全數通過（`All tests passed!`），包含既有的 v1→v5／v2→v4／v6→v7／v7→v8／v9→v10／v10→v11 等既有遷移測試不應回歸（確認 `else` 分支的新增不影響既有分支邏輯）。

- [x] **Step 5：跑全專案 `flutter test` 確認無其他回歸**

```bash
flutter test
```

Expected：全數通過——`book_reader_prefs_repository_test.dart`／`reader_prefs_manager_test.dart` 等依賴 `SqliteLibraryRepository.open()` 的既有測試不應因 schema 版本號變動而失敗（它們皆呼叫 `open()` 走 `onCreate`，非手動指定舊版本號）。

- [x] **Step 6：`flutter analyze`**

```bash
flutter analyze
```

Expected：`No issues found!`

- [x] **Step 7：Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-18): book_reader_prefs 新增 single_column 欄位（schema v11→v12）"
```

---

### Task 3：`FoliateEpubReaderView.singleColumn` 建構參數

**Files:**
- Modify: `app/lib/reader/foliate_epub_reader_view.dart`
- Test: `app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes：`bool? singleColumn` 建構參數
- Produces：`_buildPreferencesMap()` 在 `widget.singleColumn != null` 時於 map 加入 `'singleColumn': widget.singleColumn`（`bool` 原始型別，不轉字串——與 `main.js` 端 `prefs.singleColumn` 直接用布林值判斷一致，字串轉換留給 Task 6 的 `setAttribute` 呼叫自己處理）；`_preferencesChanged()` 涵蓋此欄位

- [x] **Step 1：撰寫失敗測試**

在 `app/test/reader/foliate_epub_reader_view_test.dart`，於既有 `'_onPlatformViewCreated 呼叫 openBook 並帶入正確的 path'` 測試（第 50-64 行）之後新增：

```dart
  testWidgets('singleColumn: true 時，openBook 的 initialPreferences 含 singleColumn: true',
      (tester) async {
    final calls = await _pumpFoliateEpubReaderView(
      tester,
      const FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        singleColumn: true,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(openBookCall.arguments['initialPreferences'], {'singleColumn': true});
  });

  testWidgets('singleColumn 為 null（預設）時，initialPreferences 不含 singleColumn key',
      (tester) async {
    final calls = await _pumpFoliateEpubReaderView(
      tester,
      const FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    final openBookCall = calls.firstWhere((c) => c.method == 'openBook');
    expect(
      (openBookCall.arguments['initialPreferences'] as Map).containsKey('singleColumn'),
      isFalse,
    );
  });

  testWidgets('singleColumn 變動時，didUpdateWidget 呼叫 setPreferences 並帶入新值',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    final key = GlobalKey<State<FoliateEpubReaderView>>();
    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();
    instanceCalls.clear();

    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        singleColumn: true,
      ),
    ));
    await tester.pumpAndSettle();

    final setPreferencesCall =
        instanceCalls.firstWhere((c) => c.method == 'setPreferences');
    expect(setPreferencesCall.arguments, {'singleColumn': true});
  });
```

- [x] **Step 2：執行測試確認失敗**

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart
```

Expected：新增的 3 個測試皆因 `singleColumn` 建構參數不存在而編譯失敗。

- [x] **Step 3：實作 `FoliateEpubReaderView.singleColumn`**

在 `app/lib/reader/foliate_epub_reader_view.dart` 第 55 行（`final bool? publisherStyles;`）之後新增欄位：

```dart
  final bool? publisherStyles;

  /// 強制單欄版面偏好（epic-18-reader-device-qa Issue 5）：`null`＝未覆寫
  /// （交由 foliate-js 內建 `--_max-column-count: 2` 自動判斷），`true`＝
  /// 強制單欄，`false`＝明確允許雙欄。僅直排時有意義，但不限制呼叫端只能
  /// 在直排時傳入。
  final bool? singleColumn;
```

建構子（第 94-122 行）在 `this.publisherStyles,` 之後新增：

```dart
    this.publisherStyles,
    this.singleColumn,
```

`_preferencesChanged()`（第 234-245 行）在 `widget.publisherStyles != oldWidget.publisherStyles` 之後新增：

```dart
  bool _preferencesChanged(FoliateEpubReaderView oldWidget) {
    return widget.writingMode != oldWidget.writingMode ||
        widget.pageTurnMode != oldWidget.pageTurnMode ||
        widget.fontFamily != oldWidget.fontFamily ||
        widget.fontSize != oldWidget.fontSize ||
        widget.fontWeight != oldWidget.fontWeight ||
        widget.lineHeight != oldWidget.lineHeight ||
        widget.paragraphSpacing != oldWidget.paragraphSpacing ||
        widget.pageMargins != oldWidget.pageMargins ||
        widget.textAlign != oldWidget.textAlign ||
        widget.publisherStyles != oldWidget.publisherStyles ||
        widget.singleColumn != oldWidget.singleColumn;
  }
```

`_buildPreferencesMap()`（第 251-276 行）在 `if (widget.publisherStyles != null) { map['publisherStyles'] = widget.publisherStyles; }` 之後新增：

```dart
    if (widget.publisherStyles != null) {
      map['publisherStyles'] = widget.publisherStyles;
    }
    if (widget.singleColumn != null) {
      map['singleColumn'] = widget.singleColumn;
    }
    return map;
  }
```

- [x] **Step 4：執行測試確認通過**

```bash
flutter test test/reader/foliate_epub_reader_view_test.dart
```

Expected：全數通過。

- [x] **Step 5：`flutter analyze`**

```bash
flutter analyze
```

Expected：`No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "feat(epic-18): FoliateEpubReaderView 新增 singleColumn 建構參數"
```

---

### Task 4：`ResolvedPreferences`／`ReaderPrefsManagerImpl`／`ReaderScreen` 接線

**Files:**
- Modify: `app/lib/reader/resolved_preferences.dart`
- Modify: `app/lib/reader/reader_prefs_manager_impl.dart`
- Modify: `app/lib/screens/reader_screen.dart:1656`（`FoliateEpubReaderView(...)` 建構呼叫，`publisherStyles: resolved.publisherStyles,` 之後）
- Test: `app/test/reader/resolved_preferences_test.dart`
- Test: `app/test/reader/reader_prefs_manager_test.dart`
- Test: `app/test/screens/reader_screen_test.dart`（擴充既有測試）

**Interfaces:**
- Consumes：`BookReaderPrefs.singleColumn`（Task 1）、`FoliateEpubReaderView.singleColumn`（Task 3）
- Produces：`ResolvedPreferences.singleColumn`（`bool?`，`ReaderPrefsManagerImpl.resolve()` 直接透傳 `loaded.bookPrefs.singleColumn`，無全域預設層）；`ReaderScreen._buildNativeView()` 建構 `FoliateEpubReaderView` 時傳入 `singleColumn: resolved.singleColumn`

- [x] **Step 1：撰寫失敗測試**

在 `app/test/reader/resolved_preferences_test.dart`，修改既有的唯一一個 `test(...)`（第 12-50 行），在建構子呼叫的 `publisherStyles: null,` 之後新增一行：

```dart
    const resolved = ResolvedPreferences(
      writingMode: null,
      fontFamily: null,
      fontSize: null,
      fontWeight: null,
      lineHeight: null,
      paragraphSpacing: null,
      pageMargins: null,
      textAlign: null,
      publisherStyles: null,
      singleColumn: null,
      pageTurnMode: PageTurnMode.paginated,
```

並在 `expect(resolved.textAlign, isNull);` 之後新增斷言：

```dart
    expect(resolved.fontSize, isNull);
    expect(resolved.textAlign, isNull);
    expect(resolved.singleColumn, isNull);
```

在 `app/test/reader/reader_prefs_manager_test.dart`，修改既有的 `'EPUB 字型/排版欄位原樣透傳（不套用任何預設值，維持既有 pass-through 語意）'` 測試（第 160-176 行），在 `expect(resolved.publisherStyles, isNull);` 之後新增：

```dart
      expect(resolved.publisherStyles, isNull);
      expect(resolved.singleColumn, isNull);
    });
```

並修改既有的 `'單書覆寫存在時，優先套用單書覆寫，忽略全域預設'` 測試（第 64-90 行），在 `bookPrefs` 建構子的 `showFooter: false,` 之後新增 `singleColumn: true,`：

```dart
        bookPrefs: const BookReaderPrefs(
          pageTurnModeOverride: PageTurnMode.scroll,
          screenOrientationOverride: ScreenOrientationSetting.lock90,
          pdfFitMode: PdfFitMode.fitWidth,
          pdfContrast: 20,
          dualPageMode: DualPageMode.always,
          dualPageCoverAlone: false,
          dualPageDirection: DualPageDirection.rtl,
          showHeader: false,
          showFooter: false,
          singleColumn: true,
        ),
```

並在 `expect(resolved.showFooter, isFalse);` 之後新增：

```dart
      expect(resolved.showFooter, isFalse);
      expect(resolved.singleColumn, isTrue);
    });
```

在 `app/test/screens/reader_screen_test.dart`，修改既有的 `'流式 EPUB 開書後，ReaderSettingsSheet 變動的偏好正確傳遞到 FoliateEpubReaderView'` 測試（第 195-238 行），在 `await tester.tap(find.byKey(const Key('reader_settings_writing_mode_vertical')));` 與其 `pumpAndSettle` 之後、`final updatedView = ...` 之前，新增：

```dart
    await tester.tap(find.byKey(const Key('reader_settings_writing_mode_vertical')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reader_settings_single_column')));
    await tester.pumpAndSettle();

    final updatedView =
        tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView));
    expect(updatedView.writingMode, WritingMode.vertical);
    expect(updatedView.singleColumn, isTrue);
  });
```

- [x] **Step 2：執行測試確認失敗**

```bash
flutter test test/reader/resolved_preferences_test.dart test/reader/reader_prefs_manager_test.dart test/screens/reader_screen_test.dart
```

Expected：`resolved_preferences_test.dart`／`reader_prefs_manager_test.dart` 因 `ResolvedPreferences` 建構子不接受 `singleColumn` 參數而編譯失敗；`reader_screen_test.dart` 因 `find.byKey(const Key('reader_settings_single_column'))` 找不到元件（Task 5 尚未實作）而執行期失敗——此為預期中「部分依賴後續 Task」的暫時失敗，Task 4 本身先完成 Step 3 的接線程式碼，`reader_screen_test.dart` 這一個新增斷言會在 Task 5 完成後才真正轉綠燈（見 Step 4 說明）。

- [x] **Step 3：實作接線**

在 `app/lib/reader/resolved_preferences.dart` 第 35 行（`final bool? publisherStyles;`）之後新增欄位：

```dart
  final bool? publisherStyles;

  /// 強制單欄版面偏好（epic-18-reader-device-qa Issue 5）：與 EPUB 字型/
  /// 排版欄位同組 pass-through 語意（見類別頂端文件），無既存安全預設值，
  /// `null` 原樣透傳給 [FoliateEpubReaderView]。
  final bool? singleColumn;
```

建構子（第 59-84 行）在 `this.publisherStyles,` 之後新增：

```dart
    this.publisherStyles,
    this.singleColumn,
```

在 `app/lib/reader/reader_prefs_manager_impl.dart` 的 `resolve()`（第 144-178 行）在 `publisherStyles: book.publisherStyles,` 之後新增：

```dart
      publisherStyles: book.publisherStyles,
      singleColumn: book.singleColumn,
```

在 `app/lib/screens/reader_screen.dart` 第 1656 行（`publisherStyles: resolved.publisherStyles,`）之後新增：

```dart
            publisherStyles: resolved.publisherStyles,
            singleColumn: resolved.singleColumn,
```

- [x] **Step 4：實作 Task 5（ReaderSettingsSheet UI）前的過渡確認**

`reader_screen_test.dart` 新增的斷言依賴 `Key('reader_settings_single_column')`（Task 5 產物）才能通過。先執行不含該斷言影響的其餘測試確認 Task 4 本身程式碼正確：

```bash
flutter test test/reader/resolved_preferences_test.dart test/reader/reader_prefs_manager_test.dart
```

Expected：全數通過。

`reader_screen_test.dart` 的新斷言留待 Task 5 完成後，於 Task 5 的驗證步驟中一併跑過確認轉綠燈（不在此 Task 重複執行整份 `reader_screen_test.dart`，避免因 Task 5 尚未完成而看到誤導性的紅燈）。

- [x] **Step 5：`flutter analyze`**

```bash
flutter analyze
```

Expected：`No issues found!`（`reader_screen.dart` 新增的一行參數傳遞不影響靜態分析結果，即使 Task 5 尚未完成）。

- [x] **Step 6：Commit**

```bash
git add app/lib/reader/resolved_preferences.dart app/lib/reader/reader_prefs_manager_impl.dart app/lib/screens/reader_screen.dart app/test/reader/resolved_preferences_test.dart app/test/reader/reader_prefs_manager_test.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-18): ResolvedPreferences/ReaderPrefsManagerImpl/ReaderScreen 接通 singleColumn 透傳"
```

---

### Task 5：`ReaderSettingsSheet` 新增「強制單欄（直排）」開關

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart`
- Test: `app/test/screens/reader_settings_sheet_test.dart`

**Interfaces:**
- Consumes：`BookReaderPrefs.singleColumn`（Task 1）
- Produces：`Key('reader_settings_single_column')` 的 `SwitchListTile`，`value: _singleColumn`（未持久化時預設 `false`，關閉），`onChanged` 更新本地狀態並透過 `_notifyChanged()` 回報含 `singleColumn` 的完整 `BookReaderPrefs`

- [x] **Step 1：撰寫失敗測試**

在 `app/test/screens/reader_settings_sheet_test.dart`，於既有 `'切換頁首/頁尾開關不會清空其他既有覆寫欄位（回歸檢查）'` 測試（第 437-454 行）之後、`'點擊關閉按鈕後，Bottom Sheet 關閉（Navigator.pop 生效）'` 測試（第 456 行）之前，插入：

```dart
  testWidgets('強制單欄開關初始值反映 prefs（未持久化時預設關閉）', (tester) async {
    await _pumpSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('reader_settings_single_column')))
          .value,
      isFalse,
    );
  });

  testWidgets('已持久化 singleColumn=true 時，強制單欄開關初始值反映為開啟', (tester) async {
    await _pumpSheet(
      tester,
      const BookReaderPrefs(singleColumn: true),
      (_) {},
    );

    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('reader_settings_single_column')))
          .value,
      isTrue,
    );
  });

  testWidgets('開啟強制單欄開關後，onChanged 帶入 singleColumn=true 且不影響其他既有覆寫欄位',
      (tester) async {
    BookReaderPrefs? result;
    await _pumpSheet(
      tester,
      const BookReaderPrefs(
        writingModeOverride: WritingMode.vertical,
        showHeader: false,
      ),
      (prefs) => result = prefs,
    );

    await tester.tap(find.byKey(const Key('reader_settings_single_column')));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.singleColumn, isTrue);
    expect(result!.writingModeOverride, WritingMode.vertical);
    expect(result!.showHeader, isFalse);
  });
```

- [x] **Step 2：執行測試確認失敗**

```bash
flutter test test/screens/reader_settings_sheet_test.dart
```

Expected：新增的 3 個測試皆因找不到 `Key('reader_settings_single_column')` 而失敗（`findsOneWidget` 得到 `findsNothing`）。

- [x] **Step 3：實作 `ReaderSettingsSheet` 開關**

在 `app/lib/screens/reader_settings_sheet.dart` 第 56-57 行（`_showHeader`/`_showFooter` 狀態欄位）之後新增：

```dart
  late bool _showHeader;
  late bool _showFooter;
  late bool _singleColumn;
```

`initState()`（第 59-81 行）在 `_showFooter = widget.prefs.showFooter ?? true;` 之後新增：

```dart
    _showHeader = widget.prefs.showHeader ?? true;
    _showFooter = widget.prefs.showFooter ?? true;
    _singleColumn = widget.prefs.singleColumn ?? false;
  }
```

`didUpdateWidget()`（第 84-109 行）內同樣位置（`_showFooter = widget.prefs.showFooter ?? true;` 之後）新增：

```dart
        _showHeader = widget.prefs.showHeader ?? true;
        _showFooter = widget.prefs.showFooter ?? true;
        _singleColumn = widget.prefs.singleColumn ?? false;
      });
    }
  }
```

`_notifyChanged()`（第 115-131 行）在 `showFooter: _showFooter,` 之後新增：

```dart
      showHeader: _showHeader,
      showFooter: _showFooter,
      singleColumn: _singleColumn,
    ));
  }
```

`build()` 內既有的 `reader_settings_show_footer` `SwitchListTile`（第 250-258 行）之後新增：

```dart
                SwitchListTile(
                  key: const Key('reader_settings_show_footer'),
                  title: const Text('顯示頁尾'),
                  value: _showFooter,
                  onChanged: (v) => setState(() {
                    _showFooter = v;
                    _notifyChanged();
                  }),
                ),
                SwitchListTile(
                  key: const Key('reader_settings_single_column'),
                  title: const Text('強制單欄（直排）'),
                  value: _singleColumn,
                  onChanged: (v) => setState(() {
                    _singleColumn = v;
                    _notifyChanged();
                  }),
                ),
                const SizedBox(height: 12),
                _buildWritingModeOverrideRow(),
```

- [x] **Step 4：執行測試確認通過**

```bash
flutter test test/screens/reader_settings_sheet_test.dart
```

Expected：全數通過。

- [x] **Step 5：補跑 Task 4 遺留的 `reader_screen_test.dart` 斷言**

```bash
flutter test test/screens/reader_screen_test.dart
```

Expected：全數通過，含 Task 4 Step 1 新增、依賴本 Task 產物的 `expect(updatedView.singleColumn, isTrue);` 斷言。

- [x] **Step 6：`flutter analyze`**

```bash
flutter analyze
```

Expected：`No issues found!`

- [x] **Step 7：Commit**

```bash
git add app/lib/screens/reader_settings_sheet.dart app/test/screens/reader_settings_sheet_test.dart
git commit -m "feat(epic-18): ReaderSettingsSheet 新增強制單欄（直排）開關"
```

---

### Task 6：`main.js` `applyPreferences` 接上 `max-column-count` + 核心症狀回歸測試

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`
- Create: `app/integration_test/foliate_single_column_test.dart`

**Interfaces:**
- Consumes：`prefs.singleColumn`（`boolean | undefined`，由原生端 `FoliateEpubReaderView.kt` 既有的 `Map<String, Any?>` → JSON 透傳機制原樣送達，見 Global Constraints）
- Produces：`prefs.singleColumn` 為 `boolean` 型別時，呼叫 `view.renderer.setAttribute('max-column-count', prefs.singleColumn ? '1' : '2')`；非 `boolean`（`undefined`，或理論上不應出現但仍防禦性排除的 `null`/其他型別）時完全不呼叫，保留 `paginator.js` 內建預設值 `2`

- [x] **Step 1：實作 `main.js` 變更（本檔案無 JS 單元測試，見 Global Constraints，直接實作後以 Step 2 的 `integration_test` 驗證）**

修改 `app/android/app/src/main/assets/foliate/main.js` 第 105-118 行的 `window.applyPreferences`：

```js
/**
 * 套用完整偏好設定（開書當下的 initialPreferences，或後續 setPreferences
 * 呼叫，兩者格式相同）：pageTurnMode 對應 Paginator 的 flow 屬性、
 * singleColumn 對應 Paginator 的 max-column-count 屬性（epic-18-
 * reader-device-qa Issue 5，強制直排 EPUB 單欄呈現，避免部分書籍被內建
 * --_max-column-count: 2 拆成需要多按一次翻頁的兩欄版面），兩者皆是獨立於
 * CSS 覆蓋之外的 setAttribute 呼叫；其餘 9 項透過 setStyles() 疊加 CSS。
 * 暴露為 window 全域函式供原生端 evaluateJavascript 呼叫（見
 * FoliateEpubReaderView.kt setPreferences()）。
 */
window.applyPreferences = function (prefs) {
  if (prefs.pageTurnMode) {
    view.renderer.setAttribute(
      'flow',
      prefs.pageTurnMode === 'scroll' ? 'scrolled' : 'paginated',
    )
  }
  if (typeof prefs.singleColumn === 'boolean') {
    // max-column-count 是 CSS calc() 用的純數字乘數，非長度屬性，不需要
    // 帶單位（與 Issue 4 的 margin-top/margin-bottom 不同，見 Global
    // Constraints）。用 typeof === 'boolean' 而非 !== undefined，排除
    // undefined（Dart 端 null，未加入 map，預期情況）之外，也防禦性排除
    // 理論上不應出現、但透過 evaluateJavascript 傳遞 JSON 時無法在型別
    // 層級排除的 null 或其他型別，避免誤判為「明確覆寫為允許雙欄」而呼叫
    // setAttribute('max-column-count', '2')。非 boolean 時完全不呼叫，
    // 保留 paginator.js 內建預設值 2（見 spec.md「singleColumn 偏好」）。
    view.renderer.setAttribute('max-column-count', prefs.singleColumn ? '1' : '2')
  }
  // epic-17 Issue 8：劃線/備註繪製需要知道目前實際生效的排版方向，見
  // currentWritingMode 宣告處註解。
  if (prefs.writingMode) {
    currentWritingMode = prefs.writingMode
  }
  view.renderer.setStyles([fontFaceCss, buildOverrideCss(prefs)])
}
```

- [x] **Step 2：撰寫核心症狀回歸測試（`integration_test`，需真機/模擬器）**

新增 `app/integration_test/foliate_single_column_test.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/foliate_epub_reader_view.dart';
import 'package:elinkbook/reader/writing_mode.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑。
/// 比照 app/integration_test/foliate_toc_footer_test.dart 既有的
/// _stageAssetAsFile 手法。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      '直排且開啟強制單欄後，連續點擊翻頁 pageIndex 每次皆前進，不會停留在原頁碼（Issue 5 核心症狀回歸測試——'
      '修復前，2 欄模式下第一次點擊只移動到同一邏輯頁的第二欄，pageIndex 停留不變，需要點第二次才前進）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/issue9_vertical_pagejump.epub',
        'foliate_single_column.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    final completer = Completer<void>();
    String? errorMessage;
    final key = GlobalKey<State<FoliateEpubReaderView>>();
    EpubPositionInfo? lastPosition;

    await tester.pumpWidget(
      MaterialApp(
        home: FoliateEpubReaderView(
          key: key,
          filePath: samplePath,
          onPageRendered: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (message) {
            errorMessage = message;
            if (!completer.isCompleted) completer.complete();
          },
          writingMode: WritingMode.vertical,
          singleColumn: true,
          onLocatorChanged: (info) => lastPosition = info,
        ),
      ),
    );

    await completer.future.timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(errorMessage, isNull,
        reason: '應觸發 onPageRendered，但 onError 訊息為: $errorMessage');

    final openPageIndex = lastPosition?.pageIndex;
    expect(openPageIndex, isNotNull, reason: '開書後應已收到 pageIndex');

    final pageIndices = <int>[openPageIndex!];
    for (var i = 0; i < 5; i++) {
      FoliateEpubReaderView.nextPage(key);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(errorMessage, isNull, reason: '第 ${i + 1} 次翻頁後不應觸發 onError');
      final currentPageIndex = lastPosition?.pageIndex;
      expect(currentPageIndex, isNotNull,
          reason: '第 ${i + 1} 次翻頁後應收到 pageIndex');
      pageIndices.add(currentPageIndex!);
    }

    // 核心回歸斷言（issues.md Issue 5 驗收標準 + 使用者要求）：強制單欄後
    // 每一次點擊都必須讓 pageIndex 前進，不能連續兩次讀到相同數值——這正是
    // 「需要點兩次才變化一次」症狀的直接反例。不斷言差值恆為 1（見本計劃
    // Global Constraints「頁碼估算既有限制」，pageIndex 是近似值，差值大小
    // 依內容字元密度而異，但「絕不停留在原值」是可以且應該保證的）。
    for (var i = 1; i < pageIndices.length; i++) {
      expect(pageIndices[i], greaterThan(pageIndices[i - 1]),
          reason: '第 $i 次翻頁後 pageIndex 應嚴格前進（不可停留在 ${pageIndices[i - 1]} 不變），'
              '完整序列：$pageIndices');
    }
  });
}
```

- [x] **Step 3：於真機/模擬器執行新測試確認通過**

```bash
flutter devices
flutter test integration_test/foliate_single_column_test.dart -d 3CEF42ECD491687
```

Expected：測試通過，`pageIndices` 序列嚴格遞增（例如 `[3, 4, 6, 7, 9, 10]` 這類容許差值不固定為 1，但絕不重複的序列皆算通過；若看到連續兩個相同數值如 `[3, 3, 5, ...]` 則測試失敗，代表修復未生效）。

- [x] **Step 4：跑既有 `foliate_toc_footer_test.dart`／`foliate_epub_reader_view_test.dart` 確認無回歸**

```bash
flutter test integration_test/foliate_toc_footer_test.dart -d 3CEF42ECD491687
flutter test integration_test/foliate_epub_reader_view_test.dart -d 3CEF42ECD491687
```

Expected：全數通過（`main.js` 的變更是新增一個獨立的 `if` 分支，不影響既有 `pageTurnMode`/`writingMode` 分支的既有行為）。

- [x] **Step 5：`flutter analyze`**

```bash
flutter analyze
```

Expected：`No issues found!`

- [x] **Step 6：Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js app/integration_test/foliate_single_column_test.dart
git commit -m "feat(epic-18): main.js applyPreferences 接上 max-column-count，新增單欄翻頁回歸測試"
```

---

### Task 7：真機驗收——強制單欄開關的實際效果與使用者要求的翻頁行為

**Files:** 無程式碼異動（純驗收，`issues.md` Issue 5 驗收標準要求的真機確認）

**Interfaces:**
- Consumes：Task 1-6 已 commit 的完整 `singleColumn` 偏好管線
- Produces：驗收結論，供人類決定是否合併；若發現任一項不符預期，記錄具體觀察交由人類決定後續處理

**執行後狀態（2026-07-25，Issue 5 合併時記錄）**：Task 1-6 已完成並經三輪 code review（見 `tmp/epic-18/reviews/review-issue-5.md`／`review-issue-5-round2.md`／`review-issue-5-round3.md`），已合併回 `main`（merge commit `b075a39`）。本 Task（真機人工視覺驗收）**未逐步執行完成**——第三輪審查以真機 mutation test 發現，`singleColumn` 在既有測試裝置 `3CEF42ECD491687` 的螢幕幾何下，對直排書籍的實際欄數計算是 no-op（根因見 `paginator.js` 的 `divisor` 公式），也就是說下方 Step 2-4 描述的視覺效果在該裝置上很可能原本就觀察不到差異，貿然逐項打勾會造成「已人工確認生效」的錯誤印象。是否真的在任何裝置上有效、以及本 Task 的驗收步驟本身是否需要調整，已另立 `issues.md` Issue 6 追蹤調查，不在本次合併範圍內逐步執行。經人類確認先行合併（六層透傳機制與可逆性本身正確，已充分驗證），本 Task 的核取方塊維持未勾選狀態，如實反映「尚未有可信的真機視覺驗收結論」。

- [ ] **Step 1：建置並安裝 debug APK 到真機**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
adb devices -l
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

Expected：`adb devices -l` 列出 `3CEF42ECD491687`；建置與安裝皆成功（`Success`）。

- [ ] **Step 2：確認預設關閉時維持現有行為（不強制改變）**

用 `tmp/issues/2-1.png`／`2-2.png` 對應的問題書籍/字級組合開書，切換為直排，**不開啟**「強制單欄」。確認畫面行為與修改前一致（該書仍會被拆成兩欄，需要點兩次翻頁才能看完原本一頁），證明本 Issue 的預設值（`null`，未覆寫）不影響現有多數書籍的既有行為。

Expected：與 Issue 5 開發前的既有行為一致（不強制改變任何顯示效果）。

- [ ] **Step 3：開啟「強制單欄」後，確認 2 欄症狀消除**

開啟版面設定（`ReaderSettingsSheet`），開啟「強制單欄（直排）」開關，關閉設定畫面。確認：
- 原本需要兩次翻頁才能看完的內容，現在整合為一次翻頁可見（比照 `tmp/issues/3.png` 參考效果）。
- 頁尾頁碼／進度捲軸不再出現「同一個頁碼連續兩次點擊翻頁都沒有變化」的情形——**這是使用者本次明確要求的驗證重點**：連續點擊翻頁熱區（或頁尾的下一頁動作）5-10 次，肉眼確認頁尾頁碼**每次點擊都會往前跳動**，不會出現「點一次頁碼沒變、點第二次才變」的現象。

Expected：兩欄症狀消除；頁碼變化為「每次點擊皆前進」，不需要點兩次才看到頁碼變化（與 Task 6 的自動化回歸測試結論一致）。

- [ ] **Step 4：確認關閉「強制單欄」後可退回雙欄行為（可逆性）**

在同一本書、同一次閱讀 session 中，再次關閉「強制單欄」開關。確認畫面重新出現兩欄拆分行為（`main.js` 的 `setAttribute('max-column-count', '2')` 正確生效，非只有「開啟」方向可用）。

Expected：雙向切換皆正確生效，不需要重新開書。

- [ ] **Step 5：確認橫排與其他既有書籍不受影響（回歸確認）**

切換回橫排閱讀同一本書，以及開啟一本原本就不會拆欄的一般 EPUB（例如 `sample.epub`），確認畫面顯示與翻頁行為皆與 Issue 5 開發前一致。

Expected：橫排與正常書籍的既有行為完全不受影響。

無需 commit（本 Task 純驗收，不變更任何檔案）。

---

## Self-Review Notes（撰寫計劃時的自我檢查）

- **spec 覆蓋度**：`spec.md`「`singleColumn` 偏好」表格列出的六層（SQLite／Dart 資料模型／Dart Widget／Dart→原生／原生→JS／JS→foliate-js）分別對應 Task 2／Task 1／Task 3／Task 3／（原生端不需修改，見 Global Constraints）／Task 6；`issues.md` Issue 5 描述列出的六個檔案異動點（`BookReaderPrefs`／schema migration／`ReaderSettingsSheet`／`FoliateEpubReaderView`／`ReaderScreen`／`main.js`）逐一對應 Task 1／2／5／3／4／6；審查修正新增的 SQLite migration round-trip 測試要求（(a) 全新安裝、(b) v11→v12 升級）對應 Task 2 Step 1 兩個測試。使用者本次額外提出的「每次點擊頁碼應一次增減 1，不應點兩次才變化」要求，對應 Task 6 Step 2 的新 `integration_test` 與 Task 7 Step 3 的真機人工確認，兩者皆明確驗證這個具體症狀（且在 Global Constraints 說明了為何斷言目標是「絕不停留原值」而非「差值恆為 1」，避免自我矛盾的過度承諾）。
- **無佔位符掃描**：所有 Task 皆附完整可執行的程式碼（每個檔案的修改前後完整片段、完整測試程式碼、完整 `flutter`/`adb`/`git` 指令），無 "TODO"/"視情況" 字樣。`issues.md`/`spec.md` 原文刻意留給實作階段決定的開放式描述（例如 `dualPageCoverAlone` 語意層級的三態設計、下邊距公式——後者屬於 Issue 4 範圍不在本計劃）皆不影響本計劃，本計劃涵蓋的部分（`singleColumn` 六層透傳機制、SQLite migration 位置）皆已在 Global Constraints 中做出具體、可執行的落地決定。
- **型別/介面一致性**：`singleColumn`／`single_column`／`'singleColumn'` 三種命名（Dart 欄位、SQLite 欄位、JS/JSON map key）在 Task 1-6 全數檔案中用法一致，比照既有 `showHeader`/`show_header`/`'showHeader'`（若存在，實際上 `showHeader` 目前不透傳給原生端，僅 `singleColumn`/`publisherStyles`/`pageMargins` 等既有可透傳欄位的既有命名慣例）與 `publisherStyles` 的既有命名慣例；`ResolvedPreferences.singleColumn`／`BookReaderPrefs.singleColumn`／`FoliateEpubReaderView.singleColumn` 三者皆為 `bool?`，語意（`null`＝未覆寫）在三層之間保持一致，未在任何一層意外套用非 null 預設值。
- **`else` 分支陷阱已於 Global Constraints 明確記錄並在 Task 2 Step 3 正確實作**：這是撰寫本計劃時追蹤 `onUpgrade` 既有結構才發現的非顯而易見陷阱（`_addEpubLayoutColumn` 的「頂層無條件執行」寫法對 `books` 表安全，但直接照抄用在 `book_reader_prefs` 表的新欄位會導致 `oldVersion == 1` 裝置升級時的 `duplicate column name` 崩潰），已透過 Task 2 Step 3 的程式碼與 Global Constraints 的說明具體避開。

---

## Execution Handoff

Plan complete and saved to `docs/epics/epic-18-reader-device-qa/plans/plan-issue-5.md`. Two execution options:

1. **Subagent-Driven (recommended)** — 逐一 Task 派出新的 subagent 執行，每個 Task 之間進行審查、快速迭代。
2. **Inline Execution** — 在目前 session 中依序執行，批次執行並在檢查點暫停確認。

要採用哪一種？
