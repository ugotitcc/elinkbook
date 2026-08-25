import {
  launchHarnessPage, locateVisibleText, setDecorationsAt,
  resetHarnessEvents, harnessEvents, injectSelectionAtVisibleText, clearSelection, report,
} from './lib/harness.mjs'

function lastExistingAnnotationId(events) {
  const lastSelChanged = [...events].reverse().find((e) => e.name === 'onSelectionChanged')
  if (!lastSelChanged) return undefined
  return lastSelChanged.args[lastSelChanged.args.length - 1]
}

async function main() {
  const { browser, page } = await launchHarnessPage({
    fixtureFileName: 'sample.epub',
    writingMode: 'horizontal',
  })
  try {
    const target = await locateVisibleText(page, { minLength: 8 })
    if (!target) { report('找到可視文字節點', false); return }

    // 情境 A：選取範圍命中既有畫線，existingAnnotationId 應等於該畫線
    // 的 id。
    await setDecorationsAt(page, [{ id: 'existing-highlight', cfi: target.cfi, color: 'yellow', isUnderline: false }])
    await new Promise((r) => setTimeout(r, 200))
    await resetHarnessEvents(page)
    const injectedA = await injectSelectionAtVisibleText(page, { minLength: 8 })
    if (!injectedA) { report('注入選取範圍（情境 A）', false); return }
    await new Promise((r) => setTimeout(r, 300))
    const eventsA = await harnessEvents(page)
    const hitIdA = lastExistingAnnotationId(eventsA)
    report('選取命中既有畫線，existingAnnotationId 正確回報',
      hitIdA === 'existing-highlight', `實際值=${JSON.stringify(hitIdA)}`)

    // 情境 B（對照組）：清掉畫線後，同一段選取不該再命中任何東西。
    await setDecorationsAt(page, [])
    await new Promise((r) => setTimeout(r, 200))
    await clearSelection(page)
    await resetHarnessEvents(page)
    const injectedB = await injectSelectionAtVisibleText(page, { minLength: 8 })
    if (!injectedB) { report('注入選取範圍（情境 B）', false); return }
    await new Promise((r) => setTimeout(r, 300))
    const eventsB = await harnessEvents(page)
    const hitIdB = lastExistingAnnotationId(eventsB)
    report('畫線已刪除後，同段選取不再命中任何畫線',
      hitIdB === null, `實際值=${JSON.stringify(hitIdB)}`)
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
