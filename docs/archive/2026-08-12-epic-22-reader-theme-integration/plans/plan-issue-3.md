# Epic 22 Issue 3 — 閱讀器浮動按鈕（FAB）顏色跟隨主題 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 流式 EPUB 顯示時，閱讀畫面 6 顆浮動圓形控制按鈕（返回/目錄/版面設定/書籤/筆記/進度）的底色與圖示色跟隨 `Theme.of(context)`；EPUB 固定版面（漫畫）顯示時維持現有寫死 `Colors.black54`/`Colors.white`。

**Architecture:** 比照 epic-22 Issue 1（`_themedTextColor`/`_themedBackgroundColor`）與 Issue 2 已建立的既有模式，在 `_ReaderScreenState` 新增兩個非 nullable getter `_themedFabBackgroundColor`/`_themedFabIconColor`：顯示流式 EPUB 時回傳主題色，顯示固定版面時直接回傳既有寫死值（與 Issue 1/2 的 getter 不同，這裡不用 `Color?` + `?? fallback` 模式，因為 FAB 按鈕任何情境下都一定需要一個顏色，沒有「不適用」的 null 語意）。6 個按鈕的 `Container(color: ...)`／`Icon(color: ...)` 皆改用這兩個 getter。

**Tech Stack:** Flutter/Dart（`ReaderScreen`）。

## Global Constraints

- 不新增建構子參數——直接重用既有的 `context`（`Theme.of(context)`）與 `_isFixedLayout` 欄位，比照 Issue 1/2 已建立的既有慣例。
- EPUB 固定版面（`_isFixedLayout == true`）時，FAB 顏色維持寫死 `Colors.black54`/`Colors.white` 不變——理由同 Issue 2 頁首/頁尾的既有決策：固定版面頁面內容本身不受本 Epic 影響（維持原有顏色，通常是白底圖片），深色主題下若控制按鈕也跟著變成同樣深色系，在不可預期的圖片背景上容易失去可視對比。
- PDF 不受影響——這組浮動按鈕的呼叫點既有的 `format == BookFormat.epub` 判斷式已天然排除 PDF。
- 顏色不可用已棄用的 `Color.value`／`.withOpacity()` API——本專案已在 Issue 1 審查中確認 `Color.value` 於目前 Flutter SDK（`^3.11.5`）棄用，`.withOpacity()` 同批棄用，一律改用 `.toARGB32()`／`.withValues(alpha: ...)`。

---

## File Structure

- **Modify:** `app/lib/screens/reader_screen.dart`
  - 新增 `Color get _themedFabBackgroundColor`／`Color get _themedFabIconColor` 兩個 getter。
  - 6 個浮動按鈕（`reader_foliate_back_button`／`reader_foliate_toc_button`／`reader_foliate_settings_button`／`reader_foliate_bookmark_toggle_button`／`reader_foliate_notes_button`／`reader_foliate_progress_button`）的 `Container(color: Colors.black54)` 改為 `Container(color: _themedFabBackgroundColor)`，各自 `Icon(..., color: Colors.white)` 改為 `Icon(..., color: _themedFabIconColor)`。
- **Test:** `app/test/screens/reader_screen_test.dart`（既有檔案）

---

### Task 1：新增 `_themedFabBackgroundColor`／`_themedFabIconColor` getter，並套用到全部 6 個浮動按鈕

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: 既有的 `Theme.of(context)`（`BuildContext` 存取）、既有的 `_isFixedLayout`（`_ReaderScreenState` 私有欄位）。
- Produces: `Color get _themedFabBackgroundColor`／`Color get _themedFabIconColor`（`_ReaderScreenState` 私有 getter，非 nullable）。

- [ ] **Step 1: 新增測試——深色主題下「返回」按鈕（無額外前置條件、恆可點擊）顏色跟隨主題**

在 `app/test/screens/reader_screen_test.dart` 既有的「深色主題下開啟版面設定 Bottom Sheet」測試（`epic-22-reader-theme-integration Issue 5`）之後，新增：

```dart

  testWidgets(
      '深色主題下流式 EPUB「返回」浮動按鈕底色/圖示色跟隨 Theme.of(context)'
      '（epic-22-reader-theme-integration Issue 3）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_fab_color_dark',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // find.ancestor 可能撿到不只一個 Container（例如 Scaffold/MaterialApp
    // 內部也會用到 Container），用 .first 精確鎖定最近的一個（緊包住
    // IconButton 的那一個，即 ClipOval 底下設定 color 的那個）。
    final backContainer = tester.widget<Container>(find.ancestor(
      of: find.byKey(const Key('reader_foliate_back_button')),
      matching: find.byType(Container),
    ).first);
    final backIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_foliate_back_button')),
      matching: find.byType(Icon),
    ));

    final expectedTheme = buildThemeData(AppTheme.dark);
    expect(
      backContainer.color,
      expectedTheme.colorScheme.onSurface.withValues(alpha: 0.54),
    );
    expect(backIcon.color, expectedTheme.colorScheme.surface);
  });

  testWidgets(
      '淺色主題下流式 EPUB「返回」浮動按鈕底色/圖示色跟隨 Theme.of(context)'
      '（epic-22-reader-theme-integration Issue 3）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.light),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_fab_color_light',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // find.ancestor 可能撿到不只一個 Container（例如 Scaffold/MaterialApp
    // 內部也會用到 Container），用 .first 精確鎖定最近的一個（緊包住
    // IconButton 的那一個，即 ClipOval 底下設定 color 的那個）。
    final backContainer = tester.widget<Container>(find.ancestor(
      of: find.byKey(const Key('reader_foliate_back_button')),
      matching: find.byType(Container),
    ).first);
    final backIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_foliate_back_button')),
      matching: find.byType(Icon),
    ));

    final expectedTheme = buildThemeData(AppTheme.light);
    expect(
      backContainer.color,
      expectedTheme.colorScheme.onSurface.withValues(alpha: 0.54),
    );
    expect(backIcon.color, expectedTheme.colorScheme.surface);
  });

  testWidgets(
      'EPUB 固定版面：不論主題為何，浮動按鈕維持既有寫死 Colors.black54/'
      'Colors.white（epic-22-reader-theme-integration Issue 3，固定版面'
      '內容通常是白底圖片，控制按鈕跟著深色主題變色會失去對比）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_fab_color_fxl',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // find.ancestor 可能撿到不只一個 Container（例如 Scaffold/MaterialApp
    // 內部也會用到 Container），用 .first 精確鎖定最近的一個（緊包住
    // IconButton 的那一個，即 ClipOval 底下設定 color 的那個）。
    final backContainer = tester.widget<Container>(find.ancestor(
      of: find.byKey(const Key('reader_foliate_back_button')),
      matching: find.byType(Container),
    ).first);
    final backIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_foliate_back_button')),
      matching: find.byType(Icon),
    ));

    expect(backContainer.color, Colors.black54);
    expect(backIcon.color, Colors.white);
  });

  testWidgets(
      '深色主題下流式 EPUB「版面設定」浮動按鈕（有 onPressed 分流邏輯的'
      '按鈕）顏色同樣跟隨主題（epic-22-reader-theme-integration Issue 3，'
      '驗證不只最簡單的返回按鈕生效）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_fab_color_settings_dark',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final settingsContainer = tester.widget<Container>(find.ancestor(
      of: find.byKey(const Key('reader_foliate_settings_button')),
      matching: find.byType(Container),
    ).first);
    final settingsIcon = tester.widget<Icon>(find.descendant(
      of: find.byKey(const Key('reader_foliate_settings_button')),
      matching: find.byType(Icon),
    ));

    final expectedTheme = buildThemeData(AppTheme.dark);
    expect(
      settingsContainer.color,
      expectedTheme.colorScheme.onSurface.withValues(alpha: 0.54),
    );
    expect(settingsIcon.color, expectedTheme.colorScheme.surface);
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "epic-22-reader-theme-integration Issue 3"`
Expected: 前兩個測試（深色/淺色主題「返回」按鈕）與第四個測試（「版面設定」按鈕）FAIL——目前按鈕仍寫死 `Colors.black54`/`Colors.white`。第三個測試（固定版面維持黑色）預期本來就 PASS，是回歸基準測試。

- [ ] **Step 3: 新增兩個 getter**

在 `app/lib/screens/reader_screen.dart` 找到 Issue 1 新增的：

```dart
  Color? get _themedTextColor =>
      _isFixedLayout ? null : Theme.of(context).colorScheme.onSurface;
  Color? get _themedBackgroundColor =>
      _isFixedLayout ? null : Theme.of(context).scaffoldBackgroundColor;
```

緊接在這兩個 getter 之後新增：

```dart

  /// 浮動控制按鈕（返回/目錄/版面設定/書籤/筆記/進度）的底色/圖示色，
  /// 跟隨 Theme.of(context)（epic-22-reader-theme-integration Issue 3）。
  /// 顯示流式 EPUB 時使用主題色——**底色刻意取 `colorScheme.onSurface`
  /// （而非 `surface`）**：`surface` 在淺色/深色主題下分別接近純白/接近
  /// 頁面背景本身（見 app_theme_data.dart），若拿來當按鈕底色，淺色主題
  /// 下會讓按鈕在近白頁面上幾乎隱形（重蹈 Issue 5 才修過的「控制元件顏色
  /// 跟頁面背景太接近而失去可視性」問題）。`onSurface` 在淺色主題下是
  /// 近黑色、深色主題下是近白色，天生就與同一主題的頁面背景形成對比，
  /// 淺色主題下維持與改動前 `Colors.black54` 相近的深色圓形觀感，深色
  /// 主題下則變成淺色圓形、正確對比深色頁面。半透明度沿用原本
  /// `Colors.black54` 的 54% 數值，維持「浮動、可透視底下內容」的既有
  /// 視覺語言。圖示色相應取 `colorScheme.surface`（與底色反向搭配，
  /// 維持圖示對底色的可視對比）。顯示 EPUB 固定版面（漫畫）時維持既有
  /// 寫死 Colors.black54/Colors.white——理由同 _themedTextColor：固定
  /// 版面頁面內容本身不受本 Epic 影響（通常是白底圖片），深色主題下若
  /// 控制按鈕也跟著變色，容易在不可預期的圖片背景上失去可視對比（與
  /// Issue 1/2 的 getter 不同，這裡沒有「不適用」的情境，故不用
  /// Color? + ?? fallback 模式，兩個分支各自直接回傳明確的顏色）。
  Color get _themedFabBackgroundColor => _isFixedLayout
      ? Colors.black54
      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54);
  Color get _themedFabIconColor =>
      _isFixedLayout ? Colors.white : Theme.of(context).colorScheme.surface;
```

- [ ] **Step 4: 套用到「返回」按鈕**

找到：

```dart
            if (format == BookFormat.epub && _chromeVisible)
              Positioned(
                top: 16,
                left: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_foliate_back_button'),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
```

改為：

```dart
            if (format == BookFormat.epub && _chromeVisible)
              Positioned(
                top: 16,
                left: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_back_button'),
                      icon: Icon(Icons.arrow_back, color: _themedFabIconColor),
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
```

（`Icon` 前的 `const` 拿掉，因為 `_themedFabIconColor` 是執行期才能求值的 getter。）

- [ ] **Step 5: 套用到「目錄」按鈕**

找到：

```dart
            if (format == BookFormat.epub && _chromeVisible)
              Positioned(
                top: 16,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_foliate_toc_button'),
                      icon: const Icon(Icons.menu_book, color: Colors.white),
                      tooltip: '目錄',
                      onPressed: (_autoDetectedWritingMode == null || !_tocLoaded)
                          ? null
                          : _openToc,
                    ),
                  ),
                ),
              ),
```

改為：

```dart
            if (format == BookFormat.epub && _chromeVisible)
              Positioned(
                top: 16,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_toc_button'),
                      icon: Icon(Icons.menu_book, color: _themedFabIconColor),
                      tooltip: '目錄',
                      onPressed: (_autoDetectedWritingMode == null || !_tocLoaded)
                          ? null
                          : _openToc,
                    ),
                  ),
                ),
              ),
```

- [ ] **Step 6: 套用到「版面設定」按鈕**

找到：

```dart
            if (format == BookFormat.epub && _chromeVisible)
              Positioned(
                top: 72,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_foliate_settings_button'),
                      icon: const Icon(Icons.settings, color: Colors.white),
                      tooltip: '版面設定',
                      onPressed: _isFixedLayout
                          ? _openFxlSettings
                          : (_autoDetectedWritingMode == null ? null : _openLayoutSettings),
                    ),
                  ),
                ),
              ),
```

改為：

```dart
            if (format == BookFormat.epub && _chromeVisible)
              Positioned(
                top: 72,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_settings_button'),
                      icon: Icon(Icons.settings, color: _themedFabIconColor),
                      tooltip: '版面設定',
                      onPressed: _isFixedLayout
                          ? _openFxlSettings
                          : (_autoDetectedWritingMode == null ? null : _openLayoutSettings),
                    ),
                  ),
                ),
              ),
```

- [ ] **Step 7: 套用到「書籤」按鈕**

找到：

```dart
            if (format == BookFormat.epub &&
                _chromeVisible &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 128,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_foliate_bookmark_toggle_button'),
                      icon: Icon(
                        _bookmarkAtCurrentPosition != null
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.white,
                      ),
                      tooltip: _bookmarkAtCurrentPosition != null
                          ? '已加入此頁書籤'
                          : '加入此頁書籤',
                      onPressed:
                          _epubPositionInfo == null ? null : _toggleBookmark,
                    ),
                  ),
                ),
              ),
```

改為：

```dart
            if (format == BookFormat.epub &&
                _chromeVisible &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 128,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_bookmark_toggle_button'),
                      icon: Icon(
                        _bookmarkAtCurrentPosition != null
                            ? Icons.star
                            : Icons.star_border,
                        color: _themedFabIconColor,
                      ),
                      tooltip: _bookmarkAtCurrentPosition != null
                          ? '已加入此頁書籤'
                          : '加入此頁書籤',
                      onPressed:
                          _epubPositionInfo == null ? null : _toggleBookmark,
                    ),
                  ),
                ),
              ),
```

- [ ] **Step 8: 套用到「筆記」按鈕**

找到：

```dart
            if (format == BookFormat.epub &&
                _chromeVisible &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 184,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_foliate_notes_button'),
                      icon: const Icon(Icons.bookmarks, color: Colors.white),
                      tooltip: '筆記',
                      onPressed: (_autoDetectedWritingMode == null ||
                              _epubPositionInfo == null)
                          ? null
                          : () => _openNotesSheet(BookFormat.epub),
                    ),
                  ),
                ),
              ),
```

改為：

```dart
            if (format == BookFormat.epub &&
                _chromeVisible &&
                widget.bookmarksRepository != null)
              Positioned(
                top: 184,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_notes_button'),
                      icon: Icon(Icons.bookmarks, color: _themedFabIconColor),
                      tooltip: '筆記',
                      onPressed: (_autoDetectedWritingMode == null ||
                              _epubPositionInfo == null)
                          ? null
                          : () => _openNotesSheet(BookFormat.epub),
                    ),
                  ),
                ),
              ),
```

- [ ] **Step 9: 套用到「進度/跳頁」按鈕**

找到：

```dart
            if (format == BookFormat.epub && _chromeVisible)
              Positioned(
                top: 240,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_foliate_progress_button'),
                      icon: const Icon(Icons.swap_vert, color: Colors.white),
                      tooltip: '跳頁',
                      onPressed: _openFoliateProgressSheet,
                    ),
                  ),
                ),
              ),
```

改為：

```dart
            if (format == BookFormat.epub && _chromeVisible)
              Positioned(
                top: 240,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: _themedFabBackgroundColor,
                    child: IconButton(
                      key: const Key('reader_foliate_progress_button'),
                      icon: Icon(Icons.swap_vert, color: _themedFabIconColor),
                      tooltip: '跳頁',
                      onPressed: _openFoliateProgressSheet,
                    ),
                  ),
                ),
              ),
```

- [ ] **Step 10: 執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "epic-22-reader-theme-integration Issue 3"`
Expected: PASS，4 個測試全數通過。

- [ ] **Step 11: 用 grep 確認全部 6 處已替換，沒有遺漏**

Run: `grep -n "color: Colors.black54" app/lib/screens/reader_screen.dart`
Expected: 沒有任何符合結果（若還有殘留，代表漏改了某個按鈕，須回頭檢查）。

Run: `grep -c "_themedFabBackgroundColor" app/lib/screens/reader_screen.dart`
Expected: 至少 7（1 個 getter 定義 + 6 個按鈕呼叫點）。

- [ ] **Step 12: 執行完整 `reader_screen_test.dart` 確認零回歸**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS，全數通過。

- [ ] **Step 13: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 14: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-22): 閱讀器浮動按鈕（FAB）顏色跟隨 Theme.of(context)，固定版面維持現況"
```

---

### Task 2：全專案回歸測試 + 真機視覺確認

**Files:** 無新增/修改檔案，純驗證。

**Interfaces:** 無新增介面，驗證 Task 1 整合後的端到端行為。

- [ ] **Step 1: 執行全專案 `flutter test`**

Run: `flutter test`
Expected: 全數通過，無任何回歸。

- [ ] **Step 2: 執行全專案 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3（建議）：真機/模擬器視覺確認**

本 Issue 改動的是純 Flutter widget 屬性（`Container.color`／`Icon.color`），`flutter test` 已完整涵蓋所有可觀察行為，此步驟是建議而非強制：

1. 深色主題下開啟流式 EPUB，確認 6 顆浮動按鈕底色/圖示色與深色主題視覺一致（半透明深色底 + 淺色圖示），且仍清楚可辨識、可點擊。
2. 若手邊有固定版面（FXL）EPUB，開啟後確認浮動按鈕仍維持既有黑底白圖示，不受主題影響。
3. 確認淺色/羊皮紙主題下按鈕視覺與改動前接近（半透明主題色底 + 主題文字色圖示，取代原本純黑底白圖示）。

- [ ] **Step 4: Commit（若真機驗證過程中有任何修正）**

若 Step 3 發現任何問題並修正程式碼，比照 Task 1 的模式（先確認測試涵蓋、修正、重新測試、commit）。若無需修正，本 Step 略過。
