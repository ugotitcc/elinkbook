# Epic 9 Issue 1：原型 HTML——閱讀統計畫面與貢獻圖 — 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `prototype/elinkbook_theme_prototype.html` 新增可操作的「閱讀統計」畫面（貢獻圖、詳情卡片、累計總時數、清除全部），並在 Light／Dark／Sepia 與 E-Ink 下定案貢獻圖的色階、灰階與紋理，供 Issue 5 直接取值。

**Architecture:**
- 貢獻圖的日期網格、分級、時數格式、假資料，抽成一段**不依賴 DOM 的純函式區塊**（以標記註解包住），放在獨立的 `<script>`；用 `node --test` 擷取該區塊做自動化驗證。這段邏輯正是 Flutter 端 Issue 5 要對照的行為（週一起始、53 週、五級門檻）。
- 畫面走既有原型模式：新增 `#view-stats`，由 `switchView('stats')` 切換；主題色以 CSS 變數（`--heat-0`～`--heat-4`）掛在既有的四組主題選擇器上，E-Ink 紋理用 CSS 漸層畫在方格內。
- 詳情用畫面內固定卡片，不做 Tooltip 或浮動層。

**Tech Stack:** 純 HTML／Tailwind CDN／原生 JavaScript（既有原型）；Node 24 內建 `node:test`（不安裝任何套件）。

**Spec:** [`../spec.md`](../spec.md)（「統計畫面」「主題與 E-Ink」「國際化」三段）、[`../issues.md`](../issues.md) Issue 1

## Global Constraints

- **只改 `prototype/elinkbook_theme_prototype.html` 與新增 `prototype/tests/stats_logic.test.js`。** 不動其他畫面既有的 markup／邏輯，不動 `prototype/index.html`、`eink_redesign_prototype.html`，不動 `app/`。
- 五級分級（逐字照 spec）：0 無紀錄；未滿 15 分；未滿 30 分；未滿 60 分；60 分以上。以當日全部書籍總時數判定。
- 一週從**週一**開始（row 0 = 週一，row 6 = 週日）；涵蓋今天往前 365 天，共 53 週；第一週週一之前、最後一週今天之後的格子是**不可點擊的透明佔位**。
- 版面兩欄：左側**固定不捲動**的星期標籤欄（只標「一、三、五」）；右側水平捲動容器，月份標籤在方格上方、隨容器捲動；載入畫面後**預設捲到最右側**。
- **不使用 Tooltip 或任何浮動層**顯示詳情；詳情只出現在貢獻圖下方固定卡片。進入畫面**預設選中今天**；被選中的方格有高對比外框；無紀錄顯示「當日無閱讀記錄」；各書依時數由多到少。
- E-Ink 修飾子啟用時（`data-eink="on"`）貢獻圖**不得只靠色相區分**：用階梯灰階加斜線／網點紋理；不使用動畫。
- 「清除全部統計」置於畫面底部，必經確認對話框；確認後畫面回到空白狀態並顯示通知。
- 畫面文字用 ARB 已定案的正體中文原文：`閱讀統計`、`累計閱讀時數`、`{date} 閱讀明細`、`當日無閱讀記錄`、`較少`、`較多`、`清除全部統計`、`確定要清除所有閱讀統計嗎？此動作無法復原。`、`已清除全部閱讀統計`。時數格式為「X 小時 Y 分鐘」或「Y 分鐘」。
- 程式碼內的註解一律使用正體中文。

## Review Focus

以下是 spec 隱含、但主要驗收條件沒有直接涵蓋，最可能讓使用者踩到的情況（最可能的在前）：

1. **今天沒有紀錄**：進入畫面仍預設選中今天，詳情顯示「當日無閱讀記錄」，不是空白或壞掉。（Task 3 驗證）
2. **全空（清除後）**：貢獻圖全部 0 級、累計顯示「0 分鐘」、詳情仍顯示說明。（Task 4 驗證）
3. **書名很長／一天讀多本書**：詳情卡片文字換行、時數不被擠出畫面。（Task 3 驗證，假資料含 `The Pragmatic Programmer` 與一天 ≥2 本）
4. **今天剛好是週日**：最後一週完整、沒有多餘透明佔位。（Task 1 已有自動化測試）
5. **橫向模擬（640×480）與 E-Ink 切換**：版面不破、星期欄仍固定、E-Ink 開關時方格顏色不殘留。（Task 5 驗證）

---

## 檔案結構

| 檔案 | 動作 | 責任 |
|---|---|---|
| `prototype/elinkbook_theme_prototype.html` | 修改 | 新增純邏輯 `<script>`、CSS（色階／紋理）、`#view-stats` 畫面、導覽入口、互動 JS |
| `prototype/tests/stats_logic.test.js` | 新增 | 擷取 HTML 內純邏輯區塊，驗證分級、時數格式、網格、假資料 |
| `docs/epics/epic-9-stats/epic.md` | 修改 | Task 5 記錄驗證結果與定案值 |

`prototype/tests/` 目前不存在，Task 1 建立。

---

### Task 1：純邏輯區塊與 node 測試

**Files:**
- Create: `prototype/tests/stats_logic.test.js`
- Modify: `prototype/elinkbook_theme_prototype.html`（在主 `<script>` 之前插入純邏輯 `<script>`）

**Interfaces:**
- Produces（Task 3、4 的畫面 JS 會直接呼叫，名稱與簽章固定）：
  - `statsLevelForSeconds(sec: number): 0|1|2|3|4`
  - `statsFormatDuration(sec: number): string`
  - `statsDateKey(d: Date): string`（本地日期 `YYYY-MM-DD`）
  - `statsAddDays(d: Date, n: number): Date`
  - `statsBuildHeatmapGrid(today: Date): { weeks: Array<Array<{date: string, row: number} | null>>, monthLabels: Array<{weekIndex: number, month: number}> }`
  - `statsMockData(today: Date, scenario: 'normal'|'todayEmpty'|'empty'|'heavy'): Record<string, Array<{bookId: string, title: string, seconds: number}>>`
  - `statsDayTotal(data, dateKey): number`、`statsGrandTotal(data): number`
  - 常數 `STATS_WINDOW_DAYS = 365`、`STATS_MOCK_BOOKS`

- [x] **Step 1: 寫失敗的測試**

建立 `prototype/tests/stats_logic.test.js`：

```js
// 閱讀統計原型：純邏輯測試（無需安裝任何套件，node --test 即可執行）
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

// 從原型 HTML 擷取純邏輯區塊後執行
const html = fs.readFileSync(
  path.join(__dirname, '..', 'elinkbook_theme_prototype.html'), 'utf8');
const m = html.match(/\/\* STATS-LOGIC-START \*\/([\s\S]*?)\/\* STATS-LOGIC-END \*\//);
assert.ok(m, '找不到 STATS-LOGIC 區塊');
const api = new Function(`${m[1]}
  return { statsLevelForSeconds, statsFormatDuration, statsBuildHeatmapGrid,
           statsMockData, statsDayTotal, statsGrandTotal, statsDateKey };`)();

const D = (y, mo, d) => new Date(y, mo - 1, d);

test('分級門檻：0 / 未滿15 / 未滿30 / 未滿60 / 60分以上', () => {
  const f = api.statsLevelForSeconds;
  assert.strictEqual(f(0), 0);
  assert.strictEqual(f(1), 1);
  assert.strictEqual(f(899), 1);
  assert.strictEqual(f(900), 2);
  assert.strictEqual(f(1799), 2);
  assert.strictEqual(f(1800), 3);
  assert.strictEqual(f(3599), 3);
  assert.strictEqual(f(3600), 4);
});

test('時數格式', () => {
  const f = api.statsFormatDuration;
  assert.strictEqual(f(0), '0 分鐘');
  assert.strictEqual(f(1), '1 分鐘');      // 有紀錄但不滿 1 分鐘：顯示 1 分鐘
  assert.strictEqual(f(30), '1 分鐘');
  assert.strictEqual(f(59), '1 分鐘');
  assert.strictEqual(f(60), '1 分鐘');
  assert.strictEqual(f(45 * 60), '45 分鐘');
  assert.strictEqual(f(3600), '1 小時 0 分鐘');
  assert.strictEqual(f(3600 * 2 + 5 * 60), '2 小時 5 分鐘');
});

test('網格：53 週、每週 7 格、有效格子共 365 個', () => {
  const { weeks } = api.statsBuildHeatmapGrid(D(2026, 9, 29));
  assert.strictEqual(weeks.length, 53);
  weeks.forEach(w => assert.strictEqual(w.length, 7));
  assert.strictEqual(weeks.flat().filter(Boolean).length, 365);
});

test('網格：一週從週一開始，首末週缺角為 null', () => {
  // 2026-09-29 是週二；往前 364 天 = 2025-09-30（週二）
  const { weeks } = api.statsBuildHeatmapGrid(D(2026, 9, 29));
  const first = weeks[0];
  assert.strictEqual(first[0], null);                 // 2025-09-29（週一）在範圍之前
  assert.strictEqual(first[1].date, '2025-09-30');    // 範圍第一天，row 1（週二）
  const last = weeks[weeks.length - 1];
  assert.strictEqual(last[0].date, '2026-09-28');     // 週一
  assert.strictEqual(last[1].date, '2026-09-29');     // 今天（週二）
  for (let r = 2; r < 7; r++) assert.strictEqual(last[r], null);
});

test('網格：今天為週日時最後一週完整', () => {
  const { weeks } = api.statsBuildHeatmapGrid(D(2026, 9, 27)); // 週日
  const last = weeks[weeks.length - 1];
  assert.strictEqual(last[6].date, '2026-09-27');
  assert.ok(last.every(Boolean));
});

test('月份標籤：週序遞增且不重疊', () => {
  const { monthLabels } = api.statsBuildHeatmapGrid(D(2026, 9, 29));
  for (let i = 1; i < monthLabels.length; i++) {
    assert.ok(monthLabels[i].weekIndex - monthLabels[i - 1].weekIndex >= 2);
  }
  assert.ok(monthLabels.length >= 11);
});

test('假資料：決定性、情境正確', () => {
  const today = D(2026, 9, 29);
  const key = api.statsDateKey(today);
  assert.deepStrictEqual(api.statsMockData(today, 'normal'), api.statsMockData(today, 'normal'));
  assert.deepStrictEqual(api.statsMockData(today, 'empty'), {});
  assert.ok(api.statsMockData(today, 'normal')[key].length >= 1);
  assert.strictEqual(api.statsMockData(today, 'todayEmpty')[key], undefined);
  const heavy = api.statsMockData(today, 'heavy');
  assert.ok(Object.values(heavy).every(l => api.statsLevelForSeconds(l[0].seconds) === 4));
  const normal = api.statsMockData(today, 'normal');
  assert.ok(Object.values(normal).some(l => l.length >= 2), '需有一天讀多本書');
  const levels = new Set(Object.keys(normal).map(k => api.statsLevelForSeconds(api.statsDayTotal(normal, k))));
  assert.ok([1, 2, 3, 4].every(l => levels.has(l)), '五級中的 1~4 級都要出現');
  assert.strictEqual(api.statsGrandTotal(normal),
    Object.keys(normal).reduce((s, k) => s + api.statsDayTotal(normal, k), 0));
});
```

- [x] **Step 2: 執行測試確認失敗**

Run: `node --test prototype/tests/`
Expected: FAIL，訊息含「找不到 STATS-LOGIC 區塊」（HTML 尚未加入該區塊）。

- [x] **Step 3: 插入純邏輯區塊**

用 Edit 工具修改 `prototype/elinkbook_theme_prototype.html`。`old_string`（唯一）：

```
  <script>
    let currentView = 'library';
```

`new_string`：

```
  <script>
/* STATS-LOGIC-START */
// ============ 閱讀統計：純邏輯（無 DOM 依賴；node 測試會擷取此區塊執行） ============
const STATS_WINDOW_DAYS = 365;

// 五級分級：0 無紀錄；1 未滿 15 分；2 未滿 30 分；3 未滿 60 分；4 六十分以上
function statsLevelForSeconds(sec) {
  if (sec <= 0) return 0;
  if (sec < 15 * 60) return 1;
  if (sec < 30 * 60) return 2;
  if (sec < 60 * 60) return 3;
  return 4;
}

// 時數顯示：「X 小時 Y 分鐘」或「Y 分鐘」；有紀錄但不滿 1 分鐘者顯示「1 分鐘」（避免顯示 0 分鐘）
function statsFormatDuration(sec) {
  let minutes = Math.floor(sec / 60);
  if (sec > 0 && minutes === 0) minutes = 1;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return hours > 0 ? `${hours} 小時 ${rest} 分鐘` : `${rest} 分鐘`;
}

// 本地日期 → YYYY-MM-DD
function statsDateKey(d) {
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${d.getFullYear()}-${mm}-${dd}`;
}

function statsAddDays(d, n) {
  const r = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  r.setDate(r.getDate() + n);
  return r;
}

// 建立貢獻圖網格：涵蓋「今天往前 365 天」，一週從週一開始（row 0 = 週一，row 6 = 週日）。
// 範圍外（第一週週一之前、最後一週今天之後）的格子為 null（畫成透明佔位、不可點擊）。
function statsBuildHeatmapGrid(today) {
  const t = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const start = statsAddDays(t, -(STATS_WINDOW_DAYS - 1));
  const startMonday = statsAddDays(start, -((start.getDay() + 6) % 7));
  const spanDays = Math.round((t - startMonday) / 86400000) + 1;
  const weekCount = Math.ceil(spanDays / 7);
  const weeks = [];
  for (let w = 0; w < weekCount; w++) {
    const col = [];
    for (let row = 0; row < 7; row++) {
      const day = statsAddDays(startMonday, w * 7 + row);
      col.push(day < start || day > t ? null : { date: statsDateKey(day), row });
    }
    weeks.push(col);
  }
  // 月份標籤：某週第一個有效格子的月份與前一個標籤不同時標出；
  // 第一個標籤若與第二個標籤相距不到 2 週（會重疊）則捨棄第一個
  const monthLabels = [];
  let lastMonth = -1;
  weeks.forEach((col, w) => {
    const first = col.find(c => c);
    if (!first) return;
    const month = Number(first.date.slice(5, 7));
    if (month !== lastMonth) {
      monthLabels.push({ weekIndex: w, month });
      lastMonth = month;
    }
  });
  if (monthLabels.length >= 2 && monthLabels[1].weekIndex - monthLabels[0].weekIndex < 2) {
    monthLabels.shift();
  }
  return { weeks, monthLabels };
}

// 假資料（固定亂數種子，重複載入結果一致）。scenario：
// normal 一般；todayEmpty 今天無紀錄；empty 全空（清除後）；heavy 每天都讀超過一小時
const STATS_MOCK_BOOKS = ['紅樓夢', '人間詞話', 'The Pragmatic Programmer', '三體', '歷史的研究',
  '海邊的卡夫卡' /* 示範「已刪除的書」：實際 App 以書名快照顯示，畫面與一般書無差別 */];

function statsMockData(today, scenario) {
  const data = {};
  if (scenario === 'empty') return data;
  let seed = 20260929;
  const rnd = () => { seed = (seed * 1664525 + 1013904223) % 4294967296; return seed / 4294967296; };
  for (let i = 0; i < STATS_WINDOW_DAYS; i++) {
    const key = statsDateKey(statsAddDays(today, -i));
    if (scenario === 'heavy') {
      data[key] = [{ bookId: 'b0', title: STATS_MOCK_BOOKS[0], seconds: (65 + Math.floor(rnd() * 90)) * 60 }];
      continue;
    }
    const isToday = i === 0;
    if (!isToday && rnd() > 0.55) continue;
    const count = 1 + Math.floor(rnd() * 3);
    const books = [];
    for (let b = 0; b < count; b++) {
      const idx = Math.floor(rnd() * STATS_MOCK_BOOKS.length);
      if (books.some(x => x.bookId === `b${idx}`)) continue;
      books.push({ bookId: `b${idx}`, title: STATS_MOCK_BOOKS[idx], seconds: (5 + Math.floor(rnd() * 66)) * 60 });
    }
    books.sort((a, b) => b.seconds - a.seconds);
    data[key] = books;
  }
  if (scenario === 'todayEmpty') delete data[statsDateKey(today)];
  return data;
}

function statsDayTotal(data, key) {
  return (data[key] || []).reduce((s, b) => s + b.seconds, 0);
}
function statsGrandTotal(data) {
  return Object.keys(data).reduce((s, k) => s + statsDayTotal(data, k), 0);
}
/* STATS-LOGIC-END */
  </script>

  <script>
    let currentView = 'library';
```

- [x] **Step 4: 執行測試確認通過**

Run: `node --test prototype/tests/`
Expected: 7 個測試全部 PASS，`fail 0`。

- [x] **Step 5: 語法檢查所有內嵌腳本**

Run:
```bash
node -e "const h=require('fs').readFileSync('prototype/elinkbook_theme_prototype.html','utf8');const s=[...h.matchAll(/<script(?![^>]*src)[^>]*>([\s\S]*?)<\/script>/g)].map(m=>m[1]);s.forEach((c,i)=>{try{new Function(c)}catch(e){console.error('script',i,e.message);process.exit(1)}});console.log('ok',s.length)"
```
Expected: 印出 `ok 3`（tailwind 設定、純邏輯、主腳本）。

- [x] **Step 6: Commit**

```bash
git add prototype/tests/stats_logic.test.js prototype/elinkbook_theme_prototype.html
git commit -m "feat(prototype): epic-9 Issue 1 貢獻圖純邏輯區塊與 node 測試"
```

---

### Task 2：色階與 E-Ink 紋理 CSS、畫面骨架、導覽入口

**Files:**
- Modify: `prototype/elinkbook_theme_prototype.html`

**Interfaces:**
- Consumes: 無（純樣式與 markup）。
- Produces（Task 3、4 依賴這些 id 與 class，名稱固定）：
  - CSS 變數 `--heat-0`～`--heat-4`；class `heat-cell`、`heat-l0`～`heat-l4`、`heat-empty`、`selected`。
  - DOM id：`view-stats`、`stats-total`、`stats-heatmap`（水平捲動容器）、`stats-heatmap-inner`、`stats-detail-card`、`stats-clear-btn`、`stats-clear-dialog`、`nav-stats`、`stats-scn-normal`／`stats-scn-todayEmpty`／`stats-scn-empty`／`stats-scn-heavy`。
  - JS：`enterStatsView()`（本 Task 先放空函式，Task 3 取代）。

- [x] **Step 1: 四組主題加入色階變數**

用 Edit 工具，四處各改一次（`old_string` 皆唯一）。

Light：
```
      --color-primary: #0284c7;
      --color-on-primary: #ffffff;
```
改為
```
      --color-primary: #0284c7;
      --color-on-primary: #ffffff;
      /* 貢獻圖五級色階（epic-9-stats）：0 無紀錄 → 4 六十分以上 */
      --heat-0: #eaf1f5;
      --heat-1: #bae6fd;
      --heat-2: #7dd3fc;
      --heat-3: #38bdf8;
      --heat-4: #0284c7;
```
Dark：
```
      --color-primary: #38bdf8;
      --color-on-primary: #141416;
```
改為
```
      --color-primary: #38bdf8;
      --color-on-primary: #141416;
      --heat-0: #2c2c34;
      --heat-1: #0c4a6e;
      --heat-2: #0369a1;
      --heat-3: #0ea5e9;
      --heat-4: #7dd3fc;
```
Sepia：
```
      --color-primary: #b8362d;
      --color-on-primary: #ffffff;
```
改為
```
      --color-primary: #b8362d;
      --color-on-primary: #ffffff;
      --heat-0: #e6dfcb;
      --heat-1: #efd3c4;
      --heat-2: #dea08e;
      --heat-3: #c85f4f;
      --heat-4: #b8362d;
```
E-Ink：
```
      --color-primary: #000000;
      --color-on-primary: #ffffff;
```
改為
```
      --color-primary: #000000;
      --color-on-primary: #ffffff;
      /* E-Ink：階梯灰階；級別另由下方紋理輔助，不只靠灰階深淺區分 */
      --heat-0: #ffffff;
      --heat-1: #d4d4d4;
      --heat-2: #a3a3a3;
      --heat-3: #525252;
      --heat-4: #000000;
```

- [x] **Step 2: 新增貢獻圖 CSS**

Edit：`old_string`
```
    #emulator-screen .active\:text-white:active { color: var(--color-on-primary) !important; }
  </style>
```
`new_string`
```
    #emulator-screen .active\:text-white:active { color: var(--color-on-primary) !important; }

    /* ============================================================
       閱讀統計貢獻圖（epic-9-stats）
       ============================================================ */
    .heat-cell { width: 16px; height: 16px; border-radius: 2px; flex-shrink: 0; padding: 0; background-color: var(--heat-0); }
    .heat-l1 { background-color: var(--heat-1); }
    .heat-l2 { background-color: var(--heat-2); }
    .heat-l3 { background-color: var(--heat-3); }
    .heat-l4 { background-color: var(--heat-4); }
    /* 範圍外的透明佔位格：不畫、不可點 */
    .heat-cell.heat-empty { background: transparent; pointer-events: none; }
    /* 被選中的方格：高對比外框 */
    .heat-cell.selected { position: relative; z-index: 10; outline: 2px solid var(--color-on-surface); outline-offset: 1px; }
    /* 捲動容器會裁掉超出內容區的外框：預設選中的「今天」在最右下角，外框右側與下側會被切掉。
       左、右、下留 4px 內距（外框最寬外擴 4px）；上方不加，避免與左側星期欄的垂直對齊位移 */
    #stats-heatmap-inner { padding: 0 4px 4px 4px; }
    /* 破壞性主按鈕的按壓態：以主題色反相（不用 opacity，E-Ink 下半透明會產生灰階殘影） */
    #emulator-screen .stats-danger-btn:active {
      background-color: var(--color-surface) !important;
      color: var(--color-on-surface) !important;
    }
    /* E-Ink：方格改硬邊框；1～3 級用紋理（網點／斜線／交叉線），4 級實心，0 級留白 */
    #emulator-screen[data-eink="on"] .heat-cell:not(.heat-empty) { border: 1px solid #000; border-radius: 0; }
    #emulator-screen[data-eink="on"] .heat-l0 { background-color: #fff; }
    #emulator-screen[data-eink="on"] .heat-l1 {
      background-color: #fff;
      background-image: radial-gradient(#000 1px, transparent 1.2px);
      background-size: 4px 4px;
    }
    #emulator-screen[data-eink="on"] .heat-l2 {
      background-color: #fff;
      background-image: repeating-linear-gradient(45deg, #000 0 1px, #fff 1px 4px);
    }
    #emulator-screen[data-eink="on"] .heat-l3 {
      background-color: #fff;
      background-image:
        repeating-linear-gradient(45deg, #000 0 1.5px, transparent 1.5px 4px),
        repeating-linear-gradient(-45deg, #000 0 1.5px, transparent 1.5px 4px);
    }
    #emulator-screen[data-eink="on"] .heat-l4 { background-color: #000; }
    #emulator-screen[data-eink="on"] .heat-cell.selected { outline-width: 3px; }
    /* E-Ink 的對話框遮罩改不透明白底，避免半透明灰階造成殘影 */
    #emulator-screen[data-eink="on"] #stats-clear-dialog { background-color: #ffffff; }
  </style>
```

- [x] **Step 3: 新增畫面 markup**

Edit：`old_string`（唯一）
```
      <!-- 模擬系統通知浮層 -->
```
`new_string`
```
      <!-- 畫面 F：閱讀統計（epic-9-stats）。由設定頁「閱讀統計」進入 -->
      <div id="view-stats" class="hidden flex-grow flex flex-col h-full bg-white text-black">
        <div class="h-[56px] border-b-2 border-black flex items-center px-4 gap-2 flex-shrink-0 bg-white">
          <button onclick="switchView('settings')" class="w-11 h-11 border-[1.5px] border-black rounded-md flex items-center justify-center text-base font-bold active:bg-black active:text-white">‹</button>
          <span class="text-xl font-black">閱讀統計</span>
        </div>

        <div class="flex-grow overflow-y-auto no-scrollbar bg-white p-3 flex flex-col gap-3">
          <!-- 累計總時數 -->
          <div class="border-[1.5px] border-black rounded-md p-3">
            <div class="text-[10px] opacity-75">累計閱讀時數</div>
            <div id="stats-total" class="text-2xl font-black">0 分鐘</div>
          </div>

          <!-- 貢獻圖：左側固定星期欄＋右側水平捲動 -->
          <div class="border-[1.5px] border-black rounded-md p-3">
            <div class="flex">
              <!-- 星期標籤欄：不隨捲動移動。頂端 17px 對齊月份列（14px 高＋3px 間距） -->
              <div class="flex-shrink-0 pr-1 text-[10px]" style="width:18px">
                <div style="height:17px"></div>
                <div class="flex flex-col" style="gap:3px">
                  <div style="height:16px;line-height:16px">一</div>
                  <div style="height:16px"></div>
                  <div style="height:16px;line-height:16px">三</div>
                  <div style="height:16px"></div>
                  <div style="height:16px;line-height:16px">五</div>
                  <div style="height:16px"></div>
                  <div style="height:16px"></div>
                </div>
              </div>
              <!-- 方格與月份標籤：水平捲動容器，載入後捲到最右側 -->
              <div id="stats-heatmap" class="overflow-x-auto no-scrollbar flex-1 min-w-0">
                <div id="stats-heatmap-inner" class="inline-block"></div>
              </div>
            </div>
            <!-- 圖例 -->
            <div class="flex items-center justify-end gap-1 mt-2 text-[10px]">
              <span>較少</span>
              <div class="heat-cell heat-l0"></div>
              <div class="heat-cell heat-l1"></div>
              <div class="heat-cell heat-l2"></div>
              <div class="heat-cell heat-l3"></div>
              <div class="heat-cell heat-l4"></div>
              <span>較多</span>
            </div>
          </div>

          <!-- 當日詳情：固定卡片，不使用 Tooltip -->
          <div id="stats-detail-card" class="border-[1.5px] border-black rounded-md p-3"></div>

          <!-- 清除全部統計 -->
          <button id="stats-clear-btn" onclick="openStatsClearDialog()" class="w-full h-12 border-[1.5px] border-black rounded-md text-sm font-black active:bg-black active:text-white flex-shrink-0">清除全部統計</button>
        </div>

        <!-- 清除確認對話框 -->
        <div id="stats-clear-dialog" class="hidden absolute inset-0 z-40 flex items-center justify-center bg-black/60 p-6">
          <div class="w-full bg-white text-black border-2 border-black rounded-md p-4 flex flex-col gap-4">
            <div class="text-base font-black">清除全部統計</div>
            <div class="text-sm leading-relaxed">確定要清除所有閱讀統計嗎？此動作無法復原。</div>
            <div class="flex gap-2">
              <button onclick="closeStatsClearDialog()" class="flex-1 h-11 border-[1.5px] border-black rounded-md text-sm font-black active:bg-black active:text-white">取消</button>
              <button onclick="confirmStatsClear()" class="stats-danger-btn flex-1 h-11 bg-black text-white border-[1.5px] border-black rounded-md text-sm font-black">清除</button>
            </div>
          </div>
        </div>
      </div>

      <!-- 模擬系統通知浮層 -->
```

- [x] **Step 4: 設定頁加入「閱讀統計」入口**

Edit：`old_string`（唯一）
```
                <div class="text-[10px] opacity-75 mt-0.5">預設語音、語速、睡眠定時器起始值</div>
              </div>
              <span class="text-lg font-bold">›</span>
            </div>
```
`new_string`
```
                <div class="text-[10px] opacity-75 mt-0.5">預設語音、語速、睡眠定時器起始值</div>
              </div>
              <span class="text-lg font-bold">›</span>
            </div>
            <div onclick="switchView('stats')" class="border-[1.5px] border-black rounded-md h-16 flex items-center px-4 justify-between cursor-pointer active:bg-black active:text-white">
              <div>
                <div class="text-sm font-black">閱讀統計</div>
                <div class="text-[10px] opacity-75 mt-0.5">近 365 天的閱讀時數與貢獻圖</div>
              </div>
              <span class="text-lg font-bold">›</span>
            </div>
```

- [x] **Step 5: 側欄加入畫面按鈕與情境選擇器**

Edit（畫面按鈕）：`old_string`（唯一）
```
          設定（四分區）
        </button>
```
`new_string`
```
          設定（四分區）
        </button>
        <button onclick="switchView('stats')" id="nav-stats" class="w-full text-left px-3 py-2 rounded text-sm font-semibold border-2 border-zinc-700 text-zinc-300 hover:border-zinc-500">
          閱讀統計（貢獻圖）
        </button>
```
Edit（情境選擇器）：`old_string`（唯一）
```
    <!-- 寬度模擬控制 -->
```
`new_string`
```
    <!-- 閱讀統計假資料情境（epic-9-stats） -->
    <div class="space-y-2">
      <label class="text-xs font-bold text-zinc-300 tracking-wider uppercase">閱讀統計假資料</label>
      <div class="grid grid-cols-1 gap-1.5">
        <button onclick="setStatsScenario('normal')" id="stats-scn-normal" class="text-left px-3 py-2 text-xs font-bold border-2 border-white text-white">一般（今天有讀、疏密不均）</button>
        <button onclick="setStatsScenario('todayEmpty')" id="stats-scn-todayEmpty" class="text-left px-3 py-2 text-xs font-bold border border-zinc-700 text-zinc-400">今天無紀錄</button>
        <button onclick="setStatsScenario('empty')" id="stats-scn-empty" class="text-left px-3 py-2 text-xs font-bold border border-zinc-700 text-zinc-400">全空（清除後）</button>
        <button onclick="setStatsScenario('heavy')" id="stats-scn-heavy" class="text-left px-3 py-2 text-xs font-bold border border-zinc-700 text-zinc-400">重度（每天都超過 60 分）</button>
      </div>
    </div>

    <!-- 寬度模擬控制 -->
```

- [x] **Step 6: `switchView` 加入 stats**

Edit：`old_string`
```
      const views = ['library', 'reader', 'layout', 'source', 'settings'];
```
`new_string`
```
      const views = ['library', 'reader', 'layout', 'source', 'settings', 'stats'];
```
Edit：`old_string`
```
      document.getElementById(`view-${viewName}`).classList.remove('hidden');
```
`new_string`
```
      document.getElementById(`view-${viewName}`).classList.remove('hidden');
      if (viewName === 'stats') enterStatsView(); // 進入統計畫面時才建立內容（隱藏時無法量測捲動寬度）
```

- [x] **Step 7: 暫時的空函式（Task 3 取代）**

Edit：`old_string`（唯一）
```
    // ============ 初始化 ============
```
`new_string`
```
    // ============ 閱讀統計畫面（epic-9-stats） ============
    function enterStatsView() {}
    function setStatsScenario(s) {}
    function openStatsClearDialog() {}
    function closeStatsClearDialog() {}
    function confirmStatsClear() {}

    // ============ 初始化 ============
```

- [x] **Step 8: 驗證**

Run:
```bash
node --test prototype/tests/
node -e "const h=require('fs').readFileSync('prototype/elinkbook_theme_prototype.html','utf8');const s=[...h.matchAll(/<script(?![^>]*src)[^>]*>([\s\S]*?)<\/script>/g)].map(m=>m[1]);s.forEach((c,i)=>{try{new Function(c)}catch(e){console.error('script',i,e.message);process.exit(1)}});console.log('ok',s.length)"
```
Expected: 測試 7 個通過；腳本語法檢查印出 `ok 3`。

手動：用瀏覽器開啟 `prototype/elinkbook_theme_prototype.html`，點「設定」→「閱讀統計」列，應切到一個有標題「閱讀統計」與返回鈕的空白畫面（內容在 Task 3 才出現）；返回鈕回到設定頁；側欄「閱讀統計（貢獻圖）」按鈕可切換並高亮。

- [x] **Step 9: Commit**

```bash
git add prototype/elinkbook_theme_prototype.html
git commit -m "feat(prototype): epic-9 Issue 1 統計畫面骨架、貢獻圖色階與 E-Ink 紋理"
```

---

### Task 3：貢獻圖渲染、詳情卡片、情境選擇器

**Files:**
- Modify: `prototype/elinkbook_theme_prototype.html`（以真正實作取代 Task 2 的空函式 `enterStatsView`、`setStatsScenario`）

**Interfaces:**
- Consumes: Task 1 的 `statsBuildHeatmapGrid`、`statsMockData`、`statsLevelForSeconds`、`statsFormatDuration`、`statsDayTotal`、`statsGrandTotal`、`statsDateKey`；Task 2 的 DOM id 與 class。
- Produces: `renderStats()`、`selectStatsDate(key)`、`renderStatsDetail()`、全域狀態 `statsScenario`、`statsData`、`statsToday`、`statsSelectedKey`（Task 4 會改動 `statsData` 並呼叫 `renderStats()`）。

- [ ] **Step 1: 取代空函式，實作渲染與互動**

Edit：`old_string`
```
    function enterStatsView() {}
    function setStatsScenario(s) {}
    function openStatsClearDialog() {}
```
`new_string`
```
    let statsScenario = 'normal';
    let statsData = {};
    let statsToday = new Date();
    let statsSelectedKey = null;
    const STATS_CELL = 16;
    const STATS_GAP = 3;
    const STATS_SCENARIOS = ['normal', 'todayEmpty', 'empty', 'heavy'];

    // 高亮側欄目前選中的假資料情境
    function highlightStatsScenario() {
      STATS_SCENARIOS.forEach(k => {
        const btn = document.getElementById(`stats-scn-${k}`);
        const active = k === statsScenario;
        btn.className = 'text-left px-3 py-2 text-xs font-bold border-2 ' +
          (active ? 'border-white text-white' : 'border-zinc-700 text-zinc-400');
      });
    }

    function setStatsScenario(s) {
      statsScenario = s;
      highlightStatsScenario();
      if (currentView === 'stats') enterStatsView(); // 統計畫面開著就立即重畫
    }

    // 進入統計畫面：重新取得「今天」、產生假資料、預設選中今天、捲到最右側
    function enterStatsView() {
      statsToday = new Date();
      statsData = statsMockData(statsToday, statsScenario);
      statsSelectedKey = statsDateKey(statsToday);
      renderStats();
      const sc = document.getElementById('stats-heatmap');
      sc.scrollLeft = sc.scrollWidth; // 預設捲到最右側（今天所在的一週）
    }

    function renderStats() {
      document.getElementById('stats-total').textContent = statsFormatDuration(statsGrandTotal(statsData));
      renderStatsHeatmap();
      renderStatsDetail();
    }

    function renderStatsHeatmap() {
      const { weeks, monthLabels } = statsBuildHeatmapGrid(statsToday);
      const pitch = STATS_CELL + STATS_GAP;
      const months = monthLabels.map(m =>
        `<span class="absolute text-[10px] leading-[14px] whitespace-nowrap" style="left:${m.weekIndex * pitch}px">${m.month} 月</span>`
      ).join('');
      const cols = weeks.map(col => {
        const cells = col.map(c => {
          if (!c) return '<div class="heat-cell heat-empty"></div>'; // 透明佔位，不可點擊
          const lv = statsLevelForSeconds(statsDayTotal(statsData, c.date));
          const sel = c.date === statsSelectedKey ? ' selected' : '';
          return `<button type="button" data-date="${c.date}" aria-label="${c.date}" onclick="selectStatsDate('${c.date}')" class="heat-cell heat-l${lv}${sel}"></button>`;
        }).join('');
        return `<div class="flex flex-col" style="gap:${STATS_GAP}px">${cells}</div>`;
      }).join('');
      document.getElementById('stats-heatmap-inner').innerHTML =
        `<div class="relative mb-[3px]" style="height:14px;width:${weeks.length * pitch}px">${months}</div>` +
        `<div class="flex" style="gap:${STATS_GAP}px">${cols}</div>`;
    }

    // 點選方格：只移動外框並更新詳情卡片，不重畫整張圖（保留捲動位置）
    function selectStatsDate(key) {
      statsSelectedKey = key;
      document.querySelectorAll('#stats-heatmap .heat-cell.selected').forEach(el => el.classList.remove('selected'));
      const target = document.querySelector(`#stats-heatmap .heat-cell[data-date="${key}"]`);
      if (target) target.classList.add('selected');
      renderStatsDetail();
    }

    // 詳情卡片：固定在貢獻圖下方；各書依時數由多到少；無紀錄顯示說明
    function renderStatsDetail() {
      const list = (statsData[statsSelectedKey] || []).slice().sort((a, b) => b.seconds - a.seconds);
      const body = list.length === 0
        ? '<div class="text-xs opacity-75 py-2">當日無閱讀記錄</div>'
        : list.map(b =>
            `<div class="flex items-center justify-between gap-2 py-1.5 border-b border-black">` +
            `<span class="text-sm font-bold break-words min-w-0 flex-1">${b.title}</span>` +
            `<span class="text-xs font-black flex-shrink-0">${statsFormatDuration(b.seconds)}</span></div>`
          ).join('');
      document.getElementById('stats-detail-card').innerHTML =
        `<div class="text-xs font-black mb-1">${statsSelectedKey} 閱讀明細</div>${body}`;
    }

    function openStatsClearDialog() {}
```

- [ ] **Step 2: 語法與測試**

Run:
```bash
node --test prototype/tests/
node -e "const h=require('fs').readFileSync('prototype/elinkbook_theme_prototype.html','utf8');const s=[...h.matchAll(/<script(?![^>]*src)[^>]*>([\s\S]*?)<\/script>/g)].map(m=>m[1]);s.forEach((c,i)=>{try{new Function(c)}catch(e){console.error('script',i,e.message);process.exit(1)}});console.log('ok',s.length)"
```
Expected: 7 通過；`ok 3`。

- [ ] **Step 3: 手動驗證（瀏覽器）**

開啟原型，設定 → 閱讀統計，依序確認並在每項打勾：
- [ ] 貢獻圖已捲到最右側，可看到最近一週與今天；往左拖曳可看到一年前。
- [ ] 左側「一、三、五」星期欄在水平捲動時**不動**，且與方格列對齊（一在第 1 列、三在第 3 列、五在第 5 列）。
- [ ] 月份標籤在方格上方，隨水平捲動移動。
- [ ] 星期欄的「一、三、五」各自單行顯示，沒有折行或被裁切。
- [ ] 最後一週今天之後的格子是空白（無顏色、點了沒反應）；第一週週一之前同理。
- [ ] 預設選中今天（有外框），下方卡片標題為「YYYY-MM-DD 閱讀明細」並列出書名與時數，由多到少。
- [ ] 預設選中的「今天」（最右側）外框四邊完整，右側與下側沒有被捲動容器裁掉。
- [ ] 點最上列（週一）與最下列（週日）的格子、以及往左捲到底後點第一週的格子：外框四邊都完整，沒有被裁切。
- [ ] 點另一格：外框移動、卡片切換；點沒有紀錄的日子顯示「當日無閱讀記錄」；捲動位置不跳動。
- [ ] 找到一天讀多本書：書名 `The Pragmatic Programmer` 自動換行，時數不被擠出卡片。
- [ ] 側欄選「今天無紀錄」：進入後預設選中今天並顯示「當日無閱讀記錄」。
- [ ] 側欄選「重度」：全部方格都是最深色（4 級）。
- [ ] 沒有任何浮動 Tooltip；圖例（較少 → 較多）五格顏色由淺到深。
- [ ] 累計總時數是合理的「X 小時 Y 分鐘」。

- [ ] **Step 4: Commit**

```bash
git add prototype/elinkbook_theme_prototype.html
git commit -m "feat(prototype): epic-9 Issue 1 貢獻圖渲染、詳情卡片與假資料情境"
```

---

### Task 4：清除全部統計與空白狀態

**Files:**
- Modify: `prototype/elinkbook_theme_prototype.html`

**Interfaces:**
- Consumes: Task 3 的 `statsData`、`statsScenario`、`renderStats()`、`highlightStatsScenario()`、`showNotification()`（既有）。
- Produces: `openStatsClearDialog()`、`closeStatsClearDialog()`、`confirmStatsClear()`。

- [ ] **Step 1: 實作對話框流程**

Edit：`old_string`
```
    function openStatsClearDialog() {}
    function closeStatsClearDialog() {}
    function confirmStatsClear() {}
```
`new_string`
```
    // 清除全部統計：必經確認對話框；確認後畫面回到空白狀態
    function openStatsClearDialog() {
      document.getElementById('stats-clear-dialog').classList.remove('hidden');
    }
    function closeStatsClearDialog() {
      document.getElementById('stats-clear-dialog').classList.add('hidden');
    }
    function confirmStatsClear() {
      statsScenario = 'empty';
      statsData = {};
      highlightStatsScenario();
      closeStatsClearDialog();
      renderStats();
      showNotification('已清除全部閱讀統計');
    }
```

- [ ] **Step 2: 語法與測試**

Run:
```bash
node --test prototype/tests/
node -e "const h=require('fs').readFileSync('prototype/elinkbook_theme_prototype.html','utf8');const s=[...h.matchAll(/<script(?![^>]*src)[^>]*>([\s\S]*?)<\/script>/g)].map(m=>m[1]);s.forEach((c,i)=>{try{new Function(c)}catch(e){console.error('script',i,e.message);process.exit(1)}});console.log('ok',s.length)"
```
Expected: 7 通過；`ok 3`。

- [ ] **Step 3: 手動驗證**

- [ ] 點「清除全部統計」：出現對話框，文字為「確定要清除所有閱讀統計嗎？此動作無法復原。」，有「取消」「清除」兩顆按鈕；背景畫面被遮住。
- [ ] 點「取消」：對話框關閉，資料完全不變。
- [ ] 按住「清除」按鈕不放：按鈕反相（底色與文字互換），四種主題組合都看得出按壓態。
- [ ] 點「清除」：對話框關閉、顯示通知「已清除全部閱讀統計」；累計總時數為「0 分鐘」；所有方格為 0 級；今天仍被選中，卡片顯示「當日無閱讀記錄」；側欄情境高亮變成「全空」。
- [ ] 清除後切離再回來（設定 → 閱讀統計）：仍為全空（情境已切為全空）。切換側欄情境為「一般」可復原假資料。

- [ ] **Step 4: Commit**

```bash
git add prototype/elinkbook_theme_prototype.html
git commit -m "feat(prototype): epic-9 Issue 1 清除全部統計確認流程與空白狀態"
```

---

### Task 5：四種主題組合驗證、記錄定案值、交人類確認

**Files:**
- Modify: `docs/epics/epic-9-stats/epic.md`（新增「Issue 1 完成記錄」）

**Interfaces:**
- Consumes: Task 1～4 的成果。
- Produces: 定案的色階、E-Ink 灰階與紋理值（供 Issue 5 逐字取用），以及交給人類確認的清單。

- [ ] **Step 1: 逐一驗證四種主題組合**

開啟原型，進入「閱讀統計」畫面，使用「一般」假資料，對下列四種組合各檢查一次並打勾（側欄切主題與 E-Ink；E-Ink 開啟時主題選擇器鎖住，屬既有行為）：
- [ ] Light：方格由淺藍到深藍五級可辨；被選方格外框清楚；文字對比足夠。
- [ ] Dark：方格在深色底上五級可辨（0 級不會與背景融在一起）；外框清楚。
- [ ] Sepia：由淺米到深紅五級可辨。
- [ ] E-Ink：方格全部有黑色硬邊框；0 級空白、1 級網點、2 級單向斜線、3 級交叉線、4 級實心黑；**五級在不看顏色（純黑白）下仍能彼此區分**；被選方格外框加粗（3px）；清除對話框遮罩為不透明白底。

- [ ] **Step 2: Review Focus 補驗**

- [ ] 橫向模擬（側欄「橫排 (4欄)」切到 640×480）：統計畫面版面不破、星期欄仍固定、可捲動；切回直向正常。
- [ ] 在統計畫面中切換 E-Ink 開／關，以及切換 Light／Dark／Sepia：方格顏色即時跟著變，沒有殘留舊色。
- [ ] 側欄「今天無紀錄」「全空」「重度」三情境各進入一次，版面正常。

- [ ] **Step 3: 最終自動化檢查**

Run:
```bash
node --test prototype/tests/
node -e "const h=require('fs').readFileSync('prototype/elinkbook_theme_prototype.html','utf8');const s=[...h.matchAll(/<script(?![^>]*src)[^>]*>([\s\S]*?)<\/script>/g)].map(m=>m[1]);s.forEach((c,i)=>{try{new Function(c)}catch(e){console.error('script',i,e.message);process.exit(1)}});console.log('ok',s.length)"
git status --short prototype/
```
Expected: 測試全過、`ok 3`；`git status --short prototype/` 沒有未提交變更，且本 Issue 的 commit 只動到 `elinkbook_theme_prototype.html` 與新增的 `tests/stats_logic.test.js`（沒有動其他原型檔）。

- [ ] **Step 4: 在 `epic.md` 記錄定案值與驗證結果**

在 `docs/epics/epic-9-stats/epic.md` 的「目前狀態」之前新增一節，內容如下（驗證結果照實填寫，未通過的項目要寫出來）：

```markdown
## Issue 1 完成記錄（原型，待人類確認）

**做了什麼：** `prototype/elinkbook_theme_prototype.html` 新增「閱讀統計」畫面（設定 → 閱讀統計；側欄「閱讀統計（貢獻圖）」），含 53 週貢獻圖、固定星期欄、Inline 詳情卡片、累計總時數、圖例、清除全部確認流程，以及四種假資料情境（一般／今天無紀錄／全空／重度）。純邏輯（分級、網格、假資料）以 `node --test prototype/tests/` 驗證。

**定案值（Issue 5 直接取用）：**

| 級別 | 意義 | Light | Dark | Sepia | E-Ink 灰階 | E-Ink 紋理 |
|---|---|---|---|---|---|---|
| 0 | 無紀錄 | `#eaf1f5` | `#2c2c34` | `#e6dfcb` | `#ffffff` | 留白 |
| 1 | 未滿 15 分 | `#bae6fd` | `#0c4a6e` | `#efd3c4` | `#d4d4d4` | 網點（4px 週期，1px 點） |
| 2 | 未滿 30 分 | `#7dd3fc` | `#0369a1` | `#dea08e` | `#a3a3a3` | 45° 單向斜線（4px 週期，1px 線） |
| 3 | 未滿 60 分 | `#38bdf8` | `#0ea5e9` | `#c85f4f` | `#525252` | 交叉斜線（4px 週期，1.5px 線） |
| 4 | 60 分以上 | `#0284c7` | `#7dd3fc` | `#b8362d` | `#000000` | 實心 |

- 方格 16px、間距 3px、圓角 2px（E-Ink 改 0、加 1px 黑框）；被選方格外框 2px（E-Ink 3px）、偏移 1px，且需提升層級（`z-index`）並在捲動容器左、右、下留 4px 內距，避免外框被裁切（Flutter 端繪製選取框時同樣要留出外擴空間）。
- 星期標籤欄寬 18px（含 4px 右內距，內容寬 14px），避免不同字型度量造成折行。
- E-Ink 下灰階值僅供參考，實際靠「黑框＋紋理」區分級別；灰階欄位供 Flutter 端 `ElinkTokens` 的 E-Ink 色值使用。
- 一週從週一開始；月份標籤置於方格上方，第一個標籤若與第二個相距不到 2 週則捨棄。
- 顯示規則：有紀錄但不滿 1 分鐘者顯示「1 分鐘」（避免出現「0 分鐘」；此為原型自訂，**待人類確認**）。
- 假資料：「重度」情境每日單書 65～154 分鐘；「一般」情境約 55% 的日子有紀錄，一天 1～3 本。

**驗證結果：** （照實填寫四種主題組合與 Review Focus 各項的結果）

**待人類確認：** 色階配色、E-Ink 紋理樣式、「不滿 1 分鐘顯示 1 分鐘」規則。確認前 Issue 5 不開始。
```

- [ ] **Step 5: Commit，並交給人類確認**

```bash
git add docs/epics/epic-9-stats/epic.md
git commit -m "docs(epic-9): 記錄 Issue 1 原型定案值與驗證結果，待人類確認"
```

之後**停止**，請人類開啟原型確認。在人類確認之前，不要把 `issues.md` 的 Issue 1 標為完成、不要開始 Issue 5。

---

## Self-Review

**Spec coverage：**
- 五級分級、週一起始、53 週、透明佔位、固定星期欄、水平捲動預設最右、月份標籤 → Task 1（邏輯與測試）、Task 2（版面）、Task 3（渲染與手動驗證）。
- 預設選中今天、外框、無紀錄說明、各書由多到少、無 Tooltip → Task 3。
- 累計總時數格式、圖例 → Task 1（格式）、Task 2（圖例 markup）、Task 3（渲染）。
- 清除全部確認、空白狀態 → Task 4。
- Light／Dark／Sepia 配色與 E-Ink 灰階＋紋理定案 → Task 2（CSS）、Task 5（驗證與記錄）。
- 「經人類確認後 Issue 5 才開始」→ Task 5 Step 5 停止點。
- issues.md Issue 1 四種主題組合驗證 → Task 5 Step 1。

**Placeholder 掃描：** 無 TBD／TODO；Task 5 的「驗證結果」欄位是執行者照實填寫的記錄欄，不是待補實作。

**型別一致性：** Task 1 的函式名稱（`statsLevelForSeconds`、`statsFormatDuration`、`statsBuildHeatmapGrid`、`statsMockData`、`statsDayTotal`、`statsGrandTotal`、`statsDateKey`）在 Task 3、4 的呼叫處一致；DOM id 與 class 名稱在 Task 2 定義、Task 3、4 使用，逐一核對相符。全域名稱在純邏輯腳本與主腳本之間不重複（純邏輯：`STATS_WINDOW_DAYS`、`STATS_MOCK_BOOKS`、`stats*` 函式；主腳本：`statsScenario`、`statsData`、`statsToday`、`statsSelectedKey`、`STATS_CELL`、`STATS_GAP`、`STATS_SCENARIOS`），避免經典 script 共用全域詞法作用域時的重複宣告錯誤。

**Review Focus：** 五項各有對應驗證（今天無紀錄與多書／長書名 → Task 3；全空 → Task 4；週日 → Task 1 測試；橫向與 E-Ink 切換 → Task 5）。
