# Epic 46 Issue 1 — 排版方向自動偵測改為全書預掃 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal：** 「採用書籍排版」模式下，開書時先掃過整本書（OPF `primary-writing-mode`、manifest 內所有 CSS、必要時 XHTML 內嵌樣式），只要任一處宣告直排就判定為直排。偵測結果與閱讀位置無關，也要能辨識 `-webkit-writing-mode` 和舊式 `tb-rl`。

**Architecture：** 只修改 `app/android/app/src/main/assets/foliate/main.js`。新增頂層 async 函式 `detectBookWritingMode(book)`，在 `openBook()` 的 `makeBook()` 之後、`view.open(book)` 之前 `await`，並把結果寫入既有的 `detectedBookWritingMode`。既有的 transformTarget 延遲偵測保留下來，作為「書本沒有 EPUB manifest」（KF8 等）時的回退路徑，並一併套用擴充後的 Regex。Dart 端（`foliate_reader_view.dart:658`→`reader_screen.dart:1897`）已經會接收 `onPageRendered` 的第一個參數，**不需要修改**。

**Tech Stack：** 瀏覽器 ES module（`main.js`）、Puppeteer（`app/tool/foliate_touch_harness`）、Node。

**Discovery 決策來源：** `docs/epics/epic-46-writing-mode-autodetect/epic.md`「開發記錄」2026-09-24 條目；詞彙見 `CONTEXT.md`「排版方向」和「偵測排版方向」。

## 審查修訂紀錄（`reviews/review-plan-issue-1.md`，建議修正後執行，0 Critical／3 Important／4 Minor）

- **I-1（採納；審查所附的規格依據不正確）**：`primary-writing-mode` 並不是 EPUB 3 Packages 規格定義的保留 property。它原本是 Kindle 出版指南的慣例寫法 `<meta name="…" content="…"/>`；EPUB 3 未加前綴的 `property` 只能使用規格保留的詞彙，這個名稱並不在其中。不過有些工具確實會寫成 `<meta property="primary-writing-mode">vertical-rl</meta>`，容錯支援幾乎沒有成本，所以採納：選擇器同時涵蓋 `name` 和 `property` 兩種寫法，值依序讀 `content` 屬性、再讀 `textContent`；Task 1 新增案例 D-2。
- **I-2（採納，但不採用審查建議的 Regex）**：原本的 `([\s\S]*?)\2` 遇到未閉合引號時，每次都會一路掃到文件結尾，最壞情況是 O(n²)，這個問題屬實。但審查建議的 `([^"']*)` 會造成漏判：雙引號包住的屬性值本來就可以含單引號，例如 `style="font-family:'Noto Serif'; writing-mode: vertical-rl"`，`[^"']*` 會停在 `'`，接著比對 `\2` 失敗，這筆就被跳過了。改為依引號種類分成兩個分支：`"([^"]*)"|'([^']*)'`，同時解決回溯問題和上面這種情況。Task 1 新增案例 C-2（`style="…"` 內含單引號）。
- **I-3（採納）**：spine 可能包含非 XHTML 項目，例如 SVG 頁面。在累加計數前，先依 `mediaType` 過濾出 `application/xhtml+xml`／`text/html`（比較前先轉小寫，同時處理 M-2）。
- **M-1（採納；審查舉的例子不成立）**：`div/*c*/-webkit-writing-mode` 去掉註解後變成 `div-webkit-writing-mode`，`-webkit-` 前面是 `v`，`[^-]` 仍然會匹配，所以審查舉的例子並不會漏判。不過把註解換成一個空白比較接近 CSS 分詞的語意，也沒有成本，所以改用 `' '`。
- **M-2（採納）**：`mediaType` 先轉小寫再比較。附帶說明：vendor 的 `Loader` 本身是用完全相同的字串比對（`epub.js:944`），大小寫不符的 CSS 在渲染端也不會經過 transformTarget；這裡只是讓預掃比較寬容，不改變渲染行為。
- **M-3（維持不支援 `-ms-`，但更正註解）**：原本註解寫「`[^-]` 是為了避免 `-ms-` 等其他前綴被誤認」，這個理由是我自己推測的，沒有根據。正確的判準應該是：**偵測結果要跟 WebView 實際的渲染方式一致**。Chromium 會把 `writing-mode: tb-rl`／`tb` 當成舊式別名，實際渲染成直排；`-epub-`／`-webkit-` 前綴也都有效；但 `-ms-writing-mode` 在 Chromium 上完全沒有作用，書本實際上會呈現橫排。如果把它偵測成直排，反而會和書本在其他 Chromium 閱讀器上的樣子不一致。所以維持不支援，並依這個判準改寫 Task 2 Step 1 的註解。
- **M-4（採納）**：Task 1 Step 2 補充說明：案例 E 修改前會失敗，是因為舊程式誤判成直排，不是因為漏判。

## 資料流（修改後）

```
openBook()
 ├─ makeBook()
 ├─ ★ detectBookWritingMode(book)          ← 新增；isIndexMode 時略過
 │     ├─ book.resources?.manifest 不存在 → null（KF8 等，走下方回退路徑）
 │     ├─ OPF <meta name|property="primary-writing-mode"> 值為 vertical-* → 'vertical'
 │     ├─ manifest 所有 text/css：book.loadText(href) → 去註解 → Regex → 命中即回傳 'vertical'
 │     ├─ spine 中 XHTML／HTML 項目前 N 個：<style>…</style> 和 style="…" → Regex → 命中即回傳 'vertical'
 │     └─ 都沒命中 → 'horizontal'
 │   → detectedBookWritingMode = 結果（null 時維持 null）
 ├─ transformTarget 'data' 監聽器（既有）：只在 detectedBookWritingMode === null 時才判讀（回退路徑）
 ├─ view.open(book) → view.init()
 └─ 第一次 relocate：initialPrefs.writingMode ?? detectedBookWritingMode ?? 'horizontal'（既有，不變）
```

## Global Constraints

- **不修改釘定的 vendor 檔案**（`epub.js`／`paginator.js`／`view.js` 等，ADR 0011）。只使用它們的公開欄位：`book.resources.manifest`（`{href, mediaType, ...}`，`epub.js:781`）、`book.resources.spine`／`getItemByID()`、`book.resources.opf`（XMLDocument）、`book.loadText(href)`。
- **使用者手動覆寫優先**：`initialPrefs.writingMode` 有值時，偵測結果不影響實際套用的方向（既有的 `??` 順序不變），**而且略過預掃**（程式審查 M-2 修訂，見「需人類確認的設計決定」第 2 點）。
- **索引模式（`isIndexMode`）略過預掃**：全文索引會對每本書開一次 headless WebView，但索引不需要排版方向，不應增加成本。
- 預掃失敗（例外）時一律吞掉並退回 `null`，也就是回到既有的延遲偵測，**不得讓開書失敗**。
- 不引入新的較新 ES API：只用 `for…of`、`RegExp.test`、`String.replace`，**不用** `matchAll`／`replaceAll`（見 `_esCompatPolyfillJs` 與 `app/tool/check_foliate_es_compat.js`）。
- 所有註解、文件、commit 訊息一律正體中文。
- 測試範圍：本 Issue 不修改任何 Dart 程式碼，不需要跑 `flutter test`／`flutter analyze`。回歸以 `node app/tool/foliate_touch_harness/run-all.mjs` 全部 PASS 為準。

## 需人類確認的設計決定

1. **XHTML 內嵌樣式只在 CSS 和 metadata 都沒命中時才掃描，而且上限是 spine 的前 `N = 20` 個文件。** 掃描外部 CSS 很便宜（通常只有 1～5 個幾 KB 的檔案），但 XHTML 是全書正文，數百章的書全部解壓會明顯拖慢開書。內嵌樣式的直排宣告通常出現在最前面幾章（封面／扉頁／第一章都會套用），20 是經驗值。調整方式：修改 Task 2 的常數 `INLINE_STYLE_SCAN_LIMIT` 即可；如果決定完全不掃 XHTML，就刪掉 Task 2 的第 3 段和 Task 1 的場景 C。
2. **使用者已手動覆寫時略過預掃**（2026-09-25 程式審查 M-2 修訂，推翻原本「仍照常預掃」的決定）。原本的理由是「切回採用書籍排版時需要偵測值」，但查證後不成立：`main.js` 的 `onPageRendered` 回傳 `initialPrefs.writingMode ?? detectedBookWritingMode`，有覆寫時永遠回傳覆寫值，Dart 端 `_autoDetectedWritingMode` 存的也是覆寫值，預掃結果從未傳到 Dart。因此照常預掃純屬多餘成本，改為 `!isIndexMode && !initialPrefs.writingMode` 時才預掃。「覆寫狀態下切回採用書籍排版，拿到的是覆寫值」是既有行為，不在本 Issue 範圍。
3. **Regex 的邊界字元維持原本的 `[^-]`**，不另外收緊成 `[^-\w]`。目的是只擴充前綴和數值，不改變既有的匹配語意（外科手術式修改）。前綴與數值的取捨依「偵測結果要跟 WebView 實際渲染一致」判斷（見審查修訂 M-3）：支援 `-epub-`／`-webkit-`／`tb-rl`／`tb`，不支援 `-ms-`。

## 檔案結構

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/tool/foliate_touch_harness/scenario-writing-mode-autodetect.mjs` | 新增 | 7 本合成 EPUB，斷言 `onPageRendered` 回報的排版方向；場景 A 另外量測實際後果（診斷用） |
| `app/android/app/src/main/assets/foliate/main.js` | 修改 | Regex 擴充、新增 `detectBookWritingMode()`、`openBook()` 接線、更新註解 |
| `app/tool/foliate_touch_harness/README.md` | 修改 | 補上場景說明 |
| `docs/prd.md` | 修改 | FR-06 措辭改為依 CSS／`primary-writing-mode` 判斷 |
| `docs/epics.md` | 修改 | Epic 46 列的備註 |

---

## Task 1：重現（紅燈）——新增 harness 回歸場景

**Files：** 新增 `app/tool/foliate_touch_harness/scenario-writing-mode-autodetect.mjs`

- [x] **Step 1：撰寫場景。** 比照 `scenario-preload-stale-layout.mjs` 的寫法，用 `buildStoredZip` 在記憶體中組出 EPUB（不提交二進位 fixture）。共用一個 `buildEpub({ opfMeta, cssFiles, chapters })` 產生器，開書時固定傳入 `writingMode: null`（**不能省略**：`launchHarnessPage` 的預設值是 `'horizontal'`，傳 `null` 才能模擬「採用書籍排版」，也就是 `initialPrefs.writingMode ?? detected` 會走到偵測值）。每個案例只需要檢查 `harnessEvents(page)` 中第一個 `onPageRendered` 的 `args[0]`。

  | 案例 | 構造 | 預期 | 修改前 |
  |---|---|---|---|
  | A 第二個 CSS＋`-webkit-`＋內層元素（對應《蘇東坡新傳》） | 各章 `<link>` 依序連到 `base.css`（`body{margin:0}`）和 `vertical.css`（`.main{-webkit-writing-mode:vertical-rl}`），內文包在 `<div class="main">` 裡 | `vertical` | `horizontal`（紅燈） |
  | B 直排 CSS 只被後面的章節引用 | 第 1 章只連 `base.css`，第 3 章才連 `html{writing-mode:vertical-rl}` 的 `v.css`，從第 1 章開書 | `vertical` | `horizontal`（紅燈） |
  | C XHTML 內嵌 `<style>` | 沒有外部 CSS，第 1 章 `<head><style>body{-epub-writing-mode:vertical-rl}</style>` | `vertical` | `horizontal`（紅燈） |
  | C-2 XHTML `style=""` 屬性（值內含單引號） | 沒有外部 CSS，也沒有 `<style>`，第 1 章 `<div style="font-family:'Noto Serif'; -webkit-writing-mode: vertical-rl">` | `vertical` | `horizontal`（紅燈） |
  | D OPF metadata（Kindle 慣例寫法） | 沒有任何直排 CSS，OPF 有 `<meta name="primary-writing-mode" content="vertical-rl"/>` | `vertical` | `horizontal`（紅燈） |
  | D-2 OPF metadata（`property` 寫法） | 同 D，改為 `<meta property="primary-writing-mode">vertical-rl</meta>` | `vertical` | `horizontal`（紅燈） |
  | E 反例：註解與橫排 | `base.css` 只有 `/* writing-mode: vertical-rl */` 和 `body{writing-mode:horizontal-tb}` | `horizontal` | 修改前**會誤判成 `vertical`**（Regex 沒有去除註解），修改後應為 `horizontal` |

  場景 A 另外輸出**診斷用數值**（`report` 的 detail 欄位，不作為 PASS 條件）：第一個章節 iframe 裡 `documentElement`、`body`、`.main` 三者的 `getComputedStyle().writingMode`，以及 `renderer.getContents()[0].doc.documentElement.style.columnWidth`。這是用來驗證 Discovery 的推測：「html／body 被強制成 `horizontal-tb`，但 `.main` 仍然是 `vertical-rl`，所以 Paginator 用橫排的欄寬去排直排內容」。修改前後的數值都要記錄到 `epic.md`。

- [x] **Step 2：確認紅燈。**

  ```bash
  cd app/tool/foliate_touch_harness && node scenario-writing-mode-autodetect.mjs
  ```

  預期：A、B、C、C-2、D、D-2、E 全部 FAIL，且 A 的診斷數值有印出來。注意兩種失敗的原因不同：A～D-2 是舊程式**漏判**（回報 `horizontal`）；E 則是舊程式沒有去除 CSS 註解，把註解裡的宣告**誤判**成 `vertical`。如果 A 回報 `vertical`，代表對 Regex 或 transformTarget 時序的理解有誤，**停下來回報，不要繼續**。

- [x] **Step 3：把場景 A 的修改前診斷數值寫進 `epic.md`**，作為「後果已重現」的證據。

---

## Task 2：實作 `detectBookWritingMode()`（綠燈）

**Files：** 修改 `app/android/app/src/main/assets/foliate/main.js`

- [x] **Step 1：擴充 Regex，並新增判讀 helper**（替換 `main.js:99-104`，註解同步改寫）：

  ```js
  // 判斷一段 CSS 文字是否宣告了直排（epic-17 Issue 4，FR-06；epic-46 擴充）。
  // 判準：偵測結果要跟 WebView（Chromium）實際的渲染方式一致——
  // 標準屬性和 -epub-／-webkit- 前綴都有效；數值除了 vertical-rl/vertical-lr，
  // Chromium 也把舊式的 tb-rl/tb 當成別名渲染成直排，所以一併涵蓋。
  // -ms-writing-mode 在 Chromium 上沒有作用（書本實際呈現橫排），
  // 所以刻意不認。horizontal-tb 或其他數值都視為「未宣告直排」。
  const WRITING_MODE_DECLARATION_RE =
    /(?:^|[^-])(?:-epub-|-webkit-)?writing-mode\s*:\s*(?:vertical-(?:rl|lr)|tb(?:-rl)?)\b/i

  // CSS 註解內的宣告不算數（例如被作者註解掉的 writing-mode）。註解換成
  // 一個空白而不是直接刪除，避免前後的 token 黏在一起。
  function declaresVerticalWritingMode(cssText) {
    return WRITING_MODE_DECLARATION_RE.test(String(cssText).replace(/\/\*[\s\S]*?\*\//g, ' '))
  }
  ```

- [x] **Step 2：修改 `detectedBookWritingMode` 宣告處的註解**（`main.js:106-109`），改為說明「開書前由 `detectBookWritingMode()` 預掃全書定案；只有書本沒有 EPUB manifest 時（KF8 等）才由 transformTarget 延遲判讀第一個 CSS」。

- [x] **Step 3：新增 `detectBookWritingMode(book)`**（放在 `openBook()` 之前）：

  ```js
  // epic-46：XHTML 內嵌樣式掃描上限（見 plan-issue-1.md「需人類確認的設計決定」#1）。
  const INLINE_STYLE_SCAN_LIMIT = 20

  /**
   * 開書前預掃整本書，判定「偵測排版方向」（CONTEXT.md）：任一處宣告直排
   * 即為 'vertical'，否則為 'horizontal'。結果與閱讀位置無關。
   * 書本沒有 EPUB manifest（KF8 等）時回傳 null，交由 transformTarget
   * 延遲判讀的既有回退路徑處理。
   * 刻意不採用 page-progression-direction：阿拉伯文等由右至左的橫排書籍
   * 同樣是 rtl（見 epic-46 epic.md）。
   */
  async function detectBookWritingMode(book) {
    const resources = book.resources
    if (!resources?.manifest) return null

    // 有兩種寫法：Kindle 慣例的 <meta name="…" content="…"/>，以及部分工具
    // 輸出的 <meta property="…">值</meta>（值放在文字節點）。
    const metaEl = resources.opf?.querySelector(
      'meta[name="primary-writing-mode"], meta[property="primary-writing-mode"]',
    )
    const meta = metaEl?.getAttribute('content') || metaEl?.textContent
    if (meta && /^\s*vertical/i.test(meta)) return 'vertical'

    for (const item of resources.manifest) {
      if (item.mediaType?.toLowerCase() !== 'text/css') continue
      const css = await book.loadText(item.href).catch(() => null)
      if (css && declaresVerticalWritingMode(css)) return 'vertical'
    }

    // style 屬性值依引號種類分成兩個分支，並限定不能跨越同種引號：
    // 避免遇到未閉合的引號時一路回溯到文件結尾；同時讓雙引號內含單引號
    // 的值（例如 font-family:'Noto Serif'）也能完整取到。
    const INLINE_STYLE_RE = /<style[^>]*>([\s\S]*?)<\/style>|\sstyle\s*=\s*(?:"([^"]*)"|'([^']*)')/gi
    let scanned = 0
    for (const { idref } of resources.spine) {
      if (scanned >= INLINE_STYLE_SCAN_LIMIT) break
      const item = resources.getItemByID(idref)
      if (!item) continue
      // 只掃 XHTML／HTML；spine 裡的 SVG 等其他項目不佔掃描上限。
      const type = item.mediaType?.toLowerCase()
      if (type !== 'application/xhtml+xml' && type !== 'text/html') continue
      scanned++
      const xhtml = await book.loadText(item.href).catch(() => null)
      if (!xhtml) continue
      INLINE_STYLE_RE.lastIndex = 0
      let m
      while ((m = INLINE_STYLE_RE.exec(xhtml)) !== null) {
        const styleText = m[1] ?? m[2] ?? m[3] ?? ''
        if (declaresVerticalWritingMode(styleText)) return 'vertical'
      }
    }
    return 'horizontal'
  }
  ```

  > 實作者注意：`book.loadText` 是 `EPUB` 類別的實例欄位（`epub.js:1165`）。如果實際在 harness 裡取不到，改從 `book.sections` 找對應的 `loadText`（`epub.js:1220`，但只有 spine 項目有），並把查證結果寫進本計畫。這一步查證完成前不要繼續 Step 4。

- [x] **Step 4：在 `openBook()` 接線。** 在 `makeBook()` 之後、`book.transformTarget?.addEventListener` 之前加入：

  ```js
  // epic-46：開書前預掃全書定案「偵測排版方向」，不再依賴「第一個被載入的
  // CSS」（該 CSS 會隨閱讀位置改變）。索引模式不需要排版方向，略過。
  // 預掃失敗時維持 null，回退到下方 transformTarget 延遲判讀，不影響開書。
  if (!isIndexMode) {
    detectedBookWritingMode = await detectBookWritingMode(book).catch(() => null)
  }
  ```

  同時把 transformTarget 監聽器內的 `WRITING_MODE_DECLARATION_RE.test(css)` 改為 `declaresVerticalWritingMode(css)`，並把它上方的註解改為「回退路徑」語意。`if (detectedBookWritingMode === null)` 這個條件維持不變：預掃有結果時就不會再進這一段。

- [x] **Step 5：跑場景，確認綠燈。**

  ```bash
  cd app/tool/foliate_touch_harness && node scenario-writing-mode-autodetect.mjs
  ```

  預期：A～E（含 C-2、D-2）全部 PASS。場景 A 的診斷數值應該變成 html／body／`.main` 三者都是 `vertical-rl`。把修改後的數值補進 `epic.md`，和 Task 1 Step 3 的數值並列。

- [x] **Step 6：變異驗證。** 暫時把 Step 4 的預掃呼叫註解掉，重跑場景：A、B、C、C-2、D、D-2 應該回到 FAIL（E 會因為 Step 1 的去註解邏輯仍然 PASS，這是預期結果）。確認後還原。

- [x] **Step 7：全部回歸與 ES 相容性檢查。**

  ```bash
  cd app/tool/foliate_touch_harness && node run-all.mjs
  cd ../.. && node tool/check_foliate_es_compat.js
  ```

  預期：`整體結果：全部 PASS`；ES 相容性掃描沒有新增警告。

- [x] **Step 8：Commit。**

  ```bash
  git add app/android/app/src/main/assets/foliate/main.js app/tool/foliate_touch_harness/scenario-writing-mode-autodetect.mjs
  git commit -m "fix(reader): 排版方向自動偵測改為開書前預掃全書"
  ```

---

## Task 3：文件同步

**Files：** `app/tool/foliate_touch_harness/README.md`、`docs/prd.md`、`docs/epics.md`

- [x] **Step 1：README 場景清單**新增 `scenario-writing-mode-autodetect.mjs` 一行，格式比照 `scenario-preload-stale-layout.mjs`（`README.md:38`）。
- [x] **Step 2：PRD FR-06**（`docs/prd.md:114`）措辭改為：「開啟 ePub3 時，依書本 CSS（含 `-epub-`／`-webkit-` 前綴與內嵌樣式）或 OPF `primary-writing-mode` 中繼資料是否宣告直排，自動判斷排版方向（全書任一處宣告直排即為直排，否則為橫排）；不做語言猜測。」KF8 那段括號原文保留。並在 frontmatter 的 `changes` 追加一筆 2026-09-24 紀錄。
- [x] **Step 3：`docs/epics.md` 第 47 列**：備註更新為「Issue 1 已完成」（標題用詞與 Active 狀態已在 Discovery 階段更新）。
- [x] **Step 4：Commit。**

---

## Task 4：真機驗證（人類）

- [x] **Step 1：** `flutter build apk --debug` 後安裝到真機，把《蘇東坡新傳》的版面設定排版方向設為「採用書籍排版」，確認：頁首／頁尾是直排版面、分欄正常，沒有「橫排欄寬排直排內容」的情況，而且翻頁方向正確。
- [x] **Step 2：** 從書本中段（非第一章）關閉後重新開啟，確認結果仍然是直排（對應 Discovery 事實 2）。
- [x] **Step 3：** 開一本已知是橫排的 EPUB，以及一本 TXT 合成書，確認仍然判定為橫排、沒有誤判。
- [x] **Step 4：** 主觀比較一本大型 EPUB（數百章）修改前後的開書時間，確認沒有明顯變慢；如果變慢，回頭調整 `INLINE_STYLE_SCAN_LIMIT`。
- [x] **Step 5：** 結果記錄到 `epic.md`，發 PR。

## Review Focus

1. **邊緣案例：只在某個 `.poem` 類別宣告直排的橫排書**，會依「任一處即直排」的規則被判定為直排。這是 Discovery 接受的取捨，逃生口是「強制橫排」。審查時只需確認這個取捨有寫在 `CONTEXT.md` 和 `epic.md` 裡，不需要修正。
2. **`book.loadText` 會不會觸發 transformTarget 的 `data` 事件**：Task 2 Step 3 直接呼叫 `book.loadText`，走的應該是 `EPUB` 實例欄位、不經過 `Loader`，所以不會發出事件。如果實際上會經過 Loader（例如回傳的是轉換後、帶有我們 `--overlayer-highlight-opacity` 附加規則的文字），也不影響判讀結果，但需要在 harness 裡確認沒有重複或提早觸發副作用。
3. **KF8（AZW3）**：`mobi.js` 產生的 book 沒有 `resources.manifest`，會走回退路徑，行為與修改前完全相同（只是 Regex 擴充了）。本計畫不額外處理 KF8 的全書預掃。
