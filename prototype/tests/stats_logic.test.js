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
