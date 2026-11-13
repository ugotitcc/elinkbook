// epic-66 Issue 24：雙欄一般翻頁的「目前章節」（relocate 回報的 tocItemId）。
//
// 現行判定（foliate TOCProgress.getProgress）是「range 內最後一個目錄項」。雙欄時 range 涵蓋
// 兩欄，所以標到第二欄才出現的標題，比使用者先讀到的那一欄多一節。規則（人類 2026-11-13，
// 規則 B）：雙欄時把「第一欄」當成單欄的那一頁，取第一欄範圍內最後一個目錄項；單欄不變。
//
// 預期值不手寫：用**獨立的 DOM 座標**當標準答案（fixture 的三個標題 h2#s1／s2／s3 各對應目錄
// id 1／2／3，開頭到 s1 之前為 id 0）：第一欄的邊界 ＝ renderer.start + renderer.size / columnCount
// （單欄時 columnCount 為 1，等於整頁），座標小於邊界的標題中最後一個就是答案。
// 橫排沿 x、直排沿 y（直排雙欄是上下兩欄，先讀上欄）。
//
// fixture：sample_single_spine_multi_anchor.epub（單一 spine、目錄 ids：
// 0 單檔範例、1 第一節、2 第二節、3 第三節）。每次翻頁後補欄會連續回報兩次，
// 所以等約 900 ms 後取「最後一筆 onLocatorChanged」。
import { launchHarnessPage, report } from './lib/harness.mjs'

async function reported(page) {
  return page.evaluate(() => {
    const events = window.__harnessEvents.filter((e) => e.name === 'onLocatorChanged')
    const last = events[events.length - 1]
    return last ? JSON.parse(last.args[1]).tocItemId : undefined
  })
}

// 標準答案：以標題實際座標與第一欄邊界推算。
async function oracle(page) {
  return page.evaluate(() => {
    const view = document.querySelector('foliate-view')
    const r = view.renderer
    const doc = r.shadowRoot.getElementById('container').querySelector('iframe').contentDocument
    const vertical = doc.defaultView.getComputedStyle(doc.documentElement).writingMode.startsWith('vertical')
    const boundary = r.start + r.size / r.columnCount
    let id = 0
    for (const [anchor, itemId] of [['s1', 1], ['s2', 2], ['s3', 3]]) {
      const rc = doc.getElementById(anchor).getBoundingClientRect()
      if ((vertical ? rc.top : rc.left) < boundary) id = itemId
    }
    return { id, cols: r.columnCount, start: Math.round(r.start) }
  })
}

const settle = (ms) => new Promise((r) => setTimeout(r, ms))

async function runCase({ title, writingMode, viewport, columnMode, expectCols, turns }) {
  const { browser, page, pageErrors } = await launchHarnessPage({
    fixtureFileName: 'sample_single_spine_multi_anchor.epub',
    writingMode,
    viewport,
    prefs: { columnMode, columnSize: 720 },
  })
  try {
    report(`${title}：頁面載入無 pageerror`, pageErrors.length === 0, JSON.stringify(pageErrors))
    await settle(1500)
    const mismatches = []
    const seen = new Set()
    let cols = null
    for (let turn = 0; turn <= turns; turn++) {
      if (turn > 0) {
        await page.evaluate(() => window.nextPage())
        await settle(900)
      }
      const exp = await oracle(page)
      cols = exp.cols
      const got = await reported(page)
      seen.add(`${exp.id}`)
      if (got !== exp.id) mismatches.push(`第 ${turn} 頁（start=${exp.start}）應為 ${exp.id} 實際 ${got}`)
    }
    report(`${title}：欄數為 ${expectCols}（雙欄偵測前提）`, cols === expectCols, `實際欄數＝${cols}`)
    report(`${title}：逐頁 ${turns + 1} 頁的 tocItemId 都等於第一欄的標準答案`, mismatches.length === 0, mismatches.join('；'))
    // 避免空轉通過：這幾頁必須真的涵蓋 id 1、2、3，否則標準答案沒有分辨力。
    report(`${title}：測試涵蓋的標準答案包含 1、2、3（避免空轉）`, ['1', '2', '3'].every((x) => seen.has(x)), `涵蓋＝${[...seen].join(',')}`)

    // 錨點跳轉：跳到第三節（用目錄項的真實 href）後也要等於標準答案。
    await page.evaluate(() => {
      const view = document.querySelector('foliate-view')
      const flat = (items) => items.flatMap((i) => [i, ...flat(i.subitems ?? [])])
      const target = flat(view.book.toc).find((i) => i.label.trim() === '第三節')
      return view.goTo(target.href)
    })
    await settle(1500)
    const expJump = await oracle(page)
    const gotJump = await reported(page)
    report(`${title}：跳到第三節後 tocItemId 等於第一欄的標準答案`, gotJump === expJump.id, `標準答案＝${expJump.id}（start=${expJump.start}）實際＝${gotJump}`)
  } finally {
    await browser.close()
  }
}

async function main() {
  await runCase({ title: '雙欄橫排 1280x800', writingMode: 'horizontal', viewport: { width: 1280, height: 800 }, columnMode: 'auto', expectCols: 2, turns: 6 })
  await runCase({ title: '雙欄直排 1280x800', writingMode: 'vertical', viewport: { width: 1280, height: 800 }, columnMode: 'auto', expectCols: 2, turns: 5 })
  // 單欄必須維持「該頁最後一個目錄項」（回歸防護，本 Issue 不得改變）：標準答案的邊界在單欄時
  // 就是整頁，所以同一支標準答案也適用。
  await runCase({ title: '單欄橫排 400x800', writingMode: 'horizontal', viewport: { width: 400, height: 800 }, columnMode: 'auto', expectCols: 1, turns: 12 })
  await runCase({ title: '強制單欄橫排 1280x800', writingMode: 'horizontal', viewport: { width: 1280, height: 800 }, columnMode: 'single', expectCols: 1, turns: 8 })
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
