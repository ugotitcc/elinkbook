# Epic 27 Issue 3 — 開 App／開書時畫面整個黑色一段時間 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `ReaderScreen._buildBody()` 的 Stack 中、原生渲染畫面（`InAppWebView`／`pdfrx` 繪圖表面）**之上**疊一層不透明的主題背景色（僅於 `_state == _RenderState.loading` 時顯示），蓋住原生視圖在真正收到第一次繪製結果前預設顯示黑色的空窗期，讓使用者在開書載入中看到的是與主題一致的過場色而非全黑畫面；渲染完成後遮罩立即移除，不影響閱讀與觸控手勢。

**Architecture:** `_buildBody()`（`app/lib/screens/reader_screen.dart:2034` 起）回傳的 `Stack` 目前第一個 child 是有條件掛載的 `_buildNativeView(format, isLandscape)`，中間只疊了一顆置中 `CircularProgressIndicator`（`_state == _RenderState.loading` 時），兩者之間沒有任何不透明底色。**Flutter `Stack` 依 children 清單順序繪製，後面的 child 疊在前面的 child 上方**——因此本計畫的遮罩必須放在 `_buildNativeView` **之後**（即中層，位於原生視圖與 `CircularProgressIndicator` 之間）才能真正蓋住原生視圖輸出的黑色緩衝區；若放在 `_buildNativeView` 之前只會被原生視圖蓋住，等於沒有效果（初版計畫審查發現的 Critical 錯誤，見 `reviews/review-plan-issue-3.md`）。本計畫插入一個 `if (_state == _RenderState.loading) Positioned.fill(child: ColoredBox(...))`，顏色取自 `Theme.of(context).scaffoldBackgroundColor`（適用淺色／深色／羊皮紙／E-Ink 高對比四種主題，皆有明確定義的 `scaffoldBackgroundColor`，見 `app/lib/theme/app_theme_data.dart`）。此遮罩**僅在 `_state == _RenderState.loading` 時存在**——一旦 `onPageRendered`/`onLayoutResolved` 等回呼觸發 `_state` 轉為 `rendered`，遮罩隨之從 widget tree 移除，露出已渲染完成的書籍內容，不殘留、不阻擋任何觸控手勢（見下方「設計決策」）。

**Tech Stack:** Flutter/Dart，無新增依賴。

**Spec:** `docs/epics/epic-27-reader-device-compat/issues.md`「Issue 3」、`docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md`「Issue 3」（根因診斷）。

## 設計決策（回應 `issues.md` Issue 3 留給實作者定案的 2 個開放問題）

1. **遮罩層只在 `_state == loading` 時顯示，或恆常墊底？** 採用**只在 `_state == _RenderState.loading` 時顯示**（`if (_state == _RenderState.loading) Positioned.fill(...)`），**推翻初版計畫原本「恆常墊底」的決定**。理由：初版計畫誤將遮罩放在 `_buildNativeView` **之下**，在那個（錯誤的）位置「恆常存在」確實無害，因為反正會被上層原生視圖蓋住；但依 Critical 修正，遮罩必須移到 `_buildNativeView` **之上**才能真正發揮遮蔽黑幀的作用——一旦遮罩位於原生視圖之上，若還維持「恆常存在」，會變成**永久蓋住已渲染完成的書籍內容**，讀者將永遠看到一片主題色空白、完全看不到書籍，這是比原始黑屏症狀更嚴重的回歸。因此遮罩的存在時機必須與「原生視圖尚未產生可信賴的畫面」這個狀態（`_state == _RenderState.loading`）綁定，`_state` 轉為 `rendered` 後立即移除。「原生視圖 resize／重建時可能再次出現黑色空窗期」這個假設情境（例如螢幕旋轉、雙頁模式切換）本次不處理——使用者回報的症狀是「開 App／開書時」的初次載入黑屏，不是「已在閱讀中途」的黑屏，擴大範圍去覆蓋未經回報、也未驗證是否存在的情境，屬於超出需求的推測性修法，不符合本專案「不做超出需求的彈性設計」原則；若日後真的收到對應真機回報，再另立工單處理。
2. **`main()`（`main.dart:29-108`）的同步初始化順序是否調整，以縮短冷啟動黑屏曝光時間？** **不調整**。理由：目前的初始化鏈（`pdfrxFlutterInitialize()` → 開啟 SQLite → 依序建構 `SqliteLibraryRepository`／`BookReaderPrefsRepository`／`BookmarksRepository`／`HighlightsRepository`／`NotesRepository`／`CustomFontsRepository`／`LayoutPresetRepository`／`SyncEngine`／`SyncCheckpointTrigger`）存在真實的相依順序——`BookReaderPrefsRepository` 依專案既有規定必須與 `SqliteLibraryRepository.database` 共用同一個連線（見 `main.dart:43-47` 註解），`SyncEngine` 建構時也直接依賴前面已建構完成的多個 Repository 與 `SyncMetadataRepository`。若貿然把部分初始化搬到 `runApp()` 之後非同步執行，會讓 `LibraryScreen`/`ReaderScreen` 有機會在這些 Repository 尚未就緒前就被建構並嘗試使用，需要額外設計「畫面已顯示但資料層還沒準備好」的過渡態與錯誤處理，複雜度與風險遠高於本 Issue 的效益——本 Issue 的核心視覺症狀（全黑畫面）已被上述遮罩層解決，冷啟動實際所需時間並未改變，只是使用者看到的不再是黑色而是主題色過場，符合本專案「不做超出需求的彈性設計」原則。

## Global Constraints

- 只修改 `app/lib/screens/reader_screen.dart`（新增遮罩層）與 `app/test/screens/reader_screen_test.dart`（新增測試）。
- 不修改 `main.dart` 初始化順序（見上方設計決策 2）。
- 遮罩層一律使用 `Theme.of(context).scaffoldBackgroundColor`，**不**使用既有的 `_themedBackgroundColor` getter——該 getter 對固定版面格式（`_isFixedLayout == true`）回傳 `null`（見 `reader_screen.dart:2590-2591` 註解：「固定版面內容是圖片，無法預期背景色，強制上色沒有意義」），不適合當佔位背景；`scaffoldBackgroundColor` 對所有主題都有明確定義，且用途單純是「蓋住黑色的過場色」，不需要與書頁內容色彩語意綁定。
- 遮罩層必須疊在 `_buildNativeView` **之上**（Stack children 清單中的位置在其之後）且僅於 `_state == _RenderState.loading` 時顯示——不得放在 `_buildNativeView` 之前（會被蓋住、無效果），也不得恆常存在（會在渲染完成後永久蓋住書籍內容），見上方「設計決策」1。
- 每完成 Task 就跑一次 `flutter analyze`，維持乾淨。
- 本 Issue 修復的視覺效果（黑屏是否真的消失）無法在 `flutter test` 純 Dart 環境下驗證——測試只能驗證「Dart 端遮罩層確實存在、z-order 疊在原生視圖之上、顏色正確、且隨 `_state` 轉為 `rendered` 而移除」，不能驗證原生 `InAppWebView`/`pdfrx` 表面本身的繪製時序，真機視覺驗證需留待使用者於 Mobiscribe WARE confirm，比照 Issue 1 先例。

---

### Task 1：`_buildBody()` 新增不透明遮罩層（疊於原生視圖之上，僅 loading 時顯示）

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:2050-2060`（`_buildBody()` 內的 `LayoutBuilder`/`Stack`）
- Test: `app/test/screens/reader_screen_test.dart`（於既有「開書逾時計時器」測試之後，第 5198 行 `});` 之後插入）

**Interfaces:**
- Consumes: 既有 `_buildBody()` 私有方法、`Theme.of(context).scaffoldBackgroundColor`（`BuildContext` 來自 `LayoutBuilder` 的 `builder` 參數）。
- Produces: 新增 `Key('reader_render_placeholder_background')`（遮罩 `ColoredBox`）與 `Key('reader_body_stack')`（`_buildBody()` 回傳的 `Stack` 本身，供測試讀取 `.children` 清單以斷言 z-order），皆為測試用 Key；不新增任何對外建構參數或 public API。

- [x] **Step 1：寫失敗測試——3 則新測試**

編輯 `app/test/screens/reader_screen_test.dart`，於第 5198 行（「開書逾時計時器：onPageRendered 在逾時前已觸發時，逾時計時器不應覆蓋既有的成功狀態」測試結尾的 `});`）之後、第 5200 行（下一則「流式 EPUB 頁首/頁尾文字」測試）之前，新增以下 3 則測試：

```dart
  testWidgets(
      'EPUB 載入中：原生視圖上方應有不透明主題遮罩，蓋住原生視圖首幀黑屏'
      '（epic-27-reader-device-compat Issue 3）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_black_flash_epub_loading',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 刻意不觸發 onLayoutResolved/onPageRendered，維持 _state == loading。
    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

    final placeholder = tester.widget<ColoredBox>(
      find.byKey(const Key('reader_render_placeholder_background')),
    );
    final expectedColor =
        Theme.of(tester.element(find.byType(ReaderScreen))).scaffoldBackgroundColor;
    expect(placeholder.color, expectedColor);

    // z-order 迴歸防呆（epic-27-reader-device-compat Issue 3 審查 Critical
    // #1）：遮罩必須疊在原生視圖「之上」才有蓋住黑幀的效果，若日後有人誤把
    // 順序寫反，這裡要能直接抓到，而不是只驗證「兩者都存在」。
    final stack = tester.widget<Stack>(find.byKey(const Key('reader_body_stack')));
    final nativeViewIndex =
        stack.children.indexWhere((child) => child is FoliateReaderView);
    final placeholderIndex = stack.children.indexWhere((child) =>
        child is Positioned &&
        child.child is ColoredBox &&
        (child.child as ColoredBox).key ==
            const Key('reader_render_placeholder_background'));
    expect(nativeViewIndex, greaterThanOrEqualTo(0),
        reason: '應能在 Stack 找到原生視圖 FoliateReaderView');
    expect(placeholderIndex, greaterThanOrEqualTo(0),
        reason: '應能在 Stack 找到不透明遮罩');
    expect(placeholderIndex, greaterThan(nativeViewIndex),
        reason: '遮罩必須疊在原生視圖之上（z-order 較高）才能真正蓋住原生視圖的首幀'
            '黑屏——這是初版計畫審查抓到的 Critical 錯誤（reviews/review-plan-issue-3.md），'
            '此斷言防止未來回歸');
  });

  testWidgets(
      'PDF 載入中：原生視圖上方應有不透明主題遮罩，蓋住原生視圖首幀黑屏'
      '（epic-27-reader-device-compat Issue 3）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_black_flash_pdf_loading',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 刻意不呼叫 onPageRendered，維持 _state == loading。
    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);

    final placeholder = tester.widget<ColoredBox>(
      find.byKey(const Key('reader_render_placeholder_background')),
    );
    final expectedColor =
        Theme.of(tester.element(find.byType(ReaderScreen))).scaffoldBackgroundColor;
    expect(placeholder.color, expectedColor);
  });

  testWidgets(
      'PDF 已渲染完成後：不透明遮罩應隨 _state 轉為 rendered 而消失，不殘留阻擋手勢'
      '（epic-27-reader-device-compat Issue 3 設計決策 1：僅在 loading 時顯示，'
      '非恆常存在——恆常存在會在渲染完成後永久蓋住書籍內容，是比原始黑屏更嚴重的回歸）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_black_flash_pdf_rendered',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 渲染完成前：遮罩應存在（與前一則 PDF loading 測試對稱佈置情境）。
    expect(find.byKey(const Key('reader_render_placeholder_background')),
        findsOneWidget);

    tester.widget<PdfReaderView>(find.byType(PdfReaderView)).onPageRendered();
    await tester.pump();

    expect(find.byKey(const Key('reader_loading_indicator')), findsNothing);
    expect(find.byType(PdfReaderView), findsOneWidget,
        reason: '遮罩不應影響既有原生視圖的正常渲染（零回歸）');
    expect(
        find.byKey(const Key('reader_render_placeholder_background')),
        findsNothing,
        reason: '_state 轉為 rendered 後遮罩必須立即移除，否則會永久蓋住已渲染完成的'
            '書籍內容、阻擋底層原生視圖的觸控手勢（審查 Critical #1 連帶修正的'
            '設計決策，見 plan 上方「設計決策」1）');
  });
```

- [x] **Step 2：執行測試確認失敗**

執行：`cd app && flutter test test/screens/reader_screen_test.dart --plain-name "epic-27-reader-device-compat Issue 3"`

（審查 Important #1：`--plain-name` 是子字串比對，第 3 則測試標題結尾是「...設計決策 1：僅在 loading 時顯示...」，不含「蓋住原生視圖首幀黑屏」這個子字串，若沿用該字串會漏掉第 3 則測試；三則測試標題都包含「epic-27-reader-device-compat Issue 3」，改用這個字串可完整匹配。）

預期：前兩則測試因找不到 `Key('reader_render_placeholder_background')`（`find.byKey` 回傳空，`tester.widget<ColoredBox>` 拋出「找不到符合的 widget」例外，且找不到 `Key('reader_body_stack')`）而 FAIL；第 3 則測試因「渲染完成前應存在」這個佈置斷言（`findsOneWidget`）同樣找不到該 Key 而 FAIL。

- [x] **Step 3：`_buildBody()` 新增遮罩層（位於原生視圖之上、`_state == loading` 時顯示）**

編輯 `app/lib/screens/reader_screen.dart`，找到（約第 2050-2066 行，`_buildNativeView` 掛載之後、下一個 FAB Positioned 區塊之前）：

```dart
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final selection = _currentSelection;
        final pdfSelection = _currentPdfSelection;
        return Stack(
          children: [
            if (_resolved != null &&
                (!isFoliateFormat(format) ||
                    (_dispatchedIsFixedLayout != null && _customFontsLoaded)))
              _buildNativeView(format, isLandscape),
            // epic-18-reader-device-qa Issue 7：流式 Foliate 格式的 chrome，結構對稱
```

改為（**Stack 加上 `key`；在 `_buildNativeView` 掛載之後——即 z-order 更高、疊在原生視圖上方——插入僅於 `_state == loading` 時顯示的不透明遮罩，`_buildNativeView` 那個 `if` 區塊本身不變動**）：

```dart
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final selection = _currentSelection;
        final pdfSelection = _currentPdfSelection;
        return Stack(
          key: const Key('reader_body_stack'),
          children: [
            if (_resolved != null &&
                (!isFoliateFormat(format) ||
                    (_dispatchedIsFixedLayout != null && _customFontsLoaded)))
              _buildNativeView(format, isLandscape),
            // epic-27-reader-device-compat Issue 3：原生渲染畫面（InAppWebView／
            // pdfrx 繪圖表面）在真正收到第一次繪製結果前，緩衝區預設顯示黑色
            // （Android 平台已知行為，見 reviews/bugfix-repro.md Issue 3）。這層
            // 不透明遮罩必須疊在 _buildNativeView 之上（Stack 依 children 清單
            // 順序繪製，後面的 child 疊在前面之上）才能真正蓋住原生視圖輸出的
            // 黑色緩衝區，故放在 _buildNativeView 這個 if 區塊之後；僅在
            // _state == loading 時顯示——一旦渲染完成立即移除，避免永久蓋住
            // 已渲染完成的書籍內容或阻擋觸控手勢（見 plans/plan-issue-3.md
            // 「設計決策」1，初版計畫誤放在 _buildNativeView 之下、且恆常顯示，
            // 已於審查發現並修正）。
            if (_state == _RenderState.loading)
              Positioned.fill(
                child: ColoredBox(
                  key: const Key('reader_render_placeholder_background'),
                  color: Theme.of(context).scaffoldBackgroundColor,
                ),
              ),
            // epic-18-reader-device-qa Issue 7：流式 Foliate 格式的 chrome，結構對稱
```

**注意：** 上述插入點刻意選在 FAB Positioned 區塊（`isFoliateFormat(format) && _chromeVisible` 那組返回／TOC／設定按鈕）**之前**，讓遮罩的 z-order 低於 FAB 按鈕——這些浮動按鈕目前的顯示條件不受 `_state` 影響（loading 中也可能顯示，見 `_chromeVisible` 預設值），若遮罩蓋在它們上面會讓 loading 期間這些按鈕被不透明遮罩擋住、無法點擊，屬於非預期的行為變化；蓋在它們下面則維持這些按鈕原本「loading 中也可操作」的既有行為不變。

- [x] **Step 4：執行測試確認通過**

執行：`cd app && flutter test test/screens/reader_screen_test.dart`

預期：全數 PASS（含 Step 1 新增的 3 則測試）。

- [x] **Step 5：執行完整分析與全專案測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test`

預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS，零回歸（本次改動只在 `_buildBody()` 的 Stack 新增一個僅於 `_state == loading` 時掛載的 `ColoredBox`。注意：`ColoredBox` 預設以 `HitTestBehavior.opaque` 吸收其涵蓋範圍內的觸控——這在 loading 期間是預期行為，此時原生視圖本來就不該回應觸控（見 Issue 1 的 loading 狀態防呆）；`_state` 轉為 `rendered` 後遮罩即從 widget tree 移除，不影響任何既有 `find.byType`/`find.byKey` 定位邏輯或渲染完成後的手勢處理）。

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "fix(epic-27): Issue 3——_buildBody() 於原生視圖上方新增 loading 專用遮罩層，蓋住首幀黑屏"
```

---

## 完成後的驗證（對照 `issues.md` Issue 3 驗收標準）

- [x] `flutter analyze`：全專案 "No issues found!"
- [x] `flutter test`：全專案通過，零回歸
- [ ] （建議，非本計畫強制自動化——見 Global Constraints「已知局限」，`flutter test` 無法驗證真實原生視圖的繪製時序）於真機（Mobiscribe WARE）：冷啟動 App、開啟書籍（EPUB 與 PDF 各一次），確認載入過程不再出現全黑畫面，改為與主題一致的過場色；若冷啟動黑屏現象仍明顯，代表主要成因不是「Stack 底色空窗」而是別的因素（例如 Flutter Engine Surface 建立階段），需要另外蒐集 logcat／畫面錄影才能進一步診斷，屬於本計畫已知局限，非本次修復範圍。
