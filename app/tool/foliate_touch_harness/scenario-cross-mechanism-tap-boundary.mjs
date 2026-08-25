import {
  launchHarnessPage, injectSelectionAtVisibleText, clearSelection, selectionState, cdpTap, report,
} from './lib/harness.mjs'

async function main() {
  const { browser, page, client } = await launchHarnessPage({
    fixtureFileName: 'sample.epub',
    writingMode: 'horizontal',
  })
  try {
    const awayPoint = await page.evaluate(() => {
      const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
      const iframe = container?.querySelector('iframe')
      const r = iframe?.getBoundingClientRect()
      if (!r) return null
      return { x: r.left + r.width * 0.9, y: r.top + r.height * 0.9 }
    })
    if (!awayPoint) { report('取得遠離選取範圍的座標', false); return }

    // 情境 A：選取確立後立刻（保護期 150ms 內）快速點擊別處——click 本身
    // 正常合成（不受選取保護機制阻擋），且選取應該維持存在（mousedown
    // 被攔截）。
    const injectedA = await injectSelectionAtVisibleText(page, { minLength: 8 })
    if (!injectedA) { report('注入選取範圍（情境 A）', false); return }
    const beforeA = await selectionState(page)
    await cdpTap(client, awayPoint.x, awayPoint.y, 80)
    await new Promise((r) => setTimeout(r, 100))
    const afterA = await selectionState(page)
    report('選取收尾保護期內快速點擊別處，選取維持存在',
      !beforeA.isCollapsed && !afterA.isCollapsed,
      `before.isCollapsed=${beforeA.isCollapsed}, after.isCollapsed=${afterA.isCollapsed}`)

    // 情境 B（邊界對照組）：選取確立後等待超過保護期（250ms > 150ms）
    // 才點擊別處——選取這時應該正常被折疊，證明「快速點擊分類」機制
    // 本身仍正常運作、沒有被選取保護機制永久卡住。
    await clearSelection(page)
    const injectedB = await injectSelectionAtVisibleText(page, { minLength: 8 })
    if (!injectedB) { report('注入選取範圍（情境 B）', false); return }
    const beforeB = await selectionState(page)
    await new Promise((r) => setTimeout(r, 250))
    await cdpTap(client, awayPoint.x, awayPoint.y, 80)
    await new Promise((r) => setTimeout(r, 100))
    const afterB = await selectionState(page)
    report('選取收尾保護期已過後快速點擊別處，選取正常被折疊',
      !beforeB.isCollapsed && afterB.isCollapsed,
      `before.isCollapsed=${beforeB.isCollapsed}, after.isCollapsed=${afterB.isCollapsed}`)
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
