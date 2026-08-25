import {
  launchHarnessPage, locateVisibleText, setDecorationsAt,
  cdpTap, report,
} from './lib/harness.mjs'

async function main() {
  const { browser, page, client } = await launchHarnessPage({
    fixtureFileName: 'sample_long_chinese_vertical.epub',
    writingMode: 'vertical',
  })
  try {
    const target = await locateVisibleText(page, { minLength: 6 })
    if (!target) { report('找到可視文字節點', false); return }

    await setDecorationsAt(page, [{ id: 'target', cfi: target.cfi, color: 'yellow', isUnderline: false }])
    await new Promise((r) => setTimeout(r, 200))

    // 監聽 foliate-view 上的 show-annotation 事件（view.js 在 click 命中
    // 畫線且未被 main.js 攔截時發出），記錄觸發次數。
    await page.evaluate(() => {
      window.__showAnnotationFired = 0
      document.querySelector('foliate-view')?.addEventListener('show-annotation', () => {
        window.__showAnnotationFired++
      })
    })

    // 情境 A：短按（80ms）直接點在畫線上，應被攔截，不觸發
    // show-annotation。
    await page.evaluate(() => { window.__showAnnotationFired = 0 })
    await cdpTap(client, target.pageX, target.pageY, 80)
    await new Promise((r) => setTimeout(r, 300))
    const shortTapFired = await page.evaluate(() => window.__showAnnotationFired)
    report('短按 80ms 直接點在畫線上，click 被攔截', shortTapFired === 0)

    // 情境 B：長按（900ms，原地不動）直接點在畫線上，應正常觸發
    // show-annotation（900ms > ANNOTATION_CLICK_TAP_MAX_MS=700ms）。
    await page.evaluate(() => { window.__showAnnotationFired = 0 })
    await cdpTap(client, target.pageX, target.pageY, 900)
    await new Promise((r) => setTimeout(r, 300))
    const longPressFired = await page.evaluate(() => window.__showAnnotationFired)
    report('長按 900ms 直接點在畫線上，click 正常觸發', longPressFired > 0)

    // 情境 C：短按（80ms）點在超連結上，連結點擊不受畫線攔截邏輯影響
    // （main.js 明確排除 a[href]）。動態插入 <a> 到目前可視 doc，純測試
    // target.closest('a[href]') 排除邏輯，不依賴 fixture 本身含超連結。
    const linkSetup = await page.evaluate(() => {
      const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
      const iframe = container?.querySelector('iframe')
      const doc = iframe?.contentDocument
      if (!doc?.body) return null
      const a = doc.createElement('a')
      a.href = '#test-link'
      a.textContent = 'LINK'
      a.style.position = 'absolute'
      a.style.left = '40px'
      a.style.top = '40px'
      a.style.zIndex = '9999'
      doc.body.appendChild(a)
      window.__linkClicked = false
      a.addEventListener('click', (e) => { e.preventDefault(); window.__linkClicked = true })
      const rect = a.getBoundingClientRect()
      const iframeRect = iframe.getBoundingClientRect()
      return { pageX: iframeRect.left + rect.left + rect.width / 2, pageY: iframeRect.top + rect.top + rect.height / 2 }
    })
    if (linkSetup) {
      await cdpTap(client, linkSetup.pageX, linkSetup.pageY, 80)
      await new Promise((r) => setTimeout(r, 300))
      const linkClicked = await page.evaluate(() => window.__linkClicked === true)
      report('短按 80ms 點在超連結上，連結點擊不受影響', linkClicked)
    } else {
      report('短按 80ms 點在超連結上，連結點擊不受影響', false, '無法插入測試用連結元素')
    }
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
