# Issue 8：E-Ink 安全視窗與靜態高亮策略 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐工作項執行本計畫。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**Goal:** 朗讀跨頁、目前朗讀高亮超出畫面「安全視窗」（可視範圍 20%～80%）時，自動觸發一次性翻頁/捲動跟上進度——不論是否為 E-Ink 裝置；E-Ink 高對比模式下朗讀高亮改用靜態高對比色，非既有半透明色。

**Architecture:** 安全視窗的幾何判斷（「目前朗讀高亮的矩形位置是否還在可視範圍 20%～80% 之內」）只有 JS 端（`main.js`）能算——需要 DOM `Range.getClientRects()` 與 iframe/viewport 座標換算，這是既有 `reportSelection()`（選取範圍即時回報，`main.js` 既有函式）已經用過的同一套正規化算法，本 Issue 直接重用同一套算法，套用在既有 `draw-annotation` 監聽器（`window.showTtsHighlight()` 觸發的那一次）上。JS 端只負責回報事實（「超出範圍了，該往哪個方向」），透過新的 `onTtsHighlightOutOfSafeWindow` 橋接事件送給 Dart；**是否真的要翻頁、由誰觸發**，仍由 Dart 端（`ReaderScreen`）決定並呼叫既有 `FoliateReaderView.nextPage()`/`previousPage()`，比照 `onLocatorChanged`/`onSelectionChanged` 既有「JS 回報事實、Dart 決定政策」分工慣例，`main.js` 不自行呼叫 `view.next()`/`view.prev()`。

這個自動翻頁本身會觸發一次 `relocate` 事件（→ `onLocatorChanged`），若不處理，既有 Issue 4 邏輯（`TtsController.handleExternalPositionChange()`）會把它誤判為「使用者手動導覽」而錯誤暫停朗讀。`TtsController` 因此新增一個一次性抑制旗標 `suppressNextExternalPositionChange()`——`ReaderScreen` 觸發翻頁前先呼叫它，讓緊接著到來的那一次 `handleExternalPositionChange()` 判斷為「TTS 自己造成的位置變化」而不重設播放狀態。

由於 `resyncHighlight()`（Issue 7）與一般朗讀段切換（Issue 3）都是透過同一個 `window.showTtsHighlight()` 進入 `draw-annotation` 監聽器，安全視窗檢查天然覆蓋這兩條既有路徑，不需要另外處理。

**E-Ink 高對比色**：本專案目前對朗讀高亮**沒有任何漸變/淡入淡出動畫**（`overlayer.js` 的 `Overlayer.highlight()` 純粹同步建立 SVG 元素，`main.js`/`index.html` 也沒有任何 CSS `transition` 規則），所以「E-Ink 模式停用漸變動畫、非 E-Ink 模式維持既有動畫效果」這項需求，落地後只剩「E-Ink 模式改用靜態高對比色」這一半有實際程式碼——半透明橙色（既有 `TTS_HIGHLIGHT_COLOR`）在低對比度 E-Ink 螢幕上容易被灰階轉換抹平成幾乎看不見的淡灰色，改用高對比純黑即可解決；非 E-Ink 模式維持既有半透明橙色不動，天然零回歸。本計畫不會新增一個原本不存在的動畫、只為了有東西可以「停用」——那是無中生有的範圍膨脹。

**Tech Stack:** 純既有基礎設施——`main.js`（本專案自行維護的橋接層，非 vendored 檔案，可自由修改）既有 `Overlayer`/`view.addAnnotation()`/`draw-annotation` 事件管線；`flutter_inappwebview` 既有 `addJavaScriptHandler`/`evaluateJavascript` 橋接機制。不新增任何套件相依。

**Spec:** `docs/epics/epic-34-tts-readalong/issues.md`「Issue 8」；`docs/epics/epic-34-tts-readalong/spec.md`「高亮渲染」段落、User Story 13／14；`docs/epics/epic-34-tts-readalong/design.md`／Foliate 篇研究報告 §3.4。

## 計畫修訂記錄（2026-08-28，依 `reviews/review-plan-issue-8.md`）

- **採納 Critical #1＋Important #1（合併修正）**：原版 `needNext`/`needPrev` 對安全視窗上下限（0.2/0.8）做對稱判斷，會在剛翻到新頁、頁首內容落在 0.2 門檻內時，把「正常可見」誤判為「還沒進入視野」而立刻觸發翻回上一頁，導致新頁與前一頁之間無限來回翻頁。修正為：`next` 用安全視窗軟門檻（提早觸發、體驗較平滑）；`prev` 只在段落真的超出目前頁面範圍（硬邊界 0.0/1.0）時才觸發——只有連續按「上一句」跳回前一頁才會發生。另外原版只量測單一軸向（依 `isVertical` 二擇一），改為 X／Y 兩軸都檢查、任一軸超出即視為不可見，避免對「哪一軸才是分頁進程軸」的判斷有誤（`paginator.js` 對直排/橫排的 CSS multi-column 設定互為相反，見 Task 1 Step 4 程式碼註解）。
- **採納 Important #2（旗標生命週期），但重設點與審查建議不同**：審查建議在 `play()` 開始、`dispose()`、`_status` 變為 `idle` 時重設旗標；改為在既有 4 個「重設回 idle」的既有程式碼位置（`play()` 的 `paused` 分支錯誤處理、`nextSegment()`／`_handleSegmentCompleted()` 的「已是最後一段」分支、`_playCurrentSegment()` 的 `catch`）與 `dispose()` 一併清除——這 4 個位置本來就已經是「進入 idle」的唯一入口，涵蓋審查建議的「`_status` 變為 `idle` 時重設」；不採納「`play()` 開始時額外重設」，因為旗標在進入 idle 時已經清除，`play()` 只會從 idle/paused 呼叫，屆時旗標必然已是 `false`，額外重設是多餘的。
- **採納 Important #3**：JS handler 參數改用 `is String` 防禦性檢查，比照既有 `onSelectionChanged` 慣例。
- Minor 觀察（`_openGroupFilteredView` 已完整轉發 `themeDependencies`、regression guard 字串須與修正後程式碼同步）：前者確認無需改動，後者已於本次修訂一併更新。

## Global Constraints

- **不修改任何 vendored `foliate-js` 原始碼**（`view.js`/`overlayer.js`/`paginator.js`/`epubcfi.js`，ADR 0011／0013）：本計畫只修改 `main.js`（本專案自行撰寫的橋接層）與 Dart 端檔案。
- **安全視窗範圍固定為 0.2～0.8**（`TTS_SAFE_WINDOW_MIN`/`TTS_SAFE_WINDOW_MAX`），對應 `issues.md`「可視範圍 20%～80%」的具體數字，非可設定項目——本 Issue 不新增使用者可調整的安全視窗設定介面（未被要求）。
- **安全視窗跟隨翻頁機制不受 `isEinkMode` 旗標限制**：一般裝置與 E-Ink 裝置皆須觸發，只有「高亮視覺呈現方式」（顏色）依 `isEinkMode` 分流。
- **不新增動畫基礎設施**：`overlayer.js` 目前沒有任何 CSS transition，本計畫不新增。
- **`TtsController` 既有播放邏輯不變**：`play()`/`pause()`/`nextSegment()`/`previousSegment()`/`setSpeed()`/`resyncHighlight()` 既有方法簽章與行為皆不變，本 Issue 只新增一個全新方法 `suppressNextExternalPositionChange()`，並在 `handleExternalPositionChange()` 開頭加一段提早 return 分支。
- **`FoliateReaderView.showTtsHighlight()` 簽章變動屬 breaking change**：新增 `required bool einkMode` 具名參數，唯一既有呼叫端（`reader_screen.dart`）於 Task 4 一併更新，`flutter analyze` 會攔下任何遺漏的呼叫端。
- **誠實測試邊界**（比照 Issue 3～7 既有慣例）：`flutter_test` 環境下 `FoliateReaderView._controller` 恆為 `null`，JS 端實際送出的 `_evaluate()` 呼叫參數、真實 DOM 幾何計算結果，皆無法在 Dart widget test 這層直接攔截斷言。JS 端邏輯正確性由 `main.js` 原始碼字串斷言（regression guard，比照既有 Issue 3/4 慣例）覆蓋；`TtsController` 新方法的狀態機正確性由純 Dart 單元測試覆蓋；`ReaderScreen`/`library_screen.dart` 層測試只驗證「接線本身不崩潰、依賴正確貫穿」；真實幾何方向判斷（尤其直排/橫排的翻頁方向是否正確）**只能真機驗證**，見本計畫末尾「真機驗收清單」。
- **測試執行範圍**（比照專案既有政策）：每個 Task 只跑該次異動觸及的測試檔，不需重跑全套 `flutter test`；全套 `flutter test` 只在本計畫最後一個 Task 完成時、以及發 PR 前各執行一次。

---

### Task 1：`main.js`——安全視窗幾何判斷＋E-Ink 高對比色

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`（`TTS_HIGHLIGHT_COLOR` 常數與 `window.showTtsHighlight` 附近，約第 414-449 行；既有 `draw-annotation` 監聽器，約第 827-849 行）
- Test: `app/test/reader/foliate_reader_view_test.dart`（新增 regression guard group，插入於既有「main.js 朗讀段反向查找 regression guard（epic-34-tts-readalong Issue 4）」group 之後，約第 1497 行之後）

**Interfaces:**
- Consumes：既有 `view.addAnnotation()`/`draw-annotation` 事件（`{ draw, annotation, doc, range }`，`view.js` 既有 API，`range`/`doc` 目前既有程式碼未解構，本 Task 新增解構）、既有 `NOTE_PREFIX`/`currentTtsAnnotationValue`（Issue 3 既有機制）、既有 `window.flutter_inappwebview.callHandler()`（`flutter_inappwebview` 既有橋接 API）。
- Produces：`window.showTtsHighlight(cfi, vertical, einkMode)`（第三參數變動，供 Task 2 的 Dart 端呼叫）；新橋接事件 `onTtsHighlightOutOfSafeWindow`，帶一個字串參數 `'next'` 或 `'prev'`（供 Task 2 的 Dart 端註冊監聽）。

- [ ] **Step 1：寫 regression guard 測試（預期失敗）**

在 `app/test/reader/foliate_reader_view_test.dart` 第 1497 行（既有「main.js 朗讀段反向查找 regression guard」group 的結尾 `});` 之後）插入：

```dart
  group('main.js 安全視窗跟隨翻頁 + E-Ink 高對比 regression guard（epic-34-tts-readalong Issue 8）', () {
    late String mainJsSource;

    setUpAll(() {
      mainJsSource = File('android/app/src/main/assets/foliate/main.js')
          .readAsStringSync();
    });

    test('window.showTtsHighlight 依 einkMode 選用高對比純色或既有半透明色', () {
      expect(
        mainJsSource.contains(
          'color: einkMode ? TTS_HIGHLIGHT_COLOR_EINK : TTS_HIGHLIGHT_COLOR,',
        ),
        isTrue,
        reason: 'main.js 內找不到 einkMode 三元判斷式——E-Ink 高對比模式下'
            '朗讀高亮須改用高對比純色，非既有半透明橙色（低對比度 E-Ink '
            '螢幕上容易被灰階轉換抹平成幾乎看不見的淡灰色）。',
      );
      expect(
        mainJsSource.contains(
          "window.showTtsHighlight = function (cfi, vertical, einkMode)",
        ),
        isTrue,
        reason: 'window.showTtsHighlight 須新增 einkMode 第三參數。',
      );
    });

    test('安全視窗常數為 0.2～0.8（issues.md「可視範圍 20%～80%」）', () {
      expect(mainJsSource.contains('const TTS_SAFE_WINDOW_MIN = 0.2'), isTrue,
          reason: 'main.js 內找不到安全視窗下限常數。');
      expect(mainJsSource.contains('const TTS_SAFE_WINDOW_MAX = 0.8'), isTrue,
          reason: 'main.js 內找不到安全視窗上限常數。');
    });

    test('draw-annotation 監聽器僅在目前朗讀高亮（value 與 currentTtsAnnotationValue 相符）時才觸發安全視窗檢查',
        () {
      expect(
        mainJsSource.contains('annotation.value === currentTtsAnnotationValue'),
        isTrue,
        reason: '若少了這個判斷，一般劃線/備註（window.setDecorations()，'
            '走裸 cfi key，非 foliate-note: 前綴）的 draw-annotation 事件'
            '也會誤觸發翻頁。',
      );
    });

    test('超出安全視窗時呼叫 onTtsHighlightOutOfSafeWindow', () {
      expect(
        mainJsSource
            .contains("callHandler('onTtsHighlightOutOfSafeWindow', 'next')"),
        isTrue,
      );
      expect(
        mainJsSource
            .contains("callHandler('onTtsHighlightOutOfSafeWindow', 'prev')"),
        isTrue,
      );
    });

    // 審查修正（review-plan-issue-8.md Critical #1／Important #1）：
    // next 用安全視窗軟門檻（0.2/0.8）提早觸發；prev 只能用「真正超出
    // 目前頁面範圍」的硬邊界（0.0/1.0）判斷，兩者不可對稱使用同一組
    // 門檻——否則分頁模式下剛翻到新頁的頁首內容（normY≈0.1，仍在頁面
    // 內、正常可見）會被誤判為「還沒進入視野」而觸發 prev()，導致新頁
    // 與前一頁之間無限來回翻頁。X／Y 兩軸皆須檢查，不能只看單一軸向
    // ——分頁模式底層 CSS multi-column 的實際分欄/分頁軸向依排版方向
    // 而不同（見 paginator.js columnize()），兩軸個別檢查、任一軸超出
    // 即視為不可見，可同時涵蓋兩種可能的軸向假設。
    test('needNext 使用安全視窗軟門檻（0.2/0.8），X/Y 兩軸皆檢查', () {
      expect(
        mainJsSource.contains('normX < TTS_SAFE_WINDOW_MIN || normY > 1.0'),
        isTrue,
        reason: '直排分支缺少這個條件——next 判斷須同時檢查 X 軸軟門檻與 '
            'Y 軸硬邊界。',
      );
      expect(
        mainJsSource.contains('normY > TTS_SAFE_WINDOW_MAX || normX > 1.0'),
        isTrue,
        reason: '橫排分支缺少這個條件——next 判斷須同時檢查 Y 軸軟門檻與 '
            'X 軸硬邊界。',
      );
    });

    test('needPrev 只能用真正超出頁面範圍的硬邊界（0.0/1.0）判斷，不可沿用安全視窗軟門檻（避免翻頁死循環）',
        () {
      expect(
        mainJsSource.contains('normX > 1.0 || normY < 0.0'),
        isTrue,
        reason: '直排分支的 prev 判斷式缺少或誤用了門檻——不可出現 '
            'TTS_SAFE_WINDOW_MIN/MAX，否則新頁頁首會被誤判為需要翻回'
            '上一頁。',
      );
      expect(
        mainJsSource.contains('normY < 0.0 || normX < 0.0'),
        isTrue,
        reason: '橫排分支的 prev 判斷式缺少或誤用了門檻——不可出現 '
            'TTS_SAFE_WINDOW_MIN/MAX，否則新頁頁首會被誤判為需要翻回'
            '上一頁。',
      );
      // 反向防呆：確保 prev 判斷式真的沒有誤用安全視窗常數（防止只改了
      // 上面兩個 needPrev 條件字串、卻忘記移除舊的對稱寫法殘留）。
      expect(
        mainJsSource.contains(
          'const needPrev = isVertical\n            ? center > TTS_SAFE_WINDOW_MAX\n            : center < TTS_SAFE_WINDOW_MIN',
        ),
        isFalse,
        reason: '找到舊版對稱門檻寫法殘留——這正是造成翻頁死循環的錯誤'
            '版本（review-plan-issue-8.md Critical #1），必須確認已被'
            '取代，不是新舊兩份判斷式同時存在。',
      );
    });
  });

```

- [ ] **Step 2：執行測試，確認因找不到字串而失敗**

Run: `flutter test test/reader/foliate_reader_view_test.dart --plain-name "main.js 安全視窗跟隨翻頁"`
Expected: FAIL——六個 `test()` 皆因對應字串在 `main.js` 內尚不存在而失敗。

- [ ] **Step 3：修改 `main.js`——`showTtsHighlight` 新增 `einkMode` 參數與高對比色常數**

找到既有第 429-443 行（`TTS_HIGHLIGHT_COLOR` 常數到 `window.showTtsHighlight` 結尾）：

```js
const TTS_HIGHLIGHT_COLOR = 'rgba(251, 146, 60, 0.45)'
let currentTtsAnnotationValue = null

window.showTtsHighlight = function (cfi, vertical) {
  if (currentTtsAnnotationValue) {
    view.deleteAnnotation({ value: currentTtsAnnotationValue })
  }
  currentTtsAnnotationValue = 'foliate-note:' + cfi
  view.addAnnotation({
    value: currentTtsAnnotationValue,
    color: TTS_HIGHLIGHT_COLOR,
    isUnderline: false,
    vertical,
  })
}
```

改為：

```js
const TTS_HIGHLIGHT_COLOR = 'rgba(251, 146, 60, 0.45)'
// epic-34-tts-readalong Issue 8：E-Ink 高對比模式的朗讀高亮改用高對比純
// 色——半透明橙色（TTS_HIGHLIGHT_COLOR）在低對比度 E-Ink 螢幕上容易被
// 灰階轉換抹平成幾乎看不見的淡灰色。本專案目前對朗讀高亮沒有任何漸變/
// 淡入淡出動畫（overlayer.js 的 Overlayer.highlight() 純粹同步建立 SVG
// 元素，沒有 CSS transition），故「E-Ink 模式停用漸變動畫」這項需求落地
// 後只剩「改用靜態高對比色」這一半有實際程式碼；「非 E-Ink 模式維持既有
// 動畫效果」在沒有既有動畫的前提下等同維持現狀，不需要另外實作。
const TTS_HIGHLIGHT_COLOR_EINK = 'rgba(0, 0, 0, 0.75)'
let currentTtsAnnotationValue = null

window.showTtsHighlight = function (cfi, vertical, einkMode) {
  if (currentTtsAnnotationValue) {
    view.deleteAnnotation({ value: currentTtsAnnotationValue })
  }
  currentTtsAnnotationValue = 'foliate-note:' + cfi
  view.addAnnotation({
    value: currentTtsAnnotationValue,
    color: einkMode ? TTS_HIGHLIGHT_COLOR_EINK : TTS_HIGHLIGHT_COLOR,
    isUnderline: false,
    vertical,
  })
}
```

- [ ] **Step 4：修改 `main.js`——`draw-annotation` 監聽器新增安全視窗幾何判斷**

找到既有 `draw-annotation` 監聽器（約第 827-849 行）：

```js
    view.addEventListener('draw-annotation', (e) => {
      const { draw, annotation } = e.detail
      // epic-34-tts-readalong Issue 3：annotation.vertical 由
      // window.showTtsHighlight() 明確傳入（見上方），讓朗讀高亮的直排/
      // 橫排判斷不依賴 currentWritingMode 的更新時機（理論上兩者恆一致，
      // 這裡是額外的顯式保險，也讓 Dart 端呼叫參數本身可被觀察/測試）。
      // 劃線/備註既有呼叫（window.setDecorations()）從未設定這個欄位，
      // ??（nullish coalescing，非 ||）確保只有 undefined 才落回
      // currentWritingMode——若誤用 ||，annotation.vertical 為合法值
      // false（橫排）時會被誤判為「未設定」而錯誤退回 currentWritingMode。
      const isVertical = annotation.vertical ?? (currentWritingMode === 'vertical')
      if (annotation.isUnderline) {
        draw(Overlayer.underline, {
          color: annotation.color,
          writingMode: isVertical ? 'vertical-rl' : 'horizontal-tb',
        })
      } else {
        draw(Overlayer.highlight, {
          color: annotation.color,
          vertical: isVertical,
        })
      }
    })
```

改為（新增 `TTS_SAFE_WINDOW_MIN`/`MAX` 模組層級常數，放在 `TTS_HIGHLIGHT_COLOR_EINK` 常數之後；並在監聽器內解構 `doc, range`、追加安全視窗判斷）：

先在 `const TTS_HIGHLIGHT_COLOR_EINK = ...` 那一行之後插入：

```js
// epic-34-tts-readalong Issue 8：安全視窗（issues.md「可視範圍 20%～
// 80%」）——朗讀高亮的可視範圍正規化位置只要落在這個區間內就不觸發翻頁，
// 避免逐句捲動造成頻繁刷新（E-Ink 殘影）／頻繁跳動（一般裝置）。
const TTS_SAFE_WINDOW_MIN = 0.2
const TTS_SAFE_WINDOW_MAX = 0.8
```

再把 `draw-annotation` 監聽器改為：

```js
    view.addEventListener('draw-annotation', (e) => {
      const { draw, annotation, doc, range } = e.detail
      // epic-34-tts-readalong Issue 3：annotation.vertical 由
      // window.showTtsHighlight() 明確傳入（見上方），讓朗讀高亮的直排/
      // 橫排判斷不依賴 currentWritingMode 的更新時機（理論上兩者恆一致，
      // 這裡是額外的顯式保險，也讓 Dart 端呼叫參數本身可被觀察/測試）。
      // 劃線/備註既有呼叫（window.setDecorations()）從未設定這個欄位，
      // ??（nullish coalescing，非 ||）確保只有 undefined 才落回
      // currentWritingMode——若誤用 ||，annotation.vertical 為合法值
      // false（橫排）時會被誤判為「未設定」而錯誤退回 currentWritingMode。
      const isVertical = annotation.vertical ?? (currentWritingMode === 'vertical')
      if (annotation.isUnderline) {
        draw(Overlayer.underline, {
          color: annotation.color,
          writingMode: isVertical ? 'vertical-rl' : 'horizontal-tb',
        })
      } else {
        draw(Overlayer.highlight, {
          color: annotation.color,
          vertical: isVertical,
        })
      }
      // epic-34-tts-readalong Issue 8：安全視窗跟隨翻頁。只在這是「目前
      // 的朗讀高亮」時才檢查——annotation.value 與 currentTtsAnnotationValue
      // 相符時才成立；劃線/備註（window.setDecorations()）走的是不帶
      // foliate-note: 前綴的裸 cfi key，恆不相符，不受影響。
      // resyncHighlight()（Issue 7）與一般朗讀段切換（Issue 3）都是透過
      // 同一個 window.showTtsHighlight() 進來，天然共用這段判斷。
      if (annotation.value === currentTtsAnnotationValue) {
        const rect = range.getClientRects()[0]
        const frameEl = doc.defaultView && doc.defaultView.frameElement
        if (rect && frameEl) {
          const iframeRect = frameEl.getBoundingClientRect()
          const viewportRect = view.getBoundingClientRect()
          const normX = (iframeRect.left + (rect.left + rect.right) / 2 - viewportRect.left) / viewportRect.width
          const normY = (iframeRect.top + (rect.top + rect.bottom) / 2 - viewportRect.top) / viewportRect.height
          // 審查修正（review-plan-issue-8.md Critical #1／Important #1）：
          // 分頁模式下「頁首」是正常可見內容，不能因為位置接近 0 就誤判
          // 為「還沒進入視野」而觸發 prev()——否則剛翻到新頁的第一句會
          // 立刻被翻回上一頁，跟前一頁之間無限來回翻頁震盪。next 用安全
          // 視窗軟門檻（0.2/0.8，提早觸發、體驗較平滑）；prev 只能用
          // 「段落真的已經落在目前頁面範圍之外」的硬邊界（0.0/1.0）判斷
          // ——只有使用者連按「上一句」（Issue 5）跳回前一頁時才會發生。
          // X／Y 兩軸皆檢查、不只看單一軸向：分頁模式底層 CSS
          // multi-column 實際的分欄/分頁軸向依排版方向而不同（見
          // paginator.js columnize()——直排固定 width、橫排固定
          // height，兩者互為相反），為避免對「哪一軸才是分頁進程軸」的
          // 判斷有誤，兩軸個別檢查、任一軸超出即視為不可見；此推導仍須
          // 真機分別驗證橫排/直排兩種模式，見 plan-issue-8.md 真機驗收
          // 清單。
          const needNext = isVertical
            ? normX < TTS_SAFE_WINDOW_MIN || normY > 1.0
            : normY > TTS_SAFE_WINDOW_MAX || normX > 1.0
          const needPrev = isVertical
            ? normX > 1.0 || normY < 0.0
            : normY < 0.0 || normX < 0.0
          if (needNext) {
            window.flutter_inappwebview.callHandler('onTtsHighlightOutOfSafeWindow', 'next')
          } else if (needPrev) {
            window.flutter_inappwebview.callHandler('onTtsHighlightOutOfSafeWindow', 'prev')
          }
        }
      }
    })
```

- [ ] **Step 5：執行測試，確認通過**

Run: `flutter test test/reader/foliate_reader_view_test.dart --plain-name "main.js 安全視窗跟隨翻頁"`
Expected: PASS（6 個測試）。另外重跑既有「main.js 朗讀高亮 regression guard（Issue 3）」與「main.js 朗讀段反向查找 regression guard（Issue 4）」兩個既有 group（`--plain-name "main.js 朗讀高亮"` / `"main.js 朗讀段反向查找"`），確認零回歸（`draw-annotation` 監聽器解構新增 `doc, range` 不影響既有 `isVertical`/draw 分支邏輯）。

- [ ] **Step 6：Commit**

```bash
git add android/app/src/main/assets/foliate/main.js test/reader/foliate_reader_view_test.dart
git commit -m "feat(epic-34): main.js 安全視窗跟隨翻頁判斷與 E-Ink 高對比色"
```

---

### Task 2：`foliate_reader_view.dart`——Dart 橋接層

**Files:**
- Modify: `app/lib/reader/foliate_reader_view.dart`（新增 `onTtsHighlightOutOfSafeWindow` 欄位、JS handler 註冊；更新 `showTtsHighlight` 靜態方法簽章）
- Test: `app/test/reader/foliate_reader_view_test.dart`（緊接 Task 1 新增的 group 之後）

**Interfaces:**
- Consumes：Task 1 產出的 `window.showTtsHighlight(cfi, vertical, einkMode)`／`onTtsHighlightOutOfSafeWindow` JS 事件。
- Produces：`FoliateReaderView.onTtsHighlightOutOfSafeWindow`（`ValueChanged<String>?` 欄位，供 Task 4 的 `ReaderScreen` 注入）；`FoliateReaderView.showTtsHighlight(key, cfi, {required bool vertical, required bool einkMode})`（供 Task 4 呼叫）。

- [ ] **Step 1：寫測試（預期失敗——欄位/具名參數尚不存在，無法編譯）**

在 Task 1 新增的 group 之後（同一份測試檔）插入：

```dart
  group('onTtsHighlightOutOfSafeWindow（epic-34-tts-readalong Issue 8）', () {
    test('建構參數正確保存於 widget 欄位', () {
      void handler(String direction) {}
      final view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onTtsHighlightOutOfSafeWindow: handler,
      );
      expect(view.onTtsHighlightOutOfSafeWindow, same(handler));
    });

    test('未提供時預設為 null（既有呼叫端零回歸）', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      );
      expect(view.onTtsHighlightOutOfSafeWindow, isNull);
    });
  });

```

- [ ] **Step 2：執行測試，確認因編譯錯誤失敗**

Run: `flutter test test/reader/foliate_reader_view_test.dart --plain-name "onTtsHighlightOutOfSafeWindow"`
Expected: FAIL——`onTtsHighlightOutOfSafeWindow` 具名參數不存在，編譯錯誤。

- [ ] **Step 3：`foliate_reader_view.dart` 新增欄位與建構參數**

在既有 `final VoidCallback? onSelectionCleared;`（第 421 行）之後新增：

```dart
  /// 安全視窗跟隨翻頁（epic-34-tts-readalong Issue 8）：main.js
  /// draw-annotation 監聽器偵測到目前朗讀高亮超出安全視窗（可視範圍
  /// 20%～80%）時觸發，帶入 `'next'` 或 `'prev'`（main.js 依 isVertical
  /// 分流判斷出的方向）。呼叫端（[ReaderScreen]）收到後呼叫
  /// [FoliateReaderView.nextPage]/[previousPage] 觸發一次性翻頁——本欄位
  /// 只負責回報「超出範圍了、該往哪個方向」這個事實，不自行決定要不要
  /// 真的翻頁，比照 [onLocatorChanged]/[onSelectionChanged] 既有的
  /// 「JS 回報事實、Dart 決定政策」分工慣例。
  final ValueChanged<String>? onTtsHighlightOutOfSafeWindow;
```

建構子參數列（第 463-465 行 `this.onLocatorChanged, this.onSelectionChanged, this.onSelectionCleared,` 之後）新增：

```dart
    this.onTtsHighlightOutOfSafeWindow,
```

- [ ] **Step 4：註冊 JS handler**

在既有 `onTtsSegmentIndexReady` handler 註冊區塊（第 766-774 行）之後新增：

```dart
    controller.addJavaScriptHandler(
      handlerName: 'onTtsHighlightOutOfSafeWindow',
      callback: (args) {
        // 審查修正（review-plan-issue-8.md Important #3）：比照既有
        // onSelectionChanged 的防禦性轉型慣例（見上方 argAt()），用
        // `is String` 檢查取代直接 `as String` 強制轉型——main.js 端目前
        // 恆傳字串常值，但若未來橋接參數格式意外變動（例如傳入 null 或
        // 未定義物件），直接強制轉型會拋出執行期 TypeError。
        final direction = (args.isNotEmpty && args[0] is String)
            ? args[0] as String
            : 'next';
        widget.onTtsHighlightOutOfSafeWindow?.call(direction);
      },
    );
```

- [ ] **Step 5：更新 `showTtsHighlight` 靜態方法簽章**

第 557-568 行既有：

```dart
  static void showTtsHighlight(
    GlobalKey<State<FoliateReaderView>> key,
    String cfi, {
    required bool vertical,
  }) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      state._evaluate(
        'window.showTtsHighlight(${jsonEncode(cfi)}, $vertical)',
      );
    }
  }
```

改為：

```dart
  static void showTtsHighlight(
    GlobalKey<State<FoliateReaderView>> key,
    String cfi, {
    required bool vertical,
    required bool einkMode,
  }) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      state._evaluate(
        'window.showTtsHighlight(${jsonEncode(cfi)}, $vertical, $einkMode)',
      );
    }
  }
```

- [ ] **Step 6：執行測試，確認通過**

Run: `flutter test test/reader/foliate_reader_view_test.dart`
Expected: PASS（全檔案，含 Task 1/2 新增測試與既有測試皆通過——這一步先跑整個檔案，確認 `showTtsHighlight` 簽章變動沒有波及本檔案內其他既有測試）。

- [ ] **Step 7：Commit**

```bash
git add lib/reader/foliate_reader_view.dart test/reader/foliate_reader_view_test.dart
git commit -m "feat(epic-34): FoliateReaderView 新增安全視窗事件橋接與 showTtsHighlight einkMode 參數"
```

---

### Task 3：`TtsController.suppressNextExternalPositionChange()`（TDD）

**Files:**
- Modify: `app/lib/reader/tts_controller.dart`
- Test: `app/test/reader/tts_controller_test.dart`

**Interfaces:**
- Consumes：無新依賴，純狀態機內部邏輯。
- Produces：`TtsController.suppressNextExternalPositionChange()`（無回傳值），供 Task 4 的 `ReaderScreen` 在觸發安全視窗自動翻頁前呼叫。

- [ ] **Step 1：寫失敗測試**

在 `app/test/reader/tts_controller_test.dart` 既有 `handleExternalPositionChange()` 測試群組附近（第 466-479 行「paused 狀態下呼叫」測試之後）插入：

```dart
  test(
      'suppressNextExternalPositionChange() 後緊接著一次 handleExternalPositionChange() 呼叫，'
      '不重設播放狀態（epic-34-tts-readalong Issue 8：安全視窗自動翻頁不應誤觸發暫停）',
      () async {
    final highlighted = <TtsSegmentCfi?>[];
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      onHighlightSegment: highlighted.add,
    );
    await controller.play();
    expect(controller.status, TtsPlaybackStatus.playing);
    highlighted.clear();

    controller.suppressNextExternalPositionChange();
    controller.handleExternalPositionChange();

    expect(controller.status, TtsPlaybackStatus.playing);
    expect(controller.currentIndex, 0);
    expect(controller.segments, segments);
    expect(highlighted, isEmpty,
        reason: '不應清除高亮——這次位置變化是 TTS 自己造成的安全視窗翻頁，'
            '不是使用者手動導覽。');
    expect(player.callLog, isEmpty,
        reason: '不應呼叫 player.pause()——播放不應中斷。');
  });

  test('抑制旗標只抑制「緊接著的下一次」呼叫，之後的 handleExternalPositionChange() 恢復既有暫停行為',
      () async {
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
    );
    await controller.play();

    controller.suppressNextExternalPositionChange();
    controller.handleExternalPositionChange(); // 消耗掉旗標，維持 playing
    expect(controller.status, TtsPlaybackStatus.playing);

    controller.handleExternalPositionChange(); // 真正的使用者手動導覽

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.currentIndex, -1);
  });

  // 審查修正（review-plan-issue-8.md Important #2）：抑制旗標若在設下後
  // 從未被 handleExternalPositionChange() 消耗（例如安全視窗觸發的翻頁
  // 剛好是全書最後一頁、next() 沒有效果、不會產生新的 relocate 事件），
  // 會一路殘留到下一次全新播放，錯誤抑制之後完全不相關的一次手動導覽。
  test(
      '抑制旗標若在章節自然播畢（未經 handleExternalPositionChange 消耗）前設下，'
      '不會遺留到下一輪播放、誤抑制之後真正的手動導覽（審查 review-plan-issue-8.md Important #2）',
      () async {
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
    );
    await controller.play();
    controller.suppressNextExternalPositionChange();
    // 模擬「安全視窗觸發的翻頁最終沒有送出 relocate 事件」——章節透過
    // 連續按下一句到底自然播畢，而非透過 handleExternalPositionChange()
    // 消耗掉旗標。
    await controller.nextSegment(); // -> index 1
    await controller.nextSegment(); // 超出範圍，重設為 idle
    expect(controller.status, TtsPlaybackStatus.idle);

    // 重新開始一次全新的播放。
    await controller.play();
    expect(controller.status, TtsPlaybackStatus.playing);

    controller.handleExternalPositionChange(); // 這次是真正的使用者手動導覽

    expect(controller.status, TtsPlaybackStatus.idle,
        reason: '若抑制旗標從上一輪播放遺留下來，這裡會被誤判為 TTS 自己'
            '造成的位置變化而維持 playing，導致這次真正的手動導覽沒有'
            '正確觸發自動暫停。');
  });
```

- [ ] **Step 2：執行測試，確認失敗**

Run: `flutter test test/reader/tts_controller_test.dart --plain-name "suppressNextExternalPositionChange"`
Expected: FAIL——`suppressNextExternalPositionChange` 方法不存在，編譯錯誤。

- [ ] **Step 3：實作**

在 `app/lib/reader/tts_controller.dart` 既有 `handleExternalPositionChange()` 方法（第 254-276 行）之前新增欄位與方法：

```dart
  /// 安全視窗跟隨翻頁（epic-34-tts-readalong Issue 8）觸發的一次性自動
  /// 翻頁，即將呼叫端（[ReaderScreen]）對 [FoliateReaderView] 送出下一頁/
  /// 上一頁指令前，須先呼叫本方法設下這個旗標——讓緊接著到來的那一次
  /// [handleExternalPositionChange] 呼叫（由該次翻頁觸發的 relocate 事件
  /// 間接引發）被判斷為「TTS 自己造成的位置變化」而不重設播放狀態，而非
  /// 誤判為使用者手動導覽而錯誤暫停播放。旗標只抑制「緊接著的下一次」
  /// 呼叫，用過即清除——若安全視窗翻頁與真正的使用者手動導覽幾乎同時
  /// 發生，只有先抵達的那一次呼叫會被抑制，屬可接受的邊界情況（見
  /// `plan-issue-8.md` 設計理由）。
  bool _suppressNextPositionChange = false;

  void suppressNextExternalPositionChange() {
    if (_disposed) return;
    _suppressNextPositionChange = true;
  }

```

修改既有 `handleExternalPositionChange()` 方法開頭（第 254-256 行）：

```dart
  void handleExternalPositionChange() {
    if (_disposed) return;
    _playGeneration++;
```

改為：

```dart
  void handleExternalPositionChange() {
    if (_disposed) return;
    if (_suppressNextPositionChange) {
      _suppressNextPositionChange = false;
      return;
    }
    _playGeneration++;
```

其餘方法內容不動。

審查修正（review-plan-issue-8.md Important #2）：抑制旗標若設下後從未被 `handleExternalPositionChange()` 消耗（例如安全視窗觸發的翻頁剛好是全書最後一頁、`next()` 沒有效果、不會產生新的 relocate 事件），會一路殘留到下一輪播放。修法是在既有「重設回 idle」的四個既有位置，以及 `dispose()`，一併清除這個旗標——這四個位置本來就已經一起重設 `_status`/`_currentIndex`/`_segments`，多加這一行是同一組「結束目前播放段落」狀態重設的自然延伸，不是另外新增一套獨立的清理機制。

第一處，`play()` 的 `paused` 分支錯誤處理（第 110-119 行）既有：

```dart
      try {
        await player.play();
      } catch (_) {
        if (_disposed) return;
        _status = TtsPlaybackStatus.idle;
        _currentIndex = -1;
        _segments = const [];
        onHighlightSegment?.call(null);
        notifyListeners();
      }
      return;
```

改為（新增一行 `_suppressNextPositionChange = false;`）：

```dart
      try {
        await player.play();
      } catch (_) {
        if (_disposed) return;
        _status = TtsPlaybackStatus.idle;
        _currentIndex = -1;
        _segments = const [];
        _suppressNextPositionChange = false;
        onHighlightSegment?.call(null);
        notifyListeners();
      }
      return;
```

第二處，`nextSegment()` 的「已是最後一段」分支（第 194-204 行）既有：

```dart
    if (nextIndex >= _segments.length) {
      _segmentGeneration++;
      _status = TtsPlaybackStatus.idle;
      _currentIndex = -1;
      _segments = const [];
      try {
        player.pause().catchError((_) {});
      } catch (_) {}
      onHighlightSegment?.call(null);
      notifyListeners();
      return;
    }
```

改為：

```dart
    if (nextIndex >= _segments.length) {
      _segmentGeneration++;
      _status = TtsPlaybackStatus.idle;
      _currentIndex = -1;
      _segments = const [];
      _suppressNextPositionChange = false;
      try {
        player.pause().catchError((_) {});
      } catch (_) {}
      onHighlightSegment?.call(null);
      notifyListeners();
      return;
    }
```

第三處，`_playCurrentSegment()` 的 `catch` 區塊（第 349-356 行）既有：

```dart
    } catch (_) {
      if (_disposed || generation != _segmentGeneration) return;
      _status = TtsPlaybackStatus.idle;
      _currentIndex = -1;
      _segments = const [];
      onHighlightSegment?.call(null);
      notifyListeners();
    }
```

改為：

```dart
    } catch (_) {
      if (_disposed || generation != _segmentGeneration) return;
      _status = TtsPlaybackStatus.idle;
      _currentIndex = -1;
      _segments = const [];
      _suppressNextPositionChange = false;
      onHighlightSegment?.call(null);
      notifyListeners();
    }
```

第四處，`_handleSegmentCompleted()` 的「已是最後一段」分支（第 359-370 行）既有：

```dart
  Future<void> _handleSegmentCompleted() async {
    if (_disposed) return;
    if (_status != TtsPlaybackStatus.playing) return;
    final nextIndex = _currentIndex + 1;
    if (nextIndex >= _segments.length) {
      _status = TtsPlaybackStatus.idle;
      _currentIndex = -1;
      _segments = const [];
      onHighlightSegment?.call(null);
      notifyListeners();
      return;
    }
```

改為：

```dart
  Future<void> _handleSegmentCompleted() async {
    if (_disposed) return;
    if (_status != TtsPlaybackStatus.playing) return;
    final nextIndex = _currentIndex + 1;
    if (nextIndex >= _segments.length) {
      _status = TtsPlaybackStatus.idle;
      _currentIndex = -1;
      _segments = const [];
      _suppressNextPositionChange = false;
      onHighlightSegment?.call(null);
      notifyListeners();
      return;
    }
```

第五處，`dispose()`（第 375-381 行）既有：

```dart
  @override
  void dispose() {
    _disposed = true;
    _completedSub?.cancel();
    player.dispose();
    super.dispose();
  }
```

改為：

```dart
  @override
  void dispose() {
    _disposed = true;
    _suppressNextPositionChange = false;
    _completedSub?.cancel();
    player.dispose();
    super.dispose();
  }
```

- [ ] **Step 4：執行測試，確認通過**

Run: `flutter test test/reader/tts_controller_test.dart`
Expected: PASS（全檔案，含 Step 1 新增的三個測試與既有測試——確認 `handleExternalPositionChange()` 開頭新增的提早 return、以及四個既有「重設回 idle」位置＋`dispose()` 新增的旗標清除，不影響既有測試案例，因為既有測試從未呼叫過 `suppressNextExternalPositionChange()`，旗標恆為預設值 `false`）。

- [ ] **Step 5：Commit**

```bash
git add lib/reader/tts_controller.dart test/reader/tts_controller_test.dart
git commit -m "feat(epic-34): TtsController 新增 suppressNextExternalPositionChange()"
```

---

### Task 4：`reader_screen.dart` ＋ `library_screen.dart`——全線接線

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`（新增 `isEinkMode` 建構參數；`onHighlightSegment` 閉包傳入 `einkMode`；`FoliateReaderView(...)` 建構新增 `onTtsHighlightOutOfSafeWindow`）
- Modify: `app/lib/screens/library_screen.dart`（`_openBook()` 新增 `isEinkMode: widget.themeDependencies.isEinkMode,`）
- Test: `app/test/screens/reader_screen_test.dart`（於「同步高亮跟隨（epic-34-tts-readalong Issue 3）」group 之後、或既有 TTS 相關 group 附近新增）、`app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `FoliateReaderView.onTtsHighlightOutOfSafeWindow`/`showTtsHighlight(..., einkMode: ...)`、Task 3 的 `TtsController.suppressNextExternalPositionChange()`、既有 `LibraryThemeDependencies.isEinkMode`（`library_screen_dependencies.dart` 既有欄位）。
- Produces：`ReaderScreen.isEinkMode`（`bool`，預設 `false`），供 `library_screen.dart` 與測試注入。

- [ ] **Step 1：寫 `reader_screen_test.dart` 失敗測試**

在既有「手動導覽自動暫停與恢復播放（epic-34-tts-readalong Issue 4）」group（第 7570-7638 行）之後插入：

```dart
  group('安全視窗跟隨翻頁（epic-34-tts-readalong Issue 8）', () {
    // 誠實測試邊界（比照 Issue 4 既有慣例）：flutter_test 環境下
    // FoliateReaderView 的 _controller 恆為 null，main.js 端實際的幾何
    // 計算與 view.next()/prev() 呼叫無法在這層攔截斷言。這裡驗證的是
    // 「onTtsHighlightOutOfSafeWindow 觸發（模擬 main.js 回報超出安全
    // 視窗）這段 wiring 不崩潰」這個結構性保證；TtsController 抑制旗標
    // 的狀態機正確性由 tts_controller_test.dart（純 Dart，見 Task 3）
    // 完整涵蓋；main.js 端幾何判斷/方向邏輯由 foliate_reader_view_test.dart
    // 的 main.js regression guard（見 Task 1）涵蓋；真實幾何方向正確性
    // （尤其直排/橫排翻頁方向）須真機驗證（見本計畫「真機驗收清單」）。
    testWidgets(
        '提供 ttsProvider 時，onTtsHighlightOutOfSafeWindow 觸發（模擬 next/prev）不崩潰',
        (tester) async {
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts8_safe_window',
            prefsManager: prefsManager,
            isFixedLayout: false,
            ttsProvider: ttsProvider,
            isEinkMode: true,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView =
          tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const Key('reader_tts_play_pause_button')));
      await tester.pump();
      expect(tester.takeException(), isNull);

      foliateView.onTtsHighlightOutOfSafeWindow?.call('next');
      await tester.pump();
      expect(tester.takeException(), isNull);

      foliateView.onTtsHighlightOutOfSafeWindow?.call('prev');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('未提供 ttsProvider 時，onTtsHighlightOutOfSafeWindow 欄位為 null（未建構 TtsController）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts8_no_provider',
            prefsManager: prefsManager,
            isFixedLayout: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView =
          tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      // 未提供 ttsProvider 時 _ttsControllerOrNull 恆為 null，callback 內部
      // 呼叫 _ttsController?.suppressNextExternalPositionChange() 為 no-op，
      // 呼叫本身不應崩潰。
      foliateView.onTtsHighlightOutOfSafeWindow?.call('next');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

```

在 `library_screen_test.dart` 既有「LibraryScreen 點開一本書後，ReaderScreen 收到的 layoutPresetRepository／bookReaderPrefsRepository 正確貫穿」測試（第 2990-3028 行附近）之後插入：

```dart
  testWidgets(
      'LibraryScreen 點開一本書後，ReaderScreen 收到的 isEinkMode 與 themeDependencies.isEinkMode 一致',
      (tester) async {
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      filePath: 'content://example/1.txt',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          themeDependencies: LibraryThemeDependencies(isEinkMode: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.isEinkMode, isTrue,
        reason: 'LibraryScreen._openBook() 未把 themeDependencies.isEinkMode '
            '貫穿給 ReaderScreen，導致朗讀高亮在 E-Ink 模式下仍使用一般的'
            '半透明色，在低對比度螢幕上難以辨識。');
  });

```

- [ ] **Step 2：執行測試，確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart --plain-name "安全視窗跟隨翻頁"`
Run: `flutter test test/screens/library_screen_test.dart --plain-name "isEinkMode 與 themeDependencies"`
Expected: 兩者皆 FAIL——`ReaderScreen.isEinkMode`／`FoliateReaderView.onTtsHighlightOutOfSafeWindow` 皆不存在，編譯錯誤。

- [ ] **Step 3：`reader_screen.dart` 新增 `isEinkMode` 建構參數**

在既有 `final TtsAudioFocusSource? ttsAudioFocusSource;`（第 169 行）之後新增：

```dart
  /// E-Ink 高對比模式（epic-34-tts-readalong Issue 8）：App 層級主題設定
  /// （見 `main.dart`／`LibraryThemeDependencies.isEinkMode`），由
  /// [LibraryScreen._openBook] 貫穿傳入。目前唯一用途是朗讀高亮的視覺
  /// 呈現方式——[onHighlightSegment] 呼叫
  /// `FoliateReaderView.showTtsHighlight()` 時傳入的 `einkMode` 參數，
  /// E-Ink 模式下改用靜態高對比色，非既有半透明色。非 nullable，預設
  /// `false`：這是既有 App 層級設定值的直接貫穿，不是「未提供時功能不
  /// 啟用」的可選功能旗標（比照 [FoliateReaderView.isLandscape] 既有
  /// 非 nullable＋預設值模式）。
  final bool isEinkMode;
```

建構子參數列（`this.ttsAudioFocusSource,` 附近）新增：

```dart
    this.isEinkMode = false,
```

- [ ] **Step 4：`reader_screen.dart` 更新 `onHighlightSegment` 閉包**

第 2711-2721 行既有：

```dart
      onHighlightSegment: (segment) {
        if (segment == null) {
          FoliateReaderView.clearTtsHighlight(_foliateEpubReaderViewKey);
        } else {
          FoliateReaderView.showTtsHighlight(
            _foliateEpubReaderViewKey,
            segment.cfi,
            vertical: _resolved?.writingMode == WritingMode.vertical,
          );
        }
      },
```

改為：

```dart
      onHighlightSegment: (segment) {
        if (segment == null) {
          FoliateReaderView.clearTtsHighlight(_foliateEpubReaderViewKey);
        } else {
          FoliateReaderView.showTtsHighlight(
            _foliateEpubReaderViewKey,
            segment.cfi,
            vertical: _resolved?.writingMode == WritingMode.vertical,
            einkMode: widget.isEinkMode,
          );
        }
      },
```

- [ ] **Step 5：`reader_screen.dart` 的 `FoliateReaderView(...)` 建構新增 `onTtsHighlightOutOfSafeWindow`**

在 `_buildNativeView` 內既有 `onLocatorChanged: (info) { ... _ttsController?.handleExternalPositionChange(); },`（第 2822-2833 行）之後、`onSelectionChanged: _handleSelectionChanged,` 之前新增：

```dart
          onTtsHighlightOutOfSafeWindow: (direction) {
            // epic-34-tts-readalong Issue 8：main.js 偵測到目前朗讀高亮
            // 超出安全視窗時回報方向，這裡觸發一次性翻頁；呼叫前先讓
            // TtsController 抑制緊接著那一次 handleExternalPositionChange()
            // ——否則這次翻頁觸發的 onLocatorChanged 事件會被既有 Issue 4
            // 邏輯誤判為使用者手動導覽，錯誤暫停朗讀（見 tts_controller.dart
            // suppressNextExternalPositionChange() 文件註解）。
            _ttsController?.suppressNextExternalPositionChange();
            if (direction == 'prev') {
              FoliateReaderView.previousPage(_foliateEpubReaderViewKey);
            } else {
              FoliateReaderView.nextPage(_foliateEpubReaderViewKey);
            }
          },
```

- [ ] **Step 6：`library_screen.dart` 新增 `isEinkMode` 轉送**

第 471-473 行既有：

```dart
              ttsProvider: widget.readerFeatureRepositories.ttsProvider,
              ttsAudioHandler: widget.readerFeatureRepositories.ttsAudioHandler,
              ttsAudioFocusSource: widget.readerFeatureRepositories.ttsAudioFocusSource,
```

改為：

```dart
              ttsProvider: widget.readerFeatureRepositories.ttsProvider,
              ttsAudioHandler: widget.readerFeatureRepositories.ttsAudioHandler,
              ttsAudioFocusSource: widget.readerFeatureRepositories.ttsAudioFocusSource,
              isEinkMode: widget.themeDependencies.isEinkMode,
```

- [ ] **Step 7：執行測試，確認通過**

Run: `flutter test test/screens/reader_screen_test.dart`
Run: `flutter test test/screens/library_screen_test.dart`
Expected: 兩份測試檔皆 PASS（全檔案——`isEinkMode` 為新增非 nullable 參數但有預設值 `false`，不影響任何既有呼叫端）。

- [ ] **Step 8：跑一次全套 `flutter test`（本計畫最後一個 Task，依專案既有政策執行一次）**

Run: `flutter test`
Expected: PASS，測試總數較 Issue 7 合併時（1803+ 之後陸續累加）增加約 9 個（Task 1 四個＋Task 2 兩個＋Task 3 兩個＋Task 4 兩個，實際數字以執行結果為準）。

- [ ] **Step 9：`flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 10：Commit**

```bash
git add lib/screens/reader_screen.dart lib/screens/library_screen.dart test/screens/reader_screen_test.dart test/screens/library_screen_test.dart
git commit -m "feat(epic-34): ReaderScreen/LibraryScreen 接線安全視窗跟隨翻頁與 E-Ink 高對比高亮"
```

---

## 真機驗收清單（自動化測試涵蓋不到的部分，合併前須人工執行並記錄於對應 review 報告）

比照 `issues.md`「測試要求」與 Issue 7 既有先例，以下情境無法在 `flutter test`（無真實 WebView 幾何渲染）中驗證，須實機測試：

1. **橫排書籍，朗讀跨頁時自動翻頁**：播放朗讀直到目前句子接近頁尾（安全視窗上限之外），確認自動觸發一次性翻頁（非連續捲動、非重複觸發），翻頁後朗讀不中斷、高亮正確顯示在新頁——**須特別確認翻頁後緊接著的下一句（新頁頁首）不會被誤判翻回上一頁**（review-plan-issue-8.md Critical #1 修正的行為，見 Task 1 說明）。
2. **直排書籍，朗讀跨頁時自動翻頁**：同上，改用直排（vertical-RL）書籍驗證——**這是本計畫風險最高的一項**，`paginator.js` 的 CSS multi-column 對直排/橫排的分欄/分頁軸向設定互為相反（見 Task 1 Step 4 程式碼註解），若軸向推導有誤，直排書籍會朝錯誤方向連續翻頁或完全不翻頁；X／Y 兩軸皆檢查的設計已加了一層保險，但仍須實機確認方向正確。
3. **安全視窗範圍內不觸發不必要翻頁**：朗讀單一頁內連續多個句子（皆落在可視範圍中段），確認畫面不會無故翻頁/跳動。
4. **上一句/下一句（Issue 5）跨頁時同樣正確翻頁**：按「上一句」跳回上一頁的句子，確認觸發 `prev` 方向翻頁而非卡在原頁。
5. **E-Ink 高對比模式下朗讀高亮為靜態純色**：開啟 App 層級 E-Ink 模式，確認朗讀高亮改為高對比純黑（非既有半透明橙色），非 E-Ink 模式下維持既有外觀不變。
6. **背景恢復重新同步（Issue 7）＋安全視窗共同運作**：App 背景一段時間後前景恢復，若當下高亮位置剛好超出安全視窗，確認 `resyncHighlight()` 觸發的高亮重繪同樣正確觸發一次性翻頁（見本計畫「Architecture」段落，安全視窗檢查天然覆蓋這條路徑）。

---

## 測試策略總結（Self-Review 用，非額外步驟）

- **自動化層**：`main.js` 幾何判斷/方向邏輯/E-Ink 色彩選用（regression guard，Task 1）；`FoliateReaderView` 橋接欄位與 `showTtsHighlight` 簽章（Task 2）；`TtsController` 抑制旗標狀態機（純 Dart，Task 3，最高信賴度——完整涵蓋「抑制成功」與「抑制只作用一次」兩種情境）；`ReaderScreen`/`LibraryScreen` 接線結構性測試（Task 4，不崩潰＋依賴正確貫穿）。
- **無法自動化、須真機手動驗證的部分**：見上方「真機驗收清單」6 項，對應 `issues.md` Issue 8 驗收標準前三項（跨頁翻頁、安全視窗不誤觸發、E-Ink 靜態高對比）。

## Self-Review 檢查結果

- **Spec coverage**：`issues.md` Issue 8 驗收標準四項——(1) 跨頁超出安全視窗觸發一次性翻頁（不論 E-Ink）→ Task 1（JS 幾何＋事件，2026-08-28 依審查修正翻頁死循環）＋Task 2（橋接）＋Task 3（抑制旗標避免誤暫停，含旗標生命週期修正）＋Task 4（`ReaderScreen` 實際呼叫 `nextPage`/`previousPage`）；(2) 安全視窗範圍內不觸發不必要翻頁 → Task 1 的 `TTS_SAFE_WINDOW_MIN`/`MAX` 邊界判斷（`next` 用軟門檻，`prev` 用硬邊界，見「計畫修訂記錄」）；(3) E-Ink 高對比靜態顯示、非 E-Ink 維持既有 → Task 1 的 `einkMode` 色彩分流；(4) `flutter analyze`/`flutter test` 全數通過 → Task 4 Step 8-9。四項皆有對應 Task，無缺口。
- **Placeholder scan**：全文無 TBD／「待補」／「類似 Task N」等字樣，所有程式碼步驟皆為可直接套用的完整程式碼區塊。
- **Type consistency**：`onTtsHighlightOutOfSafeWindow` 型別 `ValueChanged<String>?` 在 Task 2（定義）與 Task 4（`_buildNativeView` 內 `(direction) { ... }` 閉包、`reader_screen_test.dart` 測試 `foliateView.onTtsHighlightOutOfSafeWindow?.call('next')`）皆一致；`showTtsHighlight` 新增的 `required bool einkMode` 具名參數在 Task 2（定義）與 Task 4（唯一呼叫端）皆一致；`suppressNextExternalPositionChange()` 無回傳值，Task 3（定義＋測試）與 Task 4（呼叫端）皆一致，命名貫穿全文無誤植；`needNext`/`needPrev`（main.js）與 `normX`/`normY` 變數命名於 Task 1 Step 1（測試斷言字串）與 Step 4（實作）逐字一致，已於本次修訂交叉核對。
- **審查回應完整性**（`reviews/review-plan-issue-8.md`）：Critical #1／Important #1（合併）、Important #2、Important #3 三項阻塞性問題皆已修訂並反映於對應 Task 的程式碼與測試；Minor 觀察兩項已於「計畫修訂記錄」記錄查證結果／已同步更新，無遺漏項目。
