# Epic 27 Issue 10 — 流式 EPUB 選字選不到、選完後選取常常消失 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `main.js` 加入「選取收尾保護期（Selection Release Guard）」：選取剛被判定為非折疊（真的選到文字）之後的極短時間內，若又收到一次 `click`，主動 `preventDefault()` 擋掉瀏覽器對「點擊文字」的預設動作（把點擊處設為新插入點、連帶折疊既有選取），避免使用者放開手指前的收尾雜訊被誤判為「點擊選取範圍以外的地方」而清空辛苦選好的文字範圍。

**Architecture:** 根因與修法皆已由真機 log（`bugfix-repro.md`「Issue 10」）與人工分析（`issue-10-11-12-analysis.md`「Issue 10」）確認：`main.js` 對選取的處理純粹被動監聽瀏覽器原生 `selectionchange`／`contextmenu`／`pointercancel` 事件（`main.js:661-700`），選取本身的建立/折疊時機完全由瀏覽器/WebView 原生手勢辨識決定，本 App 不能也不需要重新實作選字邏輯；但既有的 `doc.addEventListener('click', ...)`（`main.js:838-846`）監聽器已經在同一個時間點觀察「這次觸控是不是一次快速點擊」（用於攔截畫線點擊誤觸換頁的既有機制，`ANNOTATION_CLICK_TAP_MAX_MS`），是唯一天然攔得到這個收尾 click、且不需要新增額外事件監聽器的位置。修法只需在這個既有監聽器內，多記錄一個「選取上一次被判定為非折疊的時間點」並多比對一次時間差，屬於同一整合層（`main.js`）內的最小擴充，不修改任何 vendored 檔案（ADR 0011），Dart 端無需任何改動——若瀏覽器沒有真的執行「折疊選取」這個預設動作，`selectionchange` 就不會觸發，`onSelectionCleared` 自然也就不會被送到 Dart 端，不需要在 Dart 側另外攔截或補救。

**Tech Stack:** 純 JS（`main.js` 整合層），無新增依賴；驗證另用既有 Puppeteer 差分測試手法（`reviews/issue10-harness/`，Node.js 一次性診斷腳本，非 `flutter test`／CI 範圍）。

**Spec:** `docs/epics/epic-27-reader-device-compat/issues.md`「Issue 10」、`docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md`「Issue 10」（真機 log 逐行證據，含 `t=27763~47607ms` 那段「選取長大到 47 字→緊接著 native click（`elapsedSinceTouchStart=0`）→選取清空」的具體重現序列）、`docs/epics/epic-27-reader-device-compat/reviews/issue-10-11-12-analysis.md`「Issue 10」（機制分析與建議解法方向：選取收尾保護期）。

## 立案依據說明（回應 `issues.md` 現行文字與本計畫的落差）

`issues.md` 目前 Issue 10 的 `Status` 欄寫的是 `needs-info`，且明文要求「需要在同一台裝置裝『Issue 9 之前』的版本做真機對照才能定案」，理由是排除「選取消失是不是 Issue 9 造成的迴歸」。這個真機跨版本對照到撰寫本計畫為止**仍未實際執行**。

本計畫改為採用 `issue-10-11-12-analysis.md`（已定案分析報告，2026-08-24）的結論——該報告改用**自動化 Puppeteer 差分測試**（在同一組合成觸控序列下比對 `main.base.js`〔Issue 9 之前〕與 `main.fixed.js`〔Issue 9 之後〕兩個版本的選取維持行為）取代真機跨版本對照，結果顯示兩版本行為完全一致（見 `bugfix-repro.md`「Phase 3」：「選取『已經存在之後』被小幅拖曳＋放開，不受 `no-swipe` 影響（兩版本一致，都不會消失）」），據此判定選取消失**不是 Issue 9 造成的迴歸**，而是既有的瀏覽器「點擊即折疊選取」預設行為。此結論與使用者已確認的關鍵事實（選取消失後畫面上幾乎不留下任何實際標記，排除「其實已成功畫線」的替代解釋）一致。

此立案依據已與人類確認採用（優先於 `issues.md` 原文的真機對照要求），本計畫據此直接進入實作；`issues.md` 將於本計畫收尾時同步更新 Status 與根因/解法段落，反映本次採用的證據與結論。

## Global Constraints

- 只修改 `app/android/app/src/main/assets/foliate/main.js`（整合層）與 `app/test/reader/foliate_reader_view_test.dart`（新增靜態內容回歸測試）兩個會進版控的檔案。
- 不修改 `paginator.js`／`view.js`／`epub.js`（vendored，ADR 0011）；不修改任何 Dart 端選取處理邏輯（`foliate_reader_view.dart`／`reader_screen.dart`）——見上方 Architecture 段落說明理由。
- `docs/epics/epic-27-reader-device-compat/reviews/issue10-harness/verify-issue10-guard.mjs`（Task 1 Step 6 新增）是驗證用 Node.js 腳本，存放於 gitignored 的 `reviews/` 目錄，不隨 commit 進版控，僅作為本次驗證過程的留存證據（比照 `repro-issue10.mjs` 既有先例）。
- 每個 Task 完成後跑 `flutter analyze`，維持乾淨。

---

### Task 1：`main.js` 新增選取收尾保護期（Selection Release Guard）

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`（約第 653-685 行 `reportSelection` 閉包、約第 838-846 行既有 `click` 監聽器）
- Test: `app/test/reader/foliate_reader_view_test.dart`（新增 group，緊接既有「main.js no-swipe 屬性 regression guard（Epic 27 Issue 9）」group 之後，約第 1223 行之後）
- Create（不進版控）: `docs/epics/epic-27-reader-device-compat/reviews/issue10-harness/verify-issue10-guard.mjs`

**Interfaces:**
- Consumes: 無新增——沿用 `main.js` 既有的 `doc.getSelection()`／`performance.now()`／`evt.timeStamp`（`Event.timeStamp` 與 `performance.now()` 為同一時間原點的 `DOMHighResTimeStamp`，可直接相減比較，既有程式碼於第 843 行已用同一手法比較兩個不同事件的 `timeStamp`）。
- Produces: 無新增公開介面——本次改動完全封裝在 `main.js` 的 `openBook()` 函式內部閉包變數（`SELECTION_RELEASE_GUARD_MS`／`lastNonCollapsedSelectionAtMs`），不影響任何外部呼叫端（Dart 端／其他 JS 模組）看到的行為契約。

- [x] **Step 1：寫失敗的 Dart 靜態內容回歸測試——斷言 `main.js` 含有新的保護期常數、選取時間戳記記錄，且 `evt.preventDefault()` 出現在 `click` 監聽器內、位置早於既有的 700ms 快速點擊判斷**

在 `app/test/reader/foliate_reader_view_test.dart` 第 1223 行（既有 `main.js no-swipe 屬性 regression guard` group 的結尾 `});` 之後）新增：

```dart
  group('main.js 選取收尾保護期（Selection Release Guard）regression guard'
      '（Epic 27 Issue 10）', () {
    late String mainJsSource;

    setUpAll(() {
      mainJsSource = File('android/app/src/main/assets/foliate/main.js')
          .readAsStringSync();
    });

    test('reportSelection 內，選取非折疊時記錄時間戳記，且位置早於取得 range',
        () {
      const rangeCall = 'const range = selection.getRangeAt(0)';
      const timestampCall = 'lastNonCollapsedSelectionAtMs = performance.now()';

      final rangeIndex = mainJsSource.indexOf(rangeCall);
      final timestampIndex = mainJsSource.indexOf(timestampCall);

      expect(rangeIndex, greaterThanOrEqualTo(0),
          reason: 'main.js 內找不到 "$rangeCall"——若上游改了寫法，'
              '下面的順序斷言也需要一併更新。');
      expect(timestampIndex, greaterThanOrEqualTo(0),
          reason: 'main.js 內找不到 "$timestampCall"——這一行負責記錄'
              '「選取上一次被判定為非折疊」的時間點，供 click 監聽器內的'
              '選取收尾保護期判斷使用（見 '
              'docs/epics/epic-27-reader-device-compat/reviews/'
              'bugfix-repro.md「Issue 10」），若被刪掉，保護期機制會'
              '永遠判定為「無最近選取」而完全失效。');
      expect(timestampIndex, lessThan(rangeIndex),
          reason: '"$timestampCall" 必須早於 "$rangeCall"——保護期記錄的'
              '是「選取剛被判定為非折疊」這個時間點本身，應緊接在 '
              'isCollapsed 判斷之後、取得 range 之前，避免遺漏。');
    });

    // 若真機使用後回報需要調整門檻值（比照 epic-25 Issue 1／epic-26
    // Issue 3／本 Epic Issue 12 先例），下面 guardConstant 這行字串比對
    // 需要與 main.js 實際數值同步更新，否則測試會誤判失敗（見
    // review-plan-issue-10.md Minor 2）。
    test('click 監聽器內，選取收尾保護期的 preventDefault() 早於既有 700ms '
        '快速點擊判斷、且門檻值為 150ms', () {
      const guardConstant = 'const SELECTION_RELEASE_GUARD_MS = 150';
      const clickListenerStart = "doc.addEventListener('click', (evt) => {";
      const startTimeNullReturn = 'if (startTime === null) return';

      final guardConstantIndex = mainJsSource.indexOf(guardConstant);
      final clickListenerIndex = mainJsSource.indexOf(clickListenerStart);

      expect(guardConstantIndex, greaterThanOrEqualTo(0),
          reason: 'main.js 內找不到 "$guardConstant"——選取收尾保護期的'
              '門檻值（真機證據見 bugfix-repro.md「Issue 10」，起始值'
              '150ms，理由見 plan-issue-10.md 設計決策段落）遺失或被改名。');
      expect(clickListenerIndex, greaterThanOrEqualTo(0),
          reason: 'main.js 內找不到既有的 click 監聽器註冊 '
              '"$clickListenerStart"——若上游改了寫法，下面的順序斷言'
              '也需要一併更新。');

      final preventDefaultIndex =
          mainJsSource.indexOf('evt.preventDefault()', clickListenerIndex);
      final startTimeNullReturnIndex =
          mainJsSource.indexOf(startTimeNullReturn, clickListenerIndex);

      expect(preventDefaultIndex, greaterThanOrEqualTo(0),
          reason: 'click 監聽器內找不到 "evt.preventDefault()"——選取收尾'
              '保護期未攔截瀏覽器對點擊的預設動作，選取仍會被瀏覽器'
              '折疊，症狀（選字選完後常常消失）不會被修復。');
      expect(startTimeNullReturnIndex, greaterThanOrEqualTo(0),
          reason: 'click 監聽器內找不到既有的 "$startTimeNullReturn"——'
              '若上游改了寫法，下面的順序斷言也需要一併更新。');
      expect(preventDefaultIndex, lessThan(startTimeNullReturnIndex),
          reason: '選取收尾保護期的判斷必須獨立於既有 700ms 快速點擊'
              '判斷之前執行——後者在 startTime 為 null（非觸控手勢產生的 '
              'click，例如滑鼠）時會提早 return，若保護期判斷寫在它之後，'
              '滑鼠點擊等非觸控情境會意外跳過保護期判斷。');
    });
  });
```

- [x] **Step 2：執行測試確認失敗**

Run: `cd app && flutter test test/reader/foliate_reader_view_test.dart`
Expected: 新增的 2 則測試 FAIL（`main.js` 內尚未有 `SELECTION_RELEASE_GUARD_MS`／`lastNonCollapsedSelectionAtMs`／新的 `evt.preventDefault()`），既有測試維持通過。

- [x] **Step 3：實作選取收尾保護期**

在 `app/android/app/src/main/assets/foliate/main.js` 第 653 行（`const index = e.detail.index`）之後、第 661 行（`const reportSelection = async () => {`）之前，插入：

```js
      // 選取收尾保護期（Selection Release Guard，
      // epic-27-reader-device-compat Issue 10）：見下方 click 監聽器內
      // 完整說明。這裡只負責記錄「選取上一次被判定為非折疊（真的有選到
      // 文字）」的時間點，供該監聽器判斷這次 click 是否可能是選字收尾
      // 動作本身觸發的雜訊。真機 log 佐證見
      // docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md
      // 「Issue 10」；門檻值 150ms 取自
      // issue-10-11-12-analysis.md「Issue 10」建議解法方向的區間
      // （100～150ms）上緣，尚未經真機校準，比照 epic-25 Issue 1／
      // epic-26 Issue 3 先例，後續若真機回報需要調整，另立工單處理。
      const SELECTION_RELEASE_GUARD_MS = 150
      let lastNonCollapsedSelectionAtMs = null
```

將既有的 `reportSelection` 內容（第 661-683 行）：

```js
      const reportSelection = async () => {
        const selection = doc.getSelection()
        if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
          window.flutter_inappwebview.callHandler('onSelectionCleared')
          return
        }
        const range = selection.getRangeAt(0)
```

改為（僅在 `isCollapsed` 判斷之後、取得 `range` 之前插入一行）：

```js
      const reportSelection = async () => {
        const selection = doc.getSelection()
        if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
          // 選取已折疊/不存在，主動清空保護期時間戳記——語意上明確表達
          // 「目前沒有活動中選取」，不依賴「時間窗口自然過期」這個間接
          // 效果（兩者結果相同，但顯式重置多一層防呆，避免極端情況下的
          // 時鐘回撥或測試環境 mock 殘留造成誤判，見
          // review-plan-issue-10.md Minor 1）。
          lastNonCollapsedSelectionAtMs = null
          window.flutter_inappwebview.callHandler('onSelectionCleared')
          return
        }
        lastNonCollapsedSelectionAtMs = performance.now()
        const range = selection.getRangeAt(0)
```

將既有的 `click` 監聽器（第 838-846 行）：

```js
      doc.addEventListener('click', (evt) => {
        const startTime = annotationClickTouchStartTime
        annotationClickTouchStartTime = null
        if (startTime === null) return // 非觸控手勢產生的 click（例如滑鼠），不受影響
        if (evt.target.closest('a[href]')) return // 超連結點擊一律放行
        if (evt.timeStamp - startTime <= ANNOTATION_CLICK_TAP_MAX_MS) {
          evt.stopImmediatePropagation()
        }
      }, { capture: true })
```

改為：

```js
      doc.addEventListener('click', (evt) => {
        const startTime = annotationClickTouchStartTime
        annotationClickTouchStartTime = null

        // 選取收尾保護期（epic-27-reader-device-compat Issue 10）：使用者
        // 放開手指前的最後一個小動作，若被瀏覽器判讀成「點擊」而非「拖曳
        // 延伸的收尾」，瀏覽器對點擊文字的預設動作會把點擊處設為新的
        // 插入點、連帶折疊既有選取——這與下面既有的 700ms 快速點擊判斷是
        // 兩件不同的事（那段判斷的目的是攔截「畫線點擊誤觸換頁」，用
        // stopImmediatePropagation() 擋掉事件冒泡到畫線點擊監聽器，並不會
        // 阻止瀏覽器這個預設動作，兩者需要各自獨立處理）。若選取上一次被
        // 判定為非折疊的時間點在 SELECTION_RELEASE_GUARD_MS 之內，代表這
        // 次 click 很可能就是使用者放開手指那個動作本身觸發的收尾雜訊，
        // 非使用者刻意點擊別處要取消選取，主動 preventDefault() 保留選取；
        // 超過門檻則視為使用者確實想點別的地方，正常放行讓瀏覽器折疊
        // 選取。真機重現序列見
        // docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md
        // 「Issue 10」，建議解法方向見同目錄
        // issue-10-11-12-analysis.md「Issue 10」。
        if (
          !evt.target.closest('a[href]') &&
          lastNonCollapsedSelectionAtMs !== null &&
          evt.timeStamp - lastNonCollapsedSelectionAtMs <= SELECTION_RELEASE_GUARD_MS
        ) {
          evt.preventDefault()
        }

        if (startTime === null) return // 非觸控手勢產生的 click（例如滑鼠），不受影響
        if (evt.target.closest('a[href]')) return // 超連結點擊一律放行
        if (evt.timeStamp - startTime <= ANNOTATION_CLICK_TAP_MAX_MS) {
          evt.stopImmediatePropagation()
        }
      }, { capture: true })
```

- [x] **Step 4：執行測試確認通過**

Run: `cd app && flutter test test/reader/foliate_reader_view_test.dart`
Expected: 全數 PASS，含 Step 1 新增的 2 則測試。

- [x] **Step 5：執行完整分析與全專案測試，確認零回歸**

Run: `cd app && flutter analyze && flutter test`
Expected: `flutter analyze` 顯示 "No issues found!"；`flutter test` 全數通過（本次改動未觸及任何 Dart 程式碼，理論上不影響既有測試數量，僅新增本計畫的 2 則）。

- [x] **Step 6：建立 Puppeteer 行為驗證腳本，人工確認選取收尾保護期實際運作正確**

Step 1、5 的測試只能靜態確認 `main.js` 的原始碼內容與位置關係，無法真正執行 JS 驗證行為是否正確（`flutter test` 不執行 JS）。比照本 Epic Issue 10 診斷階段已建立的 Puppeteer 差分測試手法（`reviews/issue10-harness/repro-issue10.mjs`），另建立一支聚焦驗證本次修法的腳本，用直接建構＋派發 `click` 事件（非 CDP 觸控合成）繞開已查證的環境限制（headless Chromium 無法從 touchstart/touchend 合成原生 click，見 `repro-issue10.mjs` 檔頭說明；直接 `dispatchEvent(new MouseEvent('click', ...))` 不受此限制，因為不需要瀏覽器自己合成，是測試腳本自己建構的事件）。

建立 `docs/epics/epic-27-reader-device-compat/reviews/issue10-harness/verify-issue10-guard.mjs`：

```js
// 驗證選取收尾保護期（Selection Release Guard，
// epic-27-reader-device-compat Issue 10）：選取剛建立成功後，
// SELECTION_RELEASE_GUARD_MS（150ms）之內收到的 click 應被
// evt.preventDefault() 擋下、選取維持非折疊；超過門檻後的 click 應正常
// 放行、選取如常被瀏覽器折疊。直接建構並派發 click 事件（非 CDP 觸控
// 合成），繞開 repro-issue10.mjs 檔頭記錄的 headless Chromium 限制。

import puppeteer from 'puppeteer'
import { readFile, readdir } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const FOLIATE_DIR = path.resolve(
  __dirname,
  '../../../../../app/android/app/src/main/assets/foliate',
)
const FIXTURE_EPUB = path.resolve(
  __dirname,
  '../../../../../app/test/fixtures/sample_horizontal.epub',
)
const ORIGIN = 'https://appassets.androidplatform.net'
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' }

async function listFilesRecursive(dir, base = dir) {
  const entries = await readdir(dir, { withFileTypes: true })
  const files = []
  for (const entry of entries) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) files.push(...(await listFilesRecursive(full, base)))
    else files.push(path.relative(base, full).split(path.sep).join('/'))
  }
  return files
}

async function withPage(fixtureBuf, run) {
  const relFiles = await listFilesRecursive(FOLIATE_DIR)
  const fileMap = new Map()
  for (const rel of relFiles) {
    fileMap.set(rel, await readFile(path.join(FOLIATE_DIR, rel)))
  }

  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] })
  try {
    const page = await browser.newPage()
    await page.setRequestInterception(true)
    page.on('request', (req) => {
      const url = new URL(req.url())
      if (url.origin !== ORIGIN) { req.continue(); return }
      if (url.pathname === '/book/current.epub') {
        req.respond({ status: 200, contentType: 'application/epub+zip', body: fixtureBuf })
        return
      }
      const pathname = url.pathname === '/' ? '/index.html' : url.pathname
      const rel = pathname.replace(/^\//, '')
      const buf = fileMap.get(rel)
      if (!buf) { req.respond({ status: 404, body: '' }); return }
      const ext = path.extname(rel)
      req.respond({ status: 200, contentType: MIME[ext] || 'application/octet-stream', body: buf })
    })
    page.on('pageerror', (err) => console.error('[pageerror]', err))

    await page.evaluateOnNewDocument(() => {
      window.__harnessEvents = []
      window.flutter_inappwebview = {
        callHandler: async (name, ...args) => {
          window.__harnessEvents.push({ name, args, t: performance.now() })
        },
      }
    })

    const initialPrefs = {
      writingMode: 'horizontal', fontSize: 1.0, lineHeight: 1.0,
      paragraphSpacing: 1.0, marginTop: 32, marginBottom: 16,
      marginLeft: 24, marginRight: 24,
      pageTurnMode: 'paginated', columnMode: 'auto', columnSize: 720,
    }
    const openUrl =
      `${ORIGIN}/index.html?prefs=${encodeURIComponent(JSON.stringify(initialPrefs))}` +
      `&fontFaceCss=&initialCfi=`
    await page.setViewport({ width: 800, height: 1200, hasTouch: true })
    await page.goto(openUrl, { waitUntil: 'load' })
    await page.waitForFunction(
      () => window.__harnessEvents.some((e) => e.name === 'onPageRendered'),
      { timeout: 15000 },
    )
    await page.waitForFunction(() => {
      const renderer = document.querySelector('foliate-view')?.renderer
      const container = renderer?.shadowRoot?.getElementById('container')
      for (const iframe of container?.querySelectorAll('iframe') ?? []) {
        const text = iframe.contentDocument?.body?.textContent?.trim() ?? ''
        if (text.length > 40) return true
      }
      return false
    }, { timeout: 10000 })

    return await run(page)
  } finally {
    await browser.close()
  }
}

async function runScenario(page, { waitBeforeClickMs }) {
  await page.evaluate(() => { window.__harnessEvents.length = 0 })

  // 直接用 Range/addRange 建立一段選取（模擬長按選字已完成——headless
  // Chromium 無法重現原生長按選字本身，見 repro-issue10.mjs 檔頭說明，
  // 只驗證「選取已存在後，收到 click 時的保護期行為」這一段）。
  await page.evaluate(() => {
    const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
    const doc = container?.querySelector('iframe')?.contentDocument
    const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
    let node = null
    while (walker.nextNode()) {
      if ((walker.currentNode.nodeValue || '').trim().length > 20) { node = walker.currentNode; break }
    }
    const sel = doc.getSelection()
    sel.removeAllRanges()
    const range = doc.createRange()
    range.setStart(node, 0)
    range.setEnd(node, 8)
    sel.addRange(range)
  })

  await page.waitForFunction(
    () => window.__harnessEvents.some((e) => e.name === 'onSelectionChanged'),
    { timeout: 5000 },
  )

  await new Promise((r) => setTimeout(r, waitBeforeClickMs))

  return page.evaluate(() => {
    const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
    const doc = container?.querySelector('iframe')?.contentDocument
    const evt = new MouseEvent('click', { bubbles: true, cancelable: true })
    doc.body.dispatchEvent(evt)
    const sel = doc.getSelection()
    return {
      defaultPrevented: evt.defaultPrevented,
      selectionCollapsedAfterClick: sel.isCollapsed,
    }
  })
}

async function main() {
  const fixtureBuf = await readFile(FIXTURE_EPUB)
  const withinGuard = await withPage(fixtureBuf, (page) => runScenario(page, { waitBeforeClickMs: 20 }))
  const afterGuard = await withPage(fixtureBuf, (page) => runScenario(page, { waitBeforeClickMs: 250 }))
  const result = { withinGuard, afterGuard }
  console.log(JSON.stringify(result, null, 2))

  let ok = true
  if (!withinGuard.defaultPrevented || withinGuard.selectionCollapsedAfterClick) {
    console.error('FAIL：保護期窗口內（20ms）的 click 應被 preventDefault()、選取應維持非折疊')
    ok = false
  }
  if (afterGuard.defaultPrevented || !afterGuard.selectionCollapsedAfterClick) {
    console.error('FAIL：超過保護期門檻（250ms > 150ms）的 click 不應被攔截、選取應正常被折疊')
    ok = false
  }
  if (ok) console.log('PASS：選取收尾保護期行為符合預期。')
  process.exitCode = ok ? 0 : 1
}

main().catch((err) => {
  console.error(err)
  process.exitCode = 2
})
```

Run: `cd docs/epics/epic-27-reader-device-compat/reviews/issue10-harness && node verify-issue10-guard.mjs`
Expected: 輸出 `withinGuard.defaultPrevented === true`、`withinGuard.selectionCollapsedAfterClick === false`；`afterGuard.defaultPrevented === false`、`afterGuard.selectionCollapsedAfterClick === true`；最終印出 `PASS`。

- [x] **Step 7：Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js app/test/reader/foliate_reader_view_test.dart
git commit -m "fix(epic-27): Issue 10——main.js 新增選取收尾保護期，避免選字放開瞬間被誤判為點擊而清空選取"
```

（`verify-issue10-guard.mjs` 位於 gitignored 的 `reviews/` 目錄，不納入本次 commit。）

---

## 完成後的驗證（對照 `issues.md` Issue 10 驗收標準，本計畫執行後應同步更新該工單）

- [x] `flutter analyze`：全專案 "No issues found!"
- [x] `flutter test`：全專案通過，零回歸
- [x] Puppeteer 行為驗證腳本（Task 1 Step 6）輸出 `PASS`
- [ ] （建議，非本計畫強制自動化）真機（比照本 Epic 既有先例，於曾經回報過本問題的裝置）驗證：反覆長按選字/拖曳劃線並放開手指，確認選取不再於放開瞬間無故消失；同時確認使用者刻意點擊選取範圍以外的地方，選取仍能正常被取消（保護期未過度攔截正常操作）。
- [ ] 150ms 這個門檻值若真機使用後回報有需要調整（例如仍偶發消失、或誤傷「選完立刻想點別處」的正常操作），比照 `epic-25` Issue 1／`epic-26` Issue 3／本 Epic Issue 12 先例，另立後續工單處理，不阻塞本計畫驗收。
- [x] 本計畫完成後，同步更新 `docs/epics/epic-27-reader-device-compat/issues.md`「Issue 10」的 `Status`（`needs-info` → 完成後之對應狀態）與根因/解法段落，反映本次採用 Puppeteer 差分測試結論（而非真機跨版本對照）立案的事實，不覆蓋掉原文的診斷歷程記錄。
