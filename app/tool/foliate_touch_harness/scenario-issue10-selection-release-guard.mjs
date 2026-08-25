import {
  launchHarnessPage, injectSelectionAtVisibleText, clearSelection, selectionState, cdpTap, report,
} from './lib/harness.mjs'

async function main() {
  const { browser, page, client } = await launchHarnessPage({
    fixtureFileName: 'sample_horizontal.epub',
    writingMode: 'horizontal',
  })
  try {
    // 情境 A：選取剛確立，立刻在選取本身位置做一次短按——保護期內，
    // 選取應維持存在。
    const injectedA = await injectSelectionAtVisibleText(page, { minLength: 8 })
    if (!injectedA) { report('注入選取範圍（情境 A）', false); return }
    const beforeA = await selectionState(page)
    const rectA = await page.evaluate(() => {
      const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
      const iframe = container?.querySelector('iframe')
      const sel = iframe?.contentDocument?.getSelection()
      const r = sel?.getRangeAt(0)?.getClientRects()?.[0]
      const iframeRect = iframe?.getBoundingClientRect()
      if (!r || !iframeRect) return null
      return { x: iframeRect.left + r.left + r.width / 2, y: iframeRect.top + r.top + r.height / 2 }
    })
    if (!rectA) { report('取得選取範圍畫面座標（情境 A）', false); return }
    await cdpTap(client, rectA.x, rectA.y, 80)
    await new Promise((r) => setTimeout(r, 100))
    const afterA = await selectionState(page)
    report('選取剛確立、保護期內在選取本身位置短按，選取維持存在',
      !beforeA.isCollapsed && !afterA.isCollapsed,
      `before.isCollapsed=${beforeA.isCollapsed}, after.isCollapsed=${afterA.isCollapsed}`)

    // 情境 B（對照組）：選取確立後等待超過保護期（150ms），再點擊選取
    // 以外的位置——保護期已過，選取應正常被折疊（證明保護不是永久生效，
    // 只在收尾雜訊窗口內生效）。
    await clearSelection(page)
    const injectedB = await injectSelectionAtVisibleText(page, { minLength: 8 })
    if (!injectedB) { report('注入選取範圍（情境 B）', false); return }
    const beforeB = await selectionState(page)
    const awayPoint = await page.evaluate(() => {
      const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
      const iframe = container?.querySelector('iframe')
      const r = iframe?.getBoundingClientRect()
      if (!r) return null
      return { x: r.left + r.width * 0.9, y: r.top + r.height * 0.9 }
    })
    if (!awayPoint) { report('取得遠離選取範圍的座標（情境 B）', false); return }
    await new Promise((r) => setTimeout(r, 250))
    await cdpTap(client, awayPoint.x, awayPoint.y, 80)
    await new Promise((r) => setTimeout(r, 100))
    const afterB = await selectionState(page)
    report('選取收尾保護期已過後點擊別處，選取正常被折疊',
      !beforeB.isCollapsed && afterB.isCollapsed,
      `before.isCollapsed=${beforeB.isCollapsed}, after.isCollapsed=${afterB.isCollapsed}`)
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
