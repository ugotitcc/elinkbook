# Epic 27 Issue 1 — EPUB 載入中點擊左側熱區導致崩潰畫面 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `ReaderScreen` 的熱區動作統一分派入口 `_handleZoneAction` 加入 loading 狀態防呆，讓使用者在書籍仍在載入中（`_state == _RenderState.loading`）時點擊導覽熱區（或觸發音量鍵翻頁）不再呼叫進尚未就緒的 `FoliateEpubReaderView`/`PdfReaderView` 換頁邏輯，避免真機回報的 `window.nextPage is not a function` → `Cannot read property 'next' of undefined` 崩潰畫面。

**Architecture:** `_handleZoneAction`（`app/lib/screens/reader_screen.dart:2383`）是 EPUB／PDF 兩條格式路徑共用、且是 tap 熱區與音量鍵事件（`_handleVolumeKeyCall` → `_handleZoneAction`）**唯一**共用的分派入口——`FoliateEpubReaderView.previousPage`/`nextPage`／`PdfReaderView.previousPage`/`nextPage` 這 4 個 static helper 在生產程式碼中只被 `_handleZoneAction` 呼叫（已用 `grep` 全專案核對，無其他呼叫端）。因此只需在 `previousPage`／`nextPage` 這兩個 `switch case` 開頭各加一行 `if (_state == _RenderState.loading) return;`，即可同時涵蓋 EPUB 與 PDF 兩條路徑，比照現有 `_hasActiveSelection` 的抑制模式（見 `foliate_epub_reader_view.dart:804-806`）；不在 `FoliateEpubReaderView`/`PdfReaderView` 內部另加第二層防禦（見下方「設計決策」）。

**Tech Stack:** Flutter/Dart，無新增依賴。

**Spec:** `docs/epics/epic-27-reader-device-compat/issues.md`「Issue 1」、`docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md`「Issue 1」（根因診斷）。

## 設計決策（回應 `issues.md` Issue 1 留給實作者定案的 3 個開放問題）

1. **防呆邏輯放置位置**：加在 `_handleZoneAction`（本計畫的唯一改動點），**不**在 `FoliateEpubReaderView.previousPage`/`nextPage`／`PdfReaderView.previousPage`/`nextPage` 內部加第二層防禦。理由：這 4 個 static helper 在生產程式碼中的唯一呼叫端就是 `_handleZoneAction`（已核對），而「書籍是否仍在載入中」是 `ReaderScreen`／`_RenderState` 的概念，不屬於 `FoliateEpubReaderView`/`PdfReaderView` 自身職責（它們各自已有自己的「文件/controller 是否就緒」內部防呆，例如 `PdfReaderView._nextPage()` 的 `if (!_controller.isReady) return;`，語意不同、不應混淆）。單一權責、單一防呆點，避免兩處邏輯日後不同步。
2. **PDF 端是否存在相同性質的空窗期**：**已查證，結論是「無」**——`PdfReaderView._jumpToPage`/`_nextPage`/`_previousPage`（`app/lib/reader/pdf_reader_view.dart`）皆在方法一開頭就檢查 `if (!_controller.isReady) return;`，早於任何存取內部狀態之前，pdfrx 的 `PdfViewerController.isReady` 屬性在文件尚未開啟完成時安全回傳 `false`，不會像 EPUB 的 JS 端「`window.previousPage` 賦值早於 `view.renderer` 賦值」那樣有可被崩潰命中的空窗期。**即便如此，本計畫仍在 `_handleZoneAction` 對 PDF／EPUB 兩條路徑套用同一個 loading 防呆**——因為兩者共用同一個 `switch case`、防呆成本是一行程式碼，維持「兩條格式路徑行為對稱、由同一個入口統一把關」比額外寫「只保護 EPUB」的特殊邏輯更簡單、更不容易日後遺漏。
3. **是否調整文案／新增其他 UI**：不需要，本 Issue 純粹是「載入中忽略點擊」，不改變任何既有錯誤文案或新增使用者可見的提示（沉默忽略即符合驗收標準）。

## Global Constraints

- 只修改 `_handleZoneAction`（`app/lib/screens/reader_screen.dart:2383-2424`）本體與其上方文件註解，不修改 `FoliateEpubReaderView`/`PdfReaderView` 任何程式碼。
- 防呆只加在 `ZoneAction.previousPage`／`ZoneAction.nextPage` 兩個分支，**不**加在 `ZoneAction.menu`（沉浸模式切換）——`menu` 只是切換 Dart 端 `_chromeVisible` 布林值，不呼叫任何 JS/native API，無崩潰風險；且既有測試（`reader_screen_test.dart` 約 2944 行「點擊選單熱區觸發沉浸模式切換」）在 `_state` 仍是 `loading` 的情況下呼叫 `menu` 動作、斷言沉浸模式確實切換——若對 `menu` 也加防呆會直接打壞這則既有測試（已實測驗證此風險，見下方 Task 1 Step 1 附註）。
- **重要地雷（已透過暫時性程式碼＋`flutter test`實測抓出，不是臆測）**：`app/test/screens/reader_screen_test.dart` 既有測試「PDF 換頁時應清除既有選取狀態，AnnotationToolbar 隨之消失（Epic 24 Issue 10）」（約 5807 行）目前的 `pump(); runAsync(() => Future.delayed(Duration.zero)); pump();` 等待寫法**不足以**讓 `sample_multi_page.pdf` 這份 fixture 透過 pdfrx 真正完成非同步開檔，`_state` 在該測試呼叫 `ReaderScreen.triggerZoneAction(key, ZoneAction.nextPage)` 的當下實測仍是 `loading`（該測試至今能通過純粹是因為目前完全沒有 loading 防呆）。本計畫加入防呆後，**這則既有測試會直接失敗**（已用暫時性 patch 實測重現），必須在同一個 Task 內修正——修法是在該測試內明確呼叫 `pdfView.onPageRendered()` 讓 `_state` 轉為 `rendered`（測試原本要驗證的是「已載入完成後換頁應清除選取」，不是本 Issue 要防呆的「載入中換頁」情境，改法忠於測試原意）。
- `flutter test`（本次唯一觸及的檔案）前後皆須執行過，確認新增測試通過、既有測試零回歸（含上述已知會被打中的那一則）。
- 本 Issue 修復的核心風險（JS 端 `window.previousPage`/`nextPage` 尚未賦值/`view.renderer` 尚未建立時被呼叫）**無法在 `flutter test` 純 Dart 環境下重現或驗證**——`FakeInAppWebViewPlatform`（`test/support/fake_inappwebview_platform.dart`）刻意不呼叫真實的 `onWebViewCreated`，`FoliateEpubReaderView._controller` 在整個 widget test 生命週期中恆為 `null`，`_evaluate()`（`_controller?.evaluateJavascript(...)`）因此永遠是無副作用的 no-op，不論 loading 防呆是否存在，測試環境都不會真的呼叫到 JS、也不會真的崩潰。本計畫的 widget test 因此只能驗證「Dart 端的防呆分支確實提早 return」這件事本身（見 Task 1 測試設計），**JS 呼叫真的被攔截、真機不再崩潰，仍須留待真機或 `integration_test/` 驗證**——這是本計畫的已知局限，不是遺漏，已誠實記錄於此，符合本專案既有「兩層測試架構」的既定測試哲學（見 `CLAUDE.md`）。
- 每完成 Task 就跑一次 `flutter analyze`，維持乾淨。

---

### Task 1：`_handleZoneAction` 新增 loading 狀態防呆

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: 既有 `_state`（`_RenderState`，`_ReaderScreenState` 私有欄位）、`ReaderScreen.triggerZoneAction`（既有 static test helper，`app/lib/screens/reader_screen.dart:161-169`）。
- Produces: 無新增對外介面——`_handleZoneAction` 簽章不變，純粹是既有邏輯內部新增 2 個提早 return 分支。

- [ ] **Step 1：寫失敗測試——3 則新測試 ＋ 修正 1 則既有測試**

編輯 `app/test/screens/reader_screen_test.dart`：

於既有測試「`PDF 換頁時應清除既有選取狀態，AnnotationToolbar 隨之消失（Epic 24 Issue 10）`」（約 5807-5868 行）內，第 5822-5826 行：

```dart
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));

    // 情境 A：nextPage 應清除既有選取。
```

改為（新增 `onPageRendered()` 呼叫，讓 `_state` 轉為 `rendered`——本計畫新增的 loading 防呆會讓這則既有測試在維持原寫法時失敗，見 Global Constraints「重要地雷」）：

```dart
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    // epic-27-reader-device-compat Issue 1：_handleZoneAction 新增的
    // loading 狀態防呆，若 _state 仍是 loading 會直接 return（包含本測試
    // 要驗證的清除選取副作用），故需明確模擬 onPageRendered 讓 _state
    // 轉為 rendered，比照既有 EPUB 測試的既有慣例（測的是「已載入完成後
    // 換頁」情境，不是本 Issue 要防呆的「載入中換頁」情境）。
    pdfView.onPageRendered();
    await tester.pump();

    // 情境 A：nextPage 應清除既有選取。
```

於同一則測試結尾（第 5864-5868 行，`});` 之後）、下一則測試「`PDF 換頁時若有進行中的長按拖曳框選...`」之前，新增以下 3 則測試：

```dart
  testWidgets(
      'PDF：_state 仍為 loading 時觸發換頁熱區，應被忽略——不清除既有選取狀態（epic-27-reader-device-compat Issue 1）',
      (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_loading_guard',
          prefsManager: FakeReaderPrefsManager(),
          highlightsRepository: FakeHighlightsRepository(),
          notesRepository: FakeNotesRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 刻意**不**呼叫 pdfView.onPageRendered()——維持 _state == loading，
    // 模擬使用者在書籍仍在載入中時就點擊熱區的真機回報情境。
    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onSelectionRectComputed?.call(
      const PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
        widgetRect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
      ),
    );
    await tester.pump();
    expect(find.byType(AnnotationToolbar), findsOneWidget,
        reason: '選取完成後應顯示 AnnotationToolbar（此步驟與 loading 防呆無關，只是佈置情境）');

    ReaderScreen.triggerZoneAction(key, ZoneAction.nextPage);
    await tester.pump();
    expect(find.byType(AnnotationToolbar), findsOneWidget,
        reason: '_state 仍是 loading，nextPage 應被忽略——若防呆失效，'
            'PdfReaderView.nextPage 呼叫路徑會一併清除既有選取，'
            'AnnotationToolbar 將意外消失（未加防呆前的既有行為，見 '
            'epic-27-reader-device-compat Issue 1 診斷）');

    ReaderScreen.triggerZoneAction(key, ZoneAction.previousPage);
    await tester.pump();
    expect(find.byType(AnnotationToolbar), findsOneWidget,
        reason: '_state 仍是 loading，previousPage 同樣應被忽略');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'EPUB 流式：_state 仍為 loading 時觸發換頁熱區，不拋出例外（epic-27-reader-device-compat Issue 1；真機上 JS 尚未就緒時是否正確攔截需 integration_test/人工驗證，見 issues.md）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_epub_loading_guard',
          prefsManager: prefsManager,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 刻意**不**呼叫 onPageRendered()/onLayoutResolved()——維持
    // _state == loading。rightFlip 模板：index 0（左欄）＝ previousPage、
    // index 2（右欄）＝ nextPage（見 nav_zone_mode.dart
    // rightFlipZoneTemplate）。
    await tester.tap(find.byKey(const Key('nav_zone_0')));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('nav_zone_2')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'PDF：_state 已是 rendered 後，換頁熱區維持既有行為不受 loading 防呆影響（回歸檢查，epic-27-reader-device-compat Issue 1）',
      (tester) async {
    final key = GlobalKey<State<ReaderScreen>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          key: key,
          filePath: 'test/fixtures/sample_multi_page.pdf',
          bookId: 'b_pdf_rendered_no_regression',
          prefsManager: FakeReaderPrefsManager(),
          highlightsRepository: FakeHighlightsRepository(),
          notesRepository: FakeNotesRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    pdfView.onPageRendered();
    await tester.pump();
    pdfView.onSelectionRectComputed?.call(
      const PdfSelectionInfo(
        pageIndex: 0,
        rect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
        widgetRect: PercentRect(left: 0.3, top: 0.2, right: 0.6, bottom: 0.3),
      ),
    );
    await tester.pump();
    expect(find.byType(AnnotationToolbar), findsOneWidget);

    ReaderScreen.triggerZoneAction(key, ZoneAction.nextPage);
    await tester.pump();
    expect(find.byType(AnnotationToolbar), findsNothing,
        reason: '_state 已是 rendered，既有「換頁清除選取」行為應維持不變，'
            '不受新增的 loading 防呆影響（零回歸）');
  });
```

- [ ] **Step 2：執行測試確認失敗**

執行：`cd app && flutter test test/screens/reader_screen_test.dart --plain-name "loading 時觸發換頁熱區"`
預期：`PDF：_state 仍為 loading 時觸發換頁熱區，應被忽略——不清除既有選取狀態` 失敗（`AnnotationToolbar` 找不到——目前沒有防呆，`nextPage` 會照常清除選取）；`EPUB 流式：_state 仍為 loading 時觸發換頁熱區，不拋出例外` 會 PASS（此測試本來就不會因為有無防呆而改變結果，見 Global Constraints 對測試局限的說明，純粹是安全網，非本步驟的紅燈依據）。

- [ ] **Step 3：`_handleZoneAction` 新增 loading 防呆，修正既有測試**

編輯 `app/lib/screens/reader_screen.dart`：

於文件註解（第 2354-2368 行）`_handleZoneAction` 上方，`/// 熱區動作統一分派入口...` 段落結尾（第 2368 行 `== false`，epic-14-system-settings Issue 4）忽略此次觸發。` 之後）新增一句：

```dart
  /// **epic-27-reader-device-compat Issue 1**：`previousPage`/`nextPage`
  /// 於 `_state == _RenderState.loading`（書籍仍在載入中）時直接忽略，
  /// 避免 EPUB 端 `window.previousPage`/`nextPage` 賦值早於 `view.renderer`
  /// 真正建立的空窗期被觸控命中而拋出 JS 例外、被 `_handleError()` 誤判
  /// 為崩潰畫面（見 `reviews/bugfix-repro.md` Issue 1）。`menu` 動作不受
  /// 影響——它只切換 Dart 端 `_chromeVisible`，不呼叫任何 JS/native API，
  /// 無此風險。
```

於 `_handleZoneAction`（第 2383-2424 行）：

```dart
  void _handleZoneAction(ZoneAction action) {
    final format = detectBookFormat(widget.filePath);
    switch (action) {
      case ZoneAction.previousPage:
        if (format == BookFormat.pdf) {
```

改為：

```dart
  void _handleZoneAction(ZoneAction action) {
    final format = detectBookFormat(widget.filePath);
    switch (action) {
      case ZoneAction.previousPage:
        if (_state == _RenderState.loading) return;
        if (format == BookFormat.pdf) {
```

以及：

```dart
      case ZoneAction.nextPage:
        if (format == BookFormat.pdf) {
```

改為：

```dart
      case ZoneAction.nextPage:
        if (_state == _RenderState.loading) return;
        if (format == BookFormat.pdf) {
```

- [ ] **Step 4：執行測試確認通過**

執行：`cd app && flutter test test/screens/reader_screen_test.dart`
預期：全數 PASS（含 Step 1 新增的 3 則測試，以及修正後的既有「PDF 換頁時應清除既有選取狀態」測試）。

- [ ] **Step 5：執行完整分析與全專案測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS，零回歸（本次改動只觸及 `_handleZoneAction`，理論上只有 `reader_screen_test.dart` 可能受影響，已於 Step 1-4 處理；其餘測試檔不呼叫此私有方法，不應受影響，仍建議全專案跑一次確認）。

- [ ] **Step 6：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "fix(epic-27): Issue 1——_handleZoneAction 新增 loading 狀態防呆，避免載入中點擊熱區崩潰"
```

---

## 完成後的驗證（對照 `issues.md` Issue 1 驗收標準）

- [ ] `flutter analyze`：全專案 "No issues found!"
- [ ] `flutter test`：全專案通過，零回歸
- [ ] （建議，非本計畫強制自動化——見 Global Constraints「已知局限」，`flutter test` 無法驗證真實 JS 崩潰是否真的被攔截）於真機或模擬器：開啟一本較大的 EPUB（或刻意調慢網路/裝置模擬慢速開書），在載入中轉圈圈時立即點擊畫面左側／右側熱區，確認不再出現 `window.nextPage is not a function`／`Cannot read property 'next' of undefined` 崩潰畫面；PDF 亦比照測試一次（雖然程式碼分析顯示 PDF 端本無此風險，仍建議一併確認無異常）。
