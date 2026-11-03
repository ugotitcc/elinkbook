// epic-67 Issue 5：開書時精確定位（initialCfi）失效的降級。
// 現況（修正前）：章節索引超界會讓整本書卡住（onPageRendered／onError 都不來）；
// CFI 格式損壞會靜默開在書頭。修正後應改用 initialProgression 定位並回報降級。
import { launchHarnessPage, report } from './lib/harness.mjs'
import { buildMultiChapterEpub } from './lib/multi-chapter-epub.mjs'

async function openWith({ initialCfi, initialProgression }) {
  try {
    const { browser, page } = await launchHarnessPage({
      fixtureBuffer: buildMultiChapterEpub(),
      initialCfi,
      initialProgression,
    })
    await new Promise((r) => setTimeout(r, 800))
    const events = await page.evaluate(() => window.__harnessEvents)
    await browser.close()
    return { opened: true, events }
  } catch (err) {
    return { opened: false, events: [], error: String(err).slice(0, 120) }
  }
}

function lastLocation(events) {
  const hits = events.filter((e) => e.name === 'onLocatorChanged')
  return hits.length ? JSON.parse(hits[hits.length - 1].args[0]) : null
}
const degradedReasons = (events) =>
  events.filter((e) => e.name === 'onNavigationDegraded').map((e) => e.args[0])

async function main() {
  // A. 有效 CFI（第 1 章）：正常定位，不降級
  {
    const r = await openWith({ initialCfi: 'epubcfi(/6/4!/4/4)', initialProgression: 0.9 })
    report('A 有效 CFI：開書成功', r.opened, r.error)
    report('A 有效 CFI：落在第 1 章', lastLocation(r.events)?.index === 1, JSON.stringify(lastLocation(r.events)))
    report('A 有效 CFI：不回報降級', degradedReasons(r.events).length === 0)
  }
  // B. 章節索引超界＋有進度比例：不得卡死，改用 0.8 定位並回報
  {
    const r = await openWith({ initialCfi: 'epubcfi(/6/40!/4/2)', initialProgression: 0.8 })
    report('B 索引超界：開書不卡死', r.opened, r.error)
    const loc = lastLocation(r.events)
    report('B 索引超界：改用進度比例定位（約 0.8）', loc !== null && Math.abs(loc.fraction - 0.8) < 0.15, JSON.stringify(loc))
    report('B 索引超界：回報一次 readingPosition 降級', JSON.stringify(degradedReasons(r.events)) === '["readingPosition"]', JSON.stringify(degradedReasons(r.events)))
  }
  // C. CFI 格式損壞＋有進度比例：不得靜默開在書頭
  {
    const r = await openWith({ initialCfi: 'epubcfi(/6/4!/4/', initialProgression: 0.8 })
    const loc = lastLocation(r.events)
    report('C 格式損壞：改用進度比例定位（約 0.8）', loc !== null && Math.abs(loc.fraction - 0.8) < 0.15, JSON.stringify(loc))
    report('C 格式損壞：回報一次 readingPosition 降級', JSON.stringify(degradedReasons(r.events)) === '["readingPosition"]')
  }
  // D. 索引超界＋沒有進度比例（例如搜尋結果跳轉）：開在書頭、仍回報
  {
    const r = await openWith({ initialCfi: 'epubcfi(/6/40!/4/2)', initialProgression: null })
    report('D 無進度比例：開書不卡死', r.opened, r.error)
    report('D 無進度比例：開在書頭（第 0 章）', lastLocation(r.events)?.index === 0, JSON.stringify(lastLocation(r.events)))
    report('D 無進度比例：回報一次 readingPosition 降級', JSON.stringify(degradedReasons(r.events)) === '["readingPosition"]')
  }
  // E. 進度比例超出範圍（1.7）：夾限到 1，落在書尾
  {
    const r = await openWith({ initialCfi: 'epubcfi(/6/40!/4/2)', initialProgression: 1.7 })
    const loc = lastLocation(r.events)
    report('E 比例 1.7：夾限後落在書尾（第 2 章）', loc !== null && loc.index === 2, JSON.stringify(loc))
  }
  // F. 元素路徑不存在：Foliate 自行落在該章節，不是失敗，不得誤報
  {
    const r = await openWith({ initialCfi: 'epubcfi(/6/4!/4/900/2)', initialProgression: 0.9 })
    report('F 元素不存在：落在第 1 章', lastLocation(r.events)?.index === 1, JSON.stringify(lastLocation(r.events)))
    report('F 元素不存在：不回報降級', degradedReasons(r.events).length === 0)
  }
  // H. 舊格式 Readium Locator JSON（Dart 端 extractCfi 無法解析，會原字串交給 JS）：
  //    JS 端必須判定無效並降級，不得把它當成 href 而落到別處
  {
    const legacy = '{"href":"c2.xhtml","locations":{"progression":0.3}}'
    const r = await openWith({ initialCfi: legacy, initialProgression: 0.8 })
    const loc = lastLocation(r.events)
    report('H 舊格式 JSON：改用進度比例定位（約 0.8）', loc !== null && Math.abs(loc.fraction - 0.8) < 0.15, JSON.stringify(loc))
    report('H 舊格式 JSON：回報一次 readingPosition 降級', JSON.stringify(degradedReasons(r.events)) === '["readingPosition"]')
  }
  // G. 沒有 initialCfi 的一般開書：不得觸發降級（迴歸）
  {
    const r = await openWith({ initialCfi: '', initialProgression: 0.9 })
    report('G 一般開書：開在書頭', lastLocation(r.events)?.index === 0, JSON.stringify(lastLocation(r.events)))
    report('G 一般開書：不回報降級', degradedReasons(r.events).length === 0)
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
