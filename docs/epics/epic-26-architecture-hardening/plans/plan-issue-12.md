# TTS 安全視窗判斷抽成純函式 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `main.js` 焊死在 `draw-annotation` DOM 事件監聽器裡的 TTS 安全視窗（Safe Viewport）翻頁判斷邏輯，抽成一個零 DOM 依賴、可被 Node 直接單元測試的純函式，取代目前只能靠字串比對原始碼、測不到真正行為的 Dart regression-guard 測試。

**Architecture：** 新增獨立檔案 `tts-safe-window.js`（比照同目錄既有 `progress.js` 的「零 DOM 依賴、可被 Node 匯入」模式），把安全視窗常數與判斷邏輯（含原本焊在呼叫端的「needNext 優先於 needPrev」順序規則）一併搬進去，`main.js` 改為匯入呼叫。新增比照既有 `test_section_progress_density.mjs` 慣例的 Node 測試腳本。純重構，不改變任何現有行為。

**Tech Stack：** JavaScript（ES Module，Android WebView 執行環境）、Node.js（開發期驗證腳本，內建 `node:assert/strict`，不需要 npm install 或任何測試框架）、Dart／`flutter_test`（既有 regression-guard 測試更新）。

**Spec：** `docs/epics/epic-26-architecture-hardening/issues.md` Issue 12（把 TTS 安全視窗判斷抽成純函式，讓它真正可單元測試）；設計細節出自 2026-08-29 `/grilling` 會談，完整候選背景見 `docs/research/architecture-review-epic34-tts.md` 候選 1。

## Global Constraints

- 所有程式碼註解、commit message 一律使用正體中文（CLAUDE.md）。
- `main.js` 是「非 vendored、可自由修改的橋接腳本」，與 `paginator.js`／`view.js` 等完全禁止修改的 vendored 檔案不同（CLAUDE.md「不可逆的技術決策」小節）。
- `main.js` 第 5 行 `const view = document.getElementById('view')` 是模組頂層就會執行的程式碼——任何要被 Node 直接匯入單元測試的純函式，都不能定義在 `main.js` 本身裡，必須是獨立、零 DOM 依賴的檔案（比照既有 `progress.js` 先例）。
- Node 驗證腳本比照既有 `app/tool/test_section_progress_density.mjs` 慣例：不需要 npm install，只用 `node:assert/strict`，手動執行 `node app/tool/test_tts_safe_window.mjs`；這個 repo 目前沒有接 CI，不需要另外接管線。
- 每完成一個 Task 內的 Step，把該 Step 前面的 `- [ ]` 改成 `- [x]`（SDD 工作流程慣例）。
- 測試執行範圍：每個 Task 只需要跑「這次異動實際觸及」的測試（`app/test/reader/foliate_reader_view_test.dart` 與新的 Node 腳本），不需要每次都跑全套 `flutter test`；完整 `flutter test`（無參數）只在本計畫最後一個 Task 完成時跑一次。
- 純重構、不改變任何行為——不需要真機重新驗證安全視窗翻頁邏輯本身（`epic-34-tts-readalong` Issue 11 真機驗收的橫排/直排翻頁行為已確認正確，本次不變動該行為，只變動它的可測試性）。

---

### Task 1：新增 `tts-safe-window.js` 純函式與 Node 單元測試

**Files:**
- Create: `app/android/app/src/main/assets/foliate/tts-safe-window.js`
- Create: `app/tool/test_tts_safe_window.mjs`
- Modify: `app/tool/README.md`

**Interfaces:**
- Produces: `tts-safe-window.js` 匯出 `function resolveTtsSafeWindowDirection(firstRect, lastRect, iframeRect, viewportRect, isVertical)`，回傳 `'next' | 'prev' | null`。`firstRect`／`lastRect`／`iframeRect`／`viewportRect` 皆為 `{left, right, top, bottom}` 形狀的純數字物件（或 `null`/`undefined`）——`DOMRect` 本身即符合此形狀，呼叫端不需轉型。`TTS_SAFE_WINDOW_MIN`（0.2）／`TTS_SAFE_WINDOW_MAX`（0.8）常數不對外匯出，僅供函式內部使用。Task 2 會匯入並呼叫這個函式。

- [x] **Step 1: 寫測試腳本（先寫完整份，這支腳本本身就是測試——比照 `test_section_progress_density.mjs` 慣例，不是逐一累加）**

建立 `app/tool/test_tts_safe_window.mjs`：

```js
// epic-26-architecture-hardening Issue 12：TTS 安全視窗（Safe Viewport）
// 判斷邏輯的純邏輯驗證腳本。tts-safe-window.js 零 DOM 依賴，可直接用
// Node.js 執行，不需要 npm install 或任何測試框架（比照
// test_section_progress_density.mjs 的既有慣例，見 app/tool/README.md）。
//
// 用法：node app/tool/test_tts_safe_window.mjs
// 結束碼：0 = 全數通過；非 0 = 有斷言失敗或例外。

import assert from 'node:assert/strict'
import { resolveTtsSafeWindowDirection } from '../android/app/src/main/assets/foliate/tts-safe-window.js'

// 測試用固定 iframeRect／viewportRect：iframeRect 左上角對齊 (0,0)，
// viewportRect 為 100x100 的正方形，left/top 皆為 0——因此
// normOf(rect).x = rect.left/100、normOf(rect).y = rect.top/100
// （呼叫端傳入的 rect 皆用 left===right、top===bottom 的「點矩形」，
// 讓正規化座標可直接由 left/top 除以 100 推算，方便寫斷言）。
const IFRAME_RECT = { left: 0, top: 0 }
const VIEWPORT_RECT = { left: 0, top: 0, width: 100, height: 100 }

function point(x, y) {
  return { left: x, right: x, top: y, bottom: y }
}

const SAFE = point(50, 50) // 正規化座標 (0.5, 0.5)，橫排/直排皆不觸發

// 測試 1：橫排 needNext——last.y > 0.8 觸發，first 安全時回傳 'next'。
{
  const direction = resolveTtsSafeWindowDirection(
    SAFE, point(50, 85), IFRAME_RECT, VIEWPORT_RECT, false,
  )
  assert.equal(direction, 'next')
}

// 測試 2：橫排 needPrev——first.y < 0.0 觸發，last 安全時回傳 'prev'。
{
  const direction = resolveTtsSafeWindowDirection(
    point(50, -10), SAFE, IFRAME_RECT, VIEWPORT_RECT, false,
  )
  assert.equal(direction, 'prev')
}

// 測試 3：直排 needNext——last.x < 0.2 觸發。
{
  const direction = resolveTtsSafeWindowDirection(
    SAFE, point(10, 50), IFRAME_RECT, VIEWPORT_RECT, true,
  )
  assert.equal(direction, 'next')
}

// 測試 4：直排 needPrev——first.x > 1.0 觸發。
{
  const direction = resolveTtsSafeWindowDirection(
    point(150, 50), SAFE, IFRAME_RECT, VIEWPORT_RECT, true,
  )
  assert.equal(direction, 'prev')
}

// 測試 5：橫排邊界——last.y 恰好等於 0.8（軟門檻）不觸發 next（條件是
// `>`，非 `>=`）。
{
  const direction = resolveTtsSafeWindowDirection(
    SAFE, point(50, 80), IFRAME_RECT, VIEWPORT_RECT, false,
  )
  assert.equal(direction, null)
}

// 測試 6：橫排邊界——last.y 略高於 0.8（80.1/100）觸發 next。
{
  const direction = resolveTtsSafeWindowDirection(
    SAFE, point(50, 80.1), IFRAME_RECT, VIEWPORT_RECT, false,
  )
  assert.equal(direction, 'next')
}

// 測試 7：橫排邊界——first.y 恰好等於 0.0（硬邊界）不觸發 prev（條件是
// `< 0.0`，非 `<= 0.0`）。
{
  const direction = resolveTtsSafeWindowDirection(
    point(50, 0), SAFE, IFRAME_RECT, VIEWPORT_RECT, false,
  )
  assert.equal(direction, null)
}

// 測試 8：needNext 與 needPrev 同時成立時，next 優先（沿用原本焊在
// main.js 呼叫端的 if/else if 順序規則，收進函式內部）。
{
  const direction = resolveTtsSafeWindowDirection(
    point(50, -10), point(50, 85), IFRAME_RECT, VIEWPORT_RECT, false,
  )
  assert.equal(direction, 'next')
}

// 測試 9：firstRect／lastRect／iframeRect／viewportRect 任一缺席時回傳
// null（對應 main.js 原本 `if (firstRect && lastRect && frameEl)` 防呆，
// 行為與搬移前一致）。
{
  assert.equal(
    resolveTtsSafeWindowDirection(null, SAFE, IFRAME_RECT, VIEWPORT_RECT, false),
    null,
  )
  assert.equal(
    resolveTtsSafeWindowDirection(SAFE, undefined, IFRAME_RECT, VIEWPORT_RECT, false),
    null,
  )
  assert.equal(
    resolveTtsSafeWindowDirection(SAFE, SAFE, null, VIEWPORT_RECT, false),
    null,
  )
  assert.equal(
    resolveTtsSafeWindowDirection(SAFE, SAFE, IFRAME_RECT, null, false),
    null,
  )
}

console.log('resolveTtsSafeWindowDirection 安全視窗判斷驗證：9 項全數通過')
```

- [x] **Step 2: 執行測試腳本確認它會失敗**

執行：`node app/tool/test_tts_safe_window.mjs`

預期結果：因為 `tts-safe-window.js` 還不存在，Node 會拋出模組解析錯誤（`Cannot find module '.../tts-safe-window.js'` 或等效訊息），非結束碼 0。

- [x] **Step 3: 建立 `tts-safe-window.js` 最小實作**

建立 `app/android/app/src/main/assets/foliate/tts-safe-window.js`：

```js
// epic-34-tts-readalong Issue 8／Issue 11 的安全視窗（Safe Viewport）翻頁
// 判斷邏輯，epic-26-architecture-hardening Issue 12 抽成獨立、零 DOM 依賴
// 的純函式（比照同目錄 progress.js 的既有模式）——main.js 第 5 行頂層執行
// document.getElementById()，若把這個函式留在 main.js 裡 export，Node
// 匯入整份 main.js 會直接因 document 未定義而掛掉，故獨立成此檔案，讓
// app/tool/test_tts_safe_window.mjs 可以直接匯入單元測試，不需要真機或
// WebView 環境。

// 「可視範圍 20%～80%」（issues.md 用語）——朗讀高亮的正規化位置只要
// 落在這個區間內就不觸發翻頁，避免逐句捲動造成頻繁刷新（E-Ink 殘影）／
// 頻繁跳動（一般裝置）。不對外匯出：常數搬離 main.js 後只有這個檔案的
// 內部邏輯使用得到它，行為已由下方函式的邊界值單元測試間接涵蓋。
const TTS_SAFE_WINDOW_MIN = 0.2
const TTS_SAFE_WINDOW_MAX = 0.8

/**
 * 依朗讀段落 Range 的頭尾矩形，判斷目前顯示畫面是否需要跟隨翻頁。
 *
 * @param {{left: number, right: number, top: number, bottom: number} | null | undefined} firstRect
 *   Range.getClientRects() 回傳陣列的第一個矩形（這句話開頭那一行）。
 * @param {{left: number, right: number, top: number, bottom: number} | null | undefined} lastRect
 *   Range.getClientRects() 回傳陣列的最後一個矩形（這句話結尾那一行）。
 * @param {{left: number, top: number} | null | undefined} iframeRect
 *   內容 iframe 的 getBoundingClientRect()。
 * @param {{left: number, top: number, width: number, height: number} | null | undefined} viewportRect
 *   外層 view 的 getBoundingClientRect()。
 * @param {boolean} isVertical 目前是否為直排(vertical-RL)排版。
 * @returns {'next' | 'prev' | null} 需要翻頁的方向；不需要翻頁則回傳 null。
 */
export function resolveTtsSafeWindowDirection(
  firstRect,
  lastRect,
  iframeRect,
  viewportRect,
  isVertical,
) {
  // 對應 main.js 原本 `if (firstRect && lastRect && frameEl)` 防呆——
  // 任一必要輸入缺席（例如朗讀高亮尚未附著在任何可視 iframe 上）時，
  // 視為無法判斷，不觸發翻頁。
  if (!firstRect || !lastRect || !iframeRect || !viewportRect) {
    return null
  }

  const normOf = (rect) => ({
    x: (iframeRect.left + (rect.left + rect.right) / 2 - viewportRect.left) /
      viewportRect.width,
    y: (iframeRect.top + (rect.top + rect.bottom) / 2 - viewportRect.top) /
      viewportRect.height,
  })
  const first = normOf(firstRect)
  const last = normOf(lastRect)

  // needNext 看 Range 結尾那一行的位置——這句話開始播放的當下就先確認
  // 「唸到最後一個字時，畫面來不來得及顯示」，提前翻頁（見
  // epic-34-tts-readalong Issue 11 真機驗收記錄）。分頁模式下「頁首」是
  // 正常可見內容，needPrev 因此只能用真正超出頁面範圍的硬邊界
  // （0.0/1.0）判斷、依 Range 開頭矩形——否則剛翻到新頁的第一句會立刻
  // 被翻回上一頁，跟前一頁之間無限來回翻頁震盪（見
  // epic-34-tts-readalong Issue 8 review-plan-issue-8.md Critical #1）。
  const needNext = isVertical
    ? last.x < TTS_SAFE_WINDOW_MIN || last.y > 1.0
    : last.y > TTS_SAFE_WINDOW_MAX || last.x > 1.0
  const needPrev = isVertical
    ? first.x > 1.0 || first.y < 0.0
    : first.y < 0.0 || first.x < 0.0

  // 原本焊在 main.js 呼叫端的 if/else if 順序規則——needNext 優先於
  // needPrev，一併收進函式內部，避免呼叫端還留有一小塊未被測試涵蓋的
  // 判斷邏輯。
  if (needNext) return 'next'
  if (needPrev) return 'prev'
  return null
}
```

- [x] **Step 4: 執行測試腳本確認全數通過**

執行：`node app/tool/test_tts_safe_window.mjs`

預期結果：印出 `resolveTtsSafeWindowDirection 安全視窗判斷驗證：9 項全數通過`，結束碼 0。

- [x] **Step 5: 補充 `app/tool/README.md` 文件章節**

在 `app/tool/README.md` 的 `## \`test_section_progress_density.mjs\`` 小節之後（檔案末尾）新增一節，格式比照該小節：

```markdown

## `test_tts_safe_window.mjs`

驗證 `tts-safe-window.js` 的 `resolveTtsSafeWindowDirection()`（epic-26-architecture-hardening
Issue 12：TTS 安全視窗判斷邏輯純函式化）——橫排/直排、軟門檻/硬邊界、
needNext 與 needPrev 同時成立時的優先順序、必要輸入缺席共 9 項情境。
`tts-safe-window.js` 零 DOM 依賴，腳本用 Node.js 內建 `node:assert/strict`
直接執行，不需要任何測試框架。

### 何時該執行

- 每次修改 `tts-safe-window.js` 之後。
- 升級 `foliate/` 目錄下的釘定版本（bump commit）之後，若上游改動了
  `draw-annotation` 事件（`view.js`／`overlayer.js`）相關機制，確認安全
  視窗判斷邏輯仍與新版上游行為相容。

### 執行方式

```bash
node app/tool/test_tts_safe_window.mjs
```

- 結束碼 `0`：9 項情境全數通過。
- 非 `0`：斷言失敗或拋出例外，會印出對應的錯誤訊息與堆疊。
```

- [x] **Step 6: Commit**

```bash
git add app/android/app/src/main/assets/foliate/tts-safe-window.js app/tool/test_tts_safe_window.mjs app/tool/README.md
git commit -m "feat(epic-26): Issue 12 Task 1——新增 resolveTtsSafeWindowDirection 純函式"
```

---

### Task 2：main.js 接線改用純函式，更新 Dart regression-guard 測試

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js:1-3`（新增 import）
- Modify: `app/android/app/src/main/assets/foliate/main.js:892-950`（`draw-annotation` 監聽器內安全視窗判斷區塊）
- Modify: `app/test/reader/foliate_reader_view_test.dart:1559-1727`（合併兩組 group 為一組，刪除數學細節斷言，新增 wiring 測試）
- Test: `app/test/reader/foliate_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 1 產出的 `resolveTtsSafeWindowDirection(firstRect, lastRect, iframeRect, viewportRect, isVertical)`（回傳 `'next' | 'prev' | null`）。

- [x] **Step 1: 修改 `main.js` 的 import 區塊**

`main.js` 第 1-3 行目前為：

```js
import { makeBook } from './view.js'
import { Overlayer } from './overlayer.js'
import { compare as compareCfi } from './epubcfi.js'
```

改為：

```js
import { makeBook } from './view.js'
import { Overlayer } from './overlayer.js'
import { compare as compareCfi } from './epubcfi.js'
import { resolveTtsSafeWindowDirection } from './tts-safe-window.js'
```

- [x] **Step 2: 移除 `main.js` 內原本的 `TTS_SAFE_WINDOW_MIN`／`TTS_SAFE_WINDOW_MAX` 常數宣告**

`main.js` 第 438-443 行目前為：

```js
// epic-34-tts-readalong Issue 8：安全視窗（issues.md「可視範圍 20%～
// 80%」）——朗讀高亮的可視範圍正規化位置只要落在這個區間內就不觸發翻頁，
// 避免逐句捲動造成頻繁刷新（E-Ink 殘影）／頻繁跳動（一般裝置）。
const TTS_SAFE_WINDOW_MIN = 0.2
const TTS_SAFE_WINDOW_MAX = 0.8
let currentTtsAnnotationValue = null
```

改為（常數與說明常數用途的註解已搬進 `tts-safe-window.js`，這裡只保留
`currentTtsAnnotationValue`）：

```js
let currentTtsAnnotationValue = null
```

- [x] **Step 3: 修改 `draw-annotation` 監聽器內的安全視窗判斷區塊**

`main.js` 第 892-950 行目前為（`if (annotation.value === currentTtsAnnotationValue) { ... }` 這個區塊）：

```js
      // epic-34-tts-readalong Issue 8：安全視窗跟隨翻頁。只在這是「目前
      // 的朗讀高亮」時才檢查——annotation.value 與 currentTtsAnnotationValue
      // 相符時才成立；劃線/備註（window.setDecorations()）走的是不帶
      // foliate-note: 前綴的裸 cfi key，恆不相符，不受影響。
      // resyncHighlight()（Issue 7）與一般朗讀段切換（Issue 3）都是透過
      // 同一個 window.showTtsHighlight() 進來，天然共用這段判斷。
      if (annotation.value === currentTtsAnnotationValue) {
        // epic-34-tts-readalong Issue 11 真機驗收發現：這句話的 cfi
        // Range 本身（不論是否被 TtsController 硬性長度上限切分過）
        // 可能橫跨多行/多頁——range.getClientRects() 依文件順序回傳一行
        // 一個矩形。原本固定只看 getClientRects()[0]（Range 最開頭那一
        // 行）判斷要不要翻頁：只要這句話的開頭還在畫面上就永遠判斷「安
        // 全」，即使這句話後半段早已超出目前頁面範圍，畫面也完全不會
        // 跟著翻頁（真機實測重現：橫排/直排皆無法自動翻頁）。改為：
        // needNext 看 Range 結尾那一行的位置——這句話開始播放的當下就
        // 先確認「唸到最後一個字時，畫面來不來得及顯示」，提前翻頁；
        // needPrev 仍看 Range 開頭那一行，維持下方既有「新頁頁首不可
        // 誤判為需要翻回上一頁」的保護。一般不橫跨頁面的短句，開頭/
        // 結尾矩形位置幾乎相同，行為與修改前一致。
        const rects = range.getClientRects()
        const firstRect = rects[0]
        const lastRect = rects[rects.length - 1]
        const frameEl = doc.defaultView && doc.defaultView.frameElement
        if (firstRect && lastRect && frameEl) {
          const iframeRect = frameEl.getBoundingClientRect()
          const viewportRect = view.getBoundingClientRect()
          const normOf = (rect) => ({
            x: (iframeRect.left + (rect.left + rect.right) / 2 - viewportRect.left) / viewportRect.width,
            y: (iframeRect.top + (rect.top + rect.bottom) / 2 - viewportRect.top) / viewportRect.height,
          })
          const first = normOf(firstRect)
          const last = normOf(lastRect)
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
            ? last.x < TTS_SAFE_WINDOW_MIN || last.y > 1.0
            : last.y > TTS_SAFE_WINDOW_MAX || last.x > 1.0
          const needPrev = isVertical
            ? first.x > 1.0 || first.y < 0.0
            : first.y < 0.0 || first.x < 0.0
          if (needNext) {
            window.flutter_inappwebview.callHandler('onTtsHighlightOutOfSafeWindow', 'next')
          } else if (needPrev) {
            window.flutter_inappwebview.callHandler('onTtsHighlightOutOfSafeWindow', 'prev')
          }
        }
      }
```

改為（座標數學逐字搬進 `resolveTtsSafeWindowDirection()`，這裡只剩「取
資料 → 呼叫純函式 → 有結果才 callHandler」）：

```js
      // epic-34-tts-readalong Issue 8：安全視窗跟隨翻頁。只在這是「目前
      // 的朗讀高亮」時才檢查——annotation.value 與 currentTtsAnnotationValue
      // 相符時才成立；劃線/備註（window.setDecorations()）走的是不帶
      // foliate-note: 前綴的裸 cfi key，恆不相符，不受影響。
      // resyncHighlight()（Issue 7）與一般朗讀段切換（Issue 3）都是透過
      // 同一個 window.showTtsHighlight() 進來，天然共用這段判斷。
      if (annotation.value === currentTtsAnnotationValue) {
        // epic-26-architecture-hardening Issue 12：座標數學（含 Issue 11
        // 真機驗收發現的「needNext 看 Range 結尾矩形、needPrev 看開頭
        // 矩形」判斷）已抽成 tts-safe-window.js 的純函式，這裡只負責
        // 取得 Range 的頭尾矩形與座標系資料再轉呼叫，方便脫離真機用
        // app/tool/test_tts_safe_window.mjs 單元測試整段判斷邏輯。
        const rects = range.getClientRects()
        const frameEl = doc.defaultView && doc.defaultView.frameElement
        const direction = resolveTtsSafeWindowDirection(
          rects[0],
          rects[rects.length - 1],
          frameEl && frameEl.getBoundingClientRect(),
          view.getBoundingClientRect(),
          isVertical,
        )
        if (direction) {
          window.flutter_inappwebview.callHandler(
            'onTtsHighlightOutOfSafeWindow',
            direction,
          )
        }
      }
```

- [x] **Step 4: 更新 `foliate_reader_view_test.dart` 的 regression-guard 測試**

`app/test/reader/foliate_reader_view_test.dart` 第 1559-1727 行目前是兩個
獨立 group：

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

    test('needNext 使用安全視窗軟門檻（0.2/0.8），依 Range 結尾矩形（last）的 X/Y 兩軸皆檢查'
        '（epic-34-tts-readalong Issue 11：改看 Range 結尾而非開頭，見下方獨立 group）',
        () {
      expect(
        mainJsSource.contains('last.x < TTS_SAFE_WINDOW_MIN || last.y > 1.0'),
        isTrue,
        reason: '直排分支缺少這個條件——next 判斷須同時檢查 X 軸軟門檻與 '
            'Y 軸硬邊界。',
      );
      expect(
        mainJsSource.contains('last.y > TTS_SAFE_WINDOW_MAX || last.x > 1.0'),
        isTrue,
        reason: '橫排分支缺少這個條件——next 判斷須同時檢查 Y 軸軟門檻與 '
            'X 軸硬邊界。',
      );
    });

    test('needPrev 只能用真正超出頁面範圍的硬邊界（0.0/1.0）判斷，依 Range 開頭矩形（first），'
        '不可沿用安全視窗軟門檻（避免翻頁死循環）', () {
      expect(
        mainJsSource.contains('first.x > 1.0 || first.y < 0.0'),
        isTrue,
        reason: '直排分支的 prev 判斷式缺少或誤用了門檻——不可出現 '
            'TTS_SAFE_WINDOW_MIN/MAX，否則新頁頁首會被誤判為需要翻回'
            '上一頁。',
      );
      expect(
        mainJsSource.contains('first.y < 0.0 || first.x < 0.0'),
        isTrue,
        reason: '橫排分支的 prev 判斷式缺少或誤用了門檻——不可出現 '
            'TTS_SAFE_WINDOW_MIN/MAX，否則新頁頁首會被誤判為需要翻回'
            '上一頁。',
      );
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

  group(
      'main.js 安全視窗跟隨翻頁 × 硬性長度上限切分交互作用修復 regression guard '
      '（epic-34-tts-readalong Issue 11 真機驗收發現）', () {
    late String mainJsSource;

    setUpAll(() {
      mainJsSource = File('android/app/src/main/assets/foliate/main.js')
          .readAsStringSync();
    });

    test('安全視窗檢查改用 Range 的開頭矩形與結尾矩形分別判斷，不再固定只看第一個', () {
      expect(
        mainJsSource.contains('const rects = range.getClientRects()'),
        isTrue,
        reason: '這句話的 cfi Range 本身（不論是否被硬性長度上限切分過）'
            '可能橫跨多行/多頁，getClientRects() 因此可能回傳多個矩形；'
            '固定只看 [0] 會讓安全視窗檢查永遠盯著這句話開頭的位置判斷，'
            '偵測不到這句話後半段早已超出目前頁面範圍的情況（真機實測：'
            '橫排/直排皆無法自動翻頁）。',
      );
      expect(mainJsSource.contains('const firstRect = rects[0]'), isTrue);
      expect(
        mainJsSource.contains('const lastRect = rects[rects.length - 1]'),
        isTrue,
      );
      expect(
        mainJsSource.contains('const first = normOf(firstRect)'),
        isTrue,
      );
      expect(mainJsSource.contains('const last = normOf(lastRect)'), isTrue);
    });

    test('needNext 依 Range 結尾矩形（last）判斷，needPrev 依 Range 開頭矩形（first）判斷', () {
      expect(
        mainJsSource.contains('const needNext = isVertical'),
        isTrue,
      );
      expect(
        mainJsSource.contains('? last.x < TTS_SAFE_WINDOW_MIN || last.y > 1.0'),
        isTrue,
        reason: 'needNext 必須依 Range 結尾矩形判斷——這句話開始播放的'
            '當下就先確認「唸到最後一個字時，畫面來不來得及顯示」，提前'
            '翻頁；若誤用開頭矩形，會重蹈真機發現的「這句話開頭還在畫面'
            '上就永遠判斷安全」問題。',
      );
      expect(
        mainJsSource.contains(': last.y > TTS_SAFE_WINDOW_MAX || last.x > 1.0'),
        isTrue,
      );
      expect(
        mainJsSource.contains('const needPrev = isVertical'),
        isTrue,
      );
      expect(
        mainJsSource.contains('? first.x > 1.0 || first.y < 0.0'),
        isTrue,
        reason: 'needPrev 須維持依 Range 開頭矩形判斷（Issue 8 既有「新頁'
            '頁首不可誤判為需要翻回上一頁」保護對象是「這句話的開頭位置」'
            '，不是結尾）。',
      );
      expect(
        mainJsSource.contains(': first.y < 0.0 || first.x < 0.0'),
        isTrue,
      );
    });
  });
```

改為（合併為一組，刪除數學細節斷言，新增 wiring 測試）：

```dart
  group('main.js 安全視窗跟隨翻頁 + E-Ink 高對比 regression guard（epic-34-tts-readalong Issue 8／epic-26-architecture-hardening Issue 12）', () {
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

    test(
        'draw-annotation 監聽器透過 resolveTtsSafeWindowDirection() 判斷方向'
        '（epic-26-architecture-hardening Issue 12：座標數學已抽成 '
        'tts-safe-window.js 純函式並由 app/tool/test_tts_safe_window.mjs '
        '單元測試涵蓋，這裡只驗證 main.js 接線正確，不重複驗證數學細節）',
        () {
      expect(
        mainJsSource.contains(
          "import { resolveTtsSafeWindowDirection } from './tts-safe-window.js'",
        ),
        isTrue,
        reason: 'main.js 須從 tts-safe-window.js 匯入純函式，不可自行內嵌'
            '安全視窗座標數學邏輯。',
      );
      expect(
        mainJsSource.contains('resolveTtsSafeWindowDirection('),
        isTrue,
        reason: 'draw-annotation 監聽器須呼叫這個純函式取得翻頁方向。',
      );
      expect(
        mainJsSource
            .contains("callHandler('onTtsHighlightOutOfSafeWindow', direction)"),
        isTrue,
        reason: '監聽器須把 resolveTtsSafeWindowDirection() 的回傳值原樣'
            '轉送給 callHandler，不可自行重新判斷 next/prev（該判斷已收進'
            '純函式內部，見 tts-safe-window.js）。',
      );
      expect(
        mainJsSource.contains('const TTS_SAFE_WINDOW_MIN'),
        isFalse,
        reason: '安全視窗常數已搬進 tts-safe-window.js，main.js 不應再'
            '殘留這個宣告。',
      );
    });
  });
```

（`app/test/reader/foliate_reader_view_test.dart` 第 1729 行起的
`group('onTtsHighlightOutOfSafeWindow（epic-34-tts-readalong Issue 8）', ...)`
測試 `FoliateReaderView` widget 建構參數，與本次改動無關，維持不動。）

- [x] **Step 5: 執行受影響測試確認全數通過**

執行：`flutter test test/reader/foliate_reader_view_test.dart`（於 `app/`
目錄下執行）

預期結果：全數通過，無 `mainJsSource.contains(...)` 斷言失敗。

- [x] **Step 6: 再次執行 Task 1 的 Node 測試腳本確認未受影響**

執行：`node app/tool/test_tts_safe_window.mjs`

預期結果：印出 `resolveTtsSafeWindowDirection 安全視窗判斷驗證：9 項全數通過`，結束碼 0。

- [x] **Step 7: 執行 `flutter analyze` 確認乾淨**

執行（於 `app/` 目錄下）：`flutter analyze`

預期結果：`No issues found!`

- [x] **Step 8: 執行完整 `flutter test`（本計畫最後一個 Task，依 Global Constraints 慣例整套跑一次）**

執行（於 `app/` 目錄下）：`flutter test`

預期結果：全數通過，零回歸。

- [x] **Step 9: Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js app/test/reader/foliate_reader_view_test.dart
git commit -m "refactor(epic-26): Issue 12 Task 2——main.js 接線改用 resolveTtsSafeWindowDirection"
```

---

## Self-Review（撰寫計畫時的自我檢查記錄）

1. **Spec 涵蓋度**：Issue 12 的 6 條 Solution 要點（新檔案／常數搬移／函式簽章／main.js 接線／Node 測試／README）對應 Task 1 Step 1-5；既有 Dart 測試處理（保留 wiring、刪除數學細節）對應 Task 2 Step 4；單元測試要求（Node 測試 9 種情境、wiring 測試、`flutter analyze`／`flutter test`）對應 Task 1 Step 4 與 Task 2 Step 5-8；驗收標準逐項對應 Task 2 完成後的狀態。無遺漏。
2. **Placeholder 掃描**：全文無 TBD／「補上驗證邏輯」等佔位字樣，所有程式碼步驟皆附完整內容。
3. **型別/簽章一致性**：`resolveTtsSafeWindowDirection(firstRect, lastRect, iframeRect, viewportRect, isVertical)` 在 Task 1（定義）與 Task 2（呼叫、Dart 測試斷言）三處逐字一致。
