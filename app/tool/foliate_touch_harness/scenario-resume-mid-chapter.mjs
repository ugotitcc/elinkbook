// 回歸：離開書本後用儲存的 CFI 重新開書，必須回到「同一頁」，不是章首或前一頁。
// 症狀（直排）：開書時 goTo 發生在直排樣式套用之前，重排後位置被拉回該章第一頁。
// 流程：真機尺寸連續翻頁並記錄每頁 CFI（含跨章）→ 取樣每個 CFI 各自新開頁面還原 → 比對 CFI 完全一致。
import { launchHarnessPage, report } from './lib/harness.mjs'
import { buildMultiChapterEpub } from './lib/multi-chapter-epub.mjs'

const VIEWPORT = { width: 376, height: 752 }
const STEP = Number(process.env.STEP || 3) // 每 STEP 頁取樣一次；STEP=1 全部驗證
const MAX_TURNS = 60

const lastLoc = (events) => {
  const hits = events.filter((e) => e.name === 'onLocatorChanged')
  return JSON.parse(hits[hits.length - 1].args[0])
}
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
// 翻進下一章後 browser.close() 偶爾不回應：逾時就強制結束瀏覽器程序
async function closeBrowser(browser) {
  const proc = browser.process()
  await Promise.race([browser.close(), wait(3000)])
  proc?.kill('SIGKILL')
}

async function collectPages(writingMode) {
  const A = await launchHarnessPage({ fixtureBuffer: buildMultiChapterEpub(), writingMode, viewport: VIEWPORT })
  const pages = [lastLoc(await A.page.evaluate(() => window.__harnessEvents))]
  for (let i = 0; i < MAX_TURNS; i++) {
    await A.page.evaluate(() => window.nextPage())
    await wait(250)
    const p = lastLoc(await A.page.evaluate(() => window.__harnessEvents))
    if (p.cfi === pages[pages.length - 1].cfi) break
    pages.push(p)
  }
  await closeBrowser(A.browser)
  return pages
}

async function reopenAt(writingMode, saved) {
  const B = await launchHarnessPage({
    fixtureBuffer: buildMultiChapterEpub(),
    writingMode,
    viewport: VIEWPORT,
    initialCfi: saved.cfi,
    initialProgression: saved.fraction,
  })
  await wait(800)
  const got = lastLoc(await B.page.evaluate(() => window.__harnessEvents))
  await closeBrowser(B.browser)
  return got
}

async function main() {
  for (const mode of ['horizontal', 'vertical']) {
    const pages = await collectPages(mode)
    const bad = []
    for (let i = 0; i < pages.length; i += STEP) {
      const got = await reopenAt(mode, pages[i])
      if (got.cfi !== pages[i].cfi) bad.push(`p${i} want=${pages[i].fraction.toFixed(4)} got=${got.fraction.toFixed(4)}`)
    }
    report(`${mode}：${pages.length} 頁中每 ${STEP} 頁取樣，重開後都回到同一頁`, bad.length === 0, bad.join('; '))
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
