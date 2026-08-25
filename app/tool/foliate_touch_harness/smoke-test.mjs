// 驗證 lib/harness.mjs 本身可用：能開頁、能找到可視文字、能注入選取、
// 能建立畫線並讀到 harness 事件。不測任何觸控攔截邏輯（那是其他情境
// 腳本的事），純粹是函式庫的健檢。

import {
  launchHarnessPage, locateVisibleText, injectSelectionAtVisibleText,
  selectionState, setDecorationsAt, harnessEvents, resetHarnessEvents, report,
} from './lib/harness.mjs'

async function main() {
  const { browser, page, pageErrors } = await launchHarnessPage({
    fixtureFileName: 'sample.epub',
    writingMode: 'horizontal',
  })
  try {
    report('頁面載入無 pageerror', pageErrors.length === 0, JSON.stringify(pageErrors))

    const target = await locateVisibleText(page, { minLength: 8 })
    report('找到可視文字節點並取得 CFI', !!target?.cfi, JSON.stringify(target))

    await setDecorationsAt(page, [{ id: 'smoke-highlight', cfi: target.cfi, color: 'yellow', isUnderline: false }])
    await resetHarnessEvents(page)

    const injected = await injectSelectionAtVisibleText(page, { minLength: 8 })
    report('成功注入選取範圍', injected === true)

    await new Promise((r) => setTimeout(r, 300))
    const state = await selectionState(page)
    report('選取狀態正確回報為非折疊', state.isCollapsed === false, JSON.stringify(state))

    const events = await harnessEvents(page)
    const hasSelChanged = events.some((e) => e.name === 'onSelectionChanged')
    report('onSelectionChanged bridge 事件有觸發', hasSelChanged, JSON.stringify(events.map((e) => e.name)))
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
