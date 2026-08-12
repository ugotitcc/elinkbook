# Epic 22 Issue 2 — 頁首/頁尾文字色跟隨主題（流式 EPUB），固定版面維持現況 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 流式 EPUB 顯示時，`ReaderScreen` 的頁首（章節名稱）與頁尾（頁碼進度）疊加文字顏色，從寫死的 `Colors.black` 改為跟隨 `Theme.of(context)`；EPUB 固定版面（漫畫）顯示時維持寫死 `Colors.black` 不變。

**Architecture:** Issue 1（已合併回 `main`）已經在 `_ReaderScreenState` 新增了 `Color? get _themedTextColor`——顯示流式 EPUB 時回傳 `Theme.of(context).colorScheme.onSurface`，顯示固定版面時回傳 `null`。本 Issue 純粹是把這個既有 getter 接到頁首/頁尾兩個 `Text` widget 的 `style.color`，`null` 時退回既有的 `Colors.black`（`_themedTextColor ?? Colors.black`）。不需要新增任何 getter、不需要碰 `FoliateEpubReaderView`／`main.js`——這條路徑純粹是 Flutter widget 屬性，跟 Issue 1 的 Dart→原生橋接→JS CSS 路徑完全不相交。

**Tech Stack:** Flutter/Dart（`ReaderScreen`）。

## Global Constraints

- 不新增任何建構子參數／getter——直接重用 Issue 1 已新增的 `_themedTextColor`（`app/lib/screens/reader_screen.dart`，`_ReaderScreenState` 內）。
- EPUB 固定版面（`_isFixedLayout == true`）時，頁首/頁尾文字色維持寫死 `Colors.black`，不受本 Issue 影響（`_themedTextColor` 在這個情境下已回傳 `null`，呼叫端用 `?? Colors.black` 接住）。
- PDF 不受影響——頁首/頁尾 widget 呼叫點既有的 `format == BookFormat.epub` 判斷式已天然排除 PDF，不需新增任何判斷。
- 本 Issue 涉及的 `_buildFoliateHeaderText()`／`_buildFoliateProgressText()` 都是純 Flutter widget（`Container`/`Text`），`flutter test` 可以完整觀察其 `TextStyle.color` 實際值——與 Issue 1 的 WebView CSS 注入不同，**本 Issue 沒有「flutter test 測不到」的驗證缺口**，不需要比照 Issue 1 那樣把真機視覺確認列為不可省略項目。

---

## File Structure

- **Modify:** `app/lib/screens/reader_screen.dart`
  - `_buildFoliateHeaderText()`：`style` 從 `const TextStyle(color: Colors.black, fontSize: 12)` 改為 `TextStyle(color: _themedTextColor ?? Colors.black, fontSize: 12)`（拿掉 `const`，因為 `_themedTextColor` 是執行期才能求值的 getter）。
  - `_buildFoliateProgressText()`：同上。
- **Test:** `app/test/screens/reader_screen_test.dart`（既有檔案）
  - 修正既有的 Issue 43 測試（目前 `MaterialApp` 沒有指定 `theme:`，隱含依賴 Flutter 預設 `ThemeData`，本次必須改為明確指定 `theme: buildThemeData(AppTheme.light)`，否則本次修改後這個測試的斷言基準會變成不可預期的 Flutter Material 3 預設色，而非這個專案自己的 `AppTheme.light` 色值）。
  - 新增深色主題跟隨測試、固定版面維持黑色測試。

---

### Task 1: 頁首/頁尾文字色改為跟隨 `_themedTextColor`

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Issue 1 已新增的 `Color? get _themedTextColor`（`_ReaderScreenState` 私有 getter，顯示流式 EPUB 時回傳 `Theme.of(context).colorScheme.onSurface`，顯示固定版面時回傳 `null`）。
- Produces: 無新公開介面——純粹是既有兩個 private widget-building 方法（`_buildFoliateHeaderText()`／`_buildFoliateProgressText()`）內部 `TextStyle.color` 的求值方式改變，外部可觀察行為即下方測試斷言的內容。

- [x] **Step 1: 修正既有 Issue 43 測試的隱含主題依賴，並新增深色主題／固定版面測試**

找到 `app/test/screens/reader_screen_test.dart` 內既有的測試（開頭是 `testWidgets('流式 EPUB 頁首/頁尾文字：字級為 12、不含按鈕底色與內距……'`），把整個測試方法換成以下版本（差異：`MaterialApp` 新增明確的 `theme: buildThemeData(AppTheme.light)`；兩個 `expect(...Color, Colors.black)` 改為與 `AppTheme.light` 實際色值比對；新增說明本次變動的敘述文字）：

```dart
  testWidgets(
      '流式 EPUB 頁首/頁尾文字：字級為 12、不含按鈕底色與內距，只佔文字本身空間、'
      '文字顏色跟隨 Theme.of(context)（epic-22-reader-theme-integration '
      'Issue 2；epic-18-reader-device-qa Issue 43 的既有測試在此更新——'
      '原本斷言寫死 Colors.black，現在明確指定 AppTheme.light 並比對其實際'
      'onSurface 色值，理由同 Issue 43：拿掉底色後，文字顏色必須與書頁'
      '背景形成足夠對比才看得到）', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_header_footer_no_bg',
      const BookReaderPrefs(showHeader: true, showFooter: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.light),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_header_footer_no_bg',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        pageIndex: 9,
        totalPages: 100,
      ),
    );
    await tester.pump();

    // 觸發沉浸模式讓頁首頁尾顯示
    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    final headerContainer = tester.widget<Container>(
      find.byKey(const Key('reader_foliate_header_text')),
    );
    expect(headerContainer.padding, isNull);
    expect(headerContainer.decoration, isNull);

    final headerText = tester.widget<Text>(find.descendant(
      of: find.byKey(const Key('reader_foliate_header_text')),
      matching: find.byType(Text),
    ));
    expect(headerText.style?.fontSize, 12);
    expect(
      headerText.style?.color,
      buildThemeData(AppTheme.light).colorScheme.onSurface,
    );

    final footerContainer = tester.widget<Container>(
      find.byKey(const Key('reader_foliate_progress_text')),
    );
    expect(footerContainer.padding, isNull);
    expect(footerContainer.decoration, isNull);

    final footerText = tester.widget<Text>(find.descendant(
      of: find.byKey(const Key('reader_foliate_progress_text')),
      matching: find.byType(Text),
    ));
    expect(footerText.style?.fontSize, 12);
    expect(
      footerText.style?.color,
      buildThemeData(AppTheme.light).colorScheme.onSurface,
    );
  });

  testWidgets(
      '流式 EPUB 頁首/頁尾文字：深色主題下顏色跟隨 Theme.of(context)'
      '（epic-22-reader-theme-integration Issue 2）', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_header_footer_dark',
      const BookReaderPrefs(showHeader: true, showFooter: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_header_footer_dark',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        pageIndex: 9,
        totalPages: 100,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    final headerText = tester.widget<Text>(find.descendant(
      of: find.byKey(const Key('reader_foliate_header_text')),
      matching: find.byType(Text),
    ));
    expect(
      headerText.style?.color,
      buildThemeData(AppTheme.dark).colorScheme.onSurface,
    );

    final footerText = tester.widget<Text>(find.descendant(
      of: find.byKey(const Key('reader_foliate_progress_text')),
      matching: find.byType(Text),
    ));
    expect(
      footerText.style?.color,
      buildThemeData(AppTheme.dark).colorScheme.onSurface,
    );
  });

  testWidgets(
      'EPUB 固定版面：不論主題為何，頁首/頁尾文字色維持既有寫死 Colors.black'
      '（epic-22-reader-theme-integration Issue 2，固定版面內容通常是白底'
      '圖片，若文字色跟著深色主題變淺會看不見）', (tester) async {
    await prefsManager.saveBookPrefs(
      'b_header_footer_fxl',
      const BookReaderPrefs(showHeader: true, showFooter: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(AppTheme.dark),
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_header_footer_fxl',
          prefsManager: prefsManager,
          isFixedLayout: true,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView = tester.widget<FoliateEpubReaderView>(
      find.byType(FoliateEpubReaderView),
    );
    foliateView.onPageRendered();
    foliateView.onLocatorChanged?.call(
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        pageIndex: 9,
        totalPages: 100,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('nav_zone_1')));
    await tester.pump();

    final headerText = tester.widget<Text>(find.descendant(
      of: find.byKey(const Key('reader_foliate_header_text')),
      matching: find.byType(Text),
    ));
    expect(headerText.style?.color, Colors.black);

    final footerText = tester.widget<Text>(find.descendant(
      of: find.byKey(const Key('reader_foliate_progress_text')),
      matching: find.byType(Text),
    ));
    expect(footerText.style?.color, Colors.black);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "epic-22-reader-theme-integration Issue 2"`
Expected: 前兩個測試（`AppTheme.light`／深色主題跟隨）FAIL——目前 `_buildFoliateHeaderText()`／`_buildFoliateProgressText()` 仍寫死 `Colors.black`，實際值 `Colors.black` ≠ 預期的 `buildThemeData(AppTheme.light/dark).colorScheme.onSurface`。第三個測試（固定版面維持黑色）預期本來就 PASS（現況本來就是黑色），這是回歸基準測試。

- [x] **Step 3: 修改 `_buildFoliateHeaderText()`／`_buildFoliateProgressText()`**

在 `app/lib/screens/reader_screen.dart` 找到：

```dart
  Widget _buildFoliateHeaderText() {
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    final chapterTitle =
        currentPath.isEmpty ? widget.bookTitle : currentPath.first.title;
    return Container(
      key: const Key('reader_foliate_header_text'),
      child: Text(
        chapterTitle,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        // 【程式碼審查修正】拿掉黑色半透明底色後（見上方 _buildFoliateHeaderText
        // 文件註解），白色文字疊在書本頁面（通常是淺色/白色背景）上幾乎
        // 看不見；改用與書本內文一致的黑色，讓頁首文字融入版面，而非高對比
        // 疊加控制項的視覺語言。
        style: const TextStyle(color: Colors.black, fontSize: 12),
      ),
    );
  }
```

改為：

```dart
  Widget _buildFoliateHeaderText() {
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    final chapterTitle =
        currentPath.isEmpty ? widget.bookTitle : currentPath.first.title;
    return Container(
      key: const Key('reader_foliate_header_text'),
      child: Text(
        chapterTitle,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        // 【epic-22-reader-theme-integration Issue 2】顯示流式 EPUB 時
        // 跟隨 Theme.of(context)（與書頁內容同一組色值來源，見 Issue 1）；
        // 顯示固定版面時 _themedTextColor 回傳 null，退回既有寫死黑色——
        // 固定版面內容是圖片，背景通常維持白底，文字色跟著深色主題變淺
        // 會看不見（見 spec.md 決策 9）。
        style: TextStyle(color: _themedTextColor ?? Colors.black, fontSize: 12),
      ),
    );
  }
```

接著找到：

```dart
  Widget _buildFoliateProgressText() {
    final info = _epubPositionInfo!;
    final totalPages = info.totalPages!;
    final currentPage = ((info.pageIndex ?? 0) + 1).clamp(1, totalPages);
    return Container(
      key: const Key('reader_foliate_progress_text'),
      child: Text(
        '$currentPage/$totalPages',
        // 【程式碼審查修正】理由同 _buildFoliateHeaderText()：拿掉底色後
        // 改用與書本內文一致的黑色，避免白色文字疊在淺色書頁背景上看不見。
        style: const TextStyle(color: Colors.black, fontSize: 12),
      ),
    );
  }
```

改為：

```dart
  Widget _buildFoliateProgressText() {
    final info = _epubPositionInfo!;
    final totalPages = info.totalPages!;
    final currentPage = ((info.pageIndex ?? 0) + 1).clamp(1, totalPages);
    return Container(
      key: const Key('reader_foliate_progress_text'),
      child: Text(
        '$currentPage/$totalPages',
        // 【epic-22-reader-theme-integration Issue 2】理由同
        // _buildFoliateHeaderText()：跟隨 Theme.of(context)，固定版面時
        // 退回既有寫死黑色。
        style: TextStyle(color: _themedTextColor ?? Colors.black, fontSize: 12),
      ),
    );
  }
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "epic-22-reader-theme-integration Issue 2"`
Expected: PASS，3 個測試全數通過。

- [x] **Step 5: 執行完整 `reader_screen_test.dart` 確認零回歸**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS，全數通過（含 Issue 1 新增的顏色透傳測試、其餘既有測試不受影響）。

- [x] **Step 6: `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 7: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-22): 頁首/頁尾文字色跟隨 Theme.of(context)（流式 EPUB），固定版面維持黑色"
```

---

### Task 2: 全專案回歸測試

**Files:** 無新增/修改檔案，純驗證。

**Interfaces:** 無新增介面，驗證 Task 1 整合後的端到端行為。

- [x] **Step 1: 執行全專案 `flutter test`**

Run: `flutter test`
Expected: 全數通過，無任何回歸。

- [x] **Step 2: 執行全專案 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3（建議，非必要）：真機/模擬器快速視覺確認**

與 Issue 1 不同，本 Issue 改動的是純 Flutter widget 屬性（`TextStyle.color`），`flutter test` 已完整涵蓋所有可觀察行為（Step 1 的 widget test 直接斷言實際渲染的 `TextStyle.color` 值），不像 Issue 1 的 WebView CSS 注入邏輯有自動化測試觸及不到的黑盒風險。因此本步驟是建議而非強制：

1. 安裝 debug APK 至真機或模擬器。
2. 切換為深色主題，開啟一本流式 EPUB，觸發沉浸模式收起後確認頁首/頁尾文字清晰可讀（淺色文字疊深色頁面）。
3. 若手邊有固定版面（FXL）EPUB，開啟後確認頁首/頁尾文字仍是黑色（不受深色主題影響）。

- [ ] **Step 4: Commit（若真機驗證過程中有任何修正）**

若 Step 3 發現任何問題並修正程式碼，比照 Task 1 的模式（先確認測試涵蓋、修正、重新測試、commit）。若無需修正，本 Step 略過（Task 1 的 commit 已是本 Issue 最終狀態）。
