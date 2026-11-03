// epic-67 Issue 5：開書後點擊書籤／註記跳轉，CFI 失效時改用概略進度並回報降級。
// 現況（修正前）：索引超界時 view.goTo 回傳看似成功但位置不動；格式損壞時回傳
// undefined、位置不動；兩者都沒有任何回報。
import { launchHarnessPage, report, resetHarnessEvents } from './lib/harness.mjs'
import { buildMultiChapterEpub } from './lib/multi-chapter-epub.mjs'

const settle = () => new Promise((r) => setTimeout(r, 700))

function lastLocation(events) {
  const hits = events.filter((e) => e.name === 'onLocatorChanged')
  return hits.length ? JSON.parse(hits[hits.length - 1].args[0]) : null
}
const degradedReasons = (events) =>
  events.filter((e) => e.name === 'onNavigationDegraded').map((e) => e.args[0])

// 每個案例都重新開書（起點固定在書頭），避免前一案例的位置影響斷言。
async function runCase(cfi, fallback) {
  const { browser, page } = await launchHarnessPage({ fixtureBuffer: buildMultiChapterEpub() })
  try {
    await new Promise((r) => setTimeout(r, 800))
    await resetHarnessEvents(page)
    await page.evaluate((cfi, fallback) => window.jumpToLocator(cfi, fallback), cfi, fallback)
    await settle()
    return await page.evaluate(() => window.__harnessEvents)
  } finally {
    await browser.close()
  }
}

async function main() {
  // A. 有效 CFI（第 2 章）：直接跳過去，不降級（即使帶了進度比例）
  {
    const events = await runCase('epubcfi(/6/6!/4/4)', 0.1)
    report('A 有效 CFI：落在第 2 章', lastLocation(events)?.index === 2, JSON.stringify(lastLocation(events)))
    report('A 有效 CFI：不回報降級', degradedReasons(events).length === 0)
  }
  // B. 章節索引超界＋進度比例 0.8：改跳 0.8 並回報 annotation
  {
    const events = await runCase('epubcfi(/6/40!/4/2)', 0.8)
    const loc = lastLocation(events)
    report('B 索引超界：改跳進度比例（約 0.8）', loc !== null && Math.abs(loc.fraction - 0.8) < 0.15, JSON.stringify(loc))
    report('B 索引超界：回報一次 annotation 降級', JSON.stringify(degradedReasons(events)) === '["annotation"]', JSON.stringify(degradedReasons(events)))
  }
  // C. 格式損壞＋進度比例：同上
  {
    const events = await runCase('epubcfi(/6/4!/4/', 0.8)
    const loc = lastLocation(events)
    report('C 格式損壞：改跳進度比例（約 0.8）', loc !== null && Math.abs(loc.fraction - 0.8) < 0.15, JSON.stringify(loc))
    report('C 格式損壞：回報一次 annotation 降級', JSON.stringify(degradedReasons(events)) === '["annotation"]')
  }
  // D. 舊資料沒有進度比例（null）：位置不動、不崩潰、仍回報
  {
    const events = await runCase('epubcfi(/6/40!/4/2)', null)
    report('D 無進度比例：仍回報一次 annotation 降級', JSON.stringify(degradedReasons(events)) === '["annotation"]')
    const moved = events.some((e) => e.name === 'onLocatorChanged')
    report('D 無進度比例：位置不移動（沒有新的 onLocatorChanged）', !moved, JSON.stringify(lastLocation(events)))
  }
  // E. 進度比例 NaN／超出範圍：NaN 視為沒有；1.7 夾限到書尾
  {
    const nanEvents = await runCase('epubcfi(/6/40!/4/2)', NaN)
    report('E1 比例 NaN：視為沒有比例，仍回報且不移動', JSON.stringify(degradedReasons(nanEvents)) === '["annotation"]' && !nanEvents.some((e) => e.name === 'onLocatorChanged'))
    const bigEvents = await runCase('epubcfi(/6/40!/4/2)', 1.7)
    report('E2 比例 1.7：夾限後落在書尾（第 2 章）', lastLocation(bigEvents)?.index === 2, JSON.stringify(lastLocation(bigEvents)))
  }
  // H. 舊格式 Readium Locator JSON（Dart 端 extractCfi 無法解析，會原字串交給 JS）
  {
    const legacy = '{"href":"c2.xhtml","locations":{"progression":0.3}}'
    const events = await runCase(legacy, 0.8)
    const loc = lastLocation(events)
    report('H 舊格式 JSON：改跳進度比例（約 0.8）', loc !== null && Math.abs(loc.fraction - 0.8) < 0.15, JSON.stringify(loc))
    report('H 舊格式 JSON：回報一次 annotation 降級', JSON.stringify(degradedReasons(events)) === '["annotation"]')
  }
  // F. 元素路徑不存在：Foliate 落在該章節，不是失敗，不得誤報
  {
    const events = await runCase('epubcfi(/6/6!/4/900/2)', 0.1)
    report('F 元素不存在：落在第 2 章', lastLocation(events)?.index === 2, JSON.stringify(lastLocation(events)))
    report('F 元素不存在：不回報降級', degradedReasons(events).length === 0)
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
