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
    //
    // 【已知計時脆弱性，見 reviews/review-code-issue-1.md Important #1】
    // 保護期由 main.js 內 iframe 自己的 performance.now() 量測，屬真實
    // 瀏覽器時鐘，系統負載較高時，注入選取到 cdpTap 之間的延遲可能逼近
    // 150ms 門檻，讓 mousedown 被誤判為「保護期已過」，造成與邏輯本身
    // 無關的偶發 FAIL。這裡刻意不在 cdpTap 前多插一次
    // `selectionState(page)` 往返查詢「注入後選取是否非折疊」——
    // `injectSelectionAtVisibleText` 成功時，選取範圍必然橫跨
    // `minLength` 個字元、必為非折疊，不需要額外往返確認，藉此縮短
    // 「選取確立」到「cdpTap 發出」之間的真實耗時，直接加大安全邊際。
    // 並最多重試 5 次以吸收系統負載造成的整段時序偏移；5 次都落在保護期
    // 外才真正回報 FAIL。
    let passedA = false
    let detailA = ''
    for (let attempt = 1; attempt <= 5 && !passedA; attempt++) {
      if (attempt > 1) await clearSelection(page)
      const injectedA = await injectSelectionAtVisibleText(page, { minLength: 8 })
      if (!injectedA) { report('注入選取範圍（情境 A）', false); return }
      await cdpTap(client, awayPoint.x, awayPoint.y, 80)
      await new Promise((r) => setTimeout(r, 100))
      const afterA = await selectionState(page)
      passedA = !afterA.isCollapsed
      detailA = `attempt=${attempt}, after.isCollapsed=${afterA.isCollapsed}`
    }
    report('選取收尾保護期內快速點擊別處，選取維持存在', passedA, detailA)

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
