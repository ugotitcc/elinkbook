// 選取收尾保護期（main.js 的 SELECTION_RELEASE_GUARD_MS）兩條分支的決定性場景。
//
// 為什麼不用真實時間差（epic-66 Issue 26）：這台 Windows 上，注入選取後立刻
// 送 `Input.dispatchTouchEvent touchStart` 的往返約 86～103 ms（原因未查明），
// 所以「選取 → mousedown」的真實間隔落在 150～195 ms，系統性超出 150 ms
// 保護期，舊版「真實時間 + 重試」的寫法無法穩定通過。
//
// 改法：把 iframe 的 performance.now 暫時換成「原值 ± 10 秒」，讓時間差的
// 正負由場景決定，與 CDP 往返延遲無關。
//   情境 A：+10 秒 → 差值約 -9900 ms，保護期必定生效 → 選取應維持
//   情境 B：-10 秒 → 差值約 +10000 ms，保護期必定已過 → 選取應被折疊
// 情境 B 同時守護原始 bug（main.js 註解：iframe 與最外層時鐘原點差近 850 ms，
// 若記錄時間誤用最外層時鐘，差值恆為負、保護期恆生效，選取折疊不了）。
//
// 取捨：門檻數值本身（150 ms）不會被任何情境驗證，真實時間下夠不夠用要靠真機
// 校準（見 main.js 註解）。
import {
  launchHarnessPage, injectSelectionAtVisibleText, clearSelection, selectionState,
  cdpTap, resetHarnessEvents, harnessEvents, report,
} from './lib/harness.mjs'

const settle = (ms) => new Promise((r) => setTimeout(r, ms))

// 把 iframe 的 performance.now 換成「原值 + offset」。必須綁定 this，否則 Illegal invocation。
function shiftClock(page, offset) {
  return page.evaluate((offset) => {
    const win = document.querySelector('foliate-view').renderer.shadowRoot
      .getElementById('container').querySelector('iframe').contentWindow
    const orig = win.performance.now.bind(win.performance)
    win.performance.now = () => orig() + offset
  }, offset)
}

// 移除實例上的覆寫，露出原型上的原生方法。
function restoreClock(page) {
  return page.evaluate(() => {
    const win = document.querySelector('foliate-view').renderer.shadowRoot
      .getElementById('container').querySelector('iframe').contentWindow
    delete win.performance.now
  })
}

// 等到 onSelectionChanged 事件出現（保證 lastNonCollapsedSelectionAtMs 已記錄），逾時回 false。
async function waitSelectionReported(page, timeoutMs = 2000) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    const events = await harnessEvents(page)
    if (events.some((e) => e.name === 'onSelectionChanged')) return true
    await settle(20)
  }
  return false
}

// 跑一個情境：換時鐘 → 注入選取 → 等回報 → 點擊別處 → 回傳點擊後選取狀態。
async function runScenario({ page, client, awayPoint, offset, label }) {
  await clearSelection(page)
  await resetHarnessEvents(page)
  await restoreClock(page)
  await shiftClock(page, offset)
  try {
    const injected = await injectSelectionAtVisibleText(page, { minLength: 8 })
    if (!injected) { report(`注入選取範圍（${label}）`, false); return null }
    const reported = await waitSelectionReported(page)
    if (!reported) { report(`等待 onSelectionChanged（${label}）`, false, '逾時 2 秒'); return null }
    await cdpTap(client, awayPoint.x, awayPoint.y, 80)
    await settle(300)
    return await selectionState(page)
  } finally {
    await restoreClock(page)
  }
}

async function main() {
  const { browser, page, client } = await launchHarnessPage({
    fixtureFileName: 'sample.epub',
    writingMode: 'horizontal',
  })
  try {
    const awayPoint = await page.evaluate(() => {
      const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
      const r = container?.querySelector('iframe')?.getBoundingClientRect()
      if (!r) return null
      return { x: r.left + r.width * 0.9, y: r.top + r.height * 0.9 }
    })
    if (!awayPoint) { report('取得遠離選取範圍的座標', false); return }

    const a = await runScenario({ page, client, awayPoint, offset: 10000, label: '情境 A' })
    if (a) {
      report('選取收尾保護期內快速點擊別處，選取維持存在', !a.isCollapsed, `after.isCollapsed=${a.isCollapsed}`)
    }

    const b = await runScenario({ page, client, awayPoint, offset: -10000, label: '情境 B' })
    if (b) {
      report('選取收尾保護期已過後快速點擊別處，選取正常被折疊', b.isCollapsed, `after.isCollapsed=${b.isCollapsed}`)
    }
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
