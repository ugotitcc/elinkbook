// 回歸：離開書本後用儲存的 CFI 重新開書，必須回到「同一頁」，不是章首或前一頁。
// 症狀（直排）：開書時 goTo 發生在直排樣式套用之前，重排後位置被拉回該章第一頁。
// 流程：連續翻頁並記錄每頁 CFI（含跨章，必須走到全書最後一頁）→ 取樣每個 CFI 各自新開頁面還原
// → 比對 CFI 完全一致，並要求兩端頁面都沒有未捕捉例外。
// 另驗證：橫排開書後離開開書位置，再切直排不得倒跳回開書位置。
import { launchHarnessPage, report } from './lib/harness.mjs'
import { buildMultiChapterEpub } from './lib/multi-chapter-epub.mjs'

const PHONE = { width: 376, height: 752 }
const WIDE = { width: 800, height: 1200 } // 橫排自動排成雙欄
const STEP = Number(process.env.STEP || 3) // 每 STEP 頁取樣一次；STEP=1 全部驗證
const MAX_TURNS = 150 // 上限要大於全書頁數；沒走到最後一頁會報失敗，不會默默截斷

// writingMode: null 代表開書時不指定方向，改依書內 CSS 自動偵測（verticalCss 讓書本自己宣告直排）。
const CASES = [
  { name: '橫排單欄', writingMode: 'horizontal', viewport: PHONE },
  { name: '直排', writingMode: 'vertical', viewport: PHONE },
  { name: '橫排雙欄', writingMode: 'horizontal', viewport: WIDE },
  { name: '直排（書內 CSS 自動偵測）', writingMode: null, viewport: PHONE, verticalCss: true },
]

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

async function collectPages(c) {
  const A = await launchHarnessPage({
    fixtureBuffer: buildMultiChapterEpub({ verticalCss: c.verticalCss }),
    writingMode: c.writingMode,
    viewport: c.viewport,
  })
  const pages = [lastLoc(await A.page.evaluate(() => window.__harnessEvents))]
  let reachedEnd = false
  for (let i = 0; i < MAX_TURNS; i++) {
    await A.page.evaluate(() => window.nextPage())
    await wait(250)
    const p = lastLoc(await A.page.evaluate(() => window.__harnessEvents))
    if (p.cfi === pages[pages.length - 1].cfi) { reachedEnd = true; break }
    pages.push(p)
  }
  const errors = [...A.pageErrors]
  await closeBrowser(A.browser)
  return { pages, reachedEnd, errors }
}

async function reopenAt(c, saved) {
  const B = await launchHarnessPage({
    fixtureBuffer: buildMultiChapterEpub({ verticalCss: c.verticalCss }),
    writingMode: c.writingMode,
    viewport: c.viewport,
    initialCfi: saved.cfi,
    initialProgression: saved.fraction,
  })
  await wait(800)
  const got = lastLoc(await B.page.evaluate(() => window.__harnessEvents))
  const errors = [...B.pageErrors]
  await closeBrowser(B.browser)
  return { got, errors }
}

async function checkResumeSamePage(c) {
  const { pages, reachedEnd, errors } = await collectPages(c)
  const lastChapter = pages[pages.length - 1].index
  report(`${c.name}：翻頁走到全書最後一頁（共 ${pages.length} 頁，最後在第 ${lastChapter} 章）`, reachedEnd && lastChapter === 2)
  const bad = []
  for (let i = 0; i < pages.length; i += STEP) {
    const r = await reopenAt(c, pages[i])
    errors.push(...r.errors)
    if (r.got.cfi !== pages[i].cfi) bad.push(`p${i} want=${pages[i].fraction.toFixed(4)} got=${r.got.fraction.toFixed(4)}`)
  }
  report(`${c.name}：每 ${STEP} 頁取樣，重開後都回到同一頁`, bad.length === 0, bad.join('; '))
  report(`${c.name}：頁面沒有未捕捉例外`, errors.length === 0, errors.join('; '))
}

// 橫排開書後，用不經 window.nextPage 的內部導覽（模擬捲動模式、書內連結）離開開書位置，
// 再切成直排：必須留在目前位置，不得倒跳回開書位置。
async function checkNoJumpBackAfterModeSwitch() {
  const openCfi = 'epubcfi(/6/2!/4/6,/1:625,/1:1285)'
  const A = await launchHarnessPage({
    fixtureBuffer: buildMultiChapterEpub(),
    writingMode: 'horizontal',
    viewport: PHONE,
    initialCfi: openCfi,
    initialProgression: 0.05,
  })
  await wait(800)
  const atOpen = lastLoc(await A.page.evaluate(() => window.__harnessEvents))
  for (let i = 0; i < 8; i++) {
    await A.page.evaluate(() => document.getElementById('view').next())
    await wait(250)
  }
  const moved = lastLoc(await A.page.evaluate(() => window.__harnessEvents))
  await A.page.evaluate(() => window.applyPreferences({
    writingMode: 'vertical', fontSize: 1.0, lineHeight: 1.0, paragraphSpacing: 1.0,
    marginTop: 32, marginBottom: 16, marginLeft: 24, marginRight: 24,
    pageTurnMode: 'paginated', columnMode: 'auto', columnSize: 720,
  }))
  await wait(1500)
  const after = lastLoc(await A.page.evaluate(() => window.__harnessEvents))
  const errors = [...A.pageErrors]
  await closeBrowser(A.browser)

  report('倒跳檢查前提：內部導覽確實離開了開書位置', moved.fraction > atOpen.fraction + 0.05,
    `open=${atOpen.fraction.toFixed(4)} moved=${moved.fraction.toFixed(4)}`)
  report('橫排開書後離開開書位置再切直排：留在目前位置，不倒跳回開書位置',
    Math.abs(after.fraction - moved.fraction) < Math.abs(after.fraction - atOpen.fraction),
    `open=${atOpen.fraction.toFixed(4)} moved=${moved.fraction.toFixed(4)} after=${after.fraction.toFixed(4)}`)
  report('倒跳檢查：頁面沒有未捕捉例外', errors.length === 0, errors.join('; '))
}

async function main() {
  for (const c of CASES) await checkResumeSamePage(c)
  await checkNoJumpBackAfterModeSwitch()
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
