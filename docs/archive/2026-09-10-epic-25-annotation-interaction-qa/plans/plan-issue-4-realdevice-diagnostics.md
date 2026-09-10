# Epic 25 Issue 4 — 換頁點擊位置與相鄰頁畫線重疊時誤跳出刪除確認對話框 真機診斷插樁計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 這**不是**修復計畫——`plan-issue-4.md`（headless CDP 時序驗證迴圈）已執行完畢，20 次量測 0 次重現，`issues.md` Issue 4 目前狀態是 `needs-info`：headless 環境本身無法確認/否證根因假說是否適用於真機。本計畫比照 Epic 25 Issue 1 的診斷插樁手法，在 `main.js`（JS 端）與 `reader_screen.dart`（Dart 端）加入暫時性除錯插樁，讓使用者能透過既有「閱讀器 Console Log」診斷畫面（不需 USB/ADB 連線）在真機上量測「nav-zone 熱區點擊觸發換頁」與「瀏覽器對同一次觸控合成的原生 `click` 事件」之間的真實時序，藉此區辨 `plan-issue-4.md` 留下的兩個未區辨可能性（真機 Flutter 橋接延遲確實比 headless 更長／headless 觸控合成時序與真機有實質差異）。拿到真機資料後，下一輪才依實測結果定案修法方向。

**Architecture:** JS 端在 `main.js` 既有的 `window.nextPage`/`window.previousPage`（呼叫入口）、`view.addEventListener('load', ...)` hook 內（純觀察用 `touchend`/`click` capture 監聽器）、`view.addEventListener('show-annotation', ...)` handler（誤觸發偵測點）三處插入 `console.log('[DEBUG-e25i4] ...')`，透過既有 `InAppWebView.onConsoleMessage` → `ReaderConsoleLog` 管線自動出現在診斷畫面。Dart 端在 `reader_screen.dart` 的 `_handleZoneAction()`（nav-zone 熱區點擊的統一分派點）呼叫 `ReaderConsoleLog.add(...)` 直接寫入同一份日誌。JS 端用 `Date.now()`（epoch ms）、Dart 端用 `DateTime.now().millisecondsSinceEpoch`（同為 epoch ms）——兩者可直接相減比較，跨 Dart/JS 邊界的時序落差因此可由人工比對日誌算出，不需要額外的跨時鐘同步機制。

**Tech Stack:** `main.js`（本專案自有整合層，非 vendored，ADR 0011 允許修改）＋ Flutter/Dart（`reader_screen.dart`）＋既有 `ReaderConsoleLog`（epic-18-reader-device-qa Issue 33 已建置，零 ADB 診斷管線）。

## Global Constraints

- 完全不修改任何 vendored 檔案（`paginator.js`／`view.js`／`epub.js` 等）——只在 `main.js` 既有整合層與 Dart 端新增程式碼（ADR 0011）。
- 新增的插樁監聽器**必須是純觀察**：`main.js` 新增的 `touchend`/`click` 監聽器不得呼叫 `evt.preventDefault()`／`evt.stopPropagation()`／`evt.stopImmediatePropagation()`，也不得修改任何 DOM/選取狀態——目的是觀察既有行為（含 bug 本身），不能因插樁本身改變症狀是否出現。
- 插樁訊息一律用唯一標籤 `[DEBUG-e25i4]` 開頭（比照 `/diagnose` 技能 Phase 4「Tag every debug log with a unique prefix」慣例、比照 Issue 1 `[DEBUG-e25i1]` 既有先例），方便日後用 `grep -rn "DEBUG-e25i4"` 一次性清除。
- JS 端統一用 `Date.now()`（epoch 毫秒，非 `performance.now()`）、Dart 端統一用 `DateTime.now().millisecondsSinceEpoch`——兩者基準相同（真實世界時鐘），才能讓人工比對兩份日誌時直接相減得出跨 Dart/JS 邊界的實際延遲；若混用 `performance.now()`（頁面載入起算的單調時鐘）會導致無法跨邊界比較。
- 本計畫**不會**移除插樁——插樁的移除必須排在「已取得真機資料、鎖定根因」之後的下一輪計畫，比照 Issue 1 `plan-issue-1.md` 既有先例。
- 本計畫的分支/worktree 建立、真機資料回報後的下一輪根因確認與修復計畫撰寫，皆不在本計畫範圍內。

---

### Task 1：`main.js` 新增 JS 端除錯插樁，headless 驗證插樁本身正確輸出且不影響既有行為

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js:333-339`（`window.nextPage`／`window.previousPage` 呼叫入口）、`:598-601`（`show-annotation` handler）、`:662` 之後（`load` hook 內新增純觀察 `touchend`/`click` 監聽器）

**Interfaces:**
- Consumes：既有 `view.next()`／`view.prev()`／`decorationIdByCfi`（`main.js` 模組級變數）／既有 `view.addEventListener('load', ...)` hook 內已建立的 `doc`／`index` 閉包變數（`main.js:614-615`）。
- Produces：無新增可供其他 Task 呼叫的函式——本插樁純觀察用，Task 2（Dart 端插樁）與本 Task 各自獨立新增，僅共用 `[DEBUG-e25i4]` 標籤與 epoch-ms 時間格式慣例。

- [x] **Step 1：`window.nextPage`／`window.previousPage` 新增呼叫時間戳插樁**

修改 `app/android/app/src/main/assets/foliate/main.js:333-339`：

```javascript
window.nextPage = function () {
  console.log(`[DEBUG-e25i4] window.nextPage() called t=${Date.now()}`)
  view.next()
}

window.previousPage = function () {
  console.log(`[DEBUG-e25i4] window.previousPage() called t=${Date.now()}`)
  view.prev()
}
```

- [x] **Step 2：`show-annotation` handler 新增誤觸發偵測插樁**

修改 `app/android/app/src/main/assets/foliate/main.js:598-601`：

```javascript
    view.addEventListener('show-annotation', (e) => {
      const id = decorationIdByCfi.get(e.detail.value)
      console.log(`[DEBUG-e25i4] show-annotation t=${Date.now()} value=${e.detail.value} id=${id ?? 'null'}`)
      if (id) window.flutter_inappwebview.callHandler('onAnnotationActivated', id)
    })
```

- [x] **Step 3：`load` hook 內新增純觀察 `touchend`/`click` 監聽器**

修改 `app/android/app/src/main/assets/foliate/main.js`，在 `doc.addEventListener('pointercancel', () => reportSelection())`（第 662 行）之後插入：

```javascript
      doc.addEventListener('pointercancel', () => reportSelection())

      // Epic 25 Issue 4 暫時性除錯插樁 [DEBUG-e25i4]：純觀察用 capture
      // 階段 touchend/click 監聽器，量測「點擊換頁」觸發的
      // window.nextPage() 呼叫與瀏覽器對同一次觸控合成的原生 click 事件
      // 之間的真機時序（headless CDP 驗證已排除但無法確認，見
      // docs/epics/epic-25-annotation-interaction-qa/issues.md Issue 4／
      // plan-issue-4-realdevice-diagnostics.md）。不呼叫
      // preventDefault()/stopPropagation()，不修改任何 DOM/選取狀態，
      // 不影響既有行為——目的是觀察症狀本身。確認根因、產出修復計劃後
      // 需整段移除。
      doc.addEventListener('touchend', () => {
        console.log(`[DEBUG-e25i4] touchend t=${Date.now()}`)
      }, { capture: true })
      doc.addEventListener('click', (evt) => {
        console.log(`[DEBUG-e25i4] click t=${Date.now()} x=${evt.clientX.toFixed(1)} y=${evt.clientY.toFixed(1)}`)
      }, { capture: true })
```

（保留原本緊接在 `pointercancel` 監聽器之後的 Epic 18 Issue 47 修復程式碼區塊不動，新插樁插在兩者之間。）

- [x] **Step 4：語法檢查**

Run: `node --check app/android/app/src/main/assets/foliate/main.js`
Expected: 無輸出、exit code 0。

- [x] **Step 5：headless 視訊/視覺驗證（Puppeteer 通路測試）**

Run（於任一具備 Puppeteer 安裝的 harness 目錄下，例如 `tmp/epic-25-issue-4-harness/`，重用其既有 `node_modules`）：
```bash
node -e "
import('puppeteer').then(async ({default: puppeteer}) => {
  const { readFile, readdir } = await import('node:fs/promises');
  const path = await import('node:path');
  const FOLIATE_DIR = path.resolve('../../app/android/app/src/main/assets/foliate');
  const FIXTURE_EPUB = path.resolve('../../app/test/fixtures/sample_long_chinese_vertical.epub');
  const ORIGIN = 'https://appassets.androidplatform.net';
  const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' };
  async function listFilesRecursive(dir, base = dir) {
    const entries = await readdir(dir, { withFileTypes: true });
    const files = [];
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) files.push(...(await listFilesRecursive(full, base)));
      else files.push(path.relative(base, full).split(path.sep).join('/'));
    }
    return files;
  }
  const relFiles = await listFilesRecursive(FOLIATE_DIR);
  const fileMap = new Map();
  for (const rel of relFiles) fileMap.set(rel, await readFile(path.join(FOLIATE_DIR, rel)));
  const fixtureBuf = await readFile(FIXTURE_EPUB);
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
  const page = await browser.newPage();
  await page.setRequestInterception(true);
  page.on('request', (req) => {
    const url = new URL(req.url());
    if (url.origin !== ORIGIN) { req.continue(); return; }
    if (url.pathname === '/book/current.epub') { req.respond({ status: 200, contentType: 'application/epub+zip', body: fixtureBuf }); return; }
    const pathname = url.pathname === '/' ? '/index.html' : url.pathname;
    const rel = pathname.replace(/^\//, '');
    const buf = fileMap.get(rel);
    if (!buf) { req.respond({ status: 404, body: '' }); return; }
    const ext = path.extname(rel);
    req.respond({ status: 200, contentType: MIME[ext] || 'application/octet-stream', body: buf });
  });
  page.on('console', m => { if (m.text().includes('DEBUG-e25i4')) console.log('CONSOLE:', m.text()); });
  page.on('pageerror', e => console.log('PAGEERROR:', e));
  await page.evaluateOnNewDocument(() => {
    window.__harnessEvents = [];
    window.flutter_inappwebview = { callHandler: async (name, ...args) => { window.__harnessEvents.push({name,args}); } };
  });
  const initialPrefs = { writingMode: 'vertical', fontSize: 1.0, lineHeight: 1.0, paragraphSpacing: 1.0, marginTop: 32, marginBottom: 16, marginLeft: 24, marginRight: 24, pageTurnMode: 'paginated', columnMode: 'auto', columnSize: 720 };
  const openUrl = ORIGIN + '/index.html?prefs=' + encodeURIComponent(JSON.stringify(initialPrefs)) + '&fontFaceCss=&initialCfi=';
  await page.setViewport({ width: 800, height: 1200, hasTouch: true });
  await page.goto(openUrl, { waitUntil: 'load' });
  await page.waitForFunction(() => window.__harnessEvents.some(e => e.name === 'onPageRendered'), { timeout: 15000 });
  await new Promise(r => setTimeout(r, 1500));
  console.log('--- calling nextPage() ---');
  await page.evaluate(() => window.nextPage());
  await new Promise(r => setTimeout(r, 500));
  console.log('--- dispatching touch tap ---');
  const client = page._client();
  await client.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{x:400,y:600,id:1,radiusX:5,radiusY:5,force:0.5}] });
  await new Promise(r => setTimeout(r, 30));
  await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await new Promise(r => setTimeout(r, 500));
  console.log('--- calling previousPage() ---');
  await page.evaluate(() => window.previousPage());
  await new Promise(r => setTimeout(r, 500));
  await browser.close();
});
"
```

Expected（本計畫規劃階段已實際執行過，以下為真實輸出，非預測）：
```
--- calling nextPage() ---
CONSOLE: [DEBUG-e25i4] window.nextPage() called t=1786551462018
--- dispatching touch tap ---
CONSOLE: [DEBUG-e25i4] touchend t=1786551462599
CONSOLE: [DEBUG-e25i4] click t=1786551462604 x=380.0 y=1800.0
--- calling previousPage() ---
CONSOLE: [DEBUG-e25i4] window.previousPage() called t=1786551463118
```
三則插樁皆正確輸出、無 `PAGEERROR`。`click` 的 `x`/`y` 是 `evt.clientX`/`evt.clientY`（iframe 內部本地座標，非 page-level），僅供時序判讀使用、不用於座標比對，不需額外轉換。

---

### Task 2：`reader_screen.dart` 新增 Dart 端除錯插樁

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:38`（新增 `reader_console_log.dart` import）、`:2390-2405`（`_handleZoneAction()` 的 `ZoneAction.previousPage`／`ZoneAction.nextPage` 分支）

**Interfaces:**
- Consumes：既有 `ReaderConsoleLog.add(String message)`（`app/lib/reader/reader_console_log.dart:20`，已在 `foliate_epub_reader_view.dart` 使用過的既有靜態方法）、既有 `_handleZoneAction(ZoneAction action)`（nav-zone 熱區點擊的統一分派點，PDF／EPUB 兩種格式共用同一個方法，本插樁只加在 EPUB 分支）。
- Produces：無新增可供其他 Task 呼叫的函式。

- [x] **Step 1：新增 import**

修改 `app/lib/screens/reader_screen.dart`，在 `import '../reader/reading_position.dart';`（第 38 行）之後插入：

```dart
import '../reader/reading_position.dart';
import '../reader/reader_console_log.dart';
import '../reader/reader_prefs_manager.dart';
```

- [x] **Step 2：`_handleZoneAction()` 的 EPUB 分支新增插樁**

修改 `app/lib/screens/reader_screen.dart:2390-2405`：

```dart
      case ZoneAction.previousPage:
        if (format == BookFormat.pdf) {
          PdfReaderView.previousPage(_pdfReaderViewKey);
        } else if (format == BookFormat.epub) {
          // Epic 25 Issue 4 暫時性除錯插樁 [DEBUG-e25i4]：量測 nav-zone
          // 熱區收到觸控到呼叫 FoliateEpubReaderView.previousPage()（進而
          // evaluateJavascript('window.previousPage()')）之間的真機時序，
          // 供與 main.js 同標籤插樁交叉比對。確認根因、產出修復計劃後需
          // 整段移除。
          ReaderConsoleLog.add(
            '[DEBUG-e25i4] _handleZoneAction(previousPage) t=${DateTime.now().millisecondsSinceEpoch}',
          );
          // Epic 20 Issue 2：EPUB 一律使用 FoliateEpubReaderView。
          FoliateEpubReaderView.previousPage(_foliateEpubReaderViewKey);
        }
        break;
      case ZoneAction.nextPage:
        if (format == BookFormat.pdf) {
          PdfReaderView.nextPage(_pdfReaderViewKey);
        } else if (format == BookFormat.epub) {
          // Epic 25 Issue 4 暫時性除錯插樁 [DEBUG-e25i4]：見上方
          // previousPage 分支註解，同理。
          ReaderConsoleLog.add(
            '[DEBUG-e25i4] _handleZoneAction(nextPage) t=${DateTime.now().millisecondsSinceEpoch}',
          );
          // Epic 20 Issue 2：EPUB 一律使用 FoliateEpubReaderView。
          FoliateEpubReaderView.nextPage(_foliateEpubReaderViewKey);
        }
        break;
```

- [x] **Step 3：`flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze`
Expected: `No issues found!`（本計畫規劃階段已實際執行確認）。

- [x] **Step 4：執行既有測試套件，確認無回歸**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: 全數通過（本計畫規劃階段已實際執行確認，147 項全數通過）——插樁只新增 `ReaderConsoleLog.add()` 呼叫（純副作用、無回傳值影響控制流程），不改變任何既有分派邏輯。

Run: `cd app && flutter test test/reader/foliate_epub_reader_view_test.dart`
Expected: 全數通過（本計畫規劃階段已實際執行確認，64 項全數通過，含既有 3×3 導航熱區測試確認未回歸）。

- [x] **Step 5：Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js app/lib/screens/reader_screen.dart
git commit -m "debug(epic-25): Issue 4 新增暫時性除錯插樁，量測點擊換頁與原生 click 合成事件的真機時序"
```

---

### Task 3：撰寫真機資料蒐集操作手冊，更新 `issues.md`

**Files:**
- Modify: `docs/epics/epic-25-annotation-interaction-qa/issues.md`（Issue 4 區塊，新增「真機資料蒐集步驟」小節）

**Interfaces:**
- Consumes：Task 1／Task 2 產出的 `[DEBUG-e25i4]` 插樁（已隨 debug build 部署到裝置）。
- Produces：無程式介面——本 Task 的產出是給人類操作的文字步驟，供人類在真機上實際執行後，將擷取到的 log 文字回報回來，供下一輪根因確認使用。

- [x] **Step 1：在 `issues.md` Issue 4 區塊新增操作手冊**

在 `docs/epics/epic-25-annotation-interaction-qa/issues.md` 的「## Issue 4」區塊內，「**headless CDP 時序驗證迴圈結果**」與「**解讀**」段落之後、「**下一步**」段落之前，新增：

```markdown
**真機資料蒐集步驟（`plan-issue-4-realdevice-diagnostics.md` Task 1／Task 2 完成後可執行）：**

1. 用含 `[DEBUG-e25i4]` 插樁的 debug build（`flutter build apk --debug`）安裝到真機（建議優先用 Air Reader Pro C，與 Issue 1 同一台曾重現互動類問題的裝置；若手邊沒有，任何裝置都可以先試）。
2. 開啟一本直排流式 EPUB，在畫面上對同一螢幕座標附近的文字新增一筆劃線（用長按選字→選色，建立一筆劃線，確保下一頁若剛好也有內容出現在同一位置時能誤觸發）。
3. 用 3×3 導覽熱區（點擊換頁，非滑動翻頁）連續點擊換頁多次，涵蓋「熱區位置剛好與畫線位置重疊」與「明顯不重疊」兩種情境，並留意是否有誤跳出「是否刪除畫線」的確認對話框。
4. 每次操作後，進入「設定」→「閱讀器 Console Log」，點擊右上角「複製全部」按鈕，將剪貼簿內容貼到文字檔或直接回報；同步註記該次操作「是否有觀察到誤跳出刪除確認對話框」。
5. 重複步驟 3-4 至少 5-10 次（點擊換頁動作很快，單次操作不一定會踩到競速窗口，需要多次嘗試才能提高重現機率，比照 `/diagnose` 技能「非決定性 bug 目標是提高重現率」）。
6. 將 log 檔案／文字回報回來，交叉比對 `main.js` 端（`window.nextPage()/previousPage() called`／`touchend`／`click`／`show-annotation`）與 Dart 端（`_handleZoneAction(...)`）各筆記錄的 `t=` 時間戳（皆為 epoch 毫秒，可直接相減）——特別留意：(a) `_handleZoneAction` 記錄的時間與對應的 `window.nextPage()/previousPage() called` 記錄的時間差，代表 Dart→JS 橋接呼叫的實際往返延遲；(b) `click` 記錄的時間相對 `touchend` 記錄的時間差，代表原生合成 click 事件的真機延遲；(c) 若某次操作誤跳出刪除確認對話框，比對該次 `show-annotation` 記錄的 `id` 與該次 `click` 記錄的時間，確認是否命中換頁後的新頁內容。

**下一輪（拿到真機資料後）**：依比對結果撰寫 `bugfix-repro-issue-4.md` 確認根因，另立修復計畫；本插樁需在修復計畫的 Cleanup 階段整段移除（`grep -rn "DEBUG-e25i4"` 確認清除乾淨）。
```

- [x] **Step 2：Commit**

```bash
git add docs/epics/epic-25-annotation-interaction-qa/issues.md
git commit -m "docs(epic-25): Issue 4 補上真機資料蒐集操作手冊"
```

---

## Self-Review

- **Spec 覆蓋度**：`plan-issue-4.md`「解讀」段落留下的「headless 環境無法區辨兩種可能性」問題，由本計畫的真機插樁完整覆蓋——JS 端量測原生 `click` 合成時序（區辨可能性 b：headless 觸控合成時序是否與真機不同），Dart 端量測 `_handleZoneAction`→JS 呼叫的真實橋接延遲（區辨可能性 a：真機橋接延遲是否確實比 headless `page.evaluate()` 更長）。
- **No Placeholders 掃描**：Task 1／Task 2 的插樁程式碼、Task 1 Step 5 的驗證輸出、Task 3 的操作手冊文字，皆為規劃階段實際套用到程式碼並執行驗證過的內容（`flutter analyze`／`flutter test`／headless console 輸出皆為真實結果），非理論推算。
- **型別/介面一致性**：`ReaderConsoleLog.add(String message)` 呼叫方式與 `foliate_epub_reader_view.dart:213` 既有用法一致；JS 端 `console.log` 走既有 `InAppWebView.onConsoleMessage` 管線，未新增任何橋接介面。
- **既有測試不回歸的具體論證**：JS 端插樁只新增純觀察監聽器與既有函式內的 `console.log` 呼叫，不改變任何既有回傳值或控制流程；Dart 端插樁只在既有 `switch` 分支內新增一行 `ReaderConsoleLog.add()` 副作用呼叫，同樣不改變控制流程。Task 2 Step 4 仍安排執行完整既有測試套件作為實測佐證，不僅依賴此推論。
- **範圍誠實聲明**：本計畫刻意不包含「鎖定根因」與「撰寫修復」——這兩步依賴 Task 3 蒐集回來的真機資料，屬於下一輪計畫的範圍，不在本計畫內用臆測方式提前完成。
