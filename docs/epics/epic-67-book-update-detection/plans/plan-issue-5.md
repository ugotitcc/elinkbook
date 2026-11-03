# Issue 5：Foliate 格式定位失敗降級 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** EPUB／KF8／CBZ／TXT／MD 的精確定位（CFI）在新版內容中失效時，開書不再卡死或靜默回到書頭，書籤與註記跳轉也不再毫無反應；一律改用概略進度比例定位，並向使用者提示。

**Architecture:** 在 `main.js` 新增「解析並驗證 CFI」的共用判斷（章節索引必須落在有效範圍內），開書與跳轉兩條路徑失敗時都改呼叫 `view.goToFraction()`，並透過新的 JS→Dart handler `onNavigationDegraded` 回報。Dart 端把進度比例一路傳進 `FoliateReaderView`，收到回報後由 `ReaderScreen` 顯示 SnackBar。不修改釘定的 vendor 檔案（`view.js`、`paginator.js` 等）。

**Tech Stack:** Flutter／Dart、`flutter_inappwebview`、`readest/foliate-js`（釘定版本）、Puppeteer harness（`app/tool/foliate_touch_harness`）、`integration_test`（真機）。

**Spec:** `docs/epics/epic-67-book-update-detection/spec.md`「註記與閱讀位置的降級」；工單見同目錄 `issues.md` Issue 5；背景見 `epic.md`。

**分支建議：** `epic-67/issue-5-foliate-navigation-degrade`（從最新 `main` 切出）。

## 實測結果（2026-11-03，本計畫撰寫時以 harness 對現行 `main.js` 探測）

這些是 plan 的事實依據，**與 `review-spec.md` C-3 的推測不完全相同**：

| 情境 | 開書（`initialCfi`） | 開書後跳轉（`jumpToLocator`） |
|---|---|---|
| 章節索引超界（如 `epubcfi(/6/40!/4/2)`） | **整本書卡住**：`onPageRendered`、`onError` 都不觸發，使用者看到載入畫面永遠不消失 | `view.goTo` 回傳 `{index:-1}` 看似成功，**位置完全不動**，無任何回報 |
| CFI 格式損壞（如 `epubcfi(/6/4!/4/`） | 靜默開在書頭，無任何回報 | `view.goTo` 回傳 `undefined`，**位置不動**，無任何回報 |
| 章節存在、元素路徑不存在（如 `epubcfi(/6/4!/4/900/2)`） | Foliate 自行落在該章節，**不是失敗** | 同左 |
| 舊格式 Readium Locator JSON 字串（`extractCfi` 會回傳 null，Dart 端改為原字串交給 JS） | `resolveNavigation` 回傳**非 null 但 `index` 為 undefined 的物件**——只檢查「是否為 null」會漏掉，所以 `resolveValidatedCfi` 必須用 `Number.isInteger(resolved.index)` 驗證 | 同左 |
| 失敗後再呼叫 `view.goToFraction()` | — | **可正常運作**（探測驗證過） |

結論：不能依賴 `view.goTo()` 的回傳值或例外判斷失敗（超界時它「成功」），必須**事先驗證章節索引**。元素路徑不存在不算失敗，不得誤報降級。

## Global Constraints

- 所有註解、文件、提示字串一律正體中文（zh-TW）；程式碼命名維持英文。
- **不得修改**釘定的 vendor 檔案：`app/android/app/src/main/assets/foliate/` 下的 `view.js`、`paginator.js`、`epub.js` 等；只改 `main.js`。
- `main.js` 只用既有程式碼已使用的語法（可用 `?.`、`??`；不得引入較新的內建方法，如 `Array.prototype.at`）。改完須跑 `node app/tool/check_foliate_es_compat.js`。
- JS→Dart handler 名稱一律登錄在 `FoliateBridgeHandlers`，不得在 Dart 端硬編碼字串。
- 畫面字串一律走 `AppLocalizations`，四份 ARB（`app_zh_TW.arb` 為樣板、`app_en.arb`、`app_zh.arb`、`app_zh_CN.arb`）同步；新增後執行 `flutter gen-l10n`，產生檔案（`lib/l10n/app_localizations*.dart`）一併進版控。
- 提交前：`flutter analyze` 必須 "No issues found!"；`node tool/check_l10n_hardcoded_strings.js`；動到 `integration_test/` 者另跑 `node tool/check_integration_keys.js`（皆在 `app/` 下執行）。
- 測試範圍：每個 Task 只跑該 Task 觸及的測試檔；完整 `flutter test` 只在最後一個 Task 執行一次。
- 所有指令的工作目錄除非另註，皆為 `app/`（Node harness 指令在 `app/tool/foliate_touch_harness/`）。

## Review Focus

以下是 spec 隱含、但容易被忽略的輸入或失敗情境，各自在對應 Task 內有測試：

1. **舊資料沒有概略進度**（`progression` 為 null 的舊書籤／劃線）：精確定位失敗時沒有比例可用，**不得移動位置、不得崩潰**，仍須回報降級（Task 2 情境 D；Task 3 腳本產生器 null 分支）。
2. **進度比例超出 0～1 或為 NaN／無限大**：JS 端須夾限到 0～1，Dart 端產生腳本時須丟棄非有限值（Task 2 情境 E；Task 3）。
3. **元素路徑不存在的 CFI 不是失敗**：不得誤報降級、不得被誤導到別處（Task 1 情境 F、Task 2 情境 F）。
4. **搜尋結果開書跳轉（`initialJumpTarget.cfi`）失敗且沒有進度比例**：退回書頭並提示，不卡死（Task 1 情境 D；Task 5 `initialProgression` 為 null 的測試）。
5. **沒有 `initialCfi` 的一般開書**不得觸發降級回報（Task 1 情境 G，迴歸）。
6. **舊格式 Readium Locator JSON 與損壞字串**（`extractCfi` 回傳 null）：Dart 端不得提早過濾，否則 JS 的降級被短路——開書會靜默回書頭、點書籤毫無反應（Task 1 情境 H、Task 2 情境 H；Task 3 的 `extractCfiOrRaw` 測試）。

---

### Task 1：`main.js` 開書降級（含 harness 擴充）

**Files:**
- Modify: `app/tool/foliate_touch_harness/lib/harness.mjs`（新增 `initialCfi`／`initialProgression` 選項；等待失敗時關閉瀏覽器）
- Create: `app/tool/foliate_touch_harness/lib/multi-chapter-epub.mjs`
- Create: `app/tool/foliate_touch_harness/scenario-epic67-open-position-degrade.mjs`
- Modify: `app/android/app/src/main/assets/foliate/main.js`（約 95 行、約 600 行、約 1771 行）

**Interfaces:**
- Produces（JS）：`resolveValidatedCfi(cfi)`、`goToFractionSafely(fraction)`、`reportNavigationDegraded(reason)`、`openAtInitialLocation()`；URL 參數 `initialProgression`；handler `onNavigationDegraded`，參數為字串 `'readingPosition'` 或 `'annotation'`。Task 2 會重用前三者。
- Produces（harness）：`launchHarnessPage({ initialCfi, initialProgression, ... })`、`buildMultiChapterEpub()`（3 章，每章約 12 段長文字，章節索引 0～2）。

- [x] **Step 1：擴充 harness（向後相容）**

在 `lib/harness.mjs` 的 `launchHarnessPage` 參數列（`beforeNavigate = null,` 之後）加入：

```js
  // epic-67 Issue 5：開書定位。initialCfi 預設空字串、initialProgression 預設不帶，
  // 與既有場景行為完全相同。
  initialCfi = '',
  initialProgression = null,
```

把組 `openUrl` 的那一行改為：

```js
  const progressionParam = initialProgression === null ? '' : `&initialProgression=${initialProgression}`
  const openUrl = `${ORIGIN}/index.html?prefs=${encodeURIComponent(JSON.stringify(initialPrefs))}&fontFaceCss=&initialCfi=${encodeURIComponent(initialCfi)}${progressionParam}`
```

把 `await page.goto(openUrl ...)` 之後兩段 `waitForFunction` 與 `setTimeout(300)` 包進 try／catch，失敗時先關瀏覽器再重新拋出（否則逾時時 Chromium 會殘留）：

```js
  try {
    await page.goto(openUrl, { waitUntil: 'load' })
    // ……原本的兩段 waitForFunction 與 300ms 等待，內容不變……
  } catch (err) {
    await browser.close()
    throw err
  }
```

- [x] **Step 2：新增共用 fixture**

建立 `lib/multi-chapter-epub.mjs`：

```js
// epic-67 Issue 5：3 章、每章夠長的最小合法 EPUB（記憶體組出，不進版控二進位檔）。
// 章節索引 0～2；CFI /6/2 = 第 0 章、/6/4 = 第 1 章、/6/6 = 第 2 章。
import { buildStoredZip } from './harness.mjs'

function chapter(n) {
  const para = `第${n}章的內容段落，用來撐出足夠的文字長度以便分頁與驗證，重複多次。`.repeat(40)
  const paragraphs = Array.from({ length: 12 }, (_, i) => `<p>${para}${i}</p>`).join('')
  return `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第${n}章</title></head>
<body><h1>第${n}章</h1>${paragraphs}</body></html>`
}

export function buildMultiChapterEpub() {
  const container = `<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>`
  const opf = `<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="p"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="p">urn:uuid:epic67-degrade-1</dc:identifier><dc:title>降級測試</dc:title><dc:language>zh-TW</dc:language><meta property="dcterms:modified">2026-01-01T00:00:00Z</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/><item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/><item id="c3" href="c3.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/><itemref idref="c2"/><itemref idref="c3"/></spine></package>`
  const nav = `<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目錄</title></head><body><nav epub:type="toc"><ol><li><a href="c1.xhtml">一</a></li><li><a href="c2.xhtml">二</a></li><li><a href="c3.xhtml">三</a></li></ol></nav></body></html>`
  return buildStoredZip([
    { name: 'mimetype', data: Buffer.from('application/epub+zip') },
    { name: 'META-INF/container.xml', data: Buffer.from(container) },
    { name: 'OEBPS/content.opf', data: Buffer.from(opf) },
    { name: 'OEBPS/nav.xhtml', data: Buffer.from(nav) },
    { name: 'OEBPS/c1.xhtml', data: Buffer.from(chapter(1)) },
    { name: 'OEBPS/c2.xhtml', data: Buffer.from(chapter(2)) },
    { name: 'OEBPS/c3.xhtml', data: Buffer.from(chapter(3)) },
  ])
}
```

- [x] **Step 3：寫失敗的開書情境（RED）**

建立 `scenario-epic67-open-position-degrade.mjs`：

```js
// epic-67 Issue 5：開書時精確定位（initialCfi）失效的降級。
// 現況（修正前）：章節索引超界會讓整本書卡住（onPageRendered／onError 都不來）；
// CFI 格式損壞會靜默開在書頭。修正後應改用 initialProgression 定位並回報降級。
import { launchHarnessPage, report } from './lib/harness.mjs'
import { buildMultiChapterEpub } from './lib/multi-chapter-epub.mjs'

async function openWith({ initialCfi, initialProgression }) {
  try {
    const { browser, page } = await launchHarnessPage({
      fixtureBuffer: buildMultiChapterEpub(),
      initialCfi,
      initialProgression,
    })
    await new Promise((r) => setTimeout(r, 800))
    const events = await page.evaluate(() => window.__harnessEvents)
    await browser.close()
    return { opened: true, events }
  } catch (err) {
    return { opened: false, events: [], error: String(err).slice(0, 120) }
  }
}

function lastLocation(events) {
  const hits = events.filter((e) => e.name === 'onLocatorChanged')
  return hits.length ? JSON.parse(hits[hits.length - 1].args[0]) : null
}
const degradedReasons = (events) =>
  events.filter((e) => e.name === 'onNavigationDegraded').map((e) => e.args[0])

async function main() {
  // A. 有效 CFI（第 1 章）：正常定位，不降級
  {
    const r = await openWith({ initialCfi: 'epubcfi(/6/4!/4/4)', initialProgression: 0.9 })
    report('A 有效 CFI：開書成功', r.opened, r.error)
    report('A 有效 CFI：落在第 1 章', lastLocation(r.events)?.index === 1, JSON.stringify(lastLocation(r.events)))
    report('A 有效 CFI：不回報降級', degradedReasons(r.events).length === 0)
  }
  // B. 章節索引超界＋有進度比例：不得卡死，改用 0.8 定位並回報
  {
    const r = await openWith({ initialCfi: 'epubcfi(/6/40!/4/2)', initialProgression: 0.8 })
    report('B 索引超界：開書不卡死', r.opened, r.error)
    const loc = lastLocation(r.events)
    report('B 索引超界：改用進度比例定位（約 0.8）', loc !== null && Math.abs(loc.fraction - 0.8) < 0.15, JSON.stringify(loc))
    report('B 索引超界：回報一次 readingPosition 降級', JSON.stringify(degradedReasons(r.events)) === '["readingPosition"]', JSON.stringify(degradedReasons(r.events)))
  }
  // C. CFI 格式損壞＋有進度比例：不得靜默開在書頭
  {
    const r = await openWith({ initialCfi: 'epubcfi(/6/4!/4/', initialProgression: 0.8 })
    const loc = lastLocation(r.events)
    report('C 格式損壞：改用進度比例定位（約 0.8）', loc !== null && Math.abs(loc.fraction - 0.8) < 0.15, JSON.stringify(loc))
    report('C 格式損壞：回報一次 readingPosition 降級', JSON.stringify(degradedReasons(r.events)) === '["readingPosition"]')
  }
  // D. 索引超界＋沒有進度比例（例如搜尋結果跳轉）：開在書頭、仍回報
  {
    const r = await openWith({ initialCfi: 'epubcfi(/6/40!/4/2)', initialProgression: null })
    report('D 無進度比例：開書不卡死', r.opened, r.error)
    report('D 無進度比例：開在書頭（第 0 章）', lastLocation(r.events)?.index === 0, JSON.stringify(lastLocation(r.events)))
    report('D 無進度比例：回報一次 readingPosition 降級', JSON.stringify(degradedReasons(r.events)) === '["readingPosition"]')
  }
  // E. 進度比例超出範圍（1.7）：夾限到 1，落在書尾
  {
    const r = await openWith({ initialCfi: 'epubcfi(/6/40!/4/2)', initialProgression: 1.7 })
    const loc = lastLocation(r.events)
    report('E 比例 1.7：夾限後落在書尾（第 2 章）', loc !== null && loc.index === 2, JSON.stringify(loc))
  }
  // F. 元素路徑不存在：Foliate 自行落在該章節，不是失敗，不得誤報
  {
    const r = await openWith({ initialCfi: 'epubcfi(/6/4!/4/900/2)', initialProgression: 0.9 })
    report('F 元素不存在：落在第 1 章', lastLocation(r.events)?.index === 1, JSON.stringify(lastLocation(r.events)))
    report('F 元素不存在：不回報降級', degradedReasons(r.events).length === 0)
  }
  // H. 舊格式 Readium Locator JSON（Dart 端 extractCfi 無法解析，會原字串交給 JS）：
  //    JS 端必須判定無效並降級，不得把它當成 href 而落到別處
  {
    const legacy = '{"href":"c2.xhtml","locations":{"progression":0.3}}'
    const r = await openWith({ initialCfi: legacy, initialProgression: 0.8 })
    const loc = lastLocation(r.events)
    report('H 舊格式 JSON：改用進度比例定位（約 0.8）', loc !== null && Math.abs(loc.fraction - 0.8) < 0.15, JSON.stringify(loc))
    report('H 舊格式 JSON：回報一次 readingPosition 降級', JSON.stringify(degradedReasons(r.events)) === '["readingPosition"]')
  }
  // G. 沒有 initialCfi 的一般開書：不得觸發降級（迴歸）
  {
    const r = await openWith({ initialCfi: '', initialProgression: 0.9 })
    report('G 一般開書：開在書頭', lastLocation(r.events)?.index === 0, JSON.stringify(lastLocation(r.events)))
    report('G 一般開書：不回報降級', degradedReasons(r.events).length === 0)
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
```

- [x] **Step 4：執行確認失敗**

Run（在 `app/tool/foliate_touch_harness/`）：`node scenario-epic67-open-position-degrade.mjs`
Expected：A、F、G 的定位項 PASS；B／D／E 顯示 `FAIL`（開書逾時，`r.opened` 為 false）；C、H 顯示 `FAIL`（開在書頭、無降級回報）；整體 exit code 1。

- [x] **Step 5：實作 `main.js`**

(5a) 在 `const initialCfi = params.get('initialCfi') || ''`（約 95 行）之後新增：

```js
// epic-67 Issue 5：精確定位（initialCfi）失效時的降級進度比例（0～1）。
// 缺漏或無法解析時為 NaN，降級流程會改開在書頭。
const initialProgressionParam = params.get('initialProgression')
const initialProgression =
  initialProgressionParam === null ? NaN : parseFloat(initialProgressionParam)
```

(5b) 在 `window.jumpToLocator` 的 JSDoc 註解之前（約 600 行前）新增共用函式：

```js
/**
 * epic-67 Issue 5：解析 CFI 並驗證章節索引在有效範圍內。
 *
 * 不能只靠 view.goTo()／view.resolveNavigation() 判斷失敗（實測）：章節索引
 * 超界時 resolveNavigation 回傳 {index:-1} 看似成功，開書會卡死、跳轉則位置
 * 不動；格式損壞時回傳 undefined。章節存在但元素路徑不存在時，Foliate 會自行
 * 落在該章節，那不是失敗。
 * 回傳可交給 renderer.goTo() 的物件；無效時回傳 null。
 */
function resolveValidatedCfi(cfi) {
  let resolved
  try {
    resolved = view.resolveNavigation(cfi)
  } catch (_) {
    return null
  }
  if (!resolved || !Number.isInteger(resolved.index)) return null
  const sectionCount = view.book?.sections?.length ?? 0
  if (resolved.index < 0 || resolved.index >= sectionCount) return null
  return resolved
}

/** 跳到全書進度比例（夾限 0～1）；比例無效或跳轉失敗回傳 false，不拋例外。 */
async function goToFractionSafely(fraction) {
  if (!Number.isFinite(fraction)) return false
  try {
    await view.goToFraction(Math.min(1, Math.max(0, fraction)))
    return true
  } catch (_) {
    return false
  }
}

/** 通知 Dart 端「精確定位失敗，已降級」。reason：'readingPosition' | 'annotation'。 */
function reportNavigationDegraded(reason) {
  window.flutter_inappwebview.callHandler('onNavigationDegraded', reason)
}

/**
 * 開書定位：有 initialCfi 時先驗證再跳轉；失敗（無效、超界、跳轉拋例外）改用
 * initialProgression，連比例也無效就開在書頭，並回報降級。沒有 initialCfi 時
 * 與修正前完全相同。
 */
async function openAtInitialLocation() {
  if (!initialCfi) {
    await view.init({})
    return
  }
  const resolved = resolveValidatedCfi(initialCfi)
  if (resolved) {
    try {
      await view.renderer.goTo(resolved)
      view.history.pushState(initialCfi)
      return
    } catch (_) {
      // 落到下方降級流程
    }
  }
  if (!(await goToFractionSafely(initialProgression))) {
    await view.init({})
  }
  reportNavigationDegraded('readingPosition')
}
```

(5c) 把 `openBook()` 內的 `await view.init(initialCfi ? { lastLocation: initialCfi } : {})`（約 1771 行）改為：

```js
    await openAtInitialLocation()
```

- [x] **Step 6：執行確認通過**

Run：`node scenario-epic67-open-position-degrade.mjs`
Expected：全部 `[PASS]`，exit code 0。若 B 的 `Math.abs(fraction - 0.8) < 0.15` 因分頁取整略超出，**不要放寬門檻**，先印出實際值判斷是實作問題還是 fixture 問題。

- [x] **Step 7：既有 harness 迴歸與 ES 相容檢查**

Run（`app/tool/foliate_touch_harness/`）：`node run-all.mjs`
Expected：整體結果「全部 PASS」（既有場景因 harness 改動向後相容，不應受影響）。
Run（`app/`）：`node tool/check_foliate_es_compat.js`
Expected：無新的未設防 API 用法。

- [x] **Step 8：Commit**

```bash
git add app/tool/foliate_touch_harness app/android/app/src/main/assets/foliate/main.js
git commit -m "feat(epic-67): Issue 5 開書時 CFI 失效改用進度比例並回報降級"
```

---

### Task 2：`main.js` 跳轉降級

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`（`window.jumpToLocator`，約 608 行）
- Create: `app/tool/foliate_touch_harness/scenario-epic67-jump-degrade.mjs`

**Interfaces:**
- Consumes（Task 1）：`resolveValidatedCfi`、`goToFractionSafely`、`reportNavigationDegraded`。
- Produces：`window.jumpToLocator(cfi, fallbackProgression)`——第二參數為數字或 `null`；回傳 Promise；Task 4 的 Dart 腳本以此簽章呼叫。

- [x] **Step 1：寫失敗的跳轉情境（RED）**

建立 `scenario-epic67-jump-degrade.mjs`：

```js
// epic-67 Issue 5：開書後點擊書籤／註記跳轉，CFI 失效時改用概略進度並回報降級。
// 現況（修正前）：索引超界時 view.goTo 回傳看似成功但位置不動；格式損壞時回傳
// undefined、位置不動；兩者都沒有任何回報。
import { launchHarnessPage, report, resetHarnessEvents } from './lib/harness.mjs'
import { buildMultiChapterEpub } from './lib/multi-chapter-epub.mjs'

const settle = () => new Promise((r) => setTimeout(r, 700))

function lastLocation(events) {
  const hits = events.filter((e) => e.name === 'onLocatorChanged')
  return hits.length ? JSON.parse(hits[hits.length - 1].args[0]) : null
}
const degradedReasons = (events) =>
  events.filter((e) => e.name === 'onNavigationDegraded').map((e) => e.args[0])

// 每個案例都重新開書（起點固定在書頭），避免前一案例的位置影響斷言。
async function runCase(cfi, fallback) {
  const { browser, page } = await launchHarnessPage({ fixtureBuffer: buildMultiChapterEpub() })
  try {
    await resetHarnessEvents(page)
    await page.evaluate((cfi, fallback) => window.jumpToLocator(cfi, fallback), cfi, fallback)
    await settle()
    return await page.evaluate(() => window.__harnessEvents)
  } finally {
    await browser.close()
  }
}

async function main() {
  // A. 有效 CFI（第 2 章）：直接跳過去，不降級（即使帶了進度比例）
  {
    const events = await runCase('epubcfi(/6/6!/4/4)', 0.1)
    report('A 有效 CFI：落在第 2 章', lastLocation(events)?.index === 2, JSON.stringify(lastLocation(events)))
    report('A 有效 CFI：不回報降級', degradedReasons(events).length === 0)
  }
  // B. 章節索引超界＋進度比例 0.8：改跳 0.8 並回報 annotation
  {
    const events = await runCase('epubcfi(/6/40!/4/2)', 0.8)
    const loc = lastLocation(events)
    report('B 索引超界：改跳進度比例（約 0.8）', loc !== null && Math.abs(loc.fraction - 0.8) < 0.15, JSON.stringify(loc))
    report('B 索引超界：回報一次 annotation 降級', JSON.stringify(degradedReasons(events)) === '["annotation"]', JSON.stringify(degradedReasons(events)))
  }
  // C. 格式損壞＋進度比例：同上
  {
    const events = await runCase('epubcfi(/6/4!/4/', 0.8)
    const loc = lastLocation(events)
    report('C 格式損壞：改跳進度比例（約 0.8）', loc !== null && Math.abs(loc.fraction - 0.8) < 0.15, JSON.stringify(loc))
    report('C 格式損壞：回報一次 annotation 降級', JSON.stringify(degradedReasons(events)) === '["annotation"]')
  }
  // D. 舊資料沒有進度比例（null）：位置不動、不崩潰、仍回報
  {
    const events = await runCase('epubcfi(/6/40!/4/2)', null)
    report('D 無進度比例：仍回報一次 annotation 降級', JSON.stringify(degradedReasons(events)) === '["annotation"]')
    const moved = events.some((e) => e.name === 'onLocatorChanged')
    report('D 無進度比例：位置不移動（沒有新的 onLocatorChanged）', !moved, JSON.stringify(lastLocation(events)))
  }
  // E. 進度比例 NaN／超出範圍：NaN 視為沒有；1.7 夾限到書尾
  {
    const nanEvents = await runCase('epubcfi(/6/40!/4/2)', NaN)
    report('E1 比例 NaN：視為沒有比例，仍回報且不移動', JSON.stringify(degradedReasons(nanEvents)) === '["annotation"]' && !nanEvents.some((e) => e.name === 'onLocatorChanged'))
    const bigEvents = await runCase('epubcfi(/6/40!/4/2)', 1.7)
    report('E2 比例 1.7：夾限後落在書尾（第 2 章）', lastLocation(bigEvents)?.index === 2, JSON.stringify(lastLocation(bigEvents)))
  }
  // H. 舊格式 Readium Locator JSON（Dart 端 extractCfi 無法解析，會原字串交給 JS）
  {
    const legacy = '{"href":"c2.xhtml","locations":{"progression":0.3}}'
    const events = await runCase(legacy, 0.8)
    const loc = lastLocation(events)
    report('H 舊格式 JSON：改跳進度比例（約 0.8）', loc !== null && Math.abs(loc.fraction - 0.8) < 0.15, JSON.stringify(loc))
    report('H 舊格式 JSON：回報一次 annotation 降級', JSON.stringify(degradedReasons(events)) === '["annotation"]')
  }
  // F. 元素路徑不存在：Foliate 落在該章節，不是失敗，不得誤報
  {
    const events = await runCase('epubcfi(/6/6!/4/900/2)', 0.1)
    report('F 元素不存在：落在第 2 章', lastLocation(events)?.index === 2, JSON.stringify(lastLocation(events)))
    report('F 元素不存在：不回報降級', degradedReasons(events).length === 0)
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
```

- [x] **Step 2：執行確認失敗**

Run（`app/tool/foliate_touch_harness/`）：`node scenario-epic67-jump-degrade.mjs`
Expected：A、F 的定位項 PASS；B／C／D／E 的「回報降級」項 `FAIL`；B／C／E2 的定位項 `FAIL`。（`NaN` 經 `page.evaluate` 序列化後可能變成 `null`，兩者在 JS 端都應被視為無比例，這正是 E1 要驗證的。）

- [x] **Step 3：實作 `window.jumpToLocator`**

把現有的

```js
window.jumpToLocator = function (cfi) {
  view.goTo(cfi)
}
```

換成，並更新其上方 JSDoc 註解（補一句「epic-67 Issue 5：第二參數為降級用的概略進度比例，可為 null」）：

```js
window.jumpToLocator = async function (cfi, fallbackProgression) {
  const resolved = resolveValidatedCfi(cfi)
  if (resolved) {
    // view.goTo 內部吞掉例外，失敗時回傳 undefined；成功時回傳已解析的目標物件。
    const result = await view.goTo(cfi)
    if (result) return
  }
  await goToFractionSafely(fallbackProgression)
  reportNavigationDegraded('annotation')
}
```

- [x] **Step 4：執行確認通過**

Run：`node scenario-epic67-jump-degrade.mjs` → 全部 `[PASS]`。
Run：`node scenario-epic67-open-position-degrade.mjs` → 仍全部 `[PASS]`（共用函式未被破壞）。

- [x] **Step 5：Commit**

```bash
git add app/tool/foliate_touch_harness app/android/app/src/main/assets/foliate/main.js
git commit -m "feat(epic-67): Issue 5 註記與書籤跳轉 CFI 失效改用進度比例並回報降級"
```

---

### Task 3：Dart 橋接契約（純函式，脫離 WebView 可測）

**Files:**
- Modify: `app/lib/reader/foliate_bridge_handlers.dart`
- Create: `app/lib/reader/navigation_degraded_reason.dart`
- Modify: `app/lib/reader/foliate_bridge_codec.dart`
- Modify: `app/test/reader/foliate_bridge_handlers_test.dart`
- Create: `app/test/reader/navigation_degraded_reason_test.dart`
- Modify: `app/test/reader/foliate_bridge_codec_test.dart`

**Interfaces:**
- Produces：
  - `FoliateBridgeHandlers.onNavigationDegraded`（字串值 `'onNavigationDegraded'`，須與 Task 1 的 `callHandler` 逐字相符）。
  - `enum NavigationDegradedReason { readingPosition, annotation }`。
  - `NavigationDegradedReason? parseNavigationDegradedReason(List<dynamic> args)`：`args[0]` 為 `'readingPosition'`／`'annotation'` 之一才回傳對應值，其餘（空、非字串、未知字串）回傳 `null`，不拋例外。
  - `String buildJumpToLocatorScript(String cfi, {double? fallbackProgression})`：產生 `window.jumpToLocator(<json 字串>, <數字|null>)`；非有限值（NaN、無限大）視為 `null`。
  - `String? extractCfiOrRaw(String? locatorJson)`：可解析出 CFI 就回傳 CFI；無法解析（舊格式 Readium Locator JSON、損壞字串）但去空白後非空時，回傳**去空白後的原字串**，讓 JS 端判定無效並走降級；null 或空白回傳 null。**這是為了避免 Dart 端提早過濾而短路 JS 的降級**（審查 I-1／I-2）。
  - `Map<String, String> buildInitialLocationParams({String? initialLocatorJson, double? initialProgression})`：以 `extractCfiOrRaw` 取得定位字串，非 null 時含 `initialCfi`；有限的比例才含 `initialProgression`；定位字串為 null（沒有任何儲存位置）時回傳空 map。

- [x] **Step 1：寫失敗的測試**

(1a) `foliate_bridge_handlers_test.dart`：在 `expected` 與 `actual` 兩個 map 各加一筆 `'onNavigationDegraded': 'onNavigationDegraded'`／`FoliateBridgeHandlers.onNavigationDegraded`，`values` 集合加 `FoliateBridgeHandlers.onNavigationDegraded`，並把第二個測試名稱的「11 個」改為「12 個」、`hasLength(11)` 改為 `hasLength(12)`。

(1b) 建立 `test/reader/navigation_degraded_reason_test.dart`：

```dart
import 'package:elinkbook/reader/navigation_degraded_reason.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseNavigationDegradedReason', () {
    test('readingPosition 與 annotation 各自對應', () {
      expect(parseNavigationDegradedReason(['readingPosition']),
          NavigationDegradedReason.readingPosition);
      expect(parseNavigationDegradedReason(['annotation']),
          NavigationDegradedReason.annotation);
    });

    test('空參數、非字串、未知字串都回傳 null 且不拋例外', () {
      expect(parseNavigationDegradedReason(const []), isNull);
      expect(parseNavigationDegradedReason([42]), isNull);
      expect(parseNavigationDegradedReason([null]), isNull);
      expect(parseNavigationDegradedReason(['somethingElse']), isNull);
    });
  });
}
```

(1c) `foliate_bridge_codec_test.dart` 尾端（`main()` 內）新增：

```dart
  group('buildJumpToLocatorScript', () {
    test('帶進度比例：第二個參數為數字', () {
      expect(
        buildJumpToLocatorScript('epubcfi(/6/4!/4/2)', fallbackProgression: 0.5),
        'window.jumpToLocator("epubcfi(/6/4!/4/2)", 0.5)',
      );
    });

    test('沒有進度比例：第二個參數為 null（舊資料沒有 progression）', () {
      expect(
        buildJumpToLocatorScript('epubcfi(/6/4!/4/2)'),
        'window.jumpToLocator("epubcfi(/6/4!/4/2)", null)',
      );
    });

    test('NaN 與無限大視為沒有比例，避免產生無效的 JS 字面值', () {
      expect(
        buildJumpToLocatorScript('epubcfi(/6/4)', fallbackProgression: double.nan),
        'window.jumpToLocator("epubcfi(/6/4)", null)',
      );
      expect(
        buildJumpToLocatorScript('epubcfi(/6/4)',
            fallbackProgression: double.infinity),
        'window.jumpToLocator("epubcfi(/6/4)", null)',
      );
    });

    test('CFI 內的特殊字元由 JSON 編碼處理，不會破壞腳本', () {
      expect(
        buildJumpToLocatorScript('epubcfi(/6/4"x)'),
        'window.jumpToLocator("epubcfi(/6/4\\"x)", null)',
      );
    });
  });

  group('extractCfiOrRaw', () {
    test('可解析的 CFI（含 raw CFI 與新格式 JSON）回傳 CFI', () {
      expect(extractCfiOrRaw('epubcfi(/6/4!/4/2)'), 'epubcfi(/6/4!/4/2)');
      expect(
        extractCfiOrRaw('{"cfi":"epubcfi(/6/4!/4/2)","index":1,"fraction":0.3}'),
        'epubcfi(/6/4!/4/2)',
      );
    });

    test('無法解析但非空：回傳去空白後的原字串（舊格式 JSON、損壞 CFI）', () {
      const legacy = '{"href":"c2.xhtml","locations":{"progression":0.3}}';
      expect(extractCfiOrRaw(legacy), legacy);
      expect(extractCfiOrRaw('  epubcfi(/6/4!/4/  '), 'epubcfi(/6/4!/4/');
    });

    test('null 或空白回傳 null', () {
      expect(extractCfiOrRaw(null), isNull);
      expect(extractCfiOrRaw('   '), isNull);
    });
  });

  group('buildInitialLocationParams', () {
    test('CFI 與有限比例都有：兩個參數都帶', () {
      expect(
        buildInitialLocationParams(
            initialLocatorJson: 'epubcfi(/6/4!/4/2)', initialProgression: 0.42),
        {'initialCfi': 'epubcfi(/6/4!/4/2)', 'initialProgression': '0.42'},
      );
    });

    test('只有 CFI：不帶比例', () {
      expect(
        buildInitialLocationParams(initialLocatorJson: 'epubcfi(/6/4!/4/2)'),
        {'initialCfi': 'epubcfi(/6/4!/4/2)'},
      );
    });

    test('沒有任何儲存位置（null 或空白）：回傳空 map（單獨的比例沒有意義）', () {
      expect(buildInitialLocationParams(initialProgression: 0.42), isEmpty);
      expect(
        buildInitialLocationParams(initialLocatorJson: '   ', initialProgression: 0.42),
        isEmpty,
      );
    });

    test('舊格式或損壞的定位字串：原字串仍交給 JS，連同比例讓 JS 走降級', () {
      const legacy = '{"href":"c2.xhtml","locations":{"progression":0.3}}';
      expect(
        buildInitialLocationParams(
            initialLocatorJson: legacy, initialProgression: 0.42),
        {'initialCfi': legacy, 'initialProgression': '0.42'},
      );
      expect(
        buildInitialLocationParams(initialLocatorJson: ' epubcfi(/6/4!/4/ '),
        {'initialCfi': 'epubcfi(/6/4!/4/'},
      );
    });

    test('比例為 NaN 或無限大：不帶比例', () {
      expect(
        buildInitialLocationParams(
            initialLocatorJson: 'epubcfi(/6/4)', initialProgression: double.nan),
        {'initialCfi': 'epubcfi(/6/4)'},
      );
    });
  });
```

（檔案頂端若尚未 import `foliate_bridge_codec.dart`，沿用既有 import；測試 `extractCfi` 的同一檔已經有。）

- [x] **Step 2：執行確認失敗**

Run：`flutter test test/reader/foliate_bridge_handlers_test.dart test/reader/navigation_degraded_reason_test.dart test/reader/foliate_bridge_codec_test.dart`
Expected：編譯錯誤（找不到 `onNavigationDegraded`、`navigation_degraded_reason.dart`、`buildJumpToLocatorScript`、`buildInitialLocationParams`、`extractCfiOrRaw`）。

- [x] **Step 3：實作**

(3a) `foliate_bridge_handlers.dart`，在 `onSelectionChanged` 之後加：

```dart
  // epic-67 Issue 5：精確定位（CFI）失效、已改用概略進度時回報。
  static const onNavigationDegraded = 'onNavigationDegraded';
```

(3b) 建立 `lib/reader/navigation_degraded_reason.dart`：

```dart
/// 精確定位（CFI）失效、已降級為概略進度的原因（epic-67 Issue 5）。
enum NavigationDegradedReason {
  /// 開書時，儲存的閱讀位置失效。
  readingPosition,

  /// 點擊書籤、劃線或備註跳轉時，其記錄的位置失效。
  annotation,
}

/// 解析 JS `onNavigationDegraded` handler 的參數；無法辨識時回傳 `null`，
/// 不拋例外（比照 `extractCfi()` 等橋接解析函式的優雅退回原則）。
NavigationDegradedReason? parseNavigationDegradedReason(List<dynamic> args) {
  if (args.isEmpty || args[0] is! String) return null;
  switch (args[0] as String) {
    case 'readingPosition':
      return NavigationDegradedReason.readingPosition;
    case 'annotation':
      return NavigationDegradedReason.annotation;
    default:
      return null;
  }
}
```

(3c) `foliate_bridge_codec.dart` 新增三個頂層函式（放在 `extractCfi` 之後；確認該檔已 `import 'dart:convert';`）：

```dart
/// 取出要交給 JS 的定位字串（epic-67 Issue 5）。可解析出 CFI 時回傳 CFI；
/// 無法解析（舊格式 Readium Locator JSON、損壞字串）但非空時，回傳去空白後的
/// 原字串，讓 JS 端判定無效並走降級——若在 Dart 端提早過濾，JS 的降級就會被
/// 短路（開書靜默回書頭、點書籤毫無反應）。null 或空白回傳 null。
String? extractCfiOrRaw(String? locatorJson) {
  final cfi = extractCfi(locatorJson);
  if (cfi != null) return cfi;
  final trimmed = locatorJson?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// 產生「跳到 CFI」的 JS 呼叫字串（epic-67 Issue 5）。[fallbackProgression]
/// 為 CFI 失效時的降級進度比例；`null`、NaN、無限大都以 JS 的 `null` 傳入
/// （舊資料沒有 progression 時，JS 端只回報降級、不移動位置）。
String buildJumpToLocatorScript(String cfi, {double? fallbackProgression}) {
  final fraction =
      (fallbackProgression != null && fallbackProgression.isFinite)
          ? '$fallbackProgression'
          : 'null';
  return 'window.jumpToLocator(${jsonEncode(cfi)}, $fraction)';
}

/// 組出 index.html 的開書定位 URL 參數（epic-67 Issue 5）。沒有任何儲存位置
/// （null 或空白）時回傳空 map——單獨的進度比例沒有意義，一般開書走書頭；有
/// 儲存位置但無法解析時，原字串仍會帶入，由 JS 端判定無效並降級。
Map<String, String> buildInitialLocationParams({
  String? initialLocatorJson,
  double? initialProgression,
}) {
  final cfi = extractCfiOrRaw(initialLocatorJson);
  if (cfi == null) return const {};
  return {
    'initialCfi': cfi,
    if (initialProgression != null && initialProgression.isFinite)
      'initialProgression': '$initialProgression',
  };
}
```

- [x] **Step 4：執行確認通過**

Run：同 Step 2 的指令 → 全部通過。

- [x] **Step 5：Commit**

```bash
git add app/lib/reader app/test/reader
git commit -m "feat(epic-67): Issue 5 新增降級橋接常數、原因列舉與腳本／參數產生函式"
```

---

### Task 4：`FoliateReaderView` 與 `FoliateReaderSurface` 接線

**Files:**
- Modify: `app/lib/reader/foliate_reader_view.dart`（欄位、建構子、`jumpToLocator`、`_buildIndexUri`、`_onWebViewCreated`）
- Modify: `app/lib/reader/foliate_reader_surface.dart`（`jumpTo`）
- Modify: `app/lib/reader/reader_jump_target.dart`（只改 `progression` 欄位的文件註解）
- Modify: `app/test/reader/foliate_reader_surface_test.dart`

**Interfaces:**
- Consumes（Task 3）：`buildJumpToLocatorScript`、`buildInitialLocationParams`、`parseNavigationDegradedReason`、`FoliateBridgeHandlers.onNavigationDegraded`。
- Produces：
  - `FoliateReaderView({double? initialProgression, ValueChanged<NavigationDegradedReason>? onNavigationDegraded, ...})`。
  - `static void FoliateReaderView.jumpToLocator(GlobalKey<State<FoliateReaderView>> key, String locatorJson, {double? fallbackProgression})`。
  - `ReaderJumpTarget.progression` 的語意放寬：與 `cfi` 並存時，作為 CFI 失效的降級進度（不新增欄位，避免與既有 `progression` 重複）。

- [x] **Step 1：寫失敗的測試**

`foliate_reader_surface_test.dart` 的「所有指令靜默忽略、不拋例外」測試中，在 `surface.jumpTo(const ReaderJumpTarget(progression: 0.5));` 之後新增一行：

```dart
      surface.jumpTo(const ReaderJumpTarget(cfi: 'epubcfi(/6/4!/4/2)', progression: 0.5));
```

（View 未掛載時靜默忽略。此行在 Task 4 實作前即可編譯通過，不會是 RED；真正的 RED 在下一步新增的建構子欄位測試。）

在 `test/reader/foliate_reader_view_test.dart` 新增一個 test，確認新欄位存在且可選（沿用該檔既有的建構方式，例如檔內已有的 `FoliateReaderView(filePath: ..., onPageRendered: ..., onError: _noopError)`）：

```dart
    test('initialProgression 與 onNavigationDegraded 為選填，預設 null', () {
      const view = FoliateReaderView(
        filePath: 'x.epub',
        onPageRendered: _noop,
        onError: _noopError,
      );
      expect(view.initialProgression, isNull);
      expect(view.onNavigationDegraded, isNull);
    });
```

若該檔沒有名為 `_noop` 的頂層函式，改用檔內既有的等價寫法（例如 `() {}` 搭配非 `const` 建構）。

- [x] **Step 2：執行確認失敗**

Run：`flutter test test/reader/foliate_reader_view_test.dart test/reader/foliate_reader_surface_test.dart`
Expected：編譯錯誤（`initialProgression`、`onNavigationDegraded` 未定義）。

- [x] **Step 3：實作 `FoliateReaderView`**

(3a) 檔頂 import 加：`import 'navigation_degraded_reason.dart';`（與其他 `reader/` 內 import 同區塊）。

(3b) 在 `final String? initialLocatorJson;` 之後新增欄位：

```dart
  /// 精確定位（[initialLocatorJson]）失效時的降級進度比例（0～1）。只在開書當下
  /// 讀取一次（epic-67 Issue 5）；`null` 時降級會改開在書頭。
  final double? initialProgression;

  /// 精確定位失效、已降級為概略進度時回報（epic-67 Issue 5）。呼叫端
  /// （`ReaderScreen`）負責顯示提示；本欄位只回報事實，比照既有
  /// [onLocatorChanged] 的「JS 回報事實、Dart 決定政策」分工。
  final ValueChanged<NavigationDegradedReason>? onNavigationDegraded;
```

建構子參數列在 `this.initialLocatorJson,` 之後加 `this.initialProgression,`，在 `this.onTtsHighlightOutOfSafeWindow,` 之後加 `this.onNavigationDegraded,`。

(3c) 取代 `jumpToLocator`：

```dart
  static void jumpToLocator(
    GlobalKey<State<FoliateReaderView>> key,
    String locatorJson, {
    double? fallbackProgression,
  }) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      // 用 extractCfiOrRaw 而非 extractCfi：舊格式或損壞的定位字串也要交給 JS，
      // 由 JS 判定無效後降級並回報；Dart 端提早過濾會讓點擊毫無反應（審查 I-1）。
      final cfi = extractCfiOrRaw(locatorJson);
      if (cfi != null) {
        state._evaluate(
          buildJumpToLocatorScript(cfi, fallbackProgression: fallbackProgression),
        );
      }
    }
  }
```

(3d) `_buildIndexUri` 中把

```dart
    final cfi = extractCfi(widget.initialLocatorJson);
    if (cfi != null) params['initialCfi'] = cfi;
```

改為

```dart
    params.addAll(buildInitialLocationParams(
      initialLocatorJson: widget.initialLocatorJson,
      initialProgression: widget.initialProgression,
    ));
```

(3e) 在 `_onWebViewCreated` 中 `onLocatorChanged` handler 註冊之後新增：

```dart
    controller.addJavaScriptHandler(
      handlerName: FoliateBridgeHandlers.onNavigationDegraded,
      callback: (args) {
        final reason = parseNavigationDegradedReason(args);
        if (reason == null || !mounted) return;
        widget.onNavigationDegraded?.call(reason);
      },
    );
```

(3f) `FoliateReaderSurface.jumpTo` 改為：

```dart
  @override
  void jumpTo(ReaderJumpTarget target) {
    final cfi = target.cfi;
    final progression = target.progression;
    if (cfi != null) {
      // progression 與 cfi 並存時，作為 CFI 失效的降級進度（epic-67 Issue 5）。
      FoliateReaderView.jumpToLocator(viewKey, cfi, fallbackProgression: progression);
    } else if (progression != null) {
      FoliateReaderView.jumpToProgression(viewKey, progression);
    }
  }
```

(3g) `reader_jump_target.dart` 把 `progression` 欄位的文件註解

```dart
  /// Foliate 格式的目標進度比例（0.0～1.0），進度條拖動用；與 [cfi] 擇一。
```

改為

```dart
  /// Foliate 格式的目標進度比例（0.0～1.0）。單獨存在時是進度條拖動的跳轉目標；
  /// 與 [cfi] 並存時，是 CFI 在新版內容中失效時的降級進度（epic-67 Issue 5）。
```

- [x] **Step 4：執行確認通過**

Run：`flutter test test/reader/foliate_reader_view_test.dart test/reader/foliate_reader_surface_test.dart test/reader/reader_jump_target_test.dart`
Expected：全部通過。
Run：`flutter analyze`
Expected："No issues found!"

- [x] **Step 5：Commit**

```bash
git add app/lib/reader app/test/reader
git commit -m "feat(epic-67): Issue 5 FoliateReaderView 傳遞降級進度並回報降級事件"
```

---

### Task 5：`ReaderScreen` 接線、提示字串與畫面測試

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`（`_jumpToEpubLocator`、兩處呼叫、`FoliateReaderView` 建構、新增 `_handleNavigationDegraded`）
- Modify: `app/lib/l10n/app_zh_TW.arb`、`app_en.arb`、`app_zh.arb`、`app_zh_CN.arb`；重新產生 `app/lib/l10n/app_localizations*.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes（Task 4）：`FoliateReaderView.initialProgression`、`FoliateReaderView.onNavigationDegraded`、`ReaderJumpTarget(cfi:, progression:)`。
- Produces：ARB 鍵 `readerNavigationDegradedMessage`；SnackBar Key `reader_navigation_degraded_snackbar`（Issue 6 的 PDF 降級會沿用同一個鍵與訊息）。

- [x] **Step 1：新增 ARB 字串並產生本地化檔**

`app_zh_TW.arb`（樣板，含描述），緊接在 `readerPrefsSaveFailedMessage` 條目（含其 `@` 描述區塊）之後插入：

```json
  "readerNavigationDegradedMessage": "原位置已變更，已跳至概略進度",
  "@readerNavigationDegradedMessage": {
    "description": "書籍內容更新後，書籤、劃線、備註或上次閱讀位置的精確定位失效，已改用概略進度時的 SnackBar 提示（epic-67 Issue 5；PDF 頁碼超界降級共用，Issue 6）"
  },
```

其餘三檔（無 `@` 描述）緊接在各自的 `"readerPrefsSaveFailedMessage": "...",` 那一行之後插入：

- `app_en.arb`：`"readerNavigationDegradedMessage": "The original position has changed. Jumped to the approximate progress.",`
- `app_zh.arb`：`"readerNavigationDegradedMessage": "原位置已變更，已跳至概略進度",`
- `app_zh_CN.arb`：`"readerNavigationDegradedMessage": "原位置已变更，已跳至概略进度",`

Run：`flutter gen-l10n`
Expected：`lib/l10n/app_localizations*.dart` 出現 `readerNavigationDegradedMessage`。

- [x] **Step 2：寫失敗的畫面測試**

在 `test/screens/reader_screen_test.dart` 內，緊接 `'Foliate：initialJumpTarget.cfi 優先於資料庫既有 lastPosition'` 那個 `testWidgets` 之後，加入以下三個（沿用該測試的 `MaterialApp` 包裝與 `tester.pump` 流程）：

```dart
    testWidgets('Foliate：開書把資料庫的閱讀進度當作 CFI 失效的降級比例傳給閱讀器',
        (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        readingPositionByBookId: {
          'b_degrade_progress': const ReadingPosition(
            epubLocatorJson: 'epubcfi(/stored)',
            progress: 0.42,
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_degrade_progress',
            dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      expect(foliateView.initialLocatorJson, 'epubcfi(/stored)');
      expect(foliateView.initialProgression, 0.42);
    });

    testWidgets('Foliate：搜尋跳轉目標沒有進度比例時，不拿資料庫進度冒充（初始比例為 null）',
        (tester) async {
      final prefsManager = FakeReaderPrefsManager(
        readingPositionByBookId: {
          'b_degrade_jump_no_progress': const ReadingPosition(
            epubLocatorJson: 'epubcfi(/stored)',
            progress: 0.42,
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_degrade_jump_no_progress',
            initialJumpTarget: const ReaderJumpTarget(cfi: 'epubcfi(/jump)'),
            dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      expect(foliateView.initialLocatorJson, 'epubcfi(/jump)');
      expect(foliateView.initialProgression, isNull);
    });

    testWidgets('Foliate：閱讀器回報降級時顯示提示（開書位置與註記跳轉共用）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_degrade_snackbar',
            dependencies: fakeReaderFeatureDependencies(prefsManager: FakeReaderPrefsManager()),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView = tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      expect(foliateView.onNavigationDegraded, isNotNull);

      foliateView.onNavigationDegraded!(NavigationDegradedReason.annotation);
      await tester.pump();

      expect(find.byKey(const Key('reader_navigation_degraded_snackbar')), findsOneWidget);
      expect(find.text('原位置已變更，已跳至概略進度'), findsOneWidget);
    });
```

在檔案頂端 import 區補：`import 'package:elinkbook/reader/navigation_degraded_reason.dart';`、`import 'package:elinkbook/reader/reading_position.dart';`（若已間接 import 就不重複）。

- [x] **Step 3：執行確認失敗**

Run：`flutter test test/screens/reader_screen_test.dart --plain-name "Foliate：開書把資料庫的閱讀進度"`（再分別跑另兩個 `--plain-name`）
Expected：失敗（`initialProgression` 為 null、`onNavigationDegraded` 為 null）。

- [x] **Step 4：實作 `ReaderScreen`**

(4a) 檔頂 import 加 `import '../reader/navigation_degraded_reason.dart';`。

(4b) `_jumpToEpubLocator` 改為：

```dart
  void _jumpToEpubLocator(String locatorJson, {double? progression}) {
    // Epic 20 Issue 2：EPUB 一律使用 FoliateReaderView。
    // epic-67 Issue 5：progression 是精確定位失效時的降級進度（可為 null，
    // 例如舊資料沒有記錄）。
    _surface.jumpTo(ReaderJumpTarget(cfi: locatorJson, progression: progression));
  }
```

(4c) `_openNotesSheet` 內兩個呼叫點：

```dart
          if (locatorJson != null) {
            _jumpToEpubLocator(
              locatorJson,
              progression: item.highlight?.progression ?? item.note?.progression,
            );
          }
```

```dart
          if (bookmark.epubLocatorJson != null) {
            _jumpToEpubLocator(bookmark.epubLocatorJson!,
                progression: bookmark.progression);
          }
```

目錄（`_openToc` 的 `_jumpToEpubLocator((entry as TocEntry).locatorJson)`）**不改**：目錄項目來自目前開著的書，不是舊版記錄。

(4d) 在 `FoliateReaderView(` 建構中，`initialLocatorJson: ...` 之後新增：

```dart
          // epic-67 Issue 5：精確定位失效時的降級進度。搜尋跳轉目標只在自己帶有
          // 進度比例時才使用——不拿資料庫的閱讀進度冒充（那是另一個位置）。
          initialProgression: widget.initialJumpTarget?.cfi != null
              ? widget.initialJumpTarget?.progression
              : _initialPosition?.progress,
          onNavigationDegraded: _handleNavigationDegraded,
```

(4e) 在 `_showPrefsSaveFailureNotice` 附近新增：

```dart
  /// 精確定位失效、已降級為概略進度（epic-67 Issue 5）。開書位置與註記跳轉
  /// 共用同一則提示。
  void _handleNavigationDegraded(NavigationDegradedReason reason) {
    if (!mounted) return;
    // 連續點擊多個失效的書籤時，先清掉前一則，讓使用者立刻看到最新回饋，
    // 不讓提示排隊累積（審查 M-1）。
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('reader_navigation_degraded_snackbar'),
        content: Text(AppLocalizations.of(context)!.readerNavigationDegradedMessage),
      ),
    );
  }
```

- [x] **Step 5：執行確認通過**

Run：`flutter test test/screens/reader_screen_test.dart`
Expected：全部通過（含既有案例）。
Run：`flutter analyze` → "No issues found!"
Run：`node tool/check_l10n_hardcoded_strings.js` → 無新違規。

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/lib/l10n app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-67): Issue 5 ReaderScreen 傳遞降級進度並顯示降級提示"
```

---

### Task 6：真機整合測試、文件同步與收尾

**Files:**
- Create: `app/integration_test/foliate_navigation_degrade_test.dart`
- Modify: `docs/epics/epic-67-book-update-detection/issues.md`（Issue 5 狀態與措辭）
- Modify: `docs/epics/epic-67-book-update-detection/epic.md`（待辦）

**Interfaces:**
- Consumes：`FoliateReaderView`（新參數）、`FoliateReaderView.jumpToLocator(..., fallbackProgression:)`。

- [x] **Step 1：寫真機整合測試**

建立 `integration_test/foliate_navigation_degrade_test.dart`（沿用 `foliate_epub_reader_view_test.dart` 的 `_stageAssetAsFile` 寫法與 `pumpLocalizedWidget`）：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/navigation_degraded_reason.dart';
import '../test/support/pump_localized_widget.dart';

/// epic-67 Issue 5：定位失效時的降級，必須在真實 WebView 驗證（一般 widget test
/// 的 WebView 是假的，觀察不到 JS 行為）。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('開書時 CFI 章節索引超界：不卡死、回報 readingPosition 降級', (tester) async {
    final path = await _stageAssetAsFile('test/fixtures/sample.epub', 'degrade_open.epub');
    addTearDown(() async {
      final f = File(path);
      if (await f.exists()) await f.delete();
    });

    final rendered = Completer<void>();
    final degraded = Completer<NavigationDegradedReason>();
    String? errorMessage;

    await pumpLocalizedWidget(
      tester,
      FoliateReaderView(
        filePath: path,
        initialLocatorJson: 'epubcfi(/6/400!/4/2)', // 章節索引遠超過 sample.epub 的章數
        initialProgression: 0.5,
        onPageRendered: () {
          if (!rendered.isCompleted) rendered.complete();
        },
        onError: (message) {
          errorMessage = message;
          if (!rendered.isCompleted) rendered.complete();
        },
        onNavigationDegraded: (reason) {
          if (!degraded.isCompleted) degraded.complete(reason);
        },
      ),
    );

    await rendered.future.timeout(const Duration(seconds: 15));
    expect(errorMessage, isNull, reason: '不得因定位失效而載入失敗：$errorMessage');
    expect(
      await degraded.future.timeout(const Duration(seconds: 5)),
      NavigationDegradedReason.readingPosition,
    );
  });

  testWidgets('開書後跳轉到失效 CFI：回報 annotation 降級', (tester) async {
    final path = await _stageAssetAsFile('test/fixtures/sample.epub', 'degrade_jump.epub');
    addTearDown(() async {
      final f = File(path);
      if (await f.exists()) await f.delete();
    });

    final key = GlobalKey<State<FoliateReaderView>>();
    final rendered = Completer<void>();
    final degraded = Completer<NavigationDegradedReason>();

    await pumpLocalizedWidget(
      tester,
      FoliateReaderView(
        key: key,
        filePath: path,
        onPageRendered: () {
          if (!rendered.isCompleted) rendered.complete();
        },
        onError: (_) {},
        onNavigationDegraded: (reason) {
          if (!degraded.isCompleted) degraded.complete(reason);
        },
      ),
    );
    await rendered.future.timeout(const Duration(seconds: 15));

    FoliateReaderView.jumpToLocator(
      key,
      'epubcfi(/6/400!/4/2)',
      fallbackProgression: 0.5,
    );

    expect(
      await degraded.future.timeout(const Duration(seconds: 5)),
      NavigationDegradedReason.annotation,
    );
  });
}
```

- [x] **Step 2：檢查鍵值腳本並在真機執行**

Run（`app/`）：`node tool/check_integration_keys.js` → 無新違規。
Run：`flutter devices` 取得裝置 ID，再 `flutter test integration_test/foliate_navigation_degrade_test.dart -d <device-id>`
Expected：兩個測試通過。**若本機沒有可用的真機或模擬器，如實在 PR 說明標註「整合測試未跑」，不要宣稱通過**；此步驟交由人類在真機補跑。

- [x] **Step 3：文件同步**

- `issues.md`：Issue 5 的橋接契約段落中，「`ReaderJumpTarget` 新增概略進度欄位」改為「`ReaderJumpTarget` 沿用既有 `progression` 欄位作為降級進度（與 `cfi` 並存時的語意，不新增欄位）」；總表 Issue 5 狀態改為「🟡 實作中」或實際進度；補一句「實測發現：章節索引超界會讓開書卡死、跳轉位置不動；元素路徑不存在不算失敗，詳見 `plans/plan-issue-5.md`」。
- `epic.md`：待辦中補註 Issue 5 plan 已完成。

- [x] **Step 4：完整測試（此 Task 是最後一個，執行一次完整套件）**

Run：`flutter analyze` → "No issues found!"
Run：`flutter test`
Expected：全部通過。若有失敗，先判斷是否為本 Issue 造成（特別是 `foliate_bridge_handlers_test`、`reader_screen_test`），不要以放寬斷言處理。
Run（`app/tool/foliate_touch_harness/`）：`node run-all.mjs` → 全部 PASS。
Run：`node tool/check_foliate_es_compat.js`、`node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js` → 皆無新違規。

- [x] **Step 5：Commit**

```bash
git add app/integration_test docs/epics/epic-67-book-update-detection
git commit -m "test(epic-67): Issue 5 新增降級真機整合測試並同步工單文件"
```

---

## 自我審查

**Spec 涵蓋：** 開書進度傳遞鏈（Task 1、3、4、5）、精確定位失敗改用進度比例（Task 1、2）、橋接契約常數與列舉與回呼（Task 3、4）、Dart 端提示（Task 5）、跨裝置對稱性（降級邏輯與檔案新舊無關，同一條路徑涵蓋；無需額外程式碼）、新增字串四語系（Task 5）、真機驗證（Task 6）。PDF 頁碼超界屬 Issue 6，不在本計畫。

**與 `issues.md` 的差異（已在 Task 6 同步）：** `issues.md` 寫「`ReaderJumpTarget` 新增概略進度欄位」，但既有的 `progression` 欄位已能表達，新增欄位只會造成兩個欄位語意重疊，故沿用並放寬其文件語意。

**型別一致性：** `onNavigationDegraded`（handler 字串、`FoliateBridgeHandlers` 常數、`FoliateReaderView` 回呼欄位）、`NavigationDegradedReason`（Task 3 定義，Task 4、5、6 使用）、`jumpToLocator(..., fallbackProgression:)`（Task 3 腳本產生器的參數名與 Task 4 一致）、`window.jumpToLocator(cfi, fallbackProgression)`（Task 2 的 JS 簽章與 Task 3 產生的腳本字串一致）。

**已知限制：** 舊書籤／劃線若沒有 `progression`，精確定位失敗時 JS 端只回報降級、不移動位置，但提示文字仍寫「已跳至概略進度」，與實際略有出入。此情況限於舊資料，屬可接受取捨；若真機回報困擾，再另立工單區分兩種提示。
