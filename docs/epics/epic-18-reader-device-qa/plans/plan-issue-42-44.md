# Issue 42-44 實作計劃：書架橫屏對齊、頁首/頁尾精簡、導航熱區圖示配色一致（`/diagnose` 第六輪）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修正 `/diagnose` 第六輪查明的 3 個真機回報根因（書架橫屏下分類拼貼格與書籍格同列時封面高度不一致、EPUB 頁首/頁尾文字視覺與版面精簡、導航熱區「簡單」模板卡片圖示配色不一致），皆屬 `epic-18-reader-device-qa`。

**Architecture:** Task 1（Issue 42）改動 `app/lib/screens/library_screen.dart` 的 `_GroupGridTile`／`_BookGridTile`；Task 2（Issue 43）改動 `app/lib/screens/reader_screen.dart` 的 `_buildFoliateHeaderText()`／`_buildFoliateProgressText()`；Task 3（Issue 44）改動 `app/lib/screens/nav_zone_settings_screen.dart` 的 `_buildTemplateCard()`。三者互相獨立、無依賴關係，可任意順序或平行進行。

**Tech Stack:** Flutter/Dart widget test（`flutter_test`），本計劃三個 Task 皆有明確可執行的測試 seam，全程可用 `flutter test` 驗證，不需要真機或 `integration_test`。

## Global Constraints

- 提交前 `flutter analyze` 必須乾淨（"No issues found!"）。
- 每個 Task 完成後跑一次全專案 `flutter test`（不只跑該 Task 新增/修改的測試檔），確認零回歸。
- 所有程式碼註解與 commit message 使用正體中文（專有名詞/API 名稱維持英文原文）。
- 每個 Task 各自一個 commit，commit message 開頭比照既有慣例 `fix(epic-18): Issue <N> — <一句話摘要>`。
- 三個 Task 完成後才發起程式碼審查與 PR，比照本 Epic 既有的「一輪真機回報 = 一個分支 = 多個 commit = 一個 PR」慣例（工作目錄命名 `.worktrees/epic-18-issue-42-44`，分支名稱由執行者依既有慣例自訂，例如 `fix/epic-18-issue-42-44-shelf-header-navzone`）。

---

### Task 1: Issue 42 — 書架橫屏下分類拼貼格與書籍格同列時封面高度不對齊

**背景（已用真實 widget test 量測確認根因，非臆測）：** 使用者附上真機橫屏截圖回報書架封面「未對齊」（`tmp/images/橫屏書架未對齊.jpg`，紅線標示錯位邊界）。原始附圖為直式螢幕、且是已於 PR #116（Issue 37）修正的舊問題截圖，經使用者更正提供正確的橫屏截圖後，重新分析確認：這是一個全新的、與 Issue 37 無關的問題。

橫屏下 `crossAxisCount` 從 3 變為 4（`library_screen.dart:827`），若圖書庫剛好有 3 個分類，直式（3 欄）時 3 個分類拼貼格恰好填滿第一列、書籍格從第二列開始，兩者不會同列；但橫屏（4 欄）時 3 個分類拼貼格只填滿前 3 欄，第 4 欄由第一本書籍格填入——**分類拼貼格與書籍格因此混排在同一列**。

`SliverGridDelegateWithFixedCrossAxisCount` 保證同一列所有 cell 的**外層總高度**相同，但 `_GroupGridTile`（`library_screen.dart:866-926`）的文字說明區只有 1 行（分類名稱＋本數），`_BookGridTile`（`library_screen.dart:1024-1098`）的文字說明區有 2 行（書名＋進度百分比）。兩者的封面區塊皆用 `Expanded` 吃掉「外層總高度－文字說明區高度」的剩餘空間——文字說明區行數不同，導致封面區塊的實際高度也不同，使封面底部邊界與文字說明區起始位置在同一列的不同 cell 之間出現落差，這正是使用者截圖裡紅線標示的「未對齊」。

已用真實 widget test 精確量測（3 個分類、每分類 3 本書 + 1 本個別書籍，橫屏 1600×1200，`_testBook` fixture）：分類拼貼格的封面區塊底部（緊接文字標籤起始 Y 座標）與書籍格封面區塊底部相差 **14 像素**（書籍格因為多一行進度文字，封面矮 14px）——與截圖裡的視覺錯位方向完全吻合。

**修法：** 讓兩種 cell 的「文字說明區」共用同一個固定高度（取書籍格 2 行文字所需的自然高度為準，因為它是兩者中較高的需求），分類拼貼格的 1 行文字說明維持原樣、但外層改包一個固定高度的容器，讓封面 `Expanded` 在兩種 cell 之間吃到相同的剩餘高度。分類拼貼格會因此犧牲一點點封面高度（約 14px，換取跨 cell 對齊），這是本修法必然的取捨，且比留白/錯位更符合使用者實際訴求。

**Files:**
- Modify: `app/lib/screens/library_screen.dart`（`_GroupGridTile`、`_BookGridTile`）
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：無新增依賴。
- Produces：新增檔案層級常數 `_kGridTileFooterHeight`（`double`），供 `_GroupGridTile`／`_BookGridTile` 共用；兩者的文字說明區改包在 `SizedBox(height: _kGridTileFooterHeight, ...)` 內。

- [x] **Step 1: 寫失敗測試——量測分類拼貼格與書籍格同列時的文字標籤起始 Y 座標，斷言相同**

在 `app/test/screens/library_screen_test.dart` 新增測試（放在既有「填滿可用高度」測試附近即可）：

```dart
  testWidgets(
      '橫屏（4 欄）下分類拼貼格與書籍格同列時，兩者文字標籤起始 Y 座標對齊'
      '（epic-18-reader-device-qa Issue 42，真機使用回報：書架橫屏下封面'
      '未對齊——根因是 _BookGridTile 有 2 行文字說明（書名＋進度），'
      '_GroupGridTile 只有 1 行〔分類名稱＋本數〕，兩者封面 Expanded 吃到的'
      '剩餘高度因此不同，導致同列的封面底部邊界錯開）', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final books = [
      for (var i = 0; i < 3; i++)
        _testBook(id: 'g$i', title: '分類書$i', groupName: '奇幻'),
      _testBook(id: 'b0', title: '第一本個別書'),
    ];
    final repository = FakeLibraryRepository(initialBooks: books);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final groupTileFinder = find.byKey(const Key('group_tile_奇幻'));
    final bookTileFinder = find.byKey(const Key('book_item_b0'));
    expect(groupTileFinder, findsOneWidget);
    expect(bookTileFinder, findsOneWidget);

    // 前提：兩者確實同列（外層總高度相同，這是 GridView 的既有保證，
    // 這裡順便驗證前提沒有跑掉）。
    expect(
      tester.getSize(groupTileFinder).height,
      tester.getSize(bookTileFinder).height,
    );

    final groupLabelTop = tester
        .getTopLeft(find.descendant(
          of: groupTileFinder,
          matching: find.text('奇幻 (3)'),
        ))
        .dy;
    final bookTitleTop = tester
        .getTopLeft(find.descendant(
          of: bookTileFinder,
          matching: find.text('第一本個別書'),
        ))
        .dy;

    expect(bookTitleTop, groupLabelTop,
        reason: '同列的分類拼貼格與書籍格，文字標籤起始高度應對齊，'
            '封面區塊底部邊界才不會錯開');
  });
```

（`library_screen_test.dart` 檔案內既有的共用 `prefsManager`／`_testBook` 輔助函式已停用 `openLastBookOnLaunch`，直接沿用即可，不需要額外處理。）

- [x] **Step 2: 執行測試確認失敗**

```bash
cd app
flutter test test/screens/library_screen_test.dart --plain-name "文字標籤起始 Y 座標對齊"
```

預期失敗：`bookTitleTop` 與 `groupLabelTop` 相差約 14（實際數值以執行結果為準，測試環境的字型 metrics 可能與正式環境略有差異，但方向與量級應一致）。

- [x] **Step 3: 修正 `_GroupGridTile`／`_BookGridTile`，讓文字說明區共用固定高度**

在 `library_screen.dart` 頂層（`class _GroupTile` 之前或任一兩個 class 之前皆可，建議放在 `_GroupGridTile` 上方）新增常數：

```dart
/// 分類拼貼格（_GroupGridTile）與書籍格（_BookGridTile）共用的文字說明區
/// 固定高度（epic-18-reader-device-qa Issue 42）：兩者原本文字說明區行數
/// 不同（前者 1 行、後者 2 行），導致封面 Expanded 吃到的剩餘高度不同，
/// 橫屏下兩者同列時封面底部邊界因此錯開（真機回報，已用 widget test 精確
/// 量測相差 14px）。固定高度取書籍格 2 行文字（書名＋進度）所需的自然
/// 高度為準，分類拼貼格的 1 行文字說明包進同樣高度的容器（會留一點點
/// 底部空白，換取跨 cell 對齊），是本修法必然的取捨。
const _kGridTileFooterHeight = 34.0;
```

（34.0 為初始估算值，比照書名 12px＋進度 10px 兩行文字的自然行高＋既有間距抓概略值；**實作時務必用 Step 1 的測試實際量測後校準這個數字**，不要照抄本文件的數字就當作最終值——不同字型/系統設定下的實際行高可能略有差異，以測試斷言通過為準。）

`_GroupGridTile.build()` 內，找到：

```dart
          const SizedBox(height: 4),
          Text(
            '${tile.name} (${tile.totalCount})',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
```

改為：

```dart
          const SizedBox(height: 4),
          SizedBox(
            height: _kGridTileFooterHeight,
            child: Text(
              '${tile.name} (${tile.totalCount})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ),
```

`_BookGridTile.build()` 內，找到：

```dart
          const SizedBox(height: 4),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            _progressText(book),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
```

改為：

```dart
          const SizedBox(height: 4),
          SizedBox(
            height: _kGridTileFooterHeight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  _progressText(book),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
```

- [x] **Step 4: 執行測試確認通過，若未通過則校準 `_kGridTileFooterHeight`**

```bash
flutter test test/screens/library_screen_test.dart --plain-name "文字標籤起始 Y 座標對齊"
```

若仍失敗，依失敗訊息顯示的實際差值調整 `_kGridTileFooterHeight`（增減差值後重跑），直到兩者的 `dy` 完全相等。

- [x] **Step 5: 跑整個檔案與 `flutter analyze` 確認無回歸**

```bash
flutter test test/screens/library_screen_test.dart
flutter analyze
```

特別注意：`_BookGridTile` 原本兩個 `Text` 是 `Column` 的直接子項（`crossAxisAlignment: CrossAxisAlignment.stretch`），這裡包進內層 `Column(mainAxisSize: MainAxisSize.min)` 後，內層 `Column` 預設 `crossAxisAlignment.center`，兩個 `Text` 皆已設定 `textAlign: TextAlign.center` 且外層又是 `stretch`，視覺上應無變化；若跑完既有測試發現任何依賴 `_BookGridTile` 內部 widget 結構（例如 `find.descendant` 尋找特定巢狀層級）的既有測試失敗，逐一檢視並視情況調整 finder（預期不會，因為既有測試多用 `find.text(...)`／`find.byKey(...)`，不特別依賴巢狀層級）。

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "fix(epic-18): Issue 42 — 書架橫屏下分類拼貼格與書籍格同列時封面高度不對齊"
```

---

### Task 2: Issue 43 — EPUB 頁首/頁尾文字移除按鈕底色、縮小至只佔文字空間、字級改為 12

**背景：** 使用者回報 3 項 EPUB 閱讀器頁首（章節名稱）／頁尾（頁碼進度）純顯示文字的相關調整：(1) 目前顯示為「按鈕」樣式（黑色半透明圓角背景），但只需要純文字、不需要按鈕底色；(2) 因為目前用按鈕樣式（含內距），比純文字多佔用了一些版面空間，希望縮小到只佔文字本身需要的空間；(3) 文字字級改為 12（目前為 16，epic-18 Issue 32 所設）。三項合併起來是同一次改動：拿掉 `_buildFoliateHeaderText()`／`_buildFoliateProgressText()`（`reader_screen.dart:1809-1854`）目前的 `Container(padding: ..., decoration: BoxDecoration(color: Colors.black54, borderRadius: ...))` 包裝，只保留純文字本身，並把字級從 16 改為 12。

**設計待確認（實作前建議跟人類確認一次，非阻塞性問題，若未回覆則按預設值執行）：** 目前文字顏色是白色（`Colors.white`），搭配黑色半透明背景維持可讀性；拿掉背景後，白色文字疊在淺色書頁背景上可能難以辨識。本計劃預設**維持文字顏色不變**（使用者只要求拿掉「底色」，沒有要求改文字顏色），若真機測試後發現可讀性有問題，需另外討論（例如加文字陰影，而非重新加回底色）——這不在本次計劃範圍內，作為已知風險記錄。

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`（`_buildFoliateHeaderText()`、`_buildFoliateProgressText()`）
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：無。
- Produces：兩個方法回傳的 widget 樹改為「`Container(key: ...)` 直接包一個 `Text`」（不再有 `padding`/`decoration`），`Key('reader_foliate_header_text')`／`Key('reader_foliate_progress_text')` 維持掛在最外層 `Container` 上（**不要**把 Key 直接移到 `Text` 上——既有大量測試用 `find.descendant(of: find.byKey(...), matching: find.byType(Text))` 尋找內部的 `Text`，Key 若直接掛在 `Text` 上，`descendant` 搜尋不含自身，會導致這些既有測試全部找不到而失敗）。

- [x] **Step 1: 寫失敗測試——斷言字級為 12、且不再有背景裝飾／內距**

在 `app/test/screens/reader_screen_test.dart` 新增測試（找一個既有建構好 `ReaderScreen`、`_chromeVisible` 已觸發沉浸模式顯示頁首頁尾的既有測試附近，比照其 setup 方式）：

```dart
  testWidgets(
      '流式 EPUB 頁首/頁尾文字：字級為 12、不含按鈕底色與內距，只佔文字本身空間'
      '（epic-18-reader-device-qa Issue 43，真機使用回報）', (tester) async {
    // ……比照既有測試（搜尋 `headerText.style?.fontSize, 16` 所在測試）的
    // pumpWidget／觸發沉浸模式／確認頁首頁尾已顯示的既有 setup 步驟，
    // 沿用相同流程，此處省略重複列出。

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
  });
```

- [x] **Step 2: 執行測試確認失敗**

```bash
flutter test test/screens/reader_screen_test.dart --plain-name "不含按鈕底色與內距"
```

預期失敗：`headerContainer.padding`／`decoration` 皆非 null（目前有 `EdgeInsets.symmetric`／`BoxDecoration`），字級斷言也會失敗（目前是 16）。

- [x] **Step 3: 修正 `_buildFoliateHeaderText()`／`_buildFoliateProgressText()`**

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
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
```

```dart
  Widget _buildFoliateProgressText() {
    final info = _epubPositionInfo!;
    final totalPages = info.totalPages!;
    final currentPage = ((info.pageIndex ?? 0) + 1).clamp(1, totalPages);
    return Container(
      key: const Key('reader_foliate_progress_text'),
      child: Text(
        '$currentPage/$totalPages',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
```

- [x] **Step 4: 更新既有的兩處 `fontSize, 16` 斷言為 `12`**

```bash
grep -n "fontSize, 16" test/screens/reader_screen_test.dart
```

目前已知 2 處（`headerText.style?.fontSize, 16` 與 `footerText.style?.fontSize, 16`），改為 `12`。執行這個 grep 確認沒有遺漏第 3 處——若有其他既有測試也斷言了頁首/頁尾字級為 16，一併更新。

- [x] **Step 5: 執行測試確認通過**

```bash
flutter test test/screens/reader_screen_test.dart --plain-name "不含按鈕底色與內距"
```

- [x] **Step 6: 跑整個檔案與 `flutter analyze` 確認無回歸**

```bash
flutter test test/screens/reader_screen_test.dart
flutter analyze
```

- [x] **Step 7: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "fix(epic-18): Issue 43 — 頁首/頁尾文字移除按鈕底色、縮小至只佔文字空間、字級改為 12"
```

---

### Task 3: Issue 44 — 導航熱區「簡單」模板卡片圖示配色不一致（「左翻頁」與「右翻頁」）

**背景：** `nav_zone_settings_screen.dart` 的 `_buildTemplateCard()`（`leftFlip`／`rightFlip` 兩張卡片共用，約第 197-249 行）目前用**欄位位置**決定色塊顏色——不論該欄實際顯示什麼圖示，左欄固定 `Colors.blue.shade100`、中欄固定 `Colors.green.shade100`、右欄固定 `Colors.red.shade100`。

`leftFlip`：`leftIcon: chevron_right`（左欄，藍色）／`rightIcon: chevron_left`（右欄，紅色）——`<` 恰好落在紅色欄、`>` 恰好落在藍色欄。
`rightFlip`：`leftIcon: chevron_left`（左欄，藍色）／`rightIcon: chevron_right`（右欄，紅色）——**`<` 卻落在藍色欄、`>` 卻落在紅色欄，與 leftFlip 剛好相反**。

這正是使用者回報「簡單第二個（`rightFlip`），圖示顏色應與第一個（`leftFlip`）一致」的根因——兩張卡片對同一個動作（`<`／`>`）用了不同顏色，因為顏色是綁在「欄位」而非「動作」上。這與 Issue 36（`_buildOneHandTemplateCard`，已用「動作」決定顏色：`Icons.menu` 綠、`Icons.chevron_left` 紅、`Icons.chevron_right` 藍）的既有慣例不一致，本次一併對齊。

**修法：** `_buildTemplateCard()` 改用「該欄顯示的圖示」決定顏色，而非欄位位置——新增一個依圖示對應顏色的頂層純函式，`leftIcon`／`middleIcon`／`rightIcon` 三個色塊各自呼叫這個函式決定自己的顏色，讓 `chevron_left` 永遠紅色、`chevron_right` 永遠藍色、`menu` 永遠綠色，`leftFlip`／`rightFlip`／`oneHand` 三張卡片的配色語意完全一致。

**Files:**
- Modify: `app/lib/screens/nav_zone_settings_screen.dart`（`_buildTemplateCard()`）
- Test: `app/test/screens/nav_zone_settings_screen_test.dart`

**Interfaces:**
- Consumes：無新增依賴。
- Produces：新增頂層純函式 `Color navZoneTemplateIconColor(IconData icon)`（`Icons.chevron_left` → `Colors.red.shade100`；`Icons.chevron_right` → `Colors.blue.shade100`；`Icons.menu` → `Colors.green.shade100`；其餘圖示回退 `Colors.grey.shade100`，理論上不會用到，純防禦性预設值）——抽成頂層純函式（不是 `_NavZoneSettingsScreenState` 的私有方法）方便未來若有其他呼叫端需要同樣的配色語意時重用，也方便獨立測試（比照本檔案既有 `resolveCustomFontUri`／`handleFoliateConsoleMessage` 抽出頂層純函式獨立測試的既有慣例）。

- [x] **Step 1: 寫失敗測試——斷言 `navZoneTemplateIconColor()` 的配色語意**

在 `app/test/screens/nav_zone_settings_screen_test.dart` 新增測試（獨立 `group`，不需要 pump widget，純函式測試）：

```dart
  group('navZoneTemplateIconColor（epic-18-reader-device-qa Issue 44）', () {
    test('chevron_left 恆為紅色', () {
      expect(navZoneTemplateIconColor(Icons.chevron_left), Colors.red.shade100);
    });

    test('chevron_right 恆為藍色', () {
      expect(navZoneTemplateIconColor(Icons.chevron_right), Colors.blue.shade100);
    });

    test('menu 恆為綠色', () {
      expect(navZoneTemplateIconColor(Icons.menu), Colors.green.shade100);
    });
  });
```

再新增一個 widget 層測試，驗證 `leftFlip`／`rightFlip` 兩張卡片對同一個圖示使用相同顏色（這才是真正鎖住使用者回報症狀的回歸測試——純函式測試只保證配色表本身正確，不保證兩張卡片真的都呼叫了它）：

```dart
  testWidgets(
      '「左翻頁」與「右翻頁」卡片對同一個圖示（chevron_left／chevron_right）'
      '使用相同顏色（epic-18-reader-device-qa Issue 44，真機使用回報：'
      '兩張卡片原本用欄位位置決定顏色，導致同一個 < 圖示在兩張卡片上顏色'
      '不同）', (tester) async {
    final fakeManager = FakeReaderPrefsManager();
    await tester.pumpWidget(MaterialApp(
      home: NavZoneSettingsScreen(prefsManager: fakeManager),
    ));
    await tester.pumpAndSettle();

    Color colorOfIcon(Key cardKey, IconData icon) {
      final container = tester.widget<Container>(find.descendant(
        of: find.ancestor(
          of: find.descendant(
            of: find.byKey(cardKey),
            matching: find.byWidgetPredicate((w) => w is Icon && w.icon == icon),
          ),
          matching: find.byType(Container),
        ).first,
        matching: find.byType(Container),
      ).first);
      return (container.color) as Color;
    }

    final leftFlipChevronLeftColor =
        colorOfIcon(const Key('nav_zone_mode_leftFlip'), Icons.chevron_left);
    final rightFlipChevronLeftColor =
        colorOfIcon(const Key('nav_zone_mode_rightFlip'), Icons.chevron_left);
    expect(leftFlipChevronLeftColor, rightFlipChevronLeftColor);

    final leftFlipChevronRightColor =
        colorOfIcon(const Key('nav_zone_mode_leftFlip'), Icons.chevron_right);
    final rightFlipChevronRightColor =
        colorOfIcon(const Key('nav_zone_mode_rightFlip'), Icons.chevron_right);
    expect(leftFlipChevronRightColor, rightFlipChevronRightColor);
  });
```

（上面 `colorOfIcon` 這段 finder 巢狀寫法較複雜，若實作時發現不好用，可以改用更簡單的寫法：直接用 `find.descendant(of: find.byKey(cardKey), matching: find.byWidgetPredicate((w) => w is Container && w.color != null))` 取得該卡片內全部 3 個色塊 `Container`，再逐一比對其 `child`〔`Icon`〕是否為目標圖示，取出對應的 `.color`——效果相同，寫法依實作者判斷選用較清楚的一種即可，這不是本計劃的關鍵決策點。）

- [x] **Step 2: 執行測試確認失敗**

```bash
flutter test test/screens/nav_zone_settings_screen_test.dart --plain-name "navZoneTemplateIconColor"
flutter test test/screens/nav_zone_settings_screen_test.dart --plain-name "使用相同顏色"
```

預期：`navZoneTemplateIconColor` 測試因函式不存在而編譯失敗；「使用相同顏色」測試因目前 `rightFlip` 卡片的 `chevron_left`（藍）與 `leftFlip` 的 `chevron_left`（紅）不同而斷言失敗。

- [x] **Step 3: 新增 `navZoneTemplateIconColor()` 頂層函式，修改 `_buildTemplateCard()` 改用它決定顏色**

在 `nav_zone_settings_screen.dart` 檔案頂層（class 定義之前或之後皆可，建議放在 imports 之後、`NavZoneSettingsScreen` class 之前）新增：

```dart
/// 「簡單」模板卡片（`leftFlip`／`rightFlip`／`oneHand`）色塊配色表
/// （epic-18-reader-device-qa Issue 44，真機使用回報：`leftFlip`／
/// `rightFlip` 原本用「欄位位置」決定色塊顏色，導致同一個 `chevron_left`
/// 圖示在兩張卡片上顏色不同〔一個紅一個藍〕。改用「圖示本身」決定顏色，
/// 讓三張卡片的配色語意一致：綠＝選單、紅＝上一頁、藍＝下一頁，比照
/// `_buildOneHandTemplateCard()` 既有的配色慣例。抽成頂層純函式方便獨立
/// 測試與未來重用。
Color navZoneTemplateIconColor(IconData icon) {
  if (icon == Icons.chevron_left) return Colors.red.shade100;
  if (icon == Icons.chevron_right) return Colors.blue.shade100;
  if (icon == Icons.menu) return Colors.green.shade100;
  return Colors.grey.shade100;
}
```

`_buildTemplateCard()` 內，找到：

```dart
        child: Row(
          children: [
            Expanded(
              child: Container(
                color: Colors.blue.shade100,
                alignment: Alignment.center,
                child: Icon(leftIcon, size: 16),
              ),
            ),
            Expanded(
              child: Container(
                color: Colors.green.shade100,
                alignment: Alignment.center,
                child: middleIcon == null ? null : Icon(middleIcon, size: 16),
              ),
            ),
            Expanded(
              child: Container(
                color: Colors.red.shade100,
                alignment: Alignment.center,
                child: Icon(rightIcon, size: 16),
              ),
            ),
          ],
        ),
```

改為：

```dart
        child: Row(
          children: [
            Expanded(
              child: Container(
                color: navZoneTemplateIconColor(leftIcon),
                alignment: Alignment.center,
                child: Icon(leftIcon, size: 16),
              ),
            ),
            Expanded(
              child: Container(
                color: middleIcon == null
                    ? Colors.grey.shade100
                    : navZoneTemplateIconColor(middleIcon),
                alignment: Alignment.center,
                child: middleIcon == null ? null : Icon(middleIcon, size: 16),
              ),
            ),
            Expanded(
              child: Container(
                color: navZoneTemplateIconColor(rightIcon),
                alignment: Alignment.center,
                child: Icon(rightIcon, size: 16),
              ),
            ),
          ],
        ),
```

（`middleIcon == null` 時維持原本的中性灰色 `Colors.grey.shade100`——目前 `_buildTemplateCard()` 唯一會傳 `middleIcon: null` 的呼叫端已在 Issue 36 移除〔`oneHand` 改用獨立的 `_buildOneHandTemplateCard()`〕，`leftFlip`／`rightFlip` 兩個現存呼叫端的 `middleIcon` 恆為 `Icons.menu`，這個 null 分支理論上不會被觸發，純粹防禦性保留既有行為、不删除既有邏輯分支。）

- [x] **Step 4: 執行測試確認通過**

```bash
flutter test test/screens/nav_zone_settings_screen_test.dart --plain-name "navZoneTemplateIconColor"
flutter test test/screens/nav_zone_settings_screen_test.dart --plain-name "使用相同顏色"
```

- [x] **Step 5: 跑整個檔案與 `flutter analyze` 確認無回歸**

```bash
flutter test test/screens/nav_zone_settings_screen_test.dart
flutter analyze
```

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/nav_zone_settings_screen.dart app/test/screens/nav_zone_settings_screen_test.dart
git commit -m "fix(epic-18): Issue 44 — 導航熱區「左翻頁」／「右翻頁」卡片圖示配色不一致，改用圖示本身決定顏色"
```

---

## 執行順序與注意事項

- 三個 Task 完全獨立（分別改動 `library_screen.dart`／`reader_screen.dart`／`nav_zone_settings_screen.dart`，互不重疊），可任意順序或平行進行。
- Task 1（Issue 42）的 `_kGridTileFooterHeight` 數值需要實作時依 Step 1 測試的實際量測結果校準，計劃文件內的 `34.0` 只是估算起點，不是最終答案。
- Task 2（Issue 43）的文字顏色維持白色不變（見該 Task「設計待確認」段落）——若人類在審查此計劃時想調整這個預設，請在實作前先反映，不要等實作完才發現方向不對。
- 全部 3 個 Task 完成、且全專案 `flutter test`／`flutter analyze` 皆通過後，才發起程式碼審查（`/superpowers:requesting-code-review`）與 PR。
